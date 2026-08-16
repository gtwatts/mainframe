#!/usr/bin/env python3
"""Build mainframe-mcp from a copy bound to one exact runtime archive."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import tomllib
import zipfile


SENTINEL = '__MAINFRAME_RUNTIME_INVENTORY_SHA256__'
MAX_INVENTORY_BYTES = 16 * 1024 * 1024
MAX_ARCHIVE_BYTES = 256 * 1024 * 1024
MAX_EXPANDED_BYTES = 512 * 1024 * 1024
MAX_MEMBERS = 10_000
MAX_TAR_STREAM_BYTES = MAX_EXPANDED_BYTES + (MAX_MEMBERS * 2048) + (1024 * 1024)
EXCLUDED_NAMES = {
    '.pytest_cache',
    '.ruff_cache',
    '.venv',
    '__pycache__',
    'dist',
}


def fail(message: str) -> None:
    raise SystemExit(f'build-mcp-package: {message}')


def require_regular(path: Path, label: str) -> Path:
    try:
        path_stat = path.lstat()
    except OSError as error:
        fail(f'{label} is unavailable: {error}')
    if not stat.S_ISREG(path_stat.st_mode):
        fail(f'{label} must be a regular non-symlink file: {path}')
    return path.resolve(strict=True)


class BoundedReader:
    """Refuse gzip expansion beyond the runtime archive contract."""

    def __init__(self, source: gzip.GzipFile, limit: int) -> None:
        self.source = source
        self.limit = limit
        self.consumed = 0

    def read(self, size: int = -1) -> bytes:
        remaining = self.limit - self.consumed
        request = remaining + 1 if size < 0 else min(size, remaining + 1)
        data = self.source.read(request)
        self.consumed += len(data)
        if self.consumed > self.limit:
            raise OSError('runtime archive tar stream exceeds the size limit')
        return data


def runtime_inventory_digest(archive_path: Path, expected_version: str) -> str:
    archive = require_regular(archive_path, 'runtime archive')
    if archive.stat().st_size > MAX_ARCHIVE_BYTES:
        fail('runtime archive exceeds the compressed size limit')
    inventory_data: bytes | None = None
    inventory_size = 0
    member_count = 0
    expanded_bytes = 0
    try:
        with archive.open('rb') as compressed:
            with gzip.GzipFile(fileobj=compressed, mode='rb') as uncompressed:
                bounded = BoundedReader(uncompressed, MAX_TAR_STREAM_BYTES)
                with tarfile.open(fileobj=bounded, mode='r|') as bundle:
                    for member in bundle:
                        member_count += 1
                        if member_count > MAX_MEMBERS:
                            fail('runtime archive has too many members')
                        relative = Path(member.name)
                        if (
                            not member.name
                            or member.name.startswith('/')
                            or '\\' in member.name
                            or any(ord(character) < 32 or ord(character) == 127 for character in member.name)
                            or '..' in relative.parts
                            or member.name.rstrip('/') != relative.as_posix()
                        ):
                            fail(f'runtime archive path is unsafe: {member.name}')
                        if not (member.isfile() or member.isdir()):
                            fail(f'runtime archive member type is unsafe: {member.name}')
                        if member.size < 0:
                            fail(f'runtime archive member size is invalid: {member.name}')
                        if member.isfile():
                            expanded_bytes += member.size
                            if expanded_bytes > MAX_EXPANDED_BYTES:
                                fail('runtime archive expands beyond the size limit')
                        if member.name != 'SHA256SUMS':
                            continue
                        if inventory_data is not None or not member.isfile():
                            fail('runtime archive must contain one regular root SHA256SUMS')
                        if member.size <= 0 or member.size > MAX_INVENTORY_BYTES:
                            fail('runtime SHA256SUMS size is invalid')
                        inventory_size = member.size
                        source = bundle.extractfile(member)
                        if source is None:
                            fail('runtime SHA256SUMS cannot be read')
                        try:
                            inventory_data = source.read(MAX_INVENTORY_BYTES + 1)
                        finally:
                            source.close()
    except (OSError, tarfile.TarError) as error:
        fail(f'runtime archive is invalid: {error}')
    if inventory_data is None:
        fail('runtime archive must contain exactly one root SHA256SUMS')
    if len(inventory_data) != inventory_size or len(inventory_data) > MAX_INVENTORY_BYTES:
        fail('runtime SHA256SUMS bytes do not match its declared size')
    try:
        lines = inventory_data.decode('ascii').splitlines()
    except UnicodeDecodeError:
        fail('runtime SHA256SUMS must be ASCII')
    if not lines or lines[0] != (
        f'# MAINFRAME {expected_version} release archive checksums'
    ):
        fail('runtime SHA256SUMS header does not match the package version')
    return hashlib.sha256(inventory_data).hexdigest()


def validate_source_tree(source: Path) -> Path:
    try:
        root = source.resolve(strict=True)
    except OSError as error:
        fail(f'package source is unavailable: {error}')
    if not root.is_dir() or root == root.parent:
        fail('package source must be a non-root directory')
    required = (
        root / 'pyproject.toml',
        root / 'src' / 'mainframe_mcp' / '_runtime_release.py',
    )
    for path in required:
        require_regular(path, 'package source input')
    return root


def reject_source_links(root: Path) -> None:
    for directory, names, files in os.walk(root, followlinks=False):
        base = Path(directory)
        names[:] = [name for name in names if name not in EXCLUDED_NAMES]
        for name in [*names, *files]:
            path = base / name
            if path.is_symlink():
                fail(f'package source contains a symbolic link: {path.relative_to(root)}')


def copy_source(source: Path, destination: Path) -> None:
    reject_source_links(source)
    shutil.copytree(
        source,
        destination,
        ignore=shutil.ignore_patterns(*sorted(EXCLUDED_NAMES)),
    )


def bind_source(source_copy: Path, digest: str) -> None:
    binding = source_copy / 'src' / 'mainframe_mcp' / '_runtime_release.py'
    text = binding.read_text(encoding='utf-8')
    if text.count(SENTINEL) != 1:
        fail('package source runtime-binding sentinel is missing or ambiguous')
    binding.write_text(text.replace(SENTINEL, digest), encoding='utf-8')


def package_version(source_copy: Path) -> str:
    document = tomllib.loads(
        (source_copy / 'pyproject.toml').read_text(encoding='utf-8')
    )
    version = document.get('project', {}).get('version')
    if not isinstance(version, str) or not re.fullmatch(
        r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version
    ):
        fail('package version is not stable SemVer')
    return version


def verify_artifacts(output: Path, version: str, digest: str) -> None:
    wheel = output / f'mainframe_mcp-{version}-py3-none-any.whl'
    sdist = output / f'mainframe_mcp-{version}.tar.gz'
    require_regular(wheel, 'built wheel')
    require_regular(sdist, 'built source distribution')
    wheel_binding_name = 'mainframe_mcp/_runtime_release.py'
    with zipfile.ZipFile(wheel) as package:
        wheel_binding = package.read(wheel_binding_name).decode('utf-8')
    with tarfile.open(sdist, 'r:gz') as package:
        member = package.getmember(
            f'mainframe_mcp-{version}/src/mainframe_mcp/_runtime_release.py'
        )
        source = package.extractfile(member)
        if source is None:
            fail('built source distribution binding cannot be read')
        sdist_binding = source.read().decode('utf-8')
    for label, content in (('wheel', wheel_binding), ('sdist', sdist_binding)):
        if digest not in content or SENTINEL in content:
            fail(f'built {label} does not contain the exact runtime binding')


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--runtime-archive', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--uv', default='uv')
    parser.add_argument('--offline', action='store_true')
    arguments = parser.parse_args()

    source = validate_source_tree(arguments.source)
    output = arguments.output_dir.absolute()
    if output.is_symlink() or (output.exists() and not output.is_dir()):
        fail('output path must be a non-symlink directory or absent')
    output.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix='mainframe-mcp-bound-source-') as temp:
        source_copy = Path(temp) / 'mcp'
        copy_source(source, source_copy)
        version = package_version(source_copy)
        digest = runtime_inventory_digest(arguments.runtime_archive, version)
        bind_source(source_copy, digest)
        command = [arguments.uv, 'build', '--no-sources']
        if arguments.offline:
            command.append('--offline')
        command.extend(['--out-dir', str(output), str(source_copy)])
        subprocess.run(command, check=True)
    verify_artifacts(output, version, digest)
    print(f'mainframe-mcp runtime inventory binding: {digest}')
    return 0


if __name__ == '__main__':
    sys.exit(main())

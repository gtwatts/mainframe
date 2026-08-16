#!/usr/bin/env python3
"""Authenticate and extract one pinned npm package without running package code."""

from __future__ import annotations

import argparse
import base64
import gzip
import hashlib
import hmac
import json
import os
import pathlib
import re
import stat
import sys
import tarfile
from typing import BinaryIO, NoReturn


MAX_ARCHIVE_BYTES = 512 * 1024 * 1024
MAX_MEMBERS = 10_000
MAX_MEMBER_BYTES = 512 * 1024 * 1024
MAX_EXPANDED_BYTES = 512 * 1024 * 1024
MAX_TAR_STREAM_BYTES = MAX_EXPANDED_BYTES + (MAX_MEMBERS * 2048) + (1024 * 1024)
MAX_PATH_BYTES = 4096
MAX_DEPTH = 64
CHUNK_BYTES = 1024 * 1024
SAFE_PATH = re.compile(r"^[A-Za-z0-9._@+ /-]+$")
SAFE_PACKAGE = re.compile(r"^(?:@[a-z0-9._-]+/)?[a-z0-9._-]+$")
SAFE_VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:[-.][A-Za-z0-9.-]+)?$")
SAFE_INTEGRITY = re.compile(r"^sha512-([A-Za-z0-9+/]+={0,2})$")


def die(message: str) -> NoReturn:
    raise SystemExit(f"managed package extraction failed: {message}")


class BoundedReader:
    """Expose read() while refusing gzip expansion beyond an exact cap."""

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
            raise OSError("npm tar stream exceeds the expanded size limit")
        return data


def stable_identity(metadata: os.stat_result) -> tuple[int, int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
        metadata.st_nlink,
    )


def open_archive(path: pathlib.Path) -> tuple[int, os.stat_result]:
    flags = os.O_RDONLY
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags)
    metadata = os.fstat(descriptor)
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
        os.close(descriptor)
        die("archive snapshot must be a single-link regular file")
    if metadata.st_size <= 0 or metadata.st_size > MAX_ARCHIVE_BYTES:
        os.close(descriptor)
        die("archive snapshot size is outside the supported bound")
    return descriptor, metadata


def verify_integrity(descriptor: int, expected: str) -> None:
    match = SAFE_INTEGRITY.fullmatch(expected)
    if match is None:
        die("expected npm integrity is malformed")
    try:
        decoded = base64.b64decode(match.group(1), validate=True)
    except ValueError as exc:
        die(f"expected npm integrity is malformed: {exc}")
    if len(decoded) != hashlib.sha512().digest_size:
        die("expected npm integrity is not a SHA-512 digest")

    os.lseek(descriptor, 0, os.SEEK_SET)
    digest = hashlib.sha512()
    while True:
        chunk = os.read(descriptor, CHUNK_BYTES)
        if not chunk:
            break
        digest.update(chunk)
    if not hmac.compare_digest(digest.digest(), decoded):
        die("archive SHA-512 SRI does not match the trusted package lock")
    os.lseek(descriptor, 0, os.SEEK_SET)


def safe_member_path(member: tarfile.TarInfo) -> tuple[str, ...]:
    if member.isdir() and member.name.endswith("//"):
        die(f"unsafe npm archive path: {member.name!r}")
    name = member.name[:-1] if member.isdir() and member.name.endswith("/") else member.name
    path = pathlib.PurePosixPath(name)
    if (
        not name
        or not SAFE_PATH.fullmatch(name)
        or path.is_absolute()
        or name != str(path)
        or len(name.encode("utf-8")) > MAX_PATH_BYTES
        or len(path.parts) > MAX_DEPTH
        or any(part in ("", ".", "..") or len(part.encode("utf-8")) > 255 for part in path.parts)
        or not path.parts
        or path.parts[0] != "package"
        or (len(path.parts) == 1 and not member.isdir())
    ):
        die(f"unsafe npm archive path: {member.name!r}")
    return path.parts[1:]


def open_directory_at(root_descriptor: int, parts: tuple[str, ...], create: bool) -> int:
    descriptor = os.dup(root_descriptor)
    flags = os.O_RDONLY
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        for part in parts:
            if create:
                try:
                    os.mkdir(part, 0o700, dir_fd=descriptor)
                except FileExistsError:
                    pass
            child = os.open(part, flags, dir_fd=descriptor)
            metadata = os.fstat(child)
            if not stat.S_ISDIR(metadata.st_mode):
                os.close(child)
                die(f"extraction parent is not a real directory: {'/'.join(parts)}")
            os.close(descriptor)
            descriptor = child
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def write_member(
    root_descriptor: int,
    parts: tuple[str, ...],
    member: tarfile.TarInfo,
    source: BinaryIO,
) -> None:
    parent = open_directory_at(root_descriptor, parts[:-1], create=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(parts[-1], flags, 0o600, dir_fd=parent)
    except BaseException:
        os.close(parent)
        raise

    remaining = member.size
    try:
        while remaining:
            chunk = source.read(min(CHUNK_BYTES, remaining))
            if not chunk:
                die(f"truncated npm archive member: {member.name}")
            view = memoryview(chunk)
            while view:
                written = os.write(descriptor, view)
                if written <= 0:
                    die(f"could not write npm archive member: {member.name}")
                view = view[written:]
            remaining -= len(chunk)
        if source.read(1):
            die(f"npm archive member exceeds its declared size: {member.name}")
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
        os.fsync(parent)
        os.close(parent)


def read_package_identity(root_descriptor: int) -> tuple[str, str]:
    flags = os.O_RDONLY
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open("package.json", flags, dir_fd=root_descriptor)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1 or metadata.st_size > 1024 * 1024:
            die("extracted package.json is missing or unsafe")
        with os.fdopen(os.dup(descriptor), "rb") as handle:
            value = json.load(handle)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        die(f"extracted package.json is malformed: {exc}")
    finally:
        os.close(descriptor)
    if not isinstance(value, dict) or not isinstance(value.get("name"), str) or not isinstance(value.get("version"), str):
        die("extracted package.json has no exact name and version")
    return value["name"], value["version"]


def extract(
    descriptor: int,
    destination: pathlib.Path,
    expected_name: str,
    expected_version: str,
    expected_destination_identity: str | None = None,
) -> None:
    root_flags = os.O_RDONLY
    if hasattr(os, "O_DIRECTORY"):
        root_flags |= os.O_DIRECTORY
    if hasattr(os, "O_CLOEXEC"):
        root_flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        root_flags |= os.O_NOFOLLOW
    root_descriptor = os.open(destination, root_flags)
    root_metadata = os.fstat(root_descriptor)
    if not stat.S_ISDIR(root_metadata.st_mode):
        os.close(root_descriptor)
        die("destination must be a real directory")
    if (
        expected_destination_identity is not None
        and f"{root_metadata.st_dev}:{root_metadata.st_ino}"
        != expected_destination_identity
    ):
        os.close(root_descriptor)
        die("destination identity changed before extraction")
    if os.listdir(root_descriptor):
        os.close(root_descriptor)
        die("destination must be empty")

    exact_names: set[str] = set()
    folded_spellings: dict[str, str] = {}
    member_count = 0
    expanded_bytes = 0
    os.lseek(descriptor, 0, os.SEEK_SET)
    duplicate = os.dup(descriptor)
    try:
        with os.fdopen(duplicate, "rb", closefd=True) as compressed:
            with gzip.GzipFile(fileobj=compressed, mode="rb") as uncompressed:
                bounded = BoundedReader(uncompressed, MAX_TAR_STREAM_BYTES)
                with tarfile.open(fileobj=bounded, mode="r|") as archive:
                    if archive.pax_headers:
                        die("global PAX metadata is not allowed")
                    for member in archive:
                        member_count += 1
                        if member_count > MAX_MEMBERS:
                            die("npm archive has too many members")
                        if member.pax_headers or member.linkname or member.issparse():
                            die(f"extended, linked, or sparse npm member is not allowed: {member.name}")
                        if not (member.isfile() or member.isdir()):
                            die(f"unsupported npm archive member type: {member.name}")
                        if member.size < 0 or member.size > MAX_MEMBER_BYTES:
                            die(f"npm archive member size is outside the supported bound: {member.name}")

                        parts = safe_member_path(member)
                        canonical = "/".join(parts)
                        if canonical in exact_names:
                            die(f"duplicate or case-colliding npm archive path: {member.name}")
                        exact_names.add(canonical)
                        for depth in range(1, len(parts) + 1):
                            prefix = "/".join(parts[:depth])
                            folded = prefix.casefold()
                            prior = folded_spellings.get(folded)
                            if prior is not None and prior != prefix:
                                die(
                                    "duplicate or case-colliding npm archive path: "
                                    f"{member.name}"
                                )
                            folded_spellings[folded] = prefix

                        if member.isdir():
                            directory = open_directory_at(root_descriptor, parts, create=True)
                            os.fsync(directory)
                            os.close(directory)
                            continue
                        expanded_bytes += member.size
                        if expanded_bytes > MAX_EXPANDED_BYTES:
                            die("npm archive expands beyond the supported size limit")
                        source = archive.extractfile(member)
                        if source is None:
                            die(f"npm archive member has no data: {member.name}")
                        try:
                            write_member(root_descriptor, parts, member, source)
                        finally:
                            source.close()

                trailing = bounded.read()
                if trailing and any(byte != 0 for byte in trailing):
                    die("npm archive contains non-padding data after the tar terminator")
    except (gzip.BadGzipFile, tarfile.TarError, EOFError, OSError) as exc:
        die(f"npm archive is malformed or unsafe: {exc}")

    if member_count == 0:
        die("npm archive is empty")
    actual_name, actual_version = read_package_identity(root_descriptor)
    if actual_name != expected_name or actual_version != expected_version:
        die(
            "package identity mismatch: "
            f"expected {expected_name}@{expected_version}, "
            f"found {actual_name}@{actual_version}"
        )
    os.fsync(root_descriptor)
    os.close(root_descriptor)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive")
    parser.add_argument("destination")
    parser.add_argument("integrity")
    parser.add_argument("package_name")
    parser.add_argument("package_version")
    return parser.parse_args()


def _main() -> None:
    args = parse_args()
    if SAFE_PACKAGE.fullmatch(args.package_name) is None:
        die("expected package name is malformed")
    if SAFE_VERSION.fullmatch(args.package_version) is None:
        die("expected package version is malformed")

    archive = pathlib.Path(args.archive)
    destination = pathlib.Path(args.destination)
    if archive.is_symlink() or not archive.is_file():
        die("archive snapshot must be a regular non-symlink file")
    if destination.is_symlink() or not destination.is_dir():
        die("destination must be a real non-symlink directory")

    descriptor, before = open_archive(archive)
    try:
        verify_integrity(descriptor, args.integrity)
        extract(descriptor, destination, args.package_name, args.package_version)
        after = os.fstat(descriptor)
        if stable_identity(before) != stable_identity(after):
            die("archive snapshot changed while it was authenticated and extracted")
    finally:
        os.close(descriptor)


def main() -> None:
    try:
        _main()
    except OSError as exc:
        die(exc.strerror or "operating-system file operation failed")


if __name__ == "__main__":
    main()

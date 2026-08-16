"""Read-only MAINFRAME runtime discovery and fail-closed identity validation."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import stat
from typing import Any, Optional

from ._version import __version__
from ._runtime_release import EXPECTED_RUNTIME_INVENTORY_SHA256


LEGACY_ROOT = '.mainframe'
MANAGED_LAUNCHER = '.local/bin/mainframe'
MAX_METADATA_BYTES = 16 * 1024 * 1024
STABLE_VERSION_RE = re.compile(r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')
SHA256_RE = re.compile(r'^[0-9a-f]{64}$')
UTC_TIMESTAMP_RE = re.compile(
    r'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
)
RECEIPT_NAME = '.mainframe-install-receipt.json'
CRITICAL_DIRECTORIES = ('bin', 'config', 'lib')
CRITICAL_FILES = (
    'VERSION',
    'FUNCTIONS.json',
    'MANIFEST.json',
    'SHA256SUMS',
    'bin/mainframe',
    'config/invocation-policy.json',
    'config/stable-core.json',
    'lib/common.sh',
    'lib/invoke.sh',
)


class RuntimeConfigurationError(RuntimeError):
    """Raised before MCP stdio when no coherent runtime can be selected."""


@dataclass(frozen=True)
class PathIdentity:
    relative_path: str
    device: int
    inode: int
    mode: int
    size: int
    modified_ns: int


@dataclass(frozen=True)
class RuntimeIdentity:
    """One validated runtime pinned for the complete MCP process lifetime."""

    root: Path
    version: str
    source: str
    integrity: str
    root_device: int
    root_inode: int
    critical_paths: tuple[PathIdentity, ...]
    functions_sha256: str
    manifest_sha256: str
    inventory_sha256: str

    def assert_current(self) -> None:
        """Reject a replaced or mutated runtime instead of mixing generations."""
        try:
            root_stat = self.root.stat()
        except OSError as error:
            raise RuntimeConfigurationError(
                'MAINFRAME runtime root disappeared after startup'
            ) from error
        if (root_stat.st_dev, root_stat.st_ino) != (
            self.root_device,
            self.root_inode,
        ):
            raise RuntimeConfigurationError(
                'MAINFRAME runtime root identity changed after startup'
            )

        for expected in self.critical_paths:
            path = self.root / expected.relative_path
            try:
                current = path.lstat()
            except OSError as error:
                raise RuntimeConfigurationError(
                    f'MAINFRAME runtime path disappeared: {expected.relative_path}'
                ) from error
            observed = (
                current.st_dev,
                current.st_ino,
                stat.S_IMODE(current.st_mode),
                current.st_size,
                current.st_mtime_ns,
            )
            pinned = (
                expected.device,
                expected.inode,
                expected.mode,
                expected.size,
                expected.modified_ns,
            )
            if observed != pinned:
                raise RuntimeConfigurationError(
                    f'MAINFRAME runtime path changed after startup: '
                    f'{expected.relative_path}'
                )


def _has_control_character(value: str) -> bool:
    return any(ord(character) < 32 or 127 <= ord(character) <= 159 for character in value)


def _mode_is_safe(path_stat: os.stat_result) -> bool:
    mode = stat.S_IMODE(path_stat.st_mode)
    return (
        path_stat.st_uid in {0, os.geteuid()}
        and not mode & 0o022
        and not mode & 0o7000
    )


def _safe_directory(path: Path) -> os.stat_result:
    try:
        path_stat = path.lstat()
    except OSError as error:
        raise RuntimeConfigurationError(
            f'MAINFRAME runtime directory is missing: {path}'
        ) from error
    if not stat.S_ISDIR(path_stat.st_mode) or not _mode_is_safe(path_stat):
        raise RuntimeConfigurationError(
            f'MAINFRAME runtime directory is unsafe: {path}'
        )
    return path_stat


def _safe_regular_file(path: Path, *, executable: bool = False) -> os.stat_result:
    try:
        path_stat = path.lstat()
    except OSError as error:
        raise RuntimeConfigurationError(
            f'MAINFRAME runtime file is missing: {path}'
        ) from error
    mode = stat.S_IMODE(path_stat.st_mode)
    if (
        not stat.S_ISREG(path_stat.st_mode)
        or not _mode_is_safe(path_stat)
        or executable and not mode & 0o100
    ):
        raise RuntimeConfigurationError(
            f'MAINFRAME runtime file is unsafe: {path}'
        )
    return path_stat


def _safe_inventory_file(
    root: Path, relative: str, *, executable: bool = False
) -> tuple[Path, os.stat_result]:
    """Reject symlinked or unsafe ancestors within a release inventory path."""
    if not _safe_inventory_relative_path(relative):
        raise RuntimeConfigurationError(
            f'MAINFRAME runtime inventory path is unsafe: {relative}'
        )
    current = root
    for component in Path(relative).parts[:-1]:
        current /= component
        _safe_directory(current)
    path = root / relative
    return path, _safe_regular_file(path, executable=executable)


def _account_home() -> Path:
    """Return the login account home without trusting the ambient HOME value."""
    import pwd

    try:
        raw_home = pwd.getpwuid(os.geteuid()).pw_dir
        home = Path(raw_home).resolve(strict=True)
    except (KeyError, OSError, RuntimeError) as error:
        raise RuntimeConfigurationError(
            'MAINFRAME runtime cannot resolve the account home'
        ) from error
    if not home.is_absolute() or not home.is_dir():
        raise RuntimeConfigurationError('MAINFRAME account home is invalid')
    return home


def _canonical_existing_root(raw_root: str) -> Path:
    if not isinstance(raw_root, str) or not raw_root or _has_control_character(raw_root):
        raise RuntimeConfigurationError('MAINFRAME runtime root is empty or malformed')
    expanded = Path(raw_root)
    if not expanded.is_absolute():
        raise RuntimeConfigurationError('MAINFRAME runtime root must be absolute')
    try:
        root = expanded.resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise RuntimeConfigurationError(
            f'MAINFRAME runtime root does not resolve: {expanded}'
        ) from error
    if root == root.parent or _has_control_character(str(root)):
        raise RuntimeConfigurationError('MAINFRAME runtime root is unsafe')
    _safe_directory(root)
    return root


def _safe_launcher_target() -> Optional[Path]:
    home = _account_home()
    launcher = home / MANAGED_LAUNCHER
    try:
        launcher_stat = launcher.lstat()
    except FileNotFoundError:
        return None
    except OSError as error:
        raise RuntimeConfigurationError(
            f'MAINFRAME managed launcher cannot be inspected: {launcher}'
        ) from error
    if (
        not stat.S_ISLNK(launcher_stat.st_mode)
        or launcher_stat.st_uid not in {0, os.geteuid()}
    ):
        raise RuntimeConfigurationError(
            f'MAINFRAME managed launcher is unsafe: {launcher}'
        )

    parent = launcher.parent
    while True:
        _safe_directory(parent)
        if parent == home:
            break
        if home not in parent.parents:
            raise RuntimeConfigurationError(
                'MAINFRAME managed launcher escapes the current home directory'
            )
        parent = parent.parent

    try:
        target = launcher.resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise RuntimeConfigurationError(
            f'MAINFRAME managed launcher target does not resolve: {launcher}'
        ) from error
    if target.name != 'mainframe' or target.parent.name != 'bin':
        raise RuntimeConfigurationError(
            'MAINFRAME managed launcher target has an invalid layout'
        )
    _safe_regular_file(target, executable=True)
    return target.parent.parent


def managed_install_root() -> Optional[str]:
    """Resolve the managed launcher without executing it."""
    target_root = _safe_launcher_target()
    return str(target_root) if target_root is not None else None


def _read_limited(path: Path) -> bytes:
    path_stat = _safe_regular_file(path)
    if path_stat.st_size > MAX_METADATA_BYTES:
        raise RuntimeConfigurationError(
            f'MAINFRAME metadata exceeds the size limit: {path.name}'
        )
    flags = os.O_RDONLY | getattr(os, 'O_CLOEXEC', 0) | getattr(os, 'O_NOFOLLOW', 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise RuntimeConfigurationError(
            f'MAINFRAME metadata cannot be read: {path.name}'
        ) from error
    try:
        opened_stat = os.fstat(descriptor)
        if (
            not stat.S_ISREG(opened_stat.st_mode)
            or (opened_stat.st_dev, opened_stat.st_ino)
            != (path_stat.st_dev, path_stat.st_ino)
            or not _mode_is_safe(opened_stat)
        ):
            raise RuntimeConfigurationError(
                f'MAINFRAME metadata changed while opening: {path.name}'
            )
        chunks: list[bytes] = []
        remaining = MAX_METADATA_BYTES + 1
        while remaining:
            chunk = os.read(descriptor, min(65_536, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        data = b''.join(chunks)
        if len(data) > MAX_METADATA_BYTES:
            raise RuntimeConfigurationError(
                f'MAINFRAME metadata exceeds the size limit: {path.name}'
            )
        return data
    finally:
        os.close(descriptor)


def _json_without_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'duplicate JSON field {key!r}')
        result[key] = value
    return result


def _read_json_object(path: Path) -> tuple[dict[str, Any], bytes]:
    data = _read_limited(path)
    try:
        document = json.loads(
            data.decode('utf-8'), object_pairs_hook=_json_without_duplicates
        )
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        raise RuntimeConfigurationError(
            f'MAINFRAME metadata is invalid JSON: {path.name}'
        ) from error
    if not isinstance(document, dict):
        raise RuntimeConfigurationError(
            f'MAINFRAME metadata must be an object: {path.name}'
        )
    return document, data


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path, expected_stat: os.stat_result) -> str:
    """Stream one already-authenticated regular file through SHA-256."""
    flags = os.O_RDONLY | getattr(os, 'O_CLOEXEC', 0) | getattr(os, 'O_NOFOLLOW', 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise RuntimeConfigurationError(
            f'MAINFRAME managed runtime file cannot be read: {path}'
        ) from error
    try:
        opened_stat = os.fstat(descriptor)
        if (
            not stat.S_ISREG(opened_stat.st_mode)
            or (opened_stat.st_dev, opened_stat.st_ino)
            != (expected_stat.st_dev, expected_stat.st_ino)
            or not _mode_is_safe(opened_stat)
        ):
            raise RuntimeConfigurationError(
                f'MAINFRAME managed runtime file changed while opening: {path}'
            )
        digest = hashlib.sha256()
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                return digest.hexdigest()
            digest.update(chunk)
    finally:
        os.close(descriptor)


def _safe_inventory_relative_path(value: str) -> bool:
    if (
        not value
        or value.startswith('/')
        or '\\' in value
        or _has_control_character(value)
    ):
        return False
    parts = Path(value).parts
    return bool(parts) and all(part not in {'', '.', '..'} for part in parts)


def _verify_checksum_inventory(
    root: Path, expected_version: str
) -> tuple[str, tuple[str, ...]]:
    inventory_path = root / 'SHA256SUMS'
    data = _read_limited(inventory_path)
    try:
        lines = data.decode('ascii').splitlines()
    except UnicodeDecodeError as error:
        raise RuntimeConfigurationError('MAINFRAME SHA256SUMS is not ASCII') from error
    if not lines or lines[0] != f'# MAINFRAME {expected_version} release archive checksums':
        raise RuntimeConfigurationError('MAINFRAME SHA256SUMS header is invalid')

    records: dict[str, str] = {}
    for line_number, line in enumerate(lines[1:], start=2):
        if not line:
            continue
        if len(line) < 67 or line[64:66] != '  ':
            raise RuntimeConfigurationError(
                f'MAINFRAME SHA256SUMS record is malformed at line {line_number}'
            )
        digest, relative = line[:64], line[66:]
        if (
            not SHA256_RE.fullmatch(digest)
            or not _safe_inventory_relative_path(relative)
            or relative in records
            or relative == 'SHA256SUMS'
        ):
            raise RuntimeConfigurationError(
                f'MAINFRAME SHA256SUMS record is unsafe at line {line_number}'
            )
        records[relative] = digest

    for required in CRITICAL_FILES:
        if required == 'SHA256SUMS':
            continue
        if required not in records:
            raise RuntimeConfigurationError(
                f'MAINFRAME SHA256SUMS omits required path: {required}'
            )

    for relative, expected_digest in records.items():
        path, path_stat = _safe_inventory_file(
            root, relative, executable=relative == 'bin/mainframe'
        )
        actual_digest = _sha256_file(path, path_stat)
        if actual_digest != expected_digest:
            raise RuntimeConfigurationError(
                f'MAINFRAME checksum mismatch: {relative}'
            )
    return _sha256(data), tuple(records)


def _validate_receipt(root: Path, version: str, inventory_sha256: str) -> None:
    receipt_path = root / RECEIPT_NAME
    if not receipt_path.exists() and not receipt_path.is_symlink():
        return
    receipt_stat = _safe_regular_file(receipt_path)
    if stat.S_IMODE(receipt_stat.st_mode) != 0o600:
        raise RuntimeConfigurationError('MAINFRAME release receipt mode must be 0600')
    receipt, _ = _read_json_object(receipt_path)
    expected_fields = {
        'archive_sha256',
        'bin_dir',
        'cli_link',
        'install_dir',
        'install_method',
        'installed_at',
        'manifest_sha256',
        'schema_version',
        'version',
    }
    if (
        set(receipt) != expected_fields
        or receipt.get('schema_version') != 1
        or receipt.get('install_method') != 'release-archive'
        or receipt.get('version') != version
        or receipt.get('install_dir') != str(root)
        or receipt.get('manifest_sha256') != inventory_sha256
        or not isinstance(receipt.get('archive_sha256'), str)
        or not SHA256_RE.fullmatch(receipt['archive_sha256'])
        or not isinstance(receipt.get('bin_dir'), str)
        or not os.path.isabs(receipt['bin_dir'])
        or _has_control_character(receipt['bin_dir'])
        or receipt.get('cli_link') != os.path.join(receipt['bin_dir'], 'mainframe')
        or not isinstance(receipt.get('installed_at'), str)
        or not UTC_TIMESTAMP_RE.fullmatch(receipt['installed_at'])
    ):
        raise RuntimeConfigurationError(
            'MAINFRAME release receipt does not match the selected runtime'
        )

    bin_dir = Path(receipt['bin_dir'])
    cli_link = Path(receipt['cli_link'])
    try:
        canonical_bin_dir = bin_dir.resolve(strict=True)
        link_stat = cli_link.lstat()
        link_target = cli_link.resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise RuntimeConfigurationError(
            'MAINFRAME release receipt paths do not resolve'
        ) from error
    if (
        canonical_bin_dir != bin_dir
        or not stat.S_ISLNK(link_stat.st_mode)
        or link_stat.st_uid not in {0, os.geteuid()}
        or link_target != root / 'bin' / 'mainframe'
    ):
        raise RuntimeConfigurationError(
            'MAINFRAME release receipt paths do not match the active runtime'
        )
    _safe_directory(canonical_bin_dir)


def _capture_path_identity(root: Path, relative: str) -> PathIdentity:
    path = root / relative
    path_stat = path.lstat()
    return PathIdentity(
        relative_path=relative,
        device=path_stat.st_dev,
        inode=path_stat.st_ino,
        mode=stat.S_IMODE(path_stat.st_mode),
        size=path_stat.st_size,
        modified_ns=path_stat.st_mtime_ns,
    )


def validate_runtime_root(
    raw_root: str,
    *,
    source: str,
    expected_version: str = __version__,
    allow_development_root: bool = False,
) -> RuntimeIdentity:
    """Validate one selected root without executing any runtime code."""
    if not STABLE_VERSION_RE.fullmatch(expected_version):
        raise RuntimeConfigurationError('MCP runner version is not stable SemVer')
    root = _canonical_existing_root(raw_root)
    for relative in CRITICAL_DIRECTORIES:
        _safe_directory(root / relative)
    for relative in CRITICAL_FILES:
        _safe_regular_file(
            root / relative, executable=relative == 'bin/mainframe'
        )

    version_bytes = _read_limited(root / 'VERSION')
    try:
        runtime_version = version_bytes.decode('ascii')
    except UnicodeDecodeError as error:
        raise RuntimeConfigurationError('MAINFRAME VERSION is not ASCII') from error
    if runtime_version.endswith('\n'):
        runtime_version = runtime_version[:-1]
    if (
        not STABLE_VERSION_RE.fullmatch(runtime_version)
        or runtime_version != expected_version
    ):
        raise RuntimeConfigurationError(
            f'MAINFRAME runtime version {runtime_version!r} does not match '
            f'MCP runner {expected_version!r}'
        )

    functions, functions_bytes = _read_json_object(root / 'FUNCTIONS.json')
    manifest, manifest_bytes = _read_json_object(root / 'MANIFEST.json')
    if functions.get('version') != expected_version:
        raise RuntimeConfigurationError(
            'FUNCTIONS.json version does not match the MCP runner'
        )
    if (
        manifest.get('manifest_version') != 1
        or manifest.get('version') != expected_version
    ):
        raise RuntimeConfigurationError(
            'MANIFEST.json version does not match the MCP runner'
        )

    if allow_development_root:
        if SHA256_RE.fullmatch(EXPECTED_RUNTIME_INVENTORY_SHA256):
            raise RuntimeConfigurationError(
                'a release-bound MCP package cannot use a development root'
            )
        integrity = 'explicit-development-root'
        inventory_bytes = _read_limited(root / 'SHA256SUMS')
        inventory_sha256 = _sha256(inventory_bytes)
        pinned_paths = CRITICAL_FILES
    else:
        if not SHA256_RE.fullmatch(EXPECTED_RUNTIME_INVENTORY_SHA256):
            raise RuntimeConfigurationError(
                'MAINFRAME MCP package has no release-runtime binding'
            )
        inventory_sha256, inventory_paths = _verify_checksum_inventory(
            root, expected_version
        )
        if inventory_sha256 != EXPECTED_RUNTIME_INVENTORY_SHA256:
            raise RuntimeConfigurationError(
                'MAINFRAME runtime does not match the MCP package release binding'
            )
        integrity = 'package-bound-sha256-inventory'
        pinned_paths = (*inventory_paths, 'SHA256SUMS')
    _validate_receipt(root, expected_version, inventory_sha256)

    root_stat = root.stat()
    return RuntimeIdentity(
        root=root,
        version=runtime_version,
        source=source,
        integrity=integrity,
        root_device=root_stat.st_dev,
        root_inode=root_stat.st_ino,
        critical_paths=tuple(
            _capture_path_identity(root, relative) for relative in pinned_paths
        ),
        functions_sha256=_sha256(functions_bytes),
        manifest_sha256=_sha256(manifest_bytes),
        inventory_sha256=inventory_sha256,
    )


def resolve_runtime_identity(
    explicit_root: Optional[str] = None,
    *,
    expected_version: str = __version__,
    allow_development_root: bool = False,
) -> RuntimeIdentity:
    """Select one root by strict precedence, then validate it atomically."""
    if allow_development_root and explicit_root is None:
        raise RuntimeConfigurationError(
            '--allow-development-root requires --mainframe-root'
        )

    if explicit_root is not None:
        raw_root = explicit_root
        source = 'command-line'
    else:
        managed_root = managed_install_root()
        if managed_root is not None:
            raw_root = managed_root
            source = 'managed-launcher'
        else:
            raw_root = str(_account_home() / LEGACY_ROOT)
            source = 'legacy-default'

    return validate_runtime_root(
        raw_root,
        source=source,
        expected_version=expected_version,
        allow_development_root=allow_development_root,
    )


def resolve_mainframe_root(explicit_root: Optional[str] = None) -> str:
    """Compatibility helper for low-level components and offline tooling.

    The public server uses :func:`resolve_runtime_identity`. An explicitly
    supplied component root is canonicalized but deliberately not treated as a
    public-server authorization decision.
    """
    configured = explicit_root
    if configured:
        return str(Path(configured).absolute())
    managed_root = managed_install_root()
    if managed_root is not None:
        return managed_root
    return str(_account_home() / LEGACY_ROOT)

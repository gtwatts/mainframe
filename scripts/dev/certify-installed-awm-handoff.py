#!/usr/bin/env python3
"""Certify one installed-candidate project-AWM handoff canary.

``run`` authenticates and installs an exact release archive in a private,
isolated HOME.  It then uses four fresh login-shell processes to exercise the
candidate's real project AWM, while the checked-in deterministic local-001
transport and grader provide a deliberately neutral 100/100 parity canary.

``verify`` is a read-only, subprocess-free reconstruction.  Neither action
starts Pi, Ollama, an agent, or a provider, and this program contains no socket
or network transport path.  The resulting claim is mechanism conformance only.
"""

from __future__ import annotations

import argparse
import ctypes
import datetime
import errno
import hashlib
import io
import json
import os
import platform
import re
import shlex
import signal
import stat
import struct
import subprocess
import sys
import tarfile
import zlib
from pathlib import Path, PurePosixPath
from typing import Any, Dict, Iterable, List, NoReturn, Optional, Sequence, Set, Tuple


CLAIM_SCOPE = "installed-candidate-awm-handoff-mechanism-conformance-only"
INSTALLED_PAYLOAD_STATUS = "authenticated-release-files-private-staging"
PUBLIC_KIND = "mainframe-installed-awm-handoff-evidence"
PRIVATE_KIND = "mainframe-installed-awm-handoff-private-record"
PACKAGE_TREE_ALGORITHM = "mainframe-package-tree-sha256-v1"
PRIVATE_TREE_ALGORITHM = "mainframe-agent-impact-private-tree-sha256-v1"
VERIFICATION_STATE_DOMAIN = b"MAINFRAME-INSTALLED-AWM-VERIFICATION-STATE-V1\0"
PACKAGE_TREE_DOMAIN = b"MAINFRAME-PACKAGE-TREE-SHA256-V1\0"
MAX_ARCHIVE_BYTES = 512 * 1024 * 1024
MAX_EXPANDED_BYTES = 1024 * 1024 * 1024
MAX_ARCHIVE_MEMBERS = 20000
MAX_JSON_BYTES = 16 * 1024 * 1024
MAX_OUTPUT_BYTES = 1024 * 1024
MAX_CONTINUATION_BYTES = 4096
PROCESS_TIMEOUT_SECONDS = 30.0
PROCESS_GROUP_GRACE_SECONDS = 0.25
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$")
SHELL_VERSION_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 ._+():,-]{0,255}$")
BASH_VERSION_RE = re.compile(
    r"^[0-9]+\.[0-9]+(?:\.[0-9]+)?\([0-9]+\)-[A-Za-z0-9._+-]+$")
WINDOWS_ABSOLUTE_RE = re.compile(r"^[A-Za-z]:[\\/]")
FILE_URI_RE = re.compile(r"^file://", re.IGNORECASE)
ARCHIVE_RE = re.compile(
    r"^mainframe-([0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?)\.tar\.gz$"
)
SESSION_RE = re.compile(r"^[0-9a-f]{12}$")
SOURCE_FACT = (
    "Merge dictionaries recursively. Apply defaults, project, then user; "
    "presence, not truthiness, controls precedence so False, 0, empty "
    "strings, empty lists, and None remain valid overrides."
)
DISCOVERY_FACT = (
    "local-001 requires preserving nested dictionary precedence and explicit "
    "falsy values"
)
EXPECTED_SOLUTION = (
    '"""Nested configuration merge used by the local development smoke."""\n\n\n'
    "def _merge(base: dict, overlay: dict) -> dict:\n"
    "    result = dict(base)\n"
    "    for key, value in overlay.items():\n"
    "        if isinstance(value, dict) and isinstance(result.get(key), dict):\n"
    "            result[key] = _merge(result[key], value)\n"
    "        else:\n"
    "            result[key] = value\n"
    "    return result\n\n\n"
    "def resolve_config(defaults: dict, project: dict, user: dict) -> dict:\n"
    "    return _merge(_merge(defaults, project), user)\n"
).encode("utf-8")
ALLOWED_TRANSPORT_ENVIRONMENT_NAMES = sorted([
    "CI", "HOME", "LANG", "LC_ALL", "LOGNAME", "MAINFRAME_LOCAL_PROTOCOL",
    "NO_COLOR", "PATH", "PYTHONDONTWRITEBYTECODE", "TMPDIR", "USER",
    "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME",
    "__CF_USER_TEXT_ENCODING",
])
PUBLIC_KEYS = (
    "schema_version", "kind", "claim_scope", "status", "candidate", "platform",
    "shell", "protocol", "mechanism", "parity", "integrity", "execution",
    "non_claims",
)
PRIVATE_KEYS = (
    "schema_version", "kind", "claim_scope", "candidate", "platform", "shell",
    "protocol", "processes", "mechanisms", "artifacts", "measurements",
    "execution", "public_projection_sha256",
)
PROTOCOL_RELATIVE_PATHS = {
    "certifier": "scripts/dev/certify-installed-awm-handoff.py",
    "private_schema": "evals/agent-impact/installed-awm-handoff-private.schema.json",
    "evidence_schema": "evals/agent-impact/installed-awm-handoff-evidence.schema.json",
    "neutral_continuation_schema": "evals/agent-impact/neutral-continuation.schema.json",
    "task_bundle": "evals/agent-impact/tasks/local-001",
    "fake_transport": "evals/agent-impact/runners/local-fake-transport.py",
    "grader": "evals/agent-impact/tasks/local-001/grade.py",
}
TASK_RELATIVE = "evals/agent-impact/tasks/local-001"


class CanaryError(RuntimeError):
    """A controlled, fail-closed certification refusal."""


def refuse(message: str) -> NoReturn:
    raise CanaryError(message)


def canonical_bytes(value: Any) -> bytes:
    try:
        return json.dumps(
            value, sort_keys=True, separators=(",", ":"), ensure_ascii=True,
            allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError) as error:
        refuse("value cannot be encoded as canonical JSON: {}".format(error))


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def exact_keys(value: Any, expected: Iterable[str], label: str) -> Dict[str, Any]:
    if not isinstance(value, dict):
        refuse("{} must be an object".format(label))
    expected_set = set(expected)
    actual_set = set(value)
    if actual_set != expected_set:
        refuse("{} keys differ (missing={}, extras={})".format(
            label, sorted(expected_set - actual_set), sorted(actual_set - expected_set)))
    return value


def require_string(value: Any, label: str,
                   pattern: Optional[re.Pattern] = None) -> str:
    if not isinstance(value, str) or not value:
        refuse("{} must be a non-empty string".format(label))
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        refuse("{} contains a control character".format(label))
    if pattern is not None and pattern.fullmatch(value) is None:
        refuse("{} has an unsupported value".format(label))
    return value


def require_digest(value: Any, label: str) -> str:
    return require_string(value, label, SHA256_RE)


def require_bash_version(value: Any, label: str) -> str:
    version = require_string(value, label, BASH_VERSION_RE)
    match = re.match(r"^([0-9]+)\.([0-9]+)", version)
    if match is None or (int(match.group(1)), int(match.group(2))) < (4, 4):
        refuse("{} must identify Bash 4.4+".format(label))
    return version


def reject_public_paths(value: Any, location: str = "public evidence") -> None:
    """Reject path-bearing keys and absolute/path-URI string values recursively."""
    if isinstance(value, dict):
        for key, child in value.items():
            lowered = key.lower()
            if lowered in ("path", "paths") or lowered.startswith("path_") or \
                    lowered.endswith(("_path", "_paths")):
                refuse("{} contains a path-bearing key".format(location))
            reject_public_paths(child, "{}.{}".format(location, key))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_public_paths(child, "{}[{}]".format(location, index))
    elif isinstance(value, str):
        if value.startswith(("/", "\\\\")) or WINDOWS_ABSOLUTE_RE.match(value) or \
                FILE_URI_RE.match(value):
            refuse("{} contains an absolute path or file URI".format(location))


def require_int(value: Any, expected: int, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value != expected:
        refuse("{} must equal {}".format(label, expected))
    return value


def require_bool(value: Any, expected: bool, label: str) -> bool:
    if not isinstance(value, bool) or value is not expected:
        refuse("{} must be {}".format(label, str(expected).lower()))
    return value


def reject_duplicate_pairs(pairs: List[Tuple[str, Any]]) -> Dict[str, Any]:
    value: Dict[str, Any] = {}
    for key, child in pairs:
        if key in value:
            refuse("JSON contains duplicate key {!r}".format(key))
        value[key] = child
    return value


def reject_nonfinite(value: str) -> NoReturn:
    refuse("JSON contains non-finite number {}".format(value))


def json_value_count(value: Any, depth: int = 0) -> int:
    if depth > 64:
        refuse("JSON nesting exceeds the depth ceiling")
    if isinstance(value, dict):
        if len(value) > 10000:
            refuse("JSON object exceeds the member ceiling")
        return 1 + sum(json_value_count(key, depth + 1) +
                       json_value_count(child, depth + 1)
                       for key, child in value.items())
    if isinstance(value, list):
        if len(value) > 10000:
            refuse("JSON array exceeds the item ceiling")
        return 1 + sum(json_value_count(child, depth + 1) for child in value)
    if isinstance(value, str) and len(value) > MAX_JSON_BYTES:
        refuse("JSON string exceeds the size ceiling")
    return 1


def parse_json(payload: bytes, label: str) -> Any:
    if len(payload) > MAX_JSON_BYTES:
        refuse("{} exceeds the JSON byte ceiling".format(label))
    try:
        value = json.loads(
            payload.decode("utf-8", errors="strict"),
            object_pairs_hook=reject_duplicate_pairs,
            parse_constant=reject_nonfinite,
        )
    except CanaryError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError) as error:
        refuse("{} is not strict UTF-8 JSON: {}".format(label, error))
    if json_value_count(value) > 100000:
        refuse("{} exceeds the JSON value ceiling".format(label))
    return value


def path_mode(metadata: os.stat_result) -> str:
    return format(stat.S_IMODE(metadata.st_mode), "04o")


def canonical_existing_path(path: Path, label: str) -> Path:
    text = str(path)
    if not path.is_absolute() or "\\" in text or "//" in text or \
            any(ord(character) < 32 or ord(character) == 127 for character in text):
        refuse("{} must be a normalized absolute path".format(label))
    try:
        resolved = path.resolve(strict=True)
    except OSError as error:
        refuse("{} is unavailable: {}".format(label, error))
    if str(resolved) != text:
        refuse("{} must already be canonical and contain no symbolic link".format(label))
    return resolved


def open_canonical_parent(path: Path, label: str) -> Tuple[int, str]:
    """Open an absolute parent chain component-by-component without symlinks."""
    text = str(path)
    if not path.is_absolute() or path.name in ("", ".", "..") or \
            "\\" in text or "//" in text or \
            any(ord(character) < 32 or ord(character) == 127 for character in text):
        refuse("{} must be a normalized absolute path".format(label))
    parts = path.parts
    flags = os.O_RDONLY
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(parts[0], flags)
    try:
        for component in parts[1:-1]:
            child = os.open(component, flags, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        return descriptor, parts[-1]
    except Exception:
        os.close(descriptor)
        raise


def object_identity(metadata: os.stat_result) -> Tuple[int, int, int, int]:
    """Return the stable identity fields used for admitted filesystem objects."""
    return (
        metadata.st_dev, metadata.st_ino, metadata.st_uid,
        stat.S_IMODE(metadata.st_mode),
    )


def require_same_object(observed: os.stat_result, expected: os.stat_result,
                        label: str) -> None:
    if object_identity(observed) != object_identity(expected):
        refuse("{} changed after admission".format(label))


def require_directory(path: Path, label: str, private: bool = False) -> Path:
    path = canonical_existing_path(path, label)
    metadata = path.lstat()
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        refuse("{} must be a real directory".format(label))
    if metadata.st_uid != os.geteuid():
        refuse("{} has an unexpected owner".format(label))
    if private and stat.S_IMODE(metadata.st_mode) & 0o077:
        refuse("{} must not grant group or other permissions".format(label))
    return path


def directory_open_flags() -> int:
    flags = os.O_RDONLY
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    return flags


def validate_owned_directory_metadata(metadata: os.stat_result, label: str,
                                      private: bool = False) -> None:
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode) or \
            metadata.st_uid != os.geteuid():
        refuse("{} must be a real current-user directory".format(label))
    if private and stat.S_IMODE(metadata.st_mode) & 0o077:
        refuse("{} must not grant group or other permissions".format(label))


def open_owned_directory(path: Path, label: str,
                         expected: Optional[os.stat_result] = None,
                         private: bool = False) -> Tuple[int, os.stat_result]:
    """Pin one canonical directory through its no-follow parent descriptor."""
    path = canonical_existing_path(path, label)
    parent_descriptor, basename = open_canonical_parent(path, label)
    try:
        before = os.stat(basename, dir_fd=parent_descriptor, follow_symlinks=False)
        validate_owned_directory_metadata(before, label, private)
        if expected is not None:
            require_same_object(before, expected, label)
        descriptor = os.open(
            basename, directory_open_flags(), dir_fd=parent_descriptor)
    except Exception:
        os.close(parent_descriptor)
        raise
    os.close(parent_descriptor)
    opened = os.fstat(descriptor)
    try:
        validate_owned_directory_metadata(opened, label, private)
        require_same_object(opened, before, label)
        if expected is not None:
            require_same_object(opened, expected, label)
    except Exception:
        os.close(descriptor)
        raise
    return descriptor, opened


def create_owned_directory_fd(path: Path, mode: int, label: str,
                              expected_parent: Optional[os.stat_result] = None
                              ) -> Tuple[int, os.stat_result]:
    """Create and pin one absent directory beneath its admitted parent."""
    parent_descriptor, basename = open_canonical_parent(path, label)
    admitted_parent = os.fstat(parent_descriptor)
    descriptor = -1
    try:
        validate_owned_directory_metadata(admitted_parent, "{} parent".format(label))
        if expected_parent is not None:
            require_same_object(
                admitted_parent, expected_parent, "{} parent".format(label))
        try:
            os.stat(basename, dir_fd=parent_descriptor, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            refuse("{} must be absent".format(label))
        os.mkdir(basename, 0o700, dir_fd=parent_descriptor)
        created_before = os.stat(
            basename, dir_fd=parent_descriptor, follow_symlinks=False)
        descriptor = os.open(
            basename, directory_open_flags(), dir_fd=parent_descriptor)
        opened = os.fstat(descriptor)
        validate_owned_directory_metadata(opened, label, private=True)
        require_same_object(opened, created_before, label)
        if path_mode(opened) != "0700" or os.listdir(descriptor):
            refuse("{} changed before its created directory was pinned".format(label))
        created = os.fstat(descriptor)
        validate_owned_directory_metadata(created, label, private=True)
        if mode != 0o700:
            refuse("{} must use the owner-private directory mode".format(label))
        current = os.stat(basename, dir_fd=parent_descriptor, follow_symlinks=False)
        require_same_object(current, created, label)
    except Exception:
        os.close(parent_descriptor)
        if descriptor >= 0:
            os.close(descriptor)
        raise
    os.close(parent_descriptor)
    try:
        reopened_parent, reopened_basename = open_canonical_parent(path, label)
        try:
            require_same_object(
                os.fstat(reopened_parent), admitted_parent,
                "{} parent".format(label))
            reopened = os.stat(
                reopened_basename, dir_fd=reopened_parent, follow_symlinks=False)
            require_same_object(reopened, created, label)
        finally:
            os.close(reopened_parent)
    except Exception:
        os.close(descriptor)
        raise
    return descriptor, created


def create_owned_directory(path: Path, mode: int, label: str,
                           expected_parent: Optional[os.stat_result] = None
                           ) -> os.stat_result:
    descriptor, created = create_owned_directory_fd(
        path, mode, label, expected_parent)
    os.close(descriptor)
    return created


def require_directory_path_identity(path: Path, expected: os.stat_result,
                                    label: str, private: bool = False) -> None:
    descriptor, _ = open_owned_directory(path, label, expected, private)
    os.close(descriptor)


def open_regular(path: Path, label: str, maximum: int = MAX_ARCHIVE_BYTES,
                 expected_mode: Optional[str] = None) -> Tuple[int, os.stat_result]:
    path = canonical_existing_path(path, label)
    parent_descriptor, basename = open_canonical_parent(path, label)
    try:
        before = os.stat(basename, dir_fd=parent_descriptor, follow_symlinks=False)
    except Exception:
        os.close(parent_descriptor)
        raise
    if not stat.S_ISREG(before.st_mode) or stat.S_ISLNK(before.st_mode) or \
            before.st_nlink != 1 or before.st_uid not in (0, os.geteuid()):
        refuse("{} must be a trusted-owner, single-link regular file".format(label))
    if before.st_size < 0 or before.st_size > maximum:
        refuse("{} has an unsupported size".format(label))
    if expected_mode is not None and path_mode(before) != expected_mode:
        refuse("{} mode must be {}".format(label, expected_mode))
    flags = os.O_RDONLY
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    if hasattr(os, "O_NONBLOCK"):
        # Refuse a pathname-race replacement with a FIFO/device without ever
        # waiting for a peer or triggering blocking device semantics.
        flags |= os.O_NONBLOCK
    try:
        descriptor = os.open(basename, flags, dir_fd=parent_descriptor)
    except OSError as error:
        os.close(parent_descriptor)
        refuse("{} cannot be opened safely: {}".format(label, error))
    os.close(parent_descriptor)
    opened = os.fstat(descriptor)
    if not stat.S_ISREG(opened.st_mode) or opened.st_nlink != 1 or \
            opened.st_uid not in (0, os.geteuid()) or \
            opened.st_size < 0 or opened.st_size > maximum or \
            (expected_mode is not None and path_mode(opened) != expected_mode):
        os.close(descriptor)
        refuse("{} changed to an unsafe opened object".format(label))
    if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != \
            (opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns):
        os.close(descriptor)
        refuse("{} changed before it was opened".format(label))
    return descriptor, opened


def read_regular(path: Path, label: str, maximum: int = MAX_ARCHIVE_BYTES,
                 expected_mode: Optional[str] = None) -> Tuple[bytes, os.stat_result]:
    descriptor, before = open_regular(path, label, maximum, expected_mode)
    try:
        chunks = []
        remaining = before.st_size
        while remaining:
            chunk = os.read(descriptor, min(1024 * 1024, remaining))
            if not chunk:
                refuse("{} was truncated while read".format(label))
            chunks.append(chunk)
            remaining -= len(chunk)
        after = os.fstat(descriptor)
        if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != \
                (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns):
            refuse("{} changed while it was read".format(label))
        return b"".join(chunks), before
    finally:
        os.close(descriptor)


def read_bound_file(path: Path, label: str, maximum: int = MAX_ARCHIVE_BYTES,
                    expected_mode: Optional[str] = None) -> Dict[str, Any]:
    """Read once and derive semantic bytes plus their binding from one FD."""
    path = canonical_existing_path(path, label)
    payload, metadata = read_regular(path, label, maximum, expected_mode)
    return {
        "path": path,
        "payload": payload,
        "metadata": metadata,
        "binding": {
            "path": str(path), "type": "file", "mode": path_mode(metadata),
            "size_bytes": len(payload), "sha256": sha256_bytes(payload),
        },
    }


def parse_bound_json(observed: Dict[str, Any], label: str) -> Any:
    return parse_json(observed["payload"], label)


def decode_bound_text(observed: Dict[str, Any], label: str) -> str:
    try:
        return observed["payload"].decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        refuse("{} is not UTF-8: {}".format(label, error))


def file_binding(path: Path, label: str, maximum: int = MAX_ARCHIVE_BYTES,
                 expected_mode: Optional[str] = None) -> Dict[str, Any]:
    return read_bound_file(path, label, maximum, expected_mode)["binding"]


def validate_file_binding(value: Any, label: str,
                          maximum: int = MAX_ARCHIVE_BYTES) -> Path:
    return validate_bound_file(value, label, maximum)["path"]


def validate_bound_file(value: Any, label: str,
                        maximum: int = MAX_ARCHIVE_BYTES) -> Dict[str, Any]:
    """Validate a caller binding and return the exact authenticated bytes."""
    binding = exact_keys(value, ("path", "type", "mode", "size_bytes", "sha256"), label)
    if binding["type"] != "file":
        refuse("{} type must be file".format(label))
    require_string(binding["mode"], "{} mode".format(label), re.compile(r"^0[0-7]{3}$"))
    if isinstance(binding["size_bytes"], bool) or not isinstance(binding["size_bytes"], int) or \
            not 0 <= binding["size_bytes"] <= maximum:
        refuse("{} size is invalid".format(label))
    require_digest(binding["sha256"], "{} digest".format(label))
    path = canonical_existing_path(Path(require_string(binding["path"], "{} path".format(label))),
                                   "{} path".format(label))
    observed = read_bound_file(path, label, maximum)
    if observed["binding"] != binding:
        refuse("{} no longer matches its file binding".format(label))
    return observed


def write_new(path: Path, payload: bytes, mode: int, label: str,
              expected_parent: Optional[os.stat_result] = None) -> None:
    parent = require_directory(path.parent.resolve(strict=True), "{} parent".format(label))
    admitted_parent = parent.lstat()
    if expected_parent is not None:
        require_same_object(admitted_parent, expected_parent,
                            "{} output parent".format(label))
    target = parent / path.name
    if target.exists() or target.is_symlink():
        refuse("refusing to overwrite existing {}: {}".format(label, target))
    parent_descriptor, basename = open_canonical_parent(target, "{} output".format(label))
    try:
        require_same_object(os.fstat(parent_descriptor), admitted_parent,
                            "{} output parent".format(label))
    except Exception:
        os.close(parent_descriptor)
        raise
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(basename, flags, mode, dir_fd=parent_descriptor)
    except Exception:
        os.close(parent_descriptor)
        raise
    try:
        offset = 0
        while offset < len(payload):
            offset += os.write(descriptor, payload[offset:])
        os.fsync(descriptor)
        os.fchmod(descriptor, mode)
        created = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    try:
        current = os.stat(basename, dir_fd=parent_descriptor, follow_symlinks=False)
        if not stat.S_ISREG(current.st_mode) or current.st_nlink != 1 or \
                current.st_uid != os.geteuid() or path_mode(current) != format(mode, "04o") or \
                current.st_size != len(payload):
            refuse("{} output changed after creation".format(label))
        require_same_object(current, created, "{} output".format(label))
        reopened_parent, reopened_basename = open_canonical_parent(
            target, "{} output".format(label))
        try:
            require_same_object(os.fstat(reopened_parent), admitted_parent,
                                "{} output parent".format(label))
            reopened = os.stat(
                reopened_basename, dir_fd=reopened_parent, follow_symlinks=False)
            require_same_object(reopened, created, "{} output".format(label))
        finally:
            os.close(reopened_parent)
    finally:
        os.close(parent_descriptor)


def create_new_descriptor(path: Path, mode: int, label: str,
                          expected_parent: os.stat_result) -> int:
    """Create one absent file beneath the exact parent admitted earlier."""
    parent_descriptor, basename = open_canonical_parent(path, label)
    try:
        require_same_object(os.fstat(parent_descriptor), expected_parent,
                            "{} parent".format(label))
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        if hasattr(os, "O_CLOEXEC"):
            flags |= os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = os.open(basename, flags, mode, dir_fd=parent_descriptor)
        opened = os.fstat(descriptor)
        if not stat.S_ISREG(opened.st_mode) or opened.st_nlink != 1 or \
                opened.st_uid != os.geteuid():
            os.close(descriptor)
            refuse("{} changed to an unsafe created object".format(label))
        return descriptor
    finally:
        os.close(parent_descriptor)


def create_owned_symlink(path: Path, target: str, label: str,
                         expected_parent: os.stat_result) -> os.stat_result:
    """Create one exact symlink beneath an admitted directory descriptor."""
    parent_descriptor, basename = open_canonical_parent(path, label)
    try:
        require_same_object(
            os.fstat(parent_descriptor), expected_parent,
            "{} parent".format(label))
        try:
            os.stat(basename, dir_fd=parent_descriptor, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            refuse("{} must be absent".format(label))
        os.symlink(target, basename, dir_fd=parent_descriptor)
        created = os.stat(basename, dir_fd=parent_descriptor, follow_symlinks=False)
        if not stat.S_ISLNK(created.st_mode) or created.st_uid != os.geteuid() or \
                os.readlink(basename, dir_fd=parent_descriptor) != target:
            refuse("{} changed during creation".format(label))
    finally:
        os.close(parent_descriptor)
    reopened_parent, reopened_basename = open_canonical_parent(path, label)
    try:
        require_same_object(
            os.fstat(reopened_parent), expected_parent,
            "{} parent".format(label))
        reopened = os.stat(
            reopened_basename, dir_fd=reopened_parent, follow_symlinks=False)
        require_same_object(reopened, created, label)
        if os.readlink(reopened_basename, dir_fd=reopened_parent) != target:
            refuse("{} target changed after creation".format(label))
    finally:
        os.close(reopened_parent)
    return created


def write_json(path: Path, value: Any, mode: int, label: str,
               expected_parent: Optional[os.stat_result] = None) -> None:
    write_new(
        path, canonical_bytes(value) + b"\n", mode, label, expected_parent)


def load_json_file(path: Path, label: str, expected_mode: Optional[str] = None) -> Any:
    payload, _ = read_regular(path, label, MAX_JSON_BYTES, expected_mode)
    return parse_json(payload, label)


def safe_member_name(member: tarfile.TarInfo) -> str:
    name = member.name.rstrip("/") if member.isdir() else member.name
    path = PurePosixPath(name)
    if not name or path.is_absolute() or "\\" in name or \
            any(part in ("", ".", "..") for part in path.parts) or \
            path.as_posix() != name or \
            any(ord(character) < 32 or ord(character) == 127 for character in name):
        refuse("release archive contains unsafe member path {!r}".format(member.name))
    return name


def archive_inventory(archive: Path,
                      destination: Optional[Path] = None,
                      expected_binding: Optional[Dict[str, Any]] = None,
                      destination_identity: Optional[os.stat_result] = None,
                      ) -> Dict[str, Dict[str, Any]]:
    """Authenticate, inspect, and optionally extract one exact archive image.

    Extraction is rooted in a retained directory descriptor.  Renaming or
    replacing any selected pathname cannot redirect writes through a symlink;
    a final lexical identity check turns such a race into a refusal.
    """
    archive = canonical_existing_path(archive, "release archive")
    descriptor, metadata = open_regular(archive, "release archive", MAX_ARCHIVE_BYTES)
    extraction_descriptor = -1
    extraction_metadata: Optional[os.stat_result] = None
    directory_descriptors: Dict[Tuple[str, ...], int] = {}
    if destination is not None:
        try:
            extraction_descriptor, extraction_metadata = open_owned_directory(
                destination, "release extraction root", destination_identity, private=True)
            if os.listdir(extraction_descriptor):
                refuse("release extraction root must begin empty")
            directory_descriptors[()] = extraction_descriptor
        except Exception:
            os.close(descriptor)
            raise
    inventory: Dict[str, Dict[str, Any]] = {}
    expanded = 0

    def archive_directory(parts: Tuple[str, ...]) -> int:
        current: Tuple[str, ...] = ()
        for component in parts:
            child_key = current + (component,)
            if child_key in directory_descriptors:
                current = child_key
                continue
            parent_fd = directory_descriptors[current]
            created_new = False
            try:
                before = os.stat(component, dir_fd=parent_fd, follow_symlinks=False)
            except FileNotFoundError:
                os.mkdir(component, 0o700, dir_fd=parent_fd)
                created_new = True
                before = os.stat(component, dir_fd=parent_fd, follow_symlinks=False)
            validate_owned_directory_metadata(
                before, "release extraction directory {}".format("/".join(child_key)))
            child_fd = os.open(component, directory_open_flags(), dir_fd=parent_fd)
            opened = os.fstat(child_fd)
            try:
                validate_owned_directory_metadata(
                    opened, "release extraction directory {}".format("/".join(child_key)))
                require_same_object(
                    opened, before,
                    "release extraction directory {}".format("/".join(child_key)))
                if created_new and (path_mode(opened) != "0700" or os.listdir(child_fd)):
                    refuse("release extraction directory changed before it was pinned")
            except Exception:
                os.close(child_fd)
                raise
            directory_descriptors[child_key] = child_fd
            current = child_key
        return directory_descriptors[current]

    try:
        # Authenticate the exact still-open archive descriptor before parsing
        # it. Parsing and hashing both consume this one immutable byte image.
        raw_chunks = []
        remaining_raw = metadata.st_size
        while remaining_raw:
            chunk = os.read(descriptor, min(1024 * 1024, remaining_raw))
            if not chunk:
                refuse("release archive was truncated while authenticated")
            raw_chunks.append(chunk)
            remaining_raw -= len(chunk)
        raw_payload = b"".join(raw_chunks)
        authenticated_binding = {
            "path": str(archive), "type": "file", "mode": path_mode(metadata),
            "size_bytes": len(raw_payload), "sha256": sha256_bytes(raw_payload),
        }
        if expected_binding is not None and authenticated_binding != expected_binding:
            refuse("release archive changed between binding and inspection")

        decompressor = zlib.decompressobj(16 + zlib.MAX_WBITS)
        uncompressed_payload = decompressor.decompress(
            raw_payload, MAX_EXPANDED_BYTES + 1)
        if decompressor.unconsumed_tail or len(uncompressed_payload) > MAX_EXPANDED_BYTES:
            refuse("release archive exceeds the expanded-byte ceiling")
        uncompressed_payload += decompressor.flush()
        if len(uncompressed_payload) > MAX_EXPANDED_BYTES:
            refuse("release archive exceeds the expanded-byte ceiling")
        if not decompressor.eof or decompressor.unused_data:
            refuse("release archive has trailing or concatenated gzip data")

        with io.BytesIO(uncompressed_payload) as raw_tar:
            with tarfile.open(fileobj=raw_tar, mode="r:") as payload:
                members = payload.getmembers()
                if len(members) > MAX_ARCHIVE_MEMBERS:
                    refuse("release archive exceeds the member ceiling")
                tar_payload_end = payload.offset
                trailing_tar = uncompressed_payload[tar_payload_end:]
                if len(trailing_tar) < 1024 or len(trailing_tar) % 512 != 0 or \
                        any(trailing_tar):
                    refuse("release archive has non-canonical trailing tar data")
                for member in members:
                    name = safe_member_name(member)
                    if name in inventory:
                        refuse("release archive contains duplicate member {}".format(name))
                    if not (member.isfile() or member.isdir()):
                        refuse("release archive contains link or special member {}".format(name))
                    mode = member.mode & 0o7777
                    if mode not in ({0o644, 0o755} if member.isfile() else {0o755}):
                        refuse("release archive member {} has unsupported mode".format(name))
                    parts = tuple(PurePosixPath(name).parts)
                    if member.isdir():
                        inventory[name] = {
                            "type": "directory", "mode": format(mode, "04o")}
                        if destination is not None:
                            archive_directory(parts)
                        continue
                    expanded += member.size
                    if member.size < 0 or expanded > MAX_EXPANDED_BYTES:
                        refuse("release archive exceeds the expanded-byte ceiling")
                    source = payload.extractfile(member)
                    if source is None:
                        refuse("release archive member {} cannot be read".format(name))
                    digest = hashlib.sha256()
                    remaining = member.size
                    output_fd = -1
                    output_parent = -1
                    try:
                        if destination is not None:
                            output_parent = archive_directory(parts[:-1])
                            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
                            if hasattr(os, "O_CLOEXEC"):
                                flags |= os.O_CLOEXEC
                            if hasattr(os, "O_NOFOLLOW"):
                                flags |= os.O_NOFOLLOW
                            output_fd = os.open(
                                parts[-1], flags, 0o600, dir_fd=output_parent)
                        while remaining:
                            chunk = source.read(min(1024 * 1024, remaining))
                            if not chunk:
                                refuse("release archive member {} is truncated".format(name))
                            digest.update(chunk)
                            if output_fd >= 0:
                                view = memoryview(chunk)
                                while view:
                                    written = os.write(output_fd, view)
                                    if written <= 0:
                                        refuse("release archive member {} could not be written".format(name))
                                    view = view[written:]
                            remaining -= len(chunk)
                        if output_fd >= 0:
                            os.fchmod(output_fd, mode)
                            os.fsync(output_fd)
                            created = os.fstat(output_fd)
                            if not stat.S_ISREG(created.st_mode) or created.st_nlink != 1 or \
                                    created.st_uid != os.geteuid() or \
                                    created.st_size != member.size or \
                                    path_mode(created) != format(mode, "04o"):
                                refuse("release archive member {} changed during creation".format(name))
                            current = os.stat(
                                parts[-1], dir_fd=output_parent, follow_symlinks=False)
                            require_same_object(
                                current, created, "release archive member {}".format(name))
                    finally:
                        source.close()
                        if output_fd >= 0:
                            os.close(output_fd)
                    inventory[name] = {
                        "type": "file", "mode": format(mode, "04o"),
                        "size_bytes": member.size, "sha256": digest.hexdigest(),
                    }
        after = os.fstat(descriptor)
        if (metadata.st_dev, metadata.st_ino, metadata.st_size, metadata.st_mtime_ns) != \
                (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns):
            refuse("release archive changed while inspected")
        if destination is not None and extraction_metadata is not None:
            require_directory_path_identity(
                destination, extraction_metadata,
                "release extraction root", private=True)
    except CanaryError:
        raise
    except (OSError, EOFError, tarfile.TarError, zlib.error) as error:
        refuse("release archive is invalid: {}".format(error))
    finally:
        for key, child_fd in sorted(
                directory_descriptors.items(), key=lambda item: len(item[0]), reverse=True):
            if child_fd >= 0:
                os.close(child_fd)
        os.close(descriptor)
    if not inventory:
        refuse("release archive is empty")
    return inventory


def parse_checksum(archive: Path, checksum: Path) -> Tuple[str, Dict[str, Any], Dict[str, Any]]:
    archive = canonical_existing_path(archive, "release archive")
    checksum = canonical_existing_path(checksum, "release checksum")
    archive_binding = file_binding(archive, "release archive", MAX_ARCHIVE_BYTES)
    payload, checksum_metadata = read_regular(checksum, "release checksum", 4096)
    checksum_binding = {
        "path": str(checksum), "type": "file", "mode": path_mode(checksum_metadata),
        "size_bytes": len(payload), "sha256": sha256_bytes(payload),
    }
    try:
        line = payload.decode("ascii", errors="strict")
    except UnicodeDecodeError as error:
        refuse("release checksum is not ASCII: {}".format(error))
    expected = "{}  {}\n".format(archive_binding["sha256"], archive.name)
    if line != expected:
        refuse("release checksum must be the canonical record for the selected archive")
    match = ARCHIVE_RE.fullmatch(archive.name)
    if match is None:
        refuse("release archive name must be mainframe-VERSION.tar.gz")
    return match.group(1), archive_binding, checksum_binding


def walk_tree(root: Path, label: str) -> List[Tuple[str, str, Path, os.stat_result]]:
    root = require_directory(root, label)
    found: List[Tuple[str, str, Path, os.stat_result]] = []
    for current_text, directory_names, file_names in os.walk(
            str(root), topdown=True, followlinks=False):
        directory_names.sort()
        file_names.sort()
        current = Path(current_text)
        for name in directory_names + file_names:
            path = current / name
            metadata = path.lstat()
            relative = path.relative_to(root).as_posix()
            if any(ord(character) < 32 or ord(character) == 127 for character in relative):
                refuse("{} contains a control character in a path".format(label))
            if stat.S_ISLNK(metadata.st_mode):
                refuse("{} contains a symbolic link: {}".format(label, relative))
            if stat.S_ISDIR(metadata.st_mode):
                kind = "directory"
            elif stat.S_ISREG(metadata.st_mode) and metadata.st_nlink == 1:
                kind = "file"
            else:
                refuse("{} contains a special or hard-linked entry: {}".format(label, relative))
            if metadata.st_uid != os.geteuid():
                refuse("{} contains an entry with an unexpected owner: {}".format(label, relative))
            found.append((relative, kind, path, metadata))
    found.sort(key=lambda item: item[0].encode("utf-8"))
    return found


def package_tree_sha256(root: Path) -> str:
    digest = hashlib.sha256(PACKAGE_TREE_DOMAIN)
    for relative, kind, path, metadata in walk_tree(root, "installed MAINFRAME tree"):
        encoded = relative.encode("utf-8")
        if kind == "directory":
            digest.update(b"D\0" + encoded + b"\0")
        else:
            payload, opened = read_regular(path, "installed file {}".format(relative),
                                           MAX_EXPANDED_BYTES)
            if opened.st_size != metadata.st_size:
                refuse("installed file changed while hashing: {}".format(relative))
            digest.update(b"F\0" + encoded + b"\0")
            digest.update(str(len(payload)).encode("ascii") + b"\0")
            digest.update(payload)
    return digest.hexdigest()


def private_tree_sha256(root: Path) -> str:
    return private_tree_snapshot(root)["sha256"]


def private_tree_snapshot(root: Path) -> Dict[str, Any]:
    """Capture one tree digest and all file bytes from the same bounded walk."""
    records = []
    entries: Dict[str, Dict[str, Any]] = {}
    for relative, kind, path, metadata in walk_tree(root, "private evidence tree"):
        record: Dict[str, Any] = {
            "path": relative, "type": kind, "mode": path_mode(metadata),
        }
        entry: Dict[str, Any] = {"type": kind, "mode": path_mode(metadata)}
        if kind == "file":
            observed = read_bound_file(
                path, "private tree file {}".format(relative), MAX_EXPANDED_BYTES)
            payload = observed["payload"]
            record.update({"size_bytes": len(payload), "sha256": sha256_bytes(payload)})
            entry["payload"] = payload
        records.append(record)
        entries[relative] = entry
    return {
        "root": require_directory(root, "private evidence tree"),
        "sha256": sha256_bytes(canonical_bytes(records)),
        "entries": entries,
    }


def verification_state_sha256(root: Path) -> str:
    """Hash the complete private state, admitting only its exact CLI symlink."""
    root = require_directory(root, "verification state root", private=True)
    expected_link = "home/.local/bin/mainframe"
    expected_target = str(root / "home" / "mainframe-install" / "bin" / "mainframe")
    records = []
    entries = 0
    total_bytes = 0
    for current_text, directory_names, file_names in os.walk(
            str(root), topdown=True, followlinks=False):
        directory_names.sort()
        file_names.sort()
        current = Path(current_text)
        for name in directory_names + file_names:
            path = current / name
            metadata = path.lstat()
            relative = path.relative_to(root).as_posix()
            entries += 1
            if entries > MAX_ARCHIVE_MEMBERS:
                refuse("verification state exceeds the entry ceiling")
            record: Dict[str, Any] = {
                "path": relative, "mode": path_mode(metadata),
            }
            if stat.S_ISLNK(metadata.st_mode):
                target = os.readlink(str(path))
                if relative != expected_link or target != expected_target:
                    refuse("verification state contains an unexpected symbolic link")
                record.update({"type": "symlink", "target": target})
            elif stat.S_ISDIR(metadata.st_mode):
                record["type"] = "directory"
            elif stat.S_ISREG(metadata.st_mode) and metadata.st_nlink == 1:
                payload, _ = read_regular(
                    path, "verification state file {}".format(relative),
                    MAX_EXPANDED_BYTES)
                total_bytes += len(payload)
                if total_bytes > MAX_EXPANDED_BYTES:
                    refuse("verification state exceeds the byte ceiling")
                record.update({
                    "type": "file", "size_bytes": len(payload),
                    "sha256": sha256_bytes(payload),
                })
            else:
                refuse("verification state contains a hard link or special entry")
            if metadata.st_uid != os.geteuid():
                refuse("verification state contains an unexpected owner")
            records.append(record)
    return sha256_bytes(VERIFICATION_STATE_DOMAIN + canonical_bytes(records))


def walk_verification_state(root: Path) -> List[Tuple[str, str, Path, os.stat_result]]:
    """Walk state while admitting its one exact contained CLI symlink."""
    found: List[Tuple[str, str, Path, os.stat_result]] = []
    entries = 0
    for current_text, directory_names, file_names in os.walk(
            str(root), topdown=True, followlinks=False):
        directory_names.sort()
        file_names.sort()
        current = Path(current_text)
        for name in directory_names + file_names:
            path = current / name
            metadata = path.lstat()
            relative = path.relative_to(root).as_posix()
            entries += 1
            if entries > MAX_ARCHIVE_MEMBERS:
                refuse("verification state exceeds the entry ceiling")
            if metadata.st_uid != os.geteuid():
                refuse("verification state contains an unexpected owner")
            if stat.S_ISLNK(metadata.st_mode):
                kind = "symlink"
            elif stat.S_ISDIR(metadata.st_mode):
                kind = "directory"
            elif stat.S_ISREG(metadata.st_mode) and metadata.st_nlink == 1:
                kind = "file"
            else:
                refuse("verification state contains a hard link or special entry")
            found.append((relative, kind, path, metadata))
    found.sort(key=lambda item: item[0].encode("utf-8"))
    return found


def tree_binding(root: Path, algorithm: str) -> Dict[str, Any]:
    root = require_directory(root, "tree binding root")
    digest = package_tree_sha256(root) if algorithm == PACKAGE_TREE_ALGORITHM \
        else private_tree_sha256(root)
    return {"path": str(root), "algorithm": algorithm, "sha256": digest}


def validate_tree_binding(value: Any, label: str, algorithm: str) -> Path:
    return validate_tree_snapshot(value, label, algorithm)["root"]


def validate_tree_snapshot(value: Any, label: str, algorithm: str) -> Dict[str, Any]:
    binding = exact_keys(value, ("path", "algorithm", "sha256"), label)
    if binding["algorithm"] != algorithm:
        refuse("{} uses an unsupported algorithm".format(label))
    require_digest(binding["sha256"], "{} digest".format(label))
    root = require_directory(Path(require_string(binding["path"], "{} path".format(label))),
                             "{} path".format(label))
    if algorithm == PRIVATE_TREE_ALGORITHM:
        snapshot = private_tree_snapshot(root)
        observed = {"path": str(root), "algorithm": algorithm,
                    "sha256": snapshot["sha256"]}
    else:
        snapshot = {"root": root, "sha256": package_tree_sha256(root), "entries": {}}
        observed = {"path": str(root), "algorithm": algorithm,
                    "sha256": snapshot["sha256"]}
    if observed != binding:
        refuse("{} no longer matches its tree binding".format(label))
    return snapshot


def expected_install_directories(inventory: Dict[str, Dict[str, Any]]) -> set:
    directories = {name for name, item in inventory.items()
                   if item["type"] == "directory"}
    for name in inventory:
        path = PurePosixPath(name)
        for parent in path.parents:
            if str(parent) != ".":
                directories.add(parent.as_posix())
    return directories


def verify_installed_payload(install_root: Path,
                             inventory: Dict[str, Dict[str, Any]],
                             receipt_name: str = ".mainframe-install-receipt.json") -> None:
    install_root = require_directory(install_root, "installed MAINFRAME root", private=True)
    expected_files = {name: item for name, item in inventory.items()
                      if item["type"] == "file"}
    expected_directories = expected_install_directories(inventory)
    actual_files: Dict[str, Tuple[Path, os.stat_result]] = {}
    actual_directories = set()
    for relative, kind, path, metadata in walk_tree(install_root, "installed MAINFRAME tree"):
        if kind == "directory":
            actual_directories.add(relative)
        else:
            actual_files[relative] = (path, metadata)
    if set(actual_files) != set(expected_files) | {receipt_name}:
        refuse("installed payload file inventory differs from archive plus receipt")
    if actual_directories != expected_directories:
        refuse("installed payload directory inventory differs from archive")
    for name, expected in expected_files.items():
        path, metadata = actual_files[name]
        payload, _ = read_regular(path, "installed payload {}".format(name),
                                  MAX_EXPANDED_BYTES)
        observed = {
            "type": "file", "mode": path_mode(metadata),
            "size_bytes": len(payload), "sha256": sha256_bytes(payload),
        }
        if observed != expected:
            refuse("installed payload differs from archive member {}".format(name))
    for name in expected_directories:
        directory = install_root.joinpath(*PurePosixPath(name).parts)
        # The isolated proof keeps extracted directories owner-private even
        # though the release archive advertises 0755. File bytes and modes are
        # exact; directory privacy is a deliberate stronger local staging
        # boundary and is not described as a public installer run.
        if path_mode(directory.lstat()) != "0700":
            refuse("installed directory mode differs from private staging contract: {}".format(name))


def parse_manifest(install_root: Path,
                   inventory: Dict[str, Dict[str, Any]]) -> Tuple[Path, str]:
    manifest = install_root / "SHA256SUMS"
    payload, _ = read_regular(manifest, "installed SHA256SUMS", MAX_JSON_BYTES)
    try:
        text = payload.decode("ascii", errors="strict")
    except UnicodeDecodeError as error:
        refuse("installed SHA256SUMS is not ASCII: {}".format(error))
    rows: Dict[str, str] = {}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"([0-9a-f]{64})  ([^\x00-\x1f\x7f]+)", line)
        if match is None:
            refuse("installed SHA256SUMS contains a non-canonical record")
        name = match.group(2)
        safe_member_name(tarfile.TarInfo(name))
        if name in rows:
            refuse("installed SHA256SUMS contains a duplicate record")
        rows[name] = match.group(1)
    expected = {name: item["sha256"] for name, item in inventory.items()
                if item["type"] == "file" and name != "SHA256SUMS"}
    if rows != expected:
        refuse("installed SHA256SUMS does not exactly authenticate the archive payload")
    return manifest, sha256_bytes(payload)


def validate_version(install_root: Path, expected_version: str) -> Path:
    version_path = install_root / "VERSION"
    payload, _ = read_regular(version_path, "installed VERSION", 256)
    try:
        value = payload.decode("ascii", errors="strict")
    except UnicodeDecodeError as error:
        refuse("installed VERSION is not ASCII: {}".format(error))
    if value != expected_version + "\n":
        refuse("installed VERSION does not match archive filename")
    return version_path


def install_receipt_value(version: str, archive_sha256: str, manifest_sha256: str,
                          install_root: Path, bin_dir: Path, cli_link: Path,
                          installed_at: Optional[str] = None) -> Dict[str, Any]:
    if installed_at is None:
        installed_at = datetime.datetime.now(
            datetime.timezone.utc).replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")
    return {
        "schema_version": 1,
        "install_method": "release-archive",
        "version": version,
        "archive_sha256": archive_sha256,
        "manifest_sha256": manifest_sha256,
        "install_dir": str(install_root),
        "bin_dir": str(bin_dir),
        "cli_link": str(cli_link),
        "installed_at": installed_at,
    }


def validate_install_receipt(path: Path, expected: Dict[str, Any]) -> None:
    value = exact_keys(load_json_file(path, "install receipt", "0600"),
                       ("schema_version", "install_method", "version", "archive_sha256",
                        "manifest_sha256", "install_dir", "bin_dir", "cli_link",
                        "installed_at"), "install receipt")
    for key in expected:
        if key == "installed_at":
            continue
        if value[key] != expected[key]:
            refuse("install receipt {} differs from selected candidate".format(key))
    timestamp = require_string(value["installed_at"], "install receipt timestamp")
    if re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z",
                    timestamp) is None:
        refuse("install receipt timestamp is not canonical UTC")


def normalize_architecture(value: str) -> str:
    lowered = value.lower()
    if lowered in ("arm64", "aarch64"):
        return "arm64"
    if lowered in ("x86_64", "amd64"):
        return "x86_64"
    refuse("current architecture is not advertised")


def _darwin_sysctl_int(name: str) -> Optional[int]:
    """Read one Darwin integer sysctl without starting a subprocess."""
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        sysctlbyname = libc.sysctlbyname
    except (AttributeError, OSError) as error:
        refuse("cannot inspect Darwin native execution: {}".format(error))
    sysctlbyname.argtypes = [
        ctypes.c_char_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_size_t),
        ctypes.c_void_p, ctypes.c_size_t,
    ]
    sysctlbyname.restype = ctypes.c_int
    value = ctypes.c_int(0)
    size = ctypes.c_size_t(ctypes.sizeof(value))
    ctypes.set_errno(0)
    result = sysctlbyname(
        name.encode("ascii"), ctypes.byref(value), ctypes.byref(size), None, 0)
    if result == 0:
        if size.value != ctypes.sizeof(value) or value.value not in (0, 1):
            refuse("Darwin native-state probe {} is malformed".format(name))
        return value.value
    error_number = ctypes.get_errno()
    if error_number == errno.ENOENT:
        return None
    refuse("Darwin native-state probe {} failed with errno {}".format(
        name, error_number))


def _require_native_darwin(architecture: str) -> None:
    translated = _darwin_sysctl_int("sysctl.proc_translated")
    arm64_capable = _darwin_sysctl_int("hw.optional.arm64")
    if translated == 1:
        refuse("Darwin process is translated under Rosetta; native evidence is required")
    if architecture == "arm64":
        if translated != 0 or arm64_capable != 1:
            refuse("cannot establish native Darwin arm64 execution")
    elif architecture == "x86_64" and arm64_capable == 1:
        refuse("Darwin x86_64 process is running on Apple Silicon")


def current_platform() -> Dict[str, str]:
    operating_system = platform.system()
    architecture = normalize_architecture(platform.machine())
    if operating_system == "Darwin":
        _require_native_darwin(architecture)
        system_libc = "none"
    elif operating_system == "Linux":
        try:
            libc = os.confstr("CS_GNU_LIBC_VERSION")
        except (AttributeError, OSError, ValueError):
            libc = None
        if not libc or not libc.startswith("glibc "):
            refuse("only the advertised Linux glibc candidate is supported")
        system_libc = "glibc"
    else:
        refuse("current operating system is not advertised")
    identifier = "{}-{}-{}".format(operating_system, architecture, system_libc)
    if identifier not in {
            "Darwin-arm64-none", "Darwin-x86_64-none", "Linux-x86_64-glibc"}:
        refuse("current platform tuple is not advertised: {}".format(identifier))
    return {"id": identifier, "os": operating_system,
            "architecture": architecture, "system_libc": system_libc}


def _cpu_architecture(cpu_type: int) -> Optional[str]:
    if cpu_type == 0x0100000C:
        return "arm64"
    if cpu_type == 0x01000007:
        return "x86_64"
    return None


def _validate_macho_header(raw: bytes, offset: int, limit: int, endian: str,
                           expected_cpu: Optional[int], label: str) -> int:
    if limit > len(raw) or offset < 0 or limit < offset + 32:
        refuse("{} has a truncated 64-bit Mach-O header".format(label))
    values = struct.unpack(endian + "IIIIIIII", raw[offset:offset + 32])
    (_magic, cpu_type, _subtype, file_type, command_count,
     command_bytes, _flags, _reserved) = values
    if expected_cpu is not None and cpu_type != expected_cpu:
        refuse("{} Mach-O CPU type disagrees with its container".format(label))
    if file_type != 2:
        refuse("{} must be a Mach-O executable".format(label))
    if command_count > 100_000 or command_bytes > limit - offset - 32:
        refuse("{} has invalid Mach-O load-command bounds".format(label))
    return cpu_type


def binary_identity(raw: bytes, label: str) -> Tuple[str, Set[str]]:
    """Return the supported 64-bit architectures in an executable image."""
    if len(raw) < 20:
        refuse("{} is too small to be a supported executable".format(label))
    if raw.startswith(b"\x7fELF"):
        if len(raw) < 64 or raw[4] != 2 or raw[5] not in (1, 2) or raw[6] != 1:
            refuse("{} must be a 64-bit ELF executable".format(label))
        endian = "<" if raw[5] == 1 else ">"
        elf_type = struct.unpack(endian + "H", raw[16:18])[0]
        if elf_type not in (2, 3):
            refuse("{} must be an ELF executable or shared object".format(label))
        machine = struct.unpack(endian + "H", raw[18:20])[0]
        elf_version = struct.unpack(endian + "I", raw[20:24])[0]
        if elf_version != 1:
            refuse("{} has an invalid ELF version".format(label))
        architecture = {62: "x86_64", 183: "arm64"}.get(machine)
        if architecture is None:
            refuse("{} has an unsupported ELF architecture".format(label))
        if raw[5] != 1:
            refuse("{} has unsupported ELF architecture byte order".format(label))
        program_offset = struct.unpack(endian + "Q", raw[32:40])[0]
        section_offset = struct.unpack(endian + "Q", raw[40:48])[0]
        header_size, program_entry_size, program_count, section_entry_size, \
            section_count = struct.unpack(endian + "HHHHH", raw[52:62])
        if header_size != 64:
            refuse("{} has an invalid ELF header size".format(label))
        if program_count:
            if program_entry_size != 56 or program_offset < header_size or \
                    program_offset + program_entry_size * program_count > len(raw):
                refuse("{} has invalid ELF program-header bounds".format(label))
        if section_count:
            if section_entry_size != 64 or section_offset < header_size or \
                    section_offset + section_entry_size * section_count > len(raw):
                refuse("{} has invalid ELF section-header bounds".format(label))
        return "elf", {architecture}

    thin_magics = {
        b"\xcf\xfa\xed\xfe": "<",
        b"\xfe\xed\xfa\xcf": ">",
    }
    if raw[:4] in thin_magics:
        cpu_type = _validate_macho_header(
            raw, 0, len(raw), thin_magics[raw[:4]], None, label)
        architecture = _cpu_architecture(cpu_type)
        if architecture is None:
            refuse("{} has an unsupported Mach-O architecture".format(label))
        return "mach-o", {architecture}

    fat_magics = {
        b"\xca\xfe\xba\xbe": (">", 20),
        b"\xbe\xba\xfe\xca": ("<", 20),
        b"\xca\xfe\xba\xbf": (">", 32),
        b"\xbf\xba\xfe\xca": ("<", 32),
    }
    fat = fat_magics.get(raw[:4])
    if fat is not None:
        endian, width = fat
        if len(raw) < 8:
            refuse("{} has a truncated universal Mach-O header".format(label))
        count = struct.unpack(endian + "I", raw[4:8])[0]
        if count < 1 or count > 32 or len(raw) < 8 + count * width:
            refuse("{} has an invalid universal Mach-O header".format(label))
        architectures: Set[str] = set()
        slice_ranges: List[Tuple[int, int]] = []
        for index in range(count):
            entry_offset = 8 + index * width
            cpu_type = struct.unpack(
                endian + "I", raw[entry_offset:entry_offset + 4])[0]
            architecture = _cpu_architecture(cpu_type)
            if width == 20:
                slice_offset, slice_size = struct.unpack(
                    endian + "II", raw[entry_offset + 8:entry_offset + 16])
            else:
                slice_offset, slice_size = struct.unpack(
                    endian + "QQ", raw[entry_offset + 8:entry_offset + 24])
            if (slice_size < 32 or slice_offset < 8 + count * width or
                    slice_offset + slice_size > len(raw)):
                refuse("{} has an invalid universal Mach-O slice".format(label))
            slice_end = slice_offset + slice_size
            if any(slice_offset < observed_end and observed_start < slice_end
                   for observed_start, observed_end in slice_ranges):
                refuse("{} has overlapping universal Mach-O slices".format(label))
            slice_ranges.append((slice_offset, slice_end))
            slice_magic = raw[slice_offset:slice_offset + 4]
            slice_endian = thin_magics.get(slice_magic)
            if slice_endian is None:
                refuse("{} universal slice is not 64-bit Mach-O".format(label))
            _validate_macho_header(
                raw, slice_offset, slice_end, slice_endian, cpu_type, label)
            if architecture is not None:
                architectures.add(architecture)
        if not architectures:
            refuse("{} has no supported universal Mach-O slice".format(label))
        return "mach-o-universal", architectures
    refuse("{} is not a supported ELF or Mach-O executable".format(label))


def require_observed_executable_architecture(
        observed: Dict[str, Any], platform_value: Dict[str, str],
        label: str) -> Dict[str, Any]:
    format_name, architectures = binary_identity(observed["payload"], label)
    operating_system = platform_value["os"]
    expected = platform_value["architecture"]
    if operating_system == "Darwin" and not format_name.startswith("mach-o"):
        refuse("{} is not a Mach-O executable for Darwin".format(label))
    if operating_system == "Linux" and format_name != "elf":
        refuse("{} is not an ELF executable for Linux".format(label))
    if expected not in architectures:
        refuse("{} does not contain the native {} architecture".format(
            label, expected))
    return {"format": format_name,
            "architectures": sorted(architectures), "selected": expected}


def bind_native_executable(
        path: Path, platform_value: Dict[str, str], label: str,
        expected_binding: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    observed = read_bound_file(path, label, MAX_ARCHIVE_BYTES)
    if observed["metadata"].st_mode & (stat.S_IWGRP | stat.S_IWOTH):
        refuse("{} must not be group- or other-writable".format(label))
    require_observed_executable_architecture(observed, platform_value, label)
    binding = observed["binding"]
    if expected_binding is not None and binding != expected_binding:
        refuse("{} changed after native-architecture admission".format(label))
    return binding


def trusted_executable(candidates: Sequence[str], label: str) -> Path:
    for candidate in candidates:
        if not candidate:
            continue
        path = Path(candidate)
        if not path.is_absolute():
            continue
        try:
            resolved = path.resolve(strict=True)
            metadata = resolved.lstat()
        except OSError:
            continue
        if stat.S_ISREG(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode) and \
                metadata.st_uid in (0, os.geteuid()) and metadata.st_mode & stat.S_IXUSR:
            return resolved
    refuse("{} executable was not found in a trusted location".format(label))


def select_shell(name: str) -> Tuple[Path, Path]:
    inherited_bash = os.environ.get("MAINFRAME_BASH", "")
    bash = trusted_executable((
        inherited_bash,
        "/opt/homebrew/bin/bash", "/usr/local/bin/bash",
        "/home/linuxbrew/.linuxbrew/bin/bash", "/opt/local/bin/bash",
        "/usr/bin/bash", "/bin/bash",
    ), "Bash 4.4+")
    if name == "bash":
        shell = bash
    else:
        shell = trusted_executable((
            "/bin/zsh", "/usr/bin/zsh", "/opt/homebrew/bin/zsh",
            "/usr/local/bin/zsh", "/opt/local/bin/zsh",
        ), "zsh")
    return shell, bash


def fixed_runtime_path(bin_dir: Path, poison_dir: Path,
                       shell: Path, bash: Path) -> str:
    candidates = [bin_dir, poison_dir, shell.parent, bash.parent,
                  Path("/opt/homebrew/bin"), Path("/usr/local/bin"),
                  Path("/home/linuxbrew/.linuxbrew/bin"), Path("/opt/local/bin"),
                  Path("/usr/bin"), Path("/bin"), Path("/usr/sbin"), Path("/sbin")]
    result = []
    for candidate in candidates:
        text = str(candidate)
        if candidate.is_dir() and text not in result:
            result.append(text)
    return ":".join(result)


def bootstrap_runtime_path(shell: Path, bash: Path) -> str:
    """PATH available before the isolated profile has been discovered."""
    candidates = [shell.parent, bash.parent,
                  Path("/opt/homebrew/bin"), Path("/usr/local/bin"),
                  Path("/home/linuxbrew/.linuxbrew/bin"), Path("/opt/local/bin"),
                  Path("/usr/bin"), Path("/bin"), Path("/usr/sbin"), Path("/sbin")]
    result = []
    for candidate in candidates:
        text = str(candidate)
        if candidate.is_dir() and text not in result:
            result.append(text)
    return ":".join(result)


def profile_payload(shell_name: str, install_root: Path, modern_bash: Path,
                    runtime_path: str,
                    profile_nonce: str) -> Tuple[Path, bytes, Optional[Tuple[Path, bytes]]]:
    exports = (
        "export MAINFRAME_ROOT={}\n"
        "export MAINFRAME_BASH={}\n"
        "export MAINFRAME_AI_ENABLED=1\n"
        "export MAINFRAME_CANARY_PROFILE_NONCE={}\n"
        "export PATH={}\n"
    ).format(shlex.quote(str(install_root)), shlex.quote(str(modern_bash)),
             shlex.quote(profile_nonce), shlex.quote(runtime_path)).encode("utf-8")
    if shell_name == "bash":
        profile = install_root.parent / ".bashrc"
        login = install_root.parent / ".bash_profile"
        login_payload = b'if [ -f "$HOME/.bashrc" ]; then . "$HOME/.bashrc"; fi\n'
        return profile, exports, (login, login_payload)
    return install_root.parent / ".zshrc", exports, None


def create_poison_commands(poison_dir: Path, marker: Path,
                           expected_parent: os.stat_result) -> os.stat_result:
    poison_identity = create_owned_directory(
        poison_dir, 0o700, "poison command directory", expected_parent)
    payload = (
        "#!/bin/sh\n"
        "printf '%s\\n' \"$0\" >> {}\n"
        "exit 97\n"
    ).format(shlex.quote(str(marker))).encode("utf-8")
    for name in ("pi", "ollama", "curl", "wget", "nc", "git"):
        write_new(
            poison_dir / name, payload, 0o700, "poison command", poison_identity)
    return poison_identity


def install_candidate(state_root: Path, archive: Path, version: str,
                      archive_binding: Dict[str, Any], shell_name: str,
                      shell: Path, modern_bash: Path,
                      state_root_identity: os.stat_result) -> Dict[str, Any]:
    home = state_root / "home"
    install_root = home / "mainframe-install"
    bin_dir = home / ".local" / "bin"
    poison_dir = state_root / "poison-bin"
    marker = state_root / "forbidden-runtime-invoked"
    home_identity = create_owned_directory(
        home, 0o700, "isolated HOME", state_root_identity)
    install_identity = create_owned_directory(
        install_root, 0o700, "candidate install root", home_identity)
    local_dir = home / ".local"
    local_identity = create_owned_directory(
        local_dir, 0o700, "isolated local directory", home_identity)
    bin_identity = create_owned_directory(
        bin_dir, 0o700, "isolated bin directory", local_identity)
    poison_identity = create_poison_commands(
        poison_dir, marker, state_root_identity)
    inventory = archive_inventory(
        archive, install_root, expected_binding=archive_binding,
        destination_identity=install_identity)
    validate_version(install_root, version)
    _, manifest_sha256 = parse_manifest(install_root, inventory)
    cli = install_root / "bin" / "mainframe"
    _, cli_metadata = read_regular(cli, "installed MAINFRAME CLI", MAX_JSON_BYTES)
    if not cli_metadata.st_mode & stat.S_IXUSR:
        refuse("installed MAINFRAME CLI is not executable")
    cli_link = bin_dir / "mainframe"
    create_owned_symlink(
        cli_link, str(cli), "installed MAINFRAME CLI link", bin_identity)
    receipt = install_root / ".mainframe-install-receipt.json"
    receipt_value = install_receipt_value(
        version, archive_binding["sha256"], manifest_sha256,
        install_root, bin_dir, cli_link,
    )
    write_json(
        receipt, receipt_value, 0o600, "install receipt", install_identity)
    validate_install_receipt(receipt, receipt_value)
    verify_installed_payload(install_root, inventory)
    runtime_path = fixed_runtime_path(bin_dir, poison_dir, shell, modern_bash)
    profile_nonce = sha256_bytes(
        b"MAINFRAME-INSTALLED-AWM-PROFILE-V1\0" +
        archive_binding["sha256"].encode("ascii") + b"\0" +
        shell_name.encode("ascii"))
    profile_path, profile_bytes, login = profile_payload(
        shell_name, install_root, modern_bash, runtime_path, profile_nonce)
    write_new(
        profile_path, profile_bytes, 0o600, "isolated shell profile", home_identity)
    if login is not None:
        write_new(
            login[0], login[1], 0o600, "isolated Bash login profile", home_identity)
    return {
        "home": home, "install_root": install_root, "bin_dir": bin_dir,
        "cli": cli, "cli_link": cli_link, "receipt": receipt,
        "receipt_value": receipt_value, "inventory": inventory,
        "manifest_sha256": manifest_sha256, "poison_dir": poison_dir,
        "poison_marker": marker, "runtime_path": runtime_path,
        "bootstrap_path": bootstrap_runtime_path(shell, modern_bash),
        "profile_nonce": profile_nonce,
        "profile": profile_path, "login_profile": login[0] if login else None,
        "state_root_identity": state_root_identity,
        "home_identity": home_identity, "local_identity": local_identity,
        "install_identity": install_identity,
        "bin_identity": bin_identity, "poison_identity": poison_identity,
        "installed_tree_sha256": package_tree_sha256(install_root),
    }


def ensure_absent_output(path: Path, label: str,
                         private_parent: bool) -> Tuple[Path, os.stat_result]:
    """Resolve an absent output without following a final component."""
    text = str(path)
    if not path.is_absolute() or "\\" in text or "//" in text or \
            any(ord(character) < 32 or ord(character) == 127 for character in text):
        refuse("{} must be a normalized absolute path".format(label))
    if path.name in ("", ".", ".."):
        refuse("{} must name a file".format(label))
    try:
        resolved_parent = path.parent.resolve(strict=True)
    except OSError as error:
        refuse("{} parent is unavailable: {}".format(label, error))
    parent = require_directory(
        resolved_parent, "{} parent".format(label), private=private_parent)
    target = parent / path.name
    if target.exists() or target.is_symlink():
        refuse("refusing to overwrite existing {}".format(label))
    return target, parent.lstat()


def copy_tree(source: Path, destination: Path,
              expected_parent: Optional[os.stat_result] = None) -> os.stat_result:
    """Copy a regular owner-controlled tree through pinned directory FDs."""
    source_fd, source_metadata = open_owned_directory(source, "workspace source")
    destination_fd = -1
    destination_metadata: Optional[os.stat_result] = None
    entries_seen = 0
    bytes_seen = 0

    def copy_directory(source_descriptor: int, destination_descriptor: int,
                       relative: Tuple[str, ...]) -> None:
        nonlocal entries_seen, bytes_seen
        with os.scandir(source_descriptor) as iterator:
            entries = sorted(list(iterator), key=lambda entry: os.fsencode(entry.name))
        for entry in entries:
            name = entry.name
            if name in ("", ".", "..") or "/" in name or "\\" in name or \
                    any(ord(character) < 32 or ord(character) == 127 for character in name):
                refuse("workspace source contains an unsafe entry name")
            entries_seen += 1
            if entries_seen > MAX_ARCHIVE_MEMBERS:
                refuse("workspace source exceeds the entry ceiling")
            before = entry.stat(follow_symlinks=False)
            label = "workspace source {}".format("/".join(relative + (name,)))
            if before.st_uid != os.geteuid() or stat.S_ISLNK(before.st_mode):
                refuse("{} contains an unsafe owner or symbolic link".format(label))
            if stat.S_ISDIR(before.st_mode):
                child_source = os.open(
                    name, directory_open_flags(), dir_fd=source_descriptor)
                child_destination = -1
                try:
                    opened_source = os.fstat(child_source)
                    validate_owned_directory_metadata(opened_source, label)
                    require_same_object(opened_source, before, label)
                    os.mkdir(name, 0o700, dir_fd=destination_descriptor)
                    destination_before = os.stat(
                        name, dir_fd=destination_descriptor, follow_symlinks=False)
                    child_destination = os.open(
                        name, directory_open_flags(), dir_fd=destination_descriptor)
                    created = os.fstat(child_destination)
                    validate_owned_directory_metadata(
                        created, "workspace destination", private=True)
                    require_same_object(
                        created, destination_before, "workspace destination")
                    if path_mode(created) != "0700" or os.listdir(child_destination):
                        refuse("workspace destination changed before it was pinned")
                    copy_directory(
                        child_source, child_destination, relative + (name,))
                    require_same_object(os.fstat(child_source), opened_source, label)
                    current = os.stat(
                        name, dir_fd=destination_descriptor, follow_symlinks=False)
                    require_same_object(current, created, "workspace destination")
                finally:
                    os.close(child_source)
                    if child_destination >= 0:
                        os.close(child_destination)
                continue
            if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
                refuse("{} contains a special or hard-linked entry".format(label))
            read_flags = os.O_RDONLY
            if hasattr(os, "O_CLOEXEC"):
                read_flags |= os.O_CLOEXEC
            if hasattr(os, "O_NOFOLLOW"):
                read_flags |= os.O_NOFOLLOW
            if hasattr(os, "O_NONBLOCK"):
                read_flags |= os.O_NONBLOCK
            source_file = os.open(name, read_flags, dir_fd=source_descriptor)
            destination_file = -1
            try:
                opened_source = os.fstat(source_file)
                if not stat.S_ISREG(opened_source.st_mode) or opened_source.st_nlink != 1 or \
                        opened_source.st_uid != os.geteuid() or \
                        (opened_source.st_dev, opened_source.st_ino,
                         opened_source.st_size, opened_source.st_mtime_ns) != \
                        (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns):
                    refuse("{} changed before it was opened".format(label))
                bytes_seen += opened_source.st_size
                if bytes_seen > MAX_EXPANDED_BYTES:
                    refuse("workspace source exceeds the byte ceiling")
                write_flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
                if hasattr(os, "O_CLOEXEC"):
                    write_flags |= os.O_CLOEXEC
                if hasattr(os, "O_NOFOLLOW"):
                    write_flags |= os.O_NOFOLLOW
                destination_file = os.open(
                    name, write_flags, 0o600, dir_fd=destination_descriptor)
                remaining = opened_source.st_size
                while remaining:
                    chunk = os.read(source_file, min(1024 * 1024, remaining))
                    if not chunk:
                        refuse("{} was truncated while copied".format(label))
                    view = memoryview(chunk)
                    while view:
                        written = os.write(destination_file, view)
                        if written <= 0:
                            refuse("workspace destination could not be written")
                        view = view[written:]
                    remaining -= len(chunk)
                if os.read(source_file, 1):
                    refuse("{} grew while copied".format(label))
                after_source = os.fstat(source_file)
                if (opened_source.st_dev, opened_source.st_ino,
                    opened_source.st_size, opened_source.st_mtime_ns) != \
                        (after_source.st_dev, after_source.st_ino,
                         after_source.st_size, after_source.st_mtime_ns):
                    refuse("{} changed while copied".format(label))
                os.fchmod(destination_file, stat.S_IMODE(opened_source.st_mode))
                os.fsync(destination_file)
                created = os.fstat(destination_file)
                current = os.stat(
                    name, dir_fd=destination_descriptor, follow_symlinks=False)
                if not stat.S_ISREG(created.st_mode) or created.st_nlink != 1 or \
                        created.st_uid != os.geteuid() or \
                        created.st_size != opened_source.st_size:
                    refuse("workspace destination changed during creation")
                require_same_object(current, created, "workspace destination")
            finally:
                os.close(source_file)
                if destination_file >= 0:
                    os.close(destination_file)

    try:
        destination_fd, destination_metadata = create_owned_directory_fd(
            destination, 0o700,
            "workspace destination", expected_parent)
        copy_directory(source_fd, destination_fd, ())
        require_same_object(
            os.fstat(source_fd), source_metadata, "workspace source")
        require_directory_path_identity(
            source, source_metadata, "workspace source")
        require_directory_path_identity(
            destination, destination_metadata, "workspace destination")
        return destination_metadata
    finally:
        os.close(source_fd)
        if destination_fd >= 0:
            os.close(destination_fd)


def snapshot_tree(source: Path, destination: Path,
                  expected_parent: Optional[os.stat_result] = None) -> Dict[str, Any]:
    copy_tree(source, destination, expected_parent)
    return tree_binding(destination, PRIVATE_TREE_ALGORITHM)


def bounded_process(argv: Sequence[str], environment: Dict[str, str],
                    stdout_path: Path, stderr_path: Path,
                    label: str) -> Tuple[int, int]:
    if not argv or not Path(argv[0]).is_absolute():
        refuse("{} executable must be absolute".format(label))
    stdout_path, stdout_parent = ensure_absent_output(
        stdout_path, "{} stdout".format(label), True)
    stderr_path, stderr_parent = ensure_absent_output(
        stderr_path, "{} stderr".format(label), True)
    stdout_descriptor = create_new_descriptor(
        stdout_path, 0o600, "{} stdout".format(label), stdout_parent)
    stderr_descriptor = create_new_descriptor(
        stderr_path, 0o600, "{} stderr".format(label), stderr_parent)
    try:
        process = subprocess.Popen(
            list(argv), env=environment, stdin=subprocess.DEVNULL,
            stdout=stdout_descriptor, stderr=stderr_descriptor,
            start_new_session=True, close_fds=True,
        )
        try:
            return_code = process.wait(timeout=PROCESS_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=PROCESS_GROUP_GRACE_SECONDS)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
            refuse("{} exceeded the process timeout".format(label))
    finally:
        os.close(stdout_descriptor)
        os.close(stderr_descriptor)
    if return_code != 0:
        stderr, _ = read_regular(stderr_path, "{} stderr".format(label), MAX_OUTPUT_BYTES)
        diagnostic = stderr.decode("utf-8", errors="replace").strip().replace("\n", " ")
        refuse("{} exited {}{}".format(
            label, return_code, ": " + diagnostic[:4096] if diagnostic else ""))
    return process.pid, return_code


def read_text(path: Path, label: str, maximum: int = MAX_OUTPUT_BYTES) -> str:
    payload, _ = read_regular(path, label, maximum)
    try:
        return payload.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        refuse("{} is not UTF-8: {}".format(label, error))


def project_memory_awm_root(home: Path) -> Path:
    """Return the fixed adapter tree selected from the public XDG state root."""
    return (
        home / ".local" / "state" / "mainframe"
        / ".mainframe-control-plane-runtime"
        / "project-memory-adapter-state" / "awm"
    )


def clean_environment(home: Path, temporary: Path,
                      runtime_path: str) -> Dict[str, str]:
    environment = {
        "CI": "1", "HOME": str(home), "LANG": "C", "LC_ALL": "C",
        "LOGNAME": "mainframe-canary", "MAINFRAME_LOCAL_PROTOCOL": "1",
        "NO_COLOR": "1", "PATH": runtime_path,
        "PYTHONDONTWRITEBYTECODE": "1", "TMPDIR": str(temporary),
        "USER": "mainframe-canary",
        "XDG_CACHE_HOME": str(home / ".cache"),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_STATE_HOME": str(home / ".local" / "state"),
        "__CF_USER_TEXT_ENCODING": "0x1F5:0x0:0x0",
    }
    return environment


def shell_command(shell_name: str, shell: Path, command: str) -> List[str]:
    if shell_name == "bash":
        # --norc suppresses an ambient interactive rc, while the isolated
        # .bash_profile deliberately sources the installed .bashrc.  This is
        # a real login/profile discovery path, not an explicit source in the
        # canary command itself.
        return [str(shell), "--norc", "-l", "-i", "-c", command]
    # -d disables global rc files but preserves the isolated user's .zshrc.
    return [str(shell), "-d", "-l", "-i", "-c", command]


def run_shell_operation(sequence: int, operation: str, command: str,
                        state: Dict[str, Any], shell_name: str, shell: Path,
                        project: Path, artifacts: Path, temporary: Path) -> \
        Tuple[Dict[str, Any], str]:
    stdout_path = artifacts / "shell-{}-{}.stdout".format(sequence, operation)
    stderr_path = artifacts / "shell-{}-{}.stderr".format(sequence, operation)
    wrapped = (
        "test \"${{MAINFRAME_CANARY_PROFILE_NONCE-}}\" = {} || exit 90; ".format(
            shlex.quote(state["profile_nonce"])) +
        "test \"$(command -v mainframe)\" = {} || exit 91; ".format(
            shlex.quote(str(state["cli_link"]))) +
        "printf 'CANARY_PID=%s\\n' \"$$\" || exit 92; " + command
    )
    # The installed bin and poison directories are deliberately absent here.
    # Only the isolated shell profile may introduce the complete runtime PATH
    # and nonce required by the wrapped command.
    environment = clean_environment(
        state["home"], temporary, state["bootstrap_path"])
    pid, exit_code = bounded_process(
        shell_command(shell_name, shell, wrapped), environment,
        stdout_path, stderr_path, "fresh login shell {}".format(operation))
    stdout = read_text(stdout_path, "fresh login shell stdout")
    match = re.search(r"^CANARY_PID=([1-9][0-9]*)$", stdout, re.MULTILINE)
    if match is None or int(match.group(1)) != pid:
        refuse("fresh login shell did not report its exact process identity")
    receipt = {
        "sequence": sequence, "operation": operation, "pid": pid,
        "command_sha256": sha256_bytes(command.encode("utf-8")),
        "stdout": file_binding(stdout_path, "fresh login shell stdout", MAX_OUTPUT_BYTES),
        "stderr": file_binding(stderr_path, "fresh login shell stderr", MAX_OUTPUT_BYTES),
        "exit_code": exit_code,
    }
    return receipt, stdout


def transport_request(phase: str, workspace: Path, prompt: Path,
                      context: Optional[Path], artifact_dir: Path,
                      result_path: Path, arm_suffix: str) -> Dict[str, Any]:
    return {
        "schema_version": 1,
        "kind": "mainframe-agent-impact-local-run-request",
        "study_id": "local-development-smoke-v1",
        "plan_id": "plan-0000000000000001",
        "pair_id": "pair-0000000000000001",
        "opaque_arm_id": "arm-00000000000000{}".format(arm_suffix),
        "task_id": "local-001", "phase": phase,
        "workspace": str(workspace), "prompt_path": str(prompt),
        "context_path": str(context) if context is not None else None,
        "artifact_dir": str(artifact_dir), "result_path": str(result_path),
        "budgets": {"wall_seconds": 5, "maximum_tool_calls": 10,
                    "maximum_continuation_bytes": MAX_CONTINUATION_BYTES},
        "environment_contract": {"fresh_per_phase": True,
                                 "allowed_environment_names": ALLOWED_TRANSPORT_ENVIRONMENT_NAMES},
    }


def run_fake_transport(executable: Path, request: Dict[str, Any],
                       run_root: Path, label: str) -> Dict[str, Any]:
    request_path = run_root / "request.json"
    stdout_path = run_root / "stdout"
    stderr_path = run_root / "stderr"
    write_json(request_path, request, 0o600, "{} request".format(label))
    environment = clean_environment(
        Path(request["workspace"]).parent, run_root,
        "/usr/bin:/bin:/usr/sbin:/sbin")
    # The fake transport requires exactly its reviewed environment names.
    environment = {name: environment.get(name, "")
                   for name in ALLOWED_TRANSPORT_ENVIRONMENT_NAMES}
    bounded_process(
        [sys.executable, "-I", "-S", "-B", str(executable), str(request_path)],
        environment, stdout_path, stderr_path, label)
    result_path = Path(request["result_path"])
    result = load_json_file(result_path, "{} result".format(label), "0600")
    if not isinstance(result, dict) or result.get("status") != "completed" or \
            result.get("provider_requests") != 0 or result.get("pi_sessions") != 0 or \
            result.get("network_requests") != 0:
        refuse("{} result violates the deterministic transport contract".format(label))
    return result


def make_neutral_envelope(source_fact: str) -> bytes:
    value = {
        "schema_version": 1,
        "kind": "mainframe-agent-impact-neutral-continuation",
        "payload": {"source_context": source_fact},
    }
    payload = canonical_bytes(value) + b"\n"
    if len(payload) > MAX_CONTINUATION_BYTES:
        refuse("neutral continuation exceeds its byte ceiling")
    return payload


def load_single_jsonl(path: Path, label: str) -> Dict[str, Any]:
    payload, _ = read_regular(path, label, MAX_OUTPUT_BYTES)
    lines = payload.splitlines()
    if len(lines) != 1:
        refuse("{} must contain one record".format(label))
    value = parse_json(lines[0], label)
    if not isinstance(value, dict):
        refuse("{} record must be an object".format(label))
    return value


def validate_awm_snapshot_sequence(snapshots: Dict[str, Dict[str, Any]],
                                   treatment_workspace: Path) -> bytes:
    """Validate all stage semantics from the exact bytes that formed each tree digest."""
    if snapshots["awm_before"]["entries"]:
        refuse("AWM before snapshot must be empty")
    stages = (
        "awm_after_ensure", "awm_after_checkpoint",
        "awm_after_discovery", "awm_after_handoff")
    project_digest = sha256_bytes(str(treatment_workspace).encode("utf-8"))
    project_relative = "projects/{}.json".format(project_digest)

    def payload(stage: str, relative: str, label: str) -> bytes:
        entry = snapshots[stage]["entries"].get(relative)
        if entry is None or entry.get("type") != "file":
            refuse("{} is missing from the authenticated AWM snapshot".format(label))
        return entry["payload"]

    def json_value(stage: str, relative: str, label: str) -> Any:
        return parse_json(payload(stage, relative, label), label)

    identities: Dict[str, Tuple[str, bytes, Dict[str, Any]]] = {}
    for stage in stages:
        entries = snapshots[stage]["entries"]
        project_files = sorted(
            name for name, entry in entries.items()
            if name.startswith("projects/") and entry["type"] == "file" and
            name.count("/") == 1 and not name.endswith(".lock"))
        if project_files != [project_relative]:
            refuse("AWM {} snapshot has an unexpected project mapping".format(stage))
        mapping_bytes = payload(stage, project_relative, "AWM project mapping")
        project = exact_keys(
            parse_json(mapping_bytes, "AWM project mapping"),
            ("schema_version", "project_sha256", "session_id", "created_at"),
            "AWM project mapping")
        if project["schema_version"] != 1 or project["project_sha256"] != project_digest:
            refuse("AWM {} snapshot has an unexpected project identity".format(stage))
        session_id = require_string(project["session_id"], "AWM session id", SESSION_RE)
        session_prefix = "sessions/projects/{}/".format(session_id)
        session_roots = sorted({
            name.split("/")[2] for name in entries
            if name.startswith("sessions/projects/") and len(name.split("/")) >= 3
        })
        if session_roots != [session_id]:
            refuse("AWM {} snapshot has an unexpected session layout".format(stage))
        manifest = exact_keys(
            json_value(stage, session_prefix + "manifest.json", "AWM manifest"),
            ("schema_version", "session_id", "name", "created_at", "created_epoch",
             "updated_at", "updated_epoch", "parent_session", "status", "namespace",
             "model", "backend"), "AWM manifest")
        if manifest["session_id"] != session_id or manifest["namespace"] != "projects" or \
                manifest["status"] != "active" or manifest["backend"] != "file":
            refuse("AWM {} snapshot does not bind one active project session".format(stage))
        identities[stage] = (session_id, mapping_bytes, manifest)
    if len({value[0] for value in identities.values()}) != 1 or \
            len({value[1] for value in identities.values()}) != 1:
        refuse("AWM stage project/session identity changed")
    session_id = identities["awm_after_ensure"][0]
    session_prefix = "sessions/projects/{}/".format(session_id)
    baseline_manifest = identities["awm_after_ensure"][2]
    immutable_manifest_keys = (
        "schema_version", "session_id", "name", "created_at", "created_epoch",
        "parent_session", "status", "namespace", "model", "backend")
    for stage, (_, _, manifest) in identities.items():
        if any(manifest[key] != baseline_manifest[key] for key in immutable_manifest_keys):
            refuse("AWM {} manifest identity changed".format(stage))

    def one_jsonl(stage: str, relative: str, label: str) -> Dict[str, Any]:
        lines = payload(stage, relative, label).splitlines()
        if len(lines) != 1:
            refuse("{} must contain one record".format(label))
        value = parse_json(lines[0], label)
        if not isinstance(value, dict):
            refuse("{} must contain one object".format(label))
        return value

    def journal_kinds(stage: str) -> List[str]:
        lines = payload(
            stage, session_prefix + "journal/events.jsonl", "AWM journal").splitlines()
        result = []
        for index, line in enumerate(lines, 1):
            value = parse_json(line, "AWM journal record {}".format(index))
            if not isinstance(value, dict) or value.get("session_id") != session_id or \
                    not isinstance(value.get("kind"), str):
                refuse("AWM journal contains an invalid event")
            result.append(value["kind"])
        return result

    def require_empty_locks(stage: str) -> None:
        for name, entry in snapshots[stage]["entries"].items():
            if name.endswith(".lock"):
                if entry.get("type") != "file" or entry.get("payload") != b"":
                    refuse("AWM {} snapshot has an unexpected lock artifact".format(stage))

    def categories(stage: str) -> List[str]:
        value = json_value(
            stage, session_prefix + "index/categories.json", "AWM categories")
        if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
            refuse("AWM categories must be an array of strings")
        return value

    def validate_checkpoint(stage: str, label: str) -> None:
        if payload(stage, session_prefix + "data/source_fact", label + " data") != \
                SOURCE_FACT.encode("utf-8"):
            refuse("{} lost the exact source fact".format(label))
        record = one_jsonl(
            stage, session_prefix + "logs/checkpoints.jsonl", label + " log")
        index_record = json_value(
            stage, session_prefix + "index/source_fact.json", label + " index")
        if record != index_record or record.get("kind") != "checkpoint" or \
                record.get("key") != "source_fact" or record.get("preview") != SOURCE_FACT or \
                record.get("session_id") != session_id:
            refuse("{} has an unexpected checkpoint record".format(label))

    def validate_discovery(stage: str, label: str) -> None:
        record = one_jsonl(stage, session_prefix + "discoveries.jsonl", label + " log")
        mirror = one_jsonl(
            stage, session_prefix + "logs/discoveries.jsonl", label + " mirror")
        if record != mirror or record.get("kind") != "discovery" or \
                record.get("discovery") != DISCOVERY_FACT or \
                record.get("session_id") != session_id:
            refuse("{} has an unexpected discovery record".format(label))

    def non_lock_files(stage: str) -> set:
        return {
            name for name, entry in snapshots[stage]["entries"].items()
            if entry["type"] == "file" and not name.endswith(".lock")
        }

    common_files = {
        project_relative,
        session_prefix + "discoveries.jsonl",
        session_prefix + "index/categories.json",
        session_prefix + "journal/events.jsonl",
        session_prefix + "logs/discoveries.jsonl",
        session_prefix + "logs/index.json",
        session_prefix + "manifest.json",
    }
    checkpoint_files = {
        session_prefix + "data/source_fact",
        session_prefix + "index/source_fact.json",
        session_prefix + "logs/checkpoints.jsonl",
    }
    ensure_files = non_lock_files("awm_after_ensure")
    if ensure_files != common_files or categories("awm_after_ensure") != [] or \
            journal_kinds("awm_after_ensure") != ["init"]:
        refuse("AWM ensure snapshot contains later-stage state")
    for relative in (
            session_prefix + "discoveries.jsonl",
            session_prefix + "logs/discoveries.jsonl"):
        if payload("awm_after_ensure", relative, "AWM ensure discovery log"):
            refuse("AWM ensure snapshot contains later-stage state")
    require_empty_locks("awm_after_ensure")

    checkpoint_stage = "awm_after_checkpoint"
    if non_lock_files(checkpoint_stage) != common_files | checkpoint_files or \
            categories(checkpoint_stage) != ["checkpoints"] or \
            journal_kinds(checkpoint_stage) != ["init", "checkpoint"]:
        refuse("AWM checkpoint snapshot contains later-stage state")
    validate_checkpoint(checkpoint_stage, "AWM checkpoint")
    for relative in (
            session_prefix + "discoveries.jsonl",
            session_prefix + "logs/discoveries.jsonl"):
        if payload(checkpoint_stage, relative, "AWM checkpoint discovery log"):
            refuse("AWM checkpoint snapshot contains later-stage state")
    require_empty_locks(checkpoint_stage)

    discovery_stage = "awm_after_discovery"
    if non_lock_files(discovery_stage) != common_files | checkpoint_files or \
            categories(discovery_stage) != ["checkpoints", "discoveries"] or \
            journal_kinds(discovery_stage) != ["init", "checkpoint", "discovery"]:
        refuse("AWM discovery snapshot has an unexpected event progression")
    validate_checkpoint(discovery_stage, "AWM discovery checkpoint")
    validate_discovery(discovery_stage, "AWM discovery")
    require_empty_locks(discovery_stage)

    handoff_stage = "awm_after_handoff"
    handoff_files = sorted(
        name for name in non_lock_files(handoff_stage)
        if name.startswith(session_prefix + "handoffs/"))
    if len(handoff_files) != 1 or \
            non_lock_files(handoff_stage) != common_files | checkpoint_files | {handoff_files[0]} or \
            categories(handoff_stage) != ["checkpoints", "discoveries"] or \
            journal_kinds(handoff_stage) != ["init", "checkpoint", "discovery", "handoff"]:
        refuse("AWM handoff snapshot has an unexpected event progression")
    validate_checkpoint(handoff_stage, "AWM handoff checkpoint")
    validate_discovery(handoff_stage, "AWM handoff discovery")
    require_empty_locks(handoff_stage)
    handoff_payload = payload(handoff_stage, handoff_files[0], "AWM handoff snapshot record")
    handoff = parse_json(handoff_payload, "AWM handoff snapshot record")
    context = handoff.get("context") if isinstance(handoff, dict) else None
    summary = context.get("summary") if isinstance(context, dict) else None
    checkpoints = summary.get("checkpoints") if isinstance(summary, dict) else None
    if not isinstance(handoff, dict) or handoff.get("type") != "handoff" or \
            handoff.get("target_agent") != "next-agent" or \
            handoff.get("parent_session") != session_id or not isinstance(checkpoints, dict) or \
            checkpoints.get("source_fact") != SOURCE_FACT:
        refuse("AWM handoff snapshot has an unexpected semantic record")
    return handoff_payload


def run_grader(grader: Path, workspace: Path, run_root: Path,
               label: str) -> Tuple[Dict[str, Any], Path]:
    stdout_path = run_root / "stdout"
    stderr_path = run_root / "stderr"
    environment = clean_environment(workspace.parent, run_root,
                                    "/usr/bin:/bin:/usr/sbin:/sbin")
    bounded_process(
        [sys.executable, "-I", "-S", "-B", str(grader), str(workspace)],
        environment, stdout_path, stderr_path, label)
    value = parse_json(read_regular(stdout_path, "{} stdout".format(label), 4096)[0], label)
    expected = {"maximum_score": 100, "score": 100, "solved": True,
                "tests_passed": 4, "tests_total": 4}
    if value != expected:
        refuse("{} did not produce the exact 100/100 result".format(label))
    return value, stdout_path


def protocol_bindings(install_root: Path) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for name, relative in PROTOCOL_RELATIVE_PATHS.items():
        path = install_root / relative
        if name == "task_bundle":
            result[name] = tree_binding(path, PRIVATE_TREE_ALGORITHM)
        else:
            result[name] = file_binding(path, "protocol {}".format(name), MAX_ARCHIVE_BYTES)
    result["maximum_continuation_bytes"] = MAX_CONTINUATION_BYTES
    return result


def require_executing_certifier(binding: Dict[str, Any]) -> None:
    """Bind the running program, not merely a same-named archived file."""
    invoked = file_binding(
        Path(__file__), "executing installed-AWM certifier", MAX_JSON_BYTES)
    comparable_fields = ("type", "mode", "size_bytes", "sha256")
    if any(invoked[field] != binding[field] for field in comparable_fields):
        refuse("executing certifier bytes differ from the installed protocol")


def verification_surface_binding(archive: Path, checksum: Path,
                                 private_evidence: Path, state_root: Path,
                                 shell: Path, runtime_bash: Path) -> str:
    """Bind the finite artifact surface that a replay promises not to change."""
    value = {
        "archive": file_binding(archive, "verification archive", MAX_ARCHIVE_BYTES),
        "checksum": file_binding(checksum, "verification checksum", 4096),
        "private_evidence": file_binding(
            private_evidence, "verification private evidence", MAX_JSON_BYTES, "0600"),
        "private_state": verification_state_sha256(state_root),
        "certifier": file_binding(
            Path(__file__), "verification certifier", MAX_JSON_BYTES),
        "shell": file_binding(shell, "verification shell", MAX_ARCHIVE_BYTES),
        "runtime_bash": file_binding(
            runtime_bash, "verification runtime Bash", MAX_ARCHIVE_BYTES),
    }
    return sha256_bytes(canonical_bytes(value))


def public_projection(private: Dict[str, Any]) -> Dict[str, Any]:
    candidate = private["candidate"]
    shell = private["shell"]
    protocol = private["protocol"]
    measurements = private["measurements"]
    control_final = private["artifacts"]["control_workspace_final"]["sha256"]
    treatment_final = private["artifacts"]["treatment_workspace_final"]["sha256"]
    return {
        "schema_version": 1, "kind": PUBLIC_KIND, "claim_scope": CLAIM_SCOPE,
        "status": "passed",
        "candidate": {
            "version": candidate["version"],
            "archive_sha256": candidate["archive"]["sha256"],
            "checksum_sha256": candidate["checksum"]["sha256"],
            "installed_tree_algorithm": PACKAGE_TREE_ALGORITHM,
            "installed_tree_sha256": candidate["installed_tree"]["sha256"],
            "installed_payload": INSTALLED_PAYLOAD_STATUS,
            "install_receipt_verified": True,
        },
        "platform": private["platform"],
        "shell": {
            "name": shell["name"], "executable_sha256": shell["executable"]["sha256"],
            "version": shell["version"], "fresh_login_shell_count": 4,
            "distinct_processes": True, "isolated_profile_discovery": True,
            "runtime_bash": {
                "executable_sha256": shell["runtime_bash"]["executable"]["sha256"],
                "version": shell["runtime_bash"]["version"],
            },
        },
        "protocol": {
            "certifier_sha256": protocol["certifier"]["sha256"],
            "private_schema_sha256": protocol["private_schema"]["sha256"],
            "evidence_schema_sha256": protocol["evidence_schema"]["sha256"],
            "neutral_continuation_schema_sha256": protocol["neutral_continuation_schema"]["sha256"],
            "task_bundle_sha256": protocol["task_bundle"]["sha256"],
            "fake_transport_sha256": protocol["fake_transport"]["sha256"],
            "grader_sha256": protocol["grader"]["sha256"],
            "maximum_continuation_bytes": MAX_CONTINUATION_BYTES,
        },
        "mechanism": {
            "control": "native-bounded-continuation",
            "treatment": "installed-mainframe-project-awm-handoff",
            "mainframe_runtime_exercised": True, "mainframe_awm_exercised": True,
            "source_fact_occurrences_control": measurements["source_fact_occurrences_control"],
            "source_fact_occurrences_treatment": measurements["source_fact_occurrences_treatment"],
            "neutral_envelopes_equal": True,
        },
        "parity": {
            "control_score": 100, "treatment_score": 100, "maximum_score": 100,
            "control_tests_passed": 4, "treatment_tests_passed": 4,
            "tests_total": 4, "score_delta": 0, "outcome": "tie",
            "control_final_tree_sha256": control_final,
            "treatment_final_tree_sha256": treatment_final,
            "final_trees_equal": True,
        },
        "integrity": {
            "initial_workspaces_equal": True, "investigation_workspace_unchanged": True,
            "installed_payload_unchanged": True, "private_evidence_reproduced": True,
            "verification_bound_artifacts_unchanged": True,
            "poison_path_marker_absent": True,
            "public_paths_embedded": False,
        },
        "execution": {
            "certifier_started_live_agent_sessions": 0,
            "certifier_started_provider_sessions": 0,
            "certifier_issued_provider_requests": 0,
            "certifier_started_pi_sessions": 0,
            "certifier_started_ollama_sessions": 0,
            "certifier_network_api_calls": 0,
            "host_activation_performed": False,
            "external_publication_performed": False,
        },
        "non_claims": {
            "mainframe_benefit": "not-measured", "agent_quality": "not-measured",
            "developer_productivity": "not-measured",
            "comparative_agent_performance": "not-measured",
            "real_provider_inference": "not-run", "network_containment": "not-established",
            "host_runtime_trust": "not-established",
            "same_local_account_isolation": "not-established",
            "generalization": "not-established",
        },
    }


def canary_commands(shell_name: str, project: Path) -> List[Tuple[str, str]]:
    quoted_project = shlex.quote(str(project))
    version_variable = "${BASH_VERSION}" if shell_name == "bash" else "${ZSH_VERSION}"
    # Each of the same four fresh shells asks the installed CLI to report the
    # Bash interpreter it actually selected before exercising AWM.  This binds
    # zsh cells to the separate Bash runtime that executes MAINFRAME, rather
    # than merely binding the outer login-shell executable.
    runtime_identity = "mainframe version || exit 93; "
    return [
        ("ensure", "printf 'CANARY_SHELL_VERSION=%s\\n' \"{}\"; {}"
         "mainframe awm project ensure --project {}".format(
             version_variable, runtime_identity, quoted_project)),
        ("checkpoint", "{}mainframe awm project checkpoint --project {} source_fact {} "
         "--importance high --tags installed-awm-canary".format(
             runtime_identity, quoted_project, shlex.quote(SOURCE_FACT))),
        ("discovery", "{}mainframe awm project discovery --project {} {} "
         "--importance high --tags installed-awm-canary".format(
             runtime_identity, quoted_project, shlex.quote(DISCOVERY_FACT))),
        ("handoff", "{}mainframe awm project handoff prepare --project {} next-agent "
         "--tokens {} --format json".format(
             runtime_identity, quoted_project, MAX_CONTINUATION_BYTES)),
    ]


def run_canary(archive: Path, checksum: Path, shell_name: str,
               private_output: Path, public_output: Path) -> None:
    private_output, private_parent = ensure_absent_output(
        private_output, "private evidence", True)
    public_output, public_parent = ensure_absent_output(
        public_output, "public evidence", False)
    if private_output == public_output:
        refuse("private and public evidence paths must differ")
    version, archive_binding, checksum_binding = parse_checksum(archive, checksum)
    platform_value = current_platform()
    shell, modern_bash = select_shell(shell_name)
    shell_binding = bind_native_executable(
        shell, platform_value, "selected shell executable")
    runtime_bash_binding = bind_native_executable(
        modern_bash, platform_value, "MAINFRAME runtime Bash executable")
    state_root = private_output.parent / (private_output.name + ".data")
    if state_root.exists() or state_root.is_symlink():
        refuse("private evidence data directory must be absent")
    state_root_identity = create_owned_directory(
        state_root, 0o700, "private evidence data directory", private_parent)
    try:
        artifacts_root = state_root / "artifacts"
        snapshots_root = state_root / "snapshots"
        runs_root = state_root / "runs"
        temporary = state_root / "tmp"
        artifacts_identity = create_owned_directory(
            artifacts_root, 0o700, "private artifacts directory", state_root_identity)
        snapshots_identity = create_owned_directory(
            snapshots_root, 0o700, "private snapshots directory", state_root_identity)
        runs_identity = create_owned_directory(
            runs_root, 0o700, "private runs directory", state_root_identity)
        create_owned_directory(
            temporary, 0o700, "private temporary directory", state_root_identity)
        state = install_candidate(
            state_root, archive, version, archive_binding,
            shell_name, shell, modern_bash, state_root_identity)
        install_root = state["install_root"]
        task_root = install_root / TASK_RELATIVE
        repository = task_root / "repository"
        investigate_prompt = task_root / "investigate.md"
        implement_prompt = task_root / "implement.md"
        task_path = task_root / "task.json"
        fake_transport = install_root / PROTOCOL_RELATIVE_PATHS["fake_transport"]
        grader = install_root / PROTOCOL_RELATIVE_PATHS["grader"]

        investigate_workspace = state_root / "investigate-workspace"
        copy_tree(repository, investigate_workspace, state_root_identity)
        investigate_before = private_tree_sha256(investigate_workspace)
        investigate_run = runs_root / "investigate"
        create_owned_directory(
            investigate_run, 0o700, "investigation run directory", runs_identity)
        investigate_artifacts = investigate_run / "artifacts"
        investigate_result = investigate_run / "result.json"
        investigate_request = transport_request(
            "investigate", investigate_workspace, investigate_prompt, None,
            investigate_artifacts, investigate_result, "01")
        investigate_value = run_fake_transport(
            fake_transport, investigate_request, investigate_run,
            "deterministic investigation transport")
        if private_tree_sha256(investigate_workspace) != investigate_before:
            refuse("investigation transport changed its read-only workspace")
        continuation_name = investigate_value.get("continuation_relative_path")
        if continuation_name != "agent-continuation.txt":
            refuse("investigation transport returned an unexpected continuation")
        raw_continuation = investigate_artifacts / continuation_name
        if read_regular(raw_continuation, "control raw continuation", MAX_CONTINUATION_BYTES)[0] != \
                SOURCE_FACT.encode("utf-8") + b"\n":
            refuse("investigation continuation differs from the registered source fact")

        control_workspace = state_root / "control-workspace"
        treatment_workspace = state_root / "treatment-workspace"
        copy_tree(investigate_workspace, control_workspace, state_root_identity)
        copy_tree(investigate_workspace, treatment_workspace, state_root_identity)
        control_initial = snapshot_tree(
            control_workspace, snapshots_root / "control-initial", snapshots_identity)
        treatment_initial = snapshot_tree(
            treatment_workspace, snapshots_root / "treatment-initial", snapshots_identity)
        control_after_investigate = snapshot_tree(
            control_workspace, snapshots_root / "control-after-investigate",
            snapshots_identity)
        treatment_after_investigate = snapshot_tree(
            treatment_workspace, snapshots_root / "treatment-after-investigate",
            snapshots_identity)
        if len({control_initial["sha256"], treatment_initial["sha256"],
                control_after_investigate["sha256"],
                treatment_after_investigate["sha256"]}) != 1:
            refuse("initial and post-investigation workspaces are not identical")

        # The public project-memory route deliberately ignores ambient
        # AWM_ROOT.  Materialize and snapshot the one owner-private tree its
        # fixed Python executor derives from XDG_STATE_HOME instead.
        state_home = state["home"] / ".local" / "state"
        state_home_identity = create_owned_directory(
            state_home, 0o700, "isolated state directory", state["local_identity"])
        control_plane_state = state_home / "mainframe"
        control_plane_state_identity = create_owned_directory(
            control_plane_state, 0o700, "control-plane state directory",
            state_home_identity)
        adapter_runtime = control_plane_state / ".mainframe-control-plane-runtime"
        adapter_runtime_identity = create_owned_directory(
            adapter_runtime, 0o700, "project-memory runtime directory",
            control_plane_state_identity)
        adapter_state = adapter_runtime / "project-memory-adapter-state"
        adapter_state_identity = create_owned_directory(
            adapter_state, 0o700, "project-memory adapter state directory",
            adapter_runtime_identity)
        awm_root = project_memory_awm_root(state["home"])
        create_owned_directory(
            awm_root, 0o700, "project-memory AWM directory",
            adapter_state_identity)
        awm_snapshots = snapshots_root / "awm"
        awm_snapshots_identity = create_owned_directory(
            awm_snapshots, 0o700, "AWM snapshots directory", snapshots_identity)
        awm_bindings = [snapshot_tree(
            awm_root, awm_snapshots / "before", awm_snapshots_identity)]
        process_records: List[Dict[str, Any]] = []
        handoff_stdout = ""
        shell_version = ""
        runtime_bash_versions: List[str] = []
        for sequence, (operation, command) in enumerate(
                canary_commands(shell_name, treatment_workspace), 1):
            record, stdout = run_shell_operation(
                sequence, operation, command, state, shell_name, shell,
                treatment_workspace, artifacts_root, temporary)
            process_records.append(record)
            bash_matches = re.findall(
                r"^  Bash version:\s+([^\r\n]+)$", stdout, re.MULTILINE)
            if len(bash_matches) != 1:
                refuse("fresh shell did not report one exact MAINFRAME Bash version")
            runtime_bash_versions.append(require_bash_version(
                bash_matches[0], "MAINFRAME runtime Bash version"))
            if sequence == 1:
                version_matches = re.findall(
                    r"^CANARY_SHELL_VERSION=([^\r\n]+)$", stdout, re.MULTILINE)
                if len(version_matches) != 1:
                    refuse("first fresh shell did not report its version")
                shell_version = require_string(
                    version_matches[0], "shell version", SHELL_VERSION_RE)
            if operation == "handoff":
                handoff_stdout = stdout
            awm_bindings.append(snapshot_tree(
                awm_root, awm_snapshots / "after-{}".format(operation),
                awm_snapshots_identity))
        if len({record["pid"] for record in process_records}) != 4:
            refuse("fresh login shell process identities are not distinct")
        if len(set(runtime_bash_versions)) != 1:
            refuse("fresh shells selected different MAINFRAME Bash runtimes")
        runtime_bash_version = runtime_bash_versions[0]
        if shell_name == "bash" and shell_version != runtime_bash_version:
            refuse("Bash login-shell and MAINFRAME runtime versions differ")
        bind_native_executable(
            shell, platform_value, "selected shell executable", shell_binding)
        bind_native_executable(
            modern_bash, platform_value, "MAINFRAME runtime Bash executable",
            runtime_bash_binding)

        handoff_lines = [line for line in handoff_stdout.splitlines()
                         if line.startswith("{") and line.endswith("}")]
        if len(handoff_lines) != 1:
            refuse("installed AWM emitted an ambiguous handoff payload")
        handoff_payload = handoff_lines[0].encode("utf-8") + b"\n"
        handoff_value = parse_json(handoff_payload, "installed AWM handoff")
        if handoff_payload.decode("utf-8").count(SOURCE_FACT) != 1:
            refuse("installed AWM handoff must contain the exact source fact once")
        checkpoint = handoff_value.get("context", {}).get("summary", {}).get(
            "checkpoints", {}).get("source_fact") if isinstance(handoff_value, dict) else None
        if checkpoint != SOURCE_FACT:
            refuse("installed AWM handoff did not preserve the source checkpoint")
        exported_handoff = artifacts_root / "exported-handoff.json"
        write_new(
            exported_handoff, handoff_payload, 0o600,
            "exported AWM handoff", artifacts_identity)

        neutral_payload = make_neutral_envelope(SOURCE_FACT)
        control_envelope = artifacts_root / "control-neutral-envelope.json"
        treatment_envelope = artifacts_root / "treatment-neutral-envelope.json"
        write_new(
            control_envelope, neutral_payload, 0o600,
            "control neutral envelope", artifacts_identity)
        write_new(
            treatment_envelope, neutral_payload, 0o600,
            "treatment neutral envelope", artifacts_identity)

        for arm_name, arm_suffix, workspace, envelope in (
                ("control", "02", control_workspace, control_envelope),
                ("treatment", "03", treatment_workspace, treatment_envelope)):
            arm_run = runs_root / (arm_name + "-implement")
            create_owned_directory(
                arm_run, 0o700, "{} implementation run directory".format(arm_name),
                runs_identity)
            arm_artifacts = arm_run / "artifacts"
            arm_result = arm_run / "result.json"
            request = transport_request(
                "implement", workspace, implement_prompt, envelope,
                arm_artifacts, arm_result, arm_suffix)
            value = run_fake_transport(
                fake_transport, request, arm_run,
                "deterministic {} implementation transport".format(arm_name))
            if value.get("continuation_relative_path") is not None:
                refuse("implementation transport returned an unexpected continuation")
            source_payload, _ = read_regular(
                workspace / "config_merge.py", "{} implementation".format(arm_name),
                MAX_JSON_BYTES)
            if source_payload != EXPECTED_SOLUTION:
                refuse("{} implementation differs from the registered solution".format(arm_name))

        control_final = snapshot_tree(
            control_workspace, snapshots_root / "control-final", snapshots_identity)
        treatment_final = snapshot_tree(
            treatment_workspace, snapshots_root / "treatment-final", snapshots_identity)
        if control_final["sha256"] != treatment_final["sha256"]:
            refuse("control and treatment final workspaces differ")
        control_grade_run = runs_root / "control-grade"
        treatment_grade_run = runs_root / "treatment-grade"
        create_owned_directory(
            control_grade_run, 0o700, "control grader run directory", runs_identity)
        create_owned_directory(
            treatment_grade_run, 0o700, "treatment grader run directory", runs_identity)
        control_grade, control_grade_stdout = run_grader(
            grader, control_workspace, control_grade_run, "control grader")
        treatment_grade, treatment_grade_stdout = run_grader(
            grader, treatment_workspace, treatment_grade_run, "treatment grader")
        if control_grade != treatment_grade:
            refuse("control and treatment grader results differ")
        if state["poison_marker"].exists() or state["poison_marker"].is_symlink():
            refuse("a forbidden runtime command was invoked")
        installed_tree_after = package_tree_sha256(install_root)
        if installed_tree_after != state["installed_tree_sha256"]:
            refuse("installed candidate payload changed during the canary")
        bind_native_executable(
            shell, platform_value, "selected shell executable", shell_binding)
        bind_native_executable(
            modern_bash, platform_value, "MAINFRAME runtime Bash executable",
            runtime_bash_binding)

        protocol = protocol_bindings(install_root)
        require_executing_certifier(protocol["certifier"])
        private: Dict[str, Any] = {
            "schema_version": 1, "kind": PRIVATE_KIND, "claim_scope": CLAIM_SCOPE,
            "candidate": {
                "version": version, "archive": archive_binding,
                "checksum": checksum_binding, "install_root": str(install_root),
                "installed_tree": {"path": str(install_root),
                                   "algorithm": PACKAGE_TREE_ALGORITHM,
                                   "sha256": installed_tree_after},
                "install_receipt": file_binding(
                    state["receipt"], "install receipt", MAX_JSON_BYTES, "0600"),
                "installed_payload": INSTALLED_PAYLOAD_STATUS,
                "install_receipt_verified": True,
            },
            "platform": platform_value,
            "shell": {
                "name": shell_name,
                "executable": shell_binding,
                "version": shell_version, "fresh_login_shell_count": 4,
                "distinct_processes": True, "isolated_profile_discovery": True,
                "runtime_bash": {
                    "executable": runtime_bash_binding,
                    "version": runtime_bash_version,
                },
            },
            "protocol": protocol,
            "processes": process_records,
            "mechanisms": {
                "control": {
                    "raw_continuation": file_binding(
                        raw_continuation, "control raw continuation", MAX_CONTINUATION_BYTES),
                    "neutral_envelope": file_binding(
                        control_envelope, "control neutral envelope", MAX_CONTINUATION_BYTES),
                },
                "treatment": {
                    "awm_before": awm_bindings[0],
                    "awm_after_ensure": awm_bindings[1],
                    "awm_after_checkpoint": awm_bindings[2],
                    "awm_after_discovery": awm_bindings[3],
                    "awm_after_handoff": awm_bindings[4],
                    "exported_handoff": file_binding(
                        exported_handoff, "exported AWM handoff", MAX_OUTPUT_BYTES),
                    "neutral_envelope": file_binding(
                        treatment_envelope, "treatment neutral envelope",
                        MAX_CONTINUATION_BYTES),
                },
                "neutral_envelopes_equal": True,
            },
            "artifacts": {
                "task": file_binding(task_path, "task contract", MAX_JSON_BYTES),
                "investigate_prompt": file_binding(
                    investigate_prompt, "investigate prompt", MAX_JSON_BYTES),
                "implement_prompt": file_binding(
                    implement_prompt, "implement prompt", MAX_JSON_BYTES),
                "fake_transport": file_binding(
                    fake_transport, "fake transport", MAX_JSON_BYTES),
                "grader": file_binding(grader, "grader", MAX_JSON_BYTES),
                "control_workspace_initial": control_initial,
                "control_workspace_after_investigate": control_after_investigate,
                "control_workspace_final": control_final,
                "treatment_workspace_initial": treatment_initial,
                "treatment_workspace_after_investigate": treatment_after_investigate,
                "treatment_workspace_final": treatment_final,
                "control_grader_stdout": file_binding(
                    control_grade_stdout, "control grader stdout", 4096),
                "treatment_grader_stdout": file_binding(
                    treatment_grade_stdout, "treatment grader stdout", 4096),
            },
            "measurements": {
                "source_fact_occurrences_control": 1,
                "source_fact_occurrences_treatment": 1,
                "neutral_envelopes_equal": True,
                "control_score": 100, "treatment_score": 100, "maximum_score": 100,
                "control_tests_passed": 4, "treatment_tests_passed": 4,
                "tests_total": 4, "score_delta": 0, "outcome": "tie",
                "final_trees_equal": True, "initial_workspaces_equal": True,
                "investigation_workspace_unchanged": True,
                "installed_payload_unchanged": True,
                "poison_path_marker_absent": True, "public_paths_embedded": False,
            },
            "execution": {
                "fresh_login_shell_processes": 4, "fake_transport_processes": 3,
                "grader_processes": 2, "certifier_started_top_level_processes": 9,
                "certifier_started_live_agent_sessions": 0,
                "certifier_started_provider_sessions": 0,
                "certifier_issued_provider_requests": 0,
                "certifier_started_pi_sessions": 0,
                "certifier_started_ollama_sessions": 0,
                "certifier_network_api_calls": 0,
                "host_activation_performed": False,
                "external_publication_performed": False,
            },
            "public_projection_sha256": "0" * 64,
        }
        public = public_projection(private)
        reject_public_paths(public)
        private["public_projection_sha256"] = sha256_bytes(canonical_bytes(public))
        write_new(
            private_output, canonical_bytes(private) + b"\n", 0o600,
            "private evidence", private_parent)
        try:
            reproduced = reproduce_public_from_private(
                archive, checksum, shell_name, private_output)
            if reproduced != public:
                refuse("private replay differs from the anticipated public projection")
            write_new(
                public_output, canonical_bytes(reproduced) + b"\n", 0o644,
                "public evidence", public_parent)
        except Exception:
            # A same-UID process can substitute a pathname between any final
            # identity check and unlink. Retaining an owner-private partial
            # record is safer than ever deleting an object by pathname.
            raise
    except Exception:
        # Likewise, never recursively remove a failure-state pathname. The
        # 0700 state directory is retained for diagnosis and recoverable
        # caller-directed cleanup after its identity is reviewed.
        raise


def require_fixed_private_values(private: Dict[str, Any]) -> None:
    exact_keys(private, PRIVATE_KEYS, "private evidence")
    if private["schema_version"] != 1 or private["kind"] != PRIVATE_KIND or \
            private["claim_scope"] != CLAIM_SCOPE:
        refuse("private evidence identity differs from the supported protocol")
    expected_measurements = {
        "source_fact_occurrences_control": 1,
        "source_fact_occurrences_treatment": 1,
        "neutral_envelopes_equal": True, "control_score": 100,
        "treatment_score": 100, "maximum_score": 100,
        "control_tests_passed": 4, "treatment_tests_passed": 4,
        "tests_total": 4, "score_delta": 0, "outcome": "tie",
        "final_trees_equal": True, "initial_workspaces_equal": True,
        "investigation_workspace_unchanged": True,
        "installed_payload_unchanged": True,
        "poison_path_marker_absent": True, "public_paths_embedded": False,
    }
    if private.get("measurements") != expected_measurements:
        refuse("private measurements differ from the closed conformance contract")
    expected_execution = {
        "fresh_login_shell_processes": 4, "fake_transport_processes": 3,
        "grader_processes": 2, "certifier_started_top_level_processes": 9,
        "certifier_started_live_agent_sessions": 0,
        "certifier_started_provider_sessions": 0,
        "certifier_issued_provider_requests": 0,
        "certifier_started_pi_sessions": 0,
        "certifier_started_ollama_sessions": 0,
        "certifier_network_api_calls": 0,
        "host_activation_performed": False,
        "external_publication_performed": False,
    }
    if private.get("execution") != expected_execution:
        refuse("private execution counters differ from the closed contract")


def validate_private_record(private: Dict[str, Any], archive: Path, checksum: Path,
                            shell_name: str,
                            private_evidence: Path) -> Dict[str, Any]:
    require_fixed_private_values(private)
    version, archive_binding, checksum_binding = parse_checksum(archive, checksum)
    candidate = exact_keys(
        private["candidate"],
        ("version", "archive", "checksum", "install_root", "installed_tree",
         "install_receipt", "installed_payload", "install_receipt_verified"),
        "private candidate")
    if candidate["version"] != version or candidate["archive"] != archive_binding or \
            candidate["checksum"] != checksum_binding or \
            candidate["installed_payload"] != INSTALLED_PAYLOAD_STATUS or \
            candidate["install_receipt_verified"] is not True:
        refuse("private candidate does not bind the selected archive")
    install_root = require_directory(
        Path(require_string(candidate["install_root"], "installed root")),
        "installed root", private=True)
    state_root = install_root.parent.parent
    expected_state_root = private_evidence.parent / (private_evidence.name + ".data")
    if state_root != expected_state_root:
        refuse("private run data is not adjacent to its private evidence record")
    awm_root = project_memory_awm_root(state_root / "home")
    private_directories = (
        state_root, state_root / "artifacts", state_root / "snapshots",
        state_root / "snapshots" / "awm", state_root / "runs",
        state_root / "tmp", state_root / "home", state_root / "home" / ".local",
        state_root / "home" / ".local" / "state",
        state_root / "home" / ".local" / "state" / "mainframe",
        state_root / "home" / ".local" / "state" / "mainframe"
        / ".mainframe-control-plane-runtime",
        state_root / "home" / ".local" / "state" / "mainframe"
        / ".mainframe-control-plane-runtime" / "project-memory-adapter-state",
        awm_root,
    )
    for directory in private_directories:
        metadata = require_directory(
            directory, "private run directory", private=True).lstat()
        if path_mode(metadata) != "0700":
            refuse("private run directory mode must be 0700")
    expected_install_root = state_root / "home" / "mainframe-install"
    if install_root != expected_install_root:
        refuse("installed root is not the exact private run layout")
    if validate_tree_binding(candidate["installed_tree"], "installed tree",
                             PACKAGE_TREE_ALGORITHM) != install_root:
        refuse("installed tree root differs from candidate install root")
    receipt_observed = validate_bound_file(
        candidate["install_receipt"], "install receipt", MAX_JSON_BYTES)
    receipt_path = receipt_observed["path"]
    if receipt_path != install_root / ".mainframe-install-receipt.json":
        refuse("install receipt has an unexpected path")
    inventory = archive_inventory(
        archive, expected_binding=archive_binding)
    validate_version(install_root, version)
    _, manifest_sha256 = parse_manifest(install_root, inventory)
    expected_receipt = install_receipt_value(
        version, archive_binding["sha256"], manifest_sha256, install_root,
        install_root.parent / ".local" / "bin",
        install_root.parent / ".local" / "bin" / "mainframe")
    receipt_value = exact_keys(
        parse_bound_json(receipt_observed, "install receipt"),
        ("schema_version", "install_method", "version", "archive_sha256",
         "manifest_sha256", "install_dir", "bin_dir", "cli_link", "installed_at"),
        "install receipt")
    for key in expected_receipt:
        if key != "installed_at" and receipt_value[key] != expected_receipt[key]:
            refuse("install receipt {} differs from selected candidate".format(key))
    timestamp = require_string(receipt_value["installed_at"], "install receipt timestamp")
    if re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z",
                    timestamp) is None:
        refuse("install receipt timestamp is not canonical UTC")
    verify_installed_payload(install_root, inventory)

    if private["platform"] != current_platform():
        refuse("private platform differs from the current native tuple")
    shell_value = exact_keys(
        private["shell"],
        ("name", "executable", "version", "runtime_bash", "fresh_login_shell_count",
         "distinct_processes", "isolated_profile_discovery"), "private shell")
    if shell_value["name"] != shell_name or shell_value["fresh_login_shell_count"] != 4 or \
            shell_value["distinct_processes"] is not True or \
            shell_value["isolated_profile_discovery"] is not True:
        refuse("private shell contract differs from the selected shell")
    selected_shell, modern_bash = select_shell(shell_name)
    selected_shell_observed = validate_bound_file(
        shell_value["executable"], "selected shell", MAX_ARCHIVE_BYTES)
    if selected_shell_observed["path"] != selected_shell:
        refuse("private shell executable differs from selected shell")
    if selected_shell_observed["metadata"].st_mode & \
            (stat.S_IWGRP | stat.S_IWOTH):
        refuse("selected shell must not be group- or other-writable")
    require_observed_executable_architecture(
        selected_shell_observed, private["platform"], "selected shell")
    shell_version = require_string(
        shell_value["version"], "shell version", SHELL_VERSION_RE)
    runtime_bash_value = exact_keys(
        shell_value["runtime_bash"], ("executable", "version"),
        "private runtime Bash")
    runtime_bash_observed = validate_bound_file(
        runtime_bash_value["executable"], "MAINFRAME runtime Bash",
        MAX_ARCHIVE_BYTES)
    if runtime_bash_observed["path"] != modern_bash:
        refuse("private runtime Bash executable differs from selected runtime")
    if runtime_bash_observed["metadata"].st_mode & \
            (stat.S_IWGRP | stat.S_IWOTH):
        refuse("MAINFRAME runtime Bash must not be group- or other-writable")
    require_observed_executable_architecture(
        runtime_bash_observed, private["platform"], "MAINFRAME runtime Bash")
    runtime_bash_version = require_bash_version(
        runtime_bash_value["version"], "MAINFRAME runtime Bash version")
    if shell_name == "bash" and (
            selected_shell_observed["binding"] != runtime_bash_observed["binding"] or
            shell_version != runtime_bash_version):
        refuse("Bash login-shell and MAINFRAME runtime identities differ")
    home = state_root / "home"
    bin_dir = home / ".local" / "bin"
    cli_link = bin_dir / "mainframe"
    expected_cli = install_root / "bin" / "mainframe"
    try:
        cli_metadata = cli_link.lstat()
        cli_target = os.readlink(str(cli_link))
    except OSError:
        refuse("installed CLI link differs from the isolated runtime route")
    if not stat.S_ISLNK(cli_metadata.st_mode) or cli_metadata.st_uid != os.geteuid() or \
            cli_target != str(expected_cli):
        refuse("installed CLI link differs from the isolated runtime route")
    poison_dir = state_root / "poison-bin"
    runtime_path = fixed_runtime_path(
        bin_dir, poison_dir, selected_shell, modern_bash)
    profile_nonce = sha256_bytes(
        b"MAINFRAME-INSTALLED-AWM-PROFILE-V1\0" +
        archive_binding["sha256"].encode("ascii") + b"\0" +
        shell_name.encode("ascii"))
    profile_path, profile_bytes, login = profile_payload(
        shell_name, install_root, modern_bash, runtime_path, profile_nonce)
    try:
        profile_observed = read_bound_file(
            profile_path, "isolated shell profile", MAX_JSON_BYTES, "0600")
    except CanaryError:
        refuse("isolated shell profile differs from the certified discovery route")
    if profile_observed["payload"] != profile_bytes:
        refuse("isolated shell profile differs from the certified discovery route")
    if login is not None:
        try:
            login_observed = read_bound_file(
                login[0], "isolated Bash login profile", MAX_JSON_BYTES, "0600")
        except CanaryError:
            refuse("isolated shell profile differs from the certified discovery route")
        if login_observed["payload"] != login[1]:
            refuse("isolated shell profile differs from the certified discovery route")

    expected_protocol = protocol_bindings(install_root)
    if private["protocol"] != expected_protocol:
        refuse("private protocol bindings differ from the installed candidate")
    require_executing_certifier(expected_protocol["certifier"])
    processes = private["processes"]
    if not isinstance(processes, list) or len(processes) != 4:
        refuse("private process list must contain four records")
    treatment_workspace = state_root / "treatment-workspace"
    expected_commands = canary_commands(shell_name, treatment_workspace)
    seen_pids = set()
    handoff_stdout_payload: Optional[bytes] = None
    for index, (record, expected) in enumerate(zip(processes, expected_commands), 1):
        record = exact_keys(
            record, ("sequence", "operation", "pid", "command_sha256", "stdout",
                     "stderr", "exit_code"), "process record")
        operation, command = expected
        if record["sequence"] != index or record["operation"] != operation or \
                record["exit_code"] != 0 or \
                record["command_sha256"] != sha256_bytes(command.encode("utf-8")) or \
                isinstance(record["pid"], bool) or not isinstance(record["pid"], int) or \
                record["pid"] < 1 or record["pid"] in seen_pids:
            refuse("private process record differs from the ordered shell contract")
        seen_pids.add(record["pid"])
        expected_stdout = state_root / "artifacts" / \
            "shell-{}-{}.stdout".format(index, operation)
        expected_stderr = state_root / "artifacts" / \
            "shell-{}-{}.stderr".format(index, operation)
        stdout_observed = validate_bound_file(
            record["stdout"], "shell stdout", MAX_OUTPUT_BYTES)
        stderr_observed = validate_bound_file(
            record["stderr"], "shell stderr", MAX_OUTPUT_BYTES)
        stdout_path = stdout_observed["path"]
        stderr_path = stderr_observed["path"]
        if stdout_path != expected_stdout or stderr_path != expected_stderr:
            refuse("shell process streams are not in the exact private run layout")
        stdout_text = decode_bound_text(stdout_observed, "shell stdout")
        pid_matches = re.findall(
            r"^CANARY_PID=([1-9][0-9]*)$", stdout_text, re.MULTILINE)
        if len(pid_matches) != 1 or int(pid_matches[0]) != record["pid"]:
            refuse("shell output does not bind its exact process identity")
        bash_matches = re.findall(
            r"^  Bash version:\s+([^\r\n]+)$", stdout_text, re.MULTILINE)
        if len(bash_matches) != 1 or require_bash_version(
                bash_matches[0], "reported MAINFRAME runtime Bash version") != \
                runtime_bash_version:
            refuse("shell output does not bind its exact MAINFRAME Bash runtime")
        if index == 1:
            version_matches = re.findall(
                r"^CANARY_SHELL_VERSION=([^\r\n]+)$", stdout_text, re.MULTILINE)
            if len(version_matches) != 1 or \
                    require_string(version_matches[0], "reported shell version",
                                   SHELL_VERSION_RE) != shell_version:
                refuse("private shell version differs from the first fresh shell")
        if operation == "handoff":
            handoff_lines = [line for line in stdout_text.splitlines()
                             if line.startswith("{") and line.endswith("}")]
            if len(handoff_lines) != 1:
                refuse("bound handoff shell stdout has an ambiguous payload")
            handoff_stdout_payload = handoff_lines[0].encode("utf-8") + b"\n"

    mechanisms = exact_keys(
        private["mechanisms"], ("control", "treatment", "neutral_envelopes_equal"),
        "private mechanisms")
    if mechanisms["neutral_envelopes_equal"] is not True:
        refuse("neutral envelope parity is false")
    control = exact_keys(
        mechanisms["control"], ("raw_continuation", "neutral_envelope"),
        "control mechanism")
    treatment = exact_keys(
        mechanisms["treatment"],
        ("awm_before", "awm_after_ensure", "awm_after_checkpoint",
         "awm_after_discovery", "awm_after_handoff", "exported_handoff",
         "neutral_envelope"), "treatment mechanism")
    raw_observed = validate_bound_file(
        control["raw_continuation"], "control continuation", MAX_CONTINUATION_BYTES)
    raw_path = raw_observed["path"]
    if raw_observed["payload"] != \
            SOURCE_FACT.encode("utf-8") + b"\n":
        refuse("control continuation differs from the source fact")
    control_envelope_observed = validate_bound_file(
        control["neutral_envelope"], "control envelope", MAX_CONTINUATION_BYTES)
    treatment_envelope_observed = validate_bound_file(
        treatment["neutral_envelope"], "treatment envelope", MAX_CONTINUATION_BYTES)
    control_envelope = control_envelope_observed["path"]
    treatment_envelope = treatment_envelope_observed["path"]
    expected_control_paths = {
        "raw": state_root / "runs" / "investigate" / "artifacts" /
            "agent-continuation.txt",
        "control_envelope": state_root / "artifacts" /
            "control-neutral-envelope.json",
        "treatment_envelope": state_root / "artifacts" /
            "treatment-neutral-envelope.json",
    }
    if raw_path != expected_control_paths["raw"] or \
            control_envelope != expected_control_paths["control_envelope"] or \
            treatment_envelope != expected_control_paths["treatment_envelope"]:
        refuse("mechanism artifacts are not in the exact private run layout")
    expected_envelope = make_neutral_envelope(SOURCE_FACT)
    if control_envelope_observed["payload"] != expected_envelope or \
            treatment_envelope_observed["payload"] != expected_envelope:
        refuse("neutral envelopes differ from the registered context")
    expected_awm_paths = {
        "awm_before": state_root / "snapshots" / "awm" / "before",
        "awm_after_ensure": state_root / "snapshots" / "awm" / "after-ensure",
        "awm_after_checkpoint": state_root / "snapshots" / "awm" / "after-checkpoint",
        "awm_after_discovery": state_root / "snapshots" / "awm" / "after-discovery",
        "awm_after_handoff": state_root / "snapshots" / "awm" / "after-handoff",
    }
    observed_awm_paths = []
    observed_awm_snapshots: Dict[str, Dict[str, Any]] = {}
    for key, expected_path in expected_awm_paths.items():
        observed_snapshot = validate_tree_snapshot(
            treatment[key], key, PRIVATE_TREE_ALGORITHM)
        observed_path = observed_snapshot["root"]
        if observed_path != expected_path:
            refuse("{} is not in the exact private run layout".format(key))
        observed_awm_paths.append(observed_path)
        observed_awm_snapshots[key] = observed_snapshot
    if len(set(observed_awm_paths)) != len(observed_awm_paths):
        refuse("AWM snapshot roots must be distinct")
    if len({treatment[key]["sha256"] for key in expected_awm_paths}) != \
            len(expected_awm_paths):
        refuse("AWM snapshot stages must have distinct tree identities")
    state_handoff_payload = validate_awm_snapshot_sequence(
        observed_awm_snapshots, treatment_workspace)
    handoff_observed = validate_bound_file(
        treatment["exported_handoff"], "exported handoff", MAX_OUTPUT_BYTES)
    handoff_path = handoff_observed["path"]
    if handoff_path != state_root / "artifacts" / "exported-handoff.json":
        refuse("exported handoff is not in the exact private run layout")
    handoff_payload = handoff_observed["payload"]
    if handoff_stdout_payload is None or handoff_payload != handoff_stdout_payload:
        refuse("exported handoff differs from the bound fresh-shell stdout")
    if state_handoff_payload + b"\n" != handoff_payload:
        refuse("AWM handoff state differs from exported handoff")
    if handoff_payload.decode("utf-8", errors="strict").count(SOURCE_FACT) != 1:
        refuse("exported handoff does not contain one exact source fact")
    handoff = parse_json(handoff_payload, "exported handoff")
    if not isinstance(handoff, dict) or \
            handoff.get("context", {}).get("summary", {}).get("checkpoints", {}).get(
            "source_fact") != SOURCE_FACT:
        refuse("exported handoff lost the source checkpoint")

    artifacts = exact_keys(
        private["artifacts"],
        ("task", "investigate_prompt", "implement_prompt", "fake_transport", "grader",
         "control_workspace_initial", "control_workspace_after_investigate",
         "control_workspace_final", "treatment_workspace_initial",
         "treatment_workspace_after_investigate", "treatment_workspace_final",
         "control_grader_stdout", "treatment_grader_stdout"), "private artifacts")
    artifact_observations: Dict[str, Dict[str, Any]] = {}
    for key in ("task", "investigate_prompt", "implement_prompt", "fake_transport",
                "grader", "control_grader_stdout", "treatment_grader_stdout"):
        artifact_observations[key] = validate_bound_file(
            artifacts[key], key, MAX_JSON_BYTES)
    expected_artifact_paths = {
        "task": install_root / TASK_RELATIVE / "task.json",
        "investigate_prompt": install_root / TASK_RELATIVE / "investigate.md",
        "implement_prompt": install_root / TASK_RELATIVE / "implement.md",
        "fake_transport": install_root / PROTOCOL_RELATIVE_PATHS["fake_transport"],
        "grader": install_root / PROTOCOL_RELATIVE_PATHS["grader"],
        "control_grader_stdout": state_root / "runs" / "control-grade" / "stdout",
        "treatment_grader_stdout": state_root / "runs" / "treatment-grade" / "stdout",
    }
    for key, expected_path in expected_artifact_paths.items():
        if Path(artifacts[key]["path"]) != expected_path:
            refuse("{} is not the installed protocol artifact".format(key))
    tree_keys = (
        "control_workspace_initial", "control_workspace_after_investigate",
        "control_workspace_final", "treatment_workspace_initial",
        "treatment_workspace_after_investigate", "treatment_workspace_final")
    expected_workspace_paths = {
        "control_workspace_initial": state_root / "snapshots" / "control-initial",
        "control_workspace_after_investigate": state_root / "snapshots" /
            "control-after-investigate",
        "control_workspace_final": state_root / "snapshots" / "control-final",
        "treatment_workspace_initial": state_root / "snapshots" / "treatment-initial",
        "treatment_workspace_after_investigate": state_root / "snapshots" /
            "treatment-after-investigate",
        "treatment_workspace_final": state_root / "snapshots" / "treatment-final",
    }
    observed_workspace_paths = []
    for key in tree_keys:
        observed_path = validate_tree_binding(
            artifacts[key], key, PRIVATE_TREE_ALGORITHM)
        if observed_path != expected_workspace_paths[key]:
            refuse("{} is not in the exact private run layout".format(key))
        observed_workspace_paths.append(observed_path)
    if len(set(observed_workspace_paths)) != len(observed_workspace_paths):
        refuse("workspace snapshot roots must be distinct")
    initial_digests = {artifacts[key]["sha256"] for key in tree_keys[:2] + tree_keys[3:5]}
    if len(initial_digests) != 1 or \
            artifacts["control_workspace_final"]["sha256"] != \
            artifacts["treatment_workspace_final"]["sha256"]:
        refuse("workspace parity bindings differ")
    for key in ("control_grader_stdout", "treatment_grader_stdout"):
        grade = parse_bound_json(artifact_observations[key], key)
        if grade != {"maximum_score": 100, "score": 100, "solved": True,
                     "tests_passed": 4, "tests_total": 4}:
            refuse("grader record differs from the registered result")
    for key in ("control_workspace_final", "treatment_workspace_final"):
        source = Path(artifacts[key]["path"]) / "config_merge.py"
        if read_regular(source, "final implementation", MAX_JSON_BYTES)[0] != EXPECTED_SOLUTION:
            refuse("final implementation differs from the registered solution")
    repository_digest = private_tree_sha256(
        install_root / TASK_RELATIVE / "repository")
    for key in (
            "control_workspace_initial", "control_workspace_after_investigate",
            "treatment_workspace_initial", "treatment_workspace_after_investigate"):
        if artifacts[key]["sha256"] != repository_digest:
            refuse("investigation workspace differs from the installed task baseline")
    marker = state_root / "forbidden-runtime-invoked"
    if marker.exists() or marker.is_symlink():
        refuse("forbidden runtime marker exists")
    return public_projection(private)


def reproduce_public_from_private(archive: Path, checksum: Path, shell_name: str,
                                  private_evidence: Path) -> Dict[str, Any]:
    """Reopen private evidence and perform one bounded, read-only reproduction."""
    private_evidence = canonical_existing_path(private_evidence, "private evidence")
    require_directory(private_evidence.parent, "private evidence directory", private=True)
    private_observed = read_bound_file(
        private_evidence, "private evidence", MAX_JSON_BYTES, "0600")
    private = parse_bound_json(private_observed, "private evidence")
    if not isinstance(private, dict):
        refuse("private evidence must be an object")
    if file_binding(private_evidence, "private evidence", MAX_JSON_BYTES, "0600") != \
            private_observed["binding"]:
        refuse("private evidence changed during replay")
    state_root = private_evidence.parent / (private_evidence.name + ".data")
    shell, runtime_bash = select_shell(shell_name)
    before = verification_surface_binding(
        archive, checksum, private_evidence, state_root, shell, runtime_bash)
    public = validate_private_record(
        private, archive, checksum, shell_name, private_evidence)
    reject_public_paths(public)
    after = verification_surface_binding(
        archive, checksum, private_evidence, state_root, shell, runtime_bash)
    if before != after:
        refuse("verification-bound artifacts changed during private replay")
    if file_binding(private_evidence, "private evidence", MAX_JSON_BYTES, "0600") != \
            private_observed["binding"]:
        refuse("private evidence changed during replay")
    if private.get("public_projection_sha256") != sha256_bytes(canonical_bytes(public)):
        refuse("private public-projection digest differs")
    return public


def verify_canary(archive: Path, checksum: Path, shell_name: str,
                  private_evidence: Path, evidence: Path) -> None:
    private_evidence = canonical_existing_path(private_evidence, "private evidence")
    evidence = canonical_existing_path(evidence, "public evidence")
    public_observed = read_bound_file(
        evidence, "public evidence", MAX_JSON_BYTES, "0644")
    public = parse_bound_json(public_observed, "public evidence")
    if not isinstance(public, dict):
        refuse("public evidence must be an object")
    if file_binding(evidence, "public evidence", MAX_JSON_BYTES, "0644") != \
            public_observed["binding"]:
        refuse("public evidence changed during verification")
    expected_public = reproduce_public_from_private(
        archive, checksum, shell_name, private_evidence)
    exact_keys(public, PUBLIC_KEYS, "public evidence")
    if public != expected_public:
        refuse("public evidence differs from the private reproducible projection")
    reject_public_paths(public)
    if file_binding(evidence, "public evidence", MAX_JSON_BYTES, "0644") != \
            public_observed["binding"]:
        refuse("public evidence changed during verification")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Certify installed-candidate AWM handoff mechanism conformance")
    subparsers = parser.add_subparsers(dest="action", required=True)
    run_parser = subparsers.add_parser("run", help="run the offline installed canary")
    verify_parser = subparsers.add_parser("verify", help="verify evidence read-only")
    for child in (run_parser, verify_parser):
        child.add_argument("--archive", required=True, type=Path)
        child.add_argument("--checksum", required=True, type=Path)
        child.add_argument("--shell", required=True, choices=("bash", "zsh"))
    run_parser.add_argument("--private-output", required=True, type=Path)
    run_parser.add_argument("--output", required=True, type=Path)
    verify_parser.add_argument("--private-evidence", required=True, type=Path)
    verify_parser.add_argument("--evidence", required=True, type=Path)
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    arguments = parser.parse_args(argv)
    try:
        if arguments.action == "run":
            run_canary(
                arguments.archive, arguments.checksum, arguments.shell,
                arguments.private_output, arguments.output)
        else:
            verify_canary(
                arguments.archive, arguments.checksum, arguments.shell,
                arguments.private_evidence, arguments.evidence)
    except CanaryError as error:
        print("installed AWM handoff canary refused: {}".format(error), file=sys.stderr)
        return 2
    except (OSError, ValueError, TypeError, KeyError, IndexError, UnicodeError) as error:
        # Malformed or concurrently changed caller-controlled evidence must
        # fail as a bounded refusal, not escape as a traceback.
        print("installed AWM handoff canary refused: malformed or changed input: {}".format(
            error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

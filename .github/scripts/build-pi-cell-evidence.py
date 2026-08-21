#!/usr/bin/env python3
"""Create or verify one canonical, exact-candidate Pi CI-cell receipt."""

from __future__ import annotations

import argparse
import ctypes
import errno
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import tempfile
from typing import Any, NoReturn


TREE_DOMAIN = b"MAINFRAME-PACKAGE-TREE-SHA256-V1\0"
RUNTIME_TREE_DOMAIN = b"MAINFRAME-PI-RUNTIME-TREE-SHA256-V1\0"
RUNTIME_SNAPSHOT_KIND = "mainframe-pi-pre-test-runtime-snapshot"
NODE_BINDING_ALGORITHM = "MAINFRAME-NATIVE-EXECUTABLE-BINDING-V1"
NODE_BINDING_KIND = "mainframe-pi-pre-test-node-binding"
NATIVE_EXECUTABLE_VALIDATOR_RELATIVE = Path(
    "scripts/dev/native-host/validate-native-executable.py"
)
TRUSTED_UNAME = Path("/usr/bin/uname")
TRUSTED_GETCONF = Path("/usr/bin/getconf")
TRUSTED_GIT = Path("/usr/bin/git")
TRUSTED_COMMAND_ENV = {"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C"}
VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
GIT_SHA_RE = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
REPOSITORY_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
REF_RE = re.compile(r"^refs/(?:heads|tags|pull)/[A-Za-z0-9][A-Za-z0-9._/-]*$")
NPM_INTEGRITY_RE = re.compile(r"^sha512-[A-Za-z0-9+/]+={0,2}$")
TOKEN_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
TEST_PATH_RE = re.compile(r"^tests/[A-Za-z0-9_.-]+\.bats$")
MAX_JSON_BYTES = 2 * 1024 * 1024
MAX_TEXT_BYTES = 2 * 1024 * 1024
MAX_ARCHIVE_BYTES = 1024 * 1024 * 1024
MAX_EXECUTABLE_BYTES = 512 * 1024 * 1024


class EvidenceError(ValueError):
    """A fail-closed cell-evidence violation."""


def fail(message: str) -> NoReturn:
    raise SystemExit(f"invalid Pi cell evidence: {message}")


def exact_keys(value: Any, expected: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise EvidenceError(f"{label} must be an object")
    actual = set(value)
    if actual != expected:
        raise EvidenceError(
            f"{label} keys differ: missing={sorted(expected - actual)} "
            f"extra={sorted(actual - expected)}"
        )
    return value


def strict_equal(left: Any, right: Any) -> bool:
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return set(left) == set(right) and all(
            strict_equal(left[key], right[key]) for key in left
        )
    if isinstance(left, list):
        return len(left) == len(right) and all(
            strict_equal(a, b) for a, b in zip(left, right)
        )
    return left == right


def read_regular_bytes(path: Path, maximum: int, label: str) -> bytes:
    descriptor = -1
    try:
        flags = os.O_RDONLY
        if hasattr(os, "O_CLOEXEC"):
            flags |= os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = os.open(path, flags)
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise EvidenceError(f"{label} must be a regular non-symlink file: {path}")
        if before.st_nlink != 1:
            raise EvidenceError(f"{label} must not be hard-linked: {path}")
        if before.st_size > maximum:
            raise EvidenceError(f"{label} exceeds {maximum} bytes: {path}")
        chunks: list[bytes] = []
        remaining = maximum + 1
        while remaining:
            chunk = os.read(descriptor, min(1024 * 1024, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        raw = b"".join(chunks)
        after = os.fstat(descriptor)
    except OSError as error:
        raise EvidenceError(f"could not read {label}: {path}: {error}") from error
    finally:
        if descriptor >= 0:
            os.close(descriptor)
    if len(raw) > maximum or len(raw) != before.st_size:
        raise EvidenceError(f"{label} is oversized, truncated, or dataless: {path}")
    identity_before = (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
    identity_after = (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
    if identity_before != identity_after or after.st_nlink != 1:
        raise EvidenceError(f"{label} changed while it was read: {path}")
    return raw


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def load_json(path: Path, label: str) -> tuple[dict[str, Any], bytes]:
    raw = read_regular_bytes(path, MAX_JSON_BYTES, label)

    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise EvidenceError(f"{label} contains duplicate key {key!r}")
            result[key] = value
        return result

    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=reject_duplicates)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise EvidenceError(f"{label} is not strict UTF-8 JSON: {error}") from error
    if not isinstance(value, dict):
        raise EvidenceError(f"{label} root must be an object")
    return value, raw


def canonical_json(value: dict[str, Any]) -> bytes:
    return (
        json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode("utf-8")


def strict_json_bytes(raw: bytes, label: str) -> dict[str, Any]:
    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise EvidenceError(f"{label} contains duplicate key {key!r}")
            result[key] = value
        return result

    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=reject_duplicates)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise EvidenceError(f"{label} is not strict UTF-8 JSON: {error}") from error
    if not isinstance(value, dict):
        raise EvidenceError(f"{label} root must be an object")
    return value


def canonical_relative_path(value: str, label: str) -> PurePosixPath:
    candidate = PurePosixPath(value)
    if (
        not value
        or candidate.is_absolute()
        or candidate.as_posix() != value
        or any(part in ("", ".", "..") for part in candidate.parts)
    ):
        raise EvidenceError(f"{label} is not a canonical relative path: {value!r}")
    return candidate


def run_git(repo_root: Path, *arguments: str, allow_missing: bool = False) -> str:
    metadata = TRUSTED_GIT.lstat()
    if (
        TRUSTED_GIT.is_symlink()
        or not stat.S_ISREG(metadata.st_mode)
        or not metadata.st_mode & 0o111
    ):
        raise EvidenceError(f"trusted Git is not a regular executable: {TRUSTED_GIT}")
    try:
        result = subprocess.run(
            [str(TRUSTED_GIT), "-C", str(repo_root), *arguments],
            check=not allow_missing,
            capture_output=True,
            text=True,
            env=TRUSTED_COMMAND_ENV,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise EvidenceError(f"Git source binding failed for {' '.join(arguments)}") from error
    if allow_missing and result.returncode != 0:
        return ""
    return result.stdout.strip()


def source_test_inventory(repo_root: Path, test_paths: list[str]) -> list[dict[str, Any]]:
    cases: list[dict[str, Any]] = []
    for relative in test_paths:
        raw = read_regular_bytes(repo_root / relative, MAX_TEXT_BYTES, "Pi test source")
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError as error:
            raise EvidenceError(f"Pi test source is not UTF-8: {relative}") from error
        for line in text.splitlines():
            match = re.fullmatch(r'\s*@test\s+"([^"]+)"\s*\{\s*', line)
            if match:
                cases.append(
                    {"number": len(cases) + 1, "source": relative, "name": match.group(1)}
                )
    return cases


def test_tree_sha256(repo_root: Path, test_paths: list[str]) -> str:
    directories: set[str] = set()
    files: list[tuple[str, bytes]] = []
    for relative in test_paths:
        posix = canonical_relative_path(relative, "test path")
        for parent in posix.parents:
            if parent.as_posix() != ".":
                directories.add(parent.as_posix())
        files.append(
            (relative, read_regular_bytes(repo_root / relative, MAX_TEXT_BYTES, "Pi test source"))
        )
    digest = hashlib.sha256(TREE_DOMAIN)
    entries: list[tuple[str, str, bytes | None]] = [
        (relative, "D", None) for relative in directories
    ] + [(relative, "F", raw) for relative, raw in files]
    for relative, kind, raw in sorted(entries):
        encoded = relative.encode("utf-8")
        if kind == "D":
            digest.update(b"D\0" + encoded + b"\0")
        else:
            assert raw is not None
            digest.update(b"F\0" + encoded + b"\0")
            digest.update(str(len(raw)).encode("ascii") + b"\0")
            digest.update(raw)
    return digest.hexdigest()


def runtime_tree_sha256(root: Path, label: str) -> str:
    metadata = root.lstat()
    if root.is_symlink() or not stat.S_ISDIR(metadata.st_mode):
        raise EvidenceError(f"{label} must be a real directory")
    resolved_root = root.resolve(strict=True)
    entries: list[tuple[str, str, Path]] = []
    for current, directory_names, file_names in os.walk(
        resolved_root, topdown=True, followlinks=False
    ):
        directory_names.sort()
        file_names.sort()
        current_path = Path(current)
        retained_directories: list[str] = []
        for name in directory_names:
            path = current_path / name
            item = path.lstat()
            relative = path.relative_to(resolved_root).as_posix()
            if stat.S_ISLNK(item.st_mode):
                entries.append((relative, "L", path))
            elif stat.S_ISDIR(item.st_mode):
                entries.append((relative, "D", path))
                retained_directories.append(name)
            else:
                raise EvidenceError(f"{label} contains unsupported entry: {relative}")
        directory_names[:] = retained_directories
        for name in file_names:
            path = current_path / name
            item = path.lstat()
            relative = path.relative_to(resolved_root).as_posix()
            if stat.S_ISLNK(item.st_mode):
                entries.append((relative, "L", path))
            elif stat.S_ISREG(item.st_mode):
                entries.append((relative, "F", path))
            else:
                raise EvidenceError(f"{label} contains unsupported entry: {relative}")
    digest = hashlib.sha256(RUNTIME_TREE_DOMAIN)
    digest.update(
        b"R\0" + format(stat.S_IMODE(metadata.st_mode), "04o").encode("ascii") + b"\0"
    )
    for relative, kind, path in sorted(entries):
        encoded = relative.encode("utf-8")
        if b"\0" in encoded:
            raise EvidenceError(f"{label} path contains NUL")
        if kind == "D":
            digest.update(b"D\0" + encoded + b"\0")
            digest.update(
                format(stat.S_IMODE(path.lstat().st_mode), "04o").encode("ascii") + b"\0"
            )
        elif kind == "F":
            before = path.lstat()
            raw = read_regular_bytes(path, MAX_ARCHIVE_BYTES, label)
            after = path.lstat()
            if stat.S_IMODE(before.st_mode) != stat.S_IMODE(after.st_mode):
                raise EvidenceError(f"{label} file mode changed while read: {relative}")
            digest.update(b"F\0" + encoded + b"\0")
            digest.update(
                format(stat.S_IMODE(before.st_mode), "04o").encode("ascii") + b"\0"
            )
            digest.update(str(len(raw)).encode("ascii") + b"\0")
            digest.update(raw)
        else:
            before = path.lstat()
            target = os.readlink(path)
            resolved_target = path.resolve(strict=True)
            try:
                resolved_target.relative_to(resolved_root)
            except ValueError as error:
                raise EvidenceError(
                    f"{label} symlink escapes the runtime tree: {relative}"
                ) from error
            after = path.lstat()
            if (
                before.st_dev,
                before.st_ino,
                before.st_mtime_ns,
                before.st_size,
            ) != (
                after.st_dev,
                after.st_ino,
                after.st_mtime_ns,
                after.st_size,
            ):
                raise EvidenceError(f"{label} symlink changed while read: {relative}")
            target_bytes = os.fsencode(target)
            if b"\0" in target_bytes:
                raise EvidenceError(f"{label} symlink target contains NUL")
            digest.update(b"L\0" + encoded + b"\0")
            digest.update(str(len(target_bytes)).encode("ascii") + b"\0")
            digest.update(target_bytes)
    return digest.hexdigest()


def require_real_directory(path: Path, label: str) -> Path:
    metadata = path.lstat()
    if path.is_symlink() or not stat.S_ISDIR(metadata.st_mode):
        raise EvidenceError(f"{label} must be a real directory")
    return path.resolve(strict=True)


def require_real_directory_chain(root: Path, relative: PurePosixPath, label: str) -> Path:
    current = root
    for part in relative.parts:
        current = current / part
        metadata = current.lstat()
        if current.is_symlink() or not stat.S_ISDIR(metadata.st_mode):
            raise EvidenceError(f"{label} ancestor must be a real directory: {part}")
    return current.resolve(strict=True)


def normalized_node_arch(value: str) -> str:
    normalized = {"arm64": "arm64", "x64": "x86_64", "x86_64": "x86_64"}.get(
        value
    )
    if normalized is None:
        raise EvidenceError(f"Node process.arch is unsupported: {value!r}")
    return normalized


def validate_node_executable_identity(value: Any, label: str) -> dict[str, Any]:
    identity = exact_keys(
        value,
        {
            "architectures", "basename", "format", "mode", "sha256",
            "size_bytes", "type",
        },
        label,
    )
    architectures = identity["architectures"]
    if (
        not isinstance(architectures, list)
        or not architectures
        or architectures != sorted(set(architectures))
        or any(item not in {"arm64", "x86_64"} for item in architectures)
    ):
        raise EvidenceError(f"{label} architectures are invalid")
    if (
        identity["basename"] != "node"
        or identity["format"] not in {"elf", "mach-o", "mach-o-universal"}
        or not isinstance(identity["mode"], str)
        or re.fullmatch(r"0[0-7]{3}", identity["mode"]) is None
        or identity["type"] != "file"
        or not isinstance(identity["size_bytes"], int)
        or isinstance(identity["size_bytes"], bool)
        or not 20 <= identity["size_bytes"] <= MAX_EXECUTABLE_BYTES
        or not isinstance(identity["sha256"], str)
        or SHA256_RE.fullmatch(identity["sha256"]) is None
    ):
        raise EvidenceError(f"{label} executable identity is invalid")
    return identity


def observe_node_runtime(
    repo_root: Path,
    node_executable: Path,
    expected_os: str,
    expected_arch: str,
) -> dict[str, Any]:
    if expected_os not in {"Darwin", "Linux"}:
        raise EvidenceError("expected Node operating system is unsupported")
    if expected_arch not in {"arm64", "x86_64"}:
        raise EvidenceError("expected Node architecture is unsupported")
    validator = repo_root / NATIVE_EXECUTABLE_VALIDATOR_RELATIVE
    if validator.resolve(strict=True) != validator:
        raise EvidenceError("native executable validator must be the canonical source file")
    try:
        result = subprocess.run(
            [
                os.fsdecode(os.fsencode(os.path.realpath(sys.executable))),
                str(validator),
                str(node_executable),
                expected_os,
                expected_arch,
                "Pi Node.js executable",
            ],
            check=True,
            capture_output=True,
            timeout=30,
            env=TRUSTED_COMMAND_ENV,
        )
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise EvidenceError("Pi Node executable failed native identity validation") from error
    if len(result.stdout) > 16 * 1024 or result.stderr:
        raise EvidenceError("native executable validator returned unexpected output")
    validator_binding = strict_json_bytes(result.stdout, "native executable binding")
    exact_keys(
        validator_binding,
        {"architectures", "format", "mode", "path", "sha256", "size_bytes", "type"},
        "native executable binding",
    )
    if validator_binding.get("path") != str(node_executable):
        raise EvidenceError("native executable validator changed the selected Node path")
    executable = validate_node_executable_identity(
        {"basename": node_executable.name, **{k: v for k, v in validator_binding.items() if k != "path"}},
        "Pi Node executable",
    )
    if expected_arch not in executable["architectures"]:
        raise EvidenceError("Pi Node executable does not contain the expected architecture")
    if expected_os == "Darwin" and not executable["format"].startswith("mach-o"):
        raise EvidenceError("Pi Node executable is not Mach-O on Darwin")
    if expected_os == "Linux" and executable["format"] != "elf":
        raise EvidenceError("Pi Node executable is not ELF on Linux")
    try:
        process = subprocess.run(
            [str(node_executable), "-p", "process.arch"],
            check=True,
            capture_output=True,
            timeout=30,
            env=TRUSTED_COMMAND_ENV,
        )
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise EvidenceError("could not observe the selected Node process architecture") from error
    if len(process.stdout) > 64 or process.stderr:
        raise EvidenceError("selected Node returned unexpected process.arch output")
    try:
        process_arch_raw = process.stdout.decode("ascii")
    except UnicodeDecodeError as error:
        raise EvidenceError("selected Node process.arch is not ASCII") from error
    if not process_arch_raw.endswith("\n") or process_arch_raw.count("\n") != 1:
        raise EvidenceError("selected Node process.arch output is malformed")
    process_arch = normalized_node_arch(process_arch_raw[:-1])
    if process_arch != expected_arch:
        raise EvidenceError(
            "selected Node process.arch does not match the expected matrix architecture"
        )
    return {
        "expected_arch": expected_arch,
        "observed_process_arch": process_arch,
        "executable": executable,
    }


def node_binding_snapshot(arguments: argparse.Namespace) -> dict[str, Any]:
    repo_root = require_real_directory(arguments.repo_root, "repo-root")
    observation = observe_node_runtime(
        repo_root,
        arguments.node_executable,
        arguments.expected_os,
        arguments.expected_arch,
    )
    return {
        "schema_version": 1,
        "kind": NODE_BINDING_KIND,
        **observation,
    }


def inspect_pi_runtime(
    package_input: Path,
    runtime_input: Path,
    install_prefix_input: Path,
    expected_package: str | None = None,
    expected_version: str | None = None,
) -> dict[str, Any]:
    install_prefix = require_real_directory(install_prefix_input, "pi-install-prefix")
    expected_runtime_input = install_prefix_input / "node_modules"
    if runtime_input != expected_runtime_input:
        raise EvidenceError("pi-runtime-root must be pi-install-prefix/node_modules")
    runtime_root = require_real_directory_chain(
        install_prefix, PurePosixPath("node_modules"), "Pi runtime"
    )
    package_root = require_real_directory(package_input, "pi-package-root")
    package_json, package_json_raw = load_json(package_root / "package.json", "Pi package.json")
    package_name = package_json.get("name")
    package_version = package_json.get("version")
    if (
        not isinstance(package_name, str)
        or re.fullmatch(r"@[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", package_name) is None
        or not isinstance(package_version, str)
        or VERSION_RE.fullmatch(package_version) is None
    ):
        raise EvidenceError("Pi package.json must contain a valid scoped name and version")
    if expected_package is not None and package_name != expected_package:
        raise EvidenceError("Pi package.json package does not match the expected package")
    if expected_version is not None and package_version != expected_version:
        raise EvidenceError("Pi package.json version does not match the expected version")

    package_relative = canonical_relative_path(package_name, "Pi package name")
    expected_package_input = runtime_input.joinpath(*package_relative.parts)
    if package_input != expected_package_input:
        raise EvidenceError("Pi package root is not the canonical runtime path")
    chained_package_root = require_real_directory_chain(
        runtime_root, package_relative, "Pi package"
    )
    if chained_package_root != package_root:
        raise EvidenceError("Pi package root is not canonical within the runtime root")
    try:
        package_root.relative_to(runtime_root)
    except ValueError as error:
        raise EvidenceError("Pi package root escapes the runtime root") from error

    bin_root = require_real_directory_chain(runtime_root, PurePosixPath(".bin"), "Pi runtime")
    runtime_entry = bin_root / "pi"
    entry_metadata = runtime_entry.lstat()
    if not (stat.S_ISLNK(entry_metadata.st_mode) or stat.S_ISREG(entry_metadata.st_mode)):
        raise EvidenceError("Pi runtime entry .bin/pi must be a regular file or symlink")
    resolved_entry = runtime_entry.resolve(strict=True)
    resolved_metadata = resolved_entry.stat()
    if not stat.S_ISREG(resolved_metadata.st_mode) or not resolved_metadata.st_mode & 0o111:
        raise EvidenceError("Pi runtime entry .bin/pi must resolve to a regular executable")
    try:
        resolved_entry.relative_to(package_root)
    except ValueError as error:
        raise EvidenceError("Pi runtime entry does not resolve into the selected package") from error

    return {
        "package": package_name,
        "version": package_version,
        "package_json_raw": package_json_raw,
        "package_tree_sha256": runtime_tree_sha256(package_root, "Pi package tree"),
        "runtime_tree_sha256": runtime_tree_sha256(runtime_root, "Pi runtime dependency tree"),
    }


def runtime_snapshot(arguments: argparse.Namespace) -> dict[str, Any]:
    if re.fullmatch(r"@[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", arguments.expected_package) is None:
        raise EvidenceError("expected-package must be a scoped npm package")
    if VERSION_RE.fullmatch(arguments.expected_version) is None:
        raise EvidenceError("expected-version must be semantic X.Y.Z")
    observation = inspect_pi_runtime(
        arguments.pi_package_root,
        arguments.pi_runtime_root,
        arguments.pi_install_prefix,
        arguments.expected_package,
        arguments.expected_version,
    )
    return {
        "schema_version": 1,
        "kind": RUNTIME_SNAPSHOT_KIND,
        "algorithm": "MAINFRAME-PI-RUNTIME-TREE-SHA256-V1",
        "package": observation["package"],
        "version": observation["version"],
        "runtime_root_name": "node_modules",
        "runtime_entry": ".bin/pi",
        "package_tree_sha256": observation["package_tree_sha256"],
        "runtime_tree_sha256": observation["runtime_tree_sha256"],
    }


def validate_runtime_snapshot(
    arguments: argparse.Namespace,
    pi: dict[str, Any],
    suffix: str,
    post_test: dict[str, Any],
) -> dict[str, Any]:
    snapshot, snapshot_raw = load_json(
        arguments.pre_test_runtime_snapshot, "pre-test Pi runtime snapshot"
    )
    exact_keys(
        snapshot,
        {
            "schema_version", "kind", "algorithm", "package", "version",
            "runtime_root_name", "runtime_entry", "package_tree_sha256",
            "runtime_tree_sha256",
        },
        "pre-test Pi runtime snapshot",
    )
    if snapshot_raw != canonical_json(snapshot):
        raise EvidenceError("pre-test Pi runtime snapshot is not canonical sorted-key JSON")
    snapshot_sha = sha256_bytes(snapshot_raw)
    if (
        SHA256_RE.fullmatch(arguments.pre_test_runtime_snapshot_sha256) is None
        or snapshot_sha != arguments.pre_test_runtime_snapshot_sha256
    ):
        raise EvidenceError("pre-test Pi runtime snapshot digest does not match")
    expected_name = f"pi-runtime-pre-{suffix}.json"
    if arguments.pre_test_runtime_snapshot.name != expected_name:
        raise EvidenceError("pre-test Pi runtime snapshot basename does not identify this cell")
    expected_identity = {
        "schema_version": 1,
        "kind": RUNTIME_SNAPSHOT_KIND,
        "algorithm": "MAINFRAME-PI-RUNTIME-TREE-SHA256-V1",
        "package": pi["package"],
        "version": pi["version"],
        "runtime_root_name": "node_modules",
        "runtime_entry": ".bin/pi",
    }
    if any(snapshot.get(key) != value for key, value in expected_identity.items()):
        raise EvidenceError("pre-test Pi runtime snapshot identity does not match this cell")
    for digest_key in ("package_tree_sha256", "runtime_tree_sha256"):
        if not isinstance(snapshot.get(digest_key), str) or SHA256_RE.fullmatch(
            snapshot[digest_key]
        ) is None:
            raise EvidenceError("pre-test Pi runtime snapshot digest is invalid")
        if snapshot[digest_key] != post_test[digest_key]:
            raise EvidenceError(
                f"Pi {digest_key.removesuffix('_sha256').replace('_', ' ')} changed "
                "between pre-test snapshot and post-test evidence"
            )
    return {
        "algorithm": "MAINFRAME-PI-RUNTIME-TREE-SHA256-V1",
        "pre_test_snapshot": {
            "name": arguments.pre_test_runtime_snapshot.name,
            "file_sha256": snapshot_sha,
        },
        "pre_test": {
            "package_tree_sha256": snapshot["package_tree_sha256"],
            "runtime_tree_sha256": snapshot["runtime_tree_sha256"],
        },
        "post_test": {
            "package_tree_sha256": post_test["package_tree_sha256"],
            "runtime_tree_sha256": post_test["runtime_tree_sha256"],
        },
        "package_unchanged": True,
        "runtime_unchanged": True,
        "result": "unchanged",
    }


def validate_node_runtime(
    arguments: argparse.Namespace,
    repo_root: Path,
    platform: dict[str, Any],
    suffix: str,
) -> dict[str, Any]:
    if arguments.expected_node_arch != platform["arch"]:
        raise EvidenceError("expected-node-arch does not match the observed matrix platform")
    metadata = arguments.pre_test_node_binding.lstat()
    if stat.S_IMODE(metadata.st_mode) != 0o600:
        raise EvidenceError("pre-test Node binding must remain owner-private mode 0600")
    snapshot, snapshot_raw = load_json(
        arguments.pre_test_node_binding, "pre-test Node binding"
    )
    exact_keys(
        snapshot,
        {
            "schema_version", "kind", "expected_arch", "observed_process_arch",
            "executable",
        },
        "pre-test Node binding",
    )
    if snapshot_raw != canonical_json(snapshot):
        raise EvidenceError("pre-test Node binding is not canonical sorted-key JSON")
    snapshot_sha = sha256_bytes(snapshot_raw)
    if (
        SHA256_RE.fullmatch(arguments.pre_test_node_binding_sha256) is None
        or snapshot_sha != arguments.pre_test_node_binding_sha256
    ):
        raise EvidenceError("pre-test Node binding digest does not match")
    expected_name = f"pi-node-pre-{suffix}.json"
    if arguments.pre_test_node_binding.name != expected_name:
        raise EvidenceError("pre-test Node binding basename does not identify this cell")
    if (
        snapshot["schema_version"] != 1
        or snapshot["kind"] != NODE_BINDING_KIND
        or snapshot["expected_arch"] != platform["arch"]
        or snapshot["observed_process_arch"] != platform["arch"]
    ):
        raise EvidenceError("pre-test Node binding architecture does not match this cell")
    validate_node_executable_identity(
        snapshot["executable"], "pre-test Node executable"
    )
    pre_test = {
        "expected_arch": snapshot["expected_arch"],
        "observed_process_arch": snapshot["observed_process_arch"],
        "executable": snapshot["executable"],
    }
    post_test = observe_node_runtime(
        repo_root,
        arguments.node_executable,
        platform["os"],
        platform["arch"],
    )
    if not strict_equal(pre_test, post_test):
        raise EvidenceError("Node executable or process architecture changed after Pi tests")
    return {
        "algorithm": NODE_BINDING_ALGORITHM,
        "pre_test_binding": {
            "name": arguments.pre_test_node_binding.name,
            "file_sha256": snapshot_sha,
        },
        "pre_test": pre_test,
        "post_test": post_test,
        "executable_unchanged": True,
        "process_arch_unchanged": True,
        "result": "unchanged",
    }


def validate_contract(
    contract: dict[str, Any], repo_root: Path
) -> tuple[list[str], list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    exact_keys(
        contract,
        {
            "schema_version", "kind", "claim_scope", "test_tree_algorithm",
            "test_paths", "plan_per_run", "bats_core_commit", "platforms", "pi_versions",
        },
        "contract",
    )
    if contract["schema_version"] != 1:
        raise EvidenceError("contract schema_version must equal 1")
    if contract["kind"] != "mainframe-pi-exact-candidate-contract":
        raise EvidenceError("contract kind is unsupported")
    if contract["claim_scope"] != "exact-candidate-pi-integration-conformance-only":
        raise EvidenceError("contract claim scope is unsupported")
    if contract["test_tree_algorithm"] != "MAINFRAME-PACKAGE-TREE-SHA256-V1":
        raise EvidenceError("contract test-tree algorithm is unsupported")
    test_paths = contract["test_paths"]
    if (
        not isinstance(test_paths, list)
        or len(test_paths) != 3
        or len(test_paths) != len(set(test_paths))
        or any(not isinstance(item, str) or not TEST_PATH_RE.fullmatch(item) for item in test_paths)
    ):
        raise EvidenceError("contract must contain three ordered, unique Bats test paths")
    cases = source_test_inventory(repo_root, test_paths)
    if contract["plan_per_run"] != 44 or len(cases) != 44:
        raise EvidenceError("contract and source must define exactly 44 tests per cell")
    if len({case["name"] for case in cases}) != len(cases):
        raise EvidenceError("Pi source test names must be unique")
    if not isinstance(contract["bats_core_commit"], str) or not re.fullmatch(
        r"[0-9a-f]{40}", contract["bats_core_commit"]
    ):
        raise EvidenceError("contract Bats commit is invalid")

    platforms = contract["platforms"]
    if not isinstance(platforms, list) or len(platforms) != 3:
        raise EvidenceError("contract must contain exactly three platforms")
    for index, platform in enumerate(platforms):
        exact_keys(platform, {"id", "os", "arch", "system_libc"}, f"platform[{index}]")
        expected_id = f"{platform['os']}-{platform['arch']}-{platform['system_libc']}"
        if platform["id"] != expected_id or not TOKEN_RE.fullmatch(platform["id"]):
            raise EvidenceError(f"platform[{index}] is not canonical")
    if platforms != sorted(platforms, key=lambda item: item["id"]):
        raise EvidenceError("contract platforms must be sorted")
    if len({item["id"] for item in platforms}) != 3:
        raise EvidenceError("contract platform ids must be unique")

    pi_versions = contract["pi_versions"]
    if not isinstance(pi_versions, list) or len(pi_versions) != 2:
        raise EvidenceError("contract must contain exactly two Pi versions")
    pi_keys = {
        "id", "package", "version", "npm_integrity", "profile", "expected_skips",
        "expected_skip", "limitations",
    }
    names = {case["name"] for case in cases}
    for index, pi in enumerate(pi_versions):
        exact_keys(pi, pi_keys, f"pi_versions[{index}]")
        if not isinstance(pi["id"], str) or not TOKEN_RE.fullmatch(pi["id"]):
            raise EvidenceError(f"pi_versions[{index}] id is invalid")
        if not isinstance(pi["package"], str) or not re.fullmatch(
            r"@[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", pi["package"]
        ):
            raise EvidenceError(f"pi_versions[{index}] package is invalid")
        if not isinstance(pi["version"], str) or not VERSION_RE.fullmatch(pi["version"]):
            raise EvidenceError(f"pi_versions[{index}] version is invalid")
        if not isinstance(pi["npm_integrity"], str) or not NPM_INTEGRITY_RE.fullmatch(
            pi["npm_integrity"]
        ):
            raise EvidenceError(f"pi_versions[{index}] npm integrity is invalid")
        if not isinstance(pi["profile"], str) or not re.fullmatch(r"[a-z0-9-]+", pi["profile"]):
            raise EvidenceError(f"pi_versions[{index}] profile is invalid")
        if pi["expected_skips"] not in (0, 1):
            raise EvidenceError(f"pi_versions[{index}] expected skip count is invalid")
        expected_skip = pi["expected_skip"]
        if pi["expected_skips"] == 0 and expected_skip is not None:
            raise EvidenceError(f"pi_versions[{index}] unexpected skip contract")
        if pi["expected_skips"] == 1:
            exact_keys(expected_skip, {"test", "reason"}, f"pi_versions[{index}].expected_skip")
            if expected_skip["test"] not in names or not expected_skip["reason"]:
                raise EvidenceError(f"pi_versions[{index}] expected skip is invalid")
        if not isinstance(pi["limitations"], list) or any(
            not isinstance(item, str) or not item for item in pi["limitations"]
        ):
            raise EvidenceError(f"pi_versions[{index}] limitations are invalid")
    if pi_versions != sorted(pi_versions, key=lambda item: item["id"]):
        raise EvidenceError("contract Pi versions must be sorted")
    return test_paths, platforms, pi_versions, cases


def load_compatibility(
    repo_root: Path,
    version: str,
    pi: dict[str, Any],
    platform: dict[str, Any],
) -> tuple[dict[str, Any], bytes]:
    config, raw = load_json(repo_root / "config/pi-compatibility.json", "Pi compatibility config")
    if config.get("mainframe_version") != version or not isinstance(
        config.get("certifications"), list
    ):
        raise EvidenceError("Pi compatibility config does not match Mainframe version")
    matches = [
        record for record in config["certifications"]
        if isinstance(record, dict)
        and record.get("mainframe_version") == version
        and record.get("package") == pi["package"]
        and record.get("version") == pi["version"]
        and record.get("npm_integrity") == pi["npm_integrity"]
        and record.get("profile") == pi["profile"]
    ]
    if len(matches) != 1:
        raise EvidenceError("Pi identity is not unique in compatibility config")
    record = matches[0]
    if not isinstance(record.get("id"), str) or not TOKEN_RE.fullmatch(record["id"]):
        raise EvidenceError("Pi compatibility record id is invalid")
    declared = record.get("platforms")
    if not isinstance(declared, list) or any(not isinstance(item, str) for item in declared):
        raise EvidenceError("Pi compatibility platforms are invalid")
    if record.get("support") not in {"certified", "limited"}:
        raise EvidenceError("Pi compatibility support is invalid")
    platform_declared = platform["id"] in declared
    support = record["support"] if platform_declared else "unverified"
    return {
        "manifest_record_id": record["id"],
        "platform_declared": platform_declared,
        "support": support,
        "runtime_state": {
            "certified": "READY",
            "limited": "LIMITED",
            "unverified": "COMPATIBILITY_UNVERIFIED",
        }[support],
    }, raw


def command_output(command: Path, *arguments: str) -> str:
    if command not in {TRUSTED_UNAME, TRUSTED_GETCONF}:
        raise EvidenceError(f"host observation command is not trusted: {command}")
    metadata = command.lstat()
    if command.is_symlink() or not stat.S_ISREG(metadata.st_mode) or not metadata.st_mode & 0o111:
        raise EvidenceError(f"host observation command is not a regular executable: {command}")
    try:
        result = subprocess.run(
            [str(command), *arguments],
            check=True,
            capture_output=True,
            text=True,
            env=TRUSTED_COMMAND_ENV,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise EvidenceError(
            f"host observation failed: {command} {' '.join(arguments)}"
        ) from error
    value = result.stdout.strip()
    if not value or any(ord(character) < 32 for character in value):
        raise EvidenceError(
            f"host observation returned invalid output: {command} {' '.join(arguments)}"
        )
    return value


def _darwin_sysctl_int(name: str) -> int | None:
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        sysctlbyname = libc.sysctlbyname
    except (AttributeError, OSError) as error:
        raise EvidenceError(f"cannot inspect Darwin native execution: {error}") from error
    sysctlbyname.argtypes = [
        ctypes.c_char_p,
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_size_t),
        ctypes.c_void_p,
        ctypes.c_size_t,
    ]
    sysctlbyname.restype = ctypes.c_int
    value = ctypes.c_int(0)
    size = ctypes.c_size_t(ctypes.sizeof(value))
    ctypes.set_errno(0)
    result = sysctlbyname(
        name.encode("ascii"), ctypes.byref(value), ctypes.byref(size), None, 0
    )
    if result == 0:
        if size.value != ctypes.sizeof(value) or value.value not in (0, 1):
            raise EvidenceError(f"Darwin native-state probe {name} is malformed")
        return value.value
    error_number = ctypes.get_errno()
    if error_number == errno.ENOENT:
        return None
    raise EvidenceError(
        f"Darwin native-state probe {name} failed with errno {error_number}"
    )


def _darwin_sysctl_string(name: str) -> str | None:
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        sysctlbyname = libc.sysctlbyname
    except (AttributeError, OSError) as error:
        raise EvidenceError(f"cannot inspect Darwin native execution: {error}") from error
    sysctlbyname.argtypes = [
        ctypes.c_char_p,
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_size_t),
        ctypes.c_void_p,
        ctypes.c_size_t,
    ]
    sysctlbyname.restype = ctypes.c_int
    size = ctypes.c_size_t(0)
    ctypes.set_errno(0)
    result = sysctlbyname(name.encode("ascii"), None, ctypes.byref(size), None, 0)
    if result != 0:
        error_number = ctypes.get_errno()
        if error_number == errno.ENOENT:
            return None
        raise EvidenceError(
            f"Darwin native-state probe {name} failed with errno {error_number}"
        )
    if size.value < 2 or size.value > 512:
        raise EvidenceError(f"Darwin native-state probe {name} is malformed")
    expected_size = size.value
    value = ctypes.create_string_buffer(expected_size)
    ctypes.set_errno(0)
    result = sysctlbyname(
        name.encode("ascii"), ctypes.byref(value), ctypes.byref(size), None, 0
    )
    if result != 0:
        error_number = ctypes.get_errno()
        raise EvidenceError(
            f"Darwin native-state probe {name} failed with errno {error_number}"
        )
    raw = bytes(value.raw[: size.value])
    if size.value != expected_size or not raw.endswith(b"\0"):
        raise EvidenceError(f"Darwin native-state probe {name} is malformed")
    try:
        observed = raw[:-1].decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise EvidenceError(
            f"Darwin native-state probe {name} is malformed"
        ) from error
    if not observed or any(ord(character) < 32 or ord(character) == 127 for character in observed):
        raise EvidenceError(f"Darwin native-state probe {name} is malformed")
    return observed


def _require_native_darwin(architecture: str) -> None:
    translated = _darwin_sysctl_int("sysctl.proc_translated")
    arm64_capable = _darwin_sysctl_int("hw.optional.arm64")
    if translated == 1:
        raise EvidenceError(
            "Darwin process is translated under Rosetta; native evidence is required"
        )
    if architecture == "arm64":
        if translated != 0 or arm64_capable != 1:
            raise EvidenceError("cannot establish native Darwin arm64 execution")
    elif architecture == "x86_64":
        if arm64_capable is None:
            cpu_brand = _darwin_sysctl_string("machdep.cpu.brand_string")
            if cpu_brand is None or not cpu_brand.startswith("Intel"):
                raise EvidenceError("cannot establish native Darwin Intel hardware")
        elif arm64_capable != 0:
            raise EvidenceError(
                "Darwin x86_64 process is running on Apple Silicon; native Intel evidence is required"
            )


def observe_platform(
    requested_override: str | None, platforms: list[dict[str, Any]]
) -> tuple[dict[str, Any], dict[str, Any]]:
    by_id = {item["id"]: item for item in platforms}
    if requested_override is not None:
        if os.environ.get("MAINFRAME_PI_CELL_TEST_MODE") != "1":
            raise EvidenceError(
                "--observed-platform is test-only and requires MAINFRAME_PI_CELL_TEST_MODE=1"
            )
        if requested_override not in by_id:
            raise EvidenceError("observed-platform override is not in the contract")
        return dict(by_id[requested_override]), {
            "observation_mode": "test-override",
            "commands": {
                "uname_system": None,
                "uname_machine": None,
                "getconf_long_bit": None,
                "getconf_gnu_libc_version": None,
            },
            "test_override": requested_override,
        }

    uname_system = command_output(TRUSTED_UNAME, "-s")
    uname_machine = command_output(TRUSTED_UNAME, "-m")
    long_bit = command_output(TRUSTED_GETCONF, "LONG_BIT")
    if long_bit != "64":
        raise EvidenceError("Pi cell evidence requires a 64-bit host")
    if uname_system not in {"Darwin", "Linux"}:
        raise EvidenceError(f"unsupported host operating system: {uname_system}")
    normalized_arch = {
        "arm64": "arm64",
        "aarch64": "arm64",
        "x86_64": "x86_64",
        "amd64": "x86_64",
    }.get(uname_machine)
    if normalized_arch is None:
        raise EvidenceError(f"unsupported host architecture: {uname_machine}")
    if uname_system == "Darwin":
        _require_native_darwin(normalized_arch)
    libc_version: str | None = None
    system_libc = "none"
    if uname_system == "Linux":
        libc_version = command_output(TRUSTED_GETCONF, "GNU_LIBC_VERSION")
        if re.fullmatch(r"glibc [0-9]+(?:\.[0-9]+)+", libc_version) is None:
            raise EvidenceError(f"Linux host is not observed glibc: {libc_version}")
        system_libc = "glibc"
    platform_id = f"{uname_system}-{normalized_arch}-{system_libc}"
    if platform_id not in by_id:
        raise EvidenceError(f"observed host tuple is outside the contract: {platform_id}")
    return dict(by_id[platform_id]), {
        "observation_mode": "native",
        "commands": {
            "uname_system": uname_system,
            "uname_machine": uname_machine,
            "getconf_long_bit": long_bit,
            "getconf_gnu_libc_version": libc_version,
        },
        "test_override": None,
    }


def read_binding(path: Path, label: str, pattern: re.Pattern[str]) -> tuple[str, str]:
    raw = read_regular_bytes(path, 512, label)
    try:
        value = raw.decode("ascii")
    except UnicodeDecodeError as error:
        raise EvidenceError(f"{label} is not ASCII") from error
    if not value.endswith("\n") or value.count("\n") != 1:
        raise EvidenceError(f"{label} must contain exactly one newline-terminated value")
    value = value[:-1]
    if pattern.fullmatch(value) is None:
        raise EvidenceError(f"{label} value has invalid syntax")
    return value, sha256_bytes(raw)


def parse_tap(
    path: Path, cases: list[dict[str, Any]], expected_skip: dict[str, str] | None
) -> dict[str, Any]:
    raw = read_regular_bytes(path, MAX_TEXT_BYTES, "Pi TAP artifact")
    if b"\xef\xbb\xbf" in raw or any(
        (byte < 32 and byte not in (9, 10, 13)) or byte == 127 for byte in raw
    ):
        raise EvidenceError("Pi TAP artifact contains a BOM or unsafe control character")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise EvidenceError("Pi TAP artifact is not UTF-8") from error
    if any(
        ((ord(character) < 32 and character not in "\t\n\r") or
         0x7F <= ord(character) <= 0x9F)
        for character in text
    ):
        raise EvidenceError("Pi TAP artifact contains an unsafe Unicode control character")
    lines = text.splitlines()
    plan: list[int] = []
    records: list[tuple[int, str]] = []
    skips: list[dict[str, Any]] = []
    failures = 0
    for line in lines:
        stripped = line.lstrip()
        if re.match(r"^Bail out!", stripped, re.IGNORECASE) or re.search(
            r"#\s*TODO(?:\s|$)", line, re.IGNORECASE
        ):
            raise EvidenceError("Pi TAP contains a bailout or TODO")
        if re.match(r"^1\.\.", stripped):
            match = re.fullmatch(r"1\.\.(\d+)", line)
            if match is None:
                raise EvidenceError("Pi TAP plan is malformed or indented")
            plan.append(int(match.group(1)))
            continue
        if re.match(r"^not ok(?:\s|$)", stripped, re.IGNORECASE):
            failures += 1
            continue
        if re.match(r"^ok(?:\s|$)", stripped, re.IGNORECASE) and line != stripped:
            raise EvidenceError("Pi TAP contains an indented result")
        match = re.fullmatch(r"ok\s+([0-9]+)\s+(.+)", line)
        if match:
            number = int(match.group(1))
            description = match.group(2)
            skip_match = re.fullmatch(r"(.+?)\s+#\s+skip\s+(.+)", description, re.IGNORECASE)
            if skip_match:
                name = skip_match.group(1)
                skips.append({"number": number, "test": name, "reason": skip_match.group(2)})
            else:
                name = description
            records.append((number, name))
        elif re.match(r"^ok(?:\s|$)", stripped, re.IGNORECASE):
            raise EvidenceError("Pi TAP result record is malformed")
    expected_names = [case["name"] for case in cases]
    if plan != [len(cases)]:
        raise EvidenceError(f"Pi TAP must contain one 1..{len(cases)} plan")
    if failures:
        raise EvidenceError(f"Pi TAP contains {failures} failing tests")
    if records != list(enumerate(expected_names, start=1)):
        raise EvidenceError("Pi TAP test names or numbers are incomplete or out of order")
    expected_skips: list[dict[str, Any]] = []
    if expected_skip is not None:
        number = expected_names.index(expected_skip["test"]) + 1
        expected_skips = [{"number": number, **expected_skip}]
    if skips != expected_skips:
        raise EvidenceError("Pi TAP skip details do not match the contract")
    return {
        "status": "pass",
        "plan": len(cases),
        "ok": len(records),
        "executed": len(records) - len(skips),
        "not_ok": 0,
        "skipped": len(skips),
        "skip_details": skips,
    }


def validate_ref(value: str) -> None:
    if (
        REF_RE.fullmatch(value) is None
        or ".." in value
        or "//" in value
        or value.endswith(("/", ".", ".lock"))
        or "@{" in value
    ):
        raise EvidenceError("source-ref is not a canonical Git ref")


def validate_source_and_arguments(arguments: argparse.Namespace, repo_root: Path) -> list[str]:
    if not VERSION_RE.fullmatch(arguments.version):
        raise EvidenceError("version must be semantic X.Y.Z")
    if not REPOSITORY_RE.fullmatch(arguments.repository):
        raise EvidenceError("repository must be owner/name")
    validate_ref(arguments.source_ref)
    if not GIT_SHA_RE.fullmatch(arguments.source_ref_sha):
        raise EvidenceError("source-ref-sha is invalid")
    if not GIT_SHA_RE.fullmatch(arguments.source_commit_sha):
        raise EvidenceError("source-commit-sha is invalid")
    if re.fullmatch(r"[1-9][0-9]*", arguments.workflow_run_id) is None:
        raise EvidenceError("workflow-run-id must be a positive decimal identifier")
    if arguments.workflow_run_attempt < 1:
        raise EvidenceError("workflow-run-attempt must be positive")
    version_raw = read_regular_bytes(repo_root / "VERSION", 128, "VERSION")
    try:
        source_version = version_raw.decode("ascii").strip()
    except UnicodeDecodeError as error:
        raise EvidenceError("VERSION is not ASCII") from error
    if source_version != arguments.version:
        raise EvidenceError("VERSION does not match --version")
    if arguments.archive.name != f"mainframe-{arguments.version}.tar.gz":
        raise EvidenceError("archive basename does not match --version")
    if run_git(repo_root, "rev-parse", "HEAD") != arguments.source_commit_sha:
        raise EvidenceError("Git HEAD does not match source-commit-sha")
    if run_git(repo_root, "rev-parse", arguments.source_ref) != arguments.source_ref_sha:
        raise EvidenceError("Git source ref does not match source-ref-sha")
    if run_git(repo_root, "rev-parse", f"{arguments.source_ref}^{{commit}}") != arguments.source_commit_sha:
        raise EvidenceError("Git source ref does not resolve to source-commit-sha")
    return [
        "VERSION",
        ".github/pi-evidence-contract.json",
        ".github/schemas/pi-cell-evidence.schema.json",
        ".github/scripts/build-pi-cell-evidence.py",
        "config/pi-compatibility.json",
        NATIVE_EXECUTABLE_VALIDATOR_RELATIVE.as_posix(),
    ]


def validate_source_files(
    arguments: argparse.Namespace, repo_root: Path, test_paths: list[str], base_paths: list[str]
) -> list[dict[str, str]]:
    expected_paths = {
        "contract": repo_root / ".github/pi-evidence-contract.json",
        "schema": repo_root / ".github/schemas/pi-cell-evidence.schema.json",
        "generator": repo_root / ".github/scripts/build-pi-cell-evidence.py",
    }
    actual_paths = {
        "contract": arguments.contract.resolve(strict=True),
        "schema": arguments.schema.resolve(strict=True),
        "generator": Path(__file__).resolve(strict=True),
    }
    for name, expected in expected_paths.items():
        if actual_paths[name] != expected.resolve(strict=True):
            raise EvidenceError(f"{name} must be the canonical repository file")
    relative_paths = sorted([*base_paths, *test_paths])
    run_git(repo_root, "ls-files", "--error-unmatch", *relative_paths)
    try:
        run_git(repo_root, "diff", "--quiet", "HEAD", "--", *relative_paths)
    except EvidenceError as error:
        raise EvidenceError("source evidence files differ from the bound Git commit") from error
    return [
        {
            "path": relative,
            "sha256": sha256_bytes(
                read_regular_bytes(repo_root / relative, MAX_TEXT_BYTES, "source evidence file")
            ),
        }
        for relative in relative_paths
    ]


def build_receipt(arguments: argparse.Namespace, repo_root: Path) -> dict[str, Any]:
    contract, contract_raw = load_json(arguments.contract, "Pi evidence contract")
    schema, schema_raw = load_json(arguments.schema, "Pi cell evidence schema")
    if schema.get("$id") != "https://github.com/gtwatts/mainframe/schemas/pi-cell-evidence/v1":
        raise EvidenceError("Pi cell evidence schema id is unsupported")
    test_paths, platforms, pi_versions, cases = validate_contract(contract, repo_root)
    base_paths = validate_source_and_arguments(arguments, repo_root)
    source_files = validate_source_files(arguments, repo_root, test_paths, base_paths)
    platform, observation = observe_platform(arguments.observed_platform, platforms)

    runtime_observation = inspect_pi_runtime(
        arguments.pi_package_root, arguments.pi_runtime_root, arguments.pi_install_prefix
    )
    package_name = runtime_observation["package"]
    package_version = runtime_observation["version"]
    pi_matches = [
        item for item in pi_versions
        if item["package"] == package_name and item["version"] == package_version
    ]
    if len(pi_matches) != 1:
        raise EvidenceError("Pi package.json identity is not unique in the contract")
    pi = pi_matches[0]
    npm_integrity, integrity_file_sha = read_binding(
        arguments.npm_integrity_file, "npm integrity input", NPM_INTEGRITY_RE
    )
    if npm_integrity != pi["npm_integrity"]:
        raise EvidenceError("npm integrity input does not match the Pi contract")

    compatibility, config_raw = load_compatibility(
        repo_root, arguments.version, pi, platform
    )
    archive_raw = read_regular_bytes(arguments.archive, MAX_ARCHIVE_BYTES, "release archive")
    archive_sha = sha256_bytes(archive_raw)
    tests_sha = test_tree_sha256(repo_root, test_paths)
    suffix = f"{pi['id']}-{platform['id']}"
    expected_names = {
        "archive_binding": f"pi-candidate-{suffix}.sha256",
        "test_binding": f"pi-tests-{suffix}.sha256",
        "tap": f"pi-candidate-{suffix}.tap",
    }
    for label, path in (
        ("archive_binding", arguments.archive_binding),
        ("test_binding", arguments.test_binding),
        ("tap", arguments.tap),
    ):
        if path.name != expected_names[label]:
            raise EvidenceError(f"{label} basename does not identify this exact cell")
    bound_archive, archive_binding_sha = read_binding(
        arguments.archive_binding, "archive binding", SHA256_RE
    )
    if bound_archive != archive_sha:
        raise EvidenceError("archive binding does not match the release archive")
    bound_tests, test_binding_sha = read_binding(
        arguments.test_binding, "test binding", SHA256_RE
    )
    if bound_tests != tests_sha:
        raise EvidenceError("test binding does not match the exact source test tree")
    result = parse_tap(arguments.tap, cases, pi["expected_skip"])
    tap_sha = sha256_bytes(read_regular_bytes(arguments.tap, MAX_TEXT_BYTES, "Pi TAP artifact"))
    runtime_proof = validate_runtime_snapshot(
        arguments, pi, suffix, runtime_observation
    )
    node_runtime = validate_node_runtime(
        arguments, repo_root, platform, suffix
    )
    limitations = [
        "This receipt proves one exact-candidate Pi integration conformance cell only; it does not prove live user activation, general agent safety, agent quality, or adoption.",
        "A passing cell does not upgrade compatibility support; support and runtime state are copied from the bound compatibility manifest for this platform.",
        "Package identity, npm integrity, candidate/test bindings, and TAP are represented by bounded values and SHA-256 digests, not by an installed-user attestation.",
    ]
    return {
        "schema_version": 1,
        "kind": "mainframe-pi-exact-candidate-cell-evidence",
        "claim_scope": "exact-candidate-single-cell-pi-integration-conformance-only",
        "cell_id": f"{pi['id']}@{platform['id']}",
        "mainframe": {
            "version": arguments.version,
            "archive_name": arguments.archive.name,
            "archive_size": len(archive_raw),
            "archive_sha256": archive_sha,
        },
        "source": {
            "repository": arguments.repository,
            "ref": arguments.source_ref,
            "ref_sha": arguments.source_ref_sha,
            "commit_sha": arguments.source_commit_sha,
            "workflow_run_id": arguments.workflow_run_id,
            "workflow_run_attempt": arguments.workflow_run_attempt,
            "binding_mode": "git-head-clean-tracked-files",
            "files": source_files,
        },
        "host": {"platform": platform, **observation},
        "pi": {
            "id": pi["id"],
            "package": pi["package"],
            "version": pi["version"],
            "profile": pi["profile"],
            "npm_integrity": npm_integrity,
            "package_json_name": "package.json",
            "package_json_sha256": sha256_bytes(runtime_observation["package_json_raw"]),
            "package_tree_sha256": runtime_observation["package_tree_sha256"],
            "runtime_root_name": "node_modules",
            "runtime_tree_sha256": runtime_observation["runtime_tree_sha256"],
            "runtime_entry": ".bin/pi",
            "integrity_input": {
                "name": arguments.npm_integrity_file.name,
                "file_sha256": integrity_file_sha,
                "binding_value": npm_integrity,
            },
        },
        "node_runtime": node_runtime,
        "runtime_proof": runtime_proof,
        "compatibility": compatibility,
        "producer": {
            "contract_sha256": sha256_bytes(contract_raw),
            "config_sha256": sha256_bytes(config_raw),
            "schema_sha256": sha256_bytes(schema_raw),
            "generator_sha256": sha256_bytes(
                read_regular_bytes(Path(__file__).resolve(strict=True), MAX_TEXT_BYTES, "generator")
            ),
        },
        "tests": {
            "canonicalization": contract["test_tree_algorithm"],
            "paths": list(test_paths),
            "source_tree_sha256": tests_sha,
            "plan": contract["plan_per_run"],
            "bats_core_commit": contract["bats_core_commit"],
            "cases": cases,
        },
        "artifacts": {
            "archive_binding": {
                "name": arguments.archive_binding.name,
                "file_sha256": archive_binding_sha,
                "binding_value": bound_archive,
            },
            "test_binding": {
                "name": arguments.test_binding.name,
                "file_sha256": test_binding_sha,
                "binding_value": bound_tests,
            },
            "tap": {
                "name": arguments.tap.name,
                "file_sha256": tap_sha,
                "binding_value": None,
            },
        },
        "result": result,
        "limitations": limitations,
    }


def atomic_write(path: Path, raw: bytes, mode: int = 0o644) -> None:
    parent = path.parent
    if parent.is_symlink() or not parent.is_dir():
        raise EvidenceError(f"output parent must be a real directory: {parent}")
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(raw)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, mode)
        try:
            os.link(temporary, path)
        except FileExistsError as error:
            raise EvidenceError(f"output must be absent: {path}") from error
        directory_descriptor = os.open(parent, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    finally:
        if temporary.exists():
            temporary.unlink()


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    subparsers = root.add_subparsers(dest="action", required=True)
    snapshot = subparsers.add_parser("snapshot-runtime")
    snapshot.add_argument("--pi-package-root", type=Path, required=True)
    snapshot.add_argument("--pi-runtime-root", type=Path, required=True)
    snapshot.add_argument("--pi-install-prefix", type=Path, required=True)
    snapshot.add_argument("--expected-package", required=True)
    snapshot.add_argument("--expected-version", required=True)
    snapshot.add_argument("--output", type=Path, required=True)
    node_snapshot = subparsers.add_parser("snapshot-node")
    node_snapshot.add_argument("--repo-root", type=Path, required=True)
    node_snapshot.add_argument("--node-executable", type=Path, required=True)
    node_snapshot.add_argument("--expected-os", choices=("Darwin", "Linux"), required=True)
    node_snapshot.add_argument("--expected-arch", choices=("arm64", "x86_64"), required=True)
    node_snapshot.add_argument("--output", type=Path, required=True)
    for action in ("create", "verify"):
        command = subparsers.add_parser(action)
        command.add_argument("--contract", type=Path, required=True)
        command.add_argument("--schema", type=Path, required=True)
        command.add_argument("--repo-root", type=Path, required=True)
        command.add_argument("--archive", type=Path, required=True)
        command.add_argument("--pi-package-root", type=Path, required=True)
        command.add_argument("--pi-runtime-root", type=Path, required=True)
        command.add_argument("--pi-install-prefix", type=Path, required=True)
        command.add_argument("--pre-test-runtime-snapshot", type=Path, required=True)
        command.add_argument("--pre-test-runtime-snapshot-sha256", required=True)
        command.add_argument("--node-executable", type=Path, required=True)
        command.add_argument("--expected-node-arch", choices=("arm64", "x86_64"), required=True)
        command.add_argument("--pre-test-node-binding", type=Path, required=True)
        command.add_argument("--pre-test-node-binding-sha256", required=True)
        command.add_argument("--npm-integrity-file", type=Path, required=True)
        command.add_argument("--archive-binding", type=Path, required=True)
        command.add_argument("--test-binding", type=Path, required=True)
        command.add_argument("--tap", type=Path, required=True)
        command.add_argument("--repository", required=True)
        command.add_argument("--version", required=True)
        command.add_argument("--source-ref", required=True)
        command.add_argument("--source-ref-sha", required=True)
        command.add_argument("--source-commit-sha", required=True)
        command.add_argument("--workflow-run-id", required=True)
        command.add_argument("--workflow-run-attempt", type=int, required=True)
        command.add_argument("--observed-platform")
        if action == "create":
            command.add_argument("--output", type=Path, required=True)
        else:
            command.add_argument("--evidence", type=Path, required=True)
    return root


def main() -> int:
    arguments = parser().parse_args()
    try:
        if arguments.action == "snapshot-runtime":
            arguments.pi_package_root = arguments.pi_package_root.absolute()
            arguments.pi_runtime_root = arguments.pi_runtime_root.absolute()
            arguments.pi_install_prefix = arguments.pi_install_prefix.absolute()
            snapshot = runtime_snapshot(arguments)
            atomic_write(arguments.output.absolute(), canonical_json(snapshot))
            print(f"Pre-test Pi runtime snapshot created: {arguments.output.absolute()}")
            return 0
        if arguments.action == "snapshot-node":
            arguments.repo_root = arguments.repo_root.absolute()
            arguments.node_executable = arguments.node_executable.absolute()
            snapshot = node_binding_snapshot(arguments)
            atomic_write(arguments.output.absolute(), canonical_json(snapshot), mode=0o600)
            print(f"Pre-test Pi Node binding created: {arguments.output.absolute()}")
            return 0
        repo_input = arguments.repo_root.absolute()
        metadata = repo_input.lstat()
        if repo_input.is_symlink() or not stat.S_ISDIR(metadata.st_mode):
            raise EvidenceError("repo-root must be a real directory")
        repo_root = repo_input.resolve(strict=True)
        for name in (
            "contract", "schema", "archive", "pi_package_root", "pi_runtime_root",
            "pi_install_prefix", "pre_test_runtime_snapshot", "npm_integrity_file",
            "node_executable", "pre_test_node_binding", "archive_binding",
            "test_binding", "tap",
        ):
            setattr(arguments, name, getattr(arguments, name).absolute())
        receipt = build_receipt(arguments, repo_root)
        if arguments.action == "create":
            atomic_write(arguments.output.absolute(), canonical_json(receipt))
            print(f"Pi cell evidence created: {arguments.output.absolute()}")
            return 0
        evidence, raw = load_json(arguments.evidence.absolute(), "Pi cell evidence receipt")
        if raw != canonical_json(evidence):
            raise EvidenceError("Pi cell evidence receipt is not canonical sorted-key JSON")
        if not strict_equal(evidence, receipt):
            raise EvidenceError("Pi cell evidence receipt does not match source and raw artifacts")
        print("Pi cell evidence and raw artifacts valid")
        return 0
    except (EvidenceError, OSError) as error:
        fail(str(error))


if __name__ == "__main__":
    raise SystemExit(main())

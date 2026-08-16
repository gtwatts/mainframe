#!/usr/bin/env python3
"""Bind an offline Pi/Ollama study runtime without executing either runtime.

Only ``prepare`` and ``verify`` exist.  This module deliberately has no
process-launch, process-inspection, provider, transport, network, or inference
implementation.  It must be entered through an isolated, site-disabled,
bytecode-disabled Python 3.9+ interpreter (``python3 -I -S -B``).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import struct
import sys
from typing import Any, Dict, List, NoReturn, Optional, Sequence, Set, Tuple


CLAIM_SCOPE = "offline-pi-ollama-runtime-binding-and-neutral-arm-contract-preflight-only"
SPEC_KIND = "mainframe-agent-impact-pi-ollama-preflight-spec"
ARM_KIND = "mainframe-agent-impact-pi-ollama-neutral-arm-contract"
RECEIPT_KIND = "mainframe-agent-impact-pi-ollama-preflight-receipt"
ADAPTER_ID = "mainframe-pi-ollama-dormant-v1"
ADAPTER_VERSION = "1.0.0"
MAINFRAME_TREE_ALGORITHM = "mainframe-package-tree-sha256-v1"
PI_TREE_ALGORITHM = "mainframe-pi-runtime-tree-sha256-v1"
MAINFRAME_TREE_DOMAIN = b"MAINFRAME-PACKAGE-TREE-SHA256-V1\0"
PI_TREE_DOMAIN = b"MAINFRAME-PI-RUNTIME-TREE-SHA256-V1\0"
RUNTIME_BINDING_ALGORITHM = "canonical-runtime-projection-sha256-v1"
RUNTIME_BINDING_DOMAIN = b"MAINFRAME-AGENT-IMPACT-RUNTIME-PROJECTION-V1\0"
MODEL_CLOSURE_ALGORITHM = "canonical-ollama-manifest-dependency-closure-sha256-v1"
MODEL_CLOSURE_DOMAIN = b"MAINFRAME-OLLAMA-MANIFEST-DEPENDENCY-CLOSURE-V1\0"
HOMEBREW_RECEIPT_FORMAT = "homebrew-install-receipt-v1"
MAINFRAME_RECEIPT_FORMAT = "mainframe-release-archive-install-receipt-v1"
MANIFEST_MEDIA_TYPE = "application/vnd.docker.distribution.manifest.v2+json"
CONFIG_MEDIA_TYPE = "application/vnd.docker.container.image.v1+json"
MODEL_MEDIA_TYPE = "application/vnd.ollama.image.model"
TEMPLATE_MEDIA_TYPE = "application/vnd.ollama.image.template"
MAX_JSON_BYTES = 8 * 1024 * 1024
MAX_TEXT_BYTES = 64 * 1024 * 1024
MAX_FILE_BYTES = 1024 * 1024 * 1024 * 1024
MAX_TREE_ENTRIES = 250_000
MAX_TREE_FILE_BYTES = 256 * 1024 * 1024
MAX_TREE_TOTAL_BYTES = 4 * 1024 * 1024 * 1024
MAX_BINARY_BYTES = 64 * 1024 * 1024
MAX_SYMLINK_DEPTH = 40
READ_CHUNK = 1024 * 1024
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
QUALIFIED_SHA256_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,127}$")
CERTIFICATION_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]{0,255}$")
VERSION_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/+:-]{0,255}$")
PACKAGE_RE = re.compile(r"^(?:@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]{0,127}$")
MODEL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/:+-]{0,255}$")
PAIR_RE = re.compile(r"^pair-[0-9a-f]{16}$")
ARM_RE = re.compile(r"^arm-[0-9a-f]{16}$")
FORBIDDEN_KEYS = frozenset(("arm_mode", "assignment", "control", "mechanism", "treatment"))
FORBIDDEN_VALUES = frozenset(("control", "mainframe-awm-handoff", "native-bounded-handoff", "treatment"))
TRUSTED_UIDS = frozenset((0, os.geteuid()))
BROAD_TREE_ROOTS = frozenset((
    "/Applications", "/bin", "/dev", "/etc", "/home", "/Library",
    "/media", "/mnt", "/opt", "/opt/homebrew", "/private", "/private/tmp",
    "/proc", "/root", "/run", "/sbin", "/srv", "/sys", "/System",
    "/tmp", "/usr", "/usr/local", "/var", "/Volumes", "/Users",
))
RUNTIME_PROJECTION_KEYS = (
    "schema_version", "kind", "claim_scope", "platform", "node", "mainframe",
    "pi", "ollama", "adapter", "protocol",
)
SPEC_SCHEMA_ID = (
    "https://github.com/gtwatts/mainframe/schemas/"
    "agent-impact-pi-ollama-preflight-spec-v1.json")
RECEIPT_SCHEMA_ID = (
    "https://github.com/gtwatts/mainframe/schemas/"
    "agent-impact-pi-ollama-preflight-receipt-v1.json")
ARM_SCHEMA_ID = (
    "https://github.com/gtwatts/mainframe/schemas/"
    "agent-impact-pi-ollama-arm-contract-v1.json")
REQUEST_SCHEMA_ID = (
    "https://github.com/gtwatts/mainframe/schemas/"
    "agent-impact-pi-ollama-adapter-request-v1.json")
RESULT_SCHEMA_ID = (
    "https://github.com/gtwatts/mainframe/schemas/"
    "agent-impact-pi-ollama-adapter-result-v1.json")


class PreflightError(RuntimeError):
    """A closed-contract or local-input violation."""


def fail(message: str) -> NoReturn:
    raise PreflightError(message)


def canonical_json(value: Any) -> bytes:
    try:
        return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True,
                           allow_nan=False) + "\n").encode("utf-8")
    except (TypeError, ValueError) as error:
        fail("value cannot be encoded as canonical JSON: {}".format(error))


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def exact_keys(value: Any, expected: Sequence[str], label: str) -> Dict[str, Any]:
    if not isinstance(value, dict):
        fail("{} must be an object".format(label))
    actual = set(value)
    wanted = set(expected)
    if actual != wanted:
        fail("{} keys differ (missing={}, extra={})".format(
            label, sorted(wanted - actual), sorted(actual - wanted)))
    return value


def require_string(value: Any, label: str, pattern: Optional[re.Pattern] = None,
                   maximum: int = 4096) -> str:
    if not isinstance(value, str) or not value:
        fail("{} must be a bounded non-empty string".format(label))
    try:
        encoded = value.encode("utf-8")
    except UnicodeEncodeError:
        fail("{} is not valid Unicode".format(label))
    if len(encoded) > maximum:
        fail("{} must be a bounded non-empty string".format(label))
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        fail("{} contains a control character".format(label))
    if pattern is not None and pattern.fullmatch(value) is None:
        fail("{} has an invalid value".format(label))
    return value


def require_integer(value: Any, label: str, minimum: int, maximum: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
        fail("{} must be an integer in [{}, {}]".format(label, minimum, maximum))
    return value


def require_constant(value: Any, expected: Any, label: str) -> Any:
    if type(value) is not type(expected) or value != expected:
        fail("{} must equal {!r}".format(label, expected))
    return value


def reject_duplicate_keys(label: str):
    def hook(pairs: List[Tuple[str, Any]]) -> Dict[str, Any]:
        result: Dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                fail("{} contains duplicate key {!r}".format(label, key))
            result[key] = value
        return result
    return hook


def parse_json(raw: bytes, label: str) -> Dict[str, Any]:
    try:
        text = raw.decode("utf-8")
        value = json.loads(text, object_pairs_hook=reject_duplicate_keys(label),
                           parse_constant=lambda token: fail(
                               "{} contains non-finite number {}".format(label, token)))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail("{} is not strict UTF-8 JSON: {}".format(label, error))
    if not isinstance(value, dict):
        fail("{} root must be an object".format(label))
    return value


def canonical_absolute_path(value: Any, label: str) -> str:
    path = require_string(value, label, maximum=4096)
    if (not path.startswith("/") or path.startswith("//") or path == "/" or
            os.path.normpath(path) != path):
        fail("{} must be a canonical non-root absolute path".format(label))
    if os.fsdecode(os.fsencode(path)) != path:
        fail("{} is not a lossless filesystem path".format(label))
    return path


def trusted_metadata(metadata: os.stat_result, label: str, directory: bool,
                     ancestry: bool = False) -> None:
    if metadata.st_uid not in TRUSTED_UIDS:
        fail("{} has an untrusted owner".format(label))
    mode = stat.S_IMODE(metadata.st_mode)
    if mode & 0o002:
        if not (directory and metadata.st_uid == 0 and mode & stat.S_ISVTX):
            fail("{} is world-writable".format(label))
    if mode & 0o020:
        # Homebrew intentionally uses current-user-owned 0775 Cellar/lib
        # ancestors. Accept that only during traversal. Every bound leaf and
        # every hashed tree root/entry remains non-group-writable, and this
        # receipt explicitly makes no hostile-local-account isolation claim.
        if not ((ancestry and directory and metadata.st_uid == os.geteuid()) or
                (directory and metadata.st_uid == 0 and mode == 0o1777)):
            fail("{} is group-writable".format(label))
    if mode & 0o7000 and not (directory and metadata.st_uid == 0 and mode == 0o1777):
        fail("{} has unsafe special mode bits".format(label))


def metadata_identity(metadata: os.stat_result) -> Tuple[int, ...]:
    return (metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_nlink,
            metadata.st_uid, metadata.st_gid, metadata.st_size,
            metadata.st_mtime_ns, metadata.st_ctime_ns)


def directory_identity(metadata: os.stat_result) -> Tuple[int, ...]:
    return (metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_uid,
            metadata.st_gid, metadata.st_mtime_ns, metadata.st_ctime_ns)


def directory_flags() -> int:
    flags = os.O_RDONLY
    flags |= getattr(os, "O_CLOEXEC", 0)
    flags |= getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    return flags


def file_flags() -> int:
    return (os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) |
            getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))


def open_directory_chain(path: str, label: str) -> int:
    """Open one physical directory by no-follow openat traversal."""
    canonical_absolute_path(path, label)
    descriptor = os.open("/", directory_flags())
    try:
        for index, component in enumerate(path.split("/")[1:]):
            if not component or component in (".", ".."):
                fail("{} contains a non-canonical component".format(label))
            child = os.open(component, directory_flags(), dir_fd=descriptor)
            metadata = os.fstat(child)
            if not stat.S_ISDIR(metadata.st_mode):
                os.close(child)
                fail("{} ancestor is not a real directory".format(label))
            trusted_metadata(metadata, "{} ancestor {}".format(label, index + 1),
                             True, ancestry=True)
            os.close(descriptor)
            descriptor = child
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def split_file_path(path: str, label: str) -> Tuple[str, str]:
    canonical_absolute_path(path, label)
    parent, basename = os.path.split(path)
    if not basename or basename in (".", ".."):
        fail("{} has an unsafe basename".format(label))
    return parent, basename


def read_open_descriptor(descriptor: int, label: str, maximum: int,
                         capture: bool) -> Tuple[bytes, str, os.stat_result]:
    before = os.fstat(descriptor)
    if not stat.S_ISREG(before.st_mode):
        fail("{} must be a regular non-symlink file".format(label))
    if before.st_nlink != 1:
        fail("{} must not be hard-linked".format(label))
    trusted_metadata(before, label, False)
    if before.st_size <= 0 or before.st_size > maximum:
        fail("{} has an unsupported size".format(label))
    digest = hashlib.sha256()
    chunks: List[bytes] = []
    count = 0
    while True:
        chunk = os.read(descriptor, READ_CHUNK)
        if not chunk:
            break
        count += len(chunk)
        digest.update(chunk)
        if capture:
            chunks.append(chunk)
    after = os.fstat(descriptor)
    if count != before.st_size or metadata_identity(before) != metadata_identity(after):
        fail("{} changed while it was read".format(label))
    return (b"".join(chunks), digest.hexdigest(), before)


def read_file(path: str, label: str, maximum: int = MAX_FILE_BYTES,
              capture: bool = True, executable: bool = False,
              ledger: Optional["IdentityLedger"] = None) -> Dict[str, Any]:
    parent, basename = split_file_path(path, label)
    try:
        parent_fd = open_directory_chain(parent, "{} parent".format(label))
    except OSError as error:
        fail("{} parent cannot be opened safely: {}".format(label, error))
    descriptor = -1
    try:
        parent_before = os.fstat(parent_fd)
        before_open = os.stat(basename, dir_fd=parent_fd, follow_symlinks=False)
        if not stat.S_ISREG(before_open.st_mode):
            fail("{} must be a regular non-symlink file".format(label))
        if before_open.st_nlink != 1:
            fail("{} must not be hard-linked".format(label))
        trusted_metadata(before_open, label, False)
        descriptor = os.open(basename, file_flags(), dir_fd=parent_fd)
        raw, digest, metadata = read_open_descriptor(descriptor, label, maximum, capture)
        if metadata_identity(before_open) != metadata_identity(metadata):
            fail("{} changed before it was opened".format(label))
        if executable and not stat.S_IMODE(metadata.st_mode) & 0o111:
            fail("{} must have an executable mode bit".format(label))
        parent_after = os.fstat(parent_fd)
        if directory_identity(parent_before) != directory_identity(parent_after):
            fail("{} parent changed while the file was read".format(label))
        observed = {
            "raw": raw,
            "sha256": digest,
            "size_bytes": metadata.st_size,
            "mode": format(stat.S_IMODE(metadata.st_mode), "04o"),
            "executable": bool(stat.S_IMODE(metadata.st_mode) & 0o111),
            "path": path,
            "basename": basename,
            "identity": metadata_identity(metadata),
        }
        if ledger is not None:
            ledger.remember_file(label, observed, maximum, executable)
        return observed
    except OSError as error:
        fail("{} cannot be opened safely: {}".format(label, error))
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        os.close(parent_fd)


def validate_file_binding(value: Any, label: str, maximum: int = MAX_FILE_BYTES,
                          capture: bool = True, executable: bool = False,
                          ledger: Optional["IdentityLedger"] = None) -> Dict[str, Any]:
    binding = exact_keys(value, ("path", "sha256", "size_bytes"), label)
    path = canonical_absolute_path(binding["path"], "{} path".format(label))
    expected_sha = require_string(binding["sha256"], "{} sha256".format(label), SHA256_RE, 64)
    expected_size = require_integer(binding["size_bytes"], "{} size".format(label), 1, maximum)
    observed = read_file(path, label, maximum=maximum, capture=capture,
                         executable=executable, ledger=ledger)
    if observed["sha256"] != expected_sha or observed["size_bytes"] != expected_size:
        fail("{} does not match its declared digest and size".format(label))
    return observed


def receipt_file(label: str, observed: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "label": label,
        "basename": observed["basename"],
        "path_sha256": sha256_bytes(observed["path"].encode("utf-8")),
        "size_bytes": observed["size_bytes"],
        "sha256": observed["sha256"],
        "mode": observed["mode"],
        "owner_trust": "root-or-current-user",
        "executable": observed["executable"],
    }


def load_bound_json(value: Any, label: str, maximum: int = MAX_JSON_BYTES,
                    ledger: Optional["IdentityLedger"] = None) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    observed = validate_file_binding(value, label, maximum=maximum, capture=True,
                                     ledger=ledger)
    return parse_json(observed["raw"], label), observed


class IdentityLedger:
    """Remember coherent bindings and re-read every one before acceptance."""

    def __init__(self) -> None:
        self._files: List[Tuple[str, str, str, int, Tuple[int, ...], int, bool]] = []
        self._trees: List[Tuple[str, str, str, str, int]] = []

    def remember_file(self, label: str, observed: Dict[str, Any], maximum: int,
                      executable: bool) -> None:
        record = (label, observed["path"], observed["sha256"],
                  observed["size_bytes"], observed["identity"], maximum, executable)
        if record not in self._files:
            self._files.append(record)

    def remember_tree(self, label: str, observed: Dict[str, Any]) -> None:
        record = (label, observed["root"], observed["algorithm"],
                  observed["sha256"], observed["entry_count"])
        if record not in self._trees:
            self._trees.append(record)

    def file_paths(self) -> Set[str]:
        return {record[1] for record in self._files}

    def contains_file_identity(self, identity: Tuple[int, ...]) -> bool:
        return any(record[4] == identity for record in self._files)

    def revalidate(self) -> None:
        for label, path, digest, size, identity, maximum, executable in self._files:
            observed = read_file(path, "{} final revalidation".format(label),
                                 maximum=maximum, capture=False,
                                 executable=executable, ledger=None)
            if (observed["sha256"] != digest or observed["size_bytes"] != size or
                    observed["identity"] != identity):
                fail("{} changed before preflight acceptance".format(label))
        for label, root, algorithm, digest, entry_count in self._trees:
            if algorithm == MAINFRAME_TREE_ALGORITHM:
                observed = hash_mainframe_package_tree(root, label, ledger=None)
            elif algorithm == PI_TREE_ALGORITHM:
                observed = hash_pi_runtime_tree(root, label, ledger=None)
            else:
                fail("{} has an unsupported tree algorithm".format(label))
            if observed["sha256"] != digest or observed["entry_count"] != entry_count:
                fail("{} changed before preflight acceptance".format(label))


def _safe_tree_name(name: str, label: str) -> bytes:
    if (not name or name in (".", "..") or os.sep in name or
            any(ord(character) < 32 or ord(character) == 127 for character in name)):
        fail("{} contains an unsafe entry name".format(label))
    try:
        encoded = name.encode("utf-8")
    except UnicodeEncodeError:
        fail("{} entry name is not UTF-8".format(label))
    if os.fsdecode(os.fsencode(name)) != name or b"\0" in encoded:
        fail("{} entry name is not lossless".format(label))
    return encoded


def _tree_root(path: str, label: str) -> Tuple[int, os.stat_result]:
    root = canonical_absolute_path(path, "{} root".format(label))
    if root in BROAD_TREE_ROOTS:
        fail("{} root is too broad".format(label))
    try:
        descriptor = open_directory_chain(root, "{} root".format(label))
        metadata = os.fstat(descriptor)
        trusted_metadata(metadata, "{} root".format(label), True)
        return descriptor, metadata
    except OSError as error:
        fail("{} root cannot be opened safely: {}".format(label, error))


def _inventory_tree(root_fd: int, root_metadata: os.stat_result, label: str,
                    allow_symlinks: bool) -> List[Dict[str, Any]]:
    entries: List[Dict[str, Any]] = []

    def walk(directory_fd: int, prefix: str) -> None:
        directory_before = os.fstat(directory_fd)
        try:
            names = os.listdir(directory_fd)
        except OSError as error:
            fail("{} directory cannot be enumerated: {}".format(label, error))
        names.sort()
        for name in names:
            _safe_tree_name(name, label)
            relative = name if not prefix else prefix + "/" + name
            try:
                before = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            except OSError as error:
                fail("{} entry cannot be inspected: {}: {}".format(label, relative, error))
            if before.st_dev != root_metadata.st_dev:
                fail("{} crosses a filesystem boundary: {}".format(label, relative))
            if stat.S_ISDIR(before.st_mode):
                trusted_metadata(before, "{} directory {}".format(label, relative), True)
                entry = {"relative": relative, "kind": "D",
                         "identity": directory_identity(before),
                         "mode": stat.S_IMODE(before.st_mode)}
                entries.append(entry)
                child = -1
                try:
                    child = os.open(name, directory_flags(), dir_fd=directory_fd)
                    opened = os.fstat(child)
                    if directory_identity(opened) != entry["identity"]:
                        fail("{} directory changed before open: {}".format(label, relative))
                    walk(child, relative)
                    if directory_identity(os.fstat(child)) != entry["identity"]:
                        fail("{} directory changed while read: {}".format(label, relative))
                except OSError as error:
                    fail("{} directory cannot be opened safely: {}: {}".format(
                        label, relative, error))
                finally:
                    if child >= 0:
                        os.close(child)
            elif stat.S_ISREG(before.st_mode):
                if before.st_nlink != 1:
                    fail("{} contains a hard-linked file: {}".format(label, relative))
                trusted_metadata(before, "{} file {}".format(label, relative), False)
                if before.st_size < 0 or before.st_size > MAX_TREE_FILE_BYTES:
                    fail("{} file has an unsupported size: {}".format(label, relative))
                entries.append({"relative": relative, "kind": "F",
                                "identity": metadata_identity(before),
                                "mode": stat.S_IMODE(before.st_mode),
                                "size": before.st_size})
            elif stat.S_ISLNK(before.st_mode) and allow_symlinks:
                if before.st_nlink != 1:
                    fail("{} contains a hard-linked symlink: {}".format(label, relative))
                if before.st_uid not in TRUSTED_UIDS:
                    fail("{} symlink has an untrusted owner: {}".format(label, relative))
                try:
                    target = os.readlink(name, dir_fd=directory_fd)
                    after = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
                except OSError as error:
                    fail("{} symlink cannot be read: {}: {}".format(label, relative, error))
                if metadata_identity(before) != metadata_identity(after):
                    fail("{} symlink changed while read: {}".format(label, relative))
                _canonical_symlink_target(target, "{} symlink {}".format(label, relative))
                entries.append({"relative": relative, "kind": "L",
                                "identity": metadata_identity(before),
                                "mode": stat.S_IMODE(before.st_mode), "target": target})
            elif stat.S_ISLNK(before.st_mode):
                fail("{} contains a symbolic link: {}".format(label, relative))
            else:
                fail("{} contains a special entry: {}".format(label, relative))
            if len(entries) > MAX_TREE_ENTRIES:
                fail("{} exceeds the entry ceiling".format(label))
        if directory_identity(os.fstat(directory_fd)) != directory_identity(directory_before):
            fail("{} directory changed while enumerated: {}".format(
                label, prefix or "."))

    walk(root_fd, "")
    entries.sort(key=lambda entry: entry["relative"])
    total = sum(entry.get("size", 0) for entry in entries)
    if total > MAX_TREE_TOTAL_BYTES:
        fail("{} exceeds the total-byte ceiling".format(label))
    return entries


def _canonical_symlink_target(target: str, label: str) -> bytes:
    if (not isinstance(target, str) or not target or os.path.isabs(target) or
            os.path.normpath(target) != target):
        fail("{} target must be canonical and relative".format(label))
    try:
        encoded = target.encode("utf-8")
    except UnicodeEncodeError:
        fail("{} target is not UTF-8".format(label))
    if os.fsdecode(os.fsencode(target)) != target or b"\0" in encoded:
        fail("{} target is not lossless".format(label))
    return encoded


def _normalized_inside_target(symlink_relative: str, target: str, label: str) -> str:
    combined = os.path.normpath(os.path.join(os.path.dirname(symlink_relative), target))
    if (combined in ("", ".", "..") or combined.startswith("../") or
            os.path.isabs(combined)):
        fail("{} symlink escapes or resolves to the runtime-tree root".format(label))
    return combined


def _validate_symlink_resolution(entry: Dict[str, Any],
                                 inventory: Dict[str, Dict[str, Any]], label: str) -> None:
    pending = _normalized_inside_target(entry["relative"], entry["target"], label)
    visited: Set[str] = {entry["relative"]}
    for _depth in range(MAX_SYMLINK_DEPTH):
        components = pending.split("/")
        restarted = False
        for index in range(len(components)):
            relative = "/".join(components[:index + 1])
            target_entry = inventory.get(relative)
            if target_entry is None:
                fail("{} symlink is dangling: {}".format(label, entry["relative"]))
            if target_entry["kind"] == "L":
                if relative in visited:
                    fail("{} symlink cycle detected: {}".format(label, entry["relative"]))
                visited.add(relative)
                replacement = _normalized_inside_target(relative, target_entry["target"], label)
                suffix = components[index + 1:]
                pending = os.path.normpath(os.path.join(replacement, *suffix))
                if pending in ("", ".", "..") or pending.startswith("../"):
                    fail("{} symlink escapes the runtime tree".format(label))
                restarted = True
                break
            if index < len(components) - 1 and target_entry["kind"] != "D":
                fail("{} symlink traverses a non-directory".format(label))
        if not restarted:
            return
    fail("{} symlink resolution exceeds the depth ceiling".format(label))


def _open_inventory_parent(root_fd: int, relative: str,
                           inventory: Dict[str, Dict[str, Any]], label: str) -> Tuple[int, str]:
    components = relative.split("/")
    descriptor = os.dup(root_fd)
    prefix: List[str] = []
    try:
        for component in components[:-1]:
            prefix.append(component)
            expected = inventory.get("/".join(prefix))
            if expected is None or expected["kind"] != "D":
                fail("{} inventory parent is not a directory".format(label))
            child = os.open(component, directory_flags(), dir_fd=descriptor)
            if directory_identity(os.fstat(child)) != expected["identity"]:
                os.close(child)
                fail("{} directory changed during hashing: {}".format(
                    label, "/".join(prefix)))
            os.close(descriptor)
            descriptor = child
        return descriptor, components[-1]
    except Exception:
        os.close(descriptor)
        raise


def _hash_inventory_file(root_fd: int, entry: Dict[str, Any],
                         inventory: Dict[str, Dict[str, Any]], digest: Any,
                         label: str) -> None:
    parent_fd, basename = _open_inventory_parent(root_fd, entry["relative"], inventory, label)
    descriptor = -1
    try:
        before_open = os.stat(basename, dir_fd=parent_fd, follow_symlinks=False)
        if metadata_identity(before_open) != entry["identity"]:
            fail("{} file changed before hashing: {}".format(label, entry["relative"]))
        descriptor = os.open(basename, file_flags(), dir_fd=parent_fd)
        opened = os.fstat(descriptor)
        if metadata_identity(opened) != entry["identity"] or not stat.S_ISREG(opened.st_mode):
            fail("{} file changed while opened: {}".format(label, entry["relative"]))
        count = 0
        while True:
            chunk = os.read(descriptor, READ_CHUNK)
            if not chunk:
                break
            count += len(chunk)
            digest.update(chunk)
        after = os.fstat(descriptor)
        if count != entry["size"] or metadata_identity(after) != entry["identity"]:
            fail("{} file changed while hashing: {}".format(label, entry["relative"]))
    except OSError as error:
        fail("{} file cannot be hashed safely: {}: {}".format(
            label, entry["relative"], error))
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        os.close(parent_fd)


def _revalidate_symlink(root_fd: int, entry: Dict[str, Any],
                        inventory: Dict[str, Dict[str, Any]], label: str) -> bytes:
    parent_fd, basename = _open_inventory_parent(root_fd, entry["relative"], inventory, label)
    try:
        before = os.stat(basename, dir_fd=parent_fd, follow_symlinks=False)
        if metadata_identity(before) != entry["identity"] or not stat.S_ISLNK(before.st_mode):
            fail("{} symlink changed before hashing: {}".format(label, entry["relative"]))
        target = os.readlink(basename, dir_fd=parent_fd)
        after = os.stat(basename, dir_fd=parent_fd, follow_symlinks=False)
        if metadata_identity(after) != entry["identity"] or target != entry["target"]:
            fail("{} symlink changed while hashing: {}".format(label, entry["relative"]))
        return _canonical_symlink_target(target, "{} symlink {}".format(
            label, entry["relative"]))
    except OSError as error:
        fail("{} symlink cannot be revalidated: {}: {}".format(
            label, entry["relative"], error))
    finally:
        os.close(parent_fd)


def hash_mainframe_package_tree(root: str, label: str = "MAINFRAME installed tree",
                                ledger: Optional[IdentityLedger] = None) -> Dict[str, Any]:
    """Hash the exact existing MAINFRAME package-tree-v1 byte contract."""
    root_fd, root_metadata = _tree_root(root, label)
    try:
        entries = _inventory_tree(root_fd, root_metadata, label, allow_symlinks=False)
        inventory = {entry["relative"]: entry for entry in entries}
        digest = hashlib.sha256(MAINFRAME_TREE_DOMAIN)
        for entry in entries:
            encoded = entry["relative"].encode("utf-8")
            if entry["kind"] == "D":
                digest.update(b"D\0" + encoded + b"\0")
            else:
                digest.update(b"F\0" + encoded + b"\0")
                digest.update(str(entry["size"]).encode("ascii") + b"\0")
                _hash_inventory_file(root_fd, entry, inventory, digest, label)
        if directory_identity(os.fstat(root_fd)) != directory_identity(root_metadata):
            fail("{} root changed while hashing".format(label))
        observed = {"root": root, "algorithm": MAINFRAME_TREE_ALGORITHM,
                    "sha256": digest.hexdigest(), "entry_count": len(entries),
                    "total_file_bytes": sum(entry.get("size", 0) for entry in entries)}
        if ledger is not None:
            ledger.remember_tree(label, observed)
        return observed
    finally:
        os.close(root_fd)


def hash_pi_runtime_tree(root: str, label: str = "Pi package runtime tree",
                         ledger: Optional[IdentityLedger] = None) -> Dict[str, Any]:
    """Hash Pi's mode- and contained-symlink-aware runtime-tree-v1 contract."""
    root_fd, root_metadata = _tree_root(root, label)
    try:
        entries = _inventory_tree(root_fd, root_metadata, label, allow_symlinks=True)
        inventory = {entry["relative"]: entry for entry in entries}
        for entry in entries:
            if entry["kind"] == "L":
                _validate_symlink_resolution(entry, inventory, label)
        digest = hashlib.sha256(PI_TREE_DOMAIN)
        digest.update(b"R\0" + format(stat.S_IMODE(root_metadata.st_mode), "04o").encode("ascii") + b"\0")
        for entry in entries:
            encoded = entry["relative"].encode("utf-8")
            if entry["kind"] == "D":
                digest.update(b"D\0" + encoded + b"\0")
                digest.update(format(entry["mode"], "04o").encode("ascii") + b"\0")
            elif entry["kind"] == "F":
                digest.update(b"F\0" + encoded + b"\0")
                digest.update(format(entry["mode"], "04o").encode("ascii") + b"\0")
                digest.update(str(entry["size"]).encode("ascii") + b"\0")
                _hash_inventory_file(root_fd, entry, inventory, digest, label)
            else:
                target = _revalidate_symlink(root_fd, entry, inventory, label)
                digest.update(b"L\0" + encoded + b"\0")
                digest.update(format(entry["mode"], "04o").encode("ascii") + b"\0")
                digest.update(str(len(target)).encode("ascii") + b"\0")
                digest.update(target)
        if directory_identity(os.fstat(root_fd)) != directory_identity(root_metadata):
            fail("{} root changed while hashing".format(label))
        observed = {"root": root, "algorithm": PI_TREE_ALGORITHM,
                    "sha256": digest.hexdigest(), "entry_count": len(entries),
                    "total_file_bytes": sum(entry.get("size", 0) for entry in entries),
                    "root_mode": format(stat.S_IMODE(root_metadata.st_mode), "04o")}
        if ledger is not None:
            ledger.remember_tree(label, observed)
        return observed
    finally:
        os.close(root_fd)


def require_list(value: Any, label: str, minimum: int = 0,
                 maximum: int = 4096) -> List[Any]:
    if not isinstance(value, list) or not minimum <= len(value) <= maximum:
        fail("{} must be an array with {}..{} entries".format(label, minimum, maximum))
    return value


def path_within(root: str, path: str) -> bool:
    return path == root or path.startswith(root + "/")


def physical_directory_contains(root: str, candidate: str) -> bool:
    """Return whether one physical directory is at or below another.

    String-prefix containment is not a security boundary on case-insensitive or
    normalization-insensitive filesystems.  Compare opened directory identities
    while walking toward the filesystem root instead.
    """
    root_fd = open_directory_chain(root, "containment root")
    candidate_fd = open_directory_chain(candidate, "containment candidate")
    try:
        root_identity = (os.fstat(root_fd).st_dev, os.fstat(root_fd).st_ino)
        current = candidate_fd
        candidate_fd = -1
        for _depth in range(4096):
            metadata = os.fstat(current)
            if (metadata.st_dev, metadata.st_ino) == root_identity:
                os.close(current)
                return True
            parent = os.open("..", directory_flags(), dir_fd=current)
            parent_metadata = os.fstat(parent)
            if ((parent_metadata.st_dev, parent_metadata.st_ino) ==
                    (metadata.st_dev, metadata.st_ino)):
                os.close(parent)
                os.close(current)
                return False
            os.close(current)
            current = parent
        os.close(current)
        fail("directory containment walk exceeded its depth ceiling")
    finally:
        if candidate_fd >= 0:
            os.close(candidate_fd)
        os.close(root_fd)


def same_physical_directory(first: str, second: str) -> bool:
    first_fd = open_directory_chain(first, "first directory identity")
    second_fd = open_directory_chain(second, "second directory identity")
    try:
        first_metadata = os.fstat(first_fd)
        second_metadata = os.fstat(second_fd)
        return ((first_metadata.st_dev, first_metadata.st_ino) ==
                (second_metadata.st_dev, second_metadata.st_ino))
    finally:
        os.close(second_fd)
        os.close(first_fd)


def require_physical_file_within(root: str, path: str, label: str) -> None:
    parent, _basename = split_file_path(path, label)
    if not physical_directory_contains(root, parent):
        fail("{} is outside its bound physical root".format(label))


def require_bound_path(observed: Dict[str, Any], expected: str, label: str) -> None:
    if observed["path"] != expected:
        fail("{} must use the canonical bound path {}".format(label, expected))


def require_canonical_json_bytes(value: Dict[str, Any], observed: Dict[str, Any],
                                 label: str) -> None:
    if observed["raw"] != canonical_json(value):
        fail("{} must use canonical JSON encoding".format(label))


def require_unique_strings(value: Any, label: str, minimum: int = 1,
                           maximum: int = 4096,
                           pattern: Optional[re.Pattern] = None) -> List[str]:
    values = require_list(value, label, minimum, maximum)
    result: List[str] = []
    for index, item in enumerate(values):
        result.append(require_string(item, "{}[{}]".format(label, index), pattern, 4096))
    if len(set(result)) != len(result):
        fail("{} must not contain duplicates".format(label))
    return result


def validate_platform(value: Any, ledger: IdentityLedger) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    platform = exact_keys(value, (
        "operating_system", "architecture", "platform_tuple", "shell"), "platform")
    operating_system, architecture, platform_tuple = current_platform()
    require_constant(platform["operating_system"], operating_system, "platform operating_system")
    require_constant(platform["architecture"], architecture, "platform architecture")
    require_constant(platform["platform_tuple"], platform_tuple, "platform tuple")
    shell = exact_keys(platform["shell"], ("name", "architecture", "executable"),
                       "platform shell")
    shell_name = require_string(shell["name"], "platform shell name", maximum=16)
    if shell_name not in ("bash", "zsh"):
        fail("platform shell name must be bash or zsh")
    require_constant(shell["architecture"], architecture, "platform shell architecture")
    executable = validate_file_binding(shell["executable"], "shell executable",
                                       maximum=MAX_BINARY_BYTES, executable=True,
                                       ledger=ledger)
    if executable["basename"] != shell_name:
        fail("platform shell executable basename does not match its declared name")
    binary = require_binary_architecture(executable, architecture, operating_system,
                                         "shell executable")
    return platform, {
        "operating_system": operating_system,
        "architecture": architecture,
        "platform_tuple": platform_tuple,
        "shell": {
            "name": shell_name,
            "architecture": architecture,
            "executable": receipt_file("shell executable", executable),
            "binary_identity": binary,
        },
    }


def validate_homebrew_runtime(value: Any, label: str, architecture: str,
                              operating_system: str,
                              ledger: IdentityLedger) -> Dict[str, Any]:
    runtime = exact_keys(value, (
        "version", "architecture", "executable", "install_receipt", "receipt_format"),
        label)
    version = require_string(runtime["version"], "{} version".format(label), VERSION_RE, 256)
    require_constant(runtime["architecture"], architecture,
                     "{} architecture".format(label))
    require_constant(runtime["receipt_format"], HOMEBREW_RECEIPT_FORMAT,
                     "{} receipt format".format(label))
    executable = validate_file_binding(runtime["executable"], "{} executable".format(label),
                                       maximum=MAX_BINARY_BYTES, executable=True,
                                       ledger=ledger)
    install_receipt, receipt_observed = load_bound_json(
        runtime["install_receipt"], "{} install receipt".format(label), ledger=ledger)
    if receipt_observed["basename"] != "INSTALL_RECEIPT.json":
        fail("{} Homebrew receipt must be named INSTALL_RECEIPT.json".format(label))
    receipt_root = os.path.dirname(receipt_observed["path"])
    require_physical_file_within(receipt_root, executable["path"],
                                 "{} executable".format(label))
    if executable["basename"] != label:
        fail("{} executable basename does not match its declared runtime".format(label))
    source = install_receipt.get("source")
    versions = source.get("versions") if isinstance(source, dict) else None
    if not isinstance(versions, dict) or versions.get("stable") != version:
        fail("{} install receipt does not bind the declared stable version".format(label))
    if install_receipt.get("arch") != architecture:
        fail("{} install receipt does not bind the declared architecture".format(label))
    binary = require_binary_architecture(executable, architecture, operating_system,
                                         "{} executable".format(label))
    return {
        "version": version,
        "architecture": architecture,
        "identity_source": "homebrew-install-receipt-source-versions-stable-and-arch",
        "receipt_format": HOMEBREW_RECEIPT_FORMAT,
        "executable": receipt_file("{} executable".format(label), executable),
        "install_receipt": receipt_file("{} install receipt".format(label), receipt_observed),
        "binary_identity": binary,
    }


def validate_tree_binding(value: Any, algorithm: str, label: str,
                          ledger: IdentityLedger) -> Dict[str, Any]:
    binding = exact_keys(value, ("root", "algorithm", "sha256"), label)
    root = canonical_absolute_path(binding["root"], "{} root".format(label))
    require_constant(binding["algorithm"], algorithm, "{} algorithm".format(label))
    expected = require_string(binding["sha256"], "{} sha256".format(label), SHA256_RE, 64)
    observed = (hash_mainframe_package_tree(root, label, ledger=ledger)
                if algorithm == MAINFRAME_TREE_ALGORITHM else
                hash_pi_runtime_tree(root, label, ledger=ledger))
    if observed["sha256"] != expected:
        fail("{} does not match its declared digest".format(label))
    result = {
        "algorithm": algorithm,
        "sha256": observed["sha256"],
        "entry_count": observed["entry_count"],
        "total_file_bytes": observed["total_file_bytes"],
        "root_path_sha256": sha256_bytes(root.encode("utf-8")),
    }
    if algorithm == PI_TREE_ALGORITHM:
        result["root_mode"] = observed["root_mode"]
    return result


def validate_mainframe(value: Any, platform_tuple: str,
                       ledger: IdentityLedger) -> Tuple[Dict[str, Any], Dict[str, Any], str]:
    mainframe = exact_keys(value, (
        "version", "version_file", "install_receipt", "install_receipt_format",
        "archive", "checksum_sidecar", "installed_tree", "pi_extension",
        "pi_compatibility_manifest", "pi_compatibility_certification_id",
        "awm_protocol"), "mainframe")
    version = require_string(mainframe["version"], "mainframe version", VERSION_RE, 256)
    require_constant(mainframe["install_receipt_format"], MAINFRAME_RECEIPT_FORMAT,
                     "mainframe install receipt format")
    version_file = validate_file_binding(mainframe["version_file"], "mainframe VERSION",
                                         maximum=1024, ledger=ledger)
    try:
        version_text = version_file["raw"].decode("utf-8").strip()
    except UnicodeDecodeError:
        fail("mainframe VERSION is not UTF-8")
    if version_text != version:
        fail("mainframe VERSION does not match the declared version")
    install_receipt, install_observed = load_bound_json(
        mainframe["install_receipt"], "mainframe install receipt", ledger=ledger)
    receipt_keys = {
        "schema_version", "install_method", "version", "archive_sha256", "manifest_sha256",
        "install_dir", "bin_dir", "cli_link", "installed_at",
    }
    if set(install_receipt) != receipt_keys:
        fail("mainframe install receipt keys differ")
    require_constant(install_receipt["schema_version"], 1,
                     "mainframe install receipt schema version")
    require_constant(install_receipt["install_method"], "release-archive",
                     "mainframe install method")
    require_constant(install_receipt["version"], version, "mainframe receipt version")
    archive = validate_file_binding(mainframe["archive"], "mainframe archive",
                                    capture=False, ledger=ledger)
    require_constant(install_receipt["archive_sha256"], archive["sha256"],
                     "mainframe receipt archive sha256")
    tree_root = canonical_absolute_path(mainframe["installed_tree"]["root"],
                                        "mainframe installed tree root")
    require_bound_path(version_file, tree_root + "/VERSION", "mainframe VERSION")
    require_bound_path(install_observed, tree_root + "/.mainframe-install-receipt.json",
                       "mainframe install receipt")
    require_constant(install_receipt["install_dir"], tree_root,
                     "mainframe receipt install_dir")
    bin_dir = canonical_absolute_path(install_receipt["bin_dir"],
                                      "mainframe receipt bin_dir")
    cli_link = canonical_absolute_path(install_receipt["cli_link"],
                                       "mainframe receipt cli_link")
    require_constant(cli_link, bin_dir + "/mainframe", "mainframe receipt cli_link")
    require_string(install_receipt["installed_at"], "mainframe receipt installed_at",
                   re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"),
                   20)
    sidecar = validate_file_binding(mainframe["checksum_sidecar"],
                                    "mainframe checksum sidecar", maximum=4096,
                                    ledger=ledger)
    require_bound_path(sidecar, archive["path"] + ".sha256",
                       "mainframe checksum sidecar")
    expected_sidecar = "{}  {}\n".format(archive["sha256"], archive["basename"]).encode("ascii")
    if sidecar["raw"] != expected_sidecar:
        fail("mainframe checksum sidecar does not exactly bind the archive")
    checksum_inventory = read_file(tree_root + "/SHA256SUMS", "mainframe SHA256SUMS",
                                   maximum=MAX_TEXT_BYTES, ledger=ledger)
    manifest_sha = require_string(install_receipt["manifest_sha256"],
                                  "mainframe receipt manifest_sha256", SHA256_RE, 64)
    require_constant(manifest_sha, checksum_inventory["sha256"],
                     "mainframe receipt manifest_sha256")
    tree = validate_tree_binding(mainframe["installed_tree"], MAINFRAME_TREE_ALGORITHM,
                                 "mainframe installed tree", ledger)

    contained: Dict[str, Dict[str, Any]] = {
        "version_file": version_file,
        "install_receipt": install_observed,
    }
    for key, label in (
            ("pi_extension", "mainframe Pi extension"),
            ("pi_compatibility_manifest", "mainframe Pi compatibility manifest")):
        contained[key] = validate_file_binding(mainframe[key], label, ledger=ledger)
    for key, observed in contained.items():
        require_physical_file_within(tree_root, observed["path"],
                                     "mainframe bound file {}".format(key))
    require_bound_path(contained["pi_compatibility_manifest"],
                       tree_root + "/config/pi-compatibility.json",
                       "mainframe Pi compatibility manifest")

    awm_value = exact_keys(mainframe["awm_protocol"], (
        "transition_driver", "raw_schema", "receipt_schema", "neutral_continuation_schema"),
        "mainframe awm protocol")
    awm_files: Dict[str, Dict[str, Any]] = {}
    for key, label in (
            ("transition_driver", "AWM transition driver"),
            ("raw_schema", "AWM raw schema"),
            ("receipt_schema", "AWM receipt schema"),
            ("neutral_continuation_schema", "AWM neutral continuation schema")):
        observed = validate_file_binding(awm_value[key], label, ledger=ledger)
        require_physical_file_within(tree_root, observed["path"], label)
        awm_files[key] = receipt_file(label, observed)

    compatibility = parse_json(contained["pi_compatibility_manifest"]["raw"],
                               "mainframe Pi compatibility manifest")
    exact_keys(compatibility, (
        "schema_version", "integration", "mainframe_version", "unknown_policy",
        "runtime_verification_command", "required_surface", "certifications"),
        "mainframe Pi compatibility manifest")
    if compatibility.get("schema_version") != 1 or \
            compatibility.get("integration") != "@gtwatts/mainframe-pi" or \
            compatibility.get("mainframe_version") != version:
        fail("mainframe Pi compatibility manifest identity is invalid")
    required_surface = exact_keys(compatibility["required_surface"], (
        "extension", "skill", "command", "hooks", "caller_shells", "tools"),
        "mainframe Pi required surface")
    required_surface_expected = {
        "extension": "./skills/pi/extensions/mainframe.ts",
        "skill": "./skills/pi",
        "command": "mainframe",
        "hooks": ["before_agent_start", "tool_call", "user_bash"],
        "caller_shells": ["bash", "zsh"],
        "tools": [
            "mainframe_awm", "mainframe_bash_safety_check", "mainframe_exec",
            "mainframe_help", "mainframe_install_commands", "mainframe_search",
            "mainframe_status",
        ],
    }
    if required_surface != required_surface_expected:
        fail("mainframe Pi required surface differs from the reviewed contract")
    require_bound_path(contained["pi_extension"],
                       tree_root + required_surface["extension"][1:],
                       "mainframe Pi extension")
    certification_id = require_string(
        mainframe["pi_compatibility_certification_id"],
        "Pi compatibility certification id", CERTIFICATION_ID_RE, 256)
    certifications = compatibility.get("certifications")
    if not isinstance(certifications, list):
        fail("mainframe Pi compatibility certifications must be an array")
    matches = [item for item in certifications
               if isinstance(item, dict) and item.get("id") == certification_id]
    if len(matches) != 1:
        fail("Pi compatibility certification id must select exactly one record")
    certification = exact_keys(matches[0], (
        "id", "mainframe_version", "package", "version", "npm_integrity",
        "platforms", "support", "profile", "evidence_date", "evidence",
        "capabilities", "limitations"), "Pi compatibility certification")
    platforms = require_unique_strings(certification["platforms"],
                                       "Pi compatibility platforms", 1, 64,
                                       re.compile(r"^(?:Darwin|Linux)-(?:arm64|x86_64)-(?:none|glibc|musl)$"))
    if certification.get("mainframe_version") != version or \
            certification.get("support") != "certified" or \
            certification.get("profile") != "full" or \
            platform_tuple not in platforms:
        fail("Pi compatibility certification is not exact full support for this platform")
    capabilities = certification.get("capabilities")
    capability_keys = (
        "local_package_discovery", "prompt_hook", "seven_tool_surface", "agent_bash_gate",
        "tui_user_bash_gate", "rpc_user_bash_gate", "bash_and_zsh_callers",
    )
    if not isinstance(capabilities, dict) or set(capabilities) != set(capability_keys) or \
            any(capabilities[key] != "verified" for key in capability_keys):
        fail("Pi compatibility certification lacks the exact verified capability surface")
    if certification.get("limitations") != []:
        fail("full Pi compatibility certification must have no limitations")

    return ({
        "version": version,
        "identity_source": "bound-version-file-and-release-install-receipt",
        "version_file": receipt_file("mainframe VERSION", version_file),
        "install_receipt": receipt_file("mainframe install receipt", install_observed),
        "install_receipt_format": MAINFRAME_RECEIPT_FORMAT,
        "archive": receipt_file("mainframe archive", archive),
        "checksum_sidecar": receipt_file("mainframe checksum sidecar", sidecar),
        "archive_checksum_matches": True,
        "installed_tree": tree,
        "pi_extension": receipt_file("mainframe Pi extension", contained["pi_extension"]),
        "pi_compatibility_manifest": receipt_file(
            "mainframe Pi compatibility manifest", contained["pi_compatibility_manifest"]),
        "pi_compatibility_certification_id": certification_id,
        "awm_protocol": awm_files,
    }, certification, tree_root)


def validate_pi(value: Any, architecture: str, platform_tuple: str,
                certification: Dict[str, Any], ledger: IdentityLedger) -> Tuple[Dict[str, Any], str]:
    pi = exact_keys(value, (
        "package_name", "package_version", "architecture", "executable",
        "package_manifest", "package_tree", "extension_loader"), "pi")
    package_name = require_string(pi["package_name"], "Pi package name", PACKAGE_RE, 256)
    package_version = require_string(pi["package_version"], "Pi package version", VERSION_RE, 256)
    require_constant(pi["architecture"], architecture, "Pi architecture")
    tree_root = canonical_absolute_path(pi["package_tree"]["root"], "Pi package tree root")
    tree = validate_tree_binding(pi["package_tree"], PI_TREE_ALGORITHM,
                                 "Pi package runtime tree", ledger)
    package_manifest, manifest_observed = load_bound_json(
        pi["package_manifest"], "Pi package manifest", ledger=ledger)
    require_bound_path(manifest_observed, tree_root + "/package.json",
                       "Pi package manifest")
    if package_manifest.get("name") != package_name or \
            package_manifest.get("version") != package_version:
        fail("Pi package manifest does not bind the declared name/version")
    bin_value = package_manifest.get("bin")
    if not isinstance(bin_value, dict) or set(bin_value) != {"pi"}:
        fail("Pi package manifest must have one exact pi bin entry")
    bin_relative = require_string(bin_value["pi"], "Pi package bin.pi", maximum=512)
    if bin_relative.startswith("/") or os.path.normpath(bin_relative) != bin_relative or \
            bin_relative in (".", "..") or bin_relative.startswith("../"):
        fail("Pi package bin.pi must be a canonical relative path")
    executable = validate_file_binding(pi["executable"], "Pi executable",
                                       maximum=MAX_TEXT_BYTES, executable=True,
                                       ledger=ledger)
    extension_loader = validate_file_binding(pi["extension_loader"],
                                             "Pi extension loader", ledger=ledger)
    for observed, label in ((manifest_observed, "Pi package manifest"),
                            (executable, "Pi executable"),
                            (extension_loader, "Pi extension loader")):
        require_physical_file_within(tree_root, observed["path"], label)
    expected_executable = tree_root + "/" + bin_relative
    require_bound_path(executable, expected_executable, "Pi executable")
    if not executable["raw"].startswith(b"#!/usr/bin/env node\n"):
        fail("Pi executable is not the reviewed Node entrypoint form")
    require_bound_path(extension_loader, tree_root + "/dist/core/extensions/loader.js",
                       "Pi extension loader")
    if certification.get("package") != package_name or \
            certification.get("version") != package_version or \
            platform_tuple not in certification.get("platforms", []):
        fail("Pi package identity does not match the selected certification")
    npm_integrity = require_string(certification.get("npm_integrity"),
                                   "Pi certification npm_integrity", maximum=256)
    if re.fullmatch(r"sha512-[A-Za-z0-9+/]+={0,2}", npm_integrity) is None:
        fail("Pi certification npm_integrity is invalid")
    capabilities = certification["capabilities"]
    compatibility = {
        "integration": "@gtwatts/mainframe-pi",
        "certification_id": certification["id"],
        "mainframe_version": certification["mainframe_version"],
        "package_name": package_name,
        "package_version": package_version,
        "certification_record_npm_integrity": npm_integrity,
        "npm_integrity_observation":
            "certification-record-only-local-package-tree-bound-separately",
        "platform_tuple": platform_tuple,
        "support": "certified",
        "profile": "full",
        "capabilities": {key: capabilities[key] for key in (
            "local_package_discovery", "prompt_hook", "seven_tool_surface",
            "agent_bash_gate", "tui_user_bash_gate", "rpc_user_bash_gate",
            "bash_and_zsh_callers")},
    }
    return ({
        "package_name": package_name,
        "package_version": package_version,
        "architecture": architecture,
        "identity_source": (
            "bound-package-json-and-certified-platform-tuple-node-runtime-bound-separately"),
        "executable": receipt_file("Pi executable", executable),
        "package_manifest": receipt_file("Pi package manifest", manifest_observed),
        "package_tree": tree,
        "extension_loader": receipt_file("Pi extension loader", extension_loader),
        "compatibility": compatibility,
    }, tree_root)


def descriptor_from_json(value: Any, label: str,
                         config: bool = False) -> Dict[str, Any]:
    descriptor = exact_keys(value, ("digest", "media_type", "size_bytes"), label)
    digest = require_string(descriptor["digest"], "{} digest".format(label),
                            QUALIFIED_SHA256_RE, 71)
    media_type = require_string(descriptor["media_type"], "{} media type".format(label),
                                maximum=256)
    if config:
        if media_type != CONFIG_MEDIA_TYPE:
            fail("{} media type must be the Docker config type".format(label))
    elif re.fullmatch(r"application/vnd\.ollama\.image\.[A-Za-z0-9.+_-]+",
                      media_type) is None:
        fail("{} must use an Ollama layer media type".format(label))
    size = require_integer(descriptor["size_bytes"], "{} size".format(label), 1,
                           MAX_FILE_BYTES)
    return {"digest": digest, "media_type": media_type, "size_bytes": size}


def docker_descriptor(value: Any, label: str,
                      config: bool = False) -> Dict[str, Any]:
    descriptor = exact_keys(value, ("mediaType", "digest", "size"), label)
    return descriptor_from_json({
        "digest": descriptor["digest"],
        "media_type": descriptor["mediaType"],
        "size_bytes": descriptor["size"],
    }, label, config=config)


def validate_model(value: Any, ledger: IdentityLedger) -> Tuple[Dict[str, Any], List[str]]:
    model = exact_keys(value, (
        "name", "closure", "manifest", "manifest_media_type", "config_descriptor",
        "ordered_layer_descriptors", "ordered_rootfs_diff_ids", "ordered_blobs",
        "template_contract", "tool_contract", "dependency_closure_algorithm",
        "dependency_closure_domain_separator_hex", "dependency_closure_canonicalization",
        "dependency_closure_sha256"), "Ollama model")
    name = require_string(model["name"], "Ollama model name", MODEL_RE, 256)
    if name.count(":") != 1:
        fail("Ollama model name must include one explicit tag")
    repository, tag = name.rsplit(":", 1)
    repository_parts = repository.split("/")
    if (not tag or any(not component or component in (".", "..")
                       for component in repository_parts)):
        fail("Ollama model name has an invalid repository or tag")
    require_constant(model["closure"], "manifest-referenced-blobs-only-not-entire-store",
                     "Ollama model closure")
    require_constant(model["manifest_media_type"], MANIFEST_MEDIA_TYPE,
                     "Ollama model manifest media type")
    require_constant(model["dependency_closure_algorithm"], MODEL_CLOSURE_ALGORITHM,
                     "Ollama model closure algorithm")
    require_constant(model["dependency_closure_domain_separator_hex"],
                     MODEL_CLOSURE_DOMAIN.hex(), "Ollama model closure domain")
    require_constant(model["dependency_closure_canonicalization"],
                     "utf8-json-sorted-keys-compact-ensure-ascii-lf-v1",
                     "Ollama model closure canonicalization")
    manifest, manifest_observed = load_bound_json(
        model["manifest"], "Ollama model manifest", ledger=ledger)
    manifest_parts = manifest_observed["path"].split("/")
    expected_tail = (["manifests", "registry.ollama.ai"] +
                     (["library"] if len(repository_parts) == 1 else []) +
                     repository_parts + [tag])
    if manifest_parts[-len(expected_tail):] != expected_tail:
        fail("Ollama model name does not match its exact manifest path")
    model_root_parts = manifest_parts[:-len(expected_tail)]
    if not model_root_parts:
        fail("Ollama manifest lacks a canonical model-store root")
    model_root = "/".join(model_root_parts) or "/"
    model_root = canonical_absolute_path(model_root, "Ollama model store root")
    canonical_blob_root = model_root + "/blobs"
    blob_root_fd = open_directory_chain(canonical_blob_root, "Ollama blob root")
    os.close(blob_root_fd)
    manifest_exact = exact_keys(manifest, ("schemaVersion", "mediaType", "config", "layers"),
                                "Ollama model manifest")
    require_constant(manifest_exact["schemaVersion"], 2, "Ollama manifest schemaVersion")
    require_constant(manifest_exact["mediaType"], MANIFEST_MEDIA_TYPE,
                     "Ollama manifest mediaType")
    manifest_config = docker_descriptor(manifest_exact["config"],
                                        "Ollama manifest config", config=True)
    declared_config = descriptor_from_json(model["config_descriptor"],
                                           "declared Ollama config", config=True)
    if manifest_config != declared_config:
        fail("Ollama config descriptor differs from the manifest")
    manifest_layers = require_list(manifest_exact["layers"], "Ollama manifest layers", 2, 4095)
    observed_layers = [docker_descriptor(item, "Ollama manifest layer {}".format(index))
                       for index, item in enumerate(manifest_layers)]
    declared_layers = [descriptor_from_json(item, "declared Ollama layer {}".format(index))
                       for index, item in enumerate(require_list(
                           model["ordered_layer_descriptors"],
                           "declared Ollama ordered layers", 2, 4095))]
    if observed_layers != declared_layers:
        fail("Ollama ordered layer descriptors differ from the manifest")
    digests = [manifest_config["digest"]] + [item["digest"] for item in observed_layers]
    if len(set(digests)) != len(digests):
        fail("Ollama config/layer digests must not be duplicated")

    blob_values = require_list(model["ordered_blobs"], "Ollama ordered blobs", 3, 4096)
    if len(blob_values) != len(digests):
        fail("Ollama ordered blob list must contain config followed by every layer")
    blob_receipts: List[Dict[str, Any]] = []
    model_paths: List[str] = [manifest_observed["path"]]
    config_json: Optional[Dict[str, Any]] = None
    template_index = -1
    model_layers = 0
    template_layers = 0
    for index, (blob_value, descriptor) in enumerate(zip(
            blob_values, [manifest_config] + observed_layers)):
        blob = exact_keys(blob_value, ("role", "digest", "media_type", "path", "size_bytes"),
                          "Ollama blob {}".format(index))
        role = "config" if index == 0 else "layer"
        require_constant(blob["role"], role, "Ollama blob role")
        for key in ("digest", "media_type", "size_bytes"):
            require_constant(blob[key], descriptor[key], "Ollama blob {} {}".format(index, key))
        expected_basename = descriptor["digest"].replace(":", "-")
        path = canonical_absolute_path(blob["path"], "Ollama blob path")
        if os.path.basename(path) != expected_basename:
            fail("Ollama blob filename does not match its digest")
        if not same_physical_directory(os.path.dirname(path), canonical_blob_root):
            fail("Ollama blob is outside the exact canonical model-store blob directory")
        capture_blob = index == 0 or descriptor["media_type"] == TEMPLATE_MEDIA_TYPE
        blob_maximum = (MAX_JSON_BYTES if index == 0 else
                        MAX_TEXT_BYTES if descriptor["media_type"] == TEMPLATE_MEDIA_TYPE else
                        MAX_FILE_BYTES)
        observed = read_file(path, "Ollama blob {}".format(index),
                             maximum=blob_maximum, capture=capture_blob, ledger=ledger)
        if observed["sha256"] != descriptor["digest"].split(":", 1)[1] or \
                observed["size_bytes"] != descriptor["size_bytes"]:
            fail("Ollama blob bytes do not match their descriptor")
        model_paths.append(path)
        if index == 0:
            config_json = parse_json(observed["raw"], "Ollama config blob")
        if descriptor["media_type"] == MODEL_MEDIA_TYPE:
            model_layers += 1
        if descriptor["media_type"] == TEMPLATE_MEDIA_TYPE:
            template_layers += 1
            template_index = index - 1
            try:
                template_text = observed["raw"].decode("utf-8")
            except UnicodeDecodeError:
                fail("Ollama template layer is not UTF-8")
            for marker in (".Tools", ".ToolCalls"):
                if marker not in template_text:
                    fail("Ollama template lacks required marker {}".format(marker))
        blob_receipts.append({
            "ordinal": index,
            "role": role,
            "digest": descriptor["digest"],
            "media_type": descriptor["media_type"],
            "size_bytes": descriptor["size_bytes"],
            "file": receipt_file("Ollama blob {}".format(index), observed),
        })
    if model_layers != 1 or template_layers != 1:
        fail("Ollama model must have exactly one model layer and one template layer")
    assert config_json is not None
    rootfs = config_json.get("rootfs")
    if not isinstance(rootfs, dict) or set(rootfs) != {"type", "diff_ids"} or \
            rootfs.get("type") != "layers":
        fail("Ollama config rootfs is invalid")
    diff_ids = require_unique_strings(rootfs["diff_ids"], "Ollama config rootfs diff_ids",
                                      2, 4095, QUALIFIED_SHA256_RE)
    declared_diff_ids = require_unique_strings(model["ordered_rootfs_diff_ids"],
                                               "declared Ollama rootfs diff_ids",
                                               2, 4095, QUALIFIED_SHA256_RE)
    layer_digests = [item["digest"] for item in observed_layers]
    if diff_ids != layer_digests or declared_diff_ids != layer_digests:
        fail("Ollama rootfs diff_ids do not exactly match ordered layers")
    closure_projection = {
        "config_descriptor": manifest_config,
        "ordered_layer_descriptors": observed_layers,
        "ordered_rootfs_diff_ids": diff_ids,
    }
    closure_sha = sha256_bytes(MODEL_CLOSURE_DOMAIN + canonical_json(closure_projection))
    require_constant(model["dependency_closure_sha256"], closure_sha,
                     "Ollama dependency closure digest")
    template_contract = exact_keys(model["template_contract"],
                                   ("digest", "media_type", "required_markers"),
                                   "Ollama template contract")
    require_constant(template_contract["digest"], observed_layers[template_index]["digest"],
                     "Ollama template digest")
    require_constant(template_contract["media_type"], TEMPLATE_MEDIA_TYPE,
                     "Ollama template media type")
    require_constant(template_contract["required_markers"], [".Tools", ".ToolCalls"],
                     "Ollama template markers")
    tool_contract = exact_keys(model["tool_contract"], ("mode", "native_tool_channel"),
                               "Ollama tool contract")
    require_constant(tool_contract["mode"], "native-tools-required", "Ollama tool mode")
    require_constant(tool_contract["native_tool_channel"],
                     "ollama-template-tools-and-toolcalls-markers",
                     "Ollama native tool channel")
    return ({
        "name": name,
        "closure": "manifest-referenced-blobs-only-not-entire-store",
        "manifest": receipt_file("Ollama model manifest", manifest_observed),
        "manifest_schema_version": 2,
        "manifest_media_type": MANIFEST_MEDIA_TYPE,
        "config_descriptor": manifest_config,
        "ordered_layer_descriptors": observed_layers,
        "ordered_rootfs_diff_ids": diff_ids,
        "ordered_blob_files": blob_receipts,
        "template_contract": {
            "layer_ordinal": template_index,
            "digest": observed_layers[template_index]["digest"],
            "media_type": TEMPLATE_MEDIA_TYPE,
            "required_markers": [".Tools", ".ToolCalls"],
            "observed_markers": [".Tools", ".ToolCalls"],
        },
        "tool_contract": {
            "mode": "native-tools-required",
            "native_tool_channel": "ollama-template-tools-and-toolcalls-markers",
            "exactly_one_model_layer": True,
            "exactly_one_template_layer": True,
        },
        "dependency_closure_algorithm": MODEL_CLOSURE_ALGORITHM,
        "dependency_closure_domain_separator_hex": MODEL_CLOSURE_DOMAIN.hex(),
        "dependency_closure_canonicalization":
            "utf8-json-sorted-keys-compact-ensure-ascii-lf-v1",
        "dependency_closure_sha256": closure_sha,
    }, model_paths)


def reject_neutrality_leaks(value: Any, label: str) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key in FORBIDDEN_KEYS:
                fail("{} contains forbidden assignment/mechanism key {!r}".format(label, key))
            reject_neutrality_leaks(child, label)
    elif isinstance(value, list):
        for child in value:
            reject_neutrality_leaks(child, label)
    elif isinstance(value, str) and value in FORBIDDEN_VALUES:
        fail("{} contains forbidden assignment/mechanism value {!r}".format(label, value))


def runtime_binding(spec: Dict[str, Any]) -> Dict[str, Any]:
    projection = {key: spec[key] for key in RUNTIME_PROJECTION_KEYS}
    digest = sha256_bytes(RUNTIME_BINDING_DOMAIN + canonical_json(projection))
    return {
        "algorithm": RUNTIME_BINDING_ALGORITHM,
        "domain_separator_hex": RUNTIME_BINDING_DOMAIN.hex(),
        "canonicalization": "utf8-json-sorted-keys-compact-ensure-ascii-lf-v1",
        "sha256": digest,
        "projection_keys": list(RUNTIME_PROJECTION_KEYS),
        "arm_contract_excluded": True,
    }


def validate_runtime_binding(value: Any, expected: Dict[str, Any], label: str) -> None:
    binding = exact_keys(value, (
        "algorithm", "domain_separator_hex", "canonicalization", "projection_keys",
        "arm_contract_excluded", "sha256"), label)
    if binding != expected:
        fail("{} does not equal the bound spec runtime projection".format(label))


def validate_arm(value: Any, expected_binding: Dict[str, Any],
                 expected_model: str) -> Dict[str, Any]:
    arm = exact_keys(value, (
        "schema_version", "kind", "runtime_binding", "study_id", "pair_id",
        "opaque_arm_ids", "task_id", "phases", "provider", "budgets",
        "environment_contract", "adapter_boundary"), "neutral arm contract")
    reject_neutrality_leaks({
        key: arm[key] for key in (
            "study_id", "pair_id", "opaque_arm_ids", "task_id", "phases",
            "provider", "budgets", "environment_contract")
    }, "neutral arm request-facing contract")
    require_constant(arm["schema_version"], 1, "arm schema version")
    require_constant(arm["kind"], ARM_KIND, "arm kind")
    validate_runtime_binding(arm["runtime_binding"], expected_binding, "arm runtime binding")
    study_id = require_string(arm["study_id"], "arm study_id", ID_RE, 128)
    pair_id = require_string(arm["pair_id"], "arm pair_id", PAIR_RE, 21)
    opaque_ids = require_unique_strings(arm["opaque_arm_ids"], "opaque arm ids", 2, 2,
                                        ARM_RE)
    if opaque_ids != sorted(opaque_ids):
        fail("opaque arm ids must use canonical sorted order")
    task_id = require_string(arm["task_id"], "arm task_id", ID_RE, 128)
    require_constant(arm["phases"], ["investigate", "implement"], "arm phases")
    provider = exact_keys(arm["provider"], ("name", "model"), "arm provider")
    require_constant(provider["name"], "ollama", "arm provider name")
    require_constant(provider["model"], expected_model, "arm provider model")
    budgets = exact_keys(arm["budgets"], (
        "wall_seconds_per_phase", "maximum_tool_calls_per_phase", "maximum_context_bytes"),
        "arm budgets")
    require_integer(budgets["wall_seconds_per_phase"], "wall seconds per phase", 1, 3600)
    require_integer(budgets["maximum_tool_calls_per_phase"], "maximum tool calls per phase",
                    1, 1000)
    require_integer(budgets["maximum_context_bytes"], "maximum context bytes", 1, 1048576)
    environment = exact_keys(arm["environment_contract"],
                             ("fresh_per_phase", "allowed_environment_names"),
                             "arm environment contract")
    require_constant(environment["fresh_per_phase"], True, "fresh per phase")
    environment_names = require_unique_strings(environment["allowed_environment_names"],
                                               "allowed environment names", 1, 64,
                                               re.compile(r"^[A-Z][A-Z0-9_]{0,63}$"))
    if environment_names != sorted(environment_names):
        fail("allowed environment names must use canonical sorted order")
    allowed_environment = {
        "HOME", "LANG", "LC_ALL", "PATH", "TMPDIR", "XDG_CACHE_HOME",
        "XDG_CONFIG_HOME", "XDG_STATE_HOME",
    }
    if not set(environment_names).issubset(allowed_environment):
        fail("arm environment contains an unreviewed or credential-shaped name")
    boundary = exact_keys(arm["adapter_boundary"], (
        "assignment_visibility", "mechanism_transition_owner", "scoring_owner",
        "same_adapter_executable_both_arms", "same_provider_model_both_arms",
        "same_phase_budgets_both_arms", "request_parity_fields",
        "forbidden_request_fields", "forbidden_request_string_values",
        "neutrality_validation"), "arm adapter boundary")
    boundary_expected = {
        "assignment_visibility": "opaque-arm-identities-only",
        "mechanism_transition_owner": "harness",
        "scoring_owner": "harness",
        "same_adapter_executable_both_arms": True,
        "same_provider_model_both_arms": True,
        "same_phase_budgets_both_arms": True,
        "request_parity_fields": ["budgets", "environment_contract", "phase", "provider", "task_id"],
        "forbidden_request_fields": sorted(FORBIDDEN_KEYS),
        "forbidden_request_string_values": sorted(FORBIDDEN_VALUES),
        "neutrality_validation": "recursive-exact-key-and-exact-string-value-rejection",
    }
    if boundary != boundary_expected:
        fail("arm adapter boundary differs from the reviewed neutral contract")
    parity_rows = [{
        "opaque_arm_id": opaque_id,
        "runtime_binding_sha256": expected_binding["sha256"],
        "provider": provider,
        "budgets": budgets,
        "environment_contract": environment,
        "request_parity_fields": boundary["request_parity_fields"],
    } for opaque_id in sorted(opaque_ids)]
    return {
        "study_id": study_id,
        "pair_id": pair_id,
        "opaque_arm_ids": opaque_ids,
        "task_id": task_id,
        "phases": ["investigate", "implement"],
        "runtime_binding": expected_binding,
        "provider": provider,
        "budgets": budgets,
        "environment_contract": environment,
        "adapter_boundary": boundary,
        "contract_sha256": sha256_bytes(canonical_json(arm)),
        "two_arm_parity": {
            "arm_count": 2,
            "one_neutral_contract_applied_to_both_arms": True,
            "assignment_values_absent": True,
            "mechanism_values_absent": True,
            "rows": parity_rows,
        },
    }


def require_closed_schema(schema: Dict[str, Any], label: str,
                          expected_id: str) -> None:
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        fail("{} must use JSON Schema draft 2020-12".format(label))
    if schema.get("$id") != expected_id:
        fail("{} has the wrong schema identifier".format(label))

    def visit(value: Any, location: str) -> None:
        if isinstance(value, dict):
            reference = value.get("$ref")
            if reference is not None and (not isinstance(reference, str) or
                                          not reference.startswith("#/$defs/")):
                fail("{} contains a non-local schema reference at {}".format(label, location))
            if value.get("type") == "object":
                if value.get("additionalProperties") is not False:
                    fail("{} contains an open object at {}".format(label, location))
                properties = value.get("properties")
                required = value.get("required")
                if not isinstance(properties, dict) or not isinstance(required, list):
                    fail("{} object lacks properties/required at {}".format(label, location))
                if set(required) != set(properties):
                    fail("{} object has optional or unknown properties at {}".format(
                        label, location))
            for key, child in value.items():
                visit(child, location + "/" + str(key))
        elif isinstance(value, list):
            for index, child in enumerate(value):
                visit(child, location + "/" + str(index))

    visit(schema, "#")


def running_project_root() -> str:
    running = canonical_absolute_path(os.path.abspath(__file__),
                                      "running preflight executable")
    suffix = "/scripts/dev/agent-impact-runtime-preflight.py"
    if not running.endswith(suffix):
        fail("running preflight executable is outside the reviewed package layout")
    return running[:-len(suffix)]


def require_distribution_bytes(observed: Dict[str, Any], relative: str,
                               label: str, ledger: IdentityLedger,
                               executable: bool = False) -> None:
    expected_path = running_project_root() + "/" + relative
    expected = read_file(expected_path, "running distribution {}".format(label),
                         maximum=MAX_BINARY_BYTES if executable else MAX_JSON_BYTES,
                         executable=executable, ledger=ledger)
    if (observed["sha256"] != expected["sha256"] or
            observed["size_bytes"] != expected["size_bytes"]):
        fail("{} differs from the executing reviewed distribution".format(label))


def validate_adapter(value: Any, mainframe_root: str,
                     ledger: IdentityLedger) -> Dict[str, Any]:
    adapter = exact_keys(value, (
        "executable", "manifest", "request_schema", "result_schema",
        "arm_contract_schema", "expected_adapter_id", "expected_adapter_version"),
        "adapter")
    require_constant(adapter["expected_adapter_id"], ADAPTER_ID,
                     "expected adapter id")
    require_constant(adapter["expected_adapter_version"], ADAPTER_VERSION,
                     "expected adapter version")
    observations: Dict[str, Dict[str, Any]] = {}
    for key, label, maximum, executable in (
            ("executable", "Pi/Ollama adapter executable", MAX_TEXT_BYTES, True),
            ("manifest", "Pi/Ollama adapter manifest", MAX_JSON_BYTES, False),
            ("request_schema", "Pi/Ollama request schema", MAX_JSON_BYTES, False),
            ("result_schema", "Pi/Ollama result schema", MAX_JSON_BYTES, False),
            ("arm_contract_schema", "Pi/Ollama arm schema", MAX_JSON_BYTES, False)):
        observed = validate_file_binding(adapter[key], label, maximum=maximum,
                                         executable=executable, ledger=ledger)
        require_physical_file_within(mainframe_root, observed["path"], label)
        observations[key] = observed

    relative_files = {
        "executable": "evals/agent-impact/runners/pi-ollama-adapter.py",
        "manifest": "evals/agent-impact/runners/pi-ollama-adapter.manifest.json",
        "request_schema": "evals/agent-impact/pi-ollama-adapter-request.schema.json",
        "result_schema": "evals/agent-impact/pi-ollama-adapter-result.schema.json",
        "arm_contract_schema": "evals/agent-impact/pi-ollama-arm-contract.schema.json",
    }
    for key, relative in relative_files.items():
        require_distribution_bytes(observations[key], relative,
                                   "adapter {}".format(key), ledger,
                                   executable=(key == "executable"))

    manifest = parse_json(observations["manifest"]["raw"], "Pi/Ollama adapter manifest")
    exact_keys(manifest, (
        "schema_version", "kind", "adapter_id", "adapter_version", "provider",
        "execution_status", "invocation_supported", "run_action_available",
        "executable", "request_schema", "result_schema", "arm_contract_schema",
        "assignment_input", "mechanism_transition_owner", "scoring_owner",
        "permitted_environment_names"), "Pi/Ollama adapter manifest")
    manifest_expected = {
        "schema_version": 1,
        "kind": "mainframe-agent-impact-pi-ollama-adapter-manifest",
        "adapter_id": ADAPTER_ID,
        "adapter_version": ADAPTER_VERSION,
        "provider": "ollama",
        "execution_status": "not-implemented",
        "invocation_supported": False,
        "run_action_available": False,
        "executable": "runners/pi-ollama-adapter.py",
        "request_schema": "pi-ollama-adapter-request.schema.json",
        "result_schema": "pi-ollama-adapter-result.schema.json",
        "arm_contract_schema": "pi-ollama-arm-contract.schema.json",
        "assignment_input": "forbidden",
        "mechanism_transition_owner": "harness",
        "scoring_owner": "harness",
        "permitted_environment_names": [
            "HOME", "LANG", "LC_ALL", "PATH", "TMPDIR", "XDG_CACHE_HOME",
            "XDG_CONFIG_HOME", "XDG_STATE_HOME",
        ],
    }
    if manifest != manifest_expected:
        fail("Pi/Ollama adapter manifest differs from the dormant reviewed contract")
    protocol_root = os.path.dirname(os.path.dirname(observations["manifest"]["path"]))
    for key in ("executable", "request_schema", "result_schema", "arm_contract_schema"):
        require_bound_path(observations[key], protocol_root + "/" + manifest[key],
                           "adapter {}".format(key))

    schema_contracts = (
        ("request_schema", "Pi/Ollama request schema", REQUEST_SCHEMA_ID),
        ("result_schema", "Pi/Ollama result schema", RESULT_SCHEMA_ID),
        ("arm_contract_schema", "Pi/Ollama arm schema", ARM_SCHEMA_ID),
    )
    for key, label, schema_id in schema_contracts:
        schema = parse_json(observations[key]["raw"], label)
        require_closed_schema(schema, label, schema_id)

    return {
        "adapter_id": ADAPTER_ID,
        "adapter_version": ADAPTER_VERSION,
        "provider": "ollama",
        "execution_status": "not-implemented",
        "invocation_supported": False,
        "run_action_available": False,
        "executable": receipt_file("Pi/Ollama adapter executable", observations["executable"]),
        "manifest": receipt_file("Pi/Ollama adapter manifest", observations["manifest"]),
        "request_schema": receipt_file("Pi/Ollama request schema",
                                       observations["request_schema"]),
        "result_schema": receipt_file("Pi/Ollama result schema",
                                      observations["result_schema"]),
        "arm_contract_schema": receipt_file("Pi/Ollama arm schema",
                                            observations["arm_contract_schema"]),
    }


def validate_protocol(value: Any, mainframe_root: str,
                      ledger: IdentityLedger) -> Dict[str, Any]:
    protocol = exact_keys(value, (
        "preflight_executable", "spec_schema", "receipt_schema"), "protocol")
    observations: Dict[str, Dict[str, Any]] = {}
    for key, label, maximum, executable in (
            ("preflight_executable", "offline preflight executable", MAX_TEXT_BYTES, True),
            ("spec_schema", "offline preflight spec schema", MAX_JSON_BYTES, False),
            ("receipt_schema", "offline preflight receipt schema", MAX_JSON_BYTES, False)):
        observed = validate_file_binding(protocol[key], label, maximum=maximum,
                                         executable=executable, ledger=ledger)
        require_physical_file_within(mainframe_root, observed["path"], label)
        observations[key] = observed
    relative_files = {
        "preflight_executable": "scripts/dev/agent-impact-runtime-preflight.py",
        "spec_schema": "evals/agent-impact/pi-ollama-preflight-spec.schema.json",
        "receipt_schema": "evals/agent-impact/pi-ollama-preflight-receipt.schema.json",
    }
    for key, relative in relative_files.items():
        require_distribution_bytes(observations[key], relative,
                                   "protocol {}".format(key), ledger,
                                   executable=(key == "preflight_executable"))
    for key, label, schema_id in (
            ("spec_schema", "offline preflight spec schema", SPEC_SCHEMA_ID),
            ("receipt_schema", "offline preflight receipt schema", RECEIPT_SCHEMA_ID)):
        schema = parse_json(observations[key]["raw"], label)
        require_closed_schema(schema, label, schema_id)
    return {
        "preflight_executable": receipt_file(
            "offline preflight executable", observations["preflight_executable"]),
        "spec_schema": receipt_file("offline preflight spec schema",
                                    observations["spec_schema"]),
        "receipt_schema": receipt_file("offline preflight receipt schema",
                                       observations["receipt_schema"]),
    }


def _cpu_architecture(cpu_type: int) -> Optional[str]:
    if cpu_type == 0x0100000C:
        return "arm64"
    if cpu_type == 0x01000007:
        return "x86_64"
    return None


def _validate_macho_header(raw: bytes, offset: int, endian: str,
                           expected_cpu: Optional[int], label: str) -> int:
    if len(raw) < offset + 32:
        fail("{} has a truncated 64-bit Mach-O header".format(label))
    values = struct.unpack(endian + "IIIIIIII", raw[offset:offset + 32])
    _magic, cpu_type, _subtype, file_type, command_count, command_bytes, _flags, _reserved = values
    if expected_cpu is not None and cpu_type != expected_cpu:
        fail("{} Mach-O CPU type disagrees with its container".format(label))
    if file_type != 2:
        fail("{} must be a Mach-O executable".format(label))
    if command_count > 100_000 or command_bytes > len(raw) - offset - 32:
        fail("{} has invalid Mach-O load-command bounds".format(label))
    return cpu_type


def binary_identity(raw: bytes, label: str) -> Tuple[str, Set[str]]:
    """Return 64-bit ELF/Mach-O architectures without executing the file."""
    if len(raw) < 20:
        fail("{} is too small to be a supported executable".format(label))
    if raw.startswith(b"\x7fELF"):
        if len(raw) < 64 or raw[4] != 2 or raw[5] not in (1, 2):
            fail("{} must be a 64-bit ELF executable".format(label))
        endian = "<" if raw[5] == 1 else ">"
        elf_type = struct.unpack(endian + "H", raw[16:18])[0]
        if elf_type not in (2, 3):
            fail("{} must be an ELF executable or shared object".format(label))
        machine = struct.unpack(endian + "H", raw[18:20])[0]
        mapping = {62: "x86_64", 183: "arm64"}
        architecture = mapping.get(machine)
        if architecture is None:
            fail("{} has an unsupported ELF architecture".format(label))
        return "elf", {architecture}

    thin_magics = {
        b"\xcf\xfa\xed\xfe": "<",
        b"\xfe\xed\xfa\xcf": ">",
    }
    if raw[:4] in thin_magics:
        cpu_type = _validate_macho_header(raw, 0, thin_magics[raw[:4]], None, label)
        architecture = _cpu_architecture(cpu_type)
        if architecture is None:
            fail("{} has an unsupported Mach-O architecture".format(label))
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
        count = struct.unpack(endian + "I", raw[4:8])[0]
        if count < 1 or count > 32 or len(raw) < 8 + count * width:
            fail("{} has an invalid universal Mach-O header".format(label))
        architectures: Set[str] = set()
        for index in range(count):
            offset = 8 + index * width
            cpu_type = struct.unpack(endian + "I", raw[offset:offset + 4])[0]
            architecture = _cpu_architecture(cpu_type)
            if width == 20:
                slice_offset, slice_size = struct.unpack(
                    endian + "II", raw[offset + 8:offset + 16])
            else:
                slice_offset, slice_size = struct.unpack(
                    endian + "QQ", raw[offset + 8:offset + 24])
            if (slice_size < 32 or slice_offset < 8 + count * width or
                    slice_offset + slice_size > len(raw)):
                fail("{} has an invalid universal Mach-O slice".format(label))
            slice_magic = raw[slice_offset:slice_offset + 4]
            slice_endian = thin_magics.get(slice_magic)
            if slice_endian is None or len(raw) < slice_offset + 8:
                fail("{} universal slice is not 64-bit Mach-O".format(label))
            _validate_macho_header(raw, slice_offset, slice_endian, cpu_type, label)
            if architecture is not None:
                architectures.add(architecture)
        if not architectures:
            fail("{} has no supported universal Mach-O slice".format(label))
        return "mach-o-universal", architectures
    fail("{} is not a supported ELF or Mach-O executable".format(label))


def require_binary_architecture(observed: Dict[str, Any], expected: str,
                                operating_system: str, label: str) -> Dict[str, Any]:
    format_name, architectures = binary_identity(observed["raw"], label)
    if operating_system == "Darwin" and not format_name.startswith("mach-o"):
        fail("{} is not a Mach-O executable for Darwin".format(label))
    if operating_system == "Linux" and format_name != "elf":
        fail("{} is not an ELF executable for Linux".format(label))
    if expected not in architectures:
        fail("{} does not contain the expected {} architecture".format(label, expected))
    return {
        "format": format_name,
        "observed_architectures": sorted(architectures),
        "selected_architecture": expected,
        "source": "same-descriptor-executable-header",
    }


def current_platform() -> Tuple[str, str, str]:
    uname = os.uname()
    operating_system = uname.sysname
    if operating_system not in ("Darwin", "Linux"):
        fail("the host operating system is unsupported")
    machine = uname.machine.lower()
    if machine in ("arm64", "aarch64"):
        architecture = "arm64"
    elif machine in ("x86_64", "amd64"):
        architecture = "x86_64"
    else:
        fail("the host architecture is unsupported")
    if operating_system == "Darwin":
        runtime = "none"
    else:
        try:
            libc = os.confstr("CS_GNU_LIBC_VERSION") or ""
        except (OSError, ValueError):
            libc = ""
        runtime = "glibc" if libc.startswith("glibc ") else "musl"
    return operating_system, architecture, "{}-{}-{}".format(
        operating_system, architecture, runtime)


class RuntimeAuditGuard:
    """Reject process/network/import/mutation capabilities after argument parsing."""

    def __init__(self, output_path: Optional[str]) -> None:
        self.output_path = output_path
        self.output_basename = os.path.basename(output_path) if output_path else None
        self.output_open_attempted = False
        self.output_created = False

    def _is_output(self, value: Any) -> bool:
        return (isinstance(value, str) and self.output_path is not None and
                value in (self.output_path, self.output_basename))

    def __call__(self, event: str, arguments: Tuple[Any, ...]) -> None:
        denied_prefixes = (
            "socket.", "subprocess.", "ctypes.", "os.exec", "os.spawn",
            "os.posix_spawn", "os.fork", "pty.spawn",
        )
        if event == "import" or event == "compile" or event == "exec" or \
                event.startswith(denied_prefixes) or event == "os.system":
            fail("runtime capability is disabled by the offline preflight: {}".format(event))
        if event == "open" and len(arguments) >= 3:
            flags = arguments[2]
            write_bits = (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC |
                          os.O_APPEND | getattr(os, "O_EXCL", 0))
            if isinstance(flags, int) and flags & write_bits:
                if not self._is_output(arguments[0]) or self.output_open_attempted:
                    fail("write-capable file open is disabled by the offline preflight")
                self.output_open_attempted = True
        if event in ("os.remove", "os.unlink"):
            if (not arguments or not self._is_output(arguments[0]) or
                    not self.output_created):
                fail("filesystem mutation is disabled by the offline preflight")
        elif event in (
                "os.rename", "os.replace", "os.mkdir", "os.rmdir", "os.chmod",
                "os.chown", "os.utime", "os.link", "os.symlink", "os.truncate"):
            fail("filesystem mutation is disabled by the offline preflight: {}".format(event))

    def mark_output_created(self) -> None:
        if not self.output_open_attempted or self.output_created:
            fail("output creation state is invalid")
        self.output_created = True


def install_audit_guard(output_path: Optional[str]) -> RuntimeAuditGuard:
    guard = RuntimeAuditGuard(output_path)
    sys.addaudithook(guard)
    return guard


def require_isolated_interpreter() -> None:
    if sys.version_info < (3, 9):
        fail("Python 3.9 or newer is required")
    if sys.implementation.name != "cpython":
        fail("the offline capability boundary requires CPython")
    if not (sys.flags.isolated and sys.flags.no_site and sys.flags.dont_write_bytecode):
        fail("invoke with an isolated interpreter: python3 -I -S -B")
    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY"):
        fail("this platform lacks required descriptor-safe filesystem flags")


def model_store_root(paths: Sequence[str]) -> str:
    if len(paths) < 2:
        fail("the model closure does not identify a store root")
    manifest = paths[0]
    marker = "/manifests/registry.ollama.ai/"
    if marker not in manifest:
        fail("the model manifest is outside the canonical Ollama store layout")
    common = canonical_absolute_path(manifest.split(marker, 1)[0],
                                     "Ollama model store root")
    if common in BROAD_TREE_ROOTS:
        fail("the Ollama model store root is too broad")
    descriptor = open_directory_chain(common, "Ollama model store root")
    os.close(descriptor)
    for path in paths:
        require_physical_file_within(common, path, "Ollama model artifact")
    return common


def require_receipt_location(path: str, ledger: IdentityLedger,
                             tree_roots: Sequence[str], model_root: str) -> None:
    receipt_path = canonical_absolute_path(path, "preflight receipt path")
    parent, _basename = split_file_path(receipt_path, "preflight receipt path")
    descriptor = open_directory_chain(parent, "preflight receipt parent")
    os.close(descriptor)
    if receipt_path in ledger.file_paths():
        fail("preflight receipt path overlaps a bound input")
    for root in list(tree_roots) + [model_root]:
        if physical_directory_contains(root, parent):
            fail("preflight receipt path is inside a bound runtime or model tree")


def validate_spec_and_build_receipt(spec_path: str, arm_path: str,
                                    receipt_path: str) -> Tuple[Dict[str, Any], IdentityLedger]:
    ledger = IdentityLedger()
    spec_path = canonical_absolute_path(spec_path, "preflight spec path")
    arm_path = canonical_absolute_path(arm_path, "neutral arm contract path")
    spec_observed = read_file(spec_path, "offline preflight spec",
                              maximum=MAX_JSON_BYTES, ledger=ledger)
    spec = parse_json(spec_observed["raw"], "offline preflight spec")
    require_canonical_json_bytes(spec, spec_observed, "offline preflight spec")
    exact_keys(spec, (
        "schema_version", "kind", "claim_scope", "runtime_binding_algorithm",
        "arm_contract", "platform", "node", "mainframe", "pi", "ollama",
        "adapter", "protocol"), "offline preflight spec")
    require_constant(spec["schema_version"], 1, "preflight spec schema version")
    require_constant(spec["kind"], SPEC_KIND, "preflight spec kind")
    require_constant(spec["claim_scope"], CLAIM_SCOPE, "preflight spec claim scope")
    require_constant(spec["runtime_binding_algorithm"], RUNTIME_BINDING_ALGORITHM,
                     "preflight runtime binding algorithm")

    arm_observed = validate_file_binding(spec["arm_contract"], "neutral arm contract",
                                         maximum=MAX_JSON_BYTES, ledger=ledger)
    require_bound_path(arm_observed, arm_path, "neutral arm contract")
    arm = parse_json(arm_observed["raw"], "neutral arm contract")
    require_canonical_json_bytes(arm, arm_observed, "neutral arm contract")

    _platform_input, platform_receipt = validate_platform(spec["platform"], ledger)
    operating_system = platform_receipt["operating_system"]
    architecture = platform_receipt["architecture"]
    platform_tuple = platform_receipt["platform_tuple"]
    node_receipt = validate_homebrew_runtime(spec["node"], "node", architecture,
                                             operating_system, ledger)
    mainframe_receipt, certification, mainframe_root = validate_mainframe(
        spec["mainframe"], platform_tuple, ledger)
    pi_receipt, pi_root = validate_pi(spec["pi"], architecture, platform_tuple,
                                      certification, ledger)

    ollama = exact_keys(spec["ollama"], (
        "version", "architecture", "executable", "install_receipt",
        "receipt_format", "model"), "ollama")
    ollama_receipt = validate_homebrew_runtime({
        key: ollama[key] for key in (
            "version", "architecture", "executable", "install_receipt", "receipt_format")
    }, "ollama", architecture, operating_system, ledger)
    model_receipt, model_paths = validate_model(ollama["model"], ledger)
    ollama_receipt["model"] = model_receipt
    model_root = model_store_root(model_paths)

    adapter_receipt = validate_adapter(spec["adapter"], mainframe_root, ledger)
    protocol_receipt = validate_protocol(spec["protocol"], mainframe_root, ledger)
    expected_binding = runtime_binding(spec)
    arm_receipt = validate_arm(arm, expected_binding, model_receipt["name"])
    require_receipt_location(receipt_path, ledger, (mainframe_root, pi_root), model_root)

    receipt = {
        "schema_version": 1,
        "kind": RECEIPT_KIND,
        "claim_scope": CLAIM_SCOPE,
        "status": "offline-bindings-and-neutral-arm-contract-valid",
        "spec": receipt_file("offline preflight spec", spec_observed),
        "arm_contract": receipt_file("neutral arm contract", arm_observed),
        "runtime_binding": expected_binding,
        "runtime": {
            "platform": platform_receipt,
            "node": node_receipt,
            "mainframe": mainframe_receipt,
            "pi": pi_receipt,
            "ollama": ollama_receipt,
            "adapter": adapter_receipt,
            "protocol": protocol_receipt,
        },
        "neutral_arm_contract": arm_receipt,
        "execution": {
            "offline_only": True,
            "actions_available": ["prepare", "verify"],
            "run_action_available": False,
            "processes_started_by_preflight": 0,
            "child_processes_started_after_preflight_entry": 0,
            "existing_machine_processes": "not-inspected",
            "machine_process_state_observed": False,
            "network_requests_by_preflight": 0,
            "shell_processes_started_by_preflight": 0,
            "node_processes_started_by_preflight": 0,
            "pi_processes_started_by_preflight": 0,
            "ollama_processes_started_by_preflight": 0,
            "provider_requests_by_preflight": 0,
            "prepare_action_files_created": 1,
            "verify_action_files_created": 0,
        },
        "non_claims": {
            "shell_runtime_executed": False,
            "node_runtime_executed": False,
            "pi_runtime_executed": False,
            "ollama_runtime_executed": False,
            "ollama_service_reachable": "not-inspected",
            "model_loaded": False,
            "provider_inference": False,
            "agent_sessions": 0,
            "neutral_arm_runtime_parity_executed": False,
            "mainframe_awm_transition_executed": False,
            "agent_impact_measured": False,
            "machine_safety_established": False,
            "entire_ollama_store_closed": False,
            "live_study_evidence_eligible": False,
        },
    }
    return receipt, ledger


def ensure_output_absent(path: str) -> None:
    parent, basename = split_file_path(path, "preflight receipt output")
    parent_fd = open_directory_chain(parent, "preflight receipt output parent")
    try:
        try:
            os.stat(basename, dir_fd=parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            return
        fail("preflight receipt output already exists; refusing to overwrite it")
    finally:
        os.close(parent_fd)


def output_node_identity(metadata: os.stat_result) -> Tuple[int, ...]:
    return (metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_nlink,
            metadata.st_uid, metadata.st_gid)


def remove_created_output(path: str, identity: Tuple[int, ...]) -> None:
    parent, basename = split_file_path(path, "preflight receipt cleanup")
    parent_fd = open_directory_chain(parent, "preflight receipt cleanup parent")
    try:
        metadata = os.stat(basename, dir_fd=parent_fd, follow_symlinks=False)
        if output_node_identity(metadata) != identity or not stat.S_ISREG(metadata.st_mode):
            fail("created receipt changed before cleanup; refusing to unlink it")
        os.unlink(basename, dir_fd=parent_fd)
    finally:
        os.close(parent_fd)


def write_receipt_exclusive(path: str, raw: bytes,
                            guard: RuntimeAuditGuard) -> Tuple[int, ...]:
    parent, basename = split_file_path(path, "preflight receipt output")
    parent_fd = open_directory_chain(parent, "preflight receipt output parent")
    descriptor = -1
    identity: Optional[Tuple[int, ...]] = None
    try:
        flags = (os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                 getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0))
        descriptor = os.open(basename, flags, 0o600, dir_fd=parent_fd)
        guard.mark_output_created()
        created = os.fstat(descriptor)
        identity = output_node_identity(created)
        if (not stat.S_ISREG(created.st_mode) or created.st_nlink != 1 or
                created.st_uid != os.geteuid() or stat.S_IMODE(created.st_mode) != 0o600):
            fail("created receipt does not have the required private identity")
        offset = 0
        while offset < len(raw):
            written = os.write(descriptor, raw[offset:])
            if written <= 0:
                fail("created receipt could not be written completely")
            offset += written
        os.fsync(descriptor)
        finished = os.fstat(descriptor)
        if (output_node_identity(finished) != identity or finished.st_size != len(raw)):
            fail("created receipt changed while it was written")
        os.close(descriptor)
        descriptor = -1
        observed = read_file(path, "created preflight receipt", maximum=MAX_JSON_BYTES)
        if observed["raw"] != raw or observed["mode"] != "0600":
            fail("created receipt did not preserve its canonical private bytes")
        return identity
    except Exception:
        if descriptor >= 0:
            os.close(descriptor)
            descriptor = -1
        if identity is not None:
            remove_created_output(path, identity)
        raise
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        os.close(parent_fd)


def prepare_receipt(spec_path: str, arm_path: str, output_path: str) -> None:
    output_path = canonical_absolute_path(output_path, "preflight receipt output")
    guard = install_audit_guard(output_path)
    ensure_output_absent(output_path)
    receipt, ledger = validate_spec_and_build_receipt(spec_path, arm_path, output_path)
    raw = canonical_json(receipt)
    if len(raw) > MAX_JSON_BYTES:
        fail("preflight receipt exceeds its size ceiling")
    ledger.revalidate()
    identity = write_receipt_exclusive(output_path, raw, guard)
    try:
        ledger.revalidate()
    except Exception:
        remove_created_output(output_path, identity)
        raise


def verify_receipt(spec_path: str, arm_path: str, receipt_path: str) -> None:
    receipt_path = canonical_absolute_path(receipt_path, "preflight receipt path")
    install_audit_guard(None)
    expected, ledger = validate_spec_and_build_receipt(spec_path, arm_path, receipt_path)
    observed = read_file(receipt_path, "preflight receipt", maximum=MAX_JSON_BYTES)
    if observed["mode"] != "0600":
        fail("preflight receipt must have mode 0600")
    if ledger.contains_file_identity(observed["identity"]):
        fail("preflight receipt aliases a bound input")
    parsed = parse_json(observed["raw"], "preflight receipt")
    if observed["raw"] != canonical_json(parsed):
        fail("preflight receipt is not canonical JSON")
    if parsed != expected:
        fail("preflight receipt differs from the exact current offline bindings")
    ledger.revalidate()


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prepare or verify an offline Pi/Ollama runtime-binding preflight receipt.")
    subparsers = parser.add_subparsers(dest="action", required=True)
    prepare = subparsers.add_parser("prepare", help="validate bindings and create one receipt")
    prepare.add_argument("--spec", required=True, metavar="ABSOLUTE_PATH")
    prepare.add_argument("--arm-contract", required=True, metavar="ABSOLUTE_PATH")
    prepare.add_argument("--output", required=True, metavar="ABSOLUTE_PATH")
    verify = subparsers.add_parser("verify", help="revalidate bindings and an existing receipt")
    verify.add_argument("--spec", required=True, metavar="ABSOLUTE_PATH")
    verify.add_argument("--arm-contract", required=True, metavar="ABSOLUTE_PATH")
    verify.add_argument("--receipt", required=True, metavar="ABSOLUTE_PATH")
    return parser.parse_args()


def main() -> int:
    try:
        require_isolated_interpreter()
        arguments = parse_arguments()
        if arguments.action == "prepare":
            prepare_receipt(arguments.spec, arguments.arm_contract, arguments.output)
        else:
            verify_receipt(arguments.spec, arguments.arm_contract, arguments.receipt)
        return 0
    except PreflightError as error:
        sys.stderr.write("offline Pi/Ollama preflight refused: {}\n".format(error))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

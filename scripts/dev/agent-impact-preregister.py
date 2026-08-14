#!/usr/bin/env python3
"""Prepare or verify a deterministic live-study preregistration.

This program deliberately has no action that launches a runner, provider, agent,
grader, archive, or task payload. It only validates and hashes declared inputs,
creates a public preregistration, and creates a private assignment reveal.
"""

import argparse
import ctypes
import ctypes.util
import errno
import hashlib
import hmac
import json
import math
import os
import re
import stat
import sys
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any, Dict, Iterable, List, NoReturn, Optional, Pattern, Tuple


PROJECT_ROOT = Path(__file__).resolve().parents[2]
PROTOCOL_ROOT = PROJECT_ROOT / "evals" / "agent-impact"
MAX_JSON_BYTES = 1024 * 1024
MAX_PROTOCOL_FILE_BYTES = 8 * 1024 * 1024
MAX_SEED_BYTES = 1024
MAX_TASKS = 256
MAX_REPOSITORY_ENTRIES = 10000
MAX_REPOSITORY_BYTES = 16 * 1024 * 1024
MAX_CORPUS_ENTRIES = 20000
MAX_CORPUS_BYTES = 16 * 1024 * 1024
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,127}$")
PROVIDER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/+:-]{0,255}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
IMAGE_DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
CLAIM_SCOPE = "preregistered-live-study-not-run"
HYPOTHESIS = (
    "A bounded MAINFRAME AWM handoff improves a fresh implementation session's "
    "hidden grader score relative to an equally bounded native/manual handoff "
    "for a pinned provider, model, and fixed coding-task suite."
)
POLICY_CONTRACTS: Dict[str, Dict[str, Any]] = {
    "isolation": {
        "kind": "mainframe-agent-impact-isolation-policy",
        "controls": {
            "boundary": "fresh-container-vm-or-separate-os-user",
            "task_source": "byte-identical-read-only",
            "workspace": "private-writable-per-arm",
            "fresh_state": [
                "cache",
                "configuration",
                "home",
                "process",
                "provider-session",
                "temporary-directory",
                "xdg",
            ],
            "hidden_inputs": "not-mounted-or-readable",
            "cross_arm_state": "none",
            "resource_termination": "whole-workload-before-grading",
            "network_egress": "default-deny-provider-proxy-only",
            "grader": "outside-agent-boundary-network-denied-after-stop",
        },
    },
    "provider_proxy": {
        "kind": "mainframe-agent-impact-provider-proxy-policy",
        "controls": {
            "credentials": "outside-agent-environment",
            "network_route": "sole-provider-egress-route",
            "request_scope": [
                "arm",
                "model",
                "pair",
                "parameters",
                "phase",
                "provider",
                "study",
            ],
            "unregistered_invocation": "reject",
            "duplicate_invocation": "reject",
            "call_and_token_policy": "enforce-where-provider-supports",
            "audit_record": "credential-free-append-only",
            "direct_provider_access": "invalidates-run",
        },
    },
    "awm_mechanism_contract": {
        "kind": "mainframe-agent-impact-awm-mechanism-contract",
        "controls": {
            "control_comparator": "native-bounded-handoff",
            "treatment_intervention": "mainframe-awm-handoff",
            "writes": "recorded",
            "state_receipts": "before-and-after-each-phase",
            "export": "bounded-read-only-neutral-continuation-envelope",
            "context_limit_unit": "bytes-under-LC_ALL-C",
            "executable_binding": "release-and-installed-tree",
            "arm_label_assertion": "insufficient-proof",
        },
    },
}


class ProtocolError(RuntimeError):
    """A fail-closed preregistration validation error."""


def die(message: str) -> NoReturn:
    raise ProtocolError(message)


def canonical_bytes(value: Any) -> bytes:
    try:
        return json.dumps(
            value,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
            allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError) as error:
        die("value cannot be encoded as canonical JSON: {}".format(error))


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def mode_text(path: Path) -> str:
    return format(stat.S_IMODE(path.lstat().st_mode), "04o")


def require_real_directory(path: Path, label: str) -> Path:
    try:
        metadata = path.lstat()
    except OSError as error:
        die("{} is unavailable: {}: {}".format(label, path, error))
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        die("{} must be a real directory: {}".format(label, path))
    return path.resolve(strict=True)


def require_regular_file(
    path: Path,
    label: str,
    maximum_bytes: Optional[int] = MAX_PROTOCOL_FILE_BYTES,
    executable: bool = False,
) -> Path:
    try:
        metadata = path.lstat()
    except OSError as error:
        die("{} is unavailable: {}: {}".format(label, path, error))
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        die("{} must be a regular, non-symlink file: {}".format(label, path))
    if metadata.st_nlink != 1:
        die("{} must not be hard-linked: {}".format(label, path))
    if metadata.st_size <= 0:
        die("{} must not be empty: {}".format(label, path))
    if maximum_bytes is not None and metadata.st_size > maximum_bytes:
        die("{} is oversized: {} ({} bytes)".format(label, path, metadata.st_size))
    if executable and not os.access(str(path), os.X_OK):
        die("{} must be executable: {}".format(label, path))
    return path.resolve(strict=True)


def read_bytes(
    path: Path, label: str, maximum_bytes: Optional[int] = MAX_PROTOCOL_FILE_BYTES
) -> bytes:
    path = require_regular_file(path, label, maximum_bytes=maximum_bytes)
    initial = path.lstat()
    descriptor = -1
    try:
        flags = os.O_RDONLY
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = os.open(str(path), flags)
        opened = os.fstat(descriptor)
        identity = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")
        if any(getattr(opened, field) != getattr(initial, field) for field in identity):
            die("{} changed before it was read: {}".format(label, path))
        chunks: List[bytes] = []
        bytes_read = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            bytes_read += len(chunk)
            chunks.append(chunk)
        final = os.fstat(descriptor)
        if bytes_read != initial.st_size:
            die(
                "{} is dataless, truncated, or changed while reading: {} "
                "(stat size {}, bytes read {})".format(
                    label, path, initial.st_size, bytes_read
                )
            )
        if any(getattr(final, field) != getattr(opened, field) for field in identity):
            die("{} changed while it was read: {}".format(label, path))
        return b"".join(chunks)
    except ProtocolError:
        raise
    except OSError as error:
        die("{} cannot be read: {}".format(label, error))
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def sha256_file(path: Path, label: str = "digest input") -> str:
    path = require_regular_file(path, label, maximum_bytes=None)
    initial = path.lstat()
    digest = hashlib.sha256()
    bytes_read = 0
    descriptor = -1
    try:
        flags = os.O_RDONLY
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = os.open(str(path), flags)
        opened = os.fstat(descriptor)
        identity = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")
        if any(getattr(opened, field) != getattr(initial, field) for field in identity):
            die("{} changed before it was read: {}".format(label, path))
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            bytes_read += len(chunk)
            digest.update(chunk)
        final = os.fstat(descriptor)
        if bytes_read != initial.st_size:
            die(
                "{} is dataless, truncated, or changed while hashing: {} "
                "(stat size {}, bytes read {})".format(
                    label, path, initial.st_size, bytes_read
                )
            )
        if any(getattr(final, field) != getattr(opened, field) for field in identity):
            die("{} changed while it was read: {}".format(label, path))
    except ProtocolError:
        raise
    except OSError as error:
        die("{} cannot be read: {}".format(label, error))
    finally:
        if descriptor >= 0:
            os.close(descriptor)
    return digest.hexdigest()


def raw_extended_attributes(path: Path) -> Dict[str, bytes]:
    """Read xattrs without starting a platform utility.

    Some Apple-distributed Python builds omit os.listxattr, so use libc as the
    fallback. Every caller has already rejected symbolic links.
    """

    if hasattr(os, "listxattr") and hasattr(os, "getxattr"):
        try:
            names = os.listxattr(str(path), follow_symlinks=False)
            return {
                name: os.getxattr(str(path), name, follow_symlinks=False)
                for name in names
            }
        except OSError as error:
            if error.errno in (errno.ENOTSUP, errno.EOPNOTSUPP, errno.ENOSYS):
                return {}
            raise

    library_name = ctypes.util.find_library("c")
    if library_name is None:
        die("extended attributes cannot be inspected on this platform")
    libc = ctypes.CDLL(library_name, use_errno=True)
    encoded_path = os.fsencode(str(path))
    is_macos = sys.platform == "darwin"

    def call_list(buffer: Any, size: int) -> int:
        if is_macos:
            return int(libc.listxattr(encoded_path, buffer, size, 1))
        return int(libc.listxattr(encoded_path, buffer, size))

    ctypes.set_errno(0)
    name_size = call_list(None, 0)
    if name_size < 0:
        error_number = ctypes.get_errno()
        if error_number in (errno.ENOTSUP, errno.EOPNOTSUPP, errno.ENOSYS):
            return {}
        raise OSError(error_number, os.strerror(error_number), str(path))
    if name_size == 0:
        return {}
    name_buffer = ctypes.create_string_buffer(name_size)
    if call_list(name_buffer, name_size) != name_size:
        error_number = ctypes.get_errno()
        raise OSError(error_number, os.strerror(error_number), str(path))
    names = [name for name in name_buffer.raw.split(b"\0") if name]
    attributes: Dict[str, bytes] = {}
    for encoded_name in names:
        ctypes.set_errno(0)
        if is_macos:
            value_size = int(
                libc.getxattr(encoded_path, encoded_name, None, 0, 0, 1)
            )
        else:
            value_size = int(libc.getxattr(encoded_path, encoded_name, None, 0))
        if value_size < 0:
            error_number = ctypes.get_errno()
            raise OSError(error_number, os.strerror(error_number), str(path))
        value_buffer = ctypes.create_string_buffer(value_size)
        if is_macos:
            observed_size = int(
                libc.getxattr(
                    encoded_path, encoded_name, value_buffer, value_size, 0, 1
                )
            )
        else:
            observed_size = int(
                libc.getxattr(encoded_path, encoded_name, value_buffer, value_size)
            )
        if observed_size != value_size:
            error_number = ctypes.get_errno()
            raise OSError(error_number, os.strerror(error_number), str(path))
        attributes[os.fsdecode(encoded_name)] = value_buffer.raw[:value_size]
    return attributes


def reject_extended_attributes(path: Path, label: str) -> None:
    try:
        attributes = raw_extended_attributes(path)
    except OSError as error:
        die("{} extended attributes cannot be inspected: {}".format(label, error))
    # Finder provenance and APFS transparent compression metadata are inert and
    # machine-specific. The commitment hashes the bytes returned by the file
    # API, so these bounded attributes are intentionally outside the portable
    # byte/mode identity. ResourceFork, quarantine, ACL-like, and unknown
    # attributes still fail closed.
    unsupported = {
        name: value
        for name, value in attributes.items()
        if not (
            (name == "com.apple.provenance" and len(value) <= 4096)
            or (name == "com.apple.decmpfs" and len(value) <= 1024 * 1024)
        )
    }
    if unsupported:
        die(
            "{} carries unsupported extended attributes {}: {}".format(
                label, sorted(unsupported), path
            )
        )


def load_json_text(text: str, label: str) -> Any:
    def reject_duplicates(pairs: List[Tuple[str, Any]]) -> Dict[str, Any]:
        result: Dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                die("{} contains duplicate key {!r}".format(label, key))
            result[key] = value
        return result

    def reject_constant(value: str) -> NoReturn:
        die("{} contains non-finite number {}".format(label, value))

    try:
        return json.loads(
            text,
            object_pairs_hook=reject_duplicates,
            parse_constant=reject_constant,
        )
    except json.JSONDecodeError as error:
        die("{} is not valid JSON: {}".format(label, error))


def load_json_with_bytes(
    path: Path, label: str, maximum_bytes: int = MAX_JSON_BYTES
) -> Tuple[Any, bytes]:
    payload = read_bytes(path, label, maximum_bytes=maximum_bytes)
    try:
        text = payload.decode("utf-8")
    except UnicodeDecodeError as error:
        die("{} cannot be read as UTF-8: {}".format(label, error))
    return load_json_text(text, label), payload


def load_json(path: Path, label: str, maximum_bytes: int = MAX_JSON_BYTES) -> Any:
    return load_json_with_bytes(path, label, maximum_bytes)[0]


def exact_keys(value: Any, expected: Iterable[str], label: str) -> Dict[str, Any]:
    if not isinstance(value, dict):
        die("{} must be a JSON object".format(label))
    expected_set = set(expected)
    actual_set = set(value)
    if actual_set != expected_set:
        die(
            "{} keys differ (missing={}, extras={})".format(
                label,
                sorted(expected_set - actual_set),
                sorted(actual_set - expected_set),
            )
        )
    return value


def require_string(
    value: Any,
    label: str,
    pattern: Optional[Pattern[str]] = None,
    maximum_length: int = 1024,
) -> str:
    if not isinstance(value, str) or not value:
        die("{} must be a non-empty string".format(label))
    if len(value) > maximum_length:
        die("{} is too long".format(label))
    if pattern is not None and pattern.fullmatch(value) is None:
        die("{} has an invalid value: {!r}".format(label, value))
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        die("{} contains a control character".format(label))
    return value


def require_integer(value: Any, label: str, minimum: int, maximum: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        die("{} must be an integer".format(label))
    if value < minimum or value > maximum:
        die("{} is outside [{}, {}]".format(label, minimum, maximum))
    return value


def require_number(value: Any, label: str, minimum: float, maximum: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        die("{} must be a number".format(label))
    number = float(value)
    if not math.isfinite(number) or number < minimum or number > maximum:
        die("{} is outside [{}, {}]".format(label, minimum, maximum))
    return number


def require_const(value: Any, expected: Any, label: str) -> None:
    if value != expected or type(value) is not type(expected):
        die("{} must be {!r}".format(label, expected))


def safe_relative_path(value: Any, label: str) -> PurePosixPath:
    text = require_string(value, label)
    if "\\" in text:
        die("{} must use POSIX separators".format(label))
    relative = PurePosixPath(text)
    if relative.is_absolute() or not relative.parts:
        die("{} must be a relative path".format(label))
    if any(part in ("", ".", "..") for part in relative.parts):
        die("{} contains an unsafe path component".format(label))
    return relative


def resolve_confined(
    root: Path,
    relative: PurePosixPath,
    label: str,
    want_directory: bool = False,
    executable: bool = False,
    maximum_bytes: Optional[int] = MAX_PROTOCOL_FILE_BYTES,
) -> Path:
    root = require_real_directory(root, "{} root".format(label))
    current = root
    for index, component in enumerate(relative.parts):
        current = current / component
        try:
            metadata = current.lstat()
        except OSError as error:
            die("{} is unavailable: {}: {}".format(label, current, error))
        if stat.S_ISLNK(metadata.st_mode):
            die("{} traverses a symbolic link: {}".format(label, current))
        is_last = index == len(relative.parts) - 1
        if not is_last and not stat.S_ISDIR(metadata.st_mode):
            die("{} parent is not a directory: {}".format(label, current))
    if want_directory:
        return require_real_directory(current, label)
    return require_regular_file(
        current, label, maximum_bytes=maximum_bytes, executable=executable
    )


def tree_records(root: Path) -> List[Dict[str, Any]]:
    root = require_real_directory(root, "task repository")
    reject_extended_attributes(root, "task repository directory")
    records: List[Dict[str, Any]] = []
    total_bytes = 0
    for current, directories, files in os.walk(str(root), topdown=True, followlinks=False):
        current_path = Path(current)
        directories.sort()
        files.sort()
        for name in list(directories):
            path = current_path / name
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
                die("task repository contains an unsafe directory: {}".format(path))
            reject_extended_attributes(path, "task repository directory")
            records.append(
                {
                    "path": path.relative_to(root).as_posix(),
                    "type": "directory",
                    "mode": format(stat.S_IMODE(metadata.st_mode), "04o"),
                }
            )
            if len(records) > MAX_REPOSITORY_ENTRIES:
                die("task repository exceeds the entry quota")
        for name in files:
            path = current_path / name
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
                die("task repository contains an unsafe file: {}".format(path))
            if metadata.st_nlink != 1:
                die("task repository contains a hard-linked file: {}".format(path))
            reject_extended_attributes(path, "task repository file")
            if metadata.st_size > MAX_PROTOCOL_FILE_BYTES:
                die("task repository file is oversized: {}".format(path))
            total_bytes += metadata.st_size
            if total_bytes > MAX_REPOSITORY_BYTES:
                die("task repository exceeds the total byte quota")
            records.append(
                {
                    "path": path.relative_to(root).as_posix(),
                    "type": "file",
                    "mode": format(stat.S_IMODE(metadata.st_mode), "04o"),
                    "size_bytes": metadata.st_size,
                    "sha256": sha256_file(path, "task repository file"),
                }
            )
            if len(records) > MAX_REPOSITORY_ENTRIES:
                die("task repository exceeds the entry quota")
    records.sort(key=lambda record: (record["path"], record["type"]))
    return records


def validate_task(task_path: Path, protocol_root: Path) -> Dict[str, Any]:
    reject_extended_attributes(task_path, "task definition")
    task = exact_keys(
        load_json(task_path, "task"),
        (
            "schema_version",
            "kind",
            "id",
            "title",
            "category",
            "repository",
            "phases",
            "transition",
            "budgets",
            "grader",
        ),
        "task",
    )
    require_const(task["schema_version"], 1, "task.schema_version")
    require_const(task["kind"], "mainframe-agent-impact-task", "task.kind")
    task_id = require_string(task["id"], "task.id", ID_RE)
    require_string(task["title"], "task.title")
    require_const(task["category"], "fresh-session-handoff", "task.category")
    task_directory = require_real_directory(task_path.parent, "task directory")
    reject_extended_attributes(task_directory, "task directory")

    repository_relative = safe_relative_path(task["repository"], "task.repository")
    repository = resolve_confined(
        task_directory, repository_relative, "task repository", want_directory=True
    )
    repository_inventory = tree_records(repository)
    if not any(record["type"] == "file" for record in repository_inventory):
        die("task repository must contain a regular file")

    phases = task["phases"]
    if not isinstance(phases, list) or len(phases) != 2:
        die("task.phases must contain exactly investigate and implement")
    prompt_bindings: List[Dict[str, str]] = []
    for index, (phase_id, workspace_edits) in enumerate(
        (("investigate", False), ("implement", True))
    ):
        phase = exact_keys(
            phases[index], ("id", "prompt", "workspace_edits"), "task phase"
        )
        require_const(phase["id"], phase_id, "task phase id")
        require_const(phase["workspace_edits"], workspace_edits, "workspace edits")
        prompt_relative = safe_relative_path(phase["prompt"], "task prompt")
        if len(prompt_relative.parts) != 1 or not prompt_relative.name.endswith(".md"):
            die("task prompt must be a direct Markdown child")
        prompt_path = resolve_confined(task_directory, prompt_relative, "task prompt")
        reject_extended_attributes(prompt_path, "task prompt")
        prompt_bindings.append(
            {
                "path": prompt_relative.as_posix(),
                "mode": mode_text(prompt_path),
                "sha256": sha256_file(prompt_path),
            }
        )

    transition = exact_keys(
        task["transition"],
        (
            "fresh_host_state",
            "preserve_workspace",
            "context_budget",
            "control",
            "treatment",
        ),
        "task.transition",
    )
    require_const(transition["fresh_host_state"], True, "fresh host state")
    require_const(transition["preserve_workspace"], True, "preserve workspace")
    require_const(
        transition["control"], "native-bounded-handoff", "control contract"
    )
    require_const(
        transition["treatment"], "mainframe-awm-handoff", "treatment contract"
    )
    context_budget = exact_keys(
        transition["context_budget"], ("unit", "maximum"), "task context budget"
    )
    require_const(
        context_budget["unit"], "bytes-under-LC_ALL-C", "context budget unit"
    )
    maximum_context_bytes = require_integer(
        context_budget["maximum"], "maximum context bytes", 1, 65536
    )

    budgets = exact_keys(
        task["budgets"],
        ("wall_seconds_per_phase", "maximum_tool_calls_per_phase"),
        "task.budgets",
    )
    wall_seconds = require_number(
        budgets["wall_seconds_per_phase"], "wall seconds per phase", 0.1, 7200
    )
    maximum_tool_calls = require_integer(
        budgets["maximum_tool_calls_per_phase"], "maximum tool calls", 1, 1000
    )

    grader = exact_keys(task["grader"], ("command", "maximum_score"), "task.grader")
    grader_relative = safe_relative_path(grader["command"], "task grader")
    if len(grader_relative.parts) != 1 or not grader_relative.name.endswith(".py"):
        die("task grader must be a direct Python child")
    grader_path = resolve_confined(task_directory, grader_relative, "task grader")
    reject_extended_attributes(grader_path, "task grader")
    require_integer(grader["maximum_score"], "grader maximum score", 1, 1000000)

    binding: Dict[str, Any] = {
        "task_path": task_path.relative_to(protocol_root).as_posix(),
        "task_mode": mode_text(task_path),
        "task_sha256": sha256_file(task_path),
        "task_id": task_id,
        "prompt_files": prompt_bindings,
        "repository_path": repository_relative.as_posix(),
        "repository_tree_sha256": sha256_bytes(canonical_bytes(repository_inventory)),
        "grader_path": grader_relative.as_posix(),
        "grader_mode": mode_text(grader_path),
        "grader_sha256": sha256_file(grader_path),
    }
    binding["task_bundle_sha256"] = sha256_bytes(canonical_bytes(binding))
    corpus_entry_count = 1 + len(prompt_bindings) + len(repository_inventory) + 1
    corpus_bytes = (
        task_path.lstat().st_size
        + sum(
            (task_directory / prompt["path"]).lstat().st_size
            for prompt in prompt_bindings
        )
        + sum(
            record.get("size_bytes", 0) for record in repository_inventory
        )
        + grader_path.lstat().st_size
    )
    return {
        "id": task_id,
        "binding": binding,
        "wall_seconds_per_phase": wall_seconds,
        "maximum_tool_calls_per_phase": maximum_tool_calls,
        "maximum_context_bytes": maximum_context_bytes,
        "corpus_entry_count": corpus_entry_count,
        "corpus_bytes": corpus_bytes,
    }


def load_corpus(suite_path: Path, suite_reference: str) -> Dict[str, Any]:
    suite_path = require_regular_file(suite_path, "suite")
    reject_extended_attributes(suite_path, "suite")
    if suite_path.parent.name != "suites":
        die("suite must be directly under a suites directory")
    protocol_root = require_real_directory(suite_path.parent.parent, "protocol root")
    schema_bindings: List[Dict[str, str]] = []
    corpus_entry_count = 1
    corpus_bytes = suite_path.lstat().st_size
    for schema_name in ("suite.schema.json", "task.schema.json"):
        schema_path = require_regular_file(protocol_root / schema_name, "v1 schema")
        reject_extended_attributes(schema_path, "v1 schema")
        schema_bindings.append(
            {
                "path": schema_name,
                "mode": mode_text(schema_path),
                "sha256": sha256_file(schema_path),
            }
        )
        corpus_entry_count += 1
        corpus_bytes += schema_path.lstat().st_size

    suite = exact_keys(
        load_json(suite_path, "suite"),
        ("schema_version", "kind", "id", "description", "tasks"),
        "suite",
    )
    require_const(suite["schema_version"], 1, "suite.schema_version")
    require_const(suite["kind"], "mainframe-agent-impact-suite", "suite.kind")
    suite_id = require_string(suite["id"], "suite.id", ID_RE)
    require_string(suite["description"], "suite.description")
    task_values = suite["tasks"]
    if not isinstance(task_values, list) or not task_values:
        die("suite.tasks must be a non-empty array")
    if len(task_values) > MAX_TASKS:
        die("suite.tasks exceeds the task quota")
    if len(task_values) != 3:
        die("pilot and confirmatory live studies require exactly three tasks")
    if any(not isinstance(item, str) for item in task_values):
        die("suite.tasks must contain strings")
    if len(task_values) != len(set(task_values)):
        die("suite.tasks contains duplicates")

    tasks: List[Dict[str, Any]] = []
    for index, task_value in enumerate(task_values):
        relative = safe_relative_path(task_value, "suite.tasks[{}]".format(index))
        if (
            len(relative.parts) != 3
            or relative.parts[0] != "tasks"
            or relative.parts[2] != "task.json"
        ):
            die("suite task path must be tasks/ID/task.json")
        task_path = resolve_confined(protocol_root, relative, "suite task")
        task = validate_task(task_path, protocol_root)
        if relative.parts[1] != task["id"]:
            die("task directory name must match task.id")
        tasks.append(task)
        corpus_entry_count += task["corpus_entry_count"]
        corpus_bytes += task["corpus_bytes"]
        if corpus_entry_count > MAX_CORPUS_ENTRIES:
            die("task corpus exceeds the aggregate entry quota")
        if corpus_bytes > MAX_CORPUS_BYTES:
            die("task corpus exceeds the aggregate byte quota")
    if len({task["id"] for task in tasks}) != len(tasks):
        die("suite contains duplicate task IDs")

    binding: Dict[str, Any] = {
        "protocol_version": 1,
        "suite_path": suite_reference,
        "suite_mode": mode_text(suite_path),
        "suite_id": suite_id,
        "suite_sha256": sha256_file(suite_path),
        "schemas": schema_bindings,
        "tasks": [task["binding"] for task in tasks],
    }
    binding["corpus_sha256"] = sha256_bytes(canonical_bytes(binding))
    return {"binding": binding, "tasks": tasks}


def validate_study(value: Any) -> Dict[str, Any]:
    study = exact_keys(
        value,
        (
            "schema_version",
            "kind",
            "id",
            "title",
            "hypothesis",
            "stage",
            "task_classes",
            "suite",
            "replicates_per_task",
            "planned_runner",
            "mainframe_release",
            "container_image_digest",
            "isolation_policy",
            "provider_proxy_policy",
            "awm_mechanism_contract",
            "host_environment",
            "provider",
            "budgets",
            "endpoint",
            "statistics",
            "exclusions",
            "stopping",
            "publication",
        ),
        "live study",
    )
    require_const(study["schema_version"], 2, "live study.schema_version")
    require_const(study["kind"], "mainframe-agent-impact-live-study", "live study.kind")
    require_string(study["id"], "live study.id", ID_RE)
    require_string(study["title"], "live study.title")
    require_const(study["hypothesis"], HYPOTHESIS, "live study hypothesis")
    if study["stage"] not in ("pilot", "confirmatory"):
        die("live study.stage must be pilot or confirmatory")
    expected_task_classes = [
        "nested-configuration-precedence-and-falsy-merge",
        "checkpoint-after-commit-idempotency",
        "safe-manifest-include",
    ]
    if study["task_classes"] != expected_task_classes:
        die("live study.task_classes must disclose the fixed three-task live suite")
    safe_relative_path(study["suite"], "live study.suite")
    replicates = require_integer(
        study["replicates_per_task"], "replicates per task", 6, 1000
    )
    if replicates % 2 != 0:
        die("replicates per task must be even for exact within-task balance")
    if study["stage"] == "pilot" and replicates != 6:
        die("pilot stage requires exactly 6 replicates per task")
    if study["stage"] == "confirmatory" and replicates not in (12, 20):
        die("confirmatory stage requires exactly 12 or 20 replicates per task")

    runner = exact_keys(
        study["planned_runner"], ("executable", "manifest"), "planned runner"
    )
    safe_relative_path(runner["executable"], "planned runner executable")
    safe_relative_path(runner["manifest"], "planned runner manifest")

    release = exact_keys(
        study["mainframe_release"],
        (
            "archive",
            "checksum_sidecar",
            "installed_tree_algorithm",
            "installed_tree_sha256",
        ),
        "MAINFRAME release",
    )
    safe_relative_path(release["archive"], "MAINFRAME archive")
    safe_relative_path(release["checksum_sidecar"], "MAINFRAME checksum sidecar")
    require_const(
        release["installed_tree_algorithm"],
        "mainframe-package-tree-sha256-v1",
        "installed tree algorithm",
    )
    require_string(
        release["installed_tree_sha256"], "installed tree digest", SHA256_RE
    )
    require_string(
        study["container_image_digest"],
        "container image digest",
        IMAGE_DIGEST_RE,
    )
    safe_relative_path(study["isolation_policy"], "isolation policy")
    safe_relative_path(study["provider_proxy_policy"], "provider proxy policy")
    safe_relative_path(study["awm_mechanism_contract"], "AWM mechanism contract")
    host = exact_keys(
        study["host_environment"],
        ("operating_system", "architecture", "shell"),
        "host environment",
    )
    if host["operating_system"] not in ("linux", "macos"):
        die("host operating system must be linux or macos")
    if host["architecture"] not in ("x86_64", "arm64"):
        die("host architecture must be x86_64 or arm64")
    shell = exact_keys(
        host["shell"],
        ("name", "version", "executable_sha256"),
        "host shell",
    )
    if shell["name"] not in ("bash", "zsh"):
        die("host shell name must be bash or zsh")
    require_string(shell["version"], "host shell version", PROVIDER_RE)
    require_string(shell["executable_sha256"], "host shell digest", SHA256_RE)

    provider = exact_keys(
        study["provider"],
        ("name", "model", "model_snapshot", "client", "host", "configuration"),
        "provider",
    )
    require_string(provider["name"], "provider.name", PROVIDER_RE)
    require_string(provider["model"], "provider.model", PROVIDER_RE)
    require_string(provider["model_snapshot"], "provider.model_snapshot", PROVIDER_RE)
    for binding_name in ("client", "host"):
        binding = exact_keys(
            provider[binding_name], ("name", "version"), "provider.{}".format(binding_name)
        )
        require_string(binding["name"], "provider.{}.name".format(binding_name), PROVIDER_RE)
        require_string(
            binding["version"], "provider.{}.version".format(binding_name), PROVIDER_RE
        )
    configuration = exact_keys(
        provider["configuration"],
        ("temperature", "top_p", "provider_seed", "tool_choice", "reasoning_effort"),
        "provider.configuration",
    )
    require_number(configuration["temperature"], "temperature", 0, 2)
    require_number(configuration["top_p"], "top_p", 0, 1)
    if configuration["provider_seed"] is not None:
        require_integer(
            configuration["provider_seed"], "provider seed", -(2**63), 2**63 - 1
        )
    if configuration["tool_choice"] not in ("auto", "required", "none"):
        die("tool_choice is unsupported")
    if configuration["reasoning_effort"] not in (
        "none",
        "low",
        "medium",
        "high",
    ):
        die("reasoning_effort is unsupported")

    budgets = exact_keys(
        study["budgets"],
        (
            "wall_seconds_per_phase",
            "maximum_tool_calls_per_phase",
            "maximum_context_bytes",
            "maximum_input_tokens_per_phase",
            "maximum_output_tokens_per_phase",
            "maximum_cost_usd_per_pair",
        ),
        "study budgets",
    )
    require_const(budgets["wall_seconds_per_phase"], 900, "wall budget")
    require_const(budgets["maximum_tool_calls_per_phase"], 40, "tool budget")
    require_const(budgets["maximum_context_bytes"], 8192, "context budget")
    require_integer(
        budgets["maximum_input_tokens_per_phase"], "input token budget", 1, 10000000
    )
    require_integer(
        budgets["maximum_output_tokens_per_phase"], "output token budget", 1, 10000000
    )
    require_number(
        budgets["maximum_cost_usd_per_pair"], "cost budget", 0, 1000000
    )

    endpoint = exact_keys(
        study["endpoint"], ("primary", "secondary", "direction", "unit"), "endpoint"
    )
    require_const(
        endpoint["primary"],
        "equal-task-weighted-paired-normalized-score-delta",
        "primary endpoint",
    )
    require_const(endpoint["direction"], "higher-is-better", "endpoint direction")
    require_const(endpoint["unit"], "normalized-task-score", "endpoint unit")
    require_const(
        endpoint["secondary"], "paired-binary-solve-status", "secondary endpoint"
    )

    statistics = exact_keys(
        study["statistics"],
        (
            "estimator",
            "randomization_test",
            "secondary_test",
            "confidence_interval",
            "bootstrap_random_number_algorithm",
            "bootstrap_seed",
            "bootstrap_resamples",
            "confidence_level",
            "alpha",
        ),
        "statistics",
    )
    require_const(
        statistics["estimator"],
        "equal-task-weighted-mean-paired-normalized-score-delta",
        "statistics estimator",
    )
    require_const(
        statistics["randomization_test"],
        "exact-task-blocked-sign-flip",
        "randomization test",
    )
    require_const(
        statistics["secondary_test"],
        "two-sided-exact-mcnemar",
        "secondary test",
    )
    require_const(
        statistics["confidence_interval"],
        "task-stratified-paired-bootstrap",
        "confidence interval",
    )
    require_const(
        statistics["bootstrap_random_number_algorithm"],
        "sha256-counter-prng-v1",
        "bootstrap random number algorithm",
    )
    require_integer(
        statistics["bootstrap_seed"], "bootstrap seed", -(2**63), 2**63 - 1
    )
    require_integer(
        statistics["bootstrap_resamples"], "bootstrap resamples", 10000, 1000000
    )
    require_const(statistics["confidence_level"], 0.95, "confidence level")
    require_const(statistics["alpha"], 0.05, "statistics alpha")

    exclusions = exact_keys(
        study["exclusions"],
        ("infrastructure_failure", "agent_failure", "missing_arm", "reruns"),
        "exclusions",
    )
    require_const(
        exclusions["infrastructure_failure"],
        "invalidate-complete-pair-and-publish",
        "infrastructure failure policy",
    )
    require_const(
        exclusions["agent_failure"],
        "score-as-observed-no-exclusion",
        "agent failure policy",
    )
    require_const(
        exclusions["missing_arm"],
        "invalidate-complete-pair-and-publish",
        "missing arm policy",
    )
    require_const(
        exclusions["reruns"],
        "no-silent-reruns-publish-every-attempt",
        "rerun policy",
    )

    stopping = exact_keys(
        study["stopping"],
        ("minimum_valid_pairs", "maximum_planned_pairs", "rule"),
        "stopping",
    )
    require_integer(stopping["minimum_valid_pairs"], "minimum valid pairs", 1, 1000000)
    require_integer(
        stopping["maximum_planned_pairs"], "maximum planned pairs", 1, 1000000
    )
    if stopping["minimum_valid_pairs"] > stopping["maximum_planned_pairs"]:
        die("minimum valid pairs cannot exceed maximum planned pairs")
    require_const(
        stopping["rule"],
        "run-all-preregistered-pairs-no-optional-stopping",
        "stopping rule",
    )

    publication = exact_keys(
        study["publication"],
        (
            "publish_preregistration_before_first_session",
            "publish_assignment_reveal_after_scoring",
            "publish_all_attempts",
            "publish_invalid_pairs",
            "raw_artifacts",
        ),
        "publication",
    )
    require_const(
        publication["publish_preregistration_before_first_session"],
        True,
        "pre-run publication",
    )
    require_const(
        publication["publish_assignment_reveal_after_scoring"],
        True,
        "assignment reveal publication",
    )
    require_const(publication["publish_all_attempts"], True, "attempt publication")
    require_const(publication["publish_invalid_pairs"], True, "invalid pair publication")
    require_const(
        publication["raw_artifacts"], "private-hash-bound", "raw artifact policy"
    )
    return study


def validate_checksum_sidecar(sidecar: Path, archive: Path) -> None:
    payload = read_bytes(sidecar, "MAINFRAME checksum sidecar", maximum_bytes=4096)
    try:
        text = payload.decode("ascii")
    except UnicodeDecodeError as error:
        die("MAINFRAME checksum sidecar must be ASCII: {}".format(error))
    match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9][A-Za-z0-9._+-]*)\n?", text)
    if match is None:
        die("MAINFRAME checksum sidecar must contain exactly one canonical record")
    if match.group(2) != archive.name:
        die("MAINFRAME checksum sidecar names a different archive")
    if match.group(1) != sha256_file(archive, "MAINFRAME archive"):
        die("MAINFRAME checksum sidecar does not match the archive")


def validate_policy_contract(path: Path, role: str) -> Dict[str, Any]:
    expected = POLICY_CONTRACTS[role]
    contract = exact_keys(
        load_json(path, "{} contract".format(role)),
        ("schema_version", "kind", "id", "controls"),
        "{} contract".format(role),
    )
    require_const(
        contract["schema_version"], 1, "{} contract schema version".format(role)
    )
    require_const(contract["kind"], expected["kind"], "{} contract kind".format(role))
    contract_id = require_string(contract["id"], "{} contract id".format(role), ID_RE)
    controls = exact_keys(
        contract["controls"], expected["controls"].keys(), "{} controls".format(role)
    )
    if controls != expected["controls"]:
        die("{} controls do not match the required live-study contract".format(role))
    return {
        "schema_version": 1,
        "kind": expected["kind"],
        "contract_id": contract_id,
        "controls": controls,
    }


def input_bindings(
    study_path: Path, study: Dict[str, Any], study_payload: bytes
) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    study_root = require_real_directory(study_path.parent, "study root")
    reject_extended_attributes(study_path, "live study")
    suite_relative = safe_relative_path(study["suite"], "live study.suite")
    suite_path = resolve_confined(study_root, suite_relative, "live study suite")
    corpus = load_corpus(suite_path, suite_relative.as_posix())

    runner = study["planned_runner"]
    executable_relative = safe_relative_path(runner["executable"], "runner executable")
    manifest_relative = safe_relative_path(runner["manifest"], "runner manifest")
    executable = resolve_confined(
        study_root, executable_relative, "planned runner executable", executable=True
    )
    manifest = resolve_confined(
        study_root, manifest_relative, "planned runner manifest", maximum_bytes=MAX_JSON_BYTES
    )
    reject_extended_attributes(executable, "planned runner executable")
    reject_extended_attributes(manifest, "planned runner manifest")
    manifest_value = exact_keys(
        load_json(manifest, "planned runner manifest"),
        (
            "schema_version",
            "kind",
            "runner_id",
            "runner_version",
            "adapter",
            "permitted_environment_names",
        ),
        "planned runner manifest",
    )
    require_const(manifest_value["schema_version"], 1, "runner manifest schema version")
    require_const(
        manifest_value["kind"],
        "mainframe-agent-impact-live-runner-manifest",
        "runner manifest kind",
    )
    runner_id = require_string(manifest_value["runner_id"], "runner id", ID_RE)
    runner_version = require_string(
        manifest_value["runner_version"], "runner version", PROVIDER_RE
    )
    adapter = exact_keys(
        manifest_value["adapter"],
        (
            "id",
            "version",
            "provider",
            "executable",
            "request_schema",
            "result_schema",
        ),
        "provider adapter manifest",
    )
    adapter_id = require_string(adapter["id"], "adapter id", ID_RE)
    adapter_version = require_string(adapter["version"], "adapter version", PROVIDER_RE)
    require_const(adapter["provider"], study["provider"]["name"], "adapter provider")
    adapter_executable_relative = safe_relative_path(
        adapter["executable"], "adapter executable"
    )
    adapter_request_schema_relative = safe_relative_path(
        adapter["request_schema"], "adapter request schema"
    )
    adapter_result_schema_relative = safe_relative_path(
        adapter["result_schema"], "adapter result schema"
    )
    adapter_executable = resolve_confined(
        study_root,
        adapter_executable_relative,
        "adapter executable",
        executable=True,
    )
    adapter_request_schema = resolve_confined(
        study_root,
        adapter_request_schema_relative,
        "adapter request schema",
        maximum_bytes=MAX_JSON_BYTES,
    )
    adapter_result_schema = resolve_confined(
        study_root,
        adapter_result_schema_relative,
        "adapter result schema",
        maximum_bytes=MAX_JSON_BYTES,
    )
    reject_extended_attributes(adapter_executable, "adapter executable")
    reject_extended_attributes(adapter_request_schema, "adapter request schema")
    reject_extended_attributes(adapter_result_schema, "adapter result schema")
    for schema_path, schema_label in (
        (adapter_request_schema, "adapter request schema"),
        (adapter_result_schema, "adapter result schema"),
    ):
        if not isinstance(load_json(schema_path, schema_label), dict):
            die("{} must be a JSON object".format(schema_label))
    permitted_environment_names = manifest_value["permitted_environment_names"]
    if (
        not isinstance(permitted_environment_names, list)
        or not permitted_environment_names
        or len(permitted_environment_names) > 64
        or any(not isinstance(name, str) for name in permitted_environment_names)
    ):
        die("permitted environment names must be a non-empty array of at most 64 names")
    if permitted_environment_names != sorted(set(permitted_environment_names)):
        die("permitted environment names must be sorted and unique")
    for name in permitted_environment_names:
        if re.fullmatch(r"[A-Z][A-Z0-9_]{0,63}", name) is None:
            die("permitted environment name is invalid: {!r}".format(name))
        if re.search(r"(?:AUTH|CREDENTIAL|KEY|PASSWORD|SECRET|TOKEN)", name):
            die("credential-like environment names cannot enter an agent: {!r}".format(name))

    release = study["mainframe_release"]
    archive_relative = safe_relative_path(release["archive"], "MAINFRAME archive")
    sidecar_relative = safe_relative_path(
        release["checksum_sidecar"], "MAINFRAME checksum sidecar"
    )
    archive = resolve_confined(
        study_root, archive_relative, "MAINFRAME archive", maximum_bytes=None
    )
    sidecar = resolve_confined(
        study_root, sidecar_relative, "MAINFRAME checksum sidecar", maximum_bytes=4096
    )
    reject_extended_attributes(archive, "MAINFRAME archive")
    reject_extended_attributes(sidecar, "MAINFRAME checksum sidecar")
    validate_checksum_sidecar(sidecar, archive)

    isolation_policy_relative = safe_relative_path(
        study["isolation_policy"], "isolation policy"
    )
    provider_proxy_policy_relative = safe_relative_path(
        study["provider_proxy_policy"], "provider proxy policy"
    )
    isolation_policy = resolve_confined(
        study_root,
        isolation_policy_relative,
        "isolation policy",
        maximum_bytes=MAX_JSON_BYTES,
    )
    provider_proxy_policy = resolve_confined(
        study_root,
        provider_proxy_policy_relative,
        "provider proxy policy",
        maximum_bytes=MAX_JSON_BYTES,
    )
    awm_contract_relative = safe_relative_path(
        study["awm_mechanism_contract"], "AWM mechanism contract"
    )
    awm_contract = resolve_confined(
        study_root,
        awm_contract_relative,
        "AWM mechanism contract",
        maximum_bytes=MAX_JSON_BYTES,
    )
    reject_extended_attributes(isolation_policy, "isolation policy")
    reject_extended_attributes(provider_proxy_policy, "provider proxy policy")
    reject_extended_attributes(awm_contract, "AWM mechanism contract")
    policy_contracts = {
        "isolation": validate_policy_contract(isolation_policy, "isolation"),
        "provider_proxy": validate_policy_contract(
            provider_proxy_policy, "provider_proxy"
        ),
        "awm_mechanism_contract": validate_policy_contract(
            awm_contract, "awm_mechanism_contract"
        ),
    }

    protocol_bindings: List[Dict[str, str]] = []
    for path, relative_name in (
        (Path(__file__), "scripts/dev/agent-impact-preregister.py"),
        (PROTOCOL_ROOT / "live-study.schema.json", "evals/agent-impact/live-study.schema.json"),
        (
            PROTOCOL_ROOT / "preregistration.schema.json",
            "evals/agent-impact/preregistration.schema.json",
        ),
        (
            PROJECT_ROOT / "docs" / "AGENT_IMPACT_LIVE_STUDY.md",
            "docs/AGENT_IMPACT_LIVE_STUDY.md",
        ),
    ):
        path = require_regular_file(path, "preregistration protocol input")
        reject_extended_attributes(path, "preregistration protocol input")
        protocol_bindings.append(
            {
                "path": relative_name,
                "mode": mode_text(path),
                "sha256": sha256_file(path),
            }
        )
    protocol_bindings.sort(key=lambda item: item["path"])

    bindings = {
        "study_spec": {
            "path": study_path.name,
            "mode": mode_text(study_path),
            "sha256": sha256_bytes(study_payload),
        },
        "corpus": corpus["binding"],
        "planned_runner": {
            "runner_id": runner_id,
            "runner_version": runner_version,
            "executable_path": executable_relative.as_posix(),
            "executable_mode": mode_text(executable),
            "executable_sha256": sha256_file(executable),
            "manifest_path": manifest_relative.as_posix(),
            "manifest_mode": mode_text(manifest),
            "manifest_sha256": sha256_file(manifest),
            "adapter": {
                "id": adapter_id,
                "version": adapter_version,
                "provider": adapter["provider"],
                "executable_path": adapter_executable_relative.as_posix(),
                "executable_mode": mode_text(adapter_executable),
                "executable_sha256": sha256_file(adapter_executable),
                "request_schema_path": adapter_request_schema_relative.as_posix(),
                "request_schema_mode": mode_text(adapter_request_schema),
                "request_schema_sha256": sha256_file(adapter_request_schema),
                "result_schema_path": adapter_result_schema_relative.as_posix(),
                "result_schema_mode": mode_text(adapter_result_schema),
                "result_schema_sha256": sha256_file(adapter_result_schema),
            },
            "permitted_environment_names": permitted_environment_names,
        },
        "mainframe_release": {
            "archive_path": archive_relative.as_posix(),
            "archive_mode": mode_text(archive),
            "archive_sha256": sha256_file(archive),
            "checksum_sidecar_path": sidecar_relative.as_posix(),
            "checksum_sidecar_mode": mode_text(sidecar),
            "checksum_sidecar_sha256": sha256_file(sidecar),
            "installed_tree_algorithm": release["installed_tree_algorithm"],
            "installed_tree_sha256": release["installed_tree_sha256"],
        },
        "policies": {
            "isolation": {
                "path": isolation_policy_relative.as_posix(),
                "mode": mode_text(isolation_policy),
                "sha256": sha256_file(isolation_policy),
                **policy_contracts["isolation"],
            },
            "provider_proxy": {
                "path": provider_proxy_policy_relative.as_posix(),
                "mode": mode_text(provider_proxy_policy),
                "sha256": sha256_file(provider_proxy_policy),
                **policy_contracts["provider_proxy"],
            },
            "awm_mechanism_contract": {
                "path": awm_contract_relative.as_posix(),
                "mode": mode_text(awm_contract),
                "sha256": sha256_file(awm_contract),
                **policy_contracts["awm_mechanism_contract"],
            },
        },
        "preregistration_protocol": protocol_bindings,
    }
    return bindings, corpus


def validate_cross_bindings(
    study: Dict[str, Any], corpus: Dict[str, Any]
) -> None:
    budgets = study["budgets"]
    for task in corpus["tasks"]:
        if task["wall_seconds_per_phase"] != float(budgets["wall_seconds_per_phase"]):
            die("study wall budget must exactly match every v1 task")
        if task["maximum_tool_calls_per_phase"] != budgets["maximum_tool_calls_per_phase"]:
            die("study tool budget must exactly match every v1 task")
        if task["maximum_context_bytes"] != budgets["maximum_context_bytes"]:
            die("study context budget must exactly match every v1 task")
    planned_pairs = len(corpus["tasks"]) * study["replicates_per_task"]
    if study["stopping"]["maximum_planned_pairs"] != planned_pairs:
        die("maximum planned pairs must equal task count times replicates per task")
    if study["stopping"]["minimum_valid_pairs"] != planned_pairs:
        die("minimum valid pairs must equal all planned pairs")


def load_seed_file(seed_path: Path) -> bytes:
    seed_path = require_regular_file(
        seed_path, "assignment seed file", maximum_bytes=MAX_SEED_BYTES
    )
    if stat.S_IMODE(seed_path.lstat().st_mode) != 0o600:
        die("assignment seed file mode must be exactly 0600")
    secret = read_bytes(seed_path, "assignment seed file", maximum_bytes=MAX_SEED_BYTES)
    if len(secret) < 16 or len(secret) > MAX_SEED_BYTES:
        die("assignment seed file must contain 16 to {} bytes".format(MAX_SEED_BYTES))
    return secret


def derive_hex(secret: bytes, context: str, purpose: str, length: int = 64) -> str:
    message = "mainframe-agent-impact-live-v2|{}|{}".format(context, purpose).encode(
        "utf-8"
    )
    return hmac.new(secret, message, hashlib.sha256).hexdigest()[:length]


def build_artifacts(
    study_path: Path, secret: bytes
) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    study_path = require_regular_file(study_path, "live study", maximum_bytes=MAX_JSON_BYTES)
    study_value, study_payload = load_json_with_bytes(study_path, "live study")
    study = validate_study(study_value)
    bindings, corpus = input_bindings(study_path, study, study_payload)
    validate_cross_bindings(study, corpus)
    randomization_context_sha256 = sha256_bytes(
        canonical_bytes(
            {
                "domain": "mainframe-agent-impact-live-v2-randomization-context",
                "study_id": study["id"],
                "bindings": bindings,
            }
        )
    )
    context = randomization_context_sha256

    public_pairs: List[Dict[str, Any]] = []
    private_mappings: List[Dict[str, Any]] = []
    seen_ids = set()
    replicates = study["replicates_per_task"]
    control_first_by_task: Dict[str, set] = {}
    for task in corpus["tasks"]:
        task_id = task["id"]
        ranked_replicates = sorted(
            range(1, replicates + 1),
            key=lambda replicate: derive_hex(
                secret, context, "balance|{}|{}".format(task_id, replicate)
            ),
        )
        control_first_by_task[task_id] = set(ranked_replicates[: replicates // 2])

    # Round-robin pairs by replicate so a provider drift cannot align with one
    # task block. Assignment direction remains exactly balanced within each task.
    for replicate in range(1, replicates + 1):
        for task in corpus["tasks"]:
            task_id = task["id"]
            pair_id = "pair-{}".format(
                derive_hex(secret, context, "pair|{}|{}".format(task_id, replicate), 16)
            )
            arm_ids = [
                "arm-{}".format(
                    derive_hex(
                        secret,
                        context,
                        "arm|{}|{}|{}".format(task_id, replicate, arm_index),
                        16,
                    )
                )
                for arm_index in (0, 1)
            ]
            if pair_id in seen_ids or any(arm_id in seen_ids for arm_id in arm_ids):
                die("deterministic identifier collision")
            seen_ids.add(pair_id)
            seen_ids.update(arm_ids)
            modes = (
                ["control", "treatment"]
                if replicate in control_first_by_task[task_id]
                else ["treatment", "control"]
            )
            instance_sha256 = sha256_bytes(
                canonical_bytes(
                    {
                        "task_bundle_sha256": task["binding"]["task_bundle_sha256"],
                        "replicate": replicate,
                    }
                )
            )
            public_pairs.append(
                {
                    "pair_id": pair_id,
                    "task_id": task_id,
                    "replicate": replicate,
                    "instance_sha256": instance_sha256,
                    "opaque_arm_order": arm_ids,
                    "budgets": study["budgets"],
                }
            )
            private_mappings.append(
                {
                    "pair_id": pair_id,
                    "task_id": task_id,
                    "replicate": replicate,
                    "arms": [
                        {"opaque_arm_id": arm_ids[index], "mode": modes[index]}
                        for index in (0, 1)
                    ],
                }
            )

    seed_commitment = sha256_bytes(
        b"mainframe-agent-impact-live-v2-seed\0"
        + randomization_context_sha256.encode("ascii")
        + b"\0"
        + secret
    )
    assignments = {
        "schema_version": 2,
        "kind": "mainframe-agent-impact-live-assignments",
        "study_id": study["id"],
        "study_spec_sha256": bindings["study_spec"]["sha256"],
        "corpus_sha256": bindings["corpus"]["corpus_sha256"],
        "randomization_context_sha256": randomization_context_sha256,
        "seed_commitment_sha256": seed_commitment,
        "assignments": private_mappings,
    }
    assignment_commitment = sha256_bytes(canonical_bytes(assignments))
    preregistration = {
        "schema_version": 2,
        "kind": "mainframe-agent-impact-preregistration",
        "study_id": study["id"],
        "title": study["title"],
        "claim_scope": CLAIM_SCOPE,
        "execution_status": "not-run",
        "non_claims": {
            "real_provider_inference": "not-run",
            "agent_quality": "not-measured",
            "developer_productivity": "not-measured",
            "safety_improvement": "not-measured",
            "live_agent_sessions": 0,
        },
        "design": {
            "hypothesis": HYPOTHESIS,
            "stage": study["stage"],
            "task_classes": study["task_classes"],
            "replicates_per_task": study["replicates_per_task"],
            "container_image_digest": study["container_image_digest"],
            "host_environment": study["host_environment"],
            "provider": study["provider"],
            "budgets": study["budgets"],
            "endpoint": study["endpoint"],
            "statistics": study["statistics"],
            "exclusions": study["exclusions"],
            "stopping": study["stopping"],
            "publication": study["publication"],
        },
        "bindings": bindings,
        "randomization_context_sha256": randomization_context_sha256,
        "seed_commitment_sha256": seed_commitment,
        "assignment_commitment_sha256": assignment_commitment,
        "planned_pair_count": len(public_pairs),
        "pairs": public_pairs,
    }
    return preregistration, assignments


def require_output_absent(path: Path, label: str) -> None:
    parent = require_real_directory(path.parent, "{} parent".format(label))
    target = parent / path.name
    if target.exists() or target.is_symlink():
        die("refusing to overwrite existing {}: {}".format(label, target))


def atomic_json(path: Path, value: Any, mode: int, label: str) -> None:
    parent = require_real_directory(path.parent, "{} parent".format(label))
    target = parent / path.name
    if target.exists() or target.is_symlink():
        die("refusing to overwrite existing {}: {}".format(label, target))
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".{}.tmp.".format(path.name), dir=str(parent)
    )
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "wb") as handle:
            descriptor = -1
            handle.write(canonical_bytes(value) + b"\n")
            handle.flush()
            os.fsync(handle.fileno())
        try:
            os.link(str(temporary), str(target))
        except FileExistsError:
            die("refusing to overwrite existing {}: {}".format(label, target))
        os.chmod(str(target), mode)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def validate_preregistration_envelope(value: Any) -> None:
    preregistration = exact_keys(
        value,
        (
            "schema_version",
            "kind",
            "study_id",
            "title",
            "claim_scope",
            "execution_status",
            "non_claims",
            "design",
            "bindings",
            "randomization_context_sha256",
            "seed_commitment_sha256",
            "assignment_commitment_sha256",
            "planned_pair_count",
            "pairs",
        ),
        "preregistration",
    )
    require_const(preregistration["schema_version"], 2, "preregistration schema version")
    require_const(
        preregistration["kind"],
        "mainframe-agent-impact-preregistration",
        "preregistration kind",
    )
    require_const(preregistration["claim_scope"], CLAIM_SCOPE, "claim scope")
    require_const(preregistration["execution_status"], "not-run", "execution status")
    require_string(
        preregistration["randomization_context_sha256"],
        "randomization context digest",
        SHA256_RE,
    )
    non_claims = exact_keys(
        preregistration["non_claims"],
        (
            "real_provider_inference",
            "agent_quality",
            "developer_productivity",
            "safety_improvement",
            "live_agent_sessions",
        ),
        "non-claims",
    )
    require_const(non_claims["real_provider_inference"], "not-run", "provider non-claim")
    require_const(non_claims["agent_quality"], "not-measured", "quality non-claim")
    require_const(
        non_claims["developer_productivity"], "not-measured", "productivity non-claim"
    )
    require_const(
        non_claims["safety_improvement"], "not-measured", "safety non-claim"
    )
    require_const(non_claims["live_agent_sessions"], 0, "live agent sessions")
    design = exact_keys(
        preregistration["design"],
        (
            "hypothesis",
            "stage",
            "task_classes",
            "replicates_per_task",
            "container_image_digest",
            "host_environment",
            "provider",
            "budgets",
            "endpoint",
            "statistics",
            "exclusions",
            "stopping",
            "publication",
        ),
        "preregistration design",
    )
    require_const(design["hypothesis"], HYPOTHESIS, "preregistration hypothesis")
    stage = design["stage"]
    replicates = design["replicates_per_task"]
    if stage == "pilot" and replicates == 6:
        expected_pair_count = 18
    elif stage == "confirmatory" and replicates == 12:
        expected_pair_count = 36
    elif stage == "confirmatory" and replicates == 20:
        expected_pair_count = 60
    else:
        die("preregistration stage and replicate count are inconsistent")
    require_const(
        preregistration["planned_pair_count"],
        expected_pair_count,
        "planned pair count",
    )
    if not isinstance(preregistration["pairs"], list) or len(
        preregistration["pairs"]
    ) != expected_pair_count:
        die("preregistration pair rows do not cover every planned pair")
    stopping = exact_keys(
        design["stopping"],
        ("minimum_valid_pairs", "maximum_planned_pairs", "rule"),
        "preregistration stopping",
    )
    require_const(
        stopping["minimum_valid_pairs"], expected_pair_count, "minimum valid pairs"
    )
    require_const(
        stopping["maximum_planned_pairs"], expected_pair_count, "maximum planned pairs"
    )


def validate_assignments_envelope(value: Any) -> None:
    assignments = exact_keys(
        value,
        (
            "schema_version",
            "kind",
            "study_id",
            "study_spec_sha256",
            "corpus_sha256",
            "randomization_context_sha256",
            "seed_commitment_sha256",
            "assignments",
        ),
        "private assignments",
    )
    require_const(assignments["schema_version"], 2, "assignment schema version")
    require_const(
        assignments["kind"],
        "mainframe-agent-impact-live-assignments",
        "assignment kind",
    )
    require_string(
        assignments["randomization_context_sha256"],
        "assignment randomization context digest",
        SHA256_RE,
    )
    if not isinstance(assignments["assignments"], list) or not assignments["assignments"]:
        die("private assignments must contain at least one assignment")


def file_mode(path: Path) -> int:
    return stat.S_IMODE(path.lstat().st_mode)


def prepare(args: argparse.Namespace) -> None:
    study_path = Path(args.study)
    output = Path(args.output)
    assignments_output = Path(args.assignments_output)
    if output.absolute() == assignments_output.absolute():
        die("public and private output paths must differ")
    secret = load_seed_file(Path(args.seed_file))
    preregistration, assignments = build_artifacts(study_path, secret)
    require_output_absent(output, "preregistration output")
    require_output_absent(assignments_output, "private assignments output")
    atomic_json(assignments_output, assignments, 0o600, "private assignments output")
    atomic_json(output, preregistration, 0o644, "preregistration output")
    print(
        json.dumps(
            {
                "assignment_commitment_sha256": preregistration[
                    "assignment_commitment_sha256"
                ],
                "claim_scope": CLAIM_SCOPE,
                "live_agent_sessions": 0,
                "status": "prepared-not-run",
            },
            sort_keys=True,
            separators=(",", ":"),
        )
    )


def verify(args: argparse.Namespace) -> None:
    preregistration_path = require_regular_file(
        Path(args.preregistration), "preregistration", maximum_bytes=MAX_JSON_BYTES
    )
    assignments_path = require_regular_file(
        Path(args.assignments), "private assignments", maximum_bytes=MAX_JSON_BYTES
    )
    if file_mode(preregistration_path) != 0o644:
        die("preregistration mode must be exactly 0644")
    if file_mode(assignments_path) != 0o600:
        die("private assignments mode must be exactly 0600")
    observed_preregistration, preregistration_payload = load_json_with_bytes(
        preregistration_path, "preregistration"
    )
    observed_assignments, assignments_payload = load_json_with_bytes(
        assignments_path, "private assignments"
    )
    validate_preregistration_envelope(observed_preregistration)
    validate_assignments_envelope(observed_assignments)

    expected_preregistration, expected_assignments = build_artifacts(
        Path(args.study), load_seed_file(Path(args.seed_file))
    )
    # JSON Schema fixes local shape and stage-conditioned pair counts. The
    # authoritative cross-item invariant (paths, modes, digests, commitments,
    # pair rows, and private reveal) is exact reproduction from bound inputs.
    if assignments_payload != canonical_bytes(expected_assignments) + b"\n":
        die("private assignments do not exactly reproduce from the study and seed")
    if preregistration_payload != canonical_bytes(expected_preregistration) + b"\n":
        die("preregistration does not exactly reproduce from the bound inputs")
    print(
        json.dumps(
            {
                "assignment_commitment_sha256": expected_preregistration[
                    "assignment_commitment_sha256"
                ],
                "claim_scope": CLAIM_SCOPE,
                "live_agent_sessions": 0,
                "status": "verified-not-run",
            },
            sort_keys=True,
            separators=(",", ":"),
        )
    )


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Prepare or verify a no-run MAINFRAME live-study preregistration."
    )
    subparsers = result.add_subparsers(dest="action", required=True)
    prepare_parser = subparsers.add_parser("prepare")
    prepare_parser.add_argument("--study", required=True)
    prepare_parser.add_argument("--seed-file", required=True)
    prepare_parser.add_argument("--output", required=True)
    prepare_parser.add_argument("--assignments-output", required=True)
    prepare_parser.set_defaults(function=prepare)

    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("--study", required=True)
    verify_parser.add_argument("--seed-file", required=True)
    verify_parser.add_argument("--preregistration", required=True)
    verify_parser.add_argument("--assignments", required=True)
    verify_parser.set_defaults(function=verify)
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        args.function(args)
    except ProtocolError as error:
        print("agent-impact-preregister: {}".format(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

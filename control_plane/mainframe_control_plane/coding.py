"""Fixed, reviewed coding-agent contracts and a workspace-safe executor.

This module deliberately exposes no command, argv, environment, executable, policy
outcome, durable identity, or Evidence input.  Hosts inject one trusted fixed-action
runner at construction time; untrusted invocation input is limited to a reviewed
tool ID and its closed JSON object.
"""

from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timedelta
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import threading
import time
from typing import Any, Callable, Dict, Iterator, List, Mapping, Optional, Tuple, Union, cast
import uuid

from .errors import (
    AlreadyExists,
    BindingMismatch,
    ExecutionDenied,
    ExecutorUnavailable,
    InvalidTransition,
    ValidationError,
)
from .durability import create_directory_durable
from .kernel import (
    Clock,
    ControlPlaneKernel,
    JsonValue,
    PolicyEvaluation,
    PolicyRequest,
    Snapshot,
    normalized_input_digest,
    normalized_input_metadata,
)


CODING_POLICY = "coding-agent-v1"
CODING_READ_FILE = "mainframe.coding.read_file.v1"
CODING_SEARCH_TEXT = "mainframe.coding.search_text.v1"
CODING_ATOMIC_EDIT = "mainframe.coding.atomic_edit.v1"
CODING_RUN_TEST = "mainframe.coding.run_test.v1"
CODING_RUN_BUILD = "mainframe.coding.run_build.v1"
CODING_EXECUTION_EFFECT = "code_execution"

_READ_LIMIT = 1024 * 1024
_SEARCH_SCAN_LIMIT = 8 * 1024 * 1024
_SEARCH_OUTPUT_LIMIT = 1024 * 1024
_ACTION_OUTPUT_LIMIT = 1024 * 1024
_EDIT_CONTENT_LIMIT = 24 * 1024
_PATH_LIMIT = 1024
_QUERY_LIMIT = 4096
_APPROVAL_LIFETIME = timedelta(minutes=5)
_CORRELATION_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")


@dataclass(frozen=True)
class CodingContract:
    tool: str
    effect: str
    timeout_ms: int
    output_limit: int


@dataclass(frozen=True)
class CodingApprovalRequest:
    approval_id: str
    call_id: str
    tool: str
    input_digest: str
    preimage_sha256: Optional[str]
    actor: str
    workspace: str
    policy: str
    expires_at: str


CodingTrustedApprover = Callable[[CodingApprovalRequest], str]


@dataclass(frozen=True)
class CodingExecutionRequest:
    run_id: str
    call_id: str
    decision_id: str
    evidence_id: str
    approval_id: Optional[str]
    approver: Optional[str]
    tool: str
    input_digest: str
    actor: str
    workspace: str
    policy: str


@dataclass(frozen=True)
class CodingExecutionResult:
    outcome: str
    receipt: Dict[str, JsonValue]
    stdout: bytes = b""
    stderr: bytes = b""


CodingExecutor = Callable[
    [CodingExecutionRequest, Mapping[str, JsonValue]], CodingExecutionResult
]


@dataclass(frozen=True)
class FixedActionResult:
    exit_code: int
    stdout: bytes
    stderr: bytes
    duration_ms: int


FixedActionRunner = Callable[[str, int], FixedActionResult]


@dataclass(frozen=True)
class CodingInvocationResult:
    schema_version: int
    status: str
    client_correlation_id: str
    run_id: str
    call_id: str
    decision_id: str
    approval_id: Optional[str]
    evidence_id: Optional[str]
    input_digest: str
    outcome: Optional[str]
    result_available: bool
    receipt: Optional[Dict[str, JsonValue]]
    evidence_body: Dict[str, JsonValue]
    result: Optional[CodingExecutionResult]


class FixedCodingRegistry:
    """In-code closed registry for exactly five reviewed Phase 6 operations."""

    def __init__(self) -> None:
        self.contracts: Dict[str, CodingContract] = {
            CODING_READ_FILE: CodingContract(
                CODING_READ_FILE, "read_only", 5000, _READ_LIMIT
            ),
            CODING_SEARCH_TEXT: CodingContract(
                CODING_SEARCH_TEXT, "read_only", 10000, _SEARCH_OUTPUT_LIMIT
            ),
            CODING_ATOMIC_EDIT: CodingContract(
                CODING_ATOMIC_EDIT, "mutating", 5000, 0
            ),
            CODING_RUN_TEST: CodingContract(
                CODING_RUN_TEST, CODING_EXECUTION_EFFECT, 30000, _ACTION_OUTPUT_LIMIT
            ),
            CODING_RUN_BUILD: CodingContract(
                CODING_RUN_BUILD, CODING_EXECUTION_EFFECT, 30000, _ACTION_OUTPUT_LIMIT
            ),
        }

    def contract(self, tool: str) -> CodingContract:
        if not isinstance(tool, str):
            raise ExecutionDenied("coding tool ID must be a string")
        try:
            return self.contracts[tool]
        except KeyError as exc:
            raise ExecutionDenied("coding tool ID is not reviewed") from exc

    def normalize_input(
        self, tool: str, tool_input: Mapping[str, JsonValue]
    ) -> Dict[str, JsonValue]:
        self.contract(tool)
        if not isinstance(tool_input, dict):
            raise ExecutionDenied("coding tool input must be an object")
        try:
            normalized = json.loads(
                json.dumps(
                    tool_input,
                    allow_nan=False,
                    ensure_ascii=False,
                    separators=(",", ":"),
                    sort_keys=True,
                )
            )
        except (TypeError, ValueError) as exc:
            raise ExecutionDenied("coding tool input is not canonical JSON") from exc
        if not isinstance(normalized, dict):
            raise ExecutionDenied("coding tool input must normalize to an object")
        typed = cast(Dict[str, JsonValue], normalized)
        if tool == CODING_READ_FILE:
            if set(typed) != {"path"}:
                raise ExecutionDenied("read_file input must contain exactly path")
            typed["path"] = _normalize_relative_path(typed["path"])
        elif tool == CODING_SEARCH_TEXT:
            if set(typed) != {"path", "query"}:
                raise ExecutionDenied(
                    "search_text input must contain exactly path and query"
                )
            typed["path"] = _normalize_relative_path(typed["path"])
            query = typed["query"]
            if not isinstance(query, str) or not query or "\x00" in query:
                raise ExecutionDenied("search query must be a non-empty NUL-free string")
            if len(query.encode("utf-8")) > _QUERY_LIMIT:
                raise ExecutionDenied("search query exceeds 4096 UTF-8 bytes")
        elif tool == CODING_ATOMIC_EDIT:
            if set(typed) != {"content", "expected_sha256", "path"}:
                raise ExecutionDenied(
                    "atomic_edit input must contain path, expected_sha256, and content"
                )
            typed["path"] = _normalize_relative_path(typed["path"])
            expected = typed["expected_sha256"]
            if (
                not isinstance(expected, str)
                or len(expected) != 64
                or any(character not in "0123456789abcdef" for character in expected)
            ):
                raise ExecutionDenied("atomic_edit preimage must be lowercase SHA-256")
            content = typed["content"]
            if not isinstance(content, str):
                raise ExecutionDenied("atomic_edit content must be a UTF-8 string")
            try:
                encoded = content.encode("utf-8")
            except UnicodeEncodeError as exc:
                raise ExecutionDenied("atomic_edit content must be valid UTF-8") from exc
            if len(encoded) > _EDIT_CONTENT_LIMIT:
                raise ExecutionDenied("atomic_edit content exceeds 24576 UTF-8 bytes")
        else:
            if typed:
                raise ExecutionDenied("fixed test/build actions accept no input fields")
        if len(_canonical_json(typed)) > 32768:
            raise ExecutionDenied("coding tool input exceeds 32768 UTF-8 bytes")
        return typed


class FixedCodingEvaluator:
    """Non-caller-selectable policy for the exact in-code registry."""

    def __init__(self, registry: FixedCodingRegistry) -> None:
        self._registry = registry

    def __call__(self, request: PolicyRequest) -> PolicyEvaluation:
        authority = "policy-engine:fixed-coding-agent-v1"
        if request.policy != CODING_POLICY:
            return PolicyEvaluation("deny", authority, "coding policy mismatch")
        try:
            contract = self._registry.contract(request.tool)
            normalized = self._registry.normalize_input(request.tool, request.tool_input)
        except ExecutionDenied:
            return PolicyEvaluation("deny", authority, "tool or input is not reviewed")
        if (
            contract.effect != request.effect
            or normalized != request.tool_input
            or request.timeout_at is None
        ):
            return PolicyEvaluation("deny", authority, "request binding is not canonical")
        if contract.effect in ("mutating", CODING_EXECUTION_EFFECT):
            return PolicyEvaluation(
                "approval_required",
                authority,
                "reviewed coding side effect requires exact trusted approval",
            )
        return PolicyEvaluation("allow", authority, "reviewed read-only coding action")


def _canonical_json(value: Any) -> bytes:
    return json.dumps(
        value,
        allow_nan=False,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def _normalize_relative_path(value: JsonValue) -> str:
    if not isinstance(value, str) or not value or "\x00" in value:
        raise ExecutionDenied("workspace path must be a non-empty NUL-free string")
    if os.path.isabs(value):
        raise ExecutionDenied("workspace path must be relative")
    try:
        encoded = value.encode("utf-8")
    except UnicodeEncodeError as exc:
        raise ExecutionDenied("workspace path must be valid UTF-8") from exc
    if len(encoded) > _PATH_LIMIT:
        raise ExecutionDenied("workspace path exceeds 1024 UTF-8 bytes")
    parts = value.split("/")
    if any(part in ("", ".", "..") for part in parts):
        raise ExecutionDenied("workspace path contains an unsafe component")
    if any(len(part.encode("utf-8")) > 255 for part in parts):
        raise ExecutionDenied("workspace path component exceeds 255 UTF-8 bytes")
    return "/".join(parts)


def _directory_flags() -> int:
    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY"):
        raise ExecutorUnavailable("symlink-safe workspace traversal is unavailable")
    return os.O_RDONLY | os.O_CLOEXEC | os.O_DIRECTORY | os.O_NOFOLLOW


def _file_flags() -> int:
    if not hasattr(os, "O_NOFOLLOW"):
        raise ExecutorUnavailable("symlink-safe workspace traversal is unavailable")
    return os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | getattr(os, "O_NONBLOCK", 0)


@contextmanager
def _coding_request_lock(
    ledger_path: Path, client_correlation_id: str
) -> Iterator[None]:
    """Serialize one durable request across processes without storing its values."""
    if _CORRELATION_ID.fullmatch(client_correlation_id) is None:
        raise ValidationError("client_correlation_id is malformed")
    runtime = ledger_path.parent / ".mainframe-control-plane-runtime"
    create_directory_durable(runtime, mode=0o700, parents=False)
    metadata = runtime.lstat()
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or stat.S_ISLNK(metadata.st_mode)
        or metadata.st_uid != os.geteuid()
        or stat.S_IMODE(metadata.st_mode) & 0o077
    ):
        raise ExecutionDenied("coding request lock directory is unsafe")
    name = "coding-lock-{}.lock".format(
        hashlib.sha256(client_correlation_id.encode("utf-8")).hexdigest()
    )
    flags = os.O_RDWR | os.O_CREAT | os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(str(runtime / name), flags, 0o600)
    except OSError as exc:
        raise ExecutionDenied("coding request lock is unavailable") from exc
    try:
        lock_metadata = os.fstat(fd)
        if (
            not stat.S_ISREG(lock_metadata.st_mode)
            or lock_metadata.st_uid != os.geteuid()
            or stat.S_IMODE(lock_metadata.st_mode) & 0o077
            or lock_metadata.st_nlink != 1
        ):
            raise ExecutionDenied("coding request lock is unsafe")
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def _open_workspace(path: str) -> int:
    try:
        fd = os.open(path, _directory_flags())
    except OSError as exc:
        raise ExecutionDenied("workspace is unavailable or symbolic") from exc
    metadata = os.fstat(fd)
    if not stat.S_ISDIR(metadata.st_mode):
        os.close(fd)
        raise ExecutionDenied("workspace is not a directory")
    return fd


def _open_parent(workspace_fd: int, relative_path: str) -> Tuple[int, str]:
    parts = relative_path.split("/")
    current = os.dup(workspace_fd)
    try:
        for component in parts[:-1]:
            next_fd = os.open(component, _directory_flags(), dir_fd=current)
            os.close(current)
            current = next_fd
        return current, parts[-1]
    except OSError as exc:
        os.close(current)
        raise ExecutionDenied("workspace path traverses a symlink or non-directory") from exc


def _open_relative(workspace_fd: int, relative_path: str) -> int:
    parent, name = _open_parent(workspace_fd, relative_path)
    try:
        return os.open(name, _file_flags(), dir_fd=parent)
    except OSError as exc:
        raise ExecutionDenied("workspace target is unavailable or symbolic") from exc
    finally:
        os.close(parent)


def _read_bounded(fd: int, limit: int) -> bytes:
    os.lseek(fd, 0, os.SEEK_SET)
    chunks: List[bytes] = []
    total = 0
    while True:
        chunk = os.read(fd, min(65536, limit + 1 - total))
        if not chunk:
            break
        total += len(chunk)
        if total > limit:
            raise ExecutionDenied("workspace file exceeds the reviewed size limit")
        chunks.append(chunk)
    return b"".join(chunks)


def _read_file(workspace_fd: int, relative_path: str) -> bytes:
    fd = _open_relative(workspace_fd, relative_path)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ExecutionDenied("workspace target must be a regular file")
        return _read_bounded(fd, _READ_LIMIT)
    finally:
        os.close(fd)


def _search_text(workspace_fd: int, relative_path: str, query: str) -> bytes:
    root_fd = _open_relative(workspace_fd, relative_path)
    scanned = 0
    matches: List[Dict[str, JsonValue]] = []

    def search_file(fd: int, display_path: str) -> None:
        nonlocal scanned
        remaining = _SEARCH_SCAN_LIMIT - scanned
        if remaining <= 0:
            raise ExecutionDenied("workspace search scan limit was exceeded")
        content = _read_bounded(fd, min(_READ_LIMIT, remaining))
        scanned += len(content)
        try:
            text = content.decode("utf-8")
        except UnicodeDecodeError:
            return
        for line_number, line in enumerate(text.splitlines(), 1):
            if query in line:
                matches.append(
                    {"line": line_number, "path": display_path, "text": line}
                )
                if len(matches) > 256:
                    raise ExecutionDenied("workspace search match limit was exceeded")

    def walk(directory_fd: int, display_prefix: str, depth: int) -> None:
        if depth > 32:
            raise ExecutionDenied("workspace search depth limit was exceeded")
        try:
            names = sorted(os.listdir(directory_fd))
        except OSError as exc:
            raise ExecutionDenied("workspace search directory is unavailable") from exc
        for name in names:
            try:
                metadata = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            except OSError as exc:
                raise ExecutionDenied("workspace search entry changed during traversal") from exc
            display = "{}/{}".format(display_prefix, name)
            if stat.S_ISLNK(metadata.st_mode):
                continue
            if stat.S_ISDIR(metadata.st_mode):
                child = os.open(name, _directory_flags(), dir_fd=directory_fd)
                try:
                    walk(child, display, depth + 1)
                finally:
                    os.close(child)
            elif stat.S_ISREG(metadata.st_mode):
                child = os.open(name, _file_flags(), dir_fd=directory_fd)
                try:
                    search_file(child, display)
                finally:
                    os.close(child)

    try:
        metadata = os.fstat(root_fd)
        if stat.S_ISREG(metadata.st_mode):
            search_file(root_fd, relative_path)
        elif stat.S_ISDIR(metadata.st_mode):
            walk(root_fd, relative_path, 0)
        else:
            raise ExecutionDenied("workspace search target must be a file or directory")
    finally:
        os.close(root_fd)
    rendered = _canonical_json({"matches": matches}) + b"\n"
    if len(rendered) > _SEARCH_OUTPUT_LIMIT:
        raise ExecutionDenied("workspace search output limit was exceeded")
    return rendered


def _atomic_edit(
    workspace_fd: int, relative_path: str, expected: str, content: bytes
) -> Tuple[str, str]:
    parent_fd, name = _open_parent(workspace_fd, relative_path)
    target_fd = -1
    temporary_fd = -1
    temporary_name = ".mainframe-edit-{}.tmp".format(uuid.uuid4().hex)
    try:
        fcntl.flock(parent_fd, fcntl.LOCK_EX)
        target_fd = os.open(name, _file_flags(), dir_fd=parent_fd)
        metadata = os.fstat(target_fd)
        if not stat.S_ISREG(metadata.st_mode):
            raise ExecutionDenied("atomic_edit target must be a regular file")
        preimage = _read_bounded(target_fd, _READ_LIMIT)
        preimage_digest = hashlib.sha256(preimage).hexdigest()
        if preimage_digest != expected:
            raise BindingMismatch("atomic_edit preimage digest does not match")
        temporary_fd = os.open(
            temporary_name,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC,
            stat.S_IMODE(metadata.st_mode),
            dir_fd=parent_fd,
        )
        offset = 0
        while offset < len(content):
            written = os.write(temporary_fd, content[offset:])
            if written <= 0:
                raise OSError("atomic_edit write made no progress")
            offset += written
        os.fsync(temporary_fd)
        os.close(temporary_fd)
        temporary_fd = -1

        current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        if (
            not stat.S_ISREG(current.st_mode)
            or (current.st_dev, current.st_ino) != (metadata.st_dev, metadata.st_ino)
            or hashlib.sha256(_read_bounded(target_fd, _READ_LIMIT)).hexdigest()
            != expected
        ):
            raise BindingMismatch("atomic_edit target changed before replacement")
        os.replace(
            temporary_name,
            name,
            src_dir_fd=parent_fd,
            dst_dir_fd=parent_fd,
        )
        os.fsync(parent_fd)
        return expected, hashlib.sha256(content).hexdigest()
    except OSError as exc:
        raise ExecutionDenied("atomic_edit could not commit safely") from exc
    finally:
        if temporary_fd >= 0:
            os.close(temporary_fd)
        try:
            os.unlink(temporary_name, dir_fd=parent_fd)
        except FileNotFoundError:
            pass
        if target_fd >= 0:
            os.close(target_fd)
        fcntl.flock(parent_fd, fcntl.LOCK_UN)
        os.close(parent_fd)


class FixedWorkspaceCodingExecutor:
    """Workspace-safe Python executor plus an injected fixed test/build seam."""

    def __init__(self, *, action_runner: Optional[FixedActionRunner] = None) -> None:
        self._registry = FixedCodingRegistry()
        self._action_runner = action_runner

    def __call__(
        self,
        request: CodingExecutionRequest,
        tool_input: Mapping[str, JsonValue],
    ) -> CodingExecutionResult:
        contract = self._registry.contract(request.tool)
        normalized = self._registry.normalize_input(request.tool, tool_input)
        if normalized_input_digest(normalized) != request.input_digest:
            raise BindingMismatch("executor input does not match its bound request")
        workspace_fd = _open_workspace(request.workspace)
        started = time.monotonic()
        stdout = b""
        stderr = b""
        exit_code = 0
        preimage: Optional[str] = None
        postimage: Optional[str] = None
        try:
            if request.tool == CODING_READ_FILE:
                stdout = _read_file(workspace_fd, cast(str, normalized["path"]))
            elif request.tool == CODING_SEARCH_TEXT:
                stdout = _search_text(
                    workspace_fd,
                    cast(str, normalized["path"]),
                    cast(str, normalized["query"]),
                )
            elif request.tool == CODING_ATOMIC_EDIT:
                if request.approval_id is None or request.approver is None:
                    raise ExecutionDenied("atomic_edit lacks a trusted approval binding")
                preimage, postimage = _atomic_edit(
                    workspace_fd,
                    cast(str, normalized["path"]),
                    cast(str, normalized["expected_sha256"]),
                    cast(str, normalized["content"]).encode("utf-8"),
                )
            else:
                if request.approval_id is None or request.approver is None:
                    raise ExecutionDenied(
                        "fixed test/build action lacks a trusted approval binding"
                    )
                if self._action_runner is None:
                    raise ExecutorUnavailable("fixed test/build runner is unavailable")
                # The runner receives the already validated directory handle, not
                # a path it could re-resolve after a workspace rename/symlink race.
                action = self._action_runner(request.tool, workspace_fd)
                if not isinstance(action, FixedActionResult):
                    raise ValidationError("fixed action runner returned an invalid type")
                if (
                    type(action.exit_code) is not int
                    or not 0 <= action.exit_code <= 255
                    or type(action.duration_ms) is not int
                    or not 0 <= action.duration_ms <= contract.timeout_ms
                    or not isinstance(action.stdout, bytes)
                    or not isinstance(action.stderr, bytes)
                ):
                    raise ValidationError("fixed action result fields are invalid")
                exit_code = action.exit_code
                stdout = action.stdout
                stderr = action.stderr
            if len(stdout) + len(stderr) > contract.output_limit:
                raise ValidationError("coding executor output exceeds its contract limit")
            duration_ms = max(0, int((time.monotonic() - started) * 1000))
            if request.tool in (CODING_RUN_TEST, CODING_RUN_BUILD):
                duration_ms = action.duration_ms
            outcome = "succeeded" if exit_code == 0 else "failed"
            receipt: Dict[str, JsonValue] = {
                "schema_version": 1,
                "run_id": request.run_id,
                "call_id": request.call_id,
                "decision_id": request.decision_id,
                "evidence_id": request.evidence_id,
                "approval_id": request.approval_id,
                "approver": request.approver,
                "tool": request.tool,
                "input_digest": request.input_digest,
                "actor": request.actor,
                "workspace": request.workspace,
                "policy": request.policy,
                "outcome": outcome,
                "exit_code": exit_code,
                "duration_ms": duration_ms,
                "stdout_bytes": len(stdout),
                "stdout_sha256": hashlib.sha256(stdout).hexdigest(),
                "stderr_bytes": len(stderr),
                "stderr_sha256": hashlib.sha256(stderr).hexdigest(),
                "preimage_sha256": preimage,
                "postimage_sha256": postimage,
            }
            return CodingExecutionResult(outcome, receipt, stdout, stderr)
        finally:
            os.close(workspace_fd)


_RECEIPT_KEYS = frozenset(
    (
        "schema_version",
        "run_id",
        "call_id",
        "decision_id",
        "evidence_id",
        "approval_id",
        "approver",
        "tool",
        "input_digest",
        "actor",
        "workspace",
        "policy",
        "outcome",
        "exit_code",
        "duration_ms",
        "stdout_bytes",
        "stdout_sha256",
        "stderr_bytes",
        "stderr_sha256",
        "preimage_sha256",
        "postimage_sha256",
    )
)


def validate_coding_result(
    result: Any,
    request: CodingExecutionRequest,
    contract: CodingContract,
    normalized_input: Mapping[str, JsonValue],
) -> Tuple[str, Dict[str, JsonValue]]:
    if not isinstance(result, CodingExecutionResult):
        raise ValidationError("coding executor returned an unsupported result type")
    if result.outcome not in ("succeeded", "failed"):
        raise ValidationError("coding executor returned an unsupported outcome")
    if not isinstance(result.stdout, bytes) or not isinstance(result.stderr, bytes):
        raise ValidationError("coding executor output must be bytes")
    if len(result.stdout) + len(result.stderr) > contract.output_limit:
        raise ValidationError("coding executor output exceeds its contract limit")
    receipt = result.receipt
    if not isinstance(receipt, dict) or set(receipt) != _RECEIPT_KEYS:
        raise ValidationError("coding executor receipt fields are not exact")
    expected_identity = {
        "schema_version": 1,
        "run_id": request.run_id,
        "call_id": request.call_id,
        "decision_id": request.decision_id,
        "evidence_id": request.evidence_id,
        "approval_id": request.approval_id,
        "approver": request.approver,
        "tool": request.tool,
        "input_digest": request.input_digest,
        "actor": request.actor,
        "workspace": request.workspace,
        "policy": request.policy,
        "outcome": result.outcome,
        "stdout_bytes": len(result.stdout),
        "stdout_sha256": hashlib.sha256(result.stdout).hexdigest(),
        "stderr_bytes": len(result.stderr),
        "stderr_sha256": hashlib.sha256(result.stderr).hexdigest(),
    }
    for key, value in expected_identity.items():
        if receipt.get(key) != value:
            raise BindingMismatch("coding executor receipt identity is invalid")
    exit_code = receipt["exit_code"]
    duration_ms = receipt["duration_ms"]
    if (
        type(exit_code) is not int
        or not 0 <= exit_code <= 255
        or type(duration_ms) is not int
        or not 0 <= duration_ms <= contract.timeout_ms
        or (result.outcome == "succeeded") != (exit_code == 0)
    ):
        raise ValidationError("coding executor receipt status is invalid")
    preimage = receipt["preimage_sha256"]
    postimage = receipt["postimage_sha256"]
    if request.tool == CODING_ATOMIC_EDIT:
        expected_preimage = normalized_input["expected_sha256"]
        content = cast(str, normalized_input["content"]).encode("utf-8")
        if (
            preimage != expected_preimage
            or postimage != hashlib.sha256(content).hexdigest()
            or result.stdout
            or result.stderr
        ):
            raise BindingMismatch("atomic_edit receipt does not match its exact preimage")
    elif preimage is not None or postimage is not None:
        raise BindingMismatch("read-only coding receipt contains edit metadata")
    return result.outcome, dict(receipt)


def validate_durable_coding_receipt(
    receipt: Mapping[str, JsonValue],
    *,
    run_id: str,
    call_id: str,
    decision_id: str,
    evidence_id: str,
    approval_id: Optional[str],
    approver: Optional[str],
    tool: str,
    input_digest: str,
    actor: str,
    workspace: str,
    policy: str,
    outcome: str,
) -> None:
    if not isinstance(receipt, dict) or set(receipt) != _RECEIPT_KEYS:
        raise BindingMismatch("durable coding receipt fields are not exact")
    expected = {
        "schema_version": 1,
        "run_id": run_id,
        "call_id": call_id,
        "decision_id": decision_id,
        "evidence_id": evidence_id,
        "approval_id": approval_id,
        "approver": approver,
        "tool": tool,
        "input_digest": input_digest,
        "actor": actor,
        "workspace": workspace,
        "policy": policy,
        "outcome": outcome,
    }
    if any(receipt.get(key) != value for key, value in expected.items()):
        raise BindingMismatch("durable coding receipt identity does not match Evidence")
    for prefix in ("stdout", "stderr"):
        size = receipt.get(prefix + "_bytes")
        digest = receipt.get(prefix + "_sha256")
        if type(size) is not int or size < 0 or not _is_digest(digest):
            raise ValidationError("durable coding output metadata is invalid")
    if type(receipt.get("duration_ms")) is not int or cast(int, receipt["duration_ms"]) < 0:
        raise ValidationError("durable coding duration is invalid")
    if type(receipt.get("exit_code")) is not int:
        raise ValidationError("durable coding exit code is invalid")
    if tool == CODING_ATOMIC_EDIT:
        if not _is_digest(receipt.get("preimage_sha256")) or not _is_digest(
            receipt.get("postimage_sha256")
        ):
            raise ValidationError("durable edit receipt digests are invalid")
    elif receipt.get("preimage_sha256") is not None or receipt.get("postimage_sha256") is not None:
        raise BindingMismatch("durable read-only receipt contains edit digests")


def _is_digest(value: Any) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


class CodingAgentControlPlane:
    """Atomic host-facing API; authoritative IDs and decisions are generated inside."""

    def __init__(
        self,
        ledger_path: Union[str, os.PathLike[str]],
        *,
        executor: CodingExecutor,
        trusted_approver: Optional[CodingTrustedApprover] = None,
        clock: Optional[Clock] = None,
    ) -> None:
        ledger = Path(ledger_path)
        create_directory_durable(ledger.parent, mode=0o700, parents=True)
        self._registry = FixedCodingRegistry()
        self._clock = clock
        arguments: Dict[str, Any] = {"evaluator": FixedCodingEvaluator(self._registry)}
        if clock is not None:
            arguments["clock"] = clock
        self._kernel = ControlPlaneKernel(ledger, **arguments)
        self._ledger_path = ledger
        self._executor = executor
        self._trusted_approver = trusted_approver
        self._invoke_lock = threading.Lock()

    def snapshot(self) -> Snapshot:
        return self._kernel.snapshot()

    def invoke(
        self,
        *,
        client_correlation_id: str,
        tool: str,
        tool_input: Mapping[str, JsonValue],
        actor: str,
        workspace: str,
        after_start_hook: Optional[Callable[[], None]] = None,
        after_commit_hook: Optional[Callable[[], None]] = None,
    ) -> CodingInvocationResult:
        with self._invoke_lock:
            with _coding_request_lock(self._ledger_path, client_correlation_id):
                return self._invoke_locked(
                    client_correlation_id=client_correlation_id,
                    tool=tool,
                    tool_input=tool_input,
                    actor=actor,
                    workspace=workspace,
                    after_start_hook=after_start_hook,
                    after_commit_hook=after_commit_hook,
                )

    def _invoke_locked(
        self,
        *,
        client_correlation_id: str,
        tool: str,
        tool_input: Mapping[str, JsonValue],
        actor: str,
        workspace: str,
        after_start_hook: Optional[Callable[[], None]],
        after_commit_hook: Optional[Callable[[], None]],
    ) -> CodingInvocationResult:
        normalized = self._registry.normalize_input(tool, tool_input)
        digest = normalized_input_digest(normalized)
        metadata = normalized_input_metadata(normalized)
        if not os.path.isabs(workspace):
            raise ExecutionDenied("coding workspace must be an absolute path")
        canonical_workspace = os.path.realpath(os.path.normpath(workspace))
        snapshot = self._kernel.snapshot()
        request = snapshot.canonical_requests.get(client_correlation_id)
        if request is None:
            try:
                request = self._kernel.reserve_canonical_request(
                    client_correlation_id=client_correlation_id,
                    canonical_id=tool,
                    tool_input=normalized,
                    actor=actor,
                    workspace=canonical_workspace,
                    policy=CODING_POLICY,
                )
            except AlreadyExists:
                request = self._kernel.snapshot().canonical_requests[
                    client_correlation_id
                ]
        if (
            request.canonical_id != tool
            or request.input_digest != digest
            or request.input_metadata != metadata
            or request.actor != actor
            or request.workspace != canonical_workspace
            or request.policy != CODING_POLICY
        ):
            raise BindingMismatch(
                "client correlation is bound to a different coding request"
            )
        snapshot = self._kernel.snapshot()
        run = snapshot.runs.get(request.run_id)
        if run is None:
            self._kernel.create_run(
                run_id=request.run_id,
                actor=request.actor,
                workspace=request.workspace,
                policy=request.policy,
            )
            run = self._kernel.snapshot().runs[request.run_id]
        if run.state == "created":
            self._kernel.transition_run(run.run_id, "active")
        snapshot = self._kernel.snapshot()
        call = snapshot.tool_calls.get(request.call_id)
        if call is None:
            call = self._kernel._create_coding_tool_call(
                call_id=request.call_id,
                run_id=request.run_id,
                tool=tool,
                tool_input=normalized,
                client_correlation_id=client_correlation_id,
            )
        if call.state == "running":
            self._kernel._recover_coding_execution(call.call_id)
            self._close_run(call.run_id, False)
            return self._result(request.call_id, None)
        if call.state in ("succeeded", "failed", "interrupted", "timed_out"):
            self._close_run(call.run_id, call.state == "succeeded")
            return self._result(call.call_id, None)
        snapshot = self._kernel.snapshot()
        decisions = [
            decision
            for decision in snapshot.policy_decisions.values()
            if decision.call_id == call.call_id
        ]
        if not decisions:
            self._kernel.evaluate_policy_decision(
                decision_id=request.decision_id,
                call_id=call.call_id,
                tool=call.tool,
                input_digest=call.input_digest,
                actor=call.actor,
                workspace=call.workspace,
                policy=call.policy,
                timeout_at=call.timeout_at,
                tool_input=normalized,
            )
        snapshot = self._kernel.snapshot()
        call = snapshot.tool_calls[call.call_id]
        decision = snapshot.policy_decisions[request.decision_id]
        if decision.outcome == "deny":
            self._close_run(call.run_id, False)
            return self._result(call.call_id, None)
        approval_id: Optional[str] = None
        if call.effect in ("mutating", CODING_EXECUTION_EFFECT):
            approvals = [
                approval
                for approval in snapshot.approvals.values()
                if approval.call_id == call.call_id
            ]
            if approvals:
                if len(approvals) != 1:
                    raise InvalidTransition("coding approval is not unique")
                approval_id = approvals[0].approval_id
            else:
                if self._trusted_approver is None:
                    return self._in_progress(call.call_id, "awaiting_approval")
                # The call ID is kernel-generated in the first reservation.  A
                # deterministic derivative keeps authority requests stable if the
                # coordinator dies after review but before the grant append.
                approval_id = "approval-{}".format(
                    hashlib.sha256(call.call_id.encode("utf-8")).hexdigest()[:32]
                )
                now = self._clock() if self._clock is not None else datetime.now().astimezone()
                expires_at = now + _APPROVAL_LIFETIME
                base = self._kernel.bind_approval_grant_request(
                    approval_id=approval_id,
                    call_id=call.call_id,
                    tool=call.tool,
                    input_digest=call.input_digest,
                    actor=call.actor,
                    workspace=call.workspace,
                    policy=call.policy,
                    expires_at=expires_at,
                )
                approver = self._trusted_approver(
                    CodingApprovalRequest(
                        base.approval_id,
                        base.call_id,
                        base.tool,
                        base.input_digest,
                        cast(
                            Optional[str],
                            normalized.get("expected_sha256"),
                        ),
                        base.actor,
                        base.workspace,
                        base.policy,
                        base.expires_at,
                    )
                )
                self._kernel.grant_approval(
                    approval_id=base.approval_id,
                    call_id=base.call_id,
                    tool=base.tool,
                    input_digest=base.input_digest,
                    actor=base.actor,
                    workspace=base.workspace,
                    policy=base.policy,
                    approver=approver,
                    expires_at=base.expires_at,
                )
        transient: List[CodingExecutionResult] = []
        try:
            evidence = self._kernel._execute_coding(
                call.call_id,
                tool_input=normalized,
                executor=self._executor,
                approval_id=approval_id,
                result_sink=transient.append,
                after_start_hook=after_start_hook,
                after_commit_hook=after_commit_hook,
            )
        except InvalidTransition:
            current = self._kernel.snapshot().tool_calls[call.call_id]
            if current.state == "running":
                return self._in_progress(call.call_id)
            raise
        self._close_run(call.run_id, evidence.outcome == "succeeded")
        return self._result(call.call_id, transient[0] if transient else None)

    def _close_run(self, run_id: str, succeeded: bool) -> None:
        run = self._kernel.snapshot().runs[run_id]
        if run.state == "active":
            self._kernel.transition_run(run_id, "completed" if succeeded else "failed")

    def _in_progress(
        self, call_id: str, status: str = "in_progress"
    ) -> CodingInvocationResult:
        snapshot = self._kernel.snapshot()
        call = snapshot.tool_calls[call_id]
        request = snapshot.canonical_requests[cast(str, call.client_correlation_id)]
        approvals = [item for item in snapshot.approvals.values() if item.call_id == call_id]
        return CodingInvocationResult(
            1,
            status,
            request.client_correlation_id,
            call.run_id,
            call.call_id,
            request.decision_id,
            approvals[0].approval_id if len(approvals) == 1 else None,
            request.evidence_id,
            call.input_digest,
            None,
            False,
            None,
            {},
            None,
        )

    def _result(
        self, call_id: str, transient: Optional[CodingExecutionResult]
    ) -> CodingInvocationResult:
        snapshot = self._kernel.snapshot()
        call = snapshot.tool_calls[call_id]
        request = snapshot.canonical_requests[cast(str, call.client_correlation_id)]
        evidence = [item for item in snapshot.evidence.values() if item.call_id == call_id]
        if len(evidence) != 1:
            if call.state == "denied":
                return CodingInvocationResult(
                    1,
                    "completed",
                    request.client_correlation_id,
                    call.run_id,
                    call.call_id,
                    request.decision_id,
                    None,
                    request.evidence_id,
                    call.input_digest,
                    "denied",
                    False,
                    None,
                    {},
                    None,
                )
            raise InvalidTransition("terminal coding call lacks unique Evidence")
        item = evidence[0]
        receipt_value = item.body.get("coding_receipt")
        receipt = dict(receipt_value) if isinstance(receipt_value, dict) else None
        return CodingInvocationResult(
            1,
            "completed",
            request.client_correlation_id,
            call.run_id,
            call.call_id,
            request.decision_id,
            item.approval_id,
            item.evidence_id,
            call.input_digest,
            item.outcome,
            transient is not None,
            receipt,
            dict(item.body),
            transient,
        )

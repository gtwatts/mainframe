"""Durable, local, append-only control-plane kernel.

The kernel deliberately has no production tool registry. The only executable
surface in this phase is one exact read-only tracer name, and even that requires
an executor to be injected by the caller.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, replace
from datetime import datetime, timedelta, timezone
import base64
import binascii
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
from typing import Any, Callable, Dict, List, Mapping, Optional, Set, Tuple, TYPE_CHECKING, Union, cast
import uuid

if TYPE_CHECKING:
    from .coding import (
        CodingExecutionResult,
        CodingExecutor,
    )
    from .contracts import StableCoreContract, StableCoreRegistry
    from .memory import ProjectMemoryExecutionResult, ProjectMemoryExecutor

from .errors import (
    AlreadyExists,
    ApprovalConsumed,
    ApprovalExpired,
    BindingMismatch,
    ControlPlaneError,
    ExecutionDenied,
    EvaluatorUnavailable,
    ExecutorUnavailable,
    InvalidTransition,
    LedgerCorruption,
    LedgerIOError,
    NotFound,
    ValidationError,
)
from .durability import fsync_directory


SCHEMA_VERSION = 1
READ_ONLY_TRACER_TOOL = "control_plane.trace"
DISPOSABLE_WRITE_TOOL = "control_plane.disposable_write"
DISPOSABLE_SENTINEL_NAME = ".mainframe-disposable-workspace"
DISPOSABLE_SENTINEL_CONTENT = b"MAINFRAME_DISPOSABLE_WORKSPACE_V1\n"
MAX_DISPOSABLE_WRITE_BYTES = 64 * 1024
MAX_DISPOSABLE_RELATIVE_PATH_BYTES = 1024
MAX_EVENT_BYTES = 1024 * 1024
MAX_LEDGER_BYTES = 128 * 1024 * 1024
_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
_DIGEST_PATTERN = re.compile(r"^[0-9a-f]{64}$")
_RUN_TRANSITIONS = {
    "created": frozenset(("active", "cancelled")),
    "active": frozenset(("completed", "failed", "cancelled")),
    "completed": frozenset(),
    "failed": frozenset(),
    "cancelled": frozenset(),
}
_CALL_TERMINAL_STATES = frozenset(
    ("succeeded", "failed", "denied", "cancelled", "timed_out", "interrupted")
)
_CALL_PRE_EXECUTION_STATES = frozenset(
    ("pending", "ready", "awaiting_approval", "authorized")
)
_PROJECT_MEMORY_TOOLS = frozenset(
    (
        "mainframe.project_memory.ensure.v1",
        "mainframe.project_memory.checkpoint.v1",
        "mainframe.project_memory.discovery.v1",
        "mainframe.project_memory.progress.v1",
        "mainframe.project_memory.close.v1",
        "mainframe.project_memory.handoff.v1",
        "mainframe.project_memory.session.v1",
        "mainframe.project_memory.status.v1",
        "mainframe.project_memory.get.v1",
        "mainframe.project_memory.summary.v1",
        "mainframe.project_memory.context.v1",
        "mainframe.project_memory.find.v1",
    )
)
_PROJECT_MEMORY_EFFECT = "non_authoritative_memory"
_CODING_EXECUTION_EFFECT = "code_execution"
_CODING_EXECUTION_TOOLS = frozenset(
    ("mainframe.coding.run_test.v1", "mainframe.coding.run_build.v1")
)
_CANONICAL_REQUEST_PAYLOAD_KEYS = frozenset(
    (
        "client_correlation_id",
        "run_id",
        "call_id",
        "decision_id",
        "evidence_id",
        "canonical_id",
        "input_digest",
        "input_metadata",
        "actor",
        "workspace",
        "policy",
        "reservation_binding",
        "reserved_at",
    )
)
_LEGACY_CANONICAL_REQUEST_PAYLOAD_KEYS = frozenset(
    _CANONICAL_REQUEST_PAYLOAD_KEYS - {"evidence_id", "reservation_binding"}
)


JsonValue = Union[None, bool, int, float, str, List["JsonValue"], Dict[str, "JsonValue"]]
Clock = Callable[[], datetime]
Executor = Callable[[str, Mapping[str, JsonValue]], JsonValue]


@dataclass(frozen=True)
class ApprovalGrantRequest:
    """Exact non-authorizing grant intent presented to a trusted implementation."""

    approval_id: str
    call_id: str
    tool: str
    input_digest: str
    actor: str
    workspace: str
    policy: str
    expires_at: str


TrustedApprover = Callable[[ApprovalGrantRequest], str]


@dataclass(frozen=True)
class RunRecord:
    run_id: str
    actor: str
    workspace: str
    policy: str
    state: str
    created_at: str
    updated_at: str

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class ToolCallRecord:
    call_id: str
    run_id: str
    tool: str
    tool_input: Optional[Dict[str, JsonValue]]
    input_metadata: Dict[str, JsonValue]
    input_digest: str
    actor: str
    workspace: str
    policy: str
    effect: str
    timeout_at: Optional[str]
    client_correlation_id: Optional[str]
    state: str
    created_at: str
    updated_at: str

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class PolicyDecisionRecord:
    decision_id: str
    call_id: str
    run_id: str
    tool: str
    input_digest: str
    actor: str
    workspace: str
    policy: str
    timeout_at: Optional[str]
    outcome: str
    authority: str
    reason: str
    decided_at: str

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class PolicyRequest:
    call_id: str
    run_id: str
    tool: str
    tool_input: Dict[str, JsonValue]
    input_digest: str
    actor: str
    workspace: str
    policy: str
    effect: str
    timeout_at: Optional[str]
    client_correlation_id: Optional[str]


@dataclass(frozen=True)
class PolicyEvaluation:
    outcome: str
    authority: str
    reason: str


PolicyEvaluator = Callable[[PolicyRequest], PolicyEvaluation]


@dataclass(frozen=True)
class CanonicalExecutionResult:
    outcome: str
    envelope: Optional[Dict[str, JsonValue]] = None
    error: Optional[str] = None


CanonicalExecutor = Callable[
    [str, Mapping[str, JsonValue]], CanonicalExecutionResult
]
CanonicalResultSink = Callable[[CanonicalExecutionResult], None]


@dataclass(frozen=True)
class CanonicalRequestRecord:
    client_correlation_id: str
    run_id: str
    call_id: str
    decision_id: str
    evidence_id: str
    canonical_id: str
    input_digest: str
    input_metadata: Dict[str, JsonValue]
    actor: str
    workspace: str
    policy: str
    reservation_binding: Optional[Dict[str, JsonValue]]
    reserved_at: str

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class ApprovalRecord:
    approval_id: str
    call_id: str
    run_id: str
    tool: str
    input_digest: str
    actor: str
    workspace: str
    policy: str
    approver: str
    expires_at: str
    state: str
    granted_at: str
    consumed_at: Optional[str]

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class EvidenceRecord:
    evidence_id: str
    run_id: str
    call_id: str
    approval_id: Optional[str]
    tool: str
    input_digest: str
    actor: str
    workspace: str
    policy: str
    approver: Optional[str]
    evidence_type: str
    outcome: str
    body: Dict[str, JsonValue]
    body_digest: str
    recorded_at: str

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class MemoryRecord:
    memory_id: str
    memory_op_id: str
    run_id: str
    call_id: str
    decision_id: str
    evidence_id: str
    tool: str
    input_digest: str
    actor: str
    workspace: str
    policy: str
    policy_authority: str
    project_digest: str
    session_id: str
    record_type: str
    key_sha256: Optional[str]
    value_sha256: str
    value_bytes: int
    trust_label: str
    authoritative: bool
    retention_class: str
    expires_at: Optional[str]
    created_at: str

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class HandoffRecord:
    handoff_id: str
    memory_op_id: str
    run_id: str
    call_id: str
    decision_id: str
    evidence_id: str
    tool: str
    input_digest: str
    actor: str
    workspace: str
    policy: str
    policy_authority: str
    project_digest: str
    session_id: str
    recipient_sha256: str
    summary_sha256: str
    summary_bytes: int
    trust_label: str
    authoritative: bool
    retention_class: str
    expires_at: Optional[str]
    created_at: str

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class Snapshot:
    canonical_requests: Dict[str, CanonicalRequestRecord]
    runs: Dict[str, RunRecord]
    tool_calls: Dict[str, ToolCallRecord]
    policy_decisions: Dict[str, PolicyDecisionRecord]
    approvals: Dict[str, ApprovalRecord]
    evidence: Dict[str, EvidenceRecord]
    memory_records: Dict[str, MemoryRecord]
    handoff_records: Dict[str, HandoffRecord]
    event_count: int
    head_digest: Optional[str]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "canonical_requests": {
                key: value.to_dict()
                for key, value in sorted(self.canonical_requests.items())
            },
            "runs": {key: value.to_dict() for key, value in sorted(self.runs.items())},
            "tool_calls": {
                key: value.to_dict() for key, value in sorted(self.tool_calls.items())
            },
            "policy_decisions": {
                key: value.to_dict()
                for key, value in sorted(self.policy_decisions.items())
            },
            "approvals": {
                key: value.to_dict() for key, value in sorted(self.approvals.items())
            },
            "evidence": {
                key: value.to_dict() for key, value in sorted(self.evidence.items())
            },
            "memory_records": {
                key: value.to_dict()
                for key, value in sorted(self.memory_records.items())
            },
            "handoff_records": {
                key: value.to_dict()
                for key, value in sorted(self.handoff_records.items())
            },
            "event_count": self.event_count,
            "head_digest": self.head_digest,
        }


@dataclass
class _State:
    canonical_requests: Dict[str, CanonicalRequestRecord]
    runs: Dict[str, RunRecord]
    tool_calls: Dict[str, ToolCallRecord]
    policy_decisions: Dict[str, PolicyDecisionRecord]
    approvals: Dict[str, ApprovalRecord]
    evidence: Dict[str, EvidenceRecord]
    memory_records: Dict[str, MemoryRecord]
    handoff_records: Dict[str, HandoffRecord]
    event_ids: Set[str]
    legacy_unbound_canonical_requests: Set[str]
    event_count: int = 0
    head_digest: Optional[str] = None


def _empty_state() -> _State:
    return _State({}, {}, {}, {}, {}, {}, {}, {}, set(), set())


def _canonical_json(value: Any) -> bytes:
    try:
        rendered = json.dumps(
            value,
            allow_nan=False,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        )
    except (TypeError, ValueError) as exc:
        raise ValidationError("value is not canonical JSON: {}".format(exc)) from exc
    return rendered.encode("utf-8")


def _normalized_object(value: Any, label: str) -> Dict[str, JsonValue]:
    if not isinstance(value, dict):
        raise ValidationError("{} must be a JSON object".format(label))
    encoded = _canonical_json(value)
    normalized = json.loads(encoded.decode("utf-8"))
    if not isinstance(normalized, dict):  # defensive; the input check guarantees this
        raise ValidationError("{} must normalize to a JSON object".format(label))
    return normalized


def normalized_input_digest(tool_input: Mapping[str, JsonValue]) -> str:
    normalized = _normalized_object(tool_input, "tool input")
    return hashlib.sha256(_canonical_json(normalized)).hexdigest()


def normalized_input_metadata(
    tool_input: Mapping[str, JsonValue],
) -> Dict[str, JsonValue]:
    """Return the closed, non-value metadata safe to persist for an input."""
    normalized = _normalized_object(tool_input, "tool input")
    encoded = _canonical_json(normalized)
    field_names: List[JsonValue] = [name for name in sorted(normalized)]
    return {
        "canonical_size_bytes": len(encoded),
        "field_count": len(normalized),
        "field_names": field_names,
    }


def _validate_input_metadata(value: Any) -> Dict[str, JsonValue]:
    normalized = _normalized_object(value, "input metadata")
    if set(normalized) != {
        "canonical_size_bytes",
        "field_count",
        "field_names",
    }:
        raise ValidationError("input metadata fields are not exact")
    size = normalized["canonical_size_bytes"]
    count = normalized["field_count"]
    names = normalized["field_names"]
    if not isinstance(names, list) or any(not isinstance(name, str) for name in names):
        raise ValidationError("input metadata is invalid")
    text_names = cast(List[str], names)
    if (
        type(size) is not int
        or not 2 <= size <= 32768
        or type(count) is not int
        or not 0 <= count <= 256
        or len(text_names) != count
        or text_names != sorted(text_names)
        or len(set(text_names)) != len(text_names)
        or any(not name for name in text_names)
    ):
        raise ValidationError("input metadata is invalid")
    return normalized


def _object_digest(value: Mapping[str, Any]) -> str:
    return hashlib.sha256(_canonical_json(dict(value))).hexdigest()


def _legacy_reserved_evidence_id(
    reservation_identity: Mapping[str, JsonValue],
) -> str:
    """Derive a non-authorizing provisional ID for one exact legacy request."""
    if set(reservation_identity) != _LEGACY_CANONICAL_REQUEST_PAYLOAD_KEYS:
        raise ValidationError("legacy canonical reservation identity is not exact")
    binding = {
        "schema_version": 1,
        "kind": "legacy_canonical_evidence_reservation_v1",
        "reservation": dict(reservation_identity),
    }
    return "evidence-{}".format(hashlib.sha256(_canonical_json(binding)).hexdigest()[:32])


_BROKER_ENVELOPE_KEYS = frozenset(
    (
        "schema_version",
        "ok",
        "status",
        "canonical_id",
        "name",
        "owner",
        "exit_code",
        "timed_out",
        "output_exceeded",
        "duration_ms",
        "audit_id",
        "stdout_b64",
        "stderr_b64",
        "error",
    )
)


def _decode_canonical_base64(value: Any, label: str) -> bytes:
    if not isinstance(value, str) or not value.isascii():
        raise ValidationError("{} must be an ASCII base64 string".format(label))
    try:
        decoded = base64.b64decode(value.encode("ascii"), validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ValidationError("{} must be strict base64".format(label)) from exc
    if base64.b64encode(decoded).decode("ascii") != value:
        raise ValidationError("{} must use canonical base64".format(label))
    return decoded


def _validated_canonical_result(
    result: Any,
    call: ToolCallRecord,
    contract: "StableCoreContract",
) -> Tuple[str, Dict[str, JsonValue]]:
    if not isinstance(result, CanonicalExecutionResult):
        raise ValidationError("canonical executor returned an unsupported result type")
    if result.outcome not in ("succeeded", "failed", "timed_out", "interrupted"):
        raise ValidationError("canonical executor returned an unsupported outcome")
    if result.envelope is None:
        if result.outcome not in ("failed", "timed_out", "interrupted"):
            raise ValidationError("successful canonical execution requires an envelope")
        error = _validate_text(result.error or "executor transport failed", "executor error", 4096)
        return result.outcome, {
            "error": {
                "code": "executor_transport_error",
                "detail_bytes": len(error.encode("utf-8")),
                "detail_sha256": hashlib.sha256(error.encode("utf-8")).hexdigest(),
            }
        }
    if result.error is not None:
        raise ValidationError("canonical executor result cannot mix envelope and error")
    envelope = _normalized_object(result.envelope, "broker envelope")
    if set(envelope) != _BROKER_ENVELOPE_KEYS:
        raise ValidationError("broker envelope fields are not exact")
    if type(envelope["schema_version"]) is not int or envelope["schema_version"] != 1:
        raise ValidationError("broker envelope schema version is invalid")
    if type(envelope["ok"]) is not bool:
        raise ValidationError("broker envelope ok must be boolean")
    status_value = envelope["status"]
    canonical_id_value = envelope["canonical_id"]
    name_value = envelope["name"]
    owner_value = envelope["owner"]
    audit_id_value = envelope["audit_id"]
    if not isinstance(status_value, str) or not status_value:
        raise ValidationError("broker envelope status is invalid")
    if canonical_id_value != call.tool:
        raise BindingMismatch("broker envelope canonical ID does not match the tool call")
    if name_value != contract.name or owner_value != contract.owner:
        raise BindingMismatch("broker envelope name/owner does not match the registry")
    if not isinstance(audit_id_value, str):
        raise ValidationError("broker audit_id must be a string")
    _validate_text(audit_id_value, "broker audit_id")
    exit_code = envelope["exit_code"]
    duration_ms = envelope["duration_ms"]
    if (
        type(exit_code) is not int
        or not 0 <= exit_code <= 255
        or type(duration_ms) is not int
        or duration_ms < 0
        or type(envelope["timed_out"]) is not bool
        or type(envelope["output_exceeded"]) is not bool
    ):
        raise ValidationError("broker envelope numeric/boolean metadata is invalid")
    error_value = envelope["error"]
    error_bytes = b""
    if error_value is not None:
        if not isinstance(error_value, str):
            raise ValidationError("broker error must be a string or null")
        _validate_text(error_value, "broker error", 4096)
        error_bytes = error_value.encode("utf-8")
    stdout = _decode_canonical_base64(envelope["stdout_b64"], "stdout_b64")
    stderr = _decode_canonical_base64(envelope["stderr_b64"], "stderr_b64")
    if len(stdout) + len(stderr) > contract.output_limit:
        raise ValidationError("decoded broker output exceeds the contract limit")
    success = (
        envelope["ok"] is True
        and status_value == "success"
        and exit_code == 0
        and envelope["timed_out"] is False
        and envelope["output_exceeded"] is False
        and error_value is None
    )
    timed_out = (
        envelope["ok"] is False
        and status_value == "timeout"
        and exit_code == 124
        and envelope["timed_out"] is True
        and envelope["output_exceeded"] is False
    )
    if success:
        derived_outcome = "succeeded"
    elif timed_out:
        derived_outcome = "timed_out"
    elif (
        envelope["ok"] is False
        and status_value != "success"
        and exit_code != 0
    ):
        derived_outcome = "failed"
    else:
        raise ValidationError("broker envelope status fields contradict each other")
    if result.outcome != derived_outcome:
        raise ValidationError("canonical executor outcome contradicts its envelope")
    return derived_outcome, {
        "broker_receipt": {
            "schema_version": envelope["schema_version"],
            "ok": envelope["ok"],
            "status": envelope["status"],
            "canonical_id": envelope["canonical_id"],
            "name": envelope["name"],
            "owner": envelope["owner"],
            "exit_code": envelope["exit_code"],
            "timed_out": envelope["timed_out"],
            "output_exceeded": envelope["output_exceeded"],
            "duration_ms": envelope["duration_ms"],
            "audit_id": envelope["audit_id"],
            "stdout_bytes": len(stdout),
            "stdout_sha256": hashlib.sha256(stdout).hexdigest(),
            "stderr_bytes": len(stderr),
            "stderr_sha256": hashlib.sha256(stderr).hexdigest(),
            "error_bytes": len(error_bytes),
            "error_sha256": hashlib.sha256(error_bytes).hexdigest(),
        }
    }


def _system_clock() -> datetime:
    return datetime.now(timezone.utc)


def _format_timestamp(value: datetime) -> str:
    if not isinstance(value, datetime) or value.tzinfo is None or value.utcoffset() is None:
        raise ValidationError("timestamp must be timezone-aware")
    utc = value.astimezone(timezone.utc)
    timespec = "microseconds" if utc.microsecond else "seconds"
    return utc.isoformat(timespec=timespec).replace("+00:00", "Z")


def _parse_timestamp(value: str, label: str) -> datetime:
    if not isinstance(value, str) or not value:
        raise ValidationError("{} must be an RFC3339 timestamp".format(label))
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValidationError("{} must be an RFC3339 timestamp".format(label)) from exc
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValidationError("{} must include a timezone".format(label))
    return parsed.astimezone(timezone.utc)


def _normalize_timestamp(value: Union[str, datetime], label: str) -> str:
    if isinstance(value, datetime):
        return _format_timestamp(value)
    return _format_timestamp(_parse_timestamp(value, label))


def _validate_id(value: str, label: str) -> str:
    if not isinstance(value, str) or _ID_PATTERN.fullmatch(value) is None:
        raise ValidationError(
            "{} must match {}".format(label, _ID_PATTERN.pattern)
        )
    return value


def _validate_text(value: str, label: str, maximum: int = 512) -> str:
    if not isinstance(value, str) or not value or len(value) > maximum:
        raise ValidationError("{} must be 1-{} characters".format(label, maximum))
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise ValidationError("{} must not contain control characters".format(label))
    return value


def _normalize_workspace(value: str) -> str:
    value = _validate_text(value, "workspace", 4096)
    if not os.path.isabs(value):
        raise ValidationError("workspace must be an absolute path")
    return os.path.normpath(value)


def _canonicalize_workspace(value: str) -> str:
    """Canonicalize caller input once; replay never depends on filesystem state."""
    return os.path.realpath(_normalize_workspace(value))


def _validate_digest(value: str, label: str) -> str:
    if not isinstance(value, str) or _DIGEST_PATTERN.fullmatch(value) is None:
        raise ValidationError("{} must be a lowercase SHA-256 digest".format(label))
    return value


def _require_exact_keys(payload: Mapping[str, Any], expected: Tuple[str, ...]) -> None:
    actual = set(payload)
    required = set(expected)
    if actual != required:
        raise ValidationError(
            "event payload keys differ: expected {}, got {}".format(
                sorted(required), sorted(actual)
            )
        )


def _validate_disposable_write_input(
    tool_input: Mapping[str, JsonValue],
) -> Dict[str, JsonValue]:
    normalized = _normalized_object(tool_input, "disposable write input")
    if set(normalized) != {"path", "content"}:
        raise ExecutionDenied(
            "disposable write input must contain exactly path and content"
        )
    relative_path = normalized["path"]
    content = normalized["content"]
    if not isinstance(relative_path, str) or not relative_path:
        raise ExecutionDenied("disposable write path must be a non-empty string")
    if os.path.isabs(relative_path) or "\x00" in relative_path:
        raise ExecutionDenied("disposable write path must be a safe relative path")
    try:
        path_bytes = relative_path.encode("utf-8")
    except UnicodeEncodeError as exc:
        raise ExecutionDenied("disposable write path must be valid UTF-8") from exc
    if len(path_bytes) > MAX_DISPOSABLE_RELATIVE_PATH_BYTES:
        raise ExecutionDenied("disposable write path exceeds 1024 UTF-8 bytes")
    parts = relative_path.split("/")
    if any(part in ("", ".", "..") for part in parts):
        raise ExecutionDenied(
            "disposable write path must not contain empty, dot, or parent components"
        )
    if any(len(part.encode("utf-8")) > 255 for part in parts):
        raise ExecutionDenied("disposable write path component exceeds 255 UTF-8 bytes")
    if relative_path == DISPOSABLE_SENTINEL_NAME:
        raise ExecutionDenied("disposable write must not replace its workspace sentinel")
    if not isinstance(content, str):
        raise ExecutionDenied("disposable write content must be a UTF-8 string")
    try:
        content_bytes = content.encode("utf-8")
    except UnicodeEncodeError as exc:
        raise ExecutionDenied("disposable write content must be valid UTF-8") from exc
    if len(content_bytes) > MAX_DISPOSABLE_WRITE_BYTES:
        raise ExecutionDenied("disposable write content exceeds 65536 UTF-8 bytes")
    return normalized


def _require_run(state: _State, run_id: str) -> RunRecord:
    try:
        return state.runs[run_id]
    except KeyError as exc:
        raise NotFound("run not found: {}".format(run_id)) from exc


def _require_call(state: _State, call_id: str) -> ToolCallRecord:
    try:
        return state.tool_calls[call_id]
    except KeyError as exc:
        raise NotFound("tool call not found: {}".format(call_id)) from exc


def _require_approval(state: _State, approval_id: str) -> ApprovalRecord:
    try:
        return state.approvals[approval_id]
    except KeyError as exc:
        raise NotFound("approval not found: {}".format(approval_id)) from exc


def _decision_for_call(
    state: _State, call_id: str
) -> Optional[PolicyDecisionRecord]:
    matches = [
        decision
        for decision in state.policy_decisions.values()
        if decision.call_id == call_id
    ]
    if len(matches) > 1:  # replay invariant; normal writes cannot create this
        raise InvalidTransition("tool call has multiple policy decisions")
    return matches[0] if matches else None


def _assert_call_binding(
    call: ToolCallRecord,
    *,
    call_id: str,
    tool: str,
    input_digest: str,
    actor: str,
    workspace: str,
    policy: str,
) -> None:
    expected = (
        call.call_id,
        call.tool,
        call.input_digest,
        call.actor,
        call.workspace,
        call.policy,
    )
    actual = (call_id, tool, input_digest, actor, workspace, policy)
    if actual != expected:
        raise BindingMismatch("identity binding does not exactly match the tool call")


def _reduce(state: _State, event: Mapping[str, Any]) -> None:
    kind = event["kind"]
    action = event["action"]
    payload = event["payload"]
    if not isinstance(payload, dict):
        raise ValidationError("event payload must be an object")

    if kind == "canonical_request" and action == "reserved":
        payload_keys = frozenset(payload)
        if payload_keys == _CANONICAL_REQUEST_PAYLOAD_KEYS:
            legacy_unbound = False
        elif payload_keys == _LEGACY_CANONICAL_REQUEST_PAYLOAD_KEYS:
            legacy_unbound = True
        else:
            raise ValidationError(
                "canonical reservation payload keys are neither current nor the exact legacy schema"
            )
        correlation_id = _validate_id(
            payload["client_correlation_id"], "client_correlation_id"
        )
        if correlation_id in state.canonical_requests:
            raise AlreadyExists(
                "client correlation already exists: {}".format(correlation_id)
            )
        run_id = _validate_id(payload["run_id"], "run_id")
        call_id = _validate_id(payload["call_id"], "call_id")
        decision_id = _validate_id(payload["decision_id"], "decision_id")
        canonical_id = _validate_text(payload["canonical_id"], "canonical_id")
        input_digest = _validate_digest(payload["input_digest"], "input_digest")
        input_metadata = _validate_input_metadata(payload["input_metadata"])
        actor = _validate_text(payload["actor"], "actor")
        workspace = _normalize_workspace(payload["workspace"])
        if workspace != payload["workspace"]:
            raise ValidationError("canonical request workspace is not normalized")
        policy = _validate_text(payload["policy"], "policy")
        if legacy_unbound and (
            policy != "stable-core-v1" or canonical_id in _PROJECT_MEMORY_TOOLS
        ):
            raise BindingMismatch(
                "legacy canonical reservation is outside the shipped stable-core schema"
            )
        reserved_at = _normalize_timestamp(payload["reserved_at"], "reserved_at")
        if reserved_at != payload["reserved_at"]:
            raise ValidationError("canonical request timestamp is not canonical")
        legacy_identity: Dict[str, JsonValue] = {
            "client_correlation_id": correlation_id,
            "run_id": run_id,
            "call_id": call_id,
            "decision_id": decision_id,
            "canonical_id": canonical_id,
            "input_digest": input_digest,
            "input_metadata": input_metadata,
            "actor": actor,
            "workspace": workspace,
            "policy": policy,
            "reserved_at": reserved_at,
        }
        evidence_id = (
            _legacy_reserved_evidence_id(legacy_identity)
            if legacy_unbound
            else _validate_id(payload["evidence_id"], "evidence_id")
        )
        if (
            run_id in state.runs
            or call_id in state.tool_calls
            or decision_id in state.policy_decisions
            or evidence_id in state.evidence
            or any(
                request.evidence_id == evidence_id
                for request in state.canonical_requests.values()
            )
        ):
            raise AlreadyExists("canonical request generated identity already exists")
        binding_value = None if legacy_unbound else payload["reservation_binding"]
        reservation_binding: Optional[Dict[str, JsonValue]] = None
        if binding_value is not None:
            if canonical_id not in _PROJECT_MEMORY_TOOLS:
                raise BindingMismatch(
                    "only project-memory requests may carry a reservation binding"
                )
            from .memory import parse_project_memory_reservation_binding

            observation, _retention, _expires_at = (
                parse_project_memory_reservation_binding(binding_value)
            )
            expected_project = hashlib.sha256(workspace.encode("utf-8")).hexdigest()
            if observation.project_digest != expected_project:
                raise BindingMismatch(
                    "project-memory reservation does not match its workspace"
                )
            reservation_binding = dict(binding_value)
        state.canonical_requests[correlation_id] = CanonicalRequestRecord(
            correlation_id,
            run_id,
            call_id,
            decision_id,
            evidence_id,
            canonical_id,
            input_digest,
            input_metadata,
            actor,
            workspace,
            policy,
            reservation_binding,
            reserved_at,
        )
        if legacy_unbound:
            # Replay compatibility only: the historical reservation omitted its
            # future Evidence identity and reservation-binding fields. New writers
            # must never emit the legacy shape, and only a later fully validated
            # historical Evidence event may replace the provisional ID in memory.
            state.legacy_unbound_canonical_requests.add(correlation_id)
        return

    if kind == "run" and action == "created":
        _require_exact_keys(
            payload,
            ("run_id", "actor", "workspace", "policy", "state", "created_at"),
        )
        run_id = _validate_id(payload["run_id"], "run_id")
        if run_id in state.runs:
            raise AlreadyExists("run already exists: {}".format(run_id))
        actor = _validate_text(payload["actor"], "actor")
        workspace = _normalize_workspace(payload["workspace"])
        if workspace != payload["workspace"]:
            raise ValidationError("workspace is not normalized")
        policy = _validate_text(payload["policy"], "policy")
        reserved = [
            request
            for request in state.canonical_requests.values()
            if request.run_id == run_id
        ]
        if reserved and (
            len(reserved) != 1
            or (actor, workspace, policy)
            != (reserved[0].actor, reserved[0].workspace, reserved[0].policy)
        ):
            raise BindingMismatch("run does not match its canonical request")
        created_at = _normalize_timestamp(payload["created_at"], "created_at")
        if created_at != payload["created_at"] or payload["state"] != "created":
            raise ValidationError("run creation payload is not canonical")
        state.runs[run_id] = RunRecord(
            run_id, actor, workspace, policy, "created", created_at, created_at
        )
        return

    if kind == "run" and action == "transitioned":
        _require_exact_keys(payload, ("run_id", "from_state", "to_state", "updated_at"))
        run = _require_run(state, _validate_id(payload["run_id"], "run_id"))
        from_state = payload["from_state"]
        to_state = payload["to_state"]
        if run.state != from_state or to_state not in _RUN_TRANSITIONS.get(from_state, ()):
            raise InvalidTransition(
                "run {} cannot transition from {} to {}".format(
                    run.run_id, run.state, to_state
                )
            )
        if to_state in ("completed", "failed", "cancelled"):
            unfinished = [
                call.call_id
                for call in state.tool_calls.values()
                if call.run_id == run.run_id and call.state not in _CALL_TERMINAL_STATES
            ]
            if unfinished:
                raise InvalidTransition("run has unfinished tool calls")
        updated_at = _normalize_timestamp(payload["updated_at"], "updated_at")
        if (
            updated_at != payload["updated_at"]
            or _parse_timestamp(updated_at, "updated_at")
            < _parse_timestamp(run.updated_at, "previous updated_at")
        ):
            raise InvalidTransition("run transition timestamp moved backwards")
        state.runs[run.run_id] = replace(run, state=to_state, updated_at=updated_at)
        return

    if kind == "tool_call" and action == "created":
        _require_exact_keys(
            payload,
            (
                "call_id",
                "run_id",
                "tool",
                "tool_input",
                "input_metadata",
                "input_digest",
                "actor",
                "workspace",
                "policy",
                "effect",
                "timeout_at",
                "client_correlation_id",
                "state",
                "created_at",
            ),
        )
        call_id = _validate_id(payload["call_id"], "call_id")
        if call_id in state.tool_calls:
            raise AlreadyExists("tool call already exists: {}".format(call_id))
        correlation_value = payload["client_correlation_id"]
        client_correlation_id = None
        if correlation_value is not None:
            client_correlation_id = _validate_id(
                correlation_value, "client_correlation_id"
            )
            if any(
                existing.client_correlation_id == client_correlation_id
                for existing in state.tool_calls.values()
            ):
                raise AlreadyExists(
                    "client correlation already exists: {}".format(
                        client_correlation_id
                    )
                )
        run = _require_run(state, _validate_id(payload["run_id"], "run_id"))
        if run.state != "active":
            raise InvalidTransition("tool calls require an active run")
        tool = _validate_text(payload["tool"], "tool")
        input_metadata = _validate_input_metadata(payload["input_metadata"])
        raw_tool_input = payload["tool_input"]
        tool_input: Optional[Dict[str, JsonValue]]
        if client_correlation_id is None:
            tool_input = _normalized_object(raw_tool_input, "tool input")
        else:
            if raw_tool_input is not None:
                raise ValidationError(
                    "canonical correlated tool input must not be persisted"
                )
            tool_input = None
        digest = _validate_digest(payload["input_digest"], "input_digest")
        if tool_input is not None and digest != normalized_input_digest(tool_input):
            raise BindingMismatch("tool input digest does not match normalized input")
        if tool_input is not None and input_metadata != normalized_input_metadata(tool_input):
            raise BindingMismatch("tool input metadata does not match normalized input")
        actor = _validate_text(payload["actor"], "actor")
        workspace = _normalize_workspace(payload["workspace"])
        policy = _validate_text(payload["policy"], "policy")
        if (actor, workspace, policy) != (run.actor, run.workspace, run.policy):
            raise BindingMismatch("tool call context does not exactly match its run")
        if client_correlation_id is not None:
            request = state.canonical_requests.get(client_correlation_id)
            if request is None or (
                request.run_id != run.run_id
                or request.call_id != call_id
                or request.canonical_id != tool
                or request.input_digest != digest
                or request.input_metadata != input_metadata
                or request.actor != actor
                or request.workspace != workspace
                or request.policy != policy
            ):
                raise BindingMismatch(
                    "canonical tool call does not match its reserved request"
                )
        effect = payload["effect"]
        if effect not in (
            "read_only",
            "mutating",
            _CODING_EXECUTION_EFFECT,
            _PROJECT_MEMORY_EFFECT,
        ):
            raise ValidationError("effect is unsupported")
        if effect == _PROJECT_MEMORY_EFFECT and tool not in _PROJECT_MEMORY_TOOLS:
            raise ExecutionDenied("non-authoritative memory effect requires a fixed tool")
        if tool == DISPOSABLE_WRITE_TOOL:
            if effect != "mutating":
                raise ExecutionDenied("disposable write must be recorded as mutating")
            if tool_input is None:
                raise ExecutionDenied("disposable write input cannot be ephemeral")
            tool_input = _validate_disposable_write_input(tool_input)
        created_at = _normalize_timestamp(payload["created_at"], "created_at")
        timeout_at_value = payload["timeout_at"]
        timeout_at = None
        if timeout_at_value is not None:
            timeout_at = _normalize_timestamp(timeout_at_value, "timeout_at")
            if timeout_at != timeout_at_value:
                raise ValidationError("tool call timeout is not canonical")
            if _parse_timestamp(timeout_at, "timeout_at") <= _parse_timestamp(
                created_at, "created_at"
            ):
                raise InvalidTransition("tool call timeout must follow its creation")
        if created_at != payload["created_at"] or payload["state"] != "pending":
            raise ValidationError("tool call creation payload is not canonical")
        if _parse_timestamp(created_at, "created_at") < _parse_timestamp(
            run.updated_at, "run updated_at"
        ):
            raise InvalidTransition("tool call timestamp predates its active run")
        state.tool_calls[call_id] = ToolCallRecord(
            call_id,
            run.run_id,
            tool,
            tool_input,
            input_metadata,
            digest,
            actor,
            workspace,
            policy,
            effect,
            timeout_at,
            client_correlation_id,
            "pending",
            created_at,
            created_at,
        )
        return

    if kind == "policy_decision" and action == "recorded":
        _require_exact_keys(
            payload,
            (
                "decision_id",
                "call_id",
                "run_id",
                "tool",
                "input_digest",
                "actor",
                "workspace",
                "policy",
                "timeout_at",
                "outcome",
                "authority",
                "reason",
                "decided_at",
                "call_from_state",
                "call_to_state",
            ),
        )
        decision_id = _validate_id(payload["decision_id"], "decision_id")
        if decision_id in state.policy_decisions:
            raise AlreadyExists("policy decision already exists: {}".format(decision_id))
        call = _require_call(state, _validate_id(payload["call_id"], "call_id"))
        if call.client_correlation_id is not None:
            request = state.canonical_requests.get(call.client_correlation_id)
            if request is None or request.decision_id != decision_id:
                raise BindingMismatch(
                    "policy decision ID does not match its canonical request"
                )
        run = _require_run(state, call.run_id)
        if run.state != "active":
            raise InvalidTransition("policy decision requires an active run")
        if call.state != "pending" or _decision_for_call(state, call.call_id) is not None:
            raise InvalidTransition("tool call already has a policy decision")
        if payload["run_id"] != call.run_id:
            raise BindingMismatch("policy decision run does not match the tool call")
        workspace = _normalize_workspace(payload["workspace"])
        _assert_call_binding(
            call,
            call_id=payload["call_id"],
            tool=_validate_text(payload["tool"], "tool"),
            input_digest=_validate_digest(payload["input_digest"], "input_digest"),
            actor=_validate_text(payload["actor"], "actor"),
            workspace=workspace,
            policy=_validate_text(payload["policy"], "policy"),
        )
        timeout_at_value = payload["timeout_at"]
        timeout_at = None
        if timeout_at_value is not None:
            timeout_at = _normalize_timestamp(timeout_at_value, "timeout_at")
            if timeout_at != timeout_at_value:
                raise ValidationError("policy decision timeout is not canonical")
        if timeout_at != call.timeout_at:
            raise BindingMismatch("policy decision timeout does not match the tool call")
        outcome = payload["outcome"]
        expected_state = {
            "allow": "ready",
            "deny": "denied",
            "approval_required": "awaiting_approval",
        }.get(outcome)
        if expected_state is None:
            raise ValidationError(
                "policy outcome must be allow, deny, or approval_required"
            )
        if outcome == "allow" and call.effect not in (
            "read_only",
            _PROJECT_MEMORY_EFFECT,
        ):
            raise ExecutionDenied("mutating tool calls cannot receive an allow decision")
        if outcome == "approval_required" and call.effect not in (
            "mutating",
            _CODING_EXECUTION_EFFECT,
        ):
            raise ExecutionDenied(
                "read-only tool calls cannot require a mutating approval"
            )
        if (
            payload["call_from_state"] != "pending"
            or payload["call_to_state"] != expected_state
        ):
            raise InvalidTransition("policy decision call transition is invalid")
        authority = _validate_text(payload["authority"], "authority")
        reason = _validate_text(payload["reason"], "reason", 4096)
        decided_at = _normalize_timestamp(payload["decided_at"], "decided_at")
        if decided_at != payload["decided_at"]:
            raise ValidationError("policy decision timestamp is not canonical")
        if _parse_timestamp(decided_at, "decided_at") < _parse_timestamp(
            call.updated_at, "call updated_at"
        ):
            raise InvalidTransition("policy decision timestamp moved backwards")
        decision = PolicyDecisionRecord(
            decision_id,
            call.call_id,
            call.run_id,
            call.tool,
            call.input_digest,
            call.actor,
            call.workspace,
            call.policy,
            call.timeout_at,
            outcome,
            authority,
            reason,
            decided_at,
        )
        state.policy_decisions[decision_id] = decision
        state.tool_calls[call.call_id] = replace(
            call, state=expected_state, updated_at=decided_at
        )
        return

    if kind == "tool_call" and action == "execution_started":
        _require_exact_keys(
            payload,
            (
                "call_id",
                "tool",
                "input_digest",
                "actor",
                "workspace",
                "policy",
                "from_state",
                "to_state",
                "reason",
                "updated_at",
            ),
        )
        call = _require_call(state, _validate_id(payload["call_id"], "call_id"))
        run = _require_run(state, call.run_id)
        if run.state != "active":
            raise InvalidTransition("tool execution requires an active run")
        workspace = _normalize_workspace(payload["workspace"])
        _assert_call_binding(
            call,
            call_id=payload["call_id"],
            tool=_validate_text(payload["tool"], "tool"),
            input_digest=_validate_digest(payload["input_digest"], "input_digest"),
            actor=_validate_text(payload["actor"], "actor"),
            workspace=workspace,
            policy=_validate_text(payload["policy"], "policy"),
        )
        policy_decision = _decision_for_call(state, call.call_id)
        if policy_decision is None or policy_decision.outcome != "allow":
            raise ExecutionDenied("tool execution requires an exact durable allow decision")
        read_only_start = (
            payload["reason"] == "read_only_execution_started"
            and call.effect == "read_only"
        )
        memory_start = (
            payload["reason"] == "project_memory_execution_started"
            and call.effect == _PROJECT_MEMORY_EFFECT
            and call.tool in _PROJECT_MEMORY_TOOLS
        )
        memory_read_start = (
            payload["reason"] == "project_memory_read_execution_started"
            and call.effect == "read_only"
            and call.tool in _PROJECT_MEMORY_TOOLS
        )
        if (
            call.state != "ready"
            or payload["from_state"] != "ready"
            or payload["to_state"] != "running"
            or not (read_only_start or memory_start or memory_read_start)
        ):
            raise InvalidTransition("tool execution state transition is invalid")
        updated_at = _normalize_timestamp(payload["updated_at"], "updated_at")
        if (
            updated_at != payload["updated_at"]
            or _parse_timestamp(updated_at, "updated_at")
            < _parse_timestamp(call.updated_at, "previous updated_at")
        ):
            raise InvalidTransition("tool execution timestamp moved backwards")
        if call.timeout_at is not None and _parse_timestamp(
            updated_at, "updated_at"
        ) >= _parse_timestamp(call.timeout_at, "timeout_at"):
            raise InvalidTransition("tool call deadline has elapsed")
        state.tool_calls[call.call_id] = replace(
            call, state="running", updated_at=updated_at
        )
        return

    if kind == "tool_call" and action == "resolved":
        _require_exact_keys(
            payload,
            (
                "call_id",
                "tool",
                "input_digest",
                "actor",
                "workspace",
                "policy",
                "from_state",
                "to_state",
                "reason",
                "updated_at",
            ),
        )
        call = _require_call(state, _validate_id(payload["call_id"], "call_id"))
        if _require_run(state, call.run_id).state != "active":
            raise InvalidTransition("tool call resolution requires an active run")
        workspace = _normalize_workspace(payload["workspace"])
        _assert_call_binding(
            call,
            call_id=payload["call_id"],
            tool=_validate_text(payload["tool"], "tool"),
            input_digest=_validate_digest(payload["input_digest"], "input_digest"),
            actor=_validate_text(payload["actor"], "actor"),
            workspace=workspace,
            policy=_validate_text(payload["policy"], "policy"),
        )
        from_state = payload["from_state"]
        to_state = payload["to_state"]
        reason = _validate_text(payload["reason"], "reason", 4096)
        if not reason:
            raise ValidationError("resolution reason is required")
        if call.state != from_state:
            raise InvalidTransition(
                "tool call {} is no longer in expected state {}".format(
                    call.call_id, call.state
                )
            )
        if to_state == "cancelled":
            allowed = from_state in _CALL_PRE_EXECUTION_STATES
        elif to_state == "timed_out":
            allowed = from_state in _CALL_PRE_EXECUTION_STATES and call.timeout_at is not None
        elif to_state == "interrupted":
            allowed = from_state == "running"
        else:
            allowed = False
        if not allowed:
            raise InvalidTransition(
                "tool call {} cannot resolve from {} to {}".format(
                    call.call_id, call.state, to_state
                )
            )
        updated_at = _normalize_timestamp(payload["updated_at"], "updated_at")
        if (
            updated_at != payload["updated_at"]
            or _parse_timestamp(updated_at, "updated_at")
            < _parse_timestamp(call.updated_at, "previous updated_at")
        ):
            raise InvalidTransition("tool call transition timestamp moved backwards")
        if to_state == "timed_out" and call.timeout_at is not None and _parse_timestamp(
            updated_at, "updated_at"
        ) < _parse_timestamp(call.timeout_at, "timeout_at"):
            raise InvalidTransition("tool call deadline has not elapsed")
        state.tool_calls[call.call_id] = replace(
            call, state=to_state, updated_at=updated_at
        )
        return

    if kind == "approval" and action == "granted":
        _require_exact_keys(
            payload,
            (
                "approval_id",
                "call_id",
                "run_id",
                "tool",
                "input_digest",
                "actor",
                "workspace",
                "policy",
                "approver",
                "expires_at",
                "state",
                "granted_at",
            ),
        )
        approval_id = _validate_id(payload["approval_id"], "approval_id")
        if approval_id in state.approvals:
            raise AlreadyExists("approval already exists: {}".format(approval_id))
        call = _require_call(state, _validate_id(payload["call_id"], "call_id"))
        if call.state != "awaiting_approval":
            raise InvalidTransition("approval requires an awaiting tool call")
        approval_decision = _decision_for_call(state, call.call_id)
        if approval_decision is None or approval_decision.outcome != "approval_required":
            raise ExecutionDenied(
                "approval requires an exact durable approval_required decision"
            )
        if _require_run(state, call.run_id).state != "active":
            raise InvalidTransition("approval requires an active run")
        if any(
            existing.call_id == call.call_id and existing.state == "granted"
            for existing in state.approvals.values()
        ):
            raise AlreadyExists("tool call already has an outstanding approval")
        if payload["run_id"] != call.run_id:
            raise BindingMismatch("approval run does not match the tool call")
        workspace = _normalize_workspace(payload["workspace"])
        approver = _validate_text(payload["approver"], "approver")
        if approver == call.actor:
            raise BindingMismatch("approver must be distinct from the caller actor")
        _assert_call_binding(
            call,
            call_id=payload["call_id"],
            tool=_validate_text(payload["tool"], "tool"),
            input_digest=_validate_digest(payload["input_digest"], "input_digest"),
            actor=_validate_text(payload["actor"], "actor"),
            workspace=workspace,
            policy=_validate_text(payload["policy"], "policy"),
        )
        granted_at = _normalize_timestamp(payload["granted_at"], "granted_at")
        expires_at = _normalize_timestamp(payload["expires_at"], "expires_at")
        if granted_at != payload["granted_at"] or expires_at != payload["expires_at"]:
            raise ValidationError("approval timestamps are not canonical")
        if _parse_timestamp(expires_at, "expires_at") <= _parse_timestamp(
            granted_at, "granted_at"
        ):
            raise ApprovalExpired("approval must expire after it is granted")
        if _parse_timestamp(granted_at, "granted_at") < _parse_timestamp(
            call.updated_at, "call updated_at"
        ):
            raise InvalidTransition("approval timestamp predates the tool call")
        if payload["state"] != "granted":
            raise ValidationError("approval creation state must be granted")
        state.approvals[approval_id] = ApprovalRecord(
            approval_id,
            call.call_id,
            call.run_id,
            call.tool,
            call.input_digest,
            call.actor,
            call.workspace,
            call.policy,
            approver,
            expires_at,
            "granted",
            granted_at,
            None,
        )
        return

    if kind == "approval" and action == "consumed":
        _require_exact_keys(
            payload,
            (
                "approval_id",
                "call_id",
                "actor",
                "workspace",
                "policy",
                "approver",
                "reason",
                "approval_from_state",
                "approval_to_state",
                "call_from_state",
                "call_to_state",
                "consumed_at",
            ),
        )
        approval = _require_approval(
            state, _validate_id(payload["approval_id"], "approval_id")
        )
        if approval.state == "consumed":
            raise ApprovalConsumed("approval was already consumed")
        call = _require_call(state, _validate_id(payload["call_id"], "call_id"))
        if _require_run(state, call.run_id).state != "active":
            raise InvalidTransition("approval consumption requires an active run")
        reason = payload["reason"]
        authorized_only = (
            reason == "authorization_only"
            and payload["call_to_state"] == "authorized"
            and call.tool
            not in (
                DISPOSABLE_WRITE_TOOL,
                "mainframe.coding.atomic_edit.v1",
                *_CODING_EXECUTION_TOOLS,
            )
        )
        disposable_execution = (
            reason == "disposable_write_execution_started"
            and payload["call_to_state"] == "running"
            and call.tool == DISPOSABLE_WRITE_TOOL
            and call.effect == "mutating"
        )
        coding_edit_execution = (
            reason == "coding_edit_execution_started"
            and payload["call_to_state"] == "running"
            and call.tool == "mainframe.coding.atomic_edit.v1"
            and call.effect == "mutating"
        )
        coding_action_execution = (
            reason == "coding_action_execution_started"
            and payload["call_to_state"] == "running"
            and call.tool in _CODING_EXECUTION_TOOLS
            and call.effect == _CODING_EXECUTION_EFFECT
        )
        if (
            payload["approval_from_state"] != "granted"
            or payload["approval_to_state"] != "consumed"
            or payload["call_from_state"] != "awaiting_approval"
            or call.state != "awaiting_approval"
            or not (
                authorized_only
                or disposable_execution
                or coding_edit_execution
                or coding_action_execution
            )
        ):
            raise InvalidTransition("approval consumption state transition is invalid")
        workspace = _normalize_workspace(payload["workspace"])
        actor = _validate_text(payload["actor"], "actor")
        policy = _validate_text(payload["policy"], "policy")
        approver = _validate_text(payload["approver"], "approver")
        _assert_call_binding(
            call,
            call_id=payload["call_id"],
            tool=approval.tool,
            input_digest=approval.input_digest,
            actor=actor,
            workspace=workspace,
            policy=policy,
        )
        if (
            approval.call_id != call.call_id
            or approval.run_id != call.run_id
            or approval.actor != actor
            or approval.workspace != workspace
            or approval.policy != policy
            or approval.approver != approver
            or approval.tool != call.tool
            or approval.input_digest != call.input_digest
        ):
            raise BindingMismatch("stored approval binding does not match the tool call")
        consumed_at = _normalize_timestamp(payload["consumed_at"], "consumed_at")
        if consumed_at != payload["consumed_at"]:
            raise ValidationError("consumption timestamp is not canonical")
        consumed_time = _parse_timestamp(consumed_at, "consumed_at")
        if consumed_time < _parse_timestamp(approval.granted_at, "granted_at"):
            raise InvalidTransition("approval consumption timestamp moved backwards")
        if consumed_time >= _parse_timestamp(approval.expires_at, "expires_at"):
            raise ApprovalExpired("approval has expired")
        state.approvals[approval.approval_id] = replace(
            approval, state="consumed", consumed_at=consumed_at
        )
        state.tool_calls[call.call_id] = replace(
            call, state=payload["call_to_state"], updated_at=consumed_at
        )
        return

    if kind == "evidence" and action == "recorded":
        _require_exact_keys(
            payload,
            (
                "evidence_id",
                "run_id",
                "call_id",
                "approval_id",
                "tool",
                "input_digest",
                "actor",
                "workspace",
                "policy",
                "approver",
                "evidence_type",
                "outcome",
                "body",
                "body_digest",
                "recorded_at",
                "call_from_state",
                "call_to_state",
            ),
        )
        evidence_id = _validate_id(payload["evidence_id"], "evidence_id")
        if evidence_id in state.evidence:
            raise AlreadyExists("evidence already exists: {}".format(evidence_id))
        call = _require_call(state, _validate_id(payload["call_id"], "call_id"))
        legacy_correlation: Optional[str] = None
        legacy_request: Optional[CanonicalRequestRecord] = None
        if call.client_correlation_id is not None:
            request = state.canonical_requests.get(call.client_correlation_id)
            if request is None:
                raise BindingMismatch(
                    "evidence ID does not match the canonical reservation"
                )
            if call.client_correlation_id in state.legacy_unbound_canonical_requests:
                legacy_correlation = call.client_correlation_id
                legacy_request = request
                legacy_decision = _decision_for_call(state, call.call_id)
                if (
                    legacy_decision is None
                    or legacy_decision.decision_id != request.decision_id
                ):
                    raise BindingMismatch(
                        "legacy Evidence does not match its reserved policy decision"
                    )
                if request.evidence_id != evidence_id and any(
                    correlation != legacy_correlation
                    and existing.evidence_id == evidence_id
                    for correlation, existing in state.canonical_requests.items()
                ):
                    raise AlreadyExists(
                        "historical Evidence ID is reserved by another request"
                    )
            elif request.evidence_id != evidence_id:
                raise BindingMismatch(
                    "evidence ID does not match the canonical reservation"
                )
        if _require_run(state, call.run_id).state != "active":
            raise InvalidTransition("evidence requires an active run")
        if payload["run_id"] != call.run_id:
            raise BindingMismatch("evidence run does not match the tool call")
        workspace = _normalize_workspace(payload["workspace"])
        if (
            payload["tool"] != call.tool
            or payload["input_digest"] != call.input_digest
            or payload["actor"] != call.actor
            or workspace != call.workspace
            or payload["policy"] != call.policy
        ):
            raise BindingMismatch("evidence identity does not match the tool call")
        approval_id = payload["approval_id"]
        approver = payload["approver"]
        bound_approval = None
        if approval_id is None:
            if approver is not None or call.effect not in (
                "read_only",
                _PROJECT_MEMORY_EFFECT,
            ):
                raise BindingMismatch(
                    "unapproved evidence is limited to fixed policy-allowed calls"
                )
            if (
                call.effect == _PROJECT_MEMORY_EFFECT
                and call.tool not in _PROJECT_MEMORY_TOOLS
            ):
                raise BindingMismatch("memory Evidence requires a fixed memory tool")
            evidence_decision = _decision_for_call(state, call.call_id)
            if evidence_decision is None or evidence_decision.outcome != "allow":
                raise ExecutionDenied(
                    "read-only evidence requires an exact durable allow decision"
                )
        else:
            approval = _require_approval(
                state, _validate_id(approval_id, "approval_id")
            )
            bound_approval = approval
            if (
                approval.state != "consumed"
                or approval.call_id != call.call_id
                or approval.tool != call.tool
                or approval.input_digest != call.input_digest
                or approval.actor != call.actor
                or approval.workspace != call.workspace
                or approval.policy != call.policy
                or approver != approval.approver
            ):
                raise BindingMismatch("evidence approval identity does not match")
        if payload["evidence_type"] != "tool_execution":
            raise ValidationError("unsupported evidence type")
        outcome = payload["outcome"]
        expected_state = {
            "succeeded": "succeeded",
            "failed": "failed",
            "timed_out": "timed_out",
            "interrupted": "interrupted",
        }.get(outcome)
        if expected_state is None:
            raise ValidationError("unsupported evidence outcome")
        if (
            call.state != "running"
            or payload["call_from_state"] != "running"
            or payload["call_to_state"] != expected_state
        ):
            raise InvalidTransition("evidence does not complete a running tool call")
        body = _normalized_object(payload["body"], "evidence body")
        body_digest = _validate_digest(payload["body_digest"], "body_digest")
        if body_digest != _object_digest(body):
            raise BindingMismatch("evidence body digest does not match its body")
        if call.tool == DISPOSABLE_WRITE_TOOL and outcome == "succeeded":
            if call.tool_input is None:
                raise BindingMismatch("disposable write input is unavailable")
            disposable_input = _validate_disposable_write_input(call.tool_input)
            content = disposable_input["content"]
            relative_path = disposable_input["path"]
            receipt = body.get("receipt")
            if (
                not isinstance(receipt, dict)
                or bound_approval is None
                or not isinstance(content, str)
                or not isinstance(relative_path, str)
            ):
                raise BindingMismatch("disposable write receipt is incomplete")
            content_bytes = content.encode("utf-8")
            expected_receipt = {
                "operation": "atomic_replace",
                "relative_path": relative_path,
                "bytes_written": len(content_bytes),
                "content_digest": hashlib.sha256(content_bytes).hexdigest(),
                "call_id": call.call_id,
                "approval_id": bound_approval.approval_id,
                "tool": call.tool,
                "input_digest": call.input_digest,
                "actor": call.actor,
                "workspace": call.workspace,
                "policy": call.policy,
                "approver": bound_approval.approver,
            }
            if receipt != expected_receipt:
                raise BindingMismatch("disposable write receipt identity does not match")
        coding_receipt = body.get("coding_receipt")
        if coding_receipt is not None:
            from .coding import validate_durable_coding_receipt

            if not isinstance(coding_receipt, dict):
                raise BindingMismatch("coding receipt must be an object")
            coding_decision = _decision_for_call(state, call.call_id)
            if coding_decision is None:
                raise BindingMismatch("coding receipt lacks its policy decision")
            validate_durable_coding_receipt(
                coding_receipt,
                run_id=call.run_id,
                call_id=call.call_id,
                decision_id=coding_decision.decision_id,
                evidence_id=evidence_id,
                approval_id=approval_id,
                approver=approver,
                tool=call.tool,
                input_digest=call.input_digest,
                actor=call.actor,
                workspace=call.workspace,
                policy=call.policy,
                outcome=outcome,
            )
        project_memory_receipt = body.get("project_memory_receipt")
        if project_memory_receipt is not None:
            from .memory import validate_durable_project_memory_receipt

            if set(body) != {"project_memory_receipt"} or not isinstance(
                project_memory_receipt, dict
            ):
                raise BindingMismatch(
                    "project-memory Evidence must contain one exact receipt"
                )
            memory_decision = _decision_for_call(state, call.call_id)
            if (
                approval_id is not None
                or memory_decision is None
                or memory_decision.outcome != "allow"
            ):
                raise BindingMismatch(
                    "project-memory receipt lacks its kernel policy decision"
                )
            validate_durable_project_memory_receipt(
                project_memory_receipt,
                run_id=call.run_id,
                call_id=call.call_id,
                decision_id=memory_decision.decision_id,
                evidence_id=evidence_id,
                tool=call.tool,
                input_digest=call.input_digest,
                actor=call.actor,
                workspace=call.workspace,
                policy=call.policy,
                evidence_outcome=outcome,
            )
        recorded_at = _normalize_timestamp(payload["recorded_at"], "recorded_at")
        if (
            recorded_at != payload["recorded_at"]
            or _parse_timestamp(recorded_at, "recorded_at")
            < _parse_timestamp(call.updated_at, "previous updated_at")
        ):
            raise InvalidTransition("evidence timestamp moved backwards")
        evidence = EvidenceRecord(
            evidence_id,
            call.run_id,
            call.call_id,
            approval_id,
            call.tool,
            call.input_digest,
            call.actor,
            call.workspace,
            call.policy,
            approver,
            "tool_execution",
            outcome,
            body,
            body_digest,
            recorded_at,
        )
        if legacy_correlation is not None and legacy_request is not None:
            state.canonical_requests[legacy_correlation] = replace(
                legacy_request, evidence_id=evidence_id
            )
            state.legacy_unbound_canonical_requests.remove(legacy_correlation)
        state.evidence[evidence_id] = evidence
        state.tool_calls[call.call_id] = replace(
            call, state=expected_state, updated_at=recorded_at
        )
        return

    if kind == "memory_record" and action == "created":
        _require_exact_keys(
            payload,
            (
                "memory_id",
                "memory_op_id",
                "run_id",
                "call_id",
                "decision_id",
                "evidence_id",
                "tool",
                "input_digest",
                "actor",
                "workspace",
                "policy",
                "policy_authority",
                "project_digest",
                "session_id",
                "record_type",
                "key_sha256",
                "value_sha256",
                "value_bytes",
                "trust_label",
                "authoritative",
                "retention_class",
                "expires_at",
                "created_at",
            ),
        )
        memory_id = _validate_id(payload["memory_id"], "memory_id")
        memory_op_id = _validate_id(payload["memory_op_id"], "memory_op_id")
        if memory_id in state.memory_records or any(
            item.memory_op_id == memory_op_id
            for item in list(state.memory_records.values())
            + list(state.handoff_records.values())
        ):
            raise AlreadyExists("memory aggregate identity already exists")
        call = _require_call(state, _validate_id(payload["call_id"], "call_id"))
        evidence_id = _validate_id(payload["evidence_id"], "evidence_id")
        try:
            evidence = state.evidence[evidence_id]
        except KeyError as exc:
            raise NotFound("memory Evidence not found") from exc
        decision_id = _validate_id(payload["decision_id"], "decision_id")
        try:
            decision = state.policy_decisions[decision_id]
        except KeyError as exc:
            raise NotFound("memory policy decision not found") from exc
        receipt_value = evidence.body.get("project_memory_receipt")
        if not isinstance(receipt_value, dict):
            raise BindingMismatch("MemoryRecord lacks a durable executor receipt")
        from .memory import validate_durable_project_memory_receipt

        receipt = validate_durable_project_memory_receipt(
            receipt_value,
            run_id=call.run_id,
            call_id=call.call_id,
            decision_id=decision_id,
            evidence_id=evidence_id,
            tool=call.tool,
            input_digest=call.input_digest,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
            evidence_outcome=evidence.outcome,
        )
        if (
            evidence.call_id != call.call_id
            or evidence.outcome != "succeeded"
            or call.state != "succeeded"
            or decision.call_id != call.call_id
            or decision.outcome != "allow"
            or payload["run_id"] != call.run_id
            or payload["tool"] != call.tool
            or payload["input_digest"] != call.input_digest
            or payload["actor"] != call.actor
            or _normalize_workspace(payload["workspace"]) != call.workspace
            or payload["policy"] != call.policy
            or payload["policy_authority"] != decision.authority
            or call.effect != _PROJECT_MEMORY_EFFECT
            or call.tool not in _PROJECT_MEMORY_TOOLS
            or payload["memory_id"] != receipt["memory_id"]
            or payload["memory_op_id"] != receipt["memory_op_id"]
            or payload["project_digest"] != receipt["project_digest"]
            or payload["session_id"] != receipt["session_id"]
            or payload["record_type"] != receipt["record_type"]
            or payload["key_sha256"] != receipt["key_sha256"]
            or payload["value_sha256"] != receipt["value_sha256"]
            or payload["value_bytes"] != receipt["value_bytes"]
            or payload["retention_class"] != receipt["retention_class"]
            or payload["expires_at"] != receipt["expires_at"]
        ):
            raise BindingMismatch("MemoryRecord provenance does not match its call")
        if payload["trust_label"] != "kernel_bound" or payload["authoritative"] is not False:
            raise BindingMismatch("MemoryRecord cannot create authority")
        record_type = payload["record_type"]
        if record_type not in (
            "session_ensure",
            "checkpoint",
            "discovery",
            "progress",
            "session_close",
        ):
            raise ValidationError("MemoryRecord type is unsupported")
        key_digest = payload["key_sha256"]
        if key_digest is not None:
            key_digest = _validate_digest(key_digest, "key_sha256")
        value_digest = _validate_digest(payload["value_sha256"], "value_sha256")
        value_bytes = payload["value_bytes"]
        if type(value_bytes) is not int or not 0 <= value_bytes <= 32768:
            raise ValidationError("MemoryRecord value size is invalid")
        retention = payload["retention_class"]
        if retention not in ("session", "project", "expiring"):
            raise ValidationError("MemoryRecord retention class is invalid")
        expires_value = payload["expires_at"]
        memory_expires_at: Optional[str] = None
        if expires_value is not None:
            memory_expires_at = _normalize_timestamp(expires_value, "expires_at")
            if memory_expires_at != expires_value:
                raise ValidationError("MemoryRecord expiry is not canonical")
        if (retention == "expiring") != (memory_expires_at is not None):
            raise ValidationError("MemoryRecord expiry and retention disagree")
        created_at = _normalize_timestamp(payload["created_at"], "created_at")
        if created_at != payload["created_at"]:
            raise ValidationError("MemoryRecord timestamp is not canonical")
        state.memory_records[memory_id] = MemoryRecord(
            memory_id,
            memory_op_id,
            call.run_id,
            call.call_id,
            decision.decision_id,
            evidence.evidence_id,
            call.tool,
            call.input_digest,
            call.actor,
            call.workspace,
            call.policy,
            decision.authority,
            _validate_digest(payload["project_digest"], "project_digest"),
            _validate_id(payload["session_id"], "session_id"),
            record_type,
            key_digest,
            value_digest,
            value_bytes,
            "kernel_bound",
            False,
            retention,
            memory_expires_at,
            created_at,
        )
        return

    if kind == "handoff_record" and action == "created":
        _require_exact_keys(
            payload,
            (
                "handoff_id",
                "memory_op_id",
                "run_id",
                "call_id",
                "decision_id",
                "evidence_id",
                "tool",
                "input_digest",
                "actor",
                "workspace",
                "policy",
                "policy_authority",
                "project_digest",
                "session_id",
                "recipient_sha256",
                "summary_sha256",
                "summary_bytes",
                "trust_label",
                "authoritative",
                "retention_class",
                "expires_at",
                "created_at",
            ),
        )
        handoff_id = _validate_id(payload["handoff_id"], "handoff_id")
        memory_op_id = _validate_id(payload["memory_op_id"], "memory_op_id")
        if handoff_id in state.handoff_records or any(
            item.memory_op_id == memory_op_id
            for item in list(state.memory_records.values())
            + list(state.handoff_records.values())
        ):
            raise AlreadyExists("handoff aggregate identity already exists")
        call = _require_call(state, _validate_id(payload["call_id"], "call_id"))
        evidence_id = _validate_id(payload["evidence_id"], "evidence_id")
        decision_id = _validate_id(payload["decision_id"], "decision_id")
        try:
            evidence = state.evidence[evidence_id]
            decision = state.policy_decisions[decision_id]
        except KeyError as exc:
            raise NotFound("handoff provenance is unavailable") from exc
        receipt_value = evidence.body.get("project_memory_receipt")
        if not isinstance(receipt_value, dict):
            raise BindingMismatch("HandoffRecord lacks a durable executor receipt")
        from .memory import validate_durable_project_memory_receipt

        receipt = validate_durable_project_memory_receipt(
            receipt_value,
            run_id=call.run_id,
            call_id=call.call_id,
            decision_id=decision_id,
            evidence_id=evidence_id,
            tool=call.tool,
            input_digest=call.input_digest,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
            evidence_outcome=evidence.outcome,
        )
        if (
            evidence.call_id != call.call_id
            or evidence.outcome != "succeeded"
            or call.state != "succeeded"
            or decision.call_id != call.call_id
            or decision.outcome != "allow"
            or payload["run_id"] != call.run_id
            or payload["tool"] != call.tool
            or call.tool != "mainframe.project_memory.handoff.v1"
            or payload["input_digest"] != call.input_digest
            or payload["actor"] != call.actor
            or _normalize_workspace(payload["workspace"]) != call.workspace
            or payload["policy"] != call.policy
            or payload["policy_authority"] != decision.authority
            or call.effect != _PROJECT_MEMORY_EFFECT
            or payload["handoff_id"] != receipt["handoff_id"]
            or payload["memory_op_id"] != receipt["memory_op_id"]
            or payload["project_digest"] != receipt["project_digest"]
            or payload["session_id"] != receipt["session_id"]
            or payload["recipient_sha256"] != receipt["recipient_sha256"]
            or payload["summary_sha256"] != receipt["value_sha256"]
            or payload["summary_bytes"] != receipt["value_bytes"]
            or payload["retention_class"] != receipt["retention_class"]
            or payload["expires_at"] != receipt["expires_at"]
        ):
            raise BindingMismatch("HandoffRecord provenance does not match its call")
        if payload["trust_label"] != "kernel_bound" or payload["authoritative"] is not False:
            raise BindingMismatch("HandoffRecord cannot create authority")
        summary_bytes = payload["summary_bytes"]
        if type(summary_bytes) is not int or not 0 <= summary_bytes <= 32768:
            raise ValidationError("handoff summary size is invalid")
        retention = payload["retention_class"]
        if retention not in ("session", "project", "expiring"):
            raise ValidationError("handoff retention class is invalid")
        expires_value = payload["expires_at"]
        handoff_expires_at: Optional[str] = None
        if expires_value is not None:
            handoff_expires_at = _normalize_timestamp(expires_value, "expires_at")
            if handoff_expires_at != expires_value:
                raise ValidationError("handoff expiry is not canonical")
        if (retention == "expiring") != (handoff_expires_at is not None):
            raise ValidationError("handoff expiry and retention disagree")
        created_at = _normalize_timestamp(payload["created_at"], "created_at")
        if created_at != payload["created_at"]:
            raise ValidationError("handoff timestamp is not canonical")
        state.handoff_records[handoff_id] = HandoffRecord(
            handoff_id,
            memory_op_id,
            call.run_id,
            call.call_id,
            decision.decision_id,
            evidence.evidence_id,
            call.tool,
            call.input_digest,
            call.actor,
            call.workspace,
            call.policy,
            decision.authority,
            _validate_digest(payload["project_digest"], "project_digest"),
            _validate_id(payload["session_id"], "session_id"),
            _validate_digest(payload["recipient_sha256"], "recipient_sha256"),
            _validate_digest(payload["summary_sha256"], "summary_sha256"),
            summary_bytes,
            "kernel_bound",
            False,
            retention,
            handoff_expires_at,
            created_at,
        )
        return

    raise ValidationError("unsupported event: {}.{}".format(kind, action))


@dataclass
class _PreparedDisposableWrite:
    parent_fd: int
    target_name: str
    relative_path: str
    content: bytes

    def close(self) -> None:
        if self.parent_fd >= 0:
            os.close(self.parent_fd)
            self.parent_fd = -1


def _directory_open_flags() -> int:
    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY"):
        raise ExecutionDenied("symlink-safe directory traversal is unavailable")
    return os.O_RDONLY | os.O_CLOEXEC | os.O_DIRECTORY | os.O_NOFOLLOW


def _open_absolute_directory_without_symlinks(path: str) -> int:
    path = _normalize_workspace(path)
    flags = _directory_open_flags()
    try:
        current = os.open("/", flags)
    except OSError as exc:
        raise ExecutionDenied("unable to open filesystem root safely") from exc
    try:
        for component in path.split("/"):
            if not component:
                continue
            try:
                following = os.open(component, flags, dir_fd=current)
            except OSError as exc:
                raise ExecutionDenied(
                    "workspace contains an unavailable or symbolic-link component"
                ) from exc
            os.close(current)
            current = following
        return current
    except BaseException:
        os.close(current)
        raise


def _read_exact_disposable_sentinel(workspace_fd: int) -> None:
    flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW
    try:
        sentinel_fd = os.open(DISPOSABLE_SENTINEL_NAME, flags, dir_fd=workspace_fd)
    except OSError as exc:
        raise ExecutionDenied("workspace is not marked disposable by the exact sentinel") from exc
    try:
        metadata = os.fstat(sentinel_fd)
        if not stat.S_ISREG(metadata.st_mode):
            raise ExecutionDenied("disposable workspace sentinel must be a regular file")
        observed = b""
        while len(observed) <= len(DISPOSABLE_SENTINEL_CONTENT):
            chunk = os.read(sentinel_fd, len(DISPOSABLE_SENTINEL_CONTENT) + 1)
            if not chunk:
                break
            observed += chunk
        if observed != DISPOSABLE_SENTINEL_CONTENT:
            raise ExecutionDenied("workspace disposable sentinel content does not match")
    finally:
        os.close(sentinel_fd)


def _prepare_disposable_write(call: ToolCallRecord) -> _PreparedDisposableWrite:
    if call.tool != DISPOSABLE_WRITE_TOOL or call.effect != "mutating":
        raise ExecutionDenied("only the fixed disposable-write tool may mutate files")
    if call.tool_input is None:
        raise ExecutionDenied("disposable write input is unavailable")
    tool_input = _validate_disposable_write_input(call.tool_input)
    relative_path = tool_input["path"]
    content = tool_input["content"]
    if not isinstance(relative_path, str) or not isinstance(content, str):
        raise ExecutionDenied("disposable write input types changed after validation")

    workspace_fd = _open_absolute_directory_without_symlinks(call.workspace)
    parent_fd = -1
    try:
        _read_exact_disposable_sentinel(workspace_fd)
        parent_fd = os.dup(workspace_fd)
        parts = relative_path.split("/")
        for component in parts[:-1]:
            try:
                following = os.open(component, _directory_open_flags(), dir_fd=parent_fd)
            except OSError as exc:
                raise ExecutionDenied(
                    "disposable write parent contains a symlink or non-directory"
                ) from exc
            os.close(parent_fd)
            parent_fd = following
        target_name = parts[-1]
        try:
            target = os.stat(target_name, dir_fd=parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            target = None
        except OSError as exc:
            raise ExecutionDenied("unable to inspect disposable write target safely") from exc
        if target is not None and not stat.S_ISREG(target.st_mode):
            raise ExecutionDenied("disposable write target must be absent or a regular file")
        prepared = _PreparedDisposableWrite(
            parent_fd=parent_fd,
            target_name=target_name,
            relative_path=relative_path,
            content=content.encode("utf-8"),
        )
        parent_fd = -1
        return prepared
    finally:
        if parent_fd >= 0:
            os.close(parent_fd)
        os.close(workspace_fd)


def _atomic_disposable_replace(prepared: _PreparedDisposableWrite) -> Dict[str, JsonValue]:
    temporary_name = ".mainframe-disposable-{}.tmp".format(uuid.uuid4().hex)
    temporary_fd = -1
    replaced = False
    try:
        temporary_fd = os.open(
            temporary_name,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW,
            0o600,
            dir_fd=prepared.parent_fd,
        )
        offset = 0
        while offset < len(prepared.content):
            written = os.write(temporary_fd, prepared.content[offset:])
            if written <= 0:
                raise OSError("disposable write made no progress")
            offset += written
        os.fsync(temporary_fd)
        os.close(temporary_fd)
        temporary_fd = -1
        os.replace(
            temporary_name,
            prepared.target_name,
            src_dir_fd=prepared.parent_fd,
            dst_dir_fd=prepared.parent_fd,
        )
        replaced = True
        os.fsync(prepared.parent_fd)
        return {
            "operation": "atomic_replace",
            "relative_path": prepared.relative_path,
            "bytes_written": len(prepared.content),
            "content_digest": hashlib.sha256(prepared.content).hexdigest(),
        }
    except Exception as exc:
        setattr(exc, "mainframe_write_may_have_committed", replaced)
        raise
    finally:
        if temporary_fd >= 0:
            os.close(temporary_fd)
        if not replaced:
            try:
                os.unlink(temporary_name, dir_fd=prepared.parent_fd)
            except FileNotFoundError:
                pass
            except OSError:
                pass


class _EventLedger:
    def __init__(self, path: Union[str, os.PathLike[str]]) -> None:
        self.path = Path(path)

    @staticmethod
    def _validate_file(fd: int) -> None:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode):
            raise LedgerCorruption("ledger must be a regular file")
        if hasattr(os, "geteuid") and metadata.st_uid != os.geteuid():
            raise LedgerCorruption("ledger must be owned by the current user")
        if stat.S_IMODE(metadata.st_mode) & 0o077:
            raise LedgerCorruption("ledger permissions must not grant group or other access")
        if metadata.st_size > MAX_LEDGER_BYTES:
            raise LedgerCorruption("ledger exceeds the maximum supported size")

    @staticmethod
    def _read_fd(fd: int) -> bytes:
        os.lseek(fd, 0, os.SEEK_SET)
        chunks = []
        total = 0
        while True:
            chunk = os.read(fd, 65536)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_LEDGER_BYTES:
                raise LedgerCorruption("ledger exceeds the maximum supported size")
            chunks.append(chunk)
        return b"".join(chunks)

    @classmethod
    def _read_and_repair_final_frame(cls, fd: int) -> bytes:
        """Repair only a non-newline final frame after verifying its prefix.

        This recovers a process killed during append.  It intentionally cannot
        distinguish that case from deletion of the final event plus a partial
        replacement; deployments needing deletion detection require an
        external anchored head digest.
        """
        data = cls._read_fd(fd)
        if not data or data.endswith(b"\n"):
            return data
        final_newline = data.rfind(b"\n")
        prefix_length = final_newline + 1
        prefix = data[:prefix_length]
        cls._parse(prefix)
        try:
            os.ftruncate(fd, prefix_length)
            os.fsync(fd)
        except OSError as exc:
            raise LedgerIOError("unable to repair truncated final ledger frame") from exc
        return prefix

    @staticmethod
    def _parse(data: bytes) -> _State:
        if not data:
            return _empty_state()
        if not data.endswith(b"\n"):
            raise LedgerCorruption("ledger has a truncated final record")
        state = _empty_state()
        expected_previous = None
        expected_sequence = 1
        for raw_line in data.splitlines():
            if not raw_line or len(raw_line) > MAX_EVENT_BYTES:
                raise LedgerCorruption("ledger contains an empty or oversized event")
            try:
                line = raw_line.decode("utf-8")
                event = json.loads(line)
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise LedgerCorruption("ledger contains invalid JSON") from exc
            if not isinstance(event, dict):
                raise LedgerCorruption("ledger event must be an object")
            expected_keys = {
                "schema_version",
                "sequence",
                "event_id",
                "previous_digest",
                "recorded_at",
                "kind",
                "action",
                "payload",
                "digest",
            }
            if set(event) != expected_keys:
                raise LedgerCorruption("ledger event envelope keys differ")
            try:
                if _canonical_json(event) != raw_line:
                    raise LedgerCorruption("ledger event is not canonical JSON")
            except ValidationError as exc:
                raise LedgerCorruption("ledger event is not canonical JSON") from exc
            if (
                type(event["schema_version"]) is not int
                or event["schema_version"] != SCHEMA_VERSION
            ):
                raise LedgerCorruption("unsupported ledger schema version")
            if type(event["sequence"]) is not int or event["sequence"] != expected_sequence:
                raise LedgerCorruption("ledger sequence is not contiguous")
            event_id = event["event_id"]
            try:
                _validate_id(event_id, "event_id")
            except ValidationError as exc:
                raise LedgerCorruption(str(exc)) from exc
            if event_id in state.event_ids:
                raise LedgerCorruption("ledger contains a duplicate event_id")
            if event["previous_digest"] != expected_previous:
                raise LedgerCorruption("ledger digest chain is broken")
            base = dict(event)
            digest = base.pop("digest")
            try:
                _validate_digest(digest, "event digest")
                recorded_at = _normalize_timestamp(event["recorded_at"], "recorded_at")
            except ValidationError as exc:
                raise LedgerCorruption(str(exc)) from exc
            if recorded_at != event["recorded_at"] or _object_digest(base) != digest:
                raise LedgerCorruption("ledger event digest does not verify")
            try:
                _reduce(state, event)
            except ControlPlaneError as exc:
                raise LedgerCorruption(
                    "ledger event {} violates state invariants: {}".format(
                        expected_sequence, exc
                    )
                ) from exc
            state.event_ids.add(event_id)
            state.event_count = expected_sequence
            state.head_digest = digest
            expected_previous = digest
            expected_sequence += 1
        return state

    def _open(self, create: bool) -> int:
        parent = self.path.parent
        if not parent.is_dir():
            raise LedgerIOError("ledger parent directory does not exist")
        flags = os.O_CLOEXEC | os.O_RDWR
        if create:
            flags |= os.O_CREAT | os.O_APPEND
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        try:
            return os.open(str(self.path), flags, 0o600)
        except FileNotFoundError:
            raise
        except OSError as exc:
            if exc.errno in (errno.ELOOP, errno.EMLINK):
                raise LedgerCorruption("ledger path must not be a symbolic link") from exc
            raise LedgerIOError("unable to open ledger: {}".format(exc)) from exc

    def load(self) -> _State:
        try:
            fd = self._open(create=False)
        except FileNotFoundError:
            return _empty_state()
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            self._validate_file(fd)
            return self._parse(self._read_and_repair_final_frame(fd))
        finally:
            try:
                fcntl.flock(fd, fcntl.LOCK_UN)
            finally:
                os.close(fd)

    def transact(
        self,
        recorded_at: str,
        builder: Callable[[_State], Tuple[str, str, Dict[str, Any]]],
    ) -> _State:
        fd = self._open(create=True)
        try:
            # Persist the ledger name before appending the first event. Doing
            # this on every transaction also safely retries a prior fsync error.
            fsync_directory(self.path.parent)
            fcntl.flock(fd, fcntl.LOCK_EX)
            self._validate_file(fd)
            state = self._parse(self._read_and_repair_final_frame(fd))
            kind, action, payload = builder(state)
            event: Dict[str, Any] = {
                "schema_version": SCHEMA_VERSION,
                "sequence": state.event_count + 1,
                "event_id": "evt-{}".format(uuid.uuid4().hex),
                "previous_digest": state.head_digest,
                "recorded_at": recorded_at,
                "kind": _validate_text(kind, "event kind", 64),
                "action": _validate_text(action, "event action", 64),
                "payload": _normalized_object(payload, "event payload"),
            }
            event["digest"] = _object_digest(event)
            encoded = _canonical_json(event) + b"\n"
            if len(encoded) > MAX_EVENT_BYTES:
                raise ValidationError("event exceeds the maximum supported size")
            _reduce(state, event)
            offset = 0
            while offset < len(encoded):
                written = os.write(fd, encoded[offset:])
                if written <= 0:
                    raise LedgerIOError("ledger append made no progress")
                offset += written
            os.fsync(fd)
            state.event_ids.add(event["event_id"])
            state.event_count = event["sequence"]
            state.head_digest = event["digest"]
            return state
        except OSError as exc:
            raise LedgerIOError("unable to append ledger event: {}".format(exc)) from exc
        finally:
            try:
                fcntl.flock(fd, fcntl.LOCK_UN)
            finally:
                os.close(fd)


class ControlPlaneKernel:
    """Replayable control-plane state machine backed by an append-only ledger."""

    def __init__(
        self,
        ledger_path: Union[str, os.PathLike[str]],
        *,
        clock: Clock = _system_clock,
        evaluator: Optional[PolicyEvaluator] = None,
        stable_core_registry: Optional["StableCoreRegistry"] = None,
    ) -> None:
        self._ledger = _EventLedger(ledger_path)
        self._clock = clock
        self._evaluator = evaluator
        self._stable_core_registry = stable_core_registry

    @property
    def ledger_path(self) -> Path:
        return self._ledger.path

    def _now(self) -> str:
        return _format_timestamp(self._clock())

    @staticmethod
    def _snapshot(state: _State) -> Snapshot:
        return Snapshot(
            dict(state.canonical_requests),
            dict(state.runs),
            dict(state.tool_calls),
            dict(state.policy_decisions),
            dict(state.approvals),
            dict(state.evidence),
            dict(state.memory_records),
            dict(state.handoff_records),
            state.event_count,
            state.head_digest,
        )

    def snapshot(self) -> Snapshot:
        return self._snapshot(self._ledger.load())

    def reserve_canonical_request(
        self,
        *,
        client_correlation_id: str,
        canonical_id: str,
        tool_input: Mapping[str, JsonValue],
        actor: str,
        workspace: str,
        policy: str,
    ) -> CanonicalRequestRecord:
        client_correlation_id = _validate_id(
            client_correlation_id, "client_correlation_id"
        )
        canonical_id = _validate_text(canonical_id, "canonical_id")
        normalized_input = _normalized_object(tool_input, "tool input")
        input_digest = normalized_input_digest(normalized_input)
        input_metadata = normalized_input_metadata(normalized_input)
        actor = _validate_text(actor, "actor")
        workspace = _canonicalize_workspace(workspace)
        policy = _validate_text(policy, "policy")
        run_id = "run-{}".format(uuid.uuid4().hex)
        call_id = "call-{}".format(uuid.uuid4().hex)
        decision_id = "decision-{}".format(uuid.uuid4().hex)
        evidence_id = "evidence-{}".format(uuid.uuid4().hex)
        now = self._now()

        def build(_state: _State) -> Tuple[str, str, Dict[str, Any]]:
            return "canonical_request", "reserved", {
                "client_correlation_id": client_correlation_id,
                "run_id": run_id,
                "call_id": call_id,
                "decision_id": decision_id,
                "evidence_id": evidence_id,
                "canonical_id": canonical_id,
                "input_digest": input_digest,
                "input_metadata": input_metadata,
                "actor": actor,
                "workspace": workspace,
                "policy": policy,
                "reservation_binding": None,
                "reserved_at": now,
            }

        state = self._ledger.transact(now, build)
        return state.canonical_requests[client_correlation_id]

    def _reserve_project_memory_request(
        self,
        *,
        client_correlation_id: str,
        tool: str,
        tool_input: Mapping[str, JsonValue],
        actor: str,
        workspace: str,
        policy: str,
        reservation_binding: Mapping[str, JsonValue],
    ) -> CanonicalRequestRecord:
        """Atomically bind project observation, identities, and input metadata."""
        from .memory import (
            FixedProjectMemoryRegistry,
            PROJECT_MEMORY_POLICY,
            parse_project_memory_reservation_binding,
        )

        client_correlation_id = _validate_id(
            client_correlation_id, "client_correlation_id"
        )
        registry = FixedProjectMemoryRegistry()
        registry.contract(tool)
        normalized_input = registry.normalize_input(tool, tool_input)
        actor = _validate_text(actor, "actor")
        workspace = _canonicalize_workspace(workspace)
        if policy != PROJECT_MEMORY_POLICY:
            raise BindingMismatch("project-memory reservation policy is not fixed")
        binding = _normalized_object(reservation_binding, "reservation binding")
        observation, _retention, _expires = parse_project_memory_reservation_binding(
            binding
        )
        expected_project = hashlib.sha256(workspace.encode("utf-8")).hexdigest()
        if observation.project_digest != expected_project:
            raise BindingMismatch("project-memory observation workspace changed")
        run_id = "run-{}".format(uuid.uuid4().hex)
        call_id = "call-{}".format(uuid.uuid4().hex)
        decision_id = "decision-{}".format(uuid.uuid4().hex)
        evidence_id = "evidence-{}".format(uuid.uuid4().hex)
        now = self._now()

        def build(_state: _State) -> Tuple[str, str, Dict[str, Any]]:
            return "canonical_request", "reserved", {
                "client_correlation_id": client_correlation_id,
                "run_id": run_id,
                "call_id": call_id,
                "decision_id": decision_id,
                "evidence_id": evidence_id,
                "canonical_id": tool,
                "input_digest": normalized_input_digest(normalized_input),
                "input_metadata": normalized_input_metadata(normalized_input),
                "actor": actor,
                "workspace": workspace,
                "policy": PROJECT_MEMORY_POLICY,
                "reservation_binding": binding,
                "reserved_at": now,
            }

        state = self._ledger.transact(now, build)
        return state.canonical_requests[client_correlation_id]

    def lookup(
        self, record_kind: str, record_id: str
    ) -> Union[
        RunRecord,
        ToolCallRecord,
        PolicyDecisionRecord,
        ApprovalRecord,
        EvidenceRecord,
        MemoryRecord,
        HandoffRecord,
    ]:
        record_kind = _validate_text(record_kind, "record kind", 32)
        record_id = _validate_id(record_id, "record_id")
        state = self._ledger.load()
        collections: Dict[str, Mapping[str, Any]] = {
            "run": state.runs,
            "tool_call": state.tool_calls,
            "policy_decision": state.policy_decisions,
            "approval": state.approvals,
            "evidence": state.evidence,
            "memory": state.memory_records,
            "handoff": state.handoff_records,
        }
        try:
            records = collections[record_kind]
        except KeyError as exc:
            raise ValidationError("unsupported record kind: {}".format(record_kind)) from exc
        try:
            return cast(
                Union[
                    RunRecord,
                    ToolCallRecord,
                    PolicyDecisionRecord,
                    ApprovalRecord,
                    EvidenceRecord,
                    MemoryRecord,
                    HandoffRecord,
                ],
                records[record_id],
            )
        except KeyError as exc:
            raise NotFound(
                "{} not found: {}".format(record_kind.replace("_", " "), record_id)
            ) from exc

    def create_run(
        self, *, run_id: str, actor: str, workspace: str, policy: str
    ) -> RunRecord:
        run_id = _validate_id(run_id, "run_id")
        actor = _validate_text(actor, "actor")
        workspace = _canonicalize_workspace(workspace)
        policy = _validate_text(policy, "policy")
        now = self._now()

        def build(_state: _State) -> Tuple[str, str, Dict[str, Any]]:
            return "run", "created", {
                "run_id": run_id,
                "actor": actor,
                "workspace": workspace,
                "policy": policy,
                "state": "created",
                "created_at": now,
            }

        state = self._ledger.transact(now, build)
        return state.runs[run_id]

    def transition_run(self, run_id: str, to_state: str) -> RunRecord:
        run_id = _validate_id(run_id, "run_id")
        to_state = _validate_text(to_state, "run state", 32)
        now = self._now()

        def build(state: _State) -> Tuple[str, str, Dict[str, Any]]:
            run = _require_run(state, run_id)
            return "run", "transitioned", {
                "run_id": run_id,
                "from_state": run.state,
                "to_state": to_state,
                "updated_at": now,
            }

        state = self._ledger.transact(now, build)
        return state.runs[run_id]

    def create_tool_call(
        self,
        *,
        call_id: str,
        run_id: str,
        tool: str,
        tool_input: Mapping[str, JsonValue],
        effect: str,
        timeout_at: Optional[Union[str, datetime]] = None,
        client_correlation_id: Optional[str] = None,
        persist_input: bool = True,
    ) -> ToolCallRecord:
        call_id = _validate_id(call_id, "call_id")
        run_id = _validate_id(run_id, "run_id")
        tool = _validate_text(tool, "tool")
        normalized_input = _normalized_object(tool_input, "tool input")
        if tool == DISPOSABLE_WRITE_TOOL:
            normalized_input = _validate_disposable_write_input(normalized_input)
        input_digest = normalized_input_digest(normalized_input)
        input_metadata = normalized_input_metadata(normalized_input)
        if effect not in (
            "read_only",
            "mutating",
            _CODING_EXECUTION_EFFECT,
            _PROJECT_MEMORY_EFFECT,
        ):
            raise ValidationError("effect is unsupported")
        if effect == _PROJECT_MEMORY_EFFECT and tool not in _PROJECT_MEMORY_TOOLS:
            raise ExecutionDenied("non-authoritative memory effect requires a fixed tool")
        if client_correlation_id is not None:
            client_correlation_id = _validate_id(
                client_correlation_id, "client_correlation_id"
            )
        now = self._now()
        timeout_at_text = (
            None
            if timeout_at is None
            else _normalize_timestamp(timeout_at, "timeout_at")
        )
        if timeout_at_text is not None and _parse_timestamp(
            timeout_at_text, "timeout_at"
        ) <= _parse_timestamp(now, "created_at"):
            raise InvalidTransition("tool call timeout must follow its creation")

        def build(state: _State) -> Tuple[str, str, Dict[str, Any]]:
            run = _require_run(state, run_id)
            return "tool_call", "created", {
                "call_id": call_id,
                "run_id": run_id,
                "tool": tool,
                "tool_input": normalized_input if persist_input else None,
                "input_metadata": input_metadata,
                "input_digest": input_digest,
                "actor": run.actor,
                "workspace": run.workspace,
                "policy": run.policy,
                "effect": effect,
                "timeout_at": timeout_at_text,
                "client_correlation_id": client_correlation_id,
                "state": "pending",
                "created_at": now,
            }

        state = self._ledger.transact(now, build)
        return state.tool_calls[call_id]

    def _registry(self) -> "StableCoreRegistry":
        if self._stable_core_registry is None:
            from .contracts import load_fixed_stable_core_registry

            self._stable_core_registry = load_fixed_stable_core_registry()
        return self._stable_core_registry

    def create_canonical_tool_call(
        self,
        *,
        call_id: str,
        run_id: str,
        canonical_id: str,
        tool_input: Mapping[str, JsonValue],
        client_correlation_id: Optional[str] = None,
    ) -> ToolCallRecord:
        registry = self._registry()
        contract = registry.contract(canonical_id)
        normalized_input = registry.normalize_input(canonical_id, tool_input)
        deadline = self._clock() + timedelta(milliseconds=contract.timeout_ms)
        return self.create_tool_call(
            call_id=call_id,
            run_id=run_id,
            tool=canonical_id,
            tool_input=normalized_input,
            effect="read_only",
            timeout_at=deadline,
            client_correlation_id=client_correlation_id,
            persist_input=client_correlation_id is None,
        )

    def _create_coding_tool_call(
        self,
        *,
        call_id: str,
        run_id: str,
        tool: str,
        tool_input: Mapping[str, JsonValue],
        client_correlation_id: str,
    ) -> ToolCallRecord:
        """Create one ephemeral-input call from the fixed coding registry."""
        from .coding import FixedCodingRegistry

        registry = FixedCodingRegistry()
        contract = registry.contract(tool)
        normalized_input = registry.normalize_input(tool, tool_input)
        deadline = self._clock() + timedelta(milliseconds=contract.timeout_ms)
        return self.create_tool_call(
            call_id=call_id,
            run_id=run_id,
            tool=tool,
            tool_input=normalized_input,
            effect=contract.effect,
            timeout_at=deadline,
            client_correlation_id=client_correlation_id,
            persist_input=False,
        )

    def _create_project_memory_tool_call(
        self,
        *,
        call_id: str,
        run_id: str,
        tool: str,
        tool_input: Mapping[str, JsonValue],
        client_correlation_id: str,
    ) -> ToolCallRecord:
        """Create one metadata-only call from the exact project-memory registry."""
        from .memory import FixedProjectMemoryRegistry

        registry = FixedProjectMemoryRegistry()
        contract = registry.contract(tool)
        normalized_input = registry.normalize_input(tool, tool_input)
        deadline = self._clock() + timedelta(milliseconds=contract.timeout_ms)
        return self.create_tool_call(
            call_id=call_id,
            run_id=run_id,
            tool=tool,
            tool_input=normalized_input,
            effect=contract.effect,
            timeout_at=deadline,
            client_correlation_id=client_correlation_id,
            persist_input=False,
        )

    def request_approval(self, call_id: str) -> ToolCallRecord:
        _validate_id(call_id, "call_id")
        raise ExecutionDenied(
            "direct approval requests are disabled; record an immutable policy decision"
        )

    def evaluate_policy_decision(
        self,
        *,
        decision_id: str,
        call_id: str,
        tool: str,
        input_digest: str,
        actor: str,
        workspace: str,
        policy: str,
        timeout_at: Optional[Union[str, datetime]],
        tool_input: Optional[Mapping[str, JsonValue]] = None,
    ) -> PolicyDecisionRecord:
        decision_id = _validate_id(decision_id, "decision_id")
        call_id = _validate_id(call_id, "call_id")
        tool = _validate_text(tool, "tool")
        input_digest = _validate_digest(input_digest, "input_digest")
        actor = _validate_text(actor, "actor")
        workspace = _canonicalize_workspace(workspace)
        policy = _validate_text(policy, "policy")
        timeout_at_text = (
            None
            if timeout_at is None
            else _normalize_timestamp(timeout_at, "timeout_at")
        )
        if self._evaluator is None:
            raise EvaluatorUnavailable("no trusted policy evaluator was injected")
        snapshot = self.snapshot()
        try:
            call = snapshot.tool_calls[call_id]
        except KeyError as exc:
            raise NotFound("tool call not found: {}".format(call_id)) from exc
        _assert_call_binding(
            call,
            call_id=call_id,
            tool=tool,
            input_digest=input_digest,
            actor=actor,
            workspace=workspace,
            policy=policy,
        )
        if timeout_at_text != call.timeout_at:
            raise BindingMismatch("policy evaluation timeout does not match the tool call")
        if tool_input is None:
            if call.tool_input is None:
                raise BindingMismatch(
                    "canonical policy evaluation requires exact transient input"
                )
            evaluation_input = _normalized_object(call.tool_input, "tool input")
        else:
            evaluation_input = _normalized_object(tool_input, "tool input")
        if (
            normalized_input_digest(evaluation_input) != call.input_digest
            or normalized_input_metadata(evaluation_input) != call.input_metadata
        ):
            raise BindingMismatch("transient policy input does not match the tool call")
        evaluation = self._evaluator(
            PolicyRequest(
                call.call_id,
                call.run_id,
                call.tool,
                evaluation_input,
                call.input_digest,
                call.actor,
                call.workspace,
                call.policy,
                call.effect,
                call.timeout_at,
                call.client_correlation_id,
            )
        )
        if not isinstance(evaluation, PolicyEvaluation):
            raise ValidationError("policy evaluator returned an unsupported result")
        outcome = evaluation.outcome
        if outcome not in ("allow", "deny", "approval_required"):
            raise ValidationError("policy evaluator returned an unsupported outcome")
        authority = _validate_text(evaluation.authority, "authority")
        if authority == call.actor:
            raise BindingMismatch("policy authority must be distinct from the caller actor")
        reason = _validate_text(evaluation.reason, "reason", 4096)
        now = self._now()

        def build(state: _State) -> Tuple[str, str, Dict[str, Any]]:
            call = _require_call(state, call_id)
            expected_state = {
                "allow": "ready",
                "deny": "denied",
                "approval_required": "awaiting_approval",
            }[outcome]
            return "policy_decision", "recorded", {
                "decision_id": decision_id,
                "call_id": call_id,
                "run_id": call.run_id,
                "tool": tool,
                "input_digest": input_digest,
                "actor": actor,
                "workspace": workspace,
                "policy": policy,
                "timeout_at": timeout_at_text,
                "outcome": outcome,
                "authority": authority,
                "reason": reason,
                "decided_at": now,
                "call_from_state": call.state,
                "call_to_state": expected_state,
            }

        state = self._ledger.transact(now, build)
        return state.policy_decisions[decision_id]

    def _resolve_tool_call(
        self,
        call_id: str,
        *,
        tool: str,
        input_digest: str,
        actor: str,
        workspace: str,
        policy: str,
        reason: str,
        to_state: str,
    ) -> ToolCallRecord:
        call_id = _validate_id(call_id, "call_id")
        tool = _validate_text(tool, "tool")
        input_digest = _validate_digest(input_digest, "input_digest")
        actor = _validate_text(actor, "actor")
        workspace = _canonicalize_workspace(workspace)
        policy = _validate_text(policy, "policy")
        reason = _validate_text(reason, "reason", 4096)
        now = self._now()

        def build(state: _State) -> Tuple[str, str, Dict[str, Any]]:
            call = _require_call(state, call_id)
            return "tool_call", "resolved", {
                "call_id": call_id,
                "tool": tool,
                "input_digest": input_digest,
                "actor": actor,
                "workspace": workspace,
                "policy": policy,
                "from_state": call.state,
                "to_state": to_state,
                "reason": reason,
                "updated_at": now,
            }

        state = self._ledger.transact(now, build)
        return state.tool_calls[call_id]

    def cancel_tool_call(
        self,
        call_id: str,
        *,
        tool: str,
        input_digest: str,
        actor: str,
        workspace: str,
        policy: str,
        reason: str,
    ) -> ToolCallRecord:
        return self._resolve_tool_call(
            call_id,
            tool=tool,
            input_digest=input_digest,
            actor=actor,
            workspace=workspace,
            policy=policy,
            reason=reason,
            to_state="cancelled",
        )

    def timeout_tool_call(
        self,
        call_id: str,
        *,
        tool: str,
        input_digest: str,
        actor: str,
        workspace: str,
        policy: str,
        reason: str,
    ) -> ToolCallRecord:
        return self._resolve_tool_call(
            call_id,
            tool=tool,
            input_digest=input_digest,
            actor=actor,
            workspace=workspace,
            policy=policy,
            reason=reason,
            to_state="timed_out",
        )

    def recover_tool_call(
        self,
        call_id: str,
        *,
        tool: str,
        input_digest: str,
        actor: str,
        workspace: str,
        policy: str,
        reason: str,
    ) -> ToolCallRecord:
        return self._resolve_tool_call(
            call_id,
            tool=tool,
            input_digest=input_digest,
            actor=actor,
            workspace=workspace,
            policy=policy,
            reason=reason,
            to_state="interrupted",
        )

    def grant_approval(
        self,
        *,
        approval_id: str,
        call_id: str,
        tool: str,
        input_digest: str,
        actor: str,
        workspace: str,
        policy: str,
        approver: str,
        expires_at: Union[str, datetime],
    ) -> ApprovalRecord:
        approval_id = _validate_id(approval_id, "approval_id")
        call_id = _validate_id(call_id, "call_id")
        tool = _validate_text(tool, "tool")
        input_digest = _validate_digest(input_digest, "input_digest")
        actor = _validate_text(actor, "actor")
        workspace = _canonicalize_workspace(workspace)
        policy = _validate_text(policy, "policy")
        approver = _validate_text(approver, "approver")
        if approver == actor:
            raise BindingMismatch("approver must be distinct from the caller actor")
        expires_at_text = _normalize_timestamp(expires_at, "expires_at")
        now = self._now()

        def build(state: _State) -> Tuple[str, str, Dict[str, Any]]:
            call = _require_call(state, call_id)
            return "approval", "granted", {
                "approval_id": approval_id,
                "call_id": call_id,
                "run_id": call.run_id,
                "tool": tool,
                "input_digest": input_digest,
                "actor": actor,
                "workspace": workspace,
                "policy": policy,
                "approver": approver,
                "expires_at": expires_at_text,
                "state": "granted",
                "granted_at": now,
            }

        state = self._ledger.transact(now, build)
        return state.approvals[approval_id]

    def bind_approval_grant_request(
        self,
        *,
        approval_id: str,
        call_id: str,
        tool: str,
        input_digest: str,
        actor: str,
        workspace: str,
        policy: str,
        expires_at: Union[str, datetime],
    ) -> ApprovalGrantRequest:
        """Validate an exact grant intent before exposing it to trusted authority.

        This is deliberately read-only.  The subsequent grant transaction repeats
        all state and binding checks under the ledger lock, closing the race between
        authority evaluation and durable append.
        """

        request = ApprovalGrantRequest(
            approval_id=_validate_id(approval_id, "approval_id"),
            call_id=_validate_id(call_id, "call_id"),
            tool=_validate_text(tool, "tool"),
            input_digest=_validate_digest(input_digest, "input_digest"),
            actor=_validate_text(actor, "actor"),
            workspace=_canonicalize_workspace(workspace),
            policy=_validate_text(policy, "policy"),
            expires_at=_normalize_timestamp(expires_at, "expires_at"),
        )
        state = self._ledger.load()
        if request.approval_id in state.approvals:
            raise AlreadyExists("approval already exists: {}".format(request.approval_id))
        call = _require_call(state, request.call_id)
        if call.state != "awaiting_approval":
            raise InvalidTransition("approval requires an awaiting tool call")
        decision = _decision_for_call(state, call.call_id)
        if decision is None or decision.outcome != "approval_required":
            raise ExecutionDenied(
                "approval requires an exact durable approval_required decision"
            )
        if _require_run(state, call.run_id).state != "active":
            raise InvalidTransition("approval requires an active run")
        if any(
            existing.call_id == call.call_id and existing.state == "granted"
            for existing in state.approvals.values()
        ):
            raise AlreadyExists("tool call already has an outstanding approval")
        if _parse_timestamp(request.expires_at, "expires_at") <= _parse_timestamp(
            self._now(), "current time"
        ):
            raise ApprovalExpired("approval must expire after it is granted")
        _assert_call_binding(
            call,
            call_id=request.call_id,
            tool=request.tool,
            input_digest=request.input_digest,
            actor=request.actor,
            workspace=request.workspace,
            policy=request.policy,
        )
        return request

    def consume_approval(
        self,
        approval_id: str,
        *,
        call_id: str,
        actor: str,
        workspace: str,
        policy: str,
    ) -> ApprovalRecord:
        approval_id = _validate_id(approval_id, "approval_id")
        call_id = _validate_id(call_id, "call_id")
        actor = _validate_text(actor, "actor")
        workspace = _canonicalize_workspace(workspace)
        policy = _validate_text(policy, "policy")
        now = self._now()

        def build(state: _State) -> Tuple[str, str, Dict[str, Any]]:
            approval = _require_approval(state, approval_id)
            call = _require_call(state, call_id)
            if call.tool in (
                DISPOSABLE_WRITE_TOOL,
                "mainframe.coding.atomic_edit.v1",
            ):
                raise ExecutionDenied(
                    "mutating approval is consumed only by its bound execution"
                )
            if approval.state == "consumed":
                raise ApprovalConsumed("approval was already consumed")
            if _parse_timestamp(now, "consumed_at") >= _parse_timestamp(
                approval.expires_at, "expires_at"
            ):
                raise ApprovalExpired("approval has expired")
            return "approval", "consumed", {
                "approval_id": approval_id,
                "call_id": call_id,
                "actor": actor,
                "workspace": workspace,
                "policy": policy,
                "approver": approval.approver,
                "reason": "authorization_only",
                "approval_from_state": approval.state,
                "approval_to_state": "consumed",
                "call_from_state": "awaiting_approval",
                "call_to_state": "authorized",
                "consumed_at": now,
            }

        state = self._ledger.transact(now, build)
        return state.approvals[approval_id]

    def _record_execution_evidence(
        self,
        *,
        call_id: str,
        approval_id: Optional[str],
        body: Mapping[str, JsonValue],
        outcome: str,
    ) -> EvidenceRecord:
        normalized_body = _normalized_object(body, "evidence body")
        snapshot = self.snapshot()
        call_id = _validate_id(call_id, "call_id")
        try:
            bound_call = snapshot.tool_calls[call_id]
        except KeyError as exc:
            raise NotFound("tool call not found: {}".format(call_id)) from exc
        if bound_call.client_correlation_id is None:
            evidence_id = "evidence-{}".format(uuid.uuid4().hex)
        else:
            request = snapshot.canonical_requests.get(bound_call.client_correlation_id)
            if request is None or request.call_id != bound_call.call_id:
                raise BindingMismatch("canonical Evidence reservation is unavailable")
            evidence_id = request.evidence_id
        recorded_at = self._now()

        def finish(current: _State) -> Tuple[str, str, Dict[str, Any]]:
            running = _require_call(current, call_id)
            approver = None
            if approval_id is not None:
                approver = _require_approval(current, approval_id).approver
            return "evidence", "recorded", {
                "evidence_id": evidence_id,
                "run_id": running.run_id,
                "call_id": running.call_id,
                "approval_id": approval_id,
                "tool": running.tool,
                "input_digest": running.input_digest,
                "actor": running.actor,
                "workspace": running.workspace,
                "policy": running.policy,
                "approver": approver,
                "evidence_type": "tool_execution",
                "outcome": outcome,
                "body": normalized_body,
                "body_digest": _object_digest(normalized_body),
                "recorded_at": recorded_at,
                "call_from_state": running.state,
                "call_to_state": outcome,
            }

        state = self._ledger.transact(recorded_at, finish)
        return state.evidence[evidence_id]

    def execute_read_only(self, call_id: str, executor: Optional[Executor]) -> EvidenceRecord:
        call_id = _validate_id(call_id, "call_id")
        if executor is None:
            raise ExecutorUnavailable("no read-only executor was injected")
        started_at = self._now()

        def start(state: _State) -> Tuple[str, str, Dict[str, Any]]:
            call = _require_call(state, call_id)
            if call.tool != READ_ONLY_TRACER_TOOL or call.effect != "read_only":
                raise ExecutionDenied(
                    "only the reviewed control_plane.trace read-only tool may execute"
                )
            return "tool_call", "execution_started", {
                "call_id": call_id,
                "tool": call.tool,
                "input_digest": call.input_digest,
                "actor": call.actor,
                "workspace": call.workspace,
                "policy": call.policy,
                "from_state": call.state,
                "to_state": "running",
                "reason": "read_only_execution_started",
                "updated_at": started_at,
            }

        state = self._ledger.transact(started_at, start)
        call = state.tool_calls[call_id]
        if call.tool_input is None:
            raise BindingMismatch("read-only tracer input is unavailable")
        try:
            result = executor(
                call.tool,
                _normalized_object(call.tool_input, "tool input"),
            )
            normalized_result = json.loads(_canonical_json(result).decode("utf-8"))
            body: Dict[str, JsonValue] = {"result": normalized_result}
            outcome = "succeeded"
        except Exception as exc:  # executor failures become durable evidence
            body = {
                "error": {
                    "type": type(exc).__name__,
                    "message": str(exc)[:4096],
                }
            }
            outcome = "failed"
        return self._record_execution_evidence(
            call_id=call_id,
            approval_id=None,
            body=body,
            outcome=outcome,
        )

    def execute_canonical(
        self,
        call_id: str,
        *,
        executor: Optional[CanonicalExecutor],
        tool_input: Optional[Mapping[str, JsonValue]] = None,
        result_sink: Optional[CanonicalResultSink] = None,
        after_start_hook: Optional[Callable[[], None]] = None,
    ) -> EvidenceRecord:
        call_id = _validate_id(call_id, "call_id")
        if executor is None:
            raise ExecutorUnavailable("no canonical stable-core executor was injected")
        registry = self._registry()
        snapshot = self.snapshot()
        try:
            call = snapshot.tool_calls[call_id]
        except KeyError as exc:
            raise NotFound("tool call not found: {}".format(call_id)) from exc
        contract = registry.contract(call.tool)
        source_input = call.tool_input if tool_input is None else tool_input
        if source_input is None:
            raise BindingMismatch("canonical execution requires exact transient input")
        normalized_input = registry.normalize_input(call.tool, source_input)
        if (
            normalized_input_digest(normalized_input) != call.input_digest
            or normalized_input_metadata(normalized_input) != call.input_metadata
            or call.effect != "read_only"
        ):
            raise BindingMismatch("canonical call no longer matches its frozen contract")
        started_at = self._now()

        def start(state: _State) -> Tuple[str, str, Dict[str, Any]]:
            current = _require_call(state, call_id)
            if current.tool != contract.canonical_id or current.effect != "read_only":
                raise ExecutionDenied("tool call is not a reviewed stable-core contract")
            return "tool_call", "execution_started", {
                "call_id": current.call_id,
                "tool": current.tool,
                "input_digest": current.input_digest,
                "actor": current.actor,
                "workspace": current.workspace,
                "policy": current.policy,
                "from_state": current.state,
                "to_state": "running",
                "reason": "read_only_execution_started",
                "updated_at": started_at,
            }

        state = self._ledger.transact(started_at, start)
        running = state.tool_calls[call_id]
        if after_start_hook is not None:
            after_start_hook()
        transient_result: Optional[CanonicalExecutionResult] = None
        try:
            raw_result = executor(
                running.tool,
                normalized_input,
            )
            outcome, body = _validated_canonical_result(
                raw_result, running, contract
            )
            transient_result = raw_result
        except Exception as exc:
            body = {
                "error": {
                    "code": "invalid_executor_result",
                    "type": type(exc).__name__,
                }
            }
            outcome = "failed"
        evidence = self._record_execution_evidence(
            call_id=call_id,
            approval_id=None,
            body=body,
            outcome=outcome,
        )
        if running.client_correlation_id is not None:
            run = self.snapshot().runs[running.run_id]
            if run.state == "active":
                self.transition_run(
                    run.run_id,
                    "completed" if evidence.outcome == "succeeded" else "failed",
                )
        if result_sink is not None and transient_result is not None:
            try:
                result_sink(transient_result)
            except Exception:
                # Transient presentation is non-authoritative. Durable Evidence
                # and Run closure must survive a dead/overflowed caller channel.
                pass
        return evidence

    def recover_canonical_execution(self, call_id: str) -> EvidenceRecord:
        call_id = _validate_id(call_id, "call_id")
        snapshot = self.snapshot()
        try:
            call = snapshot.tool_calls[call_id]
        except KeyError as exc:
            raise NotFound("tool call not found: {}".format(call_id)) from exc
        if (
            call.state != "running"
            or call.effect != "read_only"
            or call.client_correlation_id is None
        ):
            raise InvalidTransition(
                "only a running canonical call can be recovered as interrupted"
            )
        evidence = self._record_execution_evidence(
            call_id=call_id,
            approval_id=None,
            body={
                "error": {
                    "code": "executor_lost",
                    "message": "canonical supervisor disappeared after execution started",
                }
            },
            outcome="interrupted",
        )
        run = self.snapshot().runs[call.run_id]
        if run.state == "active":
            self.transition_run(run.run_id, "failed")
        return evidence

    def _execute_project_memory(
        self,
        call_id: str,
        *,
        tool_input: Mapping[str, JsonValue],
        executor: "ProjectMemoryExecutor",
        memory_op_id: str,
        memory_id: Optional[str],
        handoff_id: Optional[str],
        project_digest: str,
        result_sink: Optional[Callable[["ProjectMemoryExecutionResult"], None]],
        after_start_hook: Optional[Callable[[], None]] = None,
        after_evidence_hook: Optional[Callable[[], None]] = None,
    ) -> EvidenceRecord:
        """Execute one fixed memory operation and persist only validated metadata."""
        from .memory import (
            FixedProjectMemoryRegistry,
            PROJECT_MEMORY_EFFECT,
            PROJECT_MEMORY_HANDOFF,
            PROJECT_MEMORY_MUTATION_TOOLS,
            PROJECT_MEMORY_READ_TOOLS,
            ProjectMemoryExecutionRequest,
            parse_project_memory_reservation_binding,
            validate_project_memory_result,
        )

        call_id = _validate_id(call_id, "call_id")
        memory_op_id = _validate_id(memory_op_id, "memory_op_id")
        project_digest = _validate_digest(project_digest, "project_digest")
        if memory_id is not None:
            memory_id = _validate_id(memory_id, "memory_id")
        if handoff_id is not None:
            handoff_id = _validate_id(handoff_id, "handoff_id")
        snapshot = self.snapshot()
        try:
            call = snapshot.tool_calls[call_id]
        except KeyError as exc:
            raise NotFound("tool call not found: {}".format(call_id)) from exc
        registry = FixedProjectMemoryRegistry()
        contract = registry.contract(call.tool)
        normalized_input = registry.normalize_input(call.tool, tool_input)
        if call.client_correlation_id is None:
            raise BindingMismatch("project-memory call lacks its reservation")
        try:
            canonical_request = snapshot.canonical_requests[call.client_correlation_id]
        except KeyError as exc:
            raise BindingMismatch("project-memory reservation is unavailable") from exc
        observation, retention_class, expires_at = (
            parse_project_memory_reservation_binding(
                canonical_request.reservation_binding
            )
        )
        if (
            normalized_input_digest(normalized_input) != call.input_digest
            or normalized_input_metadata(normalized_input) != call.input_metadata
            or call.effect != contract.effect
            or (
                call.tool == PROJECT_MEMORY_HANDOFF
                and not (handoff_id is not None and memory_id is None)
            )
            or (
                call.tool in PROJECT_MEMORY_MUTATION_TOOLS
                and call.tool != PROJECT_MEMORY_HANDOFF
                and not (memory_id is not None and handoff_id is None)
            )
            or (
                call.tool in PROJECT_MEMORY_READ_TOOLS
                and (memory_id is not None or handoff_id is not None)
            )
            or observation.project_digest != project_digest
            or call.timeout_at is None
        ):
            raise BindingMismatch("project-memory input or aggregate identity changed")
        started_at = self._now()

        def start(state: _State) -> Tuple[str, str, Dict[str, Any]]:
            current = _require_call(state, call_id)
            if current.tool != contract.tool or current.effect != contract.effect:
                raise ExecutionDenied("tool call is not reviewed project memory")
            return "tool_call", "execution_started", {
                "call_id": current.call_id,
                "tool": current.tool,
                "input_digest": current.input_digest,
                "actor": current.actor,
                "workspace": current.workspace,
                "policy": current.policy,
                "from_state": current.state,
                "to_state": "running",
                "reason": (
                    "project_memory_execution_started"
                    if contract.effect == PROJECT_MEMORY_EFFECT
                    else "project_memory_read_execution_started"
                ),
                "updated_at": started_at,
            }

        state = self._ledger.transact(started_at, start)
        running = state.tool_calls[call_id]
        request = ProjectMemoryExecutionRequest(
            memory_op_id,
            memory_id,
            handoff_id,
            running.run_id,
            running.call_id,
            canonical_request.decision_id,
            canonical_request.evidence_id,
            running.tool,
            running.input_digest,
            running.actor,
            running.workspace,
            running.policy,
            project_digest,
            observation,
            retention_class,
            expires_at,
            cast(str, running.timeout_at),
        )
        if after_start_hook is not None:
            after_start_hook()
        transient_result: Optional["ProjectMemoryExecutionResult"] = None
        try:
            raw_result = executor(request, normalized_input)
            result_outcome, receipt = validate_project_memory_result(
                raw_result, request, contract, normalized_input
            )
            transient_result = raw_result
            body: Dict[str, JsonValue] = {"project_memory_receipt": receipt}
            outcome = "succeeded" if result_outcome == "succeeded" else "failed"
        except Exception as exc:
            body = {
                "error": {
                    "code": "invalid_executor_result",
                    "type": type(exc).__name__,
                }
            }
            outcome = "failed"
        evidence = self._record_execution_evidence(
            call_id=call_id,
            approval_id=None,
            body=body,
            outcome=outcome,
        )
        if after_evidence_hook is not None:
            after_evidence_hook()
        if result_sink is not None and transient_result is not None:
            try:
                result_sink(transient_result)
            except Exception:
                pass
        return evidence

    def _recover_project_memory_execution(self, call_id: str) -> EvidenceRecord:
        """Fail closed after an ownerless execution start; never execute it again."""
        from .memory import FixedProjectMemoryRegistry

        call_id = _validate_id(call_id, "call_id")
        snapshot = self.snapshot()
        try:
            call = snapshot.tool_calls[call_id]
        except KeyError as exc:
            raise NotFound("tool call not found: {}".format(call_id)) from exc
        contract = FixedProjectMemoryRegistry().contract(call.tool)
        if call.state != "running" or call.effect != contract.effect:
            raise InvalidTransition("only a running project-memory call can recover")
        return self._record_execution_evidence(
            call_id=call.call_id,
            approval_id=None,
            body={
                "error": {
                    "code": "recovery_required",
                    "type": "InterruptedExecution",
                }
            },
            outcome="failed",
        )

    def _finalize_project_memory_aggregate(
        self, call_id: str
    ) -> Optional[Union[MemoryRecord, HandoffRecord]]:
        """Derive one immutable aggregate solely from validated durable Evidence."""
        from .memory import (
            PROJECT_MEMORY_HANDOFF,
            PROJECT_MEMORY_READ_TOOLS,
            validate_durable_project_memory_receipt,
        )

        call_id = _validate_id(call_id, "call_id")
        snapshot = self.snapshot()
        try:
            call = snapshot.tool_calls[call_id]
        except KeyError as exc:
            raise NotFound("tool call not found: {}".format(call_id)) from exc
        if call.tool in PROJECT_MEMORY_READ_TOOLS:
            return None
        existing_memory = [
            item for item in snapshot.memory_records.values() if item.call_id == call_id
        ]
        existing_handoff = [
            item for item in snapshot.handoff_records.values() if item.call_id == call_id
        ]
        existing = existing_memory + existing_handoff
        if len(existing) > 1:
            raise BindingMismatch("project-memory call has multiple aggregates")
        if existing:
            return existing[0]
        evidence = [item for item in snapshot.evidence.values() if item.call_id == call_id]
        decisions = [
            item for item in snapshot.policy_decisions.values() if item.call_id == call_id
        ]
        if len(evidence) != 1 or len(decisions) != 1:
            raise InvalidTransition("project-memory provenance is incomplete")
        recorded = evidence[0]
        decision = decisions[0]
        receipt_value = recorded.body.get("project_memory_receipt")
        if recorded.outcome != "succeeded" or not isinstance(receipt_value, dict):
            return None
        receipt = validate_durable_project_memory_receipt(
            receipt_value,
            run_id=call.run_id,
            call_id=call.call_id,
            decision_id=decision.decision_id,
            evidence_id=recorded.evidence_id,
            tool=call.tool,
            input_digest=call.input_digest,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
            evidence_outcome=recorded.outcome,
        )
        if receipt["outcome"] != "succeeded" or decision.outcome != "allow":
            return None
        created_at = self._now()

        def build(state: _State) -> Tuple[str, str, Dict[str, Any]]:
            current = _require_call(state, call_id)
            current_evidence = state.evidence.get(recorded.evidence_id)
            current_decision = state.policy_decisions.get(decision.decision_id)
            if current_evidence is None or current_decision is None:
                raise InvalidTransition("project-memory provenance disappeared")
            common: Dict[str, Any] = {
                "memory_op_id": receipt["memory_op_id"],
                "run_id": current.run_id,
                "call_id": current.call_id,
                "decision_id": current_decision.decision_id,
                "evidence_id": current_evidence.evidence_id,
                "tool": current.tool,
                "input_digest": current.input_digest,
                "actor": current.actor,
                "workspace": current.workspace,
                "policy": current.policy,
                "policy_authority": current_decision.authority,
                "project_digest": receipt["project_digest"],
                "session_id": receipt["session_id"],
                "trust_label": "kernel_bound",
                "authoritative": False,
                "retention_class": receipt["retention_class"],
                "expires_at": receipt["expires_at"],
                "created_at": created_at,
            }
            if current.tool == PROJECT_MEMORY_HANDOFF:
                return "handoff_record", "created", dict(
                    common,
                    handoff_id=receipt["handoff_id"],
                    recipient_sha256=receipt["recipient_sha256"],
                    summary_sha256=receipt["value_sha256"],
                    summary_bytes=receipt["value_bytes"],
                )
            return "memory_record", "created", dict(
                common,
                memory_id=receipt["memory_id"],
                record_type=receipt["record_type"],
                key_sha256=receipt["key_sha256"],
                value_sha256=receipt["value_sha256"],
                value_bytes=receipt["value_bytes"],
            )

        state = self._ledger.transact(created_at, build)
        if call.tool == PROJECT_MEMORY_HANDOFF:
            return state.handoff_records[cast(str, receipt["handoff_id"])]
        return state.memory_records[cast(str, receipt["memory_id"])]

    def _execute_coding(
        self,
        call_id: str,
        *,
        tool_input: Mapping[str, JsonValue],
        executor: "CodingExecutor",
        approval_id: Optional[str],
        result_sink: Optional[Callable[["CodingExecutionResult"], None]],
        after_start_hook: Optional[Callable[[], None]] = None,
        after_commit_hook: Optional[Callable[[], None]] = None,
    ) -> EvidenceRecord:
        """Execute one exact coding call and record only validated metadata."""
        from .coding import (
            CODING_ATOMIC_EDIT,
            CodingExecutionRequest,
            FixedCodingRegistry,
            validate_coding_result,
        )

        call_id = _validate_id(call_id, "call_id")
        snapshot = self.snapshot()
        try:
            call = snapshot.tool_calls[call_id]
        except KeyError as exc:
            raise NotFound("tool call not found: {}".format(call_id)) from exc
        registry = FixedCodingRegistry()
        contract = registry.contract(call.tool)
        normalized_input = registry.normalize_input(call.tool, tool_input)
        if call.client_correlation_id is None:
            raise BindingMismatch("coding call lacks its canonical reservation")
        try:
            canonical_request = snapshot.canonical_requests[
                call.client_correlation_id
            ]
        except KeyError as exc:
            raise BindingMismatch("coding reservation is unavailable") from exc
        if (
            normalized_input_digest(normalized_input) != call.input_digest
            or normalized_input_metadata(normalized_input) != call.input_metadata
            or call.effect != contract.effect
        ):
            raise BindingMismatch("coding input no longer matches its frozen call")
        approval: Optional[ApprovalRecord] = None
        if contract.effect in ("mutating", _CODING_EXECUTION_EFFECT):
            if (
                contract.effect == "mutating"
                and call.tool != CODING_ATOMIC_EDIT
            ) or approval_id is None:
                raise ExecutionDenied("coding side effect lacks its exact approval")
            try:
                approval = snapshot.approvals[approval_id]
            except KeyError as exc:
                raise NotFound("approval not found: {}".format(approval_id)) from exc
            if approval.state == "consumed":
                raise ApprovalConsumed("approval was already consumed")
            _assert_call_binding(
                call,
                call_id=call.call_id,
                tool=approval.tool,
                input_digest=approval.input_digest,
                actor=approval.actor,
                workspace=approval.workspace,
                policy=approval.policy,
            )
        elif approval_id is not None:
            raise ExecutionDenied("read-only coding calls cannot use an approval")

        started_at = self._now()

        if approval is None:
            def start(state: _State) -> Tuple[str, str, Dict[str, Any]]:
                current = _require_call(state, call_id)
                if current.effect != "read_only" or current.tool != contract.tool:
                    raise ExecutionDenied("coding call is not the reviewed read-only tool")
                return "tool_call", "execution_started", {
                    "call_id": current.call_id,
                    "tool": current.tool,
                    "input_digest": current.input_digest,
                    "actor": current.actor,
                    "workspace": current.workspace,
                    "policy": current.policy,
                    "from_state": current.state,
                    "to_state": "running",
                    "reason": "read_only_execution_started",
                    "updated_at": started_at,
                }
        else:
            def start(state: _State) -> Tuple[str, str, Dict[str, Any]]:
                current = _require_call(state, call_id)
                current_approval = _require_approval(state, cast(str, approval_id))
                if current_approval.state == "consumed":
                    raise ApprovalConsumed("approval was already consumed")
                if _parse_timestamp(started_at, "consumed_at") >= _parse_timestamp(
                    current_approval.expires_at, "expires_at"
                ):
                    raise ApprovalExpired("approval has expired")
                _assert_call_binding(
                    current,
                    call_id=current.call_id,
                    tool=current_approval.tool,
                    input_digest=current_approval.input_digest,
                    actor=current_approval.actor,
                    workspace=current_approval.workspace,
                    policy=current_approval.policy,
                )
                return "approval", "consumed", {
                    "approval_id": current_approval.approval_id,
                    "call_id": current.call_id,
                    "actor": current.actor,
                    "workspace": current.workspace,
                    "policy": current.policy,
                    "approver": current_approval.approver,
                    "reason": (
                        "coding_edit_execution_started"
                        if current.effect == "mutating"
                        else "coding_action_execution_started"
                    ),
                    "approval_from_state": current_approval.state,
                    "approval_to_state": "consumed",
                    "call_from_state": current.state,
                    "call_to_state": "running",
                    "consumed_at": started_at,
                }

        state = self._ledger.transact(started_at, start)
        running = state.tool_calls[call_id]
        current_approval = (
            None if approval_id is None else state.approvals[approval_id]
        )
        request = CodingExecutionRequest(
            running.run_id,
            running.call_id,
            canonical_request.decision_id,
            canonical_request.evidence_id,
            approval_id,
            None if current_approval is None else current_approval.approver,
            running.tool,
            running.input_digest,
            running.actor,
            running.workspace,
            running.policy,
        )
        if after_start_hook is not None:
            after_start_hook()
        transient_result: Optional["CodingExecutionResult"] = None
        try:
            raw_result = executor(request, normalized_input)
            if after_commit_hook is not None:
                after_commit_hook()
            outcome, receipt = validate_coding_result(
                raw_result, request, contract, normalized_input
            )
            transient_result = raw_result
            body: Dict[str, JsonValue] = {"coding_receipt": receipt}
        except Exception as exc:
            body = {
                "error": {
                    "code": "invalid_executor_result",
                    "type": type(exc).__name__,
                    "write_may_have_committed": running.effect != "read_only",
                }
            }
            outcome = "failed"
        evidence = self._record_execution_evidence(
            call_id=call_id,
            approval_id=approval_id,
            body=body,
            outcome=outcome,
        )
        if result_sink is not None and transient_result is not None:
            try:
                result_sink(transient_result)
            except Exception:
                pass
        return evidence

    def _recover_coding_execution(self, call_id: str) -> EvidenceRecord:
        """Close an ownerless running coding call without ever retrying it."""
        from .coding import FixedCodingRegistry

        call_id = _validate_id(call_id, "call_id")
        snapshot = self.snapshot()
        try:
            call = snapshot.tool_calls[call_id]
        except KeyError as exc:
            raise NotFound("tool call not found: {}".format(call_id)) from exc
        contract = FixedCodingRegistry().contract(call.tool)
        if call.state != "running" or call.effect != contract.effect:
            raise InvalidTransition("only a running coding call can be recovered")
        approvals = [
            approval
            for approval in snapshot.approvals.values()
            if approval.call_id == call.call_id and approval.state == "consumed"
        ]
        if contract.effect in ("mutating", _CODING_EXECUTION_EFFECT) and len(
            approvals
        ) != 1:
            raise BindingMismatch(
                "running coding side effect lacks one consumed approval"
            )
        if contract.effect == "read_only" and approvals:
            raise BindingMismatch("running read-only coding call has an approval")
        return self._record_execution_evidence(
            call_id=call_id,
            approval_id=approvals[0].approval_id if approvals else None,
            body={"error": {"code": "executor_lost", "type": "InterruptedExecution"}},
            outcome="interrupted",
        )

    def execute_disposable_write(
        self,
        call_id: str,
        *,
        approval_id: str,
        actor: str,
        workspace: str,
        policy: str,
    ) -> EvidenceRecord:
        call_id = _validate_id(call_id, "call_id")
        approval_id = _validate_id(approval_id, "approval_id")
        actor = _validate_text(actor, "actor")
        workspace = _canonicalize_workspace(workspace)
        policy = _validate_text(policy, "policy")

        snapshot = self.snapshot()
        try:
            call = snapshot.tool_calls[call_id]
        except KeyError as exc:
            raise NotFound("tool call not found: {}".format(call_id)) from exc
        try:
            approval = snapshot.approvals[approval_id]
        except KeyError as exc:
            raise NotFound("approval not found: {}".format(approval_id)) from exc
        if approval.state == "consumed":
            raise ApprovalConsumed("approval was already consumed")
        if call.tool != DISPOSABLE_WRITE_TOOL or call.effect != "mutating":
            raise ExecutionDenied("only the fixed disposable-write tool may mutate files")
        _assert_call_binding(
            call,
            call_id=call_id,
            tool=approval.tool,
            input_digest=approval.input_digest,
            actor=actor,
            workspace=workspace,
            policy=policy,
        )

        prepared = _prepare_disposable_write(call)
        started_at = self._now()

        def start(state: _State) -> Tuple[str, str, Dict[str, Any]]:
            current_approval = _require_approval(state, approval_id)
            current_call = _require_call(state, call_id)
            if current_approval.state == "consumed":
                raise ApprovalConsumed("approval was already consumed")
            if _parse_timestamp(started_at, "consumed_at") >= _parse_timestamp(
                current_approval.expires_at, "expires_at"
            ):
                raise ApprovalExpired("approval has expired")
            _assert_call_binding(
                current_call,
                call_id=call_id,
                tool=current_approval.tool,
                input_digest=current_approval.input_digest,
                actor=actor,
                workspace=workspace,
                policy=policy,
            )
            return "approval", "consumed", {
                "approval_id": approval_id,
                "call_id": call_id,
                "actor": actor,
                "workspace": workspace,
                "policy": policy,
                "approver": current_approval.approver,
                "reason": "disposable_write_execution_started",
                "approval_from_state": current_approval.state,
                "approval_to_state": "consumed",
                "call_from_state": current_call.state,
                "call_to_state": "running",
                "consumed_at": started_at,
            }

        try:
            self._ledger.transact(started_at, start)
            try:
                receipt = _atomic_disposable_replace(prepared)
                receipt.update(
                    {
                        "call_id": call.call_id,
                        "approval_id": approval.approval_id,
                        "tool": call.tool,
                        "input_digest": call.input_digest,
                        "actor": call.actor,
                        "workspace": call.workspace,
                        "policy": call.policy,
                        "approver": approval.approver,
                    }
                )
                body: Dict[str, JsonValue] = {"receipt": receipt}
                outcome = "succeeded"
            except Exception as exc:
                body = {
                    "error": {
                        "type": type(exc).__name__,
                        "message": str(exc)[:4096],
                        "write_may_have_committed": bool(
                            getattr(exc, "mainframe_write_may_have_committed", False)
                        ),
                    }
                }
                outcome = "failed"
        finally:
            prepared.close()

        return self._record_execution_evidence(
            call_id=call_id,
            approval_id=approval_id,
            body=body,
            outcome=outcome,
        )

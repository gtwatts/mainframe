"""Durable, non-authorizing project-memory aggregate contracts."""

from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import threading
from typing import Any, Callable, Dict, Iterator, List, Mapping, Optional, Protocol, Tuple, TYPE_CHECKING, Union, cast

if TYPE_CHECKING:
    from .kernel import CanonicalRequestRecord

from .durability import create_directory_durable
from .errors import (
    AlreadyExists,
    BindingMismatch,
    ExecutionDenied,
    InvalidTransition,
    ValidationError,
)
from .kernel import (
    Clock,
    ControlPlaneKernel,
    HandoffRecord,
    JsonValue,
    MemoryRecord,
    PolicyEvaluation,
    PolicyRequest,
    Snapshot,
    normalized_input_digest,
    normalized_input_metadata,
)


PROJECT_MEMORY_POLICY = "project-memory-v1"
PROJECT_MEMORY_ENSURE = "mainframe.project_memory.ensure.v1"
PROJECT_MEMORY_CHECKPOINT = "mainframe.project_memory.checkpoint.v1"
PROJECT_MEMORY_DISCOVERY = "mainframe.project_memory.discovery.v1"
PROJECT_MEMORY_PROGRESS = "mainframe.project_memory.progress.v1"
PROJECT_MEMORY_CLOSE = "mainframe.project_memory.close.v1"
PROJECT_MEMORY_HANDOFF = "mainframe.project_memory.handoff.v1"
PROJECT_MEMORY_SESSION = "mainframe.project_memory.session.v1"
PROJECT_MEMORY_STATUS = "mainframe.project_memory.status.v1"
PROJECT_MEMORY_GET = "mainframe.project_memory.get.v1"
PROJECT_MEMORY_SUMMARY = "mainframe.project_memory.summary.v1"
PROJECT_MEMORY_CONTEXT = "mainframe.project_memory.context.v1"
PROJECT_MEMORY_FIND = "mainframe.project_memory.find.v1"
PROJECT_MEMORY_EFFECT = "non_authoritative_memory"

PROJECT_MEMORY_MUTATION_TOOLS = frozenset(
    (
        PROJECT_MEMORY_ENSURE,
        PROJECT_MEMORY_CHECKPOINT,
        PROJECT_MEMORY_DISCOVERY,
        PROJECT_MEMORY_PROGRESS,
        PROJECT_MEMORY_CLOSE,
        PROJECT_MEMORY_HANDOFF,
    )
)
PROJECT_MEMORY_READ_TOOLS = frozenset(
    (
        PROJECT_MEMORY_SESSION,
        PROJECT_MEMORY_STATUS,
        PROJECT_MEMORY_GET,
        PROJECT_MEMORY_SUMMARY,
        PROJECT_MEMORY_CONTEXT,
        PROJECT_MEMORY_FIND,
    )
)

_CORRELATION_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
_SESSION_ID = re.compile(r"^[0-9a-f]{12}$")
_DIGEST = re.compile(r"^[0-9a-f]{64}$")
_MAX_INPUT_BYTES = 32768
_MAX_TEXT_BYTES = 24576
_MAX_TRANSIENT_BYTES = 32768
_MAX_TTL_SECONDS = 315360000
_MAX_HANDOFF_TOKENS = 1000000
_MAX_READ_TOKENS = 1000000
_MAX_FIND_LIMIT = 100000
_DEFAULT_CONTEXT_INCLUDE = "discoveries,progress,checkpoints,logs"


@dataclass(frozen=True)
class ProjectMemoryContract:
    tool: str
    record_type: str
    timeout_ms: int
    effect: str
    transient_output: bool = False
    allow_empty_transient: bool = False


@dataclass(frozen=True)
class ProjectMemoryObservation:
    """Exact metadata-only project mapping observation frozen at reservation."""

    project_digest: str
    mapping_state: str
    session_id: Optional[str]
    state_digest: str

    def to_dict(self) -> Dict[str, JsonValue]:
        return {
            "project_digest": self.project_digest,
            "mapping_state": self.mapping_state,
            "session_id": self.session_id,
            "state_digest": self.state_digest,
        }


@dataclass(frozen=True)
class ProjectMemoryExecutionRequest:
    memory_op_id: str
    memory_id: Optional[str]
    handoff_id: Optional[str]
    run_id: str
    call_id: str
    decision_id: str
    evidence_id: str
    tool: str
    input_digest: str
    actor: str
    workspace: str
    policy: str
    project_digest: str
    observation: ProjectMemoryObservation
    retention_class: str
    expires_at: Optional[str]
    timeout_at: str


@dataclass(frozen=True)
class ProjectMemoryExecutionResult:
    outcome: str
    receipt: Dict[str, JsonValue]
    transient: Optional[bytes] = None


class ProjectMemoryExecutor(Protocol):
    def observe(
        self, workspace: str, project_digest: str
    ) -> ProjectMemoryObservation:
        ...

    def __call__(
        self,
        request: ProjectMemoryExecutionRequest,
        tool_input: Mapping[str, JsonValue],
    ) -> ProjectMemoryExecutionResult:
        ...


@dataclass(frozen=True)
class ProjectMemoryInvocationResult:
    schema_version: int
    status: str
    client_correlation_id: str
    memory_op_id: str
    memory_id: Optional[str]
    handoff_id: Optional[str]
    run_id: str
    call_id: str
    decision_id: str
    evidence_id: str
    input_digest: str
    project_digest: str
    session_id: Optional[str]
    outcome: str
    result_available: bool
    receipt: Optional[Dict[str, JsonValue]]
    memory_record: Optional[MemoryRecord]
    handoff_record: Optional[HandoffRecord]
    transient: Optional[bytes]


@dataclass(frozen=True)
class LegacyMemoryView:
    memory_id: str
    value_sha256: str
    value_bytes: int
    expires_at: Optional[str]
    trust_label: str = "untrusted_legacy"
    authoritative: bool = False
    run_id: Optional[str] = None
    call_id: Optional[str] = None
    evidence_id: Optional[str] = None
    input_digest: Optional[str] = None


class FixedProjectMemoryRegistry:
    """The exact reviewed mutation/read operations; there is no generic action."""

    def __init__(self) -> None:
        self.contracts: Dict[str, ProjectMemoryContract] = {
            PROJECT_MEMORY_ENSURE: ProjectMemoryContract(
                PROJECT_MEMORY_ENSURE, "session_ensure", 30000, PROJECT_MEMORY_EFFECT
            ),
            PROJECT_MEMORY_CHECKPOINT: ProjectMemoryContract(
                PROJECT_MEMORY_CHECKPOINT, "checkpoint", 30000, PROJECT_MEMORY_EFFECT
            ),
            PROJECT_MEMORY_DISCOVERY: ProjectMemoryContract(
                PROJECT_MEMORY_DISCOVERY, "discovery", 30000, PROJECT_MEMORY_EFFECT
            ),
            PROJECT_MEMORY_PROGRESS: ProjectMemoryContract(
                PROJECT_MEMORY_PROGRESS, "progress", 30000, PROJECT_MEMORY_EFFECT
            ),
            PROJECT_MEMORY_CLOSE: ProjectMemoryContract(
                PROJECT_MEMORY_CLOSE, "session_close", 30000, PROJECT_MEMORY_EFFECT
            ),
            PROJECT_MEMORY_HANDOFF: ProjectMemoryContract(
                PROJECT_MEMORY_HANDOFF,
                "handoff",
                30000,
                PROJECT_MEMORY_EFFECT,
                transient_output=True,
            ),
            PROJECT_MEMORY_SESSION: ProjectMemoryContract(
                PROJECT_MEMORY_SESSION, "project_session", 30000, "read_only", True
            ),
            PROJECT_MEMORY_STATUS: ProjectMemoryContract(
                PROJECT_MEMORY_STATUS, "project_status", 30000, "read_only", True
            ),
            PROJECT_MEMORY_GET: ProjectMemoryContract(
                PROJECT_MEMORY_GET,
                "project_get",
                30000,
                "read_only",
                True,
                True,
            ),
            PROJECT_MEMORY_SUMMARY: ProjectMemoryContract(
                PROJECT_MEMORY_SUMMARY, "project_summary", 30000, "read_only", True
            ),
            PROJECT_MEMORY_CONTEXT: ProjectMemoryContract(
                PROJECT_MEMORY_CONTEXT, "project_context", 30000, "read_only", True
            ),
            PROJECT_MEMORY_FIND: ProjectMemoryContract(
                PROJECT_MEMORY_FIND, "project_find", 30000, "read_only", True
            ),
        }

    def contract(self, tool: str) -> ProjectMemoryContract:
        if not isinstance(tool, str):
            raise ExecutionDenied("project-memory tool ID must be a string")
        try:
            return self.contracts[tool]
        except KeyError as exc:
            raise ExecutionDenied("project-memory tool ID is not reviewed") from exc

    def normalize_input(
        self, tool: str, tool_input: Mapping[str, JsonValue]
    ) -> Dict[str, JsonValue]:
        contract = self.contract(tool)
        if not isinstance(tool_input, dict):
            raise ExecutionDenied("project-memory input must be an object")
        try:
            normalized = json.loads(_canonical_json(tool_input).decode("utf-8"))
        except (TypeError, ValueError, UnicodeError) as exc:
            raise ExecutionDenied("project-memory input is not canonical JSON") from exc
        if not isinstance(normalized, dict):
            raise ExecutionDenied("project-memory input must normalize to an object")
        typed = cast(Dict[str, JsonValue], normalized)
        if tool in (PROJECT_MEMORY_SESSION, PROJECT_MEMORY_STATUS):
            _require_keys(typed, set(), contract.record_type)
        elif tool == PROJECT_MEMORY_GET:
            if set(typed) - {"key", "default"} or "key" not in typed:
                raise ExecutionDenied("get input fields are not exact")
            _text(typed["key"], "get key", 1024)
            if "default" not in typed:
                typed["default"] = ""
            _optional_text(typed["default"], "get default", _MAX_TEXT_BYTES)
        elif tool == PROJECT_MEMORY_SUMMARY:
            if set(typed) - {"max_tokens"}:
                raise ExecutionDenied("summary input fields are not exact")
            if "max_tokens" not in typed:
                typed["max_tokens"] = 0
            _bounded_uint(typed["max_tokens"], "summary max_tokens", _MAX_READ_TOKENS)
        elif tool == PROJECT_MEMORY_CONTEXT:
            if set(typed) - {"task", "max_tokens", "render_format", "include"} or "task" not in typed:
                raise ExecutionDenied("context input fields are not exact")
            _text(typed["task"], "context task", 1024)
            typed.setdefault("max_tokens", 0)
            typed.setdefault("render_format", "json")
            typed.setdefault("include", _DEFAULT_CONTEXT_INCLUDE)
            _bounded_uint(typed["max_tokens"], "context max_tokens", _MAX_READ_TOKENS)
            if typed["render_format"] not in ("json", "prompt"):
                raise ExecutionDenied("context render_format is invalid")
            _text(typed["include"], "context include", 4096)
        elif tool == PROJECT_MEMORY_FIND:
            if set(typed) - {"query", "kind", "limit"} or "query" not in typed:
                raise ExecutionDenied("find input fields are not exact")
            _text(typed["query"], "find query", 1024)
            typed.setdefault("kind", "mixed")
            typed.setdefault("limit", 10)
            if typed["kind"] not in ("discovery", "checkpoint", "log", "mixed"):
                raise ExecutionDenied("find kind is invalid")
            limit = _bounded_uint(typed["limit"], "find limit", _MAX_FIND_LIMIT)
            if limit == 0:
                raise ExecutionDenied("find limit must be greater than zero")
        elif tool == PROJECT_MEMORY_ENSURE:
            if set(typed) - {"name"}:
                raise ExecutionDenied("ensure input fields are not exact")
            if "name" in typed:
                _text(typed["name"], "ensure name", 1024)
        elif tool == PROJECT_MEMORY_CLOSE:
            _require_keys(typed, {"expected_session_id"}, "close")
            _session(typed["expected_session_id"])
        elif tool == PROJECT_MEMORY_CHECKPOINT:
            _require_keys(
                typed,
                {
                    "expected_session_id",
                    "key",
                    "value",
                    "importance",
                    "tags",
                    "ttl_seconds",
                },
                "checkpoint",
            )
            _session(typed["expected_session_id"])
            _text(typed["key"], "checkpoint key", 1024)
            _text(typed["value"], "checkpoint value", _MAX_TEXT_BYTES)
            _importance_and_tags(typed)
            _ttl_seconds(typed["ttl_seconds"])
        elif tool == PROJECT_MEMORY_DISCOVERY:
            _require_keys(
                typed,
                {
                    "expected_session_id",
                    "value",
                    "importance",
                    "tags",
                },
                "discovery",
            )
            _session(typed["expected_session_id"])
            _text(typed["value"], "discovery value", _MAX_TEXT_BYTES)
            _importance_and_tags(typed)
        elif tool == PROJECT_MEMORY_PROGRESS:
            _require_keys(
                typed,
                {
                    "expected_session_id",
                    "task",
                    "current",
                    "total",
                    "status",
                },
                "progress",
            )
            _session(typed["expected_session_id"])
            _text(typed["task"], "progress task", 1024)
            _optional_text(typed["status"], "progress status", _MAX_TEXT_BYTES)
            current = typed["current"]
            total = typed["total"]
            if (
                type(current) is not int
                or type(total) is not int
                or current < 0
                or total < 1
                or current > total
            ):
                raise ExecutionDenied("progress counters are invalid")
        else:
            _require_keys(
                typed,
                {
                    "expected_session_id",
                    "target",
                    "max_tokens",
                    "render_format",
                },
                "handoff",
            )
            _session(typed["expected_session_id"])
            _text(typed["target"], "handoff target", 1024)
            max_tokens = typed["max_tokens"]
            if (
                type(max_tokens) is not int
                or max_tokens < 0
                or max_tokens > _MAX_HANDOFF_TOKENS
            ):
                raise ExecutionDenied("handoff max_tokens is invalid")
            if typed["render_format"] not in ("json", "prompt"):
                raise ExecutionDenied("handoff render_format is invalid")
        if len(_canonical_json(typed)) > _MAX_INPUT_BYTES:
            raise ExecutionDenied("project-memory input exceeds 32768 UTF-8 bytes")
        return typed


class FixedProjectMemoryEvaluator:
    def __init__(self, registry: FixedProjectMemoryRegistry) -> None:
        self._registry = registry

    def __call__(self, request: PolicyRequest) -> PolicyEvaluation:
        authority = "policy-engine:fixed-project-memory-v1"
        if request.policy != PROJECT_MEMORY_POLICY:
            return PolicyEvaluation("deny", authority, "project-memory policy mismatch")
        try:
            contract = self._registry.contract(request.tool)
            normalized = self._registry.normalize_input(request.tool, request.tool_input)
        except ExecutionDenied:
            return PolicyEvaluation("deny", authority, "operation is not reviewed")
        if (
            request.effect != contract.effect
            or normalized != request.tool_input
            or request.timeout_at is None
        ):
            return PolicyEvaluation("deny", authority, "request is not canonical")
        return PolicyEvaluation(
            "allow", authority, "fixed reviewed project-memory operation"
        )


def _canonical_json(value: Any) -> bytes:
    return json.dumps(
        value,
        allow_nan=False,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def _require_keys(value: Mapping[str, Any], expected: set[str], label: str) -> None:
    if set(value) != expected:
        raise ExecutionDenied("{} input fields are not exact".format(label))


def _text(value: Any, label: str, maximum_bytes: int) -> str:
    if not isinstance(value, str) or not value or "\x00" in value:
        raise ExecutionDenied("{} must be a non-empty NUL-free string".format(label))
    if len(value.encode("utf-8")) > maximum_bytes:
        raise ExecutionDenied("{} exceeds its UTF-8 size limit".format(label))
    return value


def _optional_text(value: Any, label: str, maximum_bytes: int) -> str:
    if not isinstance(value, str) or "\x00" in value:
        raise ExecutionDenied("{} must be a NUL-free string".format(label))
    if len(value.encode("utf-8")) > maximum_bytes:
        raise ExecutionDenied("{} exceeds its UTF-8 size limit".format(label))
    return value


def _ttl_seconds(value: Any) -> int:
    if type(value) is not int or value < 0 or value > _MAX_TTL_SECONDS:
        raise ExecutionDenied("checkpoint ttl_seconds is invalid")
    return value


def _bounded_uint(value: Any, label: str, maximum: int) -> int:
    if type(value) is not int or value < 0 or value > maximum:
        raise ExecutionDenied("{} is invalid".format(label))
    return value


def _session(value: Any) -> str:
    if not isinstance(value, str) or _SESSION_ID.fullmatch(value) is None:
        raise ExecutionDenied("expected_session_id must be 12 lowercase hex characters")
    return value


def _timestamp(value: Any) -> Optional[str]:
    if value is None:
        return None
    if not isinstance(value, str) or not value.endswith("Z"):
        raise ExecutionDenied("expires_at must be canonical UTC RFC3339 or null")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ExecutionDenied("expires_at is invalid") from exc
    rendered = parsed.astimezone(timezone.utc).isoformat(
        timespec="microseconds" if parsed.microsecond else "seconds"
    ).replace("+00:00", "Z")
    if rendered != value:
        raise ExecutionDenied("expires_at is not canonical")
    return value


def _importance_and_tags(value: Mapping[str, JsonValue]) -> None:
    if value["importance"] not in ("low", "normal", "high", "critical"):
        raise ExecutionDenied("importance is invalid")
    tags = value["tags"]
    if (
        not isinstance(tags, list)
        or len(tags) > 32
        or any(not isinstance(tag, str) or not tag or len(tag.encode("utf-8")) > 128 for tag in tags)
        or len(set(cast(List[str], tags))) != len(tags)
    ):
        raise ExecutionDenied("tags are invalid")


def _validate_observation(value: Any, project_digest: str) -> ProjectMemoryObservation:
    if not isinstance(value, ProjectMemoryObservation):
        raise ValidationError("project-memory observation has an invalid type")
    _digest(value.project_digest, "observation project_digest")
    _digest(value.state_digest, "observation state_digest")
    if value.project_digest != project_digest:
        raise BindingMismatch("project-memory observation changed project identity")
    if value.mapping_state not in ("absent", "active", "closed", "invalid"):
        raise ValidationError("project-memory observation state is invalid")
    if value.mapping_state == "absent":
        if value.session_id is not None:
            raise BindingMismatch("absent project-memory observation has a session")
    elif value.session_id is None or _SESSION_ID.fullmatch(value.session_id) is None:
        raise BindingMismatch("mapped project-memory observation lacks a valid session")
    return value


_RESERVATION_BINDING_KEYS = frozenset(
    (
        "schema_version",
        "kind",
        "project_digest",
        "mapping_state",
        "session_id",
        "state_digest",
        "retention_class",
        "expires_at",
    )
)


def project_memory_reservation_binding(
    observation: ProjectMemoryObservation,
    *,
    retention_class: str,
    expires_at: Optional[str],
) -> Dict[str, JsonValue]:
    observed = _validate_observation(observation, observation.project_digest)
    if retention_class not in ("session", "project", "expiring"):
        raise ValidationError("project-memory reservation retention is invalid")
    normalized_expiry = _timestamp(expires_at)
    if (retention_class == "expiring") != (normalized_expiry is not None):
        raise BindingMismatch("project-memory reservation expiry is inconsistent")
    return {
        "schema_version": 1,
        "kind": "project_memory_v1",
        "project_digest": observed.project_digest,
        "mapping_state": observed.mapping_state,
        "session_id": observed.session_id,
        "state_digest": observed.state_digest,
        "retention_class": retention_class,
        "expires_at": normalized_expiry,
    }


def parse_project_memory_reservation_binding(
    value: Any,
) -> Tuple[ProjectMemoryObservation, str, Optional[str]]:
    if not isinstance(value, dict) or set(value) != _RESERVATION_BINDING_KEYS:
        raise BindingMismatch("project-memory reservation binding fields are not exact")
    if value.get("schema_version") != 1 or value.get("kind") != "project_memory_v1":
        raise BindingMismatch("project-memory reservation binding version is invalid")
    project_digest = _digest(value.get("project_digest"), "reservation project_digest")
    observation = _validate_observation(
        ProjectMemoryObservation(
            project_digest=project_digest,
            mapping_state=cast(str, value.get("mapping_state")),
            session_id=cast(Optional[str], value.get("session_id")),
            state_digest=cast(str, value.get("state_digest")),
        ),
        project_digest,
    )
    retention = value.get("retention_class")
    if retention not in ("session", "project", "expiring"):
        raise BindingMismatch("project-memory reservation retention is invalid")
    expires_at = _timestamp(value.get("expires_at"))
    if (retention == "expiring") != (expires_at is not None):
        raise BindingMismatch("project-memory reservation expiry is inconsistent")
    return observation, cast(str, retention), expires_at


def _reservation_retention(
    tool: str,
    normalized: Mapping[str, JsonValue],
    now: datetime,
) -> Tuple[str, Optional[str]]:
    if tool in PROJECT_MEMORY_READ_TOOLS:
        return "session", None
    if tool == PROJECT_MEMORY_CHECKPOINT:
        ttl = _ttl_seconds(normalized["ttl_seconds"])
        if ttl > 0:
            expires = now.astimezone(timezone.utc) + timedelta(seconds=ttl)
            return "expiring", expires.isoformat(
                timespec="microseconds" if expires.microsecond else "seconds"
            ).replace("+00:00", "Z")
        return "project", None
    if tool == PROJECT_MEMORY_DISCOVERY:
        return "project", None
    if tool == PROJECT_MEMORY_HANDOFF:
        return "project", None
    return "session", None


def _digest(value: Any, label: str) -> str:
    if not isinstance(value, str) or _DIGEST.fullmatch(value) is None:
        raise ValidationError("{} is not lowercase SHA-256".format(label))
    return value


def _derived_value_metadata(
    tool: str,
    normalized: Mapping[str, JsonValue],
    transient: Optional[bytes] = None,
) -> Tuple[Optional[str], str, int, Optional[str]]:
    key: Optional[str] = None
    recipient: Optional[str] = None
    value = b""
    if tool in PROJECT_MEMORY_READ_TOOLS:
        value = b"" if transient is None else transient
        if tool == PROJECT_MEMORY_GET:
            key = cast(str, normalized["key"])
        elif tool == PROJECT_MEMORY_CONTEXT:
            key = cast(str, normalized["task"])
        elif tool == PROJECT_MEMORY_FIND:
            key = cast(str, normalized["query"])
    elif tool == PROJECT_MEMORY_CHECKPOINT:
        key = cast(str, normalized["key"])
        value = cast(str, normalized["value"]).encode("utf-8")
    elif tool == PROJECT_MEMORY_DISCOVERY:
        value = cast(str, normalized["value"]).encode("utf-8")
    elif tool == PROJECT_MEMORY_PROGRESS:
        key = cast(str, normalized["task"])
        value = _canonical_json(
            {
                "current": normalized["current"],
                "status": normalized["status"],
                "total": normalized["total"],
            }
        )
    elif tool == PROJECT_MEMORY_HANDOFF:
        recipient = cast(str, normalized["target"])
        value = b"" if transient is None else transient
    return (
        None if key is None else hashlib.sha256(key.encode("utf-8")).hexdigest(),
        hashlib.sha256(value).hexdigest(),
        len(value),
        None
        if recipient is None
        else hashlib.sha256(recipient.encode("utf-8")).hexdigest(),
    )


_RECEIPT_KEYS = frozenset(
    (
        "schema_version",
        "memory_op_id",
        "memory_id",
        "handoff_id",
        "run_id",
        "call_id",
        "decision_id",
        "evidence_id",
        "tool",
        "input_digest",
        "actor",
        "workspace",
        "policy",
        "project_digest",
        "expected_session_id",
        "session_id",
        "outcome",
        "idempotency_key",
        "record_type",
        "key_sha256",
        "value_sha256",
        "value_bytes",
        "recipient_sha256",
        "retention_class",
        "expires_at",
        "state_digest_before",
        "state_digest_after",
        "observed_mapping_state",
        "observed_session_id",
        "observed_state_digest",
        "trust_label",
        "authoritative",
    )
)


def validate_project_memory_result(
    result: Any,
    request: ProjectMemoryExecutionRequest,
    contract: ProjectMemoryContract,
    normalized: Mapping[str, JsonValue],
) -> Tuple[str, Dict[str, JsonValue]]:
    if not isinstance(result, ProjectMemoryExecutionResult):
        raise ValidationError("project-memory executor returned an invalid type")
    if result.outcome not in ("succeeded", "failed", "recovery_required"):
        raise ValidationError("project-memory executor outcome is invalid")
    if result.transient is not None and (
        not isinstance(result.transient, bytes)
        or len(result.transient) > _MAX_TRANSIENT_BYTES
    ):
        raise ValidationError("project-memory transient output is invalid")
    if contract.transient_output:
        if result.outcome == "succeeded" and result.transient is None:
            raise ValidationError("successful project-memory operation omitted transient output")
        if (
            result.outcome == "succeeded"
            and result.transient == b""
            and not contract.allow_empty_transient
        ):
            raise ValidationError("successful project-memory operation emitted empty output")
        if result.outcome != "succeeded" and result.transient is not None:
            raise BindingMismatch("unsuccessful project-memory operation cannot emit transient output")
    receipt = result.receipt
    if not isinstance(receipt, dict) or set(receipt) != _RECEIPT_KEYS:
        raise ValidationError("project-memory receipt fields are not exact")
    expected_session = normalized.get("expected_session_id")
    identity = {
        "schema_version": 1,
        "memory_op_id": request.memory_op_id,
        "memory_id": request.memory_id,
        "handoff_id": request.handoff_id,
        "run_id": request.run_id,
        "call_id": request.call_id,
        "decision_id": request.decision_id,
        "evidence_id": request.evidence_id,
        "tool": request.tool,
        "input_digest": request.input_digest,
        "actor": request.actor,
        "workspace": request.workspace,
        "policy": request.policy,
        "project_digest": request.project_digest,
        "observed_mapping_state": request.observation.mapping_state,
        "observed_session_id": request.observation.session_id,
        "observed_state_digest": request.observation.state_digest,
        "expected_session_id": expected_session,
        "outcome": result.outcome,
        "idempotency_key": request.memory_op_id,
        "record_type": contract.record_type,
        "trust_label": "kernel_bound",
        "authoritative": False,
    }
    if any(receipt.get(key) != value for key, value in identity.items()):
        raise BindingMismatch("project-memory receipt identity is invalid")
    session_id = receipt.get("session_id")
    if request.tool in PROJECT_MEMORY_READ_TOOLS:
        if expected_session is not None:
            raise BindingMismatch("project-memory read cannot assert caller session authority")
        if request.observation.session_id is None:
            if session_id is not None or result.outcome == "succeeded":
                raise BindingMismatch("unmapped project-memory read has an invalid session")
        elif session_id != request.observation.session_id:
            raise BindingMismatch("project-memory read changed its observed session")
        if result.outcome == "succeeded" and request.observation.mapping_state not in (
            "active",
            "closed",
        ):
            raise BindingMismatch("project-memory read succeeded from an invalid mapping")
    else:
        if not isinstance(session_id, str) or _SESSION_ID.fullmatch(session_id) is None:
            raise ValidationError("project-memory receipt session_id is invalid")
        if request.tool != PROJECT_MEMORY_ENSURE and session_id != expected_session:
            raise BindingMismatch("project-memory receipt violates session CAS")
    key_digest, value_digest, value_bytes, recipient_digest = _derived_value_metadata(
        request.tool, normalized, result.transient
    )
    expected_metadata = {
        "key_sha256": key_digest,
        "value_sha256": value_digest,
        "value_bytes": value_bytes,
        "recipient_sha256": recipient_digest,
        "retention_class": request.retention_class,
        "expires_at": request.expires_at,
    }
    if any(receipt.get(key) != value for key, value in expected_metadata.items()):
        raise BindingMismatch("project-memory receipt content metadata is invalid")
    _digest(receipt.get("state_digest_before"), "state_digest_before")
    _digest(receipt.get("state_digest_after"), "state_digest_after")
    return result.outcome, dict(receipt)


def validate_durable_project_memory_receipt(
    receipt: Mapping[str, JsonValue],
    *,
    run_id: str,
    call_id: str,
    decision_id: str,
    evidence_id: str,
    tool: str,
    input_digest: str,
    actor: str,
    workspace: str,
    policy: str,
    evidence_outcome: str,
) -> Dict[str, JsonValue]:
    """Validate the metadata-only receipt that is safe to replay from Evidence."""
    registry = FixedProjectMemoryRegistry()
    contract = registry.contract(tool)
    if not isinstance(receipt, dict) or set(receipt) != _RECEIPT_KEYS:
        raise BindingMismatch("durable project-memory receipt fields are not exact")
    allowed_receipt_outcomes = {
        "succeeded": frozenset(("succeeded",)),
        "failed": frozenset(("failed", "recovery_required")),
    }.get(evidence_outcome)
    if (
        allowed_receipt_outcomes is None
        or receipt.get("outcome") not in allowed_receipt_outcomes
    ):
        raise BindingMismatch("project-memory receipt outcome is not durable")
    exact_identity = {
        "schema_version": 1,
        "run_id": run_id,
        "call_id": call_id,
        "decision_id": decision_id,
        "evidence_id": evidence_id,
        "tool": tool,
        "input_digest": input_digest,
        "actor": actor,
        "workspace": workspace,
        "policy": policy,
        "record_type": contract.record_type,
        "trust_label": "kernel_bound",
        "authoritative": False,
    }
    if any(receipt.get(key) != value for key, value in exact_identity.items()):
        raise BindingMismatch("durable project-memory receipt identity is invalid")
    memory_op_id = receipt.get("memory_op_id")
    if (
        not isinstance(memory_op_id, str)
        or _CORRELATION_ID.fullmatch(memory_op_id) is None
        or receipt.get("idempotency_key") != memory_op_id
    ):
        raise BindingMismatch("project-memory receipt idempotency identity is invalid")
    memory_id = receipt.get("memory_id")
    handoff_id = receipt.get("handoff_id")
    if tool in PROJECT_MEMORY_READ_TOOLS:
        if memory_id is not None or handoff_id is not None:
            raise BindingMismatch("project-memory read cannot create an aggregate identity")
    elif tool == PROJECT_MEMORY_HANDOFF:
        if memory_id is not None or not isinstance(handoff_id, str):
            raise BindingMismatch("handoff receipt aggregate identity is invalid")
        if _CORRELATION_ID.fullmatch(handoff_id) is None:
            raise BindingMismatch("handoff receipt ID is invalid")
    else:
        if handoff_id is not None or not isinstance(memory_id, str):
            raise BindingMismatch("memory receipt aggregate identity is invalid")
        if _CORRELATION_ID.fullmatch(memory_id) is None:
            raise BindingMismatch("memory receipt ID is invalid")
    _digest(receipt.get("project_digest"), "project_digest")
    session_id = receipt.get("session_id")
    expected_session = receipt.get("expected_session_id")
    if tool in PROJECT_MEMORY_READ_TOOLS:
        if expected_session is not None:
            raise BindingMismatch("durable project-memory read asserts caller session")
        observed_session = receipt.get("observed_session_id")
        if session_id != observed_session:
            raise BindingMismatch("durable project-memory read changed observed session")
        if session_id is not None and (
            not isinstance(session_id, str) or _SESSION_ID.fullmatch(session_id) is None
        ):
            raise BindingMismatch("durable project-memory read session ID is invalid")
        if receipt.get("outcome") == "succeeded" and session_id is None:
            raise BindingMismatch("successful durable project-memory read lacks a session")
    elif tool == PROJECT_MEMORY_ENSURE:
        if not isinstance(session_id, str) or _SESSION_ID.fullmatch(session_id) is None:
            raise BindingMismatch("durable project-memory session ID is invalid")
        if expected_session is not None:
            raise BindingMismatch("ensure receipt cannot assert an expected session")
    else:
        if (
            not isinstance(session_id, str)
            or _SESSION_ID.fullmatch(session_id) is None
            or not isinstance(expected_session, str)
            or _SESSION_ID.fullmatch(expected_session) is None
            or session_id != expected_session
        ):
            raise BindingMismatch("durable project-memory receipt violates session CAS")
    observed_state = receipt.get("observed_mapping_state")
    observed_session = receipt.get("observed_session_id")
    if observed_state not in ("absent", "active", "closed", "invalid"):
        raise BindingMismatch("durable project-memory observation state is invalid")
    if observed_state == "absent":
        if observed_session is not None:
            raise BindingMismatch("absent durable observation has a session")
    elif not isinstance(observed_session, str) or _SESSION_ID.fullmatch(observed_session) is None:
        raise BindingMismatch("mapped durable observation lacks a session")
    _digest(receipt.get("observed_state_digest"), "observed_state_digest")
    for field in (
        "value_sha256",
        "state_digest_before",
        "state_digest_after",
    ):
        _digest(receipt.get(field), field)
    for field in ("key_sha256", "recipient_sha256"):
        value = receipt.get(field)
        if value is not None:
            _digest(value, field)
    value_bytes = receipt.get("value_bytes")
    if type(value_bytes) is not int or not 0 <= value_bytes <= _MAX_TRANSIENT_BYTES:
        raise BindingMismatch("durable project-memory value size is invalid")
    retention = receipt.get("retention_class")
    if retention not in ("session", "project", "expiring"):
        raise BindingMismatch("durable project-memory retention is invalid")
    expires_at = receipt.get("expires_at")
    _timestamp(expires_at)
    if (retention == "expiring") != (expires_at is not None):
        raise BindingMismatch("durable project-memory expiry is inconsistent")
    return dict(receipt)


def legacy_memory_view(
    *,
    memory_id: str,
    value_sha256: str,
    value_bytes: int,
    expires_at: Optional[str],
) -> LegacyMemoryView:
    if not isinstance(memory_id, str) or not memory_id:
        raise ValidationError("legacy memory_id is invalid")
    _digest(value_sha256, "legacy value_sha256")
    if type(value_bytes) is not int or value_bytes < 0:
        raise ValidationError("legacy value size is invalid")
    _timestamp(expires_at)
    return LegacyMemoryView(memory_id, value_sha256, value_bytes, expires_at)


@contextmanager
def _request_lock(ledger: Path, correlation: str) -> Iterator[None]:
    if _CORRELATION_ID.fullmatch(correlation) is None:
        raise ValidationError("client_correlation_id is malformed")
    runtime = ledger.parent / ".mainframe-control-plane-runtime"
    create_directory_durable(runtime, mode=0o700, parents=False)
    metadata = runtime.lstat()
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or stat.S_ISLNK(metadata.st_mode)
        or metadata.st_uid != os.geteuid()
        or stat.S_IMODE(metadata.st_mode) & 0o077
    ):
        raise ExecutionDenied("project-memory request lock directory is unsafe")
    path = runtime / "memory-lock-{}.lock".format(
        hashlib.sha256(correlation.encode("utf-8")).hexdigest()
    )
    flags = os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(str(path), flags, 0o600)
    except OSError as exc:
        raise ExecutionDenied("project-memory request lock is unavailable") from exc
    try:
        locked = os.fstat(fd)
        if (
            not stat.S_ISREG(locked.st_mode)
            or locked.st_uid != os.geteuid()
            or stat.S_IMODE(locked.st_mode) & 0o077
            or locked.st_nlink != 1
        ):
            raise ExecutionDenied("project-memory request lock is unsafe")
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


class ProjectMemoryControlPlane:
    """Atomic host API with kernel-generated IDs and an injected fixed executor."""

    def __init__(
        self,
        ledger_path: Union[str, os.PathLike[str]],
        *,
        executor: ProjectMemoryExecutor,
        clock: Optional[Clock] = None,
    ) -> None:
        ledger = Path(ledger_path)
        create_directory_durable(ledger.parent, mode=0o700, parents=True)
        self._registry = FixedProjectMemoryRegistry()
        arguments: Dict[str, Any] = {
            "evaluator": FixedProjectMemoryEvaluator(self._registry)
        }
        if clock is not None:
            arguments["clock"] = clock
        self._kernel = ControlPlaneKernel(ledger, **arguments)
        self._ledger = ledger
        self._executor = executor
        self._clock = clock
        self._thread_lock = threading.Lock()

    def snapshot(self) -> Snapshot:
        return self._kernel.snapshot()

    def inspect_legacy(
        self, records: List[LegacyMemoryView]
    ) -> Tuple[LegacyMemoryView, ...]:
        if any(
            not isinstance(item, LegacyMemoryView)
            or item.trust_label != "untrusted_legacy"
            or item.authoritative is not False
            for item in records
        ):
            raise ExecutionDenied("legacy memory view is not safely labeled")
        return tuple(records)

    def visible_memory_records(self) -> Dict[str, MemoryRecord]:
        now = self._clock() if self._clock is not None else datetime.now(timezone.utc)
        visible: Dict[str, MemoryRecord] = {}
        for memory_id, record in self.snapshot().memory_records.items():
            if record.expires_at is None:
                visible[memory_id] = record
                continue
            expires = datetime.fromisoformat(record.expires_at.replace("Z", "+00:00"))
            if now.astimezone(timezone.utc) < expires.astimezone(timezone.utc):
                visible[memory_id] = record
        return visible

    def result_for_correlation(
        self, client_correlation_id: str
    ) -> Optional[ProjectMemoryInvocationResult]:
        """Return only a terminal durable result; transient bytes are never replayed."""
        snapshot = self._kernel.snapshot()
        request = snapshot.canonical_requests.get(client_correlation_id)
        if request is None or request.reservation_binding is None:
            return None
        observation, _retention, _expires = (
            parse_project_memory_reservation_binding(request.reservation_binding)
        )
        call = snapshot.tool_calls.get(request.call_id)
        if call is None or call.state not in (
            "succeeded",
            "failed",
            "interrupted",
            "timed_out",
        ):
            return None
        run = snapshot.runs.get(call.run_id)
        if run is None or run.state not in ("completed", "failed"):
            # The worker records Evidence before aggregate creation and Run
            # closure.  Waiting for the terminal Run prevents a second process
            # from racing the worker's aggregate finalization transaction.
            return None
        evidence = [
            item for item in snapshot.evidence.values() if item.call_id == call.call_id
        ]
        if len(evidence) != 1:
            raise InvalidTransition("terminal project-memory call lacks unique Evidence")
        return self._result(call.call_id, observation.project_digest, None)

    def invoke(
        self,
        *,
        client_correlation_id: str,
        tool: str,
        tool_input: Mapping[str, JsonValue],
        actor: str,
        workspace: str,
        result_sink: Optional[Callable[[ProjectMemoryExecutionResult], None]] = None,
        after_start_hook: Optional[Callable[[], None]] = None,
        after_evidence_hook: Optional[Callable[[], None]] = None,
    ) -> ProjectMemoryInvocationResult:
        with self._thread_lock:
            with _request_lock(self._ledger, client_correlation_id):
                return self._invoke_locked(
                    client_correlation_id,
                    tool,
                    tool_input,
                    actor,
                    workspace,
                    result_sink,
                    after_start_hook,
                    after_evidence_hook,
                )

    def reserve(
        self,
        *,
        client_correlation_id: str,
        tool: str,
        tool_input: Mapping[str, JsonValue],
        actor: str,
        workspace: str,
    ) -> "CanonicalRequestRecord":
        """Reserve exact generated identities and first observation without executing."""
        with self._thread_lock:
            with _request_lock(self._ledger, client_correlation_id):
                _normalized, request, _project_digest = self._reserve_locked(
                    client_correlation_id,
                    tool,
                    tool_input,
                    actor,
                    workspace,
                )
                return request

    def _reserve_locked(
        self,
        correlation: str,
        tool: str,
        tool_input: Mapping[str, JsonValue],
        actor: str,
        workspace: str,
    ) -> Tuple[Dict[str, JsonValue], "CanonicalRequestRecord", str]:
        normalized = self._registry.normalize_input(tool, tool_input)
        if not os.path.isabs(workspace):
            raise ExecutionDenied("project-memory workspace must be absolute")
        canonical_workspace = os.path.realpath(os.path.normpath(workspace))
        project_digest = hashlib.sha256(canonical_workspace.encode("utf-8")).hexdigest()
        input_digest = normalized_input_digest(normalized)
        input_metadata = normalized_input_metadata(normalized)
        snapshot = self._kernel.snapshot()
        request = snapshot.canonical_requests.get(correlation)
        if request is None:
            observation = _validate_observation(
                self._executor.observe(canonical_workspace, project_digest),
                project_digest,
            )
            now = self._clock() if self._clock is not None else datetime.now(timezone.utc)
            retention, expires_at = _reservation_retention(tool, normalized, now)
            binding = project_memory_reservation_binding(
                observation,
                retention_class=retention,
                expires_at=expires_at,
            )
            try:
                request = self._kernel._reserve_project_memory_request(
                    client_correlation_id=correlation,
                    tool=tool,
                    tool_input=normalized,
                    actor=actor,
                    workspace=canonical_workspace,
                    policy=PROJECT_MEMORY_POLICY,
                    reservation_binding=binding,
                )
            except AlreadyExists:
                request = self._kernel.snapshot().canonical_requests[correlation]
        if (
            request.canonical_id != tool
            or request.input_digest != input_digest
            or request.input_metadata != input_metadata
            or request.actor != actor
            or request.workspace != canonical_workspace
            or request.policy != PROJECT_MEMORY_POLICY
        ):
            raise BindingMismatch("correlation is bound to another memory operation")
        observation, _retention, _expires = (
            parse_project_memory_reservation_binding(request.reservation_binding)
        )
        if observation.project_digest != project_digest:
            raise BindingMismatch("reserved project observation changed workspace")
        return normalized, request, project_digest

    def _invoke_locked(
        self,
        correlation: str,
        tool: str,
        tool_input: Mapping[str, JsonValue],
        actor: str,
        workspace: str,
        result_sink: Optional[Callable[[ProjectMemoryExecutionResult], None]],
        after_start_hook: Optional[Callable[[], None]],
        after_evidence_hook: Optional[Callable[[], None]],
    ) -> ProjectMemoryInvocationResult:
        normalized, request, project_digest = self._reserve_locked(
            correlation, tool, tool_input, actor, workspace
        )
        memory_op_id = "memory-op-{}".format(
            hashlib.sha256(request.call_id.encode("utf-8")).hexdigest()[:32]
        )
        if tool == PROJECT_MEMORY_HANDOFF:
            memory_id = None
            handoff_id = "handoff-{}".format(
                hashlib.sha256(memory_op_id.encode("utf-8")).hexdigest()[:32]
            )
        elif tool in PROJECT_MEMORY_MUTATION_TOOLS:
            memory_id = "memory-{}".format(
                hashlib.sha256(memory_op_id.encode("utf-8")).hexdigest()[:32]
            )
            handoff_id = None
        else:
            memory_id = None
            handoff_id = None
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
            call = self._kernel._create_project_memory_tool_call(
                call_id=request.call_id,
                run_id=request.run_id,
                tool=tool,
                tool_input=normalized,
                client_correlation_id=correlation,
            )
        if call.state == "running":
            self._kernel._recover_project_memory_execution(call.call_id)
            self._close_run(call.run_id, False)
            return self._result(call.call_id, project_digest, None)
        decisions = [
            item
            for item in self._kernel.snapshot().policy_decisions.values()
            if item.call_id == call.call_id
        ]
        if not decisions and call.state == "pending":
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
        call = self._kernel.snapshot().tool_calls[call.call_id]
        if call.state in ("succeeded", "failed", "interrupted", "timed_out"):
            self._kernel._finalize_project_memory_aggregate(call.call_id)
            succeeded = self._result(call.call_id, project_digest, None).outcome == "succeeded"
            self._close_run(call.run_id, succeeded)
            return self._result(call.call_id, project_digest, None)
        transient: List[ProjectMemoryExecutionResult] = []
        evidence = self._kernel._execute_project_memory(
            call.call_id,
            tool_input=normalized,
            executor=self._executor,
            memory_op_id=memory_op_id,
            memory_id=memory_id,
            handoff_id=handoff_id,
            project_digest=project_digest,
            result_sink=transient.append,
            after_start_hook=after_start_hook,
            after_evidence_hook=after_evidence_hook,
        )
        self._kernel._finalize_project_memory_aggregate(call.call_id)
        outcome = self._evidence_outcome(evidence.body, evidence.outcome)
        self._close_run(call.run_id, outcome == "succeeded")
        first = transient[0] if transient else None
        if result_sink is not None and first is not None:
            try:
                result_sink(first)
            except Exception:
                pass
        return self._result(call.call_id, project_digest, first)

    @staticmethod
    def _evidence_outcome(body: Mapping[str, JsonValue], outcome: str) -> str:
        receipt = body.get("project_memory_receipt")
        if isinstance(receipt, dict) and receipt.get("outcome") == "recovery_required":
            return "recovery_required"
        error = body.get("error")
        if isinstance(error, dict) and error.get("code") == "recovery_required":
            return "recovery_required"
        return outcome

    def _close_run(self, run_id: str, succeeded: bool) -> None:
        run = self._kernel.snapshot().runs[run_id]
        if run.state == "active":
            self._kernel.transition_run(run_id, "completed" if succeeded else "failed")

    def _result(
        self,
        call_id: str,
        project_digest: str,
        transient: Optional[ProjectMemoryExecutionResult],
    ) -> ProjectMemoryInvocationResult:
        snapshot = self._kernel.snapshot()
        call = snapshot.tool_calls[call_id]
        request = snapshot.canonical_requests[cast(str, call.client_correlation_id)]
        evidence = [item for item in snapshot.evidence.values() if item.call_id == call_id]
        if len(evidence) != 1:
            raise InvalidTransition("project-memory call lacks unique Evidence")
        item = evidence[0]
        receipt_value = item.body.get("project_memory_receipt")
        receipt = dict(receipt_value) if isinstance(receipt_value, dict) else None
        outcome = self._evidence_outcome(item.body, item.outcome)
        memory = [item for item in snapshot.memory_records.values() if item.call_id == call_id]
        handoff = [item for item in snapshot.handoff_records.values() if item.call_id == call_id]
        if len(memory) > 1 or len(handoff) > 1 or (memory and handoff):
            raise InvalidTransition("project-memory aggregate identity is ambiguous")
        transient_value = None if transient is None else transient.transient
        return ProjectMemoryInvocationResult(
            1,
            "completed",
            request.client_correlation_id,
            cast(str, receipt["memory_op_id"]) if receipt else "memory-op-unavailable",
            cast(Optional[str], receipt["memory_id"]) if receipt else None,
            cast(Optional[str], receipt["handoff_id"]) if receipt else None,
            call.run_id,
            call.call_id,
            request.decision_id,
            item.evidence_id,
            call.input_digest,
            project_digest,
            cast(Optional[str], receipt["session_id"]) if receipt else None,
            outcome,
            transient_value is not None,
            receipt,
            memory[0] if memory else None,
            handoff[0] if handoff else None,
            transient_value,
        )

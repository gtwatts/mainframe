"""Anonymous project-memory worker result encoding and durable revalidation."""

from __future__ import annotations

import base64
import binascii
import hashlib
import json
from typing import Any, Dict

from .errors import BindingMismatch, ValidationError
from .memory import (
    PROJECT_MEMORY_HANDOFF,
    PROJECT_MEMORY_READ_TOOLS,
    ProjectMemoryInvocationResult,
)


MAX_PROJECT_MEMORY_RESULT_BYTES = 65536


def _canonical_json(value: Any) -> bytes:
    try:
        return json.dumps(
            value,
            allow_nan=False,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
    except (TypeError, ValueError, UnicodeError) as exc:
        raise ValidationError("project-memory transient result is not canonical JSON") from exc


def encode_project_memory_result(result: ProjectMemoryInvocationResult) -> bytes:
    if not result.result_available or result.transient is None:
        raise ValidationError("project-memory worker has no transient result to deliver")
    payload = {
        "schema_version": 1,
        "client_correlation_id": result.client_correlation_id,
        "memory_op_id": result.memory_op_id,
        "memory_id": result.memory_id,
        "handoff_id": result.handoff_id,
        "run_id": result.run_id,
        "call_id": result.call_id,
        "decision_id": result.decision_id,
        "evidence_id": result.evidence_id,
        "input_digest": result.input_digest,
        "project_digest": result.project_digest,
        "session_id": result.session_id,
        "outcome": result.outcome,
        "receipt": result.receipt,
        "transient_b64": base64.b64encode(result.transient).decode("ascii"),
    }
    encoded = _canonical_json(payload)
    if len(encoded) > MAX_PROJECT_MEMORY_RESULT_BYTES:
        raise ValidationError("project-memory transient result exceeds its limit")
    return encoded


def decode_project_memory_result(
    raw: bytes,
    durable: ProjectMemoryInvocationResult,
) -> bytes:
    if len(raw) > MAX_PROJECT_MEMORY_RESULT_BYTES:
        raise ValidationError("project-memory transient result exceeds its limit")
    try:
        value = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValidationError("project-memory transient result is invalid JSON") from exc
    exact_keys = {
        "schema_version",
        "client_correlation_id",
        "memory_op_id",
        "memory_id",
        "handoff_id",
        "run_id",
        "call_id",
        "decision_id",
        "evidence_id",
        "input_digest",
        "project_digest",
        "session_id",
        "outcome",
        "receipt",
        "transient_b64",
    }
    if not isinstance(value, dict) or set(value) != exact_keys:
        raise ValidationError("project-memory transient result fields are not exact")
    expected: Dict[str, Any] = {
        "schema_version": 1,
        "client_correlation_id": durable.client_correlation_id,
        "memory_op_id": durable.memory_op_id,
        "memory_id": durable.memory_id,
        "handoff_id": durable.handoff_id,
        "run_id": durable.run_id,
        "call_id": durable.call_id,
        "decision_id": durable.decision_id,
        "evidence_id": durable.evidence_id,
        "input_digest": durable.input_digest,
        "project_digest": durable.project_digest,
        "session_id": durable.session_id,
        "outcome": durable.outcome,
        "receipt": durable.receipt,
    }
    if any(value.get(key) != expected_value for key, expected_value in expected.items()):
        raise BindingMismatch("project-memory transient result identity is invalid")
    if durable.receipt is None or durable.receipt.get("tool") not in (
        PROJECT_MEMORY_READ_TOOLS | {PROJECT_MEMORY_HANDOFF}
    ):
        raise BindingMismatch("project-memory tool cannot return transient bytes")
    try:
        transient = base64.b64decode(value["transient_b64"], validate=True)
    except (TypeError, ValueError, binascii.Error) as exc:
        raise ValidationError("project-memory transient result is not strict base64") from exc
    if (
        durable.receipt.get("value_bytes") != len(transient)
        or durable.receipt.get("value_sha256")
        != hashlib.sha256(transient).hexdigest()
    ):
        raise BindingMismatch("project-memory transient bytes contradict durable Evidence")
    return transient

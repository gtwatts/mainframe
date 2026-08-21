"""Bounded anonymous worker-to-foreground result validation."""

from __future__ import annotations

import json
from typing import Any, Dict

from .errors import BindingMismatch, ValidationError
from .kernel import (
    CanonicalExecutionResult,
    CanonicalRequestRecord,
    EvidenceRecord,
    ToolCallRecord,
    _validated_canonical_result,
)
from .contracts import StableCoreContract


MAX_TRANSIENT_RESULT_BYTES = 2 * 1024 * 1024


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
        raise ValidationError("transient value is not canonical UTF-8 JSON") from exc


def encode_canonical_result(
    request: CanonicalRequestRecord,
    result: CanonicalExecutionResult,
) -> bytes:
    payload = {
        "client_correlation_id": request.client_correlation_id,
        "call_id": request.call_id,
        "input_digest": request.input_digest,
        "outcome": result.outcome,
        "broker_envelope": result.envelope,
        "executor_error": result.error,
    }
    encoded = _canonical_json(payload)
    if len(encoded) > MAX_TRANSIENT_RESULT_BYTES:
        raise ValidationError("transient canonical result exceeds its size limit")
    return encoded


def decode_canonical_result(
    raw: bytes,
    request: CanonicalRequestRecord,
    call: ToolCallRecord,
    evidence: EvidenceRecord,
    contract: StableCoreContract,
) -> Dict[str, Any]:
    if len(raw) > MAX_TRANSIENT_RESULT_BYTES:
        raise ValidationError("transient canonical result exceeds its size limit")
    try:
        value = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValidationError("transient canonical result is invalid") from exc
    if not isinstance(value, dict) or set(value) != {
        "client_correlation_id",
        "call_id",
        "input_digest",
        "outcome",
        "broker_envelope",
        "executor_error",
    }:
        raise ValidationError("transient canonical result fields are not exact")
    if (
        value["client_correlation_id"] != request.client_correlation_id
        or value["call_id"] != request.call_id
        or value["input_digest"] != request.input_digest
    ):
        raise BindingMismatch("transient canonical result binding is invalid")
    result = CanonicalExecutionResult(
        outcome=value["outcome"],
        envelope=value["broker_envelope"],
        error=value["executor_error"],
    )
    derived_outcome, derived_body = _validated_canonical_result(
        result, call, contract
    )
    if (
        derived_outcome != evidence.outcome
        or value["outcome"] != evidence.outcome
        or derived_body != evidence.body
    ):
        raise BindingMismatch(
            "transient canonical result does not match durable Evidence"
        )
    return value

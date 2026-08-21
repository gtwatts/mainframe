"""Crash-resumable per-request stable-core worker."""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
from pathlib import Path
import stat
from typing import Dict, Optional

from .contracts import FixedStableCoreEvaluator, load_fixed_stable_core_registry
from .errors import ExecutionDenied, NotFound
from .executor import FixedStableCoreSubprocessExecutor, _runtime_directory
from .kernel import (
    CanonicalExecutionResult,
    CanonicalRequestRecord,
    ControlPlaneKernel,
    EvidenceRecord,
    JsonValue,
)
from .transient import encode_canonical_result


_MAX_INPUT_BYTES = 32768


def _read_transient_input(input_fd: int) -> Dict[str, JsonValue]:
    if type(input_fd) is not int or input_fd < 3:
        raise ExecutionDenied("canonical worker input descriptor is invalid")
    chunks = []
    total = 0
    try:
        while True:
            chunk = os.read(input_fd, min(65536, _MAX_INPUT_BYTES + 1 - total))
            if not chunk:
                break
            total += len(chunk)
            if total > _MAX_INPUT_BYTES:
                raise ExecutionDenied("canonical worker input exceeds 32768 bytes")
            chunks.append(chunk)
    finally:
        os.close(input_fd)
    try:
        value = json.loads(b"".join(chunks).decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ExecutionDenied("canonical worker input is invalid UTF-8 JSON") from exc
    if not isinstance(value, dict):
        raise ExecutionDenied("canonical worker input must be an object")
    return value


def _close_fd(fd: int) -> None:
    try:
        os.close(fd)
    except OSError:
        pass


def _write_transient_result(
    result_fd: int,
    request: CanonicalRequestRecord,
    result: CanonicalExecutionResult,
) -> None:
    content = encode_canonical_result(request, result)
    offset = 0
    try:
        while offset < len(content):
            written = os.write(result_fd, content[offset:])
            if written <= 0:
                raise OSError("canonical result handoff made no progress")
            offset += written
    except BrokenPipeError:
        # The foreground caller died; the raw result is discarded and only the
        # metadata-only durable Evidence remains.
        return


def _worker_lock(ledger_path: Path, correlation_id: str) -> Optional[int]:
    runtime = _runtime_directory(ledger_path, create=True)
    name = hashlib.sha256(correlation_id.encode("utf-8")).hexdigest()[:40]
    path = runtime / ("worker-{}.lock".format(name))
    flags = os.O_RDWR | os.O_CREAT | os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(str(path), flags, 0o600)
    metadata = os.fstat(fd)
    if (
        not stat.S_ISREG(metadata.st_mode)
        or metadata.st_uid != os.geteuid()
        or stat.S_IMODE(metadata.st_mode) & 0o077
    ):
        os.close(fd)
        raise ExecutionDenied("canonical worker lock is unsafe")
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(fd)
        return None
    return fd


def run_canonical_worker(
    ledger_path: Path, correlation_id: str, *, input_fd: int, result_fd: int
) -> None:
    lock_fd = _worker_lock(ledger_path, correlation_id)
    if lock_fd is None:
        _close_fd(input_fd)
        _close_fd(result_fd)
        return
    try:
        registry = load_fixed_stable_core_registry()
        kernel = ControlPlaneKernel(
            ledger_path,
            evaluator=FixedStableCoreEvaluator(registry),
            stable_core_registry=registry,
        )
        snapshot = kernel.snapshot()
        try:
            request = snapshot.canonical_requests[correlation_id]
        except KeyError as exc:
            raise NotFound("canonical request was not reserved") from exc
        run = snapshot.runs.get(request.run_id)
        call = snapshot.tool_calls.get(request.call_id)
        if call is not None and call.state == "running":
            _close_fd(input_fd)
            return
        if call is not None and call.state in (
            "succeeded",
            "failed",
            "timed_out",
            "interrupted",
        ):
            _close_fd(input_fd)
            matches = [
                item for item in snapshot.evidence.values()
                if item.call_id == call.call_id
            ]
            if len(matches) == 1 and run is not None and run.state == "active":
                kernel.transition_run(
                    request.run_id,
                    "completed" if matches[0].outcome == "succeeded" else "failed",
                )
            return
        transient_input = _read_transient_input(input_fd)
        transient_input = registry.normalize_input(
            request.canonical_id, transient_input
        )
        if run is None:
            run = kernel.create_run(
                run_id=request.run_id,
                actor=request.actor,
                workspace=request.workspace,
                policy=request.policy,
            )
        if run.state == "created":
            run = kernel.transition_run(run.run_id, "active")
        if run.state != "active":
            return
        snapshot = kernel.snapshot()
        call = snapshot.tool_calls.get(request.call_id)
        if call is None:
            call = kernel.create_canonical_tool_call(
                call_id=request.call_id,
                run_id=request.run_id,
                canonical_id=request.canonical_id,
                tool_input=transient_input,
                client_correlation_id=request.client_correlation_id,
            )
        if call.state == "pending":
            kernel.evaluate_policy_decision(
                decision_id=request.decision_id,
                call_id=call.call_id,
                tool=call.tool,
                input_digest=call.input_digest,
                actor=call.actor,
                workspace=call.workspace,
                policy=call.policy,
                timeout_at=call.timeout_at,
                tool_input=transient_input,
            )
            call = kernel.snapshot().tool_calls[call.call_id]
        evidence: Optional[EvidenceRecord] = None
        if call.state == "ready":
            executor = FixedStableCoreSubprocessExecutor(
                registry=registry,
                call=call,
                ledger_path=ledger_path,
            )
            evidence = kernel.execute_canonical(
                call.call_id,
                executor=executor,
                tool_input=transient_input,
                result_sink=lambda result: _write_transient_result(
                    result_fd, request, result
                ),
            )
        elif call.state in ("succeeded", "failed", "timed_out", "interrupted"):
            matches = [
                item for item in kernel.snapshot().evidence.values()
                if item.call_id == call.call_id
            ]
            if len(matches) == 1:
                evidence = matches[0]
        # A running call is owned by another live/failed executor and is never retried.
        if evidence is not None:
            current_run = kernel.snapshot().runs[request.run_id]
            if current_run.state == "active":
                kernel.transition_run(
                    request.run_id,
                    "completed" if evidence.outcome == "succeeded" else "failed",
                )
    finally:
        _close_fd(input_fd)
        _close_fd(result_fd)
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)

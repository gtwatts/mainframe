"""Detached per-correlation worker for fixed project-memory operations."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Dict

from .errors import BindingMismatch, ExecutionDenied, NotFound
from .kernel import JsonValue, normalized_input_digest, normalized_input_metadata
from .memory import (
    ProjectMemoryControlPlane,
    parse_project_memory_reservation_binding,
)
from .memory_executor import FixedProjectMemorySubprocessExecutor
from .memory_transient import encode_project_memory_result
from .worker import _close_fd, _worker_lock


_MAX_INPUT_BYTES = 32768


def _read_input(input_fd: int) -> Dict[str, JsonValue]:
    if type(input_fd) is not int or input_fd < 3:
        raise ExecutionDenied("project-memory worker input descriptor is invalid")
    chunks = []
    total = 0
    try:
        while True:
            chunk = os.read(input_fd, min(65536, _MAX_INPUT_BYTES + 1 - total))
            if not chunk:
                break
            total += len(chunk)
            if total > _MAX_INPUT_BYTES:
                raise ExecutionDenied("project-memory worker input exceeds 32768 bytes")
            chunks.append(chunk)
    finally:
        os.close(input_fd)
    try:
        value = json.loads(b"".join(chunks).decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ExecutionDenied("project-memory worker input is invalid JSON") from exc
    if not isinstance(value, dict):
        raise ExecutionDenied("project-memory worker input must be an object")
    return value


def _write_result(result_fd: int, content: bytes) -> None:
    offset = 0
    try:
        while offset < len(content):
            written = os.write(result_fd, content[offset:])
            if written <= 0:
                raise OSError("project-memory result handoff made no progress")
            offset += written
    except BrokenPipeError:
        return


def run_project_memory_worker(
    ledger_path: Path,
    correlation_id: str,
    *,
    input_fd: int,
    result_fd: int,
) -> None:
    lock_fd = _worker_lock(ledger_path, correlation_id)
    if lock_fd is None:
        _close_fd(input_fd)
        _close_fd(result_fd)
        return
    try:
        executor = FixedProjectMemorySubprocessExecutor(ledger_path=ledger_path)
        control = ProjectMemoryControlPlane(ledger_path, executor=executor)
        snapshot = control.snapshot()
        try:
            request = snapshot.canonical_requests[correlation_id]
        except KeyError as exc:
            raise NotFound("project-memory request was not reserved") from exc
        parse_project_memory_reservation_binding(request.reservation_binding)
        call = snapshot.tool_calls.get(request.call_id)
        if call is not None and call.state in (
            "succeeded",
            "failed",
            "timed_out",
            "interrupted",
        ):
            _close_fd(input_fd)
            return
        transient_input = control._registry.normalize_input(
            request.canonical_id, _read_input(input_fd)
        )
        if (
            normalized_input_digest(transient_input) != request.input_digest
            or normalized_input_metadata(transient_input) != request.input_metadata
        ):
            raise BindingMismatch("project-memory worker input changed after reservation")
        completed = control.invoke(
            client_correlation_id=request.client_correlation_id,
            tool=request.canonical_id,
            tool_input=transient_input,
            actor=request.actor,
            workspace=request.workspace,
        )
        if completed.result_available and completed.transient is not None:
            _write_result(result_fd, encode_project_memory_result(completed))
    finally:
        _close_fd(input_fd)
        _close_fd(result_fd)
        try:
            import fcntl

            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        finally:
            os.close(lock_fd)

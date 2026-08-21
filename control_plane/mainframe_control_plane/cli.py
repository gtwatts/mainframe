"""Structured JSON command line for the local control-plane kernel."""

from __future__ import annotations

import argparse
import base64
import binascii
from dataclasses import dataclass
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import pwd
import signal
import stat
import subprocess
import sys
import threading
import time
from typing import Any, Callable, Mapping, NoReturn, Optional, Sequence, TextIO
import uuid

from .errors import (
    AlreadyExists,
    ApprovalAuthorityUnavailable,
    BindingMismatch,
    ControlPlaneError,
    ExecutorUnavailable,
    LedgerCorruption,
    LedgerIOError,
    InvalidTransition,
    RegistryCorruption,
    ValidationError,
)
from .contracts import (
    FixedStableCoreEvaluator,
    STABLE_CORE_POLICY,
    load_fixed_stable_core_registry,
)
from .executor import (
    probe_canonical_supervisor,
    request_canonical_cancellation,
)
from .durability import create_directory_durable
from .kernel import (
    CanonicalExecutor,
    CanonicalRequestRecord,
    ControlPlaneKernel,
    Executor,
    PolicyEvaluator,
    ToolCallRecord,
    TrustedApprover,
    normalized_input_digest,
    normalized_input_metadata,
)
from .transient import (
    MAX_TRANSIENT_RESULT_BYTES,
    decode_canonical_result,
)
from .worker import run_canonical_worker
from .memory import (
    PROJECT_MEMORY_HANDOFF,
    PROJECT_MEMORY_MUTATION_TOOLS,
    PROJECT_MEMORY_READ_TOOLS,
    ProjectMemoryControlPlane,
    ProjectMemoryInvocationResult,
)
from .memory_executor import FixedProjectMemorySubprocessExecutor
from .memory_transient import (
    MAX_PROJECT_MEMORY_RESULT_BYTES,
    decode_project_memory_result,
)
from .memory_worker import run_project_memory_worker
from .coding import (
    CodingAgentControlPlane,
    CodingInvocationResult,
    FixedWorkspaceCodingExecutor,
)


class _UsageError(Exception):
    pass


class _ForegroundSignalExit(Exception):
    def __init__(self, signal_number: int) -> None:
        super().__init__("foreground canonical invocation was interrupted")
        self.exit_code = 128 + signal_number


class _JsonArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        raise _UsageError(message)


def _parser() -> argparse.ArgumentParser:
    parser = _JsonArgumentParser(prog="mainframe-control-plane", add_help=True)
    parser.add_argument("--ledger", help="Owner-private JSONL ledger path")
    commands = parser.add_subparsers(dest="command", required=True)

    create_run = commands.add_parser("run-create")
    create_run.add_argument("--run-id", required=True)
    create_run.add_argument("--actor", required=True)
    create_run.add_argument("--workspace", required=True)
    create_run.add_argument("--policy", required=True)

    transition_run = commands.add_parser("run-transition")
    transition_run.add_argument("--run-id", required=True)
    transition_run.add_argument(
        "--to", required=True, choices=("active", "completed", "failed", "cancelled")
    )

    create_call = commands.add_parser("call-create")
    create_call.add_argument("--call-id", required=True)
    create_call.add_argument("--run-id", required=True)
    create_call.add_argument("--tool", required=True)
    create_call.add_argument("--effect", required=True, choices=("read_only", "mutating"))
    create_call.add_argument("--input-json", required=True)
    create_call.add_argument("--timeout-at")

    canonical_call = commands.add_parser("canonical-call-create")
    canonical_call.add_argument("--call-id", required=True)
    canonical_call.add_argument("--run-id", required=True)
    canonical_call.add_argument("--canonical-id", required=True)
    canonical_call.add_argument("--input-json", required=True)

    request = commands.add_parser("call-request-approval")
    request.add_argument("--call-id", required=True)

    decision = commands.add_parser("decision-evaluate")
    decision.add_argument("--decision-id", required=True)
    decision.add_argument("--call-id", required=True)
    decision.add_argument("--tool", required=True)
    decision.add_argument("--input-digest", required=True)
    decision.add_argument("--actor", required=True)
    decision.add_argument("--workspace", required=True)
    decision.add_argument("--policy", required=True)
    decision.add_argument("--timeout-at")

    for command_name in ("call-cancel", "call-timeout", "call-recover"):
        resolution = commands.add_parser(command_name)
        resolution.add_argument("--call-id", required=True)
        resolution.add_argument("--tool", required=True)
        resolution.add_argument("--input-digest", required=True)
        resolution.add_argument("--actor", required=True)
        resolution.add_argument("--workspace", required=True)
        resolution.add_argument("--policy", required=True)
        resolution.add_argument("--reason", required=True)

    grant = commands.add_parser("approval-grant")
    grant.add_argument("--approval-id", required=True)
    grant.add_argument("--call-id", required=True)
    grant.add_argument("--tool", required=True)
    grant.add_argument("--input-digest", required=True)
    grant.add_argument("--actor", required=True)
    grant.add_argument("--workspace", required=True)
    grant.add_argument("--policy", required=True)
    grant.add_argument("--expires-at", required=True)

    consume = commands.add_parser("approval-consume")
    consume.add_argument("--approval-id", required=True)
    consume.add_argument("--call-id", required=True)
    consume.add_argument("--actor", required=True)
    consume.add_argument("--workspace", required=True)
    consume.add_argument("--policy", required=True)

    execute = commands.add_parser("trace-execute")
    execute.add_argument("--call-id", required=True)

    canonical_execute = commands.add_parser("canonical-execute")
    canonical_execute.add_argument("--call-id", required=True)

    canonical_invoke = commands.add_parser("canonical-invoke")
    canonical_invoke.add_argument("--canonical-id", required=True)
    canonical_invoke.add_argument("--input-json", required=True)
    canonical_invoke.add_argument("--client-correlation-id", required=True)
    canonical_invoke.add_argument(
        "--format",
        choices=("control-plane-json-v1", "broker-json-v1", "raw"),
        default="control-plane-json-v1",
        help="Presentation only; never part of durable execution identity",
    )

    canonical_cancel = commands.add_parser("canonical-cancel")
    canonical_cancel.add_argument("--client-correlation-id", required=True)

    canonical_worker = commands.add_parser("__canonical-worker-v1")
    canonical_worker.add_argument("--client-correlation-id", required=True)
    canonical_worker.add_argument("--input-fd", required=True, type=int)
    canonical_worker.add_argument("--result-fd", required=True, type=int)

    project_memory = commands.add_parser("project-memory-invoke")
    project_memory.add_argument("--tool-id", required=True)
    project_memory.add_argument("--input-json", required=True, choices=("-",))
    project_memory.add_argument("--client-correlation-id", required=True)
    project_memory.add_argument(
        "--format",
        choices=("control-plane-json-v1", "awm-compatible-v1"),
        default="control-plane-json-v1",
        help="Presentation only; never part of durable execution identity",
    )

    project_memory_worker = commands.add_parser("__project-memory-worker-v1")
    project_memory_worker.add_argument("--client-correlation-id", required=True)
    project_memory_worker.add_argument("--input-fd", required=True, type=int)
    project_memory_worker.add_argument("--result-fd", required=True, type=int)

    coding = commands.add_parser("coding-invoke")
    coding.add_argument("--tool-id", required=True)
    coding.add_argument("--input-json", required=True, choices=("-",))
    coding.add_argument(
        "--format",
        choices=("control-plane-json-v1", "raw"),
        default="control-plane-json-v1",
        help="Presentation only; never part of durable execution identity",
    )

    disposable = commands.add_parser("disposable-write-execute")
    disposable.add_argument("--call-id", required=True)
    disposable.add_argument("--approval-id", required=True)
    disposable.add_argument("--actor", required=True)
    disposable.add_argument("--workspace", required=True)
    disposable.add_argument("--policy", required=True)

    commands.add_parser("show")
    lookup = commands.add_parser("lookup")
    lookup.add_argument(
        "--record-kind",
        required=True,
        choices=("run", "tool_call", "policy_decision", "approval", "evidence"),
    )
    lookup.add_argument("--record-id", required=True)
    return parser


def _emit(stream: TextIO, value: Mapping[str, Any]) -> None:
    stream.write(
        json.dumps(value, allow_nan=False, ensure_ascii=False, sort_keys=True) + "\n"
    )
    stream.flush()


def _emit_canonical_presentation(
    output: TextIO,
    error_output: TextIO,
    value: Mapping[str, Any],
    presentation_format: str,
) -> int:
    if presentation_format == "control-plane-json-v1":
        _emit(output, {"ok": True, "command": "canonical-invoke", "result": value})
        return 0
    if value["status"] == "in_progress":
        return 75
    if value["result_available"] is not True or not isinstance(
        value["broker_envelope"], dict
    ):
        return 66
    envelope = value["broker_envelope"]
    raw_exit_code = envelope["exit_code"]
    if type(raw_exit_code) is not int:
        raise ValidationError("validated broker exit code is not an integer")
    exit_code = raw_exit_code
    if presentation_format == "broker-json-v1":
        output.write(
            json.dumps(
                envelope,
                allow_nan=False,
                ensure_ascii=False,
                separators=(",", ":"),
                sort_keys=True,
            )
            + "\n"
        )
        output.flush()
        return exit_code
    if presentation_format != "raw":
        raise ValidationError("unsupported canonical presentation format")
    try:
        stdout_bytes = base64.b64decode(
            envelope["stdout_b64"].encode("ascii"), validate=True
        )
        stderr_bytes = base64.b64decode(
            envelope["stderr_b64"].encode("ascii"), validate=True
        )
    except (AttributeError, UnicodeEncodeError, binascii.Error, ValueError) as exc:
        raise ValidationError("validated broker output could not be decoded") from exc
    output_buffer = getattr(output, "buffer", None)
    error_buffer = getattr(error_output, "buffer", None)
    if output_buffer is None or error_buffer is None:
        raise ValidationError("raw presentation requires binary-capable streams")
    output_buffer.write(stdout_bytes)
    output_buffer.flush()
    error_buffer.write(stderr_bytes)
    error_buffer.flush()
    return exit_code


def _result(value: Any) -> Any:
    serializer = getattr(value, "to_dict", None)
    if serializer is not None:
        return serializer()
    return value


def _validate_owner_private_directory(path: Path, *, create: bool) -> Path:
    if not path.is_absolute() or path != Path(os.path.realpath(str(path))):
        raise LedgerIOError("control-plane state directory must be an exact absolute path")
    if create:
        try:
            create_directory_durable(path, mode=0o700, parents=True)
        except OSError as exc:
            raise LedgerIOError("unable to create control-plane state directory") from exc
    try:
        metadata = path.lstat()
    except OSError as exc:
        raise LedgerIOError("control-plane state directory is unavailable") from exc
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or stat.S_ISLNK(metadata.st_mode)
        or metadata.st_uid != os.geteuid()
        or stat.S_IMODE(metadata.st_mode) & 0o077
    ):
        raise LedgerIOError("control-plane state directory must be owner-private")
    return path


def _default_ledger_path() -> Path:
    xdg_state = os.environ.get("XDG_STATE_HOME")
    if xdg_state:
        state_root = _validate_owner_private_directory(
            Path(xdg_state), create=False
        )
    else:
        account_home = Path(pwd.getpwuid(os.geteuid()).pw_dir)
        state_root = account_home / ".local" / "state"
    mainframe_state = _validate_owner_private_directory(
        state_root / "mainframe", create=True
    )
    return mainframe_state / "control-plane.jsonl"


def _parse_input_json(source: str, input_stream: TextIO) -> Any:
    if source == "-":
        rendered = input_stream.read(32769)
        if len(rendered) > 32768:
            raise ValidationError("input-json exceeds 32768 characters")
    else:
        rendered = source
    try:
        encoded = rendered.encode("utf-8")
    except UnicodeEncodeError as exc:
        raise ValidationError("input-json is not valid UTF-8") from exc
    if len(encoded) > 32768:
        raise ValidationError("input-json exceeds 32768 UTF-8 bytes")
    try:
        return json.loads(rendered)
    except json.JSONDecodeError as exc:
        raise ValidationError("input-json is invalid JSON") from exc


def _canonical_result(
    kernel: ControlPlaneKernel,
    call_id: str,
    transient_raw: Optional[bytes] = None,
) -> Mapping[str, Any]:
    snapshot = kernel.snapshot()
    call = snapshot.tool_calls[call_id]
    if call.client_correlation_id is None:
        raise BindingMismatch("canonical call lacks client correlation")
    request = snapshot.canonical_requests[call.client_correlation_id]
    decisions = [
        decision
        for decision in snapshot.policy_decisions.values()
        if decision.call_id == call_id
    ]
    evidences = [
        evidence for evidence in snapshot.evidence.values() if evidence.call_id == call_id
    ]
    if len(decisions) > 1:
        raise InvalidTransition("canonical invocation policy decision is not unique")
    decision_id = decisions[0].decision_id if decisions else request.decision_id
    if not evidences:
        return {
            "schema_version": 1,
            "status": "in_progress",
            "client_correlation_id": call.client_correlation_id,
            "run_id": call.run_id,
            "call_id": call.call_id,
            "decision_id": decision_id,
            "evidence_id": request.evidence_id,
            "input_digest": call.input_digest,
            "outcome": None,
            "result_available": False,
            "broker_receipt": None,
            "broker_envelope": None,
        }
    if len(evidences) != 1:
        raise InvalidTransition("canonical invocation identity is not unique")
    evidence = evidences[0]
    transient = None
    if transient_raw:
        transient = decode_canonical_result(
            transient_raw,
            request,
            call,
            evidence,
            kernel._registry().contract(call.tool),
        )
    envelope = None if transient is None else transient["broker_envelope"]
    receipt = evidence.body.get("broker_receipt")
    if not isinstance(receipt, dict):
        receipt = None
    return {
        "schema_version": 1,
        "status": "completed",
        "client_correlation_id": call.client_correlation_id,
        "run_id": call.run_id,
        "call_id": call.call_id,
        "decision_id": decision_id,
        "evidence_id": evidence.evidence_id,
        "input_digest": call.input_digest,
        "outcome": evidence.outcome,
        "result_available": transient is not None,
        "broker_receipt": receipt,
        "broker_envelope": envelope,
    }


def _find_correlated_call(
    kernel: ControlPlaneKernel, correlation_id: str
) -> Optional[ToolCallRecord]:
    matches = [
        call
        for call in kernel.snapshot().tool_calls.values()
        if call.client_correlation_id == correlation_id
    ]
    if len(matches) > 1:
        raise BindingMismatch("client correlation is not unique")
    return matches[0] if matches else None


def _reserved_in_progress(request: CanonicalRequestRecord) -> Mapping[str, Any]:
    return {
        "schema_version": 1,
        "status": "in_progress",
        "client_correlation_id": request.client_correlation_id,
        "run_id": request.run_id,
        "call_id": request.call_id,
        "decision_id": request.decision_id,
        "evidence_id": request.evidence_id,
        "input_digest": request.input_digest,
        "outcome": None,
        "result_available": False,
        "broker_receipt": None,
        "broker_envelope": None,
    }


def _canonical_bytes(tool_input: Mapping[str, Any]) -> bytes:
    return json.dumps(
        dict(tool_input),
        allow_nan=False,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


@dataclass
class _WorkerHandle:
    process: subprocess.Popen[bytes]
    reader: threading.Thread
    result_chunks: list[bytes]
    result_overflow: threading.Event

    def poll(self) -> Optional[int]:
        return self.process.poll()

    def result_bytes(self) -> bytes:
        self.reader.join(2.0)
        if self.reader.is_alive():
            raise ValidationError("canonical result handoff did not terminate")
        if self.result_overflow.is_set():
            raise ValidationError("canonical result handoff exceeded its size limit")
        return b"".join(self.result_chunks)

    def wait(self, timeout: float = 2.0) -> None:
        try:
            self.process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            return


def _spawn_canonical_worker(
    ledger_path: Path,
    correlation_id: str,
    tool_input: Mapping[str, Any],
    *,
    write_func: Callable[[int, bytes], int] = os.write,
) -> _WorkerHandle:
    launcher = Path(__file__).resolve().parents[1] / "mainframe-control-plane"
    read_fd, write_fd = os.pipe()
    result_read_fd, result_write_fd = os.pipe()
    worker: Optional[subprocess.Popen[bytes]] = None
    try:
        worker = subprocess.Popen(
            [
                str(launcher),
                "--ledger",
                str(ledger_path),
                "__canonical-worker-v1",
                "--client-correlation-id",
                correlation_id,
                "--input-fd",
                str(read_fd),
                "--result-fd",
                str(result_write_fd),
            ],
            cwd="/",
            env={
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "LC_ALL": "C",
                "NO_COLOR": "1",
                "TERM": "dumb",
                "TMPDIR": "/tmp",
                "HOME": "/tmp",
            },
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            pass_fds=(read_fd, result_write_fd),
            start_new_session=True,
        )
    except Exception:
        os.close(write_fd)
        os.close(result_read_fd)
        raise
    finally:
        os.close(read_fd)
        os.close(result_write_fd)
    if worker is None:  # defensive; Popen either returned or raised
        raise ExecutorUnavailable("canonical worker could not be started")
    result_chunks = []
    result_overflow = threading.Event()

    def read_result() -> None:
        total = 0
        try:
            while True:
                chunk = os.read(result_read_fd, 65536)
                if not chunk:
                    break
                total += len(chunk)
                if total <= MAX_TRANSIENT_RESULT_BYTES:
                    result_chunks.append(chunk)
                else:
                    result_overflow.set()
        finally:
            os.close(result_read_fd)

    result_reader = threading.Thread(target=read_result, daemon=True)
    result_reader.start()
    try:
        content = _canonical_bytes(tool_input)
        offset = 0
        while offset < len(content):
            written = write_func(write_fd, content[offset:])
            if written <= 0:
                raise OSError("canonical handoff made no progress")
            offset += written
    except BrokenPipeError:
        # Another worker may already hold the request lock.  The invocation
        # remains safely in progress and no bytes were persisted.
        pass
    except OSError:
        try:
            worker.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            worker.terminate()
            worker.wait(timeout=2.0)
        result_reader.join(2.0)
        raise
    finally:
        os.close(write_fd)
    return _WorkerHandle(worker, result_reader, result_chunks, result_overflow)


def _canonical_invoke(
    kernel: ControlPlaneKernel,
    *,
    canonical_id: str,
    tool_input: Any,
    client_correlation_id: str,
) -> Mapping[str, Any]:
    registry = kernel._registry()
    normalized = registry.normalize_input(canonical_id, tool_input)
    digest = normalized_input_digest(normalized)
    metadata = normalized_input_metadata(normalized)
    actor = "local-uid:{}:mainframe-cli".format(os.geteuid())
    workspace = os.path.realpath(os.getcwd())
    snapshot = kernel.snapshot()
    request = snapshot.canonical_requests.get(client_correlation_id)
    if request is None:
        try:
            request = kernel.reserve_canonical_request(
                client_correlation_id=client_correlation_id,
                canonical_id=canonical_id,
                tool_input=normalized,
                actor=actor,
                workspace=workspace,
                policy=STABLE_CORE_POLICY,
            )
        except AlreadyExists:
            request = kernel.snapshot().canonical_requests[client_correlation_id]
    if (
        request.canonical_id != canonical_id
        or request.input_digest != digest
        or request.input_metadata != metadata
        or request.actor != actor
        or request.workspace != workspace
        or request.policy != STABLE_CORE_POLICY
    ):
        raise BindingMismatch(
            "client correlation is already bound to a different invocation"
        )
    signal_state: list[Optional[int]] = [None]
    previous_handlers = []
    if threading.current_thread() is threading.main_thread():
        for signal_number in (signal.SIGINT, signal.SIGTERM):
            previous_handlers.append(
                (signal_number, signal.getsignal(signal_number))
            )
            signal.signal(
                signal_number,
                lambda received, _frame: signal_state.__setitem__(0, received),
            )

    def drive() -> Mapping[str, Any]:
        existing = _find_correlated_call(kernel, client_correlation_id)
        if existing is not None and existing.state in (
            "succeeded",
            "failed",
            "timed_out",
            "interrupted",
        ):
            run = kernel.snapshot().runs[request.run_id]
            if run.state == "active":
                evidences = [
                    item
                    for item in kernel.snapshot().evidence.values()
                    if item.call_id == existing.call_id
                ]
                if len(evidences) != 1:
                    raise InvalidTransition("terminal canonical call lacks unique Evidence")
                kernel.transition_run(
                    run.run_id,
                    "completed" if evidences[0].outcome == "succeeded" else "failed",
                )
            return _canonical_result(kernel, existing.call_id)
        if existing is not None and existing.state == "running":
            if probe_canonical_supervisor(kernel.ledger_path, existing, wait_seconds=2.0):
                return _canonical_result(kernel, existing.call_id)
            kernel.recover_canonical_execution(existing.call_id)
            return _canonical_result(kernel, existing.call_id)

        worker = _spawn_canonical_worker(
            kernel.ledger_path,
            client_correlation_id,
            normalized,
        )
        wait_deadline = time.monotonic() + 35.0
        cancellation_requested = False
        while time.monotonic() < wait_deadline:
            current = kernel.snapshot()
            call = current.tool_calls.get(request.call_id)
            terminal_run = current.runs.get(request.run_id)
            received_signal = signal_state[0]
            if (
                received_signal is not None
                and call is not None
                and call.state == "running"
                and not cancellation_requested
            ):
                try:
                    request_canonical_cancellation(
                        kernel.ledger_path,
                        client_correlation_id=client_correlation_id,
                    )
                    cancellation_requested = True
                except ExecutorUnavailable:
                    pass
            if call is not None and call.state in (
                "succeeded",
                "failed",
                "timed_out",
                "interrupted",
            ) and terminal_run is not None and terminal_run.state in (
                "completed",
                "failed",
            ):
                worker.wait()
                transient_result = worker.result_bytes()
                if received_signal is not None:
                    raise _ForegroundSignalExit(received_signal)
                return _canonical_result(kernel, call.call_id, transient_result)
            if worker.poll() is not None:
                break
            time.sleep(0.02)
        current = kernel.snapshot()
        call = current.tool_calls.get(request.call_id)
        if call is not None and call.state == "running":
            if not probe_canonical_supervisor(kernel.ledger_path, call, wait_seconds=2.0):
                kernel.recover_canonical_execution(call.call_id)
                if signal_state[0] is not None:
                    raise _ForegroundSignalExit(signal_state[0])
                return _canonical_result(kernel, call.call_id)
        if signal_state[0] is not None:
            raise _ForegroundSignalExit(signal_state[0])
        if call is not None:
            return _canonical_result(
                kernel,
                call.call_id,
                worker.result_bytes() if worker.poll() is not None else None,
            )
        return _reserved_in_progress(request)

    try:
        return drive()
    finally:
        for signal_number, previous in previous_handlers:
            signal.signal(signal_number, previous)


def _spawn_project_memory_worker(
    ledger_path: Path,
    correlation_id: str,
    tool_input: Mapping[str, Any],
    *,
    write_func: Callable[[int, bytes], int] = os.write,
) -> _WorkerHandle:
    launcher = Path(__file__).resolve().parents[1] / "mainframe-control-plane"
    read_fd, write_fd = os.pipe()
    result_read_fd, result_write_fd = os.pipe()
    worker: Optional[subprocess.Popen[bytes]] = None
    try:
        worker = subprocess.Popen(
            [
                str(launcher),
                "--ledger",
                str(ledger_path),
                "__project-memory-worker-v1",
                "--client-correlation-id",
                correlation_id,
                "--input-fd",
                str(read_fd),
                "--result-fd",
                str(result_write_fd),
            ],
            cwd="/",
            env={
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "LC_ALL": "C",
                "NO_COLOR": "1",
                "TERM": "dumb",
                "TMPDIR": "/tmp",
                "HOME": "/tmp",
            },
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            pass_fds=(read_fd, result_write_fd),
            start_new_session=True,
        )
    except Exception:
        os.close(write_fd)
        os.close(result_read_fd)
        raise
    finally:
        os.close(read_fd)
        os.close(result_write_fd)
    if worker is None:
        raise ExecutorUnavailable("project-memory worker could not be started")
    result_chunks: list[bytes] = []
    result_overflow = threading.Event()

    def read_result() -> None:
        total = 0
        try:
            while True:
                chunk = os.read(result_read_fd, 65536)
                if not chunk:
                    break
                total += len(chunk)
                if total <= MAX_PROJECT_MEMORY_RESULT_BYTES:
                    result_chunks.append(chunk)
                else:
                    result_overflow.set()
        finally:
            os.close(result_read_fd)

    result_reader = threading.Thread(target=read_result, daemon=True)
    result_reader.start()
    try:
        content = _canonical_bytes(tool_input)
        offset = 0
        while offset < len(content):
            written = write_func(write_fd, content[offset:])
            if written <= 0:
                raise OSError("project-memory input handoff made no progress")
            offset += written
    except BrokenPipeError:
        pass
    except OSError:
        try:
            worker.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            worker.terminate()
            worker.wait(timeout=2.0)
        result_reader.join(2.0)
        raise
    finally:
        os.close(write_fd)
    return _WorkerHandle(worker, result_reader, result_chunks, result_overflow)


def _project_memory_result_dict(
    result: ProjectMemoryInvocationResult,
    transient_raw: Optional[bytes] = None,
) -> Mapping[str, Any]:
    transient = (
        None
        if not transient_raw
        else decode_project_memory_result(transient_raw, result)
    )
    return {
        "schema_version": 1,
        "status": result.status,
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
        "result_available": transient is not None,
        "receipt": result.receipt,
        "memory_record": None if result.memory_record is None else result.memory_record.to_dict(),
        "handoff_record": None if result.handoff_record is None else result.handoff_record.to_dict(),
        "transient_b64": None
        if transient is None
        else base64.b64encode(transient).decode("ascii"),
    }


def _project_memory_in_progress(request: CanonicalRequestRecord) -> Mapping[str, Any]:
    binding = request.reservation_binding
    project_digest = binding.get("project_digest") if isinstance(binding, dict) else None
    memory_op_id = "memory-op-{}".format(
        hashlib.sha256(request.call_id.encode("utf-8")).hexdigest()[:32]
    )
    aggregate_suffix = hashlib.sha256(memory_op_id.encode("utf-8")).hexdigest()[:32]
    is_handoff = request.canonical_id == PROJECT_MEMORY_HANDOFF
    is_mutation = request.canonical_id in PROJECT_MEMORY_MUTATION_TOOLS
    return {
        "schema_version": 1,
        "status": "in_progress",
        "client_correlation_id": request.client_correlation_id,
        "memory_op_id": memory_op_id,
        "memory_id": (
            "memory-{}".format(aggregate_suffix)
            if is_mutation and not is_handoff
            else None
        ),
        "handoff_id": "handoff-{}".format(aggregate_suffix) if is_handoff else None,
        "run_id": request.run_id,
        "call_id": request.call_id,
        "decision_id": request.decision_id,
        "evidence_id": request.evidence_id,
        "input_digest": request.input_digest,
        "project_digest": project_digest,
        "session_id": None,
        "outcome": None,
        "result_available": False,
        "receipt": None,
        "memory_record": None,
        "handoff_record": None,
        "transient_b64": None,
    }


def _project_memory_invoke(
    ledger_path: Path,
    *,
    tool: str,
    tool_input: Any,
    client_correlation_id: str,
) -> Mapping[str, Any]:
    if not isinstance(tool_input, dict):
        raise ValidationError("project-memory input must be an object")
    executor = FixedProjectMemorySubprocessExecutor(ledger_path=ledger_path)
    control = ProjectMemoryControlPlane(ledger_path, executor=executor)
    actor = "local-uid:{}:mainframe-cli".format(os.geteuid())
    workspace = os.path.realpath(os.getcwd())
    request = control.reserve(
        client_correlation_id=client_correlation_id,
        tool=tool,
        tool_input=tool_input,
        actor=actor,
        workspace=workspace,
    )
    existing = control.result_for_correlation(client_correlation_id)
    if existing is not None:
        return _project_memory_result_dict(existing)
    worker = _spawn_project_memory_worker(
        ledger_path, client_correlation_id, tool_input
    )
    deadline = time.monotonic() + 35.0
    while time.monotonic() < deadline:
        completed = control.result_for_correlation(client_correlation_id)
        if completed is not None:
            worker.wait()
            return _project_memory_result_dict(completed, worker.result_bytes())
        if worker.poll() is not None:
            break
        time.sleep(0.02)
    completed = control.result_for_correlation(client_correlation_id)
    if completed is not None:
        return _project_memory_result_dict(
            completed,
            worker.result_bytes() if worker.poll() is not None else None,
        )
    return _project_memory_in_progress(request)


def _emit_project_memory_presentation(
    output: TextIO,
    value: Mapping[str, Any],
    presentation_format: str,
) -> int:
    if presentation_format == "control-plane-json-v1":
        _emit(output, {"ok": True, "command": "project-memory-invoke", "result": value})
        return 0
    if presentation_format != "awm-compatible-v1":
        raise ValidationError("unsupported project-memory presentation format")
    if value["status"] == "in_progress":
        return 75
    if value["outcome"] == "recovery_required":
        return 75
    if value["outcome"] != "succeeded":
        return 1
    receipt = value.get("receipt")
    if not isinstance(receipt, dict):
        return 1
    tool = receipt.get("tool")
    if tool == PROJECT_MEMORY_HANDOFF or tool in PROJECT_MEMORY_READ_TOOLS:
        transient_value = value.get("transient_b64")
        if value.get("result_available") is not True or not isinstance(
            transient_value, str
        ):
            return 66
        try:
            transient = base64.b64decode(transient_value, validate=True)
        except (ValueError, binascii.Error) as exc:
            raise ValidationError("validated project-memory output is not strict base64") from exc
        output_buffer = getattr(output, "buffer", None)
        if output_buffer is None:
            raise ValidationError("AWM presentation requires a binary stream")
        output_buffer.write(transient)
        output_buffer.flush()
        return 0
    if not isinstance(tool, str):
        return 1
    if tool.endswith(".ensure.v1"):
        output.write(str(value["session_id"]) + "\n")
        output.flush()
    return 0


def _coding_result_dict(result: CodingInvocationResult) -> Mapping[str, Any]:
    transient = result.result if result.result_available else None
    if result.result_available and transient is None:
        raise BindingMismatch("coding result availability is inconsistent")
    return {
        "schema_version": result.schema_version,
        "status": result.status,
        "client_correlation_id": result.client_correlation_id,
        "run_id": result.run_id,
        "call_id": result.call_id,
        "decision_id": result.decision_id,
        "approval_id": result.approval_id,
        "evidence_id": result.evidence_id,
        "input_digest": result.input_digest,
        "outcome": result.outcome,
        "result_available": transient is not None,
        "receipt": result.receipt,
        "evidence_body": result.evidence_body,
        "stdout_b64": (
            None
            if transient is None
            else base64.b64encode(transient.stdout).decode("ascii")
        ),
        "stderr_b64": (
            None
            if transient is None
            else base64.b64encode(transient.stderr).decode("ascii")
        ),
    }


def _coding_invoke(
    ledger_path: Path,
    *,
    tool: str,
    tool_input: Any,
) -> Mapping[str, Any]:
    if not isinstance(tool_input, dict):
        raise ValidationError("coding input must be an object")
    # These are the complete production capabilities: safe workspace operations,
    # no project-code runner, and no approval authority implementation.
    control = CodingAgentControlPlane(
        ledger_path,
        executor=FixedWorkspaceCodingExecutor(),
    )
    result = control.invoke(
        client_correlation_id="coding-{}".format(uuid.uuid4().hex),
        tool=tool,
        tool_input=tool_input,
        actor="local-uid:{}:mainframe-cli".format(os.geteuid()),
        workspace=os.path.realpath(os.getcwd()),
    )
    return _coding_result_dict(result)


def _emit_coding_presentation(
    output: TextIO,
    error_output: TextIO,
    value: Mapping[str, Any],
    presentation_format: str,
) -> int:
    if presentation_format == "control-plane-json-v1":
        _emit(output, {"ok": True, "command": "coding-invoke", "result": value})
        return 0
    if presentation_format != "raw":
        raise ValidationError("unsupported coding presentation format")
    if value["status"] in ("in_progress", "awaiting_approval"):
        return 75
    if value["result_available"] is not True:
        return 66
    receipt = value.get("receipt")
    if not isinstance(receipt, dict):
        raise BindingMismatch("coding result lacks its validated exit status")
    exit_code = receipt.get("exit_code")
    if not isinstance(exit_code, int) or isinstance(exit_code, bool):
        raise BindingMismatch("coding result lacks its validated exit status")
    stdout_value = value.get("stdout_b64")
    stderr_value = value.get("stderr_b64")
    if not isinstance(stdout_value, str) or not isinstance(stderr_value, str):
        raise BindingMismatch("coding raw presentation lacks transient output")
    try:
        stdout_bytes = base64.b64decode(stdout_value, validate=True)
        stderr_bytes = base64.b64decode(stderr_value, validate=True)
    except (TypeError, ValueError, binascii.Error) as exc:
        raise BindingMismatch("coding raw presentation is not strict base64") from exc
    output_buffer = getattr(output, "buffer", None)
    error_buffer = getattr(error_output, "buffer", None)
    if output_buffer is None or error_buffer is None:
        raise ValidationError("coding raw presentation requires binary streams")
    output_buffer.write(stdout_bytes)
    output_buffer.flush()
    error_buffer.write(stderr_bytes)
    error_buffer.flush()
    return exit_code


def main(
    argv: Optional[Sequence[str]] = None,
    *,
    stdout: Optional[TextIO] = None,
    stderr: Optional[TextIO] = None,
    stdin: Optional[TextIO] = None,
    executor: Optional[Executor] = None,
    canonical_executor: Optional[CanonicalExecutor] = None,
    evaluator: Optional[PolicyEvaluator] = None,
    trusted_approver: Optional[TrustedApprover] = None,
    clock: Optional[Callable[[], datetime]] = None,
) -> int:
    output = stdout if stdout is not None else sys.stdout
    error_output = stderr if stderr is not None else sys.stderr
    input_stream = stdin if stdin is not None else sys.stdin
    command = None
    presentation_format = "control-plane-json-v1"
    try:
        arguments = _parser().parse_args(argv)
        command = arguments.command
        if command in (
            "canonical-invoke",
            "project-memory-invoke",
            "coding-invoke",
        ):
            presentation_format = arguments.format
        if command in ("project-memory-invoke", "coding-invoke") and arguments.ledger is not None:
            raise _UsageError("{} does not accept --ledger".format(command))
        ledger_path = Path(arguments.ledger) if arguments.ledger else _default_ledger_path()
        stable_core_registry = None
        effective_evaluator = evaluator
        if command == "canonical-invoke":
            stable_core_registry = load_fixed_stable_core_registry()
            if effective_evaluator is None:
                effective_evaluator = FixedStableCoreEvaluator(stable_core_registry)
        if clock is None:
            kernel = ControlPlaneKernel(
                ledger_path,
                evaluator=effective_evaluator,
                stable_core_registry=stable_core_registry,
            )
        else:
            kernel = ControlPlaneKernel(
                ledger_path,
                clock=clock,
                evaluator=effective_evaluator,
                stable_core_registry=stable_core_registry,
            )

        value: Any
        if command == "run-create":
            value = kernel.create_run(
                run_id=arguments.run_id,
                actor=arguments.actor,
                workspace=arguments.workspace,
                policy=arguments.policy,
            )
        elif command == "run-transition":
            value = kernel.transition_run(arguments.run_id, arguments.to)
        elif command == "call-create":
            try:
                tool_input = json.loads(arguments.input_json)
            except json.JSONDecodeError as exc:
                raise ValidationError("input-json is invalid JSON") from exc
            value = kernel.create_tool_call(
                call_id=arguments.call_id,
                run_id=arguments.run_id,
                tool=arguments.tool,
                tool_input=tool_input,
                effect=arguments.effect,
                timeout_at=arguments.timeout_at,
            )
        elif command == "canonical-call-create":
            try:
                tool_input = json.loads(arguments.input_json)
            except json.JSONDecodeError as exc:
                raise ValidationError("input-json is invalid JSON") from exc
            value = kernel.create_canonical_tool_call(
                call_id=arguments.call_id,
                run_id=arguments.run_id,
                canonical_id=arguments.canonical_id,
                tool_input=tool_input,
            )
        elif command == "call-request-approval":
            value = kernel.request_approval(arguments.call_id)
        elif command == "decision-evaluate":
            value = kernel.evaluate_policy_decision(
                decision_id=arguments.decision_id,
                call_id=arguments.call_id,
                tool=arguments.tool,
                input_digest=arguments.input_digest,
                actor=arguments.actor,
                workspace=arguments.workspace,
                policy=arguments.policy,
                timeout_at=arguments.timeout_at,
            )
        elif command in ("call-cancel", "call-timeout", "call-recover"):
            method = {
                "call-cancel": kernel.cancel_tool_call,
                "call-timeout": kernel.timeout_tool_call,
                "call-recover": kernel.recover_tool_call,
            }[command]
            value = method(
                arguments.call_id,
                tool=arguments.tool,
                input_digest=arguments.input_digest,
                actor=arguments.actor,
                workspace=arguments.workspace,
                policy=arguments.policy,
                reason=arguments.reason,
            )
        elif command == "approval-grant":
            if trusted_approver is None:
                raise ApprovalAuthorityUnavailable(
                    "no trusted approval implementation was injected"
                )
            approval_request = kernel.bind_approval_grant_request(
                approval_id=arguments.approval_id,
                call_id=arguments.call_id,
                tool=arguments.tool,
                input_digest=arguments.input_digest,
                actor=arguments.actor,
                workspace=arguments.workspace,
                policy=arguments.policy,
                expires_at=arguments.expires_at,
            )
            verified_approver = trusted_approver(approval_request)
            value = kernel.grant_approval(
                approval_id=arguments.approval_id,
                call_id=arguments.call_id,
                tool=arguments.tool,
                input_digest=arguments.input_digest,
                actor=arguments.actor,
                workspace=arguments.workspace,
                policy=arguments.policy,
                approver=verified_approver,
                expires_at=arguments.expires_at,
            )
        elif command == "approval-consume":
            value = kernel.consume_approval(
                arguments.approval_id,
                call_id=arguments.call_id,
                actor=arguments.actor,
                workspace=arguments.workspace,
                policy=arguments.policy,
            )
        elif command == "trace-execute":
            if executor is None:
                raise ExecutorUnavailable("no read-only executor was injected")
            value = kernel.execute_read_only(arguments.call_id, executor)
        elif command == "canonical-execute":
            if canonical_executor is None:
                raise ExecutorUnavailable("no canonical stable-core executor was injected")
            value = kernel.execute_canonical(
                arguments.call_id, executor=canonical_executor
            )
        elif command == "canonical-invoke":
            value = _canonical_invoke(
                kernel,
                canonical_id=arguments.canonical_id,
                tool_input=_parse_input_json(arguments.input_json, input_stream),
                client_correlation_id=arguments.client_correlation_id,
            )
        elif command == "canonical-cancel":
            value = request_canonical_cancellation(
                ledger_path,
                client_correlation_id=arguments.client_correlation_id,
            )
        elif command == "project-memory-invoke":
            value = _project_memory_invoke(
                ledger_path,
                tool=arguments.tool_id,
                tool_input=_parse_input_json(arguments.input_json, input_stream),
                client_correlation_id=arguments.client_correlation_id,
            )
        elif command == "coding-invoke":
            value = _coding_invoke(
                ledger_path,
                tool=arguments.tool_id,
                tool_input=_parse_input_json(arguments.input_json, input_stream),
            )
        elif command == "__canonical-worker-v1":
            run_canonical_worker(
                ledger_path,
                arguments.client_correlation_id,
                input_fd=arguments.input_fd,
                result_fd=arguments.result_fd,
            )
            value = {"settled": True}
        elif command == "__project-memory-worker-v1":
            run_project_memory_worker(
                ledger_path,
                arguments.client_correlation_id,
                input_fd=arguments.input_fd,
                result_fd=arguments.result_fd,
            )
            value = {"settled": True}
        elif command == "disposable-write-execute":
            value = kernel.execute_disposable_write(
                arguments.call_id,
                approval_id=arguments.approval_id,
                actor=arguments.actor,
                workspace=arguments.workspace,
                policy=arguments.policy,
            )
        elif command == "show":
            value = kernel.snapshot()
        elif command == "lookup":
            value = kernel.lookup(arguments.record_kind, arguments.record_id)
        else:  # pragma: no cover - argparse enforces the command set
            raise _UsageError("a command is required")

        serialized = _result(value)
        if command == "canonical-invoke":
            return _emit_canonical_presentation(
                output,
                error_output,
                serialized,
                arguments.format,
            )
        if command == "project-memory-invoke":
            return _emit_project_memory_presentation(
                output,
                serialized,
                arguments.format,
            )
        if command == "coding-invoke":
            return _emit_coding_presentation(
                output,
                error_output,
                serialized,
                arguments.format,
            )
        _emit(output, {"ok": True, "command": command, "result": serialized})
        return 0
    except _ForegroundSignalExit as exc:
        return exc.exit_code
    except _UsageError as exc:
        if presentation_format != "control-plane-json-v1":
            return 2
        _emit(
            output,
            {"ok": False, "command": command, "error": {"code": "usage_error", "message": str(exc)}},
        )
        return 2
    except ControlPlaneError as exc:
        if isinstance(exc, ValidationError):
            error_code = 2
        elif isinstance(exc, (LedgerCorruption, LedgerIOError, RegistryCorruption)):
            error_code = 4
        else:
            error_code = 3
        if presentation_format != "control-plane-json-v1":
            return error_code
        _emit(
            output,
            {"ok": False, "command": command, "error": {"code": exc.code, "message": str(exc)}},
        )
        return error_code
    except Exception:
        if presentation_format != "control-plane-json-v1":
            return 70
        _emit(
            output,
            {
                "ok": False,
                "command": command,
                "error": {
                    "code": "internal_error",
                    "message": "unexpected control-plane failure",
                },
            },
        )
        return 70


if __name__ == "__main__":
    raise SystemExit(main())

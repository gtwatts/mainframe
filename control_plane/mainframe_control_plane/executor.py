"""Fixed stable-core subprocess supervision and cross-process cancellation."""

from __future__ import annotations

import json
import errno
import os
from pathlib import Path
import platform
import pwd
from datetime import datetime, timezone
import signal
import socket
import stat
import subprocess
import threading
import time
from typing import Any, Dict, List, Mapping, Optional, Tuple

from .contracts import StableCoreRegistry
from .durability import create_directory_durable
from .errors import (
    BindingMismatch,
    ExecutionDenied,
    ExecutorUnavailable,
    InvalidTransition,
    LedgerIOError,
    NotFound,
    ValidationError,
)
from .kernel import (
    CanonicalExecutionResult,
    ControlPlaneKernel,
    JsonValue,
    ToolCallRecord,
    normalized_input_digest,
    normalized_input_metadata,
)


_FIXED_RELEASE_ROOT = Path(__file__).resolve().parents[2]
_MAX_INPUT_BYTES = 32768
_TERMINATION_GRACE_SECONDS = 0.75
_CANCEL_CONNECT_SECONDS = 2.0
_FIXED_LIVENESS_FD = 198
_FIXED_FD_SPAWN_LOCK = threading.Lock()


def _canonical_json(value: Any) -> bytes:
    try:
        return json.dumps(
            value,
            allow_nan=False,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
    except (TypeError, ValueError) as exc:
        raise ValidationError("executor input is not canonical JSON") from exc


def _validate_private_directory(path: Path, *, create: bool) -> None:
    if create:
        try:
            create_directory_durable(path, mode=0o700, parents=False)
        except OSError as exc:
            raise LedgerIOError("unable to create private runtime directory") from exc
    try:
        metadata = path.lstat()
    except OSError as exc:
        raise LedgerIOError("private runtime directory is unavailable") from exc
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or stat.S_ISLNK(metadata.st_mode)
        or metadata.st_uid != os.geteuid()
        or stat.S_IMODE(metadata.st_mode) & 0o077
    ):
        raise ExecutionDenied("runtime directory must be owner-private and non-symbolic")


def _runtime_directory(ledger_path: Path, *, create: bool) -> Path:
    parent = ledger_path.resolve().parent
    _validate_private_directory(parent, create=False)
    runtime = parent / ".mainframe-control-plane-runtime"
    _validate_private_directory(runtime, create=create)
    return runtime


def _socket_path(ledger_path: Path, call_id: str) -> Path:
    import hashlib

    temporary_root = Path("/private/tmp") if platform.system() == "Darwin" else Path("/tmp")
    base = temporary_root / ("mainframe-control-plane-{}".format(os.geteuid()))
    _validate_private_directory(base, create=True)
    ledger_name = hashlib.sha256(
        str(Path(ledger_path).resolve()).encode("utf-8")
    ).hexdigest()[:20]
    ledger_runtime = base / ledger_name
    _validate_private_directory(ledger_runtime, create=True)
    name = hashlib.sha256(call_id.encode("utf-8")).hexdigest()[:24]
    path = ledger_runtime / ("c-{}.sock".format(name))
    if len(os.fsencode(str(path))) >= 100:
        raise ExecutionDenied("cancellation endpoint path exceeds the safe bound")
    return path


def _validate_fixed_executable(path: Path) -> None:
    try:
        metadata = path.lstat()
    except OSError as exc:
        raise ExecutorUnavailable("fixed stable-core adapter is unavailable") from exc
    if (
        not stat.S_ISREG(metadata.st_mode)
        or stat.S_ISLNK(metadata.st_mode)
        or metadata.st_uid not in (0, os.geteuid())
        or stat.S_IMODE(metadata.st_mode) & 0o7022
        or metadata.st_nlink != 1
        or not os.access(str(path), os.X_OK)
    ):
        raise ExecutorUnavailable("fixed stable-core adapter is unsafe")


def _call_identity(call: ToolCallRecord) -> Dict[str, JsonValue]:
    return {
        "call_id": call.call_id,
        "tool": call.tool,
        "input_digest": call.input_digest,
        "actor": call.actor,
        "workspace": call.workspace,
        "policy": call.policy,
        "client_correlation_id": call.client_correlation_id,
    }


def _receive_json(connection: socket.socket, limit: int = 8192) -> Dict[str, Any]:
    chunks = []
    total = 0
    while True:
        chunk = connection.recv(min(4096, limit + 1 - total))
        if not chunk:
            break
        chunks.append(chunk)
        total += len(chunk)
        if total > limit:
            raise ValidationError("cancellation request exceeds its size limit")
    try:
        value = json.loads(b"".join(chunks).decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValidationError("cancellation request is not UTF-8 JSON") from exc
    if not isinstance(value, dict):
        raise ValidationError("cancellation request must be an object")
    return value


def _terminate_process_group(process: subprocess.Popen[bytes]) -> None:
    # Signal the PGID even when the leader has already exited.  A leader poll is
    # not evidence that same-session descendants are gone.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        if process.poll() is None:
            process.wait(timeout=_TERMINATION_GRACE_SECONDS)
        return
    deadline = time.monotonic() + _TERMINATION_GRACE_SECONDS
    while process.poll() is None and time.monotonic() < deadline:
        time.sleep(0.02)
    # Always attempt KILL after the grace interval.  If the leader exited but a
    # descendant retained the PGID, this is the cleanup operation that matters.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    if process.poll() is None:
        try:
            process.wait(timeout=_TERMINATION_GRACE_SECONDS)
        except subprocess.TimeoutExpired:
            raise ExecutorUnavailable("adapter process leader could not be reaped")


class FixedStableCoreSubprocessExecutor:
    """Callable executor whose executable, argv, environment, and bounds are fixed."""

    def __init__(
        self,
        *,
        registry: StableCoreRegistry,
        call: ToolCallRecord,
        ledger_path: Path,
    ) -> None:
        self._release_root = _FIXED_RELEASE_ROOT
        self._registry = registry
        self._call = call
        self._ledger_path = Path(ledger_path)

    @classmethod
    def _for_test(
        cls,
        *,
        release_root: Path,
        registry: StableCoreRegistry,
        call: ToolCallRecord,
        ledger_path: Path,
    ) -> "FixedStableCoreSubprocessExecutor":
        value = cls(registry=registry, call=call, ledger_path=ledger_path)
        value._release_root = Path(release_root).resolve()
        return value

    def _clean_environment(self, runtime: Path) -> Dict[str, str]:
        account = pwd.getpwuid(os.geteuid())
        state_home = runtime / "broker-state"
        _validate_private_directory(state_home, create=True)
        return {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LC_ALL": "C",
            "NO_COLOR": "1",
            "TERM": "dumb",
            "TMPDIR": "/tmp",
            "HOME": str(runtime),
            "XDG_STATE_HOME": str(state_home),
            "USER": account.pw_name,
            "LOGNAME": account.pw_name,
        }

    def __call__(
        self, canonical_id: str, tool_input: Mapping[str, JsonValue]
    ) -> CanonicalExecutionResult:
        if (
            canonical_id != self._call.tool
            or normalized_input_digest(tool_input) != self._call.input_digest
            or normalized_input_metadata(tool_input) != self._call.input_metadata
        ):
            raise BindingMismatch("executor input does not match its durable tool call")
        contract = self._registry.contract(canonical_id)
        canonical_input = _canonical_json(dict(tool_input))
        if len(canonical_input) > _MAX_INPUT_BYTES:
            raise ExecutionDenied("canonical input exceeds 32768 UTF-8 bytes")
        adapter = self._release_root / "bin" / "mainframe"
        _validate_fixed_executable(adapter)
        runtime = _runtime_directory(self._ledger_path, create=True)
        cancel_path = _socket_path(self._ledger_path, self._call.call_id)
        if cancel_path.exists() or cancel_path.is_symlink():
            metadata = cancel_path.lstat()
            if not stat.S_ISSOCK(metadata.st_mode) or metadata.st_uid != os.geteuid():
                raise ExecutionDenied("cancellation endpoint path is unsafe")
            cancel_path.unlink()

        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        process: Optional[subprocess.Popen[bytes]] = None
        liveness_read_fd: Optional[int] = None
        liveness_write_fd: Optional[int] = None
        readers: List[threading.Thread] = []
        previous_handlers: List[Tuple[signal.Signals, Any]] = []
        external_interrupt = threading.Event()
        group_cleanup_complete = False

        def terminate_adapter_group() -> None:
            nonlocal group_cleanup_complete
            current = process
            if current is None or group_cleanup_complete:
                return
            _terminate_process_group(current)
            # The fixed Bash guardian anchors the PGID until this cleanup. Never
            # signal the numeric PGID again after the guardian has been removed:
            # it may already have been recycled for a foreign process group.
            group_cleanup_complete = True

        try:
            listener.bind(str(cancel_path))
            os.chmod(str(cancel_path), 0o600)
            listener.listen(4)
            listener.settimeout(0.05)
            if threading.current_thread() is threading.main_thread():
                for signal_number in (signal.SIGINT, signal.SIGTERM):
                    previous_handlers.append(
                        (signal_number, signal.getsignal(signal_number))
                    )
                    signal.signal(
                        signal_number,
                        lambda _number, _frame: external_interrupt.set(),
                    )
            command = [
                str(adapter),
                "__kernel-stable-core-broker-v1",
                canonical_id,
                "--input-json",
                "-",
                "--profile",
                "stable-core",
                "--format",
                "broker-json-v1",
                "--caller",
                "control-plane",
            ]
            saved_fixed_fd: Optional[int] = None
            saved_fixed_inheritable = False
            with _FIXED_FD_SPAWN_LOCK:
                try:
                    try:
                        saved_fixed_inheritable = os.get_inheritable(
                            _FIXED_LIVENESS_FD
                        )
                        saved_fixed_fd = os.dup(_FIXED_LIVENESS_FD)
                    except OSError as exc:
                        if exc.errno != errno.EBADF:
                            raise
                    liveness_read_fd, liveness_write_fd = os.pipe()
                    os.dup2(
                        liveness_read_fd,
                        _FIXED_LIVENESS_FD,
                        inheritable=True,
                    )
                    process = subprocess.Popen(
                        command,
                        cwd=self._call.workspace,
                        env=self._clean_environment(runtime),
                        stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        pass_fds=(_FIXED_LIVENESS_FD,),
                        start_new_session=True,
                    )
                finally:
                    try:
                        if saved_fixed_fd is None:
                            try:
                                os.close(_FIXED_LIVENESS_FD)
                            except OSError as exc:
                                if exc.errno != errno.EBADF:
                                    raise
                        else:
                            os.dup2(
                                saved_fixed_fd,
                                _FIXED_LIVENESS_FD,
                                inheritable=saved_fixed_inheritable,
                            )
                    finally:
                        if saved_fixed_fd is not None:
                            os.close(saved_fixed_fd)
                        if (
                            liveness_read_fd is not None
                            and liveness_read_fd != _FIXED_LIVENESS_FD
                        ):
                            os.close(liveness_read_fd)
            if process.stdin is None or process.stdout is None or process.stderr is None:
                raise ExecutorUnavailable("adapter pipes are unavailable")

            raw_limit = max(65536, ((contract.output_limit + 2) // 3) * 4 + 65536)
            stdout_chunks: List[bytes] = []
            stderr_chunks: List[bytes] = []
            overflow = threading.Event()
            observed_bytes = [0]
            observed_lock = threading.Lock()

            def read_bounded(stream: Any, chunks: List[bytes]) -> None:
                while True:
                    chunk = stream.read(65536)
                    if not chunk:
                        break
                    with observed_lock:
                        observed_bytes[0] += len(chunk)
                        if observed_bytes[0] <= raw_limit:
                            chunks.append(chunk)
                        else:
                            overflow.set()

            readers = [
                threading.Thread(
                    target=read_bounded, args=(process.stdout, stdout_chunks), daemon=True
                ),
                threading.Thread(
                    target=read_bounded, args=(process.stderr, stderr_chunks), daemon=True
                ),
            ]
            for reader in readers:
                reader.start()
            process.stdin.write(canonical_input)
            process.stdin.close()

            cancelled = False
            timed_out = False
            if self._call.timeout_at is None:
                raise ExecutionDenied("canonical call lacks a durable deadline")
            durable_deadline = datetime.fromisoformat(
                self._call.timeout_at.replace("Z", "+00:00")
            ).astimezone(timezone.utc)
            remaining = max(
                0.0,
                (durable_deadline - datetime.now(timezone.utc)).total_seconds(),
            )
            deadline = time.monotonic() + remaining
            while process.poll() is None:
                if overflow.is_set():
                    terminate_adapter_group()
                    break
                if external_interrupt.is_set():
                    cancelled = True
                    terminate_adapter_group()
                    break
                if time.monotonic() >= deadline:
                    timed_out = True
                    terminate_adapter_group()
                    break
                try:
                    connection, _address = listener.accept()
                except socket.timeout:
                    continue
                with connection:
                    try:
                        request = _receive_json(connection)
                        identity = request.get("identity")
                        action = request.get("action")
                        if set(request) != {"action", "identity"} or identity != _call_identity(self._call):
                            raise BindingMismatch(
                                "supervisor request does not match the running call"
                            )
                        if action == "probe":
                            connection.sendall(
                                _canonical_json(
                                    {"active": True, "call_id": self._call.call_id}
                                )
                            )
                        elif action == "cancel":
                            cancelled = True
                            connection.sendall(
                                _canonical_json(
                                    {"accepted": True, "call_id": self._call.call_id}
                                )
                            )
                        else:
                            raise ValidationError("unsupported supervisor action")
                    except Exception as exc:
                        connection.sendall(
                            _canonical_json(
                                {
                                    "accepted": False,
                                    "error": getattr(exc, "code", "invalid_request"),
                                }
                            )
                        )
                    if cancelled:
                        terminate_adapter_group()
                        break

            if process.poll() is None:
                terminate_adapter_group()
            else:
                process.wait()
                terminate_adapter_group()
            for reader in readers:
                reader.join(_TERMINATION_GRACE_SECONDS)
                if reader.is_alive():
                    raise ExecutorUnavailable("adapter output reader did not terminate")
            if cancelled:
                return CanonicalExecutionResult(
                    "interrupted", error="canonical execution was cancelled"
                )
            if timed_out:
                return CanonicalExecutionResult(
                    "timed_out", error="outer canonical execution deadline elapsed"
                )
            if overflow.is_set():
                return CanonicalExecutionResult(
                    "failed", error="adapter transport exceeded its capture bound"
                )
            stdout = b"".join(stdout_chunks)
            stderr = b"".join(stderr_chunks)
            if stderr:
                return CanonicalExecutionResult(
                    "failed", error="fixed adapter wrote unexpected stderr"
                )
            try:
                rendered = stdout.decode("utf-8")
            except UnicodeDecodeError:
                return CanonicalExecutionResult(
                    "failed", error="fixed adapter output is not UTF-8"
                )
            if not rendered.endswith("\n") or rendered.count("\n") != 1:
                return CanonicalExecutionResult(
                    "failed", error="fixed adapter did not emit one JSON line"
                )
            try:
                envelope = json.loads(rendered[:-1])
            except json.JSONDecodeError:
                return CanonicalExecutionResult(
                    "failed", error="fixed adapter envelope is invalid JSON"
                )
            if not isinstance(envelope, dict):
                return CanonicalExecutionResult(
                    "failed", error="fixed adapter envelope is not an object"
                )
            exit_code = envelope.get("exit_code")
            if type(exit_code) is not int or exit_code != process.returncode:
                return CanonicalExecutionResult(
                    "failed", error="adapter exit code contradicts its envelope"
                )
            if envelope.get("timed_out") is True:
                outcome = "timed_out"
            elif envelope.get("ok") is True and envelope.get("status") == "success":
                outcome = "succeeded"
            else:
                outcome = "failed"
            return CanonicalExecutionResult(outcome, envelope)
        finally:
            try:
                for signal_number, previous in previous_handlers:
                    signal.signal(signal_number, previous)
                if process is not None:
                    terminate_adapter_group()
            finally:
                if process is not None:
                    for stream in (process.stdin, process.stdout, process.stderr):
                        if stream is not None and not stream.closed:
                            stream.close()
                for reader in readers:
                    reader.join(_TERMINATION_GRACE_SECONDS)
                if liveness_write_fd is not None:
                    os.close(liveness_write_fd)
                listener.close()
                try:
                    cancel_path.unlink()
                except FileNotFoundError:
                    pass


def request_canonical_cancellation(
    ledger_path: Path, *, client_correlation_id: str
) -> Dict[str, JsonValue]:
    snapshot = ControlPlaneKernel(ledger_path).snapshot()
    matches = [
        call
        for call in snapshot.tool_calls.values()
        if call.client_correlation_id == client_correlation_id
    ]
    if not matches:
        raise NotFound("client correlation was not found")
    if len(matches) != 1:
        raise BindingMismatch("client correlation is not unique")
    call = matches[0]
    if call.state != "running":
        raise InvalidTransition("canonical call is not running")
    response = _send_supervisor_request(
        Path(ledger_path), call, action="cancel", wait_seconds=_CANCEL_CONNECT_SECONDS
    )
    if response != {"accepted": True, "call_id": call.call_id}:
        raise ExecutionDenied("canonical cancellation was rejected")
    return {
        "accepted": True,
        "client_correlation_id": client_correlation_id,
        "call_id": call.call_id,
    }


def _send_supervisor_request(
    ledger_path: Path,
    call: ToolCallRecord,
    *,
    action: str,
    wait_seconds: float,
) -> Dict[str, Any]:
    path = _socket_path(ledger_path, call.call_id)
    deadline = time.monotonic() + wait_seconds
    last_error: Optional[OSError] = None
    while time.monotonic() < deadline:
        connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            metadata = path.lstat()
            if (
                not stat.S_ISSOCK(metadata.st_mode)
                or metadata.st_uid != os.geteuid()
                or stat.S_IMODE(metadata.st_mode) & 0o077
            ):
                raise ExecutionDenied("canonical supervisor socket is unsafe")
            connection.settimeout(0.5)
            connection.connect(str(path))
            connection.sendall(
                _canonical_json(
                    {"action": action, "identity": _call_identity(call)}
                )
            )
            connection.shutdown(socket.SHUT_WR)
            return _receive_json(connection)
        except (FileNotFoundError, ConnectionRefusedError, socket.timeout) as exc:
            last_error = exc
            time.sleep(0.02)
        finally:
            connection.close()
    raise ExecutorUnavailable("running call cancellation endpoint is unavailable") from last_error


def probe_canonical_supervisor(
    ledger_path: Path, call: ToolCallRecord, *, wait_seconds: float = 2.0
) -> bool:
    try:
        response = _send_supervisor_request(
            ledger_path, call, action="probe", wait_seconds=wait_seconds
        )
    except ExecutorUnavailable:
        return False
    return response == {"active": True, "call_id": call.call_id}

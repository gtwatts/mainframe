"""Fixed project-memory adapter supervision with anonymous value channels."""

from __future__ import annotations

import errno
import hashlib
import json
import os
from pathlib import Path
import pwd
import stat
import subprocess
import threading
from datetime import datetime, timezone
from typing import Any, Dict, List, Mapping, Optional

from .errors import (
    BindingMismatch,
    ExecutionDenied,
    ExecutorUnavailable,
    ValidationError,
)
from .durability import create_directory_durable
from .executor import (
    _runtime_directory,
    _terminate_process_group,
    _validate_fixed_executable,
)
from .kernel import JsonValue, normalized_input_digest
from .memory import (
    PROJECT_MEMORY_HANDOFF,
    PROJECT_MEMORY_READ_TOOLS,
    FixedProjectMemoryRegistry,
    ProjectMemoryExecutionRequest,
    ProjectMemoryExecutionResult,
    ProjectMemoryObservation,
)


_FIXED_RELEASE_ROOT = Path(__file__).resolve().parents[2]
_FIXED_TRANSIENT_FD = 196
_FIXED_IDENTITY_FD = 197
_FIXED_LIVENESS_FD = 198
_FIXED_FD_SPAWN_LOCK = threading.Lock()
_MAX_INPUT_BYTES = 32768
_MAX_IDENTITY_BYTES = 16384
_MAX_TRANSIENT_BYTES = 32768
_MAX_CAPTURE_BYTES = 65536


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
        raise ValidationError("project-memory adapter value is not canonical JSON") from exc


def _read_bounded(fd: int, limit: int) -> bytes:
    chunks: List[bytes] = []
    total = 0
    try:
        while True:
            chunk = os.read(fd, min(65536, limit + 1 - total))
            if not chunk:
                break
            total += len(chunk)
            if total > limit:
                raise ValidationError("project-memory transient output exceeds its limit")
            chunks.append(chunk)
    finally:
        os.close(fd)
    return b"".join(chunks)


def _write_all(fd: int, content: bytes) -> None:
    offset = 0
    try:
        while offset < len(content):
            written = os.write(fd, content[offset:])
            if written <= 0:
                raise OSError("project-memory identity handoff made no progress")
            offset += written
    finally:
        os.close(fd)


def _spawn_fixed_fd_adapter(
    command: List[str],
    *,
    cwd: str,
    environment: Mapping[str, str],
    transient_write_fd: int,
    identity_read_fd: int,
    liveness_read_fd: int,
) -> subprocess.Popen[bytes]:
    sources = {
        _FIXED_TRANSIENT_FD: os.dup(transient_write_fd),
        _FIXED_IDENTITY_FD: os.dup(identity_read_fd),
        _FIXED_LIVENESS_FD: os.dup(liveness_read_fd),
    }
    saved: Dict[int, Optional[tuple[int, bool]]] = {}
    try:
        with _FIXED_FD_SPAWN_LOCK:
            try:
                for target in sources:
                    try:
                        inheritable = os.get_inheritable(target)
                        saved[target] = (os.dup(target), inheritable)
                    except OSError as exc:
                        if exc.errno != errno.EBADF:
                            raise
                        saved[target] = None
                for target, source in sources.items():
                    os.dup2(source, target, inheritable=True)
                return subprocess.Popen(
                    command,
                    cwd=cwd,
                    env=dict(environment),
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    pass_fds=(
                        _FIXED_TRANSIENT_FD,
                        _FIXED_IDENTITY_FD,
                        _FIXED_LIVENESS_FD,
                    ),
                    start_new_session=True,
                )
            finally:
                for target, previous in saved.items():
                    if previous is None:
                        try:
                            os.close(target)
                        except OSError as exc:
                            if exc.errno != errno.EBADF:
                                raise
                    else:
                        old_fd, inheritable = previous
                        try:
                            os.dup2(old_fd, target, inheritable=inheritable)
                        finally:
                            os.close(old_fd)
    finally:
        for source in sources.values():
            os.close(source)


class FixedProjectMemorySubprocessExecutor:
    """Own the fixed observer/adapter path, environment, FDs, and bounds."""

    def __init__(self, *, ledger_path: Path) -> None:
        self._ledger_path = Path(ledger_path)
        self._release_root = _FIXED_RELEASE_ROOT

    @classmethod
    def _for_test(
        cls, *, release_root: Path, ledger_path: Path
    ) -> "FixedProjectMemorySubprocessExecutor":
        value = cls(ledger_path=ledger_path)
        value._release_root = Path(release_root).resolve()
        return value

    def _adapter(self) -> Path:
        adapter = self._release_root / "bin" / "mainframe"
        _validate_fixed_executable(adapter)
        return adapter

    def _environment(self) -> Dict[str, str]:
        runtime = _runtime_directory(self._ledger_path, create=True)
        account = pwd.getpwuid(os.geteuid())
        state = runtime / "project-memory-adapter-state"
        if not state.exists():
            create_directory_durable(state, mode=0o700, parents=False)
        metadata = state.lstat()
        if (
            not stat.S_ISDIR(metadata.st_mode)
            or stat.S_ISLNK(metadata.st_mode)
            or metadata.st_uid != os.geteuid()
            or stat.S_IMODE(metadata.st_mode) & 0o077
        ):
            raise ExecutionDenied("project-memory adapter state is unsafe")
        # This is the complete storage-selection contract for the fixed adapter.
        # AWM state must be derived beneath this clean XDG_STATE_HOME; ambient
        # AWM_ROOT and the account's real HOME are intentionally unavailable.
        return {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LC_ALL": "C",
            "NO_COLOR": "1",
            "TERM": "dumb",
            "TMPDIR": "/tmp",
            "HOME": str(runtime),
            "XDG_STATE_HOME": str(state),
            "USER": account.pw_name,
            "LOGNAME": account.pw_name,
        }

    def observe(self, workspace: str, project_digest: str) -> ProjectMemoryObservation:
        expected_digest = hashlib.sha256(workspace.encode("utf-8")).hexdigest()
        if expected_digest != project_digest:
            raise BindingMismatch("observer workspace digest is invalid")
        command = [
            str(self._adapter()),
            "__kernel-project-memory-observer-v1",
            "--format",
            "project-memory-observation-json-v1",
            "--caller",
            "control-plane",
        ]
        try:
            completed = subprocess.run(
                command,
                cwd=workspace,
                env=self._environment(),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5.0,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ExecutorUnavailable("fixed project-memory observer is unavailable") from exc
        if (
            completed.returncode != 0
            or completed.stderr
            or len(completed.stdout) > _MAX_CAPTURE_BYTES
            or not completed.stdout.endswith(b"\n")
            or completed.stdout.count(b"\n") != 1
        ):
            raise ExecutorUnavailable("fixed project-memory observer response is invalid")
        try:
            value = json.loads(completed.stdout[:-1].decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ExecutorUnavailable("fixed project-memory observer is not JSON") from exc
        if not isinstance(value, dict) or set(value) != {
            "schema_version",
            "project_digest",
            "mapping_state",
            "session_id",
            "state_digest",
        }:
            raise ExecutorUnavailable("fixed project-memory observation fields are invalid")
        if value["schema_version"] != 1 or value["project_digest"] != project_digest:
            raise BindingMismatch("fixed project-memory observation identity is invalid")
        return ProjectMemoryObservation(
            project_digest=value["project_digest"],
            mapping_state=value["mapping_state"],
            session_id=value["session_id"],
            state_digest=value["state_digest"],
        )

    def __call__(
        self,
        request: ProjectMemoryExecutionRequest,
        tool_input: Mapping[str, JsonValue],
    ) -> ProjectMemoryExecutionResult:
        if normalized_input_digest(tool_input) != request.input_digest:
            raise BindingMismatch("project-memory adapter input digest changed")
        input_bytes = _canonical_json(dict(tool_input))
        if len(input_bytes) > _MAX_INPUT_BYTES:
            raise ExecutionDenied("project-memory adapter input exceeds 32768 bytes")
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
            "observation": request.observation.to_dict(),
            "retention_class": request.retention_class,
            "expires_at": request.expires_at,
            "timeout_at": request.timeout_at,
        }
        identity_bytes = _canonical_json(identity)
        if len(identity_bytes) > _MAX_IDENTITY_BYTES:
            raise ExecutionDenied("project-memory identity exceeds its fixed bound")

        transient_read, transient_write = os.pipe()
        identity_read, identity_write = os.pipe()
        liveness_read, liveness_write = os.pipe()
        process: Optional[subprocess.Popen[bytes]] = None
        transient_chunks: List[bytes] = []
        transient_error: List[BaseException] = []

        def collect_transient() -> None:
            try:
                transient_chunks.append(_read_bounded(transient_read, _MAX_TRANSIENT_BYTES))
            except BaseException as exc:
                transient_error.append(exc)

        reader = threading.Thread(target=collect_transient, daemon=True)
        try:
            command = [
                str(self._adapter()),
                "__kernel-project-memory-executor-v1",
                request.tool,
                "--input-json",
                "-",
                "--format",
                "project-memory-executor-json-v1",
                "--caller",
                "control-plane",
            ]
            process = _spawn_fixed_fd_adapter(
                command,
                cwd=request.workspace,
                environment=self._environment(),
                transient_write_fd=transient_write,
                identity_read_fd=identity_read,
                liveness_read_fd=liveness_read,
            )
            os.close(transient_write)
            transient_write = -1
            os.close(identity_read)
            identity_read = -1
            os.close(liveness_read)
            liveness_read = -1
            reader.start()
            _write_all(identity_write, identity_bytes)
            identity_write = -1
            if process.stdin is None or process.stdout is None or process.stderr is None:
                raise ExecutorUnavailable("project-memory adapter pipes are unavailable")
            deadline = datetime.fromisoformat(
                request.timeout_at.replace("Z", "+00:00")
            ).astimezone(timezone.utc)
            remaining = max(
                0.0, (deadline - datetime.now(timezone.utc)).total_seconds()
            )
            try:
                stdout, stderr = process.communicate(input=input_bytes, timeout=remaining)
            except subprocess.TimeoutExpired:
                _terminate_process_group(process)
                raise ExecutorUnavailable(
                    "project-memory adapter exceeded its durable deadline"
                )
            _terminate_process_group(process)
            reader.join(1.5)
            if reader.is_alive() or transient_error:
                raise ExecutorUnavailable("project-memory transient channel failed")
            if len(stdout) + len(stderr) > _MAX_CAPTURE_BYTES:
                raise ValidationError("project-memory adapter capture exceeded its limit")
            if stderr or not stdout.endswith(b"\n") or stdout.count(b"\n") != 1:
                raise ValidationError("project-memory adapter did not emit one clean JSON line")
            try:
                outer = json.loads(stdout[:-1].decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise ValidationError("project-memory adapter result is invalid JSON") from exc
            if not isinstance(outer, dict) or set(outer) != {
                "schema_version",
                "outcome",
                "receipt",
                "error_code",
                "transient_bytes",
                "transient_sha256",
            }:
                raise ValidationError("project-memory adapter result fields are not exact")
            if outer["schema_version"] != 1:
                raise ValidationError("project-memory adapter result version is invalid")
            outcome = outer["outcome"]
            if outcome not in ("succeeded", "failed", "recovery_required"):
                raise ValidationError("project-memory adapter outcome is invalid")
            if outer["error_code"] is not None and not isinstance(
                outer["error_code"], str
            ):
                raise ValidationError("project-memory adapter error code is invalid")
            transient = transient_chunks[0] if transient_chunks else b""
            if (
                outer["transient_bytes"] != len(transient)
                or outer["transient_sha256"]
                != hashlib.sha256(transient).hexdigest()
            ):
                raise BindingMismatch("project-memory transient output binding is invalid")
            contract = FixedProjectMemoryRegistry().contract(request.tool)
            if request.tool == PROJECT_MEMORY_HANDOFF:
                if outcome == "succeeded" and not transient:
                    raise BindingMismatch("successful handoff omitted its transient package")
            elif request.tool in PROJECT_MEMORY_READ_TOOLS:
                if outcome == "succeeded" and not transient and not contract.allow_empty_transient:
                    raise BindingMismatch("successful project-memory read omitted its output")
                if outcome != "succeeded" and transient:
                    raise BindingMismatch("unsuccessful project-memory read emitted raw output")
            elif transient:
                raise BindingMismatch("non-handoff project-memory tool emitted raw output")
            receipt = outer["receipt"]
            if not isinstance(receipt, dict):
                raise ValidationError("project-memory adapter receipt is invalid")
            return ProjectMemoryExecutionResult(
                outcome,
                receipt,
                transient
                if outcome == "succeeded" and contract.transient_output
                else None,
            )
        finally:
            if process is not None:
                try:
                    _terminate_process_group(process)
                except Exception:
                    pass
                for stream in (process.stdin, process.stdout, process.stderr):
                    if stream is not None and not stream.closed:
                        stream.close()
            for fd in (
                transient_write,
                identity_read,
                identity_write,
                liveness_read,
                liveness_write,
            ):
                if fd >= 0:
                    try:
                        os.close(fd)
                    except OSError:
                        pass
            if reader.is_alive():
                reader.join(1.5)

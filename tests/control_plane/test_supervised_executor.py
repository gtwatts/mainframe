from __future__ import annotations

import json
import base64
from datetime import datetime, timedelta, timezone
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock


PROJECT_ROOT = Path(__file__).resolve().parents[2]
CLI = PROJECT_ROOT / "control_plane" / "mainframe-control-plane"
sys.path.insert(0, str(PROJECT_ROOT / "control_plane"))

from mainframe_control_plane import (  # noqa: E402
    ControlPlaneKernel,
    FixedStableCoreEvaluator,
    load_fixed_stable_core_registry,
)
from mainframe_control_plane.cli import (  # noqa: E402
    _canonical_invoke,
    _spawn_canonical_worker,
)
from mainframe_control_plane.executor import (  # noqa: E402
    FixedStableCoreSubprocessExecutor,
)


class SupervisedExecutorTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(os.path.realpath(self.temp_dir.name))
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        self.state_root = self.root / "state"
        self.state_root.mkdir(mode=0o700)
        self.ledger = self.state_root / "mainframe" / "control-plane.jsonl"
        self.ledger.parent.mkdir(mode=0o700)

    def _public_invoke(self, correlation_id: str, value: str):
        return subprocess.run(
            [
                str(CLI),
                "canonical-invoke",
                "--canonical-id",
                "mf:std:pure-string:to_upper",
                "--input-json",
                "-",
                "--client-correlation-id",
                correlation_id,
            ],
            input=json.dumps({"value": value}),
            cwd=self.workspace,
            env={
                "PATH": "/poisoned",
                "PYTHONPATH": "/poisoned",
                "XDG_STATE_HOME": str(self.state_root),
                "HOME": "/tmp",
                "TMPDIR": "/tmp",
            },
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )

    def test_anonymous_handoff_faults_leave_no_secret_and_retry_same_ids(self) -> None:
        registry = load_fixed_stable_core_registry()
        kernel = ControlPlaneKernel(
            self.ledger,
            evaluator=FixedStableCoreEvaluator(registry),
            stable_core_registry=registry,
        )
        first_secret = "reserve-handoff-secret-11d9"
        with mock.patch(
            "mainframe_control_plane.cli._spawn_canonical_worker",
            side_effect=OSError("injected before handoff"),
        ), mock.patch(
            "mainframe_control_plane.cli.os.getcwd",
            return_value=str(self.workspace),
        ):
            with self.assertRaises(OSError):
                _canonical_invoke(
                    kernel,
                    canonical_id="mf:std:pure-string:to_upper",
                    tool_input={"value": first_secret},
                    client_correlation_id="crash-before-handoff",
                )
        first_request = kernel.snapshot().canonical_requests["crash-before-handoff"]
        self.assertNotIn(first_secret, self.ledger.read_text(encoding="utf-8"))
        completed = self._public_invoke("crash-before-handoff", first_secret)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        first_result = json.loads(completed.stdout)["result"]
        self.assertEqual(first_result["run_id"], first_request.run_id)
        self.assertEqual(first_result["call_id"], first_request.call_id)

        second_secret = "mid-pipe-secret-72ac"
        real_write = os.write
        writes = 0

        def partial_then_fail(fd, content):
            nonlocal writes
            writes += 1
            if writes == 1:
                return real_write(fd, content[:9])
            raise OSError("injected mid-handoff failure")

        def faulty_spawn(ledger_path, correlation_id, tool_input):
            return _spawn_canonical_worker(
                ledger_path,
                correlation_id,
                tool_input,
                write_func=partial_then_fail,
            )

        with mock.patch(
            "mainframe_control_plane.cli._spawn_canonical_worker",
            side_effect=faulty_spawn,
        ), mock.patch(
            "mainframe_control_plane.cli.os.getcwd",
            return_value=str(self.workspace),
        ):
            with self.assertRaises(OSError):
                _canonical_invoke(
                    kernel,
                    canonical_id="mf:std:pure-string:to_upper",
                    tool_input={"value": second_secret},
                    client_correlation_id="crash-mid-handoff",
                )
        second_request = kernel.snapshot().canonical_requests["crash-mid-handoff"]
        self.assertNotIn(second_secret, self.ledger.read_text(encoding="utf-8"))
        self.assertNotIn(second_request.call_id, kernel.snapshot().tool_calls)
        completed = self._public_invoke("crash-mid-handoff", second_secret)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        second_result = json.loads(completed.stdout)["result"]
        self.assertEqual(second_result["run_id"], second_request.run_id)
        self.assertEqual(second_result["call_id"], second_request.call_id)
        self.assertEqual(
            len(
                [
                    call
                    for call in ControlPlaneKernel(self.ledger).snapshot().tool_calls.values()
                    if call.client_correlation_id == "crash-mid-handoff"
                ]
            ),
            1,
        )
        for path in self.state_root.rglob("*"):
            if path.is_file():
                content = path.read_bytes()
                self.assertNotIn(first_secret.encode("utf-8"), content)
                self.assertNotIn(second_secret.encode("utf-8"), content)

    def test_foreground_death_after_execution_leaves_no_raw_result_residue(self) -> None:
        secret = "caller-death-output-secret-3f8c"
        program = (
            "import sys,time;"
            "sys.path.insert(0,{control_plane!r});"
            "from mainframe_control_plane import ControlPlaneKernel,FixedStableCoreEvaluator,load_fixed_stable_core_registry;"
            "from mainframe_control_plane.cli import _canonical_invoke;"
            "r=load_fixed_stable_core_registry();"
            "k=ControlPlaneKernel({ledger!r},evaluator=FixedStableCoreEvaluator(r),stable_core_registry=r);"
            "_canonical_invoke(k,canonical_id='mf:std:pure-string:to_upper',tool_input={{'value':{secret!r}}},client_correlation_id='caller-death');"
            "time.sleep(30)"
        ).format(
            control_plane=str(PROJECT_ROOT / "control_plane"),
            ledger=str(self.ledger),
            secret=secret,
        )
        invocation = subprocess.Popen(
            ["/usr/bin/python3", "-B", "-I", "-c", program],
            cwd=self.workspace,
            env={
                "PATH": "/poisoned",
                "PYTHONPATH": "/poisoned",
                "HOME": "/tmp",
                "TMPDIR": "/tmp",
            },
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        def cleanup() -> None:
            if invocation.poll() is None:
                invocation.kill()
            invocation.wait(timeout=5)

        self.addCleanup(cleanup)
        deadline = time.monotonic() + 8
        completed = False
        while time.monotonic() < deadline:
            if self.ledger.exists():
                snapshot = ControlPlaneKernel(self.ledger).snapshot()
                request = snapshot.canonical_requests.get("caller-death")
                if (
                    request is not None
                    and snapshot.runs.get(request.run_id) is not None
                    and snapshot.runs[request.run_id].state == "completed"
                ):
                    completed = True
                    break
            time.sleep(0.02)
        self.assertTrue(completed)
        invocation.kill()
        invocation.wait(timeout=5)
        self.assertEqual(invocation.returncode, -9)
        for path in self.root.rglob("*"):
            if path.is_file():
                content = path.read_bytes()
                self.assertNotIn(secret.encode("utf-8"), content)
                self.assertNotIn(secret.upper().encode("utf-8"), content)

    def test_presentation_formats_use_only_first_anonymous_delivery(self) -> None:
        broker = subprocess.run(
            [
                str(CLI),
                "canonical-invoke",
                "--canonical-id",
                "mf:std:pure-string:to_upper",
                "--input-json",
                '{"value":"broker-pipe"}',
                "--client-correlation-id",
                "present-broker",
                "--format",
                "broker-json-v1",
            ],
            cwd=self.workspace,
            env={
                "PATH": "/poisoned",
                "XDG_STATE_HOME": str(self.state_root),
                "HOME": "/tmp",
                "TMPDIR": "/tmp",
            },
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        self.assertEqual(broker.returncode, 0)
        self.assertEqual(broker.stderr, "")
        envelope = json.loads(broker.stdout)
        self.assertEqual(envelope["stdout_b64"], "QlJPS0VSLVBJUEUK")

        consumed = subprocess.run(
            [
                str(CLI),
                "canonical-invoke",
                "--canonical-id",
                "mf:std:pure-string:to_upper",
                "--input-json",
                '{"value":"broker-pipe"}',
                "--client-correlation-id",
                "present-broker",
                "--format",
                "broker-json-v1",
            ],
            cwd=self.workspace,
            env={
                "PATH": "/poisoned",
                "XDG_STATE_HOME": str(self.state_root),
                "HOME": "/tmp",
                "TMPDIR": "/tmp",
            },
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(consumed.returncode, 66)
        self.assertEqual(consumed.stdout, b"")
        self.assertEqual(consumed.stderr, b"")

        raw = subprocess.run(
            [
                str(CLI),
                "canonical-invoke",
                "--canonical-id",
                "mf:std:pure-string:to_upper",
                "--input-json",
                '{"value":"raw-pipe"}',
                "--client-correlation-id",
                "present-raw",
                "--format",
                "raw",
            ],
            cwd=self.workspace,
            env={
                "PATH": "/poisoned",
                "XDG_STATE_HOME": str(self.state_root),
                "HOME": "/tmp",
                "TMPDIR": "/tmp",
            },
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(raw.returncode, 0)
        self.assertEqual(raw.stdout, b"RAW-PIPE\n")
        self.assertEqual(raw.stderr, b"")
        for path in self.state_root.rglob("*"):
            if path.is_file():
                content = path.read_bytes()
                self.assertNotIn(b"broker-pipe", content)
                self.assertNotIn(b"BROKER-PIPE", content)
                self.assertNotIn(b"raw-pipe", content)
                self.assertNotIn(b"RAW-PIPE", content)

    def test_restart_resumes_pending_and_ready_but_never_reexecutes_running(self) -> None:
        registry = load_fixed_stable_core_registry()
        kernel = ControlPlaneKernel(
            self.ledger,
            evaluator=FixedStableCoreEvaluator(registry),
            stable_core_registry=registry,
        )
        actor = "local-uid:{}:mainframe-cli".format(os.geteuid())

        def prepare(correlation_id: str, secret: str, state: str):
            tool_input = {"value": secret}
            request = kernel.reserve_canonical_request(
                client_correlation_id=correlation_id,
                canonical_id="mf:std:pure-string:to_upper",
                tool_input=tool_input,
                actor=actor,
                workspace=str(self.workspace),
                policy="stable-core-v1",
            )
            kernel.create_run(
                run_id=request.run_id,
                actor=request.actor,
                workspace=request.workspace,
                policy=request.policy,
            )
            kernel.transition_run(request.run_id, "active")
            call = kernel.create_canonical_tool_call(
                call_id=request.call_id,
                run_id=request.run_id,
                canonical_id=request.canonical_id,
                tool_input=tool_input,
                client_correlation_id=correlation_id,
            )
            if state in ("ready", "running"):
                kernel.evaluate_policy_decision(
                    decision_id=request.decision_id,
                    call_id=call.call_id,
                    tool=call.tool,
                    input_digest=call.input_digest,
                    actor=call.actor,
                    workspace=call.workspace,
                    policy=call.policy,
                    timeout_at=call.timeout_at,
                    tool_input=tool_input,
                )
            if state == "running":
                with self.assertRaises(RuntimeError):
                    kernel.execute_canonical(
                        call.call_id,
                        executor=lambda _tool, _input: self.fail(
                            "running recovery must not execute"
                        ),
                        tool_input=tool_input,
                        after_start_hook=lambda: (_ for _ in ()).throw(
                            RuntimeError("injected worker death after running")
                        ),
                    )
            return request

        pending = prepare("resume-pending", "pending-secret-a731", "pending")
        pending_result = json.loads(
            self._public_invoke("resume-pending", "pending-secret-a731").stdout
        )["result"]
        self.assertEqual(pending_result["call_id"], pending.call_id)
        self.assertEqual(pending_result["outcome"], "succeeded")

        ready = prepare("resume-ready", "ready-secret-820c", "ready")
        ready_result = json.loads(
            self._public_invoke("resume-ready", "ready-secret-820c").stdout
        )["result"]
        self.assertEqual(ready_result["call_id"], ready.call_id)
        self.assertEqual(ready_result["outcome"], "succeeded")

        running = prepare("recover-running", "running-secret-9e2d", "running")
        recovered_process = self._public_invoke(
            "recover-running", "running-secret-9e2d"
        )
        self.assertEqual(recovered_process.returncode, 0, recovered_process.stdout)
        recovered = json.loads(recovered_process.stdout)["result"]
        self.assertEqual(recovered["call_id"], running.call_id)
        self.assertEqual(recovered["outcome"], "interrupted")
        self.assertFalse(recovered["result_available"])
        snapshot = ControlPlaneKernel(self.ledger).snapshot()
        self.assertEqual(snapshot.runs[running.run_id].state, "failed")
        self.assertEqual(snapshot.tool_calls[running.call_id].state, "interrupted")
        self.assertEqual(
            len(
                [
                    evidence
                    for evidence in snapshot.evidence.values()
                    if evidence.call_id == running.call_id
                ]
            ),
            1,
        )

    def test_executor_uses_remaining_durable_deadline_not_fresh_contract_timeout(self) -> None:
        release = self.root / "deadline-release"
        (release / "bin").mkdir(parents=True)
        adapter = release / "bin" / "mainframe"
        adapter.write_text(
            "#!/bin/sh\ntrap 'exit 143' TERM\nsleep 30\n",
            encoding="utf-8",
        )
        adapter.chmod(0o755)
        registry = load_fixed_stable_core_registry()
        kernel = ControlPlaneKernel(
            self.ledger,
            evaluator=FixedStableCoreEvaluator(registry),
            stable_core_registry=registry,
        )
        kernel.create_run(
            run_id="deadline-run",
            actor="agent:test",
            workspace=str(self.workspace),
            policy="stable-core-v1",
        )
        kernel.transition_run("deadline-run", "active")
        tool_input = {"value": "deadline-value"}
        call = kernel.create_tool_call(
            call_id="deadline-call",
            run_id="deadline-run",
            tool="mf:std:pure-string:to_upper",
            tool_input=tool_input,
            effect="read_only",
            timeout_at=datetime.now(timezone.utc) + timedelta(milliseconds=350),
        )
        kernel.evaluate_policy_decision(
            decision_id="deadline-decision",
            call_id=call.call_id,
            tool=call.tool,
            input_digest=call.input_digest,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
            timeout_at=call.timeout_at,
        )
        time.sleep(0.25)
        executor = FixedStableCoreSubprocessExecutor._for_test(
            release_root=release,
            registry=registry,
            call=kernel.snapshot().tool_calls[call.call_id],
            ledger_path=self.ledger,
        )
        started = time.monotonic()
        evidence = kernel.execute_canonical(call.call_id, executor=executor)
        elapsed = time.monotonic() - started
        self.assertEqual(evidence.outcome, "timed_out")
        self.assertLess(elapsed, 1.5)

    def test_group_cleanup_never_resignals_a_reusable_pgid(self) -> None:
        release = self.root / "single-cleanup-release"
        (release / "bin").mkdir(parents=True)
        envelope = {
            "schema_version": 1,
            "ok": True,
            "status": "success",
            "canonical_id": "mf:std:pure-string:to_upper",
            "name": "to_upper",
            "owner": "pure-string",
            "exit_code": 0,
            "timed_out": False,
            "output_exceeded": False,
            "duration_ms": 1,
            "audit_id": "audit-single-cleanup",
            "stdout_b64": "T0sK",
            "stderr_b64": "",
            "error": None,
        }
        adapter = release / "bin" / "mainframe"
        adapter.write_text(
            "#!/bin/sh\nprintf '%s\\n' '{}'\n".format(
                json.dumps(envelope, separators=(",", ":"))
            ),
            encoding="utf-8",
        )
        adapter.chmod(0o755)
        registry = load_fixed_stable_core_registry()
        kernel = ControlPlaneKernel(
            self.ledger,
            evaluator=FixedStableCoreEvaluator(registry),
            stable_core_registry=registry,
        )
        kernel.create_run(
            run_id="single-cleanup-run",
            actor="agent:test",
            workspace=str(self.workspace),
            policy="stable-core-v1",
        )
        kernel.transition_run("single-cleanup-run", "active")
        call = kernel.create_canonical_tool_call(
            call_id="single-cleanup-call",
            run_id="single-cleanup-run",
            canonical_id="mf:std:pure-string:to_upper",
            tool_input={"value": "cleanup"},
        )
        kernel.evaluate_policy_decision(
            decision_id="single-cleanup-decision",
            call_id=call.call_id,
            tool=call.tool,
            input_digest=call.input_digest,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
            timeout_at=call.timeout_at,
        )
        executor = FixedStableCoreSubprocessExecutor._for_test(
            release_root=release,
            registry=registry,
            call=kernel.snapshot().tool_calls[call.call_id],
            ledger_path=self.ledger,
        )
        from mainframe_control_plane.executor import _terminate_process_group

        cleanup_calls = 0

        def reject_reused_pgid(process):
            nonlocal cleanup_calls
            cleanup_calls += 1
            if cleanup_calls > 1:
                raise PermissionError("numeric PGID was reused by a foreign group")
            _terminate_process_group(process)

        with mock.patch(
            "mainframe_control_plane.executor._terminate_process_group",
            side_effect=reject_reused_pgid,
        ):
            evidence = kernel.execute_canonical(call.call_id, executor=executor)
        self.assertEqual(evidence.outcome, "succeeded")
        self.assertEqual(cleanup_calls, 1)

    def test_foreground_sigint_and_sigterm_cancel_and_close_durably(self) -> None:
        fake_release = self.root / "signal-release"
        shutil.copytree(PROJECT_ROOT / "control_plane", fake_release / "control_plane")
        shutil.copy2(PROJECT_ROOT / "INVOCATION_INDEX.json", fake_release)
        shutil.copy2(PROJECT_ROOT / "VERSION", fake_release)
        (fake_release / "bin").mkdir(parents=True)
        adapter = fake_release / "bin" / "mainframe"
        adapter.write_text(
            "#!/bin/sh\n"
            "trap 'kill \"$child\" 2>/dev/null; wait \"$child\" 2>/dev/null; exit 143' TERM INT\n"
            "sleep 30 & child=$!\n"
            "printf '%s\\n' \"$child\" > child.pid\n"
            "wait \"$child\"\n",
            encoding="utf-8",
        )
        adapter.chmod(0o755)
        copied_cli = fake_release / "control_plane" / "mainframe-control-plane"

        for signal_number, expected_exit, label in (
            (signal.SIGINT, 130, "sigint"),
            (signal.SIGTERM, 143, "sigterm"),
        ):
            with self.subTest(signal=label):
                state_root = self.root / ("state-{}".format(label))
                state_root.mkdir(mode=0o700)
                workspace = self.root / ("workspace-{}".format(label))
                workspace.mkdir()
                ledger = state_root / "mainframe" / "control-plane.jsonl"
                invocation = subprocess.Popen(
                    [
                        str(copied_cli),
                        "canonical-invoke",
                        "--canonical-id",
                        "mf:std:pure-string:to_upper",
                        "--input-json",
                        '{"value":"signal-test"}',
                        "--client-correlation-id",
                        "signal-{}".format(label),
                        "--format",
                        "raw",
                    ],
                    cwd=workspace,
                    env={
                        "PATH": "/poisoned",
                        "PYTHONPATH": "/poisoned",
                        "XDG_STATE_HOME": str(state_root),
                        "HOME": "/tmp",
                        "TMPDIR": "/tmp",
                    },
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                )
                try:
                    child_file = workspace / "child.pid"
                    deadline = time.monotonic() + 5
                    while not child_file.exists() and time.monotonic() < deadline:
                        time.sleep(0.02)
                    self.assertTrue(child_file.exists())
                    child_pid = int(child_file.read_text().strip())
                    invocation.send_signal(signal_number)
                    stdout, stderr = invocation.communicate(timeout=8)
                    self.assertEqual(invocation.returncode, expected_exit)
                    self.assertEqual(stdout, b"")
                    self.assertEqual(stderr, b"")
                    snapshot = ControlPlaneKernel(ledger).snapshot()
                    request = snapshot.canonical_requests[
                        "signal-{}".format(label)
                    ]
                    self.assertEqual(
                        snapshot.tool_calls[request.call_id].state, "interrupted"
                    )
                    self.assertEqual(snapshot.runs[request.run_id].state, "failed")
                    with self.assertRaises(ProcessLookupError):
                        os.kill(child_pid, 0)
                finally:
                    if invocation.poll() is None:
                        invocation.kill()
                    invocation.wait(timeout=5)

    def test_leader_exit_still_kills_same_group_descendant_with_closed_stdio(self) -> None:
        release = self.root / "orphan-release"
        (release / "bin").mkdir(parents=True)
        adapter = release / "bin" / "mainframe"
        adapter.write_text(
            "#!/bin/sh\n"
            "sleep 30 </dev/null >/dev/null 2>&1 & child=$!\n"
            "printf '%s\\n' \"$child\" > child.pid\n"
            "exit 0\n",
            encoding="utf-8",
        )
        adapter.chmod(0o755)
        registry = load_fixed_stable_core_registry()
        kernel = ControlPlaneKernel(
            self.ledger,
            evaluator=FixedStableCoreEvaluator(registry),
            stable_core_registry=registry,
        )
        kernel.create_run(
            run_id="orphan-run",
            actor="agent:test",
            workspace=str(self.workspace),
            policy="stable-core-v1",
        )
        kernel.transition_run("orphan-run", "active")
        call = kernel.create_canonical_tool_call(
            call_id="orphan-call",
            run_id="orphan-run",
            canonical_id="mf:std:pure-string:to_upper",
            tool_input={"value": "orphan-test"},
        )
        kernel.evaluate_policy_decision(
            decision_id="orphan-decision",
            call_id=call.call_id,
            tool=call.tool,
            input_digest=call.input_digest,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
            timeout_at=call.timeout_at,
        )
        executor = FixedStableCoreSubprocessExecutor._for_test(
            release_root=release,
            registry=registry,
            call=kernel.snapshot().tool_calls[call.call_id],
            ledger_path=self.ledger,
        )
        evidence = kernel.execute_canonical(call.call_id, executor=executor)
        self.assertEqual(evidence.outcome, "failed")
        child_pid = int((self.workspace / "child.pid").read_text().strip())
        with self.assertRaises(ProcessLookupError):
            os.kill(child_pid, 0)

    def test_one_shot_launcher_owns_policy_executor_and_evidence(self) -> None:
        completed = subprocess.run(
            [
                str(CLI),
                "canonical-invoke",
                "--canonical-id",
                "mf:std:pure-string:to_upper",
                "--input-json",
                "-",
                "--client-correlation-id",
                "client-live",
            ],
            input='{"value":"private-secret-7fe1"}',
            cwd=self.workspace,
            env={
                "PATH": "/definitely/poisoned",
                "PYTHONPATH": "/poisoned",
                "XDG_STATE_HOME": str(self.state_root),
                "HOME": "/tmp",
                "TMPDIR": "/tmp",
            },
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout)
        self.assertEqual(completed.stderr, "")
        payload = json.loads(completed.stdout)
        self.assertTrue(payload["ok"])
        result = payload["result"]
        self.assertEqual(result["outcome"], "succeeded")
        self.assertEqual(result["client_correlation_id"], "client-live")
        self.assertTrue(result["run_id"].startswith("run-"))
        self.assertTrue(result["call_id"].startswith("call-"))
        self.assertTrue(result["decision_id"].startswith("decision-"))
        self.assertTrue(result["evidence_id"].startswith("evidence-"))
        self.assertNotIn(
            "client-live",
            {
                result["run_id"],
                result["call_id"],
                result["decision_id"],
                result["evidence_id"],
            },
        )
        envelope = result["broker_envelope"]
        self.assertTrue(result["result_available"])
        self.assertEqual(envelope["canonical_id"], "mf:std:pure-string:to_upper")
        self.assertEqual(envelope["name"], "to_upper")
        self.assertEqual(envelope["owner"], "pure-string")
        self.assertEqual(
            base64.b64decode(envelope["stdout_b64"]),
            b"PRIVATE-SECRET-7FE1\n",
        )
        snapshot = ControlPlaneKernel(self.ledger).snapshot()
        call = snapshot.tool_calls[result["call_id"]]
        self.assertEqual(call.state, "succeeded")
        self.assertIsNone(call.tool_input)
        self.assertEqual(call.client_correlation_id, "client-live")
        self.assertEqual(
            snapshot.policy_decisions[result["decision_id"]].authority,
            "policy-engine:fixed-stable-core-v1",
        )
        self.assertEqual(snapshot.runs[result["run_id"]].state, "completed")

        repeated = subprocess.run(
            [
                str(CLI),
                "canonical-invoke",
                "--canonical-id",
                "mf:std:pure-string:to_upper",
                "--input-json",
                '{"value":"private-secret-7fe1"}',
                "--client-correlation-id",
                "client-live",
            ],
            cwd=self.workspace,
            env={
                "XDG_STATE_HOME": str(self.state_root),
                "PATH": "/poisoned",
                "HOME": "/tmp",
                "TMPDIR": "/tmp",
            },
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        self.assertEqual(repeated.returncode, 0)
        repeated_result = json.loads(repeated.stdout)["result"]
        self.assertFalse(repeated_result["result_available"])
        self.assertIsNone(repeated_result["broker_envelope"])
        for key in (
            "run_id",
            "call_id",
            "decision_id",
            "evidence_id",
            "input_digest",
            "outcome",
            "broker_receipt",
        ):
            self.assertEqual(repeated_result[key], result[key])
        self.assertEqual(ControlPlaneKernel(self.ledger).snapshot().event_count, 8)
        for path in self.state_root.rglob("*"):
            if path.is_file():
                content = path.read_bytes()
                self.assertNotIn(b"private-secret-7fe1", content)
                self.assertNotIn(b"PRIVATE-SECRET-7FE1", content)

        mismatch = subprocess.run(
            [
                str(CLI),
                "canonical-invoke",
                "--canonical-id",
                "mf:std:pure-string:to_upper",
                "--input-json",
                '{"value":"different"}',
                "--client-correlation-id",
                "client-live",
            ],
            cwd=self.workspace,
            env={
                "XDG_STATE_HOME": str(self.state_root),
                "PATH": "/poisoned",
                "HOME": "/tmp",
                "TMPDIR": "/tmp",
            },
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        self.assertEqual(mismatch.returncode, 3)
        self.assertEqual(json.loads(mismatch.stdout)["error"]["code"], "binding_mismatch")
        self.assertEqual(ControlPlaneKernel(self.ledger).snapshot().event_count, 8)

    def test_concurrent_cancel_terminates_adapter_group_and_leaves_no_orphan(self) -> None:
        fake_release = self.root / "fake-release"
        shutil.copytree(PROJECT_ROOT / "control_plane", fake_release / "control_plane")
        shutil.copy2(PROJECT_ROOT / "INVOCATION_INDEX.json", fake_release)
        shutil.copy2(PROJECT_ROOT / "VERSION", fake_release)
        (fake_release / "bin").mkdir(parents=True)
        adapter = fake_release / "bin" / "mainframe"
        adapter.write_text(
            "#!/bin/sh\n"
            "trap 'kill \"$child\" 2>/dev/null; wait \"$child\" 2>/dev/null; exit 143' TERM\n"
            "sleep 30 & child=$!\n"
            "printf '%s\\n' \"$child\" > child.pid\n"
            "wait \"$child\"\n",
            encoding="utf-8",
        )
        adapter.chmod(0o755)
        copied_cli = fake_release / "control_plane" / "mainframe-control-plane"
        invocation = subprocess.Popen(
            [
                str(copied_cli),
                "canonical-invoke",
                "--canonical-id",
                "mf:std:pure-string:to_upper",
                "--input-json",
                '{"value":"hello"}',
                "--client-correlation-id",
                "client-cancel-live",
            ],
            cwd=self.workspace,
            env={
                "PATH": "/poisoned",
                "PYTHONPATH": "/poisoned",
                "XDG_STATE_HOME": str(self.state_root),
                "HOME": "/tmp",
                "TMPDIR": "/tmp",
            },
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        child_file = self.workspace / "child.pid"
        deadline = time.monotonic() + 5
        while not child_file.exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue(child_file.exists())
        child_pid = int(child_file.read_text().strip())

        cancellation = subprocess.run(
            [
                str(copied_cli),
                "canonical-cancel",
                "--client-correlation-id",
                "client-cancel-live",
            ],
            cwd=self.workspace,
            env={
                "PATH": "/poisoned",
                "PYTHONPATH": "/poisoned",
                "XDG_STATE_HOME": str(self.state_root),
                "HOME": "/tmp",
                "TMPDIR": "/tmp",
            },
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        self.assertEqual(cancellation.returncode, 0, cancellation.stdout)
        self.assertEqual(cancellation.stderr, "")
        cancel_result = json.loads(cancellation.stdout)["result"]
        self.assertTrue(cancel_result["accepted"])
        stdout, stderr = invocation.communicate(timeout=5)
        self.assertEqual(invocation.returncode, 0, stdout)
        self.assertEqual(stderr, "")
        result = json.loads(stdout)["result"]
        self.assertEqual(result["call_id"], cancel_result["call_id"])
        self.assertEqual(result["outcome"], "interrupted")
        snapshot = ControlPlaneKernel(self.ledger).snapshot()
        self.assertEqual(snapshot.tool_calls[result["call_id"]].state, "interrupted")
        self.assertEqual(snapshot.runs[result["run_id"]].state, "failed")
        with self.assertRaises(ProcessLookupError):
            os.kill(child_pid, 0)

    def test_worker_sigkill_liveness_guardian_eliminates_adapter_group(self) -> None:
        """An inherited anonymous pipe makes hard worker death observable."""

        fake_release = self.root / "sigkill-release"
        shutil.copytree(PROJECT_ROOT / "control_plane", fake_release / "control_plane")
        shutil.copy2(PROJECT_ROOT / "INVOCATION_INDEX.json", fake_release)
        shutil.copy2(PROJECT_ROOT / "VERSION", fake_release)
        (fake_release / "bin").mkdir(parents=True)
        adapter = fake_release / "bin" / "mainframe"
        adapter.write_text(
            "#!/bin/sh\n"
            "(\n"
            "  trap '' TERM HUP\n"
            "  : <&198 || exit 97\n"
            "  printf ready > guardian.ready\n"
            "  exec </dev/null >/dev/null 2>/dev/null\n"
            "  if IFS= read -r _clean <&198; then exit 0; fi\n"
            "  kill -TERM -- \"-$$\" 2>/dev/null || true\n"
            "  /bin/sleep 1\n"
            "  kill -KILL -- \"-$$\" 2>/dev/null || true\n"
            ") &\n"
            "exec 198<&-\n"
            "sleep 30 & child=$!\n"
            "printf '%s %s %s\\n' \"$$\" \"$PPID\" \"$child\" > worker-kill.pids\n"
            "wait \"$child\"\n",
            encoding="utf-8",
        )
        adapter.chmod(0o755)
        copied_cli = fake_release / "control_plane" / "mainframe-control-plane"
        invocation = subprocess.Popen(
            [
                str(copied_cli),
                "canonical-invoke",
                "--canonical-id",
                "mf:std:pure-string:to_upper",
                "--input-json",
                '{"value":"worker-sigkill"}',
                "--client-correlation-id",
                "worker-sigkill-red",
            ],
            cwd=self.workspace,
            env={
                "PATH": "/poisoned",
                "PYTHONPATH": "/poisoned",
                "XDG_STATE_HOME": str(self.state_root),
                "HOME": "/tmp",
                "TMPDIR": "/tmp",
            },
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        pids_file = self.workspace / "worker-kill.pids"
        guardian_ready = self.workspace / "guardian.ready"
        adapter_pid = None
        worker_pid = None
        child_pid = None

        def cleanup() -> None:
            if adapter_pid is not None:
                try:
                    os.killpg(adapter_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            if invocation.poll() is None:
                invocation.kill()
            invocation.communicate(timeout=5)

        self.addCleanup(cleanup)
        deadline = time.monotonic() + 5
        while (
            (not pids_file.exists() or not guardian_ready.exists())
            and time.monotonic() < deadline
        ):
            time.sleep(0.02)
        self.assertTrue(pids_file.exists())
        self.assertTrue(guardian_ready.exists())
        adapter_pid, worker_pid, child_pid = (
            int(value) for value in pids_file.read_text(encoding="utf-8").split()
        )
        os.kill(adapter_pid, 0)
        os.kill(child_pid, 0)
        os.kill(worker_pid, signal.SIGKILL)
        time.sleep(0.25)

        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            try:
                os.kill(adapter_pid, 0)
            except ProcessLookupError:
                break
            time.sleep(0.02)
        with self.assertRaises(ProcessLookupError):
            os.kill(adapter_pid, 0)
        with self.assertRaises(ProcessLookupError):
            os.kill(child_pid, 0)


if __name__ == "__main__":
    unittest.main()

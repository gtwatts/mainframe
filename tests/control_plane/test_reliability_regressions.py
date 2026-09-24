"""Regressions reproduced in the Mainframe review, using private fixture state."""

from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "control_plane"))

from mainframe_control_plane import (
    ControlPlaneKernel, DISPOSABLE_SENTINEL_CONTENT, DISPOSABLE_SENTINEL_NAME,
    DISPOSABLE_WRITE_TOOL, FixedStableCoreEvaluator, InvalidTransition,
    LedgerCorruption, LedgerIOError, PolicyEvaluation, load_fixed_stable_core_registry,
)
from mainframe_control_plane.memory import (
    PROJECT_MEMORY_CHECKPOINT, PROJECT_MEMORY_ENSURE, PROJECT_MEMORY_GET,
    PROJECT_MEMORY_PROGRESS, PROJECT_MEMORY_SESSION, ProjectMemoryControlPlane,
)
from mainframe_control_plane.memory_executor import FixedProjectMemorySubprocessExecutor
import mainframe_control_plane.kernel as kernel_module
import mainframe_control_plane.memory_executor as memory_executor_module


class ReliabilityRegressionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mainframe-reliability-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        self.ledger = self.root / "ledger.jsonl"

    def test_ledger_rejects_nonprivate_parent_and_symlink_ancestors(self):
        public = self.root / "public"
        public.mkdir(mode=0o777)
        public.chmod(0o777)
        real = self.root / "real"
        real.mkdir(mode=0o700)
        (real / "inner").mkdir(mode=0o700)
        (self.root / "alias").symlink_to(real, target_is_directory=True)
        for path in (public / "ledger", self.root / "alias" / "inner" / "ledger"):
            with self.subTest(path=path), self.assertRaises(LedgerCorruption):
                ControlPlaneKernel(path).create_run(
                    run_id="r", actor="a", workspace=str(self.workspace), policy="p"
                )
        self.assertFalse((public / "ledger").exists())
        self.assertFalse((real / "inner" / "ledger").exists())

    def test_cap_rejection_does_not_append_or_corrupt_replay(self):
        kernel = ControlPlaneKernel(self.ledger)
        kernel.create_run(run_id="r1", actor="a", workspace=str(self.workspace), policy="p")
        before = self.ledger.read_bytes()
        with mock.patch.object(kernel_module, "MAX_LEDGER_BYTES", len(before) + 10):
            with self.assertRaises(LedgerIOError):
                kernel.create_run(run_id="r2", actor="a", workspace=str(self.workspace), policy="p")
            self.assertEqual(self.ledger.read_bytes(), before)
            self.assertEqual(set(kernel.snapshot().runs), {"r1"})

    def test_approval_cannot_outlive_call_deadline(self):
        now = [datetime.now(timezone.utc)]
        kernel = ControlPlaneKernel(
            self.ledger, clock=lambda: now[0],
            evaluator=lambda request: PolicyEvaluation("approval_required", "reviewer", "reviewed"),
        )
        kernel.create_run(run_id="r", actor="a", workspace=str(self.workspace), policy="p")
        kernel.transition_run("r", "active")
        (self.workspace / DISPOSABLE_SENTINEL_NAME).write_bytes(DISPOSABLE_SENTINEL_CONTENT)
        for index, tool in enumerate((DISPOSABLE_WRITE_TOOL, "filesystem.write")):
            call = kernel.create_tool_call(
                call_id="c" + str(index), run_id="r", tool=tool, effect="mutating",
                tool_input={"path": "output", "content": "approved"},
                timeout_at=now[0] + timedelta(seconds=1),
            )
            binding = dict(call_id=call.call_id, tool=call.tool, input_digest=call.input_digest,
                           actor=call.actor, workspace=call.workspace, policy=call.policy)
            kernel.evaluate_policy_decision(decision_id="d" + str(index), timeout_at=call.timeout_at, **binding)
            kernel.grant_approval(approval_id="a" + str(index), approver="human",
                                  expires_at=now[0] + timedelta(minutes=5), **binding)
        now[0] += timedelta(seconds=2)
        with self.assertRaisesRegex(InvalidTransition, "deadline"):
            kernel.execute_disposable_write("c0", approval_id="a0", actor="a", workspace=str(self.workspace), policy="p")
        with self.assertRaisesRegex(InvalidTransition, "deadline"):
            kernel.consume_approval("a1", call_id="c1", actor="a", workspace=str(self.workspace), policy="p")
        self.assertFalse((self.workspace / "output").exists())
        self.assertTrue(all(item.state == "granted" for item in kernel.snapshot().approvals.values()))

    def test_expired_ready_public_retry_is_terminal_and_idempotent(self):
        registry = load_fixed_stable_core_registry()
        kernel = ControlPlaneKernel(
            self.ledger, clock=lambda: datetime.now(timezone.utc) - timedelta(minutes=1),
            evaluator=FixedStableCoreEvaluator(registry), stable_core_registry=registry,
        )
        tool = "mf:std:pure-string:to_upper"
        value = {"value": "expired"}
        actor = "local-uid:{}:mainframe-cli".format(os.geteuid())
        request = kernel.reserve_canonical_request(
            client_correlation_id="expired-ready", canonical_id=tool, tool_input=value,
            actor=actor, workspace=str(self.workspace), policy="stable-core-v1",
        )
        kernel.create_run(run_id=request.run_id, actor=actor, workspace=str(self.workspace), policy=request.policy)
        kernel.transition_run(request.run_id, "active")
        call = kernel.create_canonical_tool_call(call_id=request.call_id, run_id=request.run_id,
                    canonical_id=tool, tool_input=value, client_correlation_id=request.client_correlation_id)
        kernel.evaluate_policy_decision(decision_id=request.decision_id, call_id=call.call_id,
                    tool=call.tool, input_digest=call.input_digest, actor=actor, workspace=str(self.workspace),
                    policy=call.policy, timeout_at=call.timeout_at, tool_input=value)
        for _ in range(2):
            result = subprocess.run(
                [str(PROJECT_ROOT / "control_plane" / "mainframe-control-plane"), "--ledger", str(self.ledger),
                 "canonical-invoke", "--canonical-id", tool, "--input-json", "-",
                 "--client-correlation-id", "expired-ready"],
                input=json.dumps(value), text=True, capture_output=True, cwd=self.workspace, timeout=15,
            )
            payload = json.loads(result.stdout)
            self.assertEqual(payload["result"]["outcome"], "timed_out", result.stdout + result.stderr)
        snapshot = ControlPlaneKernel(self.ledger).snapshot()
        self.assertEqual(snapshot.tool_calls[call.call_id].state, "timed_out")
        self.assertEqual(snapshot.runs[request.run_id].state, "failed")
        self.assertEqual(len(snapshot.evidence), 1)

    def test_actual_memory_adapter_preserves_newlines_and_cleans_group_once(self):
        executor = FixedProjectMemorySubprocessExecutor(ledger_path=self.ledger)
        control = ProjectMemoryControlPlane(self.ledger, executor=executor)
        common = dict(actor="test", workspace=str(self.workspace))
        ensured = control.invoke(client_correlation_id="ensure", tool=PROJECT_MEMORY_ENSURE, tool_input={}, **common)
        self.assertEqual(ensured.outcome, "succeeded")
        value = "line\n\n"
        checkpoint = control.invoke(client_correlation_id="checkpoint", tool=PROJECT_MEMORY_CHECKPOINT,
            tool_input=dict(expected_session_id=ensured.session_id, key="multiline", value=value,
                            importance="normal", tags=[], ttl_seconds=0), **common)
        self.assertEqual(checkpoint.outcome, "succeeded")
        self.assertEqual(checkpoint.receipt["value_sha256"], hashlib.sha256(value.encode()).hexdigest())
        for key, default, expected in (("multiline", "", value), ("absent", "fallback\n\n", "fallback\n\n")):
            got = control.invoke(client_correlation_id="get-" + key, tool=PROJECT_MEMORY_GET,
                                 tool_input=dict(key=key, default=default), **common)
            self.assertEqual(got.outcome, "succeeded")
            self.assertEqual(got.transient, expected.encode())
        progress = control.invoke(client_correlation_id="progress", tool=PROJECT_MEMORY_PROGRESS,
            tool_input=dict(expected_session_id=ensured.session_id, task="review", current=1, total=2, status=value), **common)
        self.assertEqual(progress.outcome, "succeeded")
        progress_files = list(self.root.rglob("progress.jsonl"))
        self.assertTrue(progress_files)
        self.assertEqual(json.loads(progress_files[0].read_text().splitlines()[-1])["status"], value)
        with mock.patch.object(memory_executor_module, "_terminate_process_group",
                               wraps=memory_executor_module._terminate_process_group) as cleanup:
            result = control.invoke(client_correlation_id="cleanup", tool=PROJECT_MEMORY_SESSION, tool_input={}, **common)
        self.assertEqual(result.outcome, "succeeded")
        self.assertEqual(cleanup.call_count, 1)

    def test_delayed_checkpoint_uses_reserved_absolute_expiry(self):
        now = [datetime.now(timezone.utc)]
        executor = FixedProjectMemorySubprocessExecutor(ledger_path=self.ledger)
        control = ProjectMemoryControlPlane(self.ledger, executor=executor, clock=lambda: now[0])
        common = dict(actor="test", workspace=str(self.workspace))
        ensured = control.invoke(client_correlation_id="ensure", tool=PROJECT_MEMORY_ENSURE, tool_input={}, **common)
        body = dict(expected_session_id=ensured.session_id, key="short-lived", value="temporary",
                    importance="normal", tags=[], ttl_seconds=60)
        request = control.reserve(client_correlation_id="reserved", tool=PROJECT_MEMORY_CHECKPOINT, tool_input=body, **common)
        now[0] += timedelta(seconds=15)
        checkpoint = control.invoke(client_correlation_id="reserved", tool=PROJECT_MEMORY_CHECKPOINT, tool_input=body, **common)
        self.assertEqual(checkpoint.outcome, "succeeded")
        sidecar = json.loads(next(self.root.rglob("short-lived.json")).read_text())
        expires = datetime.fromisoformat(request.reservation_binding["expires_at"].replace("Z", "+00:00"))
        self.assertEqual(sidecar["retention"]["expires_at_epoch"], int(expires.timestamp()))
        control.reserve(client_correlation_id="expired", tool=PROJECT_MEMORY_CHECKPOINT, tool_input={**body, "key": "expired"}, **common)
        now[0] += timedelta(seconds=61)
        expired = control.invoke(client_correlation_id="expired", tool=PROJECT_MEMORY_CHECKPOINT,
                                 tool_input={**body, "key": "expired"}, **common)
        self.assertEqual(expired.outcome, "failed")
        self.assertFalse(any(self.root.rglob("expired.json")))


if __name__ == "__main__":
    unittest.main()

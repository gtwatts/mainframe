from __future__ import annotations

from datetime import datetime, timedelta, timezone
import hashlib
import json
import multiprocessing
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "control_plane"))

from mainframe_control_plane import (  # noqa: E402
    AlreadyExists,
    ApprovalConsumed,
    ApprovalExpired,
    BindingMismatch,
    ControlPlaneKernel,
    DISPOSABLE_SENTINEL_CONTENT,
    DISPOSABLE_SENTINEL_NAME,
    DISPOSABLE_WRITE_TOOL,
    ExecutionDenied,
    InvalidTransition,
    LedgerCorruption,
    LedgerIOError,
    MAX_DISPOSABLE_WRITE_BYTES,
    PolicyEvaluation,
    READ_ONLY_TRACER_TOOL,
)


class MutableClock:
    def __init__(self) -> None:
        self.value = datetime(2026, 8, 20, 12, 0, tzinfo=timezone.utc)

    def __call__(self) -> datetime:
        return self.value


def consume_in_process(ledger: str, workspace: str, queue) -> None:
    clock = MutableClock()
    kernel = ControlPlaneKernel(ledger, clock=clock)
    try:
        kernel.consume_approval(
            "approval-race",
            call_id="call-race",
            actor="agent:codex",
            workspace=workspace,
            policy="local-reviewed-v1",
        )
    except Exception as exc:  # returned to the parent as a stable typed result
        queue.put(getattr(exc, "code", type(exc).__name__))
    else:
        queue.put("consumed")


class KernelTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(self.temp_dir.name)
        self.ledger = self.root / "control-plane.jsonl"
        self.workspace = str(self.root / "workspace")
        Path(self.workspace).mkdir()
        self.clock = MutableClock()
        self.outcomes = {}

        def evaluator(request):
            return PolicyEvaluation(
                self.outcomes[request.call_id],
                "policy-engine:unit-test",
                "reviewed unit-test decision",
            )

        self.kernel = ControlPlaneKernel(
            self.ledger, clock=self.clock, evaluator=evaluator
        )

    def create_active_run(self, run_id: str = "run-1") -> None:
        run = self.kernel.create_run(
            run_id=run_id,
            actor="agent:codex",
            workspace=self.workspace,
            policy="local-reviewed-v1",
        )
        self.assertEqual(run.state, "created")
        run = self.kernel.transition_run(run_id, "active")
        self.assertEqual(run.state, "active")

    def create_mutating_call(self, call_id: str = "call-write"):
        return self.kernel.create_tool_call(
            call_id=call_id,
            run_id="run-1",
            tool="filesystem.write",
            tool_input={"path": "notes.txt", "content": "reviewed"},
            effect="mutating",
        )

    def decide(self, call, outcome: str):
        self.outcomes[call.call_id] = outcome
        return self.kernel.evaluate_policy_decision(
            decision_id="decision-{}".format(call.call_id),
            call_id=call.call_id,
            tool=call.tool,
            input_digest=call.input_digest,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
            timeout_at=call.timeout_at,
        )

    def test_run_and_tool_call_state_transitions_are_explicit(self) -> None:
        self.kernel.create_run(
            run_id="run-1",
            actor="agent:codex",
            workspace=self.workspace,
            policy="local-reviewed-v1",
        )

        with self.assertRaises(InvalidTransition):
            self.kernel.create_tool_call(
                call_id="call-early",
                run_id="run-1",
                tool=READ_ONLY_TRACER_TOOL,
                tool_input={"message": "too early"},
                effect="read_only",
            )

        self.clock.value += timedelta(microseconds=1)
        self.kernel.transition_run("run-1", "active")
        with self.assertRaises(InvalidTransition):
            self.kernel.transition_run("run-1", "active")

        call = self.kernel.create_tool_call(
            call_id="call-trace",
            run_id="run-1",
            tool=READ_ONLY_TRACER_TOOL,
            tool_input={"z": 1, "a": [2, 3]},
            effect="read_only",
        )
        same_input = self.kernel.create_tool_call(
            call_id="call-trace-2",
            run_id="run-1",
            tool=READ_ONLY_TRACER_TOOL,
            tool_input={"a": [2, 3], "z": 1},
            effect="read_only",
        )
        self.assertEqual(call.state, "pending")
        self.assertEqual(call.input_digest, same_input.input_digest)

        with self.assertRaises(InvalidTransition):
            self.kernel.transition_run("run-1", "cancelled")

        before = self.ledger.read_bytes()
        with self.assertRaises(ExecutionDenied):
            self.kernel.request_approval("call-trace")
        self.assertEqual(self.ledger.read_bytes(), before)

    def test_approval_is_exact_expiring_and_consumed_once_across_restart(self) -> None:
        self.create_active_run()
        call = self.create_mutating_call()
        self.decide(call, "approval_required")
        call = self.kernel.snapshot().tool_calls[call.call_id]
        self.assertEqual(call.state, "awaiting_approval")
        expiry = self.clock.value + timedelta(minutes=5)

        before = self.ledger.read_bytes()
        with self.assertRaises(BindingMismatch):
            self.kernel.grant_approval(
                approval_id="approval-wrong",
                call_id=call.call_id,
                tool=call.tool,
                input_digest="0" * 64,
                actor=call.actor,
                workspace=call.workspace,
                policy=call.policy,
                approver="human:reviewer",
                expires_at=expiry,
            )
        self.assertEqual(self.ledger.read_bytes(), before)

        approval = self.kernel.grant_approval(
            approval_id="approval-1",
            call_id=call.call_id,
            tool=call.tool,
            input_digest=call.input_digest,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
            approver="human:reviewer",
            expires_at=expiry,
        )
        self.assertEqual(approval.state, "granted")
        self.assertEqual(approval.approver, "human:reviewer")
        with self.assertRaises(AlreadyExists):
            self.kernel.grant_approval(
                approval_id="approval-duplicate",
                call_id=call.call_id,
                tool=call.tool,
                input_digest=call.input_digest,
                actor=call.actor,
                workspace=call.workspace,
                policy=call.policy,
                approver="human:reviewer",
                expires_at=expiry,
            )
        with self.assertRaises(BindingMismatch):
            self.kernel.grant_approval(
                approval_id="approval-self-approved",
                call_id=call.call_id,
                tool=call.tool,
                input_digest=call.input_digest,
                actor=call.actor,
                workspace=call.workspace,
                policy=call.policy,
                approver=call.actor,
                expires_at=expiry,
            )

        with self.assertRaises(BindingMismatch):
            self.kernel.consume_approval(
                approval.approval_id,
                call_id=call.call_id,
                actor="agent:other",
                workspace=call.workspace,
                policy=call.policy,
            )

        consumed = self.kernel.consume_approval(
            approval.approval_id,
            call_id=call.call_id,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
        )
        self.assertEqual(consumed.state, "consumed")
        self.assertEqual(
            self.kernel.snapshot().tool_calls[call.call_id].state, "authorized"
        )

        restarted = ControlPlaneKernel(self.ledger, clock=self.clock)
        with self.assertRaises(ApprovalConsumed):
            restarted.consume_approval(
                approval.approval_id,
                call_id=call.call_id,
                actor=call.actor,
                workspace=call.workspace,
                policy=call.policy,
            )

        second = self.create_mutating_call("call-expiring")
        self.decide(second, "approval_required")
        expiring = self.kernel.grant_approval(
            approval_id="approval-expiring",
            call_id=second.call_id,
            tool=second.tool,
            input_digest=second.input_digest,
            actor=second.actor,
            workspace=second.workspace,
            policy=second.policy,
            approver="human:reviewer",
            expires_at=self.clock.value + timedelta(seconds=1),
        )
        self.clock.value += timedelta(seconds=2)
        with self.assertRaises(ApprovalExpired):
            self.kernel.consume_approval(
                expiring.approval_id,
                call_id=second.call_id,
                actor=second.actor,
                workspace=second.workspace,
                policy=second.policy,
            )

        boundary = self.create_mutating_call("call-expiry-boundary")
        self.decide(boundary, "approval_required")
        expires_at = self.clock.value + timedelta(seconds=1)
        approval_at_boundary = self.kernel.grant_approval(
            approval_id="approval-expiry-boundary",
            call_id=boundary.call_id,
            tool=boundary.tool,
            input_digest=boundary.input_digest,
            actor=boundary.actor,
            workspace=boundary.workspace,
            policy=boundary.policy,
            approver="human:reviewer",
            expires_at=expires_at,
        )
        self.clock.value = expires_at
        with self.assertRaises(ApprovalExpired):
            self.kernel.consume_approval(
                approval_at_boundary.approval_id,
                call_id=boundary.call_id,
                actor=boundary.actor,
                workspace=boundary.workspace,
                policy=boundary.policy,
            )

    def test_only_reviewed_read_only_tracer_executes_via_injected_executor(self) -> None:
        self.create_active_run()
        call = self.kernel.create_tool_call(
            call_id="call-trace",
            run_id="run-1",
            tool=READ_ONLY_TRACER_TOOL,
            tool_input={"message": "observe only"},
            effect="read_only",
        )
        observed = []

        self.decide(call, "allow")

        def executor(tool, tool_input):
            observed.append((tool, tool_input))
            return {"observed": tool_input["message"]}

        evidence = self.kernel.execute_read_only(call.call_id, executor)
        self.assertEqual(observed, [(READ_ONLY_TRACER_TOOL, {"message": "observe only"})])
        self.assertEqual(evidence.outcome, "succeeded")
        self.assertEqual(evidence.body, {"result": {"observed": "observe only"}})

        restarted = ControlPlaneKernel(self.ledger, clock=self.clock)
        snapshot = restarted.snapshot()
        self.assertEqual(snapshot.tool_calls[call.call_id].state, "succeeded")
        self.assertEqual(snapshot.evidence[evidence.evidence_id], evidence)

        mutating = self.create_mutating_call("call-never-execute")
        self.decide(mutating, "approval_required")
        approval = self.kernel.grant_approval(
            approval_id="approval-never-execute",
            call_id=mutating.call_id,
            tool=mutating.tool,
            input_digest=mutating.input_digest,
            actor=mutating.actor,
            workspace=mutating.workspace,
            policy=mutating.policy,
            approver="human:reviewer",
            expires_at=self.clock.value + timedelta(minutes=1),
        )
        self.kernel.consume_approval(
            approval.approval_id,
            call_id=mutating.call_id,
            actor=mutating.actor,
            workspace=mutating.workspace,
            policy=mutating.policy,
        )
        with self.assertRaises(ExecutionDenied):
            self.kernel.execute_read_only(mutating.call_id, executor)
        self.assertEqual(len(observed), 1)

    def test_disposable_write_is_approval_bound_atomic_and_replayable(self) -> None:
        self.create_active_run()
        workspace = Path(self.kernel.snapshot().runs["run-1"].workspace)
        workspace.mkdir(parents=True, exist_ok=True)
        (workspace / DISPOSABLE_SENTINEL_NAME).write_bytes(DISPOSABLE_SENTINEL_CONTENT)
        (workspace / "nested").mkdir()
        call = self.kernel.create_tool_call(
            call_id="call-disposable-write",
            run_id="run-1",
            tool=DISPOSABLE_WRITE_TOOL,
            tool_input={"path": "nested/result.txt", "content": "approved payload"},
            effect="mutating",
        )
        self.decide(call, "approval_required")
        approval = self.kernel.grant_approval(
            approval_id="approval-disposable-write",
            call_id=call.call_id,
            tool=call.tool,
            input_digest=call.input_digest,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
            approver="human:reviewer",
            expires_at=self.clock.value + timedelta(minutes=1),
        )

        with self.assertRaises(ExecutionDenied):
            self.kernel.consume_approval(
                approval.approval_id,
                call_id=call.call_id,
                actor=call.actor,
                workspace=call.workspace,
                policy=call.policy,
            )
        self.assertEqual(
            self.kernel.snapshot().approvals[approval.approval_id].state, "granted"
        )

        evidence = self.kernel.execute_disposable_write(
            call.call_id,
            approval_id=approval.approval_id,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
        )
        target = workspace / "nested" / "result.txt"
        self.assertEqual(target.read_text(encoding="utf-8"), "approved payload")
        self.assertEqual(evidence.outcome, "succeeded")
        self.assertEqual(evidence.call_id, call.call_id)
        self.assertEqual(evidence.approval_id, approval.approval_id)
        self.assertEqual(evidence.input_digest, call.input_digest)
        self.assertEqual(evidence.workspace, call.workspace)
        self.assertEqual(evidence.approver, "human:reviewer")
        self.assertEqual(evidence.body["receipt"]["relative_path"], "nested/result.txt")
        self.assertEqual(evidence.body["receipt"]["bytes_written"], 16)
        self.assertEqual(evidence.body["receipt"]["call_id"], call.call_id)
        self.assertEqual(
            evidence.body["receipt"]["approval_id"], approval.approval_id
        )
        self.assertEqual(evidence.body["receipt"]["input_digest"], call.input_digest)
        self.assertEqual(evidence.body["receipt"]["workspace"], call.workspace)
        consumed_event = next(
            event
            for event in map(json.loads, self.ledger.read_text().splitlines())
            if event["kind"] == "approval" and event["action"] == "consumed"
        )
        self.assertEqual(consumed_event["payload"]["approver"], "human:reviewer")
        self.assertEqual(target.stat().st_mode & 0o777, 0o600)

        restarted = ControlPlaneKernel(self.ledger, clock=self.clock)
        snapshot = restarted.snapshot()
        self.assertEqual(snapshot.approvals[approval.approval_id].state, "consumed")
        self.assertEqual(snapshot.tool_calls[call.call_id].state, "succeeded")
        self.assertEqual(snapshot.evidence[evidence.evidence_id], evidence)
        with self.assertRaises(ApprovalConsumed):
            restarted.execute_disposable_write(
                call.call_id,
                approval_id=approval.approval_id,
                actor=call.actor,
                workspace=call.workspace,
                policy=call.policy,
            )

    def test_disposable_write_rejects_paths_content_sentinel_and_other_tools(self) -> None:
        self.create_active_run()
        run = self.kernel.snapshot().runs["run-1"]
        workspace = Path(run.workspace)
        workspace.mkdir(parents=True, exist_ok=True)

        invalid_inputs = (
            {"path": "/tmp/absolute", "content": "x"},
            {"path": "../escape", "content": "x"},
            {"path": "nested/../../escape", "content": "x"},
            {"path": DISPOSABLE_SENTINEL_NAME, "content": "erase marker"},
            {"path": "too-large", "content": "x" * (MAX_DISPOSABLE_WRITE_BYTES + 1)},
            {
                "path": "too-large-utf8",
                "content": "é" * ((MAX_DISPOSABLE_WRITE_BYTES // 2) + 1),
            },
            {"path": "missing-content"},
        )
        for index, tool_input in enumerate(invalid_inputs):
            with self.assertRaises(ExecutionDenied):
                self.kernel.create_tool_call(
                    call_id="call-invalid-{}".format(index),
                    run_id="run-1",
                    tool=DISPOSABLE_WRITE_TOOL,
                    tool_input=tool_input,
                    effect="mutating",
                )

        outside = self.root / "outside"
        outside.mkdir()
        (workspace / DISPOSABLE_SENTINEL_NAME).write_text("wrong\n", encoding="utf-8")
        (workspace / "link").symlink_to(outside, target_is_directory=True)
        call = self.kernel.create_tool_call(
            call_id="call-symlink",
            run_id="run-1",
            tool=DISPOSABLE_WRITE_TOOL,
            tool_input={"path": "link/escaped.txt", "content": "blocked"},
            effect="mutating",
        )
        self.decide(call, "approval_required")
        approval = self.kernel.grant_approval(
            approval_id="approval-symlink",
            call_id=call.call_id,
            tool=call.tool,
            input_digest=call.input_digest,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
            approver="human:reviewer",
            expires_at=self.clock.value + timedelta(minutes=1),
        )
        with self.assertRaises(ExecutionDenied):
            self.kernel.execute_disposable_write(
                call.call_id,
                approval_id=approval.approval_id,
                actor=call.actor,
                workspace=call.workspace,
                policy=call.policy,
            )
        self.assertFalse((outside / "escaped.txt").exists())
        snapshot = self.kernel.snapshot()
        self.assertEqual(snapshot.approvals[approval.approval_id].state, "granted")
        self.assertEqual(snapshot.tool_calls[call.call_id].state, "awaiting_approval")

        (workspace / DISPOSABLE_SENTINEL_NAME).write_bytes(DISPOSABLE_SENTINEL_CONTENT)
        with self.assertRaises(ExecutionDenied):
            self.kernel.execute_disposable_write(
                call.call_id,
                approval_id=approval.approval_id,
                actor=call.actor,
                workspace=call.workspace,
                policy=call.policy,
            )
        self.assertFalse((outside / "escaped.txt").exists())
        snapshot = self.kernel.snapshot()
        self.assertEqual(snapshot.approvals[approval.approval_id].state, "granted")

        other = self.kernel.create_tool_call(
            call_id="call-other-tool",
            run_id="run-1",
            tool="filesystem.write",
            tool_input={"path": "other.txt", "content": "blocked"},
            effect="mutating",
        )
        self.decide(other, "approval_required")
        other_approval = self.kernel.grant_approval(
            approval_id="approval-other-tool",
            call_id=other.call_id,
            tool=other.tool,
            input_digest=other.input_digest,
            actor=other.actor,
            workspace=other.workspace,
            policy=other.policy,
            approver="human:reviewer",
            expires_at=self.clock.value + timedelta(minutes=1),
        )
        with self.assertRaises(ExecutionDenied):
            self.kernel.execute_disposable_write(
                other.call_id,
                approval_id=other_approval.approval_id,
                actor=other.actor,
                workspace=other.workspace,
                policy=other.policy,
            )
        self.assertFalse((workspace / "other.txt").exists())

    def test_disposable_write_crash_consumes_approval_and_cannot_retry(self) -> None:
        self.create_active_run()
        run = self.kernel.snapshot().runs["run-1"]
        workspace = Path(run.workspace)
        workspace.mkdir(parents=True, exist_ok=True)
        (workspace / DISPOSABLE_SENTINEL_NAME).write_bytes(DISPOSABLE_SENTINEL_CONTENT)
        call = self.kernel.create_tool_call(
            call_id="call-crash",
            run_id="run-1",
            tool=DISPOSABLE_WRITE_TOOL,
            tool_input={"path": "never-written.txt", "content": "blocked by crash"},
            effect="mutating",
        )
        self.decide(call, "approval_required")
        approval = self.kernel.grant_approval(
            approval_id="approval-crash",
            call_id=call.call_id,
            tool=call.tool,
            input_digest=call.input_digest,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
            approver="human:reviewer",
            expires_at=self.clock.value + timedelta(minutes=1),
        )

        with mock.patch(
            "mainframe_control_plane.kernel._atomic_disposable_replace",
            side_effect=SystemExit("simulated crash"),
        ):
            with self.assertRaises(SystemExit):
                self.kernel.execute_disposable_write(
                    call.call_id,
                    approval_id=approval.approval_id,
                    actor=call.actor,
                    workspace=call.workspace,
                    policy=call.policy,
                )

        restarted = ControlPlaneKernel(self.ledger, clock=self.clock)
        snapshot = restarted.snapshot()
        self.assertEqual(snapshot.approvals[approval.approval_id].state, "consumed")
        self.assertEqual(snapshot.tool_calls[call.call_id].state, "running")
        self.assertFalse((workspace / "never-written.txt").exists())
        with self.assertRaises(ApprovalConsumed):
            restarted.execute_disposable_write(
                call.call_id,
                approval_id=approval.approval_id,
                actor=call.actor,
                workspace=call.workspace,
                policy=call.policy,
            )

    def test_incomplete_final_frame_is_repaired_from_verified_prefix(self) -> None:
        self.create_active_run()
        valid = self.ledger.read_bytes()
        with self.ledger.open("ab") as stream:
            stream.write(b'{"truncated":')

        restarted = ControlPlaneKernel(self.ledger, clock=self.clock)
        self.assertEqual(restarted.snapshot().event_count, 2)
        self.assertEqual(self.ledger.read_bytes(), valid)
        call = restarted.create_tool_call(
            call_id="call-after-repair",
            run_id="run-1",
            tool=READ_ONLY_TRACER_TOOL,
            tool_input={"message": "safe append"},
            effect="read_only",
        )
        self.assertEqual(call.state, "pending")

    def test_partial_append_fault_repairs_only_uncommitted_final_frame(self) -> None:
        self.create_active_run()
        valid = self.ledger.read_bytes()
        real_write = __import__("os").write
        calls = 0

        def partial_then_fail(fd, content):
            nonlocal calls
            calls += 1
            if calls == 1:
                return real_write(fd, content[:17])
            raise OSError("injected append failure")

        with mock.patch(
            "mainframe_control_plane.kernel.os.write",
            side_effect=partial_then_fail,
        ):
            with self.assertRaises(LedgerIOError):
                self.kernel.create_tool_call(
                    call_id="call-partial",
                    run_id="run-1",
                    tool=READ_ONLY_TRACER_TOOL,
                    tool_input={"message": "never committed"},
                    effect="read_only",
                )
        restarted = ControlPlaneKernel(self.ledger, clock=self.clock)
        self.assertEqual(restarted.snapshot().event_count, 2)
        self.assertEqual(self.ledger.read_bytes(), valid)
        self.assertNotIn("call-partial", restarted.snapshot().tool_calls)

    def test_non_integer_schema_is_corruption_even_with_a_valid_digest(self) -> None:
        self.kernel.create_run(
            run_id="run-1",
            actor="agent:codex",
            workspace=self.workspace,
            policy="local-reviewed-v1",
        )
        event = json.loads(self.ledger.read_text(encoding="utf-8"))
        event["schema_version"] = True
        unsigned = dict(event)
        unsigned.pop("digest")
        canonical = json.dumps(
            unsigned,
            allow_nan=False,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
        event["digest"] = hashlib.sha256(canonical).hexdigest()
        self.ledger.write_text(
            json.dumps(event, separators=(",", ":"), sort_keys=True) + "\n",
            encoding="utf-8",
        )

        with self.assertRaises(LedgerCorruption):
            ControlPlaneKernel(self.ledger, clock=self.clock).snapshot()

    def test_concurrent_consumers_cannot_reuse_an_approval(self) -> None:
        self.create_active_run()
        call = self.create_mutating_call("call-race")
        self.decide(call, "approval_required")
        self.kernel.grant_approval(
            approval_id="approval-race",
            call_id=call.call_id,
            tool=call.tool,
            input_digest=call.input_digest,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
            approver="human:reviewer",
            expires_at=self.clock.value + timedelta(minutes=1),
        )

        context = multiprocessing.get_context("spawn")
        queue = context.Queue()
        workers = [
            context.Process(
                target=consume_in_process,
                args=(str(self.ledger), self.workspace, queue),
            )
            for _ in range(2)
        ]
        for worker in workers:
            worker.start()
        for worker in workers:
            worker.join(10)
            self.assertEqual(worker.exitcode, 0)
        results = sorted(queue.get(timeout=2) for _ in workers)
        self.assertEqual(results, ["approval_consumed", "consumed"])


if __name__ == "__main__":
    unittest.main()

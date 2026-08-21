from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
import tempfile
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "control_plane"))

from mainframe_control_plane import (  # noqa: E402
    BindingMismatch,
    ControlPlaneKernel,
    ExecutionDenied,
    InvalidTransition,
    PolicyEvaluation,
    READ_ONLY_TRACER_TOOL,
)


class MutableClock:
    def __init__(self) -> None:
        self.value = datetime(2026, 8, 20, 12, 0, tzinfo=timezone.utc)

    def __call__(self) -> datetime:
        return self.value


class PolicyLifecycleTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(self.temp_dir.name)
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        self.ledger = self.root / "control-plane.jsonl"
        self.clock = MutableClock()
        self.outcomes = {}

        def evaluator(request):
            return PolicyEvaluation(
                self.outcomes[request.call_id],
                "policy-engine:local-v1",
                "unit-test decision",
            )

        self.evaluator = evaluator
        self.kernel = ControlPlaneKernel(
            self.ledger, clock=self.clock, evaluator=self.evaluator
        )
        self.kernel.create_run(
            run_id="run-policy",
            actor="agent:codex",
            workspace=str(self.workspace),
            policy="local-reviewed-v1",
        )
        self.kernel.transition_run("run-policy", "active")

    def create_call(self, call_id: str, *, timeout_at=None):
        return self.kernel.create_tool_call(
            call_id=call_id,
            run_id="run-policy",
            tool=READ_ONLY_TRACER_TOOL,
            tool_input={"message": call_id},
            effect="read_only",
            timeout_at=timeout_at,
        )

    def decide(self, call, outcome: str, *, decision_id: str):
        self.outcomes[call.call_id] = outcome
        return self.kernel.evaluate_policy_decision(
            decision_id=decision_id,
            call_id=call.call_id,
            tool=call.tool,
            input_digest=call.input_digest,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
            timeout_at=call.timeout_at,
        )

    def bound_transition(self, method, call, reason: str):
        return method(
            call.call_id,
            tool=call.tool,
            input_digest=call.input_digest,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
            reason=reason,
        )

    def test_immutable_allow_decision_is_exact_and_required_for_execution(self) -> None:
        call = self.create_call("call-allow")
        before = self.ledger.read_bytes()
        with self.assertRaises(BindingMismatch):
            self.outcomes[call.call_id] = "allow"
            self.kernel.evaluate_policy_decision(
                decision_id="decision-wrong",
                call_id=call.call_id,
                tool=call.tool,
                input_digest="0" * 64,
                actor=call.actor,
                workspace=call.workspace,
                policy=call.policy,
                timeout_at=call.timeout_at,
            )
        self.assertEqual(self.ledger.read_bytes(), before)

        with self.assertRaises(ExecutionDenied):
            self.kernel.execute_read_only(call.call_id, lambda _tool, _input: {})

        decision = self.decide(call, "allow", decision_id="decision-allow")
        self.assertEqual(decision.outcome, "allow")
        self.assertEqual(decision.input_digest, call.input_digest)
        self.assertEqual(self.kernel.snapshot().tool_calls[call.call_id].state, "ready")

        before = self.ledger.read_bytes()
        with self.assertRaises(InvalidTransition):
            self.decide(call, "deny", decision_id="decision-stale")
        self.assertEqual(self.ledger.read_bytes(), before)

        restarted = ControlPlaneKernel(
            self.ledger, clock=self.clock, evaluator=self.evaluator
        )
        snapshot = restarted.snapshot()
        self.assertEqual(snapshot.policy_decisions[decision.decision_id], decision)
        self.assertEqual(snapshot.tool_calls[call.call_id].state, "ready")

    def test_deny_is_durable_terminal_and_cannot_execute_or_be_redecided(self) -> None:
        call = self.create_call("call-deny")
        decision = self.decide(call, "deny", decision_id="decision-deny")
        self.assertEqual(decision.outcome, "deny")
        self.assertEqual(self.kernel.snapshot().tool_calls[call.call_id].state, "denied")

        restarted = ControlPlaneKernel(
            self.ledger, clock=self.clock, evaluator=self.evaluator
        )
        before = self.ledger.read_bytes()
        with self.assertRaises(ExecutionDenied):
            restarted.execute_read_only(call.call_id, lambda _tool, _input: {})
        with self.assertRaises(InvalidTransition):
            self.outcomes[call.call_id] = "allow"
            restarted.evaluate_policy_decision(
                decision_id="decision-after-deny",
                call_id=call.call_id,
                tool=call.tool,
                input_digest=call.input_digest,
                actor=call.actor,
                workspace=call.workspace,
                policy=call.policy,
                timeout_at=call.timeout_at,
            )
        self.assertEqual(self.ledger.read_bytes(), before)

    def test_cancellation_is_bound_terminal_and_replayable(self) -> None:
        call = self.create_call("call-cancel")
        self.decide(call, "allow", decision_id="decision-cancel")
        before = self.ledger.read_bytes()
        with self.assertRaises(BindingMismatch):
            self.kernel.cancel_tool_call(
                call.call_id,
                tool=call.tool,
                input_digest=call.input_digest,
                actor="agent:other",
                workspace=call.workspace,
                policy=call.policy,
                reason="wrong actor",
            )
        self.assertEqual(self.ledger.read_bytes(), before)

        cancelled = self.bound_transition(
            self.kernel.cancel_tool_call, call, "caller cancelled"
        )
        self.assertEqual(cancelled.state, "cancelled")
        restarted = ControlPlaneKernel(
            self.ledger, clock=self.clock, evaluator=self.evaluator
        )
        self.assertEqual(restarted.snapshot().tool_calls[call.call_id].state, "cancelled")
        before = self.ledger.read_bytes()
        with self.assertRaises(InvalidTransition):
            self.bound_transition(restarted.cancel_tool_call, call, "stale retry")
        self.assertEqual(self.ledger.read_bytes(), before)

    def test_timeout_requires_bound_deadline_and_never_executes(self) -> None:
        deadline = self.clock.value + timedelta(seconds=5)
        call = self.create_call("call-timeout", timeout_at=deadline)
        self.decide(call, "allow", decision_id="decision-timeout")
        before = self.ledger.read_bytes()
        with self.assertRaises(InvalidTransition):
            self.bound_transition(self.kernel.timeout_tool_call, call, "too early")
        self.assertEqual(self.ledger.read_bytes(), before)

        self.clock.value = deadline
        timed_out = self.bound_transition(
            self.kernel.timeout_tool_call, call, "deadline elapsed"
        )
        self.assertEqual(timed_out.state, "timed_out")
        with self.assertRaises(InvalidTransition):
            self.kernel.execute_read_only(call.call_id, lambda _tool, _input: {})
        restarted = ControlPlaneKernel(
            self.ledger, clock=self.clock, evaluator=self.evaluator
        )
        self.assertEqual(restarted.snapshot().tool_calls[call.call_id].state, "timed_out")

        no_deadline = self.create_call("call-no-timeout")
        before = self.ledger.read_bytes()
        with self.assertRaises(InvalidTransition):
            self.bound_transition(
                self.kernel.timeout_tool_call, no_deadline, "no ambient timeout"
            )
        self.assertEqual(self.ledger.read_bytes(), before)

    def test_recovery_only_marks_a_running_call_interrupted(self) -> None:
        call = self.create_call("call-recover")
        self.decide(call, "allow", decision_id="decision-recover")
        with self.assertRaises(SystemExit):
            self.kernel.execute_read_only(
                call.call_id,
                lambda _tool, _input: (_ for _ in ()).throw(SystemExit("crash")),
            )

        restarted = ControlPlaneKernel(
            self.ledger, clock=self.clock, evaluator=self.evaluator
        )
        self.assertEqual(restarted.snapshot().tool_calls[call.call_id].state, "running")
        recovered = self.bound_transition(
            restarted.recover_tool_call, call, "process restart recovery"
        )
        self.assertEqual(recovered.state, "interrupted")
        with self.assertRaises(InvalidTransition):
            restarted.execute_read_only(call.call_id, lambda _tool, _input: {})

        pending = self.create_call("call-not-running")
        with self.assertRaises(InvalidTransition):
            self.bound_transition(
                self.kernel.recover_tool_call, pending, "must already be running"
            )

    def test_policy_outcome_must_match_effect(self) -> None:
        call = self.create_call("call-read-only-approval")
        with self.assertRaises(ExecutionDenied):
            self.decide(
                call,
                "approval_required",
                decision_id="decision-invalid-effect",
            )

    def test_evaluator_cannot_impersonate_the_caller_as_authority(self) -> None:
        call = self.create_call("call-self-authority")

        def self_authored(_request):
            return PolicyEvaluation("allow", call.actor, "self-authored allow")

        kernel = ControlPlaneKernel(
            self.ledger, clock=self.clock, evaluator=self_authored
        )
        before = self.ledger.read_bytes()
        with self.assertRaises(BindingMismatch):
            kernel.evaluate_policy_decision(
                decision_id="decision-self-authority",
                call_id=call.call_id,
                tool=call.tool,
                input_digest=call.input_digest,
                actor=call.actor,
                workspace=call.workspace,
                policy=call.policy,
                timeout_at=call.timeout_at,
            )
        self.assertEqual(self.ledger.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()

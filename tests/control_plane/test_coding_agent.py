from __future__ import annotations

from dataclasses import replace
from datetime import datetime, timedelta, timezone
import hashlib
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "control_plane"))

from mainframe_control_plane import (  # noqa: E402
    BindingMismatch,
    CODING_ATOMIC_EDIT,
    CODING_READ_FILE,
    CODING_RUN_BUILD,
    CODING_RUN_TEST,
    CODING_SEARCH_TEXT,
    CodingAgentControlPlane,
    ExecutionDenied,
    FixedActionResult,
    FixedCodingRegistry,
    FixedWorkspaceCodingExecutor,
)


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


class MutableClock:
    def __init__(self) -> None:
        self.value = datetime(2026, 8, 20, 12, 0, tzinfo=timezone.utc)

    def __call__(self) -> datetime:
        return self.value


class SimulatedCrash(BaseException):
    pass


class CodingAgentControlPlaneTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(self.temp_dir.name)
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        self.ledger = self.root / "state" / "coding.jsonl"
        self.clock = MutableClock()
        self.approval_requests = []

        def trusted_approver(request):
            self.approval_requests.append(request)
            return "reviewer:alice"

        self.trusted_approver = trusted_approver
        self.executor = FixedWorkspaceCodingExecutor()
        self.control = CodingAgentControlPlane(
            self.ledger,
            executor=self.executor,
            trusted_approver=self.trusted_approver,
            clock=self.clock,
        )

    def invoke(self, correlation: str, tool: str, tool_input):
        return self.control.invoke(
            client_correlation_id=correlation,
            tool=tool,
            tool_input=tool_input,
            actor="agent:codex",
            workspace=str(self.workspace),
        )

    def assert_private_values_absent(self, *values: str) -> None:
        ledger = self.ledger.read_text(encoding="utf-8")
        runtime = self.ledger.parent / ".mainframe-control-plane-runtime"
        runtime_bytes = b""
        if runtime.exists():
            for path in runtime.rglob("*"):
                if path.is_file() and not path.is_symlink():
                    runtime_bytes += path.read_bytes()
        for value in values:
            self.assertNotIn(value, ledger)
            self.assertNotIn(value.encode("utf-8"), runtime_bytes)

    def test_read_and_search_are_workspace_bound_and_metadata_only(self) -> None:
        source_secret = "SOURCE-SECRET-7d2f"
        query_secret = "SECRET-7d2f"
        (self.workspace / "src").mkdir()
        (self.workspace / "src" / "main.py").write_text(
            "before\n{}\nafter\n".format(source_secret), encoding="utf-8"
        )

        read = self.invoke(
            "coding-read-1", CODING_READ_FILE, {"path": "src/main.py"}
        )
        self.assertEqual(read.outcome, "succeeded")
        self.assertTrue(read.result_available)
        self.assertEqual(read.result.stdout.decode("utf-8"), "before\n{}\nafter\n".format(source_secret))
        self.assertEqual(read.receipt["stdout_sha256"], digest(read.result.stdout))

        search = self.invoke(
            "coding-search-1",
            CODING_SEARCH_TEXT,
            {"path": "src", "query": query_secret},
        )
        self.assertEqual(search.outcome, "succeeded")
        self.assertIn(source_secret.encode("utf-8"), search.result.stdout)
        self.assertNotIn("stdout", search.evidence_body)
        self.assertNotIn("stderr", search.evidence_body)
        self.assert_private_values_absent(source_secret, query_secret)

        replay = self.invoke(
            "coding-search-1",
            CODING_SEARCH_TEXT,
            {"path": "src", "query": query_secret},
        )
        self.assertFalse(replay.result_available)
        self.assertIsNone(replay.result)
        self.assertEqual(replay.evidence_id, search.evidence_id)
        self.assertEqual(replay.receipt, search.receipt)

        outside = self.root / "outside.txt"
        outside.write_text("outside-secret", encoding="utf-8")
        os.symlink(str(outside), str(self.workspace / "src" / "escape"))
        escaped = self.invoke(
            "coding-read-symlink", CODING_READ_FILE, {"path": "src/escape"}
        )
        self.assertEqual(escaped.outcome, "failed")
        self.assertFalse(escaped.result_available)
        self.assert_private_values_absent("outside-secret")

        before = self.ledger.read_bytes()
        with self.assertRaises(ExecutionDenied):
            self.invoke("coding-read-parent", CODING_READ_FILE, {"path": "../outside.txt"})
        with self.assertRaises(ExecutionDenied):
            self.invoke("coding-read-absolute", CODING_READ_FILE, {"path": str(outside)})
        self.assertEqual(self.ledger.read_bytes(), before)

    def test_atomic_edit_requires_exact_trusted_preimage_approval_and_is_one_time(self) -> None:
        target = self.workspace / "src.py"
        old = b"old-value\n"
        new_secret = "EDIT-SECRET-986a\n"
        target.write_bytes(old)
        request = {
            "path": "src.py",
            "expected_sha256": digest(old),
            "content": new_secret,
        }

        result = self.invoke("coding-edit-1", CODING_ATOMIC_EDIT, request)
        self.assertEqual(result.outcome, "succeeded")
        self.assertEqual(target.read_text(encoding="utf-8"), new_secret)
        self.assertEqual(len(self.approval_requests), 1)
        approval_request = self.approval_requests[0]
        self.assertEqual(approval_request.preimage_sha256, digest(old))
        self.assertEqual(approval_request.actor, "agent:codex")
        self.assertEqual(approval_request.policy, "coding-agent-v1")
        self.assertEqual(approval_request.tool, CODING_ATOMIC_EDIT)
        self.assertEqual(approval_request.input_digest, result.input_digest)
        self.assertEqual(result.receipt["preimage_sha256"], digest(old))
        self.assertEqual(result.receipt["postimage_sha256"], digest(new_secret.encode()))
        snapshot = self.control.snapshot()
        self.assertEqual(snapshot.approvals[result.approval_id].state, "consumed")
        self.assert_private_values_absent(new_secret)

        replay = self.invoke("coding-edit-1", CODING_ATOMIC_EDIT, request)
        self.assertEqual(replay.outcome, "succeeded")
        self.assertFalse(replay.result_available)
        self.assertEqual(len(self.approval_requests), 1)
        self.assertEqual(replay.run_id, result.run_id)
        self.assertEqual(replay.call_id, result.call_id)
        self.assertEqual(replay.evidence_id, result.evidence_id)

        with self.assertRaises(BindingMismatch):
            self.invoke(
                "coding-edit-1",
                CODING_ATOMIC_EDIT,
                {**request, "content": "forged-content\n"},
            )
        self.assertNotIn("forged-content", target.read_text(encoding="utf-8"))

    def test_edit_fails_closed_without_authority_or_with_stale_preimage(self) -> None:
        target = self.workspace / "stale.txt"
        target.write_text("current", encoding="utf-8")
        without_authority = CodingAgentControlPlane(
            self.root / "no-authority" / "ledger.jsonl",
            executor=FixedWorkspaceCodingExecutor(),
            clock=self.clock,
        )
        pending = without_authority.invoke(
            client_correlation_id="no-authority-edit",
            tool=CODING_ATOMIC_EDIT,
            tool_input={
                "path": "stale.txt",
                "expected_sha256": digest(b"current"),
                "content": "blocked",
            },
            actor="agent:codex",
            workspace=str(self.workspace),
        )
        self.assertEqual(pending.status, "awaiting_approval")
        self.assertIsNone(pending.outcome)
        self.assertFalse(pending.result_available)
        self.assertEqual(target.read_text(encoding="utf-8"), "current")

        stale = self.invoke(
            "stale-preimage-edit",
            CODING_ATOMIC_EDIT,
            {
                "path": "stale.txt",
                "expected_sha256": "0" * 64,
                "content": "must-not-write",
            },
        )
        self.assertEqual(stale.outcome, "failed")
        self.assertEqual(target.read_text(encoding="utf-8"), "current")
        self.assertEqual(
            self.control.snapshot().approvals[stale.approval_id].state, "consumed"
        )
        self.assert_private_values_absent("must-not-write")

        outside = self.root / "outside-edit.txt"
        outside.write_text("outside", encoding="utf-8")
        os.symlink(str(outside), str(self.workspace / "edit-link"))
        symbolic = self.invoke(
            "symbolic-edit",
            CODING_ATOMIC_EDIT,
            {
                "path": "edit-link",
                "expected_sha256": digest(b"outside"),
                "content": "SYMLINK-EDIT-SECRET",
            },
        )
        self.assertEqual(symbolic.outcome, "failed")
        self.assertEqual(outside.read_text(encoding="utf-8"), "outside")
        self.assert_private_values_absent("SYMLINK-EDIT-SECRET")

    def test_fixed_test_and_build_actions_accept_no_argv_and_validate_receipts(self) -> None:
        registry = FixedCodingRegistry()
        self.assertEqual(registry.contract(CODING_RUN_TEST).effect, "code_execution")
        self.assertEqual(registry.contract(CODING_RUN_BUILD).effect, "code_execution")
        observed = []
        action_secret = b"ACTION-OUTPUT-SECRET-c61d\n"

        def action_runner(tool, workspace_fd):
            observed.append((tool, os.fstat(workspace_fd).st_ino))
            return FixedActionResult(0, action_secret, b"", 7)

        executor = FixedWorkspaceCodingExecutor(action_runner=action_runner)
        control = CodingAgentControlPlane(
            self.root / "actions" / "ledger.jsonl",
            executor=executor,
            trusted_approver=self.trusted_approver,
            clock=self.clock,
        )
        test_result = control.invoke(
            client_correlation_id="fixed-test-1",
            tool=CODING_RUN_TEST,
            tool_input={},
            actor="agent:codex",
            workspace=str(self.workspace),
        )
        build_result = control.invoke(
            client_correlation_id="fixed-build-1",
            tool=CODING_RUN_BUILD,
            tool_input={},
            actor="agent:codex",
            workspace=str(self.workspace),
        )
        self.assertEqual(test_result.outcome, "succeeded")
        self.assertEqual(build_result.outcome, "succeeded")
        self.assertIsNotNone(test_result.approval_id)
        self.assertIsNotNone(build_result.approval_id)
        self.assertEqual(test_result.receipt["decision_id"], test_result.decision_id)
        self.assertEqual(test_result.receipt["evidence_id"], test_result.evidence_id)
        self.assertEqual(
            [request.tool for request in self.approval_requests],
            [CODING_RUN_TEST, CODING_RUN_BUILD],
        )
        self.assertEqual(
            [request.preimage_sha256 for request in self.approval_requests],
            [None, None],
        )
        self.assertEqual(test_result.result.stdout, action_secret)
        self.assertNotIn(
            action_secret,
            (self.root / "actions" / "ledger.jsonl").read_bytes(),
        )
        self.assertEqual(
            observed,
            [
                (CODING_RUN_TEST, self.workspace.stat().st_ino),
                (CODING_RUN_BUILD, self.workspace.stat().st_ino),
            ],
        )

        denied_runner_calls = []

        def denied_runner(tool, workspace_fd):
            denied_runner_calls.append((tool, workspace_fd))
            raise AssertionError("unapproved project code was executed")

        no_authority = CodingAgentControlPlane(
            self.root / "actions-no-authority" / "ledger.jsonl",
            executor=FixedWorkspaceCodingExecutor(action_runner=denied_runner),
            clock=self.clock,
        )
        pending = no_authority.invoke(
            client_correlation_id="fixed-test-no-authority",
            tool=CODING_RUN_TEST,
            tool_input={},
            actor="agent:codex",
            workspace=str(self.workspace),
        )
        self.assertEqual(pending.status, "awaiting_approval")
        self.assertIsNone(pending.outcome)
        self.assertFalse(pending.result_available)
        self.assertEqual(denied_runner_calls, [])
        pending_snapshot = no_authority.snapshot()
        self.assertEqual(
            pending_snapshot.tool_calls[pending.call_id].effect, "code_execution"
        )
        self.assertEqual(
            pending_snapshot.policy_decisions[pending.decision_id].outcome,
            "approval_required",
        )
        with self.assertRaises(ExecutionDenied):
            control.invoke(
                client_correlation_id="fixed-test-forged-argv",
                tool=CODING_RUN_TEST,
                tool_input={"argv": ["sh", "-c", "touch /tmp/owned"]},
                actor="agent:codex",
                workspace=str(self.workspace),
            )

        class TamperingExecutor:
            def __call__(self, request, tool_input):
                valid = executor(request, tool_input)
                receipt = dict(valid.receipt)
                receipt["call_id"] = "call-forged"
                receipt["raw_output"] = "RECEIPT-SECRET-2fa1"
                return replace(valid, receipt=receipt)

        tamper_control = CodingAgentControlPlane(
            self.root / "tamper" / "ledger.jsonl",
            executor=TamperingExecutor(),
            trusted_approver=self.trusted_approver,
            clock=self.clock,
        )
        tampered = tamper_control.invoke(
            client_correlation_id="tampered-receipt",
            tool=CODING_RUN_TEST,
            tool_input={},
            actor="agent:codex",
            workspace=str(self.workspace),
        )
        self.assertEqual(tampered.outcome, "failed")
        self.assertFalse(tampered.result_available)
        self.assertEqual(tampered.evidence_body["error"]["code"], "invalid_executor_result")
        self.assertNotIn(
            "RECEIPT-SECRET-2fa1",
            (self.root / "tamper" / "ledger.jsonl").read_text(encoding="utf-8"),
        )

    def test_edit_concurrency_consumes_one_approval_and_records_one_evidence(self) -> None:
        target = self.workspace / "concurrent.txt"
        target.write_text("before", encoding="utf-8")
        request = {
            "path": "concurrent.txt",
            "expected_sha256": digest(b"before"),
            "content": "after",
        }
        barrier = threading.Barrier(2)
        results = []
        errors = []

        second_control = CodingAgentControlPlane(
            self.ledger,
            executor=FixedWorkspaceCodingExecutor(),
            trusted_approver=self.trusted_approver,
            clock=self.clock,
        )

        def invoke_concurrently(control):
            try:
                barrier.wait()
                results.append(
                    control.invoke(
                        client_correlation_id="concurrent-edit",
                        tool=CODING_ATOMIC_EDIT,
                        tool_input=request,
                        actor="agent:codex",
                        workspace=str(self.workspace),
                    )
                )
            except Exception as exc:
                errors.append(exc)

        threads = [
            threading.Thread(target=invoke_concurrently, args=(control,))
            for control in (self.control, second_control)
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(5)
            self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])
        self.assertEqual(target.read_text(encoding="utf-8"), "after")
        snapshot = self.control.snapshot()
        calls = [call for call in snapshot.tool_calls.values() if call.client_correlation_id == "concurrent-edit"]
        evidence = [item for item in snapshot.evidence.values() if item.call_id == calls[0].call_id]
        approvals = [item for item in snapshot.approvals.values() if item.call_id == calls[0].call_id]
        self.assertEqual(len(calls), 1)
        self.assertEqual(len(evidence), 1)
        self.assertEqual(len(approvals), 1)
        self.assertEqual(approvals[0].state, "consumed")
        self.assertEqual(sum(result.result_available for result in results), 1)

    def test_coding_receipt_cannot_forge_reserved_decision_or_evidence(self) -> None:
        (self.workspace / "identity.txt").write_text("identity", encoding="utf-8")

        for field in ("decision_id", "evidence_id"):
            observed_requests = []
            base = FixedWorkspaceCodingExecutor()

            def tampering_executor(request, tool_input, field=field):
                observed_requests.append(request)
                valid = base(request, tool_input)
                forged = dict(valid.receipt)
                forged[field] = "forged-{}".format(field)
                return replace(valid, receipt=forged)

            control = CodingAgentControlPlane(
                self.root / "identity-tamper" / field / "ledger.jsonl",
                executor=tampering_executor,
                clock=self.clock,
            )
            result = control.invoke(
                client_correlation_id="coding-tamper-{}".format(field),
                tool=CODING_READ_FILE,
                tool_input={"path": "identity.txt"},
                actor="agent:codex",
                workspace=str(self.workspace),
            )
            request = observed_requests[0]
            self.assertEqual(request.decision_id, result.decision_id)
            self.assertEqual(request.evidence_id, result.evidence_id)
            self.assertEqual(result.outcome, "failed")
            self.assertIsNone(result.receipt)
            self.assertFalse(result.result_available)

    def test_crash_before_or_after_edit_never_reexecutes_running_call(self) -> None:
        target = self.workspace / "crash.txt"
        target.write_text("before", encoding="utf-8")
        request = {
            "path": "crash.txt",
            "expected_sha256": digest(b"before"),
            "content": "after",
        }
        with self.assertRaises(SimulatedCrash):
            self.control.invoke(
                client_correlation_id="crash-before-edit",
                tool=CODING_ATOMIC_EDIT,
                tool_input=request,
                actor="agent:codex",
                workspace=str(self.workspace),
                after_start_hook=lambda: (_ for _ in ()).throw(SimulatedCrash()),
            )
        self.assertEqual(target.read_text(encoding="utf-8"), "before")
        recovered = self.invoke("crash-before-edit", CODING_ATOMIC_EDIT, request)
        self.assertEqual(recovered.outcome, "interrupted")
        self.assertEqual(target.read_text(encoding="utf-8"), "before")

        target.write_text("before", encoding="utf-8")
        with self.assertRaises(SimulatedCrash):
            self.control.invoke(
                client_correlation_id="crash-after-edit",
                tool=CODING_ATOMIC_EDIT,
                tool_input=request,
                actor="agent:codex",
                workspace=str(self.workspace),
                after_commit_hook=lambda: (_ for _ in ()).throw(SimulatedCrash()),
            )
        self.assertEqual(target.read_text(encoding="utf-8"), "after")
        target.write_text("foreign-newer-value", encoding="utf-8")
        recovered_after = self.invoke("crash-after-edit", CODING_ATOMIC_EDIT, request)
        self.assertEqual(recovered_after.outcome, "interrupted")
        self.assertEqual(target.read_text(encoding="utf-8"), "foreign-newer-value")
        replay = self.invoke("crash-after-edit", CODING_ATOMIC_EDIT, request)
        self.assertEqual(replay.evidence_id, recovered_after.evidence_id)
        self.assertFalse(replay.result_available)

    def test_crash_during_authority_review_reuses_kernel_approval_identity(self) -> None:
        target = self.workspace / "approval-crash.txt"
        target.write_text("before", encoding="utf-8")
        request = {
            "path": "approval-crash.txt",
            "expected_sha256": digest(b"before"),
            "content": "after",
        }
        observed = []

        def crashing_approver(approval_request):
            observed.append(approval_request)
            raise SimulatedCrash()

        crashing = CodingAgentControlPlane(
            self.root / "approval-crash" / "ledger.jsonl",
            executor=FixedWorkspaceCodingExecutor(),
            trusted_approver=crashing_approver,
            clock=self.clock,
        )
        with self.assertRaises(SimulatedCrash):
            crashing.invoke(
                client_correlation_id="approval-review-crash",
                tool=CODING_ATOMIC_EDIT,
                tool_input=request,
                actor="agent:codex",
                workspace=str(self.workspace),
            )
        self.assertEqual(target.read_text(encoding="utf-8"), "before")

        def resumed_approver(approval_request):
            observed.append(approval_request)
            return "reviewer:alice"

        resumed = CodingAgentControlPlane(
            self.root / "approval-crash" / "ledger.jsonl",
            executor=FixedWorkspaceCodingExecutor(),
            trusted_approver=resumed_approver,
            clock=self.clock,
        )
        completed = resumed.invoke(
            client_correlation_id="approval-review-crash",
            tool=CODING_ATOMIC_EDIT,
            tool_input=request,
            actor="agent:codex",
            workspace=str(self.workspace),
        )
        self.assertEqual(completed.outcome, "succeeded")
        self.assertEqual(target.read_text(encoding="utf-8"), "after")
        self.assertEqual(observed[0].approval_id, observed[1].approval_id)
        self.assertEqual(completed.approval_id, observed[0].approval_id)

    def test_expired_approval_and_ledger_tamper_fail_closed(self) -> None:
        target = self.workspace / "expiry.txt"
        target.write_text("before", encoding="utf-8")

        def expiring_approver(request):
            self.clock.value += timedelta(minutes=10)
            return "reviewer:late"

        control = CodingAgentControlPlane(
            self.root / "expiry" / "ledger.jsonl",
            executor=FixedWorkspaceCodingExecutor(),
            trusted_approver=expiring_approver,
            clock=self.clock,
        )
        with self.assertRaises(Exception) as caught:
            control.invoke(
                client_correlation_id="expired-edit",
                tool=CODING_ATOMIC_EDIT,
                tool_input={
                    "path": "expiry.txt",
                    "expected_sha256": digest(b"before"),
                    "content": "after",
                },
                actor="agent:codex",
                workspace=str(self.workspace),
            )
        self.assertIn("expir", str(caught.exception).lower())
        self.assertEqual(target.read_text(encoding="utf-8"), "before")

        completed = self.invoke(
            "tamper-source",
            CODING_READ_FILE,
            {"path": "expiry.txt"},
        )
        original = self.ledger.read_bytes()
        self.ledger.write_bytes(original.replace(completed.input_digest.encode(), b"0" * 64, 1))
        with self.assertRaises(Exception):
            self.control.snapshot()


if __name__ == "__main__":
    unittest.main()

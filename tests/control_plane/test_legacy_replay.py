from __future__ import annotations

import base64
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "control_plane"))

from mainframe_control_plane import (  # noqa: E402
    CanonicalExecutionResult,
    ControlPlaneKernel,
    FixedStableCoreEvaluator,
    LedgerCorruption,
    load_fixed_stable_core_registry,
)


LEGACY_RESERVATION_KEYS = {
    "actor",
    "call_id",
    "canonical_id",
    "client_correlation_id",
    "decision_id",
    "input_digest",
    "input_metadata",
    "policy",
    "reserved_at",
    "run_id",
    "workspace",
}


def canonical(value) -> bytes:
    return json.dumps(
        value,
        allow_nan=False,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def rehash(events) -> bytes:
    previous = None
    rendered = []
    for sequence, original in enumerate(events, 1):
        event = copy.deepcopy(original)
        event["sequence"] = sequence
        event["previous_digest"] = previous
        event.pop("digest", None)
        event["digest"] = hashlib.sha256(canonical(event)).hexdigest()
        previous = event["digest"]
        rendered.append(canonical(event))
    return b"\n".join(rendered) + b"\n"


class LegacyCanonicalReplayTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        self.registry = load_fixed_stable_core_registry()

    def make_chain(self, *, completed: bool):
        ledger = self.root / ("complete.jsonl" if completed else "pending.jsonl")
        kernel = ControlPlaneKernel(
            ledger,
            evaluator=FixedStableCoreEvaluator(self.registry),
            stable_core_registry=self.registry,
        )
        request = kernel.reserve_canonical_request(
            client_correlation_id="legacy-correlation",
            canonical_id="mf:std:pure-string:to_upper",
            tool_input={"value": "hello"},
            actor="local-uid:501:mainframe-cli",
            workspace=str(self.workspace),
            policy="stable-core-v1",
        )
        if completed:
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
                tool_input={"value": "hello"},
                client_correlation_id=request.client_correlation_id,
            )
            kernel.evaluate_policy_decision(
                decision_id=request.decision_id,
                call_id=call.call_id,
                tool=call.tool,
                input_digest=call.input_digest,
                actor=call.actor,
                workspace=call.workspace,
                policy=call.policy,
                timeout_at=call.timeout_at,
                tool_input={"value": "hello"},
            )
            kernel.execute_canonical(
                call.call_id,
                tool_input={"value": "hello"},
                executor=lambda canonical_id, _tool_input: CanonicalExecutionResult(
                    "succeeded",
                    {
                        "schema_version": 1,
                        "ok": True,
                        "status": "success",
                        "canonical_id": canonical_id,
                        "name": "to_upper",
                        "owner": "pure-string",
                        "exit_code": 0,
                        "timed_out": False,
                        "output_exceeded": False,
                        "duration_ms": 1,
                        "audit_id": "legacy-fixture",
                        "stdout_b64": base64.b64encode(b"HELLO\n").decode("ascii"),
                        "stderr_b64": "",
                        "error": None,
                    },
                ),
            )
        events = [json.loads(line) for line in ledger.read_text().splitlines()]
        return ledger, request, events

    @staticmethod
    def legacy_reservation(events) -> None:
        reservation = events[0]
        reservation["payload"].pop("evidence_id")
        reservation["payload"].pop("reservation_binding")
        assert set(reservation["payload"]) == LEGACY_RESERVATION_KEYS

    def write_events(self, name: str, events) -> Path:
        ledger = self.root / name
        ledger.write_bytes(rehash(events))
        ledger.chmod(0o600)
        return ledger

    def assert_corrupt(self, name: str, events) -> None:
        ledger = self.write_events(name, events)
        with self.assertRaises(LedgerCorruption):
            ControlPlaneKernel(ledger).snapshot()

    def test_exact_pending_legacy_reservation_replays_and_new_writer_stays_current(self) -> None:
        _source, original_request, events = self.make_chain(completed=False)
        self.legacy_reservation(events)
        ledger = self.write_events("legacy-pending.jsonl", events)
        before = ledger.read_bytes()

        first = ControlPlaneKernel(ledger).snapshot()
        request = first.canonical_requests["legacy-correlation"]
        self.assertTrue(request.evidence_id.startswith("evidence-"))
        self.assertNotEqual(request.evidence_id, original_request.evidence_id)
        self.assertIsNone(request.reservation_binding)
        self.assertEqual(ledger.read_bytes(), before)
        self.assertEqual(
            ControlPlaneKernel(ledger)
            .snapshot()
            .canonical_requests["legacy-correlation"]
            .evidence_id,
            request.evidence_id,
        )

        appended = ControlPlaneKernel(ledger).reserve_canonical_request(
            client_correlation_id="new-current-correlation",
            canonical_id="mf:std:pure-string:to_lower",
            tool_input={"value": "HELLO"},
            actor="local-uid:501:mainframe-cli",
            workspace=str(self.workspace),
            policy="stable-core-v1",
        )
        self.assertTrue(ledger.read_bytes().startswith(before))
        current_event = json.loads(ledger.read_text().splitlines()[-1])
        self.assertEqual(
            set(current_event["payload"]),
            LEGACY_RESERVATION_KEYS | {"evidence_id", "reservation_binding"},
        )
        self.assertEqual(current_event["payload"]["evidence_id"], appended.evidence_id)
        self.assertIsNone(current_event["payload"]["reservation_binding"])

    def test_completed_legacy_chain_adopts_one_exact_historical_evidence_in_memory(self) -> None:
        _source, _request, events = self.make_chain(completed=True)
        self.legacy_reservation(events)
        evidence = next(event for event in events if event["kind"] == "evidence")
        historical_id = "evidence-24382527aaf14f4d83468a2b0d578025"
        evidence["payload"]["evidence_id"] = historical_id
        ledger = self.write_events("legacy-complete.jsonl", events)
        before = ledger.read_bytes()

        snapshot = ControlPlaneKernel(ledger).snapshot()
        request = snapshot.canonical_requests["legacy-correlation"]
        self.assertEqual(request.evidence_id, historical_id)
        self.assertEqual(snapshot.evidence[historical_id].call_id, request.call_id)
        self.assertEqual(snapshot.event_count, len(events))
        self.assertEqual(ledger.read_bytes(), before)

    def test_pending_legacy_request_executes_once_with_its_provisional_evidence_id(self) -> None:
        _source, _request, events = self.make_chain(completed=False)
        self.legacy_reservation(events)
        ledger = self.write_events("legacy-pending-execute.jsonl", events)
        kernel = ControlPlaneKernel(
            ledger,
            evaluator=FixedStableCoreEvaluator(self.registry),
            stable_core_registry=self.registry,
        )
        request = kernel.snapshot().canonical_requests["legacy-correlation"]
        provisional = request.evidence_id
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
            tool_input={"value": "hello"},
            client_correlation_id=request.client_correlation_id,
        )
        kernel.evaluate_policy_decision(
            decision_id=request.decision_id,
            call_id=call.call_id,
            tool=call.tool,
            input_digest=call.input_digest,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
            timeout_at=call.timeout_at,
            tool_input={"value": "hello"},
        )
        evidence = kernel.execute_canonical(
            call.call_id,
            tool_input={"value": "hello"},
            executor=lambda canonical_id, _tool_input: CanonicalExecutionResult(
                "succeeded",
                {
                    "schema_version": 1,
                    "ok": True,
                    "status": "success",
                    "canonical_id": canonical_id,
                    "name": "to_upper",
                    "owner": "pure-string",
                    "exit_code": 0,
                    "timed_out": False,
                    "output_exceeded": False,
                    "duration_ms": 1,
                    "audit_id": "legacy-pending-fixture",
                    "stdout_b64": base64.b64encode(b"HELLO\n").decode("ascii"),
                    "stderr_b64": "",
                    "error": None,
                },
            ),
        )
        self.assertEqual(evidence.evidence_id, provisional)
        replay = ControlPlaneKernel(ledger).snapshot()
        self.assertEqual(
            replay.canonical_requests["legacy-correlation"].evidence_id,
            provisional,
        )
        self.assertEqual(len(replay.evidence), 1)

    def test_partial_extra_wrong_type_and_digest_tamper_remain_corruption(self) -> None:
        _source, _request, base = self.make_chain(completed=False)
        for label, mutation in (
            ("missing-evidence-only", lambda payload: payload.pop("evidence_id")),
            ("missing-binding-only", lambda payload: payload.pop("reservation_binding")),
            ("legacy-extra", lambda payload: payload.update({"extra": None})),
        ):
            events = copy.deepcopy(base)
            if label == "legacy-extra":
                self.legacy_reservation(events)
            mutation(events[0]["payload"])
            self.assert_corrupt(label + ".jsonl", events)

        wrong_type = copy.deepcopy(base)
        self.legacy_reservation(wrong_type)
        wrong_type[0]["action"] = "legacy_reserved"
        self.assert_corrupt("wrong-type.jsonl", wrong_type)

        wrong_policy = copy.deepcopy(base)
        self.legacy_reservation(wrong_policy)
        wrong_policy[0]["payload"]["policy"] = "caller-policy"
        self.assert_corrupt("wrong-policy.jsonl", wrong_policy)

        project_memory = copy.deepcopy(base)
        self.legacy_reservation(project_memory)
        project_memory[0]["payload"]["canonical_id"] = (
            "mainframe.project_memory.status.v1"
        )
        self.assert_corrupt("project-memory-legacy.jsonl", project_memory)

        digest_tamper = copy.deepcopy(base)
        self.legacy_reservation(digest_tamper)
        ledger = self.write_events("digest-tamper.jsonl", digest_tamper)
        data = ledger.read_bytes().replace(b"legacy-correlation", b"legacy-correlatioN", 1)
        ledger.write_bytes(data)
        with self.assertRaises(LedgerCorruption):
            ControlPlaneKernel(ledger).snapshot()

    def test_historical_adoption_rejects_current_cross_call_decision_and_shape_tamper(self) -> None:
        _source, _request, base = self.make_chain(completed=True)

        current_mismatch = copy.deepcopy(base)
        evidence = next(event for event in current_mismatch if event["kind"] == "evidence")
        evidence["payload"]["evidence_id"] = "evidence-historical-current-mismatch"
        self.assert_corrupt("current-mismatch.jsonl", current_mismatch)

        cross_call = copy.deepcopy(base)
        self.legacy_reservation(cross_call)
        evidence = next(event for event in cross_call if event["kind"] == "evidence")
        evidence["payload"]["evidence_id"] = "evidence-historical-cross-call"
        evidence["payload"]["call_id"] = "call-different"
        self.assert_corrupt("cross-call.jsonl", cross_call)

        decision = copy.deepcopy(base)
        self.legacy_reservation(decision)
        evidence = next(event for event in decision if event["kind"] == "evidence")
        evidence["payload"]["evidence_id"] = "evidence-historical-wrong-decision"
        policy = next(event for event in decision if event["kind"] == "policy_decision")
        policy["payload"]["decision_id"] = "decision-different"
        self.assert_corrupt("wrong-decision.jsonl", decision)

        extra_evidence = copy.deepcopy(base)
        self.legacy_reservation(extra_evidence)
        evidence = next(event for event in extra_evidence if event["kind"] == "evidence")
        evidence["payload"]["evidence_id"] = "evidence-historical-extra-shape"
        evidence["payload"]["extra"] = None
        self.assert_corrupt("extra-evidence-shape.jsonl", extra_evidence)

    def test_second_conflicting_historical_evidence_is_rejected(self) -> None:
        _source, _request, events = self.make_chain(completed=True)
        self.legacy_reservation(events)
        evidence_index = next(
            index for index, event in enumerate(events) if event["kind"] == "evidence"
        )
        events[evidence_index]["payload"]["evidence_id"] = "evidence-historical-first"
        duplicate = copy.deepcopy(events[evidence_index])
        duplicate["event_id"] = "evt-legacy-conflicting-evidence"
        duplicate["payload"]["evidence_id"] = "evidence-historical-second"
        events.insert(evidence_index + 1, duplicate)
        self.assert_corrupt("conflicting-evidence.jsonl", events)


if __name__ == "__main__":
    unittest.main()

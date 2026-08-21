from __future__ import annotations

from dataclasses import replace
from datetime import datetime, timedelta, timezone
import base64
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "control_plane"))

from mainframe_control_plane import (  # noqa: E402
    BindingMismatch,
    ExecutionDenied,
    FixedProjectMemoryRegistry,
    PROJECT_MEMORY_CHECKPOINT,
    PROJECT_MEMORY_CLOSE,
    PROJECT_MEMORY_DISCOVERY,
    PROJECT_MEMORY_ENSURE,
    PROJECT_MEMORY_HANDOFF,
    PROJECT_MEMORY_PROGRESS,
    ProjectMemoryControlPlane,
    ProjectMemoryExecutionResult,
    ProjectMemoryObservation,
    legacy_memory_view,
)
from mainframe_control_plane.memory_transient import (  # noqa: E402
    decode_project_memory_result,
    encode_project_memory_result,
)


def sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def canonical(value) -> bytes:
    return json.dumps(
        value,
        allow_nan=False,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


class MutableClock:
    def __init__(self) -> None:
        self.value = datetime(2026, 8, 20, 12, 0, tzinfo=timezone.utc)

    def __call__(self) -> datetime:
        return self.value


class SimulatedCrash(BaseException):
    pass


class FakeProjectMemoryExecutor:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.mapping = {}
        self.results = {}
        self.calls = []
        self.requests = []
        self.observe_calls = []
        self.commits = []
        self.force_recovery = False
        self.omit_handoff_transient = False
        self.tamper_field = None

    def observe(self, workspace, project_digest):
        with self.lock:
            self.observe_calls.append((workspace, project_digest))
            current = self.mapping.get(project_digest)
            if current is None:
                return ProjectMemoryObservation(
                    project_digest, "absent", None, "0" * 64
                )
            return ProjectMemoryObservation(
                project_digest,
                "closed" if current["closed"] else "active",
                current["session_id"],
                self.state_digest(
                    project_digest,
                    current["session_id"],
                    current["closed"],
                    current["version"],
                ),
            )

    @staticmethod
    def state_digest(project_digest, session_id, closed, version):
        if session_id is None:
            return "0" * 64
        return sha(
            canonical(
                {
                    "closed": closed,
                    "project_digest": project_digest,
                    "session_id": session_id,
                    "version": version,
                }
            )
        )

    def __call__(self, request, tool_input):
        with self.lock:
            self.calls.append(request.memory_op_id)
            self.requests.append(request)
            cached = self.results.get(request.memory_op_id)
            if cached is not None:
                return cached
            project = request.project_digest
            current = self.mapping.get(project)
            before = self.state_digest(
                project,
                None if current is None else current["session_id"],
                False if current is None else current["closed"],
                0 if current is None else current["version"],
            )
            expected = tool_input.get("expected_session_id")
            recovery = self.force_recovery
            current_state = "absent" if current is None else (
                "closed" if current["closed"] else "active"
            )
            current_session = None if current is None else current["session_id"]
            if (
                request.observation.mapping_state != current_state
                or request.observation.session_id != current_session
                or request.observation.state_digest != before
            ):
                recovery = True
            if request.tool == PROJECT_MEMORY_ENSURE:
                if current is None:
                    session_id = sha(project.encode("ascii"))[:12]
                    current = {"session_id": session_id, "closed": False, "version": 1}
                    self.mapping[project] = current
                elif current["closed"]:
                    recovery = True
            else:
                if (
                    current is None
                    or current["closed"]
                    or expected != current["session_id"]
                ):
                    recovery = True
            if not recovery and request.tool != PROJECT_MEMORY_ENSURE:
                current["version"] += 1
                if request.tool == PROJECT_MEMORY_CLOSE:
                    current["closed"] = True
            session_id = expected if current is None else current["session_id"]
            after = self.state_digest(
                project,
                session_id,
                False if current is None else current["closed"],
                0 if current is None else current["version"],
            )
            record_type = {
                PROJECT_MEMORY_ENSURE: "session_ensure",
                PROJECT_MEMORY_CHECKPOINT: "checkpoint",
                PROJECT_MEMORY_DISCOVERY: "discovery",
                PROJECT_MEMORY_PROGRESS: "progress",
                PROJECT_MEMORY_CLOSE: "session_close",
                PROJECT_MEMORY_HANDOFF: "handoff",
            }[request.tool]
            key_value = None
            value_bytes = b""
            recipient = None
            if request.tool == PROJECT_MEMORY_CHECKPOINT:
                key_value = tool_input["key"]
                value_bytes = tool_input["value"].encode("utf-8")
            elif request.tool == PROJECT_MEMORY_DISCOVERY:
                value_bytes = tool_input["value"].encode("utf-8")
            elif request.tool == PROJECT_MEMORY_PROGRESS:
                key_value = tool_input["task"]
                value_bytes = canonical(
                    {
                        "current": tool_input["current"],
                        "status": tool_input["status"],
                        "total": tool_input["total"],
                    }
                )
            elif request.tool == PROJECT_MEMORY_HANDOFF:
                recipient = tool_input["target"]
                value_bytes = canonical(
                    {
                        "format": tool_input["render_format"],
                        "max_tokens": tool_input["max_tokens"],
                        "session_id": session_id,
                        "target": recipient,
                    }
                )
                if recovery and self.omit_handoff_transient:
                    value_bytes = b""
            receipt = {
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
                "expected_session_id": expected,
                "session_id": session_id,
                "outcome": "recovery_required" if recovery else "succeeded",
                "idempotency_key": request.memory_op_id,
                "record_type": record_type,
                "key_sha256": None if key_value is None else sha(key_value.encode()),
                "value_sha256": sha(value_bytes),
                "value_bytes": len(value_bytes),
                "recipient_sha256": None if recipient is None else sha(recipient.encode()),
                "retention_class": request.retention_class,
                "expires_at": request.expires_at,
                "state_digest_before": before,
                "state_digest_after": after,
                "observed_mapping_state": request.observation.mapping_state,
                "observed_session_id": request.observation.session_id,
                "observed_state_digest": request.observation.state_digest,
                "trust_label": "kernel_bound",
                "authoritative": False,
            }
            result = ProjectMemoryExecutionResult(
                "recovery_required" if recovery else "succeeded",
                receipt,
                transient=(
                    None
                    if request.tool == PROJECT_MEMORY_HANDOFF
                    and self.omit_handoff_transient
                    else value_bytes
                    if request.tool == PROJECT_MEMORY_HANDOFF
                    else b"TRANSIENT-EXECUTOR-OUTPUT-51e9"
                ),
            )
            if self.tamper_field is not None:
                bad = dict(receipt)
                bad[self.tamper_field] = "forged"
                result = replace(result, receipt=bad)
            self.results[request.memory_op_id] = result
            if not recovery:
                self.commits.append((request.tool, request.memory_op_id))
            return result


class ProjectMemoryControlPlaneTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(self.temp_dir.name)
        self.workspace = self.root / "project"
        self.workspace.mkdir()
        self.ledger = self.root / "state" / "memory.jsonl"
        self.clock = MutableClock()
        self.executor = FakeProjectMemoryExecutor()
        self.control = ProjectMemoryControlPlane(
            self.ledger, executor=self.executor, clock=self.clock
        )

    def invoke(self, correlation, tool, tool_input, **kwargs):
        return self.control.invoke(
            client_correlation_id=correlation,
            tool=tool,
            tool_input=tool_input,
            actor="agent:codex",
            workspace=str(self.workspace),
            **kwargs,
        )

    def ensure(self):
        return self.invoke("memory-ensure", PROJECT_MEMORY_ENSURE, {})

    @staticmethod
    def checkpoint_input(session_id, value, *, ttl_seconds=0):
        return {
            "expected_session_id": session_id,
            "key": "current_phase",
            "value": value,
            "importance": "high",
            "tags": ["phase", "reviewed"],
            "ttl_seconds": ttl_seconds,
        }

    def test_exact_six_mutation_contracts_reject_generic_action_and_authority_fields(self) -> None:
        registry = FixedProjectMemoryRegistry()
        self.assertEqual(
            {
                tool
                for tool, contract in registry.contracts.items()
                if contract.effect == "non_authoritative_memory"
            },
            {
                PROJECT_MEMORY_ENSURE,
                PROJECT_MEMORY_CHECKPOINT,
                PROJECT_MEMORY_DISCOVERY,
                PROJECT_MEMORY_PROGRESS,
                PROJECT_MEMORY_CLOSE,
                PROJECT_MEMORY_HANDOFF,
            },
        )
        with self.assertRaises(ExecutionDenied):
            self.invoke("generic-action", "mainframe.memory.apply.v1", {})
        before = self.control.snapshot().event_count
        for forged in (
            {"action": "checkpoint"},
            {"run_id": "forged"},
            {"authority": "caller"},
            {"executable": "/bin/sh"},
        ):
            with self.assertRaises(ExecutionDenied):
                self.invoke(
                    "forged-{}".format(next(iter(forged))),
                    PROJECT_MEMORY_ENSURE,
                    forged,
                )
        self.assertEqual(self.control.snapshot().event_count, before)

    def test_checkpoint_has_exact_policy_provenance_and_no_raw_value(self) -> None:
        ensured = self.ensure()
        secret = "MEMORY-SECRET-1ac4"
        key = "private-key-name"
        tool_input = self.checkpoint_input(ensured.session_id, secret)
        tool_input["key"] = key
        result = self.invoke("memory-checkpoint", PROJECT_MEMORY_CHECKPOINT, tool_input)
        self.assertEqual(result.outcome, "succeeded")
        self.assertTrue(result.result_available)
        record = result.memory_record
        self.assertEqual(record.run_id, result.run_id)
        self.assertEqual(record.call_id, result.call_id)
        self.assertEqual(record.evidence_id, result.evidence_id)
        self.assertEqual(record.decision_id, result.decision_id)
        self.assertEqual(record.input_digest, result.input_digest)
        self.assertEqual(record.policy_authority, "policy-engine:fixed-project-memory-v1")
        self.assertEqual(record.trust_label, "kernel_bound")
        self.assertFalse(record.authoritative)
        self.assertEqual(record.value_sha256, sha(secret.encode()))
        self.assertNotEqual(result.memory_op_id, result.client_correlation_id)
        self.assertTrue(result.memory_op_id.startswith("memory-op-"))
        self.assertTrue(result.run_id.startswith("run-"))
        self.assertTrue(result.call_id.startswith("call-"))
        self.assertTrue(result.decision_id.startswith("decision-"))
        self.assertTrue(result.evidence_id.startswith("evidence-"))
        ledger = self.ledger.read_bytes()
        self.assertNotIn(secret.encode(), ledger)
        self.assertNotIn(key.encode(), ledger)
        self.assertNotIn(result.transient, ledger)
        other_workspace = self.root / "other-project"
        other_workspace.mkdir()
        with self.assertRaises(BindingMismatch):
            self.control.invoke(
                client_correlation_id="memory-checkpoint",
                tool=PROJECT_MEMORY_CHECKPOINT,
                tool_input=tool_input,
                actor="agent:codex",
                workspace=str(other_workspace),
            )

    def test_executor_and_receipt_bind_reserved_decision_and_evidence_ids(self) -> None:
        result = self.ensure()
        request = self.executor.requests[-1]
        self.assertEqual(request.decision_id, result.decision_id)
        self.assertEqual(request.evidence_id, result.evidence_id)
        self.assertEqual(result.receipt["decision_id"], result.decision_id)
        self.assertEqual(result.receipt["evidence_id"], result.evidence_id)

        for field in ("decision_id", "evidence_id"):
            executor = FakeProjectMemoryExecutor()
            executor.tamper_field = field
            control = ProjectMemoryControlPlane(
                self.root / field / "ledger.jsonl",
                executor=executor,
                clock=self.clock,
            )
            tampered = control.invoke(
                client_correlation_id="tamper-{}".format(field),
                tool=PROJECT_MEMORY_ENSURE,
                tool_input={},
                actor="agent:codex",
                workspace=str(self.workspace),
            )
            self.assertEqual(tampered.outcome, "failed")
            self.assertEqual(tampered.evidence_id, executor.requests[-1].evidence_id)
            self.assertIsNone(tampered.receipt)
            self.assertIsNone(tampered.memory_record)

    def test_first_observation_and_checkpoint_expiry_are_frozen_in_reservation(self) -> None:
        ensured = self.invoke(
            "memory-ensure-named",
            PROJECT_MEMORY_ENSURE,
            {"name": "phase-7-session"},
        )
        tool_input = self.checkpoint_input(
            ensured.session_id, "reservation-secret", ttl_seconds=60
        )
        observed_before = len(self.executor.observe_calls)
        request = self.control.reserve(
            client_correlation_id="memory-reserved-ttl",
            tool=PROJECT_MEMORY_CHECKPOINT,
            tool_input=tool_input,
            actor="agent:codex",
            workspace=str(self.workspace),
        )
        self.assertEqual(len(self.executor.observe_calls), observed_before + 1)
        binding = request.reservation_binding
        self.assertEqual(binding["mapping_state"], "active")
        self.assertEqual(binding["session_id"], ensured.session_id)
        self.assertEqual(binding["expires_at"], "2026-08-20T12:01:00Z")
        reserved_ids = (request.run_id, request.call_id, request.decision_id)

        self.clock.value += timedelta(hours=1)
        completed = self.invoke(
            "memory-reserved-ttl", PROJECT_MEMORY_CHECKPOINT, tool_input
        )
        self.assertEqual(len(self.executor.observe_calls), observed_before + 1)
        self.assertEqual(
            (completed.run_id, completed.call_id, completed.decision_id), reserved_ids
        )
        self.assertEqual(completed.receipt["expires_at"], "2026-08-20T12:01:00Z")
        self.assertNotIn(b"reservation-secret", self.ledger.read_bytes())

    def test_all_operations_and_handoff_are_separate_immutable_aggregates(self) -> None:
        ensured = self.ensure()
        session_id = ensured.session_id
        self.invoke(
            "memory-checkpoint-all",
            PROJECT_MEMORY_CHECKPOINT,
            self.checkpoint_input(session_id, "checkpoint-value"),
        )
        self.invoke(
            "memory-discovery-all",
            PROJECT_MEMORY_DISCOVERY,
            {
                "expected_session_id": session_id,
                "value": "discovery-value",
                "importance": "critical",
                "tags": ["finding"],
            },
        )
        self.invoke(
            "memory-progress-all",
            PROJECT_MEMORY_PROGRESS,
            {
                "expected_session_id": session_id,
                "task": "phase-7",
                "current": 1,
                "total": 2,
                "status": "halfway",
            },
        )
        handoff = self.invoke(
            "memory-handoff-all",
            PROJECT_MEMORY_HANDOFF,
            {
                "expected_session_id": session_id,
                "target": "reviewer",
                "max_tokens": 2048,
                "render_format": "json",
            },
        )
        self.invoke(
            "memory-close-all",
            PROJECT_MEMORY_CLOSE,
            {"expected_session_id": session_id},
        )
        snapshot = self.control.snapshot()
        self.assertEqual(len(snapshot.memory_records), 5)
        self.assertEqual(len(snapshot.handoff_records), 1)
        self.assertIsNone(handoff.memory_record)
        self.assertIsNotNone(handoff.handoff_record)
        self.assertNotIn(handoff.handoff_id, snapshot.memory_records)
        self.assertNotIn(b'"target":"reviewer"', self.ledger.read_bytes())
        with self.assertRaises(Exception):
            snapshot.memory_records[next(iter(snapshot.memory_records))].authoritative = True

    def test_retry_after_sink_and_evidence_boundaries_never_reexecutes(self) -> None:
        session_id = self.ensure().session_id
        tool_input = self.checkpoint_input(session_id, "sink-secret")

        def broken_sink(_result):
            raise OSError("dead consumer")

        completed = self.invoke(
            "memory-sink-boundary",
            PROJECT_MEMORY_CHECKPOINT,
            tool_input,
            result_sink=broken_sink,
        )
        self.assertEqual(completed.outcome, "succeeded")
        calls = len(self.executor.calls)
        replay = self.invoke(
            "memory-sink-boundary", PROJECT_MEMORY_CHECKPOINT, tool_input
        )
        self.assertFalse(replay.result_available)
        self.assertEqual(replay.memory_id, completed.memory_id)
        self.assertEqual(len(self.executor.calls), calls)

        crash_input = dict(tool_input)
        crash_input["value"] = "evidence-boundary-secret"
        with self.assertRaises(SimulatedCrash):
            self.invoke(
                "memory-evidence-boundary",
                PROJECT_MEMORY_CHECKPOINT,
                crash_input,
                after_evidence_hook=lambda: (_ for _ in ()).throw(SimulatedCrash()),
            )
        calls = len(self.executor.calls)
        recovered = self.invoke(
            "memory-evidence-boundary", PROJECT_MEMORY_CHECKPOINT, crash_input
        )
        self.assertEqual(recovered.outcome, "succeeded")
        self.assertIsNotNone(recovered.memory_record)
        self.assertEqual(len(self.executor.calls), calls)

    def test_transient_handoff_tamper_cannot_contradict_durable_receipt(self) -> None:
        session_id = self.ensure().session_id
        result = self.invoke(
            "memory-handoff-tamper",
            PROJECT_MEMORY_HANDOFF,
            {
                "expected_session_id": session_id,
                "target": "reviewer",
                "max_tokens": 1024,
                "render_format": "json",
            },
        )
        raw = encode_project_memory_result(result)
        payload = json.loads(raw.decode("utf-8"))
        payload["transient_b64"] = base64.b64encode(b"forged-handoff").decode("ascii")
        tampered = canonical(payload)
        durable = replace(result, result_available=False, transient=None)
        with self.assertRaises(BindingMismatch):
            decode_project_memory_result(tampered, durable)

    def test_handoff_transient_is_required_only_for_success(self) -> None:
        ensured = self.ensure()
        tool_input = {
            "expected_session_id": ensured.session_id,
            "target": "reviewer",
            "max_tokens": 1024,
            "render_format": "json",
        }
        self.executor.force_recovery = True
        self.executor.omit_handoff_transient = True
        recovered = self.invoke(
            "memory-handoff-empty-recovery",
            PROJECT_MEMORY_HANDOFF,
            tool_input,
        )
        self.assertEqual(recovered.outcome, "recovery_required")
        self.assertFalse(recovered.result_available)
        self.assertIsNone(recovered.transient)
        self.assertEqual(recovered.receipt["value_bytes"], 0)
        self.assertEqual(recovered.receipt["value_sha256"], sha(b""))

        success_executor = FakeProjectMemoryExecutor()
        success_executor.mapping = dict(self.executor.mapping)
        success_executor.force_recovery = False
        success_executor.omit_handoff_transient = True
        success_control = ProjectMemoryControlPlane(
            self.root / "missing-success-handoff" / "ledger.jsonl",
            executor=success_executor,
            clock=self.clock,
        )
        missing = success_control.invoke(
            client_correlation_id="memory-handoff-missing-success",
            tool=PROJECT_MEMORY_HANDOFF,
            tool_input=tool_input,
            actor="agent:codex",
            workspace=str(self.workspace),
        )
        self.assertEqual(missing.outcome, "failed")
        self.assertFalse(missing.result_available)
        self.assertIsNone(missing.receipt)

    def test_concurrent_close_and_checkpoint_are_linearizable(self) -> None:
        session_id = self.ensure().session_id
        second = ProjectMemoryControlPlane(
            self.ledger, executor=self.executor, clock=self.clock
        )
        barrier = threading.Barrier(2)
        results = []
        errors = []

        def invoke_checkpoint():
            try:
                barrier.wait()
                results.append(
                    self.invoke(
                        "memory-concurrent-checkpoint",
                        PROJECT_MEMORY_CHECKPOINT,
                        self.checkpoint_input(session_id, "concurrent-value"),
                    )
                )
            except Exception as exc:
                errors.append(exc)

        def invoke_close():
            try:
                barrier.wait()
                results.append(
                    second.invoke(
                        client_correlation_id="memory-concurrent-close",
                        tool=PROJECT_MEMORY_CLOSE,
                        tool_input={"expected_session_id": session_id},
                        actor="agent:codex",
                        workspace=str(self.workspace),
                    )
                )
            except Exception as exc:
                errors.append(exc)

        threads = [threading.Thread(target=invoke_checkpoint), threading.Thread(target=invoke_close)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(5)
            self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])
        outcomes = {result.outcome for result in results}
        self.assertTrue(outcomes in ({"succeeded"}, {"succeeded", "recovery_required"}))
        close_indexes = [
            index
            for index, item in enumerate(self.executor.commits)
            if item[0] == PROJECT_MEMORY_CLOSE
        ]
        if close_indexes:
            later_checkpoints = [
                item
                for item in self.executor.commits[close_indexes[0] + 1 :]
                if item[0] == PROJECT_MEMORY_CHECKPOINT
            ]
            self.assertEqual(later_checkpoints, [])

    def test_mapping_and_receipt_tamper_are_durable_denials_without_repair(self) -> None:
        session_id = self.ensure().session_id
        recovery_executor = FakeProjectMemoryExecutor()
        recovery_executor.mapping = dict(self.executor.mapping)
        recovery_executor.force_recovery = True
        recovery = ProjectMemoryControlPlane(
            self.root / "recovery" / "ledger.jsonl",
            executor=recovery_executor,
            clock=self.clock,
        )
        recovered = recovery.invoke(
            client_correlation_id="mapping-recovery-required",
            tool=PROJECT_MEMORY_CHECKPOINT,
            tool_input=self.checkpoint_input(session_id, "must-not-repair"),
            actor="agent:codex",
            workspace=str(self.workspace),
        )
        self.assertEqual(recovered.outcome, "recovery_required")
        self.assertIsNone(recovered.memory_record)
        calls = len(recovery_executor.calls)
        replay = recovery.invoke(
            client_correlation_id="mapping-recovery-required",
            tool=PROJECT_MEMORY_CHECKPOINT,
            tool_input=self.checkpoint_input(session_id, "must-not-repair"),
            actor="agent:codex",
            workspace=str(self.workspace),
        )
        self.assertEqual(replay.outcome, "recovery_required")
        self.assertEqual(len(recovery_executor.calls), calls)

        tamper_executor = FakeProjectMemoryExecutor()
        tamper_executor.mapping = dict(self.executor.mapping)
        tamper_executor.tamper_field = "project_digest"
        tampered = ProjectMemoryControlPlane(
            self.root / "tamper" / "ledger.jsonl",
            executor=tamper_executor,
            clock=self.clock,
        ).invoke(
            client_correlation_id="memory-receipt-tamper",
            tool=PROJECT_MEMORY_CHECKPOINT,
            tool_input=self.checkpoint_input(session_id, "receipt-secret"),
            actor="agent:codex",
            workspace=str(self.workspace),
        )
        self.assertEqual(tampered.outcome, "failed")
        self.assertIsNone(tampered.memory_record)
        tamper_calls = len(tamper_executor.calls)
        tampered_replay = ProjectMemoryControlPlane(
            self.root / "tamper" / "ledger.jsonl",
            executor=tamper_executor,
            clock=self.clock,
        ).invoke(
            client_correlation_id="memory-receipt-tamper",
            tool=PROJECT_MEMORY_CHECKPOINT,
            tool_input=self.checkpoint_input(session_id, "receipt-secret"),
            actor="agent:codex",
            workspace=str(self.workspace),
        )
        self.assertEqual(tampered_replay.outcome, "failed")
        self.assertEqual(len(tamper_executor.calls), tamper_calls)
        self.assertNotIn(
            b"receipt-secret", (self.root / "tamper" / "ledger.jsonl").read_bytes()
        )

    def test_expiry_hides_visibility_but_preserves_non_authority_metadata(self) -> None:
        session_id = self.ensure().session_id
        expires = self.clock.value + timedelta(seconds=5)
        result = self.invoke(
            "memory-expiry",
            PROJECT_MEMORY_CHECKPOINT,
            self.checkpoint_input(session_id, "expiring-secret", ttl_seconds=5),
        )
        self.assertIn(result.memory_id, self.control.visible_memory_records())
        self.clock.value = expires
        self.assertNotIn(result.memory_id, self.control.visible_memory_records())
        durable = self.control.snapshot().memory_records[result.memory_id]
        self.assertEqual(durable.trust_label, "kernel_bound")
        self.assertFalse(durable.authoritative)
        self.assertEqual(durable.policy_authority, "policy-engine:fixed-project-memory-v1")
        self.assertNotIn(b"expiring-secret", self.ledger.read_bytes())

    def test_legacy_view_is_untrusted_non_authorizing_and_never_migrated(self) -> None:
        before = self.control.snapshot().event_count
        legacy = legacy_memory_view(
            memory_id="legacy-1",
            value_sha256=sha(b"legacy-value"),
            value_bytes=len(b"legacy-value"),
            expires_at=None,
        )
        self.assertEqual(legacy.trust_label, "untrusted_legacy")
        self.assertFalse(legacy.authoritative)
        self.assertIsNone(legacy.run_id)
        self.assertIsNone(legacy.call_id)
        self.assertIsNone(legacy.evidence_id)
        self.assertEqual(self.control.snapshot().event_count, before)

        read_only = self.control.inspect_legacy([legacy])
        self.assertEqual(read_only, (legacy,))
        self.assertEqual(self.control.snapshot().event_count, before)

    def test_running_operation_recovers_without_reexecution_or_aggregate(self) -> None:
        session_id = self.ensure().session_id
        tool_input = self.checkpoint_input(session_id, "running-secret")
        with self.assertRaises(SimulatedCrash):
            self.invoke(
                "memory-running-crash",
                PROJECT_MEMORY_CHECKPOINT,
                tool_input,
                after_start_hook=lambda: (_ for _ in ()).throw(SimulatedCrash()),
            )
        calls = len(self.executor.calls)
        recovered = self.invoke(
            "memory-running-crash", PROJECT_MEMORY_CHECKPOINT, tool_input
        )
        self.assertEqual(recovered.outcome, "recovery_required")
        self.assertIsNone(recovered.memory_record)
        self.assertEqual(len(self.executor.calls), calls)
        self.assertNotIn(b"running-secret", self.ledger.read_bytes())


if __name__ == "__main__":
    unittest.main()

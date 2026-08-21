from __future__ import annotations

import hashlib
from pathlib import Path
import sys
import tempfile
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "control_plane"))

from mainframe_control_plane import (  # noqa: E402
    ExecutionDenied,
    FixedProjectMemoryRegistry,
    PROJECT_MEMORY_CONTEXT,
    PROJECT_MEMORY_FIND,
    PROJECT_MEMORY_GET,
    PROJECT_MEMORY_SESSION,
    PROJECT_MEMORY_STATUS,
    PROJECT_MEMORY_SUMMARY,
    ProjectMemoryControlPlane,
    ProjectMemoryExecutionResult,
    ProjectMemoryObservation,
)


READ_TOOLS = {
    PROJECT_MEMORY_SESSION: ({}, "project_session", b"0123456789ab\n"),
    PROJECT_MEMORY_STATUS: ({}, "project_status", b'{"status":"active"}'),
    PROJECT_MEMORY_GET: (
        {"key": "private-key", "default": ""},
        "project_get",
        b"READ-SECRET-7E",
    ),
    PROJECT_MEMORY_SUMMARY: (
        {"max_tokens": 0},
        "project_summary",
        b'{"summary":"READ-SECRET-7E"}',
    ),
    PROJECT_MEMORY_CONTEXT: (
        {
            "task": "review",
            "max_tokens": 0,
            "render_format": "json",
            "include": "discoveries,progress,checkpoints,logs",
        },
        "project_context",
        b'{"context":"READ-SECRET-7E"}',
    ),
    PROJECT_MEMORY_FIND: (
        {"query": "needle", "kind": "mixed", "limit": 10},
        "project_find",
        b'[{"preview":"READ-SECRET-7E"}]',
    ),
}


def sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


class ReadExecutor:
    def __init__(self, mapping_state: str = "active") -> None:
        self.mapping_state = mapping_state
        self.session_id = None if mapping_state == "absent" else "0123456789ab"
        self.calls = 0
        self.tamper_transient = False

    def observe(self, workspace, project_digest):
        return ProjectMemoryObservation(
            project_digest,
            self.mapping_state,
            self.session_id,
            sha((self.mapping_state + ":state").encode()),
        )

    def __call__(self, request, tool_input):
        self.calls += 1
        _normalized, record_type, transient = READ_TOOLS[request.tool]
        outcome = (
            "succeeded"
            if request.observation.mapping_state in ("active", "closed")
            else "recovery_required"
        )
        delivered = transient if outcome == "succeeded" else None
        if self.tamper_transient:
            delivered = b"tampered"
        key = None
        if request.tool == PROJECT_MEMORY_GET:
            key = tool_input["key"]
        elif request.tool == PROJECT_MEMORY_CONTEXT:
            key = tool_input["task"]
        elif request.tool == PROJECT_MEMORY_FIND:
            key = tool_input["query"]
        value = transient if outcome == "succeeded" else b""
        receipt = {
            "schema_version": 1,
            "memory_op_id": request.memory_op_id,
            "memory_id": None,
            "handoff_id": None,
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
            "expected_session_id": None,
            "session_id": request.observation.session_id,
            "outcome": outcome,
            "idempotency_key": request.memory_op_id,
            "record_type": record_type,
            "key_sha256": None if key is None else sha(key.encode()),
            "value_sha256": sha(value),
            "value_bytes": len(value),
            "recipient_sha256": None,
            "retention_class": request.retention_class,
            "expires_at": request.expires_at,
            "state_digest_before": request.observation.state_digest,
            "state_digest_after": request.observation.state_digest,
            "observed_mapping_state": request.observation.mapping_state,
            "observed_session_id": request.observation.session_id,
            "observed_state_digest": request.observation.state_digest,
            "trust_label": "kernel_bound",
            "authoritative": False,
        }
        return ProjectMemoryExecutionResult(outcome, receipt, delivered)


class ProjectMemoryReadContractTests(unittest.TestCase):
    def test_registry_has_exact_six_reads_and_normalizes_public_defaults(self) -> None:
        registry = FixedProjectMemoryRegistry()
        reads = {tool for tool, contract in registry.contracts.items() if contract.effect == "read_only"}
        self.assertEqual(reads, set(READ_TOOLS))
        self.assertEqual(registry.normalize_input(PROJECT_MEMORY_SESSION, {}), {})
        self.assertEqual(registry.normalize_input(PROJECT_MEMORY_STATUS, {}), {})
        self.assertEqual(
            registry.normalize_input(PROJECT_MEMORY_GET, {"key": "k"}),
            {"key": "k", "default": ""},
        )
        self.assertEqual(
            registry.normalize_input(PROJECT_MEMORY_SUMMARY, {}),
            {"max_tokens": 0},
        )
        self.assertEqual(
            registry.normalize_input(PROJECT_MEMORY_CONTEXT, {"task": "t"}),
            {
                "task": "t",
                "max_tokens": 0,
                "render_format": "json",
                "include": "discoveries,progress,checkpoints,logs",
            },
        )
        self.assertEqual(
            registry.normalize_input(PROJECT_MEMORY_FIND, {"query": "q"}),
            {"query": "q", "kind": "mixed", "limit": 10},
        )
        for tool, bad in (
            (PROJECT_MEMORY_SESSION, {"session_id": "caller"}),
            (PROJECT_MEMORY_GET, {"key": "k", "authority": "caller"}),
            (PROJECT_MEMORY_SUMMARY, {"max_tokens": 1000001}),
            (PROJECT_MEMORY_CONTEXT, {"task": "t", "render_format": "yaml"}),
            (PROJECT_MEMORY_FIND, {"query": "q", "kind": "anything"}),
        ):
            with self.assertRaises(ExecutionDenied):
                registry.normalize_input(tool, bad)

    def test_all_reads_are_transient_metadata_only_and_do_not_create_aggregates(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workspace = root / "workspace"
            workspace.mkdir()
            ledger = root / "state" / "ledger.jsonl"
            executor = ReadExecutor()
            control = ProjectMemoryControlPlane(ledger, executor=executor)
            for index, (tool, (tool_input, _record_type, raw)) in enumerate(READ_TOOLS.items()):
                result = control.invoke(
                    client_correlation_id="read-{}".format(index),
                    tool=tool,
                    tool_input=tool_input,
                    actor="agent:codex",
                    workspace=str(workspace),
                )
                self.assertEqual(result.outcome, "succeeded")
                self.assertEqual(result.transient, raw)
                self.assertTrue(result.result_available)
                self.assertIsNone(result.memory_id)
                self.assertIsNone(result.handoff_id)
                self.assertIsNone(result.memory_record)
                self.assertIsNone(result.handoff_record)
                self.assertEqual(result.receipt["value_sha256"], sha(raw))
                self.assertEqual(result.receipt["value_bytes"], len(raw))
            snapshot = control.snapshot()
            self.assertEqual(snapshot.memory_records, {})
            self.assertEqual(snapshot.handoff_records, {})
            durable = ledger.read_bytes()
            self.assertNotIn(b"READ-SECRET-7E", durable)
            replay = control.invoke(
                client_correlation_id="read-2",
                tool=PROJECT_MEMORY_GET,
                tool_input=READ_TOOLS[PROJECT_MEMORY_GET][0],
                actor="agent:codex",
                workspace=str(workspace),
            )
            self.assertFalse(replay.result_available)
            self.assertIsNone(replay.transient)
            self.assertEqual(executor.calls, 6)

    def test_absent_or_invalid_mapping_fails_without_transient_or_aggregate(self) -> None:
        for mapping_state in ("absent", "invalid"):
            with self.subTest(mapping_state=mapping_state), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                workspace = root / "workspace"
                workspace.mkdir()
                control = ProjectMemoryControlPlane(
                    root / "state" / "ledger.jsonl",
                    executor=ReadExecutor(mapping_state),
                )
                result = control.invoke(
                    client_correlation_id="read-{}".format(mapping_state),
                    tool=PROJECT_MEMORY_GET,
                    tool_input={"key": "k"},
                    actor="agent:codex",
                    workspace=str(workspace),
                )
                self.assertEqual(result.outcome, "recovery_required")
                self.assertFalse(result.result_available)
                self.assertIsNone(result.memory_record)
                self.assertIsNone(result.handoff_record)

    def test_closed_mapping_remains_readable_and_transient_tamper_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workspace = root / "workspace"
            workspace.mkdir()
            executor = ReadExecutor("closed")
            control = ProjectMemoryControlPlane(
                root / "state" / "ledger.jsonl", executor=executor
            )
            closed = control.invoke(
                client_correlation_id="read-closed",
                tool=PROJECT_MEMORY_STATUS,
                tool_input={},
                actor="agent:codex",
                workspace=str(workspace),
            )
            self.assertEqual(closed.outcome, "succeeded")
            self.assertTrue(closed.result_available)

            bad = ReadExecutor()
            bad.tamper_transient = True
            control = ProjectMemoryControlPlane(
                root / "bad" / "ledger.jsonl", executor=bad
            )
            tampered = control.invoke(
                client_correlation_id="read-tampered",
                tool=PROJECT_MEMORY_GET,
                tool_input={"key": "private-key", "default": ""},
                actor="agent:codex",
                workspace=str(workspace),
            )
            self.assertEqual(tampered.outcome, "failed")
            self.assertFalse(tampered.result_available)
            self.assertIsNone(tampered.receipt)


if __name__ == "__main__":
    unittest.main()

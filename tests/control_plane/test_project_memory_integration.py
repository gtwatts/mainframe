from __future__ import annotations

import base64
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "control_plane"))

from mainframe_control_plane import (  # noqa: E402
    ExecutionDenied,
    ControlPlaneKernel,
    FixedProjectMemoryRegistry,
    PROJECT_MEMORY_CHECKPOINT,
    PROJECT_MEMORY_CLOSE,
    PROJECT_MEMORY_CONTEXT,
    PROJECT_MEMORY_ENSURE,
    PROJECT_MEMORY_FIND,
    PROJECT_MEMORY_GET,
    PROJECT_MEMORY_HANDOFF,
    PROJECT_MEMORY_PROGRESS,
    PROJECT_MEMORY_SESSION,
    PROJECT_MEMORY_STATUS,
    PROJECT_MEMORY_SUMMARY,
    ProjectMemoryObservation,
)
from mainframe_control_plane.memory_executor import (  # noqa: E402
    FixedProjectMemorySubprocessExecutor,
)


def sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


class CompatibilitySchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = FixedProjectMemoryRegistry()

    def test_public_compatibility_inputs_are_closed_and_stable(self) -> None:
        self.assertEqual(
            self.registry.normalize_input(PROJECT_MEMORY_ENSURE, {"name": "phase-7"}),
            {"name": "phase-7"},
        )
        checkpoint = {
            "expected_session_id": "0123456789ab",
            "key": "phase",
            "value": "secret",
            "importance": "high",
            "tags": ["reviewed"],
            "ttl_seconds": 60,
        }
        self.assertEqual(
            self.registry.normalize_input(PROJECT_MEMORY_CHECKPOINT, checkpoint),
            checkpoint,
        )
        progress = {
            "expected_session_id": "0123456789ab",
            "task": "phase-7",
            "current": 0,
            "total": 1,
            "status": "",
        }
        self.assertEqual(
            self.registry.normalize_input(PROJECT_MEMORY_PROGRESS, progress),
            progress,
        )
        handoff = {
            "expected_session_id": "0123456789ab",
            "target": "reviewer",
            "max_tokens": 2048,
            "render_format": "json",
        }
        self.assertEqual(
            self.registry.normalize_input(PROJECT_MEMORY_HANDOFF, handoff),
            handoff,
        )
        for bad in (
            {"name": ""},
            {"name": "x", "authority": "caller"},
        ):
            with self.assertRaises(ExecutionDenied):
                self.registry.normalize_input(PROJECT_MEMORY_ENSURE, bad)

    def test_observation_contract_is_metadata_only(self) -> None:
        observed = ProjectMemoryObservation(
            project_digest=sha(b"workspace"),
            mapping_state="active",
            session_id="0123456789ab",
            state_digest=sha(b"state"),
        )
        self.assertEqual(observed.mapping_state, "active")
        self.assertNotIn("value", observed.to_dict())

    def test_non_memory_reservation_has_explicit_null_binding(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            kernel = ControlPlaneKernel(Path(directory) / "ledger.jsonl")
            request = kernel.reserve_canonical_request(
                client_correlation_id="stable-core-reservation",
                canonical_id="fixed.read.only",
                tool_input={"value": "not-persisted"},
                actor="agent:test",
                workspace=directory,
                policy="stable-core-v1",
            )
            self.assertIsNone(request.reservation_binding)
            self.assertTrue(request.evidence_id.startswith("evidence-"))
            self.assertEqual(kernel.snapshot().event_count, 1)

    def test_fixed_adapter_storage_uses_only_private_state_subtree(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "state"
            state.mkdir(mode=0o700)
            ledger = state / "control-plane.jsonl"
            executor = FixedProjectMemorySubprocessExecutor._for_test(
                release_root=root,
                ledger_path=ledger,
            )
            environment = executor._environment()
            runtime = (state / ".mainframe-control-plane-runtime").resolve()
            self.assertEqual(environment["HOME"], str(runtime))
            self.assertEqual(
                environment["XDG_STATE_HOME"],
                str(runtime / "project-memory-adapter-state"),
            )
            self.assertNotIn("AWM_ROOT", environment)
            self.assertNotIn("MAINFRAME_ROOT", environment)


class PublicProjectMemoryIntegrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(os.path.realpath(self.temporary.name))
        self.layout = self.root / "layout"
        shutil.copytree(PROJECT_ROOT / "control_plane", self.layout / "control_plane")
        (self.layout / "bin").mkdir()
        shutil.copy2(
            PROJECT_ROOT
            / "tests"
            / "control_plane"
            / "fixtures"
            / "project_memory_fake_adapter.py",
            self.layout / "bin" / "mainframe",
        )
        os.chmod(self.layout / "bin" / "mainframe", 0o700)
        self.cli = self.layout / "control_plane" / "mainframe-control-plane"
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        self.state_root = self.root / "state"
        self.state_root.mkdir(mode=0o700)
        self.adapter_state = (
            self.state_root
            / "mainframe"
            / ".mainframe-control-plane-runtime"
            / "project-memory-adapter-state"
        )

    def command(self, tool, correlation, presentation="control-plane-json-v1"):
        return [
            str(self.cli),
            "project-memory-invoke",
            "--tool-id",
            tool,
            "--input-json",
            "-",
            "--client-correlation-id",
            correlation,
            "--format",
            presentation,
        ]

    def environment(self):
        return {
            "PATH": "/poisoned",
            "PYTHONPATH": "/poisoned",
            "PYTHONHOME": "/poisoned",
            "HOME": "/poisoned",
            "TMPDIR": "/tmp",
            "XDG_STATE_HOME": str(self.state_root),
        }

    def invoke(self, tool, correlation, tool_input, presentation="control-plane-json-v1"):
        completed = subprocess.run(
            self.command(tool, correlation, presentation),
            input=json.dumps(tool_input),
            cwd=self.workspace,
            env=self.environment(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            timeout=15,
        )
        self.assertEqual(completed.stderr, "")
        return completed

    def structured(self, tool, correlation, tool_input):
        completed = self.invoke(tool, correlation, tool_input)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        payload = json.loads(completed.stdout)
        self.assertTrue(payload["ok"])
        return payload["result"]

    def ensure(self, correlation="public-memory-ensure"):
        return self.structured(
            PROJECT_MEMORY_ENSURE,
            correlation,
            {"name": "private-session-name-41af"},
        )

    @staticmethod
    def alive(pid):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        return True

    def crash_invocation(self, tool, correlation, tool_input, boundary="evidence"):
        """Kill a copied-layout process at an actual durable write boundary."""
        ledger = self.state_root / "mainframe" / "control-plane.jsonl"
        program = [
            "import json,os,sys",
            "from pathlib import Path",
            "sys.path.insert(0, " + repr(str(self.layout / "control_plane")) + ")",
            "from mainframe_control_plane.memory import ProjectMemoryControlPlane",
            "from mainframe_control_plane.memory_executor import FixedProjectMemorySubprocessExecutor",
            "from mainframe_control_plane import ControlPlaneKernel",
            "ledger=Path(" + repr(str(ledger)) + ")",
            "control=ProjectMemoryControlPlane(ledger, executor=FixedProjectMemorySubprocessExecutor(ledger_path=ledger))",
        ]
        hook = ""
        if boundary == "evidence":
            hook = ", after_evidence_hook=lambda:os._exit(87)"
        elif boundary == "aggregate":
            program += [
                "original=ControlPlaneKernel._finalize_project_memory_aggregate",
                "def crash(self, call_id):",
                "    original(self, call_id)",
                "    os._exit(87)",
                "ControlPlaneKernel._finalize_project_memory_aggregate=crash",
            ]
        elif boundary == "closed_run":
            program += [
                "original=ProjectMemoryControlPlane._close_run",
                "def crash(self, run_id, succeeded):",
                "    original(self, run_id, succeeded)",
                "    os._exit(87)",
                "ProjectMemoryControlPlane._close_run=crash",
            ]
        else:
            raise AssertionError("unknown crash boundary")
        program.append(
            "control.invoke(client_correlation_id=" + repr(correlation) + ",tool=" + repr(tool) +
            ",tool_input=json.loads(sys.stdin.read()),actor='local-uid:{}:mainframe-cli'.format(os.geteuid()),workspace=os.getcwd()" + hook + ")"
        )
        completed = subprocess.run(
            ["/usr/bin/python3", "-I", "-B", "-c", "\n".join(program)],
            input=json.dumps(tool_input), cwd=self.workspace, env=self.environment(),
            capture_output=True, text=True, timeout=15,
        )
        self.assertEqual(completed.returncode, 87, completed.stderr)
        self.assertEqual(completed.stdout, "")
        self.assertEqual(completed.stderr, "")
        return ledger, ControlPlaneKernel(ledger).snapshot()

    def invoke_worker(self, correlation, tool_input):
        ledger = self.state_root / "mainframe" / "control-plane.jsonl"
        input_read, input_write = os.pipe()
        result_read, result_write = os.pipe()
        try:
            content = json.dumps(tool_input).encode("utf-8")
            self.assertLess(len(content), 4096)
            self.assertEqual(os.write(input_write, content), len(content))
            os.close(input_write)
            input_write = -1
            completed = subprocess.run(
                [str(self.cli), "--ledger", str(ledger), "__project-memory-worker-v1",
                 "--client-correlation-id", correlation, "--input-fd", str(input_read),
                 "--result-fd", str(result_write)],
                cwd=self.workspace, env=self.environment(), stdin=subprocess.DEVNULL,
                capture_output=True, pass_fds=(input_read, result_write), text=True, timeout=15,
            )
            os.close(result_write)
            result_write = -1
            raw = os.read(result_read, 4096)
            return completed, raw
        finally:
            for fd in (input_read, input_write, result_read, result_write):
                if fd >= 0:
                    os.close(fd)

    def test_public_worker_finalizes_terminal_success_and_failure_after_evidence_crash(self) -> None:
        sid = self.ensure("evidence-crash-seed")["session_id"]
        checkpoint = dict(expected_session_id=sid, key="crash-key", value="private-crash-value",
                          importance="normal", tags=[], ttl_seconds=0)
        cases = [
            (PROJECT_MEMORY_CHECKPOINT, checkpoint, "succeeded", "completed", 1),
            # This fixture's stale-session receipt carries a mismatched session
            # identity and is rejected by receipt validation before recovery
            # classification. It must still finalize the failed Run safely.
            (PROJECT_MEMORY_CHECKPOINT, {**checkpoint, "expected_session_id": "0" * 12},
             "failed", "failed", 0),
            (PROJECT_MEMORY_GET, {"key": "tamper-receipt", "default": "private-read-value"},
             "failed", "failed", 0),
        ]
        self.assertNotEqual(sid, "0" * 12)
        for number, (tool, body, outcome, run_state, aggregate_count) in enumerate(cases):
            with self.subTest(outcome=outcome):
                correlation = "evidence-crash-" + str(number)
                ledger, snapshot = self.crash_invocation(tool, correlation, body)
                request = snapshot.canonical_requests[correlation]
                self.assertEqual(snapshot.tool_calls[request.call_id].state,
                                 "succeeded" if outcome == "succeeded" else "failed")
                self.assertEqual(snapshot.runs[request.run_id].state, "active")
                self.assertEqual(sum(item.call_id == request.call_id for item in snapshot.evidence.values()), 1)
                self.assertEqual(sum(item.call_id == request.call_id for item in snapshot.memory_records.values()), 0)
                executions = (self.adapter_state / "fixture-execute-count").read_bytes()
                recovered = self.structured(tool, correlation, body)
                self.assertEqual(recovered["status"], "completed")
                self.assertEqual(recovered["outcome"], outcome)
                self.assertFalse(recovered["result_available"])
                self.assertIsNone(recovered["transient_b64"])
                snapshot = ControlPlaneKernel(ledger).snapshot()
                self.assertEqual(snapshot.runs[request.run_id].state, run_state)
                self.assertEqual(sum(item.call_id == request.call_id for item in snapshot.memory_records.values()), aggregate_count)
                self.assertEqual(sum(item.call_id == request.call_id for item in snapshot.evidence.values()), 1)
                before = ledger.read_bytes()
                replay = self.structured(tool, correlation, body)
                self.assertEqual(replay, recovered)
                self.assertEqual(ledger.read_bytes(), before)
                self.assertEqual((self.adapter_state / "fixture-execute-count").read_bytes(), executions)
                self.assertNotIn(b"private-crash-value", before)
                self.assertNotIn(b"private-read-value", before)

    def test_public_worker_finalizes_recovery_required_after_evidence_crash(self) -> None:
        # An absent project is a valid non-authoritative recovery result, not an
        # invalid adapter receipt. Its failed ToolCall also needs Run closure.
        ledger, snapshot = self.crash_invocation(PROJECT_MEMORY_STATUS, "absent-crash", {})
        request = snapshot.canonical_requests["absent-crash"]
        self.assertEqual(snapshot.tool_calls[request.call_id].state, "failed")
        self.assertEqual(snapshot.runs[request.run_id].state, "active")
        executions = (self.adapter_state / "fixture-execute-count").read_bytes()
        recovered = self.structured(PROJECT_MEMORY_STATUS, "absent-crash", {})
        self.assertEqual(recovered["outcome"], "recovery_required")
        self.assertFalse(recovered["result_available"])
        snapshot = ControlPlaneKernel(ledger).snapshot()
        self.assertEqual(snapshot.runs[request.run_id].state, "failed")
        self.assertEqual(len(snapshot.evidence), 1)
        self.assertEqual(len(snapshot.memory_records), 0)
        self.assertEqual(len(snapshot.handoff_records), 0)
        before = ledger.read_bytes()
        self.assertEqual(self.structured(PROJECT_MEMORY_STATUS, "absent-crash", {}), recovered)
        self.assertEqual(ledger.read_bytes(), before)
        self.assertEqual((self.adapter_state / "fixture-execute-count").read_bytes(), executions)

    def test_terminal_worker_requires_exact_input_before_finalization_and_replay(self) -> None:
        self.ensure("worker-binding-seed")
        correlation = "worker-binding-crash"
        body = {"key": "missing", "default": "private-transient-value"}
        ledger, _snapshot = self.crash_invocation(PROJECT_MEMORY_GET, correlation, body)
        executions = (self.adapter_state / "fixture-execute-count").read_bytes()
        for already_finalized in (False, True):
            with self.subTest(already_finalized=already_finalized):
                before = ledger.read_bytes()
                mismatch = self.invoke(PROJECT_MEMORY_GET, correlation, {**body, "default": "substituted"})
                self.assertEqual(mismatch.returncode, 3)
                self.assertEqual(json.loads(mismatch.stdout)["error"]["code"], "binding_mismatch")
                mismatch, raw = self.invoke_worker(correlation, {**body, "default": "substituted"})
                self.assertEqual(mismatch.returncode, 3, mismatch.stdout)
                self.assertEqual(json.loads(mismatch.stdout)["error"]["code"], "binding_mismatch")
                self.assertEqual(raw, b"")
                self.assertEqual(ledger.read_bytes(), before)
                valid, raw = self.invoke_worker(correlation, body)
                self.assertEqual(valid.returncode, 0, valid.stdout)
                self.assertEqual(raw, b"")
                if already_finalized:
                    self.assertEqual(ledger.read_bytes(), before)
                recovered = self.structured(PROJECT_MEMORY_GET, correlation, body)
                self.assertEqual(recovered["outcome"], "succeeded")
                self.assertFalse(recovered["result_available"])
                self.assertIsNone(recovered["transient_b64"])
                self.assertEqual((self.adapter_state / "fixture-execute-count").read_bytes(), executions)
                self.assertNotIn(b"private-transient-value", ledger.read_bytes())

    def test_concurrent_recovery_at_evidence_aggregate_and_closed_run_boundaries(self) -> None:
        sid = self.ensure("aggregate-crash-seed")["session_id"]
        for boundary in ("evidence", "aggregate", "closed_run"):
            with self.subTest(boundary=boundary):
                correlation = "handoff-crash-" + boundary
                body = {"expected_session_id": sid, "target": "private-handoff-target",
                        "max_tokens": 1024, "render_format": "prompt"}
                ledger, snapshot = self.crash_invocation(PROJECT_MEMORY_HANDOFF, correlation, body, boundary)
                request = snapshot.canonical_requests[correlation]
                self.assertEqual(snapshot.runs[request.run_id].state, "completed" if boundary == "closed_run" else "active")
                self.assertEqual(sum(item.call_id == request.call_id for item in snapshot.handoff_records.values()),
                                 0 if boundary == "evidence" else 1)
                executions = (self.adapter_state / "fixture-execute-count").read_bytes()
                barrier = threading.Barrier(4)
                def recover(_number):
                    barrier.wait(timeout=5)
                    return self.structured(PROJECT_MEMORY_HANDOFF, correlation, body)
                with ThreadPoolExecutor(max_workers=4) as pool:
                    results = list(pool.map(recover, range(4)))
                results.append(self.structured(PROJECT_MEMORY_HANDOFF, correlation, body))
                self.assertEqual(results[-1]["outcome"], "succeeded")
                self.assertEqual({item["call_id"] for item in results}, {request.call_id})
                self.assertEqual({item["evidence_id"] for item in results}, {request.evidence_id})
                self.assertTrue(all(item["status"] in ("completed", "in_progress") for item in results))
                self.assertTrue(all(item["outcome"] == "succeeded" for item in results if item["status"] == "completed"))
                self.assertTrue(all(not item["result_available"] and item["transient_b64"] is None for item in results))
                snapshot = ControlPlaneKernel(ledger).snapshot()
                self.assertEqual(snapshot.runs[request.run_id].state, "completed")
                self.assertEqual(sum(item.call_id == request.call_id for item in snapshot.evidence.values()), 1)
                self.assertEqual(sum(item.call_id == request.call_id for item in snapshot.handoff_records.values()), 1)
                self.assertEqual((self.adapter_state / "fixture-execute-count").read_bytes(), executions)
                self.assertNotIn(b"private-handoff-target", ledger.read_bytes())

    def test_public_route_is_stdin_only_fixed_identity_and_idempotent(self) -> None:
        first = self.ensure()
        self.assertEqual(first["outcome"], "succeeded")
        self.assertFalse(first["result_available"])
        self.assertTrue(first["run_id"].startswith("run-"))
        self.assertTrue(first["call_id"].startswith("call-"))
        self.assertNotEqual(first["memory_op_id"], "public-memory-ensure")
        authoritative = (
            first["run_id"],
            first["call_id"],
            first["decision_id"],
            first["evidence_id"],
        )
        replay = self.ensure()
        self.assertEqual(
            (
                replay["run_id"],
                replay["call_id"],
                replay["decision_id"],
                replay["evidence_id"],
            ),
            authoritative,
        )
        self.assertEqual(
            (self.adapter_state / "fixture-observe-count").read_text(encoding="ascii"),
            "1",
        )
        self.assertEqual(
            (self.adapter_state / "fixture-execute-count").read_text(encoding="ascii"),
            "1",
        )
        ledger = self.state_root / "mainframe" / "control-plane.jsonl"
        self.assertNotIn(b"private-session-name-41af", ledger.read_bytes())

        mismatch = self.invoke(
            PROJECT_MEMORY_ENSURE,
            "public-memory-ensure",
            {"name": "different-private-name"},
        )
        self.assertEqual(mismatch.returncode, 3)
        self.assertEqual(json.loads(mismatch.stdout)["error"]["code"], "binding_mismatch")
        self.assertEqual(
            (self.adapter_state / "fixture-observe-count").read_text(encoding="ascii"),
            "1",
        )

        literal = subprocess.run(
            [
                str(self.cli),
                "project-memory-invoke",
                "--tool-id",
                PROJECT_MEMORY_ENSURE,
                "--input-json",
                "{}",
                "--client-correlation-id",
                "literal-input-denied",
            ],
            cwd=self.workspace,
            env=self.environment(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        self.assertEqual(literal.returncode, 2)
        self.assertEqual(json.loads(literal.stdout)["error"]["code"], "usage_error")

        awm = self.invoke(
            PROJECT_MEMORY_ENSURE,
            "awm-compatible-ensure",
            {"name": "compat"},
            "awm-compatible-v1",
        )
        self.assertEqual(awm.returncode, 0)
        self.assertRegex(awm.stdout, r"^[0-9a-f]{12}\n$")

    def test_ttl_handoff_transience_and_consumed_retry(self) -> None:
        ensured = self.ensure("handoff-seed")
        session_id = ensured["session_id"]
        checkpoint_secret = "checkpoint-secret-8b91"
        checkpoint = self.structured(
            PROJECT_MEMORY_CHECKPOINT,
            "public-memory-checkpoint",
            {
                "expected_session_id": session_id,
                "key": "phase",
                "value": checkpoint_secret,
                "importance": "high",
                "tags": ["reviewed"],
                "ttl_seconds": 60,
            },
        )
        self.assertEqual(checkpoint["receipt"]["retention_class"], "expiring")
        self.assertIsNotNone(checkpoint["receipt"]["expires_at"])
        handoff_secret = "handoff-target-secret-c137"
        handoff_input = {
            "expected_session_id": session_id,
            "target": handoff_secret,
            "max_tokens": 2048,
            "render_format": "json",
        }
        handoff = self.structured(
            PROJECT_MEMORY_HANDOFF,
            "public-memory-handoff",
            handoff_input,
        )
        self.assertTrue(handoff["result_available"])
        package = base64.b64decode(handoff["transient_b64"], validate=True)
        self.assertIn(handoff_secret.encode("utf-8"), package)
        state_before = (
            self.adapter_state / "fixture-map.json"
        ).read_bytes()
        replay = self.structured(
            PROJECT_MEMORY_HANDOFF,
            "public-memory-handoff",
            handoff_input,
        )
        self.assertFalse(replay["result_available"])
        self.assertIsNone(replay["transient_b64"])
        self.assertEqual(
            (self.adapter_state / "fixture-map.json").read_bytes(), state_before
        )
        unavailable = self.invoke(
            PROJECT_MEMORY_HANDOFF,
            "public-memory-handoff",
            handoff_input,
            "awm-compatible-v1",
        )
        self.assertEqual(unavailable.returncode, 66)
        self.assertEqual(unavailable.stdout, "")
        for path in self.state_root.rglob("*"):
            if path.is_file():
                content = path.read_bytes()
                self.assertNotIn(checkpoint_secret.encode("utf-8"), content)
                self.assertNotIn(handoff_secret.encode("utf-8"), content)

    def test_all_six_reads_are_one_consumer_metadata_only_results(self) -> None:
        ensured = self.ensure("read-plane-seed")
        secret = "READ-PLANE-SECRET-c531"
        reads = (
            (PROJECT_MEMORY_SESSION, {}, ensured["session_id"].encode("ascii") + b"\n"),
            (PROJECT_MEMORY_STATUS, {}, b'"status":"active"'),
            (PROJECT_MEMORY_GET, {"key": "private-key", "default": secret}, secret.encode()),
            (PROJECT_MEMORY_SUMMARY, {}, b'"max_tokens":0'),
            (PROJECT_MEMORY_CONTEXT, {"task": secret}, secret.encode()),
            (PROJECT_MEMORY_FIND, {"query": secret}, secret.encode()),
        )
        for index, (tool, tool_input, expected) in enumerate(reads):
            correlation = "public-read-{}".format(index)
            compatible = self.invoke(
                tool,
                correlation + "-awm",
                tool_input,
                "awm-compatible-v1",
            )
            self.assertEqual(compatible.returncode, 0)
            self.assertIn(expected, compatible.stdout.encode("utf-8"))
            first = self.structured(tool, correlation, tool_input)
            self.assertEqual(first["outcome"], "succeeded")
            self.assertTrue(first["result_available"])
            self.assertIsNone(first["memory_id"])
            self.assertIsNone(first["handoff_id"])
            self.assertIsNone(first["memory_record"])
            self.assertIsNone(first["handoff_record"])
            raw = base64.b64decode(first["transient_b64"], validate=True)
            self.assertIn(expected, raw)
            self.assertEqual(first["receipt"]["value_bytes"], len(raw))
            self.assertEqual(first["receipt"]["value_sha256"], sha(raw))
            replay = self.structured(tool, correlation, tool_input)
            self.assertFalse(replay["result_available"])
            self.assertIsNone(replay["transient_b64"])
            unavailable = self.invoke(tool, correlation, tool_input, "awm-compatible-v1")
            self.assertEqual(unavailable.returncode, 66)
            self.assertEqual(unavailable.stdout, "")
        ledger = self.state_root / "mainframe" / "control-plane.jsonl"
        self.assertNotIn(secret.encode(), ledger.read_bytes())
        for path in self.state_root.rglob("*"):
            if path.is_file():
                self.assertNotIn(secret.encode(), path.read_bytes())

    def test_read_mapping_states_and_adapter_tamper_fail_closed(self) -> None:
        absent = self.structured(PROJECT_MEMORY_STATUS, "read-absent", {})
        self.assertEqual(absent["outcome"], "recovery_required")
        self.assertFalse(absent["result_available"])
        self.assertIsNone(absent["session_id"])

        ensured = self.ensure("read-state-seed")
        closed = self.structured(
            PROJECT_MEMORY_CLOSE,
            "read-state-close",
            {"expected_session_id": ensured["session_id"]},
        )
        self.assertEqual(closed["outcome"], "succeeded")
        status = self.structured(PROJECT_MEMORY_STATUS, "read-closed", {})
        self.assertEqual(status["outcome"], "succeeded")
        self.assertIn(
            b'"status":"closed"',
            base64.b64decode(status["transient_b64"], validate=True),
        )

        for key in ("tamper-receipt", "tamper-transient"):
            result = self.structured(
                PROJECT_MEMORY_GET,
                "read-{}".format(key),
                {"key": key, "default": "private-result"},
            )
            self.assertEqual(result["outcome"], "failed")
            self.assertFalse(result["result_available"])
            self.assertIsNone(result["receipt"])

        (self.adapter_state / "fixture-map.json").write_text(
            "not-json\n", encoding="utf-8"
        )
        tampered_mapping = self.invoke(
            PROJECT_MEMORY_STATUS, "read-tampered-mapping", {}
        )
        self.assertNotEqual(tampered_mapping.returncode, 0)
        self.assertEqual(
            json.loads(tampered_mapping.stdout)["error"]["code"],
            "executor_unavailable",
        )

    def test_get_compatibility_allows_an_exact_empty_success_value(self) -> None:
        self.ensure("read-empty-seed")
        result = self.structured(
            PROJECT_MEMORY_GET,
            "read-empty-get",
            {"key": "missing", "default": ""},
        )
        self.assertTrue(result["result_available"])
        self.assertEqual(result["transient_b64"], "")
        awm = self.invoke(
            PROJECT_MEMORY_GET,
            "read-empty-awm",
            {"key": "missing", "default": ""},
            "awm-compatible-v1",
        )
        self.assertEqual(awm.returncode, 0)
        self.assertEqual(awm.stdout, "")

    def test_same_correlation_concurrency_executes_once(self) -> None:
        barrier = threading.Barrier(2)
        results = []
        errors = []

        def call():
            try:
                barrier.wait()
                completed = self.invoke(
                    PROJECT_MEMORY_ENSURE,
                    "concurrent-same-correlation",
                    {"name": "concurrent-private-name"},
                )
                results.append(json.loads(completed.stdout)["result"])
            except Exception as exc:
                errors.append(exc)

        threads = [threading.Thread(target=call), threading.Thread(target=call)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(15)
            self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])
        self.assertEqual(len(results), 2)
        self.assertEqual({item["run_id"] for item in results}, {results[0]["run_id"]})
        self.assertEqual({item["call_id"] for item in results}, {results[0]["call_id"]})
        terminal = self.structured(
            PROJECT_MEMORY_ENSURE,
            "concurrent-same-correlation",
            {"name": "concurrent-private-name"},
        )
        self.assertEqual(terminal["outcome"], "succeeded")
        self.assertEqual(
            (self.adapter_state / "fixture-observe-count").read_text(encoding="ascii"),
            "1",
        )
        self.assertEqual(
            (self.adapter_state / "fixture-execute-count").read_text(encoding="ascii"),
            "1",
        )
        for path in self.state_root.rglob("*"):
            if path.is_file():
                self.assertNotIn(b"concurrent-private-name", path.read_bytes())

    def test_worker_sigkill_closes_liveness_and_leaves_no_adapter_or_child(self) -> None:
        ensured = self.ensure("worker-kill-seed")
        target = "hold-for-worker-kill"
        tool_input = {
            "expected_session_id": ensured["session_id"],
            "target": target,
            "max_tokens": 1024,
            "render_format": "prompt",
        }
        foreground = subprocess.Popen(
            self.command(PROJECT_MEMORY_HANDOFF, "worker-kill", "control-plane-json-v1"),
            cwd=self.workspace,
            env=self.environment(),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        def cleanup_foreground():
            if foreground.poll() is None:
                foreground.kill()
                foreground.wait(timeout=5)
            for stream in (foreground.stdin, foreground.stdout, foreground.stderr):
                if stream is not None and not stream.closed:
                    stream.close()

        self.addCleanup(cleanup_foreground)
        self.assertIsNotNone(foreground.stdin)
        foreground.stdin.write(json.dumps(tool_input))
        foreground.stdin.close()
        pid_paths = [
            self.adapter_state / "fixture-worker-pid",
            self.adapter_state / "fixture-adapter-pid",
            self.adapter_state / "fixture-child-pid",
        ]
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline and not all(path.exists() for path in pid_paths):
            time.sleep(0.02)
        self.assertTrue(all(path.exists() for path in pid_paths))
        worker_pid, adapter_pid, child_pid = [
            int(path.read_text(encoding="ascii")) for path in pid_paths
        ]
        os.kill(worker_pid, signal.SIGKILL)
        cleanup_deadline = time.monotonic() + 5
        while time.monotonic() < cleanup_deadline and (
            self.alive(adapter_pid) or self.alive(child_pid)
        ):
            time.sleep(0.02)
        self.assertFalse(self.alive(adapter_pid))
        self.assertFalse(self.alive(child_pid))
        foreground.wait(timeout=5)
        if foreground.stdout is not None:
            foreground.stdout.read()
            foreground.stdout.close()
        if foreground.stderr is not None:
            foreground.stderr.read()
            foreground.stderr.close()

        recovered = self.structured(
            PROJECT_MEMORY_HANDOFF,
            "worker-kill",
            tool_input,
        )
        self.assertEqual(recovered["outcome"], "recovery_required")
        self.assertFalse(recovered["result_available"])
        self.assertEqual(
            (self.adapter_state / "fixture-execute-count").read_text(encoding="ascii"),
            "2",
        )
        for path in self.state_root.rglob("*"):
            if path.is_file():
                self.assertNotIn(target.encode("utf-8"), path.read_bytes())


if __name__ == "__main__":
    unittest.main()

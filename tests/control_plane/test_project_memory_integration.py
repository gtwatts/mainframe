from __future__ import annotations

import base64
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

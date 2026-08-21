from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "control_plane"))

from mainframe_control_plane import (  # noqa: E402
    CODING_ATOMIC_EDIT,
    CODING_READ_FILE,
    CODING_RUN_BUILD,
    CODING_RUN_TEST,
    CODING_SEARCH_TEXT,
    ControlPlaneKernel,
)


CLI = PROJECT_ROOT / "control_plane" / "mainframe-control-plane"


class PublicCodingInvokeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(os.path.realpath(self.temporary.name))
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        self.state_root = self.root / "state"
        self.state_root.mkdir(mode=0o700)

    def environment(self):
        return {
            "PATH": "/poisoned",
            "PYTHONPATH": "/poisoned",
            "PYTHONHOME": "/poisoned",
            "HOME": "/poisoned",
            "TMPDIR": "/tmp",
            "XDG_STATE_HOME": str(self.state_root),
        }

    def invoke(self, tool, tool_input, presentation="control-plane-json-v1", extra=()):
        return subprocess.run(
            [
                str(CLI),
                "coding-invoke",
                "--tool-id",
                tool,
                "--input-json",
                "-",
                "--format",
                presentation,
                *extra,
            ],
            input=json.dumps(tool_input).encode("utf-8"),
            cwd=self.workspace,
            env=self.environment(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=10,
        )

    @property
    def ledger(self):
        return self.state_root / "mainframe" / "control-plane.jsonl"

    def test_structured_and_raw_reads_are_transient_with_generated_identity(self) -> None:
        source_secret = b"PUBLIC-CODING-SOURCE-614e\n"
        query_secret = "CODING-SOURCE-614e"
        (self.workspace / "source.txt").write_bytes(source_secret)

        structured = self.invoke(CODING_READ_FILE, {"path": "source.txt"})
        self.assertEqual(structured.returncode, 0, structured.stdout)
        self.assertEqual(structured.stderr, b"")
        payload = json.loads(structured.stdout)
        self.assertEqual(set(payload), {"command", "ok", "result"})
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["command"], "coding-invoke")
        result = payload["result"]
        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["outcome"], "succeeded")
        self.assertTrue(result["result_available"])
        self.assertTrue(result["client_correlation_id"].startswith("coding-"))
        self.assertEqual(base64.b64decode(result["stdout_b64"]), source_secret)
        self.assertEqual(base64.b64decode(result["stderr_b64"]), b"")
        self.assertEqual(result["receipt"]["decision_id"], result["decision_id"])
        self.assertEqual(result["receipt"]["evidence_id"], result["evidence_id"])

        raw = self.invoke(CODING_READ_FILE, {"path": "source.txt"}, "raw")
        self.assertEqual(raw.returncode, 0)
        self.assertEqual(raw.stdout, source_secret)
        self.assertEqual(raw.stderr, b"")

        searched = self.invoke(
            CODING_SEARCH_TEXT,
            {"path": "source.txt", "query": query_secret},
        )
        self.assertEqual(searched.returncode, 0, searched.stdout)
        search_result = json.loads(searched.stdout)["result"]
        self.assertIn(source_secret.rstrip(), base64.b64decode(search_result["stdout_b64"]))

        persisted = b"".join(
            path.read_bytes()
            for path in self.state_root.rglob("*")
            if path.is_file() and not path.is_symlink()
        )
        self.assertNotIn(source_secret.rstrip(), persisted)
        self.assertNotIn(query_secret.encode("utf-8"), persisted)
        snapshot = ControlPlaneKernel(self.ledger).snapshot()
        call = snapshot.tool_calls[result["call_id"]]
        self.assertIsNone(call.tool_input)
        self.assertEqual(call.effect, "read_only")
        self.assertEqual(snapshot.runs[result["run_id"]].state, "completed")
        self.assertEqual(
            snapshot.canonical_requests[result["client_correlation_id"]].evidence_id,
            result["evidence_id"],
        )

    def test_public_mutation_and_code_execution_wait_without_executing(self) -> None:
        target = self.workspace / "target.txt"
        target.write_text("before", encoding="utf-8")
        invocations = (
            (
                CODING_ATOMIC_EDIT,
                {
                    "path": "target.txt",
                    "expected_sha256": "6db7d803e74f9159b13ea4b37a5a8c65d6d74659d17a83f5f1a05a44b99d6ac3",
                    "content": "must-not-write",
                },
            ),
            (CODING_RUN_TEST, {}),
            (CODING_RUN_BUILD, {}),
        )
        for tool, tool_input in invocations:
            completed = self.invoke(tool, tool_input)
            self.assertEqual(completed.returncode, 0, completed.stdout)
            self.assertEqual(completed.stderr, b"")
            result = json.loads(completed.stdout)["result"]
            self.assertEqual(result["status"], "awaiting_approval")
            self.assertIsNone(result["outcome"])
            self.assertFalse(result["result_available"])
            self.assertIsNone(result["approval_id"])
            self.assertTrue(result["evidence_id"].startswith("evidence-"))
            snapshot = ControlPlaneKernel(self.ledger).snapshot()
            self.assertEqual(snapshot.tool_calls[result["call_id"]].state, "awaiting_approval")
            self.assertEqual(
                snapshot.policy_decisions[result["decision_id"]].outcome,
                "approval_required",
            )
        self.assertEqual(target.read_text(encoding="utf-8"), "before")
        self.assertNotIn(b"must-not-write", self.ledger.read_bytes())

        pending_raw = self.invoke(CODING_RUN_TEST, {}, "raw")
        self.assertEqual(pending_raw.returncode, 75)
        self.assertEqual(pending_raw.stdout, b"")
        self.assertEqual(pending_raw.stderr, b"")

    def test_public_grammar_rejects_value_argv_and_authority_selectors(self) -> None:
        literal = subprocess.run(
            [
                str(CLI),
                "coding-invoke",
                "--tool-id",
                CODING_READ_FILE,
                "--input-json",
                '{"path":"source.txt"}',
            ],
            cwd=self.workspace,
            env=self.environment(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(literal.returncode, 2)
        self.assertEqual(json.loads(literal.stdout)["error"]["code"], "usage_error")

        for selector in (
            ("--approval-id", "approval-forged"),
            ("--client-correlation-id", "caller-id"),
            ("--actor", "caller-actor"),
            ("--workspace", str(self.root)),
        ):
            forged = self.invoke(
                CODING_READ_FILE,
                {"path": "source.txt"},
                extra=selector,
            )
            self.assertEqual(forged.returncode, 2)
            self.assertEqual(
                json.loads(forged.stdout)["error"]["code"], "usage_error"
            )

        for tool, tool_input in (
            (CODING_RUN_TEST, {"argv": ["sh", "-c", "exit 0"]}),
            (CODING_READ_FILE, {"path": "source.txt", "env": {"PATH": "/tmp"}}),
        ):
            injected = self.invoke(tool, tool_input)
            self.assertEqual(injected.returncode, 3)
            self.assertEqual(
                json.loads(injected.stdout)["error"]["code"], "execution_denied"
            )

        caller_ledger = self.root / "caller-selected.jsonl"
        selected = subprocess.run(
            [
                str(CLI),
                "--ledger",
                str(caller_ledger),
                "coding-invoke",
                "--tool-id",
                CODING_READ_FILE,
                "--input-json",
                "-",
            ],
            input=b'{"path":"source.txt"}',
            cwd=self.workspace,
            env=self.environment(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(selected.returncode, 2)
        self.assertEqual(json.loads(selected.stdout)["error"]["code"], "usage_error")
        self.assertFalse(caller_ledger.exists())


if __name__ == "__main__":
    unittest.main()

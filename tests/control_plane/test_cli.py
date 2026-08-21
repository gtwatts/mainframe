from __future__ import annotations

import json
import io
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
CLI = PROJECT_ROOT / "control_plane" / "mainframe-control-plane"
sys.path.insert(0, str(PROJECT_ROOT / "control_plane"))

from mainframe_control_plane import (  # noqa: E402
    ApprovalGrantRequest,
    ControlPlaneKernel,
    PolicyEvaluation,
)
from mainframe_control_plane.cli import main as cli_main  # noqa: E402


class StructuredCliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(self.temp_dir.name)
        self.ledger = self.root / "ledger.jsonl"
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()

    def run_cli(self, *args: str):
        environment = os.environ.copy()
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        completed = subprocess.run(
            [str(CLI), "--ledger", str(self.ledger), *args],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=environment,
        )
        self.assertEqual(completed.stderr, "")
        return completed, json.loads(completed.stdout)

    def run_embedded_cli(self, *args: str, clock=None, trusted_approver=None):
        output = io.StringIO()

        def evaluator(request):
            outcome = "allow" if request.effect == "read_only" else "approval_required"
            return PolicyEvaluation(
                outcome,
                "policy-engine:embedded-test",
                "trusted embedded evaluator",
            )

        code = cli_main(
            ["--ledger", str(self.ledger), *args],
            stdout=output,
            evaluator=evaluator,
            trusted_approver=trusted_approver,
            clock=clock,
        )
        return code, json.loads(output.getvalue())

    def test_cli_emits_json_for_commands_and_executor_denial(self) -> None:
        completed, payload = self.run_cli(
            "run-create",
            "--run-id",
            "run-cli",
            "--actor",
            "agent:cli",
            "--workspace",
            str(self.workspace),
            "--policy",
            "local-reviewed-v1",
        )
        self.assertEqual(completed.returncode, 0)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["result"]["state"], "created")

        completed, payload = self.run_cli(
            "run-transition", "--run-id", "run-cli", "--to", "active"
        )
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(payload["result"]["state"], "active")

        completed, payload = self.run_cli(
            "call-create",
            "--call-id",
            "call-cli",
            "--run-id",
            "run-cli",
            "--tool",
            "control_plane.trace",
            "--effect",
            "read_only",
            "--input-json",
            '{"message":"hello"}',
        )
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(payload["result"]["state"], "pending")
        call = payload["result"]

        completed, payload = self.run_cli(
            "decision-evaluate",
            "--decision-id",
            "decision-cli",
            "--call-id",
            call["call_id"],
            "--tool",
            call["tool"],
            "--input-digest",
            call["input_digest"],
            "--actor",
            call["actor"],
            "--workspace",
            call["workspace"],
            "--policy",
            call["policy"],
        )
        self.assertEqual(completed.returncode, 3)
        self.assertEqual(payload["error"]["code"], "evaluator_unavailable")

        code, payload = self.run_embedded_cli(
            "decision-evaluate",
            "--decision-id",
            "decision-cli",
            "--call-id",
            call["call_id"],
            "--tool",
            call["tool"],
            "--input-digest",
            call["input_digest"],
            "--actor",
            call["actor"],
            "--workspace",
            call["workspace"],
            "--policy",
            call["policy"],
        )
        self.assertEqual(code, 0)
        self.assertEqual(payload["result"]["outcome"], "allow")

        completed, payload = self.run_cli(
            "trace-execute", "--call-id", "call-cli"
        )
        self.assertEqual(completed.returncode, 3)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["error"]["code"], "executor_unavailable")

        completed, payload = self.run_cli("show")
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(payload["result"]["tool_calls"]["call-cli"]["state"], "ready")
        self.assertIn("decision-cli", payload["result"]["policy_decisions"])

        completed, payload = self.run_cli(
            "call-create",
            "--call-id",
            "call-not-an-object",
            "--run-id",
            "run-cli",
            "--tool",
            "control_plane.trace",
            "--effect",
            "read_only",
            "--input-json",
            "[]",
        )
        self.assertEqual(completed.returncode, 2)
        self.assertEqual(payload["error"]["code"], "validation_error")

    def test_cli_reports_usage_and_corruption_as_json_without_tracebacks(self) -> None:
        completed, payload = self.run_cli()
        self.assertEqual(completed.returncode, 2)
        self.assertEqual(payload["error"]["code"], "usage_error")

        self.ledger.write_bytes(b'{"broken":\n')
        self.ledger.chmod(0o600)
        completed, payload = self.run_cli("show")
        self.assertEqual(completed.returncode, 4)
        self.assertEqual(payload["error"]["code"], "ledger_corruption")
        self.assertNotIn("Traceback", completed.stdout)

    def test_public_cli_cannot_self_author_allow_or_forge_authority(self) -> None:
        completed, payload = self.run_cli(
            "decision-evaluate",
            "--decision-id",
            "decision-forged",
            "--call-id",
            "call-forged",
            "--tool",
            "control_plane.trace",
            "--input-digest",
            "0" * 64,
            "--actor",
            "agent:attacker",
            "--workspace",
            str(self.workspace),
            "--policy",
            "local-reviewed-v1",
            "--outcome",
            "allow",
            "--authority",
            "policy-engine:forged",
        )
        self.assertEqual(completed.returncode, 2)
        self.assertEqual(payload["error"]["code"], "usage_error")
        self.assertFalse(self.ledger.exists())

        completed, payload = self.run_cli(
            "decision-evaluate",
            "--decision-id",
            "decision-no-evaluator",
            "--call-id",
            "call-forged",
            "--tool",
            "control_plane.trace",
            "--input-digest",
            "0" * 64,
            "--actor",
            "agent:attacker",
            "--workspace",
            str(self.workspace),
            "--policy",
            "local-reviewed-v1",
        )
        self.assertEqual(completed.returncode, 3)
        self.assertEqual(payload["error"]["code"], "evaluator_unavailable")
        self.assertFalse(self.ledger.exists())

    def test_cli_executes_only_the_approval_bound_disposable_write(self) -> None:
        sentinel = self.workspace / ".mainframe-disposable-workspace"
        sentinel.write_bytes(b"MAINFRAME_DISPOSABLE_WORKSPACE_V1\n")
        completed, payload = self.run_cli(
            "run-create",
            "--run-id",
            "run-write",
            "--actor",
            "agent:cli",
            "--workspace",
            str(self.workspace),
            "--policy",
            "local-reviewed-v1",
        )
        self.assertEqual(completed.returncode, 0)
        completed, _ = self.run_cli(
            "run-transition", "--run-id", "run-write", "--to", "active"
        )
        self.assertEqual(completed.returncode, 0)
        completed, payload = self.run_cli(
            "call-create",
            "--call-id",
            "call-write",
            "--run-id",
            "run-write",
            "--tool",
            "control_plane.disposable_write",
            "--effect",
            "mutating",
            "--input-json",
            '{"content":"cli payload","path":"result.txt"}',
        )
        self.assertEqual(completed.returncode, 0)
        call = payload["result"]
        code, _ = self.run_embedded_cli(
            "decision-evaluate",
            "--decision-id",
            "decision-write",
            "--call-id",
            call["call_id"],
            "--tool",
            call["tool"],
            "--input-digest",
            call["input_digest"],
            "--actor",
            call["actor"],
            "--workspace",
            call["workspace"],
            "--policy",
            call["policy"],
        )
        self.assertEqual(code, 0)
        expiry = (datetime.now(timezone.utc) + timedelta(minutes=5)).isoformat().replace(
            "+00:00", "Z"
        )
        completed, payload = self.run_cli(
            "approval-grant",
            "--approval-id",
            "approval-write",
            "--call-id",
            "call-write",
            "--tool",
            call["tool"],
            "--input-digest",
            call["input_digest"],
            "--actor",
            call["actor"],
            "--workspace",
            call["workspace"],
            "--policy",
            call["policy"],
            "--expires-at",
            expiry,
        )
        self.assertEqual(completed.returncode, 3)
        self.assertEqual(payload["error"]["code"], "approval_authority_unavailable")

        observed_requests = []

        def trusted_approver(request: ApprovalGrantRequest) -> str:
            observed_requests.append(request)
            return "human:verified-reviewer"

        code, payload = self.run_embedded_cli(
            "approval-grant",
            "--approval-id",
            "approval-caller-authored",
            "--call-id",
            "call-write",
            "--tool",
            call["tool"],
            "--input-digest",
            call["input_digest"],
            "--actor",
            call["actor"],
            "--workspace",
            call["workspace"],
            "--policy",
            call["policy"],
            "--approver",
            "agent:attacker",
            "--expires-at",
            expiry,
            trusted_approver=trusted_approver,
        )
        self.assertEqual(code, 2)
        self.assertEqual(payload["error"]["code"], "usage_error")
        self.assertEqual(observed_requests, [])

        code, payload = self.run_embedded_cli(
            "approval-grant",
            "--approval-id",
            "approval-forged",
            "--call-id",
            "call-write",
            "--tool",
            call["tool"],
            "--input-digest",
            "0" * 64,
            "--actor",
            call["actor"],
            "--workspace",
            call["workspace"],
            "--policy",
            call["policy"],
            "--expires-at",
            expiry,
            trusted_approver=trusted_approver,
        )
        self.assertEqual(code, 3)
        self.assertEqual(payload["error"]["code"], "binding_mismatch")
        self.assertEqual(observed_requests, [])

        code, payload = self.run_embedded_cli(
            "approval-grant",
            "--approval-id",
            "approval-write",
            "--call-id",
            "call-write",
            "--tool",
            call["tool"],
            "--input-digest",
            call["input_digest"],
            "--actor",
            call["actor"],
            "--workspace",
            call["workspace"],
            "--policy",
            call["policy"],
            "--expires-at",
            expiry,
            trusted_approver=trusted_approver,
        )
        self.assertEqual(code, 0)
        self.assertEqual(payload["result"]["approver"], "human:verified-reviewer")
        self.assertEqual(len(observed_requests), 1)
        self.assertEqual(observed_requests[0].approval_id, "approval-write")
        self.assertEqual(observed_requests[0].call_id, call["call_id"])
        self.assertEqual(observed_requests[0].tool, call["tool"])
        self.assertEqual(observed_requests[0].input_digest, call["input_digest"])
        self.assertEqual(observed_requests[0].actor, call["actor"])
        self.assertEqual(observed_requests[0].workspace, call["workspace"])
        self.assertEqual(observed_requests[0].policy, call["policy"])
        self.assertEqual(observed_requests[0].expires_at, expiry)
        self.assertEqual(
            ControlPlaneKernel(self.ledger).lookup("approval", "approval-write").approver,
            "human:verified-reviewer",
        )
        completed, payload = self.run_cli(
            "disposable-write-execute",
            "--call-id",
            "call-write",
            "--approval-id",
            "approval-write",
            "--actor",
            call["actor"],
            "--workspace",
            call["workspace"],
            "--policy",
            call["policy"],
        )
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(payload["result"]["approval_id"], "approval-write")
        self.assertEqual((self.workspace / "result.txt").read_text(), "cli payload")

    def test_entrypoint_ignores_poisoned_path_python(self) -> None:
        fake_bin = self.root / "fake-bin"
        fake_bin.mkdir()
        marker = self.root / "ambient-python-ran"
        fake_python = fake_bin / "python3"
        fake_python.write_text(
            "#!/bin/sh\nprintf 'poisoned\\n' > {!r}\nexit 97\n".format(str(marker)),
            encoding="utf-8",
        )
        fake_python.chmod(0o755)
        environment = os.environ.copy()
        environment["PATH"] = str(fake_bin)
        environment["PYTHONPATH"] = str(self.root / "poisoned-modules")
        completed = subprocess.run(
            [str(CLI), "--ledger", str(self.ledger), "show"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=environment,
        )
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(completed.stderr, "")
        self.assertTrue(json.loads(completed.stdout)["ok"])
        self.assertFalse(marker.exists())

    def test_public_canonical_cli_uses_fixed_registry_and_fails_closed_without_seams(self) -> None:
        completed, _ = self.run_cli(
            "run-create",
            "--run-id",
            "run-canonical",
            "--actor",
            "agent:cli",
            "--workspace",
            str(self.workspace),
            "--policy",
            "stable-core-v1",
        )
        self.assertEqual(completed.returncode, 0)
        completed, _ = self.run_cli(
            "run-transition", "--run-id", "run-canonical", "--to", "active"
        )
        self.assertEqual(completed.returncode, 0)
        completed, payload = self.run_cli(
            "canonical-call-create",
            "--call-id",
            "call-canonical",
            "--run-id",
            "run-canonical",
            "--canonical-id",
            "mf:std:pure-string:to_upper",
            "--input-json",
            '{"value":"hello"}',
        )
        self.assertEqual(completed.returncode, 0)
        call = payload["result"]
        self.assertEqual(call["tool"], "mf:std:pure-string:to_upper")
        self.assertEqual(call["state"], "pending")
        self.assertIsNotNone(call["timeout_at"])

        completed, payload = self.run_cli(
            "canonical-execute", "--call-id", call["call_id"]
        )
        self.assertEqual(completed.returncode, 3)
        self.assertEqual(payload["error"]["code"], "executor_unavailable")
        completed, payload = self.run_cli(
            "lookup",
            "--record-kind",
            "tool_call",
            "--record-id",
            call["call_id"],
        )
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(payload["result"]["state"], "pending")

        completed, payload = self.run_cli(
            "canonical-call-create",
            "--call-id",
            "call-unknown",
            "--run-id",
            "run-canonical",
            "--canonical-id",
            "mf:std:forged:run_anything",
            "--input-json",
            "{}",
        )
        self.assertEqual(completed.returncode, 3)
        self.assertEqual(payload["error"]["code"], "execution_denied")

    def test_public_lifecycle_commands_bind_identity_and_recover_running_calls(self) -> None:
        completed, _ = self.run_cli(
            "run-create",
            "--run-id",
            "run-lifecycle",
            "--actor",
            "agent:cli",
            "--workspace",
            str(self.workspace),
            "--policy",
            "local-reviewed-v1",
        )
        self.assertEqual(completed.returncode, 0)
        completed, _ = self.run_cli(
            "run-transition", "--run-id", "run-lifecycle", "--to", "active"
        )
        self.assertEqual(completed.returncode, 0)

        def create_and_allow(call_id: str, timeout_at=None):
            arguments = [
                "call-create",
                "--call-id",
                call_id,
                "--run-id",
                "run-lifecycle",
                "--tool",
                "control_plane.trace",
                "--effect",
                "read_only",
                "--input-json",
                '{"message":"observe"}',
            ]
            if timeout_at is not None:
                arguments.extend(("--timeout-at", timeout_at))
            completed, payload = self.run_cli(*arguments)
            self.assertEqual(completed.returncode, 0)
            call = payload["result"]
            code, _ = self.run_embedded_cli(
                "decision-evaluate",
                "--decision-id",
                "decision-{}".format(call_id),
                "--call-id",
                call_id,
                "--tool",
                call["tool"],
                "--input-digest",
                call["input_digest"],
                "--actor",
                call["actor"],
                "--workspace",
                call["workspace"],
                "--policy",
                call["policy"],
                *(('--timeout-at', call["timeout_at"]) if call["timeout_at"] else ()),
            )
            self.assertEqual(code, 0)
            return call

        cancelled_call = create_and_allow("call-cancel-cli")
        completed, payload = self.run_cli(
            "call-cancel",
            "--call-id",
            cancelled_call["call_id"],
            "--tool",
            cancelled_call["tool"],
            "--input-digest",
            cancelled_call["input_digest"],
            "--actor",
            cancelled_call["actor"],
            "--workspace",
            cancelled_call["workspace"],
            "--policy",
            cancelled_call["policy"],
            "--reason",
            "caller cancellation",
        )
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(payload["result"]["state"], "cancelled")

        deadline = datetime.now(timezone.utc) + timedelta(minutes=1)
        deadline_text = deadline.isoformat().replace("+00:00", "Z")
        timed_call = create_and_allow("call-timeout-cli", deadline_text)
        code, payload = self.run_embedded_cli(
            "call-timeout",
            "--call-id",
            timed_call["call_id"],
            "--tool",
            timed_call["tool"],
            "--input-digest",
            timed_call["input_digest"],
            "--actor",
            timed_call["actor"],
            "--workspace",
            timed_call["workspace"],
            "--policy",
            timed_call["policy"],
            "--reason",
            "deadline elapsed",
            clock=lambda: deadline,
        )
        self.assertEqual(code, 0)
        self.assertEqual(payload["result"]["state"], "timed_out")

        running_call = create_and_allow("call-recover-cli")
        kernel = ControlPlaneKernel(self.ledger)
        with self.assertRaises(SystemExit):
            kernel.execute_read_only(
                running_call["call_id"],
                lambda _tool, _input: (_ for _ in ()).throw(SystemExit("crash")),
            )
        completed, payload = self.run_cli(
            "call-recover",
            "--call-id",
            running_call["call_id"],
            "--tool",
            running_call["tool"],
            "--input-digest",
            running_call["input_digest"],
            "--actor",
            running_call["actor"],
            "--workspace",
            running_call["workspace"],
            "--policy",
            running_call["policy"],
            "--reason",
            "restart recovery",
        )
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(payload["result"]["state"], "interrupted")


if __name__ == "__main__":
    unittest.main()

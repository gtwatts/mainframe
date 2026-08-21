from __future__ import annotations

import base64
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "control_plane"))

from mainframe_control_plane import (  # noqa: E402
    CanonicalExecutionResult,
    ControlPlaneKernel,
    ExecutionDenied,
    PolicyEvaluation,
    RegistryCorruption,
    load_fixed_stable_core_registry,
)
from mainframe_control_plane.contracts import (  # noqa: E402
    _load_stable_core_registry_from_root,
)


class StableCoreTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(self.temp_dir.name)
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        self.ledger = self.root / "ledger.jsonl"
        self.registry = load_fixed_stable_core_registry()

        def evaluator(_request):
            return PolicyEvaluation(
                "allow", "policy-engine:stable-core-v1", "reviewed stable-core call"
            )

        self.kernel = ControlPlaneKernel(
            self.ledger,
            evaluator=evaluator,
            stable_core_registry=self.registry,
        )
        self.kernel.create_run(
            run_id="run-stable",
            actor="agent:codex",
            workspace=str(self.workspace),
            policy="stable-core-v1",
        )
        self.kernel.transition_run("run-stable", "active")

    def test_fixed_registry_is_closed_and_normalizes_typed_defaults(self) -> None:
        self.assertEqual(len(self.registry.contracts), 26)
        effects = [contract.effect for contract in self.registry.contracts.values()]
        self.assertEqual(effects.count("read"), 1)
        self.assertEqual(effects.count("pure"), 25)
        normalized = self.registry.normalize_input(
            "mf:std:validation:validate_int", {"value": "10", "max": "20"}
        )
        self.assertEqual(normalized, {"value": "10", "min": "", "max": "20"})
        with self.assertRaises(ExecutionDenied):
            self.registry.normalize_input(
                "mf:std:validation:validate_int",
                {"value": "10", "command": "/tmp/attacker"},
            )
        with self.assertRaises(ExecutionDenied):
            self.registry.contract("to_upper")

    def test_registry_corruption_and_version_mismatch_fail_closed(self) -> None:
        release = self.root / "release"
        release.mkdir()
        shutil.copy2(PROJECT_ROOT / "VERSION", release / "VERSION")
        value = json.loads((PROJECT_ROOT / "INVOCATION_INDEX.json").read_text())
        value["contracts"]["mf:std:pure-string:to_upper"]["effects"] = ["write"]
        (release / "INVOCATION_INDEX.json").write_text(
            json.dumps(value, separators=(",", ":"), sort_keys=True) + "\n",
            encoding="utf-8",
        )
        with self.assertRaises(RegistryCorruption):
            _load_stable_core_registry_from_root(release)

        value["contracts"]["mf:std:pure-string:to_upper"]["effects"] = ["pure"]
        value["version"] = "999.0.0"
        (release / "INVOCATION_INDEX.json").write_text(
            json.dumps(value, separators=(",", ":"), sort_keys=True) + "\n",
            encoding="utf-8",
        )
        with self.assertRaises(RegistryCorruption):
            _load_stable_core_registry_from_root(release)

    def test_kernel_owns_canonical_execution_and_evidence(self) -> None:
        call = self.kernel.create_canonical_tool_call(
            call_id="call-stable",
            run_id="run-stable",
            canonical_id="mf:std:pure-string:to_upper",
            tool_input={"value": "hello"},
        )
        decision = self.kernel.evaluate_policy_decision(
            decision_id="decision-stable",
            call_id=call.call_id,
            tool=call.tool,
            input_digest=call.input_digest,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
            timeout_at=call.timeout_at,
        )
        self.assertEqual(decision.outcome, "allow")
        observed = []

        def executor(canonical_id, tool_input):
            observed.append((canonical_id, tool_input))
            return CanonicalExecutionResult(
                outcome="succeeded",
                envelope={
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
                    "audit_id": "inv-test-1",
                    "stdout_b64": base64.b64encode(b"HELLO\n").decode("ascii"),
                    "stderr_b64": "",
                    "error": None,
                },
            )

        evidence = self.kernel.execute_canonical(
            call.call_id, executor=executor
        )
        self.assertEqual(
            observed,
            [("mf:std:pure-string:to_upper", {"value": "hello"})],
        )
        self.assertEqual(evidence.outcome, "succeeded")
        self.assertEqual(evidence.tool, call.tool)
        self.assertEqual(
            evidence.body["broker_receipt"]["canonical_id"], call.tool
        )
        self.assertNotIn("stdout_b64", evidence.body["broker_receipt"])
        self.assertEqual(evidence.body["broker_receipt"]["stdout_bytes"], 6)
        restarted = ControlPlaneKernel(self.ledger)
        self.assertEqual(restarted.lookup("evidence", evidence.evidence_id), evidence)

    def test_unknown_or_malformed_executor_result_is_durable_failure(self) -> None:
        call = self.kernel.create_canonical_tool_call(
            call_id="call-bad-result",
            run_id="run-stable",
            canonical_id="mf:std:pure-string:to_lower",
            tool_input={"value": "HELLO"},
        )
        self.kernel.evaluate_policy_decision(
            decision_id="decision-bad-result",
            call_id=call.call_id,
            tool=call.tool,
            input_digest=call.input_digest,
            actor=call.actor,
            workspace=call.workspace,
            policy=call.policy,
            timeout_at=call.timeout_at,
        )

        evidence = self.kernel.execute_canonical(
            call.call_id,
            executor=lambda _canonical_id, _tool_input: CanonicalExecutionResult(
                "succeeded", {"canonical_id": "mf:forged:id:value"}
            ),
        )
        self.assertEqual(evidence.outcome, "failed")
        self.assertEqual(evidence.body["error"]["code"], "invalid_executor_result")
        self.assertEqual(self.kernel.snapshot().tool_calls[call.call_id].state, "failed")


if __name__ == "__main__":
    unittest.main()

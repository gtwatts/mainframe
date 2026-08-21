from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "control_plane"))

from mainframe_control_plane import (  # noqa: E402
    BindingMismatch,
    CanonicalExecutionResult,
    ControlPlaneKernel,
    FixedStableCoreEvaluator,
    InvalidTransition,
    STABLE_CORE_POLICY,
    load_fixed_stable_core_registry,
)
from mainframe_control_plane.transient import (  # noqa: E402
    decode_canonical_result,
    encode_canonical_result,
)
from mainframe_control_plane.cli import _canonical_result  # noqa: E402


class TransientTransportTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(os.path.realpath(self.temporary.name))
        self.root.chmod(0o700)
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        self.ledger = self.root / "ledger.jsonl"

    def test_tampered_anonymous_envelope_cannot_override_durable_receipt(self) -> None:
        registry = load_fixed_stable_core_registry()
        kernel = ControlPlaneKernel(
            self.ledger,
            evaluator=FixedStableCoreEvaluator(registry),
            stable_core_registry=registry,
        )
        tool_input = {"value": "secret-result-4ba7"}
        request = kernel.reserve_canonical_request(
            client_correlation_id="tamper-result",
            canonical_id="mf:std:pure-string:to_upper",
            tool_input=tool_input,
            actor="agent:test",
            workspace=str(self.workspace),
            policy=STABLE_CORE_POLICY,
        )
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
            tool_input=tool_input,
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
            tool_input=tool_input,
        )
        envelope = {
            "schema_version": 1,
            "ok": True,
            "status": "success",
            "canonical_id": call.tool,
            "name": "to_upper",
            "owner": "pure-string",
            "exit_code": 0,
            "timed_out": False,
            "output_exceeded": False,
            "duration_ms": 1,
            "audit_id": "inv-transient-test",
            "stdout_b64": base64.b64encode(b"SECRET-RESULT-4BA7\n").decode("ascii"),
            "stderr_b64": "",
            "error": None,
        }
        observed = []

        def failing_sink(result):
            observed.append(result)
            raise OSError("injected transient result channel failure")

        evidence = kernel.execute_canonical(
            call.call_id,
            executor=lambda _tool, _input: CanonicalExecutionResult(
                "succeeded", envelope
            ),
            tool_input=tool_input,
            result_sink=failing_sink,
        )
        snapshot = kernel.snapshot()
        self.assertEqual(snapshot.runs[request.run_id].state, "completed")
        self.assertEqual(
            len(
                [
                    item
                    for item in snapshot.evidence.values()
                    if item.call_id == call.call_id
                ]
            ),
            1,
        )
        self.assertFalse(_canonical_result(kernel, call.call_id)["result_available"])
        self.assertEqual(len(observed), 1)
        with self.assertRaises(InvalidTransition):
            kernel.execute_canonical(
                call.call_id,
                executor=lambda _tool, _input: self.fail("must not re-execute"),
                tool_input=tool_input,
            )
        encoded = encode_canonical_result(request, observed[0])
        payload = json.loads(encoded.decode("utf-8"))
        payload["broker_envelope"]["stdout_b64"] = base64.b64encode(
            b"FORGED\n"
        ).decode("ascii")
        tampered = json.dumps(
            payload, separators=(",", ":"), sort_keys=True
        ).encode("utf-8")

        with self.assertRaises(BindingMismatch):
            decode_canonical_result(
                tampered,
                request,
                kernel.snapshot().tool_calls[call.call_id],
                evidence,
                registry.contract(call.tool),
            )


if __name__ == "__main__":
    unittest.main()

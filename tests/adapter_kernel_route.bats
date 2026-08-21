#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
}

@test "adapter kernel route: Pi Node and Python request control-plane JSON with generated correlation" {
    run python3 - "$PROJECT_ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
regions = {
    "pi": (root / "skills/pi/extensions/mainframe.ts", "const cliArgs = [", "const envelopeLimit"),
    "node": (root / "bindings/nodejs/src/core.ts", "const brokerArgs = [", "const result = runBoundedBrokerProcess"),
    "python": (root / "bindings/python/mainframe_bash/core.py", "command = [", "stdout, stderr, returncode"),
}
for name, (path, start, end) in regions.items():
    text = path.read_text(encoding="utf-8")
    region = text.split(start, 1)[1].split(end, 1)[0]
    assert '"control-plane-json-v1"' in region, (name, "format")
    assert '"--client-correlation-id"' in region, (name, "correlation flag")
    assert '"broker-json-v1"' not in region, (name, "legacy presentation")
print("adapter_routes=durable")
PY

    [[ "$status" -eq 0 ]]
    [[ "$output" == "adapter_routes=durable" ]]
}

@test "adapter kernel route: canonical APIs expose strict durable identity and receipt fields" {
    run python3 - "$PROJECT_ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
required = (
    "clientCorrelationId", "runId", "callId", "decisionId", "evidenceId",
    "inputDigest", "resultAvailable", "brokerReceipt",
)
node = (root / "bindings/nodejs/src/core.ts").read_text(encoding="utf-8")
pi = (root / "skills/pi/extensions/mainframe.ts").read_text(encoding="utf-8")
for field in required:
    assert field in node, ("node", field)
    assert field in pi, ("pi", field)

python = (root / "bindings/python/mainframe_bash/core.py").read_text(encoding="utf-8")
for field in (
    "client_correlation_id", "run_id", "call_id", "decision_id", "evidence_id",
    "input_digest", "result_available", "broker_receipt",
):
    assert field in python, ("python", field)
print("adapter_identity=exposed")
PY

    [[ "$status" -eq 0 ]]
    [[ "$output" == "adapter_identity=exposed" ]]
}

@test "adapter kernel route: reviewed convenience exports cannot use legacy runners" {
    run python3 - "$PROJECT_ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
for relative in (
    "bindings/nodejs/src/json.ts",
    "bindings/nodejs/src/validation.ts",
    "bindings/python/mainframe_bash/json_funcs.py",
    "bindings/python/mainframe_bash/validation.py",
):
    text = (root / relative).read_text(encoding="utf-8")
    assert "internal/legacy" not in text, relative
    assert "_legacy_call_function" not in text, relative
print("reviewed_convenience=durable")
PY

    [[ "$status" -eq 0 ]]
    [[ "$output" == "reviewed_convenience=durable" ]]
}

@test "adapter kernel route: Pi async cancellation uses only its generated correlation ID" {
    run python3 - "$PROJECT_ROOT/skills/pi/extensions/mainframe.ts" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
cancel = text.split("async function requestDurableCancellation(", 1)[1].split(
    "function successfulBrokerResultText", 1
)[0]
assert '["invoke", "cancel", "--client-correlation-id", correlationId]' in cancel
for forbidden in (
    "--run-id", "--call-id", "--decision-id", "--evidence-id", "--actor",
    "--policy", "--authority", "--outcome", "--ledger", "--format",
):
    assert forbidden not in cancel, forbidden
stable = text.split("if (manifestClaimsStableCore(found))", 1)[1].split(
    "const risk = catalogRisk", 1
)[0]
assert "client-pi-" in stable
assert "cancel: () => requestDurableCancellation(" in stable
print("pi_cancellation=cid_only")
PY

    [[ "$status" -eq 0 ]]
    [[ "$output" == "pi_cancellation=cid_only" ]]
}

@test "adapter kernel route: Pi preserves only the kernel-validated durable state selector" {
    run python3 - "$PROJECT_ROOT/skills/pi/extensions/mainframe.ts" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(
    r'for \(const key of \[(.*?)\]\) \{\n\s*const value = process\.env\[key\];',
    source,
    re.S,
)
assert match is not None
keys = set(re.findall(r'"([A-Z_]+)"', match.group(1)))
assert keys == {"HOME", "USER", "LOGNAME", "TMPDIR", "TERM", "XDG_STATE_HOME"}
assert 'cleanChildEnvironment({ MAINFRAME_ROOT: root })' in source
assert 'XDG_STATE_HOME:' not in source
print("pi_durable_state_selector=kernel_validated")
PY

    [[ "$status" -eq 0 ]]
    [[ "$output" == "pi_durable_state_selector=kernel_validated" ]]
}

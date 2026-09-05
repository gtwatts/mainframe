#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-control-plane-claim.XXXXXX")"
    PYTHON_BIN="${MAINFRAME_PYTHON:-/usr/bin/python3}"
    [[ -x "$PYTHON_BIN" ]] || PYTHON_BIN="$(command -v python3)"
    CHECKER="$PROJECT_ROOT/scripts/check-control-plane-claim.py"
    CONTRACT="$PROJECT_ROOT/config/control-plane-claim.json"
    MAINFRAME_BIN="$PROJECT_ROOT/bin/mainframe"
}

teardown() {
    rm -rf -- "$TEST_ROOT"
}

# bats test_tags=release-readiness
@test "canonical claim contract derives only source-candidate from local receipts" {
    run "$PYTHON_BIN" -I -S -B "$CHECKER" \
        --root "$PROJECT_ROOT" --contract "$CONTRACT" --json

    [[ "$status" -eq 0 ]]
    run "$PYTHON_BIN" -I -S -B - "$output" <<'PY'
import json
import sys

result = json.loads(sys.argv[1])
assert result["ok"] is True
assert result["highest_eligible_claim"] == "source-candidate"
assert result["advertised_claim"] == "source-candidate"
assert {
    gate for gate, state in result["gate_states"].items() if state == "green"
} == {
    "release-integrity",
    "semantic-authority",
    "runtime-closure",
    "reviewed-broker-routing",
    "coding-agent-contract",
    "project-memory-contract",
    "adapter-contract",
}
assert result["blocking_gates"] == [
    "durable-authority-kernel",
    "host-conformance",
    "immutable-distribution",
    "independent-outcomes",
]
PY
    [[ "$status" -eq 0 ]]
}

# bats test_tags=release-readiness
@test "sanitized public claim runs the fixed Bats memory verifier without promotion overrides" {
    local before after
    before="$(shasum -a 256 "$CONTRACT" | awk '{print $1}')"

    run "$MAINFRAME_BIN" claim --json
    [[ "$status" -eq 0 ]]
    run "$PYTHON_BIN" -I -S -B - "$output" <<'PY'
import json
import sys

result = json.loads(sys.argv[1])
assert result["ok"] is True
assert result["highest_eligible_claim"] == "source-candidate"
assert result["advertised_claim"] == "source-candidate"
assert result["gate_states"]["project-memory-contract"] == "green"
PY
    [[ "$status" -eq 0 ]]

    run "$MAINFRAME_BIN" claim --contract "$TEST_ROOT/forged.json"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *"Usage: mainframe claim [--json]"* ]]

    run "$MAINFRAME_BIN" claim --promote category-claim
    [[ "$status" -eq 64 ]]
    [[ "$output" == *"Usage: mainframe claim [--json]"* ]]

    after="$(shasum -a 256 "$CONTRACT" | awk '{print $1}')"
    [[ "$after" == "$before" ]]
}

@test "authored advertised claim cannot override missing receipt evidence" {
    cp "$CONTRACT" "$TEST_ROOT/overclaim.json"
    "$PYTHON_BIN" -I -S -B - "$TEST_ROOT/overclaim.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
document = json.loads(path.read_text(encoding="utf-8"))
document["advertised_claim"] = "stable-release"
path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
PY

    run "$PYTHON_BIN" -I -S -B "$CHECKER" \
        --root "$PROJECT_ROOT" --contract "$TEST_ROOT/overclaim.json" --json

    [[ "$status" -ne 0 ]]
    run "$PYTHON_BIN" -I -S -B - "$output" <<'PY'
import json
import sys

result = json.loads(sys.argv[1])
assert result["ok"] is False
assert "highest_eligible_claim" not in result
PY
    [[ "$status" -eq 0 ]]
}

@test "claim checker rejects a symlinked contract before evaluating receipts" {
    ln -s "$CONTRACT" "$TEST_ROOT/claim-link.json"
    run "$PYTHON_BIN" -I -S -B "$CHECKER" \
        --root "$PROJECT_ROOT" --contract "$TEST_ROOT/claim-link.json" --json
    [[ "$status" -ne 0 ]]
    [[ "$output" == *'contract must be a regular non-symlink file'* ]]
}

@test "claim contract schema is closed and non-green gates name remaining proof" {
    cp "$CONTRACT" "$TEST_ROOT/malformed.json"
    "$PYTHON_BIN" -I -S -B - "$TEST_ROOT/malformed.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
document = json.loads(path.read_text(encoding="utf-8"))
document["unexpected"] = True
document["gates"]["host-conformance"]["remaining"] = []
path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
PY

    run "$PYTHON_BIN" -I -S -B "$CHECKER" \
        --root "$PROJECT_ROOT" --contract "$TEST_ROOT/malformed.json" --json

    [[ "$status" -ne 0 ]]
    [[ "$output" == *'unknown top-level keys'* ]]
}

#!/usr/bin/env bats
# Activation command tests (A++ Phase 1 deliverables 1-2):
# merge-safe, --dry-run, idempotent, never overwrite, managed-content-only removal.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [ -x "$BASH_BIN" ] || BASH_BIN="$(command -v bash)"
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-activate-test.XXXXXX")"
}

teardown() {
    rm -rf "$TEST_DIR"
}

mf() {
    "$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" "$@"
}

@test "activate: dry-run writes nothing" {
    run mf activate codex --project "$TEST_DIR" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would-create"* ]]
    [ ! -f "$TEST_DIR/AGENTS.md" ]
}

@test "activate: creates, is idempotent, and status reports state" {
    run mf activate codex --project "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"created"* ]]
    grep -q "MAINFRAME:BEGIN" "$TEST_DIR/AGENTS.md"

    run mf activate codex --project "$TEST_DIR"
    [[ "$output" == *"already-current"* ]]

    run mf activate status --project "$TEST_DIR"
    [[ "$output" == *"codex"* ]]
    [[ "$output" == *"active (current)"* ]]
}

@test "activate: never overwrites existing instruction file" {
    printf '# Team rules\n\nDo not commit secrets.\n' > "$TEST_DIR/AGENTS.md"
    run mf activate codex --project "$TEST_DIR"
    [[ "$output" == *"appended"* ]]
    grep -q "Do not commit secrets" "$TEST_DIR/AGENTS.md"
    grep -q "MAINFRAME:BEGIN" "$TEST_DIR/AGENTS.md"
}

@test "activate: updates a stale managed block in place" {
    mf activate codex --project "$TEST_DIR" >/dev/null
    sed -i.bak 's/AI-native bash runtime/OUTDATED TEXT/' "$TEST_DIR/AGENTS.md"
    run mf activate codex --project "$TEST_DIR"
    [[ "$output" == *"updated"* ]]
    ! grep -q "OUTDATED TEXT" "$TEST_DIR/AGENTS.md"
}

@test "deactivate: removes only MAINFRAME-managed content" {
    printf '# Team rules\n\nDo not commit secrets.\n' > "$TEST_DIR/AGENTS.md"
    mf activate codex --project "$TEST_DIR" >/dev/null
    run mf deactivate codex --project "$TEST_DIR"
    [[ "$output" == *"removed"* ]]
    grep -q "Do not commit secrets" "$TEST_DIR/AGENTS.md"
    ! grep -q "MAINFRAME:BEGIN" "$TEST_DIR/AGENTS.md"
    # second deactivation is a no-op, not an error
    run mf deactivate codex --project "$TEST_DIR"
    [[ "$output" == *"no-managed-content"* ]]
}

@test "deactivate: dry-run writes nothing" {
    mf activate codex --project "$TEST_DIR" >/dev/null
    run mf deactivate codex --project "$TEST_DIR" --dry-run
    [[ "$output" == *"would-remove"* ]]
    grep -q "MAINFRAME:BEGIN" "$TEST_DIR/AGENTS.md"
}

@test "activate: all hosts and unknown host handling" {
    run mf activate all --project "$TEST_DIR"
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/.github/copilot-instructions.md" ]
    [ -f "$TEST_DIR/.junie/guidelines.md" ]
    run mf activate not-a-host --project "$TEST_DIR"
    [ "$status" -ne 0 ]
}

@test "activate: generated and project instructions share the conservative contract" {
    run "$PROJECT_ROOT/scripts/generate-host-adapters.sh" --check
    [ "$status" -eq 0 ]

    run mf activate all --project "$TEST_DIR"
    [ "$status" -eq 0 ]

    run python3 - "$PROJECT_ROOT" "$TEST_DIR" <<'PY'
import base64
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
project = pathlib.Path(sys.argv[2])
registry = json.loads((root / "config/host-capabilities.json").read_text())
activation = registry["activation_contract"]
marker_pattern = re.compile(
    r"^<!-- MAINFRAME-ACTIVATION-CONTRACT (\{[^\n]+\}) -->$", re.MULTILINE
)
payload_pattern = re.compile(
    r"^<!-- MAINFRAME-ACTIVATION-PAYLOAD ([A-Za-z0-9+/=]+) -->$", re.MULTILINE
)
boundary = f"> {activation['boundary_statement']}"
expected_payload = "\n".join(activation["instruction_lines"])
targets = {
    "codex": "AGENTS.md",
    "claude-code": "CLAUDE.md",
    "copilot": ".github/copilot-instructions.md",
    "gemini": "GEMINI.md",
    "cursor": ".cursor/rules/mainframe.mdc",
    "jetbrains": ".aiassistant/rules/mainframe.md",
    "junie": ".junie/guidelines.md",
}

for host_id, relative in targets.items():
    static = (root / registry["hosts"][host_id]["static_adapter"]).read_text()
    activated = (project / relative).read_text()
    static_marker = marker_pattern.findall(static)
    activated_marker = marker_pattern.findall(activated)
    assert len(static_marker) == len(activated_marker) == 1, host_id
    assert static_marker[0] == activated_marker[0], host_id
    assert static.count(boundary) == activated.count(boundary) == 1, host_id
    payloads = payload_pattern.findall(static)
    assert len(payloads) == 1, host_id
    assert base64.b64decode(payloads[0], validate=True).decode() == expected_payload
    begin = f"<!-- MAINFRAME:BEGIN v{activation['block_version']} -->"
    end = f"<!-- MAINFRAME:END v{activation['block_version']} -->"
    assert activated.count(begin) == activated.count(end) == 1, host_id
    assert expected_payload in activated, host_id
    assert "direct AWM helper grants broker or project-memory authority" in activated, host_id
    assert "durable project-memory mutations (`ensure`, `checkpoint`, `discovery`, `progress`, `close`, and `handoff`)" in activated, host_id
    assert "durable records are non-authoritative metadata, not trusted facts" in activated, host_id
    assert "project-memory reads (`session`, `status`, `get`, `summary`, `context`, and `find`)" in activated, host_id
    assert "control-plane read plane" in activated, host_id
    assert "project-memory mutation or read route is unavailable, fail closed" in activated, host_id
    assert "use the read-only `mainframe awm project handoff prepare" not in activated, host_id
    assert "does not enforce non-shell file, network, process, MCP-tool, or host-control routes" in activated, host_id
    assert "stop and request human direction" in activated, host_id
    assert "evidence_level\":\"enforced" not in activated, host_id

assert not any(project.glob("**/hooks.json"))
assert not (project / ".claude/settings.json").exists()
assert not (project / ".gemini/settings.json").exists()
print("activation shares the static instructions-only contract")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"activation shares the static instructions-only contract"* ]]
}

@test "activate: rejects a static adapter that overclaims its evidence boundary" {
    local fixture="$TEST_DIR/runtime"
    mkdir -p "$fixture/lib" "$fixture/config" "$fixture/skills/codex"
    cp "$PROJECT_ROOT/lib/activate.sh" "$fixture/lib/activate.sh"
    cp "$PROJECT_ROOT/config/host-capabilities.json" "$fixture/config/host-capabilities.json"
    cp "$PROJECT_ROOT/skills/codex/AGENTS.md" "$fixture/skills/codex/AGENTS.md"
    sed -i.bak 's/"adapter_evidence_level":"instructions"/"adapter_evidence_level":"enforced"/' \
        "$fixture/skills/codex/AGENTS.md"

    run "$BASH_BIN" -c 'MAINFRAME_ROOT="$1"; source "$1/lib/activate.sh"; _mainframe_activate_block' _ "$fixture"
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid activation contract"* ]]
}

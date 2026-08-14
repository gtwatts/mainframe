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

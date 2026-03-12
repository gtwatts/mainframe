#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/mainframe-awm.bats - AWM CLI Tests
# =============================================================================

setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."
    MAINFRAME_BIN="${MAINFRAME_ROOT}/bin/mainframe"
    TEST_TMPDIR="$(mktemp -d)"
    export MAINFRAME_ROOT
    chmod +x "$MAINFRAME_BIN"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "mainframe awm help shows AWM subcommands" {
    run "$MAINFRAME_BIN" awm --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME AWM"* ]]
    [[ "$output" == *"mainframe awm init"* ]]
    [[ "$output" == *"mainframe awm handoff prepare"* ]]
}

@test "mainframe awm init creates a canonical session" {
    run env AWM_ROOT="${TEST_TMPDIR}/awm" "$MAINFRAME_BIN" awm init cli-session --namespace red-team --backend file
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^[a-f0-9]{12}$ ]]
    [[ -f "${TEST_TMPDIR}/awm/sessions/red-team/${output}/manifest.json" ]]
}

@test "mainframe awm checkpoint and get roundtrip with --session" {
    run env AWM_ROOT="${TEST_TMPDIR}/awm" "$MAINFRAME_BIN" awm init cli-roundtrip
    [[ "$status" -eq 0 ]]
    local sid="$output"

    run env AWM_ROOT="${TEST_TMPDIR}/awm" "$MAINFRAME_BIN" awm checkpoint --session "$sid" current_step 3 --importance high
    [[ "$status" -eq 0 ]]

    run env AWM_ROOT="${TEST_TMPDIR}/awm" "$MAINFRAME_BIN" awm get --session "$sid" current_step
    [[ "$status" -eq 0 ]]
    [[ "$output" == "3" ]]
}

@test "mainframe awm find searches via CLI" {
    run env AWM_ROOT="${TEST_TMPDIR}/awm" "$MAINFRAME_BIN" awm init cli-find
    [[ "$status" -eq 0 ]]
    local sid="$output"

    run env AWM_ROOT="${TEST_TMPDIR}/awm" "$MAINFRAME_BIN" awm discovery --session "$sid" "Project uses PostgreSQL 15" --importance critical
    [[ "$status" -eq 0 ]]

    run env AWM_ROOT="${TEST_TMPDIR}/awm" "$MAINFRAME_BIN" awm find --session "$sid" postgres --kind discovery
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"kind":"discovery"'* ]]
    [[ "$output" == *'PostgreSQL 15'* ]]
}

@test "mainframe awm doctor and inspect expose session details" {
    run env AWM_ROOT="${TEST_TMPDIR}/awm" "$MAINFRAME_BIN" awm init cli-inspect
    [[ "$status" -eq 0 ]]
    local sid="$output"

    run env AWM_ROOT="${TEST_TMPDIR}/awm" "$MAINFRAME_BIN" awm doctor --session "$sid"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"layout_ok":true'* ]]

    run env AWM_ROOT="${TEST_TMPDIR}/awm" "$MAINFRAME_BIN" awm inspect "$sid"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"status":'* ]]
    [[ "$output" == *'"summary":'* ]]
}

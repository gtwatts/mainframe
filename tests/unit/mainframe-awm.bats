#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/mainframe-awm.bats - AWM CLI Tests
# =============================================================================

setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."
    MAINFRAME_BIN="${MAINFRAME_ROOT}/bin/mainframe"
    TEST_TMPDIR="$(mktemp -d)"
    TEST_TMPDIR="$(cd "$TEST_TMPDIR" && pwd -P)"
    BASH_BIN="${MAINFRAME_BASH:-${BASH:-bash}}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v "$BASH_BIN")"
    export MAINFRAME_ROOT
    chmod +x "$MAINFRAME_BIN"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

arithmetic_payload_for_marker() {
    local marker="$1"
    printf 'BASH_VERSINFO[$(printf marker > "%s")0]' "$marker"
}

@test "mainframe awm help shows AWM subcommands" {
    run "$MAINFRAME_BIN" awm --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME AWM"* ]]
    [[ "$output" == *"mainframe awm init"* ]]
    [[ "$output" == *"mainframe awm handoff prepare"* ]]
}

@test "mainframe awm loads AWM on demand when explicit MAINFRAME_LIBS excludes it" {
    run env MAINFRAME_LIBS=core AWM_ROOT="${TEST_TMPDIR}/awm" \
        "$MAINFRAME_BIN" awm init selective-loader
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^[a-f0-9]{12}$ ]]
    local sid="$output"

    run env MAINFRAME_LIBS=core AWM_ROOT="${TEST_TMPDIR}/awm" \
        "$MAINFRAME_BIN" awm checkpoint --session "$sid" loader_state ready
    [[ "$status" -eq 0 ]]

    run env MAINFRAME_LIBS=core AWM_ROOT="${TEST_TMPDIR}/awm" \
        "$MAINFRAME_BIN" awm get --session "$sid" loader_state
    [[ "$status" -eq 0 ]]
    [[ "$output" == "ready" ]]
}

@test "mainframe awm selective loading preserves explicit MAINFRAME_LIBS" {
    run "$BASH_BIN" --noprofile --norc -p -c '
        export MAINFRAME_LIBS=core
        export AWM_ROOT="$1"
        source "$2" awm init selective-loader >/dev/null
        printf "MAINFRAME_LIBS=%s\n" "$MAINFRAME_LIBS"
        declare -F awm_init >/dev/null
        if declare -F agent_register >/dev/null; then
            printf "unexpected non-AWM library loaded\n" >&2
            exit 1
        fi
    ' _ "${TEST_TMPDIR}/awm" "$MAINFRAME_BIN"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "MAINFRAME_LIBS=core" ]]
}

@test "mainframe awm honors a configured full profile before applying its fast-path default" {
    local config_file="${TEST_TMPDIR}/profile-config"
    printf 'profile=full\n' > "$config_file"

    run "$BASH_BIN" --noprofile --norc -p -c '
        unset MAINFRAME_LIBS MAINFRAME_PROFILE
        export MAINFRAME_CONFIG="$1"
        export AWM_ROOT="$2"
        source "$3" awm --help >/dev/null 2>&1
        declare -F awm_init >/dev/null
        declare -F agent_register >/dev/null
        printf "MAINFRAME_PROFILE=%s MAINFRAME_LIBS=%s\n" \
            "$MAINFRAME_PROFILE" "$MAINFRAME_LIBS"
    ' _ "$config_file" "${TEST_TMPDIR}/profile-awm" "$MAINFRAME_BIN"

    [[ "$status" -eq 0 ]]
    [[ "$output" == "MAINFRAME_PROFILE=full MAINFRAME_LIBS=all" ]]
}

@test "mainframe awm honors configured libraries and adds only its command dependency" {
    local config_file="${TEST_TMPDIR}/libs-config"
    printf 'libs=core\n' > "$config_file"

    run "$BASH_BIN" --noprofile --norc -p -c '
        unset MAINFRAME_LIBS MAINFRAME_PROFILE
        export MAINFRAME_CONFIG="$1"
        export AWM_ROOT="$2"
        source "$3" awm --help >/dev/null 2>&1
        declare -F awm_init >/dev/null
        if declare -F agent_register >/dev/null; then
            printf "unexpected non-AWM library loaded\n" >&2
            exit 1
        fi
        printf "MAINFRAME_LIBS=%s\n" "$MAINFRAME_LIBS"
    ' _ "$config_file" "${TEST_TMPDIR}/libs-awm" "$MAINFRAME_BIN"

    [[ "$status" -eq 0 ]]
    [[ "$output" == "MAINFRAME_LIBS=core" ]]
}

@test "mainframe awm init creates a canonical session" {
    run env AWM_ROOT="${TEST_TMPDIR}/awm" "$MAINFRAME_BIN" awm init cli-session --namespace red-team --backend file
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^[a-f0-9]{12}$ ]]
    [[ -f "${TEST_TMPDIR}/awm/sessions/red-team/${output}/manifest.json" ]]
}

@test "zsh users can invoke the AWM CLI without changing login shells" {
    command -v zsh >/dev/null 2>&1 || skip "zsh is not installed"

    run env AWM_ROOT="${TEST_TMPDIR}/awm" zsh -f -c '"$1" awm init zsh-session' \
        _ "$MAINFRAME_BIN"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^[a-f0-9]{12}$ ]]
    [[ -f "${TEST_TMPDIR}/awm/sessions/${output}/manifest.json" ]]
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

@test "mainframe awm progress records task state with --session" {
    run env AWM_ROOT="${TEST_TMPDIR}/awm" "$MAINFRAME_BIN" awm init cli-progress
    [[ "$status" -eq 0 ]]
    local sid="$output"

    run env AWM_ROOT="${TEST_TMPDIR}/awm" "$MAINFRAME_BIN" awm progress \
        --session "$sid" audit 2/5 "checking native hosts"
    [[ "$status" -eq 0 ]]

    run env AWM_ROOT="${TEST_TMPDIR}/awm" "$MAINFRAME_BIN" awm get \
        --session "$sid" progress:audit
    [[ "$status" -eq 0 ]]
    [[ "$output" == "2/5" ]]
}

@test "mainframe awm context rejects arithmetic token payloads without executing them" {
    local marker="${TEST_TMPDIR}/cli-context-arithmetic-marker"
    local payload
    payload=$(arithmetic_payload_for_marker "$marker")

    run env AWM_ROOT="${TEST_TMPDIR}/context-awm" \
        "$MAINFRAME_BIN" awm init cli-context-input-safety
    [[ "$status" -eq 0 ]]
    local sid="$output"

    run env AWM_ROOT="${TEST_TMPDIR}/context-awm" \
        "$MAINFRAME_BIN" awm context --session "$sid" "input safety" --tokens "$payload"

    [[ "$status" -ne 0 ]]
    [[ ! -e "$marker" ]]
}

@test "mainframe awm handoff rejects arithmetic token payloads without executing them" {
    local marker="${TEST_TMPDIR}/cli-handoff-arithmetic-marker"
    local payload
    payload=$(arithmetic_payload_for_marker "$marker")

    run env AWM_ROOT="${TEST_TMPDIR}/handoff-awm" \
        "$MAINFRAME_BIN" awm init cli-handoff-input-safety
    [[ "$status" -eq 0 ]]
    local sid="$output"

    run env AWM_ROOT="${TEST_TMPDIR}/handoff-awm" \
        "$MAINFRAME_BIN" awm handoff prepare --session "$sid" reviewer --tokens "$payload"

    [[ "$status" -ne 0 ]]
    [[ ! -e "$marker" ]]
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

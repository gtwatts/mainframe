#!/usr/bin/env bats
# Explicit-consent onboarding contract over the existing public CLI surfaces.

load 'test_helper'

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v bash)"
    TEST_DIR="$(create_test_dir onboard)"
    TEST_DIR="$(cd "$TEST_DIR" && pwd -P)"
    PROJECT_DIR="$TEST_DIR/project with spaces"
    CLI_DIR="$TEST_DIR/bin"
    TEST_HOME="$TEST_DIR/home"
    XDG_STATE_HOME="$TEST_DIR/state"
    BASE_PATH="$PATH"

    mkdir -p "$PROJECT_DIR" "$CLI_DIR" "$TEST_HOME"
    mkdir -m 0700 "$XDG_STATE_HOME"
    ln -s "$PROJECT_ROOT/bin/mainframe" "$CLI_DIR/mainframe"

    export PROJECT_ROOT BASH_BIN TEST_DIR PROJECT_DIR CLI_DIR TEST_HOME BASE_PATH
    export XDG_STATE_HOME
    export HOME="$TEST_HOME"
    export AWM_ROOT="$TEST_HOME/.mainframe/awm"
    export MAINFRAME_ROOT="$PROJECT_ROOT"
    export MAINFRAME_AGENT_AUDIT_LOG="$TEST_DIR/state/gateway.jsonl"
    export PATH="$CLI_DIR:$BASE_PATH"
    export SHELL=/bin/zsh
    unset MAINFRAME_AGENT_GATE_TIER

    # Project onboarding assumes the shell runtime itself is already selected
    # and healthy. Establish that prerequisite inside the isolated HOME so an
    # unrelated MAINFRAME installed on the developer's ambient PATH cannot
    # contaminate the source-tree doctor check.
    PATH="$CLI_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
        "$PROJECT_ROOT/bin/mainframe" shell repair --shell all --yes \
        >/dev/null

    CODEX_HOOK_COMMAND="$(expected_hook_command codex)"
    CLAUDE_HOOK_COMMAND="$(expected_hook_command claude-code)"
    COPILOT_HOOK_COMMAND="$(expected_hook_command copilot)"
    GEMINI_HOOK_COMMAND="$(expected_hook_command gemini)"
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

onboard() {
    "$BASH_BIN" -c '
        root="$1"
        shift
        source "$root/lib/activate.sh"
        source "$root/lib/onboard.sh"
        mainframe_onboard "$@"
    ' _ "$PROJECT_ROOT" "$@"
}

expected_hook_command() {
    "$BASH_BIN" --noprofile --norc -p -c \
        'source "$1"; _mainframe_enforce_command_for "$2"' \
        _ "$PROJECT_ROOT/lib/activate.sh" "$1"
}

assert_no_codex_activation() {
    [[ ! -e "$PROJECT_DIR/AGENTS.md" ]]
    [[ ! -e "$PROJECT_DIR/.codex/hooks.json" ]]
}

assert_no_awm_state() {
    [[ ! -e "$AWM_ROOT" ]]
    [[ ! -e "$XDG_STATE_HOME/mainframe/control-plane.jsonl" ]]
    [[ -z "$(find "$XDG_STATE_HOME" -type f -path '*/awm/projects/*.json' -print -quit)" ]]
}

@test "onboard help documents the narrow explicit-consent contract" {
    run onboard --help

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"mainframe onboard --host <host> --project <dir>"* ]]
    [[ "$output" == *"codex, claude-code, copilot, gemini"* ]]
    [[ "$output" == *"--dry-run"*"without writing"* ]]
    [[ "$output" == *"--yes"*"non-interactive"* ]]
    [[ "$output" == *"private AWM session"* ]]
    [[ "$output" == *"Host-native trust and runtime loading"* ]]
}

@test "onboard rejects all, instruction-only, and unknown hosts before writes" {
    local host
    for host in all cursor jetbrains junie unknown-host; do
        run onboard --host "$host" --project "$PROJECT_DIR" --yes
        [[ "$status" -eq 2 ]]
    done

    [[ -z "$(find "$PROJECT_DIR" -mindepth 1 -print -quit)" ]]
    [[ ! -e "$MAINFRAME_AGENT_AUDIT_LOG" ]]
    assert_no_awm_state
}

@test "onboard dry-run canonicalizes the project and changes nothing" {
    local physical_project
    physical_project="$(cd "$PROJECT_DIR" && pwd -P)"

    run onboard --host codex --project "$PROJECT_DIR" --dry-run

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Project: $physical_project"* ]]
    [[ "$output" == *"Activation preview:"* ]]
    [[ "$output" == *"would-create"* ]]
    [[ "$output" == *"would-enforce-create"* ]]
    [[ "$output" == *"Dry run complete. No project files, AWM state, or audit records were changed."* ]]
    assert_no_codex_activation
    [[ ! -e "$MAINFRAME_AGENT_AUDIT_LOG" ]]
    assert_no_awm_state
}

@test "onboard refuses non-interactive mutation without --yes" {
    run onboard --host codex --project "$PROJECT_DIR"

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"Activation preview:"* ]]
    [[ "$output" == *"refusing non-interactive changes without --yes"* ]]
    assert_no_codex_activation
    [[ ! -e "$MAINFRAME_AGENT_AUDIT_LOG" ]]
    assert_no_awm_state
}

@test "onboard consent accepts only exact y or yes forms" {
    local answer
    for answer in y Y yes YES Yes yEs yeS YEs YeS yES; do
        run "$BASH_BIN" -c '
            source "$1/lib/onboard.sh"
            _mainframe_onboard_consent_is_yes "$2"
        ' _ "$PROJECT_ROOT" "$answer"
        [[ "$status" -eq 0 ]]
    done

    for answer in "" n no yeah " yes" "yes " 1 true; do
        run "$BASH_BIN" -c '
            source "$1/lib/onboard.sh"
            _mainframe_onboard_consent_is_yes "$2"
        ' _ "$PROJECT_ROOT" "$answer"
        [[ "$status" -ne 0 ]]
    done
}

@test "onboard --yes configures and verifies each enforced host" {
    local host project nested instruction_file session_id
    for host in codex claude-code copilot gemini; do
        project="$TEST_DIR/project-$host"
        mkdir -p "$project"

        run onboard --host "$host" --project "$project" --yes

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"Privileged gateway:"*"VERIFIED"* ]]
        [[ "$output" == *"Gateway allow canary:  PASS"* ]]
        [[ "$output" == *"Gateway deny canary:   PASS"* ]]
        [[ "$output" == *"AWM project session:"*"RECORDED"*"non-authoritative"* ]]
        [[ "$output" == *"AWM project reads:"*"READY"*"non-authoritative"* ]]
        [[ "$output" == *"Project configuration: READY"* ]]
        [[ "$output" == *"Host runtime load:     UNVERIFIED"* ]]
        [[ "$output" == *"Rollback preview:"*"Rollback apply:"* ]]
        [[ "$output" == *"Deactivation leaves private project-memory history intact"* ]]
        ! grep -Eq '^AWM project session:[[:space:]]+READY' <<< "$output"

        case "$host" in
            codex)
                instruction_file="$project/AGENTS.md"
                [[ -f "$instruction_file" ]]
                jq -e --arg command "$CODEX_HOOK_COMMAND" \
                    '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[]
                    | select(.command == $command)]
                    | length == 1' "$project/.codex/hooks.json" >/dev/null
                ;;
            claude-code)
                instruction_file="$project/CLAUDE.md"
                [[ -f "$instruction_file" ]]
                jq -e --arg command "$CLAUDE_HOOK_COMMAND" \
                    '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[]
                    | select(.command == $command)]
                    | length == 1' "$project/.claude/settings.json" >/dev/null
                ;;
            copilot)
                instruction_file="$project/.github/copilot-instructions.md"
                [[ -f "$instruction_file" ]]
                jq -e --arg command "$COPILOT_HOOK_COMMAND" \
                    '[.hooks.preToolUse[]
                    | select(.bash == $command)]
                    | length == 1' "$project/.github/hooks/mainframe.json" >/dev/null
                [[ "$output" == *"timeouts as fail-open"* ]]
                ;;
            gemini)
                instruction_file="$project/GEMINI.md"
                [[ -f "$instruction_file" ]]
                jq -e --arg command "$GEMINI_HOOK_COMMAND" \
                    '[.hooks.BeforeTool[] | select(.matcher == "run_shell_command") | .hooks[]
                    | select(.command == $command)]
                    | length == 1' "$project/.gemini/settings.json" >/dev/null
                ;;
        esac

        grep -Fq 'Neither `common.sh`, `atomic_write`, `atomic_append`, `ensure_dir`, `ensure_file`, nor any direct AWM helper grants broker or project-memory authority.' "$instruction_file"
        grep -Fq 'durable project-memory mutations (`ensure`, `checkpoint`, `discovery`, `progress`, `close`, and `handoff`) only through the reviewed MAINFRAME control-plane memory route' "$instruction_file"
        grep -Fq 'durable records are non-authoritative metadata, not trusted facts' "$instruction_file"
        grep -Fq 'project-memory reads (`session`, `status`, `get`, `summary`, `context`, and `find`) only through the reviewed MAINFRAME control-plane read plane' "$instruction_file"
        grep -Fq 'project-memory mutation or read route is unavailable, fail closed' "$instruction_file"
        grep -Fq 'Never fall back to a sourced helper, direct AWM storage, or an ad-hoc shell write.' "$instruction_file"
        ! grep -Fq 'use the read-only `mainframe awm project handoff prepare' "$instruction_file"
        grep -Fq 'Never store credentials, tokens, secrets, raw sensitive payloads, or routine command chatter.' "$instruction_file"

        if [[ "$output" =~ RECORDED\ \(([0-9a-f]{12})\; ]]; then
            session_id="${BASH_REMATCH[1]}"
        else
            false
        fi

        run "$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" awm project status --project "$project"
        [[ "$status" -eq 0 ]]
        jq -e --arg session_id "$session_id" \
            '.status == "mapped" and .private == true and .session_id == $session_id' \
            <<< "$output" >/dev/null

        nested="$project/src/agent/work"
        mkdir -p -- "$nested"
        run "$BASH_BIN" -c '
            cd -- "$1"
            exec "$2" "$3" awm project session --project . --discover-root
        ' _ "$nested" "$BASH_BIN" "$PROJECT_ROOT/bin/mainframe"
        [[ "$status" -eq 0 ]]
        [[ "$output" == "$session_id" ]]

        run "$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" protect status "$host" --project "$project"
        [[ "$status" -eq 0 ]]
        [[ "$output" == *"Static readiness: READY"* ]]
    done

    [[ "$(wc -l < "$MAINFRAME_AGENT_AUDIT_LOG" | tr -d ' ')" -eq 8 ]]
    [[ "$(file_mode "$MAINFRAME_AGENT_AUDIT_LOG")" == "600" ]]
    ! grep -Fq 'git status --short' "$MAINFRAME_AGENT_AUDIT_LOG"
    ! grep -Fq 'mainframe-onboard-never-execute' "$MAINFRAME_AGENT_AUDIT_LOG"
}

@test "onboard is idempotent for managed project files" {
    run onboard --host codex --project "$PROJECT_DIR" --yes
    [[ "$status" -eq 0 ]]

    local instructions_before hooks_before session_before session_after
    instructions_before="$(cksum "$PROJECT_DIR/AGENTS.md")"
    hooks_before="$(cksum "$PROJECT_DIR/.codex/hooks.json")"
    [[ "$output" =~ RECORDED\ \(([0-9a-f]{12})\; ]]
    session_before="${BASH_REMATCH[1]}"
    [[ "$session_before" =~ ^[0-9a-f]{12}$ ]]

    run onboard --host codex --project "$PROJECT_DIR" --yes

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"already-current"* ]]
    [[ "$output" == *"enforcement-current"* ]]
    [[ "$(cksum "$PROJECT_DIR/AGENTS.md")" == "$instructions_before" ]]
    [[ "$(cksum "$PROJECT_DIR/.codex/hooks.json")" == "$hooks_before" ]]
    [[ "$output" =~ RECORDED\ \(([0-9a-f]{12})\; ]]
    session_after="${BASH_REMATCH[1]}"
    [[ "$session_after" == "$session_before" ]]
    [[ "$(find "$XDG_STATE_HOME" -type f -path '*/awm/projects/*.json' | wc -l | tr -d ' ')" -eq 1 ]]
    [[ "$(grep -c 'MAINFRAME:BEGIN' "$PROJECT_DIR/AGENTS.md")" -eq 1 ]]
    jq -e --arg command "$CODEX_HOOK_COMMAND" \
        '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[]
        | select(.command == $command)]
        | length == 1' "$PROJECT_DIR/.codex/hooks.json" >/dev/null
}

@test "onboard invalid JSON fails in preview before consent or mutation" {
    mkdir -p "$PROJECT_DIR/.claude"
    printf '%s\n' '{not-json' > "$PROJECT_DIR/.claude/settings.json"

    run onboard --host claude-code --project "$PROJECT_DIR" --yes

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Invalid JSON object"* ]]
    [[ "$output" == *"activation preview failed; no project changes were attempted"* ]]
    [[ ! -e "$PROJECT_DIR/CLAUDE.md" ]]
    [[ "$(<"$PROJECT_DIR/.claude/settings.json")" == "{not-json" ]]
    [[ ! -e "$MAINFRAME_AGENT_AUDIT_LOG" ]]
    assert_no_awm_state
}

@test "onboard ignores ambient legacy AWM storage and uses the private kernel route" {
    export AWM_ROOT="$TEST_DIR/ambient-legacy-awm"

    run onboard --host codex --project "$PROJECT_DIR" --yes

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"AWM project session:"*"RECORDED"*"non-authoritative"* ]]
    [[ "$output" == *"AWM project reads:"*"READY"*"non-authoritative"* ]]
    [[ -f "$PROJECT_DIR/AGENTS.md" ]]
    [[ -f "$PROJECT_DIR/.codex/hooks.json" ]]
    [[ -f "$MAINFRAME_AGENT_AUDIT_LOG" ]]
    [[ "$(wc -l < "$MAINFRAME_AGENT_AUDIT_LOG" | tr -d ' ')" -eq 2 ]]
    [[ ! -e "$AWM_ROOT" ]]
    [[ -f "$XDG_STATE_HOME/mainframe/control-plane.jsonl" ]]
}

@test "onboard refuses a PATH-first mainframe emulator before mutation" {
    local fake_dir="$TEST_DIR/plausible-fake-gateway"
    local marker="$TEST_DIR/fake-mainframe-ran"
    mkdir -p "$fake_dir"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        "touch \"$marker\"" \
        'payload=$(cat)' \
        'if [[ "$payload" == *"git status --short"* ]]; then' \
        '    printf "{}\n"' \
        '    exit 0' \
        'fi' \
        'printf "risk=critical rule=recursive-force-rm decision=deny\n" >&2' \
        'exit 2' > "$fake_dir/mainframe"
    chmod +x "$fake_dir/mainframe"
    export PATH="$fake_dir:$CLI_DIR:$BASE_PATH"

    run onboard --host codex --project "$PROJECT_DIR" --yes

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Shell identity: not-selected"* ]]
    [[ "$output" == *"doctor failed; no project changes were attempted"* ]]
    [[ ! -e "$marker" ]]
    assert_no_codex_activation
    [[ ! -e "$MAINFRAME_AGENT_AUDIT_LOG" ]]
    assert_no_awm_state
}

@test "onboard rejects a project-controlled jq before consent or mutation" {
    local fake_bin="$PROJECT_DIR/bin"
    mkdir -p "$fake_bin"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$fake_bin/jq"
    chmod +x "$fake_bin/jq"
    export PATH="$fake_bin:$CLI_DIR:$BASE_PATH"

    run onboard --host codex --project "$PROJECT_DIR" --yes

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"refusing a project-controlled jq executable"* ]]
    [[ "$output" == *"privileged gateway runtime is not ready"* ]]
    [[ "$output" == *"no project changes were attempted"* ]]
    assert_no_codex_activation
    [[ ! -e "$MAINFRAME_AGENT_AUDIT_LOG" ]]
    assert_no_awm_state
}

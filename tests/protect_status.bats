#!/usr/bin/env bats
# Read-only, exact-entry protection observability for every host adapter.

load 'test_helper'

setup() {
    TEST_DIR="$(create_test_dir protect-status)"
    PROJECT_DIR="$TEST_DIR/project"
    CLI_DIR="$TEST_DIR/bin"
    BASE_PATH="$PATH"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    PROJECT_VERSION="$(tr -d '[:space:]' < "$MAINFRAME_ROOT/VERSION")"
    [ -x "$BASH_BIN" ] || BASH_BIN="$(command -v bash)"
    mkdir -p "$PROJECT_DIR" "$CLI_DIR"
    ln -s "$MAINFRAME_ROOT/bin/mainframe" "$CLI_DIR/mainframe"
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

mf() {
    env PATH="$CLI_DIR:$BASE_PATH" "$BASH_BIN" "$MAINFRAME_ROOT/bin/mainframe" "$@"
}

@test "protect status reports every exact adapter and instruction-only hosts" {
    mf activate all --project "$PROJECT_DIR" --enforce >/dev/null

    run mf protect status --project "$PROJECT_DIR"

    [ "$status" -eq 0 ]
    [[ "$output" == *"codex"*".codex/hooks.json"*"configured"* ]]
    [[ "$output" == *"claude-code"*".claude/settings.json"*"configured"* ]]
    [[ "$output" == *"copilot"*".github/hooks/mainframe.json"*"configured"* ]]
    [[ "$output" == *"gemini"*".gemini/settings.json"*"configured"* ]]
    [[ "$output" == *"cursor"*"instruction-only"* ]]
    [[ "$output" == *"Codex trust and runtime load unverified"* ]]
    [[ "$output" == *"Runtime load: UNVERIFIED"* ]]
    [[ "$output" == *"Static readiness: READY"* ]]
}

@test "protect status scopes readiness to the requested host" {
    mf activate claude-code --project "$PROJECT_DIR" --enforce >/dev/null

    run mf protect status claude-code --project "$PROJECT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude-code"*"configured"* ]]
    [[ "$output" != *"gemini"* ]]

    run mf protect status --project "$PROJECT_DIR"
    [ "$status" -ne 0 ]
    [[ "$output" == *"gemini"*"missing"* ]]
}

@test "protect status reports an absent config as missing" {
    run mf protect status gemini --project "$PROJECT_DIR"

    [ "$status" -ne 0 ]
    [[ "$output" == *"gemini"*"missing"*"config file is absent"* ]]
    [[ "$output" == *"Static readiness: NOT READY"* ]]
}

@test "protect status reports corrupt JSON as invalid" {
    mkdir -p "$PROJECT_DIR/.gemini"
    printf '%s\n' '{not-json' > "$PROJECT_DIR/.gemini/settings.json"

    run mf protect status gemini --project "$PROJECT_DIR"

    [ "$status" -ne 0 ]
    [[ "$output" == *"gemini"*"invalid"*"Invalid JSON object"* ]]
}

@test "protect status never mistakes or mutates a foreign hook entry" {
    mkdir -p "$PROJECT_DIR/.claude"
    cat > "$PROJECT_DIR/.claude/settings.json" <<'JSON'
{
  "permissions": {"allow": ["Read"]},
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": "./foreign-check.sh"}]
      }
    ]
  }
}
JSON
    before="$(jq -cS . "$PROJECT_DIR/.claude/settings.json")"

    run mf protect status claude-code --project "$PROJECT_DIR"

    [ "$status" -ne 0 ]
    [[ "$output" == *"claude-code"*"missing"*"exact MAINFRAME hook entry is absent"* ]]
    after="$(jq -cS . "$PROJECT_DIR/.claude/settings.json")"
    [ "$after" = "$before" ]
}

@test "protect status rejects a symbolic-link config path" {
    mkdir -p "$PROJECT_DIR/.codex"
    printf '%s\n' '{}' > "$PROJECT_DIR/team-hooks.json"
    ln -s "$PROJECT_DIR/team-hooks.json" "$PROJECT_DIR/.codex/hooks.json"

    run mf protect status codex --project "$PROJECT_DIR"

    [ "$status" -ne 0 ]
    [[ "$output" == *"codex"*"invalid"*"symbolic-link managed project file"* ]]
}

@test "protect status rejects a symbolic-link config parent" {
    mkdir -p "$PROJECT_DIR/outside-gemini"
    ln -s "$PROJECT_DIR/outside-gemini" "$PROJECT_DIR/.gemini"

    run mf protect status gemini --project "$PROJECT_DIR"

    [ "$status" -ne 0 ]
    [[ "$output" == *"gemini"*"invalid"*"symbolic-link parent"* ]]
}

@test "protect status fails when jq is unavailable" {
    mf activate codex --project "$PROJECT_DIR" --enforce >/dev/null
    no_jq_path="$TEST_DIR/no-jq-bin"
    mkdir -p "$no_jq_path"
    for helper in awk basename cat dirname readlink tr; do
        ln -s "$(command -v "$helper")" "$no_jq_path/$helper"
    done

    run env PATH="$no_jq_path" MAINFRAME_ROOT="$MAINFRAME_ROOT" \
        "$BASH_BIN" --noprofile --norc -p -c \
        'source "$1"; _mainframe_protect_status codex --project "$2"' \
        _ "$MAINFRAME_ROOT/lib/activate.sh" "$PROJECT_DIR"

    [ "$status" -ne 0 ]
    [[ "$output" == *"gateway-bindings"*"not-ready"*"jq was not found"* ]]
    [[ "$output" == *"cannot inspect config because jq is unavailable"* ]]
}

@test "protect status does not depend on an executable named mainframe on PATH" {
    mf activate gemini --project "$PROJECT_DIR" --enforce >/dev/null
    fake_dir="$TEST_DIR/foreign-bin"
    marker="$TEST_DIR/foreign-mainframe-ran"
    mkdir -p "$fake_dir"
    cat > "$fake_dir/mainframe" <<EOF
#!/bin/sh
touch "$marker"
exit 99
EOF
    chmod +x "$fake_dir/mainframe"

    run env PATH="$fake_dir:$BASE_PATH" "$BASH_BIN" "$MAINFRAME_ROOT/bin/mainframe" \
        protect status gemini --project "$PROJECT_DIR"

    [ "$status" -eq 0 ]
    [[ "$output" != *"mainframe-path"* ]]
    [[ "$output" == *"gemini"*"configured"* ]]
    [ ! -e "$marker" ]
}

@test "protect status accepts a new installation binding without config churn" {
    mf activate gemini --project "$PROJECT_DIR" --enforce >/dev/null
    before="$(jq -cS . "$PROJECT_DIR/.gemini/settings.json")"
    fake_keg="$TEST_DIR/Cellar/mainframe/$PROJECT_VERSION"
    fake_root="$fake_keg/libexec"
    mkdir -p "$fake_root/hooks" "$fake_root/lib"
    cp "$MAINFRAME_ROOT/hooks/agent-gateway.sh" "$fake_root/hooks/agent-gateway.sh"
    cp "$MAINFRAME_ROOT/lib/agent_safety.sh" "$fake_root/lib/agent_safety.sh"

    run env PATH="$BASE_PATH" MAINFRAME_ROOT="$fake_root" \
        "$BASH_BIN" --noprofile --norc -p -c \
        'source "$1"; _mainframe_protect_status gemini --project "$2"' \
        _ "$MAINFRAME_ROOT/lib/activate.sh" "$PROJECT_DIR"

    [ "$status" -eq 0 ]
    [[ "$output" == *"agent-gateway"*"ready"*"$fake_root/hooks/agent-gateway.sh"* ]]
    [[ "$output" == *"Static readiness: READY"* ]]
    after="$(jq -cS . "$PROJECT_DIR/.gemini/settings.json")"
    [ "$after" = "$before" ]
}

@test "protect status reports a missing gateway dependency" {
    fake_root="$TEST_DIR/fake-mainframe"
    mkdir -p "$fake_root/hooks"

    run env PATH="$BASE_PATH" MAINFRAME_ROOT="$fake_root" \
        "$BASH_BIN" --noprofile --norc -p -c \
        'source "$1"; _mainframe_protect_status cursor --project "$2"' \
        _ "$MAINFRAME_ROOT/lib/activate.sh" "$PROJECT_DIR"

    [ "$status" -ne 0 ]
    [[ "$output" == *"gateway-bindings"*"not-ready"*"gateway is missing or unsafe"* ]]
}

@test "Bash dependency check rejects versions before 4.4" {
    run "$BASH_BIN" -c 'source "$1"; _mainframe_bash_44_or_newer 4 3' \
        _ "$MAINFRAME_ROOT/lib/activate.sh"
    [ "$status" -ne 0 ]

    run "$BASH_BIN" -c 'source "$1"; _mainframe_bash_44_or_newer 4 4' \
        _ "$MAINFRAME_ROOT/lib/activate.sh"
    [ "$status" -eq 0 ]
}

@test "requesting an instruction-only host is not reported as enforced" {
    run mf protect status cursor --project "$PROJECT_DIR"

    [ "$status" -ne 0 ]
    [[ "$output" == *"cursor"*"instruction-only"* ]]
    [[ "$output" == *"no supported blocking pre-tool adapter"* ]]
}

@test "protect help documents the static and runtime boundary" {
    run mf protect --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: mainframe protect status"* ]]
    [[ "$output" == *"Runtime hook trust/load"* ]]
}

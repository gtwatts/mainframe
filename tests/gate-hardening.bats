#!/usr/bin/env bats
# Regression tests execute helpers only inside their disposable fixture.
# Destructive shell strings are passed only to the analysis-only classifier.
load 'test_helper'

setup() {
    umask 077
    TEST_DIR=$(create_test_dir "gate_hardening")
    export AWM_ROOT="$TEST_DIR/awm"
    export AGENT_AUDIT_LOG="$TEST_DIR/audit.jsonl"
    export AGENT_SAFE_BASE="$TEST_DIR/base"
    export AGENT_CURRENT_PROFILE=project
    mkdir -p "$TEST_DIR/base" "$TEST_DIR/outside"
    source_lib agent_safety
}

teardown() { cleanup_test_dir "$TEST_DIR"; }

@test "readonly policy applies to absolute and relative executable paths" {
    printf '%s' fixture > "$TEST_DIR/base/source"
    AGENT_CURRENT_PROFILE=readonly
    local executable
    executable=$(type -P cp)
    run agent_safe_exec "$executable" "$TEST_DIR/base/source" "$TEST_DIR/base/copy"
    [ "$status" -eq 1 ]
    [[ "$output" == *"write command"* ]]
    [ ! -e "$TEST_DIR/base/copy" ]
    run agent_safe_exec_capture "$executable" "$TEST_DIR/base/source" "$TEST_DIR/base/copy"
    [ "$status" -eq 1 ]
    [ ! -e "$TEST_DIR/base/copy" ]
    run agent_validate_command ./cp source copy
    [ "$status" -eq 1 ]
    [[ "$output" == *"write command"* ]]
}

@test "path-qualified policy remains before existence and confines copy targets" {
    run agent_validate_command /not-installed/mkfs.ext4 /not-a-device
    [ "$status" -eq 1 ]
    [[ "$output" == *"destructive command"* ]]
    run agent_validate_command /not-installed/curl https://example.invalid
    [ "$status" -eq 1 ]
    [[ "$output" == *"network command"* ]]
    printf '%s' fixture > "$TEST_DIR/base/source"
    run agent_safe_exec "$(type -P cp)" "$TEST_DIR/base/source" "$TEST_DIR/outside/copy"
    [ "$status" -eq 1 ]
    [ ! -e "$TEST_DIR/outside/copy" ]
    [ "$(< "$TEST_DIR/base/source")" = fixture ]
}

@test "ensure line checks confinement before write and idempotent return" {
    run agent_ensure_line "$TEST_DIR/outside/line" marker
    [ "$status" -eq 1 ]
    [ ! -e "$TEST_DIR/outside/line" ]
    printf '%s\n' marker > "$TEST_DIR/outside/line"
    run agent_ensure_line "$TEST_DIR/outside/line" marker
    [ "$status" -eq 1 ]
    [ "$(< "$TEST_DIR/outside/line")" = marker ]
    run agent_ensure_line "$TEST_DIR/base/line" marker
    [ "$status" -eq 0 ]
    [ "$(< "$TEST_DIR/base/line")" = marker ]
}

@test "ensure symlink confines both link and its relative referent" {
    printf '%s' fixture > "$TEST_DIR/base/source"
    run agent_ensure_symlink "$TEST_DIR/outside/link" "$TEST_DIR/base/source"
    [ "$status" -eq 1 ]
    [ ! -L "$TEST_DIR/outside/link" ]
    run agent_ensure_symlink "$TEST_DIR/base/link" "$TEST_DIR/outside/target"
    [ "$status" -eq 1 ]
    [ ! -L "$TEST_DIR/base/link" ]
    run agent_ensure_symlink "$TEST_DIR/base/link" source
    [ "$status" -eq 0 ]
    [ "$(readlink "$TEST_DIR/base/link")" = source ]
    run agent_ensure_symlink "$TEST_DIR/base/link" source
    [ "$status" -eq 0 ]
}

@test "realpath failure rejects final symlinks and dangling ancestor escapes" {
    printf '%s' fixture > "$TEST_DIR/outside/target"
    printf '%s' fixture > "$TEST_DIR/base/ordinary"
    ln -s "$TEST_DIR/outside/target" "$TEST_DIR/base/escape"
    ln -s "$TEST_DIR/outside/missing" "$TEST_DIR/base/dangling"
    run _agent_validate_path_safe "$TEST_DIR/base/dangling/new" "$AGENT_SAFE_BASE"
    [ "$status" -eq 1 ]
    realpath() { return 127; }
    run _agent_validate_path_safe "$TEST_DIR/base/escape" "$AGENT_SAFE_BASE"
    [ "$status" -eq 1 ]
    run _agent_validate_path_safe "$TEST_DIR/base/ordinary" "$AGENT_SAFE_BASE"
    [ "$status" -eq 0 ]
    run _agent_validate_path_safe "$TEST_DIR/base/new/ordinary" "$AGENT_SAFE_BASE"
    [ "$status" -eq 0 ]
}

@test "ensure symlink repairs outward final links without following old referents" {
    printf '%s' inside > "$TEST_DIR/base/source"
    printf '%s' outside > "$TEST_DIR/outside/source"
    ln -s "$TEST_DIR/outside/source" "$TEST_DIR/base/link"
    run agent_ensure_symlink "$TEST_DIR/base/link" source
    [ "$status" -eq 0 ]
    [ "$(readlink "$TEST_DIR/base/link")" = source ]
    [ "$(< "$TEST_DIR/outside/source")" = outside ]

    ln -s "$TEST_DIR/outside/missing" "$TEST_DIR/base/dangling"
    realpath() { return 127; }
    run agent_ensure_symlink "$TEST_DIR/base/dangling" source
    [ "$status" -eq 0 ]
    [ "$(readlink "$TEST_DIR/base/dangling")" = source ]
    ln -s "$TEST_DIR/outside/source" "$TEST_DIR/base/another"
    run agent_ensure_symlink "$TEST_DIR/base/another" "$TEST_DIR/base/source"
    [ "$status" -eq 0 ]
    [ "$(readlink "$TEST_DIR/base/another")" = "$TEST_DIR/base/source" ]
}

@test "symlink repair rejects escaping parents and new referents before removal" {
    printf '%s' inside > "$TEST_DIR/base/source"
    ln -s "$TEST_DIR/outside/old" "$TEST_DIR/base/link"
    ln -s "$TEST_DIR/outside" "$TEST_DIR/base/parent"
    ln -s old "$TEST_DIR/outside/link"
    run agent_ensure_symlink "$TEST_DIR/base/link" "$TEST_DIR/outside/new"
    [ "$status" -eq 1 ]
    [ "$(readlink "$TEST_DIR/base/link")" = "$TEST_DIR/outside/old" ]
    run agent_ensure_symlink "$TEST_DIR/base/parent/link" "$TEST_DIR/base/source"
    [ "$status" -eq 1 ]
    [ "$(readlink "$TEST_DIR/outside/link")" = old ]
    realpath() { return 127; }
    run agent_ensure_symlink "$TEST_DIR/base/parent/link" "$TEST_DIR/base/source"
    [ "$status" -eq 1 ]
    [ "$(readlink "$TEST_DIR/outside/link")" = old ]
    run agent_ensure_symlink "$TEST_DIR/outside/link" "$TEST_DIR/base/source"
    [ "$status" -eq 1 ]
    [ "$(readlink "$TEST_DIR/outside/link")" = old ]
}

@test "Bash gate blocks heredoc header substitutions and preserves literal authoring" {
    run agent_gate_classify $'cat <<\'EOF\'; printf "%s" "$(rm -rf /tmp/never-executed)"\nsafe\nEOF\n'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"rule":"dynamic-shell-expansion"'* ]]
    [[ "$output" == *'"blocked":true'* ]]
    run agent_gate_classify $'cat <<\'EOF\'\nIt\'s a "document $(literal)\nEOF\ngit status\n'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"risk":"low"'* ]]
}

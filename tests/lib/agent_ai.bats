#!/usr/bin/env bats

# Smoke tests for the current agent_ai.sh API surface.

load ../test_helper

_agent_ai_test_handler() {
    printf 'handled:%s\n' "${1:-}"
}

_agent_ai_parallel_handler() {
    sleep 0.01
    printf 'parallel:%s\n' "${1:-}"
}

setup() {
    TEST_DIR=$(mktemp -d)
    export AGENT_AI_TEST_MODE=1
    export AGENT_AI_STATE_DIR="$TEST_DIR/state"
    export AGENT_AI_TRANSCRIPT_DIR="$TEST_DIR/transcripts"
    export AGENT_AI_SESSION_FILE="$TEST_DIR/session"

    source "$MAINFRAME_ROOT/lib/common.sh"
    source "$MAINFRAME_ROOT/lib/agent_ai.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "agent_ai_context_init sets max and reserve budget" {
    agent_ai_context_init 1000 20
    [ "$AGENT_AI_CTX_MAX" -eq 1000 ]
    [ "$AGENT_AI_CTX_RESERVE" -eq 200 ]
    [ "$AGENT_AI_CTX_USED" -eq 0 ]
}

@test "agent_ai_context_use returns warning at threshold" {
    agent_ai_context_init 1000 20
    run agent_ai_context_use 650 "warning_test"
    [ "$status" -eq 1 ]
}

@test "agent_ai_context_use returns critical at threshold" {
    agent_ai_context_init 1000 20
    run agent_ai_context_use 770 "critical_test"
    [ "$status" -eq 2 ]
}

@test "agent_ai_tool_register stores allow permission" {
    agent_ai_tool_register "json_escape" "JSON escape helper" "_agent_ai_test_handler" "allow"
    agent_ai_tool_register "json_parse" "JSON parse helper" "_agent_ai_test_handler" "allow"
    [ "${_AGENT_AI_TOOL_PERMS[json_escape]}" = "allow" ]
    [ "${_AGENT_AI_TOOL_PERMS[json_parse]}" = "allow" ]
}

@test "agent_ai_tool_deny blocks function execution" {
    agent_ai_tool_register "rm" "dangerous tool" "_agent_ai_test_handler" "deny"
    run agent_ai_tool_permitted "rm"
    [ "$status" -eq 1 ]
}

@test "agent_ai_tool_permitted allows permitted function" {
    agent_ai_tool_register "echo" "echo tool" "_agent_ai_test_handler" "allow"
    run agent_ai_tool_permitted "echo"
    [ "$status" -eq 0 ]
}

@test "agent_ai_model_edit_format returns diff for Sonnet models" {
    result=$(agent_ai_model_edit_format "claude-sonnet-4")
    [ "$result" = "$AGENT_AI_EDIT_DIFF" ]
}

@test "agent_ai_model_edit_format returns whole-file for Opus models" {
    result=$(agent_ai_model_edit_format "claude-opus-4")
    [ "$result" = "$AGENT_AI_EDIT_WHOLE" ]
}

@test "agent_ai_session_start creates session" {
    sid=$(agent_ai_session_start "test_task")
    [ "$sid" = "test_task" ]
    [ -f "$AGENT_AI_STATE_DIR/test_task.session" ]
}

@test "agent_ai_session_fork creates child session" {
    agent_ai_session_start "parent" >/dev/null
    child=$(agent_ai_session_fork "child_task")
    [ "${AGENT_AI_SESSION_ID}" = "parent" ]
    [ "$child" = "child_task" ]
    [ -f "$AGENT_AI_STATE_DIR/child_task.session" ]
}

@test "agent_ai_spawn creates parallel subagent handle" {
    agent_ai_session_start "spawn_parent" >/dev/null
    aid=$(agent_ai_spawn "worker" "_agent_ai_parallel_handler" --parallel)
    [[ "$aid" == sub_*:* ]]
}

@test "agent_ai_context_status shows critical state at threshold" {
    agent_ai_context_init 1000 20
    agent_ai_context_use 770 "compress_test" || true
    status_json=$(agent_ai_context_status)
    [[ "$status_json" == *'"status":"critical"'* ]]
}

@test "agent_ai_tool_list is empty before registration" {
    result=$(agent_ai_tool_list)
    [ "$result" = "[]" ]
}

@test "agent_ai_context_status reports remaining budget" {
    agent_ai_context_init 1000 0
    agent_ai_context_use 750 "budget_test"
    status_json=$(agent_ai_context_status)
    [[ "$status_json" == *'"remaining":250'* ]]
}

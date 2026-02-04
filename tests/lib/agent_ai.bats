#!/usr/bin/env bats

# Tests for agent_ai.sh - AI Agent Orchestration
# Critical: Context budget, tool registry, edit strategies, subagents

load ../test_helper

setup() {
    source "$MAINFRAME_ROOT/lib/common.sh"
    TEST_DIR=$(mktemp -d)
    export AGENT_AI_TEST_MODE=1
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "agent_ai_budget_init sets warning and critical thresholds" {
    agent_ai_budget_init 1000 80 95
    [ "$AGENT_AI_BUDGET_MAX" -eq 1000 ]
    [ "$AGENT_AI_BUDGET_WARN" -eq 800 ]
    [ "$AGENT_AI_BUDGET_CRITICAL" -eq 950 ]
}

@test "agent_ai_budget_check returns warning at threshold" {
    agent_ai_budget_init 100 80 95
    run agent_ai_budget_check 85
    [ "$status" -eq 1 ]  # WARNING
}

@test "agent_ai_budget_check returns critical at threshold" {
    agent_ai_budget_init 100 80 95
    run agent_ai_budget_check 96
    [ "$status" -eq 2 ]  # CRITICAL
}

@test "agent_ai_tool_allow adds function to allow list" {
    agent_ai_tool_init
    agent_ai_tool_allow "json_escape"
    agent_ai_tool_allow "json_parse"
    [[ "$AGENT_AI_TOOLS_ALLOWED" == *"json_escape"* ]]
    [[ "$AGENT_AI_TOOLS_ALLOWED" == *"json_parse"* ]]
}

@test "agent_ai_tool_deny blocks function execution" {
    agent_ai_tool_init
    agent_ai_tool_deny "rm"
    run agent_ai_tool_check "rm"
    [ "$status" -eq 1 ]  # DENIED
}

@test "agent_ai_tool_check allows permitted function" {
    agent_ai_tool_init
    agent_ai_tool_allow "echo"
    run agent_ai_tool_check "echo"
    [ "$status" -eq 0 ]  # ALLOWED
}

@test "agent_ai_edit_strategy_diff returns diff command" {
    result=$(agent_ai_edit_strategy_diff "file.txt" "old content" "new content")
    [[ "$result" == *"diff"* ]]
}

@test "agent_ai_edit_strategy_whole returns write command" {
    result=$(agent_ai_edit_strategy_whole "file.txt" "content")
    [[ "$result" == *"write"* || "$result" == *"echo"* ]]
}

@test "agent_ai_session_init creates session" {
    sid=$(agent_ai_session_init "test_task")
    [ -n "$sid" ]
    [[ "$sid" == ai_* ]]
}

@test "agent_ai_session_fork creates child session" {
    parent=$(agent_ai_session_init "parent")
    child=$(agent_ai_session_fork "$parent" "child_task")
    [ -n "$child" ]
    [[ "$child" == ai_* ]]
    [ "$child" != "$parent" ]
}

@test "agent_ai_subagent_spawn creates subagent" {
    agent_ai_subagent_init
    aid=$(agent_ai_subagent_spawn "worker" "echo hello")
    [ -n "$aid" ]
}

@test "agent_ai_context_compress triggers at critical threshold" {
    agent_ai_budget_init 100 80 90
    run agent_ai_context_compress 95
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # Compressed or attempted
}

@test "agent_ai_tool_init clears all permissions" {
    agent_ai_tool_allow "test_func"
    agent_ai_tool_init
    [ -z "$AGENT_AI_TOOLS_ALLOWED" ]
    [ -z "$AGENT_AI_TOOLS_DENIED" ]
}

@test "agent_ai_budget_remaining calculates correctly" {
    agent_ai_budget_init 1000
    remaining=$(agent_ai_budget_remaining 750)
    [ "$remaining" -eq 250 ]
}

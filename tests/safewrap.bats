#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: SafeWrap Command Wrapping Pipeline Tests
# =============================================================================
# Tests for lib/safewrap.sh - Transparent safety pipeline for command execution
# =============================================================================

load 'test_helper'

setup() {
    # Force fresh load by unsetting the guard
    unset _MAINFRAME_SAFEWRAP_LOADED
    source_lib "safewrap"
    export TEST_DIR="$(mktemp -d)"
    safewrap_enable
}

teardown() {
    rm -rf "$TEST_DIR"
    safewrap_disable
    safewrap_reset
}

# =============================================================================
# DOUBLE-SOURCE GUARD (1 test)
# =============================================================================

@test "double-source guard prevents re-loading" {
    # After first source, the guard variable should be set
    [ -n "$_MAINFRAME_SAFEWRAP_LOADED" ]

    # Source again - should not error
    source_lib "safewrap"
    [ "$?" -eq 0 ]
}

# =============================================================================
# BASIC COMMAND EXECUTION (7 tests)
# =============================================================================

@test "safewrap executes simple command" {
    run safewrap echo "hello world"
    [ "$status" -eq 0 ]
    [ "$output" = "hello world" ]
}

@test "safewrap passes exit code from command" {
    run safewrap false
    [ "$status" -eq 1 ]
}

@test "safewrap passes successful exit code" {
    run safewrap true
    [ "$status" -eq 0 ]
}

@test "safewrap handles command with multiple arguments" {
    run safewrap printf '%s-%s' "foo" "bar"
    [ "$status" -eq 0 ]
    [ "$output" = "foo-bar" ]
}

@test "safewrap returns error for empty command" {
    run safewrap
    [ "$status" -eq 1 ]
}

@test "safewrap executes command that produces output" {
    echo "test_content" > "$TEST_DIR/file.txt"
    run safewrap cat "$TEST_DIR/file.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "test_content" ]
}

@test "safewrap handles command with special characters in args" {
    run safewrap echo "hello 'world' \"test\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
}

# =============================================================================
# ENABLE/DISABLE TOGGLING (6 tests)
# =============================================================================

@test "safewrap_enable activates wrapping" {
    safewrap_disable
    safewrap_enable
    safewrap_is_enabled
    [ "$?" -eq 0 ]
}

@test "safewrap_disable deactivates wrapping" {
    safewrap_disable
    run safewrap_is_enabled
    [ "$status" -eq 1 ]
}

@test "safewrap_is_enabled returns 0 when enabled" {
    safewrap_enable
    safewrap_is_enabled
}

@test "safewrap_is_enabled returns 1 when disabled" {
    safewrap_disable
    run safewrap_is_enabled
    [ "$status" -eq 1 ]
}

@test "disabled safewrap passes commands through directly" {
    safewrap_disable
    run safewrap echo "passthrough"
    [ "$status" -eq 0 ]
    [ "$output" = "passthrough" ]
}

@test "enable/disable is idempotent" {
    safewrap_enable
    safewrap_enable
    safewrap_is_enabled
    safewrap_disable
    safewrap_disable
    run safewrap_is_enabled
    [ "$status" -eq 1 ]
}

# =============================================================================
# CUSTOM WRAPPER REGISTRATION (8 tests)
# =============================================================================

@test "safewrap_register adds custom wrapper" {
    my_wrapper() { echo "wrapped: $*"; }
    safewrap_register "testcmd" "my_wrapper"
    [ "${_MAINFRAME_WRAP_REGISTRY[testcmd]}" = "my_wrapper" ]
}

@test "safewrap_register fails with empty command" {
    run safewrap_register "" "my_func"
    [ "$status" -eq 1 ]
}

@test "safewrap_register fails with empty function" {
    run safewrap_register "cmd" ""
    [ "$status" -eq 1 ]
}

@test "safewrap_unregister removes wrapper" {
    my_wrapper() { echo "wrapped"; }
    safewrap_register "testcmd" "my_wrapper"
    safewrap_unregister "testcmd"
    [ -z "${_MAINFRAME_WRAP_REGISTRY[testcmd]:-}" ]
}

@test "safewrap_unregister fails for unregistered command" {
    run safewrap_unregister "nonexistent"
    [ "$status" -eq 1 ]
}

@test "safewrap_unregister fails with empty argument" {
    run safewrap_unregister ""
    [ "$status" -eq 1 ]
}

@test "registered wrapper is invoked during safewrap" {
    my_echo_wrapper() {
        echo "WRAPPED: $2"
    }
    safewrap_register "echo" "my_echo_wrapper"
    run safewrap echo "hello"
    [ "$status" -eq 0 ]
    [ "$output" = "WRAPPED: hello" ]
    safewrap_unregister "echo"
}

@test "wrapper receives full command and args" {
    capture_wrapper() {
        # $1 is the original command, $2+ are args
        echo "cmd=$1 args=$2,$3"
    }
    safewrap_register "ls" "capture_wrapper"
    run safewrap ls "-la" "/tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "cmd=ls args=-la,/tmp" ]
    safewrap_unregister "ls"
}

# =============================================================================
# POLICY LEVELS (7 tests)
# =============================================================================

@test "safewrap_policy defaults to moderate" {
    [ "$_MAINFRAME_WRAP_POLICY" = "moderate" ]
}

@test "safewrap_policy sets strict" {
    safewrap_policy "strict"
    [ "$_MAINFRAME_WRAP_POLICY" = "strict" ]
}

@test "safewrap_policy sets moderate" {
    safewrap_policy "moderate"
    [ "$_MAINFRAME_WRAP_POLICY" = "moderate" ]
}

@test "safewrap_policy sets permissive" {
    safewrap_policy "permissive"
    [ "$_MAINFRAME_WRAP_POLICY" = "permissive" ]
}

@test "safewrap_policy rejects invalid level" {
    run safewrap_policy "invalid"
    [ "$status" -eq 1 ]
}

@test "safewrap_policy with no argument reports current" {
    safewrap_policy "strict"
    run safewrap_policy
    [ "$status" -eq 0 ]
    [ "$output" = "strict" ]
}

@test "strict policy has lower block threshold than permissive" {
    safewrap_policy "strict"
    local strict_thresh
    strict_thresh=$(_wrap_block_threshold)

    safewrap_policy "permissive"
    local permissive_thresh
    permissive_thresh=$(_wrap_block_threshold)

    [ "$strict_thresh" -lt "$permissive_thresh" ]
}

# =============================================================================
# BYPASS MODE (5 tests)
# =============================================================================

@test "safewrap_bypass executes command directly" {
    run safewrap_bypass echo "bypassed"
    [ "$status" -eq 0 ]
    [ "$output" = "bypassed" ]
}

@test "safewrap_bypass passes exit code" {
    run safewrap_bypass false
    [ "$status" -eq 1 ]
}

@test "safewrap_bypass fails with empty command" {
    run safewrap_bypass
    [ "$status" -eq 1 ]
}

@test "safewrap_bypass increments bypass counter" {
    safewrap_reset_stats
    safewrap_bypass true
    [ "$_MAINFRAME_WRAP_STATS_BYPASSED" -eq 1 ]
}

@test "safewrap_bypass logs with decision=bypassed" {
    safewrap_clear_log
    safewrap_bypass echo "test"
    local log
    log=$(safewrap_log)
    [[ "$log" == *'"decision":"bypassed"'* ]]
}

# =============================================================================
# LOGGING (7 tests)
# =============================================================================

@test "safewrap_log returns empty array initially" {
    safewrap_clear_log
    run safewrap_log
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "safewrap_log captures executed commands" {
    safewrap_clear_log
    safewrap echo "logged"
    run safewrap_log
    [ "$status" -eq 0 ]
    [[ "$output" == *'"command":"echo"'* ]]
}

@test "safewrap_log captures command args" {
    safewrap_clear_log
    safewrap echo "arg1" "arg2"
    run safewrap_log
    [[ "$output" == *'"args":["arg1","arg2"]'* ]]
}

@test "safewrap_log records exit code" {
    safewrap_clear_log
    safewrap true
    run safewrap_log
    [[ "$output" == *'"exit_code":0'* ]]
}

@test "safewrap_log records decision type" {
    safewrap_clear_log
    safewrap true
    run safewrap_log
    [[ "$output" == *'"decision":"executed"'* ]]
}

@test "safewrap_clear_log empties the log" {
    safewrap echo "entry"
    safewrap_clear_log
    run safewrap_log
    [ "$output" = "[]" ]
}

@test "safewrap_log accumulates multiple entries" {
    safewrap_clear_log
    safewrap true
    safewrap echo "two"
    safewrap true
    local log
    log=$(safewrap_log)
    # Count occurrences of "command" key
    local count
    count=$(echo "$log" | grep -o '"command"' | wc -l)
    [ "$count" -eq 3 ]
}

# =============================================================================
# STATISTICS (7 tests)
# =============================================================================

@test "safewrap_stats returns JSON" {
    run safewrap_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *'"total":'* ]]
    [[ "$output" == *'"executed":'* ]]
    [[ "$output" == *'"blocked":'* ]]
}

@test "safewrap_stats tracks total calls" {
    safewrap_reset_stats
    safewrap true
    safewrap true
    [ "$_MAINFRAME_WRAP_STATS_TOTAL" -eq 2 ]
}

@test "safewrap_stats tracks executed calls" {
    safewrap_reset_stats
    safewrap true
    [ "$_MAINFRAME_WRAP_STATS_EXECUTED" -eq 1 ]
}

@test "safewrap_stats tracks bypassed calls" {
    safewrap_reset_stats
    safewrap_bypass true
    [ "$_MAINFRAME_WRAP_STATS_BYPASSED" -eq 1 ]
}

@test "safewrap_reset_stats zeros all counters" {
    safewrap true
    safewrap_bypass true
    safewrap_reset_stats
    [ "$_MAINFRAME_WRAP_STATS_TOTAL" -eq 0 ]
    [ "$_MAINFRAME_WRAP_STATS_EXECUTED" -eq 0 ]
    [ "$_MAINFRAME_WRAP_STATS_BLOCKED" -eq 0 ]
    [ "$_MAINFRAME_WRAP_STATS_BYPASSED" -eq 0 ]
}

@test "safewrap_stats includes approval_rate" {
    run safewrap_stats
    [[ "$output" == *'"approval_rate":'* ]]
}

@test "safewrap_stats approval_rate is 100 when all executed" {
    safewrap_reset_stats
    safewrap true
    safewrap true
    run safewrap_stats
    [[ "$output" == *'"approval_rate":100'* ]]
}

# =============================================================================
# GRACEFUL DEGRADATION (5 tests)
# =============================================================================

@test "safewrap works without risk.sh loaded" {
    # risk.sh may or may not be loaded; safewrap should work either way
    run safewrap echo "no-risk"
    [ "$status" -eq 0 ]
    [ "$output" = "no-risk" ]
}

@test "safewrap works without scope.sh loaded" {
    run safewrap echo "no-scope"
    [ "$status" -eq 0 ]
    [ "$output" = "no-scope" ]
}

@test "safewrap works without limits.sh loaded" {
    run safewrap echo "no-limits"
    [ "$status" -eq 0 ]
    [ "$output" = "no-limits" ]
}

@test "safewrap works without confirm.sh loaded" {
    run safewrap echo "no-confirm"
    [ "$status" -eq 0 ]
    [ "$output" = "no-confirm" ]
}

@test "safewrap_status shows integration availability" {
    run safewrap_status
    [ "$status" -eq 0 ]
    [[ "$output" == *'"integrations":'* ]]
    [[ "$output" == *'"scope":'* ]]
    [[ "$output" == *'"risk":'* ]]
}

# =============================================================================
# RISK.SH INTEGRATION (6 tests)
# =============================================================================

@test "safewrap blocks high-risk commands with risk.sh" {
    [[ -z "${_MAINFRAME_RISK_LOADED:-}" ]] && source_lib "risk"
    safewrap_policy "strict"

    run safewrap rm -rf /etc
    [ "$status" -eq 1 ]
}

@test "safewrap allows low-risk commands with risk.sh" {
    [[ -z "${_MAINFRAME_RISK_LOADED:-}" ]] && source_lib "risk"

    run safewrap echo "safe"
    [ "$status" -eq 0 ]
    [ "$output" = "safe" ]
}

@test "safewrap records risk_score in log with risk.sh" {
    [[ -z "${_MAINFRAME_RISK_LOADED:-}" ]] && source_lib "risk"
    safewrap_clear_log
    safewrap echo "scored"
    local log
    log=$(safewrap_log)
    [[ "$log" == *'"risk_score":0'* ]]
}

@test "safewrap blocks based on policy threshold with risk.sh" {
    [[ -z "${_MAINFRAME_RISK_LOADED:-}" ]] && source_lib "risk"
    safewrap_policy "strict"

    # chmod scores 5 base which exceeds strict threshold of 4
    run safewrap chmod 777 "$TEST_DIR/file"
    [ "$status" -eq 1 ]
}

@test "safewrap allows moderate-risk with permissive policy" {
    [[ -z "${_MAINFRAME_RISK_LOADED:-}" ]] && source_lib "risk"
    safewrap_policy "permissive"

    # mkdir scores 2 - well under permissive threshold
    run safewrap mkdir -p "$TEST_DIR/subdir"
    [ "$status" -eq 0 ]
}

@test "safewrap increments blocked counter for high-risk" {
    [[ -z "${_MAINFRAME_RISK_LOADED:-}" ]] && source_lib "risk"
    safewrap_reset_stats
    safewrap_policy "strict"

    # This will be blocked by risk threshold
    safewrap rm -rf /etc 2>/dev/null || true
    [ "$_MAINFRAME_WRAP_STATS_BLOCKED" -ge 1 ]
}

# =============================================================================
# SCOPE.SH INTEGRATION (4 tests)
# =============================================================================

@test "safewrap blocks out-of-scope commands with scope.sh" {
    [[ -z "${_MAINFRAME_SCOPE_LOADED:-}" ]] && source_lib "scope"
    export MAINFRAME_SCOPE_ENABLED=1
    mainframe_scope_set commands "echo,cat,true"

    run safewrap ls /tmp
    [ "$status" -eq 1 ]
}

@test "safewrap allows in-scope commands with scope.sh" {
    [[ -z "${_MAINFRAME_SCOPE_LOADED:-}" ]] && source_lib "scope"
    export MAINFRAME_SCOPE_ENABLED=1
    mainframe_scope_set commands "echo,cat,true"

    run safewrap echo "in-scope"
    [ "$status" -eq 0 ]
    [ "$output" = "in-scope" ]
}

@test "safewrap blocks out-of-scope filesystem access" {
    [[ -z "${_MAINFRAME_SCOPE_LOADED:-}" ]] && source_lib "scope"
    export MAINFRAME_SCOPE_ENABLED=1
    mainframe_scope_set filesystem "$TEST_DIR"

    run safewrap cat /etc/passwd
    [ "$status" -eq 1 ]
}

@test "safewrap allows in-scope filesystem access" {
    [[ -z "${_MAINFRAME_SCOPE_LOADED:-}" ]] && source_lib "scope"
    export MAINFRAME_SCOPE_ENABLED=1
    mainframe_scope_set filesystem "$TEST_DIR"

    echo "content" > "$TEST_DIR/test.txt"
    run safewrap cat "$TEST_DIR/test.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "content" ]
}

# =============================================================================
# PIPELINE EXECUTION ORDER (3 tests)
# =============================================================================

@test "pipeline runs scope before risk" {
    [[ -z "${_MAINFRAME_SCOPE_LOADED:-}" ]] && source_lib "scope"
    [[ -z "${_MAINFRAME_RISK_LOADED:-}" ]] && source_lib "risk"
    export MAINFRAME_SCOPE_ENABLED=1
    mainframe_scope_set commands "echo,true,false"
    safewrap_clear_log

    # 'rm' is not in scope, so it should be blocked by scope before risk
    safewrap rm -rf /tmp/test 2>/dev/null || true
    local log
    log=$(safewrap_log)
    # Decision should show blocked (by scope, before risk evaluation matters)
    [[ "$log" == *'"decision":"blocked"'* ]]
}

@test "pipeline runs risk after scope passes" {
    [[ -z "${_MAINFRAME_RISK_LOADED:-}" ]] && source_lib "risk"
    safewrap_policy "strict"
    safewrap_clear_log

    # rm scores high risk, should be blocked by risk stage
    safewrap rm -rf /etc 2>/dev/null || true
    local log
    log=$(safewrap_log)
    [[ "$log" == *'"decision":"blocked"'* ]]
}

@test "pipeline executes when all stages pass" {
    safewrap_clear_log
    safewrap echo "all-clear"
    local log
    log=$(safewrap_log)
    [[ "$log" == *'"decision":"executed"'* ]]
}

# =============================================================================
# EDGE CASES (5 tests)
# =============================================================================

@test "safewrap handles command with path prefix" {
    run safewrap /bin/echo "pathed"
    [ "$status" -eq 0 ]
    [ "$output" = "pathed" ]
}

@test "safewrap handles command not found" {
    run safewrap nonexistent_command_xyz123
    [ "$status" -ne 0 ]
}

@test "safewrap_status works with no wrappers registered" {
    safewrap_reset
    safewrap_enable
    run safewrap_status
    [ "$status" -eq 0 ]
    [[ "$output" == *'"wrapper_count":0'* ]]
}

@test "safewrap_reset clears all state" {
    safewrap_register "testcmd" "testfunc"
    safewrap true
    safewrap_policy "strict"
    safewrap_reset

    [ "$_MAINFRAME_WRAP_STATS_TOTAL" -eq 0 ]
    [ "$_MAINFRAME_WRAP_POLICY" = "moderate" ]
    [ "$_MAINFRAME_WRAP_ENABLED" -eq 0 ]
    [ -z "${_MAINFRAME_WRAP_REGISTRY[testcmd]:-}" ]
}

@test "safewrap passthrough mode still logs" {
    safewrap_disable
    safewrap_clear_log
    safewrap echo "passthrough-logged"
    local log
    log=$(safewrap_log)
    [[ "$log" == *'"decision":"passthrough"'* ]]
}

# =============================================================================
# JSON OUTPUT MODE (4 tests)
# =============================================================================

@test "safewrap_stats produces USOP envelope in json mode" {
    MAINFRAME_OUTPUT="json"
    run safewrap_stats
    MAINFRAME_OUTPUT=""
    [ "$status" -eq 0 ]
    [[ "$output" == *'"ok":true'* ]]
    [[ "$output" == *'"data":'* ]]
}

@test "safewrap_log produces USOP envelope in json mode" {
    safewrap_clear_log
    safewrap true
    MAINFRAME_OUTPUT="json"
    run safewrap_log
    MAINFRAME_OUTPUT=""
    [[ "$output" == *'"ok":true'* ]]
    [[ "$output" == *'"meta":{"count":1}'* ]]
}

@test "safewrap error produces JSON on stderr in json mode" {
    MAINFRAME_OUTPUT="json"
    run safewrap
    MAINFRAME_OUTPUT=""
    [ "$status" -eq 1 ]
}

@test "safewrap_policy reports JSON in json mode" {
    MAINFRAME_OUTPUT="json"
    safewrap_policy "strict"
    run safewrap_policy
    MAINFRAME_OUTPUT=""
    [[ "$output" == *'"policy":"strict"'* ]]
}

# =============================================================================
# safewrap_status COMPREHENSIVE (3 tests)
# =============================================================================

@test "safewrap_status includes policy info" {
    safewrap_policy "permissive"
    run safewrap_status
    [[ "$output" == *'"policy":"permissive"'* ]]
}

@test "safewrap_status includes registered wrappers" {
    my_wrap() { true; }
    safewrap_register "mycmd" "my_wrap"
    run safewrap_status
    [[ "$output" == *'"mycmd":"my_wrap"'* ]]
    safewrap_unregister "mycmd"
}

@test "safewrap_status includes stats" {
    safewrap_reset_stats
    safewrap true
    run safewrap_status
    [[ "$output" == *'"total":1'* ]]
}

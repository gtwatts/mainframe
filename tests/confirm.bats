#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Confirmation Gate Tests
# =============================================================================
# Tests for lib/confirm.sh - Human/orchestrator approval gates
# =============================================================================

load 'test_helper'

setup() {
    source_lib "confirm"
    export TEST_DIR="$(mktemp -d)"
    mainframe_confirm_auto_approve  # Tests don't need real input
}

teardown() {
    rm -rf "$TEST_DIR"
    mainframe_confirm_reset
}

# =============================================================================
# DOUBLE-SOURCE GUARD (1 test)
# =============================================================================

@test "double-source guard prevents reloading" {
    [ "$_MAINFRAME_CONFIRM_LOADED" = "1" ]
    # Source again - should not error
    source "$MAINFRAME_ROOT/lib/confirm.sh"
    [ "$_MAINFRAME_CONFIRM_LOADED" = "1" ]
}

# =============================================================================
# AUTO-APPROVE MODE (8 tests)
# =============================================================================

@test "auto_approve: mainframe_confirm returns 0" {
    mainframe_confirm_auto_approve
    mainframe_confirm "Test message"
}

@test "auto_approve: records decision in history" {
    mainframe_confirm_auto_approve
    mainframe_confirm_clear_log
    mainframe_confirm "Approve this?"
    local count
    count=$(mainframe_confirm_count)
    [ "$count" -eq 1 ]
}

@test "auto_approve: history shows approved decision" {
    mainframe_confirm_auto_approve
    mainframe_confirm_clear_log
    mainframe_confirm "Test action"
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" '"decision":"approved"'
}

@test "auto_approve: history shows auto method" {
    mainframe_confirm_auto_approve
    mainframe_confirm_clear_log
    mainframe_confirm "Test action"
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" '"method":"auto"'
}

@test "auto_approve: multiple confirmations all succeed" {
    mainframe_confirm_auto_approve
    mainframe_confirm_clear_log
    mainframe_confirm "First"
    mainframe_confirm "Second"
    mainframe_confirm "Third"
    local count
    count=$(mainframe_confirm_count)
    [ "$count" -eq 3 ]
}

@test "auto_approve: confirm_risk returns 0" {
    mainframe_confirm_auto_approve
    mainframe_confirm_risk rm -rf /tmp/test
}

@test "auto_approve: confirm_batch returns 0" {
    mainframe_confirm_auto_approve
    mainframe_confirm_batch "Deploy" "git add ." "git commit" "git push"
}

@test "auto_approve: confirm_timeout returns 0" {
    mainframe_confirm_auto_approve
    mainframe_confirm_timeout "Quick action?" 5
}

# =============================================================================
# AUTO-DENY MODE (8 tests)
# =============================================================================

@test "auto_deny: mainframe_confirm returns 1" {
    mainframe_confirm_auto_deny
    run mainframe_confirm "Test message"
    [ "$status" -eq 1 ]
}

@test "auto_deny: records denied decision" {
    mainframe_confirm_auto_deny
    mainframe_confirm_clear_log
    run mainframe_confirm "Deny this?"
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" '"decision":"denied"'
}

@test "auto_deny: history shows auto method" {
    mainframe_confirm_auto_deny
    mainframe_confirm_clear_log
    run mainframe_confirm "Test"
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" '"method":"auto"'
}

@test "auto_deny: confirm_risk returns 1" {
    mainframe_confirm_auto_deny
    run mainframe_confirm_risk ls -la
    [ "$status" -eq 1 ]
}

@test "auto_deny: confirm_batch returns 1" {
    mainframe_confirm_auto_deny
    run mainframe_confirm_batch "Deploy" "git add ." "git push"
    [ "$status" -eq 1 ]
}

@test "auto_deny: confirm_timeout returns 1" {
    mainframe_confirm_auto_deny
    run mainframe_confirm_timeout "Action?" 10
    [ "$status" -eq 1 ]
}

@test "auto_deny: multiple denials all recorded" {
    mainframe_confirm_auto_deny
    mainframe_confirm_clear_log
    run mainframe_confirm "First"
    run mainframe_confirm "Second"
    local count
    count=$(mainframe_confirm_count)
    [ "$count" -eq 2 ]
}

@test "auto_deny: confirm_timeout records timeout method" {
    mainframe_confirm_auto_deny
    mainframe_confirm_clear_log
    run mainframe_confirm_timeout "Timeout test" 5
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" '"method":"timeout"'
}

# =============================================================================
# POLICY SWITCHING (7 tests)
# =============================================================================

@test "policy: set to always succeeds" {
    mainframe_confirm_policy "always"
    local status_out
    status_out=$(mainframe_confirm_status)
    assert_contains "$status_out" '"policy":"always"'
}

@test "policy: set to never succeeds" {
    mainframe_confirm_policy "never"
    local status_out
    status_out=$(mainframe_confirm_status)
    assert_contains "$status_out" '"policy":"never"'
}

@test "policy: set to risk succeeds" {
    mainframe_confirm_policy "risk"
    local status_out
    status_out=$(mainframe_confirm_status)
    assert_contains "$status_out" '"policy":"risk"'
}

@test "policy: invalid policy returns 1" {
    run mainframe_confirm_policy "invalid"
    [ "$status" -eq 1 ]
}

@test "policy: empty policy returns 1" {
    run mainframe_confirm_policy ""
    [ "$status" -eq 1 ]
}

@test "policy: set policy then verify via status" {
    mainframe_confirm_policy "risk"
    local result
    result=$(mainframe_confirm_status)
    assert_contains "$result" '"policy":"risk"'
}

@test "policy: reset restores always policy" {
    mainframe_confirm_policy "never"
    mainframe_confirm_reset
    local result
    result=$(mainframe_confirm_status)
    assert_contains "$result" '"policy":"always"'
}

# =============================================================================
# THRESHOLD LEVELS (8 tests)
# =============================================================================

@test "threshold: set to 3 succeeds" {
    mainframe_confirm_threshold 3
    local result
    result=$(mainframe_confirm_status)
    assert_contains "$result" '"threshold":3'
}

@test "threshold: set to 0 succeeds" {
    mainframe_confirm_threshold 0
    local result
    result=$(mainframe_confirm_status)
    assert_contains "$result" '"threshold":0'
}

@test "threshold: set to 10 succeeds" {
    mainframe_confirm_threshold 10
    local result
    result=$(mainframe_confirm_status)
    assert_contains "$result" '"threshold":10'
}

@test "threshold: non-numeric returns 1" {
    run mainframe_confirm_threshold "abc"
    [ "$status" -eq 1 ]
}

@test "threshold: empty returns 1" {
    run mainframe_confirm_threshold ""
    [ "$status" -eq 1 ]
}

@test "threshold: negative returns 1" {
    run mainframe_confirm_threshold "-1"
    [ "$status" -eq 1 ]
}

@test "threshold: 11 returns 1 (out of range)" {
    run mainframe_confirm_threshold 11
    [ "$status" -eq 1 ]
}

@test "threshold: reset restores default 5" {
    mainframe_confirm_threshold 8
    mainframe_confirm_reset
    local result
    result=$(mainframe_confirm_status)
    assert_contains "$result" '"threshold":5'
}

# =============================================================================
# HISTORY TRACKING (10 tests)
# =============================================================================

@test "history: starts empty after clear" {
    mainframe_confirm_clear_log
    local count
    count=$(mainframe_confirm_count)
    [ "$count" -eq 0 ]
}

@test "history: increments on confirm" {
    mainframe_confirm_clear_log
    mainframe_confirm "First"
    local count
    count=$(mainframe_confirm_count)
    [ "$count" -eq 1 ]
}

@test "history: log returns valid JSON array" {
    mainframe_confirm_clear_log
    mainframe_confirm "Test"
    local log
    log=$(mainframe_confirm_log)
    assert_starts_with "$log" "["
    assert_ends_with "$log" "]"
}

@test "history: empty log returns empty JSON array" {
    mainframe_confirm_clear_log
    local log
    log=$(mainframe_confirm_log)
    [ "$log" = "[]" ]
}

@test "history: entries contain timestamp" {
    mainframe_confirm_clear_log
    mainframe_confirm "Time test"
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" '"timestamp":'
}

@test "history: entries contain message" {
    mainframe_confirm_clear_log
    mainframe_confirm "My unique message"
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" '"message":"My unique message"'
}

@test "history: entries contain decision" {
    mainframe_confirm_clear_log
    mainframe_confirm "Decision test"
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" '"decision":"approved"'
}

@test "history: entries contain method" {
    mainframe_confirm_clear_log
    mainframe_confirm "Method test"
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" '"method":"auto"'
}

@test "history: last returns error on empty history" {
    mainframe_confirm_clear_log
    run mainframe_confirm_last
    [ "$status" -eq 1 ]
}

@test "history: multiple entries preserved in order" {
    mainframe_confirm_clear_log
    mainframe_confirm "First entry"
    mainframe_confirm "Second entry"
    mainframe_confirm "Third entry"
    local log
    log=$(mainframe_confirm_log)
    # Check that all entries are present
    assert_contains "$log" '"message":"First entry"'
    assert_contains "$log" '"message":"Second entry"'
    assert_contains "$log" '"message":"Third entry"'
}

# =============================================================================
# BATCH CONFIRMATIONS (6 tests)
# =============================================================================

@test "batch: requires description and at least one command" {
    mainframe_confirm_auto_approve
    run mainframe_confirm_batch "Only description"
    [ "$status" -eq 1 ]
}

@test "batch: approves with valid description and commands" {
    mainframe_confirm_auto_approve
    mainframe_confirm_batch "Deploy" "cmd1" "cmd2"
}

@test "batch: records batch in history" {
    mainframe_confirm_auto_approve
    mainframe_confirm_clear_log
    mainframe_confirm_batch "Build" "make" "make install"
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" "batch:Build"
}

@test "batch: records command count in history" {
    mainframe_confirm_auto_approve
    mainframe_confirm_clear_log
    mainframe_confirm_batch "Release" "test" "build" "deploy"
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" "3 cmds"
}

@test "batch: denied in auto_deny mode" {
    mainframe_confirm_auto_deny
    run mainframe_confirm_batch "Ops" "cmd1" "cmd2"
    [ "$status" -eq 1 ]
}

@test "batch: denied batch recorded in history" {
    mainframe_confirm_auto_deny
    mainframe_confirm_clear_log
    run mainframe_confirm_batch "Denied batch" "cmd1"
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" '"decision":"denied"'
}

# =============================================================================
# TIMEOUT BEHAVIOR (5 tests)
# =============================================================================

@test "timeout: auto_deny simulates timeout denial" {
    mainframe_confirm_auto_deny
    mainframe_confirm_clear_log
    run mainframe_confirm_timeout "Timeout test" 1
    [ "$status" -eq 1 ]
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" '"method":"timeout"'
}

@test "timeout: auto_approve bypasses timeout" {
    mainframe_confirm_auto_approve
    mainframe_confirm_timeout "Quick" 1
}

@test "timeout: records message in history" {
    mainframe_confirm_auto_deny
    mainframe_confirm_clear_log
    run mainframe_confirm_timeout "My timeout msg" 5
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" '"message":"My timeout msg"'
}

@test "timeout: non-numeric timeout defaults to 30" {
    mainframe_confirm_auto_approve
    mainframe_confirm_clear_log
    mainframe_confirm_timeout "Default timeout" "abc"
    local count
    count=$(mainframe_confirm_count)
    [ "$count" -eq 1 ]
}

@test "timeout: zero timeout still works" {
    mainframe_confirm_auto_deny
    run mainframe_confirm_timeout "Zero timeout" 0
    [ "$status" -eq 1 ]
}

# =============================================================================
# RISK INTEGRATION (8 tests)
# =============================================================================

@test "risk: empty command denied" {
    mainframe_confirm_auto_approve
    # Even in auto_approve, empty command is explicitly denied by confirm_risk
    _MAINFRAME_CONFIRM_MODE="interactive"
    run mainframe_confirm_risk
    [ "$status" -eq 1 ]
}

@test "risk: auto_approve bypasses risk check" {
    mainframe_confirm_auto_approve
    mainframe_confirm_risk rm -rf /
}

@test "risk: auto_deny bypasses risk check" {
    mainframe_confirm_auto_deny
    run mainframe_confirm_risk ls
    [ "$status" -eq 1 ]
}

@test "risk: with risk.sh loaded, low-risk auto-approves" {
    # Load risk.sh for integration
    source_lib "risk"
    # Set mode to interactive so risk logic is actually used
    _MAINFRAME_CONFIRM_MODE="interactive"
    # Set threshold high so ls (score 0) is auto-approved
    _MAINFRAME_CONFIRM_THRESHOLD=5
    mainframe_confirm_clear_log
    mainframe_confirm_risk ls -la
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" '"decision":"approved"'
    assert_contains "$last" '"method":"risk"'
}

@test "risk: with risk.sh loaded, safe command below threshold" {
    source_lib "risk"
    _MAINFRAME_CONFIRM_MODE="interactive"
    _MAINFRAME_CONFIRM_THRESHOLD=5
    mainframe_confirm_risk cat /etc/hostname
}

@test "risk: records risk method for approved command" {
    source_lib "risk"
    _MAINFRAME_CONFIRM_MODE="interactive"
    _MAINFRAME_CONFIRM_THRESHOLD=5
    mainframe_confirm_clear_log
    mainframe_confirm_risk echo "hello"
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" '"method":"risk"'
}

@test "risk: threshold 0 means all commands need confirmation" {
    source_lib "risk"
    _MAINFRAME_CONFIRM_THRESHOLD=0
    # Even ls scores 0, which is NOT less than 0
    # So it should prompt - we use auto_deny to simulate denial
    _MAINFRAME_CONFIRM_MODE="auto_deny"
    run mainframe_confirm_risk ls
    [ "$status" -eq 1 ]
}

@test "risk: threshold 10 auto-approves most commands" {
    source_lib "risk"
    _MAINFRAME_CONFIRM_MODE="interactive"
    _MAINFRAME_CONFIRM_THRESHOLD=10
    mainframe_confirm_clear_log
    # rm scores 6 base, below threshold 10
    mainframe_confirm_risk rm /tmp/test
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" '"decision":"approved"'
}

# =============================================================================
# STATUS OUTPUT (5 tests)
# =============================================================================

@test "status: returns valid JSON" {
    local result
    result=$(mainframe_confirm_status)
    assert_contains "$result" '"mode":'
    assert_contains "$result" '"policy":'
    assert_contains "$result" '"threshold":'
}

@test "status: shows current mode" {
    mainframe_confirm_auto_approve
    local result
    result=$(mainframe_confirm_status)
    assert_contains "$result" '"mode":"auto_approve"'
}

@test "status: shows history count" {
    mainframe_confirm_clear_log
    mainframe_confirm "One"
    mainframe_confirm "Two"
    local result
    result=$(mainframe_confirm_status)
    assert_contains "$result" '"history_count":2'
}

@test "status: shows risk_integration flag" {
    local result
    result=$(mainframe_confirm_status)
    assert_contains "$result" '"risk_integration":'
}

@test "status: risk_integration true when risk.sh loaded" {
    source_lib "risk"
    local result
    result=$(mainframe_confirm_status)
    assert_contains "$result" '"risk_integration":true'
}

# =============================================================================
# EDGE CASES (7 tests)
# =============================================================================

@test "edge: confirm with empty message uses default" {
    mainframe_confirm_auto_approve
    mainframe_confirm_clear_log
    mainframe_confirm ""
    local count
    count=$(mainframe_confirm_count)
    [ "$count" -eq 1 ]
}

@test "edge: confirm with special characters in message" {
    mainframe_confirm_auto_approve
    mainframe_confirm_clear_log
    mainframe_confirm 'Delete "all" files & folders?'
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" "timestamp"
}

@test "edge: confirm with newline in message" {
    mainframe_confirm_auto_approve
    mainframe_confirm_clear_log
    mainframe_confirm "Line1
Line2"
    local last
    last=$(mainframe_confirm_last)
    # Should be escaped in JSON (single \n in output)
    assert_contains "$last" '\n'
}

@test "edge: clear_log is idempotent" {
    mainframe_confirm_clear_log
    mainframe_confirm_clear_log
    mainframe_confirm_clear_log
    local count
    count=$(mainframe_confirm_count)
    [ "$count" -eq 0 ]
}

@test "edge: count returns 0 type when empty" {
    mainframe_confirm_clear_log
    local count
    count=$(mainframe_confirm_count)
    [ "$count" -eq 0 ]
}

@test "edge: mode switching mid-session" {
    mainframe_confirm_clear_log
    mainframe_confirm_auto_approve
    mainframe_confirm "Approved"
    mainframe_confirm_auto_deny
    run mainframe_confirm "Denied"
    [ "$status" -eq 1 ]
    local count
    count=$(mainframe_confirm_count)
    [ "$count" -eq 2 ]
}

@test "edge: batch with single command works" {
    mainframe_confirm_auto_approve
    mainframe_confirm_batch "Single" "one_cmd"
}

# =============================================================================
# JSON OUTPUT MODE (5 tests)
# =============================================================================

@test "json: confirm outputs JSON when MAINFRAME_OUTPUT=json" {
    mainframe_confirm_auto_approve
    export MAINFRAME_OUTPUT=json
    local result
    result=$(mainframe_confirm "JSON test")
    assert_contains "$result" '"ok":true'
    assert_contains "$result" '"decision":"approved"'
    unset MAINFRAME_OUTPUT
}

@test "json: status outputs wrapped JSON when MAINFRAME_OUTPUT=json" {
    export MAINFRAME_OUTPUT=json
    local result
    result=$(mainframe_confirm_status)
    assert_contains "$result" '"ok":true'
    assert_contains "$result" '"data":'
    unset MAINFRAME_OUTPUT
}

@test "json: policy error outputs JSON error" {
    export MAINFRAME_OUTPUT=json
    local result
    result=$(mainframe_confirm_policy "bad" 2>&1) || true
    assert_contains "$result" '"ok":false'
    assert_contains "$result" "E_INVALID_POLICY"
    unset MAINFRAME_OUTPUT
}

@test "json: threshold outputs JSON on success" {
    export MAINFRAME_OUTPUT=json
    local result
    result=$(mainframe_confirm_threshold 7)
    assert_contains "$result" '"ok":true'
    assert_contains "$result" '"threshold":7'
    unset MAINFRAME_OUTPUT
}

@test "json: log outputs wrapped JSON when MAINFRAME_OUTPUT=json" {
    mainframe_confirm_clear_log
    mainframe_confirm "Entry"
    export MAINFRAME_OUTPUT=json
    local result
    result=$(mainframe_confirm_log)
    assert_contains "$result" '"ok":true'
    assert_contains "$result" '"data":['
    unset MAINFRAME_OUTPUT
}

# =============================================================================
# RESET BEHAVIOR (4 tests)
# =============================================================================

@test "reset: mode returns to interactive" {
    mainframe_confirm_auto_approve
    mainframe_confirm_reset
    local result
    result=$(mainframe_confirm_status)
    assert_contains "$result" '"mode":"interactive"'
}

@test "reset: policy returns to always" {
    mainframe_confirm_policy "risk"
    mainframe_confirm_reset
    local result
    result=$(mainframe_confirm_status)
    assert_contains "$result" '"policy":"always"'
}

@test "reset: threshold returns to 5" {
    mainframe_confirm_threshold 9
    mainframe_confirm_reset
    local result
    result=$(mainframe_confirm_status)
    assert_contains "$result" '"threshold":5'
}

@test "reset: history preserved after reset" {
    mainframe_confirm_auto_approve
    mainframe_confirm_clear_log
    mainframe_confirm "Before reset"
    mainframe_confirm_reset
    # Switch back to auto_approve so we can add more
    mainframe_confirm_auto_approve
    mainframe_confirm "After reset"
    local count
    count=$(mainframe_confirm_count)
    [ "$count" -eq 2 ]
}

# =============================================================================
# CONFIRM_RISK EDGE CASES (3 tests)
# =============================================================================

@test "risk_edge: confirm_risk records command in history message" {
    mainframe_confirm_auto_approve
    mainframe_confirm_clear_log
    mainframe_confirm_risk chmod 777 /tmp/test
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" "chmod 777 /tmp/test"
}

@test "risk_edge: confirm_risk denied records in history" {
    mainframe_confirm_auto_deny
    mainframe_confirm_clear_log
    run mainframe_confirm_risk rm -rf /
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" '"decision":"denied"'
}

@test "risk_edge: risk score extraction with MAINFRAME_OUTPUT unset" {
    source_lib "risk"
    _MAINFRAME_CONFIRM_MODE="interactive"
    _MAINFRAME_CONFIRM_THRESHOLD=8
    unset MAINFRAME_OUTPUT
    mainframe_confirm_clear_log
    # ls scores 0, well below threshold 8
    mainframe_confirm_risk ls
    local last
    last=$(mainframe_confirm_last)
    assert_contains "$last" '"decision":"approved"'
}

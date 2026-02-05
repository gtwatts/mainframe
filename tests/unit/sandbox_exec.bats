#!/usr/bin/env bats
# Tests for Sandboxed Execution

load '../bats-support/load'
load '../bats-assert/load'

setup() {
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    export TEST_TMPDIR="$(mktemp -d)"
    source "$MAINFRAME_ROOT/lib/sandbox_exec.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "sandbox_available: returns capability status" {
    run sandbox_available
    assert_success
    # Should return full, partial, or none
    assert [ -n "$output" ]
}

@test "sandbox_capabilities: returns JSON capabilities" {
    run sandbox_capabilities
    assert_success
    assert_output --partial '"timeout"'
}

@test "sandbox_exec: runs command successfully" {
    run sandbox_exec -- echo "hello"
    assert_success
    assert_output --partial "hello"
}

@test "sandbox_exec: captures exit code" {
    run sandbox_exec -- false
    assert_failure
}

@test "sandbox_exec_with_report: returns resource usage" {
    run sandbox_exec_with_report -- echo "test"
    assert_success
    assert_output --partial "exit_code"
    assert_output --partial "cpu_time"
}

@test "sandbox_show_limits: displays current limits" {
    run sandbox_show_limits
    assert_success
    assert_output --partial "CPU"
    assert_output --partial "Memory"
}

@test "sandbox_reset_limits: resets to defaults" {
    sandbox_set_limits --cpu 10
    sandbox_reset_limits
    
    [ "$SANDBOX_MAX_CPU_SECONDS" = "30" ]  # Default value
}

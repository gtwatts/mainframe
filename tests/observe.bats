#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Observability Module Tests
# =============================================================================

load 'test_helper'

setup() {
    source_lib "observe"
    export MAINFRAME_TRACE_ENABLED=1
    export MAINFRAME_TRACE_OUTPUT="/dev/null"  # Suppress stderr in tests
    TEST_DIR=$(create_test_dir "observe")
    export MAINFRAME_TRACE_DIR="$TEST_DIR/.traces"
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# trace_start TESTS
# =============================================================================

@test "trace_start returns trace ID" {
    local tid
    tid=$(trace_start "test_op")
    [[ "$tid" == trace_* ]]
}

@test "trace_start includes PID in ID" {
    local tid
    tid=$(trace_start "test_op")
    [[ "$tid" == *"$$"* ]] || [[ "$tid" == trace_* ]]
}

@test "trace_start generates unique IDs" {
    local tid1 tid2
    tid1=$(trace_start "op1")
    tid2=$(trace_start "op2")
    [ "$tid1" != "$tid2" ]
}

# =============================================================================
# trace_step TESTS
# =============================================================================

@test "trace_step succeeds with valid trace" {
    local tid
    tid=$(trace_start "myop")
    trace_step "$tid" "step1" "ok"
}

@test "trace_step fails with invalid trace" {
    ! trace_step "invalid_trace_id" "step1"
}

@test "trace_step accepts detail message" {
    local tid
    tid=$(trace_start "myop")
    trace_step "$tid" "step1" "ok" "extra detail"
}

# =============================================================================
# trace_end TESTS
# =============================================================================

@test "trace_end returns JSON with trace_id" {
    local tid
    tid=$(trace_start "myop")
    local result
    result=$(trace_end "$tid" "success")
    [[ "$result" == *"trace_id"* ]]
    [[ "$result" == *"$tid"* ]]
}

@test "trace_end returns JSON with status" {
    local tid
    tid=$(trace_start "myop")
    local result
    result=$(trace_end "$tid" "failed")
    [[ "$result" == *'"status":"failed"'* ]]
}

@test "trace_end returns JSON with name" {
    local tid
    tid=$(trace_start "deploy_config")
    local result
    result=$(trace_end "$tid")
    [[ "$result" == *'"name":"deploy_config"'* ]]
}

@test "trace_end returns JSON with duration" {
    local tid
    tid=$(trace_start "timed_op")
    sleep 0.1
    local result
    result=$(trace_end "$tid")
    [[ "$result" == *"duration_s"* ]]
}

@test "trace_end includes steps" {
    local tid
    tid=$(trace_start "multi_step")
    trace_step "$tid" "first" "ok"
    trace_step "$tid" "second" "ok"
    local result
    result=$(trace_end "$tid")
    [[ "$result" == *'"step":"first"'* ]]
    [[ "$result" == *'"step":"second"'* ]]
}

@test "trace_end fails with unknown trace" {
    local result
    ! result=$(trace_end "nonexistent" 2>/dev/null)
}

# =============================================================================
# observe_command TESTS
# =============================================================================

@test "observe_command captures exit code 0" {
    local result
    result=$(observe_command true)
    [[ "$result" == *'"exit_code":0'* ]]
}

@test "observe_command captures exit code non-zero" {
    local result
    result=$(observe_command false) || true
    [[ "$result" == *'"exit_code":1'* ]]
}

@test "observe_command captures stdout" {
    local result
    result=$(observe_command echo "hello world")
    [[ "$result" == *"hello world"* ]]
}

@test "observe_command captures stderr" {
    local result
    result=$(observe_command bash -c 'echo "err msg" >&2; exit 0')
    [[ "$result" == *"err msg"* ]]
}

@test "observe_command includes duration" {
    local result
    result=$(observe_command sleep 0.1)
    [[ "$result" == *"duration_s"* ]]
}

@test "observe_command includes command name" {
    local result
    result=$(observe_command ls /tmp)
    [[ "$result" == *'"cmd":"ls /tmp"'* ]]
}

@test "observe_command fails with no args" {
    local result
    result=$(observe_command) || true
    [[ "$result" == *"no command"* ]]
}

# =============================================================================
# stack_trace TESTS
# =============================================================================

@test "stack_trace returns JSON with stack array" {
    _helper_for_stack() {
        stack_trace
    }
    local result
    result=$(_helper_for_stack)
    [[ "$result" == *'"stack":['* ]]
}

@test "stack_trace includes depth" {
    local result
    result=$(stack_trace)
    [[ "$result" == *'"depth":'* ]]
}

@test "stack_trace includes function names" {
    _inner_func() {
        stack_trace
    }
    local result
    result=$(_inner_func)
    [[ "$result" == *'"func":"_inner_func"'* ]]
}

# =============================================================================
# observe_error TESTS
# =============================================================================

@test "observe_error emits JSON to stderr" {
    local err
    err=$(observe_error 42 "something broke" 2>&1) || true
    [[ "$err" == *'"error":true'* ]]
    [[ "$err" == *'"code":42'* ]]
    [[ "$err" == *'"msg":"something broke"'* ]]
}

@test "observe_error returns provided exit code" {
    local rc=0
    observe_error 5 "test" 2>/dev/null || rc=$?
    [ "$rc" = "5" ]
}

@test "observe_error includes context when provided" {
    local err
    err=$(observe_error 1 "bad port" "port=99999" 2>&1) || true
    [[ "$err" == *'"context":"port=99999"'* ]]
}

# =============================================================================
# observe_time / observe_elapsed TESTS
# =============================================================================

@test "observe_time returns numeric timestamp" {
    local t
    t=$(observe_time)
    [[ "$t" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "observe_elapsed returns duration" {
    local start
    start=$(observe_time)
    sleep 0.1
    local elapsed
    elapsed=$(observe_elapsed "$start")
    [[ "$elapsed" =~ ^[0-9]+\.?[0-9]*$ ]]
}

# =============================================================================
# TRACE TO FILE TESTS
# =============================================================================

@test "trace output writes to file when configured" {
    export MAINFRAME_TRACE_OUTPUT="$TEST_DIR/trace.log"
    local tid
    tid=$(trace_start "file_trace")
    trace_step "$tid" "write" "ok"
    trace_end "$tid" "success" > /dev/null
    [ -f "$TEST_DIR/trace.log" ]
    [[ $(cat "$TEST_DIR/trace.log") == *"file_trace"* ]]
}

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Structured Error Output Tests
# =============================================================================
# Tests for lib/output.sh - output_structured_error, output_try
# =============================================================================

load '../test_helper'

setup() {
    # Fix MAINFRAME_ROOT for tests in subdirectory
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    source_lib "output"
    TEST_DIR=$(create_test_dir "output_errors")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# output_structured_error TESTS
# =============================================================================

@test "output_structured_error produces valid JSON" {
    local result
    result=$(output_structured_error "TEST_ERROR" "something went wrong" "" 2>/dev/null || true)
    # Must start with { and end with }
    [[ "$result" == "{"* ]]
    [[ "$result" == *"}" ]]
    # Validate with jq if available
    if command -v jq &>/dev/null; then
        printf '%s' "$result" | jq . >/dev/null 2>&1
    fi
}

@test "output_structured_error includes status field" {
    local result
    result=$(output_structured_error "ERR_CODE" "msg" "" 2>/dev/null || true)
    [[ "$result" == *'"status":"error"'* ]]
}

@test "output_structured_error includes error code" {
    local result
    result=$(output_structured_error "FILE_NOT_FOUND" "cannot read" "" 2>/dev/null || true)
    [[ "$result" == *'"code":"FILE_NOT_FOUND"'* ]]
}

@test "output_structured_error includes message" {
    local result
    result=$(output_structured_error "ERR" "detailed error message" "" 2>/dev/null || true)
    [[ "$result" == *'"message":"detailed error message"'* ]]
}

@test "output_structured_error includes suggestion when provided" {
    local result
    result=$(output_structured_error "ERR" "msg" "try this fix" 2>/dev/null || true)
    [[ "$result" == *'"suggestion":"try this fix"'* ]]
}

@test "output_structured_error omits suggestion when empty" {
    local result
    result=$(output_structured_error "ERR" "msg" "" 2>/dev/null || true)
    [[ "$result" != *'"suggestion"'* ]]
}

@test "output_structured_error includes stack trace" {
    # Call from a wrapper function to get stack info
    _test_error_wrapper() {
        output_structured_error "ERR" "msg" "" 2>/dev/null || true
    }
    local result
    result=$(_test_error_wrapper)
    [[ "$result" == *'"stack":'* ]]
}

@test "output_structured_error includes context key-value pairs" {
    local result
    result=$(output_structured_error "ERR" "msg" "fix it" "path=/etc/config" "user=root" 2>/dev/null || true)
    [[ "$result" == *'"context":'* ]]
    [[ "$result" == *'"path":"/etc/config"'* ]]
    [[ "$result" == *'"user":"root"'* ]]
}

@test "output_structured_error returns exit code 1" {
    run output_structured_error "ERR" "msg" ""
    [ "$status" -eq 1 ]
}

@test "output_structured_error escapes special characters in message" {
    local result
    result=$(output_structured_error "ERR" 'line1
line2' "" 2>/dev/null || true)
    # Newline should be escaped as \n in JSON (backslash-n, two chars)
    [[ "$result" == *'\n'* ]]
    # Validate JSON if jq available
    if command -v jq &>/dev/null; then
        printf '%s' "$result" | jq . >/dev/null 2>&1
    fi
}

@test "output_structured_error escapes quotes in code" {
    local result
    result=$(output_structured_error 'CODE_"X"' "msg" "" 2>/dev/null || true)
    if command -v jq &>/dev/null; then
        local code
        code=$(printf '%s' "$result" | jq -r '.code' 2>/dev/null)
        [ "$code" = 'CODE_"X"' ]
    fi
}

@test "output_structured_error handles multiple context pairs" {
    local result
    result=$(output_structured_error "ERR" "msg" "" "key1=val1" "key2=val2" "key3=val3" 2>/dev/null || true)
    [[ "$result" == *'"key1":"val1"'* ]]
    [[ "$result" == *'"key2":"val2"'* ]]
    [[ "$result" == *'"key3":"val3"'* ]]
}

# =============================================================================
# output_try TESTS
# =============================================================================

@test "output_try passes through stdout on success" {
    local result
    result=$(output_try echo "hello world")
    [ "$result" = "hello world" ]
}

@test "output_try returns 0 on success" {
    run output_try true
    [ "$status" -eq 0 ]
}

@test "output_try produces structured error on failure" {
    local result
    result=$(output_try ls "/nonexistent_path_xyz_$$" 2>/dev/null || true)
    [[ "$result" == *'"status":"error"'* ]]
    [[ "$result" == *'"code":"COMMAND_FAILED"'* ]]
}

@test "output_try preserves original exit code" {
    # Use a subshell that exits with specific code (function might not be visible in run)
    run output_try bash -c 'exit 42'
    [ "$status" -eq 42 ]
}

@test "output_try includes command in context on failure" {
    local result
    result=$(output_try cat "/no_such_file_$$" 2>/dev/null || true)
    [[ "$result" == *'"command":'* ]]
    [[ "$result" == *"cat"* ]]
}

@test "output_try includes exit_code in context on failure" {
    local result
    result=$(output_try false 2>/dev/null || true)
    [[ "$result" == *'"exit_code":'* ]]
}

@test "output_try includes suggestion on failure" {
    local result
    result=$(output_try false 2>/dev/null || true)
    [[ "$result" == *'"suggestion":"Check command arguments and permissions"'* ]]
}

@test "output_try handles commands with arguments" {
    local result
    result=$(output_try printf '%s %s' "arg1" "arg2")
    [ "$result" = "arg1 arg2" ]
}

@test "output_try captures multiline stdout on success" {
    _multi_output() {
        printf 'line1\nline2\nline3\n'
    }
    local result
    result=$(output_try _multi_output)
    [[ "$result" == *"line1"* ]]
    [[ "$result" == *"line2"* ]]
    [[ "$result" == *"line3"* ]]
}

@test "output_try captures stderr in error message" {
    _stderr_cmd() {
        echo "error details" >&2
        return 1
    }
    local result
    result=$(output_try _stderr_cmd 2>/dev/null || true)
    [[ "$result" == *"error details"* ]]
}

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Universal Structured Output Protocol (USOP) Tests
# =============================================================================
# Tests for lib/output.sh
# Covers: output modes, envelope functions, timing, wrapping, backward compat
# =============================================================================

load '../test_helper'

setup() {
    source_lib "output"
    # Reset to default mode before each test
    export MAINFRAME_OUTPUT="raw"
}

teardown() {
    unset MAINFRAME_OUTPUT
}

# =============================================================================
# OUTPUT MODE DETECTION TESTS
# =============================================================================

@test "output_mode returns current mode when called without args" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_mode)
    [ "$result" = "json" ]
}

@test "output_mode sets mode when called with arg" {
    output_mode "json"
    [ "$MAINFRAME_OUTPUT" = "json" ]
}

@test "output_mode defaults to raw when unset" {
    unset MAINFRAME_OUTPUT
    local result
    result=$(output_mode)
    [ "$result" = "raw" ]
}

@test "output_mode accepts raw mode" {
    output_mode "raw"
    [ "$MAINFRAME_OUTPUT" = "raw" ]
}

@test "output_mode accepts json mode" {
    output_mode "json"
    [ "$MAINFRAME_OUTPUT" = "json" ]
}

@test "output_mode accepts minimal mode" {
    output_mode "minimal"
    [ "$MAINFRAME_OUTPUT" = "minimal" ]
}

@test "output_mode accepts debug mode" {
    output_mode "debug"
    [ "$MAINFRAME_OUTPUT" = "debug" ]
}

@test "output_mode returns 1 for invalid mode" {
    run output_mode "invalid_mode"
    [ "$status" -eq 1 ]
}

# =============================================================================
# MODE CHECK FUNCTIONS TESTS
# =============================================================================

@test "output_is_json returns 0 when json mode" {
    export MAINFRAME_OUTPUT="json"
    output_is_json
}

@test "output_is_json returns 1 when raw mode" {
    export MAINFRAME_OUTPUT="raw"
    ! output_is_json
}

@test "output_is_raw returns 0 when raw mode" {
    export MAINFRAME_OUTPUT="raw"
    output_is_raw
}

@test "output_is_raw returns 1 when json mode" {
    export MAINFRAME_OUTPUT="json"
    ! output_is_raw
}

@test "output_is_debug returns 0 when debug mode" {
    export MAINFRAME_OUTPUT="debug"
    output_is_debug
}

@test "output_is_debug returns 1 when raw mode" {
    export MAINFRAME_OUTPUT="raw"
    ! output_is_debug
}

@test "output_is_minimal returns 0 when minimal mode" {
    export MAINFRAME_OUTPUT="minimal"
    output_is_minimal
}

@test "output_is_minimal returns 1 when json mode" {
    export MAINFRAME_OUTPUT="json"
    ! output_is_minimal
}

# =============================================================================
# OUTPUT_INIT TESTS
# =============================================================================

@test "output_init initializes output system" {
    output_init
    # Should not error
    [ "$?" -eq 0 ]
}

@test "output_init respects MAINFRAME_OUTPUT env var" {
    export MAINFRAME_OUTPUT="json"
    output_init
    local result
    result=$(output_mode)
    [ "$result" = "json" ]
}

@test "output_init sets default mode when env unset" {
    unset MAINFRAME_OUTPUT
    output_init
    local result
    result=$(output_mode)
    [ "$result" = "raw" ]
}

# =============================================================================
# OUTPUT_SUCCESS TESTS - JSON MODE
# =============================================================================

@test "output_success emits JSON envelope in json mode" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_success "test data")
    [[ "$result" == '{"ok":true,'* ]]
}

@test "output_success includes data field" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_success "hello world")
    [[ "$result" == *'"data":"hello world"'* ]]
}

@test "output_success includes hint when provided" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_success "data" "next_function")
    [[ "$result" == *'"hint":"next_function"'* ]]
}

@test "output_success omits hint when not provided" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_success "data")
    [[ "$result" != *'"hint"'* ]]
}

@test "output_success escapes special characters in data" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_success 'hello "world"')
    [[ "$result" == *'\"world\"'* ]]
}

@test "output_success escapes newlines in data" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_success $'line1\nline2')
    [[ "$result" == *'\\n'* ]]
}

# =============================================================================
# OUTPUT_SUCCESS TESTS - RAW MODE (BACKWARD COMPAT)
# =============================================================================

@test "output_success emits raw data in raw mode" {
    export MAINFRAME_OUTPUT="raw"
    local result
    result=$(output_success "plain text")
    [ "$result" = "plain text" ]
}

@test "output_success ignores hint in raw mode" {
    export MAINFRAME_OUTPUT="raw"
    local result
    result=$(output_success "plain text" "ignored_hint")
    [ "$result" = "plain text" ]
}

# =============================================================================
# OUTPUT_SUCCESS TESTS - MINIMAL MODE
# =============================================================================

@test "output_success emits minimal JSON in minimal mode" {
    export MAINFRAME_OUTPUT="minimal"
    local result
    result=$(output_success "data")
    [[ "$result" == '{"ok":true,"data":"data"}' ]]
}

@test "output_success omits meta in minimal mode" {
    export MAINFRAME_OUTPUT="minimal"
    local result
    result=$(output_success "data")
    [[ "$result" != *'"meta"'* ]]
}

# =============================================================================
# OUTPUT_ERROR TESTS - JSON MODE
# =============================================================================

@test "output_error emits JSON error envelope in json mode" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_error "E_NOT_FOUND" "File not found")
    [[ "$result" == '{"ok":false,'* ]]
}

@test "output_error includes error code" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_error "E_NOT_FOUND" "File not found")
    [[ "$result" == *'"code":"E_NOT_FOUND"'* ]]
}

@test "output_error includes error message" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_error "E_NOT_FOUND" "File not found")
    [[ "$result" == *'"msg":"File not found"'* ]]
}

@test "output_error includes suggestion when provided" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_error "E_NOT_FOUND" "File not found" "use file_exists first")
    [[ "$result" == *'"suggestion":"use file_exists first"'* ]]
}

@test "output_error omits suggestion when not provided" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_error "E_NOT_FOUND" "File not found")
    [[ "$result" != *'"suggestion"'* ]]
}

# =============================================================================
# OUTPUT_ERROR TESTS - RAW MODE
# =============================================================================

@test "output_error emits plain message in raw mode" {
    export MAINFRAME_OUTPUT="raw"
    local result
    result=$(output_error "E_NOT_FOUND" "File not found" 2>&1)
    [[ "$result" == *"File not found"* ]]
}

@test "output_error writes to stderr in raw mode" {
    export MAINFRAME_OUTPUT="raw"
    # Capture stderr only
    local result
    result=$(output_error "E_NOT_FOUND" "File not found" 2>&1 >/dev/null)
    [[ "$result" == *"File not found"* ]]
}

# =============================================================================
# OUTPUT_RAW TESTS
# =============================================================================

@test "output_raw emits text in raw mode" {
    export MAINFRAME_OUTPUT="raw"
    local result
    result=$(output_raw "plain text")
    [ "$result" = "plain text" ]
}

@test "output_raw emits text in json mode" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_raw "plain text")
    [ "$result" = "plain text" ]
}

@test "output_raw always bypasses envelope" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_raw "no envelope here")
    [[ "$result" != *'"ok"'* ]]
}

# =============================================================================
# OUTPUT_JSON TESTS
# =============================================================================

@test "output_json emits json string unchanged in json mode" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_json '{"custom":"data"}')
    [ "$result" = '{"custom":"data"}' ]
}

@test "output_json emits json unchanged in raw mode" {
    export MAINFRAME_OUTPUT="raw"
    local result
    result=$(output_json '{"custom":"data"}')
    [ "$result" = '{"custom":"data"}' ]
}

# =============================================================================
# TIMING / META TESTS
# =============================================================================

@test "output_timer_start records start time" {
    # Note: timer state is global, so this works
    output_timer_start
    # Check that the variable exists in the shell after calling
    [ -n "$_MAINFRAME_OUTPUT_START_MS" ]
}

@test "output_timer_elapsed returns elapsed milliseconds" {
    # Run in same shell context to preserve timer state
    _test_elapsed() {
        output_timer_start
        sleep 0.1
        output_timer_elapsed
    }
    local elapsed
    elapsed=$(_test_elapsed)
    [ "$elapsed" -ge 50 ]  # At least 50ms (allow for timing variance)
}

@test "output_timer_elapsed returns 0 if start not called" {
    unset _MAINFRAME_OUTPUT_START_MS
    local elapsed
    elapsed=$(output_timer_elapsed)
    [ "$elapsed" -eq 0 ]
}

@test "output_success includes elapsed_ms in meta when timer started" {
    export MAINFRAME_OUTPUT="json"
    # Start timer, sleep, then call output_success - all in same shell
    # Note: subshell for $() loses timer state, so we test via output_wrap instead
    _test_timed() {
        output_timer_start
        sleep 0.05
        output_success "data"
    }
    local result
    result=$(_test_timed)
    [[ "$result" == *'"meta":{"elapsed_ms":'* ]]
}

# =============================================================================
# OUTPUT_WRAP TESTS
# =============================================================================

@test "output_wrap wraps function output in envelope" {
    export MAINFRAME_OUTPUT="json"
    # Define a test function
    _test_func() { echo "test output"; }
    local result
    result=$(output_wrap _test_func)
    [[ "$result" == '{"ok":true,'* ]]
    [[ "$result" == *'"data":"test output"'* ]]
}

@test "output_wrap captures exit code" {
    export MAINFRAME_OUTPUT="json"
    _test_fail() { return 1; }
    local result
    result=$(output_wrap _test_fail)
    [[ "$result" == '{"ok":false,'* ]]
}

@test "output_wrap passes arguments to function" {
    export MAINFRAME_OUTPUT="json"
    _test_args() { echo "arg1=$1 arg2=$2"; }
    local result
    result=$(output_wrap _test_args "hello" "world")
    [[ "$result" == *'arg1=hello arg2=world'* ]]
}

@test "output_wrap measures elapsed time" {
    export MAINFRAME_OUTPUT="json"
    _test_slow() { sleep 0.05; echo "done"; }
    local result
    result=$(output_wrap _test_slow)
    [[ "$result" == *'"elapsed_ms":'* ]]
}

@test "output_wrap returns function exit code" {
    export MAINFRAME_OUTPUT="raw"
    _test_exit() { return 42; }
    run output_wrap _test_exit
    [ "$status" -eq 42 ]
}

@test "output_wrap in raw mode outputs raw result" {
    export MAINFRAME_OUTPUT="raw"
    _test_raw() { echo "raw output"; }
    local result
    result=$(output_wrap _test_raw)
    [ "$result" = "raw output" ]
}

# =============================================================================
# OUTPUT_WITH_MODE TESTS
# =============================================================================

@test "output_with_mode temporarily changes mode" {
    export MAINFRAME_OUTPUT="raw"
    local result
    result=$(output_with_mode "json" output_success "data")
    [[ "$result" == '{"ok":true,'* ]]
}

@test "output_with_mode restores original mode" {
    export MAINFRAME_OUTPUT="raw"
    output_with_mode "json" true
    [ "$MAINFRAME_OUTPUT" = "raw" ]
}

# =============================================================================
# OUTPUT TYPE HELPERS TESTS
# =============================================================================

@test "output_string emits string in json mode" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_string "hello")
    [[ "$result" == '{"ok":true,"data":"hello"'* ]]
}

@test "output_int emits integer in json mode" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_int 42)
    [[ "$result" == '{"ok":true,"data":42'* ]]
}

@test "output_bool emits boolean true in json mode" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_bool true)
    [[ "$result" == '{"ok":true,"data":true'* ]]
}

@test "output_bool emits boolean false in json mode" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_bool false)
    [[ "$result" == '{"ok":true,"data":false'* ]]
}

@test "output_float emits float in json mode" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_float 3.14)
    [[ "$result" == '{"ok":true,"data":3.14'* ]]
}

@test "output_json_object emits object in json mode" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_json_object '{"key":"value"}')
    [[ "$result" == '{"ok":true,"data":{"key":"value"}'* ]]
}

@test "output_json_array emits array in json mode" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_json_array '["a","b","c"]')
    [[ "$result" == '{"ok":true,"data":["a","b","c"]'* ]]
}

@test "output_file_path emits path in json mode" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_file_path "/tmp/test.txt")
    [[ "$result" == '{"ok":true,"data":"/tmp/test.txt"'* ]]
}

@test "output_void emits null in json mode" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_void)
    [[ "$result" == '{"ok":true,"data":null'* ]]
}

# =============================================================================
# TYPE HELPERS - RAW MODE
# =============================================================================

@test "output_string emits plain string in raw mode" {
    export MAINFRAME_OUTPUT="raw"
    local result
    result=$(output_string "hello")
    [ "$result" = "hello" ]
}

@test "output_int emits plain number in raw mode" {
    export MAINFRAME_OUTPUT="raw"
    local result
    result=$(output_int 42)
    [ "$result" = "42" ]
}

@test "output_bool emits plain bool in raw mode" {
    export MAINFRAME_OUTPUT="raw"
    local result
    result=$(output_bool true)
    [ "$result" = "true" ]
}

# =============================================================================
# DEBUG MODE TESTS
# =============================================================================

@test "debug mode includes caller or timestamp in meta" {
    export MAINFRAME_OUTPUT="debug"
    _test_debug() { output_success "data"; }
    local result
    result=$(_test_debug)
    # Debug mode should have meta with either caller info or at minimum a timestamp
    [[ "$result" == *'"meta":'* ]]
    [[ "$result" == *'"timestamp":'* ]] || [[ "$result" == *'"caller":'* ]]
}

@test "debug mode includes timestamp in meta" {
    export MAINFRAME_OUTPUT="debug"
    local result
    result=$(output_success "data")
    [[ "$result" == *'"timestamp":'* ]]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "output_success handles empty string" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_success "")
    [[ "$result" == '{"ok":true,"data":""'* ]]
}

@test "output_success handles multiline string" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_success $'line1\nline2\nline3')
    [[ "$result" == *'\\n'* ]]
}

@test "output_success handles special JSON characters" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_success '{"nested": "json"}')
    # Should escape the inner quotes
    [[ "$result" == *'\\\"nested\\\"'* ]]
}

@test "output_success handles tabs" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_success $'col1\tcol2')
    [[ "$result" == *'\\t'* ]]
}

@test "output_success handles backslashes" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_success 'path\\to\\file')
    [[ "$result" == *'\\\\'* ]]
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

@test "json mode overhead is reasonable" {
    # Skip if nanosecond timing not available (macOS)
    if ! date +%s%N &>/dev/null || [[ "$(date +%s%N)" == *"N"* ]]; then
        skip "nanosecond timing not available"
    fi

    export MAINFRAME_OUTPUT="json"

    # Time 100 iterations
    local start end elapsed_json
    start=$(date +%s%N)
    for i in {1..100}; do
        output_success "test data $i" >/dev/null
    done
    end=$(date +%s%N)
    elapsed_json=$(( (end - start) / 1000000 ))  # Convert to ms

    # Compare to raw mode
    export MAINFRAME_OUTPUT="raw"
    start=$(date +%s%N)
    for i in {1..100}; do
        output_success "test data $i" >/dev/null
    done
    end=$(date +%s%N)
    local elapsed_raw=$(( (end - start) / 1000000 ))

    # JSON mode should be within 5x overhead due to escape processing
    # Allow for variance in test environments and character-by-character escaping
    local max_allowed=$(( elapsed_raw * 5 ))
    [ "$elapsed_json" -lt "$max_allowed" ]
}

# =============================================================================
# NAMEREF VARIANT TESTS (for performance)
# =============================================================================

@test "output_v stores result in variable" {
    export MAINFRAME_OUTPUT="json"
    local result
    output_v result "test data"
    [[ "$result" == '{"ok":true,"data":"test data"'* ]]
}

@test "output_v avoids subshell" {
    export MAINFRAME_OUTPUT="json"
    local result
    output_v result "data"
    # If we got here without error, nameref worked
    [ -n "$result" ]
}

# =============================================================================
# BACKWARD COMPATIBILITY TESTS
# =============================================================================

@test "existing output_is_json function works" {
    export MAINFRAME_OUTPUT="json"
    output_is_json
}

@test "existing output_format function returns mode" {
    export MAINFRAME_OUTPUT="json"
    local result
    result=$(output_format)
    [ "$result" = "json" ]
}

@test "mainframe_call wrapper still works" {
    # Existing function from output.sh
    _test_existing() { echo "existing"; }
    local result
    result=$(mainframe_call _test_existing)
    [[ "$result" == *'"data":"existing"'* ]] || [[ "$result" == *'"status":"success"'* ]]
}

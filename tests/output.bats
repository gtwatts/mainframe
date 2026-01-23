#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Universal Structured Output Protocol (USOP) Tests
# =============================================================================

load 'test_helper'

setup() {
    source_lib "output"
    # Reset state between tests
    MAINFRAME_OUTPUT="raw"
    MAINFRAME_OUTPUT_HINT=""
    unset _MAINFRAME_TIMER__default 2>/dev/null || true
}

# =============================================================================
# CONFIGURATION TESTS
# =============================================================================

@test "MAINFRAME_OUTPUT defaults to raw" {
    # After setup sources output.sh, MAINFRAME_OUTPUT is set to raw
    [ "$MAINFRAME_OUTPUT" = "raw" ]
}

@test "double-source guard prevents reloading" {
    [ "$_MAINFRAME_OUTPUT_LOADED" = "1" ]
}

# =============================================================================
# RAW MODE TESTS
# =============================================================================

@test "output in raw mode prints plain text" {
    MAINFRAME_OUTPUT=raw
    local result
    result=$(output "hello world")
    [ "$result" = "hello world" ]
}

@test "output -n suppresses newline in raw mode" {
    MAINFRAME_OUTPUT=raw
    local result
    result=$(output -n "hello")
    [ "$result" = "hello" ]
}

@test "output -t void produces no output in raw mode" {
    MAINFRAME_OUTPUT=raw
    local result
    result=$(output -t void "")
    [ -z "$result" ]
}

@test "output in raw mode with int type just prints value" {
    MAINFRAME_OUTPUT=raw
    local result
    result=$(output -t int "42")
    [ "$result" = "42" ]
}

@test "output in raw mode has near-zero overhead" {
    MAINFRAME_OUTPUT=raw
    # Just verify it does not crash or add JSON wrapping
    local result
    result=$(output -t bool "true")
    [ "$result" = "true" ]
}

# =============================================================================
# MINIMAL MODE TESTS
# =============================================================================

@test "output in minimal mode prints value" {
    MAINFRAME_OUTPUT=minimal
    local result
    result=$(output "test value")
    [ "$result" = "test value" ]
}

@test "output in minimal mode - void produces nothing" {
    MAINFRAME_OUTPUT=minimal
    local result
    result=$(output -t void "")
    [ -z "$result" ]
}

# =============================================================================
# JSON MODE TESTS
# =============================================================================

@test "output in json mode produces envelope" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output "hello")
    assert_contains "$result" '"ok":true'
    assert_contains "$result" '"data":"hello"'
    assert_contains "$result" '"elapsed_ms"'
}

@test "output json mode wraps string type" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -t string "hello world")
    assert_contains "$result" '"data":"hello world"'
}

@test "output json mode wraps int type" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -t int "42")
    assert_contains "$result" '"data":42'
}

@test "output json mode wraps float type" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -t float "3.14")
    assert_contains "$result" '"data":3.14'
}

@test "output json mode wraps bool type" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -t bool "true")
    assert_contains "$result" '"data":true'
}

@test "output json mode wraps bool false" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -t bool "false")
    assert_contains "$result" '"data":false'
}

@test "output json mode wraps json_object type" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -t json_object '{"name":"John"}')
    assert_contains "$result" '"data":{"name":"John"}'
}

@test "output json mode wraps json_array type" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -t json_array '["a","b","c"]')
    assert_contains "$result" '"data":["a","b","c"]'
}

@test "output json mode wraps void as null" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -t void "")
    assert_contains "$result" '"data":null'
}

@test "output json mode includes hint when set" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -h "next_func" "value")
    assert_contains "$result" '"hint":"next_func"'
}

@test "output json mode - hint is consumed (reset after output)" {
    MAINFRAME_OUTPUT=json
    output -h "myhint" "value" >/dev/null
    [ -z "$MAINFRAME_OUTPUT_HINT" ]
}

@test "output json mode file_path type includes exists flag" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -t file_path "/tmp")
    assert_contains "$result" '"path":"/tmp"'
    assert_contains "$result" '"exists":true'
}

@test "output json mode file_path for nonexistent path" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -t file_path "/nonexistent_path_xyz_12345")
    assert_contains "$result" '"exists":false'
}

@test "output json mode stream type" {
    MAINFRAME_OUTPUT=json
    local multiline
    multiline=$(printf 'line1\nline2\nline3')
    local result
    result=$(output -t stream "$multiline")
    assert_contains "$result" '"line1"'
    assert_contains "$result" '"line2"'
    assert_contains "$result" '"line3"'
}

@test "output json mode escapes special characters" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output "hello \"world\"")
    assert_contains "$result" 'hello \"world\"'
}

# =============================================================================
# DEBUG MODE TESTS
# =============================================================================

@test "output in debug mode prints value to stdout" {
    MAINFRAME_OUTPUT=debug
    local result
    result=$(output "debug value" 2>/dev/null)
    [ "$result" = "debug value" ]
}

@test "output in debug mode prints metadata to stderr" {
    MAINFRAME_OUTPUT=debug
    local stderr_out
    stderr_out=$(output "test" 2>&1 >/dev/null)
    assert_contains "$stderr_out" "[DEBUG]"
    assert_contains "$stderr_out" "type=string"
}

@test "output in debug mode void prints (void) to stderr" {
    MAINFRAME_OUTPUT=debug
    local stderr_out
    stderr_out=$(output -t void "" 2>&1 >/dev/null)
    assert_contains "$stderr_out" "(void)"
}

# =============================================================================
# TIMER TESTS
# =============================================================================

@test "output_timer_start creates timer variable" {
    output_timer_start "test_timer"
    local varname="_MAINFRAME_TIMER_test_timer"
    [ -n "${!varname}" ]
}

@test "output_timer_elapsed returns a number" {
    output_timer_start "elapsed_test"
    local ms
    ms=$(output_timer_elapsed "elapsed_test")
    [[ "$ms" =~ ^[0-9]+$ ]]
}

@test "output_timer_elapsed returns 0 for missing timer" {
    local ms
    ms=$(output_timer_elapsed "nonexistent_timer_xyz") || true
    [ "$ms" = "0" ]
}

@test "output_timer_elapsed returns non-negative" {
    output_timer_start "nonneg_test"
    sleep 0.01
    local ms
    ms=$(output_timer_elapsed "nonneg_test")
    [ "$ms" -ge 0 ]
}

@test "output_timer_start default timer name" {
    output_timer_start
    local varname="_MAINFRAME_TIMER__default"
    [ -n "${!varname}" ]
}

@test "output_timer_elapsed default timer name" {
    output_timer_start
    local ms
    ms=$(output_timer_elapsed)
    [[ "$ms" =~ ^[0-9]+$ ]]
}

@test "multiple named timers are independent" {
    output_timer_start "timer_a"
    sleep 0.02
    output_timer_start "timer_b"
    sleep 0.02
    local ms_a ms_b
    ms_a=$(output_timer_elapsed "timer_a")
    ms_b=$(output_timer_elapsed "timer_b")
    # timer_a should have more elapsed time than timer_b
    [ "$ms_a" -ge "$ms_b" ]
}

@test "json output includes elapsed_ms from timer" {
    MAINFRAME_OUTPUT=json
    output_timer_start
    sleep 0.01
    local result
    result=$(output "timed")
    assert_contains "$result" '"elapsed_ms":'
}

# =============================================================================
# ERROR OUTPUT TESTS
# =============================================================================

@test "output_error in raw mode prints to stderr" {
    MAINFRAME_OUTPUT=raw
    local stderr_out
    stderr_out=$(output_error "E_TEST" "test error" 2>&1) || true
    assert_contains "$stderr_out" "E_TEST"
    assert_contains "$stderr_out" "test error"
}

@test "output_error in raw mode includes suggestion" {
    MAINFRAME_OUTPUT=raw
    local stderr_out
    stderr_out=$(output_error -s "try again" "E_FAIL" "it failed" 2>&1) || true
    assert_contains "$stderr_out" "try again"
}

@test "output_error in minimal mode prints terse error" {
    MAINFRAME_OUTPUT=minimal
    local stderr_out
    stderr_out=$(output_error "E_CODE" "msg" 2>&1) || true
    assert_contains "$stderr_out" "E_CODE: msg"
}

@test "output_error in json mode produces error envelope" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output_error "E_NOT_FOUND" "File missing" 2>/dev/null) || true
    assert_contains "$result" '"ok":false'
    assert_contains "$result" '"code":"E_NOT_FOUND"'
    assert_contains "$result" '"msg":"File missing"'
}

@test "output_error json mode includes suggestion" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output_error -s "check path" "E_NOT_FOUND" "missing" 2>/dev/null) || true
    assert_contains "$result" '"suggestion":"check path"'
}

@test "output_error json mode includes context" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output_error -c '{"path":"/tmp/foo"}' "E_NOT_FOUND" "missing" 2>/dev/null) || true
    assert_contains "$result" '"context":{"path":"/tmp/foo"}'
}

@test "output_error returns exit code 1" {
    MAINFRAME_OUTPUT=raw
    ! output_error "E_TEST" "error" 2>/dev/null
}

@test "output_error in debug mode prints verbose info" {
    MAINFRAME_OUTPUT=debug
    local stderr_out
    stderr_out=$(output_error "E_DBG" "debug error" 2>&1 >/dev/null) || true
    assert_contains "$stderr_out" "[ERROR]"
    assert_contains "$stderr_out" "code=E_DBG"
    assert_contains "$stderr_out" "message: debug error"
}

# =============================================================================
# TYPE FORMAT TESTS
# =============================================================================

@test "int type validates integer" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -t int "not_a_number")
    assert_contains "$result" '"data":null'
}

@test "int type accepts negative integers" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -t int "-42")
    assert_contains "$result" '"data":-42'
}

@test "float type validates number" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -t float "not_float")
    assert_contains "$result" '"data":null'
}

@test "float type accepts scientific notation" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -t float "1.5e10")
    assert_contains "$result" '"data":1.5e10'
}

@test "bool type normalizes yes/on to true" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -t bool "yes")
    assert_contains "$result" '"data":true'
}

@test "bool type normalizes no/off to false" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -t bool "off")
    assert_contains "$result" '"data":false'
}

@test "bool type returns null for invalid" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -t bool "maybe")
    assert_contains "$result" '"data":null'
}

@test "unknown type treated as string" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output -t custom_type "value")
    assert_contains "$result" '"data":"value"'
}

# =============================================================================
# CONVENIENCE WRAPPER TESTS
# =============================================================================

@test "output_string delegates to output" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output_string "test")
    assert_contains "$result" '"data":"test"'
}

@test "output_int delegates to output" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output_int "99")
    assert_contains "$result" '"data":99'
}

@test "output_bool delegates to output" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output_bool "true")
    assert_contains "$result" '"data":true'
}

@test "output_float delegates to output" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output_float "2.718")
    assert_contains "$result" '"data":2.718'
}

@test "output_json_object passes through" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output_json_object '{"x":1}')
    assert_contains "$result" '"data":{"x":1}'
}

@test "output_json_array passes through" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output_json_array '[1,2,3]')
    assert_contains "$result" '"data":[1,2,3]'
}

@test "output_void produces null data" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output_void)
    assert_contains "$result" '"data":null'
}

@test "output_file_path checks existence" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output_file_path "/tmp")
    assert_contains "$result" '"exists":true'
}

# =============================================================================
# NAMEREF VARIANT TESTS
# =============================================================================

@test "output_v stores value in variable (raw mode)" {
    MAINFRAME_OUTPUT=raw
    local my_result
    output_v my_result "hello from nameref"
    [ "$my_result" = "hello from nameref" ]
}

@test "output_v stores JSON envelope (json mode)" {
    MAINFRAME_OUTPUT=json
    local my_result
    output_v my_result -t int "42"
    assert_contains "$my_result" '"ok":true'
    assert_contains "$my_result" '"data":42'
}

@test "output_v handles void type" {
    MAINFRAME_OUTPUT=raw
    local my_result="placeholder"
    output_v my_result -t void ""
    [ -z "$my_result" ]
}

@test "output_v includes hint in json mode" {
    MAINFRAME_OUTPUT=json
    local my_result
    output_v my_result -h "next_step" "value"
    assert_contains "$my_result" '"hint":"next_step"'
}

# =============================================================================
# MODE UTILITY TESTS
# =============================================================================

@test "output_is_json returns true in json mode" {
    MAINFRAME_OUTPUT=json
    output_is_json
}

@test "output_is_json returns false in raw mode" {
    MAINFRAME_OUTPUT=raw
    ! output_is_json
}

@test "output_is_raw returns true in raw mode" {
    MAINFRAME_OUTPUT=raw
    output_is_raw
}

@test "output_is_debug returns true in debug mode" {
    MAINFRAME_OUTPUT=debug
    output_is_debug
}

@test "output_is_minimal returns true in minimal mode" {
    MAINFRAME_OUTPUT=minimal
    output_is_minimal
}

@test "output_with_mode temporarily changes mode" {
    MAINFRAME_OUTPUT=raw
    local result
    result=$(output_with_mode json output "switched")
    assert_contains "$result" '"ok":true'
    # Mode should be restored
    [ "$MAINFRAME_OUTPUT" = "raw" ]
}

@test "output_with_mode restores mode after failure" {
    MAINFRAME_OUTPUT=raw
    fail_func() { return 1; }
    output_with_mode json fail_func || true
    [ "$MAINFRAME_OUTPUT" = "raw" ]
}

@test "output_with_mode preserves exit code" {
    MAINFRAME_OUTPUT=raw
    exit42() { return 42; }
    local rc=0
    output_with_mode json exit42 || rc=$?
    [ "$rc" = "42" ]
}

# =============================================================================
# ESCAPE FUNCTION TESTS
# =============================================================================

@test "output escapes backslash in json mode" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output 'path\to\file')
    assert_contains "$result" 'path\\to\\file'
}

@test "output escapes double quote in json mode" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output 'say "hello"')
    assert_contains "$result" 'say \"hello\"'
}

@test "output escapes tab in json mode" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output $'col1\tcol2')
    assert_contains "$result" 'col1\tcol2'
}

# =============================================================================
# INTERNAL FUNCTION TESTS
# =============================================================================

@test "_output_json generates valid envelope" {
    local result
    result=$(_output_json '"test"' 5 "hint1")
    assert_contains "$result" '"ok":true'
    assert_contains "$result" '"data":"test"'
    assert_contains "$result" '"elapsed_ms":5'
    assert_contains "$result" '"hint":"hint1"'
}

@test "_output_json without hint omits hint field" {
    MAINFRAME_OUTPUT_HINT=""
    local result
    result=$(_output_json '42' 0 "")
    # Should not contain hint key
    [[ "$result" != *'"hint"'* ]]
}

@test "_error_json generates valid error envelope" {
    local result
    result=$(_error_json "E_FAIL" "broke" "fix it" 10 '{"key":"val"}')
    assert_contains "$result" '"ok":false'
    assert_contains "$result" '"code":"E_FAIL"'
    assert_contains "$result" '"msg":"broke"'
    assert_contains "$result" '"suggestion":"fix it"'
    assert_contains "$result" '"elapsed_ms":10'
    assert_contains "$result" '"context":{"key":"val"}'
}

@test "_error_json without suggestion omits field" {
    local result
    result=$(_error_json "E_X" "msg" "" 0 "")
    [[ "$result" != *'"suggestion"'* ]]
}

@test "_error_json without context omits field" {
    local result
    result=$(_error_json "E_X" "msg" "sug" 0 "")
    [[ "$result" != *'"context"'* ]]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "output handles empty string value" {
    MAINFRAME_OUTPUT=json
    local result
    result=$(output "")
    assert_contains "$result" '"data":""'
}

@test "output handles value starting with dash" {
    MAINFRAME_OUTPUT=raw
    local result
    result=$(output -- "-dangerous")
    [ "$result" = "-dangerous" ]
}

@test "unknown MAINFRAME_OUTPUT mode falls back gracefully" {
    MAINFRAME_OUTPUT=invalid_mode
    local result
    result=$(output "fallback test")
    [ "$result" = "fallback test" ]
}

@test "output_error with unknown mode still prints error" {
    MAINFRAME_OUTPUT=invalid_mode
    local stderr_out
    stderr_out=$(output_error "E_X" "unknown mode error" 2>&1) || true
    assert_contains "$stderr_out" "E_X"
}

@test "timer name with special chars gets sanitized" {
    output_timer_start "my-timer.1"
    local ms
    ms=$(output_timer_elapsed "my-timer.1")
    [[ "$ms" =~ ^[0-9]+$ ]]
}

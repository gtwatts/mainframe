#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Contract Module Tests
# =============================================================================

load 'test_helper'

setup() {
    source_lib "contract"
    export MAINFRAME_CONTRACTS_ENABLED=1
    export MAINFRAME_ERROR_JSON=1
    TEST_DIR=$(create_test_dir "contract")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# mainframe_error TESTS
# =============================================================================

@test "mainframe_error emits JSON to stderr" {
    local err
    err=$(mainframe_error 42 "something broke" 2>&1) || true
    [[ "$err" == *'"error":true'* ]]
    [[ "$err" == *'"code":42'* ]]
    [[ "$err" == *'"msg":"something broke"'* ]]
}

@test "mainframe_error returns provided exit code" {
    local rc=0
    mainframe_error 7 "test" 2>/dev/null || rc=$?
    [ "$rc" = "7" ]
}

@test "mainframe_error includes context key=value pairs" {
    local err
    err=$(mainframe_error 1 "bad port" "port=99999" "range=1-65535" 2>&1) || true
    [[ "$err" == *'"context":'* ]]
    [[ "$err" == *'"port":"99999"'* ]]
    [[ "$err" == *'"range":"1-65535"'* ]]
}

@test "mainframe_error includes function name" {
    _helper_func() {
        mainframe_error 1 "test" 2>&1
    }
    local err
    err=$(_helper_func) || true
    [[ "$err" == *'"func":"_helper_func"'* ]]
}

@test "mainframe_error plain text mode" {
    export MAINFRAME_ERROR_JSON=0
    local err
    err=$(mainframe_error 1 "plain error" 2>&1) || true
    [[ "$err" == *"[contract]"* ]]
    [[ "$err" == *"plain error"* ]]
}

# =============================================================================
# contract_require TESTS
# =============================================================================

@test "contract_require passes on true condition" {
    contract_require "[[ 1 -eq 1 ]]" "math works"
}

@test "contract_require fails on false condition" {
    local err
    ! err=$(contract_require "[[ 1 -eq 2 ]]" "math broken" 2>&1)
}

@test "contract_require emits precondition type" {
    local err
    err=$(contract_require "[[ -f /nonexistent ]]" "missing file" 2>&1) || true
    [[ "$err" == *'"type":"precondition"'* ]]
}

@test "contract_require includes expression in error" {
    local err
    err=$(contract_require "[[ -d /nope ]]" "dir missing" 2>&1) || true
    [[ "$err" == *'"expr":'* ]]
}

@test "contract_require skips when disabled" {
    export MAINFRAME_CONTRACTS_ENABLED=0
    contract_require "[[ 1 -eq 2 ]]" "should not fire"
}

# =============================================================================
# contract_ensure TESTS
# =============================================================================

@test "contract_ensure passes on true condition" {
    contract_ensure "[[ -d /tmp ]]" "/tmp exists"
}

@test "contract_ensure fails on false condition" {
    ! contract_ensure "[[ -f /nonexistent_file ]]" "output missing" 2>/dev/null
}

@test "contract_ensure emits postcondition type" {
    local err
    err=$(contract_ensure "[[ 0 -eq 1 ]]" "bad result" 2>&1) || true
    [[ "$err" == *'"type":"postcondition"'* ]]
}

@test "contract_ensure skips when disabled" {
    export MAINFRAME_CONTRACTS_ENABLED=0
    contract_ensure "[[ 1 -eq 99 ]]" "should not fire"
}

# =============================================================================
# contract_invariant TESTS
# =============================================================================

@test "contract_invariant passes on true condition" {
    local count=5
    contract_invariant "[[ $count -ge 0 ]]" "count non-negative"
}

@test "contract_invariant fails on false condition" {
    ! contract_invariant "[[ 5 -lt 0 ]]" "impossible" 2>/dev/null
}

@test "contract_invariant emits invariant type" {
    local err
    err=$(contract_invariant "[[ 0 -gt 1 ]]" "violated" 2>&1) || true
    [[ "$err" == *'"type":"invariant"'* ]]
}

# =============================================================================
# contract_type_check TESTS
# =============================================================================

@test "contract_type_check validates int" {
    contract_type_check "42" "int" "port"
    contract_type_check "-10" "int" "offset"
}

@test "contract_type_check rejects non-int" {
    ! contract_type_check "abc" "int" "port" 2>/dev/null
    ! contract_type_check "3.14" "int" "port" 2>/dev/null
}

@test "contract_type_check validates float" {
    contract_type_check "3.14" "float" "rate"
    contract_type_check "42" "float" "whole"
    contract_type_check "-1.5" "float" "offset"
}

@test "contract_type_check rejects non-float" {
    ! contract_type_check "abc" "float" "rate" 2>/dev/null
}

@test "contract_type_check validates bool" {
    contract_type_check "true" "bool" "flag"
    contract_type_check "false" "bool" "flag"
    contract_type_check "1" "bool" "flag"
    contract_type_check "0" "bool" "flag"
    contract_type_check "yes" "bool" "flag"
    contract_type_check "no" "bool" "flag"
}

@test "contract_type_check rejects non-bool" {
    ! contract_type_check "maybe" "bool" "flag" 2>/dev/null
}

@test "contract_type_check validates nonempty" {
    contract_type_check "hello" "nonempty" "name"
}

@test "contract_type_check rejects empty for nonempty" {
    ! contract_type_check "" "nonempty" "name" 2>/dev/null
}

@test "contract_type_check validates file" {
    touch "$TEST_DIR/exists.txt"
    contract_type_check "$TEST_DIR/exists.txt" "file" "config"
}

@test "contract_type_check rejects missing file" {
    ! contract_type_check "/no/such/file" "file" "config" 2>/dev/null
}

@test "contract_type_check validates dir" {
    contract_type_check "$TEST_DIR" "dir" "output"
}

@test "contract_type_check rejects missing dir" {
    ! contract_type_check "/no/such/dir" "dir" "output" 2>/dev/null
}

@test "contract_type_check emits JSON error" {
    local err
    err=$(contract_type_check "abc" "int" "port" 2>&1) || true
    [[ "$err" == *'"type":"type_check"'* ]]
    [[ "$err" == *'"expected_type":"int"'* ]]
    [[ "$err" == *'"name":"port"'* ]]
}

# =============================================================================
# contract_not_empty TESTS
# =============================================================================

@test "contract_not_empty passes for non-empty args" {
    contract_not_empty "hello" "world"
}

@test "contract_not_empty fails on first empty arg" {
    ! contract_not_empty "hello" "" "world" 2>/dev/null
}

@test "contract_not_empty reports argument index" {
    local err
    err=$(contract_not_empty "a" "b" "" 2>&1) || true
    [[ "$err" == *'"arg_index":3'* ]]
}

@test "contract_not_empty passes with single arg" {
    contract_not_empty "value"
}

# =============================================================================
# contract_is_file TESTS
# =============================================================================

@test "contract_is_file passes for existing file" {
    touch "$TEST_DIR/test.txt"
    contract_is_file "$TEST_DIR/test.txt"
}

@test "contract_is_file fails for missing file" {
    ! contract_is_file "$TEST_DIR/nope.txt" 2>/dev/null
}

@test "contract_is_file emits path in error" {
    local err
    err=$(contract_is_file "/no/such/file" "config" 2>&1) || true
    [[ "$err" == *'"path":"/no/such/file"'* ]]
    [[ "$err" == *'"type":"file_check"'* ]]
}

# =============================================================================
# contract_is_dir TESTS
# =============================================================================

@test "contract_is_dir passes for existing dir" {
    contract_is_dir "$TEST_DIR"
}

@test "contract_is_dir fails for missing dir" {
    ! contract_is_dir "/no/such/dir" 2>/dev/null
}

@test "contract_is_dir emits path in error" {
    local err
    err=$(contract_is_dir "/no/such/dir" "output" 2>&1) || true
    [[ "$err" == *'"path":"/no/such/dir"'* ]]
    [[ "$err" == *'"type":"dir_check"'* ]]
}

# =============================================================================
# contract_in_range TESTS
# =============================================================================

@test "contract_in_range passes for value in range" {
    contract_in_range 8080 1 65535 "port"
}

@test "contract_in_range passes for boundary values" {
    contract_in_range 1 1 100 "val"
    contract_in_range 100 1 100 "val"
}

@test "contract_in_range fails for value below min" {
    ! contract_in_range 0 1 65535 "port" 2>/dev/null
}

@test "contract_in_range fails for value above max" {
    ! contract_in_range 70000 1 65535 "port" 2>/dev/null
}

@test "contract_in_range fails for non-integer" {
    ! contract_in_range "abc" 1 100 "val" 2>/dev/null
}

@test "contract_in_range emits range context" {
    local err
    err=$(contract_in_range 0 1 65535 "port" 2>&1) || true
    [[ "$err" == *'"min":1'* ]]
    [[ "$err" == *'"max":65535'* ]]
    [[ "$err" == *'"type":"range_check"'* ]]
}

# =============================================================================
# contracts_enable / contracts_disable TESTS
# =============================================================================

@test "contracts_disable suppresses all checks" {
    contracts_disable
    # These would all fail if enabled
    contract_require "[[ 1 -eq 2 ]]" "nope"
    contract_ensure "[[ 0 -gt 1 ]]" "nope"
    contract_invariant "[[ -1 -gt 0 ]]" "nope"
    contract_type_check "" "nonempty" "val"
    contract_not_empty ""
    contract_is_file "/nonexistent"
    contract_is_dir "/nonexistent"
    contract_in_range 0 1 10 "val"
}

@test "contracts_enable re-enables checks" {
    contracts_disable
    contract_require "[[ 1 -eq 2 ]]" "disabled"
    contracts_enable
    ! contract_require "[[ 1 -eq 2 ]]" "enabled" 2>/dev/null
}

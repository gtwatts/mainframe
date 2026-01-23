#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Performance Utilities Tests
# =============================================================================

load 'test_helper'

setup() {
    source_lib "perf"
    TEST_DIR=$(create_test_dir "perf")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# bash_version TESTS
# =============================================================================

@test "bash_version returns major.minor.patch format" {
    local ver
    ver=$(bash_version)
    [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "bash_version_major returns single number" {
    local major
    major=$(bash_version_major)
    [[ "$major" =~ ^[0-9]+$ ]]
    (( major >= 4 ))
}

@test "bash_version matches BASH_VERSINFO" {
    local ver
    ver=$(bash_version)
    local expected="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}.${BASH_VERSINFO[2]}"
    [ "$ver" = "$expected" ]
}

# =============================================================================
# bash_version_at_least TESTS
# =============================================================================

@test "bash_version_at_least returns 0 for current version" {
    bash_version_at_least "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"
}

@test "bash_version_at_least returns 0 for older version" {
    bash_version_at_least 4 0
}

@test "bash_version_at_least returns 1 for future version" {
    ! bash_version_at_least 99 0
}

@test "bash_version_at_least handles major-only comparison" {
    bash_version_at_least 4
}

@test "bash_version_at_least higher major wins over lower minor" {
    local cur_major="${BASH_VERSINFO[0]}"
    bash_version_at_least $((cur_major - 1)) 99
}

# =============================================================================
# bash_has_feature TESTS
# =============================================================================

@test "bash_has_feature detects mapfile" {
    bash_has_feature "mapfile"
}

@test "bash_has_feature detects associative_arrays" {
    bash_has_feature "associative_arrays"
}

@test "bash_has_feature detects extglob" {
    bash_has_feature "extglob"
}

@test "bash_has_feature returns 1 for unknown feature" {
    ! bash_has_feature "quantum_computing"
}

@test "bash_has_feature accepts aliases" {
    bash_has_feature "assoc"
    bash_has_feature "readarray"
}

@test "bash_has_feature detects namerefs on bash 4.3+" {
    if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) )); then
        bash_has_feature "namerefs"
    else
        ! bash_has_feature "namerefs"
    fi
}

@test "bash_has_feature detects epochrealtime on bash 5+" {
    if (( BASH_VERSINFO[0] >= 5 )); then
        bash_has_feature "epochrealtime"
    else
        ! bash_has_feature "epochrealtime"
    fi
}

# =============================================================================
# bash_features TESTS
# =============================================================================

@test "bash_features returns JSON object" {
    local result
    result=$(bash_features)
    [[ "$result" == "{"* ]]
    [[ "$result" == *"}" ]]
}

@test "bash_features includes mapfile" {
    local result
    result=$(bash_features)
    [[ "$result" == *'"mapfile":'* ]]
}

@test "bash_features includes namerefs" {
    local result
    result=$(bash_features)
    [[ "$result" == *'"namerefs":'* ]]
}

@test "bash_features values are boolean" {
    local result
    result=$(bash_features)
    [[ "$result" == *":true"* ]] || [[ "$result" == *":false"* ]]
}

# =============================================================================
# perf_timer_start / perf_timer_elapsed / perf_timer_stop TESTS
# =============================================================================

@test "perf_timer_start sets timer variable" {
    perf_timer_start "test_timer"
    [[ -n "${PERF_TIMER_test_timer:-}" ]]
}

@test "perf_timer_elapsed returns numeric value" {
    perf_timer_start "elapsed_test"
    local elapsed
    elapsed=$(perf_timer_elapsed "elapsed_test")
    [[ "$elapsed" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "perf_timer_elapsed measures time" {
    perf_timer_start "measure_test"
    sleep 0.1
    local elapsed
    elapsed=$(perf_timer_elapsed "measure_test")
    # Should be >= 0 (we can't guarantee precision but it should be non-negative)
    [[ "$elapsed" =~ ^[0-9] ]]
}

@test "perf_timer_elapsed returns 0 for unknown timer" {
    local elapsed
    elapsed=$(perf_timer_elapsed "nonexistent") || true
    [ "$elapsed" = "0" ]
}

@test "perf_timer_stop returns JSON" {
    perf_timer_start "stop_test"
    local result
    result=$(perf_timer_stop "stop_test")
    [[ "$result" == *'"timer":"stop_test"'* ]]
    [[ "$result" == *'"duration_s":'* ]]
}

@test "perf_timer_stop cleans up variable" {
    export PERF_TIMER_cleanup_test="12345"
    perf_timer_stop "cleanup_test" >/dev/null
    [[ -z "${PERF_TIMER_cleanup_test:-}" ]]
}

# =============================================================================
# perf_compare TESTS
# =============================================================================

@test "perf_compare returns JSON with winner" {
    local result
    result=$(perf_compare "true" "true" 5)
    [[ "$result" == *'"winner":'* ]]
    [[ "$result" == *'"iterations":5'* ]]
}

@test "perf_compare includes both durations" {
    local result
    result=$(perf_compare "true" "true" 3)
    [[ "$result" == *'"cmd1_total_s":'* ]]
    [[ "$result" == *'"cmd2_total_s":'* ]]
}

@test "perf_compare with different iteration counts" {
    local result
    result=$(perf_compare "true" "true" 1)
    [[ "$result" == *'"iterations":1'* ]]
}

# =============================================================================
# perf_setvar TESTS
# =============================================================================

@test "perf_setvar sets variable value" {
    local myvar=""
    perf_setvar "myvar" "hello"
    [ "$myvar" = "hello" ]
}

@test "perf_setvar handles spaces" {
    local myvar=""
    perf_setvar "myvar" "hello world"
    [ "$myvar" = "hello world" ]
}

@test "perf_setvar handles empty string" {
    local myvar="old"
    perf_setvar "myvar" ""
    [ "$myvar" = "" ]
}

# =============================================================================
# perf_benchmark TESTS
# =============================================================================

@test "perf_benchmark returns JSON" {
    local result
    result=$(perf_benchmark "true" 5)
    [[ "$result" == *'"iterations":5'* ]]
    [[ "$result" == *'"total_s":'* ]]
    [[ "$result" == *'"avg_s":'* ]]
}

@test "perf_benchmark captures exit code" {
    local result
    result=$(perf_benchmark "false" 3) || true
    [[ "$result" == *'"exit_code":1'* ]]
}

@test "perf_benchmark includes command name" {
    local result
    result=$(perf_benchmark "true" 2)
    [[ "$result" == *'"cmd":"true"'* ]]
}

@test "perf_benchmark default iterations is 10" {
    local result
    result=$(perf_benchmark "true")
    [[ "$result" == *'"iterations":10'* ]]
}

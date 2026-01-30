#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Function Composition Library Tests
# =============================================================================
# Tests for lib/compose.sh - Composition, partial application, lazy evaluation
# =============================================================================

load 'test_helper'

setup() {
    source_lib "compose"
    TEST_DIR=$(create_test_dir "compose")

    # Reset compose module state
    compose_reset

    # Suppress output mode for cleaner tests
    export MAINFRAME_OUTPUT="raw"
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# TEST HELPER FUNCTIONS
# =============================================================================

# Simple functions for testing composition
add_one() {
    echo $(($1 + 1))
}

double() {
    echo $(($1 * 2))
}

triple() {
    echo $(($1 * 3))
}

square() {
    echo $(($1 * $1))
}

negate() {
    echo $((-$1))
}

add() {
    echo $(($1 + $2))
}

subtract() {
    echo $(($1 - $2))
}

multiply() {
    echo $(($1 * $2))
}

uppercase() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

lowercase() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

trim() {
    local str="$1"
    str="${str#"${str%%[![:space:]]*}"}"
    str="${str%"${str##*[![:space:]]}"}"
    printf '%s' "$str"
}

prefix_hello() {
    printf 'Hello, %s' "$1"
}

suffix_exclaim() {
    printf '%s!' "$1"
}

is_positive() {
    (($1 > 0))
}

is_negative() {
    (($1 < 0))
}

is_even() {
    (($1 % 2 == 0))
}

is_long() {
    [[ ${#1} -gt 5 ]]
}

failing_fn() {
    return 1
}

sometimes_fails() {
    [[ "$1" == "good" ]] && printf 'success' || return 1
}

naturals_gen() {
    printf '%d' "$1"
}

squares_gen() {
    printf '%d' "$(($1 * $1))"
}

fib_gen() {
    local n="$1"
    if [[ $n -le 1 ]]; then
        printf '%d' "$n"
    else
        local a=0 b=1 i
        for ((i=2; i<=n; i++)); do
            local tmp=$((a + b))
            a=$b
            b=$tmp
        done
        printf '%d' "$b"
    fi
}

expensive_compute() {
    sleep 0.01
    printf 'computed:%s' "$1"
}

log_value() {
    printf '[LOG] %s\n' "$1" >> "$TEST_DIR/tap.log"
}

add_three() {
    echo $(($1 + $2 + $3))
}

# =============================================================================
# COMPOSE TESTS
# =============================================================================

@test "compose creates (f . g)(x) = f(g(x))" {
    local composed
    composed=$(compose "add_one" "double")

    # double(5) = 10, then add_one(10) = 11
    run $composed 5
    [ "$status" -eq 0 ]
    [ "$output" = "11" ]
}

@test "compose with different functions" {
    local composed
    composed=$(compose "square" "add_one")

    # add_one(3) = 4, then square(4) = 16
    run $composed 3
    [ "$status" -eq 0 ]
    [ "$output" = "16" ]
}

@test "compose fails with missing first function" {
    run compose "" "double"
    [ "$status" -ne 0 ]
}

@test "compose fails with missing second function" {
    run compose "double" ""
    [ "$status" -ne 0 ]
}

@test "compose fails with non-existent function" {
    run compose "nonexistent" "double"
    [ "$status" -ne 0 ]
}

@test "compose with string functions" {
    local composed
    composed=$(compose "uppercase" "trim")

    run $composed "  hello  "
    [ "$status" -eq 0 ]
    [ "$output" = "HELLO" ]
}

# =============================================================================
# PIPE_FN TESTS
# =============================================================================

@test "pipe_fn creates left-to-right pipeline" {
    local piped
    piped=$(pipe_fn "double" "add_one")

    # double(5) = 10, then add_one(10) = 11
    run $piped 5
    [ "$status" -eq 0 ]
    [ "$output" = "11" ]
}

@test "pipe_fn with three functions" {
    local piped
    piped=$(pipe_fn "add_one" "double" "square")

    # add_one(2) = 3, double(3) = 6, square(6) = 36
    run $piped 2
    [ "$status" -eq 0 ]
    [ "$output" = "36" ]
}

@test "pipe_fn with single function returns that function" {
    local piped
    piped=$(pipe_fn "double")

    run $piped 5
    [ "$status" -eq 0 ]
    [ "$output" = "10" ]
}

@test "pipe_fn fails with no functions" {
    run pipe_fn
    [ "$status" -ne 0 ]
}

@test "pipe_fn fails with non-existent function" {
    run pipe_fn "double" "nonexistent"
    [ "$status" -ne 0 ]
}

@test "pipe_fn with string transformation" {
    local piped
    piped=$(pipe_fn "trim" "uppercase" "prefix_hello")

    run $piped "  world  "
    [ "$status" -eq 0 ]
    [ "$output" = "Hello, WORLD" ]
}

# =============================================================================
# CHAIN TESTS
# =============================================================================

@test "chain propagates errors" {
    local chained
    chained=$(chain "sometimes_fails" "uppercase")

    # Should fail because sometimes_fails("bad") returns 1
    run $chained "bad"
    [ "$status" -ne 0 ]
}

@test "chain succeeds when all functions succeed" {
    local chained
    chained=$(chain "sometimes_fails" "uppercase")

    run $chained "good"
    [ "$status" -eq 0 ]
    [ "$output" = "SUCCESS" ]
}

@test "chain with multiple functions" {
    local chained
    chained=$(chain "add_one" "double" "add_one")

    run $chained 5
    [ "$status" -eq 0 ]
    [ "$output" = "13" ]  # add_one(5)=6, double(6)=12, add_one(12)=13
}

@test "chain fails with no functions" {
    run chain
    [ "$status" -ne 0 ]
}

# =============================================================================
# PARTIAL TESTS
# =============================================================================

@test "partial pre-fills first argument" {
    local add5
    add5=$(partial "add" 5)

    run $add5 3
    [ "$status" -eq 0 ]
    [ "$output" = "8" ]
}

@test "partial with multiple pre-filled arguments" {
    local mult_by_2_3
    mult_by_2_3=$(partial "add_three" 2 3)

    run $mult_by_2_3 5
    [ "$status" -eq 0 ]
    [ "$output" = "10" ]  # 2 + 3 + 5
}

@test "partial fails with missing function" {
    run partial ""
    [ "$status" -ne 0 ]
}

@test "partial fails with non-existent function" {
    run partial "nonexistent" 5
    [ "$status" -ne 0 ]
}

@test "partial with string arguments" {
    local greet
    greet=$(partial "prefix_hello")

    run $greet "World"
    [ "$status" -eq 0 ]
    [ "$output" = "Hello, World" ]
}

@test "partial with arguments containing spaces" {
    local echo_hello
    echo_hello=$(partial "printf" "Hello, %s!\n")

    run $echo_hello "Gordon Watts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Gordon Watts"* ]]
}

# =============================================================================
# CURRY TESTS
# =============================================================================

@test "curry transforms binary function" {
    local curried
    curried=$(curry "add" 2)

    # First call returns new function
    local f1
    f1=$($curried 5)

    # Second call produces result
    run $f1 3
    [ "$status" -eq 0 ]
    [ "$output" = "8" ]
}

@test "curry fails with invalid arity" {
    run curry "add" "abc"
    [ "$status" -ne 0 ]
}

@test "curry fails with missing function" {
    run curry "" 2
    [ "$status" -ne 0 ]
}

# =============================================================================
# FLIP TESTS
# =============================================================================

@test "flip swaps first two arguments" {
    local flipped
    flipped=$(flip "subtract")

    # subtract(3, 10) normally = -7
    # flipped(3, 10) = subtract(10, 3) = 7
    run $flipped 3 10
    [ "$status" -eq 0 ]
    [ "$output" = "7" ]
}

@test "flip fails with missing function" {
    run flip ""
    [ "$status" -ne 0 ]
}

@test "flip fails with non-existent function" {
    run flip "nonexistent"
    [ "$status" -ne 0 ]
}

# =============================================================================
# TAP TESTS
# =============================================================================

@test "tap executes function for side effect" {
    local tapper
    tapper=$(tap "log_value")

    rm -f "$TEST_DIR/tap.log"
    run $tapper "test_data"
    [ "$status" -eq 0 ]
    [ "$output" = "test_data" ]

    # Verify side effect occurred
    [ -f "$TEST_DIR/tap.log" ]
    grep -q "test_data" "$TEST_DIR/tap.log"
}

@test "tap passes input through unchanged" {
    local tapper
    tapper=$(tap "double")

    run $tapper "hello"
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "tap fails with missing function" {
    run tap ""
    [ "$status" -ne 0 ]
}

# =============================================================================
# IDENTITY TESTS
# =============================================================================

@test "identity returns input unchanged" {
    run identity "hello world"
    [ "$status" -eq 0 ]
    [ "$output" = "hello world" ]
}

@test "identity with number" {
    run identity 42
    [ "$status" -eq 0 ]
    [ "$output" = "42" ]
}

@test "identity with empty string" {
    run identity ""
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# =============================================================================
# CONSTANT TESTS
# =============================================================================

@test "constant ignores input and returns fixed value" {
    local always42
    always42=$(constant 42)

    run $always42 "ignored"
    [ "$status" -eq 0 ]
    [ "$output" = "42" ]
}

@test "constant with string value" {
    local always_hello
    always_hello=$(constant "hello world")

    run $always_hello "whatever"
    [ "$status" -eq 0 ]
    [ "$output" = "hello world" ]
}

@test "constant returns same value for any input" {
    local const_fn
    const_fn=$(constant "fixed")

    local result1 result2 result3
    result1=$($const_fn "a")
    result2=$($const_fn "b")
    result3=$($const_fn 123)

    [ "$result1" = "fixed" ]
    [ "$result2" = "fixed" ]
    [ "$result3" = "fixed" ]
}

# =============================================================================
# APPLY TESTS
# =============================================================================

@test "apply spreads array as arguments" {
    local args=(5 3)

    run apply "add" args
    [ "$status" -eq 0 ]
    [ "$output" = "8" ]
}

@test "apply with three arguments" {
    local args=(1 2 3)

    run apply "add_three" args
    [ "$status" -eq 0 ]
    [ "$output" = "6" ]
}

@test "apply fails with missing function" {
    local args=(1 2)

    run apply "" args
    [ "$status" -ne 0 ]
}

# =============================================================================
# LAZY TESTS
# =============================================================================

@test "lazy creates deferred computation" {
    local thunk
    thunk=$(lazy "double" 5)

    [ -n "$thunk" ]
    [[ "$thunk" == thunk_* ]]
}

@test "force evaluates lazy thunk" {
    local thunk
    thunk=$(lazy "double" 5)

    run force "$thunk"
    [ "$status" -eq 0 ]
    [ "$output" = "10" ]
}

@test "force returns cached result on subsequent calls" {
    local thunk
    thunk=$(lazy "expensive_compute" "test")

    # First force
    local result1
    result1=$(force "$thunk")

    # Second force should return cached
    local result2
    result2=$(force "$thunk")

    [ "$result1" = "$result2" ]
    [ "$result1" = "computed:test" ]
}

@test "lazy fails with missing function" {
    run lazy ""
    [ "$status" -ne 0 ]
}

@test "force fails with invalid thunk_id" {
    run force "invalid_thunk"
    [ "$status" -ne 0 ]
}

@test "force fails with empty thunk_id" {
    run force ""
    [ "$status" -ne 0 ]
}

@test "multiple thunks are independent" {
    local thunk1 thunk2
    thunk1=$(lazy "double" 5)
    thunk2=$(lazy "triple" 4)

    local result1 result2
    result1=$(force "$thunk1")
    result2=$(force "$thunk2")

    [ "$result1" = "10" ]
    [ "$result2" = "12" ]
}

# =============================================================================
# LAZY_SEQ TESTS
# =============================================================================

@test "lazy_seq creates lazy sequence" {
    local seq_id
    seq_id=$(lazy_seq "naturals_gen")

    [ -n "$seq_id" ]
    [[ "$seq_id" == seq_* ]]
}

@test "take_lazy returns n elements" {
    local seq_id
    seq_id=$(lazy_seq "naturals_gen")

    run take_lazy 5 "$seq_id"
    [ "$status" -eq 0 ]

    # Should output 0, 1, 2, 3, 4 on separate lines
    local -a lines
    IFS=$'\n' read -r -d '' -a lines <<< "$output" || true

    [ "${lines[0]}" = "0" ]
    [ "${lines[1]}" = "1" ]
    [ "${lines[2]}" = "2" ]
    [ "${lines[3]}" = "3" ]
    [ "${lines[4]}" = "4" ]
}

@test "take_lazy advances sequence state" {
    local seq_id
    seq_id=$(lazy_seq "naturals_gen")

    # Take first 3
    take_lazy 3 "$seq_id" > /dev/null

    # Take next 3 should be 3, 4, 5
    run take_lazy 3 "$seq_id"
    [ "$status" -eq 0 ]

    local -a lines
    IFS=$'\n' read -r -d '' -a lines <<< "$output" || true

    [ "${lines[0]}" = "3" ]
    [ "${lines[1]}" = "4" ]
    [ "${lines[2]}" = "5" ]
}

@test "lazy_seq with squares generator" {
    local seq_id
    seq_id=$(lazy_seq "squares_gen")

    run take_lazy 5 "$seq_id"
    [ "$status" -eq 0 ]

    local -a lines
    IFS=$'\n' read -r -d '' -a lines <<< "$output" || true

    [ "${lines[0]}" = "0" ]   # 0^2
    [ "${lines[1]}" = "1" ]   # 1^2
    [ "${lines[2]}" = "4" ]   # 2^2
    [ "${lines[3]}" = "9" ]   # 3^2
    [ "${lines[4]}" = "16" ]  # 4^2
}

@test "lazy_seq fails with missing generator" {
    run lazy_seq ""
    [ "$status" -ne 0 ]
}

@test "take_lazy fails with invalid sequence" {
    run take_lazy 5 "invalid_seq"
    [ "$status" -ne 0 ]
}

# =============================================================================
# MEMOIZE_FN TESTS
# =============================================================================

@test "memoize_fn creates memoized function" {
    local memo_fn
    memo_fn=$(memoize_fn "double")

    [ -n "$memo_fn" ]
    [[ "$memo_fn" == _memo_* ]]
}

@test "memoize_fn caches results" {
    local memo_fn
    memo_fn=$(memoize_fn "expensive_compute")

    # First call computes
    local result1
    result1=$($memo_fn "test")

    # Second call should be cached (much faster)
    local result2
    result2=$($memo_fn "test")

    [ "$result1" = "$result2" ]
    [ "$result1" = "computed:test" ]
}

@test "memoize_fn caches different args separately" {
    local memo_fn
    memo_fn=$(memoize_fn "double")

    local result1 result2
    result1=$($memo_fn 5)
    result2=$($memo_fn 7)

    [ "$result1" = "10" ]
    [ "$result2" = "14" ]
}

@test "memoize_fn fails with missing function" {
    run memoize_fn ""
    [ "$status" -ne 0 ]
}

# =============================================================================
# CACHE_CLEAR_FN TESTS
# =============================================================================

@test "cache_clear_fn clears all memoization" {
    local memo_fn
    memo_fn=$(memoize_fn "double")

    # Populate cache
    $memo_fn 5 > /dev/null
    $memo_fn 7 > /dev/null

    run cache_clear_fn
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "cache_clear_fn clears matching pattern" {
    local memo_fn1 memo_fn2
    memo_fn1=$(memoize_fn "double")
    memo_fn2=$(memoize_fn "triple")

    # Populate caches
    $memo_fn1 5 > /dev/null
    $memo_fn2 5 > /dev/null

    run cache_clear_fn "double"
    [ "$status" -eq 0 ]
}

# =============================================================================
# COMPOSE_RESET TESTS
# =============================================================================

@test "compose_reset clears all state" {
    # Create some state
    lazy "double" 5 > /dev/null
    lazy_seq "naturals_gen" > /dev/null
    local memo_fn
    memo_fn=$(memoize_fn "double")
    $memo_fn 5 > /dev/null

    compose_reset

    run compose_stats --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"thunks":0'* ]]
    [[ "$output" == *'"lazy_sequences":0'* ]]
    [[ "$output" == *'"memo_entries":0'* ]]
}

# =============================================================================
# COMPOSE_STATS TESTS
# =============================================================================

@test "compose_stats returns statistics" {
    run compose_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"Thunks"* ]]
    [[ "$output" == *"Memo Entries"* ]]
}

@test "compose_stats --json returns JSON" {
    run compose_stats --json
    [ "$status" -eq 0 ]
    [[ "$output" == "{"* ]]
    [[ "$output" == *"thunks"* ]]
}

# =============================================================================
# TRY_EACH TESTS
# =============================================================================

@test "try_each returns first success" {
    local fallback
    fallback=$(try_each "failing_fn" "double" "triple")

    run $fallback 5
    [ "$status" -eq 0 ]
    [ "$output" = "10" ]
}

@test "try_each fails when all fail" {
    local fallback
    fallback=$(try_each "failing_fn" "failing_fn")

    run $fallback 5
    [ "$status" -ne 0 ]
}

@test "try_each fails with no functions" {
    run try_each
    [ "$status" -ne 0 ]
}

# =============================================================================
# WHEN TESTS
# =============================================================================

@test "when applies function when predicate true" {
    local conditional
    conditional=$(when "is_positive" "double")

    run $conditional 5
    [ "$status" -eq 0 ]
    [ "$output" = "10" ]
}

@test "when returns input unchanged when predicate false" {
    local conditional
    conditional=$(when "is_positive" "double")

    run $conditional -5
    [ "$status" -eq 0 ]
    [ "$output" = "-5" ]
}

@test "when fails with missing predicate" {
    run when "" "double"
    [ "$status" -ne 0 ]
}

@test "when fails with missing function" {
    run when "is_positive" ""
    [ "$status" -ne 0 ]
}

# =============================================================================
# IF_ELSE TESTS
# =============================================================================

@test "if_else applies then_fn when predicate true" {
    local classifier
    classifier=$(if_else "is_positive" "double" "negate")

    run $classifier 5
    [ "$status" -eq 0 ]
    [ "$output" = "10" ]
}

@test "if_else applies else_fn when predicate false" {
    local classifier
    classifier=$(if_else "is_positive" "double" "negate")

    run $classifier -5
    [ "$status" -eq 0 ]
    [ "$output" = "5" ]
}

@test "if_else fails with missing arguments" {
    run if_else "is_positive" "double" ""
    [ "$status" -ne 0 ]
}

# =============================================================================
# TIMES TESTS
# =============================================================================

@test "times applies function n times" {
    local triple_double
    triple_double=$(times 3 "double")

    # double(double(double(2))) = double(double(4)) = double(8) = 16
    run $triple_double 2
    [ "$status" -eq 0 ]
    [ "$output" = "16" ]
}

@test "times 0 returns input unchanged" {
    local zero_times
    zero_times=$(times 0 "double")

    run $zero_times 5
    [ "$status" -eq 0 ]
    [ "$output" = "5" ]
}

@test "times 1 applies function once" {
    local once
    once=$(times 1 "double")

    run $once 5
    [ "$status" -eq 0 ]
    [ "$output" = "10" ]
}

@test "times fails with negative n" {
    run times -1 "double"
    [ "$status" -ne 0 ]
}

@test "times fails with missing function" {
    run times 3 ""
    [ "$status" -ne 0 ]
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

@test "compose and pipe_fn are inverses" {
    # compose(f, g)(x) should equal pipe_fn(g, f)(x)
    local composed piped
    composed=$(compose "add_one" "double")
    piped=$(pipe_fn "double" "add_one")

    local result1 result2
    result1=$($composed 5)
    result2=$($piped 5)

    [ "$result1" = "$result2" ]
}

@test "partial can be used with compose" {
    local add5 add5_then_double
    add5=$(partial "add" 5)
    add5_then_double=$(compose "double" "$add5")

    # add5(3) = 8, double(8) = 16
    run $add5_then_double 3
    [ "$status" -eq 0 ]
    [ "$output" = "16" ]
}

@test "memoize_fn works with composed functions" {
    local composed memo_composed
    composed=$(compose "double" "add_one")
    memo_composed=$(memoize_fn "$composed")

    run $memo_composed 5
    [ "$status" -eq 0 ]
    [ "$output" = "12" ]  # add_one(5)=6, double(6)=12
}

@test "chain with partial application" {
    local add5 multiply_by_2
    add5=$(partial "add" 5)
    multiply_by_2=$(partial "multiply" 2)

    local chained
    chained=$(chain "$add5" "$multiply_by_2")

    run $chained 3
    [ "$status" -eq 0 ]
    [ "$output" = "16" ]  # (3+5)*2 = 16
}

@test "lazy evaluation with composed function" {
    local composed thunk
    composed=$(compose "double" "add_one")
    thunk=$(lazy "$composed" 5)

    run force "$thunk"
    [ "$status" -eq 0 ]
    [ "$output" = "12" ]
}

@test "complex pipeline with multiple patterns" {
    # Build a processing pipeline
    local add5 doubled_add5 conditional final

    # Step 1: Create partial function
    add5=$(partial "add" 5)

    # Step 2: Compose with double
    doubled_add5=$(compose "double" "$add5")

    # Step 3: Apply conditionally
    conditional=$(when "is_positive" "$doubled_add5")

    # Test with positive number
    run $conditional 3
    [ "$status" -eq 0 ]
    [ "$output" = "16" ]  # (3+5)*2 = 16

    # Test with negative number (no transformation)
    run $conditional -3
    [ "$status" -eq 0 ]
    [ "$output" = "-3" ]
}

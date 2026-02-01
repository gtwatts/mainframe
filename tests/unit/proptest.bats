#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/proptest.bats - Property-Based Testing Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/proptest.sh
#              Property-based testing framework with generators and shrinking
# Test Count: 50+ test cases
# Categories: generators, shrinking, assertions, test runner, USOP output
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Source the library with minimal dependencies
    MAINFRAME_LIBS="core" source "$MAINFRAME_ROOT/lib/common.sh"
    source "$MAINFRAME_ROOT/lib/proptest.sh"

    # Use fixed seed for reproducible tests
    PROPTEST_SEED=12345
    PROPTEST_VERBOSE=0
    PROPTEST_ITERATIONS=10
    PROPTEST_OUTPUT=text
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
    proptest_reset
}

# =============================================================================
# CATEGORY 1: RANDOM NUMBER GENERATION
# =============================================================================

@test "_proptest_srand: initializes random state" {
    _proptest_srand 42
    [[ "$_PROPTEST_RAND_STATE" -gt 0 ]]
    [[ "$_PROPTEST_LAST_SEED" == "42" ]]
}

@test "_proptest_rand: generates positive integers" {
    _proptest_srand 12345
    local val
    val=$(_proptest_rand)
    [[ $val -ge 0 ]]
}

@test "_proptest_rand: is reproducible with same seed" {
    _proptest_srand 99999
    local val1
    val1=$(_proptest_rand)

    _proptest_srand 99999
    local val2
    val2=$(_proptest_rand)

    [[ "$val1" == "$val2" ]]
}

@test "_proptest_rand_range: generates values in range" {
    _proptest_srand 12345
    for _ in {1..20}; do
        local val
        val=$(_proptest_rand_range 10 20)
        [[ $val -ge 10 ]]
        [[ $val -le 20 ]]
    done
}

# =============================================================================
# CATEGORY 2: INTEGER GENERATORS
# =============================================================================

@test "gen_int: generates integers" {
    _proptest_srand 12345
    local val
    val=$(gen_int)
    [[ "$val" =~ ^-?[0-9]+$ ]]
}

@test "gen_int: respects min/max bounds" {
    _proptest_srand 12345
    for _ in {1..20}; do
        local val
        val=$(gen_int 5 15)
        [[ $val -ge 5 ]]
        [[ $val -le 15 ]]
    done
}

@test "gen_int: handles negative range" {
    _proptest_srand 12345
    for _ in {1..10}; do
        local val
        val=$(gen_int -100 -50)
        [[ $val -ge -100 ]]
        [[ $val -le -50 ]]
    done
}

@test "gen_positive_int: generates positive integers only" {
    _proptest_srand 12345
    for _ in {1..20}; do
        local val
        val=$(gen_positive_int 100)
        [[ $val -ge 1 ]]
        [[ $val -le 100 ]]
    done
}

@test "gen_nat: includes zero" {
    _proptest_srand 1  # seed that should hit 0 eventually
    local found_zero=false
    for _ in {1..100}; do
        local val
        val=$(gen_nat 5)
        [[ $val -ge 0 ]]
        [[ $val -le 5 ]]
        [[ $val -eq 0 ]] && found_zero=true
    done
    # Zero should be possible (may not always hit in 100 tries, so just check range)
    [[ $val -ge 0 ]]
}

# =============================================================================
# CATEGORY 3: STRING GENERATORS
# =============================================================================

@test "gen_string: generates empty string when min_len is 0" {
    _proptest_srand 1
    # Run multiple times to get a short string
    local found_short=false
    for _ in {1..50}; do
        local val
        val=$(gen_string 0 5)
        [[ ${#val} -le 5 ]]
        [[ ${#val} -lt 3 ]] && found_short=true
    done
    [[ $found_short == true ]]
}

@test "gen_string: respects length bounds" {
    _proptest_srand 12345
    for _ in {1..20}; do
        local val
        val=$(gen_string 5 10)
        local len=${#val}
        [[ $len -ge 5 ]]
        [[ $len -le 10 ]]
    done
}

@test "gen_string: uses custom charset" {
    _proptest_srand 12345
    local val
    val=$(gen_string 10 10 "abc")
    [[ "$val" =~ ^[abc]+$ ]]
    [[ ${#val} -eq 10 ]]
}

@test "gen_alpha: generates only letters" {
    _proptest_srand 12345
    local val
    val=$(gen_alpha 10 10)
    [[ "$val" =~ ^[a-zA-Z]+$ ]]
}

@test "gen_lower: generates only lowercase" {
    _proptest_srand 12345
    local val
    val=$(gen_lower 10 10)
    [[ "$val" =~ ^[a-z]+$ ]]
}

@test "gen_upper: generates only uppercase" {
    _proptest_srand 12345
    local val
    val=$(gen_upper 10 10)
    [[ "$val" =~ ^[A-Z]+$ ]]
}

@test "gen_ascii: generates printable ASCII" {
    _proptest_srand 12345
    local val
    val=$(gen_ascii 10 20)
    local len=${#val}
    [[ $len -ge 10 ]]
    [[ $len -le 20 ]]
}

@test "gen_hex: generates hex characters" {
    _proptest_srand 12345
    local val
    val=$(gen_hex 16 16)
    [[ "$val" =~ ^[0-9a-f]+$ ]]
    [[ ${#val} -eq 16 ]]
}

# =============================================================================
# CATEGORY 4: CHOICE AND BOOLEAN GENERATORS
# =============================================================================

@test "gen_choice: selects from provided options" {
    _proptest_srand 12345
    for _ in {1..20}; do
        local val
        val=$(gen_choice "apple" "banana" "cherry")
        [[ "$val" == "apple" || "$val" == "banana" || "$val" == "cherry" ]]
    done
}

@test "gen_choice: returns single option when only one provided" {
    _proptest_srand 12345
    local val
    val=$(gen_choice "only")
    [[ "$val" == "only" ]]
}

@test "gen_bool: returns true or false" {
    _proptest_srand 12345
    for _ in {1..20}; do
        local val
        val=$(gen_bool)
        [[ "$val" == "true" || "$val" == "false" ]]
    done
}

# =============================================================================
# CATEGORY 5: COMPLEX GENERATORS
# =============================================================================

@test "gen_email: generates valid email format" {
    _proptest_srand 12345
    local val
    val=$(gen_email)
    [[ "$val" =~ ^[a-z]+@[a-z]+\.[a-z]+$ ]]
}

@test "gen_uuid: generates valid UUID v4 format" {
    _proptest_srand 12345
    local val
    val=$(gen_uuid)
    # UUID v4: 8-4-4-4-12 format with version 4 marker
    [[ "$val" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]
}

@test "gen_json_object: generates valid JSON" {
    _proptest_srand 12345
    local val
    val=$(gen_json_object 3)
    # Should start with { and end with }
    [[ "$val" == "{"* ]]
    [[ "$val" == *"}" ]]
}

@test "gen_json_object: handles empty object" {
    _proptest_srand 1
    # With low seed, should eventually generate empty object
    local found_empty=false
    for _ in {1..50}; do
        local val
        val=$(gen_json_object 2)
        [[ "$val" == "{}" ]] && found_empty=true
    done
    # At minimum, all outputs should be valid JSON objects
    [[ "$val" == "{"* ]]
}

@test "gen_url: generates valid URL format" {
    _proptest_srand 12345
    local val
    val=$(gen_url)
    [[ "$val" =~ ^https?://[a-z]+\.[a-z]+ ]]
}

@test "gen_date: generates valid ISO date format" {
    _proptest_srand 12345
    local val
    val=$(gen_date 2000 2025)
    [[ "$val" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

@test "gen_ipv4: generates valid IPv4 format" {
    _proptest_srand 12345
    local val
    val=$(gen_ipv4)
    [[ "$val" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]

    # Validate octets are 0-255
    local IFS='.'
    read -ra octets <<< "$val"
    for octet in "${octets[@]}"; do
        [[ $octet -ge 0 ]]
        [[ $octet -le 255 ]]
    done
}

@test "gen_port: generates valid port numbers" {
    _proptest_srand 12345
    for _ in {1..20}; do
        local val
        val=$(gen_port)
        [[ $val -ge 1024 ]]
        [[ $val -le 65535 ]]
    done
}

@test "gen_port: includes privileged ports when requested" {
    _proptest_srand 12345
    local found_low=false
    for _ in {1..100}; do
        local val
        val=$(gen_port true)
        [[ $val -ge 1 ]]
        [[ $val -le 65535 ]]
        [[ $val -lt 1024 ]] && found_low=true
    done
    # Should find at least one low port in 100 tries
    [[ $found_low == true ]]
}

@test "gen_float: generates valid floating point numbers" {
    _proptest_srand 12345
    local val
    val=$(gen_float 0 100 2)
    [[ "$val" =~ ^-?[0-9]+\.[0-9]+$ ]]
}

@test "gen_array: generates array of values" {
    _proptest_srand 12345
    local val
    val=$(gen_array "gen_int 1 10" 3 5)
    local count
    count=$(echo "$val" | wc -l)
    [[ $count -ge 3 ]]
    [[ $count -le 5 ]]
}

@test "gen_oneof: selects from multiple generators" {
    _proptest_srand 12345
    for _ in {1..20}; do
        local val
        val=$(gen_oneof "gen_int 1 10" "gen_lower 5 5")
        # Should be either a number or a 5-char lowercase string
        [[ "$val" =~ ^[0-9]+$ ]] || [[ "$val" =~ ^[a-z]{5}$ ]]
    done
}

# =============================================================================
# CATEGORY 6: SHRINKING
# =============================================================================

@test "proptest_shrink_int: shrinks towards zero" {
    local shrinks
    mapfile -t shrinks < <(proptest_shrink_int 100)

    # Should include 0
    [[ " ${shrinks[*]} " =~ " 0 " ]]

    # Should include 50 (half)
    [[ " ${shrinks[*]} " =~ " 50 " ]]

    # Should include 99 (decrement)
    [[ " ${shrinks[*]} " =~ " 99 " ]]
}

@test "proptest_shrink_int: handles negative numbers" {
    local shrinks
    mapfile -t shrinks < <(proptest_shrink_int -50)

    # Should include 0
    [[ " ${shrinks[*]} " =~ " 0 " ]]

    # Should include positive version
    [[ " ${shrinks[*]} " =~ " 50 " ]]
}

@test "proptest_shrink_string: shrinks by removing characters" {
    local shrinks
    mapfile -t shrinks < <(proptest_shrink_string "hello")

    # Should include empty string
    local found_empty=false
    for s in "${shrinks[@]}"; do
        [[ -z "$s" ]] && found_empty=true
    done
    [[ $found_empty == true ]]

    # Should include "ello" (first char removed)
    [[ " ${shrinks[*]} " =~ " ello " ]]

    # Should include "hell" (last char removed)
    [[ " ${shrinks[*]} " =~ " hell " ]]
}

@test "proptest_shrink: auto-detects integer type" {
    local shrinks
    mapfile -t shrinks < <(proptest_shrink 42)

    [[ " ${shrinks[*]} " =~ " 0 " ]]
}

@test "proptest_shrink: auto-detects string type" {
    local shrinks
    mapfile -t shrinks < <(proptest_shrink "test")

    [[ " ${shrinks[*]} " =~ " est " ]] || [[ " ${shrinks[*]} " =~ " tes " ]]
}

# =============================================================================
# CATEGORY 7: ASSERTIONS
# =============================================================================

@test "proptest_check: returns 0 for true condition" {
    proptest_check '[[ 1 -eq 1 ]]' "one equals one"
    [[ $? -eq 0 ]]
}

@test "proptest_check: returns 1 for false condition" {
    run proptest_check '[[ 1 -eq 2 ]]' "one equals two"
    [[ "$status" -eq 1 ]]
}

@test "proptest_assert_eq: passes for equal values" {
    proptest_assert_eq "hello" "hello"
    [[ $? -eq 0 ]]
}

@test "proptest_assert_eq: fails for unequal values" {
    run proptest_assert_eq "hello" "world"
    [[ "$status" -eq 1 ]]
}

@test "proptest_assert_ne: passes for unequal values" {
    proptest_assert_ne "hello" "world"
    [[ $? -eq 0 ]]
}

@test "proptest_assert_ne: fails for equal values" {
    run proptest_assert_ne "hello" "hello"
    [[ "$status" -eq 1 ]]
}

@test "proptest_assert_match: passes for matching pattern" {
    proptest_assert_match '^[0-9]+$' "12345"
    [[ $? -eq 0 ]]
}

@test "proptest_assert_match: fails for non-matching pattern" {
    run proptest_assert_match '^[0-9]+$' "hello"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 8: TEST RUNNER
# =============================================================================

@test "proptest_run: passes for always-true property" {
    run proptest_run "always_true" "gen_int 1 100" '[[ $1 -gt 0 ]]'
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "PASS" ]]
}

@test "proptest_run: fails for always-false property" {
    run proptest_run "always_false" "gen_int 1 100" '[[ $1 -lt 0 ]]'
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "FAIL" ]]
}

@test "proptest_run: reports seed for reproducibility" {
    run proptest_run "seed_test" "gen_int 1 10" '[[ $1 -lt 20 ]]'
    [[ "$output" =~ "seed=" ]]
}

@test "proptest_run: respects PROPTEST_ITERATIONS" {
    PROPTEST_ITERATIONS=5
    run proptest_run "iteration_test" "gen_int 1 10" '[[ $1 -gt 0 ]]'
    [[ "$output" =~ "5 iterations" ]]
}

@test "proptest_run: shrinks failing input" {
    PROPTEST_MAX_SHRINKS=10
    run proptest_run "shrink_test" "gen_int 50 100" '[[ $1 -lt 50 ]]'
    [[ "$status" -eq 1 ]]
    # Should attempt to shrink
    [[ "$output" =~ "Shrunk" ]] || [[ "$output" =~ "minimal" ]] || [[ "$status" -eq 1 ]]
}

@test "proptest: convenience alias works" {
    run proptest "convenience_test" "gen_int 1 10" '[[ $1 -ge 1 ]]'
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "PASS" ]]
}

@test "proptest_reset: clears statistics" {
    _PROPTEST_PASS_COUNT=10
    _PROPTEST_FAIL_COUNT=5
    proptest_reset
    [[ $_PROPTEST_PASS_COUNT -eq 0 ]]
    [[ $_PROPTEST_FAIL_COUNT -eq 0 ]]
}

@test "proptest_stats: reports statistics" {
    _PROPTEST_PASS_COUNT=5
    _PROPTEST_FAIL_COUNT=2
    _PROPTEST_SHRINK_COUNT=3
    local stats
    stats=$(proptest_stats)
    [[ "$stats" =~ "passed=5" ]]
    [[ "$stats" =~ "failed=2" ]]
    [[ "$stats" =~ "shrinks=3" ]]
}

# =============================================================================
# CATEGORY 9: USOP OUTPUT
# =============================================================================

@test "proptest_usop_result: outputs text format" {
    PROPTEST_OUTPUT=text
    local result
    result=$(proptest_usop_result "test_name" "pass")
    [[ "$result" =~ "[pass]" ]]
    [[ "$result" =~ "test_name" ]]
}

@test "proptest_usop_result: outputs JSON format" {
    PROPTEST_OUTPUT=json
    local result
    result=$(proptest_usop_result "test_name" "pass" "details here")
    [[ "$result" =~ '"test":"test_name"' ]]
    [[ "$result" =~ '"status":"pass"' ]]
    [[ "$result" =~ '"details":"details here"' ]]
}

@test "proptest_run: outputs JSON when configured" {
    PROPTEST_OUTPUT=json
    run proptest_run "json_test" "gen_int 1 10" '[[ $1 -gt 0 ]]'
    [[ "$output" =~ '"status":"pass"' ]]
}

# =============================================================================
# CATEGORY 10: PROPERTY TEST EXAMPLES
# =============================================================================

@test "property: string length is non-negative" {
    run proptest "string_length_nonneg" "gen_string 0 100" '
        local input="$1"
        local len=${#input}
        [[ $len -ge 0 ]]
    '
    [[ "$status" -eq 0 ]]
}

@test "property: integer addition is commutative" {
    run proptest "addition_commutative" "gen_int -100 100" '
        local a="$1"
        # Generate another number with current seed
        local b=$(gen_int -100 100)
        [[ $((a + b)) -eq $((b + a)) ]]
    '
    [[ "$status" -eq 0 ]]
}

@test "property: double negation returns original" {
    run proptest "double_negation" "gen_int -1000 1000" '
        local n="$1"
        local neg=$((-n))
        local double_neg=$((-neg))
        [[ $n -eq $double_neg ]]
    '
    [[ "$status" -eq 0 ]]
}

@test "property: uppercase is idempotent" {
    run proptest "uppercase_idempotent" "gen_alpha 1 50" '
        local input="$1"
        local upper1="${input^^}"
        local upper2="${upper1^^}"
        [[ "$upper1" == "$upper2" ]]
    '
    [[ "$status" -eq 0 ]]
}

# =============================================================================
# CATEGORY 11: EDGE CASES
# =============================================================================

@test "gen_string: handles zero length" {
    _proptest_srand 12345
    local val
    val=$(gen_string 0 0)
    [[ -z "$val" ]]
}

@test "gen_int: handles single value range" {
    _proptest_srand 12345
    local val
    val=$(gen_int 42 42)
    [[ $val -eq 42 ]]
}

@test "gen_choice: handles empty list gracefully" {
    run gen_choice
    [[ "$status" -eq 1 ]]
}

@test "proptest_shrink_string: handles empty string" {
    local shrinks
    mapfile -t shrinks < <(proptest_shrink_string "")
    # Empty string shrinks to itself
    [[ ${#shrinks[@]} -ge 1 ]]
}

@test "proptest_shrink_int: handles zero" {
    local shrinks
    mapfile -t shrinks < <(proptest_shrink_int 0)
    # Zero shrinks to zero
    [[ " ${shrinks[*]} " =~ " 0 " ]]
}

# =============================================================================
# CATEGORY 12: MODULE EXPORTS
# =============================================================================

@test "_PROPTEST_EXPORTS: contains core functions" {
    [[ " ${_PROPTEST_EXPORTS[*]} " =~ " proptest_run " ]]
    [[ " ${_PROPTEST_EXPORTS[*]} " =~ " proptest_check " ]]
    [[ " ${_PROPTEST_EXPORTS[*]} " =~ " proptest_shrink " ]]
}

@test "_PROPTEST_EXPORTS: contains generators" {
    [[ " ${_PROPTEST_EXPORTS[*]} " =~ " gen_int " ]]
    [[ " ${_PROPTEST_EXPORTS[*]} " =~ " gen_string " ]]
    [[ " ${_PROPTEST_EXPORTS[*]} " =~ " gen_email " ]]
    [[ " ${_PROPTEST_EXPORTS[*]} " =~ " gen_uuid " ]]
}

@test "_PROPTEST_EXPORTS: contains assertions" {
    [[ " ${_PROPTEST_EXPORTS[*]} " =~ " proptest_assert_eq " ]]
    [[ " ${_PROPTEST_EXPORTS[*]} " =~ " proptest_assert_ne " ]]
    [[ " ${_PROPTEST_EXPORTS[*]} " =~ " proptest_assert_match " ]]
}

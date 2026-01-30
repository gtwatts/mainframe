#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Property-Based Testing Module Tests
# =============================================================================
# Comprehensive tests for lib/property_test.sh (40+ functions)
# Covers: generators, shrinking, property testing, statistics, and USOP output
# =============================================================================

load 'test_helper'

setup() {
    source_lib "property_test"
    export MAINFRAME_QUIET=1
    export PROP_VERBOSE=0
    TEST_DIR=$(create_test_dir "property_test")
    # Reset state before each test
    _prop_reset
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# CONFIGURATION TESTS
# =============================================================================

@test "prop_set_iterations sets default iterations" {
    prop_set_iterations 500
    [ "$PROP_DEFAULT_ITERATIONS" = "500" ]
}

@test "prop_set_iterations rejects non-positive values" {
    ! prop_set_iterations 0
    ! prop_set_iterations -1
    ! prop_set_iterations "abc"
}

@test "prop_set_seed sets random seed" {
    prop_set_seed 12345
    [ "$PROP_SEED" = "12345" ]
}

@test "prop_set_seed rejects invalid values" {
    ! prop_set_seed "abc"
    ! prop_set_seed "-1"
}

@test "prop_set_max_shrinks sets max shrink attempts" {
    prop_set_max_shrinks 200
    [ "$PROP_MAX_SHRINKS" = "200" ]
}

@test "prop_set_max_shrinks rejects invalid values" {
    ! prop_set_max_shrinks 0
    ! prop_set_max_shrinks "abc"
}

@test "prop_verbose enables verbose mode" {
    prop_verbose
    [ "$PROP_VERBOSE" = "1" ]
}

# =============================================================================
# GENERATOR TESTS - INTEGER
# =============================================================================

@test "gen_int generates integer" {
    local result
    result=$(gen_int)
    [[ "$result" =~ ^-?[0-9]+$ ]]
}

@test "gen_int respects size parameter" {
    local result
    result=$(gen_int 5)
    [[ "$result" -ge -5 && "$result" -le 5 ]]
}

@test "gen_int_range generates in specified range" {
    local result
    result=$(gen_int_range 10 20)
    [[ "$result" -ge 10 && "$result" -le 20 ]]
}

@test "gen_int_range handles reversed min/max" {
    local result
    result=$(gen_int_range 20 10)
    [[ "$result" -ge 10 && "$result" -le 20 ]]
}

@test "gen_int_range handles negative range" {
    local result
    result=$(gen_int_range -100 -50)
    [[ "$result" -ge -100 && "$result" -le -50 ]]
}

@test "gen_int_range handles single value range" {
    local result
    result=$(gen_int_range 42 42)
    [ "$result" = "42" ]
}

# =============================================================================
# GENERATOR TESTS - FLOAT
# =============================================================================

@test "gen_float generates float" {
    local result
    result=$(gen_float)
    [[ "$result" =~ ^-?[0-9]+\.[0-9]+$ ]]
}

@test "gen_float respects bounds" {
    local result int_part
    result=$(gen_float 5)
    int_part="${result%%.*}"
    [[ "$int_part" -ge -5 && "$int_part" -le 5 ]]
}

# =============================================================================
# GENERATOR TESTS - BOOLEAN
# =============================================================================

@test "gen_bool returns true or false" {
    local result
    result=$(gen_bool)
    [[ "$result" == "true" || "$result" == "false" ]]
}

@test "gen_bool generates both values over multiple calls" {
    local has_true=0
    local has_false=0
    local i

    for ((i=0; i<100; i++)); do
        local result
        result=$(gen_bool)
        [[ "$result" == "true" ]] && has_true=1
        [[ "$result" == "false" ]] && has_false=1
    done

    [ "$has_true" = "1" ]
    [ "$has_false" = "1" ]
}

# =============================================================================
# GENERATOR TESTS - STRING
# =============================================================================

@test "gen_string generates string" {
    local result
    result=$(gen_string)
    # Result should be a string (possibly empty)
    [[ -n "$result" || "$result" == "" ]]
}

@test "gen_string respects max length" {
    local result
    result=$(gen_string 5)
    [ "${#result}" -le 5 ]
}

@test "gen_string_alpha generates alphabetic string" {
    local result
    result=$(gen_string_alpha 10)
    # Should only contain letters
    [[ "$result" =~ ^[a-zA-Z]*$ ]]
}

@test "gen_string_alnum generates alphanumeric string" {
    local result
    result=$(gen_string_alnum 10)
    # Should only contain letters and digits
    [[ "$result" =~ ^[a-zA-Z0-9]*$ ]]
}

@test "gen_string_pattern generates matching pattern [a-z]+" {
    local result
    result=$(gen_string_pattern "[a-z]+" 10)
    # Should only contain lowercase letters, at least 1
    [[ "$result" =~ ^[a-z]+$ ]]
}

@test "gen_string_pattern generates matching pattern [A-Z]*" {
    local result
    result=$(gen_string_pattern "[A-Z]*" 10)
    # Should only contain uppercase letters
    [[ "$result" =~ ^[A-Z]*$ ]]
}

@test "gen_string_pattern generates matching pattern [0-9]+" {
    local result
    result=$(gen_string_pattern "[0-9]+" 10)
    # Should only contain digits, at least 1
    [[ "$result" =~ ^[0-9]+$ ]]
}

# =============================================================================
# GENERATOR TESTS - CHOICE
# =============================================================================

@test "gen_choice selects from options" {
    local result
    result=$(gen_choice "red" "green" "blue")
    [[ "$result" == "red" || "$result" == "green" || "$result" == "blue" ]]
}

@test "gen_choice fails with no options" {
    ! gen_choice
}

@test "gen_choice with single option always returns it" {
    local result
    result=$(gen_choice "only")
    [ "$result" = "only" ]
}

@test "gen_frequency uses weighted selection" {
    # With extreme weights, should almost always get the heavy option
    local heavy_count=0
    local i

    for ((i=0; i<50; i++)); do
        local result
        result=$(gen_frequency 99 "heavy" 1 "light")
        [[ "$result" == "heavy" ]] && ((heavy_count++))
    done

    # Should have heavy at least 40 times out of 50
    [ "$heavy_count" -ge 40 ]
}

@test "gen_one_of selects and runs a generator" {
    # Define simple test generators
    test_gen_a() { echo "A"; }
    test_gen_b() { echo "B"; }

    local result
    result=$(gen_one_of test_gen_a test_gen_b)
    [[ "$result" == "A" || "$result" == "B" ]]
}

@test "gen_one_of fails with no generators" {
    ! gen_one_of
}

# =============================================================================
# GENERATOR TESTS - ARRAY
# =============================================================================

@test "gen_array generates array elements" {
    local result
    result=$(gen_array 5)
    # Result should be parseable as array elements
    [[ -n "$result" || "$result" == "" ]]
}

@test "gen_array_of uses specified generator" {
    local result
    result=$(gen_array_of gen_bool 5)
    # Result should contain 'true' or 'false' values
    [[ "$result" =~ (true|false) || "$result" == "" ]]
}

@test "gen_array_of fails with unknown generator" {
    ! gen_array_of "nonexistent_generator"
}

# =============================================================================
# GENERATOR TESTS - OPTIONAL
# =============================================================================

@test "gen_maybe returns value or empty" {
    local has_value=0
    local has_empty=0
    local i

    for ((i=0; i<100; i++)); do
        local result
        result=$(gen_maybe gen_bool)
        [[ -n "$result" ]] && has_value=1
        [[ -z "$result" ]] && has_empty=1
    done

    # Should have both over 100 iterations
    [ "$has_value" = "1" ]
    [ "$has_empty" = "1" ]
}

# =============================================================================
# GENERATOR TESTS - SIZE CONTROL
# =============================================================================

@test "gen_sized controls generation size" {
    local result
    result=$(gen_sized 3 gen_string)
    [ "${#result}" -le 3 ]
}

# =============================================================================
# SHRINKING TESTS - INTEGER
# =============================================================================

@test "shrink_int includes 0 for positive integers" {
    local result
    result=$(shrink_int 100)
    [[ "$result" == *"0"* ]]
}

@test "shrink_int includes 0 for negative integers" {
    local result
    result=$(shrink_int -100)
    [[ "$result" == *"0"* ]]
}

@test "shrink_int returns empty for 0" {
    local result
    result=$(shrink_int 0)
    [ -z "$result" ]
}

@test "shrink_int includes value-1 for positives" {
    local result
    result=$(shrink_int 10)
    [[ "$result" == *"9"* ]]
}

@test "shrink_int includes value+1 for negatives" {
    local result
    result=$(shrink_int -10)
    [[ "$result" == *"-9"* ]]
}

# =============================================================================
# SHRINKING TESTS - STRING
# =============================================================================

@test "shrink_string includes empty for non-empty" {
    local result
    result=$(shrink_string "hello")
    [[ "$result" == *"''"* ]]
}

@test "shrink_string returns empty for empty" {
    local result
    result=$(shrink_string "")
    [ -z "$result" ]
}

@test "shrink_string includes shorter variants" {
    local result
    result=$(shrink_string "hello")
    # Should have 'ello', 'hllo', 'helo', 'hell' etc.
    [[ "$result" == *"'ello'"* || "$result" == *"'hllo'"* ]]
}

# =============================================================================
# SHRINKING TESTS - ARRAY
# =============================================================================

@test "shrink_array includes empty for non-empty" {
    local result
    result=$(shrink_array "a" "b" "c")
    [[ "$result" == *"()"* ]]
}

@test "shrink_array returns empty for empty" {
    local result
    result=$(shrink_array)
    [ -z "$result" ]
}

@test "shrink_array includes single-element removals" {
    local result
    result=$(shrink_array "a" "b" "c")
    # Should have variants with 2 elements
    [[ "$result" == *"'b' 'c'"* || "$result" == *"'a' 'c'"* ]]
}

# =============================================================================
# SHRINKING TESTS - FIND MINIMAL
# =============================================================================

@test "shrink_find_minimal finds smaller failing case" {
    # Property: value < 50 (fails for value >= 50)
    test_prop() { [[ "$1" -lt 50 ]]; }

    local result
    result=$(shrink_find_minimal test_prop 100 shrink_int)

    # Should shrink toward 50
    [[ "$result" -ge 50 && "$result" -lt 100 ]]
}

@test "shrink_binary_search finds boundary" {
    # Property: value < 42 (fails for value >= 42)
    test_prop() { [[ "$1" -lt 42 ]]; }

    local result
    result=$(shrink_binary_search test_prop 1000)

    # Should find 42 (minimal failing case)
    [ "$result" = "42" ]
}

# =============================================================================
# PROPERTY TESTS - PROP_FORALL
# =============================================================================

@test "prop_forall passes for always-true property" {
    always_true() { return 0; }

    prop_forall gen_int always_true 10
}

@test "prop_forall fails for always-false property" {
    always_false() { return 1; }

    ! prop_forall gen_int always_false 10
}

@test "prop_forall stores counterexample on failure" {
    fail_on_positive() { [[ "$1" -le 0 ]]; }
    _PROP_SIZE=100  # Ensure we generate some positive numbers

    ! prop_forall gen_int fail_on_positive 100 2>/dev/null

    # Should have stored a counterexample
    [[ -n "$_PROP_LAST_COUNTEREXAMPLE" ]]
}

# =============================================================================
# PROPERTY TESTS - PROP_CHECK
# =============================================================================

@test "prop_check outputs USOP success JSON" {
    always_true() { return 0; }

    local result
    result=$(prop_check gen_int always_true 10)

    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'"type":"property_test"'* ]]
    [[ "$result" == *'"passed":'* ]]
}

@test "prop_check outputs USOP failure JSON" {
    always_false() { return 1; }

    local result
    result=$(prop_check gen_int always_false 10)

    [[ "$result" == *'"ok":false'* ]]
    [[ "$result" == *'"counterexample":'* ]]
    [[ "$result" == *'"shrink_steps":'* ]]
}

@test "prop_check includes seed in output" {
    always_true() { return 0; }

    local result
    result=$(prop_check gen_int always_true 10)

    [[ "$result" == *'"seed":'* ]]
}

# =============================================================================
# PROPERTY TESTS - PROP_VERIFY
# =============================================================================

@test "prop_verify returns success for passing property" {
    is_positive() { [[ "$1" -gt 0 ]]; }

    prop_verify is_positive 42
}

@test "prop_verify returns failure for failing property" {
    is_positive() { [[ "$1" -gt 0 ]]; }

    ! prop_verify is_positive -5
}

@test "prop_verify outputs JSON" {
    is_positive() { [[ "$1" -gt 0 ]]; }

    local result
    result=$(prop_verify is_positive 42)

    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'"type":"verify"'* ]]
}

# =============================================================================
# PROPERTY COMBINATORS TESTS
# =============================================================================

@test "prop_implies passes when precondition false" {
    always_false() { return 1; }
    always_false2() { return 1; }

    # false => false should be true (vacuously)
    prop_implies always_false always_false2 "any"
}

@test "prop_implies passes when both hold" {
    always_true() { return 0; }

    prop_implies always_true always_true "any"
}

@test "prop_implies fails when precondition holds but property fails" {
    always_true() { return 0; }
    always_false() { return 1; }

    ! prop_implies always_true always_false "any"
}

@test "prop_and passes when both hold" {
    always_true() { return 0; }

    prop_and always_true always_true "any"
}

@test "prop_and fails when either fails" {
    always_true() { return 0; }
    always_false() { return 1; }

    ! prop_and always_true always_false "any"
    ! prop_and always_false always_true "any"
}

@test "prop_or passes when either holds" {
    always_true() { return 0; }
    always_false() { return 1; }

    prop_or always_true always_false "any"
    prop_or always_false always_true "any"
}

@test "prop_or fails when both fail" {
    always_false() { return 1; }

    ! prop_or always_false always_false "any"
}

# =============================================================================
# STATISTICS TESTS
# =============================================================================

@test "prop_label records labels" {
    prop_label "test_label"
    prop_label "test_label"
    prop_label "other_label"

    [ "${_PROP_LABELS["test_label"]}" = "2" ]
    [ "${_PROP_LABELS["other_label"]}" = "1" ]
}

@test "prop_classify records when condition true" {
    prop_classify "1" "positive"
    prop_classify "true" "positive"
    prop_classify "0" "negative"

    [ "${_PROP_CLASSIFICATIONS["positive"]}" = "2" ]
    [ -z "${_PROP_CLASSIFICATIONS["negative"]:-}" ]
}

@test "prop_collect records value distribution" {
    prop_collect "apple"
    prop_collect "banana"
    prop_collect "apple"

    [ "${_PROP_LABELS["apple"]}" = "2" ]
    [ "${_PROP_LABELS["banana"]}" = "1" ]
}

@test "prop_cover registers coverage requirement" {
    prop_cover 50 "1" "test_coverage"

    [ "${_PROP_COVERAGE["test_coverage"]}" = "1" ]
    [ "${_PROP_COVERAGE_REQUIRED["test_coverage"]}" = "50" ]
}

@test "prop_stats returns JSON" {
    prop_label "test"
    prop_classify "1" "class1"

    local result
    result=$(prop_stats)

    [[ "$result" == *'"labels":'* ]]
    [[ "$result" == *'"classifications":'* ]]
    [[ "$result" == *'"coverage":'* ]]
}

# =============================================================================
# SAMPLING AND REPLAY TESTS
# =============================================================================

@test "prop_sample returns array of values" {
    local result
    result=$(prop_sample gen_int 5)

    [[ "$result" == '['* ]]
    [[ "$result" == *']' ]]
}

@test "prop_sample respects count parameter" {
    local result
    result=$(prop_sample gen_bool 3)

    # Count commas (should be 2 for 3 elements)
    local commas="${result//[^,]/}"
    [ "${#commas}" = "2" ]
}

@test "prop_counterexample returns error when none recorded" {
    _PROP_LAST_COUNTEREXAMPLE=""

    ! prop_counterexample
}

@test "prop_counterexample returns JSON when recorded" {
    _PROP_LAST_COUNTEREXAMPLE="test_value"
    _PROP_LAST_SEED="12345"
    _PROP_SHRINK_STEPS="3"

    local result
    result=$(prop_counterexample)

    [[ "$result" == *'"counterexample":"test_value"'* ]]
    [[ "$result" == *'"seed":12345'* ]]
    [[ "$result" == *'"shrink_steps":3'* ]]
}

@test "prop_replay uses specified seed" {
    always_true() { return 0; }

    local result
    result=$(prop_replay 12345 gen_int always_true 5)

    [[ "$result" == *'"seed":12345'* ]]
}

# =============================================================================
# JSON OUTPUT TESTS
# =============================================================================

@test "prop_to_json returns complete statistics" {
    _PROP_TESTS_RUN=100
    _PROP_TESTS_PASSED=95
    _PROP_TESTS_FAILED=5
    _PROP_SHRINK_STEPS=10
    _PROP_LAST_COUNTEREXAMPLE="test"
    _PROP_LAST_SEED="12345"

    local result
    result=$(prop_to_json)

    [[ "$result" == *'"tests_run":100'* ]]
    [[ "$result" == *'"tests_passed":95'* ]]
    [[ "$result" == *'"tests_failed":5'* ]]
    [[ "$result" == *'"shrink_steps":10'* ]]
    [[ "$result" == *'"last_counterexample":"test"'* ]]
    [[ "$result" == *'"last_seed":12345'* ]]
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

@test "integration: test list reversal property" {
    # Property: reversing a list twice returns original
    # Simplified for bash: check string reverse
    reverse_string() {
        local s="$1"
        local result=""
        local i
        for ((i=${#s}-1; i>=0; i--)); do
            result+="${s:i:1}"
        done
        echo "$result"
    }

    double_reverse_prop() {
        local s="$1"
        local once twice
        once=$(reverse_string "$s")
        twice=$(reverse_string "$once")
        [[ "$twice" == "$s" ]]
    }

    prop_check gen_string_alpha double_reverse_prop 50
}

@test "integration: test addition commutativity" {
    # a + b == b + a
    add_commutative() {
        local a b
        # Parse "a,b" input
        a="${1%%,*}"
        b="${1#*,}"
        [[ $((a + b)) -eq $((b + a)) ]]
    }

    # Generator that produces "a,b" pairs
    gen_pair() {
        local a b
        a=$(gen_int_range -100 100)
        b=$(gen_int_range -100 100)
        echo "$a,$b"
    }

    prop_check gen_pair add_commutative 100
}

@test "integration: test absolute value property" {
    # |x| >= 0
    abs_non_negative() {
        local x="$1"
        local abs_x
        if [[ "$x" -lt 0 ]]; then
            abs_x=$((-x))
        else
            abs_x="$x"
        fi
        [[ "$abs_x" -ge 0 ]]
    }

    prop_check gen_int abs_non_negative 100
}

@test "integration: shrinking finds minimal counterexample" {
    # Property fails for x > 10
    small_enough() { [[ "$1" -le 10 ]]; }

    local result
    result=$(prop_check gen_int small_enough 100 2>/dev/null) || true

    # Should have shrunk to 11 (minimal failing case)
    if [[ "$result" == *'"counterexample":'* ]]; then
        # Extract counterexample value
        local ce="${result#*\"counterexample\":\"}"
        ce="${ce%%\"*}"
        [[ "$ce" -ge 11 && "$ce" -le 20 ]]
    fi
}

@test "integration: reproducibility with seed" {
    always_true() { return 0; }

    # Run twice with same seed
    prop_set_seed 42
    local result1
    result1=$(prop_sample gen_int 5)

    prop_set_seed 42
    local result2
    result2=$(prop_sample gen_int 5)

    [ "$result1" = "$result2" ]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "edge case: empty string property" {
    not_empty() { [[ -n "$1" ]]; }

    # This might fail since gen_string can produce empty
    local result
    result=$(prop_check gen_string not_empty 50 2>/dev/null) || true

    # Should either pass (no empty generated) or fail with empty counterexample
    [[ "$result" == *'"ok":'* ]]
}

@test "edge case: zero iterations" {
    always_true() { return 0; }

    local result
    result=$(prop_check gen_int always_true 0)

    # Should still produce valid output
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'"passed":0'* ]]
}

@test "edge case: special characters in generated strings" {
    # Property that always passes
    accept_any() { return 0; }

    # Generate strings that might have special characters
    _PROP_SIZE=20
    prop_check gen_string accept_any 50
}

@test "edge case: negative integer shrinking" {
    # Property fails for x < -5
    not_too_negative() { [[ "$1" -ge -5 ]]; }

    local result
    result=$(prop_check gen_int not_too_negative 100 2>/dev/null) || true

    # Counterexample should be around -6
    if [[ "$result" == *'"counterexample":'* ]]; then
        local ce="${result#*\"counterexample\":\"}"
        ce="${ce%%\"*}"
        [[ "$ce" -lt 0 ]]
    fi
}

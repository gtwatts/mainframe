#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Pure Array Library Tests
# =============================================================================

load 'test_helper'

setup() {
    source_lib "pure-array"
}

# =============================================================================
# BASIC OPERATIONS TESTS
# =============================================================================

@test "array_length returns correct count" {
    result=$(array_length "a" "b" "c")
    [ "$result" = "3" ]
}

@test "array_first returns first element" {
    result=$(array_first "a" "b" "c")
    [ "$result" = "a" ]
}

@test "array_last returns last element" {
    result=$(array_last "a" "b" "c")
    [ "$result" = "c" ]
}

@test "array_get returns element at index" {
    result=$(array_get 1 "a" "b" "c")
    [ "$result" = "b" ]
}

# =============================================================================
# SEARCH TESTS
# =============================================================================

@test "array_contains finds existing element" {
    array_contains "b" "a" "b" "c"
}

@test "array_contains fails for missing element" {
    ! array_contains "x" "a" "b" "c"
}

@test "array_index_of returns correct index" {
    result=$(array_index_of "b" "a" "b" "c")
    [ "$result" = "1" ]
}

@test "array_index_of returns -1 for missing element" {
    result=$(array_index_of "x" "a" "b" "c")
    [ "$result" = "-1" ]
}

@test "array_count counts occurrences" {
    result=$(array_count "a" "a" "b" "a" "c" "a")
    [ "$result" = "3" ]
}

@test "array_empty returns true for empty" {
    array_empty
}

@test "array_empty returns false for non-empty" {
    ! array_empty "a" "b"
}

# =============================================================================
# TRANSFORMATION TESTS
# =============================================================================

@test "array_reverse reverses order" {
    result=$(array_reverse "a" "b" "c" | tr '\n' ' ' | sed 's/ $//')
    [ "$result" = "c b a" ]
}

@test "array_unique removes duplicates" {
    result=$(array_unique "a" "b" "a" "c" "b" | sort | tr '\n' ' ' | sed 's/ $//')
    [ "$result" = "a b c" ]
}

@test "array_sort sorts lexicographically" {
    result=$(array_sort "c" "a" "b" | tr '\n' ' ' | sed 's/ $//')
    [ "$result" = "a b c" ]
}

@test "array_sort_num sorts numerically" {
    result=$(array_sort_num "10" "2" "1" "20" | tr '\n' ' ' | sed 's/ $//')
    [ "$result" = "1 2 10 20" ]
}

# =============================================================================
# SELECTION TESTS
# =============================================================================

@test "array_random returns an element" {
    result=$(array_random "a" "b" "c")
    [[ "$result" =~ ^[abc]$ ]]
}

@test "array_filter matches pattern" {
    result=$(array_filter '*or*' "apple" "orange" "word" "banana" | tr '\n' ' ' | sed 's/ $//')
    [ "$result" = "orange word" ]
}

@test "array_reject excludes pattern" {
    result=$(array_reject '*or*' "apple" "orange" "banana" | tr '\n' ' ' | sed 's/ $//')
    [ "$result" = "apple banana" ]
}

# =============================================================================
# JOINING TESTS
# =============================================================================

@test "array_join joins with delimiter" {
    result=$(array_join "," "a" "b" "c")
    [ "$result" = "a,b,c" ]
}

@test "array_join with empty delimiter" {
    result=$(array_join "" "a" "b" "c")
    [ "$result" = "abc" ]
}

# =============================================================================
# COMPARISON TESTS
# =============================================================================

@test "array_intersect finds common elements" {
    arr1=("a" "b" "c")
    arr2=("b" "c" "d")
    result=$(array_intersect arr1 arr2 | sort | tr '\n' ' ' | sed 's/ $//')
    [ "$result" = "b c" ]
}

@test "array_diff finds elements only in first" {
    arr1=("a" "b" "c")
    arr2=("b" "c" "d")
    result=$(array_diff arr1 arr2)
    [ "$result" = "a" ]
}

@test "array_union combines unique elements" {
    arr1=("a" "b")
    arr2=("b" "c")
    result=$(array_union arr1 arr2 | sort | tr '\n' ' ' | sed 's/ $//')
    [ "$result" = "a b c" ]
}

# =============================================================================
# AGGREGATION TESTS
# =============================================================================

@test "array_sum adds numbers" {
    result=$(array_sum 1 2 3 4 5)
    [ "$result" = "15" ]
}

@test "array_min finds minimum" {
    result=$(array_min 5 2 8 1 9)
    [ "$result" = "1" ]
}

@test "array_max finds maximum" {
    result=$(array_max 5 2 8 1 9)
    [ "$result" = "9" ]
}

@test "array_avg calculates average" {
    result=$(array_avg 2 4 6 8 10)
    [ "$result" = "6" ]
}

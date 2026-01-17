#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Pure String Library Tests
# =============================================================================

load 'test_helper'

setup() {
    source_lib "pure-string"
}

# =============================================================================
# WHITESPACE TESTS
# =============================================================================

@test "trim_string removes leading whitespace" {
    result=$(trim_string "  hello")
    [ "$result" = "hello" ]
}

@test "trim_string removes trailing whitespace" {
    result=$(trim_string "hello  ")
    [ "$result" = "hello" ]
}

@test "trim_string removes both leading and trailing whitespace" {
    result=$(trim_string "  hello world  ")
    [ "$result" = "hello world" ]
}

@test "trim_string preserves internal whitespace" {
    result=$(trim_string "  hello   world  ")
    [ "$result" = "hello   world" ]
}

@test "trim_left removes leading whitespace only" {
    result=$(trim_left "  hello  ")
    [ "$result" = "hello  " ]
}

@test "trim_right removes trailing whitespace only" {
    result=$(trim_right "  hello  ")
    [ "$result" = "  hello" ]
}

# =============================================================================
# CASE CONVERSION TESTS
# =============================================================================

@test "to_lower converts to lowercase" {
    result=$(to_lower "HELLO")
    [ "$result" = "hello" ]
}

@test "to_upper converts to uppercase" {
    result=$(to_upper "hello")
    [ "$result" = "HELLO" ]
}

@test "capitalize capitalizes first letter" {
    result=$(capitalize "hello")
    [ "$result" = "Hello" ]
}

@test "reverse_case reverses case" {
    result=$(reverse_case "HeLLo")
    [ "$result" = "hEllO" ]
}

# =============================================================================
# PATTERN REMOVAL TESTS
# =============================================================================

@test "strip_all removes all occurrences" {
    result=$(strip_all "hello" "l")
    [ "$result" = "heo" ]
}

@test "strip_first removes first occurrence" {
    result=$(strip_first "hello" "l")
    [ "$result" = "helo" ]
}

@test "lstrip removes from start" {
    result=$(lstrip "hello" "hel")
    [ "$result" = "lo" ]
}

@test "rstrip removes from end" {
    result=$(rstrip "hello" "lo")
    [ "$result" = "hel" ]
}

# =============================================================================
# REPLACEMENT TESTS
# =============================================================================

@test "replace_first replaces first occurrence" {
    result=$(replace_first "hello" "l" "L")
    [ "$result" = "heLlo" ]
}

@test "replace_all replaces all occurrences" {
    result=$(replace_all "hello" "l" "L")
    [ "$result" = "heLLo" ]
}

# =============================================================================
# SUBSTRING TESTS
# =============================================================================

@test "substring extracts substring" {
    result=$(substring "hello" 1 3)
    [ "$result" = "ell" ]
}

@test "strlen returns string length" {
    result=$(strlen "hello")
    [ "$result" = "5" ]
}

@test "char_at returns character at index" {
    result=$(char_at "hello" 2)
    [ "$result" = "l" ]
}

# =============================================================================
# CHECK TESTS
# =============================================================================

@test "contains returns true when substring present" {
    contains "hello world" "world"
}

@test "contains returns false when substring absent" {
    ! contains "hello world" "xyz"
}

@test "starts_with returns true for matching prefix" {
    starts_with "hello" "hel"
}

@test "starts_with returns false for non-matching prefix" {
    ! starts_with "hello" "xyz"
}

@test "ends_with returns true for matching suffix" {
    ends_with "hello" "lo"
}

@test "ends_with returns false for non-matching suffix" {
    ! ends_with "hello" "xyz"
}

@test "is_empty returns true for empty string" {
    is_empty ""
}

@test "is_empty returns false for non-empty string" {
    ! is_empty "hello"
}

@test "matches returns true for matching regex" {
    matches "hello123" '^[a-z]+[0-9]+$'
}

# =============================================================================
# URL ENCODING TESTS
# =============================================================================

@test "urlencode encodes space" {
    result=$(urlencode "hello world")
    [ "$result" = "hello%20world" ]
}

@test "urldecode decodes percent encoding" {
    result=$(urldecode "hello%20world")
    [ "$result" = "hello world" ]
}

# =============================================================================
# GENERATION TESTS
# =============================================================================

@test "repeat_string repeats correctly" {
    result=$(repeat_string "-" 5)
    [ "$result" = "-----" ]
}

@test "pad_right pads string on right" {
    result=$(pad_right "hi" 5 ".")
    [ "$result" = "hi..." ]
}

@test "pad_left pads string on left" {
    result=$(pad_left "hi" 5 ".")
    [ "$result" = "...hi" ]
}

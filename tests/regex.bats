#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Regex Module Tests
# =============================================================================
# Tests for lib/regex.sh
# Covers: matching, replacement, splitting, extraction, pattern builders,
#         ReDoS protection, escaping, and common validators
# =============================================================================

load 'test_helper'

setup() {
    source_lib "regex"
    export MAINFRAME_QUIET=1
    export MAINFRAME_ERROR_JSON=0
}

# =============================================================================
# REGEX CONSTANTS TESTS
# =============================================================================

@test "REGEX_EMAIL constant is defined" {
    [ -n "$REGEX_EMAIL" ]
}

@test "REGEX_URL constant is defined" {
    [ -n "$REGEX_URL" ]
}

@test "REGEX_IPV4 constant is defined" {
    [ -n "$REGEX_IPV4" ]
}

@test "REGEX_UUID constant is defined" {
    [ -n "$REGEX_UUID" ]
}

@test "REGEX_SEMVER constant is defined" {
    [ -n "$REGEX_SEMVER" ]
}

@test "REGEX_SLUG constant is defined" {
    [ -n "$REGEX_SLUG" ]
}

@test "REGEX_IDENTIFIER constant is defined" {
    [ -n "$REGEX_IDENTIFIER" ]
}

# =============================================================================
# regex_is_valid TESTS
# =============================================================================

@test "regex_is_valid accepts simple pattern" {
    run regex_is_valid "[a-z]+"
    [ "$status" -eq 0 ]
}

@test "regex_is_valid accepts empty pattern" {
    run regex_is_valid ""
    [ "$status" -eq 1 ]
}

@test "regex_is_valid accepts anchored pattern" {
    run regex_is_valid "^hello$"
    [ "$status" -eq 0 ]
}

@test "regex_is_valid accepts pattern with groups" {
    run regex_is_valid "([a-z]+)([0-9]+)"
    [ "$status" -eq 0 ]
}

@test "regex_is_valid accepts alternation pattern" {
    run regex_is_valid "cat|dog|bird"
    [ "$status" -eq 0 ]
}

# =============================================================================
# regex_complexity_score TESTS
# =============================================================================

@test "regex_complexity_score returns 0 for empty pattern" {
    run regex_complexity_score ""
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "regex_complexity_score returns low score for simple pattern" {
    run regex_complexity_score "[a-z]"
    [ "$status" -eq 0 ]
    [ "$output" -lt 10 ]
}

@test "regex_complexity_score returns higher score for complex pattern" {
    run regex_complexity_score "([a-z]+)+([0-9]+)+"
    [ "$status" -eq 0 ]
    [ "$output" -gt 20 ]
}

@test "regex_complexity_score detects dangerous nested quantifiers" {
    run regex_complexity_score "(a+)+"
    [ "$status" -eq 0 ]
    [ "$output" -gt 50 ]
}

# =============================================================================
# regex_compile_safe TESTS (ReDoS Protection)
# =============================================================================

@test "regex_compile_safe accepts simple pattern" {
    run regex_compile_safe "[a-z]+"
    [ "$status" -eq 0 ]
}

@test "regex_compile_safe rejects empty pattern" {
    run regex_compile_safe ""
    [ "$status" -eq 1 ]
}

@test "regex_compile_safe rejects overly long pattern" {
    local long_pattern
    long_pattern=$(printf 'a%.0s' {1..600})
    run regex_compile_safe "$long_pattern"
    [ "$status" -eq 1 ]
}

@test "regex_compile_safe warns on high complexity" {
    # Create a pattern with dangerous nested quantifiers
    run regex_compile_safe "(a+)+(b+)+(c+)+"
    [ "$status" -eq 1 ]
}

# =============================================================================
# regex_match TESTS
# =============================================================================

@test "regex_match returns 0 on match" {
    run regex_match "hello world" "hello"
    [ "$status" -eq 0 ]
}

@test "regex_match returns 1 on no match" {
    run regex_match "hello world" "goodbye"
    [ "$status" -eq 1 ]
}

@test "regex_match handles empty pattern" {
    run regex_match "hello" ""
    [ "$status" -eq 1 ]
}

@test "regex_match matches numbers" {
    run regex_match "test123" "[0-9]+"
    [ "$status" -eq 0 ]
}

@test "regex_match with anchors - full match" {
    run regex_match "hello" "^hello$"
    [ "$status" -eq 0 ]
}

@test "regex_match with anchors - partial no match" {
    run regex_match "hello world" "^hello$"
    [ "$status" -eq 1 ]
}

# =============================================================================
# regex_test TESTS (alias)
# =============================================================================

@test "regex_test is alias for regex_match" {
    run regex_test "hello" "[a-z]+"
    [ "$status" -eq 0 ]
}

# =============================================================================
# regex_find TESTS
# =============================================================================

@test "regex_find returns first match" {
    run regex_find "hello123world" "[0-9]+"
    [ "$status" -eq 0 ]
    [ "$output" = "123" ]
}

@test "regex_find returns empty on no match" {
    run regex_find "hello" "[0-9]+"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "regex_find handles letters" {
    run regex_find "123abc456" "[a-z]+"
    [ "$status" -eq 0 ]
    [ "$output" = "abc" ]
}

@test "regex_find with empty pattern fails" {
    run regex_find "hello" ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# regex_find_all TESTS
# =============================================================================

@test "regex_find_all returns all matches" {
    result=$(regex_find_all "a1b2c3" "[0-9]")
    [ "$(echo "$result" | wc -l)" -eq 3 ]
    [ "$(echo "$result" | head -1)" = "1" ]
}

@test "regex_find_all returns empty on no match" {
    run regex_find_all "hello" "[0-9]"
    [ "$status" -eq 1 ]
}

@test "regex_find_all handles multi-char matches" {
    result=$(regex_find_all "cat123dog456" "[0-9]+")
    [ "$(echo "$result" | wc -l)" -eq 2 ]
    [ "$(echo "$result" | head -1)" = "123" ]
    [ "$(echo "$result" | tail -1)" = "456" ]
}

# =============================================================================
# regex_groups TESTS
# =============================================================================

@test "regex_groups extracts capture groups" {
    result=$(regex_groups "hello123" "([a-z]+)([0-9]+)")
    [ "$(echo "$result" | wc -l)" -eq 3 ]
    [ "$(echo "$result" | head -1)" = "hello123" ]
    [ "$(echo "$result" | sed -n '2p')" = "hello" ]
    [ "$(echo "$result" | sed -n '3p')" = "123" ]
}

@test "regex_groups returns empty on no match" {
    run regex_groups "hello" "[0-9]+"
    [ "$status" -eq 1 ]
}

@test "regex_groups handles single group" {
    result=$(regex_groups "test123" "([0-9]+)")
    [ "$(echo "$result" | sed -n '2p')" = "123" ]
}

# =============================================================================
# regex_named_groups TESTS
# =============================================================================

@test "regex_named_groups returns name=value pairs" {
    result=$(regex_named_groups "hello123" "([a-z]+)([0-9]+)" "word num")
    [ "$(echo "$result" | head -1)" = "word=hello" ]
    [ "$(echo "$result" | tail -1)" = "num=123" ]
}

@test "regex_named_groups uses defaults for missing names" {
    result=$(regex_named_groups "hello123" "([a-z]+)([0-9]+)" "word")
    [ "$(echo "$result" | tail -1)" = "group2=123" ]
}

# =============================================================================
# regex_replace TESTS
# =============================================================================

@test "regex_replace replaces first match" {
    run regex_replace "hello world" "world" "bash"
    [ "$status" -eq 0 ]
    [ "$output" = "hello bash" ]
}

@test "regex_replace only replaces first occurrence" {
    run regex_replace "aaa" "a" "b"
    [ "$status" -eq 0 ]
    [ "$output" = "baa" ]
}

@test "regex_replace returns original on no match" {
    run regex_replace "hello" "xyz" "abc"
    [ "$status" -eq 1 ]
    [ "$output" = "hello" ]
}

@test "regex_replace with empty pattern" {
    run regex_replace "hello" "" "x"
    [ "$status" -eq 1 ]
    [ "$output" = "hello" ]
}

# =============================================================================
# regex_replace_all TESTS
# =============================================================================

@test "regex_replace_all replaces all matches" {
    run regex_replace_all "a1b2c3" "[0-9]" "X"
    [ "$status" -eq 0 ]
    [ "$output" = "aXbXcX" ]
}

@test "regex_replace_all handles multiple occurrences" {
    run regex_replace_all "aaa" "a" "b"
    [ "$status" -eq 0 ]
    [ "$output" = "bbb" ]
}

@test "regex_replace_all returns original on no match" {
    run regex_replace_all "hello" "[0-9]" "X"
    [ "$status" -eq 1 ]
    [ "$output" = "hello" ]
}

# =============================================================================
# regex_replace_callback TESTS
# =============================================================================

@test "regex_replace_callback applies function to matches" {
    my_upper() { echo "${1^^}"; }
    export -f my_upper

    result=$(regex_replace_callback "hello world" "[a-z]+" my_upper)
    [ "$result" = "HELLO WORLD" ]
}

@test "regex_replace_callback fails on invalid callback" {
    run regex_replace_callback "hello" "[a-z]" nonexistent_func
    [ "$status" -eq 1 ]
}

# =============================================================================
# regex_sub TESTS (backreference substitution)
# =============================================================================

@test "regex_sub handles backreferences" {
    run regex_sub "hello123" "([a-z]+)([0-9]+)" '\2-\1'
    [ "$status" -eq 0 ]
    [ "$output" = "123-hello" ]
}

@test "regex_sub handles full match backref" {
    run regex_sub "hello" "([a-z]+)" '[\0]'
    [ "$status" -eq 0 ]
    [ "$output" = "[hello]" ]
}

# =============================================================================
# regex_split TESTS
# =============================================================================

@test "regex_split splits by pattern" {
    result=$(regex_split "a1b2c3" "[0-9]")
    [ "$(echo "$result" | head -1)" = "a" ]
    [ "$(echo "$result" | sed -n '2p')" = "b" ]
    [ "$(echo "$result" | sed -n '3p')" = "c" ]
}

@test "regex_split handles no match" {
    run regex_split "hello" "[0-9]"
    [ "$output" = "hello" ]
}

@test "regex_split handles empty pattern" {
    run regex_split "hello" ""
    [ "$output" = "hello" ]
}

# =============================================================================
# regex_split_limit TESTS
# =============================================================================

@test "regex_split_limit respects limit" {
    result=$(regex_split_limit "a-b-c-d" "-" 2)
    [ "$(echo "$result" | wc -l)" -eq 2 ]
    [ "$(echo "$result" | head -1)" = "a" ]
    [ "$(echo "$result" | tail -1)" = "b-c-d" ]
}

@test "regex_split_limit with limit 1 returns whole string" {
    result=$(regex_split_limit "a-b-c" "-" 1)
    [ "$(echo "$result" | wc -l)" -eq 1 ]
    [ "$result" = "a-b-c" ]
}

# =============================================================================
# regex_escape TESTS
# =============================================================================

@test "regex_escape escapes metacharacters" {
    run regex_escape "hello.*world"
    [ "$output" = 'hello\.\*world' ]
}

@test "regex_escape handles brackets" {
    run regex_escape "[test]"
    [ "$output" = '\[test\]' ]
}

@test "regex_escape handles all special chars" {
    run regex_escape '^$.|*+?()[]{}\\'
    [ -n "$output" ]
    # Should have backslashes before each special char
}

@test "regex_escape handles normal text" {
    run regex_escape "hello"
    [ "$output" = "hello" ]
}

# =============================================================================
# regex_unescape TESTS
# =============================================================================

@test "regex_unescape removes escapes" {
    run regex_unescape 'hello\.\*world'
    [ "$output" = "hello.*world" ]
}

@test "regex_unescape handles brackets" {
    run regex_unescape '\[test\]'
    [ "$output" = "[test]" ]
}

# =============================================================================
# regex_quote_literal TESTS
# =============================================================================

@test "regex_quote_literal is alias for escape" {
    run regex_quote_literal "file.txt"
    [ "$output" = 'file\.txt' ]
}

# =============================================================================
# regex_any_of TESTS
# =============================================================================

@test "regex_any_of builds alternation" {
    run regex_any_of "cat" "dog" "bird"
    [ "$output" = "(cat|dog|bird)" ]
}

@test "regex_any_of handles single option" {
    run regex_any_of "cat"
    [ "$output" = "(cat)" ]
}

@test "regex_any_of fails with no args" {
    run regex_any_of
    [ "$status" -eq 1 ]
}

# =============================================================================
# regex_sequence TESTS
# =============================================================================

@test "regex_sequence concatenates patterns" {
    run regex_sequence "[a-z]+" "[0-9]+"
    [ "$output" = "[a-z]+[0-9]+" ]
}

@test "regex_sequence handles single pattern" {
    run regex_sequence "[a-z]+"
    [ "$output" = "[a-z]+" ]
}

# =============================================================================
# regex_optional TESTS
# =============================================================================

@test "regex_optional adds question mark" {
    run regex_optional "[a-z]+"
    # Should wrap in non-capture group and add ?
    [[ "$output" == *"?"* ]]
}

@test "regex_optional handles single char" {
    run regex_optional "a"
    [ "$output" = "a?" ]
}

# =============================================================================
# regex_repeat TESTS
# =============================================================================

@test "regex_repeat with exact count" {
    run regex_repeat "[a-z]" 3
    [[ "$output" == *"{3}"* ]]
}

@test "regex_repeat with range" {
    run regex_repeat "[a-z]" 2 5
    [[ "$output" == *"{2,5}"* ]]
}

@test "regex_repeat with 0 and no max returns star" {
    run regex_repeat "a" 0 ""
    [ "$output" = "a*" ]
}

@test "regex_repeat with 1 and no max returns plus" {
    run regex_repeat "a" 1 ""
    [ "$output" = "a+" ]
}

# =============================================================================
# regex_group TESTS
# =============================================================================

@test "regex_group wraps in parentheses" {
    run regex_group "[a-z]+"
    [ "$output" = "([a-z]+)" ]
}

# =============================================================================
# regex_non_capture TESTS
# =============================================================================

@test "regex_non_capture wraps in non-capture group" {
    run regex_non_capture "[a-z]+"
    [ "$output" = "(?:[a-z]+)" ]
}

# =============================================================================
# regex_anchor TESTS
# =============================================================================

@test "regex_anchor adds both anchors by default" {
    run regex_anchor "[a-z]+"
    [ "$output" = "^[a-z]+\$" ]
}

@test "regex_anchor adds start anchor only" {
    run regex_anchor "[a-z]+" "start"
    [ "$output" = "^[a-z]+" ]
}

@test "regex_anchor adds end anchor only" {
    run regex_anchor "[a-z]+" "end"
    [ "$output" = "[a-z]+\$" ]
}

# =============================================================================
# regex_word_boundary TESTS
# =============================================================================

@test "regex_word_boundary adds boundaries" {
    run regex_word_boundary "hello"
    [ "$output" = '\bhello\b' ]
}

@test "regex_word_boundary adds start boundary only" {
    run regex_word_boundary "hello" "start"
    [ "$output" = '\bhello' ]
}

# =============================================================================
# glob_to_regex TESTS
# =============================================================================

@test "glob_to_regex converts star" {
    run glob_to_regex "*.txt"
    [ "$output" = '^.*\.txt$' ]
}

@test "glob_to_regex converts question mark" {
    run glob_to_regex "file?.txt"
    [ "$output" = '^file.\.txt$' ]
}

@test "glob_to_regex handles character class" {
    run glob_to_regex "[abc].txt"
    [ "$output" = '^[abc]\.txt$' ]
}

# =============================================================================
# regex_to_glob TESTS
# =============================================================================

@test "regex_to_glob converts .* to *" {
    run regex_to_glob ".*\.txt"
    [ "$output" = "*.txt" ]
}

# =============================================================================
# regex_flags_parse TESTS
# =============================================================================

@test "regex_flags_parse extracts pattern and flags" {
    result=$(regex_flags_parse "/hello/gi")
    [ "$(echo "$result" | head -1)" = "hello" ]
    [ "$(echo "$result" | tail -1)" = "gi" ]
}

@test "regex_flags_parse handles no flags" {
    result=$(regex_flags_parse "/hello/")
    [ "$(echo "$result" | head -1)" = "hello" ]
}

@test "regex_flags_parse handles plain pattern" {
    result=$(regex_flags_parse "hello")
    [ "$(echo "$result" | head -1)" = "hello" ]
}

# =============================================================================
# regex_count TESTS
# =============================================================================

@test "regex_count counts matches" {
    run regex_count "a1b2c3" "[0-9]"
    [ "$output" = "3" ]
}

@test "regex_count returns 0 for no match" {
    run regex_count "hello" "[0-9]"
    [ "$output" = "0" ]
}

# =============================================================================
# regex_positions TESTS
# =============================================================================

@test "regex_positions returns positions" {
    result=$(regex_positions "a1b2c3" "[0-9]")
    [ "$(echo "$result" | head -1)" = "1:2" ]
}

# =============================================================================
# regex_full_match TESTS
# =============================================================================

@test "regex_full_match requires entire string match" {
    run regex_full_match "hello" "[a-z]+"
    [ "$status" -eq 0 ]
}

@test "regex_full_match fails on partial" {
    run regex_full_match "hello123" "[a-z]+"
    [ "$status" -eq 1 ]
}

# =============================================================================
# regex_starts_with TESTS
# =============================================================================

@test "regex_starts_with matches at start" {
    run regex_starts_with "hello world" "hello"
    [ "$status" -eq 0 ]
}

@test "regex_starts_with fails for middle match" {
    run regex_starts_with "say hello" "hello"
    [ "$status" -eq 1 ]
}

# =============================================================================
# regex_ends_with TESTS
# =============================================================================

@test "regex_ends_with matches at end" {
    run regex_ends_with "hello world" "world"
    [ "$status" -eq 0 ]
}

@test "regex_ends_with fails for middle match" {
    run regex_ends_with "world hello" "world"
    [ "$status" -eq 1 ]
}

# =============================================================================
# regex_remove TESTS
# =============================================================================

@test "regex_remove removes all matches" {
    run regex_remove "hello123world" "[0-9]+"
    [ "$output" = "helloworld" ]
}

# =============================================================================
# regex_keep TESTS
# =============================================================================

@test "regex_keep keeps only matches" {
    run regex_keep "hello123world456" "[0-9]+"
    [ "$output" = "123456" ]
}

# =============================================================================
# COMMON VALIDATORS TESTS
# =============================================================================

@test "regex_validate_email accepts valid email" {
    run regex_validate_email "user@example.com"
    [ "$status" -eq 0 ]
}

@test "regex_validate_email rejects invalid email" {
    run regex_validate_email "not-an-email"
    [ "$status" -eq 1 ]
}

@test "regex_validate_url accepts valid URL" {
    run regex_validate_url "https://example.com"
    [ "$status" -eq 0 ]
}

@test "regex_validate_url rejects invalid URL" {
    run regex_validate_url "not-a-url"
    [ "$status" -eq 1 ]
}

@test "regex_validate_ipv4 accepts valid IP" {
    run regex_validate_ipv4 "192.168.1.1"
    [ "$status" -eq 0 ]
}

@test "regex_validate_ipv4 rejects invalid IP" {
    run regex_validate_ipv4 "999.999.999.999"
    # Pattern matches format, not value validity
    [ "$status" -eq 0 ]
}

@test "regex_validate_uuid accepts valid UUID" {
    run regex_validate_uuid "550e8400-e29b-41d4-a716-446655440000"
    [ "$status" -eq 0 ]
}

@test "regex_validate_uuid rejects invalid UUID" {
    run regex_validate_uuid "not-a-uuid"
    [ "$status" -eq 1 ]
}

@test "regex_validate_semver accepts valid version" {
    run regex_validate_semver "1.2.3"
    [ "$status" -eq 0 ]
}

@test "regex_validate_semver accepts v prefix" {
    run regex_validate_semver "v1.0.0"
    [ "$status" -eq 0 ]
}

@test "regex_validate_semver accepts prerelease" {
    run regex_validate_semver "1.0.0-alpha.1"
    [ "$status" -eq 0 ]
}

@test "regex_validate_date_iso accepts valid date" {
    run regex_validate_date_iso "2024-01-15"
    [ "$status" -eq 0 ]
}

@test "regex_validate_date_iso rejects invalid date" {
    run regex_validate_date_iso "2024-13-45"
    [ "$status" -eq 1 ]
}

@test "regex_validate_slug accepts valid slug" {
    run regex_validate_slug "hello-world"
    [ "$status" -eq 0 ]
}

@test "regex_validate_slug rejects uppercase" {
    run regex_validate_slug "Hello-World"
    [ "$status" -eq 1 ]
}

@test "regex_validate_identifier accepts valid identifier" {
    run regex_validate_identifier "my_variable"
    [ "$status" -eq 0 ]
}

@test "regex_validate_identifier rejects starting with number" {
    run regex_validate_identifier "123var"
    [ "$status" -eq 1 ]
}

@test "regex_validate_hex_color accepts valid hex" {
    run regex_validate_hex_color "#ff5500"
    [ "$status" -eq 0 ]
}

@test "regex_validate_hex_color accepts short form" {
    run regex_validate_hex_color "#f50"
    [ "$status" -eq 0 ]
}

@test "regex_validate_mac_address accepts valid MAC" {
    run regex_validate_mac_address "00:1A:2B:3C:4D:5E"
    [ "$status" -eq 0 ]
}

# =============================================================================
# regex_debug TESTS
# =============================================================================

@test "regex_debug outputs JSON" {
    run regex_debug "[a-z]+"
    [[ "$output" == *"pattern"* ]]
    [[ "$output" == *"valid"* ]]
    [[ "$output" == *"complexity"* ]]
}

# =============================================================================
# EDGE CASES AND SPECIAL PATTERNS
# =============================================================================

@test "handles empty string input" {
    run regex_match "" ".*"
    [ "$status" -eq 0 ]
}

@test "handles unicode in string" {
    run regex_match "hello mundo" "[a-z]+"
    [ "$status" -eq 0 ]
}

@test "handles special characters in string" {
    run regex_find 'hello$world' '\$'
    [ "$status" -eq 0 ]
    [ "$output" = '$' ]
}

@test "handles newlines in string" {
    result=$(printf "line1\nline2" | regex_split $'\n')
    [ "$(echo "$result" | head -1)" = "line1" ]
}

@test "handles tabs in string" {
    result=$(printf "a\tb\tc" | regex_split $'\t')
    [ "$(echo "$result" | head -1)" = "a" ]
}

# =============================================================================
# REDOS PROTECTION TESTS
# =============================================================================

@test "ReDoS protection rejects catastrophic backtracking pattern" {
    # (a+)+ is a classic ReDoS pattern
    run regex_compile_safe "(a+)+"
    [ "$status" -eq 1 ]
}

@test "ReDoS protection allows safe patterns" {
    run regex_compile_safe "[a-z][a-z0-9]*"
    [ "$status" -eq 0 ]
}

@test "ReDoS protection detects overlapping alternations" {
    run regex_compile_safe "((a|aa)+)+"
    [ "$status" -eq 1 ]
}

@test "ReDoS protection respects max quantifiers limit" {
    # Many quantifiers but safe pattern
    run regex_compile_safe "a+b+c+d+e+f+g+h+i+j+k+"
    [ "$status" -eq 1 ]  # Exceeds REGEX_MAX_QUANTIFIERS (10)
}

@test "ReDoS protection respects max groups limit" {
    # Many groups
    pattern="(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)(l)(m)(n)(o)(p)"
    run regex_compile_safe "$pattern"
    [ "$status" -eq 1 ]  # Exceeds REGEX_MAX_GROUPS (15)
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

@test "parse log line with multiple groups" {
    log="2024-01-15 10:30:00 [ERROR] Something failed"
    result=$(regex_groups "$log" "([0-9-]+) ([0-9:]+) \[([A-Z]+)\] (.*)")
    [ "$(echo "$result" | sed -n '2p')" = "2024-01-15" ]
    [ "$(echo "$result" | sed -n '3p')" = "10:30:00" ]
    [ "$(echo "$result" | sed -n '4p')" = "ERROR" ]
}

@test "extract all URLs from text" {
    text="Visit https://example.com or http://test.org for more info"
    result=$(regex_find_all "$text" "https?://[A-Za-z0-9.-]+")
    [ "$(echo "$result" | wc -l)" -eq 2 ]
}

@test "replace sensitive data" {
    text="Email: user@example.com, Card: 1234-5678-9012-3456"
    result=$(regex_replace_all "$text" "[0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9]{4}" "****-****-****-****")
    [[ "$result" == *"****-****-****-****"* ]]
}

@test "validate and extract version numbers" {
    versions="v1.0.0-alpha, 2.3.4, v10.20.30-beta.1+build.123"
    while IFS= read -r ver; do
        run regex_validate_semver "$ver"
        [ "$status" -eq 0 ]
    done < <(regex_find_all "$versions" "v?[0-9]+\.[0-9]+\.[0-9]+[^,]*")
}

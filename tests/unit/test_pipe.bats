#!/usr/bin/env bats
# =============================================================================
# Tests for lib/pipe.sh - Unix Pipeline Processing Library
# =============================================================================

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
    source "$PROJECT_ROOT/lib/pipe.sh"
}

# =============================================================================
# pipe_map tests
# =============================================================================

@test "pipe_map: applies tr command to each line" {
    result=$(echo -e "hello\nworld" | pipe_map 'tr a-z A-Z')
    [[ "$result" == $'HELLO\nWORLD' ]]
}

@test "pipe_map: works with empty input" {
    result=$(echo -n "" | pipe_map 'cat')
    [[ -z "$result" ]]
}

# =============================================================================
# pipe_filter tests
# =============================================================================

@test "pipe_filter: filters lines matching pattern" {
    result=$(echo -e "foo\nbar\nbaz" | pipe_filter 'ba')
    [[ "$result" == $'bar\nbaz' ]]
}

@test "pipe_filter: regex pattern support" {
    result=$(printf '%s\n' "1" "2" "10" "20" | pipe_filter '^[12]$')
    [[ "$result" == $'1\n2' ]]
}

@test "pipe_filter: no matches returns empty" {
    result=$(printf '%s\n' "foo" "bar" | pipe_filter 'xyz')
    [[ -z "$result" ]]
}

# =============================================================================
# pipe_reject tests
# =============================================================================

@test "pipe_reject: filters lines NOT matching pattern" {
    result=$(printf '%s\n' "foo" "bar" "baz" | pipe_reject 'ba')
    [[ "$result" == "foo" ]]
}

# =============================================================================
# pipe_take tests
# =============================================================================

@test "pipe_take: takes first N lines" {
    result=$(echo -e "1\n2\n3\n4\n5" | pipe_take 3)
    [[ "$result" == $'1\n2\n3' ]]
}

@test "pipe_take: handles fewer lines than requested" {
    result=$(echo -e "1\n2" | pipe_take 5)
    [[ "$result" == $'1\n2' ]]
}

# =============================================================================
# pipe_drop tests
# =============================================================================

@test "pipe_drop: drops first N lines" {
    result=$(echo -e "1\n2\n3\n4\n5" | pipe_drop 2)
    [[ "$result" == $'3\n4\n5' ]]
}

@test "pipe_drop: dropping more than available returns empty" {
    result=$(echo -e "1\n2" | pipe_drop 5)
    [[ -z "$result" ]]
}

# =============================================================================
# pipe_take_while tests
# =============================================================================

@test "pipe_take_while: takes while condition matches" {
    result=$(echo -e "1\n2\n3\na\n4" | pipe_take_while '^[0-9]')
    [[ "$result" == $'1\n2\n3' ]]
}

# =============================================================================
# pipe_drop_while tests
# =============================================================================

@test "pipe_drop_while: drops while condition matches, emits rest" {
    result=$(echo -e "1\n2\na\n3\n4" | pipe_drop_while '^[0-9]')
    [[ "$result" == $'a\n3\n4' ]]
}

# =============================================================================
# pipe_unique tests
# =============================================================================

@test "pipe_unique: removes duplicates preserving order" {
    result=$(echo -e "a\nb\na\nc\nb" | pipe_unique)
    [[ "$result" == $'a\nb\nc' ]]
}

@test "pipe_unique: handles all unique" {
    result=$(echo -e "a\nb\nc" | pipe_unique)
    [[ "$result" == $'a\nb\nc' ]]
}

# =============================================================================
# pipe_uniq tests
# =============================================================================

@test "pipe_uniq: removes consecutive duplicates" {
    result=$(echo -e "a\na\nb\na\na" | pipe_uniq)
    [[ "$result" == $'a\nb\na' ]]
}

# =============================================================================
# pipe_reverse tests
# =============================================================================

@test "pipe_reverse: reverses line order" {
    result=$(echo -e "1\n2\n3" | pipe_reverse)
    [[ "$result" == $'3\n2\n1' ]]
}

# =============================================================================
# pipe_field tests
# =============================================================================

@test "pipe_field: extracts field by position (default space delimiter)" {
    result=$(echo "a b c" | pipe_field 2)
    [[ "$result" == "b" ]]
}

@test "pipe_field: extracts field with custom delimiter" {
    result=$(echo "a:b:c" | pipe_field 2 ':')
    [[ "$result" == "b" ]]
}

@test "pipe_field: handles multiple lines" {
    result=$(printf '%s\n' "a:b:c" "d:e:f" | pipe_field 1 ':')
    [[ "$result" == $'a\nd' ]]
}

# =============================================================================
# pipe_fields tests
# =============================================================================

@test "pipe_fields: extracts multiple fields" {
    result=$(echo "a:b:c:d" | pipe_fields 1,3 ':' ' ')
    [[ "$result" == "a c" ]]
}

# =============================================================================
# pipe_nf tests
# =============================================================================

@test "pipe_nf: counts fields per line" {
    result=$(echo "a b c" | pipe_nf)
    [[ "$result" == "3" ]]
}

@test "pipe_nf: counts with custom delimiter" {
    result=$(echo "a:b" | pipe_nf ':')
    [[ "$result" == "2" ]]
}

# =============================================================================
# pipe_count tests
# =============================================================================

@test "pipe_count: counts lines" {
    result=$(echo -e "a\nb\nc" | pipe_count)
    [[ "$result" == "3" ]]
}

@test "pipe_count: empty input returns 0" {
    result=$(echo -n "" | pipe_count)
    [[ "$result" == "0" ]]
}

# =============================================================================
# pipe_sum tests
# =============================================================================

@test "pipe_sum: sums numeric values" {
    result=$(echo -e "1\n2\n3" | pipe_sum)
    [[ "$result" == "6" ]]
}

@test "pipe_sum: handles floats" {
    result=$(echo -e "1.5\n2.5" | pipe_sum)
    [[ "$result" == "4" ]]
}

@test "pipe_sum: ignores non-numeric lines" {
    result=$(echo -e "1\nfoo\n2" | pipe_sum)
    [[ "$result" == "3" ]]
}

# =============================================================================
# pipe_avg tests
# =============================================================================

@test "pipe_avg: calculates average" {
    result=$(echo -e "1\n2\n3" | pipe_avg)
    [[ "$result" == "2.00" ]]
}

# =============================================================================
# pipe_min/max tests
# =============================================================================

@test "pipe_min: finds minimum value" {
    result=$(echo -e "3\n1\n2" | pipe_min)
    [[ "$result" == "1" ]]
}

@test "pipe_max: finds maximum value" {
    result=$(echo -e "3\n1\n2" | pipe_max)
    [[ "$result" == "3" ]]
}

# =============================================================================
# pipe_group_count tests
# =============================================================================

@test "pipe_group_count: groups and counts occurrences" {
    result=$(echo -e "a\nb\na\na" | pipe_group_count | sort -k2)
    # Check that 'a' has count 3
    [[ "$result" =~ "3".*"a" ]]
}

# =============================================================================
# pipe_prepend/append/wrap tests
# =============================================================================

@test "pipe_prepend: prepends string to each line" {
    result=$(echo -e "foo\nbar" | pipe_prepend '> ')
    [[ "$result" == $'> foo\n> bar' ]]
}

@test "pipe_append: appends string to each line" {
    result=$(echo -e "foo\nbar" | pipe_append '!')
    [[ "$result" == $'foo!\nbar!' ]]
}

@test "pipe_wrap: wraps each line with prefix and suffix" {
    result=$(echo -e "foo\nbar" | pipe_wrap '"' '"')
    [[ "$result" == $'"foo"\n"bar"' ]]
}

# =============================================================================
# pipe_number tests
# =============================================================================

@test "pipe_number: numbers lines" {
    result=$(echo -e "a\nb\nc" | pipe_number)
    [[ "$result" =~ ^1 ]]
    [[ "$result" =~ 3 ]]
}

# =============================================================================
# pipe_replace tests
# =============================================================================

@test "pipe_replace: replaces pattern in each line" {
    result=$(echo -e "hello\nworld" | pipe_replace 'o' '0')
    [[ "$result" == $'hell0\nw0rld' ]]
}

# =============================================================================
# pipe_join tests
# =============================================================================

@test "pipe_join: joins lines with delimiter" {
    result=$(echo -e "a\nb\nc" | pipe_join ',')
    [[ "$result" == "a,b,c" ]]
}

@test "pipe_join: default comma delimiter" {
    result=$(echo -e "1\n2\n3" | pipe_join)
    [[ "$result" == "1,2,3" ]]
}

# =============================================================================
# pipe_split tests
# =============================================================================

@test "pipe_split: splits line into multiple lines" {
    result=$(echo "a,b,c" | pipe_split ',')
    [[ "$result" == $'a\nb\nc' ]]
}

# =============================================================================
# pipe_chunk tests
# =============================================================================

@test "pipe_chunk: chunks lines into groups" {
    result=$(echo -e "1\n2\n3\n4" | pipe_chunk 2 ',')
    [[ "$result" == $'1,2\n3,4' ]]
}

@test "pipe_chunk: handles remainder" {
    result=$(echo -e "1\n2\n3" | pipe_chunk 2 ',')
    [[ "$result" == $'1,2\n3' ]]
}

# =============================================================================
# pipe_upper/lower/trim tests
# =============================================================================

@test "pipe_upper: converts to uppercase" {
    result=$(echo -e "hello\nWorld" | pipe_upper)
    [[ "$result" == $'HELLO\nWORLD' ]]
}

@test "pipe_lower: converts to lowercase" {
    result=$(echo -e "HELLO\nWorld" | pipe_lower)
    [[ "$result" == $'hello\nworld' ]]
}

@test "pipe_trim: trims whitespace" {
    result=$(echo -e "  hello  \n  world  " | pipe_trim)
    [[ "$result" == $'hello\nworld' ]]
}

# =============================================================================
# pipe_length tests
# =============================================================================

@test "pipe_length: returns length of each line" {
    result=$(echo -e "a\nab\nabc" | pipe_length)
    [[ "$result" == $'1\n2\n3' ]]
}

# =============================================================================
# pipe_peek tests
# =============================================================================

@test "pipe_peek: passes through while printing to stderr" {
    result=$(echo -e "a\nb" | pipe_peek 2>/dev/null)
    [[ "$result" == $'a\nb' ]]
}

# =============================================================================
# pipe_reduce tests
# =============================================================================

@test "pipe_reduce: accumulates values" {
    # Simple concatenation
    result=$(echo -e "a\nb\nc" | pipe_reduce 'printf "%s%s" "$acc" "$line"')
    [[ "$result" == "abc" ]]
}

# =============================================================================
# Composition tests (the power of pipes!)
# =============================================================================

@test "composition: chain multiple pipe functions" {
    result=$(echo -e "  hello  \n  WORLD  \n  foo  " | pipe_trim | pipe_lower | pipe_filter 'o')
    [[ "$result" == $'hello\nworld\nfoo' ]]
}

@test "composition: filter, take, join" {
    result=$(echo -e "1\n2\n3\n4\n5" | pipe_filter '^[0-9]$' | pipe_take 3 | pipe_join '-')
    [[ "$result" == "1-2-3" ]]
}

@test "composition: field extraction and transformation" {
    result=$(printf '%s\n' "John:Doe" "Jane:Smith" | pipe_field 1 ':' | pipe_upper)
    [[ "$result" == $'JOHN\nJANE' ]]
}

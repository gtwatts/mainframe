#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Streaming Module Tests
# =============================================================================
# Comprehensive tests for lib/streaming.sh (30+ functions, 60+ test cases)
# Covers: map, filter, reduce, parallel, rate limiting, type-aware pipes, USOP
# =============================================================================

load 'test_helper'

setup() {
    source_lib "streaming"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "streaming")

    # Create test helper functions
    double() { echo $(($1 * 2)); }
    export -f double

    increment() { echo $(($1 + 1)); }
    export -f increment

    is_even() { (($1 % 2 == 0)); }
    export -f is_even

    is_positive() { (($1 > 0)); }
    export -f is_positive

    is_not_empty() { [[ -n "$1" ]]; }
    export -f is_not_empty

    sum() { echo $(($1 + $2)); }
    export -f sum

    product() { echo $(($1 * $2)); }
    export -f product

    to_upper() { echo "${1^^}"; }
    export -f to_upper

    starts_with_hash() { [[ "$1" == \#* ]]; }
    export -f starts_with_hash

    is_valid_json() { [[ "$1" =~ ^\{.*\}$ ]] || [[ "$1" =~ ^\[.*\]$ ]]; }
    export -f is_valid_json
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# stream_map TESTS
# =============================================================================

@test "stream_map applies function to each line" {
    local result
    result=$(printf '1\n2\n3\n' | stream_map double)
    [ "$result" = $'2\n4\n6' ]
}

@test "stream_map handles empty input" {
    local result
    result=$(printf '' | stream_map double)
    [ -z "$result" ]
}

@test "stream_map handles single line" {
    local result
    result=$(printf '5\n' | stream_map double)
    [ "$result" = "10" ]
}

@test "stream_map works with string transformation" {
    local result
    result=$(printf 'hello\nworld\n' | stream_map to_upper)
    [ "$result" = $'HELLO\nWORLD' ]
}

@test "stream_map_v stores results in array" {
    local -a result
    stream_map_v result double 1 2 3 4 5
    [ "${#result[@]}" -eq 5 ]
    [ "${result[0]}" = "2" ]
    [ "${result[4]}" = "10" ]
}

# =============================================================================
# stream_filter TESTS
# =============================================================================

@test "stream_filter keeps matching lines" {
    local result
    result=$(printf '1\n2\n3\n4\n5\n6\n' | stream_filter is_even)
    [ "$result" = $'2\n4\n6' ]
}

@test "stream_filter handles all matching" {
    local result
    result=$(printf '2\n4\n6\n' | stream_filter is_even)
    [ "$result" = $'2\n4\n6' ]
}

@test "stream_filter handles none matching" {
    local result
    result=$(printf '1\n3\n5\n' | stream_filter is_even)
    [ -z "$result" ]
}

@test "stream_filter handles empty input" {
    local result
    result=$(printf '' | stream_filter is_even)
    [ -z "$result" ]
}

@test "stream_filter_v stores filtered results in array" {
    local -a result
    stream_filter_v result is_even 1 2 3 4 5 6
    [ "${#result[@]}" -eq 3 ]
    [ "${result[0]}" = "2" ]
    [ "${result[1]}" = "4" ]
    [ "${result[2]}" = "6" ]
}

# =============================================================================
# stream_reduce TESTS
# =============================================================================

@test "stream_reduce folds to single value" {
    local result
    result=$(printf '1\n2\n3\n4\n5\n' | stream_reduce sum 0)
    [ "$result" = "15" ]
}

@test "stream_reduce handles empty input" {
    local result
    result=$(printf '' | stream_reduce sum 0)
    [ "$result" = "0" ]
}

@test "stream_reduce handles single element" {
    local result
    result=$(printf '42\n' | stream_reduce sum 0)
    [ "$result" = "42" ]
}

@test "stream_reduce with product" {
    local result
    result=$(printf '2\n3\n4\n' | stream_reduce product 1)
    [ "$result" = "24" ]
}

@test "stream_reduce_v stores result in variable" {
    local result
    stream_reduce_v result sum 0 1 2 3 4 5
    [ "$result" = "15" ]
}

# =============================================================================
# stream_take / stream_skip / stream_head / stream_tail TESTS
# =============================================================================

@test "stream_take gets first N lines" {
    local result
    result=$(printf '1\n2\n3\n4\n5\n' | stream_take 3)
    [ "$result" = $'1\n2\n3' ]
}

@test "stream_take handles fewer lines than N" {
    local result
    result=$(printf '1\n2\n' | stream_take 5)
    [ "$result" = $'1\n2' ]
}

@test "stream_take zero returns nothing" {
    local result
    result=$(printf '1\n2\n3\n' | stream_take 0)
    [ -z "$result" ]
}

@test "stream_skip skips first N lines" {
    local result
    result=$(printf '1\n2\n3\n4\n5\n' | stream_skip 2)
    [ "$result" = $'3\n4\n5' ]
}

@test "stream_skip all returns nothing" {
    local result
    result=$(printf '1\n2\n3\n' | stream_skip 5)
    [ -z "$result" ]
}

@test "stream_head is alias for stream_take" {
    local result
    result=$(printf '1\n2\n3\n4\n5\n' | stream_head 2)
    [ "$result" = $'1\n2' ]
}

@test "stream_tail gets last N lines" {
    local result
    result=$(printf '1\n2\n3\n4\n5\n' | stream_tail 2)
    [ "$result" = $'4\n5' ]
}

@test "stream_tail handles fewer lines than N" {
    local result
    result=$(printf '1\n2\n' | stream_tail 5)
    [ "$result" = $'1\n2' ]
}

# =============================================================================
# stream_unique / stream_sort / stream_reverse TESTS
# =============================================================================

@test "stream_unique removes duplicates" {
    local result
    result=$(printf 'a\nb\na\nc\nb\n' | stream_unique)
    [ "$result" = $'a\nb\nc' ]
}

@test "stream_unique preserves order" {
    local result
    result=$(printf 'c\na\nb\na\n' | stream_unique)
    [ "$result" = $'c\na\nb' ]
}

@test "stream_unique handles empty input" {
    local result
    result=$(printf '' | stream_unique)
    [ -z "$result" ]
}

@test "stream_sort sorts alphabetically" {
    local result
    result=$(printf 'banana\napple\ncherry\n' | stream_sort)
    [ "$result" = $'apple\nbanana\ncherry' ]
}

@test "stream_sort handles numeric sort" {
    local result
    result=$(printf '10\n2\n1\n20\n' | stream_sort -n)
    [ "$result" = $'1\n2\n10\n20' ]
}

@test "stream_reverse reverses order" {
    local result
    result=$(printf '1\n2\n3\n' | stream_reverse)
    [ "$result" = $'3\n2\n1' ]
}

@test "stream_reverse handles empty input" {
    local result
    result=$(printf '' | stream_reverse)
    [ -z "$result" ]
}

@test "stream_reverse handles single line" {
    local result
    result=$(printf 'only\n' | stream_reverse)
    [ "$result" = "only" ]
}

# =============================================================================
# stream_batch / stream_chunk TESTS
# =============================================================================

@test "stream_batch processes in batches" {
    local result
    result=$(printf '1\n2\n3\n4\n5\n' | stream_batch 2 'wc -l')
    # Two batches of 2, one batch of 1
    local lines
    lines=$(echo "$result" | wc -l)
    [ "$lines" -eq 3 ]
}

@test "stream_chunk splits into chunks" {
    local result
    result=$(printf '1\n2\n3\n4\n5\n' | stream_chunk 2)
    local lines
    lines=$(echo "$result" | wc -l)
    [ "$lines" -eq 5 ]
}

@test "stream_chunk with separator" {
    local result
    result=$(printf '1\n2\n3\n4\n' | stream_chunk 2 "---")
    [[ "$result" == *"---"* ]]
}

# =============================================================================
# stream_fanout / stream_fanin TESTS
# =============================================================================

@test "stream_fanout distributes to processors" {
    # Simple test with identity functions
    cat_fn() { cat; }
    export -f cat_fn

    local result
    result=$(printf 'test\n' | stream_fanout 2 cat_fn cat_fn)
    local lines
    lines=$(echo "$result" | wc -l)
    [ "$lines" -eq 2 ]
}

@test "stream_fanout fails with insufficient functions" {
    cat_fn() { cat; }
    export -f cat_fn

    run stream_fanout 3 cat_fn cat_fn < /dev/null
    [ "$status" -ne 0 ]
}

@test "stream_fanin merges files" {
    printf '1\n2\n' > "$TEST_DIR/f1.txt"
    printf 'a\nb\n' > "$TEST_DIR/f2.txt"

    local result
    result=$(stream_fanin "$TEST_DIR/f1.txt" "$TEST_DIR/f2.txt")
    # Should interleave: 1, a, 2, b
    [[ "$result" == *"1"* ]]
    [[ "$result" == *"a"* ]]
}

# =============================================================================
# stream_rate_limit TESTS
# =============================================================================

@test "stream_rate_limit outputs all items" {
    local result
    result=$(printf '1\n2\n3\n' | stream_rate_limit 100 10ms)
    [ "$result" = $'1\n2\n3' ]
}

@test "stream_rate_limit handles seconds format" {
    local result
    # Quick rate for testing
    result=$(printf 'a\n' | stream_rate_limit 10 1s)
    [ "$result" = "a" ]
}

# =============================================================================
# stream_json_lines / stream_csv_lines / stream_detect_type TESTS
# =============================================================================

@test "stream_json_lines parses NDJSON" {
    local result
    result=$(printf '{"a":1}\n{"b":2}\n' | stream_json_lines)
    [ "$result" = $'{"a":1}\n{"b":2}' ]
}

@test "stream_json_lines skips invalid JSON" {
    local result
    result=$(printf '{"a":1}\nnot json\n{"b":2}\n' | stream_json_lines)
    [ "$result" = $'{"a":1}\n{"b":2}' ]
}

@test "stream_json_lines skips empty lines" {
    local result
    result=$(printf '{"a":1}\n\n{"b":2}\n' | stream_json_lines)
    [ "$result" = $'{"a":1}\n{"b":2}' ]
}

@test "stream_csv_lines passes through CSV" {
    local result
    result=$(printf 'header,row\n1,a\n2,b\n' | stream_csv_lines false)
    [ "$result" = $'1,a\n2,b' ]
}

@test "stream_csv_lines with header" {
    local result
    result=$(printf 'header,row\n1,a\n' | stream_csv_lines true)
    [ "$result" = $'header,row\n1,a' ]
}

@test "stream_validate passes valid lines" {
    local result
    result=$(printf '{"a":1}\n{"b":2}\n' | stream_validate is_valid_json)
    [ "$result" = $'{"a":1}\n{"b":2}' ]
}

@test "stream_validate skips invalid in non-strict mode" {
    local result
    result=$(printf '{"a":1}\nnot json\n{"b":2}\n' | stream_validate is_valid_json false)
    [ "$result" = $'{"a":1}\n{"b":2}' ]
}

@test "stream_validate fails in strict mode" {
    run bash -c "printf '{\"a\":1}\nnot json\n' | stream_validate is_valid_json true"
    [ "$status" -ne 0 ]
}

# =============================================================================
# stream_count / stream_any / stream_all / stream_none / stream_find TESTS
# =============================================================================

@test "stream_count returns line count" {
    local result
    result=$(printf '1\n2\n3\n4\n5\n' | stream_count)
    [ "$result" = "5" ]
}

@test "stream_count handles empty input" {
    local result
    result=$(printf '' | stream_count)
    [ "$result" = "0" ]
}

@test "stream_any returns 0 when match found" {
    printf '1\n2\n3\n' | stream_any is_even
}

@test "stream_any returns 1 when no match" {
    ! printf '1\n3\n5\n' | stream_any is_even
}

@test "stream_all returns 0 when all match" {
    printf '2\n4\n6\n' | stream_all is_even
}

@test "stream_all returns 1 when any fails" {
    ! printf '2\n3\n4\n' | stream_all is_even
}

@test "stream_none returns 0 when none match" {
    printf '1\n3\n5\n' | stream_none is_even
}

@test "stream_none returns 1 when any match" {
    ! printf '1\n2\n3\n' | stream_none is_even
}

@test "stream_find returns first match" {
    local result
    result=$(printf '1\n3\n4\n5\n6\n' | stream_find is_even)
    [ "$result" = "4" ]
}

@test "stream_find returns 1 when not found" {
    ! printf '1\n3\n5\n' | stream_find is_even
}

# =============================================================================
# stream_take_while / stream_drop_while TESTS
# =============================================================================

@test "stream_take_while takes while condition holds" {
    local result
    result=$(printf '1\n2\n3\n-1\n4\n5\n' | stream_take_while is_positive)
    [ "$result" = $'1\n2\n3' ]
}

@test "stream_take_while handles empty result" {
    local result
    result=$(printf '-1\n2\n3\n' | stream_take_while is_positive)
    [ -z "$result" ]
}

@test "stream_drop_while drops while condition holds" {
    local result
    result=$(printf '# comment\n# another\ndata\nmore\n' | stream_drop_while starts_with_hash)
    [ "$result" = $'data\nmore' ]
}

@test "stream_drop_while handles all dropped" {
    local result
    result=$(printf '# a\n# b\n' | stream_drop_while starts_with_hash)
    [ -z "$result" ]
}

# =============================================================================
# stream_group_by / stream_enumerate / stream_zip TESTS
# =============================================================================

@test "stream_group_by groups by key" {
    first_char() { echo "${1:0:1}"; }
    export -f first_char

    local result
    result=$(printf 'apple\napricot\nbanana\nblueberry\n' | stream_group_by first_char)
    [[ "$result" == *"a:"* ]]
    [[ "$result" == *"b:"* ]]
}

@test "stream_enumerate adds line numbers" {
    local result
    result=$(printf 'a\nb\nc\n' | stream_enumerate)
    [[ "$result" == "0"*"a"* ]]
    [[ "$result" == *"1"*"b"* ]]
    [[ "$result" == *"2"*"c"* ]]
}

@test "stream_enumerate with custom start" {
    local result
    result=$(printf 'a\nb\n' | stream_enumerate 100)
    [[ "$result" == "100"*"a"* ]]
    [[ "$result" == *"101"*"b"* ]]
}

@test "stream_zip pairs two streams" {
    printf '1\n2\n3\n' > "$TEST_DIR/nums.txt"

    local result
    result=$(printf 'a\nb\nc\n' | stream_zip "$TEST_DIR/nums.txt")
    [[ "$result" == *"a"*"1"* ]]
    [[ "$result" == *"b"*"2"* ]]
    [[ "$result" == *"c"*"3"* ]]
}

# =============================================================================
# USOP OUTPUT TESTS
# =============================================================================

@test "stream_to_usop wraps in JSON envelope" {
    local result
    result=$(printf 'a\nb\nc\n' | stream_to_usop)
    [[ "$result" == '{"ok":true,"data":'* ]]
    [[ "$result" == *'"a"'* ]]
    [[ "$result" == *'"count":3'* ]]
}

@test "stream_to_usop handles empty input" {
    local result
    result=$(printf '' | stream_to_usop)
    [[ "$result" == '{"ok":true,"data":[],"meta":{"count":0}}' ]]
}

@test "stream_from_usop extracts data" {
    local result
    result=$(stream_from_usop '{"ok":true,"data":["x","y","z"]}')
    [ "$result" = $'x\ny\nz' ]
}

@test "stream_stats computes statistics" {
    local result
    result=$(printf '1\n2\n3\n4\n5\n' | stream_stats)
    [[ "$result" == *'"count":5'* ]]
    [[ "$result" == *'"sum":15'* ]]
    [[ "$result" == *'"min":1'* ]]
    [[ "$result" == *'"max":5'* ]]
    [[ "$result" == *'"avg":3.00'* ]]
}

@test "stream_stats handles non-numeric data" {
    local result
    result=$(printf 'a\nb\nc\n' | stream_stats)
    [[ "$result" == *'"count":3'* ]]
}

# =============================================================================
# stream_compose / stream_tap TESTS
# =============================================================================

@test "stream_compose chains operations" {
    local result
    result=$(printf '1\n2\n3\n4\n5\n6\n' | stream_compose "stream_filter is_even" "stream_map double")
    [ "$result" = $'4\n8\n12' ]
}

@test "stream_tap passes through while calling function" {
    log_to_file() { echo "$1" >> "$TEST_DIR/tap.log"; }
    export -f log_to_file
    export TEST_DIR

    local result
    result=$(printf 'a\nb\nc\n' | stream_tap log_to_file 2>/dev/null)
    [ "$result" = $'a\nb\nc' ]
}

# =============================================================================
# EDGE CASES & INTEGRATION TESTS
# =============================================================================

@test "pipeline: filter then map then reduce" {
    local result
    result=$(printf '1\n2\n3\n4\n5\n6\n' | stream_filter is_even | stream_map double | stream_reduce sum 0)
    # evens: 2,4,6 -> doubled: 4,8,12 -> sum: 24
    [ "$result" = "24" ]
}

@test "pipeline: take unique sorted" {
    local result
    result=$(printf 'c\na\nb\na\nc\n' | stream_unique | stream_sort | stream_take 2)
    [ "$result" = $'a\nb' ]
}

@test "handles lines with spaces" {
    local result
    result=$(printf 'hello world\nfoo bar\n' | stream_map to_upper)
    [ "$result" = $'HELLO WORLD\nFOO BAR' ]
}

@test "handles lines with special characters" {
    local result
    result=$(printf 'a$b\nc&d\n' | stream_count)
    [ "$result" = "2" ]
}

@test "handles very long lines" {
    local long_line
    long_line=$(printf 'a%.0s' {1..1000})
    local result
    result=$(printf '%s\n' "$long_line" | stream_count)
    [ "$result" = "1" ]
}

@test "handles binary-like content gracefully" {
    local result
    result=$(printf 'normal\n\x00binary\nnormal2\n' | stream_count 2>/dev/null || echo "error")
    # Should either count or handle gracefully
    [[ "$result" =~ ^[0-9]+$ ]] || [ "$result" = "error" ]
}

@test "stream operations are composable with standard unix tools" {
    local result
    result=$(printf '1\n2\n3\n' | stream_map double | grep '4')
    [ "$result" = "4" ]
}

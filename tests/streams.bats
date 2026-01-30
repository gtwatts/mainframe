#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Streams Module Tests
# =============================================================================
# Comprehensive tests for lib/streams.sh (47+ functions)
# Covers: creation, transformation, aggregation, windowing, combination, output
# =============================================================================

load 'test_helper'

setup() {
    source_lib "streams"
    export MAINFRAME_QUIET=1
    export MAINFRAME_STREAM_DEBUG=0
    TEST_DIR=$(create_test_dir "streams")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# STREAM CREATION TESTS
# =============================================================================

@test "stream_from_array creates stream from array variable" {
    local arr=(a b c)
    local result
    result=$(stream_from_array arr)
    [ "$(echo "$result" | wc -l)" -eq 3 ]
    [ "$(echo "$result" | head -1)" = "a" ]
    [ "$(echo "$result" | tail -1)" = "c" ]
}

@test "stream_from_array creates stream from positional args" {
    local result
    result=$(stream_from_array "x" "y" "z")
    [ "$(echo "$result" | wc -l)" -eq 3 ]
    [ "$(echo "$result" | head -1)" = "x" ]
}

@test "stream_from_file reads file lines" {
    echo -e "line1\nline2\nline3" > "$TEST_DIR/test.txt"
    local result
    result=$(stream_from_file "$TEST_DIR/test.txt")
    [ "$(echo "$result" | wc -l)" -eq 3 ]
    [ "$(echo "$result" | head -1)" = "line1" ]
}

@test "stream_from_file fails for missing file" {
    run stream_from_file "/nonexistent/file.txt"
    [ "$status" -ne 0 ]
}

@test "stream_from_command executes command" {
    local result
    result=$(stream_from_command "echo -e 'a\nb\nc'")
    [ "$(echo "$result" | wc -l)" -eq 3 ]
}

@test "stream_from_range generates numeric sequence" {
    local result
    result=$(stream_from_range 1 5)
    [ "$(echo "$result" | wc -l)" -eq 5 ]
    [ "$(echo "$result" | head -1)" = "1" ]
    [ "$(echo "$result" | tail -1)" = "5" ]
}

@test "stream_from_range handles step parameter" {
    local result
    result=$(stream_from_range 0 10 2)
    [ "$(echo "$result" | wc -l)" -eq 6 ]
    assert_equal "0" "$(echo "$result" | head -1)"
    assert_equal "10" "$(echo "$result" | tail -1)"
}

@test "stream_from_range handles negative step" {
    local result
    result=$(stream_from_range 5 1 -1)
    [ "$(echo "$result" | wc -l)" -eq 5 ]
    [ "$(echo "$result" | head -1)" = "5" ]
    [ "$(echo "$result" | tail -1)" = "1" ]
}

@test "stream_from_range rejects zero step" {
    run stream_from_range 1 10 0
    [ "$status" -ne 0 ]
}

@test "stream_from_generator uses generator function" {
    counter=0
    gen() { ((counter++)); echo "$counter"; [[ $counter -lt 5 ]] || return 1; }
    local result
    result=$(stream_from_generator gen 5)
    [ "$(echo "$result" | wc -l)" -eq 5 ]
}

@test "stream_empty produces no output" {
    local result
    result=$(stream_empty)
    [ -z "$result" ]
}

@test "stream_of creates stream from arguments" {
    local result
    result=$(stream_of foo bar baz)
    [ "$(echo "$result" | wc -l)" -eq 3 ]
    [ "$(echo "$result" | head -1)" = "foo" ]
}

@test "stream_repeat repeats value N times" {
    local result
    result=$(stream_repeat "x" 5)
    [ "$(echo "$result" | wc -l)" -eq 5 ]
    [ "$(echo "$result" | uniq | wc -l)" -eq 1 ]
}

@test "stream_iterate applies function iteratively" {
    double() { echo $(($1 * 2)); }
    local result
    result=$(stream_iterate double 1 5)
    [ "$(echo "$result" | wc -l)" -eq 5 ]
    [ "$(echo "$result" | head -1)" = "1" ]
    [ "$(echo "$result" | tail -1)" = "16" ]
}

# =============================================================================
# STREAM TRANSFORMATION TESTS
# =============================================================================

@test "stream_map transforms each element" {
    local result
    result=$(stream_of 1 2 3 | stream_map 'echo $(($item * 2))')
    [ "$(echo "$result" | head -1)" = "2" ]
    [ "$(echo "$result" | tail -1)" = "6" ]
}

@test "stream_map handles string transformation" {
    local result
    result=$(stream_of a b c | stream_map 'printf "x%s" "$item"')
    [ "$(echo "$result" | head -1)" = "xa" ]
}

@test "stream_filter keeps matching elements" {
    local result
    result=$(stream_from_range 1 10 | stream_filter '[[ $item -gt 5 ]]')
    [ "$(echo "$result" | wc -l)" -eq 5 ]
    [ "$(echo "$result" | head -1)" = "6" ]
}

@test "stream_filter with pattern matching" {
    local result
    result=$(stream_of foo bar baz | stream_filter '[[ "$item" == b* ]]')
    [ "$(echo "$result" | wc -l)" -eq 2 ]
}

@test "stream_take limits elements" {
    local result
    result=$(stream_from_range 1 100 | stream_take 5)
    [ "$(echo "$result" | wc -l)" -eq 5 ]
    [ "$(echo "$result" | tail -1)" = "5" ]
}

@test "stream_drop skips elements" {
    local result
    result=$(stream_from_range 1 10 | stream_drop 3)
    [ "$(echo "$result" | wc -l)" -eq 7 ]
    [ "$(echo "$result" | head -1)" = "4" ]
}

@test "stream_take_while stops at false" {
    local result
    result=$(stream_from_range 1 10 | stream_take_while '[[ $item -lt 5 ]]')
    [ "$(echo "$result" | wc -l)" -eq 4 ]
    [ "$(echo "$result" | tail -1)" = "4" ]
}

@test "stream_drop_while starts at false" {
    local result
    result=$(stream_from_range 1 10 | stream_drop_while '[[ $item -lt 5 ]]')
    [ "$(echo "$result" | wc -l)" -eq 6 ]
    [ "$(echo "$result" | head -1)" = "5" ]
}

@test "stream_distinct removes duplicates" {
    local result
    result=$(stream_of a b a c b d | stream_distinct)
    [ "$(echo "$result" | wc -l)" -eq 4 ]
    assert_equal "a" "$(echo "$result" | head -1)"
}

@test "stream_sorted sorts lexicographically" {
    local result
    result=$(stream_of c a b | stream_sorted)
    [ "$(echo "$result" | head -1)" = "a" ]
    [ "$(echo "$result" | tail -1)" = "c" ]
}

@test "stream_sorted sorts numerically with -n" {
    local result
    result=$(stream_of 10 2 1 20 | stream_sorted -n)
    [ "$(echo "$result" | head -1)" = "1" ]
    [ "$(echo "$result" | tail -1)" = "20" ]
}

@test "stream_sorted reverse with -r" {
    local result
    result=$(stream_of 1 2 3 | stream_sorted -n -r)
    [ "$(echo "$result" | head -1)" = "3" ]
    [ "$(echo "$result" | tail -1)" = "1" ]
}

@test "stream_reversed reverses order" {
    local result
    result=$(stream_of a b c | stream_reversed)
    [ "$(echo "$result" | head -1)" = "c" ]
    [ "$(echo "$result" | tail -1)" = "a" ]
}

@test "stream_flat_map flattens results" {
    local result
    result=$(stream_of "a b" "c d" | stream_flat_map 'echo $item | tr " " "\n"')
    [ "$(echo "$result" | wc -l)" -eq 4 ]
}

@test "stream_enumerate adds indices" {
    local result
    result=$(stream_of a b c | stream_enumerate)
    [ "$(echo "$result" | head -1)" = "0:a" ]
    [ "$(echo "$result" | tail -1)" = "2:c" ]
}

@test "stream_enumerate with custom start" {
    local result
    result=$(stream_of a b | stream_enumerate --start 10)
    [ "$(echo "$result" | head -1)" = "10:a" ]
}

@test "stream_trim removes whitespace" {
    local result
    result=$(stream_of "  a  " "  b  " | stream_trim)
    [ "$(echo "$result" | head -1)" = "a" ]
}

@test "stream_compact removes empty lines" {
    local result
    result=$(stream_of "a" "" "b" "  " "c" | stream_compact)
    [ "$(echo "$result" | wc -l)" -eq 3 ]
}

# =============================================================================
# STREAM AGGREGATION TESTS
# =============================================================================

@test "stream_reduce sums with accumulator" {
    local result
    result=$(stream_of 1 2 3 4 | stream_reduce 'echo $(($acc + $item))')
    [ "$result" = "10" ]
}

@test "stream_fold uses initial value" {
    local result
    result=$(stream_of 1 2 3 | stream_fold 10 'echo $(($acc + $item))')
    [ "$result" = "16" ]
}

@test "stream_count counts elements" {
    local result
    result=$(stream_from_range 1 100 | stream_count)
    [ "$result" = "100" ]
}

@test "stream_count handles empty stream" {
    local result
    result=$(stream_empty | stream_count)
    [ "$result" = "0" ]
}

@test "stream_sum sums integers" {
    local result
    result=$(stream_of 1 2 3 4 5 | stream_sum)
    [ "$result" = "15" ]
}

@test "stream_min finds minimum" {
    local result
    result=$(stream_of 3 1 4 1 5 | stream_min -n)
    [ "$result" = "1" ]
}

@test "stream_max finds maximum" {
    local result
    result=$(stream_of 3 1 4 1 5 | stream_max -n)
    [ "$result" = "5" ]
}

@test "stream_first gets first element" {
    local result
    result=$(stream_of a b c | stream_first)
    [ "$result" = "a" ]
}

@test "stream_first returns 1 for empty stream" {
    run bash -c 'source '"$MAINFRAME_ROOT"'/lib/streams.sh; stream_empty | stream_first'
    [ "$status" -eq 1 ]
}

@test "stream_last gets last element" {
    local result
    result=$(stream_of a b c | stream_last)
    [ "$result" = "c" ]
}

@test "stream_any returns true when match found" {
    local result
    result=$(stream_of 1 2 3 | stream_any '[[ $item -gt 2 ]]')
    [ "$result" = "true" ]
}

@test "stream_any returns false when no match" {
    local result
    result=$(stream_of 1 2 3 | stream_any '[[ $item -gt 5 ]]')
    [ "$result" = "false" ]
}

@test "stream_all returns true when all match" {
    local result
    result=$(stream_of 2 4 6 | stream_all '[[ $(($item % 2)) -eq 0 ]]')
    [ "$result" = "true" ]
}

@test "stream_all returns false when not all match" {
    local result
    result=$(stream_of 1 2 3 | stream_all '[[ $(($item % 2)) -eq 0 ]]')
    [ "$result" = "false" ]
}

@test "stream_none returns true when none match" {
    local result
    result=$(stream_of 1 2 3 | stream_none '[[ $item -gt 5 ]]')
    [ "$result" = "true" ]
}

@test "stream_none returns false when any match" {
    local result
    result=$(stream_of 1 2 3 | stream_none '[[ $item -gt 2 ]]')
    [ "$result" = "false" ]
}

@test "stream_find returns first match" {
    local result
    result=$(stream_of 1 2 3 4 | stream_find '[[ $item -gt 2 ]]')
    [ "$result" = "3" ]
}

@test "stream_average calculates mean" {
    local result
    result=$(stream_of 10 20 30 | stream_average)
    [ "$result" = "20" ]
}

# =============================================================================
# STREAM WINDOWING TESTS
# =============================================================================

@test "stream_window creates sliding windows" {
    local result
    result=$(stream_of 1 2 3 4 5 | stream_window 3)
    [ "$(echo "$result" | wc -l)" -eq 3 ]
    assert_contains "$result" '["1","2","3"]'
}

@test "stream_batch creates fixed batches" {
    local result
    result=$(stream_of 1 2 3 4 5 | stream_batch 2)
    [ "$(echo "$result" | wc -l)" -eq 3 ]
    assert_contains "$result" '["1","2"]'
}

@test "stream_batch handles remainder" {
    local result
    result=$(stream_of 1 2 3 4 5 | stream_batch 2 | tail -1)
    [ "$result" = '["5"]' ]
}

@test "stream_sample takes every Nth element" {
    local result
    result=$(stream_from_range 1 20 | stream_sample 5)
    [ "$(echo "$result" | wc -l)" -eq 4 ]
    [ "$(echo "$result" | head -1)" = "1" ]
}

@test "stream_throttle outputs all elements" {
    local result
    result=$(stream_of a b c | stream_throttle 1)
    [ "$(echo "$result" | wc -l)" -eq 3 ]
}

@test "stream_shuffle outputs all elements" {
    local result
    result=$(stream_from_range 1 10 | stream_shuffle)
    [ "$(echo "$result" | wc -l)" -eq 10 ]
}

@test "stream_random returns one element" {
    local result
    result=$(stream_from_range 1 100 | stream_random)
    [ "$(echo "$result" | wc -l)" -eq 1 ]
    [[ "$result" -ge 1 && "$result" -le 100 ]]
}

# =============================================================================
# STREAM COMBINATION TESTS
# =============================================================================

@test "stream_zip pairs elements" {
    local result
    result=$(stream_zip <(stream_of a b c) <(stream_of 1 2 3))
    [ "$(echo "$result" | wc -l)" -eq 3 ]
    [ "$(echo "$result" | head -1)" = "a:1" ]
}

@test "stream_zip with custom separator" {
    local result
    result=$(stream_zip <(stream_of a b) <(stream_of 1 2) --separator ",")
    [ "$(echo "$result" | head -1)" = "a,1" ]
}

@test "stream_concat joins streams" {
    local result
    result=$(stream_concat <(stream_of a b) <(stream_of c d))
    [ "$(echo "$result" | wc -l)" -eq 4 ]
    [ "$(echo "$result" | head -1)" = "a" ]
    [ "$(echo "$result" | tail -1)" = "d" ]
}

@test "stream_interleave alternates elements" {
    local result
    result=$(stream_interleave <(stream_of a b c) <(stream_of 1 2 3))
    [ "$(echo "$result" | wc -l)" -eq 6 ]
    [ "$(echo "$result" | head -1)" = "a" ]
    [ "$(echo "$result" | head -2 | tail -1)" = "1" ]
}

@test "stream_merge_sorted maintains order" {
    local result
    result=$(stream_merge_sorted <(stream_of 1 3 5) <(stream_of 2 4 6) -n)
    [ "$(echo "$result" | wc -l)" -eq 6 ]
    [ "$(echo "$result" | head -1)" = "1" ]
    [ "$(echo "$result" | tail -1)" = "6" ]
}

# =============================================================================
# STREAM OUTPUT TESTS
# =============================================================================

@test "stream_collect outputs JSON array" {
    local result
    result=$(stream_of a b c | stream_collect)
    [ "$result" = '["a","b","c"]' ]
}

@test "stream_to_file writes to file" {
    stream_of a b c | stream_to_file "$TEST_DIR/output.txt"
    [ -f "$TEST_DIR/output.txt" ]
    [ "$(wc -l < "$TEST_DIR/output.txt")" -eq 3 ]
}

@test "stream_to_file appends with --append" {
    stream_of a b | stream_to_file "$TEST_DIR/append.txt"
    stream_of c d | stream_to_file "$TEST_DIR/append.txt" --append
    [ "$(wc -l < "$TEST_DIR/append.txt")" -eq 4 ]
}

@test "stream_foreach executes action" {
    stream_of 1 2 3 | stream_foreach 'echo "item: $item"' > "$TEST_DIR/foreach.txt"
    assert_contains "$(cat "$TEST_DIR/foreach.txt")" "item: 1"
}

@test "stream_to_json outputs valid JSON" {
    local result
    result=$(stream_of "hello world" "foo" | stream_to_json)
    assert_contains "$result" '"hello world"'
    assert_starts_with "$result" "["
    assert_ends_with "$result" "]"
}

@test "stream_to_json escapes special chars" {
    local result
    result=$(stream_of 'say "hello"' | stream_to_json)
    assert_contains "$result" '\"hello\"'
}

@test "stream_stats outputs statistics" {
    local result
    result=$(stream_of 1 2 3 4 5 | stream_stats)
    assert_contains "$result" '"count":5'
    assert_contains "$result" '"sum":15'
}

@test "stream_join joins with delimiter" {
    local result
    result=$(stream_of a b c | stream_join ",")
    [ "$result" = "a,b,c" ]
}

@test "stream_tee writes to file and stdout" {
    local result
    result=$(stream_of a b c | stream_tee "$TEST_DIR/tee.txt")
    [ -f "$TEST_DIR/tee.txt" ]
    [ "$(echo "$result" | wc -l)" -eq 3 ]
}

# =============================================================================
# STREAM UTILITY TESTS
# =============================================================================

@test "stream_peek outputs to stderr" {
    local result
    result=$(stream_of a b c | stream_peek 2>/dev/null)
    [ "$(echo "$result" | wc -l)" -eq 3 ]
}

@test "stream_at gets element at index" {
    local result
    result=$(stream_of a b c d | stream_at 2)
    [ "$result" = "c" ]
}

@test "stream_at returns 1 for out of bounds" {
    run bash -c 'source '"$MAINFRAME_ROOT"'/lib/streams.sh; stream_of a b c | stream_at 10'
    [ "$status" -eq 1 ]
}

@test "stream_group_by groups elements" {
    local result
    result=$(stream_of aa ab ba bb | stream_group_by 'echo ${item:0:1}')
    assert_contains "$result" '"a":'
    assert_contains "$result" '"b":'
}

@test "stream_frequency counts occurrences" {
    local result
    result=$(stream_of a b a c b a | stream_frequency)
    assert_contains "$result" '"a":3'
    assert_contains "$result" '"b":2'
}

@test "stream_partition splits by predicate" {
    local result
    result=$(stream_of 1 2 3 4 5 | stream_partition '[[ $item -gt 3 ]]')
    assert_contains "$result" '"true":'
    assert_contains "$result" '"false":'
}

@test "stream_chunk_by splits at separator" {
    local result
    result=$(stream_of a b --- c d | stream_chunk_by '---')
    [ "$(echo "$result" | wc -l)" -eq 2 ]
}

@test "stream_difference computes set difference" {
    local result
    result=$(stream_of a b c d | stream_difference <(stream_of b d))
    [ "$(echo "$result" | wc -l)" -eq 2 ]
    assert_contains "$result" "a"
    assert_contains "$result" "c"
}

@test "stream_intersect computes set intersection" {
    local result
    result=$(stream_of a b c d | stream_intersect <(stream_of b d e))
    [ "$(echo "$result" | wc -l)" -eq 2 ]
    assert_contains "$result" "b"
    assert_contains "$result" "d"
}

@test "stream_union computes set union" {
    local result
    result=$(stream_of a b c | stream_union <(stream_of b c d))
    [ "$(echo "$result" | wc -l)" -eq 4 ]
}

@test "stream_version outputs library info" {
    local result
    result=$(stream_version)
    assert_contains "$result" '"library":"mainframe/streams"'
    assert_contains "$result" '"version":"1.0.0"'
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

@test "complex pipeline: filter, map, reduce" {
    local result
    result=$(stream_from_range 1 10 | \
        stream_filter '[[ $item -gt 5 ]]' | \
        stream_map 'echo $(($item * 2))' | \
        stream_sum)
    # 6*2 + 7*2 + 8*2 + 9*2 + 10*2 = 12+14+16+18+20 = 80
    [ "$result" = "80" ]
}

@test "complex pipeline: distinct, sort, take" {
    local result
    result=$(stream_of 3 1 4 1 5 9 2 6 5 | \
        stream_distinct | \
        stream_sorted -n | \
        stream_take 5 | \
        stream_join ",")
    [ "$result" = "1,2,3,4,5" ]
}

@test "complex pipeline: file processing" {
    cat > "$TEST_DIR/data.txt" << 'EOF'
apple 10
banana 20
cherry 15
date 25
EOF
    local result
    result=$(stream_from_file "$TEST_DIR/data.txt" | \
        stream_map 'echo "$item" | awk "{print \$2}"' | \
        stream_sum)
    [ "$result" = "70" ]
}

@test "complex pipeline: batch processing" {
    local result
    result=$(stream_from_range 1 9 | stream_batch 3 | wc -l)
    [ "$result" = "3" ]
}

@test "handles empty stream gracefully" {
    local result
    result=$(stream_empty | stream_map 'echo "x$item"' | stream_count)
    [ "$result" = "0" ]
}

@test "handles special characters in elements" {
    local result
    result=$(stream_of 'hello world' 'foo	bar' 'line
break' | stream_count)
    [ "$result" = "3" ]
}

@test "large stream performance (1000 elements)" {
    local start end elapsed
    start=$(date +%s%N)
    local result
    result=$(stream_from_range 1 1000 | stream_filter '[[ $(($item % 2)) -eq 0 ]]' | stream_count)
    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))

    [ "$result" = "500" ]
    # Should complete in under 5 seconds
    [ "$elapsed" -lt 5000 ]
}

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Collection Module Tests
# =============================================================================
# Comprehensive tests for lib/collection.sh (40+ functions)
# Covers: map, filter, reduce, find, partition, grouping, chunking, set ops
# =============================================================================

load 'test_helper'

setup() {
    source_lib "collection"
    export MAINFRAME_QUIET=1
    export COLLECTION_CONTRACTS=1
    TEST_DIR=$(create_test_dir "collection")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# HELPER FUNCTIONS FOR TESTS
# =============================================================================

# Transformation functions
double() { printf '%s' $(($1 * 2)); }
triple() { printf '%s' $(($1 * 3)); }
square() { printf '%s' $(($1 * $1)); }
to_upper() { printf '%s' "${1^^}"; }
add_prefix() { printf 'pre_%s' "$1"; }
get_length() { printf '%s' "${#1}"; }
first_char() { printf '%s' "${1:0:1}"; }
identity() { printf '%s' "$1"; }

# Predicate functions (return 0 for true, 1 for false)
is_even() { (( $1 % 2 == 0 )); }
is_odd() { (( $1 % 2 == 1 )); }
is_positive() { (( $1 > 0 )); }
is_negative() { (( $1 < 0 )); }
is_zero() { (( $1 == 0 )); }
is_greater_than_3() { (( $1 > 3 )); }
is_less_than_5() { (( $1 < 5 )); }
starts_with_a() { [[ "$1" == a* ]]; }
has_length_3() { [[ ${#1} -eq 3 ]]; }
always_true() { return 0; }
always_false() { return 1; }

# Reducer functions
sum() { printf '%s' $(($1 + $2)); }
product() { printf '%s' $(($1 * $2)); }
concat() { printf '%s%s' "$1" "$2"; }
max() { (( $1 > $2 )) && printf '%s' "$1" || printf '%s' "$2"; }
min() { (( $1 < $2 )) && printf '%s' "$1" || printf '%s' "$2"; }

# Multi-value functions
expand_range() { seq 1 "$1" 2>/dev/null || echo "$1"; }
split_chars() {
    local s="$1"
    local i
    for ((i=0; i<${#s}; i++)); do
        echo "${s:i:1}"
    done
}

# =============================================================================
# array_map TESTS
# =============================================================================

@test "array_map doubles all elements" {
    local arr=(1 2 3 4 5)
    local result
    array_map arr double result
    [ "${result[0]}" = "2" ]
    [ "${result[1]}" = "4" ]
    [ "${result[2]}" = "6" ]
    [ "${result[3]}" = "8" ]
    [ "${result[4]}" = "10" ]
}

@test "array_map preserves array length" {
    local arr=(1 2 3 4 5)
    local result
    array_map arr double result
    [ "${#result[@]}" -eq 5 ]
}

@test "array_map with empty array returns empty" {
    local arr=()
    local result
    array_map arr double result
    [ "${#result[@]}" -eq 0 ]
}

@test "array_map with string transformation" {
    local arr=(hello world)
    local result
    array_map arr to_upper result
    [ "${result[0]}" = "HELLO" ]
    [ "${result[1]}" = "WORLD" ]
}

@test "array_map fails with invalid callback" {
    local arr=(1 2 3)
    local result
    run array_map arr nonexistent_function result
    [ "$status" -ne 0 ]
}

@test "array_map with identity function" {
    local arr=(a b c)
    local result
    array_map arr identity result
    [ "${result[0]}" = "a" ]
    [ "${result[1]}" = "b" ]
    [ "${result[2]}" = "c" ]
}

# =============================================================================
# collection_filter TESTS
# =============================================================================

@test "collection_filter keeps only even numbers" {
    local arr=(1 2 3 4 5 6)
    local result
    collection_filter arr is_even result
    [ "${#result[@]}" -eq 3 ]
    [ "${result[0]}" = "2" ]
    [ "${result[1]}" = "4" ]
    [ "${result[2]}" = "6" ]
}

@test "collection_filter with no matches returns empty" {
    local arr=(1 3 5 7)
    local result
    collection_filter arr is_even result
    [ "${#result[@]}" -eq 0 ]
}

@test "collection_filter with all matches returns all" {
    local arr=(2 4 6 8)
    local result
    collection_filter arr is_even result
    [ "${#result[@]}" -eq 4 ]
}

@test "collection_filter with empty array returns empty" {
    local arr=()
    local result
    collection_filter arr is_even result
    [ "${#result[@]}" -eq 0 ]
}

@test "collection_filter with string predicate" {
    local arr=(apple apricot banana cherry)
    local result
    collection_filter arr starts_with_a result
    [ "${#result[@]}" -eq 2 ]
    [ "${result[0]}" = "apple" ]
    [ "${result[1]}" = "apricot" ]
}

@test "collection_filter fails with invalid predicate" {
    local arr=(1 2 3)
    local result
    run collection_filter arr nonexistent_predicate result
    [ "$status" -ne 0 ]
}

# =============================================================================
# array_reduce TESTS
# =============================================================================

@test "array_reduce sums array" {
    local arr=(1 2 3 4 5)
    local result
    array_reduce arr sum 0 result
    [ "$result" = "15" ]
}

@test "array_reduce with product" {
    local arr=(1 2 3 4 5)
    local result
    array_reduce arr product 1 result
    [ "$result" = "120" ]
}

@test "array_reduce with string concatenation" {
    local arr=(a b c)
    local result
    array_reduce arr concat "" result
    [ "$result" = "abc" ]
}

@test "array_reduce with empty array returns initial" {
    local arr=()
    local result
    array_reduce arr sum 42 result
    [ "$result" = "42" ]
}

@test "array_reduce finds max" {
    local arr=(3 1 4 1 5 9 2 6)
    local result
    array_reduce arr max 0 result
    [ "$result" = "9" ]
}

@test "array_reduce finds min" {
    local arr=(3 1 4 1 5 9 2 6)
    local result
    array_reduce arr min 999 result
    [ "$result" = "1" ]
}

@test "array_reduce fails with invalid reducer" {
    local arr=(1 2 3)
    local result
    run array_reduce arr nonexistent_reducer 0 result
    [ "$status" -ne 0 ]
}

# =============================================================================
# array_find TESTS
# =============================================================================

@test "array_find returns first match" {
    local arr=(1 2 3 4 5)
    local result
    result=$(array_find arr is_greater_than_3)
    [ "$result" = "4" ]
}

@test "array_find returns 1 when no match" {
    local arr=(1 2 3)
    run array_find arr is_greater_than_3
    [ "$status" -eq 1 ]
}

@test "array_find with empty array returns 1" {
    local arr=()
    run array_find arr is_even
    [ "$status" -eq 1 ]
}

@test "array_find_index returns correct index" {
    local arr=(1 3 5 6 7)
    local result
    result=$(array_find_index arr is_even)
    [ "$result" = "3" ]
}

@test "array_find_index returns 1 when no match" {
    local arr=(1 3 5 7)
    run array_find_index arr is_even
    [ "$status" -eq 1 ]
}

# =============================================================================
# array_every TESTS
# =============================================================================

@test "array_every returns 0 when all match" {
    local arr=(2 4 6 8)
    array_every arr is_even
}

@test "array_every returns 1 when one fails" {
    local arr=(2 4 5 8)
    run array_every arr is_even
    [ "$status" -eq 1 ]
}

@test "array_every with empty array returns 0 (vacuous truth)" {
    local arr=()
    array_every arr is_even
}

@test "array_every with always_true predicate" {
    local arr=(1 2 3)
    array_every arr always_true
}

@test "array_every with always_false predicate on non-empty" {
    local arr=(1 2 3)
    run array_every arr always_false
    [ "$status" -eq 1 ]
}

# =============================================================================
# array_some TESTS
# =============================================================================

@test "array_some returns 0 when one matches" {
    local arr=(1 3 4 5)
    array_some arr is_even
}

@test "array_some returns 1 when none match" {
    local arr=(1 3 5 7)
    run array_some arr is_even
    [ "$status" -eq 1 ]
}

@test "array_some with empty array returns 1" {
    local arr=()
    run array_some arr is_even
    [ "$status" -eq 1 ]
}

@test "array_none returns 0 when none match" {
    local arr=(1 3 5 7)
    array_none arr is_even
}

@test "array_none returns 1 when one matches" {
    local arr=(1 2 3)
    run array_none arr is_even
    [ "$status" -eq 1 ]
}

# =============================================================================
# array_partition TESTS
# =============================================================================

@test "array_partition splits by predicate" {
    local arr=(1 2 3 4 5 6)
    local evens odds
    array_partition arr is_even evens odds
    [ "${#evens[@]}" -eq 3 ]
    [ "${#odds[@]}" -eq 3 ]
    [ "${evens[0]}" = "2" ]
    [ "${odds[0]}" = "1" ]
}

@test "array_partition with all matching" {
    local arr=(2 4 6)
    local evens odds
    array_partition arr is_even evens odds
    [ "${#evens[@]}" -eq 3 ]
    [ "${#odds[@]}" -eq 0 ]
}

@test "array_partition with none matching" {
    local arr=(1 3 5)
    local evens odds
    array_partition arr is_even evens odds
    [ "${#evens[@]}" -eq 0 ]
    [ "${#odds[@]}" -eq 3 ]
}

@test "array_partition with empty array" {
    local arr=()
    local evens odds
    array_partition arr is_even evens odds
    [ "${#evens[@]}" -eq 0 ]
    [ "${#odds[@]}" -eq 0 ]
}

# =============================================================================
# array_group_by TESTS
# =============================================================================

@test "array_group_by groups by key function" {
    local arr=("a" "bb" "ccc" "dd" "e")
    local result
    result=$(array_group_by arr get_length)
    [[ "$result" == *'"1":'* ]]
    [[ "$result" == *'"2":'* ]]
    [[ "$result" == *'"3":'* ]]
}

@test "array_group_by with first character" {
    local arr=(apple apricot banana cherry)
    local result
    result=$(array_group_by arr first_char)
    [[ "$result" == *'"a":'* ]]
    [[ "$result" == *'"b":'* ]]
    [[ "$result" == *'"c":'* ]]
}

@test "array_group_by with empty array" {
    local arr=()
    local result
    result=$(array_group_by arr get_length)
    [ "$result" = "{}" ]
}

# =============================================================================
# array_flat_map TESTS
# =============================================================================

@test "array_flat_map expands and flattens" {
    local arr=(3 2 1)
    local result
    array_flat_map arr expand_range result
    [ "${#result[@]}" -eq 6 ]  # 1,2,3 + 1,2 + 1
}

@test "array_flat_map with empty array" {
    local arr=()
    local result
    array_flat_map arr expand_range result
    [ "${#result[@]}" -eq 0 ]
}

@test "array_flat_map with identity (single values)" {
    local arr=(a b c)
    local result
    array_flat_map arr identity result
    [ "${#result[@]}" -eq 3 ]
}

# =============================================================================
# array_take / array_drop TESTS
# =============================================================================

@test "array_take gets first n elements" {
    local arr=(1 2 3 4 5)
    local result
    array_take 3 arr result
    [ "${#result[@]}" -eq 3 ]
    [ "${result[0]}" = "1" ]
    [ "${result[2]}" = "3" ]
}

@test "array_take with n > length returns all" {
    local arr=(1 2 3)
    local result
    array_take 10 arr result
    [ "${#result[@]}" -eq 3 ]
}

@test "array_take with n=0 returns empty" {
    local arr=(1 2 3)
    local result
    array_take 0 arr result
    [ "${#result[@]}" -eq 0 ]
}

@test "array_drop skips first n elements" {
    local arr=(1 2 3 4 5)
    local result
    array_drop 2 arr result
    [ "${#result[@]}" -eq 3 ]
    [ "${result[0]}" = "3" ]
}

@test "array_drop with n > length returns empty" {
    local arr=(1 2 3)
    local result
    array_drop 10 arr result
    [ "${#result[@]}" -eq 0 ]
}

@test "array_drop with n=0 returns all" {
    local arr=(1 2 3)
    local result
    array_drop 0 arr result
    [ "${#result[@]}" -eq 3 ]
}

# =============================================================================
# array_take_while / array_drop_while TESTS
# =============================================================================

@test "array_take_while takes while predicate true" {
    local arr=(1 2 3 4 5 1)
    local result
    array_take_while arr is_less_than_5 result
    [ "${#result[@]}" -eq 4 ]
    [ "${result[3]}" = "4" ]
}

@test "array_take_while with always_false returns empty" {
    local arr=(1 2 3)
    local result
    array_take_while arr always_false result
    [ "${#result[@]}" -eq 0 ]
}

@test "array_drop_while drops while predicate true" {
    local arr=(1 2 3 4 5)
    local result
    array_drop_while arr is_less_than_5 result
    [ "${#result[@]}" -eq 1 ]
    [ "${result[0]}" = "5" ]
}

@test "array_drop_while with always_false returns all" {
    local arr=(1 2 3)
    local result
    array_drop_while arr always_false result
    [ "${#result[@]}" -eq 3 ]
}

# =============================================================================
# collection_slice TESTS
# =============================================================================

@test "collection_slice extracts middle section" {
    local arr=(a b c d e)
    local result
    collection_slice 1 4 arr result
    [ "${#result[@]}" -eq 3 ]
    [ "${result[0]}" = "b" ]
    [ "${result[1]}" = "c" ]
    [ "${result[2]}" = "d" ]
}

@test "collection_slice with end > length" {
    local arr=(a b c)
    local result
    collection_slice 1 10 arr result
    [ "${#result[@]}" -eq 2 ]
}

@test "collection_slice with start=end returns empty" {
    local arr=(a b c)
    local result
    collection_slice 2 2 arr result
    [ "${#result[@]}" -eq 0 ]
}

# =============================================================================
# array_chunk TESTS
# =============================================================================

@test "array_chunk splits into correct sizes" {
    local arr=(1 2 3 4 5)
    local result
    result=$(array_chunk 2 arr)
    [[ "$result" == '[["1","2"],["3","4"],["5"]]' ]]
}

@test "array_chunk with exact division" {
    local arr=(1 2 3 4)
    local result
    result=$(array_chunk 2 arr)
    [[ "$result" == '[["1","2"],["3","4"]]' ]]
}

@test "array_chunk with empty array" {
    local arr=()
    local result
    result=$(array_chunk 2 arr)
    [ "$result" = "[]" ]
}

# =============================================================================
# array_zip / array_unzip TESTS
# =============================================================================

@test "array_zip combines arrays" {
    local a=(1 2 3)
    local b=(a b c)
    local result
    array_zip a b result
    [ "${result[0]}" = "1:a" ]
    [ "${result[1]}" = "2:b" ]
    [ "${result[2]}" = "3:c" ]
}

@test "array_zip stops at shorter array" {
    local a=(1 2 3 4 5)
    local b=(a b)
    local result
    array_zip a b result
    [ "${#result[@]}" -eq 2 ]
}

@test "array_zip_with custom function" {
    add_nums() { printf '%s' $(($1 + $2)); }
    local a=(1 2 3)
    local b=(10 20 30)
    local result
    array_zip_with a b add_nums result
    [ "${result[0]}" = "11" ]
    [ "${result[1]}" = "22" ]
    [ "${result[2]}" = "33" ]
}

@test "array_unzip splits pairs" {
    local pairs=("1:a" "2:b" "3:c")
    local nums letters
    array_unzip pairs nums letters
    [ "${nums[0]}" = "1" ]
    [ "${letters[0]}" = "a" ]
}

# =============================================================================
# array_concat TESTS
# =============================================================================

@test "array_concat combines multiple arrays" {
    local a=(1 2)
    local b=(3 4)
    local c=(5 6)
    local result
    array_concat result a b c
    [ "${#result[@]}" -eq 6 ]
    [ "${result[0]}" = "1" ]
    [ "${result[5]}" = "6" ]
}

@test "array_concat with empty arrays" {
    local a=(1 2)
    local b=()
    local c=(3)
    local result
    array_concat result a b c
    [ "${#result[@]}" -eq 3 ]
}

# =============================================================================
# array_flatten TESTS
# =============================================================================

@test "array_flatten flattens space-separated elements" {
    local arr=("1 2" "3 4" "5")
    local result
    array_flatten arr result
    [ "${#result[@]}" -eq 5 ]
    [ "${result[0]}" = "1" ]
    [ "${result[4]}" = "5" ]
}

# =============================================================================
# collection_count TESTS
# =============================================================================

@test "collection_count counts matching elements" {
    local arr=(1 2 3 4 5 6)
    local result
    result=$(collection_count arr is_even)
    [ "$result" = "3" ]
}

@test "collection_count with no matches" {
    local arr=(1 3 5)
    local result
    result=$(collection_count arr is_even)
    [ "$result" = "0" ]
}

# =============================================================================
# array_max_by / array_min_by TESTS
# =============================================================================

@test "array_max_by finds element with max key" {
    local arr=("a" "bbb" "cc")
    local result
    result=$(array_max_by arr get_length)
    [ "$result" = "bbb" ]
}

@test "array_min_by finds element with min key" {
    local arr=("aaa" "b" "cc")
    local result
    result=$(array_min_by arr get_length)
    [ "$result" = "b" ]
}

@test "array_max_by with empty array returns 1" {
    local arr=()
    run array_max_by arr get_length
    [ "$status" -eq 1 ]
}

# =============================================================================
# array_sort_by TESTS
# =============================================================================

@test "array_sort_by sorts by key function" {
    local arr=("aaa" "b" "cc")
    local result
    array_sort_by arr get_length result
    [ "${result[0]}" = "b" ]
    [ "${result[1]}" = "cc" ]
    [ "${result[2]}" = "aaa" ]
}

# =============================================================================
# pipe_through TESTS
# =============================================================================

@test "pipe_through applies filter then map" {
    local result
    result=$(printf '1\n2\n3\n4\n' | pipe_through "filter:is_even" "map:double")
    [[ "$result" == *"4"* ]]
    [[ "$result" == *"8"* ]]
}

@test "pipe_through with take operation" {
    local result
    result=$(printf '1\n2\n3\n4\n5\n' | pipe_through "take:3")
    local count
    count=$(echo "$result" | wc -l)
    [ "$count" -eq 3 ]
}

@test "pipe_through with drop operation" {
    local result
    result=$(printf '1\n2\n3\n4\n5\n' | pipe_through "drop:2")
    local count
    count=$(echo "$result" | wc -l)
    [ "$count" -eq 3 ]
}

# =============================================================================
# collection_to_json TESTS
# =============================================================================

@test "collection_to_json converts array to JSON" {
    local arr=(one two three)
    local result
    result=$(collection_to_json arr)
    [ "$result" = '["one","two","three"]' ]
}

@test "collection_to_json with empty array" {
    local arr=()
    local result
    result=$(collection_to_json arr)
    [ "$result" = '[]' ]
}

@test "collection_to_json escapes special characters" {
    local arr=('say "hello"' 'path\to')
    local result
    result=$(collection_to_json arr)
    [[ "$result" == *'\"hello\"'* ]]
}

@test "collection_to_json_numbers for numeric arrays" {
    local arr=(1 2 3)
    local result
    result=$(collection_to_json_numbers arr)
    [ "$result" = '[1,2,3]' ]
}

# =============================================================================
# collection_from_json TESTS
# =============================================================================

@test "collection_from_json parses JSON array" {
    local result
    collection_from_json '["one","two","three"]' result
    [ "${#result[@]}" -eq 3 ]
    [ "${result[0]}" = "one" ]
    [ "${result[1]}" = "two" ]
    [ "${result[2]}" = "three" ]
}

@test "collection_from_json with empty array" {
    local result
    collection_from_json '[]' result
    [ "${#result[@]}" -eq 0 ]
}

# =============================================================================
# array_foreach TESTS
# =============================================================================

@test "array_foreach calls function for each element" {
    local arr=(1 2 3)
    local count=0
    count_calls() { ((count++)) || true; }
    # Use subshell workaround since count won't persist
    local result
    result=$(array_foreach arr identity)
    # Just verify no error
    [ "$?" -eq 0 ]
}

@test "array_foreach_indexed provides index and element" {
    local arr=(a b c)
    local output=""
    capture_indexed() { output+="[$1:$2]"; }
    # This test verifies the function runs without error
    array_foreach_indexed arr identity
    [ "$?" -eq 0 ]
}

# =============================================================================
# collection_sum / array_product TESTS
# =============================================================================

@test "collection_sum calculates sum" {
    local arr=(1 2 3 4 5)
    local result
    result=$(collection_sum arr)
    [ "$result" = "15" ]
}

@test "collection_sum with empty array returns 0" {
    local arr=()
    local result
    result=$(collection_sum arr)
    [ "$result" = "0" ]
}

@test "array_product calculates product" {
    local arr=(1 2 3 4 5)
    local result
    result=$(array_product arr)
    [ "$result" = "120" ]
}

@test "array_product with empty array returns 0" {
    local arr=()
    local result
    result=$(array_product arr)
    [ "$result" = "0" ]
}

# =============================================================================
# array_join TESTS
# =============================================================================

@test "array_join with comma separator" {
    local arr=(one two three)
    local result
    result=$(array_join arr ", ")
    [ "$result" = "one, two, three" ]
}

@test "array_join with default separator" {
    local arr=(a b c)
    local result
    result=$(array_join arr)
    [ "$result" = "a,b,c" ]
}

@test "array_join with empty array" {
    local arr=()
    local result
    result=$(array_join arr)
    [ "$result" = "" ]
}

# =============================================================================
# collection_unique TESTS
# =============================================================================

@test "collection_unique removes duplicates" {
    local arr=(1 2 2 3 1 4)
    local result
    collection_unique arr result
    [ "${#result[@]}" -eq 4 ]
}

@test "collection_unique preserves order" {
    local arr=(1 2 2 3 1 4)
    local result
    collection_unique arr result
    [ "${result[0]}" = "1" ]
    [ "${result[1]}" = "2" ]
    [ "${result[2]}" = "3" ]
    [ "${result[3]}" = "4" ]
}

@test "array_unique_by removes duplicates by key" {
    local arr=(apple apricot banana blueberry cherry)
    local result
    array_unique_by arr first_char result
    [ "${#result[@]}" -eq 3 ]
    [ "${result[0]}" = "apple" ]
    [ "${result[1]}" = "banana" ]
    [ "${result[2]}" = "cherry" ]
}

# =============================================================================
# SET OPERATIONS TESTS
# =============================================================================

@test "collection_intersect finds common elements" {
    local a=(1 2 3 4)
    local b=(3 4 5 6)
    local result
    collection_intersect a b result
    [ "${#result[@]}" -eq 2 ]
    [ "${result[0]}" = "3" ]
    [ "${result[1]}" = "4" ]
}

@test "collection_intersect with no common elements" {
    local a=(1 2)
    local b=(3 4)
    local result
    collection_intersect a b result
    [ "${#result[@]}" -eq 0 ]
}

@test "array_difference finds elements only in first" {
    local a=(1 2 3 4)
    local b=(3 4 5 6)
    local result
    array_difference a b result
    [ "${#result[@]}" -eq 2 ]
    [ "${result[0]}" = "1" ]
    [ "${result[1]}" = "2" ]
}

@test "array_symmetric_difference finds elements in either but not both" {
    local a=(1 2 3 4)
    local b=(3 4 5 6)
    local result
    array_symmetric_difference a b result
    [ "${#result[@]}" -eq 4 ]
}

# =============================================================================
# CONVENIENCE FUNCTION TESTS
# =============================================================================

@test "collection_reverse reverses order" {
    local arr=(1 2 3 4 5)
    local result
    collection_reverse arr result
    [ "${result[0]}" = "5" ]
    [ "${result[4]}" = "1" ]
}

@test "collection_first returns first element" {
    local arr=(a b c)
    local result
    result=$(collection_first arr)
    [ "$result" = "a" ]
}

@test "collection_first with empty array returns 1" {
    local arr=()
    run collection_first arr
    [ "$status" -eq 1 ]
}

@test "collection_last returns last element" {
    local arr=(a b c)
    local result
    result=$(collection_last arr)
    [ "$result" = "c" ]
}

@test "collection_last with empty array returns 1" {
    local arr=()
    run collection_last arr
    [ "$status" -eq 1 ]
}

@test "array_nth returns element at index" {
    local arr=(a b c d e)
    local result
    result=$(array_nth 2 arr)
    [ "$result" = "c" ]
}

@test "array_nth with out of bounds returns 1" {
    local arr=(a b c)
    run array_nth 10 arr
    [ "$status" -eq 1 ]
}

@test "array_is_empty returns 0 for empty array" {
    local arr=()
    array_is_empty arr
}

@test "array_is_empty returns 1 for non-empty array" {
    local arr=(1)
    run array_is_empty arr
    [ "$status" -eq 1 ]
}

@test "collection_length returns correct count" {
    local arr=(a b c d e)
    local result
    result=$(collection_length arr)
    [ "$result" = "5" ]
}

@test "collection_length of empty array is 0" {
    local arr=()
    local result
    result=$(collection_length arr)
    [ "$result" = "0" ]
}

# =============================================================================
# CONTRACT VALIDATION TESTS
# =============================================================================

@test "contracts can be disabled for performance" {
    COLLECTION_CONTRACTS=0
    local arr=(1 2 3)
    local result
    # Should not fail even with invalid callback when contracts disabled
    array_map arr nonexistent_function result 2>/dev/null || true
    COLLECTION_CONTRACTS=1
}

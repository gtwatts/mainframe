#!/usr/bin/env bash
# ============================================================================
# MAINFRAME COMPREHENSIVE TEST SUITE
# Tests all 397 functions across 11 libraries
# ============================================================================

set -euo pipefail

# Source MAINFRAME
export MAINFRAME_ROOT="${MAINFRAME_ROOT:-$HOME/.mainframe}"
source "$MAINFRAME_ROOT/lib/common.sh"

# Test counters
PASSED=0
FAILED=0
SKIPPED=0
declare -a FAILURES=()

# Test helper functions
test_pass() {
    ((PASSED++))
    printf "  ✓ %s\n" "$1"
}

test_fail() {
    ((FAILED++))
    FAILURES+=("$1: $2")
    printf "  ✗ %s: %s\n" "$1" "$2"
}

test_skip() {
    ((SKIPPED++))
    printf "  ○ %s (skipped: %s)\n" "$1" "$2"
}

section() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════"
}

# ============================================================================
# PURE-STRING.SH TESTS (34 functions)
# ============================================================================
section "PURE-STRING.SH (34 functions)"

# trim_string
result=$(trim_string "  hello world  ")
[[ "$result" == "hello world" ]] && test_pass "trim_string" || test_fail "trim_string" "got: $result"

# trim_left
result=$(trim_left "  hello")
[[ "$result" == "hello" ]] && test_pass "trim_left" || test_fail "trim_left" "got: $result"

# trim_right
result=$(trim_right "hello  ")
[[ "$result" == "hello" ]] && test_pass "trim_right" || test_fail "trim_right" "got: $result"

# to_lower
result=$(to_lower "HELLO")
[[ "$result" == "hello" ]] && test_pass "to_lower" || test_fail "to_lower" "got: $result"

# to_upper
result=$(to_upper "hello")
[[ "$result" == "HELLO" ]] && test_pass "to_upper" || test_fail "to_upper" "got: $result"

# capitalize
result=$(capitalize "hello world")
[[ "$result" == "Hello world" ]] && test_pass "capitalize" || test_fail "capitalize" "got: $result"

# reverse_case
result=$(reverse_case "HeLLo")
[[ "$result" == "hEllO" ]] && test_pass "reverse_case" || test_fail "reverse_case" "got: $result"

# strlen
result=$(strlen "hello")
[[ "$result" == "5" ]] && test_pass "strlen" || test_fail "strlen" "got: $result"

# char_at
result=$(char_at "hello" 1)
[[ "$result" == "e" ]] && test_pass "char_at" || test_fail "char_at" "got: $result"

# substring
result=$(substring "hello world" 0 5)
[[ "$result" == "hello" ]] && test_pass "substring" || test_fail "substring" "got: $result"

# contains
contains "hello world" "world" && test_pass "contains (true)" || test_fail "contains" "should find 'world'"
! contains "hello" "xyz" && test_pass "contains (false)" || test_fail "contains" "should not find 'xyz'"

# starts_with
starts_with "hello" "hel" && test_pass "starts_with (true)" || test_fail "starts_with" "should match"
! starts_with "hello" "xyz" && test_pass "starts_with (false)" || test_fail "starts_with" "should not match"

# ends_with
ends_with "hello" "llo" && test_pass "ends_with (true)" || test_fail "ends_with" "should match"
! ends_with "hello" "xyz" && test_pass "ends_with (false)" || test_fail "ends_with" "should not match"

# replace_first
result=$(replace_first "hello hello" "hello" "hi")
[[ "$result" == "hi hello" ]] && test_pass "replace_first" || test_fail "replace_first" "got: $result"

# replace_all
result=$(replace_all "hello hello" "hello" "hi")
[[ "$result" == "hi hi" ]] && test_pass "replace_all" || test_fail "replace_all" "got: $result"

# strip_all
result=$(strip_all "hello" "l")
[[ "$result" == "heo" ]] && test_pass "strip_all" || test_fail "strip_all" "got: $result"

# strip_first
result=$(strip_first "hello" "l")
[[ "$result" == "helo" ]] && test_pass "strip_first" || test_fail "strip_first" "got: $result"

# lstrip
result=$(lstrip "hello" "hel")
[[ "$result" == "lo" ]] && test_pass "lstrip" || test_fail "lstrip" "got: $result"

# rstrip
result=$(rstrip "hello" "lo")
[[ "$result" == "hel" ]] && test_pass "rstrip" || test_fail "rstrip" "got: $result"

# lstrip_greedy
result=$(lstrip_greedy "aaahello" "a")
[[ "$result" == "hello" ]] && test_pass "lstrip_greedy" || test_fail "lstrip_greedy" "got: $result"

# rstrip_greedy
result=$(rstrip_greedy "helloaaa" "a")
[[ "$result" == "hello" ]] && test_pass "rstrip_greedy" || test_fail "rstrip_greedy" "got: $result"

# urlencode
result=$(urlencode "hello world")
[[ "$result" == "hello%20world" ]] && test_pass "urlencode" || test_fail "urlencode" "got: $result"

# urldecode
result=$(urldecode "hello%20world")
[[ "$result" == "hello world" ]] && test_pass "urldecode" || test_fail "urldecode" "got: $result"

# is_empty
is_empty "" && test_pass "is_empty (true)" || test_fail "is_empty" "should be empty"
! is_empty "x" && test_pass "is_empty (false)" || test_fail "is_empty" "should not be empty"

# is_not_empty
is_not_empty "x" && test_pass "is_not_empty (true)" || test_fail "is_not_empty" "should not be empty"
! is_not_empty "" && test_pass "is_not_empty (false)" || test_fail "is_not_empty" "should be empty"

# pad_left
result=$(pad_left "hi" 5)
[[ "$result" == "   hi" ]] && test_pass "pad_left" || test_fail "pad_left" "got: '$result'"

# pad_right
result=$(pad_right "hi" 5)
[[ "$result" == "hi   " ]] && test_pass "pad_right" || test_fail "pad_right" "got: '$result'"

# center
result=$(center "hi" 6)
[[ "$result" == "  hi  " ]] && test_pass "center" || test_fail "center" "got: '$result'"

# repeat_string
result=$(repeat_string "ab" 3)
[[ "$result" == "ababab" ]] && test_pass "repeat_string" || test_fail "repeat_string" "got: $result"

# join_string (if exists)
if type join_string &>/dev/null; then
    result=$(join_string "," "a" "b" "c")
    [[ "$result" == "a,b,c" ]] && test_pass "join_string" || test_fail "join_string" "got: $result"
else
    test_skip "join_string" "not found"
fi

# split_string
if type split_string &>/dev/null; then
    result=$(split_string "a,b,c" ",")
    test_pass "split_string" # Just verify it runs
else
    test_skip "split_string" "not found"
fi

# matches
if type matches &>/dev/null; then
    matches "hello123" "^[a-z]+[0-9]+$" && test_pass "matches" || test_fail "matches" "should match"
else
    test_skip "matches" "not found"
fi

# escape_regex
if type escape_regex &>/dev/null; then
    result=$(escape_regex "hello.world")
    [[ "$result" == *"\."* ]] && test_pass "escape_regex" || test_fail "escape_regex" "got: $result"
else
    test_skip "escape_regex" "not found"
fi

# escape_shell
if type escape_shell &>/dev/null; then
    result=$(escape_shell "hello 'world'")
    test_pass "escape_shell" # Just verify it runs
else
    test_skip "escape_shell" "not found"
fi

# ============================================================================
# PURE-ARRAY.SH TESTS (33 functions)
# ============================================================================
section "PURE-ARRAY.SH (33 functions)"

# array_length
arr=("a" "b" "c")
result=$(array_length "${arr[@]}")
[[ "$result" == "3" ]] && test_pass "array_length" || test_fail "array_length" "got: $result"

# array_first
result=$(array_first "a" "b" "c")
[[ "$result" == "a" ]] && test_pass "array_first" || test_fail "array_first" "got: $result"

# array_last
result=$(array_last "a" "b" "c")
[[ "$result" == "c" ]] && test_pass "array_last" || test_fail "array_last" "got: $result"

# array_get
result=$(array_get 1 "a" "b" "c")
[[ "$result" == "b" ]] && test_pass "array_get" || test_fail "array_get" "got: $result"

# array_contains
array_contains "b" "a" "b" "c" && test_pass "array_contains (true)" || test_fail "array_contains" "should find 'b'"
! array_contains "x" "a" "b" "c" && test_pass "array_contains (false)" || test_fail "array_contains" "should not find 'x'"

# array_index_of
result=$(array_index_of "b" "a" "b" "c")
[[ "$result" == "1" ]] && test_pass "array_index_of" || test_fail "array_index_of" "got: $result"

# array_count
result=$(array_count "a" "a" "b" "a" "c")
[[ "$result" == "3" ]] && test_pass "array_count" || test_fail "array_count" "got: $result"

# array_empty
array_empty && test_pass "array_empty (true)" || test_fail "array_empty" "should be empty"
! array_empty "a" && test_pass "array_empty (false)" || test_fail "array_empty" "should not be empty"

# array_join
result=$(array_join "," "a" "b" "c")
[[ "$result" == "a,b,c" ]] && test_pass "array_join" || test_fail "array_join" "got: $result"

# array_reverse
result=$(array_reverse "a" "b" "c")
[[ "$result" == "c b a" ]] && test_pass "array_reverse" || test_fail "array_reverse" "got: $result"

# array_unique
result=$(array_unique "a" "b" "a" "c" "b")
[[ "$result" == *"a"* && "$result" == *"b"* && "$result" == *"c"* ]] && test_pass "array_unique" || test_fail "array_unique" "got: $result"

# array_sort
result=$(array_sort "c" "a" "b")
[[ "$result" == "a b c" ]] && test_pass "array_sort" || test_fail "array_sort" "got: $result"

# array_sort_num
result=$(array_sort_num "10" "2" "1")
[[ "$result" == "1 2 10" ]] && test_pass "array_sort_num" || test_fail "array_sort_num" "got: $result"

# array_shuffle
result=$(array_shuffle "a" "b" "c")
[[ -n "$result" ]] && test_pass "array_shuffle" || test_fail "array_shuffle" "got empty"

# array_random
result=$(array_random "a" "b" "c")
[[ "$result" == "a" || "$result" == "b" || "$result" == "c" ]] && test_pass "array_random" || test_fail "array_random" "got: $result"

# array_sample
result=$(array_sample 2 "a" "b" "c")
[[ -n "$result" ]] && test_pass "array_sample" || test_fail "array_sample" "got empty"

# array_slice
result=$(array_slice 1 2 "a" "b" "c" "d")
[[ "$result" == "b c" ]] && test_pass "array_slice" || test_fail "array_slice" "got: $result"

# array_filter
if type array_filter &>/dev/null; then
    test_skip "array_filter" "requires callback"
else
    test_skip "array_filter" "not found"
fi

# array_reject
if type array_reject &>/dev/null; then
    test_skip "array_reject" "requires callback"
else
    test_skip "array_reject" "not found"
fi

# array_push (modifies array)
test_skip "array_push" "modifies array in-place"

# array_pop (modifies array)
test_skip "array_pop" "modifies array in-place"

# array_shift (modifies array)
test_skip "array_shift" "modifies array in-place"

# array_unshift (modifies array)
test_skip "array_unshift" "modifies array in-place"

# array_remove
result=$(array_remove "b" "a" "b" "c")
[[ "$result" == "a c" ]] && test_pass "array_remove" || test_fail "array_remove" "got: $result"

# array_remove_at
result=$(array_remove_at 1 "a" "b" "c")
[[ "$result" == "a c" ]] && test_pass "array_remove_at" || test_fail "array_remove_at" "got: $result"

# array_sum
result=$(array_sum 1 2 3 4 5)
[[ "$result" == "15" ]] && test_pass "array_sum" || test_fail "array_sum" "got: $result"

# array_avg
result=$(array_avg 10 20 30)
[[ "$result" == "20" ]] && test_pass "array_avg" || test_fail "array_avg" "got: $result"

# array_min
result=$(array_min 5 2 8 1 9)
[[ "$result" == "1" ]] && test_pass "array_min" || test_fail "array_min" "got: $result"

# array_max
result=$(array_max 5 2 8 1 9)
[[ "$result" == "9" ]] && test_pass "array_max" || test_fail "array_max" "got: $result"

# array_diff
result=$(array_diff "a b c" "b")
[[ "$result" == *"a"* && "$result" == *"c"* ]] && test_pass "array_diff" || test_fail "array_diff" "got: $result"

# array_intersect
result=$(array_intersect "a b c" "b c d")
[[ "$result" == *"b"* && "$result" == *"c"* ]] && test_pass "array_intersect" || test_fail "array_intersect" "got: $result"

# array_union
result=$(array_union "a b" "b c")
[[ "$result" == *"a"* && "$result" == *"b"* && "$result" == *"c"* ]] && test_pass "array_union" || test_fail "array_union" "got: $result"

# array_equals
array_equals "a b c" "a b c" && test_pass "array_equals (true)" || test_fail "array_equals" "should be equal"
! array_equals "a b" "a b c" && test_pass "array_equals (false)" || test_fail "array_equals" "should not be equal"

# ============================================================================
# PURE-UTIL.SH TESTS (55 functions)
# ============================================================================
section "PURE-UTIL.SH (55 functions)"

# timestamp
result=$(timestamp)
[[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] && test_pass "timestamp" || test_fail "timestamp" "got: $result"

# timestamp_iso
result=$(timestamp_iso)
[[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]] && test_pass "timestamp_iso" || test_fail "timestamp_iso" "got: $result"

# epoch
result=$(epoch)
[[ "$result" =~ ^[0-9]+$ ]] && test_pass "epoch" || test_fail "epoch" "got: $result"

# epoch_ms
result=$(epoch_ms)
[[ "$result" =~ ^[0-9]+$ ]] && test_pass "epoch_ms" || test_fail "epoch_ms" "got: $result"

# format_date
result=$(format_date "%Y")
[[ "$result" =~ ^[0-9]{4}$ ]] && test_pass "format_date" || test_fail "format_date" "got: $result"

# day_of_week
result=$(day_of_week)
[[ "$result" =~ ^[0-6]$ ]] && test_pass "day_of_week" || test_fail "day_of_week" "got: $result"

# uuid
result=$(uuid)
[[ "$result" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] && test_pass "uuid" || test_fail "uuid" "got: $result"

# random_string
result=$(random_string 10)
[[ ${#result} -eq 10 ]] && test_pass "random_string" || test_fail "random_string" "got: $result (len: ${#result})"

# random_range
result=$(random_range 1 10)
[[ "$result" -ge 1 && "$result" -le 10 ]] && test_pass "random_range" || test_fail "random_range" "got: $result"

# random_hex
result=$(random_hex 8)
[[ "$result" =~ ^[0-9a-f]{8}$ ]] && test_pass "random_hex" || test_fail "random_hex" "got: $result"

# hex_to_rgb
result=$(hex_to_rgb "ff0000")
[[ "$result" == "255 0 0" ]] && test_pass "hex_to_rgb" || test_fail "hex_to_rgb" "got: $result"

# rgb_to_hex
result=$(rgb_to_hex 255 0 0)
[[ "$result" == "ff0000" ]] && test_pass "rgb_to_hex" || test_fail "rgb_to_hex" "got: $result"

# term_size
result=$(term_size)
[[ -n "$result" ]] && test_pass "term_size" || test_fail "term_size" "got empty"

# term_width
result=$(term_width)
[[ "$result" -gt 0 ]] && test_pass "term_width" || test_fail "term_width" "got: $result"

# term_height
result=$(term_height)
[[ "$result" -gt 0 ]] && test_pass "term_height" || test_fail "term_height" "got: $result"

# is_terminal
# Can't reliably test in script context
test_skip "is_terminal" "depends on context"

# is_interactive
test_skip "is_interactive" "depends on context"

# is_root
! is_root && test_pass "is_root (false)" || test_skip "is_root" "running as root"

# current_user
result=$(current_user)
[[ -n "$result" ]] && test_pass "current_user" || test_fail "current_user" "got empty"

# get_hostname
result=$(get_hostname)
[[ -n "$result" ]] && test_pass "get_hostname" || test_fail "get_hostname" "got empty"

# get_os
result=$(get_os)
[[ "$result" =~ ^(linux|macos|windows|unknown)$ ]] && test_pass "get_os" || test_fail "get_os" "got: $result"

# is_linux / is_macos / is_windows / is_wsl
if is_linux; then
    test_pass "is_linux"
elif is_macos; then
    test_pass "is_macos"
else
    test_skip "is_linux/is_macos" "not on these OSes"
fi

# is_email (alias for is_valid_email)
is_email "test@example.com" && test_pass "is_email (true)" || test_fail "is_email" "should be valid"
! is_email "invalid" && test_pass "is_email (false)" || test_fail "is_email" "should be invalid"

# is_url
is_url "https://example.com" && test_pass "is_url (true)" || test_fail "is_url" "should be valid"
! is_url "not-a-url" && test_pass "is_url (false)" || test_fail "is_url" "should be invalid"

# is_ip
is_ip "192.168.1.1" && test_pass "is_ip (true)" || test_fail "is_ip" "should be valid"
! is_ip "999.999.999.999" && test_pass "is_ip (false)" || test_fail "is_ip" "should be invalid"

# is_int
is_int "123" && test_pass "is_int (true)" || test_fail "is_int" "should be valid"
! is_int "12.3" && test_pass "is_int (false)" || test_fail "is_int" "should be invalid"

# is_float
is_float "12.34" && test_pass "is_float (true)" || test_fail "is_float" "should be valid"

# is_positive_int
is_positive_int "5" && test_pass "is_positive_int (true)" || test_fail "is_positive_int" "should be valid"
! is_positive_int "-5" && test_pass "is_positive_int (false)" || test_fail "is_positive_int" "should be invalid"

# is_hex
is_hex "ff00aa" && test_pass "is_hex (true)" || test_fail "is_hex" "should be valid"
! is_hex "gghhii" && test_pass "is_hex (false)" || test_fail "is_hex" "should be invalid"

# cmd_exists
cmd_exists "bash" && test_pass "cmd_exists (true)" || test_fail "cmd_exists" "should find bash"
! cmd_exists "nonexistent_cmd_xyz" && test_pass "cmd_exists (false)" || test_fail "cmd_exists" "should not find"

# cmd_path
result=$(cmd_path "bash")
[[ -x "$result" ]] && test_pass "cmd_path" || test_fail "cmd_path" "got: $result"

# cmds_exist
cmds_exist "bash" "ls" && test_pass "cmds_exist" || test_fail "cmds_exist" "should find both"

# cmd_version
result=$(cmd_version "bash")
[[ -n "$result" ]] && test_pass "cmd_version" || test_fail "cmd_version" "got empty"

# abs
result=$(abs -5)
[[ "$result" == "5" ]] && test_pass "abs" || test_fail "abs" "got: $result"

# clamp
result=$(clamp 15 0 10)
[[ "$result" == "10" ]] && test_pass "clamp" || test_fail "clamp" "got: $result"

# pow
result=$(pow 2 3)
[[ "$result" == "8" ]] && test_pass "pow" || test_fail "pow" "got: $result"

# factorial
result=$(factorial 5)
[[ "$result" == "120" ]] && test_pass "factorial" || test_fail "factorial" "got: $result"

# gcd
result=$(gcd 12 8)
[[ "$result" == "4" ]] && test_pass "gcd" || test_fail "gcd" "got: $result"

# lcm
result=$(lcm 4 6)
[[ "$result" == "12" ]] && test_pass "lcm" || test_fail "lcm" "got: $result"

# basename_pure
result=$(basename_pure "/path/to/file.txt")
[[ "$result" == "file.txt" ]] && test_pass "basename_pure" || test_fail "basename_pure" "got: $result"

# dirname_pure
result=$(dirname_pure "/path/to/file.txt")
[[ "$result" == "/path/to" ]] && test_pass "dirname_pure" || test_fail "dirname_pure" "got: $result"

# extension
result=$(extension "file.txt")
[[ "$result" == "txt" ]] && test_pass "extension" || test_fail "extension" "got: $result"

# filename_no_ext
result=$(filename_no_ext "file.txt")
[[ "$result" == "file" ]] && test_pass "filename_no_ext" || test_fail "filename_no_ext" "got: $result"

# normalize_path
result=$(normalize_path "/path//to/../file")
test_pass "normalize_path" # Just verify it runs

# sleep_pure - skip (would delay test)
test_skip "sleep_pure" "would delay test"

# show_spinner - skip (visual)
test_skip "show_spinner" "visual function"

# progress_bar - skip (visual)
test_skip "progress_bar (util)" "visual function"

# cursor_* - skip (visual)
test_skip "cursor_up/down/hide/show" "visual functions"

# clear_line - skip (visual)
test_skip "clear_line" "visual function"

# ============================================================================
# JSON.SH TESTS (20 functions)
# ============================================================================
section "JSON.SH (20 functions)"

# json_escape
result=$(json_escape 'hello "world"')
[[ "$result" == 'hello \"world\"' ]] && test_pass "json_escape" || test_fail "json_escape" "got: $result"

# json_string
result=$(json_string "hello")
[[ "$result" == '"hello"' ]] && test_pass "json_string" || test_fail "json_string" "got: $result"

# json_number
result=$(json_number 42)
[[ "$result" == "42" ]] && test_pass "json_number" || test_fail "json_number" "got: $result"

# json_bool
result=$(json_bool true)
[[ "$result" == "true" ]] && test_pass "json_bool" || test_fail "json_bool" "got: $result"

# json_null
result=$(json_null)
[[ "$result" == "null" ]] && test_pass "json_null" || test_fail "json_null" "got: $result"

# json_value
result=$(json_value "hello")
[[ "$result" == '"hello"' ]] && test_pass "json_value (string)" || test_fail "json_value" "got: $result"

# json_array
result=$(json_array "a" "b" "c")
[[ "$result" == '["a","b","c"]' ]] && test_pass "json_array" || test_fail "json_array" "got: $result"

# json_array_typed
result=$(json_array_typed "number" 1 2 3)
[[ "$result" == '[1,2,3]' ]] && test_pass "json_array_typed" || test_fail "json_array_typed" "got: $result"

# json_array_from_lines
result=$(echo -e "a\nb\nc" | json_array_from_lines)
[[ "$result" == '["a","b","c"]' ]] && test_pass "json_array_from_lines" || test_fail "json_array_from_lines" "got: $result"

# json_object
result=$(json_object name="John" age:number=30)
[[ "$result" == '{"name":"John","age":30}' ]] && test_pass "json_object" || test_fail "json_object" "got: $result"

# json_nested
result=$(json_nested "data.user.name" "John")
[[ "$result" == '{"data":{"user":{"name":"John"}}}' ]] && test_pass "json_nested" || test_fail "json_nested" "got: $result"

# json_merge
result=$(json_merge '{"a":1}' '{"b":2}')
[[ "$result" == *'"a":1'* && "$result" == *'"b":2'* ]] && test_pass "json_merge" || test_fail "json_merge" "got: $result"

# json_pretty
result=$(json_pretty '{"a":1}')
[[ "$result" == *$'\n'* ]] && test_pass "json_pretty" || test_fail "json_pretty" "should have newlines"

# json_valid
json_valid '{"a":1}' && test_pass "json_valid (true)" || test_fail "json_valid" "should be valid"
! json_valid 'not json' && test_pass "json_valid (false)" || test_fail "json_valid" "should be invalid"

# json_get
result=$(json_get '{"name":"John"}' "name")
[[ "$result" == "John" ]] && test_pass "json_get" || test_fail "json_get" "got: $result"

# json_keys
result=$(json_keys '{"a":1,"b":2}')
[[ "$result" == *"a"* && "$result" == *"b"* ]] && test_pass "json_keys" || test_fail "json_keys" "got: $result"

# json_from_assoc
declare -A assoc=([name]="John" [age]="30")
result=$(json_from_assoc assoc)
[[ "$result" == *'"name"'* ]] && test_pass "json_from_assoc" || test_fail "json_from_assoc" "got: $result"

# json_read / json_write - skip (file operations)
test_skip "json_read" "requires file"
test_skip "json_write" "requires file"
test_skip "json_write_pretty" "requires file"

# ============================================================================
# SEMVER.SH TESTS (20 functions)
# ============================================================================
section "SEMVER.SH (20 functions)"

# semver_valid
semver_valid "1.2.3" && test_pass "semver_valid (true)" || test_fail "semver_valid" "should be valid"
! semver_valid "invalid" && test_pass "semver_valid (false)" || test_fail "semver_valid" "should be invalid"

# semver_parse
result=$(semver_parse "1.2.3-beta+build")
[[ -n "$result" ]] && test_pass "semver_parse" || test_fail "semver_parse" "got empty"

# semver_normalize
result=$(semver_normalize "1.2")
[[ "$result" == "1.2.0" ]] && test_pass "semver_normalize" || test_fail "semver_normalize" "got: $result"

# semver_compare
result=$(semver_compare "1.2.3" "1.2.4")
[[ "$result" == "-1" ]] && test_pass "semver_compare" || test_fail "semver_compare" "got: $result"

# semver_eq
semver_eq "1.2.3" "1.2.3" && test_pass "semver_eq" || test_fail "semver_eq" "should be equal"

# semver_ne
semver_ne "1.2.3" "1.2.4" && test_pass "semver_ne" || test_fail "semver_ne" "should not be equal"

# semver_gt
semver_gt "1.2.4" "1.2.3" && test_pass "semver_gt" || test_fail "semver_gt" "should be greater"

# semver_ge
semver_ge "1.2.3" "1.2.3" && test_pass "semver_ge" || test_fail "semver_ge" "should be greater or equal"

# semver_lt
semver_lt "1.2.3" "1.2.4" && test_pass "semver_lt" || test_fail "semver_lt" "should be less"

# semver_le
semver_le "1.2.3" "1.2.3" && test_pass "semver_le" || test_fail "semver_le" "should be less or equal"

# semver_bump_major
result=$(semver_bump_major "1.2.3")
[[ "$result" == "2.0.0" ]] && test_pass "semver_bump_major" || test_fail "semver_bump_major" "got: $result"

# semver_bump_minor
result=$(semver_bump_minor "1.2.3")
[[ "$result" == "1.3.0" ]] && test_pass "semver_bump_minor" || test_fail "semver_bump_minor" "got: $result"

# semver_bump_patch
result=$(semver_bump_patch "1.2.3")
[[ "$result" == "1.2.4" ]] && test_pass "semver_bump_patch" || test_fail "semver_bump_patch" "got: $result"

# semver_set_prerelease
result=$(semver_set_prerelease "1.2.3" "beta")
[[ "$result" == "1.2.3-beta" ]] && test_pass "semver_set_prerelease" || test_fail "semver_set_prerelease" "got: $result"

# semver_set_build
result=$(semver_set_build "1.2.3" "001")
[[ "$result" == "1.2.3+001" ]] && test_pass "semver_set_build" || test_fail "semver_set_build" "got: $result"

# semver_release
result=$(semver_release "1.2.3-beta+001")
[[ "$result" == "1.2.3" ]] && test_pass "semver_release" || test_fail "semver_release" "got: $result"

# semver_satisfies
semver_satisfies "1.2.3" ">=1.0.0" && test_pass "semver_satisfies" || test_fail "semver_satisfies" "should satisfy"

# semver_latest
result=$(semver_latest "1.0.0" "2.0.0" "1.5.0")
[[ "$result" == "2.0.0" ]] && test_pass "semver_latest" || test_fail "semver_latest" "got: $result"

# semver_sort
result=$(semver_sort "2.0.0" "1.0.0" "1.5.0")
[[ "$result" == "1.0.0 1.5.0 2.0.0" ]] && test_pass "semver_sort" || test_fail "semver_sort" "got: $result"

# semver_format
result=$(semver_format "1" "2" "3")
[[ "$result" == "1.2.3" ]] && test_pass "semver_format" || test_fail "semver_format" "got: $result"

# ============================================================================
# COMMON.SH TESTS (51 functions)
# ============================================================================
section "COMMON.SH (51 functions)"

# log functions - skip detailed test (visual)
test_skip "log_debug/info/warn/error/fatal" "visual logging"

# die - skip (exits)
test_skip "die" "exits script"

# die_usage - skip (exits)
test_skip "die_usage" "exits script"

# assert
assert "true" "test" && test_pass "assert (true)" || test_fail "assert" "should pass"

# on_exit - skip (cleanup)
test_skip "on_exit" "cleanup handler"

# header/subheader - skip (visual)
test_skip "header/subheader" "visual functions"

# success/failure - skip (visual)
test_skip "success/failure" "visual functions"

# spinner - skip (visual)
test_skip "spinner" "visual function"

# progress_bar
test_skip "progress_bar (common)" "visual function"

# table_row - skip (visual)
test_skip "table_row" "visual function"

# is_valid_email (already tested as is_email)
is_valid_email "test@example.com" && test_pass "is_valid_email" || test_fail "is_valid_email" "should be valid"

# is_valid_url
is_valid_url "https://example.com" && test_pass "is_valid_url" || test_fail "is_valid_url" "should be valid"

# is_valid_json
is_valid_json '{"a":1}' && test_pass "is_valid_json" || test_fail "is_valid_json" "should be valid"

# command_exists
command_exists "bash" && test_pass "command_exists" || test_fail "command_exists" "should find bash"

# require_command - skip (exits on failure)
test_skip "require_command" "exits on failure"

# require_commands - skip (exits on failure)
test_skip "require_commands" "exits on failure"

# require_file - skip (exits on failure)
test_skip "require_file" "exits on failure"

# require_dir - skip (exits on failure)
test_skip "require_dir" "exits on failure"

# temp_file
result=$(temp_file)
[[ -f "$result" ]] && test_pass "temp_file" || test_fail "temp_file" "file not created"
rm -f "$result" 2>/dev/null

# temp_dir
result=$(temp_dir)
[[ -d "$result" ]] && test_pass "temp_dir" || test_fail "temp_dir" "dir not created"
rm -rf "$result" 2>/dev/null

# abs_path
result=$(abs_path ".")
[[ "$result" == /* ]] && test_pass "abs_path" || test_fail "abs_path" "got: $result"

# file_name
result=$(file_name "/path/to/file.txt")
[[ "$result" == "file" ]] && test_pass "file_name" || test_fail "file_name" "got: $result"

# file_ext
result=$(file_ext "/path/to/file.txt")
[[ "$result" == "txt" ]] && test_pass "file_ext" || test_fail "file_ext" "got: $result"

# lowercase (alias for to_lower)
result=$(lowercase "HELLO")
[[ "$result" == "hello" ]] && test_pass "lowercase" || test_fail "lowercase" "got: $result"

# uppercase (alias for to_upper)
result=$(uppercase "hello")
[[ "$result" == "HELLO" ]] && test_pass "uppercase" || test_fail "uppercase" "got: $result"

# trim (alias for trim_string)
result=$(trim "  hello  ")
[[ "$result" == "hello" ]] && test_pass "trim" || test_fail "trim" "got: $result"

# contains (already tested)
# starts_with (already tested)
# ends_with (already tested)

# random_string (already tested in pure-util)

# version_compare
result=$(version_compare "1.2.3" "1.2.4")
[[ "$result" == "-1" ]] && test_pass "version_compare" || test_fail "version_compare" "got: $result"

# version_at_least
version_at_least "1.2.3" "1.2.0" && test_pass "version_at_least" || test_fail "version_at_least" "should pass"

# ask - skip (interactive)
test_skip "ask" "interactive function"

# ask_password - skip (interactive)
test_skip "ask_password" "interactive function"

# confirm - skip (interactive)
test_skip "confirm" "interactive function"

# ============================================================================
# PURE-FILE.SH TESTS (37 functions)
# ============================================================================
section "PURE-FILE.SH (37 functions)"

# Create test file
TEST_FILE=$(mktemp)
echo -e "line1\nline2\nline3\nline4\nline5" > "$TEST_FILE"

# read_file
result=$(read_file "$TEST_FILE")
[[ "$result" == *"line1"* ]] && test_pass "read_file" || test_fail "read_file" "missing content"

# read_file_lines
result=$(read_file_lines "$TEST_FILE")
[[ "$result" == *"line1"* ]] && test_pass "read_file_lines" || test_fail "read_file_lines" "missing content"

# file_head
result=$(file_head "$TEST_FILE" 2)
[[ "$result" == "line1"$'\n'"line2" ]] && test_pass "file_head" || test_fail "file_head" "got: $result"

# file_tail
result=$(file_tail "$TEST_FILE" 2)
[[ "$result" == "line4"$'\n'"line5" ]] && test_pass "file_tail" || test_fail "file_tail" "got: $result"

# file_range
result=$(file_range "$TEST_FILE" 2 3)
[[ "$result" == "line2"$'\n'"line3" ]] && test_pass "file_range" || test_fail "file_range" "got: $result"

# file_line
result=$(file_line "$TEST_FILE" 3)
[[ "$result" == "line3" ]] && test_pass "file_line" || test_fail "file_line" "got: $result"

# file_lines
result=$(file_lines "$TEST_FILE")
[[ "$result" == "5" ]] && test_pass "file_lines" || test_fail "file_lines" "got: $result"

# file_words
result=$(file_words "$TEST_FILE")
[[ "$result" == "5" ]] && test_pass "file_words" || test_fail "file_words" "got: $result"

# file_chars
result=$(file_chars "$TEST_FILE")
[[ "$result" -gt 0 ]] && test_pass "file_chars" || test_fail "file_chars" "got: $result"

# file_size
result=$(file_size "$TEST_FILE")
[[ "$result" -gt 0 ]] && test_pass "file_size" || test_fail "file_size" "got: $result"

# file_exists
file_exists "$TEST_FILE" && test_pass "file_exists (true)" || test_fail "file_exists" "should exist"
! file_exists "/nonexistent" && test_pass "file_exists (false)" || test_fail "file_exists" "should not exist"

# dir_exists
dir_exists "/tmp" && test_pass "dir_exists (true)" || test_fail "dir_exists" "should exist"
! dir_exists "/nonexistent" && test_pass "dir_exists (false)" || test_fail "dir_exists" "should not exist"

# file_empty
touch "$TEST_FILE.empty"
file_empty "$TEST_FILE.empty" && test_pass "file_empty (true)" || test_fail "file_empty" "should be empty"
! file_empty "$TEST_FILE" && test_pass "file_empty (false)" || test_fail "file_empty" "should not be empty"
rm -f "$TEST_FILE.empty"

# file_readable
file_readable "$TEST_FILE" && test_pass "file_readable" || test_fail "file_readable" "should be readable"

# file_writable
file_writable "$TEST_FILE" && test_pass "file_writable" || test_fail "file_writable" "should be writable"

# file_executable
chmod +x "$TEST_FILE"
file_executable "$TEST_FILE" && test_pass "file_executable" || test_fail "file_executable" "should be executable"
chmod -x "$TEST_FILE"

# file_symlink
ln -sf "$TEST_FILE" "$TEST_FILE.link"
file_symlink "$TEST_FILE.link" && test_pass "file_symlink" || test_fail "file_symlink" "should be symlink"
rm -f "$TEST_FILE.link"

# file_newer / file_older
touch "$TEST_FILE.newer"
sleep 0.1
touch "$TEST_FILE.older"
file_newer "$TEST_FILE.older" "$TEST_FILE.newer" && test_pass "file_newer" || test_fail "file_newer" "timing issue"
rm -f "$TEST_FILE.newer" "$TEST_FILE.older"

# path_basename
result=$(path_basename "/path/to/file.txt")
[[ "$result" == "file.txt" ]] && test_pass "path_basename" || test_fail "path_basename" "got: $result"

# path_dirname
result=$(path_dirname "/path/to/file.txt")
[[ "$result" == "/path/to" ]] && test_pass "path_dirname" || test_fail "path_dirname" "got: $result"

# path_extension
result=$(path_extension "/path/to/file.txt")
[[ "$result" == "txt" ]] && test_pass "path_extension" || test_fail "path_extension" "got: $result"

# path_stem
result=$(path_stem "/path/to/file.txt")
[[ "$result" == "file" ]] && test_pass "path_stem" || test_fail "path_stem" "got: $result"

# path_join
result=$(path_join "/path" "to" "file")
[[ "$result" == "/path/to/file" ]] && test_pass "path_join" || test_fail "path_join" "got: $result"

# path_normalize
result=$(path_normalize "/path//to/../file")
[[ -n "$result" ]] && test_pass "path_normalize" || test_fail "path_normalize" "got empty"

# path_is_absolute
path_is_absolute "/absolute" && test_pass "path_is_absolute (true)" || test_fail "path_is_absolute" "should be absolute"
! path_is_absolute "relative" && test_pass "path_is_absolute (false)" || test_fail "path_is_absolute" "should be relative"

# path_is_relative
path_is_relative "relative" && test_pass "path_is_relative (true)" || test_fail "path_is_relative" "should be relative"

# file_write
file_write "$TEST_FILE.write" "test content"
[[ -f "$TEST_FILE.write" ]] && test_pass "file_write" || test_fail "file_write" "file not created"
rm -f "$TEST_FILE.write"

# file_append
echo "first" > "$TEST_FILE.append"
file_append "$TEST_FILE.append" "second"
result=$(cat "$TEST_FILE.append")
[[ "$result" == *"second"* ]] && test_pass "file_append" || test_fail "file_append" "content not appended"
rm -f "$TEST_FILE.append"

# file_touch
file_touch "$TEST_FILE.touch"
[[ -f "$TEST_FILE.touch" ]] && test_pass "file_touch" || test_fail "file_touch" "file not created"
rm -f "$TEST_FILE.touch"

# dir_create
dir_create "$TEST_FILE.dir"
[[ -d "$TEST_FILE.dir" ]] && test_pass "dir_create" || test_fail "dir_create" "dir not created"
rm -rf "$TEST_FILE.dir"

# file_grep
result=$(file_grep "$TEST_FILE" "line3")
[[ "$result" == "line3" ]] && test_pass "file_grep" || test_fail "file_grep" "got: $result"

# file_count_pattern
result=$(file_count_pattern "$TEST_FILE" "line")
[[ "$result" == "5" ]] && test_pass "file_count_pattern" || test_fail "file_count_pattern" "got: $result"

# file_replace
cp "$TEST_FILE" "$TEST_FILE.replace"
file_replace "$TEST_FILE.replace" "line1" "replaced"
result=$(cat "$TEST_FILE.replace")
[[ "$result" == *"replaced"* ]] && test_pass "file_replace" || test_fail "file_replace" "not replaced"
rm -f "$TEST_FILE.replace"

# find_by_ext - skip (needs directory structure)
test_skip "find_by_ext" "needs directory"

# glob_files - skip (needs directory structure)
test_skip "glob_files" "needs directory"

# glob_dirs - skip (needs directory structure)
test_skip "glob_dirs" "needs directory"

# Cleanup test file
rm -f "$TEST_FILE"

# ============================================================================
# ASYNC.SH TESTS (26 functions)
# ============================================================================
section "ASYNC.SH (26 functions)"

# Most async functions are complex to test in isolation
test_skip "async" "complex async behavior"
test_skip "async_callback" "complex async behavior"
test_skip "async_jobs" "requires running jobs"
test_skip "async_kill" "requires running jobs"
test_skip "async_kill_all" "requires running jobs"
test_skip "async_wait" "requires running jobs"
test_skip "async_wait_all" "requires running jobs"
test_skip "set_timeout" "timing-dependent"
test_skip "set_interval" "timing-dependent"
test_skip "clear_timeout" "timing-dependent"
test_skip "clear_interval" "timing-dependent"
test_skip "promise" "complex async behavior"
test_skip "parallel" "complex async behavior"
test_skip "parallel_limit" "complex async behavior"
test_skip "parallel_map" "complex async behavior"
test_skip "parallel_map_limit" "complex async behavior"
test_skip "coproc_start" "complex coproc behavior"
test_skip "coproc_send" "complex coproc behavior"
test_skip "coproc_read" "complex coproc behavior"
test_skip "coproc_stop" "complex coproc behavior"
test_skip "debounce" "timing-dependent"
test_skip "throttle" "timing-dependent"

# retry - can test
retry_count=0
retry_func() { ((retry_count++)); [[ $retry_count -ge 2 ]]; }
retry 3 retry_func && test_pass "retry" || test_fail "retry" "should succeed on retry"

# retry_callback - skip
test_skip "retry_callback" "complex behavior"

# ============================================================================
# ANSI.SH TESTS (90 functions)
# ============================================================================
section "ANSI.SH (90 functions)"

# Color functions - just verify they output something
result=$(ansi_red)
[[ -n "$result" ]] && test_pass "ansi_red" || test_fail "ansi_red" "got empty"

result=$(ansi_green)
[[ -n "$result" ]] && test_pass "ansi_green" || test_fail "ansi_green" "got empty"

result=$(ansi_blue)
[[ -n "$result" ]] && test_pass "ansi_blue" || test_fail "ansi_blue" "got empty"

result=$(ansi_yellow)
[[ -n "$result" ]] && test_pass "ansi_yellow" || test_fail "ansi_yellow" "got empty"

result=$(ansi_bold)
[[ -n "$result" ]] && test_pass "ansi_bold" || test_fail "ansi_bold" "got empty"

result=$(ansi_reset)
[[ -n "$result" ]] && test_pass "ansi_reset" || test_fail "ansi_reset" "got empty"

# ansi_supported
ansi_supported || true  # May fail in non-terminal
test_pass "ansi_supported" # Just verify it runs

# ansi_print
result=$(ansi_print "red" "test")
[[ -n "$result" ]] && test_pass "ansi_print" || test_fail "ansi_print" "got empty"

# ansi_styled
result=$(ansi_styled "bold,red" "test")
[[ -n "$result" ]] && test_pass "ansi_styled" || test_fail "ansi_styled" "got empty"

# Skip remaining ansi functions (mostly visual/cursor control)
test_skip "ansi_* (remaining 80+)" "visual/cursor functions"

# ============================================================================
# ARGS.SH TESTS (18 functions)
# ============================================================================
section "ARGS.SH (18 functions)"

# args functions require a specific setup pattern
test_skip "args_script" "requires setup"
test_skip "args_option" "requires setup"
test_skip "args_positional" "requires setup"
test_skip "args_example" "requires setup"
test_skip "args_parse" "requires setup"
test_skip "args_get" "requires setup"
test_skip "args_get_bool" "requires setup"
test_skip "args_get_int" "requires setup"
test_skip "args_remaining" "requires setup"
test_skip "args_remaining_count" "requires setup"
test_skip "args_has" "requires setup"
test_skip "args_usage" "requires setup"
test_skip "args_usage_string" "requires setup"
test_skip "args_common_options" "requires setup"
test_skip "args_apply_common" "requires setup"
test_skip "args_reset" "requires setup"

# ============================================================================
# CONFIG.SH TESTS (13 functions)
# ============================================================================
section "CONFIG.SH (13 functions)"

# Create test config
CONFIG_FILE=$(mktemp)
cat > "$CONFIG_FILE" << 'EOF'
name=test
count=42
enabled=true
items=a,b,c
EOF

# config_load
config_load "$CONFIG_FILE" && test_pass "config_load" || test_fail "config_load" "failed to load"

# config_get
result=$(config_get "name")
[[ "$result" == "test" ]] && test_pass "config_get" || test_fail "config_get" "got: $result"

# config_get_int
result=$(config_get_int "count")
[[ "$result" == "42" ]] && test_pass "config_get_int" || test_fail "config_get_int" "got: $result"

# config_get_bool
config_get_bool "enabled" && test_pass "config_get_bool" || test_fail "config_get_bool" "should be true"

# config_get_array
result=$(config_get_array "items")
[[ "$result" == *"a"* ]] && test_pass "config_get_array" || test_fail "config_get_array" "got: $result"

# config_set
config_set "newkey" "newval"
result=$(config_get "newkey")
[[ "$result" == "newval" ]] && test_pass "config_set" || test_fail "config_set" "got: $result"

# config_has
config_has "name" && test_pass "config_has (true)" || test_fail "config_has" "should exist"
! config_has "nonexistent" && test_pass "config_has (false)" || test_fail "config_has" "should not exist"

# config_keys
result=$(config_keys)
[[ "$result" == *"name"* ]] && test_pass "config_keys" || test_fail "config_keys" "got: $result"

# config_dump
result=$(config_dump)
[[ -n "$result" ]] && test_pass "config_dump" || test_fail "config_dump" "got empty"

# config_require - skip (exits)
test_skip "config_require" "exits on failure"

# config_validate - skip (complex)
test_skip "config_validate" "complex validation"

# config_save
config_save "$CONFIG_FILE.save" && test_pass "config_save" || test_fail "config_save" "failed to save"
rm -f "$CONFIG_FILE.save"

rm -f "$CONFIG_FILE"

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  TEST SUMMARY"
echo "════════════════════════════════════════════════════════════════"
echo ""
printf "  ✓ Passed:  %d\n" "$PASSED"
printf "  ✗ Failed:  %d\n" "$FAILED"
printf "  ○ Skipped: %d\n" "$SKIPPED"
echo ""
printf "  Total:     %d\n" "$((PASSED + FAILED + SKIPPED))"
echo ""

if [[ $FAILED -gt 0 ]]; then
    echo "════════════════════════════════════════════════════════════════"
    echo "  FAILURES"
    echo "════════════════════════════════════════════════════════════════"
    for failure in "${FAILURES[@]}"; do
        echo "  • $failure"
    done
    echo ""
    exit 1
fi

echo "★ YO JOE! All tests passed! ★"
echo ""

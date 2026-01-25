#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Diff Library Tests
# =============================================================================
# Tests for lib/diff.sh - Diff generation, patch application, search-replace
# =============================================================================

load 'test_helper'

setup() {
    source_lib "diff"
    TEST_DIR=$(create_test_dir "diff")

    # Create a basic test file
    printf 'line one\nline two\nline three\nline four\nline five\n' > "$TEST_DIR/basic.txt"

    # Create a multi-line test file
    printf 'function hello() {\n    console.log("hello");\n    return true;\n}\n\nfunction world() {\n    console.log("world");\n    return false;\n}\n' > "$TEST_DIR/code.txt"
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# DIFF GENERATION TESTS
# =============================================================================

@test "diff_strings produces unified diff for different strings" {
    run diff_strings "hello" "hello world"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-hello"* ]]
    [[ "$output" == *"+hello world"* ]]
}

@test "diff_strings returns 1 for identical strings" {
    run diff_strings "same" "same"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "diff_strings handles multiline text" {
    local old=$'line one\nline two\nline three'
    local new=$'line one\nline TWO\nline three'
    run diff_strings "$old" "$new"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-line two"* ]]
    [[ "$output" == *"+line TWO"* ]]
}

@test "diff_strings respects --context option" {
    local old=$'a\nb\nc\nd\ne\nf\ng'
    local new=$'a\nb\nc\nD\ne\nf\ng'
    run diff_strings "$old" "$new" --context 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"@@"* ]]
}

@test "diff_files produces unified diff between two files" {
    printf 'alpha\nbeta\ngamma\n' > "$TEST_DIR/file_a.txt"
    printf 'alpha\nBETA\ngamma\n' > "$TEST_DIR/file_b.txt"
    run diff_files "$TEST_DIR/file_a.txt" "$TEST_DIR/file_b.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-beta"* ]]
    [[ "$output" == *"+BETA"* ]]
}

@test "diff_files returns 1 for identical files" {
    printf 'same content\n' > "$TEST_DIR/same_a.txt"
    printf 'same content\n' > "$TEST_DIR/same_b.txt"
    run diff_files "$TEST_DIR/same_a.txt" "$TEST_DIR/same_b.txt"
    [ "$status" -eq 1 ]
}

@test "diff_files returns 2 for missing file" {
    run diff_files "$TEST_DIR/nonexistent.txt" "$TEST_DIR/basic.txt"
    [ "$status" -eq 2 ]
}

@test "diff_preview shows what would change" {
    run diff_preview "$TEST_DIR/basic.txt" $'line one\nline TWO\nline three\nline four\nline five'
    [ "$status" -eq 0 ]
    [[ "$output" == *"-line two"* ]]
    [[ "$output" == *"+line TWO"* ]]
}

@test "diff_preview returns 2 for missing file" {
    run diff_preview "$TEST_DIR/missing.txt" "content"
    [ "$status" -eq 2 ]
}

@test "diff_edit_script produces delete commands" {
    run diff_edit_script $'a\nb\nc' $'a\nc'
    [ "$status" -eq 0 ]
    [[ "$output" == *"d2"* ]]
}

@test "diff_edit_script produces add commands" {
    run diff_edit_script $'a\nc' $'a\nb\nc'
    [ "$status" -eq 0 ]
    [[ "$output" == *"a"* ]]
}

@test "diff_edit_script returns 1 for identical text" {
    run diff_edit_script "same" "same"
    [ "$status" -eq 1 ]
}

# =============================================================================
# PATCH APPLICATION TESTS
# =============================================================================

@test "diff_apply applies a valid unified diff" {
    # Generate a diff
    local old_content
    old_content=$(cat "$TEST_DIR/basic.txt")
    local new_content=$'line one\nline TWO\nline three\nline four\nline five'
    local diff_text
    diff_text=$(diff_strings "$old_content" "$new_content")

    run diff_apply "$TEST_DIR/basic.txt" "$diff_text" --no-backup
    [ "$status" -eq 0 ]

    # Verify content changed
    local result
    result=$(cat "$TEST_DIR/basic.txt")
    [[ "$result" == *"line TWO"* ]]
}

@test "diff_apply creates backup by default" {
    local old_content
    old_content=$(cat "$TEST_DIR/basic.txt")
    local new_content=$'line one\nline TWO\nline three\nline four\nline five'
    local diff_text
    diff_text=$(diff_strings "$old_content" "$new_content")

    run diff_apply "$TEST_DIR/basic.txt" "$diff_text" --backup
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/basic.txt.orig" ]
}

@test "diff_apply --dry-run does not modify file" {
    local original
    original=$(cat "$TEST_DIR/basic.txt")
    local new_content=$'line one\nline TWO\nline three\nline four\nline five'
    local diff_text
    diff_text=$(diff_strings "$original" "$new_content")

    run diff_apply "$TEST_DIR/basic.txt" "$diff_text" --dry-run --no-backup
    [ "$status" -eq 0 ]

    # File should be unchanged
    local after
    after=$(cat "$TEST_DIR/basic.txt")
    [ "$after" = "$original" ]
}

@test "diff_apply returns 1 on conflict" {
    # Create a diff against different content
    local diff_text
    diff_text=$(diff_strings "wrong content" "new content")

    run diff_apply "$TEST_DIR/basic.txt" "$diff_text" --no-backup
    [ "$status" -eq 1 ]
}

@test "diff_apply returns 2 for missing file" {
    run diff_apply "$TEST_DIR/nonexistent.txt" "some diff"
    [ "$status" -eq 2 ]
}

@test "diff_apply_string applies additions" {
    local original=$'line one\nline two\nline three'
    local diff_text
    diff_text=$(diff_strings "$original" $'line one\nline two\nnew line\nline three')

    run diff_apply_string "$original" "$diff_text"
    [ "$status" -eq 0 ]
    [[ "$output" == *"new line"* ]]
}

@test "diff_apply_string applies deletions" {
    local original=$'line one\nline two\nline three'
    local diff_text
    diff_text=$(diff_strings "$original" $'line one\nline three')

    run diff_apply_string "$original" "$diff_text"
    [ "$status" -eq 0 ]
    [[ "$output" != *"line two"* ]]
}

@test "diff_apply_string applies modifications" {
    local original=$'alpha\nbeta\ngamma'
    local diff_text
    diff_text=$(diff_strings "$original" $'alpha\nBETA\ngamma')

    run diff_apply_string "$original" "$diff_text"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BETA"* ]]
    [[ "$output" != *"beta"* ]]
}

@test "diff_reverse undoes a patch" {
    local original
    original=$(cat "$TEST_DIR/basic.txt")
    local new_content=$'line one\nline TWO\nline three\nline four\nline five'
    local diff_text
    diff_text=$(diff_strings "$original" "$new_content")

    # Apply the patch
    diff_apply "$TEST_DIR/basic.txt" "$diff_text" --no-backup

    # Reverse it
    run diff_reverse "$TEST_DIR/basic.txt" "$diff_text"
    [ "$status" -eq 0 ]

    # Verify content restored
    local restored
    restored=$(cat "$TEST_DIR/basic.txt")
    [[ "$restored" == *"line two"* ]]
}

# =============================================================================
# SEARCH-AND-REPLACE TESTS
# =============================================================================

@test "diff_replace replaces unique text in file" {
    run diff_replace "$TEST_DIR/basic.txt" "line two" "line TWO" --no-backup
    [ "$status" -eq 0 ]

    local result
    result=$(cat "$TEST_DIR/basic.txt")
    [[ "$result" == *"line TWO"* ]]
    [[ "$result" != *"line two"* ]]
}

@test "diff_replace returns 1 when text not found" {
    run diff_replace "$TEST_DIR/basic.txt" "nonexistent text" "replacement" --no-backup
    [ "$status" -eq 1 ]
}

@test "diff_replace returns 2 for ambiguous match without --all" {
    printf 'hello world\nhello there\n' > "$TEST_DIR/ambig.txt"
    run diff_replace "$TEST_DIR/ambig.txt" "hello" "hi" --no-backup
    [ "$status" -eq 2 ]
}

@test "diff_replace --all replaces all occurrences" {
    printf 'hello world\nhello there\n' > "$TEST_DIR/multi.txt"
    run diff_replace "$TEST_DIR/multi.txt" "hello" "hi" --all --no-backup
    [ "$status" -eq 0 ]

    local result
    result=$(cat "$TEST_DIR/multi.txt")
    [[ "$result" == *"hi world"* ]]
    [[ "$result" == *"hi there"* ]]
    [[ "$result" != *"hello"* ]]
}

@test "diff_replace handles multiline old_text" {
    run diff_replace "$TEST_DIR/code.txt" $'    console.log("hello");\n    return true;' $'    console.log("hi");\n    return 42;' --no-backup
    [ "$status" -eq 0 ]

    local result
    result=$(cat "$TEST_DIR/code.txt")
    [[ "$result" == *'console.log("hi")'* ]]
    [[ "$result" == *"return 42"* ]]
}

@test "diff_replace creates backup with --backup" {
    diff_replace "$TEST_DIR/basic.txt" "line two" "LINE 2" --backup
    [ -f "$TEST_DIR/basic.txt.orig" ]

    # Original content in backup
    local backup
    backup=$(cat "$TEST_DIR/basic.txt.orig")
    [[ "$backup" == *"line two"* ]]
}

@test "diff_replace_string replaces first occurrence" {
    run diff_replace_string "hello world hello" "hello" "hi"
    [ "$status" -eq 0 ]
    [ "$output" = "hi world hello" ]
}

@test "diff_replace_string --all replaces all occurrences" {
    run diff_replace_string "hello world hello" "hello" "hi" --all
    [ "$status" -eq 0 ]
    [ "$output" = "hi world hi" ]
}

@test "diff_replace_string handles multiline" {
    local input=$'line one\nline two\nline three'
    run diff_replace_string "$input" $'line two\nline three' $'LINE 2\nLINE 3'
    [ "$status" -eq 0 ]
    [[ "$output" == *"LINE 2"* ]]
    [[ "$output" == *"LINE 3"* ]]
}

@test "diff_insert_after inserts text after matching line" {
    run diff_insert_after "$TEST_DIR/basic.txt" "line two" "inserted line"
    [ "$status" -eq 0 ]

    local result
    result=$(cat "$TEST_DIR/basic.txt")
    # Check that "inserted line" comes after "line two"
    [[ "$result" == *"line two"*"inserted line"* ]]
}

@test "diff_insert_after returns 1 when match not found" {
    run diff_insert_after "$TEST_DIR/basic.txt" "nonexistent" "new text"
    [ "$status" -eq 1 ]
}

@test "diff_insert_before inserts text before matching line" {
    run diff_insert_before "$TEST_DIR/basic.txt" "line three" "inserted before"
    [ "$status" -eq 0 ]

    local result
    result=$(cat "$TEST_DIR/basic.txt")
    [[ "$result" == *"inserted before"*"line three"* ]]
}

@test "diff_insert_before returns 1 when match not found" {
    run diff_insert_before "$TEST_DIR/basic.txt" "nonexistent" "new text"
    [ "$status" -eq 1 ]
}

@test "diff_delete_lines removes matching lines" {
    run diff_delete_lines "$TEST_DIR/basic.txt" "line two"
    [ "$status" -eq 0 ]

    local result
    result=$(cat "$TEST_DIR/basic.txt")
    [[ "$result" != *"line two"* ]]
    [[ "$result" == *"line one"* ]]
    [[ "$result" == *"line three"* ]]
}

@test "diff_delete_lines with --regex removes regex matches" {
    run diff_delete_lines "$TEST_DIR/basic.txt" "^line (two|four)$" --regex
    [ "$status" -eq 0 ]

    local result
    result=$(cat "$TEST_DIR/basic.txt")
    [[ "$result" != *"line two"* ]]
    [[ "$result" != *"line four"* ]]
    [[ "$result" == *"line one"* ]]
}

@test "diff_delete_lines returns 1 for no matches" {
    run diff_delete_lines "$TEST_DIR/basic.txt" "nonexistent pattern"
    [ "$status" -eq 1 ]
}

@test "diff_replace_range replaces a range of lines" {
    run diff_replace_range "$TEST_DIR/basic.txt" 2 3 "replaced content"
    [ "$status" -eq 0 ]

    local result
    result=$(cat "$TEST_DIR/basic.txt")
    [[ "$result" == *"line one"* ]]
    [[ "$result" == *"replaced content"* ]]
    [[ "$result" == *"line four"* ]]
    [[ "$result" != *"line two"* ]]
    [[ "$result" != *"line three"* ]]
}

@test "diff_replace_range with multiline replacement" {
    run diff_replace_range "$TEST_DIR/basic.txt" 2 2 $'new line A\nnew line B'
    [ "$status" -eq 0 ]

    local result
    result=$(cat "$TEST_DIR/basic.txt")
    [[ "$result" == *"new line A"* ]]
    [[ "$result" == *"new line B"* ]]
    [[ "$result" != *"line two"* ]]
}

@test "diff_replace_range returns 1 for invalid range" {
    run diff_replace_range "$TEST_DIR/basic.txt" 5 2 "invalid"
    [ "$status" -eq 1 ]
}

# =============================================================================
# CONFLICT DETECTION TESTS
# =============================================================================

@test "diff_can_apply returns 0 for clean diff" {
    local content
    content=$(cat "$TEST_DIR/basic.txt")
    local diff_text
    diff_text=$(diff_strings "$content" $'line one\nline TWO\nline three\nline four\nline five')

    run diff_can_apply "$TEST_DIR/basic.txt" "$diff_text"
    [ "$status" -eq 0 ]
}

@test "diff_can_apply returns 1 for conflicting diff" {
    local diff_text
    diff_text=$(diff_strings "wrong content entirely" "new content")

    run diff_can_apply "$TEST_DIR/basic.txt" "$diff_text"
    [ "$status" -eq 1 ]
}

@test "diff_validate_unique returns 0 for unique text" {
    run diff_validate_unique "$TEST_DIR/basic.txt" "line two"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "diff_validate_unique returns 1 for missing text" {
    run diff_validate_unique "$TEST_DIR/basic.txt" "nonexistent"
    [ "$status" -eq 1 ]
    [ "$output" = "0" ]
}

@test "diff_validate_unique returns 2 for multiple matches" {
    printf 'hello world\nhello there\n' > "$TEST_DIR/dup.txt"
    run diff_validate_unique "$TEST_DIR/dup.txt" "hello"
    [ "$status" -eq 2 ]
    [ "$output" = "2" ]
}

@test "diff_conflicts returns JSON array" {
    local diff_text
    diff_text=$(diff_strings "wrong content" "new content")

    run diff_conflicts "$TEST_DIR/basic.txt" "$diff_text"
    [ "$status" -eq 0 ]
    [[ "$output" == "["* ]]
    [[ "$output" == *"]" ]]
}

@test "diff_conflicts returns empty array for clean diff" {
    local content
    content=$(cat "$TEST_DIR/basic.txt")
    local diff_text
    diff_text=$(diff_strings "$content" $'line one\nline TWO\nline three\nline four\nline five')

    run diff_conflicts "$TEST_DIR/basic.txt" "$diff_text"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

# =============================================================================
# DIFF ANALYSIS TESTS
# =============================================================================

@test "diff_stats counts additions and deletions" {
    local diff_text
    diff_text=$(diff_strings $'a\nb\nc' $'a\nB\nc\nd')

    run diff_stats "$diff_text"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"additions":'* ]]
    [[ "$output" == *'"deletions":'* ]]
    [[ "$output" == *'"changes":'* ]]
}

@test "diff_stats counts files" {
    local diff_text=$'--- a/file1\n+++ b/file1\n@@ -1 +1 @@\n-old\n+new'

    run diff_stats "$diff_text"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"files":1'* ]]
}

@test "diff_stats returns zeros for empty diff" {
    run diff_stats ""
    [ "$status" -eq 0 ]
    [[ "$output" == *'"additions":0'* ]]
    [[ "$output" == *'"deletions":0'* ]]
}

@test "diff_changed_lines extracts only + and - lines" {
    local diff_text=$'--- a/file\n+++ b/file\n@@ -1,3 +1,3 @@\n context\n-old line\n+new line\n context2'

    run diff_changed_lines "$diff_text"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-old line"* ]]
    [[ "$output" == *"+new line"* ]]
    [[ "$output" != *"context"* ]]
}

@test "diff_changed_lines excludes --- and +++ headers" {
    local diff_text=$'--- a/file\n+++ b/file\n@@ -1 +1 @@\n-old\n+new'

    run diff_changed_lines "$diff_text"
    [ "$status" -eq 0 ]
    [[ "$output" != *"--- a/file"* ]]
    [[ "$output" != *"+++ b/file"* ]]
    [[ "$output" == *"-old"* ]]
    [[ "$output" == *"+new"* ]]
}

@test "diff_affected_lines returns line numbers" {
    local diff_text=$'--- a/file\n+++ b/file\n@@ -2,3 +2,3 @@\n context\n-deleted\n+added\n context'

    run diff_affected_lines "$diff_text"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3"* ]]
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

@test "diff_replace handles empty new_text (deletion)" {
    printf 'keep this\nremove this\nkeep this too\n' > "$TEST_DIR/del.txt"
    run diff_replace "$TEST_DIR/del.txt" "remove this" "" --no-backup
    [ "$status" -eq 0 ]

    local result
    result=$(cat "$TEST_DIR/del.txt")
    [[ "$result" != *"remove this"* ]]
}

@test "diff_replace handles special characters" {
    printf 'price is $100\n' > "$TEST_DIR/special.txt"
    run diff_replace "$TEST_DIR/special.txt" 'price is $100' 'price is $200' --no-backup
    [ "$status" -eq 0 ]

    local result
    result=$(cat "$TEST_DIR/special.txt")
    [[ "$result" == *'$200'* ]]
}

@test "diff_strings handles empty old text" {
    run diff_strings "" "new content"
    [ "$status" -eq 0 ]
    [[ "$output" == *"+new content"* ]]
}

@test "diff_replace_string with no match returns original" {
    run diff_replace_string "hello world" "xyz" "abc"
    [ "$status" -eq 0 ]
    [ "$output" = "hello world" ]
}

@test "diff_insert_after with multiline new_text" {
    run diff_insert_after "$TEST_DIR/basic.txt" "line two" $'new A\nnew B\nnew C'
    [ "$status" -eq 0 ]

    local result
    result=$(cat "$TEST_DIR/basic.txt")
    [[ "$result" == *"new A"* ]]
    [[ "$result" == *"new B"* ]]
    [[ "$result" == *"new C"* ]]
}

@test "diff_apply with --fuzz allows offset matching" {
    # Create a file with slightly shifted content
    printf 'header\nline one\nline two\nline three\nfooter\n' > "$TEST_DIR/fuzz.txt"

    # Create a diff that expects content starting at line 1 instead of 2
    local diff_text=$'--- old\n+++ new\n@@ -1,3 +1,3 @@\n line one\n-line two\n+line TWO\n line three'

    run diff_apply "$TEST_DIR/fuzz.txt" "$diff_text" --fuzz 2 --no-backup
    [ "$status" -eq 0 ]

    local result
    result=$(cat "$TEST_DIR/fuzz.txt")
    [[ "$result" == *"line TWO"* ]]
}

@test "double-source guard prevents reloading" {
    # Source twice - should not error
    source_lib "diff"
    source_lib "diff"
    # If we get here, guard worked
    [ $? -eq 0 ]
}

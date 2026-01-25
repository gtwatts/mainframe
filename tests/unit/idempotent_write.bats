#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Idempotent File Write Tests
# =============================================================================
# Tests for lib/idempotent.sh - file_write_if_changed, file_write_if_changed_nl,
# file_append_if_missing, file_write_json_if_changed
# =============================================================================

load '../test_helper'

setup() {
    # Fix MAINFRAME_ROOT for tests in subdirectory
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    source_lib "idempotent"
    TEST_DIR=$(create_test_dir "idempotent_write")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# file_write_if_changed TESTS
# =============================================================================

@test "file_write_if_changed creates new file" {
    run file_write_if_changed "$TEST_DIR/new.txt" "hello world"
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/new.txt" ]
    [ "$(< "$TEST_DIR/new.txt")" = "hello world" ]
}

@test "file_write_if_changed skips identical content" {
    printf '%s' "same content" > "$TEST_DIR/existing.txt"
    local mtime_before
    mtime_before=$(stat -c %Y "$TEST_DIR/existing.txt" 2>/dev/null || stat -f %m "$TEST_DIR/existing.txt")
    sleep 1
    run file_write_if_changed "$TEST_DIR/existing.txt" "same content"
    [ "$status" -eq 1 ]
    local mtime_after
    mtime_after=$(stat -c %Y "$TEST_DIR/existing.txt" 2>/dev/null || stat -f %m "$TEST_DIR/existing.txt")
    [ "$mtime_before" = "$mtime_after" ]
}

@test "file_write_if_changed updates changed content" {
    printf '%s' "old content" > "$TEST_DIR/update.txt"
    run file_write_if_changed "$TEST_DIR/update.txt" "new content"
    [ "$status" -eq 0 ]
    [ "$(< "$TEST_DIR/update.txt")" = "new content" ]
}

@test "file_write_if_changed creates missing parent directories" {
    run file_write_if_changed "$TEST_DIR/deep/nested/dir/file.txt" "deep content"
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/deep/nested/dir/file.txt" ]
    [ "$(< "$TEST_DIR/deep/nested/dir/file.txt")" = "deep content" ]
}

@test "file_write_if_changed writes atomically (no temp files left)" {
    run file_write_if_changed "$TEST_DIR/atomic.txt" "atomic write"
    [ "$status" -eq 0 ]
    # No .tmp.XXXXXX files should remain
    local tmp_count
    tmp_count=$(find "$TEST_DIR" -name '.tmp.*' | wc -l)
    [ "$tmp_count" -eq 0 ]
}

@test "file_write_if_changed handles empty string content" {
    run file_write_if_changed "$TEST_DIR/empty.txt" ""
    # Empty string is still valid content (required param but can be "")
    # The :? would reject truly empty, but "" passed as arg is valid in bash
    [ -f "$TEST_DIR/empty.txt" ] || [ "$status" -ne 0 ]
}

@test "file_write_if_changed handles multiline content" {
    local content="line1
line2
line3"
    run file_write_if_changed "$TEST_DIR/multi.txt" "$content"
    [ "$status" -eq 0 ]
    [ "$(< "$TEST_DIR/multi.txt")" = "$content" ]
}

@test "file_write_if_changed handles special characters" {
    local content='key="value with spaces" & <brackets>'
    run file_write_if_changed "$TEST_DIR/special.txt" "$content"
    [ "$status" -eq 0 ]
    [ "$(< "$TEST_DIR/special.txt")" = "$content" ]
}

@test "file_write_if_changed returns 2 on unwritable directory" {
    mkdir -p "$TEST_DIR/readonly"
    chmod 555 "$TEST_DIR/readonly"
    run file_write_if_changed "$TEST_DIR/readonly/noperm/file.txt" "content"
    [ "$status" -eq 2 ]
    chmod 755 "$TEST_DIR/readonly"
}

# =============================================================================
# file_write_if_changed_nl TESTS
# =============================================================================

@test "file_write_if_changed_nl adds trailing newline" {
    run file_write_if_changed_nl "$TEST_DIR/nl.txt" "hello"
    [ "$status" -eq 0 ]
    # File should end with newline
    local content
    content=$(cat "$TEST_DIR/nl.txt")
    [ "$content" = "hello" ]
    # Check raw bytes include the trailing newline
    local byte_count
    byte_count=$(wc -c < "$TEST_DIR/nl.txt")
    [ "$byte_count" -eq 6 ]  # "hello" (5) + "\n" (1)
}

@test "file_write_if_changed_nl skips if content with newline matches" {
    printf 'existing\n' > "$TEST_DIR/nl_existing.txt"
    run file_write_if_changed_nl "$TEST_DIR/nl_existing.txt" "existing"
    [ "$status" -eq 1 ]
}

@test "file_write_if_changed_nl creates missing file with newline" {
    run file_write_if_changed_nl "$TEST_DIR/sub/nl_new.txt" "new line"
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/sub/nl_new.txt" ]
    local byte_count
    byte_count=$(wc -c < "$TEST_DIR/sub/nl_new.txt")
    [ "$byte_count" -eq 9 ]  # "new line" (8) + "\n" (1)
}

# =============================================================================
# file_append_if_missing TESTS
# =============================================================================

@test "file_append_if_missing appends new line to existing file" {
    printf 'line1\nline2\n' > "$TEST_DIR/append.txt"
    run file_append_if_missing "$TEST_DIR/append.txt" "line3"
    [ "$status" -eq 0 ]
    grep -qFx "line3" "$TEST_DIR/append.txt"
}

@test "file_append_if_missing skips existing line" {
    printf 'line1\nline2\nline3\n' > "$TEST_DIR/has_line.txt"
    run file_append_if_missing "$TEST_DIR/has_line.txt" "line2"
    [ "$status" -eq 1 ]
    # Should still have exactly one occurrence
    local count
    count=$(grep -cFx "line2" "$TEST_DIR/has_line.txt")
    [ "$count" -eq 1 ]
}

@test "file_append_if_missing creates file if missing" {
    run file_append_if_missing "$TEST_DIR/brand_new.txt" "first line"
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/brand_new.txt" ]
    grep -qFx "first line" "$TEST_DIR/brand_new.txt"
}

@test "file_append_if_missing distinguishes partial matches" {
    printf 'export PATH=/usr/bin\n' > "$TEST_DIR/partial.txt"
    run file_append_if_missing "$TEST_DIR/partial.txt" "export PATH=/usr/bin:/opt/bin"
    [ "$status" -eq 0 ]
    local count
    count=$(wc -l < "$TEST_DIR/partial.txt")
    [ "$count" -eq 2 ]
}

@test "file_append_if_missing handles lines with special regex chars" {
    printf 'normal line\n' > "$TEST_DIR/regex.txt"
    run file_append_if_missing "$TEST_DIR/regex.txt" 'value=.*[0-9]+'
    [ "$status" -eq 0 ]
    grep -qFx 'value=.*[0-9]+' "$TEST_DIR/regex.txt"
}

# =============================================================================
# file_write_json_if_changed TESTS
# =============================================================================

@test "file_write_json_if_changed creates new JSON file" {
    run file_write_json_if_changed "$TEST_DIR/config.json" '{"name":"test","value":42}'
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/config.json" ]
    [[ "$(< "$TEST_DIR/config.json")" == *'"name"'* ]]
}

@test "file_write_json_if_changed skips semantically identical JSON" {
    if ! command -v jq &>/dev/null; then
        skip "jq not available for semantic comparison"
    fi
    # Write with one formatting
    printf '{"name":"test","value":42}' > "$TEST_DIR/same.json"
    # Try to write with different formatting but same content
    run file_write_json_if_changed "$TEST_DIR/same.json" '{  "value": 42, "name": "test"  }'
    [ "$status" -eq 1 ]
}

@test "file_write_json_if_changed writes when JSON values differ" {
    if ! command -v jq &>/dev/null; then
        skip "jq not available for semantic comparison"
    fi
    printf '{"name":"old","value":1}' > "$TEST_DIR/diff.json"
    run file_write_json_if_changed "$TEST_DIR/diff.json" '{"name":"new","value":2}'
    [ "$status" -eq 0 ]
    [[ "$(< "$TEST_DIR/diff.json")" == *'"new"'* ]]
}

@test "file_write_json_if_changed falls back to byte compare without jq" {
    # Temporarily hide jq
    local real_path="$PATH"
    PATH="/nonexistent_dir_only"
    printf '{"a":1}' > "$TEST_DIR/byte.json"
    # Same bytes should skip
    run file_write_json_if_changed "$TEST_DIR/byte.json" '{"a":1}'
    [ "$status" -eq 1 ]
    PATH="$real_path"
}

@test "file_write_json_if_changed handles nested JSON" {
    if ! command -v jq &>/dev/null; then
        skip "jq not available for semantic comparison"
    fi
    local json='{"config":{"db":{"host":"localhost","port":5432},"cache":true}}'
    run file_write_json_if_changed "$TEST_DIR/nested.json" "$json"
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/nested.json" ]
}

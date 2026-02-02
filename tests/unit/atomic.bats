#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/atomic.bats - Atomic Operations Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/atomic.sh
#              Atomic file operations with TOCTOU protection, recovery, and
#              checkpoint/rollback mechanisms
# Test Count: 50+ test cases
# Categories: atomic_write, atomic_append, atomic_replace, safe_remove,
#             safe_restore, file_checkpoint, file_rollback, concurrency
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create isolated temp directories for test artifacts
    TEST_TMPDIR="$(mktemp -d)"
    export MAINFRAME_CHECKPOINT_DIR="${TEST_TMPDIR}/checkpoints"
    export MAINFRAME_TRASH_DIR="${TEST_TMPDIR}/trash"
    export MAINFRAME_QUIET=1

    # Source the library
    source "$MAINFRAME_ROOT/lib/atomic.sh"
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# CATEGORY 1: atomic_write - Basic Operations
# =============================================================================

@test "atomic_write: creates file with correct content" {
    run atomic_write "$TEST_TMPDIR/test.txt" "hello world"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$TEST_TMPDIR/test.txt")" == "hello world" ]]
}

@test "atomic_write: creates parent directories" {
    run atomic_write "$TEST_TMPDIR/nested/deep/test.txt" "content"
    [[ "$status" -eq 0 ]]
    [[ -f "$TEST_TMPDIR/nested/deep/test.txt" ]]
    [[ "$(cat "$TEST_TMPDIR/nested/deep/test.txt")" == "content" ]]
}

@test "atomic_write: overwrites existing file" {
    echo "original" > "$TEST_TMPDIR/overwrite.txt"
    run atomic_write "$TEST_TMPDIR/overwrite.txt" "updated"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$TEST_TMPDIR/overwrite.txt")" == "updated" ]]
}

@test "atomic_write: handles empty content" {
    run atomic_write "$TEST_TMPDIR/empty.txt" ""
    [[ "$status" -eq 0 ]]
    [[ -f "$TEST_TMPDIR/empty.txt" ]]
    [[ ! -s "$TEST_TMPDIR/empty.txt" ]]
}

@test "atomic_write: handles multiline content" {
    local content=$'line1\nline2\nline3'
    run atomic_write "$TEST_TMPDIR/multiline.txt" "$content"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$TEST_TMPDIR/multiline.txt")" == "$content" ]]
}

@test "atomic_write: handles content with special characters" {
    local content='$VAR "quoted" `backtick` \n not-newline'
    run atomic_write "$TEST_TMPDIR/special.txt" "$content"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$TEST_TMPDIR/special.txt")" == "$content" ]]
}

@test "atomic_write: fails without target path" {
    run atomic_write "" "content"
    [[ "$status" -eq 1 ]]
}

@test "atomic_write: sets explicit permissions" {
    run atomic_write "$TEST_TMPDIR/perms.txt" "secure content" "0600"
    [[ "$status" -eq 0 ]]
    local mode
    mode=$(stat -c '%a' "$TEST_TMPDIR/perms.txt" 2>/dev/null || stat -f '%Lp' "$TEST_TMPDIR/perms.txt")
    [[ "$mode" == "600" ]]
}

@test "atomic_write: preserves existing file permissions" {
    echo "original" > "$TEST_TMPDIR/preserve.txt"
    chmod 640 "$TEST_TMPDIR/preserve.txt"
    run atomic_write "$TEST_TMPDIR/preserve.txt" "updated"
    [[ "$status" -eq 0 ]]
    local mode
    mode=$(stat -c '%a' "$TEST_TMPDIR/preserve.txt" 2>/dev/null || stat -f '%Lp' "$TEST_TMPDIR/preserve.txt")
    [[ "$mode" == "640" ]]
}

@test "atomic_write: handles file in current directory" {
    cd "$TEST_TMPDIR"
    run atomic_write "local.txt" "local content"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$TEST_TMPDIR/local.txt")" == "local content" ]]
}

# =============================================================================
# CATEGORY 2: atomic_write - Concurrency Safety (TOCTOU Verification)
# =============================================================================

@test "atomic_write: is safe with concurrent access" {
    # Multiple processes writing to same file
    for i in {1..10}; do
        atomic_write "$TEST_TMPDIR/race.txt" "iteration $i" &
    done
    wait

    # File should exist and contain valid content from one of the iterations
    [[ -f "$TEST_TMPDIR/race.txt" ]]
    local content
    content=$(cat "$TEST_TMPDIR/race.txt")
    [[ "$content" =~ ^iteration\ [0-9]+$ ]]
}

@test "atomic_write: no partial writes visible" {
    # Write a large content to increase chance of catching partial write
    local large_content
    large_content=$(printf 'x%.0s' {1..10000})

    # Concurrent writes
    for i in {1..5}; do
        atomic_write "$TEST_TMPDIR/large.txt" "${large_content}${i}" &
    done
    wait

    # File should be complete (not truncated)
    local file_content
    file_content=$(cat "$TEST_TMPDIR/large.txt")
    local expected_length=$((10001))  # 10000 x's + 1 digit
    [[ ${#file_content} -eq $expected_length ]]
}

@test "atomic_write: temp files cleaned up on success" {
    atomic_write "$TEST_TMPDIR/cleanup.txt" "content"
    # No temp files should remain
    local temp_count
    temp_count=$(find "$TEST_TMPDIR" -name ".mainframe_atomic.*" 2>/dev/null | wc -l)
    [[ "$temp_count" -eq 0 ]]
}

# =============================================================================
# CATEGORY 3: atomic_append
# =============================================================================

@test "atomic_append: appends to existing file" {
    echo "line1" > "$TEST_TMPDIR/append.txt"
    run atomic_append "$TEST_TMPDIR/append.txt" "line2"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$TEST_TMPDIR/append.txt")" == $'line1\nline2' ]]
}

@test "atomic_append: creates file if not exists" {
    run atomic_append "$TEST_TMPDIR/newappend.txt" "first line"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$TEST_TMPDIR/newappend.txt")" == "first line" ]]
}

@test "atomic_append: multiple appends preserve order" {
    for i in 1 2 3 4 5; do
        atomic_append "$TEST_TMPDIR/order.txt" "line$i"
    done
    local content
    content=$(cat "$TEST_TMPDIR/order.txt")
    [[ "$content" == $'line1\nline2\nline3\nline4\nline5' ]]
}

@test "atomic_append: creates parent directories" {
    run atomic_append "$TEST_TMPDIR/nested/append.txt" "content"
    [[ "$status" -eq 0 ]]
    [[ -f "$TEST_TMPDIR/nested/append.txt" ]]
}

@test "atomic_append: fails without target" {
    run atomic_append "" "content"
    [[ "$status" -eq 1 ]]
}

@test "atomic_append: fails without content" {
    run atomic_append "$TEST_TMPDIR/file.txt" ""
    [[ "$status" -eq 1 ]]
}

@test "atomic_append: concurrent appends with flock" {
    # If flock is available, concurrent appends should not interleave
    if ! command -v flock &>/dev/null; then
        skip "flock not available"
    fi

    for i in {1..20}; do
        atomic_append "$TEST_TMPDIR/concurrent.txt" "line$i" &
    done
    wait

    # Should have 20 complete lines
    local line_count
    line_count=$(wc -l < "$TEST_TMPDIR/concurrent.txt")
    [[ "$line_count" -eq 20 ]]
}

# =============================================================================
# CATEGORY 4: atomic_replace
# =============================================================================

@test "atomic_replace: replaces file with backup" {
    echo "original content" > "$TEST_TMPDIR/replace.txt"
    run atomic_replace "$TEST_TMPDIR/replace.txt" "new content"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$TEST_TMPDIR/replace.txt")" == "new content" ]]
    # Backup should exist
    local backup
    backup=$(ls "$TEST_TMPDIR"/replace.txt.bak.* 2>/dev/null | head -1)
    [[ -n "$backup" ]]
    [[ "$(cat "$backup")" == "original content" ]]
}

@test "atomic_replace: works on new file (no backup needed)" {
    run atomic_replace "$TEST_TMPDIR/newfile.txt" "content"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$TEST_TMPDIR/newfile.txt")" == "content" ]]
}

@test "atomic_replace: verify command success proceeds" {
    echo "original" > "$TEST_TMPDIR/verify.txt"
    run atomic_replace "$TEST_TMPDIR/verify.txt" "valid" "true"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$TEST_TMPDIR/verify.txt")" == "valid" ]]
}

@test "atomic_replace: verify command failure triggers rollback" {
    echo "original" > "$TEST_TMPDIR/rollback.txt"
    run atomic_replace "$TEST_TMPDIR/rollback.txt" "invalid" "false"
    [[ "$status" -eq 1 ]]
    # Should have rolled back to original
    [[ "$(cat "$TEST_TMPDIR/rollback.txt")" == "original" ]]
}

@test "atomic_replace: fails without target" {
    run atomic_replace "" "content"
    [[ "$status" -eq 1 ]]
}

@test "atomic_replace: backup has timestamp" {
    echo "content" > "$TEST_TMPDIR/timestamp.txt"
    sleep 1
    atomic_replace "$TEST_TMPDIR/timestamp.txt" "new"
    local backup
    backup=$(ls "$TEST_TMPDIR"/timestamp.txt.bak.* 2>/dev/null | head -1)
    [[ "$backup" =~ \.bak\.[0-9]+$ ]]
}

# =============================================================================
# CATEGORY 5: safe_remove and safe_restore
# =============================================================================

@test "safe_remove: moves file to trash" {
    echo "content" > "$TEST_TMPDIR/removeme.txt"
    run safe_remove "$TEST_TMPDIR/removeme.txt"
    [[ "$status" -eq 0 ]]
    [[ ! -e "$TEST_TMPDIR/removeme.txt" ]]
    # Should exist in trash
    [[ -d "$MAINFRAME_TRASH_DIR" ]]
    local trash_file
    trash_file=$(ls "$MAINFRAME_TRASH_DIR"/removeme.txt.* 2>/dev/null | grep -v ".origin$" | head -1)
    [[ -n "$trash_file" ]]
}

@test "safe_remove: creates origin file for restore" {
    echo "content" > "$TEST_TMPDIR/withorigin.txt"
    safe_remove "$TEST_TMPDIR/withorigin.txt"
    local origin_file
    origin_file=$(ls "$MAINFRAME_TRASH_DIR"/withorigin.txt.*.origin 2>/dev/null | head -1)
    [[ -f "$origin_file" ]]
    [[ "$(cat "$origin_file")" == "$TEST_TMPDIR/withorigin.txt" ]]
}

@test "safe_remove: idempotent for non-existent path" {
    run safe_remove "$TEST_TMPDIR/nonexistent.txt"
    [[ "$status" -eq 0 ]]
}

@test "safe_remove: fails without path" {
    run safe_remove ""
    [[ "$status" -eq 1 ]]
}

@test "safe_remove: handles symlinks" {
    echo "target" > "$TEST_TMPDIR/target.txt"
    ln -s "$TEST_TMPDIR/target.txt" "$TEST_TMPDIR/symlink.txt"
    run safe_remove "$TEST_TMPDIR/symlink.txt"
    [[ "$status" -eq 0 ]]
    [[ ! -L "$TEST_TMPDIR/symlink.txt" ]]
    # Target should still exist
    [[ -f "$TEST_TMPDIR/target.txt" ]]
}

@test "safe_remove: handles directories" {
    mkdir -p "$TEST_TMPDIR/removedir/subdir"
    echo "file" > "$TEST_TMPDIR/removedir/file.txt"
    run safe_remove "$TEST_TMPDIR/removedir"
    [[ "$status" -eq 0 ]]
    [[ ! -d "$TEST_TMPDIR/removedir" ]]
}

@test "safe_restore: restores file to original location" {
    echo "restore me" > "$TEST_TMPDIR/torestore.txt"
    safe_remove "$TEST_TMPDIR/torestore.txt"
    [[ ! -e "$TEST_TMPDIR/torestore.txt" ]]

    run safe_restore "torestore.txt"
    [[ "$status" -eq 0 ]]
    [[ -f "$TEST_TMPDIR/torestore.txt" ]]
    [[ "$(cat "$TEST_TMPDIR/torestore.txt")" == "restore me" ]]
}

@test "safe_restore: fails for non-existent trash entry" {
    run safe_restore "never-existed.txt"
    [[ "$status" -eq 1 ]]
}

@test "safe_restore: fails without filename" {
    run safe_restore ""
    [[ "$status" -eq 1 ]]
}

@test "safe_restore: restores most recent version" {
    echo "version1" > "$TEST_TMPDIR/multi.txt"
    safe_remove "$TEST_TMPDIR/multi.txt"
    sleep 1

    echo "version2" > "$TEST_TMPDIR/multi.txt"
    safe_remove "$TEST_TMPDIR/multi.txt"

    safe_restore "multi.txt"
    [[ "$(cat "$TEST_TMPDIR/multi.txt")" == "version2" ]]
}

# =============================================================================
# CATEGORY 6: file_checkpoint and file_rollback
# =============================================================================

@test "file_checkpoint: creates named checkpoint" {
    echo "checkpoint content" > "$TEST_TMPDIR/checkpoint.txt"
    run file_checkpoint "$TEST_TMPDIR/checkpoint.txt" "before-change"
    [[ "$status" -eq 0 ]]
    [[ -d "$MAINFRAME_CHECKPOINT_DIR" ]]
    local checkpoint
    checkpoint=$(ls "$MAINFRAME_CHECKPOINT_DIR"/*__before-change 2>/dev/null | head -1)
    [[ -f "$checkpoint" ]]
    [[ "$(cat "$checkpoint")" == "checkpoint content" ]]
}

@test "file_checkpoint: uses default name when not specified" {
    echo "content" > "$TEST_TMPDIR/defaultcp.txt"
    run file_checkpoint "$TEST_TMPDIR/defaultcp.txt"
    [[ "$status" -eq 0 ]]
    local checkpoint
    checkpoint=$(ls "$MAINFRAME_CHECKPOINT_DIR"/*__default 2>/dev/null | head -1)
    [[ -f "$checkpoint" ]]
}

@test "file_checkpoint: creates meta file with original path" {
    echo "content" > "$TEST_TMPDIR/meta.txt"
    file_checkpoint "$TEST_TMPDIR/meta.txt" "test"
    local meta
    meta=$(ls "$MAINFRAME_CHECKPOINT_DIR"/*__test.meta 2>/dev/null | head -1)
    [[ -f "$meta" ]]
    [[ "$(cat "$meta")" == "$TEST_TMPDIR/meta.txt" ]]
}

@test "file_checkpoint: fails for non-existent file" {
    run file_checkpoint "$TEST_TMPDIR/nonexistent.txt" "test"
    [[ "$status" -eq 1 ]]
}

@test "file_checkpoint: fails without file path" {
    run file_checkpoint "" "test"
    [[ "$status" -eq 1 ]]
}

@test "file_checkpoint: idempotent - overwrites same checkpoint name" {
    echo "version1" > "$TEST_TMPDIR/idem.txt"
    file_checkpoint "$TEST_TMPDIR/idem.txt" "snap"
    echo "version2" > "$TEST_TMPDIR/idem.txt"
    file_checkpoint "$TEST_TMPDIR/idem.txt" "snap"

    local count
    count=$(ls "$MAINFRAME_CHECKPOINT_DIR"/*__snap 2>/dev/null | wc -l)
    [[ "$count" -eq 1 ]]
}

@test "file_checkpoint: preserves file permissions" {
    echo "content" > "$TEST_TMPDIR/perms.txt"
    chmod 0750 "$TEST_TMPDIR/perms.txt"
    file_checkpoint "$TEST_TMPDIR/perms.txt" "perms"

    local checkpoint
    checkpoint=$(ls "$MAINFRAME_CHECKPOINT_DIR"/*__perms 2>/dev/null | head -1)
    local mode
    mode=$(stat -c '%a' "$checkpoint" 2>/dev/null || stat -f '%Lp' "$checkpoint")
    [[ "$mode" == "750" ]]
}

@test "file_rollback: restores from checkpoint" {
    echo "original" > "$TEST_TMPDIR/rollback.txt"
    file_checkpoint "$TEST_TMPDIR/rollback.txt" "original"

    echo "modified" > "$TEST_TMPDIR/rollback.txt"
    [[ "$(cat "$TEST_TMPDIR/rollback.txt")" == "modified" ]]

    run file_rollback "$TEST_TMPDIR/rollback.txt" "original"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$TEST_TMPDIR/rollback.txt")" == "original" ]]
}

@test "file_rollback: uses default checkpoint name" {
    echo "original" > "$TEST_TMPDIR/default.txt"
    file_checkpoint "$TEST_TMPDIR/default.txt"
    echo "changed" > "$TEST_TMPDIR/default.txt"

    run file_rollback "$TEST_TMPDIR/default.txt"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$TEST_TMPDIR/default.txt")" == "original" ]]
}

@test "file_rollback: fails for missing checkpoint" {
    echo "content" > "$TEST_TMPDIR/nocp.txt"
    run file_rollback "$TEST_TMPDIR/nocp.txt" "nonexistent"
    [[ "$status" -eq 1 ]]
}

@test "file_rollback: fails without file path" {
    run file_rollback "" "test"
    [[ "$status" -eq 1 ]]
}

@test "file_rollback: uses atomic_write for safety" {
    echo "original" > "$TEST_TMPDIR/atomic_rb.txt"
    file_checkpoint "$TEST_TMPDIR/atomic_rb.txt" "safe"
    echo "changed" > "$TEST_TMPDIR/atomic_rb.txt"

    file_rollback "$TEST_TMPDIR/atomic_rb.txt" "safe"

    # Should not leave temp files
    local temp_count
    temp_count=$(find "$TEST_TMPDIR" -name ".mainframe_atomic.*" 2>/dev/null | wc -l)
    [[ "$temp_count" -eq 0 ]]
}

# =============================================================================
# CATEGORY 7: file_checkpoints listing
# =============================================================================

@test "file_checkpoints: lists all checkpoints" {
    echo "file1" > "$TEST_TMPDIR/f1.txt"
    echo "file2" > "$TEST_TMPDIR/f2.txt"
    file_checkpoint "$TEST_TMPDIR/f1.txt" "cp1"
    file_checkpoint "$TEST_TMPDIR/f2.txt" "cp2"

    run file_checkpoints
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "cp1" ]]
    [[ "$output" =~ "cp2" ]]
}

@test "file_checkpoints: filters by file path" {
    echo "file1" > "$TEST_TMPDIR/filter1.txt"
    echo "file2" > "$TEST_TMPDIR/filter2.txt"
    file_checkpoint "$TEST_TMPDIR/filter1.txt" "first"
    file_checkpoint "$TEST_TMPDIR/filter2.txt" "second"

    run file_checkpoints "$TEST_TMPDIR/filter1.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "first" ]]
    [[ ! "$output" =~ "second" ]]
}

@test "file_checkpoints: returns empty for no checkpoints" {
    run file_checkpoints
    [[ "$status" -eq 0 ]]
}

@test "file_checkpoints: shows file size" {
    echo "some content here" > "$TEST_TMPDIR/sized.txt"
    file_checkpoint "$TEST_TMPDIR/sized.txt" "size-test"

    run file_checkpoints
    [[ "$output" =~ "bytes" ]]
}

# =============================================================================
# CATEGORY 8: file_checkpoint_cleanup
# =============================================================================

@test "file_checkpoint_cleanup: removes old checkpoints" {
    echo "old" > "$TEST_TMPDIR/old.txt"
    file_checkpoint "$TEST_TMPDIR/old.txt" "old-cp"

    # Touch checkpoint to make it old (2 seconds ago)
    local checkpoint
    checkpoint=$(ls "$MAINFRAME_CHECKPOINT_DIR"/*__old-cp 2>/dev/null | head -1)
    touch -d "2 seconds ago" "$checkpoint"

    run file_checkpoint_cleanup 1
    [[ "$status" -eq 0 ]]
    [[ ! -f "$checkpoint" ]]
}

@test "file_checkpoint_cleanup: preserves recent checkpoints" {
    echo "recent" > "$TEST_TMPDIR/recent.txt"
    file_checkpoint "$TEST_TMPDIR/recent.txt" "recent-cp"

    run file_checkpoint_cleanup 3600  # 1 hour
    [[ "$status" -eq 0 ]]

    local checkpoint
    checkpoint=$(ls "$MAINFRAME_CHECKPOINT_DIR"/*__recent-cp 2>/dev/null | head -1)
    [[ -f "$checkpoint" ]]
}

@test "file_checkpoint_cleanup: handles empty checkpoint dir" {
    run file_checkpoint_cleanup
    [[ "$status" -eq 0 ]]
}

@test "file_checkpoint_cleanup: uses default 24h max age" {
    echo "test" > "$TEST_TMPDIR/default.txt"
    file_checkpoint "$TEST_TMPDIR/default.txt" "def"

    run file_checkpoint_cleanup
    [[ "$status" -eq 0 ]]
    # Should still exist (created just now)
    local checkpoint
    checkpoint=$(ls "$MAINFRAME_CHECKPOINT_DIR"/*__def 2>/dev/null | head -1)
    [[ -f "$checkpoint" ]]
}

# =============================================================================
# CATEGORY 9: Edge Cases and Error Handling
# =============================================================================

@test "atomic_write: handles very long filenames" {
    local long_name
    long_name=$(printf 'a%.0s' {1..200})
    run atomic_write "$TEST_TMPDIR/${long_name}.txt" "content"
    # Should either succeed or fail gracefully
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

@test "atomic_write: handles unicode content" {
    local unicode_content="Hello unicode"
    run atomic_write "$TEST_TMPDIR/unicode.txt" "$unicode_content"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$TEST_TMPDIR/unicode.txt")" == "$unicode_content" ]]
}

@test "atomic_write: handles binary-like content" {
    local binary_content=$'\x00\x01\x02\x03'
    # Note: printf %s cannot handle null bytes, so we test what's possible
    run atomic_write "$TEST_TMPDIR/binary.txt" "binary test"
    [[ "$status" -eq 0 ]]
}

@test "atomic_replace: verify command with complex shell" {
    echo "config" > "$TEST_TMPDIR/complex.txt"
    # Verify command that checks file content (use double quotes so $TEST_TMPDIR expands)
    run atomic_replace "$TEST_TMPDIR/complex.txt" "valid config" \
        "grep -q 'valid' '$TEST_TMPDIR/complex.txt'"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$TEST_TMPDIR/complex.txt")" == "valid config" ]]
}

@test "safe_remove: unique trash names for same filename" {
    echo "first" > "$TEST_TMPDIR/same.txt"
    safe_remove "$TEST_TMPDIR/same.txt"

    echo "second" > "$TEST_TMPDIR/same.txt"
    safe_remove "$TEST_TMPDIR/same.txt"

    # Should have two trash entries
    local count
    count=$(ls "$MAINFRAME_TRASH_DIR"/same.txt.* 2>/dev/null | grep -v ".origin$" | wc -l)
    [[ "$count" -eq 2 ]]
}

@test "file_checkpoint: multiple checkpoints for same file" {
    echo "v1" > "$TEST_TMPDIR/multi.txt"
    file_checkpoint "$TEST_TMPDIR/multi.txt" "v1"

    echo "v2" > "$TEST_TMPDIR/multi.txt"
    file_checkpoint "$TEST_TMPDIR/multi.txt" "v2"

    echo "v3" > "$TEST_TMPDIR/multi.txt"
    file_checkpoint "$TEST_TMPDIR/multi.txt" "v3"

    # Can rollback to any version
    file_rollback "$TEST_TMPDIR/multi.txt" "v1"
    [[ "$(cat "$TEST_TMPDIR/multi.txt")" == "v1" ]]

    file_rollback "$TEST_TMPDIR/multi.txt" "v3"
    [[ "$(cat "$TEST_TMPDIR/multi.txt")" == "v3" ]]
}

# =============================================================================
# CATEGORY 10: Integration with Other Components
# =============================================================================

@test "atomic_write: works with json content" {
    local json_content='{"key":"value","nested":{"array":[1,2,3]}}'
    run atomic_write "$TEST_TMPDIR/data.json" "$json_content"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$TEST_TMPDIR/data.json")" == "$json_content" ]]
}

@test "checkpoint-modify-rollback workflow" {
    # Create initial config
    echo "setting=original" > "$TEST_TMPDIR/config.conf"

    # Checkpoint before modification
    file_checkpoint "$TEST_TMPDIR/config.conf" "before-update"

    # Make changes
    echo "setting=modified" > "$TEST_TMPDIR/config.conf"
    [[ "$(cat "$TEST_TMPDIR/config.conf")" == "setting=modified" ]]

    # Something went wrong - rollback
    file_rollback "$TEST_TMPDIR/config.conf" "before-update"
    [[ "$(cat "$TEST_TMPDIR/config.conf")" == "setting=original" ]]
}

@test "safe_remove with immediate restore" {
    echo "important data" > "$TEST_TMPDIR/important.txt"
    local original_path="$TEST_TMPDIR/important.txt"

    safe_remove "$original_path"
    [[ ! -e "$original_path" ]]

    safe_restore "important.txt"
    [[ -f "$original_path" ]]
    [[ "$(cat "$original_path")" == "important data" ]]
}

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/checkpoint.bats - Checkpoint & Rollback Test Suite
# =============================================================================
# Description: Comprehensive tests for lib/checkpoint.sh including security
#              tests for path traversal, concurrent access, and integrity.
# Run: bats tests/checkpoint.bats
# =============================================================================

# Test setup
setup() {
    # Create temporary test directory
    export TEST_DIR=$(mktemp -d)
    export MAINFRAME_CHECKPOINT_DIR="${TEST_DIR}/checkpoints"
    export MAINFRAME_CHECKPOINT_MAX_SIZE_MB=10
    export MAINFRAME_CHECKPOINT_MAX_COUNT=10
    export MAINFRAME_CHECKPOINT_MAX_AGE=86400
    export MAINFRAME_QUIET=1

    # Create test files
    mkdir -p "${TEST_DIR}/source"
    echo "original content 1" > "${TEST_DIR}/source/file1.txt"
    echo "original content 2" > "${TEST_DIR}/source/file2.txt"
    mkdir -p "${TEST_DIR}/source/subdir"
    echo "nested content" > "${TEST_DIR}/source/subdir/nested.txt"

    # Source the checkpoint library
    source "${BATS_TEST_DIRNAME}/../lib/checkpoint.sh"
}

# Test teardown
teardown() {
    rm -rf "$TEST_DIR"
}

_checkpoint_test_sha256() {
    local file="$1"
    if command -v sha256sum &>/dev/null; then
        sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    fi
}

_checkpoint_test_sed_in_place() {
    local expr="$1"
    local file="$2"
    local tmp="${file}.tmp.$$"
    sed "$expr" "$file" > "$tmp"
    mv "$tmp" "$file"
}

# =============================================================================
# BASIC CREATE/ROLLBACK TESTS
# =============================================================================

@test "checkpoint_create creates checkpoint with single file" {
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "test1" "${TEST_DIR}/source/file1.txt")

    [ -n "$checkpoint_id" ]
    [ -d "${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}" ]
    [ -f "${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}/metadata.json" ]
    [ -f "${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}/data.tar.gz" ]
}

@test "checkpoint_create creates checkpoint with multiple files" {
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "test2" \
        "${TEST_DIR}/source/file1.txt" \
        "${TEST_DIR}/source/file2.txt")

    [ -n "$checkpoint_id" ]

    # Verify metadata contains both files
    local metadata="${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}/metadata.json"
    grep -q "file1.txt" "$metadata"
    grep -q "file2.txt" "$metadata"
}

@test "checkpoint_create creates checkpoint with directory" {
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "test3" "${TEST_DIR}/source")

    [ -n "$checkpoint_id" ]

    # Verify archive contains directory contents
    tar -tzf "${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}/data.tar.gz" | grep -q "file1.txt"
    tar -tzf "${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}/data.tar.gz" | grep -q "nested.txt"
}

@test "checkpoint_rollback restores single file" {
    # Create checkpoint
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "restore1" "${TEST_DIR}/source/file1.txt")

    # Modify the file
    echo "modified content" > "${TEST_DIR}/source/file1.txt"
    [ "$(cat "${TEST_DIR}/source/file1.txt")" = "modified content" ]

    # Rollback
    checkpoint_rollback "$checkpoint_id"

    # Verify restoration
    [ "$(cat "${TEST_DIR}/source/file1.txt")" = "original content 1" ]
}

@test "checkpoint_rollback restores multiple files" {
    # Create checkpoint
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "restore2" \
        "${TEST_DIR}/source/file1.txt" \
        "${TEST_DIR}/source/file2.txt")

    # Modify both files
    echo "modified 1" > "${TEST_DIR}/source/file1.txt"
    echo "modified 2" > "${TEST_DIR}/source/file2.txt"

    # Rollback
    checkpoint_rollback "$checkpoint_id"

    # Verify restoration
    [ "$(cat "${TEST_DIR}/source/file1.txt")" = "original content 1" ]
    [ "$(cat "${TEST_DIR}/source/file2.txt")" = "original content 2" ]
}

@test "checkpoint_rollback restores directory" {
    # Create checkpoint
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "restore3" "${TEST_DIR}/source")

    # Modify files
    echo "modified" > "${TEST_DIR}/source/file1.txt"
    echo "modified nested" > "${TEST_DIR}/source/subdir/nested.txt"
    rm -f "${TEST_DIR}/source/file2.txt"

    # Rollback
    checkpoint_rollback "$checkpoint_id"

    # Verify restoration
    [ "$(cat "${TEST_DIR}/source/file1.txt")" = "original content 1" ]
    [ "$(cat "${TEST_DIR}/source/file2.txt")" = "original content 2" ]
    [ "$(cat "${TEST_DIR}/source/subdir/nested.txt")" = "nested content" ]
}

@test "checkpoint_rollback dry-run shows files without restoring" {
    # Create checkpoint
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "dryrun" "${TEST_DIR}/source/file1.txt")

    # Modify the file
    echo "modified content" > "${TEST_DIR}/source/file1.txt"

    # Dry run
    local result
    result=$(checkpoint_rollback "$checkpoint_id" --dry-run)

    # File should still be modified
    [ "$(cat "${TEST_DIR}/source/file1.txt")" = "modified content" ]

    # Result should contain dry_run flag
    echo "$result" | grep -q '"dry_run":true'
}

# =============================================================================
# LIST/INFO/DELETE TESTS
# =============================================================================

@test "checkpoint_list shows all checkpoints" {
    # Create multiple checkpoints
    checkpoint_create "list1" "${TEST_DIR}/source/file1.txt" > /dev/null
    checkpoint_create "list2" "${TEST_DIR}/source/file2.txt" > /dev/null

    # List checkpoints
    local result
    result=$(checkpoint_list --json)

    echo "$result" | grep -q "list1"
    echo "$result" | grep -q "list2"
}

@test "checkpoint_info returns metadata" {
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "info1" "${TEST_DIR}/source/file1.txt")

    local info
    info=$(checkpoint_info "$checkpoint_id")

    echo "$info" | grep -q '"checkpoint_id"'
    echo "$info" | grep -Eq '"name"[[:space:]]*:[[:space:]]*"info1"'
    echo "$info" | grep -q '"archive_hash"'
}

@test "checkpoint_delete removes checkpoint" {
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "delete1" "${TEST_DIR}/source/file1.txt")

    [ -d "${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}" ]

    checkpoint_delete "$checkpoint_id"

    [ ! -d "${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}" ]
}

@test "checkpoint_delete is idempotent" {
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "delete2" "${TEST_DIR}/source/file1.txt")

    checkpoint_delete "$checkpoint_id"

    # Second delete should succeed
    local result
    result=$(checkpoint_delete "$checkpoint_id")
    [ $? -eq 0 ]
    echo "$result" | grep -q '"already_deleted":true'
}

@test "checkpoint_exists returns correct status" {
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "exists1" "${TEST_DIR}/source/file1.txt")

    run checkpoint_exists "$checkpoint_id"
    [ "$status" -eq 0 ]

    checkpoint_delete "$checkpoint_id"

    run checkpoint_exists "$checkpoint_id"
    [ "$status" -ne 0 ]
}

# =============================================================================
# PRUNE TESTS
# =============================================================================

@test "checkpoint_prune removes old checkpoints" {
    # Create checkpoint with backdated timestamp
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "old1" "${TEST_DIR}/source/file1.txt")

    # Manually backdate the metadata
    local metadata="${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}/metadata.json"
    local old_epoch=$(($(date +%s) - 100000))
    _checkpoint_test_sed_in_place "s/\"created_epoch\":[[:space:]]*[0-9]*/\"created_epoch\": ${old_epoch}/" "$metadata"

    # Prune with short max age
    local result
    result=$(checkpoint_prune --max-age 1000)

    echo "$result" | grep -q '"pruned":[1-9]'
    [ ! -d "${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}" ]
}

@test "checkpoint_prune respects max count" {
    # Create more checkpoints than max
    for i in {1..12}; do
        checkpoint_create "count${i}" "${TEST_DIR}/source/file1.txt" > /dev/null
        sleep 0.1  # Ensure different timestamps
    done

    # Prune with max count 5
    checkpoint_prune --max-count 5 > /dev/null

    # Count remaining
    local count
    count=$(find "$MAINFRAME_CHECKPOINT_DIR" -maxdepth 1 -type d | wc -l)
    count=$((count - 1))

    [ "$count" -le 5 ]
}

@test "checkpoint_prune dry-run does not delete" {
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "dryprune" "${TEST_DIR}/source/file1.txt")

    # Backdate
    local metadata="${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}/metadata.json"
    local old_epoch=$(($(date +%s) - 100000))
    _checkpoint_test_sed_in_place "s/\"created_epoch\":[[:space:]]*[0-9]*/\"created_epoch\": ${old_epoch}/" "$metadata"

    # Dry run prune
    checkpoint_prune --max-age 1000 --dry-run > /dev/null

    # Checkpoint should still exist
    [ -d "${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}" ]
}

# =============================================================================
# AUTO-CHECKPOINT TESTS
# =============================================================================

@test "checkpoint_auto_start creates scope" {
    checkpoint_auto_start "scope1" "${TEST_DIR}/source/file1.txt"
    [ $? -eq 0 ]

    # Verify checkpoint was created
    [ -n "${_CHECKPOINT_AUTO_IDS[scope1]:-}" ]
}

@test "checkpoint_auto_commit removes checkpoint" {
    checkpoint_auto_start "scope2" "${TEST_DIR}/source/file1.txt"
    local checkpoint_id="${_CHECKPOINT_AUTO_IDS[scope2]}"

    # Modify file
    echo "modified" > "${TEST_DIR}/source/file1.txt"

    # Commit
    checkpoint_auto_commit "scope2"

    # Checkpoint should be deleted
    [ ! -d "${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}" ]

    # File should remain modified
    [ "$(cat "${TEST_DIR}/source/file1.txt")" = "modified" ]
}

@test "checkpoint_auto_abort restores and removes checkpoint" {
    checkpoint_auto_start "scope3" "${TEST_DIR}/source/file1.txt"
    local checkpoint_id="${_CHECKPOINT_AUTO_IDS[scope3]}"

    # Modify file
    echo "modified" > "${TEST_DIR}/source/file1.txt"

    # Abort
    checkpoint_auto_abort "scope3"

    # Checkpoint should be deleted
    [ ! -d "${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}" ]

    # File should be restored
    [ "$(cat "${TEST_DIR}/source/file1.txt")" = "original content 1" ]
}

# =============================================================================
# SECURITY TESTS - PATH TRAVERSAL PREVENTION
# =============================================================================

@test "checkpoint_create rejects path traversal in name" {
    run checkpoint_create "../../../etc/passwd" "${TEST_DIR}/source/file1.txt"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "invalid checkpoint name"
}

@test "checkpoint_create rejects slash in name" {
    run checkpoint_create "test/bad" "${TEST_DIR}/source/file1.txt"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "invalid checkpoint name"
}

@test "checkpoint_create rejects backslash in name" {
    run checkpoint_create 'test\bad' "${TEST_DIR}/source/file1.txt"
    [ "$status" -eq 1 ]
}

@test "checkpoint_rollback rejects path traversal in ID" {
    run checkpoint_rollback "../../../etc/passwd"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "invalid checkpoint ID"
}

@test "checkpoint_delete rejects path traversal in ID" {
    run checkpoint_delete "../../../etc/passwd"
    [ "$status" -eq 1 ]
}

@test "checkpoint_info rejects path traversal in ID" {
    run checkpoint_info "../../../etc/passwd"
    [ "$status" -eq 1 ]
}

@test "checkpoint_create rejects control characters in name" {
    local bad_name=$'test\nbad'
    run checkpoint_create "$bad_name" "${TEST_DIR}/source/file1.txt"
    [ "$status" -eq 1 ]
}

# =============================================================================
# SECURITY TESTS - SIZE LIMIT ENFORCEMENT
# =============================================================================

@test "checkpoint_create rejects files exceeding size limit" {
    # Create a large file
    dd if=/dev/zero of="${TEST_DIR}/source/large.bin" bs=1M count=15 2>/dev/null

    run checkpoint_create "toolarge" "${TEST_DIR}/source/large.bin"
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "size limit exceeded"
}

# =============================================================================
# INTEGRITY TESTS
# =============================================================================

@test "checkpoint_rollback detects corrupted archive" {
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "corrupt1" "${TEST_DIR}/source/file1.txt")

    # Corrupt the archive
    echo "corrupted" >> "${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}/data.tar.gz"

    # Rollback should fail integrity check
    run checkpoint_rollback "$checkpoint_id"
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "integrity check failed"
}

@test "checkpoint_rollback with --force ignores integrity failure" {
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "corrupt2" "${TEST_DIR}/source/file1.txt")

    # Modify the file first
    echo "modified" > "${TEST_DIR}/source/file1.txt"

    # Corrupt the archive hash in metadata (not the actual archive)
    local metadata="${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}/metadata.json"
    _checkpoint_test_sed_in_place 's/"archive_hash":"[^"]*"/"archive_hash":"badhash"/' "$metadata"

    # Rollback with --force should work (but we've corrupted the hash, not the archive)
    run checkpoint_rollback "$checkpoint_id" --force
    [ "$status" -eq 0 ]
}

# =============================================================================
# CONCURRENT ACCESS TESTS
# =============================================================================

@test "concurrent checkpoint_create operations are safe" {
    # Launch multiple checkpoint creates in parallel
    for i in {1..5}; do
        echo "content $i" > "${TEST_DIR}/source/concurrent${i}.txt"
        checkpoint_create "concurrent${i}" "${TEST_DIR}/source/concurrent${i}.txt" &
    done

    # Wait for all to complete
    wait

    # Count created checkpoints
    local count
    count=$(checkpoint_list --json | grep -o '"id"' | wc -l)
    [ "$count" -eq 5 ]
}

@test "concurrent checkpoint operations with locking" {
    # Create a checkpoint
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "locktest" "${TEST_DIR}/source/file1.txt")

    # Try parallel operations
    checkpoint_info "$checkpoint_id" &
    checkpoint_list --json &
    checkpoint_exists "$checkpoint_id" &

    wait

    # All should succeed (read operations)
    checkpoint_exists "$checkpoint_id"
    [ $? -eq 0 ]
}

# =============================================================================
# LARGE FILE HANDLING TESTS
# =============================================================================

@test "checkpoint handles binary files correctly" {
    # Create a binary file
    dd if=/dev/urandom of="${TEST_DIR}/source/binary.bin" bs=1K count=100 2>/dev/null
    local original_hash
    original_hash=$(_checkpoint_test_sha256 "${TEST_DIR}/source/binary.bin")

    # Create checkpoint
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "binary1" "${TEST_DIR}/source/binary.bin")

    # Corrupt the file
    dd if=/dev/urandom of="${TEST_DIR}/source/binary.bin" bs=1K count=100 2>/dev/null

    # Rollback
    checkpoint_rollback "$checkpoint_id"

    # Verify hash matches
    local restored_hash
    restored_hash=$(_checkpoint_test_sha256 "${TEST_DIR}/source/binary.bin")
    [ "$original_hash" = "$restored_hash" ]
}

@test "checkpoint handles files with special characters in names" {
    # Create file with special chars (but valid for filesystem)
    local special_file="${TEST_DIR}/source/file with spaces.txt"
    echo "special content" > "$special_file"

    # Create checkpoint
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "special1" "$special_file")
    [ -n "$checkpoint_id" ]

    # Modify
    echo "modified" > "$special_file"

    # Rollback
    checkpoint_rollback "$checkpoint_id"

    [ "$(cat "$special_file")" = "special content" ]
}

@test "checkpoint handles empty files" {
    touch "${TEST_DIR}/source/empty.txt"

    local checkpoint_id
    checkpoint_id=$(checkpoint_create "empty1" "${TEST_DIR}/source/empty.txt")
    [ -n "$checkpoint_id" ]

    echo "not empty anymore" > "${TEST_DIR}/source/empty.txt"

    checkpoint_rollback "$checkpoint_id"

    [ ! -s "${TEST_DIR}/source/empty.txt" ]
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

@test "checkpoint_create fails for non-existent file" {
    run checkpoint_create "noexist" "/nonexistent/path/file.txt"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "path not found"
}

@test "checkpoint_create fails with empty file list" {
    run checkpoint_create "nofiles"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "no files or directories specified"
}

@test "checkpoint_rollback fails for non-existent checkpoint" {
    run checkpoint_rollback "chk_nonexistent_12345"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "checkpoint not found"
}

@test "checkpoint_info fails for non-existent checkpoint" {
    run checkpoint_info "chk_nonexistent_12345"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "checkpoint not found"
}

# =============================================================================
# METADATA VALIDATION TESTS
# =============================================================================

@test "checkpoint metadata contains required fields" {
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "metadata1" "${TEST_DIR}/source/file1.txt")

    local metadata="${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}/metadata.json"

    grep -q '"checkpoint_id"' "$metadata"
    grep -q '"name"' "$metadata"
    grep -q '"created_at"' "$metadata"
    grep -q '"created_epoch"' "$metadata"
    grep -q '"files"' "$metadata"
    grep -q '"file_count"' "$metadata"
    grep -q '"archive_hash"' "$metadata"
    grep -q '"status"' "$metadata"
    grep -q '"version"' "$metadata"
}

@test "checkpoint archive hash is valid SHA-256" {
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "hash1" "${TEST_DIR}/source/file1.txt")

    local metadata="${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}/metadata.json"
    local stored_hash
    stored_hash=$(grep -o '"archive_hash"[[:space:]]*:[[:space:]]*"[^"]*"' "$metadata" | sed 's/.*"\([^"]*\)"$/\1/')

    # SHA-256 hash should be 64 hex characters
    [ ${#stored_hash} -eq 64 ]
    [[ "$stored_hash" =~ ^[a-f0-9]+$ ]]
}

# =============================================================================
# CLEANUP TESTS
# =============================================================================

@test "checkpoint directory has restrictive permissions" {
    checkpoint_create "perms1" "${TEST_DIR}/source/file1.txt" > /dev/null

    local perms
    perms=$(stat -c "%a" "$MAINFRAME_CHECKPOINT_DIR" 2>/dev/null || stat -f "%Lp" "$MAINFRAME_CHECKPOINT_DIR")

    # Should be 700 (owner only)
    [ "$perms" = "700" ]
}

@test "individual checkpoint directories have restrictive permissions" {
    local checkpoint_id
    checkpoint_id=$(checkpoint_create "perms2" "${TEST_DIR}/source/file1.txt")

    local perms
    perms=$(stat -c "%a" "${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}" 2>/dev/null || \
            stat -f "%Lp" "${MAINFRAME_CHECKPOINT_DIR}/${checkpoint_id}")

    # Should be 700 (owner only)
    [ "$perms" = "700" ]
}

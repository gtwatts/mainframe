#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Atomic File Operations Tests
# =============================================================================

load 'test_helper'

setup() {
    source_lib "atomic"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "atomic")
    export MAINFRAME_CHECKPOINT_DIR="$TEST_DIR/.checkpoints"
    export MAINFRAME_TRASH_DIR="$TEST_DIR/.trash"
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# atomic_write TESTS
# =============================================================================

@test "atomic_write creates new file" {
    atomic_write "$TEST_DIR/new.txt" "hello"
    local content
    content=$(<"$TEST_DIR/new.txt")
    [ "$content" = "hello" ]
}

@test "atomic_write overwrites existing file" {
    echo "old" > "$TEST_DIR/exist.txt"
    atomic_write "$TEST_DIR/exist.txt" "new"
    local content
    content=$(<"$TEST_DIR/exist.txt")
    [ "$content" = "new" ]
}

@test "atomic_write sets permissions" {
    atomic_write "$TEST_DIR/perm.txt" "secret" "0600"
    local mode
    mode=$(file_mode "$TEST_DIR/perm.txt")
    [ "$mode" = "600" ]
}

@test "atomic_write creates parent directories" {
    atomic_write "$TEST_DIR/deep/nested/file.txt" "data"
    [ -f "$TEST_DIR/deep/nested/file.txt" ]
}

@test "atomic_write preserves existing permissions" {
    echo "test" > "$TEST_DIR/existing.txt"
    chmod 0640 "$TEST_DIR/existing.txt"
    atomic_write "$TEST_DIR/existing.txt" "updated"
    local mode
    mode=$(file_mode "$TEST_DIR/existing.txt")
    [ "$mode" = "640" ]
}

@test "atomic_write no temp file left on success" {
    atomic_write "$TEST_DIR/clean.txt" "data"
    local temps
    temps=$(find "$TEST_DIR" -name ".mainframe_atomic.*" 2>/dev/null | wc -l)
    [ "$temps" -eq 0 ]
}

@test "atomic_write handles multiline content" {
    local content=$'line1\nline2\nline3'
    atomic_write "$TEST_DIR/multi.txt" "$content"
    local result
    result=$(<"$TEST_DIR/multi.txt")
    [ "$result" = "$content" ]
}

@test "atomic_write fails with empty path" {
    ! atomic_write "" "content"
}

# =============================================================================
# atomic_append TESTS
# =============================================================================

@test "atomic_append adds to file" {
    echo "first" > "$TEST_DIR/append.txt"
    atomic_append "$TEST_DIR/append.txt" "second"
    grep -q "second" "$TEST_DIR/append.txt"
}

@test "atomic_append creates file if missing" {
    atomic_append "$TEST_DIR/new_append.txt" "content"
    [ -f "$TEST_DIR/new_append.txt" ]
}

@test "atomic_append adds newline" {
    atomic_append "$TEST_DIR/nl.txt" "line1"
    atomic_append "$TEST_DIR/nl.txt" "line2"
    local content
    content=$(<"$TEST_DIR/nl.txt")
    [ "$content" = $'line1\nline2' ]
}

@test "atomic_append fails with empty args" {
    ! atomic_append "" "content"
    ! atomic_append "$TEST_DIR/f.txt" ""
}

# =============================================================================
# atomic_replace TESTS
# =============================================================================

@test "atomic_replace replaces content" {
    echo "original" > "$TEST_DIR/replace.txt"
    atomic_replace "$TEST_DIR/replace.txt" "replaced"
    local content
    content=$(<"$TEST_DIR/replace.txt")
    [ "$content" = "replaced" ]
}

@test "atomic_replace creates backup" {
    echo "original" > "$TEST_DIR/backup.txt"
    atomic_replace "$TEST_DIR/backup.txt" "new"
    local backup
    backup=$(ls "$TEST_DIR"/backup.txt.bak.* 2>/dev/null | head -1)
    [ -n "$backup" ]
}

@test "atomic_replace backup contains original content" {
    echo "save-me" > "$TEST_DIR/bk.txt"
    atomic_replace "$TEST_DIR/bk.txt" "changed"
    local backup_file
    backup_file=$(ls "$TEST_DIR"/bk.txt.bak.* 2>/dev/null | head -1)
    local backup_content
    backup_content=$(<"$backup_file")
    [ "$backup_content" = "save-me" ]
}

@test "atomic_replace rolls back on verify failure" {
    echo "good-config" > "$TEST_DIR/verify.txt"
    ! atomic_replace "$TEST_DIR/verify.txt" "bad" "false"
    local content
    content=$(<"$TEST_DIR/verify.txt")
    [ "$content" = "good-config" ]
}

@test "atomic_replace succeeds with passing verify" {
    echo "old" > "$TEST_DIR/pass.txt"
    atomic_replace "$TEST_DIR/pass.txt" "new" "true"
    local content
    content=$(<"$TEST_DIR/pass.txt")
    [ "$content" = "new" ]
}

# =============================================================================
# safe_remove / safe_restore TESTS
# =============================================================================

@test "safe_remove moves file to trash" {
    echo "deleteme" > "$TEST_DIR/trash.txt"
    safe_remove "$TEST_DIR/trash.txt"
    [ ! -e "$TEST_DIR/trash.txt" ]
    [ -d "$MAINFRAME_TRASH_DIR" ]
}

@test "safe_remove is idempotent (missing file ok)" {
    safe_remove "$TEST_DIR/nonexistent.txt"
}

@test "safe_remove stores origin metadata" {
    echo "data" > "$TEST_DIR/origin.txt"
    safe_remove "$TEST_DIR/origin.txt"
    local origin_files
    origin_files=$(ls "$MAINFRAME_TRASH_DIR"/*.origin 2>/dev/null | wc -l)
    [ "$origin_files" -ge "1" ]
}

@test "safe_restore recovers trashed file" {
    echo "recoverable" > "$TEST_DIR/recover.txt"
    safe_remove "$TEST_DIR/recover.txt"
    [ ! -e "$TEST_DIR/recover.txt" ]
    safe_restore "recover.txt"
    [ -f "$TEST_DIR/recover.txt" ]
    local content
    content=$(<"$TEST_DIR/recover.txt")
    [ "$content" = "recoverable" ]
}

@test "safe_restore fails for unknown file" {
    ! safe_restore "never_existed.txt"
}

# =============================================================================
# file_checkpoint / file_rollback TESTS
# =============================================================================

@test "file_checkpoint creates checkpoint" {
    echo "state1" > "$TEST_DIR/check.txt"
    file_checkpoint "$TEST_DIR/check.txt" "v1"
    [ -d "$MAINFRAME_CHECKPOINT_DIR" ]
}

@test "file_rollback restores from checkpoint" {
    echo "state1" > "$TEST_DIR/roll.txt"
    file_checkpoint "$TEST_DIR/roll.txt" "before"
    echo "state2" > "$TEST_DIR/roll.txt"
    file_rollback "$TEST_DIR/roll.txt" "before"
    local content
    content=$(<"$TEST_DIR/roll.txt")
    [ "$content" = "state1" ]
}

@test "file_checkpoint is idempotent (same name overwrites)" {
    echo "v1" > "$TEST_DIR/idem.txt"
    file_checkpoint "$TEST_DIR/idem.txt" "snap"
    echo "v2" > "$TEST_DIR/idem.txt"
    file_checkpoint "$TEST_DIR/idem.txt" "snap"
    file_rollback "$TEST_DIR/idem.txt" "snap"
    local content
    content=$(<"$TEST_DIR/idem.txt")
    [ "$content" = "v2" ]
}

@test "file_checkpoint supports multiple named checkpoints" {
    echo "alpha" > "$TEST_DIR/multi.txt"
    file_checkpoint "$TEST_DIR/multi.txt" "first"
    echo "beta" > "$TEST_DIR/multi.txt"
    file_checkpoint "$TEST_DIR/multi.txt" "second"
    echo "gamma" > "$TEST_DIR/multi.txt"

    file_rollback "$TEST_DIR/multi.txt" "first"
    local content
    content=$(<"$TEST_DIR/multi.txt")
    [ "$content" = "alpha" ]
}

@test "file_rollback fails for nonexistent checkpoint" {
    echo "data" > "$TEST_DIR/nocp.txt"
    ! file_rollback "$TEST_DIR/nocp.txt" "nonexistent"
}

@test "file_checkpoint fails for nonexistent file" {
    ! file_checkpoint "$TEST_DIR/nope.txt" "snap"
}

@test "file_checkpoints lists checkpoints" {
    echo "data" > "$TEST_DIR/listed.txt"
    file_checkpoint "$TEST_DIR/listed.txt" "mysnap"
    local output
    output=$(file_checkpoints "$TEST_DIR/listed.txt")
    [[ "$output" == *"mysnap"* ]]
}

# =============================================================================
# file_checkpoint_cleanup TESTS
# =============================================================================

@test "file_checkpoint_cleanup removes old checkpoints" {
    echo "old" > "$TEST_DIR/old.txt"
    file_checkpoint "$TEST_DIR/old.txt" "ancient"
    # Backdate the checkpoint file
    touch -t 202001010000 "$MAINFRAME_CHECKPOINT_DIR"/*
    file_checkpoint_cleanup 1
    local remaining
    remaining=$(ls "$MAINFRAME_CHECKPOINT_DIR"/* 2>/dev/null | grep -v ".meta" | wc -l)
    [ "$remaining" -eq 0 ]
}

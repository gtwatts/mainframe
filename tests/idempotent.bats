#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Idempotent Operations Tests
# =============================================================================

load 'test_helper'

setup() {
    source_lib "idempotent"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "idempotent")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# ensure_dir TESTS
# =============================================================================

@test "ensure_dir creates directory" {
    ensure_dir "$TEST_DIR/newdir"
    [ -d "$TEST_DIR/newdir" ]
}

@test "ensure_dir is idempotent (second call succeeds)" {
    ensure_dir "$TEST_DIR/newdir"
    ensure_dir "$TEST_DIR/newdir"
    [ -d "$TEST_DIR/newdir" ]
}

@test "ensure_dir creates nested directories" {
    ensure_dir "$TEST_DIR/a/b/c/d"
    [ -d "$TEST_DIR/a/b/c/d" ]
}

@test "ensure_dir sets permissions" {
    ensure_dir "$TEST_DIR/permdir" "0750"
    local mode
    mode=$(stat -c '%a' "$TEST_DIR/permdir")
    [ "$mode" = "750" ]
}

@test "ensure_dir fixes permissions on existing dir" {
    mkdir -p "$TEST_DIR/fixdir"
    chmod 0777 "$TEST_DIR/fixdir"
    ensure_dir "$TEST_DIR/fixdir" "0755"
    local mode
    mode=$(stat -c '%a' "$TEST_DIR/fixdir")
    [ "$mode" = "755" ]
}

@test "ensure_dir fails if path is a file" {
    touch "$TEST_DIR/afile"
    ! ensure_dir "$TEST_DIR/afile"
}

@test "ensure_dir fails with empty arg" {
    ! ensure_dir ""
}

# =============================================================================
# ensure_file TESTS
# =============================================================================

@test "ensure_file creates empty file" {
    ensure_file "$TEST_DIR/newfile.txt"
    [ -f "$TEST_DIR/newfile.txt" ]
    [ ! -s "$TEST_DIR/newfile.txt" ]
}

@test "ensure_file creates file with content" {
    ensure_file "$TEST_DIR/content.txt" "hello world"
    local content
    content=$(<"$TEST_DIR/content.txt")
    [ "$content" = "hello world" ]
}

@test "ensure_file is idempotent with same content" {
    ensure_file "$TEST_DIR/idem.txt" "same"
    ensure_file "$TEST_DIR/idem.txt" "same"
    local content
    content=$(<"$TEST_DIR/idem.txt")
    [ "$content" = "same" ]
}

@test "ensure_file updates when content differs" {
    ensure_file "$TEST_DIR/update.txt" "old"
    ensure_file "$TEST_DIR/update.txt" "new"
    local content
    content=$(<"$TEST_DIR/update.txt")
    [ "$content" = "new" ]
}

@test "ensure_file creates parent directories" {
    ensure_file "$TEST_DIR/deep/nested/file.txt" "data"
    [ -f "$TEST_DIR/deep/nested/file.txt" ]
}

@test "ensure_file sets permissions" {
    ensure_file "$TEST_DIR/perm.txt" "secret" "0600"
    local mode
    mode=$(stat -c '%a' "$TEST_DIR/perm.txt")
    [ "$mode" = "600" ]
}

@test "ensure_file fails with empty arg" {
    ! ensure_file ""
}

# =============================================================================
# ensure_line TESTS
# =============================================================================

@test "ensure_line adds line to empty file" {
    touch "$TEST_DIR/lines.txt"
    ensure_line "$TEST_DIR/lines.txt" "first line"
    grep -q "first line" "$TEST_DIR/lines.txt"
}

@test "ensure_line is idempotent (no duplicate)" {
    touch "$TEST_DIR/lines.txt"
    ensure_line "$TEST_DIR/lines.txt" "unique"
    ensure_line "$TEST_DIR/lines.txt" "unique"
    local count
    count=$(grep -c "unique" "$TEST_DIR/lines.txt")
    [ "$count" = "1" ]
}

@test "ensure_line creates file if missing" {
    ensure_line "$TEST_DIR/created.txt" "auto-created"
    [ -f "$TEST_DIR/created.txt" ]
    grep -q "auto-created" "$TEST_DIR/created.txt"
}

@test "ensure_line uses marker for matching" {
    printf 'export PATH="/opt/bin:$PATH"  # MY_MARKER\n' > "$TEST_DIR/bashrc"
    ensure_line "$TEST_DIR/bashrc" 'export PATH="/opt/new:$PATH"' "MY_MARKER"
    # Should NOT add since marker exists
    local count
    count=$(wc -l < "$TEST_DIR/bashrc")
    [ "$count" = "1" ]
}

@test "ensure_line appends when marker not found" {
    printf 'existing line\n' > "$TEST_DIR/append.txt"
    ensure_line "$TEST_DIR/append.txt" "new line" "NEW_MARKER"
    local count
    count=$(wc -l < "$TEST_DIR/append.txt")
    [ "$count" = "2" ]
}

@test "ensure_line fails with empty args" {
    ! ensure_line "" "line"
    ! ensure_line "$TEST_DIR/f.txt" ""
}

# =============================================================================
# ensure_symlink TESTS
# =============================================================================

@test "ensure_symlink creates new symlink" {
    touch "$TEST_DIR/target"
    ensure_symlink "$TEST_DIR/target" "$TEST_DIR/link"
    [ -L "$TEST_DIR/link" ]
    [ "$(readlink "$TEST_DIR/link")" = "$TEST_DIR/target" ]
}

@test "ensure_symlink is idempotent (correct link exists)" {
    touch "$TEST_DIR/target"
    ensure_symlink "$TEST_DIR/target" "$TEST_DIR/link"
    ensure_symlink "$TEST_DIR/target" "$TEST_DIR/link"
    [ -L "$TEST_DIR/link" ]
}

@test "ensure_symlink fixes wrong target" {
    touch "$TEST_DIR/target1"
    touch "$TEST_DIR/target2"
    ln -sf "$TEST_DIR/target1" "$TEST_DIR/link"
    ensure_symlink "$TEST_DIR/target2" "$TEST_DIR/link"
    [ "$(readlink "$TEST_DIR/link")" = "$TEST_DIR/target2" ]
}

@test "ensure_symlink fails when file exists (no force)" {
    echo "content" > "$TEST_DIR/blocker"
    ! ensure_symlink "$TEST_DIR/target" "$TEST_DIR/blocker"
}

@test "ensure_symlink replaces file with force" {
    touch "$TEST_DIR/target"
    echo "content" > "$TEST_DIR/blocker"
    ensure_symlink "$TEST_DIR/target" "$TEST_DIR/blocker" true
    [ -L "$TEST_DIR/blocker" ]
}

@test "ensure_symlink creates parent directories" {
    touch "$TEST_DIR/target"
    ensure_symlink "$TEST_DIR/target" "$TEST_DIR/deep/nested/link"
    [ -L "$TEST_DIR/deep/nested/link" ]
}

@test "ensure_symlink fails with empty args" {
    ! ensure_symlink "" "$TEST_DIR/link"
    ! ensure_symlink "$TEST_DIR/target" ""
}

# =============================================================================
# ensure_command TESTS
# =============================================================================

@test "ensure_command succeeds for existing command" {
    ensure_command "bash"
}

@test "ensure_command fails for missing command" {
    ! ensure_command "nonexistent_command_xyz_12345"
}

# =============================================================================
# ensure_dirs TESTS
# =============================================================================

@test "ensure_dirs creates multiple directories" {
    ensure_dirs "$TEST_DIR/a" "$TEST_DIR/b" "$TEST_DIR/c"
    [ -d "$TEST_DIR/a" ]
    [ -d "$TEST_DIR/b" ]
    [ -d "$TEST_DIR/c" ]
}

# =============================================================================
# ensure_lines TESTS
# =============================================================================

@test "ensure_lines adds multiple lines" {
    touch "$TEST_DIR/multi.txt"
    ensure_lines "$TEST_DIR/multi.txt" "line1" "line2" "line3"
    local count
    count=$(wc -l < "$TEST_DIR/multi.txt")
    [ "$count" = "3" ]
}

@test "ensure_lines is idempotent for all lines" {
    touch "$TEST_DIR/multi.txt"
    ensure_lines "$TEST_DIR/multi.txt" "a" "b" "c"
    ensure_lines "$TEST_DIR/multi.txt" "a" "b" "c"
    local count
    count=$(wc -l < "$TEST_DIR/multi.txt")
    [ "$count" = "3" ]
}

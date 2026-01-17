#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/test_path.bats - Path Library Tests
# =============================================================================
# Run with: bats tests/unit/test_path.bats
# =============================================================================

setup() {
    # Get the directory containing this test file
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

    # Source the library
    source "$PROJECT_ROOT/lib/path.sh"

    # Create temp directory for tests
    TEST_TMPDIR=$(mktemp -d)
}

teardown() {
    # Clean up temp directory
    [[ -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# PATH NORMALIZATION
# =============================================================================

@test "path_normalize: collapses multiple slashes" {
    result=$(path_normalize "/foo//bar///baz")
    [[ "$result" == "/foo/bar/baz" ]]
}

@test "path_normalize: resolves single dot" {
    result=$(path_normalize "/foo/./bar/./baz")
    [[ "$result" == "/foo/bar/baz" ]]
}

@test "path_normalize: resolves parent references" {
    result=$(path_normalize "/foo/bar/../baz")
    [[ "$result" == "/foo/baz" ]]
}

@test "path_normalize: complex path with multiple .. and ." {
    result=$(path_normalize "/foo/bar/baz/../../qux/./quux")
    [[ "$result" == "/foo/qux/quux" ]]
}

@test "path_normalize: handles root" {
    result=$(path_normalize "/")
    [[ "$result" == "/" ]]
}

@test "path_normalize: handles empty path" {
    result=$(path_normalize "")
    [[ "$result" == "." ]]
}

@test "path_normalize: removes trailing slashes" {
    result=$(path_normalize "/foo/bar/")
    [[ "$result" == "/foo/bar" ]]
}

@test "path_normalize: keeps .. for relative paths when needed" {
    result=$(path_normalize "../foo/bar")
    [[ "$result" == "../foo/bar" ]]
}

@test "path_normalize: stops at root for absolute paths" {
    result=$(path_normalize "/foo/../../bar")
    [[ "$result" == "/bar" ]]
}

@test "path_absolute: returns absolute for relative path" {
    cd "$TEST_TMPDIR"
    result=$(path_absolute "foo/bar")
    [[ "$result" == "$TEST_TMPDIR/foo/bar" ]]
}

@test "path_absolute: normalizes already absolute path" {
    result=$(path_absolute "/foo//bar/../baz")
    [[ "$result" == "/foo/baz" ]]
}

@test "path_absolute: expands tilde" {
    result=$(path_absolute "~/foo")
    [[ "$result" == "$HOME/foo" ]]
}

@test "path_relative: simple case" {
    result=$(path_relative "/a/b/c" "/a")
    [[ "$result" == "b/c" ]]
}

@test "path_relative: same path returns dot" {
    result=$(path_relative "/foo/bar" "/foo/bar")
    [[ "$result" == "." ]]
}

@test "path_relative: requires parent traversal" {
    result=$(path_relative "/a/b/c" "/a/d/e")
    [[ "$result" == "../../b/c" ]]
}

# =============================================================================
# PATH COMPONENTS
# =============================================================================

@test "path_dir: extracts directory" {
    result=$(path_dir "/foo/bar/baz.txt")
    [[ "$result" == "/foo/bar" ]]
}

@test "path_dir: handles filename only" {
    result=$(path_dir "file.txt")
    [[ "$result" == "." ]]
}

@test "path_dir: handles root file" {
    result=$(path_dir "/file.txt")
    [[ "$result" == "/" ]]
}

@test "path_dir: handles empty path" {
    result=$(path_dir "")
    [[ "$result" == "." ]]
}

@test "path_base: extracts filename" {
    result=$(path_base "/foo/bar/baz.txt")
    [[ "$result" == "baz.txt" ]]
}

@test "path_base: handles path without dir" {
    result=$(path_base "file.txt")
    [[ "$result" == "file.txt" ]]
}

@test "path_base: handles trailing slash" {
    result=$(path_base "/foo/bar/")
    [[ "$result" == "bar" ]]
}

@test "path_ext: extracts extension" {
    result=$(path_ext "/foo/bar.txt")
    [[ "$result" == "txt" ]]
}

@test "path_ext: handles multiple extensions - returns last" {
    result=$(path_ext "/foo/bar.tar.gz")
    [[ "$result" == "gz" ]]
}

@test "path_ext: returns empty for no extension" {
    result=$(path_ext "/foo/bar")
    [[ -z "$result" ]]
}

@test "path_ext: handles hidden files without extension" {
    result=$(path_ext ".bashrc")
    [[ -z "$result" ]]
}

@test "path_ext: handles hidden files with extension" {
    result=$(path_ext ".bashrc.bak")
    [[ "$result" == "bak" ]]
}

@test "path_ext_full: returns all extensions" {
    result=$(path_ext_full "/foo/bar.tar.gz")
    [[ "$result" == "tar.gz" ]]
}

@test "path_stem: removes last extension" {
    result=$(path_stem "/foo/bar.tar.gz")
    [[ "$result" == "bar.tar" ]]
}

@test "path_stem: handles file without extension" {
    result=$(path_stem "/foo/bar")
    [[ "$result" == "bar" ]]
}

@test "path_stem: handles hidden file" {
    result=$(path_stem ".bashrc")
    [[ "$result" == ".bashrc" ]]
}

@test "path_stem_full: removes all extensions" {
    result=$(path_stem_full "/foo/bar.tar.gz")
    [[ "$result" == "bar" ]]
}

@test "path_stem_full: handles hidden file with extension" {
    result=$(path_stem_full ".bashrc.bak")
    [[ "$result" == ".bashrc" ]]
}

# =============================================================================
# PATH CONSTRUCTION
# =============================================================================

@test "path_join: joins multiple components" {
    result=$(path_join "/foo" "bar" "baz")
    [[ "$result" == "/foo/bar/baz" ]]
}

@test "path_join: handles trailing slashes" {
    result=$(path_join "/foo/" "/bar/" "baz")
    [[ "$result" == "/foo/bar/baz" ]]
}

@test "path_join: handles empty components" {
    result=$(path_join "/foo" "" "bar")
    [[ "$result" == "/foo/bar" ]]
}

@test "path_join: preserves root" {
    result=$(path_join "/" "foo" "bar")
    [[ "$result" == "/foo/bar" ]]
}

@test "path_replace_ext: replaces extension" {
    result=$(path_replace_ext "/foo/bar.txt" "md")
    [[ "$result" == "/foo/bar.md" ]]
}

@test "path_replace_ext: adds extension to file without" {
    result=$(path_replace_ext "/foo/bar" "txt")
    [[ "$result" == "/foo/bar.txt" ]]
}

@test "path_replace_ext: removes extension with empty" {
    result=$(path_replace_ext "/foo/bar.txt" "")
    [[ "$result" == "/foo/bar" ]]
}

@test "path_add_suffix: adds suffix before extension" {
    result=$(path_add_suffix "/foo/bar.txt" "_backup")
    [[ "$result" == "/foo/bar_backup.txt" ]]
}

@test "path_add_suffix: handles file without extension" {
    result=$(path_add_suffix "/foo/bar" "_backup")
    [[ "$result" == "/foo/bar_backup" ]]
}

# =============================================================================
# CROSS-PLATFORM
# =============================================================================

@test "path_to_unix: converts Windows path" {
    result=$(path_to_unix 'C:\Users\foo\file.txt')
    [[ "$result" == "/c/Users/foo/file.txt" ]]
}

@test "path_to_unix: handles lowercase drive" {
    result=$(path_to_unix 'd:\data')
    [[ "$result" == "/d/data" ]]
}

@test "path_to_windows: converts Unix path" {
    result=$(path_to_windows "/c/Users/foo/file.txt")
    [[ "$result" == 'C:\Users\foo\file.txt' ]]
}

@test "path_style: detects Windows path" {
    result=$(path_style 'C:\Users\foo')
    [[ "$result" == "windows" ]]
}

@test "path_style: detects Unix absolute path" {
    result=$(path_style "/foo/bar")
    [[ "$result" == "unix" ]]
}

@test "path_style: detects relative path" {
    result=$(path_style "foo/bar")
    [[ "$result" == "relative" ]]
}

# =============================================================================
# SAFETY
# =============================================================================

@test "path_quote: leaves safe path unchanged" {
    result=$(path_quote "/foo/bar/baz.txt")
    [[ "$result" == "/foo/bar/baz.txt" ]]
}

@test "path_quote: escapes path with spaces" {
    result=$(path_quote "/foo/bar baz/file.txt")
    # Should be properly escaped - check it contains escape chars or quotes
    [[ "$result" != "/foo/bar baz/file.txt" ]]
}

@test "path_is_safe: allows path within base" {
    path_is_safe "/base" "/base/sub/file.txt"
}

@test "path_is_safe: allows exact base path" {
    path_is_safe "/base" "/base"
}

@test "path_is_safe: rejects path outside base" {
    ! path_is_safe "/base" "/other/file.txt"
}

@test "path_is_safe: rejects traversal attack" {
    ! path_is_safe "/base" "/base/../other/file.txt"
}

@test "path_is_safe: handles relative path against base" {
    path_is_safe "/base" "sub/file.txt"
}

@test "path_ensure_dir: creates parent directories" {
    local path="$TEST_TMPDIR/a/b/c/file.txt"
    path_ensure_dir "$path"
    [[ -d "$TEST_TMPDIR/a/b/c" ]]
}

@test "path_sanitize: removes unsafe characters" {
    result=$(path_sanitize 'file: <bad> "chars"?.txt')
    [[ "$result" != *":"* ]]
    [[ "$result" != *"<"* ]]
    [[ "$result" != *">"* ]]
    [[ "$result" != *"?"* ]]
    [[ "$result" != *'"'* ]]
}

@test "path_sanitize: handles multiple bad chars" {
    result=$(path_sanitize 'a::b')
    # Should not have multiple underscores in a row
    [[ "$result" != *"__"* ]]
}

# =============================================================================
# EXPANSION
# =============================================================================

@test "path_expand_tilde: expands ~ to HOME" {
    result=$(path_expand_tilde "~/Documents")
    [[ "$result" == "$HOME/Documents" ]]
}

@test "path_expand_tilde: expands ~ alone" {
    result=$(path_expand_tilde "~")
    [[ "$result" == "$HOME" ]]
}

@test "path_expand_tilde: leaves non-tilde path unchanged" {
    result=$(path_expand_tilde "/foo/bar")
    [[ "$result" == "/foo/bar" ]]
}

@test "path_common_prefix: finds common directory" {
    result=$(path_common_prefix "/a/b/c" "/a/b/d")
    [[ "$result" == "/a/b" ]]
}

@test "path_common_prefix: handles root-only common" {
    result=$(path_common_prefix "/foo/bar" "/baz/qux")
    [[ "$result" == "/" ]]
}

@test "path_common_prefix: handles identical paths" {
    result=$(path_common_prefix "/a/b/c" "/a/b/c")
    [[ "$result" == "/a/b" ]]
}

@test "path_common_prefix: handles multiple paths" {
    result=$(path_common_prefix "/a/b/c" "/a/b/d" "/a/b/e")
    [[ "$result" == "/a/b" ]]
}

# =============================================================================
# PATH CHECKS
# =============================================================================

@test "path_is_absolute: true for absolute path" {
    path_is_absolute "/foo/bar"
}

@test "path_is_absolute: false for relative path" {
    ! path_is_absolute "foo/bar"
}

@test "path_is_relative: true for relative path" {
    path_is_relative "foo/bar"
}

@test "path_is_relative: false for absolute path" {
    ! path_is_relative "/foo/bar"
}

@test "path_has_parent_ref: detects .." {
    path_has_parent_ref "../foo"
}

@test "path_has_parent_ref: detects .. in middle" {
    path_has_parent_ref "foo/../bar"
}

@test "path_has_parent_ref: false for normal path" {
    ! path_has_parent_ref "/foo/bar"
}

@test "path_is_hidden: true for hidden file" {
    path_is_hidden ".bashrc"
}

@test "path_is_hidden: true for hidden in path" {
    path_is_hidden "/foo/.hidden"
}

@test "path_is_hidden: false for normal file" {
    ! path_is_hidden "file.txt"
}

@test "path_equals: true for equivalent paths" {
    path_equals "/foo/bar/../baz" "/foo/baz"
}

@test "path_equals: false for different paths" {
    ! path_equals "/foo/bar" "/foo/baz"
}

@test "path_depth: counts path components" {
    result=$(path_depth "/foo/bar/baz")
    [[ "$result" == "3" ]]
}

@test "path_depth: root has depth 0" {
    result=$(path_depth "/")
    [[ "$result" == "0" ]]
}

@test "path_split: splits into array" {
    declare -a parts
    path_split "/foo/bar/baz" parts
    [[ "${parts[0]}" == "foo" ]]
    [[ "${parts[1]}" == "bar" ]]
    [[ "${parts[2]}" == "baz" ]]
    [[ "${#parts[@]}" == "3" ]]
}

# =============================================================================
# FILENAME UTILITIES
# =============================================================================

@test "path_unique: returns original if not exists" {
    result=$(path_unique "$TEST_TMPDIR/nonexistent.txt")
    [[ "$result" == "$TEST_TMPDIR/nonexistent.txt" ]]
}

@test "path_unique: generates unique name if exists" {
    touch "$TEST_TMPDIR/exists.txt"
    result=$(path_unique "$TEST_TMPDIR/exists.txt")
    [[ "$result" == "$TEST_TMPDIR/exists (1).txt" ]]
}

@test "path_unique: increments counter for multiple" {
    touch "$TEST_TMPDIR/file.txt"
    touch "$TEST_TMPDIR/file (1).txt"
    result=$(path_unique "$TEST_TMPDIR/file.txt")
    [[ "$result" == "$TEST_TMPDIR/file (2).txt" ]]
}

@test "path_resolve: resolves symlink" {
    # Create a real file and symlink
    echo "content" > "$TEST_TMPDIR/real.txt"
    ln -s "$TEST_TMPDIR/real.txt" "$TEST_TMPDIR/link.txt"

    result=$(path_resolve "$TEST_TMPDIR/link.txt")
    [[ "$result" == "$TEST_TMPDIR/real.txt" ]]
}

@test "path_resolve: returns normalized path for non-symlink" {
    echo "content" > "$TEST_TMPDIR/file.txt"
    result=$(path_resolve "$TEST_TMPDIR/file.txt")
    [[ "$result" == "$TEST_TMPDIR/file.txt" ]]
}

# =============================================================================
# EDGE CASES: PATHS WITH SPACES
# =============================================================================

@test "path_dir: handles spaces in path" {
    result=$(path_dir "/foo/bar baz/file.txt")
    [[ "$result" == "/foo/bar baz" ]]
}

@test "path_base: handles spaces in filename" {
    result=$(path_base "/foo/my file.txt")
    [[ "$result" == "my file.txt" ]]
}

@test "path_join: handles spaces" {
    result=$(path_join "/foo" "bar baz" "file.txt")
    [[ "$result" == "/foo/bar baz/file.txt" ]]
}

@test "path_normalize: handles spaces" {
    result=$(path_normalize "/foo/bar baz/../qux")
    [[ "$result" == "/foo/qux" ]]
}

@test "path_is_safe: handles spaces in paths" {
    path_is_safe "/base dir" "/base dir/sub/file.txt"
}

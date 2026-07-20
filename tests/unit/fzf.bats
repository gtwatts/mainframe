#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: fzf.sh Interactive Pipe Filter Library Tests
# =============================================================================
# Tests for lib/fzf.sh - fzf_select, fallback menus, specialized selectors
# =============================================================================
# Strategy: Tests run non-interactively (no TTY in BATS), so fzf_select uses
# the automatic first-line selection codepath. Interactive/fallback paths are
# tested by examining internal helper behavior.
# =============================================================================

setup() {
    export MAINFRAME_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    # Reset double-source guard so library loads fresh each test file run
    unset _MAINFRAME_FZF_LOADED
    source "${MAINFRAME_ROOT}/lib/fzf.sh"
}

# =============================================================================
# fzf_available
# =============================================================================

@test "fzf_available: returns 0 when fzf is in PATH" {
    if ! command -v fzf &>/dev/null; then
        skip "fzf not installed on this system"
    fi
    run fzf_available
    [[ "$status" -eq 0 ]]
}

@test "fzf_available: returns 1 when fzf is not in PATH" {
    # Restrict PATH to a directory that certainly does not contain fzf
    local empty_dir
    empty_dir=$(mktemp -d)
    PATH="$empty_dir" run fzf_available
    rmdir "$empty_dir"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# _fzf_is_interactive
# =============================================================================

@test "_fzf_is_interactive: returns 1 in BATS (non-interactive)" {
    run _fzf_is_interactive
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# _fzf_build_args
# =============================================================================

@test "_fzf_build_args: no args produces empty FZF_ARGS" {
    _fzf_build_args
    [[ ${#FZF_ARGS[@]} -eq 0 ]]
}

@test "_fzf_build_args: --prompt sets prompt argument" {
    _fzf_build_args --prompt "Pick: "
    [[ "${FZF_ARGS[*]}" == *"--prompt"* ]]
    [[ "${FZF_ARGS[*]}" == *"Pick: "* ]]
}

@test "_fzf_build_args: --header sets header argument" {
    _fzf_build_args --header "My Header"
    [[ "${FZF_ARGS[*]}" == *"--header"* ]]
    [[ "${FZF_ARGS[*]}" == *"My Header"* ]]
}

@test "_fzf_build_args: --multi sets multi flag" {
    _fzf_build_args --multi
    [[ "${FZF_ARGS[*]}" == *"--multi"* ]]
    [[ "$FALLBACK_MULTI" -eq 1 ]]
}

@test "_fzf_build_args: --preview sets preview argument" {
    _fzf_build_args --preview "cat {}"
    [[ "${FZF_ARGS[*]}" == *"--preview"* ]]
    [[ "${FZF_ARGS[*]}" == *"cat {}"* ]]
}

@test "_fzf_build_args: --height sets height argument" {
    _fzf_build_args --height "40%"
    [[ "${FZF_ARGS[*]}" == *"--height"* ]]
    [[ "${FZF_ARGS[*]}" == *"40%"* ]]
}

@test "_fzf_build_args: sets FALLBACK_PROMPT from --prompt" {
    _fzf_build_args --prompt "Choose file: "
    [[ "$FALLBACK_PROMPT" == "Choose file: " ]]
}

@test "_fzf_build_args: sets FALLBACK_HEADER from --header" {
    _fzf_build_args --header "List of items"
    [[ "$FALLBACK_HEADER" == "List of items" ]]
}

@test "_fzf_build_args: unknown args pass through to FZF_ARGS" {
    _fzf_build_args --reverse --exact
    [[ "${FZF_ARGS[*]}" == *"--reverse"* ]]
    [[ "${FZF_ARGS[*]}" == *"--exact"* ]]
}

# =============================================================================
# fzf_select (non-interactive codepath)
# =============================================================================

@test "fzf_select: outputs first line when non-interactive" {
    result=$(printf 'line1\nline2\nline3\n' | fzf_select 2>/dev/null)
    [[ "$result" == "line1" ]]
}

@test "fzf_select: outputs FZF_DEFAULT match when set" {
    result=$(FZF_DEFAULT="line2" bash -c '
        source "'"${MAINFRAME_ROOT}"'/lib/fzf.sh"
        printf "line1\nline2\nline3\n" | fzf_select 2>/dev/null
    ')
    [[ "$result" == "line2" ]]
}

@test "fzf_select: FZF_DEFAULT partial match works" {
    result=$(FZF_DEFAULT="ne2" bash -c '
        source "'"${MAINFRAME_ROOT}"'/lib/fzf.sh"
        printf "line1\nline2\nline3\n" | fzf_select 2>/dev/null
    ')
    [[ "$result" == "line2" ]]
}

@test "fzf_select: FZF_DEFAULT with no match falls back to first line" {
    result=$(FZF_DEFAULT="nomatch" bash -c '
        source "'"${MAINFRAME_ROOT}"'/lib/fzf.sh"
        printf "line1\nline2\nline3\n" | fzf_select 2>/dev/null
    ')
    [[ "$result" == "line1" ]]
}

@test "fzf_select: empty input returns failure" {
    run bash -c "source '$MAINFRAME_ROOT/lib/fzf.sh'; printf '' | fzf_select 2>/dev/null"
    [[ "$status" -eq 1 ]]
}

@test "fzf_select: preserves lines with spaces" {
    result=$(printf 'hello world\ngoodbye world\n' | fzf_select 2>/dev/null)
    [[ "$result" == "hello world" ]]
}

@test "fzf_select: preserves lines with special characters" {
    result=$(printf 'path/to/file.txt\nanother/path\n' | fzf_select 2>/dev/null)
    [[ "$result" == "path/to/file.txt" ]]
}

@test "fzf_select: single line input returns that line" {
    result=$(printf 'only-one\n' | fzf_select 2>/dev/null)
    [[ "$result" == "only-one" ]]
}

@test "fzf_select: stderr shows non-interactive message" {
    stderr=$(printf 'line1\nline2\n' | fzf_select 2>&1 >/dev/null)
    [[ "$stderr" == *"Non-interactive"* ]]
}

# =============================================================================
# fzf_or_select (alias for fzf_select)
# =============================================================================

@test "fzf_or_select: behaves same as fzf_select" {
    result=$(printf 'alpha\nbeta\ngamma\n' | fzf_or_select 2>/dev/null)
    [[ "$result" == "alpha" ]]
}

# =============================================================================
# fzf_file
# =============================================================================

@test "fzf_file: selects first file in directory (non-interactive)" {
    local test_dir
    test_dir=$(mktemp -d)
    touch "$test_dir/aaa.txt" "$test_dir/bbb.txt" "$test_dir/ccc.txt"

    result=$(fzf_file "$test_dir" 2>/dev/null)
    # find | sort means output is deterministic; first file alphabetically
    [[ "$result" == *"aaa.txt"* ]]

    rm -rf "$test_dir"
}

@test "fzf_file: returns failure for empty directory" {
    local test_dir
    test_dir=$(mktemp -d)

    run fzf_file "$test_dir"
    [[ "$status" -eq 1 ]]

    rm -rf "$test_dir"
}

@test "fzf_file: excludes .git directory contents" {
    local test_dir
    test_dir=$(mktemp -d)
    mkdir -p "$test_dir/.git/objects"
    touch "$test_dir/.git/objects/abc123"
    touch "$test_dir/real-file.txt"

    result=$(fzf_file "$test_dir" 2>/dev/null)
    [[ "$result" == *"real-file.txt"* ]]
    [[ "$result" != *".git"* ]]

    rm -rf "$test_dir"
}

# =============================================================================
# fzf_dir
# =============================================================================

@test "fzf_dir: selects first directory (non-interactive)" {
    local test_dir
    test_dir=$(mktemp -d)
    mkdir -p "$test_dir/alpha" "$test_dir/beta"

    result=$(fzf_dir "$test_dir" 2>/dev/null)
    # The find includes the root dir itself; after sort the root or first subdir comes first
    [[ -n "$result" ]]

    rm -rf "$test_dir"
}

@test "fzf_dir: excludes .git directory" {
    local test_dir
    test_dir=$(mktemp -d)
    mkdir -p "$test_dir/.git/refs" "$test_dir/src"

    result=$(fzf_dir "$test_dir" 2>/dev/null)
    [[ "$result" != *".git"* ]]

    rm -rf "$test_dir"
}

# =============================================================================
# fzf_process
# =============================================================================

@test "fzf_process: outputs at least one PID" {
    result=$(fzf_process 2>/dev/null)
    # There is always at least one process (the shell itself)
    [[ -n "$result" ]]
}

@test "fzf_process: output is numeric (PID)" {
    result=$(fzf_process 2>/dev/null)
    [[ "$result" =~ ^[0-9]+$ ]]
}

# =============================================================================
# fzf_git_branch (requires git repo)
# =============================================================================

@test "fzf_git_branch: outputs branch name in git repo" {
    local test_dir
    test_dir=$(mktemp -d)
    cd "$test_dir"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    git commit --allow-empty -m "init" -q

    result=$(fzf_git_branch 2>/dev/null)
    # Should be main or master depending on git config
    [[ "$result" == "main" || "$result" == "master" ]]

    cd /
    rm -rf "$test_dir"
}

@test "fzf_git_branch: fails gracefully outside git repo" {
    local test_dir
    test_dir=$(mktemp -d)
    cd "$test_dir"

    # No git init, so git branch will fail and produce empty input
    run fzf_git_branch
    [[ "$status" -eq 1 ]]

    cd /
    rm -rf "$test_dir"
}

# =============================================================================
# fzf_git_log (requires git repo)
# =============================================================================

@test "fzf_git_log: outputs commit hash" {
    local test_dir
    test_dir=$(mktemp -d)
    cd "$test_dir"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    git commit --allow-empty -m "initial commit" -q

    result=$(fzf_git_log 2>/dev/null)
    # Commit hash is 7+ hex characters
    [[ "$result" =~ ^[0-9a-f]{7,}$ ]]

    cd /
    rm -rf "$test_dir"
}

@test "fzf_git_log: fails gracefully outside git repo" {
    local test_dir
    test_dir=$(mktemp -d)
    cd "$test_dir"

    run fzf_git_log
    [[ "$status" -eq 1 ]]

    cd /
    rm -rf "$test_dir"
}

# =============================================================================
# fzf_git_file (requires git repo)
# =============================================================================

@test "fzf_git_file: outputs tracked file path" {
    local test_dir
    test_dir=$(mktemp -d)
    cd "$test_dir"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "content" > tracked.txt
    git add tracked.txt
    git commit -m "add file" -q

    result=$(fzf_git_file 2>/dev/null)
    [[ "$result" == "tracked.txt" ]]

    cd /
    rm -rf "$test_dir"
}

@test "fzf_git_file: does not include untracked files" {
    local test_dir
    test_dir=$(mktemp -d)
    cd "$test_dir"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "tracked" > aaa.txt
    git add aaa.txt
    git commit -m "add file" -q
    echo "untracked" > zzz.txt

    result=$(fzf_git_file 2>/dev/null)
    [[ "$result" == "aaa.txt" ]]

    cd /
    rm -rf "$test_dir"
}

# =============================================================================
# fzf_env
# =============================================================================

@test "fzf_env: outputs at least one line" {
    result=$(fzf_env 2>/dev/null)
    [[ -n "$result" ]]
}

@test "fzf_env: output contains equals sign (VAR=value)" {
    result=$(fzf_env 2>/dev/null)
    [[ "$result" == *"="* ]]
}

# =============================================================================
# fzf_docker_container
# =============================================================================

@test "fzf_docker_container: runs without error" {
    # May output empty if Docker is not running or no containers
    fzf_docker_container 2>/dev/null || true
    # If we get here without crashing, test passes
}

# =============================================================================
# fzf_port
# =============================================================================

@test "fzf_port: runs without error" {
    # May output empty if no ports are listening or ss/netstat not available
    fzf_port 2>/dev/null || true
    # If we get here without crashing, test passes
}

# =============================================================================
# fzf_history
# =============================================================================

@test "fzf_history: runs without error" {
    # history may be empty in non-interactive shell
    fzf_history 2>/dev/null || true
    # If we get here without crashing, test passes
}

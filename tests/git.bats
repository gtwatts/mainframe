#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Git Module Tests
# =============================================================================
# Tests for lib/git.sh
# Covers: repo state, branches, commits, status checks, diffs
# =============================================================================

load 'test_helper'

setup() {
    source_lib "git"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "git")

    # Create a temporary git repository for testing
    GIT_DIR="$TEST_DIR/repo"
    mkdir -p "$GIT_DIR"
    cd "$GIT_DIR"
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test User"
    printf 'initial\n' > file.txt
    git add file.txt
    git commit --quiet -m "Initial commit"
}

teardown() {
    cd /
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# git_is_repo TESTS
# =============================================================================

@test "git_is_repo returns 0 in git repo" {
    cd "$GIT_DIR"
    run git_is_repo
    [ "$status" -eq 0 ]
}

@test "git_is_repo returns non-zero outside git repo" {
    local nongit_dir
    nongit_dir=$(mktemp -d)
    cd "$nongit_dir"
    export GIT_CEILING_DIRECTORIES="${nongit_dir%/*}"
    run git_is_repo
    unset GIT_CEILING_DIRECTORIES
    rm -rf "$nongit_dir"
    [ "$status" -ne 0 ]
}

# =============================================================================
# git_root TESTS
# =============================================================================

@test "git_root returns repo root" {
    cd "$GIT_DIR"
    local result
    result=$(git_root)
    [ "$result" = "$(cd "$GIT_DIR" && pwd -P)" ]
}

@test "git_root works from subdirectory" {
    mkdir -p "$GIT_DIR/sub/dir"
    cd "$GIT_DIR/sub/dir"
    local result
    result=$(git_root)
    [ "$result" = "$(cd "$GIT_DIR" && pwd -P)" ]
}

# =============================================================================
# git_branch TESTS
# =============================================================================

@test "git_branch returns current branch" {
    cd "$GIT_DIR"
    local result
    result=$(git_branch)
    # Initial branch could be main or master depending on git config
    [[ "$result" == "main" || "$result" == "master" ]]
}

@test "git_branch shows new branch after checkout" {
    cd "$GIT_DIR"
    git checkout --quiet -b feature-branch
    local result
    result=$(git_branch)
    [ "$result" = "feature-branch" ]
}

# =============================================================================
# git_branches TESTS
# =============================================================================

@test "git_branches lists local branches" {
    cd "$GIT_DIR"
    git checkout --quiet -b branch-a
    git checkout --quiet -b branch-b
    local result
    result=$(git_branches)
    [[ "$result" == *"branch-a"* ]]
    [[ "$result" == *"branch-b"* ]]
}

# =============================================================================
# git_is_clean / git_is_dirty TESTS
# =============================================================================

@test "git_is_clean returns 0 for clean repo" {
    cd "$GIT_DIR"
    run git_is_clean
    [ "$status" -eq 0 ]
}

@test "git_is_dirty returns 0 for modified file" {
    cd "$GIT_DIR"
    printf 'changed\n' >> file.txt
    run git_is_dirty
    [ "$status" -eq 0 ]
}

@test "git_is_dirty returns 0 for untracked file" {
    cd "$GIT_DIR"
    printf 'new\n' > untracked.txt
    run git_is_dirty
    [ "$status" -eq 0 ]
}

@test "git_is_clean returns 1 for dirty repo" {
    cd "$GIT_DIR"
    printf 'modified\n' >> file.txt
    run git_is_clean
    [ "$status" -eq 1 ]
}

# =============================================================================
# git_has_staged TESTS
# =============================================================================

@test "git_has_staged returns 1 with no staged changes" {
    cd "$GIT_DIR"
    run git_has_staged
    [ "$status" -eq 1 ]
}

@test "git_has_staged returns 0 with staged changes" {
    cd "$GIT_DIR"
    printf 'staged\n' >> file.txt
    git add file.txt
    run git_has_staged
    [ "$status" -eq 0 ]
}

# =============================================================================
# git_has_unstaged TESTS
# =============================================================================

@test "git_has_unstaged returns 1 with no changes" {
    cd "$GIT_DIR"
    run git_has_unstaged
    [ "$status" -eq 1 ]
}

@test "git_has_unstaged returns 0 with modified file" {
    cd "$GIT_DIR"
    printf 'modified\n' >> file.txt
    run git_has_unstaged
    [ "$status" -eq 0 ]
}

# =============================================================================
# git_has_untracked TESTS
# =============================================================================

@test "git_has_untracked returns 1 with no untracked files" {
    cd "$GIT_DIR"
    run git_has_untracked
    [ "$status" -eq 1 ]
}

@test "git_has_untracked returns 0 with untracked file" {
    cd "$GIT_DIR"
    printf 'new\n' > new_file.txt
    run git_has_untracked
    [ "$status" -eq 0 ]
}

# =============================================================================
# git_status_short TESTS
# =============================================================================

@test "git_status_short returns empty for clean repo" {
    cd "$GIT_DIR"
    local result
    result=$(git_status_short)
    [ -z "$result" ]
}

@test "git_status_short shows modified files" {
    cd "$GIT_DIR"
    printf 'changed\n' >> file.txt
    local result
    result=$(git_status_short)
    [[ "$result" == *"file.txt"* ]]
}

# =============================================================================
# git_files_changed TESTS
# =============================================================================

@test "git_files_changed lists modified files" {
    cd "$GIT_DIR"
    printf 'changed\n' >> file.txt
    printf 'new\n' > other.txt
    local result
    result=$(git_files_changed)
    [[ "$result" == *"file.txt"* ]]
    [[ "$result" == *"other.txt"* ]]
}

# =============================================================================
# git_default_branch TESTS
# =============================================================================

@test "git_default_branch returns main or master" {
    cd "$GIT_DIR"
    local result
    result=$(git_default_branch)
    [[ "$result" == "main" || "$result" == "master" ]]
}

# =============================================================================
# INTEGRATION: multiple operations
# =============================================================================

@test "stage add commit cycle works" {
    cd "$GIT_DIR"
    printf 'new content\n' > newfile.txt
    git add newfile.txt

    run git_has_staged
    [ "$status" -eq 0 ]

    git commit --quiet -m "Add newfile"

    run git_is_clean
    [ "$status" -eq 0 ]
}

@test "branch create and switch" {
    cd "$GIT_DIR"
    git checkout --quiet -b test-branch
    local branch
    branch=$(git_branch)
    [ "$branch" = "test-branch" ]

    # Original branch still listed
    local branches
    branches=$(git_branches)
    [[ "$branches" == *"test-branch"* ]]
}

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/git.bats - Git Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/git.sh
#              Git helper functions for workflow convenience
# Test Count: 70+ test cases
# Categories: repository state, status checks, commit info, tags, remote,
#             utilities, comparison, AI workflow, stash, worktree, submodules,
#             upstream/tracking, config, enhanced functions
# Note: Many tests require actual git repository context
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"
    TEST_GIT_DIR="$TEST_TMPDIR/git_repo"

    # Create a test git repository
    mkdir -p "$TEST_GIT_DIR"
    cd "$TEST_GIT_DIR"
    git init --quiet
    git config user.email "test@example.com"
    git config user.name "Test User"

    # Create initial commit
    echo "Initial content" > file.txt
    git add file.txt
    git commit --quiet -m "Initial commit"

    # Source the library
    source "$MAINFRAME_ROOT/lib/git.sh"
}

# Teardown: Clean up test artifacts
teardown() {
    cd /
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# CATEGORY 1: REPOSITORY STATE
# =============================================================================

@test "git_is_repo: returns true in git repository" {
    cd "$TEST_GIT_DIR"
    git_is_repo
    [[ $? -eq 0 ]]
}

@test "git_is_repo: returns false outside git repository" {
    cd "$TEST_TMPDIR"
    mkdir not_a_repo
    cd not_a_repo
    run git_is_repo
    [[ "$status" -eq 1 ]]
}

@test "git_root: returns repository root directory" {
    cd "$TEST_GIT_DIR"
    mkdir -p subdir/nested
    cd subdir/nested
    result=$(git_root)
    [[ "$result" == "$TEST_GIT_DIR" ]]
}

@test "git_branch: returns current branch name" {
    cd "$TEST_GIT_DIR"
    result=$(git_branch)
    # Default branch is usually main or master
    [[ "$result" =~ ^(main|master)$ ]]
}

@test "git_branch: returns branch name after checkout" {
    cd "$TEST_GIT_DIR"
    git checkout -b feature-branch --quiet
    result=$(git_branch)
    [[ "$result" == "feature-branch" ]]
}

@test "git_branches: lists all local branches" {
    cd "$TEST_GIT_DIR"
    git checkout -b branch-a --quiet
    git checkout -b branch-b --quiet
    result=$(git_branches)
    [[ "$result" =~ "branch-a" ]]
    [[ "$result" =~ "branch-b" ]]
}

@test "git_default_branch: returns main or master" {
    cd "$TEST_GIT_DIR"
    result=$(git_default_branch)
    [[ "$result" =~ ^(main|master)$ ]]
}

# =============================================================================
# CATEGORY 2: STATUS CHECKS
# =============================================================================

@test "git_is_clean: returns true when no changes" {
    cd "$TEST_GIT_DIR"
    git_is_clean
    [[ $? -eq 0 ]]
}

@test "git_is_dirty: returns true when uncommitted changes" {
    cd "$TEST_GIT_DIR"
    echo "modified" >> file.txt
    git_is_dirty
    [[ $? -eq 0 ]]
}

@test "git_has_staged: returns true when staged changes" {
    cd "$TEST_GIT_DIR"
    echo "new content" > new_file.txt
    git add new_file.txt
    git_has_staged
    [[ $? -eq 0 ]]
}

@test "git_has_staged: returns false when no staged changes" {
    cd "$TEST_GIT_DIR"
    run git_has_staged
    [[ "$status" -eq 1 ]]
}

@test "git_has_unstaged: returns true when unstaged changes" {
    cd "$TEST_GIT_DIR"
    echo "modified" >> file.txt
    git_has_unstaged
    [[ $? -eq 0 ]]
}

@test "git_has_unstaged: returns false when clean" {
    cd "$TEST_GIT_DIR"
    run git_has_unstaged
    [[ "$status" -eq 1 ]]
}

@test "git_has_untracked: returns true when untracked files" {
    cd "$TEST_GIT_DIR"
    echo "untracked" > untracked.txt
    git_has_untracked
    [[ $? -eq 0 ]]
}

@test "git_has_untracked: returns false when no untracked files" {
    cd "$TEST_GIT_DIR"
    run git_has_untracked
    [[ "$status" -eq 1 ]]
}

@test "git_status_short: returns porcelain output" {
    cd "$TEST_GIT_DIR"
    echo "modified" >> file.txt
    result=$(git_status_short)
    [[ "$result" =~ "M" ]] || [[ "$result" =~ " M" ]]
}

@test "git_files_changed: lists changed files" {
    cd "$TEST_GIT_DIR"
    echo "modified" >> file.txt
    echo "new" > new.txt
    result=$(git_files_changed)
    [[ "$result" =~ "file.txt" ]]
    [[ "$result" =~ "new.txt" ]]
}

# =============================================================================
# CATEGORY 3: COMMIT INFO
# =============================================================================

@test "git_commit_hash: returns short hash" {
    cd "$TEST_GIT_DIR"
    result=$(git_commit_hash)
    [[ "$result" =~ ^[0-9a-f]{7,}$ ]]
}

@test "git_commit_hash_full: returns full hash" {
    cd "$TEST_GIT_DIR"
    result=$(git_commit_hash_full)
    [[ "$result" =~ ^[0-9a-f]{40}$ ]]
}

@test "git_commit_message: returns latest commit message" {
    cd "$TEST_GIT_DIR"
    result=$(git_commit_message)
    [[ "$result" == "Initial commit" ]]
}

@test "git_commit_author: returns commit author name" {
    cd "$TEST_GIT_DIR"
    result=$(git_commit_author)
    [[ "$result" == "Test User" ]]
}

@test "git_commit_date: returns commit date" {
    cd "$TEST_GIT_DIR"
    result=$(git_commit_date)
    # Should contain year
    [[ "$result" =~ [0-9]{4} ]]
}

@test "git_commit_count: returns number of commits" {
    cd "$TEST_GIT_DIR"
    result=$(git_commit_count)
    [[ "$result" -ge 1 ]]
}

@test "git_commit_count: increments after new commit" {
    cd "$TEST_GIT_DIR"
    before=$(git_commit_count)
    echo "second" > second.txt
    git add second.txt
    git commit --quiet -m "Second commit"
    after=$(git_commit_count)
    [[ "$after" -eq $((before + 1)) ]]
}

# =============================================================================
# CATEGORY 4: TAGS
# =============================================================================

@test "git_tags: lists all tags" {
    cd "$TEST_GIT_DIR"
    git tag v1.0.0
    git tag v1.1.0
    result=$(git_tags)
    [[ "$result" =~ "v1.0.0" ]]
    [[ "$result" =~ "v1.1.0" ]]
}

@test "git_tag_latest: returns most recent tag" {
    cd "$TEST_GIT_DIR"
    git tag v1.0.0
    result=$(git_tag_latest)
    [[ "$result" == "v1.0.0" ]]
}

@test "git_tag_exists: returns true for existing tag" {
    cd "$TEST_GIT_DIR"
    git tag test-tag
    git_tag_exists "test-tag"
    [[ $? -eq 0 ]]
}

@test "git_tag_exists: returns false for non-existing tag" {
    cd "$TEST_GIT_DIR"
    run git_tag_exists "nonexistent-tag"
    [[ "$status" -eq 1 ]]
}

@test "git_describe: returns tag-based description" {
    cd "$TEST_GIT_DIR"
    git tag v1.0.0
    result=$(git_describe)
    [[ "$result" =~ "v1.0.0" ]] || [[ "$result" =~ ^[0-9a-f]+ ]]
}

# =============================================================================
# CATEGORY 5: REMOTE (Limited - No remote in test)
# =============================================================================

@test "git_has_remote: returns false when no remote" {
    cd "$TEST_GIT_DIR"
    run git_has_remote
    [[ "$status" -eq 1 ]]
}

@test "git_remote_name: returns empty when no remote" {
    cd "$TEST_GIT_DIR"
    result=$(git_remote_name)
    [[ -z "$result" ]]
}

# Test with mock remote
@test "git_has_remote: returns true when remote configured" {
    cd "$TEST_GIT_DIR"
    git remote add origin "https://github.com/test/repo.git"
    git_has_remote
    [[ $? -eq 0 ]]
}

@test "git_remote_url: returns remote URL" {
    cd "$TEST_GIT_DIR"
    git remote add origin "https://github.com/test/repo.git"
    result=$(git_remote_url)
    [[ "$result" == "https://github.com/test/repo.git" ]]
}

@test "git_remote_name: returns origin when configured" {
    cd "$TEST_GIT_DIR"
    git remote add origin "https://github.com/test/repo.git"
    result=$(git_remote_name)
    [[ "$result" == "origin" ]]
}

# =============================================================================
# CATEGORY 6: UTILITIES
# =============================================================================

@test "git_user_name: returns configured user name" {
    cd "$TEST_GIT_DIR"
    result=$(git_user_name)
    [[ "$result" == "Test User" ]]
}

@test "git_user_email: returns configured user email" {
    cd "$TEST_GIT_DIR"
    result=$(git_user_email)
    [[ "$result" == "test@example.com" ]]
}

@test "git_ignore_check: returns true for gitignored file" {
    cd "$TEST_GIT_DIR"
    echo "*.log" > .gitignore
    git add .gitignore
    git commit --quiet -m "Add gitignore"
    git_ignore_check "test.log"
    [[ $? -eq 0 ]]
}

@test "git_ignore_check: returns false for non-ignored file" {
    cd "$TEST_GIT_DIR"
    run git_ignore_check "file.txt"
    [[ "$status" -eq 1 ]]
}

@test "git_file_history: shows commit history for file" {
    cd "$TEST_GIT_DIR"
    echo "change 1" >> file.txt
    git add file.txt
    git commit --quiet -m "Change 1"
    result=$(git_file_history "file.txt")
    [[ "$result" =~ "Initial commit" ]]
    [[ "$result" =~ "Change 1" ]]
}

@test "git_blame_line: shows blame for specific line" {
    cd "$TEST_GIT_DIR"
    result=$(git_blame_line "file.txt" 1)
    [[ "$result" =~ "Initial" ]]
}

# =============================================================================
# CATEGORY 7: COMPARISON
# =============================================================================

@test "git_diff_files: lists files changed between refs" {
    cd "$TEST_GIT_DIR"
    git checkout -b feature --quiet
    echo "feature change" > feature.txt
    git add feature.txt
    git commit --quiet -m "Feature commit"

    git checkout master --quiet 2>/dev/null || git checkout main --quiet
    result=$(git_diff_files "feature")
    [[ "$result" =~ "feature.txt" ]]
}

@test "git_diff_stat: shows diff statistics" {
    cd "$TEST_GIT_DIR"
    git checkout -b stats-branch --quiet
    echo "new content" > stats.txt
    git add stats.txt
    git commit --quiet -m "Stats commit"

    git checkout master --quiet 2>/dev/null || git checkout main --quiet
    result=$(git_diff_stat "stats-branch")
    [[ "$result" =~ "stats.txt" ]]
    [[ "$result" =~ "insertion" ]]
}

@test "git_merge_base: finds common ancestor" {
    cd "$TEST_GIT_DIR"
    default_branch=$(git_branch)
    git checkout -b ancestor-branch --quiet
    echo "branch change" > branch.txt
    git add branch.txt
    git commit --quiet -m "Branch commit"

    result=$(git_merge_base "$default_branch" "ancestor-branch")
    [[ "$result" =~ ^[0-9a-f]{40}$ ]]
}

# =============================================================================
# CATEGORY 8: AI WORKFLOW CONVENIENCE
# =============================================================================

@test "git_summary: returns one-line summary" {
    cd "$TEST_GIT_DIR"
    result=$(git_summary)
    # Should contain branch, hash, and status
    [[ "$result" =~ "@" ]]
    [[ "$result" =~ "[" ]]
    [[ "$result" =~ "]" ]]
}

@test "git_summary: shows clean status" {
    cd "$TEST_GIT_DIR"
    result=$(git_summary)
    [[ "$result" =~ "clean" ]]
}

@test "git_summary: shows dirty status" {
    cd "$TEST_GIT_DIR"
    echo "dirty" >> file.txt
    result=$(git_summary)
    [[ "$result" =~ "modified" ]]
}

@test "git_summary: returns error outside repo" {
    cd "$TEST_TMPDIR"
    mkdir not_repo
    cd not_repo
    run git_summary
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Not a git" ]]
}

@test "git_log_oneline: returns recent commits" {
    cd "$TEST_GIT_DIR"
    echo "second" > second.txt
    git add second.txt
    git commit --quiet -m "Second commit"

    result=$(git_log_oneline 2)
    [[ "$result" =~ "Second commit" ]]
    [[ "$result" =~ "Initial commit" ]]
}

@test "git_log_oneline: respects count parameter" {
    cd "$TEST_GIT_DIR"
    echo "second" > second.txt
    git add second.txt
    git commit --quiet -m "Second commit"
    echo "third" > third.txt
    git add third.txt
    git commit --quiet -m "Third commit"

    result=$(git_log_oneline 1)
    lines=$(echo "$result" | wc -l)
    [[ "$lines" -eq 1 ]]
}

# =============================================================================
# CATEGORY 9: STASH OPERATIONS
# =============================================================================

@test "git_has_stash: returns false when no stash" {
    cd "$TEST_GIT_DIR"
    run git_has_stash
    [[ "$status" -eq 1 ]]
}

@test "git_has_stash: returns true when stash exists" {
    cd "$TEST_GIT_DIR"
    echo "stash me" >> file.txt
    git stash push --quiet
    git_has_stash
    [[ $? -eq 0 ]]
}

@test "git_stash_count: returns 0 when no stash" {
    cd "$TEST_GIT_DIR"
    result=$(git_stash_count)
    [[ "$result" -eq 0 ]]
}

@test "git_stash_count: returns correct count" {
    cd "$TEST_GIT_DIR"
    echo "stash 1" >> file.txt
    git stash push --quiet
    echo "stash 2" >> file.txt
    git stash push --quiet
    result=$(git_stash_count)
    [[ "$result" -eq 2 ]]
}

# =============================================================================
# CATEGORY 10: WORKTREE INFO
# =============================================================================

@test "git_is_worktree: returns false for main repo" {
    cd "$TEST_GIT_DIR"
    run git_is_worktree
    [[ "$status" -eq 1 ]]
}

@test "git_worktrees: lists worktrees" {
    cd "$TEST_GIT_DIR"
    result=$(git_worktrees)
    [[ "$result" =~ "$TEST_GIT_DIR" ]]
}

# =============================================================================
# CATEGORY 11: SUBMODULE INFO
# =============================================================================

@test "git_has_submodules: returns false when no submodules" {
    cd "$TEST_GIT_DIR"
    run git_has_submodules
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 12: CONFIG HELPERS
# =============================================================================

@test "git_config_get: returns config value" {
    cd "$TEST_GIT_DIR"
    result=$(git_config_get "user.name")
    [[ "$result" == "Test User" ]]
}

@test "git_config_get: returns empty for missing key" {
    cd "$TEST_GIT_DIR"
    result=$(git_config_get "nonexistent.key")
    [[ -z "$result" ]]
}

@test "git_config_exists: returns true for existing key" {
    cd "$TEST_GIT_DIR"
    git_config_exists "user.name"
    [[ $? -eq 0 ]]
}

@test "git_config_exists: returns false for missing key" {
    cd "$TEST_GIT_DIR"
    run git_config_exists "nonexistent.key"
    [[ "$status" -eq 1 ]]
}

@test "git_version: returns version string" {
    result=$(git_version)
    [[ "$result" =~ ^[0-9]+\.[0-9]+ ]]
}

# =============================================================================
# CATEGORY 13: ENHANCED REMOTE & PROVIDER INFO
# =============================================================================

@test "git_repo_name: extracts repo name from HTTPS URL" {
    cd "$TEST_GIT_DIR"
    git remote add origin "https://github.com/owner/myrepo.git"
    result=$(git_repo_name)
    [[ "$result" == "myrepo" ]]
}

@test "git_repo_name: extracts repo name from SSH URL" {
    cd "$TEST_GIT_DIR"
    git remote add origin "git@github.com:owner/myrepo.git"
    result=$(git_repo_name)
    [[ "$result" == "myrepo" ]]
}

@test "git_provider: detects GitHub" {
    cd "$TEST_GIT_DIR"
    git remote add origin "https://github.com/owner/repo.git"
    result=$(git_provider)
    [[ "$result" == "github" ]]
}

@test "git_provider: detects GitLab" {
    cd "$TEST_GIT_DIR"
    git remote add origin "https://gitlab.com/owner/repo.git"
    result=$(git_provider)
    [[ "$result" == "gitlab" ]]
}

@test "git_provider: detects Bitbucket" {
    cd "$TEST_GIT_DIR"
    git remote add origin "https://bitbucket.org/owner/repo.git"
    result=$(git_provider)
    [[ "$result" == "bitbucket" ]]
}

@test "git_provider: returns unknown for unrecognized host" {
    cd "$TEST_GIT_DIR"
    git remote add origin "https://unknown.example.com/owner/repo.git"
    run git_provider
    [[ "$output" == "unknown" ]]
}

@test "git_repo_owner: extracts owner from HTTPS URL" {
    cd "$TEST_GIT_DIR"
    git remote add origin "https://github.com/myowner/repo.git"
    result=$(git_repo_owner)
    [[ "$result" == "myowner" ]]
}

@test "git_repo_owner: extracts owner from SSH URL" {
    cd "$TEST_GIT_DIR"
    git remote add origin "git@github.com:myowner/repo.git"
    result=$(git_repo_owner)
    [[ "$result" == "myowner" ]]
}

@test "git_web_url: generates GitHub web URL" {
    cd "$TEST_GIT_DIR"
    git remote add origin "git@github.com:owner/repo.git"
    result=$(git_web_url)
    [[ "$result" == "https://github.com/owner/repo" ]]
}

@test "git_remotes_json: returns JSON array of remotes" {
    cd "$TEST_GIT_DIR"
    git remote add origin "https://github.com/owner/repo.git"
    result=$(git_remotes_json)
    [[ "$result" =~ '"name":"origin"' ]]
    [[ "$result" =~ '"fetch_url"' ]]
}

@test "git_remotes_json: returns empty array when no remotes" {
    cd "$TEST_GIT_DIR"
    result=$(git_remotes_json)
    [[ "$result" == "[]" ]]
}

# =============================================================================
# CATEGORY 14: ENHANCED CHANGED FILES
# =============================================================================

@test "git_changed_files: returns all changed files by default" {
    cd "$TEST_GIT_DIR"
    echo "modified" >> file.txt
    echo "new" > new.txt
    git add new.txt
    echo "untracked" > untracked.txt

    result=$(git_changed_files)
    [[ "$result" =~ "file.txt" ]]
    [[ "$result" =~ "new.txt" ]]
    [[ "$result" =~ "untracked.txt" ]]
}

@test "git_changed_files: filters staged only" {
    cd "$TEST_GIT_DIR"
    echo "new" > new.txt
    git add new.txt
    echo "modified" >> file.txt

    result=$(git_changed_files staged)
    [[ "$result" =~ "new.txt" ]]
    [[ ! "$result" =~ "file.txt" ]]
}

@test "git_changed_files: filters unstaged only" {
    cd "$TEST_GIT_DIR"
    echo "new" > new.txt
    git add new.txt
    echo "modified" >> file.txt

    result=$(git_changed_files unstaged)
    [[ "$result" =~ "file.txt" ]]
    [[ ! "$result" =~ "new.txt" ]]
}

@test "git_changed_files: filters untracked only" {
    cd "$TEST_GIT_DIR"
    echo "modified" >> file.txt
    echo "untracked" > untracked.txt

    result=$(git_changed_files untracked)
    [[ "$result" =~ "untracked.txt" ]]
    [[ ! "$result" =~ "file.txt" ]]
}

# =============================================================================
# CATEGORY 15: ENHANCED COMMIT INFO
# =============================================================================

@test "git_last_commit: returns JSON with commit info" {
    cd "$TEST_GIT_DIR"
    result=$(git_last_commit)
    [[ "$result" =~ '"hash":' ]]
    [[ "$result" =~ '"author":' ]]
    [[ "$result" =~ '"message":' ]]
    [[ "$result" =~ '"date":' ]]
}

@test "git_summary_json: returns comprehensive JSON summary" {
    cd "$TEST_GIT_DIR"
    git remote add origin "https://github.com/owner/repo.git"
    result=$(git_summary_json)
    [[ "$result" =~ '"branch":' ]]
    [[ "$result" =~ '"commit_hash":' ]]
    [[ "$result" =~ '"is_dirty":' ]]
    [[ "$result" =~ '"provider":' ]]
}

@test "git_summary_json: includes correct dirty status" {
    cd "$TEST_GIT_DIR"
    result=$(git_summary_json)
    [[ "$result" =~ '"is_dirty":false' ]]

    echo "dirty" >> file.txt
    result=$(git_summary_json)
    [[ "$result" =~ '"is_dirty":true' ]]
}

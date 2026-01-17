#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/git.sh - Git Helper Functions
# =============================================================================
# Description: Thin wrappers around git commands for convenience
# Dependency: git (required - these functions are specifically for git workflows)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_GIT_LOADED:-}" ]] && return 0
readonly _MAINFRAME_GIT_LOADED=1

# =============================================================================
# REPOSITORY STATE
# =============================================================================

# Check if current directory is a git repository
# Usage: git_is_repo && echo "yes"
git_is_repo() {
    git rev-parse --is-inside-work-tree &>/dev/null
}

# Get repository root directory
# Usage: root=$(git_root)
git_root() {
    git rev-parse --show-toplevel 2>/dev/null
}

# Get current branch name
# Usage: branch=$(git_branch)
git_branch() {
    git symbolic-ref --short HEAD 2>/dev/null || \
        git rev-parse --short HEAD 2>/dev/null
}

# List all local branches (one per line)
# Usage: git_branches
git_branches() {
    git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null
}

# List remote branches (one per line)
# Usage: git_remote_branches
git_remote_branches() {
    git for-each-ref --format='%(refname:short)' refs/remotes/ 2>/dev/null
}

# Get default branch (main or master)
# Usage: default=$(git_default_branch)
git_default_branch() {
    # Try to get from remote HEAD
    local remote_head
    remote_head=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)
    if [[ -n "$remote_head" ]]; then
        printf '%s\n' "${remote_head##*/}"
        return 0
    fi

    # Fall back to checking common names
    if git show-ref --verify --quiet refs/heads/main 2>/dev/null; then
        printf 'main\n'
    elif git show-ref --verify --quiet refs/heads/master 2>/dev/null; then
        printf 'master\n'
    else
        # Return first branch as fallback
        git_branches | head -1
    fi
}

# =============================================================================
# STATUS CHECKS
# =============================================================================

# Check if working tree has uncommitted changes
# Usage: git_is_dirty && echo "dirty"
git_is_dirty() {
    ! git_is_clean
}

# Check if working tree is clean (no uncommitted changes)
# Usage: git_is_clean && echo "clean"
git_is_clean() {
    git diff --quiet HEAD 2>/dev/null && \
        [[ -z "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]
}

# Check if there are staged changes
# Usage: git_has_staged && echo "has staged"
git_has_staged() {
    ! git diff --cached --quiet 2>/dev/null
}

# Check if there are unstaged changes
# Usage: git_has_unstaged && echo "has unstaged"
git_has_unstaged() {
    ! git diff --quiet 2>/dev/null
}

# Check if there are untracked files
# Usage: git_has_untracked && echo "has untracked"
git_has_untracked() {
    [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]
}

# Get short status output (porcelain format)
# Usage: git_status_short
git_status_short() {
    git status --porcelain 2>/dev/null
}

# List changed files (modified, staged, untracked)
# Usage: git_files_changed
git_files_changed() {
    git status --porcelain 2>/dev/null | awk '{print $2}'
}

# =============================================================================
# COMMIT INFO
# =============================================================================

# Get current HEAD commit hash (short)
# Usage: hash=$(git_commit_hash)
git_commit_hash() {
    git rev-parse --short HEAD 2>/dev/null
}

# Get current HEAD commit hash (full)
# Usage: hash=$(git_commit_hash_full)
git_commit_hash_full() {
    git rev-parse HEAD 2>/dev/null
}

# Get latest commit message
# Usage: msg=$(git_commit_message)
git_commit_message() {
    git log -1 --format='%s' 2>/dev/null
}

# Get latest commit author
# Usage: author=$(git_commit_author)
git_commit_author() {
    git log -1 --format='%an' 2>/dev/null
}

# Get latest commit date
# Usage: date=$(git_commit_date)
git_commit_date() {
    git log -1 --format='%ci' 2>/dev/null
}

# Get total commit count
# Usage: count=$(git_commit_count)
git_commit_count() {
    git rev-list --count HEAD 2>/dev/null
}

# Get commits ahead of remote tracking branch
# Usage: ahead=$(git_commits_ahead)
git_commits_ahead() {
    local tracking
    tracking=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null) || return 1
    git rev-list --count "$tracking..HEAD" 2>/dev/null
}

# Get commits behind remote tracking branch
# Usage: behind=$(git_commits_behind)
git_commits_behind() {
    local tracking
    tracking=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null) || return 1
    git rev-list --count "HEAD..$tracking" 2>/dev/null
}

# =============================================================================
# TAGS
# =============================================================================

# Get most recent tag
# Usage: tag=$(git_tag_latest)
git_tag_latest() {
    git describe --tags --abbrev=0 2>/dev/null
}

# List all tags (one per line)
# Usage: git_tags
git_tags() {
    git tag --list 2>/dev/null
}

# Check if a tag exists
# Usage: git_tag_exists "v1.0.0" && echo "exists"
git_tag_exists() {
    local tag="$1"
    git show-ref --tags --verify --quiet "refs/tags/$tag" 2>/dev/null
}

# Get git describe output
# Usage: desc=$(git_describe)
git_describe() {
    git describe --tags --always 2>/dev/null
}

# =============================================================================
# REMOTE
# =============================================================================

# Get origin remote URL
# Usage: url=$(git_remote_url)
git_remote_url() {
    local remote="${1:-origin}"
    git remote get-url "$remote" 2>/dev/null
}

# Get remote name (usually origin)
# Usage: name=$(git_remote_name)
git_remote_name() {
    git remote 2>/dev/null | head -1
}

# Check if remote is configured
# Usage: git_has_remote && echo "has remote"
git_has_remote() {
    [[ -n "$(git remote 2>/dev/null)" ]]
}

# Check if current branch is pushed to remote
# Usage: git_is_pushed && echo "pushed"
git_is_pushed() {
    local tracking
    tracking=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null) || return 1

    # Check if local and remote are at same commit
    local local_hash remote_hash
    local_hash=$(git rev-parse HEAD 2>/dev/null)
    remote_hash=$(git rev-parse "$tracking" 2>/dev/null)

    [[ "$local_hash" == "$remote_hash" ]]
}

# =============================================================================
# UTILITIES
# =============================================================================

# Get configured user.name
# Usage: name=$(git_user_name)
git_user_name() {
    git config user.name 2>/dev/null
}

# Get configured user.email
# Usage: email=$(git_user_email)
git_user_email() {
    git config user.email 2>/dev/null
}

# Check if a file is gitignored
# Usage: git_ignore_check "file.txt" && echo "ignored"
git_ignore_check() {
    local file="$1"
    git check-ignore -q "$file" 2>/dev/null
}

# Get commit history for a specific file
# Usage: git_file_history "path/to/file"
git_file_history() {
    local file="$1"
    git log --oneline --follow -- "$file" 2>/dev/null
}

# Get blame info for a specific line
# Usage: git_blame_line "file.txt" 42
git_blame_line() {
    local file="$1"
    local line="$2"
    git blame -L "$line,$line" "$file" 2>/dev/null
}

# =============================================================================
# COMPARISON
# =============================================================================

# List files changed between two refs
# Usage: git_diff_files "main" "feature"
git_diff_files() {
    local ref1="$1"
    local ref2="${2:-HEAD}"
    git diff --name-only "$ref1" "$ref2" 2>/dev/null
}

# Get diff statistics between two refs
# Usage: git_diff_stat "main" "feature"
git_diff_stat() {
    local ref1="$1"
    local ref2="${2:-HEAD}"
    git diff --stat "$ref1" "$ref2" 2>/dev/null
}

# Find common ancestor of two branches
# Usage: base=$(git_merge_base "main" "feature")
git_merge_base() {
    local branch1="$1"
    local branch2="${2:-HEAD}"
    git merge-base "$branch1" "$branch2" 2>/dev/null
}

# =============================================================================
# AI WORKFLOW CONVENIENCE
# =============================================================================

# One-line repository summary
# Usage: git_summary
git_summary() {
    if ! git_is_repo; then
        printf 'Not a git repository\n'
        return 1
    fi

    local branch hash status_info
    branch=$(git_branch)
    hash=$(git_commit_hash)

    # Build status info
    if git_is_clean; then
        status_info="clean"
    else
        local parts=()
        git_has_staged && parts+=("staged")
        git_has_unstaged && parts+=("modified")
        git_has_untracked && parts+=("untracked")
        status_info=$(IFS=,; printf '%s' "${parts[*]}")
    fi

    printf '%s @ %s [%s]\n' "$branch" "$hash" "$status_info"
}

# Get last N commits, one line each
# Usage: git_log_oneline 10
git_log_oneline() {
    local count="${1:-10}"
    git log --oneline -n "$count" 2>/dev/null
}

# List files changed since a ref
# Usage: git_changed_since "main"
git_changed_since() {
    local ref="$1"
    git diff --name-only "$ref"..HEAD 2>/dev/null
}

# =============================================================================
# STASH OPERATIONS
# =============================================================================

# Check if there are stashed changes
# Usage: git_has_stash && echo "has stash"
git_has_stash() {
    [[ -n "$(git stash list 2>/dev/null)" ]]
}

# Count stashed entries
# Usage: count=$(git_stash_count)
git_stash_count() {
    git stash list 2>/dev/null | wc -l
}

# =============================================================================
# WORKTREE INFO
# =============================================================================

# Check if in a worktree
# Usage: git_is_worktree && echo "worktree"
git_is_worktree() {
    local git_dir common_dir
    git_dir=$(git rev-parse --git-dir 2>/dev/null)
    common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
    [[ "$git_dir" != "$common_dir" ]]
}

# List all worktrees
# Usage: git_worktrees
git_worktrees() {
    git worktree list 2>/dev/null
}

# =============================================================================
# SUBMODULE INFO
# =============================================================================

# Check if repo has submodules
# Usage: git_has_submodules && echo "has submodules"
git_has_submodules() {
    [[ -f "$(git_root)/.gitmodules" ]]
}

# List submodules
# Usage: git_submodules
git_submodules() {
    git submodule status 2>/dev/null | awk '{print $2}'
}

# =============================================================================
# UPSTREAM / TRACKING
# =============================================================================

# Get tracking branch name
# Usage: tracking=$(git_tracking_branch)
git_tracking_branch() {
    git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null
}

# Check if branch has upstream
# Usage: git_has_upstream && echo "has upstream"
git_has_upstream() {
    git rev-parse --abbrev-ref '@{upstream}' &>/dev/null
}

# Get ahead/behind count as "ahead:behind"
# Usage: counts=$(git_ahead_behind)
git_ahead_behind() {
    local tracking
    tracking=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null) || return 1

    local ahead behind
    ahead=$(git rev-list --count "$tracking..HEAD" 2>/dev/null)
    behind=$(git rev-list --count "HEAD..$tracking" 2>/dev/null)

    printf '%d:%d\n' "$ahead" "$behind"
}

# =============================================================================
# CONFIG HELPERS
# =============================================================================

# Get a git config value
# Usage: val=$(git_config_get "core.editor")
git_config_get() {
    local key="$1"
    git config --get "$key" 2>/dev/null
}

# Check if a config key is set
# Usage: git_config_exists "user.email" && echo "set"
git_config_exists() {
    local key="$1"
    git config --get "$key" &>/dev/null
}

# Get git version
# Usage: ver=$(git_version)
git_version() {
    git --version 2>/dev/null | awk '{print $3}'
}

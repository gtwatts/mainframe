#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/github.sh - GitHub CLI Wrapper Library
# =============================================================================
# Description: Comprehensive wrapper around gh CLI for GitHub operations
#              with JSON output optimized for AI agent consumption.
#
# Features:
#   - Authentication and configuration management
#   - Repository operations (create, clone, fork, archive, delete)
#   - Issue and Pull Request management
#   - Gist operations
#   - Release management
#   - Search across repos, code, issues, users
#   - User and social operations
#   - Notifications handling
#   - AI agent context functions for optimal context window usage
#
# @module      github
# @version     1.0.0
# @requires    git.sh
# @provides    100+ functions
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_GITHUB_LOADED:-}" ]] && return 0
readonly _MAINFRAME_GITHUB_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

_GITHUB_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source git.sh if not already loaded
if [[ -z "${_MAINFRAME_GIT_LOADED:-}" ]]; then
    # shellcheck source=lib/git.sh
    source "$_GITHUB_LIB_DIR/git.sh" 2>/dev/null || true
fi

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Check if gh CLI is available
# Usage: _gh_available && echo "gh is installed"
_gh_available() {
    command -v gh &>/dev/null
}

# Ensure gh is authenticated
# Usage: _gh_require_auth || return 1
_gh_require_auth() {
    if ! _gh_available; then
        printf 'ERROR: gh CLI not installed\n' >&2
        return 1
    fi
    if ! gh auth status &>/dev/null 2>&1; then
        printf 'ERROR: gh CLI not authenticated. Run: gh auth login\n' >&2
        return 1
    fi
    return 0
}

# Escape string for JSON output
# Usage: _gh_json_escape "string with \"quotes\""
_gh_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

# =============================================================================
# AUTHENTICATION & CONFIGURATION
# =============================================================================

# Check if gh is authenticated
# @return 0 if authenticated, 1 otherwise
# Usage: gh_auth_status && echo "logged in"
gh_auth_status() {
    _gh_available || return 1
    gh auth status &>/dev/null 2>&1
}

# Get current auth token (masked for security)
# @return Masked token string
# Usage: token=$(gh_auth_token)
gh_auth_token() {
    _gh_require_auth || return 1
    local token
    token=$(gh auth token 2>/dev/null) || return 1
    # Mask token for security: show first 4 and last 4 chars
    if [[ ${#token} -gt 12 ]]; then
        printf '%s...%s' "${token:0:4}" "${token: -4}"
    else
        printf '****'
    fi
}

# Get current authenticated username
# @return GitHub username
# Usage: user=$(gh_whoami)
gh_whoami() {
    _gh_require_auth || return 1
    gh api user --jq '.login' 2>/dev/null
}

# Get gh config value
# @param $1 key - Config key (e.g., git_protocol, editor, browser)
# @return Config value
# Usage: protocol=$(gh_config_get git_protocol)
gh_config_get() {
    local key="$1"
    _gh_available || return 1
    gh config get "$key" 2>/dev/null
}

# Set gh config value
# @param $1 key - Config key
# @param $2 value - Config value
# @return 0 on success
# Usage: gh_config_set git_protocol ssh
gh_config_set() {
    local key="$1"
    local value="$2"
    _gh_available || return 1
    gh config set "$key" "$value" 2>/dev/null
}

# =============================================================================
# REPOSITORY OPERATIONS
# =============================================================================

# Get repository info as JSON
# @param $1 repo - Repository in owner/repo format
# @return JSON object with repo details
# Usage: gh_repo_view "owner/repo"
gh_repo_view() {
    local repo="$1"
    _gh_require_auth || return 1
    gh repo view "$repo" --json name,owner,description,url,sshUrl,defaultBranchRef,isPrivate,isFork,isArchived,stargazerCount,forkCount,watchers,createdAt,updatedAt,diskUsage,languages,licenseInfo 2>/dev/null
}

# List repositories for a user or org
# @param $1 owner - GitHub username or org
# @param $2 [limit] - Max results (default: 30)
# @return JSON array of repos
# Usage: gh_repo_list "octocat"
# Usage: gh_repo_list "octocat" 100
gh_repo_list() {
    local owner="$1"
    local limit="${2:-30}"
    _gh_require_auth || return 1
    gh repo list "$owner" --json name,owner,description,isPrivate,isFork,stargazerCount,updatedAt --limit "$limit" 2>/dev/null
}

# Create a new repository
# @param $1 name - Repository name
# @param --public|--private - Visibility (default: private)
# @param --description - Repo description
# @param --clone - Clone after creation
# @return JSON with new repo info
# Usage: gh_repo_create "my-repo" --public --description "My project"
gh_repo_create() {
    local name="$1"
    shift
    _gh_require_auth || return 1
    gh repo create "$name" "$@" --json name,url,sshUrl 2>/dev/null
}

# Clone a repository
# @param $1 repo - Repository in owner/repo format
# @param $2 [dir] - Target directory
# @return 0 on success
# Usage: gh_repo_clone "owner/repo"
# Usage: gh_repo_clone "owner/repo" "./my-dir"
gh_repo_clone() {
    local repo="$1"
    local dir="${2:-}"
    _gh_require_auth || return 1
    if [[ -n "$dir" ]]; then
        gh repo clone "$repo" "$dir" 2>/dev/null
    else
        gh repo clone "$repo" 2>/dev/null
    fi
}

# Fork a repository
# @param $1 repo - Repository to fork in owner/repo format
# @param --clone - Clone the fork after creation
# @return JSON with fork info
# Usage: gh_repo_fork "owner/repo"
# Usage: gh_repo_fork "owner/repo" --clone
gh_repo_fork() {
    local repo="$1"
    shift
    _gh_require_auth || return 1
    gh repo fork "$repo" "$@" --json name,url,owner 2>/dev/null
}

# Delete a repository (DANGEROUS)
# @param $1 repo - Repository in owner/repo format
# @param --yes - Skip confirmation
# @return 0 on success
# Usage: gh_repo_delete "owner/repo" --yes
gh_repo_delete() {
    local repo="$1"
    shift
    _gh_require_auth || return 1
    gh repo delete "$repo" "$@" 2>/dev/null
}

# Archive a repository
# @param $1 repo - Repository in owner/repo format
# @return 0 on success
# Usage: gh_repo_archive "owner/repo"
gh_repo_archive() {
    local repo="$1"
    _gh_require_auth || return 1
    gh repo archive "$repo" --yes 2>/dev/null
}

# Get repository topics
# @param $1 repo - Repository in owner/repo format
# @return JSON array of topics
# Usage: gh_repo_topics "owner/repo"
gh_repo_topics() {
    local repo="$1"
    _gh_require_auth || return 1
    gh repo view "$repo" --json repositoryTopics --jq '.repositoryTopics[].name' 2>/dev/null
}

# Get repository languages breakdown
# @param $1 repo - Repository in owner/repo format
# @return JSON object with language percentages
# Usage: gh_repo_languages "owner/repo"
gh_repo_languages() {
    local repo="$1"
    _gh_require_auth || return 1
    gh api "repos/$repo/languages" 2>/dev/null
}

# List repository contributors
# @param $1 repo - Repository in owner/repo format
# @param $2 [limit] - Max results (default: 30)
# @return JSON array of contributors
# Usage: gh_repo_contributors "owner/repo"
gh_repo_contributors() {
    local repo="$1"
    local limit="${2:-30}"
    _gh_require_auth || return 1
    gh api "repos/$repo/contributors?per_page=$limit" 2>/dev/null
}

# Get star count for a repository
# @param $1 repo - Repository in owner/repo format
# @return Star count as integer
# Usage: stars=$(gh_repo_stars "owner/repo")
gh_repo_stars() {
    local repo="$1"
    _gh_require_auth || return 1
    gh repo view "$repo" --json stargazerCount --jq '.stargazerCount' 2>/dev/null
}

# Get fork count for a repository
# @param $1 repo - Repository in owner/repo format
# @return Fork count as integer
# Usage: forks=$(gh_repo_forks "owner/repo")
gh_repo_forks() {
    local repo="$1"
    _gh_require_auth || return 1
    gh repo view "$repo" --json forkCount --jq '.forkCount' 2>/dev/null
}

# Check if a repository exists
# @param $1 repo - Repository in owner/repo format
# @return 0 if exists, 1 otherwise
# Usage: gh_repo_exists "owner/repo" && echo "exists"
gh_repo_exists() {
    local repo="$1"
    _gh_require_auth || return 1
    gh repo view "$repo" &>/dev/null 2>&1
}

# Get default branch for a repository
# @param $1 repo - Repository in owner/repo format
# @return Branch name
# Usage: branch=$(gh_repo_default_branch "owner/repo")
gh_repo_default_branch() {
    local repo="$1"
    _gh_require_auth || return 1
    gh repo view "$repo" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null
}

# Check if repository is a fork
# @param $1 repo - Repository in owner/repo format
# @return 0 if fork, 1 otherwise
# Usage: gh_repo_is_fork "owner/repo" && echo "is a fork"
gh_repo_is_fork() {
    local repo="$1"
    _gh_require_auth || return 1
    local is_fork
    is_fork=$(gh repo view "$repo" --json isFork --jq '.isFork' 2>/dev/null)
    [[ "$is_fork" == "true" ]]
}

# Get parent repository if this is a fork
# @param $1 repo - Repository in owner/repo format
# @return Parent repo in owner/repo format
# Usage: parent=$(gh_repo_parent "owner/repo")
gh_repo_parent() {
    local repo="$1"
    _gh_require_auth || return 1
    gh repo view "$repo" --json parent --jq '.parent.nameWithOwner' 2>/dev/null
}

# Get repository visibility
# @param $1 repo - Repository in owner/repo format
# @return "public", "private", or "internal"
# Usage: visibility=$(gh_repo_visibility "owner/repo")
gh_repo_visibility() {
    local repo="$1"
    _gh_require_auth || return 1
    local is_private
    is_private=$(gh repo view "$repo" --json isPrivate --jq '.isPrivate' 2>/dev/null)
    if [[ "$is_private" == "true" ]]; then
        printf 'private'
    else
        printf 'public'
    fi
}

# Rename a repository
# @param $1 repo - Repository in owner/repo format
# @param $2 new_name - New repository name
# @return 0 on success
# Usage: gh_repo_rename "owner/old-name" "new-name"
gh_repo_rename() {
    local repo="$1"
    local new_name="$2"
    _gh_require_auth || return 1
    gh repo rename "$new_name" -R "$repo" --yes 2>/dev/null
}

# Sync a fork with upstream
# @param $1 [repo] - Repository (default: current repo)
# @param --branch - Branch to sync (default: default branch)
# @return 0 on success
# Usage: gh_repo_sync
# Usage: gh_repo_sync "owner/repo" --branch main
gh_repo_sync() {
    _gh_require_auth || return 1
    gh repo sync "$@" 2>/dev/null
}

# =============================================================================
# ISSUES
# =============================================================================

# List issues for a repository
# @param $1 repo - Repository in owner/repo format
# @param --state - open, closed, all (default: open)
# @param --limit - Max results (default: 30)
# @return JSON array of issues
# Usage: gh_issue_list "owner/repo"
# Usage: gh_issue_list "owner/repo" --state closed --limit 50
gh_issue_list() {
    local repo="$1"
    shift
    _gh_require_auth || return 1
    gh issue list -R "$repo" --json number,title,state,author,labels,assignees,createdAt,updatedAt,url "$@" 2>/dev/null
}

# Create a new issue
# @param $1 repo - Repository in owner/repo format
# @param $2 title - Issue title
# @param $3 [body] - Issue body
# @return JSON with new issue info
# Usage: gh_issue_create "owner/repo" "Bug report" "Description here"
gh_issue_create() {
    local repo="$1"
    local title="$2"
    local body="${3:-}"
    _gh_require_auth || return 1
    if [[ -n "$body" ]]; then
        gh issue create -R "$repo" --title "$title" --body "$body" --json number,url 2>/dev/null
    else
        gh issue create -R "$repo" --title "$title" --json number,url 2>/dev/null
    fi
}

# View issue details
# @param $1 repo - Repository in owner/repo format
# @param $2 number - Issue number
# @return JSON with issue details
# Usage: gh_issue_view "owner/repo" 123
gh_issue_view() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh issue view "$number" -R "$repo" --json number,title,body,state,author,labels,assignees,comments,createdAt,updatedAt,url 2>/dev/null
}

# Close an issue
# @param $1 repo - Repository in owner/repo format
# @param $2 number - Issue number
# @return 0 on success
# Usage: gh_issue_close "owner/repo" 123
gh_issue_close() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh issue close "$number" -R "$repo" 2>/dev/null
}

# Reopen an issue
# @param $1 repo - Repository in owner/repo format
# @param $2 number - Issue number
# @return 0 on success
# Usage: gh_issue_reopen "owner/repo" 123
gh_issue_reopen() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh issue reopen "$number" -R "$repo" 2>/dev/null
}

# Add a comment to an issue
# @param $1 repo - Repository in owner/repo format
# @param $2 number - Issue number
# @param $3 body - Comment body
# @return 0 on success
# Usage: gh_issue_comment "owner/repo" 123 "This is my comment"
gh_issue_comment() {
    local repo="$1"
    local number="$2"
    local body="$3"
    _gh_require_auth || return 1
    gh issue comment "$number" -R "$repo" --body "$body" 2>/dev/null
}

# Get labels on an issue
# @param $1 repo - Repository in owner/repo format
# @param $2 number - Issue number
# @return JSON array of labels
# Usage: gh_issue_labels "owner/repo" 123
gh_issue_labels() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh issue view "$number" -R "$repo" --json labels --jq '.labels[].name' 2>/dev/null
}

# Add labels to an issue
# @param $1 repo - Repository in owner/repo format
# @param $2 number - Issue number
# @param $@ labels - Label names to add
# @return 0 on success
# Usage: gh_issue_add_labels "owner/repo" 123 "bug" "help wanted"
gh_issue_add_labels() {
    local repo="$1"
    local number="$2"
    shift 2
    _gh_require_auth || return 1
    gh issue edit "$number" -R "$repo" --add-label "$(IFS=','; echo "$*")" 2>/dev/null
}

# Get assignees on an issue
# @param $1 repo - Repository in owner/repo format
# @param $2 number - Issue number
# @return Newline-separated list of usernames
# Usage: gh_issue_assignees "owner/repo" 123
gh_issue_assignees() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh issue view "$number" -R "$repo" --json assignees --jq '.assignees[].login' 2>/dev/null
}

# Assign users to an issue
# @param $1 repo - Repository in owner/repo format
# @param $2 number - Issue number
# @param $@ users - Usernames to assign
# @return 0 on success
# Usage: gh_issue_assign "owner/repo" 123 "user1" "user2"
gh_issue_assign() {
    local repo="$1"
    local number="$2"
    shift 2
    _gh_require_auth || return 1
    gh issue edit "$number" -R "$repo" --add-assignee "$(IFS=','; echo "$*")" 2>/dev/null
}

# Search issues
# @param $1 query - Search query
# @param --limit - Max results (default: 30)
# @return JSON array of issues
# Usage: gh_issue_search "label:bug is:open"
gh_issue_search() {
    local query="$1"
    shift
    _gh_require_auth || return 1
    gh search issues "$query" --json repository,number,title,state,author,createdAt,url "$@" 2>/dev/null
}

# Edit an issue
# @param $1 repo - Repository in owner/repo format
# @param $2 number - Issue number
# @param $@ options - Edit options (--title, --body, etc.)
# @return 0 on success
# Usage: gh_issue_edit "owner/repo" 123 --title "New title"
gh_issue_edit() {
    local repo="$1"
    local number="$2"
    shift 2
    _gh_require_auth || return 1
    gh issue edit "$number" -R "$repo" "$@" 2>/dev/null
}

# Transfer an issue to another repository
# @param $1 repo - Source repository in owner/repo format
# @param $2 number - Issue number
# @param $3 target - Target repository in owner/repo format
# @return 0 on success
# Usage: gh_issue_transfer "owner/repo" 123 "owner/other-repo"
gh_issue_transfer() {
    local repo="$1"
    local number="$2"
    local target="$3"
    _gh_require_auth || return 1
    gh issue transfer "$number" "$target" -R "$repo" 2>/dev/null
}

# Pin an issue
# @param $1 repo - Repository in owner/repo format
# @param $2 number - Issue number
# @return 0 on success
# Usage: gh_issue_pin "owner/repo" 123
gh_issue_pin() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh issue pin "$number" -R "$repo" 2>/dev/null
}

# Unpin an issue
# @param $1 repo - Repository in owner/repo format
# @param $2 number - Issue number
# @return 0 on success
# Usage: gh_issue_unpin "owner/repo" 123
gh_issue_unpin() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh issue unpin "$number" -R "$repo" 2>/dev/null
}

# =============================================================================
# PULL REQUESTS
# =============================================================================

# List pull requests for a repository
# @param $1 repo - Repository in owner/repo format
# @param --state - open, closed, merged, all (default: open)
# @param --limit - Max results (default: 30)
# @return JSON array of PRs
# Usage: gh_pr_list "owner/repo"
# Usage: gh_pr_list "owner/repo" --state merged --limit 50
gh_pr_list() {
    local repo="$1"
    shift
    _gh_require_auth || return 1
    gh pr list -R "$repo" --json number,title,state,author,headRefName,baseRefName,isDraft,labels,createdAt,updatedAt,url "$@" 2>/dev/null
}

# Create a new pull request
# @param $1 repo - Repository in owner/repo format
# @param $2 title - PR title
# @param --body - PR body
# @param --base - Base branch (default: default branch)
# @param --head - Head branch (default: current branch)
# @param --draft - Create as draft
# @return JSON with new PR info
# Usage: gh_pr_create "owner/repo" "My PR" --body "Description" --base main
gh_pr_create() {
    local repo="$1"
    local title="$2"
    shift 2
    _gh_require_auth || return 1
    gh pr create -R "$repo" --title "$title" --json number,url "$@" 2>/dev/null
}

# View pull request details
# @param $1 repo - Repository in owner/repo format
# @param $2 number - PR number
# @return JSON with PR details
# Usage: gh_pr_view "owner/repo" 42
gh_pr_view() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh pr view "$number" -R "$repo" --json number,title,body,state,author,headRefName,baseRefName,isDraft,mergeable,labels,assignees,reviewRequests,reviews,comments,commits,additions,deletions,changedFiles,createdAt,updatedAt,mergedAt,url 2>/dev/null
}

# Get pull request diff
# @param $1 repo - Repository in owner/repo format
# @param $2 number - PR number
# @return Diff text
# Usage: gh_pr_diff "owner/repo" 42
gh_pr_diff() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh pr diff "$number" -R "$repo" 2>/dev/null
}

# List files changed in a pull request
# @param $1 repo - Repository in owner/repo format
# @param $2 number - PR number
# @return JSON array of changed files
# Usage: gh_pr_files "owner/repo" 42
gh_pr_files() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh pr view "$number" -R "$repo" --json files 2>/dev/null
}

# Merge a pull request
# @param $1 repo - Repository in owner/repo format
# @param $2 number - PR number
# @param --squash|--rebase|--merge - Merge method
# @param --delete-branch - Delete branch after merge
# @return 0 on success
# Usage: gh_pr_merge "owner/repo" 42 --squash --delete-branch
gh_pr_merge() {
    local repo="$1"
    local number="$2"
    shift 2
    _gh_require_auth || return 1
    gh pr merge "$number" -R "$repo" "$@" 2>/dev/null
}

# Close a pull request without merging
# @param $1 repo - Repository in owner/repo format
# @param $2 number - PR number
# @return 0 on success
# Usage: gh_pr_close "owner/repo" 42
gh_pr_close() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh pr close "$number" -R "$repo" 2>/dev/null
}

# Reopen a closed pull request
# @param $1 repo - Repository in owner/repo format
# @param $2 number - PR number
# @return 0 on success
# Usage: gh_pr_reopen "owner/repo" 42
gh_pr_reopen() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh pr reopen "$number" -R "$repo" 2>/dev/null
}

# Review a pull request
# @param $1 repo - Repository in owner/repo format
# @param $2 number - PR number
# @param --approve|--request-changes|--comment - Review action
# @param --body - Review body
# @return 0 on success
# Usage: gh_pr_review "owner/repo" 42 --approve --body "LGTM"
gh_pr_review() {
    local repo="$1"
    local number="$2"
    shift 2
    _gh_require_auth || return 1
    gh pr review "$number" -R "$repo" "$@" 2>/dev/null
}

# Add a comment to a pull request
# @param $1 repo - Repository in owner/repo format
# @param $2 number - PR number
# @param $3 body - Comment body
# @return 0 on success
# Usage: gh_pr_comment "owner/repo" 42 "Nice work!"
gh_pr_comment() {
    local repo="$1"
    local number="$2"
    local body="$3"
    _gh_require_auth || return 1
    gh pr comment "$number" -R "$repo" --body "$body" 2>/dev/null
}

# Get CI/check status for a pull request
# @param $1 repo - Repository in owner/repo format
# @param $2 number - PR number
# @return JSON with check statuses
# Usage: gh_pr_checks "owner/repo" 42
gh_pr_checks() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh pr checks "$number" -R "$repo" --json name,state,conclusion,startedAt,completedAt,url 2>/dev/null
}

# Mark a PR as ready for review (remove draft status)
# @param $1 repo - Repository in owner/repo format
# @param $2 number - PR number
# @return 0 on success
# Usage: gh_pr_ready "owner/repo" 42
gh_pr_ready() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh pr ready "$number" -R "$repo" 2>/dev/null
}

# Convert a PR to draft
# @param $1 repo - Repository in owner/repo format
# @param $2 number - PR number
# @return 0 on success
# Usage: gh_pr_draft "owner/repo" 42
gh_pr_draft() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh pr ready "$number" -R "$repo" --undo 2>/dev/null
}

# Get labels on a pull request
# @param $1 repo - Repository in owner/repo format
# @param $2 number - PR number
# @return Newline-separated list of labels
# Usage: gh_pr_labels "owner/repo" 42
gh_pr_labels() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh pr view "$number" -R "$repo" --json labels --jq '.labels[].name' 2>/dev/null
}

# Get requested reviewers for a pull request
# @param $1 repo - Repository in owner/repo format
# @param $2 number - PR number
# @return Newline-separated list of usernames
# Usage: gh_pr_reviewers "owner/repo" 42
gh_pr_reviewers() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh pr view "$number" -R "$repo" --json reviewRequests --jq '.reviewRequests[].login' 2>/dev/null
}

# Checkout a pull request locally
# @param $1 repo - Repository in owner/repo format
# @param $2 number - PR number
# @return 0 on success
# Usage: gh_pr_checkout "owner/repo" 42
gh_pr_checkout() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh pr checkout "$number" -R "$repo" 2>/dev/null
}

# Check if a pull request is merged
# @param $1 repo - Repository in owner/repo format
# @param $2 number - PR number
# @return 0 if merged, 1 otherwise
# Usage: gh_pr_is_merged "owner/repo" 42 && echo "merged"
gh_pr_is_merged() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    local state
    state=$(gh pr view "$number" -R "$repo" --json state --jq '.state' 2>/dev/null)
    [[ "$state" == "MERGED" ]]
}

# Get the merge commit hash for a merged PR
# @param $1 repo - Repository in owner/repo format
# @param $2 number - PR number
# @return Merge commit SHA
# Usage: commit=$(gh_pr_merge_commit "owner/repo" 42)
gh_pr_merge_commit() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1
    gh pr view "$number" -R "$repo" --json mergeCommit --jq '.mergeCommit.oid' 2>/dev/null
}

# Edit a pull request
# @param $1 repo - Repository in owner/repo format
# @param $2 number - PR number
# @param $@ options - Edit options (--title, --body, --add-label, etc.)
# @return 0 on success
# Usage: gh_pr_edit "owner/repo" 42 --title "New title" --add-label "bug"
gh_pr_edit() {
    local repo="$1"
    local number="$2"
    shift 2
    _gh_require_auth || return 1
    gh pr edit "$number" -R "$repo" "$@" 2>/dev/null
}

# =============================================================================
# GISTS
# =============================================================================

# List user's gists
# @param --public|--secret - Filter by visibility
# @param --limit - Max results (default: 10)
# @return JSON array of gists
# Usage: gh_gist_list
# Usage: gh_gist_list --public --limit 20
gh_gist_list() {
    _gh_require_auth || return 1
    gh gist list "$@" 2>/dev/null
}

# Create a new gist
# @param $1 file - File to include in gist (or - for stdin)
# @param --public|--secret - Visibility (default: secret)
# @param --desc - Gist description
# @return Gist URL
# Usage: gh_gist_create "script.sh" --public --desc "My script"
# Usage: echo "content" | gh_gist_create - --desc "From stdin"
gh_gist_create() {
    _gh_require_auth || return 1
    gh gist create "$@" 2>/dev/null
}

# View gist content
# @param $1 id - Gist ID or URL
# @param --files - Show only filenames
# @return Gist content
# Usage: gh_gist_view "abc123"
gh_gist_view() {
    local id="$1"
    shift
    _gh_require_auth || return 1
    gh gist view "$id" "$@" 2>/dev/null
}

# Clone a gist
# @param $1 id - Gist ID or URL
# @param $2 [dir] - Target directory
# @return 0 on success
# Usage: gh_gist_clone "abc123"
# Usage: gh_gist_clone "abc123" "./my-gist"
gh_gist_clone() {
    local id="$1"
    local dir="${2:-}"
    _gh_require_auth || return 1
    if [[ -n "$dir" ]]; then
        gh gist clone "$id" "$dir" 2>/dev/null
    else
        gh gist clone "$id" 2>/dev/null
    fi
}

# Edit a gist
# @param $1 id - Gist ID or URL
# @param --add - Add a file
# @param --remove - Remove a file
# @return 0 on success
# Usage: gh_gist_edit "abc123" --add "newfile.txt"
gh_gist_edit() {
    local id="$1"
    shift
    _gh_require_auth || return 1
    gh gist edit "$id" "$@" 2>/dev/null
}

# Delete a gist
# @param $1 id - Gist ID or URL
# @return 0 on success
# Usage: gh_gist_delete "abc123"
gh_gist_delete() {
    local id="$1"
    _gh_require_auth || return 1
    gh gist delete "$id" --yes 2>/dev/null
}

# Rename a gist file
# @param $1 id - Gist ID or URL
# @param $2 old_name - Current filename
# @param $3 new_name - New filename
# @return 0 on success
# Usage: gh_gist_rename "abc123" "old.txt" "new.txt"
gh_gist_rename() {
    local id="$1"
    local old_name="$2"
    local new_name="$3"
    _gh_require_auth || return 1
    gh gist rename "$id" "$old_name" "$new_name" 2>/dev/null
}

# =============================================================================
# RELEASES
# =============================================================================

# List releases for a repository
# @param $1 repo - Repository in owner/repo format
# @param --limit - Max results (default: 30)
# @return JSON array of releases
# Usage: gh_release_list "owner/repo"
gh_release_list() {
    local repo="$1"
    shift
    _gh_require_auth || return 1
    gh release list -R "$repo" "$@" 2>/dev/null
}

# Get the latest release
# @param $1 repo - Repository in owner/repo format
# @return JSON with release info
# Usage: gh_release_latest "owner/repo"
gh_release_latest() {
    local repo="$1"
    _gh_require_auth || return 1
    gh release view -R "$repo" --json tagName,name,body,isDraft,isPrerelease,createdAt,publishedAt,url,assets 2>/dev/null
}

# Create a new release
# @param $1 repo - Repository in owner/repo format
# @param $2 tag - Tag name for the release
# @param --title - Release title
# @param --notes - Release notes
# @param --draft - Create as draft
# @param --prerelease - Mark as prerelease
# @param --target - Target commitish
# @return JSON with release info
# Usage: gh_release_create "owner/repo" "v1.0.0" --title "Version 1.0" --notes "First release"
gh_release_create() {
    local repo="$1"
    local tag="$2"
    shift 2
    _gh_require_auth || return 1
    gh release create "$tag" -R "$repo" "$@" 2>/dev/null
}

# View release details
# @param $1 repo - Repository in owner/repo format
# @param $2 tag - Tag name
# @return JSON with release info
# Usage: gh_release_view "owner/repo" "v1.0.0"
gh_release_view() {
    local repo="$1"
    local tag="$2"
    _gh_require_auth || return 1
    gh release view "$tag" -R "$repo" --json tagName,name,body,isDraft,isPrerelease,createdAt,publishedAt,url,assets 2>/dev/null
}

# Delete a release
# @param $1 repo - Repository in owner/repo format
# @param $2 tag - Tag name
# @param --yes - Skip confirmation
# @return 0 on success
# Usage: gh_release_delete "owner/repo" "v1.0.0" --yes
gh_release_delete() {
    local repo="$1"
    local tag="$2"
    shift 2
    _gh_require_auth || return 1
    gh release delete "$tag" -R "$repo" "$@" 2>/dev/null
}

# Download release assets
# @param $1 repo - Repository in owner/repo format
# @param $2 tag - Tag name
# @param --dir - Download directory
# @param --pattern - Glob pattern for assets
# @return 0 on success
# Usage: gh_release_download "owner/repo" "v1.0.0" --dir ./downloads
gh_release_download() {
    local repo="$1"
    local tag="$2"
    shift 2
    _gh_require_auth || return 1
    gh release download "$tag" -R "$repo" "$@" 2>/dev/null
}

# Upload assets to a release
# @param $1 repo - Repository in owner/repo format
# @param $2 tag - Tag name
# @param $@ files - Files to upload
# @return 0 on success
# Usage: gh_release_upload "owner/repo" "v1.0.0" "dist/app.zip" "dist/app.tar.gz"
gh_release_upload() {
    local repo="$1"
    local tag="$2"
    shift 2
    _gh_require_auth || return 1
    gh release upload "$tag" "$@" -R "$repo" 2>/dev/null
}

# Generate release notes
# @param $1 repo - Repository in owner/repo format
# @param $2 tag - Tag name
# @param --previous-tag - Previous tag for comparison
# @return Generated release notes
# Usage: gh_release_notes "owner/repo" "v1.1.0" --previous-tag "v1.0.0"
gh_release_notes() {
    local repo="$1"
    local tag="$2"
    shift 2
    _gh_require_auth || return 1
    gh api "repos/$repo/releases/generate-notes" -f tag_name="$tag" "$@" --jq '.body' 2>/dev/null
}

# Edit a release
# @param $1 repo - Repository in owner/repo format
# @param $2 tag - Tag name
# @param $@ options - Edit options (--title, --notes, --draft, etc.)
# @return 0 on success
# Usage: gh_release_edit "owner/repo" "v1.0.0" --title "New Title"
gh_release_edit() {
    local repo="$1"
    local tag="$2"
    shift 2
    _gh_require_auth || return 1
    gh release edit "$tag" -R "$repo" "$@" 2>/dev/null
}

# =============================================================================
# SEARCH
# =============================================================================

# Search repositories
# @param $1 query - Search query
# @param --limit - Max results (default: 30)
# @return JSON array of repos
# Usage: gh_search_repos "language:bash stars:>100"
gh_search_repos() {
    local query="$1"
    shift
    _gh_require_auth || return 1
    gh search repos "$query" --json fullName,description,isPrivate,isFork,stargazerCount,forkCount,updatedAt,url "$@" 2>/dev/null
}

# Search code
# @param $1 query - Search query
# @param --limit - Max results (default: 30)
# @return JSON array of code matches
# Usage: gh_search_code "function main repo:owner/repo"
gh_search_code() {
    local query="$1"
    shift
    _gh_require_auth || return 1
    gh search code "$query" --json repository,path,url "$@" 2>/dev/null
}

# Search issues and pull requests
# @param $1 query - Search query
# @param --limit - Max results (default: 30)
# @return JSON array of issues/PRs
# Usage: gh_search_issues "is:open label:bug"
gh_search_issues() {
    local query="$1"
    shift
    _gh_require_auth || return 1
    gh search issues "$query" --json repository,number,title,state,author,createdAt,url "$@" 2>/dev/null
}

# Search users
# @param $1 query - Search query
# @param --limit - Max results (default: 30)
# @return JSON array of users
# Usage: gh_search_users "location:SF followers:>1000"
gh_search_users() {
    local query="$1"
    shift
    _gh_require_auth || return 1
    gh api "search/users?q=$(printf '%s' "$query" | jq -sRr @uri)&per_page=${1:-30}" --jq '.items' 2>/dev/null
}

# Search commits
# @param $1 query - Search query
# @param --limit - Max results (default: 30)
# @return JSON array of commits
# Usage: gh_search_commits "fix bug repo:owner/repo"
gh_search_commits() {
    local query="$1"
    shift
    _gh_require_auth || return 1
    gh search commits "$query" --json repository,sha,commit,author,url "$@" 2>/dev/null
}

# Search topics
# @param $1 query - Topic query
# @return JSON array of topics
# Usage: gh_search_topics "machine-learning"
gh_search_topics() {
    local query="$1"
    _gh_require_auth || return 1
    gh api "search/topics?q=$query" --jq '.items' 2>/dev/null
}

# =============================================================================
# USER & SOCIAL
# =============================================================================

# Get user profile info
# @param $1 username - GitHub username
# @return JSON with user info
# Usage: gh_user_info "octocat"
gh_user_info() {
    local username="$1"
    _gh_require_auth || return 1
    gh api "users/$username" 2>/dev/null
}

# List user's public repositories
# @param $1 username - GitHub username
# @param $2 [limit] - Max results (default: 30)
# @return JSON array of repos
# Usage: gh_user_repos "octocat"
gh_user_repos() {
    local username="$1"
    local limit="${2:-30}"
    _gh_require_auth || return 1
    gh api "users/$username/repos?per_page=$limit&sort=updated" 2>/dev/null
}

# List user's organizations
# @param $1 username - GitHub username
# @return JSON array of orgs
# Usage: gh_user_orgs "octocat"
gh_user_orgs() {
    local username="$1"
    _gh_require_auth || return 1
    gh api "users/$username/orgs" 2>/dev/null
}

# List user's followers
# @param $1 username - GitHub username
# @param $2 [limit] - Max results (default: 30)
# @return JSON array of users
# Usage: gh_user_followers "octocat"
gh_user_followers() {
    local username="$1"
    local limit="${2:-30}"
    _gh_require_auth || return 1
    gh api "users/$username/followers?per_page=$limit" 2>/dev/null
}

# List who user follows
# @param $1 username - GitHub username
# @param $2 [limit] - Max results (default: 30)
# @return JSON array of users
# Usage: gh_user_following "octocat"
gh_user_following() {
    local username="$1"
    local limit="${2:-30}"
    _gh_require_auth || return 1
    gh api "users/$username/following?per_page=$limit" 2>/dev/null
}

# Star a repository
# @param $1 repo - Repository in owner/repo format
# @return 0 on success
# Usage: gh_star_repo "owner/repo"
gh_star_repo() {
    local repo="$1"
    _gh_require_auth || return 1
    gh api "user/starred/$repo" -X PUT 2>/dev/null
}

# Unstar a repository
# @param $1 repo - Repository in owner/repo format
# @return 0 on success
# Usage: gh_unstar_repo "owner/repo"
gh_unstar_repo() {
    local repo="$1"
    _gh_require_auth || return 1
    gh api "user/starred/$repo" -X DELETE 2>/dev/null
}

# Watch a repository
# @param $1 repo - Repository in owner/repo format
# @return 0 on success
# Usage: gh_watch_repo "owner/repo"
gh_watch_repo() {
    local repo="$1"
    _gh_require_auth || return 1
    gh api "repos/$repo/subscription" -X PUT -f subscribed=true 2>/dev/null
}

# Check if user has starred a repo
# @param $1 repo - Repository in owner/repo format
# @return 0 if starred, 1 otherwise
# Usage: gh_is_starred "owner/repo" && echo "starred"
gh_is_starred() {
    local repo="$1"
    _gh_require_auth || return 1
    gh api "user/starred/$repo" 2>/dev/null
}

# Follow a user
# @param $1 username - GitHub username
# @return 0 on success
# Usage: gh_follow_user "octocat"
gh_follow_user() {
    local username="$1"
    _gh_require_auth || return 1
    gh api "user/following/$username" -X PUT 2>/dev/null
}

# Unfollow a user
# @param $1 username - GitHub username
# @return 0 on success
# Usage: gh_unfollow_user "octocat"
gh_unfollow_user() {
    local username="$1"
    _gh_require_auth || return 1
    gh api "user/following/$username" -X DELETE 2>/dev/null
}

# =============================================================================
# NOTIFICATIONS
# =============================================================================

# List notifications
# @param --all - Include read notifications
# @param --participating - Only participating
# @return JSON array of notifications
# Usage: gh_notifications_list
gh_notifications_list() {
    _gh_require_auth || return 1
    gh api notifications "$@" 2>/dev/null
}

# Get unread notification count
# @return Number of unread notifications
# Usage: count=$(gh_notifications_count)
gh_notifications_count() {
    _gh_require_auth || return 1
    gh api notifications --jq 'length' 2>/dev/null
}

# Mark all notifications as read
# @return 0 on success
# Usage: gh_notifications_mark_read
gh_notifications_mark_read() {
    _gh_require_auth || return 1
    gh api notifications -X PUT -f read=true 2>/dev/null
}

# Mark repository notifications as read
# @param $1 repo - Repository in owner/repo format
# @return 0 on success
# Usage: gh_notifications_mark_read_repo "owner/repo"
gh_notifications_mark_read_repo() {
    local repo="$1"
    _gh_require_auth || return 1
    gh api "repos/$repo/notifications" -X PUT 2>/dev/null
}

# =============================================================================
# ACTIONS / WORKFLOWS
# =============================================================================

# List workflow runs
# @param $1 repo - Repository in owner/repo format
# @param --limit - Max results (default: 20)
# @return JSON array of runs
# Usage: gh_run_list "owner/repo"
gh_run_list() {
    local repo="$1"
    shift
    _gh_require_auth || return 1
    gh run list -R "$repo" --json databaseId,displayTitle,status,conclusion,event,headBranch,createdAt,url "$@" 2>/dev/null
}

# View a specific workflow run
# @param $1 repo - Repository in owner/repo format
# @param $2 run_id - Run ID
# @return JSON with run details
# Usage: gh_run_view "owner/repo" 12345
gh_run_view() {
    local repo="$1"
    local run_id="$2"
    _gh_require_auth || return 1
    gh run view "$run_id" -R "$repo" --json databaseId,displayTitle,status,conclusion,jobs,createdAt,updatedAt,url 2>/dev/null
}

# Rerun a workflow
# @param $1 repo - Repository in owner/repo format
# @param $2 run_id - Run ID
# @return 0 on success
# Usage: gh_run_rerun "owner/repo" 12345
gh_run_rerun() {
    local repo="$1"
    local run_id="$2"
    _gh_require_auth || return 1
    gh run rerun "$run_id" -R "$repo" 2>/dev/null
}

# Cancel a workflow run
# @param $1 repo - Repository in owner/repo format
# @param $2 run_id - Run ID
# @return 0 on success
# Usage: gh_run_cancel "owner/repo" 12345
gh_run_cancel() {
    local repo="$1"
    local run_id="$2"
    _gh_require_auth || return 1
    gh run cancel "$run_id" -R "$repo" 2>/dev/null
}

# Watch a workflow run
# @param $1 repo - Repository in owner/repo format
# @param $2 run_id - Run ID
# @return 0 on completion
# Usage: gh_run_watch "owner/repo" 12345
gh_run_watch() {
    local repo="$1"
    local run_id="$2"
    _gh_require_auth || return 1
    gh run watch "$run_id" -R "$repo" 2>/dev/null
}

# Download workflow artifacts
# @param $1 repo - Repository in owner/repo format
# @param $2 run_id - Run ID
# @param --dir - Download directory
# @return 0 on success
# Usage: gh_run_download "owner/repo" 12345 --dir ./artifacts
gh_run_download() {
    local repo="$1"
    local run_id="$2"
    shift 2
    _gh_require_auth || return 1
    gh run download "$run_id" -R "$repo" "$@" 2>/dev/null
}

# =============================================================================
# AI AGENT CONTEXT FUNCTIONS
# =============================================================================

# Get comprehensive repository context as JSON for AI agents
# @param $1 repo - Repository in owner/repo format
# @return JSON object with full repo context optimized for AI consumption
# Usage: gh_context_json "owner/repo"
gh_context_json() {
    local repo="$1"
    _gh_require_auth || return 1

    local repo_json languages contributors readme
    repo_json=$(gh repo view "$repo" --json name,owner,description,url,sshUrl,defaultBranchRef,isPrivate,isFork,isArchived,stargazerCount,forkCount,createdAt,updatedAt,diskUsage,licenseInfo,repositoryTopics 2>/dev/null) || return 1
    languages=$(gh api "repos/$repo/languages" 2>/dev/null) || languages="{}"
    contributors=$(gh api "repos/$repo/contributors?per_page=5" --jq '[.[] | {login, contributions}]' 2>/dev/null) || contributors="[]"

    # Try to get README
    readme=$(gh api "repos/$repo/readme" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null | head -c 2000) || readme=""

    # Build context JSON
    printf '{'
    printf '"repository":%s,' "$repo_json"
    printf '"languages":%s,' "$languages"
    printf '"top_contributors":%s,' "$contributors"
    printf '"readme_preview":"%s"' "$(_gh_json_escape "${readme:0:2000}")"
    printf '}\n'
}

# Get PR context with diff stats for AI agents
# @param $1 repo - Repository in owner/repo format
# @param $2 number - PR number
# @return JSON with PR details and diff summary
# Usage: gh_pr_context "owner/repo" 42
gh_pr_context() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1

    local pr_json files_json checks_json
    pr_json=$(gh pr view "$number" -R "$repo" --json number,title,body,state,author,headRefName,baseRefName,isDraft,mergeable,labels,assignees,additions,deletions,changedFiles,createdAt,url 2>/dev/null) || return 1
    files_json=$(gh pr view "$number" -R "$repo" --json files --jq '[.files[] | {path, additions, deletions}]' 2>/dev/null) || files_json="[]"
    checks_json=$(gh pr checks "$number" -R "$repo" --json name,state,conclusion 2>/dev/null) || checks_json="[]"

    printf '{'
    printf '"pull_request":%s,' "$pr_json"
    printf '"changed_files":%s,' "$files_json"
    printf '"checks":%s' "$checks_json"
    printf '}\n'
}

# Get issue context with comments for AI agents
# @param $1 repo - Repository in owner/repo format
# @param $2 number - Issue number
# @return JSON with issue details and recent comments
# Usage: gh_issue_context "owner/repo" 123
gh_issue_context() {
    local repo="$1"
    local number="$2"
    _gh_require_auth || return 1

    local issue_json comments_json
    issue_json=$(gh issue view "$number" -R "$repo" --json number,title,body,state,author,labels,assignees,createdAt,updatedAt,url 2>/dev/null) || return 1
    comments_json=$(gh api "repos/$repo/issues/$number/comments?per_page=10" --jq '[.[] | {author: .user.login, body: .body, created_at: .created_at}]' 2>/dev/null) || comments_json="[]"

    printf '{'
    printf '"issue":%s,' "$issue_json"
    printf '"recent_comments":%s' "$comments_json"
    printf '}\n'
}

# Parse CODEOWNERS file from repository
# @param $1 repo - Repository in owner/repo format
# @return JSON array of ownership rules
# Usage: gh_codeowners "owner/repo"
gh_codeowners() {
    local repo="$1"
    _gh_require_auth || return 1

    local content
    # Try common CODEOWNERS locations
    for path in "CODEOWNERS" ".github/CODEOWNERS" "docs/CODEOWNERS"; do
        content=$(gh api "repos/$repo/contents/$path" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)
        if [[ -n "$content" ]]; then
            # Parse CODEOWNERS into JSON
            printf '['
            local first=true
            while IFS= read -r line; do
                # Skip empty lines and comments
                [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
                # Parse: pattern @owner1 @owner2
                local pattern owners
                pattern=$(echo "$line" | awk '{print $1}')
                owners=$(echo "$line" | awk '{$1=""; print}' | tr -d '@' | xargs)
                $first || printf ','
                first=false
                printf '{"pattern":"%s","owners":[' "$(_gh_json_escape "$pattern")"
                local first_owner=true
                for owner in $owners; do
                    $first_owner || printf ','
                    first_owner=false
                    printf '"%s"' "$(_gh_json_escape "$owner")"
                done
                printf ']}'
            done <<< "$content"
            printf ']\n'
            return 0
        fi
    done

    printf '[]\n'
}

# Get quick repository summary for context window
# @param $1 repo - Repository in owner/repo format
# @return Compact summary string
# Usage: gh_repo_summary "owner/repo"
gh_repo_summary() {
    local repo="$1"
    _gh_require_auth || return 1

    local json
    json=$(gh repo view "$repo" --json name,description,stargazerCount,forkCount,defaultBranchRef,isPrivate,isFork,isArchived,updatedAt 2>/dev/null) || return 1

    local name desc stars forks branch visibility
    name=$(echo "$json" | jq -r '.name // ""')
    desc=$(echo "$json" | jq -r '.description // "No description"')
    stars=$(echo "$json" | jq -r '.stargazerCount // 0')
    forks=$(echo "$json" | jq -r '.forkCount // 0')
    branch=$(echo "$json" | jq -r '.defaultBranchRef.name // "main"')
    visibility=$(echo "$json" | jq -r 'if .isPrivate then "private" else "public" end')

    printf '%s (%s) - %s | Stars: %s, Forks: %s, Branch: %s\n' \
        "$name" "$visibility" "${desc:0:100}" "$stars" "$forks" "$branch"
}

# Get repository file tree for context
# @param $1 repo - Repository in owner/repo format
# @param $2 [path] - Path to list (default: root)
# @param $3 [depth] - Max depth (default: 2)
# @return JSON array of files/directories
# Usage: gh_repo_tree "owner/repo"
# Usage: gh_repo_tree "owner/repo" "src" 3
gh_repo_tree() {
    local repo="$1"
    local path="${2:-.}"
    local depth="${3:-2}"
    _gh_require_auth || return 1

    local ref
    ref=$(gh_repo_default_branch "$repo") || ref="main"

    gh api "repos/$repo/git/trees/$ref?recursive=1" \
        --jq "[.tree[] | select(.path | startswith(\"$path\") or . == \"$path\") | {path, type, size}] | .[0:100]" 2>/dev/null
}

# Get recent commits for context
# @param $1 repo - Repository in owner/repo format
# @param $2 [limit] - Max commits (default: 10)
# @return JSON array of commits
# Usage: gh_recent_commits "owner/repo"
gh_recent_commits() {
    local repo="$1"
    local limit="${2:-10}"
    _gh_require_auth || return 1

    gh api "repos/$repo/commits?per_page=$limit" \
        --jq '[.[] | {sha: .sha[0:7], message: .commit.message, author: .commit.author.name, date: .commit.author.date}]' 2>/dev/null
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

_GITHUB_EXPORTS=(
    # Internal helpers (not exported but useful)
    _gh_available
    _gh_require_auth

    # Authentication
    gh_auth_status
    gh_auth_token
    gh_whoami
    gh_config_get
    gh_config_set

    # Repository operations
    gh_repo_view
    gh_repo_list
    gh_repo_create
    gh_repo_clone
    gh_repo_fork
    gh_repo_delete
    gh_repo_archive
    gh_repo_topics
    gh_repo_languages
    gh_repo_contributors
    gh_repo_stars
    gh_repo_forks
    gh_repo_exists
    gh_repo_default_branch
    gh_repo_is_fork
    gh_repo_parent
    gh_repo_visibility
    gh_repo_rename
    gh_repo_sync

    # Issues
    gh_issue_list
    gh_issue_create
    gh_issue_view
    gh_issue_close
    gh_issue_reopen
    gh_issue_comment
    gh_issue_labels
    gh_issue_add_labels
    gh_issue_assignees
    gh_issue_assign
    gh_issue_search
    gh_issue_edit
    gh_issue_transfer
    gh_issue_pin
    gh_issue_unpin

    # Pull requests
    gh_pr_list
    gh_pr_create
    gh_pr_view
    gh_pr_diff
    gh_pr_files
    gh_pr_merge
    gh_pr_close
    gh_pr_reopen
    gh_pr_review
    gh_pr_comment
    gh_pr_checks
    gh_pr_ready
    gh_pr_draft
    gh_pr_labels
    gh_pr_reviewers
    gh_pr_checkout
    gh_pr_is_merged
    gh_pr_merge_commit
    gh_pr_edit

    # Gists
    gh_gist_list
    gh_gist_create
    gh_gist_view
    gh_gist_clone
    gh_gist_edit
    gh_gist_delete
    gh_gist_rename

    # Releases
    gh_release_list
    gh_release_latest
    gh_release_create
    gh_release_view
    gh_release_delete
    gh_release_download
    gh_release_upload
    gh_release_notes
    gh_release_edit

    # Search
    gh_search_repos
    gh_search_code
    gh_search_issues
    gh_search_users
    gh_search_commits
    gh_search_topics

    # User & Social
    gh_user_info
    gh_user_repos
    gh_user_orgs
    gh_user_followers
    gh_user_following
    gh_star_repo
    gh_unstar_repo
    gh_watch_repo
    gh_is_starred
    gh_follow_user
    gh_unfollow_user

    # Notifications
    gh_notifications_list
    gh_notifications_count
    gh_notifications_mark_read
    gh_notifications_mark_read_repo

    # Actions/Workflows
    gh_run_list
    gh_run_view
    gh_run_rerun
    gh_run_cancel
    gh_run_watch
    gh_run_download

    # AI Agent Context
    gh_context_json
    gh_pr_context
    gh_issue_context
    gh_codeowners
    gh_repo_summary
    gh_repo_tree
    gh_recent_commits
)

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/github_actions.sh - GitHub Actions Workflow Library
# =============================================================================
# Description: Comprehensive GitHub Actions management for CI/CD workflows.
#              Provides workflow management, run control, artifact handling,
#              secrets/variables, environments, YAML generation, and CI status
#              monitoring optimized for AI agent consumption.
#
# Features:
#   - Workflow listing, triggering, enable/disable
#   - Run management with status tracking and log retrieval
#   - Artifact upload/download/management
#   - Secrets and variables for repo/org/environment scopes
#   - Environment management with protection rules
#   - YAML generation helpers for common workflow patterns
#   - CI status and metrics for AI agent context
#   - Self-hosted runner management
#
# @module      github_actions
# @version     1.0.0
# @requires    git.sh (for repo detection)
# @provides    70+ functions
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_GITHUB_ACTIONS_LOADED:-}" ]] && return 0
readonly _MAINFRAME_GITHUB_ACTIONS_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

_GHA_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source git.sh if not already loaded
if [[ -z "${_MAINFRAME_GIT_LOADED:-}" ]]; then
    # shellcheck source=lib/git.sh
    source "$_GHA_LIB_DIR/git.sh" 2>/dev/null || true
fi

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Check if gh CLI is available
# Usage: _gha_check_gh && echo "gh available"
_gha_check_gh() {
    command -v gh &>/dev/null
}

# Get repo in owner/repo format
# Usage: repo=$(_gha_repo)
_gha_repo() {
    local repo="$1"
    if [[ -z "$repo" ]]; then
        # Try to detect from current git repo
        local owner name
        owner=$(git_repo_owner 2>/dev/null)
        name=$(git_repo_name 2>/dev/null)
        if [[ -n "$owner" && -n "$name" ]]; then
            printf '%s/%s' "$owner" "$name"
        else
            return 1
        fi
    else
        printf '%s' "$repo"
    fi
}

# Log error to stderr
# Usage: _gha_error "message"
_gha_error() {
    printf '[ERROR] github_actions: %s\n' "$1" >&2
}

# JSON escape a string
# Delegates to canonical json_escape from lib/json.sh (core tier, always loaded)
# Usage: escaped=$(_gha_json_escape "$string")
_gha_json_escape() {
    json_escape "$@"
}

# =============================================================================
# SECTION 1: WORKFLOW MANAGEMENT (~15 functions)
# =============================================================================

# List all workflows in a repository
# @param $1 - Repository (owner/repo format, or auto-detect)
# @param $2 - Limit (default: 30)
# @return JSON array of workflows
#
# Usage: gha_workflow_list
# Usage: gha_workflow_list "owner/repo"
# Usage: gha_workflow_list "owner/repo" 50
gha_workflow_list() {
    local repo limit
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    limit="${2:-30}"

    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh workflow list -R "$repo" --limit "$limit" --json id,name,path,state 2>/dev/null
}

# View detailed information about a workflow
# @param $1 - Repository (owner/repo)
# @param $2 - Workflow ID or filename
# @return JSON workflow details
#
# Usage: gha_workflow_view "owner/repo" "ci.yml"
# Usage: gha_workflow_view "owner/repo" 12345678
gha_workflow_view() {
    local repo workflow_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    workflow_id="$2"

    [[ -z "$workflow_id" ]] && { _gha_error "Workflow ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh workflow view "$workflow_id" -R "$repo" --json id,name,path,state 2>/dev/null
}

# List runs for a specific workflow
# @param $1 - Repository (owner/repo)
# @param $2 - Workflow ID or filename
# @param $3 - Limit (default: 20)
# @return JSON array of workflow runs
#
# Usage: gha_workflow_runs "owner/repo" "ci.yml"
# Usage: gha_workflow_runs "owner/repo" "ci.yml" 50
gha_workflow_runs() {
    local repo workflow_id limit
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    workflow_id="$2"
    limit="${3:-20}"

    [[ -z "$workflow_id" ]] && { _gha_error "Workflow ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh run list -R "$repo" --workflow "$workflow_id" --limit "$limit" \
        --json databaseId,displayTitle,status,conclusion,event,headBranch,createdAt,updatedAt 2>/dev/null
}

# Trigger a workflow dispatch event
# @param $1 - Repository (owner/repo)
# @param $2 - Workflow ID or filename
# @param $3 - Branch/ref (default: main)
# @param $@ - Additional inputs as key=value pairs
# @return 0 on success, 1 on failure
#
# Usage: gha_workflow_run "owner/repo" "deploy.yml"
# Usage: gha_workflow_run "owner/repo" "deploy.yml" "main" "environment=production"
gha_workflow_run() {
    local repo workflow_id ref
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    workflow_id="$2"
    ref="${3:-main}"
    shift 3 2>/dev/null || shift $#

    [[ -z "$workflow_id" ]] && { _gha_error "Workflow ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    local -a inputs=()
    for input in "$@"; do
        inputs+=(-f "$input")
    done

    gh workflow run "$workflow_id" -R "$repo" --ref "$ref" "${inputs[@]}" 2>/dev/null
}

# Enable a workflow
# @param $1 - Repository (owner/repo)
# @param $2 - Workflow ID or filename
# @return 0 on success
#
# Usage: gha_workflow_enable "owner/repo" "ci.yml"
gha_workflow_enable() {
    local repo workflow_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    workflow_id="$2"

    [[ -z "$workflow_id" ]] && { _gha_error "Workflow ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh workflow enable "$workflow_id" -R "$repo" 2>/dev/null
}

# Disable a workflow
# @param $1 - Repository (owner/repo)
# @param $2 - Workflow ID or filename
# @return 0 on success
#
# Usage: gha_workflow_disable "owner/repo" "ci.yml"
gha_workflow_disable() {
    local repo workflow_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    workflow_id="$2"

    [[ -z "$workflow_id" ]] && { _gha_error "Workflow ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh workflow disable "$workflow_id" -R "$repo" 2>/dev/null
}

# Get workflow YAML file content
# @param $1 - Repository (owner/repo)
# @param $2 - Workflow filename (e.g., ci.yml)
# @param $3 - Branch (default: main)
# @return Workflow YAML content
#
# Usage: gha_workflow_file "owner/repo" "ci.yml"
# Usage: gha_workflow_file "owner/repo" "ci.yml" "develop"
gha_workflow_file() {
    local repo workflow_name branch
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    workflow_name="$2"
    branch="${3:-main}"

    [[ -z "$workflow_name" ]] && { _gha_error "Workflow filename required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    # Ensure .github/workflows/ prefix
    local path="$workflow_name"
    [[ "$path" != .github/workflows/* ]] && path=".github/workflows/$workflow_name"

    gh api "repos/$repo/contents/$path?ref=$branch" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null
}

# Check if a workflow exists
# @param $1 - Repository (owner/repo)
# @param $2 - Workflow ID or filename
# @return 0 if exists, 1 otherwise
#
# Usage: gha_workflow_exists "owner/repo" "ci.yml" && echo "exists"
gha_workflow_exists() {
    local repo workflow_id
    repo=$(_gha_repo "$1") || return 1
    workflow_id="$2"

    [[ -z "$workflow_id" ]] && return 1
    _gha_check_gh || return 1

    gh workflow view "$workflow_id" -R "$repo" &>/dev/null
}

# Get workflow state (active/disabled)
# @param $1 - Repository (owner/repo)
# @param $2 - Workflow ID or filename
# @return "active" or "disabled_manually" or "disabled_inactivity"
#
# Usage: state=$(gha_workflow_state "owner/repo" "ci.yml")
gha_workflow_state() {
    local repo workflow_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    workflow_id="$2"

    [[ -z "$workflow_id" ]] && { _gha_error "Workflow ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh workflow view "$workflow_id" -R "$repo" --json state --jq '.state' 2>/dev/null
}

# List workflow files in .github/workflows/
# @param $1 - Repository (owner/repo)
# @return Newline-separated list of workflow filenames
#
# Usage: gha_workflow_files "owner/repo"
gha_workflow_files() {
    local repo
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh api "repos/$repo/contents/.github/workflows" --jq '.[].name' 2>/dev/null
}

# Get workflow by name (search)
# @param $1 - Repository (owner/repo)
# @param $2 - Workflow name (partial match)
# @return JSON workflow info
#
# Usage: gha_workflow_find "owner/repo" "CI"
gha_workflow_find() {
    local repo name
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    name="$2"

    [[ -z "$name" ]] && { _gha_error "Search name required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh workflow list -R "$repo" --json id,name,path,state 2>/dev/null | \
        jq --arg name "$name" '[.[] | select(.name | test($name; "i"))]' 2>/dev/null
}

# Get workflow dispatch inputs schema
# @param $1 - Repository (owner/repo)
# @param $2 - Workflow filename
# @return JSON inputs definition (parsed from YAML)
#
# Usage: gha_workflow_inputs "owner/repo" "deploy.yml"
gha_workflow_inputs() {
    local repo workflow_name content
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    workflow_name="$2"

    content=$(gha_workflow_file "$repo" "$workflow_name") || return 1

    # Extract workflow_dispatch inputs using grep/awk (basic YAML parsing)
    # This is a simplified extraction - full YAML parsing would require yq
    printf '%s\n' "$content" | \
        awk '/workflow_dispatch:/,/^[a-z]/' | \
        grep -A 100 'inputs:' | \
        grep -B 100 -m 1 '^[a-z]' 2>/dev/null || printf '%s\n' "$content"
}

# Count workflows in repository
# @param $1 - Repository (owner/repo)
# @return Number of workflows
#
# Usage: count=$(gha_workflow_count "owner/repo")
gha_workflow_count() {
    local repo
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh workflow list -R "$repo" --json id 2>/dev/null | jq 'length' 2>/dev/null
}

# =============================================================================
# SECTION 2: RUN MANAGEMENT (~12 functions)
# =============================================================================

# View detailed information about a run
# @param $1 - Repository (owner/repo)
# @param $2 - Run ID
# @return JSON run details
#
# Usage: gha_run_view "owner/repo" 12345678
gha_run_view() {
    local repo run_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    run_id="$2"

    [[ -z "$run_id" ]] && { _gha_error "Run ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh run view "$run_id" -R "$repo" --json databaseId,displayTitle,status,conclusion,event,headBranch,headSha,createdAt,updatedAt,url,workflowName 2>/dev/null
}

# Download run logs
# @param $1 - Repository (owner/repo)
# @param $2 - Run ID
# @param $3 - Output directory (default: current directory)
# @return 0 on success
#
# Usage: gha_run_logs "owner/repo" 12345678
# Usage: gha_run_logs "owner/repo" 12345678 "/tmp/logs"
gha_run_logs() {
    local repo run_id output_dir
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    run_id="$2"
    output_dir="${3:-.}"

    [[ -z "$run_id" ]] && { _gha_error "Run ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh run download "$run_id" -R "$repo" --dir "$output_dir" 2>/dev/null || \
        gh run view "$run_id" -R "$repo" --log 2>/dev/null
}

# Cancel a running workflow
# @param $1 - Repository (owner/repo)
# @param $2 - Run ID
# @return 0 on success
#
# Usage: gha_run_cancel "owner/repo" 12345678
gha_run_cancel() {
    local repo run_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    run_id="$2"

    [[ -z "$run_id" ]] && { _gha_error "Run ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh run cancel "$run_id" -R "$repo" 2>/dev/null
}

# Re-run entire workflow
# @param $1 - Repository (owner/repo)
# @param $2 - Run ID
# @return 0 on success
#
# Usage: gha_run_rerun "owner/repo" 12345678
gha_run_rerun() {
    local repo run_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    run_id="$2"

    [[ -z "$run_id" ]] && { _gha_error "Run ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh run rerun "$run_id" -R "$repo" 2>/dev/null
}

# Re-run only failed jobs
# @param $1 - Repository (owner/repo)
# @param $2 - Run ID
# @return 0 on success
#
# Usage: gha_run_rerun_failed "owner/repo" 12345678
gha_run_rerun_failed() {
    local repo run_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    run_id="$2"

    [[ -z "$run_id" ]] && { _gha_error "Run ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh run rerun "$run_id" -R "$repo" --failed 2>/dev/null
}

# Get run status
# @param $1 - Repository (owner/repo)
# @param $2 - Run ID
# @return "queued", "in_progress", "completed"
#
# Usage: status=$(gha_run_status "owner/repo" 12345678)
gha_run_status() {
    local repo run_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    run_id="$2"

    [[ -z "$run_id" ]] && { _gha_error "Run ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh run view "$run_id" -R "$repo" --json status --jq '.status' 2>/dev/null
}

# Get run conclusion
# @param $1 - Repository (owner/repo)
# @param $2 - Run ID
# @return "success", "failure", "cancelled", "skipped", "timed_out", "action_required"
#
# Usage: conclusion=$(gha_run_conclusion "owner/repo" 12345678)
gha_run_conclusion() {
    local repo run_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    run_id="$2"

    [[ -z "$run_id" ]] && { _gha_error "Run ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh run view "$run_id" -R "$repo" --json conclusion --jq '.conclusion' 2>/dev/null
}

# Wait for a run to complete (blocking)
# @param $1 - Repository (owner/repo)
# @param $2 - Run ID
# @param $3 - Timeout in seconds (default: 3600)
# @param $4 - Poll interval in seconds (default: 30)
# @return 0 on success, 1 on failure/timeout
#
# Usage: gha_run_wait "owner/repo" 12345678
# Usage: gha_run_wait "owner/repo" 12345678 1800 15
gha_run_wait() {
    local repo run_id timeout interval
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    run_id="$2"
    timeout="${3:-3600}"
    interval="${4:-30}"

    [[ -z "$run_id" ]] && { _gha_error "Run ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    local elapsed=0
    local status conclusion

    while (( elapsed < timeout )); do
        status=$(gha_run_status "$repo" "$run_id")

        if [[ "$status" == "completed" ]]; then
            conclusion=$(gha_run_conclusion "$repo" "$run_id")
            if [[ "$conclusion" == "success" ]]; then
                return 0
            else
                return 1
            fi
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    _gha_error "Timeout waiting for run $run_id"
    return 1
}

# List jobs in a run
# @param $1 - Repository (owner/repo)
# @param $2 - Run ID
# @return JSON array of jobs
#
# Usage: gha_run_jobs "owner/repo" 12345678
gha_run_jobs() {
    local repo run_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    run_id="$2"

    [[ -z "$run_id" ]] && { _gha_error "Run ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh run view "$run_id" -R "$repo" --json jobs 2>/dev/null
}

# List artifacts from a run
# @param $1 - Repository (owner/repo)
# @param $2 - Run ID
# @return JSON array of artifacts
#
# Usage: gha_run_artifacts "owner/repo" 12345678
gha_run_artifacts() {
    local repo run_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    run_id="$2"

    [[ -z "$run_id" ]] && { _gha_error "Run ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh api "repos/$repo/actions/runs/$run_id/artifacts" --jq '.artifacts' 2>/dev/null
}

# Get latest run for a workflow
# @param $1 - Repository (owner/repo)
# @param $2 - Workflow ID or filename
# @return JSON run details
#
# Usage: gha_run_latest "owner/repo" "ci.yml"
gha_run_latest() {
    local repo workflow_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    workflow_id="$2"

    [[ -z "$workflow_id" ]] && { _gha_error "Workflow ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh run list -R "$repo" --workflow "$workflow_id" --limit 1 \
        --json databaseId,displayTitle,status,conclusion,event,headBranch,createdAt 2>/dev/null | \
        jq '.[0]' 2>/dev/null
}

# List pending/running runs
# @param $1 - Repository (owner/repo)
# @param $2 - Limit (default: 20)
# @return JSON array of in-progress runs
#
# Usage: gha_run_pending "owner/repo"
gha_run_pending() {
    local repo limit
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    limit="${2:-20}"

    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh run list -R "$repo" --status in_progress --limit "$limit" \
        --json databaseId,displayTitle,status,workflowName,headBranch,createdAt 2>/dev/null
}

# =============================================================================
# SECTION 3: ARTIFACT MANAGEMENT (~6 functions)
# =============================================================================

# List all artifacts in a repository
# @param $1 - Repository (owner/repo)
# @param $2 - Limit (default: 30)
# @return JSON array of artifacts
#
# Usage: gha_artifact_list "owner/repo"
gha_artifact_list() {
    local repo limit
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    limit="${2:-30}"

    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh api "repos/$repo/actions/artifacts?per_page=$limit" --jq '.artifacts' 2>/dev/null
}

# Download an artifact
# @param $1 - Repository (owner/repo)
# @param $2 - Artifact ID or name
# @param $3 - Output directory (default: current)
# @return 0 on success
#
# Usage: gha_artifact_download "owner/repo" 12345678
# Usage: gha_artifact_download "owner/repo" "build-output" "/tmp/artifacts"
gha_artifact_download() {
    local repo artifact_id output_dir
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    artifact_id="$2"
    output_dir="${3:-.}"

    [[ -z "$artifact_id" ]] && { _gha_error "Artifact ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    # If numeric, it's an ID; otherwise it's a name
    if [[ "$artifact_id" =~ ^[0-9]+$ ]]; then
        local download_url
        download_url=$(gh api "repos/$repo/actions/artifacts/$artifact_id" --jq '.archive_download_url' 2>/dev/null)
        [[ -z "$download_url" ]] && { _gha_error "Artifact not found"; return 1; }
        gh api "$download_url" > "$output_dir/artifact-$artifact_id.zip" 2>/dev/null
    else
        # Find by name in recent runs
        gh run download -R "$repo" -n "$artifact_id" --dir "$output_dir" 2>/dev/null
    fi
}

# Delete an artifact
# @param $1 - Repository (owner/repo)
# @param $2 - Artifact ID
# @return 0 on success
#
# Usage: gha_artifact_delete "owner/repo" 12345678
gha_artifact_delete() {
    local repo artifact_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    artifact_id="$2"

    [[ -z "$artifact_id" ]] && { _gha_error "Artifact ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh api -X DELETE "repos/$repo/actions/artifacts/$artifact_id" 2>/dev/null
}

# Get artifact size in bytes
# @param $1 - Repository (owner/repo)
# @param $2 - Artifact ID
# @return Size in bytes
#
# Usage: size=$(gha_artifact_size "owner/repo" 12345678)
gha_artifact_size() {
    local repo artifact_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    artifact_id="$2"

    [[ -z "$artifact_id" ]] && { _gha_error "Artifact ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh api "repos/$repo/actions/artifacts/$artifact_id" --jq '.size_in_bytes' 2>/dev/null
}

# Check if artifact is expired
# @param $1 - Repository (owner/repo)
# @param $2 - Artifact ID
# @return 0 if expired, 1 if still valid
#
# Usage: gha_artifact_expired "owner/repo" 12345678 && echo "expired"
gha_artifact_expired() {
    local repo artifact_id
    repo=$(_gha_repo "$1") || return 1
    artifact_id="$2"

    [[ -z "$artifact_id" ]] && return 1
    _gha_check_gh || return 1

    local expired
    expired=$(gh api "repos/$repo/actions/artifacts/$artifact_id" --jq '.expired' 2>/dev/null)
    [[ "$expired" == "true" ]]
}

# Get artifact info as JSON
# @param $1 - Repository (owner/repo)
# @param $2 - Artifact ID
# @return JSON artifact details
#
# Usage: gha_artifact_info "owner/repo" 12345678
gha_artifact_info() {
    local repo artifact_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    artifact_id="$2"

    [[ -z "$artifact_id" ]] && { _gha_error "Artifact ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh api "repos/$repo/actions/artifacts/$artifact_id" 2>/dev/null
}

# =============================================================================
# SECTION 4: SECRETS MANAGEMENT (~8 functions)
# =============================================================================

# List repository secrets (names only, values are not retrievable)
# @param $1 - Repository (owner/repo)
# @return JSON array of secret names
#
# Usage: gha_secret_list "owner/repo"
gha_secret_list() {
    local repo
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh secret list -R "$repo" --json name,updatedAt 2>/dev/null
}

# Set a repository secret
# @param $1 - Repository (owner/repo)
# @param $2 - Secret name
# @param $3 - Secret value
# @return 0 on success
#
# Usage: gha_secret_set "owner/repo" "MY_SECRET" "secret_value"
gha_secret_set() {
    local repo name value
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    name="$2"
    value="$3"

    [[ -z "$name" ]] && { _gha_error "Secret name required"; return 1; }
    [[ -z "$value" ]] && { _gha_error "Secret value required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    printf '%s' "$value" | gh secret set "$name" -R "$repo" 2>/dev/null
}

# Delete a repository secret
# @param $1 - Repository (owner/repo)
# @param $2 - Secret name
# @return 0 on success
#
# Usage: gha_secret_delete "owner/repo" "MY_SECRET"
gha_secret_delete() {
    local repo name
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    name="$2"

    [[ -z "$name" ]] && { _gha_error "Secret name required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh secret delete "$name" -R "$repo" 2>/dev/null
}

# List organization secrets
# @param $1 - Organization name
# @return JSON array of secret names
#
# Usage: gha_secret_org_list "my-org"
gha_secret_org_list() {
    local org="$1"
    [[ -z "$org" ]] && { _gha_error "Organization name required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh secret list --org "$org" --json name,updatedAt,visibility 2>/dev/null
}

# Set an organization secret
# @param $1 - Organization name
# @param $2 - Secret name
# @param $3 - Secret value
# @param $4 - Visibility: all, private, selected (default: private)
# @return 0 on success
#
# Usage: gha_secret_org_set "my-org" "ORG_SECRET" "value"
# Usage: gha_secret_org_set "my-org" "ORG_SECRET" "value" "all"
gha_secret_org_set() {
    local org name value visibility
    org="$1"
    name="$2"
    value="$3"
    visibility="${4:-private}"

    [[ -z "$org" ]] && { _gha_error "Organization name required"; return 1; }
    [[ -z "$name" ]] && { _gha_error "Secret name required"; return 1; }
    [[ -z "$value" ]] && { _gha_error "Secret value required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    printf '%s' "$value" | gh secret set "$name" --org "$org" --visibility "$visibility" 2>/dev/null
}

# List environment secrets
# @param $1 - Repository (owner/repo)
# @param $2 - Environment name
# @return JSON array of secret names
#
# Usage: gha_secret_env_list "owner/repo" "production"
gha_secret_env_list() {
    local repo env_name
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    env_name="$2"

    [[ -z "$env_name" ]] && { _gha_error "Environment name required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh secret list -R "$repo" --env "$env_name" --json name,updatedAt 2>/dev/null
}

# Set an environment secret
# @param $1 - Repository (owner/repo)
# @param $2 - Environment name
# @param $3 - Secret name
# @param $4 - Secret value
# @return 0 on success
#
# Usage: gha_secret_env_set "owner/repo" "production" "DEPLOY_KEY" "value"
gha_secret_env_set() {
    local repo env_name name value
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    env_name="$2"
    name="$3"
    value="$4"

    [[ -z "$env_name" ]] && { _gha_error "Environment name required"; return 1; }
    [[ -z "$name" ]] && { _gha_error "Secret name required"; return 1; }
    [[ -z "$value" ]] && { _gha_error "Secret value required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    printf '%s' "$value" | gh secret set "$name" -R "$repo" --env "$env_name" 2>/dev/null
}

# Check if a secret exists
# @param $1 - Repository (owner/repo)
# @param $2 - Secret name
# @return 0 if exists, 1 otherwise
#
# Usage: gha_secret_exists "owner/repo" "MY_SECRET" && echo "exists"
gha_secret_exists() {
    local repo name
    repo=$(_gha_repo "$1") || return 1
    name="$2"

    [[ -z "$name" ]] && return 1
    _gha_check_gh || return 1

    gh secret list -R "$repo" --json name 2>/dev/null | jq -e --arg n "$name" '.[] | select(.name == $n)' &>/dev/null
}

# =============================================================================
# SECTION 5: VARIABLES (~6 functions)
# =============================================================================

# List repository variables
# @param $1 - Repository (owner/repo)
# @return JSON array of variables
#
# Usage: gha_variable_list "owner/repo"
gha_variable_list() {
    local repo
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh variable list -R "$repo" --json name,value,updatedAt 2>/dev/null
}

# Get a variable value
# @param $1 - Repository (owner/repo)
# @param $2 - Variable name
# @return Variable value
#
# Usage: value=$(gha_variable_get "owner/repo" "MY_VAR")
gha_variable_get() {
    local repo name
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    name="$2"

    [[ -z "$name" ]] && { _gha_error "Variable name required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh variable get "$name" -R "$repo" 2>/dev/null
}

# Set a repository variable
# @param $1 - Repository (owner/repo)
# @param $2 - Variable name
# @param $3 - Variable value
# @return 0 on success
#
# Usage: gha_variable_set "owner/repo" "MY_VAR" "my_value"
gha_variable_set() {
    local repo name value
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    name="$2"
    value="$3"

    [[ -z "$name" ]] && { _gha_error "Variable name required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh variable set "$name" -R "$repo" --body "$value" 2>/dev/null
}

# Delete a repository variable
# @param $1 - Repository (owner/repo)
# @param $2 - Variable name
# @return 0 on success
#
# Usage: gha_variable_delete "owner/repo" "MY_VAR"
gha_variable_delete() {
    local repo name
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    name="$2"

    [[ -z "$name" ]] && { _gha_error "Variable name required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh variable delete "$name" -R "$repo" 2>/dev/null
}

# List organization variables
# @param $1 - Organization name
# @return JSON array of variables
#
# Usage: gha_variable_org_list "my-org"
gha_variable_org_list() {
    local org="$1"
    [[ -z "$org" ]] && { _gha_error "Organization name required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh variable list --org "$org" --json name,value,visibility,updatedAt 2>/dev/null
}

# List environment variables
# @param $1 - Repository (owner/repo)
# @param $2 - Environment name
# @return JSON array of variables
#
# Usage: gha_variable_env_list "owner/repo" "production"
gha_variable_env_list() {
    local repo env_name
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    env_name="$2"

    [[ -z "$env_name" ]] && { _gha_error "Environment name required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh variable list -R "$repo" --env "$env_name" --json name,value,updatedAt 2>/dev/null
}

# =============================================================================
# SECTION 6: ENVIRONMENTS (~5 functions)
# =============================================================================

# List environments in a repository
# @param $1 - Repository (owner/repo)
# @return JSON array of environments
#
# Usage: gha_env_list "owner/repo"
gha_env_list() {
    local repo
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh api "repos/$repo/environments" --jq '.environments' 2>/dev/null
}

# Create an environment
# @param $1 - Repository (owner/repo)
# @param $2 - Environment name
# @return 0 on success
#
# Usage: gha_env_create "owner/repo" "staging"
gha_env_create() {
    local repo env_name
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    env_name="$2"

    [[ -z "$env_name" ]] && { _gha_error "Environment name required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh api -X PUT "repos/$repo/environments/$env_name" 2>/dev/null
}

# Delete an environment
# @param $1 - Repository (owner/repo)
# @param $2 - Environment name
# @return 0 on success
#
# Usage: gha_env_delete "owner/repo" "staging"
gha_env_delete() {
    local repo env_name
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    env_name="$2"

    [[ -z "$env_name" ]] && { _gha_error "Environment name required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh api -X DELETE "repos/$repo/environments/$env_name" 2>/dev/null
}

# Get environment protection rules
# @param $1 - Repository (owner/repo)
# @param $2 - Environment name
# @return JSON protection rules
#
# Usage: gha_env_protection_rules "owner/repo" "production"
gha_env_protection_rules() {
    local repo env_name
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    env_name="$2"

    [[ -z "$env_name" ]] && { _gha_error "Environment name required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh api "repos/$repo/environments/$env_name" --jq '.protection_rules' 2>/dev/null
}

# Get environment wait timer setting
# @param $1 - Repository (owner/repo)
# @param $2 - Environment name
# @return Wait timer in minutes (0 if none)
#
# Usage: timer=$(gha_env_wait_timer "owner/repo" "production")
gha_env_wait_timer() {
    local repo env_name
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    env_name="$2"

    [[ -z "$env_name" ]] && { _gha_error "Environment name required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh api "repos/$repo/environments/$env_name" \
        --jq '.protection_rules[] | select(.type == "wait_timer") | .wait_timer // 0' 2>/dev/null || printf '0'
}

# =============================================================================
# SECTION 7: YAML GENERATION HELPERS (~10 functions)
# =============================================================================

# Generate workflow skeleton YAML
# @param $1 - Workflow name
# @param $2 - Trigger events (default: "push,pull_request")
# @return YAML content
#
# Usage: gha_yaml_workflow "CI"
# Usage: gha_yaml_workflow "Deploy" "workflow_dispatch"
gha_yaml_workflow() {
    local name="${1:-CI}"
    local triggers="${2:-push,pull_request}"

    cat << EOF
name: $name

on:
EOF
    # Parse comma-separated triggers
    IFS=',' read -ra events <<< "$triggers"
    for event in "${events[@]}"; do
        event=$(printf '%s' "$event" | tr -d ' ')
        case "$event" in
            push|pull_request)
                printf '  %s:\n    branches: [main]\n' "$event"
                ;;
            workflow_dispatch)
                printf '  %s:\n' "$event"
                ;;
            schedule)
                printf '  %s:\n    - cron: "0 0 * * *"\n' "$event"
                ;;
            *)
                printf '  %s:\n' "$event"
                ;;
        esac
    done

    printf '\njobs:\n'
}

# Generate job block YAML
# @param $1 - Job name
# @param $2 - Runs-on (default: ubuntu-latest)
# @return YAML content
#
# Usage: gha_yaml_job "build"
# Usage: gha_yaml_job "build" "ubuntu-22.04"
gha_yaml_job() {
    local name="${1:-build}"
    local runs_on="${2:-ubuntu-latest}"

    cat << EOF
  $name:
    runs-on: $runs_on
    steps:
EOF
}

# Generate step block YAML
# @param $1 - Step name
# @param $2 - Run command
# @return YAML content
#
# Usage: gha_yaml_step "Run tests" "npm test"
gha_yaml_step() {
    local name="$1"
    local run_cmd="$2"

    [[ -z "$name" ]] && { _gha_error "Step name required"; return 1; }

    if [[ -n "$run_cmd" ]]; then
        cat << EOF
      - name: $name
        run: $run_cmd
EOF
    else
        cat << EOF
      - name: $name
EOF
    fi
}

# Generate uses action YAML
# @param $1 - Action reference (e.g., actions/checkout@v4)
# @param $2 - With arguments as JSON or key=value pairs
# @return YAML content
#
# Usage: gha_yaml_uses "actions/checkout@v4"
# Usage: gha_yaml_uses "actions/setup-node@v4" "node-version=20"
gha_yaml_uses() {
    local action="$1"
    shift
    local -a with_args=("$@")

    [[ -z "$action" ]] && { _gha_error "Action reference required"; return 1; }

    printf '      - uses: %s\n' "$action"

    if [[ ${#with_args[@]} -gt 0 ]]; then
        printf '        with:\n'
        for arg in "${with_args[@]}"; do
            local key="${arg%%=*}"
            local val="${arg#*=}"
            printf '          %s: %s\n' "$key" "$val"
        done
    fi
}

# Generate checkout step YAML
# @param $1 - Fetch depth (default: 1)
# @return YAML content
#
# Usage: gha_yaml_checkout
# Usage: gha_yaml_checkout 0  # Full history
gha_yaml_checkout() {
    local fetch_depth="${1:-1}"

    cat << EOF
      - uses: actions/checkout@v4
        with:
          fetch-depth: $fetch_depth
EOF
}

# Generate setup-node step YAML
# @param $1 - Node version (default: 20)
# @param $2 - Package manager (npm, yarn, pnpm, bun)
# @return YAML content
#
# Usage: gha_yaml_setup_node
# Usage: gha_yaml_setup_node 18 "pnpm"
gha_yaml_setup_node() {
    local version="${1:-20}"
    local pm="${2:-npm}"

    cat << EOF
      - uses: actions/setup-node@v4
        with:
          node-version: $version
          cache: $pm
EOF
}

# Generate setup-python step YAML
# @param $1 - Python version (default: 3.12)
# @return YAML content
#
# Usage: gha_yaml_setup_python
# Usage: gha_yaml_setup_python 3.11
gha_yaml_setup_python() {
    local version="${1:-3.12}"

    cat << EOF
      - uses: actions/setup-python@v5
        with:
          python-version: $version
          cache: pip
EOF
}

# Generate cache step YAML
# @param $1 - Path to cache
# @param $2 - Cache key
# @param $3 - Restore keys (optional)
# @return YAML content
#
# Usage: gha_yaml_cache "~/.npm" "npm-\${{ hashFiles('package-lock.json') }}"
gha_yaml_cache() {
    local path="$1"
    local key="$2"
    local restore_keys="${3:-}"

    [[ -z "$path" || -z "$key" ]] && { _gha_error "Path and key required"; return 1; }

    cat << EOF
      - uses: actions/cache@v4
        with:
          path: $path
          key: $key
EOF
    [[ -n "$restore_keys" ]] && printf '          restore-keys: %s\n' "$restore_keys"
}

# Generate upload-artifact step YAML
# @param $1 - Artifact name
# @param $2 - Path
# @param $3 - Retention days (default: 30)
# @return YAML content
#
# Usage: gha_yaml_upload_artifact "build-output" "dist/"
gha_yaml_upload_artifact() {
    local name="$1"
    local path="$2"
    local retention="${3:-30}"

    [[ -z "$name" || -z "$path" ]] && { _gha_error "Name and path required"; return 1; }

    cat << EOF
      - uses: actions/upload-artifact@v4
        with:
          name: $name
          path: $path
          retention-days: $retention
EOF
}

# Generate matrix strategy YAML
# @param $1 - Matrix key (e.g., "node-version")
# @param $@ - Matrix values
# @return YAML content
#
# Usage: gha_yaml_matrix "node-version" 18 20 22
# Usage: gha_yaml_matrix "os" "ubuntu-latest" "macos-latest" "windows-latest"
gha_yaml_matrix() {
    local key="$1"
    shift
    local -a values=("$@")

    [[ -z "$key" ]] && { _gha_error "Matrix key required"; return 1; }
    [[ ${#values[@]} -eq 0 ]] && { _gha_error "Matrix values required"; return 1; }

    printf '    strategy:\n'
    printf '      matrix:\n'
    printf '        %s: [%s]\n' "$key" "$(IFS=,; printf '%s' "${values[*]}")"
}

# =============================================================================
# SECTION 8: CI STATUS FOR AI AGENTS (~8 functions)
# =============================================================================

# Get status badge URL for a workflow
# @param $1 - Repository (owner/repo)
# @param $2 - Workflow filename
# @param $3 - Branch (default: main)
# @return Badge URL
#
# Usage: gha_status_badge "owner/repo" "ci.yml"
gha_status_badge() {
    local repo workflow_name branch
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    workflow_name="$2"
    branch="${3:-main}"

    [[ -z "$workflow_name" ]] && { _gha_error "Workflow filename required"; return 1; }

    printf 'https://github.com/%s/actions/workflows/%s/badge.svg?branch=%s\n' \
        "$repo" "$workflow_name" "$branch"
}

# Check if default branch is green (all workflows passing)
# @param $1 - Repository (owner/repo)
# @return 0 if passing, 1 if failing
#
# Usage: gha_is_passing "owner/repo" && echo "CI is green"
gha_is_passing() {
    local repo
    repo=$(_gha_repo "$1") || return 1
    _gha_check_gh || return 1

    local conclusion
    conclusion=$(gh run list -R "$repo" --limit 1 --json conclusion --jq '.[0].conclusion' 2>/dev/null)
    [[ "$conclusion" == "success" ]]
}

# Get last successful run for a workflow
# @param $1 - Repository (owner/repo)
# @param $2 - Workflow ID or filename
# @return JSON run details
#
# Usage: gha_last_success "owner/repo" "ci.yml"
gha_last_success() {
    local repo workflow_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    workflow_id="$2"

    [[ -z "$workflow_id" ]] && { _gha_error "Workflow ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh run list -R "$repo" --workflow "$workflow_id" --status completed \
        --json databaseId,displayTitle,createdAt,headBranch,headSha 2>/dev/null | \
        jq '[.[] | select(.conclusion == "success")][0]' 2>/dev/null
}

# Calculate failure rate for a workflow
# @param $1 - Repository (owner/repo)
# @param $2 - Workflow ID or filename
# @param $3 - Number of runs to analyze (default: 100)
# @return Failure rate as percentage (e.g., "15.5")
#
# Usage: rate=$(gha_failure_rate "owner/repo" "ci.yml")
# Usage: rate=$(gha_failure_rate "owner/repo" "ci.yml" 50)
gha_failure_rate() {
    local repo workflow_id count
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    workflow_id="$2"
    count="${3:-100}"

    [[ -z "$workflow_id" ]] && { _gha_error "Workflow ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    local runs total failures rate
    runs=$(gh run list -R "$repo" --workflow "$workflow_id" --limit "$count" \
        --json conclusion 2>/dev/null)

    total=$(printf '%s' "$runs" | jq 'length' 2>/dev/null)
    failures=$(printf '%s' "$runs" | jq '[.[] | select(.conclusion == "failure")] | length' 2>/dev/null)

    if [[ "$total" -gt 0 ]]; then
        # Calculate percentage with one decimal place
        rate=$(awk "BEGIN { printf \"%.1f\", ($failures / $total) * 100 }")
        printf '%s\n' "$rate"
    else
        printf '0.0\n'
    fi
}

# Get average run duration for a workflow
# @param $1 - Repository (owner/repo)
# @param $2 - Workflow ID or filename
# @param $3 - Number of runs to analyze (default: 20)
# @return Average duration in seconds
#
# Usage: duration=$(gha_avg_duration "owner/repo" "ci.yml")
gha_avg_duration() {
    local repo workflow_id count
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    workflow_id="$2"
    count="${3:-20}"

    [[ -z "$workflow_id" ]] && { _gha_error "Workflow ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    # Get completed runs with timing
    gh run list -R "$repo" --workflow "$workflow_id" --status completed --limit "$count" \
        --json createdAt,updatedAt 2>/dev/null | \
        jq 'if length > 0 then
            [.[] |
                ((.updatedAt | fromdateiso8601) - (.createdAt | fromdateiso8601))
            ] | add / length | floor
        else 0 end' 2>/dev/null
}

# Get full CI context for AI agents
# @param $1 - Repository (owner/repo)
# @return JSON with comprehensive CI status
#
# Usage: context=$(gha_context_json "owner/repo")
gha_context_json() {
    local repo
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    local workflows latest_run is_passing pending_count

    workflows=$(gh workflow list -R "$repo" --json id,name,state 2>/dev/null)
    latest_run=$(gh run list -R "$repo" --limit 1 \
        --json databaseId,displayTitle,status,conclusion,workflowName,headBranch,createdAt 2>/dev/null | \
        jq '.[0]' 2>/dev/null)

    if gha_is_passing "$repo"; then
        is_passing="true"
    else
        is_passing="false"
    fi

    pending_count=$(gh run list -R "$repo" --status in_progress --json databaseId 2>/dev/null | \
        jq 'length' 2>/dev/null)

    jq -n \
        --argjson workflows "$workflows" \
        --argjson latest "$latest_run" \
        --argjson is_passing "$is_passing" \
        --argjson pending "$pending_count" \
        '{
            "repository": $repo,
            "is_passing": $is_passing,
            "pending_runs": $pending,
            "workflows": $workflows,
            "latest_run": $latest
        }' --arg repo "$repo" 2>/dev/null
}

# Get required status checks for a branch
# @param $1 - Repository (owner/repo)
# @param $2 - Branch (default: main)
# @return JSON array of required checks
#
# Usage: gha_required_checks "owner/repo"
# Usage: gha_required_checks "owner/repo" "develop"
gha_required_checks() {
    local repo branch
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    branch="${2:-main}"

    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh api "repos/$repo/branches/$branch/protection/required_status_checks" \
        --jq '.contexts // .checks // []' 2>/dev/null || printf '[]\n'
}

# Get check suites for a specific ref
# @param $1 - Repository (owner/repo)
# @param $2 - Git ref (commit SHA, branch, or tag)
# @return JSON array of check suites
#
# Usage: gha_check_suites "owner/repo" "abc1234"
# Usage: gha_check_suites "owner/repo" "main"
gha_check_suites() {
    local repo ref
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    ref="$2"

    [[ -z "$ref" ]] && { _gha_error "Git ref required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh api "repos/$repo/commits/$ref/check-suites" --jq '.check_suites' 2>/dev/null
}

# =============================================================================
# SECTION 9: SELF-HOSTED RUNNERS (~5 functions)
# =============================================================================

# List self-hosted runners for a repository
# @param $1 - Repository (owner/repo)
# @return JSON array of runners
#
# Usage: gha_runner_list "owner/repo"
gha_runner_list() {
    local repo
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh api "repos/$repo/actions/runners" --jq '.runners' 2>/dev/null
}

# List self-hosted runners for an organization
# @param $1 - Organization name
# @return JSON array of runners
#
# Usage: gha_runner_org_list "my-org"
gha_runner_org_list() {
    local org="$1"
    [[ -z "$org" ]] && { _gha_error "Organization name required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh api "orgs/$org/actions/runners" --jq '.runners' 2>/dev/null
}

# Get runner status
# @param $1 - Repository (owner/repo)
# @param $2 - Runner ID
# @return "online" or "offline"
#
# Usage: status=$(gha_runner_status "owner/repo" 12345)
gha_runner_status() {
    local repo runner_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    runner_id="$2"

    [[ -z "$runner_id" ]] && { _gha_error "Runner ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh api "repos/$repo/actions/runners/$runner_id" --jq '.status' 2>/dev/null
}

# Get runner labels
# @param $1 - Repository (owner/repo)
# @param $2 - Runner ID
# @return JSON array of labels
#
# Usage: gha_runner_labels "owner/repo" 12345
gha_runner_labels() {
    local repo runner_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    runner_id="$2"

    [[ -z "$runner_id" ]] && { _gha_error "Runner ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh api "repos/$repo/actions/runners/$runner_id" --jq '.labels[].name' 2>/dev/null
}

# Remove a self-hosted runner
# @param $1 - Repository (owner/repo)
# @param $2 - Runner ID
# @return 0 on success
#
# Usage: gha_runner_remove "owner/repo" 12345
gha_runner_remove() {
    local repo runner_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    runner_id="$2"

    [[ -z "$runner_id" ]] && { _gha_error "Runner ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh api -X DELETE "repos/$repo/actions/runners/$runner_id" 2>/dev/null
}

# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

# Get quick CI status summary (human-readable)
# @param $1 - Repository (owner/repo)
# @return Formatted status string
#
# Usage: gha_quick_status "owner/repo"
gha_quick_status() {
    local repo
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    local latest status conclusion workflow

    latest=$(gh run list -R "$repo" --limit 1 \
        --json status,conclusion,workflowName,displayTitle 2>/dev/null | jq '.[0]' 2>/dev/null)

    status=$(printf '%s' "$latest" | jq -r '.status' 2>/dev/null)
    conclusion=$(printf '%s' "$latest" | jq -r '.conclusion // "pending"' 2>/dev/null)
    workflow=$(printf '%s' "$latest" | jq -r '.workflowName' 2>/dev/null)

    case "$status" in
        completed)
            case "$conclusion" in
                success)   printf '[PASS] %s\n' "$workflow" ;;
                failure)   printf '[FAIL] %s\n' "$workflow" ;;
                cancelled) printf '[CANCELLED] %s\n' "$workflow" ;;
                *)         printf '[%s] %s\n' "$conclusion" "$workflow" ;;
            esac
            ;;
        in_progress)
            printf '[RUNNING] %s\n' "$workflow"
            ;;
        queued)
            printf '[QUEUED] %s\n' "$workflow"
            ;;
        *)
            printf '[%s] %s\n' "$status" "$workflow"
            ;;
    esac
}

# Watch a run until completion (with progress output)
# @param $1 - Repository (owner/repo)
# @param $2 - Run ID
# @return 0 on success, 1 on failure
#
# Usage: gha_run_watch "owner/repo" 12345678
gha_run_watch() {
    local repo run_id
    repo=$(_gha_repo "$1") || { _gha_error "Cannot determine repository"; return 1; }
    run_id="$2"

    [[ -z "$run_id" ]] && { _gha_error "Run ID required"; return 1; }
    _gha_check_gh || { _gha_error "gh CLI not installed"; return 1; }

    gh run watch "$run_id" -R "$repo" 2>/dev/null
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

_GHA_EXPORTS=(
    # Workflow Management
    gha_workflow_list
    gha_workflow_view
    gha_workflow_runs
    gha_workflow_run
    gha_workflow_enable
    gha_workflow_disable
    gha_workflow_file
    gha_workflow_exists
    gha_workflow_state
    gha_workflow_files
    gha_workflow_find
    gha_workflow_inputs
    gha_workflow_count

    # Run Management
    gha_run_view
    gha_run_logs
    gha_run_cancel
    gha_run_rerun
    gha_run_rerun_failed
    gha_run_status
    gha_run_conclusion
    gha_run_wait
    gha_run_jobs
    gha_run_artifacts
    gha_run_latest
    gha_run_pending

    # Artifact Management
    gha_artifact_list
    gha_artifact_download
    gha_artifact_delete
    gha_artifact_size
    gha_artifact_expired
    gha_artifact_info

    # Secrets Management
    gha_secret_list
    gha_secret_set
    gha_secret_delete
    gha_secret_org_list
    gha_secret_org_set
    gha_secret_env_list
    gha_secret_env_set
    gha_secret_exists

    # Variables
    gha_variable_list
    gha_variable_get
    gha_variable_set
    gha_variable_delete
    gha_variable_org_list
    gha_variable_env_list

    # Environments
    gha_env_list
    gha_env_create
    gha_env_delete
    gha_env_protection_rules
    gha_env_wait_timer

    # YAML Generation
    gha_yaml_workflow
    gha_yaml_job
    gha_yaml_step
    gha_yaml_uses
    gha_yaml_checkout
    gha_yaml_setup_node
    gha_yaml_setup_python
    gha_yaml_cache
    gha_yaml_upload_artifact
    gha_yaml_matrix

    # CI Status
    gha_status_badge
    gha_is_passing
    gha_last_success
    gha_failure_rate
    gha_avg_duration
    gha_context_json
    gha_required_checks
    gha_check_suites

    # Runners
    gha_runner_list
    gha_runner_org_list
    gha_runner_status
    gha_runner_labels
    gha_runner_remove

    # Convenience
    gha_quick_status
    gha_run_watch
)

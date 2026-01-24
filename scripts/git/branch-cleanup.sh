#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/scripts/git/branch-cleanup.sh - Git Branch Cleanup
# =============================================================================
# Description: Cleans up merged and stale git branches. Supports dry-run,
#              remote cleanup, age-based filtering, and branch protection.
# Version: 1.0.0
# Requires: Bash 4.0+, git
# =============================================================================

set -o pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Configuration
DRY_RUN=false
CLEAN_REMOTE=false
DAYS_OLD=30
PROTECTED_BRANCHES=("main" "master" "develop" "dev" "staging" "release")
CURRENT_BRANCH=""

usage() {
    cat <<EOF
Usage: branch-cleanup.sh [options]

Cleans up merged and stale git branches.

Options:
    --dry-run           Show what would be deleted without acting
    --remote            Also clean remote tracking branches
    --older-than <Nd>   Age threshold in days (default: 30d)
    --protect <branch>  Add branch to protected list (repeatable)
    -h, --help          Show this help
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)     DRY_RUN=true; shift ;;
            --remote)      CLEAN_REMOTE=true; shift ;;
            --older-than)
                DAYS_OLD="${2%d}"  # Strip trailing 'd' if present
                shift 2
                ;;
            --protect)
                PROTECTED_BRANCHES+=("$2")
                shift 2
                ;;
            -h|--help)     usage ;;
            *)             log_error "Unknown option: $1"; usage ;;
        esac
    done
}

is_protected() {
    local branch="$1"
    for p in "${PROTECTED_BRANCHES[@]}"; do
        [[ "$branch" == "$p" ]] && return 0
    done
    return 1
}

branch_age_days() {
    local branch="$1"
    local last_commit
    last_commit=$(git log -1 --format=%ct "$branch" 2>/dev/null) || return 1
    local now
    now=$(date +%s)
    echo $(( (now - last_commit) / 86400 ))
}

branch_last_info() {
    local branch="$1"
    git log -1 --format="%cr by %an: %s" "$branch" 2>/dev/null
}

delete_local() {
    local branch="$1"
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would delete local: $branch"
    else
        if git branch -d "$branch" 2>/dev/null; then
            log_info "Deleted local: $branch"
        else
            log_warn "Force-deleting: $branch (not fully merged)"
            git branch -D "$branch" 2>/dev/null
        fi
    fi
}

delete_remote() {
    local branch="$1"
    local remote="${branch%%/*}"
    local ref="${branch#*/}"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would delete remote: $remote/$ref"
    else
        if git push "$remote" --delete "$ref" 2>/dev/null; then
            log_info "Deleted remote: $remote/$ref"
        else
            log_error "Failed to delete remote: $remote/$ref"
        fi
    fi
}

main() {
    parse_args "$@"

    # Verify git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not a git repository"
        exit 1
    fi

    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    log_info "Current branch: $CURRENT_BRANCH"
    log_info "Protected: ${PROTECTED_BRANCHES[*]}"
    log_info "Age threshold: ${DAYS_OLD} days"

    [[ "$DRY_RUN" == true ]] && log_warn "DRY RUN MODE - no changes will be made"

    local deleted_count=0

    # --- Merged local branches ---
    log_info "Scanning merged local branches..."
    while IFS= read -r branch; do
        branch=$(echo "$branch" | sed 's/^[* ]*//' | xargs)
        [[ -z "$branch" ]] && continue
        [[ "$branch" == "$CURRENT_BRANCH" ]] && continue
        is_protected "$branch" && continue

        local age info
        age=$(branch_age_days "$branch")
        info=$(branch_last_info "$branch")
        echo "  - $branch (${age}d old) [$info]"
        delete_local "$branch"
        ((deleted_count++))
    done < <(git branch --merged "$CURRENT_BRANCH" 2>/dev/null | grep -v '^\*')

    # --- Stale local branches (not merged but old) ---
    log_info "Scanning stale local branches (>${DAYS_OLD} days, unmerged)..."
    while IFS= read -r branch; do
        branch="${branch//refs\/heads\//}"
        [[ "$branch" == "$CURRENT_BRANCH" ]] && continue
        is_protected "$branch" && continue

        local age
        age=$(branch_age_days "$branch")
        [[ -z "$age" ]] && continue
        [[ $age -lt $DAYS_OLD ]] && continue

        # Skip if already deleted as merged
        git rev-parse --verify "$branch" >/dev/null 2>&1 || continue

        local info
        info=$(branch_last_info "$branch")
        echo "  - $branch (${age}d old, unmerged) [$info]"

        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would force-delete stale: $branch"
        else
            read -rp "  Delete unmerged stale branch '$branch'? [y/N] " answer
            if [[ "${answer,,}" == "y" ]]; then
                git branch -D "$branch" 2>/dev/null
                log_info "Force-deleted: $branch"
                ((deleted_count++))
            fi
        fi
    done < <(git for-each-ref --format='%(refname:short)' refs/heads/)

    # --- Remote branches ---
    if [[ "$CLEAN_REMOTE" == true ]]; then
        log_info "Scanning remote branches..."
        git fetch --prune 2>/dev/null

        while IFS= read -r branch; do
            branch=$(echo "$branch" | xargs)
            [[ -z "$branch" ]] && continue
            [[ "$branch" == *"HEAD"* ]] && continue

            local short="${branch#origin/}"
            is_protected "$short" && continue

            local age
            age=$(branch_age_days "$branch")
            [[ -z "$age" ]] && continue
            [[ $age -lt $DAYS_OLD ]] && continue

            local info
            info=$(branch_last_info "$branch")
            echo "  - $branch (${age}d old) [$info]"
            delete_remote "$branch"
            ((deleted_count++))
        done < <(git branch -r --merged "$CURRENT_BRANCH" 2>/dev/null | grep -v "HEAD")
    fi

    echo ""
    if [[ $deleted_count -eq 0 ]]; then
        log_info "No branches to clean up."
    else
        log_info "Cleanup complete: $deleted_count branch(es) processed."
    fi
}

main "$@"

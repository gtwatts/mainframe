#!/usr/bin/env bash
# =============================================================================
# git-worktree-picker.sh - Interactive git worktree manager
# =============================================================================
# Description: Lists git worktrees, presents interactive selection, and
#              prints the path for cd (use: cd "$(./git-worktree-picker.sh)")
# Version:     1.0.0
# Requires:    git, fzf (optional)
# Usage:       ./git-worktree-picker.sh [--add <branch>]
# Make executable: chmod +x scripts/git/git-worktree-picker.sh
# =============================================================================
set -euo pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

usage() {
    echo "Usage: $(basename "$0") [--add <branch>]"
    echo "  Select a git worktree and print its path."
    echo "  Use with: cd \"\$($(basename "$0"))\""
    echo ""
    echo "  --add <branch>  Create new worktree for branch"
    exit "${1:-0}"
}

_pick() {
    if command -v fzf >/dev/null 2>&1; then
        fzf --height=15 --border --prompt="$1> " "${@:2}"
    else
        local lines=() i=1
        while IFS= read -r line; do lines+=("$line"); echo "  $((i++))) $line" >&2; done
        read -rp "Select [1-${#lines[@]}]: " n </dev/tty >&2
        echo "${lines[$((n-1))]}"
    fi
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

git rev-parse --git-dir >/dev/null 2>&1 || { log_error "Not a git repository."; exit 1; }

# Handle --add flag
if [[ "${1:-}" == "--add" ]]; then
    branch="${2:?Usage: --add <branch>}"
    base_dir=$(dirname "$(git rev-parse --show-toplevel)")
    worktree_path="$base_dir/$branch"
    git worktree add "$worktree_path" "$branch" 2>/dev/null \
        || git worktree add -b "$branch" "$worktree_path"
    log_info "Created worktree: $worktree_path" >&2
    echo "$worktree_path"
    exit 0
fi

# Parse worktree list into selectable lines
worktrees=$(git worktree list --porcelain \
    | awk '/^worktree /{path=$2} /^branch /{sub(/refs\/heads\//, "", $2); printf "%-50s %s\n", path, $2}')

[[ -z "$worktrees" ]] && { log_error "No worktrees found."; exit 1; }

selected=$(echo "$worktrees" | _pick "Worktree")
path=$(echo "$selected" | awk '{print $1}')

# Print path to stdout (for cd capture), info to stderr
log_info "Selected: $(ansi_green "$path")" >&2
echo "$path"

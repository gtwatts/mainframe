#!/usr/bin/env bash
# =============================================================================
# disk-cleanup.sh - Interactive disk space cleaner
# =============================================================================
# Description: Finds largest files under a path, presents multi-select,
#              confirms total size, and removes selected files.
# Version:     1.0.0
# Requires:    find, du, fzf (optional, falls back to numbered menu)
# Usage:       ./disk-cleanup.sh [path]
# Make executable: chmod +x scripts/device/disk-cleanup.sh
# =============================================================================
set -euo pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

usage() {
    echo "Usage: $(basename "$0") [path]"
    echo "  Find and interactively delete the largest files under [path]."
    echo "  Defaults to current directory if no path given."
    exit "${1:-0}"
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

target="${1:-.}"
[[ ! -d "$target" ]] && { log_error "Not a directory: $target"; exit 1; }

log_info "Scanning largest files under $(ansi_bold "$target")..."

# Find top 20 largest files with human-readable sizes
big_files=$(find "$target" -maxdepth 4 -type f -exec du -h {} + 2>/dev/null \
    | sort -rh | head -20)

[[ -z "$big_files" ]] && { log_info "No files found."; exit 0; }

if command -v fzf >/dev/null 2>&1; then
    selected=$(echo "$big_files" | fzf --multi --height=20 --border \
        --prompt="Select files to delete (TAB=multi)> " \
        --header="SIZE  PATH")
else
    local_lines=()
    i=1
    while IFS= read -r line; do
        local_lines+=("$line")
        echo "  $((i++))) $line" >&2
    done <<< "$big_files"
    read -rp "Select numbers (comma-separated): " nums </dev/tty
    selected=""
    IFS=',' read -ra picks <<< "$nums"
    for n in "${picks[@]}"; do
        n=$(echo "$n" | tr -d ' ')
        selected+="${local_lines[$((n-1))]}"$'\n'
    done
fi

[[ -z "$selected" ]] && { log_info "Nothing selected."; exit 0; }

# Calculate total size and confirm
total=$(echo "$selected" | awk '{print $1}' | paste -sd+ | tr -d '\n')
file_count=$(echo "$selected" | grep -c .)

echo ""
echo "$selected"
echo ""
read -rp "Delete $file_count file(s)? [y/N]: " confirm </dev/tty
[[ "$confirm" != [yY]* ]] && { log_info "Cancelled."; exit 0; }

echo "$selected" | awk '{print $2}' | while IFS= read -r f; do
    [[ -n "$f" ]] && rm -v "$f"
done

log_info "Cleanup complete."

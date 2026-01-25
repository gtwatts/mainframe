#!/usr/bin/env bash
# =============================================================================
# recent-editor.sh - Open recently modified files in $EDITOR
# Version: 1.0.0
# Requires: find, fzf (optional, falls back to select)
# Usage: ./recent-editor.sh [directory]
# chmod +x scripts/file/recent-editor.sh
# =============================================================================
set -euo pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

usage() {
    echo "Usage: $(basename "$0") [directory]"
    echo "  Browse files modified in the last 7 days and open in \$EDITOR."
    echo "  Default directory: ."
    exit 0
}

_pick() {
    if command -v fzf >/dev/null 2>&1; then
        fzf "$@"
    else
        local lines=() i=1
        while IFS= read -r line; do lines+=("$line"); echo "  $((i++))) $line" >&2; done
        read -rp "Select [1-${#lines[@]}]: " n >&2
        echo "${lines[$((n-1))]}"
    fi
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

dir="${1:-.}"
[[ -d "$dir" ]] || { log_error "Not a directory: $dir"; exit 1; }

FZF_PREVIEW=()
if command -v fzf >/dev/null 2>&1; then
    FZF_PREVIEW=(--preview "head -20 {}")
fi

selected=$(find "$dir" -type f -mtime -7 \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/__pycache__/*' \
    -printf '%T@ %p\n' \
    | sort -rn \
    | awk '{print $2}' \
    | _pick --prompt="Recent> " "${FZF_PREVIEW[@]}" || true)

[[ -z "$selected" ]] && { log_info "No file selected."; exit 0; }

${EDITOR:-vim} "$selected"

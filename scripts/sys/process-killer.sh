#!/usr/bin/env bash
# =============================================================================
# process-killer.sh - Interactive process killer (top memory consumers)
# Version: 1.0.0
# Requires: ps, fzf (optional, falls back to select)
# Usage: ./process-killer.sh [--force|-9]
# chmod +x scripts/sys/process-killer.sh
# =============================================================================
set -euo pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

usage() {
    echo "Usage: $(basename "$0") [--force|-9]"
    echo "  Select processes to kill from top 30 memory consumers."
    echo "  --force, -9  Use SIGKILL instead of SIGTERM"
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

SIG="-15"
[[ "${1:-}" == "--force" || "${1:-}" == "-9" ]] && SIG="-9"

selected=$(ps aux --sort=-%mem \
    | head -31 \
    | tail -30 \
    | _pick --multi --prompt="Kill> " || true)

[[ -z "$selected" ]] && { log_info "No processes selected."; exit 0; }

pids=$(echo "$selected" | awk '{print $2}')
count=$(echo "$pids" | wc -l)

echo "$selected"
read -rp "Kill $count process(es) with signal $SIG? [y/N]: " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { log_info "Aborted."; exit 0; }

echo "$pids" | xargs kill "$SIG" 2>/dev/null && log_info "Sent $SIG to $count process(es)."

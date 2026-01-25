#!/usr/bin/env bash
# =============================================================================
# port-kill.sh - Kill process by listening port
# =============================================================================
# Description: Lists listening TCP ports with process info, presents
#              interactive selection, and kills the selected process.
# Version:     1.0.0
# Requires:    ss (or netstat), fzf (optional)
# Usage:       ./port-kill.sh [--force]
# Make executable: chmod +x scripts/net/port-kill.sh
# =============================================================================
set -euo pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

usage() {
    echo "Usage: $(basename "$0") [--force]"
    echo "  Interactively kill a process listening on a TCP port."
    echo "  --force   Use SIGKILL (kill -9) instead of SIGTERM"
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

force=0
[[ "${1:-}" == "--force" ]] && { force=1; shift; }
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

# List listening TCP ports with process info
listeners=$(ss -tlnp 2>/dev/null \
    | awk 'NR>1 {
        port=$4; sub(/.*:/, "", port)
        proc=$7; gsub(/.*"/, "", proc); gsub(/".*/, "", proc)
        pid=$7; match(pid, /pid=[0-9]+/); pid=substr(pid, RSTART+4, RLENGTH-4)
        if(pid!="") printf ":%s  pid=%-7s %s\n", port, pid, proc
    }' | sort -t: -k2 -n | uniq)

[[ -z "$listeners" ]] && { log_info "No listening TCP ports found."; exit 0; }

selected=$(echo "$listeners" | _pick "Kill port")
pid=$(echo "$selected" | grep -oP 'pid=\K[0-9]+')

[[ -z "$pid" ]] && { log_error "Could not extract PID."; exit 1; }

signal="TERM"
[[ "$force" -eq 1 ]] && signal="KILL"

log_info "Killing PID $(ansi_bold "$pid") (SIG$signal): $selected"
read -rp "Confirm? [y/N]: " confirm </dev/tty
[[ "$confirm" != [yY]* ]] && { log_info "Cancelled."; exit 0; }

kill -"$signal" "$pid"
log_info "Sent SIG$signal to PID $pid"

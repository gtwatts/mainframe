#!/usr/bin/env bash
# =============================================================================
# wifi-connect.sh - Interactive WiFi connector via nmcli
# =============================================================================
# Description: Scans available WiFi networks, presents interactive selection
#              with signal strength, and connects via NetworkManager.
# Version:     1.0.0
# Requires:    nmcli (NetworkManager), fzf (optional)
# Usage:       ./wifi-connect.sh
# Make executable: chmod +x scripts/net/wifi-connect.sh
# =============================================================================
set -euo pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

usage() {
    echo "Usage: $(basename "$0")"
    echo "  Scan and interactively connect to a WiFi network."
    echo "  Requires NetworkManager (nmcli)."
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

command -v nmcli >/dev/null 2>&1 || { log_error "nmcli not found. Install NetworkManager."; exit 1; }

log_info "Scanning WiFi networks..."
nmcli dev wifi rescan 2>/dev/null || true
sleep 1

# Format: SSID | SIGNAL% | SECURITY
networks=$(nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list \
    | awk -F: '$1!="" {printf "%-32s %3s%%  %s\n", $1, $2, $3}' \
    | sort -t'%' -k1 -rn | uniq)

[[ -z "$networks" ]] && { log_error "No WiFi networks found."; exit 1; }

selected=$(echo "$networks" | _pick "Network")
ssid=$(echo "$selected" | sed 's/\s\+[0-9]\+%.*$//' | sed 's/\s*$//')
security=$(echo "$selected" | grep -oP '(WPA|WEP|OWE|SAE)\S*' || true)

log_info "Connecting to: $(ansi_green "$ssid")"

if [[ -n "$security" ]]; then
    read -rsp "Password: " pass </dev/tty
    echo ""
    nmcli dev wifi connect "$ssid" password "$pass"
else
    nmcli dev wifi connect "$ssid"
fi

log_info "Connected to $(ansi_green "$ssid")"

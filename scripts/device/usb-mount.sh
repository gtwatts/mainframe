#!/usr/bin/env bash
# =============================================================================
# usb-mount.sh - Interactive USB partition mount
# =============================================================================
# Description: Lists unmounted partitions, presents interactive selection,
#              and mounts the chosen device to a specified mount point.
# Version:     1.0.0
# Requires:    lsblk, sudo, fzf (optional, falls back to numbered menu)
# Usage:       ./usb-mount.sh
# Make executable: chmod +x scripts/device/usb-mount.sh
# =============================================================================
set -euo pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

usage() {
    echo "Usage: $(basename "$0")"
    echo "  Interactively mount an unmounted USB partition."
    echo "  Requires root privileges for mount operation."
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

# List unmounted partitions (type=part, no mountpoint, removable=1)
devices=$(lsblk -lp -o NAME,SIZE,FSTYPE,MOUNTPOINT,RM \
    | awk 'NR>1 && $4=="" && $5=="1" && $3!="" {print $1, $2, $3}')

[[ -z "$devices" ]] && { log_error "No unmounted removable partitions found."; exit 1; }

log_info "Unmounted removable partitions:"
selected=$(echo "$devices" | _pick "Device")
device=$(echo "$selected" | awk '{print $1}')

# Suggest mount point based on device label or basename
label=$(lsblk -no LABEL "$device" 2>/dev/null | tr -d ' ')
default_mount="/mnt/${label:-$(basename "$device")}"

read -rp "Mount point [$default_mount]: " mountpoint </dev/tty
mountpoint="${mountpoint:-$default_mount}"

sudo mkdir -p "$mountpoint"
sudo mount "$device" "$mountpoint"

log_info "Mounted $(ansi_green "$device") at $(ansi_green "$mountpoint")"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT "$device"

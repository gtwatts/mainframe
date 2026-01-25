#!/usr/bin/env bash
# =============================================================================
# service-manager.sh - Interactive systemd service manager
# Version: 1.0.0
# Requires: systemctl, fzf (optional, falls back to select)
# Usage: ./service-manager.sh
# chmod +x scripts/sys/service-manager.sh
# =============================================================================
set -euo pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

usage() {
    echo "Usage: $(basename "$0")"
    echo "  Interactive systemd service manager."
    echo "  Select a running service, then choose an action."
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

while true; do
    svc=$(systemctl list-units --type=service --state=running --no-pager --plain \
        | awk 'NF{print $1}' \
        | grep '\.service$' \
        | _pick --prompt="Service> " || true)

    [[ -z "$svc" ]] && break

    echo ""
    systemctl status "$svc" --no-pager 2>/dev/null | head -15
    echo ""
    read -rp "[s]tart [S]top [r]estart [l]ogs [q]uit: " action

    case "$action" in
        s) sudo systemctl start "$svc" && log_info "Started $svc" ;;
        S) sudo systemctl stop "$svc" && log_info "Stopped $svc" ;;
        r) sudo systemctl restart "$svc" && log_info "Restarted $svc" ;;
        l) journalctl -u "$svc" --no-pager -n 50 ;;
        q) break ;;
        *) log_error "Unknown action: $action" ;;
    esac
    echo ""
done

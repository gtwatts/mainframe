#!/usr/bin/env bash
# =============================================================================
# container-shell.sh - Interactive docker container shell
# Version: 1.0.0
# Requires: docker, fzf (optional, falls back to select)
# Usage: ./container-shell.sh [--logs]
# chmod +x scripts/docker/container-shell.sh
# =============================================================================
set -euo pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

usage() {
    echo "Usage: $(basename "$0") [--logs]"
    echo "  Select a running container and open an interactive shell."
    echo "  --logs  Show container logs instead of shell"
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

MODE="shell"
[[ "${1:-}" == "--logs" ]] && MODE="logs"

docker ps --format '{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}' \
    | grep -q . || { log_error "No running containers found."; exit 1; }

selected=$(docker ps --format '{{.ID}}  {{.Names}}  {{.Image}}  {{.Status}}' \
    | _pick --prompt="Container> " || true)

[[ -z "$selected" ]] && { log_info "No container selected."; exit 0; }

container=$(echo "$selected" | awk '{print $1}')

if [[ "$MODE" == "logs" ]]; then
    docker logs -f --tail 100 "$container"
else
    log_info "Attaching to $container ..."
    docker exec -it "$container" "${SHELL:-/bin/sh}"
fi

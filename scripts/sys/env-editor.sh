#!/usr/bin/env bash
# =============================================================================
# env-editor.sh - Interactive .env file editor
# Version: 1.0.0
# Requires: fzf (optional, falls back to select)
# Usage: ./env-editor.sh [file] [--add]
# chmod +x scripts/sys/env-editor.sh
# =============================================================================
set -euo pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

usage() {
    echo "Usage: $(basename "$0") [file] [--add]"
    echo "  Edit variables in a .env file interactively."
    echo "  Default file: .env"
    echo "  --add  Add a new variable instead of editing existing"
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

ADD_MODE=false
ENVFILE=".env"
for arg in "$@"; do
    case "$arg" in
        --add) ADD_MODE=true ;;
        -*) ;;
        *) ENVFILE="$arg" ;;
    esac
done

[[ -f "$ENVFILE" ]] || { log_error "File not found: $ENVFILE"; exit 1; }

if [[ "$ADD_MODE" == true ]]; then
    read -rp "Variable name: " varname
    [[ -z "$varname" ]] && { log_error "Empty name."; exit 1; }
    read -rp "Value: " varval
    echo "${varname}=${varval}" >> "$ENVFILE"
    log_info "Added ${varname} to $ENVFILE"
    exit 0
fi

selected=$(grep -v '^\s*#' "$ENVFILE" \
    | grep -v '^\s*$' \
    | _pick --prompt="Variable> " || true)

[[ -z "$selected" ]] && { log_info "No variable selected."; exit 0; }

key=$(echo "$selected" | cut -d= -f1)
old_val=$(echo "$selected" | cut -d= -f2-)

echo "Current: ${key}=${old_val}"
read -rp "New value (empty to keep): " new_val

[[ -z "$new_val" ]] && { log_info "Unchanged."; exit 0; }

# Preserve file structure: replace only the matching line
sed -i "s|^${key}=.*|${key}=${new_val}|" "$ENVFILE"
log_info "Updated ${key} in $ENVFILE"

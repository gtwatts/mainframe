#!/usr/bin/env bash
# =============================================================================
# MAINFRAME: Command Presence Checker
# =============================================================================
# Description: Check if commands exist and display their versions
# Category:    Environment
# WOW Factor:  8/10
# Inspired by: https://github.com/kdabir/has
# =============================================================================
# "Knowing what you have is half the battle." - Mainframe Philosophy
# =============================================================================

set -euo pipefail

# Source MAINFRAME common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAINFRAME_ROOT="${MAINFRAME_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
source "$MAINFRAME_ROOT/lib/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_VERSION="1.0.0"

# =============================================================================
# COMMAND CHECKING
# =============================================================================

# Check if command exists (faster than which)
# Usage: cmd_exists curl
has() {
    local cmd="$1"
    local version_flag="${2:---version}"

    if type -p "$cmd" &>/dev/null; then
        local version
        version=$("$cmd" "$version_flag" 2>&1 | head -1) || version="(version unavailable)"
        printf '%b%-15s%b %s\n' "$CLR_GREEN" "$cmd" "$CLR_RESET" "$version"
        return 0
    else
        printf '%b%-15s%b %s\n' "$CLR_RED" "$cmd" "$CLR_RESET" "NOT FOUND"
        return 1
    fi
}

# Check command with custom version flag
# Usage: has_flag java -version
has_flag() {
    local cmd="$1"
    local flag="$2"
    has "$cmd" "$flag"
}

# Check multiple commands
# Usage: has_all curl jq git
has_all() {
    local failures=0
    for cmd in "$@"; do
        has "$cmd" || ((failures++)) || true
    done
    return "$failures"
}

# Check if any command exists
# Usage: has_any curl wget
has_any() {
    for cmd in "$@"; do
        if type -p "$cmd" &>/dev/null; then
            has "$cmd"
            return 0
        fi
    done
    printf '%bNone found:%b %s\n' "$CLR_RED" "$CLR_RESET" "$*" >&2
    return 1
}

# List all commands in PATH
# Usage: has_list
has_list() {
    local dirs
    IFS=':' read -ra dirs <<< "$PATH"

    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            for file in "$dir"/*; do
                [[ -x "$file" ]] && printf '%s\n' "${file##*/}"
            done
        fi
    done | sort -u
}

# =============================================================================
# COMMON COMMAND GROUPS
# =============================================================================

# Check development tools
has_dev() {
    header "Development Tools"
    has git || true
    has make || true
    has gcc || true
    has_flag python3 --version || true
    has_flag node --version || true
    has npm || true
    has go version || true
    has_flag rustc --version || true
    has cargo || true
}

# Check network tools
has_net() {
    header "Network Tools"
    has curl || true
    has wget || true
    has ssh || true
    has_flag openssl version || true
    has nmap || true
    has nc || true
    has dig || true
    has ping || true
}

# Check container tools
has_containers() {
    header "Container Tools"
    has docker || true
    has docker-compose || true
    has podman || true
    has kubectl || true
    has helm || true
    has minikube || true
}

# Check shell tools
has_shell() {
    header "Shell Tools"
    has bash || true
    has zsh || true
    has fish || true
    has tmux || true
    has screen || true
    has jq || true
    has yq || true
    has fzf || true
    has ripgrep || true
    has fd || true
}

# Check AI/ML tools
has_ai() {
    header "AI/ML Tools"
    has_flag python3 --version || true
    has pip || true
    has ollama || true
    has claude || true
}

# Full system check
has_system() {
    has_dev
    has_net
    has_containers
    has_shell
    has_ai
}

# =============================================================================
# HELP
# =============================================================================

show_help() {
    cat << EOF
${CLR_BOLD}MAINFRAME Command Checker${CLR_RESET}

Usage: $SCRIPT_NAME [options] [command...]

Options:
    -h, --help          Show this help message
    -v, --version       Show version
    -a, --all           Check common development tools
    -d, --dev           Check development tools
    -n, --net           Check network tools
    -c, --containers    Check container tools
    -s, --shell         Check shell tools
    --ai                Check AI/ML tools
    --any               Check if ANY of the commands exist

Examples:
    $SCRIPT_NAME curl jq git              # Check specific commands
    $SCRIPT_NAME --dev                     # Check all dev tools
    $SCRIPT_NAME --any curl wget           # Check if curl OR wget exists
    $SCRIPT_NAME --all                     # Full system check

${CLR_DIM}YO JOE!${CLR_RESET}
EOF
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local mode="check"
    local commands=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
                exit 0
                ;;
            -a|--all)
                mode="system"
                shift
                ;;
            -d|--dev)
                mode="dev"
                shift
                ;;
            -n|--net)
                mode="net"
                shift
                ;;
            -c|--containers)
                mode="containers"
                shift
                ;;
            -s|--shell)
                mode="shell"
                shift
                ;;
            --ai)
                mode="ai"
                shift
                ;;
            --any)
                mode="any"
                shift
                ;;
            -*)
                die_usage "Unknown option: $1"
                ;;
            *)
                commands+=("$1")
                shift
                ;;
        esac
    done

    case "$mode" in
        system)
            has_system
            ;;
        dev)
            has_dev
            ;;
        net)
            has_net
            ;;
        containers)
            has_containers
            ;;
        shell)
            has_shell
            ;;
        ai)
            has_ai
            ;;
        any)
            if [[ ${#commands[@]} -eq 0 ]]; then
                die_usage "Please specify commands to check with --any"
            fi
            has_any "${commands[@]}"
            ;;
        check)
            if [[ ${#commands[@]} -eq 0 ]]; then
                show_help
                exit 0
            fi
            has_all "${commands[@]}"
            ;;
    esac
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

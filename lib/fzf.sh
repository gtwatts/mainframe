#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/fzf.sh - Interactive Pipe Filter Library
# =============================================================================
# Description: Wraps fzf as a composable pipe stage for interactive selection.
#              Text flows in on stdin, user selects, selection flows out on
#              stdout. Falls back to a numbered menu when fzf is not installed.
#              In non-interactive mode (no TTY), selects first match or
#              $FZF_DEFAULT automatically.
# Version: 1.0.0
# Requires: Bash 4.0+ (fzf optional - graceful fallback)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_FZF_LOADED:-}" ]] && return 0
readonly _MAINFRAME_FZF_LOADED=1

source "${MAINFRAME_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/common.sh" 2>/dev/null || true

# =============================================================================
# HELPERS (PRIVATE)
# =============================================================================

# Check if stdin and stderr (for prompts) are connected to a TTY
_fzf_is_interactive() {
    [[ -t 2 ]]
}

# Parse our option flags into fzf command-line arguments
# Sets FZF_ARGS array and FALLBACK_PROMPT, FALLBACK_HEADER, FALLBACK_MULTI
_fzf_build_args() {
    FZF_ARGS=()
    FALLBACK_PROMPT="Select: "
    FALLBACK_HEADER=""
    FALLBACK_MULTI=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --multi)       FZF_ARGS+=(--multi); FALLBACK_MULTI=1 ;;
            --prompt)      FZF_ARGS+=(--prompt "$2"); FALLBACK_PROMPT="$2"; shift ;;
            --header)      FZF_ARGS+=(--header "$2"); FALLBACK_HEADER="$2"; shift ;;
            --preview)     FZF_ARGS+=(--preview "$2"); shift ;;
            --height)      FZF_ARGS+=(--height "$2"); shift ;;
            *)             FZF_ARGS+=("$1") ;;
        esac
        shift
    done
}

# Pure bash numbered menu fallback (no fzf needed)
# Reads lines from an array, displays numbered list, prompts for selection
_fzf_fallback_menu() {
    local -a items=("$@")
    local count=${#items[@]}

    if [[ $count -eq 0 ]]; then
        return 1
    fi

    # Display header if set
    [[ -n "${FALLBACK_HEADER:-}" ]] && printf '%s\n' "$FALLBACK_HEADER" >&2

    # Display numbered list
    local i
    for ((i = 0; i < count; i++)); do
        printf '  %d) %s\n' "$((i + 1))" "${items[$i]}" >&2
    done

    if [[ ${FALLBACK_MULTI:-0} -eq 1 ]]; then
        printf '%s' "${FALLBACK_PROMPT:-Select (space-separated) [1-$count]: }" >&2
        local input
        read -r input </dev/tty
        local num
        for num in $input; do
            if [[ "$num" =~ ^[0-9]+$ ]] && ((num >= 1 && num <= count)); then
                printf '%s\n' "${items[$((num - 1))]}"
            fi
        done
    else
        printf '%s' "${FALLBACK_PROMPT:-Select [1-$count]: }" >&2
        local choice
        read -r choice </dev/tty
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= count)); then
            printf '%s\n' "${items[$((choice - 1))]}"
        else
            return 1
        fi
    fi
}

# =============================================================================
# CORE SELECTION
# =============================================================================

# Return 0 if fzf is installed, 1 if not
fzf_available() {
    command -v fzf &>/dev/null
}

# Read stdin lines, present interactive menu, output selection on stdout
# Options: --multi, --prompt "text", --header "text", --preview "cmd {}", --height N
fzf_select() {
    _fzf_build_args "$@"

    # Read all stdin into array
    local -a lines=()
    while IFS= read -r line; do
        lines+=("$line")
    done

    if [[ ${#lines[@]} -eq 0 ]]; then
        return 1
    fi

    # Non-interactive: auto-select
    if ! _fzf_is_interactive; then
        if [[ -n "${FZF_DEFAULT:-}" ]]; then
            local match
            for match in "${lines[@]}"; do
                if [[ "$match" == *"$FZF_DEFAULT"* ]]; then
                    printf '%s\n' "$match"
                    return 0
                fi
            done
        fi
        printf 'Non-interactive: selecting first match\n' >&2
        printf '%s\n' "${lines[0]}"
        return 0
    fi

    # Interactive with fzf
    if fzf_available; then
        printf '%s\n' "${lines[@]}" | fzf "${FZF_ARGS[@]}"
    else
        # Fallback to numbered menu
        _fzf_fallback_menu "${lines[@]}"
    fi
}

# Explicit fallback name (alias for fzf_select)
fzf_or_select() {
    fzf_select "$@"
}

# =============================================================================
# SPECIALIZED SELECTORS
# =============================================================================

# Select a file from a directory (default: current dir)
fzf_file() {
    local dir="${1:-.}"
    find "$dir" -type f -not -path '*/.git/*' 2>/dev/null | sort \
        | fzf_select --prompt "File: " --preview "head -40 {}"
}

# Select a directory (default: current dir)
fzf_dir() {
    local dir="${1:-.}"
    find "$dir" -type d -not -path '*/.git/*' 2>/dev/null | sort \
        | fzf_select --prompt "Dir: "
}

# Select a process, output PID
fzf_process() {
    ps aux 2>/dev/null \
        | fzf_select --prompt "Process: " --header "USER PID %CPU %MEM COMMAND" \
        | awk '{print $2}'
}

# Select a git branch, output clean branch name
fzf_git_branch() {
    git branch --all 2>/dev/null | sed 's/^[* ]*//' | sed 's|remotes/||' \
        | fzf_select --prompt "Branch: "
}

# Select a git commit, output commit hash
fzf_git_log() {
    git log --oneline -50 2>/dev/null \
        | fzf_select --prompt "Commit: " --preview "git show --stat {1}" \
        | awk '{print $1}'
}

# Select a tracked git file, output file path
fzf_git_file() {
    git ls-files 2>/dev/null \
        | fzf_select --prompt "Git file: " --preview "head -40 {}"
}

# Select a docker container, output container ID
fzf_docker_container() {
    docker ps --format "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null \
        | fzf_select --prompt "Container: " --header "ID  NAME  IMAGE  STATUS" \
        | awk '{print $1}'
}

# Select a listening port, output port number
fzf_port() {
    if command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null | tail -n +2
    elif command -v netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null | tail -n +3
    else
        printf 'No ss or netstat available\n' >&2
        return 1
    fi \
        | fzf_select --prompt "Port: " \
        | grep -oP ':\K[0-9]+' | head -1
}

# Select an environment variable, output VAR=value
fzf_env() {
    env | sort | fzf_select --prompt "Env: "
}

# Select from shell history, output the command
fzf_history() {
    history 2>/dev/null | tail -200 | tac \
        | fzf_select --prompt "History: " \
        | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//'
}

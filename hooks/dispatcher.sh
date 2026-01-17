#!/usr/bin/env bash
# =============================================================================
# basher/hooks/dispatcher.sh - Central hook dispatcher for Basher
# =============================================================================

set -euo pipefail

# Determine root directory
BASHER_ROOT="${BASHER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export BASHER_ROOT

# Source libraries
source "$BASHER_ROOT/lib/common.sh"
source "$BASHER_ROOT/lib/config.sh"

# =============================================================================
# HOOK EXECUTION
# =============================================================================

# Run all hooks in a directory
run_hooks() {
    local hook_dir="$1"
    shift
    local -a hook_args=("$@")

    if [[ ! -d "$hook_dir" ]]; then
        log_debug "Hook directory not found: $hook_dir"
        return 0
    fi

    local hook_type
    hook_type=$(basename "$hook_dir")
    export BASHER_HOOK_TYPE="$hook_type"

    # Check if hooks are enabled
    if ! config_get_bool "hooks.enabled" true; then
        log_debug "Hooks disabled globally"
        return 0
    fi

    if ! config_get_bool "${hook_type}.enabled" true; then
        log_debug "Hooks disabled for type: $hook_type"
        return 0
    fi

    # Get timeout
    local timeout
    timeout=$(config_get_int "hooks.timeout" 30)

    # Get script list (or all scripts)
    local -a scripts
    local configured_scripts
    configured_scripts=$(config_get "${hook_type}.scripts" "")

    if [[ -n "$configured_scripts" ]]; then
        IFS=',' read -ra scripts <<< "$configured_scripts"
        scripts=("${scripts[@]/#/$hook_dir/}")
    else
        # Find all executable scripts
        mapfile -t scripts < <(find "$hook_dir" -maxdepth 1 -type f -executable | sort)
    fi

    [[ ${#scripts[@]} -eq 0 ]] && return 0

    log_debug "Running ${#scripts[@]} hooks for: $hook_type"

    local script exit_code=0
    for script in "${scripts[@]}"; do
        [[ -x "$script" ]] || continue

        local script_name
        script_name=$(basename "$script")

        log_debug "Executing hook: $script_name"

        # Run with timeout
        if command_exists timeout; then
            timeout --preserve-status "$timeout" "$script" "${hook_args[@]}" || exit_code=$?
        else
            "$script" "${hook_args[@]}" || exit_code=$?
        fi

        case $exit_code in
            0)
                log_debug "Hook completed: $script_name"
                ;;
            1)
                if [[ "$hook_type" == "pre-command" ]]; then
                    log_warn "Hook aborted command: $script_name"
                    return 1
                else
                    log_warn "Hook failed: $script_name (exit code: 1)"
                fi
                ;;
            2)
                log_debug "Hook requested skip remaining: $script_name"
                return 0
                ;;
            124)
                log_warn "Hook timed out: $script_name"
                ;;
            *)
                log_warn "Hook failed: $script_name (exit code: $exit_code)"
                ;;
        esac
    done

    return 0
}

# =============================================================================
# SPECIALIZED DISPATCHERS
# =============================================================================

# Pre-command dispatcher
dispatch_pre_command() {
    export BASHER_COMMAND="${1:-}"
    run_hooks "$BASHER_ROOT/hooks/pre-command" "$@"
}

# Post-command dispatcher
dispatch_post_command() {
    export BASHER_COMMAND="${1:-}"
    export BASHER_EXIT_CODE="${2:-0}"
    run_hooks "$BASHER_ROOT/hooks/post-command" "$@"
}

# File change dispatcher
dispatch_file_change() {
    local file="${1:?File path required}"
    local change_type="${2:-modify}"

    export BASHER_CHANGED_FILE="$file"
    export BASHER_CHANGED_TYPE="$change_type"

    # Check if file matches configured patterns
    local patterns
    patterns=$(config_get "file-change.patterns" "*")

    local IFS=','
    local pattern matched=false
    for pattern in $patterns; do
        pattern=$(trim "$pattern")
        if [[ "$file" == $pattern ]]; then
            matched=true
            break
        fi
    done

    if [[ "$matched" != "true" ]]; then
        log_debug "File does not match patterns: $file"
        return 0
    fi

    run_hooks "$BASHER_ROOT/hooks/file-change" "$file" "$change_type"
}

# Context provider dispatcher
dispatch_context() {
    local context=""
    local hook_dir="$BASHER_ROOT/hooks/context"

    if [[ ! -d "$hook_dir" ]]; then
        return 0
    fi

    local script
    for script in "$hook_dir"/*; do
        [[ -x "$script" ]] || continue

        local output
        if output=$("$script" 2>/dev/null); then
            [[ -n "$output" ]] && context+="$output"$'\n\n'
        fi
    done

    # Output accumulated context
    printf '%s' "$context"
}

# =============================================================================
# MAIN DISPATCHER
# =============================================================================

main() {
    local hook_type="${1:-}"
    shift || true

    if [[ -z "$hook_type" ]]; then
        printf "Usage: %s <hook-type> [args...]\n" "$(basename "$0")"
        printf "\nHook types:\n"
        printf "  pre-command   Run before command execution\n"
        printf "  post-command  Run after command execution\n"
        printf "  file-change   Run when files change\n"
        printf "  context       Generate context for AI agent\n"
        exit 1
    fi

    case "$hook_type" in
        pre-command|precommand)
            dispatch_pre_command "$@"
            ;;
        post-command|postcommand)
            dispatch_post_command "$@"
            ;;
        file-change|filechange)
            dispatch_file_change "$@"
            ;;
        context)
            dispatch_context "$@"
            ;;
        *)
            die "$EXIT_USAGE" "Unknown hook type: $hook_type"
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

#!/usr/bin/env bash
# =============================================================================
# events.sh - Event and Hook System for MAINFRAME
# =============================================================================
# Description: Provides a general-purpose event system with hooks for
#              extending MAINFRAME behavior. Supports before/after hooks,
#              event emission, and listener registration.
# Version: 1.0.0
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_EVENTS_LOADED:-}" ]] && return 0
declare -g _MAINFRAME_EVENTS_LOADED=1

# =============================================================================
# Global State
# =============================================================================

# Associative arrays for hooks and event listeners
declare -gA _EVENTS_HOOKS=()        # hook_name -> "callback1;callback2;..."
declare -gA _EVENTS_LISTENERS=()    # event_name -> "callback1;callback2;..."
declare -g _EVENTS_LOG_FILE=""      # Optional event log file

# =============================================================================
# Internal Functions
# =============================================================================

# Split callbacks and execute each
_events_execute_callbacks() {
    local callbacks="$1"
    shift
    local args=("$@")

    [[ -z "$callbacks" ]] && return 0

    # Split by semicolon and execute each
    local IFS=';'
    local callback
    for callback in $callbacks; do
        [[ -z "$callback" ]] && continue

        # Execute callback with arguments
        if declare -F "$callback" &>/dev/null; then
            "$callback" "${args[@]}"
        else
            # Try as command string
            eval "$callback" 2>/dev/null || true
        fi
    done
}

# Log event if logging enabled
_events_log() {
    [[ -z "$_EVENTS_LOG_FILE" ]] && return 0

    local event="$1"
    local data="${2:-}"
    local timestamp
    timestamp=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')

    printf '{"timestamp":"%s","event":"%s","data":%s}\n' \
        "$timestamp" "$event" "${data:-null}" >> "$_EVENTS_LOG_FILE"
}

# =============================================================================
# Hook API (before/after execution points)
# =============================================================================

# hook_on - Register a hook callback
# Usage: hook_on <hook_name> <callback>
# Example: hook_on "before_write" "my_validator"
hook_on() {
    local hook_name="$1"
    local callback="$2"

    [[ -z "$hook_name" || -z "$callback" ]] && {
        echo "Usage: hook_on <hook_name> <callback>" >&2
        return 1
    }

    # Append to existing hooks
    if [[ -n "${_EVENTS_HOOKS[$hook_name]:-}" ]]; then
        _EVENTS_HOOKS[$hook_name]+=";"
    fi
    _EVENTS_HOOKS[$hook_name]+="$callback"

    return 0
}

# hook_off - Remove a hook callback
# Usage: hook_off <hook_name> [callback]
hook_off() {
    local hook_name="$1"
    local callback="${2:-}"

    [[ -z "$hook_name" ]] && {
        echo "Usage: hook_off <hook_name> [callback]" >&2
        return 1
    }

    if [[ -z "$callback" ]]; then
        # Remove all callbacks for this hook
        unset "_EVENTS_HOOKS[$hook_name]"
    else
        # Remove specific callback
        local current="${_EVENTS_HOOKS[$hook_name]:-}"
        local new_callbacks=""
        local IFS=';'
        local cb
        for cb in $current; do
            [[ "$cb" == "$callback" ]] && continue
            [[ -n "$new_callbacks" ]] && new_callbacks+=";"
            new_callbacks+="$cb"
        done
        _EVENTS_HOOKS[$hook_name]="$new_callbacks"
    fi
}

# hook_trigger - Execute all callbacks for a hook
# Usage: hook_trigger <hook_name> [args...]
# Returns: 0 if all callbacks succeed, 1 if any fail
hook_trigger() {
    local hook_name="$1"
    shift

    local callbacks="${_EVENTS_HOOKS[$hook_name]:-}"
    [[ -z "$callbacks" ]] && return 0

    _events_log "hook:$hook_name" "{\"args\":\"$*\"}"
    _events_execute_callbacks "$callbacks" "$@"
}

# hook_list - List registered hooks
# Usage: hook_list [hook_name]
hook_list() {
    local hook_name="${1:-}"

    if [[ -n "$hook_name" ]]; then
        echo "Hook: $hook_name"
        echo "Callbacks: ${_EVENTS_HOOKS[$hook_name]:-none}"
    else
        echo "Registered Hooks:"
        local name
        for name in "${!_EVENTS_HOOKS[@]}"; do
            echo "  $name: ${_EVENTS_HOOKS[$name]}"
        done
    fi
}

# =============================================================================
# Event API (pub/sub pattern)
# =============================================================================

# event_on - Subscribe to an event
# Usage: event_on <event_name> <callback>
# Example: event_on "deployment_complete" "update_status_page"
event_on() {
    local event_name="$1"
    local callback="$2"

    [[ -z "$event_name" || -z "$callback" ]] && {
        echo "Usage: event_on <event_name> <callback>" >&2
        return 1
    }

    # Append to existing listeners
    if [[ -n "${_EVENTS_LISTENERS[$event_name]:-}" ]]; then
        _EVENTS_LISTENERS[$event_name]+=";"
    fi
    _EVENTS_LISTENERS[$event_name]+="$callback"

    return 0
}

# event_off - Unsubscribe from an event
# Usage: event_off <event_name> [callback]
event_off() {
    local event_name="$1"
    local callback="${2:-}"

    [[ -z "$event_name" ]] && {
        echo "Usage: event_off <event_name> [callback]" >&2
        return 1
    }

    if [[ -z "$callback" ]]; then
        unset "_EVENTS_LISTENERS[$event_name]"
    else
        local current="${_EVENTS_LISTENERS[$event_name]:-}"
        local new_listeners=""
        local IFS=';'
        local cb
        for cb in $current; do
            [[ "$cb" == "$callback" ]] && continue
            [[ -n "$new_listeners" ]] && new_listeners+=";"
            new_listeners+="$cb"
        done
        _EVENTS_LISTENERS[$event_name]="$new_listeners"
    fi
}

# event_emit - Emit an event to all listeners
# Usage: event_emit <event_name> [--data "json"]
event_emit() {
    local event_name="$1"
    shift
    local data=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --data) data="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    [[ -z "$event_name" ]] && {
        echo "Usage: event_emit <event_name> [--data \"json\"]" >&2
        return 1
    }

    local listeners="${_EVENTS_LISTENERS[$event_name]:-}"

    _events_log "$event_name" "${data:-null}"

    [[ -z "$listeners" ]] && return 0

    _events_execute_callbacks "$listeners" "$event_name" "$data"
}

# event_once - Subscribe to an event for one-time execution
# Usage: event_once <event_name> <callback>
event_once() {
    local event_name="$1"
    local callback="$2"

    [[ -z "$event_name" || -z "$callback" ]] && {
        echo "Usage: event_once <event_name> <callback>" >&2
        return 1
    }

    # Create wrapper that removes itself after execution
    local wrapper="_once_${event_name}_${callback//[^a-zA-Z0-9_]/_}"

    eval "$wrapper() {
        $callback \"\$@\"
        event_off \"$event_name\" \"$wrapper\"
    }"

    event_on "$event_name" "$wrapper"
}

# event_list - List registered events and listeners
# Usage: event_list [event_name]
event_list() {
    local event_name="${1:-}"

    if [[ -n "$event_name" ]]; then
        echo "Event: $event_name"
        echo "Listeners: ${_EVENTS_LISTENERS[$event_name]:-none}"
    else
        echo "Registered Events:"
        local name
        for name in "${!_EVENTS_LISTENERS[@]}"; do
            echo "  $name: ${_EVENTS_LISTENERS[$name]}"
        done
    fi
}

# =============================================================================
# Built-in Hooks (Common Extension Points)
# =============================================================================

# These are the recommended hook points for MAINFRAME
# Scripts can trigger these at appropriate times

# Built-in hook names (documented for users)
: << 'HOOK_DOCUMENTATION'
Built-in hooks that other MAINFRAME components may trigger:

before_exec     - Before executing a command
after_exec      - After executing a command (with exit code)
before_write    - Before writing to a file
after_write     - After writing to a file
on_error        - When an error occurs
on_success      - When an operation succeeds
checkpoint_created   - When a checkpoint is created
checkpoint_restored  - When a checkpoint is restored
HOOK_DOCUMENTATION

# =============================================================================
# Configuration
# =============================================================================

# events_enable_logging - Enable event logging to file
# Usage: events_enable_logging <file_path>
events_enable_logging() {
    local file_path="$1"

    [[ -z "$file_path" ]] && {
        echo "Usage: events_enable_logging <file_path>" >&2
        return 1
    }

    # Ensure parent directory exists
    mkdir -p "$(dirname "$file_path")" 2>/dev/null

    _EVENTS_LOG_FILE="$file_path"
    echo "Event logging enabled: $file_path"
}

# events_disable_logging - Disable event logging
events_disable_logging() {
    _EVENTS_LOG_FILE=""
    echo "Event logging disabled"
}

# events_clear_all - Clear all hooks and listeners
events_clear_all() {
    _EVENTS_HOOKS=()
    _EVENTS_LISTENERS=()
    echo "All hooks and listeners cleared"
}

# =============================================================================
# Module Exports
# =============================================================================

declare -ga _EVENTS_EXPORTS=(
    hook_on
    hook_off
    hook_trigger
    hook_list
    event_on
    event_off
    event_emit
    event_once
    event_list
    events_enable_logging
    events_disable_logging
    events_clear_all
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${_EVENTS_EXPORTS[@]}" 2>/dev/null || true
fi

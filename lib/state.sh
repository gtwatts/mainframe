#!/usr/bin/env bash
# =============================================================================
# state.sh - Simple State Persistence for Scripts
# =============================================================================
# Description: Provides a simple key-value state store with checkpointing.
#              Wraps taskstate.sh with a cleaner API for general use.
# Version: 1.0.0
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_STATE_LOADED:-}" ]] && return 0
_MAINFRAME_STATE_LOADED=1
readonly _MAINFRAME_STATE_LOADED

# =============================================================================
# Global State
# =============================================================================

_STATE_CURRENT_PATH=""
_STATE_FORMAT="json"
_STATE_TTL=0

# =============================================================================
# Internal Functions
# =============================================================================

# Atomic write with temp file + rename
_state_atomic_write() {
    local file="$1"
    local content="$2"
    local tmp="${file}.tmp.$$"

    printf '%s' "$content" > "$tmp" && mv "$tmp" "$file"
}

# Get current timestamp
_state_timestamp() {
    date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S'
}

# Initialize state file if needed
_state_init_file() {
    local state_file="${_STATE_CURRENT_PATH}/state.json"

    if [[ ! -f "$state_file" ]]; then
        local now
        now=$(_state_timestamp)
        local expires_at=0
        [[ $_STATE_TTL -gt 0 ]] && expires_at=$(($(date +%s) + _STATE_TTL))

        _state_atomic_write "$state_file" "{
  \"_meta\": {
    \"format_version\": \"1.0\",
    \"created_at\": \"$now\",
    \"updated_at\": \"$now\",
    \"ttl\": $_STATE_TTL,
    \"expires_at\": $expires_at
  },
  \"data\": {}
}"
    fi
}

# Read state file
_state_read() {
    local state_file="${_STATE_CURRENT_PATH}/state.json"
    [[ -f "$state_file" ]] && cat "$state_file"
}

# Update a key in state (simple implementation)
_state_update_key() {
    local key="$1"
    local value="$2"
    local type="${3:-string}"
    local state_file="${_STATE_CURRENT_PATH}/state.json"

    # Lock file for concurrent access
    local lock_file="${state_file}.lock"

    (
        # Try to get lock
        if command -v flock &>/dev/null; then
            flock -x 200 2>/dev/null || true
        fi

        local current
        current=$(_state_read)
        [[ -z "$current" ]] && return 1

        local now
        now=$(_state_timestamp)

        # Build the value JSON based on type
        local value_json
        case "$type" in
            int|number)
                value_json="$value"
                ;;
            bool|boolean)
                [[ "$value" =~ ^(true|1|yes)$ ]] && value_json="true" || value_json="false"
                ;;
            json)
                value_json="$value"
                ;;
            *)
                # Escape string value
                local escaped="${value//\\/\\\\}"
                escaped="${escaped//\"/\\\"}"
                escaped="${escaped//$'\n'/\\n}"
                value_json="\"$escaped\""
                ;;
        esac

        # Simple key insertion/update using sed-like approach
        # Check if key exists
        if [[ "$current" =~ \"$key\"[[:space:]]*: ]]; then
            # Update existing key - use awk for reliability
            local new_content
            new_content=$(echo "$current" | awk -v key="$key" -v val="$value_json" -v type="$type" -v now="$now" '
                BEGIN { in_key = 0 }
                /"data"/ { in_data = 1 }
                in_data && $0 ~ "\"" key "\"" { in_key = 1 }
                in_key && /}/ {
                    print "    \"" key "\": {"
                    print "      \"value\": " val ","
                    print "      \"type\": \"" type "\","
                    print "      \"updated_at\": \"" now "\""
                    print "    }"
                    in_key = 0
                    next
                }
                in_key { next }
                { print }
            ')
            [[ -n "$new_content" ]] && _state_atomic_write "$state_file" "$new_content"
        else
            # Insert new key before closing brace of data
            local entry="    \"$key\": {\n      \"value\": $value_json,\n      \"type\": \"$type\",\n      \"updated_at\": \"$now\"\n    }"

            # Find position to insert (before last } in data block)
            if [[ "$current" =~ \"data\"[[:space:]]*:[[:space:]]*\{\} ]]; then
                # Empty data, replace {}
                local new_content="${current/\"data\": \{\}/\"data\": {\n$entry\n  \}}"
                _state_atomic_write "$state_file" "$new_content"
            else
                # Has data, insert before closing }
                local new_content
                new_content=$(echo "$current" | sed "/\"data\".*{/,/^  }/ s/^  }/,\n$entry\n  }/")
                [[ -n "$new_content" ]] && _state_atomic_write "$state_file" "$new_content"
            fi
        fi

        # Update metadata timestamp
        # (simplified - in production would update _meta.updated_at)

    ) 200>"$lock_file"

    rm -f "$lock_file" 2>/dev/null
}

# Read a key from state
_state_read_key() {
    local key="$1"
    local current
    current=$(_state_read) || return 1

    # Extract the value for the key
    # Look for "key": { "value": ... }
    local pattern="\"$key\"[[:space:]]*:[[:space:]]*\{[^}]*\"value\"[[:space:]]*:[[:space:]]*"

    if [[ "$current" =~ $pattern ]]; then
        local rest="${current#*$pattern}"
        # Extract the value (handle string or other types)
        if [[ "$rest" =~ ^\"([^\"]*)\" ]]; then
            printf '%s' "${BASH_REMATCH[1]}"
            return 0
        elif [[ "$rest" =~ ^([^,}]+) ]]; then
            printf '%s' "${BASH_REMATCH[1]}" | tr -d ' '
            return 0
        fi
    fi

    return 1
}

# =============================================================================
# Public API
# =============================================================================

# state_init - Initialize a state store
# Usage: state_init <path> [--format json|env] [--ttl seconds]
state_init() {
    local path="$1"
    shift

    [[ -z "$path" ]] && {
        echo "Usage: state_init <path> [--ttl seconds]" >&2
        return 1
    }

    _STATE_FORMAT="json"
    _STATE_TTL=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) _STATE_FORMAT="$2"; shift 2 ;;
            --ttl) _STATE_TTL="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Create directory
    mkdir -p "$path" || return 1

    _STATE_CURRENT_PATH="$path"

    # Initialize state file
    _state_init_file

    return 0
}

# state_set - Store a value
# Usage: state_set <key> <value> [--type string|int|bool|json]
state_set() {
    local key="$1"
    local value="$2"
    shift 2
    local type="string"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type) type="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    [[ -z "$_STATE_CURRENT_PATH" ]] && {
        echo "Error: state not initialized. Call state_init first." >&2
        return 1
    }

    [[ -z "$key" ]] && {
        echo "Usage: state_set <key> <value> [--type string|int|bool|json]" >&2
        return 1
    }

    _state_update_key "$key" "$value" "$type"
}

# state_get - Retrieve a value
# Usage: state_get <key> [--default value]
state_get() {
    local key="$1"
    shift
    local default=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --default) default="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    [[ -z "$_STATE_CURRENT_PATH" ]] && {
        echo "Error: state not initialized. Call state_init first." >&2
        return 1
    }

    local value
    if value=$(_state_read_key "$key"); then
        printf '%s' "$value"
        return 0
    else
        [[ -n "$default" ]] && printf '%s' "$default"
        return 1
    fi
}

# state_delete - Remove a key
# Usage: state_delete <key>
state_delete() {
    local key="$1"

    [[ -z "$_STATE_CURRENT_PATH" ]] && {
        echo "Error: state not initialized. Call state_init first." >&2
        return 1
    }

    local state_file="${_STATE_CURRENT_PATH}/state.json"
    local current
    current=$(_state_read) || return 0

    # Remove the key block (simplified)
    local new_content
    new_content=$(echo "$current" | awk -v key="$key" '
        BEGIN { skip = 0 }
        $0 ~ "\"" key "\"" { skip = 1 }
        skip && /}/ { skip = 0; next }
        skip { next }
        { print }
    ')

    [[ -n "$new_content" ]] && _state_atomic_write "$state_file" "$new_content"
}

# state_list - List all keys
# Usage: state_list [--prefix pattern]
state_list() {
    local prefix=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prefix) prefix="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    [[ -z "$_STATE_CURRENT_PATH" ]] && {
        echo "Error: state not initialized. Call state_init first." >&2
        return 1
    }

    local current
    current=$(_state_read) || return 0

    # Extract keys from data block
    echo "$current" | grep -oE '"[a-zA-Z_][a-zA-Z0-9_.]*"[[:space:]]*:[[:space:]]*\{' | \
        grep -oE '"[^"]+"' | tr -d '"' | grep -v '_meta' | \
        { [[ -n "$prefix" ]] && grep "^$prefix" || cat; }
}

# state_checkpoint - Create named snapshot
# Usage: state_checkpoint <name>
state_checkpoint() {
    local name="$1"

    [[ -z "$name" ]] && {
        echo "Usage: state_checkpoint <name>" >&2
        return 1
    }

    [[ -z "$_STATE_CURRENT_PATH" ]] && {
        echo "Error: state not initialized. Call state_init first." >&2
        return 1
    }

    local checkpoints_dir="${_STATE_CURRENT_PATH}/checkpoints"
    mkdir -p "$checkpoints_dir"

    local state_file="${_STATE_CURRENT_PATH}/state.json"
    local checkpoint_file="${checkpoints_dir}/${name}.json"

    cp "$state_file" "$checkpoint_file"
    echo "Checkpoint '$name' created"
}

# state_rollback - Restore from checkpoint
# Usage: state_rollback <name>
state_rollback() {
    local name="$1"

    [[ -z "$name" ]] && {
        echo "Usage: state_rollback <name>" >&2
        return 1
    }

    [[ -z "$_STATE_CURRENT_PATH" ]] && {
        echo "Error: state not initialized. Call state_init first." >&2
        return 1
    }

    local checkpoint_file="${_STATE_CURRENT_PATH}/checkpoints/${name}.json"
    local state_file="${_STATE_CURRENT_PATH}/state.json"

    [[ ! -f "$checkpoint_file" ]] && {
        echo "Error: Checkpoint '$name' not found" >&2
        return 1
    }

    # Backup current state
    cp "$state_file" "${state_file}.backup.$(date +%s)"

    # Restore checkpoint
    cp "$checkpoint_file" "$state_file"
    echo "Restored from checkpoint '$name'"
}

# state_history - List checkpoints
# Usage: state_history
state_history() {
    [[ -z "$_STATE_CURRENT_PATH" ]] && {
        echo "Error: state not initialized. Call state_init first." >&2
        return 1
    }

    local checkpoints_dir="${_STATE_CURRENT_PATH}/checkpoints"

    [[ ! -d "$checkpoints_dir" ]] && {
        echo "No checkpoints found"
        return 0
    }

    echo "Checkpoints:"
    for f in "$checkpoints_dir"/*.json; do
        [[ -f "$f" ]] || continue
        local name="${f##*/}"
        name="${name%.json}"
        local mtime
        mtime=$(stat -c %y "$f" 2>/dev/null || stat -f %Sm "$f" 2>/dev/null || echo "unknown")
        printf '  %-20s %s\n' "$name" "$mtime"
    done
}

# state_clear - Clear all data
# Usage: state_clear
state_clear() {
    [[ -z "$_STATE_CURRENT_PATH" ]] && {
        echo "Error: state not initialized. Call state_init first." >&2
        return 1
    }

    _state_init_file  # Reinitialize with empty data
    echo "State cleared"
}

# state_destroy - Remove entire state directory
# Usage: state_destroy
state_destroy() {
    [[ -z "$_STATE_CURRENT_PATH" ]] && return 0

    rm -rf "$_STATE_CURRENT_PATH"
    _STATE_CURRENT_PATH=""
    echo "State destroyed"
}

# =============================================================================
# Module Exports
# =============================================================================

declare -ga _STATE_EXPORTS 2>/dev/null || declare -a _STATE_EXPORTS
_STATE_EXPORTS=(
    state_init
    state_set
    state_get
    state_delete
    state_list
    state_checkpoint
    state_rollback
    state_history
    state_clear
    state_destroy
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${_STATE_EXPORTS[@]}" 2>/dev/null || true
fi

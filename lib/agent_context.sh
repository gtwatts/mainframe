#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/agent_context.sh - Persistent Context Object Pattern
# =============================================================================
# Description: Agent state management with persistent context objects, snapshots,
#              versioning, and automatic recovery. Complements lib/context.sh
#              with agent-specific state management patterns.
# Version: 1.0.0
# Requires: Bash 4.0+, jq
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_AGENT_CONTEXT_LOADED:-}" ]] && return 0
readonly _MAINFRAME_AGENT_CONTEXT_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Base directory for context storage
MAINFRAME_CONTEXT_DIR="${MAINFRAME_CONTEXT_DIR:-$HOME/.mainframe/contexts}"

# Auto-save threshold (save after N changes)
MAINFRAME_CONTEXT_AUTOSAVE="${MAINFRAME_CONTEXT_AUTOSAVE:-10}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Current session state (module-level)
declare -g _CTX_SESSION_ID=""
declare -g _CTX_SESSION_DIR=""
declare -g _CTX_VERSION=0
declare -g _CTX_CHANGE_COUNT=0
declare -g _CTX_CREATED_AT=""
declare -g _CTX_UPDATED_AT=""
declare -g _CTX_SNAPSHOT_COUNTER=0
declare -g _CTX_LAST_SNAPSHOT=""
declare -g _CTX_DIRTY=0
declare -gA _CTX_DATA=()
declare -gA _CTX_METADATA=()
declare -g _CTX_EXIT_CLEANUP_REGISTERED=0
declare -g _CTX_PREVIOUS_EXIT_TRAP=""

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Centralized logging
_ctx_log() {
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "agent_context" "$@"
    else
        local level="$1"; shift
        [[ "${MAINFRAME_QUIET:-}" != "1" ]] && printf '[agent_context] %s: %s\n' "$level" "$*" >&2
        :
    fi
}

# Generate ISO timestamp
_ctx_timestamp() {
    date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S
}

# Check if jq is available
_ctx_require_jq() {
    if ! command -v jq &>/dev/null; then
        _ctx_log error "jq is required but not found"
        return 1
    fi
    return 0
}

# Generate unique snapshot ID
_ctx_next_snapshot_id() {
    local target_var="${1:-}"
    local next_snapshot_id

    if [[ -f "${_CTX_SESSION_DIR}/meta.json" ]]; then
        _CTX_SNAPSHOT_COUNTER=$(jq -r '.snapshot_count // 0' "${_CTX_SESSION_DIR}/meta.json" 2>/dev/null || printf '%s' "$_CTX_SNAPSHOT_COUNTER")
    fi

    ((_CTX_SNAPSHOT_COUNTER += 1))
    printf -v next_snapshot_id 'snap_%03d' "$_CTX_SNAPSHOT_COUNTER"

    if [[ -n "$target_var" ]]; then
        printf -v "$target_var" '%s' "$next_snapshot_id"
    else
        printf '%s' "$next_snapshot_id"
    fi
}

# Atomic file write (temp + rename)
_ctx_atomic_write() {
    local target="$1"
    local content="$2"

    local parent_dir="${target%/*}"
    [[ "$parent_dir" != "$target" ]] && mkdir -p "$parent_dir" 2>/dev/null

    local tmpfile
    tmpfile="${target}.tmp.$$"

    if ! printf '%s' "$content" > "$tmpfile"; then
        rm -f "$tmpfile" 2>/dev/null
        return 1
    fi

    if ! mv -f "$tmpfile" "$target"; then
        rm -f "$tmpfile" 2>/dev/null
        return 1
    fi

    return 0
}

# Build JSON from associative array
_ctx_assoc_to_json() {
    local -n arr=$1
    local first=true

    printf '{'
    for key in "${!arr[@]}"; do
        $first || printf ','
        first=false
        # Use jq for proper escaping
        local escaped_key escaped_val
        escaped_key=$(printf '%s' "$key" | jq -Rs '.')
        escaped_val=$(printf '%s' "${arr[$key]}" | jq -Rs '.')
        printf '%s:%s' "$escaped_key" "$escaped_val"
    done
    printf '}'
}

# Parse JSON into associative array
_ctx_json_to_assoc() {
    local json="$1"
    local -n target_arr=$2

    # Clear target array
    target_arr=()

    # Parse each key-value pair
    local key value
    while IFS= read -r key; do
        value=$(printf '%s\n' "$json" | jq -r --arg key "$key" '.[$key]')
        target_arr["$key"]="$value"
    done < <(printf '%s\n' "$json" | jq -r 'keys[]' 2>/dev/null)
}

# Build full context JSON
_ctx_build_json() {
    local data_json metadata_json
    data_json=$(_ctx_assoc_to_json _CTX_DATA)
    metadata_json=$(_ctx_assoc_to_json _CTX_METADATA)

    jq -n \
        --arg session_id "$_CTX_SESSION_ID" \
        --arg created_at "$_CTX_CREATED_AT" \
        --arg updated_at "$_CTX_UPDATED_AT" \
        --argjson version "$_CTX_VERSION" \
        --argjson data "$data_json" \
        --argjson metadata "$metadata_json" \
        '{
            session_id: $session_id,
            created_at: $created_at,
            updated_at: $updated_at,
            version: $version,
            data: $data,
            metadata: $metadata
        }'
}

# Load context from JSON
_ctx_parse_json() {
    local json="$1"

    _CTX_SESSION_ID=$(printf '%s\n' "$json" | jq -r '.session_id // ""')
    _CTX_CREATED_AT=$(printf '%s\n' "$json" | jq -r '.created_at // ""')
    _CTX_UPDATED_AT=$(printf '%s\n' "$json" | jq -r '.updated_at // ""')
    _CTX_VERSION=$(printf '%s\n' "$json" | jq -r '.version // 0')

    local data_json metadata_json
    data_json=$(printf '%s\n' "$json" | jq -c '.data // {}')
    metadata_json=$(printf '%s\n' "$json" | jq -c '.metadata // {}')

    _ctx_json_to_assoc "$data_json" _CTX_DATA
    _ctx_json_to_assoc "$metadata_json" _CTX_METADATA
    _CTX_DIRTY=0
}

# Append to history log
_ctx_log_change() {
    local operation="$1"
    local key="${2:-}"
    local value="${3:-}"

    local history_file="${_CTX_SESSION_DIR}/history.jsonl"
    local entry

    entry=$(jq -cn \
        --arg op "$operation" \
        --arg key "$key" \
        --arg value "$value" \
        --arg timestamp "$(_ctx_timestamp)" \
        --argjson version "$_CTX_VERSION" \
        '{timestamp: $timestamp, version: $version, op: $op, key: $key, value: $value}')

    printf '%s\n' "$entry" >> "$history_file"
}

# Auto-save check
_ctx_check_autosave() {
    ((_CTX_CHANGE_COUNT += 1))
    if [[ $_CTX_CHANGE_COUNT -ge ${MAINFRAME_CONTEXT_AUTOSAVE:-10} ]]; then
        ctx_save
        _CTX_CHANGE_COUNT=0
    fi
}

# Cleanup handler for exit trap
_ctx_cleanup() {
    if [[ -n "$_CTX_SESSION_ID" && ("$_CTX_DIRTY" == "1" || ! -f "${_CTX_SESSION_DIR}/current.json") ]]; then
        ctx_save 2>/dev/null || true
    fi
}

_ctx_get_trap_command() {
    local signal="$1"
    local trap_def

    trap_def=$(trap -p "$signal") || return 0
    [[ -n "$trap_def" ]] || return 0

    trap_def=${trap_def#trap -- \'}
    trap_def=${trap_def%\' "$signal"}
    printf '%s\n' "$trap_def"
}

_ctx_run_exit_cleanup() {
    local exit_code="$1"

    _ctx_cleanup || true

    if [[ -n "${_CTX_PREVIOUS_EXIT_TRAP:-}" ]]; then
        builtin eval -- "$_CTX_PREVIOUS_EXIT_TRAP" || true
    fi

    return "$exit_code"
}

_ctx_install_exit_cleanup() {
    [[ "${_CTX_EXIT_CLEANUP_REGISTERED:-0}" == "1" ]] && return 0

    if declare -F _mainframe_add_exit_trap >/dev/null 2>&1; then
        _mainframe_add_exit_trap "_ctx_cleanup"
    else
        _CTX_PREVIOUS_EXIT_TRAP="$(_ctx_get_trap_command EXIT)"
        trap '_ctx_run_exit_cleanup "$?"' EXIT
    fi

    _CTX_EXIT_CLEANUP_REGISTERED=1
}

# =============================================================================
# SESSION MANAGEMENT
# =============================================================================

# Initialize a new context session
# @pre: jq available
# @post: New session created with empty data
# @idempotent: No - creates new session each time
# @returns: 0 on success, 1 on failure
#
# Usage: ctx_init "session_id"
# Example: ctx_init "agent-task-123"
ctx_init() {
    local session_id="$1"

    if [[ -z "$session_id" ]]; then
        _ctx_log error "ctx_init: session_id required"
        return 1
    fi

    _ctx_require_jq || return 1

    # Initialize state
    _CTX_SESSION_ID="$session_id"
    _CTX_SESSION_DIR="${MAINFRAME_CONTEXT_DIR}/${session_id}"
    _CTX_CREATED_AT=$(_ctx_timestamp)
    _CTX_UPDATED_AT="$_CTX_CREATED_AT"
    _CTX_VERSION=0
    _CTX_CHANGE_COUNT=0
    _CTX_SNAPSHOT_COUNTER=0
    _CTX_LAST_SNAPSHOT=""
    _CTX_DIRTY=1
    _CTX_DATA=()
    _CTX_METADATA=()

    # Create session directory structure
    mkdir -p "${_CTX_SESSION_DIR}/snapshots" 2>/dev/null || {
        _ctx_log error "ctx_init: failed to create session directory"
        return 1
    }

    # Create initial meta.json
    local meta_json
    meta_json=$(jq -cn \
        --arg session_id "$session_id" \
        --arg created_at "$_CTX_CREATED_AT" \
        '{session_id: $session_id, created_at: $created_at, snapshot_count: 0}')

    _ctx_atomic_write "${_CTX_SESSION_DIR}/meta.json" "$meta_json" || return 1

    # Save initial state
    ctx_save || return 1

    # Register cleanup handler
    _ctx_install_exit_cleanup

    _ctx_log debug "ctx_init: created session $session_id"
    return 0
}

# Load an existing context session
# @pre: Session exists on disk
# @post: Session state loaded into memory
# @returns: 0 on success, 1 if session not found
#
# Usage: ctx_load "session_id"
# Example: ctx_load "agent-task-123"
ctx_load() {
    local session_id="$1"

    if [[ -z "$session_id" ]]; then
        _ctx_log error "ctx_load: session_id required"
        return 1
    fi

    _ctx_require_jq || return 1

    local session_dir="${MAINFRAME_CONTEXT_DIR}/${session_id}"
    local current_file="${session_dir}/current.json"

    if [[ ! -f "$current_file" ]]; then
        _ctx_log error "ctx_load: session not found: $session_id"
        return 1
    fi

    # Read and parse current state
    local json
    json=$(<"$current_file")
    _ctx_parse_json "$json"

    _CTX_SESSION_DIR="$session_dir"
    _CTX_CHANGE_COUNT=0

    # Load snapshot counter from meta
    if [[ -f "${session_dir}/meta.json" ]]; then
        _CTX_SNAPSHOT_COUNTER=$(jq -r '.snapshot_count // 0' "${session_dir}/meta.json")
    fi
    _CTX_DIRTY=0

    # Register cleanup handler
    _ctx_install_exit_cleanup

    _ctx_log debug "ctx_load: loaded session $session_id (version $_CTX_VERSION)"
    return 0
}

# Save current context to disk
# @pre: Session initialized
# @post: Current state persisted atomically
# @idempotent: Yes
# @returns: 0 on success, 1 on failure
#
# Usage: ctx_save
ctx_save() {
    if [[ -z "$_CTX_SESSION_ID" ]]; then
        _ctx_log error "ctx_save: no active session"
        return 1
    fi

    _CTX_UPDATED_AT=$(_ctx_timestamp)
    ((_CTX_VERSION += 1))

    local json
    json=$(_ctx_build_json)

    _ctx_atomic_write "${_CTX_SESSION_DIR}/current.json" "$json" || {
        _ctx_log error "ctx_save: failed to write state"
        return 1
    }

    _ctx_log_change "save" "" ""
    _CTX_DIRTY=0
    _ctx_log debug "ctx_save: saved version $_CTX_VERSION"
    return 0
}

# Close and cleanup the current session
# @pre: Session initialized
# @post: Session saved and state cleared
# @returns: 0 on success
#
# Usage: ctx_close
ctx_close() {
    if [[ -z "$_CTX_SESSION_ID" ]]; then
        return 0  # No session to close
    fi

    # Final save
    if [[ "$_CTX_DIRTY" == "1" || ! -f "${_CTX_SESSION_DIR}/current.json" ]]; then
        ctx_save 2>/dev/null || true
    fi

    # Update meta
    if [[ -f "${_CTX_SESSION_DIR}/meta.json" ]]; then
        local meta
        meta=$(jq \
            --arg closed_at "$(_ctx_timestamp)" \
            --argjson snapshot_count "$_CTX_SNAPSHOT_COUNTER" \
            '. + {closed_at: $closed_at, snapshot_count: $snapshot_count}' \
            "${_CTX_SESSION_DIR}/meta.json")
        _ctx_atomic_write "${_CTX_SESSION_DIR}/meta.json" "$meta"
    fi

    local session_id="$_CTX_SESSION_ID"

    # Clear state
    _CTX_SESSION_ID=""
    _CTX_SESSION_DIR=""
    _CTX_VERSION=0
    _CTX_CHANGE_COUNT=0
    _CTX_CREATED_AT=""
    _CTX_UPDATED_AT=""
    _CTX_SNAPSHOT_COUNTER=0
    _CTX_LAST_SNAPSHOT=""
    _CTX_DIRTY=0
    _CTX_DATA=()
    _CTX_METADATA=()

    _ctx_log debug "ctx_close: closed session $session_id"
    return 0
}

# =============================================================================
# DATA OPERATIONS
# =============================================================================

# Set a value in the context
# @pre: Session initialized
# @post: Key-value stored, version incremented
# @returns: 0 on success, 1 on failure
#
# Usage: ctx_set "key" "value"
# Example: ctx_set "current_task" "research"
ctx_set() {
    local key="$1"
    local value="$2"

    if [[ -z "$_CTX_SESSION_ID" ]]; then
        _ctx_log error "ctx_set: no active session"
        return 1
    fi

    if [[ -z "$key" ]]; then
        _ctx_log error "ctx_set: key required"
        return 1
    fi

    _CTX_DATA["$key"]="$value"
    _CTX_DIRTY=1
    _ctx_log_change "set" "$key" "$value"
    _ctx_check_autosave

    return 0
}

# Get a value from the context
# @pre: Session initialized
# @post: Outputs value or empty string
# @returns: 0 on success (key exists), 1 if key not found
#
# Usage: ctx_get "key"
# Example: value=$(ctx_get "current_task")
ctx_get() {
    local key="$1"

    if [[ -z "$_CTX_SESSION_ID" ]]; then
        _ctx_log error "ctx_get: no active session"
        return 1
    fi

    if [[ -z "$key" ]]; then
        _ctx_log error "ctx_get: key required"
        return 1
    fi

    if [[ -v "_CTX_DATA[$key]" ]]; then
        printf '%s' "${_CTX_DATA[$key]}"
        return 0
    fi

    return 1
}

# Delete a key from the context
# @pre: Session initialized
# @post: Key removed if it existed
# @returns: 0 on success, 1 if key not found
#
# Usage: ctx_delete "key"
# Example: ctx_delete "temporary_data"
ctx_delete() {
    local key="$1"

    if [[ -z "$_CTX_SESSION_ID" ]]; then
        _ctx_log error "ctx_delete: no active session"
        return 1
    fi

    if [[ -z "$key" ]]; then
        _ctx_log error "ctx_delete: key required"
        return 1
    fi

    if [[ -v "_CTX_DATA[$key]" ]]; then
        unset "_CTX_DATA[$key]"
        _CTX_DIRTY=1
        _ctx_log_change "delete" "$key" ""
        _ctx_check_autosave
        return 0
    fi

    return 1
}

# List all keys in the context
# @pre: Session initialized
# @post: Outputs keys, one per line
# @returns: 0 on success
#
# Usage: ctx_list_keys
# Example: keys=$(ctx_list_keys)
ctx_list_keys() {
    if [[ -z "$_CTX_SESSION_ID" ]]; then
        _ctx_log error "ctx_list_keys: no active session"
        return 1
    fi

    local key
    for key in "${!_CTX_DATA[@]}"; do
        printf '%s\n' "$key"
    done

    return 0
}

# Clear all data (keep session)
# @pre: Session initialized
# @post: All data cleared, session persists
# @returns: 0 on success
#
# Usage: ctx_clear
ctx_clear() {
    if [[ -z "$_CTX_SESSION_ID" ]]; then
        _ctx_log error "ctx_clear: no active session"
        return 1
    fi

    _CTX_DATA=()
    _CTX_DIRTY=1
    _ctx_log_change "clear" "" ""
    ctx_save

    _ctx_log debug "ctx_clear: cleared all data"
    return 0
}

# =============================================================================
# SNAPSHOT OPERATIONS
# =============================================================================

# Create a point-in-time snapshot
# @pre: Session initialized
# @post: Snapshot saved to disk
# @returns: 0 on success, outputs snapshot ID
#
# Usage: snapshot_id=$(ctx_snapshot)
# Example: snap=$(ctx_snapshot)
ctx_snapshot() {
    if [[ -z "$_CTX_SESSION_ID" ]]; then
        _ctx_log error "ctx_snapshot: no active session"
        return 1
    fi

    # Ensure current state is saved
    ctx_save || return 1

    local snapshot_id
    _ctx_next_snapshot_id snapshot_id
    local snapshot_file="${_CTX_SESSION_DIR}/snapshots/${snapshot_id}.json"

    # Copy current state to snapshot
    local json
    json=$(_ctx_build_json)

    # Add snapshot metadata
    json=$(printf '%s\n' "$json" | jq \
        --arg snapshot_id "$snapshot_id" \
        --arg snapshot_at "$(_ctx_timestamp)" \
        '. + {snapshot_id: $snapshot_id, snapshot_at: $snapshot_at}')

    _ctx_atomic_write "$snapshot_file" "$json" || {
        _ctx_log error "ctx_snapshot: failed to create snapshot"
        return 1
    }

    _CTX_LAST_SNAPSHOT="$snapshot_id"
    _ctx_log_change "snapshot" "$snapshot_id" ""

    # Update meta with snapshot count
    if [[ -f "${_CTX_SESSION_DIR}/meta.json" ]]; then
        local meta
        meta=$(jq --argjson count "$_CTX_SNAPSHOT_COUNTER" \
            '.snapshot_count = $count' "${_CTX_SESSION_DIR}/meta.json")
        _ctx_atomic_write "${_CTX_SESSION_DIR}/meta.json" "$meta"
    fi

    printf '%s' "$snapshot_id"
    _ctx_log debug "ctx_snapshot: created $snapshot_id"
    return 0
}

# Restore from a snapshot
# @pre: Session initialized, snapshot exists
# @post: State restored from snapshot
# @returns: 0 on success, 1 if snapshot not found
#
# Usage: ctx_restore "snapshot_id"
# Example: ctx_restore "snap_001"
ctx_restore() {
    local snapshot_id="$1"

    if [[ -z "$_CTX_SESSION_ID" ]]; then
        _ctx_log error "ctx_restore: no active session"
        return 1
    fi

    if [[ -z "$snapshot_id" ]]; then
        _ctx_log error "ctx_restore: snapshot_id required"
        return 1
    fi

    local snapshot_file="${_CTX_SESSION_DIR}/snapshots/${snapshot_id}.json"

    if [[ ! -f "$snapshot_file" ]]; then
        _ctx_log error "ctx_restore: snapshot not found: $snapshot_id"
        return 1
    fi

    # Load snapshot data (preserving session ID and directory)
    local session_id="$_CTX_SESSION_ID"
    local session_dir="$_CTX_SESSION_DIR"

    local json
    json=$(<"$snapshot_file")
    _ctx_parse_json "$json"

    _CTX_SESSION_ID="$session_id"
    _CTX_SESSION_DIR="$session_dir"

    _ctx_log_change "restore" "$snapshot_id" ""
    ctx_save

    _ctx_log debug "ctx_restore: restored from $snapshot_id"
    return 0
}

# Compare current state to a snapshot
# @pre: Session initialized, snapshot exists
# @post: Outputs diff as JSON
# @returns: 0 on success, 1 if snapshot not found
#
# Usage: ctx_diff "snapshot_id"
# Example: diff_json=$(ctx_diff "snap_001")
ctx_diff() {
    local snapshot_id="$1"

    if [[ -z "$_CTX_SESSION_ID" ]]; then
        _ctx_log error "ctx_diff: no active session"
        return 1
    fi

    if [[ -z "$snapshot_id" ]]; then
        _ctx_log error "ctx_diff: snapshot_id required"
        return 1
    fi

    local snapshot_file="${_CTX_SESSION_DIR}/snapshots/${snapshot_id}.json"

    if [[ ! -f "$snapshot_file" ]]; then
        _ctx_log error "ctx_diff: snapshot not found: $snapshot_id"
        return 1
    fi

    local current_json snapshot_json
    current_json=$(_ctx_build_json)
    snapshot_json=$(<"$snapshot_file")

    # Extract data objects
    local current_data snapshot_data
    current_data=$(printf '%s\n' "$current_json" | jq -c '.data')
    snapshot_data=$(printf '%s\n' "$snapshot_json" | jq -c '.data')

    # Compute differences
    local added removed changed

    # Keys only in current
    added=$(jq -cn --argjson cur "$current_data" --argjson snap "$snapshot_data" \
        '[$cur | keys[] | select(. as $k | $snap | has($k) | not)]')

    # Keys only in snapshot
    removed=$(jq -cn --argjson cur "$current_data" --argjson snap "$snapshot_data" \
        '[$snap | keys[] | select(. as $k | $cur | has($k) | not)]')

    # Keys with different values
    changed=$(jq -cn --argjson cur "$current_data" --argjson snap "$snapshot_data" \
        '[$cur | keys[] | select(. as $k | $snap | has($k) and ($cur[$k] != $snap[$k]))]')

    jq -cn \
        --argjson added "$added" \
        --argjson removed "$removed" \
        --argjson changed "$changed" \
        '{added: $added, removed: $removed, changed: $changed}'

    return 0
}

# Rollback to the last snapshot
# @pre: Session initialized, at least one snapshot exists
# @post: State restored from last snapshot
# @returns: 0 on success, 1 if no snapshots
#
# Usage: ctx_rollback
ctx_rollback() {
    if [[ -z "$_CTX_SESSION_ID" ]]; then
        _ctx_log error "ctx_rollback: no active session"
        return 1
    fi

    if [[ -z "$_CTX_LAST_SNAPSHOT" ]]; then
        # Find most recent snapshot
        local latest
        latest=$(ls -1 "${_CTX_SESSION_DIR}/snapshots/"*.json 2>/dev/null | sort -V | tail -1)

        if [[ -z "$latest" ]]; then
            _ctx_log error "ctx_rollback: no snapshots available"
            return 1
        fi

        _CTX_LAST_SNAPSHOT=$(basename "$latest" .json)
    fi

    ctx_restore "$_CTX_LAST_SNAPSHOT"
}

# =============================================================================
# IMPORT/EXPORT OPERATIONS
# =============================================================================

# Export context to a JSON file
# @pre: Session initialized
# @post: Context exported to specified file
# @returns: 0 on success, 1 on failure
#
# Usage: ctx_export "/path/to/file.json"
# Example: ctx_export "/tmp/backup.json"
ctx_export() {
    local target_file="$1"

    if [[ -z "$_CTX_SESSION_ID" ]]; then
        _ctx_log error "ctx_export: no active session"
        return 1
    fi

    if [[ -z "$target_file" ]]; then
        _ctx_log error "ctx_export: target file required"
        return 1
    fi

    local json
    json=$(_ctx_build_json)

    _ctx_atomic_write "$target_file" "$json" || {
        _ctx_log error "ctx_export: failed to write file"
        return 1
    }

    _ctx_log debug "ctx_export: exported to $target_file"
    return 0
}

# Import context from a JSON file
# @pre: Session initialized, file exists
# @post: Context data merged from file
# @returns: 0 on success, 1 on failure
#
# Usage: ctx_import "/path/to/file.json"
# Example: ctx_import "/tmp/backup.json"
ctx_import() {
    local source_file="$1"

    if [[ -z "$_CTX_SESSION_ID" ]]; then
        _ctx_log error "ctx_import: no active session"
        return 1
    fi

    if [[ -z "$source_file" ]]; then
        _ctx_log error "ctx_import: source file required"
        return 1
    fi

    if [[ ! -f "$source_file" ]]; then
        _ctx_log error "ctx_import: file not found: $source_file"
        return 1
    fi

    local json
    json=$(<"$source_file")

    # Validate JSON
    if ! printf '%s\n' "$json" | jq empty >/dev/null 2>&1; then
        _ctx_log error "ctx_import: invalid JSON in file"
        return 1
    fi

    # Extract and import data
    local data_json
    data_json=$(printf '%s\n' "$json" | jq -c '.data // {}')

    local -A import_data=()
    _ctx_json_to_assoc "$data_json" import_data

    # Merge into current data
    for key in "${!import_data[@]}"; do
        _CTX_DATA["$key"]="${import_data[$key]}"
    done

    _CTX_DIRTY=1
    _ctx_log_change "import" "$source_file" ""
    ctx_save

    _ctx_log debug "ctx_import: imported from $source_file"
    return 0
}

# Merge another session's context into this one
# @pre: Session initialized, other session exists
# @post: Other session's data merged into current
# @returns: 0 on success, 1 on failure
#
# Usage: ctx_merge "other_session_id"
# Example: ctx_merge "agent-subtask-456"
ctx_merge() {
    local other_session_id="$1"

    if [[ -z "$_CTX_SESSION_ID" ]]; then
        _ctx_log error "ctx_merge: no active session"
        return 1
    fi

    if [[ -z "$other_session_id" ]]; then
        _ctx_log error "ctx_merge: other_session_id required"
        return 1
    fi

    local other_file="${MAINFRAME_CONTEXT_DIR}/${other_session_id}/current.json"

    if [[ ! -f "$other_file" ]]; then
        _ctx_log error "ctx_merge: session not found: $other_session_id"
        return 1
    fi

    local other_json
    other_json=$(<"$other_file")

    local other_data
    other_data=$(printf '%s\n' "$other_json" | jq -c '.data // {}')

    local -A merge_data=()
    _ctx_json_to_assoc "$other_data" merge_data

    # Merge into current data
    for key in "${!merge_data[@]}"; do
        _CTX_DATA["$key"]="${merge_data[$key]}"
    done

    _CTX_DIRTY=1
    _ctx_log_change "merge" "$other_session_id" ""
    ctx_save

    _ctx_log debug "ctx_merge: merged from $other_session_id"
    return 0
}

# =============================================================================
# METADATA OPERATIONS
# =============================================================================

# Set metadata value
# @pre: Session initialized
# @post: Metadata key-value stored
# @returns: 0 on success
#
# Usage: ctx_set_meta "key" "value"
# Example: ctx_set_meta "agent_type" "researcher"
ctx_set_meta() {
    local key="$1"
    local value="$2"

    if [[ -z "$_CTX_SESSION_ID" ]]; then
        _ctx_log error "ctx_set_meta: no active session"
        return 1
    fi

    if [[ -z "$key" ]]; then
        _ctx_log error "ctx_set_meta: key required"
        return 1
    fi

    _CTX_METADATA["$key"]="$value"
    _CTX_DIRTY=1
    return 0
}

# Get metadata value
# @pre: Session initialized
# @post: Outputs metadata value
# @returns: 0 if found, 1 if not
#
# Usage: ctx_get_meta "key"
# Example: agent_type=$(ctx_get_meta "agent_type")
ctx_get_meta() {
    local key="$1"

    if [[ -z "$_CTX_SESSION_ID" ]]; then
        _ctx_log error "ctx_get_meta: no active session"
        return 1
    fi

    if [[ -v "_CTX_METADATA[$key]" ]]; then
        printf '%s' "${_CTX_METADATA[$key]}"
        return 0
    fi

    return 1
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get current session ID
# @returns: 0 with session ID, 1 if no session
#
# Usage: session=$(ctx_session)
ctx_session() {
    if [[ -z "$_CTX_SESSION_ID" ]]; then
        return 1
    fi
    printf '%s' "$_CTX_SESSION_ID"
    return 0
}

# Get current version
# @returns: 0 with version, 1 if no session
#
# Usage: version=$(ctx_version)
ctx_version() {
    if [[ -z "$_CTX_SESSION_ID" ]]; then
        return 1
    fi
    printf '%d' "$_CTX_VERSION"
    return 0
}

# Get full context as JSON
# @returns: 0 with JSON, 1 if no session
#
# Usage: json=$(ctx_json)
ctx_json() {
    if [[ -z "$_CTX_SESSION_ID" ]]; then
        _ctx_log error "ctx_json: no active session"
        return 1
    fi
    _ctx_build_json
    return 0
}

# List available snapshots
# @returns: 0 with snapshot list, 1 if no session
#
# Usage: ctx_snapshots
ctx_snapshots() {
    if [[ -z "$_CTX_SESSION_ID" ]]; then
        _ctx_log error "ctx_snapshots: no active session"
        return 1
    fi

    local snap
    for snap in "${_CTX_SESSION_DIR}/snapshots/"*.json; do
        [[ -f "$snap" ]] || continue
        basename "$snap" .json
    done

    return 0
}

# Check if session exists
# @returns: 0 if exists, 1 if not
#
# Usage: ctx_exists "session_id" && echo "exists"
ctx_exists() {
    local session_id="$1"
    [[ -f "${MAINFRAME_CONTEXT_DIR}/${session_id}/current.json" ]]
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

_AGENT_CONTEXT_EXPORTS=(
    # Session management
    ctx_init
    ctx_load
    ctx_save
    ctx_close
    # Data operations
    ctx_set
    ctx_get
    ctx_delete
    ctx_list_keys
    ctx_clear
    # Snapshot operations
    ctx_snapshot
    ctx_restore
    ctx_diff
    ctx_rollback
    # Import/export
    ctx_export
    ctx_import
    ctx_merge
    # Metadata
    ctx_set_meta
    ctx_get_meta
    # Utilities
    ctx_session
    ctx_version
    ctx_json
    ctx_snapshots
    ctx_exists
)

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/progress.sh - Progress Broadcasting for AI Agents
# =============================================================================
# Description: File-based progress broadcasting for long-running operations,
#              enabling AI agents to monitor task status across processes.
#
# Features:
#   - Stateful progress tracking with unique IDs
#   - Stateless one-shot progress emission
#   - File-based coordination for multi-agent scenarios
#   - Heartbeat mechanism for long-running operations
#   - USOP JSON output format
#
# Version: 6.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_PROGRESS_LOADED:-}" ]] && return 0
readonly _MAINFRAME_PROGRESS_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

# shellcheck source=./common.sh
source "${MAINFRAME_ROOT:-${HOME}/.mainframe}/lib/common.sh" 2>/dev/null || true
# shellcheck source=./validation.sh
source "${MAINFRAME_ROOT:-${HOME}/.mainframe}/lib/validation.sh" 2>/dev/null || true
# shellcheck source=./json.sh
source "${MAINFRAME_ROOT:-${HOME}/.mainframe}/lib/json.sh" 2>/dev/null || true
# shellcheck source=./output.sh
source "${MAINFRAME_ROOT:-${HOME}/.mainframe}/lib/output.sh" 2>/dev/null || true

# =============================================================================
# CONFIGURATION
# =============================================================================

# Progress file storage directory
MAINFRAME_PROGRESS_DIR="${MAINFRAME_PROGRESS_DIR:-${TMPDIR:-/tmp}/mainframe_progress}"

# Quota settings to prevent disk exhaustion
readonly PROGRESS_MAX_FILES="${PROGRESS_MAX_FILES:-100}"
readonly PROGRESS_MAX_SIZE_KB="${PROGRESS_MAX_SIZE_KB:-1024}"
readonly PROGRESS_FILE_MAX_KB="${PROGRESS_FILE_MAX_KB:-10}"
readonly PROGRESS_MAX_AGE_MINUTES="${PROGRESS_MAX_AGE_MINUTES:-60}"

# Broadcast targets: stderr|stdout|file|all
MAINFRAME_BROADCAST_TARGET="${MAINFRAME_BROADCAST_TARGET:-stderr}"
MAINFRAME_BROADCAST_FORMAT="${MAINFRAME_BROADCAST_FORMAT:-json}"
MAINFRAME_BROADCAST_FILE="${MAINFRAME_BROADCAST_FILE:-}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Progress tracker state (associative arrays)
declare -gA _PROGRESS_NAME        # [id] -> operation name
declare -gA _PROGRESS_CURRENT     # [id] -> current value
declare -gA _PROGRESS_TOTAL       # [id] -> total value
declare -gA _PROGRESS_MESSAGE     # [id] -> current message
declare -gA _PROGRESS_STARTED     # [id] -> start timestamp (epoch)
declare -gA _PROGRESS_UNIT        # [id] -> unit label
declare -gA _PROGRESS_STATUS      # [id] -> active|complete|failed

# Sensitive information patterns to redact
readonly -a _PROGRESS_REDACT_PATTERNS=(
    'password[[:space:]]*[=:][[:space:]]*[^[:space:]]+'
    'api[_-]?key[[:space:]]*[=:][[:space:]]*[^[:space:]]+'
    'token[[:space:]]*[=:][[:space:]]*[^[:space:]]+'
    '/etc/(shadow|passwd|sudoers)'
    '\.ssh/.*_rsa'
    '\.env'
    'credentials?\.(json|yaml|conf)'
    'secret[[:space:]]*[=:][[:space:]]*[^[:space:]]+'
)

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Generate unique progress ID
# Combines PID, RANDOM, and microseconds for uniqueness
_progress_gen_id() {
    local prefix="${1:-prog}"
    local rand
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        rand="${EPOCHREALTIME//./}"
        rand="${rand: -6}"
    else
        rand="$RANDOM$RANDOM"
    fi
    printf '%s_%s_%s' "$prefix" "$$" "$rand"
}

# Get current timestamp in seconds with optional fractional precision
_progress_now() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        printf '%s' "$EPOCHREALTIME"
    elif command -v date &>/dev/null; then
        date +%s.%N 2>/dev/null || date +%s
    else
        printf '%s' "${EPOCHSECONDS:-0}"
    fi
}

# Get integer timestamp (epoch seconds)
_progress_now_epoch() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    else
        date +%s 2>/dev/null || printf '0'
    fi
}

# Escape string for JSON embedding
# Uses json.sh if available, otherwise internal implementation
_progress_escape_json() {
    local str="$1"

    # Try json_escape from json.sh
    if declare -f json_escape &>/dev/null; then
        json_escape "$str"
        return
    fi

    # Internal fallback
    local result=""
    local i char
    for ((i=0; i<${#str}; i++)); do
        char="${str:i:1}"
        case "$char" in
            '"')  result+='\"' ;;
            '\')  result+='\\' ;;
            $'\b') result+='\b' ;;
            $'\f') result+='\f' ;;
            $'\n') result+='\n' ;;
            $'\r') result+='\r' ;;
            $'\t') result+='\t' ;;
            *)
                if [[ "$char" < $'\x20' ]]; then
                    printf -v char '\\u%04x' "'$char"
                fi
                result+="$char"
                ;;
        esac
    done
    printf '%s' "$result"
}

# Redact sensitive information from messages
_progress_redact() {
    local message="$1"
    local pattern

    for pattern in "${_PROGRESS_REDACT_PATTERNS[@]}"; do
        local redacted
        if redacted=$(printf '%s' "$message" | sed -E "s#${pattern}#[REDACTED]#g" 2>/dev/null); then
            message="$redacted"
        fi
    done

    printf '%s' "$message"
}

# Validate progress ID format (prevent path traversal)
# Only allows alphanumeric, dash, underscore
_progress_validate_id() {
    local id="$1"

    # Reject empty
    [[ -z "$id" ]] && return 1

    # Reject path traversal
    [[ "$id" == *".."* ]] && return 1
    [[ "$id" == *"/"* ]] && return 1
    [[ "$id" == *"\\"* ]] && return 1

    # Allow only safe characters
    [[ "$id" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1

    # Length limit
    [[ ${#id} -le 64 ]] || return 1

    return 0
}

# Initialize progress directory with proper permissions
_progress_init_dir() {
    if [[ ! -d "$MAINFRAME_PROGRESS_DIR" ]]; then
        mkdir -p "$MAINFRAME_PROGRESS_DIR" 2>/dev/null || return 1
        chmod 700 "$MAINFRAME_PROGRESS_DIR" 2>/dev/null || true
    fi

    # Verify not a symlink (security)
    if [[ -L "$MAINFRAME_PROGRESS_DIR" ]]; then
        return 1
    fi

    return 0
}

_progress_tracker_file() {
    local id="$1"
    printf '%s/%s.progress' "$MAINFRAME_PROGRESS_DIR" "$id"
}

_progress_oldest_progress_files() {
    local dir="$1"
    local -a files=("$dir"/*.progress)
    [[ -e "${files[0]}" ]] || return 0
    ls -1tr "${files[@]}" 2>/dev/null || true
}

_progress_snapshot_json() {
    local id="$1"
    local current="${_PROGRESS_CURRENT[$id]:-0}"
    local total="${_PROGRESS_TOTAL[$id]:-0}"
    local name="${_PROGRESS_NAME[$id]:-unknown}"
    local message="${_PROGRESS_MESSAGE[$id]:-}"
    local status="${_PROGRESS_STATUS[$id]:-active}"
    local started="${_PROGRESS_STARTED[$id]:-0}"
    local unit="${_PROGRESS_UNIT[$id]:-items}"

    local now percent
    now=$(_progress_now_epoch)
    percent=0
    if [[ "$total" -gt 0 ]]; then
        percent=$(( current * 100 / total ))
    fi

    local safe_name safe_message
    safe_name=$(_progress_redact "$name")
    safe_message=$(_progress_redact "$message")

    local escaped_name escaped_message escaped_status escaped_unit
    escaped_name=$(_progress_escape_json "$safe_name")
    escaped_message=$(_progress_escape_json "$safe_message")
    escaped_status=$(_progress_escape_json "$status")
    escaped_unit=$(_progress_escape_json "$unit")

    printf '{"id":"%s","name":"%s","current":%d,"total":%d,"percent":%d,"message":"%s","status":"%s","unit":"%s","started":%d,"updated":%d}' \
        "$id" \
        "$escaped_name" \
        "$current" \
        "$total" \
        "$percent" \
        "$escaped_message" \
        "$escaped_status" \
        "$escaped_unit" \
        "$started" \
        "$now"
}

_progress_write_state() {
    local id="$1"
    local filepath="${2:-$(_progress_tracker_file "$id")}"

    _progress_init_dir || return 1

    local content
    content=$(_progress_snapshot_json "$id")

    local tmpfile="${filepath}.tmp.$$"
    if printf '%s\n' "$content" > "$tmpfile" 2>/dev/null; then
        mv -f "$tmpfile" "$filepath" 2>/dev/null || {
            rm -f "$tmpfile" 2>/dev/null
            return 1
        }
        return 0
    fi

    rm -f "$tmpfile" 2>/dev/null
    return 1
}

_progress_load_state() {
    local id="$1"
    local filepath="${2:-$(_progress_tracker_file "$id")}"
    local content

    [[ -f "$filepath" && ! -L "$filepath" ]] || return 1
    content=$(<"$filepath") || return 1

    if declare -F json_get &>/dev/null; then
        _PROGRESS_NAME["$id"]="$(json_get "$content" "name")"
        _PROGRESS_CURRENT["$id"]="$(json_get "$content" "current")"
        _PROGRESS_TOTAL["$id"]="$(json_get "$content" "total")"
        _PROGRESS_MESSAGE["$id"]="$(json_get "$content" "message")"
        _PROGRESS_STATUS["$id"]="$(json_get "$content" "status")"
        _PROGRESS_STARTED["$id"]="$(json_get "$content" "started")"
        _PROGRESS_UNIT["$id"]="$(json_get "$content" "unit")"
        return 0
    fi

    return 1
}

# Enforce quota to prevent disk exhaustion
_progress_enforce_quota() {
    local dir="$MAINFRAME_PROGRESS_DIR"
    [[ ! -d "$dir" ]] && return 0

    # Count files
    local count
    count=$(find "$dir" -maxdepth 1 -name "*.progress" 2>/dev/null | wc -l) || count=0

    if (( count > PROGRESS_MAX_FILES )); then
        # Remove oldest files
        _progress_oldest_progress_files "$dir" | head -n "$((count - PROGRESS_MAX_FILES + 10))" | \
            xargs rm -f 2>/dev/null || true
    fi

    # Check total size
    local size_kb
    size_kb=$(du -sk "$dir" 2>/dev/null | cut -f1) || size_kb=0

    if (( size_kb > PROGRESS_MAX_SIZE_KB )); then
        # Remove oldest until under limit
        while (( $(du -sk "$dir" 2>/dev/null | cut -f1 || echo 0) > PROGRESS_MAX_SIZE_KB / 2 )); do
            local oldest
            oldest=$(_progress_oldest_progress_files "$dir" | head -1)
            [[ -n "$oldest" ]] && rm -f "$oldest" 2>/dev/null
            [[ -z "$oldest" ]] && break
        done
    fi

    # Remove old files
    find "$dir" -maxdepth 1 -name "*.progress" -mmin "+${PROGRESS_MAX_AGE_MINUTES}" \
        -exec rm -f {} \; 2>/dev/null || true
}

# Emit to configured broadcast targets
_progress_emit() {
    local json="$1"
    local targets
    IFS=',' read -ra targets <<< "$MAINFRAME_BROADCAST_TARGET"

    for target in "${targets[@]}"; do
        case "$target" in
            stderr)
                printf '%s\n' "$json" >&2
                ;;
            stdout)
                printf '%s\n' "$json"
                ;;
            file)
                if [[ -n "$MAINFRAME_BROADCAST_FILE" ]]; then
                    printf '%s\n' "$json" >> "$MAINFRAME_BROADCAST_FILE" 2>/dev/null || true
                fi
                ;;
            all)
                printf '%s\n' "$json" >&2
                printf '%s\n' "$json"
                if [[ -n "$MAINFRAME_BROADCAST_FILE" ]]; then
                    printf '%s\n' "$json" >> "$MAINFRAME_BROADCAST_FILE" 2>/dev/null || true
                fi
                ;;
        esac
    done
}

# =============================================================================
# PUBLIC API - PROGRESS TRACKING
# =============================================================================

# Initialize a new progress tracker
# @description Create a stateful progress tracker for long-running operations
# @pre        None
# @post       Progress tracker created with unique ID, start event emitted
# @idempotent No - creates new tracker each call
# @param      $1 name - Human-readable operation name
# @param      $2 total - Total units of work (use 0 for indeterminate)
# @param      --id - Optional custom ID (default: auto-generated)
# @param      --unit - Unit label (default: "items")
# @stdout     Progress tracker ID
# @return     0 on success, 1 on invalid input
#
# Usage: pid=$(progress_init "Building" 100)
# Usage: pid=$(progress_init "Downloading" 1024 --unit "MB")
progress_init() {
    local name="$1"
    local total="${2:-0}"
    shift 2 2>/dev/null || shift $#

    local id="" unit="items"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id)
                id="$2"
                shift 2
                ;;
            --unit)
                unit="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Validate total is a number
    if ! [[ "$total" =~ ^[0-9]+$ ]]; then
        total=0
    fi

    # Generate or validate ID
    if [[ -z "$id" ]]; then
        id=$(_progress_gen_id)
    else
        if ! _progress_validate_id "$id"; then
            if [[ "$MAINFRAME_BROADCAST_FORMAT" == "json" ]]; then
                printf '{"ok":false,"error":{"code":"E_INVALID_ID","msg":"Invalid progress ID format"}}'
            fi
            return 1
        fi
    fi

    # Get timestamp
    local now
    now=$(_progress_now_epoch)

    # Store state
    _PROGRESS_NAME["$id"]="$name"
    _PROGRESS_CURRENT["$id"]=0
    _PROGRESS_TOTAL["$id"]="$total"
    _PROGRESS_MESSAGE["$id"]=""
    _PROGRESS_STARTED["$id"]="$now"
    _PROGRESS_UNIT["$id"]="$unit"
    _PROGRESS_STATUS["$id"]="active"

    _progress_write_state "$id" || return 1

    # Redact name for output
    local safe_name
    safe_name=$(_progress_redact "$name")

    # Emit start event
    if [[ "$MAINFRAME_BROADCAST_FORMAT" == "json" ]]; then
        local escaped_name escaped_unit
        escaped_name=$(_progress_escape_json "$safe_name")
        escaped_unit=$(_progress_escape_json "$unit")
        local progress_json
        progress_json="{\"event\":\"progress_start\",\"id\":\"$id\",\"name\":\"$escaped_name\",\"total\":$total,\"unit\":\"$escaped_unit\",\"timestamp\":$now}"

        # progress_init returns the tracker ID on stdout, so emit start
        # notifications to stderr/file targets only.
        local original_target="$MAINFRAME_BROADCAST_TARGET"
        case ",$MAINFRAME_BROADCAST_TARGET," in
            *,all,*)
                MAINFRAME_BROADCAST_TARGET="stderr,file"
                ;;
            *,stdout,*)
                MAINFRAME_BROADCAST_TARGET="stderr"
                ;;
        esac
        _progress_emit "$progress_json"
        MAINFRAME_BROADCAST_TARGET="$original_target"
    fi

    printf '%s' "$id"
}

# Update progress with current value and optional message
# @description Update a progress tracker with new value
# @pre        Progress tracker exists (from progress_init)
# @post       Progress broadcast to configured targets
# @idempotent Yes - updates to same value are no-op
# @param      $1 id - Progress tracker ID
# @param      $2 current - Current progress value
# @param      $3 [message] - Optional status message
# @stdout     None (broadcasts to configured targets)
# @return     0 on success, 1 if tracker not found
#
# Usage: progress_update "$pid" 50 "Halfway done"
progress_update() {
    local id="$1"
    local value="${2:-0}"
    local message="${3:-}"

    # Validate ID exists
    if [[ -z "${_PROGRESS_TOTAL[$id]:-}" ]]; then
        _progress_load_state "$id" >/dev/null 2>&1 || true
    fi
    if [[ -z "${_PROGRESS_TOTAL[$id]:-}" ]]; then
        if [[ "$MAINFRAME_BROADCAST_FORMAT" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_NOT_FOUND","msg":"Progress tracker not found"}}'
        fi
        return 1
    fi

    # Validate value is a number
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        value=0
    fi

    # Update state
    _PROGRESS_CURRENT["$id"]="$value"
    if [[ -n "$message" ]]; then
        _PROGRESS_MESSAGE["$id"]="$message"
    fi

    _progress_write_state "$id" || return 1

    # Calculate percentage
    local total="${_PROGRESS_TOTAL[$id]}"
    local percent=0
    if [[ "$total" -gt 0 ]]; then
        percent=$(( value * 100 / total ))
    fi

    # Get timestamp
    local now
    now=$(_progress_now_epoch)

    # Redact message
    local safe_message
    safe_message=$(_progress_redact "${_PROGRESS_MESSAGE[$id]}")

    # Emit update event
    if [[ "$MAINFRAME_BROADCAST_FORMAT" == "json" ]]; then
        local escaped_msg
        escaped_msg=$(_progress_escape_json "$safe_message")

        _progress_emit "{\"event\":\"progress_update\",\"id\":\"$id\",\"current\":$value,\"total\":$total,\"percent\":$percent,\"message\":\"$escaped_msg\",\"timestamp\":$now}"
    else
        printf '\r[%s] %d/%d (%d%%) %s' "${_PROGRESS_NAME[$id]}" "$value" "$total" "$percent" "$safe_message" >&2
    fi

    return 0
}

# Increment progress by N
# @description Increment progress by a given amount
# @pre        Progress tracker exists
# @post       Progress value increased by increment, update broadcast
# @idempotent No - increments each call
# @param      $1 id - Progress tracker ID
# @param      $2 [increment] - Amount to increment (default: 1)
# @param      $3 [message] - Optional status message
# @return     0 on success, 1 if tracker not found
#
# Usage: progress_increment "$pid"
# Usage: progress_increment "$pid" 5 "Processed batch"
progress_increment() {
    local id="$1"
    local increment="${2:-1}"
    local message="${3:-}"

    # Validate ID exists
    if [[ -z "${_PROGRESS_CURRENT[$id]:-}" ]]; then
        _progress_load_state "$id" >/dev/null 2>&1 || true
    fi
    if [[ -z "${_PROGRESS_CURRENT[$id]:-}" ]]; then
        return 1
    fi

    # Validate increment is a number
    if ! [[ "$increment" =~ ^[0-9]+$ ]]; then
        increment=1
    fi

    # Calculate new value
    local current="${_PROGRESS_CURRENT[$id]}"
    local new_value=$((current + increment))

    # Call update
    progress_update "$id" "$new_value" "$message"
}

# Mark progress as complete
# @description Mark a progress tracker as complete (success)
# @pre        Progress tracker exists
# @post       Final progress broadcast, tracker marked complete
# @idempotent Yes - completing already complete is no-op
# @param      $1 id - Progress tracker ID
# @param      $2 [message] - Final status message
# @return     0 on success
#
# Usage: progress_complete "$pid"
# Usage: progress_complete "$pid" "All files processed successfully"
progress_complete() {
    local id="$1"
    local message="${2:-}"

    if [[ -z "${_PROGRESS_STATUS[$id]:-}" ]]; then
        _progress_load_state "$id" >/dev/null 2>&1 || true
    fi

    # Check if already complete
    if [[ "${_PROGRESS_STATUS[$id]:-}" != "active" ]]; then
        return 0
    fi

    # Calculate duration
    local now started duration
    now=$(_progress_now_epoch)
    started="${_PROGRESS_STARTED[$id]:-$now}"
    duration=$((now - started))

    # Mark as complete
    _PROGRESS_STATUS["$id"]="complete"
    _PROGRESS_MESSAGE["$id"]="$message"

    # Set current to total if total > 0
    local total="${_PROGRESS_TOTAL[$id]:-0}"
    if [[ "$total" -gt 0 ]]; then
        _PROGRESS_CURRENT["$id"]="$total"
    fi

    _progress_write_state "$id" || return 1

    # Redact message
    local safe_message
    safe_message=$(_progress_redact "$message")

    # Emit completion event
    if [[ "$MAINFRAME_BROADCAST_FORMAT" == "json" ]]; then
        local escaped_msg
        escaped_msg=$(_progress_escape_json "$safe_message")

        _progress_emit "{\"event\":\"progress_complete\",\"id\":\"$id\",\"status\":\"success\",\"message\":\"$escaped_msg\",\"duration_s\":$duration,\"timestamp\":$now}"
    else
        printf '\n[%s] Complete - %s (took %ds)\n' "${_PROGRESS_NAME[$id]}" "$safe_message" "$duration" >&2
    fi

    return 0
}

# Mark progress as failed
# @description Mark a progress tracker as failed with error message
# @pre        Progress tracker exists
# @post       Failure broadcast, tracker marked failed
# @idempotent Yes - failing already failed is no-op
# @param      $1 id - Progress tracker ID
# @param      $2 [error_message] - Error description
# @return     0 on success
#
# Usage: progress_fail "$pid" "Connection timeout"
progress_fail() {
    local id="$1"
    local error_message="${2:-Unknown error}"

    if [[ -z "${_PROGRESS_STATUS[$id]:-}" ]]; then
        _progress_load_state "$id" >/dev/null 2>&1 || true
    fi

    # Check if already terminal state
    if [[ "${_PROGRESS_STATUS[$id]:-}" != "active" ]]; then
        return 0
    fi

    # Calculate duration
    local now started duration
    now=$(_progress_now_epoch)
    started="${_PROGRESS_STARTED[$id]:-$now}"
    duration=$((now - started))

    # Mark as failed
    _PROGRESS_STATUS["$id"]="failed"
    _PROGRESS_MESSAGE["$id"]="$error_message"
    _progress_write_state "$id" || return 1

    # Redact error message
    local safe_error
    safe_error=$(_progress_redact "$error_message")

    # Emit failure event
    if [[ "$MAINFRAME_BROADCAST_FORMAT" == "json" ]]; then
        local escaped_error
        escaped_error=$(_progress_escape_json "$safe_error")

        _progress_emit "{\"event\":\"progress_complete\",\"id\":\"$id\",\"status\":\"failed\",\"message\":\"$escaped_error\",\"duration_s\":$duration,\"timestamp\":$now}"
    else
        printf '\n[%s] FAILED - %s (after %ds)\n' "${_PROGRESS_NAME[$id]}" "$safe_error" "$duration" >&2
    fi

    return 0
}

# =============================================================================
# PUBLIC API - STATUS EVENTS
# =============================================================================

# Emit heartbeat event
# @description Emit a heartbeat for long-running operations without progress metrics
# @pre        None
# @post       Heartbeat event broadcast
# @idempotent Yes
# @param      $1 id - Operation identifier
# @param      $2 [message] - Optional heartbeat message
# @return     0 always
#
# Usage: status_heartbeat "long-task-123"
# Usage: status_heartbeat "backup-job" "Still running, 2GB processed"
status_heartbeat() {
    local id="$1"
    local message="${2:-}"

    # Validate ID format
    if ! _progress_validate_id "$id"; then
        return 1
    fi

    local now
    now=$(_progress_now_epoch)

    # Redact message
    local safe_message
    safe_message=$(_progress_redact "$message")

    if [[ "$MAINFRAME_BROADCAST_FORMAT" == "json" ]]; then
        local escaped_msg
        escaped_msg=$(_progress_escape_json "$safe_message")

        _progress_emit "{\"event\":\"heartbeat\",\"id\":\"$id\",\"message\":\"$escaped_msg\",\"timestamp\":$now}"
    else
        printf '[heartbeat] %s: %s\n' "$id" "$safe_message" >&2
    fi

    return 0
}

# Emit generic status event with JSON data
# @description Emit a status event with arbitrary JSON payload
# @pre        None
# @post       Status event broadcast
# @idempotent Yes
# @param      $1 event_type - Event type name
# @param      $2 data - JSON data payload (must be valid JSON object contents)
# @return     0 always
#
# Usage: status_emit "checkpoint" '{"files":5,"bytes":1024}'
# Usage: status_emit "milestone" '{"stage":"build","percent":75}'
status_emit() {
    local event_type="$1"
    local data="${2:-{}}"

    local now
    now=$(_progress_now_epoch)

    # Validate event_type (alphanumeric, underscore, hyphen only)
    if [[ ! "$event_type" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        event_type="status"
    fi

    # Escape event type
    local escaped_type
    escaped_type=$(_progress_escape_json "$event_type")

    # The data should already be JSON formatted - validate it has content
    if [[ -z "$data" || "$data" == "{}" ]]; then
        data="{}"
    fi

    if [[ "$MAINFRAME_BROADCAST_FORMAT" == "json" ]]; then
        # If data doesn't start with {, wrap it
        if [[ "${data:0:1}" != "{" ]]; then
            data="{\"value\":\"$(_progress_escape_json "$data")\"}"
        fi

        _progress_emit "{\"event\":\"$escaped_type\",\"data\":$data,\"timestamp\":$now}"
    else
        printf '[%s] %s\n' "$event_type" "$data" >&2
    fi

    return 0
}

# =============================================================================
# PUBLIC API - FILE-BASED COORDINATION
# =============================================================================

# Write progress to file for multi-agent coordination
# @description Persist progress state to file for cross-process monitoring
# @pre        Progress tracker exists or custom data provided
# @post       Progress written atomically to file
# @idempotent Yes - overwrites with latest state
# @param      $1 id - Progress tracker ID
# @param      $2 [filepath] - Output file path (default: $MAINFRAME_PROGRESS_DIR/<id>.progress)
# @return     0 on success, 1 on write failure
#
# Usage: progress_stream_to "$pid"
# Usage: progress_stream_to "$pid" "/tmp/my-progress.json"
progress_stream_to() {
    local id="$1"
    local filepath="${2:-}"

    # Validate ID
    if ! _progress_validate_id "$id"; then
        return 1
    fi

    # Initialize directory
    if ! _progress_init_dir; then
        return 1
    fi

    # Enforce quota
    _progress_enforce_quota

    # Determine file path
    if [[ -z "$filepath" ]]; then
        filepath="$(_progress_tracker_file "$id")"
    fi

    # Ensure filepath is not a symlink (security)
    if [[ -L "$filepath" ]]; then
        return 1
    fi

    if [[ -z "${_PROGRESS_TOTAL[$id]:-}" ]]; then
        _progress_load_state "$id" >/dev/null 2>&1 || true
    fi

    _progress_write_state "$id" "$filepath"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Read progress from file
# @description Read progress state from a progress file
# @param      $1 id - Progress tracker ID
# @param      $2 [filepath] - File path (default: $MAINFRAME_PROGRESS_DIR/<id>.progress)
# @stdout     JSON progress data
# @return     0 on success, 1 if not found
progress_read_file() {
    local id="$1"
    local filepath="${2:-}"

    if ! _progress_validate_id "$id"; then
        return 1
    fi

    if [[ -z "$filepath" ]]; then
        filepath="${MAINFRAME_PROGRESS_DIR}/${id}.progress"
    fi

    if [[ -f "$filepath" && ! -L "$filepath" ]]; then
        cat "$filepath"
        return 0
    fi

    return 1
}

# Get status of a progress tracker
# @description Get current status of a progress tracker
# @param      $1 id - Progress tracker ID
# @stdout     JSON status object
# @return     0 on success, 1 if not found
progress_status() {
    local id="$1"

    if [[ -z "${_PROGRESS_TOTAL[$id]:-}" ]]; then
        _progress_load_state "$id" >/dev/null 2>&1 || true
    fi

    if [[ -z "${_PROGRESS_TOTAL[$id]:-}" ]]; then
        if [[ "$MAINFRAME_BROADCAST_FORMAT" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_NOT_FOUND","msg":"Progress tracker not found"}}'
        fi
        return 1
    fi

    local current="${_PROGRESS_CURRENT[$id]:-0}"
    local total="${_PROGRESS_TOTAL[$id]:-0}"
    local started="${_PROGRESS_STARTED[$id]:-0}"
    local duration=$(( $(_progress_now_epoch) - started ))
    local snapshot
    snapshot=$(_progress_snapshot_json "$id")
    printf '%s' "${snapshot%\}}"
    printf ',"duration_s":%d}' "$duration"
}

# Clean up old progress files
# @description Remove expired progress files from storage
# @param      $1 [max_age_minutes] - Maximum age in minutes (default: PROGRESS_MAX_AGE_MINUTES)
# @return     0 always
progress_cleanup() {
    local max_age="${1:-$PROGRESS_MAX_AGE_MINUTES}"

    if [[ -d "$MAINFRAME_PROGRESS_DIR" ]]; then
        find "$MAINFRAME_PROGRESS_DIR" -maxdepth 1 -name "*.progress" \
            -mmin "+${max_age}" -exec rm -f {} \; 2>/dev/null || true
    fi

    return 0
}

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

# Initialize on source (but don't create directory until needed)
output_init 2>/dev/null || true

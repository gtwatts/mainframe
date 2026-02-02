#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/futures.sh - Future/Promise Pattern for Non-Blocking Execution
# =============================================================================
# Description: Implements a future/promise pattern for asynchronous command
#              execution with status tracking, result retrieval, and cleanup.
#              Uses background jobs with file-based IPC for state management.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_FUTURES_LOADED:-}" ]] && return 0
readonly _MAINFRAME_FUTURES_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Base directory for future state files
readonly _FUTURES_BASE_DIR="${TMPDIR:-/tmp}/mainframe/futures"

# Future status constants
readonly FUTURE_STATUS_PENDING="pending"
readonly FUTURE_STATUS_RUNNING="running"
readonly FUTURE_STATUS_DONE="done"
readonly FUTURE_STATUS_FAILED="failed"
readonly FUTURE_STATUS_CANCELLED="cancelled"

# Default timeout for await operations (seconds)
readonly _FUTURES_DEFAULT_TIMEOUT=3600

# Global tracking of futures created in this session
declare -gA _MAINFRAME_FUTURES_REGISTRY 2>/dev/null || declare -A _MAINFRAME_FUTURES_REGISTRY

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Get the directory path for a future
# Usage: _future_dir "future_id"
_future_dir() {
    printf '%s/%s' "$_FUTURES_BASE_DIR" "$1"
}

# Ensure base directory exists
# Usage: _future_ensure_base
_future_ensure_base() {
    [[ -d "$_FUTURES_BASE_DIR" ]] || mkdir -p "$_FUTURES_BASE_DIR"
}

# Generate unique future ID
# Usage: _future_gen_id
_future_gen_id() {
    local timestamp pid random
    timestamp=$(date +%s%N 2>/dev/null || date +%s)
    pid=$$
    random=$RANDOM
    printf 'future_%s_%s_%s' "$timestamp" "$pid" "$random"
}

# Read a status file safely
# Usage: _future_read_file "path"
_future_read_file() {
    local path="$1"
    [[ -f "$path" ]] && cat "$path" 2>/dev/null
}

# Write to a status file atomically
# Usage: _future_write_file "path" "content"
_future_write_file() {
    local path="$1"
    local content="$2"
    local tmpfile="${path}.tmp.$$"

    printf '%s' "$content" > "$tmpfile" && mv "$tmpfile" "$path"
}

# Internal logging
_future_log() {
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "futures" "$@"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[futures] %s: %s\n' "$1" "${*:2}" >&2
    fi
}

# =============================================================================
# CORE FUTURE FUNCTIONS
# =============================================================================

# Run a command in background and return a future ID
# The command runs asynchronously; use future_await to wait for completion
#
# Usage: future_run "command" [args...]
# Returns: Future ID (string) on stdout
# Exit: 0 on success, 1 if command is empty
#
# Example:
#   fid=$(future_run sleep 5)
#   echo "Future started: $fid"
future_run() {
    if [[ $# -eq 0 ]]; then
        _future_log error "No command provided"
        return 1
    fi

    _future_ensure_base

    local id
    id=$(_future_gen_id)
    local dir
    dir=$(_future_dir "$id")

    # Create future directory structure
    mkdir -p "$dir"

    # Record start time
    printf '%s' "$(date +%s)" > "$dir/start_time"

    # Record command
    printf '%s' "$*" > "$dir/command"

    # Initial status
    printf '%s' "$FUTURE_STATUS_RUNNING" > "$dir/status"

    # Execute command in background subshell
    (
        # Run the command, capturing stdout and stderr
        "$@" > "$dir/stdout" 2> "$dir/stderr"
        local exit_code=$?

        # Record exit code
        printf '%d' "$exit_code" > "$dir/exit_code"

        # Record end time
        printf '%s' "$(date +%s)" > "$dir/end_time"

        # Update status based on exit code
        if [[ $exit_code -eq 0 ]]; then
            printf '%s' "$FUTURE_STATUS_DONE" > "$dir/status"
        else
            printf '%s' "$FUTURE_STATUS_FAILED" > "$dir/status"
        fi
    ) &

    # Record PID
    local pid=$!
    printf '%d' "$pid" > "$dir/pid"

    # Register in session tracking
    _MAINFRAME_FUTURES_REGISTRY["$id"]="$pid"

    printf '%s' "$id"
}

# Get the current status of a future
# Returns one of: pending, running, done, failed, cancelled
#
# Usage: future_status "future_id"
# Returns: Status string on stdout
# Exit: 0 if future exists, 1 if not found
#
# Example:
#   status=$(future_status "$fid")
#   [[ "$status" == "done" ]] && echo "Complete!"
future_status() {
    local id="$1"

    if [[ -z "$id" ]]; then
        _future_log error "Future ID required"
        return 1
    fi

    local dir
    dir=$(_future_dir "$id")

    if [[ ! -d "$dir" ]]; then
        _future_log error "Future not found: $id"
        return 1
    fi

    local status
    status=$(_future_read_file "$dir/status")

    # If status is running, verify the process is actually still alive
    if [[ "$status" == "$FUTURE_STATUS_RUNNING" ]]; then
        local pid
        pid=$(_future_read_file "$dir/pid")
        if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
            # Process died unexpectedly - check if it completed
            if [[ -f "$dir/exit_code" ]]; then
                local exit_code
                exit_code=$(_future_read_file "$dir/exit_code")
                if [[ "$exit_code" == "0" ]]; then
                    status="$FUTURE_STATUS_DONE"
                else
                    status="$FUTURE_STATUS_FAILED"
                fi
                printf '%s' "$status" > "$dir/status"
            else
                # No exit code means it crashed
                printf '%s' "$FUTURE_STATUS_FAILED" > "$dir/status"
                printf '%d' "137" > "$dir/exit_code"
                status="$FUTURE_STATUS_FAILED"
            fi
        fi
    fi

    printf '%s' "$status"
}

# Block until a future completes or times out
# Returns as soon as the future transitions to done, failed, or cancelled
#
# Usage: future_await "future_id" [timeout_seconds]
# Exit: 0 if completed successfully, 1 if failed/cancelled, 124 if timeout
#
# Example:
#   if future_await "$fid" 30; then
#       result=$(future_result "$fid")
#   fi
future_await() {
    local id="$1"
    local timeout="${2:-$_FUTURES_DEFAULT_TIMEOUT}"

    if [[ -z "$id" ]]; then
        _future_log error "Future ID required"
        return 1
    fi

    local dir
    dir=$(_future_dir "$id")

    if [[ ! -d "$dir" ]]; then
        _future_log error "Future not found: $id"
        return 1
    fi

    local start_time elapsed
    start_time=$(date +%s)

    while true; do
        local status
        status=$(future_status "$id") || return 1

        case "$status" in
            "$FUTURE_STATUS_DONE")
                return 0
                ;;
            "$FUTURE_STATUS_FAILED")
                return 1
                ;;
            "$FUTURE_STATUS_CANCELLED")
                return 1
                ;;
        esac

        # Check timeout
        elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -ge $timeout ]]; then
            _future_log warn "Future $id timed out after ${timeout}s"
            return 124
        fi

        # Sleep briefly before next check
        sleep 0.1
    done
}

# Get the result (stdout) of a completed future
# Should only be called after future has completed (status=done)
#
# Usage: future_result "future_id"
# Returns: Command stdout on stdout
# Exit: 0 if future completed with result, 1 if not found or not complete
#
# Example:
#   result=$(future_result "$fid")
future_result() {
    local id="$1"

    if [[ -z "$id" ]]; then
        _future_log error "Future ID required"
        return 1
    fi

    local dir
    dir=$(_future_dir "$id")

    if [[ ! -d "$dir" ]]; then
        _future_log error "Future not found: $id"
        return 1
    fi

    local status
    status=$(future_status "$id")

    if [[ "$status" != "$FUTURE_STATUS_DONE" && "$status" != "$FUTURE_STATUS_FAILED" ]]; then
        _future_log warn "Future $id not complete (status=$status)"
        return 1
    fi

    _future_read_file "$dir/stdout"
}

# Get the error output (stderr) of a future
# Useful when a future has failed to understand what went wrong
#
# Usage: future_error "future_id"
# Returns: Command stderr on stdout
# Exit: 0 if future exists and has stderr, 1 if not found
#
# Example:
#   if [[ $(future_status "$fid") == "failed" ]]; then
#       error=$(future_error "$fid")
#   fi
future_error() {
    local id="$1"

    if [[ -z "$id" ]]; then
        _future_log error "Future ID required"
        return 1
    fi

    local dir
    dir=$(_future_dir "$id")

    if [[ ! -d "$dir" ]]; then
        _future_log error "Future not found: $id"
        return 1
    fi

    _future_read_file "$dir/stderr"
}

# Get the exit code of a completed future
#
# Usage: future_exit_code "future_id"
# Returns: Exit code (integer) on stdout
# Exit: 0 if future has exit code, 1 if not found or not complete
#
# Example:
#   code=$(future_exit_code "$fid")
#   [[ $code -eq 0 ]] && echo "Success"
future_exit_code() {
    local id="$1"

    if [[ -z "$id" ]]; then
        _future_log error "Future ID required"
        return 1
    fi

    local dir
    dir=$(_future_dir "$id")

    if [[ ! -d "$dir" ]]; then
        _future_log error "Future not found: $id"
        return 1
    fi

    local exit_code
    exit_code=$(_future_read_file "$dir/exit_code")

    if [[ -z "$exit_code" ]]; then
        _future_log warn "Future $id has no exit code (still running?)"
        return 1
    fi

    printf '%s' "$exit_code"
}

# Cancel a running future
# Sends SIGTERM to the background process
#
# Usage: future_cancel "future_id"
# Exit: 0 if cancelled, 1 if not found or already completed
#
# Example:
#   future_cancel "$fid" && echo "Cancelled"
future_cancel() {
    local id="$1"

    if [[ -z "$id" ]]; then
        _future_log error "Future ID required"
        return 1
    fi

    local dir
    dir=$(_future_dir "$id")

    if [[ ! -d "$dir" ]]; then
        _future_log error "Future not found: $id"
        return 1
    fi

    local status
    status=$(future_status "$id")

    # Can only cancel running futures
    if [[ "$status" != "$FUTURE_STATUS_RUNNING" ]]; then
        _future_log warn "Cannot cancel future $id (status=$status)"
        return 1
    fi

    local pid
    pid=$(_future_read_file "$dir/pid")

    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        # Send SIGTERM, wait briefly, then SIGKILL if still running
        kill -TERM "$pid" 2>/dev/null

        # Brief wait for graceful shutdown
        local i
        for i in {1..10}; do
            if ! kill -0 "$pid" 2>/dev/null; then
                break
            fi
            sleep 0.1
        done

        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null
        fi
    fi

    # Update status
    printf '%s' "$FUTURE_STATUS_CANCELLED" > "$dir/status"
    printf '%d' "130" > "$dir/exit_code"  # 130 = 128 + SIGINT
    printf '%s' "$(date +%s)" > "$dir/end_time"

    return 0
}

# =============================================================================
# LISTING AND CLEANUP
# =============================================================================

# List all active futures (created in this session or found in temp dir)
# Returns JSON array of future info objects in USOP format
#
# Usage: future_list
# Returns: JSON array on stdout
# Exit: 0 always
#
# Example:
#   futures=$(future_list)
future_list() {
    _future_ensure_base

    local json_arr="["
    local first=true
    local id status pid start_time

    # List all futures in the base directory
    for dir in "$_FUTURES_BASE_DIR"/future_*; do
        [[ -d "$dir" ]] || continue

        id="${dir##*/}"
        status=$(_future_read_file "$dir/status")
        pid=$(_future_read_file "$dir/pid")
        start_time=$(_future_read_file "$dir/start_time")

        $first || json_arr+=","
        first=false

        # Build JSON object using json_object if available, else manual
        if declare -F json_object &>/dev/null; then
            json_arr+=$(json_object \
                "id=$id" \
                "status=$status" \
                "pid:number=${pid:-0}" \
                "start_time:number=${start_time:-0}")
        else
            json_arr+="{\"id\":\"$id\",\"status\":\"${status:-unknown}\",\"pid\":${pid:-0},\"start_time\":${start_time:-0}}"
        fi
    done

    json_arr+="]"
    printf '%s' "$json_arr"
}

# Clean up completed futures (removes their state directories)
# By default only cleans done and failed futures
#
# Usage: future_cleanup [--all]
# Options:
#   --all  Also clean cancelled futures
# Exit: 0 always
#
# Example:
#   future_cleanup  # Clean completed
#   future_cleanup --all  # Clean all non-running
future_cleanup() {
    local clean_all=false
    [[ "$1" == "--all" ]] && clean_all=true

    _future_ensure_base

    local cleaned=0
    local id status

    for dir in "$_FUTURES_BASE_DIR"/future_*; do
        [[ -d "$dir" ]] || continue

        id="${dir##*/}"
        status=$(future_status "$id" 2>/dev/null)

        case "$status" in
            "$FUTURE_STATUS_DONE"|"$FUTURE_STATUS_FAILED")
                rm -rf "$dir"
                unset "_MAINFRAME_FUTURES_REGISTRY[$id]"
                ((cleaned++))
                ;;
            "$FUTURE_STATUS_CANCELLED")
                if $clean_all; then
                    rm -rf "$dir"
                    unset "_MAINFRAME_FUTURES_REGISTRY[$id]"
                    ((cleaned++))
                fi
                ;;
        esac
    done

    _future_log info "Cleaned up $cleaned futures"
}

# =============================================================================
# MULTI-FUTURE OPERATIONS
# =============================================================================

# Wait for all specified futures to complete
# Returns when all futures have finished (done, failed, or cancelled)
#
# Usage: future_wait_all "id1" "id2" ...
# Exit: 0 if all completed successfully, 1 if any failed
#
# Example:
#   fid1=$(future_run cmd1)
#   fid2=$(future_run cmd2)
#   future_wait_all "$fid1" "$fid2"
future_wait_all() {
    if [[ $# -eq 0 ]]; then
        _future_log warn "No futures specified"
        return 0
    fi

    local ids=("$@")
    local all_success=true
    local id status

    for id in "${ids[@]}"; do
        if ! future_await "$id"; then
            all_success=false
        fi
    done

    $all_success
}

# Wait for any of the specified futures to complete
# Returns as soon as one future finishes
#
# Usage: future_wait_any "id1" "id2" ...
# Returns: The ID of the first completed future on stdout
# Exit: 0 if one completed successfully, 1 if first completed failed
#
# Example:
#   fid1=$(future_run slow_cmd)
#   fid2=$(future_run fast_cmd)
#   first=$(future_wait_any "$fid1" "$fid2")
#   echo "First to complete: $first"
future_wait_any() {
    if [[ $# -eq 0 ]]; then
        _future_log warn "No futures specified"
        return 1
    fi

    local ids=("$@")
    local id status

    while true; do
        for id in "${ids[@]}"; do
            status=$(future_status "$id" 2>/dev/null) || continue

            case "$status" in
                "$FUTURE_STATUS_DONE")
                    printf '%s' "$id"
                    return 0
                    ;;
                "$FUTURE_STATUS_FAILED"|"$FUTURE_STATUS_CANCELLED")
                    printf '%s' "$id"
                    return 1
                    ;;
            esac
        done

        # Brief sleep before next poll
        sleep 0.1
    done
}

# =============================================================================
# USOP OUTPUT FUNCTIONS
# =============================================================================

# Get detailed future info as JSON object (USOP compliant)
#
# Usage: future_info "future_id"
# Returns: JSON object with full future details
# Exit: 0 if found, 1 if not found
#
# Example:
#   info=$(future_info "$fid")
future_info() {
    local id="$1"

    if [[ -z "$id" ]]; then
        if declare -F output_error &>/dev/null; then
            output_error "E_INVALID_ARG" "Future ID required"
        else
            printf '{"ok":false,"error":{"code":"E_INVALID_ARG","msg":"Future ID required"}}'
        fi
        return 1
    fi

    local dir
    dir=$(_future_dir "$id")

    if [[ ! -d "$dir" ]]; then
        if declare -F output_error &>/dev/null; then
            output_error "E_NOT_FOUND" "Future not found: $id"
        else
            printf '{"ok":false,"error":{"code":"E_NOT_FOUND","msg":"Future not found: %s"}}' "$id"
        fi
        return 1
    fi

    local status pid exit_code start_time end_time command duration_ms
    status=$(future_status "$id")
    pid=$(_future_read_file "$dir/pid")
    exit_code=$(_future_read_file "$dir/exit_code")
    start_time=$(_future_read_file "$dir/start_time")
    end_time=$(_future_read_file "$dir/end_time")
    command=$(_future_read_file "$dir/command")

    # Calculate duration if both times available
    if [[ -n "$start_time" && -n "$end_time" ]]; then
        duration_ms=$(( (end_time - start_time) * 1000 ))
    elif [[ -n "$start_time" ]]; then
        duration_ms=$(( ($(date +%s) - start_time) * 1000 ))
    else
        duration_ms=0
    fi

    # Build JSON response
    if declare -F json_object &>/dev/null; then
        local json
        json=$(json_object \
            "id=$id" \
            "status=$status" \
            "pid:number=${pid:-0}" \
            "exit_code:number=${exit_code:--1}" \
            "start_time:number=${start_time:-0}" \
            "end_time:number=${end_time:-0}" \
            "duration_ms:number=$duration_ms" \
            "command=$command")

        if declare -F output_json_object &>/dev/null; then
            output_json_object "$json"
        else
            printf '{"ok":true,"data":%s}' "$json"
        fi
    else
        printf '{"ok":true,"data":{"id":"%s","status":"%s","pid":%d,"exit_code":%d,"start_time":%d,"end_time":%d,"duration_ms":%d,"command":"%s"}}' \
            "$id" "$status" "${pid:-0}" "${exit_code:--1}" "${start_time:-0}" "${end_time:-0}" "$duration_ms" "$command"
    fi
}

# =============================================================================
# NAMEREF VARIANTS (HIGH PERFORMANCE)
# =============================================================================

# Run command and store future ID in variable (avoids subshell)
#
# Usage: future_run_v result_var command [args...]
# Example:
#   future_run_v fid sleep 5
#   echo "Future: $fid"
future_run_v() {
    local -n __frv_out=$1
    shift
    __frv_out=$(future_run "$@")
}

# Get status into variable (avoids subshell)
#
# Usage: future_status_v result_var "future_id"
# Example:
#   future_status_v status "$fid"
future_status_v() {
    local -n __fsv_out=$1
    __fsv_out=$(future_status "$2")
}

# Get result into variable (avoids subshell)
#
# Usage: future_result_v result_var "future_id"
# Example:
#   future_result_v output "$fid"
future_result_v() {
    local -n __frev_out=$1
    __frev_out=$(future_result "$2")
}

# Get error into variable (avoids subshell)
#
# Usage: future_error_v result_var "future_id"
# Example:
#   future_error_v err "$fid"
future_error_v() {
    local -n __feev_out=$1
    __feev_out=$(future_error "$2")
}

# Get exit code into variable (avoids subshell)
#
# Usage: future_exit_code_v result_var "future_id"
# Example:
#   future_exit_code_v code "$fid"
future_exit_code_v() {
    local -n __fecv_out=$1
    __fecv_out=$(future_exit_code "$2")
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# List of public functions for documentation
_FUTURES_EXPORTS=(
    # Core operations
    future_run
    future_status
    future_await
    future_result
    future_error
    future_exit_code
    future_cancel
    # Listing and cleanup
    future_list
    future_cleanup
    # Multi-future operations
    future_wait_all
    future_wait_any
    # USOP output
    future_info
    # Nameref variants
    future_run_v
    future_status_v
    future_result_v
    future_error_v
    future_exit_code_v
)

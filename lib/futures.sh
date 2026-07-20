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

_future_json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
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
_future_start() {
    local __future_outvar="$1"
    shift

    if [[ $# -eq 0 ]]; then
        _future_log error "No command provided"
        return 1
    fi

    _future_ensure_base

    local future_id
    future_id=$(_future_gen_id)
    local dir
    dir=$(_future_dir "$future_id")

    # Create future directory structure
    mkdir -p "$dir"

    # Record start time
    printf '%s' "$(date +%s)" > "$dir/start_time"

    # Record command
    printf '%s' "$*" > "$dir/command"

    # Initial status
    _future_write_file "$dir/status" "$FUTURE_STATUS_RUNNING"

    # Launch a detached worker so command-substitution callers do not block.
    nohup bash -c '
        dir="$1"
        done_status="$2"
        failed_status="$3"
        cancelled_status="$4"
        shift 4

        child_pid=""

        on_cancel() {
            if [[ -n "${child_pid:-}" ]] && kill -0 "$child_pid" 2>/dev/null; then
                kill -TERM "$child_pid" 2>/dev/null || true
                wait "$child_pid" 2>/dev/null || true
            fi

            printf "%s" "$cancelled_status" > "$dir/status"
            printf "%d" "130" > "$dir/exit_code"
            printf "%s" "$(date +%s)" > "$dir/end_time"
            exit 0
        }

        trap on_cancel TERM INT

        "$@" > "$dir/stdout" 2> "$dir/stderr" &
        child_pid=$!
        printf "%d" "$child_pid" > "$dir/pid"

        wait "$child_pid"
        exit_code=$?

        printf "%d" "$exit_code" > "$dir/exit_code"
        printf "%s" "$(date +%s)" > "$dir/end_time"

        if [[ $exit_code -eq 0 ]]; then
            printf "%s" "$done_status" > "$dir/status"
        else
            printf "%s" "$failed_status" > "$dir/status"
        fi
    ' bash "$dir" "$FUTURE_STATUS_DONE" "$FUTURE_STATUS_FAILED" "$FUTURE_STATUS_CANCELLED" "$@" \
        </dev/null >/dev/null 2>&1 &

    local worker_pid=$!
    printf '%d' "$worker_pid" > "$dir/worker_pid"
    printf '%d' "$worker_pid" > "$dir/pid"

    # Register in session tracking
    _MAINFRAME_FUTURES_REGISTRY["$future_id"]="$worker_pid"

    printf -v "$__future_outvar" '%s' "$future_id"
}

future_run() {
    local id
    _future_start id "$@" || return $?
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
        local worker_pid
        pid=$(_future_read_file "$dir/pid")
        worker_pid=$(_future_read_file "$dir/worker_pid")

        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            printf '%s' "$status"
            return 0
        fi

        if [[ -n "$worker_pid" ]] && kill -0 "$worker_pid" 2>/dev/null; then
            printf '%s' "$status"
            return 0
        fi

        # Process died unexpectedly or completed - check recorded exit state.
        if [[ -f "$dir/exit_code" ]]; then
            local exit_code
            exit_code=$(_future_read_file "$dir/exit_code")
            if [[ "$exit_code" == "130" ]]; then
                status="$FUTURE_STATUS_CANCELLED"
            elif [[ "$exit_code" == "0" ]]; then
                status="$FUTURE_STATUS_DONE"
            else
                status="$FUTURE_STATUS_FAILED"
            fi
            _future_write_file "$dir/status" "$status"
        else
            _future_write_file "$dir/status" "$FUTURE_STATUS_FAILED"
            _future_write_file "$dir/exit_code" "137"
            status="$FUTURE_STATUS_FAILED"
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
    local worker_pid
    pid=$(_future_read_file "$dir/pid")
    worker_pid=$(_future_read_file "$dir/worker_pid")

    if [[ -n "$worker_pid" ]] && kill -0 "$worker_pid" 2>/dev/null; then
        kill -TERM "$worker_pid" 2>/dev/null || true
    elif [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null || true
    fi

    # Brief wait for graceful shutdown
    local i
    for i in {1..10}; do
        local child_alive=0
        local worker_alive=0

        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            child_alive=1
        fi
        if [[ -n "$worker_pid" ]] && kill -0 "$worker_pid" 2>/dev/null; then
            worker_alive=1
        fi

        if [[ $child_alive -eq 0 && $worker_alive -eq 0 ]]; then
            break
        fi

        sleep 0.1
    done

    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
    fi

    if [[ -n "$worker_pid" ]] && kill -0 "$worker_pid" 2>/dev/null; then
        kill -KILL "$worker_pid" 2>/dev/null || true
    fi

    # Update status
    _future_write_file "$dir/status" "$FUTURE_STATUS_CANCELLED"
    _future_write_file "$dir/exit_code" "130"
    _future_write_file "$dir/end_time" "$(date +%s)"

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
        status=$(future_status "$id" 2>/dev/null || _future_read_file "$dir/status")
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
                cleaned=$((cleaned + 1))
                ;;
            "$FUTURE_STATUS_CANCELLED")
                if $clean_all; then
                    rm -rf "$dir"
                    unset "_MAINFRAME_FUTURES_REGISTRY[$id]"
                    cleaned=$((cleaned + 1))
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
        printf '{"ok":false,"error":{"code":"E_INVALID_ARG","msg":"Future ID required"}}'
        return 1
    fi

    local dir
    dir=$(_future_dir "$id")

    if [[ ! -d "$dir" ]]; then
        printf '{"ok":false,"error":{"code":"E_NOT_FOUND","msg":"Future not found: %s"}}' "$(_future_json_escape "$id")"
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

    printf '{"ok":true,"data":{"id":"%s","status":"%s","pid":%d,"exit_code":%d,"start_time":%d,"end_time":%d,"duration_ms":%d,"command":"%s"}}' \
        "$(_future_json_escape "$id")" \
        "$(_future_json_escape "$status")" \
        "${pid:-0}" \
        "${exit_code:--1}" \
        "${start_time:-0}" \
        "${end_time:-0}" \
        "$duration_ms" \
        "$(_future_json_escape "$command")"
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
    _future_start __frv_out "$@"
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

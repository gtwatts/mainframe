#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/async.sh - Asynchronous Execution Library
# =============================================================================
# Description: Async operations, timers, and job management for bash
# Source: Inspired by github.com/zombieleet/async-bash
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_ASYNC_LOADED:-}" ]] && return 0
readonly _MAINFRAME_ASYNC_LOADED=1

# =============================================================================
# JOB TRACKING
# =============================================================================

# Array to track background jobs
declare -ga _MAINFRAME_ASYNC_JOBS=()

# Register a job
_async_register_job() {
    local pid="$1"
    local description="${2:-background job}"
    _MAINFRAME_ASYNC_JOBS+=("$pid:$description")
}

# Get all running job PIDs
async_jobs() {
    local job
    for job in "${_MAINFRAME_ASYNC_JOBS[@]}"; do
        local pid="${job%%:*}"
        if kill -0 "$pid" 2>/dev/null; then
            printf '%s\n' "$job"
        fi
    done
}

# Kill a specific job by PID
async_kill() {
    local target_pid="$1"
    local signal="${2:-TERM}"

    if kill -0 "$target_pid" 2>/dev/null; then
        kill "-$signal" "$target_pid" 2>/dev/null
        return $?
    fi
    return 1
}

# Kill all async jobs
async_kill_all() {
    local signal="${1:-TERM}"
    local job

    for job in "${_MAINFRAME_ASYNC_JOBS[@]}"; do
        local pid="${job%%:*}"
        kill "-$signal" "$pid" 2>/dev/null || true
    done
    _MAINFRAME_ASYNC_JOBS=()
}

# Wait for a specific job
async_wait() {
    local pid="$1"
    wait "$pid" 2>/dev/null
    return $?
}

# Wait for all jobs
async_wait_all() {
    local job
    for job in "${_MAINFRAME_ASYNC_JOBS[@]}"; do
        local pid="${job%%:*}"
        wait "$pid" 2>/dev/null || true
    done
}

# =============================================================================
# SAFE COMMAND DISPATCH (replaces eval)
# =============================================================================

# Internal: Execute a command string safely by word-splitting.
# Handles: function names, commands with args (space-separated).
# Does NOT handle: pipes, redirections, or quoted args with spaces.
# For those cases, wrap in a function: my_pipe() { cmd1 | cmd2; }
_async_exec() {
    local -a _cmd_parts
    read -ra _cmd_parts <<< "$1"
    "${_cmd_parts[@]}"
}

# Internal: Execute a command string with additional arguments appended.
_async_exec_with_args() {
    local _cmd_str="$1"
    shift
    local -a _cmd_parts
    read -ra _cmd_parts <<< "$_cmd_str"
    "${_cmd_parts[@]}" "$@"
}

# Internal: Wait for any background job (version-gated).
# Bash 4.3+ supports wait -n; older versions fall back to polling.
_async_wait_any() {
    if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3))); then
        _async_wait_any
    else
        sleep 0.2
    fi
}

# =============================================================================
# TIMER FUNCTIONS
# =============================================================================

# Execute command after delay (like JavaScript setTimeout)
# Usage: set_timeout 5 "echo hello"
# Returns: PID of background process
set_timeout() {
    local delay="$1"
    local command="$2"

    {
        sleep "$delay"
        _async_exec "$command"
    } &

    local pid=$!
    _async_register_job "$pid" "timeout: $command"
    printf '%d\n' "$pid"
}

# Execute command repeatedly at interval (like JavaScript setInterval)
# Usage: set_interval 5 "echo tick"
# Returns: PID of background process
set_interval() {
    local interval="$1"
    local command="$2"

    {
        while sleep "$interval"; do
            _async_exec "$command"
        done
    } &

    local pid=$!
    _async_register_job "$pid" "interval: $command"
    printf '%d\n' "$pid"
}

# Clear a timeout/interval by PID
# Usage: clear_timeout $pid
clear_timeout() {
    async_kill "$1"
}

# Alias for clarity
clear_interval() {
    async_kill "$1"
}

# =============================================================================
# ASYNC EXECUTION
# =============================================================================

# Execute command asynchronously
# Usage: async "long_running_command"
# Returns: PID
async() {
    local command="$1"

    _async_exec "$command" &
    local pid=$!

    _async_register_job "$pid" "async: $command"
    printf '%d\n' "$pid"
}

# Execute command and call callback with result
# Usage: async_callback "command" "on_success" "on_failure"
async_callback() {
    local command="$1"
    local on_success="${2:-:}"
    local on_failure="${3:-:}"

    {
        local output
        if output=$(_async_exec "$command" 2>&1); then
            _async_exec_with_args "$on_success" "$output"
        else
            _async_exec_with_args "$on_failure" "$output"
        fi
    } &

    local pid=$!
    _async_register_job "$pid" "callback: $command"
    printf '%d\n' "$pid"
}

# Promise-like async execution
# Usage: promise "command" resolve_func reject_func
promise() {
    local command="$1"
    local resolve="${2:-echo}"
    local reject="${3:-echo}"

    {
        local result
        local status

        result=$(_async_exec "$command" 2>&1)
        status=$?

        if [[ $status -eq 0 ]]; then
            $resolve "$result"
        else
            $reject "$result"
        fi
    } &

    local pid=$!
    _async_register_job "$pid" "promise: $command"
    printf '%d\n' "$pid"
}

# =============================================================================
# PARALLEL EXECUTION
# =============================================================================

# Execute multiple commands in parallel
# Usage: parallel "cmd1" "cmd2" "cmd3"
parallel() {
    local pids=()

    for cmd in "$@"; do
        _async_exec "$cmd" &
        pids+=($!)
    done

    # Wait for all and collect exit codes
    local codes=()
    for pid in "${pids[@]}"; do
        wait "$pid"
        codes+=($?)
    done

    # Return non-zero if any failed
    for code in "${codes[@]}"; do
        [[ $code -ne 0 ]] && return 1
    done
    return 0
}

# Execute commands in parallel with a limit
# Usage: parallel_limit 4 "cmd1" "cmd2" ... "cmd10"
parallel_limit() {
    local limit="$1"
    shift
    local commands=("$@")
    local running=0
    local pids=()
    local i=0

    while [[ $i -lt ${#commands[@]} ]] || [[ $running -gt 0 ]]; do
        # Start new jobs up to limit
        while [[ $running -lt $limit ]] && [[ $i -lt ${#commands[@]} ]]; do
            _async_exec "${commands[$i]}" &
            pids+=($!)
            ((running++)) || true
            ((i++)) || true
        done

        # Wait for any job to finish
        if [[ $running -gt 0 ]]; then
            _async_wait_any
            ((running--)) || true
        fi
    done

    # Final wait for stragglers
    wait
}

# Map function over array in parallel
# Usage: parallel_map "process_item" "${items[@]}"
parallel_map() {
    local func="$1"
    shift
    local items=("$@")
    local pids=()

    for item in "${items[@]}"; do
        $func "$item" &
        pids+=($!)
    done

    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

# Map with concurrency limit
# Usage: parallel_map_limit 4 "process_item" "${items[@]}"
parallel_map_limit() {
    local limit="$1"
    local func="$2"
    shift 2
    local items=("$@")
    local running=0
    local i=0

    while [[ $i -lt ${#items[@]} ]] || [[ $running -gt 0 ]]; do
        while [[ $running -lt $limit ]] && [[ $i -lt ${#items[@]} ]]; do
            $func "${items[$i]}" &
            ((running++)) || true
            ((i++)) || true
        done

        if [[ $running -gt 0 ]]; then
            _async_wait_any
            ((running--)) || true
        fi
    done

    wait
}

# =============================================================================
# COPROCESSES
# =============================================================================

# Start a coprocess for bidirectional communication
# Usage: coproc_start "worker_command"
# Note: Use ${COPROC[0]} to read, ${COPROC[1]} to write
coproc_start() {
    local command="$1"
    coproc MAINFRAME_COPROC { _async_exec "$command"; }
    printf '%d\n' "$MAINFRAME_COPROC_PID"
}

# Send data to coprocess
coproc_send() {
    local data="$1"
    printf '%s\n' "$data" >&"${MAINFRAME_COPROC[1]}"
}

# Read from coprocess (with timeout)
coproc_read() {
    local timeout="${1:-5}"
    local line

    if read -t "$timeout" -r line <&"${MAINFRAME_COPROC[0]}"; then
        printf '%s\n' "$line"
        return 0
    fi
    return 1
}

# Stop coprocess
coproc_stop() {
    if [[ -n "${MAINFRAME_COPROC_PID:-}" ]]; then
        kill "$MAINFRAME_COPROC_PID" 2>/dev/null || true
    fi
}

# =============================================================================
# DEBOUNCE & THROTTLE
# =============================================================================

# Debounce: execute only after delay without new calls
# Usage: debounce "my_func" 2  (wait 2 seconds)
declare -gA _MAINFRAME_DEBOUNCE_PIDS=()

debounce() {
    local func="$1"
    local delay="${2:-1}"
    local key="${3:-$func}"

    # Cancel previous timer if exists
    if [[ -n "${_MAINFRAME_DEBOUNCE_PIDS[$key]:-}" ]]; then
        kill "${_MAINFRAME_DEBOUNCE_PIDS[$key]}" 2>/dev/null || true
    fi

    # Set new timer
    {
        sleep "$delay"
        _async_exec "$func"
    } &

    _MAINFRAME_DEBOUNCE_PIDS[$key]=$!
}

# Throttle: execute at most once per interval
# Usage: throttle "my_func" 2
declare -gA _MAINFRAME_THROTTLE_LAST=()

throttle() {
    local func="$1"
    local interval="${2:-1}"
    local key="${3:-$func}"
    local now
    now=$(date +%s)

    local last="${_MAINFRAME_THROTTLE_LAST[$key]:-0}"
    local diff=$((now - last))

    if [[ $diff -ge $interval ]]; then
        _MAINFRAME_THROTTLE_LAST[$key]=$now
        _async_exec "$func"
        return 0
    fi
    return 1
}

# =============================================================================
# RETRY LOGIC
# =============================================================================

# Retry command with exponential backoff (async version with positional args)
# Note: For the more sophisticated retry with named options, use retry from retry.sh
# Usage: async_retry 5 "curl http://example.com"
async_retry() {
    local max_attempts="${1:-3}"
    local command="$2"
    local delay="${3:-1}"
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if _async_exec "$command"; then
            return 0
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            sleep "$delay"
            delay=$((delay * 2))
        fi

        ((attempt++)) || true
    done

    return 1
}

# Retry with callback on each failure
# Usage: retry_callback 5 "command" "on_fail_callback"
retry_callback() {
    local max_attempts="${1:-3}"
    local command="$2"
    local on_fail="${3:-:}"
    local delay="${4:-1}"
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if _async_exec "$command"; then
            return 0
        fi

        $on_fail "$attempt" "$max_attempts"

        if [[ $attempt -lt $max_attempts ]]; then
            sleep "$delay"
            delay=$((delay * 2))
        fi

        ((attempt++)) || true
    done

    return 1
}

# =============================================================================
# CLEANUP
# =============================================================================

# Ensure async cleanup on exit
_async_cleanup() {
    async_kill_all
}

# Register cleanup (can be disabled with ASYNC_NO_CLEANUP=1)
if [[ -z "${ASYNC_NO_CLEANUP:-}" ]]; then
    if declare -F _mainframe_add_exit_trap >/dev/null 2>&1; then
        _mainframe_add_exit_trap "_async_cleanup"
    else
        trap _async_cleanup EXIT
    fi
fi

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
declare -a ASYNC_JOBS=()

# Register a job
_async_register_job() {
    local pid="$1"
    local description="${2:-background job}"
    ASYNC_JOBS+=("$pid:$description")
}

# Get all running job PIDs
async_jobs() {
    local job
    for job in "${ASYNC_JOBS[@]}"; do
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

    for job in "${ASYNC_JOBS[@]}"; do
        local pid="${job%%:*}"
        kill "-$signal" "$pid" 2>/dev/null || true
    done
    ASYNC_JOBS=()
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
    for job in "${ASYNC_JOBS[@]}"; do
        local pid="${job%%:*}"
        wait "$pid" 2>/dev/null || true
    done
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
        eval "$command"
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
            eval "$command"
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

    eval "$command" &
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
        if output=$(eval "$command" 2>&1); then
            eval "$on_success" '"$output"'
        else
            eval "$on_failure" '"$output"'
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

        result=$(eval "$command" 2>&1)
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
        eval "$cmd" &
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
            eval "${commands[$i]}" &
            pids+=($!)
            ((running++)) || true
            ((i++)) || true
        done

        # Wait for any job to finish
        if [[ $running -gt 0 ]]; then
            wait -n 2>/dev/null || sleep 0.1
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
            wait -n 2>/dev/null || sleep 0.1
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
    coproc MAINFRAME_COPROC { eval "$command"; }
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
declare -A _DEBOUNCE_PIDS=()

debounce() {
    local func="$1"
    local delay="${2:-1}"
    local key="${3:-$func}"

    # Cancel previous timer if exists
    if [[ -n "${_DEBOUNCE_PIDS[$key]:-}" ]]; then
        kill "${_DEBOUNCE_PIDS[$key]}" 2>/dev/null || true
    fi

    # Set new timer
    {
        sleep "$delay"
        eval "$func"
    } &

    _DEBOUNCE_PIDS[$key]=$!
}

# Throttle: execute at most once per interval
# Usage: throttle "my_func" 2
declare -A _THROTTLE_LAST=()

throttle() {
    local func="$1"
    local interval="${2:-1}"
    local key="${3:-$func}"
    local now
    now=$(date +%s)

    local last="${_THROTTLE_LAST[$key]:-0}"
    local diff=$((now - last))

    if [[ $diff -ge $interval ]]; then
        _THROTTLE_LAST[$key]=$now
        eval "$func"
        return 0
    fi
    return 1
}

# =============================================================================
# RETRY LOGIC
# =============================================================================

# Retry command with exponential backoff
# Usage: retry 5 "curl http://example.com"
retry() {
    local max_attempts="${1:-3}"
    local command="$2"
    local delay="${3:-1}"
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if eval "$command"; then
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
        if eval "$command"; then
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
    trap _async_cleanup EXIT
fi


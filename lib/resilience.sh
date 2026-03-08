#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/resilience.sh - Resilience Patterns for Distributed Systems
# =============================================================================
# Description: Circuit breakers, bulkheads, rate limiters, retries, fallbacks,
#              timeouts, and health checks. Essential patterns for building
#              fault-tolerant systems and protecting against cascading failures.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_RESILIENCE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_RESILIENCE_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default circuit breaker settings
RESILIENCE_CB_FAILURE_THRESHOLD="${RESILIENCE_CB_FAILURE_THRESHOLD:-5}"
RESILIENCE_CB_SUCCESS_THRESHOLD="${RESILIENCE_CB_SUCCESS_THRESHOLD:-2}"
RESILIENCE_CB_TIMEOUT="${RESILIENCE_CB_TIMEOUT:-30}"

# Default retry settings
RESILIENCE_RETRY_MAX_ATTEMPTS="${RESILIENCE_RETRY_MAX_ATTEMPTS:-3}"
RESILIENCE_RETRY_BASE_DELAY="${RESILIENCE_RETRY_BASE_DELAY:-1}"
RESILIENCE_RETRY_MAX_DELAY="${RESILIENCE_RETRY_MAX_DELAY:-60}"

# Default rate limiter settings
RESILIENCE_RATE_LIMIT="${RESILIENCE_RATE_LIMIT:-10}"
RESILIENCE_RATE_WINDOW="${RESILIENCE_RATE_WINDOW:-60}"

# Default bulkhead settings
RESILIENCE_BULKHEAD_MAX="${RESILIENCE_BULKHEAD_MAX:-10}"

# =============================================================================
# INTERNAL STATE STORAGE
# =============================================================================

# Circuit breaker state: name -> "state:failures:successes:last_failure_time"
declare -gA _RESILIENCE_CB_STATE 2>/dev/null || declare -A _RESILIENCE_CB_STATE
declare -gA _RESILIENCE_CB_CONFIG 2>/dev/null || declare -A _RESILIENCE_CB_CONFIG
_RESILIENCE_CB_STATE=()
_RESILIENCE_CB_CONFIG=()

# Bulkhead state: name -> "current:max"
declare -gA _RESILIENCE_BULKHEAD_STATE 2>/dev/null || declare -A _RESILIENCE_BULKHEAD_STATE
declare -gA _RESILIENCE_BULKHEAD_WAITERS 2>/dev/null || declare -A _RESILIENCE_BULKHEAD_WAITERS
_RESILIENCE_BULKHEAD_STATE=()
_RESILIENCE_BULKHEAD_WAITERS=()

# Rate limiter state: name -> "count:window_start"
declare -gA _RESILIENCE_RATE_STATE 2>/dev/null || declare -A _RESILIENCE_RATE_STATE
declare -gA _RESILIENCE_RATE_CONFIG 2>/dev/null || declare -A _RESILIENCE_RATE_CONFIG
_RESILIENCE_RATE_STATE=()
_RESILIENCE_RATE_CONFIG=()

# Health check registry: name -> "function:interval:last_check:last_status"
declare -gA _RESILIENCE_HEALTH_CHECKS 2>/dev/null || declare -A _RESILIENCE_HEALTH_CHECKS
_RESILIENCE_HEALTH_CHECKS=()

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Internal logging helper
_resilience_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[resilience] %s: %s\n' "$level" "$*" >&2
    fi
}

# JSON-escape a string
_resilience_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Get current timestamp in seconds
_resilience_now() {
    printf '%d' "$(date +%s)"
}

# Emit structured JSON error
_resilience_error() {
    local code="${1:-1}"
    local msg="${2:-unknown error}"
    shift 2 2>/dev/null || shift $#

    local func="${FUNCNAME[1]:-main}"
    local escaped_msg escaped_func
    escaped_msg=$(_resilience_escape "$msg")
    escaped_func=$(_resilience_escape "$func")

    local json
    json="{\"error\":true,\"code\":$code,\"msg\":\"$escaped_msg\",\"func\":\"$escaped_func\""

    # Add context key=value pairs
    if [[ $# -gt 0 ]]; then
        json+=",\"context\":{"
        local first=true kv key val
        for kv in "$@"; do
            key="${kv%%=*}"
            val="${kv#*=}"
            local escaped_key escaped_val
            escaped_key=$(_resilience_escape "$key")
            escaped_val=$(_resilience_escape "$val")
            if [[ "$first" == "true" ]]; then
                first=false
            else
                json+=","
            fi
            json+="\"$escaped_key\":\"$escaped_val\""
        done
        json+="}"
    fi

    json+="}"
    printf '%s\n' "$json" >&2
    return "$code"
}

# Normalize numeric output so integer-like values do not keep trailing zeros.
_resilience_normalize_number() {
    local value="${1:-0}"

    while [[ "$value" == *.* && "$value" == *0 ]]; do
        value="${value%0}"
    done
    [[ "$value" == *"." ]] && value="${value%.}"
    [[ -z "$value" ]] && value="0"

    printf '%s' "$value"
}

_resilience_multiply_number() {
    local left="$1"
    local right="$2"
    local result

    if [[ "$left" =~ ^-?[0-9]+$ ]] && [[ "$right" =~ ^-?[0-9]+$ ]]; then
        printf '%s' "$(( left * right ))"
        return 0
    fi

    result=$(awk -v a="$left" -v b="$right" 'BEGIN { printf "%.6f", a * b }')
    _resilience_normalize_number "$result"
}

_resilience_number_gt() {
    local left="$1"
    local right="$2"

    if [[ "$left" =~ ^-?[0-9]+$ ]] && [[ "$right" =~ ^-?[0-9]+$ ]]; then
        [[ "$left" -gt "$right" ]]
        return $?
    fi

    awk -v a="$left" -v b="$right" 'BEGIN { exit !(a > b) }'
}

_resilience_exec_capture() {
    local output_var="$1"
    shift

    local tmp_file
    local status=0
    local captured=""

    tmp_file=$(mktemp "${TMPDIR:-/tmp}/mainframe-resilience.XXXXXX") || return 1

    if _resilience_exec "$@" >"$tmp_file" 2>&1; then
        status=0
    else
        status=$?
    fi

    captured=$(<"$tmp_file")
    rm -f "$tmp_file"

    printf -v "$output_var" '%s' "$captured"
    return "$status"
}

# Safe command dispatch that supports either command strings or argv-style calls.
_resilience_exec() {
    local command="$1"
    local shell_bin="${BASH:-}"
    shift

    if [[ -z "$command" ]]; then
        return 1
    fi

    if [[ $# -gt 0 ]]; then
        "$command" "$@"
        return $?
    fi

    if [[ "$command" != *[[:space:]]* ]] && type -t "$command" >/dev/null 2>&1; then
        "$command"
        return $?
    fi

    if [[ -z "$shell_bin" ]] || [[ ! -x "$shell_bin" ]]; then
        shell_bin="$(command -v bash 2>/dev/null || printf '/bin/bash')"
    fi

    "$shell_bin" -c "$command"
}

# =============================================================================
# CIRCUIT BREAKER
# =============================================================================
# The circuit breaker pattern prevents cascading failures by wrapping calls
# to external services and monitoring for failures. When failures exceed a
# threshold, the circuit "opens" and calls fail fast without attempting
# the underlying operation.
#
# States:
#   - CLOSED: Normal operation, calls pass through
#   - OPEN: Calls fail immediately (circuit tripped)
#   - HALF_OPEN: Test phase, allowing limited calls through
# =============================================================================

# @pre: name is non-empty
# @post: circuit breaker initialized with config
# @idempotent: yes - resets existing breaker to initial state
# @returns: 0 on success, 1 on invalid args
#
# Initialize a circuit breaker with optional configuration.
# Configuration options (key=value):
#   - failure_threshold: failures before opening (default: 5)
#   - success_threshold: successes in half-open to close (default: 2)
#   - timeout: seconds before half-open retry (default: 30)
#
# Usage: circuit_breaker_create "my_service"
# Usage: circuit_breaker_create "api" failure_threshold=3 timeout=60
circuit_breaker_create() {
    local name="$1"
    shift

    if [[ -z "$name" ]]; then
        _resilience_error 1 "circuit breaker name required"
        return 1
    fi

    # Parse configuration
    local failure_threshold="$RESILIENCE_CB_FAILURE_THRESHOLD"
    local success_threshold="$RESILIENCE_CB_SUCCESS_THRESHOLD"
    local timeout="$RESILIENCE_CB_TIMEOUT"

    local kv key val
    for kv in "$@"; do
        key="${kv%%=*}"
        val="${kv#*=}"
        case "$key" in
            failure_threshold) failure_threshold="$val" ;;
            success_threshold) success_threshold="$val" ;;
            timeout) timeout="$val" ;;
            *)
                _resilience_log warn "unknown config: $key"
                ;;
        esac
    done

    # Store config: failure_threshold:success_threshold:timeout
    _RESILIENCE_CB_CONFIG["$name"]="${failure_threshold}:${success_threshold}:${timeout}"

    # Initialize state: state(0=closed,1=open,2=half-open):failures:successes:last_failure_time
    _RESILIENCE_CB_STATE["$name"]="0:0:0:0"

    _resilience_log debug "circuit breaker '$name' created (threshold=$failure_threshold, timeout=${timeout}s)"
    return 0
}

# @pre: circuit breaker exists
# @post: command executed if circuit closed/half-open, failed fast if open
# @idempotent: no - state changes on each call
# @returns: command exit code if executed, 1 if circuit open
#
# Execute a command through the circuit breaker. If the circuit is open,
# the command is not executed and the call fails immediately.
#
# Usage: circuit_breaker_call "my_service" "curl -s http://api/health"
# Usage: circuit_breaker_call "db" "pg_isready -h localhost"
circuit_breaker_call() {
    local name="$1"
    local command="$2"
    shift 2

    if [[ -z "$name" ]]; then
        _resilience_error 1 "circuit breaker name required"
        return 1
    fi

    if [[ -z "${_RESILIENCE_CB_STATE[$name]:-}" ]]; then
        # Auto-create with defaults if not exists
        circuit_breaker_create "$name"
    fi

    # Parse current state
    local state_str="${_RESILIENCE_CB_STATE[$name]}"
    local state failures successes last_failure
    IFS=':' read -r state failures successes last_failure <<< "$state_str"

    # Parse config
    local config_str="${_RESILIENCE_CB_CONFIG[$name]}"
    local failure_threshold success_threshold timeout
    IFS=':' read -r failure_threshold success_threshold timeout <<< "$config_str"

    local now
    now=$(_resilience_now)

    # Check if we should transition from OPEN to HALF_OPEN
    if [[ "$state" == "1" ]]; then
        local elapsed=$((now - last_failure))
        if [[ $elapsed -ge $timeout ]]; then
            state=2  # Transition to HALF_OPEN
            successes=0
            _resilience_log info "circuit '$name' transitioning to HALF_OPEN after ${elapsed}s"
        else
            # Circuit is OPEN - fail fast
            _resilience_log debug "circuit '$name' is OPEN, failing fast"
            _RESILIENCE_CB_STATE["$name"]="$state:$failures:$successes:$last_failure"
            return 1
        fi
    fi

    # Execute the command
    local exit_code=0
    local output
    _resilience_exec_capture output "$command" "$@" || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        # Success
        if [[ "$state" == "2" ]]; then
            # HALF_OPEN: count successes
            ((successes++)) || true
            if [[ $successes -ge $success_threshold ]]; then
                # Transition to CLOSED
                state=0
                failures=0
                successes=0
                _resilience_log info "circuit '$name' transitioning to CLOSED after $success_threshold successes"
            fi
        else
            # CLOSED: reset failure count
            failures=0
        fi
        _RESILIENCE_CB_STATE["$name"]="$state:$failures:$successes:$last_failure"
        printf '%s' "$output"
        return 0
    else
        # Failure
        ((failures++)) || true
        last_failure="$now"

        if [[ "$state" == "2" ]]; then
            # HALF_OPEN: any failure trips back to OPEN
            state=1
            _resilience_log warn "circuit '$name' tripped back to OPEN from HALF_OPEN"
        elif [[ $failures -ge $failure_threshold ]]; then
            # CLOSED: too many failures, trip to OPEN
            state=1
            _resilience_log warn "circuit '$name' tripped to OPEN after $failures failures"
        fi

        _RESILIENCE_CB_STATE["$name"]="$state:$failures:$successes:$last_failure"
        printf '%s' "$output" >&2
        return $exit_code
    fi
}

# @pre: circuit breaker exists
# @post: returns current state
# @idempotent: yes
# @returns: state string (closed|open|half_open)
#
# Get the current state of a circuit breaker.
#
# Usage: state=$(circuit_breaker_state "my_service")
circuit_breaker_state() {
    local name="$1"

    if [[ -z "$name" ]] || [[ -z "${_RESILIENCE_CB_STATE[$name]:-}" ]]; then
        printf 'unknown'
        return 0
    fi

    local state_str="${_RESILIENCE_CB_STATE[$name]}"
    local state
    IFS=':' read -r state _ _ _ <<< "$state_str"

    case "$state" in
        0) printf 'closed' ;;
        1) printf 'open' ;;
        2) printf 'half_open' ;;
        *) printf 'unknown' ;;
    esac
    return 0
}

# @pre: circuit breaker exists
# @post: circuit reset to CLOSED state
# @idempotent: yes
# @returns: 0 on success
#
# Manually reset a circuit breaker to the CLOSED state.
#
# Usage: circuit_breaker_reset "my_service"
circuit_breaker_reset() {
    local name="$1"

    if [[ -z "$name" ]]; then
        _resilience_error 1 "circuit breaker name required"
        return 1
    fi

    if [[ -z "${_RESILIENCE_CB_STATE[$name]:-}" ]]; then
        _resilience_error 1 "circuit breaker '$name' not found"
        return 1
    fi

    _RESILIENCE_CB_STATE["$name"]="0:0:0:0"
    _resilience_log info "circuit '$name' manually reset to CLOSED"
    return 0
}

# @pre: circuit breaker exists
# @post: circuit forced to OPEN state
# @idempotent: yes
# @returns: 0 on success
#
# Manually trip a circuit breaker to the OPEN state.
#
# Usage: circuit_breaker_trip "my_service"
circuit_breaker_trip() {
    local name="$1"

    if [[ -z "$name" ]]; then
        _resilience_error 1 "circuit breaker name required"
        return 1
    fi

    if [[ -z "${_RESILIENCE_CB_STATE[$name]:-}" ]]; then
        circuit_breaker_create "$name"
    fi

    local now
    now=$(_resilience_now)

    local state_str="${_RESILIENCE_CB_STATE[$name]}"
    local _ failures successes _
    IFS=':' read -r _ failures successes _ <<< "$state_str"

    _RESILIENCE_CB_STATE["$name"]="1:$failures:$successes:$now"
    _resilience_log info "circuit '$name' manually tripped to OPEN"
    return 0
}

# @pre: circuit breaker exists
# @post: returns JSON with statistics
# @idempotent: yes
# @returns: JSON object with state, failures, successes, config
#
# Get statistics for a circuit breaker as JSON.
#
# Usage: circuit_breaker_stats "my_service"
# Output: {"name":"my_service","state":"closed","failures":2,"successes":0,...}
circuit_breaker_stats() {
    local name="$1"

    if [[ -z "$name" ]] || [[ -z "${_RESILIENCE_CB_STATE[$name]:-}" ]]; then
        printf '{"error":"circuit breaker not found"}'
        return 1
    fi

    local state_str="${_RESILIENCE_CB_STATE[$name]}"
    local state failures successes last_failure
    IFS=':' read -r state failures successes last_failure <<< "$state_str"

    local config_str="${_RESILIENCE_CB_CONFIG[$name]}"
    local failure_threshold success_threshold timeout
    IFS=':' read -r failure_threshold success_threshold timeout <<< "$config_str"

    local state_name
    case "$state" in
        0) state_name="closed" ;;
        1) state_name="open" ;;
        2) state_name="half_open" ;;
        *) state_name="unknown" ;;
    esac

    local escaped_name
    escaped_name=$(_resilience_escape "$name")

    printf '{"name":"%s","state":"%s","failures":%d,"successes":%d,"last_failure":%d,"config":{"failure_threshold":%d,"success_threshold":%d,"timeout":%d}}' \
        "$escaped_name" "$state_name" "$failures" "$successes" "$last_failure" \
        "$failure_threshold" "$success_threshold" "$timeout"
    return 0
}

# @pre: circuit breaker exists
# @post: returns or updates configuration
# @idempotent: yes
# @returns: JSON config or 0 on update
#
# Get or set configuration for a circuit breaker.
#
# Usage: circuit_breaker_config "my_service"              # get config
# Usage: circuit_breaker_config "my_service" timeout=60   # set config
circuit_breaker_config() {
    local name="$1"
    shift

    if [[ -z "$name" ]]; then
        _resilience_error 1 "circuit breaker name required"
        return 1
    fi

    if [[ -z "${_RESILIENCE_CB_CONFIG[$name]:-}" ]]; then
        _resilience_error 1 "circuit breaker '$name' not found"
        return 1
    fi

    if [[ $# -eq 0 ]]; then
        # Get config
        local config_str="${_RESILIENCE_CB_CONFIG[$name]}"
        local failure_threshold success_threshold timeout
        IFS=':' read -r failure_threshold success_threshold timeout <<< "$config_str"
        printf '{"failure_threshold":%d,"success_threshold":%d,"timeout":%d}' \
            "$failure_threshold" "$success_threshold" "$timeout"
        return 0
    fi

    # Update config
    local config_str="${_RESILIENCE_CB_CONFIG[$name]}"
    local failure_threshold success_threshold timeout
    IFS=':' read -r failure_threshold success_threshold timeout <<< "$config_str"

    local kv key val
    for kv in "$@"; do
        key="${kv%%=*}"
        val="${kv#*=}"
        case "$key" in
            failure_threshold) failure_threshold="$val" ;;
            success_threshold) success_threshold="$val" ;;
            timeout) timeout="$val" ;;
        esac
    done

    _RESILIENCE_CB_CONFIG["$name"]="${failure_threshold}:${success_threshold}:${timeout}"
    return 0
}

# =============================================================================
# BULKHEAD
# =============================================================================
# The bulkhead pattern isolates elements to prevent failures from cascading.
# It limits concurrent access to a resource, similar to compartments in a ship
# that prevent flooding from spreading.
# =============================================================================

# @pre: name is non-empty, max_concurrent is positive integer
# @post: bulkhead initialized
# @idempotent: yes - reinitializes if exists
# @returns: 0 on success, 1 on invalid args
#
# Create a bulkhead with maximum concurrent executions.
#
# Usage: bulkhead_create "api_calls" 10
bulkhead_create() {
    local name="$1"
    local max_concurrent="${2:-$RESILIENCE_BULKHEAD_MAX}"

    if [[ -z "$name" ]]; then
        _resilience_error 1 "bulkhead name required"
        return 1
    fi

    if ! [[ "$max_concurrent" =~ ^[0-9]+$ ]] || [[ "$max_concurrent" -lt 1 ]]; then
        _resilience_error 1 "max_concurrent must be positive integer" "value=$max_concurrent"
        return 1
    fi

    # State: current:max
    _RESILIENCE_BULKHEAD_STATE["$name"]="0:$max_concurrent"
    _RESILIENCE_BULKHEAD_WAITERS["$name"]="0"

    _resilience_log debug "bulkhead '$name' created with max=$max_concurrent"
    return 0
}

# @pre: bulkhead exists
# @post: slot acquired, blocking until available
# @idempotent: no - increments counter
# @returns: 0 on success
#
# Acquire a slot in the bulkhead, blocking if all slots are in use.
#
# Usage: bulkhead_acquire "api_calls"
bulkhead_acquire() {
    local name="$1"
    local timeout="${2:-0}"  # 0 = wait forever

    if [[ -z "$name" ]]; then
        _resilience_error 1 "bulkhead name required"
        return 1
    fi

    if [[ -z "${_RESILIENCE_BULKHEAD_STATE[$name]:-}" ]]; then
        bulkhead_create "$name"
    fi

    local start_time
    start_time=$(_resilience_now)

    while true; do
        local state_str="${_RESILIENCE_BULKHEAD_STATE[$name]}"
        local current max
        IFS=':' read -r current max <<< "$state_str"

        if [[ $current -lt $max ]]; then
            # Slot available
            ((current++)) || true
            _RESILIENCE_BULKHEAD_STATE["$name"]="$current:$max"
            return 0
        fi

        # Check timeout
        if [[ $timeout -gt 0 ]]; then
            local elapsed=$(($(_resilience_now) - start_time))
            if [[ $elapsed -ge $timeout ]]; then
                _resilience_log warn "bulkhead '$name' acquire timed out after ${timeout}s"
                return 1
            fi
        fi

        # Wait and retry
        local waiters="${_RESILIENCE_BULKHEAD_WAITERS[$name]}"
        ((waiters++)) || true
        _RESILIENCE_BULKHEAD_WAITERS["$name"]="$waiters"
        sleep 0.1
        ((waiters--)) || true
        _RESILIENCE_BULKHEAD_WAITERS["$name"]="$waiters"
    done
}

# @pre: bulkhead exists
# @post: slot acquired if available, returns immediately
# @idempotent: no - increments counter if successful
# @returns: 0 if acquired, 1 if bulkhead full
#
# Try to acquire a slot without blocking.
#
# Usage: if bulkhead_try_acquire "api_calls"; then ...; fi
bulkhead_try_acquire() {
    local name="$1"

    if [[ -z "$name" ]]; then
        _resilience_error 1 "bulkhead name required"
        return 1
    fi

    if [[ -z "${_RESILIENCE_BULKHEAD_STATE[$name]:-}" ]]; then
        bulkhead_create "$name"
    fi

    local state_str="${_RESILIENCE_BULKHEAD_STATE[$name]}"
    local current max
    IFS=':' read -r current max <<< "$state_str"

    if [[ $current -lt $max ]]; then
        ((current++)) || true
        _RESILIENCE_BULKHEAD_STATE["$name"]="$current:$max"
        return 0
    fi

    return 1
}

# @pre: bulkhead exists, slot was acquired
# @post: slot released
# @idempotent: no - decrements counter
# @returns: 0 on success
#
# Release a slot back to the bulkhead.
#
# Usage: bulkhead_release "api_calls"
bulkhead_release() {
    local name="$1"

    if [[ -z "$name" ]]; then
        _resilience_error 1 "bulkhead name required"
        return 1
    fi

    if [[ -z "${_RESILIENCE_BULKHEAD_STATE[$name]:-}" ]]; then
        _resilience_error 1 "bulkhead '$name' not found"
        return 1
    fi

    local state_str="${_RESILIENCE_BULKHEAD_STATE[$name]}"
    local current max
    IFS=':' read -r current max <<< "$state_str"

    if [[ $current -gt 0 ]]; then
        ((current--)) || true
        _RESILIENCE_BULKHEAD_STATE["$name"]="$current:$max"
    fi

    return 0
}

# @pre: bulkhead exists
# @post: command executed within bulkhead constraints
# @idempotent: no - state changes during execution
# @returns: command exit code
#
# Execute a command within a bulkhead. Acquires slot before execution
# and releases it after (even on failure).
#
# Usage: bulkhead_execute "api_calls" "curl -s http://api/data"
bulkhead_execute() {
    local name="$1"
    local command="$2"
    local timeout="${3:-0}"
    shift 3 2>/dev/null || shift $#

    if [[ -z "$name" ]] || [[ -z "$command" ]]; then
        _resilience_error 1 "bulkhead name and command required"
        return 1
    fi

    # Acquire slot (with optional timeout)
    if ! bulkhead_acquire "$name" "$timeout"; then
        return 1
    fi

    # Execute command
    local exit_code=0
    _resilience_exec "$command" "$@" || exit_code=$?

    # Always release slot
    bulkhead_release "$name"

    return $exit_code
}

# @pre: bulkhead exists
# @post: returns JSON statistics
# @idempotent: yes
# @returns: JSON with current, max, available, waiters
#
# Get statistics for a bulkhead.
#
# Usage: bulkhead_stats "api_calls"
bulkhead_stats() {
    local name="$1"

    if [[ -z "$name" ]] || [[ -z "${_RESILIENCE_BULKHEAD_STATE[$name]:-}" ]]; then
        printf '{"error":"bulkhead not found"}'
        return 1
    fi

    local state_str="${_RESILIENCE_BULKHEAD_STATE[$name]}"
    local current max
    IFS=':' read -r current max <<< "$state_str"

    local available=$((max - current))
    local waiters="${_RESILIENCE_BULKHEAD_WAITERS[$name]:-0}"

    local escaped_name
    escaped_name=$(_resilience_escape "$name")

    printf '{"name":"%s","current":%d,"max":%d,"available":%d,"waiters":%d}' \
        "$escaped_name" "$current" "$max" "$available" "$waiters"
    return 0
}

# @pre: bulkhead exists
# @post: max concurrent updated
# @idempotent: yes
# @returns: 0 on success
#
# Resize a bulkhead's maximum concurrent slots.
#
# Usage: bulkhead_resize "api_calls" 20
bulkhead_resize() {
    local name="$1"
    local new_max="$2"

    if [[ -z "$name" ]]; then
        _resilience_error 1 "bulkhead name required"
        return 1
    fi

    if ! [[ "$new_max" =~ ^[0-9]+$ ]] || [[ "$new_max" -lt 1 ]]; then
        _resilience_error 1 "new max must be positive integer" "value=$new_max"
        return 1
    fi

    if [[ -z "${_RESILIENCE_BULKHEAD_STATE[$name]:-}" ]]; then
        _resilience_error 1 "bulkhead '$name' not found"
        return 1
    fi

    local state_str="${_RESILIENCE_BULKHEAD_STATE[$name]}"
    local current _
    IFS=':' read -r current _ <<< "$state_str"

    _RESILIENCE_BULKHEAD_STATE["$name"]="$current:$new_max"
    _resilience_log info "bulkhead '$name' resized to max=$new_max"
    return 0
}

# =============================================================================
# RATE LIMITER
# =============================================================================
# The rate limiter pattern restricts the number of requests that can be made
# within a time window. Uses a fixed window algorithm for simplicity.
# =============================================================================

# @pre: name is non-empty
# @post: rate limiter initialized
# @idempotent: yes - reinitializes if exists
# @returns: 0 on success
#
# Create a rate limiter with requests per window.
#
# Usage: rate_limiter_create "api" 100 60  # 100 requests per 60 seconds
rate_limiter_create() {
    local name="$1"
    local limit="${2:-$RESILIENCE_RATE_LIMIT}"
    local window="${3:-$RESILIENCE_RATE_WINDOW}"

    if [[ -z "$name" ]]; then
        _resilience_error 1 "rate limiter name required"
        return 1
    fi

    # Config: limit:window
    _RESILIENCE_RATE_CONFIG["$name"]="$limit:$window"

    # State: count:window_start
    local now
    now=$(_resilience_now)
    _RESILIENCE_RATE_STATE["$name"]="0:$now"

    _resilience_log debug "rate limiter '$name' created: $limit requests per ${window}s"
    return 0
}

# @pre: rate limiter exists
# @post: returns whether request is allowed, updates counter
# @idempotent: no - increments counter if allowed
# @returns: 0 if allowed, 1 if rate limited
#
# Check if a request is allowed under the rate limit.
#
# Usage: if rate_limiter_allow "api"; then make_request; fi
rate_limiter_allow() {
    local name="$1"

    if [[ -z "$name" ]]; then
        _resilience_error 1 "rate limiter name required"
        return 1
    fi

    if [[ -z "${_RESILIENCE_RATE_CONFIG[$name]:-}" ]]; then
        rate_limiter_create "$name"
    fi

    local config_str="${_RESILIENCE_RATE_CONFIG[$name]}"
    local limit window
    IFS=':' read -r limit window <<< "$config_str"

    local state_str="${_RESILIENCE_RATE_STATE[$name]}"
    local count window_start
    IFS=':' read -r count window_start <<< "$state_str"

    local now
    now=$(_resilience_now)

    # Check if window has expired
    local elapsed=$((now - window_start))
    if [[ $elapsed -ge $window ]]; then
        # New window
        count=0
        window_start="$now"
    fi

    # Check limit
    if [[ $count -ge $limit ]]; then
        _RESILIENCE_RATE_STATE["$name"]="$count:$window_start"
        return 1  # Rate limited
    fi

    # Allow and increment
    ((count++)) || true
    _RESILIENCE_RATE_STATE["$name"]="$count:$window_start"
    return 0
}

# @pre: rate limiter exists
# @post: blocks until request is allowed
# @idempotent: no - increments counter when allowed
# @returns: 0 when allowed
#
# Block until a request is allowed under the rate limit.
#
# Usage: rate_limiter_wait "api"; make_request
rate_limiter_wait() {
    local name="$1"
    local max_wait="${2:-0}"  # 0 = wait forever

    if [[ -z "$name" ]]; then
        _resilience_error 1 "rate limiter name required"
        return 1
    fi

    local start_time
    start_time=$(_resilience_now)

    while ! rate_limiter_allow "$name"; do
        if [[ $max_wait -gt 0 ]]; then
            local elapsed=$(($(_resilience_now) - start_time))
            if [[ $elapsed -ge $max_wait ]]; then
                return 1
            fi
        fi
        sleep 0.1
    done

    return 0
}

# @pre: rate limiter exists
# @post: command executed if rate allows
# @idempotent: no - uses rate limit slot
# @returns: command exit code, or 1 if rate limited
#
# Execute a command if the rate limit allows.
#
# Usage: rate_limiter_execute "api" "curl http://api/data"
rate_limiter_execute() {
    local name="$1"
    local command="$2"
    shift 2

    if [[ -z "$name" ]] || [[ -z "$command" ]]; then
        _resilience_error 1 "rate limiter name and command required"
        return 1
    fi

    if ! rate_limiter_allow "$name"; then
        _resilience_log debug "rate limiter '$name' rejected request"
        return 1
    fi

    _resilience_exec "$command" "$@"
}

# @pre: rate limiter exists
# @post: returns JSON statistics
# @idempotent: yes
# @returns: JSON with count, limit, window, remaining
#
# Get statistics for a rate limiter.
#
# Usage: rate_limiter_stats "api"
rate_limiter_stats() {
    local name="$1"

    if [[ -z "$name" ]] || [[ -z "${_RESILIENCE_RATE_CONFIG[$name]:-}" ]]; then
        printf '{"error":"rate limiter not found"}'
        return 1
    fi

    local config_str="${_RESILIENCE_RATE_CONFIG[$name]}"
    local limit window
    IFS=':' read -r limit window <<< "$config_str"

    local state_str="${_RESILIENCE_RATE_STATE[$name]}"
    local count window_start
    IFS=':' read -r count window_start <<< "$state_str"

    local now
    now=$(_resilience_now)
    local elapsed=$((now - window_start))
    local remaining=$((limit - count))
    [[ $remaining -lt 0 ]] && remaining=0

    local resets_in=$((window - elapsed))
    [[ $resets_in -lt 0 ]] && resets_in=0

    local escaped_name
    escaped_name=$(_resilience_escape "$name")

    printf '{"name":"%s","count":%d,"limit":%d,"window":%d,"remaining":%d,"resets_in":%d}' \
        "$escaped_name" "$count" "$limit" "$window" "$remaining" "$resets_in"
    return 0
}

# @pre: rate limiter exists
# @post: counter reset to 0
# @idempotent: yes
# @returns: 0 on success
#
# Reset a rate limiter's counter.
#
# Usage: rate_limiter_reset "api"
rate_limiter_reset() {
    local name="$1"

    if [[ -z "$name" ]]; then
        _resilience_error 1 "rate limiter name required"
        return 1
    fi

    if [[ -z "${_RESILIENCE_RATE_CONFIG[$name]:-}" ]]; then
        _resilience_error 1 "rate limiter '$name' not found"
        return 1
    fi

    local now
    now=$(_resilience_now)
    _RESILIENCE_RATE_STATE["$name"]="0:$now"

    _resilience_log info "rate limiter '$name' reset"
    return 0
}

# =============================================================================
# RETRY PATTERNS
# =============================================================================
# Retry patterns handle transient failures by automatically retrying
# operations with various backoff strategies.
# =============================================================================

# @pre: command is non-empty, max_attempts > 0
# @post: command executed with exponential backoff retries
# @idempotent: depends on command
# @returns: command exit code on success, last exit code on failure
#
# Retry a command with exponential backoff.
# Delay doubles after each failure: base, 2*base, 4*base, etc.
#
# Usage: retry_exponential "curl http://api" 5 2  # 5 attempts, 2s base delay
retry_exponential() {
    local command="$1"
    local max_attempts="${2:-$RESILIENCE_RETRY_MAX_ATTEMPTS}"
    local base_delay="${3:-$RESILIENCE_RETRY_BASE_DELAY}"
    local max_delay="${4:-$RESILIENCE_RETRY_MAX_DELAY}"
    shift 4 2>/dev/null || shift $#

    if [[ -z "$command" ]]; then
        _resilience_error 1 "command required"
        return 1
    fi

    local attempt=1
    local delay="$base_delay"
    local exit_code
    local output

    while [[ $attempt -le $max_attempts ]]; do
        _resilience_exec_capture output "$command" "$@" && {
            printf '%s' "$output"
            return 0
        }
        exit_code=$?

        if [[ $attempt -lt $max_attempts ]]; then
            _resilience_log debug "retry $attempt/$max_attempts failed, waiting ${delay}s"
            sleep "$delay"

            # Exponential backoff: delay *= 2
            delay=$(_resilience_multiply_number "$delay" 2)
            if _resilience_number_gt "$delay" "$max_delay"; then
                delay="$max_delay"
            fi
        fi

        ((attempt++)) || true
    done

    _resilience_log warn "all $max_attempts attempts failed"
    printf '%s' "$output" >&2
    return $exit_code
}

# @pre: command is non-empty, max_attempts > 0
# @post: command executed with linear backoff retries
# @idempotent: depends on command
# @returns: command exit code on success, last exit code on failure
#
# Retry a command with linear backoff.
# Delay increases linearly: base, 2*base, 3*base, etc.
#
# Usage: retry_linear "curl http://api" 5 1  # 5 attempts, 1s base delay
retry_linear() {
    local command="$1"
    local max_attempts="${2:-$RESILIENCE_RETRY_MAX_ATTEMPTS}"
    local base_delay="${3:-$RESILIENCE_RETRY_BASE_DELAY}"
    local max_delay="${4:-$RESILIENCE_RETRY_MAX_DELAY}"
    shift 4 2>/dev/null || shift $#

    if [[ -z "$command" ]]; then
        _resilience_error 1 "command required"
        return 1
    fi

    local attempt=1
    local exit_code
    local output

    while [[ $attempt -le $max_attempts ]]; do
        _resilience_exec_capture output "$command" "$@" && {
            printf '%s' "$output"
            return 0
        }
        exit_code=$?

        if [[ $attempt -lt $max_attempts ]]; then
            local delay
            delay=$(_resilience_multiply_number "$base_delay" "$attempt")
            if _resilience_number_gt "$delay" "$max_delay"; then
                delay="$max_delay"
            fi

            _resilience_log debug "retry $attempt/$max_attempts failed, waiting ${delay}s"
            sleep "$delay"
        fi

        ((attempt++)) || true
    done

    _resilience_log warn "all $max_attempts attempts failed"
    printf '%s' "$output" >&2
    return $exit_code
}

# @pre: command is non-empty, max_attempts > 0
# @post: command executed with fibonacci backoff retries
# @idempotent: depends on command
# @returns: command exit code on success, last exit code on failure
#
# Retry a command with Fibonacci backoff.
# Delay follows Fibonacci sequence: 1, 1, 2, 3, 5, 8, 13, etc.
#
# Usage: retry_fibonacci "curl http://api" 5  # 5 attempts
retry_fibonacci() {
    local command="$1"
    local max_attempts="${2:-$RESILIENCE_RETRY_MAX_ATTEMPTS}"
    local max_delay="${3:-$RESILIENCE_RETRY_MAX_DELAY}"
    shift 3 2>/dev/null || shift $#

    if [[ -z "$command" ]]; then
        _resilience_error 1 "command required"
        return 1
    fi

    local attempt=1
    local fib_prev=0
    local fib_curr=1
    local exit_code
    local output

    while [[ $attempt -le $max_attempts ]]; do
        _resilience_exec_capture output "$command" "$@" && {
            printf '%s' "$output"
            return 0
        }
        exit_code=$?

        if [[ $attempt -lt $max_attempts ]]; then
            local delay="$fib_curr"
            [[ $delay -gt $max_delay ]] && delay="$max_delay"

            _resilience_log debug "retry $attempt/$max_attempts failed, waiting ${delay}s"
            sleep "$delay"

            # Next Fibonacci number
            local next=$((fib_prev + fib_curr))
            fib_prev="$fib_curr"
            fib_curr="$next"
        fi

        ((attempt++)) || true
    done

    _resilience_log warn "all $max_attempts attempts failed"
    printf '%s' "$output" >&2
    return $exit_code
}

# @pre: delay is positive number, jitter_factor is between 0 and 1
# @post: returns delay with random jitter applied
# @idempotent: no - random result each call
# @returns: jittered delay value
#
# Add random jitter to a delay value.
# Helps prevent thundering herd when multiple clients retry simultaneously.
#
# Usage: delay=$(retry_with_jitter 5 0.5)  # 5s +/- 50% jitter
retry_with_jitter() {
    local delay="$1"
    local jitter_factor="${2:-0.3}"  # Default 30% jitter

    if [[ -z "$delay" ]]; then
        printf '0'
        return 1
    fi

    if [[ ! "$delay" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || [[ ! "$jitter_factor" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
        printf '0'
        return 1
    fi

    # Prefer awk for numeric stability across CI environments. Preserve integer
    # output when the input delay is an integer so existing callers can keep
    # using shell integer comparisons.
    if command -v awk &>/dev/null; then
        local jittered
        jittered=$(awk -v delay="$delay" -v jitter="$jitter_factor" -v random_val="${RANDOM:-0}" '
            BEGIN {
                factor = (1 - jitter) + (random_val / 32767) * (jitter * 2)
                value = delay * factor
                if (delay ~ /^-?[0-9]+$/) {
                    printf "%d", int(value)
                } else {
                    printf "%.6f", value
                }
            }'
        )

        if [[ -n "$jittered" ]]; then
            _resilience_normalize_number "$jittered"
            return 0
        fi
    fi

    # Pure-shell integer fallback when awk is unavailable.
    if [[ "$delay" =~ ^-?[0-9]+$ ]]; then
        local jitter_pct=$((RANDOM % 60))  # 0-59%
        local adjustment=$(( (delay * jitter_pct) / 100 ))
        if [[ $((RANDOM % 2)) -eq 0 ]]; then
            printf '%d' $((delay + adjustment))
        else
            printf '%d' $((delay - adjustment))
        fi
        return 0
    fi

    printf '%s' "$delay"
}

# @pre: command is non-empty
# @post: command executed until success or max attempts
# @idempotent: depends on command
# @returns: 0 on success, 1 on all failures
#
# Retry a command until it succeeds, with configurable backoff and jitter.
#
# Usage: retry_until_success "curl http://api" 10 2 exponential 0.3
retry_until_success() {
    local command="$1"
    local max_attempts="${2:-$RESILIENCE_RETRY_MAX_ATTEMPTS}"
    local base_delay="${3:-$RESILIENCE_RETRY_BASE_DELAY}"
    local backoff_type="${4:-exponential}"  # exponential, linear, fibonacci
    local jitter="${5:-0}"  # jitter factor (0 = no jitter)
    shift 5 2>/dev/null || shift $#

    if [[ -z "$command" ]]; then
        _resilience_error 1 "command required"
        return 1
    fi

    local attempt=1
    local delay="$base_delay"
    local fib_prev=0
    local fib_curr=1
    local exit_code
    local output

    while [[ $attempt -le $max_attempts ]]; do
        _resilience_exec_capture output "$command" "$@" && {
            printf '%s' "$output"
            return 0
        }
        exit_code=$?

        if [[ $attempt -lt $max_attempts ]]; then
            # Calculate base delay based on backoff type
            case "$backoff_type" in
                exponential)
                    delay="$base_delay"
                    local step=1
                    while [[ $step -lt $attempt ]]; do
                        delay=$(_resilience_multiply_number "$delay" 2)
                        ((step++)) || true
                    done
                    ;;
                linear)
                    delay=$(_resilience_multiply_number "$base_delay" "$attempt")
                    ;;
                fibonacci)
                    delay="$fib_curr"
                    local next=$((fib_prev + fib_curr))
                    fib_prev="$fib_curr"
                    fib_curr="$next"
                    ;;
                constant|*)
                    delay="$base_delay"
                    ;;
            esac

            # Apply jitter if specified
            if [[ "$jitter" != "0" ]] && [[ -n "$jitter" ]]; then
                delay=$(retry_with_jitter "$delay" "$jitter")
            fi

            # Cap at max delay
            if _resilience_number_gt "$delay" "$RESILIENCE_RETRY_MAX_DELAY"; then
                delay="$RESILIENCE_RETRY_MAX_DELAY"
            fi

            _resilience_log debug "retry $attempt/$max_attempts failed, waiting ${delay}s"
            sleep "$delay"
        fi

        ((attempt++)) || true
    done

    _resilience_log warn "all $max_attempts attempts failed"
    printf '%s' "$output" >&2
    return $exit_code
}

# @pre: command and fallback_command are non-empty
# @post: primary command or fallback executed
# @idempotent: depends on commands
# @returns: exit code of successful command, or last fallback exit code
#
# Retry a command, then execute a fallback if all retries fail.
#
# Usage: retry_with_fallback "curl http://primary" "curl http://backup" 3
retry_with_fallback() {
    local command="$1"
    local fallback_command="$2"
    local max_attempts="${3:-$RESILIENCE_RETRY_MAX_ATTEMPTS}"
    local base_delay="${4:-$RESILIENCE_RETRY_BASE_DELAY}"
    shift 4 2>/dev/null || shift $#

    if [[ -z "$command" ]] || [[ -z "$fallback_command" ]]; then
        _resilience_error 1 "command and fallback_command required"
        return 1
    fi

    # Try primary with retries
    local output
    _resilience_exec_capture output retry_exponential "$command" "$max_attempts" "$base_delay" "$@" && {
        printf '%s' "$output"
        return 0
    }

    # Primary failed, try fallback
    _resilience_log info "primary command failed, trying fallback"
    _resilience_exec "$fallback_command" "$@"
}

# =============================================================================
# FALLBACK PATTERNS
# =============================================================================
# Fallback patterns provide alternative behavior when primary operations fail.
# =============================================================================

# @pre: command is non-empty
# @post: command or fallback executed
# @idempotent: depends on commands
# @returns: exit code of successful operation
#
# Execute a command with a single fallback on failure.
#
# Usage: fallback_to "curl http://primary" "curl http://backup"
fallback_to() {
    local command="$1"
    local fallback_command="$2"
    shift 2

    if [[ -z "$command" ]]; then
        _resilience_error 1 "command required"
        return 1
    fi

    local output
    _resilience_exec_capture output "$command" "$@" && {
        printf '%s' "$output"
        return 0
    }

    if [[ -n "$fallback_command" ]]; then
        _resilience_log debug "primary failed, using fallback"
        _resilience_exec "$fallback_command" "$@"
        return $?
    fi

    printf '%s' "$output" >&2
    return 1
}

# @pre: at least one command provided
# @post: first successful command's output returned
# @idempotent: depends on commands
# @returns: exit code of first successful command, or last failure
#
# Execute a chain of fallback commands until one succeeds.
#
# Usage: fallback_chain "curl http://a" "curl http://b" "curl http://c"
fallback_chain() {
    local exit_code=1
    local output=""
    local cmd

    for cmd in "$@"; do
        _resilience_exec_capture output "$cmd" && {
            printf '%s' "$output"
            return 0
        }
        exit_code=$?
        _resilience_log debug "command failed: $cmd"
    done

    printf '%s' "$output" >&2
    return $exit_code
}

# @pre: command is non-empty
# @post: command output or default value returned
# @idempotent: depends on command
# @returns: 0 always
#
# Execute a command and return a default value on failure.
#
# Usage: result=$(fallback_default "curl http://api" "default_value")
fallback_default() {
    local command="$1"
    local default_value="${2:-}"
    shift 2 2>/dev/null || shift $#

    if [[ -z "$command" ]]; then
        printf '%s' "$default_value"
        return 0
    fi

    local output
    _resilience_exec_capture output "$command" "$@" && {
        printf '%s' "$output"
        return 0
    }

    printf '%s' "$default_value"
    return 0
}

# Cache for fallback_cache
declare -gA _RESILIENCE_FALLBACK_CACHE 2>/dev/null || declare -A _RESILIENCE_FALLBACK_CACHE
_RESILIENCE_FALLBACK_CACHE=()

# @pre: command is non-empty
# @post: command output returned or cached value on failure
# @idempotent: depends on command
# @returns: 0 if value returned, 1 if no value available
#
# Execute a command and cache the result. On failure, return cached value.
# Useful for providing stale data when fresh data is unavailable.
#
# Usage: result=$(fallback_cache "api_call" "curl http://api")
fallback_cache() {
    local cache_key="$1"
    local command="$2"
    shift 2 2>/dev/null || shift $#

    if [[ -z "$cache_key" ]] || [[ -z "$command" ]]; then
        _resilience_error 1 "cache_key and command required"
        return 1
    fi

    local output
    _resilience_exec_capture output "$command" "$@" && {
        # Success - cache and return
        _RESILIENCE_FALLBACK_CACHE["$cache_key"]="$output"
        printf '%s' "$output"
        return 0
    }

    # Failure - try to return cached value
    if [[ -n "${_RESILIENCE_FALLBACK_CACHE[$cache_key]:-}" ]]; then
        _resilience_log debug "returning cached value for '$cache_key'"
        printf '%s' "${_RESILIENCE_FALLBACK_CACHE[$cache_key]}"
        return 0
    fi

    # No cached value available
    _resilience_log warn "no cached value available for '$cache_key'"
    return 1
}

# =============================================================================
# TIMEOUT PATTERNS
# =============================================================================
# Timeout patterns prevent operations from blocking indefinitely.
# =============================================================================

# @pre: command is non-empty, timeout_seconds is positive
# @post: command executed with timeout
# @idempotent: depends on command
# @returns: command exit code, or 124 on timeout
#
# Execute a command with a timeout. Enhanced version with signal handling.
#
# Usage: with_timeout 30 "long_running_command"
with_timeout() {
    local timeout_seconds="$1"
    local command="$2"
    shift 2

    if [[ -z "$timeout_seconds" ]] || [[ -z "$command" ]]; then
        _resilience_error 1 "timeout_seconds and command required"
        return 1
    fi

    if ! [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || [[ "$timeout_seconds" -lt 1 ]]; then
        _resilience_error 1 "timeout must be positive integer" "value=$timeout_seconds"
        return 1
    fi

    # Use timeout command if available (GNU coreutils)
    if command -v timeout &>/dev/null; then
        if [[ $# -gt 0 ]]; then
            timeout --signal=TERM "$timeout_seconds" "$command" "$@"
        else
            local shell_bin="${BASH:-}"
            if [[ -z "$shell_bin" ]] || [[ ! -x "$shell_bin" ]]; then
                shell_bin="$(command -v bash 2>/dev/null || printf '/bin/bash')"
            fi
            timeout --signal=TERM "$timeout_seconds" "$shell_bin" -c "$command"
        fi
        return $?
    fi

    # Fallback: manual implementation with background process
    local pid
    local exit_code

    _resilience_exec "$command" "$@" &
    pid=$!

    # Monitor with timeout
    local waited=0
    while [[ $waited -lt $timeout_seconds ]]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            # Process finished
            wait "$pid"
            return $?
        fi
        sleep 1
        ((waited++)) || true
    done

    # Timeout - kill process
    kill -TERM "$pid" 2>/dev/null || true
    sleep 0.5
    kill -KILL "$pid" 2>/dev/null || true

    _resilience_log warn "command timed out after ${timeout_seconds}s"
    return 124  # Standard timeout exit code
}

# @pre: pid is valid process ID
# @post: process terminated
# @idempotent: yes - no-op if process doesn't exist
# @returns: 0 if terminated, 1 if not found
#
# Cancel a running operation by PID.
#
# Usage: timeout_cancel $pid
timeout_cancel() {
    local pid="$1"

    if [[ -z "$pid" ]]; then
        return 1
    fi

    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null || true
        sleep 0.2
        kill -KILL "$pid" 2>/dev/null || true
        return 0
    fi

    return 1
}

# @pre: seconds is positive number
# @post: returns deadline timestamp
# @idempotent: no - based on current time
# @returns: unix timestamp for deadline
#
# Calculate a deadline timestamp from now.
#
# Usage: deadline=$(deadline_from_now 30)
deadline_from_now() {
    local seconds="$1"

    if [[ -z "$seconds" ]]; then
        _resilience_error 1 "seconds required"
        return 1
    fi

    local now
    now=$(_resilience_now)
    printf '%d' $((now + seconds))
}

# @pre: deadline is unix timestamp
# @post: returns remaining time or 0 if passed
# @idempotent: no - based on current time
# @returns: seconds until deadline (0 if passed)
#
# Get seconds remaining until a deadline.
#
# Usage: remaining=$(deadline_remaining $deadline)
deadline_remaining() {
    local deadline="$1"

    if [[ -z "$deadline" ]]; then
        printf '0'
        return 1
    fi

    local now
    now=$(_resilience_now)
    local remaining=$((deadline - now))

    if [[ $remaining -lt 0 ]]; then
        printf '0'
    else
        printf '%d' "$remaining"
    fi
}

# =============================================================================
# HEALTH CHECKS
# =============================================================================
# Health check patterns provide a standardized way to monitor system
# component health and aggregate status.
# =============================================================================

# @pre: name is non-empty, check_func is valid function
# @post: health check registered
# @idempotent: yes - replaces existing registration
# @returns: 0 on success
#
# Register a health check function.
# The function should return 0 for healthy, non-zero for unhealthy.
#
# Usage: health_check_register "database" "pg_isready -h localhost"
health_check_register() {
    local name="$1"
    local check_func="$2"
    local interval="${3:-60}"  # Check interval in seconds

    if [[ -z "$name" ]] || [[ -z "$check_func" ]]; then
        _resilience_error 1 "name and check_func required"
        return 1
    fi

    # Store: function:interval:last_check:last_status:last_message
    _RESILIENCE_HEALTH_CHECKS["$name"]="${check_func}:${interval}:0:unknown:"

    _resilience_log debug "health check '$name' registered"
    return 0
}

# @pre: health check registered
# @post: removes health check registration
# @idempotent: yes
# @returns: 0 on success
#
# Unregister a health check.
#
# Usage: health_check_unregister "database"
health_check_unregister() {
    local name="$1"

    if [[ -z "$name" ]]; then
        _resilience_error 1 "name required"
        return 1
    fi

    unset '_RESILIENCE_HEALTH_CHECKS[$name]'
    return 0
}

# @pre: optional name to run specific check
# @post: health checks executed, results cached
# @idempotent: no - state changes with each run
# @returns: 0 if all healthy, 1 if any unhealthy
#
# Run health checks. If name provided, runs only that check.
# Otherwise runs all registered checks.
#
# Usage: health_check_run              # Run all
# Usage: health_check_run "database"   # Run specific
health_check_run() {
    local target_name="${1:-}"
    local all_healthy=true
    local now
    now=$(_resilience_now)

    local name check_data
    for name in "${!_RESILIENCE_HEALTH_CHECKS[@]}"; do
        # Skip if targeting specific check
        [[ -n "$target_name" ]] && [[ "$name" != "$target_name" ]] && continue

        check_data="${_RESILIENCE_HEALTH_CHECKS[$name]}"
        local check_func interval last_check last_status last_message
        IFS=':' read -r check_func interval last_check last_status last_message <<< "$check_data"

        # Check if we should run (based on interval)
        local elapsed=$((now - last_check))
        if [[ -n "$target_name" ]] || [[ $elapsed -ge $interval ]] || [[ "$last_status" == "unknown" ]]; then
            # Run the check
            local output
            local status
            _resilience_exec_capture output "$check_func" && status="healthy" || status="unhealthy"

            # Update cache
            local escaped_output
            escaped_output="${output//:/_}"  # Remove colons to not break parsing
            _RESILIENCE_HEALTH_CHECKS["$name"]="${check_func}:${interval}:${now}:${status}:${escaped_output}"

            if [[ "$status" != "healthy" ]]; then
                all_healthy=false
                _resilience_log warn "health check '$name' is $status"
            fi
        else
            # Use cached status
            if [[ "$last_status" != "healthy" ]]; then
                all_healthy=false
            fi
        fi
    done

    if $all_healthy; then
        return 0
    else
        return 1
    fi
}

# @pre: health checks registered
# @post: returns JSON status
# @idempotent: yes
# @returns: JSON object with overall and individual health status
#
# Get overall health status as JSON.
#
# Usage: health_check_status
# Output: {"status":"healthy","checks":{"db":{"status":"healthy",...},...}}
health_check_status() {
    local force="${1:-false}"

    # Run checks if forced
    if [[ "$force" == "true" ]] || [[ "$force" == "1" ]]; then
        health_check_run >/dev/null 2>&1 || true
    fi

    local overall="healthy"
    local checks_json=""
    local first=true

    local name check_data
    for name in "${!_RESILIENCE_HEALTH_CHECKS[@]}"; do
        check_data="${_RESILIENCE_HEALTH_CHECKS[$name]}"
        local check_func interval last_check status message
        IFS=':' read -r check_func interval last_check status message <<< "$check_data"

        if [[ "$status" != "healthy" ]] && [[ "$status" != "unknown" ]]; then
            overall="unhealthy"
        fi

        local escaped_name escaped_message
        escaped_name=$(_resilience_escape "$name")
        escaped_message=$(_resilience_escape "$message")

        if $first; then
            first=false
        else
            checks_json+=","
        fi

        checks_json+="\"$escaped_name\":{\"status\":\"$status\",\"last_check\":$last_check,\"message\":\"$escaped_message\"}"
    done

    if [[ -z "$checks_json" ]]; then
        printf '{"status":"unknown","message":"no health checks registered","checks":{}}'
    else
        printf '{"status":"%s","checks":{%s}}' "$overall" "$checks_json"
    fi
    return 0
}

# @pre: health check registered
# @post: returns single check status
# @idempotent: yes
# @returns: 0 if healthy, 1 if unhealthy
#
# Check if a specific component is healthy.
#
# Usage: if health_check_is_healthy "database"; then ...; fi
health_check_is_healthy() {
    local name="$1"

    if [[ -z "$name" ]] || [[ -z "${_RESILIENCE_HEALTH_CHECKS[$name]:-}" ]]; then
        return 1
    fi

    local check_data="${_RESILIENCE_HEALTH_CHECKS[$name]}"
    local _ _ _ status _
    IFS=':' read -r _ _ _ status _ <<< "$check_data"

    [[ "$status" == "healthy" ]]
}

# =============================================================================
# COMBINED PATTERNS
# =============================================================================
# Higher-level functions that combine multiple resilience patterns.
# =============================================================================

# @pre: command is non-empty
# @post: command executed with circuit breaker and retry
# @idempotent: depends on command
# @returns: command exit code
#
# Execute with both circuit breaker and retry patterns.
#
# Usage: resilient_call "api" "curl http://api" 3 2
resilient_call() {
    local breaker_name="$1"
    local command="$2"
    local max_attempts="${3:-3}"
    local base_delay="${4:-1}"
    shift 4 2>/dev/null || shift $#

    if [[ -z "$breaker_name" ]] || [[ -z "$command" ]]; then
        _resilience_error 1 "breaker_name and command required"
        return 1
    fi

    # Check circuit breaker state first
    local state
    state=$(circuit_breaker_state "$breaker_name")
    if [[ "$state" == "open" ]]; then
        _resilience_log debug "circuit '$breaker_name' is open, failing fast"
        return 1
    fi

    # Retry with circuit breaker
    local attempt=1
    local delay="$base_delay"

    while [[ $attempt -le $max_attempts ]]; do
        circuit_breaker_call "$breaker_name" "$command" "$@" && return 0

        # Check if circuit opened
        state=$(circuit_breaker_state "$breaker_name")
        if [[ "$state" == "open" ]]; then
            _resilience_log debug "circuit '$breaker_name' opened, stopping retries"
            return 1
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            _resilience_log debug "resilient call attempt $attempt/$max_attempts failed"
            sleep "$delay"
            delay=$(_resilience_multiply_number "$delay" 2)
        fi

        ((attempt++)) || true
    done

    return 1
}

# @pre: commands specified
# @post: command executed with full resilience stack
# @idempotent: depends on command
# @returns: command exit code or fallback result
#
# Execute with bulkhead, circuit breaker, retry, timeout, and fallback.
# The ultimate resilient execution pattern.
#
# Usage: resilient_execute "service" "curl http://api" "echo default" 30 10 3
resilient_execute() {
    local service_name="$1"
    local command="$2"
    local fallback="${3:-}"
    local timeout="${4:-30}"
    local max_concurrent="${5:-10}"
    local max_retries="${6:-3}"
    shift 6 2>/dev/null || shift $#

    if [[ -z "$service_name" ]] || [[ -z "$command" ]]; then
        _resilience_error 1 "service_name and command required"
        return 1
    fi

    # Initialize components if needed
    [[ -z "${_RESILIENCE_CB_STATE[$service_name]:-}" ]] && circuit_breaker_create "$service_name"
    [[ -z "${_RESILIENCE_BULKHEAD_STATE[$service_name]:-}" ]] && bulkhead_create "$service_name" "$max_concurrent"

    # Check circuit breaker
    local state
    state=$(circuit_breaker_state "$service_name")
    if [[ "$state" == "open" ]]; then
        if [[ -n "$fallback" ]]; then
            _resilience_exec "$fallback" "$@"
            return $?
        fi
        return 1
    fi

    # Try to acquire bulkhead slot
    if ! bulkhead_try_acquire "$service_name"; then
        if [[ -n "$fallback" ]]; then
            _resilience_log debug "bulkhead full, using fallback"
            _resilience_exec "$fallback" "$@"
            return $?
        fi
        return 1
    fi

    # Execute with timeout and retry
    local result
    result=$(
        retry_exponential "with_timeout" "$max_retries" 1 "$RESILIENCE_RETRY_MAX_DELAY" "$timeout" "$command" 2>&1
    ) && {
        # Success - update circuit breaker and release bulkhead
        local dummy
        dummy=$(circuit_breaker_call "$service_name" "true" 2>&1) || true
        bulkhead_release "$service_name"
        printf '%s' "$result"
        return 0
    }

    # Failure - update circuit breaker and release bulkhead
    local dummy
    dummy=$(circuit_breaker_call "$service_name" "false" 2>&1) || true
    bulkhead_release "$service_name"

    # Try fallback
    if [[ -n "$fallback" ]]; then
        _resilience_log debug "command failed, using fallback"
        _resilience_exec "$fallback" "$@"
        return $?
    fi

    printf '%s' "$result" >&2
    return 1
}

# =============================================================================
# CLEANUP & RESET
# =============================================================================

# @pre: none
# @post: all resilience state cleared
# @idempotent: yes
# @returns: 0
#
# Reset all resilience pattern state. Useful for testing.
#
# Usage: resilience_reset_all
resilience_reset_all() {
    _RESILIENCE_CB_STATE=()
    _RESILIENCE_CB_CONFIG=()
    _RESILIENCE_BULKHEAD_STATE=()
    _RESILIENCE_BULKHEAD_WAITERS=()
    _RESILIENCE_RATE_STATE=()
    _RESILIENCE_RATE_CONFIG=()
    _RESILIENCE_HEALTH_CHECKS=()
    _RESILIENCE_FALLBACK_CACHE=()

    _resilience_log debug "all resilience state reset"
    return 0
}

# @pre: none
# @post: returns JSON summary of all components
# @idempotent: yes
# @returns: JSON with all component statistics
#
# Get a summary of all resilience components.
#
# Usage: resilience_summary
resilience_summary() {
    local cb_count="${#_RESILIENCE_CB_STATE[@]}"
    local bulkhead_count="${#_RESILIENCE_BULKHEAD_STATE[@]}"
    local rate_count="${#_RESILIENCE_RATE_CONFIG[@]}"
    local health_count="${#_RESILIENCE_HEALTH_CHECKS[@]}"

    printf '{"circuit_breakers":%d,"bulkheads":%d,"rate_limiters":%d,"health_checks":%d}' \
        "$cb_count" "$bulkhead_count" "$rate_count" "$health_count"
    return 0
}

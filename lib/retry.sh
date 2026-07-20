#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/retry.sh - Retry, Timeout, and Circuit Breaker Primitives
# =============================================================================
# Description: Resilient operation primitives for AI agents — retry with
#              configurable backoff, timeouts, circuit breakers, polling/wait
#              helpers, and token-bucket rate limiting. Pure bash.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_RETRY_LOADED:-}" ]] && return 0
readonly _MAINFRAME_RETRY_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# State directories
MAINFRAME_CB_DIR="${MAINFRAME_CB_DIR:-${TMPDIR:-/tmp}/mainframe_cb}"
MAINFRAME_RL_DIR="${MAINFRAME_RL_DIR:-${TMPDIR:-/tmp}/mainframe_rl}"

# Exit code for timeout (matches GNU timeout convention)
readonly MAINFRAME_EXIT_TIMEOUT=124

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_retry_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[retry] %s: %s\n' "$level" "$*" >&2
    fi
}

# Generate random integer in range [0, max)
_retry_random() {
    local max="$1"
    echo $(( RANDOM % max ))
}

# Read JSON-like field from simple state file
# Usage: _retry_state_get "file" "field"
_retry_state_get() {
    local file="$1" field="$2"
    if [[ -f "$file" ]]; then
        grep -o "\"${field}\":[^,}]*" "$file" 2>/dev/null | head -1 | \
            sed 's/.*://;s/^"//;s/"$//'
    fi
}

# Write a simple JSON state file
# Usage: _retry_state_write "file" "key1" "val1" "key2" "val2" ...
_retry_state_write() {
    local file="$1"
    shift
    local json="{"
    local first=1
    while [[ $# -ge 2 ]]; do
        local key="$1" val="$2"
        shift 2
        [[ $first -eq 0 ]] && json+=","
        first=0
        # Detect if value is numeric or string
        if [[ "$val" =~ ^-?[0-9]+$ ]]; then
            json+="\"${key}\":${val}"
        else
            json+="\"${key}\":\"${val}\""
        fi
    done
    json+="}"
    printf '%s' "$json" > "$file"
}

# Get current epoch seconds (bash 4.2+ uses printf, older falls back to date)
_retry_now() {
    local ts
    # shellcheck disable=SC2183
    if ts=$(printf '%(%s)T' -1 2>/dev/null) && [[ -n "$ts" ]]; then
        printf '%s' "$ts"
    else
        date +%s
    fi
}

# Get current epoch milliseconds for sub-second timing-sensitive flows.
_retry_now_ms() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        local epoch_real="$EPOCHREALTIME"
        local seconds="${epoch_real%%.*}"
        local frac="${epoch_real#*.}"
        frac="${frac}000"
        printf '%s%s' "$seconds" "${frac:0:3}"
        return 0
    fi

    local ts
    ts=$(date +%s%3N 2>/dev/null)
    if [[ "$ts" =~ ^[0-9]+$ ]]; then
        printf '%s' "$ts"
    else
        printf '%s000' "$(_retry_now)"
    fi
}

# =============================================================================
# RETRY
# =============================================================================

# @pre: command must be executable
# @post: command succeeded within max-attempts, or all attempts exhausted
# @returns: 0 on success, last exit code on failure
#
# Retry a command with configurable attempts and backoff strategy.
#
# Usage: retry [options] command [args...]
# Options:
#   --max-attempts N     Maximum attempts (default: 3)
#   --delay SECONDS      Initial delay between retries (default: 1)
#   --backoff STRATEGY   Backoff strategy: linear|exponential|fixed (default: exponential)
#   --max-delay SECONDS  Maximum delay cap (default: 30)
#   --jitter             Add random jitter (0-50% of delay) to each wait
#   --on-retry "cmd"     Callback executed before each retry (receives attempt number as $1)
#
# Example:
#   retry --max-attempts 5 --backoff exponential curl -sf http://api.example.com
#   retry --delay 2 --jitter --on-retry "echo Attempt:" wget -q http://example.com
retry() {
    local max_attempts=3
    local delay=1
    local backoff="exponential"
    local max_delay=30
    local jitter=0
    local on_retry=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-attempts)
                max_attempts="$2"
                shift 2
                ;;
            --delay)
                delay="$2"
                shift 2
                ;;
            --backoff)
                backoff="$2"
                shift 2
                ;;
            --max-delay)
                max_delay="$2"
                shift 2
                ;;
            --jitter)
                jitter=1
                shift
                ;;
            --on-retry)
                on_retry="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            -*)
                _retry_log error "retry: unknown option: $1"
                return 1
                ;;
            *)
                break
                ;;
        esac
    done

    if [[ $# -eq 0 ]]; then
        _retry_log error "retry: no command specified"
        return 1
    fi

    local attempt=1
    local exit_code=0

    while [[ $attempt -le $max_attempts ]]; do
        # Execute the command
        "$@"
        exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            return 0
        fi

        # If this was the last attempt, don't wait
        if [[ $attempt -ge $max_attempts ]]; then
            break
        fi

        # Calculate delay for this attempt
        local current_delay
        case "$backoff" in
            fixed)
                current_delay=$delay
                ;;
            linear)
                current_delay=$(( delay * attempt ))
                ;;
            exponential)
                # delay * 2^(attempt-1)
                local power=1
                local i
                for (( i = 1; i < attempt; i++ )); do
                    power=$(( power * 2 ))
                done
                current_delay=$(( delay * power ))
                ;;
            *)
                _retry_log error "retry: unknown backoff strategy: $backoff"
                return 1
                ;;
        esac

        # Cap at max_delay
        if [[ $current_delay -gt $max_delay ]]; then
            current_delay=$max_delay
        fi

        # Apply jitter: add random 0-50% of current delay
        if [[ $jitter -eq 1 && $current_delay -gt 0 ]]; then
            local jitter_amount=$(( current_delay / 2 ))
            if [[ $jitter_amount -gt 0 ]]; then
                jitter_amount=$(_retry_random "$jitter_amount")
                current_delay=$(( current_delay + jitter_amount ))
            fi
        fi

        # Execute on-retry callback if provided
        if [[ -n "$on_retry" ]]; then
            "$on_retry" "$attempt"
        fi

        _retry_log debug "retry: attempt $attempt/$max_attempts failed (exit=$exit_code), waiting ${current_delay}s"

        sleep "$current_delay"
        attempt=$(( attempt + 1 ))
    done

    _retry_log debug "retry: all $max_attempts attempts failed for: $*"
    return $exit_code
}

# @pre: N >= 1, command must be executable
# @post: command succeeded or N attempts exhausted
# @returns: 0 on success, last exit code on failure
#
# Simple retry helper — retry N times with 1s exponential backoff.
#
# Usage: retry_simple N command [args...]
# Example: retry_simple 3 curl -sf http://example.com
retry_simple() {
    local n="$1"
    shift
    retry --max-attempts "$n" "$@"
}

# =============================================================================
# TIMEOUT
# =============================================================================

# @pre: command must be executable, seconds > 0
# @post: command completed within timeout, or was killed
# @returns: command exit code, or 124 if timed out
#
# Run a command with a timeout. Returns 124 if the command times out
# (matching GNU timeout convention).
#
# Uses the `timeout` command if available, otherwise falls back to
# a background process + kill implementation.
#
# Usage: with_timeout SECONDS command [args...]
# Example: with_timeout 30 curl -sf http://slow-api.com
with_timeout() {
    local seconds="$1"
    shift

    if [[ $# -eq 0 ]]; then
        _retry_log error "with_timeout: no command specified"
        return 1
    fi

    if ! [[ "$seconds" =~ ^[0-9]+$ ]] || [[ "$seconds" -le 0 ]]; then
        _retry_log error "with_timeout: timeout must be positive integer"
        return 1
    fi

    # Prefer GNU timeout if available
    if command -v timeout &>/dev/null; then
        timeout "$seconds" "$@"
        local rc=$?
        # GNU timeout returns 124 on timeout
        _MAINFRAME_LAST_EXIT=$rc
        return $rc
    fi

    # Fallback: background process + kill
    local pid
    "$@" &
    pid=$!

    # Start a watchdog in the background
    (
        sleep "$seconds"
        kill -TERM "$pid" 2>/dev/null
        # Give it a moment to terminate, then force kill
        sleep 1
        kill -KILL "$pid" 2>/dev/null
    ) &
    local watchdog_pid=$!

    # Wait for the command to finish
    wait "$pid" 2>/dev/null
    local rc=$?

    # Kill the watchdog if it's still running
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true

    # Check if the command was killed by our watchdog
    # SIGTERM=143 (128+15), SIGKILL=137 (128+9)
    if [[ $rc -eq 143 || $rc -eq 137 ]]; then
        _MAINFRAME_LAST_EXIT=$MAINFRAME_EXIT_TIMEOUT
        return "$MAINFRAME_EXIT_TIMEOUT"
    fi

    _MAINFRAME_LAST_EXIT=$rc
    return $rc
}

# @post: returns 0 if the last with_timeout call timed out
#
# Check if the last command timed out (exit code 124).
#
# Usage:
#   with_timeout 5 slow_command
#   if did_timeout; then echo "Timed out!"; fi
did_timeout() {
    [[ "${_MAINFRAME_LAST_EXIT:-0}" -eq $MAINFRAME_EXIT_TIMEOUT ]]
}

# =============================================================================
# CIRCUIT BREAKER
# =============================================================================

# @pre: name must be a valid identifier (alphanumeric + underscore)
# @post: circuit breaker state file created in MAINFRAME_CB_DIR
# @returns: 0 on success
#
# Initialize a circuit breaker for a named service.
#
# Usage: circuit_breaker_init "service_name" [options]
# Options:
#   --threshold N       Failure count to trip open (default: 5)
#   --timeout SECONDS   Time in open state before trying half-open (default: 60)
#   --half-open-max N   Successes needed in half-open to close (default: 1)
#
# Example: circuit_breaker_init "redis" --threshold 3 --timeout 30
circuit_breaker_init() {
    local name="$1"
    shift

    if [[ -z "$name" ]]; then
        _retry_log error "circuit_breaker_init: name required"
        return 1
    fi

    local threshold=5
    local cb_timeout=60
    local half_open_max=1

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --threshold)
                threshold="$2"
                shift 2
                ;;
            --timeout)
                cb_timeout="$2"
                shift 2
                ;;
            --half-open-max)
                half_open_max="$2"
                shift 2
                ;;
            *)
                _retry_log error "circuit_breaker_init: unknown option: $1"
                return 1
                ;;
        esac
    done

    mkdir -p "$MAINFRAME_CB_DIR"

    local state_file="${MAINFRAME_CB_DIR}/${name}"
    _retry_state_write "$state_file" \
        "state" "closed" \
        "failures" "0" \
        "successes" "0" \
        "threshold" "$threshold" \
        "timeout" "$cb_timeout" \
        "half_open_max" "$half_open_max" \
        "last_failure" "0" \
        "opened_at" "0"

    _retry_log debug "circuit_breaker_init: initialized '$name' (threshold=$threshold, timeout=${cb_timeout}s)"
    return 0
}

# @pre: circuit breaker must be initialized
# @post: command executed (if circuit allows), state updated
# @returns: 0=success, 1=command failed, 2=circuit OPEN (rejected)
#
# Execute a command through the circuit breaker.
#
# Usage: circuit_breaker_call "service_name" command [args...]
# Example: circuit_breaker_call "redis" redis-cli ping
circuit_breaker_call() {
    local name="$1"
    shift

    if [[ -z "$name" ]]; then
        _retry_log error "circuit_breaker_call: name required"
        return 1
    fi

    local state_file="${MAINFRAME_CB_DIR}/${name}"
    if [[ ! -f "$state_file" ]]; then
        _retry_log error "circuit_breaker_call: breaker '$name' not initialized"
        return 1
    fi

    # Read current state
    local state failures threshold cb_timeout half_open_max opened_at successes
    state=$(_retry_state_get "$state_file" "state")
    failures=$(_retry_state_get "$state_file" "failures")
    threshold=$(_retry_state_get "$state_file" "threshold")
    cb_timeout=$(_retry_state_get "$state_file" "timeout")
    half_open_max=$(_retry_state_get "$state_file" "half_open_max")
    opened_at=$(_retry_state_get "$state_file" "opened_at")
    successes=$(_retry_state_get "$state_file" "successes")

    local now
    now=$(_retry_now)

    # Handle state transitions
    case "$state" in
        open)
            # Check if timeout has elapsed -> transition to half-open
            local elapsed=$(( now - opened_at ))
            if [[ $elapsed -ge $cb_timeout ]]; then
                state="half-open"
                successes=0
                _retry_log debug "circuit_breaker_call: '$name' transitioning to half-open"
            else
                _retry_log debug "circuit_breaker_call: '$name' is OPEN, rejecting call"
                return 2
            fi
            ;;
        half-open)
            # Allow the call through for testing
            ;;
        closed)
            # Normal operation
            ;;
    esac

    # Execute the command
    "$@"
    local rc=$?

    if [[ $rc -eq 0 ]]; then
        # Success
        case "$state" in
            half-open)
                successes=$(( successes + 1 ))
                if [[ $successes -ge $half_open_max ]]; then
                    # Enough successes, close the circuit
                    _retry_state_write "$state_file" \
                        "state" "closed" \
                        "failures" "0" \
                        "successes" "0" \
                        "threshold" "$threshold" \
                        "timeout" "$cb_timeout" \
                        "half_open_max" "$half_open_max" \
                        "last_failure" "0" \
                        "opened_at" "0"
                    _retry_log debug "circuit_breaker_call: '$name' closed (recovered)"
                else
                    _retry_state_write "$state_file" \
                        "state" "half-open" \
                        "failures" "$failures" \
                        "successes" "$successes" \
                        "threshold" "$threshold" \
                        "timeout" "$cb_timeout" \
                        "half_open_max" "$half_open_max" \
                        "last_failure" "$(_retry_state_get "$state_file" "last_failure")" \
                        "opened_at" "$opened_at"
                fi
                ;;
            closed)
                # Reset failure count on success
                if [[ $failures -gt 0 ]]; then
                    _retry_state_write "$state_file" \
                        "state" "closed" \
                        "failures" "0" \
                        "successes" "0" \
                        "threshold" "$threshold" \
                        "timeout" "$cb_timeout" \
                        "half_open_max" "$half_open_max" \
                        "last_failure" "0" \
                        "opened_at" "0"
                fi
                ;;
        esac
        return 0
    else
        # Failure
        failures=$(( failures + 1 ))
        local last_failure
        last_failure=$(_retry_now)

        case "$state" in
            half-open)
                # Failure in half-open -> back to open
                _retry_state_write "$state_file" \
                    "state" "open" \
                    "failures" "$failures" \
                    "successes" "0" \
                    "threshold" "$threshold" \
                    "timeout" "$cb_timeout" \
                    "half_open_max" "$half_open_max" \
                    "last_failure" "$last_failure" \
                    "opened_at" "$last_failure"
                _retry_log debug "circuit_breaker_call: '$name' half-open failed, reopening"
                ;;
            closed)
                if [[ $failures -ge $threshold ]]; then
                    # Trip the circuit open
                    _retry_state_write "$state_file" \
                        "state" "open" \
                        "failures" "$failures" \
                        "successes" "0" \
                        "threshold" "$threshold" \
                        "timeout" "$cb_timeout" \
                        "half_open_max" "$half_open_max" \
                        "last_failure" "$last_failure" \
                        "opened_at" "$last_failure"
                    _retry_log debug "circuit_breaker_call: '$name' tripped OPEN (failures=$failures)"
                else
                    _retry_state_write "$state_file" \
                        "state" "closed" \
                        "failures" "$failures" \
                        "successes" "0" \
                        "threshold" "$threshold" \
                        "timeout" "$cb_timeout" \
                        "half_open_max" "$half_open_max" \
                        "last_failure" "$last_failure" \
                        "opened_at" "0"
                fi
                ;;
        esac
        return 1
    fi
}

# @pre: circuit breaker must be initialized
# @returns: prints "closed", "open", or "half-open"
#
# Query the current state of a circuit breaker.
#
# Usage: circuit_breaker_state "service_name"
# Example: state=$(circuit_breaker_state "redis")
circuit_breaker_state() {
    local name="$1"
    local state_file="${MAINFRAME_CB_DIR}/${name}"

    if [[ ! -f "$state_file" ]]; then
        printf 'unknown'
        return 1
    fi

    local state opened_at cb_timeout
    state=$(_retry_state_get "$state_file" "state")
    opened_at=$(_retry_state_get "$state_file" "opened_at")
    cb_timeout=$(_retry_state_get "$state_file" "timeout")

    # Check if open circuit should transition to half-open
    if [[ "$state" == "open" ]]; then
        local now elapsed
        now=$(_retry_now)
        elapsed=$(( now - opened_at ))
        if [[ $elapsed -ge $cb_timeout ]]; then
            state="half-open"
        fi
    fi

    printf '%s' "$state"
}

# @pre: circuit breaker must be initialized
# @returns: prints current failure count
#
# Get the current failure count for a circuit breaker.
#
# Usage: count=$(circuit_breaker_failures "service_name")
circuit_breaker_failures() {
    local name="$1"
    local state_file="${MAINFRAME_CB_DIR}/${name}"

    if [[ ! -f "$state_file" ]]; then
        printf '0'
        return 1
    fi

    local failures
    failures=$(_retry_state_get "$state_file" "failures")
    printf '%s' "${failures:-0}"
}

# @pre: circuit breaker must be initialized
# @post: circuit breaker reset to closed state with zero failures
# @returns: 0 on success
#
# Force reset a circuit breaker to closed state.
#
# Usage: circuit_breaker_reset "service_name"
circuit_breaker_reset() {
    local name="$1"
    local state_file="${MAINFRAME_CB_DIR}/${name}"

    if [[ ! -f "$state_file" ]]; then
        _retry_log error "circuit_breaker_reset: breaker '$name' not initialized"
        return 1
    fi

    local threshold cb_timeout half_open_max
    threshold=$(_retry_state_get "$state_file" "threshold")
    cb_timeout=$(_retry_state_get "$state_file" "timeout")
    half_open_max=$(_retry_state_get "$state_file" "half_open_max")

    _retry_state_write "$state_file" \
        "state" "closed" \
        "failures" "0" \
        "successes" "0" \
        "threshold" "$threshold" \
        "timeout" "$cb_timeout" \
        "half_open_max" "$half_open_max" \
        "last_failure" "0" \
        "opened_at" "0"

    _retry_log debug "circuit_breaker_reset: '$name' reset to closed"
    return 0
}

# @returns: prints list of all circuit breaker names, one per line
#
# List all initialized circuit breakers.
#
# Usage: circuit_breaker_list
circuit_breaker_list() {
    if [[ ! -d "$MAINFRAME_CB_DIR" ]]; then
        return 0
    fi

    local f
    for f in "$MAINFRAME_CB_DIR"/*; do
        [[ -f "$f" ]] || continue
        local name state failures
        name="${f##*/}"
        state=$(_retry_state_get "$f" "state")
        failures=$(_retry_state_get "$f" "failures")
        printf '%s\t%s\t%s\n' "$name" "${state:-unknown}" "${failures:-0}"
    done
}

# =============================================================================
# POLLING / WAIT
# =============================================================================

# @pre: command must be executable
# @post: command returned 0, or timeout elapsed
# @returns: 0 if condition met, 1 if timed out
#
# Wait for a condition (command) to become true, polling at an interval.
#
# Usage: wait_for [options] command [args...]
# Options:
#   --timeout SECONDS    Maximum time to wait (default: 30)
#   --interval SECONDS   Polling interval (default: 1)
#   --message "text"     Message displayed while waiting
#
# Example:
#   wait_for --timeout 60 --interval 2 curl -sf http://localhost:8080/health
wait_for() {
    local wait_timeout=30
    local interval=1
    local message=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)
                wait_timeout="$2"
                shift 2
                ;;
            --interval)
                interval="$2"
                shift 2
                ;;
            --message)
                message="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            -*)
                _retry_log error "wait_for: unknown option: $1"
                return 1
                ;;
            *)
                break
                ;;
        esac
    done

    if [[ $# -eq 0 ]]; then
        _retry_log error "wait_for: no command specified"
        return 1
    fi

    local start elapsed
    start=$(_retry_now)

    while true; do
        # Try the command
        if "$@" &>/dev/null; then
            return 0
        fi

        # Check timeout
        elapsed=$(( $(_retry_now) - start ))
        if [[ $elapsed -ge $wait_timeout ]]; then
            if [[ -n "$message" ]]; then
                _retry_log warn "wait_for: timed out after ${wait_timeout}s: $message"
            else
                _retry_log debug "wait_for: timed out after ${wait_timeout}s waiting for: $*"
            fi
            return 1
        fi

        # Display message if provided
        if [[ -n "$message" ]]; then
            _retry_log debug "wait_for: $message (${elapsed}s/${wait_timeout}s)"
        fi

        sleep "$interval"
    done
}

# @pre: path is valid
# @post: file exists at path, or timeout elapsed
# @returns: 0 if file found, 1 if timed out
#
# Wait for a file to exist on the filesystem.
#
# Usage: wait_for_file "/path/to/file" [timeout_seconds]
# Example: wait_for_file "/var/run/app.pid" 10
wait_for_file() {
    local file="$1"
    local file_timeout="${2:-30}"

    if [[ -z "$file" ]]; then
        _retry_log error "wait_for_file: path required"
        return 1
    fi

    wait_for --timeout "$file_timeout" --interval 1 \
        --message "waiting for file: $file" \
        test -f "$file"
}

# @pre: host and port are valid
# @post: TCP connection succeeded, or timeout elapsed
# @returns: 0 if port open, 1 if timed out
#
# Wait for a TCP port to be open on a host.
#
# Usage: wait_for_port HOST PORT [timeout_seconds]
# Example: wait_for_port localhost 8080 60
wait_for_port() {
    local host="$1"
    local port="$2"
    local port_timeout="${3:-30}"

    if [[ -z "$host" || -z "$port" ]]; then
        _retry_log error "wait_for_port: host and port required"
        return 1
    fi

    local check_cmd
    if command -v nc &>/dev/null; then
        check_cmd="_retry_check_port_nc"
    elif [[ -e /dev/tcp ]]; then
        check_cmd="_retry_check_port_devtcp"
    else
        # Fallback: try bash /dev/tcp (may work even without /dev/tcp existing)
        check_cmd="_retry_check_port_bash"
    fi

    wait_for --timeout "$port_timeout" --interval 1 \
        --message "waiting for ${host}:${port}" \
        "$check_cmd" "$host" "$port"
}

# Port check helpers
_retry_check_port_nc() {
    nc -z "$1" "$2" 2>/dev/null
}

_retry_check_port_devtcp() {
    (echo > "/dev/tcp/$1/$2") 2>/dev/null
}

_retry_check_port_bash() {
    (echo > "/dev/tcp/$1/$2") 2>/dev/null
}

# =============================================================================
# RATE LIMITER
# =============================================================================

# @pre: name is a valid identifier, rate > 0, per > 0
# @post: rate limiter state file created in MAINFRAME_RL_DIR
# @returns: 0 on success
#
# Initialize a token-bucket rate limiter.
#
# Usage: rate_limit_init "name" --rate N --per SECONDS
# Example: rate_limit_init "api_calls" --rate 10 --per 60
rate_limit_init() {
    local name="$1"
    shift

    if [[ -z "$name" ]]; then
        _retry_log error "rate_limit_init: name required"
        return 1
    fi

    local rate=0
    local per=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --rate)
                rate="$2"
                shift 2
                ;;
            --per)
                per="$2"
                shift 2
                ;;
            *)
                _retry_log error "rate_limit_init: unknown option: $1"
                return 1
                ;;
        esac
    done

    if [[ $rate -le 0 || $per -le 0 ]]; then
        _retry_log error "rate_limit_init: --rate and --per must be positive"
        return 1
    fi

    mkdir -p "$MAINFRAME_RL_DIR"

    local state_file="${MAINFRAME_RL_DIR}/${name}"
    local now_ms
    now_ms=$(_retry_now_ms)

    _retry_state_write "$state_file" \
        "rate" "$rate" \
        "per" "$per" \
        "tokens" "$rate" \
        "last_refill_ms" "$now_ms"

    _retry_log debug "rate_limit_init: initialized '$name' (rate=$rate per ${per}s)"
    return 0
}

# @pre: rate limiter must be initialized
# @post: token consumed, or caller blocked until available (or rejected with --no-wait)
# @returns: 0 if token acquired, 1 if rate exceeded (only with --no-wait)
#
# Acquire a token from the rate limiter. Blocks by default until a token
# is available. Use --no-wait to return immediately if no tokens available.
#
# Usage: rate_limit_acquire "name" [--no-wait]
# Example:
#   rate_limit_acquire "api_calls"              # blocks until token available
#   rate_limit_acquire "api_calls" --no-wait    # returns 1 if no tokens
rate_limit_acquire() {
    local name="$1"
    local no_wait=0

    if [[ "${2:-}" == "--no-wait" ]]; then
        no_wait=1
    fi

    if [[ -z "$name" ]]; then
        _retry_log error "rate_limit_acquire: name required"
        return 1
    fi

    local state_file="${MAINFRAME_RL_DIR}/${name}"
    if [[ ! -f "$state_file" ]]; then
        _retry_log error "rate_limit_acquire: limiter '$name' not initialized"
        return 1
    fi

    while true; do
        # Read state
        local rate per tokens last_refill_ms
        rate=$(_retry_state_get "$state_file" "rate")
        per=$(_retry_state_get "$state_file" "per")
        tokens=$(_retry_state_get "$state_file" "tokens")
        last_refill_ms=$(_retry_state_get "$state_file" "last_refill_ms")
        if [[ -z "$last_refill_ms" ]]; then
            local legacy_last_refill
            legacy_last_refill=$(_retry_state_get "$state_file" "last_refill")
            if [[ -n "$legacy_last_refill" ]]; then
                last_refill_ms=$(( legacy_last_refill * 1000 ))
            else
                last_refill_ms=$(_retry_now_ms)
            fi
        fi

        # Calculate token refill
        local now_ms elapsed_ms tokens_to_add per_ms
        now_ms=$(_retry_now_ms)
        per_ms=$(( per * 1000 ))
        elapsed_ms=$(( now_ms - last_refill_ms ))

        if [[ $elapsed_ms -ge $per_ms ]]; then
            # Full refill: enough time has passed for a complete bucket refill
            tokens=$rate
            last_refill_ms=$now_ms
        elif [[ $elapsed_ms -gt 0 ]]; then
            # Partial refill: add proportional tokens
            # tokens_to_add = rate * elapsed_ms / per_ms
            tokens_to_add=$(( rate * elapsed_ms / per_ms ))
            if [[ $tokens_to_add -gt 0 ]]; then
                tokens=$(( tokens + tokens_to_add ))
                if [[ $tokens -gt $rate ]]; then
                    tokens=$rate
                fi
                last_refill_ms=$(( last_refill_ms + (tokens_to_add * per_ms / rate) ))
            fi
        fi

        # Try to consume a token
        if [[ $tokens -gt 0 ]]; then
            tokens=$(( tokens - 1 ))
            _retry_state_write "$state_file" \
                "rate" "$rate" \
                "per" "$per" \
                "tokens" "$tokens" \
                "last_refill_ms" "$last_refill_ms"
            return 0
        fi

        # No tokens available
        if [[ $no_wait -eq 1 ]]; then
            return 1
        fi

        # Block: wait for next token to become available
        # Time until next token: per / rate (seconds per token)
        local wait_time=$(( per / rate ))
        if [[ $wait_time -lt 1 ]]; then
            wait_time=1
        fi
        _retry_log debug "rate_limit_acquire: '$name' rate limited, waiting ${wait_time}s"
        sleep "$wait_time"
    done
}

# @pre: rate limiter must be initialized
# @post: rate limiter reset to full token bucket
# @returns: 0 on success
#
# Reset a rate limiter to its initial state (full bucket).
#
# Usage: rate_limit_reset "name"
rate_limit_reset() {
    local name="$1"
    local state_file="${MAINFRAME_RL_DIR}/${name}"

    if [[ ! -f "$state_file" ]]; then
        _retry_log error "rate_limit_reset: limiter '$name' not initialized"
        return 1
    fi

    local rate per now_ms
    rate=$(_retry_state_get "$state_file" "rate")
    per=$(_retry_state_get "$state_file" "per")
    now_ms=$(_retry_now_ms)

    _retry_state_write "$state_file" \
        "rate" "$rate" \
        "per" "$per" \
        "tokens" "$rate" \
        "last_refill_ms" "$now_ms"

    _retry_log debug "rate_limit_reset: '$name' reset to $rate tokens"
    return 0
}

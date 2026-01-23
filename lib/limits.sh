#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/limits.sh - Resource Consumption Caps
# =============================================================================
# Description: Resource limit tracking and enforcement for AI agent operations.
#              Provides configurable caps on file operations, write volume,
#              execution time, recursion depth, and network operations. Prevents
#              runaway agents from consuming unbounded resources.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_LIMITS_LOADED:-}" ]] && return 0
_MAINFRAME_LIMITS_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Tracking directory for counters (survives subshells via filesystem)
_MAINFRAME_LIMIT_DIR="${_MAINFRAME_LIMIT_DIR:-}"

# Whether limits system is active
_MAINFRAME_LIMIT_ENABLED=0

# Limit maximums (0 = unlimited)
_MAINFRAME_LIMIT_MAX_FILES=0
_MAINFRAME_LIMIT_MAX_WRITES=0
_MAINFRAME_LIMIT_MAX_TIME=0
_MAINFRAME_LIMIT_MAX_DEPTH=0
_MAINFRAME_LIMIT_MAX_NETWORK=0

# Known limit types
_MAINFRAME_LIMIT_TYPES="files writes time depth network"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# JSON-escape a string
_limit_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# @pre: code is integer, msg is non-empty
# @post: error emitted to stderr (JSON or plain text)
# @returns: provided exit code
#
# Emit a structured error for the limits module.
#
# Usage: _limit_error 1 "limit exceeded"
_limit_error() {
    local code="${1:-1}"
    local msg="${2:-unknown error}"

    local func="${FUNCNAME[1]:-main}"

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        local escaped_msg escaped_func
        escaped_msg=$(_limit_escape "$msg")
        escaped_func=$(_limit_escape "$func")
        printf '{"error":true,"code":%d,"msg":"%s","module":"limits","func":"%s"}\n' \
            "$code" "$escaped_msg" "$escaped_func" >&2
    else
        printf '[limits] ERROR: %s (in %s)\n' "$msg" "$func" >&2
    fi
    return "$code"
}

# @pre: size_str is a string like "10MB", "1GB", "512KB", "1024"
# @post: prints size in bytes to stdout
# @returns: 0 on success, 1 on invalid input
#
# Parse human-readable size strings into byte values.
# Supports B, KB, MB, GB (case-insensitive). Plain numbers treated as bytes.
#
# Usage: bytes=$(_limit_parse_size "10MB")
_limit_parse_size() {
    local input="$1"

    if [[ -z "$input" ]]; then
        return 1
    fi

    # Extract numeric portion and suffix
    local number=""
    local suffix=""

    # Handle pure numbers (no suffix)
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        printf '%s' "$input"
        return 0
    fi

    # Match number followed by optional suffix
    if [[ "$input" =~ ^([0-9]+)[[:space:]]*(([gGmMkKbB])[bB]?)$ ]]; then
        number="${BASH_REMATCH[1]}"
        suffix="${BASH_REMATCH[2]}"
    else
        return 1
    fi

    # Convert suffix to uppercase for comparison
    local upper_suffix=""
    local i
    for (( i=0; i<${#suffix}; i++ )); do
        local c="${suffix:$i:1}"
        case "$c" in
            [a-z]) upper_suffix+="${c^}" ;;
            *)     upper_suffix+="$c" ;;
        esac
    done

    local multiplier=1
    case "$upper_suffix" in
        B)   multiplier=1 ;;
        KB|K) multiplier=1024 ;;
        MB|M) multiplier=1048576 ;;
        GB|G) multiplier=1073741824 ;;
        *)   return 1 ;;
    esac

    local result=$(( number * multiplier ))
    printf '%s' "$result"
    return 0
}

# Read a counter value from the tracking directory
_limit_read_counter() {
    local type="$1"

    if [[ -z "$_MAINFRAME_LIMIT_DIR" ]] || [[ ! -d "$_MAINFRAME_LIMIT_DIR" ]]; then
        printf '0'
        return 0
    fi

    local file="$_MAINFRAME_LIMIT_DIR/${type}.count"
    if [[ -f "$file" ]]; then
        cat "$file" 2>/dev/null || printf '0'
    else
        printf '0'
    fi
    return 0
}

# Write a counter value to the tracking directory
_limit_write_counter() {
    local type="$1"
    local value="$2"

    if [[ -z "$_MAINFRAME_LIMIT_DIR" ]] || [[ ! -d "$_MAINFRAME_LIMIT_DIR" ]]; then
        return 1
    fi

    printf '%s' "$value" > "$_MAINFRAME_LIMIT_DIR/${type}.count"
    return 0
}

# Get the maximum for a given type
_limit_get_max() {
    local type="$1"

    case "$type" in
        files)   printf '%s' "$_MAINFRAME_LIMIT_MAX_FILES" ;;
        writes)  printf '%s' "$_MAINFRAME_LIMIT_MAX_WRITES" ;;
        time)    printf '%s' "$_MAINFRAME_LIMIT_MAX_TIME" ;;
        depth)   printf '%s' "$_MAINFRAME_LIMIT_MAX_DEPTH" ;;
        network) printf '%s' "$_MAINFRAME_LIMIT_MAX_NETWORK" ;;
        *)       printf '0' ; return 1 ;;
    esac
    return 0
}

# Validate that a type is known
_limit_valid_type() {
    local type="$1"
    case "$type" in
        files|writes|time|depth|network) return 0 ;;
        *) return 1 ;;
    esac
}

# Get epoch seconds (for time tracking)
_limit_epoch() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    else
        date +%s
    fi
}

# =============================================================================
# PUBLIC API
# =============================================================================

# @pre: none
# @post: tracking directory created, system enabled
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Initialize the limits tracking system. Creates a temporary directory
# for counter files and marks the system as active.
#
# Usage: mainframe_limit_init
mainframe_limit_init() {
    if [[ -n "$_MAINFRAME_LIMIT_DIR" ]] && [[ -d "$_MAINFRAME_LIMIT_DIR" ]]; then
        # Already initialized, just ensure enabled
        _MAINFRAME_LIMIT_ENABLED=1
        return 0
    fi

    _MAINFRAME_LIMIT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/mainframe_limits_$$.XXXXXX") || {
        _limit_error 1 "failed to create tracking directory"
        return 1
    }

    # Initialize all counters to 0
    local type
    for type in $_MAINFRAME_LIMIT_TYPES; do
        printf '0' > "$_MAINFRAME_LIMIT_DIR/${type}.count"
    done

    # Record start time for time limit tracking
    _limit_write_counter "start_time" "$(_limit_epoch)"

    _MAINFRAME_LIMIT_ENABLED=1
    return 0
}

# @pre: max is a positive integer
# @post: file operations limit set
# @returns: 0 on success, 1 on invalid input
#
# Set the maximum number of file operations (open, read, write, delete) allowed.
#
# Usage: mainframe_limit_files 100
mainframe_limit_files() {
    local max="$1"

    if [[ -z "$max" ]] || [[ ! "$max" =~ ^[0-9]+$ ]]; then
        _limit_error 1 "mainframe_limit_files requires a positive integer"
        return 1
    fi

    _MAINFRAME_LIMIT_MAX_FILES="$max"
    return 0
}

# @pre: size is a human-readable size string or integer bytes
# @post: write volume limit set
# @returns: 0 on success, 1 on invalid input
#
# Set the maximum total write volume allowed. Accepts human-readable sizes.
#
# Usage: mainframe_limit_writes "10MB"
# Usage: mainframe_limit_writes "1GB"
# Usage: mainframe_limit_writes 1048576
mainframe_limit_writes() {
    local size_str="$1"

    if [[ -z "$size_str" ]]; then
        _limit_error 1 "mainframe_limit_writes requires a size argument"
        return 1
    fi

    local bytes
    bytes=$(_limit_parse_size "$size_str") || {
        _limit_error 1 "invalid size format: $size_str"
        return 1
    }

    _MAINFRAME_LIMIT_MAX_WRITES="$bytes"
    return 0
}

# @pre: seconds is a positive integer
# @post: execution time limit set
# @returns: 0 on success, 1 on invalid input
#
# Set the maximum execution time in seconds.
#
# Usage: mainframe_limit_time 300
mainframe_limit_time() {
    local seconds="$1"

    if [[ -z "$seconds" ]] || [[ ! "$seconds" =~ ^[0-9]+$ ]]; then
        _limit_error 1 "mainframe_limit_time requires a positive integer (seconds)"
        return 1
    fi

    _MAINFRAME_LIMIT_MAX_TIME="$seconds"

    # Record start time if not already set
    if [[ "$_MAINFRAME_LIMIT_ENABLED" == "1" ]] && [[ -d "$_MAINFRAME_LIMIT_DIR" ]]; then
        local existing
        existing=$(_limit_read_counter "start_time")
        if [[ "$existing" == "0" ]]; then
            _limit_write_counter "start_time" "$(_limit_epoch)"
        fi
    fi

    return 0
}

# @pre: n is a positive integer
# @post: recursion/nesting depth limit set
# @returns: 0 on success, 1 on invalid input
#
# Set the maximum recursion or nesting depth.
#
# Usage: mainframe_limit_depth 10
mainframe_limit_depth() {
    local n="$1"

    if [[ -z "$n" ]] || [[ ! "$n" =~ ^[0-9]+$ ]]; then
        _limit_error 1 "mainframe_limit_depth requires a positive integer"
        return 1
    fi

    _MAINFRAME_LIMIT_MAX_DEPTH="$n"
    return 0
}

# @pre: n is a positive integer
# @post: network operations limit set
# @returns: 0 on success, 1 on invalid input
#
# Set the maximum number of network operations allowed.
#
# Usage: mainframe_limit_network 50
mainframe_limit_network() {
    local n="$1"

    if [[ -z "$n" ]] || [[ ! "$n" =~ ^[0-9]+$ ]]; then
        _limit_error 1 "mainframe_limit_network requires a positive integer"
        return 1
    fi

    _MAINFRAME_LIMIT_MAX_NETWORK="$n"
    return 0
}

# @pre: type is a valid limit type (files, writes, time, depth, network)
# @post: none (read-only check)
# @returns: 0 if within limits, 1 if exceeded
#
# Check whether a specific limit has been exceeded.
# For time limits, calculates elapsed time since init.
#
# Usage: mainframe_limit_check files || echo "File limit exceeded!"
mainframe_limit_check() {
    local type="$1"

    if [[ -z "$type" ]]; then
        _limit_error 1 "mainframe_limit_check requires a type argument"
        return 1
    fi

    if ! _limit_valid_type "$type"; then
        _limit_error 1 "unknown limit type: $type"
        return 1
    fi

    # If system not enabled, everything is within limits
    if [[ "$_MAINFRAME_LIMIT_ENABLED" != "1" ]]; then
        return 0
    fi

    local max
    max=$(_limit_get_max "$type")

    # 0 means unlimited
    if [[ "$max" == "0" ]]; then
        return 0
    fi

    local current

    if [[ "$type" == "time" ]]; then
        # Time is special: calculate elapsed
        local start_time now elapsed
        start_time=$(_limit_read_counter "start_time")
        now=$(_limit_epoch)
        elapsed=$(( now - start_time ))
        current="$elapsed"
    else
        current=$(_limit_read_counter "$type")
    fi

    if [[ "$current" -ge "$max" ]]; then
        return 1
    fi

    return 0
}

# @pre: type is a valid limit type, amount is a positive integer (default 1)
# @post: counter incremented by amount
# @returns: 0 on success, 1 on error
#
# Increment a usage counter. Used to track resource consumption.
#
# Usage: mainframe_limit_increment files
# Usage: mainframe_limit_increment writes 4096
mainframe_limit_increment() {
    local type="$1"
    local amount="${2:-1}"

    if [[ -z "$type" ]]; then
        _limit_error 1 "mainframe_limit_increment requires a type argument"
        return 1
    fi

    if ! _limit_valid_type "$type"; then
        _limit_error 1 "unknown limit type: $type"
        return 1
    fi

    if [[ ! "$amount" =~ ^[0-9]+$ ]]; then
        _limit_error 1 "amount must be a positive integer"
        return 1
    fi

    if [[ "$_MAINFRAME_LIMIT_ENABLED" != "1" ]] || [[ ! -d "$_MAINFRAME_LIMIT_DIR" ]]; then
        _limit_error 1 "limits system not initialized (call mainframe_limit_init first)"
        return 1
    fi

    # Time type cannot be incremented manually
    if [[ "$type" == "time" ]]; then
        _limit_error 1 "time limit is tracked automatically, cannot increment manually"
        return 1
    fi

    local current
    current=$(_limit_read_counter "$type")
    local new_value=$(( current + amount ))
    _limit_write_counter "$type" "$new_value"
    return 0
}

# @pre: limits system initialized
# @post: JSON or plain text status emitted to stdout
# @returns: 0
#
# Display status of all limits with current usage and maximums.
#
# Usage: mainframe_limit_status
mainframe_limit_status() {
    if [[ "$_MAINFRAME_LIMIT_ENABLED" != "1" ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"enabled":false,"limits":{}}\n'
        else
            printf 'Limits system: DISABLED\n'
        fi
        return 0
    fi

    local files_cur files_max writes_cur writes_max
    local time_cur time_max depth_cur depth_max network_cur network_max

    files_cur=$(_limit_read_counter "files")
    files_max="$_MAINFRAME_LIMIT_MAX_FILES"

    writes_cur=$(_limit_read_counter "writes")
    writes_max="$_MAINFRAME_LIMIT_MAX_WRITES"

    # Time: calculate elapsed
    local start_time now
    start_time=$(_limit_read_counter "start_time")
    now=$(_limit_epoch)
    time_cur=$(( now - start_time ))
    time_max="$_MAINFRAME_LIMIT_MAX_TIME"

    depth_cur=$(_limit_read_counter "depth")
    depth_max="$_MAINFRAME_LIMIT_MAX_DEPTH"

    network_cur=$(_limit_read_counter "network")
    network_max="$_MAINFRAME_LIMIT_MAX_NETWORK"

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '{"enabled":true,"limits":{'
        printf '"files":{"current":%d,"max":%d},' "$files_cur" "$files_max"
        printf '"writes":{"current":%d,"max":%d},' "$writes_cur" "$writes_max"
        printf '"time":{"current":%d,"max":%d},' "$time_cur" "$time_max"
        printf '"depth":{"current":%d,"max":%d},' "$depth_cur" "$depth_max"
        printf '"network":{"current":%d,"max":%d}' "$network_cur" "$network_max"
        printf '}}\n'
    else
        printf 'Limits system: ENABLED\n'
        printf '  files:   %d / %s\n' "$files_cur" "$( [[ $files_max -eq 0 ]] && printf 'unlimited' || printf '%d' "$files_max" )"
        printf '  writes:  %d / %s bytes\n' "$writes_cur" "$( [[ $writes_max -eq 0 ]] && printf 'unlimited' || printf '%d' "$writes_max" )"
        printf '  time:    %ds / %s\n' "$time_cur" "$( [[ $time_max -eq 0 ]] && printf 'unlimited' || printf '%ds' "$time_max" )"
        printf '  depth:   %d / %s\n' "$depth_cur" "$( [[ $depth_max -eq 0 ]] && printf 'unlimited' || printf '%d' "$depth_max" )"
        printf '  network: %d / %s\n' "$network_cur" "$( [[ $network_max -eq 0 ]] && printf 'unlimited' || printf '%d' "$network_max" )"
    fi
    return 0
}

# @pre: none
# @post: counters reset to 0 (all or specific type)
# @returns: 0 on success, 1 on error
#
# Reset usage counters. With no argument, resets all counters.
# With a type argument, resets only that counter.
#
# Usage: mainframe_limit_reset
# Usage: mainframe_limit_reset files
mainframe_limit_reset() {
    local type="${1:-}"

    if [[ -n "$type" ]]; then
        if ! _limit_valid_type "$type"; then
            _limit_error 1 "unknown limit type: $type"
            return 1
        fi

        if [[ "$type" == "time" ]]; then
            # Reset time means reset start_time to now
            if [[ "$_MAINFRAME_LIMIT_ENABLED" == "1" ]] && [[ -d "$_MAINFRAME_LIMIT_DIR" ]]; then
                _limit_write_counter "start_time" "$(_limit_epoch)"
            fi
        else
            if [[ "$_MAINFRAME_LIMIT_ENABLED" == "1" ]] && [[ -d "$_MAINFRAME_LIMIT_DIR" ]]; then
                _limit_write_counter "$type" "0"
            fi
        fi
        return 0
    fi

    # Reset all counters
    if [[ "$_MAINFRAME_LIMIT_ENABLED" == "1" ]] && [[ -d "$_MAINFRAME_LIMIT_DIR" ]]; then
        local t
        for t in $_MAINFRAME_LIMIT_TYPES; do
            if [[ "$t" == "time" ]]; then
                _limit_write_counter "start_time" "$(_limit_epoch)"
            else
                _limit_write_counter "$t" "0"
            fi
        done
    fi

    # Also reset the maximums
    _MAINFRAME_LIMIT_MAX_FILES=0
    _MAINFRAME_LIMIT_MAX_WRITES=0
    _MAINFRAME_LIMIT_MAX_TIME=0
    _MAINFRAME_LIMIT_MAX_DEPTH=0
    _MAINFRAME_LIMIT_MAX_NETWORK=0

    return 0
}

# @pre: type is a valid limit type
# @post: remaining quota printed to stdout
# @returns: 0 on success, 1 on error or exceeded
#
# Show the remaining quota for a specific limit type.
# Prints "unlimited" if no limit is set (max=0).
#
# Usage: remaining=$(mainframe_limit_remaining files)
mainframe_limit_remaining() {
    local type="$1"

    if [[ -z "$type" ]]; then
        _limit_error 1 "mainframe_limit_remaining requires a type argument"
        return 1
    fi

    if ! _limit_valid_type "$type"; then
        _limit_error 1 "unknown limit type: $type"
        return 1
    fi

    local max
    max=$(_limit_get_max "$type")

    # 0 means unlimited
    if [[ "$max" == "0" ]]; then
        printf 'unlimited'
        return 0
    fi

    local current

    if [[ "$type" == "time" ]]; then
        local start_time now
        start_time=$(_limit_read_counter "start_time")
        now=$(_limit_epoch)
        current=$(( now - start_time ))
    else
        current=$(_limit_read_counter "$type")
    fi

    local remaining=$(( max - current ))
    if [[ "$remaining" -lt 0 ]]; then
        remaining=0
        printf '%d' "$remaining"
        return 1
    fi

    printf '%d' "$remaining"
    return 0
}

# @pre: limits system initialized, command provided
# @post: command executed if within limits, blocked if exceeded
# @returns: 0 if command executed successfully, 1 if blocked or command failed
#
# Run a command only if the current limits allow it. Checks all active
# limits (those with max > 0) before executing. Increments the files
# counter by 1 after successful execution.
#
# Usage: mainframe_limit_enforce ls -la /tmp
# Usage: mainframe_limit_enforce cat file.txt
mainframe_limit_enforce() {
    if [[ $# -eq 0 ]]; then
        _limit_error 1 "mainframe_limit_enforce requires a command"
        return 1
    fi

    # If limits not enabled, just run the command
    if [[ "$_MAINFRAME_LIMIT_ENABLED" != "1" ]]; then
        "$@"
        return $?
    fi

    # Check all active limits
    local type
    for type in $_MAINFRAME_LIMIT_TYPES; do
        local max
        max=$(_limit_get_max "$type")
        if [[ "$max" != "0" ]]; then
            if ! mainframe_limit_check "$type"; then
                if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
                    local escaped_cmd
                    escaped_cmd=$(_limit_escape "$*")
                    printf '{"blocked":true,"type":"%s","command":"%s"}\n' "$type" "$escaped_cmd" >&2
                else
                    printf '[limits] BLOCKED: %s limit exceeded (command: %s)\n' "$type" "$*" >&2
                fi
                return 1
            fi
        fi
    done

    # Execute the command
    "$@"
    local rc=$?

    # Increment files counter on successful execution
    if [[ $rc -eq 0 ]]; then
        mainframe_limit_increment files 1 2>/dev/null || true
    fi

    return $rc
}

# @pre: none
# @post: none (read-only check)
# @returns: 0 if enabled, 1 if disabled
#
# Check if the limits system is currently active.
#
# Usage: mainframe_limit_is_enabled && echo "Limits active"
mainframe_limit_is_enabled() {
    [[ "$_MAINFRAME_LIMIT_ENABLED" == "1" ]]
}

# =============================================================================
# CLEANUP
# =============================================================================

# Clean up tracking directory on exit (only if we created it)
_mainframe_limit_cleanup() {
    if [[ -n "$_MAINFRAME_LIMIT_DIR" ]] && [[ -d "$_MAINFRAME_LIMIT_DIR" ]]; then
        rm -rf "$_MAINFRAME_LIMIT_DIR" 2>/dev/null || true
    fi
}

# Register cleanup trap only if not already registered
if [[ -z "${_MAINFRAME_LIMIT_TRAP_SET:-}" ]]; then
    trap _mainframe_limit_cleanup EXIT
    _MAINFRAME_LIMIT_TRAP_SET=1
fi

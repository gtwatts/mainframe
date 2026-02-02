#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/structured_log.sh - JSON-Structured Logging for Observability
# =============================================================================
# Description: Structured logging with JSON Lines output for AI agents and
#              observability platforms. Supports buffered writes, log rotation,
#              persistent context, and automatic caller detection.
#
# Usage:
#   slog_init --output "/var/log/agent.jsonl" --level "INFO"
#   slog_info "Processing task" task_id="123" duration_ms=50
#   slog_with_context service="agent" version="1.0"
#   slog_error "Failed to connect" error_code="E_CONN" retry=true
#
# Log Entry Format (JSON Lines):
#   {"timestamp":"2026-02-01T12:00:00.123Z","level":"INFO","message":"Processing task","task_id":"123","duration_ms":50,"caller":"process_item:42"}
#
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_STRUCTURED_LOG_LOADED:-}" ]] && return 0
readonly _MAINFRAME_STRUCTURED_LOG_LOADED=1

# =============================================================================
# CONSTANTS - Log Levels (numeric for comparison)
# =============================================================================

readonly SLOG_LEVEL_DEBUG=10
readonly SLOG_LEVEL_INFO=20
readonly SLOG_LEVEL_WARN=30
readonly SLOG_LEVEL_ERROR=40
readonly SLOG_LEVEL_FATAL=50

# =============================================================================
# STATE - Global Configuration
# =============================================================================

# Output destination: file path, "stderr", "stdout", or "both:<filepath>"
declare -g _SLOG_OUTPUT="${SLOG_OUTPUT:-stderr}"

# Current log level (minimum level to emit)
declare -g _SLOG_LEVEL="${SLOG_LEVEL:-$SLOG_LEVEL_INFO}"

# Persistent context fields (JSON fragment)
declare -g _SLOG_CONTEXT=""

# Write buffer for performance
declare -g _SLOG_BUFFER=""
declare -g _SLOG_BUFFER_COUNT=0
declare -g _SLOG_BUFFER_MAX="${SLOG_BUFFER_MAX:-10}"

# Rotation settings
declare -g _SLOG_ROTATE_SIZE="${SLOG_ROTATE_SIZE:-10485760}"  # 10MB default
declare -g _SLOG_ROTATE_COUNT="${SLOG_ROTATE_COUNT:-5}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Convert level name to numeric value
# Usage: _slog_level_num "INFO" -> 20
_slog_level_num() {
    local level="${1^^}"  # Uppercase
    case "$level" in
        DEBUG) echo "$SLOG_LEVEL_DEBUG" ;;
        INFO)  echo "$SLOG_LEVEL_INFO" ;;
        WARN|WARNING) echo "$SLOG_LEVEL_WARN" ;;
        ERROR) echo "$SLOG_LEVEL_ERROR" ;;
        FATAL) echo "$SLOG_LEVEL_FATAL" ;;
        *)     echo "$SLOG_LEVEL_INFO" ;;  # Default to INFO
    esac
}

# Get current timestamp with milliseconds (ISO 8601)
# Usage: _slog_timestamp -> "2026-02-01T12:00:00.123Z"
_slog_timestamp() {
    local epoch_sec epoch_ms

    # Try Bash 5.0+ EPOCHREALTIME first (most precise)
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        local epoch_real="$EPOCHREALTIME"
        epoch_sec="${epoch_real%%.*}"
        local frac="${epoch_real#*.}"
        # Pad to at least 3 digits for milliseconds
        frac="${frac}000"
        epoch_ms="${frac:0:3}"
    else
        # Fallback: try GNU date with nanoseconds
        local ns
        ns=$(date +%s%N 2>/dev/null)
        if [[ "$ns" =~ ^[0-9]+$ && ${#ns} -gt 6 ]]; then
            epoch_sec="${ns:0:${#ns}-9}"
            epoch_ms="${ns:${#ns}-9:3}"
        else
            # Last resort: seconds only, zero ms
            epoch_sec="${EPOCHSECONDS:-$(date +%s)}"
            epoch_ms="000"
        fi
    fi

    # Format as ISO 8601 with milliseconds
    # Use printf for portability (Bash 4.2+)
    printf '%(%Y-%m-%dT%H:%M:%S)T.%sZ\n' "$epoch_sec" "$epoch_ms"
}

# Escape string for JSON (delegate to json.sh if available, else inline)
# Usage: _slog_escape "hello \"world\"" -> hello \"world\"
_slog_escape() {
    local str="$1"
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
                # Check for control characters (< 0x20)
                if [[ "$char" < $'\x20' ]]; then
                    printf -v char '\\u%04x' "'$char"
                fi
                result+="$char"
                ;;
        esac
    done

    printf '%s' "$result"
}

# Get caller information (function:line)
# Usage: _slog_caller -> "process_item:42"
_slog_caller() {
    local frame=1
    local line func

    # Walk up the call stack to find non-internal caller
    while caller $frame 2>/dev/null | read -r line func _; do
        # Skip slog_* and _slog_* internal functions
        if [[ "$func" != slog_* && "$func" != _slog_* ]]; then
            printf '%s:%s' "$func" "$line"
            return 0
        fi
        ((frame++))
        # Safety limit
        [[ $frame -gt 20 ]] && break
    done

    # Fallback: direct script call
    local caller_line="${BASH_LINENO[1]:-0}"
    local caller_file="${BASH_SOURCE[2]:-main}"
    caller_file="${caller_file##*/}"  # Base name only
    printf '%s:%s' "$caller_file" "$caller_line"
}

# Write log entry to configured output
# Usage: _slog_write '{"timestamp":"...","level":"INFO",...}'
_slog_write() {
    local entry="$1"
    local output="$_SLOG_OUTPUT"

    case "$output" in
        stderr)
            printf '%s\n' "$entry" >&2
            ;;
        stdout)
            printf '%s\n' "$entry"
            ;;
        both:*)
            local file="${output#both:}"
            printf '%s\n' "$entry" >&2
            printf '%s\n' "$entry" >> "$file"
            ;;
        *)
            # File output
            printf '%s\n' "$entry" >> "$output"
            ;;
    esac
}

# Buffer a log entry and flush when buffer is full
# Usage: _slog_buffer_add '{"timestamp":"..."}'
_slog_buffer_add() {
    local entry="$1"

    _SLOG_BUFFER+="${entry}"$'\n'
    ((_SLOG_BUFFER_COUNT++)) || true

    if [[ $_SLOG_BUFFER_COUNT -ge $_SLOG_BUFFER_MAX ]]; then
        slog_flush
    fi
}

# Core logging function
# Usage: _slog_emit "INFO" "message" key="value" ...
_slog_emit() {
    local level="$1"
    local message="$2"
    shift 2

    # Check log level threshold
    local level_num current_level_num
    level_num=$(_slog_level_num "$level")
    current_level_num="$_SLOG_LEVEL"

    if [[ $level_num -lt $current_level_num ]]; then
        return 0
    fi

    # Build JSON log entry
    local timestamp caller_info
    timestamp=$(_slog_timestamp)
    caller_info=$(_slog_caller)

    local json="{"
    json+="\"timestamp\":\"$timestamp\""
    json+=",\"level\":\"${level^^}\""
    json+=",\"message\":\"$(_slog_escape "$message")\""
    json+=",\"caller\":\"$caller_info\""

    # Add persistent context fields
    if [[ -n "$_SLOG_CONTEXT" ]]; then
        json+=",$_SLOG_CONTEXT"
    fi

    # Add additional key=value pairs
    for pair in "$@"; do
        local key value type

        # Parse key:type=value or key=value
        if [[ "$pair" =~ ^([^:=]+):([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            type="${BASH_REMATCH[2]}"
            value="${BASH_REMATCH[3]}"
        elif [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            type="auto"
            value="${BASH_REMATCH[2]}"
        else
            continue
        fi

        # Format value based on type
        local json_value
        case "$type" in
            number|num|int|float)
                if [[ "$value" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]; then
                    json_value="$value"
                else
                    json_value="null"
                fi
                ;;
            bool|boolean)
                case "${value,,}" in
                    true|1|yes|on) json_value="true" ;;
                    *) json_value="false" ;;
                esac
                ;;
            raw|json)
                json_value="$value"
                ;;
            string)
                json_value="\"$(_slog_escape "$value")\""
                ;;
            auto|*)
                # Auto-detect type
                if [[ "$value" == "null" ]]; then
                    json_value="null"
                elif [[ "$value" == "true" || "$value" == "false" ]]; then
                    json_value="$value"
                elif [[ "$value" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]; then
                    json_value="$value"
                else
                    json_value="\"$(_slog_escape "$value")\""
                fi
                ;;
        esac

        json+=",\"$(_slog_escape "$key")\":$json_value"
    done

    json+="}"

    # Buffer or write directly
    if [[ $_SLOG_BUFFER_MAX -gt 1 ]]; then
        _slog_buffer_add "$json"
    else
        _slog_write "$json"
    fi
}

# =============================================================================
# PUBLIC API - Initialization
# =============================================================================

# Initialize structured logger
# Usage: slog_init --output "/var/log/agent.jsonl" --level "INFO"
#        slog_init --output "stderr"
#        slog_init --output "both:/var/log/agent.jsonl"
slog_init() {
    local output=""
    local level=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output|-o)
                output="$2"
                shift 2
                ;;
            --level|-l)
                level="$2"
                shift 2
                ;;
            --buffer-size|-b)
                _SLOG_BUFFER_MAX="$2"
                shift 2
                ;;
            --rotate-size|-r)
                _SLOG_ROTATE_SIZE="$2"
                shift 2
                ;;
            --rotate-count|-c)
                _SLOG_ROTATE_COUNT="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Apply settings
    if [[ -n "$output" ]]; then
        _SLOG_OUTPUT="$output"
    fi

    if [[ -n "$level" ]]; then
        _SLOG_LEVEL=$(_slog_level_num "$level")
    fi

    # Clear buffer and context
    _SLOG_BUFFER=""
    _SLOG_BUFFER_COUNT=0
    _SLOG_CONTEXT=""

    return 0
}

# =============================================================================
# PUBLIC API - Level-Specific Logging
# =============================================================================

# Log debug message
# Usage: slog_debug "Entering function" var_x=42 var_y="test"
slog_debug() {
    local message="$1"
    shift
    _slog_emit "DEBUG" "$message" "$@"
}

# Log info message
# Usage: slog_info "Processing task" task_id="123" status="running"
slog_info() {
    local message="$1"
    shift
    _slog_emit "INFO" "$message" "$@"
}

# Log warning message
# Usage: slog_warn "Connection slow" latency_ms=500 threshold_ms=200
slog_warn() {
    local message="$1"
    shift
    _slog_emit "WARN" "$message" "$@"
}

# Log error message
# Usage: slog_error "Failed to connect" error_code="E_CONN" host="db.example.com"
slog_error() {
    local message="$1"
    shift
    _slog_emit "ERROR" "$message" "$@"
}

# Log fatal message and exit
# Usage: slog_fatal "Unrecoverable error" reason="config missing"
slog_fatal() {
    local message="$1"
    shift
    _slog_emit "FATAL" "$message" "$@"
    slog_flush
    exit 1
}

# =============================================================================
# PUBLIC API - Configuration
# =============================================================================

# Set minimum log level
# Usage: slog_set_level "DEBUG"
#        slog_set_level "ERROR"
slog_set_level() {
    local level="$1"
    _SLOG_LEVEL=$(_slog_level_num "$level")
}

# Set output destination
# Usage: slog_set_output "/var/log/agent.jsonl"
#        slog_set_output "stderr"
#        slog_set_output "both:/var/log/agent.jsonl"
slog_set_output() {
    local output="$1"

    # Validate file path if it's a file (not stderr/stdout/both:)
    case "$output" in
        stderr|stdout)
            ;;
        both:*)
            local file="${output#both:}"
            local dir="${file%/*}"
            if [[ "$dir" != "$file" && ! -d "$dir" ]]; then
                printf 'slog_set_output: directory does not exist: %s\n' "$dir" >&2
                return 1
            fi
            ;;
        *)
            local dir="${output%/*}"
            if [[ "$dir" != "$output" && ! -d "$dir" ]]; then
                printf 'slog_set_output: directory does not exist: %s\n' "$dir" >&2
                return 1
            fi
            ;;
    esac

    _SLOG_OUTPUT="$output"
    return 0
}

# Add persistent context fields (included in all subsequent log entries)
# Usage: slog_with_context service="agent" version="1.0" environment="prod"
slog_with_context() {
    local fragment=""

    for pair in "$@"; do
        local key value

        if [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
        else
            continue
        fi

        [[ -n "$fragment" ]] && fragment+=","
        fragment+="\"$(_slog_escape "$key")\":\"$(_slog_escape "$value")\""
    done

    if [[ -n "$_SLOG_CONTEXT" ]]; then
        _SLOG_CONTEXT+=",$fragment"
    else
        _SLOG_CONTEXT="$fragment"
    fi
}

# Clear all persistent context fields
# Usage: slog_clear_context
slog_clear_context() {
    _SLOG_CONTEXT=""
}

# =============================================================================
# PUBLIC API - Buffer Management
# =============================================================================

# Flush buffered logs to output
# Usage: slog_flush
slog_flush() {
    if [[ -z "$_SLOG_BUFFER" ]]; then
        return 0
    fi

    local output="$_SLOG_OUTPUT"

    case "$output" in
        stderr)
            printf '%s' "$_SLOG_BUFFER" >&2
            ;;
        stdout)
            printf '%s' "$_SLOG_BUFFER"
            ;;
        both:*)
            local file="${output#both:}"
            printf '%s' "$_SLOG_BUFFER" >&2
            printf '%s' "$_SLOG_BUFFER" >> "$file"
            ;;
        *)
            printf '%s' "$_SLOG_BUFFER" >> "$output"
            ;;
    esac

    _SLOG_BUFFER=""
    _SLOG_BUFFER_COUNT=0
}

# =============================================================================
# PUBLIC API - Log Rotation
# =============================================================================

# Rotate log file if it exceeds the configured size
# Usage: slog_rotate
slog_rotate() {
    local output="$_SLOG_OUTPUT"

    # Extract file path
    case "$output" in
        stderr|stdout)
            return 0  # Nothing to rotate
            ;;
        both:*)
            output="${output#both:}"
            ;;
    esac

    # Check if file exists
    if [[ ! -f "$output" ]]; then
        return 0
    fi

    # Get file size
    local size
    if [[ "$OSTYPE" == darwin* ]]; then
        size=$(stat -f%z "$output" 2>/dev/null || echo "0")
    else
        size=$(stat -c%s "$output" 2>/dev/null || echo "0")
    fi

    # Check if rotation needed
    if [[ $size -lt $_SLOG_ROTATE_SIZE ]]; then
        return 0
    fi

    # Flush buffer first
    slog_flush

    # Rotate existing files (shift .N -> .N+1)
    local i
    for ((i = _SLOG_ROTATE_COUNT - 1; i >= 1; i--)); do
        local prev=$((i - 1))
        if [[ $prev -eq 0 ]]; then
            [[ -f "$output" ]] && mv "$output" "${output}.1"
        else
            [[ -f "${output}.${prev}" ]] && mv "${output}.${prev}" "${output}.${i}"
        fi
    done

    # Remove oldest if it exceeds count
    local oldest="${output}.${_SLOG_ROTATE_COUNT}"
    [[ -f "$oldest" ]] && rm -f "$oldest"

    return 0
}

# =============================================================================
# PUBLIC API - Utility Functions
# =============================================================================

# Get current log level name
# Usage: level=$(slog_get_level)
slog_get_level() {
    case "$_SLOG_LEVEL" in
        "$SLOG_LEVEL_DEBUG") echo "DEBUG" ;;
        "$SLOG_LEVEL_INFO")  echo "INFO" ;;
        "$SLOG_LEVEL_WARN")  echo "WARN" ;;
        "$SLOG_LEVEL_ERROR") echo "ERROR" ;;
        "$SLOG_LEVEL_FATAL") echo "FATAL" ;;
        *) echo "UNKNOWN" ;;
    esac
}

# Get current output destination
# Usage: output=$(slog_get_output)
slog_get_output() {
    printf '%s' "$_SLOG_OUTPUT"
}

# Check if a level would be logged
# Usage: slog_would_log "DEBUG" && expensive_debug_operation
slog_would_log() {
    local level="$1"
    local level_num
    level_num=$(_slog_level_num "$level")
    [[ $level_num -ge $_SLOG_LEVEL ]]
}

# Get structured log statistics
# Usage: slog_stats
slog_stats() {
    printf '{"buffer_count":%d,"buffer_max":%d,"level":"%s","output":"%s","context_set":%s}\n' \
        "$_SLOG_BUFFER_COUNT" \
        "$_SLOG_BUFFER_MAX" \
        "$(slog_get_level)" \
        "$(_slog_escape "$_SLOG_OUTPUT")" \
        "$([[ -n "$_SLOG_CONTEXT" ]] && echo "true" || echo "false")"
}

# =============================================================================
# PUBLIC API - Nameref Variants (High Performance)
# =============================================================================

# Build log entry into variable (avoids subshell)
# Usage: slog_build_v result "INFO" "message" key="value"
slog_build_v() {
    local -n __sbv_out=$1
    local level="$2"
    local message="$3"
    shift 3

    local timestamp caller_info
    timestamp=$(_slog_timestamp)
    caller_info=$(_slog_caller)

    __sbv_out="{"
    __sbv_out+="\"timestamp\":\"$timestamp\""
    __sbv_out+=",\"level\":\"${level^^}\""
    __sbv_out+=",\"message\":\"$(_slog_escape "$message")\""
    __sbv_out+=",\"caller\":\"$caller_info\""

    # Add persistent context
    if [[ -n "$_SLOG_CONTEXT" ]]; then
        __sbv_out+=",$_SLOG_CONTEXT"
    fi

    # Add additional fields
    for pair in "$@"; do
        local key value

        if [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
        else
            continue
        fi

        # Auto-detect type
        local json_value
        if [[ "$value" == "null" ]]; then
            json_value="null"
        elif [[ "$value" == "true" || "$value" == "false" ]]; then
            json_value="$value"
        elif [[ "$value" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]; then
            json_value="$value"
        else
            json_value="\"$(_slog_escape "$value")\""
        fi

        __sbv_out+=",\"$(_slog_escape "$key")\":$json_value"
    done

    __sbv_out+="}"
}

# =============================================================================
# CLEANUP - Register flush on exit
# =============================================================================

# Auto-flush on script exit
_slog_cleanup() {
    slog_flush
}

# Register cleanup if trap mechanism available
if [[ -z "${_SLOG_TRAP_SET:-}" ]]; then
    trap _slog_cleanup EXIT
    readonly _SLOG_TRAP_SET=1
fi

# =============================================================================
# MODULE EXPORTS
# =============================================================================

_STRUCTURED_LOG_EXPORTS=(
    # Initialization
    slog_init
    # Level-specific logging
    slog_debug
    slog_info
    slog_warn
    slog_error
    slog_fatal
    # Configuration
    slog_set_level
    slog_set_output
    slog_with_context
    slog_clear_context
    # Buffer management
    slog_flush
    # Rotation
    slog_rotate
    # Utilities
    slog_get_level
    slog_get_output
    slog_would_log
    slog_stats
    # Nameref variants
    slog_build_v
)

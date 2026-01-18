#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/log.sh - Structured JSON Logging
# =============================================================================
# Description: Production-grade logging with JSON output, log levels,
#              context fields, timing, and rotation helpers
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_LOG_LOADED:-}" ]] && return 0
readonly _MAINFRAME_LOG_LOADED=1

# Source JSON library for structured output
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/json.sh
source "$SCRIPT_DIR/json.sh"

# =============================================================================
# GLOBAL CONFIGURATION
# =============================================================================

# Log levels (numeric for comparison)
declare -gA _LOG_LEVELS=(
    [debug]=0
    [info]=1
    [warn]=2
    [error]=3
    [fatal]=4
)

# Current configuration
declare -g _LOG_LEVEL="info"
declare -g _LOG_FORMAT="text"           # text, json, pretty
declare -g _LOG_OUTPUT=""               # Empty = stdout
declare -gA _LOG_CONTEXT=()             # Persistent context fields

# Timing state
declare -gA _LOG_TIMERS=()

# Color codes for pretty output
declare -gA _LOG_COLORS=(
    [debug]="\033[36m"    # Cyan
    [info]="\033[32m"     # Green
    [warn]="\033[33m"     # Yellow
    [error]="\033[31m"    # Red
    [fatal]="\033[35m"    # Magenta
    [reset]="\033[0m"
)

# =============================================================================
# CONFIGURATION FUNCTIONS
# =============================================================================

# Set minimum log level
# Usage: log::set_level "debug"  # debug, info, warn, error, fatal
log::set_level() {
    local level="${1,,}"  # lowercase
    if [[ -n "${_LOG_LEVELS[$level]:-}" ]]; then
        _LOG_LEVEL="$level"
    else
        log::warn "Invalid log level: $level (using info)"
        _LOG_LEVEL="info"
    fi
}

# Get current log level
# Usage: level=$(log::get_level)
log::get_level() {
    printf '%s' "$_LOG_LEVEL"
}

# Set output format
# Usage: log::set_format "json"  # json, text, pretty
log::set_format() {
    local format="${1,,}"
    case "$format" in
        json|text|pretty)
            _LOG_FORMAT="$format"
            ;;
        *)
            log::warn "Invalid log format: $format (using text)"
            _LOG_FORMAT="text"
            ;;
    esac
}

# Get current format
# Usage: fmt=$(log::get_format)
log::get_format() {
    printf '%s' "$_LOG_FORMAT"
}

# Set output destination
# Usage: log::set_output "/var/log/app.log"
# Usage: log::set_output ""  # stdout
log::set_output() {
    local output="$1"
    if [[ -n "$output" ]]; then
        # Ensure parent directory exists
        local dir="${output%/*}"
        if [[ -n "$dir" && "$dir" != "$output" ]]; then
            mkdir -p "$dir" 2>/dev/null || {
                log::error "Cannot create log directory: $dir"
                return 1
            }
        fi
        # Test write access
        if ! touch "$output" 2>/dev/null; then
            log::error "Cannot write to log file: $output"
            return 1
        fi
    fi
    _LOG_OUTPUT="$output"
}

# Get current output
# Usage: out=$(log::get_output)
log::get_output() {
    printf '%s' "$_LOG_OUTPUT"
}

# Set persistent context fields
# Usage: log::set_context app="myapp" env="prod" version="1.0.0"
log::set_context() {
    local pair key value
    for pair in "$@"; do
        if [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            _LOG_CONTEXT["$key"]="$value"
        fi
    done
}

# Clear context fields
# Usage: log::clear_context
log::clear_context() {
    _LOG_CONTEXT=()
}

# Get context as JSON fragment
# Usage: ctx=$(log::get_context)
log::get_context() {
    local first=true
    for key in "${!_LOG_CONTEXT[@]}"; do
        $first || printf ','
        first=false
        printf '"%s":' "$(json_escape "$key")"
        json_value "${_LOG_CONTEXT[$key]}"
    done
}

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Check if level should be logged
_log_should_log() {
    local level="$1"
    local current_num="${_LOG_LEVELS[$_LOG_LEVEL]:-1}"
    local check_num="${_LOG_LEVELS[$level]:-1}"
    ((check_num >= current_num))
}

# Generate ISO8601 timestamp
_log_timestamp() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# Write output to appropriate destination
_log_write() {
    local msg="$1"
    if [[ -n "$_LOG_OUTPUT" ]]; then
        printf '%s\n' "$msg" >> "$_LOG_OUTPUT"
    else
        printf '%s\n' "$msg"
    fi
}

# Format and write a log entry
_log_emit() {
    local level="$1"
    local message="$2"
    shift 2
    
    # Check level threshold
    _log_should_log "$level" || return 0
    
    local timestamp
    timestamp=$(_log_timestamp)
    
    case "$_LOG_FORMAT" in
        json)
            _log_emit_json "$level" "$message" "$timestamp" "$@"
            ;;
        pretty)
            _log_emit_pretty "$level" "$message" "$timestamp" "$@"
            ;;
        text|*)
            _log_emit_text "$level" "$message" "$timestamp" "$@"
            ;;
    esac
}

# Emit JSON format
_log_emit_json() {
    local level="$1"
    local message="$2"
    local timestamp="$3"
    shift 3
    
    local json="{"
    json+="\"level\":\"$level\""
    json+=",\"msg\":\"$(json_escape "$message")\""
    json+=",\"timestamp\":\"$timestamp\""
    
    # Add context fields
    local ctx
    ctx=$(log::get_context)
    if [[ -n "$ctx" ]]; then
        json+=",$ctx"
    fi
    
    # Add extra fields from arguments
    local pair key value
    for pair in "$@"; do
        if [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            json+=",\"$(json_escape "$key")\":"
            json+="$(json_value "$value")"
        fi
    done
    
    json+="}"
    _log_write "$json"
}

# Emit pretty format (colored for terminals)
_log_emit_pretty() {
    local level="$1"
    local message="$2"
    local timestamp="$3"
    shift 3
    
    local color="${_LOG_COLORS[$level]:-}"
    local reset="${_LOG_COLORS[reset]}"
    local level_upper="${level^^}"
    local level_padded
    printf -v level_padded '%-5s' "$level_upper"
    
    local output="${color}${level_padded}${reset} [${timestamp}] ${message}"
    
    # Add extra fields
    if (($# > 0)); then
        output+=" {"
        local first=true
        for pair in "$@"; do
            $first || output+=", "
            first=false
            output+="$pair"
        done
        output+="}"
    fi
    
    # Add context if present
    if ((${#_LOG_CONTEXT[@]} > 0)); then
        output+=" ctx:{"
        local first=true
        for key in "${!_LOG_CONTEXT[@]}"; do
            $first || output+=", "
            first=false
            output+="${key}=${_LOG_CONTEXT[$key]}"
        done
        output+="}"
    fi
    
    _log_write "$output"
}

# Emit text format (plain)
_log_emit_text() {
    local level="$1"
    local message="$2"
    local timestamp="$3"
    shift 3
    
    local level_upper="${level^^}"
    local level_padded
    printf -v level_padded '%-5s' "$level_upper"
    
    local output="${level_padded} [${timestamp}] ${message}"
    
    # Add extra fields
    if (($# > 0)); then
        output+=" {"
        local first=true
        for pair in "$@"; do
            $first || output+=", "
            first=false
            output+="$pair"
        done
        output+="}"
    fi
    
    # Add context if present
    if ((${#_LOG_CONTEXT[@]} > 0)); then
        output+=" ctx:{"
        local first=true
        for key in "${!_LOG_CONTEXT[@]}"; do
            $first || output+=", "
            first=false
            output+="${key}=${_LOG_CONTEXT[$key]}"
        done
        output+="}"
    fi
    
    _log_write "$output"
}

# =============================================================================
# BASIC LOGGING FUNCTIONS
# =============================================================================

# Debug level logging
# Usage: log::debug "Debug message" [key=value ...]
log::debug() {
    local msg="$1"
    shift
    _log_emit "debug" "$msg" "$@"
}

# Info level logging
# Usage: log::info "Info message" [key=value ...]
log::info() {
    local msg="$1"
    shift
    _log_emit "info" "$msg" "$@"
}

# Warning level logging
# Usage: log::warn "Warning message" [key=value ...]
log::warn() {
    local msg="$1"
    shift
    _log_emit "warn" "$msg" "$@"
}

# Error level logging
# Usage: log::error "Error message" [key=value ...]
log::error() {
    local msg="$1"
    shift
    _log_emit "error" "$msg" "$@"
}

# Fatal level logging (also exits with code 1)
# Usage: log::fatal "Fatal error" [key=value ...]
log::fatal() {
    local msg="$1"
    shift
    _log_emit "fatal" "$msg" "$@"
    exit 1
}

# =============================================================================
# JSON STRUCTURED LOGGING
# =============================================================================

# Emit JSON log with explicit level
# Usage: log::json "info" "User logged in" user_id=123 ip="1.2.3.4" action="login"
log::json() {
    local level="${1,,}"
    local message="$2"
    shift 2
    
    # Validate level
    if [[ -z "${_LOG_LEVELS[$level]:-}" ]]; then
        level="info"
    fi
    
    # Check level threshold
    _log_should_log "$level" || return 0
    
    local timestamp
    timestamp=$(_log_timestamp)
    
    local json="{"
    json+="\"level\":\"$level\""
    json+=",\"msg\":\"$(json_escape "$message")\""
    
    # Add extra fields from arguments
    local pair key value
    for pair in "$@"; do
        if [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            json+=",\"$(json_escape "$key")\":"
            json+="$(json_value "$value")"
        fi
    done
    
    # Add context fields
    local ctx
    ctx=$(log::get_context)
    if [[ -n "$ctx" ]]; then
        json+=",$ctx"
    fi
    
    json+=",\"timestamp\":\"$timestamp\""
    json+="}"
    
    _log_write "$json"
}

# =============================================================================
# TIMING / PERFORMANCE LOGGING
# =============================================================================

# Start a timer for an operation
# Usage: log::time_start "operation_name"
log::time_start() {
    local name="$1"
    local now
    now=$(date +%s%N 2>/dev/null || date +%s)000000000
    _LOG_TIMERS["$name"]="$now"
}

# End timer and log duration
# Usage: log::time_end "operation_name" [key=value ...]
log::time_end() {
    local name="$1"
    shift
    
    local start="${_LOG_TIMERS[$name]:-}"
    if [[ -z "$start" ]]; then
        log::warn "Timer not found: $name"
        return 1
    fi
    
    local end
    end=$(date +%s%N 2>/dev/null || date +%s)000000000
    
    # Calculate duration in milliseconds
    local duration_ns=$((end - start))
    local duration_ms=$((duration_ns / 1000000))
    
    # Format duration for display
    local duration_str
    if ((duration_ms < 1000)); then
        duration_str="${duration_ms}ms"
    elif ((duration_ms < 60000)); then
        local secs=$((duration_ms / 1000))
        local ms=$((duration_ms % 1000))
        duration_str="${secs}.${ms}s"
    else
        local mins=$((duration_ms / 60000))
        local secs=$(((duration_ms % 60000) / 1000))
        duration_str="${mins}m${secs}s"
    fi
    
    # Clean up timer
    unset '_LOG_TIMERS[$name]'
    
    # Log the timing
    log::info "Timer completed: $name" "duration=$duration_str" "duration_ms=$duration_ms" "$@"
}

# Time a command and log its duration
# Usage: log::time "operation_name" command args...
log::time() {
    local name="$1"
    shift
    
    log::time_start "$name"
    local result=0
    "$@" || result=$?
    log::time_end "$name" "exit_code=$result"
    return $result
}

# =============================================================================
# LOG ROTATION HELPERS
# =============================================================================

# Parse size string to bytes
_log_parse_size() {
    local size="$1"
    local num="${size%[KMGkmg]}"
    local unit="${size: -1}"
    
    case "${unit^^}" in
        K) echo $((num * 1024)) ;;
        M) echo $((num * 1024 * 1024)) ;;
        G) echo $((num * 1024 * 1024 * 1024)) ;;
        *) echo "$size" ;;
    esac
}

# Rotate log file if it exceeds max size
# Usage: log::rotate "/var/log/app.log" --max-size 10M --keep 5
log::rotate() {
    local file="$1"
    shift
    
    local max_size="10M"
    local keep=5
    
    # Parse options
    while (($# > 0)); do
        case "$1" in
            --max-size|-s)
                max_size="$2"
                shift 2
                ;;
            --keep|-k)
                keep="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Check if file exists
    [[ -f "$file" ]] || return 0
    
    # Get file size
    local file_size
    file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
    
    # Parse max size to bytes
    local max_bytes
    max_bytes=$(_log_parse_size "$max_size")
    
    # Check if rotation needed
    if ((file_size < max_bytes)); then
        return 0
    fi
    
    log::info "Rotating log file" "file=$file" "size=$file_size" "max=$max_bytes"
    
    # Remove oldest if we're at the limit
    local oldest="${file}.${keep}"
    [[ -f "$oldest" ]] && rm -f "$oldest"
    
    # Shift existing rotated files
    local i
    for ((i = keep - 1; i >= 1; i--)); do
        local current="${file}.${i}"
        local next="${file}.$((i + 1))"
        [[ -f "$current" ]] && mv "$current" "$next"
    done
    
    # Rotate current file
    mv "$file" "${file}.1"
    
    # Create new empty file
    touch "$file"
    
    log::info "Log rotation complete" "file=$file" "kept=$keep"
}

# Check if rotation is needed (without rotating)
# Usage: if log::needs_rotation "/var/log/app.log" 10M; then ...; fi
log::needs_rotation() {
    local file="$1"
    local max_size="${2:-10M}"
    
    [[ -f "$file" ]] || return 1
    
    local file_size
    file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
    
    local max_bytes
    max_bytes=$(_log_parse_size "$max_size")
    
    ((file_size >= max_bytes))
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Log with caller information (file:line:function)
# Usage: log::trace "Something happened"
log::trace() {
    local msg="$1"
    shift
    
    local func="${FUNCNAME[1]:-main}"
    local line="${BASH_LINENO[0]:-0}"
    local source="${BASH_SOURCE[1]:-unknown}"
    source="${source##*/}"  # basename
    
    _log_emit "debug" "$msg" "caller=${func}" "source=${source}:${line}" "$@"
}

# Log with printf-style formatting
# Usage: log::infof "User %s logged in from %s" "$user" "$ip"
# shellcheck disable=SC2059  # Variable format string is intentional for printf-style logging
log::debugf() { local fmt="$1"; shift; local msg; printf -v msg "$fmt" "$@"; log::debug "$msg"; }
log::infof()  { local fmt="$1"; shift; local msg; printf -v msg "$fmt" "$@"; log::info "$msg"; }
log::warnf()  { local fmt="$1"; shift; local msg; printf -v msg "$fmt" "$@"; log::warn "$msg"; }
log::errorf() { local fmt="$1"; shift; local msg; printf -v msg "$fmt" "$@"; log::error "$msg"; }
log::fatalf() { local fmt="$1"; shift; local msg; printf -v msg "$fmt" "$@"; log::fatal "$msg"; }

# Conditional logging (only logs if condition is true)
# Usage: log::debug_if "$DEBUG" "Detailed info"
log::debug_if() { [[ -n "$1" && "$1" != "0" && "$1" != "false" ]] && { shift; log::debug "$@"; }; }
log::info_if()  { [[ -n "$1" && "$1" != "0" && "$1" != "false" ]] && { shift; log::info "$@"; }; }
log::warn_if()  { [[ -n "$1" && "$1" != "0" && "$1" != "false" ]] && { shift; log::warn "$@"; }; }
log::error_if() { [[ -n "$1" && "$1" != "0" && "$1" != "false" ]] && { shift; log::error "$@"; }; }

# Log an error and return error code (doesn't exit like fatal)
# Usage: log::fail "Something went wrong" && return 1
log::fail() {
    log::error "$@"
    return 1
}

# Create a child logger with additional context
# Usage: mylog=$(log::child service="auth" component="login")
#        $mylog "User authenticated"  # includes service and component
log::child() {
    local context_args="$*"
    echo "log::info \"\$1\" $context_args"
}

# Log environment information (useful for debugging)
# Usage: log::env
log::env() {
    log::debug "Environment" \
        "bash_version=${BASH_VERSION:-unknown}" \
        "user=${USER:-unknown}" \
        "pwd=${PWD:-unknown}" \
        "hostname=${HOSTNAME:-$(hostname 2>/dev/null || echo unknown)}"
}

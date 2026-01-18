#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/error.sh - Error Handling, Try/Catch, and Stack Traces
# =============================================================================
# Description: Structured error handling with try/catch pattern, stack traces,
#              and error context for better debugging and error recovery
# Purpose: Provides robust error handling patterns that are often missing in
#          bash scripts, enabling cleaner error recovery and debugging
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_ERROR_LOADED:-}" ]] && return 0
readonly _MAINFRAME_ERROR_LOADED=1

# =============================================================================
# GLOBAL STATE
# =============================================================================

# Error state variables
declare -g ERROR_MESSAGE=""           # Last error message
declare -g ERROR_CODE=0               # Last error exit code
declare -g ERROR_LINE=0               # Line where error occurred
declare -g ERROR_FUNC=""              # Function where error occurred
declare -g ERROR_SOURCE=""            # Source file where error occurred

# Error context stack (for nested operations)
declare -ga _ERROR_CONTEXT_STACK=()   # Stack of operation:details pairs

# Try/catch state
declare -gi _ERROR_TRY_DEPTH=0        # Nesting depth of try blocks
declare -ga _ERROR_TRY_STATES=()      # Saved set -e states per depth

# =============================================================================
# STACK TRACE FUNCTIONS
# =============================================================================

# Print a stack trace from the current location
# Usage: error::stack_trace [skip_frames]
# Arguments:
#   skip_frames - Number of stack frames to skip (default: 1, skips this function)
# Output: Prints stack trace to stderr in format:
#   Stack trace:
#     at function_name (file.sh:line)
#     at caller_name (file.sh:line)
#     ...
error::stack_trace() {
    local skip="${1:-1}"
    local frame=0
    
    printf '%s\n' "Stack trace:" >&2
    
    # Walk up the call stack using BASH_SOURCE, BASH_LINENO, FUNCNAME
    while true; do
        local func="${FUNCNAME[$((frame + skip))]:-}"
        local line="${BASH_LINENO[$((frame + skip - 1))]:-}"
        local source="${BASH_SOURCE[$((frame + skip))]:-}"
        
        # Stop when we run out of frames
        [[ -z "$func" ]] && break
        
        # Format source path (use basename for cleaner output, full path available)
        local source_display="${source##*/}"
        [[ -z "$source_display" ]] && source_display="<unknown>"
        
        # Print frame
        printf '  at %s (%s:%s)\n' "$func" "$source_display" "$line" >&2
        
        # Stop at main
        [[ "$func" == "main" ]] && break
        
        ((frame++))
    done
}

# Get stack trace as a string (for logging, storing in variables)
# Usage: trace=$(error::stack_trace_string [skip_frames])
error::stack_trace_string() {
    local skip="${1:-1}"
    local result=""
    local frame=0
    
    result+="Stack trace:\n"
    
    while true; do
        local func="${FUNCNAME[$((frame + skip + 1))]:-}"
        local line="${BASH_LINENO[$((frame + skip))]:-}"
        local source="${BASH_SOURCE[$((frame + skip + 1))]:-}"
        
        [[ -z "$func" ]] && break
        
        local source_display="${source##*/}"
        [[ -z "$source_display" ]] && source_display="<unknown>"
        
        result+="  at ${func} (${source_display}:${line})\n"
        
        [[ "$func" == "main" ]] && break
        ((frame++))
    done
    
    printf '%b' "$result"
}

# Get caller info at specific depth
# Usage: error::caller [depth]
# Returns: "function:file:line"
error::caller() {
    local depth="${1:-1}"
    local func="${FUNCNAME[$((depth + 1))]:-main}"
    local line="${BASH_LINENO[$depth]:-0}"
    local source="${BASH_SOURCE[$((depth + 1))]:-unknown}"
    
    printf '%s:%s:%s' "$func" "${source##*/}" "$line"
}

# =============================================================================
# ERROR CONTEXT FUNCTIONS
# =============================================================================

# Push operation context onto the stack (for nested error reporting)
# Usage: error::context "operation" "details"
# Example:
#   error::context "parsing" "config.json"
#   error::context "validating" "user input"
error::context() {
    local operation="${1:-unknown}"
    local details="${2:-}"
    
    if [[ -n "$details" ]]; then
        _ERROR_CONTEXT_STACK+=("${operation}: ${details}")
    else
        _ERROR_CONTEXT_STACK+=("${operation}")
    fi
}

# Pop the most recent context from the stack
# Usage: error::context_pop
error::context_pop() {
    local len=${#_ERROR_CONTEXT_STACK[@]}
    if ((len > 0)); then
        unset '_ERROR_CONTEXT_STACK[-1]'
    fi
}

# Clear all error context
# Usage: error::context_clear
error::context_clear() {
    _ERROR_CONTEXT_STACK=()
}

# Get current context as formatted string
# Usage: context=$(error::context_string)
error::context_string() {
    local len=${#_ERROR_CONTEXT_STACK[@]}
    
    if ((len == 0)); then
        printf ''
        return
    fi
    
    printf 'Context:\n'
    local i
    for ((i = len - 1; i >= 0; i--)); do
        printf '  → %s\n' "${_ERROR_CONTEXT_STACK[$i]}"
    done
}

# Execute a command with context (auto-pops on completion)
# Usage: error::with_context "operation" "details" command args...
# Example: error::with_context "parsing" "file.json" jq '.key' file.json
error::with_context() {
    local operation="$1"
    local details="$2"
    shift 2
    
    error::context "$operation" "$details"
    local result=0
    "$@" || result=$?
    error::context_pop
    
    return $result
}

# =============================================================================
# THROW FUNCTIONS
# =============================================================================

# Throw an error with message (sets error state and optionally exits)
# Usage: error::throw "message" [exit_code] [--no-exit]
# Options:
#   exit_code  - Exit code (default: 1)
#   --no-exit  - Set error state but don't exit (for use in try blocks)
error::throw() {
    local message="$1"
    local code="${2:-1}"
    local no_exit=false
    
    # Check for --no-exit flag
    if [[ "${2:-}" == "--no-exit" ]]; then
        no_exit=true
        code=1
    elif [[ "${3:-}" == "--no-exit" ]]; then
        no_exit=true
    fi
    
    # Populate error state
    ERROR_MESSAGE="$message"
    ERROR_CODE="$code"
    ERROR_LINE="${BASH_LINENO[0]:-0}"
    ERROR_FUNC="${FUNCNAME[1]:-main}"
    ERROR_SOURCE="${BASH_SOURCE[1]:-unknown}"
    
    # If inside a try block, just return with error code (don't exit)
    if ((_ERROR_TRY_DEPTH > 0)); then
        return "$code"
    fi
    
    # Print error with context and stack trace
    printf '%sError:%s %s\n' "${CLR_RED:-}" "${CLR_RESET:-}" "$message" >&2
    
    # Print context if any
    local ctx
    ctx=$(error::context_string)
    if [[ -n "$ctx" ]]; then
        printf '%s' "$ctx" >&2
    fi
    
    # Print stack trace
    error::stack_trace 2
    
    # Exit unless --no-exit
    if ! $no_exit; then
        exit "$code"
    fi
    
    return "$code"
}

# Throw with formatted message
# Usage: error::throwf format args...
# Example: error::throwf "Failed to open file: %s" "$filename"
error::throwf() {
    local format="$1"
    shift
    local message
    # shellcheck disable=SC2059
    printf -v message "$format" "$@"
    error::throw "$message"
}

# Assert a condition, throw if false
# Usage: error::assert "condition" "message"
# Example: error::assert "[[ -f $file ]]" "File must exist"
error::assert() {
    local condition="$1"
    local message="${2:-Assertion failed}"
    
    if ! eval "$condition"; then
        error::throw "$message: $condition"
    fi
}

# =============================================================================
# TRY/CATCH IMPLEMENTATION
# =============================================================================

# Begin a try block - errors will be caught instead of exiting
# Usage:
#   try
#   (
#       risky_command
#       another_command
#   )
#   catch && {
#       echo "Error caught: $ERROR_MESSAGE"
#   }
#
# Alternative inline syntax:
#   try { risky_command; } catch { echo "caught: $ERROR_MESSAGE"; }
#
try() {
    # Handle brace syntax: try { commands; }
    if [[ "${1:-}" == "{" ]]; then
        shift
        _error_try_brace "$@"
        return $?
    fi
    
    # Save current errexit state
    local errexit_enabled=false
    if [[ "$-" == *e* ]]; then
        errexit_enabled=true
    fi
    _ERROR_TRY_STATES[_ERROR_TRY_DEPTH]="$errexit_enabled"
    
    # Increment try depth
    ((_ERROR_TRY_DEPTH++))
    
    # Clear previous error state
    ERROR_MESSAGE=""
    ERROR_CODE=0
    ERROR_LINE=0
    ERROR_FUNC=""
    ERROR_SOURCE=""
    
    # Disable errexit for try block
    set +e
    
    return 0
}

# End try block and check for errors - returns 0 if error occurred (for catch)
# Usage: catch or catch { handler; }
catch() {
    local try_result=$?
    
    # Handle brace syntax: catch { handler; }
    if [[ "${1:-}" == "{" ]]; then
        shift
        if ((try_result != 0)); then
            _error_catch_brace "$@"
        fi
        return 0
    fi
    
    # Decrement try depth (ensure we don't go negative)
    if ((_ERROR_TRY_DEPTH > 0)); then
        ((_ERROR_TRY_DEPTH--))
        
        # Restore errexit state
        if [[ "${_ERROR_TRY_STATES[$_ERROR_TRY_DEPTH]:-false}" == "true" ]]; then
            set -e
        fi
    fi
    
    # If there was an error, populate error state if not already set
    if ((try_result != 0)); then
        if [[ -z "$ERROR_MESSAGE" ]]; then
            ERROR_MESSAGE="Command failed with exit code $try_result"
            ERROR_CODE=$try_result
        fi
        return 0  # Error occurred - catch block should run
    fi
    
    return 1  # No error - catch block should not run
}

# Internal: Handle try { commands; } syntax
_error_try_brace() {
    local cmd=""
    local brace_depth=1
    
    # Collect everything until matching }
    while (($# > 0)); do
        if [[ "$1" == "}" ]]; then
            ((brace_depth--))
            if ((brace_depth == 0)); then
                shift
                break
            fi
        elif [[ "$1" == "{" ]]; then
            ((brace_depth++))
        fi
        cmd+="$1 "
        shift
    done
    
    # Clear error state
    ERROR_MESSAGE=""
    ERROR_CODE=0
    
    # Execute and capture result
    ((_ERROR_TRY_DEPTH++))
    set +e
    eval "$cmd"
    local result=$?
    set -e
    ((_ERROR_TRY_DEPTH--))
    
    # Check for catch block
    if [[ "${1:-}" == "catch" ]]; then
        shift
        if ((result != 0)); then
            if [[ -z "$ERROR_MESSAGE" ]]; then
                ERROR_MESSAGE="Command failed with exit code $result"
                ERROR_CODE=$result
            fi
            if [[ "${1:-}" == "{" ]]; then
                shift
                _error_catch_brace "$@"
            fi
        fi
    fi
    
    return 0
}

# Internal: Handle catch { handler; } syntax
_error_catch_brace() {
    local cmd=""
    local brace_depth=1
    
    while (($# > 0)); do
        if [[ "$1" == "}" ]]; then
            ((brace_depth--))
            if ((brace_depth == 0)); then
                break
            fi
        elif [[ "$1" == "{" ]]; then
            ((brace_depth++))
        fi
        cmd+="$1 "
        shift
    done
    
    eval "$cmd"
}

# =============================================================================
# ERROR HANDLER SETUP
# =============================================================================

# Install a trap-based error handler for automatic error reporting
# Usage: error::trap_install
# Note: This overrides any existing ERR trap
error::trap_install() {
    trap '_error_trap_handler $? "${BASH_COMMAND}" ${LINENO} "${FUNCNAME[0]:-main}" "${BASH_SOURCE[0]:-unknown}"' ERR
}

# Remove the trap-based error handler
# Usage: error::trap_remove
error::trap_remove() {
    trap - ERR
}

# Internal trap handler
_error_trap_handler() {
    local exit_code="$1"
    local command="$2"
    local line="$3"
    local func="$4"
    local source="$5"
    
    # Don't handle if inside try block
    ((_ERROR_TRY_DEPTH > 0)) && return 0
    
    # Set error state
    ERROR_MESSAGE="Command failed: $command"
    ERROR_CODE=$exit_code
    ERROR_LINE=$line
    ERROR_FUNC=$func
    ERROR_SOURCE=$source
    
    printf '%sError:%s %s (exit code: %d)\n' "${CLR_RED:-}" "${CLR_RESET:-}" "$ERROR_MESSAGE" "$exit_code" >&2
    printf '  at %s (%s:%d)\n' "$func" "${source##*/}" "$line" >&2
    
    local ctx
    ctx=$(error::context_string)
    if [[ -n "$ctx" ]]; then
        printf '%s' "$ctx" >&2
    fi
}

# =============================================================================
# RETRY PATTERN
# =============================================================================

# Retry a command with exponential backoff
# Usage: error::retry [options] command args...
# Options:
#   -n, --max-attempts NUM  Maximum attempts (default: 3)
#   -d, --delay SECONDS     Initial delay between retries (default: 1)
#   -m, --max-delay SECONDS Maximum delay (default: 60)
#   -e, --exponential       Use exponential backoff (default: true)
# Example: error::retry -n 5 -d 2 curl -f https://example.com
error::retry() {
    local max_attempts=3
    local delay=1
    local max_delay=60
    local exponential=true
    
    # Parse options
    while [[ "$1" == -* ]]; do
        case "$1" in
            -n|--max-attempts)
                max_attempts="$2"
                shift 2
                ;;
            -d|--delay)
                delay="$2"
                shift 2
                ;;
            -m|--max-delay)
                max_delay="$2"
                shift 2
                ;;
            -e|--exponential)
                exponential=true
                shift
                ;;
            --linear)
                exponential=false
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                break
                ;;
        esac
    done
    
    local attempt=1
    local current_delay=$delay
    local result
    
    while ((attempt <= max_attempts)); do
        # Try the command
        if "$@"; then
            return 0
        fi
        result=$?
        
        # Last attempt failed
        if ((attempt >= max_attempts)); then
            ERROR_MESSAGE="Command failed after $max_attempts attempts"
            ERROR_CODE=$result
            return $result
        fi
        
        # Wait before retry
        sleep "$current_delay"
        
        # Calculate next delay
        if $exponential; then
            current_delay=$((current_delay * 2))
            ((current_delay > max_delay)) && current_delay=$max_delay
        fi
        
        ((attempt++))
    done
    
    return $result
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Check if we're currently inside a try block
# Usage: if error::in_try; then ...; fi
error::in_try() {
    ((_ERROR_TRY_DEPTH > 0))
}

# Get last error info as a formatted string
# Usage: info=$(error::last)
error::last() {
    if [[ -z "$ERROR_MESSAGE" ]]; then
        printf 'No error'
        return
    fi
    
    printf 'Error: %s\n' "$ERROR_MESSAGE"
    printf '  Code: %d\n' "$ERROR_CODE"
    printf '  Location: %s (%s:%d)\n' "$ERROR_FUNC" "${ERROR_SOURCE##*/}" "$ERROR_LINE"
}

# Clear error state
# Usage: error::clear
error::clear() {
    ERROR_MESSAGE=""
    ERROR_CODE=0
    ERROR_LINE=0
    ERROR_FUNC=""
    ERROR_SOURCE=""
    _ERROR_CONTEXT_STACK=()
}

# Check if there's an error set
# Usage: if error::has_error; then ...; fi
error::has_error() {
    [[ -n "$ERROR_MESSAGE" ]] || ((ERROR_CODE != 0))
}

# Die with error message (simple wrapper for scripts not using try/catch)
# Usage: error::die "message" [exit_code]
error::die() {
    local message="$1"
    local code="${2:-1}"
    
    printf '%sError:%s %s\n' "${CLR_RED:-}" "${CLR_RESET:-}" "$message" >&2
    exit "$code"
}

# Warn with message (non-fatal)
# Usage: error::warn "message"
error::warn() {
    local message="$1"
    
    printf '%sWarning:%s %s\n' "${CLR_YELLOW:-}" "${CLR_RESET:-}" "$message" >&2
}

# =============================================================================
# CLEANUP REGISTRATION
# =============================================================================

# Register cleanup handlers that run on script exit (even on error)
declare -ga _ERROR_CLEANUP_HANDLERS=()

# Register a cleanup function to run on exit
# Usage: error::on_exit "command" or error::on_exit function_name
# Example: error::on_exit "rm -f $tempfile"
error::on_exit() {
    _ERROR_CLEANUP_HANDLERS+=("$1")
    
    # Install trap if this is the first handler
    if ((${#_ERROR_CLEANUP_HANDLERS[@]} == 1)); then
        trap '_error_run_cleanup' EXIT
    fi
}

# Internal: Run all cleanup handlers in reverse order
_error_run_cleanup() {
    local i
    for ((i = ${#_ERROR_CLEANUP_HANDLERS[@]} - 1; i >= 0; i--)); do
        eval "${_ERROR_CLEANUP_HANDLERS[$i]}" || true
    done
}

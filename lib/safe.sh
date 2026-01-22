#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/safe.sh - Strict Mode Helpers and Gotcha Prevention
# =============================================================================
# Description: Safe execution patterns for AI-generated scripts
# Purpose: Prevent common AI coding assistant errors through strict mode,
#          safe sourcing, output capture, retry with backoff, and timeout
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_SAFE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_SAFE_LOADED=1

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Track original shell options for restore
declare -g _SAFE_ORIGINAL_OPTS=""
declare -g _SAFE_STRICT_ENABLED=false

# Track shellcheck warnings to suppress in linting
declare -ga _SAFE_SHELLCHECK_EXCLUDES=(
    SC2015  # A && B || C pattern (common idiom)
    SC2155  # Declare and assign separately
    SC2034  # Variable appears unused (often false positive)
)

# =============================================================================
# LOGGING HELPERS (minimal dependency)
# =============================================================================

_safe_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "$*"
    else
        printf '[%s] %s: %s\n' "$(date +%H:%M:%S)" "${level^^}" "$*" >&2
    fi
}

_safe_error() { _safe_log error "$@"; }
_safe_warn() { _safe_log warn "$@"; }
_safe_info() { _safe_log info "$@"; }
_safe_debug() { _safe_log debug "$@"; }

# =============================================================================
# STRICT MODE MANAGEMENT
# =============================================================================

# Enable strict mode with sensible defaults for AI-generated scripts
# Usage: enable_strict_mode
#
# Enables:
#   -e  Exit immediately on command failure
#   -u  Treat unset variables as errors
#   -o pipefail  Pipeline fails on first command failure
#   inherit_errexit  Subshells inherit -e (bash 4.4+)
#
# Example:
#   enable_strict_mode
#   # Now errors will cause immediate exit
#   undefined_var  # This will error out
enable_strict_mode() {
    # Save current options for potential restore
    _SAFE_ORIGINAL_OPTS="$-"

    # Core strict mode settings
    set -e          # Exit on error
    set -u          # Error on unset variables
    set -o pipefail # Pipeline returns rightmost non-zero

    # Enable inherit_errexit if available (bash 4.4+)
    # This ensures subshells also exit on error
    if shopt -q inherit_errexit 2>/dev/null; then
        shopt -s inherit_errexit
    fi

    _SAFE_STRICT_ENABLED=true
    _safe_debug "Strict mode enabled"
}

# Disable strict mode (restore previous settings)
# Usage: disable_strict_mode
#
# Restores shell options to state before enable_strict_mode was called
# Useful for sections that need to handle errors manually
#
# Example:
#   enable_strict_mode
#   # ... strict code ...
#   disable_strict_mode
#   # Now errors won't cause immediate exit
disable_strict_mode() {
    if [[ -n "$_SAFE_ORIGINAL_OPTS" ]]; then
        # Restore original options
        if [[ "$_SAFE_ORIGINAL_OPTS" != *e* ]]; then
            set +e
        fi
        if [[ "$_SAFE_ORIGINAL_OPTS" != *u* ]]; then
            set +u
        fi
        # Note: pipefail state is not captured in $-, check separately
        set +o pipefail 2>/dev/null || true

        # Disable inherit_errexit if we enabled it
        shopt -u inherit_errexit 2>/dev/null || true
    else
        # Fallback: just disable everything
        set +e
        set +u
        set +o pipefail 2>/dev/null || true
        shopt -u inherit_errexit 2>/dev/null || true
    fi

    _SAFE_STRICT_ENABLED=false
    _safe_debug "Strict mode disabled"
}

# Check if strict mode is currently enabled
# Usage: is_strict_mode && echo "strict"
# Returns: 0 if strict mode enabled, 1 if not
is_strict_mode() {
    $_SAFE_STRICT_ENABLED
}

# =============================================================================
# UNSAFE EXECUTION
# =============================================================================

# Run command with strict mode temporarily disabled
# Usage: unsafe_run "command that might fail"
#
# Executes the given command in a context where errors don't cause script exit
# Captures and returns the actual exit code of the command
#
# Example:
#   if unsafe_run "grep pattern missing-file.txt"; then
#       echo "Pattern found"
#   else
#       echo "Pattern not found or file missing"
#   fi
#
# Example with variable capture:
#   local result
#   if result=$(unsafe_run "some_command"); then
#       echo "Got: $result"
#   fi
unsafe_run() {
    local command="$1"
    local exit_code=0

    # Disable strict mode for this execution
    set +e
    set +u
    set +o pipefail 2>/dev/null || true

    # Execute the command
    eval "$command"
    exit_code=$?

    # Re-enable strict mode if it was on
    if $_SAFE_STRICT_ENABLED; then
        set -e
        set -u
        set -o pipefail
    fi

    return $exit_code
}

# Run command, capturing exit code without triggering errexit
# Usage: safe_exit_code "command"
# Returns: Exit code is stored in SAFE_EXIT_CODE variable
#
# Example:
#   safe_exit_code "grep pattern file.txt"
#   if [[ $SAFE_EXIT_CODE -eq 0 ]]; then
#       echo "Found"
#   fi
declare -g SAFE_EXIT_CODE=0

safe_exit_code() {
    local command="$1"

    # The || true pattern prevents errexit from triggering
    eval "$command" && SAFE_EXIT_CODE=0 || SAFE_EXIT_CODE=$?

    return 0  # Always return success to not trigger errexit
}

# =============================================================================
# SAFE SOURCING
# =============================================================================

# Safe source that checks file exists and is readable
# Usage: safe_source "file.sh" [required]
#
# Parameters:
#   file.sh  - Path to the file to source
#   required - If "true" (default), error on missing file
#              If "false", silently skip missing files
#
# Returns: 0 on success, 1 on failure (if required=false)
#
# Example:
#   safe_source "/etc/myapp/config.sh"          # Required (errors if missing)
#   safe_source "optional.sh" false             # Optional (silent if missing)
safe_source() {
    local file="$1"
    local required="${2:-true}"

    # Check for empty path
    if [[ -z "$file" ]]; then
        _safe_error "safe_source: Empty file path provided"
        return 1
    fi

    # Check file exists
    if [[ ! -f "$file" ]]; then
        if [[ "$required" == "true" ]]; then
            _safe_error "safe_source: File not found: $file"
            return 1
        else
            _safe_debug "safe_source: Optional file not found, skipping: $file"
            return 0
        fi
    fi

    # Check file is readable
    if [[ ! -r "$file" ]]; then
        _safe_error "safe_source: File not readable: $file"
        return 1
    fi

    # Source the file
    # shellcheck disable=SC1090
    source "$file"
}

# Source multiple files safely
# Usage: safe_source_all [required] file1.sh file2.sh ...
#
# Example:
#   safe_source_all true "$HOME/.bashrc" "$HOME/.bash_aliases"
safe_source_all() {
    local required="${1:-true}"
    shift

    for file in "$@"; do
        safe_source "$file" "$required" || return 1
    done
}

# Source file if it exists (convenience wrapper)
# Usage: source_if_exists "file.sh"
#
# Example:
#   source_if_exists "$HOME/.local_config"
source_if_exists() {
    safe_source "$1" false
}

# =============================================================================
# OUTPUT CAPTURE
# =============================================================================

# Run command and capture both stdout and stderr separately
# Usage: capture_both stdout_var stderr_var "command"
#
# Captures stdout and stderr into separate variables without mixing them
# Uses temporary files for reliable capture (pure bash alternative is complex)
#
# Parameters:
#   stdout_var - Name of variable to store stdout
#   stderr_var - Name of variable to store stderr
#   command    - Command to execute
#
# Returns: Exit code of the command
#
# Example:
#   capture_both out err "ls /nonexistent"
#   echo "stdout: $out"
#   echo "stderr: $err"
capture_both() {
    local -n stdout_ref="$1"
    local -n stderr_ref="$2"
    local command="$3"
    local exit_code=0

    # Create temp files for capture
    local stdout_file stderr_file
    stdout_file=$(mktemp) || {
        _safe_error "capture_both: Failed to create temp file"
        return 1
    }
    stderr_file=$(mktemp) || {
        rm -f "$stdout_file"
        _safe_error "capture_both: Failed to create temp file"
        return 1
    }

    # Execute command, capturing streams separately
    {
        eval "$command"
    } > "$stdout_file" 2> "$stderr_file"
    exit_code=$?

    # Read results into variables
    stdout_ref=$(cat "$stdout_file")
    stderr_ref=$(cat "$stderr_file")

    # Cleanup
    rm -f "$stdout_file" "$stderr_file"

    return $exit_code
}

# Capture stdout only, discard stderr
# Usage: result=$(capture_stdout "command")
#
# Example:
#   version=$(capture_stdout "python --version 2>&1")
capture_stdout() {
    local command="$1"
    eval "$command" 2>/dev/null
}

# Capture stderr only, discard stdout
# Usage: errors=$(capture_stderr "command")
#
# Example:
#   errors=$(capture_stderr "make build")
capture_stderr() {
    local command="$1"
    eval "$command" 2>&1 >/dev/null
}

# Capture combined stdout+stderr
# Usage: all_output=$(capture_all "command")
#
# Example:
#   log=$(capture_all "npm install")
capture_all() {
    local command="$1"
    eval "$command" 2>&1
}

# =============================================================================
# RETRY WITH BACKOFF
# =============================================================================

# Retry command with exponential backoff
# Usage: retry_backoff max_attempts "command" [initial_delay] [max_delay]
#
# Parameters:
#   max_attempts  - Maximum number of retry attempts (must be > 0)
#   command       - Command to execute
#   initial_delay - Initial delay in seconds (default: 1)
#   max_delay     - Maximum delay cap in seconds (default: 60)
#
# Returns: 0 on success, 1 if all attempts failed
#
# Example:
#   retry_backoff 5 "curl -sf http://api.example.com/health"
#   retry_backoff 3 "docker pull nginx" 2 30
retry_backoff() {
    local max_attempts="${1:-3}"
    local command="$2"
    local initial_delay="${3:-1}"
    local max_delay="${4:-60}"

    local attempt=1
    local delay="$initial_delay"
    local exit_code

    # Validate max_attempts
    if [[ ! "$max_attempts" =~ ^[0-9]+$ ]] || (( max_attempts < 1 )); then
        _safe_error "retry_backoff: max_attempts must be a positive integer"
        return 1
    fi

    while (( attempt <= max_attempts )); do
        _safe_debug "Attempt $attempt/$max_attempts: $command"

        # Execute with error capture
        set +e
        eval "$command"
        exit_code=$?
        set -e 2>/dev/null || true  # Only set if strict mode was on

        if [[ $exit_code -eq 0 ]]; then
            _safe_debug "Command succeeded on attempt $attempt"
            return 0
        fi

        if (( attempt < max_attempts )); then
            _safe_warn "Attempt $attempt failed (exit code $exit_code), retrying in ${delay}s..."
            sleep "$delay"

            # Calculate next delay with exponential backoff
            # delay = min(delay * 2, max_delay)
            delay=$((delay * 2))
            if (( delay > max_delay )); then
                delay="$max_delay"
            fi
        else
            _safe_error "All $max_attempts attempts failed"
        fi

        ((attempt++))
    done

    return 1
}

# Retry with jitter (adds randomness to prevent thundering herd)
# Usage: retry_backoff_jitter max_attempts "command" [initial_delay] [max_delay]
#
# Same as retry_backoff but adds random jitter (0-25% of delay)
# Useful for distributed systems to prevent synchronized retries
#
# Example:
#   retry_backoff_jitter 5 "curl -sf http://api.example.com/endpoint"
retry_backoff_jitter() {
    local max_attempts="${1:-3}"
    local command="$2"
    local initial_delay="${3:-1}"
    local max_delay="${4:-60}"

    local attempt=1
    local delay="$initial_delay"
    local exit_code

    while (( attempt <= max_attempts )); do
        _safe_debug "Attempt $attempt/$max_attempts: $command"

        set +e
        eval "$command"
        exit_code=$?
        set -e 2>/dev/null || true

        if [[ $exit_code -eq 0 ]]; then
            return 0
        fi

        if (( attempt < max_attempts )); then
            # Add jitter: 0-25% of current delay
            local jitter=$(( RANDOM % (delay / 4 + 1) ))
            local actual_delay=$((delay + jitter))

            _safe_warn "Attempt $attempt failed, retrying in ${actual_delay}s (${delay}s + ${jitter}s jitter)..."
            sleep "$actual_delay"

            delay=$((delay * 2))
            if (( delay > max_delay )); then
                delay="$max_delay"
            fi
        fi

        ((attempt++))
    done

    return 1
}

# Retry with custom callback on each failure
# Usage: retry_with_callback max_attempts "command" "callback_func"
#
# Callback receives: attempt_number max_attempts exit_code
#
# Example:
#   on_retry() { echo "Retry $1/$2 (error: $3)"; }
#   retry_with_callback 3 "flaky_command" on_retry
retry_with_callback() {
    local max_attempts="${1:-3}"
    local command="$2"
    local callback="${3:-:}"  # Default to no-op

    local attempt=1
    local delay=1
    local exit_code

    while (( attempt <= max_attempts )); do
        set +e
        eval "$command"
        exit_code=$?
        set -e 2>/dev/null || true

        if [[ $exit_code -eq 0 ]]; then
            return 0
        fi

        # Call the callback with attempt info
        $callback "$attempt" "$max_attempts" "$exit_code"

        if (( attempt < max_attempts )); then
            sleep "$delay"
            delay=$((delay * 2))
        fi

        ((attempt++))
    done

    return 1
}

# =============================================================================
# TIMEOUT EXECUTION
# =============================================================================

# Run command with timeout (pure bash implementation)
# Usage: run_with_timeout seconds "command"
#
# Executes command and kills it if it exceeds the specified timeout.
# Uses background process and wait -n for efficient implementation.
#
# Parameters:
#   seconds - Maximum time to wait (must be positive integer)
#   command - Command to execute
#
# Returns:
#   0   - Command completed successfully within timeout
#   124 - Command timed out (matches GNU timeout behavior)
#   *   - Command's actual exit code if it completed
#
# Example:
#   if run_with_timeout 5 "sleep 10"; then
#       echo "Completed"
#   elif [[ $? -eq 124 ]]; then
#       echo "Timed out"
#   fi
run_with_timeout() {
    local timeout="$1"
    local command="$2"

    # Validate timeout
    if [[ ! "$timeout" =~ ^[0-9]+$ ]] || (( timeout < 1 )); then
        _safe_error "run_with_timeout: timeout must be a positive integer"
        return 1
    fi

    local cmd_pid
    local watchdog_pid
    local exit_code

    # Start the command in background
    eval "$command" &
    cmd_pid=$!

    # Start watchdog timer in background
    {
        sleep "$timeout"
        # Check if command is still running
        if kill -0 "$cmd_pid" 2>/dev/null; then
            _safe_warn "Command timed out after ${timeout}s, killing PID $cmd_pid"
            kill -TERM "$cmd_pid" 2>/dev/null
            sleep 0.5
            kill -KILL "$cmd_pid" 2>/dev/null || true
        fi
    } &
    watchdog_pid=$!

    # Wait for command to finish
    wait "$cmd_pid" 2>/dev/null
    exit_code=$?

    # Kill watchdog if still running
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true

    # Check if we killed it (exit code 137 = SIGKILL, 143 = SIGTERM)
    if [[ $exit_code -eq 137 || $exit_code -eq 143 ]]; then
        return 124  # Standard timeout exit code
    fi

    return $exit_code
}

# Run with timeout, using GNU timeout if available (more reliable)
# Falls back to pure bash implementation if timeout not available
# Usage: timeout_cmd seconds "command"
#
# Example:
#   timeout_cmd 10 "curl -sf http://slow-api.example.com"
timeout_cmd() {
    local seconds="$1"
    local command="$2"

    if command -v timeout &>/dev/null; then
        # Use GNU timeout (more reliable for complex commands)
        timeout --signal=TERM --kill-after=5 "$seconds" bash -c "$command"
    else
        # Fallback to pure bash implementation
        run_with_timeout "$seconds" "$command"
    fi
}

# =============================================================================
# SCRIPT LINTING
# =============================================================================

# Check for common script issues using shellcheck
# Usage: lint_script "script.sh" [severity]
#
# Parameters:
#   script.sh - Path to script to lint
#   severity  - Minimum severity: error, warning, info, style (default: warning)
#
# Returns: 0 if no issues at specified severity, 1 if issues found
#
# Example:
#   if lint_script "my_script.sh" warning; then
#       echo "Script looks good!"
#   else
#       echo "Issues found, check output"
#   fi
lint_script() {
    local script="$1"
    local severity="${2:-warning}"

    # Check if script exists
    if [[ ! -f "$script" ]]; then
        _safe_error "lint_script: Script not found: $script"
        return 1
    fi

    # Check if shellcheck is available
    if ! command -v shellcheck &>/dev/null; then
        _safe_warn "lint_script: shellcheck not installed, skipping lint"
        _safe_warn "  Install with: apt install shellcheck / brew install shellcheck"
        return 0
    fi

    # Build exclude list
    local excludes=""
    for code in "${_SAFE_SHELLCHECK_EXCLUDES[@]}"; do
        excludes="${excludes:+$excludes,}$code"
    done

    # Run shellcheck
    local shellcheck_args=(-s bash -S "$severity")
    [[ -n "$excludes" ]] && shellcheck_args+=(-e "$excludes")

    _safe_info "Linting: $script"
    if shellcheck "${shellcheck_args[@]}" "$script"; then
        _safe_info "No issues found"
        return 0
    else
        _safe_warn "Issues found in $script"
        return 1
    fi
}

# Quick syntax check only (faster than full lint)
# Usage: check_syntax "script.sh"
#
# Example:
#   check_syntax "script.sh" || exit 1
check_syntax() {
    local script="$1"

    if [[ ! -f "$script" ]]; then
        _safe_error "check_syntax: Script not found: $script"
        return 1
    fi

    if bash -n "$script" 2>&1; then
        _safe_debug "Syntax OK: $script"
        return 0
    else
        _safe_error "Syntax error in: $script"
        return 1
    fi
}

# Lint multiple scripts
# Usage: lint_scripts "dir/" [pattern]
#
# Example:
#   lint_scripts "./scripts/" "*.sh"
lint_scripts() {
    local dir="${1:-.}"
    local pattern="${2:-*.sh}"
    local failed=0

    while IFS= read -r -d '' script; do
        lint_script "$script" warning || ((failed++))
    done < <(find "$dir" -name "$pattern" -type f -print0 2>/dev/null)

    if (( failed > 0 )); then
        _safe_warn "$failed script(s) have issues"
        return 1
    fi

    return 0
}

# =============================================================================
# ERROR CONTEXT
# =============================================================================

# Enable detailed error context for debugging
# Usage: enable_error_context
#
# When enabled, errors will print stack trace and command context
enable_error_context() {
    trap '_safe_error_handler $? $LINENO "$BASH_COMMAND"' ERR
    _safe_debug "Error context enabled"
}

# Internal error handler for context
_safe_error_handler() {
    local exit_code="$1"
    local line_number="$2"
    local command="$3"

    _safe_error "Command failed with exit code $exit_code"
    _safe_error "  Command: $command"
    _safe_error "  Line: $line_number"
    _safe_error "  Script: ${BASH_SOURCE[1]:-unknown}"

    # Print stack trace
    _safe_print_stack 2
}

# Print stack trace
_safe_print_stack() {
    local start="${1:-0}"
    local i

    _safe_error "Stack trace:"
    for ((i=start; i < ${#FUNCNAME[@]}; i++)); do
        _safe_error "  ${FUNCNAME[$i]}() at ${BASH_SOURCE[$i]:-unknown}:${BASH_LINENO[$((i-1))]}"
    done
}

# Disable error context
# Usage: disable_error_context
disable_error_context() {
    trap - ERR
    _safe_debug "Error context disabled"
}

# =============================================================================
# GOTCHA PREVENTION HELPERS
# =============================================================================

# Safely get variable with default (prevents unbound variable errors)
# Usage: default "varname" "default_value"
#
# Example:
#   value=$(default "MY_VAR" "fallback")
default() {
    local varname="$1"
    local default_value="$2"
    printf '%s' "${!varname:-$default_value}"
}

# Assert variable is set and non-empty
# Usage: require_var "varname" ["error message"]
#
# Example:
#   require_var "API_KEY" "API_KEY environment variable is required"
require_var() {
    local varname="$1"
    local message="${2:-Required variable '$varname' is not set or empty}"

    if [[ -z "${!varname:-}" ]]; then
        _safe_error "$message"
        return 1
    fi
}

# Safe array access with bounds checking
# Usage: array_get arr_name index [default]
#
# Example:
#   arr=(a b c)
#   value=$(array_get arr 5 "not found")
array_get() {
    local -n arr_ref="$1"
    local index="$2"
    local default_val="${3:-}"

    if (( index >= 0 && index < ${#arr_ref[@]} )); then
        printf '%s' "${arr_ref[$index]}"
    else
        printf '%s' "$default_val"
    fi
}

# Safe arithmetic that handles empty/non-numeric values
# Usage: safe_math "expression" [default]
#
# Example:
#   result=$(safe_math "$a + $b" 0)
safe_math() {
    local expr="$1"
    local default="${2:-0}"

    # Replace empty values with 0
    expr="${expr:-0}"

    # Try to evaluate, return default on failure
    local result
    if result=$(( expr )) 2>/dev/null; then
        printf '%d' "$result"
    else
        printf '%d' "$default"
    fi
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_SAFE_EXPORTS=(
    # Strict mode
    enable_strict_mode
    disable_strict_mode
    is_strict_mode

    # Unsafe execution
    unsafe_run
    safe_exit_code

    # Safe sourcing
    safe_source
    safe_source_all
    source_if_exists

    # Output capture
    capture_both
    capture_stdout
    capture_stderr
    capture_all

    # Retry with backoff
    retry_backoff
    retry_backoff_jitter
    retry_with_callback

    # Timeout
    run_with_timeout
    timeout_cmd

    # Linting
    lint_script
    check_syntax
    lint_scripts

    # Error context
    enable_error_context
    disable_error_context

    # Gotcha prevention
    default
    require_var
    array_get
    safe_math
)

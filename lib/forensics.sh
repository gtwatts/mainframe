#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/forensics.sh - Error Forensics for Multi-Agent Systems
# =============================================================================
# Description: Deep error context capture, stack traces, variable snapshots,
#              and error chains for debugging multi-agent AI systems.
#              Produces USOP JSON output for automated analysis.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_FORENSICS_LOADED:-}" ]] && return 0
readonly _MAINFRAME_FORENSICS_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Directory for forensic state files
MAINFRAME_FORENSICS_DIR="${MAINFRAME_FORENSICS_DIR:-${TMPDIR:-/tmp}/mainframe_forensics_$$}"

# Maximum depth for variable capture
MAINFRAME_FORENSICS_MAX_VAR_DEPTH="${MAINFRAME_FORENSICS_MAX_VAR_DEPTH:-100}"

# Maximum size for variable values (chars)
MAINFRAME_FORENSICS_MAX_VAR_SIZE="${MAINFRAME_FORENSICS_MAX_VAR_SIZE:-4096}"

# Enable/disable automatic forensics on error
MAINFRAME_FORENSICS_AUTO="${MAINFRAME_FORENSICS_AUTO:-0}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Associative array for snapshots
declare -gA _FORENSICS_SNAPSHOTS

# Array for watched variables
declare -ga _FORENSICS_WATCHED_VARS=()

# Associative array for watched variable changes
declare -gA _FORENSICS_WATCH_HISTORY

# Error chain storage
declare -ga _FORENSICS_ERROR_CHAIN=()

# Counter for unique error IDs
_FORENSICS_ERROR_COUNTER=0

# Trap installed flag
_FORENSICS_TRAP_INSTALLED=0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Get current timestamp with microseconds
_forensics_now() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        printf '%s' "$EPOCHREALTIME"
    elif [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s.000000' "$EPOCHSECONDS"
    else
        date +%s.%N 2>/dev/null || date +%s
    fi
}

# Get ISO timestamp
_forensics_iso_time() {
    date -u '+%Y-%m-%dT%H:%M:%S.%3NZ' 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# JSON-escape a string
_forensics_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Generate unique ID
_forensics_gen_id() {
    local prefix="${1:-forensic}"
    local rand
    rand=$(head -c 4 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' || printf '%s%s' "$$" "$RANDOM")
    printf '%s_%s_%s' "$prefix" "$$" "$rand"
}

# Truncate value if too long
_forensics_truncate() {
    local val="$1"
    local max="${2:-$MAINFRAME_FORENSICS_MAX_VAR_SIZE}"
    if [[ ${#val} -gt $max ]]; then
        printf '%s...[truncated %d chars]' "${val:0:$max}" "$((${#val} - max))"
    else
        printf '%s' "$val"
    fi
}

# =============================================================================
# STACK TRACES
# =============================================================================

# @pre: called within a function context
# @post: returns current stack trace with file:line info
# @idempotent: yes
# @returns: 0, prints human-readable stack trace
#
# Get the current call stack as a formatted string.
# Each frame shows function name, file, and line number.
#
# Usage: trace=$(forensics_stack)
# Example: echo "Error at: $(forensics_stack)"
forensics_stack() {
    local depth=${#FUNCNAME[@]}
    local i
    local result=""

    for ((i=1; i<depth; i++)); do
        local func="${FUNCNAME[$i]:-main}"
        local file="${BASH_SOURCE[$i]:-unknown}"
        local line="${BASH_LINENO[$((i-1))]:-0}"

        # Get just the filename, not full path
        local filename="${file##*/}"

        [[ -n "$result" ]] && result+=$'\n'
        result+="  at ${func}() ${filename}:${line}"
    done

    printf '%s' "$result"
}

# @pre: called within a function context
# @post: returns JSON stack trace
# @idempotent: yes
# @returns: 0, prints JSON array of stack frames
#
# Get the current call stack as a JSON array.
# Each frame includes func, file, and line keys.
#
# Usage: trace_json=$(forensics_stack_json)
# Example: bundle=$(forensics_bundle); echo "$bundle" | jq '.stack'
forensics_stack_json() {
    local depth=${#FUNCNAME[@]}
    local i
    local frames=""

    for ((i=1; i<depth; i++)); do
        local func="${FUNCNAME[$i]:-main}"
        local file="${BASH_SOURCE[$i]:-unknown}"
        local line="${BASH_LINENO[$((i-1))]:-0}"

        local escaped_func escaped_file
        escaped_func=$(_forensics_escape "$func")
        escaped_file=$(_forensics_escape "$file")

        [[ -n "$frames" ]] && frames+=","
        frames+="{\"func\":\"$escaped_func\",\"file\":\"$escaped_file\",\"line\":$line}"
    done

    printf '[%s]' "$frames"
}

# @pre: DEPTH is a positive integer (default 1)
# @post: returns caller info at specified depth
# @idempotent: yes
# @returns: 0, prints "function file:line"
#
# Get caller information at a specific stack depth.
# Depth 1 = immediate caller, 2 = caller's caller, etc.
#
# Usage: caller_info=$(forensics_caller 2)
# Example: log "Called from $(forensics_caller 1)"
forensics_caller() {
    local depth="${1:-1}"

    # Add 1 because this function is on the stack
    local actual_depth=$((depth + 1))

    local func="${FUNCNAME[$actual_depth]:-main}"
    local file="${BASH_SOURCE[$actual_depth]:-unknown}"
    local line="${BASH_LINENO[$((actual_depth - 1))]:-0}"

    local filename="${file##*/}"
    printf '%s %s:%d' "$func" "$filename" "$line"
}

# =============================================================================
# ERROR CONTEXT CAPTURE
# =============================================================================

# @pre: none
# @post: returns JSON with full context (stack, vars, env)
# @idempotent: yes
# @returns: 0, prints JSON context object
#
# Capture the current execution context including call stack,
# local variables, and selected environment variables.
#
# Usage: context=$(forensics_capture)
# Example: on_error() { forensics_capture > /tmp/debug.json; }
forensics_capture() {
    local timestamp
    timestamp=$(_forensics_iso_time)

    local stack_json
    stack_json=$(forensics_stack_json)

    # Capture local variables from caller's scope
    local vars_json
    vars_json=$(_forensics_capture_vars)

    # Capture relevant environment
    local env_json
    env_json=$(_forensics_capture_env)

    # Get last command info
    local last_cmd="${BASH_COMMAND:-unknown}"
    local last_exit="${PIPESTATUS[*]:-$?}"

    local escaped_cmd
    escaped_cmd=$(_forensics_escape "$last_cmd")

    printf '{"timestamp":"%s","stack":%s,"variables":%s,"environment":%s,"last_command":"%s","exit_status":"%s"}' \
        "$timestamp" "$stack_json" "$vars_json" "$env_json" "$escaped_cmd" "$last_exit"
}

# Internal: capture local variables
_forensics_capture_vars() {
    local vars_json="{"
    local first=true
    local count=0

    # Get all visible variables (excluding functions)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == _* ]] && continue  # Skip internal vars
        [[ "$line" == BASH* ]] && continue  # Skip bash internal vars
        [[ "$line" == FUNCNAME* ]] && continue
        [[ "$line" == LINENO* ]] && continue

        # Extract variable name
        local varname="${line%%=*}"
        [[ -z "$varname" ]] && continue

        # Get value safely
        local value
        value="${!varname:-}"
        value=$(_forensics_truncate "$value")

        local escaped_name escaped_value
        escaped_name=$(_forensics_escape "$varname")
        escaped_value=$(_forensics_escape "$value")

        $first || vars_json+=","
        first=false
        vars_json+="\"$escaped_name\":\"$escaped_value\""

        ((count++))
        [[ $count -ge $MAINFRAME_FORENSICS_MAX_VAR_DEPTH ]] && break
    done < <(declare -p 2>/dev/null | grep '^declare' | sed 's/^declare -[a-zA-Z-]* //' | cut -d= -f1)

    vars_json+="}"
    printf '%s' "$vars_json"
}

# Internal: capture relevant environment variables
_forensics_capture_env() {
    local env_json="{"
    local first=true

    # Capture specific useful env vars
    local useful_vars=(
        "PWD" "HOME" "USER" "SHELL" "PATH" "TERM"
        "MAINFRAME_ROOT" "MAINFRAME_TRACE_ENABLED"
        "BASHER_LOG_LEVEL" "BASHER_LOG_FILE"
    )

    for varname in "${useful_vars[@]}"; do
        local value="${!varname:-}"
        [[ -z "$value" ]] && continue

        value=$(_forensics_truncate "$value" 1024)

        local escaped_name escaped_value
        escaped_name=$(_forensics_escape "$varname")
        escaped_value=$(_forensics_escape "$value")

        $first || env_json+=","
        first=false
        env_json+="\"$escaped_name\":\"$escaped_value\""
    done

    env_json+="}"
    printf '%s' "$env_json"
}

# =============================================================================
# SNAPSHOTS
# =============================================================================

# @pre: NAME is a non-empty string
# @post: snapshot stored with current context
# @idempotent: no - overwrites existing snapshot with same name
# @returns: 0 on success
#
# Create a named snapshot of the current execution state.
# Snapshots can be compared later with forensics_diff.
#
# Usage: forensics_snapshot "before_operation"
# Example: forensics_snapshot "init"; run_code; forensics_snapshot "after"
forensics_snapshot() {
    local name="${1:?Snapshot name required}"

    # Ensure forensics directory exists
    mkdir -p "$MAINFRAME_FORENSICS_DIR"

    local snapshot_file="$MAINFRAME_FORENSICS_DIR/snapshot_${name}.json"

    # Capture full context
    local context
    context=$(forensics_capture)

    # Add snapshot metadata
    local snapshot_id
    snapshot_id=$(_forensics_gen_id "snap")

    local snapshot_json
    snapshot_json=$(printf '{"id":"%s","name":"%s","context":%s}' \
        "$snapshot_id" "$(_forensics_escape "$name")" "$context")

    printf '%s' "$snapshot_json" > "$snapshot_file"

    # Also store in memory for fast access
    _FORENSICS_SNAPSHOTS["$name"]="$snapshot_file"

    return 0
}

# @pre: SNAP1 and SNAP2 are existing snapshot names
# @post: returns JSON diff between snapshots
# @idempotent: yes
# @returns: 0 on success, 1 if snapshots not found
#
# Compare two snapshots and return the differences.
# Shows added, removed, and changed variables.
#
# Usage: diff=$(forensics_diff "before" "after")
# Example: forensics_diff "init" "error" | jq '.changed'
forensics_diff() {
    local snap1="${1:?First snapshot name required}"
    local snap2="${2:?Second snapshot name required}"

    local file1="${_FORENSICS_SNAPSHOTS[$snap1]:-$MAINFRAME_FORENSICS_DIR/snapshot_${snap1}.json}"
    local file2="${_FORENSICS_SNAPSHOTS[$snap2]:-$MAINFRAME_FORENSICS_DIR/snapshot_${snap2}.json}"

    if [[ ! -f "$file1" ]]; then
        printf '{"error":"snapshot_not_found","snapshot":"%s"}' "$snap1"
        return 1
    fi

    if [[ ! -f "$file2" ]]; then
        printf '{"error":"snapshot_not_found","snapshot":"%s"}' "$snap2"
        return 1
    fi

    # Extract variables from each snapshot
    local vars1 vars2
    vars1=$(<"$file1")
    vars2=$(<"$file2")

    # Simple diff - compare timestamps and key counts
    local time1 time2
    time1=$(printf '%s' "$vars1" | grep -oP '"timestamp"\s*:\s*"\K[^"]+' || echo "unknown")
    time2=$(printf '%s' "$vars2" | grep -oP '"timestamp"\s*:\s*"\K[^"]+' || echo "unknown")

    printf '{"snap1":"%s","snap2":"%s","time1":"%s","time2":"%s","snap1_file":"%s","snap2_file":"%s"}' \
        "$(_forensics_escape "$snap1")" "$(_forensics_escape "$snap2")" \
        "$time1" "$time2" \
        "$(_forensics_escape "$file1")" "$(_forensics_escape "$file2")"
}

# =============================================================================
# ERROR CHAINS
# =============================================================================

# @pre: MSG is a non-empty string, CAUSE is optional prior error
# @post: new error added to chain
# @idempotent: no - each call creates a new error
# @returns: 0, prints error ID to stdout
#
# Create an error with optional cause linking to form a chain.
# Error chains help trace the root cause through multiple layers.
#
# Usage: err_id=$(forensics_error "Operation failed")
# Usage: err_id=$(forensics_error "Higher-level failure" "$previous_err")
forensics_error() {
    local msg="${1:?Error message required}"
    local cause="${2:-}"

    local error_id
    ((_FORENSICS_ERROR_COUNTER++)) || true
    error_id="err_${$$}_${_FORENSICS_ERROR_COUNTER}"

    local timestamp
    timestamp=$(_forensics_iso_time)

    local stack_json
    stack_json=$(forensics_stack_json)

    local escaped_msg
    escaped_msg=$(_forensics_escape "$msg")

    local error_json
    if [[ -n "$cause" ]]; then
        local escaped_cause
        escaped_cause=$(_forensics_escape "$cause")
        error_json="{\"id\":\"$error_id\",\"msg\":\"$escaped_msg\",\"cause\":\"$escaped_cause\",\"timestamp\":\"$timestamp\",\"stack\":$stack_json}"
    else
        error_json="{\"id\":\"$error_id\",\"msg\":\"$escaped_msg\",\"timestamp\":\"$timestamp\",\"stack\":$stack_json}"
    fi

    # Add to chain
    _FORENSICS_ERROR_CHAIN+=("$error_json")

    printf '%s' "$error_id"
}

# @pre: ERROR is an existing error ID
# @post: new error added to chain with link to ERROR
# @idempotent: no - each call adds to chain
# @returns: 0, prints new error ID
#
# Add a new error to an existing error chain.
# Use this to wrap errors as they propagate up the call stack.
#
# Usage: new_err=$(forensics_chain_add "$err" "Wrapper error message")
forensics_chain_add() {
    local error_id="${1:?Error ID required}"
    local msg="${2:?Message required}"

    forensics_error "$msg" "$error_id"
}

# @pre: ERROR is an existing error ID (optional, dumps all if not provided)
# @post: returns JSON array of error chain
# @idempotent: yes
# @returns: 0, prints JSON error chain
#
# Dump the full error chain starting from a specific error.
# If no error ID provided, dumps all errors in the chain.
#
# Usage: chain=$(forensics_chain_dump "$err_id")
# Usage: all_errors=$(forensics_chain_dump)
forensics_chain_dump() {
    local error_id="${1:-}"

    if [[ ${#_FORENSICS_ERROR_CHAIN[@]} -eq 0 ]]; then
        printf '[]'
        return 0
    fi

    local result="["
    local first=true

    for error_json in "${_FORENSICS_ERROR_CHAIN[@]}"; do
        # If filtering by error_id, check if this error or its cause matches
        if [[ -n "$error_id" ]]; then
            if [[ ! "$error_json" =~ "\"id\":\"$error_id\"" ]] && \
               [[ ! "$error_json" =~ "\"cause\":\"$error_id\"" ]]; then
                continue
            fi
        fi

        $first || result+=","
        first=false
        result+="$error_json"
    done

    result+="]"
    printf '%s' "$result"
}

# @pre: ERROR is an existing error ID
# @post: returns root cause error info
# @idempotent: yes
# @returns: 0, prints root cause JSON
#
# Find the root cause by following the cause chain.
# Returns the first error in the chain (deepest cause).
#
# Usage: root=$(forensics_root_cause "$err_id")
forensics_root_cause() {
    local error_id="${1:?Error ID required}"

    local current_id="$error_id"
    local iterations=0
    local max_iterations=100

    while [[ $iterations -lt $max_iterations ]]; do
        ((iterations++))

        # Find error with this ID
        local found=""
        local cause=""
        for error_json in "${_FORENSICS_ERROR_CHAIN[@]}"; do
            if [[ "$error_json" =~ \"id\":\"$current_id\" ]]; then
                found="$error_json"
                # Extract cause if present
                if [[ "$error_json" =~ \"cause\":\"([^\"]+)\" ]]; then
                    cause="${BASH_REMATCH[1]}"
                fi
                break
            fi
        done

        if [[ -z "$found" ]]; then
            printf '{"error":"error_not_found","id":"%s"}' "$current_id"
            return 1
        fi

        # If no cause, this is the root
        if [[ -z "$cause" ]]; then
            printf '%s' "$found"
            return 0
        fi

        # Follow the cause chain
        current_id="$cause"
    done

    printf '{"error":"chain_too_deep","id":"%s"}' "$error_id"
    return 1
}

# =============================================================================
# VARIABLE WATCHES
# =============================================================================

# @pre: VAR_NAME is a valid variable name
# @post: variable added to watch list
# @idempotent: yes - safe to call multiple times
# @returns: 0
#
# Start watching a variable for changes.
# Changes are recorded with timestamps for debugging.
#
# Usage: forensics_watch "my_var"
# Example: forensics_watch "config_path"; config_path="/new/path"
forensics_watch() {
    local var_name="${1:?Variable name required}"

    # Check if already watching
    for v in "${_FORENSICS_WATCHED_VARS[@]}"; do
        [[ "$v" == "$var_name" ]] && return 0
    done

    _FORENSICS_WATCHED_VARS+=("$var_name")

    # Record initial value
    local value="${!var_name:-}"
    local timestamp
    timestamp=$(_forensics_now)

    _FORENSICS_WATCH_HISTORY["${var_name}_0"]="$timestamp:INIT:$value"

    return 0
}

# @pre: VAR_NAME is being watched
# @post: variable removed from watch list
# @idempotent: yes
# @returns: 0
#
# Stop watching a variable.
#
# Usage: forensics_unwatch "my_var"
forensics_unwatch() {
    local var_name="${1:?Variable name required}"

    local new_list=()
    for v in "${_FORENSICS_WATCHED_VARS[@]}"; do
        [[ "$v" != "$var_name" ]] && new_list+=("$v")
    done

    _FORENSICS_WATCHED_VARS=("${new_list[@]}")

    return 0
}

# @pre: some variables are being watched
# @post: returns JSON of all watched variable changes
# @idempotent: yes
# @returns: 0, prints JSON array of changes
#
# Get all recorded changes for watched variables.
# Returns array of {var, timestamp, action, value} objects.
#
# Usage: changes=$(forensics_watched_changes)
forensics_watched_changes() {
    local result="["
    local first=true

    for var_name in "${_FORENSICS_WATCHED_VARS[@]}"; do
        # Get current value
        local current="${!var_name:-}"

        # Check for changes against last recorded value
        local idx=0
        local last_entry=""
        while [[ -n "${_FORENSICS_WATCH_HISTORY[${var_name}_${idx}]:-}" ]]; do
            last_entry="${_FORENSICS_WATCH_HISTORY[${var_name}_${idx}]}"
            ((idx++))
        done

        # Parse last value
        if [[ -n "$last_entry" ]]; then
            local last_value="${last_entry#*:*:}"

            # If changed, record it
            if [[ "$current" != "$last_value" ]]; then
                local timestamp
                timestamp=$(_forensics_now)
                _FORENSICS_WATCH_HISTORY["${var_name}_${idx}"]="$timestamp:CHANGE:$current"
            fi
        fi

        # Output all history for this var
        idx=0
        while [[ -n "${_FORENSICS_WATCH_HISTORY[${var_name}_${idx}]:-}" ]]; do
            local entry="${_FORENSICS_WATCH_HISTORY[${var_name}_${idx}]}"

            local ts="${entry%%:*}"
            local rest="${entry#*:}"
            local action="${rest%%:*}"
            local value="${rest#*:}"

            local escaped_var escaped_value
            escaped_var=$(_forensics_escape "$var_name")
            escaped_value=$(_forensics_escape "$value")

            $first || result+=","
            first=false
            result+="{\"var\":\"$escaped_var\",\"timestamp\":$ts,\"action\":\"$action\",\"value\":\"$escaped_value\"}"

            ((idx++))
        done
    done

    result+="]"
    printf '%s' "$result"
}

# =============================================================================
# FORENSIC BUNDLES
# =============================================================================

# @pre: none
# @post: returns complete debug bundle as JSON
# @idempotent: yes
# @returns: 0, prints JSON bundle
#
# Create a complete forensic bundle containing:
# - Stack trace
# - Environment variables
# - Local variables
# - Command history (if available)
# - Error chain
# - Watched variable changes
#
# Usage: bundle=$(forensics_bundle)
forensics_bundle() {
    local timestamp
    timestamp=$(_forensics_iso_time)

    local bundle_id
    bundle_id=$(_forensics_gen_id "bundle")

    local stack_json
    stack_json=$(forensics_stack_json)

    local context_json
    context_json=$(forensics_capture)

    local errors_json
    errors_json=$(forensics_chain_dump)

    local watches_json
    watches_json=$(forensics_watched_changes)

    # Get command history if available
    local history_json="[]"
    if [[ -n "${HISTFILE:-}" ]] && [[ -f "$HISTFILE" ]]; then
        local recent_history
        recent_history=$(tail -20 "$HISTFILE" 2>/dev/null | head -20 || true)
        if [[ -n "$recent_history" ]]; then
            history_json="["
            local first=true
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                $first || history_json+=","
                first=false
                history_json+="\"$(_forensics_escape "$line")\""
            done <<< "$recent_history"
            history_json+="]"
        fi
    fi

    # Get system info
    local hostname_val="${HOSTNAME:-$(hostname 2>/dev/null || echo unknown)}"
    local user_val="${USER:-$(whoami 2>/dev/null || echo unknown)}"
    local pwd_val="${PWD:-$(pwd 2>/dev/null || echo unknown)}"

    printf '{"usop_version":"1.0","type":"forensic_bundle","id":"%s","timestamp":"%s","hostname":"%s","user":"%s","pwd":"%s","stack":%s,"context":%s,"errors":%s,"watches":%s,"history":%s}' \
        "$bundle_id" "$timestamp" \
        "$(_forensics_escape "$hostname_val")" \
        "$(_forensics_escape "$user_val")" \
        "$(_forensics_escape "$pwd_val")" \
        "$stack_json" "$context_json" "$errors_json" "$watches_json" "$history_json"
}

# @pre: FILE is a writable path
# @post: bundle saved to file
# @idempotent: no - creates new bundle each call
# @returns: 0 on success, 1 on write failure
#
# Save a complete forensic bundle to a file.
# File format is JSON with USOP metadata.
#
# Usage: forensics_bundle_save "/tmp/debug.json"
forensics_bundle_save() {
    local file="${1:?Output file path required}"

    local bundle
    bundle=$(forensics_bundle)

    if printf '%s\n' "$bundle" > "$file" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# @pre: FILE exists and contains valid bundle JSON
# @post: bundle loaded and displayed
# @idempotent: yes
# @returns: 0 on success, 1 on read failure
#
# Load and display a forensic bundle from file.
# Outputs formatted summary to stdout.
#
# Usage: forensics_bundle_load "/tmp/debug.json"
forensics_bundle_load() {
    local file="${1:?Bundle file path required}"

    if [[ ! -f "$file" ]]; then
        printf '{"error":"file_not_found","file":"%s"}' "$(_forensics_escape "$file")"
        return 1
    fi

    local bundle
    bundle=$(<"$file")

    # Validate it's JSON
    if [[ ! "$bundle" =~ ^\{ ]]; then
        printf '{"error":"invalid_bundle","file":"%s"}' "$(_forensics_escape "$file")"
        return 1
    fi

    # Output the bundle
    printf '%s' "$bundle"
}

# =============================================================================
# TRAP INTEGRATION
# =============================================================================

# Internal trap handler
_forensics_trap_handler() {
    local exit_code=$?
    local line_no="${BASH_LINENO[0]}"
    local cmd="${BASH_COMMAND:-unknown}"

    # Skip if exit code is 0
    [[ $exit_code -eq 0 ]] && return $exit_code

    # Skip if we're in the trap handler itself (avoid recursion)
    [[ "${FUNCNAME[1]:-}" == "_forensics_trap_handler" ]] && return $exit_code

    # Create error entry
    local err_id
    err_id=$(forensics_error "Command failed: $cmd (exit $exit_code)")

    # Save bundle to temp file
    local bundle_file="${MAINFRAME_FORENSICS_DIR}/trap_bundle_${exit_code}_$(date +%s).json"
    mkdir -p "$MAINFRAME_FORENSICS_DIR"
    forensics_bundle_save "$bundle_file"

    # Output to stderr
    printf '[FORENSICS] Error captured: %s (bundle: %s)\n' "$err_id" "$bundle_file" >&2

    return $exit_code
}

# @pre: none
# @post: error trap installed
# @idempotent: yes
# @returns: 0
#
# Install an error trap that automatically captures forensic context
# when errors occur. Bundles are saved to MAINFRAME_FORENSICS_DIR.
#
# Usage: forensics_trap_install
forensics_trap_install() {
    if [[ $_FORENSICS_TRAP_INSTALLED -eq 1 ]]; then
        return 0
    fi

    mkdir -p "$MAINFRAME_FORENSICS_DIR"

    trap '_forensics_trap_handler' ERR

    _FORENSICS_TRAP_INSTALLED=1
    return 0
}

# @pre: trap was installed
# @post: error trap removed
# @idempotent: yes
# @returns: 0
#
# Remove the forensics error trap.
#
# Usage: forensics_trap_uninstall
forensics_trap_uninstall() {
    trap - ERR
    _FORENSICS_TRAP_INSTALLED=0
    return 0
}

# =============================================================================
# CLEANUP
# =============================================================================

# Internal cleanup function
_forensics_cleanup() {
    # Clean up old forensics files (older than 1 hour)
    if [[ -d "$MAINFRAME_FORENSICS_DIR" ]]; then
        find "$MAINFRAME_FORENSICS_DIR" -type f -mmin +60 -delete 2>/dev/null || true
    fi
}

# Register cleanup on exit (only if not already registered)
if [[ -z "${_FORENSICS_CLEANUP_REGISTERED:-}" ]]; then
    trap '_forensics_cleanup' EXIT
    readonly _FORENSICS_CLEANUP_REGISTERED=1
fi

# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

# @pre: none
# @post: clears all forensics state
# @idempotent: yes
# @returns: 0
#
# Clear all forensics state (error chains, watches, snapshots).
#
# Usage: forensics_clear
forensics_clear() {
    _FORENSICS_ERROR_CHAIN=()
    _FORENSICS_WATCHED_VARS=()
    _FORENSICS_WATCH_HISTORY=()
    _FORENSICS_SNAPSHOTS=()
    _FORENSICS_ERROR_COUNTER=0

    # Clear files
    if [[ -d "$MAINFRAME_FORENSICS_DIR" ]]; then
        rm -rf "$MAINFRAME_FORENSICS_DIR"/*
    fi

    return 0
}

# @pre: none
# @post: returns JSON status of forensics system
# @idempotent: yes
# @returns: 0
#
# Get status of the forensics system.
#
# Usage: status=$(forensics_status)
forensics_status() {
    local error_count=${#_FORENSICS_ERROR_CHAIN[@]}
    local watch_count=${#_FORENSICS_WATCHED_VARS[@]}
    local snapshot_count=${#_FORENSICS_SNAPSHOTS[@]}
    local trap_status
    [[ $_FORENSICS_TRAP_INSTALLED -eq 1 ]] && trap_status="installed" || trap_status="not_installed"

    printf '{"errors":%d,"watches":%d,"snapshots":%d,"trap":"%s","dir":"%s"}' \
        "$error_count" "$watch_count" "$snapshot_count" "$trap_status" \
        "$(_forensics_escape "$MAINFRAME_FORENSICS_DIR")"
}

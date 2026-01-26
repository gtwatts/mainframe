#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/trace.sh - Savant-Level Debugging Framework
# =============================================================================
# Description: Advanced function tracing, variable watching, high-precision
#              timing, and session replay. Produces JSON output for AI agent
#              debugging and analysis. Supports DEBUG trap-based variable
#              watching and function interception.
# Version: 1.0.0
# Requires: Bash 4.0+ (enhanced features on 5.0+)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_TRACE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_TRACE_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Enable/disable tracing globally (check before any tracing operation)
MAINFRAME_TRACE_ENABLED="${MAINFRAME_TRACE_ENABLED:-0}"

# Output destination for trace data (file path or /dev/stderr)
MAINFRAME_TRACE_FILE="${MAINFRAME_TRACE_FILE:-/dev/stderr}"

# Maximum number of trace entries to retain in memory
MAINFRAME_TRACE_MAX_ENTRIES="${MAINFRAME_TRACE_MAX_ENTRIES:-1000}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# State directory for trace data (survives subshells)
MAINFRAME_TRACE_STATE_DIR="${MAINFRAME_TRACE_STATE_DIR:-${TMPDIR:-/tmp}/mainframe_trace_$$}"

# Associative arrays for runtime state (Bash 4.0+)
declare -gA _TRACE_TIMERS 2>/dev/null || declare -A _TRACE_TIMERS
declare -gA _TRACE_WATCHED_VARS 2>/dev/null || declare -A _TRACE_WATCHED_VARS
declare -gA _TRACE_FUNC_WRAPPERS 2>/dev/null || declare -A _TRACE_FUNC_WRAPPERS
declare -gA _TRACE_VAR_VALUES 2>/dev/null || declare -A _TRACE_VAR_VALUES
declare -gA _TRACE_SNAPSHOTS 2>/dev/null || declare -A _TRACE_SNAPSHOTS

# Sequential trace entries (stored as JSON lines)
declare -ga _TRACE_ENTRIES 2>/dev/null || declare -a _TRACE_ENTRIES

# Active recording session
_TRACE_RECORDING_SESSION=""
_TRACE_RECORDING_ACTIVE=0

# Original DEBUG trap (if any)
_TRACE_ORIGINAL_DEBUG_TRAP=""

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Get high-precision timestamp
# Uses EPOCHREALTIME (Bash 5.0+) or /proc/uptime fallback
_trace_now() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        printf '%s' "$EPOCHREALTIME"
    elif [[ -r /proc/uptime ]]; then
        local uptime
        read -r uptime _ < /proc/uptime
        printf '%s' "$uptime"
    elif [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s.000000' "$EPOCHSECONDS"
    else
        date +%s.%N 2>/dev/null || date +%s
    fi
}

# Get timestamp in nanoseconds (integer) where possible
_trace_now_ns() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        local ts="$EPOCHREALTIME"
        local secs="${ts%%.*}"
        local frac="${ts#*.}"
        # Pad or truncate to 9 digits (nanoseconds)
        frac="${frac}000000000"
        frac="${frac:0:9}"
        printf '%s%s' "$secs" "$frac"
    else
        local ts
        ts=$(_trace_now)
        local secs="${ts%%.*}"
        local frac="${ts#*.}"
        frac="${frac}000000000"
        frac="${frac:0:9}"
        printf '%s%s' "$secs" "$frac"
    fi
}

# JSON-escape a string (minimal, safe implementation)
_trace_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    # Handle control characters
    str="${str//$'\b'/\\b}"
    str="${str//$'\f'/\\f}"
    printf '%s' "$str"
}

# Emit a JSON trace entry to output
_trace_emit() {
    [[ "$MAINFRAME_TRACE_ENABLED" != "1" ]] && return 0
    local json="$1"

    # Add to memory buffer
    if (( ${#_TRACE_ENTRIES[@]} >= MAINFRAME_TRACE_MAX_ENTRIES )); then
        # Remove oldest entry
        _TRACE_ENTRIES=("${_TRACE_ENTRIES[@]:1}")
    fi
    _TRACE_ENTRIES+=("$json")

    # Write to output destination
    if [[ "$MAINFRAME_TRACE_FILE" == "/dev/stderr" ]]; then
        printf '%s\n' "$json" >&2
    elif [[ -n "$MAINFRAME_TRACE_FILE" ]]; then
        printf '%s\n' "$json" >> "$MAINFRAME_TRACE_FILE"
    fi
}

# Ensure state directory exists
_trace_ensure_state_dir() {
    [[ -d "$MAINFRAME_TRACE_STATE_DIR" ]] || mkdir -p "$MAINFRAME_TRACE_STATE_DIR"
}

# Calculate duration between two timestamps
_trace_duration() {
    local start="$1"
    local end="$2"

    if command -v bc &>/dev/null; then
        local result
        result=$(printf '%s - %s\n' "$end" "$start" | bc 2>/dev/null || echo "0")
        [[ "$result" == .* ]] && result="0$result"
        printf '%s' "$result"
    else
        local start_int end_int
        start_int="${start%%.*}"
        end_int="${end%%.*}"
        printf '%d' $((end_int - start_int))
    fi
}

# =============================================================================
# FUNCTION TRACING
# =============================================================================

# @pre: func_name is a defined function
# @post: function is wrapped with timing/argument tracing
# @idempotent: yes - re-tracing same function is safe
# @returns: 0 on success, 1 if function not found
#
# Intercept a function to trace all calls with timing and arguments.
# Creates a wrapper function that logs entry/exit and delegates to original.
#
# Usage: trace_function "my_func"
# Example: trace_function "process_file"
trace_function() {
    [[ "$MAINFRAME_TRACE_ENABLED" != "1" ]] && return 0

    local func_name="$1"

    # Validate function exists
    if ! declare -f "$func_name" &>/dev/null; then
        return 1
    fi

    # Skip if already traced
    [[ -n "${_TRACE_FUNC_WRAPPERS[$func_name]:-}" ]] && return 0

    # Store original function definition
    local orig_def
    orig_def=$(declare -f "$func_name")
    _TRACE_FUNC_WRAPPERS["$func_name"]="$orig_def"

    # Rename original function
    local orig_name="_trace_orig_${func_name}"

    # Create renamed original using function body extraction
    local func_body
    func_body="${orig_def#*\{}"
    func_body="${func_body%\}}"

    # Define the renamed original
    # shellcheck disable=SC2163
    printf -v "$orig_name" '%s' "placeholder"
    unset "$orig_name"

    # Use a file-based approach to avoid eval
    _trace_ensure_state_dir
    local wrapper_file="$MAINFRAME_TRACE_STATE_DIR/wrapper_${func_name}.sh"

    cat > "$wrapper_file" << WRAPPER_EOF
# Renamed original function
${orig_name}() {
${func_body}
}

# Tracing wrapper
${func_name}() {
    local _trace_start _trace_end _trace_result _trace_exit_code
    _trace_start=\$(_trace_now)

    # Build args JSON array
    local _trace_args_json="["
    local _trace_first=true
    for _trace_arg in "\$@"; do
        if [[ "\$_trace_first" == "true" ]]; then
            _trace_first=false
        else
            _trace_args_json+=","
        fi
        local _trace_escaped_arg
        _trace_escaped_arg=\$(_trace_escape "\$_trace_arg")
        _trace_args_json+="\"\$_trace_escaped_arg\""
    done
    _trace_args_json+="]"

    # Log entry
    _trace_emit "{\"event\":\"func_entry\",\"func\":\"${func_name}\",\"args\":\$_trace_args_json,\"timestamp\":\$_trace_start}"

    # Call original
    _trace_result=\$($orig_name "\$@")
    _trace_exit_code=\$?

    _trace_end=\$(_trace_now)
    local _trace_duration
    _trace_duration=\$(_trace_duration "\$_trace_start" "\$_trace_end")

    # Log exit
    local _trace_escaped_result
    _trace_escaped_result=\$(_trace_escape "\$_trace_result")
    _trace_emit "{\"event\":\"func_exit\",\"func\":\"${func_name}\",\"exit_code\":\$_trace_exit_code,\"duration_s\":\$_trace_duration,\"timestamp\":\$_trace_end}"

    printf '%s' "\$_trace_result"
    return \$_trace_exit_code
}
WRAPPER_EOF

    # Source the wrapper
    # shellcheck source=/dev/null
    source "$wrapper_file"

    return 0
}

# @pre: func_name was previously traced
# @post: original function restored
# @idempotent: yes
# @returns: 0 on success, 1 if function was not traced
#
# Remove tracing from a function and restore the original.
#
# Usage: trace_untrace "my_func"
trace_untrace() {
    local func_name="$1"

    # Check if traced
    [[ -z "${_TRACE_FUNC_WRAPPERS[$func_name]:-}" ]] && return 1

    # Restore original definition
    local orig_def="${_TRACE_FUNC_WRAPPERS[$func_name]}"

    # Write to temp file and source (avoids eval)
    _trace_ensure_state_dir
    local restore_file="$MAINFRAME_TRACE_STATE_DIR/restore_${func_name}.sh"
    printf '%s\n' "$orig_def" > "$restore_file"
    # shellcheck source=/dev/null
    source "$restore_file"

    # Clean up
    unset "_TRACE_FUNC_WRAPPERS[$func_name]"
    rm -f "$MAINFRAME_TRACE_STATE_DIR/wrapper_${func_name}.sh" 2>/dev/null
    rm -f "$restore_file" 2>/dev/null

    return 0
}

# @pre: file_path is a valid bash script
# @post: all functions in file are traced
# @idempotent: yes
# @returns: 0 on success, 1 if file not found
#
# Trace all function definitions in a bash file.
#
# Usage: trace_all_in_file "lib/utils.sh"
trace_all_in_file() {
    [[ "$MAINFRAME_TRACE_ENABLED" != "1" ]] && return 0

    local file_path="$1"

    [[ -f "$file_path" ]] || return 1

    # Extract function names (handles both styles: func() and function func)
    local func_names
    func_names=$(grep -E '^\s*(function\s+)?[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)' "$file_path" | \
                 sed -E 's/^\s*(function\s+)?([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\).*/\2/')

    local func_name
    while IFS= read -r func_name; do
        [[ -n "$func_name" ]] && trace_function "$func_name"
    done <<< "$func_names"

    return 0
}

# =============================================================================
# VARIABLE WATCHING
# =============================================================================

# @pre: var_name is a valid variable name
# @post: DEBUG trap installed to watch variable changes
# @idempotent: yes
# @returns: 0
#
# Watch a variable for changes using DEBUG trap.
# Emits JSON event when variable value changes.
#
# Usage: trace_variable "my_var"
# Example: trace_variable "CONFIG_FILE"
trace_variable() {
    [[ "$MAINFRAME_TRACE_ENABLED" != "1" ]] && return 0

    local var_name="$1"

    # Store current value
    _TRACE_WATCHED_VARS["$var_name"]=1
    _TRACE_VAR_VALUES["$var_name"]="${!var_name:-}"

    # Install DEBUG trap if not already active
    _trace_install_debug_trap

    return 0
}

# @pre: var_name was previously watched
# @post: variable no longer watched
# @idempotent: yes
# @returns: 0
#
# Stop watching a variable.
#
# Usage: trace_unwatch "my_var"
trace_unwatch() {
    local var_name="$1"

    unset "_TRACE_WATCHED_VARS[$var_name]"
    unset "_TRACE_VAR_VALUES[$var_name]"

    # If no more watched vars, remove DEBUG trap
    if [[ ${#_TRACE_WATCHED_VARS[@]} -eq 0 ]]; then
        _trace_remove_debug_trap
    fi

    return 0
}

# Install DEBUG trap for variable watching
_trace_install_debug_trap() {
    # Store original trap if not already stored
    if [[ -z "$_TRACE_ORIGINAL_DEBUG_TRAP" ]]; then
        _TRACE_ORIGINAL_DEBUG_TRAP=$(trap -p DEBUG)
    fi

    # Set our DEBUG trap
    trap '_trace_debug_handler' DEBUG
}

# Remove DEBUG trap
_trace_remove_debug_trap() {
    # Restore original trap or clear it
    if [[ -n "$_TRACE_ORIGINAL_DEBUG_TRAP" ]]; then
        # shellcheck disable=SC2064
        trap "${_TRACE_ORIGINAL_DEBUG_TRAP#trap -- }" DEBUG 2>/dev/null || trap - DEBUG
        _TRACE_ORIGINAL_DEBUG_TRAP=""
    else
        trap - DEBUG
    fi
}

# DEBUG trap handler - check watched variables
_trace_debug_handler() {
    [[ "$MAINFRAME_TRACE_ENABLED" != "1" ]] && return 0

    local var_name old_value new_value
    for var_name in "${!_TRACE_WATCHED_VARS[@]}"; do
        old_value="${_TRACE_VAR_VALUES[$var_name]:-}"
        new_value="${!var_name:-}"

        if [[ "$old_value" != "$new_value" ]]; then
            _TRACE_VAR_VALUES["$var_name"]="$new_value"

            local escaped_old escaped_new
            escaped_old=$(_trace_escape "$old_value")
            escaped_new=$(_trace_escape "$new_value")

            local now func file line
            now=$(_trace_now)
            func="${FUNCNAME[1]:-main}"
            file="${BASH_SOURCE[1]:-unknown}"
            line="${BASH_LINENO[0]:-0}"

            _trace_emit "{\"event\":\"var_change\",\"var\":\"$var_name\",\"old\":\"$escaped_old\",\"new\":\"$escaped_new\",\"func\":\"$func\",\"file\":\"$file\",\"line\":$line,\"timestamp\":$now}"
        fi
    done
}

# @pre: name is a valid identifier
# @post: snapshot of all shell variables stored
# @idempotent: no - overwrites previous snapshot with same name
# @returns: 0
#
# Capture a snapshot of all shell variables for later comparison.
#
# Usage: trace_snapshot "before_operation"
trace_snapshot() {
    [[ "$MAINFRAME_TRACE_ENABLED" != "1" ]] && return 0

    local name="$1"
    local now
    now=$(_trace_now)

    _trace_ensure_state_dir
    local snapshot_file="$MAINFRAME_TRACE_STATE_DIR/snapshot_${name}.txt"

    # Capture all variables (excluding internal trace vars)
    declare -p 2>/dev/null | grep -v '^declare.*_TRACE_' | grep -v '^declare.*MAINFRAME_TRACE' > "$snapshot_file"

    _TRACE_SNAPSHOTS["$name"]="$snapshot_file"

    _trace_emit "{\"event\":\"snapshot\",\"name\":\"$name\",\"timestamp\":$now}"

    return 0
}

# @pre: both snapshots exist
# @post: JSON diff printed to stdout
# @idempotent: yes
# @returns: 0 on success, 1 if snapshot not found
#
# Compare two snapshots and output differences as JSON.
#
# Usage: diff_json=$(trace_diff "snap1" "snap2")
trace_diff() {
    local snap1="$1"
    local snap2="$2"

    local file1="${_TRACE_SNAPSHOTS[$snap1]:-}"
    local file2="${_TRACE_SNAPSHOTS[$snap2]:-}"

    [[ -f "$file1" ]] || return 1
    [[ -f "$file2" ]] || return 1

    local json='{"diff":{'
    local added='[]'
    local removed='[]'
    local changed='[]'

    # Extract variable names and values from snapshots
    declare -A vars1 vars2

    local line var_name var_value
    while IFS= read -r line; do
        if [[ "$line" =~ ^declare\ [^\ ]+\ ([a-zA-Z_][a-zA-Z0-9_]*)= ]]; then
            var_name="${BASH_REMATCH[1]}"
            vars1["$var_name"]="$line"
        fi
    done < "$file1"

    while IFS= read -r line; do
        if [[ "$line" =~ ^declare\ [^\ ]+\ ([a-zA-Z_][a-zA-Z0-9_]*)= ]]; then
            var_name="${BASH_REMATCH[1]}"
            vars2["$var_name"]="$line"
        fi
    done < "$file2"

    # Find added, removed, and changed
    local added_arr=() removed_arr=() changed_arr=()

    for var_name in "${!vars2[@]}"; do
        if [[ -z "${vars1[$var_name]:-}" ]]; then
            added_arr+=("\"$var_name\"")
        elif [[ "${vars1[$var_name]}" != "${vars2[$var_name]}" ]]; then
            changed_arr+=("\"$var_name\"")
        fi
    done

    for var_name in "${!vars1[@]}"; do
        if [[ -z "${vars2[$var_name]:-}" ]]; then
            removed_arr+=("\"$var_name\"")
        fi
    done

    # Build JSON arrays
    local IFS=','
    added="[${added_arr[*]:-}]"
    removed="[${removed_arr[*]:-}]"
    changed="[${changed_arr[*]:-}]"

    json+='"added":'$added',"removed":'$removed',"changed":'$changed
    json+='},"snap1":"'$snap1'","snap2":"'$snap2'"}'

    printf '%s' "$json"
    return 0
}

# =============================================================================
# TIMING
# =============================================================================

# @pre: label is a valid identifier
# @post: timer started, stored in associative array
# @idempotent: no - restarts timer
# @returns: 0
#
# Start a high-precision timer with the given label.
#
# Usage: trace_timer_start "database_query"
trace_timer_start() {
    local label="$1"
    local now
    now=$(_trace_now_ns)
    _TRACE_TIMERS["$label"]="$now"

    if [[ "$MAINFRAME_TRACE_ENABLED" == "1" ]]; then
        _trace_emit "{\"event\":\"timer_start\",\"label\":\"$label\",\"timestamp_ns\":$now}"
    fi

    return 0
}

# @pre: timer with label was started
# @post: elapsed time printed (nanoseconds if available)
# @idempotent: yes - can be called multiple times
# @returns: 0 on success, 1 if timer not found
#
# Stop timer and return elapsed time in nanoseconds (or seconds with decimal).
#
# Usage: elapsed=$(trace_timer_stop "database_query")
trace_timer_stop() {
    local label="$1"
    local start="${_TRACE_TIMERS[$label]:-}"

    [[ -z "$start" ]] && { printf '0'; return 1; }

    local end
    end=$(_trace_now_ns)

    # Calculate difference
    local elapsed
    elapsed=$((end - start))

    if [[ "$MAINFRAME_TRACE_ENABLED" == "1" ]]; then
        _trace_emit "{\"event\":\"timer_stop\",\"label\":\"$label\",\"elapsed_ns\":$elapsed,\"timestamp_ns\":$end}"
    fi

    # Clean up timer
    unset "_TRACE_TIMERS[$label]"

    printf '%s' "$elapsed"
    return 0
}

# @pre: label provided, command is executable
# @post: command executed, timing JSON printed
# @idempotent: depends on command
# @returns: exit code of command
#
# Time a command execution and emit timing information.
#
# Usage: trace_timing "fetch_data" curl -s http://example.com
trace_timing() {
    local label="$1"
    shift

    local start end elapsed exit_code
    start=$(_trace_now_ns)

    # Execute command
    "$@"
    exit_code=$?

    end=$(_trace_now_ns)
    elapsed=$((end - start))

    if [[ "$MAINFRAME_TRACE_ENABLED" == "1" ]]; then
        local escaped_cmd
        escaped_cmd=$(_trace_escape "$*")
        _trace_emit "{\"event\":\"timing\",\"label\":\"$label\",\"cmd\":\"$escaped_cmd\",\"exit_code\":$exit_code,\"elapsed_ns\":$elapsed,\"timestamp_ns\":$end}"
    fi

    return $exit_code
}

# =============================================================================
# OUTPUT
# =============================================================================

# @pre: trace entries collected
# @post: JSON array of all trace entries printed
# @idempotent: yes
# @returns: 0
#
# Output all collected trace entries as a JSON array.
#
# Usage: all_traces=$(trace_to_json)
trace_to_json() {
    local json="["
    local first=true
    local entry

    for entry in "${_TRACE_ENTRIES[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=","
        fi
        json+="$entry"
    done

    json+="]"
    printf '%s' "$json"
}

# @pre: trace entries with function events collected
# @post: Mermaid sequence diagram printed
# @idempotent: yes
# @returns: 0
#
# Generate a Mermaid sequence diagram from function trace events.
#
# Usage: diagram=$(trace_to_mermaid)
trace_to_mermaid() {
    printf 'sequenceDiagram\n'
    printf '    participant Main\n'

    local participants=()
    local entry func event

    # First pass: collect unique function names
    for entry in "${_TRACE_ENTRIES[@]}"; do
        if [[ "$entry" =~ \"func\":\"([^\"]+)\" ]]; then
            func="${BASH_REMATCH[1]}"
            local found=0
            for p in "${participants[@]}"; do
                [[ "$p" == "$func" ]] && found=1 && break
            done
            if [[ "$found" -eq 0 && "$func" != "main" ]]; then
                participants+=("$func")
                printf '    participant %s\n' "$func"
            fi
        fi
    done

    # Second pass: generate sequence
    local caller="Main"
    for entry in "${_TRACE_ENTRIES[@]}"; do
        if [[ "$entry" =~ \"event\":\"func_entry\",\"func\":\"([^\"]+)\" ]]; then
            func="${BASH_REMATCH[1]}"
            printf '    %s->>%s: call()\n' "$caller" "$func"
            caller="$func"
        elif [[ "$entry" =~ \"event\":\"func_exit\",\"func\":\"([^\"]+)\" ]]; then
            func="${BASH_REMATCH[1]}"
            printf '    %s-->>Main: return\n' "$func"
            caller="Main"
        fi
    done
}

# @pre: none
# @post: all trace data cleared
# @idempotent: yes
# @returns: 0
#
# Clear all trace data from memory.
#
# Usage: trace_clear
trace_clear() {
    _TRACE_ENTRIES=()
    _TRACE_TIMERS=()
    _TRACE_WATCHED_VARS=()
    _TRACE_VAR_VALUES=()
    _TRACE_FUNC_WRAPPERS=()
    _TRACE_SNAPSHOTS=()

    # Clean up state directory
    [[ -d "$MAINFRAME_TRACE_STATE_DIR" ]] && rm -rf "$MAINFRAME_TRACE_STATE_DIR"/*

    return 0
}

# @pre: file_path is writable
# @post: trace output redirected to file
# @idempotent: yes
# @returns: 0
#
# Set the output destination for trace data.
#
# Usage: trace_set_output "/tmp/traces.jsonl"
trace_set_output() {
    local file_path="$1"
    MAINFRAME_TRACE_FILE="$file_path"
    return 0
}

# =============================================================================
# REPLAY (ADVANCED)
# =============================================================================

# @pre: session is a valid identifier
# @post: recording started, inputs/commands captured
# @idempotent: no - starts new recording
# @returns: 0
#
# Begin recording a session for later replay.
# Captures commands executed and their arguments.
#
# Usage: trace_record_start "my_session"
trace_record_start() {
    [[ "$MAINFRAME_TRACE_ENABLED" != "1" ]] && return 0

    local session="$1"

    _trace_ensure_state_dir

    _TRACE_RECORDING_SESSION="$session"
    _TRACE_RECORDING_ACTIVE=1

    local record_file="$MAINFRAME_TRACE_STATE_DIR/record_${session}.jsonl"
    : > "$record_file"

    local now
    now=$(_trace_now)
    printf '{"event":"session_start","session":"%s","timestamp":%s}\n' "$session" "$now" >> "$record_file"

    _trace_emit "{\"event\":\"record_start\",\"session\":\"$session\",\"timestamp\":$now}"

    return 0
}

# @pre: recording active
# @post: recording stopped
# @idempotent: yes
# @returns: 0
#
# Stop the current recording session.
#
# Usage: trace_record_stop
trace_record_stop() {
    [[ "$_TRACE_RECORDING_ACTIVE" != "1" ]] && return 0

    local session="$_TRACE_RECORDING_SESSION"
    local record_file="$MAINFRAME_TRACE_STATE_DIR/record_${session}.jsonl"

    local now
    now=$(_trace_now)
    printf '{"event":"session_end","session":"%s","timestamp":%s}\n' "$session" "$now" >> "$record_file"

    _TRACE_RECORDING_ACTIVE=0
    _TRACE_RECORDING_SESSION=""

    _trace_emit "{\"event\":\"record_stop\",\"session\":\"$session\",\"timestamp\":$now}"

    return 0
}

# @pre: session was recorded
# @post: commands replayed to stdout
# @idempotent: yes (outputs same replay)
# @returns: 0 on success, 1 if session not found
#
# Replay a recorded session (outputs the recorded commands as JSON).
#
# Usage: trace_replay "my_session"
trace_replay() {
    local session="$1"

    _trace_ensure_state_dir
    local record_file="$MAINFRAME_TRACE_STATE_DIR/record_${session}.jsonl"

    [[ -f "$record_file" ]] || return 1

    printf '{"replay_session":"%s","events":[\n' "$session"

    local first=true line
    while IFS= read -r line; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            printf ',\n'
        fi
        printf '%s' "$line"
    done < "$record_file"

    printf '\n]}\n'

    return 0
}

# Record a command execution (called internally or manually)
trace_record_command() {
    [[ "$_TRACE_RECORDING_ACTIVE" != "1" ]] && return 0

    local cmd="$1"
    shift

    local session="$_TRACE_RECORDING_SESSION"
    local record_file="$MAINFRAME_TRACE_STATE_DIR/record_${session}.jsonl"

    local now
    now=$(_trace_now)

    # Build args JSON
    local args_json="["
    local first=true arg
    for arg in "$@"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            args_json+=","
        fi
        local escaped
        escaped=$(_trace_escape "$arg")
        args_json+="\"$escaped\""
    done
    args_json+="]"

    local escaped_cmd
    escaped_cmd=$(_trace_escape "$cmd")

    printf '{"event":"command","cmd":"%s","args":%s,"timestamp":%s}\n' "$escaped_cmd" "$args_json" "$now" >> "$record_file"

    return 0
}

# =============================================================================
# CONTROL FUNCTIONS
# =============================================================================

# @pre: none
# @post: tracing enabled globally
# @idempotent: yes
# @returns: 0
#
# Enable tracing globally.
#
# Usage: trace_enable
trace_enable() {
    MAINFRAME_TRACE_ENABLED=1
    _trace_ensure_state_dir
    return 0
}

# @pre: none
# @post: tracing disabled globally
# @idempotent: yes
# @returns: 0
#
# Disable tracing globally.
#
# Usage: trace_disable
trace_disable() {
    MAINFRAME_TRACE_ENABLED=0
    return 0
}

# @pre: none
# @post: prints 1 if enabled, 0 if disabled
# @idempotent: yes
# @returns: 0 if enabled, 1 if disabled
#
# Check if tracing is enabled.
#
# Usage: trace_is_enabled && echo "Tracing active"
trace_is_enabled() {
    [[ "$MAINFRAME_TRACE_ENABLED" == "1" ]]
}

# @pre: none
# @post: JSON status printed
# @idempotent: yes
# @returns: 0
#
# Get trace system status as JSON.
#
# Usage: status=$(trace_status)
trace_status() {
    local enabled="false"
    [[ "$MAINFRAME_TRACE_ENABLED" == "1" ]] && enabled="true"

    local entry_count="${#_TRACE_ENTRIES[@]}"
    local timer_count="${#_TRACE_TIMERS[@]}"
    local watched_count="${#_TRACE_WATCHED_VARS[@]}"
    local func_count="${#_TRACE_FUNC_WRAPPERS[@]}"
    local snapshot_count="${#_TRACE_SNAPSHOTS[@]}"

    local recording="false"
    [[ "$_TRACE_RECORDING_ACTIVE" == "1" ]] && recording="true"

    printf '{"enabled":%s,"entries":%d,"timers":%d,"watched_vars":%d,"traced_funcs":%d,"snapshots":%d,"recording":%s,"output":"%s"}' \
        "$enabled" "$entry_count" "$timer_count" "$watched_count" "$func_count" "$snapshot_count" "$recording" "$MAINFRAME_TRACE_FILE"
}

# =============================================================================
# CLEANUP
# =============================================================================

# Clean up trace state on exit
_trace_cleanup() {
    # Remove DEBUG trap if installed
    if [[ ${#_TRACE_WATCHED_VARS[@]} -gt 0 ]]; then
        _trace_remove_debug_trap
    fi

    # Clean up state directory
    [[ -d "$MAINFRAME_TRACE_STATE_DIR" ]] && rm -rf "$MAINFRAME_TRACE_STATE_DIR"
}

# Register cleanup (only if not in sourced-only mode)
if [[ -z "${_MAINFRAME_TRACE_NO_CLEANUP:-}" ]]; then
    trap _trace_cleanup EXIT
fi

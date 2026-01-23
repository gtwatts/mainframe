#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/observe.sh - Structured Observability for AI Agents
# =============================================================================
# Description: Trace, timing, and structured error reporting that produces
#              JSON output AI coding assistants can parse for debugging,
#              error recovery, and performance analysis.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_OBSERVE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_OBSERVE_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Output destination for traces (stderr by default, can be file path)
MAINFRAME_TRACE_OUTPUT="${MAINFRAME_TRACE_OUTPUT:-/dev/stderr}"

# Enable/disable tracing globally
MAINFRAME_TRACE_ENABLED="${MAINFRAME_TRACE_ENABLED:-1}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Directory for trace state files (survives subshells)
MAINFRAME_TRACE_DIR="${MAINFRAME_TRACE_DIR:-${TMPDIR:-/tmp}/mainframe_traces_$$}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Get current time in seconds (with microseconds if available)
_observe_now() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        printf '%s' "$EPOCHREALTIME"
    elif [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s.000000' "$EPOCHSECONDS"
    else
        date +%s.%N 2>/dev/null || date +%s
    fi
}

# Get epoch seconds (integer)
_observe_epoch() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    else
        date +%s
    fi
}

# JSON-escape a string (lightweight inline version)
_observe_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Emit a JSON line to trace output
_observe_emit() {
    [[ "$MAINFRAME_TRACE_ENABLED" != "1" ]] && return 0
    local json="$1"
    if [[ "$MAINFRAME_TRACE_OUTPUT" == "/dev/stderr" ]]; then
        printf '%s\n' "$json" >&2
    else
        printf '%s\n' "$json" >> "$MAINFRAME_TRACE_OUTPUT"
    fi
}

# Generate a unique trace ID using /dev/urandom
_observe_gen_id() {
    local rand
    rand=$(head -c 6 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' || printf '%s%s' "$$" "$RANDOM")
    printf 'trace_%s' "$rand"
}

# =============================================================================
# TRACE OPERATIONS
# =============================================================================

# @pre: none
# @post: new trace started, ID stored for later steps/end
# @idempotent: no - each call creates a new trace
# @returns: 0, prints trace_id to stdout
#
# Begin a named trace. Returns a trace ID that must be passed to
# trace_step and trace_end. Captures start timestamp.
# State is stored in files to survive subshell boundaries.
#
# Usage: trace_id=$(trace_start "operation_name")
# Example: tid=$(trace_start "deploy_config")
trace_start() {
    local name="${1:-unnamed}"
    local trace_id
    trace_id=$(_observe_gen_id)

    local now
    now=$(_observe_now)

    # Store state in files (survives subshells)
    mkdir -p "$MAINFRAME_TRACE_DIR"
    printf '%s\n' "$now" > "$MAINFRAME_TRACE_DIR/${trace_id}.start"
    printf '%s\n' "$name" > "$MAINFRAME_TRACE_DIR/${trace_id}.name"
    : > "$MAINFRAME_TRACE_DIR/${trace_id}.steps"

    local escaped_name
    escaped_name=$(_observe_escape "$name")

    _observe_emit "{\"event\":\"trace_start\",\"trace_id\":\"$trace_id\",\"name\":\"$escaped_name\",\"timestamp\":$now}"

    printf '%s' "$trace_id"
}

# @pre: trace_id from trace_start exists
# @post: step recorded in trace
# @idempotent: no - each call adds a step
# @returns: 0 on success, 1 if trace_id invalid
#
# Record a step within an active trace. Each step has a name,
# optional status, and optional detail message.
#
# Usage: trace_step "$trace_id" "step_name" [status] [detail]
# Example: trace_step "$tid" "write_config" "ok" "wrote 3 keys"
# Example: trace_step "$tid" "validate" "error" "missing required field"
trace_step() {
    local trace_id="$1"
    local step_name="${2:-step}"
    local status="${3:-ok}"
    local detail="${4:-}"

    # Verify trace exists
    if [[ ! -f "$MAINFRAME_TRACE_DIR/${trace_id}.start" ]]; then
        return 1
    fi

    local now
    now=$(_observe_now)

    local escaped_step escaped_detail escaped_status
    escaped_step=$(_observe_escape "$step_name")
    escaped_status=$(_observe_escape "$status")
    escaped_detail=$(_observe_escape "$detail")

    local step_json
    step_json="{\"step\":\"$escaped_step\",\"status\":\"$escaped_status\""
    if [[ -n "$detail" ]]; then
        step_json+=",\"detail\":\"$escaped_detail\""
    fi
    step_json+=",\"timestamp\":$now}"

    # Append to steps file
    printf '%s\n' "$step_json" >> "$MAINFRAME_TRACE_DIR/${trace_id}.steps"

    _observe_emit "{\"event\":\"trace_step\",\"trace_id\":\"$trace_id\",\"step\":\"$escaped_step\",\"status\":\"$escaped_status\",\"detail\":\"$escaped_detail\",\"timestamp\":$now}"
}

# @pre: trace_id from trace_start exists
# @post: trace completed, full JSON summary emitted
# @idempotent: no - ends the trace
# @returns: 0, prints JSON summary to stdout
#
# End a trace and emit a complete JSON summary including all steps,
# duration, and final status.
#
# Usage: summary=$(trace_end "$trace_id" [status])
# Example: result=$(trace_end "$tid" "success")
# Example: result=$(trace_end "$tid" "failed")
trace_end() {
    local trace_id="$1"
    local status="${2:-success}"

    if [[ ! -f "$MAINFRAME_TRACE_DIR/${trace_id}.start" ]]; then
        printf '{"error":"unknown trace_id","trace_id":"%s"}' "$trace_id"
        return 1
    fi

    local now start_time name
    now=$(_observe_now)
    start_time=$(<"$MAINFRAME_TRACE_DIR/${trace_id}.start")
    start_time="${start_time%$'\n'}"
    name=$(<"$MAINFRAME_TRACE_DIR/${trace_id}.name")
    name="${name%$'\n'}"

    # Calculate duration
    local duration
    if command -v bc &>/dev/null; then
        duration=$(printf '%s - %s\n' "$now" "$start_time" | bc 2>/dev/null || echo "0")
        [[ "$duration" == .* ]] && duration="0$duration"
    else
        local now_int start_int
        now_int="${now%%.*}"
        start_int="${start_time%%.*}"
        duration=$((now_int - start_int))
    fi

    local escaped_name escaped_status
    escaped_name=$(_observe_escape "$name")
    escaped_status=$(_observe_escape "$status")

    # Read steps from file, join with commas
    local steps=""
    if [[ -s "$MAINFRAME_TRACE_DIR/${trace_id}.steps" ]]; then
        local line first=true
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if [[ "$first" == "true" ]]; then
                first=false
            else
                steps+=","
            fi
            steps+="$line"
        done < "$MAINFRAME_TRACE_DIR/${trace_id}.steps"
    fi

    local summary
    summary="{\"event\":\"trace_end\",\"trace_id\":\"$trace_id\",\"name\":\"$escaped_name\",\"status\":\"$escaped_status\",\"duration_s\":$duration,\"started\":$start_time,\"ended\":$now,\"steps\":[$steps]}"

    _observe_emit "$summary"

    # Cleanup state files
    rm -f "$MAINFRAME_TRACE_DIR/${trace_id}".{start,name,steps}

    printf '%s' "$summary"
}

# =============================================================================
# COMMAND OBSERVATION
# =============================================================================

# @pre: command is executable
# @post: command executed, result captured with timing and exit code
# @idempotent: depends on the command
# @returns: exit code of the command
#
# Execute a command and capture its stdout, stderr, exit code, and duration
# as a structured JSON object. Useful for AI agents to understand command
# outcomes without parsing unstructured output.
#
# Usage: result=$(observe_command "command" [args...])
# Example: result=$(observe_command ls -la /tmp)
# Example: result=$(observe_command npm test)
#
# Output JSON: {"cmd":"...","exit_code":N,"duration_s":N,"stdout":"...","stderr":"..."}
observe_command() {
    if [[ $# -eq 0 ]]; then
        printf '{"error":"no command provided","exit_code":1}'
        return 1
    fi

    local cmd_display="$*"
    local escaped_cmd
    escaped_cmd=$(_observe_escape "$cmd_display")

    local start_time end_time
    start_time=$(_observe_now)

    # Execute and capture
    local stdout_file stderr_file
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)

    local exit_code=0
    "$@" > "$stdout_file" 2> "$stderr_file" || exit_code=$?

    end_time=$(_observe_now)

    # Read captured output (truncate to prevent context overflow)
    local stdout stderr
    stdout=$(head -c 4096 "$stdout_file" 2>/dev/null || true)
    stderr=$(head -c 2048 "$stderr_file" 2>/dev/null || true)
    rm -f "$stdout_file" "$stderr_file"

    local escaped_stdout escaped_stderr
    escaped_stdout=$(_observe_escape "$stdout")
    escaped_stderr=$(_observe_escape "$stderr")

    # Calculate duration
    local duration
    if command -v bc &>/dev/null; then
        duration=$(printf '%s - %s\n' "$end_time" "$start_time" | bc 2>/dev/null || echo "0")
        [[ "$duration" == .* ]] && duration="0$duration"
    else
        local end_int start_int
        end_int="${end_time%%.*}"
        start_int="${start_time%%.*}"
        duration=$((end_int - start_int))
    fi

    local result
    result="{\"cmd\":\"$escaped_cmd\",\"exit_code\":$exit_code,\"duration_s\":$duration,\"stdout\":\"$escaped_stdout\",\"stderr\":\"$escaped_stderr\"}"

    _observe_emit "$result"
    printf '%s' "$result"
    return $exit_code
}

# =============================================================================
# STACK TRACE
# =============================================================================

# @pre: called within a function (FUNCNAME/BASH_SOURCE populated)
# @post: JSON stack trace emitted
# @idempotent: yes
# @returns: 0, prints JSON array of call stack frames
#
# Capture the current bash call stack as a JSON array.
# Each frame includes function name, source file, and line number.
# Useful for error reporting that AI agents can parse.
#
# Usage: trace=$(stack_trace)
# Example: some_error && stack_trace >&2
stack_trace() {
    local frames=""
    local i
    local depth=${#FUNCNAME[@]}

    for ((i=1; i<depth; i++)); do
        local func="${FUNCNAME[$i]:-unknown}"
        local file="${BASH_SOURCE[$i]:-unknown}"
        local line="${BASH_LINENO[$((i-1))]:-0}"

        local escaped_func escaped_file
        escaped_func=$(_observe_escape "$func")
        escaped_file=$(_observe_escape "$file")

        if [[ -n "$frames" ]]; then
            frames+=","
        fi
        frames+="{\"func\":\"$escaped_func\",\"file\":\"$escaped_file\",\"line\":$line}"
    done

    local result="{\"stack\":[$frames],\"depth\":$((depth-1))}"
    printf '%s' "$result"
}

# =============================================================================
# STRUCTURED ERROR REPORTING
# =============================================================================

# @pre: none
# @post: JSON error object emitted to stderr
# @returns: the provided exit code
#
# Emit a structured error with code, message, function context, and stack.
# Designed for AI agents to parse and take corrective action.
#
# Usage: observe_error 1 "file not found" [extra_context]
# Example: observe_error 2 "invalid port number" "port=$port"
observe_error() {
    local code="${1:-1}"
    local msg="${2:-unknown error}"
    local context="${3:-}"

    local func="${FUNCNAME[1]:-main}"
    local file="${BASH_SOURCE[1]:-unknown}"
    local line="${BASH_LINENO[0]:-0}"

    local escaped_msg escaped_func escaped_file escaped_context
    escaped_msg=$(_observe_escape "$msg")
    escaped_func=$(_observe_escape "$func")
    escaped_file=$(_observe_escape "$file")
    escaped_context=$(_observe_escape "$context")

    local error_json
    error_json="{\"error\":true,\"code\":$code,\"msg\":\"$escaped_msg\",\"func\":\"$escaped_func\",\"file\":\"$escaped_file\",\"line\":$line"
    if [[ -n "$context" ]]; then
        error_json+=",\"context\":\"$escaped_context\""
    fi
    error_json+="}"

    printf '%s\n' "$error_json" >&2
    return "$code"
}

# =============================================================================
# TIMING UTILITIES
# =============================================================================

# @pre: none
# @post: returns current high-resolution timestamp
# @returns: 0, prints timestamp
#
# Get current timestamp suitable for duration calculations.
# Uses EPOCHREALTIME (bash 5.0+) or date fallback.
#
# Usage: start=$(observe_time)
observe_time() {
    _observe_now
}

# @pre: start timestamp from observe_time
# @post: duration calculated
# @returns: 0, prints duration in seconds
#
# Calculate elapsed time between a start timestamp and now.
#
# Usage: elapsed=$(observe_elapsed "$start")
observe_elapsed() {
    local start="$1"
    local now
    now=$(_observe_now)

    local result
    if command -v bc &>/dev/null; then
        result=$(printf '%s - %s\n' "$now" "$start" | bc 2>/dev/null || echo "0")
        # Trim whitespace from bc output
        result="${result#"${result%%[![:space:]]*}"}"
        # Ensure leading zero for values < 1
        [[ "$result" == .* ]] && result="0$result"
        printf '%s' "$result"
    else
        local now_int start_int
        now_int="${now%%.*}"
        start_int="${start%%.*}"
        printf '%d' $((now_int - start_int))
    fi
}

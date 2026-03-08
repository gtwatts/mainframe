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
# Priority: EPOCHREALTIME (Bash 5.0+) > EPOCHSECONDS > printf builtin > date
_observe_now() {
    local ts
    # Fastest: Bash 5.0+ EPOCHREALTIME (microsecond precision)
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        printf '%s' "$EPOCHREALTIME"
    # Fast: Bash 5.0+ EPOCHSECONDS (second precision)
    elif [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s.000000' "$EPOCHSECONDS"
    # Medium: Bash 4.2+ printf builtin (~100x faster than date)
    elif printf -v ts '%(%s)T' -1 2>/dev/null && [[ -n "$ts" ]]; then
        printf '%s.000000' "$ts"
    # Fallback: external date command
    else
        date +%s.%N 2>/dev/null || date +%s
    fi
}

# Get epoch seconds (integer)
# Priority: EPOCHSECONDS (Bash 5.0+) > printf builtin > date
_observe_epoch() {
    local ts
    # Fastest: Bash 5.0+ EPOCHSECONDS variable
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    # Fast: Bash 4.2+ printf builtin (~100x faster than date)
    elif printf -v ts '%(%s)T' -1 2>/dev/null && [[ -n "$ts" ]]; then
        printf '%s' "$ts"
    # Fallback: external date command
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

# =============================================================================
# OPENTELEMETRY TRACING - W3C Trace Context Compliant
# =============================================================================
# Specification: https://www.w3.org/TR/trace-context/
# OTLP Format: https://opentelemetry.io/docs/specs/otlp/
# =============================================================================

# =============================================================================
# OTEL CONFIGURATION
# =============================================================================

# OTLP HTTP endpoint for trace export
OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-http://localhost:4318}"

# Service name for traces
OTEL_SERVICE_NAME="${OTEL_SERVICE_NAME:-mainframe}"

# Enable/disable OTEL tracing (separate from legacy traces)
OTEL_TRACE_ENABLED="${OTEL_TRACE_ENABLED:-1}"

# Sampling rate (1.0 = 100%, 0.5 = 50%, etc.)
OTEL_TRACE_SAMPLE_RATE="${OTEL_TRACE_SAMPLE_RATE:-1.0}"

# =============================================================================
# OTEL INTERNAL STATE
# =============================================================================

# Directory for OTEL span state files (multi-process safe)
OTEL_SPAN_DIR="${OTEL_SPAN_DIR:-${TMPDIR:-/tmp}/mainframe_otel_$$}"

# Associative array for current trace context
declare -gA _OTEL_TRACE_CTX

# Batch buffer for span collection
declare -ga _OTEL_BATCH_BUFFER=()

# Batch mode flag
_OTEL_BATCH_MODE="${_OTEL_BATCH_MODE:-0}"

# =============================================================================
# OTEL INTERNAL HELPERS
# =============================================================================

# Generate 32-character hex trace ID (128 bits)
_otel_gen_trace_id() {
    if [[ -r /dev/urandom ]]; then
        head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
    else
        # Fallback: use timestamp + PID + random
        printf '%016x%016x' "$$$(date +%s%N 2>/dev/null || echo "$RANDOM$RANDOM")" "$RANDOM$RANDOM$RANDOM$RANDOM"
    fi
}

# Generate 16-character hex span ID (64 bits)
_otel_gen_span_id() {
    if [[ -r /dev/urandom ]]; then
        head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n'
    else
        # Fallback
        printf '%016x' "$$$(date +%N 2>/dev/null || echo "$RANDOM")$RANDOM"
    fi
}

# Get current time in nanoseconds (Unix epoch)
_otel_now_nanos() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        # Bash 5.0+ EPOCHREALTIME: seconds.microseconds
        local epoch_real="$EPOCHREALTIME"
        local secs="${epoch_real%%.*}"
        local frac="${epoch_real#*.}"
        # Pad/truncate to 9 digits for nanoseconds
        frac="${frac}000000000"
        printf '%s%s' "$secs" "${frac:0:9}"
    elif date +%s%N &>/dev/null 2>&1; then
        date +%s%N
    else
        # Fallback: seconds with 9 zeros
        printf '%s000000000' "$(date +%s)"
    fi
}

_otel_context_file() {
    printf '%s/.context' "$OTEL_SPAN_DIR"
}

_otel_context_write() {
    mkdir -p "$OTEL_SPAN_DIR" 2>/dev/null || return 1

    cat > "$(_otel_context_file)" << EOF
trace_id=${_OTEL_TRACE_CTX[trace_id]:-}
span_id=${_OTEL_TRACE_CTX[span_id]:-}
parent_id=${_OTEL_TRACE_CTX[parent_id]:-}
flags=${_OTEL_TRACE_CTX[flags]:-01}
EOF
}

_otel_context_load() {
    local context_file
    context_file="$(_otel_context_file)"
    [[ -f "$context_file" ]] || return 1

    local key value
    while IFS='=' read -r key value; do
        case "$key" in
            trace_id|span_id|parent_id|flags)
                _OTEL_TRACE_CTX["$key"]="$value"
                ;;
        esac
    done < "$context_file"

    return 0
}

_otel_context_clear() {
    _OTEL_TRACE_CTX[trace_id]=""
    _OTEL_TRACE_CTX[span_id]=""
    _OTEL_TRACE_CTX[parent_id]=""
    _OTEL_TRACE_CTX[flags]=""
    rm -f "$(_otel_context_file)" 2>/dev/null || true
}

_observe_json_get_string() {
    local json="$1"
    local field="$2"

    if [[ "$json" =~ \"$field\"[[:space:]]*:[[:space:]]*\"([^\\\"]*)\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

_observe_json_get_number() {
    local json="$1"
    local field="$2"

    if [[ "$json" =~ \"$field\"[[:space:]]*:[[:space:]]*([0-9.]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

_otel_append_array_json() {
    local json="$1"
    local field="$2"
    local entry_json="$3"
    local empty_token="\"${field}\": []"
    local array_token="\"${field}\": ["

    if [[ "$json" == *"$empty_token"* ]]; then
        printf '%s' "${json/$empty_token/\"${field}\": [$entry_json]}"
    else
        printf '%s' "${json/$array_token/\"${field}\": [$entry_json, }"
    fi
}

_otel_replace_status_json() {
    local json="$1"
    local status_json="$2"

    if [[ "$json" =~ \"status\"[[:space:]]*:[[:space:]]*\{[^}]*\} ]]; then
        local old_status="${BASH_REMATCH[0]}"
        printf '%s' "${json/$old_status/\"status\": $status_json}"
        return 0
    fi

    printf '%s' "$json"
    return 0
}

# Validate hex string of specified length
_otel_validate_hex() {
    local hex="$1"
    local expected_len="$2"

    if [[ ${#hex} -ne $expected_len ]]; then
        return 1
    fi

    if [[ ! "$hex" =~ ^[0-9a-fA-F]+$ ]]; then
        return 1
    fi

    return 0
}

# Check if tracing is enabled and sampled
_otel_should_trace() {
    [[ "$OTEL_TRACE_ENABLED" != "1" ]] && return 1

    # Simple sampling based on OTEL_TRACE_SAMPLE_RATE
    if [[ "$OTEL_TRACE_SAMPLE_RATE" != "1.0" && "$OTEL_TRACE_SAMPLE_RATE" != "1" ]]; then
        local rand=$((RANDOM % 100))
        local threshold
        threshold=$(printf '%.0f' "$(echo "$OTEL_TRACE_SAMPLE_RATE * 100" | bc 2>/dev/null || echo "100")")
        [[ $rand -ge $threshold ]] && return 1
    fi

    return 0
}

# =============================================================================
# TRACE MANAGEMENT
# =============================================================================

# @pre: none
# @post: new trace started, context stored
# @idempotent: no - each call creates a new trace
# @returns: 0, prints trace_id to stdout
#
# Start a new trace with W3C trace context.
# Optionally accepts JSON attributes for the root span.
#
# Usage: trace_id=$(otel_trace_start "operation-name")
# Usage: trace_id=$(otel_trace_start "operation-name" '{"service":"myapp"}')
otel_trace_start() {
    local name="${1:-unnamed}"
    local attributes="${2:-}"

    _otel_should_trace || { printf ''; return 0; }

    local trace_id span_id start_time
    trace_id=$(_otel_gen_trace_id)
    span_id=$(_otel_gen_span_id)
    start_time=$(_otel_now_nanos)

    # Initialize trace context
    _OTEL_TRACE_CTX[trace_id]="$trace_id"
    _OTEL_TRACE_CTX[span_id]="$span_id"
    _OTEL_TRACE_CTX[parent_id]=""
    _OTEL_TRACE_CTX[flags]="01"  # Sampled
    _otel_context_write || return 1

    # Create span directory
    mkdir -p "$OTEL_SPAN_DIR"

    # Store root span state
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"
    cat > "$span_file" << EOF
{
  "traceId": "$trace_id",
  "spanId": "$span_id",
  "parentSpanId": "",
  "name": "$(_observe_escape "$name")",
  "kind": "INTERNAL",
  "startTimeUnixNano": $start_time,
  "attributes": $(if [[ -n "$attributes" ]]; then echo "$attributes"; else echo '[]'; fi),
  "events": [],
  "status": {"code": "UNSET"}
}
EOF

    printf '%s' "$trace_id"
}

# @pre: trace_id from otel_trace_start (optional, uses current context if not provided)
# @post: trace ended, spans can be exported
# @idempotent: no - ends the trace
# @returns: 0
#
# End the current trace. If trace_id is provided, ends that specific trace.
# Otherwise uses the current trace context.
#
# Usage: otel_trace_end
# Usage: otel_trace_end "$trace_id"
otel_trace_end() {
    _otel_context_load >/dev/null 2>&1 || true
    local trace_id="${1:-${_OTEL_TRACE_CTX[trace_id]:-}}"

    [[ -z "$trace_id" ]] && return 0

    # Find the root span for this trace and end it
    local root_span_file
    root_span_file=$(find "$OTEL_SPAN_DIR" -name "${trace_id}_*.span" -type f 2>/dev/null | head -1)

    if [[ -n "$root_span_file" && -f "$root_span_file" ]]; then
        local end_time
        end_time=$(_otel_now_nanos)

        # Read current span, add endTimeUnixNano
        local span_json
        span_json=$(<"$root_span_file")

        # Update with end time (simple sed replacement)
        span_json="${span_json%\}}"
        span_json+=",\"endTimeUnixNano\": $end_time}"

        printf '%s' "$span_json" > "$root_span_file"
    fi

    if [[ "${_OTEL_TRACE_CTX[trace_id]:-}" == "$trace_id" ]]; then
        _otel_context_clear
    fi

    return 0
}

# =============================================================================
# SPAN MANAGEMENT
# =============================================================================

# @pre: active trace context or parent_id provided
# @post: new span created within current trace
# @idempotent: no - each call creates a new span
# @returns: 0, prints span_id to stdout
#
# Create a span within the current trace.
# If parent_id is not provided, uses the current span as parent.
#
# Usage: span_id=$(otel_span_create "function-call")
# Usage: span_id=$(otel_span_create "function-call" "$parent_span_id")
otel_span_create() {
    _otel_context_load >/dev/null 2>&1 || true
    local name="${1:-unnamed_span}"
    local parent_id="${2:-${_OTEL_TRACE_CTX[span_id]:-}}"
    local trace_id="${_OTEL_TRACE_CTX[trace_id]:-}"

    [[ -z "$trace_id" ]] && { printf ''; return 1; }

    local span_id start_time
    span_id=$(_otel_gen_span_id)
    start_time=$(_otel_now_nanos)

    # Update current span context
    _OTEL_TRACE_CTX[parent_id]="$parent_id"
    _OTEL_TRACE_CTX[span_id]="$span_id"
    _otel_context_write || return 1

    # Create span file
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"
    cat > "$span_file" << EOF
{
  "traceId": "$trace_id",
  "spanId": "$span_id",
  "parentSpanId": "$parent_id",
  "name": "$(_observe_escape "$name")",
  "kind": "INTERNAL",
  "startTimeUnixNano": $start_time,
  "attributes": [],
  "events": [],
  "status": {"code": "UNSET"}
}
EOF

    printf '%s' "$span_id"
}

# @pre: span_id from otel_span_create
# @post: span ended with status
# @idempotent: no - ends the span
# @returns: 0 on success, 1 if span not found
#
# End a span with optional status code.
# Status can be "OK", "ERROR", or "UNSET".
#
# Usage: otel_span_end "$span_id"
# Usage: otel_span_end "$span_id" "OK"
# Usage: otel_span_end "$span_id" "ERROR"
otel_span_end() {
    local span_id="$1"
    local status="${2:-OK}"
    _otel_context_load >/dev/null 2>&1 || true
    local trace_id="${_OTEL_TRACE_CTX[trace_id]:-}"

    if [[ -z "$trace_id" && -n "$span_id" ]]; then
        local span_file_match
        span_file_match=$(find "$OTEL_SPAN_DIR" -name "*_${span_id}.span" -type f 2>/dev/null | head -1)
        if [[ -n "$span_file_match" ]]; then
            trace_id=$(basename "$span_file_match" .span)
            trace_id="${trace_id%_${span_id}}"
            _OTEL_TRACE_CTX[trace_id]="$trace_id"
        fi
    fi

    [[ -z "$span_id" || -z "$trace_id" ]] && return 1

    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    [[ ! -f "$span_file" ]] && return 1

    local end_time
    end_time=$(_otel_now_nanos)

    # Read span JSON
    local span_json
    span_json=$(<"$span_file")

    # Map status to OTLP codes
    local status_code
    case "$status" in
        OK|ok)       status_code="OK" ;;
        ERROR|error) status_code="ERROR" ;;
        *)           status_code="UNSET" ;;
    esac

    # Update end time and status
    # Replace the status and add endTimeUnixNano
    span_json=$(_otel_replace_status_json "$span_json" "{\"code\": \"$status_code\"}")
    span_json="${span_json%\}}"
    span_json+=",\"endTimeUnixNano\": $end_time}"

    printf '%s' "$span_json" > "$span_file"

    # Restore parent span as current
    local parent_id
    parent_id=$(_observe_json_get_string "$span_json" "parentSpanId" || true)
    _OTEL_TRACE_CTX[parent_id]="$parent_id"
    _OTEL_TRACE_CTX[span_id]="$parent_id"
    _otel_context_write || return 1

    return 0
}

# @pre: span_id from otel_span_create
# @post: attribute added to span
# @idempotent: no - adds attribute each call
# @returns: 0 on success, 1 if span not found
#
# Add a key-value attribute to a span.
# Value type is auto-detected (string, number, boolean).
#
# Usage: otel_span_attribute "$span_id" "http.method" "GET"
# Usage: otel_span_attribute "$span_id" "http.status_code" "200"
otel_span_attribute() {
    local span_id="$1"
    local key="$2"
    local value="$3"
    _otel_context_load >/dev/null 2>&1 || true
    local trace_id="${_OTEL_TRACE_CTX[trace_id]:-}"

    [[ -z "$span_id" || -z "$trace_id" || -z "$key" ]] && return 1

    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    [[ ! -f "$span_file" ]] && return 1

    # Determine value type and format
    local attr_json
    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
        attr_json="{\"key\": \"$(_observe_escape "$key")\", \"value\": {\"intValue\": $value}}"
    elif [[ "$value" =~ ^-?[0-9]+\.[0-9]+$ ]]; then
        attr_json="{\"key\": \"$(_observe_escape "$key")\", \"value\": {\"doubleValue\": $value}}"
    elif [[ "$value" == "true" || "$value" == "false" ]]; then
        attr_json="{\"key\": \"$(_observe_escape "$key")\", \"value\": {\"boolValue\": $value}}"
    else
        attr_json="{\"key\": \"$(_observe_escape "$key")\", \"value\": {\"stringValue\": \"$(_observe_escape "$value")\"}}"
    fi

    # Read span and append attribute
    local span_json
    span_json=$(<"$span_file")

    # Find attributes array and append
    span_json=$(_otel_append_array_json "$span_json" "attributes" "$attr_json")

    printf '%s' "$span_json" > "$span_file"

    return 0
}

# @pre: span_id from otel_span_create
# @post: event added to span
# @idempotent: no - adds event each call
# @returns: 0 on success, 1 if span not found
#
# Add a timestamped event to a span.
# Events represent discrete occurrences during span execution.
#
# Usage: otel_span_event "$span_id" "cache.hit"
# Usage: otel_span_event "$span_id" "db.query" '{"sql":"SELECT *"}'
otel_span_event() {
    local span_id="$1"
    local name="$2"
    local attributes="${3:-}"
    _otel_context_load >/dev/null 2>&1 || true
    local trace_id="${_OTEL_TRACE_CTX[trace_id]:-}"

    [[ -z "$span_id" || -z "$trace_id" || -z "$name" ]] && return 1

    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    [[ ! -f "$span_file" ]] && return 1

    local event_time
    event_time=$(_otel_now_nanos)

    local event_json
    event_json="{\"timeUnixNano\": $event_time, \"name\": \"$(_observe_escape "$name")\""

    if [[ -n "$attributes" ]]; then
        event_json+=", \"attributes\": $attributes"
    else
        event_json+=", \"attributes\": []"
    fi
    event_json+="}"

    # Read span and append event
    local span_json
    span_json=$(<"$span_file")

    # Find events array and append
    span_json=$(_otel_append_array_json "$span_json" "events" "$event_json")

    printf '%s' "$span_json" > "$span_file"

    return 0
}

# @pre: span_id from otel_span_create
# @post: exception recorded in span with ERROR status
# @idempotent: no - records exception each call
# @returns: 0 on success, 1 if span not found
#
# Record an exception in a span. Sets span status to ERROR.
#
# Usage: otel_span_exception "$span_id" "File not found" "$stack_trace"
otel_span_exception() {
    local span_id="$1"
    local message="$2"
    local stacktrace="${3:-}"
    _otel_context_load >/dev/null 2>&1 || true
    local trace_id="${_OTEL_TRACE_CTX[trace_id]:-}"

    [[ -z "$span_id" || -z "$trace_id" ]] && return 1

    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    [[ ! -f "$span_file" ]] && return 1

    # Build exception attributes
    local attrs="["
    attrs+="{\"key\": \"exception.message\", \"value\": {\"stringValue\": \"$(_observe_escape "$message")\"}},"
    attrs+="{\"key\": \"exception.type\", \"value\": {\"stringValue\": \"bash.error\"}}"
    if [[ -n "$stacktrace" ]]; then
        attrs+=",{\"key\": \"exception.stacktrace\", \"value\": {\"stringValue\": \"$(_observe_escape "$stacktrace")\"}}"
    fi
    attrs+="]"

    # Add exception event
    otel_span_event "$span_id" "exception" "$attrs"

    # Update span status to ERROR
    local span_json
    span_json=$(<"$span_file")
    span_json=$(_otel_replace_status_json "$span_json" "{\"code\": \"ERROR\", \"message\": \"$(_observe_escape "$message")\"}")

    printf '%s' "$span_json" > "$span_file"

    return 0
}

# =============================================================================
# CONTEXT PROPAGATION - W3C Trace Context
# =============================================================================

# @pre: active trace context
# @post: none (read-only)
# @returns: 0, prints W3C traceparent header value
#
# Get the W3C traceparent header value for the current context.
# Format: version-trace_id-span_id-flags
# Example: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
#
# Usage: traceparent=$(otel_traceparent)
otel_traceparent() {
    _otel_context_load >/dev/null 2>&1 || true
    local trace_id="${_OTEL_TRACE_CTX[trace_id]:-}"
    local span_id="${_OTEL_TRACE_CTX[span_id]:-}"
    local flags="${_OTEL_TRACE_CTX[flags]:-01}"

    [[ -z "$trace_id" || -z "$span_id" ]] && return 1

    printf '00-%s-%s-%s' "$trace_id" "$span_id" "$flags"
}

# @pre: active trace context
# @post: none (read-only)
# @returns: 0, prints W3C tracestate header value
#
# Get the W3C tracestate header value for the current context.
# Contains vendor-specific trace information.
#
# Usage: tracestate=$(otel_tracestate)
otel_tracestate() {
    _otel_context_load >/dev/null 2>&1 || true
    local trace_id="${_OTEL_TRACE_CTX[trace_id]:-}"

    [[ -z "$trace_id" ]] && return 1

    printf 'mainframe=%s' "${trace_id:0:16}"
}

# @pre: valid W3C traceparent header value
# @post: sets OTEL_TRACE_ID, OTEL_PARENT_SPAN_ID, OTEL_FLAGS
# @idempotent: yes
# @returns: 0 on success, 1 if invalid format
#
# Parse an incoming traceparent header and populate environment variables.
#
# Usage: otel_parse_traceparent "00-xxx-yyy-01"
otel_parse_traceparent() {
    local traceparent="$1"

    # W3C format: version-trace_id-parent_id-flags
    # version: 2 hex chars (00)
    # trace_id: 32 hex chars
    # parent_id: 16 hex chars
    # flags: 2 hex chars (01 = sampled)

    if [[ ! "$traceparent" =~ ^([0-9a-fA-F]{2})-([0-9a-fA-F]{32})-([0-9a-fA-F]{16})-([0-9a-fA-F]{2})$ ]]; then
        return 1
    fi

    local version="${BASH_REMATCH[1]}"
    local trace_id="${BASH_REMATCH[2]}"
    local parent_span_id="${BASH_REMATCH[3]}"
    local flags="${BASH_REMATCH[4]}"

    # Only support version 00
    if [[ "$version" != "00" ]]; then
        return 1
    fi

    # Validate trace_id is not all zeros
    if [[ "$trace_id" =~ ^0+$ ]]; then
        return 1
    fi

    # Validate parent_span_id is not all zeros
    if [[ "$parent_span_id" =~ ^0+$ ]]; then
        return 1
    fi

    # Export parsed values
    export OTEL_TRACE_ID="$trace_id"
    export OTEL_PARENT_SPAN_ID="$parent_span_id"
    export OTEL_FLAGS="$flags"

    # Update internal context
    _OTEL_TRACE_CTX[trace_id]="$trace_id"
    _OTEL_TRACE_CTX[parent_id]="$parent_span_id"
    _OTEL_TRACE_CTX[flags]="$flags"

    return 0
}

# @pre: active trace context
# @post: TRACEPARENT and TRACESTATE exported to environment
# @idempotent: yes
# @returns: 0
#
# Propagate trace context to child processes via environment variables.
# Call before spawning subprocesses to maintain trace continuity.
#
# Usage: otel_context_inject && ./child_process.sh
otel_context_inject() {
    local traceparent tracestate

    traceparent=$(otel_traceparent) || return 1
    tracestate=$(otel_tracestate) || return 1

    export TRACEPARENT="$traceparent"
    export TRACESTATE="$tracestate"

    return 0
}

# @pre: TRACEPARENT environment variable set (from parent process)
# @post: trace context restored from environment
# @idempotent: yes
# @returns: 0 on success, 1 if no context found
#
# Extract trace context from environment variables.
# Call at the start of child processes to continue the trace.
#
# Usage: otel_context_extract && otel_span_create "child-operation"
otel_context_extract() {
    local traceparent="${TRACEPARENT:-}"

    [[ -z "$traceparent" ]] && return 1

    otel_parse_traceparent "$traceparent" || return 1
    _otel_context_write
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# @pre: spans exist in OTEL_SPAN_DIR
# @post: spans exported to OTLP HTTP endpoint
# @returns: 0 on success, 1 on failure
#
# Export all collected spans to an OTLP HTTP endpoint.
# Uses /dev/tcp for pure bash HTTP or falls back to curl.
#
# Usage: otel_export_otlp
# Usage: otel_export_otlp "http://collector:4318"
otel_export_otlp() {
    local endpoint="${1:-$OTEL_EXPORTER_OTLP_ENDPOINT}"
    local traces_endpoint="${endpoint}/v1/traces"

    # Collect all completed spans
    local spans=""
    local first=true

    # Use nullglob to handle empty directory gracefully
    local _old_nullglob
    _old_nullglob=$(shopt -p nullglob 2>/dev/null || echo "shopt -u nullglob")
    shopt -s nullglob

    for span_file in "$OTEL_SPAN_DIR"/*.span; do
        [[ -f "$span_file" ]] || continue

        # Only export completed spans (have endTimeUnixNano)
        if grep -q "endTimeUnixNano" "$span_file" 2>/dev/null; then
            local span_json
            span_json=$(<"$span_file")

            $first || spans+=","
            first=false
            spans+="$span_json"
        fi
    done

    [[ -z "$spans" ]] && return 0

    # Build OTLP request body
    local body
    body=$(cat << EOF
{
  "resourceSpans": [{
    "resource": {
      "attributes": [
        {"key": "service.name", "value": {"stringValue": "$OTEL_SERVICE_NAME"}},
        {"key": "telemetry.sdk.name", "value": {"stringValue": "mainframe"}},
        {"key": "telemetry.sdk.language", "value": {"stringValue": "bash"}}
      ]
    },
    "scopeSpans": [{
      "scope": {
        "name": "mainframe.observe",
        "version": "1.0.0"
      },
      "spans": [$spans]
    }]
  }]
}
EOF
)

    # Try curl first (most reliable)
    if type -p curl &>/dev/null; then
        if curl -sf -X POST "$traces_endpoint" \
            -H "Content-Type: application/json" \
            -d "$body" &>/dev/null; then
            # Clean up exported spans
            _otel_cleanup_exported_spans
            return 0
        fi
    fi

    # Fallback: /dev/tcp for HTTP (not HTTPS)
    if [[ "$traces_endpoint" =~ ^http://([^/:]+):?([0-9]*)(/.*)$ ]]; then
        local host="${BASH_REMATCH[1]}"
        local port="${BASH_REMATCH[2]:-80}"
        local path="${BASH_REMATCH[3]}"

        local content_length=${#body}
        local request
        request="POST $path HTTP/1.1\r\n"
        request+="Host: $host\r\n"
        request+="Content-Type: application/json\r\n"
        request+="Content-Length: $content_length\r\n"
        request+="Connection: close\r\n"
        request+="\r\n"
        request+="$body"

        if exec 3<>"/dev/tcp/$host/$port" 2>/dev/null; then
            printf '%b' "$request" >&3
            local response
            response=$(cat <&3)
            exec 3>&-

            if [[ "$response" =~ HTTP/[0-9.]+[[:space:]]2[0-9]{2} ]]; then
                _otel_cleanup_exported_spans
                return 0
            fi
        fi
    fi

    return 1
}

# @pre: spans exist in OTEL_SPAN_DIR
# @post: spans written to JSON file
# @returns: 0 on success, 1 on failure
#
# Export all spans to a JSON file for debugging or batch processing.
#
# Usage: otel_export_json "/tmp/traces.json"
otel_export_json() {
    local output_file="$1"

    [[ -z "$output_file" ]] && return 1

    # Collect all spans
    local spans=""
    local first=true

    for span_file in "$OTEL_SPAN_DIR"/*.span; do
        [[ -f "$span_file" ]] || continue

        local span_json
        span_json=$(<"$span_file")

        $first || spans+=","
        first=false
        spans+="$span_json"
    done

    # Write OTLP format JSON
    cat > "$output_file" << EOF
{
  "resourceSpans": [{
    "resource": {
      "attributes": [
        {"key": "service.name", "value": {"stringValue": "$OTEL_SERVICE_NAME"}}
      ]
    },
    "scopeSpans": [{
      "scope": {"name": "mainframe.observe"},
      "spans": [$spans]
    }]
  }]
}
EOF

    return 0
}

# @pre: spans exist in OTEL_SPAN_DIR
# @post: spans printed to stderr as structured log lines
# @returns: 0
#
# Export spans to console as structured JSON log lines.
# Useful for debugging and development.
#
# Usage: otel_export_console
otel_export_console() {
    for span_file in "$OTEL_SPAN_DIR"/*.span; do
        [[ -f "$span_file" ]] || continue

        local span_json
        span_json=$(<"$span_file")

        # Format as single-line JSON log
        printf '[OTEL] %s\n' "$(printf '%s' "$span_json" | tr -d '\n' | tr -s ' ')" >&2
    done

    return 0
}

# @pre: none
# @post: pending spans flushed to configured exporter
# @returns: 0
#
# Flush any pending/buffered spans.
# Should be called before process exit to ensure all spans are exported.
#
# Usage: otel_flush
otel_flush() {
    # If batch mode is active, flush the batch
    if [[ "$_OTEL_BATCH_MODE" == "1" ]]; then
        otel_batch_flush
    fi

    # End any unclosed spans
    for span_file in "$OTEL_SPAN_DIR"/*.span; do
        [[ -f "$span_file" ]] || continue

        if ! grep -q "endTimeUnixNano" "$span_file" 2>/dev/null; then
            local span_id
            span_id=$(basename "$span_file" .span | cut -d_ -f2)
            otel_span_end "$span_id" "ERROR"
        fi
    done

    return 0
}

# Internal: clean up exported span files
_otel_cleanup_exported_spans() {
    for span_file in "$OTEL_SPAN_DIR"/*.span; do
        [[ -f "$span_file" ]] || continue

        if grep -q "endTimeUnixNano" "$span_file" 2>/dev/null; then
            rm -f "$span_file"
        fi
    done
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# @pre: function_name is a valid function
# @post: function executed with automatic span instrumentation
# @returns: exit code of the instrumented function
#
# Auto-instrument a function call with span creation/completion.
# Wraps function execution with span lifecycle management.
#
# Usage: otel_instrument "my_function" arg1 arg2
otel_instrument() {
    local func_name="$1"
    shift

    local span_id exit_code
    span_id=$(otel_span_create "$func_name")

    # Execute function
    "$func_name" "$@"
    exit_code=$?

    # End span with appropriate status
    if [[ $exit_code -eq 0 ]]; then
        otel_span_end "$span_id" "OK"
    else
        otel_span_end "$span_id" "ERROR"
    fi

    return $exit_code
}

# @pre: active trace context
# @post: command executed with timing span
# @returns: exit code of the command
#
# Measure execution time with automatic span creation.
#
# Usage: otel_timed "db-query" psql -c "SELECT * FROM users"
otel_timed() {
    local span_name="$1"
    shift

    local span_id exit_code
    span_id=$(otel_span_create "$span_name")

    # Add command as attribute
    otel_span_attribute "$span_id" "command" "$*"

    # Execute command
    "$@"
    exit_code=$?

    # Add exit code as attribute
    otel_span_attribute "$span_id" "exit_code" "$exit_code"

    # End span with appropriate status
    if [[ $exit_code -eq 0 ]]; then
        otel_span_end "$span_id" "OK"
    else
        otel_span_end "$span_id" "ERROR"
    fi

    return $exit_code
}

# =============================================================================
# BATCH COLLECTION
# =============================================================================

# @pre: none
# @post: batch mode enabled
# @returns: 0
#
# Start batch collection mode for efficiency.
# Spans are buffered and exported together.
#
# Usage: otel_batch_start
otel_batch_start() {
    _OTEL_BATCH_MODE="1"
    _OTEL_BATCH_BUFFER=()
    return 0
}

# @pre: batch mode active
# @post: span JSON added to batch buffer
# @returns: 0
#
# Add a span JSON to the batch buffer.
# Internal use primarily, but can be used for custom span formats.
#
# Usage: otel_batch_add "$span_json"
otel_batch_add() {
    local span_json="$1"
    _OTEL_BATCH_BUFFER+=("$span_json")
    return 0
}

# @pre: batch mode active with buffered spans
# @post: all buffered spans exported, buffer cleared
# @returns: 0 on success, 1 on failure
#
# Flush all buffered spans to the configured exporter.
#
# Usage: otel_batch_flush
otel_batch_flush() {
    [[ ${#_OTEL_BATCH_BUFFER[@]} -eq 0 ]] && return 0

    # Write buffered spans to temp files for export
    local i span_json trace_id span_id
    for span_json in "${_OTEL_BATCH_BUFFER[@]}"; do
        trace_id=$(_observe_json_get_string "$span_json" "traceId" || echo "batch")
        span_id=$(_observe_json_get_string "$span_json" "spanId" || echo "$RANDOM")

        mkdir -p "$OTEL_SPAN_DIR"
        printf '%s' "$span_json" > "$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"
    done

    # Export and clean up
    otel_export_otlp || true

    # Clear buffer
    _OTEL_BATCH_BUFFER=()
    _OTEL_BATCH_MODE="0"

    return 0
}

# =============================================================================
# LEGACY BRIDGE
# =============================================================================

# @pre: trace_id from legacy trace_start
# @post: OTEL context populated from legacy trace
# @returns: 0 on success, 1 if trace not found
#
# Bridge function to convert a legacy MAINFRAME trace to OTEL format.
# Allows gradual migration from trace_* to otel_* functions.
#
# Usage: otel_from_trace "$legacy_trace_id"
otel_from_trace() {
    local legacy_trace_id="$1"

    # Check if legacy trace exists
    if [[ ! -f "$MAINFRAME_TRACE_DIR/${legacy_trace_id}.start" ]]; then
        return 1
    fi

    # Read legacy trace data
    local start_time name
    start_time=$(<"$MAINFRAME_TRACE_DIR/${legacy_trace_id}.start")
    name=$(<"$MAINFRAME_TRACE_DIR/${legacy_trace_id}.name")

    # Generate OTEL IDs from legacy trace
    local trace_id span_id
    # Use hash of legacy ID for deterministic mapping
    if type -p sha256sum &>/dev/null; then
        trace_id=$(printf '%s' "$legacy_trace_id" | sha256sum | cut -c1-32)
        span_id=$(printf '%s-root' "$legacy_trace_id" | sha256sum | cut -c1-16)
    else
        # Fallback: pad/truncate legacy ID
        trace_id=$(printf '%-32s' "${legacy_trace_id//[^a-zA-Z0-9]/}" | tr ' ' '0' | cut -c1-32)
        span_id=$(printf '%-16s' "${legacy_trace_id//[^a-zA-Z0-9]/}" | tr ' ' '0' | cut -c1-16)
    fi

    # Convert start time to nanoseconds
    local start_nanos
    local secs="${start_time%%.*}"
    local frac="${start_time#*.}"
    frac="${frac}000000000"
    start_nanos="${secs}${frac:0:9}"

    # Initialize OTEL context
    _OTEL_TRACE_CTX[trace_id]="$trace_id"
    _OTEL_TRACE_CTX[span_id]="$span_id"
    _OTEL_TRACE_CTX[parent_id]=""
    _OTEL_TRACE_CTX[flags]="01"
    _otel_context_write || return 1

    # Create OTEL span file
    mkdir -p "$OTEL_SPAN_DIR"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    cat > "$span_file" << EOF
{
  "traceId": "$trace_id",
  "spanId": "$span_id",
  "parentSpanId": "",
  "name": "$(_observe_escape "${name%$'\n'}")",
  "kind": "INTERNAL",
  "startTimeUnixNano": $start_nanos,
  "attributes": [
    {"key": "legacy.trace_id", "value": {"stringValue": "$legacy_trace_id"}}
  ],
  "events": [],
  "status": {"code": "UNSET"}
}
EOF

    # Convert legacy steps to OTEL events
    if [[ -s "$MAINFRAME_TRACE_DIR/${legacy_trace_id}.steps" ]]; then
        while IFS= read -r step_json; do
            [[ -z "$step_json" ]] && continue

            local step_name step_status step_detail step_ts
            step_name=$(_observe_json_get_string "$step_json" "step" || echo "step")
            step_status=$(_observe_json_get_string "$step_json" "status" || echo "ok")
            step_detail=$(_observe_json_get_string "$step_json" "detail" || echo "")
            step_ts=$(_observe_json_get_number "$step_json" "timestamp" || echo "0")

            local step_attrs="["
            step_attrs+="{\"key\": \"step.status\", \"value\": {\"stringValue\": \"$step_status\"}}"
            if [[ -n "$step_detail" ]]; then
                step_attrs+=",{\"key\": \"step.detail\", \"value\": {\"stringValue\": \"$step_detail\"}}"
            fi
            step_attrs+="]"

            otel_span_event "$span_id" "legacy.step.$step_name" "$step_attrs"
        done < "$MAINFRAME_TRACE_DIR/${legacy_trace_id}.steps"
    fi

    printf '%s' "$trace_id"
    return 0
}

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/output.sh - Universal Structured Output Protocol (USOP)
# =============================================================================
# Description: Unified output layer that formats function results as raw text,
#              JSON envelopes, minimal, or debug output based on the
#              MAINFRAME_OUTPUT environment variable. Enables AI agents and
#              scripts to consume structured responses with timing metadata.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_OUTPUT_LOADED:-}" ]] && return 0
readonly _MAINFRAME_OUTPUT_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Output mode: raw (default), json, minimal, debug
MAINFRAME_OUTPUT="${MAINFRAME_OUTPUT:-raw}"

# Hint for next function (set by callers, consumed by output)
MAINFRAME_OUTPUT_HINT="${MAINFRAME_OUTPUT_HINT:-}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Lightweight JSON escape (inline, avoids json.sh dependency)
# Handles: backslash, double-quote, newline, tab, carriage return, control chars
_output_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\b'/\\b}"
    str="${str//$'\f'/\\f}"
    printf '%s' "$str"
}

# Get current time with sub-millisecond precision
# Uses EPOCHREALTIME (bash 5.0+) or falls back to date +%s%N
_output_now_ns() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        # EPOCHREALTIME is seconds.microseconds (e.g., 1705312896.123456)
        # Convert to nanoseconds for consistent internal representation
        local epoch_real="$EPOCHREALTIME"
        local secs="${epoch_real%%.*}"
        local frac="${epoch_real#*.}"
        # Pad fraction to 9 digits (microseconds -> nanoseconds)
        while [[ ${#frac} -lt 9 ]]; do
            frac="${frac}0"
        done
        frac="${frac:0:9}"
        printf '%s%s' "$secs" "$frac"
    else
        # Fallback: date +%s%N (GNU coreutils)
        local ns
        ns=$(date +%s%N 2>/dev/null)
        if [[ -n "$ns" && "$ns" != *"N"* ]]; then
            printf '%s' "$ns"
        else
            # Last resort: seconds only (macOS without GNU date)
            printf '%s000000000' "$(date +%s)"
        fi
    fi
}

# Compute elapsed milliseconds from nanosecond timestamps
# Usage: _output_elapsed_ms "$start_ns" "$end_ns"
_output_elapsed_ms() {
    local start_ns="$1"
    local end_ns="$2"

    # Use bash arithmetic for integer subtraction
    # Both values are nanoseconds as integers
    local diff_ns=$(( end_ns - start_ns ))
    local ms=$(( diff_ns / 1000000 ))

    # If sub-millisecond, report 0 (not negative)
    [[ $ms -lt 0 ]] && ms=0
    printf '%s' "$ms"
}

# =============================================================================
# TIMER FUNCTIONS
# =============================================================================

# Start a timer, storing the start time in a global variable.
# Usage: output_timer_start [timer_name]
# The timer name defaults to "_default". Multiple named timers are supported.
output_timer_start() {
    local name="${1:-_default}"
    local varname="_MAINFRAME_TIMER_${name//[^a-zA-Z0-9_]/_}"

    # Store start nanoseconds using printf -v to avoid subshell
    local now_ns
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        local epoch_real="$EPOCHREALTIME"
        local secs="${epoch_real%%.*}"
        local frac="${epoch_real#*.}"
        while [[ ${#frac} -lt 9 ]]; do
            frac="${frac}0"
        done
        frac="${frac:0:9}"
        now_ns="${secs}${frac}"
    else
        now_ns=$(_output_now_ns)
    fi

    printf -v "$varname" '%s' "$now_ns"
}

# Get elapsed milliseconds since output_timer_start was called.
# Usage: output_timer_elapsed [timer_name]
# Prints the elapsed time in milliseconds to stdout.
output_timer_elapsed() {
    local name="${1:-_default}"
    local varname="_MAINFRAME_TIMER_${name//[^a-zA-Z0-9_]/_}"
    local start_ns="${!varname:-}"

    if [[ -z "$start_ns" ]]; then
        printf '0'
        return 1
    fi

    local end_ns
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        local epoch_real="$EPOCHREALTIME"
        local secs="${epoch_real%%.*}"
        local frac="${epoch_real#*.}"
        while [[ ${#frac} -lt 9 ]]; do
            frac="${frac}0"
        done
        frac="${frac:0:9}"
        end_ns="${secs}${frac}"
    else
        end_ns=$(_output_now_ns)
    fi

    _output_elapsed_ms "$start_ns" "$end_ns"
}

# =============================================================================
# JSON ENVELOPE GENERATORS (INTERNAL)
# =============================================================================

# Generate a success JSON envelope.
# Usage: _output_json <data> [elapsed_ms] [hint]
# data: the JSON-encoded value (string, number, object, array, etc.)
# elapsed_ms: timing in milliseconds (default 0)
# hint: optional next-function suggestion
_output_json() {
    local data="$1"
    local elapsed_ms="${2:-0}"
    local hint="${3:-${MAINFRAME_OUTPUT_HINT:-}}"

    local result
    result="{\"ok\":true,\"data\":${data},\"meta\":{\"elapsed_ms\":${elapsed_ms}}"

    if [[ -n "$hint" ]]; then
        local escaped_hint
        escaped_hint=$(_output_escape "$hint")
        result+=",\"hint\":\"${escaped_hint}\""
    fi

    result+="}"
    printf '%s\n' "$result"

    # Reset hint after consumption
    MAINFRAME_OUTPUT_HINT=""
}

# Generate an error JSON envelope.
# Usage: _error_json <code> <message> [suggestion] [elapsed_ms] [context_json]
# code: error code string (e.g., "E_NOT_FOUND")
# message: human-readable error message
# suggestion: actionable suggestion for recovery
# elapsed_ms: timing in milliseconds
# context_json: optional JSON object with additional context (must be valid JSON)
_error_json() {
    local code="${1:-E_UNKNOWN}"
    local msg="${2:-unknown error}"
    local suggestion="${3:-}"
    local elapsed_ms="${4:-0}"
    local context_json="${5:-}"

    local escaped_code escaped_msg escaped_suggestion
    escaped_code=$(_output_escape "$code")
    escaped_msg=$(_output_escape "$msg")

    local result
    result="{\"ok\":false,\"error\":{\"code\":\"${escaped_code}\",\"msg\":\"${escaped_msg}\""

    if [[ -n "$suggestion" ]]; then
        escaped_suggestion=$(_output_escape "$suggestion")
        result+=",\"suggestion\":\"${escaped_suggestion}\""
    fi

    if [[ -n "$context_json" ]]; then
        result+=",\"context\":${context_json}"
    fi

    result+="},\"meta\":{\"elapsed_ms\":${elapsed_ms}}}"
    printf '%s\n' "$result"
}

# =============================================================================
# TYPE FORMATTERS (INTERNAL)
# =============================================================================

# Format a value according to its declared type for JSON output.
# Usage: _output_type_format <type> <value>
# Supported types: string, int, bool, float, json_object, json_array,
#                  file_path, void, stream
_output_type_format() {
    local type="$1"
    local value="$2"

    case "$type" in
        string)
            local escaped
            escaped=$(_output_escape "$value")
            printf '"%s"' "$escaped"
            ;;
        int)
            # Validate integer, fallback to null
            if [[ "$value" =~ ^-?[0-9]+$ ]]; then
                printf '%s' "$value"
            else
                printf 'null'
                return 1
            fi
            ;;
        float)
            # Validate numeric (int or float), fallback to null
            if [[ "$value" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]; then
                printf '%s' "$value"
            else
                printf 'null'
                return 1
            fi
            ;;
        bool)
            case "${value,,}" in
                true|1|yes|on)  printf 'true' ;;
                false|0|no|off) printf 'false' ;;
                *) printf 'null'; return 1 ;;
            esac
            ;;
        json_object|json_array)
            # Pass through raw JSON (caller must ensure validity)
            printf '%s' "$value"
            ;;
        file_path)
            # Wrap file path as a string with path metadata
            local escaped
            escaped=$(_output_escape "$value")
            printf '{"path":"%s","exists":%s}' \
                "$escaped" \
                "$( [[ -e "$value" ]] && printf 'true' || printf 'false' )"
            ;;
        void)
            printf 'null'
            ;;
        stream)
            # Stream type: collect lines into a JSON array of strings
            local result="["
            local first=true
            local line
            while IFS= read -r line; do
                $first || result+=","
                first=false
                local escaped_line
                escaped_line=$(_output_escape "$line")
                result+="\"${escaped_line}\""
            done <<< "$value"
            result+="]"
            printf '%s' "$result"
            ;;
        *)
            # Unknown type: treat as string
            local escaped
            escaped=$(_output_escape "$value")
            printf '"%s"' "$escaped"
            ;;
    esac
}

# =============================================================================
# PUBLIC OUTPUT FUNCTIONS
# =============================================================================

# Main output wrapper.
# Formats output based on MAINFRAME_OUTPUT mode.
#
# Usage: output [options] <value>
#   -t <type>    Value type: string, int, bool, float, json_object, json_array,
#                file_path, void, stream (default: string)
#   -h <hint>    Hint for next function to call
#   -T <timer>   Timer name to read elapsed_ms from (default: _default)
#   -n           No trailing newline in raw mode
#
# Examples:
#   output "hello world"
#   output -t int "42"
#   output -t json_object '{"name":"John","age":30}'
#   output -t bool "true" -h "check_permissions"
#   output -t void
output() {
    local type="string"
    local hint=""
    local timer="_default"
    local no_newline=false
    local value=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t) type="$2"; shift 2 ;;
            -h) hint="$2"; shift 2 ;;
            -T) timer="$2"; shift 2 ;;
            -n) no_newline=true; shift ;;
            --)  shift; value="$*"; break ;;
            *)   value="$*"; break ;;
        esac
    done

    # Set hint if provided via option
    [[ -n "$hint" ]] && MAINFRAME_OUTPUT_HINT="$hint"

    case "$MAINFRAME_OUTPUT" in
        raw)
            # Raw mode: near-zero overhead, just printf
            if [[ "$type" == "void" ]]; then
                return 0
            fi
            if $no_newline; then
                printf '%s' "$value"
            else
                printf '%s\n' "$value"
            fi
            ;;

        minimal)
            # Minimal mode: value only, no envelope, no metadata
            if [[ "$type" == "void" ]]; then
                return 0
            fi
            printf '%s\n' "$value"
            ;;

        json)
            # JSON mode: wrap in structured envelope
            local elapsed_ms=0
            local varname="_MAINFRAME_TIMER_${timer//[^a-zA-Z0-9_]/_}"
            if [[ -n "${!varname:-}" ]]; then
                elapsed_ms=$(output_timer_elapsed "$timer")
            fi

            local formatted_data
            formatted_data=$(_output_type_format "$type" "$value")

            _output_json "$formatted_data" "$elapsed_ms"
            ;;

        debug)
            # Debug mode: human-readable with metadata
            local elapsed_ms=0
            local varname="_MAINFRAME_TIMER_${timer//[^a-zA-Z0-9_]/_}"
            if [[ -n "${!varname:-}" ]]; then
                elapsed_ms=$(output_timer_elapsed "$timer")
            fi

            local caller_func="${FUNCNAME[1]:-main}"
            local caller_file="${BASH_SOURCE[1]:-unknown}"
            local caller_line="${BASH_LINENO[0]:-0}"

            printf '[DEBUG] %s:%s:%d | type=%s elapsed=%dms' \
                "$caller_file" "$caller_func" "$caller_line" "$type" "$elapsed_ms" >&2
            if [[ -n "${MAINFRAME_OUTPUT_HINT:-}" ]]; then
                printf ' hint=%s' "$MAINFRAME_OUTPUT_HINT" >&2
            fi
            printf '\n' >&2

            if [[ "$type" == "void" ]]; then
                printf '(void)\n' >&2
            else
                printf '%s\n' "$value"
            fi
            ;;

        *)
            # Unknown mode: fall back to raw
            if [[ "$type" != "void" ]]; then
                printf '%s\n' "$value"
            fi
            ;;
    esac

    return 0
}

# Output an error with structured envelope.
# In raw/minimal mode: prints error to stderr.
# In json mode: emits error JSON envelope to stdout.
# In debug mode: prints detailed error to stderr.
#
# Usage: output_error [options] <code> <message>
#   -s <suggestion>   Recovery suggestion
#   -c <context_json> Additional context (valid JSON object)
#   -T <timer>        Timer name to read elapsed_ms from
#
# Examples:
#   output_error "E_NOT_FOUND" "File not found: /tmp/foo.txt"
#   output_error -s "Check the path exists" "E_NOT_FOUND" "File missing"
#   output_error -c '{"path":"/tmp/foo.txt"}' "E_NOT_FOUND" "File missing"
output_error() {
    local suggestion=""
    local context_json=""
    local timer="_default"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s) suggestion="$2"; shift 2 ;;
            -c) context_json="$2"; shift 2 ;;
            -T) timer="$2"; shift 2 ;;
            --) shift; break ;;
            *)  break ;;
        esac
    done

    local code="${1:-E_UNKNOWN}"
    local msg="${2:-unknown error}"

    case "$MAINFRAME_OUTPUT" in
        raw)
            # Raw mode: simple error to stderr
            printf 'error: [%s] %s\n' "$code" "$msg" >&2
            if [[ -n "$suggestion" ]]; then
                printf '  suggestion: %s\n' "$suggestion" >&2
            fi
            ;;

        minimal)
            # Minimal mode: terse error to stderr
            printf '%s: %s\n' "$code" "$msg" >&2
            ;;

        json)
            # JSON mode: structured error envelope to stdout
            local elapsed_ms=0
            local varname="_MAINFRAME_TIMER_${timer//[^a-zA-Z0-9_]/_}"
            if [[ -n "${!varname:-}" ]]; then
                elapsed_ms=$(output_timer_elapsed "$timer")
            fi

            _error_json "$code" "$msg" "$suggestion" "$elapsed_ms" "$context_json"
            ;;

        debug)
            # Debug mode: verbose error to stderr
            local caller_func="${FUNCNAME[1]:-main}"
            local caller_file="${BASH_SOURCE[1]:-unknown}"
            local caller_line="${BASH_LINENO[0]:-0}"

            local elapsed_ms=0
            local varname="_MAINFRAME_TIMER_${timer//[^a-zA-Z0-9_]/_}"
            if [[ -n "${!varname:-}" ]]; then
                elapsed_ms=$(output_timer_elapsed "$timer")
            fi

            printf '[ERROR] %s:%s:%d | code=%s elapsed=%dms\n' \
                "$caller_file" "$caller_func" "$caller_line" "$code" "$elapsed_ms" >&2
            printf '  message: %s\n' "$msg" >&2
            if [[ -n "$suggestion" ]]; then
                printf '  suggestion: %s\n' "$suggestion" >&2
            fi
            if [[ -n "$context_json" ]]; then
                printf '  context: %s\n' "$context_json" >&2
            fi
            ;;

        *)
            printf 'error: [%s] %s\n' "$code" "$msg" >&2
            ;;
    esac

    return 1
}

# =============================================================================
# CONVENIENCE WRAPPERS
# =============================================================================

# Output a string value.
# Usage: output_string "hello world"
output_string() {
    output -t string "$@"
}

# Output an integer value.
# Usage: output_int 42
output_int() {
    output -t int "$@"
}

# Output a boolean value.
# Usage: output_bool true
output_bool() {
    output -t bool "$@"
}

# Output a float value.
# Usage: output_float 3.14
output_float() {
    output -t float "$@"
}

# Output a JSON object (pass-through).
# Usage: output_json_object '{"name":"John"}'
output_json_object() {
    output -t json_object "$@"
}

# Output a JSON array (pass-through).
# Usage: output_json_array '["a","b","c"]'
output_json_array() {
    output -t json_array "$@"
}

# Output a file path with existence check.
# Usage: output_file_path "/tmp/result.txt"
output_file_path() {
    output -t file_path "$@"
}

# Output void (no data, just timing/hint in json mode).
# Usage: output_void
output_void() {
    output -t void ""
}

# =============================================================================
# NAMEREF VARIANTS (High-Performance, No Subshell)
# =============================================================================

# Format output into a variable instead of printing.
# Usage: output_v result_var [options] <value>
# Same options as output(), but stores result in the named variable.
output_v() {
    local -n __ov_out=$1
    shift

    local type="string"
    local hint=""
    local timer="_default"
    local value=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t) type="$2"; shift 2 ;;
            -h) hint="$2"; shift 2 ;;
            -T) timer="$2"; shift 2 ;;
            -n) shift ;; # no-op for variable output
            --) shift; value="$*"; break ;;
            *)  value="$*"; break ;;
        esac
    done

    [[ -n "$hint" ]] && MAINFRAME_OUTPUT_HINT="$hint"

    case "$MAINFRAME_OUTPUT" in
        raw|minimal)
            if [[ "$type" == "void" ]]; then
                __ov_out=""
            else
                __ov_out="$value"
            fi
            ;;

        json)
            local elapsed_ms=0
            local varname="_MAINFRAME_TIMER_${timer//[^a-zA-Z0-9_]/_}"
            if [[ -n "${!varname:-}" ]]; then
                elapsed_ms=$(output_timer_elapsed "$timer")
            fi

            local formatted_data
            formatted_data=$(_output_type_format "$type" "$value")

            local hint_part=""
            if [[ -n "${MAINFRAME_OUTPUT_HINT:-}" ]]; then
                local escaped_hint
                escaped_hint=$(_output_escape "$MAINFRAME_OUTPUT_HINT")
                hint_part=",\"hint\":\"${escaped_hint}\""
            fi

            __ov_out="{\"ok\":true,\"data\":${formatted_data},\"meta\":{\"elapsed_ms\":${elapsed_ms}}${hint_part}}"
            MAINFRAME_OUTPUT_HINT=""
            ;;

        debug|*)
            if [[ "$type" == "void" ]]; then
                __ov_out=""
            else
                __ov_out="$value"
            fi
            ;;
    esac
}

# =============================================================================
# OUTPUT MODE UTILITIES
# =============================================================================

# Check if current output mode is JSON.
# Usage: output_is_json && echo "json mode"
output_is_json() {
    [[ "$MAINFRAME_OUTPUT" == "json" ]]
}

# Check if current output mode is raw.
# Usage: output_is_raw && echo "raw mode"
output_is_raw() {
    [[ "$MAINFRAME_OUTPUT" == "raw" ]]
}

# Check if current output mode is debug.
# Usage: output_is_debug && echo "debug mode"
output_is_debug() {
    [[ "$MAINFRAME_OUTPUT" == "debug" ]]
}

# Check if current output mode is minimal.
# Usage: output_is_minimal && echo "minimal mode"
output_is_minimal() {
    [[ "$MAINFRAME_OUTPUT" == "minimal" ]]
}

# Temporarily set output mode, run a command, restore.
# Usage: output_with_mode json my_function arg1 arg2
output_with_mode() {
    local mode="$1"
    shift
    local saved_mode="$MAINFRAME_OUTPUT"
    MAINFRAME_OUTPUT="$mode"
    "$@"
    local rc=$?
    MAINFRAME_OUTPUT="$saved_mode"
    return $rc
}

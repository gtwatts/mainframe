#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/output.sh - Universal Structured Output Protocol (USOP)
# =============================================================================
# Description: Enables all MAINFRAME functions to output structured JSON
#              envelopes instead of raw text, making the toolkit machine-readable
#              for AI coding agents. Provides mode detection, envelope functions,
#              timing helpers, and the output_wrap meta-wrapper.
#
# Modes:
#   raw     - Plain text output (default, backward compatible)
#   json    - Full JSON envelope with ok, data, meta, hint
#   minimal - Compact JSON envelope (ok, data only)
#   debug   - JSON envelope with extra debugging info (timestamp, caller)
#
# Version: 2.0.0
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

# Valid output modes
readonly _OUTPUT_MODES="raw json minimal debug"

# Environment variable to control output mode globally
# Set MAINFRAME_OUTPUT=json to activate structured output
MAINFRAME_OUTPUT="${MAINFRAME_OUTPUT:-raw}"

# Timer state (global to support timing across calls)
_MAINFRAME_OUTPUT_START_MS=""

# =============================================================================
# OUTPUT MODE MANAGEMENT
# =============================================================================

# Initialize output system
# Sets default mode if not already set via environment
# Usage: output_init
output_init() {
    MAINFRAME_OUTPUT="${MAINFRAME_OUTPUT:-raw}"
    return 0
}

# Get or set output mode
# Without args: returns current mode
# With arg: sets mode if valid, returns 1 if invalid
# Usage: output_mode              # Get mode
# Usage: output_mode "json"       # Set mode
output_mode() {
    if [[ $# -eq 0 ]]; then
        printf '%s' "${MAINFRAME_OUTPUT:-raw}"
        return 0
    fi

    local new_mode="$1"
    case " $_OUTPUT_MODES " in
        *" $new_mode "*)
            MAINFRAME_OUTPUT="$new_mode"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# MODE CHECK FUNCTIONS
# =============================================================================

# Check if JSON output mode is active
# Returns 0 if MAINFRAME_OUTPUT=json
# Usage: output_is_json && echo "JSON mode active"
output_is_json() {
    [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]
}

# Check if raw output mode is active
# Returns 0 if MAINFRAME_OUTPUT=raw or unset
# Usage: output_is_raw && echo "Raw mode active"
output_is_raw() {
    [[ "${MAINFRAME_OUTPUT:-raw}" == "raw" ]]
}

# Check if minimal output mode is active
# Returns 0 if MAINFRAME_OUTPUT=minimal
# Usage: output_is_minimal && echo "Minimal mode active"
output_is_minimal() {
    [[ "${MAINFRAME_OUTPUT:-raw}" == "minimal" ]]
}

# Check if debug output mode is active
# Returns 0 if MAINFRAME_OUTPUT=debug
# Usage: output_is_debug && echo "Debug mode active"
output_is_debug() {
    [[ "${MAINFRAME_OUTPUT:-raw}" == "debug" ]]
}

# Returns the current output format (backward compat alias)
# Usage: fmt=$(output_format)
output_format() {
    printf '%s' "${MAINFRAME_OUTPUT:-raw}"
}

# =============================================================================
# TIMING FUNCTIONS
# =============================================================================

# Get current time in milliseconds for duration measurement
# Uses EPOCHREALTIME (Bash 5.0+), GNU date %s%N, or EPOCHSECONDS fallback
_output_now_ms() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        # Bash 5.0+ has EPOCHREALTIME (seconds.microseconds)
        local epoch_real="$EPOCHREALTIME"
        local seconds="${epoch_real%%.*}"
        local frac="${epoch_real#*.}"
        # Pad fractional part to at least 3 digits for ms precision
        frac="${frac}000"
        printf '%s%s' "$seconds" "${frac:0:3}"
    else
        # Try GNU date with nanoseconds
        local ns
        ns=$(date +%s%N 2>/dev/null)
        if [[ "$ns" =~ ^[0-9]+$ && ${#ns} -gt 6 ]]; then
            # Trim nanoseconds to milliseconds (remove last 6 digits)
            printf '%s' "${ns:0:${#ns}-6}"
        else
            # Last resort: seconds * 1000
            printf '%s000' "${EPOCHSECONDS:-$(date +%s)}"
        fi
    fi
}

# Start timing for output operations
# Usage: output_timer_start
output_timer_start() {
    _MAINFRAME_OUTPUT_START_MS=$(_output_now_ms)
}

# Get elapsed time since timer_start in milliseconds
# Returns 0 if timer was not started
# Usage: elapsed=$(output_timer_elapsed)
output_timer_elapsed() {
    if [[ -z "${_MAINFRAME_OUTPUT_START_MS:-}" ]]; then
        printf '0'
        return 0
    fi

    local end_ms elapsed
    end_ms=$(_output_now_ms)
    elapsed=$((end_ms - _MAINFRAME_OUTPUT_START_MS))

    # Guard against negative duration (clock skew / fallback timer issues)
    if [[ $elapsed -lt 0 ]]; then
        elapsed=0
    fi

    printf '%d' "$elapsed"
}

# =============================================================================
# JSON ESCAPE HELPER
# =============================================================================

# Escape a string for safe JSON embedding
# Handles: quotes, backslashes, newlines, tabs, carriage returns,
#          backspace, form feed, and all control characters (< 0x20)
# Usage: escaped=$(_output_escape "hello \"world\"")
_output_escape() {
    local str="$1"
    local result=""
    local i char

    for ((i=0; i<${#str}; i++)); do
        char="${str:i:1}"
        case "$char" in
            \\)    result+='\\\\' ;;
            '"')   result+='\\\"' ;;
            $'\b') result+='\\b' ;;
            $'\f') result+='\\f' ;;
            $'\n') result+='\\n' ;;
            $'\r') result+='\\r' ;;
            $'\t') result+='\\t' ;;
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

# Nameref variant for performance (avoids subshell)
# Usage: _output_escape_v result_var "hello \"world\""
_output_escape_v() {
    local -n __oev_out=$1
    local str="$2"
    local i char

    __oev_out=""
    for ((i=0; i<${#str}; i++)); do
        char="${str:i:1}"
        case "$char" in
            \\)    __oev_out+='\\\\' ;;
            '"')   __oev_out+='\\\"' ;;
            $'\b') __oev_out+='\\b' ;;
            $'\f') __oev_out+='\\f' ;;
            $'\n') __oev_out+='\\n' ;;
            $'\r') __oev_out+='\\r' ;;
            $'\t') __oev_out+='\\t' ;;
            *)
                # Check for control characters (< 0x20)
                if [[ "$char" < $'\x20' ]]; then
                    printf -v char '\\u%04x' "'$char"
                fi
                __oev_out+="$char"
                ;;
        esac
    done
}

# Public alias for backward compatibility
output_json_escape() {
    _output_escape "$@"
}

# =============================================================================
# CORE ENVELOPE FUNCTIONS - USOP FORMAT
# =============================================================================

# Build meta object based on mode and timer state
# Usage: meta=$(_output_build_meta)
_output_build_meta() {
    local mode="${MAINFRAME_OUTPUT:-raw}"
    local meta=""

    # Check if timer was started
    if [[ -n "${_MAINFRAME_OUTPUT_START_MS:-}" ]]; then
        local elapsed
        elapsed=$(output_timer_elapsed)
        meta="\"elapsed_ms\":$elapsed"
    fi

    # Debug mode adds extra info
    if [[ "$mode" == "debug" ]]; then
        local timestamp caller_info
        timestamp=$(_output_now_ms)

        # Get caller function name (skip internal frames)
        local frame=1
        local line func file
        while caller $frame 2>/dev/null | read -r line func file; do
            if [[ "$func" != _output_* && "$func" != output_* ]]; then
                caller_info="$func"
                break
            fi
            ((frame++))
        done

        [[ -n "$meta" ]] && meta+=","
        meta+="\"timestamp\":$timestamp"
        if [[ -n "${caller_info:-}" ]]; then
            meta+=",\"caller\":\"$caller_info\""
        fi
    fi

    printf '%s' "$meta"
}

# Emit a success envelope
# Format depends on MAINFRAME_OUTPUT mode:
#   raw:     plain data
#   json:    {"ok":true,"data":"...","meta":{...},"hint":"..."}
#   minimal: {"ok":true,"data":"..."}
#   debug:   json + timestamp + caller
#
# Usage: output_success "result_data" ["hint"]
output_success() {
    local data="$1"
    local hint="${2:-}"
    local mode="${MAINFRAME_OUTPUT:-raw}"

    case "$mode" in
        raw)
            printf '%s' "$data"
            ;;
        minimal)
            printf '{"ok":true,"data":"%s"}' "$(_output_escape "$data")"
            ;;
        json|debug)
            local escaped_data meta
            escaped_data=$(_output_escape "$data")
            meta=$(_output_build_meta)

            printf '{"ok":true,"data":"%s"' "$escaped_data"

            if [[ -n "$meta" ]]; then
                printf ',"meta":{%s}' "$meta"
            fi

            if [[ -n "$hint" ]]; then
                printf ',"hint":"%s"' "$(_output_escape "$hint")"
            fi

            printf '}'
            ;;
    esac
}

# Emit an error envelope
# Format depends on MAINFRAME_OUTPUT mode:
#   raw:     plain message to stderr
#   json:    {"ok":false,"error":{"code":"...","msg":"...","suggestion":"..."}}
#   minimal: {"ok":false,"error":{"code":"...","msg":"..."}}
#   debug:   json + timestamp + caller
#
# Usage: output_error "code" "message" ["suggestion"]
output_error() {
    local code="$1"
    local msg="$2"
    local suggestion="${3:-}"
    local mode="${MAINFRAME_OUTPUT:-raw}"

    case "$mode" in
        raw)
            printf '%s\n' "$msg" >&2
            ;;
        minimal)
            printf '{"ok":false,"error":{"code":"%s","msg":"%s"}}' \
                "$(_output_escape "$code")" \
                "$(_output_escape "$msg")"
            ;;
        json|debug)
            local meta
            meta=$(_output_build_meta)

            printf '{"ok":false,"error":{"code":"%s","msg":"%s"' \
                "$(_output_escape "$code")" \
                "$(_output_escape "$msg")"

            if [[ -n "$suggestion" ]]; then
                printf ',"suggestion":"%s"' "$(_output_escape "$suggestion")"
            fi

            printf '}'

            if [[ -n "$meta" ]]; then
                printf ',"meta":{%s}' "$meta"
            fi

            printf '}'
            ;;
    esac
}

# =============================================================================
# RAW OUTPUT (MODE-INDEPENDENT)
# =============================================================================

# Emit raw text regardless of output mode
# Always bypasses envelope formatting
# Usage: output_raw "plain text"
output_raw() {
    printf '%s' "$1"
}

# Emit JSON string unchanged regardless of output mode
# Useful for custom JSON that shouldn't be wrapped
# Usage: output_json '{"custom":"data"}'
output_json() {
    printf '%s' "$1"
}

# =============================================================================
# TYPE-SPECIFIC OUTPUT HELPERS
# =============================================================================

# Emit string data
# Usage: output_string "hello"
output_string() {
    local data="$1"
    local hint="${2:-}"
    local mode="${MAINFRAME_OUTPUT:-raw}"

    case "$mode" in
        raw)
            printf '%s' "$data"
            ;;
        *)
            output_success "$data" "$hint"
            ;;
    esac
}

# Emit integer data
# Usage: output_int 42
output_int() {
    local data="$1"
    local hint="${2:-}"
    local mode="${MAINFRAME_OUTPUT:-raw}"

    case "$mode" in
        raw)
            printf '%s' "$data"
            ;;
        minimal)
            printf '{"ok":true,"data":%d}' "$data"
            ;;
        json|debug)
            local meta
            meta=$(_output_build_meta)
            printf '{"ok":true,"data":%d' "$data"
            if [[ -n "$meta" ]]; then
                printf ',"meta":{%s}' "$meta"
            fi
            if [[ -n "$hint" ]]; then
                printf ',"hint":"%s"' "$(_output_escape "$hint")"
            fi
            printf '}'
            ;;
    esac
}

# Emit float data
# Usage: output_float 3.14
output_float() {
    local data="$1"
    local hint="${2:-}"
    local mode="${MAINFRAME_OUTPUT:-raw}"

    case "$mode" in
        raw)
            printf '%s' "$data"
            ;;
        minimal)
            printf '{"ok":true,"data":%s}' "$data"
            ;;
        json|debug)
            local meta
            meta=$(_output_build_meta)
            printf '{"ok":true,"data":%s' "$data"
            if [[ -n "$meta" ]]; then
                printf ',"meta":{%s}' "$meta"
            fi
            if [[ -n "$hint" ]]; then
                printf ',"hint":"%s"' "$(_output_escape "$hint")"
            fi
            printf '}'
            ;;
    esac
}

# Emit boolean data
# Usage: output_bool true
output_bool() {
    local data="$1"
    local hint="${2:-}"
    local mode="${MAINFRAME_OUTPUT:-raw}"
    local bool_val

    # Normalize to true/false
    case "${data,,}" in
        true|1|yes|on) bool_val="true" ;;
        *)             bool_val="false" ;;
    esac

    case "$mode" in
        raw)
            printf '%s' "$bool_val"
            ;;
        minimal)
            printf '{"ok":true,"data":%s}' "$bool_val"
            ;;
        json|debug)
            local meta
            meta=$(_output_build_meta)
            printf '{"ok":true,"data":%s' "$bool_val"
            if [[ -n "$meta" ]]; then
                printf ',"meta":{%s}' "$meta"
            fi
            if [[ -n "$hint" ]]; then
                printf ',"hint":"%s"' "$(_output_escape "$hint")"
            fi
            printf '}'
            ;;
    esac
}

# Emit JSON object data (already formatted JSON)
# Usage: output_json_object '{"key":"value"}'
output_json_object() {
    local data="$1"
    local hint="${2:-}"
    local mode="${MAINFRAME_OUTPUT:-raw}"

    case "$mode" in
        raw)
            printf '%s' "$data"
            ;;
        minimal)
            printf '{"ok":true,"data":%s}' "$data"
            ;;
        json|debug)
            local meta
            meta=$(_output_build_meta)
            printf '{"ok":true,"data":%s' "$data"
            if [[ -n "$meta" ]]; then
                printf ',"meta":{%s}' "$meta"
            fi
            if [[ -n "$hint" ]]; then
                printf ',"hint":"%s"' "$(_output_escape "$hint")"
            fi
            printf '}'
            ;;
    esac
}

# Emit JSON array data (already formatted JSON)
# Usage: output_json_array '["a","b","c"]'
output_json_array() {
    local data="$1"
    local hint="${2:-}"
    local mode="${MAINFRAME_OUTPUT:-raw}"

    case "$mode" in
        raw)
            printf '%s' "$data"
            ;;
        minimal)
            printf '{"ok":true,"data":%s}' "$data"
            ;;
        json|debug)
            local meta
            meta=$(_output_build_meta)
            printf '{"ok":true,"data":%s' "$data"
            if [[ -n "$meta" ]]; then
                printf ',"meta":{%s}' "$meta"
            fi
            if [[ -n "$hint" ]]; then
                printf ',"hint":"%s"' "$(_output_escape "$hint")"
            fi
            printf '}'
            ;;
    esac
}

# Emit file path data
# Usage: output_file_path "/tmp/test.txt"
output_file_path() {
    output_string "$@"
}

# Emit void/null data
# Usage: output_void
output_void() {
    local hint="${1:-}"
    local mode="${MAINFRAME_OUTPUT:-raw}"

    case "$mode" in
        raw)
            # No output for void in raw mode
            ;;
        minimal)
            printf '{"ok":true,"data":null}'
            ;;
        json|debug)
            local meta
            meta=$(_output_build_meta)
            printf '{"ok":true,"data":null'
            if [[ -n "$meta" ]]; then
                printf ',"meta":{%s}' "$meta"
            fi
            if [[ -n "$hint" ]]; then
                printf ',"hint":"%s"' "$(_output_escape "$hint")"
            fi
            printf '}'
            ;;
    esac
}

# =============================================================================
# NAMEREF VARIANT (HIGH PERFORMANCE)
# =============================================================================

# Store output in variable (avoids subshell)
# Usage: output_v result_var "data" ["hint"]
output_v() {
    local -n __ov_out=$1
    local data="$2"
    local hint="${3:-}"
    local mode="${MAINFRAME_OUTPUT:-raw}"
    local __ov_escaped meta

    case "$mode" in
        raw)
            __ov_out="$data"
            ;;
        minimal)
            _output_escape_v __ov_escaped "$data"
            __ov_out="{\"ok\":true,\"data\":\"${__ov_escaped}\"}"
            ;;
        json|debug)
            _output_escape_v __ov_escaped "$data"
            meta=$(_output_build_meta)

            __ov_out="{\"ok\":true,\"data\":\"${__ov_escaped}\""

            if [[ -n "$meta" ]]; then
                __ov_out+=",\"meta\":{${meta}}"
            fi

            if [[ -n "$hint" ]]; then
                local __ov_hint_escaped
                _output_escape_v __ov_hint_escaped "$hint"
                __ov_out+=",\"hint\":\"${__ov_hint_escaped}\""
            fi

            __ov_out+="}"
            ;;
    esac
}

# =============================================================================
# OUTPUT WRAPPING
# =============================================================================

# Wrap any function call with automatic USOP envelope
# Captures stdout, exit code, and timing
#
# Usage: output_wrap function_name [args...]
output_wrap() {
    local func_name="$1"
    shift
    local mode="${MAINFRAME_OUTPUT:-raw}"

    # Start timing
    local start_ms end_ms duration_ms
    start_ms=$(_output_now_ms)

    # Execute function, capturing output
    local func_output func_exit_code
    func_output=$("$func_name" "$@" 2>&1)
    func_exit_code=$?

    # Calculate duration
    end_ms=$(_output_now_ms)
    duration_ms=$((end_ms - start_ms))
    [[ $duration_ms -lt 0 ]] && duration_ms=0

    case "$mode" in
        raw)
            printf '%s' "$func_output"
            return $func_exit_code
            ;;
        minimal)
            if [[ $func_exit_code -eq 0 ]]; then
                printf '{"ok":true,"data":"%s"}' "$(_output_escape "$func_output")"
            else
                printf '{"ok":false,"error":{"code":"E_FUNC_FAILED","msg":"%s"}}' \
                    "$(_output_escape "$func_output")"
            fi
            return $func_exit_code
            ;;
        json|debug)
            local escaped_output meta
            escaped_output=$(_output_escape "$func_output")

            # Build meta with elapsed time
            meta="\"elapsed_ms\":$duration_ms"
            if [[ "$mode" == "debug" ]]; then
                meta+=",\"timestamp\":$start_ms,\"function\":\"$func_name\""
            fi

            if [[ $func_exit_code -eq 0 ]]; then
                printf '{"ok":true,"data":"%s","meta":{%s}}' "$escaped_output" "$meta"
            else
                printf '{"ok":false,"error":{"code":"E_FUNC_FAILED","msg":"%s"},"meta":{%s}}' \
                    "$escaped_output" "$meta"
            fi
            return $func_exit_code
            ;;
    esac
}

# =============================================================================
# TEMPORARY MODE CHANGE
# =============================================================================

# Execute command with temporary output mode
# Restores original mode after execution
#
# Usage: output_with_mode "json" output_success "data"
output_with_mode() {
    local temp_mode="$1"
    shift
    local original_mode="${MAINFRAME_OUTPUT:-raw}"

    MAINFRAME_OUTPUT="$temp_mode"
    "$@"
    local exit_code=$?
    MAINFRAME_OUTPUT="$original_mode"

    return $exit_code
}

# =============================================================================
# BACKWARD COMPATIBILITY - Legacy Functions
# =============================================================================

# Legacy output_success (old format)
# Kept for backward compatibility with existing code
# Usage: output_success_legacy "data" ["message"]
output_success_legacy() {
    local data="$1"
    local message="${2:-}"

    printf '{"status":"success","data":"%s"' "$(_output_escape "$data")"
    if [[ -n "$message" ]]; then
        printf ',"message":"%s"' "$(_output_escape "$message")"
    fi
    printf '}\n'
}

# Legacy output_error (old format)
# Usage: output_error_legacy "message" [exit_code] ["context"]
output_error_legacy() {
    local error_msg="$1"
    local exit_code="${2:-1}"
    local context="${3:-}"

    printf '{"status":"error","error":"%s","code":%d' "$(_output_escape "$error_msg")" "$exit_code"
    if [[ -n "$context" ]]; then
        printf ',"context":"%s"' "$(_output_escape "$context")"
    fi
    printf '}\n'
}

# Emit a JSON key-value pair with string value
# Usage: output_json_string "key" "value"
# Output: "key":"value"
output_json_string_kv() {
    local key="$1"
    local value="$2"
    printf '"%s":"%s"' "$(_output_escape "$key")" "$(_output_escape "$value")"
}

# Emit a JSON key-value pair with number value
# Usage: output_json_number "key" 42
# Output: "key":42
output_json_number() {
    local key="$1"
    local value="$2"
    if [[ "$value" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]; then
        printf '"%s":%s' "$(_output_escape "$key")" "$value"
    else
        printf '"%s":null' "$(_output_escape "$key")"
        return 1
    fi
}

# Emit a JSON key-value pair with boolean value
# Usage: output_json_bool "key" true
# Output: "key":true
output_json_bool() {
    local key="$1"
    local value="$2"
    case "${value,,}" in
        true|1|yes|on)  printf '"%s":true' "$(_output_escape "$key")" ;;
        false|0|no|off) printf '"%s":false' "$(_output_escape "$key")" ;;
        *) printf '"%s":null' "$(_output_escape "$key")"; return 1 ;;
    esac
}

# Emit a JSON key-value pair with null value
# Usage: output_json_null "key"
# Output: "key":null
output_json_null() {
    local key="$1"
    printf '"%s":null' "$(_output_escape "$key")"
}

# Read stdin lines and output a JSON array of strings
# Usage: echo -e "line1\nline2" | output_json_array_from_lines
# Output: ["line1","line2"]
output_json_array_from_lines() {
    local first=true
    printf '['
    while IFS= read -r line || [[ -n "$line" ]]; do
        $first || printf ','
        first=false
        printf '"%s"' "$(_output_escape "$line")"
    done
    printf ']'
}

# Emit a list/array envelope (legacy format)
# Usage: output_list item1 item2 item3
# Output: {"status":"success","data":["item1","item2","item3"],"count":3}
output_list() {
    local count=$#
    local first=true

    printf '{"status":"success","data":['
    for item in "$@"; do
        $first || printf ','
        first=false
        printf '"%s"' "$(_output_escape "$item")"
    done
    printf '],"count":%d}\n' "$count"
}

# Emit a key-value object envelope (legacy format)
# Usage: output_object "key1=val1" "key2=val2" "key3:number=42"
output_object() {
    local first=true

    printf '{"status":"success","data":{'
    for pair in "$@"; do
        local key type value

        if [[ "$pair" =~ ^([^:=]+):([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            type="${BASH_REMATCH[2]}"
            value="${BASH_REMATCH[3]}"
        elif [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            type="string"
            value="${BASH_REMATCH[2]}"
        else
            continue
        fi

        $first || printf ','
        first=false

        printf '"%s":' "$(_output_escape "$key")"
        case "$type" in
            number)
                if [[ "$value" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]; then
                    printf '%s' "$value"
                else
                    printf 'null'
                fi
                ;;
            bool)
                case "${value,,}" in
                    true|1|yes|on)  printf 'true' ;;
                    false|0|no|off) printf 'false' ;;
                    *) printf 'null' ;;
                esac
                ;;
            null)   printf 'null' ;;
            raw)    printf '%s' "$value" ;;
            *)      printf '"%s"' "$(_output_escape "$value")" ;;
        esac
    done
    printf '}}\n'
}

# Emit a progress envelope for streaming/long operations
# Usage: output_progress "step_name" current total ["message"]
output_progress() {
    local step="$1"
    local current="$2"
    local total="$3"
    local message="${4:-}"

    printf '{"status":"progress","step":"%s","current":%d,"total":%d' \
        "$(_output_escape "$step")" "$current" "$total"
    if [[ -n "$message" ]]; then
        printf ',"message":"%s"' "$(_output_escape "$message")"
    fi
    printf '}\n'
}

# =============================================================================
# mainframe_call META-WRAPPER (Legacy)
# =============================================================================

# Invoke any MAINFRAME function with automatic USOP wrapping
# Captures stdout, stderr, exit code, and wraps in JSON envelope
#
# Usage: mainframe_call function_name [args...]
mainframe_call() {
    local func_name="$1"
    shift

    # Validate function exists
    if ! declare -F "$func_name" &>/dev/null; then
        printf '{"status":"error","function":"%s","error":"Function not found: %s","exit_code":127,"duration_ms":0}\n' \
            "$(_output_escape "$func_name")" \
            "$(_output_escape "$func_name")"
        return 127
    fi

    local start_ms end_ms duration_ms
    start_ms=$(_output_now_ms)

    # Create temporary files for capturing output
    local tmp_stdout tmp_stderr
    tmp_stdout=$(mktemp "${TMPDIR:-/tmp}/mainframe_call_out.XXXXXX")
    tmp_stderr=$(mktemp "${TMPDIR:-/tmp}/mainframe_call_err.XXXXXX")

    # Execute function, capturing stdout and stderr separately
    local func_exit_code
    "$func_name" "$@" >"$tmp_stdout" 2>"$tmp_stderr"
    func_exit_code=$?

    end_ms=$(_output_now_ms)
    duration_ms=$((end_ms - start_ms))

    # Guard against negative duration
    [[ $duration_ms -lt 0 ]] && duration_ms=0

    # Read captured output
    local stdout_content stderr_content
    stdout_content=$(<"$tmp_stdout")
    stderr_content=$(<"$tmp_stderr")

    # Clean up temp files
    rm -f "$tmp_stdout" "$tmp_stderr"

    # Determine status from exit code
    local status
    if [[ $func_exit_code -eq 0 ]]; then
        status="success"
    else
        status="error"
    fi

    # Build JSON envelope
    printf '{"status":"%s","function":"%s","data":"%s"' \
        "$status" \
        "$(_output_escape "$func_name")" \
        "$(_output_escape "$stdout_content")"

    if [[ -n "$stderr_content" ]]; then
        printf ',"stderr":"%s"' "$(_output_escape "$stderr_content")"
    fi

    printf ',"exit_code":%d,"duration_ms":%d}\n' "$func_exit_code" "$duration_ms"
    return $func_exit_code
}

# Auto-detect output mode and emit appropriate format (legacy)
# Usage: output_auto "plain text result" '{"status":"success","data":"value"}'
output_auto() {
    local text_output="$1"
    local json_data="$2"
    if output_is_json; then
        printf '%s\n' "$json_data"
    else
        printf '%s\n' "$text_output"
    fi
}

# =============================================================================
# STRUCTURED ERROR OBJECTS (Legacy)
# =============================================================================

# Create a rich error object with context for AI agent consumption
# Usage: output_structured_error CODE "message" ["suggestion"] ["context_key=val"...]
output_structured_error() {
    local code="${1:?error code required}"
    local message="${2:?error message required}"
    local suggestion="${3:-}"
    shift 3 2>/dev/null || shift $#

    local result
    result='{"status":"error"'
    result+=',"code":"'"$(_output_escape "$code")"'"'
    result+=',"message":"'"$(_output_escape "$message")"'"'

    if [[ -n "$suggestion" ]]; then
        result+=',"suggestion":"'"$(_output_escape "$suggestion")"'"'
    fi

    # Add stack trace (caller chain)
    local stack=""
    local frame=0
    while caller $frame 2>/dev/null | read -r line func file; do
        [[ -n "$stack" ]] && stack+="\\n"
        stack+="${file}:${line} ${func}"
        ((frame++))
    done
    if [[ -n "$stack" ]]; then
        result+=',"stack":"'"$stack"'"'
    fi

    # Add context key=value pairs
    if [[ $# -gt 0 ]]; then
        result+=',"context":{'
        local first=true
        local pair
        for pair in "$@"; do
            local key="${pair%%=*}"
            local val="${pair#*=}"
            $first || result+=','
            first=false
            result+='"'"$(_output_escape "$key")"'":"'"$(_output_escape "$val")"'"'
        done
        result+='}'
    fi

    result+='}'
    printf '%s\n' "$result"
    return 1
}

# Wrap a command and produce structured error on failure
# Usage: output_try command [args...]
output_try() {
    local cmd_str="$*"
    local stdout_file stderr_file
    stdout_file=$(mktemp) || return 2
    stderr_file=$(mktemp) || { rm -f "$stdout_file"; return 2; }

    local exit_code=0
    "$@" >"$stdout_file" 2>"$stderr_file" || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        cat "$stdout_file"
        rm -f "$stdout_file" "$stderr_file"
        return 0
    else
        local stderr_content
        stderr_content=$(<"$stderr_file")
        rm -f "$stdout_file" "$stderr_file"
        [[ -z "$stderr_content" ]] && stderr_content="Command exited with code $exit_code"
        output_structured_error \
            "COMMAND_FAILED" \
            "$stderr_content" \
            "Check command arguments and permissions" \
            "command=$cmd_str" \
            "exit_code=$exit_code"
        return $exit_code
    fi
}

# =============================================================================
# USOP COMMAND EXECUTION - AI Agent Command Envelopes
# =============================================================================
# These functions provide standardized JSON envelopes for command execution
# results, enabling AI agents to parse output reliably and self-correct.
#
# Dependencies: json.sh (for json_object, json_get, json_array)
# =============================================================================

# Auto-source json.sh if json_object is not available
if ! declare -F json_object &>/dev/null; then
    _usop_lib_dir="${BASH_SOURCE[0]%/*}"
    if [[ -f "${_usop_lib_dir}/json.sh" ]]; then
        source "${_usop_lib_dir}/json.sh"
    fi
fi

# Execute any command and wrap result in USOP envelope
# Returns JSON with: success, exit_code, stdout, stderr, duration_ms, command, cwd, timestamp
#
# Usage: usop_exec command [args...]
# Example: result=$(usop_exec ls -la /tmp)
usop_exec() {
    local -a cmd=("$@")

    if [[ ${#cmd[@]} -eq 0 ]]; then
        json_object \
            "success:bool=false" \
            "exit_code:number=1" \
            "stdout=" \
            "stderr=usop_exec: no command provided" \
            "duration_ms:number=0" \
            "command=" \
            "cwd=$PWD" \
            "timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
        return 1
    fi

    local start_time stdout_file stderr_file
    start_time=$(_output_now_ms)
    stdout_file=$(mktemp "${TMPDIR:-/tmp}/usop_out.XXXXXX")
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/usop_err.XXXXXX")

    # Execute capturing output
    "${cmd[@]}" >"$stdout_file" 2>"$stderr_file"
    local exit_code=$?

    local end_time duration_ms
    end_time=$(_output_now_ms)
    duration_ms=$((end_time - start_time))
    [[ $duration_ms -lt 0 ]] && duration_ms=0

    # Read captured output
    local stdout stderr
    stdout=$(<"$stdout_file")
    stderr=$(<"$stderr_file")
    rm -f "$stdout_file" "$stderr_file"

    local success="false"
    [[ $exit_code -eq 0 ]] && success="true"

    json_object \
        "success:bool=$success" \
        "exit_code:number=$exit_code" \
        "stdout=$stdout" \
        "stderr=$stderr" \
        "duration_ms:number=$duration_ms" \
        "command=${cmd[*]}" \
        "cwd=$PWD" \
        "timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"

    return $exit_code
}

# Parse USOP result and extract a specific field
# Supports both top-level fields and nested values
#
# Usage: usop_get JSON_STRING FIELD
# Example: stdout=$(usop_get "$result" "stdout")
usop_get() {
    local json="$1"
    local field="$2"

    if [[ -z "$json" || -z "$field" ]]; then
        return 1
    fi

    json_get "$json" "$field"
}

# Check if USOP result indicates success
# Returns 0 (true) if success:true, 1 (false) otherwise
#
# Usage: usop_ok JSON_STRING
# Example: usop_ok "$result" && echo "Command succeeded"
usop_ok() {
    local json="$1"

    if [[ -z "$json" ]]; then
        return 1
    fi

    local success
    success=$(json_get "$json" "success")
    [[ "$success" == "true" ]]
}

# =============================================================================
# USOP FILE OPERATIONS
# =============================================================================

# Read file and return USOP envelope with content
# Includes file metadata (size, path) and AI-friendly error suggestions
#
# Usage: usop_read_file PATH
# Example: result=$(usop_read_file /etc/hosts)
usop_read_file() {
    local path="$1"

    if [[ -z "$path" ]]; then
        json_object \
            "success:bool=false" \
            "error=path required" \
            "path=" \
            "suggestion=Provide a file path as the first argument"
        return 1
    fi

    if [[ ! -e "$path" ]]; then
        json_object \
            "success:bool=false" \
            "error=file not found" \
            "path=$path" \
            "suggestion=Verify the path exists and check for typos"
        return 1
    fi

    if [[ ! -f "$path" ]]; then
        json_object \
            "success:bool=false" \
            "error=not a regular file" \
            "path=$path" \
            "suggestion=The path exists but is not a regular file (may be directory or special file)"
        return 1
    fi

    if [[ ! -r "$path" ]]; then
        json_object \
            "success:bool=false" \
            "error=permission denied" \
            "path=$path" \
            "suggestion=Check file permissions or run with appropriate privileges"
        return 1
    fi

    local content size
    content=$(<"$path")
    # Get file size (portable between Linux and macOS)
    if [[ "$OSTYPE" == darwin* ]]; then
        size=$(stat -f%z "$path" 2>/dev/null || echo "0")
    else
        size=$(stat -c%s "$path" 2>/dev/null || echo "0")
    fi

    json_object \
        "success:bool=true" \
        "path=$path" \
        "size:number=$size" \
        "content=$content"
}

# Write content to file atomically and return USOP envelope
# Uses atomic_write if available for safe file operations
#
# Usage: usop_write_file PATH CONTENT
# Example: result=$(usop_write_file /tmp/test.txt "Hello World")
usop_write_file() {
    local path="$1"
    local content="$2"

    if [[ -z "$path" ]]; then
        json_object \
            "success:bool=false" \
            "error=path required" \
            "path=" \
            "suggestion=Provide a file path as the first argument"
        return 1
    fi

    # Check parent directory exists
    local parent_dir
    parent_dir="${path%/*}"
    if [[ "$parent_dir" != "$path" ]] && [[ ! -d "$parent_dir" ]]; then
        json_object \
            "success:bool=false" \
            "error=parent directory does not exist" \
            "path=$path" \
            "parent=$parent_dir" \
            "suggestion=Create parent directory first or check the path"
        return 1
    fi

    # Check if parent is writable
    local check_dir="$parent_dir"
    [[ "$check_dir" == "$path" ]] && check_dir="."
    if [[ ! -w "$check_dir" ]]; then
        json_object \
            "success:bool=false" \
            "error=permission denied" \
            "path=$path" \
            "operation=write" \
            "suggestion=Check directory permissions or run with appropriate privileges"
        return 1
    fi

    # Use atomic_write if available
    if declare -F atomic_write &>/dev/null; then
        if atomic_write "$path" "$content"; then
            json_object \
                "success:bool=true" \
                "path=$path" \
                "bytes_written:number=${#content}" \
                "action=written"
        else
            json_object \
                "success:bool=false" \
                "error=write failed" \
                "path=$path" \
                "suggestion=Check disk space and file system permissions"
            return 1
        fi
    else
        # Fallback to direct write
        if printf '%s' "$content" > "$path"; then
            json_object \
                "success:bool=true" \
                "path=$path" \
                "bytes_written:number=${#content}" \
                "action=written"
        else
            json_object \
                "success:bool=false" \
                "error=write failed" \
                "path=$path" \
                "suggestion=Check disk space and file system permissions"
            return 1
        fi
    fi
}

# List directory contents and return USOP envelope
# Returns array of entries with file/directory information
#
# Usage: usop_list_dir [PATH]
# Example: result=$(usop_list_dir /tmp)
usop_list_dir() {
    local path="${1:-.}"

    if [[ ! -e "$path" ]]; then
        json_object \
            "success:bool=false" \
            "error=path not found" \
            "path=$path" \
            "suggestion=Verify the path exists"
        return 1
    fi

    if [[ ! -d "$path" ]]; then
        json_object \
            "success:bool=false" \
            "error=not a directory" \
            "path=$path" \
            "suggestion=The path exists but is not a directory"
        return 1
    fi

    if [[ ! -r "$path" ]] || [[ ! -x "$path" ]]; then
        json_object \
            "success:bool=false" \
            "error=permission denied" \
            "path=$path" \
            "suggestion=Check directory permissions (need read and execute)"
        return 1
    fi

    local -a entries=()
    local entry
    while IFS= read -r -d '' entry; do
        entries+=("$entry")
    done < <(find "$path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null | sort -z)

    local entries_json
    entries_json=$(json_array "${entries[@]}")

    json_object \
        "success:bool=true" \
        "path=$path" \
        "count:number=${#entries[@]}" \
        "entries:raw=$entries_json"
}

# =============================================================================
# USOP PROCESS OPERATIONS
# =============================================================================

# Run command in background and return USOP envelope with tracking info
# Returns PID and paths to stdout/stderr capture files
#
# Usage: usop_run_background command [args...]
# Example: result=$(usop_run_background sleep 30)
usop_run_background() {
    local -a cmd=("$@")

    if [[ ${#cmd[@]} -eq 0 ]]; then
        json_object \
            "success:bool=false" \
            "error=no command provided" \
            "suggestion=Provide a command to run in background"
        return 1
    fi

    local stdout_file stderr_file
    stdout_file=$(mktemp "${TMPDIR:-/tmp}/usop_bg_out.XXXXXX")
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/usop_bg_err.XXXXXX")

    # Start in background
    "${cmd[@]}" >"$stdout_file" 2>"$stderr_file" &
    local pid=$!

    # Verify process started
    if ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$stdout_file" "$stderr_file"
        json_object \
            "success:bool=false" \
            "error=failed to start process" \
            "command=${cmd[*]}" \
            "suggestion=Check if command exists and is executable"
        return 1
    fi

    json_object \
        "success:bool=true" \
        "pid:number=$pid" \
        "stdout_file=$stdout_file" \
        "stderr_file=$stderr_file" \
        "command=${cmd[*]}"
}

# Check status of a process by PID
# Returns running status and exit code if completed
#
# Usage: usop_check_pid PID
# Example: result=$(usop_check_pid 12345)
usop_check_pid() {
    local pid="$1"

    if [[ -z "$pid" ]]; then
        json_object \
            "success:bool=false" \
            "error=pid required" \
            "suggestion=Provide a process ID to check"
        return 1
    fi

    if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
        json_object \
            "success:bool=false" \
            "error=invalid pid format" \
            "pid=$pid" \
            "suggestion=PID must be a positive integer"
        return 1
    fi

    if kill -0 "$pid" 2>/dev/null; then
        json_object \
            "success:bool=true" \
            "pid:number=$pid" \
            "status=running"
    else
        # Process not running - try to get exit code
        local exit_code=0
        wait "$pid" 2>/dev/null
        exit_code=$?

        json_object \
            "success:bool=true" \
            "pid:number=$pid" \
            "status=exited" \
            "exit_code:number=$exit_code"
    fi
}

# =============================================================================
# USOP ERROR HELPERS - Standard Error Formats for AI Agents
# =============================================================================

# Generate standard "not found" error envelope
#
# Usage: usop_error_not_found WHAT PATH
# Example: usop_error_not_found "file" "/path/to/missing"
usop_error_not_found() {
    local what="${1:-resource}"
    local path="$2"

    json_object \
        "success:bool=false" \
        "error=$what not found" \
        "path=$path" \
        "suggestion=Verify the path exists and check for typos"
}

# Generate standard "permission denied" error envelope
#
# Usage: usop_error_permission PATH OPERATION
# Example: usop_error_permission "/etc/shadow" "read"
usop_error_permission() {
    local path="$1"
    local operation="${2:-access}"

    json_object \
        "success:bool=false" \
        "error=permission denied" \
        "path=$path" \
        "operation=$operation" \
        "suggestion=Check file permissions or run with appropriate privileges"
}

# Generate standard validation error envelope
#
# Usage: usop_error_validation FIELD VALUE EXPECTED
# Example: usop_error_validation "port" "abc" "integer 1-65535"
usop_error_validation() {
    local field="$1"
    local value="$2"
    local expected="$3"

    json_object \
        "success:bool=false" \
        "error=validation failed" \
        "field=$field" \
        "value=$value" \
        "expected=$expected" \
        "suggestion=Provide a value matching the expected format"
}

# Generate timeout error envelope
#
# Usage: usop_error_timeout OPERATION TIMEOUT_SECS
# Example: usop_error_timeout "HTTP request" "30"
usop_error_timeout() {
    local operation="${1:-operation}"
    local timeout_secs="${2:-unknown}"

    json_object \
        "success:bool=false" \
        "error=timeout" \
        "operation=$operation" \
        "timeout_secs=$timeout_secs" \
        "suggestion=Increase timeout or check if target is responsive"
}

# Generate command failed error envelope with full context
#
# Usage: usop_error_command_failed CMD EXIT_CODE STDERR
# Example: usop_error_command_failed "git pull" "128" "fatal: not a git repository"
usop_error_command_failed() {
    local cmd_str="$1"
    local exit_code="${2:-1}"
    local stderr="$3"

    json_object \
        "success:bool=false" \
        "error=command failed" \
        "command=$cmd_str" \
        "exit_code:number=$exit_code" \
        "stderr=$stderr" \
        "suggestion=Check command arguments, permissions, and prerequisites"
}

# =============================================================================
# USOP NAMEREF VARIANTS (High Performance)
# =============================================================================

# Execute command and store USOP result in variable (avoids subshell)
#
# Usage: usop_exec_v RESULT_VAR command [args...]
# Example: usop_exec_v result ls -la /tmp
usop_exec_v() {
    local -n __uev_out=$1
    shift
    local -a cmd=("$@")

    if [[ ${#cmd[@]} -eq 0 ]]; then
        json_object_v __uev_out \
            "success:bool=false" \
            "exit_code:number=1" \
            "stdout=" \
            "stderr=usop_exec: no command provided" \
            "duration_ms:number=0" \
            "command=" \
            "cwd=$PWD" \
            "timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
        return 1
    fi

    local start_time stdout_file stderr_file
    start_time=$(_output_now_ms)
    stdout_file=$(mktemp "${TMPDIR:-/tmp}/usop_out.XXXXXX")
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/usop_err.XXXXXX")

    # Execute capturing output
    "${cmd[@]}" >"$stdout_file" 2>"$stderr_file"
    local exit_code=$?

    local end_time duration_ms
    end_time=$(_output_now_ms)
    duration_ms=$((end_time - start_time))
    [[ $duration_ms -lt 0 ]] && duration_ms=0

    # Read captured output
    local stdout stderr
    stdout=$(<"$stdout_file")
    stderr=$(<"$stderr_file")
    rm -f "$stdout_file" "$stderr_file"

    local success="false"
    [[ $exit_code -eq 0 ]] && success="true"

    json_object_v __uev_out \
        "success:bool=$success" \
        "exit_code:number=$exit_code" \
        "stdout=$stdout" \
        "stderr=$stderr" \
        "duration_ms:number=$duration_ms" \
        "command=${cmd[*]}" \
        "cwd=$PWD" \
        "timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"

    return $exit_code
}

# Extract USOP field into variable (avoids subshell)
#
# Usage: usop_get_v RESULT_VAR JSON_STRING FIELD
# Example: usop_get_v stdout_val "$result" "stdout"
usop_get_v() {
    local -n __ugv_out=$1
    local json="$2"
    local field="$3"

    if [[ -z "$json" || -z "$field" ]]; then
        __ugv_out=""
        return 1
    fi

    json_get_v __ugv_out "$json" "$field"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# List of public functions for documentation
_OUTPUT_EXPORTS=(
    # Mode management
    output_init
    output_mode
    output_is_json
    output_is_raw
    output_is_minimal
    output_is_debug
    output_format
    # Timing
    output_timer_start
    output_timer_elapsed
    # Core USOP
    output_success
    output_error
    output_raw
    output_json
    # Type helpers
    output_string
    output_int
    output_float
    output_bool
    output_json_object
    output_json_array
    output_file_path
    output_void
    # Nameref variant
    output_v
    # Wrapping
    output_wrap
    output_with_mode
    # Legacy
    mainframe_call
    output_auto
    output_list
    output_object
    output_progress
    output_structured_error
    output_try
    output_json_escape
    output_json_array_from_lines
    # USOP Command Execution
    usop_exec
    usop_get
    usop_ok
    usop_exec_v
    usop_get_v
    # USOP File Operations
    usop_read_file
    usop_write_file
    usop_list_dir
    # USOP Process Operations
    usop_run_background
    usop_check_pid
    # USOP Error Helpers
    usop_error_not_found
    usop_error_permission
    usop_error_validation
    usop_error_timeout
    usop_error_command_failed
)

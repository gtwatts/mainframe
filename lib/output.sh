#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/output.sh - Universal Structured Output Protocol (USOP)
# =============================================================================
# Description: Enables all MAINFRAME functions to output structured JSON
#              envelopes instead of raw text, making the toolkit machine-readable
#              for AI coding agents. Provides mode detection, envelope functions,
#              and the mainframe_call meta-wrapper for automatic USOP wrapping.
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

# Environment variable to enable JSON output globally
# Set MAINFRAME_OUTPUT=json to activate structured output
MAINFRAME_OUTPUT="${MAINFRAME_OUTPUT:-text}"

# =============================================================================
# OUTPUT MODE DETECTION
# =============================================================================

# Check if JSON output is requested
# Returns 0 if MAINFRAME_OUTPUT=json
# Usage: output_is_json && echo "JSON mode active"
output_is_json() {
    [[ "${MAINFRAME_OUTPUT:-text}" == "json" ]]
}

# Returns the current output format: "json" or "text"
# Usage: fmt=$(output_format)
output_format() {
    if output_is_json; then
        printf 'json'
    else
        printf 'text'
    fi
}

# =============================================================================
# JSON HELPERS
# =============================================================================

# Escape a string for safe JSON embedding
# Handles: quotes, backslashes, newlines, tabs, carriage returns,
#           backspace, form feed, and all control characters (< 0x20)
# Usage: escaped=$(output_json_escape "hello \"world\"")
output_json_escape() {
    local str="$1"
    local result=""
    local i char

    for ((i=0; i<${#str}; i++)); do
        char="${str:i:1}"
        case "$char" in
            '"')   result+='\"' ;;
            '\')   result+='\\' ;;
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

# Emit a JSON key-value pair with string value
# Usage: output_json_string "key" "value"
# Output: "key":"value"
output_json_string() {
    local key="$1"
    local value="$2"
    printf '"%s":"%s"' "$(output_json_escape "$key")" "$(output_json_escape "$value")"
}

# Emit a JSON key-value pair with number value
# Usage: output_json_number "key" 42
# Output: "key":42
output_json_number() {
    local key="$1"
    local value="$2"
    # Validate number format (integer, float, or scientific notation)
    if [[ "$value" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]; then
        printf '"%s":%s' "$(output_json_escape "$key")" "$value"
    else
        printf '"%s":null' "$(output_json_escape "$key")"
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
        true|1|yes|on)  printf '"%s":true' "$(output_json_escape "$key")" ;;
        false|0|no|off) printf '"%s":false' "$(output_json_escape "$key")" ;;
        *) printf '"%s":null' "$(output_json_escape "$key")"; return 1 ;;
    esac
}

# Emit a JSON key-value pair with null value
# Usage: output_json_null "key"
# Output: "key":null
output_json_null() {
    local key="$1"
    printf '"%s":null' "$(output_json_escape "$key")"
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
        printf '"%s"' "$(output_json_escape "$line")"
    done
    printf ']'
}

# =============================================================================
# USOP ENVELOPE FUNCTIONS
# =============================================================================

# Emit a success envelope
# Usage: output_success "result_data" ["message"]
# Output: {"status":"success","data":"result_data","message":"Operation completed"}
output_success() {
    local data="$1"
    local message="${2:-}"

    printf '{"status":"success","data":"%s"' "$(output_json_escape "$data")"
    if [[ -n "$message" ]]; then
        printf ',"message":"%s"' "$(output_json_escape "$message")"
    fi
    printf '}\n'
}

# Emit an error envelope
# Usage: output_error "error message" [exit_code] ["context"]
# Output: {"status":"error","error":"error message","code":1,"context":"..."}
output_error() {
    local error_msg="$1"
    local exit_code="${2:-1}"
    local context="${3:-}"

    printf '{"status":"error","error":"%s","code":%d' "$(output_json_escape "$error_msg")" "$exit_code"
    if [[ -n "$context" ]]; then
        printf ',"context":"%s"' "$(output_json_escape "$context")"
    fi
    printf '}\n'
}

# Emit a list/array envelope
# Usage: output_list item1 item2 item3
# Output: {"status":"success","data":["item1","item2","item3"],"count":3}
output_list() {
    local count=$#
    local first=true

    printf '{"status":"success","data":['
    for item in "$@"; do
        $first || printf ','
        first=false
        printf '"%s"' "$(output_json_escape "$item")"
    done
    printf '],"count":%d}\n' "$count"
}

# Emit a key-value object envelope
# Supports typed values via key:type=value syntax
# Types: number, bool, null, raw (default: string)
#
# Usage: output_object "key1=val1" "key2=val2" "key3:number=42"
# Output: {"status":"success","data":{"key1":"val1","key2":"val2","key3":42}}
output_object() {
    local first=true

    printf '{"status":"success","data":{'
    for pair in "$@"; do
        local key type value

        # Parse key:type=value or key=value
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

        printf '"%s":' "$(output_json_escape "$key")"
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
            null)
                printf 'null'
                ;;
            raw)
                printf '%s' "$value"
                ;;
            *)
                # Default: string
                printf '"%s"' "$(output_json_escape "$value")"
                ;;
        esac
    done
    printf '}}\n'
}

# Emit a progress envelope for streaming/long operations
# Usage: output_progress "step_name" current total ["message"]
# Output: {"status":"progress","step":"step_name","current":3,"total":10,"message":"..."}
output_progress() {
    local step="$1"
    local current="$2"
    local total="$3"
    local message="${4:-}"

    printf '{"status":"progress","step":"%s","current":%d,"total":%d' \
        "$(output_json_escape "$step")" "$current" "$total"
    if [[ -n "$message" ]]; then
        printf ',"message":"%s"' "$(output_json_escape "$message")"
    fi
    printf '}\n'
}

# =============================================================================
# mainframe_call META-WRAPPER
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

# Invoke any MAINFRAME function with automatic USOP wrapping
# Captures stdout, stderr, exit code, and wraps in JSON envelope
#
# Usage: mainframe_call function_name [args...]
# Output: {
#   "status": "success|error",
#   "function": "function_name",
#   "data": "stdout content",
#   "stderr": "stderr content",
#   "exit_code": 0,
#   "duration_ms": 42
# }
mainframe_call() {
    local func_name="$1"
    shift

    # Validate function exists
    if ! declare -F "$func_name" &>/dev/null; then
        printf '{"status":"error","function":"%s","error":"Function not found: %s","exit_code":127,"duration_ms":0}\n' \
            "$(output_json_escape "$func_name")" \
            "$(output_json_escape "$func_name")"
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

    # Guard against negative duration (clock skew / fallback timer issues)
    if [[ $duration_ms -lt 0 ]]; then
        duration_ms=0
    fi

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
        "$(output_json_escape "$func_name")" \
        "$(output_json_escape "$stdout_content")"

    if [[ -n "$stderr_content" ]]; then
        printf ',"stderr":"%s"' "$(output_json_escape "$stderr_content")"
    fi

    printf ',"exit_code":%d,"duration_ms":%d}\n' "$func_exit_code" "$duration_ms"
    return $func_exit_code
}

# =============================================================================
# CONDITIONAL OUTPUT HELPER
# =============================================================================

# Auto-detect output mode and emit appropriate format
# If MAINFRAME_OUTPUT=json, outputs json_data; otherwise outputs text_output
#
# Usage: output_auto "plain text result" '{"status":"success","data":"value"}'
# Usage inside functions:
#   local result="computed value"
#   output_auto "$result" "$(output_success "$result" "done")"
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
# STRUCTURED ERROR OBJECTS
# =============================================================================

# Create a rich error object with context for AI agent consumption
# Produces valid JSON with error code, message, optional suggestion,
# stack trace (caller chain), and arbitrary context key-value pairs.
#
# Usage: output_structured_error CODE "message" ["suggestion"] ["context_key=val"...]
# Example: output_structured_error "FILE_NOT_FOUND" "Cannot read config" "Check path exists" "path=/etc/app.conf"
# Returns: always returns 1 (error status)
output_structured_error() {
    local code="${1:?error code required}"
    local message="${2:?error message required}"
    local suggestion="${3:-}"
    shift 3 2>/dev/null || shift $#

    local result
    result='{"status":"error"'
    result+=',"code":"'"$(output_json_escape "$code")"'"'
    result+=',"message":"'"$(output_json_escape "$message")"'"'

    # Add suggestion if provided
    if [[ -n "$suggestion" ]]; then
        result+=',"suggestion":"'"$(output_json_escape "$suggestion")"'"'
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
            result+='"'"$(output_json_escape "$key")"'":"'"$(output_json_escape "$val")"'"'
        done
        result+='}'
    fi

    result+='}'
    printf '%s\n' "$result"
    return 1
}

# Wrap a command and produce structured error on failure
# On success: outputs stdout normally, returns 0
# On failure: outputs structured error JSON with captured stderr, returns original exit code
#
# Usage: output_try command [args...]
# Example: output_try ls /nonexistent
# Example: result=$(output_try grep "pattern" file.txt)
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
        # Provide default message if stderr is empty
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

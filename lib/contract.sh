#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/contract.sh - Design-by-Contract & Structured Errors
# =============================================================================
# Description: Precondition/postcondition assertions, type checking, and
#              structured JSON error reporting that AI agents can parse
#              for automated debugging and recovery.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_CONTRACT_LOADED:-}" ]] && return 0
readonly _MAINFRAME_CONTRACT_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Enable/disable contract checking (disable in production for performance)
MAINFRAME_CONTRACTS_ENABLED="${MAINFRAME_CONTRACTS_ENABLED:-1}"

# Emit errors as JSON (1) or plain text (0)
MAINFRAME_ERROR_JSON="${MAINFRAME_ERROR_JSON:-1}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# JSON-escape a string
_contract_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# =============================================================================
# STRUCTURED ERROR REPORTING
# =============================================================================

# @pre: code is integer, msg is non-empty
# @post: JSON error emitted to stderr
# @idempotent: yes
# @returns: the provided exit code
#
# Emit a structured error with code, message, calling function, file, and line.
# AI agents parse this JSON to understand failures and take corrective action.
#
# Usage: mainframe_error 1 "file not found" [context_key=value...]
# Example: mainframe_error 2 "invalid port" "port=99999" "range=1-65535"
mainframe_error() {
    local code="${1:-1}"
    local msg="${2:-unknown error}"
    shift 2 2>/dev/null || shift $#

    local func="${FUNCNAME[1]:-main}"
    local file="${BASH_SOURCE[1]:-unknown}"
    local line="${BASH_LINENO[0]:-0}"

    if [[ "$MAINFRAME_ERROR_JSON" == "1" ]]; then
        local escaped_msg escaped_func escaped_file
        escaped_msg=$(_contract_escape "$msg")
        escaped_func=$(_contract_escape "$func")
        escaped_file=$(_contract_escape "$file")

        local json
        json="{\"error\":true,\"code\":$code,\"msg\":\"$escaped_msg\",\"func\":\"$escaped_func\",\"file\":\"$escaped_file\",\"line\":$line"

        # Add context key=value pairs
        if [[ $# -gt 0 ]]; then
            json+=",\"context\":{"
            local first=true kv key val
            for kv in "$@"; do
                key="${kv%%=*}"
                val="${kv#*=}"
                local escaped_key escaped_val
                escaped_key=$(_contract_escape "$key")
                escaped_val=$(_contract_escape "$val")
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    json+=","
                fi
                json+="\"$escaped_key\":\"$escaped_val\""
            done
            json+="}"
        fi

        json+="}"
        printf '%s\n' "$json" >&2
    else
        printf '[contract] ERROR(%d) in %s (%s:%d): %s\n' \
            "$code" "$func" "$file" "$line" "$msg" >&2
    fi

    return "$code"
}

# =============================================================================
# PRECONDITION CHECKS
# =============================================================================

# @pre: expression is a valid bash test expression
# @post: returns 0 if condition holds, calls mainframe_error otherwise
# @idempotent: yes
# @returns: 0 if condition true, 1 if false (with error emitted)
#
# Assert a precondition. If it fails, emit structured error and return 1.
# Use at the top of functions to validate inputs.
#
# Usage: contract_require "[[ -n \$arg ]]" "argument required" || return $?
# Example: contract_require "[[ -f \$config ]]" "config file missing"
contract_require() {
    [[ "$MAINFRAME_CONTRACTS_ENABLED" != "1" ]] && return 0

    local expr="$1"
    local msg="${2:-precondition failed}"

    if ! eval "$expr" 2>/dev/null; then
        local func="${FUNCNAME[1]:-main}"
        local file="${BASH_SOURCE[1]:-unknown}"
        local line="${BASH_LINENO[0]:-0}"

        if [[ "$MAINFRAME_ERROR_JSON" == "1" ]]; then
            local escaped_msg escaped_func escaped_file escaped_expr
            escaped_msg=$(_contract_escape "$msg")
            escaped_func=$(_contract_escape "$func")
            escaped_file=$(_contract_escape "$file")
            escaped_expr=$(_contract_escape "$expr")

            printf '{"error":true,"type":"precondition","code":1,"msg":"%s","expr":"%s","func":"%s","file":"%s","line":%d}\n' \
                "$escaped_msg" "$escaped_expr" "$escaped_func" "$escaped_file" "$line" >&2
        else
            printf '[contract] PRECONDITION FAILED in %s (%s:%d): %s [%s]\n' \
                "$func" "$file" "$line" "$msg" "$expr" >&2
        fi
        return 1
    fi
    return 0
}

# =============================================================================
# POSTCONDITION CHECKS
# =============================================================================

# @pre: expression is a valid bash test expression
# @post: returns 0 if condition holds, calls mainframe_error otherwise
# @idempotent: yes
# @returns: 0 if condition true, 1 if false (with error emitted)
#
# Assert a postcondition. If it fails, emit structured error.
# Use before returning from functions to validate outputs.
#
# Usage: contract_ensure "[[ -f \$output ]]" "output file not created" || return $?
contract_ensure() {
    [[ "$MAINFRAME_CONTRACTS_ENABLED" != "1" ]] && return 0

    local expr="$1"
    local msg="${2:-postcondition failed}"

    if ! eval "$expr" 2>/dev/null; then
        local func="${FUNCNAME[1]:-main}"
        local file="${BASH_SOURCE[1]:-unknown}"
        local line="${BASH_LINENO[0]:-0}"

        if [[ "$MAINFRAME_ERROR_JSON" == "1" ]]; then
            local escaped_msg escaped_func escaped_file escaped_expr
            escaped_msg=$(_contract_escape "$msg")
            escaped_func=$(_contract_escape "$func")
            escaped_file=$(_contract_escape "$file")
            escaped_expr=$(_contract_escape "$expr")

            printf '{"error":true,"type":"postcondition","code":1,"msg":"%s","expr":"%s","func":"%s","file":"%s","line":%d}\n' \
                "$escaped_msg" "$escaped_expr" "$escaped_func" "$escaped_file" "$line" >&2
        else
            printf '[contract] POSTCONDITION FAILED in %s (%s:%d): %s [%s]\n' \
                "$func" "$file" "$line" "$msg" "$expr" >&2
        fi
        return 1
    fi
    return 0
}

# =============================================================================
# INVARIANT CHECKS
# =============================================================================

# @pre: expression is a valid bash test expression
# @post: returns 0 if condition holds, calls mainframe_error otherwise
# @idempotent: yes
# @returns: 0 if condition true, 1 if false (with error emitted)
#
# Assert an invariant that should always hold. Emits structured error on failure.
#
# Usage: contract_invariant "[[ \$count -ge 0 ]]" "count cannot be negative"
contract_invariant() {
    [[ "$MAINFRAME_CONTRACTS_ENABLED" != "1" ]] && return 0

    local expr="$1"
    local msg="${2:-invariant violated}"

    if ! eval "$expr" 2>/dev/null; then
        local func="${FUNCNAME[1]:-main}"
        local file="${BASH_SOURCE[1]:-unknown}"
        local line="${BASH_LINENO[0]:-0}"

        if [[ "$MAINFRAME_ERROR_JSON" == "1" ]]; then
            local escaped_msg escaped_func escaped_file escaped_expr
            escaped_msg=$(_contract_escape "$msg")
            escaped_func=$(_contract_escape "$func")
            escaped_file=$(_contract_escape "$file")
            escaped_expr=$(_contract_escape "$expr")

            printf '{"error":true,"type":"invariant","code":1,"msg":"%s","expr":"%s","func":"%s","file":"%s","line":%d}\n' \
                "$escaped_msg" "$escaped_expr" "$escaped_func" "$escaped_file" "$line" >&2
        else
            printf '[contract] INVARIANT VIOLATED in %s (%s:%d): %s [%s]\n' \
                "$func" "$file" "$line" "$msg" "$expr" >&2
        fi
        return 1
    fi
    return 0
}

# =============================================================================
# TYPE CHECKS
# =============================================================================

# @pre: value and type are non-empty
# @post: returns 0 if value matches type, 1 otherwise
# @idempotent: yes
# @returns: 0 on match, 1 on mismatch
#
# Check if a value matches an expected type.
# Supported types: int, float, string, bool, file, dir, path, nonempty
#
# Usage: contract_type_check "$port" "int" "port number" || return $?
# Example: contract_type_check "$enabled" "bool" "enabled flag"
contract_type_check() {
    [[ "$MAINFRAME_CONTRACTS_ENABLED" != "1" ]] && return 0

    local value="$1"
    local type="$2"
    local name="${3:-value}"

    local valid=true

    case "$type" in
        int|integer)
            [[ "$value" =~ ^-?[0-9]+$ ]] || valid=false
            ;;
        float|number)
            [[ "$value" =~ ^-?[0-9]+\.?[0-9]*$ ]] || valid=false
            ;;
        bool|boolean)
            [[ "$value" =~ ^(true|false|0|1|yes|no)$ ]] || valid=false
            ;;
        string)
            # Any value is a valid string
            ;;
        nonempty)
            [[ -n "$value" ]] || valid=false
            ;;
        file)
            [[ -f "$value" ]] || valid=false
            ;;
        dir|directory)
            [[ -d "$value" ]] || valid=false
            ;;
        path)
            [[ -e "$value" ]] || valid=false
            ;;
        *)
            valid=false
            ;;
    esac

    if [[ "$valid" != "true" ]]; then
        local func="${FUNCNAME[1]:-main}"
        local file="${BASH_SOURCE[1]:-unknown}"
        local line="${BASH_LINENO[0]:-0}"

        if [[ "$MAINFRAME_ERROR_JSON" == "1" ]]; then
            local escaped_name escaped_type escaped_value escaped_func escaped_file
            escaped_name=$(_contract_escape "$name")
            escaped_type=$(_contract_escape "$type")
            escaped_value=$(_contract_escape "$value")
            escaped_func=$(_contract_escape "$func")
            escaped_file=$(_contract_escape "$file")

            printf '{"error":true,"type":"type_check","code":1,"msg":"%s is not %s","name":"%s","expected_type":"%s","actual_value":"%s","func":"%s","file":"%s","line":%d}\n' \
                "$escaped_name" "$escaped_type" "$escaped_name" "$escaped_type" "$escaped_value" "$escaped_func" "$escaped_file" "$line" >&2
        else
            printf '[contract] TYPE ERROR in %s (%s:%d): %s is not %s (got: %s)\n' \
                "$func" "$file" "$line" "$name" "$type" "$value" >&2
        fi
        return 1
    fi
    return 0
}

# =============================================================================
# CONVENIENCE ASSERTIONS
# =============================================================================

# @pre: arguments provided
# @post: returns 0 if all non-empty, 1 on first empty
# @idempotent: yes
# @returns: 0 if all non-empty, 1 if any empty
#
# Assert that all provided arguments are non-empty strings.
# Common precondition for functions requiring arguments.
#
# Usage: contract_not_empty "arg1" "arg2" || return $?
# Example: contract_not_empty "$file" "$content" || return $?
contract_not_empty() {
    [[ "$MAINFRAME_CONTRACTS_ENABLED" != "1" ]] && return 0

    local i=1
    for arg in "$@"; do
        if [[ -z "$arg" ]]; then
            local func="${FUNCNAME[1]:-main}"
            local file="${BASH_SOURCE[1]:-unknown}"
            local line="${BASH_LINENO[0]:-0}"

            if [[ "$MAINFRAME_ERROR_JSON" == "1" ]]; then
                local escaped_func escaped_file
                escaped_func=$(_contract_escape "$func")
                escaped_file=$(_contract_escape "$file")

                printf '{"error":true,"type":"not_empty","code":1,"msg":"argument %d is empty","arg_index":%d,"func":"%s","file":"%s","line":%d}\n' \
                    "$i" "$i" "$escaped_func" "$escaped_file" "$line" >&2
            else
                printf '[contract] EMPTY ARGUMENT in %s (%s:%d): argument %d is empty\n' \
                    "$func" "$file" "$line" "$i" >&2
            fi
            return 1
        fi
        i=$((i + 1))
    done
    return 0
}

# @pre: path argument provided
# @post: returns 0 if file exists, 1 otherwise
# @idempotent: yes
# @returns: 0 if file exists, 1 if not
#
# Assert that a file exists. Emits structured error with path context.
#
# Usage: contract_is_file "$config_path" || return $?
contract_is_file() {
    [[ "$MAINFRAME_CONTRACTS_ENABLED" != "1" ]] && return 0

    local path="$1"
    local name="${2:-file}"

    if [[ ! -f "$path" ]]; then
        local func="${FUNCNAME[1]:-main}"
        local file="${BASH_SOURCE[1]:-unknown}"
        local line="${BASH_LINENO[0]:-0}"

        if [[ "$MAINFRAME_ERROR_JSON" == "1" ]]; then
            local escaped_path escaped_name escaped_func escaped_file
            escaped_path=$(_contract_escape "$path")
            escaped_name=$(_contract_escape "$name")
            escaped_func=$(_contract_escape "$func")
            escaped_file=$(_contract_escape "$file")

            printf '{"error":true,"type":"file_check","code":1,"msg":"%s not found","path":"%s","func":"%s","file":"%s","line":%d}\n' \
                "$escaped_name" "$escaped_path" "$escaped_func" "$escaped_file" "$line" >&2
        else
            printf '[contract] FILE NOT FOUND in %s (%s:%d): %s (%s)\n' \
                "$func" "$file" "$line" "$name" "$path" >&2
        fi
        return 1
    fi
    return 0
}

# @pre: path argument provided
# @post: returns 0 if directory exists, 1 otherwise
# @idempotent: yes
# @returns: 0 if directory exists, 1 if not
#
# Assert that a directory exists. Emits structured error with path context.
#
# Usage: contract_is_dir "$output_dir" || return $?
contract_is_dir() {
    [[ "$MAINFRAME_CONTRACTS_ENABLED" != "1" ]] && return 0

    local path="$1"
    local name="${2:-directory}"

    if [[ ! -d "$path" ]]; then
        local func="${FUNCNAME[1]:-main}"
        local file="${BASH_SOURCE[1]:-unknown}"
        local line="${BASH_LINENO[0]:-0}"

        if [[ "$MAINFRAME_ERROR_JSON" == "1" ]]; then
            local escaped_path escaped_name escaped_func escaped_file
            escaped_path=$(_contract_escape "$path")
            escaped_name=$(_contract_escape "$name")
            escaped_func=$(_contract_escape "$func")
            escaped_file=$(_contract_escape "$file")

            printf '{"error":true,"type":"dir_check","code":1,"msg":"%s not found","path":"%s","func":"%s","file":"%s","line":%d}\n' \
                "$escaped_name" "$escaped_path" "$escaped_func" "$escaped_file" "$line" >&2
        else
            printf '[contract] DIR NOT FOUND in %s (%s:%d): %s (%s)\n' \
                "$func" "$file" "$line" "$name" "$path" >&2
        fi
        return 1
    fi
    return 0
}

# @pre: value and min/max are integers
# @post: returns 0 if value in range, 1 otherwise
# @idempotent: yes
# @returns: 0 if in range, 1 if out of range
#
# Assert that an integer value is within a given range [min, max].
#
# Usage: contract_in_range "$port" 1 65535 "port" || return $?
contract_in_range() {
    [[ "$MAINFRAME_CONTRACTS_ENABLED" != "1" ]] && return 0

    local value="$1"
    local min="$2"
    local max="$3"
    local name="${4:-value}"

    # First check it's an integer
    if [[ ! "$value" =~ ^-?[0-9]+$ ]]; then
        local func="${FUNCNAME[1]:-main}"
        local file="${BASH_SOURCE[1]:-unknown}"
        local line="${BASH_LINENO[0]:-0}"

        if [[ "$MAINFRAME_ERROR_JSON" == "1" ]]; then
            local escaped_name escaped_func escaped_file
            escaped_name=$(_contract_escape "$name")
            escaped_func=$(_contract_escape "$func")
            escaped_file=$(_contract_escape "$file")

            printf '{"error":true,"type":"range_check","code":1,"msg":"%s is not an integer","name":"%s","value":"%s","min":%d,"max":%d,"func":"%s","file":"%s","line":%d}\n' \
                "$escaped_name" "$escaped_name" "$value" "$min" "$max" "$escaped_func" "$escaped_file" "$line" >&2
        fi
        return 1
    fi

    if (( value < min || value > max )); then
        local func="${FUNCNAME[1]:-main}"
        local file="${BASH_SOURCE[1]:-unknown}"
        local line="${BASH_LINENO[0]:-0}"

        if [[ "$MAINFRAME_ERROR_JSON" == "1" ]]; then
            local escaped_name escaped_func escaped_file
            escaped_name=$(_contract_escape "$name")
            escaped_func=$(_contract_escape "$func")
            escaped_file=$(_contract_escape "$file")

            printf '{"error":true,"type":"range_check","code":1,"msg":"%s out of range","name":"%s","value":%d,"min":%d,"max":%d,"func":"%s","file":"%s","line":%d}\n' \
                "$escaped_name" "$escaped_name" "$value" "$min" "$max" "$escaped_func" "$escaped_file" "$line" >&2
        else
            printf '[contract] RANGE ERROR in %s (%s:%d): %s=%d not in [%d,%d]\n' \
                "$func" "$file" "$line" "$name" "$value" "$min" "$max" >&2
        fi
        return 1
    fi
    return 0
}

# @pre: none
# @post: contract checking disabled
# @idempotent: yes
# @returns: 0
#
# Disable contract checking globally (for production performance).
#
# Usage: contracts_disable
contracts_disable() {
    MAINFRAME_CONTRACTS_ENABLED=0
}

# @pre: none
# @post: contract checking enabled
# @idempotent: yes
# @returns: 0
#
# Enable contract checking globally.
#
# Usage: contracts_enable
contracts_enable() {
    MAINFRAME_CONTRACTS_ENABLED=1
}

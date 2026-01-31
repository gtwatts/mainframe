#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/jsonpath.sh - Pure Bash JSONPath Query Engine
# =============================================================================
# Description: Extract values from JSON using JSONPath-like syntax without
#              external dependencies (no jq required). Optimized for AI agents.
# Version: 1.1.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================
#
# Supported JSONPath Syntax:
#   .key           - Object property access
#   [N]            - Array index (0-based)
#   [-N]           - Negative index (from end)
#   .a.b.c         - Chained property access
#   [*]            - All array elements (returns JSON array)
#   .key1.key2[0]  - Mixed access
#
# Examples:
#   jsonpath_query '{"name":"John"}' '.name'                    -> John
#   jsonpath_query '{"users":[{"id":1}]}' '.users[0].id'       -> 1
#   jsonpath_query '{"items":["a","b","c"]}' '.items[-1]'      -> c
#   jsonpath_query '{"data":[1,2,3]}' '.data[*]'               -> [1,2,3]
#
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_JSONPATH_LOADED:-}" ]] && return 0
declare -g _MAINFRAME_JSONPATH_LOADED=1

# =============================================================================
# ERROR CODES
# =============================================================================

readonly JSONPATH_OK=0
readonly JSONPATH_E_INVALID_JSON=1
readonly JSONPATH_E_INVALID_PATH=2
readonly JSONPATH_E_PATH_NOT_FOUND=3
readonly JSONPATH_E_TYPE_MISMATCH=4
readonly JSONPATH_E_INDEX_OUT_OF_BOUNDS=5

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Extract a string value at current position
# @param $1 - JSON string
# @param $2 - start position (at opening quote)
# @sets _JP_VALUE - the extracted string
# @sets _JP_END - position after closing quote
_jp_extract_string() {
    local json="$1"
    local pos=$2
    local len=${#json}
    local result=""
    local char prev_char=""

    # Skip opening quote
    ((pos++))

    while (( pos < len )); do
        char="${json:pos:1}"

        if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
            _JP_VALUE="$result"
            _JP_END=$((pos + 1))
            return 0
        fi

        if [[ "$prev_char" == '\' ]]; then
            result="${result%\\}"
            case "$char" in
                'n') result+=$'\n' ;;
                'r') result+=$'\r' ;;
                't') result+=$'\t' ;;
                '"'|'/'|'\') result+="$char" ;;
                *) result+="\\$char" ;;
            esac
        else
            result+="$char"
        fi

        prev_char="$char"
        ((pos++))
    done

    return 1
}

# Skip whitespace
# @param $1 - JSON string
# @param $2 - start position
# @returns new position
_jp_skip_ws() {
    local json="$1"
    local pos=$2
    local len=${#json}

    while (( pos < len )); do
        case "${json:pos:1}" in
            ' '|$'\t'|$'\n'|$'\r') ((pos++)) ;;
            *) break ;;
        esac
    done

    printf '%d' "$pos"
}

# Find end of a JSON value
# @param $1 - JSON string
# @param $2 - start position
# @returns position after value
_jp_skip_value() {
    local json="$1"
    local pos=$2
    local len=${#json}
    local char

    pos=$(_jp_skip_ws "$json" "$pos")
    char="${json:pos:1}"

    case "$char" in
        '"')
            _jp_extract_string "$json" "$pos"
            printf '%d' "$_JP_END"
            ;;
        '{')
            local depth=1
            ((pos++))
            local in_string=false
            while (( pos < len && depth > 0 )); do
                char="${json:pos:1}"
                if $in_string; then
                    if [[ "$char" == '"' && "${json:pos-1:1}" != '\' ]]; then
                        in_string=false
                    fi
                else
                    case "$char" in
                        '"') in_string=true ;;
                        '{') ((depth++)) ;;
                        '}') ((depth--)) ;;
                    esac
                fi
                ((pos++))
            done
            printf '%d' "$pos"
            ;;
        '[')
            local depth=1
            ((pos++))
            local in_string=false
            while (( pos < len && depth > 0 )); do
                char="${json:pos:1}"
                if $in_string; then
                    if [[ "$char" == '"' && "${json:pos-1:1}" != '\' ]]; then
                        in_string=false
                    fi
                else
                    case "$char" in
                        '"') in_string=true ;;
                        '[') ((depth++)) ;;
                        ']') ((depth--)) ;;
                    esac
                fi
                ((pos++))
            done
            printf '%d' "$pos"
            ;;
        '-'|[0-9])
            while (( pos < len )) && [[ "${json:pos:1}" =~ [0-9.eE+-] ]]; do
                ((pos++))
            done
            printf '%d' "$pos"
            ;;
        't')
            printf '%d' $((pos + 4))
            ;;
        'f')
            printf '%d' $((pos + 5))
            ;;
        'n')
            printf '%d' $((pos + 4))
            ;;
        *)
            printf '%d' "$pos"
            ;;
    esac
}

# Get value from object by key
# @param $1 - JSON object string
# @param $2 - key to find
# @sets _JP_RESULT - extracted value
_jp_object_get() {
    local json="$1"
    local target_key="$2"
    local pos=0
    local len=${#json}

    pos=$(_jp_skip_ws "$json" "$pos")

    # Must be at '{'
    [[ "${json:pos:1}" != '{' ]] && return "$JSONPATH_E_TYPE_MISMATCH"
    ((pos++))

    pos=$(_jp_skip_ws "$json" "$pos")

    # Empty object
    [[ "${json:pos:1}" == '}' ]] && return "$JSONPATH_E_PATH_NOT_FOUND"

    while (( pos < len )); do
        pos=$(_jp_skip_ws "$json" "$pos")

        # Read key
        [[ "${json:pos:1}" != '"' ]] && return "$JSONPATH_E_INVALID_JSON"

        _jp_extract_string "$json" "$pos" || return "$JSONPATH_E_INVALID_JSON"
        local key="$_JP_VALUE"
        pos=$_JP_END

        pos=$(_jp_skip_ws "$json" "$pos")

        # Expect colon
        [[ "${json:pos:1}" != ':' ]] && return "$JSONPATH_E_INVALID_JSON"
        ((pos++))

        pos=$(_jp_skip_ws "$json" "$pos")

        if [[ "$key" == "$target_key" ]]; then
            # Found it - extract value
            local value_start=$pos
            local value_end
            value_end=$(_jp_skip_value "$json" "$pos")
            _JP_RESULT="${json:value_start:value_end-value_start}"
            return 0
        fi

        # Skip this value
        pos=$(_jp_skip_value "$json" "$pos")
        pos=$(_jp_skip_ws "$json" "$pos")

        # Check for comma or end
        local char="${json:pos:1}"
        if [[ "$char" == '}' ]]; then
            break
        elif [[ "$char" == ',' ]]; then
            ((pos++))
        else
            return "$JSONPATH_E_INVALID_JSON"
        fi
    done

    return "$JSONPATH_E_PATH_NOT_FOUND"
}

# Get value from array by index
# @param $1 - JSON array string
# @param $2 - index (can be negative)
# @sets _JP_RESULT - extracted value
_jp_array_get() {
    local json="$1"
    local target_idx=$2
    local pos=0
    local len=${#json}

    pos=$(_jp_skip_ws "$json" "$pos")

    # Must be at '['
    [[ "${json:pos:1}" != '[' ]] && return "$JSONPATH_E_TYPE_MISMATCH"
    ((pos++))

    pos=$(_jp_skip_ws "$json" "$pos")

    # Empty array
    [[ "${json:pos:1}" == ']' ]] && return "$JSONPATH_E_INDEX_OUT_OF_BOUNDS"

    # For negative index, count elements first
    if (( target_idx < 0 )); then
        local count_pos=$pos
        local count=0
        while (( count_pos < len )); do
            count_pos=$(_jp_skip_ws "$json" "$count_pos")
            [[ "${json:count_pos:1}" == ']' ]] && break
            count_pos=$(_jp_skip_value "$json" "$count_pos")
            ((count++))
            count_pos=$(_jp_skip_ws "$json" "$count_pos")
            local char="${json:count_pos:1}"
            if [[ "$char" == ']' ]]; then
                break
            elif [[ "$char" == ',' ]]; then
                ((count_pos++))
            fi
        done
        target_idx=$((count + target_idx))
        (( target_idx < 0 )) && return "$JSONPATH_E_INDEX_OUT_OF_BOUNDS"
    fi

    # Iterate to target index
    local current_idx=0
    while (( pos < len )); do
        pos=$(_jp_skip_ws "$json" "$pos")

        [[ "${json:pos:1}" == ']' ]] && return "$JSONPATH_E_INDEX_OUT_OF_BOUNDS"

        if (( current_idx == target_idx )); then
            local value_start=$pos
            local value_end
            value_end=$(_jp_skip_value "$json" "$pos")
            _JP_RESULT="${json:value_start:value_end-value_start}"
            return 0
        fi

        pos=$(_jp_skip_value "$json" "$pos")
        pos=$(_jp_skip_ws "$json" "$pos")

        local char="${json:pos:1}"
        if [[ "$char" == ']' ]]; then
            break
        elif [[ "$char" == ',' ]]; then
            ((pos++))
            ((current_idx++))
        else
            return "$JSONPATH_E_INVALID_JSON"
        fi
    done

    return "$JSONPATH_E_INDEX_OUT_OF_BOUNDS"
}

# Get all array elements
# @param $1 - JSON array string
# @sets _JP_RESULT - the original array (pass-through)
_jp_array_all() {
    local json="$1"
    local pos=0

    pos=$(_jp_skip_ws "$json" "$pos")
    [[ "${json:pos:1}" != '[' ]] && return "$JSONPATH_E_TYPE_MISMATCH"

    _JP_RESULT="$json"
    return 0
}

# =============================================================================
# PUBLIC API
# =============================================================================

# Query JSON using JSONPath syntax
# @param $1 - JSON string
# @param $2 - JSONPath query (e.g., ".data.users[0].email")
# @return Extracted value (raw for primitives, JSON for objects/arrays)
jsonpath_query() {
    local json="$1"
    local path="$2"

    # Handle empty/root path
    if [[ -z "$path" || "$path" == "." || "$path" == "$" ]]; then
        printf '%s' "$json"
        return 0
    fi

    # Remove leading $ if present
    [[ "${path:0:1}" == '$' ]] && path="${path:1}"

    # Current value being operated on
    local current="$json"
    local pos=0
    local len=${#path}

    while (( pos < len )); do
        local char="${path:pos:1}"

        case "$char" in
            '.')
                # Property access
                ((pos++))
                local key=""
                while (( pos < len )) && [[ "${path:pos:1}" =~ [a-zA-Z0-9_] ]]; do
                    key+="${path:pos:1}"
                    ((pos++))
                done

                if [[ -z "$key" ]]; then
                    return "$JSONPATH_E_INVALID_PATH"
                fi

                _jp_object_get "$current" "$key" || return $?
                current="$_JP_RESULT"
                ;;

            '[')
                # Array access
                ((pos++))

                if [[ "${path:pos:1}" == '*' ]]; then
                    # Wildcard
                    ((pos++))
                    [[ "${path:pos:1}" != ']' ]] && return "$JSONPATH_E_INVALID_PATH"
                    ((pos++))

                    _jp_array_all "$current" || return $?
                    current="$_JP_RESULT"
                else
                    # Numeric index
                    local idx_str=""
                    if [[ "${path:pos:1}" == '-' ]]; then
                        idx_str="-"
                        ((pos++))
                    fi
                    while (( pos < len )) && [[ "${path:pos:1}" =~ [0-9] ]]; do
                        idx_str+="${path:pos:1}"
                        ((pos++))
                    done

                    [[ "${path:pos:1}" != ']' ]] && return "$JSONPATH_E_INVALID_PATH"
                    ((pos++))

                    _jp_array_get "$current" "$idx_str" || return $?
                    current="$_JP_RESULT"
                fi
                ;;

            *)
                return "$JSONPATH_E_INVALID_PATH"
                ;;
        esac
    done

    # Unquote string results
    if [[ "$current" =~ ^\"(.*)\"$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        printf '%s' "$current"
    fi

    return 0
}

# Nameref variant - stores result in variable (no subshell)
# @param $1 - variable name for result
# @param $2 - JSON string
# @param $3 - JSONPath query
# @return 0 on success, error code on failure
jsonpath_query_v() {
    local -n __jpqv_out=$1
    local json="$2"
    local path="$3"

    local tmpfile="${TMPDIR:-/tmp}/jsonpath_$$_$RANDOM"

    if jsonpath_query "$json" "$path" > "$tmpfile" 2>/dev/null; then
        __jpqv_out=$(<"$tmpfile")
        rm -f "$tmpfile"
        return 0
    else
        local rc=$?
        rm -f "$tmpfile"
        __jpqv_out=""
        return $rc
    fi
}

# Check if path exists in JSON
# @param $1 - JSON string
# @param $2 - JSONPath query
# @return 0 if exists, 1 if not
jsonpath_exists() {
    local json="$1"
    local path="$2"

    jsonpath_query "$json" "$path" > /dev/null 2>&1
}

# Get the JSON type at a path
# @param $1 - JSON string
# @param $2 - JSONPath query
# @return "string", "number", "boolean", "null", "object", "array", or "undefined"
jsonpath_type() {
    local json="$1"
    local path="$2"

    local value
    value=$(jsonpath_query "$json" "$path" 2>/dev/null)
    local rc=$?

    if [[ $rc -ne 0 ]]; then
        printf 'undefined'
        return 1
    fi

    case "$value" in
        null)
            printf 'null'
            ;;
        true|false)
            printf 'boolean'
            ;;
        \{*)
            printf 'object'
            ;;
        \[*)
            printf 'array'
            ;;
        *)
            if [[ "$value" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]; then
                printf 'number'
            else
                printf 'string'
            fi
            ;;
    esac
}

# Get length of array at path
# @param $1 - JSON string
# @param $2 - JSONPath query (optional, defaults to root)
# @return Array length or -1 on error
jsonpath_length() {
    local json="$1"
    local path="${2:-.}"

    local arr
    arr=$(jsonpath_query "$json" "$path" 2>/dev/null) || { printf '%d' -1; return 1; }

    # Must be array
    [[ "${arr:0:1}" != '[' ]] && { printf '%d' -1; return 1; }

    # Count elements
    local pos=1
    local len=${#arr}
    local count=0

    pos=$(_jp_skip_ws "$arr" "$pos")
    [[ "${arr:pos:1}" == ']' ]] && { printf '%d' 0; return 0; }

    while (( pos < len )); do
        pos=$(_jp_skip_ws "$arr" "$pos")
        [[ "${arr:pos:1}" == ']' ]] && break
        pos=$(_jp_skip_value "$arr" "$pos")
        ((count++))
        pos=$(_jp_skip_ws "$arr" "$pos")
        local char="${arr:pos:1}"
        if [[ "$char" == ']' ]]; then
            break
        elif [[ "$char" == ',' ]]; then
            ((pos++))
        fi
    done

    printf '%d' "$count"
}

# Iterate over array elements
# @param $1 - JSON string
# @param $2 - JSONPath query (optional, defaults to root)
# @return One element per line
jsonpath_iterate() {
    local json="$1"
    local path="${2:-.}"

    local arr
    arr=$(jsonpath_query "$json" "$path" 2>/dev/null) || return 1

    [[ "${arr:0:1}" != '[' ]] && return 1

    local pos=1
    local len=${#arr}

    pos=$(_jp_skip_ws "$arr" "$pos")
    [[ "${arr:pos:1}" == ']' ]] && return 0

    while (( pos < len )); do
        pos=$(_jp_skip_ws "$arr" "$pos")
        [[ "${arr:pos:1}" == ']' ]] && break

        local value_start=$pos
        local value_end
        value_end=$(_jp_skip_value "$arr" "$pos")
        local elem="${arr:value_start:value_end-value_start}"

        # Unquote if string
        if [[ "$elem" =~ ^\"(.*)\"$ ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
        else
            printf '%s\n' "$elem"
        fi

        pos=$value_end
        pos=$(_jp_skip_ws "$arr" "$pos")
        local char="${arr:pos:1}"
        if [[ "$char" == ']' ]]; then
            break
        elif [[ "$char" == ',' ]]; then
            ((pos++))
        fi
    done
}

# Get all keys of an object
# @param $1 - JSON string
# @param $2 - JSONPath query (optional, defaults to root)
# @return One key per line
jsonpath_keys() {
    local json="$1"
    local path="${2:-.}"

    local obj
    obj=$(jsonpath_query "$json" "$path" 2>/dev/null) || return 1

    [[ "${obj:0:1}" != '{' ]] && return 1

    local pos=1
    local len=${#obj}

    pos=$(_jp_skip_ws "$obj" "$pos")
    [[ "${obj:pos:1}" == '}' ]] && return 0

    while (( pos < len )); do
        pos=$(_jp_skip_ws "$obj" "$pos")
        [[ "${obj:pos:1}" == '}' ]] && break
        [[ "${obj:pos:1}" != '"' ]] && return 1

        _jp_extract_string "$obj" "$pos" || return 1
        printf '%s\n' "$_JP_VALUE"
        pos=$_JP_END

        pos=$(_jp_skip_ws "$obj" "$pos")
        [[ "${obj:pos:1}" != ':' ]] && return 1
        ((pos++))

        pos=$(_jp_skip_value "$obj" "$pos")
        pos=$(_jp_skip_ws "$obj" "$pos")

        local char="${obj:pos:1}"
        if [[ "$char" == '}' ]]; then
            break
        elif [[ "$char" == ',' ]]; then
            ((pos++))
        fi
    done
}

# =============================================================================
# MODULE INFO
# =============================================================================

jsonpath_version() {
    cat << 'EOF'
jsonpath 1.1.0 - Pure Bash JSONPath Query Engine for MAINFRAME

Supported Syntax:
  .key           - Object property access
  [N]            - Array index (0-based)
  [-N]           - Negative index (from end)
  .a.b.c         - Chained property access
  [*]            - All array elements

Functions:
  jsonpath_query     - Extract value at path
  jsonpath_query_v   - Extract value (nameref variant)
  jsonpath_exists    - Check if path exists
  jsonpath_type      - Get type at path
  jsonpath_length    - Get array length
  jsonpath_iterate   - Iterate array elements
  jsonpath_keys      - Get object keys

Dependencies: None (pure bash)
Requires: Bash 4.0+
EOF
}

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/json.sh - Pure Bash JSON Generation
# =============================================================================
# Description: Create and manipulate JSON in pure bash
# Source: Inspired by github.com/h4l/json.bash
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_JSON_LOADED:-}" ]] && return 0
readonly _MAINFRAME_JSON_LOADED=1

# =============================================================================
# STRING ESCAPING
# =============================================================================

# Escape string for JSON
# Usage: json_escape "hello\nworld"
json_escape() {
    local str="$1"
    local result=""
    local i char

    for ((i=0; i<${#str}; i++)); do
        char="${str:i:1}"
        case "$char" in
            '"')  result+='\"' ;;
            '\')  result+='\\' ;;
            $'\b') result+='\b' ;;
            $'\f') result+='\f' ;;
            $'\n') result+='\n' ;;
            $'\r') result+='\r' ;;
            $'\t') result+='\t' ;;
            *)
                # Check for control characters
                if [[ "$char" < $'\x20' ]]; then
                    printf -v char '\\u%04x' "'$char"
                fi
                result+="$char"
                ;;
        esac
    done

    printf '%s' "$result"
}

# =============================================================================
# VALUE CREATION
# =============================================================================

# Create JSON string
# Usage: json_string "hello world"
json_string() {
    printf '"%s"' "$(json_escape "$1")"
}

# Create JSON number
# Usage: json_number 42
json_number() {
    # Validate it's a number
    if [[ "$1" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]; then
        printf '%s' "$1"
    else
        printf 'null'
        return 1
    fi
}

# Create JSON boolean
# Usage: json_bool true
json_bool() {
    case "${1,,}" in
        true|1|yes|on)  printf 'true' ;;
        false|0|no|off) printf 'false' ;;
        *) printf 'null'; return 1 ;;
    esac
}

# Create JSON null
# Usage: json_null
json_null() {
    printf 'null'
}

# Auto-detect type and create appropriate JSON value
# Usage: json_value "hello"
json_value() {
    local val="$1"
    local type="${2:-auto}"

    case "$type" in
        string) json_string "$val" ;;
        number) json_number "$val" ;;
        bool)   json_bool "$val" ;;
        null)   json_null ;;
        raw)    printf '%s' "$val" ;;
        auto)
            # Auto-detect type
            if [[ "$val" == "null" ]]; then
                json_null
            elif [[ "$val" == "true" || "$val" == "false" ]]; then
                printf '%s' "$val"
            elif [[ "$val" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]; then
                json_number "$val"
            else
                json_string "$val"
            fi
            ;;
    esac
}

# =============================================================================
# ARRAY CREATION
# =============================================================================

# Create JSON array from arguments
# Usage: json_array "a" "b" "c"
json_array() {
    local first=true
    printf '['
    for item in "$@"; do
        $first || printf ','
        first=false
        json_value "$item"
    done
    printf ']'
}

# Create JSON array with explicit types
# Usage: json_array_typed string "a" "b" "c"
json_array_typed() {
    local type="$1"
    shift
    local first=true

    printf '['
    for item in "$@"; do
        $first || printf ','
        first=false
        json_value "$item" "$type"
    done
    printf ']'
}

# Create JSON array from newline-separated string
# Usage: echo -e "a\nb\nc" | json_array_from_lines
json_array_from_lines() {
    local first=true
    printf '['
    while IFS= read -r line; do
        $first || printf ','
        first=false
        json_string "$line"
    done
    printf ']'
}

# =============================================================================
# OBJECT CREATION
# =============================================================================

# Create JSON object from key=value pairs
# Usage: json_object name="John" age:number=30 active:bool=true
json_object() {
    local first=true
    printf '{'

    for pair in "$@"; do
        $first || printf ','
        first=false

        local key type value

        # Parse key:type=value or key=value
        if [[ "$pair" =~ ^([^:=]+):([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            type="${BASH_REMATCH[2]}"
            value="${BASH_REMATCH[3]}"
        elif [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            type="auto"
            value="${BASH_REMATCH[2]}"
        else
            continue
        fi

        printf '"%s":' "$(json_escape "$key")"
        json_value "$value" "$type"
    done

    printf '}'
}

# Create JSON object from associative array
# Usage: declare -A data=([name]="John" [age]="30"); json_from_assoc data
json_from_assoc() {
    local -n arr="$1"
    local first=true

    printf '{'
    for key in "${!arr[@]}"; do
        $first || printf ','
        first=false
        printf '"%s":' "$(json_escape "$key")"
        json_value "${arr[$key]}"
    done
    printf '}'
}

# Create nested object
# Usage: json_nested "a.b.c" "value"
json_nested() {
    local path="$1"
    local value="$2"
    local IFS='.'
    local keys=($path)
    local depth=${#keys[@]}
    local i

    for ((i=0; i<depth; i++)); do
        printf '{"%s":' "$(json_escape "${keys[i]}")"
    done

    json_value "$value"

    for ((i=0; i<depth; i++)); do
        printf '}'
    done
}

# =============================================================================
# MERGING & MODIFICATION
# =============================================================================

# Merge multiple JSON objects (simple, top-level only)
# Usage: json_merge '{"a":1}' '{"b":2}'
json_merge() {
    local result="{"
    local first=true

    for json in "$@"; do
        # Strip outer braces and trim
        local inner="${json#\{}"
        inner="${inner%\}}"
        inner="${inner#"${inner%%[![:space:]]*}"}"
        inner="${inner%"${inner##*[![:space:]]}"}"

        if [[ -n "$inner" ]]; then
            $first || result+=","
            first=false
            result+="$inner"
        fi
    done

    result+="}"
    printf '%s' "$result"
}

# =============================================================================
# PRETTY PRINTING
# =============================================================================

# Simple pretty print (indentation only)
# Usage: json_pretty '{"a":1,"b":2}'
json_pretty() {
    local json="$1"
    local indent="${2:-  }"
    local level=0
    local in_string=false
    local char prev_char=""
    local i

    for ((i=0; i<${#json}; i++)); do
        char="${json:i:1}"

        if $in_string; then
            printf '%s' "$char"
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
            fi
        else
            case "$char" in
                '"')
                    printf '%s' "$char"
                    in_string=true
                    ;;
                '{' | '[')
                    ((level++)) || true
                    printf '%s\n' "$char"
                    printf '%s' "${indent:0:$((${#indent} * level))}"
                    ;;
                '}' | ']')
                    ((level--)) || true
                    printf '\n%s%s' "${indent:0:$((${#indent} * level))}" "$char"
                    ;;
                ',')
                    printf ',\n%s' "${indent:0:$((${#indent} * level))}"
                    ;;
                ':')
                    printf ': '
                    ;;
                ' ' | $'\t' | $'\n' | $'\r')
                    # Skip whitespace outside strings
                    ;;
                *)
                    printf '%s' "$char"
                    ;;
            esac
        fi

        prev_char="$char"
    done
    printf '\n'
}

# =============================================================================
# VALIDATION
# =============================================================================

# Basic JSON syntax validation (pure bash)
# Usage: json_valid '{"a":1}' && echo "valid"
json_valid() {
    local json="$1"
    local depth=0
    local in_string=false
    local prev_char=""
    local i char

    # Check for empty input
    [[ -z "${json//[[:space:]]/}" ]] && return 1

    for ((i=0; i<${#json}; i++)); do
        char="${json:i:1}"

        if $in_string; then
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
            fi
        else
            case "$char" in
                '"')
                    in_string=true
                    ;;
                '{' | '[')
                    ((depth++)) || true
                    ;;
                '}' | ']')
                    ((depth--)) || true
                    [[ $depth -lt 0 ]] && return 1
                    ;;
            esac
        fi

        prev_char="$char"
    done

    # Check balanced brackets and closed strings
    [[ $depth -eq 0 ]] && ! $in_string
}

# =============================================================================
# EXTRACTION (Basic)
# =============================================================================

# Extract string value by key (simple, top-level only)
# Usage: json_get '{"name":"John"}' "name"
json_get() {
    local json="$1"
    local key="$2"

    # Simple regex extraction for top-level string values
    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    # Try numeric value
    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*([0-9.-]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    # Try boolean/null
    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*(true|false|null) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

# Extract all keys (simple, top-level only)
# Usage: json_keys '{"a":1,"b":2}'
json_keys() {
    local json="$1"
    local in_string=false
    local key=""
    local depth=0
    local i char prev_char=""

    for ((i=0; i<${#json}; i++)); do
        char="${json:i:1}"

        if $in_string; then
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
                # Check if this is a key (followed by :)
                local rest="${json:i+1}"
                if [[ "${rest}" =~ ^[[:space:]]*: ]] && [[ $depth -eq 1 ]]; then
                    printf '%s\n' "$key"
                fi
                key=""
            else
                key+="$char"
            fi
        else
            case "$char" in
                '"')
                    in_string=true
                    key=""
                    ;;
                '{' | '[')
                    ((depth++)) || true
                    ;;
                '}' | ']')
                    ((depth--)) || true
                    ;;
            esac
        fi

        prev_char="$char"
    done
}

# =============================================================================
# FILE OPERATIONS
# =============================================================================

# Read JSON from file
# Usage: json_read "/path/to/file.json"
json_read() {
    [[ -f "$1" ]] && printf '%s' "$(<"$1")"
}

# Write JSON to file
# Usage: json_write "/path/to/file.json" '{"a":1}'
json_write() {
    printf '%s\n' "$2" > "$1"
}

# Write pretty JSON to file
# Usage: json_write_pretty "/path/to/file.json" '{"a":1}'
json_write_pretty() {
    json_pretty "$2" > "$1"
}

# =============================================================================
# NAMEREF VARIANTS (High-Performance)
# =============================================================================
# These _v variants use bash namerefs to avoid subshell overhead.
# Instead of: result=$(json_object "name=John")  # Creates subshell
# Use:        json_object_v result "name=John"   # No subshell
# =============================================================================

# Escape string for JSON into variable
# Usage: json_escape_v result_var "hello\nworld"
json_escape_v() {
    local -n __jev_out=$1
    local str="$2"
    local i char

    __jev_out=""
    for ((i=0; i<${#str}; i++)); do
        char="${str:i:1}"
        case "$char" in
            '"')  __jev_out+='\"' ;;
            '\')  __jev_out+='\\' ;;
            $'\b') __jev_out+='\b' ;;
            $'\f') __jev_out+='\f' ;;
            $'\n') __jev_out+='\n' ;;
            $'\r') __jev_out+='\r' ;;
            $'\t') __jev_out+='\t' ;;
            *)
                # Check for control characters
                if [[ "$char" < $'\x20' ]]; then
                    printf -v char '\\u%04x' "'$char"
                fi
                __jev_out+="$char"
                ;;
        esac
    done
}

# Create JSON string into variable
# Usage: json_string_v result_var "hello world"
json_string_v() {
    local -n __jsv_out=$1
    local __jsv_escaped
    json_escape_v __jsv_escaped "$2"
    __jsv_out="\"${__jsv_escaped}\""
}

# Create JSON number into variable
# Usage: json_number_v result_var 42
json_number_v() {
    local -n __jnv_out=$1
    if [[ "$2" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]; then
        __jnv_out="$2"
        return 0
    else
        __jnv_out="null"
        return 1
    fi
}

# Create JSON boolean into variable
# Usage: json_bool_v result_var true
json_bool_v() {
    local -n __jbv_out=$1
    case "${2,,}" in
        true|1|yes|on)  __jbv_out='true'; return 0 ;;
        false|0|no|off) __jbv_out='false'; return 0 ;;
        *) __jbv_out='null'; return 1 ;;
    esac
}

# Auto-detect type and create appropriate JSON value into variable
# Usage: json_value_v result_var "hello" [type]
json_value_v() {
    local -n __jvv_out=$1
    local val="$2"
    local type="${3:-auto}"
    local __jvv_temp

    case "$type" in
        string)
            json_string_v __jvv_temp "$val"
            __jvv_out="$__jvv_temp"
            ;;
        number)
            json_number_v __jvv_temp "$val"
            __jvv_out="$__jvv_temp"
            ;;
        bool)
            json_bool_v __jvv_temp "$val"
            __jvv_out="$__jvv_temp"
            ;;
        null)
            __jvv_out='null'
            ;;
        raw)
            __jvv_out="$val"
            ;;
        auto)
            # Auto-detect type
            if [[ "$val" == "null" ]]; then
                __jvv_out='null'
            elif [[ "$val" == "true" || "$val" == "false" ]]; then
                __jvv_out="$val"
            elif [[ "$val" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]; then
                json_number_v __jvv_temp "$val"
                __jvv_out="$__jvv_temp"
            else
                json_string_v __jvv_temp "$val"
                __jvv_out="$__jvv_temp"
            fi
            ;;
    esac
}

# Create JSON array from arguments into variable
# Usage: json_array_v result_var "a" "b" "c"
json_array_v() {
    local -n __jav_out=$1
    shift
    local first=true
    local __jav_item

    __jav_out='['
    for item in "$@"; do
        $first || __jav_out+=','
        first=false
        json_value_v __jav_item "$item"
        __jav_out+="$__jav_item"
    done
    __jav_out+=']'
}

# Create JSON array with explicit types into variable
# Usage: json_array_typed_v result_var string "a" "b" "c"
json_array_typed_v() {
    local -n __jatv_out=$1
    local type="$2"
    shift 2
    local first=true
    local __jatv_item

    __jatv_out='['
    for item in "$@"; do
        $first || __jatv_out+=','
        first=false
        json_value_v __jatv_item "$item" "$type"
        __jatv_out+="$__jatv_item"
    done
    __jatv_out+=']'
}

# Create JSON object from key=value pairs into variable
# Usage: json_object_v result_var name="John" age:number=30 active:bool=true
json_object_v() {
    local -n __jov_out=$1
    shift
    local first=true
    local __jov_key __jov_val

    __jov_out='{'
    for pair in "$@"; do
        local key type value

        # Parse key:type=value or key=value
        if [[ "$pair" =~ ^([^:=]+):([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            type="${BASH_REMATCH[2]}"
            value="${BASH_REMATCH[3]}"
        elif [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            type="auto"
            value="${BASH_REMATCH[2]}"
        else
            continue
        fi

        $first || __jov_out+=','
        first=false

        json_escape_v __jov_key "$key"
        json_value_v __jov_val "$value" "$type"
        __jov_out+="\"${__jov_key}\":${__jov_val}"
    done

    __jov_out+='}'
}

# Create JSON object from associative array into variable
# Usage: declare -A data=([name]="John" [age]="30"); json_from_assoc_v result_var data
json_from_assoc_v() {
    local -n __jfav_out=$1
    local -n __jfav_arr="$2"
    local first=true
    local __jfav_key __jfav_val

    __jfav_out='{'
    for key in "${!__jfav_arr[@]}"; do
        $first || __jfav_out+=','
        first=false
        json_escape_v __jfav_key "$key"
        json_value_v __jfav_val "${__jfav_arr[$key]}"
        __jfav_out+="\"${__jfav_key}\":${__jfav_val}"
    done
    __jfav_out+='}'
}

# Create nested object into variable
# Usage: json_nested_v result_var "a.b.c" "value"
json_nested_v() {
    local -n __jnev_out=$1
    local path="$2"
    local value="$3"
    local IFS='.'
    local keys=($path)
    local depth=${#keys[@]}
    local i
    local __jnev_key __jnev_val

    __jnev_out=""
    for ((i=0; i<depth; i++)); do
        json_escape_v __jnev_key "${keys[i]}"
        __jnev_out+="{\"${__jnev_key}\":"
    done

    json_value_v __jnev_val "$value"
    __jnev_out+="$__jnev_val"

    for ((i=0; i<depth; i++)); do
        __jnev_out+='}'
    done
}

# Extract value by key into variable (simple, top-level only)
# Usage: json_get_v result_var '{"name":"John"}' "name"
json_get_v() {
    local -n __jgv_out=$1
    local json="$2"
    local key="$3"

    # Simple regex extraction for top-level string values
    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        __jgv_out="${BASH_REMATCH[1]}"
        return 0
    fi

    # Try numeric value
    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*([0-9.-]+) ]]; then
        __jgv_out="${BASH_REMATCH[1]}"
        return 0
    fi

    # Try boolean/null
    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*(true|false|null) ]]; then
        __jgv_out="${BASH_REMATCH[1]}"
        return 0
    fi

    __jgv_out=""
    return 1
}

# Merge multiple JSON objects into variable (simple, top-level only)
# Usage: json_merge_v result_var '{"a":1}' '{"b":2}'
json_merge_v() {
    local -n __jmv_out=$1
    shift
    local first=true

    __jmv_out="{"
    for json in "$@"; do
        # Strip outer braces and trim
        local inner="${json#\{}"
        inner="${inner%\}}"
        inner="${inner#"${inner%%[![:space:]]*}"}"
        inner="${inner%"${inner##*[![:space:]]}"}"

        if [[ -n "$inner" ]]; then
            $first || __jmv_out+=","
            first=false
            __jmv_out+="$inner"
        fi
    done

    __jmv_out+="}"
}

# Pretty print JSON into variable
# Usage: json_pretty_v result_var '{"a":1,"b":2}' [indent]
json_pretty_v() {
    local -n __jpv_out=$1
    local json="$2"
    local indent="${3:-  }"
    local level=0
    local in_string=false
    local char prev_char=""
    local i
    local indent_str

    __jpv_out=""
    for ((i=0; i<${#json}; i++)); do
        char="${json:i:1}"

        if $in_string; then
            __jpv_out+="$char"
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
            fi
        else
            case "$char" in
                '"')
                    __jpv_out+="$char"
                    in_string=true
                    ;;
                '{' | '[')
                    ((level++)) || true
                    printf -v indent_str '%*s' $((${#indent} * level)) ''
                    # Replace spaces with indent pattern
                    indent_str="${indent_str// /${indent:0:1}}"
                    __jpv_out+="${char}"$'\n'"${indent_str:0:$((${#indent} * level))}"
                    ;;
                '}' | ']')
                    ((level--)) || true
                    printf -v indent_str '%*s' $((${#indent} * level)) ''
                    indent_str="${indent_str// /${indent:0:1}}"
                    __jpv_out+=$'\n'"${indent_str:0:$((${#indent} * level))}${char}"
                    ;;
                ',')
                    printf -v indent_str '%*s' $((${#indent} * level)) ''
                    indent_str="${indent_str// /${indent:0:1}}"
                    __jpv_out+=','$'\n'"${indent_str:0:$((${#indent} * level))}"
                    ;;
                ':')
                    __jpv_out+=': '
                    ;;
                ' ' | $'\t' | $'\n' | $'\r')
                    # Skip whitespace outside strings
                    ;;
                *)
                    __jpv_out+="$char"
                    ;;
            esac
        fi

        prev_char="$char"
    done
    __jpv_out+=$'\n'
}


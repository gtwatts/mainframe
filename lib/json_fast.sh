#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/json_fast.sh - Accelerated JSON Processing
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_JSON_FAST_LOADED:-}" ]] && return 0
readonly _MAINFRAME_JSON_FAST_LOADED=1

# =============================================================================
# FAST JSON ESCAPING
# =============================================================================

json_escape_fast() {
    local str="$1"
    
    if [[ "$str" != *[\"\\$'\b'$'\f'$'\n'$'\r'$'\t']* ]]; then
        printf '%s' "$str"
        return 0
    fi
    
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\b'/\\b}"
    str="${str//$'\f'/\\f}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    
    printf '%s' "$str"
}

json_escape_fast_v() {
    local -n __jefv_out=$1
    local str="$2"
    
    if [[ "$str" != *[\"\\$'\b'$'\f'$'\n'$'\r'$'\t']* ]]; then
        __jefv_out="$str"
        return 0
    fi
    
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\b'/\\b}"
    str="${str//$'\f'/\\f}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    
    __jefv_out="$str"
}

json_string_fast() {
    local escaped
    escaped=$(json_escape_fast "$1")
    printf '"%s"' "$escaped"
}

json_string_fast_v() {
    local -n __jsfv_out=$1
    local escaped
    json_escape_fast_v escaped "$2"
    __jsfv_out="\"${escaped}\""
}

# =============================================================================
# FAST JSON VALIDATION
# =============================================================================

json_valid_fast() {
    local json="$1"
    
    [[ -z "${json//[[:space:]]/}" ]] && return 1
    
    local first_char="${json:0:1}"
    local last_char="${json: -1:1}"
    
    [[ "$first_char" != "{" && "$first_char" != "[" ]] && return 1
    [[ "$first_char" == "{" && "$last_char" != "}" ]] && return 1
    [[ "$first_char" == "[" && "$last_char" != "]" ]] && return 1
    
    local depth=0 i char in_string=false prev_char=""
    
    for ((i=0; i<${#json}; i++)); do
        char="${json:i:1}"
        
        if $in_string; then
            if [[ "$char" == '"' && "$prev_char" != '\\' ]]; then
                in_string=false
            fi
        else
            case "$char" in
                '"') in_string=true ;;
                '{'|'[') ((depth++)) ;;
                '}'|']') 
                    ((depth--))
                    [[ $depth -lt 0 ]] && return 1
                    ;;
            esac
        fi
        
        [[ "$prev_char" == '\\' ]] && prev_char='' || prev_char="$char"
    done
    
    [[ $depth -eq 0 && "$in_string" == false ]]
}

# =============================================================================
# FAST JSON EXTRACTION
# =============================================================================

json_extract_fast() {
    local json="$1"
    local key="$2"
    local pattern
    
    pattern="\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
    if [[ "$json" =~ $pattern ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    
    pattern="\"$key\"[[:space:]]*:[[:space:]]*(-?[0-9]+)"
    if [[ "$json" =~ $pattern ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    
    pattern="\"$key\"[[:space:]]*:[[:space:]]*(true|false|null)"
    if [[ "$json" =~ $pattern ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    
    return 1
}

json_extract_fast_v() {
    local -n __jxfv_out=$1
    local json="$2"
    local key="$3"
    local pattern
    
    pattern="\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
    if [[ "$json" =~ $pattern ]]; then
        __jxfv_out="${BASH_REMATCH[1]}"
        return 0
    fi
    
    pattern="\"$key\"[[:space:]]*:[[:space:]]*(-?[0-9]+)"
    if [[ "$json" =~ $pattern ]]; then
        __jxfv_out="${BASH_REMATCH[1]}"
        return 0
    fi
    
    pattern="\"$key\"[[:space:]]*:[[:space:]]*(true|false|null)"
    if [[ "$json" =~ $pattern ]]; then
        __jxfv_out="${BASH_REMATCH[1]}"
        return 0
    fi
    
    __jxfv_out=""
    return 1
}

json_extract_multi() {
    local json="$1"
    shift
    local keys=("$@")
    
    local first=true
    printf '{'
    
    for key in "${keys[@]}"; do
        local value
        if json_extract_fast_v value "$json" "$key"; then
            $first || printf ','
            first=false
            printf '"%s":' "$key"
            if [[ "$value" =~ ^(true|false|null|-?[0-9]+)$ ]]; then
                printf '%s' "$value"
            else
                printf '"%s"' "$(json_escape_fast "$value")"
            fi
        fi
    done
    
    printf '}'
}

# =============================================================================
# FAST JSON MERGING
# =============================================================================

json_merge_fast() {
    local result="{"
    local first=true
    
    for json in "$@"; do
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
# FAST JSON ARRAY/OPERATIONS
# =============================================================================

json_array_fast() {
    local first=true
    printf '['
    for item in "$@"; do
        $first || printf ','
        first=false
        json_string_fast "$item"
    done
    printf ']'
}

json_array_fast_v() {
    local -n __jafv_out=$1
    shift
    local first=true
    local item escaped
    
    __jafv_out='['
    for item in "$@"; do
        $first || __jafv_out+=','
        first=false
        json_string_fast_v escaped "$item"
        __jafv_out+="$escaped"
    done
    __jafv_out+=']'
}

json_object_fast() {
    local first=true
    printf '{'
    
    for pair in "$@"; do
        local key type value
        
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
        
        $first || printf ','
        first=false
        
        local escaped_key
        escaped_key=$(json_escape_fast "$key")
        printf '"%s":' "$escaped_key"
        
        case "$type" in
            string)
                json_string_fast "$value"
                ;;
            number)
                if [[ "$value" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]; then
                    printf '%s' "$value"
                else
                    printf 'null'
                fi
                ;;
            bool)
                case "${value,,}" in
                    true|1|yes|on) printf 'true' ;;
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
            auto|*)
                if [[ "$value" == "null" ]]; then
                    printf 'null'
                elif [[ "$value" == "true" || "$value" == "false" ]]; then
                    printf '%s' "$value"
                elif [[ "$value" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]; then
                    printf '%s' "$value"
                else
                    json_string_fast "$value"
                fi
                ;;
        esac
    done
    
    printf '}'
}

json_object_fast_v() {
    local -n __jofv_out=$1
    shift
    local first=true
    local pair key type value escaped
    
    __jofv_out='{'
    
    for pair in "$@"; do
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
        
        $first || __jofv_out+=','
        first=false
        
        json_escape_fast_v escaped "$key"
        __jofv_out+="\"${escaped}\":"
        
        case "$type" in
            string)
                json_string_fast_v escaped "$value"
                __jofv_out+="$escaped"
                ;;
            number)
                if [[ "$value" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]; then
                    __jofv_out+="$value"
                else
                    __jofv_out+='null'
                fi
                ;;
            bool)
                case "${value,,}" in
                    true|1|yes|on) __jofv_out+='true' ;;
                    false|0|no|off) __jofv_out+='false' ;;
                    *) __jofv_out+='null' ;;
                esac
                ;;
            null)
                __jofv_out+='null'
                ;;
            raw)
                __jofv_out+="$value"
                ;;
            auto|*)
                if [[ "$value" == "null" ]]; then
                    __jofv_out+='null'
                elif [[ "$value" == "true" || "$value" == "false" ]]; then
                    __jofv_out+="$value"
                elif [[ "$value" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]; then
                    __jofv_out+="$value"
                else
                    json_string_fast_v escaped "$value"
                    __jofv_out+="$escaped"
                fi
                ;;
        esac
    done
    
    __jofv_out+='}'
}

# =============================================================================
# BENCHMARKING
# =============================================================================

json_fast_benchmark() {
    local iterations="${1:-1000}"
    local test_str='Hello "World" with \ backslash'
    
    printf 'JSON Fast Benchmark (%d iterations)\n' "$iterations"
    printf 'Test string length: %d chars\n' "${#test_str}"
    printf '\n'
    
    local start end fast_ms
    start=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")
    for ((i=0; i<iterations; i++)); do
        json_escape_fast "$test_str" >/dev/null
    done
    end=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")
    fast_ms=$(( (end - start) / 1000000 ))
    
    printf 'json_escape_fast:  %d ms\n' "$fast_ms"
    
    printf '\nCorrectness check:\n'
    local result
    result=$(json_escape_fast '"hello\world')
    printf '  Escape sequences result: %s\n' "$result"
    
    result=$(json_escape_fast "no special")
    if [[ "$result" == "no special" ]]; then
        printf '  Fast path: PASS\n'
    else
        printf '  Fast path: FAIL (got: %s)\n' "$result"
    fi
}

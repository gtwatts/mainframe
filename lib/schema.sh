#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/schema.sh - JSON Schema Validation Library
# =============================================================================
# Description: Pure bash JSON Schema validation (subset of draft 2020-12)
#              For structured data validation between agents
# Dependencies: json.sh (for parsing and generation)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_SCHEMA_LOADED:-}" ]] && return 0
readonly _MAINFRAME_SCHEMA_LOADED=1

# =============================================================================
# SCHEMA REGISTRY
# =============================================================================
# Global associative array to store registered schemas
# Key: schema name, Value: schema JSON
declare -gA _SCHEMA_REGISTRY

# Global array to store validation errors from last validation
declare -ga _SCHEMA_ERRORS

# =============================================================================
# SCHEMA DEFINITION FUNCTIONS
# =============================================================================

# Register a schema by name
# Usage: schema_define "User" '{"type":"object",...}'
# Returns: 0 on success, 1 on invalid JSON
schema_define() {
    local name="$1"
    local schema_json="$2"

    [[ -z "$name" ]] && return 1
    [[ -z "$schema_json" ]] && return 1

    # Validate the schema is valid JSON
    if ! json_valid "$schema_json"; then
        return 1
    fi

    _SCHEMA_REGISTRY["$name"]="$schema_json"
    return 0
}

# Load schema from file
# Usage: schema_load "User" "/path/to/schema.json"
# Returns: 0 on success, 1 on failure
schema_load() {
    local name="$1"
    local file="$2"

    [[ -z "$name" ]] && return 1
    [[ -z "$file" ]] && return 1
    [[ ! -f "$file" ]] && return 1

    local schema_json
    schema_json=$(<"$file")

    schema_define "$name" "$schema_json"
}

# List all registered schema names
# Usage: schema_list
# Output: One schema name per line
schema_list() {
    local name
    for name in "${!_SCHEMA_REGISTRY[@]}"; do
        printf '%s\n' "$name"
    done | sort
}

# Get schema definition by name
# Usage: schema_get "User"
# Output: Schema JSON
# Returns: 0 on success, 1 if not found
schema_get() {
    local name="$1"

    [[ -z "$name" ]] && return 1
    [[ -z "${_SCHEMA_REGISTRY[$name]:-}" ]] && return 1

    printf '%s' "${_SCHEMA_REGISTRY[$name]}"
    return 0
}

# Remove a schema from registry
# Usage: schema_undefine "User"
# Returns: 0 on success, 1 if not found
schema_undefine() {
    local name="$1"

    [[ -z "$name" ]] && return 1
    [[ -z "${_SCHEMA_REGISTRY[$name]:-}" ]] && return 1

    unset "_SCHEMA_REGISTRY[$name]"
    return 0
}

# Clear all registered schemas
# Usage: schema_clear
schema_clear() {
    _SCHEMA_REGISTRY=()
}

# =============================================================================
# INTERNAL PARSING HELPERS
# =============================================================================

# Extract a string value from JSON by key (handles nested quotes)
# Usage: _schema_get_string '{"type":"object"}' "type"
_schema_get_string() {
    local json="$1"
    local key="$2"

    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

# Extract a number value from JSON by key
# Usage: _schema_get_number '{"minimum":0}' "minimum"
_schema_get_number() {
    local json="$1"
    local key="$2"

    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*(-?[0-9]+\.?[0-9]*) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

# Extract a boolean value from JSON by key
# Usage: _schema_get_bool '{"required":true}' "required"
_schema_get_bool() {
    local json="$1"
    local key="$2"

    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

# Extract an array from JSON by key (returns the array including brackets)
# Usage: _schema_get_array '{"required":["a","b"]}' "required"
_schema_get_array() {
    local json="$1"
    local key="$2"
    local result=""
    local depth=0
    local in_string=false
    local started=false
    local i char prev_char=""

    # Find the key position
    local key_pattern="\"$key\""
    local key_pos=-1
    local search_pos=0

    while [[ $search_pos -lt ${#json} ]]; do
        if [[ "${json:search_pos}" == "$key_pattern"* ]]; then
            key_pos=$search_pos
            break
        fi
        ((search_pos++))
    done

    [[ $key_pos -lt 0 ]] && return 1

    # Find the opening bracket after the key
    local start_pos=$((key_pos + ${#key_pattern}))
    while [[ $start_pos -lt ${#json} ]]; do
        char="${json:start_pos:1}"
        if [[ "$char" == "[" ]]; then
            break
        elif [[ "$char" == ":" || "$char" == " " || "$char" == $'\t' || "$char" == $'\n' ]]; then
            ((start_pos++))
        else
            return 1
        fi
    done

    # Extract the array
    for ((i=start_pos; i<${#json}; i++)); do
        char="${json:i:1}"

        if $in_string; then
            result+="$char"
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
            fi
        else
            case "$char" in
                '"')
                    result+="$char"
                    in_string=true
                    ;;
                '[')
                    result+="$char"
                    ((depth++))
                    started=true
                    ;;
                ']')
                    result+="$char"
                    ((depth--))
                    if [[ $depth -eq 0 ]]; then
                        printf '%s' "$result"
                        return 0
                    fi
                    ;;
                *)
                    if $started; then
                        result+="$char"
                    fi
                    ;;
            esac
        fi
        prev_char="$char"
    done

    return 1
}

# Extract an object from JSON by key
# Usage: _schema_get_object '{"properties":{"name":{}}}' "properties"
_schema_get_object() {
    local json="$1"
    local key="$2"
    local result=""
    local depth=0
    local in_string=false
    local started=false
    local i char prev_char=""

    # Find the key position
    local key_pattern="\"$key\""
    local key_pos=-1
    local search_pos=0

    while [[ $search_pos -lt ${#json} ]]; do
        if [[ "${json:search_pos}" == "$key_pattern"* ]]; then
            key_pos=$search_pos
            break
        fi
        ((search_pos++))
    done

    [[ $key_pos -lt 0 ]] && return 1

    # Find the opening brace after the key
    local start_pos=$((key_pos + ${#key_pattern}))
    while [[ $start_pos -lt ${#json} ]]; do
        char="${json:start_pos:1}"
        if [[ "$char" == "{" ]]; then
            break
        elif [[ "$char" == ":" || "$char" == " " || "$char" == $'\t' || "$char" == $'\n' ]]; then
            ((start_pos++))
        else
            return 1
        fi
    done

    # Extract the object
    for ((i=start_pos; i<${#json}; i++)); do
        char="${json:i:1}"

        if $in_string; then
            result+="$char"
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
            fi
        else
            case "$char" in
                '"')
                    result+="$char"
                    in_string=true
                    ;;
                '{')
                    result+="$char"
                    ((depth++))
                    started=true
                    ;;
                '}')
                    result+="$char"
                    ((depth--))
                    if [[ $depth -eq 0 ]]; then
                        printf '%s' "$result"
                        return 0
                    fi
                    ;;
                *)
                    if $started; then
                        result+="$char"
                    fi
                    ;;
            esac
        fi
        prev_char="$char"
    done

    return 1
}

# Parse array elements (strings only)
# Usage: _schema_parse_array '["a","b","c"]'
# Output: One element per line (unquoted)
_schema_parse_array() {
    local arr="$1"
    local in_string=false
    local current=""
    local i char prev_char=""

    for ((i=0; i<${#arr}; i++)); do
        char="${arr:i:1}"

        if $in_string; then
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
                printf '%s\n' "$current"
                current=""
            else
                current+="$char"
            fi
        else
            if [[ "$char" == '"' ]]; then
                in_string=true
            fi
        fi
        prev_char="$char"
    done
}

# Get the type of a JSON value
# Usage: _schema_value_type '"hello"'  # returns "string"
_schema_value_type() {
    local value="$1"

    # Trim whitespace
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    [[ -z "$value" ]] && { printf 'null'; return; }

    case "${value:0:1}" in
        '"') printf 'string' ;;
        '{') printf 'object' ;;
        '[') printf 'array' ;;
        't'|'f')
            if [[ "$value" == "true" || "$value" == "false" ]]; then
                printf 'boolean'
            else
                printf 'unknown'
            fi
            ;;
        'n')
            if [[ "$value" == "null" ]]; then
                printf 'null'
            else
                printf 'unknown'
            fi
            ;;
        '-'|[0-9])
            if [[ "$value" =~ ^-?[0-9]+$ ]]; then
                printf 'integer'
            elif [[ "$value" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]; then
                printf 'number'
            else
                printf 'unknown'
            fi
            ;;
        *) printf 'unknown' ;;
    esac
}

# Extract raw value from JSON (with quotes for strings)
# Usage: _schema_get_value '{"name":"John"}' "name"
_schema_get_value() {
    local json="$1"
    local key="$2"
    local result=""
    local depth=0
    local in_string=false
    local started=false
    local i char prev_char=""

    # Find the key position
    local key_pattern="\"$key\""
    local key_pos=-1
    local search_pos=0

    while [[ $search_pos -lt ${#json} ]]; do
        if [[ "${json:search_pos}" == "$key_pattern"* ]]; then
            key_pos=$search_pos
            break
        fi
        ((search_pos++))
    done

    [[ $key_pos -lt 0 ]] && return 1

    # Skip to the colon
    local start_pos=$((key_pos + ${#key_pattern}))
    while [[ $start_pos -lt ${#json} ]]; do
        char="${json:start_pos:1}"
        if [[ "$char" == ":" ]]; then
            ((start_pos++))
            break
        fi
        ((start_pos++))
    done

    # Skip whitespace
    while [[ $start_pos -lt ${#json} ]]; do
        char="${json:start_pos:1}"
        if [[ "$char" != " " && "$char" != $'\t' && "$char" != $'\n' ]]; then
            break
        fi
        ((start_pos++))
    done

    # Determine value type and extract
    local first_char="${json:start_pos:1}"
    case "$first_char" in
        '"')
            # String value
            result='"'
            for ((i=start_pos+1; i<${#json}; i++)); do
                char="${json:i:1}"
                result+="$char"
                if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                    printf '%s' "$result"
                    return 0
                fi
                prev_char="$char"
            done
            ;;
        '{')
            # Object
            _schema_get_object "$json" "$key"
            return $?
            ;;
        '[')
            # Array
            _schema_get_array "$json" "$key"
            return $?
            ;;
        *)
            # Number, boolean, or null
            for ((i=start_pos; i<${#json}; i++)); do
                char="${json:i:1}"
                if [[ "$char" == "," || "$char" == "}" || "$char" == "]" || "$char" == " " || "$char" == $'\n' ]]; then
                    printf '%s' "$result"
                    return 0
                fi
                result+="$char"
            done
            printf '%s' "$result"
            return 0
            ;;
    esac

    return 1
}

# Add an error to the error list
# Usage: _schema_add_error "path" "message"
_schema_add_error() {
    local path="$1"
    local message="$2"
    _SCHEMA_ERRORS+=("$path: $message")
}

# =============================================================================
# TYPE VALIDATORS
# =============================================================================

# Validate string type with constraints
# Usage: _schema_validate_string "value" "schema" "path"
_schema_validate_string() {
    local value="$1"
    local schema="$2"
    local path="$3"

    # Remove quotes from string value
    local str="${value:1:-1}"

    # Check minLength
    local min_len
    if min_len=$(_schema_get_number "$schema" "minLength"); then
        if (( ${#str} < min_len )); then
            _schema_add_error "$path" "string length ${#str} is less than minimum $min_len"
            return 1
        fi
    fi

    # Check maxLength
    local max_len
    if max_len=$(_schema_get_number "$schema" "maxLength"); then
        if (( ${#str} > max_len )); then
            _schema_add_error "$path" "string length ${#str} exceeds maximum $max_len"
            return 1
        fi
    fi

    # Check pattern
    local pattern
    if pattern=$(_schema_get_string "$schema" "pattern"); then
        if [[ ! "$str" =~ $pattern ]]; then
            _schema_add_error "$path" "string does not match pattern '$pattern'"
            return 1
        fi
    fi

    # Check format (built-in formats)
    local format
    if format=$(_schema_get_string "$schema" "format"); then
        case "$format" in
            email)
                if [[ ! "$str" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
                    _schema_add_error "$path" "string is not a valid email format"
                    return 1
                fi
                ;;
            uri|url)
                if [[ ! "$str" =~ ^https?:// ]]; then
                    _schema_add_error "$path" "string is not a valid URL format"
                    return 1
                fi
                ;;
            uuid)
                if [[ ! "$str" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
                    _schema_add_error "$path" "string is not a valid UUID format"
                    return 1
                fi
                ;;
            date)
                if [[ ! "$str" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
                    _schema_add_error "$path" "string is not a valid date format (YYYY-MM-DD)"
                    return 1
                fi
                ;;
            date-time)
                if [[ ! "$str" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
                    _schema_add_error "$path" "string is not a valid date-time format"
                    return 1
                fi
                ;;
            ipv4)
                if [[ ! "$str" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                    _schema_add_error "$path" "string is not a valid IPv4 format"
                    return 1
                fi
                ;;
        esac
    fi

    return 0
}

# Validate number/integer type with constraints
# Usage: _schema_validate_number "value" "schema" "path" "is_integer"
_schema_validate_number() {
    local value="$1"
    local schema="$2"
    local path="$3"
    local is_integer="${4:-false}"

    local num="$value"

    # Check minimum
    local min
    if min=$(_schema_get_number "$schema" "minimum"); then
        if (( $(echo "$num < $min" | bc -l 2>/dev/null || echo 0) )); then
            _schema_add_error "$path" "number $num is less than minimum $min"
            return 1
        fi
    fi

    # Check maximum
    local max
    if max=$(_schema_get_number "$schema" "maximum"); then
        if (( $(echo "$num > $max" | bc -l 2>/dev/null || echo 0) )); then
            _schema_add_error "$path" "number $num exceeds maximum $max"
            return 1
        fi
    fi

    # Check exclusiveMinimum
    local exc_min
    if exc_min=$(_schema_get_number "$schema" "exclusiveMinimum"); then
        if (( $(echo "$num <= $exc_min" | bc -l 2>/dev/null || echo 0) )); then
            _schema_add_error "$path" "number $num must be greater than $exc_min"
            return 1
        fi
    fi

    # Check exclusiveMaximum
    local exc_max
    if exc_max=$(_schema_get_number "$schema" "exclusiveMaximum"); then
        if (( $(echo "$num >= $exc_max" | bc -l 2>/dev/null || echo 0) )); then
            _schema_add_error "$path" "number $num must be less than $exc_max"
            return 1
        fi
    fi

    return 0
}

# Validate array type with constraints
# Usage: _schema_validate_array "value" "schema" "path"
_schema_validate_array() {
    local value="$1"
    local schema="$2"
    local path="$3"

    # Count array elements
    local count=0
    local depth=0
    local in_string=false
    local i char prev_char=""

    for ((i=0; i<${#value}; i++)); do
        char="${value:i:1}"

        if $in_string; then
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
            fi
        else
            case "$char" in
                '"') in_string=true ;;
                '[') ((depth++)) ;;
                ']') ((depth--)) ;;
                ',')
                    if [[ $depth -eq 1 ]]; then
                        ((count++))
                    fi
                    ;;
            esac
        fi
        prev_char="$char"
    done

    # Adjust count (if array is non-empty, count commas + 1)
    if [[ "$value" != "[]" ]]; then
        ((count++))
    fi

    # Check minItems
    local min_items
    if min_items=$(_schema_get_number "$schema" "minItems"); then
        if (( count < min_items )); then
            _schema_add_error "$path" "array has $count items, minimum is $min_items"
            return 1
        fi
    fi

    # Check maxItems
    local max_items
    if max_items=$(_schema_get_number "$schema" "maxItems"); then
        if (( count > max_items )); then
            _schema_add_error "$path" "array has $count items, maximum is $max_items"
            return 1
        fi
    fi

    # Validate items schema if present
    local items_schema
    if items_schema=$(_schema_get_object "$schema" "items"); then
        local item_index=0
        local current_item=""
        local item_depth=0
        local item_in_string=false

        for ((i=1; i<${#value}-1; i++)); do
            char="${value:i:1}"

            if $item_in_string; then
                current_item+="$char"
                if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                    item_in_string=false
                fi
            else
                case "$char" in
                    '"')
                        current_item+="$char"
                        item_in_string=true
                        ;;
                    '['|'{')
                        current_item+="$char"
                        ((item_depth++))
                        ;;
                    ']'|'}')
                        current_item+="$char"
                        ((item_depth--))
                        ;;
                    ',')
                        if [[ $item_depth -eq 0 ]]; then
                            # Trim and validate item
                            current_item="${current_item#"${current_item%%[![:space:]]*}"}"
                            current_item="${current_item%"${current_item##*[![:space:]]}"}"
                            if [[ -n "$current_item" ]]; then
                                if ! _schema_validate_value "$current_item" "$items_schema" "${path}[$item_index]"; then
                                    return 1
                                fi
                            fi
                            ((item_index++))
                            current_item=""
                        else
                            current_item+="$char"
                        fi
                        ;;
                    ' '|$'\t'|$'\n')
                        if [[ -n "$current_item" ]]; then
                            current_item+="$char"
                        fi
                        ;;
                    *)
                        current_item+="$char"
                        ;;
                esac
            fi
            prev_char="$char"
        done

        # Handle last item
        current_item="${current_item#"${current_item%%[![:space:]]*}"}"
        current_item="${current_item%"${current_item##*[![:space:]]}"}"
        if [[ -n "$current_item" ]]; then
            if ! _schema_validate_value "$current_item" "$items_schema" "${path}[$item_index]"; then
                return 1
            fi
        fi
    fi

    return 0
}

# Validate object type with constraints
# Usage: _schema_validate_object "value" "schema" "path"
_schema_validate_object() {
    local value="$1"
    local schema="$2"
    local path="$3"

    # Check required properties
    local required_arr
    if required_arr=$(_schema_get_array "$schema" "required"); then
        local req_props
        req_props=$(_schema_parse_array "$required_arr")
        while IFS= read -r prop; do
            [[ -z "$prop" ]] && continue
            if ! _schema_get_value "$value" "$prop" >/dev/null 2>&1; then
                _schema_add_error "$path" "missing required property '$prop'"
                return 1
            fi
        done <<< "$req_props"
    fi

    # Validate properties
    local properties_schema
    if properties_schema=$(_schema_get_object "$schema" "properties"); then
        # Extract property names from properties schema
        local prop_keys
        prop_keys=$(json_keys "$properties_schema")

        while IFS= read -r prop; do
            [[ -z "$prop" ]] && continue

            local prop_value
            if prop_value=$(_schema_get_value "$value" "$prop"); then
                local prop_schema
                if prop_schema=$(_schema_get_object "$properties_schema" "$prop"); then
                    if ! _schema_validate_value "$prop_value" "$prop_schema" "${path}.${prop}"; then
                        return 1
                    fi
                fi
            fi
        done <<< "$prop_keys"
    fi

    return 0
}

# Main validation dispatcher
# Usage: _schema_validate_value "value" "schema" "path"
_schema_validate_value() {
    local value="$1"
    local schema="$2"
    local path="${3:-$}"

    # Get expected type from schema
    local expected_type
    expected_type=$(_schema_get_string "$schema" "type")

    # Get actual type of value
    local actual_type
    actual_type=$(_schema_value_type "$value")

    # Check enum constraint
    local enum_arr
    if enum_arr=$(_schema_get_array "$schema" "enum"); then
        local found=false
        local enum_vals
        enum_vals=$(_schema_parse_array "$enum_arr")

        # For strings, compare without quotes
        local compare_value="$value"
        if [[ "$actual_type" == "string" ]]; then
            compare_value="${value:1:-1}"
        fi

        while IFS= read -r enum_val; do
            [[ -z "$enum_val" ]] && continue
            if [[ "$compare_value" == "$enum_val" ]]; then
                found=true
                break
            fi
        done <<< "$enum_vals"

        if ! $found; then
            _schema_add_error "$path" "value '$value' is not in enum"
            return 1
        fi
    fi

    # Type validation
    if [[ -n "$expected_type" ]]; then
        case "$expected_type" in
            string)
                if [[ "$actual_type" != "string" ]]; then
                    _schema_add_error "$path" "expected string, got $actual_type"
                    return 1
                fi
                _schema_validate_string "$value" "$schema" "$path" || return 1
                ;;
            number)
                if [[ "$actual_type" != "number" && "$actual_type" != "integer" ]]; then
                    _schema_add_error "$path" "expected number, got $actual_type"
                    return 1
                fi
                _schema_validate_number "$value" "$schema" "$path" || return 1
                ;;
            integer)
                if [[ "$actual_type" != "integer" ]]; then
                    _schema_add_error "$path" "expected integer, got $actual_type"
                    return 1
                fi
                _schema_validate_number "$value" "$schema" "$path" true || return 1
                ;;
            boolean)
                if [[ "$actual_type" != "boolean" ]]; then
                    _schema_add_error "$path" "expected boolean, got $actual_type"
                    return 1
                fi
                ;;
            array)
                if [[ "$actual_type" != "array" ]]; then
                    _schema_add_error "$path" "expected array, got $actual_type"
                    return 1
                fi
                _schema_validate_array "$value" "$schema" "$path" || return 1
                ;;
            object)
                if [[ "$actual_type" != "object" ]]; then
                    _schema_add_error "$path" "expected object, got $actual_type"
                    return 1
                fi
                _schema_validate_object "$value" "$schema" "$path" || return 1
                ;;
            null)
                if [[ "$actual_type" != "null" ]]; then
                    _schema_add_error "$path" "expected null, got $actual_type"
                    return 1
                fi
                ;;
        esac
    else
        # No type specified, validate nested constraints if object
        if [[ "$actual_type" == "object" ]]; then
            _schema_validate_object "$value" "$schema" "$path" || return 1
        elif [[ "$actual_type" == "array" ]]; then
            _schema_validate_array "$value" "$schema" "$path" || return 1
        fi
    fi

    return 0
}

# =============================================================================
# PUBLIC VALIDATION FUNCTIONS
# =============================================================================

# Validate JSON data against a registered schema
# Usage: schema_validate "User" '{"id":"abc","email":"user@example.com"}'
# Returns: 0 if valid, 1 if invalid
schema_validate() {
    local name="$1"
    local data="$2"

    [[ -z "$name" ]] && return 1
    [[ -z "$data" ]] && return 1

    local schema
    schema=$(schema_get "$name") || return 1

    # Clear previous errors
    _SCHEMA_ERRORS=()

    # Validate the data is valid JSON
    if ! json_valid "$data"; then
        _SCHEMA_ERRORS+=("$: invalid JSON")
        return 1
    fi

    _schema_validate_value "$data" "$schema" "$"
}

# Validate JSON file contents against a registered schema
# Usage: schema_validate_file "User" "/path/to/data.json"
# Returns: 0 if valid, 1 if invalid
schema_validate_file() {
    local name="$1"
    local file="$2"

    [[ -z "$name" ]] && return 1
    [[ -z "$file" ]] && return 1
    [[ ! -f "$file" ]] && return 1

    local data
    data=$(<"$file")

    schema_validate "$name" "$data"
}

# Get validation errors from last validation as JSON array
# Usage: schema_errors "User" '{"bad":"data"}'
# Output: JSON array of error messages
schema_errors() {
    local name="$1"
    local data="$2"

    # Run validation to populate errors
    schema_validate "$name" "$data"

    # Output errors as JSON array
    local first=true
    printf '['
    for err in "${_SCHEMA_ERRORS[@]}"; do
        $first || printf ','
        first=false
        json_string "$err"
    done
    printf ']'
}

# Get errors from last validation (without re-validating)
# Usage: schema_last_errors
# Output: JSON array of error messages
schema_last_errors() {
    local first=true
    printf '['
    for err in "${_SCHEMA_ERRORS[@]}"; do
        $first || printf ','
        first=false
        json_string "$err"
    done
    printf ']'
}

# =============================================================================
# BUILT-IN SCHEMAS
# =============================================================================

# Email validation schema
# Usage: schema_builtin_email
# Output: Schema JSON for email validation
schema_builtin_email() {
    printf '%s' '{"type":"string","format":"email"}'
}

# UUID v4 validation schema
# Usage: schema_builtin_uuid
# Output: Schema JSON for UUID v4 validation
schema_builtin_uuid() {
    printf '%s' '{"type":"string","format":"uuid","pattern":"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"}'
}

# URL validation schema
# Usage: schema_builtin_url
# Output: Schema JSON for URL validation
schema_builtin_url() {
    printf '%s' '{"type":"string","format":"uri","pattern":"^https?://[^[:space:]]+"}'
}

# Semantic version validation schema
# Usage: schema_builtin_semver
# Output: Schema JSON for semver validation
schema_builtin_semver() {
    printf '%s' '{"type":"string","pattern":"^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?$"}'
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Register built-in schemas
# Usage: schema_register_builtins
schema_register_builtins() {
    schema_define "builtin:email" "$(schema_builtin_email)"
    schema_define "builtin:uuid" "$(schema_builtin_uuid)"
    schema_define "builtin:url" "$(schema_builtin_url)"
    schema_define "builtin:semver" "$(schema_builtin_semver)"
}

# Quick validation without registering schema
# Usage: schema_check '{"type":"string","minLength":1}' '"hello"'
# Returns: 0 if valid, 1 if invalid
schema_check() {
    local schema="$1"
    local data="$2"

    [[ -z "$schema" ]] && return 1
    [[ -z "$data" ]] && return 1

    # Clear previous errors
    _SCHEMA_ERRORS=()

    # Validate schema is valid JSON
    if ! json_valid "$schema"; then
        _SCHEMA_ERRORS+=("schema: invalid JSON")
        return 1
    fi

    # Validate the data is valid JSON
    if ! json_valid "$data"; then
        _SCHEMA_ERRORS+=("$: invalid JSON")
        return 1
    fi

    _schema_validate_value "$data" "$schema" "$"
}

# =============================================================================
# NAMEREF VARIANTS (High-Performance)
# =============================================================================

# Validate and store result in variable
# Usage: schema_validate_v result_var "User" '{"id":"abc"}'
# Sets result_var to "true" or "false"
schema_validate_v() {
    local -n __sv_out=$1
    local name="$2"
    local data="$3"

    if schema_validate "$name" "$data"; then
        __sv_out="true"
    else
        __sv_out="false"
    fi
}

# Get errors into variable
# Usage: schema_errors_v result_var "User" '{"bad":"data"}'
schema_errors_v() {
    local -n __sev_out=$1
    local name="$2"
    local data="$3"

    __sev_out=$(schema_errors "$name" "$data")
}

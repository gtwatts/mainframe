#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/immutable.sh - Immutable Data Structures
# =============================================================================
# Description: Persistent immutable data structures with copy-on-write semantics.
#              All operations return new structures, never mutate. Designed for
#              functional programming patterns in bash where predictability and
#              thread-safety (via immutability) are paramount.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_IMMUTABLE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_IMMUTABLE_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Enable immutability enforcement (freeze checks)
MAINFRAME_IMMUTABLE_STRICT="${MAINFRAME_IMMUTABLE_STRICT:-1}"

# Enable USOP JSON output for structured results
MAINFRAME_IMMUTABLE_JSON="${MAINFRAME_IMMUTABLE_JSON:-1}"

# Namespace for structure identifiers
declare -A _MAINFRAME_IMAP_DATA 2>/dev/null || true
declare -A _MAINFRAME_IMAP_META 2>/dev/null || true
declare -A _MAINFRAME_ILIST_DATA 2>/dev/null || true
declare -A _MAINFRAME_ILIST_META 2>/dev/null || true
declare -A _MAINFRAME_ISET_DATA 2>/dev/null || true
declare -A _MAINFRAME_ISET_META 2>/dev/null || true

# Counter for unique structure IDs
_MAINFRAME_IMMUT_COUNTER=0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Generate unique structure ID
# @returns: unique ID string
_immut_gen_id() {
    local prefix="${1:-immut}"
    ((_MAINFRAME_IMMUT_COUNTER++))
    printf '%s_%d_%d' "$prefix" "$$" "$_MAINFRAME_IMMUT_COUNTER"
}

# Log message (respects quiet mode)
_immut_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[immutable] %s: %s\n' "${level}" "$*" >&2
    fi
}

# JSON-escape a string
_immut_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Emit USOP JSON error
# @pre: code is integer, msg is non-empty
# @post: JSON error emitted to stderr
_immut_error() {
    local code="${1:-1}"
    local msg="${2:-unknown error}"
    local func="${FUNCNAME[2]:-main}"

    if [[ "$MAINFRAME_IMMUTABLE_JSON" == "1" ]]; then
        local escaped_msg escaped_func
        escaped_msg=$(_immut_escape "$msg")
        escaped_func=$(_immut_escape "$func")
        printf '{"error":true,"code":%d,"msg":"%s","func":"%s"}\n' \
            "$code" "$escaped_msg" "$escaped_func" >&2
    else
        printf '[immutable] ERROR(%d) in %s: %s\n' "$code" "$func" "$msg" >&2
    fi
    return "$code"
}

# Emit USOP JSON success
# @pre: result is valid JSON fragment or string
# @post: JSON result emitted to stdout
_immut_result() {
    local result="$1"
    local type="${2:-value}"

    if [[ "$MAINFRAME_IMMUTABLE_JSON" == "1" ]]; then
        case "$type" in
            raw)
                printf '%s\n' "$result"
                ;;
            string)
                printf '"%s"\n' "$(_immut_escape "$result")"
                ;;
            number|bool)
                printf '%s\n' "$result"
                ;;
            *)
                printf '%s\n' "$result"
                ;;
        esac
    else
        printf '%s\n' "$result"
    fi
}

# Compute structural hash (for equality checks)
# @pre: data is non-empty string
# @post: returns hash string
_immut_hash_string() {
    local data="$1"
    local hash=0
    local i char

    for ((i=0; i<${#data}; i++)); do
        printf -v char '%d' "'${data:i:1}"
        hash=$(( (hash * 31 + char) % 2147483647 ))
    done
    printf '%d' "$hash"
}

# =============================================================================
# IMMUTABLE MAP (Persistent Hash Map)
# =============================================================================
# Maps are stored as: _MAINFRAME_IMAP_DATA["id:key"] = value
#                     _MAINFRAME_IMAP_META["id:size"] = count
#                     _MAINFRAME_IMAP_META["id:frozen"] = 0|1
#                     _MAINFRAME_IMAP_META["id:keys"] = "key1\x00key2\x00..."
# =============================================================================

# @pre: none
# @post: returns new empty map ID
# @idempotent: no - creates new map each call
# @returns: map ID string
#
# Create an empty immutable map.
#
# Usage: map_id=$(imap_create)
imap_create() {
    local id
    id=$(_immut_gen_id "imap")

    _MAINFRAME_IMAP_META["$id:size"]=0
    _MAINFRAME_IMAP_META["$id:frozen"]=0
    _MAINFRAME_IMAP_META["$id:keys"]=""

    _immut_result "$id" "string"
}

# @pre: pairs in format key=value or key:type=value
# @post: returns new map ID with entries set
# @idempotent: no - creates new map each call
# @returns: map ID string
#
# Create an immutable map from key=value pairs.
# Supports typed values: key:number=42, key:bool=true
#
# Usage: map_id=$(imap_from_pairs "name=John" "age:number=30")
imap_from_pairs() {
    local id
    id=$(_immut_gen_id "imap")

    _MAINFRAME_IMAP_META["$id:size"]=0
    _MAINFRAME_IMAP_META["$id:frozen"]=0
    _MAINFRAME_IMAP_META["$id:keys"]=""

    local count=0
    local keys=""

    for pair in "$@"; do
        local key value

        # Parse key:type=value or key=value
        if [[ "$pair" =~ ^([^:=]+)(:[^=]+)?=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[3]}"
        else
            _immut_log warn "imap_from_pairs: skipping invalid pair: $pair"
            continue
        fi

        _MAINFRAME_IMAP_DATA["$id:$key"]="$value"

        # Add to keys list if not already present
        if [[ "$keys" != *$'\x00'"$key"$'\x00'* ]] && [[ "$keys" != "$key"$'\x00'* ]] && [[ "$keys" != *$'\x00'"$key" ]] && [[ "$keys" != "$key" ]]; then
            [[ -n "$keys" ]] && keys+=$'\x00'
            keys+="$key"
            ((count++))
        fi
    done

    _MAINFRAME_IMAP_META["$id:size"]=$count
    _MAINFRAME_IMAP_META["$id:keys"]="$keys"

    _immut_result "$id" "string"
}

# @pre: map_id is valid map, key is non-empty
# @post: returns NEW map ID with key set (original unchanged)
# @idempotent: yes - same key/value produces equivalent result
# @returns: new map ID string
#
# Return a new map with the key set to value.
# The original map is never mutated.
#
# Usage: new_map=$(imap_set "$map_id" "key" "value")
imap_set() {
    local map_id="${1:-}"
    local key="${2:-}"
    local value="${3:-}"

    # Validate inputs
    if [[ -z "$map_id" ]]; then
        _immut_error 1 "map_id required"
        return 1
    fi
    if [[ -z "$key" ]]; then
        _immut_error 1 "key required"
        return 1
    fi

    # Check if frozen
    if [[ "$MAINFRAME_IMMUTABLE_STRICT" == "1" ]] && \
       [[ "${_MAINFRAME_IMAP_META["$map_id:frozen"]:-0}" == "1" ]]; then
        _immut_error 2 "cannot modify frozen map"
        return 2
    fi

    # Create new map (copy-on-write)
    local new_id
    new_id=$(_immut_gen_id "imap")

    # Copy all existing entries
    local old_keys="${_MAINFRAME_IMAP_META["$map_id:keys"]:-}"
    local new_keys=""
    local new_size=0
    local key_exists=0

    if [[ -n "$old_keys" ]]; then
        while IFS= read -r -d $'\x00' old_key || [[ -n "$old_key" ]]; do
            if [[ -n "$old_key" ]]; then
                if [[ "$old_key" == "$key" ]]; then
                    key_exists=1
                fi
                _MAINFRAME_IMAP_DATA["$new_id:$old_key"]="${_MAINFRAME_IMAP_DATA["$map_id:$old_key"]}"
                [[ -n "$new_keys" ]] && new_keys+=$'\x00'
                new_keys+="$old_key"
                ((new_size++))
            fi
        done <<< "$old_keys"
    fi

    # Set the new/updated key
    _MAINFRAME_IMAP_DATA["$new_id:$key"]="$value"

    if [[ "$key_exists" == "0" ]]; then
        [[ -n "$new_keys" ]] && new_keys+=$'\x00'
        new_keys+="$key"
        ((new_size++))
    fi

    _MAINFRAME_IMAP_META["$new_id:size"]=$new_size
    _MAINFRAME_IMAP_META["$new_id:keys"]="$new_keys"
    _MAINFRAME_IMAP_META["$new_id:frozen"]=0

    _immut_result "$new_id" "string"
}

# @pre: map_id is valid map, key is non-empty
# @post: returns value for key or empty string
# @idempotent: yes - read-only operation
# @returns: value string (may be empty)
#
# Get the value for a key in the map.
# Returns empty string if key not found.
#
# Usage: value=$(imap_get "$map_id" "key")
imap_get() {
    local map_id="${1:-}"
    local key="${2:-}"

    if [[ -z "$map_id" ]] || [[ -z "$key" ]]; then
        printf ''
        return 1
    fi

    local value="${_MAINFRAME_IMAP_DATA["$map_id:$key"]:-}"
    printf '%s' "$value"
}

# @pre: map_id is valid map, key is non-empty
# @post: returns 0 if key exists, 1 otherwise
# @idempotent: yes - read-only operation
# @returns: 0 (exists) or 1 (not exists)
#
# Check if a key exists in the map.
#
# Usage: imap_has "$map_id" "key" && echo "exists"
imap_has() {
    local map_id="${1:-}"
    local key="${2:-}"

    if [[ -z "$map_id" ]] || [[ -z "$key" ]]; then
        return 1
    fi

    [[ -v _MAINFRAME_IMAP_DATA["$map_id:$key"] ]]
}

# @pre: map_id is valid map, key is non-empty
# @post: returns NEW map ID without the key (original unchanged)
# @idempotent: yes - deleting non-existent key is no-op
# @returns: new map ID string
#
# Return a new map without the specified key.
# The original map is never mutated.
#
# Usage: new_map=$(imap_delete "$map_id" "key")
imap_delete() {
    local map_id="${1:-}"
    local key="${2:-}"

    if [[ -z "$map_id" ]]; then
        _immut_error 1 "map_id required"
        return 1
    fi
    if [[ -z "$key" ]]; then
        _immut_error 1 "key required"
        return 1
    fi

    # Check if frozen
    if [[ "$MAINFRAME_IMMUTABLE_STRICT" == "1" ]] && \
       [[ "${_MAINFRAME_IMAP_META["$map_id:frozen"]:-0}" == "1" ]]; then
        _immut_error 2 "cannot modify frozen map"
        return 2
    fi

    # Create new map without the key
    local new_id
    new_id=$(_immut_gen_id "imap")

    local old_keys="${_MAINFRAME_IMAP_META["$map_id:keys"]:-}"
    local new_keys=""
    local new_size=0

    if [[ -n "$old_keys" ]]; then
        while IFS= read -r -d $'\x00' old_key || [[ -n "$old_key" ]]; do
            if [[ -n "$old_key" ]] && [[ "$old_key" != "$key" ]]; then
                _MAINFRAME_IMAP_DATA["$new_id:$old_key"]="${_MAINFRAME_IMAP_DATA["$map_id:$old_key"]}"
                [[ -n "$new_keys" ]] && new_keys+=$'\x00'
                new_keys+="$old_key"
                ((new_size++))
            fi
        done <<< "$old_keys"
    fi

    _MAINFRAME_IMAP_META["$new_id:size"]=$new_size
    _MAINFRAME_IMAP_META["$new_id:keys"]="$new_keys"
    _MAINFRAME_IMAP_META["$new_id:frozen"]=0

    _immut_result "$new_id" "string"
}

# @pre: map_id is valid map
# @post: returns newline-separated list of keys
# @idempotent: yes - read-only operation
# @returns: keys (one per line)
#
# Get all keys in the map.
#
# Usage: imap_keys "$map_id"
imap_keys() {
    local map_id="${1:-}"

    if [[ -z "$map_id" ]]; then
        return 1
    fi

    local keys="${_MAINFRAME_IMAP_META["$map_id:keys"]:-}"
    if [[ -n "$keys" ]]; then
        printf '%s\n' "${keys//$'\x00'/$'\n'}"
    fi
}

# @pre: map_id is valid map
# @post: returns newline-separated list of values
# @idempotent: yes - read-only operation
# @returns: values (one per line)
#
# Get all values in the map.
#
# Usage: imap_values "$map_id"
imap_values() {
    local map_id="${1:-}"

    if [[ -z "$map_id" ]]; then
        return 1
    fi

    local keys="${_MAINFRAME_IMAP_META["$map_id:keys"]:-}"
    if [[ -n "$keys" ]]; then
        while IFS= read -r -d $'\x00' key || [[ -n "$key" ]]; do
            if [[ -n "$key" ]]; then
                printf '%s\n' "${_MAINFRAME_IMAP_DATA["$map_id:$key"]}"
            fi
        done <<< "$keys"
    fi
}

# @pre: map_id is valid map
# @post: returns key=value pairs (one per line)
# @idempotent: yes - read-only operation
# @returns: entries (key=value per line)
#
# Get all entries in the map as key=value pairs.
#
# Usage: imap_entries "$map_id"
imap_entries() {
    local map_id="${1:-}"

    if [[ -z "$map_id" ]]; then
        return 1
    fi

    local keys="${_MAINFRAME_IMAP_META["$map_id:keys"]:-}"
    if [[ -n "$keys" ]]; then
        while IFS= read -r -d $'\x00' key || [[ -n "$key" ]]; do
            if [[ -n "$key" ]]; then
                printf '%s=%s\n' "$key" "${_MAINFRAME_IMAP_DATA["$map_id:$key"]}"
            fi
        done <<< "$keys"
    fi
}

# @pre: map_id is valid map
# @post: returns entry count
# @idempotent: yes - read-only operation
# @returns: integer size
#
# Get the number of entries in the map.
#
# Usage: size=$(imap_size "$map_id")
imap_size() {
    local map_id="${1:-}"

    if [[ -z "$map_id" ]]; then
        printf '0'
        return 1
    fi

    printf '%d' "${_MAINFRAME_IMAP_META["$map_id:size"]:-0}"
}

# @pre: map_id is valid map
# @post: returns 0 if empty, 1 if not empty
# @idempotent: yes - read-only operation
# @returns: 0 (empty) or 1 (not empty)
#
# Check if the map is empty.
#
# Usage: imap_is_empty "$map_id" && echo "empty"
imap_is_empty() {
    local map_id="${1:-}"

    if [[ -z "$map_id" ]]; then
        return 0
    fi

    [[ "${_MAINFRAME_IMAP_META["$map_id:size"]:-0}" -eq 0 ]]
}

# @pre: map_id1 and map_id2 are valid maps
# @post: returns NEW map ID with all entries from both (map2 wins on conflict)
# @idempotent: yes - same inputs produce equivalent result
# @returns: new map ID string
#
# Merge two maps into a new map. Values from map2 override map1.
#
# Usage: merged=$(imap_merge "$map1" "$map2")
imap_merge() {
    local map1="${1:-}"
    local map2="${2:-}"

    if [[ -z "$map1" ]] || [[ -z "$map2" ]]; then
        _immut_error 1 "two map IDs required"
        return 1
    fi

    local new_id
    new_id=$(_immut_gen_id "imap")

    local new_keys=""
    local new_size=0
    declare -A seen_keys

    # Copy from map1
    local keys1="${_MAINFRAME_IMAP_META["$map1:keys"]:-}"
    if [[ -n "$keys1" ]]; then
        while IFS= read -r -d $'\x00' key || [[ -n "$key" ]]; do
            if [[ -n "$key" ]] && [[ ! -v seen_keys["$key"] ]]; then
                _MAINFRAME_IMAP_DATA["$new_id:$key"]="${_MAINFRAME_IMAP_DATA["$map1:$key"]}"
                [[ -n "$new_keys" ]] && new_keys+=$'\x00'
                new_keys+="$key"
                seen_keys["$key"]=1
                ((new_size++))
            fi
        done <<< "$keys1"
    fi

    # Copy/override from map2
    local keys2="${_MAINFRAME_IMAP_META["$map2:keys"]:-}"
    if [[ -n "$keys2" ]]; then
        while IFS= read -r -d $'\x00' key || [[ -n "$key" ]]; do
            if [[ -n "$key" ]]; then
                _MAINFRAME_IMAP_DATA["$new_id:$key"]="${_MAINFRAME_IMAP_DATA["$map2:$key"]}"
                if [[ ! -v seen_keys["$key"] ]]; then
                    [[ -n "$new_keys" ]] && new_keys+=$'\x00'
                    new_keys+="$key"
                    seen_keys["$key"]=1
                    ((new_size++))
                fi
            fi
        done <<< "$keys2"
    fi

    _MAINFRAME_IMAP_META["$new_id:size"]=$new_size
    _MAINFRAME_IMAP_META["$new_id:keys"]="$new_keys"
    _MAINFRAME_IMAP_META["$new_id:frozen"]=0

    _immut_result "$new_id" "string"
}

# @pre: map_id is valid map, func is callable
# @post: returns NEW map ID with transformed values
# @idempotent: yes - pure function produces consistent result
# @returns: new map ID string
#
# Transform all values in the map using a function.
# The function receives (key, value) and should output new value.
#
# Usage: transformed=$(imap_map_values "$map_id" "transform_fn")
# Example function: my_transform() { echo "${2^^}"; }
imap_map_values() {
    local map_id="${1:-}"
    local func="${2:-}"

    if [[ -z "$map_id" ]] || [[ -z "$func" ]]; then
        _immut_error 1 "map_id and function required"
        return 1
    fi

    if ! declare -F "$func" &>/dev/null; then
        _immut_error 1 "function not found: $func"
        return 1
    fi

    local new_id
    new_id=$(_immut_gen_id "imap")

    local keys="${_MAINFRAME_IMAP_META["$map_id:keys"]:-}"
    local new_keys=""
    local new_size=0

    if [[ -n "$keys" ]]; then
        while IFS= read -r -d $'\x00' key || [[ -n "$key" ]]; do
            if [[ -n "$key" ]]; then
                local old_value="${_MAINFRAME_IMAP_DATA["$map_id:$key"]}"
                local new_value
                new_value=$("$func" "$key" "$old_value")
                _MAINFRAME_IMAP_DATA["$new_id:$key"]="$new_value"
                [[ -n "$new_keys" ]] && new_keys+=$'\x00'
                new_keys+="$key"
                ((new_size++))
            fi
        done <<< "$keys"
    fi

    _MAINFRAME_IMAP_META["$new_id:size"]=$new_size
    _MAINFRAME_IMAP_META["$new_id:keys"]="$new_keys"
    _MAINFRAME_IMAP_META["$new_id:frozen"]=0

    _immut_result "$new_id" "string"
}

# @pre: map_id is valid map, predicate is callable
# @post: returns NEW map ID with only entries matching predicate
# @idempotent: yes - pure predicate produces consistent result
# @returns: new map ID string
#
# Filter map entries using a predicate function.
# The predicate receives (key, value) and should return 0 to keep.
#
# Usage: filtered=$(imap_filter "$map_id" "predicate_fn")
# Example predicate: is_positive() { [[ "$2" -gt 0 ]]; }
imap_filter() {
    local map_id="${1:-}"
    local predicate="${2:-}"

    if [[ -z "$map_id" ]] || [[ -z "$predicate" ]]; then
        _immut_error 1 "map_id and predicate required"
        return 1
    fi

    if ! declare -F "$predicate" &>/dev/null; then
        _immut_error 1 "predicate not found: $predicate"
        return 1
    fi

    local new_id
    new_id=$(_immut_gen_id "imap")

    local keys="${_MAINFRAME_IMAP_META["$map_id:keys"]:-}"
    local new_keys=""
    local new_size=0

    if [[ -n "$keys" ]]; then
        while IFS= read -r -d $'\x00' key || [[ -n "$key" ]]; do
            if [[ -n "$key" ]]; then
                local value="${_MAINFRAME_IMAP_DATA["$map_id:$key"]}"
                if "$predicate" "$key" "$value"; then
                    _MAINFRAME_IMAP_DATA["$new_id:$key"]="$value"
                    [[ -n "$new_keys" ]] && new_keys+=$'\x00'
                    new_keys+="$key"
                    ((new_size++))
                fi
            fi
        done <<< "$keys"
    fi

    _MAINFRAME_IMAP_META["$new_id:size"]=$new_size
    _MAINFRAME_IMAP_META["$new_id:keys"]="$new_keys"
    _MAINFRAME_IMAP_META["$new_id:frozen"]=0

    _immut_result "$new_id" "string"
}

# @pre: map_id is valid map
# @post: returns JSON object representation
# @idempotent: yes - read-only operation
# @returns: JSON object string
#
# Serialize the map to a JSON object.
#
# Usage: json=$(imap_to_json "$map_id")
imap_to_json() {
    local map_id="${1:-}"

    if [[ -z "$map_id" ]]; then
        printf '{}'
        return 1
    fi

    local keys="${_MAINFRAME_IMAP_META["$map_id:keys"]:-}"
    local first=true

    printf '{'
    if [[ -n "$keys" ]]; then
        while IFS= read -r -d $'\x00' key || [[ -n "$key" ]]; do
            if [[ -n "$key" ]]; then
                $first || printf ','
                first=false
                local value="${_MAINFRAME_IMAP_DATA["$map_id:$key"]}"
                printf '"%s":"%s"' "$(_immut_escape "$key")" "$(_immut_escape "$value")"
            fi
        done <<< "$keys"
    fi
    printf '}'
}

# @pre: json is valid JSON object string
# @post: returns new map ID with entries from JSON
# @idempotent: no - creates new map each call
# @returns: map ID string
#
# Deserialize a JSON object to an immutable map.
# Limited parser - handles simple key:string-value objects.
#
# Usage: map_id=$(imap_from_json '{"name":"John","age":"30"}')
imap_from_json() {
    local json="${1:-}"

    if [[ -z "$json" ]] || [[ "$json" == "{}" ]]; then
        imap_create
        return
    fi

    local id
    id=$(_immut_gen_id "imap")

    _MAINFRAME_IMAP_META["$id:size"]=0
    _MAINFRAME_IMAP_META["$id:frozen"]=0
    _MAINFRAME_IMAP_META["$id:keys"]=""

    local keys=""
    local count=0

    # Simple JSON parsing - extract "key":"value" pairs
    # Remove outer braces
    json="${json#\{}"
    json="${json%\}}"

    # Parse key-value pairs (simplified - expects "key":"value" format)
    local remaining="$json"
    while [[ -n "$remaining" ]]; do
        # Match "key":"value" pattern
        if [[ "$remaining" =~ ^[[:space:]]*\"([^\"]+)\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            remaining="${BASH_REMATCH[3]}"

            # Unescape value
            value="${value//\\n/$'\n'}"
            value="${value//\\t/$'\t'}"
            value="${value//\\r/$'\r'}"
            value="${value//\\\"/\"}"
            value="${value//\\\\/\\}"

            _MAINFRAME_IMAP_DATA["$id:$key"]="$value"
            [[ -n "$keys" ]] && keys+=$'\x00'
            keys+="$key"
            ((count++))

            # Remove leading comma
            remaining="${remaining#,}"
        else
            break
        fi
    done

    _MAINFRAME_IMAP_META["$id:size"]=$count
    _MAINFRAME_IMAP_META["$id:keys"]="$keys"

    _immut_result "$id" "string"
}

# =============================================================================
# IMMUTABLE LIST (Persistent Vector)
# =============================================================================
# Lists are stored as: _MAINFRAME_ILIST_DATA["id:index"] = value
#                      _MAINFRAME_ILIST_META["id:size"] = count
#                      _MAINFRAME_ILIST_META["id:frozen"] = 0|1
# =============================================================================

# @pre: none
# @post: returns new empty list ID
# @idempotent: no - creates new list each call
# @returns: list ID string
#
# Create an empty immutable list.
#
# Usage: list_id=$(ilist_create)
ilist_create() {
    local id
    id=$(_immut_gen_id "ilist")

    _MAINFRAME_ILIST_META["$id:size"]=0
    _MAINFRAME_ILIST_META["$id:frozen"]=0

    _immut_result "$id" "string"
}

# @pre: values are positional arguments
# @post: returns new list ID with values
# @idempotent: no - creates new list each call
# @returns: list ID string
#
# Create an immutable list from array/arguments.
#
# Usage: list_id=$(ilist_from_array "a" "b" "c")
ilist_from_array() {
    local id
    id=$(_immut_gen_id "ilist")

    local index=0
    for value in "$@"; do
        _MAINFRAME_ILIST_DATA["$id:$index"]="$value"
        ((index++))
    done

    _MAINFRAME_ILIST_META["$id:size"]=$index
    _MAINFRAME_ILIST_META["$id:frozen"]=0

    _immut_result "$id" "string"
}

# @pre: list_id is valid list, value is provided
# @post: returns NEW list ID with value appended
# @idempotent: no - each call adds to list
# @returns: new list ID string
#
# Return a new list with the value appended at the end.
# The original list is never mutated.
#
# Usage: new_list=$(ilist_append "$list_id" "value")
ilist_append() {
    local list_id="${1:-}"
    local value="${2:-}"

    if [[ -z "$list_id" ]]; then
        _immut_error 1 "list_id required"
        return 1
    fi

    # Check if frozen
    if [[ "$MAINFRAME_IMMUTABLE_STRICT" == "1" ]] && \
       [[ "${_MAINFRAME_ILIST_META["$list_id:frozen"]:-0}" == "1" ]]; then
        _immut_error 2 "cannot modify frozen list"
        return 2
    fi

    local new_id
    new_id=$(_immut_gen_id "ilist")

    # Copy existing elements
    local old_size="${_MAINFRAME_ILIST_META["$list_id:size"]:-0}"
    for ((i=0; i<old_size; i++)); do
        _MAINFRAME_ILIST_DATA["$new_id:$i"]="${_MAINFRAME_ILIST_DATA["$list_id:$i"]}"
    done

    # Append new value
    _MAINFRAME_ILIST_DATA["$new_id:$old_size"]="$value"
    _MAINFRAME_ILIST_META["$new_id:size"]=$((old_size + 1))
    _MAINFRAME_ILIST_META["$new_id:frozen"]=0

    _immut_result "$new_id" "string"
}

# @pre: list_id is valid list, value is provided
# @post: returns NEW list ID with value prepended
# @idempotent: no - each call adds to list
# @returns: new list ID string
#
# Return a new list with the value prepended at the start.
# The original list is never mutated.
#
# Usage: new_list=$(ilist_prepend "$list_id" "value")
ilist_prepend() {
    local list_id="${1:-}"
    local value="${2:-}"

    if [[ -z "$list_id" ]]; then
        _immut_error 1 "list_id required"
        return 1
    fi

    # Check if frozen
    if [[ "$MAINFRAME_IMMUTABLE_STRICT" == "1" ]] && \
       [[ "${_MAINFRAME_ILIST_META["$list_id:frozen"]:-0}" == "1" ]]; then
        _immut_error 2 "cannot modify frozen list"
        return 2
    fi

    local new_id
    new_id=$(_immut_gen_id "ilist")

    # Insert new value at index 0
    _MAINFRAME_ILIST_DATA["$new_id:0"]="$value"

    # Copy existing elements shifted by 1
    local old_size="${_MAINFRAME_ILIST_META["$list_id:size"]:-0}"
    for ((i=0; i<old_size; i++)); do
        _MAINFRAME_ILIST_DATA["$new_id:$((i + 1))"]="${_MAINFRAME_ILIST_DATA["$list_id:$i"]}"
    done

    _MAINFRAME_ILIST_META["$new_id:size"]=$((old_size + 1))
    _MAINFRAME_ILIST_META["$new_id:frozen"]=0

    _immut_result "$new_id" "string"
}

# @pre: list_id is valid list, index is integer
# @post: returns value at index or empty string
# @idempotent: yes - read-only operation
# @returns: value string (may be empty)
#
# Get the value at the specified index.
# Returns empty string if index out of bounds.
#
# Usage: value=$(ilist_get "$list_id" 0)
ilist_get() {
    local list_id="${1:-}"
    local index="${2:-}"

    if [[ -z "$list_id" ]] || [[ -z "$index" ]]; then
        printf ''
        return 1
    fi

    # Validate index
    if [[ ! "$index" =~ ^-?[0-9]+$ ]]; then
        printf ''
        return 1
    fi

    local size="${_MAINFRAME_ILIST_META["$list_id:size"]:-0}"

    # Handle negative indices
    if [[ "$index" -lt 0 ]]; then
        index=$((size + index))
    fi

    if [[ "$index" -lt 0 ]] || [[ "$index" -ge "$size" ]]; then
        printf ''
        return 1
    fi

    printf '%s' "${_MAINFRAME_ILIST_DATA["$list_id:$index"]:-}"
}

# @pre: list_id is valid list, index is integer
# @post: returns NEW list ID with value at index
# @idempotent: yes - same index/value produces equivalent result
# @returns: new list ID string
#
# Return a new list with the value at the specified index.
# The original list is never mutated.
#
# Usage: new_list=$(ilist_set "$list_id" 1 "new_value")
ilist_set() {
    local list_id="${1:-}"
    local index="${2:-}"
    local value="${3:-}"

    if [[ -z "$list_id" ]]; then
        _immut_error 1 "list_id required"
        return 1
    fi
    if [[ -z "$index" ]] || [[ ! "$index" =~ ^-?[0-9]+$ ]]; then
        _immut_error 1 "valid index required"
        return 1
    fi

    local size="${_MAINFRAME_ILIST_META["$list_id:size"]:-0}"

    # Handle negative indices
    if [[ "$index" -lt 0 ]]; then
        index=$((size + index))
    fi

    if [[ "$index" -lt 0 ]] || [[ "$index" -ge "$size" ]]; then
        _immut_error 1 "index out of bounds: $index (size: $size)"
        return 1
    fi

    # Check if frozen
    if [[ "$MAINFRAME_IMMUTABLE_STRICT" == "1" ]] && \
       [[ "${_MAINFRAME_ILIST_META["$list_id:frozen"]:-0}" == "1" ]]; then
        _immut_error 2 "cannot modify frozen list"
        return 2
    fi

    local new_id
    new_id=$(_immut_gen_id "ilist")

    # Copy all elements, replacing the one at index
    for ((i=0; i<size; i++)); do
        if [[ "$i" -eq "$index" ]]; then
            _MAINFRAME_ILIST_DATA["$new_id:$i"]="$value"
        else
            _MAINFRAME_ILIST_DATA["$new_id:$i"]="${_MAINFRAME_ILIST_DATA["$list_id:$i"]}"
        fi
    done

    _MAINFRAME_ILIST_META["$new_id:size"]=$size
    _MAINFRAME_ILIST_META["$new_id:frozen"]=0

    _immut_result "$new_id" "string"
}

# @pre: list_id is valid list, index is integer
# @post: returns NEW list ID without element at index
# @idempotent: yes - removing same index produces consistent result
# @returns: new list ID string
#
# Return a new list without the element at the specified index.
# The original list is never mutated.
#
# Usage: new_list=$(ilist_remove "$list_id" 1)
ilist_remove() {
    local list_id="${1:-}"
    local index="${2:-}"

    if [[ -z "$list_id" ]]; then
        _immut_error 1 "list_id required"
        return 1
    fi
    if [[ -z "$index" ]] || [[ ! "$index" =~ ^-?[0-9]+$ ]]; then
        _immut_error 1 "valid index required"
        return 1
    fi

    local size="${_MAINFRAME_ILIST_META["$list_id:size"]:-0}"

    # Handle negative indices
    if [[ "$index" -lt 0 ]]; then
        index=$((size + index))
    fi

    if [[ "$index" -lt 0 ]] || [[ "$index" -ge "$size" ]]; then
        _immut_error 1 "index out of bounds: $index (size: $size)"
        return 1
    fi

    # Check if frozen
    if [[ "$MAINFRAME_IMMUTABLE_STRICT" == "1" ]] && \
       [[ "${_MAINFRAME_ILIST_META["$list_id:frozen"]:-0}" == "1" ]]; then
        _immut_error 2 "cannot modify frozen list"
        return 2
    fi

    local new_id
    new_id=$(_immut_gen_id "ilist")

    # Copy all elements except the one at index
    local new_index=0
    for ((i=0; i<size; i++)); do
        if [[ "$i" -ne "$index" ]]; then
            _MAINFRAME_ILIST_DATA["$new_id:$new_index"]="${_MAINFRAME_ILIST_DATA["$list_id:$i"]}"
            ((new_index++))
        fi
    done

    _MAINFRAME_ILIST_META["$new_id:size"]=$((size - 1))
    _MAINFRAME_ILIST_META["$new_id:frozen"]=0

    _immut_result "$new_id" "string"
}

# @pre: list_id is valid list, start/end are integers
# @post: returns NEW list ID with slice of elements
# @idempotent: yes - same range produces consistent result
# @returns: new list ID string
#
# Return a new list with elements from start to end (exclusive).
# Supports negative indices like Python slicing.
#
# Usage: sliced=$(ilist_slice "$list_id" 1 3)  # elements 1, 2
ilist_slice() {
    local list_id="${1:-}"
    local start="${2:-0}"
    local end="${3:-}"

    if [[ -z "$list_id" ]]; then
        _immut_error 1 "list_id required"
        return 1
    fi

    local size="${_MAINFRAME_ILIST_META["$list_id:size"]:-0}"

    # Handle default end
    [[ -z "$end" ]] && end=$size

    # Handle negative indices
    [[ "$start" -lt 0 ]] && start=$((size + start))
    [[ "$end" -lt 0 ]] && end=$((size + end))

    # Clamp to valid range
    [[ "$start" -lt 0 ]] && start=0
    [[ "$end" -gt "$size" ]] && end=$size
    [[ "$start" -gt "$end" ]] && start=$end

    local new_id
    new_id=$(_immut_gen_id "ilist")

    local new_index=0
    for ((i=start; i<end; i++)); do
        _MAINFRAME_ILIST_DATA["$new_id:$new_index"]="${_MAINFRAME_ILIST_DATA["$list_id:$i"]}"
        ((new_index++))
    done

    _MAINFRAME_ILIST_META["$new_id:size"]=$new_index
    _MAINFRAME_ILIST_META["$new_id:frozen"]=0

    _immut_result "$new_id" "string"
}

# @pre: list_id1 and list_id2 are valid lists
# @post: returns NEW list ID with all elements from both
# @idempotent: yes - same inputs produce equivalent result
# @returns: new list ID string
#
# Concatenate two lists into a new list.
#
# Usage: combined=$(ilist_concat "$list1" "$list2")
ilist_concat() {
    local list1="${1:-}"
    local list2="${2:-}"

    if [[ -z "$list1" ]] || [[ -z "$list2" ]]; then
        _immut_error 1 "two list IDs required"
        return 1
    fi

    local new_id
    new_id=$(_immut_gen_id "ilist")

    local size1="${_MAINFRAME_ILIST_META["$list1:size"]:-0}"
    local size2="${_MAINFRAME_ILIST_META["$list2:size"]:-0}"

    local new_index=0

    # Copy from list1
    for ((i=0; i<size1; i++)); do
        _MAINFRAME_ILIST_DATA["$new_id:$new_index"]="${_MAINFRAME_ILIST_DATA["$list1:$i"]}"
        ((new_index++))
    done

    # Copy from list2
    for ((i=0; i<size2; i++)); do
        _MAINFRAME_ILIST_DATA["$new_id:$new_index"]="${_MAINFRAME_ILIST_DATA["$list2:$i"]}"
        ((new_index++))
    done

    _MAINFRAME_ILIST_META["$new_id:size"]=$new_index
    _MAINFRAME_ILIST_META["$new_id:frozen"]=0

    _immut_result "$new_id" "string"
}

# @pre: list_id is valid list
# @post: returns element count
# @idempotent: yes - read-only operation
# @returns: integer size
#
# Get the number of elements in the list.
#
# Usage: size=$(ilist_size "$list_id")
ilist_size() {
    local list_id="${1:-}"

    if [[ -z "$list_id" ]]; then
        printf '0'
        return 1
    fi

    printf '%d' "${_MAINFRAME_ILIST_META["$list_id:size"]:-0}"
}

# @pre: list_id is valid list
# @post: returns 0 if empty, 1 if not empty
# @idempotent: yes - read-only operation
# @returns: 0 (empty) or 1 (not empty)
#
# Check if the list is empty.
#
# Usage: ilist_is_empty "$list_id" && echo "empty"
ilist_is_empty() {
    local list_id="${1:-}"

    if [[ -z "$list_id" ]]; then
        return 0
    fi

    [[ "${_MAINFRAME_ILIST_META["$list_id:size"]:-0}" -eq 0 ]]
}

# @pre: list_id is valid list, func is callable
# @post: returns NEW list ID with transformed elements
# @idempotent: yes - pure function produces consistent result
# @returns: new list ID string
#
# Transform all elements in the list using a function.
# The function receives (index, value) and should output new value.
#
# Usage: transformed=$(ilist_map "$list_id" "transform_fn")
ilist_map() {
    local list_id="${1:-}"
    local func="${2:-}"

    if [[ -z "$list_id" ]] || [[ -z "$func" ]]; then
        _immut_error 1 "list_id and function required"
        return 1
    fi

    if ! declare -F "$func" &>/dev/null; then
        _immut_error 1 "function not found: $func"
        return 1
    fi

    local new_id
    new_id=$(_immut_gen_id "ilist")

    local size="${_MAINFRAME_ILIST_META["$list_id:size"]:-0}"

    for ((i=0; i<size; i++)); do
        local old_value="${_MAINFRAME_ILIST_DATA["$list_id:$i"]}"
        local new_value
        new_value=$("$func" "$i" "$old_value")
        _MAINFRAME_ILIST_DATA["$new_id:$i"]="$new_value"
    done

    _MAINFRAME_ILIST_META["$new_id:size"]=$size
    _MAINFRAME_ILIST_META["$new_id:frozen"]=0

    _immut_result "$new_id" "string"
}

# @pre: list_id is valid list, predicate is callable
# @post: returns NEW list ID with only elements matching predicate
# @idempotent: yes - pure predicate produces consistent result
# @returns: new list ID string
#
# Filter list elements using a predicate function.
# The predicate receives (index, value) and should return 0 to keep.
#
# Usage: filtered=$(ilist_filter "$list_id" "predicate_fn")
ilist_filter() {
    local list_id="${1:-}"
    local predicate="${2:-}"

    if [[ -z "$list_id" ]] || [[ -z "$predicate" ]]; then
        _immut_error 1 "list_id and predicate required"
        return 1
    fi

    if ! declare -F "$predicate" &>/dev/null; then
        _immut_error 1 "predicate not found: $predicate"
        return 1
    fi

    local new_id
    new_id=$(_immut_gen_id "ilist")

    local size="${_MAINFRAME_ILIST_META["$list_id:size"]:-0}"
    local new_size=0

    for ((i=0; i<size; i++)); do
        local value="${_MAINFRAME_ILIST_DATA["$list_id:$i"]}"
        if "$predicate" "$i" "$value"; then
            _MAINFRAME_ILIST_DATA["$new_id:$new_size"]="$value"
            ((new_size++))
        fi
    done

    _MAINFRAME_ILIST_META["$new_id:size"]=$new_size
    _MAINFRAME_ILIST_META["$new_id:frozen"]=0

    _immut_result "$new_id" "string"
}

# @pre: list_id is valid list, func is callable
# @post: returns accumulated result
# @idempotent: yes - pure function produces consistent result
# @returns: accumulated value string
#
# Reduce list to a single value using a function.
# The function receives (accumulator, index, value) and outputs new accumulator.
#
# Usage: sum=$(ilist_reduce "$list_id" "reduce_fn" "0")
ilist_reduce() {
    local list_id="${1:-}"
    local func="${2:-}"
    local initial="${3:-}"

    if [[ -z "$list_id" ]] || [[ -z "$func" ]]; then
        _immut_error 1 "list_id and function required"
        return 1
    fi

    if ! declare -F "$func" &>/dev/null; then
        _immut_error 1 "function not found: $func"
        return 1
    fi

    local size="${_MAINFRAME_ILIST_META["$list_id:size"]:-0}"
    local acc="$initial"

    for ((i=0; i<size; i++)); do
        local value="${_MAINFRAME_ILIST_DATA["$list_id:$i"]}"
        acc=$("$func" "$acc" "$i" "$value")
    done

    printf '%s' "$acc"
}

# @pre: list_id is valid list
# @post: returns JSON array representation
# @idempotent: yes - read-only operation
# @returns: JSON array string
#
# Serialize the list to a JSON array.
#
# Usage: json=$(ilist_to_json "$list_id")
ilist_to_json() {
    local list_id="${1:-}"

    if [[ -z "$list_id" ]]; then
        printf '[]'
        return 1
    fi

    local size="${_MAINFRAME_ILIST_META["$list_id:size"]:-0}"
    local first=true

    printf '['
    for ((i=0; i<size; i++)); do
        $first || printf ','
        first=false
        local value="${_MAINFRAME_ILIST_DATA["$list_id:$i"]}"
        printf '"%s"' "$(_immut_escape "$value")"
    done
    printf ']'
}

# @pre: json is valid JSON array string
# @post: returns new list ID with elements from JSON
# @idempotent: no - creates new list each call
# @returns: list ID string
#
# Deserialize a JSON array to an immutable list.
# Limited parser - handles simple string arrays.
#
# Usage: list_id=$(ilist_from_json '["a","b","c"]')
ilist_from_json() {
    local json="${1:-}"

    if [[ -z "$json" ]] || [[ "$json" == "[]" ]]; then
        ilist_create
        return
    fi

    local id
    id=$(_immut_gen_id "ilist")

    _MAINFRAME_ILIST_META["$id:frozen"]=0

    # Remove outer brackets
    json="${json#\[}"
    json="${json%\]}"

    local index=0
    local remaining="$json"

    while [[ -n "$remaining" ]]; do
        # Match "value" pattern
        if [[ "$remaining" =~ ^[[:space:]]*\"([^\"]*)\"(.*)$ ]]; then
            local value="${BASH_REMATCH[1]}"
            remaining="${BASH_REMATCH[2]}"

            # Unescape value
            value="${value//\\n/$'\n'}"
            value="${value//\\t/$'\t'}"
            value="${value//\\r/$'\r'}"
            value="${value//\\\"/\"}"
            value="${value//\\\\/\\}"

            _MAINFRAME_ILIST_DATA["$id:$index"]="$value"
            ((index++))

            # Remove leading comma
            remaining="${remaining#,}"
        else
            break
        fi
    done

    _MAINFRAME_ILIST_META["$id:size"]=$index

    _immut_result "$id" "string"
}

# =============================================================================
# IMMUTABLE SET
# =============================================================================
# Sets are stored as: _MAINFRAME_ISET_DATA["id:value"] = 1
#                     _MAINFRAME_ISET_META["id:size"] = count
#                     _MAINFRAME_ISET_META["id:frozen"] = 0|1
#                     _MAINFRAME_ISET_META["id:values"] = "val1\x00val2\x00..."
# =============================================================================

# @pre: none
# @post: returns new empty set ID
# @idempotent: no - creates new set each call
# @returns: set ID string
#
# Create an empty immutable set.
#
# Usage: set_id=$(iset_create)
iset_create() {
    local id
    id=$(_immut_gen_id "iset")

    _MAINFRAME_ISET_META["$id:size"]=0
    _MAINFRAME_ISET_META["$id:frozen"]=0
    _MAINFRAME_ISET_META["$id:values"]=""

    _immut_result "$id" "string"
}

# @pre: values are positional arguments
# @post: returns new set ID with values
# @idempotent: no - creates new set each call
# @returns: set ID string
#
# Create an immutable set from array/arguments.
# Duplicates are automatically removed.
#
# Usage: set_id=$(iset_from_array "a" "b" "c")
iset_from_array() {
    local id
    id=$(_immut_gen_id "iset")

    _MAINFRAME_ISET_META["$id:frozen"]=0

    local values=""
    local count=0

    for value in "$@"; do
        # Check if already present
        if [[ ! -v _MAINFRAME_ISET_DATA["$id:$value"] ]]; then
            _MAINFRAME_ISET_DATA["$id:$value"]=1
            [[ -n "$values" ]] && values+=$'\x00'
            values+="$value"
            ((count++))
        fi
    done

    _MAINFRAME_ISET_META["$id:size"]=$count
    _MAINFRAME_ISET_META["$id:values"]="$values"

    _immut_result "$id" "string"
}

# @pre: set_id is valid set, value is provided
# @post: returns NEW set ID with value added
# @idempotent: yes - adding existing value is no-op
# @returns: new set ID string
#
# Return a new set with the value added.
# The original set is never mutated.
#
# Usage: new_set=$(iset_add "$set_id" "value")
iset_add() {
    local set_id="${1:-}"
    local value="${2:-}"

    if [[ -z "$set_id" ]]; then
        _immut_error 1 "set_id required"
        return 1
    fi

    # Check if frozen
    if [[ "$MAINFRAME_IMMUTABLE_STRICT" == "1" ]] && \
       [[ "${_MAINFRAME_ISET_META["$set_id:frozen"]:-0}" == "1" ]]; then
        _immut_error 2 "cannot modify frozen set"
        return 2
    fi

    local new_id
    new_id=$(_immut_gen_id "iset")

    # Copy existing values
    local old_values="${_MAINFRAME_ISET_META["$set_id:values"]:-}"
    local new_values=""
    local new_size=0
    local value_exists=0

    if [[ -n "$old_values" ]]; then
        while IFS= read -r -d $'\x00' old_val || [[ -n "$old_val" ]]; do
            if [[ -n "$old_val" ]]; then
                if [[ "$old_val" == "$value" ]]; then
                    value_exists=1
                fi
                _MAINFRAME_ISET_DATA["$new_id:$old_val"]=1
                [[ -n "$new_values" ]] && new_values+=$'\x00'
                new_values+="$old_val"
                ((new_size++))
            fi
        done <<< "$old_values"
    fi

    # Add new value if not exists
    if [[ "$value_exists" == "0" ]]; then
        _MAINFRAME_ISET_DATA["$new_id:$value"]=1
        [[ -n "$new_values" ]] && new_values+=$'\x00'
        new_values+="$value"
        ((new_size++))
    fi

    _MAINFRAME_ISET_META["$new_id:size"]=$new_size
    _MAINFRAME_ISET_META["$new_id:values"]="$new_values"
    _MAINFRAME_ISET_META["$new_id:frozen"]=0

    _immut_result "$new_id" "string"
}

# @pre: set_id is valid set, value is provided
# @post: returns NEW set ID without the value
# @idempotent: yes - removing non-existent value is no-op
# @returns: new set ID string
#
# Return a new set without the specified value.
# The original set is never mutated.
#
# Usage: new_set=$(iset_remove "$set_id" "value")
iset_remove() {
    local set_id="${1:-}"
    local value="${2:-}"

    if [[ -z "$set_id" ]]; then
        _immut_error 1 "set_id required"
        return 1
    fi

    # Check if frozen
    if [[ "$MAINFRAME_IMMUTABLE_STRICT" == "1" ]] && \
       [[ "${_MAINFRAME_ISET_META["$set_id:frozen"]:-0}" == "1" ]]; then
        _immut_error 2 "cannot modify frozen set"
        return 2
    fi

    local new_id
    new_id=$(_immut_gen_id "iset")

    local old_values="${_MAINFRAME_ISET_META["$set_id:values"]:-}"
    local new_values=""
    local new_size=0

    if [[ -n "$old_values" ]]; then
        while IFS= read -r -d $'\x00' old_val || [[ -n "$old_val" ]]; do
            if [[ -n "$old_val" ]] && [[ "$old_val" != "$value" ]]; then
                _MAINFRAME_ISET_DATA["$new_id:$old_val"]=1
                [[ -n "$new_values" ]] && new_values+=$'\x00'
                new_values+="$old_val"
                ((new_size++))
            fi
        done <<< "$old_values"
    fi

    _MAINFRAME_ISET_META["$new_id:size"]=$new_size
    _MAINFRAME_ISET_META["$new_id:values"]="$new_values"
    _MAINFRAME_ISET_META["$new_id:frozen"]=0

    _immut_result "$new_id" "string"
}

# @pre: set_id is valid set, value is provided
# @post: returns 0 if value in set, 1 otherwise
# @idempotent: yes - read-only operation
# @returns: 0 (member) or 1 (not member)
#
# Check if a value is in the set.
#
# Usage: iset_has "$set_id" "value" && echo "member"
iset_has() {
    local set_id="${1:-}"
    local value="${2:-}"

    if [[ -z "$set_id" ]]; then
        return 1
    fi

    [[ -v _MAINFRAME_ISET_DATA["$set_id:$value"] ]]
}

# @pre: set_id is valid set
# @post: returns element count
# @idempotent: yes - read-only operation
# @returns: integer size
#
# Get the number of elements in the set.
#
# Usage: size=$(iset_size "$set_id")
iset_size() {
    local set_id="${1:-}"

    if [[ -z "$set_id" ]]; then
        printf '0'
        return 1
    fi

    printf '%d' "${_MAINFRAME_ISET_META["$set_id:size"]:-0}"
}

# @pre: set_id is valid set
# @post: returns 0 if empty, 1 if not empty
# @idempotent: yes - read-only operation
# @returns: 0 (empty) or 1 (not empty)
#
# Check if the set is empty.
#
# Usage: iset_is_empty "$set_id" && echo "empty"
iset_is_empty() {
    local set_id="${1:-}"

    if [[ -z "$set_id" ]]; then
        return 0
    fi

    [[ "${_MAINFRAME_ISET_META["$set_id:size"]:-0}" -eq 0 ]]
}

# @pre: set_id1 and set_id2 are valid sets
# @post: returns NEW set ID with all elements from both
# @idempotent: yes - same inputs produce equivalent result
# @returns: new set ID string
#
# Return the union of two sets.
#
# Usage: combined=$(iset_union "$set1" "$set2")
iset_union() {
    local set1="${1:-}"
    local set2="${2:-}"

    if [[ -z "$set1" ]] || [[ -z "$set2" ]]; then
        _immut_error 1 "two set IDs required"
        return 1
    fi

    local new_id
    new_id=$(_immut_gen_id "iset")

    local new_values=""
    local new_size=0
    declare -A seen_vals

    # Copy from set1
    local vals1="${_MAINFRAME_ISET_META["$set1:values"]:-}"
    if [[ -n "$vals1" ]]; then
        while IFS= read -r -d $'\x00' val || [[ -n "$val" ]]; do
            if [[ -n "$val" ]] && [[ ! -v seen_vals["$val"] ]]; then
                _MAINFRAME_ISET_DATA["$new_id:$val"]=1
                [[ -n "$new_values" ]] && new_values+=$'\x00'
                new_values+="$val"
                seen_vals["$val"]=1
                ((new_size++))
            fi
        done <<< "$vals1"
    fi

    # Add from set2 (duplicates auto-excluded)
    local vals2="${_MAINFRAME_ISET_META["$set2:values"]:-}"
    if [[ -n "$vals2" ]]; then
        while IFS= read -r -d $'\x00' val || [[ -n "$val" ]]; do
            if [[ -n "$val" ]] && [[ ! -v seen_vals["$val"] ]]; then
                _MAINFRAME_ISET_DATA["$new_id:$val"]=1
                [[ -n "$new_values" ]] && new_values+=$'\x00'
                new_values+="$val"
                seen_vals["$val"]=1
                ((new_size++))
            fi
        done <<< "$vals2"
    fi

    _MAINFRAME_ISET_META["$new_id:size"]=$new_size
    _MAINFRAME_ISET_META["$new_id:values"]="$new_values"
    _MAINFRAME_ISET_META["$new_id:frozen"]=0

    _immut_result "$new_id" "string"
}

# @pre: set_id1 and set_id2 are valid sets
# @post: returns NEW set ID with only common elements
# @idempotent: yes - same inputs produce equivalent result
# @returns: new set ID string
#
# Return the intersection of two sets.
#
# Usage: common=$(iset_intersect "$set1" "$set2")
iset_intersect() {
    local set1="${1:-}"
    local set2="${2:-}"

    if [[ -z "$set1" ]] || [[ -z "$set2" ]]; then
        _immut_error 1 "two set IDs required"
        return 1
    fi

    local new_id
    new_id=$(_immut_gen_id "iset")

    local new_values=""
    local new_size=0

    # Only include values that are in both sets
    local vals1="${_MAINFRAME_ISET_META["$set1:values"]:-}"
    if [[ -n "$vals1" ]]; then
        while IFS= read -r -d $'\x00' val || [[ -n "$val" ]]; do
            if [[ -n "$val" ]] && [[ -v _MAINFRAME_ISET_DATA["$set2:$val"] ]]; then
                _MAINFRAME_ISET_DATA["$new_id:$val"]=1
                [[ -n "$new_values" ]] && new_values+=$'\x00'
                new_values+="$val"
                ((new_size++))
            fi
        done <<< "$vals1"
    fi

    _MAINFRAME_ISET_META["$new_id:size"]=$new_size
    _MAINFRAME_ISET_META["$new_id:values"]="$new_values"
    _MAINFRAME_ISET_META["$new_id:frozen"]=0

    _immut_result "$new_id" "string"
}

# @pre: set_id1 and set_id2 are valid sets
# @post: returns NEW set ID with elements in set1 but not set2
# @idempotent: yes - same inputs produce equivalent result
# @returns: new set ID string
#
# Return the difference of two sets (set1 - set2).
#
# Usage: diff=$(iset_difference "$set1" "$set2")
iset_difference() {
    local set1="${1:-}"
    local set2="${2:-}"

    if [[ -z "$set1" ]] || [[ -z "$set2" ]]; then
        _immut_error 1 "two set IDs required"
        return 1
    fi

    local new_id
    new_id=$(_immut_gen_id "iset")

    local new_values=""
    local new_size=0

    # Only include values that are in set1 but not set2
    local vals1="${_MAINFRAME_ISET_META["$set1:values"]:-}"
    if [[ -n "$vals1" ]]; then
        while IFS= read -r -d $'\x00' val || [[ -n "$val" ]]; do
            if [[ -n "$val" ]] && [[ ! -v _MAINFRAME_ISET_DATA["$set2:$val"] ]]; then
                _MAINFRAME_ISET_DATA["$new_id:$val"]=1
                [[ -n "$new_values" ]] && new_values+=$'\x00'
                new_values+="$val"
                ((new_size++))
            fi
        done <<< "$vals1"
    fi

    _MAINFRAME_ISET_META["$new_id:size"]=$new_size
    _MAINFRAME_ISET_META["$new_id:values"]="$new_values"
    _MAINFRAME_ISET_META["$new_id:frozen"]=0

    _immut_result "$new_id" "string"
}

# @pre: set_id1 and set_id2 are valid sets
# @post: returns 0 if set1 is subset of set2, 1 otherwise
# @idempotent: yes - read-only operation
# @returns: 0 (is subset) or 1 (not subset)
#
# Check if set1 is a subset of set2.
#
# Usage: iset_is_subset "$set1" "$set2" && echo "subset"
iset_is_subset() {
    local set1="${1:-}"
    local set2="${2:-}"

    if [[ -z "$set1" ]] || [[ -z "$set2" ]]; then
        return 1
    fi

    local vals1="${_MAINFRAME_ISET_META["$set1:values"]:-}"

    # Empty set is subset of any set
    [[ -z "$vals1" ]] && return 0

    while IFS= read -r -d $'\x00' val || [[ -n "$val" ]]; do
        if [[ -n "$val" ]] && [[ ! -v _MAINFRAME_ISET_DATA["$set2:$val"] ]]; then
            return 1
        fi
    done <<< "$vals1"

    return 0
}

# @pre: set_id is valid set
# @post: returns newline-separated list of values
# @idempotent: yes - read-only operation
# @returns: values (one per line)
#
# Get all values in the set.
#
# Usage: iset_values "$set_id"
iset_values() {
    local set_id="${1:-}"

    if [[ -z "$set_id" ]]; then
        return 1
    fi

    local values="${_MAINFRAME_ISET_META["$set_id:values"]:-}"
    if [[ -n "$values" ]]; then
        printf '%s\n' "${values//$'\x00'/$'\n'}"
    fi
}

# @pre: set_id is valid set
# @post: returns JSON array representation
# @idempotent: yes - read-only operation
# @returns: JSON array string
#
# Serialize the set to a JSON array.
#
# Usage: json=$(iset_to_json "$set_id")
iset_to_json() {
    local set_id="${1:-}"

    if [[ -z "$set_id" ]]; then
        printf '[]'
        return 1
    fi

    local values="${_MAINFRAME_ISET_META["$set_id:values"]:-}"
    local first=true

    printf '['
    if [[ -n "$values" ]]; then
        while IFS= read -r -d $'\x00' val || [[ -n "$val" ]]; do
            if [[ -n "$val" ]]; then
                $first || printf ','
                first=false
                printf '"%s"' "$(_immut_escape "$val")"
            fi
        done <<< "$values"
    fi
    printf ']'
}

# =============================================================================
# STRUCTURAL SHARING UTILITIES
# =============================================================================

# @pre: struct_id is valid structure ID
# @post: returns NEW frozen structure ID
# @idempotent: yes - freezing already frozen is no-op
# @returns: frozen structure ID string
#
# Mark a structure as immutable (frozen). Frozen structures cannot be
# modified (any modification attempt returns error in strict mode).
#
# Usage: frozen_map=$(immut_freeze "$map_id")
immut_freeze() {
    local struct_id="${1:-}"

    if [[ -z "$struct_id" ]]; then
        _immut_error 1 "structure ID required"
        return 1
    fi

    # Determine structure type
    if [[ -v _MAINFRAME_IMAP_META["$struct_id:size"] ]]; then
        _MAINFRAME_IMAP_META["$struct_id:frozen"]=1
    elif [[ -v _MAINFRAME_ILIST_META["$struct_id:size"] ]]; then
        _MAINFRAME_ILIST_META["$struct_id:frozen"]=1
    elif [[ -v _MAINFRAME_ISET_META["$struct_id:size"] ]]; then
        _MAINFRAME_ISET_META["$struct_id:frozen"]=1
    else
        _immut_error 1 "unknown structure: $struct_id"
        return 1
    fi

    _immut_result "$struct_id" "string"
}

# @pre: struct_id is valid structure ID
# @post: returns 0 if frozen, 1 if not frozen
# @idempotent: yes - read-only operation
# @returns: 0 (frozen) or 1 (not frozen)
#
# Check if a structure is frozen.
#
# Usage: immut_is_frozen "$map_id" && echo "frozen"
immut_is_frozen() {
    local struct_id="${1:-}"

    if [[ -z "$struct_id" ]]; then
        return 1
    fi

    # Determine structure type
    if [[ -v _MAINFRAME_IMAP_META["$struct_id:size"] ]]; then
        [[ "${_MAINFRAME_IMAP_META["$struct_id:frozen"]:-0}" == "1" ]]
    elif [[ -v _MAINFRAME_ILIST_META["$struct_id:size"] ]]; then
        [[ "${_MAINFRAME_ILIST_META["$struct_id:frozen"]:-0}" == "1" ]]
    elif [[ -v _MAINFRAME_ISET_META["$struct_id:size"] ]]; then
        [[ "${_MAINFRAME_ISET_META["$struct_id:frozen"]:-0}" == "1" ]]
    else
        return 1
    fi
}

# @pre: struct_id is valid structure ID
# @post: returns NEW unfrozen copy of structure
# @idempotent: no - creates new structure each call
# @returns: new structure ID string
#
# Create a mutable (unfrozen) copy of a structure.
# This is useful when you need to make multiple modifications.
#
# Usage: mutable_map=$(immut_thaw "$frozen_map")
immut_thaw() {
    local struct_id="${1:-}"

    if [[ -z "$struct_id" ]]; then
        _immut_error 1 "structure ID required"
        return 1
    fi

    # Determine structure type and create unfrozen copy
    if [[ -v _MAINFRAME_IMAP_META["$struct_id:size"] ]]; then
        # Create new map with same data
        local new_id
        new_id=$(_immut_gen_id "imap")

        local keys="${_MAINFRAME_IMAP_META["$struct_id:keys"]:-}"
        local new_keys=""
        local new_size=0

        if [[ -n "$keys" ]]; then
            while IFS= read -r -d $'\x00' key || [[ -n "$key" ]]; do
                if [[ -n "$key" ]]; then
                    _MAINFRAME_IMAP_DATA["$new_id:$key"]="${_MAINFRAME_IMAP_DATA["$struct_id:$key"]}"
                    [[ -n "$new_keys" ]] && new_keys+=$'\x00'
                    new_keys+="$key"
                    ((new_size++))
                fi
            done <<< "$keys"
        fi

        _MAINFRAME_IMAP_META["$new_id:size"]=$new_size
        _MAINFRAME_IMAP_META["$new_id:keys"]="$new_keys"
        _MAINFRAME_IMAP_META["$new_id:frozen"]=0

        _immut_result "$new_id" "string"

    elif [[ -v _MAINFRAME_ILIST_META["$struct_id:size"] ]]; then
        # Create new list with same data
        local new_id
        new_id=$(_immut_gen_id "ilist")

        local size="${_MAINFRAME_ILIST_META["$struct_id:size"]:-0}"
        for ((i=0; i<size; i++)); do
            _MAINFRAME_ILIST_DATA["$new_id:$i"]="${_MAINFRAME_ILIST_DATA["$struct_id:$i"]}"
        done

        _MAINFRAME_ILIST_META["$new_id:size"]=$size
        _MAINFRAME_ILIST_META["$new_id:frozen"]=0

        _immut_result "$new_id" "string"

    elif [[ -v _MAINFRAME_ISET_META["$struct_id:size"] ]]; then
        # Create new set with same data
        local new_id
        new_id=$(_immut_gen_id "iset")

        local values="${_MAINFRAME_ISET_META["$struct_id:values"]:-}"
        local new_values=""
        local new_size=0

        if [[ -n "$values" ]]; then
            while IFS= read -r -d $'\x00' val || [[ -n "$val" ]]; do
                if [[ -n "$val" ]]; then
                    _MAINFRAME_ISET_DATA["$new_id:$val"]=1
                    [[ -n "$new_values" ]] && new_values+=$'\x00'
                    new_values+="$val"
                    ((new_size++))
                fi
            done <<< "$values"
        fi

        _MAINFRAME_ISET_META["$new_id:size"]=$new_size
        _MAINFRAME_ISET_META["$new_id:values"]="$new_values"
        _MAINFRAME_ISET_META["$new_id:frozen"]=0

        _immut_result "$new_id" "string"

    else
        _immut_error 1 "unknown structure: $struct_id"
        return 1
    fi
}

# @pre: struct_id1 and struct_id2 are valid structure IDs of same type
# @post: returns 0 if structurally equal, 1 otherwise
# @idempotent: yes - read-only operation
# @returns: 0 (equal) or 1 (not equal)
#
# Check if two structures are deeply equal.
#
# Usage: immut_equals "$map1" "$map2" && echo "equal"
immut_equals() {
    local struct1="${1:-}"
    local struct2="${2:-}"

    if [[ -z "$struct1" ]] || [[ -z "$struct2" ]]; then
        return 1
    fi

    # Same reference
    [[ "$struct1" == "$struct2" ]] && return 0

    # Check type match and compare
    if [[ -v _MAINFRAME_IMAP_META["$struct1:size"] ]] && \
       [[ -v _MAINFRAME_IMAP_META["$struct2:size"] ]]; then
        # Both are maps
        local size1="${_MAINFRAME_IMAP_META["$struct1:size"]:-0}"
        local size2="${_MAINFRAME_IMAP_META["$struct2:size"]:-0}"

        [[ "$size1" -ne "$size2" ]] && return 1

        local keys1="${_MAINFRAME_IMAP_META["$struct1:keys"]:-}"
        if [[ -n "$keys1" ]]; then
            while IFS= read -r -d $'\x00' key || [[ -n "$key" ]]; do
                if [[ -n "$key" ]]; then
                    [[ ! -v _MAINFRAME_IMAP_DATA["$struct2:$key"] ]] && return 1
                    [[ "${_MAINFRAME_IMAP_DATA["$struct1:$key"]}" != "${_MAINFRAME_IMAP_DATA["$struct2:$key"]}" ]] && return 1
                fi
            done <<< "$keys1"
        fi
        return 0

    elif [[ -v _MAINFRAME_ILIST_META["$struct1:size"] ]] && \
         [[ -v _MAINFRAME_ILIST_META["$struct2:size"] ]]; then
        # Both are lists
        local size1="${_MAINFRAME_ILIST_META["$struct1:size"]:-0}"
        local size2="${_MAINFRAME_ILIST_META["$struct2:size"]:-0}"

        [[ "$size1" -ne "$size2" ]] && return 1

        for ((i=0; i<size1; i++)); do
            [[ "${_MAINFRAME_ILIST_DATA["$struct1:$i"]}" != "${_MAINFRAME_ILIST_DATA["$struct2:$i"]}" ]] && return 1
        done
        return 0

    elif [[ -v _MAINFRAME_ISET_META["$struct1:size"] ]] && \
         [[ -v _MAINFRAME_ISET_META["$struct2:size"] ]]; then
        # Both are sets
        local size1="${_MAINFRAME_ISET_META["$struct1:size"]:-0}"
        local size2="${_MAINFRAME_ISET_META["$struct2:size"]:-0}"

        [[ "$size1" -ne "$size2" ]] && return 1

        local vals1="${_MAINFRAME_ISET_META["$struct1:values"]:-}"
        if [[ -n "$vals1" ]]; then
            while IFS= read -r -d $'\x00' val || [[ -n "$val" ]]; do
                if [[ -n "$val" ]] && [[ ! -v _MAINFRAME_ISET_DATA["$struct2:$val"] ]]; then
                    return 1
                fi
            done <<< "$vals1"
        fi
        return 0
    fi

    # Type mismatch
    return 1
}

# @pre: struct_id is valid structure ID
# @post: returns structural hash integer
# @idempotent: yes - same structure produces same hash
# @returns: integer hash value
#
# Compute a structural hash for a structure.
# Equal structures produce equal hashes.
#
# Usage: hash=$(immut_hash "$map_id")
immut_hash() {
    local struct_id="${1:-}"

    if [[ -z "$struct_id" ]]; then
        printf '0'
        return 1
    fi

    local content=""

    if [[ -v _MAINFRAME_IMAP_META["$struct_id:size"] ]]; then
        content="map:"
        local keys="${_MAINFRAME_IMAP_META["$struct_id:keys"]:-}"
        # Sort keys for consistent hash
        if [[ -n "$keys" ]]; then
            local sorted_keys
            sorted_keys=$(printf '%s\n' "${keys//$'\x00'/$'\n'}" | sort)
            while IFS= read -r key; do
                if [[ -n "$key" ]]; then
                    content+="$key=${_MAINFRAME_IMAP_DATA["$struct_id:$key"]};"
                fi
            done <<< "$sorted_keys"
        fi

    elif [[ -v _MAINFRAME_ILIST_META["$struct_id:size"] ]]; then
        content="list:"
        local size="${_MAINFRAME_ILIST_META["$struct_id:size"]:-0}"
        for ((i=0; i<size; i++)); do
            content+="${_MAINFRAME_ILIST_DATA["$struct_id:$i"]};"
        done

    elif [[ -v _MAINFRAME_ISET_META["$struct_id:size"] ]]; then
        content="set:"
        local values="${_MAINFRAME_ISET_META["$struct_id:values"]:-}"
        # Sort values for consistent hash
        if [[ -n "$values" ]]; then
            local sorted_vals
            sorted_vals=$(printf '%s\n' "${values//$'\x00'/$'\n'}" | sort)
            while IFS= read -r val; do
                if [[ -n "$val" ]]; then
                    content+="$val;"
                fi
            done <<< "$sorted_vals"
        fi
    fi

    _immut_hash_string "$content"
}

# =============================================================================
# CONVENIENCE: ITERATION HELPERS
# =============================================================================

# @pre: list_id is valid list
# @post: outputs each element on a line
# @idempotent: yes - read-only operation
# @returns: list elements (one per line)
#
# Iterate over list elements.
#
# Usage: ilist_each "$list_id" | while read -r item; do echo "$item"; done
ilist_each() {
    local list_id="${1:-}"

    if [[ -z "$list_id" ]]; then
        return 1
    fi

    local size="${_MAINFRAME_ILIST_META["$list_id:size"]:-0}"
    for ((i=0; i<size; i++)); do
        printf '%s\n' "${_MAINFRAME_ILIST_DATA["$list_id:$i"]}"
    done
}

# @pre: map_id is valid map
# @post: outputs each key=value on a line
# @idempotent: yes - read-only operation
# @returns: map entries (key=value per line)
#
# Iterate over map entries.
#
# Usage: imap_each "$map_id" | while IFS='=' read -r k v; do echo "$k: $v"; done
imap_each() {
    imap_entries "$@"
}

# @pre: set_id is valid set
# @post: outputs each value on a line
# @idempotent: yes - read-only operation
# @returns: set values (one per line)
#
# Iterate over set values.
#
# Usage: iset_each "$set_id" | while read -r item; do echo "$item"; done
iset_each() {
    iset_values "$@"
}

# =============================================================================
# CONVENIENCE: TYPE DETECTION
# =============================================================================

# @pre: struct_id is provided
# @post: returns structure type or "unknown"
# @idempotent: yes - read-only operation
# @returns: "map", "list", "set", or "unknown"
#
# Detect the type of a structure.
#
# Usage: type=$(immut_type "$struct_id")
immut_type() {
    local struct_id="${1:-}"

    if [[ -z "$struct_id" ]]; then
        printf 'unknown'
        return 1
    fi

    if [[ -v _MAINFRAME_IMAP_META["$struct_id:size"] ]]; then
        printf 'map'
    elif [[ -v _MAINFRAME_ILIST_META["$struct_id:size"] ]]; then
        printf 'list'
    elif [[ -v _MAINFRAME_ISET_META["$struct_id:size"] ]]; then
        printf 'set'
    else
        printf 'unknown'
        return 1
    fi
}

# @pre: struct_id is provided
# @post: returns size of structure
# @idempotent: yes - read-only operation
# @returns: integer size
#
# Get size of any structure type.
#
# Usage: size=$(immut_size "$struct_id")
immut_size() {
    local struct_id="${1:-}"

    if [[ -z "$struct_id" ]]; then
        printf '0'
        return 1
    fi

    if [[ -v _MAINFRAME_IMAP_META["$struct_id:size"] ]]; then
        printf '%d' "${_MAINFRAME_IMAP_META["$struct_id:size"]:-0}"
    elif [[ -v _MAINFRAME_ILIST_META["$struct_id:size"] ]]; then
        printf '%d' "${_MAINFRAME_ILIST_META["$struct_id:size"]:-0}"
    elif [[ -v _MAINFRAME_ISET_META["$struct_id:size"] ]]; then
        printf '%d' "${_MAINFRAME_ISET_META["$struct_id:size"]:-0}"
    else
        printf '0'
        return 1
    fi
}

# @pre: struct_id is provided
# @post: returns 0 if empty, 1 if not empty
# @idempotent: yes - read-only operation
# @returns: 0 (empty) or 1 (not empty)
#
# Check if any structure type is empty.
#
# Usage: immut_is_empty "$struct_id" && echo "empty"
immut_is_empty() {
    local struct_id="${1:-}"

    if [[ -z "$struct_id" ]]; then
        return 0
    fi

    local size
    size=$(immut_size "$struct_id")
    [[ "$size" -eq 0 ]]
}

# =============================================================================
# CLEANUP
# =============================================================================

# @pre: struct_id is valid structure ID
# @post: structure data is removed from memory
# @idempotent: yes - deleting non-existent structure is no-op
# @returns: 0 on success
#
# Free a structure from memory.
# Use when done with a structure to prevent memory leaks.
#
# Usage: immut_free "$map_id"
immut_free() {
    local struct_id="${1:-}"

    if [[ -z "$struct_id" ]]; then
        return 0
    fi

    if [[ -v _MAINFRAME_IMAP_META["$struct_id:size"] ]]; then
        local keys="${_MAINFRAME_IMAP_META["$struct_id:keys"]:-}"
        if [[ -n "$keys" ]]; then
            while IFS= read -r -d $'\x00' key || [[ -n "$key" ]]; do
                [[ -n "$key" ]] && unset "_MAINFRAME_IMAP_DATA[$struct_id:$key]"
            done <<< "$keys"
        fi
        unset "_MAINFRAME_IMAP_META[$struct_id:size]"
        unset "_MAINFRAME_IMAP_META[$struct_id:frozen]"
        unset "_MAINFRAME_IMAP_META[$struct_id:keys]"

    elif [[ -v _MAINFRAME_ILIST_META["$struct_id:size"] ]]; then
        local size="${_MAINFRAME_ILIST_META["$struct_id:size"]:-0}"
        for ((i=0; i<size; i++)); do
            unset "_MAINFRAME_ILIST_DATA[$struct_id:$i]"
        done
        unset "_MAINFRAME_ILIST_META[$struct_id:size]"
        unset "_MAINFRAME_ILIST_META[$struct_id:frozen]"

    elif [[ -v _MAINFRAME_ISET_META["$struct_id:size"] ]]; then
        local values="${_MAINFRAME_ISET_META["$struct_id:values"]:-}"
        if [[ -n "$values" ]]; then
            while IFS= read -r -d $'\x00' val || [[ -n "$val" ]]; do
                [[ -n "$val" ]] && unset "_MAINFRAME_ISET_DATA[$struct_id:$val]"
            done <<< "$values"
        fi
        unset "_MAINFRAME_ISET_META[$struct_id:size]"
        unset "_MAINFRAME_ISET_META[$struct_id:frozen]"
        unset "_MAINFRAME_ISET_META[$struct_id:values]"
    fi

    return 0
}

# =============================================================================
# MODULE INFORMATION
# =============================================================================

# @pre: none
# @post: outputs version information
# @idempotent: yes - read-only operation
# @returns: version string
immut_version() {
    printf 'MAINFRAME/immutable v1.0.0\n'
    printf 'Structures: imap (persistent hash map), ilist (persistent vector), iset (persistent set)\n'
    printf 'Features: copy-on-write, freeze/thaw, structural equality, JSON serialization\n'
}

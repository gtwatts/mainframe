#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/toml.sh - TOML Parser
# =============================================================================
# Description: Pure bash TOML parser for Cargo.toml, pyproject.toml, and other
#              TOML-formatted configuration files. Outputs flat key=value or JSON.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# LIMITATIONS (regex-based parsing, not full TOML spec):
#   - Datetime values are treated as strings (no validation)
#   - Deeply nested inline tables may not parse correctly
#   - Unicode escape sequences (\uXXXX) are passed through, not decoded
#   - Multiline literal strings (''') are not supported
#   - Integer separators (1_000) are passed through as-is
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_TOML_LOADED:-}" ]] && return 0
readonly _MAINFRAME_TOML_LOADED=1

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Escape a string for JSON output
_toml_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Trim leading and trailing whitespace
_toml_trim() {
    local str="$1"
    str="${str#"${str%%[![:space:]]*}"}"
    str="${str%"${str##*[![:space:]]}"}"
    printf '%s' "$str"
}

# Unquote a TOML string value (basic or literal)
_toml_unquote() {
    local val="$1"
    if [[ "$val" == '"'*'"' ]]; then
        val="${val#\"}"
        val="${val%\"}"
        # Process escape sequences in basic strings
        val="${val//\\n/$'\n'}"
        val="${val//\\t/$'\t'}"
        val="${val//\\r/$'\r'}"
        val="${val//\\\\/\\}"
        val="${val//\\\"/\"}"
    elif [[ "$val" == "'"*"'" ]]; then
        val="${val#\'}"
        val="${val%\'}"
        # Literal strings: no escape processing
    fi
    printf '%s' "$val"
}

# Parse an inline table: { key = val, key2 = val2 }
# Outputs key=value pairs with the given prefix
_toml_parse_inline_table() {
    local prefix="$1"
    local content="$2"

    # Strip outer braces
    content="${content#\{}"
    content="${content%\}}"
    content=$(_toml_trim "$content")

    [[ -z "$content" ]] && return 0

    # Split by comma, handling quoted strings
    local i=0 len=${#content}
    local field="" in_quote="" quote_char=""
    local depth=0

    while (( i < len )); do
        local ch="${content:$i:1}"

        if [[ -n "$in_quote" ]]; then
            if [[ "$ch" == "$quote_char" && "${content:$((i-1)):1}" != "\\" ]]; then
                in_quote=""
            fi
            field+="$ch"
        elif [[ "$ch" == '"' || "$ch" == "'" ]]; then
            in_quote=1
            quote_char="$ch"
            field+="$ch"
        elif [[ "$ch" == '{' ]]; then
            depth=$((depth + 1))
            field+="$ch"
        elif [[ "$ch" == '}' ]]; then
            depth=$((depth - 1))
            field+="$ch"
        elif [[ "$ch" == ',' && $depth -eq 0 ]]; then
            _toml_parse_inline_field "$prefix" "$field"
            field=""
        else
            field+="$ch"
        fi
        i=$((i + 1))
    done

    [[ -n "$field" ]] && _toml_parse_inline_field "$prefix" "$field"
}

# Parse a single inline table field: key = value
_toml_parse_inline_field() {
    local prefix="$1"
    local field="$2"

    field=$(_toml_trim "$field")
    [[ -z "$field" ]] && return 0

    local key value
    key="${field%%=*}"
    value="${field#*=}"
    key=$(_toml_trim "$key")
    value=$(_toml_trim "$value")

    # Unquote key if needed
    key=$(_toml_unquote "$key")

    local full_key="${prefix}.${key}"

    if [[ "$value" == "{"*"}" ]]; then
        _toml_parse_inline_table "$full_key" "$value"
    elif [[ "$value" == "["*"]" ]]; then
        printf '%s=%s\n' "$full_key" "$value"
    else
        value=$(_toml_unquote "$value")
        printf '%s=%s\n' "$full_key" "$value"
    fi
}


# Strip inline comments (not inside strings)
_toml_strip_comment() {
    local line="$1"
    local i=0 len=${#line}
    local in_quote="" quote_char=""
    local result=""

    while (( i < len )); do
        local ch="${line:$i:1}"

        if [[ -n "$in_quote" ]]; then
            if [[ "$ch" == "$quote_char" && "${line:$((i > 0 ? i-1 : 0)):1}" != "\\" ]]; then
                in_quote=""
            fi
            result+="$ch"
        elif [[ "$ch" == '"' || "$ch" == "'" ]]; then
            in_quote=1
            quote_char="$ch"
            result+="$ch"
        elif [[ "$ch" == '#' ]]; then
            break
        else
            result+="$ch"
        fi
        i=$((i + 1))
    done

    printf '%s' "$result"
}


# =============================================================================
# PUBLIC API
# =============================================================================

# @pre: file_path points to a TOML file
# @post: prints flat key=value pairs with dot-notation for nesting
# @idempotent: yes
# @returns: 0 on success, 1 on file error
#
# Parse a TOML file into flat key-value representation.
# Nested keys use dot notation: section.key=value
#
# Usage: toml_parse "Cargo.toml"
# Example: toml_parse "pyproject.toml" | grep "^project\."
toml_parse() {
    local file="$1"

    if [[ -z "$file" ]]; then
        printf 'error: no file specified\n' >&2
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        printf 'error: file not found: %s\n' "$file" >&2
        return 1
    fi

    # Read all lines into array
    local -a lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done < "$file"

    local current_section=""
    local array_table_counts=()
    local idx=0

    while (( idx < ${#lines[@]} )); do
        local line="${lines[$idx]}"
        idx=$((idx + 1))

        # Strip leading/trailing whitespace
        local trimmed
        trimmed=$(_toml_trim "$line")

        # Skip empty lines and comments
        [[ -z "$trimmed" ]] && continue
        [[ "$trimmed" == "#"* ]] && continue

        # Check for array of tables: [[section]]
        if [[ "$trimmed" == "[["*"]]" ]]; then
            local section="${trimmed#\[\[}"
            section="${section%\]\]}"
            section=$(_toml_trim "$section")

            # Track array index for this section
            local found=0
            local aidx=0
            for ((aidx=0; aidx<${#array_table_counts[@]}; aidx+=2)); do
                if [[ "${array_table_counts[$aidx]}" == "$section" ]]; then
                    array_table_counts[aidx+1]=$(( ${array_table_counts[aidx+1]} + 1 ))
                    found=1
                    current_section="${section}[${array_table_counts[$((aidx+1))]}]"
                    break
                fi
            done
            if [[ $found -eq 0 ]]; then
                array_table_counts+=("$section" "0")
                current_section="${section}[0]"
            fi
            continue
        fi

        # Check for table: [section]
        if [[ "$trimmed" == "["*"]" ]]; then
            current_section="${trimmed#\[}"
            current_section="${current_section%\]}"
            current_section=$(_toml_trim "$current_section")
            continue
        fi

        # Parse key = value
        # Find the first = that is not inside quotes
        local key="" value="" found_eq=0
        local i=0 len=${#trimmed}
        local in_q="" q_char=""

        while (( i < len )); do
            local ch="${trimmed:$i:1}"
            if [[ -n "$in_q" ]]; then
                if [[ "$ch" == "$q_char" ]]; then
                    in_q=""
                fi
            elif [[ "$ch" == '"' || "$ch" == "'" ]]; then
                in_q=1
                q_char="$ch"
            elif [[ "$ch" == '=' && $found_eq -eq 0 ]]; then
                key="${trimmed:0:$i}"
                value="${trimmed:$((i+1))}"
                found_eq=1
                break
            fi
            i=$((i + 1))
        done

        [[ $found_eq -eq 0 ]] && continue

        key=$(_toml_trim "$key")
        value=$(_toml_trim "$value")

        # Strip inline comment from value
        value=$(_toml_strip_comment "$value")
        value=$(_toml_trim "$value")

        # Handle quoted keys
        key=$(_toml_unquote "$key")

        # Build full key path
        local full_key
        if [[ -n "$current_section" ]]; then
            full_key="${current_section}.${key}"
        else
            full_key="$key"
        fi

        # Handle dotted keys in the key portion (a.b.c = value)
        # These are already in dot notation, just use them directly

        # Handle multiline basic strings
        if [[ "$value" == '"""'* ]]; then
            # Remove opening """
            local ml_content="${value#\"\"\"}"

            # Check if closing """ is on the same line
            if [[ "$ml_content" == *'"""'* ]]; then
                ml_content="${ml_content%\"\"\"*}"
            else
                # Collect lines until closing """
                local ml_result="$ml_content"
                while (( idx < ${#lines[@]} )); do
                    local ml_line="${lines[$idx]}"
                    idx=$((idx + 1))
                    if [[ "$ml_line" == *'"""'* ]]; then
                        ml_result+=$'\n'"${ml_line%%\"\"\"*}"
                        break
                    else
                        ml_result+=$'\n'"$ml_line"
                    fi
                done
                ml_content="$ml_result"
            fi
            printf '%s=%s\n' "$full_key" "$ml_content"
            continue
        fi

        # Handle arrays (possibly multiline)
        if [[ "$value" == "["* ]]; then
            local full_array="$value"

            # Check if array is complete (balanced brackets)
            local open=0 close=0 ci
            for ((ci=0; ci<${#full_array}; ci++)); do
                [[ "${full_array:$ci:1}" == "[" ]] && open=$((open + 1))
                [[ "${full_array:$ci:1}" == "]" ]] && close=$((close + 1))
            done

            while (( open > close )) && (( idx < ${#lines[@]} )); do
                local arr_line="${lines[$idx]}"
                idx=$((idx + 1))
                local arr_stripped
                arr_stripped=$(_toml_strip_comment "$arr_line")
                arr_stripped=$(_toml_trim "$arr_stripped")
                full_array+=" $arr_stripped"
                for ((ci=0; ci<${#arr_stripped}; ci++)); do
                    [[ "${arr_stripped:$ci:1}" == "[" ]] && open=$((open + 1))
                    [[ "${arr_stripped:$ci:1}" == "]" ]] && close=$((close + 1))
                done
            done

            printf '%s=%s\n' "$full_key" "$full_array"
            continue
        fi

        # Handle inline tables
        if [[ "$value" == "{"*"}" ]]; then
            _toml_parse_inline_table "$full_key" "$value"
            continue
        fi

        # Regular value - unquote strings
        value=$(_toml_unquote "$value")
        printf '%s=%s\n' "$full_key" "$value"
    done
}

# @pre: file_path is a valid TOML file, key_path is dot-notation key
# @post: prints the value for the given key
# @idempotent: yes
# @returns: 0 if found, 1 if not found
#
# Get a specific value from a TOML file.
#
# Usage: toml_get "Cargo.toml" "package.name"
# Example: version=$(toml_get "pyproject.toml" "project.version")
toml_get() {
    local file="$1"
    local key="$2"

    if [[ -z "$file" || -z "$key" ]]; then
        return 1
    fi

    local result
    result=$(toml_parse "$file" | while IFS='=' read -r k v; do
        if [[ "$k" == "$key" ]]; then
            printf '%s' "$v"
            break
        fi
    done)

    if [[ -n "$result" ]]; then
        printf '%s\n' "$result"
        return 0
    fi
    return 1
}

# @pre: file_path is a valid TOML file, section is a table name
# @post: prints key=value pairs within that section
# @idempotent: yes
# @returns: 0 on success
#
# Get all key-value pairs within a specific TOML section.
#
# Usage: toml_get_section "Cargo.toml" "dependencies"
# Example: toml_get_section "pyproject.toml" "project"
toml_get_section() {
    local file="$1"
    local section="$2"

    if [[ -z "$file" || -z "$section" ]]; then
        return 1
    fi

    toml_parse "$file" | while IFS='=' read -r k v; do
        if [[ "$k" == "${section}."* ]]; then
            local sub_key="${k#${section}.}"
            printf '%s=%s\n' "$sub_key" "$v"
        fi
    done
}

# @pre: file_path is a valid TOML file
# @post: prints JSON object representation
# @idempotent: yes
# @returns: 0 on success
#
# Convert a TOML file to JSON format.
#
# Usage: toml_to_json "Cargo.toml"
# Example: toml_to_json "pyproject.toml" | jq '.project.name'
toml_to_json() {
    local file="$1"

    if [[ -z "$file" ]]; then
        printf '{}'
        return 1
    fi

    local -a keys=()
    local -a values=()

    while IFS='=' read -r k v; do
        keys+=("$k")
        values+=("$v")
    done < <(toml_parse "$file")

    if [[ ${#keys[@]} -eq 0 ]]; then
        printf '{}'
        return 0
    fi

    # Build nested JSON from flat key=value pairs
    local json="{"
    local first=true

    local idx
    for ((idx=0; idx<${#keys[@]}; idx++)); do
        local key="${keys[$idx]}"
        local val="${values[$idx]}"

        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=","
        fi

        local escaped_key escaped_val
        escaped_key=$(_toml_json_escape "$key")

        # Determine value type for JSON
        case "$val" in
            true|false)
                json+="\"$escaped_key\":$val"
                ;;
            [0-9]*)
                if [[ "$val" =~ ^-?[0-9]+$ ]]; then
                    json+="\"$escaped_key\":$val"
                elif [[ "$val" =~ ^-?[0-9]+\.[0-9]+$ ]]; then
                    json+="\"$escaped_key\":$val"
                else
                    escaped_val=$(_toml_json_escape "$val")
                    json+="\"$escaped_key\":\"$escaped_val\""
                fi
                ;;
            -[0-9]*)
                if [[ "$val" =~ ^-?[0-9]+$ ]]; then
                    json+="\"$escaped_key\":$val"
                elif [[ "$val" =~ ^-?[0-9]+\.[0-9]+$ ]]; then
                    json+="\"$escaped_key\":$val"
                else
                    escaped_val=$(_toml_json_escape "$val")
                    json+="\"$escaped_key\":\"$escaped_val\""
                fi
                ;;
            "["*"]")
                # Array value - convert to JSON array
                local arr_json
                arr_json=$(_toml_array_to_json "$val")
                json+="\"$escaped_key\":$arr_json"
                ;;
            *)
                escaped_val=$(_toml_json_escape "$val")
                json+="\"$escaped_key\":\"$escaped_val\""
                ;;
        esac
    done

    json+="}"
    printf '%s' "$json"
}

# Convert a TOML array string to JSON array
_toml_array_to_json() {
    local arr="$1"
    # Strip outer brackets
    arr="${arr#\[}"
    arr="${arr%\]}"
    arr=$(_toml_trim "$arr")

    if [[ -z "$arr" ]]; then
        printf '[]'
        return 0
    fi

    local json="["
    local first=true
    local i=0 len=${#arr}
    local elem="" in_quote="" quote_char="" depth=0

    while (( i < len )); do
        local ch="${arr:$i:1}"

        if [[ -n "$in_quote" ]]; then
            if [[ "$ch" == "$quote_char" && "${arr:$((i > 0 ? i-1 : 0)):1}" != "\\" ]]; then
                in_quote=""
            fi
            elem+="$ch"
        elif [[ "$ch" == '"' || "$ch" == "'" ]]; then
            in_quote=1
            quote_char="$ch"
            elem+="$ch"
        elif [[ "$ch" == '[' ]]; then
            depth=$((depth + 1))
            elem+="$ch"
        elif [[ "$ch" == ']' ]]; then
            depth=$((depth - 1))
            elem+="$ch"
        elif [[ "$ch" == ',' && $depth -eq 0 ]]; then
            elem=$(_toml_trim "$elem")
            if [[ -n "$elem" ]]; then
                [[ "$first" == "true" ]] && first=false || json+=","
                json+=$(_toml_value_to_json "$elem")
            fi
            elem=""
        else
            elem+="$ch"
        fi
        i=$((i + 1))
    done

    elem=$(_toml_trim "$elem")
    if [[ -n "$elem" ]]; then
        [[ "$first" == "true" ]] && first=false || json+=","
        json+=$(_toml_value_to_json "$elem")
    fi

    json+="]"
    printf '%s' "$json"
}

# Convert a single TOML value to JSON representation
_toml_value_to_json() {
    local val="$1"
    case "$val" in
        true|false)
            printf '%s' "$val"
            ;;
        '"'*'"')
            local unq="${val#\"}"
            unq="${unq%\"}"
            local escaped
            escaped=$(_toml_json_escape "$unq")
            printf '"%s"' "$escaped"
            ;;
        "'"*"'")
            local unq="${val#\'}"
            unq="${unq%\'}"
            local escaped
            escaped=$(_toml_json_escape "$unq")
            printf '"%s"' "$escaped"
            ;;
        "["*"]")
            _toml_array_to_json "$val"
            ;;
        *)
            if [[ "$val" =~ ^-?[0-9]+$ ]]; then
                printf '%s' "$val"
            elif [[ "$val" =~ ^-?[0-9]+\.[0-9]+$ ]]; then
                printf '%s' "$val"
            else
                local escaped
                escaped=$(_toml_json_escape "$val")
                printf '"%s"' "$escaped"
            fi
            ;;
    esac
}

# @pre: file_path is a valid TOML file
# @post: prints section/table names, one per line
# @idempotent: yes
# @returns: 0 on success
#
# List all sections (table names) in a TOML file.
#
# Usage: toml_sections "Cargo.toml"
# Example: toml_sections "pyproject.toml" | grep "project"
toml_sections() {
    local file="$1"

    if [[ -z "$file" || ! -f "$file" ]]; then
        return 1
    fi

    local -a sections=()

    while IFS= read -r line; do
        local trimmed
        trimmed=$(_toml_trim "$line")

        # Array of tables
        if [[ "$trimmed" == "[["*"]]" ]]; then
            local section="${trimmed#\[\[}"
            section="${section%\]\]}"
            section=$(_toml_trim "$section")
            # Add if not already present
            local found=0
            for s in "${sections[@]}"; do
                [[ "$s" == "$section" ]] && { found=1; break; }
            done
            [[ $found -eq 0 ]] && sections+=("$section")
            continue
        fi

        # Regular tables
        if [[ "$trimmed" == "["*"]" && "$trimmed" != "[["* ]]; then
            local section="${trimmed#\[}"
            section="${section%\]}"
            section=$(_toml_trim "$section")
            sections+=("$section")
        fi
    done < "$file"

    for s in "${sections[@]}"; do
        printf '%s\n' "$s"
    done
}

# @pre: file_path is a valid TOML file
# @post: prints all keys in dot-notation, one per line
# @idempotent: yes
# @returns: 0 on success
#
# List all keys (flattened dot-notation) in a TOML file.
#
# Usage: toml_keys "Cargo.toml"
# Example: toml_keys "pyproject.toml" | wc -l
toml_keys() {
    local file="$1"

    if [[ -z "$file" ]]; then
        return 1
    fi

    toml_parse "$file" | while IFS='=' read -r k _; do
        printf '%s\n' "$k"
    done
}

# @pre: file_path is a valid TOML file, key_path is dot-notation key
# @post: returns 0 if key exists, 1 if not
# @idempotent: yes
# @returns: 0=exists, 1=not found
#
# Check if a key exists in a TOML file.
#
# Usage: toml_has "Cargo.toml" "package.name" && echo "exists"
# Example: if toml_has "pyproject.toml" "project.version"; then ...
toml_has() {
    local file="$1"
    local key="$2"

    if [[ -z "$file" || -z "$key" ]]; then
        return 1
    fi

    local _found=0
    while IFS='=' read -r k _; do
        if [[ "$k" == "$key" ]]; then
            _found=1
            break
        fi
    done < <(toml_parse "$file")
    [[ $_found -eq 1 ]]
}

# @pre: file_path is a valid TOML file, key_path points to an array value
# @post: prints array elements, one per line
# @idempotent: yes
# @returns: 0 on success, 1 if key not found or not an array
#
# Get array elements from a TOML file.
#
# Usage: toml_get_array "Cargo.toml" "package.keywords"
# Example: toml_get_array "pyproject.toml" "project.classifiers"
toml_get_array() {
    local file="$1"
    local key="$2"

    if [[ -z "$file" || -z "$key" ]]; then
        return 1
    fi

    local raw_value
    raw_value=$(toml_parse "$file" | while IFS='=' read -r k v; do
        if [[ "$k" == "$key" ]]; then
            printf '%s' "$v"
            break
        fi
    done)

    if [[ -z "$raw_value" ]]; then
        return 1
    fi

    # Strip brackets
    if [[ "$raw_value" != "["*"]" ]]; then
        # Not an array, just print as single element
        printf '%s\n' "$raw_value"
        return 0
    fi

    local arr="${raw_value#\[}"
    arr="${arr%\]}"
    arr=$(_toml_trim "$arr")

    [[ -z "$arr" ]] && return 0

    # Parse array elements
    local i=0 len=${#arr}
    local elem="" in_quote="" quote_char="" depth=0

    while (( i < len )); do
        local ch="${arr:$i:1}"

        if [[ -n "$in_quote" ]]; then
            if [[ "$ch" == "$quote_char" && "${arr:$((i > 0 ? i-1 : 0)):1}" != "\\" ]]; then
                in_quote=""
            fi
            elem+="$ch"
        elif [[ "$ch" == '"' || "$ch" == "'" ]]; then
            in_quote=1
            quote_char="$ch"
            elem+="$ch"
        elif [[ "$ch" == '[' ]]; then
            depth=$((depth + 1))
            elem+="$ch"
        elif [[ "$ch" == ']' ]]; then
            depth=$((depth - 1))
            elem+="$ch"
        elif [[ "$ch" == ',' && $depth -eq 0 ]]; then
            elem=$(_toml_trim "$elem")
            if [[ -n "$elem" ]]; then
                elem=$(_toml_unquote "$elem")
                printf '%s\n' "$elem"
            fi
            elem=""
        else
            elem+="$ch"
        fi
        i=$((i + 1))
    done

    elem=$(_toml_trim "$elem")
    if [[ -n "$elem" ]]; then
        elem=$(_toml_unquote "$elem")
        printf '%s\n' "$elem"
    fi
}

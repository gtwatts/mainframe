#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/bridge.sh - Format Detection and Conversion Library
# =============================================================================
# Description: Bridge between data formats - auto-detect and convert between
#              JSON, CSV, YAML, XML, INI, NDJSON, and key-value formats
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe bridges the gap between your data and sanity."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_BRIDGE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_BRIDGE_LOADED=1

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Escape string for JSON output
_bridge_json_escape() {
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

# Trim leading and trailing whitespace
_bridge_trim() {
    local str="$1"
    str="${str#"${str%%[![:space:]]*}"}"
    str="${str%"${str##*[![:space:]]}"}"
    printf '%s' "$str"
}

# Check if value looks like a JSON number
_bridge_is_number() {
    local val="$1"
    [[ "$val" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]
}

# Check if value looks like a JSON boolean
_bridge_is_bool() {
    local val="$1"
    [[ "$val" == "true" || "$val" == "false" ]]
}

# Escape a value for CSV output (quotes if needed)
_bridge_csv_escape() {
    local value="$1"
    local needs_quote=false

    # Check if quoting needed
    if [[ "$value" == *","* ]] || \
       [[ "$value" == *'"'* ]] || \
       [[ "$value" == *$'\n'* ]] || \
       [[ "$value" == *$'\r'* ]] || \
       [[ "$value" =~ ^[[:space:]] ]] || \
       [[ "$value" =~ [[:space:]]$ ]]; then
        needs_quote=true
    fi

    if $needs_quote; then
        # Escape quotes by doubling them
        local escaped="${value//\"/\"\"}"
        printf '"%s"' "$escaped"
    else
        printf '%s' "$value"
    fi
}

# Escape string for XML output
# Note: & in replacement means "matched string" so we must escape with \&
_bridge_xml_escape() {
    local str="$1"
    # Must escape & first before adding new &-entities
    str="${str//&/\&amp;}"
    str="${str//</\&lt;}"
    str="${str//>/\&gt;}"
    str="${str//\"/\&quot;}"
    str="${str//\'/\&apos;}"
    printf '%s' "$str"
}

# Unescape XML entities
_bridge_xml_unescape() {
    local str="$1"
    str="${str//&lt;/<}"
    str="${str//&gt;/>}"
    str="${str//&quot;/\"}"
    str="${str//&apos;/\'}"
    # Note: & in replacement means "matched string" so we escape it
    str="${str//&amp;/\&}"
    printf '%s' "$str"
}

# =============================================================================
# FORMAT DETECTION
# =============================================================================

# @pre: content is a string to analyze
# @post: prints detected format name
# @idempotent: yes
# @returns: 0 on success
#
# Detect the format of content by analyzing its structure.
# Returns: json|csv|yaml|xml|ini|ndjson|kv|unknown
#
# Usage: bridge_detect "$content"
# Example: format=$(bridge_detect '{"name":"John"}')  # json
bridge_detect() {
    local content="$1"

    # Handle empty input
    if [[ -z "$content" ]]; then
        printf 'unknown'
        return 0
    fi

    # Trim leading/trailing spaces (but preserve newlines for multi-line detection)
    local trimmed="$content"
    # Trim leading spaces/tabs on first line only
    trimmed="${trimmed#"${trimmed%%[![:blank:]]*}"}"
    # Trim trailing spaces/tabs on last portion
    trimmed="${trimmed%"${trimmed##*[![:blank:]]}"}"

    # NDJSON detection FIRST (multiple lines, each starting with { and ending with })
    # Must check before single JSON to avoid false positive
    local first_line second_line
    first_line=$(printf '%s' "$trimmed" | head -n1)
    # Trim the first line for pattern matching
    first_line="${first_line#"${first_line%%[![:space:]]*}"}"
    first_line="${first_line%"${first_line##*[![:space:]]}"}"
    second_line=$(printf '%s' "$trimmed" | sed -n '2p')
    # Trim the second line for pattern matching
    second_line="${second_line#"${second_line%%[![:space:]]*}"}"
    second_line="${second_line%"${second_line##*[![:space:]]}"}"

    if [[ "$first_line" == "{"*"}" ]] && [[ -n "$second_line" ]] && [[ "$second_line" == "{"*"}" ]]; then
        printf 'ndjson'
        return 0
    fi

    # JSON object or array (single object/array, not multi-line NDJSON)
    if [[ "$trimmed" == "{"* && "$trimmed" == *"}" ]]; then
        printf 'json'
        return 0
    fi
    if [[ "$trimmed" == "["* && "$trimmed" == *"]" ]]; then
        printf 'json'
        return 0
    fi

    # XML (starts with < and has matching closing)
    if [[ "$trimmed" == "<?xml"* ]] || [[ "$trimmed" == "<"[a-zA-Z]* ]]; then
        printf 'xml'
        return 0
    fi

    # INI format (sections like [section] or key=value without quotes)
    if [[ "$trimmed" == "["*"]"* ]] && [[ "$trimmed" == *$'\n'* ]]; then
        # Has section headers
        printf 'ini'
        return 0
    fi

    # CSV (comma-separated, possibly with quotes, has header-like first line)
    if [[ "$trimmed" == *","* ]]; then
        # Check if it looks like CSV (multiple commas, possibly quoted fields)
        local comma_count
        comma_count=$(printf '%s' "$first_line" | tr -cd ',' | wc -c)
        if [[ $comma_count -gt 0 ]]; then
            # Check second line has similar structure
            if [[ -n "$second_line" ]]; then
                local second_comma_count
                second_comma_count=$(printf '%s' "$second_line" | tr -cd ',' | wc -c)
                if [[ $comma_count -eq $second_comma_count ]]; then
                    printf 'csv'
                    return 0
                fi
            else
                # Single line with commas could be CSV
                printf 'csv'
                return 0
            fi
        fi
    fi

    # YAML (indentation-based, key: value patterns, or starts with ---)
    if [[ "$trimmed" == "---"* ]] || [[ "$trimmed" == *": "* && "$trimmed" != *"="* ]]; then
        # Check for YAML-style key: value (without equals)
        if [[ "$first_line" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*:[[:space:]] ]]; then
            printf 'yaml'
            return 0
        fi
        if [[ "$trimmed" == "---"* ]]; then
            printf 'yaml'
            return 0
        fi
    fi

    # Key-value format (key=value on each line)
    if [[ "$first_line" == *"="* ]] && [[ "$first_line" != *","* ]]; then
        # Check if it looks like key=value pairs
        if [[ "$first_line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*= ]]; then
            printf 'kv'
            return 0
        fi
    fi

    printf 'unknown'
    return 0
}

# @pre: path is a file path
# @post: prints detected format name
# @idempotent: yes
# @returns: 0 on success, 1 if file not found
#
# Detect format from file (uses extension hint + content analysis).
#
# Usage: bridge_detect_file "data.json"
# Example: format=$(bridge_detect_file "/path/to/data.csv")
bridge_detect_file() {
    local path="$1"

    if [[ ! -f "$path" ]]; then
        printf 'unknown'
        return 1
    fi

    # Get extension hint
    local ext="${path##*.}"
    ext="${ext,,}"  # lowercase

    # Known extensions
    case "$ext" in
        json) printf 'json'; return 0 ;;
        csv)  printf 'csv'; return 0 ;;
        yaml|yml) printf 'yaml'; return 0 ;;
        xml)  printf 'xml'; return 0 ;;
        ini|conf|cfg) printf 'ini'; return 0 ;;
        ndjson|jsonl) printf 'ndjson'; return 0 ;;
    esac

    # Fall back to content detection
    local content
    content=$(head -c 4096 "$path")
    bridge_detect "$content"
}

# =============================================================================
# JSON <-> CSV CONVERSIONS
# =============================================================================

# @pre: stdin is JSON array of objects
# @post: prints CSV to stdout
# @idempotent: yes
# @returns: 0 on success
#
# Convert JSON array of objects to CSV format.
# Streaming: reads line by line, extracts keys from first object.
#
# Usage: echo '[{"name":"John","age":30}]' | bridge_json_to_csv
# Example: cat data.json | bridge_json_to_csv > output.csv
bridge_json_to_csv() {
    local json=""
    local line
    local -a headers=()
    # shellcheck disable=SC2034 # Used via nameref in _bridge_json_object_to_csv_row
    local headers_printed=false
    local in_object=false
    local in_array=false
    local in_string=false
    local depth=0
    local object_buffer=""
    local char prev_char=""

    # Read all input
    while IFS= read -r line || [[ -n "$line" ]]; do
        json+="$line"
    done

    # Simple state machine to extract objects
    local len=${#json}
    local i=0

    while ((i < len)); do
        char="${json:i:1}"

        if $in_string; then
            object_buffer+="$char"
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
            fi
        else
            case "$char" in
                '[')
                    if ! $in_array && ! $in_object; then
                        in_array=true
                    else
                        object_buffer+="$char"
                        ((depth++)) || true
                    fi
                    ;;
                ']')
                    if [[ $depth -eq 0 ]] && $in_array && ! $in_object; then
                        in_array=false
                    else
                        object_buffer+="$char"
                        ((depth--)) || true
                    fi
                    ;;
                '{')
                    if $in_array && ! $in_object; then
                        in_object=true
                        object_buffer="{"
                    else
                        object_buffer+="$char"
                        ((depth++)) || true
                    fi
                    ;;
                '}')
                    if $in_object && [[ $depth -eq 0 ]]; then
                        object_buffer+="}"
                        in_object=false

                        # Process completed object
                        _bridge_json_object_to_csv_row "$object_buffer" headers_printed headers
                        # shellcheck disable=SC2034
                        headers_printed=true
                        object_buffer=""
                    else
                        object_buffer+="$char"
                        ((depth--)) || true
                    fi
                    ;;
                '"')
                    in_string=true
                    object_buffer+="$char"
                    ;;
                *)
                    if $in_object; then
                        object_buffer+="$char"
                    fi
                    ;;
            esac
        fi

        prev_char="$char"
        ((i++)) || true
    done
}

# Internal: convert a single JSON object to CSV row
_bridge_json_object_to_csv_row() {
    local json="$1"
    local -n _headers_printed_ref=$2
    local -n _headers_ref=$3

    local -a keys=()
    local -A values=()

    # Parse JSON object to extract key-value pairs
    local len=${#json}
    local i=1  # Skip opening brace
    local in_string=false
    local in_key=false
    local in_value=false
    local depth=0
    local current_key=""
    local current_value=""
    local char prev_char=""

    while ((i < len - 1)); do  # Skip closing brace
        char="${json:i:1}"

        if $in_string; then
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
                if $in_key; then
                    in_key=false
                elif $in_value; then
                    # String value complete
                    :
                fi
            else
                if $in_key; then
                    current_key+="$char"
                elif $in_value; then
                    current_value+="$char"
                fi
            fi
        else
            case "$char" in
                '"')
                    in_string=true
                    if ! $in_value && [[ -z "$current_key" || -n "${values[$current_key]+x}" ]]; then
                        in_key=true
                        current_key=""
                    elif $in_value; then
                        :  # Start of string value
                    fi
                    ;;
                ':')
                    if [[ $depth -eq 0 ]]; then
                        in_value=true
                        current_value=""
                    else
                        current_value+="$char"
                    fi
                    ;;
                ',')
                    if [[ $depth -eq 0 ]] && $in_value; then
                        # Save current key-value
                        current_value=$(_bridge_trim "$current_value")
                        values["$current_key"]="$current_value"
                        if ! $_headers_printed_ref; then
                            keys+=("$current_key")
                        fi
                        in_value=false
                        current_key=""
                        current_value=""
                    elif $in_value; then
                        current_value+="$char"
                    fi
                    ;;
                '{' | '[')
                    if $in_value; then
                        current_value+="$char"
                        ((depth++)) || true
                    fi
                    ;;
                '}' | ']')
                    if $in_value && [[ $depth -gt 0 ]]; then
                        current_value+="$char"
                        ((depth--)) || true
                    fi
                    ;;
                ' ' | $'\t' | $'\n' | $'\r')
                    # Skip whitespace outside strings
                    ;;
                *)
                    if $in_value; then
                        current_value+="$char"
                    fi
                    ;;
            esac
        fi

        prev_char="$char"
        ((i++)) || true
    done

    # Save last key-value pair
    if [[ -n "$current_key" ]] && $in_value; then
        current_value=$(_bridge_trim "$current_value")
        values["$current_key"]="$current_value"
        if ! $_headers_printed_ref; then
            keys+=("$current_key")
        fi
    fi

    # Print headers if first object
    if ! $_headers_printed_ref; then
        _headers_ref=("${keys[@]}")
        local first=true
        for key in "${keys[@]}"; do
            $first || printf ','
            first=false
            _bridge_csv_escape "$key"
        done
        printf '\n'
    fi

    # Print values row
    local first=true
    for key in "${_headers_ref[@]}"; do
        $first || printf ','
        first=false
        local val="${values[$key]:-}"
        # Remove JSON string quotes if present
        if [[ "$val" == '"'*'"' ]]; then
            val="${val:1:${#val}-2}"
        fi
        # Handle JSON escape sequences
        val="${val//\\n/$'\n'}"
        val="${val//\\t/$'\t'}"
        val="${val//\\\"/\"}"
        val="${val//\\\\/\\}"
        _bridge_csv_escape "$val"
    done
    printf '\n'
}

# @pre: stdin is CSV content
# @post: prints JSON array to stdout
# @idempotent: yes
# @returns: 0 on success
#
# Convert CSV to JSON array of objects.
# First row is treated as headers (keys).
#
# Usage: cat data.csv | bridge_csv_to_json
# Example: bridge_csv_to_json < input.csv > output.json
bridge_csv_to_json() {
    local -a headers=()
    local first_row=true
    local first_obj=true
    local line

    printf '['

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines
        [[ -z "$(_bridge_trim "$line")" ]] && continue

        # Parse CSV line
        local -a fields=()
        _bridge_parse_csv_line "$line" fields

        if $first_row; then
            # First row is headers
            headers=("${fields[@]}")
            first_row=false
            continue
        fi

        # Build JSON object
        $first_obj || printf ','
        first_obj=false
        printf '{'

        local first_field=true
        local i
        for ((i=0; i<${#headers[@]}; i++)); do
            $first_field || printf ','
            first_field=false

            local key="${headers[$i]}"
            local val="${fields[$i]:-}"

            printf '"%s":' "$(_bridge_json_escape "$key")"

            # Auto-detect type
            if [[ -z "$val" ]]; then
                printf 'null'
            elif [[ "$val" == "null" ]]; then
                printf 'null'
            elif [[ "$val" == "true" || "$val" == "false" ]]; then
                printf '%s' "$val"
            elif _bridge_is_number "$val"; then
                printf '%s' "$val"
            else
                printf '"%s"' "$(_bridge_json_escape "$val")"
            fi
        done

        printf '}'
    done

    printf ']\n'
}

# Internal: parse a single CSV line into array
_bridge_parse_csv_line() {
    local line="$1"
    local -n _fields_ref=$2
    local len=${#line}
    local i=0
    local field=""
    local in_quotes=false
    local char next_char

    _fields_ref=()

    while ((i < len)); do
        char="${line:i:1}"
        next_char="${line:$((i+1)):1}"

        if $in_quotes; then
            if [[ "$char" == '"' ]]; then
                # Check for escaped quote (doubled)
                if [[ "$next_char" == '"' ]]; then
                    field+='"'
                    ((i++)) || true
                else
                    # End of quoted section
                    in_quotes=false
                fi
            else
                field+="$char"
            fi
        else
            if [[ "$char" == '"' ]]; then
                in_quotes=true
            elif [[ "$char" == ',' ]]; then
                _fields_ref+=("$field")
                field=""
            else
                field+="$char"
            fi
        fi
        ((i++)) || true
    done

    # Add final field
    _fields_ref+=("$field")
}

# =============================================================================
# JSON <-> NDJSON CONVERSIONS
# =============================================================================

# @pre: stdin is JSON array
# @post: prints NDJSON to stdout (one JSON object per line)
# @idempotent: yes
# @returns: 0 on success
#
# Convert JSON array to newline-delimited JSON.
# Each element of the array becomes a separate line.
#
# Usage: echo '[{"a":1},{"a":2}]' | bridge_json_to_ndjson
# Example: cat array.json | bridge_json_to_ndjson > data.ndjson
bridge_json_to_ndjson() {
    local json=""
    local line

    # Read all input
    while IFS= read -r line || [[ -n "$line" ]]; do
        json+="$line"
    done

    # Parse array and output each element on its own line
    local len=${#json}
    local i=0
    local in_string=false
    local in_array=false
    local depth=0
    local element=""
    local char prev_char=""

    while ((i < len)); do
        char="${json:i:1}"

        if $in_string; then
            element+="$char"
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
            fi
        else
            case "$char" in
                '[')
                    if ! $in_array; then
                        in_array=true
                    else
                        element+="$char"
                        ((depth++)) || true
                    fi
                    ;;
                ']')
                    if [[ $depth -eq 0 ]] && $in_array; then
                        # End of array - output last element if any
                        element=$(_bridge_trim "$element")
                        [[ -n "$element" ]] && printf '%s\n' "$element"
                        in_array=false
                    else
                        element+="$char"
                        ((depth--)) || true
                    fi
                    ;;
                ',')
                    if [[ $depth -eq 0 ]] && $in_array; then
                        # Element separator - output current element
                        element=$(_bridge_trim "$element")
                        [[ -n "$element" ]] && printf '%s\n' "$element"
                        element=""
                    else
                        element+="$char"
                    fi
                    ;;
                '"')
                    element+="$char"
                    in_string=true
                    ;;
                '{')
                    if $in_array; then
                        element+="$char"
                        ((depth++)) || true
                    fi
                    ;;
                '}')
                    element+="$char"
                    ((depth--)) || true
                    ;;
                ' ' | $'\t' | $'\n' | $'\r')
                    # Preserve whitespace only inside elements
                    if [[ -n "$element" ]]; then
                        element+="$char"
                    fi
                    ;;
                *)
                    element+="$char"
                    ;;
            esac
        fi

        prev_char="$char"
        ((i++)) || true
    done
}

# @pre: stdin is NDJSON (one JSON object per line)
# @post: prints JSON array to stdout
# @idempotent: yes
# @returns: 0 on success
#
# Convert newline-delimited JSON to JSON array.
#
# Usage: cat data.ndjson | bridge_ndjson_to_json
# Example: bridge_ndjson_to_json < events.jsonl > array.json
bridge_ndjson_to_json() {
    local first=true
    local line

    printf '['

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines
        line=$(_bridge_trim "$line")
        [[ -z "$line" ]] && continue

        $first || printf ','
        first=false
        printf '%s' "$line"
    done

    printf ']\n'
}

# =============================================================================
# YAML <-> JSON CONVERSIONS
# =============================================================================

# @pre: stdin is YAML content
# @post: prints JSON to stdout
# @idempotent: yes
# @returns: 0 on success
#
# Convert YAML to JSON format.
# Note: Relies on yaml.sh if available, otherwise uses simplified parser.
#
# Usage: cat config.yaml | bridge_yaml_to_json
# Example: bridge_yaml_to_json < values.yaml > values.json
bridge_yaml_to_json() {
    local content=""
    local line

    # Read all input
    while IFS= read -r line || [[ -n "$line" ]]; do
        content+="$line"$'\n'
    done

    # Check if yaml.sh functions are available
    if type -t yaml_parse &>/dev/null; then
        # Write to temp file and use yaml_to_json
        local tmpfile
        tmpfile=$(mktemp)
        printf '%s' "$content" > "$tmpfile"
        yaml_to_json "$tmpfile"
        rm -f "$tmpfile"
        return 0
    fi

    # Simplified YAML to JSON conversion
    # Handles flat key: value pairs
    printf '{'
    local first=true
    local key val

    while IFS= read -r line; do
        # Skip empty lines and comments
        line=$(_bridge_trim "$line")
        [[ -z "$line" || "$line" == "#"* || "$line" == "---" || "$line" == "..." ]] && continue

        # Parse key: value
        if [[ "$line" == *": "* ]]; then
            key="${line%%:*}"
            val="${line#*: }"
            key=$(_bridge_trim "$key")
            val=$(_bridge_trim "$val")

            # Remove quotes from value
            if [[ "$val" == '"'*'"' ]]; then
                val="${val:1:${#val}-2}"
            elif [[ "$val" == "'"*"'" ]]; then
                val="${val:1:${#val}-2}"
            fi

            $first || printf ','
            first=false

            printf '"%s":' "$(_bridge_json_escape "$key")"

            # Determine type
            if [[ -z "$val" || "$val" == "~" || "$val" == "null" ]]; then
                printf 'null'
            elif [[ "$val" == "true" || "$val" == "false" ]]; then
                printf '%s' "$val"
            elif _bridge_is_number "$val"; then
                printf '%s' "$val"
            else
                printf '"%s"' "$(_bridge_json_escape "$val")"
            fi
        fi
    done <<< "$content"

    printf '}\n'
}

# @pre: stdin is JSON content
# @post: prints YAML to stdout
# @idempotent: yes
# @returns: 0 on success
#
# Convert JSON to YAML format.
# Handles flat objects only (no nested structures).
#
# Usage: cat config.json | bridge_json_to_yaml
# Example: bridge_json_to_yaml < values.json > values.yaml
bridge_json_to_yaml() {
    local json=""
    local line

    # Read all input
    while IFS= read -r line || [[ -n "$line" ]]; do
        json+="$line"
    done

    # Trim whitespace
    json="$(_bridge_trim "$json")"

    # Handle arrays - process each element as separate YAML document
    if [[ "$json" == "["* && "$json" == *"]" ]]; then
        _bridge_json_array_to_yaml "$json"
        return 0
    fi

    # Simple JSON object to YAML
    local len=${#json}
    local i=0
    local in_string=false
    local in_key=false
    local in_value=false
    local depth=0
    local current_key=""
    local current_value=""
    local char prev_char=""

    while ((i < len)); do
        char="${json:i:1}"

        if $in_string; then
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
                if $in_key; then
                    in_key=false
                elif $in_value; then
                    # Add closing quote to value for string values
                    current_value+='"'
                fi
            else
                if $in_key; then
                    current_key+="$char"
                elif $in_value; then
                    current_value+="$char"
                fi
            fi
        else
            case "$char" in
                '{' | '[')
                    ((depth++)) || true
                    if $in_value; then
                        current_value+="$char"
                    fi
                    ;;
                '}' | ']')
                    ((depth--)) || true
                    if $in_value && [[ $depth -gt 0 ]]; then
                        current_value+="$char"
                    elif $in_value; then
                        # End of value at top level
                        _bridge_output_yaml_pair "$current_key" "$current_value"
                        current_key=""
                        current_value=""
                        in_value=false
                    fi
                    ;;
                '"')
                    in_string=true
                    if [[ $depth -eq 1 ]] && ! $in_value; then
                        in_key=true
                        current_key=""
                    elif $in_value; then
                        current_value+='"'
                    fi
                    ;;
                ':')
                    if [[ $depth -eq 1 ]] && ! $in_value; then
                        in_value=true
                        current_value=""
                    elif $in_value; then
                        current_value+="$char"
                    fi
                    ;;
                ',')
                    if [[ $depth -eq 1 ]] && $in_value; then
                        _bridge_output_yaml_pair "$current_key" "$current_value"
                        current_key=""
                        current_value=""
                        in_value=false
                    elif $in_value; then
                        current_value+="$char"
                    fi
                    ;;
                ' ' | $'\t' | $'\n' | $'\r')
                    # Skip whitespace
                    if $in_value && [[ -n "$current_value" ]]; then
                        current_value+="$char"
                    fi
                    ;;
                *)
                    if $in_value; then
                        current_value+="$char"
                    fi
                    ;;
            esac
        fi

        prev_char="$char"
        ((i++)) || true
    done
}

# Internal: convert JSON array to YAML with list syntax
_bridge_json_array_to_yaml() {
    local json="$1"
    local len=${#json}
    local i=1  # Skip opening bracket
    local depth=0
    local current_obj=""
    local in_string=false
    local char prev_char=""
    local first_item=true

    while ((i < len - 1)); do  # Skip closing bracket
        char="${json:i:1}"

        if $in_string; then
            current_obj+="$char"
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
            fi
        else
            case "$char" in
                '"')
                    in_string=true
                    current_obj+="$char"
                    ;;
                '{')
                    ((depth++)) || true
                    current_obj+="$char"
                    ;;
                '}')
                    ((depth--)) || true
                    current_obj+="$char"
                    if [[ $depth -eq 0 ]]; then
                        # Output this object as YAML list item
                        if ! $first_item; then
                            printf '\n'
                        fi
                        first_item=false
                        printf -- '- '
                        # Parse the object and output key:value pairs
                        _bridge_json_obj_to_yaml_inline "$current_obj"
                        current_obj=""
                    fi
                    ;;
                ',')
                    if [[ $depth -eq 0 ]]; then
                        # Skip comma between array elements
                        :
                    else
                        current_obj+="$char"
                    fi
                    ;;
                ' ' | $'\t' | $'\n' | $'\r')
                    if [[ $depth -gt 0 ]]; then
                        current_obj+="$char"
                    fi
                    ;;
                *)
                    if [[ $depth -gt 0 ]]; then
                        current_obj+="$char"
                    fi
                    ;;
            esac
        fi

        prev_char="$char"
        ((i++)) || true
    done
    printf '\n'
}

# Internal: convert a single JSON object to inline YAML (for array items)
_bridge_json_obj_to_yaml_inline() {
    local json="$1"
    local len=${#json}
    local i=0
    local in_string=false
    local in_key=false
    local in_value=false
    local depth=0
    local current_key=""
    local current_value=""
    local char prev_char=""
    local first_pair=true

    while ((i < len)); do
        char="${json:i:1}"

        if $in_string; then
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
                if $in_key; then
                    in_key=false
                elif $in_value; then
                    current_value+='"'
                fi
            else
                if $in_key; then
                    current_key+="$char"
                elif $in_value; then
                    current_value+="$char"
                fi
            fi
        else
            case "$char" in
                '{')
                    ((depth++)) || true
                    if $in_value; then
                        current_value+="$char"
                    fi
                    ;;
                '}')
                    ((depth--)) || true
                    if $in_value && [[ $depth -gt 0 ]]; then
                        current_value+="$char"
                    elif $in_value; then
                        # End of value
                        if ! $first_pair; then
                            printf ', '
                        fi
                        first_pair=false
                        _bridge_output_yaml_value "$current_key" "$current_value"
                        current_key=""
                        current_value=""
                        in_value=false
                    fi
                    ;;
                '"')
                    in_string=true
                    if [[ $depth -eq 1 ]] && ! $in_value; then
                        in_key=true
                        current_key=""
                    elif $in_value; then
                        current_value+='"'
                    fi
                    ;;
                ':')
                    if [[ $depth -eq 1 ]] && ! $in_value; then
                        in_value=true
                        current_value=""
                    elif $in_value; then
                        current_value+="$char"
                    fi
                    ;;
                ',')
                    if [[ $depth -eq 1 ]] && $in_value; then
                        if ! $first_pair; then
                            printf ', '
                        fi
                        first_pair=false
                        _bridge_output_yaml_value "$current_key" "$current_value"
                        current_key=""
                        current_value=""
                        in_value=false
                    elif $in_value; then
                        current_value+="$char"
                    fi
                    ;;
                ' ' | $'\t' | $'\n' | $'\r')
                    if $in_value && [[ -n "$current_value" ]]; then
                        current_value+="$char"
                    fi
                    ;;
                *)
                    if $in_value; then
                        current_value+="$char"
                    fi
                    ;;
            esac
        fi

        prev_char="$char"
        ((i++)) || true
    done
}

# Internal: output a YAML key:value pair (inline format)
_bridge_output_yaml_value() {
    local key="$1"
    local val="$2"

    val=$(_bridge_trim "$val")

    # Handle different value types
    if [[ "$val" == "null" ]]; then
        printf '%s: ~' "$key"
    elif [[ "$val" == "true" || "$val" == "false" ]]; then
        printf '%s: %s' "$key" "$val"
    elif _bridge_is_number "$val"; then
        printf '%s: %s' "$key" "$val"
    elif [[ "$val" == '"'*'"' ]]; then
        # Quoted string - remove quotes
        val="${val:1:${#val}-2}"
        val="${val//\\n/$'\n'}"
        val="${val//\\t/$'\t'}"
        val="${val//\\\"/\"}"
        val="${val//\\\\/\\}"
        printf '%s: %s' "$key" "$val"
    else
        printf '%s: %s' "$key" "$val"
    fi
}

# Internal: output a single YAML key-value pair
_bridge_output_yaml_pair() {
    local key="$1"
    local val="$2"

    val=$(_bridge_trim "$val")

    # Handle different value types
    if [[ "$val" == "null" ]]; then
        printf '%s: ~\n' "$key"
    elif [[ "$val" == "true" || "$val" == "false" ]]; then
        printf '%s: %s\n' "$key" "$val"
    elif _bridge_is_number "$val"; then
        printf '%s: %s\n' "$key" "$val"
    elif [[ "$val" == '"'*'"' ]]; then
        # Quoted string - remove quotes and output
        val="${val:1:${#val}-2}"
        # Unescape JSON escapes
        val="${val//\\n/$'\n'}"
        val="${val//\\t/$'\t'}"
        val="${val//\\\"/\"}"
        val="${val//\\\\/\\}"
        # If value has special chars, quote it
        if [[ "$val" == *$'\n'* || "$val" == *":"* || "$val" == *"#"* ]]; then
            printf '%s: "%s"\n' "$key" "$(_bridge_json_escape "$val")"
        else
            printf '%s: %s\n' "$key" "$val"
        fi
    else
        printf '%s: %s\n' "$key" "$val"
    fi
}

# =============================================================================
# XML <-> JSON CONVERSIONS
# =============================================================================

# @pre: stdin is simple XML content
# @post: prints JSON to stdout
# @idempotent: yes
# @returns: 0 on success
#
# Convert simple XML to JSON format.
# Handles flat element structures only.
#
# Usage: echo '<root><name>John</name></root>' | bridge_xml_to_json
# Example: bridge_xml_to_json < data.xml > data.json
bridge_xml_to_json() {
    local xml=""
    local line

    # Read all input
    while IFS= read -r line || [[ -n "$line" ]]; do
        xml+="$line"
    done

    # Remove XML declaration if present
    xml="${xml#<?xml*?>}"

    printf '{'
    local first=true
    local tag content

    # Simple regex-based extraction of <tag>content</tag>
    while [[ "$xml" =~ \<([a-zA-Z_][a-zA-Z0-9_-]*)\>([^<]*)\</([a-zA-Z_][a-zA-Z0-9_-]*)\> ]]; do
        tag="${BASH_REMATCH[1]}"
        content="${BASH_REMATCH[2]}"
        local close_tag="${BASH_REMATCH[3]}"

        # Verify matching tags
        if [[ "$tag" == "$close_tag" ]]; then
            $first || printf ','
            first=false

            content=$(_bridge_xml_unescape "$content")
            content=$(_bridge_trim "$content")

            printf '"%s":' "$(_bridge_json_escape "$tag")"

            # Determine type
            if [[ -z "$content" ]]; then
                printf 'null'
            elif [[ "$content" == "true" || "$content" == "false" ]]; then
                printf '%s' "$content"
            elif _bridge_is_number "$content"; then
                printf '%s' "$content"
            else
                printf '"%s"' "$(_bridge_json_escape "$content")"
            fi
        fi

        # Remove matched portion and continue
        xml="${xml#*</"$close_tag">}"
    done

    printf '}\n'
}

# @pre: stdin is JSON object, root_tag is XML root element name
# @post: prints XML to stdout
# @idempotent: yes
# @returns: 0 on success
#
# Convert JSON object to simple XML format.
#
# Usage: echo '{"name":"John"}' | bridge_json_to_xml "person"
# Example: bridge_json_to_xml "config" < settings.json > settings.xml
bridge_json_to_xml() {
    local root_tag="${1:-root}"
    local json=""
    local line

    # Read all input
    while IFS= read -r line || [[ -n "$line" ]]; do
        json+="$line"
    done

    printf '<?xml version="1.0" encoding="UTF-8"?>\n'
    printf '<%s>\n' "$root_tag"

    # Parse JSON and output XML elements
    local len=${#json}
    local i=0
    local in_string=false
    local in_key=false
    local in_value=false
    local depth=0
    local current_key=""
    local current_value=""
    local char prev_char=""

    while ((i < len)); do
        char="${json:i:1}"

        if $in_string; then
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
                if $in_key; then
                    in_key=false
                fi
            else
                if $in_key; then
                    current_key+="$char"
                elif $in_value; then
                    current_value+="$char"
                fi
            fi
        else
            case "$char" in
                '{' | '[')
                    ((depth++)) || true
                    if $in_value; then
                        current_value+="$char"
                    fi
                    ;;
                '}' | ']')
                    ((depth--)) || true
                    if $in_value && [[ $depth -gt 0 ]]; then
                        current_value+="$char"
                    elif $in_value; then
                        _bridge_output_xml_element "$current_key" "$current_value"
                        current_key=""
                        current_value=""
                        in_value=false
                    fi
                    ;;
                '"')
                    in_string=true
                    if [[ $depth -eq 1 ]] && ! $in_value; then
                        in_key=true
                        current_key=""
                    fi
                    # Don't add quote to value - quotes are JSON syntax, not data
                    ;;
                ':')
                    if [[ $depth -eq 1 ]] && ! $in_value; then
                        in_value=true
                        current_value=""
                    elif $in_value; then
                        current_value+="$char"
                    fi
                    ;;
                ',')
                    if [[ $depth -eq 1 ]] && $in_value; then
                        _bridge_output_xml_element "$current_key" "$current_value"
                        current_key=""
                        current_value=""
                        in_value=false
                    elif $in_value; then
                        current_value+="$char"
                    fi
                    ;;
                ' ' | $'\t' | $'\n' | $'\r')
                    if $in_value && [[ -n "$current_value" ]]; then
                        current_value+="$char"
                    fi
                    ;;
                *)
                    if $in_value; then
                        current_value+="$char"
                    fi
                    ;;
            esac
        fi

        prev_char="$char"
        ((i++)) || true
    done

    printf '</%s>\n' "$root_tag"
}

# Internal: output a single XML element
_bridge_output_xml_element() {
    local tag="$1"
    local val="$2"

    val=$(_bridge_trim "$val")

    # Handle null
    if [[ "$val" == "null" ]]; then
        printf '  <%s/>\n' "$tag"
        return
    fi

    # Unescape JSON escapes (values are already unquoted)
    val="${val//\\n/$'\n'}"
    val="${val//\\t/$'\t'}"
    val="${val//\\\"/\"}"
    val="${val//\\\\/\\}"

    printf '  <%s>%s</%s>\n' "$tag" "$(_bridge_xml_escape "$val")" "$tag"
}

# =============================================================================
# UNIVERSAL CONVERTER
# =============================================================================

# @pre: stdin has source data, target_format is desired output format
# @post: prints converted data to stdout
# @idempotent: yes
# @returns: 0 on success, 1 on unsupported conversion
#
# Auto-detect source format and convert to target format.
# Supported targets: json, csv, yaml, xml, ndjson
#
# Usage: cat data.csv | bridge_convert "json"
# Example: bridge_convert "yaml" < config.json
bridge_convert() {
    local target_format="${1:-json}"
    local content=""
    local line

    # Read all input
    while IFS= read -r line || [[ -n "$line" ]]; do
        content+="$line"$'\n'
    done

    # Remove trailing newline
    content="${content%$'\n'}"

    # Detect source format
    local source_format
    source_format=$(bridge_detect "$content")

    # Handle same format (passthrough)
    if [[ "$source_format" == "$target_format" ]]; then
        printf '%s\n' "$content"
        return 0
    fi

    # Route to appropriate converter
    case "${source_format}:${target_format}" in
        json:csv)
            printf '%s' "$content" | bridge_json_to_csv
            ;;
        json:ndjson)
            printf '%s' "$content" | bridge_json_to_ndjson
            ;;
        json:yaml)
            printf '%s' "$content" | bridge_json_to_yaml
            ;;
        json:xml)
            printf '%s' "$content" | bridge_json_to_xml "root"
            ;;
        csv:json)
            printf '%s' "$content" | bridge_csv_to_json
            ;;
        ndjson:json)
            printf '%s' "$content" | bridge_ndjson_to_json
            ;;
        yaml:json)
            printf '%s' "$content" | bridge_yaml_to_json
            ;;
        xml:json)
            printf '%s' "$content" | bridge_xml_to_json
            ;;
        # Multi-hop conversions (via JSON)
        csv:yaml)
            printf '%s' "$content" | bridge_csv_to_json | bridge_json_to_yaml
            ;;
        csv:xml)
            printf '%s' "$content" | bridge_csv_to_json | bridge_json_to_xml "root"
            ;;
        csv:ndjson)
            printf '%s' "$content" | bridge_csv_to_json | bridge_json_to_ndjson
            ;;
        yaml:csv)
            printf '%s' "$content" | bridge_yaml_to_json | bridge_json_to_csv
            ;;
        yaml:xml)
            printf '%s' "$content" | bridge_yaml_to_json | bridge_json_to_xml "root"
            ;;
        yaml:ndjson)
            printf '%s' "$content" | bridge_yaml_to_json | bridge_json_to_ndjson
            ;;
        xml:csv)
            printf '%s' "$content" | bridge_xml_to_json | bridge_json_to_csv
            ;;
        xml:yaml)
            printf '%s' "$content" | bridge_xml_to_json | bridge_json_to_yaml
            ;;
        xml:ndjson)
            printf '%s' "$content" | bridge_xml_to_json | bridge_json_to_ndjson
            ;;
        ndjson:csv)
            printf '%s' "$content" | bridge_ndjson_to_json | bridge_json_to_csv
            ;;
        ndjson:yaml)
            printf '%s' "$content" | bridge_ndjson_to_json | bridge_json_to_yaml
            ;;
        ndjson:xml)
            printf '%s' "$content" | bridge_ndjson_to_json | bridge_json_to_xml "root"
            ;;
        *)
            printf 'error: unsupported conversion %s -> %s\n' "$source_format" "$target_format" >&2
            return 1
            ;;
    esac
}

# =============================================================================
# SCHEMA EXTRACTION
# =============================================================================

# @pre: stdin has data (JSON array, CSV, etc.)
# @post: prints schema description as JSON
# @idempotent: yes
# @returns: 0 on success
#
# Infer schema from input data.
# Returns JSON object with field names and detected types.
#
# Usage: cat data.json | bridge_schema_extract
# Example: bridge_schema_extract < users.csv
bridge_schema_extract() {
    local content=""
    local line

    # Read all input
    while IFS= read -r line || [[ -n "$line" ]]; do
        content+="$line"$'\n'
    done

    content="${content%$'\n'}"

    # Detect format
    local format
    format=$(bridge_detect "$content")

    # Convert to JSON if needed
    local json_content
    case "$format" in
        json)
            json_content="$content"
            ;;
        csv)
            json_content=$(printf '%s' "$content" | bridge_csv_to_json)
            ;;
        ndjson)
            json_content=$(printf '%s' "$content" | bridge_ndjson_to_json)
            ;;
        *)
            printf '{"error":"unsupported format for schema extraction: %s"}\n' "$format"
            return 1
            ;;
    esac

    # Parse JSON to extract schema
    printf '{"format":"%s","fields":{' "$format"

    # Extract first object to infer schema
    local first_obj=""
    local len=${#json_content}
    local i=0
    local depth=0
    local in_string=false
    local in_array=false
    local char prev_char=""

    while ((i < len)); do
        char="${json_content:i:1}"

        if $in_string; then
            first_obj+="$char"
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
            fi
        else
            case "$char" in
                '[')
                    in_array=true
                    ;;
                '{')
                    ((depth++)) || true
                    first_obj+="$char"
                    ;;
                '}')
                    first_obj+="$char"
                    ((depth--)) || true
                    if [[ $depth -eq 0 ]]; then
                        break  # Got first object
                    fi
                    ;;
                '"')
                    first_obj+="$char"
                    in_string=true
                    ;;
                *)
                    if [[ $depth -gt 0 ]]; then
                        first_obj+="$char"
                    fi
                    ;;
            esac
        fi

        prev_char="$char"
        ((i++)) || true
    done

    # Parse first object for field types
    local -A field_types=()
    len=${#first_obj}
    i=1  # Skip opening brace
    in_string=false
    local in_key=false
    local in_value=false
    local value_is_string=false
    depth=0
    local current_key=""
    local current_value=""
    prev_char=""

    while ((i < len - 1)); do
        char="${first_obj:i:1}"

        if $in_string; then
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
                if $in_key; then
                    in_key=false
                fi
            else
                if $in_key; then
                    current_key+="$char"
                elif $in_value; then
                    current_value+="$char"
                fi
            fi
        else
            case "$char" in
                '"')
                    in_string=true
                    if ! $in_value; then
                        in_key=true
                        current_key=""
                    else
                        # Starting a string value
                        value_is_string=true
                    fi
                    ;;
                ':')
                    if [[ $depth -eq 0 ]]; then
                        in_value=true
                        value_is_string=false
                        current_value=""
                    else
                        current_value+="$char"
                    fi
                    ;;
                ',')
                    if [[ $depth -eq 0 ]]; then
                        current_value=$(_bridge_trim "$current_value")
                        field_types["$current_key"]=$(_bridge_infer_type "$current_value" "$value_is_string")
                        in_value=false
                        value_is_string=false
                        current_key=""
                        current_value=""
                    else
                        current_value+="$char"
                    fi
                    ;;
                '{' | '[')
                    current_value+="$char"
                    ((depth++)) || true
                    ;;
                '}' | ']')
                    current_value+="$char"
                    ((depth--)) || true
                    ;;
                ' ' | $'\t' | $'\n' | $'\r')
                    ;;
                *)
                    if $in_value; then
                        current_value+="$char"
                    fi
                    ;;
            esac
        fi

        prev_char="$char"
        ((i++)) || true
    done

    # Handle last field
    if [[ -n "$current_key" ]]; then
        current_value=$(_bridge_trim "$current_value")
        field_types["$current_key"]=$(_bridge_infer_type "$current_value" "$value_is_string")
    fi

    # Output schema
    local first=true
    for key in "${!field_types[@]}"; do
        $first || printf ','
        first=false
        printf '"%s":"%s"' "$key" "${field_types[$key]}"
    done

    printf '}}\n'
}

# Internal: infer type from JSON value
_bridge_infer_type() {
    local val="$1"
    local is_string="${2:-false}"  # Flag if value came from quoted string

    if [[ -z "$val" || "$val" == "null" ]]; then
        printf 'null'
    elif [[ "$val" == "true" || "$val" == "false" ]]; then
        printf 'boolean'
    elif [[ "$val" =~ ^-?[0-9]+$ ]]; then
        printf 'integer'
    elif _bridge_is_number "$val"; then
        printf 'number'
    elif [[ "$val" == '"'* ]] || [[ "$is_string" == "true" ]]; then
        printf 'string'
    elif [[ "$val" == "["* ]]; then
        printf 'array'
    elif [[ "$val" == "{"* ]]; then
        printf 'object'
    else
        # Fallback: if it looks like text, it's a string
        if [[ "$val" =~ ^[a-zA-Z] ]]; then
            printf 'string'
        else
            printf 'unknown'
        fi
    fi
}

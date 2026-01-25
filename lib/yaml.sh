#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/yaml.sh - YAML Parser
# =============================================================================
# Description: Pure bash YAML parser for CI/CD configs, Docker Compose,
#              Kubernetes manifests, and other YAML files. Outputs flat
#              key=value pairs or JSON.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# LIMITATIONS (indentation-based parsing, not full YAML spec):
#   - Does not handle complex merge keys (<<:) beyond basic alias expansion
#   - Tags (!tag) are stripped, not interpreted
#   - Multi-document files (---): only first document parsed by default
#   - Complex keys (? key : value) not supported
#   - Binary data (!!binary) not supported
#   - Set type (!!set) not supported
#   - Very deeply nested structures (>20 levels) may be slow
#   - Flow collections inside block sequences may have edge cases
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_YAML_LOADED:-}" ]] && return 0
readonly _MAINFRAME_YAML_LOADED=1

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Escape a string for JSON output
_yaml_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Trim leading and trailing whitespace
_yaml_trim() {
    local str="$1"
    str="${str#"${str%%[![:space:]]*}"}"
    str="${str%"${str##*[![:space:]]}"}"
    printf '%s' "$str"
}

# Get indentation level (number of leading spaces)
_yaml_indent_level() {
    local line="$1"
    local stripped="${line#"${line%%[![:space:]]*}"}"
    printf '%d' $(( ${#line} - ${#stripped} ))
}

# Unquote a YAML string value
_yaml_unquote() {
    local val="$1"
    if [[ "$val" == '"'*'"' ]]; then
        val="${val#\"}"
        val="${val%\"}"
        # Process escape sequences
        val="${val//\\n/$'\n'}"
        val="${val//\\t/$'\t'}"
        val="${val//\\r/$'\r'}"
        val="${val//\\\\/\\}"
        val="${val//\\\"/\"}"
    elif [[ "$val" == "'"*"'" ]]; then
        val="${val#\'}"
        val="${val%\'}"
    fi
    printf '%s' "$val"
}

# Strip inline comment from a YAML value (respecting quotes)
_yaml_strip_comment() {
    local val="$1"
    local i=0 len=${#val}
    local in_quote="" quote_char=""
    local result=""

    while (( i < len )); do
        local ch="${val:$i:1}"

        if [[ -n "$in_quote" ]]; then
            if [[ "$ch" == "$quote_char" ]]; then
                in_quote=""
            fi
            result+="$ch"
        elif [[ "$ch" == '"' || "$ch" == "'" ]]; then
            in_quote=1
            quote_char="$ch"
            result+="$ch"
        elif [[ "$ch" == '#' ]]; then
            # Check if preceded by space (YAML comment requirement)
            if (( i > 0 )) && [[ "${val:$((i-1)):1}" == ' ' ]]; then
                # Remove trailing space before comment
                result="${result% }"
                break
            else
                result+="$ch"
            fi
        else
            result+="$ch"
        fi
        i=$((i + 1))
    done

    printf '%s' "$result"
}

# Parse a YAML flow sequence: [a, b, c]
_yaml_parse_flow_sequence() {
    local content="$1"
    local prefix="$2"

    # Strip outer brackets
    content="${content#\[}"
    content="${content%\]}"
    content=$(_yaml_trim "$content")

    [[ -z "$content" ]] && return 0

    local i=0 len=${#content}
    local elem="" in_quote="" quote_char="" depth=0
    local arr_idx=0

    while (( i < len )); do
        local ch="${content:$i:1}"

        if [[ -n "$in_quote" ]]; then
            if [[ "$ch" == "$quote_char" && "${content:$((i > 0 ? i-1 : 0)):1}" != "\\" ]]; then
                in_quote=""
            fi
            elem+="$ch"
        elif [[ "$ch" == '"' || "$ch" == "'" ]]; then
            in_quote=1
            quote_char="$ch"
            elem+="$ch"
        elif [[ "$ch" == '[' || "$ch" == '{' ]]; then
            depth=$((depth + 1))
            elem+="$ch"
        elif [[ "$ch" == ']' || "$ch" == '}' ]]; then
            depth=$((depth - 1))
            elem+="$ch"
        elif [[ "$ch" == ',' && $depth -eq 0 ]]; then
            elem=$(_yaml_trim "$elem")
            if [[ -n "$elem" ]]; then
                elem=$(_yaml_unquote "$elem")
                printf '%s[%d]=%s\n' "$prefix" "$arr_idx" "$elem"
                arr_idx=$((arr_idx + 1))
            fi
            elem=""
        else
            elem+="$ch"
        fi
        i=$((i + 1))
    done

    elem=$(_yaml_trim "$elem")
    if [[ -n "$elem" ]]; then
        elem=$(_yaml_unquote "$elem")
        printf '%s[%d]=%s\n' "$prefix" "$arr_idx" "$elem"
    fi
}

# Parse a YAML flow mapping: {a: 1, b: 2}
_yaml_parse_flow_mapping() {
    local content="$1"
    local prefix="$2"

    # Strip outer braces
    content="${content#\{}"
    content="${content%\}}"
    content=$(_yaml_trim "$content")

    [[ -z "$content" ]] && return 0

    local i=0 len=${#content}
    local field="" in_quote="" quote_char="" depth=0

    while (( i < len )); do
        local ch="${content:$i:1}"

        if [[ -n "$in_quote" ]]; then
            if [[ "$ch" == "$quote_char" && "${content:$((i > 0 ? i-1 : 0)):1}" != "\\" ]]; then
                in_quote=""
            fi
            field+="$ch"
        elif [[ "$ch" == '"' || "$ch" == "'" ]]; then
            in_quote=1
            quote_char="$ch"
            field+="$ch"
        elif [[ "$ch" == '{' || "$ch" == '[' ]]; then
            depth=$((depth + 1))
            field+="$ch"
        elif [[ "$ch" == '}' || "$ch" == ']' ]]; then
            depth=$((depth - 1))
            field+="$ch"
        elif [[ "$ch" == ',' && $depth -eq 0 ]]; then
            _yaml_parse_flow_field "$prefix" "$field"
            field=""
        else
            field+="$ch"
        fi
        i=$((i + 1))
    done

    [[ -n "$field" ]] && _yaml_parse_flow_field "$prefix" "$field"
}

# Parse a single flow mapping field: key: value
_yaml_parse_flow_field() {
    local prefix="$1"
    local field="$2"

    field=$(_yaml_trim "$field")
    [[ -z "$field" ]] && return 0

    local key value
    # Find first colon followed by space (or end)
    if [[ "$field" == *": "* ]]; then
        key="${field%%: *}"
        value="${field#*: }"
    elif [[ "$field" == *":"* ]]; then
        key="${field%%:*}"
        value="${field#*:}"
    else
        return 0
    fi

    key=$(_yaml_trim "$key")
    value=$(_yaml_trim "$value")
    key=$(_yaml_unquote "$key")
    value=$(_yaml_unquote "$value")

    local full_key
    if [[ -n "$prefix" ]]; then
        full_key="${prefix}.${key}"
    else
        full_key="$key"
    fi

    printf '%s=%s\n' "$full_key" "$value"
}

# Build a dot-notation path from path_keys array
# Handles [N] entries correctly (no dot before brackets)
_yaml_build_path() {
    local result=""
    local k
    for k in "$@"; do
        if [[ -z "$result" ]]; then
            result="$k"
        elif [[ "$k" == "["* ]]; then
            result+="$k"
        else
            result+=".${k}"
        fi
    done
    printf '%s' "$result"
}

# Resolve YAML value (handle null, booleans, etc.)
_yaml_resolve_value() {
    local val="$1"
    case "$val" in
        "~"|null|Null|NULL|"") printf ''; return ;;
        true|True|TRUE|yes|Yes|YES|on|On|ON) printf '%s' "$val"; return ;;
        false|False|FALSE|no|No|NO|off|Off|OFF) printf '%s' "$val"; return ;;
    esac
    printf '%s' "$val"
}

# =============================================================================
# PUBLIC API
# =============================================================================

# @pre: file_path points to a YAML file
# @post: prints flat key=value pairs with dot-notation and [N] for arrays
# @idempotent: yes
# @returns: 0 on success, 1 on file error
#
# Parse a YAML file into flat key-value representation.
# Nested keys use dot notation, array indices use [N].
#
# Usage: yaml_parse "docker-compose.yml"
# Example: yaml_parse ".github/workflows/ci.yml" | grep "^jobs\."
yaml_parse() {
    local file="$1"

    if [[ -z "$file" ]]; then
        printf 'error: no file specified\n' >&2
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        printf 'error: file not found: %s\n' "$file" >&2
        return 1
    fi

    # Read all lines
    local -a lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done < "$file"

    # Path stack: (indent_level, key_segment) pairs
    local -a path_keys=()
    local -a path_indents=()

    # Track array indices by parent_path@indent
    local -A seq_counters=()

    # Anchor storage
    local -A anchors=()

    local idx=0
    local in_multiline=0
    local multiline_key=""
    local multiline_style=""  # "|" or ">"
    local multiline_indent=-1
    local multiline_content=""
    local past_first_doc=0

    while (( idx < ${#lines[@]} )); do
        local line="${lines[$idx]}"
        idx=$((idx + 1))

        # Handle document separators
        if [[ "$line" == "---" ]]; then
            if [[ $past_first_doc -eq 1 ]]; then
                # Second document, stop parsing
                break
            fi
            past_first_doc=1
            continue
        fi
        [[ "$line" == "..." ]] && break

        # Handle multiline string collection
        if [[ $in_multiline -eq 1 ]]; then
            local ml_indent
            ml_indent=$(_yaml_indent_level "$line")

            # Empty line in multiline
            if [[ -z "$(_yaml_trim "$line")" ]]; then
                multiline_content+=$'\n'
                continue
            fi

            # Set reference indent from first content line
            if [[ $multiline_indent -lt 0 ]]; then
                multiline_indent=$ml_indent
            fi

            if (( ml_indent >= multiline_indent )); then
                local ml_text="${line:$multiline_indent}"
                if [[ -n "$multiline_content" ]]; then
                    if [[ "$multiline_style" == "|" ]]; then
                        multiline_content+=$'\n'"$ml_text"
                    else
                        # Folded: newlines become spaces
                        multiline_content+=" $ml_text"
                    fi
                else
                    multiline_content="$ml_text"
                fi
                continue
            fi

            # Multiline block ended (current line has less indent)
            in_multiline=0
            # Trim trailing newline for literal blocks
            multiline_content="${multiline_content%$'\n'}"
            printf '%s=%s\n' "$multiline_key" "$multiline_content"
            multiline_content=""
            multiline_indent=-1
            # Fall through to process current line
        fi

        # Skip empty lines
        local trimmed
        trimmed=$(_yaml_trim "$line")
        [[ -z "$trimmed" ]] && continue

        # Skip pure comment lines
        [[ "$trimmed" == "#"* ]] && continue

        # Get indentation
        local indent
        indent=$(_yaml_indent_level "$line")

        # Pop stack entries that are at same or deeper indent
        while (( ${#path_indents[@]} > 0 )); do
            local top_indent=${path_indents[${#path_indents[@]}-1]}
            if (( indent <= top_indent )); then
                unset 'path_keys[${#path_keys[@]}-1]'
                unset 'path_indents[${#path_indents[@]}-1]'
            else
                break
            fi
        done

        # Check if this is a sequence item (- prefix)
        local content="$trimmed"

        if [[ "$trimmed" == "- "* || "$trimmed" == "-" ]]; then
            content="${trimmed#- }"
            [[ "$trimmed" == "-" ]] && content=""

            # Track sequence index by parent path + indent
            local seq_parent
            seq_parent=$(_yaml_build_path "${path_keys[@]}")
            local seq_key_id="${seq_parent}@${indent}"

            local arr_idx
            if [[ -n "${seq_counters[$seq_key_id]+x}" ]]; then
                seq_counters[$seq_key_id]=$(( ${seq_counters[$seq_key_id]} + 1 ))
            else
                seq_counters[$seq_key_id]=0
            fi
            arr_idx=${seq_counters[$seq_key_id]}

            # Check if content is a mapping (key: value)
            # A mapping requires "key: value" (colon followed by space) or "key:" at end
            # Skip if content starts with a quote (it's a scalar string)
            # Skip if content looks like a path/URL with colon (no space after colon)
            local _is_mapping=0
            if [[ "$content" != '"'* && "$content" != "'"* ]]; then
                if [[ "$content" == *": "* ]]; then
                    _is_mapping=1
                elif [[ "$content" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*:$ ]]; then
                    # Only treat bare "key:" (identifier followed by colon at end) as mapping
                    _is_mapping=1
                fi
            fi
            if [[ $_is_mapping -eq 1 ]]; then
                # Sequence of mappings
                local seq_key seq_val
                seq_key="${content%%:*}"
                seq_val="${content#*:}"
                seq_val=$(_yaml_trim "$seq_val")
                seq_key=$(_yaml_trim "$seq_key")
                seq_key=$(_yaml_unquote "$seq_key")

                # Strip anchor from key
                if [[ "$seq_key" == *" &"* ]]; then
                    local anchor="${seq_key##* &}"
                    seq_key="${seq_key%% &*}"
                fi

                local full_path
                full_path=$(_yaml_build_path "${path_keys[@]}")

                if [[ -n "$full_path" ]]; then
                    full_path="${full_path}[${arr_idx}]"
                else
                    full_path="[${arr_idx}]"
                fi

                if [[ -n "$seq_val" ]]; then
                    # Handle flow collections in sequence items
                    if [[ "$seq_val" == "["*"]" ]]; then
                        _yaml_parse_flow_sequence "$seq_val" "${full_path}.${seq_key}"
                    elif [[ "$seq_val" == "{"*"}" ]]; then
                        _yaml_parse_flow_mapping "$seq_val" "${full_path}.${seq_key}"
                    else
                        seq_val=$(_yaml_strip_comment "$seq_val")
                        seq_val=$(_yaml_unquote "$seq_val")
                        printf '%s.%s=%s\n' "$full_path" "$seq_key" "$seq_val"
                    fi
                else
                    # Key with no value - nested content follows
                    :
                fi

                # Push the array index as path element so sibling keys
                # under the same dash are captured correctly.
                # Use indent+2 as the reference (content indent under dash).
                local seq_content_indent=$((indent + 2))
                path_keys+=("[${arr_idx}]")
                path_indents+=("$indent")

                # Push the first key for nested content resolution
                path_keys+=("$seq_key")
                path_indents+=("$seq_content_indent")

                continue
            fi

            # Simple sequence item (scalar value)
            local full_path
            full_path=$(_yaml_build_path "${path_keys[@]}")

            if [[ "$content" == "["*"]" ]]; then
                # Flow sequence as array element
                _yaml_parse_flow_sequence "$content" "${full_path}[${arr_idx}]"
            elif [[ "$content" == "{"*"}" ]]; then
                _yaml_parse_flow_mapping "$content" "${full_path}[${arr_idx}]"
            else
                content=$(_yaml_strip_comment "$content")
                content=$(_yaml_unquote "$content")
                if [[ -n "$full_path" ]]; then
                    printf '%s[%d]=%s\n' "$full_path" "$arr_idx" "$content"
                else
                    printf '[%d]=%s\n' "$arr_idx" "$content"
                fi
            fi
            continue
        fi

        # Reset array counter when we're not in a sequence
        # (array counters are managed per-level in the stack)

        # Parse key: value
        local key="" value="" found_colon=0

        # Handle quoted keys
        if [[ "$content" == '"'* ]]; then
            # Find closing quote
            local rest="${content#\"}"
            key="${rest%%\"*}"
            local after="${rest#*\"}"
            if [[ "$after" == ":"* ]]; then
                value="${after#:}"
                value=$(_yaml_trim "$value")
                found_colon=1
            fi
        elif [[ "$content" == "'"* ]]; then
            local rest="${content#\'}"
            key="${rest%%\'*}"
            local after="${rest#*\'}"
            if [[ "$after" == ":"* ]]; then
                value="${after#:}"
                value=$(_yaml_trim "$value")
                found_colon=1
            fi
        elif [[ "$content" == *": "* || "$content" == *":" ]]; then
            key="${content%%:*}"
            value="${content#*:}"
            value=$(_yaml_trim "$value")
            found_colon=1
        fi

        [[ $found_colon -eq 0 ]] && continue

        key=$(_yaml_trim "$key")

        # Handle anchors on values
        local anchor=""
        if [[ "$value" == "&"* ]]; then
            # Anchor definition: &name value
            local anchor_rest="${value#&}"
            anchor="${anchor_rest%% *}"
            if [[ "$anchor_rest" == *" "* ]]; then
                value="${anchor_rest#* }"
            else
                value=""
            fi
        elif [[ "$value" == "*"* ]]; then
            # Alias reference
            local alias_name="${value#\*}"
            alias_name=$(_yaml_trim "$alias_name")
            alias_name=$(_yaml_strip_comment "$alias_name")
            if [[ -n "${anchors[$alias_name]:-}" ]]; then
                value="${anchors[$alias_name]}"
            fi
        fi

        # Strip tags
        if [[ "$value" == "!"*" "* ]]; then
            value="${value#* }"
        fi

        # Build full key path
        local full_path
        full_path=$(_yaml_build_path "${path_keys[@]}")

        local full_key
        full_key=$(_yaml_build_path "${path_keys[@]}" "$key")

        # Handle multiline strings (| and >)
        if [[ "$value" == "|" || "$value" == "|"[-+]* || "$value" == ">" || "$value" == ">"[-+]* ]]; then
            in_multiline=1
            multiline_key="$full_key"
            multiline_style="${value:0:1}"
            multiline_indent=-1
            multiline_content=""

            # Push key for context
            path_keys+=("$key")
            path_indents+=("$indent")

            continue
        fi

        # Handle flow sequences
        if [[ "$value" == "["*"]" ]]; then
            _yaml_parse_flow_sequence "$value" "$full_key"
            path_keys+=("$key")
            path_indents+=("$indent")
            continue
        fi

        # Handle flow mappings
        if [[ "$value" == "{"*"}" ]]; then
            _yaml_parse_flow_mapping "$value" "$full_key"
            path_keys+=("$key")
            path_indents+=("$indent")
            continue
        fi

        if [[ -z "$value" ]]; then
            # No value - this is a parent key for nested content
            path_keys+=("$key")
            path_indents+=("$indent")
            continue
        fi

        # Regular scalar value
        value=$(_yaml_strip_comment "$value")
        value=$(_yaml_unquote "$value")

        # Store anchor value
        if [[ -n "$anchor" ]]; then
            anchors["$anchor"]="$value"
        fi

        # Resolve null
        local resolved
        resolved=$(_yaml_resolve_value "$value")

        if [[ -n "$resolved" ]]; then
            printf '%s=%s\n' "$full_key" "$resolved"
        else
            printf '%s=\n' "$full_key"
        fi

        # Push key onto stack (for potential nested content)
        path_keys+=("$key")
        path_indents+=("$indent")
    done

    # Flush any remaining multiline content
    if [[ $in_multiline -eq 1 && -n "$multiline_content" ]]; then
        multiline_content="${multiline_content%$'\n'}"
        printf '%s=%s\n' "$multiline_key" "$multiline_content"
    fi
}

# @pre: file_path is a valid YAML file, key_path is dot-notation key
# @post: prints the value for the given key
# @idempotent: yes
# @returns: 0 if found, 1 if not found
#
# Get a specific value from a YAML file.
#
# Usage: yaml_get "docker-compose.yml" "services.web.image"
# Example: name=$(yaml_get "chart.yaml" "name")
yaml_get() {
    local file="$1"
    local key="$2"

    if [[ -z "$file" || -z "$key" ]]; then
        return 1
    fi

    local result found=0
    while IFS='=' read -r k v; do
        if [[ "$k" == "$key" ]]; then
            result="$v"
            found=1
            break
        fi
    done < <(yaml_parse "$file")

    if [[ $found -eq 1 ]]; then
        printf '%s\n' "$result"
        return 0
    fi
    return 1
}

# @pre: file_path is a valid YAML file, section is a key path
# @post: prints key=value pairs within that section
# @idempotent: yes
# @returns: 0 on success
#
# Get a section/subtree as key=value pairs.
#
# Usage: yaml_get_section "docker-compose.yml" "services.web"
# Example: yaml_get_section "ci.yml" "jobs.build"
yaml_get_section() {
    local file="$1"
    local section="$2"

    if [[ -z "$file" || -z "$section" ]]; then
        return 1
    fi

    yaml_parse "$file" | while IFS='=' read -r k v; do
        if [[ "$k" == "${section}."* ]]; then
            local sub_key="${k#"${section}".}"
            printf '%s=%s\n' "$sub_key" "$v"
        elif [[ "$k" == "${section}["* ]]; then
            local sub_key="${k#"${section}"}"
            printf '%s=%s\n' "$sub_key" "$v"
        fi
    done
}

# @pre: file_path is a valid YAML file
# @post: prints JSON object
# @idempotent: yes
# @returns: 0 on success
#
# Convert a YAML file to JSON format.
# Uses flat key=value representation as intermediate.
#
# Usage: yaml_to_json "docker-compose.yml"
# Example: yaml_to_json "values.yaml" | jq '.image.tag'
yaml_to_json() {
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
    done < <(yaml_parse "$file")

    if [[ ${#keys[@]} -eq 0 ]]; then
        printf '{}'
        return 0
    fi

    local json="{"
    local first=true

    local idx
    for ((idx=0; idx<${#keys[@]}; idx++)); do
        local key="${keys[$idx]}"
        local val="${values[$idx]}"

        [[ "$first" == "true" ]] && first=false || json+=","

        local escaped_key escaped_val
        escaped_key=$(_yaml_json_escape "$key")

        # Determine value type
        case "$val" in
            true|True|TRUE|yes|Yes|YES|on|On|ON)
                json+="\"$escaped_key\":true"
                ;;
            false|False|FALSE|no|No|NO|off|Off|OFF)
                json+="\"$escaped_key\":false"
                ;;
            "~"|null|Null|NULL|"")
                json+="\"$escaped_key\":null"
                ;;
            *)
                if [[ "$val" =~ ^-?[0-9]+$ ]]; then
                    json+="\"$escaped_key\":$val"
                elif [[ "$val" =~ ^-?[0-9]+\.[0-9]+$ ]]; then
                    json+="\"$escaped_key\":$val"
                else
                    escaped_val=$(_yaml_json_escape "$val")
                    json+="\"$escaped_key\":\"$escaped_val\""
                fi
                ;;
        esac
    done

    json+="}"
    printf '%s' "$json"
}

# @pre: file_path is a valid YAML file
# @post: prints top-level keys, one per line
# @idempotent: yes
# @returns: 0 on success
#
# List top-level keys in a YAML file.
#
# Usage: yaml_keys "docker-compose.yml"
# Example: yaml_keys "chart.yaml"
yaml_keys() {
    local file="$1"

    if [[ -z "$file" || ! -f "$file" ]]; then
        return 1
    fi

    local -a seen=()

    yaml_parse "$file" | while IFS='=' read -r k _; do
        # Extract top-level key
        local top_key
        if [[ "$k" == *"."* ]]; then
            top_key="${k%%.*}"
        elif [[ "$k" == *"["* ]]; then
            top_key="${k%%\[*}"
        else
            top_key="$k"
        fi

        # Deduplicate
        local found=0
        for s in "${seen[@]}"; do
            [[ "$s" == "$top_key" ]] && { found=1; break; }
        done
        if [[ $found -eq 0 ]]; then
            seen+=("$top_key")
            printf '%s\n' "$top_key"
        fi
    done
}

# @pre: file_path is a valid YAML file, key_path is dot-notation key
# @post: returns 0 if key exists, 1 if not
# @idempotent: yes
# @returns: 0=exists, 1=not found
#
# Check if a key exists in a YAML file.
#
# Usage: yaml_has "compose.yml" "services.web" && echo "has web service"
# Example: if yaml_has "values.yaml" "image.tag"; then ...
yaml_has() {
    local file="$1"
    local key="$2"

    if [[ -z "$file" || -z "$key" ]]; then
        return 1
    fi

    local _found=0
    while IFS='=' read -r k _; do
        if [[ "$k" == "$key" || "$k" == "${key}."* || "$k" == "${key}["* ]]; then
            _found=1
            break
        fi
    done < <(yaml_parse "$file")
    [[ $_found -eq 1 ]]
}

# @pre: file_path is a valid YAML file, key_path points to an array
# @post: prints array elements, one per line
# @idempotent: yes
# @returns: 0 on success, 1 if not found
#
# Get array elements from a YAML file.
#
# Usage: yaml_get_array "compose.yml" "services.web.ports"
# Example: yaml_get_array "ci.yml" "jobs.build.steps"
yaml_get_array() {
    local file="$1"
    local key="$2"

    if [[ -z "$file" || -z "$key" ]]; then
        return 1
    fi

    local _found=0
    local -a _results=()

    while IFS='=' read -r k v; do
        if [[ "$k" == "${key}["*"]" && "$k" != "${key}["*"]."* ]]; then
            # Direct array element: key[N]=value (not key[N].subkey)
            _results+=("$v")
            _found=1
        fi
    done < <(yaml_parse "$file")

    if [[ $_found -eq 1 ]]; then
        for v in "${_results[@]}"; do
            printf '%s\n' "$v"
        done
        return 0
    fi
    return 1
}

# @pre: file_path is a valid YAML file, key_path points to an array
# @post: prints array length as integer
# @idempotent: yes
# @returns: 0 on success
#
# Get the length of an array in a YAML file.
#
# Usage: yaml_array_length "compose.yml" "services.web.ports"
# Example: count=$(yaml_array_length "ci.yml" "jobs.build.steps")
yaml_array_length() {
    local file="$1"
    local key="$2"

    if [[ -z "$file" || -z "$key" ]]; then
        printf '0'
        return 1
    fi

    local max_idx=-1

    while IFS='=' read -r k _; do
        if [[ "$k" == "${key}["*"]"* ]]; then
            # Extract index
            local idx_part="${k#"${key}"[}"
            idx_part="${idx_part%%\]*}"
            if [[ "$idx_part" =~ ^[0-9]+$ ]] && (( idx_part > max_idx )); then
                max_idx=$idx_part
            fi
        fi
    done < <(yaml_parse "$file")

    printf '%d' $((max_idx + 1))
}

# @pre: file_path is a valid YAML file, parent_path is a key prefix
# @post: prints child keys at the given depth
# @idempotent: yes
# @returns: 0 on success
#
# Get all keys at a given depth/parent path.
#
# Usage: yaml_keys_at "compose.yml" "services"
# Example: yaml_keys_at "ci.yml" "jobs"
yaml_keys_at() {
    local file="$1"
    local parent="$2"

    if [[ -z "$file" ]]; then
        return 1
    fi

    local -a seen=()

    yaml_parse "$file" | while IFS='=' read -r k _; do
        if [[ -z "$parent" ]]; then
            # Top-level keys
            local top_key
            if [[ "$k" == *"."* ]]; then
                top_key="${k%%.*}"
            elif [[ "$k" == *"["* ]]; then
                top_key="${k%%\[*}"
            else
                top_key="$k"
            fi

            local found=0
            for s in "${seen[@]}"; do
                [[ "$s" == "$top_key" ]] && { found=1; break; }
            done
            if [[ $found -eq 0 ]]; then
                seen+=("$top_key")
                printf '%s\n' "$top_key"
            fi
        elif [[ "$k" == "${parent}."* ]]; then
            local sub="${k#"${parent}".}"
            local child_key
            if [[ "$sub" == *"."* ]]; then
                child_key="${sub%%.*}"
            elif [[ "$sub" == *"["* ]]; then
                child_key="${sub%%\[*}"
            else
                child_key="$sub"
            fi

            local found=0
            for s in "${seen[@]}"; do
                [[ "$s" == "$child_key" ]] && { found=1; break; }
            done
            if [[ $found -eq 0 ]]; then
                seen+=("$child_key")
                printf '%s\n' "$child_key"
            fi
        fi
    done
}

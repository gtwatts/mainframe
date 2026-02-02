#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/registry_schema.sh - JSON Schema Generator for LLM Function Calling
# =============================================================================
# Description: Generate OpenAI and Anthropic function calling schemas from
#              MAINFRAME's FUNCTIONS.json registry. Enables AI agents to use
#              MAINFRAME functions via structured tool interfaces.
#
# Supported Formats:
#   - OpenAI Function Calling (GPT-4, GPT-3.5-turbo)
#   - Anthropic Tool Use (Claude)
#   - OpenAPI 3.0 (generic REST API documentation)
#
# Dependencies: json.sh, jq (for complex JSON operations)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_REGISTRY_SCHEMA_LOADED:-}" ]] && return 0
readonly _MAINFRAME_REGISTRY_SCHEMA_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Path to FUNCTIONS.json registry
MAINFRAME_FUNCTIONS_JSON="${MAINFRAME_FUNCTIONS_JSON:-${MAINFRAME_ROOT:-${BASH_SOURCE[0]%/lib/*}}/FUNCTIONS.json}"

# Cache for loaded registry
declare -g _REGISTRY_SCHEMA_CACHE=""
declare -g _REGISTRY_SCHEMA_CACHE_TIME=0

# Type mapping from docstring types to JSON Schema types
# Format: docstring_type -> json_schema_type
declare -gA _TYPE_MAP=(
    ["string"]="string"
    ["str"]="string"
    ["number"]="number"
    ["num"]="number"
    ["integer"]="integer"
    ["int"]="integer"
    ["boolean"]="boolean"
    ["bool"]="boolean"
    ["object"]="object"
    ["obj"]="object"
    ["array"]="array"
    ["any"]="any"
    ["null"]="null"
    ["void"]="null"
    # Array types
    ["string[]"]="array:string"
    ["number[]"]="array:number"
    ["integer[]"]="array:integer"
    ["boolean[]"]="array:boolean"
    ["object[]"]="array:object"
)

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Load the FUNCTIONS.json registry (with simple caching)
# Usage: _registry_load
# Returns: 0 on success, 1 if file not found or invalid
_registry_load() {
    local registry_file="$MAINFRAME_FUNCTIONS_JSON"

    # Check if file exists
    if [[ ! -f "$registry_file" ]]; then
        printf 'Error: FUNCTIONS.json not found at %s\n' "$registry_file" >&2
        return 1
    fi

    # Check cache validity (reload if file changed)
    local file_mtime
    file_mtime=$(stat -c %Y "$registry_file" 2>/dev/null || stat -f %m "$registry_file" 2>/dev/null)

    if [[ -n "$_REGISTRY_SCHEMA_CACHE" && "$file_mtime" -le "$_REGISTRY_SCHEMA_CACHE_TIME" ]]; then
        return 0
    fi

    # Load and cache
    _REGISTRY_SCHEMA_CACHE=$(<"$registry_file")
    _REGISTRY_SCHEMA_CACHE_TIME="$file_mtime"

    return 0
}

# Get function metadata from registry
# Usage: _registry_get_function "json_object"
# Output: Function metadata as JSON
# Returns: 0 if found, 1 if not found
_registry_get_function() {
    local func_name="$1"

    _registry_load || return 1

    # Use jq to extract function data
    local result
    result=$(jq -r --arg fn "$func_name" '
        .libraries | to_entries[] |
        select(.value.functions[$fn] != null) |
        .value.functions[$fn] + {library: .key, library_file: .value.file}
    ' <<< "$_REGISTRY_SCHEMA_CACHE" 2>/dev/null)

    if [[ -z "$result" || "$result" == "null" ]]; then
        return 1
    fi

    printf '%s' "$result"
    return 0
}

# Map a type string to JSON Schema type object
# Usage: _type_to_schema "string"
# Output: JSON Schema type fragment (e.g., {"type": "string"})
_type_to_schema() {
    local type_str="$1"
    local mapped

    # Normalize type string
    type_str="${type_str,,}"  # lowercase
    type_str="${type_str// /}"  # remove spaces

    # Check direct mapping
    mapped="${_TYPE_MAP[$type_str]:-}"

    if [[ -z "$mapped" ]]; then
        # Default to string for unknown types
        mapped="string"
    fi

    # Handle array types
    if [[ "$mapped" == array:* ]]; then
        local item_type="${mapped#array:}"
        printf '{"type":"array","items":{"type":"%s"}}' "$item_type"
    elif [[ "$mapped" == "any" ]]; then
        # No type constraint for 'any'
        printf '{}'
    else
        printf '{"type":"%s"}' "$mapped"
    fi
}

# Detect if a parameter is optional from its description
# Usage: _is_optional "Optional timeout in seconds"
# Returns: 0 if optional, 1 if required
_is_optional() {
    local desc="$1"
    local default="$2"

    # Check for explicit optional indicators
    [[ "$desc" =~ [Oo]ptional ]] && return 0
    [[ "$desc" =~ \[optional\] ]] && return 0
    [[ "$desc" =~ \(optional\) ]] && return 0

    # Check if default value is provided (non-null)
    [[ -n "$default" && "$default" != "null" ]] && return 0

    return 1
}

# Infer type from parameter name patterns
# Usage: _infer_type "timeout_secs"
# Output: Inferred type string
_infer_type() {
    local param_name="$1"

    case "$param_name" in
        *_count|*_num|*_size|*_len|*_length|*_index|*_id)
            printf 'integer' ;;
        *_secs|*_seconds|*_ms|*_milliseconds|*_timeout|*_delay|*_port)
            printf 'integer' ;;
        *_enabled|*_active|*_flag|is_*|has_*|*_bool)
            printf 'boolean' ;;
        *_list|*_array|*_items|*s)
            # Trailing 's' might be plural array, but too risky
            printf 'string' ;;
        *)
            printf 'string' ;;
    esac
}

# Escape string for JSON
# Usage: _json_escape "hello \"world\""
_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"   # backslash
    str="${str//\"/\\\"}"   # double quote
    str="${str//$'\n'/\\n}" # newline
    str="${str//$'\r'/\\r}" # carriage return
    str="${str//$'\t'/\\t}" # tab
    printf '%s' "$str"
}

# =============================================================================
# OPENAI SCHEMA GENERATION
# =============================================================================

# Generate OpenAI function calling schema for a single function
# Usage: registry_to_openai_schema "json_object"
# Output: OpenAI function schema JSON
# Returns: 0 on success, 1 if function not found
registry_to_openai_schema() {
    local func_name="$1"

    if [[ -z "$func_name" ]]; then
        printf '{"error":"Function name required"}\n' >&2
        return 1
    fi

    local func_meta
    func_meta=$(_registry_get_function "$func_name")
    if [[ $? -ne 0 ]]; then
        printf '{"error":"Function not found: %s"}\n' "$func_name" >&2
        return 1
    fi

    # Extract metadata using jq
    local description signature params_json
    description=$(jq -r '.description // "No description available"' <<< "$func_meta")
    signature=$(jq -r '.signature // ""' <<< "$func_meta")
    params_json=$(jq -c '.params // []' <<< "$func_meta")

    # Build properties and required arrays
    local properties="{}"
    local required="[]"

    if [[ "$params_json" != "[]" ]]; then
        # Process each parameter
        properties=$(jq -c '
            reduce .[] as $p (
                {};
                . + {
                    ($p.name): {
                        type: (if $p.type then $p.type else "string" end),
                        description: (if $p.description then $p.description
                                     else "Parameter: " + $p.name end)
                    }
                }
            )
        ' <<< "$params_json" 2>/dev/null || echo "{}")

        # Get required parameters (where required=true and no default)
        required=$(jq -c '
            [.[] | select(.required == true and (.default == null or .default == "")) | .name]
        ' <<< "$params_json" 2>/dev/null || echo "[]")
    fi

    # Build the final OpenAI schema
    local escaped_desc
    escaped_desc=$(_json_escape "$description")

    cat <<EOF
{
  "type": "function",
  "function": {
    "name": "$func_name",
    "description": "$escaped_desc",
    "parameters": {
      "type": "object",
      "properties": $properties,
      "required": $required
    }
  }
}
EOF
    return 0
}

# =============================================================================
# ANTHROPIC SCHEMA GENERATION
# =============================================================================

# Generate Anthropic tool schema for a single function
# Usage: registry_to_anthropic_schema "json_object"
# Output: Anthropic tool schema JSON
# Returns: 0 on success, 1 if function not found
registry_to_anthropic_schema() {
    local func_name="$1"

    if [[ -z "$func_name" ]]; then
        printf '{"error":"Function name required"}\n' >&2
        return 1
    fi

    local func_meta
    func_meta=$(_registry_get_function "$func_name")
    if [[ $? -ne 0 ]]; then
        printf '{"error":"Function not found: %s"}\n' "$func_name" >&2
        return 1
    fi

    # Extract metadata using jq
    local description params_json
    description=$(jq -r '.description // "No description available"' <<< "$func_meta")
    params_json=$(jq -c '.params // []' <<< "$func_meta")

    # Build properties and required arrays
    local properties="{}"
    local required="[]"

    if [[ "$params_json" != "[]" ]]; then
        properties=$(jq -c '
            reduce .[] as $p (
                {};
                . + {
                    ($p.name): {
                        type: (if $p.type then $p.type else "string" end),
                        description: (if $p.description then $p.description
                                     else "Parameter: " + $p.name end)
                    }
                }
            )
        ' <<< "$params_json" 2>/dev/null || echo "{}")

        required=$(jq -c '
            [.[] | select(.required == true and (.default == null or .default == "")) | .name]
        ' <<< "$params_json" 2>/dev/null || echo "[]")
    fi

    local escaped_desc
    escaped_desc=$(_json_escape "$description")

    # Anthropic uses input_schema instead of parameters
    cat <<EOF
{
  "name": "$func_name",
  "description": "$escaped_desc",
  "input_schema": {
    "type": "object",
    "properties": $properties,
    "required": $required
  }
}
EOF
    return 0
}

# =============================================================================
# OPENAPI SPECIFICATION GENERATION
# =============================================================================

# Generate OpenAPI 3.0 spec for a library file
# Usage: registry_to_openapi "lib/json.sh"
# Output: OpenAPI 3.0 specification JSON
# Returns: 0 on success, 1 on error
registry_to_openapi() {
    local lib_file="$1"

    if [[ -z "$lib_file" ]]; then
        printf '{"error":"Library file path required"}\n' >&2
        return 1
    fi

    _registry_load || return 1

    # Find library by file path
    local lib_name lib_data
    lib_data=$(jq -r --arg file "$lib_file" '
        .libraries | to_entries[] | select(.value.file == $file) |
        {name: .key, description: .value.description, functions: .value.functions}
    ' <<< "$_REGISTRY_SCHEMA_CACHE" 2>/dev/null)

    if [[ -z "$lib_data" || "$lib_data" == "null" ]]; then
        printf '{"error":"Library not found: %s"}\n' "$lib_file" >&2
        return 1
    fi

    lib_name=$(jq -r '.name' <<< "$lib_data")
    local lib_desc
    lib_desc=$(jq -r '.description // "MAINFRAME library"' <<< "$lib_data")

    # Generate paths for each function
    local paths
    paths=$(jq -r '
        .functions | to_entries |
        reduce .[] as $f (
            {};
            . + {
                ("/\($f.key)"): {
                    "post": {
                        "operationId": $f.key,
                        "summary": ($f.value.description // "No description"),
                        "requestBody": {
                            "content": {
                                "application/json": {
                                    "schema": {
                                        "type": "object",
                                        "properties": (
                                            if $f.value.params then
                                                ($f.value.params | reduce .[] as $p (
                                                    {};
                                                    . + {($p.name): {type: "string"}}
                                                ))
                                            else {}
                                            end
                                        )
                                    }
                                }
                            }
                        },
                        "responses": {
                            "200": {
                                "description": "Success"
                            }
                        }
                    }
                }
            }
        )
    ' <<< "$lib_data" 2>/dev/null || echo "{}")

    local escaped_desc
    escaped_desc=$(_json_escape "$lib_desc")

    cat <<EOF
{
  "openapi": "3.0.0",
  "info": {
    "title": "MAINFRAME $lib_name",
    "description": "$escaped_desc",
    "version": "1.0.0"
  },
  "paths": $paths
}
EOF
    return 0
}

# =============================================================================
# BATCH OPERATIONS
# =============================================================================

# Export all function schemas to a file
# Usage: registry_export_schemas "tools.json" [format]
# format: openai (default), anthropic, all
# Returns: 0 on success, 1 on error
registry_export_schemas() {
    local output_file="$1"
    local format="${2:-openai}"

    if [[ -z "$output_file" ]]; then
        printf 'Error: Output file path required\n' >&2
        return 1
    fi

    _registry_load || return 1

    # Get all function names
    local func_names
    func_names=$(jq -r '.libraries[].functions | keys[]' <<< "$_REGISTRY_SCHEMA_CACHE" 2>/dev/null)

    if [[ -z "$func_names" ]]; then
        printf 'Error: No functions found in registry\n' >&2
        return 1
    fi

    local schemas="[]"
    local func schema

    while IFS= read -r func; do
        [[ -z "$func" ]] && continue

        case "$format" in
            openai)
                schema=$(registry_to_openai_schema "$func" 2>/dev/null)
                ;;
            anthropic)
                schema=$(registry_to_anthropic_schema "$func" 2>/dev/null)
                ;;
            all)
                # Export both formats
                local openai_schema anthropic_schema
                openai_schema=$(registry_to_openai_schema "$func" 2>/dev/null)
                anthropic_schema=$(registry_to_anthropic_schema "$func" 2>/dev/null)
                schema=$(jq -n --argjson o "$openai_schema" --argjson a "$anthropic_schema" \
                    '{openai: $o, anthropic: $a}' 2>/dev/null)
                ;;
            *)
                printf 'Error: Unknown format: %s (use openai, anthropic, or all)\n' "$format" >&2
                return 1
                ;;
        esac

        if [[ -n "$schema" && "$schema" != "null" ]]; then
            schemas=$(jq --argjson s "$schema" '. + [$s]' <<< "$schemas" 2>/dev/null)
        fi
    done <<< "$func_names"

    # Write to file
    jq '.' <<< "$schemas" > "$output_file" 2>/dev/null

    local count
    count=$(jq 'length' <<< "$schemas" 2>/dev/null)
    printf 'Exported %s schemas to %s\n' "$count" "$output_file"

    return 0
}

# Generate schemas for functions matching a pattern
# Usage: registry_schema_batch "json_*"
# Output: JSON array of schemas
# Returns: 0 on success
registry_schema_batch() {
    local pattern="$1"
    local format="${2:-openai}"

    if [[ -z "$pattern" ]]; then
        printf '{"error":"Pattern required"}\n' >&2
        return 1
    fi

    _registry_load || return 1

    # Get all function names
    local func_names
    func_names=$(jq -r '.libraries[].functions | keys[]' <<< "$_REGISTRY_SCHEMA_CACHE" 2>/dev/null)

    local schemas="[]"
    local func schema

    # Convert glob pattern to regex for matching
    local regex_pattern
    regex_pattern="^${pattern//\*/.*}$"

    while IFS= read -r func; do
        [[ -z "$func" ]] && continue

        # Check if function name matches pattern
        if [[ "$func" =~ $regex_pattern ]]; then
            case "$format" in
                openai)
                    schema=$(registry_to_openai_schema "$func" 2>/dev/null)
                    ;;
                anthropic)
                    schema=$(registry_to_anthropic_schema "$func" 2>/dev/null)
                    ;;
                *)
                    schema=$(registry_to_openai_schema "$func" 2>/dev/null)
                    ;;
            esac

            if [[ -n "$schema" && "$schema" != "null" ]]; then
                schemas=$(jq --argjson s "$schema" '. + [$s]' <<< "$schemas" 2>/dev/null)
            fi
        fi
    done <<< "$func_names"

    printf '%s' "$schemas"
    return 0
}

# =============================================================================
# SCHEMA VALIDATION
# =============================================================================

# Validate a generated schema against JSON Schema draft
# Usage: registry_validate_schema "schema.json"
# Output: Validation result (JSON)
# Returns: 0 if valid, 1 if invalid
registry_validate_schema() {
    local schema_file="$1"

    if [[ -z "$schema_file" ]]; then
        printf '{"valid":false,"error":"Schema file path required"}\n'
        return 1
    fi

    if [[ ! -f "$schema_file" ]]; then
        printf '{"valid":false,"error":"Schema file not found: %s"}\n' "$schema_file"
        return 1
    fi

    local schema_content
    schema_content=$(<"$schema_file")

    # Check for valid JSON
    if ! jq empty <<< "$schema_content" 2>/dev/null; then
        printf '{"valid":false,"error":"Invalid JSON syntax"}\n'
        return 1
    fi

    # Validate schema structure
    local errors=""
    local is_valid=true

    # Check for OpenAI format
    local schema_type
    schema_type=$(jq -r 'type' <<< "$schema_content" 2>/dev/null)

    if [[ "$schema_type" == "object" ]]; then
        # Single schema - validate structure
        local has_name has_description has_parameters has_input_schema

        # Check OpenAI format
        has_name=$(jq -r '.function.name // .name // empty' <<< "$schema_content" 2>/dev/null)
        has_description=$(jq -r '.function.description // .description // empty' <<< "$schema_content" 2>/dev/null)
        has_parameters=$(jq -r '.function.parameters // empty' <<< "$schema_content" 2>/dev/null)
        has_input_schema=$(jq -r '.input_schema // empty' <<< "$schema_content" 2>/dev/null)

        if [[ -z "$has_name" ]]; then
            errors+="Missing required field: name; "
            is_valid=false
        fi

        if [[ -z "$has_parameters" && -z "$has_input_schema" ]]; then
            errors+="Missing parameters or input_schema; "
            is_valid=false
        fi

        # Validate parameters/input_schema structure
        local params_obj="${has_parameters:-$has_input_schema}"
        if [[ -n "$params_obj" ]]; then
            local params_type
            params_type=$(jq -r '.type // empty' <<< "$params_obj" 2>/dev/null)
            if [[ "$params_type" != "object" ]]; then
                errors+="Parameters type must be 'object'; "
                is_valid=false
            fi
        fi

    elif [[ "$schema_type" == "array" ]]; then
        # Array of schemas - validate each
        local count invalid_count=0
        count=$(jq 'length' <<< "$schema_content" 2>/dev/null)

        for ((i=0; i<count; i++)); do
            local item
            item=$(jq ".[$i]" <<< "$schema_content" 2>/dev/null)

            local item_name
            item_name=$(jq -r '.function.name // .name // empty' <<< "$item" 2>/dev/null)

            if [[ -z "$item_name" ]]; then
                ((invalid_count++))
            fi
        done

        if [[ $invalid_count -gt 0 ]]; then
            errors+="$invalid_count schemas missing name field; "
            is_valid=false
        fi
    else
        errors+="Schema must be an object or array; "
        is_valid=false
    fi

    if $is_valid; then
        printf '{"valid":true,"format":"%s"}\n' \
            "$(jq -r 'if .function then "openai" elif .input_schema then "anthropic" else "unknown" end' <<< "$schema_content" 2>/dev/null)"
        return 0
    else
        printf '{"valid":false,"errors":"%s"}\n' "${errors%%; }"
        return 1
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# List all available functions in the registry
# Usage: registry_list_functions [library]
# Output: One function name per line
registry_list_functions() {
    local lib_filter="$1"

    _registry_load || return 1

    if [[ -n "$lib_filter" ]]; then
        jq -r --arg lib "$lib_filter" '
            .libraries[$lib].functions // {} | keys[]
        ' <<< "$_REGISTRY_SCHEMA_CACHE" 2>/dev/null
    else
        jq -r '.libraries[].functions | keys[]' <<< "$_REGISTRY_SCHEMA_CACHE" 2>/dev/null | sort -u
    fi
}

# List all libraries in the registry
# Usage: registry_list_libraries
# Output: One library name per line
registry_list_libraries() {
    _registry_load || return 1

    jq -r '.libraries | keys[]' <<< "$_REGISTRY_SCHEMA_CACHE" 2>/dev/null | sort
}

# Get function count in registry
# Usage: registry_function_count [library]
registry_function_count() {
    local lib_filter="$1"

    _registry_load || return 1

    if [[ -n "$lib_filter" ]]; then
        jq -r --arg lib "$lib_filter" '
            .libraries[$lib].functions // {} | length
        ' <<< "$_REGISTRY_SCHEMA_CACHE" 2>/dev/null
    else
        jq -r '.libraries[].functions | length' <<< "$_REGISTRY_SCHEMA_CACHE" 2>/dev/null | \
            awk '{sum+=$1} END {print sum}'
    fi
}

# Search functions by description keyword
# Usage: registry_search "json"
# Output: Matching function names with descriptions
registry_search() {
    local keyword="$1"

    if [[ -z "$keyword" ]]; then
        printf 'Usage: registry_search KEYWORD\n' >&2
        return 1
    fi

    _registry_load || return 1

    jq -r --arg kw "$keyword" '
        .libraries | to_entries[] |
        .value.functions | to_entries[] |
        select(.value.description | test($kw; "i")) |
        "\(.key): \(.value.description | .[0:80])"
    ' <<< "$_REGISTRY_SCHEMA_CACHE" 2>/dev/null
}

# Get detailed function info
# Usage: registry_function_info "json_object"
# Output: Detailed function metadata
registry_function_info() {
    local func_name="$1"

    if [[ -z "$func_name" ]]; then
        printf 'Usage: registry_function_info FUNCTION_NAME\n' >&2
        return 1
    fi

    local func_meta
    func_meta=$(_registry_get_function "$func_name")
    if [[ $? -ne 0 ]]; then
        printf 'Function not found: %s\n' "$func_name" >&2
        return 1
    fi

    jq '.' <<< "$func_meta"
}

# Clear the registry cache
# Usage: registry_cache_clear
registry_cache_clear() {
    _REGISTRY_SCHEMA_CACHE=""
    _REGISTRY_SCHEMA_CACHE_TIME=0
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_REGISTRY_SCHEMA_EXPORTS=(
    # Core schema generation
    registry_to_openai_schema
    registry_to_anthropic_schema
    registry_to_openapi

    # Batch operations
    registry_export_schemas
    registry_schema_batch

    # Validation
    registry_validate_schema

    # Utilities
    registry_list_functions
    registry_list_libraries
    registry_function_count
    registry_search
    registry_function_info
    registry_cache_clear
)

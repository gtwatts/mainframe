#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/llm_functions.sh - LLM Function/Tool Calling Primitives
# =============================================================================
# Description: Pure bash library for parsing, validating, and executing LLM
#              tool calls. Supports both OpenAI and Anthropic formats.
#              Provides tool registry, schema validation, and result formatting.
#
# Features:
#   - Parse tool calls from OpenAI and Anthropic response formats
#   - Register and execute tools with schema validation
#   - Format results for LLM consumption
#   - Export tools in OpenAI/Anthropic formats
#
# Dependencies: json.sh, schema.sh
# Version: 1.0.0
# Requires: Bash 4.0+, jq (for complex JSON parsing)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_LLM_FUNCTIONS_LOADED:-}" ]] && return 0
readonly _MAINFRAME_LLM_FUNCTIONS_LOADED=1

# =============================================================================
# TOOL REGISTRY
# =============================================================================
# Global associative arrays to store registered tools
# Tool name -> function name mapping
declare -gA _LLM_TOOL_FUNCTIONS
# Tool name -> schema JSON mapping
declare -gA _LLM_TOOL_SCHEMAS
# Tool name -> description mapping
declare -gA _LLM_TOOL_DESCRIPTIONS

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Internal logging using centralized MAINFRAME logging
_llm_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "llm" "$level" "$@"
    fi
}

# Check if jq is available
_llm_has_jq() {
    command -v jq &>/dev/null
}

# Extract value from JSON using jq (safer for complex structures)
# Usage: _llm_jq_get '{"key":"value"}' '.key'
_llm_jq_get() {
    local json="$1"
    local path="$2"

    if _llm_has_jq; then
        jq -r "$path // empty" <<< "$json" 2>/dev/null
    else
        return 1
    fi
}

# Extract raw value (with type info) using jq
# Usage: _llm_jq_get_raw '{"key":42}' '.key'
_llm_jq_get_raw() {
    local json="$1"
    local path="$2"

    if _llm_has_jq; then
        jq -c "$path // null" <<< "$json" 2>/dev/null
    else
        return 1
    fi
}

# Generate a unique ID for tool calls
# Usage: _llm_generate_id [prefix]
_llm_generate_id() {
    local prefix="${1:-call}"
    local random_part

    if [[ -f /dev/urandom ]]; then
        random_part=$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')
    else
        random_part=$(date +%s%N | md5sum | head -c 12)
    fi

    printf '%s_%s' "$prefix" "$random_part"
}

# =============================================================================
# TOOL REGISTRATION
# =============================================================================

# Register a tool for execution
# Usage: llm_register_tool "name" "function" "schema_json"
# Example:
#   llm_register_tool "get_weather" "my_weather_func" '{
#     "name": "get_weather",
#     "description": "Get weather for a city",
#     "parameters": {
#       "type": "object",
#       "properties": {
#         "city": {"type": "string", "description": "City name"}
#       },
#       "required": ["city"]
#     }
#   }'
# Returns: 0 on success, 1 on failure
llm_register_tool() {
    local name="$1"
    local func="$2"
    local schema="$3"

    # Validate inputs
    [[ -z "$name" ]] && {
        _llm_log "error" "Tool name is required"
        return 1
    }
    [[ -z "$func" ]] && {
        _llm_log "error" "Function name is required"
        return 1
    }
    [[ -z "$schema" ]] && {
        _llm_log "error" "Schema is required"
        return 1
    }

    # Validate function exists
    if ! declare -F "$func" &>/dev/null; then
        _llm_log "error" "Function '$func' not found"
        return 1
    fi

    # Validate schema is valid JSON
    if declare -F json_valid &>/dev/null; then
        if ! json_valid "$schema"; then
            _llm_log "error" "Invalid JSON schema"
            return 1
        fi
    fi

    # Extract description from schema
    local desc=""
    if _llm_has_jq; then
        desc=$(_llm_jq_get "$schema" '.description')
    elif declare -F json_get &>/dev/null; then
        desc=$(json_get "$schema" "description") || desc=""
    fi

    # Register the tool
    _LLM_TOOL_FUNCTIONS["$name"]="$func"
    _LLM_TOOL_SCHEMAS["$name"]="$schema"
    _LLM_TOOL_DESCRIPTIONS["$name"]="${desc:-No description}"

    _llm_log "info" "Registered tool: $name -> $func"
    return 0
}

# Unregister a tool
# Usage: llm_unregister_tool "name"
# Returns: 0 on success, 1 if not found
llm_unregister_tool() {
    local name="$1"

    [[ -z "$name" ]] && return 1
    [[ -z "${_LLM_TOOL_FUNCTIONS[$name]:-}" ]] && return 1

    unset "_LLM_TOOL_FUNCTIONS[$name]"
    unset "_LLM_TOOL_SCHEMAS[$name]"
    unset "_LLM_TOOL_DESCRIPTIONS[$name]"

    return 0
}

# List all registered tools
# Usage: llm_list_tools
# Output: One tool name per line
llm_list_tools() {
    local name
    for name in "${!_LLM_TOOL_FUNCTIONS[@]}"; do
        printf '%s\n' "$name"
    done | sort
}

# Get schema for a specific tool
# Usage: llm_get_tool_schema "tool_name"
# Output: Schema JSON
# Returns: 0 on success, 1 if not found
llm_get_tool_schema() {
    local name="$1"

    [[ -z "$name" ]] && return 1
    [[ -z "${_LLM_TOOL_SCHEMAS[$name]:-}" ]] && return 1

    printf '%s' "${_LLM_TOOL_SCHEMAS[$name]}"
    return 0
}

# Check if a tool is registered
# Usage: llm_tool_exists "tool_name"
# Returns: 0 if exists, 1 if not
llm_tool_exists() {
    local name="$1"
    [[ -n "${_LLM_TOOL_FUNCTIONS[$name]:-}" ]]
}

# Clear all registered tools
# Usage: llm_clear_tools
llm_clear_tools() {
    _LLM_TOOL_FUNCTIONS=()
    _LLM_TOOL_SCHEMAS=()
    _LLM_TOOL_DESCRIPTIONS=()
}

# =============================================================================
# TOOL CALL PARSING
# =============================================================================

# Detect format of LLM response (openai or anthropic)
# Usage: llm_detect_format "response_json"
# Output: "openai", "anthropic", or "unknown"
llm_detect_format() {
    local response="$1"

    [[ -z "$response" ]] && {
        printf 'unknown'
        return 1
    }

    if _llm_has_jq; then
        # Check for OpenAI format: has tool_calls array
        if jq -e '.tool_calls' <<< "$response" &>/dev/null; then
            printf 'openai'
            return 0
        fi

        # Check for Anthropic format: has content array with tool_use type
        if jq -e '.content[]? | select(.type == "tool_use")' <<< "$response" &>/dev/null; then
            printf 'anthropic'
            return 0
        fi
    else
        # Fallback to pattern matching
        if [[ "$response" =~ \"tool_calls\"[[:space:]]*: ]]; then
            printf 'openai'
            return 0
        fi
        if [[ "$response" =~ \"type\"[[:space:]]*:[[:space:]]*\"tool_use\" ]]; then
            printf 'anthropic'
            return 0
        fi
    fi

    printf 'unknown'
    return 1
}

# Parse tool call from LLM response (auto-detects format)
# Usage: llm_parse_tool_call "response_json"
# Output: JSON object with normalized tool call info:
#   {"id":"...", "name":"...", "arguments":{...}}
# Returns: 0 on success, 1 on failure
llm_parse_tool_call() {
    local response="$1"

    [[ -z "$response" ]] && {
        _llm_log "error" "Empty response"
        return 1
    }

    local format
    format=$(llm_detect_format "$response")

    case "$format" in
        openai)
            _llm_parse_openai "$response"
            ;;
        anthropic)
            _llm_parse_anthropic "$response"
            ;;
        *)
            _llm_log "error" "Unknown response format"
            return 1
            ;;
    esac
}

# Parse OpenAI format tool call
# Input: {"tool_calls": [{"id": "call_abc", "type": "function", "function": {"name": "get_weather", "arguments": "{\"city\":\"NYC\"}"}}]}
# Output: {"id":"call_abc", "name":"get_weather", "arguments":{"city":"NYC"}}
_llm_parse_openai() {
    local response="$1"

    if ! _llm_has_jq; then
        _llm_log "error" "jq required for OpenAI parsing"
        return 1
    fi

    # Extract first tool call
    local tool_call
    tool_call=$(jq -c '.tool_calls[0] // null' <<< "$response" 2>/dev/null)

    [[ "$tool_call" == "null" || -z "$tool_call" ]] && {
        _llm_log "error" "No tool calls found"
        return 1
    }

    local id name args_str
    id=$(jq -r '.id // ""' <<< "$tool_call")
    name=$(jq -r '.function.name // ""' <<< "$tool_call")
    args_str=$(jq -r '.function.arguments // "{}"' <<< "$tool_call")

    [[ -z "$name" ]] && {
        _llm_log "error" "No function name in tool call"
        return 1
    }

    # Parse arguments string to JSON
    local args_json
    if jq -e '.' <<< "$args_str" &>/dev/null; then
        args_json=$(jq -c '.' <<< "$args_str")
    else
        args_json='{}'
    fi

    # Build normalized output
    jq -c -n \
        --arg id "$id" \
        --arg name "$name" \
        --argjson args "$args_json" \
        '{"id": $id, "name": $name, "arguments": $args}'
}

# Parse Anthropic format tool call
# Input: {"content": [{"type": "tool_use", "id": "toolu_abc", "name": "get_weather", "input": {"city": "NYC"}}]}
# Output: {"id":"toolu_abc", "name":"get_weather", "arguments":{"city":"NYC"}}
_llm_parse_anthropic() {
    local response="$1"

    if ! _llm_has_jq; then
        _llm_log "error" "jq required for Anthropic parsing"
        return 1
    fi

    # Extract first tool_use from content
    local tool_use
    tool_use=$(jq -c '.content[] | select(.type == "tool_use") | limit(1;.)' <<< "$response" 2>/dev/null | head -1)

    [[ -z "$tool_use" ]] && {
        _llm_log "error" "No tool_use found in content"
        return 1
    }

    local id name input
    id=$(jq -r '.id // ""' <<< "$tool_use")
    name=$(jq -r '.name // ""' <<< "$tool_use")
    input=$(jq -c '.input // {}' <<< "$tool_use")

    [[ -z "$name" ]] && {
        _llm_log "error" "No name in tool_use"
        return 1
    }

    # Build normalized output (use "arguments" for consistency)
    jq -c -n \
        --arg id "$id" \
        --arg name "$name" \
        --argjson args "$input" \
        '{"id": $id, "name": $name, "arguments": $args}'
}

# Parse all tool calls from response (for multiple tool calls)
# Usage: llm_parse_tool_calls "response_json"
# Output: JSON array of normalized tool calls
llm_parse_tool_calls() {
    local response="$1"

    [[ -z "$response" ]] && {
        printf '[]'
        return 1
    }

    local format
    format=$(llm_detect_format "$response")

    if ! _llm_has_jq; then
        # Fallback: just parse single call and wrap in array
        local single
        single=$(llm_parse_tool_call "$response") || {
            printf '[]'
            return 1
        }
        printf '[%s]' "$single"
        return 0
    fi

    case "$format" in
        openai)
            jq -c '[.tool_calls[]? | {
                id: .id,
                name: .function.name,
                arguments: (.function.arguments | if type == "string" then fromjson else . end)
            }]' <<< "$response" 2>/dev/null || printf '[]'
            ;;
        anthropic)
            jq -c '[.content[]? | select(.type == "tool_use") | {
                id: .id,
                name: .name,
                arguments: .input
            }]' <<< "$response" 2>/dev/null || printf '[]'
            ;;
        *)
            printf '[]'
            return 1
            ;;
    esac
}

# =============================================================================
# ARGUMENT VALIDATION
# =============================================================================

# Validate tool arguments against schema
# Usage: llm_validate_tool_args "schema_json" "args_json"
# Returns: 0 if valid, 1 if invalid
# Note: Uses lib/schema.sh for validation when available
llm_validate_tool_args() {
    local schema_json="$1"
    local args_json="$2"

    [[ -z "$schema_json" ]] && {
        _llm_log "error" "Schema is required"
        return 1
    }
    [[ -z "$args_json" ]] && {
        _llm_log "error" "Arguments are required"
        return 1
    }

    # Extract parameters schema from tool schema
    local params_schema
    if _llm_has_jq; then
        params_schema=$(jq -c '.parameters // .' <<< "$schema_json" 2>/dev/null)
    else
        params_schema="$schema_json"
    fi

    # Use schema.sh if available
    if declare -F schema_check &>/dev/null; then
        if schema_check "$params_schema" "$args_json"; then
            return 0
        else
            _llm_log "error" "Schema validation failed"
            return 1
        fi
    fi

    # Fallback: basic validation with jq
    if _llm_has_jq; then
        # Check if args is valid JSON
        if ! jq -e '.' <<< "$args_json" &>/dev/null; then
            _llm_log "error" "Invalid JSON arguments"
            return 1
        fi

        # Check required fields
        local required
        required=$(jq -r '.required[]?' <<< "$params_schema" 2>/dev/null)

        if [[ -n "$required" ]]; then
            while IFS= read -r field; do
                [[ -z "$field" ]] && continue
                if ! jq -e --arg f "$field" 'has($f)' <<< "$args_json" &>/dev/null; then
                    _llm_log "error" "Missing required field: $field"
                    return 1
                fi
            done <<< "$required"
        fi

        return 0
    fi

    # No validation available, assume valid
    _llm_log "warn" "No validation available, skipping"
    return 0
}

# Get validation errors for tool arguments
# Usage: llm_validate_tool_args_errors "schema_json" "args_json"
# Output: JSON array of error messages
llm_validate_tool_args_errors() {
    local schema_json="$1"
    local args_json="$2"

    # Extract parameters schema
    local params_schema
    if _llm_has_jq; then
        params_schema=$(jq -c '.parameters // .' <<< "$schema_json" 2>/dev/null)
    else
        params_schema="$schema_json"
    fi

    # Use schema.sh if available
    if declare -F schema_check &>/dev/null && declare -F schema_last_errors &>/dev/null; then
        schema_check "$params_schema" "$args_json" || true
        schema_last_errors
        return 0
    fi

    # Basic error collection with jq
    if _llm_has_jq; then
        local errors='[]'

        # Check valid JSON
        if ! jq -e '.' <<< "$args_json" &>/dev/null; then
            printf '["Invalid JSON arguments"]'
            return 0
        fi

        # Check required fields
        local required
        required=$(jq -r '.required[]?' <<< "$params_schema" 2>/dev/null)

        if [[ -n "$required" ]]; then
            while IFS= read -r field; do
                [[ -z "$field" ]] && continue
                if ! jq -e --arg f "$field" 'has($f)' <<< "$args_json" &>/dev/null; then
                    errors=$(jq -c --arg e "Missing required field: $field" '. + [$e]' <<< "$errors")
                fi
            done <<< "$required"
        fi

        printf '%s' "$errors"
        return 0
    fi

    printf '[]'
}

# =============================================================================
# TOOL EXECUTION
# =============================================================================

# Execute a registered tool with arguments
# Usage: llm_execute_tool "tool_name" "args_json"
# Output: Tool execution result (raw output from function)
# Returns: Tool function's return code
llm_execute_tool() {
    local tool_name="$1"
    local _default_args='{}'
    local args_json="${2:-$_default_args}"

    [[ -z "$tool_name" ]] && {
        _llm_log "error" "Tool name is required"
        return 1
    }

    # Check if tool exists
    if ! llm_tool_exists "$tool_name"; then
        _llm_log "error" "Tool not found: $tool_name"
        return 1
    fi

    local func="${_LLM_TOOL_FUNCTIONS[$tool_name]}"
    local schema="${_LLM_TOOL_SCHEMAS[$tool_name]}"

    # Validate arguments if schema exists
    if [[ -n "$schema" ]]; then
        if ! llm_validate_tool_args "$schema" "$args_json"; then
            _llm_log "error" "Argument validation failed for $tool_name"
            return 1
        fi
    fi

    # Execute the tool function
    # Pass args as first parameter (function should parse JSON)
    _llm_log "debug" "Executing tool: $tool_name"
    "$func" "$args_json"
}

# Execute tool and capture result with metadata
# Usage: llm_execute_tool_safe "tool_name" "args_json"
# Output: JSON with result, error, duration, etc.
llm_execute_tool_safe() {
    local tool_name="$1"
    local _default_args='{}'
    local args_json="${2:-$_default_args}"

    local start_time result exit_code end_time duration

    # Record start time
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        start_time="$EPOCHREALTIME"
    else
        start_time=$(date +%s.%N 2>/dev/null || date +%s)
    fi

    # Execute and capture
    result=$(llm_execute_tool "$tool_name" "$args_json" 2>&1)
    exit_code=$?

    # Record end time
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        end_time="$EPOCHREALTIME"
    else
        end_time=$(date +%s.%N 2>/dev/null || date +%s)
    fi

    # Calculate duration (using bc if available)
    if command -v bc &>/dev/null; then
        duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
    else
        duration="0"
    fi

    # Build response
    if _llm_has_jq; then
        jq -c -n \
            --arg tool "$tool_name" \
            --argjson args "$args_json" \
            --arg result "$result" \
            --argjson exit_code "$exit_code" \
            --arg duration "$duration" \
            '{
                tool: $tool,
                arguments: $args,
                result: $result,
                success: ($exit_code == 0),
                exit_code: $exit_code,
                duration_seconds: ($duration | tonumber)
            }'
    else
        # Fallback JSON construction
        local success="false"
        [[ $exit_code -eq 0 ]] && success="true"

        local escaped_result
        escaped_result=$(printf '%s' "$result" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')

        printf '{"tool":"%s","result":"%s","success":%s,"exit_code":%d}' \
            "$tool_name" "$escaped_result" "$success" "$exit_code"
    fi
}

# =============================================================================
# RESULT FORMATTING
# =============================================================================

# Format tool result for LLM consumption
# Usage: llm_format_tool_result "result" "tool_call_id" [format]
# Output: Formatted result JSON for OpenAI or Anthropic
llm_format_tool_result() {
    local result="$1"
    local tool_call_id="${2:-$(_llm_generate_id "call")}"
    local format="${3:-openai}"

    case "$format" in
        openai)
            _llm_format_result_openai "$result" "$tool_call_id"
            ;;
        anthropic)
            _llm_format_result_anthropic "$result" "$tool_call_id"
            ;;
        *)
            _llm_log "error" "Unknown format: $format"
            return 1
            ;;
    esac
}

# Format result for OpenAI format
# Output: {"role": "tool", "tool_call_id": "...", "content": "..."}
_llm_format_result_openai() {
    local result="$1"
    local tool_call_id="$2"

    if _llm_has_jq; then
        jq -c -n \
            --arg role "tool" \
            --arg id "$tool_call_id" \
            --arg content "$result" \
            '{"role": $role, "tool_call_id": $id, "content": $content}'
    else
        local escaped
        escaped=$(printf '%s' "$result" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')
        printf '{"role":"tool","tool_call_id":"%s","content":"%s"}' "$tool_call_id" "$escaped"
    fi
}

# Format result for Anthropic format
# Output: {"type": "tool_result", "tool_use_id": "...", "content": "..."}
_llm_format_result_anthropic() {
    local result="$1"
    local tool_use_id="$2"

    if _llm_has_jq; then
        jq -c -n \
            --arg type "tool_result" \
            --arg id "$tool_use_id" \
            --arg content "$result" \
            '{"type": $type, "tool_use_id": $id, "content": $content}'
    else
        local escaped
        escaped=$(printf '%s' "$result" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')
        printf '{"type":"tool_result","tool_use_id":"%s","content":"%s"}' "$tool_use_id" "$escaped"
    fi
}

# Format error result for LLM
# Usage: llm_format_tool_error "error_message" "tool_call_id" [format]
llm_format_tool_error() {
    local error="$1"
    local tool_call_id="${2:-$(_llm_generate_id "call")}"
    local format="${3:-openai}"

    local error_result
    if _llm_has_jq; then
        error_result=$(jq -c -n --arg e "$error" '{"error": $e}')
    else
        local escaped
        escaped=$(printf '%s' "$error" | sed 's/\\/\\\\/g; s/"/\\"/g')
        error_result="{\"error\":\"$escaped\"}"
    fi

    llm_format_tool_result "$error_result" "$tool_call_id" "$format"
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export all tools in OpenAI function format
# Usage: llm_tools_to_openai
# Output: JSON array of function definitions
llm_tools_to_openai() {
    if ! _llm_has_jq; then
        _llm_log "error" "jq required for export"
        printf '[]'
        return 1
    fi

    local tools='[]'
    local name schema params desc

    for name in "${!_LLM_TOOL_SCHEMAS[@]}"; do
        schema="${_LLM_TOOL_SCHEMAS[$name]}"
        desc="${_LLM_TOOL_DESCRIPTIONS[$name]}"

        # Extract parameters from schema
        params=$(jq -c '.parameters // {}' <<< "$schema" 2>/dev/null || echo '{}')

        # Build function definition
        local func_def
        func_def=$(jq -c -n \
            --arg name "$name" \
            --arg desc "$desc" \
            --argjson params "$params" \
            '{
                type: "function",
                function: {
                    name: $name,
                    description: $desc,
                    parameters: $params
                }
            }')

        tools=$(jq -c --argjson t "$func_def" '. + [$t]' <<< "$tools")
    done

    printf '%s' "$tools"
}

# Export all tools in Anthropic tool format
# Usage: llm_tools_to_anthropic
# Output: JSON array of tool definitions
llm_tools_to_anthropic() {
    if ! _llm_has_jq; then
        _llm_log "error" "jq required for export"
        printf '[]'
        return 1
    fi

    local tools='[]'
    local name schema params desc

    for name in "${!_LLM_TOOL_SCHEMAS[@]}"; do
        schema="${_LLM_TOOL_SCHEMAS[$name]}"
        desc="${_LLM_TOOL_DESCRIPTIONS[$name]}"

        # Extract parameters (Anthropic calls it input_schema)
        params=$(jq -c '.parameters // {}' <<< "$schema" 2>/dev/null || echo '{}')

        # Build tool definition
        local tool_def
        tool_def=$(jq -c -n \
            --arg name "$name" \
            --arg desc "$desc" \
            --argjson params "$params" \
            '{
                name: $name,
                description: $desc,
                input_schema: $params
            }')

        tools=$(jq -c --argjson t "$tool_def" '. + [$t]' <<< "$tools")
    done

    printf '%s' "$tools"
}

# Export single tool in specified format
# Usage: llm_tool_export "tool_name" [format]
# format: "openai" or "anthropic"
llm_tool_export() {
    local name="$1"
    local format="${2:-openai}"

    [[ -z "$name" ]] && return 1
    [[ -z "${_LLM_TOOL_SCHEMAS[$name]:-}" ]] && return 1

    if ! _llm_has_jq; then
        printf '%s' "${_LLM_TOOL_SCHEMAS[$name]}"
        return 0
    fi

    local schema="${_LLM_TOOL_SCHEMAS[$name]}"
    local desc="${_LLM_TOOL_DESCRIPTIONS[$name]}"
    local params
    params=$(jq -c '.parameters // {}' <<< "$schema" 2>/dev/null || echo '{}')

    case "$format" in
        openai)
            jq -c -n \
                --arg name "$name" \
                --arg desc "$desc" \
                --argjson params "$params" \
                '{
                    type: "function",
                    function: {
                        name: $name,
                        description: $desc,
                        parameters: $params
                    }
                }'
            ;;
        anthropic)
            jq -c -n \
                --arg name "$name" \
                --arg desc "$desc" \
                --argjson params "$params" \
                '{
                    name: $name,
                    description: $desc,
                    input_schema: $params
                }'
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

# Process a complete tool call cycle: parse, execute, format result
# Usage: llm_process_tool_call "response_json" [output_format]
# Output: Formatted tool result ready to send back to LLM
llm_process_tool_call() {
    local response="$1"
    local output_format="${2:-}"

    # Auto-detect input format if output format not specified
    if [[ -z "$output_format" ]]; then
        output_format=$(llm_detect_format "$response")
        [[ "$output_format" == "unknown" ]] && output_format="openai"
    fi

    # Parse the tool call
    local parsed
    parsed=$(llm_parse_tool_call "$response") || {
        llm_format_tool_error "Failed to parse tool call" "" "$output_format"
        return 1
    }

    if ! _llm_has_jq; then
        llm_format_tool_error "jq required for processing" "" "$output_format"
        return 1
    fi

    local tool_id tool_name args
    tool_id=$(jq -r '.id' <<< "$parsed")
    tool_name=$(jq -r '.name' <<< "$parsed")
    args=$(jq -c '.arguments' <<< "$parsed")

    # Check if tool exists
    if ! llm_tool_exists "$tool_name"; then
        llm_format_tool_error "Unknown tool: $tool_name" "$tool_id" "$output_format"
        return 1
    fi

    # Execute tool
    local result exit_code
    result=$(llm_execute_tool "$tool_name" "$args" 2>&1)
    exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        llm_format_tool_error "$result" "$tool_id" "$output_format"
        return 1
    fi

    # Format and return result
    llm_format_tool_result "$result" "$tool_id" "$output_format"
}

# Get tool info as JSON
# Usage: llm_tool_info "tool_name"
# Output: JSON with tool name, description, function, has_schema
llm_tool_info() {
    local name="$1"

    [[ -z "$name" ]] && return 1
    [[ -z "${_LLM_TOOL_FUNCTIONS[$name]:-}" ]] && return 1

    if _llm_has_jq; then
        jq -c -n \
            --arg name "$name" \
            --arg func "${_LLM_TOOL_FUNCTIONS[$name]}" \
            --arg desc "${_LLM_TOOL_DESCRIPTIONS[$name]:-}" \
            --argjson has_schema "$([[ -n "${_LLM_TOOL_SCHEMAS[$name]:-}" ]] && echo true || echo false)" \
            '{
                name: $name,
                function: $func,
                description: $desc,
                has_schema: $has_schema
            }'
    else
        printf '{"name":"%s","function":"%s","description":"%s"}' \
            "$name" "${_LLM_TOOL_FUNCTIONS[$name]}" "${_LLM_TOOL_DESCRIPTIONS[$name]:-}"
    fi
}

# =============================================================================
# NAMEREF VARIANTS (High-Performance)
# =============================================================================

# Parse tool call into variable
# Usage: llm_parse_tool_call_v result_var "response_json"
llm_parse_tool_call_v() {
    local -n __lptcv_out=$1
    __lptcv_out=$(llm_parse_tool_call "$2")
}

# Execute tool and store result in variable
# Usage: llm_execute_tool_v result_var "tool_name" "args_json"
llm_execute_tool_v() {
    local -n __letv_out=$1
    __letv_out=$(llm_execute_tool "$2" "$3")
}

# Validate tool args and store result in variable
# Usage: llm_validate_tool_args_v result_var "schema" "args"
# Sets result_var to "true" or "false"
llm_validate_tool_args_v() {
    local -n __lvtav_out=$1
    if llm_validate_tool_args "$2" "$3"; then
        __lvtav_out="true"
    else
        __lvtav_out="false"
    fi
}

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

# Initialize module (called on source)
_llm_functions_init() {
    # Ensure jq is available for full functionality
    if ! _llm_has_jq; then
        _llm_log "warn" "jq not found - some features will be limited"
    fi

    _llm_log "debug" "llm_functions.sh loaded"
}

# Run initialization
_llm_functions_init

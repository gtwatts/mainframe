#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/llm_functions.bats - LLM Function/Tool Calling Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/llm_functions.sh
#              Tests tool registration, parsing, validation, execution,
#              and format conversion for OpenAI and Anthropic APIs.
# Test Count: 50+ test cases
# Categories: tool registration, tool call parsing, argument validation,
#             tool execution, result formatting, format export, edge cases
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Source required libraries
    source "$MAINFRAME_ROOT/lib/json.sh"
    source "$MAINFRAME_ROOT/lib/schema.sh"
    source "$MAINFRAME_ROOT/lib/llm_functions.sh"

    # Clear tool registry for clean tests
    llm_clear_tools

    # Define test tools
    _define_test_tools
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
    llm_clear_tools
}

# Helper: Define standard test tools
_define_test_tools() {
    # Simple echo tool
    test_echo_tool() {
        local args="$1"
        if command -v jq &>/dev/null; then
            jq -r '.message // "no message"' <<< "$args"
        else
            printf '%s' "$args"
        fi
    }

    # Weather tool
    test_weather_tool() {
        local args="$1"
        local city
        if command -v jq &>/dev/null; then
            city=$(jq -r '.city // "Unknown"' <<< "$args")
        else
            city="TestCity"
        fi
        printf '{"city":"%s","temp":72,"condition":"sunny"}' "$city"
    }

    # Calculator tool
    test_calc_tool() {
        local args="$1"
        if command -v jq &>/dev/null; then
            local a b op
            a=$(jq -r '.a // 0' <<< "$args")
            b=$(jq -r '.b // 0' <<< "$args")
            op=$(jq -r '.op // "add"' <<< "$args")
            case "$op" in
                add) echo $((a + b)) ;;
                sub) echo $((a - b)) ;;
                mul) echo $((a * b)) ;;
                *) echo "0" ;;
            esac
        else
            echo "0"
        fi
    }

    # Failing tool
    test_failing_tool() {
        echo "error: intentional failure"
        return 1
    }

    # Export functions for use in tests
    export -f test_echo_tool test_weather_tool test_calc_tool test_failing_tool
}

# =============================================================================
# CATEGORY 1: TOOL REGISTRATION
# =============================================================================

@test "llm_register_tool: registers a valid tool" {
    llm_register_tool "echo" "test_echo_tool" '{
        "name": "echo",
        "description": "Echo a message",
        "parameters": {
            "type": "object",
            "properties": {"message": {"type": "string"}},
            "required": ["message"]
        }
    }'
    [[ $? -eq 0 ]]
}

@test "llm_register_tool: fails on empty name" {
    run llm_register_tool "" "test_echo_tool" '{"name":"test"}'
    [[ "$status" -eq 1 ]]
}

@test "llm_register_tool: fails on empty function" {
    run llm_register_tool "test" "" '{"name":"test"}'
    [[ "$status" -eq 1 ]]
}

@test "llm_register_tool: fails on non-existent function" {
    run llm_register_tool "test" "nonexistent_function_xyz" '{"name":"test"}'
    [[ "$status" -eq 1 ]]
}

@test "llm_register_tool: fails on empty schema" {
    run llm_register_tool "test" "test_echo_tool" ""
    [[ "$status" -eq 1 ]]
}

@test "llm_register_tool: fails on invalid JSON schema" {
    run llm_register_tool "test" "test_echo_tool" '{invalid}'
    [[ "$status" -eq 1 ]]
}

@test "llm_register_tool: overwrites existing tool" {
    llm_register_tool "echo" "test_echo_tool" '{"name":"echo","description":"Old"}'
    llm_register_tool "echo" "test_weather_tool" '{"name":"echo","description":"New"}'
    result=$(llm_get_tool_schema "echo")
    [[ "$result" =~ "New" ]]
}

# =============================================================================
# CATEGORY 2: TOOL REGISTRY OPERATIONS
# =============================================================================

@test "llm_list_tools: lists registered tools" {
    llm_register_tool "alpha" "test_echo_tool" '{"name":"alpha"}'
    llm_register_tool "beta" "test_echo_tool" '{"name":"beta"}'
    result=$(llm_list_tools)
    [[ "$result" =~ "alpha" ]]
    [[ "$result" =~ "beta" ]]
}

@test "llm_list_tools: returns empty for no tools" {
    result=$(llm_list_tools)
    [[ -z "$result" ]]
}

@test "llm_get_tool_schema: returns registered schema" {
    llm_register_tool "test" "test_echo_tool" '{"name":"test","parameters":{}}'
    result=$(llm_get_tool_schema "test")
    [[ "$result" =~ '"name":"test"' ]]
}

@test "llm_get_tool_schema: fails for non-existent tool" {
    run llm_get_tool_schema "nonexistent"
    [[ "$status" -eq 1 ]]
}

@test "llm_tool_exists: returns 0 for existing tool" {
    llm_register_tool "exists" "test_echo_tool" '{"name":"exists"}'
    llm_tool_exists "exists"
    [[ $? -eq 0 ]]
}

@test "llm_tool_exists: returns 1 for non-existent tool" {
    run llm_tool_exists "nonexistent"
    [[ "$status" -eq 1 ]]
}

@test "llm_unregister_tool: removes a tool" {
    llm_register_tool "to_remove" "test_echo_tool" '{"name":"to_remove"}'
    llm_unregister_tool "to_remove"
    run llm_tool_exists "to_remove"
    [[ "$status" -eq 1 ]]
}

@test "llm_clear_tools: removes all tools" {
    llm_register_tool "one" "test_echo_tool" '{"name":"one"}'
    llm_register_tool "two" "test_echo_tool" '{"name":"two"}'
    llm_clear_tools
    result=$(llm_list_tools)
    [[ -z "$result" ]]
}

# =============================================================================
# CATEGORY 3: FORMAT DETECTION
# =============================================================================

@test "llm_detect_format: detects OpenAI format" {
    local openai_response='{"tool_calls":[{"id":"call_123","type":"function","function":{"name":"test","arguments":"{}"}}]}'
    result=$(llm_detect_format "$openai_response")
    [[ "$result" == "openai" ]]
}

@test "llm_detect_format: detects Anthropic format" {
    local anthropic_response='{"content":[{"type":"tool_use","id":"toolu_123","name":"test","input":{}}]}'
    result=$(llm_detect_format "$anthropic_response")
    [[ "$result" == "anthropic" ]]
}

@test "llm_detect_format: returns unknown for invalid format" {
    local invalid='{"message":"hello"}'
    run llm_detect_format "$invalid"
    [[ "$output" == "unknown" ]]
}

@test "llm_detect_format: returns unknown for empty input" {
    run llm_detect_format ""
    [[ "$output" == "unknown" ]]
}

# =============================================================================
# CATEGORY 4: OPENAI TOOL CALL PARSING
# =============================================================================

@test "llm_parse_tool_call: parses OpenAI format" {
    skip_if_no_jq
    local response='{"tool_calls":[{"id":"call_abc","type":"function","function":{"name":"get_weather","arguments":"{\"city\":\"NYC\"}"}}]}'
    result=$(llm_parse_tool_call "$response")
    [[ "$result" =~ '"name":"get_weather"' ]]
    [[ "$result" =~ '"id":"call_abc"' ]]
    [[ "$result" =~ '"city":"NYC"' ]]
}

@test "llm_parse_tool_call: extracts arguments from OpenAI format" {
    skip_if_no_jq
    local response='{"tool_calls":[{"id":"call_123","type":"function","function":{"name":"calc","arguments":"{\"a\":5,\"b\":3}"}}]}'
    result=$(llm_parse_tool_call "$response")
    # Arguments should be parsed JSON, not string
    echo "$result" | jq -e '.arguments.a == 5' &>/dev/null
}

@test "llm_parse_tool_call: handles empty arguments" {
    skip_if_no_jq
    local response='{"tool_calls":[{"id":"call_123","type":"function","function":{"name":"test","arguments":"{}"}}]}'
    result=$(llm_parse_tool_call "$response")
    [[ "$result" =~ '"arguments":{}' ]]
}

# =============================================================================
# CATEGORY 5: ANTHROPIC TOOL CALL PARSING
# =============================================================================

@test "llm_parse_tool_call: parses Anthropic format" {
    skip_if_no_jq
    local response='{"content":[{"type":"tool_use","id":"toolu_abc","name":"get_weather","input":{"city":"NYC"}}]}'
    result=$(llm_parse_tool_call "$response")
    [[ "$result" =~ '"name":"get_weather"' ]]
    [[ "$result" =~ '"id":"toolu_abc"' ]]
    [[ "$result" =~ '"city":"NYC"' ]]
}

@test "llm_parse_tool_call: handles Anthropic nested input" {
    skip_if_no_jq
    local response='{"content":[{"type":"tool_use","id":"toolu_123","name":"nested","input":{"user":{"name":"John","age":30}}}]}'
    result=$(llm_parse_tool_call "$response")
    echo "$result" | jq -e '.arguments.user.name == "John"' &>/dev/null
}

# =============================================================================
# CATEGORY 6: MULTIPLE TOOL CALLS
# =============================================================================

@test "llm_parse_tool_calls: parses multiple OpenAI calls" {
    skip_if_no_jq
    local response='{"tool_calls":[
        {"id":"call_1","type":"function","function":{"name":"tool1","arguments":"{}"}},
        {"id":"call_2","type":"function","function":{"name":"tool2","arguments":"{}"}}
    ]}'
    result=$(llm_parse_tool_calls "$response")
    count=$(echo "$result" | jq 'length')
    [[ "$count" == "2" ]]
}

@test "llm_parse_tool_calls: parses multiple Anthropic calls" {
    skip_if_no_jq
    local response='{"content":[
        {"type":"tool_use","id":"toolu_1","name":"tool1","input":{}},
        {"type":"text","text":"Some text"},
        {"type":"tool_use","id":"toolu_2","name":"tool2","input":{}}
    ]}'
    result=$(llm_parse_tool_calls "$response")
    count=$(echo "$result" | jq 'length')
    [[ "$count" == "2" ]]
}

@test "llm_parse_tool_calls: returns empty array for no calls" {
    skip_if_no_jq
    local response='{"message":"no tools here"}'
    run llm_parse_tool_calls "$response"
    [[ "$output" == "[]" ]]
}

# =============================================================================
# CATEGORY 7: ARGUMENT VALIDATION
# =============================================================================

@test "llm_validate_tool_args: validates valid args" {
    local schema='{"parameters":{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}}'
    local args='{"name":"John"}'
    llm_validate_tool_args "$schema" "$args"
    [[ $? -eq 0 ]]
}

@test "llm_validate_tool_args: fails missing required field" {
    skip_if_no_jq
    local schema='{"parameters":{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}}'
    local args='{"age":30}'
    run llm_validate_tool_args "$schema" "$args"
    [[ "$status" -eq 1 ]]
}

@test "llm_validate_tool_args: fails invalid JSON args" {
    skip_if_no_jq
    local schema='{"parameters":{"type":"object"}}'
    local args='{invalid}'
    run llm_validate_tool_args "$schema" "$args"
    [[ "$status" -eq 1 ]]
}

@test "llm_validate_tool_args_errors: returns error array" {
    skip_if_no_jq
    local schema='{"parameters":{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}}'
    local args='{"age":30}'
    result=$(llm_validate_tool_args_errors "$schema" "$args")
    [[ "$result" =~ "[" ]]
}

# =============================================================================
# CATEGORY 8: TOOL EXECUTION
# =============================================================================

@test "llm_execute_tool: executes registered tool" {
    llm_register_tool "echo" "test_echo_tool" '{"name":"echo","parameters":{"type":"object","properties":{"message":{"type":"string"}}}}'
    result=$(llm_execute_tool "echo" '{"message":"Hello World"}')
    [[ "$result" == "Hello World" ]]
}

@test "llm_execute_tool: fails for non-existent tool" {
    run llm_execute_tool "nonexistent" '{}'
    [[ "$status" -eq 1 ]]
}

@test "llm_execute_tool: passes args to function" {
    skip_if_no_jq
    llm_register_tool "calc" "test_calc_tool" '{"name":"calc","parameters":{"type":"object","properties":{"a":{"type":"integer"},"b":{"type":"integer"},"op":{"type":"string"}}}}'
    result=$(llm_execute_tool "calc" '{"a":5,"b":3,"op":"add"}')
    [[ "$result" == "8" ]]
}

@test "llm_execute_tool: returns tool exit code" {
    llm_register_tool "failing" "test_failing_tool" '{"name":"failing"}'
    run llm_execute_tool "failing" '{}'
    [[ "$status" -eq 1 ]]
}

@test "llm_execute_tool_safe: captures result with metadata" {
    skip_if_no_jq
    llm_register_tool "echo" "test_echo_tool" '{"name":"echo","parameters":{}}'
    result=$(llm_execute_tool_safe "echo" '{"message":"test"}')
    echo "$result" | jq -e '.success == true' &>/dev/null
    echo "$result" | jq -e 'has("duration_seconds")' &>/dev/null
}

@test "llm_execute_tool_safe: captures failure" {
    skip_if_no_jq
    llm_register_tool "failing" "test_failing_tool" '{"name":"failing"}'
    result=$(llm_execute_tool_safe "failing" '{}')
    echo "$result" | jq -e '.success == false' &>/dev/null
}

# =============================================================================
# CATEGORY 9: RESULT FORMATTING
# =============================================================================

@test "llm_format_tool_result: formats for OpenAI" {
    skip_if_no_jq
    result=$(llm_format_tool_result "success" "call_123" "openai")
    echo "$result" | jq -e '.role == "tool"' &>/dev/null
    echo "$result" | jq -e '.tool_call_id == "call_123"' &>/dev/null
    echo "$result" | jq -e '.content == "success"' &>/dev/null
}

@test "llm_format_tool_result: formats for Anthropic" {
    skip_if_no_jq
    result=$(llm_format_tool_result "success" "toolu_123" "anthropic")
    echo "$result" | jq -e '.type == "tool_result"' &>/dev/null
    echo "$result" | jq -e '.tool_use_id == "toolu_123"' &>/dev/null
    echo "$result" | jq -e '.content == "success"' &>/dev/null
}

@test "llm_format_tool_result: generates ID if not provided" {
    skip_if_no_jq
    result=$(llm_format_tool_result "success")
    echo "$result" | jq -e '.tool_call_id | startswith("call_")' &>/dev/null
}

@test "llm_format_tool_error: formats error for OpenAI" {
    skip_if_no_jq
    result=$(llm_format_tool_error "Something went wrong" "call_123" "openai")
    echo "$result" | jq -e '.role == "tool"' &>/dev/null
    [[ "$result" =~ "error" ]]
}

@test "llm_format_tool_error: formats error for Anthropic" {
    skip_if_no_jq
    result=$(llm_format_tool_error "Something went wrong" "toolu_123" "anthropic")
    echo "$result" | jq -e '.type == "tool_result"' &>/dev/null
    [[ "$result" =~ "error" ]]
}

# =============================================================================
# CATEGORY 10: EXPORT FUNCTIONS
# =============================================================================

@test "llm_tools_to_openai: exports tools in OpenAI format" {
    skip_if_no_jq
    llm_register_tool "weather" "test_weather_tool" '{"name":"weather","description":"Get weather","parameters":{"type":"object","properties":{"city":{"type":"string"}}}}'
    result=$(llm_tools_to_openai)
    echo "$result" | jq -e '.[0].type == "function"' &>/dev/null
    echo "$result" | jq -e '.[0].function.name == "weather"' &>/dev/null
}

@test "llm_tools_to_anthropic: exports tools in Anthropic format" {
    skip_if_no_jq
    llm_register_tool "weather" "test_weather_tool" '{"name":"weather","description":"Get weather","parameters":{"type":"object","properties":{"city":{"type":"string"}}}}'
    result=$(llm_tools_to_anthropic)
    echo "$result" | jq -e '.[0].name == "weather"' &>/dev/null
    echo "$result" | jq -e '.[0] | has("input_schema")' &>/dev/null
}

@test "llm_tool_export: exports single tool in OpenAI format" {
    skip_if_no_jq
    llm_register_tool "test" "test_echo_tool" '{"name":"test","description":"Test tool","parameters":{}}'
    result=$(llm_tool_export "test" "openai")
    echo "$result" | jq -e '.type == "function"' &>/dev/null
}

@test "llm_tool_export: exports single tool in Anthropic format" {
    skip_if_no_jq
    llm_register_tool "test" "test_echo_tool" '{"name":"test","description":"Test tool","parameters":{}}'
    result=$(llm_tool_export "test" "anthropic")
    echo "$result" | jq -e 'has("input_schema")' &>/dev/null
}

# =============================================================================
# CATEGORY 11: COMPLETE PROCESSING CYCLE
# =============================================================================

@test "llm_process_tool_call: processes OpenAI call end-to-end" {
    skip_if_no_jq
    llm_register_tool "echo" "test_echo_tool" '{"name":"echo","parameters":{"type":"object","properties":{"message":{"type":"string"}}}}'
    local request='{"tool_calls":[{"id":"call_123","type":"function","function":{"name":"echo","arguments":"{\"message\":\"Hello\"}"}}]}'
    result=$(llm_process_tool_call "$request")
    echo "$result" | jq -e '.role == "tool"' &>/dev/null
    [[ "$result" =~ "Hello" ]]
}

@test "llm_process_tool_call: processes Anthropic call end-to-end" {
    skip_if_no_jq
    llm_register_tool "echo" "test_echo_tool" '{"name":"echo","parameters":{"type":"object","properties":{"message":{"type":"string"}}}}'
    local request='{"content":[{"type":"tool_use","id":"toolu_123","name":"echo","input":{"message":"Hello"}}]}'
    result=$(llm_process_tool_call "$request")
    echo "$result" | jq -e '.type == "tool_result"' &>/dev/null
    [[ "$result" =~ "Hello" ]]
}

@test "llm_process_tool_call: handles unknown tool" {
    skip_if_no_jq
    local request='{"tool_calls":[{"id":"call_123","type":"function","function":{"name":"unknown_tool","arguments":"{}"}}]}'
    run llm_process_tool_call "$request"
    [[ "$output" =~ "error" ]]
    [[ "$output" =~ "Unknown tool" ]]
}

# =============================================================================
# CATEGORY 12: TOOL INFO
# =============================================================================

@test "llm_tool_info: returns tool information" {
    skip_if_no_jq
    llm_register_tool "info_test" "test_echo_tool" '{"name":"info_test","description":"Test description"}'
    result=$(llm_tool_info "info_test")
    echo "$result" | jq -e '.name == "info_test"' &>/dev/null
    echo "$result" | jq -e '.function == "test_echo_tool"' &>/dev/null
    echo "$result" | jq -e '.has_schema == true' &>/dev/null
}

@test "llm_tool_info: fails for non-existent tool" {
    run llm_tool_info "nonexistent"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 13: NAMEREF VARIANTS
# =============================================================================

@test "llm_parse_tool_call_v: stores result in variable" {
    skip_if_no_jq
    local out
    local response='{"tool_calls":[{"id":"call_123","type":"function","function":{"name":"test","arguments":"{}"}}]}'
    llm_parse_tool_call_v out "$response"
    [[ "$out" =~ '"name":"test"' ]]
}

@test "llm_execute_tool_v: stores result in variable" {
    local out
    llm_register_tool "echo" "test_echo_tool" '{"name":"echo"}'
    llm_execute_tool_v out "echo" '{"message":"stored"}'
    [[ "$out" == "stored" ]]
}

@test "llm_validate_tool_args_v: stores validation result" {
    local out
    local schema='{"parameters":{"type":"object","properties":{"name":{"type":"string"}}}}'
    local args='{"name":"test"}'
    llm_validate_tool_args_v out "$schema" "$args"
    [[ "$out" == "true" ]]
}

# =============================================================================
# CATEGORY 14: EDGE CASES
# =============================================================================

@test "llm_parse_tool_call: handles special characters in args" {
    skip_if_no_jq
    local response='{"tool_calls":[{"id":"call_123","type":"function","function":{"name":"test","arguments":"{\"text\":\"hello\\nworld\"}"}}]}'
    result=$(llm_parse_tool_call "$response")
    [[ "$result" =~ '"name":"test"' ]]
}

@test "llm_parse_tool_call: handles unicode in args" {
    skip_if_no_jq
    local response='{"tool_calls":[{"id":"call_123","type":"function","function":{"name":"test","arguments":"{\"text\":\"caf\\u00e9\"}"}}]}'
    result=$(llm_parse_tool_call "$response")
    [[ "$result" =~ '"name":"test"' ]]
}

@test "llm_parse_tool_call: handles empty tool_calls array" {
    skip_if_no_jq
    local response='{"tool_calls":[]}'
    run llm_parse_tool_call "$response"
    [[ "$status" -eq 1 ]]
}

@test "llm_execute_tool: handles empty args" {
    llm_register_tool "echo" "test_echo_tool" '{"name":"echo"}'
    result=$(llm_execute_tool "echo" '{}')
    [[ $? -eq 0 ]]
}

@test "llm_format_tool_result: handles JSON result" {
    skip_if_no_jq
    local json_result='{"status":"ok","data":[1,2,3]}'
    result=$(llm_format_tool_result "$json_result" "call_123" "openai")
    [[ "$result" =~ "status" ]]
}

@test "llm_tools_to_openai: returns empty array when no tools" {
    skip_if_no_jq
    result=$(llm_tools_to_openai)
    [[ "$result" == "[]" ]]
}

@test "llm_tools_to_anthropic: returns empty array when no tools" {
    skip_if_no_jq
    result=$(llm_tools_to_anthropic)
    [[ "$result" == "[]" ]]
}

# =============================================================================
# CATEGORY 15: COMPLEX TOOL SCHEMAS
# =============================================================================

@test "llm_register_tool: handles complex nested schema" {
    local schema='{
        "name": "search",
        "description": "Search API",
        "parameters": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search query"},
                "filters": {
                    "type": "object",
                    "properties": {
                        "date_range": {
                            "type": "object",
                            "properties": {
                                "start": {"type": "string", "format": "date"},
                                "end": {"type": "string", "format": "date"}
                            }
                        },
                        "categories": {
                            "type": "array",
                            "items": {"type": "string"}
                        }
                    }
                },
                "limit": {"type": "integer", "minimum": 1, "maximum": 100}
            },
            "required": ["query"]
        }
    }'
    llm_register_tool "search" "test_echo_tool" "$schema"
    [[ $? -eq 0 ]]
    llm_tool_exists "search"
    [[ $? -eq 0 ]]
}

@test "llm_validate_tool_args: validates nested object args" {
    skip_if_no_jq
    local schema='{"parameters":{"type":"object","properties":{"user":{"type":"object","properties":{"name":{"type":"string"},"age":{"type":"integer"}}}}}}'
    local args='{"user":{"name":"John","age":30}}'
    llm_validate_tool_args "$schema" "$args"
    [[ $? -eq 0 ]]
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Skip test if jq is not available
skip_if_no_jq() {
    if ! command -v jq &>/dev/null; then
        skip "jq not available"
    fi
}

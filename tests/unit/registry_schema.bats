#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/registry_schema.bats - Registry Schema Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/registry_schema.sh
#              JSON Schema generation for LLM function calling
# Test Count: 30+ test cases
# Categories: OpenAI schemas, Anthropic schemas, OpenAPI, batch ops,
#             validation, utilities, error handling, edge cases
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Set FUNCTIONS.json path
    export MAINFRAME_FUNCTIONS_JSON="$MAINFRAME_ROOT/FUNCTIONS.json"

    # Source the library
    source "$MAINFRAME_ROOT/lib/json.sh"
    source "$MAINFRAME_ROOT/lib/registry_schema.sh"

    # Create a minimal test registry for isolated tests
    TEST_REGISTRY="$TEST_TMPDIR/test_functions.json"
    cat > "$TEST_REGISTRY" << 'EOF'
{
  "version": "1.0.0",
  "libraries": {
    "test_lib": {
      "file": "lib/test_lib.sh",
      "description": "Test library for unit tests",
      "functions": {
        "test_func": {
          "description": "A test function with parameters",
          "signature": "test_func NAME [OPTIONS]",
          "params": [
            {"name": "name", "position": 1, "required": true, "default": null},
            {"name": "timeout", "position": 2, "required": false, "default": "30"}
          ],
          "returns": "stdout"
        },
        "test_no_params": {
          "description": "A function with no parameters",
          "signature": "test_no_params",
          "params": [],
          "returns": "exit_code"
        },
        "test_optional": {
          "description": "Function with all optional parameters",
          "signature": "test_optional [A] [B]",
          "params": [
            {"name": "a", "position": 1, "required": false, "default": "default_a"},
            {"name": "b", "position": 2, "required": false, "default": "default_b"}
          ],
          "returns": "stdout"
        }
      }
    },
    "json_lib": {
      "file": "lib/json.sh",
      "description": "JSON manipulation library",
      "functions": {
        "json_object": {
          "description": "Create JSON object from key=value pairs",
          "signature": "json_object [key=value ...]",
          "params": [
            {"name": "pairs", "position": 1, "required": true, "default": null, "type": "array"}
          ],
          "returns": "stdout"
        }
      }
    }
  }
}
EOF
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# CATEGORY 1: OPENAI SCHEMA GENERATION
# =============================================================================

@test "registry_to_openai_schema: generates valid OpenAI schema structure" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_to_openai_schema "test_func")

    # Check top-level structure
    [[ $(jq -r '.type' <<< "$result") == "function" ]]
    [[ $(jq -r '.function.name' <<< "$result") == "test_func" ]]
    [[ $(jq -r '.function.parameters.type' <<< "$result") == "object" ]]
}

@test "registry_to_openai_schema: includes function description" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_to_openai_schema "test_func")
    desc=$(jq -r '.function.description' <<< "$result")

    [[ "$desc" == "A test function with parameters" ]]
}

@test "registry_to_openai_schema: generates properties for parameters" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_to_openai_schema "test_func")

    # Check that properties exist
    has_name=$(jq -r '.function.parameters.properties.name' <<< "$result")
    has_timeout=$(jq -r '.function.parameters.properties.timeout' <<< "$result")

    [[ "$has_name" != "null" ]]
    [[ "$has_timeout" != "null" ]]
}

@test "registry_to_openai_schema: marks required parameters correctly" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_to_openai_schema "test_func")
    required=$(jq -c '.function.parameters.required' <<< "$result")

    # 'name' is required (no default), 'timeout' is optional (has default)
    [[ "$required" == '["name"]' ]]
}

@test "registry_to_openai_schema: handles functions with no parameters" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_to_openai_schema "test_no_params")

    [[ $(jq -r '.function.name' <<< "$result") == "test_no_params" ]]
    [[ $(jq -c '.function.parameters.properties' <<< "$result") == "{}" ]]
    [[ $(jq -c '.function.parameters.required' <<< "$result") == "[]" ]]
}

@test "registry_to_openai_schema: returns error for nonexistent function" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    run registry_to_openai_schema "nonexistent_function"

    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "not found" ]]
}

@test "registry_to_openai_schema: returns error for empty function name" {
    run registry_to_openai_schema ""

    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "required" ]]
}

# =============================================================================
# CATEGORY 2: ANTHROPIC SCHEMA GENERATION
# =============================================================================

@test "registry_to_anthropic_schema: generates valid Anthropic schema structure" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_to_anthropic_schema "test_func")

    # Check Anthropic-specific structure
    [[ $(jq -r '.name' <<< "$result") == "test_func" ]]
    [[ $(jq -r '.input_schema.type' <<< "$result") == "object" ]]
    # Anthropic doesn't have .type: "function" wrapper
    [[ $(jq -r '.type' <<< "$result") == "null" ]]
}

@test "registry_to_anthropic_schema: includes description at top level" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_to_anthropic_schema "test_func")
    desc=$(jq -r '.description' <<< "$result")

    [[ "$desc" == "A test function with parameters" ]]
}

@test "registry_to_anthropic_schema: uses input_schema not parameters" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_to_anthropic_schema "test_func")

    # Must have input_schema
    [[ $(jq -r '.input_schema' <<< "$result") != "null" ]]
    # Must NOT have parameters
    [[ $(jq -r '.parameters' <<< "$result") == "null" ]]
}

@test "registry_to_anthropic_schema: marks required parameters correctly" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_to_anthropic_schema "test_func")
    required=$(jq -c '.input_schema.required' <<< "$result")

    [[ "$required" == '["name"]' ]]
}

@test "registry_to_anthropic_schema: handles all optional parameters" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_to_anthropic_schema "test_optional")
    required=$(jq -c '.input_schema.required' <<< "$result")

    [[ "$required" == "[]" ]]
}

# =============================================================================
# CATEGORY 3: OPENAPI GENERATION
# =============================================================================

@test "registry_to_openapi: generates valid OpenAPI 3.0 structure" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_to_openapi "lib/test_lib.sh")

    [[ $(jq -r '.openapi' <<< "$result") == "3.0.0" ]]
    [[ $(jq -r '.info.title' <<< "$result") =~ "test_lib" ]]
    [[ $(jq -r '.paths' <<< "$result") != "null" ]]
}

@test "registry_to_openapi: creates paths for each function" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_to_openapi "lib/test_lib.sh")

    # Should have path for each function
    [[ $(jq -r '.paths["/test_func"]' <<< "$result") != "null" ]]
    [[ $(jq -r '.paths["/test_no_params"]' <<< "$result") != "null" ]]
}

@test "registry_to_openapi: returns error for nonexistent library" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    run registry_to_openapi "lib/nonexistent.sh"

    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "not found" ]]
}

# =============================================================================
# CATEGORY 4: BATCH OPERATIONS
# =============================================================================

@test "registry_export_schemas: exports all functions to file" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    local output_file="$TEST_TMPDIR/exported.json"

    run registry_export_schemas "$output_file" "openai"

    [[ "$status" -eq 0 ]]
    [[ -f "$output_file" ]]

    # Should have exported 4 functions
    count=$(jq 'length' "$output_file")
    [[ "$count" -eq 4 ]]
}

@test "registry_export_schemas: supports anthropic format" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    local output_file="$TEST_TMPDIR/anthropic.json"

    run registry_export_schemas "$output_file" "anthropic"

    [[ "$status" -eq 0 ]]

    # Verify Anthropic format (has input_schema)
    has_input_schema=$(jq '.[0].input_schema' "$output_file")
    [[ "$has_input_schema" != "null" ]]
}

@test "registry_schema_batch: filters functions by pattern" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_schema_batch "test_*")

    # Should match test_func, test_no_params, test_optional (3 functions)
    count=$(jq 'length' <<< "$result")
    [[ "$count" -eq 3 ]]
}

@test "registry_schema_batch: returns empty array for no matches" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_schema_batch "nonexistent_*")

    [[ "$result" == "[]" ]]
}

@test "registry_schema_batch: supports anthropic format" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_schema_batch "json_*" "anthropic")

    # Should match json_object
    count=$(jq 'length' <<< "$result")
    [[ "$count" -eq 1 ]]

    # Verify Anthropic format
    [[ $(jq -r '.[0].input_schema' <<< "$result") != "null" ]]
}

# =============================================================================
# CATEGORY 5: SCHEMA VALIDATION
# =============================================================================

@test "registry_validate_schema: validates correct OpenAI schema" {
    local schema_file="$TEST_TMPDIR/valid_openai.json"
    cat > "$schema_file" << 'EOF'
{
  "type": "function",
  "function": {
    "name": "test_func",
    "description": "A test function",
    "parameters": {
      "type": "object",
      "properties": {},
      "required": []
    }
  }
}
EOF

    run registry_validate_schema "$schema_file"

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ '"valid":true' ]]
    [[ "$output" =~ '"format":"openai"' ]]
}

@test "registry_validate_schema: validates correct Anthropic schema" {
    local schema_file="$TEST_TMPDIR/valid_anthropic.json"
    cat > "$schema_file" << 'EOF'
{
  "name": "test_func",
  "description": "A test function",
  "input_schema": {
    "type": "object",
    "properties": {},
    "required": []
  }
}
EOF

    run registry_validate_schema "$schema_file"

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ '"valid":true' ]]
    [[ "$output" =~ '"format":"anthropic"' ]]
}

@test "registry_validate_schema: detects missing name field" {
    local schema_file="$TEST_TMPDIR/invalid.json"
    cat > "$schema_file" << 'EOF'
{
  "type": "function",
  "function": {
    "description": "Missing name",
    "parameters": {"type": "object"}
  }
}
EOF

    run registry_validate_schema "$schema_file"

    [[ "$status" -eq 1 ]]
    [[ "$output" =~ '"valid":false' ]]
    [[ "$output" =~ "name" ]]
}

@test "registry_validate_schema: detects invalid JSON" {
    local schema_file="$TEST_TMPDIR/bad_json.json"
    echo "{ invalid json" > "$schema_file"

    run registry_validate_schema "$schema_file"

    [[ "$status" -eq 1 ]]
    [[ "$output" =~ '"valid":false' ]]
    [[ "$output" =~ "Invalid JSON" ]]
}

@test "registry_validate_schema: validates array of schemas" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    local schema_file="$TEST_TMPDIR/array.json"
    registry_export_schemas "$schema_file" "openai"

    run registry_validate_schema "$schema_file"

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ '"valid":true' ]]
}

# =============================================================================
# CATEGORY 6: UTILITY FUNCTIONS
# =============================================================================

@test "registry_list_functions: lists all functions" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_list_functions)

    [[ "$result" =~ "test_func" ]]
    [[ "$result" =~ "test_no_params" ]]
    [[ "$result" =~ "json_object" ]]
}

@test "registry_list_functions: filters by library" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_list_functions "test_lib")

    [[ "$result" =~ "test_func" ]]
    [[ ! "$result" =~ "json_object" ]]
}

@test "registry_list_libraries: lists all libraries" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_list_libraries)

    [[ "$result" =~ "test_lib" ]]
    [[ "$result" =~ "json_lib" ]]
}

@test "registry_function_count: returns total function count" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_function_count)

    [[ "$result" -eq 4 ]]
}

@test "registry_function_count: returns count for specific library" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_function_count "test_lib")

    [[ "$result" -eq 3 ]]
}

@test "registry_search: finds functions by keyword" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_search "optional")

    [[ "$result" =~ "test_optional" ]]
}

@test "registry_function_info: returns detailed function metadata" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_function_info "test_func")

    [[ $(jq -r '.description' <<< "$result") == "A test function with parameters" ]]
    [[ $(jq -r '.signature' <<< "$result") == "test_func NAME [OPTIONS]" ]]
}

@test "registry_cache_clear: clears the cache" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"

    # First call loads cache
    registry_list_functions > /dev/null

    # Clear cache
    registry_cache_clear

    # Verify internal state
    [[ -z "$_REGISTRY_SCHEMA_CACHE" ]]
    [[ "$_REGISTRY_SCHEMA_CACHE_TIME" -eq 0 ]]
}

# =============================================================================
# CATEGORY 7: EDGE CASES AND ERROR HANDLING
# =============================================================================

@test "handles missing FUNCTIONS.json gracefully" {
    export MAINFRAME_FUNCTIONS_JSON="/nonexistent/path/FUNCTIONS.json"
    registry_cache_clear

    run registry_to_openai_schema "test_func"

    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "not found" ]]
}

@test "handles special characters in description" {
    local special_registry="$TEST_TMPDIR/special.json"
    cat > "$special_registry" << 'EOF'
{
  "version": "1.0.0",
  "libraries": {
    "special": {
      "file": "lib/special.sh",
      "description": "Special \"quoted\" and\nnewline chars",
      "functions": {
        "special_func": {
          "description": "Function with \"quotes\" and tab\there",
          "signature": "special_func",
          "params": [],
          "returns": "stdout"
        }
      }
    }
  }
}
EOF

    export MAINFRAME_FUNCTIONS_JSON="$special_registry"
    registry_cache_clear

    result=$(registry_to_openai_schema "special_func")

    # Should produce valid JSON
    jq empty <<< "$result"
    [[ $? -eq 0 ]]

    # Function name should be correct
    [[ $(jq -r '.function.name' <<< "$result") == "special_func" ]]
}

@test "handles functions with array type parameters" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_to_openai_schema "json_object")

    # Should have array type for pairs parameter
    pairs_type=$(jq -r '.function.parameters.properties.pairs.type' <<< "$result")
    [[ "$pairs_type" == "array" ]]
}

# =============================================================================
# CATEGORY 8: INTEGRATION WITH REAL FUNCTIONS.JSON
# =============================================================================

@test "works with real FUNCTIONS.json if available" {
    # Use the actual FUNCTIONS.json
    export MAINFRAME_FUNCTIONS_JSON="$MAINFRAME_ROOT/FUNCTIONS.json"
    registry_cache_clear

    # Skip if FUNCTIONS.json doesn't exist
    if [[ ! -f "$MAINFRAME_FUNCTIONS_JSON" ]]; then
        skip "FUNCTIONS.json not found"
    fi

    # Try to get a schema for a known function
    result=$(registry_to_openai_schema "json_object" 2>/dev/null || echo "")

    if [[ -n "$result" && "$result" != *"error"* ]]; then
        [[ $(jq -r '.function.name' <<< "$result") == "json_object" ]]
    else
        skip "json_object function not found in FUNCTIONS.json"
    fi
}

@test "real registry has expected structure" {
    export MAINFRAME_FUNCTIONS_JSON="$MAINFRAME_ROOT/FUNCTIONS.json"
    registry_cache_clear

    if [[ ! -f "$MAINFRAME_FUNCTIONS_JSON" ]]; then
        skip "FUNCTIONS.json not found"
    fi

    # Verify we can list functions
    result=$(registry_list_functions)
    count=$(echo "$result" | wc -l)

    # Should have at least some functions
    [[ "$count" -gt 10 ]]
}

# =============================================================================
# CATEGORY 9: USOP COMPLIANCE (OUTPUT FORMAT)
# =============================================================================

@test "schema output is valid JSON" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_to_openai_schema "test_func")

    # Must be valid JSON
    run jq empty <<< "$result"
    [[ "$status" -eq 0 ]]
}

@test "batch output is valid JSON array" {
    export MAINFRAME_FUNCTIONS_JSON="$TEST_REGISTRY"
    registry_cache_clear

    result=$(registry_schema_batch "test_*")

    # Must be valid JSON array
    run jq 'type' <<< "$result"
    [[ "$output" == '"array"' ]]
}

@test "validation output follows USOP format" {
    local schema_file="$TEST_TMPDIR/test.json"
    echo '{"name":"test","input_schema":{"type":"object"}}' > "$schema_file"

    result=$(registry_validate_schema "$schema_file")

    # Should have 'valid' field
    [[ $(jq -r '.valid' <<< "$result") == "true" ]]
}

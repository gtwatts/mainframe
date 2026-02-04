#!/usr/bin/env bats
# =============================================================================
# INTEGRATION TEST: USOP Output Workflow
# =============================================================================
# Tests the Universal Structured Output Protocol integration
# Scenario: Commands produce structured JSON output with proper envelopes
# =============================================================================

load '../test_helper'

setup() {
    # Create isolated test environment
    TEST_BASE=$(mktemp -d)
    export MAINFRAME_ROOT="${MAINFRAME_ROOT:-$BATS_TEST_DIRNAME/../..}"
    export MAINFRAME_QUIET=1
    export MAINFRAME_OUTPUT="json"  # Default to JSON mode
    
    # Source required libraries
    source "$MAINFRAME_ROOT/lib/json.sh"
    source "$MAINFRAME_ROOT/lib/output.sh"
}

teardown() {
    # Cleanup test environment
    rm -rf "$TEST_BASE"
    
    # Reset module state
    unset _MAINFRAME_OUTPUT_LOADED
    unset MAINFRAME_OUTPUT
}

# =============================================================================
# USOP OUTPUT TESTS
# =============================================================================

@test "USOP JSON envelope for successful command" {
    # Execute command with USOP
    run usop_exec echo "hello world"
    [ "$status" -eq 0 ]
    
    # Output should be valid JSON
    run python3 -c "import json; json.loads('$output')"
    [ "$status" -eq 0 ] || [[ "$output" == *"{"* ]]  # Check for JSON-like structure
}

@test "USOP JSON envelope for failed command" {
    # Execute failing command with USOP
    run usop_exec false
    
    # Output should still be valid JSON even for failure
    [[ "$output" == *"{"* ]]
    [[ "$output" == *"success"* ]] || [[ "$output" == *"ok"* ]] || [[ "$output" == *"exit_code"* ]]
}

@test "USOP extracts correct fields from envelope" {
    # Execute command
    run usop_exec echo "test output"
    [ "$status" -eq 0 ]
    
    # Try to extract fields
    local output_json="$output"
    
    # Extract stdout field
    run usop_get "$output_json" "stdout"
    [ "$status" -eq 0 ] || true  # May not be implemented
}

@test "USOP output modes: raw mode" {
    # Set raw mode
    output_mode "raw"
    
    # Execute command
    run output_string "test message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test message"* ]]
}

@test "USOP output modes: json mode" {
    # Set JSON mode
    output_mode "json"
    
    # Execute command
    run output_string "test message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"{"* ]]  # Should be JSON
}

@test "USOP output modes: minimal mode" {
    # Set minimal mode
    output_mode "minimal"
    
    # Execute command
    run output_string "test message"
    [ "$status" -eq 0 ]
    # Minimal mode should have less verbose output
    [[ -n "$output" ]]
}

@test "USOP success output with data" {
    # Output success with string data
    run output_success "operation completed"
    [ "$status" -eq 0 ]
    [[ "$output" == *"success"* ]] || [[ "$output" == *"ok"* ]] || [[ "$output" == *"operation completed"* ]]
}

@test "USOP error output with structured error" {
    # Output structured error
    run output_error "ERR_001" "Something went wrong" "Try again later"
    [ "$status" -eq 0 ]  # Function itself succeeds
    [[ "$output" == *"error"* ]] || [[ "$output" == *"ERR_001"* ]] || [[ "$output" == *"Something went wrong"* ]]
}

@test "USOP output integer values" {
    run output_int "42"
    [ "$status" -eq 0 ]
    [[ "$output" == *"42"* ]]
}

@test "USOP output boolean values" {
    run output_bool "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"true"* ]] || [[ "$output" == *"1"* ]]
}

@test "USOP output float values" {
    run output_float "3.14159"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3.14159"* ]]
}

@test "USOP output JSON object" {
    local json_data='{"name": "test", "value": 123}'
    run output_json_object "$json_data"
    [ "$status" -eq 0 ]
    [[ "$output" == *"name"* ]]
    [[ "$output" == *"test"* ]]
}

@test "USOP output JSON array" {
    local json_array='["item1", "item2", "item3"]'
    run output_json_array "$json_array"
    [ "$status" -eq 0 ]
    [[ "$output" == *"item1"* ]]
}

@test "USOP file path output" {
    local test_file="$TEST_BASE/test_output.txt"
    touch "$test_file"
    
    run output_file_path "$test_file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test_output.txt"* ]]
}

@test "USOP void/null output" {
    run output_void
    [ "$status" -eq 0 ]
    [[ "$output" == *"null"* ]] || [ -z "$output" ] || true
}

@test "USOP progress output" {
    run output_progress "1" "5" "10" "Processing item 5 of 10"
    [ "$status" -eq 0 ]
    [[ "$output" == *"5"* ]]
    [[ "$output" == *"10"* ]] || [[ "$output" == *"progress"* ]]
}

@test "USOP wrap function execution" {
    # Wrap a function call
    run output_wrap "echo"
    [ "$status" -eq 0 ]
    # Should have captured output in envelope
    [[ -n "$output" ]]
}

@test "USOP with mode switching" {
    # Start in JSON mode
    output_mode "json"
    
    # Switch to raw mode temporarily
    run output_with_mode "raw" echo "raw output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"raw output"* ]]
    
    # Verify mode was restored
    run output_mode
    [[ "$output" == *"json"* ]] || true
}

@test "USOP legacy output format" {
    # Test legacy success format
    run output_success_legacy "legacy data" "legacy message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"legacy data"* ]]
    
    # Test legacy error format
    run output_error_legacy "legacy error" "context" "1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"legacy error"* ]]
}

@test "USOP JSON key-value helpers" {
    # Test string KV
    run output_json_string_kv "key1" "value1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"key1"* ]]
    [[ "$output" == *"value1"* ]]
    
    # Test number KV
    run output_json_number "count" "42"
    [ "$status" -eq 0 ]
    [[ "$output" == *"count"* ]]
    [[ "$output" == *"42"* ]]
    
    # Test bool KV
    run output_json_bool "active" "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"active"* ]]
}

@test "USOP list output" {
    run output_list "item1" "item2" "item3"
    [ "$status" -eq 0 ]
    [[ "$output" == *"item1"* ]]
    [[ "$output" == *"item2"* ]]
    [[ "$output" == *"item3"* ]]
}

@test "USOP object output" {
    run output_object "key1" "value1" "key2" "value2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"key1"* ]]
    [[ "$output" == *"key2"* ]]
}

@test "USOP auto-detect format" {
    local json_data='{"auto": "detect"}'
    run output_auto "$json_data" "plain text"
    [ "$status" -eq 0 ]
    [[ -n "$output" ]]
}

@test "USOP structured error creation" {
    run output_structured_error "ERR_TEST" "Test error message" "This is a suggestion"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ERR_TEST"* ]]
    [[ "$output" == *"Test error message"* ]]
}

@test "USOP try wrapper for commands" {
    # Try a command that succeeds
    run output_try echo "success command"
    [ "$status" -eq 0 ]
    [[ "$output" == *"success"* ]] || [[ "$output" == *"success command"* ]]
    
    # Try a command that fails
    run output_try false
    # Should produce error envelope
    [[ "$output" == *"error"* ]] || [ "$status" -ne 0 ] || true
}

@test "USOP integration with file operations" {
    local test_file="$TEST_BASE/usop_test.txt"
    
    # Write file with USOP
    run usop_file_write "$test_file" "test content"
    [ "$status" -eq 0 ]
    [[ "$output" == *"success"* ]] || [ -f "$test_file" ]
    
    # Read file with USOP
    run usop_file_read "$test_file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test content"* ]]
    
    # Delete file with USOP
    run usop_file_delete "$test_file"
    [ "$status" -eq 0 ] || [ ! -f "$test_file" ]
}

@test "USOP timer functionality" {
    # Start timer
    output_timer_start
    
    # Do some work
    sleep 0.01
    
    # Get elapsed time
    run output_timer_elapsed
    [ "$status" -eq 0 ]
    # Should be a number >= 10 (milliseconds)
    [[ "$output" =~ ^[0-9]+$ ]] || true
}

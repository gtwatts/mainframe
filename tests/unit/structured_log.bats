#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/structured_log.bats - Structured Logging Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/structured_log.sh
#              JSON-structured logging for observability
# Test Count: 35+ test cases
# Categories: initialization, log levels, context, buffering, rotation,
#             output destinations, caller detection, JSON format, utilities
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"
    TEST_LOG_FILE="${TEST_TMPDIR}/test.jsonl"

    # Source the library
    source "$MAINFRAME_ROOT/lib/structured_log.sh"

    # Reset state for each test
    _SLOG_OUTPUT="stderr"
    _SLOG_LEVEL="$SLOG_LEVEL_INFO"
    _SLOG_CONTEXT=""
    _SLOG_BUFFER=""
    _SLOG_BUFFER_COUNT=0
    _SLOG_BUFFER_MAX=1  # Disable buffering by default for tests
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# CATEGORY 1: INITIALIZATION
# =============================================================================

@test "slog_init: sets output destination" {
    slog_init --output "$TEST_LOG_FILE"
    [[ "$_SLOG_OUTPUT" == "$TEST_LOG_FILE" ]]
}

@test "slog_init: sets log level" {
    slog_init --level "DEBUG"
    [[ "$_SLOG_LEVEL" -eq "$SLOG_LEVEL_DEBUG" ]]
}

@test "slog_init: sets buffer size" {
    slog_init --buffer-size 20
    [[ "$_SLOG_BUFFER_MAX" -eq 20 ]]
}

@test "slog_init: clears existing context" {
    _SLOG_CONTEXT="old=context"
    slog_init --output "$TEST_LOG_FILE"
    [[ -z "$_SLOG_CONTEXT" ]]
}

@test "slog_init: accepts multiple options" {
    slog_init --output "$TEST_LOG_FILE" --level "WARN" --buffer-size 5
    [[ "$_SLOG_OUTPUT" == "$TEST_LOG_FILE" ]]
    [[ "$_SLOG_LEVEL" -eq "$SLOG_LEVEL_WARN" ]]
    [[ "$_SLOG_BUFFER_MAX" -eq 5 ]]
}

# =============================================================================
# CATEGORY 2: LOG LEVEL FUNCTIONS
# =============================================================================

@test "slog_debug: outputs DEBUG level log" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_debug "Debug message"
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"level":"DEBUG"' ]]
    [[ "$content" =~ '"message":"Debug message"' ]]
}

@test "slog_info: outputs INFO level log" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info "Info message"
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"level":"INFO"' ]]
    [[ "$content" =~ '"message":"Info message"' ]]
}

@test "slog_warn: outputs WARN level log" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_warn "Warning message"
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"level":"WARN"' ]]
    [[ "$content" =~ '"message":"Warning message"' ]]
}

@test "slog_error: outputs ERROR level log" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_error "Error message"
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"level":"ERROR"' ]]
    [[ "$content" =~ '"message":"Error message"' ]]
}

@test "slog_debug: filtered when level is INFO" {
    slog_init --output "$TEST_LOG_FILE" --level "INFO"
    slog_debug "Should not appear"
    slog_flush

    [[ ! -f "$TEST_LOG_FILE" ]] || [[ ! -s "$TEST_LOG_FILE" ]]
}

@test "slog_info: filtered when level is WARN" {
    slog_init --output "$TEST_LOG_FILE" --level "WARN"
    slog_info "Should not appear"
    slog_flush

    [[ ! -f "$TEST_LOG_FILE" ]] || [[ ! -s "$TEST_LOG_FILE" ]]
}

@test "slog_error: passes when level is WARN" {
    slog_init --output "$TEST_LOG_FILE" --level "WARN"
    slog_error "Should appear"
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"level":"ERROR"' ]]
}

# =============================================================================
# CATEGORY 3: KEY-VALUE FIELDS
# =============================================================================

@test "slog_info: includes string key-value pair" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info "Test message" status="running"
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"status":"running"' ]]
}

@test "slog_info: includes numeric key-value pair" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info "Test message" duration_ms=150
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"duration_ms":150' ]]
}

@test "slog_info: includes boolean key-value pair" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info "Test message" success=true
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"success":true' ]]
}

@test "slog_info: includes multiple key-value pairs" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info "Test message" task_id="abc123" count=5 active=true
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"task_id":"abc123"' ]]
    [[ "$content" =~ '"count":5' ]]
    [[ "$content" =~ '"active":true' ]]
}

@test "slog_info: explicit number type" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info "Test" value:number=42
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"value":42' ]]
}

@test "slog_info: explicit bool type" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info "Test" flag:bool=yes
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"flag":true' ]]
}

# =============================================================================
# CATEGORY 4: PERSISTENT CONTEXT
# =============================================================================

@test "slog_with_context: adds context to logs" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_with_context service="agent"
    slog_info "Test message"
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"service":"agent"' ]]
}

@test "slog_with_context: adds multiple context fields" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_with_context service="agent" version="1.0" env="prod"
    slog_info "Test message"
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"service":"agent"' ]]
    [[ "$content" =~ '"version":"1.0"' ]]
    [[ "$content" =~ '"env":"prod"' ]]
}

@test "slog_with_context: accumulates context across calls" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_with_context service="agent"
    slog_with_context version="2.0"
    slog_info "Test message"
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"service":"agent"' ]]
    [[ "$content" =~ '"version":"2.0"' ]]
}

@test "slog_clear_context: removes all context" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_with_context service="agent"
    slog_clear_context
    slog_info "Test message"
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ ! "$content" =~ '"service":"agent"' ]]
}

# =============================================================================
# CATEGORY 5: JSON FORMAT
# =============================================================================

@test "log entry: includes timestamp" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info "Test"
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    # Check timestamp format: ISO 8601 with milliseconds
    [[ "$content" =~ '"timestamp":"20' ]]
    [[ "$content" =~ 'T' ]]
    [[ "$content" =~ 'Z"' ]]
}

@test "log entry: includes caller info" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info "Test"
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"caller":"' ]]
}

@test "log entry: is valid JSON" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info "Test message" key="value"
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    # Check basic JSON structure
    [[ "$content" =~ ^\{ ]]
    [[ "$content" =~ \}$ ]]
}

@test "log entry: escapes special characters in message" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info 'Message with "quotes" and
newline'
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '\\"quotes\\"' ]]
    [[ "$content" =~ '\\n' ]]
}

@test "log entry: escapes special characters in values" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info "Test" path='C:\Users\test'
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '\\\\' ]]
}

# =============================================================================
# CATEGORY 6: OUTPUT DESTINATIONS
# =============================================================================

@test "slog_set_output: changes output destination" {
    slog_init --output "stderr"
    slog_set_output "$TEST_LOG_FILE"
    [[ "$_SLOG_OUTPUT" == "$TEST_LOG_FILE" ]]
}

@test "slog_set_output: accepts stderr" {
    slog_set_output "stderr"
    [[ "$_SLOG_OUTPUT" == "stderr" ]]
}

@test "slog_set_output: accepts stdout" {
    slog_set_output "stdout"
    [[ "$_SLOG_OUTPUT" == "stdout" ]]
}

@test "slog_set_output: rejects invalid directory" {
    run slog_set_output "/nonexistent/path/log.jsonl"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 7: BUFFERING
# =============================================================================

@test "slog_flush: writes buffered entries" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG" --buffer-size 10
    slog_info "Message 1"
    slog_info "Message 2"

    # Before flush, file should not exist or be empty
    [[ ! -f "$TEST_LOG_FILE" ]] || [[ ! -s "$TEST_LOG_FILE" ]]

    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ "Message 1" ]]
    [[ "$content" =~ "Message 2" ]]
}

@test "buffer: auto-flushes when full" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG" --buffer-size 2
    slog_info "Message 1"
    slog_info "Message 2"  # This should trigger auto-flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ "Message 1" ]]
    [[ "$content" =~ "Message 2" ]]
}

# =============================================================================
# CATEGORY 8: LOG ROTATION
# =============================================================================

@test "slog_rotate: creates rotated file" {
    slog_init --output "$TEST_LOG_FILE" --rotate-size 50

    # Write enough to exceed rotation size
    slog_info "This is a test message that should be long enough"
    slog_flush

    slog_rotate

    # Original file should be moved to .1
    [[ -f "${TEST_LOG_FILE}.1" ]]
}

@test "slog_rotate: shifts existing rotated files" {
    slog_init --output "$TEST_LOG_FILE" --rotate-size 50

    # Create initial rotated files
    echo "old1" > "${TEST_LOG_FILE}.1"
    echo "old2" > "${TEST_LOG_FILE}.2"

    # Write and rotate
    slog_info "New content that is long enough to trigger rotation"
    slog_flush
    slog_rotate

    # Check rotation happened
    [[ -f "${TEST_LOG_FILE}.1" ]]
    local content=$(<"${TEST_LOG_FILE}.1")
    [[ "$content" =~ "New content" ]]

    # Old .1 should be moved to .2
    local old1=$(<"${TEST_LOG_FILE}.2")
    [[ "$old1" == "old1" ]]
}

# =============================================================================
# CATEGORY 9: UTILITY FUNCTIONS
# =============================================================================

@test "slog_set_level: changes log level" {
    slog_set_level "ERROR"
    [[ "$_SLOG_LEVEL" -eq "$SLOG_LEVEL_ERROR" ]]
}

@test "slog_get_level: returns current level name" {
    slog_set_level "WARN"
    result=$(slog_get_level)
    [[ "$result" == "WARN" ]]
}

@test "slog_get_output: returns current output" {
    slog_set_output "$TEST_LOG_FILE"
    result=$(slog_get_output)
    [[ "$result" == "$TEST_LOG_FILE" ]]
}

@test "slog_would_log: returns true for loggable level" {
    slog_set_level "INFO"
    slog_would_log "ERROR"
    [[ $? -eq 0 ]]
}

@test "slog_would_log: returns false for filtered level" {
    slog_set_level "ERROR"
    ! slog_would_log "DEBUG"
}

@test "slog_stats: returns JSON statistics" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG" --buffer-size 5
    slog_with_context service="test"

    result=$(slog_stats)
    [[ "$result" =~ '"buffer_max":5' ]]
    [[ "$result" =~ '"level":"DEBUG"' ]]
    [[ "$result" =~ '"context_set":true' ]]
}

# =============================================================================
# CATEGORY 10: NAMEREF VARIANTS
# =============================================================================

@test "slog_build_v: builds log entry into variable" {
    local out
    slog_build_v out "INFO" "Test message" key="value"

    [[ "$out" =~ '"level":"INFO"' ]]
    [[ "$out" =~ '"message":"Test message"' ]]
    [[ "$out" =~ '"key":"value"' ]]
}

@test "slog_build_v: includes timestamp" {
    local out
    slog_build_v out "INFO" "Test"

    [[ "$out" =~ '"timestamp":"' ]]
}

@test "slog_build_v: includes caller" {
    local out
    slog_build_v out "INFO" "Test"

    [[ "$out" =~ '"caller":"' ]]
}

# =============================================================================
# CATEGORY 11: EDGE CASES
# =============================================================================

@test "slog_info: handles empty message" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info ""
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"message":""' ]]
}

@test "slog_info: handles message with only special chars" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info '"\\\n\t'
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ -n "$content" ]]
}

@test "slog_info: handles very long message" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    local long_message
    long_message=$(printf 'x%.0s' {1..1000})
    slog_info "$long_message"
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ "xxxx" ]]
}

@test "slog_info: handles value with equals sign" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info "Test" formula="a=b+c"
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"formula":"a=b\+c"' ]] || [[ "$content" =~ '"formula":"a=b+c"' ]]
}

@test "log level names: case insensitive" {
    slog_set_level "debug"
    [[ "$_SLOG_LEVEL" -eq "$SLOG_LEVEL_DEBUG" ]]

    slog_set_level "DEBUG"
    [[ "$_SLOG_LEVEL" -eq "$SLOG_LEVEL_DEBUG" ]]

    slog_set_level "Debug"
    [[ "$_SLOG_LEVEL" -eq "$SLOG_LEVEL_DEBUG" ]]
}

@test "slog_set_level: handles WARNING alias" {
    slog_set_level "WARNING"
    [[ "$_SLOG_LEVEL" -eq "$SLOG_LEVEL_WARN" ]]
}

# =============================================================================
# CATEGORY 12: DUAL OUTPUT (both:)
# =============================================================================

@test "slog_set_output: accepts both: prefix" {
    slog_set_output "both:$TEST_LOG_FILE"
    [[ "$_SLOG_OUTPUT" == "both:$TEST_LOG_FILE" ]]
}

@test "both output: writes to file" {
    slog_init --output "both:$TEST_LOG_FILE" --level "DEBUG"
    slog_info "Dual output test" 2>/dev/null
    slog_flush 2>/dev/null

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ "Dual output test" ]]
}

# =============================================================================
# CATEGORY 13: TYPE COERCION
# =============================================================================

@test "slog_info: null value auto-detected" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info "Test" value=null
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"value":null' ]]
}

@test "slog_info: false boolean auto-detected" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info "Test" active=false
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"active":false' ]]
}

@test "slog_info: negative number auto-detected" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info "Test" delta=-42
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"delta":-42' ]]
}

@test "slog_info: float number auto-detected" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info "Test" rate=3.14
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"rate":3.14' ]]
}

@test "slog_info: scientific notation auto-detected" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_info "Test" large=1.5e10
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"large":1.5e10' ]]
}

# =============================================================================
# CATEGORY 14: BUFFER EDGE CASES
# =============================================================================

@test "slog_flush: handles empty buffer" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG" --buffer-size 10
    # Flush without writing anything
    slog_flush

    # Should not create file or error
    [[ ! -f "$TEST_LOG_FILE" ]] || [[ ! -s "$TEST_LOG_FILE" ]]
}

@test "buffer size 1: writes immediately" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG" --buffer-size 1
    slog_info "Immediate write"

    # File should exist immediately without explicit flush
    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ "Immediate write" ]]
}

# =============================================================================
# CATEGORY 15: ROTATION EDGE CASES
# =============================================================================

@test "slog_rotate: no-op for stderr" {
    slog_init --output "stderr"
    run slog_rotate
    [[ "$status" -eq 0 ]]
}

@test "slog_rotate: no-op for stdout" {
    slog_init --output "stdout"
    run slog_rotate
    [[ "$status" -eq 0 ]]
}

@test "slog_rotate: no-op for nonexistent file" {
    slog_init --output "${TEST_TMPDIR}/nonexistent.jsonl"
    run slog_rotate
    [[ "$status" -eq 0 ]]
}

# =============================================================================
# CATEGORY 16: CONTEXT EDGE CASES
# =============================================================================

@test "slog_with_context: handles value with quotes" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_with_context query='SELECT * FROM "users"'
    slog_info "Test"
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"query":' ]]
}

@test "slog_with_context: skips malformed pairs" {
    slog_init --output "$TEST_LOG_FILE" --level "DEBUG"
    slog_with_context valid="ok" malformed_no_equals
    slog_info "Test"
    slog_flush

    local content=$(<"$TEST_LOG_FILE")
    [[ "$content" =~ '"valid":"ok"' ]]
}

# =============================================================================
# CATEGORY 17: LEVEL CONSTANTS
# =============================================================================

@test "log level constants: correct values" {
    [[ "$SLOG_LEVEL_DEBUG" -eq 10 ]]
    [[ "$SLOG_LEVEL_INFO" -eq 20 ]]
    [[ "$SLOG_LEVEL_WARN" -eq 30 ]]
    [[ "$SLOG_LEVEL_ERROR" -eq 40 ]]
    [[ "$SLOG_LEVEL_FATAL" -eq 50 ]]
}

@test "log levels: correct ordering" {
    [[ "$SLOG_LEVEL_DEBUG" -lt "$SLOG_LEVEL_INFO" ]]
    [[ "$SLOG_LEVEL_INFO" -lt "$SLOG_LEVEL_WARN" ]]
    [[ "$SLOG_LEVEL_WARN" -lt "$SLOG_LEVEL_ERROR" ]]
    [[ "$SLOG_LEVEL_ERROR" -lt "$SLOG_LEVEL_FATAL" ]]
}

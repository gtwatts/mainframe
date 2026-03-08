#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/otel.bats - OpenTelemetry Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/otel.sh
#              OpenTelemetry-compatible distributed tracing
# Test Count: 45+ test cases
# Categories: initialization, trace operations, span attributes, events,
#             context propagation, W3C trace context, export, convenience
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"
    export OTEL_SPAN_DIR="$TEST_TMPDIR/spans"
    export OTEL_EXPORT_FILE="$TEST_TMPDIR/traces.jsonl"

    # Disable actual exports in tests
    export OTEL_EXPORTER_ENDPOINT="http://localhost:65535"

    # Source the library
    MAINFRAME_LIBS="core" source "$MAINFRAME_ROOT/lib/common.sh"
    source "$MAINFRAME_ROOT/lib/otel.sh"

    # Reset state between tests
    _OTEL_SPAN_STACK=()
    _OTEL_CTX=([trace_id]="" [span_id]="" [parent_span_id]="" [flags]="01" [tracestate]="")
    _OTEL_INITIALIZED=0
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# CATEGORY 1: INITIALIZATION
# =============================================================================

@test "otel_init: initializes with default values" {
    otel_init
    [[ "$_OTEL_INITIALIZED" == "1" ]]
}

@test "otel_init: accepts --service parameter" {
    otel_init --service "test-service"
    [[ "$OTEL_SERVICE_NAME" == "test-service" ]]
}

@test "otel_init: accepts --endpoint parameter" {
    otel_init --endpoint "http://collector:4318"
    [[ "$OTEL_EXPORTER_ENDPOINT" == "http://collector:4318" ]]
}

@test "otel_init: accepts --sample-rate parameter" {
    otel_init --sample-rate "0.5"
    [[ "$OTEL_SAMPLE_RATE" == "0.5" ]]
}

@test "otel_init: creates span directory" {
    otel_init
    [[ -d "$OTEL_SPAN_DIR" ]]
}

@test "otel_init: accepts multiple parameters" {
    otel_init --service "multi-test" --endpoint "http://test:1234" --sample-rate "0.75"
    [[ "$OTEL_SERVICE_NAME" == "multi-test" ]]
    [[ "$OTEL_EXPORTER_ENDPOINT" == "http://test:1234" ]]
    [[ "$OTEL_SAMPLE_RATE" == "0.75" ]]
}

# =============================================================================
# CATEGORY 2: TRACE OPERATIONS
# =============================================================================

@test "otel_trace_start: returns span ID" {
    otel_init
    local span_id
    span_id=$(otel_trace_start "test-operation")
    [[ -n "$span_id" ]]
    [[ ${#span_id} -eq 16 ]]
}

@test "otel_trace_start: creates span file" {
    otel_init
    local span_id
    span_id=$(otel_trace_start "test-operation")

    local trace_id
    trace_id=$(otel_trace_id)
    [[ -f "$OTEL_SPAN_DIR/${trace_id}_${span_id}.span" ]]
}

@test "otel_trace_start: generates valid trace ID" {
    otel_init
    otel_trace_start "test"
    local trace_id="${_OTEL_CTX[trace_id]}"

    [[ ${#trace_id} -eq 32 ]]
    [[ "$trace_id" =~ ^[0-9a-f]+$ ]]
}

@test "otel_trace_start: span file contains correct name" {
    otel_init
    local span_id
    span_id=$(otel_trace_start "my-operation")

    local trace_id
    trace_id=$(otel_trace_id)
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    grep -q '"name": "my-operation"' "$span_file"
}

@test "otel_trace_start: nested spans maintain trace ID" {
    otel_init
    otel_trace_start "parent"
    local parent_trace_id="${_OTEL_CTX[trace_id]}"

    otel_trace_start "child"
    local child_trace_id="${_OTEL_CTX[trace_id]}"

    [[ "$parent_trace_id" == "$child_trace_id" ]]
}

@test "otel_trace_start: nested spans set parent span ID" {
    otel_init
    local parent_span_id
    parent_span_id=$(otel_trace_start "parent")

    otel_trace_start "child"
    [[ "${_OTEL_CTX[parent_span_id]}" == "$parent_span_id" ]]
}

@test "otel_trace_end: ends current span" {
    otel_init
    otel_trace_start "test"
    local span_id="${_OTEL_CTX[span_id]}"
    local trace_id="${_OTEL_CTX[trace_id]}"

    otel_trace_end

    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"
    grep -q '"endTimeUnixNano": "[0-9]' "$span_file"
}

@test "otel_trace_end: pops span stack correctly" {
    otel_init
    local parent_span_id
    parent_span_id=$(otel_trace_start "parent")
    otel_trace_start "child"

    otel_trace_end  # End child

    [[ "${_OTEL_CTX[span_id]}" == "$parent_span_id" ]]
}

@test "otel_trace_end: clears context when stack empty" {
    otel_init
    otel_trace_start "single"
    otel_trace_end

    [[ -z "${_OTEL_CTX[span_id]}" ]]
    [[ -z "${_OTEL_CTX[trace_id]}" ]]
}

@test "otel_trace_end: handles multiple nested spans" {
    otel_init
    local span1 span2 span3

    span1=$(otel_trace_start "level1")
    span2=$(otel_trace_start "level2")
    span3=$(otel_trace_start "level3")

    otel_trace_end  # End level3
    [[ "${_OTEL_CTX[span_id]}" == "$span2" ]]

    otel_trace_end  # End level2
    [[ "${_OTEL_CTX[span_id]}" == "$span1" ]]

    otel_trace_end  # End level1
    [[ -z "${_OTEL_CTX[span_id]}" ]]
}

# =============================================================================
# CATEGORY 3: SPAN ATTRIBUTES
# =============================================================================

@test "otel_trace_set_attribute: adds string attribute" {
    otel_init
    otel_trace_start "test"
    otel_trace_set_attribute "user.name" "john"

    local trace_id="${_OTEL_CTX[trace_id]}"
    local span_id="${_OTEL_CTX[span_id]}"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    grep -q '"stringValue": "john"' "$span_file"
}

@test "otel_trace_set_attribute: adds integer attribute" {
    otel_init
    otel_trace_start "test"
    otel_trace_set_attribute "http.status_code" "200"

    local trace_id="${_OTEL_CTX[trace_id]}"
    local span_id="${_OTEL_CTX[span_id]}"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    grep -q '"intValue": 200' "$span_file"
}

@test "otel_trace_set_attribute: adds boolean attribute" {
    otel_init
    otel_trace_start "test"
    otel_trace_set_attribute "cache.hit" "true"

    local trace_id="${_OTEL_CTX[trace_id]}"
    local span_id="${_OTEL_CTX[span_id]}"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    grep -q '"boolValue": true' "$span_file"
}

@test "otel_trace_set_attribute: adds float attribute" {
    otel_init
    otel_trace_start "test"
    otel_trace_set_attribute "duration_ms" "123.45"

    local trace_id="${_OTEL_CTX[trace_id]}"
    local span_id="${_OTEL_CTX[span_id]}"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    grep -q '"doubleValue": 123.45' "$span_file"
}

@test "otel_trace_set_attribute: handles special characters" {
    otel_init
    otel_trace_start "test"
    otel_trace_set_attribute "message" 'hello "world"'

    local trace_id="${_OTEL_CTX[trace_id]}"
    local span_id="${_OTEL_CTX[span_id]}"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    grep -q 'hello \\"world\\"' "$span_file"
}

@test "otel_trace_set_attribute: returns error without active span" {
    otel_init
    run otel_trace_set_attribute "key" "value"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 4: EVENTS
# =============================================================================

@test "otel_trace_add_event: adds event to span" {
    otel_init
    otel_trace_start "test"
    otel_trace_add_event "cache.miss"

    local trace_id="${_OTEL_CTX[trace_id]}"
    local span_id="${_OTEL_CTX[span_id]}"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    grep -q '"name": "cache.miss"' "$span_file"
}

@test "otel_trace_add_event: adds event with attributes" {
    otel_init
    otel_trace_start "test"
    otel_trace_add_event "db.query" query="SELECT * FROM users" rows="10"

    local trace_id="${_OTEL_CTX[trace_id]}"
    local span_id="${_OTEL_CTX[span_id]}"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    grep -q '"name": "db.query"' "$span_file"
    grep -q '"key": "query"' "$span_file"
}

@test "otel_trace_add_event: includes timestamp" {
    otel_init
    otel_trace_start "test"
    otel_trace_add_event "checkpoint"

    local trace_id="${_OTEL_CTX[trace_id]}"
    local span_id="${_OTEL_CTX[span_id]}"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    grep -q '"timeUnixNano":' "$span_file"
}

@test "otel_trace_add_event: returns error without active span" {
    otel_init
    run otel_trace_add_event "orphan"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 5: STATUS
# =============================================================================

@test "otel_trace_set_status: sets OK status" {
    otel_init
    otel_trace_start "test"
    otel_trace_set_status "OK"

    local trace_id="${_OTEL_CTX[trace_id]}"
    local span_id="${_OTEL_CTX[span_id]}"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    grep -q '"code": 1' "$span_file"
}

@test "otel_trace_set_status: sets ERROR status" {
    otel_init
    otel_trace_start "test"
    otel_trace_set_status "ERROR"

    local trace_id="${_OTEL_CTX[trace_id]}"
    local span_id="${_OTEL_CTX[span_id]}"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    grep -q '"code": 2' "$span_file"
}

@test "otel_trace_set_status: sets status with message" {
    otel_init
    otel_trace_start "test"
    otel_trace_set_status "ERROR" "Connection refused"

    local trace_id="${_OTEL_CTX[trace_id]}"
    local span_id="${_OTEL_CTX[span_id]}"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    grep -q '"message": "Connection refused"' "$span_file"
}

@test "otel_trace_set_status: case insensitive" {
    otel_init
    otel_trace_start "test"
    otel_trace_set_status "ok"

    local trace_id="${_OTEL_CTX[trace_id]}"
    local span_id="${_OTEL_CTX[span_id]}"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    grep -q '"code": 1' "$span_file"
}

# =============================================================================
# CATEGORY 6: CONTEXT ACCESS
# =============================================================================

@test "otel_trace_id: returns current trace ID" {
    otel_init
    otel_trace_start "test"

    local trace_id
    trace_id=$(otel_trace_id)

    [[ -n "$trace_id" ]]
    [[ ${#trace_id} -eq 32 ]]
}

@test "otel_span_id: returns current span ID" {
    otel_init
    local span_id
    span_id=$(otel_trace_start "test")

    local current_span_id
    current_span_id=$(otel_span_id)

    [[ "$span_id" == "$current_span_id" ]]
}

@test "otel_trace_id: returns empty when no active trace" {
    otel_init
    local trace_id
    trace_id=$(otel_trace_id)
    [[ -z "$trace_id" ]]
}

# =============================================================================
# CATEGORY 7: W3C TRACE CONTEXT PROPAGATION
# =============================================================================

@test "otel_inject_headers: generates valid traceparent" {
    otel_init
    otel_trace_start "test"

    local headers
    headers=$(otel_inject_headers)

    [[ "$headers" =~ traceparent:\ 00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2} ]]
}

@test "otel_inject_headers: includes tracestate" {
    otel_init
    otel_trace_start "test"

    local headers
    headers=$(otel_inject_headers)

    [[ "$headers" =~ tracestate: ]]
}

@test "otel_inject_headers: returns error without active trace" {
    otel_init
    run otel_inject_headers
    [[ "$status" -eq 1 ]]
}

@test "otel_extract_headers: parses valid traceparent" {
    otel_init
    local traceparent="00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

    otel_extract_headers "$traceparent"
    [[ $? -eq 0 ]]

    [[ "${_OTEL_CTX[trace_id]}" == "4bf92f3577b34da6a3ce929d0e0e4736" ]]
    [[ "${_OTEL_CTX[parent_span_id]}" == "00f067aa0ba902b7" ]]
    [[ "${_OTEL_CTX[flags]}" == "01" ]]
}

@test "otel_extract_headers: rejects invalid traceparent" {
    otel_init
    run otel_extract_headers "invalid-traceparent"
    [[ "$status" -eq 1 ]]
}

@test "otel_extract_headers: rejects all-zero trace ID" {
    otel_init
    local traceparent="00-00000000000000000000000000000000-00f067aa0ba902b7-01"
    run otel_extract_headers "$traceparent"
    [[ "$status" -eq 1 ]]
}

@test "otel_extract_headers: rejects all-zero span ID" {
    otel_init
    local traceparent="00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01"
    run otel_extract_headers "$traceparent"
    [[ "$status" -eq 1 ]]
}

@test "otel_extract_headers: preserves tracestate" {
    otel_init
    local traceparent="00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    local tracestate="rojo=00f067aa0ba902b7,congo=t61rcWkgMzE"

    otel_extract_headers "$traceparent" "$tracestate"
    [[ "${_OTEL_CTX[tracestate]}" == "$tracestate" ]]
}

@test "otel_extract_headers: generates new span ID" {
    otel_init
    local traceparent="00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

    otel_extract_headers "$traceparent"

    # New span ID should be different from parent
    [[ "${_OTEL_CTX[span_id]}" != "00f067aa0ba902b7" ]]
    [[ ${#_OTEL_CTX[span_id]} -eq 16 ]]
}

# =============================================================================
# CATEGORY 8: EXPORT
# =============================================================================

@test "otel_export: exports to file format" {
    otel_init
    otel_trace_start "export-test"
    otel_trace_end

    otel_export "file"

    [[ -f "$OTEL_EXPORT_FILE" ]]
}

@test "otel_export: file contains span data" {
    otel_init
    otel_trace_start "file-export-test"
    otel_trace_set_attribute "test.key" "test-value"
    otel_trace_end

    otel_export "file"

    grep -q "file-export-test" "$OTEL_EXPORT_FILE"
}

@test "otel_export: console format outputs to stderr" {
    otel_init
    otel_trace_start "console-test"
    otel_trace_end

    local output
    output=$(otel_export "console" 2>&1)

    [[ "$output" =~ "OTEL SPAN" ]]
}

@test "otel_export: rejects unknown format" {
    otel_init
    run otel_export "unknown_format"
    [[ "$status" -eq 1 ]]
}

@test "otel_export: only exports completed spans" {
    otel_init
    otel_trace_start "incomplete"
    # Don't call otel_trace_end

    otel_export "file"

    # File should not exist or be empty (incomplete span not exported)
    [[ ! -f "$OTEL_EXPORT_FILE" ]] || [[ ! -s "$OTEL_EXPORT_FILE" ]]
}

@test "otel_flush: ends unclosed spans" {
    otel_init
    otel_trace_start "unclosed1"
    otel_trace_start "unclosed2"

    otel_flush

    # Context should be cleared
    [[ -z "${_OTEL_CTX[span_id]}" ]]
}

# =============================================================================
# CATEGORY 9: CONVENIENCE FUNCTIONS
# =============================================================================

@test "otel_instrument: wraps function execution" {
    otel_init

    my_test_func() {
        echo "executed"
        return 0
    }

    local output
    output=$(otel_instrument "my_test_func")

    [[ "$output" == "executed" ]]
}

@test "otel_instrument: creates span for function" {
    otel_init

    my_traced_func() { return 0; }

    otel_instrument "my_traced_func"

    # Span file should exist with function name
    local span_files
    span_files=$(ls "$OTEL_SPAN_DIR"/*.span 2>/dev/null | wc -l)
    [[ $span_files -gt 0 ]]
}

@test "otel_instrument: sets OK status on success" {
    otel_init

    success_func() { return 0; }

    otel_instrument "success_func"

    # Check any span file for OK status (code 1)
    grep -r '"code": 1' "$OTEL_SPAN_DIR"/*.span
}

@test "otel_instrument: sets ERROR status on failure" {
    otel_init

    fail_func() { return 1; }

    run otel_instrument "fail_func"
    [[ "$status" -eq 1 ]]

    # Check for ERROR status (code 2)
    grep -r '"code": 2' "$OTEL_SPAN_DIR"/*.span
}

@test "otel_timed: records command as attribute" {
    otel_init

    otel_timed "echo-test" echo "hello"

    grep -r '"key": "command"' "$OTEL_SPAN_DIR"/*.span
}

@test "otel_timed: records exit code" {
    otel_init

    otel_timed "true-test" true

    grep -r '"key": "exit_code"' "$OTEL_SPAN_DIR"/*.span
}

# =============================================================================
# CATEGORY 10: SAMPLING
# =============================================================================

@test "sampling: 0% rate produces no spans" {
    export OTEL_SAMPLE_RATE="0.0"
    otel_init

    local span_id
    span_id=$(otel_trace_start "unsampled")

    [[ -z "$span_id" ]]
}

@test "sampling: 100% rate produces spans" {
    export OTEL_SAMPLE_RATE="1.0"
    otel_init

    local span_id
    span_id=$(otel_trace_start "sampled")

    [[ -n "$span_id" ]]
}

@test "sampling: disabled tracing produces no spans" {
    export OTEL_TRACING_ENABLED="0"
    otel_init

    local span_id
    span_id=$(otel_trace_start "disabled")

    [[ -z "$span_id" ]]
}

# =============================================================================
# CATEGORY 11: EDGE CASES
# =============================================================================

@test "edge case: empty operation name" {
    otel_init
    local span_id
    span_id=$(otel_trace_start "")

    [[ -n "$span_id" ]]
}

@test "edge case: special characters in operation name" {
    otel_init
    otel_trace_start 'test "quoted" & <special>'

    local trace_id="${_OTEL_CTX[trace_id]}"
    local span_id="${_OTEL_CTX[span_id]}"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    # File should exist and be valid
    [[ -f "$span_file" ]]
}

@test "edge case: deeply nested spans (10 levels)" {
    otel_init

    local spans=()
    for i in {1..10}; do
        spans+=("$(otel_trace_start "level$i")")
    done

    # Verify stack depth
    _otel_sync_state
    [[ ${#_OTEL_SPAN_STACK[@]} -eq 9 ]]  # 9 parents in stack

    # End all spans
    for i in {10..1}; do
        otel_trace_end
    done

    [[ -z "${_OTEL_CTX[span_id]}" ]]
}

@test "edge case: multiple traces in sequence" {
    otel_init

    local trace1 trace2

    otel_trace_start "trace1"
    trace1=$(otel_trace_id)
    otel_trace_end

    otel_trace_start "trace2"
    trace2=$(otel_trace_id)
    otel_trace_end

    # Should be different traces
    [[ "$trace1" != "$trace2" ]]
}

@test "edge case: otel_trace_end without active span" {
    otel_init
    # Should not error
    run otel_trace_end
    [[ "$status" -eq 0 ]]
}

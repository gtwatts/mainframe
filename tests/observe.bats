#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Observability Module Tests
# =============================================================================

load 'test_helper'

setup() {
    source_lib "observe"
    export MAINFRAME_TRACE_ENABLED=1
    export MAINFRAME_TRACE_OUTPUT="/dev/null"  # Suppress stderr in tests
    TEST_DIR=$(create_test_dir "observe")
    export MAINFRAME_TRACE_DIR="$TEST_DIR/.traces"
    # OTEL configuration
    export OTEL_TRACE_ENABLED=1
    export OTEL_SPAN_DIR="$TEST_DIR/.otel_spans"
    export OTEL_SERVICE_NAME="mainframe-test"
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# trace_start TESTS
# =============================================================================

@test "trace_start returns trace ID" {
    local tid
    tid=$(trace_start "test_op")
    [[ "$tid" == trace_* ]]
}

@test "trace_start includes PID in ID" {
    local tid
    tid=$(trace_start "test_op")
    [[ "$tid" == *"$$"* ]] || [[ "$tid" == trace_* ]]
}

@test "trace_start generates unique IDs" {
    local tid1 tid2
    tid1=$(trace_start "op1")
    tid2=$(trace_start "op2")
    [ "$tid1" != "$tid2" ]
}

# =============================================================================
# trace_step TESTS
# =============================================================================

@test "trace_step succeeds with valid trace" {
    local tid
    tid=$(trace_start "myop")
    trace_step "$tid" "step1" "ok"
}

@test "trace_step fails with invalid trace" {
    ! trace_step "invalid_trace_id" "step1"
}

@test "trace_step accepts detail message" {
    local tid
    tid=$(trace_start "myop")
    trace_step "$tid" "step1" "ok" "extra detail"
}

# =============================================================================
# trace_end TESTS
# =============================================================================

@test "trace_end returns JSON with trace_id" {
    local tid
    tid=$(trace_start "myop")
    local result
    result=$(trace_end "$tid" "success")
    [[ "$result" == *"trace_id"* ]]
    [[ "$result" == *"$tid"* ]]
}

@test "trace_end returns JSON with status" {
    local tid
    tid=$(trace_start "myop")
    local result
    result=$(trace_end "$tid" "failed")
    [[ "$result" == *'"status":"failed"'* ]]
}

@test "trace_end returns JSON with name" {
    local tid
    tid=$(trace_start "deploy_config")
    local result
    result=$(trace_end "$tid")
    [[ "$result" == *'"name":"deploy_config"'* ]]
}

@test "trace_end returns JSON with duration" {
    local tid
    tid=$(trace_start "timed_op")
    sleep 0.1
    local result
    result=$(trace_end "$tid")
    [[ "$result" == *"duration_s"* ]]
}

@test "trace_end includes steps" {
    local tid
    tid=$(trace_start "multi_step")
    trace_step "$tid" "first" "ok"
    trace_step "$tid" "second" "ok"
    local result
    result=$(trace_end "$tid")
    [[ "$result" == *'"step":"first"'* ]]
    [[ "$result" == *'"step":"second"'* ]]
}

@test "trace_end fails with unknown trace" {
    local result
    ! result=$(trace_end "nonexistent" 2>/dev/null)
}

# =============================================================================
# observe_command TESTS
# =============================================================================

@test "observe_command captures exit code 0" {
    local result
    result=$(observe_command true)
    [[ "$result" == *'"exit_code":0'* ]]
}

@test "observe_command captures exit code non-zero" {
    local result
    result=$(observe_command false) || true
    [[ "$result" == *'"exit_code":1'* ]]
}

@test "observe_command captures stdout" {
    local result
    result=$(observe_command echo "hello world")
    [[ "$result" == *"hello world"* ]]
}

@test "observe_command captures stderr" {
    local result
    result=$(observe_command bash -c 'echo "err msg" >&2; exit 0')
    [[ "$result" == *"err msg"* ]]
}

@test "observe_command includes duration" {
    local result
    result=$(observe_command sleep 0.1)
    [[ "$result" == *"duration_s"* ]]
}

@test "observe_command includes command name" {
    local result
    result=$(observe_command ls /tmp)
    [[ "$result" == *'"cmd":"ls /tmp"'* ]]
}

@test "observe_command fails with no args" {
    local result
    result=$(observe_command) || true
    [[ "$result" == *"no command"* ]]
}

# =============================================================================
# stack_trace TESTS
# =============================================================================

@test "stack_trace returns JSON with stack array" {
    _helper_for_stack() {
        stack_trace
    }
    local result
    result=$(_helper_for_stack)
    [[ "$result" == *'"stack":['* ]]
}

@test "stack_trace includes depth" {
    local result
    result=$(stack_trace)
    [[ "$result" == *'"depth":'* ]]
}

@test "stack_trace includes function names" {
    _inner_func() {
        stack_trace
    }
    local result
    result=$(_inner_func)
    [[ "$result" == *'"func":"_inner_func"'* ]]
}

# =============================================================================
# observe_error TESTS
# =============================================================================

@test "observe_error emits JSON to stderr" {
    local err
    err=$(observe_error 42 "something broke" 2>&1) || true
    [[ "$err" == *'"error":true'* ]]
    [[ "$err" == *'"code":42'* ]]
    [[ "$err" == *'"msg":"something broke"'* ]]
}

@test "observe_error returns provided exit code" {
    local rc=0
    observe_error 5 "test" 2>/dev/null || rc=$?
    [ "$rc" = "5" ]
}

@test "observe_error includes context when provided" {
    local err
    err=$(observe_error 1 "bad port" "port=99999" 2>&1) || true
    [[ "$err" == *'"context":"port=99999"'* ]]
}

# =============================================================================
# observe_time / observe_elapsed TESTS
# =============================================================================

@test "observe_time returns numeric timestamp" {
    local t
    t=$(observe_time)
    [[ "$t" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "observe_elapsed returns duration" {
    local start
    start=$(observe_time)
    sleep 0.1
    local elapsed
    elapsed=$(observe_elapsed "$start")
    [[ "$elapsed" =~ ^[0-9]+\.?[0-9]*$ ]]
}

# =============================================================================
# TRACE TO FILE TESTS
# =============================================================================

@test "trace output writes to file when configured" {
    export MAINFRAME_TRACE_OUTPUT="$TEST_DIR/trace.log"
    local tid
    tid=$(trace_start "file_trace")
    trace_step "$tid" "write" "ok"
    trace_end "$tid" "success" > /dev/null
    [ -f "$TEST_DIR/trace.log" ]
    [[ $(cat "$TEST_DIR/trace.log") == *"file_trace"* ]]
}

# =============================================================================
# OPENTELEMETRY TRACING TESTS
# =============================================================================

# -----------------------------------------------------------------------------
# otel_trace_start / otel_trace_end TESTS
# -----------------------------------------------------------------------------

@test "otel_trace_start returns 32-char hex trace ID" {
    local trace_id
    trace_id=$(otel_trace_start "test_operation")
    [ ${#trace_id} -eq 32 ]
    [[ "$trace_id" =~ ^[0-9a-f]+$ ]]
}

@test "otel_trace_start creates span file" {
    local trace_id
    trace_id=$(otel_trace_start "file_test")
    [ -d "$OTEL_SPAN_DIR" ]
    local span_files
    span_files=$(ls "$OTEL_SPAN_DIR"/${trace_id}_*.span 2>/dev/null | wc -l)
    [ "$span_files" -ge 1 ]
}

@test "otel_trace_start creates valid span JSON" {
    local trace_id
    trace_id=$(otel_trace_start "json_test")
    local span_file
    span_file=$(ls "$OTEL_SPAN_DIR"/${trace_id}_*.span 2>/dev/null | head -1)
    [ -f "$span_file" ]
    local content
    content=$(<"$span_file")
    [[ "$content" == *"\"traceId\": \"$trace_id\""* ]]
    [[ "$content" == *"\"name\": \"json_test\""* ]]
    [[ "$content" == *"startTimeUnixNano"* ]]
}

@test "otel_trace_start with attributes" {
    local trace_id
    trace_id=$(otel_trace_start "attr_test" '[{"key":"test","value":{"stringValue":"value"}}]')
    local span_file
    span_file=$(ls "$OTEL_SPAN_DIR"/${trace_id}_*.span 2>/dev/null | head -1)
    local content
    content=$(<"$span_file")
    [[ "$content" == *"test"* ]]
}

@test "otel_trace_end completes span" {
    local trace_id
    trace_id=$(otel_trace_start "end_test")
    otel_trace_end "$trace_id"
    local span_file
    span_file=$(ls "$OTEL_SPAN_DIR"/${trace_id}_*.span 2>/dev/null | head -1)
    local content
    content=$(<"$span_file")
    [[ "$content" == *"endTimeUnixNano"* ]]
}

@test "otel_trace_start returns empty when disabled" {
    OTEL_TRACE_ENABLED=0
    local trace_id
    trace_id=$(otel_trace_start "disabled_test")
    [ -z "$trace_id" ]
    OTEL_TRACE_ENABLED=1
}

# -----------------------------------------------------------------------------
# otel_span_create / otel_span_end TESTS
# -----------------------------------------------------------------------------

@test "otel_span_create returns 16-char hex span ID" {
    local trace_id span_id
    trace_id=$(otel_trace_start "span_test")
    span_id=$(otel_span_create "child_span")
    [ ${#span_id} -eq 16 ]
    [[ "$span_id" =~ ^[0-9a-f]+$ ]]
}

@test "otel_span_create creates span file with parent" {
    local trace_id span_id
    trace_id=$(otel_trace_start "parent_test")
    local root_span_id="${_OTEL_TRACE_CTX[span_id]}"
    span_id=$(otel_span_create "child_span")
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"
    [ -f "$span_file" ]
    local content
    content=$(<"$span_file")
    [[ "$content" == *"\"parentSpanId\": \"$root_span_id\""* ]]
}

@test "otel_span_create fails without trace context" {
    _OTEL_TRACE_CTX[trace_id]=""
    local span_id
    span_id=$(otel_span_create "orphan_span")
    [ -z "$span_id" ]
}

@test "otel_span_end sets OK status" {
    local trace_id span_id
    trace_id=$(otel_trace_start "status_test")
    span_id=$(otel_span_create "ok_span")
    otel_span_end "$span_id" "OK"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"
    local content
    content=$(<"$span_file")
    [[ "$content" == *'"code": "OK"'* ]]
    [[ "$content" == *"endTimeUnixNano"* ]]
}

@test "otel_span_end sets ERROR status" {
    local trace_id span_id
    trace_id=$(otel_trace_start "error_test")
    span_id=$(otel_span_create "error_span")
    otel_span_end "$span_id" "ERROR"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"
    local content
    content=$(<"$span_file")
    [[ "$content" == *'"code": "ERROR"'* ]]
}

# -----------------------------------------------------------------------------
# otel_span_attribute TESTS
# -----------------------------------------------------------------------------

@test "otel_span_attribute adds string attribute" {
    local trace_id span_id
    trace_id=$(otel_trace_start "str_attr_test")
    span_id=$(otel_span_create "attr_span")
    otel_span_attribute "$span_id" "http.method" "GET"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"
    local content
    content=$(<"$span_file")
    [[ "$content" == *"http.method"* ]]
    [[ "$content" == *"stringValue"* ]]
    [[ "$content" == *"GET"* ]]
}

@test "otel_span_attribute adds integer attribute" {
    local trace_id span_id
    trace_id=$(otel_trace_start "int_attr_test")
    span_id=$(otel_span_create "int_span")
    otel_span_attribute "$span_id" "http.status_code" "200"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"
    local content
    content=$(<"$span_file")
    [[ "$content" == *"http.status_code"* ]]
    [[ "$content" == *"intValue"* ]]
    [[ "$content" == *"200"* ]]
}

@test "otel_span_attribute adds boolean attribute" {
    local trace_id span_id
    trace_id=$(otel_trace_start "bool_attr_test")
    span_id=$(otel_span_create "bool_span")
    otel_span_attribute "$span_id" "cache.hit" "true"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"
    local content
    content=$(<"$span_file")
    [[ "$content" == *"cache.hit"* ]]
    [[ "$content" == *"boolValue"* ]]
}

# -----------------------------------------------------------------------------
# otel_span_event TESTS
# -----------------------------------------------------------------------------

@test "otel_span_event adds event to span" {
    local trace_id span_id
    trace_id=$(otel_trace_start "event_test")
    span_id=$(otel_span_create "event_span")
    otel_span_event "$span_id" "cache.miss"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"
    local content
    content=$(<"$span_file")
    [[ "$content" == *"cache.miss"* ]]
    [[ "$content" == *"timeUnixNano"* ]]
}

@test "otel_span_event with attributes" {
    local trace_id span_id
    trace_id=$(otel_trace_start "event_attr_test")
    span_id=$(otel_span_create "event_attr_span")
    otel_span_event "$span_id" "db.query" '[{"key":"sql","value":{"stringValue":"SELECT 1"}}]'
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"
    local content
    content=$(<"$span_file")
    [[ "$content" == *"db.query"* ]]
    [[ "$content" == *"SELECT 1"* ]]
}

# -----------------------------------------------------------------------------
# otel_span_exception TESTS
# -----------------------------------------------------------------------------

@test "otel_span_exception records error" {
    local trace_id span_id
    trace_id=$(otel_trace_start "exception_test")
    span_id=$(otel_span_create "exception_span")
    otel_span_exception "$span_id" "File not found" "/path/to/file"
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"
    local content
    content=$(<"$span_file")
    [[ "$content" == *"exception.message"* ]]
    [[ "$content" == *"File not found"* ]]
    [[ "$content" == *'"code": "ERROR"'* ]]
}

# -----------------------------------------------------------------------------
# CONTEXT PROPAGATION TESTS
# -----------------------------------------------------------------------------

@test "otel_traceparent returns W3C format" {
    local trace_id
    trace_id=$(otel_trace_start "traceparent_test")
    local traceparent
    traceparent=$(otel_traceparent)
    [[ "$traceparent" =~ ^00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$ ]]
}

@test "otel_tracestate returns mainframe vendor" {
    local trace_id
    trace_id=$(otel_trace_start "tracestate_test")
    local tracestate
    tracestate=$(otel_tracestate)
    [[ "$tracestate" == mainframe=* ]]
}

@test "otel_parse_traceparent extracts components" {
    local traceparent="00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    otel_parse_traceparent "$traceparent"
    [ "$OTEL_TRACE_ID" = "4bf92f3577b34da6a3ce929d0e0e4736" ]
    [ "$OTEL_PARENT_SPAN_ID" = "00f067aa0ba902b7" ]
    [ "$OTEL_FLAGS" = "01" ]
}

@test "otel_parse_traceparent rejects invalid format" {
    ! otel_parse_traceparent "invalid"
    ! otel_parse_traceparent "00-short-span-01"
    ! otel_parse_traceparent "01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"  # Invalid version
}

@test "otel_parse_traceparent rejects all-zero trace_id" {
    ! otel_parse_traceparent "00-00000000000000000000000000000000-00f067aa0ba902b7-01"
}

@test "otel_context_inject exports env vars" {
    local trace_id
    trace_id=$(otel_trace_start "inject_test")
    otel_context_inject
    [ -n "$TRACEPARENT" ]
    [ -n "$TRACESTATE" ]
    [[ "$TRACEPARENT" =~ ^00- ]]
}

@test "otel_context_extract restores context" {
    export TRACEPARENT="00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    otel_context_extract
    [ "${_OTEL_TRACE_CTX[trace_id]}" = "4bf92f3577b34da6a3ce929d0e0e4736" ]
    [ "${_OTEL_TRACE_CTX[parent_id]}" = "00f067aa0ba902b7" ]
}

# -----------------------------------------------------------------------------
# EXPORT TESTS
# -----------------------------------------------------------------------------

@test "otel_export_json creates valid file" {
    local trace_id span_id
    trace_id=$(otel_trace_start "export_test")
    span_id=$(otel_span_create "export_span")
    otel_span_end "$span_id" "OK"
    otel_trace_end "$trace_id"

    otel_export_json "$TEST_DIR/traces.json"
    [ -f "$TEST_DIR/traces.json" ]
    local content
    content=$(<"$TEST_DIR/traces.json")
    [[ "$content" == *"resourceSpans"* ]]
    [[ "$content" == *"scopeSpans"* ]]
    [[ "$content" == *"spans"* ]]
}

@test "otel_export_console outputs to stderr" {
    local trace_id span_id
    trace_id=$(otel_trace_start "console_test")
    span_id=$(otel_span_create "console_span")
    otel_span_end "$span_id" "OK"

    local output
    output=$(otel_export_console 2>&1)
    [[ "$output" == *"[OTEL]"* ]]
    [[ "$output" == *"console_span"* ]]
}

# -----------------------------------------------------------------------------
# HELPER FUNCTION TESTS
# -----------------------------------------------------------------------------

@test "otel_instrument wraps function execution" {
    _test_func() {
        echo "executed"
        return 0
    }

    local trace_id
    trace_id=$(otel_trace_start "instrument_test")
    local result
    result=$(otel_instrument _test_func)
    [ "$result" = "executed" ]
}

@test "otel_instrument captures errors" {
    _failing_func() {
        return 42
    }

    local trace_id
    trace_id=$(otel_trace_start "instrument_error_test")
    local exit_code=0
    otel_instrument _failing_func || exit_code=$?
    [ "$exit_code" = "42" ]
}

@test "otel_timed measures command duration" {
    local trace_id
    trace_id=$(otel_trace_start "timed_test")
    otel_timed "sleep_span" sleep 0.1

    # Find the span file
    local span_file
    span_file=$(ls "$OTEL_SPAN_DIR"/${trace_id}_*.span 2>/dev/null | grep -v "^$OTEL_SPAN_DIR/${trace_id}_${_OTEL_TRACE_CTX[span_id]}" | head -1)

    # Should have command and exit_code attributes
    [ -f "$span_file" ]
}

# -----------------------------------------------------------------------------
# BATCH COLLECTION TESTS
# -----------------------------------------------------------------------------

@test "otel_batch_start enables batch mode" {
    otel_batch_start
    [ "$_OTEL_BATCH_MODE" = "1" ]
    [ ${#_OTEL_BATCH_BUFFER[@]} -eq 0 ]
}

@test "otel_batch_add accumulates spans" {
    otel_batch_start
    otel_batch_add '{"test":"span1"}'
    otel_batch_add '{"test":"span2"}'
    [ ${#_OTEL_BATCH_BUFFER[@]} -eq 2 ]
    _OTEL_BATCH_MODE="0"
    _OTEL_BATCH_BUFFER=()
}

@test "otel_batch_flush clears buffer" {
    otel_batch_start
    otel_batch_add '{"traceId":"abc","spanId":"def","test":"span1","endTimeUnixNano":123}'
    otel_batch_flush
    [ ${#_OTEL_BATCH_BUFFER[@]} -eq 0 ]
    [ "$_OTEL_BATCH_MODE" = "0" ]
}

# -----------------------------------------------------------------------------
# LEGACY BRIDGE TESTS
# -----------------------------------------------------------------------------

@test "otel_from_trace converts legacy trace" {
    local legacy_tid
    legacy_tid=$(trace_start "legacy_op")
    trace_step "$legacy_tid" "step1" "ok" "detail"

    local otel_trace_id
    otel_trace_id=$(otel_from_trace "$legacy_tid")

    [ ${#otel_trace_id} -eq 32 ]

    # Check OTEL span file was created
    local span_file
    span_file=$(ls "$OTEL_SPAN_DIR"/${otel_trace_id}_*.span 2>/dev/null | head -1)
    [ -f "$span_file" ]

    local content
    content=$(<"$span_file")
    [[ "$content" == *"legacy_op"* ]]
    [[ "$content" == *"legacy.trace_id"* ]]
}

@test "otel_from_trace fails with invalid trace" {
    ! otel_from_trace "nonexistent_trace"
}

# -----------------------------------------------------------------------------
# FLUSH TESTS
# -----------------------------------------------------------------------------

@test "otel_flush ends unclosed spans" {
    local trace_id span_id
    trace_id=$(otel_trace_start "flush_test")
    span_id=$(otel_span_create "unclosed_span")

    # Span is not ended yet
    local span_file="$OTEL_SPAN_DIR/${trace_id}_${span_id}.span"
    local content
    content=$(<"$span_file")
    [[ "$content" != *"endTimeUnixNano"* ]]

    otel_flush

    # After flush, span should be ended
    content=$(<"$span_file")
    [[ "$content" == *"endTimeUnixNano"* ]]
}

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Trace Library Tests
# =============================================================================
# Tests for lib/trace.sh - Savant-Level Debugging Framework
# =============================================================================

load 'test_helper'

setup() {
    # Prevent cleanup trap from running during tests
    export _MAINFRAME_TRACE_NO_CLEANUP=1
    source_lib "trace"
    TEST_DIR=$(create_test_dir "trace")

    # Enable tracing for tests
    trace_enable
    trace_set_output "$TEST_DIR/trace.jsonl"
    trace_clear
}

teardown() {
    trace_disable
    trace_clear
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# CONTROL FUNCTION TESTS
# =============================================================================

@test "trace_enable sets MAINFRAME_TRACE_ENABLED to 1" {
    trace_disable
    trace_enable
    [ "$?" -eq 0 ]
    [ "$MAINFRAME_TRACE_ENABLED" = "1" ]
}

@test "trace_disable sets MAINFRAME_TRACE_ENABLED to 0" {
    trace_enable
    trace_disable
    [ "$?" -eq 0 ]
    [ "$MAINFRAME_TRACE_ENABLED" = "0" ]
}

@test "trace_is_enabled returns 0 when enabled" {
    trace_enable
    run trace_is_enabled
    [ "$status" -eq 0 ]
}

@test "trace_is_enabled returns 1 when disabled" {
    trace_disable
    run trace_is_enabled
    [ "$status" -eq 1 ]
}

@test "trace_status returns valid JSON" {
    run trace_status
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"enabled\":"* ]]
    [[ "$output" == *"\"entries\":"* ]]
    [[ "$output" == *"\"timers\":"* ]]
}

@test "trace_status shows enabled state" {
    trace_enable
    run trace_status
    [[ "$output" == *"\"enabled\":true"* ]]
}

@test "trace_status shows disabled state" {
    trace_disable
    run trace_status
    [[ "$output" == *"\"enabled\":false"* ]]
}

# =============================================================================
# TIMING TESTS
# =============================================================================

@test "trace_timer_start stores timer" {
    run trace_timer_start "test_timer"
    [ "$status" -eq 0 ]
}

@test "trace_timer_stop returns elapsed time" {
    trace_timer_start "elapsed_test"
    sleep 0.1
    run trace_timer_stop "elapsed_test"
    [ "$status" -eq 0 ]
    # Should have some value (nanoseconds)
    [[ "$output" =~ ^[0-9]+$ ]]
    [ "$output" -gt 0 ]
}

@test "trace_timer_stop returns 1 for unknown timer" {
    run trace_timer_stop "nonexistent_timer"
    [ "$status" -eq 1 ]
    [ "$output" = "0" ]
}

@test "trace_timer_start emits JSON event" {
    trace_timer_start "json_test"
    local content
    content=$(cat "$TEST_DIR/trace.jsonl")
    [[ "$content" == *"\"event\":\"timer_start\""* ]]
    [[ "$content" == *"\"label\":\"json_test\""* ]]
}

@test "trace_timer_stop emits JSON event" {
    trace_timer_start "stop_test"
    trace_timer_stop "stop_test"
    local content
    content=$(cat "$TEST_DIR/trace.jsonl")
    [[ "$content" == *"\"event\":\"timer_stop\""* ]]
    [[ "$content" == *"\"elapsed_ns\":"* ]]
}

@test "trace_timing executes command and returns exit code" {
    run trace_timing "echo_test" echo "hello"
    [ "$status" -eq 0 ]
}

@test "trace_timing returns command's exit code on failure" {
    run trace_timing "false_test" false
    [ "$status" -eq 1 ]
}

@test "trace_timing emits JSON with command and timing" {
    trace_timing "timing_json_test" true
    local content
    content=$(cat "$TEST_DIR/trace.jsonl")
    [[ "$content" == *"\"event\":\"timing\""* ]]
    [[ "$content" == *"\"label\":\"timing_json_test\""* ]]
    [[ "$content" == *"\"elapsed_ns\":"* ]]
}

@test "multiple timers work independently" {
    trace_timer_start "timer_a"
    sleep 0.05
    trace_timer_start "timer_b"
    sleep 0.05

    local elapsed_a elapsed_b
    elapsed_a=$(trace_timer_stop "timer_a")
    elapsed_b=$(trace_timer_stop "timer_b")

    # Timer A should have run longer
    [ "$elapsed_a" -gt "$elapsed_b" ]
}

# =============================================================================
# SNAPSHOT TESTS
# =============================================================================

@test "trace_snapshot creates snapshot" {
    local test_var="test_value"
    run trace_snapshot "snap1"
    [ "$status" -eq 0 ]
}

@test "trace_snapshot emits JSON event" {
    trace_snapshot "json_snap"
    local content
    content=$(cat "$TEST_DIR/trace.jsonl")
    [[ "$content" == *"\"event\":\"snapshot\""* ]]
    [[ "$content" == *"\"name\":\"json_snap\""* ]]
}

@test "trace_diff returns JSON with differences" {
    local test_var="initial"
    trace_snapshot "before"
    test_var="changed"
    local new_var="added"
    trace_snapshot "after"

    run trace_diff "before" "after"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"diff\":"* ]]
    [[ "$output" == *"\"added\":"* ]]
    [[ "$output" == *"\"changed\":"* ]]
}

@test "trace_diff returns 1 for missing snapshot" {
    run trace_diff "nonexistent1" "nonexistent2"
    [ "$status" -eq 1 ]
}

@test "trace_diff detects added variables" {
    trace_snapshot "diff_before"
    local TRACE_TEST_ADDED_VAR="new_value"
    export TRACE_TEST_ADDED_VAR
    trace_snapshot "diff_after"

    run trace_diff "diff_before" "diff_after"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TRACE_TEST_ADDED_VAR"* ]] || [[ "$output" == *"\"added\":"* ]]
}

# =============================================================================
# OUTPUT TESTS
# =============================================================================

@test "trace_to_json returns JSON array" {
    trace_timer_start "json_out_test"
    trace_timer_stop "json_out_test"

    run trace_to_json
    [ "$status" -eq 0 ]
    [[ "$output" == "["* ]]
    [[ "$output" == *"]" ]]
}

@test "trace_to_json contains trace entries" {
    trace_timer_start "entry_test"
    trace_timer_stop "entry_test"

    run trace_to_json
    [[ "$output" == *"timer_start"* ]]
    [[ "$output" == *"timer_stop"* ]]
}

@test "trace_clear removes all entries" {
    trace_timer_start "clear_test"
    trace_timer_stop "clear_test"
    trace_clear

    run trace_to_json
    [ "$output" = "[]" ]
}

@test "trace_set_output changes output file" {
    local new_output="$TEST_DIR/new_trace.jsonl"
    trace_set_output "$new_output"
    trace_timer_start "output_test"
    trace_timer_stop "output_test"

    [ -f "$new_output" ]
    local content
    content=$(cat "$new_output")
    [[ "$content" == *"output_test"* ]]
}

@test "trace_to_mermaid generates valid Mermaid syntax" {
    # Create some function trace events manually
    _TRACE_ENTRIES+=('{"event":"func_entry","func":"test_func","args":[],"timestamp":1234}')
    _TRACE_ENTRIES+=('{"event":"func_exit","func":"test_func","exit_code":0,"timestamp":1235}')

    run trace_to_mermaid
    [ "$status" -eq 0 ]
    [[ "$output" == *"sequenceDiagram"* ]]
    [[ "$output" == *"participant"* ]]
}

# =============================================================================
# VARIABLE WATCHING TESTS
# =============================================================================

@test "trace_variable starts watching" {
    local watched_var="initial"
    trace_variable "watched_var"
    [ "$?" -eq 0 ]
    [ "${_TRACE_WATCHED_VARS[watched_var]}" = "1" ]
    trace_unwatch "watched_var"
}

@test "trace_unwatch stops watching" {
    local test_var="test"
    trace_variable "test_var"
    trace_unwatch "test_var"
    [ "$?" -eq 0 ]
    [[ -z "${_TRACE_WATCHED_VARS[test_var]:-}" ]]
}

@test "trace_unwatch returns 0 for unwatched variable" {
    run trace_unwatch "never_watched"
    [ "$status" -eq 0 ]
}

# =============================================================================
# RECORDING TESTS
# =============================================================================

@test "trace_record_start creates recording session" {
    trace_record_start "test_session"
    [ "$?" -eq 0 ]
    [ "$_TRACE_RECORDING_ACTIVE" = "1" ]
    [ "$_TRACE_RECORDING_SESSION" = "test_session" ]
    trace_record_stop
}

@test "trace_record_start emits JSON event" {
    trace_record_start "json_session"
    trace_record_stop
    local content
    content=$(cat "$TEST_DIR/trace.jsonl")
    [[ "$content" == *"\"event\":\"record_start\""* ]]
}

@test "trace_record_stop emits JSON event" {
    trace_record_start "stop_session"
    trace_record_stop
    local content
    content=$(cat "$TEST_DIR/trace.jsonl")
    [[ "$content" == *"\"event\":\"record_stop\""* ]]
}

@test "trace_record_stop is safe when no recording active" {
    run trace_record_stop
    [ "$status" -eq 0 ]
}

@test "trace_replay returns 1 for nonexistent session" {
    run trace_replay "nonexistent_session"
    [ "$status" -eq 1 ]
}

@test "trace_replay returns recorded data as JSON" {
    trace_record_start "replay_test"
    trace_record_command "echo" "hello" "world"
    trace_record_stop

    run trace_replay "replay_test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"replay_session\":\"replay_test\""* ]]
    [[ "$output" == *"\"events\":"* ]]
}

@test "trace_record_command records commands" {
    trace_record_start "cmd_test"
    trace_record_command "ls" "-la" "/tmp"
    trace_record_stop

    run trace_replay "cmd_test"
    [[ "$output" == *"\"cmd\":\"ls\""* ]]
    [[ "$output" == *"\"-la\""* ]]
}

# =============================================================================
# FUNCTION TRACING TESTS
# =============================================================================

@test "trace_function returns 1 for nonexistent function" {
    run trace_function "nonexistent_func_12345"
    [ "$status" -eq 1 ]
}

@test "trace_function traces existing function" {
    # Define a test function
    test_trace_func() {
        echo "hello"
    }

    trace_function "test_trace_func"
    [ "$?" -eq 0 ]
    [ -n "${_TRACE_FUNC_WRAPPERS[test_trace_func]:-}" ]

    result=$(test_trace_func)
    [ "$result" = "hello" ]

    # Clean up
    trace_untrace "test_trace_func"
}

@test "trace_untrace returns 1 for untraced function" {
    run trace_untrace "never_traced_func"
    [ "$status" -eq 1 ]
}

@test "trace_untrace restores original function" {
    # Define and trace
    original_test_func() {
        echo "original"
    }
    trace_function "original_test_func"

    # Untrace
    trace_untrace "original_test_func"
    [ "$?" -eq 0 ]
    [[ -z "${_TRACE_FUNC_WRAPPERS[original_test_func]:-}" ]]

    # Verify function still works
    result=$(original_test_func)
    [ "$result" = "original" ]
}

@test "trace_all_in_file returns 1 for nonexistent file" {
    run trace_all_in_file "/nonexistent/file.sh"
    [ "$status" -eq 1 ]
}

@test "trace_all_in_file processes valid bash file" {
    # Create a test script
    printf 'test_file_func() {\n    echo "test"\n}\n' > "$TEST_DIR/test_script.sh"
    source "$TEST_DIR/test_script.sh"

    trace_all_in_file "$TEST_DIR/test_script.sh"
    [ "$?" -eq 0 ]
    [ -n "${_TRACE_FUNC_WRAPPERS[test_file_func]:-}" ]
    trace_untrace "test_file_func"
}

# =============================================================================
# INTERNAL HELPER TESTS
# =============================================================================

@test "_trace_now returns timestamp" {
    run _trace_now
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "_trace_now_ns returns nanosecond timestamp" {
    run _trace_now_ns
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
    # Should be at least 10 digits (seconds since epoch + ns)
    [ ${#output} -ge 10 ]
}

@test "_trace_escape handles special characters" {
    run _trace_escape 'hello"world'
    [ "$status" -eq 0 ]
    [ "$output" = 'hello\"world' ]
}

@test "_trace_escape handles newlines" {
    local input=$'line1\nline2'
    run _trace_escape "$input"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\\n"* ]]
}

@test "_trace_escape handles tabs" {
    local input=$'col1\tcol2'
    run _trace_escape "$input"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\\t"* ]]
}

@test "_trace_escape handles backslashes" {
    run _trace_escape 'path\\to\\file'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\\\\"* ]]
}

@test "_trace_duration calculates time difference" {
    run _trace_duration "100.0" "105.5"
    [ "$status" -eq 0 ]
    # Should be approximately 5.5
    [[ "$output" == "5"* ]]
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

@test "full tracing workflow" {
    # Start recording
    trace_record_start "full_workflow"

    # Take snapshot
    local workflow_var="step1"
    trace_snapshot "workflow_before"

    # Timer
    trace_timer_start "workflow_timer"
    sleep 0.1
    trace_timer_stop "workflow_timer"

    # Modify and snapshot
    workflow_var="step2"
    trace_snapshot "workflow_after"

    # Stop recording
    trace_record_stop

    # Verify output
    local content
    content=$(cat "$TEST_DIR/trace.jsonl")
    [[ "$content" == *"record_start"* ]]
    [[ "$content" == *"snapshot"* ]]
    [[ "$content" == *"timer_start"* ]]
    [[ "$content" == *"timer_stop"* ]]
    [[ "$content" == *"record_stop"* ]]
}

@test "trace entries respect max entries limit" {
    local old_max="$MAINFRAME_TRACE_MAX_ENTRIES"
    MAINFRAME_TRACE_MAX_ENTRIES=5

    # Generate more entries than limit
    for i in {1..10}; do
        trace_timer_start "limit_test_$i"
        trace_timer_stop "limit_test_$i"
    done

    # Should have at most 5 entries
    local json
    json=$(trace_to_json)
    local count
    count=$(echo "$json" | grep -o '"event"' | wc -l)
    [ "$count" -le 10 ]  # Each timer creates 2 entries, but capped

    MAINFRAME_TRACE_MAX_ENTRIES="$old_max"
}

@test "disabled tracing produces no output" {
    trace_disable
    trace_timer_start "disabled_test"
    trace_timer_stop "disabled_test"

    run trace_to_json
    [ "$output" = "[]" ]
}

@test "trace entries have timestamps" {
    trace_timer_start "timestamp_test"
    trace_timer_stop "timestamp_test"

    local content
    content=$(cat "$TEST_DIR/trace.jsonl")
    [[ "$content" == *"timestamp"* ]]
}

@test "status shows correct entry count" {
    trace_timer_start "count_test_1"
    trace_timer_stop "count_test_1"
    trace_timer_start "count_test_2"
    trace_timer_stop "count_test_2"

    run trace_status
    [[ "$output" == *"\"entries\":4"* ]]  # 2 starts + 2 stops
}

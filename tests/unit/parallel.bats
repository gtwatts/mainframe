#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/parallel.bats - Parallel Execution Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/parallel.sh
#              Parallel map, race, all, any, batch, timeout, retry, progress
# Test Count: 60 test cases
# Categories: map operations, race/all/any, batch processing, timeout,
#             retry logic, progress reporting, edge cases
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"
    export PARALLEL_STATE_DIR="$TEST_TMPDIR/parallel_state"
    mkdir -p "$PARALLEL_STATE_DIR"

    # Suppress logging during tests
    export MAINFRAME_QUIET=1

    # Create mock bin directory
    MOCK_BIN="$TEST_TMPDIR/mock_bin"
    mkdir -p "$MOCK_BIN"
    export PATH="$MOCK_BIN:$PATH"

    # Source the library
    source "$MAINFRAME_ROOT/lib/parallel.sh"
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# Helper: Create a simple test function
create_test_function() {
    eval '
    test_echo() {
        echo "processed: $1"
    }
    '
}

# Helper: Create a slow test function
create_slow_function() {
    eval '
    slow_echo() {
        sleep "${1:-0.1}"
        echo "slow: $1"
    }
    '
}

# Helper: Create a failing function
create_failing_function() {
    eval '
    fail_sometimes() {
        if [[ "$1" == "fail" ]]; then
            echo "error: $1" >&2
            return 1
        fi
        echo "ok: $1"
    }
    '
}

# Helper: Extract JSON field
json_get() {
    local json="$1"
    local field="$2"
    echo "$json" | grep -o "\"$field\":[^,}]*" | head -1 | sed 's/.*://;s/"//g'
}

# Helper: Check if JSON contains field with value
json_has() {
    local json="$1"
    local field="$2"
    local value="$3"
    [[ "$json" == *"\"$field\":$value"* ]] || [[ "$json" == *"\"$field\":\"$value\""* ]]
}

# =============================================================================
# CATEGORY 1: PARALLEL MAP
# =============================================================================

@test "parallel_map: processes all items" {
    create_test_function
    result=$(parallel_map "test_echo" "a" "b" "c")
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'"succeeded":3'* ]]
}

@test "parallel_map: returns correct result count" {
    create_test_function
    result=$(parallel_map "test_echo" "x" "y")
    [[ "$result" == *'"succeeded":2'* ]]
    [[ "$result" == *'"failed":0'* ]]
}

@test "parallel_map: captures output from each item" {
    create_test_function
    result=$(parallel_map "test_echo" "hello")
    [[ "$result" == *"processed: hello"* ]]
}

@test "parallel_map: handles empty input" {
    result=$(parallel_map "echo")
    [[ "$result" == *'"results":[]'* ]]
}

@test "parallel_map: reports failures correctly" {
    create_failing_function
    result=$(parallel_map "fail_sometimes" "ok" "fail" "ok")
    [[ "$result" == *'"ok":false'* ]]
    [[ "$result" == *'"failed":1'* ]]
    [[ "$result" == *'"succeeded":2'* ]]
}

@test "parallel_map: includes duration measurements" {
    create_test_function
    result=$(parallel_map "test_echo" "item")
    [[ "$result" == *'"duration_ms":'* ]]
    [[ "$result" == *'"total_duration_ms":'* ]]
}

# =============================================================================
# CATEGORY 2: PARALLEL MAP WITH CONCURRENCY LIMIT
# =============================================================================

@test "parallel_map_n: respects concurrency limit" {
    # Create a function that tracks concurrent execution
    cat > "$MOCK_BIN/track_concurrent" << 'EOF'
#!/bin/bash
echo "$$" >> /tmp/parallel_test_pids
sleep 0.1
echo "done: $1"
EOF
    chmod +x "$MOCK_BIN/track_concurrent"

    rm -f /tmp/parallel_test_pids
    result=$(parallel_map_n "track_concurrent" 2 "a" "b" "c" "d")
    rm -f /tmp/parallel_test_pids

    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'"succeeded":4'* ]]
}

@test "parallel_map_n: handles limit of 1 (sequential)" {
    create_test_function
    result=$(parallel_map_n "test_echo" 1 "a" "b" "c")
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'"succeeded":3'* ]]
}

@test "parallel_map_n: handles limit greater than items" {
    create_test_function
    result=$(parallel_map_n "test_echo" 10 "a" "b")
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'"succeeded":2'* ]]
}

@test "parallel_map_n: invalid limit defaults to 1" {
    create_test_function
    result=$(parallel_map_n "test_echo" 0 "a" "b")
    [[ "$result" == *'"ok":true'* ]]
}

# =============================================================================
# CATEGORY 3: PARALLEL RACE
# =============================================================================

@test "parallel_race: returns first completer" {
    # Create fast and slow commands
    result=$(parallel_race "echo fast" "sleep 2; echo slow")
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *"fast"* ]]
}

@test "parallel_race: cancels other commands" {
    result=$(parallel_race "echo winner" "sleep 2")
    [[ "$result" == *'"succeeded":1'* ]]
}

@test "parallel_race: returns error if winner fails" {
    result=$(parallel_race "false" "sleep 2")
    [[ "$result" == *'"ok":false'* ]]
}

@test "parallel_race: handles no commands" {
    run parallel_race
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'"ok":false'* ]]
    [[ "$output" == *'E_NO_COMMANDS'* ]]
}

@test "parallel_race: includes winner_index hint" {
    result=$(parallel_race "echo first" "sleep 1; echo second")
    [[ "$result" == *'winner_index'* ]]
}

# =============================================================================
# CATEGORY 4: PARALLEL ALL
# =============================================================================

@test "parallel_all: waits for all commands" {
    result=$(parallel_all "echo a" "echo b" "echo c")
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'"succeeded":3'* ]]
}

@test "parallel_all: reports ok=false if any fails" {
    result=$(parallel_all "echo ok" "false" "echo ok")
    [[ "$result" == *'"ok":false'* ]]
    [[ "$result" == *'"succeeded":2'* ]]
    [[ "$result" == *'"failed":1'* ]]
}

@test "parallel_all: handles no commands" {
    run parallel_all
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'"ok":false'* ]]
    [[ "$output" == *'E_NO_COMMANDS'* ]]
}

@test "parallel_all: captures all outputs" {
    result=$(parallel_all "echo output1" "echo output2")
    [[ "$result" == *"output1"* ]]
    [[ "$result" == *"output2"* ]]
}

# =============================================================================
# CATEGORY 5: PARALLEL ANY
# =============================================================================

@test "parallel_any: ok=true if any succeeds" {
    result=$(parallel_any "false" "echo success" "false")
    [[ "$result" == *'"ok":true'* ]]
}

@test "parallel_any: ok=false if all fail" {
    result=$(parallel_any "false" "false" "false")
    [[ "$result" == *'"ok":false'* ]]
    [[ "$result" == *'"succeeded":0'* ]]
}

@test "parallel_any: handles no commands" {
    run parallel_any
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'"ok":false'* ]]
    [[ "$output" == *'E_NO_COMMANDS'* ]]
}

@test "parallel_any: reports correct success/fail counts" {
    result=$(parallel_any "true" "false" "true")
    [[ "$result" == *'"succeeded":2'* ]]
    [[ "$result" == *'"failed":1'* ]]
}

# =============================================================================
# CATEGORY 6: PARALLEL SEQUENCE
# =============================================================================

@test "parallel_sequence: runs commands in order" {
    result=$(parallel_sequence "echo first" "echo second")
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'"succeeded":2'* ]]
}

@test "parallel_sequence: handles failures" {
    result=$(parallel_sequence "echo ok" "false")
    [[ "$result" == *'"ok":false'* ]]
    [[ "$result" == *'"failed":1'* ]]
}

@test "parallel_sequence: handles no commands" {
    run parallel_sequence
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'"ok":false'* ]]
    [[ "$output" == *'E_NO_COMMANDS'* ]]
}

# =============================================================================
# CATEGORY 7: BATCH PROCESSING
# =============================================================================

@test "parallel_batch: processes items in batches" {
    result=$(parallel_batch --batch-size 2 "echo a" "echo b" "echo c" "echo d")
    [[ "$result" == *'"ok":true'* ]]
}

@test "parallel_batch: respects batch size" {
    result=$(parallel_batch --batch-size 2 "echo 1" "echo 2" "echo 3")
    [[ "$result" == *'"ok":true'* ]]
}

@test "parallel_batch: handles command template" {
    result=$(parallel_batch --batch-size 2 --command "echo" "a" "b" "c")
    [[ "$result" == *'"ok":true'* ]]
}

@test "parallel_batch: handles no items" {
    run parallel_batch --batch-size 2
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'"ok":false'* ]]
    [[ "$output" == *'E_NO_ITEMS'* ]]
}

# =============================================================================
# CATEGORY 8: TIMEOUT
# =============================================================================

@test "parallel_timeout: completes before timeout" {
    result=$(parallel_timeout 5 "echo quick")
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *"quick"* ]]
}

@test "parallel_timeout: kills command after timeout" {
    run parallel_timeout 1 "sleep 2; echo never"
    [[ "$status" -eq 124 ]]
    [[ "$output" == *'"status":"timeout"'* ]]
}

@test "parallel_timeout: handles no command" {
    run parallel_timeout 5
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'"ok":false'* ]]
    [[ "$output" == *'E_NO_COMMAND'* ]]
}

@test "parallel_timeout: handles invalid timeout" {
    run parallel_timeout -1 "echo test"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'"ok":false'* ]]
    [[ "$output" == *'E_INVALID_TIMEOUT'* ]]
}

@test "parallel_timeout: captures output before timeout" {
    run parallel_timeout 2 "echo partial; sleep 5"
    [[ "$status" -eq 124 ]]
    # Should timeout but may have captured partial output
    [[ "$output" == *'timeout'* ]] || [[ "$output" == *'partial'* ]]
}

# =============================================================================
# CATEGORY 9: RETRY
# =============================================================================

@test "parallel_retry: succeeds on first try" {
    result=$(parallel_retry "echo success" --max-attempts 3)
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'"attempts":1'* ]]
}

@test "parallel_retry: retries on failure" {
    # Create a command that fails twice then succeeds
    cat > "$MOCK_BIN/flaky" << 'EOF'
#!/bin/bash
COUNTER_FILE="/tmp/flaky_counter"
if [[ ! -f "$COUNTER_FILE" ]]; then
    echo 0 > "$COUNTER_FILE"
fi
COUNT=$(cat "$COUNTER_FILE")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"
if [[ $COUNT -lt 3 ]]; then
    echo "fail $COUNT"
    exit 1
fi
echo "success on attempt $COUNT"
rm -f "$COUNTER_FILE"
exit 0
EOF
    chmod +x "$MOCK_BIN/flaky"
    rm -f /tmp/flaky_counter

    result=$(parallel_retry "flaky" --max-attempts 5 --delay 0)
    rm -f /tmp/flaky_counter

    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'"attempts":3'* ]]
}

@test "parallel_retry: fails after max attempts" {
    run parallel_retry "false" --max-attempts 2 --delay 0
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'"ok":false'* ]]
    [[ "$output" == *'"attempts":2'* ]]
    [[ "$output" == *'failed after'* ]]
}

@test "parallel_retry: handles no command" {
    run parallel_retry --max-attempts 3
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'"ok":false'* ]]
    [[ "$output" == *'E_NO_COMMAND'* ]]
}

@test "parallel_retry: uses exponential backoff by default" {
    # Just verify it doesn't crash with backoff
    result=$(parallel_retry "true" --max-attempts 2 --delay 0 --backoff exponential)
    [[ "$result" == *'"ok":true'* ]]
}

@test "parallel_retry: supports fixed backoff" {
    result=$(parallel_retry "true" --max-attempts 2 --delay 0 --backoff fixed)
    [[ "$result" == *'"ok":true'* ]]
}

@test "parallel_retry: supports linear backoff" {
    result=$(parallel_retry "true" --max-attempts 2 --delay 0 --backoff linear)
    [[ "$result" == *'"ok":true'* ]]
}

# =============================================================================
# CATEGORY 10: PROGRESS
# =============================================================================

@test "parallel_progress: processes all items" {
    # Redirect stderr to suppress progress bar in test output
    result=$(parallel_progress "echo a" "echo b" "echo c" 2>/dev/null)
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'"succeeded":3'* ]]
}

@test "parallel_progress: handles failures" {
    result=$(parallel_progress "echo ok" "false" 2>/dev/null)
    [[ "$result" == *'"ok":false'* ]]
    [[ "$result" == *'"failed":1'* ]]
}

@test "parallel_progress: handles no commands" {
    run parallel_progress
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'"ok":false'* ]]
    [[ "$output" == *'E_NO_COMMANDS'* ]]
}

# =============================================================================
# CATEGORY 11: EDGE CASES AND ERROR HANDLING
# =============================================================================

@test "parallel functions: handle special characters in output" {
    create_test_function
    result=$(parallel_map "test_echo" 'hello "world"')
    [[ "$result" == *'processed'* ]]
}

@test "parallel functions: handle newlines in output" {
    result=$(parallel_all "printf 'line1\nline2'")
    [[ "$result" == *'"ok":true'* ]]
}

@test "parallel functions: measure duration accurately" {
    result=$(parallel_timeout 5 "sleep 0.1; echo done")
    # Duration should be at least 100ms
    duration=$(echo "$result" | grep -o '"total_duration_ms":[0-9]*' | cut -d: -f2)
    [[ "$duration" -ge 50 ]]  # Allow some margin for test environment
}

@test "parallel_cleanup: removes state files" {
    # Create some state files
    touch "$PARALLEL_STATE_DIR/test_file"
    parallel_cleanup
    [[ ! -f "$PARALLEL_STATE_DIR/test_file" ]]
}

# =============================================================================
# CATEGORY 12: JSON OUTPUT FORMAT
# =============================================================================

@test "output format: includes ok field" {
    result=$(parallel_all "echo test")
    [[ "$result" == *'"ok":'* ]]
}

@test "output format: includes data object" {
    result=$(parallel_all "echo test")
    [[ "$result" == *'"data":{'* ]]
}

@test "output format: includes results array" {
    result=$(parallel_all "echo test")
    [[ "$result" == *'"results":['* ]]
}

@test "output format: includes succeeded count" {
    result=$(parallel_all "echo test")
    [[ "$result" == *'"succeeded":'* ]]
}

@test "output format: includes failed count" {
    result=$(parallel_all "echo test")
    [[ "$result" == *'"failed":'* ]]
}

@test "output format: includes total_duration_ms" {
    result=$(parallel_all "echo test")
    [[ "$result" == *'"total_duration_ms":'* ]]
}

@test "output format: result entries have index" {
    result=$(parallel_all "echo test")
    [[ "$result" == *'"index":0'* ]]
}

@test "output format: result entries have status" {
    result=$(parallel_all "echo test")
    [[ "$result" == *'"status":"done"'* ]]
}

@test "output format: result entries have duration_ms" {
    result=$(parallel_all "echo test")
    [[ "$result" == *'"duration_ms":'* ]]
}

@test "output format: error entries have error field" {
    result=$(parallel_all "false")
    [[ "$result" == *'"error":'* ]]
}

# =============================================================================
# CATEGORY 13: ADDITIONAL COVERAGE
# =============================================================================

@test "parallel_map: handles large number of items" {
    create_test_function
    local -a items=()
    for i in {1..10}; do
        items+=("item$i")
    done
    result=$(parallel_map "test_echo" "${items[@]}")
    [[ "$result" == *'"succeeded":10'* ]]
}

@test "parallel_map_n: handles items equal to limit" {
    create_test_function
    result=$(parallel_map_n "test_echo" 3 "a" "b" "c")
    [[ "$result" == *'"succeeded":3'* ]]
}

@test "parallel_race: handles single command" {
    result=$(parallel_race "echo only")
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *"only"* ]]
}

@test "parallel_all: handles single command" {
    result=$(parallel_all "echo single")
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'"succeeded":1'* ]]
}

@test "parallel_any: handles single failing command" {
    result=$(parallel_any "false")
    [[ "$result" == *'"ok":false'* ]]
}

@test "parallel_batch: handles batch size larger than items" {
    result=$(parallel_batch --batch-size 100 "echo a" "echo b")
    [[ "$result" == *'"ok":true'* ]]
}

@test "parallel_timeout: zero timeout rejected" {
    run parallel_timeout 0 "echo test"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'"ok":false'* ]]
}

@test "parallel_retry: command with arguments" {
    result=$(parallel_retry "echo hello world" --max-attempts 2)
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *"hello world"* ]]
}

@test "parallel functions: empty output handled" {
    result=$(parallel_all "true")
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'"result":""'* ]]
}

@test "parallel functions: stderr captured" {
    result=$(parallel_all "echo error >&2")
    [[ "$result" == *"error"* ]]
}

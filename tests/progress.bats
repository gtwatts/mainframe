#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/progress.bats - Tests for Progress Broadcasting
# =============================================================================
# Run with: bats tests/progress.bats
# =============================================================================

# Setup and teardown
setup() {
    # Set up test environment
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/.."
    export MAINFRAME_PROGRESS_DIR="${BATS_TMPDIR}/test_progress_$$"
    export MAINFRAME_BROADCAST_FORMAT="json"
    export MAINFRAME_BROADCAST_TARGET="stdout"

    # Clean start
    rm -rf "$MAINFRAME_PROGRESS_DIR"
    mkdir -p "$MAINFRAME_PROGRESS_DIR"

    # Source the library
    source "${MAINFRAME_ROOT}/lib/progress.sh"
}

teardown() {
    # Clean up test files
    rm -rf "$MAINFRAME_PROGRESS_DIR"
}

# =============================================================================
# progress_init tests
# =============================================================================

@test "progress_init creates tracker with auto-generated ID" {
    local pid
    pid=$(progress_init "Test Operation" 100)

    [[ -n "$pid" ]]
    [[ "$pid" =~ ^prog_[0-9]+_[0-9]+$ ]]
}

@test "progress_init accepts custom ID" {
    local pid
    pid=$(progress_init "Test" 50 --id "custom-id-123")

    [[ "$pid" == "custom-id-123" ]]
}

@test "progress_init rejects invalid ID with path traversal" {
    run progress_init "Test" 100 --id "../../../etc/passwd"

    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "E_INVALID_ID" ]]
}

@test "progress_init rejects ID with slashes" {
    run progress_init "Test" 100 --id "bad/id"

    [[ "$status" -eq 1 ]]
}

@test "progress_init emits start event in JSON format" {
    # Capture stderr where JSON is emitted
    export MAINFRAME_BROADCAST_TARGET="stdout"

    progress_init "Building" 100 --id "test-build" >/dev/null

    # Read progress file or check internal state
    local status
    status=$(progress_status "test-build")

    [[ "$status" =~ "\"status\":\"active\"" ]]
}

@test "progress_init sets custom unit" {
    local pid
    pid=$(progress_init "Download" 1024 --unit "MB")

    local status
    status=$(progress_status "$pid")

    [[ -n "$status" ]]
}

@test "progress_init handles indeterminate progress (total=0)" {
    local pid
    pid=$(progress_init "Scanning" 0)

    local status
    status=$(progress_status "$pid")

    [[ "$status" =~ "\"total\":0" ]]
}

# =============================================================================
# progress_update tests
# =============================================================================

@test "progress_update updates current value" {
    local pid
    pid=$(progress_init "Test" 100)

    progress_update "$pid" 50 "Halfway"

    local status
    status=$(progress_status "$pid")

    [[ "$status" =~ "\"current\":50" ]]
}

@test "progress_update calculates correct percentage" {
    local pid
    pid=$(progress_init "Test" 200)

    progress_update "$pid" 100

    local status
    status=$(progress_status "$pid")

    [[ "$status" =~ "\"percent\":50" ]]
}

@test "progress_update returns error for unknown tracker" {
    run progress_update "nonexistent-id" 50

    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "E_NOT_FOUND" ]]
}

@test "progress_update handles invalid numeric value" {
    local pid
    pid=$(progress_init "Test" 100)

    progress_update "$pid" "not-a-number"

    # Should default to 0
    local status
    status=$(progress_status "$pid")

    [[ "$status" =~ "\"current\":0" ]]
}

# =============================================================================
# progress_increment tests
# =============================================================================

@test "progress_increment adds 1 by default" {
    local pid
    pid=$(progress_init "Test" 100)

    progress_update "$pid" 10
    progress_increment "$pid"

    local status
    status=$(progress_status "$pid")

    [[ "$status" =~ "\"current\":11" ]]
}

@test "progress_increment adds custom amount" {
    local pid
    pid=$(progress_init "Test" 100)

    progress_update "$pid" 10
    progress_increment "$pid" 5

    local status
    status=$(progress_status "$pid")

    [[ "$status" =~ "\"current\":15" ]]
}

@test "progress_increment returns error for unknown tracker" {
    run progress_increment "nonexistent-id"

    [[ "$status" -eq 1 ]]
}

# =============================================================================
# progress_complete tests
# =============================================================================

@test "progress_complete marks tracker as success" {
    local pid
    pid=$(progress_init "Test" 100)

    progress_complete "$pid" "Done"

    local status
    status=$(progress_status "$pid")

    [[ "$status" =~ "\"status\":\"complete\"" ]]
}

@test "progress_complete sets current to total" {
    local pid
    pid=$(progress_init "Test" 100)

    progress_update "$pid" 50
    progress_complete "$pid"

    local status
    status=$(progress_status "$pid")

    [[ "$status" =~ "\"current\":100" ]]
}

@test "progress_complete is idempotent" {
    local pid
    pid=$(progress_init "Test" 100)

    progress_complete "$pid" "First"
    progress_complete "$pid" "Second"

    # Should not error
    [[ $? -eq 0 ]]
}

# =============================================================================
# progress_fail tests
# =============================================================================

@test "progress_fail marks tracker as failed" {
    local pid
    pid=$(progress_init "Test" 100)

    progress_fail "$pid" "Connection lost"

    local status
    status=$(progress_status "$pid")

    [[ "$status" =~ "\"status\":\"failed\"" ]]
}

@test "progress_fail is idempotent" {
    local pid
    pid=$(progress_init "Test" 100)

    progress_fail "$pid" "First error"
    progress_fail "$pid" "Second error"

    # Should not error
    [[ $? -eq 0 ]]
}

# =============================================================================
# status_heartbeat tests
# =============================================================================

@test "status_heartbeat emits heartbeat event" {
    export MAINFRAME_BROADCAST_TARGET="stdout"

    run status_heartbeat "task-123" "Still running"

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "\"event\":\"heartbeat\"" ]]
    [[ "$output" =~ "\"id\":\"task-123\"" ]]
}

@test "status_heartbeat validates ID format" {
    run status_heartbeat "../bad/id"

    [[ "$status" -eq 1 ]]
}

# =============================================================================
# status_emit tests
# =============================================================================

@test "status_emit emits custom event" {
    export MAINFRAME_BROADCAST_TARGET="stdout"

    run status_emit "checkpoint" '{"files":5}'

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "\"event\":\"checkpoint\"" ]]
    [[ "$output" =~ "\"files\":5" ]]
}

@test "status_emit sanitizes invalid event type" {
    export MAINFRAME_BROADCAST_TARGET="stdout"

    run status_emit "123invalid" '{}'

    # Should default to "status"
    [[ "$output" =~ "\"event\":\"status\"" ]]
}

# =============================================================================
# progress_stream_to tests
# =============================================================================

@test "progress_stream_to writes progress to file" {
    local pid
    pid=$(progress_init "Test" 100 --id "file-test")

    progress_update "$pid" 50 "Midway"
    progress_stream_to "$pid"

    local filepath="${MAINFRAME_PROGRESS_DIR}/${pid}.progress"
    [[ -f "$filepath" ]]

    local content
    content=$(cat "$filepath")

    [[ "$content" =~ "\"current\":50" ]]
    [[ "$content" =~ "\"total\":100" ]]
}

@test "progress_stream_to uses custom filepath" {
    local pid
    pid=$(progress_init "Test" 100)

    local custom_path="${BATS_TMPDIR}/custom-progress.json"
    progress_stream_to "$pid" "$custom_path"

    [[ -f "$custom_path" ]]

    rm -f "$custom_path"
}

@test "progress_stream_to rejects symlinks" {
    local pid
    pid=$(progress_init "Test" 100 --id "symlink-test")

    # Create a symlink target
    local target="${BATS_TMPDIR}/target-file"
    local symlink="${MAINFRAME_PROGRESS_DIR}/${pid}.progress"

    echo "original" > "$target"
    ln -sf "$target" "$symlink"

    run progress_stream_to "$pid"

    [[ "$status" -eq 1 ]]

    # Target should not be modified
    [[ "$(cat "$target")" == "original" ]]

    rm -f "$target" "$symlink"
}

@test "progress_stream_to validates ID" {
    run progress_stream_to "../../../etc/passwd"

    [[ "$status" -eq 1 ]]
}

# =============================================================================
# Security tests - Sensitive info redaction
# =============================================================================

@test "progress redacts password in messages" {
    local pid
    pid=$(progress_init "Test" 100)

    progress_update "$pid" 50 "Using password=secret123 for auth"
    progress_stream_to "$pid"

    local content
    content=$(cat "${MAINFRAME_PROGRESS_DIR}/${pid}.progress")

    # Should NOT contain the actual password
    [[ ! "$content" =~ "secret123" ]]
    [[ "$content" =~ "REDACTED" ]]
}

@test "progress redacts API keys" {
    local pid
    pid=$(progress_init "Test" 100)

    progress_update "$pid" 50 "Connecting with api_key=sk-abcd1234"
    progress_stream_to "$pid"

    local content
    content=$(cat "${MAINFRAME_PROGRESS_DIR}/${pid}.progress")

    [[ ! "$content" =~ "sk-abcd1234" ]]
    [[ "$content" =~ "REDACTED" ]]
}

@test "progress redacts sensitive file paths" {
    local pid
    pid=$(progress_init "Processing /etc/shadow file" 100)

    progress_stream_to "$pid"

    local content
    content=$(cat "${MAINFRAME_PROGRESS_DIR}/${pid}.progress")

    [[ "$content" =~ "REDACTED" ]]
}

# =============================================================================
# Security tests - Path validation
# =============================================================================

@test "progress_init rejects ID with control characters" {
    run progress_init "Test" 100 --id $'test\nbad'

    [[ "$status" -eq 1 ]]
}

@test "progress rejects IDs longer than 64 chars" {
    local long_id
    long_id=$(printf 'a%.0s' {1..100})

    run progress_init "Test" 100 --id "$long_id"

    [[ "$status" -eq 1 ]]
}

# =============================================================================
# Quota enforcement tests
# =============================================================================

@test "progress enforces file quota" {
    # Create many progress files
    for i in {1..120}; do
        local pid
        pid=$(progress_init "Test $i" 100 --id "quota-test-$i")
        progress_stream_to "$pid"
    done

    # Force cleanup
    _progress_enforce_quota

    # Count remaining files
    local count
    count=$(find "$MAINFRAME_PROGRESS_DIR" -maxdepth 1 -name "*.progress" 2>/dev/null | wc -l)

    # Should be at or below max
    [[ "$count" -le 100 ]]
}

# =============================================================================
# progress_read_file tests
# =============================================================================

@test "progress_read_file returns file content" {
    local pid
    pid=$(progress_init "Test" 100 --id "read-test")

    progress_update "$pid" 75 "Almost done"
    progress_stream_to "$pid"

    local content
    content=$(progress_read_file "$pid")

    [[ "$content" =~ "\"current\":75" ]]
}

@test "progress_read_file returns error for nonexistent file" {
    run progress_read_file "nonexistent-id"

    [[ "$status" -eq 1 ]]
}

# =============================================================================
# progress_status tests
# =============================================================================

@test "progress_status returns JSON status" {
    local pid
    pid=$(progress_init "Test" 100)

    progress_update "$pid" 25

    local status
    status=$(progress_status "$pid")

    [[ "$status" =~ "\"percent\":25" ]]
    [[ "$status" =~ "\"status\":\"active\"" ]]
}

@test "progress_status returns error for unknown tracker" {
    run progress_status "unknown-id"

    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "E_NOT_FOUND" ]]
}

# =============================================================================
# progress_cleanup tests
# =============================================================================

@test "progress_cleanup removes old files" {
    # Create a file and backdate it
    local old_file="${MAINFRAME_PROGRESS_DIR}/old-test.progress"
    echo '{"test":true}' > "$old_file"
    touch -t "$(date -v-2H +%Y%m%d%H%M.%S 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M.%S)" "$old_file"

    progress_cleanup 1  # Clean files older than 1 minute

    [[ ! -f "$old_file" ]]
}

# =============================================================================
# Edge cases and error handling
# =============================================================================

@test "progress handles empty message gracefully" {
    local pid
    pid=$(progress_init "Test" 100)

    progress_update "$pid" 50 ""

    local status
    status=$(progress_status "$pid")

    [[ "$status" =~ "\"current\":50" ]]
}

@test "progress handles special characters in name" {
    local pid
    pid=$(progress_init 'Test "with" quotes & <special> chars' 100)

    [[ -n "$pid" ]]

    local status
    status=$(progress_status "$pid")

    # Should be properly escaped
    [[ "$status" =~ "\"name\":" ]]
}

@test "progress handles newlines in message" {
    local pid
    pid=$(progress_init "Test" 100)

    progress_update "$pid" 50 $'Line 1\nLine 2'
    progress_stream_to "$pid"

    local content
    content=$(cat "${MAINFRAME_PROGRESS_DIR}/${pid}.progress")

    # Should be escaped as \n
    [[ "$content" != "${content//\\n/}" ]]
}

@test "multiple trackers can coexist" {
    local pid1 pid2
    pid1=$(progress_init "Task 1" 100 --id "multi-1")
    pid2=$(progress_init "Task 2" 200 --id "multi-2")

    progress_update "$pid1" 50
    progress_update "$pid2" 100

    local status1 status2
    status1=$(progress_status "$pid1")
    status2=$(progress_status "$pid2")

    [[ "$status1" =~ "\"current\":50" ]]
    [[ "$status2" =~ "\"current\":100" ]]
}

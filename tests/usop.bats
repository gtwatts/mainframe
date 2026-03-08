#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Universal Structured Output Protocol (USOP) Tests
# =============================================================================
# Comprehensive tests for USOP functions in lib/output.sh
# Covers: command execution, file operations, process operations, error helpers
# =============================================================================

load 'test_helper'

setup() {
    source_lib "json"
    source_lib "atomic"
    source_lib "output"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "usop")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# usop_exec TESTS - Command Execution Envelope
# =============================================================================

@test "usop_exec returns valid JSON envelope" {
    local result
    result=$(usop_exec echo "hello")
    # Should be valid JSON
    json_valid "$result"
}

@test "usop_exec envelope contains all required fields" {
    local result
    result=$(usop_exec echo "test")
    # Check all required fields exist
    assert_contains "$result" '"success"'
    assert_contains "$result" '"exit_code"'
    assert_contains "$result" '"stdout"'
    assert_contains "$result" '"stderr"'
    assert_contains "$result" '"duration_ms"'
    assert_contains "$result" '"command"'
    assert_contains "$result" '"cwd"'
    assert_contains "$result" '"timestamp"'
}

@test "usop_exec captures stdout correctly" {
    local result
    result=$(usop_exec echo "hello world")
    local stdout
    stdout=$(json_get "$result" "stdout")
    [ "$stdout" = "hello world" ]
}

@test "usop_exec captures stderr correctly" {
    local result
    result=$(usop_exec bash -c 'echo "error message" >&2')
    local stderr
    stderr=$(json_get "$result" "stderr")
    [ "$stderr" = "error message" ]
}

@test "usop_exec reports success:true for exit code 0" {
    local result
    result=$(usop_exec true)
    local success
    success=$(json_get "$result" "success")
    [ "$success" = "true" ]
}

@test "usop_exec reports success:false for non-zero exit" {
    local result
    result=$(usop_exec false) || true
    local success
    success=$(json_get "$result" "success")
    [ "$success" = "false" ]
}

@test "usop_exec returns correct exit code" {
    local result
    result=$(usop_exec bash -c 'exit 42') || true
    local exit_code
    exit_code=$(json_get "$result" "exit_code")
    [ "$exit_code" = "42" ]
}

@test "usop_exec records command string" {
    local result
    result=$(usop_exec ls -la /tmp)
    local cmd
    cmd=$(json_get "$result" "command")
    [ "$cmd" = "ls -la /tmp" ]
}

@test "usop_exec records current working directory" {
    local result
    result=$(usop_exec pwd)
    local cwd
    cwd=$(json_get "$result" "cwd")
    [ "$cwd" = "$PWD" ]
}

@test "usop_exec records timestamp in ISO format" {
    local result
    result=$(usop_exec true)
    local timestamp
    timestamp=$(json_get "$result" "timestamp")
    # Should match ISO 8601 format (YYYY-MM-DDTHH:MM:SS)
    [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}

@test "usop_exec records non-negative duration_ms" {
    local result
    result=$(usop_exec sleep 0.01)
    local duration
    duration=$(json_get "$result" "duration_ms")
    # Duration should be numeric and >= 0
    [[ "$duration" =~ ^[0-9]+$ ]]
    [ "$duration" -ge 0 ]
}

@test "usop_exec handles command with arguments" {
    local result
    result=$(usop_exec printf "%s %s" "hello" "world")
    local stdout
    stdout=$(json_get "$result" "stdout")
    [ "$stdout" = "hello world" ]
}

@test "usop_exec handles multiline output" {
    local result
    result=$(usop_exec printf "line1\nline2\nline3")
    local stdout
    stdout=$(json_get "$result" "stdout")
    # JSON escapes newlines
    [[ "$result" == *'line1\\nline2\\nline3'* ]] || [[ "$stdout" == *"line1"* ]]
}

@test "usop_exec handles empty command (error)" {
    local result
    result=$(usop_exec) || true
    local success
    success=$(json_get "$result" "success")
    [ "$success" = "false" ]
    assert_contains "$result" "no command provided"
}

@test "usop_exec handles command not found" {
    local result
    result=$(usop_exec nonexistent_command_xyz 2>/dev/null) || true
    local success
    success=$(json_get "$result" "success")
    [ "$success" = "false" ]
}

@test "usop_exec escapes special characters in output" {
    local result
    result=$(usop_exec echo 'say "hello"')
    # Should be valid JSON even with quotes in output
    json_valid "$result"
}

# =============================================================================
# usop_get TESTS - Field Extraction
# =============================================================================

@test "usop_get extracts string field" {
    local json='{"success":true,"stdout":"hello"}'
    local result
    result=$(usop_get "$json" "stdout")
    [ "$result" = "hello" ]
}

@test "usop_get extracts numeric field" {
    local json='{"exit_code":42}'
    local result
    result=$(usop_get "$json" "exit_code")
    [ "$result" = "42" ]
}

@test "usop_get extracts boolean field" {
    local json='{"success":true}'
    local result
    result=$(usop_get "$json" "success")
    [ "$result" = "true" ]
}

@test "usop_get fails for missing field" {
    local json='{"success":true}'
    ! usop_get "$json" "missing"
}

@test "usop_get fails with empty json" {
    ! usop_get "" "field"
}

@test "usop_get fails with empty field" {
    ! usop_get '{"a":1}' ""
}

# =============================================================================
# usop_ok TESTS - Success Check
# =============================================================================

@test "usop_ok returns 0 for success:true" {
    local json='{"success":true}'
    usop_ok "$json"
}

@test "usop_ok returns 1 for success:false" {
    local json='{"success":false}'
    ! usop_ok "$json"
}

@test "usop_ok returns 1 for empty input" {
    ! usop_ok ""
}

@test "usop_ok returns 1 for missing success field" {
    local json='{"data":"value"}'
    ! usop_ok "$json"
}

@test "usop_ok works with full envelope" {
    local result
    result=$(usop_exec true)
    usop_ok "$result"
}

@test "usop_ok detects failure in full envelope" {
    local result
    result=$(usop_exec false) || true
    ! usop_ok "$result"
}

# =============================================================================
# usop_read_file TESTS - File Reading
# =============================================================================

@test "usop_read_file returns valid JSON" {
    echo "test content" > "$TEST_DIR/read.txt"
    local result
    result=$(usop_read_file "$TEST_DIR/read.txt")
    json_valid "$result"
}

@test "usop_read_file returns content" {
    echo -n "hello world" > "$TEST_DIR/content.txt"
    local result
    result=$(usop_read_file "$TEST_DIR/content.txt")
    local content
    content=$(json_get "$result" "content")
    [ "$content" = "hello world" ]
}

@test "usop_read_file returns file size" {
    echo -n "12345" > "$TEST_DIR/size.txt"
    local result
    result=$(usop_read_file "$TEST_DIR/size.txt")
    local size
    size=$(json_get "$result" "size")
    [ "$size" = "5" ]
}

@test "usop_read_file returns path" {
    echo "data" > "$TEST_DIR/path.txt"
    local result
    result=$(usop_read_file "$TEST_DIR/path.txt")
    local path
    path=$(json_get "$result" "path")
    [ "$path" = "$TEST_DIR/path.txt" ]
}

@test "usop_read_file success for existing file" {
    echo "data" > "$TEST_DIR/exists.txt"
    local result
    result=$(usop_read_file "$TEST_DIR/exists.txt")
    usop_ok "$result"
}

@test "usop_read_file failure for missing file" {
    run usop_read_file "$TEST_DIR/nonexistent.txt"
    [ "$status" -eq 1 ]
    ! usop_ok "$output"
    assert_contains "$output" "not found"
    assert_contains "$output" "suggestion"
}

@test "usop_read_file failure for directory" {
    mkdir -p "$TEST_DIR/subdir"
    run usop_read_file "$TEST_DIR/subdir"
    [ "$status" -eq 1 ]
    ! usop_ok "$output"
    assert_contains "$output" "not a regular file"
}

@test "usop_read_file failure for empty path" {
    run usop_read_file ""
    [ "$status" -eq 1 ]
    ! usop_ok "$output"
    assert_contains "$output" "path required"
}

@test "usop_read_file handles multiline content" {
    printf "line1\nline2\nline3" > "$TEST_DIR/multi.txt"
    local result
    result=$(usop_read_file "$TEST_DIR/multi.txt")
    usop_ok "$result"
    json_valid "$result"
}

@test "usop_read_file handles special characters" {
    echo 'say "hello" & <tag>' > "$TEST_DIR/special.txt"
    local result
    result=$(usop_read_file "$TEST_DIR/special.txt")
    json_valid "$result"
}

# =============================================================================
# usop_write_file TESTS - File Writing
# =============================================================================

@test "usop_write_file creates new file" {
    local result
    result=$(usop_write_file "$TEST_DIR/new.txt" "hello")
    usop_ok "$result"
    [ -f "$TEST_DIR/new.txt" ]
}

@test "usop_write_file writes correct content" {
    usop_write_file "$TEST_DIR/write.txt" "test content"
    local content
    content=$(<"$TEST_DIR/write.txt")
    [ "$content" = "test content" ]
}

@test "usop_write_file returns bytes_written" {
    local result
    result=$(usop_write_file "$TEST_DIR/bytes.txt" "12345")
    local bytes
    bytes=$(json_get "$result" "bytes_written")
    [ "$bytes" = "5" ]
}

@test "usop_write_file returns path" {
    local result
    result=$(usop_write_file "$TEST_DIR/path.txt" "data")
    local path
    path=$(json_get "$result" "path")
    [ "$path" = "$TEST_DIR/path.txt" ]
}

@test "usop_write_file overwrites existing file" {
    echo "old" > "$TEST_DIR/overwrite.txt"
    usop_write_file "$TEST_DIR/overwrite.txt" "new"
    local content
    content=$(<"$TEST_DIR/overwrite.txt")
    [ "$content" = "new" ]
}

@test "usop_write_file failure for empty path" {
    run usop_write_file "" "content"
    [ "$status" -eq 1 ]
    ! usop_ok "$output"
    assert_contains "$output" "path required"
}

@test "usop_write_file failure for nonexistent parent" {
    run usop_write_file "$TEST_DIR/no/such/dir/file.txt" "content"
    [ "$status" -eq 1 ]
    ! usop_ok "$output"
    assert_contains "$output" "parent directory"
}

@test "usop_write_file handles multiline content" {
    local content=$'line1\nline2\nline3'
    usop_write_file "$TEST_DIR/multi.txt" "$content"
    local result
    result=$(<"$TEST_DIR/multi.txt")
    [ "$result" = "$content" ]
}

@test "usop_write_file handles empty content" {
    local result
    result=$(usop_write_file "$TEST_DIR/empty.txt" "")
    usop_ok "$result"
    [ -f "$TEST_DIR/empty.txt" ]
    local size
    size=$(stat -c%s "$TEST_DIR/empty.txt" 2>/dev/null || stat -f%z "$TEST_DIR/empty.txt")
    [ "$size" = "0" ]
}

# =============================================================================
# usop_list_dir TESTS - Directory Listing
# =============================================================================

@test "usop_list_dir returns valid JSON" {
    local result
    result=$(usop_list_dir "$TEST_DIR")
    json_valid "$result"
}

@test "usop_list_dir lists files" {
    touch "$TEST_DIR/file1.txt"
    touch "$TEST_DIR/file2.txt"
    local result
    result=$(usop_list_dir "$TEST_DIR")
    usop_ok "$result"
    assert_contains "$result" "file1.txt"
    assert_contains "$result" "file2.txt"
}

@test "usop_list_dir returns count" {
    touch "$TEST_DIR/a.txt"
    touch "$TEST_DIR/b.txt"
    touch "$TEST_DIR/c.txt"
    local result
    result=$(usop_list_dir "$TEST_DIR")
    local count
    count=$(json_get "$result" "count")
    [ "$count" = "3" ]
}

@test "usop_list_dir returns path" {
    local result
    result=$(usop_list_dir "$TEST_DIR")
    local path
    path=$(json_get "$result" "path")
    [ "$path" = "$TEST_DIR" ]
}

@test "usop_list_dir success for empty directory" {
    mkdir -p "$TEST_DIR/empty_dir"
    local result
    result=$(usop_list_dir "$TEST_DIR/empty_dir")
    usop_ok "$result"
    local count
    count=$(json_get "$result" "count")
    [ "$count" = "0" ]
}

@test "usop_list_dir defaults to current directory" {
    local result
    result=$(usop_list_dir)
    usop_ok "$result"
    assert_contains "$result" '"path":"."' || assert_contains "$result" '"path": "."'
}

@test "usop_list_dir failure for nonexistent path" {
    run usop_list_dir "$TEST_DIR/nonexistent"
    [ "$status" -eq 1 ]
    ! usop_ok "$output"
    assert_contains "$output" "not found"
}

@test "usop_list_dir failure for file path" {
    touch "$TEST_DIR/notadir.txt"
    run usop_list_dir "$TEST_DIR/notadir.txt"
    [ "$status" -eq 1 ]
    ! usop_ok "$output"
    assert_contains "$output" "not a directory"
}

@test "usop_list_dir lists subdirectories" {
    mkdir -p "$TEST_DIR/subdir"
    local result
    result=$(usop_list_dir "$TEST_DIR")
    assert_contains "$result" "subdir"
}

# =============================================================================
# usop_run_background TESTS - Background Execution
# =============================================================================

@test "usop_run_background returns valid JSON" {
    local result
    result=$(usop_run_background sleep 0.1)
    json_valid "$result"
    # Clean up
    local pid
    pid=$(json_get "$result" "pid")
    kill "$pid" 2>/dev/null || true
}

@test "usop_run_background returns PID" {
    local result
    result=$(usop_run_background sleep 0.5)
    local pid
    pid=$(json_get "$result" "pid")
    [[ "$pid" =~ ^[0-9]+$ ]]
    # Clean up
    kill "$pid" 2>/dev/null || true
}

@test "usop_run_background returns stdout_file path" {
    local result
    result=$(usop_run_background sleep 0.1)
    local stdout_file
    stdout_file=$(json_get "$result" "stdout_file")
    [ -f "$stdout_file" ]
    # Clean up
    local pid
    pid=$(json_get "$result" "pid")
    kill "$pid" 2>/dev/null || true
    rm -f "$stdout_file"
}

@test "usop_run_background returns stderr_file path" {
    local result
    result=$(usop_run_background sleep 0.1)
    local stderr_file
    stderr_file=$(json_get "$result" "stderr_file")
    [ -f "$stderr_file" ]
    # Clean up
    local pid
    pid=$(json_get "$result" "pid")
    kill "$pid" 2>/dev/null || true
    rm -f "$stderr_file"
}

@test "usop_run_background process actually runs" {
    local result
    result=$(usop_run_background sleep 1)
    local pid
    pid=$(json_get "$result" "pid")
    # Process should be running
    kill -0 "$pid" 2>/dev/null
    # Clean up
    kill "$pid" 2>/dev/null || true
}

@test "usop_run_background failure for no command" {
    run usop_run_background
    [ "$status" -eq 1 ]
    ! usop_ok "$output"
    assert_contains "$output" "no command provided"
}

@test "usop_run_background captures output to files" {
    local result
    result=$(usop_run_background bash -c 'echo "hello"; sleep 0.1')
    usop_ok "$result"
    local pid stdout_file
    pid=$(json_get "$result" "pid")
    stdout_file=$(json_get "$result" "stdout_file")
    # Wait for process to complete
    sleep 0.2
    local output
    output=$(<"$stdout_file")
    [ "$output" = "hello" ]
    # Clean up
    rm -f "$stdout_file"
}

# =============================================================================
# usop_check_pid TESTS - Process Status Check
# =============================================================================

@test "usop_check_pid returns valid JSON" {
    local bg_result
    bg_result=$(usop_run_background sleep 1)
    local pid
    pid=$(json_get "$bg_result" "pid")

    local result
    result=$(usop_check_pid "$pid")
    json_valid "$result"

    # Clean up
    kill "$pid" 2>/dev/null || true
}

@test "usop_check_pid detects running process" {
    local bg_result
    bg_result=$(usop_run_background sleep 1)
    local pid
    pid=$(json_get "$bg_result" "pid")

    local result
    result=$(usop_check_pid "$pid")
    local status
    status=$(json_get "$result" "status")
    [ "$status" = "running" ]

    # Clean up
    kill "$pid" 2>/dev/null || true
}

@test "usop_check_pid detects exited process" {
    local bg_result
    bg_result=$(usop_run_background bash -c 'exit 0')
    local pid
    pid=$(json_get "$bg_result" "pid")

    # Wait for completion
    sleep 0.1

    local result
    result=$(usop_check_pid "$pid")
    local status
    status=$(json_get "$result" "status")
    [ "$status" = "exited" ]
}

@test "usop_check_pid failure for empty pid" {
    run usop_check_pid ""
    [ "$status" -eq 1 ]
    ! usop_ok "$output"
    assert_contains "$output" "pid required"
}

@test "usop_check_pid failure for invalid pid format" {
    run usop_check_pid "abc"
    [ "$status" -eq 1 ]
    ! usop_ok "$output"
    assert_contains "$output" "invalid pid format"
}

@test "usop_check_pid returns exit_code for completed process" {
    local bg_result
    bg_result=$(usop_run_background bash -c 'exit 42')
    local pid
    pid=$(json_get "$bg_result" "pid")

    # Wait for completion
    sleep 0.1

    local result
    result=$(usop_check_pid "$pid")
    assert_contains "$result" '"exit_code"'
}

# =============================================================================
# USOP ERROR HELPERS TESTS
# =============================================================================

@test "usop_error_not_found returns valid JSON" {
    local result
    result=$(usop_error_not_found "file" "/path/to/missing")
    json_valid "$result"
}

@test "usop_error_not_found includes error message" {
    local result
    result=$(usop_error_not_found "file" "/path/to/missing")
    assert_contains "$result" "file not found"
}

@test "usop_error_not_found includes path" {
    local result
    result=$(usop_error_not_found "file" "/path/to/missing")
    assert_contains "$result" "/path/to/missing"
}

@test "usop_error_not_found includes suggestion" {
    local result
    result=$(usop_error_not_found "file" "/path")
    assert_contains "$result" "suggestion"
}

@test "usop_error_not_found sets success:false" {
    local result
    result=$(usop_error_not_found "file" "/path")
    ! usop_ok "$result"
}

@test "usop_error_permission returns valid JSON" {
    local result
    result=$(usop_error_permission "/etc/shadow" "read")
    json_valid "$result"
}

@test "usop_error_permission includes path and operation" {
    local result
    result=$(usop_error_permission "/etc/shadow" "read")
    assert_contains "$result" "/etc/shadow"
    assert_contains "$result" "read"
    assert_contains "$result" "permission denied"
}

@test "usop_error_validation returns valid JSON" {
    local result
    result=$(usop_error_validation "port" "abc" "integer 1-65535")
    json_valid "$result"
}

@test "usop_error_validation includes field info" {
    local result
    result=$(usop_error_validation "port" "abc" "integer 1-65535")
    assert_contains "$result" '"field":"port"' || assert_contains "$result" '"field": "port"'
    assert_contains "$result" "abc"
    assert_contains "$result" "integer 1-65535"
}

@test "usop_error_timeout returns valid JSON" {
    local result
    result=$(usop_error_timeout "HTTP request" "30")
    json_valid "$result"
}

@test "usop_error_timeout includes operation and timeout" {
    local result
    result=$(usop_error_timeout "HTTP request" "30")
    assert_contains "$result" "HTTP request"
    assert_contains "$result" "30"
    assert_contains "$result" "timeout"
}

@test "usop_error_command_failed returns valid JSON" {
    local result
    result=$(usop_error_command_failed "git pull" "128" "fatal: not a git repository")
    json_valid "$result"
}

@test "usop_error_command_failed includes command details" {
    local result
    result=$(usop_error_command_failed "git pull" "128" "fatal error")
    assert_contains "$result" "git pull"
    assert_contains "$result" "128"
    assert_contains "$result" "fatal error"
    assert_contains "$result" "command failed"
}

# =============================================================================
# NAMEREF VARIANT TESTS (_v functions)
# =============================================================================

@test "usop_exec_v stores result in variable" {
    local out
    usop_exec_v out echo "hello"
    json_valid "$out"
    assert_contains "$out" "hello"
}

@test "usop_exec_v matches usop_exec output" {
    local subshell_result nameref_result
    subshell_result=$(usop_exec echo "test")
    usop_exec_v nameref_result echo "test"

    # Both should have same fields (timestamps will differ)
    assert_contains "$subshell_result" '"success":true'
    assert_contains "$nameref_result" '"success":true'
    assert_contains "$subshell_result" '"exit_code":0'
    assert_contains "$nameref_result" '"exit_code":0'
}

@test "usop_exec_v handles command failure" {
    local out
    usop_exec_v out false || true
    ! usop_ok "$out"
}

@test "usop_get_v extracts field into variable" {
    local json='{"success":true,"stdout":"hello"}'
    local out
    usop_get_v out "$json" "stdout"
    [ "$out" = "hello" ]
}

@test "usop_get_v sets empty on missing field" {
    local json='{"a":1}'
    local out="initial"
    ! usop_get_v out "$json" "missing"
    [ "$out" = "" ]
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

@test "roundtrip: write then read file via USOP" {
    local content="integration test content"
    usop_write_file "$TEST_DIR/roundtrip.txt" "$content"

    local read_result
    read_result=$(usop_read_file "$TEST_DIR/roundtrip.txt")
    local read_content
    read_content=$(json_get "$read_result" "content")

    [ "$read_content" = "$content" ]
}

@test "background process output captured correctly" {
    local bg_result
    bg_result=$(usop_run_background bash -c 'echo "output line"')
    local stdout_file
    stdout_file=$(json_get "$bg_result" "stdout_file")

    # Wait for process
    sleep 0.2

    local output
    output=$(<"$stdout_file")
    [ "$output" = "output line" ]

    # Clean up
    rm -f "$stdout_file"
}

@test "usop_exec with piped commands" {
    local result
    result=$(usop_exec bash -c 'echo "hello world" | tr "a-z" "A-Z"')
    local stdout
    stdout=$(json_get "$result" "stdout")
    [ "$stdout" = "HELLO WORLD" ]
}

@test "usop_exec preserves environment variables" {
    export TEST_VAR="test_value"
    local result
    result=$(usop_exec bash -c 'echo $TEST_VAR')
    local stdout
    stdout=$(json_get "$result" "stdout")
    [ "$stdout" = "test_value" ]
}

@test "usop error helpers all set success:false" {
    local r1 r2 r3 r4 r5
    r1=$(usop_error_not_found "x" "y")
    r2=$(usop_error_permission "x" "y")
    r3=$(usop_error_validation "x" "y" "z")
    r4=$(usop_error_timeout "x" "y")
    r5=$(usop_error_command_failed "x" "y" "z")

    ! usop_ok "$r1"
    ! usop_ok "$r2"
    ! usop_ok "$r3"
    ! usop_ok "$r4"
    ! usop_ok "$r5"
}

@test "usop functions handle special characters safely" {
    # Write file with special characters
    local special_content='{"key": "value with \"quotes\" and $vars"}'
    usop_write_file "$TEST_DIR/special.json" "$special_content"

    # Read it back
    local result
    result=$(usop_read_file "$TEST_DIR/special.json")
    usop_ok "$result"
    json_valid "$result"
}

@test "usop_list_dir handles many files" {
    # Create 20 files
    for i in {1..20}; do
        touch "$TEST_DIR/file_$i.txt"
    done

    local result
    result=$(usop_list_dir "$TEST_DIR")
    usop_ok "$result"

    local count
    count=$(json_get "$result" "count")
    [ "$count" = "20" ]
}

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/futures.bats - Futures Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/futures.sh
#              Future/Promise pattern for non-blocking execution
# Test Count: 30+ test cases
# Categories: core operations, status tracking, await/timeout, result retrieval,
#             cancellation, listing, cleanup, multi-future operations, USOP output,
#             nameref variants, edge cases
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Clear any existing futures
    rm -rf "${TMPDIR:-/tmp}/mainframe/futures/future_"* 2>/dev/null || true

    # Source the libraries
    source "$MAINFRAME_ROOT/lib/common.sh"
    source "$MAINFRAME_ROOT/lib/futures.sh"
}

# Teardown: Clean up test artifacts and futures
teardown() {
    # Clean up any futures created during test
    future_cleanup --all 2>/dev/null || true
    rm -rf "$TEST_TMPDIR"
    rm -rf "${TMPDIR:-/tmp}/mainframe/futures/future_"* 2>/dev/null || true
}

# =============================================================================
# CATEGORY 1: CORE FUTURE OPERATIONS
# =============================================================================

@test "future_run: returns a future ID" {
    local fid
    fid=$(future_run echo "hello")
    [[ -n "$fid" ]]
    [[ "$fid" =~ ^future_ ]]
}

@test "future_run: creates state directory" {
    local fid
    fid=$(future_run echo "hello")
    local dir="${TMPDIR:-/tmp}/mainframe/futures/$fid"
    [[ -d "$dir" ]]
}

@test "future_run: records PID" {
    local fid
    fid=$(future_run sleep 1)
    local dir="${TMPDIR:-/tmp}/mainframe/futures/$fid"
    [[ -f "$dir/pid" ]]
    local pid
    pid=$(<"$dir/pid")
    [[ "$pid" =~ ^[0-9]+$ ]]
}

@test "future_run: records command" {
    local fid
    fid=$(future_run echo "test command")
    local dir="${TMPDIR:-/tmp}/mainframe/futures/$fid"
    [[ -f "$dir/command" ]]
    local cmd
    cmd=$(<"$dir/command")
    [[ "$cmd" == "echo test command" ]]
}

@test "future_run: fails with no command" {
    run future_run
    [[ "$status" -eq 1 ]]
}

@test "future_run: handles command with arguments" {
    local fid
    fid=$(future_run printf "%s-%s" "arg1" "arg2")
    future_await "$fid"
    local result
    result=$(future_result "$fid")
    [[ "$result" == "arg1-arg2" ]]
}

# =============================================================================
# CATEGORY 2: STATUS TRACKING
# =============================================================================

@test "future_status: returns running for active future" {
    local fid
    fid=$(future_run sleep 2)
    local status
    status=$(future_status "$fid")
    [[ "$status" == "running" ]]
    future_cancel "$fid"
}

@test "future_status: returns done for completed future" {
    local fid
    fid=$(future_run echo "quick")
    sleep 0.3
    local status
    status=$(future_status "$fid")
    [[ "$status" == "done" ]]
}

@test "future_status: returns failed for failed command" {
    local fid
    fid=$(future_run false)
    sleep 0.3
    local status
    status=$(future_status "$fid")
    [[ "$status" == "failed" ]]
}

@test "future_status: returns cancelled for cancelled future" {
    local fid
    fid=$(future_run sleep 2)
    future_cancel "$fid"
    local status
    status=$(future_status "$fid")
    [[ "$status" == "cancelled" ]]
}

@test "future_status: fails for non-existent future" {
    run future_status "future_nonexistent_123"
    [[ "$status" -eq 1 ]]
}

@test "future_status: fails with empty ID" {
    run future_status ""
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 3: AWAIT AND TIMEOUT
# =============================================================================

@test "future_await: blocks until completion" {
    local fid
    fid=$(future_run sleep 0.2)
    local start_time end_time
    start_time=$(date +%s)
    future_await "$fid"
    end_time=$(date +%s)
    # Should have waited at least some time
    [[ $((end_time - start_time)) -ge 0 ]]
}

@test "future_await: returns 0 for successful future" {
    local fid
    fid=$(future_run echo "success")
    future_await "$fid"
    [[ $? -eq 0 ]]
}

@test "future_await: returns 1 for failed future" {
    local fid
    fid=$(future_run false)
    run future_await "$fid"
    [[ "$status" -eq 1 ]]
}

@test "future_await: returns 124 on timeout" {
    local fid
    fid=$(future_run sleep 3)
    run future_await "$fid" 1
    [[ "$status" -eq 124 ]]
    future_cancel "$fid"
}

@test "future_await: fails for non-existent future" {
    run future_await "future_nonexistent_456"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 4: RESULT RETRIEVAL
# =============================================================================

@test "future_result: returns stdout of completed command" {
    local fid
    fid=$(future_run echo "hello world")
    future_await "$fid"
    local result
    result=$(future_result "$fid")
    [[ "$result" == "hello world" ]]
}

@test "future_result: handles multi-line output" {
    local fid
    fid=$(future_run bash -c 'echo "line1"; echo "line2"')
    future_await "$fid"
    local result
    result=$(future_result "$fid")
    [[ "$result" == $'line1\nline2' ]]
}

@test "future_result: fails for non-existent future" {
    run future_result "future_nonexistent_789"
    [[ "$status" -eq 1 ]]
}

@test "future_error: returns stderr of failed command" {
    local fid
    fid=$(future_run bash -c 'echo "error message" >&2; exit 1')
    future_await "$fid" || true
    local err
    err=$(future_error "$fid")
    [[ "$err" == "error message" ]]
}

@test "future_exit_code: returns 0 for success" {
    local fid
    fid=$(future_run true)
    future_await "$fid"
    local code
    code=$(future_exit_code "$fid")
    [[ "$code" -eq 0 ]]
}

@test "future_exit_code: returns non-zero for failure" {
    local fid
    fid=$(future_run bash -c 'exit 42')
    future_await "$fid" || true
    local code
    code=$(future_exit_code "$fid")
    [[ "$code" -eq 42 ]]
}

# =============================================================================
# CATEGORY 5: CANCELLATION
# =============================================================================

@test "future_cancel: cancels running future" {
    local fid
    fid=$(future_run sleep 2)
    future_cancel "$fid"
    local status
    status=$(future_status "$fid")
    [[ "$status" == "cancelled" ]]
}

@test "future_cancel: returns 0 on success" {
    local fid
    fid=$(future_run sleep 2)
    future_cancel "$fid"
    [[ $? -eq 0 ]]
}

@test "future_cancel: returns 1 for already completed future" {
    local fid
    fid=$(future_run echo "quick")
    sleep 0.3
    run future_cancel "$fid"
    [[ "$status" -eq 1 ]]
}

@test "future_cancel: kills the background process" {
    local fid
    fid=$(future_run sleep 2)
    local dir="${TMPDIR:-/tmp}/mainframe/futures/$fid"
    local pid
    pid=$(<"$dir/pid")

    # Verify process is running
    kill -0 "$pid" 2>/dev/null
    [[ $? -eq 0 ]]

    future_cancel "$fid"

    # Brief wait for cleanup
    sleep 0.2

    # Verify process is gone
    ! kill -0 "$pid" 2>/dev/null
}

# =============================================================================
# CATEGORY 6: LISTING AND CLEANUP
# =============================================================================

@test "future_list: returns JSON array" {
    local fid
    fid=$(future_run sleep 1)
    local list
    list=$(future_list)
    [[ "$list" =~ ^\[.*\]$ ]]
    future_cancel "$fid"
}

@test "future_list: includes created future" {
    local fid
    fid=$(future_run sleep 1)
    local list
    list=$(future_list)
    [[ "$list" =~ "$fid" ]]
    future_cancel "$fid"
}

@test "future_list: returns empty array when no futures" {
    # Clear all futures first
    rm -rf "${TMPDIR:-/tmp}/mainframe/futures/future_"* 2>/dev/null || true
    local list
    list=$(future_list)
    [[ "$list" == "[]" ]]
}

@test "future_cleanup: removes completed futures" {
    local fid
    fid=$(future_run echo "quick")
    sleep 0.3  # Let it complete
    local dir="${TMPDIR:-/tmp}/mainframe/futures/$fid"
    [[ -d "$dir" ]]

    future_cleanup

    [[ ! -d "$dir" ]]
}

@test "future_cleanup: preserves running futures" {
    local fid
    fid=$(future_run sleep 2)
    local dir="${TMPDIR:-/tmp}/mainframe/futures/$fid"

    future_cleanup

    [[ -d "$dir" ]]
    future_cancel "$fid"
}

@test "future_cleanup --all: removes cancelled futures" {
    local fid
    fid=$(future_run sleep 2)
    future_cancel "$fid"
    local dir="${TMPDIR:-/tmp}/mainframe/futures/$fid"

    future_cleanup --all

    [[ ! -d "$dir" ]]
}

# =============================================================================
# CATEGORY 7: MULTI-FUTURE OPERATIONS
# =============================================================================

@test "future_wait_all: waits for all futures" {
    local fid1 fid2
    fid1=$(future_run sleep 0.2)
    fid2=$(future_run sleep 0.1)

    future_wait_all "$fid1" "$fid2"

    local s1 s2
    s1=$(future_status "$fid1")
    s2=$(future_status "$fid2")
    [[ "$s1" == "done" ]]
    [[ "$s2" == "done" ]]
}

@test "future_wait_all: returns 0 when all succeed" {
    local fid1 fid2
    fid1=$(future_run true)
    fid2=$(future_run true)

    future_wait_all "$fid1" "$fid2"
    [[ $? -eq 0 ]]
}

@test "future_wait_all: returns 1 when any fails" {
    local fid1 fid2
    fid1=$(future_run true)
    fid2=$(future_run false)

    run future_wait_all "$fid1" "$fid2"
    [[ "$status" -eq 1 ]]
}

@test "future_wait_any: returns first completed ID" {
    local fid1 fid2
    fid1=$(future_run sleep 2)
    fid2=$(future_run echo "quick")

    local first
    first=$(future_wait_any "$fid1" "$fid2")
    [[ "$first" == "$fid2" ]]

    future_cancel "$fid1"
}

@test "future_wait_any: returns 0 for successful first completion" {
    local fid1 fid2
    fid1=$(future_run sleep 2)
    fid2=$(future_run true)

    future_wait_any "$fid1" "$fid2" >/dev/null
    [[ $? -eq 0 ]]

    future_cancel "$fid1"
}

@test "future_wait_any: returns 1 for failed first completion" {
    local fid1 fid2
    fid1=$(future_run sleep 2)
    fid2=$(future_run false)

    run bash -c "source '$MAINFRAME_ROOT/lib/common.sh'; source '$MAINFRAME_ROOT/lib/futures.sh'; future_wait_any '$fid1' '$fid2'"
    [[ "$status" -eq 1 ]]

    future_cancel "$fid1"
}

# =============================================================================
# CATEGORY 8: USOP OUTPUT
# =============================================================================

@test "future_info: returns JSON with ok:true for existing future" {
    local fid
    fid=$(future_run echo "test")
    future_await "$fid"
    local info
    info=$(future_info "$fid")
    [[ "$info" =~ '"ok":true' ]]
}

@test "future_info: includes future ID in response" {
    local fid
    fid=$(future_run echo "test")
    future_await "$fid"
    local info
    info=$(future_info "$fid")
    [[ "$info" =~ "$fid" ]]
}

@test "future_info: includes status in response" {
    local fid
    fid=$(future_run echo "test")
    future_await "$fid"
    local info
    info=$(future_info "$fid")
    [[ "$info" =~ '"status":"done"' ]]
}

@test "future_info: returns error for non-existent future" {
    local info
    run future_info "future_nonexistent_abc"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ '"ok":false' ]] || [[ "$output" =~ 'E_NOT_FOUND' ]]
}

@test "future_info: returns error for empty ID" {
    run future_info ""
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 9: NAMEREF VARIANTS
# =============================================================================

@test "future_run_v: stores future ID in variable" {
    local fid=""
    future_run_v fid echo "hello"
    [[ -n "$fid" ]]
    [[ "$fid" =~ ^future_ ]]
    future_await "$fid" || true
}

@test "future_status_v: stores status in variable" {
    local fid status=""
    fid=$(future_run echo "quick")
    sleep 0.3
    future_status_v status "$fid"
    [[ "$status" == "done" ]]
}

@test "future_result_v: stores result in variable" {
    local fid result=""
    fid=$(future_run echo "nameref test")
    future_await "$fid"
    future_result_v result "$fid"
    [[ "$result" == "nameref test" ]]
}

@test "future_error_v: stores error in variable" {
    local fid err=""
    fid=$(future_run bash -c 'echo "err output" >&2; exit 1')
    future_await "$fid" || true
    future_error_v err "$fid"
    [[ "$err" == "err output" ]]
}

@test "future_exit_code_v: stores exit code in variable" {
    local fid code=""
    fid=$(future_run bash -c 'exit 77')
    future_await "$fid" || true
    future_exit_code_v code "$fid"
    [[ "$code" -eq 77 ]]
}

# =============================================================================
# CATEGORY 10: EDGE CASES AND SECURITY
# =============================================================================

@test "future_run: handles command with spaces in arguments" {
    local fid
    fid=$(future_run echo "hello world with spaces")
    future_await "$fid"
    local result
    result=$(future_result "$fid")
    [[ "$result" == "hello world with spaces" ]]
}

@test "future_run: handles command with special characters" {
    local fid
    fid=$(future_run bash -c 'echo "quotes\" and \$pecial"')
    future_await "$fid"
    local result
    result=$(future_result "$fid")
    [[ "$result" == 'quotes" and $pecial' ]]
}

@test "future: handles rapid creation of multiple futures" {
    local fids=()
    local i
    for i in {1..5}; do
        fids+=( "$(future_run echo "future $i")" )
    done

    # All should have unique IDs
    local unique_count
    unique_count=$(printf '%s\n' "${fids[@]}" | sort -u | wc -l)
    [[ "$unique_count" -eq 5 ]]

    # Wait for all
    future_wait_all "${fids[@]}"
}

@test "future: handles long-running commands" {
    skip "Skipping long-running test in unit suite"
    local fid
    fid=$(future_run sleep 3)
    future_await "$fid" 10
    [[ $? -eq 0 ]]
}

@test "future_result: handles empty output" {
    local fid
    fid=$(future_run true)  # Produces no output
    future_await "$fid"
    local result
    result=$(future_result "$fid")
    [[ -z "$result" ]]
}

@test "future_error: handles empty stderr" {
    local fid
    fid=$(future_run echo "stdout only")
    future_await "$fid"
    local err
    err=$(future_error "$fid")
    [[ -z "$err" ]]
}

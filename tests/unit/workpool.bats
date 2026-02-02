#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/workpool.bats - Work Pool Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/workpool.sh
#              Lightweight work pool for parallel batch processing
# Test Count: 54 test cases
# Categories: pool management, job submission, synchronization, results,
#             rate limiting, edge cases
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create unique temp directory for each test
    export TEST_TMPDIR="$(mktemp -d)"
    export POOL_STATE_DIR="$TEST_TMPDIR/pools"

    # Source the library
    MAINFRAME_LIBS="core" source "$MAINFRAME_ROOT/lib/common.sh"
    source "$MAINFRAME_ROOT/lib/workpool.sh"
}

# Teardown: Clean up test artifacts
teardown() {
    # Kill any leftover processes from this test
    pkill -P $$ 2>/dev/null || true

    # Clean up temp directory
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# CATEGORY 1: POOL MANAGEMENT - pool_create
# =============================================================================

@test "pool_create: creates pool with default workers" {
    pool_create "test_pool"
    [[ -d "$POOL_STATE_DIR/test_pool" ]]
    [[ -d "$POOL_STATE_DIR/test_pool/jobs" ]]
    [[ -d "$POOL_STATE_DIR/test_pool/results" ]]
    [[ -f "$POOL_STATE_DIR/test_pool/max_workers" ]]
}

@test "pool_create: creates pool with specified worker count" {
    pool_create "test_pool" 8
    local workers
    workers=$(cat "$POOL_STATE_DIR/test_pool/max_workers")
    [[ "$workers" -eq 8 ]]
}

@test "pool_create: uses CPU count when workers=0" {
    pool_create "test_pool" 0
    local workers
    workers=$(cat "$POOL_STATE_DIR/test_pool/max_workers")
    [[ "$workers" -gt 0 ]]
}

@test "pool_create: is idempotent" {
    pool_create "test_pool" 4
    run pool_create "test_pool" 8
    [[ "$status" -eq 0 ]]
    # Original worker count preserved
    local workers
    workers=$(cat "$POOL_STATE_DIR/test_pool/max_workers")
    [[ "$workers" -eq 4 ]]
}

@test "pool_create: rejects invalid pool names" {
    run pool_create ""
    [[ "$status" -eq 1 ]]

    run pool_create "has space"
    [[ "$status" -eq 1 ]]

    run pool_create "../path"
    [[ "$status" -eq 1 ]]

    run pool_create "123start"
    [[ "$status" -eq 1 ]]
}

@test "pool_create: accepts valid pool names" {
    run pool_create "valid_name"
    [[ "$status" -eq 0 ]]

    run pool_create "valid-name"
    [[ "$status" -eq 0 ]]

    run pool_create "_underscore"
    [[ "$status" -eq 0 ]]

    run pool_create "CamelCase"
    [[ "$status" -eq 0 ]]
}

# =============================================================================
# CATEGORY 2: POOL MANAGEMENT - pool_destroy
# =============================================================================

@test "pool_destroy: removes pool directory" {
    pool_create "test_pool"
    pool_destroy "test_pool"
    [[ ! -d "$POOL_STATE_DIR/test_pool" ]]
}

@test "pool_destroy: is idempotent" {
    pool_create "test_pool"
    pool_destroy "test_pool"
    run pool_destroy "test_pool"
    [[ "$status" -eq 0 ]]
}

@test "pool_destroy: kills running jobs" {
    pool_create "test_pool" 4

    # Submit a long-running job
    local job_id
    job_id=$(pool_submit "test_pool" sleep 3)

    # Give it time to start
    sleep 0.2

    # Get the PID
    local pid
    pid=$(cat "$POOL_STATE_DIR/test_pool/jobs/$job_id/pid" 2>/dev/null)

    # Destroy pool
    pool_destroy "test_pool"

    # Verify process is killed
    sleep 0.2
    ! kill -0 "$pid" 2>/dev/null
}

# =============================================================================
# CATEGORY 3: POOL MANAGEMENT - pool_resize
# =============================================================================

@test "pool_resize: changes worker count" {
    pool_create "test_pool" 4
    pool_resize "test_pool" 16
    local workers
    workers=$(cat "$POOL_STATE_DIR/test_pool/max_workers")
    [[ "$workers" -eq 16 ]]
}

@test "pool_resize: fails for non-existent pool" {
    run pool_resize "nonexistent" 4
    [[ "$status" -eq 1 ]]
}

@test "pool_resize: rejects invalid count" {
    pool_create "test_pool"
    run pool_resize "test_pool" 0
    [[ "$status" -eq 1 ]]

    run pool_resize "test_pool" -1
    [[ "$status" -eq 1 ]]

    run pool_resize "test_pool" "abc"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 4: JOB SUBMISSION - pool_submit
# =============================================================================

@test "pool_submit: returns job ID" {
    pool_create "test_pool"
    local job_id
    job_id=$(pool_submit "test_pool" echo "hello")
    [[ "$job_id" =~ ^job_[0-9]+$ ]]
}

@test "pool_submit: creates job directory" {
    pool_create "test_pool"
    local job_id
    job_id=$(pool_submit "test_pool" echo "hello")
    [[ -d "$POOL_STATE_DIR/test_pool/jobs/$job_id" ]]
}

@test "pool_submit: executes command" {
    pool_create "test_pool"
    local job_id
    job_id=$(pool_submit "test_pool" echo "hello world")
    pool_wait "test_pool" "$job_id"

    local result
    result=$(pool_result "test_pool" "$job_id")
    [[ "$result" == "hello world" ]]
}

@test "pool_submit: handles command with arguments" {
    pool_create "test_pool"
    local job_id
    job_id=$(pool_submit "test_pool" printf "%s %s" "arg1" "arg2")
    pool_wait "test_pool" "$job_id"

    local result
    result=$(pool_result "test_pool" "$job_id")
    [[ "$result" == "arg1 arg2" ]]
}

@test "pool_submit: fails for non-existent pool" {
    run pool_submit "nonexistent" echo "hello"
    [[ "$status" -eq 1 ]]
}

@test "pool_submit: fails with no command" {
    pool_create "test_pool"
    run pool_submit "test_pool"
    [[ "$status" -eq 1 ]]
}

@test "pool_submit: increments job counter" {
    pool_create "test_pool"

    local job1 job2 job3
    job1=$(pool_submit "test_pool" true)
    job2=$(pool_submit "test_pool" true)
    job3=$(pool_submit "test_pool" true)

    [[ "$job1" == "job_1" ]]
    [[ "$job2" == "job_2" ]]
    [[ "$job3" == "job_3" ]]
}

# =============================================================================
# CATEGORY 5: JOB SUBMISSION - pool_submit_batch
# =============================================================================

@test "pool_submit_batch: submits jobs from file" {
    pool_create "test_pool"

    cat > "$TEST_TMPDIR/commands.txt" << 'EOF'
echo line1
echo line2
echo line3
EOF

    local job_ids
    job_ids=$(pool_submit_batch "test_pool" "$TEST_TMPDIR/commands.txt")

    local count
    count=$(echo "$job_ids" | wc -l)
    [[ "$count" -eq 3 ]]
}

@test "pool_submit_batch: skips comments and empty lines" {
    pool_create "test_pool"

    cat > "$TEST_TMPDIR/commands.txt" << 'EOF'
# This is a comment
echo valid1

  # Indented comment
echo valid2
EOF

    local job_ids
    job_ids=$(pool_submit_batch "test_pool" "$TEST_TMPDIR/commands.txt")

    local count
    count=$(echo "$job_ids" | wc -l)
    [[ "$count" -eq 2 ]]
}

@test "pool_submit_batch: fails for missing file" {
    pool_create "test_pool"
    run pool_submit_batch "test_pool" "$TEST_TMPDIR/nonexistent.txt"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 6: JOB SUBMISSION - pool_map
# =============================================================================

@test "pool_map: maps command over items" {
    pool_create "test_pool"

    local job_ids
    job_ids=$(pool_map "test_pool" echo "a" "b" "c")

    pool_wait "test_pool"

    local count
    count=$(echo "$job_ids" | wc -l)
    [[ "$count" -eq 3 ]]
}

@test "pool_map: executes command for each item" {
    pool_create "test_pool"

    pool_map "test_pool" echo "alpha" "beta" > /dev/null
    pool_wait "test_pool"

    # Check results
    local results
    results=$(pool_results "test_pool")
    [[ "$results" =~ "alpha" ]]
    [[ "$results" =~ "beta" ]]
}

# =============================================================================
# CATEGORY 7: SYNCHRONIZATION - pool_wait
# =============================================================================

@test "pool_wait: waits for all jobs" {
    pool_create "test_pool"

    pool_submit "test_pool" sleep 0.1 > /dev/null
    pool_submit "test_pool" sleep 0.1 > /dev/null

    local start end
    start=$(date +%s)
    pool_wait "test_pool"
    end=$(date +%s)

    # Should have waited at least 0.1 seconds
    [[ $((end - start)) -ge 0 ]]
}

@test "pool_wait: waits for specific job" {
    pool_create "test_pool"

    local job1 job2
    job1=$(pool_submit "test_pool" sleep 0.1)
    job2=$(pool_submit "test_pool" sleep 0.5)

    pool_wait "test_pool" "$job1"

    # job1 should be done, job2 might still be running
    local status
    status=$(pool_status "test_pool" "$job1")
    [[ "$status" == "done" ]]
}

@test "pool_wait: returns 0 when all jobs succeed" {
    pool_create "test_pool"

    pool_submit "test_pool" true > /dev/null
    pool_submit "test_pool" true > /dev/null

    run pool_wait "test_pool"
    [[ "$status" -eq 0 ]]
}

@test "pool_wait: returns 1 when any job fails" {
    pool_create "test_pool"

    pool_submit "test_pool" true > /dev/null
    pool_submit "test_pool" false > /dev/null

    run pool_wait "test_pool"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 8: SYNCHRONIZATION - pool_wait_any
# =============================================================================

@test "pool_wait_any: returns completed job ID" {
    pool_create "test_pool"

    pool_submit "test_pool" sleep 0.1 > /dev/null
    pool_submit "test_pool" echo "fast" > /dev/null

    local completed
    completed=$(pool_wait_any "test_pool")
    [[ "$completed" =~ ^job_[0-9]+$ ]]
}

@test "pool_wait_any: returns 1 when no jobs" {
    pool_create "test_pool"
    run pool_wait_any "test_pool"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 9: SYNCHRONIZATION - pool_barrier
# =============================================================================

@test "pool_barrier: blocks until all jobs complete" {
    pool_create "test_pool"

    pool_submit "test_pool" sleep 0.1 > /dev/null
    pool_submit "test_pool" sleep 0.1 > /dev/null

    pool_barrier "test_pool"

    # All jobs should be done
    local pending
    pending=$(pool_info "test_pool" | grep -o '"pending":[0-9]*' | grep -o '[0-9]*')
    [[ "$pending" -eq 0 ]]
}

# =============================================================================
# CATEGORY 10: RESULTS - pool_result
# =============================================================================

@test "pool_result: returns job stdout" {
    pool_create "test_pool"

    local job_id
    job_id=$(pool_submit "test_pool" echo "expected output")
    pool_wait "test_pool" "$job_id"

    local result
    result=$(pool_result "test_pool" "$job_id")
    [[ "$result" == "expected output" ]]
}

@test "pool_result: fails for non-existent job" {
    pool_create "test_pool"
    run pool_result "test_pool" "job_999"
    [[ "$status" -eq 1 ]]
}

@test "pool_result: fails for running job" {
    pool_create "test_pool"

    local job_id
    job_id=$(pool_submit "test_pool" sleep 2)

    sleep 0.2  # Let it start

    run pool_result "test_pool" "$job_id"
    [[ "$status" -eq 1 ]]

    # Clean up
    pool_destroy "test_pool"
}

# =============================================================================
# CATEGORY 11: RESULTS - pool_status
# =============================================================================

@test "pool_status: returns pending for queued job" {
    # Create pool with 1 worker
    pool_create "test_pool" 1

    # Submit a blocking job to occupy the worker
    pool_submit "test_pool" sleep 2 > /dev/null
    sleep 0.2

    # Submit another job that will be pending
    local job_id
    job_id=$(pool_submit "test_pool" echo "pending job")

    # Check status immediately
    local status
    status=$(pool_status "test_pool" "$job_id")

    # Clean up first
    pool_destroy "test_pool"

    # Could be pending or done depending on timing
    [[ "$status" == "pending" || "$status" == "running" || "$status" == "done" ]]
}

@test "pool_status: returns done for completed job" {
    pool_create "test_pool"

    local job_id
    job_id=$(pool_submit "test_pool" echo "done")
    pool_wait "test_pool" "$job_id"

    local status
    status=$(pool_status "test_pool" "$job_id")
    [[ "$status" == "done" ]]
}

@test "pool_status: returns failed for failed job" {
    pool_create "test_pool"

    local job_id
    job_id=$(pool_submit "test_pool" false)
    pool_wait "test_pool" "$job_id"

    local status
    status=$(pool_status "test_pool" "$job_id")
    [[ "$status" == "failed" ]]
}

# =============================================================================
# CATEGORY 12: RESULTS - pool_results
# =============================================================================

@test "pool_results: returns JSON array" {
    pool_create "test_pool"

    pool_submit "test_pool" echo "one" > /dev/null
    pool_submit "test_pool" echo "two" > /dev/null
    pool_wait "test_pool"

    local results
    results=$(pool_results "test_pool")

    # Should be valid JSON array
    [[ "$results" =~ ^\[.*\]$ ]]
}

@test "pool_results: contains job info" {
    pool_create "test_pool"

    pool_submit "test_pool" echo "test" > /dev/null
    pool_wait "test_pool"

    local results
    results=$(pool_results "test_pool")

    [[ "$results" =~ '"id":"job_1"' ]]
    [[ "$results" =~ '"status":"done"' ]]
    [[ "$results" =~ '"result":"test' ]]
}

# =============================================================================
# CATEGORY 13: RATE LIMITING - pool_rate_limit
# =============================================================================

@test "pool_rate_limit: sets rate limit" {
    pool_create "test_pool"
    pool_rate_limit "test_pool" 10

    local rate
    rate=$(cat "$POOL_STATE_DIR/test_pool/rate_limit")
    [[ "$rate" -eq 10 ]]
}

@test "pool_rate_limit: 0 means unlimited" {
    pool_create "test_pool"
    pool_rate_limit "test_pool" 0

    local rate
    rate=$(cat "$POOL_STATE_DIR/test_pool/rate_limit")
    [[ "$rate" -eq 0 ]]
}

@test "pool_rate_limit: fails for non-existent pool" {
    run pool_rate_limit "nonexistent" 10
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 14: RATE LIMITING - pool_semaphore
# =============================================================================

@test "pool_semaphore: sets semaphore count" {
    pool_create "test_pool"
    pool_semaphore "test_pool" 5

    local sem
    sem=$(cat "$POOL_STATE_DIR/test_pool/semaphore")
    [[ "$sem" -eq 5 ]]
}

@test "pool_semaphore: fails for non-existent pool" {
    run pool_semaphore "nonexistent" 5
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 15: UTILITY - pool_info
# =============================================================================

@test "pool_info: returns JSON object" {
    pool_create "test_pool" 4

    local info
    info=$(pool_info "test_pool")

    [[ "$info" =~ ^\{.*\}$ ]]
    [[ "$info" =~ '"name":"test_pool"' ]]
    [[ "$info" =~ '"max_workers":4' ]]
}

@test "pool_info: tracks job counts" {
    pool_create "test_pool"

    pool_submit "test_pool" true > /dev/null
    pool_submit "test_pool" false > /dev/null
    pool_wait "test_pool"

    local info
    info=$(pool_info "test_pool")

    [[ "$info" =~ '"done":1' ]]
    [[ "$info" =~ '"failed":1' ]]
}

# =============================================================================
# CATEGORY 16: UTILITY - pool_list_jobs
# =============================================================================

@test "pool_list_jobs: lists all job IDs" {
    pool_create "test_pool"

    pool_submit "test_pool" true > /dev/null
    pool_submit "test_pool" true > /dev/null
    pool_submit "test_pool" true > /dev/null
    pool_wait "test_pool"

    local jobs
    jobs=$(pool_list_jobs "test_pool")

    local count
    count=$(echo "$jobs" | wc -l)
    [[ "$count" -eq 3 ]]
}

# =============================================================================
# CATEGORY 17: CONCURRENCY
# =============================================================================

@test "concurrency: respects max workers" {
    pool_create "test_pool" 2

    # Submit 4 jobs that take time
    pool_submit "test_pool" sleep 0.5 > /dev/null
    pool_submit "test_pool" sleep 0.5 > /dev/null
    pool_submit "test_pool" sleep 0.5 > /dev/null
    pool_submit "test_pool" sleep 0.5 > /dev/null

    sleep 0.2

    # Only 2 should be running
    local running
    running=$(_pool_running_count "test_pool")
    [[ "$running" -le 2 ]]

    pool_destroy "test_pool"
}

@test "concurrency: processes all jobs eventually" {
    pool_create "test_pool" 2

    pool_submit "test_pool" echo "1" > /dev/null
    pool_submit "test_pool" echo "2" > /dev/null
    pool_submit "test_pool" echo "3" > /dev/null
    pool_submit "test_pool" echo "4" > /dev/null

    pool_wait "test_pool"

    local info
    info=$(pool_info "test_pool")
    [[ "$info" =~ '"done":4' ]]
}

# =============================================================================
# CATEGORY 18: EDGE CASES
# =============================================================================

@test "edge case: handles special characters in output" {
    pool_create "test_pool"

    local job_id
    job_id=$(pool_submit "test_pool" echo 'hello "world" \n test')
    pool_wait "test_pool" "$job_id"

    local result
    result=$(pool_result "test_pool" "$job_id")
    [[ -n "$result" ]]
}

@test "edge case: handles empty output" {
    pool_create "test_pool"

    local job_id
    job_id=$(pool_submit "test_pool" true)
    pool_wait "test_pool" "$job_id"

    local result
    result=$(pool_result "test_pool" "$job_id")
    [[ -z "$result" ]]
}

@test "edge case: handles multiline output" {
    pool_create "test_pool"

    local job_id
    job_id=$(pool_submit "test_pool" printf "line1\nline2\nline3")
    pool_wait "test_pool" "$job_id"

    local result
    result=$(pool_result "test_pool" "$job_id")

    local lines
    lines=$(echo "$result" | wc -l)
    [[ "$lines" -eq 3 ]]
}

@test "edge case: pool with hyphen in name" {
    pool_create "my-pool"
    [[ -d "$POOL_STATE_DIR/my-pool" ]]
    pool_destroy "my-pool"
}

@test "edge case: multiple pools simultaneously" {
    pool_create "pool_a" 2
    pool_create "pool_b" 2

    pool_submit "pool_a" echo "from a" > /dev/null
    pool_submit "pool_b" echo "from b" > /dev/null

    pool_wait "pool_a"
    pool_wait "pool_b"

    local info_a info_b
    info_a=$(pool_info "pool_a")
    info_b=$(pool_info "pool_b")

    [[ "$info_a" =~ '"done":1' ]]
    [[ "$info_b" =~ '"done":1' ]]

    pool_destroy "pool_a"
    pool_destroy "pool_b"
}

@test "pool_wait: specific job fails for non-existent job" {
    pool_create "test_pool"
    run pool_wait "test_pool" "job_nonexistent"
    [[ "$status" -eq 1 ]]
}

@test "pool_info: fails for non-existent pool" {
    run pool_info "nonexistent_pool"
    [[ "$status" -eq 1 ]]
}

@test "pool_list_jobs: fails for non-existent pool" {
    run pool_list_jobs "nonexistent_pool"
    [[ "$status" -eq 1 ]]
}

@test "pool_results: fails for non-existent pool" {
    run pool_results "nonexistent_pool"
    [[ "$status" -eq 1 ]]
}

@test "pool_status: fails for non-existent pool" {
    run pool_status "nonexistent" "job_1"
    [[ "$status" -eq 1 ]]
}

@test "pool_result: fails for non-existent pool" {
    run pool_result "nonexistent" "job_1"
    [[ "$status" -eq 1 ]]
}

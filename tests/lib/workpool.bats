#!/usr/bin/env bats

# Smoke tests for the current workpool.sh API surface.

load ../test_helper

setup() {
    TEST_DIR=$(mktemp -d)
    export POOL_STATE_DIR="$TEST_DIR/pools"

    source "$MAINFRAME_ROOT/lib/common.sh"
    source "$MAINFRAME_ROOT/lib/workpool.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "pool_create initializes pool directories" {
    pool_create "test_pool" 2
    [ -d "$POOL_STATE_DIR/test_pool/jobs" ]
    [ -d "$POOL_STATE_DIR/test_pool/results" ]
}

@test "pool_destroy removes the pool" {
    pool_create "test_pool" 2
    pool_destroy "test_pool"
    [ ! -d "$POOL_STATE_DIR/test_pool" ]
}

@test "pool_submit and pool_wait execute a job asynchronously" {
    pool_create "test_pool" 2

    job_id=$(pool_submit "test_pool" sleep 0.5)
    run pool_result "test_pool" "$job_id"
    [ "$status" -eq 1 ]

    run pool_wait "test_pool" "$job_id"
    [ "$status" -eq 0 ]

    status_text=$(pool_status "test_pool" "$job_id")
    [ "$status_text" = "done" ]
}

@test "pool_result returns completed stdout" {
    pool_create "test_pool" 2

    job_id=$(pool_submit "test_pool" printf "hello")
    pool_wait "test_pool" "$job_id"

    result=$(pool_result "test_pool" "$job_id")
    [ "$result" = "hello" ]
}

@test "pool_submit_batch returns one job per command" {
    pool_create "test_pool" 2

    cat > "$TEST_DIR/commands.txt" <<'EOF'
echo first
echo second
EOF

    job_ids=$(pool_submit_batch "test_pool" "$TEST_DIR/commands.txt")
    run pool_wait "test_pool"
    [ "$status" -eq 0 ]

    count=$(printf '%s\n' "$job_ids" | wc -l | tr -d ' ')
    [ "$count" -eq 2 ]
}

@test "pool_map fans out a command over items" {
    pool_create "test_pool" 2

    job_ids=$(pool_map "test_pool" echo "alpha" "beta")
    pool_wait "test_pool"

    results=$(pool_results "test_pool")
    [[ "$job_ids" == *"job_1"* ]]
    [[ "$job_ids" == *"job_2"* ]]
    [[ "$results" == *'"result":"alpha"'* ]]
    [[ "$results" == *'"result":"beta"'* ]]
}

@test "pool_wait returns failure when any job fails" {
    pool_create "test_pool" 2

    pool_submit "test_pool" true > /dev/null
    pool_submit "test_pool" false > /dev/null

    run pool_wait "test_pool"
    [ "$status" -eq 1 ]
}

@test "pool_info reports counts for completed jobs" {
    pool_create "test_pool" 2

    pool_submit "test_pool" true > /dev/null
    pool_submit "test_pool" false > /dev/null
    run pool_wait "test_pool"
    [ "$status" -eq 1 ]

    info=$(pool_info "test_pool")
    [[ "$info" == *'"done":1'* ]]
    [[ "$info" == *'"failed":1'* ]]
}

@test "pool_semaphore limits concurrent entries" {
    pool_create "test_pool" 2
    pool_semaphore "test_pool" 1

    job1=$(pool_submit "test_pool" sleep 0.2)
    job2=$(pool_submit "test_pool" sleep 0.2)

    sleep 0.05
    sem_count=$(cat "$POOL_STATE_DIR/test_pool/semaphore_count")
    [ "$sem_count" -eq 1 ]

    pool_wait "test_pool" "$job1"
    pool_wait "test_pool" "$job2"

    sem_count=$(cat "$POOL_STATE_DIR/test_pool/semaphore_count")
    [ "$sem_count" -eq 0 ]
}

@test "pool_list_jobs lists submitted work across pools" {
    pool_create "pool_a" 1
    pool_create "pool_b" 1

    pool_submit "pool_a" echo "from a" > /dev/null
    pool_submit "pool_b" echo "from b" > /dev/null
    pool_wait "pool_a"
    pool_wait "pool_b"

    jobs_a=$(pool_list_jobs "pool_a")
    jobs_b=$(pool_list_jobs "pool_b")
    [ "$jobs_a" = "job_1" ]
    [ "$jobs_b" = "job_1" ]
}

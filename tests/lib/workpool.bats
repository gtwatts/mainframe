#!/usr/bin/env bats

# Tests for workpool.sh - Work Pool Management
# Critical: Pool operations, semaphore race condition fix

load ../test_helper

setup() {
    source "$MAINFRAME_ROOT/lib/common.sh"
    TEST_DIR=$(mktemp -d)
    export MAINFRAME_WORKPOOL_DIR="$TEST_DIR/workpools"
    mkdir -p "$MAINFRAME_WORKPOOL_DIR"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "workpool_create initializes new pool" {
    workpool_create "test_pool"
    [ -d "$MAINFRAME_WORKPOOL_DIR/test_pool" ]
    [ -f "$MAINFRAME_WORKPOOL_DIR/test_pool/queue" ]
}

@test "workpool_destroy removes pool" {
    workpool_create "test_pool"
    workpool_destroy "test_pool"
    [ ! -d "$MAINFRAME_WORKPOOL_DIR/test_pool" ]
}

@test "workpool_push adds work item" {
    workpool_create "test_pool"
    workpool_push "test_pool" "task1"
    run workpool_count "test_pool"
    [ "$output" -eq 1 ]
}

@test "workpool_pop removes and returns work item" {
    workpool_create "test_pool"
    workpool_push "test_pool" "task1"
    result=$(workpool_pop "test_pool")
    [ "$result" = "task1" ]
}

@test "workpool_pop returns empty when pool empty" {
    workpool_create "test_pool"
    result=$(workpool_pop "test_pool")
    [ -z "$result" ]
}

@test "workpool_count returns correct number" {
    workpool_create "test_pool"
    workpool_push "test_pool" "task1"
    workpool_push "test_pool" "task2"
    workpool_push "test_pool" "task3"
    count=$(workpool_count "test_pool")
    [ "$count" -eq 3 ]
}

@test "workpool_clear removes all items" {
    workpool_create "test_pool"
    workpool_push "test_pool" "task1"
    workpool_push "test_pool" "task2"
    workpool_clear "test_pool"
    count=$(workpool_count "test_pool")
    [ "$count" -eq 0 ]
}

@test "workpool_semaphore_acquire respects limit" {
    workpool_create "test_pool" 2  # max 2 concurrent
    workpool_semaphore_acquire "test_pool"
    workpool_semaphore_acquire "test_pool"
    run workpool_semaphore_acquire "test_pool" 1  # timeout 1s
    [ "$status" -eq 1 ]  # timeout, semaphore full
}

@test "workpool_semaphore_release frees slot" {
    workpool_create "test_pool" 1
    workpool_semaphore_acquire "test_pool"
    workpool_semaphore_release "test_pool"
    run workpool_semaphore_acquire "test_pool" 1
    [ "$status" -eq 0 ]  # acquired successfully
}

@test "workpool_list returns all pools" {
    workpool_create "pool1"
    workpool_create "pool2"
    workpool_create "pool3"
    result=$(workpool_list)
    [[ "$result" == *"pool1"* ]]
    [[ "$result" == *"pool2"* ]]
    [[ "$result" == *"pool3"* ]]
}

@test "workpool_exists returns true for existing pool" {
    workpool_create "test_pool"
    run workpool_exists "test_pool"
    [ "$status" -eq 0 ]
}

@test "workpool_exists returns false for non-existing pool" {
    run workpool_exists "nonexistent"
    [ "$status" -eq 1 ]
}

@test "workpool_peek returns item without removing" {
    workpool_create "test_pool"
    workpool_push "test_pool" "task1"
    result=$(workpool_peek "test_pool")
    [ "$result" = "task1" ]
    count=$(workpool_count "test_pool")
    [ "$count" -eq 1 ]  # still there
}

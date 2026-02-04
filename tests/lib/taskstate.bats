#!/usr/bin/env bats

# Tests for taskstate.sh - Task State Management
# Critical: Task lifecycle, checkpoints, progress tracking

load ../test_helper

setup() {
    source "$MAINFRAME_ROOT/lib/common.sh"
    TEST_DIR=$(mktemp -d)
    export MAINFRAME_TASKSTATE_DIR="$TEST_DIR/taskstate"
    mkdir -p "$MAINFRAME_TASKSTATE_DIR"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "taskstate_create initializes new task" {
    tid=$(taskstate_create "my_task")
    [ -n "$tid" ]
    [ -d "$MAINFRAME_TASKSTATE_DIR/$tid" ]
}

@test "taskstate_destroy removes task" {
    tid=$(taskstate_create "my_task")
    taskstate_destroy "$tid"
    [ ! -d "$MAINFRAME_TASKSTATE_DIR/$tid" ]
}

@test "taskstate_add_step adds step to task" {
    tid=$(taskstate_create "my_task")
    taskstate_add_step "$tid" "step1" "First step"
    run taskstate_list_steps "$tid"
    [[ "$output" == *"step1"* ]]
}

@test "taskstate_step_complete marks step done" {
    tid=$(taskstate_create "my_task")
    taskstate_add_step "$tid" "step1"
    taskstate_step_complete "$tid" "step1"
    status=$(taskstate_step_status "$tid" "step1")
    [ "$status" = "completed" ]
}

@test "taskstate_step_fail marks step failed" {
    tid=$(taskstate_create "my_task")
    taskstate_add_step "$tid" "step1"
    taskstate_step_fail "$tid" "step1" "error message"
    status=$(taskstate_step_status "$tid" "step1")
    [ "$status" = "failed" ]
}

@test "taskstate_step_skip marks step skipped" {
    tid=$(taskstate_create "my_task")
    taskstate_add_step "$tid" "step1"
    taskstate_step_skip "$tid" "step1"
    status=$(taskstate_step_status "$tid" "step1")
    [ "$status" = "skipped" ]
}

@test "taskstate_progress returns completion fraction" {
    tid=$(taskstate_create "my_task")
    taskstate_add_step "$tid" "step1"
    taskstate_add_step "$tid" "step2"
    taskstate_step_complete "$tid" "step1"
    progress=$(taskstate_progress "$tid")
    [ "$progress" = "1/2" ]
}

@test "taskstate_checkpoint creates snapshot" {
    tid=$(taskstate_create "my_task")
    taskstate_add_step "$tid" "step1"
    taskstate_step_complete "$tid" "step1"
    taskstate_checkpoint "$tid" "checkpoint1"
    [ -f "$MAINFRAME_TASKSTATE_DIR/$tid/checkpoints/checkpoint1" ]
}

@test "taskstate_restore restores from checkpoint" {
    tid=$(taskstate_create "my_task")
    taskstate_add_step "$tid" "step1"
    taskstate_step_complete "$tid" "step1"
    taskstate_checkpoint "$tid" "checkpoint1"
    taskstate_step_fail "$tid" "step1"  # modify after checkpoint
    taskstate_restore "$tid" "checkpoint1"
    status=$(taskstate_step_status "$tid" "step1")
    [ "$status" = "completed" ]  # back to checkpoint state
}

@test "taskstate_set stores arbitrary data" {
    tid=$(taskstate_create "my_task")
    taskstate_set "$tid" "mykey" "myvalue"
    result=$(taskstate_get "$tid" "mykey")
    [ "$result" = "myvalue" ]
}

@test "taskstate_get returns empty for missing key" {
    tid=$(taskstate_create "my_task")
    result=$(taskstate_get "$tid" "nonexistent")
    [ -z "$result" ]
}

@test "taskstate_is_done returns true when all steps complete" {
    tid=$(taskstate_create "my_task")
    taskstate_add_step "$tid" "step1"
    taskstate_step_complete "$tid" "step1"
    run taskstate_is_done "$tid"
    [ "$status" -eq 0 ]
}

@test "taskstate_is_done returns false with pending steps" {
    tid=$(taskstate_create "my_task")
    taskstate_add_step "$tid" "step1"
    run taskstate_is_done "$tid"
    [ "$status" -eq 1 ]
}

@test "taskstate_remaining lists incomplete steps" {
    tid=$(taskstate_create "my_task")
    taskstate_add_step "$tid" "step1"
    taskstate_add_step "$tid" "step2"
    taskstate_step_complete "$tid" "step1"
    remaining=$(taskstate_remaining "$tid")
    [[ "$remaining" == *"step2"* ]]
    [[ "$remaining" != *"step1"* ]]  # step1 is done
}

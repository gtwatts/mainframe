#!/usr/bin/env bats

# Smoke tests for the current taskstate.sh API surface.

load ../test_helper

_start_task() {
    task_create "$1" > "$TEST_DIR/task_id"
    TASK_ID=$(<"$TEST_DIR/task_id")
}

setup() {
    TEST_DIR=$(mktemp -d)
    export MAINFRAME_TASK_DIR="$TEST_DIR/taskstate"
    mkdir -p "$MAINFRAME_TASK_DIR"

    source "$MAINFRAME_ROOT/lib/common.sh"
    source "$MAINFRAME_ROOT/lib/taskstate.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "task_create initializes new task" {
    _start_task "my_task"
    [ -n "$TASK_ID" ]
    [ -d "$MAINFRAME_TASK_DIR/$TASK_ID" ]
}

@test "task_delete removes task" {
    _start_task "my_task"
    task_delete "$TASK_ID"
    [ ! -d "$MAINFRAME_TASK_DIR/$TASK_ID" ]
}

@test "task_add_step adds step to task" {
    _start_task "my_task"
    task_add_step "step1" "First step"
    run task_remaining
    [[ "$output" == *"step1"* ]]
}

@test "task_step_complete marks step done" {
    _start_task "my_task"
    task_add_step "step1"
    task_step_complete "step1"
    status=$(task_step_status "step1")
    [ "$status" = "completed" ]
}

@test "task_step_fail marks step failed" {
    _start_task "my_task"
    task_add_step "step1"
    task_step_fail "step1" "error message"
    status=$(task_step_status "step1")
    [ "$status" = "failed" ]
}

@test "task_step_skip marks step skipped" {
    _start_task "my_task"
    task_add_step "step1"
    task_step_skip "step1"
    status=$(task_step_status "step1")
    [ "$status" = "skipped" ]
}

@test "task_progress returns completion fraction" {
    _start_task "my_task"
    task_add_step "step1"
    task_add_step "step2"
    task_step_complete "step1"
    progress=$(task_progress)
    [ "$progress" = "1/2" ]
}

@test "task_checkpoint creates snapshot" {
    _start_task "my_task"
    task_add_step "step1"
    task_step_complete "step1"
    task_checkpoint "checkpoint1"
    [ -d "$MAINFRAME_TASK_DIR/$TASK_ID/checkpoints/checkpoint1" ]
}

@test "task_restore_checkpoint restores from checkpoint" {
    _start_task "my_task"
    task_add_step "step1"
    task_step_complete "step1"
    task_checkpoint "checkpoint1"
    task_step_fail "step1" "broken after checkpoint"
    task_restore_checkpoint "checkpoint1"
    status=$(task_step_status "step1")
    [ "$status" = "completed" ]
}

@test "task_set stores arbitrary data" {
    _start_task "my_task"
    task_set "mykey" "myvalue"
    result=$(task_get "mykey")
    [ "$result" = "myvalue" ]
}

@test "task_get returns empty for missing key" {
    _start_task "my_task"
    result=$(task_get "nonexistent")
    [ -z "$result" ]
}

@test "task_summary reports completed task when all steps complete" {
    _start_task "my_task"
    task_add_step "step1"
    task_step_complete "step1"
    summary=$(task_summary)
    [[ "$summary" == *'"status":"completed"'* ]]
}

@test "task_summary reports pending task with incomplete steps" {
    _start_task "my_task"
    task_add_step "step1"
    summary=$(task_summary)
    [[ "$summary" == *'"status":"pending"'* ]]
}

@test "task_remaining lists incomplete steps" {
    _start_task "my_task"
    task_add_step "step1"
    task_add_step "step2"
    task_step_complete "step1"
    remaining=$(task_remaining)
    [[ "$remaining" == *"step2"* ]]
    [[ "$remaining" != *"step1"* ]]
}

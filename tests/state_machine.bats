#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/state_machine.bats - State Machine Test Suite
# =============================================================================
# Description: Comprehensive tests for lib/state_machine.sh including workflow
#              definition, execution, visualization, and checkpointing.
# Run: bats tests/state_machine.bats
# =============================================================================

# Test setup
setup() {
    # Create temporary test directory
    export TEST_DIR=$(mktemp -d)
    export STATE_MACHINE_DIR="${TEST_DIR}/state_machines"
    export MAINFRAME_QUIET=1
    
    # Source required libraries
    source "${BATS_TEST_DIRNAME}/../lib/json.sh"
    source "${BATS_TEST_DIRNAME}/../lib/state.sh"
    source "${BATS_TEST_DIRNAME}/../lib/state_machine.sh"
}

# Test teardown
teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================================================
# DEFINITION TESTS
# =============================================================================

@test "state_machine_define creates new machine" {
    local result
    result=$(state_machine_define "test_machine")
    
    [[ "$result" == *'"success":true'* ]]
    [[ "$result" == *'"name":"test_machine"'* ]]
    [[ -d "$STATE_MACHINE_DIR/test_machine" ]]
}

@test "state_machine_define validates name" {
    run state_machine_define "invalid/name"

    [[ "$status" -eq 1 ]]
    [[ "$output" == *'"success":false'* ]]
}

@test "state_machine_add_state adds state to machine" {
    state_machine_define "test_add_state" >/dev/null
    
    local result
    result=$(state_machine_add_state "test_add_state" "start" \
        --on_enter "on_start" \
        --on_exit "on_exit_start" \
        --transitions '{"go": "middle"}')
    
    [[ "$result" == *'"success":true'* ]]
    [[ "$result" == *'"state":"start"'* ]]
}

@test "state_machine_add_state validates state name" {
    state_machine_define "test_bad_state" >/dev/null

    run state_machine_add_state "test_bad_state" "invalid/state"

    [[ "$status" -eq 1 ]]
    [[ "$output" == *'"success":false'* ]]
}

@test "state_machine_add_state supports final states" {
    state_machine_define "test_final" >/dev/null
    
    local result
    result=$(state_machine_add_state "test_final" "end" --final)
    
    [[ "$result" == *'"success":true'* ]]
}

@test "state_machine_set_initial sets initial state" {
    state_machine_define "test_initial" >/dev/null
    state_machine_add_state "test_initial" "first" --transitions '{}' >/dev/null
    
    local result
    result=$(state_machine_set_initial "test_initial" "first")
    
    [[ "$result" == *'"success":true'* ]]
    [[ "$result" == *'"initial":"first"'* ]]
}

# =============================================================================
# EXECUTION TESTS
# =============================================================================

@test "state_machine_run executes machine" {
    local runner="$TEST_DIR/run_state_machine.sh"
    cat > "$runner" <<EOF
#!/usr/bin/env bash
source "${BATS_TEST_DIRNAME}/../lib/json.sh"
source "${BATS_TEST_DIRNAME}/../lib/state.sh"
source "${BATS_TEST_DIRNAME}/../lib/state_machine.sh"
export MAINFRAME_QUIET=1
export STATE_MACHINE_DIR="$STATE_MACHINE_DIR"
state_machine_define "test_run" >/dev/null
state_machine_add_state "test_run" "start" --transitions '{"complete": "end"}' >/dev/null
state_machine_add_state "test_run" "end" --final >/dev/null
state_machine_run "test_run" --initial "start" --event_timeout 1 >/dev/null
EOF
    chmod +x "$runner"

    # Run in background to avoid blocking
    bash "$runner" &
    local run_pid=$!
    
    # Give it time to start
    sleep 0.5
    
    # Send completion event
    state_machine_send_event "test_run" --event "complete" >/dev/null
    
    local state_file="$STATE_MACHINE_DIR/test_run/machine_state.json"
    local machine_state=""
    local attempt=0
    while [[ $attempt -lt 20 ]]; do
        [[ -f "$state_file" ]] && machine_state=$(<"$state_file")
        [[ "$machine_state" == *'"current_state":"end"'* ]] && [[ "$machine_state" == *'"status":"completed"'* ]] && break
        sleep 0.1
        attempt=$((attempt + 1))
    done

    kill "$run_pid" 2>/dev/null || true
    wait "$run_pid" 2>/dev/null || true
    
    [[ "$machine_state" == *'"current_state":"end"'* ]]
    [[ "$machine_state" == *'"status":"completed"'* ]]
}

@test "state_machine_send_event sends event to machine" {
    state_machine_define "test_event" >/dev/null
    
    local result
    result=$(state_machine_send_event "test_event" --event "test" --data '{"key":"value"}')
    
    [[ "$result" == *'"success":true'* ]]
    [[ -f "$STATE_MACHINE_DIR/test_event/pending_event.json" ]]
}

@test "state_machine_send_event validates event name" {
    state_machine_define "test_no_event" >/dev/null

    run state_machine_send_event "test_no_event" --data '{"key":"value"}'

    [[ "$status" -eq 1 ]]
    [[ "$output" == *'"success":false'* ]]
}

# =============================================================================
# STATUS & CONTROL TESTS
# =============================================================================

@test "state_machine_status returns machine status" {
    state_machine_define "test_status" >/dev/null
    state_machine_add_state "test_status" "idle" >/dev/null
    
    # Initialize state file
    state_machine_run "test_status" --initial "idle" --event_timeout 0 &
    sleep 0.2
    
    local result
    result=$(state_machine_status "test_status")
    
    [[ "$result" == *'"success":true'* ]]
    [[ "$result" == *'"machine":"test_status"'* ]]
}

@test "state_machine_status handles missing machine" {
    run state_machine_status "nonexistent_xyz"

    [[ "$status" -eq 1 ]]
    [[ "$output" == *'"success":false'* ]]
}

@test "state_machine_pause pauses machine" {
    state_machine_define "test_pause" >/dev/null
    state_machine_add_state "test_pause" "idle" >/dev/null
    
    # Initialize
    state_machine_run "test_pause" --initial "idle" --event_timeout 0 &
    sleep 0.2
    
    local result
    result=$(state_machine_pause "test_pause")
    
    [[ "$result" == *'"success":true'* ]]
    [[ "$result" == *'"status":"paused"'* ]]
    [[ -f "$STATE_MACHINE_DIR/test_pause/.paused" ]]
}

@test "state_machine_resume resumes machine" {
    state_machine_define "test_resume" >/dev/null
    state_machine_add_state "test_resume" "idle" >/dev/null
    
    # Initialize and pause
    state_machine_run "test_resume" --initial "idle" --event_timeout 0 &
    sleep 0.2
    state_machine_pause "test_resume" >/dev/null
    
    local result
    result=$(state_machine_resume "test_resume")
    
    [[ "$result" == *'"success":true'* ]]
    [[ "$result" == *'"status":"running"'* ]]
    [[ ! -f "$STATE_MACHINE_DIR/test_resume/.paused" ]]
}

# =============================================================================
# CHECKPOINT TESTS
# =============================================================================

@test "state_machine_checkpoint creates checkpoint" {
    state_machine_define "test_checkpoint" >/dev/null
    state_machine_add_state "test_checkpoint" "active" >/dev/null
    
    # Initialize state
    state_machine_run "test_checkpoint" --initial "active" --event_timeout 0 &
    sleep 0.2
    
    local result
    result=$(state_machine_checkpoint "test_checkpoint")
    
    [[ "$result" == *'"success":true'* ]]
    [[ -f "$STATE_MACHINE_DIR/test_checkpoint/checkpoint.json" ]]
}

@test "state_machine_checkpoint fails for non-running machine" {
    state_machine_define "test_no_checkpoint" >/dev/null

    run state_machine_checkpoint "test_no_checkpoint"

    [[ "$status" -eq 1 ]]
    [[ "$output" == *'"success":false'* ]]
}

@test "state_machine_resume_from_checkpoint restores state" {
    state_machine_define "test_restore" >/dev/null
    state_machine_add_state "test_restore" "saved" >/dev/null
    
    # Initialize and checkpoint
    state_machine_run "test_restore" --initial "saved" --event_timeout 0 &
    sleep 0.2
    state_machine_checkpoint "test_restore" >/dev/null
    
    local result
    result=$(state_machine_resume_from_checkpoint "test_restore")
    
    [[ "$result" == *'"success":true'* ]]
}

@test "state_machine_resume_from_checkpoint fails without checkpoint" {
    state_machine_define "test_no_restore" >/dev/null

    run state_machine_resume_from_checkpoint "test_no_restore"

    [[ "$status" -eq 1 ]]
    [[ "$output" == *'"success":false'* ]]
    [[ "$output" == *'No checkpoint found'* ]]
}

@test "state_machine_replay resets machine" {
    state_machine_define "test_replay" >/dev/null
    state_machine_add_state "test_replay" "start" >/dev/null
    state_machine_add_state "test_replay" "middle" >/dev/null
    
    # Initialize
    state_machine_run "test_replay" --initial "start" --event_timeout 0 &
    sleep 0.2
    
    local result
    result=$(state_machine_replay "test_replay")
    
    [[ "$result" == *'"success":true'* ]]
    [[ "$result" == *'"replayed":true'* ]]
}

@test "state_machine_replay supports --from parameter" {
    state_machine_define "test_replay_from" >/dev/null
    state_machine_add_state "test_replay_from" "start" >/dev/null
    state_machine_add_state "test_replay_from" "custom" >/dev/null
    
    # Initialize
    state_machine_run "test_replay_from" --initial "start" --event_timeout 0 &
    sleep 0.2
    
    local result
    result=$(state_machine_replay "test_replay_from" --from "custom")
    
    [[ "$result" == *'"success":true'* ]]
    [[ "$result" == *'"starting_state":"custom"'* ]]
}

# =============================================================================
# VISUALIZATION TESTS
# =============================================================================

@test "state_machine_visualize outputs diagram" {
    state_machine_define "test_viz" >/dev/null
    state_machine_add_state "test_viz" "start" --transitions '{"go": "end"}' >/dev/null
    state_machine_add_state "test_viz" "end" --final >/dev/null
    
    local output
    output=$(state_machine_visualize "test_viz")
    
    [[ "$output" == *'State Machine: test_viz'* ]]
    [[ "$output" == *'start'* ]]
    [[ "$output" == *'end'* ]]
}

@test "state_machine_visualize handles missing machine" {
    run state_machine_visualize "nonexistent_viz"

    [[ "$status" -eq 1 ]]
    [[ "$output" == *'Error'* ]]
}

@test "state_machine_to_dot generates DOT format" {
    state_machine_define "test_dot" >/dev/null
    state_machine_add_state "test_dot" "a" --transitions '{"next": "b"}' >/dev/null
    state_machine_add_state "test_dot" "b" --final >/dev/null
    
    local output
    output=$(state_machine_to_dot "test_dot")
    
    [[ "$output" == *'digraph test_dot'* ]]
    [[ "$output" == *'"a"'* ]]
    [[ "$output" == *'"b"'* ]]
}

@test "state_machine_to_dot outputs to file" {
    state_machine_define "test_dot_file" >/dev/null
    state_machine_add_state "test_dot_file" "a" >/dev/null
    
    local output_file="$TEST_DIR/output.dot"
    state_machine_to_dot "test_dot_file" --output "$output_file"
    
    [[ -f "$output_file" ]]
    [[ "$(head -1 "$output_file")" == *'digraph test_dot_file'* ]]
}

# =============================================================================
# LISTING & CLEANUP TESTS
# =============================================================================

@test "state_machine_list shows machines" {
    state_machine_define "test_list_a" >/dev/null
    state_machine_define "test_list_b" >/dev/null
    
    local result
    result=$(state_machine_list)
    
    [[ "$result" == *'test_list_a'* ]]
    [[ "$result" == *'test_list_b'* ]]
}

@test "state_machine_list --json returns JSON" {
    state_machine_define "test_list_json" >/dev/null
    
    local result
    result=$(state_machine_list --json)
    
    [[ "$result" == '['* ]]
    [[ "$result" == *']' ]]
}

@test "state_machine_destroy removes machine" {
    state_machine_define "test_destroy" >/dev/null
    
    local result
    result=$(state_machine_destroy "test_destroy")
    
    [[ "$result" == *'"success":true'* ]]
    [[ ! -d "$STATE_MACHINE_DIR/test_destroy" ]]
}

@test "state_machine_destroy handles missing machine" {
    local result
    result=$(state_machine_destroy "nonexistent_destroy")
    
    [[ "$result" == *'"success":false'* ]]
}

# =============================================================================
# COMPLEX WORKFLOW TESTS
# =============================================================================

@test "state_machine supports multi-state workflow" {
    state_machine_define "test_workflow" >/dev/null
    
    # Create a simple workflow: start -> process -> end
    state_machine_add_state "test_workflow" "start" \
        --transitions '{"process": "processing"}' >/dev/null
    
    state_machine_add_state "test_workflow" "processing" \
        --transitions '{"complete": "end", "fail": "error"}' \
        --timeout 60 \
        --retries 3 >/dev/null
    
    state_machine_add_state "test_workflow" "end" --final >/dev/null
    state_machine_add_state "test_workflow" "error" --final >/dev/null
    
    # Verify all states were added
    local dir
    dir="$STATE_MACHINE_DIR/test_workflow"
    [[ -d "$dir" ]]
}

@test "state_machine handles transition wildcards" {
    state_machine_define "test_wildcard" >/dev/null
    
    # State with wildcard transition
    state_machine_add_state "test_wildcard" "any" \
        --transitions '{"*": "next"}' >/dev/null
    
    state_machine_add_state "test_wildcard" "next" --final >/dev/null
    
    local result
    result=$(state_machine_status "test_wildcard" 2>/dev/null || echo '{}')
    
    # Should be able to define without error
    [[ -d "$STATE_MACHINE_DIR/test_wildcard" ]]
}

# =============================================================================
# CALLBACK TESTS
# =============================================================================

@test "state_machine_add_state accepts callback functions" {
    state_machine_define "test_callbacks" >/dev/null
    
    # Define callbacks
    on_enter_test() { echo "entered"; }
    on_exit_test() { echo "exited"; }
    export -f on_enter_test on_exit_test
    
    local result
    result=$(state_machine_add_state "test_callbacks" "state1" \
        --on_enter "on_enter_test" \
        --on_exit "on_exit_test")
    
    [[ "$result" == *'"success":true'* ]]
}

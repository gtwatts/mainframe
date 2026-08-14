#!/usr/bin/env bats
# =============================================================================
# INTEGRATION TEST: Agent + AWM Workflow
# =============================================================================
# Tests the integration between Agent module and Agent Working Memory (AWM)
# Scenario: Agent uses AWM for long-running task with context window management
# =============================================================================

load '../test_helper'

setup() {
    # Create isolated test environment
    TEST_BASE=$(mktemp -d)
    TEST_BASE="$(cd "$TEST_BASE" && pwd -P)"
    export MAINFRAME_AGENT_DIR="$TEST_BASE/agents"
    export AWM_ROOT="$TEST_BASE/awm"
    export MAINFRAME_QUIET=1
    
    # Source required libraries
    source "$MAINFRAME_ROOT/lib/json.sh"
    source "$MAINFRAME_ROOT/lib/agent.sh"
    source "$MAINFRAME_ROOT/lib/awm.sh"
}

teardown() {
    # Cleanup test environment
    rm -rf "$TEST_BASE"
    
    # Reset module state
    unset _MAINFRAME_AGENT_LOADED
    unset _MAINFRAME_AWM_LOADED
    unset _MAINFRAME_AGENT_NAME
    unset _MAINFRAME_AGENT_SEQ
}

# =============================================================================
# COMPLETE AGENT + AWM WORKFLOW TEST
# =============================================================================

@test "complete agent workflow with AWM for long-running task" {
    # Step 1: Initialize agent
    agent_register "worker1" "compute" "storage"
    [ -d "$MAINFRAME_AGENT_DIR/worker1" ]
    [ "$agent_name" = "worker1" ] || [ "$_MAINFRAME_AGENT_NAME" = "worker1" ]
    
    # Step 2: Create AWM session for the task
    local sid
    sid=$(awm_init "long_running_task")
    [ -n "$sid" ]
    [[ "$sid" =~ ^[a-f0-9]{12}$ ]]
    
    # Step 3: Store initial task state in AWM
    awm_set "$sid" "task_name" "data_processing_pipeline"
    awm_set "$sid" "step" "1"
    awm_set "$sid" "status" "running"
    awm_set "$sid" "data" '{"records": 1000, "processed": 0}'
    
    # Verify data persistence
    local task_name
    task_name=$(awm_get "$sid" "task_name")
    [ "$task_name" = "data_processing_pipeline" ]
    
    local step
    step=$(awm_get "$sid" "step")
    [ "$step" = "1" ]
    
    # Step 4: Simulate work progress - update step counter
    awm_set "$sid" "step" "2"
    awm_set "$sid" "data" '{"records": 1000, "processed": 500}'
    
    # Step 5: Append to log (simulating context window pressure management)
    awm_append "$sid" "log" "Started processing at $(_awm_iso_timestamp)"
    awm_append "$sid" "log" "Processed batch 1: 500 records"
    awm_append "$sid" "log" "Memory usage: 45%"
    
    # Step 6: Simulate checkpoint (context window pressure)
    awm_checkpoint "$sid" "after_batch_1"
    [ -d "$AWM_ROOT/sessions/$sid/checkpoints" ]
    
    # Step 7: Continue work after "context refresh"
    awm_set "$sid" "step" "3"
    awm_set "$sid" "data" '{"records": 1000, "processed": 1000}'
    awm_append "$sid" "log" "Processed batch 2: 500 records"
    awm_append "$sid" "log" "Task completed successfully"
    
    # Step 8: Verify all data integrity after "context refresh"
    local final_step
    final_step=$(awm_get "$sid" "step")
    [ "$final_step" = "3" ]
    
    local final_data
    final_data=$(awm_get "$sid" "data")
    [[ "$final_data" == *"processed\": 1000"* ]] || [[ "$final_data" == *"processed\":1000"* ]]
    
    # Step 9: Verify log has all entries
    local log_count
    log_count=$(awm_get "$sid" "log" | wc -l)
    [ "$log_count" -ge 4 ]
    
    # Step 10: Retrieve checkpoint and verify
    local checkpoint_data
    checkpoint_data=$(awm_get_checkpoint "$sid" "after_batch_1")
    [ -n "$checkpoint_data" ]
    
    # Step 11: Cleanup
    awm_destroy "$sid"
    [ ! -d "$AWM_ROOT/sessions/$sid" ]
    
    agent_unregister "worker1"
    [ ! -d "$MAINFRAME_AGENT_DIR/worker1" ]
}

@test "agent uses AWM for sub-task delegation" {
    # Register parent agent
    agent_register "parent_agent" "orchestration"
    
    # Create parent session
    local parent_sid
    parent_sid=$(awm_init "parent_task")
    awm_set "$parent_sid" "subtasks" "3"
    awm_set "$parent_sid" "completed" "0"
    
    # Simulate creating sub-agent sessions
    local child_sid1 child_sid2
    child_sid1=$(awm_init "subtask_1")
    child_sid2=$(awm_init "subtask_2")
    
    # Link child sessions to parent
    awm_set "$child_sid1" "parent_session" "$parent_sid"
    awm_set "$child_sid1" "task" "fetch_data"
    awm_set "$child_sid2" "parent_session" "$parent_sid"
    awm_set "$child_sid2" "task" "process_data"
    
    # Simulate child task completion
    awm_set "$child_sid1" "status" "completed"
    awm_set "$child_sid1" "result" '{"fetched": 100}'
    awm_set "$child_sid2" "status" "completed"
    awm_set "$child_sid2" "result" '{"processed": 100}'
    
    # Parent aggregates results
    local result1 result2
    result1=$(awm_get "$child_sid1" "result")
    result2=$(awm_get "$child_sid2" "result")
    [ -n "$result1" ]
    [ -n "$result2" ]
    
    # Cleanup all sessions
    awm_destroy "$child_sid1"
    awm_destroy "$child_sid2"
    awm_destroy "$parent_sid"
    agent_unregister "parent_agent"
}

@test "agent resumes work from AWM after simulated crash" {
    agent_register "resilient_worker" "compute"
    
    # Create session and store state
    local sid
    sid=$(awm_init "resilient_task")
    awm_set "$sid" "iteration" "42"
    awm_set "$sid" "last_processed_id" "user_12345"
    awm_set "$sid" "accumulated_result" "1500"
    awm_append "$sid" "processing_log" "Iteration 42: processed user_12345"
    
    # Simulate crash - destroy session reference but keep data
    _AWM_SESSION_ID=""
    
    # Resume - re-discover session
    local sessions
    sessions=$(awm_list_sessions)
    [[ "$sessions" == *"$sid"* ]]
    
    # Recover state
    local iteration last_id
    iteration=$(awm_get "$sid" "iteration")
    last_id=$(awm_get "$sid" "last_processed_id")
    
    [ "$iteration" = "42" ]
    [ "$last_id" = "user_12345" ]
    
    # Continue from where we left off
    awm_set "$sid" "iteration" "43"
    awm_set "$sid" "status" "recovered_and_continuing"
    
    # Verify
    local new_iteration
    new_iteration=$(awm_get "$sid" "iteration")
    [ "$new_iteration" = "43" ]
    
    awm_destroy "$sid"
    agent_unregister "resilient_worker"
}

@test "multiple agents share AWM session safely" {
    # Register multiple agents
    agent_register "agent_a" "reader"
    agent_register "agent_b" "writer"
    agent_register "agent_c" "validator"
    
    # Create shared session
    local shared_sid
    shared_sid=$(awm_init "collaborative_task")
    
    # Agent B writes data
    awm_set "$shared_sid" "input_data" '{"items": [1,2,3,4,5]}'
    awm_set "$shared_sid" "status" "processing"
    
    # Agent A reads and processes
    local data
    data=$(awm_get "$shared_sid" "input_data")
    [ -n "$data" ]
    awm_set "$shared_sid" "processed_by" "agent_a"
    
    # Agent C validates
    local processed_by
    processed_by=$(awm_get "$shared_sid" "processed_by")
    [ "$processed_by" = "agent_a" ]
    awm_set "$shared_sid" "validated_by" "agent_c"
    awm_set "$shared_sid" "status" "completed"
    
    # Verify final state
    local final_status
    final_status=$(awm_get "$shared_sid" "status")
    [ "$final_status" = "completed" ]
    
    local validated_by
    validated_by=$(awm_get "$shared_sid" "validated_by")
    [ "$validated_by" = "agent_c" ]
    
    awm_destroy "$shared_sid"
    agent_unregister "agent_a"
    agent_unregister "agent_b"
    agent_unregister "agent_c"
}

@test "AWM memory management under simulated context pressure" {
    agent_register "memory_manager" "optimization"
    
    local sid
    sid=$(awm_init "memory_intensive_task")
    
    # Simulate storing large amounts of data
    local i
    for i in {1..50}; do
        awm_set "$sid" "chunk_$i" "$(printf 'x%.0s' {1..1000})"
    done
    
    # Verify we can still retrieve early and late chunks
    local chunk1 chunk50
    chunk1=$(awm_get "$sid" "chunk_1")
    chunk50=$(awm_get "$sid" "chunk_50")
    
    [ "${#chunk1}" -eq 1000 ]
    [ "${#chunk50}" -eq 1000 ]
    
    # Simulate "compression" by removing old chunks
    for i in {1..25}; do
        awm_unset "$sid" "chunk_$i"
    done
    
    # Verify old chunks are gone but new ones remain
    run awm_get "$sid" "chunk_1"
    [ "$status" -ne 0 ] || [ -z "$output" ]
    
    chunk50=$(awm_get "$sid" "chunk_50")
    [ "${#chunk50}" -eq 1000 ]
    
    awm_destroy "$sid"
    agent_unregister "memory_manager"
}

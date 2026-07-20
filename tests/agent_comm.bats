#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Agent Communication Protocol Tests
# =============================================================================
# Comprehensive tests for lib/agent_comm.sh
# Covers: identity, message passing, status, task coordination, shared state,
#         cleanup functionality
# =============================================================================

load 'test_helper'

setup() {
    source_lib "json"
    export AGENT_BASE_DIR="/tmp/mainframe_agents"
    source_lib "agent_comm"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "agent_comm")

    # Clean up any previous test agents
    rm -rf /tmp/mainframe_agents

    # Initialize a test agent for most tests
    AGENT_RESULT=$(agent_init "test_agent")
    AGENT_ID=$(json_get "$AGENT_RESULT" "agent_id")
}

teardown() {
    # Clean shutdown if we have an agent
    [[ -n "$AGENT_ID" ]] && agent_shutdown >/dev/null 2>&1
    cleanup_test_dir "$TEST_DIR"

    # Full cleanup of agent infrastructure
    rm -rf /tmp/mainframe_agents
}

# =============================================================================
# 1. AGENT IDENTITY TESTS
# =============================================================================

@test "agent_init creates unique agent ID" {
    local result
    result=$(json_get "$AGENT_RESULT" "agent_id")
    [[ "$result" =~ ^test_agent_[0-9]+_[0-9]+$ ]]
}

@test "agent_init creates workspace directories" {
    local workspace
    workspace=$(json_get "$AGENT_RESULT" "workspace")
    [ -d "$workspace/inbox" ]
    [ -d "$workspace/outbox" ]
    [ -d "$workspace/status" ]
}

@test "agent_init registers agent in registry" {
    [ -f "/tmp/mainframe_agents/registry/$AGENT_ID.json" ]
}

@test "agent_register stores correct agent info" {
    local registry_file="/tmp/mainframe_agents/registry/$AGENT_ID.json"
    local data
    data=$(<"$registry_file")

    local stored_id stored_pid
    stored_id=$(json_get "$data" "id")
    stored_pid=$(json_get "$data" "pid")

    [ "$stored_id" = "$AGENT_ID" ]
    [ "$stored_pid" = "$$" ]
}

@test "agent_add_capability updates registration" {
    agent_add_capability "file_processing"
    agent_add_capability "data_analysis"

    local registry_file="/tmp/mainframe_agents/registry/$AGENT_ID.json"
    local data
    data=$(<"$registry_file")

    # Check capabilities are in the JSON
    [[ "$data" == *"file_processing"* ]]
    [[ "$data" == *"data_analysis"* ]]
}

@test "agent_remove_capability updates registration" {
    agent_add_capability "temp_cap"
    agent_remove_capability "temp_cap"

    local registry_file="/tmp/mainframe_agents/registry/$AGENT_ID.json"
    local data
    data=$(<"$registry_file")

    # Capability should not be in JSON (unless in a different context)
    [[ "$data" != *'"temp_cap"'* ]]
}

@test "agent_info returns agent data" {
    local info
    info=$(agent_info)

    local info_id
    info_id=$(json_get "$info" "id")
    [ "$info_id" = "$AGENT_ID" ]
}

@test "agent_info returns error for unknown agent" {
    local info
    info=$(agent_info "nonexistent_agent_12345")

    local success
    success=$(json_get "$info" "success")
    [ "$success" = "false" ]
}

# =============================================================================
# 2. MESSAGE PASSING TESTS
# =============================================================================

@test "agent_send delivers message to inbox" {
    # Create a second agent
    local agent1_id="$AGENT_ID"

    # Manually create inbox for a fake agent
    local fake_agent="fake_agent_123"
    mkdir -p "/tmp/mainframe_agents/$fake_agent/inbox"

    local result
    result=$(agent_send "$fake_agent" "test_message" "hello world")

    local success
    success=$(json_get "$result" "success")
    [ "$success" = "true" ]

    # Check message was delivered
    local msg_count
    msg_count=$(ls -1 "/tmp/mainframe_agents/$fake_agent/inbox"/*.json 2>/dev/null | wc -l)
    [ "$msg_count" -eq 1 ]
}

@test "agent_send returns error for nonexistent agent" {
    local result
    result=$(agent_send "nonexistent_agent" "test" "payload")

    local success
    success=$(json_get "$result" "success")
    [ "$success" = "false" ]
}

@test "agent_send includes correct message fields" {
    local fake_agent="fake_receiver"
    mkdir -p "/tmp/mainframe_agents/$fake_agent/inbox"

    agent_send "$fake_agent" "greeting" "hello"

    local msg_file
    msg_file=$(ls -1 "/tmp/mainframe_agents/$fake_agent/inbox"/*.json | head -1)
    local msg_data
    msg_data=$(<"$msg_file")

    local msg_type msg_from msg_to
    msg_type=$(json_get "$msg_data" "type")
    msg_from=$(json_get "$msg_data" "from")
    msg_to=$(json_get "$msg_data" "to")

    [ "$msg_type" = "greeting" ]
    [ "$msg_from" = "$AGENT_ID" ]
    [ "$msg_to" = "$fake_agent" ]
}

@test "agent_receive gets oldest message first" {
    # Send multiple messages to our inbox
    mkdir -p "/tmp/mainframe_agents/$AGENT_ID/inbox"

    # Create messages with different timestamps
    echo '{"id":"msg_1","from":"other","type":"first","payload":"one"}' \
        > "/tmp/mainframe_agents/$AGENT_ID/inbox/msg_001.json"
    sleep 0.1
    echo '{"id":"msg_2","from":"other","type":"second","payload":"two"}' \
        > "/tmp/mainframe_agents/$AGENT_ID/inbox/msg_002.json"

    local first_msg
    first_msg=$(agent_receive)

    local msg_type
    msg_type=$(json_get "$first_msg" "type")
    [ "$msg_type" = "first" ]
}

@test "agent_receive removes message after reading" {
    mkdir -p "/tmp/mainframe_agents/$AGENT_ID/inbox"
    echo '{"id":"msg_test","type":"test"}' \
        > "/tmp/mainframe_agents/$AGENT_ID/inbox/msg_test.json"

    agent_receive
    [ ! -f "/tmp/mainframe_agents/$AGENT_ID/inbox/msg_test.json" ]
}

@test "agent_receive returns immediately if no timeout and no messages" {
    local start=$SECONDS
    agent_receive 0 || true
    local elapsed=$((SECONDS - start))
    [ "$elapsed" -lt 2 ]
}

@test "agent_peek shows messages without removing" {
    mkdir -p "/tmp/mainframe_agents/$AGENT_ID/inbox"
    echo '{"id":"msg_peek","type":"peek_test"}' \
        > "/tmp/mainframe_agents/$AGENT_ID/inbox/msg_peek.json"

    agent_peek
    [ -f "/tmp/mainframe_agents/$AGENT_ID/inbox/msg_peek.json" ]
}

@test "agent_broadcast sends to multiple agents" {
    # Create fake agents
    for i in 1 2 3; do
        local fake_id="fake_broadcast_$i"
        mkdir -p "/tmp/mainframe_agents/$fake_id/inbox"
        # Create registration with our PID so they appear alive
        echo "{\"id\":\"$fake_id\",\"pid\":$$}" \
            > "/tmp/mainframe_agents/registry/$fake_id.json"
    done

    local result
    result=$(agent_broadcast "announcement" "hello all")

    local sent
    sent=$(json_get "$result" "sent")
    [ "$sent" -eq 3 ]
}

# =============================================================================
# 3. STATUS REPORTING TESTS
# =============================================================================

@test "agent_status writes status file" {
    agent_status "working" "processing data"

    local status_file="/tmp/mainframe_agents/$AGENT_ID/status/current.json"
    [ -f "$status_file" ]
}

@test "agent_status stores correct values" {
    agent_status "idle" "waiting for work"

    local status_file="/tmp/mainframe_agents/$AGENT_ID/status/current.json"
    local data
    data=$(<"$status_file")

    local status details
    status=$(json_get "$data" "status")
    details=$(json_get "$data" "details")

    [ "$status" = "idle" ]
    [ "$details" = "waiting for work" ]
}

@test "agent_get_status retrieves status" {
    agent_status "busy" "crunching numbers"

    local status_data
    status_data=$(agent_get_status "$AGENT_ID")

    local status
    status=$(json_get "$status_data" "status")
    [ "$status" = "busy" ]
}

@test "agent_get_status returns unknown for nonexistent agent" {
    local status_data
    status_data=$(agent_get_status "nonexistent_agent")

    local status
    status=$(json_get "$status_data" "status")
    [ "$status" = "unknown" ]
}

@test "agent_list includes current agent" {
    local agents
    agents=$(agent_list)
    [[ "$agents" == *"$AGENT_ID"* ]]
}

@test "agent_list excludes dead agents" {
    # Create a fake dead agent (PID that doesn't exist)
    mkdir -p "/tmp/mainframe_agents/dead_agent_999"
    echo '{"id":"dead_agent_999","pid":999999}' \
        > "/tmp/mainframe_agents/registry/dead_agent_999.json"

    local agents
    agents=$(agent_list)

    # Dead agent should be cleaned up and not in list
    [[ "$agents" != *"dead_agent_999"* ]]
}

@test "agent_find_by_capability finds matching agents" {
    agent_add_capability "special_skill"

    local found
    found=$(agent_find_by_capability "special_skill")

    [[ "$found" == *"$AGENT_ID"* ]]
}

# =============================================================================
# 4. TASK COORDINATION TESTS
# =============================================================================

@test "agent_create_task creates task directory" {
    local result
    result=$(agent_create_task "task_001" "Test task")

    [ -d "/tmp/mainframe_agents/tasks/task_001" ]
    [ -f "/tmp/mainframe_agents/tasks/task_001/task.json" ]
}

@test "agent_claim_task succeeds for unclaimed task" {
    agent_create_task "claim_test" "A task to claim"

    local result
    result=$(agent_claim_task "claim_test")

    local success
    success=$(json_get "$result" "success")
    [ "$success" = "true" ]
}

@test "agent_claim_task fails for already claimed task" {
    agent_create_task "contested_task" "Contested"
    agent_claim_task "contested_task"

    # Save current agent ID
    local first_agent="$AGENT_ID"

    # Try to claim from "another agent" (simulate by changing AGENT_ID)
    AGENT_ID="other_agent_$$"

    local result
    result=$(agent_claim_task "contested_task")

    local success
    success=$(json_get "$result" "success")
    [ "$success" = "false" ]

    # Restore
    AGENT_ID="$first_agent"
}

@test "agent_claim_task is atomic (mkdir-based)" {
    agent_create_task "atomic_test" "Atomic claim test"
    agent_claim_task "atomic_test"

    # The claim directory should exist
    [ -d "/tmp/mainframe_agents/tasks/atomic_test/claimed_by_$AGENT_ID" ]
}

@test "agent_complete_task stores result" {
    agent_create_task "complete_test" "Task to complete"
    agent_claim_task "complete_test"
    agent_complete_task "complete_test" "task completed successfully"

    [ -f "/tmp/mainframe_agents/tasks/complete_test/result.json" ]

    local result_data
    result_data=$(<"/tmp/mainframe_agents/tasks/complete_test/result.json")
    local result_text
    result_text=$(json_get "$result_data" "result")
    [ "$result_text" = "task completed successfully" ]
}

@test "agent_fail_task releases claim" {
    agent_create_task "fail_test" "Task that will fail"
    agent_claim_task "fail_test"
    agent_fail_task "fail_test" "something went wrong"

    # Claim directory should be removed
    [ ! -d "/tmp/mainframe_agents/tasks/fail_test/claimed_by_$AGENT_ID" ]

    # Error file should exist
    [ -f "/tmp/mainframe_agents/tasks/fail_test/error.json" ]
}

@test "agent_wait_task returns result when complete" {
    agent_create_task "wait_test" "Task to wait for"

    # Complete the task in background
    (
        sleep 0.2
        echo '{"task_id":"wait_test","result":"done"}' \
            > "/tmp/mainframe_agents/tasks/wait_test/result.json"
    ) &

    local result
    result=$(agent_wait_task "wait_test" 5)

    local task_result
    task_result=$(json_get "$result" "result")
    [ "$task_result" = "done" ]
}

@test "agent_wait_task times out correctly" {
    agent_create_task "timeout_test" "Task that never completes"

    local start=$SECONDS
    local result
    result=$(agent_wait_task "timeout_test" 1) || true
    local elapsed=$((SECONDS - start))

    [ "$elapsed" -ge 1 ]
    [ "$elapsed" -lt 3 ]

    local error
    error=$(json_get "$result" "error")
    [[ "$error" == *"timeout"* ]]
}

@test "agent_task_status shows correct state" {
    agent_create_task "status_test" "Status test task"

    # Check pending
    local status
    status=$(agent_task_status "status_test")
    [ "$(json_get "$status" "status")" = "pending" ]

    # Claim and check in_progress
    agent_claim_task "status_test"
    status=$(agent_task_status "status_test")
    [ "$(json_get "$status" "status")" = "in_progress" ]

    # Complete and check completed
    agent_complete_task "status_test" "done"
    status=$(agent_task_status "status_test")
    [ "$(json_get "$status" "status")" = "completed" ]
}

@test "agent_list_tasks returns all tasks" {
    agent_create_task "list_task_1" "First"
    agent_create_task "list_task_2" "Second"

    local tasks
    tasks=$(agent_list_tasks)

    [[ "$tasks" == *"list_task_1"* ]]
    [[ "$tasks" == *"list_task_2"* ]]
}

# =============================================================================
# 5. SHARED STATE TESTS
# =============================================================================

@test "agent_state_set creates state file" {
    agent_state_set "test_key" "test_value"
    [ -f "/tmp/mainframe_agents/shared_state/test_key" ]
}

@test "agent_state_get retrieves value" {
    agent_state_set "get_test" "hello world"

    local value
    value=$(agent_state_get "get_test")
    [ "$value" = "hello world" ]
}

@test "agent_state_get returns default for missing key" {
    local value
    value=$(agent_state_get "nonexistent_key" "default_value")
    [ "$value" = "default_value" ]
}

@test "agent_state_del removes state" {
    agent_state_set "del_test" "to be deleted"
    agent_state_del "del_test"
    [ ! -f "/tmp/mainframe_agents/shared_state/del_test" ]
}

@test "agent_state_exists returns correct status" {
    agent_state_set "exists_test" "value"
    agent_state_exists "exists_test"

    ! agent_state_exists "nonexistent_test"
}

@test "agent_state_incr increments counter" {
    agent_state_set "counter" "5"

    local new_val
    new_val=$(agent_state_incr "counter" 3)
    [ "$new_val" -eq 8 ]

    local stored
    stored=$(agent_state_get "counter")
    [ "$stored" -eq 8 ]
}

@test "agent_state_incr creates counter if missing" {
    local new_val
    new_val=$(agent_state_incr "new_counter" 10)
    [ "$new_val" -eq 10 ]
}

@test "agent_state_decr decrements counter" {
    agent_state_set "dec_counter" "10"

    local new_val
    new_val=$(agent_state_decr "dec_counter" 3)
    [ "$new_val" -eq 7 ]
}

@test "agent_state_list shows all keys" {
    agent_state_set "key_a" "value_a"
    agent_state_set "key_b" "value_b"

    local keys
    keys=$(agent_state_list)

    [[ "$keys" == *"key_a"* ]]
    [[ "$keys" == *"key_b"* ]]
}

@test "agent_state_cas succeeds when values match" {
    agent_state_set "cas_test" "original"

    agent_state_cas "cas_test" "original" "updated"
    local result=$?
    [ "$result" -eq 0 ]

    local value
    value=$(agent_state_get "cas_test")
    [ "$value" = "updated" ]
}

@test "agent_state_cas fails when values don't match" {
    agent_state_set "cas_fail" "original"

    # CAS should fail and return non-zero
    ! agent_state_cas "cas_fail" "wrong" "updated"

    local value
    value=$(agent_state_get "cas_fail")
    [ "$value" = "original" ]
}

# =============================================================================
# 6. CLEANUP TESTS
# =============================================================================

@test "agent_shutdown removes from registry" {
    local agent_id="$AGENT_ID"
    agent_shutdown

    [ ! -f "/tmp/mainframe_agents/registry/$agent_id.json" ]
}

@test "agent_shutdown removes workspace" {
    local workspace="/tmp/mainframe_agents/$AGENT_ID"
    [ -d "$workspace" ]

    agent_shutdown
    [ ! -d "$workspace" ]
}

@test "agent_shutdown clears AGENT_ID" {
    agent_shutdown
    [ -z "$AGENT_ID" ]
}

@test "agent_cleanup_dead removes dead agents" {
    # Create fake dead agent
    mkdir -p "/tmp/mainframe_agents/dead_agent_cleanup"
    echo '{"id":"dead_agent_cleanup","pid":999998}' \
        > "/tmp/mainframe_agents/registry/dead_agent_cleanup.json"

    local cleaned
    cleaned=$(agent_cleanup_dead)
    [ "$cleaned" -ge 1 ]

    [ ! -f "/tmp/mainframe_agents/registry/dead_agent_cleanup.json" ]
}

@test "agent_cleanup_dead keeps alive agents" {
    local count_before
    count_before=$(ls -1 /tmp/mainframe_agents/registry/*.json 2>/dev/null | wc -l)

    agent_cleanup_dead

    local count_after
    count_after=$(ls -1 /tmp/mainframe_agents/registry/*.json 2>/dev/null | wc -l)

    # Our agent should still be there
    [ -f "/tmp/mainframe_agents/registry/$AGENT_ID.json" ]
}

@test "agent_cleanup_all removes everything" {
    # Create some state
    agent_state_set "cleanup_all_test" "value"
    agent_create_task "cleanup_all_task" "task"

    agent_cleanup_all

    [ ! -d "/tmp/mainframe_agents" ]
}

# =============================================================================
# 7. ERROR REPORTING TESTS
# =============================================================================

@test "agent_error logs to errors.log" {
    agent_error "Something went wrong"

    local error_log="/tmp/mainframe_agents/$AGENT_ID/errors.log"
    [ -f "$error_log" ]

    grep -q "Something went wrong" "$error_log"
}

@test "agent_warn logs to warnings.log" {
    agent_warn "This is a warning"

    local warn_log="/tmp/mainframe_agents/$AGENT_ID/warnings.log"
    [ -f "$warn_log" ]

    grep -q "This is a warning" "$warn_log"
}

@test "agent_progress updates status and returns progress" {
    local progress
    progress=$(agent_progress 50 100 "Processing files")

    local percent
    percent=$(json_get "$progress" "percent")
    [ "$percent" -eq 50 ]

    # Status should be updated
    local status_data
    status_data=$(agent_get_status "$AGENT_ID")
    [[ "$(json_get "$status_data" "details")" == *"50/100"* ]]
}

# =============================================================================
# CONCURRENCY TESTS
# =============================================================================

@test "concurrent task claims are atomic" {
    agent_create_task "concurrent_claim" "Contested task"

    # Run multiple claim attempts in background
    local results_dir="$TEST_DIR/claim_results"
    mkdir -p "$results_dir"

    for i in {1..5}; do
        (
            # Each subprocess is a different "agent"
            AGENT_ID="claimer_$i"
            agent_claim_task "concurrent_claim" > "$results_dir/result_$i.json"
        ) &
    done

    wait

    # Count successful claims
    local success_count=0
    for result_file in "$results_dir"/result_*.json; do
        if grep -q '"success":true' "$result_file"; then
            success_count=$((success_count + 1))
        fi
    done

    # Exactly one should succeed
    [ "$success_count" -eq 1 ]
}

@test "concurrent state increments are atomic" {
    agent_state_set "concurrent_counter" "0"

    # Run multiple increments in background
    for i in {1..10}; do
        agent_state_incr "concurrent_counter" 1 &
    done

    wait

    local final
    final=$(agent_state_get "concurrent_counter")
    [ "$final" -eq 10 ]
}

#!/usr/bin/env bats
# =============================================================================
# INTEGRATION TEST: Multi-Agent Coordination
# =============================================================================
# Tests complex multi-agent scenarios with barriers, signals, and work queues
# Scenario: Distributed task processing with coordination primitives
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
# MULTI-AGENT COORDINATION TESTS
# =============================================================================

@test "work queue distributed processing" {
    # Register coordinator and workers
    agent_register "coordinator" "coordination" "queue_management"
    agent_register "worker_1" "compute" "data_processing"
    agent_register "worker_2" "compute" "data_processing"
    agent_register "worker_3" "compute" "data_processing"
    
    # Create work queue
    local queue_name="data_processing_queue"
    agent_work_queue "$queue_name"
    
    # Coordinator populates work queue
    local tasks=("task_1:process_chunk_1" "task_2:process_chunk_2" "task_3:process_chunk_3" \
                 "task_4:process_chunk_4" "task_5:process_chunk_5" "task_6:process_chunk_6")
    
    for task in "${tasks[@]}"; do
        agent_work_push "$queue_name" "$task"
    done
    
    # Verify queue has all items
    local queue_count
    queue_count=$(agent_work_count "$queue_name")
    [ "$queue_count" -eq 6 ]
    
    # Workers process tasks (simulated)
    local processed=()
    for worker in worker_1 worker_2 worker_3; do
        # Each worker takes 2 tasks
        local task1 task2
        task1=$(agent_work_pop "$queue_name")
        task2=$(agent_work_pop "$queue_name")
        
        if [[ -n "$task1" ]]; then
            processed+=("$worker:$task1")
        fi
        if [[ -n "$task2" ]]; then
            processed+=("$worker:$task2")
        fi
    done
    
    # Verify all tasks were processed
    [ "${#processed[@]}" -eq 6 ]
    
    # Queue should be empty
    queue_count=$(agent_work_count "$queue_name")
    [ "$queue_count" -eq 0 ]
    
    # Cleanup
    agent_work_clear "$queue_name"
    agent_unregister "coordinator"
    agent_unregister "worker_1"
    agent_unregister "worker_2"
    agent_unregister "worker_3"
}

@test "agent barrier synchronization" {
    # Register agents that need to synchronize
    agent_register "sync_agent_1" "compute"
    agent_register "sync_agent_2" "compute"
    agent_register "sync_agent_3" "compute"
    
    local barrier_name="test_barrier"
    local barrier_count="3"
    
    # Create barrier
    agent_barrier_create "$barrier_name" "$barrier_count"
    
    # Simulate agents reaching barrier (in background for parallel test)
    # In real scenario, these would be separate processes
    local results_file="$TEST_BASE/barrier_results"
    touch "$results_file"
    
    # Simulate agent 1 reaching barrier
    (
        _MAINFRAME_AGENT_NAME="sync_agent_1"
        echo "agent_1:before_barrier:$(date +%s%N)" >> "$results_file"
        agent_barrier_wait "$barrier_name" 5  # 5 second timeout
        echo "agent_1:after_barrier:$(date +%s%N)" >> "$results_file"
    ) &
    local pid1=$!
    
    # Simulate agent 2 reaching barrier
    (
        sleep 0.1  # Slight delay
        _MAINFRAME_AGENT_NAME="sync_agent_2"
        echo "agent_2:before_barrier:$(date +%s%N)" >> "$results_file"
        agent_barrier_wait "$barrier_name" 5
        echo "agent_2:after_barrier:$(date +%s%N)" >> "$results_file"
    ) &
    local pid2=$!
    
    # Simulate agent 3 reaching barrier
    (
        sleep 0.2  # More delay
        _MAINFRAME_AGENT_NAME="sync_agent_3"
        echo "agent_3:before_barrier:$(date +%s%N)" >> "$results_file"
        agent_barrier_wait "$barrier_name" 5
        echo "agent_3:after_barrier:$(date +%s%N)" >> "$results_file"
    ) &
    local pid3=$!
    
    # Wait for all agents
    wait $pid1 $pid2 $pid3
    
    # Verify all agents passed the barrier
    local after_count
    after_count=$(grep -c "after_barrier" "$results_file" || true)
    [ "$after_count" -eq 3 ]
    
    # Cleanup
    agent_unregister "sync_agent_1"
    agent_unregister "sync_agent_2"
    agent_unregister "sync_agent_3"
}

@test "signal-based coordination between agents" {
    # Register producer and consumer
    agent_register "producer" "data_generation"
    agent_register "consumer" "data_consumption"
    
    local signal_name="data_ready"
    local shared_state="$TEST_BASE/shared_state"
    
    # Consumer waits for signal (in background)
    (
        # Wait for data ready signal
        agent_wait "$signal_name" 10
        # Read and process data
        if [[ -f "$shared_state" ]]; then
            echo "processed:$(cat "$shared_state")" >> "$TEST_BASE/consumer_log"
        fi
    ) &
    local consumer_pid=$!
    
    # Producer generates data
    sleep 0.2
    echo "important_data_123" > "$shared_state"
    
    # Signal consumer
    agent_signal "$signal_name"
    
    # Wait for consumer
    wait $consumer_pid
    
    # Verify consumer processed the data
    [ -f "$TEST_BASE/consumer_log" ]
    grep -q "processed:important_data_123" "$TEST_BASE/consumer_log"
    
    # Cleanup
    agent_unregister "producer"
    agent_unregister "consumer"
}

@test "agent discovery by capability" {
    # Register agents with different capabilities
    agent_register "db_worker" "database" "sql" "backup"
    agent_register "api_worker" "rest_api" "graphql" "http"
    agent_register "ml_worker" "machine_learning" "python" "tensorflow"
    agent_register "general_worker" "database" "http"  # Multiple capabilities
    
    # Discover agents by capability
    local db_agents
    db_agents=$(agent_discover "database")
    [[ "$db_agents" == *"db_worker"* ]]
    [[ "$db_agents" == *"general_worker"* ]]
    
    local ml_agents
    ml_agents=$(agent_discover "machine_learning")
    [[ "$ml_agents" == *"ml_worker"* ]]
    
    local http_agents
    http_agents=$(agent_discover "http")
    [[ "$http_agents" == *"api_worker"* ]]
    [[ "$http_agents" == *"general_worker"* ]]
    
    # Cleanup
    agent_unregister "db_worker"
    agent_unregister "api_worker"
    agent_unregister "ml_worker"
    agent_unregister "general_worker"
}

@test "broadcast messaging to all agents" {
    # Register multiple agents
    agent_register "listener_1" "messaging"
    agent_register "listener_2" "messaging"
    agent_register "listener_3" "messaging"
    
    # Send broadcast message
    local broadcast_msg='{"type": "system_alert", "severity": "high", "message": "Maintenance in 5 minutes"}'
    agent_broadcast "$broadcast_msg" "alert"
    
    # Current contract matches the unit suite: broadcasts go to all other agents,
    # not to the sender. The last registered agent is the active sender here.
    local inbox_count_1 inbox_count_2 inbox_count_3

    # Switch to each agent and check inbox
    _MAINFRAME_AGENT_NAME="listener_1"
    inbox_count_1=$(agent_inbox_count)
    [ "$inbox_count_1" -ge 1 ]
    
    _MAINFRAME_AGENT_NAME="listener_2"
    inbox_count_2=$(agent_inbox_count)
    [ "$inbox_count_2" -ge 1 ]

    _MAINFRAME_AGENT_NAME="listener_3"
    inbox_count_3=$(agent_inbox_count)
    [ "$inbox_count_3" -eq 0 ]
    
    # Verify message content
    _MAINFRAME_AGENT_NAME="listener_1"
    local msg
    msg=$(agent_receive 5)
    [[ "$msg" == *"system_alert"* ]]
    [[ "$msg" == *"Maintenance"* ]]
    
    # Cleanup
    agent_unregister "listener_1"
    agent_unregister "listener_2"
    agent_unregister "listener_3"
}

@test "point-to-point agent messaging" {
    # Register sender and receiver
    agent_register "sender_agent" "coordination"
    agent_register "receiver_agent" "coordination"
    
    # Send direct message
    local direct_msg='{"task": "process_data", "params": {"file": "data.csv"}}'
    agent_send "receiver_agent" "$direct_msg" "task_assignment"
    
    # Switch to receiver context
    _MAINFRAME_AGENT_NAME="receiver_agent"
    
    # Receive message
    local received_msg
    received_msg=$(agent_receive 5)
    
    [ -n "$received_msg" ]
    [[ "$received_msg" == *"process_data"* ]]
    [[ "$received_msg" == *"data.csv"* ]]
    
    # Send response back
    local response='{"status": "accepted", "eta": "5m"}'
    agent_send "sender_agent" "$response" "task_response"
    
    # Switch to sender and verify response
    _MAINFRAME_AGENT_NAME="sender_agent"
    local response_msg
    response_msg=$(agent_receive 5)
    
    [ -n "$response_msg" ]
    [[ "$response_msg" == *"accepted"* ]]
    
    # Cleanup
    agent_unregister "sender_agent"
    agent_unregister "receiver_agent"
}

@test "complex workflow: map-reduce with agents" {
    # Setup: Coordinator and multiple mapper/reducer agents
    agent_register "coordinator" "orchestration"
    agent_register "mapper_1" "map" "compute"
    agent_register "mapper_2" "map" "compute"
    agent_register "reducer" "reduce" "compute"
    
    # Create AWM session for job tracking
    local job_id
    job_id=$(awm_init "map_reduce_job")
    awm_set "$job_id" "status" "mapping"
    awm_set "$job_id" "chunks" "4"
    
    # Create work queue for map tasks
    local map_queue="map_tasks"
    agent_work_queue "$map_queue"
    
    # Add map tasks
    for i in {1..4}; do
        agent_work_push "$map_queue" "chunk_$i"
    done
    
    # Mappers process chunks
    local map_results=()
    for mapper in mapper_1 mapper_2; do
        # Each mapper takes 2 chunks
        local chunk1_env chunk2_env chunk1 chunk2
        chunk1_env=$(agent_work_pop "$map_queue")
        chunk2_env=$(agent_work_pop "$map_queue")
        
        if [[ -n "$chunk1_env" ]]; then
            chunk1=$(json_get "$chunk1_env" "item")
            map_results+=("${mapper}_result_${chunk1}")
        fi
        if [[ -n "$chunk2_env" ]]; then
            chunk2=$(json_get "$chunk2_env" "item")
            map_results+=("${mapper}_result_${chunk2}")
        fi
    done
    
    # Store map results
    awm_set "$job_id" "map_results" "$(printf '%s,' "${map_results[@]}")"
    awm_set "$job_id" "status" "reducing"
    
    # Reducer processes all map results
    local reduce_output="final_result"
    for result in "${map_results[@]}"; do
        reduce_output="${reduce_output}_${result}"
    done
    
    awm_set "$job_id" "reduce_output" "$reduce_output"
    awm_set "$job_id" "status" "completed"
    
    # Verify results
    local final_status
    final_status=$(awm_get "$job_id" "status")
    [ "$final_status" = "completed" ]
    
    local final_output
    final_output=$(awm_get "$job_id" "reduce_output")
    [[ "$final_output" == *"mapper_1_result_chunk_1"* ]]
    [[ "$final_output" == *"mapper_2_result_chunk_4"* ]]
    
    # Cleanup
    awm_destroy "$job_id"
    agent_work_clear "$map_queue"
    agent_unregister "coordinator"
    agent_unregister "mapper_1"
    agent_unregister "mapper_2"
    agent_unregister "reducer"
}

@test "agent heartbeat and health monitoring" {
    # Register agents
    agent_register "healthy_agent" "compute"
    agent_register "stale_agent" "compute"
    
    # Send heartbeats
    agent_heartbeat
    
    # Switch to stale_agent and don't send heartbeat
    _MAINFRAME_AGENT_NAME="stale_agent"
    # (No heartbeat sent)
    
    # Switch back to healthy_agent and send heartbeat
    _MAINFRAME_AGENT_NAME="healthy_agent"
    agent_heartbeat
    
    # List agents and verify both exist
    local agent_list
    agent_list=$(agent_list)
    [[ "$agent_list" == *"healthy_agent"* ]]
    [[ "$agent_list" == *"stale_agent"* ]]
    
    # Get agent status
    local healthy_status stale_status
    healthy_status=$(agent_status "healthy_agent")
    stale_status=$(agent_status "stale_agent")
    
    [ -n "$healthy_status" ]
    [ -n "$stale_status" ]
    
    # Cleanup
    agent_unregister "healthy_agent"
    agent_unregister "stale_agent"
}

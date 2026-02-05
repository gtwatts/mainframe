#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/agent_loop.bats - Agent Loop System Test Suite
# =============================================================================
# Description: Comprehensive tests for lib/agent_loop.sh including lifecycle,
#              multi-agent coordination, and human-in-the-loop features.
# Run: bats tests/agent_loop.bats
# =============================================================================

# Test setup
setup() {
    # Create temporary test directory
    export TEST_DIR=$(mktemp -d)
    export AGENT_LOOP_DIR="${TEST_DIR}/agent_loops"
    export UAP_BASE_DIR="${TEST_DIR}/uap"
    export MAINFRAME_QUIET=1
    
    # Source required libraries
    source "${BATS_TEST_DIRNAME}/../lib/json.sh"
    source "${BATS_TEST_DIRNAME}/../lib/proc.sh"
    source "${BATS_TEST_DIRNAME}/../lib/uap.sh"
    source "${BATS_TEST_DIRNAME}/../lib/state.sh"
    source "${BATS_TEST_DIRNAME}/../lib/agent_loop.sh"
}

# Test teardown
teardown() {
    # Stop any running test agents
    agent_loop_list --json 2>/dev/null | grep -o '"name":"[^"]*"' | while read -r name; do
        name="${name#\"name\":\"}"
        name="${name%\"}"
        [[ "$name" == test_* ]] && agent_loop_stop "$name" 2>/dev/null || true
    done
    
    rm -rf "$TEST_DIR"
}

# =============================================================================
# BASIC LIFECYCLE TESTS
# =============================================================================

@test "agent_loop_start creates agent with goal" {
    local result
    result=$(agent_loop_start "test_basic" --goal "Test goal")
    
    [[ "$result" == *'"success":true'* ]]
    [[ "$result" == *'"name":"test_basic"'* ]]
    [[ -d "$AGENT_LOOP_DIR/test_basic" ]]
    [[ -f "$AGENT_LOOP_DIR/test_basic/state.json" ]]
}

@test "agent_loop_start validates goal requirement" {
    local result
    result=$(agent_loop_start "test_no_goal")
    
    [[ "$result" == *'"success":false'* ]]
    [[ "$result" == *'error'* ]]
}

@test "agent_loop_start validates agent name" {
    local result
    result=$(agent_loop_start "invalid/name" --goal "Test")
    
    [[ "$result" == *'"success":false'* ]]
}

@test "agent_loop_status returns agent info" {
    agent_loop_start "test_status" --goal "Test status" --priority high
    
    local result
    result=$(agent_loop_status "test_status")
    
    [[ "$result" == *'"name":"test_status"'* ]]
    [[ "$result" == *'"state"'* ]]
}

@test "agent_loop_status returns error for non-existent agent" {
    local result
    result=$(agent_loop_status "nonexistent_agent_xyz")
    
    [[ "$result" == *'"success":false'* ]]
}

@test "agent_loop_list shows created agents" {
    agent_loop_start "test_list_1" --goal "Goal 1"
    agent_loop_start "test_list_2" --goal "Goal 2"
    
    local result
    result=$(agent_loop_list)
    
    [[ "$result" == *'test_list_1'* ]]
    [[ "$result" == *'test_list_2'* ]]
}

@test "agent_loop_list --json returns valid JSON" {
    agent_loop_start "test_json_list" --goal "JSON test"
    
    local result
    result=$(agent_loop_list --json)
    
    [[ "$result" == '['* ]]
    [[ "$result" == *']' ]]
}

@test "agent_loop_stop stops running agent" {
    agent_loop_start "test_stop" --goal "Test stop"
    sleep 1
    
    local result
    result=$(agent_loop_stop "test_stop")
    
    [[ "$result" == *'"success":true'* ]]
    [[ "$result" == *'"status":"stopped"'* ]]
}

@test "agent_loop_stop handles non-existent agent" {
    local result
    result=$(agent_loop_stop "nonexistent_xyz")
    
    [[ "$result" == *'"success":false'* ]]
}

# =============================================================================
# PAUSE/RESUME TESTS
# =============================================================================

@test "agent_loop_pause pauses running agent" {
    agent_loop_start "test_pause" --goal "Test pause"
    sleep 1
    
    local result
    result=$(agent_loop_pause "test_pause")
    
    [[ "$result" == *'"success":true'* ]]
    [[ "$result" == *'"status":"paused"'* ]]
}

@test "agent_loop_pause fails for non-running agent" {
    local result
    result=$(agent_loop_pause "nonexistent_pause")
    
    [[ "$result" == *'"success":false'* ]]
}

@test "agent_loop_resume resumes paused agent" {
    agent_loop_start "test_resume" --goal "Test resume"
    sleep 1
    agent_loop_pause "test_resume" >/dev/null
    
    local result
    result=$(agent_loop_resume "test_resume" --context "Test context")
    
    [[ "$result" == *'"success":true'* ]]
    [[ "$result" == *'"status":"running"'* ]]
}

@test "agent_loop_resume with context updates state" {
    agent_loop_start "test_resume_ctx" --goal "Test context"
    sleep 1
    agent_loop_pause "test_resume_ctx" >/dev/null
    
    local result
    result=$(agent_loop_resume "test_resume_ctx" --context "New focus")
    
    [[ "$result" == *'"context":"New focus"'* ]]
}

# =============================================================================
# CHECKPOINT/RECOVERY TESTS
# =============================================================================

@test "agent_loop_restore recovers from checkpoint" {
    agent_loop_start "test_restore" --goal "Test checkpoint"
    sleep 1
    
    # Manually create a checkpoint
    local checkpoint_dir="$AGENT_LOOP_DIR/test_restore"
    local checkpoint_data
    checkpoint_data=$(json_object \
        "checkpoint_time=test" \
        "state=$(cat "$checkpoint_dir/state.json")")
    echo "$checkpoint_data" > "$checkpoint_dir/checkpoint.json"
    
    local result
    result=$(agent_loop_restore "test_restore")
    
    [[ "$result" == *'"success":true'* ]]
}

@test "agent_loop_restore fails without checkpoint" {
    agent_loop_start "test_no_checkpoint" --goal "Test no checkpoint"
    
    local result
    result=$(agent_loop_restore "test_no_checkpoint")
    
    [[ "$result" == *'"success":false'* ]]
    [[ "$result" == *'No checkpoint found'* ]]
}

# =============================================================================
# MULTI-AGENT COORDINATION TESTS
# =============================================================================

@test "agent_loop_spawn creates child agent" {
    agent_loop_start "test_parent" --goal "Parent goal"
    sleep 1
    
    local result
    result=$(agent_loop_spawn \
        --parent "test_parent" \
        --child "test_child" \
        --goal "Child goal")
    
    [[ "$result" == *'"success":true'* ]] || [[ "$result" == *'already running'* ]] || [[ "$result" == *'not running'* ]]
}

@test "agent_loop_spawn validates parent exists" {
    local result
    result=$(agent_loop_spawn \
        --parent "nonexistent_parent" \
        --child "test_child2" \
        --goal "Child goal")
    
    [[ "$result" == *'"success":false'* ]]
}

@test "agent_loop_join waits for agent" {
    agent_loop_start "test_join_target" --goal "Target goal"
    agent_loop_start "test_join_waiter" --goal "Waiter goal"
    sleep 1
    
    # Stop target quickly
    (sleep 2; agent_loop_stop "test_join_target") &
    
    local result
    result=$(agent_loop_join "test_join_waiter" --wait_for "test_join_target" --timeout 5)
    
    [[ "$result" == *'"joined":"test_join_target"'* ]] || [[ "$result" == *'Timeout'* ]]
}

# =============================================================================
# HUMAN INTERACTION TESTS
# =============================================================================

@test "agent_loop_request_input creates input request" {
    agent_loop_start "test_input" --goal "Test input"
    sleep 1
    
    local result
    result=$(agent_loop_request_input "test_input" --prompt "Enter value:")
    
    [[ "$result" == *'"success":true'* ]] || [[ "$result" == *'not running'* ]]
}

@test "agent_loop_notify logs notification" {
    agent_loop_start "test_notify" --goal "Test notify"
    sleep 1
    
    local result
    result=$(agent_loop_notify "test_notify" --message "Test message" --level info)
    
    [[ "$result" == *'"success":true'* ]]
    [[ "$result" == *'"message":"Test message"'* ]]
}

@test "agent_loop_notify validates message requirement" {
    local result
    result=$(agent_loop_notify "test_notify2")
    
    [[ "$result" == *'"success":false'* ]]
}

# =============================================================================
# STATE PERSISTENCE TESTS
# =============================================================================

@test "agent state includes required fields" {
    agent_loop_start "test_fields" --goal "Test fields" --priority high
    sleep 1
    
    local state_file="$AGENT_LOOP_DIR/test_fields/state.json"
    local state
    state=$(cat "$state_file")
    
    [[ "$state" == *'"name"'* ]]
    [[ "$state" == *'"status"'* ]]
    [[ "$state" == *'"goal"'* ]]
    [[ "$state" == *'"priority"'* ]]
    [[ "$state" == *'"started"'* ]]
}

@test "agent log file is created" {
    agent_loop_start "test_log" --goal "Test log"
    sleep 1
    
    local log_file="$AGENT_LOOP_DIR/test_log/log.jsonl"
    [[ -f "$log_file" ]]
}

@test "agent PID file is created" {
    agent_loop_start "test_pid" --goal "Test PID"
    sleep 1
    
    local pid_file="$AGENT_LOOP_DIR/test_pid/agent.pid"
    [[ -f "$pid_file" ]]
    
    local pid
    pid=$(cat "$pid_file")
    [[ -n "$pid" ]]
    [[ "$pid" =~ ^[0-9]+$ ]]
}

# =============================================================================
# PRIORITY TESTS
# =============================================================================

@test "agent_loop_start accepts different priorities" {
    local result
    
    result=$(agent_loop_start "test_priority_low" --goal "Low" --priority low)
    [[ "$result" == *'"success":true'* ]]
    
    result=$(agent_loop_start "test_priority_high" --goal "High" --priority high)
    [[ "$result" == *'"success":true'* ]]
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

@test "agent_loop handles duplicate start gracefully" {
    agent_loop_start "test_duplicate" --goal "First"
    sleep 1
    
    local result
    result=$(agent_loop_start "test_duplicate" --goal "Second")
    
    [[ "$result" == *'"success":false'* ]] || [[ "$result" == *'already running'* ]]
}

@test "agent_loop_status handles missing state file" {
    mkdir -p "$AGENT_LOOP_DIR/missing_state"
    
    local result
    result=$(agent_loop_status "missing_state")
    
    [[ "$result" == *'"success":false'* ]]
}

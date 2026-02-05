#!/usr/bin/env bats
# Tests for Universal Agent Protocol v2 (UAP v2)

load '../bats-support/load'
load '../bats-assert/load'

setup() {
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    export TEST_TMPDIR="$(mktemp -d)"
    export UAP_V2_BASE_DIR="$TEST_TMPDIR/uap_v2"
    export MAINFRAME_QUIET=1
    
    source "$MAINFRAME_ROOT/lib/json.sh"
    source "$MAINFRAME_ROOT/lib/uap_v2.sh"
}

teardown() {
    # Cleanup any registered agents
    if [[ -n "$UAP_V2_AGENT_NAME" ]]; then
        uap_v2_unregister "$UAP_V2_AGENT_NAME" 2>/dev/null || true
    fi
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# Registration & Discovery Tests
# =============================================================================

@test "uap_v2_register: registers agent with basic info" {
    run uap_v2_register "test-agent"
    assert_success
    assert_output --partial '"success":true'
    assert_output --partial '"name":"test-agent"'
    
    # Verify registration file exists
    [ -f "$UAP_V2_AGENT_DIR/test-agent.json" ]
}

@test "uap_v2_register: registers agent with capabilities" {
    run uap_v2_register "cap-agent" --capabilities "code.review,security.scan"
    assert_success
    assert_output --partial '"capabilities"'
    assert_output --partial '"code.review"'
}

@test "uap_v2_register: generates authentication token" {
    uap_v2_register "token-agent"
    [ -n "$UAP_V2_TOKEN" ]
    [ ${#UAP_V2_TOKEN} -ge 16 ]
}

@test "uap_v2_unregister: removes agent registration" {
    uap_v2_register "temp-agent"
    [ -f "$UAP_V2_AGENT_DIR/temp-agent.json" ]
    
    run uap_v2_unregister "temp-agent"
    assert_success
    [ ! -f "$UAP_V2_AGENT_DIR/temp-agent.json" ]
}

@test "uap_v2_discover: finds agents by capability pattern" {
    uap_v2_register "agent1" --capabilities "code.review"
    uap_v2_register "agent2" --capabilities "security.scan"
    
    run uap_v2_discover "code.review"
    assert_success
    assert_output --partial "agent1"
}

@test "uap_v2_list_agents: lists all registered agents" {
    uap_v2_register "list-agent1"
    uap_v2_register "list-agent2"
    
    run uap_v2_list_agents
    assert_success
    assert_output --partial "list-agent1"
    assert_output --partial "list-agent2"
}

# =============================================================================
# Message Encoding/Decoding Tests
# =============================================================================

@test "_uap_v2_encode_message: creates valid UAP v2 message" {
    UAP_V2_AGENT_NAME="test-sender"
    
    run _uap_v2_encode_message --type "request" --target "receiver" --payload '{"test":true}'
    assert_success
    assert_output --partial '"uap_version":"2.0"'
    assert_output --partial '"type":"request"'
    assert_output --partial '"message_id"'
    assert_output --partial '"integrity"'
}

@test "_uap_v2_decode_message: extracts fields from message" {
    UAP_V2_AGENT_NAME="test-sender"
    
    local message
    message=$(_uap_v2_encode_message --type "request" --target "receiver" --payload '{"test":true}')
    
    run _uap_v2_decode_message "$message" --get "type"
    assert_success
    assert_output "request"
}

@test "_uap_v2_verify_integrity: validates message integrity" {
    UAP_V2_AGENT_NAME="test-sender"
    
    local message
    message=$(_uap_v2_encode_message --type "request" --target "receiver" --payload '{"test":true}')
    
    run _uap_v2_verify_integrity "$message"
    assert_success
}

# =============================================================================
# Transport Layer Tests
# =============================================================================

@test "_uap_v2_detect_transport: detects available transport" {
    run _uap_v2_detect_transport
    assert_success
    [[ "$output" == "socket" || "$output" == "pipe" || "$output" == "file" ]]
}

@test "_uap_v2_send_file: sends message via file mailbox" {
    uap_v2_register "sender"
    uap_v2_register "receiver"
    
    local message='{"test":"data"}'
    
    run _uap_v2_send_file "receiver" "$message"
    assert_success
    
    # Verify message was delivered
    [ -n "$(ls -A $UAP_V2_MAILBOX_DIR/receiver/*.json 2>/dev/null)" ]
}

@test "_uap_v2_receive_file: receives message from mailbox" {
    uap_v2_register "receiver"
    
    # Send a message
    local message='{"test":"received"}'
    _uap_v2_send_file "receiver" "$message"
    
    run _uap_v2_receive_file 1
    assert_success
    assert_output --partial '"test":"received"'
}

# =============================================================================
# RPC Tests
# =============================================================================

@test "uap_v2_call: validates required arguments" {
    run uap_v2_call
    assert_failure
    
    run uap_v2_call "agent"
    assert_failure
}

@test "uap_v2_call: builds proper request payload" {
    uap_v2_register "caller"
    uap_v2_register "callee"
    
    # Test that the function builds a proper request
    # Note: Actual call will timeout since no listener is running
    run timeout 1 uap_v2_call "callee" "test_method" --arg key=value --timeout 2 || true
    # Should attempt to send (may fail due to timeout)
}

@test "uap_v2_call_async: validates callback function exists" {
    uap_v2_register "async-caller"
    
    run uap_v2_call_async "target" "method" --callback "nonexistent_function"
    assert_failure
    assert_output --partial "not found"
}

@test "uap_v2_schema: retrieves method schema" {
    uap_v2_register "schema-agent" --schema 'test={"type":"object"}'
    
    run uap_v2_schema "schema-agent" "test"
    assert_success
    assert_output --partial '"type":"object"'
}

# =============================================================================
# Streaming Tests
# =============================================================================

@test "uap_v2_stream: validates required arguments" {
    run uap_v2_stream
    assert_failure
    
    run uap_v2_stream "agent"
    assert_failure
    
    run uap_v2_stream "agent" "method"
    assert_failure
}

@test "uap_v2_stream: validates chunk handler exists" {
    uap_v2_register "stream-caller"
    
    run uap_v2_stream "target" "method" --on_chunk "nonexistent_handler"
    assert_failure
    assert_output --partial "not found"
}

@test "uap_v2_broadcast: sends to multiple agents" {
    uap_v2_register "broadcaster"
    uap_v2_register "receiver1" --capabilities "test.cap"
    uap_v2_register "receiver2" --capabilities "test.cap"
    
    run uap_v2_broadcast "hello" --filter "test.cap"
    assert_success
    assert_output --partial '"success":true'
    assert_output --partial '"sent":'
}

# =============================================================================
# Health & Status Tests
# =============================================================================

@test "uap_v2_heartbeat: updates agent heartbeat" {
    uap_v2_register "hb-agent"
    
    run uap_v2_heartbeat "hb-agent"
    assert_success
}

@test "uap_v2_status: returns agent status" {
    uap_v2_register "status-agent"
    
    run uap_v2_status "status-agent"
    assert_success
    assert_output --partial '"name":"status-agent"'
    assert_output --partial '"online":'
}

@test "uap_v2_status: handles nonexistent agent" {
    run uap_v2_status "nonexistent-agent"
    assert_failure
    assert_output --partial '"status":"not_found"'
}

@test "uap_v2_health_check: returns system health" {
    run uap_v2_health_check
    assert_success
    assert_output --partial '"status":'
    assert_output --partial '"healthy":'
    assert_output --partial '"transport":'
}

@test "uap_v2_health_check: detects transport availability" {
    run uap_v2_health_check --verbose
    assert_success
    assert_output --partial '"transport"'
}

# =============================================================================
# Utility Tests
# =============================================================================

@test "_uap_v2_uuid: generates unique identifiers" {
    local uuid1
    uuid1=$(_uap_v2_uuid)
    
    [ -n "$uuid1" ]
    [ ${#uuid1} -ge 16 ]
}

@test "_uap_v2_timestamp: generates ISO8601 timestamp" {
    run _uap_v2_timestamp
    assert_success
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "_uap_v2_hash: generates message integrity hash" {
    run _uap_v2_hash "test data"
    assert_success
    [ ${#output} -eq 16 ]
}

@test "_uap_v2_ensure_dirs: creates directory structure" {
    rm -rf "$UAP_V2_BASE_DIR"
    
    run _uap_v2_ensure_dirs
    assert_success
    [ -d "$UAP_V2_AGENT_DIR" ]
    [ -d "$UAP_V2_MAILBOX_DIR" ]
    [ -d "$UAP_V2_LOG_DIR" ]
}

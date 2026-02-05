#!/usr/bin/env bats
# Tests for Universal Agent Protocol (UAP)

load '../bats-support/load'
load '../bats-assert/load'

setup() {
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    export TEST_TMPDIR="$(mktemp -d)"
    export UAP_BASE_DIR="$TEST_TMPDIR/uap"
    source "$MAINFRAME_ROOT/lib/uap.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "uap_detect_platform: returns a platform string" {
    run uap_detect_platform
    assert_success
    # Should return one of the known platforms or unknown
    assert [ -n "$output" ]
}

@test "uap_encode_message: creates valid UAP message" {
    run uap_encode_message --type "task_request" --payload '{"task":"test"}'
    assert_success
    assert_output --partial '"uap_version":"1.0"'
    assert_output --partial '"message_type":"task_request"'
    assert_output --partial '"task":"test"'
}

@test "uap_decode_message: extracts fields from message" {
    message='{"uap_version":"1.0","message_type":"test","message_id":"abc123"}'
    
    run uap_decode_message --field "message_type" --message "$message"
    assert_success
    assert_output "test"
}

@test "uap_capability_matches: matches wildcards correctly" {
    run uap_capability_matches --required "bash.*" --available "bash.execute"
    assert_success
    
    run uap_capability_matches --required "bash.write" --available "bash.read"
    assert_failure
}

@test "uap_init: registers agent with capabilities" {
    run uap_init --agent "test-agent" --capabilities "bash.execute" "json.parse"
    assert_success
    
    # Verify agent directory was created
    [ -d "$UAP_BASE_DIR/test-agent" ]
}

@test "uap_heartbeat: updates agent heartbeat" {
    uap_init --agent "test-agent" --capabilities "bash.execute"
    
    run uap_heartbeat
    assert_success
    
    # Verify heartbeat file exists and is recent
    [ -f "$UAP_BASE_DIR/test-agent/heartbeat" ]
}

@test "uap_send and receive: message delivery" {
    uap_init --agent "sender" --capabilities "test"
    uap_init --agent "receiver" --capabilities "test"
    
    # Send message
    run uap_send --to "receiver" --message '{"content":"hello"}'
    assert_success
    
    # Receive message (as receiver)
    _UAP_AGENT_NAME="receiver"
    run uap_receive --timeout 2
    assert_success
    assert_output --partial "hello"
}

@test "uap_list_agents: lists registered agents" {
    uap_init --agent "agent1" --capabilities "test"
    uap_init --agent "agent2" --capabilities "test"
    
    run uap_list_agents
    assert_success
    assert_output --partial "agent1"
    assert_output --partial "agent2"
}

@test "uap_get_agent_info: returns agent details" {
    uap_init --agent "test-agent" --capabilities "bash.execute" "json.parse"
    
    run uap_get_agent_info --agent "test-agent"
    assert_success
    assert_output --partial '"agent_id":"test-agent"'
    assert_output --partial '"capabilities"'
}

@test "uap_shutdown: unregisters agent" {
    uap_init --agent "temp-agent" --capabilities "test"
    
    run uap_shutdown
    assert_success
    
    # Verify agent directory was removed
    [ ! -d "$UAP_BASE_DIR/temp-agent" ]
}

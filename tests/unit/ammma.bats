#!/usr/bin/env bats
# Tests for AMMA V3 (Advanced Multi-tier Memory Architecture)

load '../bats-support/load'
load '../bats-assert/load'

setup() {
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    export TEST_TMPDIR="$(mktemp -d)"
    export AWM_ROOT="$TEST_TMPDIR/awm"
    source "$MAINFRAME_ROOT/lib/ammma.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "ammma_init: creates session successfully" {
    run ammma_init --session "test-session" --agent "test-agent"
    assert_success
    assert_output --regexp '^[a-f0-9]{12}$'
}

@test "ammma_init: inherits from parent session" {
    parent_id=$(ammma_init --session "parent")
    _AWM_SESSION_ID="$parent_id"
    ammma_checkpoint_set --key "parent_key" --value "parent_value"
    
    child_id=$(ammma_init --session "child" --parent "$parent_id")
    assert [ -n "$child_id" ]
    assert [ "$child_id" != "$parent_id" ]
}

@test "ammma_checkpoint_set and get: stores and retrieves values" {
    session_id=$(ammma_init --session "test")
    _AWM_SESSION_ID="$session_id"
    
    run ammma_checkpoint_set --key "mykey" --value "myvalue"
    assert_success
    
    run ammma_checkpoint_get --key "mykey"
    assert_success
    assert_output "myvalue"
}

@test "ammma_episode_log: logs episode with importance" {
    session_id=$(ammma_init --session "test")
    _AWM_SESSION_ID="$session_id"
    
    run ammma_episode_log --content "Test discovery" --importance high
    assert_success
    
    # Verify episode was logged
    run ammma_stats
    assert_success
    assert_output --partial '"episodes":1'
}

@test "ammma_fact_store: stores declarative fact" {
    session_id=$(ammma_init --session "test")
    _AWM_SESSION_ID="$session_id"
    
    run ammma_fact_store --subject "Python" --predicate "supports" --object "async/await"
    assert_success
    
    run ammma_fact_query --subject "Python"
    assert_success
    assert_output --partial 'async/await'
}

@test "ammma_pattern_learn: learns procedural pattern" {
    session_id=$(ammma_init --session "test")
    _AWM_SESSION_ID="$session_id"
    
    run ammma_pattern_learn --name "error-handling" --trigger "error" --action "Check logs"
    assert_success
    
    run ammma_stats
    assert_success
    assert_output --partial '"patterns":1'
}

@test "ammma_retrieve: retrieves relevant memories" {
    session_id=$(ammma_init --session "test")
    _AWM_SESSION_ID="$session_id"
    
    ammma_episode_log --content "Database uses PostgreSQL" --importance high
    ammma_episode_log --content "API rate limit is 100/min" --importance normal
    
    run ammma_retrieve --query "database" --limit 5
    assert_success
    assert_output --partial "PostgreSQL"
}

@test "ammma_context_build: builds context within token budget" {
    session_id=$(ammma_init --session "test")
    _AWM_SESSION_ID="$session_id"
    
    ammma_episode_log --content "Important discovery about the system"
    ammma_checkpoint_set --key "status" --value "active"
    
    run ammma_context_build --max-tokens 1000
    assert_success
    assert_output --partial "discovery"
}

@test "ammma_close: closes session successfully" {
    session_id=$(ammma_init --session "test")
    _AWM_SESSION_ID="$session_id"
    
    run ammma_close
    assert_success
}

@test "ammma_stats: returns session statistics" {
    session_id=$(ammma_init --session "test")
    _AWM_SESSION_ID="$session_id"
    
    run ammma_stats
    assert_success
    assert_output --partial '"session_id"'
    assert_output --partial '"tier_distribution"'
}

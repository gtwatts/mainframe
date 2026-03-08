#!/usr/bin/env bats
# Tests for AMMA V3 (Advanced Multi-tier Memory Architecture)

load '../bats-support/load'
load '../bats-assert/load'

setup() {
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    export TEST_TMPDIR="$(mktemp -d)"
    export AMMA_ROOT="$TEST_TMPDIR/amma"
    export MAINFRAME_QUIET=1
    source "$MAINFRAME_ROOT/lib/ammma.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "ammma_init: creates session successfully" {
    run ammma_init --session "test-session" --agent "test-agent"
    assert_success
    assert_output --partial '"session_id":"test-session"'
    assert_output --partial '"initialized":true'
}

@test "ammma_init: inherits from parent session" {
    ammma_init --session "parent" >/dev/null
    ammma_checkpoint_set --key "parent_key" --value "parent_value"

    ammma_init --session "child" --parent "parent" >/dev/null
    run ammma_checkpoint_get --key "parent_key"
    assert_success
    assert_output --partial "parent_value"
}

@test "ammma_checkpoint_set and get: stores and retrieves values" {
    ammma_init --session "test" >/dev/null
    
    run ammma_checkpoint_set --key "mykey" --value "myvalue"
    assert_success
    
    run ammma_checkpoint_get --key "mykey"
    assert_success
    assert_output --partial '"key":"mykey"'
    assert_output --partial '"value":"myvalue"'
    assert_output --partial '"tier":"L2"'
}

@test "ammma_episode_log: logs episode with importance" {
    ammma_init --session "test" >/dev/null
    
    run ammma_episode_log --content "Test discovery" --importance high
    assert_success
    
    # Verify episode was logged
    run ammma_stats
    assert_success
    assert_output --partial '"episodes":1'
}

@test "ammma_fact_store: stores declarative fact" {
    ammma_init --session "test" >/dev/null
    
    run ammma_fact_store --subject "Python" --predicate "supports" --object "async/await"
    assert_success
    
    run ammma_fact_query --subject "Python"
    assert_success
    assert_output --partial 'async/await'
}

@test "ammma_pattern_learn: learns procedural pattern" {
    ammma_init --session "test" >/dev/null
    
    run ammma_pattern_learn --name "error-handling" --trigger "error" --action "Check logs"
    assert_success
    
    run ammma_stats
    assert_success
    assert_output --partial '"patterns":1'
}

@test "ammma_retrieve: retrieves relevant memories" {
    ammma_init --session "test" >/dev/null
    
    ammma_episode_log --content "Database uses PostgreSQL" --importance high
    ammma_episode_log --content "API rate limit is 100/min" --importance normal
    
    run ammma_retrieve --query "database" --limit 5
    assert_success
    assert_output --partial "PostgreSQL"
}

@test "ammma_context_build: builds context within token budget" {
    ammma_init --session "test" >/dev/null
    
    ammma_episode_log --content "Important discovery about the system"
    ammma_checkpoint_set --key "status" --value "active"
    
    run ammma_context_build --max-tokens 1000
    assert_success
    assert_output --partial "discovery"
}

@test "ammma_close: closes session successfully" {
    ammma_init --session "test" >/dev/null
    
    run ammma_close
    assert_success
}

@test "ammma_stats: returns session statistics" {
    ammma_init --session "test" >/dev/null
    
    run ammma_stats
    assert_success
    assert_output --partial '"session_id"'
    assert_output --partial '"tier_distribution"'
}

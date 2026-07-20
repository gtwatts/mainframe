#!/usr/bin/env bats
# Tests for Fast Cache

load '../bats-support/load'
load '../bats-assert/load'

setup() {
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    source "$MAINFRAME_ROOT/lib/fast_cache.sh"
}

@test "fast_cache_init: initializes cache" {
    run fast_cache_init --size 100 --name "test_cache"
    assert_success
}

@test "fast_cache_has: checks key existence" {
    fast_cache_init --name "test"
    fast_cache_set --key "exists" --value "yes"
    
    run fast_cache_has --key "exists"
    assert_success
    
    run fast_cache_has --key "notexists"
    assert_failure
}

@test "fast_cache_clear: removes all entries" {
    fast_cache_init --name "test"
    fast_cache_set --key "key1" --value "val1"
    fast_cache_set --key "key2" --value "val2"
    
    fast_cache_clear --name "test"
    
    run fast_cache_has --key "key1"
    assert_failure
}

@test "fast_cache_stats: returns statistics" {
    fast_cache_init --name "test"
    fast_cache_set --key "key1" --value "val1"
    
    run fast_cache_stats --name "test"
    assert_success
    assert_output --partial "Cache: test"
    assert_output --partial "Hits:"
}

@test "fast_cache: respects size limit" {
    fast_cache_init --size 2 --name "small"
    
    fast_cache_set --key "key1" --value "val1"
    fast_cache_set --key "key2" --value "val2"
    fast_cache_set --key "key3" --value "val3"
    
    # Check stats - should show size limit
    run fast_cache_stats --name "small"
    assert_success
    assert_output --partial "2"
}

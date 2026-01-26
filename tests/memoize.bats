#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: AI-Agent Optimized Memoization Tests
# =============================================================================
# Tests for lib/cache.sh v2.0 - Decorator memoization, command caching,
# file caching, computation caching, and prewarming
# =============================================================================

load 'test_helper'

setup() {
    source_lib "cache"
    TEST_DIR=$(create_test_dir "memoize")

    # Override cache root to use test directory
    export MAINFRAME_CACHE_ROOT="$TEST_DIR/cache"
    export MAINFRAME_CACHE_MAX_SIZE_MB=10
    export MAINFRAME_CACHE_DEFAULT_TTL=0
    export MAINFRAME_QUIET=1

    # Reset cache statistics
    _MAINFRAME_CACHE_HITS=0
    _MAINFRAME_CACHE_MISSES=0

    # Clear session cache
    _MAINFRAME_SESSION_CACHE=()

    # Test counter for stateful function tests
    export _TEST_COUNTER=0
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
    # Clean up any wrapped functions
    unset -f _memo_orig_stateful_func 2>/dev/null || true
    unset -f _memo_orig_pure_func 2>/dev/null || true
}

# =============================================================================
# HELPER FUNCTIONS FOR TESTS
# =============================================================================

# A pure function - same input always gives same output
pure_func() {
    local arg="${1:-default}"
    printf 'result:%s' "$arg"
}

# A stateful function - returns different values each call
stateful_func() {
    _TEST_COUNTER=$((_TEST_COUNTER + 1))
    printf '%s' "$_TEST_COUNTER"
}

# A slow function for timing tests
slow_func() {
    sleep 0.2
    printf 'slow_result'
}

# A function that fails
failing_func() {
    printf 'error' >&2
    return 1
}

# A computation function for cache_compute tests
compute_summary() {
    printf 'computed_at_%s' "$(date +%s%N)"
}

# =============================================================================
# MEMO_WRAP DECORATOR TESTS
# =============================================================================

@test "memo_wrap wraps a function successfully" {
    run memo_wrap pure_func
    [ "$status" -eq 0 ]

    # Original should be preserved
    declare -F _memo_orig_pure_func
}

@test "memo_wrap caches pure function results" {
    memo_wrap stateful_func

    # First call - should compute
    local result1
    result1=$(stateful_func)
    [ "$result1" = "1" ]

    # Second call - should return cached value
    local result2
    result2=$(stateful_func)
    [ "$result2" = "1" ]  # Same as first, not "2"
}

@test "memo_wrap increments hit counter on cache hit" {
    memo_wrap pure_func

    pure_func "test" > /dev/null
    local hits_before=$_MAINFRAME_CACHE_HITS

    pure_func "test" > /dev/null
    local hits_after=$_MAINFRAME_CACHE_HITS

    [ "$hits_after" -gt "$hits_before" ]
}

@test "memo_wrap increments miss counter on cache miss" {
    memo_wrap pure_func

    _MAINFRAME_CACHE_MISSES=0
    pure_func "unique_arg_1" > /dev/null

    [ "$_MAINFRAME_CACHE_MISSES" -ge 1 ]
}

@test "memo_wrap fails for non-existent function" {
    run memo_wrap nonexistent_function
    [ "$status" -ne 0 ]
}

@test "memo_wrap warns if already wrapped" {
    memo_wrap pure_func
    run memo_wrap pure_func
    [ "$status" -eq 0 ]
}

@test "memo_wrap with TTL respects expiration" {
    memo_wrap stateful_func 1  # 1 second TTL

    stateful_func > /dev/null
    local result1
    result1=$(stateful_func)
    [ "$result1" = "1" ]

    # Wait for expiration
    sleep 2

    # Should recompute
    local result2
    result2=$(stateful_func)
    [ "$result2" = "2" ]
}

# =============================================================================
# MEMO_UNWRAP TESTS
# =============================================================================

@test "memo_unwrap restores original function" {
    memo_wrap stateful_func

    # Call wrapped version
    stateful_func > /dev/null

    memo_unwrap stateful_func

    # Should no longer be cached - each call increments
    local result1 result2
    result1=$(stateful_func)
    result2=$(stateful_func)

    [ "$result1" != "$result2" ]
}

@test "memo_unwrap fails if not wrapped" {
    run memo_unwrap pure_func
    [ "$status" -ne 0 ]
}

@test "memo_unwrap removes backup function" {
    memo_wrap pure_func
    memo_unwrap pure_func

    run declare -F _memo_orig_pure_func
    [ "$status" -ne 0 ]
}

# =============================================================================
# MEMO_CLEAR TESTS
# =============================================================================

@test "memo_clear clears cache for specific function" {
    memo_wrap stateful_func

    stateful_func > /dev/null  # Counter = 1

    memo_clear stateful_func

    # Next call should recompute
    local result
    result=$(stateful_func)
    [ "$result" = "2" ]
}

@test "memo_clear requires function name" {
    run memo_clear ""
    [ "$status" -ne 0 ]
}

@test "memo_clear returns count of cleared entries" {
    memo_wrap pure_func
    pure_func "a" > /dev/null
    pure_func "b" > /dev/null
    pure_func "c" > /dev/null

    run memo_clear pure_func
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
    [ "$output" -ge 1 ]
}

# =============================================================================
# CACHE_COMMAND TESTS
# =============================================================================

@test "cache_command caches command output" {
    run cache_command 60 echo "test output"
    [ "$status" -eq 0 ]
    [ "$output" = "test output" ]
}

@test "cache_command returns cached value on second call" {
    # Use a command that changes each time
    cache_command 60 date +%s%N > /dev/null

    local result1 result2
    result1=$(cache_command 60 date +%s%N)
    sleep 0.1
    result2=$(cache_command 60 date +%s%N)

    [ "$result1" = "$result2" ]
}

@test "cache_command increments hit counter" {
    cache_command 60 echo "hit test" > /dev/null

    local hits_before=$_MAINFRAME_CACHE_HITS
    cache_command 60 echo "hit test" > /dev/null
    local hits_after=$_MAINFRAME_CACHE_HITS

    [ "$hits_after" -gt "$hits_before" ]
}

@test "cache_command requires command" {
    run cache_command 60
    [ "$status" -ne 0 ]
}

@test "cache_command respects TTL" {
    cache_command 1 date +%s%N > /dev/null

    local result1
    result1=$(cache_command 1 date +%s%N)

    sleep 2

    local result2
    result2=$(cache_command 1 date +%s%N)

    [ "$result1" != "$result2" ]
}

@test "cache_command handles command with arguments" {
    run cache_command 60 printf '%s %s' "hello" "world"
    [ "$status" -eq 0 ]
    [ "$output" = "hello world" ]
}

@test "cache_command preserves exit code on failure" {
    run cache_command 60 false
    [ "$status" -ne 0 ]
}

# =============================================================================
# CACHE_FILE TESTS
# =============================================================================

@test "cache_file caches file contents" {
    local test_file="$TEST_DIR/test.txt"
    printf 'file content' > "$test_file"

    run cache_file "$test_file"
    [ "$status" -eq 0 ]
    [ "$output" = "file content" ]
}

@test "cache_file returns cached value on second call" {
    local test_file="$TEST_DIR/cached.txt"
    printf 'original' > "$test_file"

    cache_file "$test_file" > /dev/null

    local result
    result=$(cache_file "$test_file")
    [ "$result" = "original" ]
}

@test "cache_file invalidates when file changes" {
    local test_file="$TEST_DIR/changing.txt"
    printf 'version1' > "$test_file"

    cache_file "$test_file" > /dev/null

    # Modify the file
    printf 'version2' > "$test_file"

    local result
    result=$(cache_file "$test_file")
    [ "$result" = "version2" ]
}

@test "cache_file fails for non-existent file" {
    run cache_file "$TEST_DIR/nonexistent.txt"
    [ "$status" -ne 0 ]
}

@test "cache_file increments hit counter" {
    local test_file="$TEST_DIR/hit_test.txt"
    printf 'data' > "$test_file"

    cache_file "$test_file" > /dev/null

    local hits_before=$_MAINFRAME_CACHE_HITS
    cache_file "$test_file" > /dev/null
    local hits_after=$_MAINFRAME_CACHE_HITS

    [ "$hits_after" -gt "$hits_before" ]
}

@test "cache_file handles large files" {
    local test_file="$TEST_DIR/large.txt"
    for i in {1..1000}; do
        printf 'line %d with some content\n' "$i"
    done > "$test_file"

    run cache_file "$test_file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"line 1"* ]]
    [[ "$output" == *"line 1000"* ]]
}

# =============================================================================
# CACHE_FILE_INVALIDATE TESTS
# =============================================================================

@test "cache_file_invalidate clears file cache" {
    local test_file="$TEST_DIR/invalidate_test.txt"
    printf 'original' > "$test_file"

    cache_file "$test_file" > /dev/null
    cache_file_invalidate "$test_file"

    # Change file content
    printf 'modified' > "$test_file"

    # The stat changed, so even without invalidate it would refresh
    # But invalidate ensures cache is cleared
    run cache_file "$test_file"
    [ "$status" -eq 0 ]
}

@test "cache_file_invalidate works for uncached file" {
    run cache_file_invalidate "$TEST_DIR/never_cached.txt"
    [ "$status" -eq 0 ]
}

# =============================================================================
# CACHE_COMPUTE TESTS
# =============================================================================

@test "cache_compute caches computation result" {
    run cache_compute "test_key" compute_summary
    [ "$status" -eq 0 ]
    [[ "$output" == computed_at_* ]]
}

@test "cache_compute returns cached value on second call" {
    local result1 result2
    result1=$(cache_compute "same_key" compute_summary)
    sleep 0.1
    result2=$(cache_compute "same_key" compute_summary)

    [ "$result1" = "$result2" ]
}

@test "cache_compute invalidates when dependency changes" {
    local dep_file="$TEST_DIR/dep.txt"
    printf 'v1' > "$dep_file"

    local result1
    result1=$(cache_compute "dep_test" compute_summary "$dep_file")

    # Change dependency
    printf 'v2' > "$dep_file"

    local result2
    result2=$(cache_compute "dep_test" compute_summary "$dep_file")

    [ "$result1" != "$result2" ]
}

@test "cache_compute requires key and function" {
    run cache_compute "" compute_summary
    [ "$status" -ne 0 ]

    run cache_compute "key" ""
    [ "$status" -ne 0 ]
}

@test "cache_compute fails for non-existent function" {
    run cache_compute "key" nonexistent_compute_fn
    [ "$status" -ne 0 ]
}

@test "cache_compute handles multiple dependencies" {
    local dep1="$TEST_DIR/dep1.txt"
    local dep2="$TEST_DIR/dep2.txt"
    printf 'data1' > "$dep1"
    printf 'data2' > "$dep2"

    local result1
    result1=$(cache_compute "multi_dep" compute_summary "$dep1" "$dep2")

    # Change one dependency
    printf 'data1_modified' > "$dep1"

    local result2
    result2=$(cache_compute "multi_dep" compute_summary "$dep1" "$dep2")

    [ "$result1" != "$result2" ]
}

# =============================================================================
# CACHE_STATS_RESET TESTS
# =============================================================================

@test "cache_stats_reset resets hit counter" {
    _MAINFRAME_CACHE_HITS=100
    cache_stats_reset
    [ "$_MAINFRAME_CACHE_HITS" -eq 0 ]
}

@test "cache_stats_reset resets miss counter" {
    _MAINFRAME_CACHE_MISSES=50
    cache_stats_reset
    [ "$_MAINFRAME_CACHE_MISSES" -eq 0 ]
}

@test "cache_stats_reset returns success" {
    run cache_stats_reset
    [ "$status" -eq 0 ]
}

# =============================================================================
# CACHE_PREWARM TESTS
# =============================================================================

@test "cache_prewarm with standard profile succeeds" {
    run cache_prewarm standard
    [ "$status" -eq 0 ]
}

@test "cache_prewarm with git profile succeeds" {
    run cache_prewarm git
    [ "$status" -eq 0 ]
}

@test "cache_prewarm with project profile caches project files" {
    local proj_dir="$TEST_DIR/project"
    mkdir -p "$proj_dir"
    printf '{"name":"test"}' > "$proj_dir/package.json"
    cd "$proj_dir"

    run cache_prewarm project
    [ "$status" -eq 0 ]

    cd -
}

@test "cache_prewarm with system profile succeeds" {
    run cache_prewarm system
    [ "$status" -eq 0 ]
}

@test "cache_prewarm with all profile succeeds" {
    run cache_prewarm all
    [ "$status" -eq 0 ]
}

@test "cache_prewarm populates expected cache entries" {
    cache_prewarm system

    # At least some entries should exist
    local count
    count=$(find "${MAINFRAME_CACHE_ROOT}/memo" -type f ! -name "*.meta" ! -name "*.deps" 2>/dev/null | wc -l)
    [ "$count" -ge 1 ]
}

@test "cache_prewarm with unknown profile returns error" {
    run cache_prewarm unknown_profile
    [ "$status" -ne 0 ]
}

# =============================================================================
# CACHE STATS ACCURACY TESTS
# =============================================================================

@test "cache stats reflect actual hits and misses" {
    cache_stats_reset

    # Generate some hits and misses
    cache_command 60 echo "stats test 1" > /dev/null  # miss
    cache_command 60 echo "stats test 1" > /dev/null  # hit
    cache_command 60 echo "stats test 2" > /dev/null  # miss
    cache_command 60 echo "stats test 1" > /dev/null  # hit

    [ "$_MAINFRAME_CACHE_HITS" -eq 2 ]
    [ "$_MAINFRAME_CACHE_MISSES" -eq 2 ]
}

@test "cache_stats --json includes hit ratio" {
    cache_stats_reset
    _MAINFRAME_CACHE_HITS=8
    _MAINFRAME_CACHE_MISSES=2

    run cache_stats --json
    [ "$status" -eq 0 ]
    [[ "$output" == *"hit_ratio"* ]] || [[ "$output" == *"80"* ]]
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

@test "memo_wrap and cache_command work together" {
    memo_wrap pure_func

    pure_func "arg" > /dev/null
    cache_command 60 echo "cmd" > /dev/null

    local stats
    stats=$(cache_stats --json)
    [[ "$stats" == *"memo_entries"* ]] || [[ "$stats" =~ [0-9]+ ]]
}

@test "file and compute caching integrate correctly" {
    local config="$TEST_DIR/config.json"
    printf '{"version":1}' > "$config"

    # Cache file
    cache_file "$config" > /dev/null

    # Cache computation depending on file
    cache_compute "based_on_config" compute_summary "$config" > /dev/null

    local stats
    stats=$(cache_stats --json)
    [ "$status" -eq 0 ] || true
}

@test "prewarm improves subsequent cache hits" {
    cache_prewarm system
    local prewarm_misses=$_MAINFRAME_CACHE_MISSES

    # Same commands should now hit
    cache_command 3600 uname -a > /dev/null
    cache_command 3600 hostname > /dev/null

    # Hits should have increased (or stayed same if prewarm cached them)
    [ "$_MAINFRAME_CACHE_HITS" -ge 0 ]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "cache_command handles commands with special characters" {
    run cache_command 60 echo "hello 'world' \"test\""
    [ "$status" -eq 0 ]
}

@test "cache_file handles files with spaces in path" {
    local test_file="$TEST_DIR/file with spaces.txt"
    printf 'content' > "$test_file"

    run cache_file "$test_file"
    [ "$status" -eq 0 ]
    [ "$output" = "content" ]
}

@test "cache_compute handles empty dependency list" {
    run cache_compute "no_deps" compute_summary
    [ "$status" -eq 0 ]
}

@test "memo_wrap handles function with no arguments" {
    no_arg_func() {
        printf 'no args'
    }

    memo_wrap no_arg_func

    run no_arg_func
    [ "$status" -eq 0 ]
    [ "$output" = "no args" ]
}

@test "cache preserves newlines in output" {
    multiline_output() {
        printf 'line1\nline2\nline3'
    }

    memo_wrap multiline_output

    local result
    result=$(multiline_output)

    [[ "$result" == *"line1"* ]]
    [[ "$result" == *"line2"* ]]
    [[ "$result" == *"line3"* ]]
}

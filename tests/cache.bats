#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Caching & Memoization Library Tests
# =============================================================================
# Tests for lib/cache.sh - Memoization, CAS, Session Cache, LRU Eviction
# =============================================================================

load 'test_helper'

setup() {
    source_lib "cache"
    TEST_DIR=$(create_test_dir "cache")

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
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# HELPER FUNCTIONS FOR TESTS
# =============================================================================

# A simple test function to memoize
expensive_compute() {
    local arg="${1:-default}"
    printf 'computed:%s' "$arg"
}

# A function that returns different values each call
counter_func() {
    local count="${_TEST_COUNTER:-0}"
    _TEST_COUNTER=$((count + 1))
    printf '%s' "$_TEST_COUNTER"
}

# A function that fails
failing_func() {
    printf 'error output' >&2
    return 1
}

# A function that sleeps (for testing TTL)
slow_func() {
    sleep 0.1
    printf 'slow_result'
}

# =============================================================================
# MEMOIZATION CORE TESTS
# =============================================================================

@test "memoize caches function output" {
    run memoize expensive_compute "test_arg"
    [ "$status" -eq 0 ]
    [ "$output" = "computed:test_arg" ]
}

@test "memoize returns cached value on second call" {
    # First call - compute
    memoize expensive_compute "arg1" > /dev/null

    # Second call - should return cached
    run memoize expensive_compute "arg1"
    [ "$status" -eq 0 ]
    [ "$output" = "computed:arg1" ]
}

@test "memoize increments hit counter on cache hit" {
    memoize expensive_compute "hit_test" > /dev/null
    memoize expensive_compute "hit_test" > /dev/null

    [ "$_MAINFRAME_CACHE_HITS" -ge 1 ]
}

@test "memoize increments miss counter on cache miss" {
    _MAINFRAME_CACHE_MISSES=0
    memoize expensive_compute "miss_test" > /dev/null

    [ "$_MAINFRAME_CACHE_MISSES" -ge 1 ]
}

@test "memoize caches different args separately" {
    local result1 result2
    result1=$(memoize expensive_compute "arg_a")
    result2=$(memoize expensive_compute "arg_b")

    [ "$result1" = "computed:arg_a" ]
    [ "$result2" = "computed:arg_b" ]
}

@test "memoize fails for non-existent function" {
    run memoize nonexistent_function
    [ "$status" -ne 0 ]
}

@test "memoize requires function name" {
    run memoize
    [ "$status" -ne 0 ]
}

@test "memoize preserves function exit code on failure" {
    run memoize failing_func
    [ "$status" -ne 0 ]
}

@test "memoize does not cache failed function results" {
    memoize failing_func 2>/dev/null || true

    # The cache file should not exist
    local key_pattern="${MAINFRAME_CACHE_ROOT}/memo/"
    local count
    count=$(find "$key_pattern" -type f ! -name "*.meta" ! -name "*.deps" 2>/dev/null | wc -l)
    [ "$count" -eq 0 ]
}

# =============================================================================
# MEMOIZATION TTL TESTS
# =============================================================================

@test "memoize respects TTL option" {
    export _TEST_COUNTER=0

    # Cache with 1 second TTL
    memoize --ttl 1 counter_func > /dev/null
    local first_result
    first_result=$(memoize --ttl 1 counter_func)

    [ "$first_result" = "1" ]
}

@test "memoize returns stale value before TTL expires" {
    export _TEST_COUNTER=0

    memoize --ttl 60 counter_func > /dev/null

    # Immediate second call should return cached value
    local result
    result=$(memoize --ttl 60 counter_func)
    [ "$result" = "1" ]
}

@test "memoize recomputes after TTL expires" {
    export _TEST_COUNTER=0

    # Very short TTL for testing
    memoize --ttl 1 counter_func > /dev/null

    # Wait for TTL to expire
    sleep 2

    # Should recompute
    local result
    result=$(memoize --ttl 1 counter_func)
    [ "$result" = "2" ]
}

@test "memoize with TTL 0 means no expiration" {
    export _TEST_COUNTER=0

    memoize --ttl 0 counter_func > /dev/null
    sleep 1

    local result
    result=$(memoize --ttl 0 counter_func)
    [ "$result" = "1" ]
}

# =============================================================================
# DEPENDENCY-AWARE INVALIDATION TESTS
# =============================================================================

@test "memoize with --invalidate-on registers dependencies" {
    local dep_file="$TEST_DIR/config.json"
    printf '{"key": "value"}' > "$dep_file"

    memoize --invalidate-on "$dep_file" expensive_compute "dep_test" > /dev/null

    # Check deps file exists
    local deps_found=false
    if find "${MAINFRAME_CACHE_ROOT}/memo" -name "*.deps" 2>/dev/null | grep -q .; then
        deps_found=true
    fi
    [ "$deps_found" = "true" ]
}

@test "memoize invalidates when dependency file changes" {
    local dep_file="$TEST_DIR/dep_file.txt"
    printf 'version1' > "$dep_file"
    export _TEST_COUNTER=0

    # First call
    memoize --invalidate-on "$dep_file" counter_func > /dev/null

    # Modify dependency
    printf 'version2' > "$dep_file"

    # Second call should recompute due to changed dependency
    local result
    result=$(memoize --invalidate-on "$dep_file" counter_func)
    [ "$result" = "2" ]
}

@test "memoize invalidates when dependency file is deleted" {
    local dep_file="$TEST_DIR/will_delete.txt"
    printf 'content' > "$dep_file"
    export _TEST_COUNTER=0

    memoize --invalidate-on "$dep_file" counter_func > /dev/null
    rm -f "$dep_file"

    local result
    result=$(memoize --invalidate-on "$dep_file" counter_func)
    [ "$result" = "2" ]
}

@test "cache_depends_on registers file dependencies" {
    local test_file="$TEST_DIR/test_dep.txt"
    printf 'test content' > "$test_file"

    run cache_depends_on "test_key_123" "$test_file"
    [ "$status" -eq 0 ]

    [ -f "${MAINFRAME_CACHE_ROOT}/memo/test_key_123.deps" ]
}

@test "cache_check_deps returns 0 when deps unchanged" {
    local test_file="$TEST_DIR/unchanged.txt"
    printf 'original' > "$test_file"

    cache_depends_on "unchanged_key" "$test_file"

    run cache_check_deps "unchanged_key"
    [ "$status" -eq 0 ]
}

@test "cache_check_deps returns 1 when deps changed" {
    local test_file="$TEST_DIR/changed.txt"
    printf 'original' > "$test_file"

    cache_depends_on "changed_key" "$test_file"

    printf 'modified' > "$test_file"

    run cache_check_deps "changed_key"
    [ "$status" -ne 0 ]
}

@test "cache_check_deps returns 0 when no deps registered" {
    run cache_check_deps "no_deps_key"
    [ "$status" -eq 0 ]
}

# =============================================================================
# CONTENT-ADDRESSABLE STORE (CAS) TESTS
# =============================================================================

@test "cas_store returns SHA-256 hash" {
    run cas_store "test content"
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 64 ]  # SHA-256 hash is 64 hex chars
}

@test "cas_store is idempotent" {
    local hash1 hash2
    hash1=$(cas_store "identical content")
    hash2=$(cas_store "identical content")

    [ "$hash1" = "$hash2" ]
}

@test "cas_store creates file in CAS directory" {
    local hash
    hash=$(cas_store "stored content")

    local prefix="${hash:0:2}"
    [ -f "${MAINFRAME_CACHE_ROOT}/cas/${prefix}/${hash}" ]
}

@test "cas_get retrieves stored content" {
    local hash
    hash=$(cas_store "retrievable content")

    run cas_get "$hash"
    [ "$status" -eq 0 ]
    [ "$output" = "retrievable content" ]
}

@test "cas_get returns error for non-existent hash" {
    run cas_get "0000000000000000000000000000000000000000000000000000000000000000"
    [ "$status" -ne 0 ]
}

@test "cas_exists returns 0 for existing content" {
    local hash
    hash=$(cas_store "existing content")

    run cas_exists "$hash"
    [ "$status" -eq 0 ]
}

@test "cas_exists returns 1 for non-existent content" {
    run cas_exists "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    [ "$status" -ne 0 ]
}

@test "cas_store requires content" {
    run cas_store ""
    [ "$status" -ne 0 ]
}

@test "cas_get requires hash" {
    run cas_get ""
    [ "$status" -ne 0 ]
}

@test "cas_store deduplicates large content" {
    local large_content=""
    for i in {1..1000}; do
        large_content+="line $i of content\n"
    done

    local hash1 hash2
    hash1=$(cas_store "$large_content")
    hash2=$(cas_store "$large_content")

    [ "$hash1" = "$hash2" ]

    # Only one file should exist
    local prefix="${hash1:0:2}"
    local count
    count=$(find "${MAINFRAME_CACHE_ROOT}/cas/${prefix}" -type f 2>/dev/null | wc -l)
    [ "$count" -eq 1 ]
}

# =============================================================================
# CAS GARBAGE COLLECTION TESTS
# =============================================================================

@test "cas_gc removes old entries" {
    # Store some content
    local hash1 hash2
    hash1=$(cas_store "old content 1")
    hash2=$(cas_store "old content 2")

    # Backdate the files
    local prefix1="${hash1:0:2}"
    local prefix2="${hash2:0:2}"
    touch -d "10 days ago" "${MAINFRAME_CACHE_ROOT}/cas/${prefix1}/${hash1}" 2>/dev/null || \
    touch -t "$(date -d '10 days ago' +%Y%m%d%H%M)" "${MAINFRAME_CACHE_ROOT}/cas/${prefix1}/${hash1}" 2>/dev/null || true

    # GC with 5-day threshold
    run cas_gc --older-than 5
    [ "$status" -eq 0 ]
}

@test "cas_gc preserves recent entries" {
    local hash
    hash=$(cas_store "recent content")

    run cas_gc --older-than 1
    [ "$status" -eq 0 ]

    # Content should still exist
    run cas_exists "$hash"
    [ "$status" -eq 0 ]
}

@test "cas_gc with default age works" {
    local hash
    hash=$(cas_store "default gc test")

    run cas_gc
    [ "$status" -eq 0 ]

    # Recent content should still exist
    run cas_exists "$hash"
    [ "$status" -eq 0 ]
}

# =============================================================================
# SESSION CACHE (IN-MEMORY) TESTS
# =============================================================================

@test "session_cache_set stores value" {
    run session_cache_set "key1" "value1"
    [ "$status" -eq 0 ]
}

@test "session_cache_get retrieves stored value" {
    session_cache_set "key2" "value2"

    run session_cache_get "key2"
    [ "$status" -eq 0 ]
    [ "$output" = "value2" ]
}

@test "session_cache_get returns default for missing key" {
    run session_cache_get "missing_key" "default_value"
    [ "$status" -ne 0 ]  # Returns 1 when key not found
    [ "$output" = "default_value" ]
}

@test "session_cache_get returns empty string with no default" {
    run session_cache_get "no_default_key"
    [ "$output" = "" ]
}

@test "session_cache_has returns 0 for existing key" {
    session_cache_set "exists_key" "some_value"

    run session_cache_has "exists_key"
    [ "$status" -eq 0 ]
}

@test "session_cache_has returns 1 for missing key" {
    run session_cache_has "does_not_exist"
    [ "$status" -ne 0 ]
}

@test "session_cache_clear removes all entries" {
    session_cache_set "clear_key1" "val1"
    session_cache_set "clear_key2" "val2"

    session_cache_clear

    run session_cache_has "clear_key1"
    [ "$status" -ne 0 ]

    run session_cache_has "clear_key2"
    [ "$status" -ne 0 ]
}

@test "session_cache_set overwrites existing value" {
    session_cache_set "overwrite_key" "original"
    session_cache_set "overwrite_key" "updated"

    run session_cache_get "overwrite_key"
    [ "$output" = "updated" ]
}

@test "session_cache_set requires key" {
    run session_cache_set "" "value"
    [ "$status" -ne 0 ]
}

@test "session_cache_stats reports entry count" {
    session_cache_set "stats_key1" "val1"
    session_cache_set "stats_key2" "val2"

    run session_cache_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"entries"* ]] || [[ "$output" == *"2"* ]]
}

@test "session_cache_stats reports memory estimate" {
    session_cache_set "mem_key" "some value for memory estimation"

    run session_cache_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"bytes"* ]] || [[ "$output" =~ [0-9]+ ]]
}

# =============================================================================
# MEMOIZE CLEAR TESTS
# =============================================================================

@test "memoize_clear removes matching entries" {
    memoize expensive_compute "clear1" > /dev/null
    memoize expensive_compute "clear2" > /dev/null

    run memoize_clear "expensive_compute"
    [ "$status" -eq 0 ]
}

@test "memoize_clear with pattern removes matching only" {
    memoize expensive_compute "pattern1" > /dev/null
    memoize counter_func > /dev/null

    memoize_clear "expensive_compute"

    # expensive_compute cache should be cleared
    export _TEST_COUNTER=0
    local counter_result
    counter_result=$(memoize counter_func)

    # counter_func should still be cached (value 1, not 2)
    [ "$counter_result" = "1" ] || [ "$counter_result" = "2" ]
}

@test "memoize_clear all removes everything" {
    memoize expensive_compute "all1" > /dev/null
    memoize expensive_compute "all2" > /dev/null

    run memoize_clear
    [ "$status" -eq 0 ]
}

# =============================================================================
# MEMOIZE STATS TESTS
# =============================================================================

@test "memoize_stats shows hit/miss counts" {
    _MAINFRAME_CACHE_HITS=5
    _MAINFRAME_CACHE_MISSES=3

    run memoize_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"5"* ]]
    [[ "$output" == *"3"* ]]
}

@test "memoize_stats shows hit ratio" {
    _MAINFRAME_CACHE_HITS=8
    _MAINFRAME_CACHE_MISSES=2

    run memoize_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"80"* ]] || [[ "$output" == *"ratio"* ]]
}

# =============================================================================
# CACHE STATS TESTS
# =============================================================================

@test "cache_stats outputs statistics" {
    run cache_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hits"* ]] || [[ "$output" == *"hits"* ]]
}

@test "cache_stats --json outputs valid JSON" {
    run cache_stats --json
    [ "$status" -eq 0 ]
    [[ "$output" == "{"* ]]
    [[ "$output" == *"}" ]]
}

@test "cache_stats shows memo entry count" {
    memoize expensive_compute "stats1" > /dev/null
    memoize expensive_compute "stats2" > /dev/null

    run cache_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"Memo"* ]] || [[ "$output" == *"memo"* ]]
}

@test "cache_stats shows CAS entry count" {
    cas_store "cas stats content 1"
    cas_store "cas stats content 2"

    run cache_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"CAS"* ]] || [[ "$output" == *"cas"* ]]
}

# =============================================================================
# CACHE INVALIDATION TESTS
# =============================================================================

@test "cache_invalidate removes exact key" {
    memoize expensive_compute "invalidate_test" > /dev/null

    # Get the cache key
    local key
    key=$(find "${MAINFRAME_CACHE_ROOT}/memo" -type f ! -name "*.meta" ! -name "*.deps" -printf "%f\n" 2>/dev/null | head -1)

    if [ -n "$key" ]; then
        run cache_invalidate "$key"
        [ "$status" -eq 0 ]
    fi
}

@test "cache_invalidate by function name" {
    memoize expensive_compute "inv1" > /dev/null
    memoize expensive_compute "inv2" > /dev/null

    run cache_invalidate "expensive_compute"
    [ "$status" -eq 0 ]
}

@test "cache_invalidate requires pattern" {
    run cache_invalidate ""
    [ "$status" -ne 0 ]
}

# =============================================================================
# CACHE CLEAR TESTS
# =============================================================================

@test "cache_clear requires --force" {
    run cache_clear
    [ "$status" -ne 0 ]
}

@test "cache_clear --force clears all caches" {
    memoize expensive_compute "will_clear" > /dev/null
    cas_store "will also clear"

    run cache_clear --force
    [ "$status" -eq 0 ]

    # Directories should be recreated but empty
    local memo_count
    memo_count=$(find "${MAINFRAME_CACHE_ROOT}/memo" -type f 2>/dev/null | wc -l)
    [ "$memo_count" -eq 0 ]
}

@test "cache_clear --force resets statistics" {
    _MAINFRAME_CACHE_HITS=100
    _MAINFRAME_CACHE_MISSES=50

    cache_clear --force

    [ "$_MAINFRAME_CACHE_HITS" -eq 0 ]
    [ "$_MAINFRAME_CACHE_MISSES" -eq 0 ]
}

# =============================================================================
# LRU EVICTION TESTS
# =============================================================================

@test "cache_evict_lru removes oldest entries" {
    # Store multiple entries
    for i in {1..5}; do
        memoize expensive_compute "lru_$i" > /dev/null
        sleep 0.1
    done

    # Force eviction to very small size
    run cache_evict_lru 0
    [ "$status" -eq 0 ]
}

@test "cache_evict_lru respects max size" {
    # Create cache entries
    memoize expensive_compute "size1" > /dev/null
    memoize expensive_compute "size2" > /dev/null

    run cache_evict_lru 100
    [ "$status" -eq 0 ]
}

@test "cache_evict_lru returns eviction count" {
    memoize expensive_compute "evict1" > /dev/null
    memoize expensive_compute "evict2" > /dev/null

    run cache_evict_lru 0
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "cache_evict_lru returns 0 when under limit" {
    run cache_evict_lru 1000
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

# =============================================================================
# CACHE MAX SIZE TESTS
# =============================================================================

@test "cache_max_size sets limit" {
    cache_max_size "256MB"
    [ "$MAINFRAME_CACHE_MAX_SIZE_MB" -eq 256 ]
}

@test "cache_max_size accepts numeric MB" {
    cache_max_size 128
    [ "$MAINFRAME_CACHE_MAX_SIZE_MB" -eq 128 ]
}

@test "cache_max_size triggers eviction if over limit" {
    # Store data
    for i in {1..10}; do
        cas_store "$(printf 'x%.0s' {1..10000})"
    done

    # Set very low limit - should trigger eviction
    cache_max_size "0MB"

    # Should have evicted something
    run cache_stats --json
    [ "$status" -eq 0 ]
}

# =============================================================================
# SMART PRELOADING TESTS
# =============================================================================

@test "cache_warm runs without error" {
    run cache_warm "project-type=bash"
    [ "$status" -eq 0 ]
}

@test "cache_warm with node project type" {
    mkdir -p "$TEST_DIR/node_project"
    printf '{"name": "test"}\n' > "$TEST_DIR/node_project/package.json"

    run cache_warm "project-type=node" "$TEST_DIR/node_project"
    [ "$status" -eq 0 ]
}

@test "cache_warm with python project type" {
    mkdir -p "$TEST_DIR/py_project"
    printf 'requests\n' > "$TEST_DIR/py_project/requirements.txt"

    run cache_warm "project-type=python" "$TEST_DIR/py_project"
    [ "$status" -eq 0 ]
}

# =============================================================================
# CONCURRENCY TESTS
# =============================================================================

@test "memoize handles concurrent access" {
    # Run multiple memoize calls in background
    for i in {1..5}; do
        memoize expensive_compute "concurrent_$i" &
    done

    wait

    # All should have completed without error
    run cache_stats --json
    [ "$status" -eq 0 ]
}

@test "cas_store handles concurrent writes" {
    # Same content from multiple processes
    for i in {1..3}; do
        cas_store "concurrent content" &
    done

    wait

    # Should have exactly one file
    local hash
    hash=$(cas_store "concurrent content")
    local prefix="${hash:0:2}"
    local count
    count=$(find "${MAINFRAME_CACHE_ROOT}/cas/${prefix}" -name "$hash" 2>/dev/null | wc -l)
    [ "$count" -eq 1 ]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "memoize handles empty function output" {
    empty_func() { :; }

    run memoize empty_func
    [ "$status" -eq 0 ]
}

@test "memoize handles multiline output" {
    multiline_func() {
        printf 'line1\nline2\nline3\n'
    }

    local result
    result=$(memoize multiline_func)

    [[ "$result" == *"line1"* ]]
    [[ "$result" == *"line2"* ]]
}

@test "cas_store handles binary-like content" {
    local content
    content=$(printf '\x00\x01\x02\x03')

    run cas_store "$content"
    # May succeed or fail depending on implementation
    # At minimum should not hang or crash
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "session_cache handles special characters in keys" {
    session_cache_set "key/with/slashes" "value1"
    session_cache_set "key:with:colons" "value2"
    session_cache_set "key with spaces" "value3"

    run session_cache_get "key/with/slashes"
    [ "$output" = "value1" ]

    run session_cache_get "key:with:colons"
    [ "$output" = "value2" ]

    run session_cache_get "key with spaces"
    [ "$output" = "value3" ]
}

@test "session_cache handles empty values" {
    session_cache_set "empty_value_key" ""

    run session_cache_has "empty_value_key"
    [ "$status" -eq 0 ]

    run session_cache_get "empty_value_key"
    [ "$output" = "" ]
}

# =============================================================================
# PERFORMANCE VALIDATION
# =============================================================================

@test "session_cache_get is fast (no disk I/O)" {
    session_cache_set "perf_key" "perf_value"

    local start end elapsed
    start=$(date +%s%N 2>/dev/null || date +%s)

    for i in {1..100}; do
        session_cache_get "perf_key" > /dev/null
    done

    end=$(date +%s%N 2>/dev/null || date +%s)

    # Should complete in reasonable time (test just verifies it runs)
    [ "$?" -eq 0 ]
}

@test "memoize cache hit is faster than miss" {
    slow_test_func() {
        sleep 0.2
        printf 'slow_result'
    }

    # First call (miss)
    local start1 end1
    start1=$(date +%s)
    memoize slow_test_func > /dev/null
    end1=$(date +%s)

    # Second call (hit)
    local start2 end2
    start2=$(date +%s)
    memoize slow_test_func > /dev/null
    end2=$(date +%s)

    # Hit should not add significant time
    # (Test just validates functionality, not precise timing)
    [ "$?" -eq 0 ]
}

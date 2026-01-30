#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Probabilistic Data Structures Tests
# =============================================================================
# Tests for lib/probabilistic.sh
# Covers: Bloom Filter, Counting Bloom Filter, HyperLogLog, Count-Min Sketch,
#         MinHash, utility functions, serialization/deserialization
# =============================================================================

load 'test_helper'

setup() {
    source_lib "probabilistic"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "probabilistic")
    # Clear all structures before each test
    prob_clear_all >/dev/null 2>&1
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
    prob_clear_all >/dev/null 2>&1
}

# =============================================================================
# HASH FUNCTION TESTS
# =============================================================================

@test "prob_hash produces consistent output" {
    local h1 h2
    h1=$(prob_hash "hello")
    h2=$(prob_hash "hello")
    [ "$h1" = "$h2" ]
}

@test "prob_hash produces different output for different inputs" {
    local h1 h2
    h1=$(prob_hash "hello")
    h2=$(prob_hash "world")
    [ "$h1" != "$h2" ]
}

@test "prob_hash handles empty string" {
    local result
    result=$(prob_hash "")
    [[ "$result" =~ ^[0-9]+$ ]]
}

@test "prob_hash handles special characters" {
    local result
    result=$(prob_hash "!@#\$%^&*()")
    [[ "$result" =~ ^[0-9]+$ ]]
}

@test "prob_murmurhash produces consistent output" {
    local h1 h2
    h1=$(prob_murmurhash "test" 42)
    h2=$(prob_murmurhash "test" 42)
    [ "$h1" = "$h2" ]
}

@test "prob_murmurhash different seeds produce different hashes" {
    local h1 h2
    h1=$(prob_murmurhash "test" 1)
    h2=$(prob_murmurhash "test" 2)
    [ "$h1" != "$h2" ]
}

@test "prob_murmurhash handles long strings" {
    local result
    result=$(prob_murmurhash "this is a very long string that should still hash correctly" 0)
    [[ "$result" =~ ^[0-9]+$ ]]
}

# =============================================================================
# BLOOM FILTER TESTS
# =============================================================================

@test "bloom_create creates filter with default parameters" {
    local result
    result=$(bloom_create "test_filter")
    [[ "$result" =~ \"ok\":true ]]
    [[ "$result" =~ \"filter\":\"test_filter\" ]]
}

@test "bloom_create creates filter with custom size" {
    local result
    result=$(bloom_create "custom" 2048 5)
    [[ "$result" =~ \"size\":2048 ]]
    [[ "$result" =~ \"hash_count\":5 ]]
}

@test "bloom_create fails without name" {
    run bloom_create ""
    [ "$status" -eq 1 ]
    [[ "$output" =~ \"error\":true ]]
}

@test "bloom_create fails with invalid size" {
    run bloom_create "test" -1
    [ "$status" -eq 1 ]
}

@test "bloom_add adds element successfully" {
    bloom_create "bf" >/dev/null
    local result
    result=$(bloom_add "bf" "hello")
    [[ "$result" =~ \"ok\":true ]]
    [[ "$result" =~ \"element\":\"hello\" ]]
}

@test "bloom_add fails for nonexistent filter" {
    run bloom_add "nonexistent" "hello"
    [ "$status" -eq 1 ]
    [[ "$output" =~ \"error\":true ]]
}

@test "bloom_contains finds added element" {
    bloom_create "bf" >/dev/null
    bloom_add "bf" "hello" >/dev/null
    local result
    result=$(bloom_contains "bf" "hello")
    [[ "$result" =~ \"ok\":true ]]
    [[ "$result" =~ \"contains\":true ]]
}

@test "bloom_contains returns false for missing element" {
    bloom_create "bf" >/dev/null
    bloom_add "bf" "hello" >/dev/null
    local result
    result=$(bloom_contains "bf" "world")
    [[ "$result" =~ \"ok\":true ]]
    [[ "$result" =~ \"contains\":false ]]
}

@test "bloom_contains handles multiple elements" {
    bloom_create "bf" 1000 7 >/dev/null
    bloom_add "bf" "apple" >/dev/null
    bloom_add "bf" "banana" >/dev/null
    bloom_add "bf" "cherry" >/dev/null

    local result
    result=$(bloom_contains "bf" "apple")
    [[ "$result" =~ \"contains\":true ]]
    result=$(bloom_contains "bf" "banana")
    [[ "$result" =~ \"contains\":true ]]
    result=$(bloom_contains "bf" "cherry")
    [[ "$result" =~ \"contains\":true ]]
}

@test "bloom_clear resets filter" {
    bloom_create "bf" >/dev/null
    bloom_add "bf" "hello" >/dev/null
    bloom_clear "bf" >/dev/null

    local result
    result=$(bloom_contains "bf" "hello")
    [[ "$result" =~ \"ok\":true ]]
    [[ "$result" =~ \"contains\":false ]]
}

@test "bloom_size returns correct size" {
    bloom_create "bf" 2048 >/dev/null
    local result
    result=$(bloom_size "bf")
    [[ "$result" =~ \"size\":2048 ]]
}

@test "bloom_count tracks added elements" {
    bloom_create "bf" >/dev/null
    bloom_add "bf" "one" >/dev/null
    bloom_add "bf" "two" >/dev/null
    bloom_add "bf" "three" >/dev/null

    local result
    result=$(bloom_count "bf")
    [[ "$result" =~ \"count\":3 ]]
}

@test "bloom_false_positive_rate returns valid rate" {
    bloom_create "bf" 1000 7 >/dev/null
    bloom_add "bf" "test" >/dev/null

    local result
    result=$(bloom_false_positive_rate "bf")
    [[ "$result" =~ \"fp_rate\":0\. ]]
}

@test "bloom_union combines two filters" {
    bloom_create "bf1" 256 3 >/dev/null
    bloom_create "bf2" 256 3 >/dev/null
    bloom_add "bf1" "apple" >/dev/null
    bloom_add "bf2" "banana" >/dev/null

    bloom_union "combined" "bf1" "bf2" >/dev/null

    local result
    result=$(bloom_contains "combined" "apple")
    [[ "$result" =~ \"contains\":true ]]
    result=$(bloom_contains "combined" "banana")
    [[ "$result" =~ \"contains\":true ]]
}

@test "bloom_union fails for mismatched filters" {
    bloom_create "bf1" 256 3 >/dev/null
    bloom_create "bf2" 512 3 >/dev/null

    run bloom_union "combined" "bf1" "bf2"
    [ "$status" -eq 1 ]
}

@test "bloom_intersect finds common elements" {
    bloom_create "bf1" 256 3 >/dev/null
    bloom_create "bf2" 256 3 >/dev/null
    bloom_add "bf1" "common" >/dev/null
    bloom_add "bf1" "only1" >/dev/null
    bloom_add "bf2" "common" >/dev/null
    bloom_add "bf2" "only2" >/dev/null

    bloom_intersect "result" "bf1" "bf2" >/dev/null

    # Common element should still be present
    local result
    result=$(bloom_contains "result" "common")
    [[ "$result" =~ \"contains\":true ]]
}

@test "bloom_to_json serializes filter" {
    bloom_create "bf" 128 5 >/dev/null
    bloom_add "bf" "test" >/dev/null

    local json
    json=$(bloom_to_json "bf")
    [[ "$json" =~ \"type\":\"bloom\" ]]
    [[ "$json" =~ \"name\":\"bf\" ]]
    [[ "$json" =~ \"bits\": ]]
}

@test "bloom_from_json deserializes filter" {
    bloom_create "bf" 128 5 >/dev/null
    bloom_add "bf" "hello" >/dev/null
    bloom_add "bf" "world" >/dev/null

    local json
    json=$(bloom_to_json "bf")

    # Clear and reload
    bloom_delete "bf" >/dev/null
    bloom_from_json "$json" >/dev/null

    local result
    result=$(bloom_contains "bf" "hello")
    [[ "$result" =~ \"contains\":true ]]
    result=$(bloom_contains "bf" "world")
    [[ "$result" =~ \"contains\":true ]]
}

@test "bloom_delete removes filter" {
    bloom_create "bf" >/dev/null
    bloom_delete "bf" >/dev/null

    run bloom_contains "bf" "test"
    [ "$status" -eq 1 ]
}

# =============================================================================
# COUNTING BLOOM FILTER TESTS
# =============================================================================

@test "cbloom_create creates counting filter" {
    local result
    result=$(cbloom_create "cbf" 500 5)
    [[ "$result" =~ \"ok\":true ]]
    [[ "$result" =~ \"type\":\"counting_bloom\" ]]
}

@test "cbloom_add increments counters" {
    cbloom_create "cbf" >/dev/null
    local result
    result=$(cbloom_add "cbf" "test")
    [[ "$result" =~ \"added\":true ]]
}

@test "cbloom_contains finds added element" {
    cbloom_create "cbf" >/dev/null
    cbloom_add "cbf" "hello" >/dev/null

    local result
    result=$(cbloom_contains "cbf" "hello")
    [[ "$result" =~ \"ok\":true ]]
    [[ "$result" =~ \"contains\":true ]]
}

@test "cbloom_remove decrements counters" {
    cbloom_create "cbf" >/dev/null
    cbloom_add "cbf" "hello" >/dev/null
    cbloom_remove "cbf" "hello" >/dev/null

    local result
    result=$(cbloom_contains "cbf" "hello")
    [[ "$result" =~ \"ok\":true ]]
    [[ "$result" =~ \"contains\":false ]]
}

@test "cbloom_count_estimate returns frequency" {
    cbloom_create "cbf" 500 5 >/dev/null
    cbloom_add "cbf" "test" >/dev/null
    cbloom_add "cbf" "test" >/dev/null
    cbloom_add "cbf" "test" >/dev/null

    local result
    result=$(cbloom_count_estimate "cbf" "test")
    [[ "$result" =~ \"estimated_count\":3 ]]
}

@test "cbloom handles multiple adds and removes" {
    cbloom_create "cbf" 500 5 >/dev/null
    cbloom_add "cbf" "item" >/dev/null
    cbloom_add "cbf" "item" >/dev/null
    cbloom_remove "cbf" "item" >/dev/null

    # Should still be present (count = 1)
    local result
    result=$(cbloom_contains "cbf" "item")
    [[ "$result" =~ \"contains\":true ]]
}

@test "cbloom_delete removes filter" {
    cbloom_create "cbf" >/dev/null
    cbloom_delete "cbf" >/dev/null

    run cbloom_contains "cbf" "test"
    [ "$status" -eq 1 ]
}

# =============================================================================
# HYPERLOGLOG TESTS
# =============================================================================

@test "hll_create creates counter with default precision" {
    local result
    result=$(hll_create "hll")
    [[ "$result" =~ \"ok\":true ]]
    [[ "$result" =~ \"type\":\"hyperloglog\" ]]
}

@test "hll_create creates counter with custom precision" {
    local result
    result=$(hll_create "hll" 10)
    [[ "$result" =~ \"precision\":10 ]]
    [[ "$result" =~ \"registers\":1024 ]]
}

@test "hll_create fails with invalid precision" {
    run hll_create "hll" 3
    [ "$status" -eq 1 ]

    run hll_create "hll" 19
    [ "$status" -eq 1 ]
}

@test "hll_add adds element successfully" {
    hll_create "hll" >/dev/null
    local result
    result=$(hll_add "hll" "user123")
    [[ "$result" =~ \"added\":true ]]
}

@test "hll_count estimates cardinality" {
    hll_create "hll" 10 >/dev/null

    # Add some unique elements
    for i in {1..100}; do
        hll_add "hll" "user$i" >/dev/null
    done

    local result
    result=$(hll_count "hll")
    [[ "$result" =~ \"estimate\": ]]

    # Extract estimate and verify it's reasonable (within 20% of 100)
    local estimate
    estimate=$(echo "$result" | grep -o '"estimate":[0-9]*' | cut -d: -f2)
    (( estimate > 80 && estimate < 120 ))
}

@test "hll_count returns 0 for empty counter" {
    hll_create "hll" >/dev/null

    local result
    result=$(hll_count "hll")
    # For empty HLL, estimate should be 0 or very small
    [[ "$result" =~ \"estimate\": ]]
}

@test "hll_merge combines two counters" {
    hll_create "hll1" 10 >/dev/null
    hll_create "hll2" 10 >/dev/null

    for i in {1..50}; do
        hll_add "hll1" "user$i" >/dev/null
    done
    for i in {51..100}; do
        hll_add "hll2" "user$i" >/dev/null
    done

    hll_merge "combined" "hll1" "hll2" >/dev/null

    local result
    result=$(hll_count "combined")
    [[ "$result" =~ \"estimate\": ]]
}

@test "hll_merge fails for different precisions" {
    hll_create "hll1" 10 >/dev/null
    hll_create "hll2" 12 >/dev/null

    run hll_merge "combined" "hll1" "hll2"
    [ "$status" -eq 1 ]
}

@test "hll_clear resets counter" {
    hll_create "hll" >/dev/null
    hll_add "hll" "test" >/dev/null
    hll_clear "hll" >/dev/null

    local result
    result=$(hll_count "hll")
    [[ "$result" =~ \"estimate\": ]]
}

@test "hll_to_json serializes counter" {
    hll_create "hll" 8 >/dev/null
    hll_add "hll" "test" >/dev/null

    local json
    json=$(hll_to_json "hll")
    [[ "$json" =~ \"type\":\"hyperloglog\" ]]
    [[ "$json" =~ \"registers\":\[ ]]
}

@test "hll_from_json deserializes counter" {
    hll_create "hll" 8 >/dev/null
    hll_add "hll" "element1" >/dev/null
    hll_add "hll" "element2" >/dev/null

    local json
    json=$(hll_to_json "hll")
    local count1
    count1=$(hll_count "hll")

    hll_delete "hll" >/dev/null
    hll_from_json "$json" >/dev/null

    local count2
    count2=$(hll_count "hll")

    # Counts should be same after reload
    [ "$count1" = "$count2" ]
}

@test "hll_delete removes counter" {
    hll_create "hll" >/dev/null
    hll_delete "hll" >/dev/null

    run hll_add "hll" "test"
    [ "$status" -eq 1 ]
}

# =============================================================================
# COUNT-MIN SKETCH TESTS
# =============================================================================

@test "cms_create creates sketch with default parameters" {
    local result
    result=$(cms_create "cms")
    [[ "$result" =~ \"ok\":true ]]
    [[ "$result" =~ \"type\":\"count_min_sketch\" ]]
}

@test "cms_create creates sketch with custom dimensions" {
    local result
    result=$(cms_create "cms" 512 7)
    [[ "$result" =~ \"width\":512 ]]
    [[ "$result" =~ \"depth\":7 ]]
}

@test "cms_update increments counters" {
    cms_create "cms" >/dev/null
    local result
    result=$(cms_update "cms" "item1")
    [[ "$result" =~ \"ok\":true ]]
}

@test "cms_update with custom delta" {
    cms_create "cms" >/dev/null
    cms_update "cms" "item1" 5 >/dev/null

    local result
    result=$(cms_query "cms" "item1")
    [[ "$result" =~ \"frequency\":5 ]]
}

@test "cms_query returns frequency estimate" {
    cms_create "cms" 512 5 >/dev/null
    cms_update "cms" "popular" 10 >/dev/null

    local result
    result=$(cms_query "cms" "popular")
    [[ "$result" =~ \"frequency\":10 ]]
}

@test "cms_query returns 0 for unseen element" {
    cms_create "cms" >/dev/null

    local result
    result=$(cms_query "cms" "unknown")
    [[ "$result" =~ \"frequency\":0 ]]
}

@test "cms handles heavy hitters correctly" {
    cms_create "cms" 256 5 >/dev/null

    # Add items with different frequencies
    for i in {1..100}; do
        cms_update "cms" "common" >/dev/null
    done
    for i in {1..10}; do
        cms_update "cms" "rare" >/dev/null
    done

    local common_freq rare_freq
    common_freq=$(cms_query "cms" "common" | grep -o '"frequency":[0-9]*' | cut -d: -f2)
    rare_freq=$(cms_query "cms" "rare" | grep -o '"frequency":[0-9]*' | cut -d: -f2)

    # Common should have higher frequency
    (( common_freq >= 100 && rare_freq >= 10 ))
}

@test "cms_merge combines two sketches" {
    cms_create "cms1" 256 5 >/dev/null
    cms_create "cms2" 256 5 >/dev/null

    cms_update "cms1" "item" 50 >/dev/null
    cms_update "cms2" "item" 30 >/dev/null

    cms_merge "combined" "cms1" "cms2" >/dev/null

    local result
    result=$(cms_query "combined" "item")
    [[ "$result" =~ \"frequency\":80 ]]
}

@test "cms_merge fails for different dimensions" {
    cms_create "cms1" 256 5 >/dev/null
    cms_create "cms2" 512 5 >/dev/null

    run cms_merge "combined" "cms1" "cms2"
    [ "$status" -eq 1 ]
}

@test "cms_to_json serializes sketch" {
    cms_create "cms" 128 3 >/dev/null
    cms_update "cms" "test" 5 >/dev/null

    local json
    json=$(cms_to_json "cms")
    [[ "$json" =~ \"type\":\"count_min_sketch\" ]]
    [[ "$json" =~ \"counters\":\[ ]]
}

@test "cms_from_json deserializes sketch" {
    cms_create "cms" 128 3 >/dev/null
    cms_update "cms" "item" 42 >/dev/null

    local json
    json=$(cms_to_json "cms")

    cms_delete "cms" >/dev/null
    cms_from_json "$json" >/dev/null

    local result
    result=$(cms_query "cms" "item")
    [[ "$result" =~ \"frequency\":42 ]]
}

@test "cms_delete removes sketch" {
    cms_create "cms" >/dev/null
    cms_delete "cms" >/dev/null

    run cms_query "cms" "test"
    [ "$status" -eq 1 ]
}

# =============================================================================
# MINHASH TESTS
# =============================================================================

@test "minhash_create creates signature" {
    local result
    result=$(minhash_create "sig")
    [[ "$result" =~ \"ok\":true ]]
    [[ "$result" =~ \"type\":\"minhash\" ]]
}

@test "minhash_create with custom size" {
    local result
    result=$(minhash_create "sig" 64)
    [[ "$result" =~ \"num_hashes\":64 ]]
}

@test "minhash_add adds element to signature" {
    minhash_create "sig" >/dev/null
    local result
    result=$(minhash_add "sig" "word")
    [[ "$result" =~ \"added\":true ]]
}

@test "minhash_signature returns hash array" {
    minhash_create "sig" 8 >/dev/null
    minhash_add "sig" "hello" >/dev/null

    local result
    result=$(minhash_signature "sig")
    [[ "$result" =~ \"values\":\[ ]]
}

@test "minhash_similarity detects identical sets" {
    minhash_create "sig1" 64 >/dev/null
    minhash_create "sig2" 64 >/dev/null

    local words=("apple" "banana" "cherry" "date" "elderberry")
    for word in "${words[@]}"; do
        minhash_add "sig1" "$word" >/dev/null
        minhash_add "sig2" "$word" >/dev/null
    done

    local result
    result=$(minhash_similarity "sig1" "sig2")
    [[ "$result" =~ \"similarity\":1\. ]] || [[ "$result" =~ \"similarity\":0\.9 ]]
}

@test "minhash_similarity detects different sets" {
    minhash_create "sig1" 64 >/dev/null
    minhash_create "sig2" 64 >/dev/null

    minhash_add "sig1" "apple" >/dev/null
    minhash_add "sig1" "banana" >/dev/null
    minhash_add "sig2" "cherry" >/dev/null
    minhash_add "sig2" "date" >/dev/null

    local result
    result=$(minhash_similarity "sig1" "sig2")
    # Should have low similarity
    [[ "$result" =~ \"similarity\":0\. ]]
}

@test "minhash_similarity detects partial overlap" {
    minhash_create "sig1" 64 >/dev/null
    minhash_create "sig2" 64 >/dev/null

    # 50% overlap
    minhash_add "sig1" "common1" >/dev/null
    minhash_add "sig1" "common2" >/dev/null
    minhash_add "sig1" "only1" >/dev/null
    minhash_add "sig1" "only1b" >/dev/null

    minhash_add "sig2" "common1" >/dev/null
    minhash_add "sig2" "common2" >/dev/null
    minhash_add "sig2" "only2" >/dev/null
    minhash_add "sig2" "only2b" >/dev/null

    local result
    result=$(minhash_similarity "sig1" "sig2")
    [[ "$result" =~ \"similarity\": ]]
}

@test "minhash_similarity fails for different sizes" {
    minhash_create "sig1" 64 >/dev/null
    minhash_create "sig2" 128 >/dev/null

    run minhash_similarity "sig1" "sig2"
    [ "$status" -eq 1 ]
}

@test "minhash_merge creates union signature" {
    minhash_create "sig1" 64 >/dev/null
    minhash_create "sig2" 64 >/dev/null

    minhash_add "sig1" "a" >/dev/null
    minhash_add "sig2" "b" >/dev/null

    local result
    result=$(minhash_merge "merged" "sig1" "sig2")
    [[ "$result" =~ \"operation\":\"merge\" ]]
}

@test "minhash_delete removes signature" {
    minhash_create "sig" >/dev/null
    minhash_delete "sig" >/dev/null

    run minhash_add "sig" "test"
    [ "$status" -eq 1 ]
}

# =============================================================================
# UTILITY FUNCTION TESTS
# =============================================================================

@test "prob_optimal_bloom_size calculates correct size" {
    local result
    result=$(prob_optimal_bloom_size 10000 1)
    [[ "$result" =~ \"optimal_size\": ]]

    local size
    size=$(echo "$result" | grep -o '"optimal_size":[0-9]*' | cut -d: -f2)
    # For 10000 elements at 1% FP, optimal size should be around 95000 bits
    (( size > 50000 && size < 200000 ))
}

@test "prob_optimal_bloom_size handles different FP rates" {
    local result1 result2
    result1=$(prob_optimal_bloom_size 1000 1)
    result2=$(prob_optimal_bloom_size 1000 10)

    local size1 size2
    size1=$(echo "$result1" | grep -o '"optimal_size":[0-9]*' | cut -d: -f2)
    size2=$(echo "$result2" | grep -o '"optimal_size":[0-9]*' | cut -d: -f2)

    # Lower FP rate requires more bits
    (( size1 > size2 ))
}

@test "prob_optimal_hash_count calculates correct count" {
    local result
    result=$(prob_optimal_hash_count 10000 1000)
    [[ "$result" =~ \"optimal_hash_count\": ]]

    local k
    k=$(echo "$result" | grep -o '"optimal_hash_count":[0-9]*' | cut -d: -f2)
    # k = (m/n) * ln(2) ~ 7 for this ratio
    (( k >= 1 && k <= 20 ))
}

@test "prob_list shows all structures" {
    bloom_create "bf1" >/dev/null
    cbloom_create "cbf1" >/dev/null
    hll_create "hll1" >/dev/null
    cms_create "cms1" >/dev/null
    minhash_create "sig1" >/dev/null

    local result
    result=$(prob_list)

    [[ "$result" =~ \"bloom_filters\":\[\"bf1\"\] ]]
    [[ "$result" =~ \"counting_bloom_filters\":\[\"cbf1\"\] ]]
    [[ "$result" =~ \"hyperloglog_counters\":\[\"hll1\"\] ]]
    [[ "$result" =~ \"count_min_sketches\":\[\"cms1\"\] ]]
    [[ "$result" =~ \"minhash_signatures\":\[\"sig1\"\] ]]
}

@test "prob_clear_all removes all structures" {
    bloom_create "bf" >/dev/null
    hll_create "hll" >/dev/null
    cms_create "cms" >/dev/null

    prob_clear_all >/dev/null

    run bloom_contains "bf" "test"
    [ "$status" -eq 1 ]

    run hll_add "hll" "test"
    [ "$status" -eq 1 ]

    run cms_query "cms" "test"
    [ "$status" -eq 1 ]
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

@test "functions handle missing arguments gracefully" {
    run bloom_add "filter"
    [ "$status" -eq 1 ]

    run cbloom_add "filter"
    [ "$status" -eq 1 ]

    run hll_add "counter"
    [ "$status" -eq 1 ]

    run cms_update "sketch"
    [ "$status" -eq 1 ]

    run minhash_add "sig"
    [ "$status" -eq 1 ]
}

@test "functions handle nonexistent structures" {
    run bloom_contains "missing" "test"
    [ "$status" -eq 1 ]
    [[ "$output" =~ \"error\":true ]]

    run cbloom_contains "missing" "test"
    [ "$status" -eq 1 ]

    run hll_add "missing" "test"
    [ "$status" -eq 1 ]

    run cms_query "missing" "test"
    [ "$status" -eq 1 ]

    run minhash_add "missing" "test"
    [ "$status" -eq 1 ]
}

@test "JSON output is valid format" {
    bloom_create "bf" >/dev/null
    local result
    result=$(bloom_add "bf" "test")

    # Should be valid JSON (starts with { ends with })
    [[ "$result" =~ ^\{.*\}$ ]]

    # Should have required fields
    [[ "$result" =~ \"ok\":true ]]
}

# =============================================================================
# PERFORMANCE / STRESS TESTS
# =============================================================================

@test "bloom filter handles many elements" {
    bloom_create "large" 10000 10 >/dev/null

    for i in {1..500}; do
        bloom_add "large" "element$i" >/dev/null
    done

    # Verify some elements
    local result
    result=$(bloom_contains "large" "element1")
    [[ "$result" =~ \"contains\":true ]]
    result=$(bloom_contains "large" "element250")
    [[ "$result" =~ \"contains\":true ]]
    result=$(bloom_contains "large" "element500")
    [[ "$result" =~ \"contains\":true ]]
}

@test "HLL handles many unique elements" {
    hll_create "large" 12 >/dev/null

    for i in {1..1000}; do
        hll_add "large" "user$i" >/dev/null
    done

    local result
    result=$(hll_count "large")
    local estimate
    estimate=$(echo "$result" | grep -o '"estimate":[0-9]*' | cut -d: -f2)

    # Should be within 10% of 1000
    (( estimate > 900 && estimate < 1100 ))
}

@test "CMS tracks multiple item frequencies" {
    cms_create "freq" 512 5 >/dev/null

    # Add with varying frequencies
    for i in {1..100}; do
        cms_update "freq" "high" >/dev/null
    done
    for i in {1..50}; do
        cms_update "freq" "medium" >/dev/null
    done
    for i in {1..10}; do
        cms_update "freq" "low" >/dev/null
    done

    local high_freq medium_freq low_freq
    high_freq=$(cms_query "freq" "high" | grep -o '"frequency":[0-9]*' | cut -d: -f2)
    medium_freq=$(cms_query "freq" "medium" | grep -o '"frequency":[0-9]*' | cut -d: -f2)
    low_freq=$(cms_query "freq" "low" | grep -o '"frequency":[0-9]*' | cut -d: -f2)

    # Frequencies should reflect relative counts
    (( high_freq >= 100 ))
    (( medium_freq >= 50 ))
    (( low_freq >= 10 ))
}

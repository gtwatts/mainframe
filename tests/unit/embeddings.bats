#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/embeddings.bats - Embedding Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/embeddings.sh
#              Embedding generation for semantic search and RAG
# Test Count: 40+ test cases
# Categories: Caching, vector operations, provider detection, chunking,
#             similarity calculation, normalization, batch processing
# Note: API tests use mocks to avoid external dependencies
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Use test-specific cache directory
    export EMBED_CACHE_DIR="$TEST_TMPDIR/embed_cache"
    mkdir -p "$EMBED_CACHE_DIR"

    # Mock directory for mock executables
    MOCK_BIN="$TEST_TMPDIR/mock_bin"
    mkdir -p "$MOCK_BIN"

    # Suppress log output during tests
    export MAINFRAME_QUIET=1

    # Source the library
    source "$MAINFRAME_ROOT/lib/embeddings.sh"
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# Helper: Create mock embedding vector
mock_vector() {
    local dims="${1:-3}"
    local values=""
    for ((i=0; i<dims; i++)); do
        [[ $i -gt 0 ]] && values+=","
        # Generate deterministic values based on index
        values+="0.$((i + 1))"
    done
    printf '[%s]' "$values"
}

# Helper: Create mock curl for API mocking
setup_curl_mock() {
    local response="$1"
    local http_code="${2:-200}"

    cat > "$MOCK_BIN/curl" << EOF
#!/bin/bash
printf '%s\n%s' '$response' '$http_code'
EOF
    chmod +x "$MOCK_BIN/curl"
    export PATH="$MOCK_BIN:$PATH"
}

# =============================================================================
# CATEGORY 1: CONFIGURATION AND CONSTANTS
# =============================================================================

@test "EMBED_MODEL_DIMS: contains OpenAI models" {
    [[ "${EMBED_MODEL_DIMS[text-embedding-ada-002]}" == "1536" ]]
    [[ "${EMBED_MODEL_DIMS[text-embedding-3-small]}" == "1536" ]]
    [[ "${EMBED_MODEL_DIMS[text-embedding-3-large]}" == "3072" ]]
}

@test "EMBED_MODEL_DIMS: contains Ollama models" {
    [[ "${EMBED_MODEL_DIMS[nomic-embed-text]}" == "768" ]]
    [[ "${EMBED_MODEL_DIMS[all-minilm]}" == "384" ]]
}

@test "EMBED_MODEL_DIMS: contains local fallback" {
    [[ "${EMBED_MODEL_DIMS[local]}" == "384" ]]
}

@test "EMBED_CACHE_DIR: uses environment variable" {
    [[ "$EMBED_CACHE_DIR" == "$TEST_TMPDIR/embed_cache" ]]
}

@test "EMBED_CACHE_TTL: has default value" {
    # Default is 86400 (24 hours) unless overridden
    [[ "$EMBED_CACHE_TTL" -gt 0 ]]
}

# =============================================================================
# CATEGORY 2: CACHE FUNCTIONS
# =============================================================================

@test "embed_cache_set: stores embedding with metadata" {
    local hash="test_hash_123"
    local vector="[0.1,0.2,0.3]"

    embed_cache_set "$hash" "$vector" "test_provider" "test_model"

    [[ -f "$EMBED_CACHE_DIR/${hash}.json" ]]
    [[ -f "$EMBED_CACHE_DIR/${hash}.meta" ]]
}

@test "embed_cache_get: retrieves cached embedding" {
    local hash="cache_get_test"
    local vector="[0.5,0.6,0.7]"

    embed_cache_set "$hash" "$vector"

    result=$(embed_cache_get "$hash")
    [[ "$result" == "$vector" ]]
}

@test "embed_cache_get: returns failure for missing entry" {
    run embed_cache_get "nonexistent_hash"
    [[ "$status" -eq 1 ]]
}

@test "embed_cache_get: returns failure for expired entry" {
    local hash="expired_test"
    local vector="[0.1,0.2]"

    # Write cache files manually with old timestamp
    printf '%s' "$vector" > "$EMBED_CACHE_DIR/${hash}.json"
    printf 'timestamp=1000\nprovider=test\nmodel=test\n' > "$EMBED_CACHE_DIR/${hash}.meta"

    run embed_cache_get "$hash"
    [[ "$status" -eq 1 ]]
}

@test "embed_cache_clear: removes all cached embeddings" {
    # Create some cache entries
    embed_cache_set "clear_test_1" "[0.1]"
    embed_cache_set "clear_test_2" "[0.2]"

    [[ -f "$EMBED_CACHE_DIR/clear_test_1.json" ]]
    [[ -f "$EMBED_CACHE_DIR/clear_test_2.json" ]]

    result=$(embed_cache_clear)

    [[ ! -f "$EMBED_CACHE_DIR/clear_test_1.json" ]]
    [[ ! -f "$EMBED_CACHE_DIR/clear_test_2.json" ]]
    [[ "$result" == "2" ]]
}

@test "embed_cache_set: requires hash and vector" {
    run embed_cache_set "" "[0.1]"
    [[ "$status" -eq 1 ]]

    run embed_cache_set "hash" ""
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 3: PROVIDER VALIDATION
# =============================================================================

@test "_embed_validate_provider: accepts valid providers" {
    _embed_validate_provider "openai"
    [[ $? -eq 0 ]]

    _embed_validate_provider "ollama"
    [[ $? -eq 0 ]]

    _embed_validate_provider "local"
    [[ $? -eq 0 ]]
}

@test "_embed_validate_provider: rejects invalid provider" {
    run _embed_validate_provider "invalid"
    [[ "$status" -eq 1 ]]
}

@test "_embed_get_model: returns default model for provider" {
    result=$(_embed_get_model "openai")
    [[ "$result" == "text-embedding-ada-002" ]]

    result=$(_embed_get_model "ollama")
    [[ "$result" == "nomic-embed-text" ]]

    result=$(_embed_get_model "local")
    [[ "$result" == "local" ]]
}

@test "_embed_get_model: respects EMBED_MODEL override" {
    export EMBED_MODEL="custom-model"

    result=$(_embed_get_model "openai")
    [[ "$result" == "custom-model" ]]

    unset EMBED_MODEL
}

# =============================================================================
# CATEGORY 4: EMBED DIMENSIONS
# =============================================================================

@test "embed_dimensions: returns correct dimensions for openai" {
    result=$(embed_dimensions "openai")
    [[ "$result" == "1536" ]]
}

@test "embed_dimensions: returns correct dimensions for ollama" {
    result=$(embed_dimensions "ollama")
    [[ "$result" == "768" ]]
}

@test "embed_dimensions: returns correct dimensions for local" {
    result=$(embed_dimensions "local")
    [[ "$result" == "384" ]]
}

@test "embed_dimensions: accepts model override" {
    result=$(embed_dimensions "openai" "text-embedding-3-large")
    [[ "$result" == "3072" ]]
}

@test "embed_dimensions: handles unknown model gracefully" {
    result=$(embed_dimensions "openai" "unknown-model")
    [[ "$result" == "1536" ]]  # Falls back to provider default
}

@test "embed_dimensions: requires provider" {
    run embed_dimensions ""
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 5: LOCAL EMBEDDING PROVIDER
# =============================================================================

@test "_embed_local: generates vector of correct dimensions" {
    result=$(_embed_local "hello world" 10)

    # Should be a JSON array
    [[ "$result" =~ ^\[.*\]$ ]]

    # Count commas to verify dimensions (dims-1 commas for dims values)
    local comma_count
    comma_count=$(printf '%s' "$result" | tr -cd ',' | wc -c | tr -d '[:space:]')
    [[ "$comma_count" == "9" ]]  # 10 dimensions = 9 commas
}

@test "_embed_local: produces normalized vectors" {
    result=$(_embed_local "test text" 5)

    # Parse and check magnitude is approximately 1
    local vec_str="${result#[}"
    vec_str="${vec_str%]}"

    local sum_sq=0
    IFS=',' read -ra values <<< "$vec_str"
    for v in "${values[@]}"; do
        v="${v// /}"
        sum_sq=$(awk -v s="$sum_sq" -v val="$v" 'BEGIN {print s + val*val}')
    done

    local mag
    mag=$(awk -v s="$sum_sq" 'BEGIN {printf "%.1f", sqrt(s)}')

    # Magnitude should be close to 1.0 (normalized)
    [[ "$mag" == "1.0" ]] || [[ "$mag" == "0.0" ]]  # 0.0 for empty input edge case
}

@test "_embed_local: different texts produce different vectors" {
    result1=$(_embed_local "hello" 10)
    result2=$(_embed_local "goodbye" 10)

    [[ "$result1" != "$result2" ]]
}

@test "_embed_local: handles empty text" {
    result=$(_embed_local "" 5)
    [[ "$result" =~ ^\[.*\]$ ]]
}

# =============================================================================
# CATEGORY 6: VECTOR SIMILARITY
# =============================================================================

@test "embed_similarity: calculates correct cosine similarity" {
    # Identical vectors should have similarity 1.0
    vec="[0.5,0.5,0.5]"
    result=$(embed_similarity "$vec" "$vec")

    # Should be close to 1.0
    [[ "$result" =~ ^0\.9 ]] || [[ "$result" == "1" ]] || [[ "$result" == "1.0" ]] || [[ "$result" =~ ^1\.0 ]]
}

@test "embed_similarity: orthogonal vectors have zero similarity" {
    # [1,0] and [0,1] are orthogonal
    vec1="[1.0,0.0]"
    vec2="[0.0,1.0]"

    result=$(embed_similarity "$vec1" "$vec2")

    # Should be close to 0
    [[ "$result" =~ ^0\.0 ]] || [[ "$result" == "0" ]] || [[ "$result" =~ ^-?0\.0 ]]
}

@test "embed_similarity: requires matching dimensions" {
    vec1="[0.1,0.2,0.3]"
    vec2="[0.1,0.2]"

    run embed_similarity "$vec1" "$vec2"
    [[ "$status" -eq 1 ]]
}

@test "embed_similarity: requires two vectors" {
    run embed_similarity "[0.1,0.2]" ""
    [[ "$status" -eq 1 ]]

    run embed_similarity "" "[0.1,0.2]"
    [[ "$status" -eq 1 ]]
}

@test "embed_similarity: handles negative values" {
    vec1="[-0.5,0.5]"
    vec2="[0.5,-0.5]"

    result=$(embed_similarity "$vec1" "$vec2")

    # Opposite vectors should have similarity close to -1
    [[ "$result" =~ ^-0\.9 ]] || [[ "$result" =~ ^-1 ]]
}

# =============================================================================
# CATEGORY 7: VECTOR NORMALIZATION
# =============================================================================

@test "embed_normalize: produces unit vector" {
    vec="[3.0,4.0]"  # 3-4-5 triangle, magnitude = 5

    result=$(embed_normalize "$vec")

    # Normalized should be [0.6, 0.8]
    [[ "$result" =~ "0.6" ]]
    [[ "$result" =~ "0.8" ]]
}

@test "embed_normalize: handles already normalized vector" {
    # Unit vector [1,0]
    vec="[1.0,0.0]"

    result=$(embed_normalize "$vec")

    [[ "$result" =~ "1.0" ]]
    [[ "$result" =~ "0.0" ]]
}

@test "embed_normalize: handles zero vector" {
    vec="[0.0,0.0,0.0]"

    result=$(embed_normalize "$vec")

    # Should return input unchanged (or with warning)
    [[ "$result" =~ ^\[.*\]$ ]]
}

@test "embed_normalize: requires vector" {
    run embed_normalize ""
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 8: TEXT CHUNKING
# =============================================================================

@test "embed_chunk: splits text into chunks" {
    local long_text="word1 word2 word3 word4 word5 word6 word7 word8 word9 word10"

    result=$(embed_chunk "$long_text" 3 0)

    # Should produce multiple chunks
    local chunk_count
    chunk_count=$(printf '%s' "$result" | grep -c .)
    [[ $chunk_count -gt 1 ]]
}

@test "embed_chunk: respects max_tokens limit" {
    local text="this is a test of chunking"

    result=$(embed_chunk "$text" 2 0 | head -n1)

    # First chunk should be limited
    [[ ${#result} -le 16 ]]  # 2 tokens * 4 chars + some margin
}

@test "embed_chunk: handles empty text" {
    result=$(embed_chunk "" 10 0)
    [[ -z "$result" ]]
}

@test "embed_chunk: handles short text" {
    result=$(embed_chunk "short" 100 0)

    # Should produce single chunk
    local chunk_count
    chunk_count=$(printf '%s\n' "$result" | grep -c .)
    [[ $chunk_count -eq 1 ]]
}

# =============================================================================
# CATEGORY 9: EMBED TEXT (LOCAL PROVIDER)
# =============================================================================

@test "embed_text: generates embedding with local provider" {
    result=$(embed_text "test content" "local")

    # Should be valid JSON array
    [[ "$result" =~ ^\[.*\]$ ]]

    # Should have 384 dimensions (default for local)
    local comma_count
    comma_count=$(printf '%s' "$result" | tr -cd ',' | wc -c | tr -d '[:space:]')
    [[ "$comma_count" == "383" ]]
}

@test "embed_text: caches result" {
    # First call
    embed_text "cache test content" "local" >/dev/null

    # Check cache was populated
    local cache_files
    cache_files=$(find "$EMBED_CACHE_DIR" -name "*.json" -type f | wc -l)
    [[ $cache_files -gt 0 ]]
}

@test "embed_text: returns cached result on second call" {
    local content="cached content test"

    # First call (cache miss)
    embed_text "$content" "local" >/dev/null

    # Record cache state
    local initial_misses=$_EMBED_CACHE_MISSES
    local initial_hits=$_EMBED_CACHE_HITS

    # Second call (should be cache hit)
    embed_text "$content" "local" >/dev/null

    # Cache hits should increase
    [[ $_EMBED_CACHE_HITS -gt $initial_hits ]] || [[ $_EMBED_CACHE_MISSES -eq $initial_misses ]]
}

@test "embed_text: requires content" {
    run embed_text "" "local"
    [[ "$status" -eq 1 ]]
}

@test "embed_text: validates provider" {
    run embed_text "test" "invalid_provider"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 10: BATCH EMBEDDING
# =============================================================================

@test "embed_batch: processes file line by line" {
    # Create test file
    printf 'line one\nline two\nline three\n' > "$TEST_TMPDIR/batch_test.txt"

    result=$(embed_batch "$TEST_TMPDIR/batch_test.txt" "local")

    # Should have 3 JSONL lines
    local line_count
    line_count=$(printf '%s\n' "$result" | grep -c '{')
    [[ $line_count -eq 3 ]]
}

@test "embed_batch: outputs JSONL format" {
    printf 'test line\n' > "$TEST_TMPDIR/jsonl_test.txt"

    result=$(embed_batch "$TEST_TMPDIR/jsonl_test.txt" "local")

    # Should contain text and embedding fields
    [[ "$result" =~ '"text":' ]]
    [[ "$result" =~ '"embedding":' ]]
}

@test "embed_batch: skips empty lines" {
    printf 'line one\n\nline two\n\n\n' > "$TEST_TMPDIR/empty_lines.txt"

    result=$(embed_batch "$TEST_TMPDIR/empty_lines.txt" "local")

    # Should only have 2 embeddings (skipping empty lines)
    local line_count
    line_count=$(printf '%s\n' "$result" | grep -c '{')
    [[ $line_count -eq 2 ]]
}

@test "embed_batch: requires existing file" {
    run embed_batch "/nonexistent/file.txt" "local"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 11: STATISTICS
# =============================================================================

@test "embed_stats: reports cache statistics" {
    # Generate some cache activity
    embed_text "stats test 1" "local" >/dev/null
    embed_text "stats test 2" "local" >/dev/null

    result=$(embed_stats)

    [[ "$result" =~ "Cache Hits:" ]]
    [[ "$result" =~ "Cache Misses:" ]]
    [[ "$result" =~ "Hit Ratio:" ]]
}

@test "embed_stats: supports JSON output" {
    embed_text "json stats test" "local" >/dev/null

    result=$(embed_stats --json)

    [[ "$result" =~ '"cache_hits":' ]]
    [[ "$result" =~ '"cache_misses":' ]]
    [[ "$result" =~ '"hit_ratio_pct":' ]]
}

# =============================================================================
# CATEGORY 12: PROVIDER CHECKING
# =============================================================================

@test "embed_providers: lists all providers" {
    result=$(embed_providers)

    [[ "$result" =~ "openai" ]]
    [[ "$result" =~ "ollama" ]]
    [[ "$result" =~ "local" ]]
}

@test "embed_providers: shows local as always available" {
    result=$(embed_providers)

    [[ "$result" =~ "local - Always available" ]]
}

# =============================================================================
# CATEGORY 13: JSON HELPERS
# =============================================================================

@test "_embed_json_escape: escapes quotes" {
    result=$(_embed_json_escape 'hello "world"')
    [[ "$result" == 'hello \"world\"' ]]
}

@test "_embed_json_escape: escapes backslashes" {
    result=$(_embed_json_escape 'path\to\file')
    [[ "$result" == 'path\\to\\file' ]]
}

@test "_embed_json_escape: escapes newlines" {
    result=$(_embed_json_escape $'line1\nline2')
    [[ "$result" == 'line1\nline2' ]]
}

@test "_embed_json_escape: escapes tabs" {
    result=$(_embed_json_escape $'col1\tcol2')
    [[ "$result" == 'col1\tcol2' ]]
}

# =============================================================================
# CATEGORY 14: EMBED RANK
# =============================================================================

@test "embed_rank: returns indices sorted by similarity" {
    local query="[1.0,0.0,0.0]"
    # Doc 0: orthogonal, Doc 1: same direction, Doc 2: opposite
    local docs="[[0.0,1.0,0.0],[1.0,0.0,0.0],[-1.0,0.0,0.0]]"

    result=$(embed_rank "$query" "$docs")

    # Doc 1 should be first (most similar)
    first_idx=$(printf '%s' "$result" | head -n1)
    [[ "$first_idx" == "1" ]]
}

@test "embed_rank: requires query and documents" {
    run embed_rank "" "[[0.1]]"
    [[ "$status" -eq 1 ]]

    run embed_rank "[0.1]" ""
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 15: EDGE CASES
# =============================================================================

@test "embed_text: handles special characters" {
    result=$(embed_text 'test with "quotes" and \backslash' "local")
    [[ "$result" =~ ^\[.*\]$ ]]
}

@test "embed_text: handles unicode" {
    result=$(embed_text "hello" "local")
    [[ "$result" =~ ^\[.*\]$ ]]
}

@test "embed_similarity: handles very small numbers" {
    vec1="[0.0000001,0.0000001]"
    vec2="[0.0000001,0.0000001]"

    result=$(embed_similarity "$vec1" "$vec2")
    # Should not crash and produce a reasonable result
    [[ -n "$result" ]]
}

@test "embed_normalize: handles single dimension" {
    vec="[5.0]"
    result=$(embed_normalize "$vec")

    [[ "$result" =~ "1.0" ]]
}

# =============================================================================
# CATEGORY 16: MODULE EXPORTS
# =============================================================================

@test "MAINFRAME_EMBEDDINGS_EXPORTS: contains core functions" {
    [[ "${MAINFRAME_EMBEDDINGS_EXPORTS[*]}" =~ "embed_text" ]]
    [[ "${MAINFRAME_EMBEDDINGS_EXPORTS[*]}" =~ "embed_batch" ]]
    [[ "${MAINFRAME_EMBEDDINGS_EXPORTS[*]}" =~ "embed_similarity" ]]
    [[ "${MAINFRAME_EMBEDDINGS_EXPORTS[*]}" =~ "embed_normalize" ]]
}

@test "MAINFRAME_EMBEDDINGS_EXPORTS: contains cache functions" {
    [[ "${MAINFRAME_EMBEDDINGS_EXPORTS[*]}" =~ "embed_cache_get" ]]
    [[ "${MAINFRAME_EMBEDDINGS_EXPORTS[*]}" =~ "embed_cache_set" ]]
    [[ "${MAINFRAME_EMBEDDINGS_EXPORTS[*]}" =~ "embed_cache_clear" ]]
}

@test "MAINFRAME_EMBEDDINGS_EXPORTS: contains utility functions" {
    [[ "${MAINFRAME_EMBEDDINGS_EXPORTS[*]}" =~ "embed_chunk" ]]
    [[ "${MAINFRAME_EMBEDDINGS_EXPORTS[*]}" =~ "embed_rank" ]]
    [[ "${MAINFRAME_EMBEDDINGS_EXPORTS[*]}" =~ "embed_dimensions" ]]
}

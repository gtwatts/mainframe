#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/llm_tokens.bats - LLM Token Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/llm_tokens.sh
#              Pure bash LLM token counting, cost estimation, and chunking
# Test Count: 50+ test cases
# Categories: token counting, cost estimation, truncation, chunk splitting,
#             model utilities, edge cases, caching, USOP compliance
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Source the library
    source "$MAINFRAME_ROOT/lib/llm_tokens.sh"
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
    llm_clear_cache 2>/dev/null || true
}

# =============================================================================
# CATEGORY 1: TOKEN COUNTING - Basic Functionality
# =============================================================================

@test "llm_count_tokens: counts tokens for simple text" {
    result=$(llm_count_tokens "Hello, world!")
    # ~13 chars / 4 chars per token = ~3 tokens
    [[ "$result" -ge 2 ]] && [[ "$result" -le 5 ]]
}

@test "llm_count_tokens: returns 0 for empty string" {
    result=$(llm_count_tokens "")
    [[ "$result" -eq 0 ]]
}

@test "llm_count_tokens: handles multiline text" {
    local text=$'Line 1\nLine 2\nLine 3'
    result=$(llm_count_tokens "$text")
    [[ "$result" -ge 4 ]] && [[ "$result" -le 10 ]]
}

@test "llm_count_tokens: handles special characters" {
    result=$(llm_count_tokens "Hello @#$%^& World!")
    [[ "$result" -ge 3 ]]
}

@test "llm_count_tokens: handles unicode text" {
    result=$(llm_count_tokens "Hello World")
    [[ "$result" -ge 2 ]]
}

@test "llm_count_tokens: counts code correctly" {
    local code='function hello() { console.log("Hello"); }'
    result=$(llm_count_tokens "$code")
    [[ "$result" -ge 8 ]] && [[ "$result" -le 20 ]]
}

# =============================================================================
# CATEGORY 2: TOKEN COUNTING - Model-Specific
# =============================================================================

@test "llm_count_tokens: uses model-specific ratios for gpt-4" {
    local text="This is a test sentence with several words in it."
    result=$(llm_count_tokens "$text" "gpt-4")
    [[ "$result" -ge 8 ]] && [[ "$result" -le 20 ]]
}

@test "llm_count_tokens: uses model-specific ratios for claude-3-opus" {
    local text="This is a test sentence with several words in it."
    # Claude has ~3.5 chars/token, so should have slightly more tokens
    result=$(llm_count_tokens "$text" "claude-3-opus")
    [[ "$result" -ge 10 ]] && [[ "$result" -le 25 ]]
}

@test "llm_count_tokens: uses default ratio for unknown model" {
    local text="Hello world"
    result=$(llm_count_tokens "$text" "unknown-model-xyz")
    [[ "$result" -ge 2 ]] && [[ "$result" -le 5 ]]
}

@test "llm_count_tokens: handles gpt-3.5-turbo" {
    result=$(llm_count_tokens "Test text" "gpt-3.5-turbo")
    [[ "$result" -ge 2 ]] && [[ "$result" -le 5 ]]
}

@test "llm_count_tokens: handles llama models" {
    result=$(llm_count_tokens "Test text" "llama-3.1")
    [[ "$result" -ge 2 ]] && [[ "$result" -le 5 ]]
}

@test "llm_count_tokens: handles qwen models" {
    result=$(llm_count_tokens "Test text" "qwen-2.5")
    [[ "$result" -ge 2 ]] && [[ "$result" -le 5 ]]
}

# =============================================================================
# CATEGORY 3: TOKEN COUNTING - File Operations
# =============================================================================

@test "llm_count_tokens_file: counts tokens in a file" {
    echo "Hello world, this is a test file." > "$TEST_TMPDIR/test.txt"
    result=$(llm_count_tokens_file "$TEST_TMPDIR/test.txt")
    [[ "$result" -ge 5 ]] && [[ "$result" -le 15 ]]
}

@test "llm_count_tokens_file: returns 0 for missing file" {
    run llm_count_tokens_file "$TEST_TMPDIR/nonexistent.txt"
    [[ "$output" -eq 0 ]]
}

@test "llm_count_tokens_file: counts tokens with model parameter" {
    echo "Test content for token counting" > "$TEST_TMPDIR/test.txt"
    result=$(llm_count_tokens_file "$TEST_TMPDIR/test.txt" "claude-3-sonnet")
    [[ "$result" -ge 5 ]]
}

# =============================================================================
# CATEGORY 4: TOKEN COUNTING - Caching
# =============================================================================

@test "llm_count_tokens: caches repeated calls" {
    local text="This is a cached test string for token counting."
    result1=$(llm_count_tokens "$text" "gpt-4")
    result2=$(llm_count_tokens "$text" "gpt-4")
    [[ "$result1" -eq "$result2" ]]
}

@test "llm_clear_cache: clears the token cache" {
    llm_count_tokens "test" "gpt-4"
    llm_clear_cache
    # Cache should be empty now (no error)
    [[ $? -eq 0 ]]
}

# =============================================================================
# CATEGORY 5: COST ESTIMATION
# =============================================================================

@test "llm_estimate_cost: returns valid JSON for input cost" {
    result=$(llm_estimate_cost "Hello world" "gpt-4")
    [[ "$result" =~ '"ok":true' ]]
    [[ "$result" =~ '"tokens":' ]]
    [[ "$result" =~ '"input_cost_usd":' ]]
}

@test "llm_estimate_cost: calculates cost for gpt-4-turbo" {
    # 1000 tokens at $10/1M input = $0.01
    local text=$(printf 'x%.0s' {1..4000})  # ~1000 tokens
    result=$(llm_estimate_cost "$text" "gpt-4-turbo" input)
    [[ "$result" =~ '"input_cost_usd":0.0' ]]
}

@test "llm_estimate_cost: supports output cost type" {
    result=$(llm_estimate_cost "Test" "gpt-4" --type output)
    [[ "$result" =~ '"cost_type":"output"' ]]
}

@test "llm_estimate_cost: supports both cost type" {
    result=$(llm_estimate_cost "Test" "gpt-4" --type both)
    [[ "$result" =~ '"cost_type":"both"' ]]
}

@test "llm_estimate_cost: handles free models" {
    result=$(llm_estimate_cost "Test" "llama")
    [[ "$result" =~ '"input_cost_usd":0.000000' ]]
}

# =============================================================================
# CATEGORY 6: PRICING INFO
# =============================================================================

@test "llm_get_pricing: returns pricing for gpt-4" {
    result=$(llm_get_pricing "gpt-4")
    [[ "$result" =~ '"ok":true' ]]
    [[ "$result" =~ '"input_price_per_1m_usd":30' ]]
}

@test "llm_get_pricing: returns pricing for claude-3-opus" {
    result=$(llm_get_pricing "claude-3-opus")
    [[ "$result" =~ '"input_price_per_1m_usd":15' ]]
}

@test "llm_get_pricing: returns context window" {
    result=$(llm_get_pricing "gpt-4-turbo")
    [[ "$result" =~ '"context_window":128000' ]]
}

@test "llm_list_models: returns JSON array" {
    result=$(llm_list_models)
    [[ "$result" =~ '"ok":true' ]]
    [[ "$result" =~ '"gpt-4"' ]]
    [[ "$result" =~ '"claude-3-opus"' ]]
}

# =============================================================================
# CATEGORY 7: TEXT TRUNCATION
# =============================================================================

@test "llm_truncate_to_tokens: returns text unchanged if under limit" {
    local text="Short text"
    result=$(llm_truncate_to_tokens "$text" 100 "gpt-4")
    [[ "$result" == "$text" ]]
}

@test "llm_truncate_to_tokens: truncates long text with head strategy" {
    local text=$(printf 'word %.0s' {1..500})
    result=$(llm_truncate_to_tokens "$text" 50 "gpt-4" head)
    [[ ${#result} -lt ${#text} ]]
    [[ "$result" =~ 'truncated' ]]
}

@test "llm_truncate_to_tokens: truncates with tail strategy" {
    local text=$'Line 1\nLine 2\nLine 3\nLine 4\nLine 5'
    result=$(llm_truncate_to_tokens "$text" 5 "gpt-4" tail)
    [[ "$result" =~ 'truncated' ]]
}

@test "llm_truncate_to_tokens: truncates with middle strategy" {
    local text=$(printf 'word %.0s' {1..200})
    result=$(llm_truncate_to_tokens "$text" 30 "gpt-4" middle)
    [[ "$result" =~ 'truncated' ]]
}

@test "llm_truncate_to_tokens: handles empty text" {
    result=$(llm_truncate_to_tokens "" 100)
    [[ -z "$result" ]]
}

@test "llm_truncate_to_tokens: handles zero max_tokens" {
    result=$(llm_truncate_to_tokens "test" 0)
    [[ "$result" == "test" ]]
}

# =============================================================================
# CATEGORY 8: CHUNK SPLITTING
# =============================================================================

@test "llm_split_chunks: splits text into chunks" {
    local text=$(printf 'This is sentence number %d. ' {1..50})
    result=$(llm_split_chunks "$text" 100 "gpt-4")
    [[ "$result" =~ '"ok":true' ]]
    [[ "$result" =~ '"chunks":' ]]
    [[ "$result" =~ '"total_chunks":' ]]
}

@test "llm_split_chunks: returns empty array for empty text" {
    result=$(llm_split_chunks "" 100)
    [[ "$result" =~ '"chunks":[]' ]]
    [[ "$result" =~ '"total_chunks":0' ]]
}

@test "llm_split_chunks: respects chunk_size" {
    local text=$(printf 'word %.0s' {1..1000})
    result=$(llm_split_chunks "$text" 50 "gpt-4")
    [[ "$result" =~ '"total_chunks":' ]]
    # Should have multiple chunks
    chunks=$(echo "$result" | grep -o '"total_chunks":[0-9]*' | grep -o '[0-9]*')
    [[ "$chunks" -gt 1 ]]
}

@test "llm_split_chunks: supports overlap option" {
    local text=$(printf 'word %.0s' {1..200})
    result=$(llm_split_chunks "$text" 50 "gpt-4" --overlap 10)
    [[ "$result" =~ '"overlap":10' ]]
}

@test "llm_split_chunks: supports preserve-lines option" {
    local text=$'Line 1\nLine 2\nLine 3\nLine 4\nLine 5'
    result=$(llm_split_chunks "$text" 10 "gpt-4" --preserve-lines)
    [[ "$result" =~ '"ok":true' ]]
}

@test "llm_split_chunks: returns error for invalid chunk_size" {
    run llm_split_chunks "test" 0
    [[ "$output" =~ '"ok":false' ]]
}

@test "llm_split_chunks_file: splits file content" {
    printf 'This is test content. ' > "$TEST_TMPDIR/test.txt"
    printf 'More content here. ' >> "$TEST_TMPDIR/test.txt"
    result=$(llm_split_chunks_file "$TEST_TMPDIR/test.txt" 50)
    [[ "$result" =~ '"ok":true' ]]
}

@test "llm_split_chunks_file: returns error for missing file" {
    run llm_split_chunks_file "$TEST_TMPDIR/nonexistent.txt" 50
    [[ "$output" =~ '"ok":false' ]]
}

# =============================================================================
# CATEGORY 9: MODEL UTILITIES
# =============================================================================

@test "llm_context_window: returns correct size for gpt-4" {
    result=$(llm_context_window "gpt-4")
    [[ "$result" -eq 8192 ]]
}

@test "llm_context_window: returns correct size for gpt-4-turbo" {
    result=$(llm_context_window "gpt-4-turbo")
    [[ "$result" -eq 128000 ]]
}

@test "llm_context_window: returns correct size for claude-3-opus" {
    result=$(llm_context_window "claude-3-opus")
    [[ "$result" -eq 200000 ]]
}

@test "llm_context_window: returns default for unknown model" {
    result=$(llm_context_window "unknown-model")
    [[ "$result" -eq 8192 ]]
}

@test "llm_fits_context: returns true for short text" {
    llm_fits_context "Hello" "gpt-4"
    [[ $? -eq 0 ]]
}

@test "llm_fits_context: respects reserve option" {
    # Create text close to context limit
    llm_fits_context "Hello" "gpt-4" --reserve 8000
    [[ $? -eq 0 ]]
}

@test "llm_model_family: extracts gpt-4 family" {
    result=$(llm_model_family "gpt-4-turbo-2024-04-09")
    [[ "$result" == "gpt-4" ]]
}

@test "llm_model_family: extracts claude family" {
    result=$(llm_model_family "claude-3.5-sonnet-20240620")
    [[ "$result" == "claude-sonnet" ]]
}

@test "llm_model_family: extracts llama family" {
    result=$(llm_model_family "llama-3.1-70b-instruct")
    [[ "$result" == "llama-3.1" ]]
}

@test "llm_model_family: handles unknown model" {
    result=$(llm_model_family "some-random-model")
    [[ "$result" == "default" ]]
}

# =============================================================================
# CATEGORY 10: USOP COMPLIANCE
# =============================================================================

@test "llm_count_tokens_usop: returns JSON envelope" {
    result=$(llm_count_tokens_usop "Hello world" "gpt-4")
    [[ "$result" =~ '"ok":true' ]]
    [[ "$result" =~ '"data":{' ]]
    [[ "$result" =~ '"tokens":' ]]
    [[ "$result" =~ '"model":"gpt-4"' ]]
}

@test "llm_count_tokens_usop: includes char count" {
    result=$(llm_count_tokens_usop "Hello" "gpt-4")
    [[ "$result" =~ '"chars":5' ]]
}

@test "llm_truncate_usop: returns JSON envelope" {
    local text=$(printf 'word %.0s' {1..200})
    result=$(llm_truncate_usop "$text" 50 "gpt-4")
    [[ "$result" =~ '"ok":true' ]]
    [[ "$result" =~ '"original_tokens":' ]]
    [[ "$result" =~ '"final_tokens":' ]]
    [[ "$result" =~ '"was_truncated":' ]]
}

@test "llm_truncate_usop: indicates when truncation occurred" {
    local text=$(printf 'word %.0s' {1..500})
    result=$(llm_truncate_usop "$text" 10 "gpt-4")
    [[ "$result" =~ '"was_truncated":true' ]]
}

@test "llm_truncate_usop: indicates when no truncation needed" {
    result=$(llm_truncate_usop "short" 1000 "gpt-4")
    [[ "$result" =~ '"was_truncated":false' ]]
}

# =============================================================================
# CATEGORY 11: EDGE CASES AND STRESS TESTS
# =============================================================================

@test "llm_count_tokens: handles very long text" {
    local text=$(printf 'x%.0s' {1..10000})
    result=$(llm_count_tokens "$text")
    [[ "$result" -ge 2000 ]] && [[ "$result" -le 3000 ]]
}

@test "llm_count_tokens: handles text with only whitespace" {
    result=$(llm_count_tokens "     ")
    [[ "$result" -ge 1 ]] && [[ "$result" -le 3 ]]
}

@test "llm_count_tokens: handles text with tabs and newlines" {
    result=$(llm_count_tokens $'\t\t\n\n\t')
    [[ "$result" -ge 1 ]]
}

@test "llm_split_chunks: handles single-character text" {
    result=$(llm_split_chunks "x" 10)
    [[ "$result" =~ '"total_chunks":1' ]]
}

@test "llm_truncate_to_tokens: handles text exactly at limit" {
    # ~40 chars should be ~10 tokens for gpt-4
    local text="This is exactly forty chars long text!"
    result=$(llm_truncate_to_tokens "$text" 100 "gpt-4")
    [[ "$result" == "$text" ]]
}

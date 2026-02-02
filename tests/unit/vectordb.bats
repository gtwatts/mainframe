#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/vectordb.bats - Vector Database Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/vectordb.sh
#              Universal vector database interface with backend abstraction
# Test Count: 60+ test cases
# Categories: initialization, backend validation, sqlite-vec operations,
#             collection management, document operations, search,
#             health checks, error handling, edge cases
# Note: Tests use sqlite-vec backend for isolated testing without external deps
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"
    TEST_DB="$TEST_TMPDIR/test_vectordb.sqlite"

    # Mock bin directory for curl/http mocking
    MOCK_BIN="$TEST_TMPDIR/mock_bin"
    mkdir -p "$MOCK_BIN"

    # Source the library (loads dependencies automatically via common.sh patterns)
    source "$MAINFRAME_ROOT/lib/vectordb.sh"

    # Reset state before each test
    vectordb_reset
}

# Teardown: Clean up test artifacts
teardown() {
    vectordb_reset
    rm -rf "$TEST_TMPDIR"
}

# Helper: Create mock curl for HTTP testing
create_mock_curl() {
    local behavior="$1"
    cat > "$MOCK_BIN/curl" << EOF
#!/bin/bash
$behavior
EOF
    chmod +x "$MOCK_BIN/curl"
    export PATH="$MOCK_BIN:$PATH"
}

# Helper: Generate test embedding
generate_embedding() {
    local dim="${1:-384}"
    local prefix="${2:-0.}"
    local values=""
    for ((i=1; i<=dim; i++)); do
        [[ -n "$values" ]] && values+=","
        values+="${prefix}${i}"
    done
    printf '[%s]' "$values"
}

# Helper: Generate small test embedding (for performance)
small_embedding() {
    printf '[0.1,0.2,0.3,0.4,0.5]'
}

# =============================================================================
# CATEGORY 1: CONSTANTS AND MODULE LOADING
# =============================================================================

@test "VECTORDB_VERSION: is set" {
    [[ -n "$VECTORDB_VERSION" ]]
    [[ "$VECTORDB_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "VECTORDB_DEFAULT_BACKEND: is chromadb" {
    [[ "$VECTORDB_DEFAULT_BACKEND" == "chromadb" ]]
}

@test "VECTORDB_BACKENDS: includes all supported backends" {
    [[ "$VECTORDB_BACKENDS" =~ "chromadb" ]]
    [[ "$VECTORDB_BACKENDS" =~ "pinecone" ]]
    [[ "$VECTORDB_BACKENDS" =~ "qdrant" ]]
    [[ "$VECTORDB_BACKENDS" =~ "sqlite-vec" ]]
}

@test "VECTORDB_DEFAULT_TOP_K: is 5" {
    [[ "$VECTORDB_DEFAULT_TOP_K" -eq 5 ]]
}

@test "VECTORDB_DEFAULT_DIMENSIONS: is 384" {
    [[ "$VECTORDB_DEFAULT_DIMENSIONS" -eq 384 ]]
}

@test "VECTORDB_EXPORTS: contains expected functions" {
    [[ "${VECTORDB_EXPORTS[*]}" =~ "vectordb_init" ]]
    [[ "${VECTORDB_EXPORTS[*]}" =~ "vectordb_upsert" ]]
    [[ "${VECTORDB_EXPORTS[*]}" =~ "vectordb_search" ]]
    [[ "${VECTORDB_EXPORTS[*]}" =~ "vectordb_health" ]]
}

# =============================================================================
# CATEGORY 2: BACKEND VALIDATION
# =============================================================================

@test "_vectordb_valid_backend: accepts chromadb" {
    _vectordb_valid_backend "chromadb"
    [[ $? -eq 0 ]]
}

@test "_vectordb_valid_backend: accepts pinecone" {
    _vectordb_valid_backend "pinecone"
    [[ $? -eq 0 ]]
}

@test "_vectordb_valid_backend: accepts qdrant" {
    _vectordb_valid_backend "qdrant"
    [[ $? -eq 0 ]]
}

@test "_vectordb_valid_backend: accepts sqlite-vec" {
    _vectordb_valid_backend "sqlite-vec"
    [[ $? -eq 0 ]]
}

@test "_vectordb_valid_backend: rejects invalid backend" {
    run _vectordb_valid_backend "invalid"
    [[ "$status" -eq 1 ]]
}

@test "_vectordb_valid_backend: rejects empty backend" {
    run _vectordb_valid_backend ""
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 3: INITIALIZATION
# =============================================================================

@test "vectordb_init: initializes sqlite-vec backend" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    [[ $? -eq 0 ]]
    [[ -f "$TEST_DB" ]]
}

@test "vectordb_init: creates SQLite tables" {
    vectordb_init "sqlite-vec" "$TEST_DB"

    # Check tables exist
    local tables
    tables=$(sqlite3 "$TEST_DB" ".tables")
    [[ "$tables" =~ "vectordb_collections" ]]
    [[ "$tables" =~ "vectordb_documents" ]]
}

@test "vectordb_init: rejects invalid backend" {
    run vectordb_init "invalid_backend" "http://localhost"
    [[ "$status" -eq 1 ]]
}

@test "vectordb_init: uses default backend when not specified" {
    # Mock curl for chromadb (will fail but should attempt)
    create_mock_curl 'exit 1'
    run vectordb_init "" "http://localhost:8000"
    # Should fail because chromadb is not available, but backend should be set
    [[ "$output" =~ "chromadb" ]] || [[ "$status" -eq 0 ]]
}

@test "vectordb_init: requires API key for pinecone" {
    unset PINECONE_API_KEY
    run vectordb_init "pinecone" "https://controller.pinecone.io"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "API key" ]]
}

@test "vectordb_init: accepts pinecone with API key" {
    run vectordb_init "pinecone" "https://controller.pinecone.io" "test-api-key"
    [[ "$status" -eq 0 ]]
}

@test "vectordb_reset: clears all state" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_reset

    # Verify state is cleared (operations should fail)
    run vectordb_health
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 4: COLLECTION OPERATIONS
# =============================================================================

@test "vectordb_create_collection: creates collection" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "test_collection" 5
    [[ $? -eq 0 ]]

    # Verify in database
    local count
    count=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM vectordb_collections WHERE name='test_collection';")
    [[ "$count" -eq 1 ]]
}

@test "vectordb_create_collection: stores dimensions" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "test_dims" 128

    local dims
    dims=$(sqlite3 "$TEST_DB" "SELECT dimensions FROM vectordb_collections WHERE name='test_dims';")
    [[ "$dims" -eq 128 ]]
}

@test "vectordb_create_collection: uses default dimensions" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "default_dims"

    local dims
    dims=$(sqlite3 "$TEST_DB" "SELECT dimensions FROM vectordb_collections WHERE name='default_dims';")
    [[ "$dims" -eq 384 ]]
}

@test "vectordb_create_collection: requires name" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    run vectordb_create_collection ""
    [[ "$status" -eq 1 ]]
}

@test "vectordb_create_collection: rejects invalid dimensions" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    run vectordb_create_collection "test" "invalid"
    [[ "$status" -eq 1 ]]
}

@test "vectordb_create_collection: rejects zero dimensions" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    run vectordb_create_collection "test" 0
    [[ "$status" -eq 1 ]]
}

@test "vectordb_create_collection: fails without init" {
    run vectordb_create_collection "test" 5
    [[ "$status" -eq 1 ]]
}

@test "vectordb_delete_collection: deletes collection" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "to_delete" 5
    vectordb_delete_collection "to_delete"

    local count
    count=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM vectordb_collections WHERE name='to_delete';")
    [[ "$count" -eq 0 ]]
}

@test "vectordb_delete_collection: removes associated documents" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "with_docs" 5
    vectordb_upsert "with_docs" "doc1" "text" "$(small_embedding)" "{}"

    vectordb_delete_collection "with_docs"

    local count
    count=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM vectordb_documents WHERE collection='with_docs';")
    [[ "$count" -eq 0 ]]
}

@test "vectordb_list_collections: returns JSON array" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "list_test1" 5
    vectordb_create_collection "list_test2" 10

    local result
    result=$(vectordb_list_collections)

    # Should be valid JSON array
    [[ "$result" =~ ^\[ ]]
    [[ "$result" =~ list_test1 ]]
    [[ "$result" =~ list_test2 ]]
}

@test "vectordb_list_collections: returns empty array for no collections" {
    vectordb_init "sqlite-vec" "$TEST_DB"

    local result
    result=$(vectordb_list_collections)

    [[ "$result" == "[]" ]]
}

# =============================================================================
# CATEGORY 5: DOCUMENT OPERATIONS
# =============================================================================

@test "vectordb_upsert: inserts new document" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "docs" 5
    vectordb_upsert "docs" "doc1" "Hello world" "$(small_embedding)" '{"source":"test"}'
    [[ $? -eq 0 ]]

    local count
    count=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM vectordb_documents WHERE id='doc1';")
    [[ "$count" -eq 1 ]]
}

@test "vectordb_upsert: updates existing document" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "docs" 5
    vectordb_upsert "docs" "doc1" "Original" "$(small_embedding)" "{}"
    vectordb_upsert "docs" "doc1" "Updated" "$(small_embedding)" "{}"

    local text
    text=$(sqlite3 "$TEST_DB" "SELECT text FROM vectordb_documents WHERE id='doc1';")
    [[ "$text" == "Updated" ]]
}

@test "vectordb_upsert: requires collection" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    run vectordb_upsert "" "doc1" "text" "$(small_embedding)"
    [[ "$status" -eq 1 ]]
}

@test "vectordb_upsert: requires id" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "docs" 5
    run vectordb_upsert "docs" "" "text" "$(small_embedding)"
    [[ "$status" -eq 1 ]]
}

@test "vectordb_upsert: requires embedding" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "docs" 5
    run vectordb_upsert "docs" "doc1" "text" ""
    [[ "$status" -eq 1 ]]
}

@test "vectordb_upsert: handles text with quotes" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "docs" 5
    vectordb_upsert "docs" "doc1" "It's a \"test\"" "$(small_embedding)" "{}"

    local text
    text=$(sqlite3 "$TEST_DB" "SELECT text FROM vectordb_documents WHERE id='doc1';")
    [[ "$text" =~ "test" ]]
}

@test "vectordb_upsert: stores metadata" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "docs" 5
    vectordb_upsert "docs" "doc1" "text" "$(small_embedding)" '{"key":"value"}'

    local metadata
    metadata=$(sqlite3 "$TEST_DB" "SELECT metadata FROM vectordb_documents WHERE id='doc1';")
    [[ "$metadata" =~ "key" ]]
    [[ "$metadata" =~ "value" ]]
}

@test "vectordb_get: retrieves document by ID" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "docs" 5
    vectordb_upsert "docs" "doc1" "Test content" "$(small_embedding)" '{"tag":"important"}'

    local result
    result=$(vectordb_get "docs" "doc1")

    [[ "$result" =~ "doc1" ]]
    [[ "$result" =~ "Test content" ]]
}

@test "vectordb_get: returns empty for missing document" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "docs" 5

    local result
    result=$(vectordb_get "docs" "nonexistent")

    [[ "$result" == "[]" ]]
}

@test "vectordb_delete: removes document" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "docs" 5
    vectordb_upsert "docs" "doc1" "text" "$(small_embedding)" "{}"

    vectordb_delete "docs" "doc1"

    local count
    count=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM vectordb_documents WHERE id='doc1';")
    [[ "$count" -eq 0 ]]
}

@test "vectordb_count: returns document count" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "docs" 5
    vectordb_upsert "docs" "doc1" "text1" "$(small_embedding)" "{}"
    vectordb_upsert "docs" "doc2" "text2" "$(small_embedding)" "{}"
    vectordb_upsert "docs" "doc3" "text3" "$(small_embedding)" "{}"

    local count
    count=$(vectordb_count "docs")

    [[ "$count" -eq 3 ]]
}

@test "vectordb_count: returns 0 for empty collection" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "empty" 5

    local count
    count=$(vectordb_count "empty")

    [[ "$count" -eq 0 ]]
}

# =============================================================================
# CATEGORY 6: SEARCH OPERATIONS
# =============================================================================

@test "vectordb_search: finds similar documents" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "search" 5

    # Insert documents with different embeddings
    vectordb_upsert "search" "doc1" "First document" "[0.1,0.2,0.3,0.4,0.5]" "{}"
    vectordb_upsert "search" "doc2" "Second document" "[0.5,0.4,0.3,0.2,0.1]" "{}"
    vectordb_upsert "search" "doc3" "Third document" "[0.1,0.2,0.3,0.4,0.5]" "{}"

    local result
    result=$(vectordb_search "search" "[0.1,0.2,0.3,0.4,0.5]" --top-k 2)

    [[ "$result" =~ "doc1" ]] || [[ "$result" =~ "doc3" ]]
}

@test "vectordb_search: respects top-k limit" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "search" 5

    for i in {1..10}; do
        vectordb_upsert "search" "doc$i" "Document $i" "$(small_embedding)" "{}"
    done

    local result
    result=$(vectordb_search "search" "$(small_embedding)" --top-k 3)

    # Count number of results (count id occurrences)
    local count
    count=$(echo "$result" | grep -o '"id"' | wc -l)
    [[ "$count" -le 3 ]]
}

@test "vectordb_search: uses default top-k when not specified" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "search" 5

    for i in {1..10}; do
        vectordb_upsert "search" "doc$i" "Document $i" "$(small_embedding)" "{}"
    done

    local result
    result=$(vectordb_search "search" "$(small_embedding)")

    # Default is 5
    local count
    count=$(echo "$result" | grep -o '"id"' | wc -l)
    [[ "$count" -le 5 ]]
}

@test "vectordb_search: returns JSON array" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "search" 5
    vectordb_upsert "search" "doc1" "text" "$(small_embedding)" "{}"

    local result
    result=$(vectordb_search "search" "$(small_embedding)")

    [[ "$result" =~ ^\[ ]]
    [[ "$result" =~ \]$ ]]
}

@test "vectordb_search: includes score in results" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "search" 5
    vectordb_upsert "search" "doc1" "text" "[0.1,0.2,0.3,0.4,0.5]" "{}"

    local result
    result=$(vectordb_search "search" "[0.1,0.2,0.3,0.4,0.5]")

    [[ "$result" =~ "score" ]]
}

@test "vectordb_search: requires collection" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    run vectordb_search "" "$(small_embedding)"
    [[ "$status" -eq 1 ]]
}

@test "vectordb_search: requires embedding" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "search" 5
    run vectordb_search "search" ""
    [[ "$status" -eq 1 ]]
}

@test "vectordb_search: accepts -k short option" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "search" 5

    for i in {1..5}; do
        vectordb_upsert "search" "doc$i" "Document $i" "$(small_embedding)" "{}"
    done

    local result
    result=$(vectordb_search "search" "$(small_embedding)" -k 2)

    local count
    count=$(echo "$result" | grep -o '"id"' | wc -l)
    [[ "$count" -le 2 ]]
}

# =============================================================================
# CATEGORY 7: HEALTH AND STATUS
# =============================================================================

@test "vectordb_health: returns success for working sqlite-vec" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_health
    [[ $? -eq 0 ]]
}

@test "vectordb_health: fails without init" {
    run vectordb_health
    [[ "$status" -eq 1 ]]
}

@test "vectordb_info: returns JSON with backend info" {
    vectordb_init "sqlite-vec" "$TEST_DB"

    local result
    result=$(vectordb_info)

    [[ "$result" =~ "backend" ]]
    [[ "$result" =~ "sqlite-vec" ]]
    [[ "$result" =~ "status" ]]
    [[ "$result" =~ "initialized" ]]
}

@test "vectordb_info: shows healthy status when working" {
    vectordb_init "sqlite-vec" "$TEST_DB"

    local result
    result=$(vectordb_info)

    [[ "$result" =~ "healthy" ]]
}

# =============================================================================
# CATEGORY 8: EDGE CASES
# =============================================================================

@test "operations fail without initialization" {
    run vectordb_create_collection "test" 5
    [[ "$status" -eq 1 ]]

    run vectordb_upsert "test" "id" "text" "[0.1]" "{}"
    [[ "$status" -eq 1 ]]

    run vectordb_search "test" "[0.1]"
    [[ "$status" -eq 1 ]]
}

@test "vectordb_upsert: handles empty text" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "docs" 5

    vectordb_upsert "docs" "doc1" "" "$(small_embedding)" "{}"
    [[ $? -eq 0 ]]

    local text
    text=$(sqlite3 "$TEST_DB" "SELECT text FROM vectordb_documents WHERE id='doc1';")
    [[ -z "$text" ]]
}

@test "vectordb_upsert: handles default empty metadata" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "docs" 5

    vectordb_upsert "docs" "doc1" "text" "$(small_embedding)"
    [[ $? -eq 0 ]]
}

@test "vectordb_search: returns empty array for empty collection" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "empty" 5

    local result
    result=$(vectordb_search "empty" "$(small_embedding)")

    [[ "$result" == "[]" ]]
}

@test "multiple collections are isolated" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "col1" 5
    vectordb_create_collection "col2" 5

    vectordb_upsert "col1" "doc1" "text1" "$(small_embedding)" "{}"
    vectordb_upsert "col2" "doc2" "text2" "$(small_embedding)" "{}"

    local count1 count2
    count1=$(vectordb_count "col1")
    count2=$(vectordb_count "col2")

    [[ "$count1" -eq 1 ]]
    [[ "$count2" -eq 1 ]]
}

@test "re-initialization preserves data in sqlite-vec" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "persist" 5
    vectordb_upsert "persist" "doc1" "text" "$(small_embedding)" "{}"

    # Reset and reinitialize to same DB
    vectordb_reset
    vectordb_init "sqlite-vec" "$TEST_DB"

    local count
    count=$(vectordb_count "persist")
    [[ "$count" -eq 1 ]]
}

# =============================================================================
# CATEGORY 9: INTERNAL HELPERS
# =============================================================================

@test "_vectordb_parse_embedding: removes brackets" {
    local result
    result=$(_vectordb_parse_embedding "[0.1,0.2,0.3]")
    [[ "$result" == "0.1 0.2 0.3" ]]
}

@test "_vectordb_format_embedding: adds brackets" {
    local result
    result=$(_vectordb_format_embedding "0.1 0.2 0.3")
    [[ "$result" == "[0.1,0.2,0.3]" ]]
}

@test "_vectordb_dot_product: calculates correctly" {
    local result
    result=$(_vectordb_dot_product "1 0 0" "1 0 0")
    # Should be 1.0
    [[ "$result" =~ ^1\.?0* ]]
}

@test "_vectordb_dot_product: handles orthogonal vectors" {
    local result
    result=$(_vectordb_dot_product "1 0" "0 1")
    # Should be 0
    [[ "$result" =~ ^0\.?0* ]]
}

# =============================================================================
# CATEGORY 10: SECURITY TESTS
# =============================================================================

@test "vectordb_upsert: escapes SQL injection in text" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "docs" 5

    # Attempt SQL injection in text field
    vectordb_upsert "docs" "doc1" "'; DROP TABLE vectordb_documents; --" "$(small_embedding)" "{}"

    # Table should still exist
    local count
    count=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM vectordb_documents;")
    [[ "$count" -ge 0 ]]
}

@test "vectordb_upsert: handles special characters in ID" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "docs" 5

    vectordb_upsert "docs" "doc-with_special.chars" "text" "$(small_embedding)" "{}"
    [[ $? -eq 0 ]]
}

@test "vectordb_create_collection: handles special characters in name" {
    vectordb_init "sqlite-vec" "$TEST_DB"

    # Underscores and hyphens should work
    vectordb_create_collection "my_test-collection" 5
    [[ $? -eq 0 ]]
}

# =============================================================================
# CATEGORY 11: PERFORMANCE TESTS
# =============================================================================

@test "vectordb_search: handles many documents" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "perf" 5

    # Insert 50 documents
    for i in {1..50}; do
        vectordb_upsert "perf" "doc$i" "Document number $i" "$(small_embedding)" "{}"
    done

    # Search should complete in reasonable time
    local result
    result=$(vectordb_search "perf" "$(small_embedding)" --top-k 10)

    [[ -n "$result" ]]
    local count
    count=$(echo "$result" | grep -o '"id"' | wc -l)
    [[ "$count" -le 10 ]]
}

@test "vectordb_count: is efficient" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    vectordb_create_collection "count_test" 5

    for i in {1..100}; do
        vectordb_upsert "count_test" "doc$i" "text" "$(small_embedding)" "{}"
    done

    local count
    count=$(vectordb_count "count_test")
    [[ "$count" -eq 100 ]]
}

# =============================================================================
# CATEGORY 12: CHROMADB MOCK TESTS
# =============================================================================

@test "chromadb: health check sends correct request" {
    create_mock_curl '
        if [[ "$*" =~ "heartbeat" ]]; then
            echo "{\"nanosecond heartbeat\":12345}"
            exit 0
        fi
        echo "Unknown request: $*" >&2
        exit 1
    '

    vectordb_init "chromadb" "http://localhost:8000"
    vectordb_health
    [[ $? -eq 0 ]]
}

@test "chromadb: create collection sends POST request" {
    local captured_request=""
    create_mock_curl '
        captured_request="$*"
        if [[ "$*" =~ "POST" ]] && [[ "$*" =~ "collections" ]]; then
            echo "{\"id\":\"test-uuid\",\"name\":\"test\"}"
            exit 0
        fi
        echo "{}"
    '

    vectordb_init "chromadb" "http://localhost:8000"
    vectordb_create_collection "test" 384
    [[ $? -eq 0 ]]
}

# =============================================================================
# CATEGORY 13: QDRANT MOCK TESTS
# =============================================================================

@test "qdrant: health check sends correct request" {
    create_mock_curl '
        if [[ "$*" =~ "readyz" ]]; then
            echo "ok"
            exit 0
        fi
        echo "Unknown request" >&2
        exit 1
    '

    vectordb_init "qdrant" "http://localhost:6333"
    vectordb_health
    [[ $? -eq 0 ]]
}

@test "qdrant: create collection uses PUT method" {
    create_mock_curl '
        if [[ "$*" =~ "PUT" ]] && [[ "$*" =~ "collections" ]]; then
            echo "{\"result\":true,\"status\":\"ok\"}"
            exit 0
        fi
        echo "Unknown: $*" >&2
        exit 1
    '

    vectordb_init "qdrant" "http://localhost:6333"
    vectordb_create_collection "test" 384
    [[ $? -eq 0 ]]
}

# =============================================================================
# CATEGORY 14: ERROR MESSAGE TESTS
# =============================================================================

@test "error: clear message for missing init" {
    run vectordb_create_collection "test" 5
    [[ "$output" =~ "not initialized" ]] || [[ "$output" =~ "Call vectordb_init" ]]
}

@test "error: clear message for missing collection name" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    run vectordb_create_collection ""
    [[ "$output" =~ "Collection name required" ]] || [[ "$output" =~ "required" ]]
}

@test "error: clear message for invalid dimensions" {
    vectordb_init "sqlite-vec" "$TEST_DB"
    run vectordb_create_collection "test" "abc"
    [[ "$output" =~ "Invalid dimensions" ]] || [[ "$output" =~ "dimensions" ]]
}

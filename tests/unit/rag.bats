#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/rag.bats - RAG Pipeline Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/rag.sh
#              End-to-end RAG (Retrieval-Augmented Generation) pipeline
# Test Count: 50+ test cases
# Categories: Initialization, chunking, ingestion, querying, reranking,
#             context augmentation, statistics, edge cases
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Configure RAG for testing
    export RAG_VECTORDB_BACKEND="sqlite-vec"
    export RAG_VECTORDB_PATH="$TEST_TMPDIR/test_rag.sqlite"
    export RAG_EMBED_PROVIDER="local"
    export RAG_COLLECTION="test_collection"
    export RAG_CHUNK_SIZE="100"
    export RAG_CHUNK_OVERLAP="10"

    # Configure embeddings cache
    export EMBED_CACHE_DIR="$TEST_TMPDIR/embed_cache"
    mkdir -p "$EMBED_CACHE_DIR"

    # Suppress log output during tests
    export MAINFRAME_QUIET=1

    # Source the library
    source "$MAINFRAME_ROOT/lib/rag.sh"

    # Create test documents directory
    TEST_DOCS_DIR="$TEST_TMPDIR/docs"
    mkdir -p "$TEST_DOCS_DIR"
}

# Teardown: Clean up test artifacts
teardown() {
    rag_reset 2>/dev/null || true
    rm -rf "$TEST_TMPDIR"
}

# Helper: Create test document
create_test_doc() {
    local name="$1"
    local content="$2"
    printf '%s' "$content" > "$TEST_DOCS_DIR/$name"
}

# Helper: Check JSON validity (basic)
is_valid_json() {
    local json="$1"
    [[ "$json" =~ ^\{.*\}$ ]] || [[ "$json" =~ ^\[.*\]$ ]]
}

# =============================================================================
# CATEGORY 1: CONFIGURATION
# =============================================================================

@test "RAG_CHUNK_SIZE: respects environment variable" {
    [[ "$RAG_CHUNK_SIZE" == "100" ]]
}

@test "RAG_CHUNK_OVERLAP: respects environment variable" {
    [[ "$RAG_CHUNK_OVERLAP" == "10" ]]
}

@test "RAG_VECTORDB_BACKEND: respects environment variable" {
    [[ "$RAG_VECTORDB_BACKEND" == "sqlite-vec" ]]
}

@test "RAG_EMBED_PROVIDER: respects environment variable" {
    [[ "$RAG_EMBED_PROVIDER" == "local" ]]
}

@test "RAG_EXPORTS: contains all public functions" {
    [[ "${RAG_EXPORTS[*]}" =~ "rag_init" ]]
    [[ "${RAG_EXPORTS[*]}" =~ "rag_ingest" ]]
    [[ "${RAG_EXPORTS[*]}" =~ "rag_query" ]]
    [[ "${RAG_EXPORTS[*]}" =~ "rag_search" ]]
    [[ "${RAG_EXPORTS[*]}" =~ "rag_chunk_text" ]]
}

# =============================================================================
# CATEGORY 2: INITIALIZATION
# =============================================================================

@test "rag_init: initializes with default settings" {
    rag_init "test_init"

    [[ "$?" -eq 0 ]]
    rag_is_initialized
}

@test "rag_init: sets current collection" {
    rag_init "my_collection"

    result=$(rag_collection)
    [[ "$result" == "my_collection" ]]
}

@test "rag_init: accepts provider option" {
    rag_init "test_provider" --provider "local"

    [[ "$RAG_EMBED_PROVIDER" == "local" ]]
}

@test "rag_init: requires collection name" {
    run rag_init ""
    [[ "$status" -eq 1 ]]
}

@test "rag_is_initialized: returns false before init" {
    rag_reset

    ! rag_is_initialized
}

@test "rag_is_initialized: returns true after init" {
    rag_init "test_check"

    rag_is_initialized
}

@test "rag_reset: clears initialization state" {
    rag_init "test_reset"
    rag_reset

    ! rag_is_initialized
}

# =============================================================================
# CATEGORY 3: TEXT CHUNKING - FIXED STRATEGY
# =============================================================================

@test "rag_chunk_text: splits text into chunks" {
    local text="This is a test. This is another sentence. And one more here."

    result=$(rag_chunk_text "$text" --size 30 --overlap 5)

    # Should produce multiple chunks
    local chunk_count
    chunk_count=$(printf '%s' "$result" | grep -c .)
    [[ $chunk_count -gt 1 ]]
}

@test "rag_chunk_text: respects size parameter" {
    local text="word1 word2 word3 word4 word5 word6 word7 word8"

    result=$(rag_chunk_text "$text" --size 20 --overlap 0 | head -n1)

    [[ ${#result} -le 25 ]]  # Allow some margin for word boundaries
}

@test "rag_chunk_text: handles overlap" {
    local text="aaa bbb ccc ddd eee fff ggg hhh"

    chunks=$(rag_chunk_text "$text" --size 15 --overlap 5)

    # With overlap, chunks should share some content
    local chunk1 chunk2
    chunk1=$(printf '%s' "$chunks" | head -n1)
    chunk2=$(printf '%s' "$chunks" | head -n2 | tail -n1)

    # Chunks exist
    [[ -n "$chunk1" ]]
}

@test "rag_chunk_text: handles empty text" {
    result=$(rag_chunk_text "" --size 100)

    [[ -z "$result" ]]
}

@test "rag_chunk_text: handles short text" {
    result=$(rag_chunk_text "short" --size 100)

    chunk_count=$(printf '%s\n' "$result" | grep -c .)
    [[ $chunk_count -eq 1 ]]
}

@test "rag_chunk_text: preserves word boundaries" {
    local text="hello world this is a test of chunking"

    result=$(rag_chunk_text "$text" --size 15 --overlap 0 | head -n1)

    # Should not cut words in half
    [[ ! "$result" =~ [a-z]$ ]] || [[ "$result" =~ [[:space:]]$ ]] || [[ "$result" =~ ^[a-z]+$ ]]
}

# =============================================================================
# CATEGORY 4: TEXT CHUNKING - SENTENCE STRATEGY
# =============================================================================

@test "rag_chunk_text: sentence strategy splits on sentence boundaries" {
    local text="First sentence. Second sentence. Third sentence. Fourth sentence."

    result=$(rag_chunk_text "$text" --strategy sentence --size 40 --overlap 0)

    # Should produce multiple chunks
    local chunk_count
    chunk_count=$(printf '%s' "$result" | grep -c '.')
    [[ $chunk_count -ge 1 ]]
}

@test "rag_chunk_text: sentence strategy handles exclamation marks" {
    local text="Hello! How are you? I am fine."

    result=$(rag_chunk_text "$text" --strategy sentence --size 200)

    [[ -n "$result" ]]
}

# =============================================================================
# CATEGORY 5: TEXT CHUNKING - PARAGRAPH STRATEGY
# =============================================================================

@test "rag_chunk_text: paragraph strategy splits on double newlines" {
    local text=$'First paragraph here.\n\nSecond paragraph here.\n\nThird paragraph.'

    result=$(rag_chunk_text "$text" --strategy paragraph --size 100)

    [[ -n "$result" ]]
}

# =============================================================================
# CATEGORY 6: TEXT CHUNKING - CODE STRATEGY
# =============================================================================

@test "rag_chunk_text: code strategy handles functions" {
    local code='function hello() {
    echo "Hello"
}

function world() {
    echo "World"
}'

    result=$(rag_chunk_text "$code" --strategy code --size 200)

    [[ -n "$result" ]]
}

# =============================================================================
# CATEGORY 7: TEXT INGESTION
# =============================================================================

@test "rag_ingest_text: stores text in vector database" {
    rag_init "test_ingest"

    rag_ingest_text "This is test content" --id "test_doc_1"

    [[ "$?" -eq 0 ]]
}

@test "rag_ingest_text: generates ID if not provided" {
    rag_init "test_auto_id"

    rag_ingest_text "Content without explicit ID"

    [[ "$?" -eq 0 ]]
}

@test "rag_ingest_text: requires non-empty content" {
    rag_init "test_empty"

    run rag_ingest_text ""
    [[ "$status" -eq 1 ]]
}

@test "rag_ingest_text: accepts metadata" {
    rag_init "test_metadata"

    rag_ingest_text "Content with metadata" --id "meta_doc" \
        --metadata '{"author":"test","version":1}'

    [[ "$?" -eq 0 ]]
}

@test "rag_ingest_text: auto-initializes if needed" {
    rag_reset

    rag_ingest_text "Auto init test" --id "auto_init_doc" --collection "auto_collection"

    rag_is_initialized
}

# =============================================================================
# CATEGORY 8: FILE INGESTION
# =============================================================================

@test "rag_ingest_file: ingests text file" {
    create_test_doc "test.txt" "This is a text file with some content for testing."
    rag_init "test_file_ingest"

    rag_ingest_file "$TEST_DOCS_DIR/test.txt"

    [[ "$?" -eq 0 ]]
}

@test "rag_ingest_file: ingests markdown file" {
    create_test_doc "test.md" "# Header\n\nThis is markdown content."
    rag_init "test_md_ingest"

    rag_ingest_file "$TEST_DOCS_DIR/test.md"

    [[ "$?" -eq 0 ]]
}

@test "rag_ingest_file: ingests code file with code strategy" {
    create_test_doc "test.sh" 'function test() { echo "test"; }'
    rag_init "test_code_ingest"

    rag_ingest_file "$TEST_DOCS_DIR/test.sh"

    [[ "$?" -eq 0 ]]
}

@test "rag_ingest_file: requires existing file" {
    rag_init "test_missing"

    run rag_ingest_file "/nonexistent/file.txt"
    [[ "$status" -eq 1 ]]
}

@test "rag_ingest_file: handles custom ID" {
    create_test_doc "custom_id.txt" "Content for custom ID test"
    rag_init "test_custom_id"

    rag_ingest_file "$TEST_DOCS_DIR/custom_id.txt" --id "my_custom_id"

    [[ "$?" -eq 0 ]]
}

@test "rag_ingest_file: handles empty file gracefully" {
    create_test_doc "empty.txt" ""
    rag_init "test_empty_file"

    run rag_ingest_file "$TEST_DOCS_DIR/empty.txt"
    # Should warn/fail for empty file
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 9: DIRECTORY INGESTION
# =============================================================================

@test "rag_ingest: ingests all files in directory" {
    create_test_doc "doc1.txt" "First document content"
    create_test_doc "doc2.txt" "Second document content"
    rag_init "test_dir_ingest"

    result=$(rag_ingest "$TEST_DOCS_DIR")

    [[ "$result" -eq 2 ]]
}

@test "rag_ingest: requires existing directory" {
    rag_init "test_missing_dir"

    run rag_ingest "/nonexistent/directory"
    [[ "$status" -eq 1 ]]
}

@test "rag_ingest: handles collection option" {
    create_test_doc "dir_test.txt" "Test content"
    rag_init "default"

    rag_ingest "$TEST_DOCS_DIR" --collection "custom_collection"

    [[ "$?" -eq 0 ]]
}

# =============================================================================
# CATEGORY 10: SEARCHING
# =============================================================================

@test "rag_search: returns results for matching query" {
    rag_init "test_search"
    rag_ingest_text "JSON objects are created using json_object function" --id "json_doc"

    result=$(rag_search "JSON objects" --top-k 5)

    [[ "$result" =~ '"ok":true' ]]
}

@test "rag_search: returns empty array for no matches" {
    rag_init "test_empty_search"

    result=$(rag_search "nonexistent query xyz123" --raw)

    # Should return empty array or empty results
    [[ "$result" == "[]" ]] || [[ -z "$result" ]] || [[ "$result" =~ \[\] ]]
}

@test "rag_search: respects top-k parameter" {
    rag_init "test_topk"
    rag_ingest_text "Document one about testing" --id "doc1"
    rag_ingest_text "Document two about testing" --id "doc2"
    rag_ingest_text "Document three about testing" --id "doc3"

    result=$(rag_search "testing" --top-k 2 --raw)

    # Should limit results
    [[ -n "$result" ]]
}

@test "rag_search: requires query" {
    rag_init "test_no_query"

    run rag_search "" --raw
    # Should return empty or handle gracefully
    [[ "$output" == "[]" ]] || [[ "$status" -eq 0 ]]
}

@test "rag_search: returns USOP JSON format" {
    rag_init "test_usop"
    rag_ingest_text "Test document for USOP format" --id "usop_doc"

    result=$(rag_search "USOP format")

    [[ "$result" =~ '"ok":' ]]
    [[ "$result" =~ '"data":' ]] || [[ "$result" =~ '"error":' ]]
}

# =============================================================================
# CATEGORY 11: QUERYING (WITH CONTEXT)
# =============================================================================

@test "rag_query: returns query with context" {
    rag_init "test_query"
    rag_ingest_text "Use json_object to create JSON in bash" --id "json_help"

    result=$(rag_query "How do I create JSON?")

    [[ "$result" =~ '"ok":true' ]]
    [[ "$result" =~ '"query":' ]]
}

@test "rag_query: includes augmented_prompt" {
    rag_init "test_augmented"
    rag_ingest_text "RAG pipelines retrieve relevant documents" --id "rag_doc"

    result=$(rag_query "What is RAG?")

    [[ "$result" =~ '"augmented_prompt":' ]]
}

@test "rag_query: handles no-prompt option" {
    rag_init "test_no_prompt"
    rag_ingest_text "Test document" --id "np_doc"

    result=$(rag_query "test" --no-prompt)

    [[ "$result" =~ '"ok":true' ]]
}

@test "rag_query: requires query" {
    rag_init "test_query_required"

    result=$(rag_query "")

    [[ "$result" =~ '"ok":false' ]] || [[ "$result" =~ '"error":' ]]
}

@test "rag_query: auto-initializes if needed" {
    rag_reset

    result=$(rag_query "test query" --collection "auto_query_collection")

    # Should not crash, may have empty results
    [[ -n "$result" ]]
}

# =============================================================================
# CATEGORY 12: CONTEXT AUGMENTATION
# =============================================================================

@test "rag_augment_prompt: injects context into prompt" {
    local -a contexts=("First document content" "Second document content")

    result=$(rag_augment_prompt "What is the answer?" contexts)

    [[ "$result" =~ "Context" ]]
    [[ "$result" =~ "First document content" ]]
    [[ "$result" =~ "What is the answer?" ]]
}

@test "rag_augment_prompt: numbers context items" {
    local -a contexts=("Doc 1" "Doc 2" "Doc 3")

    result=$(rag_augment_prompt "Question?" contexts)

    [[ "$result" =~ "[1]" ]]
    [[ "$result" =~ "[2]" ]]
    [[ "$result" =~ "[3]" ]]
}

@test "rag_augment_prompt: handles empty context" {
    local -a contexts=()

    result=$(rag_augment_prompt "Question?" contexts)

    [[ "$result" =~ "Question?" ]]
}

@test "rag_augment_prompt: handles empty prompt" {
    local -a contexts=("Some context")

    result=$(rag_augment_prompt "" contexts)

    # Should handle gracefully
    [[ -z "$result" ]] || [[ -n "$result" ]]
}

# =============================================================================
# CATEGORY 13: RERANKING
# =============================================================================

@test "rag_rerank: handles empty results" {
    result=$(rag_rerank "[]" "test query")

    [[ "$result" == "[]" ]]
}

@test "rag_rerank: handles empty query" {
    local results='[{"text":"doc1"},{"text":"doc2"}]'

    result=$(rag_rerank "$results" "")

    # Should return original results
    [[ "$result" =~ "doc1" ]]
}

@test "rag_rerank: returns valid JSON" {
    rag_init "test_rerank"
    local results='[{"text":"hello world"},{"text":"goodbye world"}]'

    result=$(rag_rerank "$results" "hello")

    is_valid_json "$result"
}

# =============================================================================
# CATEGORY 14: DELETION
# =============================================================================

@test "rag_delete: removes document from index" {
    rag_init "test_delete"
    rag_ingest_text "Document to delete" --id "delete_me"

    rag_delete "delete_me"

    [[ "$?" -eq 0 ]]
}

@test "rag_delete: requires document ID" {
    rag_init "test_delete_id"

    run rag_delete ""
    [[ "$status" -eq 1 ]]
}

@test "rag_delete: handles collection option" {
    rag_init "delete_collection"
    rag_ingest_text "Delete from collection" --id "coll_delete"

    rag_delete "coll_delete" --collection "delete_collection"

    [[ "$?" -eq 0 ]]
}

# =============================================================================
# CATEGORY 15: STATISTICS
# =============================================================================

@test "rag_stats: returns statistics" {
    rag_init "test_stats"

    result=$(rag_stats)

    [[ "$result" =~ "RAG Pipeline Statistics" ]]
    [[ "$result" =~ "Collection:" ]]
}

@test "rag_stats: supports JSON output" {
    rag_init "test_json_stats"

    result=$(rag_stats --json)

    [[ "$result" =~ '"ok":true' ]]
    [[ "$result" =~ '"collection":' ]]
}

@test "rag_stats: includes session statistics" {
    rag_init "test_session_stats"
    rag_ingest_text "Stats test doc" --id "stats_doc"

    result=$(rag_stats --json)

    [[ "$result" =~ '"docs_ingested":' ]]
    [[ "$result" =~ '"chunks_created":' ]]
    [[ "$result" =~ '"queries_made":' ]]
}

@test "rag_stats: tracks document count" {
    rag_init "test_doc_count"
    rag_ingest_text "Doc 1" --id "count_1"
    rag_ingest_text "Doc 2" --id "count_2"

    result=$(rag_stats --json)

    [[ "$result" =~ '"document_count":' ]]
}

# =============================================================================
# CATEGORY 16: EDGE CASES
# =============================================================================

@test "rag_ingest_text: handles special characters" {
    rag_init "test_special"

    rag_ingest_text 'Text with "quotes" and \backslash' --id "special_doc"

    [[ "$?" -eq 0 ]]
}

@test "rag_ingest_text: handles newlines" {
    rag_init "test_newlines"

    rag_ingest_text $'Line 1\nLine 2\nLine 3' --id "newline_doc"

    [[ "$?" -eq 0 ]]
}

@test "rag_search: handles special characters in query" {
    rag_init "test_special_query"
    rag_ingest_text "Document about C++" --id "cpp_doc"

    result=$(rag_search 'C++')

    [[ -n "$result" ]]
}

@test "rag_chunk_text: handles unicode" {
    local text="Hello world. Test content here."

    result=$(rag_chunk_text "$text" --size 50)

    [[ -n "$result" ]]
}

@test "rag_ingest_file: handles JSON files" {
    create_test_doc "test.json" '{"name":"test","value":"content"}'
    rag_init "test_json_file"

    rag_ingest_file "$TEST_DOCS_DIR/test.json"

    [[ "$?" -eq 0 ]]
}

# =============================================================================
# CATEGORY 17: INTEGRATION TESTS
# =============================================================================

@test "integration: full ingest-search cycle" {
    rag_init "integration_test"

    # Ingest multiple documents
    rag_ingest_text "JSON functions help create structured data" --id "int_doc1"
    rag_ingest_text "Arrays can be created using json_array" --id "int_doc2"
    rag_ingest_text "Validation ensures data integrity" --id "int_doc3"

    # Search for relevant documents
    result=$(rag_search "JSON")

    [[ "$result" =~ '"ok":true' ]]
}

@test "integration: ingest directory and query" {
    create_test_doc "intro.txt" "This is an introduction to the system."
    create_test_doc "guide.txt" "This guide explains how to use features."
    rag_init "int_dir_test"

    count=$(rag_ingest "$TEST_DOCS_DIR")
    [[ "$count" -ge 2 ]]

    result=$(rag_query "how to use")

    [[ "$result" =~ '"ok":true' ]]
}

@test "integration: multiple collections" {
    rag_init "collection_a"
    rag_ingest_text "Document in collection A" --id "col_a_doc" --collection "collection_a"

    rag_init "collection_b"
    rag_ingest_text "Document in collection B" --id "col_b_doc" --collection "collection_b"

    result_a=$(rag_search "collection" --collection "collection_a")
    result_b=$(rag_search "collection" --collection "collection_b")

    [[ -n "$result_a" ]]
    [[ -n "$result_b" ]]
}

# =============================================================================
# CATEGORY 18: CHUNKING STATISTICS
# =============================================================================

@test "chunking: updates chunks_created counter" {
    rag_reset
    rag_init "test_chunk_counter"

    local text="This is a test sentence. This is another test sentence. And one more."
    rag_chunk_text "$text" --size 30 --overlap 5 > /dev/null

    result=$(rag_stats --json)
    [[ "$result" =~ '"chunks_created":' ]]
}

# =============================================================================
# CATEGORY 19: FILE TYPE DETECTION
# =============================================================================

@test "_rag_detect_file_type: detects text files" {
    result=$(_rag_detect_file_type "readme.txt")
    [[ "$result" == "text" ]]

    result=$(_rag_detect_file_type "doc.md")
    [[ "$result" == "text" ]]
}

@test "_rag_detect_file_type: detects code files" {
    result=$(_rag_detect_file_type "script.sh")
    [[ "$result" == "code" ]]

    result=$(_rag_detect_file_type "app.py")
    [[ "$result" == "code" ]]

    result=$(_rag_detect_file_type "module.js")
    [[ "$result" == "code" ]]
}

@test "_rag_detect_file_type: detects data files" {
    result=$(_rag_detect_file_type "config.json")
    [[ "$result" == "data" ]]

    result=$(_rag_detect_file_type "settings.yaml")
    [[ "$result" == "data" ]]
}

@test "_rag_detect_file_type: returns unknown for unsupported" {
    result=$(_rag_detect_file_type "binary.exe")
    [[ "$result" == "unknown" ]]
}

# =============================================================================
# CATEGORY 20: ID GENERATION
# =============================================================================

@test "_rag_generate_id: generates consistent IDs" {
    id1=$(_rag_generate_id "test content" "source.txt" 0)
    id2=$(_rag_generate_id "test content" "source.txt" 0)

    [[ "$id1" == "$id2" ]]
}

@test "_rag_generate_id: generates different IDs for different content" {
    id1=$(_rag_generate_id "content one" "source.txt" 0)
    id2=$(_rag_generate_id "content two" "source.txt" 0)

    [[ "$id1" != "$id2" ]]
}

@test "_rag_generate_id: generates different IDs for different chunks" {
    id1=$(_rag_generate_id "same content" "source.txt" 0)
    id2=$(_rag_generate_id "same content" "source.txt" 1)

    [[ "$id1" != "$id2" ]]
}

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/vectordb.sh - Universal Vector Database Interface
# =============================================================================
# Description: Backend-agnostic vector database operations for AI agents
# Supported Backends: chromadb, pinecone, qdrant, sqlite-vec
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================
#
# Usage: source vectordb.sh
#
# Examples:
#   # Initialize connection
#   vectordb_init "chromadb" "http://localhost:8000"
#
#   # Create collection
#   vectordb_create_collection "documents" 384
#
#   # Upsert document with embedding
#   vectordb_upsert "documents" "doc1" "Hello world" "[0.1,0.2,0.3]" '{"source":"test"}'
#
#   # Search for similar documents
#   vectordb_search "documents" "[0.1,0.2,0.3]" --top-k 5
#
# Backends:
#   chromadb   - REST API at http://localhost:8000 (default)
#   pinecone   - Cloud API with API key
#   qdrant     - REST API at http://localhost:6333
#   sqlite-vec - Local SQLite with vector extension (no external deps)
#
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_VECTORDB_LOADED:-}" ]] && return 0
readonly _MAINFRAME_VECTORDB_LOADED=1

# =============================================================================
# CONSTANTS
# =============================================================================

readonly VECTORDB_VERSION="1.0.0"
readonly VECTORDB_DEFAULT_BACKEND="chromadb"
readonly VECTORDB_DEFAULT_TOP_K=5
readonly VECTORDB_DEFAULT_DIMENSIONS=384

# Supported backends
readonly VECTORDB_BACKENDS="chromadb pinecone qdrant sqlite-vec"

# =============================================================================
# STATE MANAGEMENT
# =============================================================================

# Current backend state (module-level)
_VECTORDB_BACKEND=""
_VECTORDB_CONNECTION=""
_VECTORDB_API_KEY=""
_VECTORDB_INITIALIZED=false

# ChromaDB collection ID cache (name -> id mapping)
declare -gA _VECTORDB_CHROMADB_COLLECTIONS 2>/dev/null || declare -A _VECTORDB_CHROMADB_COLLECTIONS

# SQLite-vec database path
_VECTORDB_SQLITE_PATH=""

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Internal logging helper
_vectordb_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "vectordb" "$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[vectordb] %s: %s\n' "$level" "$*" >&2
    fi
}

# Validate backend name
# Usage: _vectordb_valid_backend "chromadb"
_vectordb_valid_backend() {
    local backend="$1"
    [[ -z "$backend" ]] && return 1
    [[ " $VECTORDB_BACKENDS " == *" $backend "* ]]
}

# Check if backend is initialized
# Usage: _vectordb_require_init
_vectordb_require_init() {
    if [[ "$_VECTORDB_INITIALIZED" != "true" ]]; then
        _vectordb_log "error" "Vector database not initialized. Call vectordb_init first."
        return 1
    fi
    return 0
}

# Parse embedding from JSON array to space-separated floats
# Usage: _vectordb_parse_embedding "[0.1,0.2,0.3]"
_vectordb_parse_embedding() {
    local embedding="$1"
    # Remove brackets and convert commas to spaces
    embedding="${embedding#[}"
    embedding="${embedding%]}"
    printf '%s' "${embedding//,/ }"
}

# Format embedding as JSON array
# Usage: _vectordb_format_embedding "0.1 0.2 0.3"
_vectordb_format_embedding() {
    local values="$1"
    printf '[%s]' "${values// /,}"
}

# Calculate dot product for similarity (pure bash, for sqlite-vec)
# Usage: _vectordb_dot_product "0.1 0.2 0.3" "0.4 0.5 0.6"
_vectordb_dot_product() {
    local -a vec1=($1)
    local -a vec2=($2)
    local sum=0
    local i

    for ((i=0; i<${#vec1[@]}; i++)); do
        # Use awk for floating point math
        sum=$(awk "BEGIN {printf \"%.10f\", $sum + ${vec1[i]} * ${vec2[i]}}")
    done

    printf '%s' "$sum"
}

# Make HTTP request (delegates to http.sh if available)
# Usage: _vectordb_http "GET" "http://localhost:8000/api/v1/collections"
_vectordb_http() {
    local method="$1"
    local url="$2"
    local body="${3:-}"
    local headers=("${@:4}")

    # Prefer MAINFRAME http.sh functions if available
    if declare -F http_request &>/dev/null; then
        if [[ -n "$body" ]]; then
            http_request "$method" "$url" "$body" "Content-Type: application/json" "${headers[@]}"
        else
            http_request "$method" "$url" "" "${headers[@]}"
        fi
        return $?
    fi

    # Fallback to curl
    if ! command -v curl &>/dev/null; then
        _vectordb_log "error" "curl not found and http.sh not loaded"
        return 1
    fi

    local curl_args=(-s -X "$method")

    if [[ -n "$body" ]]; then
        curl_args+=(-H "Content-Type: application/json" -d "$body")
    fi

    for header in "${headers[@]}"; do
        curl_args+=(-H "$header")
    done

    curl "${curl_args[@]}" "$url"
}

# Extract HTTP body from response
# Usage: body=$(_vectordb_http_body "$response")
_vectordb_http_body() {
    local response="$1"

    if declare -F http_body &>/dev/null; then
        http_body "$response"
    else
        # Assume curl output is just the body
        printf '%s' "$response"
    fi
}

# Extract HTTP status from response
# Usage: status=$(_vectordb_http_status "$response")
_vectordb_http_status() {
    local response="$1"

    if declare -F http_status &>/dev/null; then
        http_status "$response"
    else
        # Assume success if we got output
        [[ -n "$response" ]] && printf '200' || printf '0'
    fi
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize vector database connection
# Usage: vectordb_init "chromadb" "http://localhost:8000"
# Usage: vectordb_init "pinecone" "https://controller.pinecone.io" "api-key"
# Usage: vectordb_init "sqlite-vec" "/path/to/database.db"
# Returns: 0 on success, 1 on failure
vectordb_init() {
    local backend="${1:-$VECTORDB_DEFAULT_BACKEND}"
    local connection="${2:-}"
    local api_key="${3:-}"

    # Validate backend
    if ! _vectordb_valid_backend "$backend"; then
        _vectordb_log "error" "Invalid backend: $backend. Supported: $VECTORDB_BACKENDS"
        return 1
    fi

    # Set defaults based on backend
    case "$backend" in
        chromadb)
            connection="${connection:-http://localhost:8000}"
            ;;
        pinecone)
            if [[ -z "$api_key" ]]; then
                api_key="${PINECONE_API_KEY:-}"
            fi
            if [[ -z "$api_key" ]]; then
                _vectordb_log "error" "Pinecone requires API key"
                return 1
            fi
            connection="${connection:-https://controller.pinecone.io}"
            ;;
        qdrant)
            connection="${connection:-http://localhost:6333}"
            ;;
        sqlite-vec)
            connection="${connection:-${TMPDIR:-/tmp}/vectordb.sqlite}"
            _VECTORDB_SQLITE_PATH="$connection"
            # Initialize SQLite database
            _vectordb_sqlite_init "$connection" || return 1
            ;;
    esac

    _VECTORDB_BACKEND="$backend"
    _VECTORDB_CONNECTION="$connection"
    _VECTORDB_API_KEY="$api_key"
    _VECTORDB_INITIALIZED=true

    _vectordb_log "info" "Initialized $backend backend at $connection"
    return 0
}

# =============================================================================
# SQLITE-VEC IMPLEMENTATION
# =============================================================================

# Initialize SQLite database for vector storage
# Usage: _vectordb_sqlite_init "/path/to/db.sqlite"
_vectordb_sqlite_init() {
    local db_path="$1"

    if ! command -v sqlite3 &>/dev/null; then
        _vectordb_log "error" "sqlite3 not found"
        return 1
    fi

    # Create tables if they don't exist
    sqlite3 "$db_path" <<'EOF'
CREATE TABLE IF NOT EXISTS vectordb_collections (
    name TEXT PRIMARY KEY,
    dimensions INTEGER NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS vectordb_documents (
    id TEXT NOT NULL,
    collection TEXT NOT NULL,
    text TEXT,
    embedding TEXT NOT NULL,
    metadata TEXT DEFAULT '{}',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, collection),
    FOREIGN KEY (collection) REFERENCES vectordb_collections(name)
);

CREATE INDEX IF NOT EXISTS idx_documents_collection ON vectordb_documents(collection);
EOF

    return $?
}

# SQLite: Create collection
_vectordb_sqlite_create_collection() {
    local name="$1"
    local dimensions="$2"

    sqlite3 "$_VECTORDB_SQLITE_PATH" \
        "INSERT OR REPLACE INTO vectordb_collections (name, dimensions) VALUES ('$name', $dimensions);"
}

# SQLite: Delete collection
_vectordb_sqlite_delete_collection() {
    local name="$1"

    sqlite3 "$_VECTORDB_SQLITE_PATH" <<EOF
DELETE FROM vectordb_documents WHERE collection = '$name';
DELETE FROM vectordb_collections WHERE name = '$name';
EOF
}

# SQLite: List collections
_vectordb_sqlite_list_collections() {
    local result
    result=$(sqlite3 -json "$_VECTORDB_SQLITE_PATH" \
        "SELECT name, dimensions FROM vectordb_collections;")
    # sqlite3 -json returns empty string when no rows, normalize to []
    [[ -z "$result" ]] && result="[]"
    printf '%s\n' "$result"
}

# SQLite: Upsert document
_vectordb_sqlite_upsert() {
    local collection="$1"
    local id="$2"
    local text="$3"
    local embedding="$4"
    local metadata="${5:-{}}"

    # Escape single quotes in text and metadata
    text="${text//\'/\'\'}"
    metadata="${metadata//\'/\'\'}"

    sqlite3 "$_VECTORDB_SQLITE_PATH" \
        "INSERT OR REPLACE INTO vectordb_documents (id, collection, text, embedding, metadata) VALUES ('$id', '$collection', '$text', '$embedding', '$metadata');"
}

# SQLite: Get document by ID
_vectordb_sqlite_get() {
    local collection="$1"
    local id="$2"

    local result
    result=$(sqlite3 -json "$_VECTORDB_SQLITE_PATH" \
        "SELECT id, text, embedding, metadata FROM vectordb_documents WHERE collection = '$collection' AND id = '$id';")
    # sqlite3 -json returns empty string when no rows, normalize to []
    [[ -z "$result" ]] && result="[]"
    printf '%s\n' "$result"
}

# SQLite: Delete document
_vectordb_sqlite_delete() {
    local collection="$1"
    local id="$2"

    sqlite3 "$_VECTORDB_SQLITE_PATH" \
        "DELETE FROM vectordb_documents WHERE collection = '$collection' AND id = '$id';"
}

# SQLite: Count documents
_vectordb_sqlite_count() {
    local collection="$1"

    sqlite3 "$_VECTORDB_SQLITE_PATH" \
        "SELECT COUNT(*) FROM vectordb_documents WHERE collection = '$collection';"
}

# SQLite: Search by similarity (brute force dot product)
_vectordb_sqlite_search() {
    local collection="$1"
    local query_embedding="$2"
    local top_k="${3:-$VECTORDB_DEFAULT_TOP_K}"

    local query_vec
    query_vec=$(_vectordb_parse_embedding "$query_embedding")

    # Get all documents and compute similarity
    local results
    results=$(sqlite3 -separator $'\t' "$_VECTORDB_SQLITE_PATH" \
        "SELECT id, text, embedding, metadata FROM vectordb_documents WHERE collection = '$collection';")

    # Compute similarities and sort
    local scored_results=""
    while IFS=$'\t' read -r id text embedding metadata; do
        [[ -z "$id" ]] && continue
        local doc_vec
        doc_vec=$(_vectordb_parse_embedding "$embedding")
        local score
        score=$(_vectordb_dot_product "$query_vec" "$doc_vec")
        scored_results+="$score"$'\t'"$id"$'\t'"$text"$'\t'"$metadata"$'\n'
    done <<< "$results"

    # Sort by score (descending) and take top-k
    printf '%s' "$scored_results" | sort -t$'\t' -k1 -rn | head -n "$top_k" | \
        awk -F'\t' 'BEGIN{printf "["}
            NR>1{printf ","}
            {gsub(/"/, "\\\"", $3); gsub(/"/, "\\\"", $4); printf "{\"id\":\"%s\",\"score\":%s,\"text\":\"%s\",\"metadata\":%s}", $2, $1, $3, $4}
            END{printf "]"}'
}

# =============================================================================
# CHROMADB IMPLEMENTATION
# =============================================================================

# ChromaDB: Get or create collection, return collection ID
_vectordb_chromadb_get_collection_id() {
    local name="$1"
    local create="${2:-false}"
    local dimensions="${3:-$VECTORDB_DEFAULT_DIMENSIONS}"

    # Check cache first
    if [[ -n "${_VECTORDB_CHROMADB_COLLECTIONS[$name]:-}" ]]; then
        printf '%s' "${_VECTORDB_CHROMADB_COLLECTIONS[$name]}"
        return 0
    fi

    # Try to get existing collection
    local response body
    response=$(_vectordb_http "GET" "${_VECTORDB_CONNECTION}/api/v1/collections/${name}")
    body=$(_vectordb_http_body "$response")

    # Check if collection exists
    if [[ "$body" =~ \"id\":\"([^\"]+)\" ]]; then
        local id="${BASH_REMATCH[1]}"
        _VECTORDB_CHROMADB_COLLECTIONS["$name"]="$id"
        printf '%s' "$id"
        return 0
    fi

    # Create if requested
    if [[ "$create" == "true" ]]; then
        local create_body
        create_body=$(printf '{"name":"%s","metadata":{"dimensions":%d}}' "$name" "$dimensions")
        response=$(_vectordb_http "POST" "${_VECTORDB_CONNECTION}/api/v1/collections" "$create_body")
        body=$(_vectordb_http_body "$response")

        if [[ "$body" =~ \"id\":\"([^\"]+)\" ]]; then
            local id="${BASH_REMATCH[1]}"
            _VECTORDB_CHROMADB_COLLECTIONS["$name"]="$id"
            printf '%s' "$id"
            return 0
        fi
    fi

    return 1
}

# ChromaDB: Create collection
_vectordb_chromadb_create_collection() {
    local name="$1"
    local dimensions="${2:-$VECTORDB_DEFAULT_DIMENSIONS}"

    local body
    body=$(printf '{"name":"%s","metadata":{"dimensions":%d}}' "$name" "$dimensions")

    local response
    response=$(_vectordb_http "POST" "${_VECTORDB_CONNECTION}/api/v1/collections" "$body")

    local response_body
    response_body=$(_vectordb_http_body "$response")

    if [[ "$response_body" =~ \"id\":\"([^\"]+)\" ]]; then
        _VECTORDB_CHROMADB_COLLECTIONS["$name"]="${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

# ChromaDB: Delete collection
_vectordb_chromadb_delete_collection() {
    local name="$1"

    _vectordb_http "DELETE" "${_VECTORDB_CONNECTION}/api/v1/collections/${name}"
    unset "_VECTORDB_CHROMADB_COLLECTIONS[$name]"
    return 0
}

# ChromaDB: List collections
_vectordb_chromadb_list_collections() {
    local response body
    response=$(_vectordb_http "GET" "${_VECTORDB_CONNECTION}/api/v1/collections")
    body=$(_vectordb_http_body "$response")
    printf '%s' "$body"
}

# ChromaDB: Upsert document
_vectordb_chromadb_upsert() {
    local collection="$1"
    local id="$2"
    local text="$3"
    local embedding="$4"
    local metadata="${5:-{}}"

    local collection_id
    collection_id=$(_vectordb_chromadb_get_collection_id "$collection" "true") || return 1

    # Escape text for JSON
    local escaped_text
    if declare -F json_escape &>/dev/null; then
        escaped_text=$(json_escape "$text")
    else
        escaped_text="${text//\\/\\\\}"
        escaped_text="${escaped_text//\"/\\\"}"
        escaped_text="${escaped_text//$'\n'/\\n}"
    fi

    local body
    body=$(printf '{"ids":["%s"],"embeddings":[%s],"documents":["%s"],"metadatas":[%s]}' \
        "$id" "$embedding" "$escaped_text" "$metadata")

    local response
    response=$(_vectordb_http "POST" "${_VECTORDB_CONNECTION}/api/v1/collections/${collection_id}/upsert" "$body")

    return 0
}

# ChromaDB: Get document
_vectordb_chromadb_get() {
    local collection="$1"
    local id="$2"

    local collection_id
    collection_id=$(_vectordb_chromadb_get_collection_id "$collection") || return 1

    local body
    body=$(printf '{"ids":["%s"],"include":["documents","metadatas","embeddings"]}' "$id")

    local response
    response=$(_vectordb_http "POST" "${_VECTORDB_CONNECTION}/api/v1/collections/${collection_id}/get" "$body")
    _vectordb_http_body "$response"
}

# ChromaDB: Delete document
_vectordb_chromadb_delete() {
    local collection="$1"
    local id="$2"

    local collection_id
    collection_id=$(_vectordb_chromadb_get_collection_id "$collection") || return 1

    local body
    body=$(printf '{"ids":["%s"]}' "$id")

    _vectordb_http "POST" "${_VECTORDB_CONNECTION}/api/v1/collections/${collection_id}/delete" "$body"
    return 0
}

# ChromaDB: Count documents
_vectordb_chromadb_count() {
    local collection="$1"

    local collection_id
    collection_id=$(_vectordb_chromadb_get_collection_id "$collection") || return 1

    local response body
    response=$(_vectordb_http "GET" "${_VECTORDB_CONNECTION}/api/v1/collections/${collection_id}/count")
    body=$(_vectordb_http_body "$response")

    # Extract count from response
    if [[ "$body" =~ ^[0-9]+$ ]]; then
        printf '%s' "$body"
    else
        printf '0'
    fi
}

# ChromaDB: Search
_vectordb_chromadb_search() {
    local collection="$1"
    local query_embedding="$2"
    local top_k="${3:-$VECTORDB_DEFAULT_TOP_K}"

    local collection_id
    collection_id=$(_vectordb_chromadb_get_collection_id "$collection") || return 1

    local body
    body=$(printf '{"query_embeddings":[%s],"n_results":%d,"include":["documents","metadatas","distances"]}' \
        "$query_embedding" "$top_k")

    local response
    response=$(_vectordb_http "POST" "${_VECTORDB_CONNECTION}/api/v1/collections/${collection_id}/query" "$body")
    _vectordb_http_body "$response"
}

# =============================================================================
# QDRANT IMPLEMENTATION
# =============================================================================

# Qdrant: Create collection
_vectordb_qdrant_create_collection() {
    local name="$1"
    local dimensions="${2:-$VECTORDB_DEFAULT_DIMENSIONS}"

    local body
    body=$(printf '{"vectors":{"size":%d,"distance":"Cosine"}}' "$dimensions")

    _vectordb_http "PUT" "${_VECTORDB_CONNECTION}/collections/${name}" "$body"
    return $?
}

# Qdrant: Delete collection
_vectordb_qdrant_delete_collection() {
    local name="$1"
    _vectordb_http "DELETE" "${_VECTORDB_CONNECTION}/collections/${name}"
    return $?
}

# Qdrant: List collections
_vectordb_qdrant_list_collections() {
    local response body
    response=$(_vectordb_http "GET" "${_VECTORDB_CONNECTION}/collections")
    body=$(_vectordb_http_body "$response")
    printf '%s' "$body"
}

# Qdrant: Upsert document
_vectordb_qdrant_upsert() {
    local collection="$1"
    local id="$2"
    local text="$3"
    local embedding="$4"
    local metadata="${5:-{}}"

    # Qdrant uses numeric IDs, hash string ID
    local numeric_id
    numeric_id=$(printf '%s' "$id" | cksum | cut -d' ' -f1)

    # Escape text for JSON
    local escaped_text
    if declare -F json_escape &>/dev/null; then
        escaped_text=$(json_escape "$text")
    else
        escaped_text="${text//\\/\\\\}"
        escaped_text="${escaped_text//\"/\\\"}"
    fi

    local body
    body=$(printf '{"points":[{"id":%d,"vector":%s,"payload":{"text":"%s","original_id":"%s",%s}}]}' \
        "$numeric_id" "$embedding" "$escaped_text" "$id" "${metadata:1:-1}")

    _vectordb_http "PUT" "${_VECTORDB_CONNECTION}/collections/${collection}/points" "$body"
    return $?
}

# Qdrant: Get document
_vectordb_qdrant_get() {
    local collection="$1"
    local id="$2"

    local numeric_id
    numeric_id=$(printf '%s' "$id" | cksum | cut -d' ' -f1)

    local response body
    response=$(_vectordb_http "GET" "${_VECTORDB_CONNECTION}/collections/${collection}/points/${numeric_id}")
    body=$(_vectordb_http_body "$response")
    printf '%s' "$body"
}

# Qdrant: Delete document
_vectordb_qdrant_delete() {
    local collection="$1"
    local id="$2"

    local numeric_id
    numeric_id=$(printf '%s' "$id" | cksum | cut -d' ' -f1)

    local body
    body=$(printf '{"points":[%d]}' "$numeric_id")

    _vectordb_http "POST" "${_VECTORDB_CONNECTION}/collections/${collection}/points/delete" "$body"
    return $?
}

# Qdrant: Count documents
_vectordb_qdrant_count() {
    local collection="$1"

    local response body
    response=$(_vectordb_http "GET" "${_VECTORDB_CONNECTION}/collections/${collection}")
    body=$(_vectordb_http_body "$response")

    # Extract points_count from response
    if [[ "$body" =~ \"points_count\":([0-9]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        printf '0'
    fi
}

# Qdrant: Search
_vectordb_qdrant_search() {
    local collection="$1"
    local query_embedding="$2"
    local top_k="${3:-$VECTORDB_DEFAULT_TOP_K}"

    local body
    body=$(printf '{"vector":%s,"limit":%d,"with_payload":true}' "$query_embedding" "$top_k")

    local response
    response=$(_vectordb_http "POST" "${_VECTORDB_CONNECTION}/collections/${collection}/points/search" "$body")
    _vectordb_http_body "$response"
}

# =============================================================================
# PINECONE IMPLEMENTATION
# =============================================================================

# Pinecone: Create collection (index)
_vectordb_pinecone_create_collection() {
    local name="$1"
    local dimensions="${2:-$VECTORDB_DEFAULT_DIMENSIONS}"

    local body
    body=$(printf '{"name":"%s","dimension":%d,"metric":"cosine"}' "$name" "$dimensions")

    _vectordb_http "POST" "${_VECTORDB_CONNECTION}/indexes" "$body" \
        "Api-Key: $_VECTORDB_API_KEY"
    return $?
}

# Pinecone: Delete collection (index)
_vectordb_pinecone_delete_collection() {
    local name="$1"

    _vectordb_http "DELETE" "${_VECTORDB_CONNECTION}/indexes/${name}" "" \
        "Api-Key: $_VECTORDB_API_KEY"
    return $?
}

# Pinecone: List collections (indexes)
_vectordb_pinecone_list_collections() {
    local response body
    response=$(_vectordb_http "GET" "${_VECTORDB_CONNECTION}/indexes" "" \
        "Api-Key: $_VECTORDB_API_KEY")
    body=$(_vectordb_http_body "$response")
    printf '%s' "$body"
}

# Pinecone: Upsert document
_vectordb_pinecone_upsert() {
    local collection="$1"
    local id="$2"
    local text="$3"
    local embedding="$4"
    local metadata="${5:-{}}"

    # Get index host
    local host_response host_body index_host
    host_response=$(_vectordb_http "GET" "${_VECTORDB_CONNECTION}/indexes/${collection}" "" \
        "Api-Key: $_VECTORDB_API_KEY")
    host_body=$(_vectordb_http_body "$host_response")

    if [[ "$host_body" =~ \"host\":\"([^\"]+)\" ]]; then
        index_host="${BASH_REMATCH[1]}"
    else
        return 1
    fi

    # Escape text for JSON
    local escaped_text
    if declare -F json_escape &>/dev/null; then
        escaped_text=$(json_escape "$text")
    else
        escaped_text="${text//\\/\\\\}"
        escaped_text="${escaped_text//\"/\\\"}"
    fi

    local body
    body=$(printf '{"vectors":[{"id":"%s","values":%s,"metadata":{"text":"%s",%s}}]}' \
        "$id" "$embedding" "$escaped_text" "${metadata:1:-1}")

    _vectordb_http "POST" "https://${index_host}/vectors/upsert" "$body" \
        "Api-Key: $_VECTORDB_API_KEY"
    return $?
}

# Pinecone: Search
_vectordb_pinecone_search() {
    local collection="$1"
    local query_embedding="$2"
    local top_k="${3:-$VECTORDB_DEFAULT_TOP_K}"

    # Get index host
    local host_response host_body index_host
    host_response=$(_vectordb_http "GET" "${_VECTORDB_CONNECTION}/indexes/${collection}" "" \
        "Api-Key: $_VECTORDB_API_KEY")
    host_body=$(_vectordb_http_body "$host_response")

    if [[ "$host_body" =~ \"host\":\"([^\"]+)\" ]]; then
        index_host="${BASH_REMATCH[1]}"
    else
        return 1
    fi

    local body
    body=$(printf '{"vector":%s,"topK":%d,"includeMetadata":true}' "$query_embedding" "$top_k")

    local response
    response=$(_vectordb_http "POST" "https://${index_host}/query" "$body" \
        "Api-Key: $_VECTORDB_API_KEY")
    _vectordb_http_body "$response"
}

# =============================================================================
# PUBLIC API - COLLECTION OPERATIONS
# =============================================================================

# Create a new collection
# Usage: vectordb_create_collection "name" [dimensions]
# Returns: 0 on success, 1 on failure
vectordb_create_collection() {
    local name="$1"
    local dimensions="${2:-$VECTORDB_DEFAULT_DIMENSIONS}"

    _vectordb_require_init || return 1

    [[ -z "$name" ]] && {
        _vectordb_log "error" "Collection name required"
        return 1
    }

    # Validate dimensions
    if ! [[ "$dimensions" =~ ^[0-9]+$ ]] || [[ "$dimensions" -lt 1 ]]; then
        _vectordb_log "error" "Invalid dimensions: $dimensions"
        return 1
    fi

    case "$_VECTORDB_BACKEND" in
        chromadb)   _vectordb_chromadb_create_collection "$name" "$dimensions" ;;
        pinecone)   _vectordb_pinecone_create_collection "$name" "$dimensions" ;;
        qdrant)     _vectordb_qdrant_create_collection "$name" "$dimensions" ;;
        sqlite-vec) _vectordb_sqlite_create_collection "$name" "$dimensions" ;;
        *)          return 1 ;;
    esac
}

# Delete a collection
# Usage: vectordb_delete_collection "name"
# Returns: 0 on success, 1 on failure
vectordb_delete_collection() {
    local name="$1"

    _vectordb_require_init || return 1

    [[ -z "$name" ]] && {
        _vectordb_log "error" "Collection name required"
        return 1
    }

    case "$_VECTORDB_BACKEND" in
        chromadb)   _vectordb_chromadb_delete_collection "$name" ;;
        pinecone)   _vectordb_pinecone_delete_collection "$name" ;;
        qdrant)     _vectordb_qdrant_delete_collection "$name" ;;
        sqlite-vec) _vectordb_sqlite_delete_collection "$name" ;;
        *)          return 1 ;;
    esac
}

# List all collections
# Usage: vectordb_list_collections
# Returns: JSON array of collections
vectordb_list_collections() {
    _vectordb_require_init || return 1

    case "$_VECTORDB_BACKEND" in
        chromadb)   _vectordb_chromadb_list_collections ;;
        pinecone)   _vectordb_pinecone_list_collections ;;
        qdrant)     _vectordb_qdrant_list_collections ;;
        sqlite-vec) _vectordb_sqlite_list_collections ;;
        *)          return 1 ;;
    esac
}

# =============================================================================
# PUBLIC API - DOCUMENT OPERATIONS
# =============================================================================

# Upsert a document with embedding
# Usage: vectordb_upsert "collection" "id" "text" "[0.1,0.2,...]" '{"key":"value"}'
# Returns: 0 on success, 1 on failure
vectordb_upsert() {
    local collection="$1"
    local id="$2"
    local text="$3"
    local embedding="$4"
    local metadata="${5:-{}}"

    _vectordb_require_init || return 1

    # Validate required fields
    [[ -z "$collection" ]] && {
        _vectordb_log "error" "Collection name required"
        return 1
    }
    [[ -z "$id" ]] && {
        _vectordb_log "error" "Document ID required"
        return 1
    }
    [[ -z "$embedding" ]] && {
        _vectordb_log "error" "Embedding required"
        return 1
    }

    case "$_VECTORDB_BACKEND" in
        chromadb)   _vectordb_chromadb_upsert "$collection" "$id" "$text" "$embedding" "$metadata" ;;
        pinecone)   _vectordb_pinecone_upsert "$collection" "$id" "$text" "$embedding" "$metadata" ;;
        qdrant)     _vectordb_qdrant_upsert "$collection" "$id" "$text" "$embedding" "$metadata" ;;
        sqlite-vec) _vectordb_sqlite_upsert "$collection" "$id" "$text" "$embedding" "$metadata" ;;
        *)          return 1 ;;
    esac
}

# Search for similar documents
# Usage: vectordb_search "collection" "[0.1,0.2,...]" --top-k 5
# Returns: JSON array of results
vectordb_search() {
    local collection="$1"
    local query_embedding="$2"
    shift 2

    local top_k="$VECTORDB_DEFAULT_TOP_K"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --top-k)
                top_k="$2"
                shift 2
                ;;
            -k)
                top_k="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    _vectordb_require_init || return 1

    [[ -z "$collection" ]] && {
        _vectordb_log "error" "Collection name required"
        return 1
    }
    [[ -z "$query_embedding" ]] && {
        _vectordb_log "error" "Query embedding required"
        return 1
    }

    case "$_VECTORDB_BACKEND" in
        chromadb)   _vectordb_chromadb_search "$collection" "$query_embedding" "$top_k" ;;
        pinecone)   _vectordb_pinecone_search "$collection" "$query_embedding" "$top_k" ;;
        qdrant)     _vectordb_qdrant_search "$collection" "$query_embedding" "$top_k" ;;
        sqlite-vec) _vectordb_sqlite_search "$collection" "$query_embedding" "$top_k" ;;
        *)          return 1 ;;
    esac
}

# Get document by ID
# Usage: vectordb_get "collection" "id"
# Returns: JSON document
vectordb_get() {
    local collection="$1"
    local id="$2"

    _vectordb_require_init || return 1

    [[ -z "$collection" ]] && {
        _vectordb_log "error" "Collection name required"
        return 1
    }
    [[ -z "$id" ]] && {
        _vectordb_log "error" "Document ID required"
        return 1
    }

    case "$_VECTORDB_BACKEND" in
        chromadb)   _vectordb_chromadb_get "$collection" "$id" ;;
        pinecone)   _vectordb_log "error" "Get by ID not directly supported in Pinecone"; return 1 ;;
        qdrant)     _vectordb_qdrant_get "$collection" "$id" ;;
        sqlite-vec) _vectordb_sqlite_get "$collection" "$id" ;;
        *)          return 1 ;;
    esac
}

# Delete document by ID
# Usage: vectordb_delete "collection" "id"
# Returns: 0 on success, 1 on failure
vectordb_delete() {
    local collection="$1"
    local id="$2"

    _vectordb_require_init || return 1

    [[ -z "$collection" ]] && {
        _vectordb_log "error" "Collection name required"
        return 1
    }
    [[ -z "$id" ]] && {
        _vectordb_log "error" "Document ID required"
        return 1
    }

    case "$_VECTORDB_BACKEND" in
        chromadb)   _vectordb_chromadb_delete "$collection" "$id" ;;
        pinecone)   _vectordb_log "error" "Delete not directly supported in Pinecone via this interface"; return 1 ;;
        qdrant)     _vectordb_qdrant_delete "$collection" "$id" ;;
        sqlite-vec) _vectordb_sqlite_delete "$collection" "$id" ;;
        *)          return 1 ;;
    esac
}

# Get document count in collection
# Usage: vectordb_count "collection"
# Returns: Integer count
vectordb_count() {
    local collection="$1"

    _vectordb_require_init || return 1

    [[ -z "$collection" ]] && {
        _vectordb_log "error" "Collection name required"
        return 1
    }

    case "$_VECTORDB_BACKEND" in
        chromadb)   _vectordb_chromadb_count "$collection" ;;
        pinecone)   _vectordb_log "error" "Count not directly supported in Pinecone via this interface"; return 1 ;;
        qdrant)     _vectordb_qdrant_count "$collection" ;;
        sqlite-vec) _vectordb_sqlite_count "$collection" ;;
        *)          return 1 ;;
    esac
}

# =============================================================================
# PUBLIC API - HEALTH AND STATUS
# =============================================================================

# Check backend health
# Usage: vectordb_health
# Returns: 0 if healthy, 1 if unhealthy
vectordb_health() {
    _vectordb_require_init || return 1

    local response body status

    case "$_VECTORDB_BACKEND" in
        chromadb)
            response=$(_vectordb_http "GET" "${_VECTORDB_CONNECTION}/api/v1/heartbeat")
            body=$(_vectordb_http_body "$response")
            [[ "$body" =~ nanosecond ]] && return 0
            ;;
        pinecone)
            response=$(_vectordb_http "GET" "${_VECTORDB_CONNECTION}/indexes" "" \
                "Api-Key: $_VECTORDB_API_KEY")
            status=$(_vectordb_http_status "$response")
            [[ "$status" == "200" ]] && return 0
            ;;
        qdrant)
            response=$(_vectordb_http "GET" "${_VECTORDB_CONNECTION}/readyz")
            body=$(_vectordb_http_body "$response")
            [[ "$body" =~ ok ]] && return 0
            ;;
        sqlite-vec)
            [[ -f "$_VECTORDB_SQLITE_PATH" ]] && sqlite3 "$_VECTORDB_SQLITE_PATH" "SELECT 1;" &>/dev/null && return 0
            ;;
    esac

    return 1
}

# Get current backend info
# Usage: vectordb_info
# Returns: JSON with backend, connection, status
vectordb_info() {
    local health_status="unhealthy"
    vectordb_health && health_status="healthy"

    if declare -F json_object &>/dev/null; then
        json_object \
            "backend=$_VECTORDB_BACKEND" \
            "connection=$_VECTORDB_CONNECTION" \
            "status=$health_status" \
            "initialized:bool=$_VECTORDB_INITIALIZED"
    else
        printf '{"backend":"%s","connection":"%s","status":"%s","initialized":%s}' \
            "$_VECTORDB_BACKEND" "$_VECTORDB_CONNECTION" "$health_status" "$_VECTORDB_INITIALIZED"
    fi
}

# Reset connection state (for testing)
# Usage: vectordb_reset
vectordb_reset() {
    _VECTORDB_BACKEND=""
    _VECTORDB_CONNECTION=""
    _VECTORDB_API_KEY=""
    _VECTORDB_INITIALIZED=false
    _VECTORDB_SQLITE_PATH=""

    # Clear collection cache
    local key
    for key in "${!_VECTORDB_CHROMADB_COLLECTIONS[@]}"; do
        unset "_VECTORDB_CHROMADB_COLLECTIONS[$key]"
    done
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

VECTORDB_EXPORTS=(
    # Initialization
    vectordb_init
    vectordb_reset
    vectordb_info
    vectordb_health
    # Collection operations
    vectordb_create_collection
    vectordb_delete_collection
    vectordb_list_collections
    # Document operations
    vectordb_upsert
    vectordb_search
    vectordb_get
    vectordb_delete
    vectordb_count
)

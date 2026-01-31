#!/usr/bin/env bash
# AWM Storage Abstraction Layer
# Provides unified interface across file, Redis, and ChromaDB backends
# Version: 2.0.0

# Prevent double-loading
[[ -n "$_AWM_STORAGE_LOADED" ]] && return 0
readonly _AWM_STORAGE_LOADED=1

# =============================================================================
# STORAGE BACKEND STATE
# =============================================================================

# Current backend (detected or configured)
_AWM_STORAGE_BACKEND=""

# Backend-specific configuration
_AWM_STORAGE_DIR=""
_AWM_REDIS_HOST=""
_AWM_REDIS_PORT=""
_AWM_CHROMADB_URL=""
_AWM_CHROMADB_COLLECTION=""

# Feature flags (set during init)
_AWM_HAS_SEMANTIC_SEARCH=0
_AWM_HAS_PUBSUB=0
_AWM_HAS_TTL=0

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize storage backend with auto-detection and fallback
# Usage: awm_storage_init
# Returns: 0 on success
awm_storage_init() {
    # Allow explicit override via environment
    if [[ -n "$MAINFRAME_STORAGE" ]]; then
        _awm_storage_init_backend "$MAINFRAME_STORAGE"
        return $?
    fi

    # Auto-detection priority: ChromaDB > Redis > File

    # Check ChromaDB (best for semantic search)
    local chromadb_url="${MAINFRAME_CHROMADB_URL:-http://localhost:8000}"
    if _awm_check_chromadb "$chromadb_url"; then
        _awm_storage_init_backend "chromadb"
        return 0
    fi

    # Check Redis Stack (port 6380) then standard Redis (port 6379)
    local redis_host="${MAINFRAME_REDIS_HOST:-localhost}"
    local redis_port="${MAINFRAME_REDIS_PORT:-6380}"

    if _awm_check_redis "$redis_host" "$redis_port"; then
        _awm_storage_init_backend "redis"
        return 0
    fi

    # Try standard Redis port as fallback
    if [[ "$redis_port" == "6380" ]] && _awm_check_redis "$redis_host" "6379"; then
        MAINFRAME_REDIS_PORT=6379
        _awm_storage_init_backend "redis"
        return 0
    fi

    # Fallback to file-based (always available)
    _awm_storage_init_backend "file"
    return 0
}

# Initialize specific backend
_awm_storage_init_backend() {
    local backend="$1"

    case "$backend" in
        chromadb)
            _AWM_STORAGE_BACKEND="chromadb"
            _AWM_CHROMADB_URL="${MAINFRAME_CHROMADB_URL:-http://localhost:8000}"
            _AWM_CHROMADB_COLLECTION="${MAINFRAME_CHROMADB_COLLECTION:-awm_memory}"
            _AWM_HAS_SEMANTIC_SEARCH=1
            _AWM_HAS_PUBSUB=0
            _AWM_HAS_TTL=0
            # Also use file backend for non-vector operations
            _awm_init_file_backend
            ;;
        redis)
            _AWM_STORAGE_BACKEND="redis"
            _AWM_REDIS_HOST="${MAINFRAME_REDIS_HOST:-localhost}"
            _AWM_REDIS_PORT="${MAINFRAME_REDIS_PORT:-6380}"
            _AWM_HAS_SEMANTIC_SEARCH=0
            _AWM_HAS_PUBSUB=1
            _AWM_HAS_TTL=1
            ;;
        file|*)
            _AWM_STORAGE_BACKEND="file"
            _awm_init_file_backend
            _AWM_HAS_SEMANTIC_SEARCH=0
            _AWM_HAS_PUBSUB=0
            _AWM_HAS_TTL=0
            ;;
    esac

    return 0
}

# Initialize file backend directories
_awm_init_file_backend() {
    _AWM_STORAGE_DIR="${MAINFRAME_AWM_DIR:-$HOME/.mainframe/awm}/store"
    mkdir -p "$_AWM_STORAGE_DIR"/{kv,lists,pubsub,index}
}

# Check if ChromaDB is available
_awm_check_chromadb() {
    local url="$1"
    # ChromaDB heartbeat endpoint
    curl -sf "${url}/api/v1/heartbeat" >/dev/null 2>&1
}

# Check if Redis is available
_awm_check_redis() {
    local host="$1"
    local port="$2"
    redis-cli -h "$host" -p "$port" ping >/dev/null 2>&1
}

# Get current backend name
# Usage: awm_storage_backend
# Returns: file|redis|chromadb
awm_storage_backend() {
    [[ -z "$_AWM_STORAGE_BACKEND" ]] && awm_storage_init
    echo "$_AWM_STORAGE_BACKEND"
}

# Get storage capabilities as JSON
# Usage: awm_storage_caps
awm_storage_caps() {
    [[ -z "$_AWM_STORAGE_BACKEND" ]] && awm_storage_init
    printf '{"backend":"%s","semantic_search":%s,"pubsub":%s,"ttl":%s}' \
        "$_AWM_STORAGE_BACKEND" \
        "$([[ $_AWM_HAS_SEMANTIC_SEARCH -eq 1 ]] && echo 'true' || echo 'false')" \
        "$([[ $_AWM_HAS_PUBSUB -eq 1 ]] && echo 'true' || echo 'false')" \
        "$([[ $_AWM_HAS_TTL -eq 1 ]] && echo 'true' || echo 'false')"
}

# =============================================================================
# KEY-VALUE OPERATIONS
# =============================================================================

# Store a value with optional TTL
# Usage: awm_store_set "key" "value" [ttl_seconds]
# Returns: 0 on success
awm_store_set() {
    local key="$1"
    local value="$2"
    local ttl="${3:-0}"

    [[ -z "$_AWM_STORAGE_BACKEND" ]] && awm_storage_init

    case "$_AWM_STORAGE_BACKEND" in
        redis)
            _awm_redis_set "$key" "$value" "$ttl"
            ;;
        chromadb|file|*)
            _awm_file_set "$key" "$value" "$ttl"
            ;;
    esac
}

# Get a value with optional default
# Usage: awm_store_get "key" [default]
# Returns: value or default
awm_store_get() {
    local key="$1"
    local default="${2:-}"

    [[ -z "$_AWM_STORAGE_BACKEND" ]] && awm_storage_init

    local result
    case "$_AWM_STORAGE_BACKEND" in
        redis)
            result=$(_awm_redis_get "$key")
            ;;
        chromadb|file|*)
            result=$(_awm_file_get "$key")
            ;;
    esac

    if [[ -z "$result" ]]; then
        echo "$default"
    else
        echo "$result"
    fi
}

# Delete a key
# Usage: awm_store_delete "key"
# Returns: 0 on success
awm_store_delete() {
    local key="$1"

    [[ -z "$_AWM_STORAGE_BACKEND" ]] && awm_storage_init

    case "$_AWM_STORAGE_BACKEND" in
        redis)
            _awm_redis_delete "$key"
            ;;
        chromadb|file|*)
            _awm_file_delete "$key"
            ;;
    esac
}

# Check if key exists
# Usage: awm_store_exists "key"
# Returns: 0 if exists, 1 if not
awm_store_exists() {
    local key="$1"

    [[ -z "$_AWM_STORAGE_BACKEND" ]] && awm_storage_init

    case "$_AWM_STORAGE_BACKEND" in
        redis)
            _awm_redis_exists "$key"
            ;;
        chromadb|file|*)
            _awm_file_exists "$key"
            ;;
    esac
}

# =============================================================================
# LIST/QUEUE OPERATIONS
# =============================================================================

# Append value to list
# Usage: awm_store_push "list" "value"
awm_store_push() {
    local list="$1"
    local value="$2"

    [[ -z "$_AWM_STORAGE_BACKEND" ]] && awm_storage_init

    case "$_AWM_STORAGE_BACKEND" in
        redis)
            _awm_redis_push "$list" "$value"
            ;;
        chromadb|file|*)
            _awm_file_push "$list" "$value"
            ;;
    esac
}

# Pop first value from list
# Usage: awm_store_pop "list"
# Returns: value or empty
awm_store_pop() {
    local list="$1"

    [[ -z "$_AWM_STORAGE_BACKEND" ]] && awm_storage_init

    case "$_AWM_STORAGE_BACKEND" in
        redis)
            _awm_redis_pop "$list"
            ;;
        chromadb|file|*)
            _awm_file_pop "$list"
            ;;
    esac
}

# Get range of list elements
# Usage: awm_store_range "list" start end
# Returns: JSON array of values
awm_store_range() {
    local list="$1"
    local start="${2:-0}"
    local end="${3:--1}"

    [[ -z "$_AWM_STORAGE_BACKEND" ]] && awm_storage_init

    case "$_AWM_STORAGE_BACKEND" in
        redis)
            _awm_redis_range "$list" "$start" "$end"
            ;;
        chromadb|file|*)
            _awm_file_range "$list" "$start" "$end"
            ;;
    esac
}

# Get list length
# Usage: awm_store_len "list"
# Returns: integer count
awm_store_len() {
    local list="$1"

    [[ -z "$_AWM_STORAGE_BACKEND" ]] && awm_storage_init

    case "$_AWM_STORAGE_BACKEND" in
        redis)
            _awm_redis_len "$list"
            ;;
        chromadb|file|*)
            _awm_file_len "$list"
            ;;
    esac
}

# =============================================================================
# SEARCH OPERATIONS
# =============================================================================

# Semantic search (falls back to text grep)
# Usage: awm_store_search "query" [limit]
# Returns: JSON array of {key, content, score}
awm_store_search() {
    local query="$1"
    local limit="${2:-10}"

    [[ -z "$_AWM_STORAGE_BACKEND" ]] && awm_storage_init

    if [[ $_AWM_HAS_SEMANTIC_SEARCH -eq 1 ]]; then
        _awm_chromadb_search "$query" "$limit"
    else
        _awm_file_search "$query" "$limit"
    fi
}

# Add content to search index
# Usage: awm_store_index "key" "content" [metadata_json]
awm_store_index() {
    local key="$1"
    local content="$2"
    local metadata="${3:-{}}"

    [[ -z "$_AWM_STORAGE_BACKEND" ]] && awm_storage_init

    if [[ $_AWM_HAS_SEMANTIC_SEARCH -eq 1 ]]; then
        _awm_chromadb_index "$key" "$content" "$metadata"
    else
        _awm_file_index "$key" "$content" "$metadata"
    fi
}

# =============================================================================
# PUB/SUB OPERATIONS
# =============================================================================

# Publish message to channel
# Usage: awm_store_publish "channel" "message"
awm_store_publish() {
    local channel="$1"
    local message="$2"

    [[ -z "$_AWM_STORAGE_BACKEND" ]] && awm_storage_init

    if [[ $_AWM_HAS_PUBSUB -eq 1 ]]; then
        _awm_redis_publish "$channel" "$message"
    else
        _awm_file_publish "$channel" "$message"
    fi
}

# Subscribe to channel (blocking)
# Usage: awm_store_subscribe "channel" callback_function [timeout]
awm_store_subscribe() {
    local channel="$1"
    local callback="$2"
    local timeout="${3:-0}"

    [[ -z "$_AWM_STORAGE_BACKEND" ]] && awm_storage_init

    if [[ $_AWM_HAS_PUBSUB -eq 1 ]]; then
        _awm_redis_subscribe "$channel" "$callback" "$timeout"
    else
        _awm_file_subscribe "$channel" "$callback" "$timeout"
    fi
}

# =============================================================================
# FILE BACKEND IMPLEMENTATION
# =============================================================================

_awm_file_set() {
    local key="$1"
    local value="$2"
    local ttl="$3"

    local key_hash
    key_hash=$(echo -n "$key" | sha256sum | cut -c1-16)
    local file="$_AWM_STORAGE_DIR/kv/$key_hash"

    # Atomic write via temp file
    local tmp="${file}.tmp.$$"
    local expire_at=0
    [[ "$ttl" -gt 0 ]] && expire_at=$(($(date +%s) + ttl))

    # Format: expire_at\nvalue
    printf '%d\n%s' "$expire_at" "$value" > "$tmp"
    mv -f "$tmp" "$file"
}

_awm_file_get() {
    local key="$1"

    local key_hash
    key_hash=$(echo -n "$key" | sha256sum | cut -c1-16)
    local file="$_AWM_STORAGE_DIR/kv/$key_hash"

    [[ ! -f "$file" ]] && return 0

    # Read expire time (first line)
    local expire_at
    expire_at=$(head -1 "$file")

    # Check TTL
    if [[ "$expire_at" -gt 0 ]] && [[ "$expire_at" -lt $(date +%s) ]]; then
        rm -f "$file"
        return 0
    fi

    # Return value (everything after first line)
    tail -n +2 "$file"
}

_awm_file_delete() {
    local key="$1"

    local key_hash
    key_hash=$(echo -n "$key" | sha256sum | cut -c1-16)
    rm -f "$_AWM_STORAGE_DIR/kv/$key_hash"
}

_awm_file_exists() {
    local key="$1"

    local key_hash
    key_hash=$(echo -n "$key" | sha256sum | cut -c1-16)
    local file="$_AWM_STORAGE_DIR/kv/$key_hash"

    [[ -f "$file" ]] || return 1

    # Check TTL
    local expire_at
    expire_at=$(head -1 "$file")
    if [[ "$expire_at" -gt 0 ]] && [[ "$expire_at" -lt $(date +%s) ]]; then
        rm -f "$file"
        return 1
    fi

    return 0
}

_awm_file_push() {
    local list="$1"
    local value="$2"

    local list_hash
    list_hash=$(echo -n "$list" | sha256sum | cut -c1-16)
    local file="$_AWM_STORAGE_DIR/lists/$list_hash"

    # Append with newline delimiter (handle multiline via base64)
    local encoded
    encoded=$(echo -n "$value" | base64 -w 0)
    echo "$encoded" >> "$file"
}

_awm_file_pop() {
    local list="$1"

    local list_hash
    list_hash=$(echo -n "$list" | sha256sum | cut -c1-16)
    local file="$_AWM_STORAGE_DIR/lists/$list_hash"

    [[ ! -f "$file" ]] && return 0

    # Get and remove first line (atomic via lock)
    (
        flock -x 200
        local first
        first=$(head -1 "$file")
        tail -n +2 "$file" > "${file}.tmp"
        mv -f "${file}.tmp" "$file"
        echo -n "$first" | base64 -d
    ) 200>"${file}.lock"
}

_awm_file_range() {
    local list="$1"
    local start="$2"
    local end="$3"

    local list_hash
    list_hash=$(echo -n "$list" | sha256sum | cut -c1-16)
    local file="$_AWM_STORAGE_DIR/lists/$list_hash"

    [[ ! -f "$file" ]] && echo '[]' && return 0

    local total
    total=$(wc -l < "$file")

    # Handle negative indices
    [[ "$end" -lt 0 ]] && end=$((total + end + 1))
    [[ "$start" -lt 0 ]] && start=$((total + start + 1))

    # Convert to 1-indexed for sed
    local start_line=$((start + 1))
    local end_line=$((end + 1))

    # Build JSON array
    echo -n '['
    local first=1
    sed -n "${start_line},${end_line}p" "$file" | while IFS= read -r encoded; do
        [[ $first -eq 0 ]] && echo -n ','
        first=0
        local decoded
        decoded=$(echo -n "$encoded" | base64 -d)
        # Escape for JSON
        printf '%s' "$decoded" | jq -Rs .
    done
    echo ']'
}

_awm_file_len() {
    local list="$1"

    local list_hash
    list_hash=$(echo -n "$list" | sha256sum | cut -c1-16)
    local file="$_AWM_STORAGE_DIR/lists/$list_hash"

    [[ ! -f "$file" ]] && echo 0 && return 0

    wc -l < "$file"
}

_awm_file_search() {
    local query="$1"
    local limit="$2"

    local index_dir="$_AWM_STORAGE_DIR/index"

    [[ ! -d "$index_dir" ]] && echo '[]' && return 0

    # Simple grep-based search with scoring
    local results='['
    local first=1
    local count=0

    grep -rl "$query" "$index_dir" 2>/dev/null | head -n "$limit" | while read -r file; do
        [[ $count -ge $limit ]] && break

        local key
        key=$(basename "$file")
        local content
        content=$(cat "$file")

        # Simple score: count of query occurrences
        local score
        score=$(grep -c "$query" "$file" 2>/dev/null || echo 0)

        [[ $first -eq 0 ]] && results+=','
        first=0

        results+=$(printf '{"key":"%s","score":%d,"content":%s}' \
            "$key" "$score" "$(echo "$content" | jq -Rs .)")

        ((count++))
    done

    echo "${results}]"
}

_awm_file_index() {
    local key="$1"
    local content="$2"
    local metadata="$3"

    local key_hash
    key_hash=$(echo -n "$key" | sha256sum | cut -c1-16)
    local file="$_AWM_STORAGE_DIR/index/$key_hash"

    # Store content with metadata header
    printf '%s\n%s' "$metadata" "$content" > "$file"
}

_awm_file_publish() {
    local channel="$1"
    local message="$2"

    local channel_hash
    channel_hash=$(echo -n "$channel" | sha256sum | cut -c1-16)
    local channel_dir="$_AWM_STORAGE_DIR/pubsub/$channel_hash"
    mkdir -p "$channel_dir"

    # Create timestamped message file
    local msg_file="$channel_dir/$(date +%s%N)"
    echo "$message" > "$msg_file"
}

_awm_file_subscribe() {
    local channel="$1"
    local callback="$2"
    local timeout="$3"

    local channel_hash
    channel_hash=$(echo -n "$channel" | sha256sum | cut -c1-16)
    local channel_dir="$_AWM_STORAGE_DIR/pubsub/$channel_hash"
    mkdir -p "$channel_dir"

    local start_time
    start_time=$(date +%s)
    local last_seen=""

    while true; do
        # Check timeout
        if [[ "$timeout" -gt 0 ]]; then
            local elapsed=$(($(date +%s) - start_time))
            [[ $elapsed -ge $timeout ]] && break
        fi

        # Find new messages
        local newest
        newest=$(ls -t "$channel_dir" 2>/dev/null | head -1)

        if [[ -n "$newest" ]] && [[ "$newest" != "$last_seen" ]]; then
            local message
            message=$(cat "$channel_dir/$newest")
            $callback "$message"
            last_seen="$newest"

            # Cleanup old messages (keep last 100)
            ls -t "$channel_dir" | tail -n +101 | xargs -I {} rm -f "$channel_dir/{}"
        fi

        sleep 0.1
    done
}

# =============================================================================
# REDIS BACKEND IMPLEMENTATION
# =============================================================================

_awm_redis_cmd() {
    redis-cli -h "$_AWM_REDIS_HOST" -p "$_AWM_REDIS_PORT" "$@"
}

_awm_redis_set() {
    local key="$1"
    local value="$2"
    local ttl="$3"

    if [[ "$ttl" -gt 0 ]]; then
        _awm_redis_cmd SET "awm:$key" "$value" EX "$ttl" >/dev/null
    else
        _awm_redis_cmd SET "awm:$key" "$value" >/dev/null
    fi
}

_awm_redis_get() {
    _awm_redis_cmd GET "awm:$1"
}

_awm_redis_delete() {
    _awm_redis_cmd DEL "awm:$1" >/dev/null
}

_awm_redis_exists() {
    local result
    result=$(_awm_redis_cmd EXISTS "awm:$1")
    [[ "$result" == "1" ]]
}

_awm_redis_push() {
    _awm_redis_cmd RPUSH "awm:list:$1" "$2" >/dev/null
}

_awm_redis_pop() {
    _awm_redis_cmd LPOP "awm:list:$1"
}

_awm_redis_range() {
    local list="$1"
    local start="$2"
    local end="$3"

    # Get range and format as JSON array
    local results
    results=$(_awm_redis_cmd LRANGE "awm:list:$list" "$start" "$end")

    echo -n '['
    local first=1
    echo "$results" | while IFS= read -r item; do
        [[ -z "$item" ]] && continue
        [[ $first -eq 0 ]] && echo -n ','
        first=0
        printf '%s' "$item" | jq -Rs .
    done
    echo ']'
}

_awm_redis_len() {
    _awm_redis_cmd LLEN "awm:list:$1"
}

_awm_redis_publish() {
    _awm_redis_cmd PUBLISH "awm:channel:$1" "$2" >/dev/null
}

_awm_redis_subscribe() {
    local channel="$1"
    local callback="$2"
    local timeout="$3"

    local timeout_opt=""
    [[ "$timeout" -gt 0 ]] && timeout_opt="--timeout $timeout"

    # shellcheck disable=SC2086
    _awm_redis_cmd $timeout_opt SUBSCRIBE "awm:channel:$channel" | while read -r type; do
        read -r ch
        read -r message
        [[ "$type" == "message" ]] && $callback "$message"
    done
}

# =============================================================================
# CHROMADB BACKEND IMPLEMENTATION
# =============================================================================

_awm_chromadb_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    if [[ -n "$data" ]]; then
        curl -sf -X "$method" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "${_AWM_CHROMADB_URL}${endpoint}"
    else
        curl -sf -X "$method" \
            "${_AWM_CHROMADB_URL}${endpoint}"
    fi
}

_awm_chromadb_ensure_collection() {
    # Create collection if it doesn't exist
    _awm_chromadb_api POST "/api/v1/collections" \
        "{\"name\":\"${_AWM_CHROMADB_COLLECTION}\",\"metadata\":{\"hnsw:space\":\"cosine\"}}" \
        >/dev/null 2>&1 || true
}

_awm_chromadb_search() {
    local query="$1"
    local limit="$2"

    _awm_chromadb_ensure_collection

    # Query using text (ChromaDB will embed)
    local result
    result=$(_awm_chromadb_api POST \
        "/api/v1/collections/${_AWM_CHROMADB_COLLECTION}/query" \
        "{\"query_texts\":[\"$query\"],\"n_results\":$limit,\"include\":[\"documents\",\"metadatas\",\"distances\"]}")

    # Transform to our format
    echo "$result" | jq '[
        range(0; (.ids[0] // []) | length) |
        {
            key: .ids[0][.],
            content: .documents[0][.],
            score: (1 - .distances[0][.]),
            metadata: .metadatas[0][.]
        }
    ]'
}

_awm_chromadb_index() {
    local key="$1"
    local content="$2"
    local metadata="$3"

    _awm_chromadb_ensure_collection

    # Upsert document
    _awm_chromadb_api POST \
        "/api/v1/collections/${_AWM_CHROMADB_COLLECTION}/upsert" \
        "{\"ids\":[\"$key\"],\"documents\":[$(echo "$content" | jq -Rs .)],\"metadatas\":[$metadata]}" \
        >/dev/null
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Clear all storage (use with caution)
awm_storage_clear() {
    [[ -z "$_AWM_STORAGE_BACKEND" ]] && awm_storage_init

    case "$_AWM_STORAGE_BACKEND" in
        redis)
            _awm_redis_cmd KEYS "awm:*" | xargs -r _awm_redis_cmd DEL
            ;;
        file|chromadb)
            rm -rf "$_AWM_STORAGE_DIR"/*
            ;;
    esac
}

# Get storage statistics
awm_storage_stats() {
    [[ -z "$_AWM_STORAGE_BACKEND" ]] && awm_storage_init

    local kv_count=0
    local list_count=0
    local index_count=0
    local total_size=0

    case "$_AWM_STORAGE_BACKEND" in
        redis)
            kv_count=$(_awm_redis_cmd KEYS "awm:*" | grep -v "list:" | grep -v "channel:" | wc -l)
            list_count=$(_awm_redis_cmd KEYS "awm:list:*" | wc -l)
            total_size=$(_awm_redis_cmd INFO memory | grep used_memory: | cut -d: -f2 | tr -d '\r')
            ;;
        file|chromadb)
            kv_count=$(find "$_AWM_STORAGE_DIR/kv" -type f 2>/dev/null | wc -l)
            list_count=$(find "$_AWM_STORAGE_DIR/lists" -type f 2>/dev/null | wc -l)
            index_count=$(find "$_AWM_STORAGE_DIR/index" -type f 2>/dev/null | wc -l)
            total_size=$(du -sb "$_AWM_STORAGE_DIR" 2>/dev/null | cut -f1)
            ;;
    esac

    printf '{"backend":"%s","kv_count":%d,"list_count":%d,"index_count":%d,"total_bytes":%d}' \
        "$_AWM_STORAGE_BACKEND" "$kv_count" "$list_count" "$index_count" "${total_size:-0}"
}

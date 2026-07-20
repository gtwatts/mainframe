#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/embeddings.sh - Embedding Generation for Semantic Search
# =============================================================================
# Description: Generate embedding vectors for semantic search and RAG workflows.
#              Supports OpenAI, Ollama, and local TF-IDF fallback providers.
# Version: 1.0.0
# Requires: Bash 4.0+, curl (for API calls), jq (optional, for JSON parsing)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================
#
# Usage: source embeddings.sh
#
# Examples:
#   # Generate embedding with OpenAI
#   vector=$(embed_text "hello world" "openai")
#
#   # Batch embed from file
#   embeddings=$(embed_batch "texts.txt" "ollama")
#
#   # Calculate similarity
#   similarity=$(embed_similarity "$vec1" "$vec2")
#
#   # Get provider dimensions
#   dims=$(embed_dimensions "openai")
#
# Provider Configuration:
#   OPENAI_API_KEY    - Required for OpenAI provider
#   OLLAMA_HOST       - Ollama server URL (default: http://localhost:11434)
#   EMBED_MODEL       - Override default model per provider
#   EMBED_CACHE_DIR   - Cache directory (default: ~/.mainframe/cache/embeddings)
#   EMBED_CACHE_TTL   - Cache TTL in seconds (default: 86400 = 24h)
#
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_EMBEDDINGS_LOADED:-}" ]] && return 0
readonly _MAINFRAME_EMBEDDINGS_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Provider defaults
readonly EMBED_OPENAI_URL="https://api.openai.com/v1/embeddings"
readonly EMBED_OLLAMA_DEFAULT_HOST="http://localhost:11434"

# Model defaults by provider
readonly EMBED_OPENAI_DEFAULT_MODEL="text-embedding-ada-002"
readonly EMBED_OLLAMA_DEFAULT_MODEL="nomic-embed-text"
readonly EMBED_LOCAL_DEFAULT_DIMS=384

# Dimensions by model
declare -gA EMBED_MODEL_DIMS=(
    # OpenAI models
    ["text-embedding-ada-002"]=1536
    ["text-embedding-3-small"]=1536
    ["text-embedding-3-large"]=3072
    # Ollama models
    ["nomic-embed-text"]=768
    ["all-minilm"]=384
    ["mxbai-embed-large"]=1024
    # Local fallback
    ["local"]=384
)

# Token limits by model (approximate)
declare -gA EMBED_MODEL_TOKEN_LIMITS=(
    ["text-embedding-ada-002"]=8191
    ["text-embedding-3-small"]=8191
    ["text-embedding-3-large"]=8191
    ["nomic-embed-text"]=8192
    ["all-minilm"]=512
    ["mxbai-embed-large"]=512
    ["local"]=2048
)

# Cache configuration
EMBED_CACHE_DIR="${EMBED_CACHE_DIR:-$HOME/.mainframe/cache/embeddings}"
EMBED_CACHE_TTL="${EMBED_CACHE_TTL:-86400}"

# Internal state
declare -gi _EMBED_CACHE_HITS=0
declare -gi _EMBED_CACHE_MISSES=0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Delegate to centralized logging (with fallback for standalone testing)
_embed_log() {
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "embeddings" "$@"
    else
        local level="$1"; shift
        [[ "${MAINFRAME_QUIET:-}" != "1" ]] && printf '[embeddings] %s: %s\n' "$level" "$*" >&2
        :
    fi
}

# Get epoch seconds
_embed_epoch() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    elif printf -v _ts '%(%s)T' -1 2>/dev/null && [[ -n "$_ts" ]]; then
        printf '%s' "$_ts"
    else
        date +%s
    fi
}

# Compute SHA-256 hash for cache key
_embed_hash() {
    local input="$1"
    if type -p sha256sum &>/dev/null; then
        printf '%s' "$input" | sha256sum | cut -d' ' -f1
    elif type -p shasum &>/dev/null; then
        printf '%s' "$input" | shasum -a 256 | cut -d' ' -f1
    elif type -p openssl &>/dev/null; then
        printf '%s' "$input" | openssl dgst -sha256 | awk '{print $NF}'
    else
        # Fallback: simple hash using cksum
        printf '%s' "$input" | cksum | awk '{print $1}'
    fi
}

# Ensure cache directory exists
_embed_ensure_cache_dir() {
    mkdir -p "$EMBED_CACHE_DIR" 2>/dev/null
}

# JSON escape string (pure bash)
_embed_json_escape() {
    local str="$1"
    local result=""
    local i char

    for ((i=0; i<${#str}; i++)); do
        char="${str:i:1}"
        case "$char" in
            '"')  result+='\"' ;;
            '\')  result+='\\' ;;
            $'\b') result+='\b' ;;
            $'\f') result+='\f' ;;
            $'\n') result+='\n' ;;
            $'\r') result+='\r' ;;
            $'\t') result+='\t' ;;
            *)
                if [[ "$char" < $'\x20' ]]; then
                    printf -v char '\\u%04x' "'$char"
                fi
                result+="$char"
                ;;
        esac
    done

    printf '%s' "$result"
}

# Extract JSON array value using regex (no jq dependency)
_embed_json_get_array() {
    local json="$1"
    local key="$2"

    # Pattern: "key":[...]
    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*\[([^\]]*)\] ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

# Extract simple JSON string value
_embed_json_get_string() {
    local json="$1"
    local key="$2"

    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

# Validate provider name
_embed_validate_provider() {
    local provider="$1"
    case "$provider" in
        openai|ollama|local) return 0 ;;
        *)
            _embed_log error "Unknown provider: $provider (valid: openai, ollama, local)"
            return 1
            ;;
    esac
}

# Get model for provider
_embed_get_model() {
    local provider="$1"

    # Check for override
    if [[ -n "${EMBED_MODEL:-}" ]]; then
        printf '%s' "$EMBED_MODEL"
        return
    fi

    case "$provider" in
        openai) printf '%s' "$EMBED_OPENAI_DEFAULT_MODEL" ;;
        ollama) printf '%s' "$EMBED_OLLAMA_DEFAULT_MODEL" ;;
        local)  printf '%s' "local" ;;
    esac
}

# =============================================================================
# CACHE FUNCTIONS
# =============================================================================

# @pre: text_hash is a valid hash string
# @post: cached embedding printed to stdout if found and not expired
# @returns: 0 if cache hit, 1 if cache miss
#
# Get cached embedding by text hash.
#
# Usage: embed_cache_get TEXT_HASH
# Example: cached=$(embed_cache_get "abc123...")
embed_cache_get() {
    local text_hash="$1"

    if [[ -z "$text_hash" ]]; then
        return 1
    fi

    local cache_file="${EMBED_CACHE_DIR}/${text_hash}.json"
    local meta_file="${EMBED_CACHE_DIR}/${text_hash}.meta"

    # Check if cache files exist
    if [[ ! -f "$cache_file" ]] || [[ ! -f "$meta_file" ]]; then
        return 1
    fi

    # Check TTL expiration
    local now meta_content timestamp
    now=$(_embed_epoch)

    meta_content=$(< "$meta_file")
    if [[ "$meta_content" =~ timestamp[[:space:]]*=[[:space:]]*([0-9]+) ]]; then
        timestamp="${BASH_REMATCH[1]}"
    else
        return 1
    fi

    local age=$((now - timestamp))
    if [[ $age -ge $EMBED_CACHE_TTL ]]; then
        # Expired
        return 1
    fi

    # Cache hit
    _EMBED_CACHE_HITS=$((_EMBED_CACHE_HITS + 1))
    cat "$cache_file"
    return 0
}

# @pre: text_hash is a valid hash string, vector is a JSON array string
# @post: embedding cached to disk with metadata
# @returns: 0 on success
#
# Cache embedding vector by text hash.
#
# Usage: embed_cache_set TEXT_HASH VECTOR [PROVIDER] [MODEL]
# Example: embed_cache_set "abc123..." "[0.1, 0.2, ...]" "openai" "text-embedding-ada-002"
embed_cache_set() {
    local text_hash="$1"
    local vector="$2"
    local provider="${3:-unknown}"
    local model="${4:-unknown}"

    if [[ -z "$text_hash" ]] || [[ -z "$vector" ]]; then
        _embed_log error "embed_cache_set: hash and vector required"
        return 1
    fi

    _embed_ensure_cache_dir

    local cache_file="${EMBED_CACHE_DIR}/${text_hash}.json"
    local meta_file="${EMBED_CACHE_DIR}/${text_hash}.meta"
    local now
    now=$(_embed_epoch)

    # Write vector
    printf '%s' "$vector" > "$cache_file"

    # Write metadata
    printf 'timestamp=%s\nprovider=%s\nmodel=%s\n' "$now" "$provider" "$model" > "$meta_file"

    return 0
}

# @pre: none
# @post: all embedding cache files removed
# @returns: 0, number of removed entries printed
#
# Clear all cached embeddings.
#
# Usage: embed_cache_clear
embed_cache_clear() {
    local count=0

    if [[ ! -d "$EMBED_CACHE_DIR" ]]; then
        printf '0'
        return 0
    fi

    local file
    while IFS= read -r -d '' file; do
        rm -f "$file" 2>/dev/null
        count=$((count + 1))
    done < <(find "$EMBED_CACHE_DIR" -type f \( -name "*.json" -o -name "*.meta" \) -print0 2>/dev/null)

    # Reset stats
    _EMBED_CACHE_HITS=0
    _EMBED_CACHE_MISSES=0

    # Count is for .json files only (each entry has .json and .meta)
    printf '%s' "$((count / 2))"
    return 0
}

# =============================================================================
# PROVIDER IMPLEMENTATIONS
# =============================================================================

# OpenAI embedding API call
_embed_openai() {
    local text="$1"
    local model="$2"

    # Require API key
    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        _embed_log error "OPENAI_API_KEY not set"
        return 1
    fi

    # Build request JSON
    local escaped_text
    escaped_text=$(_embed_json_escape "$text")
    local request_body
    request_body=$(printf '{"input":"%s","model":"%s"}' "$escaped_text" "$model")

    # Make API call
    local response http_code
    response=$(curl -s -w "\n%{http_code}" \
        -X POST "$EMBED_OPENAI_URL" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$request_body" 2>/dev/null)

    # Extract HTTP code from last line
    http_code=$(printf '%s' "$response" | tail -n1)
    response=$(printf '%s' "$response" | sed '$d')

    if [[ "$http_code" != "200" ]]; then
        local error_msg
        error_msg=$(_embed_json_get_string "$response" "message")
        _embed_log error "OpenAI API error ($http_code): ${error_msg:-unknown error}"
        return 1
    fi

    # Extract embedding array
    # Response format: {"data":[{"embedding":[...]}]}
    local embedding
    if [[ "$response" =~ \"embedding\"[[:space:]]*:[[:space:]]*\[([^\]]+)\] ]]; then
        embedding="${BASH_REMATCH[1]}"
        printf '[%s]' "$embedding"
        return 0
    fi

    _embed_log error "Failed to parse OpenAI response"
    return 1
}

# Ollama embedding API call
_embed_ollama() {
    local text="$1"
    local model="$2"
    local host="${OLLAMA_HOST:-$EMBED_OLLAMA_DEFAULT_HOST}"

    # Build request JSON
    local escaped_text
    escaped_text=$(_embed_json_escape "$text")
    local request_body
    request_body=$(printf '{"model":"%s","prompt":"%s"}' "$model" "$escaped_text")

    # Make API call
    local response http_code
    response=$(curl -s -w "\n%{http_code}" \
        -X POST "${host}/api/embeddings" \
        -H "Content-Type: application/json" \
        -d "$request_body" 2>/dev/null)

    # Extract HTTP code
    http_code=$(printf '%s' "$response" | tail -n1)
    response=$(printf '%s' "$response" | sed '$d')

    if [[ "$http_code" != "200" ]]; then
        local error_msg
        error_msg=$(_embed_json_get_string "$response" "error")
        _embed_log error "Ollama API error ($http_code): ${error_msg:-unknown error}"
        return 1
    fi

    # Extract embedding array
    # Response format: {"embedding":[...]}
    local embedding
    if [[ "$response" =~ \"embedding\"[[:space:]]*:[[:space:]]*\[([^\]]+)\] ]]; then
        embedding="${BASH_REMATCH[1]}"
        printf '[%s]' "$embedding"
        return 0
    fi

    _embed_log error "Failed to parse Ollama response"
    return 1
}

# Local TF-IDF style embedding (fallback when no API available)
# This produces a simple bag-of-words vector with term frequency weighting
_embed_local() {
    local text="$1"
    local dims="${2:-$EMBED_LOCAL_DEFAULT_DIMS}"

    # Normalize text: lowercase, remove punctuation
    local normalized
    normalized=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' ' ')

    # Generate pseudo-embedding using hash-based feature hashing
    # Each word contributes to a specific dimension based on its hash
    local -a vector=()
    local i
    for ((i=0; i<dims; i++)); do
        vector+=("0.0")
    done

    # Process words
    local word word_hash dim_idx weight
    for word in $normalized; do
        [[ -z "$word" ]] && continue

        # Hash word to get dimension index
        word_hash=$(_embed_hash "$word")
        # Convert first 8 hex chars to decimal and mod by dims
        dim_idx=$(( 16#${word_hash:0:8} % dims ))

        # Get current value and add weight (simple TF)
        local current="${vector[$dim_idx]}"
        # Use bc for floating point, or fallback to integer
        if type -p bc &>/dev/null; then
            weight=$(printf 'scale=6; %s + 0.1\n' "$current" | bc)
        else
            weight=$(printf '%.6f' "$(echo "$current + 0.1" | awk '{print $1 + 0.1}')")
        fi
        vector[$dim_idx]="$weight"
    done

    # Normalize the vector to unit length
    local sum_sq=0
    for ((i=0; i<dims; i++)); do
        if type -p bc &>/dev/null; then
            sum_sq=$(printf 'scale=10; %s + %s * %s\n' "$sum_sq" "${vector[$i]}" "${vector[$i]}" | bc)
        else
            sum_sq=$(awk -v s="$sum_sq" -v v="${vector[$i]}" 'BEGIN {print s + v*v}')
        fi
    done

    local magnitude
    if type -p bc &>/dev/null; then
        magnitude=$(printf 'scale=10; sqrt(%s)\n' "$sum_sq" | bc)
    else
        magnitude=$(awk -v s="$sum_sq" 'BEGIN {print sqrt(s)}')
    fi

    # Avoid division by zero
    if [[ "$magnitude" == "0" ]] || [[ -z "$magnitude" ]]; then
        magnitude="1"
    fi

    # Normalize and output
    printf '['
    for ((i=0; i<dims; i++)); do
        [[ $i -gt 0 ]] && printf ','
        if type -p bc &>/dev/null; then
            printf '%.6f' "$(printf 'scale=6; %s / %s\n' "${vector[$i]}" "$magnitude" | bc)"
        else
            printf '%.6f' "$(awk -v v="${vector[$i]}" -v m="$magnitude" 'BEGIN {print v/m}')"
        fi
    done
    printf ']'

    return 0
}

# =============================================================================
# PUBLIC API
# =============================================================================

# @pre: content is a non-empty string
# @post: embedding vector printed to stdout as JSON array
# @returns: 0 on success, 1 on failure
#
# Generate embedding vector for text content.
# Uses caching to avoid redundant API calls.
#
# Usage: embed_text CONTENT [PROVIDER]
# Example: vector=$(embed_text "hello world" "openai")
# Example: vector=$(embed_text "semantic search" "ollama")
# Example: vector=$(embed_text "fallback mode" "local")
embed_text() {
    local content="$1"
    local provider="${2:-ollama}"

    if [[ -z "$content" ]]; then
        _embed_log error "embed_text: content required"
        return 1
    fi

    _embed_validate_provider "$provider" || return 1

    local model
    model=$(_embed_get_model "$provider")

    # Check cache first
    local cache_key
    cache_key=$(_embed_hash "${provider}:${model}:${content}")

    local cached
    if cached=$(embed_cache_get "$cache_key"); then
        printf '%s' "$cached"
        return 0
    fi

    # Cache miss
    _EMBED_CACHE_MISSES=$((_EMBED_CACHE_MISSES + 1))

    # Generate embedding based on provider
    local vector
    case "$provider" in
        openai)
            vector=$(_embed_openai "$content" "$model") || return 1
            ;;
        ollama)
            vector=$(_embed_ollama "$content" "$model") || return 1
            ;;
        local)
            vector=$(_embed_local "$content") || return 1
            ;;
    esac

    # Cache the result
    embed_cache_set "$cache_key" "$vector" "$provider" "$model"

    printf '%s' "$vector"
    return 0
}

# @pre: file exists and is readable, contains one text per line
# @post: JSONL output with embeddings, one per line
# @returns: 0 on success, 1 on failure
#
# Batch embed lines from a file.
# Each line is embedded separately and output as JSONL.
#
# Usage: embed_batch FILE [PROVIDER]
# Example: embed_batch "texts.txt" "ollama"
# Output format: {"text":"original text","embedding":[...]}
embed_batch() {
    local file="$1"
    local provider="${2:-ollama}"

    if [[ ! -f "$file" ]]; then
        _embed_log error "embed_batch: file not found: $file"
        return 1
    fi

    _embed_validate_provider "$provider" || return 1

    local line line_num=0 errors=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))

        # Skip empty lines
        [[ -z "${line// /}" ]] && continue

        local escaped_text vector
        escaped_text=$(_embed_json_escape "$line")

        if vector=$(embed_text "$line" "$provider"); then
            printf '{"text":"%s","embedding":%s}\n' "$escaped_text" "$vector"
        else
            _embed_log warn "Failed to embed line $line_num"
            errors=$((errors + 1))
        fi
    done < "$file"

    if [[ $errors -gt 0 ]]; then
        _embed_log warn "Batch completed with $errors errors"
    fi

    return 0
}

# @pre: vec1_json and vec2_json are valid JSON arrays of numbers
# @post: cosine similarity printed to stdout (value between -1 and 1)
# @returns: 0 on success, 1 on failure
#
# Calculate cosine similarity between two embedding vectors.
#
# Usage: embed_similarity VEC1_JSON VEC2_JSON
# Example: similarity=$(embed_similarity "[0.1,0.2,0.3]" "[0.2,0.3,0.4]")
embed_similarity() {
    local vec1_json="$1"
    local vec2_json="$2"

    if [[ -z "$vec1_json" ]] || [[ -z "$vec2_json" ]]; then
        _embed_log error "embed_similarity: two vectors required"
        return 1
    fi

    # Parse vectors - remove brackets and split by comma
    local vec1_str="${vec1_json#[}"
    vec1_str="${vec1_str%]}"
    local vec2_str="${vec2_json#[}"
    vec2_str="${vec2_str%]}"

    # Convert to arrays
    local IFS=','
    local -a vec1=($vec1_str)
    local -a vec2=($vec2_str)

    # Check dimensions match
    if [[ ${#vec1[@]} -ne ${#vec2[@]} ]]; then
        _embed_log error "embed_similarity: vector dimensions must match (${#vec1[@]} vs ${#vec2[@]})"
        return 1
    fi

    # Calculate dot product and magnitudes
    local dot_product=0 mag1=0 mag2=0
    local i v1 v2

    for ((i=0; i<${#vec1[@]}; i++)); do
        v1="${vec1[$i]// /}"
        v2="${vec2[$i]// /}"

        if type -p bc &>/dev/null; then
            dot_product=$(printf 'scale=10; %s + %s * %s\n' "$dot_product" "$v1" "$v2" | bc)
            mag1=$(printf 'scale=10; %s + %s * %s\n' "$mag1" "$v1" "$v1" | bc)
            mag2=$(printf 'scale=10; %s + %s * %s\n' "$mag2" "$v2" "$v2" | bc)
        else
            dot_product=$(awk -v d="$dot_product" -v a="$v1" -v b="$v2" 'BEGIN {print d + a*b}')
            mag1=$(awk -v m="$mag1" -v v="$v1" 'BEGIN {print m + v*v}')
            mag2=$(awk -v m="$mag2" -v v="$v2" 'BEGIN {print m + v*v}')
        fi
    done

    # Calculate cosine similarity
    local similarity
    if type -p bc &>/dev/null; then
        local denominator
        denominator=$(printf 'scale=10; sqrt(%s) * sqrt(%s)\n' "$mag1" "$mag2" | bc)
        if [[ "$denominator" == "0" ]] || [[ -z "$denominator" ]]; then
            similarity="0.0"
        else
            similarity=$(printf 'scale=6; %s / %s\n' "$dot_product" "$denominator" | bc)
        fi
    else
        similarity=$(awk -v d="$dot_product" -v m1="$mag1" -v m2="$mag2" 'BEGIN {
            denom = sqrt(m1) * sqrt(m2)
            if (denom == 0) print "0.0"
            else printf "%.6f", d / denom
        }')
    fi

    printf '%s' "$similarity"
    return 0
}

# @pre: vector_json is a valid JSON array of numbers
# @post: normalized vector (unit length) printed to stdout
# @returns: 0 on success, 1 on failure
#
# Normalize embedding vector to unit length.
#
# Usage: embed_normalize VECTOR_JSON
# Example: normalized=$(embed_normalize "[0.1,0.2,0.3]")
embed_normalize() {
    local vector_json="$1"

    if [[ -z "$vector_json" ]]; then
        _embed_log error "embed_normalize: vector required"
        return 1
    fi

    # Parse vector
    local vec_str="${vector_json#[}"
    vec_str="${vec_str%]}"

    local IFS=','
    local -a vec=($vec_str)
    local dims=${#vec[@]}

    # Calculate magnitude
    local sum_sq=0 i v
    for ((i=0; i<dims; i++)); do
        v="${vec[$i]// /}"
        if type -p bc &>/dev/null; then
            sum_sq=$(printf 'scale=10; %s + %s * %s\n' "$sum_sq" "$v" "$v" | bc)
        else
            sum_sq=$(awk -v s="$sum_sq" -v val="$v" 'BEGIN {print s + val*val}')
        fi
    done

    local magnitude
    if type -p bc &>/dev/null; then
        magnitude=$(printf 'scale=10; sqrt(%s)\n' "$sum_sq" | bc)
    else
        magnitude=$(awk -v s="$sum_sq" 'BEGIN {print sqrt(s)}')
    fi

    # Avoid division by zero
    if [[ "$magnitude" == "0" ]] || [[ -z "$magnitude" ]]; then
        _embed_log warn "embed_normalize: zero vector, returning as-is"
        printf '%s' "$vector_json"
        return 0
    fi

    # Normalize
    printf '['
    for ((i=0; i<dims; i++)); do
        [[ $i -gt 0 ]] && printf ','
        v="${vec[$i]// /}"
        if type -p bc &>/dev/null; then
            printf '%.6f' "$(printf 'scale=6; %s / %s\n' "$v" "$magnitude" | bc)"
        else
            printf '%.6f' "$(awk -v val="$v" -v m="$magnitude" 'BEGIN {printf "%.6f", val/m}')"
        fi
    done
    printf ']'

    return 0
}

# @pre: provider is valid (openai, ollama, local)
# @post: dimension count printed to stdout
# @returns: 0 on success, 1 on failure
#
# Get embedding dimensions for a provider/model.
#
# Usage: embed_dimensions PROVIDER [MODEL]
# Example: dims=$(embed_dimensions "openai")
# Example: dims=$(embed_dimensions "openai" "text-embedding-3-large")
embed_dimensions() {
    local provider="$1"
    local model="${2:-}"

    if [[ -z "$provider" ]]; then
        _embed_log error "embed_dimensions: provider required"
        return 1
    fi

    _embed_validate_provider "$provider" || return 1

    # Get model if not specified
    if [[ -z "$model" ]]; then
        model=$(_embed_get_model "$provider")
    fi

    # Look up dimensions
    local dims="${EMBED_MODEL_DIMS[$model]:-}"

    if [[ -z "$dims" ]]; then
        _embed_log warn "Unknown model dimensions for: $model, using default"
        case "$provider" in
            openai) dims=1536 ;;
            ollama) dims=768 ;;
            local)  dims=$EMBED_LOCAL_DEFAULT_DIMS ;;
        esac
    fi

    printf '%s' "$dims"
    return 0
}

# @pre: none
# @post: statistics printed to stdout (JSON or plain text)
# @returns: 0
#
# Display embedding cache statistics.
#
# Usage: embed_stats [--json]
# Example: embed_stats --json
embed_stats() {
    local json_output=false

    if [[ "${1:-}" == "--json" ]]; then
        json_output=true
    fi

    local total_requests=$((_EMBED_CACHE_HITS + _EMBED_CACHE_MISSES))
    local hit_ratio=0
    if [[ $total_requests -gt 0 ]]; then
        hit_ratio=$(( (_EMBED_CACHE_HITS * 100) / total_requests ))
    fi

    local cache_count=0
    local cache_size=0
    if [[ -d "$EMBED_CACHE_DIR" ]]; then
        cache_count=$(find "$EMBED_CACHE_DIR" -name "*.json" -type f 2>/dev/null | wc -l)
        cache_size=$(du -sb "$EMBED_CACHE_DIR" 2>/dev/null | cut -f1)
        [[ "$cache_size" =~ ^[0-9]+$ ]] || cache_size=$(find "$EMBED_CACHE_DIR" -type f -exec stat -f%z {} + 2>/dev/null | awk '{s+=$1} END{print s+0}')
        [[ "$cache_size" =~ ^[0-9]+$ ]] || cache_size=0
    fi

    if [[ "$json_output" == true ]]; then
        printf '{"cache_hits":%d,"cache_misses":%d,"hit_ratio_pct":%d,"cached_entries":%d,"cache_size_bytes":%d,"ttl_seconds":%d}' \
            "$_EMBED_CACHE_HITS" "$_EMBED_CACHE_MISSES" "$hit_ratio" "$cache_count" "$cache_size" "$EMBED_CACHE_TTL"
    else
        printf 'Embedding Statistics:\n'
        printf '  Cache Hits:    %d\n' "$_EMBED_CACHE_HITS"
        printf '  Cache Misses:  %d\n' "$_EMBED_CACHE_MISSES"
        printf '  Hit Ratio:     %d%%\n' "$hit_ratio"
        printf '  Cached Items:  %d\n' "$cache_count"
        printf '  Cache Size:    %d bytes\n' "$cache_size"
        printf '  TTL:           %d seconds\n' "$EMBED_CACHE_TTL"
    fi

    return 0
}

# @pre: none
# @post: provider availability status printed
# @returns: 0
#
# Check which embedding providers are available.
#
# Usage: embed_providers
embed_providers() {
    printf 'Embedding Providers:\n'
    printf '====================\n'

    # OpenAI
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        printf '[OK] openai - API key configured\n'
        printf '     Model: %s (%d dims)\n' "$EMBED_OPENAI_DEFAULT_MODEL" "${EMBED_MODEL_DIMS[$EMBED_OPENAI_DEFAULT_MODEL]}"
    else
        printf '[--] openai - OPENAI_API_KEY not set\n'
    fi

    # Ollama
    local ollama_host="${OLLAMA_HOST:-$EMBED_OLLAMA_DEFAULT_HOST}"
    if curl -s "${ollama_host}/api/tags" &>/dev/null; then
        printf '[OK] ollama - Server available at %s\n' "$ollama_host"
        printf '     Model: %s (%d dims)\n' "$EMBED_OLLAMA_DEFAULT_MODEL" "${EMBED_MODEL_DIMS[$EMBED_OLLAMA_DEFAULT_MODEL]}"
    else
        printf '[--] ollama - Server not reachable at %s\n' "$ollama_host"
    fi

    # Local
    printf '[OK] local - Always available (TF-IDF fallback)\n'
    printf '     Dimensions: %d (configurable)\n' "$EMBED_LOCAL_DEFAULT_DIMS"

    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# @pre: text is a non-empty string, max_tokens is positive integer
# @post: array of text chunks printed, one per line
# @returns: 0 on success
#
# Chunk text into segments suitable for embedding.
# Useful for texts that exceed model token limits.
#
# Usage: embed_chunk TEXT [MAX_TOKENS] [OVERLAP]
# Example: embed_chunk "$long_text" 512 50
embed_chunk() {
    local text="$1"
    local max_tokens="${2:-512}"
    local overlap="${3:-50}"

    if [[ -z "$text" ]]; then
        return 0
    fi

    # Approximate: 1 token ~= 4 characters (rough estimate)
    local max_chars=$((max_tokens * 4))
    local overlap_chars=$((overlap * 4))

    local text_len=${#text}
    local start=0

    while [[ $start -lt $text_len ]]; do
        local chunk="${text:start:max_chars}"

        # Try to break at word boundary
        if [[ $((start + max_chars)) -lt $text_len ]]; then
            # Find last space in chunk
            local last_space=-1
            local i
            for ((i=${#chunk}-1; i>=0; i--)); do
                if [[ "${chunk:i:1}" == " " ]]; then
                    last_space=$i
                    break
                fi
            done
            if [[ $last_space -gt $((max_chars / 2)) ]]; then
                chunk="${chunk:0:last_space}"
            fi
        fi

        printf '%s\n' "$chunk"

        # Move start position with overlap
        start=$((start + ${#chunk} - overlap_chars))
        [[ $start -lt 0 ]] && start=0
    done

    return 0
}

# @pre: query and documents are valid JSON
# @post: documents sorted by similarity score printed
# @returns: 0 on success
#
# Rank documents by similarity to query embedding.
# Input: query embedding, array of document embeddings
# Output: sorted indices by similarity (highest first)
#
# Usage: embed_rank QUERY_VEC DOC_VECS_JSON
# Example: embed_rank "[0.1,0.2]" "[[0.2,0.3],[0.1,0.4]]"
embed_rank() {
    local query_vec="$1"
    local docs_json="$2"

    if [[ -z "$query_vec" ]] || [[ -z "$docs_json" ]]; then
        _embed_log error "embed_rank: query vector and documents required"
        return 1
    fi

    # Parse documents array - simplistic parsing
    # Expected format: [[...],[...],[...]]
    local docs_inner="${docs_json#[}"
    docs_inner="${docs_inner%]}"

    # Split on ],[ pattern
    local -a docs=()
    local current=""
    local depth=0
    local i char

    for ((i=0; i<${#docs_inner}; i++)); do
        char="${docs_inner:i:1}"
        if [[ "$char" == "[" ]]; then
            ((depth++))
            current+="$char"
        elif [[ "$char" == "]" ]]; then
            ((depth--))
            current+="$char"
            if [[ $depth -eq 0 ]]; then
                docs+=("$current")
                current=""
            fi
        elif [[ "$char" == "," ]] && [[ $depth -eq 0 ]]; then
            # Skip comma between docs
            continue
        else
            current+="$char"
        fi
    done

    # Calculate similarities
    local -a scores=()
    local idx=0
    local doc sim

    for doc in "${docs[@]}"; do
        sim=$(embed_similarity "$query_vec" "$doc") || sim="0"
        scores+=("$idx:$sim")
        ((idx++))
    done

    # Sort by score descending
    printf '%s\n' "${scores[@]}" | sort -t: -k2 -rn | cut -d: -f1

    return 0
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_EMBEDDINGS_EXPORTS=(
    # Core functions
    embed_text
    embed_batch
    embed_similarity
    embed_normalize
    embed_dimensions
    # Cache functions
    embed_cache_get
    embed_cache_set
    embed_cache_clear
    # Utility functions
    embed_chunk
    embed_rank
    embed_stats
    embed_providers
)

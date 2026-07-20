#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/rag.sh - Retrieval-Augmented Generation Pipeline
# =============================================================================
# Description: End-to-end RAG pipeline for document ingestion, retrieval, and
#              context augmentation. Integrates embeddings.sh and vectordb.sh.
# Version: 1.0.0
# Requires: Bash 4.0+, embeddings.sh, vectordb.sh
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================
#
# Usage: source rag.sh
#
# Examples:
#   # Initialize RAG pipeline
#   rag_init "documents"
#
#   # Ingest documents
#   rag_ingest "docs/" --collection "docs"
#   rag_ingest_file "readme.md" --collection "docs"
#   rag_ingest_text "Hello world" --id "doc1"
#
#   # Query with retrieval
#   rag_query "How do I create JSON?" --collection "docs" --top-k 5
#
#   # Search only (no LLM)
#   rag_search "JSON creation" --collection "docs"
#
# Configuration:
#   RAG_COLLECTION       - Default collection name (default: "default")
#   RAG_CHUNK_SIZE       - Default chunk size in characters (default: 500)
#   RAG_CHUNK_OVERLAP    - Default chunk overlap (default: 50)
#   RAG_TOP_K            - Default number of results (default: 5)
#   RAG_EMBED_PROVIDER   - Embedding provider (default: "local")
#   RAG_VECTORDB_BACKEND - Vector DB backend (default: "sqlite-vec")
#
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_RAG_LOADED:-}" ]] && return 0
readonly _MAINFRAME_RAG_LOADED=1


# Portable SHA-256 digest (sha256sum -> shasum -> openssl fallback chain).
# Shared micro-shim: the declare -F guard means it is defined once per
# process no matter how many MAINFRAME libraries are sourced.
if ! declare -F _mainframe_sha256 &>/dev/null; then
_mainframe_sha256() {
    if command -v sha256sum &>/dev/null; then
        sha256sum "$@"
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$@"
    else
        openssl dgst -sha256 "$@" | sed 's/^.* //'
    fi
}
fi

# =============================================================================
# DEPENDENCIES
# =============================================================================

# Source required libraries if not already loaded
_RAG_LIB_DIR="${BASH_SOURCE[0]%/*}"

if [[ -z "${_MAINFRAME_EMBEDDINGS_LOADED:-}" ]]; then
    [[ -f "${_RAG_LIB_DIR}/embeddings.sh" ]] && source "${_RAG_LIB_DIR}/embeddings.sh"
fi

if [[ -z "${_MAINFRAME_VECTORDB_LOADED:-}" ]]; then
    [[ -f "${_RAG_LIB_DIR}/vectordb.sh" ]] && source "${_RAG_LIB_DIR}/vectordb.sh"
fi

if [[ -z "${_MAINFRAME_JSON_LOADED:-}" ]]; then
    [[ -f "${_RAG_LIB_DIR}/json.sh" ]] && source "${_RAG_LIB_DIR}/json.sh"
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

RAG_COLLECTION="${RAG_COLLECTION:-default}"
RAG_CHUNK_SIZE="${RAG_CHUNK_SIZE:-500}"
RAG_CHUNK_OVERLAP="${RAG_CHUNK_OVERLAP:-50}"
RAG_TOP_K="${RAG_TOP_K:-5}"
RAG_EMBED_PROVIDER="${RAG_EMBED_PROVIDER:-local}"
RAG_VECTORDB_BACKEND="${RAG_VECTORDB_BACKEND:-sqlite-vec}"
RAG_VECTORDB_PATH="${RAG_VECTORDB_PATH:-${TMPDIR:-/tmp}/mainframe_rag.sqlite}"

# Chunking strategies
readonly RAG_CHUNK_FIXED="fixed"
readonly RAG_CHUNK_SENTENCE="sentence"
readonly RAG_CHUNK_PARAGRAPH="paragraph"
readonly RAG_CHUNK_CODE="code"

# Supported file extensions
readonly RAG_TEXT_EXTENSIONS="txt md markdown rst"
readonly RAG_CODE_EXTENSIONS="sh bash py js ts jsx tsx go rs rb pl java c cpp h hpp cs"
readonly RAG_DATA_EXTENSIONS="json yaml yml toml xml"

# Internal state
_RAG_INITIALIZED=false
_RAG_CURRENT_COLLECTION=""

# Statistics
declare -gi _RAG_DOCS_INGESTED=0
declare -gi _RAG_CHUNKS_CREATED=0
declare -gi _RAG_QUERIES_MADE=0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Logging helper
_rag_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "rag" "$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[rag] %s: %s\n' "$level" "$*" >&2
    fi
}

# JSON escape helper (use library function if available)
_rag_json_escape() {
    local str="$1"
    if declare -F json_escape &>/dev/null; then
        json_escape "$str"
    else
        # Fallback: basic escaping
        str="${str//\\/\\\\}"
        str="${str//\"/\\\"}"
        str="${str//$'\n'/\\n}"
        str="${str//$'\r'/\\r}"
        str="${str//$'\t'/\\t}"
        printf '%s' "$str"
    fi
}

# Generate document ID from content and source
_rag_generate_id() {
    local content="$1"
    local source="${2:-}"
    local chunk_idx="${3:-0}"

    local hash_input="${source}:${chunk_idx}:${content:0:100}"

    if command -v sha256sum &>/dev/null; then
        printf '%s' "$hash_input" | _mainframe_sha256 | cut -c1-16
    elif command -v shasum &>/dev/null; then
        printf '%s' "$hash_input" | shasum -a 256 | cut -c1-16
    elif command -v openssl &>/dev/null; then
        printf '%s' "$hash_input" | openssl dgst -sha256 | awk '{print $NF}' | cut -c1-16
    else
        # Fallback: cksum-based hash
        printf '%s' "$hash_input" | cksum | awk '{printf "%08x%08x", $1, $2}'
    fi
}

# Detect file type from extension
_rag_detect_file_type() {
    local file="$1"
    local ext="${file##*.}"
    ext="${ext,,}"  # lowercase

    if [[ " $RAG_TEXT_EXTENSIONS " == *" $ext "* ]]; then
        printf 'text'
    elif [[ " $RAG_CODE_EXTENSIONS " == *" $ext "* ]]; then
        printf 'code'
    elif [[ " $RAG_DATA_EXTENSIONS " == *" $ext "* ]]; then
        printf 'data'
    else
        printf 'unknown'
    fi
}

# Extract text from JSON file
_rag_extract_json_text() {
    local file="$1"
    local content
    content=$(<"$file")

    # Extract string values from JSON (simple extraction)
    # Matches: "key": "value" patterns
    local extracted=""
    while IFS= read -r line; do
        if [[ "$line" =~ \"[^\"]+\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            extracted+="${BASH_REMATCH[1]} "
        fi
    done <<< "$content"

    # If no string values found, return raw content
    if [[ -z "${extracted// /}" ]]; then
        printf '%s' "$content"
    else
        printf '%s' "$extracted"
    fi
}

# =============================================================================
# CHUNKING FUNCTIONS
# =============================================================================

# @pre: text is a non-empty string
# @post: chunks printed to stdout, one per line
# @returns: 0 on success
#
# Chunk text using fixed size with overlap.
#
# Usage: rag_chunk_text TEXT [--size SIZE] [--overlap OVERLAP] [--strategy STRATEGY]
# Example: rag_chunk_text "$content" --size 500 --overlap 50
# Example: rag_chunk_text "$code" --strategy code
rag_chunk_text() {
    local text="$1"
    shift

    local size="$RAG_CHUNK_SIZE"
    local overlap="$RAG_CHUNK_OVERLAP"
    local strategy="$RAG_CHUNK_FIXED"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --size|-s)
                size="$2"
                shift 2
                ;;
            --overlap|-o)
                overlap="$2"
                shift 2
                ;;
            --strategy)
                strategy="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    [[ -z "$text" ]] && return 0

    case "$strategy" in
        "$RAG_CHUNK_FIXED")
            _rag_chunk_fixed "$text" "$size" "$overlap"
            ;;
        "$RAG_CHUNK_SENTENCE")
            _rag_chunk_sentence "$text" "$size" "$overlap"
            ;;
        "$RAG_CHUNK_PARAGRAPH")
            _rag_chunk_paragraph "$text" "$size"
            ;;
        "$RAG_CHUNK_CODE")
            _rag_chunk_code "$text" "$size"
            ;;
        *)
            _rag_chunk_fixed "$text" "$size" "$overlap"
            ;;
    esac
}

# Fixed size chunking with overlap
_rag_chunk_fixed() {
    local text="$1"
    local size="${2:-500}"
    local overlap="${3:-50}"

    local text_len=${#text}
    local start=0
    local chunk_num=0

    while [[ $start -lt $text_len ]]; do
        local chunk="${text:start:size}"

        # Try to break at word boundary if not at end
        if [[ $((start + size)) -lt $text_len ]]; then
            local last_space=-1
            local i
            for ((i=${#chunk}-1; i>=0; i--)); do
                if [[ "${chunk:i:1}" == " " ]]; then
                    last_space=$i
                    break
                fi
            done
            if [[ $last_space -gt $((size / 2)) ]]; then
                chunk="${chunk:0:last_space}"
            fi
        fi

        # Trim whitespace
        chunk="${chunk#"${chunk%%[![:space:]]*}"}"
        chunk="${chunk%"${chunk##*[![:space:]]}"}"

        [[ -n "$chunk" ]] && printf '%s\n' "$chunk"

        # Move start position with overlap
        start=$((start + ${#chunk} - overlap))
        [[ $start -lt 0 ]] && start=0

        ((chunk_num++))
        _RAG_CHUNKS_CREATED=$((_RAG_CHUNKS_CREATED + 1))
    done
}

# Sentence-based chunking
_rag_chunk_sentence() {
    local text="$1"
    local max_size="${2:-500}"
    local overlap="${3:-1}"  # Number of sentences to overlap

    # Split into sentences (simple heuristic)
    local -a sentences=()
    local current=""
    local i char prev_char=""

    for ((i=0; i<${#text}; i++)); do
        char="${text:i:1}"
        current+="$char"

        # Sentence boundary: .!? followed by space or end
        if [[ "$char" =~ [.!?] ]]; then
            local next_char="${text:i+1:1}"
            if [[ -z "$next_char" || "$next_char" == " " || "$next_char" == $'\n' ]]; then
                # Trim and add sentence
                current="${current#"${current%%[![:space:]]*}"}"
                current="${current%"${current##*[![:space:]]}"}"
                [[ -n "$current" ]] && sentences+=("$current")
                current=""
            fi
        fi

        prev_char="$char"
    done

    # Add remaining text
    current="${current#"${current%%[![:space:]]*}"}"
    current="${current%"${current##*[![:space:]]}"}"
    [[ -n "$current" ]] && sentences+=("$current")

    # Group sentences into chunks
    local chunk=""
    local sentence_count=0
    local -a chunk_sentences=()

    for sentence in "${sentences[@]}"; do
        if [[ $((${#chunk} + ${#sentence} + 1)) -gt $max_size && -n "$chunk" ]]; then
            printf '%s\n' "$chunk"
            _RAG_CHUNKS_CREATED=$((_RAG_CHUNKS_CREATED + 1))

            # Overlap: keep last N sentences
            chunk=""
            local start_idx=$((${#chunk_sentences[@]} - overlap))
            [[ $start_idx -lt 0 ]] && start_idx=0
            for ((j=start_idx; j<${#chunk_sentences[@]}; j++)); do
                [[ -n "$chunk" ]] && chunk+=" "
                chunk+="${chunk_sentences[j]}"
            done
            chunk_sentences=("${chunk_sentences[@]:start_idx}")
        fi

        [[ -n "$chunk" ]] && chunk+=" "
        chunk+="$sentence"
        chunk_sentences+=("$sentence")
    done

    # Output remaining chunk
    [[ -n "$chunk" ]] && {
        printf '%s\n' "$chunk"
        _RAG_CHUNKS_CREATED=$((_RAG_CHUNKS_CREATED + 1))
    }
}

# Paragraph-based chunking
_rag_chunk_paragraph() {
    local text="$1"
    local max_size="${2:-1000}"

    local chunk=""
    local IFS=$'\n'

    # Split by double newlines (paragraphs)
    local para_text="${text//$'\n\n'/$'\x00'}"
    local -a paragraphs
    IFS=$'\x00' read -ra paragraphs <<< "$para_text"

    for para in "${paragraphs[@]}"; do
        # Trim whitespace
        para="${para#"${para%%[![:space:]]*}"}"
        para="${para%"${para##*[![:space:]]}"}"

        [[ -z "$para" ]] && continue

        if [[ $((${#chunk} + ${#para} + 2)) -gt $max_size && -n "$chunk" ]]; then
            printf '%s\n' "$chunk"
            _RAG_CHUNKS_CREATED=$((_RAG_CHUNKS_CREATED + 1))
            chunk=""
        fi

        [[ -n "$chunk" ]] && chunk+=$'\n\n'
        chunk+="$para"
    done

    [[ -n "$chunk" ]] && {
        printf '%s\n' "$chunk"
        _RAG_CHUNKS_CREATED=$((_RAG_CHUNKS_CREATED + 1))
    }
}

# Code-aware chunking (function boundaries)
_rag_chunk_code() {
    local text="$1"
    local max_size="${2:-1000}"

    local chunk=""
    local in_function=false
    local brace_depth=0
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Detect function start (simple heuristics)
        if [[ "$line" =~ ^[[:space:]]*(function[[:space:]]+[a-zA-Z_]|[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)|def[[:space:]]+[a-zA-Z_]|func[[:space:]]+[a-zA-Z_]) ]]; then
            # If we have content and would exceed max, emit chunk
            if [[ -n "$chunk" && $((${#chunk} + ${#line})) -gt $max_size ]]; then
                printf '%s\n' "$chunk"
                _RAG_CHUNKS_CREATED=$((_RAG_CHUNKS_CREATED + 1))
                chunk=""
            fi
            in_function=true
        fi

        # Count braces
        local open_braces="${line//[^\{]/}"
        local close_braces="${line//[^\}]/}"
        brace_depth=$((brace_depth + ${#open_braces} - ${#close_braces}))

        # Add line to chunk
        [[ -n "$chunk" ]] && chunk+=$'\n'
        chunk+="$line"

        # End of function (brace depth returns to 0)
        if $in_function && [[ $brace_depth -eq 0 ]]; then
            if [[ ${#chunk} -gt 0 ]]; then
                printf '%s\n' "$chunk"
                _RAG_CHUNKS_CREATED=$((_RAG_CHUNKS_CREATED + 1))
                chunk=""
            fi
            in_function=false
        fi

        # Force chunk if too large
        if [[ ${#chunk} -gt $((max_size * 2)) ]]; then
            printf '%s\n' "$chunk"
            _RAG_CHUNKS_CREATED=$((_RAG_CHUNKS_CREATED + 1))
            chunk=""
            in_function=false
            brace_depth=0
        fi
    done <<< "$text"

    # Emit remaining chunk
    [[ -n "$chunk" ]] && {
        printf '%s\n' "$chunk"
        _RAG_CHUNKS_CREATED=$((_RAG_CHUNKS_CREATED + 1))
    }
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# @pre: collection_name is a valid identifier
# @post: RAG pipeline initialized with vectordb and embeddings
# @returns: 0 on success, 1 on failure
#
# Initialize RAG pipeline for a collection.
#
# Usage: rag_init COLLECTION_NAME [--backend BACKEND] [--provider PROVIDER]
# Example: rag_init "documents"
# Example: rag_init "code" --backend chromadb --provider ollama
rag_init() {
    local collection="${1:-$RAG_COLLECTION}"
    shift 2>/dev/null || true

    local backend="$RAG_VECTORDB_BACKEND"
    local provider="$RAG_EMBED_PROVIDER"
    local db_path="$RAG_VECTORDB_PATH"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --backend|-b)
                backend="$2"
                shift 2
                ;;
            --provider|-p)
                provider="$2"
                shift 2
                ;;
            --path)
                db_path="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    [[ -z "$collection" ]] && {
        _rag_log "error" "Collection name required"
        return 1
    }

    # Initialize vector database
    if ! vectordb_init "$backend" "$db_path"; then
        _rag_log "error" "Failed to initialize vector database"
        return 1
    fi

    # Get embedding dimensions
    local dims
    dims=$(embed_dimensions "$provider")

    # Create collection if it doesn't exist
    vectordb_create_collection "$collection" "$dims" 2>/dev/null || true

    _RAG_INITIALIZED=true
    _RAG_CURRENT_COLLECTION="$collection"
    RAG_EMBED_PROVIDER="$provider"

    _rag_log "info" "RAG initialized: collection=$collection, backend=$backend, provider=$provider"
    return 0
}

# =============================================================================
# DOCUMENT INGESTION
# =============================================================================

# @pre: path is a valid directory, RAG is initialized
# @post: all supported documents ingested into collection
# @returns: 0 on success, number of ingested documents in stdout
#
# Ingest all documents from a directory.
#
# Usage: rag_ingest PATH [--collection COLLECTION] [--recursive]
# Example: rag_ingest "docs/" --collection "docs"
rag_ingest() {
    local path="$1"
    shift

    local collection="$_RAG_CURRENT_COLLECTION"
    local recursive=false
    local chunk_size="$RAG_CHUNK_SIZE"
    local chunk_overlap="$RAG_CHUNK_OVERLAP"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --collection|-c)
                collection="$2"
                shift 2
                ;;
            --recursive|-r)
                recursive=true
                shift
                ;;
            --chunk-size)
                chunk_size="$2"
                shift 2
                ;;
            --chunk-overlap)
                chunk_overlap="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    [[ ! -d "$path" ]] && {
        _rag_log "error" "Directory not found: $path"
        return 1
    }

    [[ "$_RAG_INITIALIZED" != "true" ]] && rag_init "$collection"

    local count=0
    local find_opts=("-type" "f")
    $recursive || find_opts+=("-maxdepth" "1")

    while IFS= read -r -d '' file; do
        if rag_ingest_file "$file" --collection "$collection" \
            --chunk-size "$chunk_size" --chunk-overlap "$chunk_overlap"; then
            ((count++))
        fi
    done < <(find "$path" "${find_opts[@]}" -print0 2>/dev/null)

    _rag_log "info" "Ingested $count documents from $path"
    printf '%d' "$count"
}

# @pre: file exists and is readable
# @post: file content chunked and ingested into collection
# @returns: 0 on success, 1 on failure
#
# Ingest a single file.
#
# Usage: rag_ingest_file FILE [--collection COLLECTION] [--id ID]
# Example: rag_ingest_file "readme.md" --collection "docs"
rag_ingest_file() {
    local file="$1"
    shift

    local collection="$_RAG_CURRENT_COLLECTION"
    local doc_id=""
    local chunk_size="$RAG_CHUNK_SIZE"
    local chunk_overlap="$RAG_CHUNK_OVERLAP"
    local strategy=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --collection|-c)
                collection="$2"
                shift 2
                ;;
            --id)
                doc_id="$2"
                shift 2
                ;;
            --chunk-size)
                chunk_size="$2"
                shift 2
                ;;
            --chunk-overlap)
                chunk_overlap="$2"
                shift 2
                ;;
            --strategy)
                strategy="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    [[ ! -f "$file" ]] && {
        _rag_log "error" "File not found: $file"
        return 1
    }

    [[ "$_RAG_INITIALIZED" != "true" ]] && rag_init "$collection"

    # Detect file type and extract text
    local file_type content
    file_type=$(_rag_detect_file_type "$file")

    case "$file_type" in
        text|code)
            content=$(<"$file")
            [[ -z "$strategy" && "$file_type" == "code" ]] && strategy="$RAG_CHUNK_CODE"
            ;;
        data)
            local ext="${file##*.}"
            ext="${ext,,}"
            if [[ "$ext" == "json" ]]; then
                content=$(_rag_extract_json_text "$file")
            else
                content=$(<"$file")
            fi
            ;;
        *)
            # Try to read as text anyway
            content=$(<"$file") 2>/dev/null || {
                _rag_log "warn" "Cannot read file: $file"
                return 1
            }
            ;;
    esac

    [[ -z "$content" ]] && {
        _rag_log "warn" "Empty file: $file"
        return 1
    }

    # Chunk content
    local chunk_idx=0
    local abs_path
    abs_path=$(cd "$(dirname "$file")" && pwd)/$(basename "$file")

    while IFS= read -r chunk; do
        [[ -z "$chunk" ]] && continue

        # Generate ID for this chunk
        local chunk_id
        if [[ -n "$doc_id" ]]; then
            chunk_id="${doc_id}_${chunk_idx}"
        else
            chunk_id=$(_rag_generate_id "$chunk" "$abs_path" "$chunk_idx")
        fi

        # Create metadata
        local metadata
        metadata=$(printf '{"source":"%s","chunk":%d,"type":"%s","file":"%s"}' \
            "$(_rag_json_escape "$abs_path")" "$chunk_idx" "$file_type" \
            "$(_rag_json_escape "$(basename "$file")")")

        # Ingest chunk
        if rag_ingest_text "$chunk" --id "$chunk_id" --collection "$collection" \
            --metadata "$metadata"; then
            ((chunk_idx++))
        fi
    done < <(rag_chunk_text "$content" --size "$chunk_size" --overlap "$chunk_overlap" \
        ${strategy:+--strategy "$strategy"})

    _RAG_DOCS_INGESTED=$((_RAG_DOCS_INGESTED + 1))
    _rag_log "debug" "Ingested $file: $chunk_idx chunks"

    return 0
}

# @pre: content is non-empty, RAG is initialized
# @post: text embedded and stored in vector database
# @returns: 0 on success, 1 on failure
#
# Ingest raw text content.
#
# Usage: rag_ingest_text CONTENT [--id ID] [--collection COLLECTION] [--metadata JSON]
# Example: rag_ingest_text "Hello world" --id "doc1"
rag_ingest_text() {
    local content="$1"
    shift

    local doc_id=""
    local collection="$_RAG_CURRENT_COLLECTION"
    local metadata="{}"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id)
                doc_id="$2"
                shift 2
                ;;
            --collection|-c)
                collection="$2"
                shift 2
                ;;
            --metadata|-m)
                metadata="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    [[ -z "$content" ]] && {
        _rag_log "error" "Content required"
        return 1
    }

    [[ "$_RAG_INITIALIZED" != "true" ]] && rag_init "$collection"

    # Generate ID if not provided
    [[ -z "$doc_id" ]] && doc_id=$(_rag_generate_id "$content")

    # Generate embedding
    local embedding
    embedding=$(embed_text "$content" "$RAG_EMBED_PROVIDER")

    if [[ -z "$embedding" ]]; then
        _rag_log "error" "Failed to generate embedding"
        return 1
    fi

    # Store in vector database
    if ! vectordb_upsert "$collection" "$doc_id" "$content" "$embedding" "$metadata"; then
        _rag_log "error" "Failed to store document"
        return 1
    fi

    return 0
}

# =============================================================================
# QUERYING
# =============================================================================

# @pre: RAG is initialized, query is non-empty
# @post: returns USOP JSON with query results and augmented prompt
# @returns: 0 on success, 1 on failure
#
# Query the RAG pipeline with retrieval and context augmentation.
#
# Usage: rag_query QUESTION [--collection COLLECTION] [--top-k N]
# Example: rag_query "How do I create JSON?" --collection "docs" --top-k 5
rag_query() {
    local query="$1"
    shift

    local collection="$_RAG_CURRENT_COLLECTION"
    local top_k="$RAG_TOP_K"
    local include_prompt=true

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --collection|-c)
                collection="$2"
                shift 2
                ;;
            --top-k|-k)
                top_k="$2"
                shift 2
                ;;
            --no-prompt)
                include_prompt=false
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    [[ -z "$query" ]] && {
        _rag_output_error "Query required"
        return 1
    }

    [[ "$_RAG_INITIALIZED" != "true" ]] && rag_init "$collection"

    _RAG_QUERIES_MADE=$((_RAG_QUERIES_MADE + 1))

    # Search for relevant documents
    local search_results
    search_results=$(rag_search "$query" --collection "$collection" --top-k "$top_k" --raw)

    if [[ -z "$search_results" || "$search_results" == "[]" ]]; then
        _rag_output_success "$query" "[]" "" ""
        return 0
    fi

    # Build context from results
    local context=""
    local -a results_array=()

    # Parse results and build context
    # Results format depends on backend, but we'll extract text content
    local result_idx=0

    # Simple parsing of JSON array results
    local in_result=false
    local current_text=""
    local current_score=""
    local current_id=""
    local current_metadata="{}"
    local depth=0

    # Create context from search results
    context="Based on the available documentation:"$'\n\n'

    # Parse the search results (simplified - assumes specific format)
    # For proper parsing, we'd need a full JSON parser
    local temp_results="$search_results"
    local result_count=0

    while [[ "$temp_results" =~ \"text\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; do
        local text="${BASH_REMATCH[1]}"
        ((result_count++))
        context+="[$result_count] $text"$'\n\n'
        # Remove processed match
        temp_results="${temp_results#*"${BASH_REMATCH[0]}"}"
    done

    # Build augmented prompt
    local augmented_prompt=""
    if $include_prompt; then
        augmented_prompt="Context:"$'\n'"$context"$'\n'"Question: $query"$'\n\n'"Please answer based on the provided context."
    fi

    _rag_output_success "$query" "$search_results" "$context" "$augmented_prompt"
    return 0
}

# Output helper for success
_rag_output_success() {
    local query="$1"
    local results="$2"
    local context="$3"
    local augmented="$4"

    local escaped_query escaped_context escaped_augmented
    escaped_query=$(_rag_json_escape "$query")
    escaped_context=$(_rag_json_escape "$context")
    escaped_augmented=$(_rag_json_escape "$augmented")

    printf '{"ok":true,"data":{"query":"%s","results":%s,"context":"%s","augmented_prompt":"%s"}}' \
        "$escaped_query" "${results:-[]}" "$escaped_context" "$escaped_augmented"
}

# Output helper for error
_rag_output_error() {
    local message="$1"
    local escaped_msg
    escaped_msg=$(_rag_json_escape "$message")
    printf '{"ok":false,"error":"%s"}' "$escaped_msg"
}

# @pre: RAG is initialized, query is non-empty
# @post: returns search results without LLM augmentation
# @returns: 0 on success, 1 on failure
#
# Search for similar documents without context augmentation.
#
# Usage: rag_search QUERY [--collection COLLECTION] [--top-k N]
# Example: rag_search "JSON creation" --collection "docs"
rag_search() {
    local query="$1"
    shift

    local collection="$_RAG_CURRENT_COLLECTION"
    local top_k="$RAG_TOP_K"
    local raw_output=false

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --collection|-c)
                collection="$2"
                shift 2
                ;;
            --top-k|-k)
                top_k="$2"
                shift 2
                ;;
            --raw)
                raw_output=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    [[ -z "$query" ]] && {
        $raw_output && { printf '[]'; return 0; }
        _rag_output_error "Query required"
        return 1
    }

    [[ "$_RAG_INITIALIZED" != "true" ]] && rag_init "$collection"

    # Generate query embedding
    local query_embedding
    query_embedding=$(embed_text "$query" "$RAG_EMBED_PROVIDER")

    if [[ -z "$query_embedding" ]]; then
        $raw_output && { printf '[]'; return 0; }
        _rag_output_error "Failed to generate query embedding"
        return 1
    fi

    # Search vector database
    local results
    results=$(vectordb_search "$collection" "$query_embedding" --top-k "$top_k")

    if $raw_output; then
        printf '%s' "${results:-[]}"
    else
        local escaped_query
        escaped_query=$(_rag_json_escape "$query")
        printf '{"ok":true,"data":{"query":"%s","results":%s}}' \
            "$escaped_query" "${results:-[]}"
    fi

    return 0
}

# =============================================================================
# CONTEXT AUGMENTATION
# =============================================================================

# @pre: prompt and context_array are valid
# @post: returns augmented prompt with injected context
# @returns: 0 on success
#
# Inject context into a prompt for LLM consumption.
#
# Usage: rag_augment_prompt PROMPT CONTEXT_ARRAY
# Example: contexts=("doc1 content" "doc2 content"); rag_augment_prompt "Question?" contexts
rag_augment_prompt() {
    local prompt="$1"
    local -n context_arr="$2" 2>/dev/null || {
        # Fallback for older bash
        shift
        local context_arr=("$@")
    }

    [[ -z "$prompt" ]] && {
        printf '%s' "$prompt"
        return 0
    }

    local augmented="Context from relevant documents:"$'\n\n'
    local idx=1

    for ctx in "${context_arr[@]}"; do
        augmented+="[$idx] $ctx"$'\n\n'
        ((idx++))
    done

    augmented+="---"$'\n\n'
    augmented+="Based on the above context, please answer:"$'\n\n'
    augmented+="$prompt"

    printf '%s' "$augmented"
}

# =============================================================================
# RERANKING
# =============================================================================

# @pre: results is a JSON array, query is non-empty
# @post: returns reranked results by relevance
# @returns: 0 on success
#
# Rerank search results by relevance to query.
# Uses embedding similarity for reranking.
#
# Usage: rag_rerank RESULTS_JSON QUERY
# Example: rag_rerank "$results" "How do I create JSON?"
rag_rerank() {
    local results_json="$1"
    local query="$2"

    [[ -z "$results_json" || "$results_json" == "[]" ]] && {
        printf '[]'
        return 0
    }

    [[ -z "$query" ]] && {
        printf '%s' "$results_json"
        return 0
    }

    # Get query embedding
    local query_embedding
    query_embedding=$(embed_text "$query" "$RAG_EMBED_PROVIDER")

    [[ -z "$query_embedding" ]] && {
        printf '%s' "$results_json"
        return 0
    }

    # Extract texts and compute similarity scores
    local -a scored_results=()
    local temp="$results_json"
    local idx=0

    while [[ "$temp" =~ \{[^\}]*\"text\"[[:space:]]*:[[:space:]]*\"([^\"]+)\"[^\}]*\} ]]; do
        local match="${BASH_REMATCH[0]}"
        local text="${BASH_REMATCH[1]}"

        # Get embedding for result text
        local text_embedding
        text_embedding=$(embed_text "$text" "$RAG_EMBED_PROVIDER")

        # Calculate similarity
        local score
        score=$(embed_similarity "$query_embedding" "$text_embedding" 2>/dev/null || echo "0")

        scored_results+=("$score|$idx|$match")

        # Move past current match
        temp="${temp#*"$match"}"
        ((idx++))
    done

    # Sort by score descending
    local sorted
    sorted=$(printf '%s\n' "${scored_results[@]}" | sort -t'|' -k1 -rn)

    # Rebuild results array
    local reranked="["
    local first=true

    while IFS='|' read -r score idx match; do
        [[ -z "$match" ]] && continue
        $first || reranked+=","
        first=false
        # Add score to result
        local with_score="${match%\}}"
        with_score+=",\"rerank_score\":$score}"
        reranked+="$with_score"
    done <<< "$sorted"

    reranked+="]"
    printf '%s' "$reranked"
}

# =============================================================================
# DELETION
# =============================================================================

# @pre: doc_id is valid, RAG is initialized
# @post: document removed from index
# @returns: 0 on success, 1 on failure
#
# Delete a document from the RAG index.
#
# Usage: rag_delete DOC_ID [--collection COLLECTION]
# Example: rag_delete "doc_123" --collection "docs"
rag_delete() {
    local doc_id="$1"
    shift

    local collection="$_RAG_CURRENT_COLLECTION"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --collection|-c)
                collection="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    [[ -z "$doc_id" ]] && {
        _rag_log "error" "Document ID required"
        return 1
    }

    [[ "$_RAG_INITIALIZED" != "true" ]] && {
        _rag_log "error" "RAG not initialized"
        return 1
    }

    if vectordb_delete "$collection" "$doc_id"; then
        _rag_log "info" "Deleted document: $doc_id"
        return 0
    else
        _rag_log "error" "Failed to delete document: $doc_id"
        return 1
    fi
}

# =============================================================================
# STATISTICS
# =============================================================================

# @pre: RAG may or may not be initialized
# @post: statistics printed to stdout
# @returns: 0
#
# Get RAG collection statistics.
#
# Usage: rag_stats [COLLECTION] [--json]
# Example: rag_stats "docs" --json
rag_stats() {
    local collection="${1:-$_RAG_CURRENT_COLLECTION}"
    local json_output=false

    shift 2>/dev/null || true

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                json_output=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    local doc_count=0
    local backend="unknown"
    local status="not_initialized"

    if [[ "$_RAG_INITIALIZED" == "true" ]]; then
        doc_count=$(vectordb_count "$collection" 2>/dev/null || echo 0)
        backend="$RAG_VECTORDB_BACKEND"
        status="initialized"
    fi

    if $json_output; then
        printf '{"ok":true,"data":{"collection":"%s","status":"%s","backend":"%s","provider":"%s","document_count":%d,"docs_ingested":%d,"chunks_created":%d,"queries_made":%d}}' \
            "$(_rag_json_escape "$collection")" \
            "$status" \
            "$backend" \
            "$RAG_EMBED_PROVIDER" \
            "$doc_count" \
            "$_RAG_DOCS_INGESTED" \
            "$_RAG_CHUNKS_CREATED" \
            "$_RAG_QUERIES_MADE"
    else
        printf 'RAG Pipeline Statistics:\n'
        printf '========================\n'
        printf '  Collection:      %s\n' "$collection"
        printf '  Status:          %s\n' "$status"
        printf '  Backend:         %s\n' "$backend"
        printf '  Embed Provider:  %s\n' "$RAG_EMBED_PROVIDER"
        printf '  Document Count:  %d\n' "$doc_count"
        printf '  Session Stats:\n'
        printf '    Docs Ingested: %d\n' "$_RAG_DOCS_INGESTED"
        printf '    Chunks Created:%d\n' "$_RAG_CHUNKS_CREATED"
        printf '    Queries Made:  %d\n' "$_RAG_QUERIES_MADE"
    fi

    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Reset RAG state (for testing)
rag_reset() {
    _RAG_INITIALIZED=false
    _RAG_CURRENT_COLLECTION=""
    _RAG_DOCS_INGESTED=0
    _RAG_CHUNKS_CREATED=0
    _RAG_QUERIES_MADE=0
    vectordb_reset 2>/dev/null || true
}

# Check if RAG is initialized
rag_is_initialized() {
    [[ "$_RAG_INITIALIZED" == "true" ]]
}

# Get current collection name
rag_collection() {
    printf '%s' "$_RAG_CURRENT_COLLECTION"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

RAG_EXPORTS=(
    # Initialization
    rag_init
    rag_reset
    rag_is_initialized
    rag_collection
    # Ingestion
    rag_ingest
    rag_ingest_file
    rag_ingest_text
    # Chunking
    rag_chunk_text
    # Querying
    rag_query
    rag_search
    # Context
    rag_augment_prompt
    rag_rerank
    # Management
    rag_delete
    rag_stats
)

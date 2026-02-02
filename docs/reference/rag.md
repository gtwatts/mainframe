# RAG Pipeline Library Reference

End-to-end Retrieval-Augmented Generation (RAG) pipeline for document ingestion, retrieval, and context augmentation.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
# Or load explicitly:
mainframe_load rag
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `RAG_COLLECTION` | `default` | Default collection name |
| `RAG_CHUNK_SIZE` | `500` | Default chunk size in characters |
| `RAG_CHUNK_OVERLAP` | `50` | Default chunk overlap |
| `RAG_TOP_K` | `5` | Default number of results |
| `RAG_EMBED_PROVIDER` | `local` | Embedding provider: `openai`, `ollama`, `local` |
| `RAG_VECTORDB_BACKEND` | `sqlite-vec` | Vector DB backend |
| `RAG_VECTORDB_PATH` | `/tmp/mainframe_rag.sqlite` | SQLite database path |

## Supported File Types

| Category | Extensions |
|----------|------------|
| Text | `.txt`, `.md`, `.markdown`, `.rst` |
| Code | `.sh`, `.bash`, `.py`, `.js`, `.ts`, `.go`, `.rs`, `.rb`, `.java`, `.c`, `.cpp` |
| Data | `.json`, `.yaml`, `.yml`, `.toml`, `.xml` |

## Chunking Strategies

| Strategy | Description |
|----------|-------------|
| `fixed` | Fixed size with overlap (default) |
| `sentence` | Split on sentence boundaries |
| `paragraph` | Split on double newlines |
| `code` | Code-aware splitting on function boundaries |

---

## Initialization

### rag_init

Initialize RAG pipeline for a collection.

```bash
rag_init COLLECTION_NAME [--backend BACKEND] [--provider PROVIDER] [--path DB_PATH]
```

**Parameters:**
- `COLLECTION_NAME` - Name of the collection to initialize
- `--backend` - Vector database backend: `sqlite-vec`, `chromadb`, `qdrant`, `pinecone`
- `--provider` - Embedding provider: `openai`, `ollama`, `local`
- `--path` - Database path (for sqlite-vec)

**Examples:**
```bash
# Initialize with defaults
rag_init "documents"

# Initialize with specific backend and provider
rag_init "code_docs" --backend chromadb --provider ollama

# Use SQLite with custom path
rag_init "local_docs" --backend sqlite-vec --path "/data/vectors.db"
```

### rag_reset

Reset RAG state and clear initialization.

```bash
rag_reset
```

### rag_is_initialized

Check if RAG pipeline is initialized.

```bash
rag_is_initialized && echo "Ready"
```

### rag_collection

Get current collection name.

```bash
current=$(rag_collection)
```

---

## Document Ingestion

### rag_ingest

Ingest all documents from a directory.

```bash
rag_ingest PATH [--collection COLLECTION] [--recursive] [--chunk-size N] [--chunk-overlap N]
```

**Parameters:**
- `PATH` - Directory path
- `--collection` - Target collection name
- `--recursive` - Include subdirectories
- `--chunk-size` - Characters per chunk (default: 500)
- `--chunk-overlap` - Overlap between chunks (default: 50)

**Returns:** Number of documents ingested

**Examples:**
```bash
# Ingest all files in docs/
count=$(rag_ingest "docs/")
echo "Ingested $count documents"

# Recursive ingestion with custom chunking
count=$(rag_ingest "src/" --recursive --chunk-size 1000 --chunk-overlap 100)

# Ingest to specific collection
rag_ingest "manuals/" --collection "user_manuals"
```

### rag_ingest_file

Ingest a single file.

```bash
rag_ingest_file FILE [--collection COLLECTION] [--id ID] [--strategy STRATEGY]
```

**Parameters:**
- `FILE` - File path
- `--collection` - Target collection
- `--id` - Custom document ID (auto-generated if not provided)
- `--strategy` - Chunking strategy: `fixed`, `sentence`, `paragraph`, `code`

**Examples:**
```bash
# Ingest markdown file
rag_ingest_file "README.md"

# Ingest code with code-aware chunking
rag_ingest_file "lib/utils.sh" --strategy code

# Custom ID for later reference
rag_ingest_file "config.json" --id "main_config"
```

### rag_ingest_text

Ingest raw text content.

```bash
rag_ingest_text CONTENT [--id ID] [--collection COLLECTION] [--metadata JSON]
```

**Parameters:**
- `CONTENT` - Text content to ingest
- `--id` - Document ID (auto-generated if not provided)
- `--collection` - Target collection
- `--metadata` - JSON metadata object

**Examples:**
```bash
# Simple text ingestion
rag_ingest_text "JSON objects are created using json_object function" --id "json_help"

# With metadata
rag_ingest_text "API endpoint documentation" \
    --id "api_docs" \
    --metadata '{"source":"manual","version":"2.0"}'
```

---

## Text Chunking

### rag_chunk_text

Chunk text for ingestion using various strategies.

```bash
rag_chunk_text TEXT [--size N] [--overlap N] [--strategy STRATEGY]
```

**Parameters:**
- `TEXT` - Text to chunk
- `--size` - Maximum chunk size in characters (default: 500)
- `--overlap` - Overlap between chunks (default: 50)
- `--strategy` - Chunking strategy: `fixed`, `sentence`, `paragraph`, `code`

**Returns:** One chunk per line

**Examples:**
```bash
# Fixed-size chunking
chunks=$(rag_chunk_text "$long_text" --size 500 --overlap 50)

# Sentence-based chunking
chunks=$(rag_chunk_text "$article" --strategy sentence)

# Code-aware chunking for source files
chunks=$(rag_chunk_text "$source_code" --strategy code --size 1000)

# Process chunks
while IFS= read -r chunk; do
    echo "Chunk: ${chunk:0:50}..."
done <<< "$chunks"
```

---

## Querying

### rag_query

Query the RAG pipeline with retrieval and context augmentation.

```bash
rag_query QUESTION [--collection COLLECTION] [--top-k N] [--no-prompt]
```

**Parameters:**
- `QUESTION` - Query text
- `--collection` - Collection to search
- `--top-k` - Number of results to retrieve (default: 5)
- `--no-prompt` - Skip augmented prompt generation

**Returns:** USOP JSON with query results and augmented prompt

```json
{
  "ok": true,
  "data": {
    "query": "How do I create JSON?",
    "results": [...],
    "context": "Based on the documentation...",
    "augmented_prompt": "Context:\n...\n\nQuestion: How do I create..."
  }
}
```

**Examples:**
```bash
# Basic query
result=$(rag_query "How do I create a JSON object?")

# Query specific collection with more results
result=$(rag_query "authentication flow" --collection "api_docs" --top-k 10)

# Search only, no augmented prompt
result=$(rag_query "validation functions" --no-prompt)
```

### rag_search

Search for similar documents without context augmentation.

```bash
rag_search QUERY [--collection COLLECTION] [--top-k N] [--raw]
```

**Parameters:**
- `QUERY` - Search query
- `--collection` - Collection to search
- `--top-k` - Number of results
- `--raw` - Return raw results array only

**Returns:** USOP JSON with search results

**Examples:**
```bash
# Full USOP response
result=$(rag_search "JSON validation")

# Raw results only
results=$(rag_search "error handling" --raw)

# Search with custom top-k
results=$(rag_search "authentication" --top-k 3 --collection "security_docs")
```

---

## Context Augmentation

### rag_augment_prompt

Inject context into a prompt for LLM consumption.

```bash
rag_augment_prompt PROMPT CONTEXT_ARRAY
```

**Parameters:**
- `PROMPT` - The question or prompt
- `CONTEXT_ARRAY` - Name of array containing context documents

**Returns:** Augmented prompt string

**Example:**
```bash
# Build context array
declare -a contexts=(
    "JSON objects can be created using json_object function"
    "Arrays are created with json_array"
    "Use json_escape for safe string handling"
)

# Generate augmented prompt
prompt=$(rag_augment_prompt "How do I work with JSON?" contexts)
echo "$prompt"
# Output:
# Context from relevant documents:
# [1] JSON objects can be created using json_object function
# [2] Arrays are created with json_array
# [3] Use json_escape for safe string handling
# ---
# Based on the above context, please answer:
# How do I work with JSON?
```

### rag_rerank

Rerank search results by relevance to query using embedding similarity.

```bash
rag_rerank RESULTS_JSON QUERY
```

**Parameters:**
- `RESULTS_JSON` - JSON array of search results
- `QUERY` - Original query for reranking

**Returns:** Reranked JSON array with `rerank_score` added

**Example:**
```bash
# Search then rerank
results=$(rag_search "JSON functions" --raw)
reranked=$(rag_rerank "$results" "How to create JSON objects")
```

---

## Management

### rag_delete

Delete a document from the RAG index.

```bash
rag_delete DOC_ID [--collection COLLECTION]
```

**Parameters:**
- `DOC_ID` - Document ID to delete
- `--collection` - Collection name

**Example:**
```bash
# Delete specific document
rag_delete "doc_123"

# Delete from specific collection
rag_delete "old_doc" --collection "archive"
```

### rag_stats

Get RAG collection statistics.

```bash
rag_stats [COLLECTION] [--json]
```

**Parameters:**
- `COLLECTION` - Collection name (optional, uses current)
- `--json` - Output as JSON

**Example:**
```bash
# Human-readable stats
rag_stats
# RAG Pipeline Statistics:
# ========================
#   Collection:      documents
#   Status:          initialized
#   Backend:         sqlite-vec
#   Embed Provider:  local
#   Document Count:  156
#   Session Stats:
#     Docs Ingested: 12
#     Chunks Created:47
#     Queries Made:  5

# JSON output
stats=$(rag_stats --json)
```

---

## Pipeline Architecture

### Ingestion Pipeline

```
Input File
    |
    v
Detect File Type (text/code/data)
    |
    v
Extract Text Content
    |
    v
Chunk Text (fixed/sentence/paragraph/code)
    |
    v
Generate Embeddings
    |
    v
Store in Vector Database
```

### Query Pipeline

```
Question
    |
    v
Generate Query Embedding
    |
    v
Search Vector Database
    |
    v
(Optional) Rerank Results
    |
    v
Format Context
    |
    v
Generate Augmented Prompt
```

---

## Integration Examples

### Building a Documentation Search System

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT}/lib/common.sh"

# Initialize RAG
rag_init "product_docs" --backend sqlite-vec --provider local

# Ingest documentation
rag_ingest "docs/" --recursive
rag_ingest "README.md"
rag_ingest "CHANGELOG.md"

# Interactive search
while true; do
    read -p "Search: " query
    [[ -z "$query" ]] && break

    result=$(rag_query "$query" --top-k 3)
    echo "$result" | jq -r '.data.context'
done
```

### Code Documentation Assistant

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT}/lib/common.sh"

# Initialize for code
rag_init "codebase" --provider local

# Ingest source files with code strategy
for file in lib/*.sh; do
    rag_ingest_file "$file" --strategy code
done

# Query about functions
result=$(rag_query "How does the validation system work?")
echo "$result" | jq -r '.data.augmented_prompt'
```

### Multi-Collection Setup

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT}/lib/common.sh"

# Create separate collections
rag_init "api_docs"
rag_ingest "docs/api/" --collection "api_docs"

rag_init "tutorials"
rag_ingest "docs/tutorials/" --collection "tutorials"

# Search specific collection
result=$(rag_search "authentication" --collection "api_docs")

# Search another
result=$(rag_search "getting started" --collection "tutorials")
```

---

## Best Practices

1. **Chunk Size**: Use 500-1000 characters for general text, larger (1000-2000) for code
2. **Overlap**: Use 10-20% overlap to maintain context across chunks
3. **Chunking Strategy**: Match strategy to content type (code for source files, sentence for prose)
4. **Top-K**: Start with 3-5 results, increase if context seems incomplete
5. **Metadata**: Always include source information for traceability
6. **Initialization**: Call `rag_init` once per session with desired settings

## See Also

- [Embeddings Reference](embeddings.md) - Embedding generation details
- [VectorDB Reference](vectordb.md) - Vector database operations
- [Agent Reference](agent.md) - AI agent primitives

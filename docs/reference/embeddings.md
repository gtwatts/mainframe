# Embeddings Library Reference

Embedding generation for semantic search and RAG workflows.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
# Or load explicitly:
mainframe_load embeddings
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENAI_API_KEY` | - | Required for OpenAI provider |
| `OLLAMA_HOST` | `http://localhost:11434` | Ollama server URL |
| `EMBED_MODEL` | per-provider | Override default model |
| `EMBED_CACHE_DIR` | `~/.mainframe/cache/embeddings` | Cache directory |
| `EMBED_CACHE_TTL` | `86400` | Cache TTL in seconds |

## Providers and Models

| Provider | Default Model | Dimensions |
|----------|--------------|------------|
| `openai` | text-embedding-ada-002 | 1536 |
| `openai` | text-embedding-3-small | 1536 |
| `openai` | text-embedding-3-large | 3072 |
| `ollama` | nomic-embed-text | 768 |
| `ollama` | all-minilm | 384 |
| `local` | TF-IDF fallback | 384 (configurable) |

---

## Core Functions

### embed_text

Generate embedding vector for text content.

```bash
embed_text CONTENT [PROVIDER]
```

**Parameters:**
- `CONTENT` - Text to embed
- `PROVIDER` - Provider name: `openai`, `ollama`, `local` (default: `ollama`)

**Returns:** JSON array of floating-point numbers

**Examples:**
```bash
# Using Ollama (default)
vector=$(embed_text "semantic search query")

# Using OpenAI
export OPENAI_API_KEY="sk-..."
vector=$(embed_text "hello world" "openai")

# Using local fallback (no API required)
vector=$(embed_text "offline embedding" "local")
```

---

### embed_batch

Batch embed lines from a file.

```bash
embed_batch FILE [PROVIDER]
```

**Parameters:**
- `FILE` - Path to text file (one text per line)
- `PROVIDER` - Provider name (default: `ollama`)

**Returns:** JSONL output with embeddings

**Output format:** `{"text":"original text","embedding":[...]}`

**Example:**
```bash
# Create input file
echo -e "query one\nquery two\nquery three" > texts.txt

# Batch embed
embed_batch texts.txt "ollama" > embeddings.jsonl
```

---

### embed_similarity

Calculate cosine similarity between two embedding vectors.

```bash
embed_similarity VEC1_JSON VEC2_JSON
```

**Parameters:**
- `VEC1_JSON` - First vector as JSON array
- `VEC2_JSON` - Second vector as JSON array

**Returns:** Cosine similarity (-1 to 1)

**Example:**
```bash
vec1=$(embed_text "happy dog" "local")
vec2=$(embed_text "joyful puppy" "local")
similarity=$(embed_similarity "$vec1" "$vec2")
echo "Similarity: $similarity"
```

---

### embed_normalize

Normalize embedding vector to unit length.

```bash
embed_normalize VECTOR_JSON
```

**Parameters:**
- `VECTOR_JSON` - Vector as JSON array

**Returns:** Normalized vector as JSON array

**Example:**
```bash
vec="[3.0,4.0]"  # magnitude = 5
normalized=$(embed_normalize "$vec")
# Returns: [0.6,0.8] (unit vector)
```

---

### embed_dimensions

Get embedding dimensions for a provider/model.

```bash
embed_dimensions PROVIDER [MODEL]
```

**Parameters:**
- `PROVIDER` - Provider name
- `MODEL` - Optional model override

**Returns:** Dimension count (integer)

**Example:**
```bash
dims=$(embed_dimensions "openai")           # 1536
dims=$(embed_dimensions "openai" "text-embedding-3-large")  # 3072
dims=$(embed_dimensions "ollama")           # 768
```

---

## Cache Functions

### embed_cache_get

Get cached embedding by text hash.

```bash
embed_cache_get TEXT_HASH
```

**Returns:** Cached vector JSON or failure (exit 1) if not found/expired.

---

### embed_cache_set

Cache embedding vector by text hash.

```bash
embed_cache_set TEXT_HASH VECTOR [PROVIDER] [MODEL]
```

**Parameters:**
- `TEXT_HASH` - Hash key for the cached content
- `VECTOR` - Embedding vector as JSON array
- `PROVIDER` - Provider name (for metadata)
- `MODEL` - Model name (for metadata)

---

### embed_cache_clear

Clear all cached embeddings.

```bash
embed_cache_clear
```

**Returns:** Number of removed entries

---

## Utility Functions

### embed_chunk

Chunk text into segments suitable for embedding.

```bash
embed_chunk TEXT [MAX_TOKENS] [OVERLAP]
```

**Parameters:**
- `TEXT` - Text to chunk
- `MAX_TOKENS` - Maximum tokens per chunk (default: 512)
- `OVERLAP` - Token overlap between chunks (default: 50)

**Returns:** One chunk per line

**Example:**
```bash
long_text=$(cat document.txt)
chunks=$(embed_chunk "$long_text" 256 25)

# Process each chunk
while IFS= read -r chunk; do
    vec=$(embed_text "$chunk" "local")
    echo "$vec"
done <<< "$chunks"
```

---

### embed_rank

Rank documents by similarity to query embedding.

```bash
embed_rank QUERY_VEC DOC_VECS_JSON
```

**Parameters:**
- `QUERY_VEC` - Query embedding vector
- `DOC_VECS_JSON` - Array of document embeddings

**Returns:** Document indices sorted by similarity (highest first)

**Example:**
```bash
query=$(embed_text "machine learning" "local")
docs="[$(embed_text "AI algorithms" "local"),$(embed_text "cooking recipes" "local")]"
ranking=$(embed_rank "$query" "$docs")
# Returns: 0 (AI is more relevant than cooking)
```

---

### embed_stats

Display embedding cache statistics.

```bash
embed_stats [--json]
```

**Example:**
```bash
embed_stats
# Output:
# Embedding Statistics:
#   Cache Hits:    42
#   Cache Misses:  8
#   Hit Ratio:     84%
#   Cached Items:  50
#   Cache Size:    245760 bytes
#   TTL:           86400 seconds

embed_stats --json
# {"cache_hits":42,"cache_misses":8,"hit_ratio_pct":84,...}
```

---

### embed_providers

Check which embedding providers are available.

```bash
embed_providers
```

**Example:**
```bash
embed_providers
# Output:
# Embedding Providers:
# ====================
# [OK] openai - API key configured
#      Model: text-embedding-ada-002 (1536 dims)
# [OK] ollama - Server available at http://localhost:11434
#      Model: nomic-embed-text (768 dims)
# [OK] local - Always available (TF-IDF fallback)
#      Dimensions: 384 (configurable)
```

---

## Common Patterns

### Semantic Search

```bash
# Build index
while IFS= read -r doc; do
    vec=$(embed_text "$doc" "ollama")
    echo "$vec" >> index.jsonl
done < documents.txt

# Search
query_vec=$(embed_text "search query" "ollama")
best_idx=0
best_sim=-1

idx=0
while IFS= read -r doc_vec; do
    sim=$(embed_similarity "$query_vec" "$doc_vec")
    if (( $(echo "$sim > $best_sim" | bc -l) )); then
        best_sim="$sim"
        best_idx=$idx
    fi
    ((idx++))
done < index.jsonl

echo "Best match: line $best_idx (similarity: $best_sim)"
```

### RAG with Chunking

```bash
# Chunk and embed document
long_doc=$(cat document.md)
chunks=$(embed_chunk "$long_doc" 512 50)

# Find most relevant chunk for query
query_vec=$(embed_text "user question" "ollama")
best_chunk=""
best_sim=-1

while IFS= read -r chunk; do
    chunk_vec=$(embed_text "$chunk" "ollama")
    sim=$(embed_similarity "$query_vec" "$chunk_vec")
    if (( $(echo "$sim > $best_sim" | bc -l) )); then
        best_sim="$sim"
        best_chunk="$chunk"
    fi
done <<< "$chunks"

# Use best_chunk as context for LLM
```

### Caching Best Practices

```bash
# Set custom cache location
export EMBED_CACHE_DIR="/tmp/my_embeddings"

# Set shorter TTL for dynamic content
export EMBED_CACHE_TTL=3600  # 1 hour

# Check cache stats periodically
embed_stats --json | jq '.hit_ratio_pct'

# Clear cache when needed
embed_cache_clear
```

---

## Function Summary

| Function | Description |
|----------|-------------|
| `embed_text` | Generate embedding for text |
| `embed_batch` | Batch embed from file |
| `embed_similarity` | Cosine similarity between vectors |
| `embed_normalize` | Normalize vector to unit length |
| `embed_dimensions` | Get dimensions for provider/model |
| `embed_cache_get` | Get cached embedding |
| `embed_cache_set` | Cache embedding |
| `embed_cache_clear` | Clear all cached embeddings |
| `embed_chunk` | Chunk text for embedding |
| `embed_rank` | Rank documents by similarity |
| `embed_stats` | Display cache statistics |
| `embed_providers` | List available providers |

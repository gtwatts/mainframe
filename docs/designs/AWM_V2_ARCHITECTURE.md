# AWM v2: Infinite Agent Memory Architecture

> **Version**: 2.0 | **Status**: Design | **Author**: MAINFRAME Team

## Executive Summary

AWM v2 transforms MAINFRAME's Agent Working Memory from a file-based session store into a **multi-tiered, protocol-driven infinite memory system** that enables agents to:

1. Process unlimited data without context overflow
2. Communicate efficiently with other agents
3. Persist knowledge across sessions with semantic retrieval
4. Work on any system (with or without Redis/ChromaDB)

## Design Principles

| Principle | Description |
|-----------|-------------|
| **Zero Dependencies** | File-based core works on any system |
| **Graceful Enhancement** | Auto-detect Redis/ChromaDB for better performance |
| **Context as Currency** | Every token is valuable; minimize waste |
| **Memory Pointers** | Store large data externally, pass references |
| **Semantic Preservation** | Chunking preserves meaning, not just bytes |
| **Protocol Compatibility** | Align with A2A/MCP standards |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         AGENT LAYER                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │   Agent 1   │  │   Agent 2   │  │   Agent N   │              │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘              │
└─────────┼────────────────┼────────────────┼─────────────────────┘
          │                │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    AWM PROTOCOL LAYER                            │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  USOP v4 Messages: request | response | discovery | handoff│   │
│  │  Agent Cards: capabilities, context_budget, specialization │   │
│  │  contextId: session continuity across agent boundaries     │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                  CONTEXT STREAMING ENGINE                        │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐    │
│  │ Semantic Chunk │  │ Memory Pointer │  │  Pre-Rot Mgmt  │    │
│  │    Manager     │  │    System      │  │   (75% cap)    │    │
│  └────────────────┘  └────────────────┘  └────────────────┘    │
│                                                                  │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐    │
│  │  Token Budget  │  │  Observation   │  │  Compression   │    │
│  │   Enforcer     │  │    Masking     │  │    Pipeline    │    │
│  └────────────────┘  └────────────────┘  └────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    TIERED MEMORY MANAGER                         │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  HOT TIER (Context Window)                                  │ │
│  │  - Current conversation                                     │ │
│  │  - Active tool results                                      │ │
│  │  - Working memory                        [Dynamic Budget]   │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  WARM TIER (Session Cache)                                  │ │
│  │  - Recent discoveries                                       │ │
│  │  - Compressed checkpoints                                   │ │
│  │  - Parent agent context                    [LRU + 1hr TTL]  │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  COLD TIER (Persistent Archive)                             │ │
│  │  - Semantic search index                                    │ │
│  │  - Historical sessions                                      │ │
│  │  - Cross-session knowledge              [Vector DB / Files] │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   STORAGE ABSTRACTION LAYER                      │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐    │
│  │   File Store   │  │  Redis Store   │  │ ChromaDB Store │    │
│  │   (Default)    │  │  (If avail)    │  │   (If avail)   │    │
│  │                │  │                │  │                │    │
│  │  - JSONL logs  │  │  - TimeSeries  │  │  - Embeddings  │    │
│  │  - Atomic ops  │  │  - Pub/Sub     │  │  - Semantic    │    │
│  │  - No deps     │  │  - Fast K/V    │  │  - Similarity  │    │
│  └────────────────┘  └────────────────┘  └────────────────┘    │
│                                                                  │
│  Priority: ChromaDB > Redis > File (auto-detected at startup)   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component Specifications

### 1. Storage Abstraction Layer (`lib/awm_storage.sh`)

**Purpose**: Unified interface to multiple storage backends with automatic fallback.

#### Interface

```bash
# Backend detection and initialization
awm_storage_init                           # Auto-detect available backends
awm_storage_backend                        # Returns: file|redis|chromadb

# Key-Value Operations
awm_store_set "key" "value" [ttl_seconds]  # Store with optional TTL
awm_store_get "key" [default]              # Retrieve with fallback
awm_store_delete "key"                     # Remove key
awm_store_exists "key"                     # Check existence (0=yes, 1=no)

# List/Queue Operations
awm_store_push "list" "value"              # Append to list
awm_store_pop "list"                       # Remove and return first
awm_store_range "list" start end           # Get range (0-indexed)
awm_store_len "list"                       # List length

# Search Operations (ChromaDB-enhanced)
awm_store_search "query" [limit]           # Semantic search (falls back to grep)
awm_store_index "key" "content" [metadata] # Add to search index

# Pub/Sub (Redis-enhanced, file-based fallback)
awm_store_publish "channel" "message"      # Publish message
awm_store_subscribe "channel" callback     # Subscribe with callback
```

#### Backend Detection Logic

```bash
awm_storage_init() {
    # Check ChromaDB (highest priority for semantic search)
    if curl -sf "http://localhost:8000/api/v1/heartbeat" >/dev/null 2>&1; then
        _AWM_STORAGE_BACKEND="chromadb"
        _AWM_CHROMADB_URL="http://localhost:8000"
    # Check Redis Stack (second priority for speed)
    elif redis-cli -p 6380 ping >/dev/null 2>&1; then
        _AWM_STORAGE_BACKEND="redis"
        _AWM_REDIS_PORT=6380
    elif redis-cli ping >/dev/null 2>&1; then
        _AWM_STORAGE_BACKEND="redis"
        _AWM_REDIS_PORT=6379
    # Fallback to file-based (always available)
    else
        _AWM_STORAGE_BACKEND="file"
        _AWM_STORAGE_DIR="${MAINFRAME_AWM_DIR:-$HOME/.mainframe/awm}/store"
        mkdir -p "$_AWM_STORAGE_DIR"
    fi

    # Allow explicit override
    [[ -n "$MAINFRAME_STORAGE" ]] && _AWM_STORAGE_BACKEND="$MAINFRAME_STORAGE"
}
```

---

### 2. Context Streaming Engine (`lib/awm_stream.sh`)

**Purpose**: Prevent context overflow through intelligent data management.

#### Token Budget System

```bash
# Model-aware budget initialization
awm_budget_init [model]                    # Auto-detect or specify model
awm_budget_max                             # Returns max tokens for model
awm_budget_used                            # Current token usage estimate
awm_budget_remaining                       # Available tokens
awm_budget_fits content                    # 0 if fits, 1 if exceeds

# Model detection table
declare -A AWM_MODEL_LIMITS=(
    ["claude-3-opus"]=200000
    ["claude-3-sonnet"]=200000
    ["claude-3-haiku"]=200000
    ["gpt-4-turbo"]=128000
    ["gpt-4o"]=128000
    ["gpt-4"]=8192
    ["gpt-3.5-turbo"]=16385
    ["gemini-pro"]=1000000
    ["glm-4"]=128000
    ["default"]=32000
)

# Pre-rot threshold (trigger compression at 75%)
AWM_PREROT_THRESHOLD=0.75
```

#### Memory Pointer System

```bash
# Store large content, return reference
awm_pointer_create "content" [type]        # Returns: ptr://awm/[hash]
awm_pointer_resolve "ptr://awm/[hash]"     # Returns: original content
awm_pointer_exists "ptr://awm/[hash]"      # Check if pointer valid

# Auto-pointer for tool results
awm_wrap_result "large_output" [max_tokens]
# If output > max_tokens:
#   1. Store in cold tier
#   2. Return: {"_ptr": "ptr://awm/abc123", "preview": "first 100 chars...", "tokens": 5000}
# Else:
#   Return original output
```

#### Semantic Chunking

```bash
# Chunk content by type
awm_chunk "content" [type] [max_tokens]    # Returns: JSON array of chunks

# Type detection and strategy
awm_detect_content_type "content"          # Returns: code|prose|json|markdown|mixed

# Chunking strategies
awm_chunk_code "content" max_tokens        # Split at function/class boundaries
awm_chunk_prose "content" max_tokens       # Split at paragraph/sentence boundaries
awm_chunk_json "content" max_tokens        # Split at object/array boundaries
awm_chunk_semantic "content" max_tokens    # Use embedding similarity (if ChromaDB)
```

#### Compression Pipeline

```bash
# Progressive compression stages
awm_compress "content" level               # level: 1-5 (1=light, 5=aggressive)

# Level 1: Remove whitespace, normalize
# Level 2: Remove comments, docstrings
# Level 3: Summarize large blocks (if LLM available)
# Level 4: Extract key facts only
# Level 5: Single-line summary

# Observation masking (reversible)
awm_mask_observations session_id           # Replace tool outputs with pointers
awm_unmask_observations session_id         # Restore from pointers on demand
```

---

### 3. Agent Communication Protocol (`lib/awm_protocol.sh`)

**Purpose**: Standardized message passing between agents using USOP extensions.

#### Message Types

```bash
# USOP v4 Message Envelope
{
    "usop": "4.0",
    "type": "agent_message",
    "timestamp": "2026-01-30T23:45:00Z",
    "message": {
        "id": "msg_abc123",
        "type": "request|response|discovery|handoff|heartbeat",
        "from": "agent_id",
        "to": "agent_id|broadcast",
        "contextId": "ctx_session_123",
        "payload": { ... },
        "metadata": {
            "tokens_used": 150,
            "priority": "high|normal|low",
            "ttl": 3600
        }
    }
}
```

#### Agent Cards (Capability Discovery)

```bash
# Register agent capabilities
awm_agent_register "agent_id" capabilities...
# Creates agent card:
{
    "agent_id": "researcher_01",
    "capabilities": ["web_search", "document_analysis", "summarization"],
    "context_budget": 64000,
    "specialization": "research",
    "status": "available",
    "registered_at": "2026-01-30T23:45:00Z"
}

# Discover agents by capability
awm_agent_find "web_search"                # Returns: list of agent_ids
awm_agent_card "agent_id"                  # Returns: full agent card
awm_agent_status "agent_id"                # Returns: available|busy|offline
```

#### Message Operations

```bash
# Send message to specific agent
awm_send "target_agent" "type" "payload" [contextId]

# Broadcast to all agents with capability
awm_broadcast "capability" "type" "payload"

# Receive messages (blocking with timeout)
awm_receive [timeout_seconds]              # Returns: next message or empty

# Subscribe to message types
awm_subscribe "type" callback_function

# Context continuity
awm_context_new                            # Generate new contextId
awm_context_get                            # Get current contextId
awm_context_set "contextId"                # Set contextId for session
```

#### Handoff Protocol

```bash
# Prepare handoff package for sub-agent
awm_handoff_prepare "target_agent" [max_tokens]
# Returns:
{
    "type": "handoff",
    "contextId": "ctx_abc123",
    "parent_session": "session_xyz",
    "discoveries": [...],           # All parent discoveries
    "context_summary": "...",       # Compressed current context
    "checkpoints": {...},           # Key state (< 1KB each)
    "pointers": {...},              # References to large data
    "budget_remaining": 45000       # Tokens available for child
}

# Accept handoff and initialize
awm_handoff_accept "handoff_package"       # Sets up child session

# Report back to parent
awm_handoff_complete "result_summary"      # Sends completion to parent
```

---

### 4. Tiered Memory Manager (`lib/awm_tiers.sh`)

**Purpose**: Automatic memory promotion/eviction across hot/warm/cold tiers.

#### Tier Definitions

```bash
# HOT TIER: In-memory, current session
# - Capacity: Dynamic (model context window)
# - TTL: Session lifetime
# - Access: O(1) via associative arrays
declare -A _AWM_HOT_TIER

# WARM TIER: Fast access, recent data
# - Capacity: 10MB or 50K tokens
# - TTL: 1 hour or session + 30 min
# - Access: File or Redis
_AWM_WARM_DIR="${MAINFRAME_AWM_DIR}/warm"

# COLD TIER: Persistent, searchable archive
# - Capacity: Unlimited
# - TTL: 30 days default
# - Access: ChromaDB or JSONL files
_AWM_COLD_DIR="${MAINFRAME_AWM_DIR}/cold"
```

#### Tier Operations

```bash
# Write to appropriate tier (auto-selects based on size/importance)
awm_tier_write "key" "value" [importance]  # importance: critical|high|normal|low

# Read with tier traversal (hot → warm → cold)
awm_tier_read "key" [default]              # Auto-promotes to hot on access

# Explicit tier operations
awm_hot_set "key" "value"                  # Direct hot tier write
awm_warm_set "key" "value" [ttl]           # Direct warm tier write
awm_cold_set "key" "value" [metadata]      # Direct cold tier write (indexed)

# Tier statistics
awm_tier_stats                             # Returns: JSON with tier usage
```

#### Eviction Policies

```bash
# Automatic eviction triggers
AWM_HOT_MAX_TOKENS=0.75 * model_limit      # 75% of context window
AWM_WARM_MAX_SIZE=10485760                 # 10MB
AWM_COLD_TTL_DAYS=30                       # 30 days

# Eviction strategies
awm_evict_hot [target_tokens]              # LRU eviction, move to warm
awm_evict_warm [target_size]               # LRU eviction, move to cold
awm_evict_cold [days]                      # Age-based deletion

# Importance-based retention
# - "critical": Never evicted automatically
# - "high": Last to be evicted
# - "normal": Standard LRU
# - "low": First to be evicted
```

#### Semantic Search (Cold Tier)

```bash
# Search across all cold tier data
awm_search "query" [limit] [filters]
# Returns:
[
    {
        "key": "discovery_abc",
        "content": "API requires OAuth2...",
        "score": 0.92,
        "metadata": {"session": "xyz", "agent": "auth_researcher"}
    },
    ...
]

# Semantic similarity for related content
awm_similar "content" [limit]              # Find similar entries
```

---

## Integration with Existing AWM

### Backward Compatibility

AWM v2 is **fully backward compatible** with AWM v1:

```bash
# Old API still works
awm_init "task"                 # → Creates session in hot tier
awm_checkpoint "key" "value"    # → Writes to hot tier
awm_discovery "finding"         # → Writes to hot tier with critical importance
awm_get "key"                   # → Reads from tier chain
awm_summary                     # → Aggregates across tiers

# New API for enhanced features
awm_init "task" --with-protocol # Enable agent communication
awm_init "task" --budget 64000  # Set explicit token budget
```

### Migration Path

1. **Phase 1**: Install new libraries alongside existing awm.sh
2. **Phase 2**: awm.sh imports awm_storage.sh, awm_stream.sh, etc.
3. **Phase 3**: Old functions become thin wrappers over new system
4. **Phase 4**: Deprecation warnings for direct file access

---

## Configuration

### Environment Variables

```bash
# Storage backend (auto-detected if not set)
MAINFRAME_STORAGE=file|redis|chromadb

# Redis configuration
MAINFRAME_REDIS_HOST=localhost
MAINFRAME_REDIS_PORT=6380

# ChromaDB configuration
MAINFRAME_CHROMADB_URL=http://localhost:8000
MAINFRAME_CHROMADB_COLLECTION=awm_memory

# Tier configuration
MAINFRAME_AWM_DIR=~/.mainframe/awm
MAINFRAME_HOT_MAX_RATIO=0.75
MAINFRAME_WARM_MAX_MB=10
MAINFRAME_COLD_TTL_DAYS=30

# Token budget (auto-detected from model if not set)
MAINFRAME_TOKEN_BUDGET=64000
MAINFRAME_MODEL=claude-3-sonnet
```

---

## Usage Examples

### Example 1: Large Data Processing

```bash
source lib/common.sh

# Initialize with budget
awm_init "data-processor" --budget auto

# Process large file without filling context
while IFS= read -r line; do
    # Wrap result (auto-stores if too large)
    result=$(awm_wrap_result "$(process_line "$line")" 1000)

    # Check budget before continuing
    if ! awm_budget_fits 500; then
        awm_evict_hot  # Free up space
    fi

    awm_log "progress" "$result"
done < huge_file.csv

# Get summary without loading all data
summary=$(awm_summary --compressed)
```

### Example 2: Multi-Agent Collaboration

```bash
# Agent 1: Researcher
source lib/common.sh
awm_init "researcher" --with-protocol

# Register capabilities
awm_agent_register "researcher_01" "web_search" "summarization"

# Do research
result=$(web_search "topic")
awm_discovery "Found: key insight from research"

# Hand off to writer
handoff=$(awm_handoff_prepare "writer_01" 32000)
awm_send "writer_01" "handoff" "$handoff"

# Wait for completion
response=$(awm_receive 300)  # 5 min timeout
```

```bash
# Agent 2: Writer
source lib/common.sh

# Accept handoff
msg=$(awm_receive)
awm_handoff_accept "$(echo "$msg" | jq -r '.payload')"

# Write using inherited discoveries
# (discoveries automatically available via awm_get)
article=$(write_article)

# Complete and report back
awm_handoff_complete "Article complete: 2500 words"
```

### Example 3: Semantic Search Across Sessions

```bash
source lib/common.sh
awm_storage_init

# Search for relevant past learnings
results=$(awm_search "authentication patterns" 5)

# Use in current context
echo "$results" | jq -r '.[].content' | while read -r insight; do
    echo "Previous learning: $insight"
done
```

---

## Performance Characteristics

| Operation | File Backend | Redis Backend | ChromaDB Backend |
|-----------|-------------|---------------|------------------|
| Key-Value Read | O(1) | O(1) | O(1) |
| Key-Value Write | O(1) | O(1) | O(1) |
| List Append | O(1) | O(1) | O(n) |
| Search (text) | O(n) | O(n) | O(1) semantic |
| Pub/Sub Latency | 100ms | 1ms | N/A |
| Cold Storage | Unlimited | Unlimited | Unlimited |

---

## Security Considerations

1. **Namespace Isolation**: Each agent session is isolated by session_id
2. **No Cross-Agent Data Access**: Agents can only access data via protocol
3. **TTL Enforcement**: Sensitive data can have short TTLs
4. **Audit Trail**: All tier transitions logged

---

## Future Enhancements

1. **Distributed AWM**: Multi-machine session sharing via Redis Cluster
2. **LLM Compression**: Use small model for intelligent summarization
3. **Real-time Sync**: WebSocket-based agent communication
4. **Encryption**: At-rest encryption for cold tier

---

*AWM v2: Enabling infinite agent memory through intelligent tiering and protocols.*

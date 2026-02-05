# Mainframe Advanced Memory Architecture (AMMA V3)

## Executive Summary

This document presents the design for **Mainframe Advanced Memory Architecture (AMMA V3)**, a comprehensive multi-tier memory system that transforms how AI agents store, retrieve, and reason about information. Building upon the existing AWM (Agent Working Memory) system, AMMA V3 introduces cognitive-inspired memory types, semantic retrieval, and distributed memory capabilities.

### Key Innovations

1. **Five-Tier Memory Hierarchy**: From immediate context to external knowledge graphs
2. **Cognitive Memory Types**: Episodic, procedural, and declarative memory systems
3. **Semantic Retrieval**: Vector-based similarity search with embedding integration
4. **Intelligent Lifecycle Management**: Automatic promotion, demotion, and consolidation
5. **Cross-Agent Memory Sharing**: Distributed memory protocols for multi-agent systems

---

## 1. Multi-Tier Memory Architecture

### 1.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AMMA V3 MEMORY HIERARCHY                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ L1: IMMEDIATE CONTEXT  (Sub-millisecond access)                     │   │
│  │ ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │ │ Shell Variables │ Active Context │ Current Intent │ Working Set  │ │   │
│  │ └─────────────────────────────────────────────────────────────────┘ │   │
│  │ Size: ~4KB │ Latency: <0.1ms │ Volatility: Session-only            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼ Promote on access                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ L2: WORKING MEMORY  (Fast file-based, session-scoped)               │   │
│  │ ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │ │ Hot Tier │ Recent Discoveries │ Active Checkpoints │ Progress    │ │   │
│  │ └─────────────────────────────────────────────────────────────────┘ │   │
│  │ Size: ~10MB │ Latency: <1ms │ Volatility: Session + 24h             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼ Promote on importance                 │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ L3: SHORT-TERM MEMORY  (Compressed, queryable)                      │   │
│  │ ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │ │ Warm Tier │ Categorized Logs │ Session History │ Compressed      │ │   │
│  │ └─────────────────────────────────────────────────────────────────┘ │   │
│  │ Size: ~100MB │ Latency: <10ms │ Volatility: 7 days                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼ Promote on semantic relevance         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ L4: LONG-TERM MEMORY  (Persistent, semantic search)                 │   │
│  │ ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │ │ Cold Tier │ Vector Embeddings │ Knowledge Base │ Project Memory  │ │   │
│  │ └─────────────────────────────────────────────────────────────────┘ │   │
│  │ Size: ~1GB │ Latency: <100ms │ Volatility: Indefinite               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼ Promote on cross-session value        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ L5: EXTERNAL MEMORY  (Vector DB, Knowledge Graphs)                  │   │
│  │ ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │ │ ChromaDB │ Pinecone │ Qdrant │ Neo4j │ Shared Memory Mesh       │ │   │
│  │ └─────────────────────────────────────────────────────────────────┘ │   │
│  │ Size: Unlimited │ Latency: Variable │ Volatility: Persistent        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Tier Characteristics

| Tier | Storage | Latency | Capacity | TTL | Use Case |
|------|---------|---------|----------|-----|----------|
| L1 | RAM (Bash assoc arrays) | <0.1ms | ~4KB | Session | Immediate context, active variables |
| L2 | Fast disk (SSD) | <1ms | ~10MB | 24h | Session state, checkpoints, discoveries |
| L3 | Compressed files | <10ms | ~100MB | 7d | Historical logs, session summaries |
| L4 | Persistent storage + vectors | <100ms | ~1GB | Indefinite | Knowledge base, semantic index |
| L5 | External services | Variable | Unlimited | Persistent | Cross-agent memory, global knowledge |

---

## 2. Cognitive Memory Types

### 2.1 Memory Type Taxonomy

AMMA V3 implements three cognitive-inspired memory types, each optimized for different retrieval patterns:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        COGNITIVE MEMORY SYSTEMS                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     EPISODIC MEMORY                                 │   │
│  │  Event sequences with temporal and causal relationships             │   │
│  │                                                                     │   │
│  │  Structure: {                                                       │   │
│  │    event_id: "uuid",                                                │   │
│  │    timestamp: "2026-02-05T06:05:00Z",                               │   │
│  │    event_type: "action|observation|decision|error",                 │   │
│  │    content: "What happened",                                        │   │
│  │    context: { location, task, participants },                       │   │
│  │    causal_links: [prev_event, next_event],                          │   │
│  │    emotional_valence: "positive|neutral|negative",                  │   │
│  │    importance_score: 0.85                                           │   │
│  │  }                                                                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    PROCEDURAL MEMORY                                │   │
│  │  Learned patterns, strategies, and operational knowledge            │   │
│  │                                                                     │   │
│  │  Structure: {                                                       │   │
│  │    pattern_id: "uuid",                                              │   │
│  │    pattern_type: "workflow|heuristic|strategy|template",            │   │
│  │    trigger_conditions: [...],                                       │   │
│  │    action_sequence: [...],                                          │   │
│  │    success_rate: 0.92,                                              │   │
│  │    usage_count: 47,                                                 │   │
│  │    last_used: "2026-02-05T06:00:00Z",                               │   │
│  │    embedding: [0.12, -0.34, ...]                                    │   │
│  │  }                                                                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                   DECLARATIVE MEMORY                                │   │
│  │  Facts, concepts, and semantic knowledge                            │   │
│  │                                                                     │   │
│  │  Structure: {                                                       │   │
│  │    fact_id: "uuid",                                                 │   │
│  │    fact_type: "entity|relation|attribute|rule",                     │   │
│  │    subject: "API rate limit",                                       │   │
│  │    predicate: "is",                                                 │   │
│  │    object: "100 requests per minute",                               │   │
│  │    confidence: 0.95,                                                │   │
│  │    source: "documentation",                                         │   │
│  │    expiration: "2026-03-05T00:00:00Z",                              │   │
│  │    embedding: [0.23, 0.45, ...]                                     │   │
│  │  }                                                                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Memory Schemas

#### Episodic Memory Schema
```json
{
  "schema_version": "1.0",
  "memory_type": "episodic",
  "event": {
    "id": "evt_abc123",
    "timestamp": 1738754700.123456,
    "iso_timestamp": "2026-02-05T06:05:00.123Z",
    "session_id": "sess_xyz789",
    "sequence_number": 42
  },
  "content": {
    "type": "decision",
    "description": "Chose PostgreSQL over MySQL for transaction support",
    "reasoning": "User requires ACID compliance for financial data",
    "alternatives_considered": ["MySQL", "SQLite"],
    "outcome": "successful"
  },
  "context": {
    "task_id": "database-selection",
    "parent_task": "backend-design",
    "agent_id": "main-agent",
    "environment": "production",
    "user_preferences": ["reliability", "consistency"]
  },
  "relationships": {
    "previous_event": "evt_abc122",
    "next_event": "evt_abc124",
    "related_events": ["evt_abc100", "evt_abc101"],
    "causal_parents": ["evt_abc120"],
    "causal_children": ["evt_abc125"]
  },
  "metadata": {
    "importance": 0.85,
    "emotional_valence": "positive",
    "access_count": 3,
    "last_accessed": 1738755000.000000,
    "consolidated": false
  }
}
```

#### Procedural Memory Schema
```json
{
  "schema_version": "1.0",
  "memory_type": "procedural",
  "pattern": {
    "id": "pat_def456",
    "name": "fastapi-error-handling",
    "created_at": "2026-02-01T00:00:00Z",
    "updated_at": "2026-02-05T06:05:00Z"
  },
  "specification": {
    "trigger_conditions": [
      "task involves FastAPI",
      "error handling mentioned",
      "production deployment"
    ],
    "required_context": ["framework:fastapi", "environment:production"],
    "action_sequence": [
      "1. Define custom exception classes",
      "2. Create exception handlers",
      "3. Add structured logging",
      "4. Implement retry logic"
    ],
    "code_template": "from fastapi import HTTPException...",
    "parameters": {
      "retry_count": {"default": 3, "type": "int"},
      "log_level": {"default": "INFO", "type": "string"}
    }
  },
  "performance": {
    "success_rate": 0.94,
    "usage_count": 23,
    "avg_execution_time_ms": 150,
    "failure_modes": [
      {"cause": "missing_dependencies", "count": 2}
    ]
  },
  "embedding": {
    "vector": [0.12, -0.34, 0.56, ...],
    "model": "nomic-embed-text",
    "dimensions": 768
  }
}
```

#### Declarative Memory Schema
```json
{
  "schema_version": "1.0",
  "memory_type": "declarative",
  "fact": {
    "id": "fact_ghi789",
    "type": "attribute",
    "created_at": "2026-02-05T06:00:00Z",
    "updated_at": "2026-02-05T06:05:00Z",
    "expiration": "2027-02-05T06:00:00Z"
  },
  "triple": {
    "subject": "Mainframe vectordb.sh",
    "predicate": "supports",
    "object": "ChromaDB, Pinecone, Qdrant, SQLite-vec"
  },
  "attributes": {
    "confidence": 0.99,
    "source": "source_code:lib/vectordb.sh",
    "verification_status": "verified",
    "category": "technical_capability"
  },
  "context": {
    "project": "mainframe",
    "applicable_versions": ["1.0.0+"],
    "tags": ["database", "vector", "integration"]
  },
  "embedding": {
    "vector": [0.23, 0.45, -0.12, ...],
    "model": "nomic-embed-text",
    "dimensions": 768
  }
}
```

---

## 3. Memory Importance and Attention Mechanisms

### 3.1 Importance Scoring Algorithm

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    IMPORTANCE SCORING CALCULATION                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   importance_score = base_score × recency_factor × relevance_factor         │
│                                                                             │
│   Where:                                                                    │
│   ┌──────────────────────────────────────────────────────────────────┐     │
│   │ BASE SCORE (0-100)                                               │     │
│   │                                                                  │     │
│   │   Explicit Signals:          Weight:                             │     │
│   │   ├─ User marked important   +50                                 │     │
│   │   ├─ Error/failure event     +40                                 │     │
│   │   ├─ Successful outcome      +30                                 │     │
│   │   ├─ Decision point          +25                                 │     │
│   │   ├─ Discovery/insight       +20                                 │     │
│   │   └─ Routine observation     +5                                  │     │
│   │                                                                  │     │
│   │   Intrinsic Factors:                                             │     │
│   │   ├─ Uniqueness (rarity)     × 1.0-2.0                           │     │
│   │   ├─ Complexity              × 1.0-1.5                           │     │
│   │   └─ Cross-reference count   × 1.0-1.3                           │     │
│   └──────────────────────────────────────────────────────────────────┘     │
│                                                                             │
│   ┌──────────────────────────────────────────────────────────────────┐     │
│   │ RECENCY FACTOR (decay over time)                                 │     │
│   │                                                                  │     │
│   │   recency = 1 / (1 + ln(1 + hours_since_access / half_life))     │     │
│   │                                                                  │     │
│   │   Half-lives by tier:                                            │     │
│   │   ├─ L1 (Immediate):    1 minute                                 │     │
│   │   ├─ L2 (Working):      1 hour                                   │     │
│   │   ├─ L3 (Short-term):   24 hours                                 │     │
│   │   ├─ L4 (Long-term):    30 days                                  │     │
│   │   └─ L5 (External):     365 days                                 │     │
│   └──────────────────────────────────────────────────────────────────┘     │
│                                                                             │
│   ┌──────────────────────────────────────────────────────────────────┐     │
│   │ RELEVANCE FACTOR (to current context)                            │     │
│   │                                                                  │     │
│   │   relevance = cosine_similarity(current_context_embedding,       │     │
│   │                                    memory_embedding)             │     │
│   │                                                                  │     │
│   │   Boosts:                                                        │     │
│   │   ├─ Same task/project:      +0.2                                │     │
│   │   ├─ Similar environment:    +0.1                                │     │
│   │   └─ Shared participants:    +0.15                               │     │
│   └──────────────────────────────────────────────────────────────────┘     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Attention Mechanism

The attention system determines which memories are actively available for retrieval:

```bash
# Attention window configuration
AMMA_ATTENTION_WINDOW_SIZE=20      # Max memories in focus
AMMA_ATTENTION_REFRESH_INTERVAL=60  # Seconds between re-evaluation

# Attention scoring combines:
# 1. Importance score (from above)
# 2. Current task relevance
# 3. Temporal locality (recently accessed)
# 4. Predictive relevance (what might be needed next)

ammma_attention_update() {
    local current_context="$1"
    
    # 1. Score all memories in L1-L3
    # 2. Select top N by attention score
    # 3. Promote to L1 if not already
    # 4. Demote from L1 if score below threshold
}
```

---

## 4. Automatic Tier Management

### 4.1 Promotion and Demotion Policies

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    TIER TRANSITION POLICIES                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  PROMOTION RULES (lower tier → higher tier):                                │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ L2 → L1: Working → Immediate                                        │   │
│  │   • Access count > 3 in 5 minutes                                   │   │
│  │   • Explicitly marked as "critical"                                 │   │
│  │   • Currently needed for active task                                │   │
│  │   • Part of attention window                                        │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │ L3 → L2: Short-term → Working                                       │   │
│  │   • Accessed within last 10 minutes                                 │   │
│  │   • Importance score > 0.7                                          │   │
│  │   • Relevance to current context > 0.6                              │   │
│  │   • Session resumed after interruption                              │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │ L4 → L3: Long-term → Short-term                                     │   │
│  │   • Semantic similarity to current query > 0.8                      │   │
│  │   • Retrieved during search                                         │   │
│  │   • User explicitly requested                                       │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │ L5 → L4: External → Long-term                                       │   │
│  │   • Accessed more than 3 times                                      │   │
│  │   • Caching policy: frequently_used                                 │   │
│  │   • Network latency exceeds threshold                               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  DEMOTION RULES (higher tier → lower tier):                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ L1 → L2: Immediate → Working                                        │   │
│  │   • Not accessed for 2 minutes                                      │   │
│  │   • Attention window full and lower priority                        │   │
│  │   • Session context switch                                          │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │ L2 → L3: Working → Short-term                                       │   │
│  │   • Session closed                                                  │   │
│  │   • Not accessed for 1 hour                                         │   │
│  │   • Compression threshold exceeded                                  │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │ L3 → L4: Short-term → Long-term                                     │   │
│  │   • Age exceeds 7 days                                              │   │
│  │   • Storage quota exceeded                                          │   │
│  │   • Explicit archive command                                        │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │ L4 → L5: Long-term → External                                       │   │
│  │   • Local storage exceeds 1GB                                       │   │
│  │   • Marked for global sharing                                       │   │
│  │   • Access pattern suggests cloud retrieval OK                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Consolidation Algorithm

Memory consolidation simulates sleep-like processes that merge and summarize memories:

```bash
# Consolidation runs periodically (e.g., every 6 hours or on session close)
ammma_consolidate() {
    local session_id="$1"
    
    # Phase 1: Extract patterns from episodic memories
    _ammma_extract_patterns "$session_id"
    
    # Phase 2: Merge similar episodic memories
    _ammma_merge_episodes "$session_id"
    
    # Phase 3: Update procedural memory with new patterns
    _ammma_update_procedures "$session_id"
    
    # Phase 4: Generate summaries for long-term storage
    _ammma_create_summaries "$session_id"
    
    # Phase 5: Garbage collect obsolete memories
    _ammma_gc_memories "$session_id"
}
```

---

## 5. Semantic Memory Retrieval

### 5.1 Multi-Modal Retrieval Pipeline

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SEMANTIC RETRIEVAL PIPELINE                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Query: "How do I handle errors in FastAPI?"                               │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │ 1. QUERY UNDERSTANDING                                              │  │
│   │                                                                     │  │
│   │    • Intent classification: "how_to"                                │  │
│   │    • Entity extraction: ["FastAPI", "error handling"]               │  │
│   │    • Generate embedding: [0.23, -0.45, 0.67, ...]                   │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                        │
│                                    ▼                                        │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │ 2. PARALLEL TIER SEARCH                                             │  │
│   │                                                                     │  │
│   │    ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │  │
│   │    │   L1-L2     │  │    L3       │  │   L4-L5     │               │  │
│   │    │ Exact Match │  │ Keyword     │  │ Semantic    │               │  │
│   │    │             │  │ Search      │  │ Search      │               │  │
│   │    │ Results: 2  │  │ Results: 5  │  │ Results: 8  │               │  │
│   │    └─────────────┘  └─────────────┘  └─────────────┘               │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                        │
│                                    ▼                                        │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │ 3. RESULT FUSION (Reciprocal Rank Fusion)                           │  │
│   │                                                                     │  │
│   │    score = Σ 1 / (k + rank_i)  where k=60                           │  │
│   │                                                                     │  │
│   │    Combined Results (top 10):                                       │  │
│   │    ┌─────────────────────────────────────────────────────────────┐  │  │
│   │    │ 1. Error handling pattern (procedural)      Score: 0.95   │  │  │
│   │    │ 2. FastAPI exception docs (declarative)     Score: 0.89   │  │  │
│   │    │ 3. Previous project setup (episodic)        Score: 0.87   │  │  │
│   │    │ 4. API design decision (episodic)           Score: 0.82   │  │  │
│   │    │ ...                                                   │  │  │
│   │    └─────────────────────────────────────────────────────────────┘  │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                        │
│                                    ▼                                        │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │ 4. CONTEXTUAL RERANKING                                             │  │
│   │                                                                     │  │
│   │    Boost factors:                                                   │  │
│   │    • Same project: +0.1                                             │  │
│   │    • Recent (24h): +0.15                                            │  │
│   │    • High importance: +0.1                                          │  │
│   │    • Task relevance: +0.2                                           │  │
│   │                                                                     │  │
│   │    Final Ranking:                                                   │  │
│   │    ┌─────────────────────────────────────────────────────────────┐  │  │
│   │    │ 1. Error handling pattern (current project)   Score: 1.15  │  │  │
│   │    │ 2. Previous project setup (same user)         Score: 1.02  │  │  │
│   │    │ 3. FastAPI exception docs (general)           Score: 0.99  │  │  │
│   │    └─────────────────────────────────────────────────────────────┘  │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                        │
│                                    ▼                                        │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │ 5. RESPONSE GENERATION                                              │  │
│   │                                                                     │  │
│   │    • Retrieve full content of top 5 results                         │  │
│   │    • Format as structured context                                   │  │
│   │    • Apply token budget constraints                                 │  │
│   │    • Return to agent with relevance scores                          │  │
│   │                                                                     │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Retrieval API

```bash
# Semantic memory search
ammma_retrieve() {
    local query="$1"
    shift
    
    local limit=10
    local min_score=0.5
    local memory_types="all"  # episodic|procedural|declarative|all
    local time_range="all"    # 1h|24h|7d|30d|all
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --limit) limit="$2"; shift 2 ;;
            --min-score) min_score="$2"; shift 2 ;;
            --type) memory_types="$2"; shift 2 ;;
            --time-range) time_range="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    # Generate query embedding
    local query_embedding
    query_embedding=$(embed_text "$query")
    
    # Search all tiers in parallel
    local results
    results=$(_ammma_search_tiers "$query" "$query_embedding" "$memory_types")
    
    # Fuse and rerank
    results=$(_ammma_fuse_results "$results" "$limit" "$min_score")
    
    # Format output
    echo "$results"
}

# Associative retrieval (follow memory chains)
ammma_associate() {
    local memory_id="$1"
    local depth="${2:-2}"
    
    # Traverse causal links, temporal sequences, and semantic similarities
    # Return related memories forming a "memory chain"
}
```

---

## 6. Cross-Agent Memory Sharing

### 6.1 Memory Mesh Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     CROSS-AGENT MEMORY MESH                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│    ┌───────────────────────────────────────────────────────────────────┐   │
│    │                      SHARED MEMORY SPACE                         │   │
│    │                                                                   │   │
│    │   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │   │
│    │   │  Agent A     │  │  Agent B     │  │  Agent C     │          │   │
│    │   │  (Builder)   │  │  (Reviewer)  │  │  (Tester)    │          │   │
│    │   └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │   │
│    │          │                 │                 │                  │   │
│    │          │    ┌────────────┴────────────┐    │                  │   │
│    │          └───►│      Memory Broker      │◄───┘                  │   │
│    │               │    (Pub/Sub + Registry) │                       │   │
│    │               └────────────┬────────────┘                       │   │
│    │                            │                                    │   │
│    │          ┌─────────────────┼─────────────────┐                  │   │
│    │          ▼                 ▼                 ▼                  │   │
│    │   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │   │
│    │   │  Project     │  │  Pattern     │  │  Knowledge   │          │   │
│    │   │  Context     │  │  Library     │  │  Graph       │          │   │
│    │   └──────────────┘  └──────────────┘  └──────────────┘          │   │
│    │                                                                   │   │
│    └───────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│   Memory Sharing Protocols:                                                 │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │ 1. BROADCAST: Agent publishes discovery to all peers                │  │
│   │    Example: "Found that API X requires auth header Y"               │  │
│   │                                                                     │  │
│   │ 2. QUERY: Agent requests specific memory from mesh                  │  │
│   │    Example: "Has anyone worked with library Z before?"              │  │
│   │                                                                     │  │
│   │ 3. SUBSCRIBE: Agent registers interest in topic                     │  │
│   │    Example: Subscribe to "deployment" events                        │  │
│   │                                                                     │  │
│   │ 4. INHERIT: Child agent receives parent context                     │  │
│   │    Example: Sub-agent gets filtered summary of parent session       │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   Access Control:                                                           │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │ Level  │ Description                        │ Scope                  │  │
│   │────────┼────────────────────────────────────┼────────────────────────│  │
│   │ public │ Fully shared across all agents     │ Project-wide           │  │
│   │ team   │ Shared within team namespace       │ Namespace-scoped       │  │
│   │ private│ Agent-local only                   │ Session-only           │  │
│   │ inherit│ Shared parent→child only           │ Lineage-scoped         │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 6.2 Memory Broker Protocol

```bash
# Initialize connection to memory mesh
ammma_mesh_init() {
    local agent_id="$1"
    local namespace="${2:-default}"
    
    # Register agent with broker
    # Set up pub/sub channels
    # Sync shared memory state
}

# Publish memory to mesh
ammma_mesh_publish() {
    local memory_id="$1"
    local scope="${2:-team}"  # public|team|inherit
    
    # Serialize memory with metadata
    # Apply scope-based filtering
    # Broadcast to interested subscribers
}

# Query mesh for memories
ammma_mesh_query() {
    local query="$1"
    local target_agents="${2:-*}"  # * or comma-separated list
    
    # Send query to specified agents
    # Collect responses with timeout
    # Fuse and return results
}

# Subscribe to memory topics
ammma_mesh_subscribe() {
    local topic="$1"
    local callback="$2"
    
    # Register interest in topic
    # Set up async notification
}
```

---

## 7. Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)

**Goal**: Establish L1-L3 tier management and basic cognitive memory types

```bash
# New files to create:
lib/ammma.sh              # Main API
lib/ammma_tiers.sh        # Tier management
lib/ammma_cognitive.sh    # Episodic/procedural/declarative
lib/ammma_importance.sh   # Scoring algorithms
lib/ammma_consolidate.sh  # Memory consolidation
```

**Deliverables**:
- [ ] L1-L3 tier operations with automatic promotion/demotion
- [ ] Episodic memory logging with causal links
- [ ] Basic importance scoring
- [ ] Integration with existing AWM v2 API

### Phase 2: Semantic Layer (Weeks 3-4)

**Goal**: Implement semantic retrieval and L4 long-term memory

**Deliverables**:
- [ ] Vector embedding integration for all memory types
- [ ] L4 persistent storage with semantic indexing
- [ ] Multi-modal retrieval pipeline
- [ ] Memory fusion and reranking algorithms

### Phase 3: Intelligence (Weeks 5-6)

**Goal**: Add intelligent features - consolidation, prediction, attention

**Deliverables**:
- [ ] Memory consolidation algorithms
- [ ] Attention mechanism with dynamic window
- [ ] Predictive preloading (anticipatory retrieval)
- [ ] Pattern extraction from episodic memories

### Phase 4: Distribution (Weeks 7-8)

**Goal**: Cross-agent memory sharing and L5 external integration

**Deliverables**:
- [ ] Memory mesh protocol
- [ ] Redis/ChromaDB integration for shared memory
- [ ] Access control and privacy mechanisms
- [ ] Conflict resolution for concurrent updates

### Phase 5: Optimization (Weeks 9-10)

**Goal**: Performance tuning, testing, and documentation

**Deliverables**:
- [ ] Sub-100ms retrieval latency guarantee
- [ ] Compression algorithms for memory efficiency
- [ ] Comprehensive test suite
- [ ] Migration guide from AWM v2

---

## 8. Data Structures and Storage Formats

### 8.1 Memory Entry (Unified Format)

```json
{
  "_schema": "amma.v3.memory",
  "_version": "1.0.0",
  
  "id": "mem_abc123def456",
  "type": "episodic|procedural|declarative",
  "tier": "l1|l2|l3|l4|l5",
  
  "content": {
    // Type-specific content (see section 2.2)
  },
  
  "metadata": {
    "created_at": 1738754700.123456,
    "updated_at": 1738754700.123456,
    "access_count": 5,
    "last_accessed": 1738755000.000000,
    "importance_score": 0.85,
    "attention_score": 0.92,
    "session_id": "sess_xyz789",
    "agent_id": "agent_main",
    "namespace": "project_alpha"
  },
  
  "embedding": {
    "vector": [0.12, -0.34, 0.56, ...],
    "model": "nomic-embed-text",
    "dimensions": 768,
    "generated_at": 1738754700.123456
  },
  
  "relationships": {
    "causes": ["mem_prev123"],
    "caused_by": ["mem_next456"],
    "similar_to": ["mem_sim789"],
    "part_of": ["mem_parent000"],
    "contains": ["mem_child111"]
  },
  
  "sharing": {
    "scope": "public|team|private|inherit",
    "shared_with": ["agent_1", "agent_2"],
    "access_policy": "read|write|admin"
  }
}
```

### 8.2 Storage Layout

```
~/.mainframe/amma/
├── l1/                          # Immediate (not persisted, runtime only)
│   └── *.tmp                    # Temporary runtime files
├── l2/                          # Working memory
│   ├── sessions/
│   │   └── {session_id}/
│   │       ├── hot.json         # In-memory dump
│   │       ├── checkpoints/
│   │       └── discoveries.jsonl
│   └── current/                 # Current session symlink
├── l3/                          # Short-term memory
│   ├── compressed/
│   │   └── {date}/
│   │       └── sessions.tar.gz
│   └── summaries/
│       └── {session_id}.json
├── l4/                          # Long-term memory
│   ├── episodes/
│   │   └── {year}/{month}/
│   │       └── {id}.json
│   ├── patterns/
│   │   └── {category}/
│   │       └── {id}.json
│   ├── facts/
│   │   └── {domain}/
│   │       └── {id}.json
│   └── vectors/                 # Vector index
│       ├── chroma/              # ChromaDB files
│       └── faiss/               # FAISS index (if used)
└── l5/                          # External (references only)
    └── connections.json         # External DB connections
```

---

## 9. Code Examples

### 9.1 Basic Usage

```bash
#!/usr/bin/env bash
source ~/.mainframe/lib/ammma.sh

# Initialize AMMA for this session
amma_init --session "feature-x" --namespace "team-backend"

# Store an episodic memory (automatically captures context)
amma_episode_log \
    --type "decision" \
    --content "Chose PostgreSQL over MySQL for transaction support" \
    --importance "high" \
    --tags ["database","architecture"]

# Store a procedural memory (learned pattern)
amma_pattern_learn \
    --name "fastapi-error-handling" \
    --trigger "fastapi AND error" \
    --steps ["define_exceptions","add_handlers","test"] \
    --template '{"code": "..."}'

# Store a declarative fact
amma_fact_store \
    --subject "API rate limit" \
    --predicate "is" \
    --object "100 req/min" \
    --confidence 0.95 \
    --source "documentation"

# Retrieve memories semantically
results=$(amma_retrieve \
    "How should I handle errors in FastAPI?" \
    --limit 5 \
    --min-score 0.7)

echo "$results" | jq '.memories[] | {type, content, relevance}'

# Get associative memory chain
chain=$(amma_associate \
    --memory-id "mem_abc123" \
    --depth 2)

# Context-aware retrieval (automatically uses current context)
context=$(amma_context_build --max-tokens 4000)
echo "$context"
```

### 9.2 Advanced Patterns

```bash
# Automatic context offloading when approaching token limit
amma_config_set AUTO_OFFLOAD_THRESHOLD 0.8  # 80% of context

# Enable predictive preloading
amma_config_set PREDICTIVE_PRELOAD true

# Configure consolidation schedule
amma_config_set CONSOLIDATION_INTERVAL 21600  # 6 hours

# Custom importance scorer
_ammma_importance_custom() {
    local memory="$1"
    local base_score=$(echo "$memory" | jq '.metadata.base_score')
    
    # Custom business logic
    if echo "$memory" | jq -e '.content.tags | contains(["critical"])' >/dev/null; then
        base_score=$(echo "$base_score + 50" | bc)
    fi
    
    echo "$base_score"
}

amma_register_importance_scorer "custom" _ammma_importance_custom
```

### 9.3 Cross-Agent Example

```bash
# Agent A: Initialize and share
amma_init --agent-id "builder-agent"
amma_mesh_init --namespace "project-x"

# Make a discovery and share
discovery_id=$(amma_episode_log --type "discovery" \
    --content "Found optimal chunk size is 512 tokens")

amma_mesh_publish "$discovery_id" --scope team

# Agent B: Query the mesh
amma_init --agent-id "reviewer-agent"
amma_mesh_init --namespace "project-x"

# Search team memories
results=$(amma_mesh_query "chunk size recommendations" --scope team)

# Subscribe to discoveries
ammma_mesh_subscribe "discovery" _handle_discovery

_handle_discovery() {
    local memory="$1"
    echo "New discovery: $(echo "$memory" | jq -r '.content')"
}
```

---

## 10. Performance and Scalability

### 10.1 Performance Targets

| Operation | Target Latency | Max Throughput |
|-----------|---------------|----------------|
| L1 Read | <0.1ms | 100K ops/sec |
| L2 Read | <1ms | 10K ops/sec |
| L3 Read | <10ms | 1K ops/sec |
| L4 Semantic Search | <100ms | 100 queries/sec |
| L5 Remote Query | <500ms | 10 queries/sec |
| Memory Write (all tiers) | <5ms | 1K ops/sec |
| Consolidation | <1s per 1000 memories | Nightly batch |

### 10.2 Scalability Limits

| Resource | Soft Limit | Hard Limit |
|----------|-----------|------------|
| L1 (RAM per session) | 1MB | 10MB |
| L2 (per session) | 10MB | 100MB |
| L3 (total) | 100MB | 1GB |
| L4 (total) | 1GB | 10GB |
| L5 | Unlimited | Cloud limits |
| Memories per session | 10,000 | 100,000 |
| Concurrent agents | 100 | 1,000 |

### 10.3 Optimization Strategies

```bash
# 1. Batched writes
ammma_batch_start
ammma_episode_log ...
ammma_episode_log ...
ammma_episode_log ...
ammma_batch_commit  # Single disk sync

# 2. Compressed embeddings (product quantization)
ammma_config_set EMBEDDING_COMPRESSION "pq"  # 4x smaller

# 3. Tiered caching for L4
ammma_config_set L4_CACHE_SIZE "100MB"
ammma_config_set L4_CACHE_POLICY "lru"  # or "attention-based"

# 4. Async consolidation
ammma_consolidate --async --priority low

# 5. Selective embedding (don't embed low-importance memories)
ammma_config_set AUTO_EMBED_THRESHOLD 0.3
```

---

## 11. Integration with Existing Systems

### 11.1 AWM v2 Compatibility Layer

```bash
# Existing AWM v2 calls continue to work
awm_init "my-session"                    # Maps to amma_init
awm_checkpoint "key" "value"             # Maps to amma_declare_store
awm_discovery "insight"                  # Maps to amma_episode_log --type discovery
awm_summary                              # Maps to amma_context_build

# Gradual migration path
# Step 1: Use compatibility layer (no changes)
# Step 2: Start using AMMA APIs for new features
# Step 3: Migrate critical code to AMMA APIs
# Step 4: Deprecate AWM v2 (after 2 releases)
```

### 11.2 Integration Points

| System | Integration | Data Flow |
|--------|-------------|-----------|
| AWM v2 | Compatibility layer | Bidirectional sync |
| vectordb.sh | L4-L5 backend | Embeddings → Vector DB |
| embeddings.sh | Embedding generation | Text → Vectors |
| rag.sh | Knowledge source | Declarative memories |
| cache.sh | L2 optimization | Hot tier caching |
| checkpoint.sh | Session persistence | L2 → L3 migration |

---

## 12. Security and Privacy

### 12.1 Memory Classification

```bash
# Classification levels
AMMA_CLASSIFICATION_PUBLIC="public"       # Safe to share
AMMA_CLASSIFICATION_INTERNAL="internal"   # Team only
AMMA_CLASSIFICATION_CONFIDENTIAL="conf"   # Project only
AMMA_CLASSIFICATION_SECRET="secret"       # Agent only

# Store with classification
ammma_episode_log \
    --content "Password is hunter2" \
    --classification "secret" \
    --auto-redact true
```

### 12.2 Data Sanitization

```bash
# Automatic PII detection and redaction
ammma_config_set PII_DETECTION "enabled"
ammma_config_set PII_ACTION "redact"  # or "flag", "block"

# Pattern-based sanitization
ammma_sanitizer_add "api_key" 'sk-[a-zA-Z0-9]{48}' '[REDACTED_API_KEY]'
ammma_sanitizer_add "password" '(?i)password["\']?\s*[:=]\s*["\']?[^"\'\s]+' '[REDACTED_PASSWORD]'
```

---

## Appendix A: Configuration Reference

```bash
# ~/.mainframe/amma/config.env

# Tier Configuration
AMMA_L1_MAX_SIZE=4096           # bytes
AMMA_L2_MAX_SIZE=10485760       # 10MB
AMMA_L3_MAX_SIZE=104857600      # 100MB
AMMA_L4_MAX_SIZE=1073741824     # 1GB

# Timeouts (seconds)
AMMA_L2_TTL=86400               # 24 hours
AMMA_L3_TTL=604800              # 7 days
AMMA_L4_TTL=0                   # Indefinite

# Performance
AMMA_CONSOLIDATION_INTERVAL=21600
AMMA_ATTENTION_WINDOW=20
AMMA_EMBEDDING_BATCH_SIZE=32

# External Services
AMMA_CHROMADB_URL="http://localhost:8000"
AMMA_REDIS_URL="redis://localhost:6379"

# Features
AMMA_PREDICTIVE_PRELOAD=true
AMMA_AUTO_CONSOLIDATE=true
AMMA_SEMANTIC_SEARCH=true
```

---

## Appendix B: API Quick Reference

| Function | Purpose | Tier |
|----------|---------|------|
| `amma_init` | Initialize session | All |
| `amma_episode_log` | Record event | L1-L4 |
| `amma_pattern_learn` | Store procedure | L3-L5 |
| `amma_fact_store` | Store fact | L3-L5 |
| `amma_retrieve` | Semantic search | All |
| `amma_associate` | Memory chains | L3-L5 |
| `amma_context_build` | Get context for LLM | L1-L3 |
| `amma_consolidate` | Run consolidation | L3-L4 |
| `amma_mesh_publish` | Share memory | L5 |
| `amma_mesh_query` | Query mesh | L5 |

---

*Document Version: 1.0.0*
*Last Updated: 2026-02-05*
*Status: Design Phase*

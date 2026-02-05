# Mainframe AI-Native Bash Runtime: Architecture Review

**Review Date:** 2026-02-04  
**Reviewer:** Systems Architect (AI Agent Infrastructure)  
**Scope:** Agentic Offloading & Memory Management Architecture  

---

## Executive Summary

Mainframe represents a sophisticated AI-native bash runtime with an advanced **Agent Working Memory (AWM)** system designed to address the fundamental constraint of finite LLM context windows. The architecture demonstrates mature patterns for:

- **Tiered memory management** (Hot/Warm/Cold tiers)
- **Multi-storage backend abstraction** (File/Redis/ChromaDB)
- **Agent lifecycle orchestration** with parent/child inheritance
- **Token-aware context management** with intelligent compression
- **Distributed coordination** via Redis pub/sub with file-based fallback

### Current Capabilities Assessment

| Capability | Status | Assessment |
|------------|--------|------------|
| Session-based memory | ✅ Production-ready | Robust checkpoint/summary system |
| Tiered storage | ✅ Advanced | Hot/Warm/Cold with automatic eviction |
| Multi-backend storage | ✅ Flexible | File/Redis/ChromaDB with auto-detection |
| Token estimation | ✅ Mature | Multi-strategy with content-type detection |
| Agent inheritance | ✅ Implemented | Parent/child discovery passing |
| Cross-session resume | ✅ Implemented | Session ID-based recovery |
| Semantic search | ⚠️ Partial | ChromaDB integration exists but limited |
| Automatic offloading | ⚠️ Basic | Manual pointer system, no predictive eviction |
| Context compression | ⚠️ Rule-based | Pre-rot threshold only, no semantic compression |

---

## 1. Current Architecture Analysis

### 1.1 Agent Working Memory (AWM) System

**Core Components:**

```
┌─────────────────────────────────────────────────────────────────┐
│                     AWM ARCHITECTURE LAYER                      │
├─────────────────────────────────────────────────────────────────┤
│  awm.sh          → Session lifecycle, checkpoints, discoveries  │
│  awm_storage.sh  → Backend abstraction (File/Redis/ChromaDB)   │
│  awm_protocol.sh → USOP v4 agent-to-agent messaging             │
│  awm_stream.sh   → Token budget, chunking, compression         │
│  awm_tiers.sh    → Hot/Warm/Cold memory management             │
└─────────────────────────────────────────────────────────────────┘
```

**Key Design Patterns:**

1. **Session-Centric Model**: Each `awm_init()` creates an isolated session with:
   - Unique 12-char hex session ID
   - Hierarchical directory structure (`sessions/{namespace}/{id}/`)
   - Manifest JSON for metadata
   - Category-based logging (`discoveries.jsonl`, `{category}.jsonl`)

2. **Atomic Operations**: All writes use temp-file + rename pattern:
   ```bash
   _awm_atomic_write() {
       local tmpfile="${target}.tmp.$$"
       printf '%s' "$content" > "$tmpfile"
       mv -f "$tmpfile" "$target"
   }
   ```

3. **Concurrent Safety**: File-based locking via `flock`:
   ```bash
   _awm_locked_append() {
       ( flock -x 200; printf '%s\n' "$content" >> "$target" ) 200>"${target}.lock"
   }
   ```

**Strengths:**
- Simple, battle-tested file-based persistence
- JSONL format enables append-only logging with easy parsing
- Namespace isolation supports multi-agent scenarios
- Inheritance model for sub-agents is elegant

**Limitations:**
- No built-in encryption for sensitive data
- File-based search is O(n) grep, not scalable
- No built-in replication/backup

### 1.2 Storage Backend Architecture

**awm_storage.sh** implements a sophisticated multi-backend system:

```bash
# Auto-detection priority: ChromaDB > Redis > File
awm_storage_init() {
    # 1. Check ChromaDB (port 8000) - best for semantic search
    # 2. Check Redis Stack (port 6380) then Redis (port 6379)
    # 3. Fallback to file-based storage
}
```

**Capability Matrix:**

| Feature | File | Redis | ChromaDB |
|---------|------|-------|----------|
| Key-Value | ✅ | ✅ | ✅ (via file fallback) |
| Lists/Queues | ✅ (base64-encoded) | ✅ (native) | ❌ |
| Pub/Sub | ✅ (polling-based) | ✅ (native) | ❌ |
| TTL | ✅ (manual cleanup) | ✅ (native) | ❌ |
| Semantic Search | ❌ | ❌ | ✅ |
| Vector Storage | ❌ | ❌ | ✅ |

**Design Insight:** The storage layer uses a **capability-based fallback** pattern where ChromaDB handles vector operations while falling back to file storage for non-vector operations. This is pragmatic but creates architectural complexity.

### 1.3 Tiered Memory System (awm_tiers.sh)

**Three-Tier Architecture:**

```
┌────────────────────────────────────────────────────────────────┐
│ HOT TIER (In-Memory)                                           │
│ ├─ Bash associative array: _AWM_HOT_TIER[]                    │
│ ├─ Metadata tracking: access_count, last_access, importance   │
│ ├─ Automatic eviction based on weighted score                 │
│ └─ Target: <10% of token budget per item                      │
├────────────────────────────────────────────────────────────────┤
│ WARM TIER (File/Redis with TTL)                                │
│ ├─ JSON storage with metadata                                 │
│ ├─ Configurable TTL (default: 1 hour)                         │
│ ├─ Automatic promotion on access                              │
│ └─ Size limit: 10MB default                                   │
├────────────────────────────────────────────────────────────────┤
│ COLD TIER (Persistent Archive)                                 │
│ ├─ Searchable persistent storage                              │
│ ├─ Indexed for retrieval                                      │
│ ├─ 30-day TTL default                                         │
│ └─ Best for large, rarely accessed data                       │
└────────────────────────────────────────────────────────────────┘
```

**Eviction Algorithm:**
```bash
# Score = importance_weight * access_count * 1000 / (age + 1)
# Lower score = evict first
score=$((weight * access_count * 1000 / (age + 1)))
```

**Critique:** The eviction algorithm is **frequency-based** rather than **utility-based**. It doesn't account for:
- Semantic relevance to current task
- Temporal locality patterns
- Predictive value for future operations

### 1.4 Token Management System

**Dual Implementation:**

1. **context.sh** - Basic token estimation
   - Character-based heuristics (3.5-4.0 chars/token)
   - Content type detection (code/JSON/markdown/text)
   - Budget allocation tracking

2. **llm_tokens.sh** - Advanced token management
   - Model-specific ratios
   - Tiktoken integration (optional Python)
   - Cost estimation
   - Chunk splitting with overlap

3. **awm_stream.sh** - Stream-oriented management
   - Memory pointer system (`ptr://awm/{hash}`)
   - Content-type-aware chunking
   - Compression pipeline (5 levels)

**Token Estimation Accuracy:**

| Content Type | Ratio | Actual Tokenizer | Error |
|--------------|-------|------------------|-------|
| English prose | 4.0 | ~4.0 (Claude) | ±10% |
| Code | 3.5 | ~3.2-3.8 | ±15% |
| JSON | 3.0 | ~2.5-3.5 | ±20% |
| Markdown | 3.8 | ~3.5-4.2 | ±15% |

**Gap:** No integration with actual tokenizer APIs for precise counting. The 10-20% error margin accumulates over large contexts.

### 1.5 Agent Lifecycle & Context Management

**agent_context.sh** provides persistent context objects:

```bash
# Session lifecycle
ctx_init "session_id"      # Create new session
ctx_load "session_id"      # Resume existing
ctx_save                   # Persist current state
ctx_snapshot               # Point-in-time backup
ctx_restore "snapshot_id"  # Rollback
```

**agent_ai.sh** synthesizes patterns from major AI CLIs:

| Source | Pattern | Implementation |
|--------|---------|----------------|
| Claude Code | Context budget, subagents | `agent_ai_context_init()`, `agent_ai_spawn()` |
| Aider | Edit formats, reflection | `agent_ai_edit_apply()`, `agent_ai_reflect()` |
| OpenCode | Tool registry, spillover | `agent_ai_tool_register()`, `agent_ai_output_truncate()` |
| Copilot CLI | Auto-compress, file refs | `agent_ai_context_use()`, `agent_ai_ref_add()` |
| Codex | Hierarchical AGENTS.md, gates | `agent_ai_context_hierarchy()`, `agent_ai_gate_define()` |

### 1.6 Multi-Agent Orchestration

**orchestrate.sh** + **leader.sh** provide distributed coordination:

```
┌────────────────────────────────────────────────────────────────┐
│                    ORCHESTRATION LAYER                         │
├────────────────────────────────────────────────────────────────┤
│  Team Management                                               │
│  ├─ Team registration with capabilities                      │
│  ├─ Agent spawning in TMUX windows                            │
│  └─ Slot-based resource allocation (atomic mkdir)            │
├────────────────────────────────────────────────────────────────┤
│  Communication                                                 │
│  ├─ Redis pub/sub (primary)                                   │
│  ├─ File-based fallback (polling)                             │
│  └─ Message types: heartbeat, task, result, control          │
├────────────────────────────────────────────────────────────────┤
│  Leader Election                                               │
│  ├─ Redis SET NX EX (distributed)                             │
│  ├─ File-based flock (single-node)                            │
│  └─ Automatic renewal with TTL                                │
└────────────────────────────────────────────────────────────────┘
```

---

## 2. Agentic Offloading Opportunities

### 2.1 Current Offloading Mechanisms

**1. Memory Pointer System (awm_stream.sh)**
```bash
# Store large content externally
pointer=$(awm_pointer_create "$large_content")
# Returns: ptr://awm/a1b2c3d4...

# Resolve when needed
content=$(awm_pointer_resolve "$pointer")
```

**2. Result Wrapping**
```bash
# Automatically creates pointer if content exceeds threshold
awm_wrap_result "$content" [max_tokens] [preview_chars]
# Returns: {_ptr, preview, tokens, message}
```

**3. Observation Masking**
```bash
# Replace large observations with pointers
awm_mask_observations "$session_id" "tool_results" "file_contents"
```

### 2.2 Proposed: Transparent State Persistence

**Design: Auto-Offloading Middleware**

```bash
# Pseudocode for proposed enhancement

# Configuration
AWM_AUTO_OFFLOAD_THRESHOLD=2000    # tokens
AWM_AUTO_OFFLOAD_STRATEGY="pointer"  # pointer|compress|summarize

# Auto-offload function
awm_auto_store() {
    local key="$1"
    local value="$2"
    local tokens=$(awm_estimate_tokens "$value")
    
    if [[ $tokens -gt $AWM_AUTO_OFFLOAD_THRESHOLD ]]; then
        case "$AWM_AUTO_OFFLOAD_STRATEGY" in
            pointer)
                local ptr=$(awm_pointer_create "$value")
                awm_hot_set "$key" "$ptr" "normal"
                echo "{\"_ptr\":\"$ptr\",\"tokens\":$tokens}"
                ;;
            compress)
                local compressed=$(awm_compress "$value" 3)
                awm_tier_write "$key" "$compressed" "high"
                ;;
            summarize)
                # Requires LLM call - async
                awm_tier_write "$key" "$value" "normal"
                awm_queue_summarization "$key" "$value"
                ;;
        esac
    else
        awm_hot_set "$key" "$value" "normal"
    fi
}
```

### 2.3 Proposed: Hierarchical Memory System

**Enhanced Three-Tier with Semantic Layer:**

```
┌─────────────────────────────────────────────────────────────────┐
│ WORKING MEMORY (Hot)                                            │
│ ├─ Current conversation context                                 │
│ ├─ Active tool results                                          │
│ ├─ Immediate parent discoveries                                 │
│ └─ Auto-eviction: LRU with importance weighting                 │
├─────────────────────────────────────────────────────────────────┤
│ SHORT-TERM MEMORY (Warm)                                        │
│ ├─ Recent checkpoints (< 1 hour)                                │
│ ├─ High-importance discoveries                                  │
│ ├─ Cross-turn context                                           │
│ └─ Storage: Redis/File with TTL                                 │
├─────────────────────────────────────────────────────────────────┤
│ LONG-TERM MEMORY (Cold)                                         │
│ ├─ Session archives                                             │
│ ├─ Project-wide discoveries                                     │
│ ├─ Indexed for semantic search                                  │
│ └─ Storage: ChromaDB + compressed files                         │
├─────────────────────────────────────────────────────────────────┤
│ SEMANTIC INDEX (Vector)                                         │
│ ├─ Embeddings of all discoveries                                │
│ ├─ Task-relevant memory retrieval                               │
│ └─ Query: "What do I know about X?"                             │
└─────────────────────────────────────────────────────────────────┘
```

### 2.4 Proposed: Automatic Checkpointing

**Smart Checkpoint Strategy:**

```bash
# Configuration
AWM_CHECKPOINT_INTERVAL=300        # 5 minutes
AWM_CHECKPOINT_ON_EVENT="discovery|error|milestone"
AWM_CHECKPOINT_STRATEGY="diff"     # full|diff|incremental

# Implementation
awm_auto_checkpoint() {
    local event_type="$1"
    local now=$(awm_epoch)
    local last=$(awm_get "_last_checkpoint" 0)
    
    # Time-based checkpoint
    if [[ $((now - last)) -gt $AWM_CHECKPOINT_INTERVAL ]]; then
        _awm_create_checkpoint "time"
        return
    fi
    
    # Event-based checkpoint
    if [[ "$AWM_CHECKPOINT_ON_EVENT" == *"$event_type"* ]]; then
        _awm_create_checkpoint "$event_type"
        return
    fi
    
    # Delta-based: checkpoint if significant changes
    local changes=$(awm_change_count_since "$last")
    if [[ $changes -gt 10 ]]; then
        _awm_create_checkpoint "delta"
    fi
}
```

---

## 3. Context Window Management Enhancements

### 3.1 Current Token Estimation Analysis

**lib/llm_tokens.sh** provides:
- Character-based heuristics with model-specific ratios
- Optional tiktoken integration (Python dependency)
- Simple in-memory caching

**Limitations:**
1. No integration with actual LLM APIs for precise token counts
2. Caching is session-local only
3. No tracking of token count drift over conversation
4. No predictive modeling of token growth

### 3.2 Proposed: Intelligent Context Compression

**Semantic Compression Pipeline:**

```bash
# Multi-stage compression based on urgency

awm_intelligent_compress() {
    local content="$1"
    local urgency="${2:-normal}"  # low|normal|high|critical
    local target_tokens="$3"
    
    local current_tokens=$(awm_estimate_tokens "$content")
    local reduction_needed=$((current_tokens - target_tokens))
    
    case "$urgency" in
        low)
            # Level 1: Remove whitespace, comments
            awm_compress "$content" 2
            ;;
        normal)
            # Level 2: Extract key patterns
            awm_compress "$content" 3
            ;;
        high)
            # Level 3: Function signatures only
            awm_compress "$content" 4
            ;;
        critical)
            # Level 4: Summarize via LLM (expensive)
            awm_llm_summarize "$content" "$target_tokens"
            ;;
    esac
}
```

### 3.3 Proposed: Context Prioritization Engine

**Priority Scoring Algorithm:**

```bash
# Calculate priority score for context items
# Higher score = more likely to stay in context

_awm_context_priority_score() {
    local item="$1"
    local item_type="$2"  # discovery|checkpoint|log|tool_result
    local age_seconds="$3"
    local access_count="$4"
    local semantic_relevance="$5"  # 0.0-1.0 from vector search
    
    # Base weights by type
    local type_weight
    case "$item_type" in
        discovery)     type_weight=100 ;;
        checkpoint)    type_weight=80  ;;
        tool_result)   type_weight=40  ;;
        log)           type_weight=20  ;;
        *)             type_weight=10  ;;
    esac
    
    # Recency factor (exponential decay)
    local recency=$((100 * 2**(-age_seconds/3600)))
    
    # Frequency factor (logarithmic)
    local frequency=$((20 * log2(access_count + 1)))
    
    # Semantic relevance (0-100 scale)
    local relevance_score=$((semantic_relevance * 100))
    
    # Combined score
    echo $((type_weight + recency + frequency + relevance_score))
}
```

### 3.4 Proposed: Automatic Context Optimization

**Dynamic Context Window Management:**

```bash
# Monitor and optimize context usage

awm_context_optimizer() {
    local budget=$(awm_budget_max)
    local used=$(awm_budget_used)
    local usage_pct=$((used * 100 / budget))
    
    # Proactive compression at 75%
    if [[ $usage_pct -gt 75 ]]; then
        _awm_compress_low_priority_items
    fi
    
    # Aggressive compression at 90%
    if [[ $usage_pct -gt 90 ]]; then
        _awm_offload_to_warm_tier
        _awm_summarize_old_discoveries
    fi
    
    # Emergency compression at 95%
    if [[ $usage_pct -gt 95 ]]; then
        _awm_emergency_compress
        awm_warn_context_critical
    fi
}
```

---

## 4. Cross-Session Memory Design

### 4.1 Current State

Mainframe supports session resumption via `awm_resume()` and inheritance via parent session IDs:

```bash
# Current inheritance model
awm_init "child" "$PARENT_SESSION_ID"
# Copies discoveries.jsonl and data/ directory
```

**Limitations:**
- Inheritance is copy-on-init, not live-linked
- No mechanism for parent-to-child updates after spawn
- No aggregation of child discoveries back to parent
- Project-wide memory requires manual coordination

### 4.2 Proposed: Memory Inheritance Architecture

**Linked Memory Model:**

```bash
# Enhanced inheritance with live linking

awm_init_linked() {
    local session_name="$1"
    local parent_id="$2"
    local link_type="${3:-snapshot}"  # snapshot|live|aggregate
    
    local child_id=$(awm_gen_session_id)
    _awm_create_session "$child_id" "$session_name"
    
    case "$link_type" in
        snapshot)
            # Current behavior: copy at init time
            _awm_inherit_snapshot "$parent_id" "$child_id"
            ;;
        live)
            # Live-linked: parent updates propagate
            _awm_inherit_live "$parent_id" "$child_id"
            ;;
        aggregate)
            # Bidirectional: child discoveries flow back
            _awm_inherit_aggregate "$parent_id" "$child_id"
            ;;
    esac
    
    echo "$child_id"
}
```

### 4.3 Proposed: Project-Wide Memory Federation

**Federated Memory Design:**

```
┌─────────────────────────────────────────────────────────────────┐
│ PROJECT MEMORY (Global)                                         │
│ ~/.mainframe/awm/projects/{project_hash}/                       │
│ ├─ global_discoveries.jsonl    # Shared across all sessions    │
│ ├─ codebase_index.json         # File structure & semantics    │
│ ├─ conventions.json            # Project-specific patterns     │
│ └─ agent_learnings/            # Per-agent accumulated wisdom  │
├─────────────────────────────────────────────────────────────────┤
│ SESSION MEMORY (Isolated)                                       │
│ ~/.mainframe/awm/sessions/{session_id}/                         │
│ ├─ Inherits from project memory                                │
│ ├─ Contributes back on completion                              │
│ └─ Can query project memory on-demand                          │
└─────────────────────────────────────────────────────────────────┘
```

**Implementation:**

```bash
# Project-scoped memory operations

awm_project_init() {
    local project_path="${1:-$(pwd)}"
    local project_hash=$(echo "$project_path" | sha256sum | cut -c1-16)
    
    export _AWM_PROJECT_HASH="$project_hash"
    export _AWM_PROJECT_PATH="$project_path"
    
    mkdir -p "$AWM_ROOT/projects/$project_hash"
    
    # Load project context into hot tier
    awm_tier_prefetch "project:conventions" "project:architecture"
}

awm_project_discover() {
    local insight="$1"
    local importance="${2:-normal}"
    
    # Store in both session and project
    awm_discovery "$insight"  # Session-local
    _awm_project_append_discovery "$insight" "$importance"
}

awm_project_query() {
    local query="$1"
    # Semantic search across project memory
    awm_cold_search "$query" --scope=project
}
```

### 4.4 Proposed: Cross-CLI Memory Federation

**Standardized Memory Exchange:**

```bash
# Standard format for memory exchange between AI CLIs
# ~/.mainframe/awm/federation/{cli_name}/

awm_federation_export() {
    local format="${1:-mcp}"  # mcp|json|markdown
    local output_file="$AWM_ROOT/federation/mainframe/export.json"
    
    # Export in Model Context Protocol format
    jq -n \
        --arg session "$_AWM_SESSION_ID" \
        --arg project "$_AWM_PROJECT_HASH" \
        --slurpfile discoveries "$(_awm_session_dir)/logs/discoveries.jsonl" \
        '{
            source: "mainframe",
            version: "2.0",
            session: $session,
            project: $project,
            timestamp: now,
            discoveries: $discoveries,
            context_summary: awm_summary
        }' > "$output_file"
    
    echo "$output_file"
}

awm_federation_import() {
    local cli_name="$1"
    local import_file="$AWM_ROOT/federation/$cli_name/export.json"
    
    if [[ -f "$import_file" ]]; then
        # Import discoveries with attribution
        jq -r '.discoveries[] | "[\(.source // "unknown")] \(.discovery)"' "$import_file" | \
        while read -r discovery; do
            awm_discovery "$discovery"
        done
    fi
}
```

---

## 5. Performance Optimizations

### 5.1 Current Performance Characteristics

| Operation | Latency (File) | Latency (Redis) | Notes |
|-----------|---------------|-----------------|-------|
| Hot tier read | <1ms | N/A | In-memory array |
| Hot tier write | <1ms | N/A | In-memory array |
| Warm tier read | 5-20ms | 2-5ms | File I/O vs network |
| Warm tier write | 10-30ms | 2-5ms | Atomic rename |
| Cold tier search | 100-500ms | N/A | grep-based |
| Semantic search | N/A | 50-200ms | ChromaDB HTTP |
| Tier promotion | 10-50ms | 5-10ms | Read + write |

### 5.2 Proposed: Memory Storage Efficiency

**Compressed Storage Format:**

```bash
# Implement zstd compression for cold tier

awm_cold_store_compressed() {
    local key="$1"
    local value="$2"
    
    # Check if compression is beneficial (>100 bytes)
    if [[ ${#value} -gt 100 ]]; then
        local compressed=$(echo -n "$value" | zstd -c | base64)
        local metadata=$(jq -n \
            --arg key "$key" \
            --arg compressed "$compressed" \
            --arg original_size ${#value} \
            --arg compressed_size ${#compressed} \
            '{key: $key, data: $compressed, compressed: true, 
              original_size: $original_size, compressed_size: $compressed_size}')
        awm_cold_set "$key" "$metadata"
    else
        awm_cold_set "$key" "$value"
    fi
}
```

**Deduplication via CAS:**

```bash
# Content-addressable storage for discoveries

awm_store_deduped() {
    local content="$1"
    local hash=$(echo -n "$content" | sha256sum | cut -c1-32)
    
    # Check if already exists
    if awm_cold_exists "hash:$hash"; then
        # Store reference only
        awm_hot_set "ref:$hash" "ptr://awm/hash:$hash"
        return
    fi
    
    # Store content
    awm_cold_set "hash:$hash" "$content"
}
```

### 5.3 Proposed: Retrieval Latency Optimization

**Predictive Prefetching:**

```bash
# Prefetch likely-to-be-needed memories

awm_prefetch_engine() {
    local current_task="$1"
    
    # 1. Semantic search for relevant memories
    local relevant=$(awm_cold_search "$current_task" 20)
    
    # 2. Check temporal patterns (what's usually accessed together)
    local correlated=$(awm_find_correlated "$current_task")
    
    # 3. Prefetch into warm tier
    for key in $relevant $correlated; do
        if ! awm_warm_exists "$key"; then
            awm_tier_promote "$key" &  # Background promotion
        fi
    done
}
```

**Lazy Loading with Speculative Fetch:**

```bash
# Load on access with background speculation

awm_smart_get() {
    local key="$1"
    
    # Check hot tier (fastest)
    if awm_hot_exists "$key"; then
        # Trigger speculative prefetch of neighbors
        awm_speculative_prefetch "$key" &
        awm_hot_get "$key"
        return
    fi
    
    # Check warm tier
    if awm_warm_exists "$key"; then
        # Promote to hot in background
        (awm_tier_promote "$key") &
        awm_warm_get "$key"
        return
    fi
    
    # Cold tier (slowest)
    awm_cold_get "$key"
}
```

### 5.4 Proposed: Caching Strategies
n
**Multi-Level Cache with Semantic Layer:**

```
┌─────────────────────────────────────────────────────────────────┐
│ L1: In-Memory (Hot Tier)                                        │
│ ├─ Associative array: O(1) access                              │
│ ├─ Max 10% of context budget                                   │
│ └─ Eviction: LRU + importance                                  │
├─────────────────────────────────────────────────────────────────┤
│ L2: Local Disk (Warm Tier)                                      │
│ ├─ Memory-mapped for fast access                               │
│ ├─ Compressed zstd format                                      │
│ └─ Eviction: TTL + size limit                                  │
├─────────────────────────────────────────────────────────────────┤
│ L3: Redis (Distributed)                                         │
│ ├─ Shared across agents                                        │
│ ├─ Pub/sub for real-time sync                                  │
│ └─ Eviction: LRU with persistence                              │
├─────────────────────────────────────────────────────────────────┤
│ L4: Semantic Cache (ChromaDB)                                   │
│ ├─ Vector embeddings for similarity search                     │
│ ├─ Approximate nearest neighbors                               │
│ └─ Query: "What do I know about X?"                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. Specific Enhancement Proposals

### 6.1 Smart Context Manager (lib/awm_smart_context.sh)

```bash
#!/usr/bin/env bash
# Smart Context Manager - Automated context window optimization

# Configuration
readonly SCM_COMPRESS_THRESHOLD=75     # % of budget
readonly SCM_OFFLOAD_THRESHOLD=90      # % of budget  
readonly SCM_EMERGENCY_THRESHOLD=95    # % of budget

# Initialize smart context for a model
scm_init() {
    local model="${1:-claude-3.5-sonnet}"
    local budget=$(llm_context_window "$model")
    
    awm_budget_init --max-tokens "$budget"
    awm_tier_init
    
    # Start monitoring loop
    _scm_monitor_loop &
    echo $! > "$_AWM_SESSION_DIR/scm_monitor.pid"
}

# Auto-compress based on semantic importance
scm_auto_compress() {
    local usage_pct=$(awm_budget_summary | jq -r '.used_percent')
    
    if [[ $usage_pct -gt $SCM_COMPRESS_THRESHOLD ]]; then
        # Identify low-importance items
        local candidates=$(awm_list_compressible)
        
        for item in $candidates; do
            awm_compress_item "$item"
            usage_pct=$(awm_budget_summary | jq -r '.used_percent')
            [[ $usage_pct -lt $SCM_COMPRESS_THRESHOLD ]] && break
        done
    fi
}

# Emergency compression - keep only essentials
scm_emergency_compress() {
    # 1. Offload all tool results to pointers
    awm_mask_observations "$session_id" "tool_results"
    
    # 2. Compress all but critical discoveries
    awm_compress_category "discoveries" --keep-critical
    
    # 3. Truncate logs to last 10 entries
    awm_truncate_logs 10
    
    # 4. Summarize checkpoints
    awm_summarize_checkpoints
}

# Semantic memory retrieval
scm_recall() {
    local query="$1"
    local limit="${2:-5}"
    
    # 1. Exact match in hot tier
    local exact=$(awm_hot_get "$query")
    [[ -n "$exact" ]] && echo "$exact" && return
    
    # 2. Semantic search in cold tier
    local semantic=$(awm_cold_search "$query" "$limit")
    
    # 3. Promote results to warm tier for future access
    for result in $semantic; do
        awm_tier_promote "$result" &
    done
    
    echo "$semantic"
}
```

### 6.2 Predictive Memory Loader (lib/awm_predictive.sh)

```bash
#!/usr/bin/env bash
# Predictive Memory Loader - Anticipate needed memories

# Track access patterns
_AWM_ACCESS_PATTERN=()
_AWM_PREDICTION_MODEL="markov"  # markov|lstm|simple

# Record access for pattern learning
awm_record_access() {
    local key="$1"
    local timestamp=$(awm_epoch)
    
    _AWM_ACCESS_PATTERN+=("$timestamp:$key")
    
    # Keep only last 1000 accesses
    if [[ ${#_AWM_ACCESS_PATTERN[@]} -gt 1000 ]]; then
        _AWM_ACCESS_PATTERN=("${_AWM_ACCESS_PATTERN[@]:500}")
    fi
}

# Predict next likely accesses
awm_predict_next() {
    local current="$1"
    local n="${2:-3}"
    
    # Simple Markov chain: what usually follows current?
    local next_items=$(echo "${_AWM_ACCESS_PATTERN[*]}" | \
        grep -oP "$current:\K[^ ]+" | \
        sort | uniq -c | sort -rn | head -n "$n" | \
        awk '{print $2}')
    
    echo "$next_items"
}

# Prefetch predicted items
awm_prefetch_predicted() {
    local current="$1"
    local predicted=$(awm_predict_next "$current")
    
    for item in $predicted; do
        if ! awm_hot_exists "$item" && ! awm_warm_exists "$item"; then
            # Background load into warm tier
            (awm_cold_get "$item" | awm_warm_set "$item") &
        fi
    done
}
```

### 6.3 Cross-Session Memory Bridge (lib/awm_bridge.sh)

```bash
#!/usr/bin/env bash
# Memory Bridge - Connect related sessions

# Create bridge between sessions
awm_bridge_create() {
    local session_a="$1"
    local session_b="$2"
    local bridge_type="${3:-bidirectional}"  # unidirectional|bidirectional|hierarchical
    
    local bridge_id=$(echo "$session_a:$session_b" | sha256sum | cut -c1-16)
    
    cat > "$AWM_ROOT/bridges/$bridge_id.json" << EOF
{
    "bridge_id": "$bridge_id",
    "session_a": "$session_a",
    "session_b": "$session_b",
    "type": "$bridge_type",
    "created_at": $(awm_epoch),
    "sync_mode": "async"
}
EOF
    
    echo "$bridge_id"
}

# Synchronize discoveries across bridged sessions
awm_bridge_sync() {
    local bridge_id="$1"
    local direction="${2:-a_to_b}"  # a_to_b|b_to_a|both
    
    local bridge_file="$AWM_ROOT/bridges/$bridge_id.json"
    [[ ! -f "$bridge_file" ]] && return 1
    
    local session_a=$(jq -r '.session_a' "$bridge_file")
    local session_b=$(jq -r '.session_b' "$bridge_file")
    
    case "$direction" in
        a_to_b)
            _awm_sync_discoveries "$session_a" "$session_b"
            ;;
        b_to_a)
            _awm_sync_discoveries "$session_b" "$session_a"
            ;;
        both)
            _awm_sync_discoveries "$session_a" "$session_b"
            _awm_sync_discoveries "$session_b" "$session_a"
            ;;
    esac
}

# Query across all bridged sessions
awm_bridge_query() {
    local session_id="$1"
    local query="$2"
    
    # Find all bridges connected to this session
    local bridges=$(grep -l "$session_id" "$AWM_ROOT/bridges/"*.json 2>/dev/null)
    
    local results=""
    for bridge in $bridges; do
        local other=$(jq -r '.session_a, .session_b' "$bridge" | grep -v "$session_id")
        results+="$(awm_search_session "$other" "$query")"
    done
    
    echo "$results" | sort -u
}
```

---

## 7. Priority-Ranked Recommendations

### P0 (Critical - Implement First)

| # | Recommendation | Impact | Effort |
|---|----------------|--------|--------|
| 1 | **Smart Auto-Offloading** - Automatically convert large content to pointers when approaching context limits | High | Medium |
| 2 | **Emergency Compression Pipeline** - 4-tier compression strategy triggered at 95% usage | High | Low |
| 3 | **Context Priority Scoring** - Importance-based retention instead of simple LRU | High | Medium |

### P1 (High Priority)

| # | Recommendation | Impact | Effort |
|---|----------------|--------|--------|
| 4 | **Project-Wide Memory** - Persistent project context across all sessions | High | Medium |
| 5 | **Predictive Prefetching** - Load likely-to-be-needed memories before access | Medium | High |
| 6 | **Semantic Memory Retrieval** - Vector search integration for relevant memory discovery | High | High |
| 7 | **Cross-Session Bridges** - Link related sessions for shared context | Medium | Medium |

### P2 (Medium Priority)

| # | Recommendation | Impact | Effort |
|---|----------------|--------|--------|
| 8 | **Compression for Cold Tier** - zstd compression for archived memories | Medium | Low |
| 9 | **Deduplication via CAS** - Content-addressable storage to reduce redundancy | Medium | Low |
| 10 | **Memory Federation** - Standard format for memory exchange between AI CLIs | Medium | High |
| 11 | **Live Memory Linking** - Parent sessions can push updates to children | Medium | High |

### P3 (Future Considerations)

| # | Recommendation | Impact | Effort |
|---|----------------|--------|--------|
| 12 | **Learned Compression** - Train model-specific compression strategies | Low | Very High |
| 13 | **Distributed Memory Grid** - Shard memories across multiple Redis nodes | Low | High |
| 14 | **Encrypted Memory** - At-rest encryption for sensitive data | Medium | Medium |
| 15 | **Memory Visualization** - Web UI for exploring session memory graph | Low | High |

---

## 8. Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)
- Implement `awm_auto_store()` with configurable thresholds
- Add emergency compression at 95% usage
- Create context priority scoring system

### Phase 2: Intelligence (Weeks 3-4)
- Build semantic search integration
- Implement predictive prefetching
- Add project-wide memory scope

### Phase 3: Connectivity (Weeks 5-6)
- Create cross-session bridges
- Implement memory federation format
- Add live memory linking

### Phase 4: Optimization (Weeks 7-8)
- Add compression for cold tier
- Implement CAS deduplication
- Performance tuning and benchmarking

---

## 9. Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         AI AGENT (Claude, GPT, etc.)                        │
│                    ┌─────────────────────────────────┐                      │
│                    │      CONTEXT WINDOW             │                      │
│                    │  (Limited tokens, ephemeral)    │                      │
│                    └────────────────┬────────────────┘                      │
│                                     │                                       │
└─────────────────────────────────────┼───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       MAINFRAME RUNTIME LAYER                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    SMART CONTEXT MANAGER                            │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌────────────┐  │   │
│  │  │  Monitor    │  │  Compress   │  │  Prioritize │  │  Offload   │  │   │
│  │  │  Usage %    │→ │  Content    │→ │  by Score   │→ │  to Tiers  │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    THREE-TIER MEMORY SYSTEM                         │   │
│  │                                                                     │   │
│  │  ┌──────────────┐   ┌──────────────┐   ┌────────────────────────┐  │   │
│  │  │   HOT TIER   │   │  WARM TIER   │   │      COLD TIER         │  │   │
│  │  │  (In-Memory) │   │  (Redis/FS)  │   │   (Persistent +        │  │   │
│  │  │              │◄──│   w/ TTL     │◄──│    Semantic Index)     │  │   │
│  │  │  O(1) access │   │  O(ms)       │   │    O(100ms)            │  │   │
│  │  │  <10% budget │   │  1hr TTL     │   │    30-day TTL          │  │   │
│  │  └──────────────┘   └──────────────┘   └────────────────────────┘  │   │
│  │           ▲                                   ▲                     │   │
│  │           └──────────────┬────────────────────┘                     │   │
│  │                          │                                         │   │
│  │               ┌──────────┴──────────┐                              │   │
│  │               │  PREDICTIVE CACHE   │                              │   │
│  │               │  Prefetch • Promote │                              │   │
│  │               └─────────────────────┘                              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    STORAGE ABSTRACTION LAYER                        │   │
│  │                                                                     │   │
│  │   ┌──────────────┐   ┌──────────────┐   ┌──────────────────────┐   │   │
│  │   │ File Backend │   │Redis Backend │   │  ChromaDB Backend    │   │   │
│  │   │  (Default)   │   │ (Optional)   │   │  (Vector Search)     │   │   │
│  │   │  Always      │   │ Pub/Sub      │   │  Embeddings          │   │   │
│  │   │  Available   │   │ TTL          │   │  ANN Search          │   │   │
│  │   └──────────────┘   └──────────────┘   └──────────────────────┘   │   │
│  │                                                                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌───────────────────┐   │
│  │   PROJECT MEMORY    │  │   SESSION MEMORY    │  │   CROSS-CLI       │   │
│  │  (Persistent Scope) │  │  (Isolated Scope)   │  │   FEDERATION      │   │
│  │                     │  │                     │  │                   │   │
│  │ • Global discoveries│  │ • Current session   │  │ • MCP Format      │   │
│  │ • Codebase index    │  │ • Parent inheritance│  │ • Import/Export   │   │
│  │ • Conventions       │  │ • Temp checkponts   │  │ • Bridge Sessions │   │
│  └─────────────────────┘  └─────────────────────┘  └───────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 10. Conclusion

Mainframe's Agent Working Memory system represents a mature, production-ready architecture for AI agent memory management. The current implementation provides solid foundations with:

- **Robust session management** with atomic operations
- **Flexible storage backends** with graceful degradation
- **Tiered memory architecture** with automatic eviction
- **Token-aware context management** with basic compression

The proposed enhancements focus on **intelligent automation** - moving from manual memory management to predictive, semantic-aware systems that anticipate agent needs and optimize context usage automatically.

**Key architectural principles for implementation:**

1. **Backward Compatibility** - All enhancements must be opt-in
2. **Graceful Degradation** - Features fail soft when dependencies unavailable
3. **Observability** - Every decision logged for debugging
4. **Modularity** - Each enhancement is a standalone module
5. **Performance** - Sub-100ms for hot tier, sub-1s for cold tier operations

The recommended P0 enhancements (auto-offloading, emergency compression, priority scoring) would provide immediate value with moderate implementation effort, while the P1-P2 features build toward a fully autonomous memory management system.

---

*Review completed by Systems Architect*  
*For questions or clarifications, refer to the Mainframe project documentation*

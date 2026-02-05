# Mainframe Context Management Architecture Review

## Executive Summary

Mainframe has an **advanced, production-ready context management system** that already implements many best practices for AI agent memory management. This review assesses current capabilities and proposes architectural enhancements to enable long-running AI agent workflows at scale.

**Current State**: Tiered memory (Hot/Warm/Cold), token budgeting, semantic search via vector DB, session management with checkpoints, and multi-backend storage abstraction.

**Enhancement Focus**: Hierarchical token budgets, intelligent compression, cross-turn preservation, multi-agent context sharing, and domain-specific optimizations.

---

## 1. Current Capabilities Assessment

### 1.1 Token Management (`lib/context.sh`, `lib/llm_tokens.sh`)

| Feature | Status | Assessment |
|---------|--------|------------|
| Model-specific token estimation | ✅ Complete | 30+ models with accurate chars-per-token ratios |
| Content type detection | ✅ Complete | Code/text/data with appropriate ratios |
| Truncation strategies | ✅ Complete | head/tail/middle/smart with line preservation |
| Budget allocation | ✅ Complete | Labeled allocations with state persistence |
| Cost estimation | ✅ Complete | Input/output pricing for all major providers |
| Chunk splitting | ✅ Complete | Overlap support with line preservation |
| File batching | ✅ Complete | Sort by size/alpha/mtime with greedy selection |

**Strengths**:
- Tiktoken integration for OpenAI models (exact counts)
- Character-based heuristics as fallback (10-20% accuracy)
- Content-aware chunk sizing (code: 6000, text: 8000 for Claude)

**Gaps**:
- No hierarchical budget inheritance
- No predictive token usage models
- No compression trigger thresholds

### 1.2 Agent Working Memory (`lib/awm.sh`)

| Feature | Status | Assessment |
|---------|--------|------------|
| Session lifecycle | ✅ Complete | Init/resume/close with manifest |
| Checkpoint storage | ✅ Complete | Key-value with atomic writes |
| Category logging | ✅ Complete | Discoveries, errors, decisions, progress |
| Session inheritance | ✅ Complete | Parent → child context passing |
| Namespace isolation | ✅ Complete | Sub-agent separation |
| Token estimation | ✅ Complete | Per-operation cost prediction |
| Compression | ✅ Complete | Log archiving with age thresholds |

**Strengths**:
- Lock-safe concurrent access (flock)
- Session resumption after interruption
- Importance-weighted compression (discoveries preserved)

**Gaps**:
- No automatic compression triggers
- Limited semantic search integration

### 1.3 Tiered Memory (`lib/awm_tiers.sh`, `lib/awm_storage.sh`)

| Feature | Status | Assessment |
|---------|--------|------------|
| Hot tier (in-context) | ✅ Complete | In-memory associative arrays |
| Warm tier (working) | ✅ Complete | File/Redis with TTL |
| Cold tier (archive) | ✅ Complete | Persistent with semantic indexing |
| Auto-promotion | ✅ Complete | Hot→Warm→Cold based on size/importance |
| Auto-demotion | ✅ Complete | LRU eviction with importance weights |
| Storage backends | ✅ Complete | File/Redis/ChromaDB auto-detection |
| Crash recovery | ✅ Complete | Checkpoints to warm tier |

**Strengths**:
- Sub-100ms promotion latency target
- Importance-based retention (critical/high/normal/low)
- Zero-data-loss recovery

**Gaps**:
- No AST-aware code compression
- Limited cross-session memory sharing

### 1.4 Caching (`lib/cache.sh`)

| Feature | Status | Assessment |
|---------|--------|------------|
| Function memoization | ✅ Complete | SHA-256 key, TTL, dependency tracking |
| Content-addressable store | ✅ Complete | Deduplication via hashing |
| LRU eviction | ✅ Complete | Size-based with mtime sorting |
| Dependency invalidation | ✅ Complete | File hash tracking |
| Session cache | ✅ Complete | In-memory associative array |
| Smart preloading | ✅ Complete | Project-type detection |

### 1.5 Semantic Search (`lib/embeddings.sh`, `lib/vectordb.sh`)

| Feature | Status | Assessment |
|---------|--------|------------|
| Multi-provider embeddings | ✅ Complete | OpenAI, Ollama, local TF-IDF fallback |
| Vector DB backends | ✅ Complete | ChromaDB, Pinecone, Qdrant, SQLite |
| Similarity scoring | ✅ Complete | Cosine similarity with normalization |
| Embedding caching | ✅ Complete | SHA-256 keyed with TTL |
| Text chunking | ✅ Complete | Token-aware with overlap |

---

## 2. Token Budget Architecture

### 2.1 Hierarchical Budget Design

```
┌─────────────────────────────────────────────────────────────┐
│                    SYSTEM BUDGET                           │
│              (Model Context Window)                         │
│                    ~200K tokens                             │
├─────────────────────────────────────────────────────────────┤
│  AGENT 1 (40%)  │  AGENT 2 (35%)  │  AGENT 3 (25%)         │
│   ~80K tokens   │   ~70K tokens   │   ~50K tokens           │
├─────────────────┼─────────────────┼─────────────────────────┤
│ Task A │ Task B │ Task C │ Task D │ Task E │ Task F        │
│  30K   │  50K   │  35K   │  35K   │  25K   │  25K           │
├────────┴────────┴────────┴────────┴────────┴────────────────┤
│ Operations (per-task): System Prompt + Tools + History      │
│ Op 1: 5K │ Op 2: 8K │ Op 3: 12K │ Op 4: 5K                  │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Budget Structure

```bash
# Budget hierarchy definitions
declare -gA _CTX_BUDGET_HIERARCHY=(
    ["system"]=200000      # Claude-3 Opus context window
    ["agent"]=80000        # Per-agent allocation
    ["task"]=30000         # Per-task allocation
    ["operation"]=5000     # Per-operation buffer
)

# Budget pool with inheritance
declare -gA _CTX_BUDGET_POOLS=(
    ["system:available"]=200000
    ["system:reserved"]=20000    # 10% emergency reserve
    ["system:committed"]=0
)

# Per-agent tracking
declare -gA _CTX_AGENT_BUDGETS=(
    ["agent_abc123:allocated"]=80000
    ["agent_abc123:used"]=0
    ["agent_abc123:children"]=2
)
```

### 2.3 Dynamic Reallocation Algorithm

```bash
# Reallocate budget based on pressure and priority
_ctx_budget_reallocate() {
    local agent_id="$1"
    local pressure_level="$2"  # low|medium|high|critical
    
    local current=$(awm_budget_get "${agent_id}:allocated")
    local parent_id=$(awm_agent_parent "$agent_id")
    local siblings=$(awm_agent_siblings "$agent_id")
    
    case "$pressure_level" in
        critical)
            # Emergency: borrow from system reserve
            local reserve=$(awm_budget_get "system:reserved")
            local borrow=$((current * 25 / 100))
            [[ $borrow -gt $reserve ]] && borrow=$reserve
            awm_budget_transfer "system:reserve" "$agent_id" "$borrow"
            ;;
        high)
            # High pressure: reallocate from lowest-priority sibling
            local target_sibling=$(awm_budget_find_lowest_priority "$siblings")
            local available=$(awm_budget_available "$target_sibling")
            local reallocation=$((available * 20 / 100))
            awm_budget_transfer "$target_sibling" "$agent_id" "$reallocation"
            ;;
        medium)
            # Medium: request parent to reshuffle
            awm_budget_request_reshuffle "$parent_id"
            ;;
    esac
}
```

### 2.4 Token Usage Prediction Model

```bash
# Predict token usage based on operation type and history
_ctx_predict_tokens() {
    local operation_type="$1"
    local input_size="$2"
    local complexity="$3"  # simple|moderate|complex
    
    # Historical averages per operation type
    declare -gA _CTX_PREDICTION_MODEL=(
        ["file_read:avg_ratio"]=3.5
        ["file_read:std_dev"]=0.8
        ["code_gen:avg_ratio"]=4.2
        ["code_gen:std_dev"]=1.2
        ["analysis:avg_ratio"]=3.8
        ["analysis:std_dev"]=0.9
    )
    
    local base_ratio="${_CTX_PREDICTION_MODEL["${operation_type}:avg_ratio"]}"
    local std_dev="${_CTX_PREDICTION_MODEL["${operation_type}:std_dev"]}"
    
    # Apply complexity multiplier
    case "$complexity" in
        simple)   local multiplier=0.7 ;;
        moderate) local multiplier=1.0 ;;
        complex)  local multiplier=1.5 ;;
    esac
    
    # Calculate prediction with 2-sigma buffer (95% confidence)
    local predicted=$((input_size * base_ratio * multiplier / 10))
    local buffer=$((input_size * std_dev * 2 / 10))
    
    echo $((predicted + buffer))
}

# Update prediction model with actual results
_ctx_update_prediction_model() {
    local operation_type="$1"
    local predicted="$2"
    local actual="$3"
    
    # Exponential moving average update
    local alpha=0.3  # Learning rate
    local current_ratio="${_CTX_PREDICTION_MODEL["${operation_type}:avg_ratio"]}"
    local actual_ratio=$((actual * 10 / predicted))
    
    local new_ratio=$(echo "$alpha * $actual_ratio + (1 - $alpha) * $current_ratio" | bc)
    _CTX_PREDICTION_MODEL["${operation_type}:avg_ratio"]="$new_ratio"
}
```

### 2.5 Token Reservation for Critical Operations

```bash
# Reserve tokens for critical path operations
_ctx_reserve_critical() {
    local operation_id="$1"
    local estimated_tokens="$2"
    local priority="$3"  # 1-10
    
    local reservation_id="res_$(date +%s)_$RANDOM"
    local expiry=$(($(date +%s) + 300))  # 5 minute expiry
    
    # Store reservation
    _CTX_CRITICAL_RESERVATIONS["$reservation_id"]=$(jq -n \
        --arg id "$reservation_id" \
        --argjson tokens "$estimated_tokens" \
        --argjson priority "$priority" \
        --argjson expiry "$expiry" \
        '{id: $id, tokens: $tokens, priority: $priority, expiry: $expiry}')
    
    # Sort by priority and allocate
    _ctx_allocate_reservations
    
    echo "$reservation_id"
}

# Release reservation after operation completes
_ctx_release_reservation() {
    local reservation_id="$1"
    local actual_tokens="$2"
    
    unset "_CTX_CRITICAL_RESERVATIONS[$reservation_id]"
    
    # Update prediction model
    local reserved="${_CTX_RESERVATION_AMOUNTS[$reservation_id]}"
    _ctx_update_prediction_model "critical_path" "$reserved" "$actual_tokens"
}
```

---

## 3. Intelligent Context Compression

### 3.1 Summarization Trigger System

```bash
# Trigger levels for automatic summarization
declare -gA _CTX_COMPRESSION_TRIGGERS=(
    ["soft_threshold"]=70      # 70% of budget - start planning compression
    ["hard_threshold"]=85      # 85% of budget - execute compression
    ["emergency_threshold"]=95 # 95% of budget - aggressive compression
)

# Monitor and trigger compression
_ctx_compression_monitor() {
    local current_usage=$(awm_budget_used)
    local max_budget=$(awm_budget_max)
    local usage_pct=$((current_usage * 100 / max_budget))
    
    local soft="${_CTX_COMPRESSION_TRIGGERS["soft_threshold"]}"
    local hard="${_CTX_COMPRESSION_TRIGGERS["hard_threshold"]}"
    local emergency="${_CTX_COMPRESSION_TRIGGERS["emergency_threshold"]}"
    
    if [[ $usage_pct -ge $emergency ]]; then
        _ctx_compress_emergency
    elif [[ $usage_pct -ge $hard ]]; then
        _ctx_compress_hard
    elif [[ $usage_pct -ge $soft ]]; then
        _ctx_compress_plan
    fi
}
```

### 3.2 Semantic Chunking for Code

```bash
# AST-aware code chunking
_ctx_chunk_code_semantic() {
    local filepath="$1"
    local max_tokens="$2"
    
    # Detect language from extension
    local lang=$(awm_detect_language "$filepath")
    
    # Extract semantic units based on language
    case "$lang" in
        python)
            # Chunk by function/class definitions
            awk '/^(def |class )/ {print "CHUNK_START:" $0; next} {print}' "$filepath" | \
                awk 'BEGIN{chunk=""} /^CHUNK_START:/ {if(chunk) print chunk; chunk=$0; next} {chunk=chunk ORS $0} END{print chunk}' | \
                while IFS= read -r chunk; do
                    local tokens=$(context_estimate_tokens "$chunk")
                    if [[ $tokens -le $max_tokens ]]; then
                        echo "$chunk"
                    else
                        # Chunk is too large - split by logical blocks
                        _ctx_chunk_by_blocks "$chunk" "$lang" "$max_tokens"
                    fi
                done
            ;;
        javascript|typescript)
            # Chunk by function/const/let/var/export
            grep -nE '^(export |const |let |var |function |class |async function)' "$filepath" | \
                awk -F: 'NR>1 {print prev":"($1-1); prev=$1} END{print prev":"NR}' | \
                while IFS=: read -r start end; do
                    sed -n "${start},${end}p" "$filepath"
                done
            ;;
        *)
            # Fallback: line-based chunking
            context_chunk_size --type code --model claude | \
                xargs -I {} head -c {} "$filepath"
            ;;
    esac
}
```

### 3.3 Importance Scoring Algorithm

```bash
# Calculate importance score for context retention
calculate_importance_score() {
    local content="$1"
    local context_type="$2"  # conversation|code|tool_result|error
    local age_seconds="$3"
    local access_count="$4"
    
    # Base importance by type
    local base_score=0
    case "$context_type" in
        error)           base_score=100 ;;
        user_query)      base_score=90  ;;
        tool_result)     base_score=70  ;;
        code_change)     base_score=60  ;;
        ai_response)     base_score=50  ;;
        system_message)  base_score=40  ;;
        conversation)    base_score=30  ;;
        *)               base_score=10  ;;
    esac
    
    # Recency factor (exponential decay)
    local half_life=3600  # 1 hour
    local recency_factor=$(echo "e( -$age_seconds / $half_life )" | bc -l)
    
    # Access frequency factor (logarithmic)
    local access_factor=$(echo "l($access_count + 1) / l(10)" | bc -l)
    
    # Content density factor (information density)
    local char_count=${#content}
    local word_count=$(echo "$content" | wc -w)
    local density=$((char_count / (word_count + 1)))
    local density_factor=1
    [[ $density -gt 5 ]] && density_factor=1.2  # Technical content
    
    # Final score
    local final_score=$(echo "scale=2; $base_score * $recency_factor * (1 + $access_factor) * $density_factor" | bc)
    echo "${final_score%.*}"
}

# Rank context items by importance
_ctx_rank_for_retention() {
    local context_items="$1"  # JSON array
    
    echo "$context_items" | jq -c '.[]' | while read -r item; do
        local content=$(echo "$item" | jq -r '.content')
        local type=$(echo "$item" | jq -r '.type')
        local age=$(echo "$item" | jq -r '.age // 0')
        local accesses=$(echo "$item" | jq -r '.access_count // 0')
        
        local score=$(calculate_importance_score "$content" "$type" "$age" "$accesses")
        echo "$score $item"
    done | sort -rn | cut -d' ' -f2-
}
```

### 3.4 Progressive Disclosure Patterns

```bash
# Multi-level context disclosure
declare -gA _CTX_DISCLOSURE_LEVELS=(
    ["level_1"]=256    # Single sentence summary
    ["level_2"]=1024   # Paragraph summary
    ["level_3"]=4096   # Key details only
    ["level_4"]=16384  # Full content
    ["level_5"]=-1     # Complete with context
)

# Get content at appropriate disclosure level
_ctx_disclose() {
    local content_id="$1"
    local available_tokens="$2"
    
    # Determine level based on available tokens
    local level=1
    for l in 5 4 3 2 1; do
        local threshold="${_CTX_DISCLOSURE_LEVELS["level_$l"]}"
        if [[ $available_tokens -ge $threshold ]] || [[ $threshold -eq -1 ]]; then
            level=$l
            break
        fi
    done
    
    # Retrieve or generate content at level
    local cached=$(awm_get "disclosure:${content_id}:level${level}")
    if [[ -n "$cached" ]]; then
        echo "$cached"
        return
    fi
    
    # Generate summary at this level
    local full_content=$(awm_get "content:${content_id}")
    local summary=$(awm_summarize "$full_content" "$level")
    
    # Cache for future use
    awm_set "disclosure:${content_id}:level${level}" "$summary"
    echo "$summary"
}
```

---

## 4. Working Memory Tiers (Enhanced)

### 4.1 Three-Tier Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                        HOT TIER                              │
│                    (In-Context Memory)                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  System     │  │   Recent    │  │  Active Tools       │  │
│  │  Prompt     │  │   Messages  │  │  & Functions        │  │
│  │  ~2K tokens │  │  ~10K tok   │  │  ~5K tokens         │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│  Capacity: ~20K tokens | Access: <1ms | Persistence: None   │
├──────────────────────────────────────────────────────────────┤
│                       WARM TIER                              │
│                   (Working Memory)                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  Session    │  │   Cached    │  │  Recent Search      │  │
│  │  State      │  │   Results   │  │  Results            │  │
│  │  (AWM v1)   │  │             │  │                     │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│  Capacity: ~100K tokens | Access: ~10ms | TTL: 1 hour       │
├──────────────────────────────────────────────────────────────┤
│                       COLD TIER                              │
│                   (Archive Memory)                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  Vector DB  │  │   File      │  │  Knowledge Graph    │  │
│  │  (Semantic) │  │  Storage    │  │  (Relations)        │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│  Capacity: Unlimited | Access: ~100ms | TTL: 30 days        │
└──────────────────────────────────────────────────────────────┘
```

### 4.2 Automatic Promotion/Demotion Logic

```bash
# Promote from cold to warm based on query relevance
cold_to_warm_promotion() {
    local query_embedding="$1"
    local relevance_threshold=0.75
    
    # Search cold tier for highly relevant items
    local candidates=$(awm_cold_search_by_embedding "$query_embedding" 20)
    
    echo "$candidates" | jq -c '.[] | select(.score >= '"$relevance_threshold"')' | \
        while read -r item; do
            local key=$(echo "$item" | jq -r '.key')
            local value=$(echo "$item" | jq -r '.value')
            local score=$(echo "$item" | jq -r '.score')
            
            # Promote to warm tier
            local importance="normal"
            [[ $(echo "$score > 0.9" | bc -l) -eq 1 ]] && importance="high"
            
            awm_warm_set "$key" "$value" 3600 "$importance"
        done
}

# Demote from hot to warm based on inactivity
hot_to_warm_demotion() {
    local inactivity_threshold=300  # 5 minutes
    local current_time=$(date +%s)
    
    for key in "${_AWM_HOT_TIER[@]}"; do
        local meta="${_AWM_HOT_META[$key]}"
        local last_access=$(echo "$meta" | jq -r '.last_access')
        local importance=$(echo "$meta" | jq -r '.importance')
        
        # Skip critical items
        [[ "$importance" == "critical" ]] && continue
        
        local inactive=$((current_time - last_access))
        if [[ $inactive -gt $inactivity_threshold ]]; then
            local value="${_AWM_HOT_TIER[$key]}"
            awm_warm_set "$key" "$value" "$AWM_WARM_TTL" "$importance"
            awm_hot_delete "$key"
        fi
    done
}
```

### 4.3 Memory Indexing for Fast Retrieval

```bash
# Multi-index memory system
declare -gA _AWM_MEMORY_INDEXES=(
    ["semantic"]=1      # Vector embedding index
    ["temporal"]=1      # Time-based index
    ["hierarchical"]=1  # Parent-child relationships
    ["tagged"]=1        # Tag-based index
    ["fuzzy"]=1         # Fuzzy text search
)

# Build comprehensive index
awm_build_memory_index() {
    local session_id="$1"
    
    # Semantic index (embeddings)
    for item in $(awm_cold_list "$session_id"); do
        local content=$(echo "$item" | jq -r '.value')
        local key=$(echo "$item" | jq -r '.key')
        local embedding=$(embed_text "$content" "local")
        awm_index_store "semantic" "$key" "$embedding"
    done
    
    # Temporal index (timestamp buckets)
    for item in $(awm_cold_list "$session_id"); do
        local key=$(echo "$item" | jq -r '.key')
        local timestamp=$(echo "$item" | jq -r '.created')
        local hour_bucket=$((timestamp / 3600))
        awm_index_append "temporal:$hour_bucket" "$key"
    done
    
    # Hierarchical index
    for item in $(awm_cold_list "$session_id"); do
        local key=$(echo "$item" | jq -r '.key')
        local parent=$(echo "$item" | jq -r '.parent // empty')
        if [[ -n "$parent" ]]; then
            awm_index_append "children:$parent" "$key"
        fi
    done
}

# Search across all indexes
awm_multi_index_search() {
    local query="$1"
    local query_embedding=$(embed_text "$query" "local")
    
    # Semantic search
    local semantic_results=$(awm_index_search "semantic" "$query_embedding" 10)
    
    # Fuzzy text search
    local fuzzy_results=$(awm_index_fuzzy_search "$query" 10)
    
    # Recent temporal search
    local current_hour=$(($(date +%s) / 3600))
    local recent_keys=$(awm_index_get "temporal:$current_hour")
    
    # Merge and rank results
    jq -s 'add | unique_by(.key) | sort_by(.score) | reverse | .[0:10]' \
        <<< "$semantic_results" \
        <<< "$fuzzy_results"
}
```

### 4.4 Garbage Collection for Stale Memories

```bash
# Garbage collection strategy
declare -gA _AWM_GC_STRATEGY=(
    ["hot_max_age"]=600      # 10 minutes
    ["warm_max_age"]=3600    # 1 hour
    ["cold_max_age"]=2592000 # 30 days
    ["min_importance_gc"]=10 # Don't GC items with importance >= 10
)

# Run garbage collection
awm_gc_run() {
    local tier="$1"
    local dry_run="${2:-false}"
    local collected=0
    local current_time=$(date +%s)
    
    case "$tier" in
        hot)
            local max_age="${_AWM_GC_STRATEGY["hot_max_age"]}"
            for key in "${_!_AWM_HOT_META[@]}"; do
                local meta="${_AWM_HOT_META[$key]}"
                local last_access=$(echo "$meta" | jq -r '.last_access')
                local importance=$(echo "$meta" | jq -r '.importance_weight')
                
                local age=$((current_time - last_access))
                if [[ $age -gt $max_age ]] && [[ $importance -lt ${_AWM_GC_STRATEGY["min_importance_gc"]} ]]; then
                    if [[ "$dry_run" == "false" ]]; then
                        awm_hot_delete "$key"
                    fi
                    ((collected++))
                fi
            done
            ;;
        warm)
            local max_age="${_AWM_GC_STRATEGY["warm_max_age"]}"
            find "$AWM_WARM_DIR" -type f -mmin +$((max_age / 60)) -print0 | \
                while IFS= read -r -d '' file; do
                    if [[ "$dry_run" == "false" ]]; then
                        rm -f "$file"
                    fi
                    ((collected++))
                done
            ;;
        cold)
            awm_gc_cold_tier "$dry_run"
            ;;
    esac
    
    echo "Collected $collected items from $tier tier"
}

# Cold tier GC with vector consolidation
awm_gc_cold_tier() {
    local dry_run="$1"
    
    # Find similar vectors that can be consolidated
    local duplicates=$(awm_cold_find_duplicates 0.95)
    
    echo "$duplicates" | while read -r dup_group; do
        local keys=$(echo "$dup_group" | jq -r '.keys[]')
        local keep_key=$(echo "$keys" | head -1)
        
        # Merge metadata from duplicates
        local merged_meta=$(echo "$dup_group" | jq -c '.metadata | add')
        awm_cold_update_meta "$keep_key" "$merged_meta"
        
        # Remove duplicates
        for key in $(echo "$keys" | tail -n +2); do
            if [[ "$key" != "$keep_key" ]] && [[ "$dry_run" == "false" ]]; then
                awm_cold_delete "$key"
            fi
        done
    done
}
```

---

## 5. Cross-Turn Context Preservation

### 5.1 State Serialization Format

```json
{
  "session_id": "sess_abc123",
  "version": 42,
  "timestamp": "2024-01-15T10:30:00Z",
  "hot_tier": {
    "items": [
      {"key": "current_task", "value": "...", "meta": {...}},
      {"key": "user_preferences", "value": "...", "meta": {...}}
    ],
    "token_count": 15432
  },
  "conversation": {
    "messages": [...],
    "summary": "User is debugging a Python asyncio issue...",
    "turn_count": 15,
    "checkpoint_at_turn": 10
  },
  "checkpoints": [
    {"id": "cp_001", "turn": 5, "hash": "sha256:..."},
    {"id": "cp_002", "turn": 10, "hash": "sha256:..."}
  ],
  "tool_state": {
    "active_sessions": [...],
    "pending_operations": [...]
  },
  "metadata": {
    "agent_type": "code_assistant",
    "project_context": "python_web_app",
    "last_user_intent": "debug_error"
  }
}
```

### 5.2 Automatic State Checkpointing

```bash
# Checkpoint manager for cross-turn preservation
_ctx_checkpoint_manager() {
    local session_id="$1"
    local turn_number="$2"
    local operation="$3"  # save|restore|list|prune
    
    local checkpoint_dir="${AWM_ROOT}/checkpoints/${session_id}"
    mkdir -p "$checkpoint_dir"
    
    case "$operation" in
        save)
            local checkpoint_id="cp_${turn_number}_$(date +%s)"
            local state=$(_ctx_serialize_state "$session_id")
            local hash=$(echo "$state" | sha256sum | cut -c1-16)
            
            # Store checkpoint
            echo "$state" | gzip > "${checkpoint_dir}/${checkpoint_id}.json.gz"
            
            # Update index
            echo "${checkpoint_id}|${turn_number}|${hash}|$(date +%s)" >> "${checkpoint_dir}/index"
            
            # Keep only last N checkpoints
            _ctx_prune_checkpoints "$checkpoint_dir" 10
            
            echo "$checkpoint_id"
            ;;
        restore)
            local checkpoint_id="$4"
            local checkpoint_file="${checkpoint_dir}/${checkpoint_id}.json.gz"
            
            if [[ -f "$checkpoint_file" ]]; then
                zcat "$checkpoint_file" | _ctx_deserialize_state
                return 0
            fi
            return 1
            ;;
        list)
            if [[ -f "${checkpoint_dir}/index" ]]; then
                cat "${checkpoint_dir}/index" | column -t -s'|'
            fi
            ;;
        prune)
            local max_checkpoints="${4:-10}"
            _ctx_prune_checkpoints "$checkpoint_dir" "$max_checkpoints"
            ;;
    esac
}

# Periodic checkpointing based on changes
_ctx_auto_checkpoint() {
    local session_id="$1"
    local changes_since_last=$(awm_get_change_count "$session_id")
    local turns_since_last=$(awm_get_turns_since_checkpoint "$session_id")
    
    # Checkpoint every 5 turns or 20 changes
    if [[ $turns_since_last -ge 5 ]] || [[ $changes_since_last -ge 20 ]]; then
        local turn=$(awm_get_current_turn "$session_id")
        _ctx_checkpoint_manager "$session_id" "$turn" "save"
        awm_reset_change_count "$session_id"
    fi
}
```

### 5.3 Crash Recovery and Resumption

```bash
# Detect and recover from crashes
_ctx_crash_recovery() {
    local session_id="$1"
    
    # Check for dirty state indicator
    local dirty_file="${AWM_ROOT}/sessions/${session_id}/.dirty"
    if [[ ! -f "$dirty_file" ]]; then
        return 0  # Clean shutdown
    fi
    
    echo "[recovery] Detected unclean shutdown for session $session_id"
    
    # Load dirty state metadata
    local dirty_meta=$(cat "$dirty_file")
    local last_turn=$(echo "$dirty_meta" | jq -r '.last_turn')
    local last_checkpoint=$(echo "$dirty_meta" | jq -r '.last_checkpoint')
    local pending_ops=$(echo "$dirty_meta" | jq -r '.pending_operations // []')
    
    # Restore from last checkpoint
    echo "[recovery] Restoring from checkpoint $last_checkpoint"
    _ctx_checkpoint_manager "$session_id" "$last_turn" "restore" "$last_checkpoint"
    
    # Replay operations from WAL (Write-Ahead Log)
    local wal_file="${AWM_ROOT}/sessions/${session_id}/wal.jsonl"
    if [[ -f "$wal_file" ]]; then
        echo "[recovery] Replaying operations from WAL"
        tail -n +$((last_turn + 1)) "$wal_file" | while read -r entry; do
            local op=$(echo "$entry" | jq -r '.operation')
            local params=$(echo "$entry" | jq -r '.params')
            _ctx_replay_operation "$op" "$params"
        done
    fi
    
    # Mark recovery complete
    rm -f "$dirty_file"
    echo "[recovery] Session $session_id recovered successfully"
}

# Write-ahead logging for durability
_ctx_wal_append() {
    local session_id="$1"
    local operation="$2"
    local params="$3"
    
    local wal_file="${AWM_ROOT}/sessions/${session_id}/wal.jsonl"
    local entry=$(jq -n \
        --arg op "$operation" \
        --argjson params "$params" \
        --arg timestamp "$(date -Iseconds)" \
        '{timestamp: $timestamp, operation: $op, params: $params}')
    
    echo "$entry" >> "$wal_file"
    
    # Sync to ensure durability
    sync "$wal_file"
}
```

### 5.4 Context Diffing for Efficient Updates

```bash
# Generate diff between two context states
_ctx_diff_states() {
    local state_a="$1"
    local state_b="$2"
    
    # Compare hot tier items
    local hot_diff=$(jq -n \
        --argjson a "$(echo "$state_a" | jq '.hot_tier.items')" \
        --argjson b "$(echo "$state_b" | jq '.hot_tier.items')" \
        '{
            added: [$b[] | select(.key as $k | $a | map(.key) | index($k) | not)],
            removed: [$a[] | select(.key as $k | $b | map(.key) | index($k) | not)],
            modified: [
                $a[] as $item_a |
                $b[] as $item_b |
                select($item_a.key == $item_b.key and $item_a.value != $item_b.value) |
                {key: $item_a.key, old: $item_a.value, new: $item_b.value}
            ]
        }')
    
    # Compare conversation state
    local conv_diff=$(jq -n \
        --argjson a "$(echo "$state_a" | jq '.conversation')" \
        --argjson b "$(echo "$state_b" | jq '.conversation')" \
        '{
            new_messages: ($b.messages - $a.messages),
            summary_changed: ($a.summary != $b.summary)
        }')
    
    # Merge diffs
    jq -n \
        --argjson hot "$hot_diff" \
        --argjson conv "$conv_diff" \
        '{hot_tier: $hot, conversation: $conv}'
}

# Apply diff to update context efficiently
_ctx_apply_diff() {
    local base_state="$1"
    local diff="$2"
    
    # Add new items
    for item in $(echo "$diff" | jq -c '.hot_tier.added[]'); do
        local key=$(echo "$item" | jq -r '.key')
        local value=$(echo "$item" | jq -r '.value')
        awm_hot_set "$key" "$value"
    done
    
    # Remove deleted items
    for key in $(echo "$diff" | jq -r '.hot_tier.removed[].key'); do
        awm_hot_delete "$key"
    done
    
    # Update modified items
    for item in $(echo "$diff" | jq -c '.hot_tier.modified[]'); do
        local key=$(echo "$item" | jq -r '.key')
        local new_value=$(echo "$item" | jq -r '.new')
        awm_hot_set "$key" "$new_value"
    done
    
    # Append new messages
    for msg in $(echo "$diff" | jq -c '.conversation.new_messages[]'); do
        awm_conversation_append "$msg"
    done
}
```

---

## 6. Multi-Agent Context Sharing

### 6.1 Shared Context Space Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                   SHARED CONTEXT SPACE                        │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              SHARED KNOWLEDGE GRAPH                      │ │
│  │  (Entities, Relationships, Inferred Knowledge)           │ │
│  └─────────────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              SHARED VECTOR INDEX                         │ │
│  │  (Semantic embeddings of shared documents/code)          │ │
│  └─────────────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              COORDINATION LOG                            │ │
│  │  (Agent actions, decisions, handoffs)                    │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  Agent A    Agent B    Agent C    Agent D                    │
│    │          │          │          │                        │
│    └──────────┴──────────┴──────────┘                        │
│                │                                              │
│         ┌──────┴──────┐                                       │
│         │  SYNC BUS   │  (Pub/Sub for real-time updates)     │
│         └─────────────┘                                       │
└──────────────────────────────────────────────────────────────┘
```

### 6.2 Context Inheritance Patterns

```bash
# Define inheritance patterns for sub-agent spawning
declare -gA _CTX_INHERITANCE_PATTERNS=(
    ["minimal"]=1      # Session ID only
    ["task"]=2         # Task context + discoveries
    ["full"]=3         # All hot tier + working memory
    ["selective"]=4    # Custom selection
)

# Spawn sub-agent with inherited context
_ctx_spawn_sub_agent() {
    local parent_id="$1"
    local sub_agent_name="$2"
    local inheritance_pattern="${3:-task}"
    local custom_selection="${4:-}"
    
    # Generate sub-agent ID
    local sub_id="${parent_id}_$(echo "$sub_agent_name" | tr ' ' '_')_$(date +%s)"
    
    # Create sub-agent session
    awm_init "$sub_agent_name" "$parent_id"
    awm_namespace "$sub_id"
    
    # Apply inheritance pattern
    case "$inheritance_pattern" in
        minimal)
            # Just session linkage
            awm_checkpoint "parent_session" "$parent_id"
            ;;
        task)
            # Inherit discoveries and task context
            local discoveries=$(awm_recent "discoveries" 20)
            awm_checkpoint "inherited_discoveries" "$discoveries"
            
            local task_context=$(awm_get "task_context")
            awm_checkpoint "task_context" "$task_context"
            ;;
        full)
            # Full hot tier inheritance
            local hot_data=$(awm_hot_dump)
            awm_checkpoint "inherited_hot_tier" "$hot_data"
            
            # Inherit all checkpoints
            local checkpoints=$(awm_summary | jq '.checkpoints')
            awm_checkpoint "inherited_checkpoints" "$checkpoints"
            ;;
        selective)
            # Custom selection
            for key in $custom_selection; do
                local value=$(awm_get "$key")
                [[ -n "$value" ]] && awm_checkpoint "$key" "$value"
            done
            ;;
    esac
    
    # Record spawn event in parent
    awm_log "agent_spawns" "Spawned $sub_agent_name ($sub_id) with $inheritance_pattern inheritance"
    
    echo "$sub_id"
}

# Aggregate results from sub-agents
_ctx_aggregate_results() {
    local parent_id="$1"
    shift
    local sub_agent_ids=("$@")
    
    local aggregated='{"results": [], "discoveries": [], "conflicts": []}'
    
    for sub_id in "${sub_agent_ids[@]}"; do
        # Load sub-agent results
        local sub_results=$(awm_export_session "$sub_id")
        
        # Extract discoveries
        local sub_discoveries=$(echo "$sub_results" | jq '.discoveries')
        aggregated=$(echo "$aggregated" | jq --argjson d "$sub_discoveries" '.discoveries += $d')
        
        # Extract results
        local sub_output=$(echo "$sub_results" | jq '.checkpoints.result')
        aggregated=$(echo "$aggregated" | jq --argjson r "$sub_output" '.results += [$r]')
    done
    
    # Detect conflicts
    aggregated=$(echo "$aggregated" | jq '
        .conflicts = [
            .results | group_by(.key) | 
            map(select(length > 1 and map(.value) | unique | length > 1)) | 
            add // empty
        ]
    ')
    
    echo "$aggregated"
}
```

### 6.3 Context Isolation When Needed

```bash
# Create isolated sandbox for untrusted operations
_ctx_create_isolated_context() {
    local base_session="$1"
    local isolation_level="${2:-hard}"  # soft|hard|airgap
    
    local sandbox_id="sandbox_$(date +%s)_$RANDOM"
    
    case "$isolation_level" in
        soft)
            # Copy-on-write: share read-only base, copy modifications
            mkdir -p "${AWM_ROOT}/sandboxes/${sandbox_id}"
            mount -o bind,ro "${AWM_ROOT}/sessions/${base_session}" \
                           "${AWM_ROOT}/sandboxes/${sandbox_id}/base" 2>/dev/null || true
            
            # Writable overlay for changes
            mkdir -p "${AWM_ROOT}/sandboxes/${sandbox_id}/{upper,work}"
            mount -t overlay overlay \
                -o "lowerdir=${AWM_ROOT}/sandboxes/${sandbox_id}/base,"\
"upperdir=${AWM_ROOT}/sandboxes/${sandbox_id}/upper,"\
"workdir=${AWM_ROOT}/sandboxes/${sandbox_id}/work" \
                "${AWM_ROOT}/sessions/${sandbox_id}" 2>/dev/null || true
            ;;
        hard)
            # Complete copy, no sharing
            cp -r "${AWM_ROOT}/sessions/${base_session}" \
                  "${AWM_ROOT}/sessions/${sandbox_id}"
            ;;
        airgap)
            # No data sharing, only schema
            mkdir -p "${AWM_ROOT}/sessions/${sandbox_id}"
            # Copy only structure, no content
            find "${AWM_ROOT}/sessions/${base_session}" -type d -exec \
                mkdir -p "${AWM_ROOT}/sessions/${sandbox_id}/{}" \;
            ;;
    esac
    
    # Mark as sandbox
    echo "$isolation_level" > "${AWM_ROOT}/sessions/${sandbox_id}/.isolated"
    
    echo "$sandbox_id"
}

# Merge isolated context back (if approved)
_ctx_merge_isolated() {
    local sandbox_id="$1"
    local approval_check="${2:-true}"
    
    # Verify isolation marker
    if [[ ! -f "${AWM_ROOT}/sessions/${sandbox_id}/.isolated" ]]; then
        echo "Error: Not an isolated session"
        return 1
    fi
    
    # Run approval check
    if [[ "$approval_check" == "true" ]]; then
        local changes=$(diff -r "${AWM_ROOT}/sessions/${parent_id}" \
                                 "${AWM_ROOT}/sessions/${sandbox_id}")
        local approved=$(awm_request_approval "$changes")
        [[ "$approved" != "true" ]] && return 1
    fi
    
    # Perform merge
    local parent_id=$(awm_get_parent "$sandbox_id")
    awm_merge_sessions "$parent_id" "$sandbox_id"
    
    # Cleanup sandbox
    rm -rf "${AWM_ROOT}/sessions/${sandbox_id}"
    [[ -d "${AWM_ROOT}/sandboxes/${sandbox_id}" ]] && \
        rm -rf "${AWM_ROOT}/sandboxes/${sandbox_id}"
}
```

### 6.4 Conflict Resolution for Shared State

```bash
# Detect and resolve state conflicts
_ctx_resolve_conflicts() {
    local conflicting_states="$1"  # JSON array of conflicting values
    local resolution_strategy="${2:-auto}"  # auto|manual|last-write-wins|merge
    
    case "$resolution_strategy" in
        last-write-wins)
            # Take most recent
            echo "$conflicting_states" | jq 'max_by(.timestamp)'
            ;;
        
        merge)
            # Attempt intelligent merge
            _ctx_intelligent_merge "$conflicting_states"
            ;;
        
        auto)
            # Automatic resolution based on content type
            local content_type=$(echo "$conflicting_states" | jq -r '.[0].type')
            
            case "$content_type" in
                counter|number)
                    # Sum numeric values
                    echo "$conflicting_states" | jq '{value: [.[].value] | add}'
                    ;;
                set|list)
                    # Union of unique items
                    echo "$conflicting_states" | jq '{value: [.[].value] | flatten | unique}'
                    ;;
                flag|boolean)
                    # OR operation for flags
                    echo "$conflicting_states" | jq '{value: [.[].value] | any}'
                    ;;
                text)
                    # Concatenate with separator
                    echo "$conflicting_states" | jq '{value: [.[].value] | join("\n---\n")}'
                    ;;
                *)
                    # Default to last-write-wins
                    echo "$conflicting_states" | jq 'max_by(.timestamp)'
                    ;;
            esac
            ;;
        
        manual)
            # Queue for manual resolution
            local conflict_id="conflict_$(date +%s)_$RANDOM"
            echo "$conflicting_states" > "${AWM_ROOT}/conflicts/${conflict_id}"
            echo '{"status": "pending_resolution", "conflict_id": "'"$conflict_id"'"}'
            ;;
    esac
}

# Three-way merge for concurrent modifications
_ctx_three_way_merge() {
    local base="$1"      # Common ancestor
    local left="$2"      # Agent A's version
    local right="$3"     # Agent B's version
    
    # Detect which side changed what
    local left_changes=$(diff -u <(echo "$base") <(echo "$left") | grep '^[+-]' | grep -v '^[+-][+-][+-]')
    local right_changes=$(diff -u <(echo "$base") <(echo "$right") | grep '^[+-]' | grep -v '^[+-][+-][+-]')
    
    # Check for overlapping changes
    local conflicts=$(comm -12 <(echo "$left_changes" | sort) <(echo "$right_changes" | sort))
    
    if [[ -z "$conflicts" ]]; then
        # No conflicts - apply both sets of changes
        echo "$base" | jq --argjson l "$left" --argjson r "$right" '
            . as $base |
            $base + ($l - $base) + ($r - $base)
        '
    else
        # Conflicts detected
        echo '{"conflict": true, "details": "Overlapping modifications detected"}'
    fi
}
```

---

## 7. Domain-Specific Optimizations

### 7.1 Code Context Management (AST-Aware)

```bash
# AST-aware code compression
_ctx_compress_code_ast() {
    local filepath="$1"
    local target_tokens="$2"
    local lang=$(awm_detect_language "$filepath")
    
    # Parse and extract AST structure
    local ast=$(awm_parse_ast "$filepath" "$lang")
    
    # Identify critical elements
    local critical=$(echo "$ast" | jq '[
        .definitions[] | select(.type == "function" or .type == "class"),
        .imports[],
        .exports[]
    ]')
    
    # Identify compressible elements (implementation details)
    local compressible=$(echo "$ast" | jq '[
        .definitions[].body | select(.complexity > 10)
    ]')
    
    # Generate compressed representation
    local compressed=$(jq -n \
        --argjson critical "$critical" \
        --argjson compressible "$compressible" \
        '{
            signature: $critical,
            implementations: ($compressible | map({
                name: .name,
                summary: .summary,
                complexity: .complexity,
                lines: .line_count
            })),
            metrics: {
                total_lines: ($critical | length + $compressible | length),
                compressed: true
            }
        }')
    
    # Verify token count
    local token_count=$(context_estimate_tokens "$compressed")
    if [[ $token_count -gt $target_tokens ]]; then
        # Further compression needed - summarize implementations
        compressed=$(echo "$compressed" | jq '.implementations = (.implementations | map({name, summary}))')
    fi
    
    echo "$compressed"
}

# Code-aware context assembly
_ctx_assemble_code_context() {
    local target_file="$1"
    local max_tokens="$2"
    
    # Get file dependencies
    local deps=$(awm_get_dependencies "$target_file")
    
    # Build dependency graph
    local dep_graph=$(echo "$deps" | jq '[.[] | {file: ., tokens: 0}]')
    
    # Calculate tokens for each dependency
    for dep in $(echo "$deps" | jq -r '.[]'); do
        local tokens=$(context_file_tokens "$dep")
        dep_graph=$(echo "$dep_graph" | jq 'map(if .file == "'"$dep"'" then .tokens = '"$tokens"' else . end)')
    done
    
    # Sort by importance (distance from target)
    dep_graph=$(echo "$dep_graph" | jq 'sort_by(.tokens)')
    
    # Greedy selection to fit budget
    local context=""
    local used_tokens=0
    
    for item in $(echo "$dep_graph" | jq -c '.[]'); do
        local file=$(echo "$item" | jq -r '.file')
        local tokens=$(echo "$item" | jq -r '.tokens')
        
        if [[ $((used_tokens + tokens)) -le $max_tokens ]]; then
            local content=$(cat "$file")
            context="${context}\n// --- ${file} ---\n${content}"
            used_tokens=$((used_tokens + tokens))
        fi
    done
    
    echo -e "$context"
}
```

### 7.2 Conversation History Optimization

```bash
# Conversation summarization strategy
_ctx_optimize_conversation() {
    local messages="$1"
    local max_tokens="$2"
    
    # Estimate current size
    local current_tokens=$(context_estimate_tokens "$messages")
    
    if [[ $current_tokens -le $max_tokens ]]; then
        echo "$messages"
        return
    fi
    
    # Phase 1: Compress individual messages
    local compressed=$(echo "$messages" | jq '[.[] | {
        role: .role,
        content: (if (.content | length) > 1000 then 
            (.content | .[0:500] + "... [truncated] ..." + .[-200:]) 
        else .content end),
        timestamp: .timestamp,
        importance: (.importance // "normal")
    }]')
    
    # Phase 2: Summarize old exchanges into running summary
    local cutoff_age=$(($(date +%s) - 3600))  # 1 hour
    local old_messages=$(echo "$compressed" | jq '[.[] | select(.timestamp < '"$cutoff_age"')]')
    local recent_messages=$(echo "$compressed" | jq '[.[] | select(.timestamp >= '"$cutoff_age"')]')
    
    # Generate summary of old messages
    local summary=$(awm_summarize_conversation "$old_messages")
    
    # Combine summary with recent messages
    jq -n \
        --arg summary "$summary" \
        --argjson recent "$recent_messages" \
        '{
            context_summary: $summary,
            recent_messages: $recent
        }'
}

# Extract key information from conversation
_ctx_extract_conversation_keypoints() {
    local conversation="$1"
    
    echo "$conversation" | jq '
        group_by(.role) |
        map({
            role: .[0].role,
            key_points: [
                .[] | select(.content | contains("TODO:")) |
                {type: "todo", content: .content},
                .[] | select(.content | contains("BUG:")) |
                {type: "bug", content: .content},
                .[] | select(.content | contains("NOTE:")) |
                {type: "note", content: .content}
            ]
        })
    '
}
```

### 7.3 File Operation Context Tracking

```bash
# Track file operations for context reconstruction
_ctx_track_file_operation() {
    local operation="$1"  # read|write|modify|delete
    local filepath="$2"
    local metadata="${3:-{}}"
    
    local operation_id="op_$(date +%s)_$RANDOM"
    local timestamp=$(date -Iseconds)
    local hash=$(sha256sum "$filepath" 2>/dev/null | cut -c1-16 || echo "deleted")
    
    # Record operation
    local entry=$(jq -n \
        --arg id "$operation_id" \
        --arg op "$operation" \
        --arg file "$filepath" \
        --arg hash "$hash" \
        --arg time "$timestamp" \
        --argjson meta "$metadata" \
        '{
            id: $id,
            operation: $op,
            file: $file,
            hash: $hash,
            timestamp: $time,
            metadata: $meta
        }')
    
    # Append to operation log
    echo "$entry" >> "${AWM_ROOT}/sessions/${_AWM_SESSION_ID}/file_ops.jsonl"
    
    # Update file state
    _CTX_FILE_STATES["$filepath"]="$entry"
    
    echo "$operation_id"
}

# Reconstruct context from file operations
_ctx_reconstruct_from_operations() {
    local since_timestamp="$1"
    
    # Read operation log
    local ops=$(jq -s '.' "${AWM_ROOT}/sessions/${_AWM_SESSION_ID}/file_ops.jsonl" | \
                jq '[.[] | select(.timestamp >= "'"$since_timestamp"'")]')
    
    # Group by file
    local by_file=$(echo "$ops" | jq 'group_by(.file)')
    
    # Generate summary per file
    echo "$by_file" | jq '[.[] | {
        file: .[0].file,
        operations: length,
        last_operation: last.operation,
        current_state: (if last.operation == "delete" then "deleted" else "exists" end)
    }]'
}
```

### 7.4 Error Context Preservation

```bash
# Enhanced error capture with full context
_ctx_capture_error_context() {
    local error_message="$1"
    local error_code="${2:-1}"
    
    local error_id="err_$(date +%s)_$RANDOM"
    
    # Capture comprehensive context
    local context=$(jq -n \
        --arg id "$error_id" \
        --arg msg "$error_message" \
        --argjson code "$error_code" \
        --arg session "$_AWM_SESSION_ID" \
        --argjson hot_size "$(awm_hot_size)" \
        --argjson budget_remaining "$(context_budget_remaining)" \
        --arg hot_dump "$(awm_hot_dump | head -c 10000)" \
        '{
            error_id: $id,
            message: $msg,
            code: $code,
            timestamp: now,
            session: $session,
            context_state: {
                hot_tier_size: $hot_size,
                budget_remaining: $budget_remaining,
                recent_items: $hot_dump
            },
            system_state: {
                pwd: $ENV.PWD,
                last_commands: []  # Populated from history
            }
        }')
    
    # Store in error log
    echo "$context" >> "${AWM_ROOT}/sessions/${_AWM_SESSION_ID}/errors.jsonl"
    
    # Also checkpoint for recovery
    _ctx_checkpoint_manager "$_AWM_SESSION_ID" "$(awm_get_current_turn)" "save"
    
    echo "$error_id"
}

# Error context retrieval for debugging
_ctx_get_error_context() {
    local error_id="$1"
    
    # Find error in log
    local error_entry=$(jq -s '.[] | select(.error_id == "'"$error_id"'")' \
        "${AWM_ROOT}/sessions/${_AWM_SESSION_ID}/errors.jsonl")
    
    # Retrieve associated checkpoint
    local checkpoint_id=$(echo "$error_entry" | jq -r '.checkpoint_id // empty')
    
    if [[ -n "$checkpoint_id" ]]; then
        local checkpoint=$(awm_checkpoint_load "$checkpoint_id")
        error_entry=$(echo "$error_entry" | jq --argjson cp "$checkpoint" '. + {checkpoint: $cp}')
    fi
    
    echo "$error_entry"
}
```

---

## 8. Implementation Phases and Priorities

### Phase 1: Foundation (Weeks 1-2) - CRITICAL

**Goal**: Establish core infrastructure for advanced context management

| Component | Priority | Effort | Deliverable |
|-----------|----------|--------|-------------|
| Hierarchical Token Budgets | P0 | 3 days | `lib/awm_budget_hierarchy.sh` |
| Token Prediction Model | P1 | 2 days | Basic linear regression model |
| Compression Triggers | P0 | 2 days | Threshold monitoring daemon |
| State Serialization | P0 | 3 days | JSON serialization for all tiers |

**Dependencies**: Existing AWM v2, context.sh

**Success Criteria**:
- [ ] Hierarchical budgets functional with parent-child inheritance
- [ ] Compression triggers fire at correct thresholds
- [ ] Full state can be serialized/deserialized

### Phase 2: Intelligence (Weeks 3-4) - HIGH

**Goal**: Add intelligent compression and cross-turn preservation

| Component | Priority | Effort | Deliverable |
|-----------|----------|--------|-------------|
| Semantic Code Chunking | P1 | 3 days | AST-aware chunking for Python/JS/TS |
| Importance Scoring | P1 | 2 days | Multi-factor importance algorithm |
| Progressive Disclosure | P2 | 2 days | Multi-level summary system |
| Checkpoint Automation | P1 | 2 days | Auto-checkpoint on changes |

**Dependencies**: Phase 1, embeddings.sh

**Success Criteria**:
- [ ] Code compressed with <5% semantic loss
- [ ] Importance scores correlate with human judgment
- [ ] Checkpoints created automatically every N turns

### Phase 3: Resilience (Weeks 5-6) - HIGH

**Goal**: Enable crash recovery and long-running workflows

| Component | Priority | Effort | Deliverable |
|-----------|----------|--------|-------------|
| Write-Ahead Logging | P1 | 2 days | WAL implementation for durability |
| Crash Recovery | P0 | 3 days | Automatic recovery on startup |
| Context Diffing | P2 | 2 days | Efficient state diff/patch |
| Garbage Collection | P2 | 2 days | Tier GC with importance weighting |

**Dependencies**: Phase 2

**Success Criteria**:
- [ ] Zero data loss on simulated crash
- [ ] Recovery completes in <5 seconds
- [ ] GC runs without impacting performance

### Phase 4: Multi-Agent (Weeks 7-8) - MEDIUM

**Goal**: Enable agent teams with shared context

| Component | Priority | Effort | Deliverable |
|-----------|----------|--------|-------------|
| Shared Context Space | P1 | 3 days | Redis-backed shared memory |
| Context Inheritance | P1 | 2 days | Sub-agent spawning patterns |
| Conflict Resolution | P2 | 3 days | Auto-merge strategies |
| Isolation Sandboxes | P2 | 2 days | Copy-on-write isolation |

**Dependencies**: Phase 3, awm_storage.sh

**Success Criteria**:
- [ ] 3+ agents share context without conflicts
- [ ] Sub-agents inherit appropriate context
- [ ] Conflicts resolved automatically in >80% of cases

### Phase 5: Domain Optimization (Weeks 9-10) - MEDIUM

**Goal**: Domain-specific optimizations for code and conversations

| Component | Priority | Effort | Deliverable |
|-----------|----------|--------|-------------|
| AST-Aware Compression | P1 | 3 days | Language-specific parsers |
| Conversation Optimization | P2 | 2 days | Message summarization |
| File Operation Tracking | P2 | 2 days | Operation log with reconstruction |
| Error Context Preservation | P1 | 2 days | Comprehensive error capture |

**Dependencies**: Phase 4

**Success Criteria**:
- [ ] Code context 50% smaller with same comprehension
- [ ] Conversation history optimized automatically
- [ ] Errors include full recovery context

### Phase 6: Integration & Polish (Weeks 11-12) - LOW

**Goal**: Integration with existing Mainframe systems

| Component | Priority | Effort | Deliverable |
|-----------|----------|--------|-------------|
| USOP Compliance | P1 | 2 days | All functions USOP-compliant |
| Documentation | P0 | 3 days | Complete API documentation |
| Performance Testing | P1 | 3 days | Benchmarks for all tiers |
| Migration Tools | P2 | 2 days | AWM v1 → v2 migration |

**Dependencies**: All previous phases

---

## 9. Integration Points with Mainframe

### 9.1 Module Dependencies

```
lib/context_manager.sh
├── lib/awm.sh (session management)
├── lib/awm_tiers.sh (tiered memory)
├── lib/awm_storage.sh (storage backends)
├── lib/context.sh (token estimation)
├── lib/llm_tokens.sh (model-specific counting)
├── lib/embeddings.sh (semantic search)
├── lib/vectordb.sh (vector storage)
├── lib/cache.sh (memoization)
├── lib/agent_context.sh (persistent contexts)
└── lib/json.sh (JSON utilities)
```

### 9.2 Hook Points

```bash
# Initialize context manager in mainframe init
mainframe_init() {
    # Existing initialization...
    
    # New: Context manager initialization
    source "${MAINFRAME_ROOT}/lib/context_manager.sh"
    ctx_manager_init --model "${MAINFRAME_LLM_MODEL:-claude-3-opus-4}"
    
    # Register cleanup handler
    trap ctx_manager_cleanup EXIT
}

# Pre-LLM call hook
pre_llm_call() {
    local prompt="$1"
    
    # Check budget and compress if needed
    ctx_manager_check_budget "$prompt"
    
    # Update token prediction model
    ctx_manager_predict_tokens "$prompt"
    
    # Return potentially modified prompt
    ctx_manager_optimize_prompt "$prompt"
}

# Post-LLM call hook
post_llm_call() {
    local prompt="$1"
    local response="$2"
    local actual_tokens="$3"
    
    # Update prediction model
    ctx_manager_update_model "$prompt" "$actual_tokens"
    
    # Record interaction
    ctx_manager_record_turn "$prompt" "$response"
    
    # Auto-checkpoint if needed
    ctx_manager_auto_checkpoint
}
```

### 9.3 Configuration Integration

```bash
# config/context.conf
CONTEXT_MANAGER_ENABLED=1
CONTEXT_MODEL="claude-3-opus-4"
CONTEXT_HOT_TIER_MAX=20000
CONTEXT_WARM_TIER_MAX=100000
CONTEXT_COLD_TIER_MAX=0  # Unlimited

COMPRESSION_SOFT_THRESHOLD=70
COMPRESSION_HARD_THRESHOLD=85
COMPRESSION_EMERGENCY_THRESHOLD=95

CHECKPOINT_INTERVAL_TURNS=5
CHECKPOINT_INTERVAL_CHANGES=20
WAL_ENABLED=1

GC_HOT_MAX_AGE=600
GC_WARM_MAX_AGE=3600
GC_COLD_MAX_AGE=2592000
```

---

## 10. Metrics and Monitoring

### 10.1 Key Performance Indicators

| Metric | Target | Measurement |
|--------|--------|-------------|
| Hot tier access latency | <1ms | p99 measurement |
| Warm tier access latency | <10ms | p99 measurement |
| Cold tier access latency | <100ms | p99 measurement |
| Promotion latency | <100ms | Tier-to-tier promotion |
| Checkpoint duration | <500ms | Full state save |
| Recovery time | <5s | From crash to operational |
| Token prediction accuracy | ±15% | MAE vs actual |
| Compression ratio | 3:1 | Original:compressed |
| GC pause time | <50ms | Stop-the-world duration |

### 10.2 Health Checks

```bash
# Context manager health check
ctx_manager_health_check() {
    local checks=()
    
    # Check tier connectivity
    if ! awm_hot_ping; then
        checks+=("hot_tier:unhealthy")
    fi
    
    # Check budget state
    local budget_usage=$(awm_budget_usage_pct)
    if [[ $budget_usage -gt 95 ]]; then
        checks+=("budget:critical")
    elif [[ $budget_usage -gt 80 ]]; then
        checks+=("budget:warning")
    fi
    
    # Check storage backend
    if ! awm_storage_health; then
        checks+=("storage:unhealthy")
    fi
    
    # Check WAL
    if [[ -n "$_CTX_WAL_UNFLUSHED" ]] && [[ $_CTX_WAL_UNFLUSHED -gt 100 ]]; then
        checks+=("wal:backlogged")
    fi
    
    if [[ ${#checks[@]} -eq 0 ]]; then
        echo "healthy"
    else
        echo "degraded: ${checks[*]}"
    fi
}
```

---

## 11. Conclusion

Mainframe's existing context management infrastructure provides a **solid foundation** for advanced AI agent workflows. The proposed enhancements build incrementally on this foundation:

1. **Hierarchical budgets** enable complex multi-agent scenarios
2. **Intelligent compression** extends effective context by 3-5x
3. **Cross-turn preservation** enables truly long-running workflows
4. **Multi-agent sharing** enables collaborative agent teams
5. **Domain optimizations** provide specialized handling for code

**Risk Assessment**:
- **Low**: Phases 1-3 build on existing stable infrastructure
- **Medium**: Phase 4 multi-agent introduces distributed systems complexity
- **Low**: Phase 5 domain optimizations are additive features

**Recommendation**: Proceed with Phase 1 immediately as it provides immediate value for context-intensive workflows. Phases 2-3 follow in parallel tracks, with Phase 4 contingent on successful completion of multi-agent architecture review.

---

## Appendix A: Glossary

| Term | Definition |
|------|------------|
| **AWM** | Agent Working Memory - Mainframe's persistent memory system |
| **Hot Tier** | In-context memory (active in LLM context window) |
| **Warm Tier** | Working memory (fast access, TTL-based) |
| **Cold Tier** | Archive memory (persistent, searchable) |
| **USOP** | Uniform Structured Output Protocol - Mainframe's API standard |
| **WAL** | Write-Ahead Log - Durability mechanism |
| **AST** | Abstract Syntax Tree - Code structure representation |
| **GC** | Garbage Collection - Memory reclamation |

## Appendix B: References

- `lib/awm.sh` - Core AWM implementation
- `lib/awm_tiers.sh` - Tiered memory implementation
- `lib/awm_storage.sh` - Storage abstraction
- `lib/context.sh` - Token management
- `lib/llm_tokens.sh` - Model-specific token counting
- `lib/cache.sh` - Caching and memoization
- `lib/embeddings.sh` - Semantic embeddings
- `lib/vectordb.sh` - Vector database interface

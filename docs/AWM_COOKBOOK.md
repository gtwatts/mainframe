# AWM Cookbook - Agent Working Memory Usage Patterns

Practical guide for AI agents using MAINFRAME's Agent Working Memory (AWM) system.

**Last Updated:** 2026-02-01

---

## Quick Reference

### Essential Functions

```bash
# Session lifecycle
sid=$(awm_init "task-name")          # Start new session, returns session_id
sid=$(awm_init "subtask" "$parent")  # Inherit from parent session
awm_resume "$sid"                    # Resume existing session
awm_close                            # Mark session complete

# Core writes
awm_checkpoint "key" "value"         # Idempotent key-value store
awm_discovery "Important finding"    # High-priority insight (never compressed)
awm_log "category" "message"         # Append to category log
awm_progress "task" "47/200"         # Track task progress

# Core reads
value=$(awm_get "key" "default")     # Retrieve checkpoint (with default)
entries=$(awm_recent "errors" 10)    # Last N entries from category
summary=$(awm_summary)               # Compressed session overview
ctx=$(awm_context_for "subtask")     # Context package for sub-agent

# Token management
tokens=$(awm_token_estimate)         # Total memory token cost
awm_check_limits && echo "OK"        # Check if approaching limits
```

### V2 Enhanced Functions

```bash
# Initialize v2 subsystems (auto-detects storage backend)
awm_v2_init "claude-opus-4"

# Budget-aware operations
awm_checkpoint_v2 "key" "value" "high"   # Auto-tier based on size/importance
value=$(awm_get_v2 "key" "" "true")      # Tier traversal with promotion
ctx=$(awm_context_v2 10000 "false")      # Budget-limited context

# Recovery
awm_recovery_checkpoint                  # Save for crash recovery
awm_recovery_restore "$sid"              # Restore after restart
```

---

## Common Patterns

### 1. Session Lifecycle

**Basic Session**
```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Initialize session at task start
session_id=$(awm_init "code-audit-$(date +%Y%m%d)")

# Work with checkpoints
awm_checkpoint "current_phase" "scanning"
awm_checkpoint "files_processed" "0"

# Log progress
awm_log "audit" "Started scanning /src directory"

# Record discoveries
awm_discovery "Found deprecated API usage in auth.ts"

# Close when done
awm_close
```

**Session with Parent Inheritance**
```bash
# Main agent creates session
main_session=$(awm_init "research-project")
awm_checkpoint "topic" "distributed systems"
awm_discovery "Key paper: Lamport 1978 on timestamps"

# Sub-agent inherits context
sub_session=$(awm_init "literature-review" "$main_session")
# Sub-agent automatically receives:
# - Parent's discoveries (in inherited_discoveries.jsonl)
# - Parent's checkpoint data
```

**Resume After Interruption**
```bash
# Check for existing session
if awm_resume "a1b2c3d4e5f6"; then
    echo "Resumed session"
    current=$(awm_get "current_step")
    echo "Continuing from step: $current"
else
    echo "Starting fresh"
    awm_init "new-task"
fi
```

### 2. Key-Value Checkpoints

**Progress Tracking**
```bash
awm_init "batch-processor"

# Track multi-step process
for step in setup scan analyze report; do
    awm_checkpoint "current_step" "$step"
    awm_checkpoint "step_started" "$(date +%s)"

    # ... do work ...

    awm_checkpoint "step_completed" "$(date +%s)"
done

# Store final result
awm_checkpoint "total_time" "$elapsed"
awm_checkpoint "status" "complete"
```

**Configuration State**
```bash
# Store complex state as JSON
awm_checkpoint "config" '{"mode":"strict","threshold":0.8,"retries":3}'

# Store arrays via JSON
awm_checkpoint "processed_files" '["a.ts","b.ts","c.ts"]'

# Retrieve and parse
config=$(awm_get "config")
mode=$(echo "$config" | jq -r '.mode')
```

### 3. Discovery Logging

Discoveries are **never compressed** and are inherited by sub-agents.

```bash
# Security audit discoveries
awm_discovery "SQL injection vulnerability in /api/users endpoint"
awm_discovery "Missing rate limiting on authentication routes"
awm_discovery "Hardcoded API key in config.js line 42"

# Architecture insights
awm_discovery "Database schema lacks foreign key constraints"
awm_discovery "Event handlers are synchronous, causing latency spikes"

# User preferences (from conversation)
awm_discovery "User prefers PostgreSQL over MySQL for new projects"
awm_discovery "Deployment target is AWS EKS, not plain EC2"
```

### 4. Sub-Agent Context Inheritance

**Parent Agent**
```bash
main_session=$(awm_init "codebase-analysis")

# Gather context
awm_checkpoint "repo_root" "/home/user/project"
awm_checkpoint "language" "typescript"
awm_discovery "Uses monorepo structure with Turborepo"
awm_discovery "API uses OpenAPI 3.0 spec"

# Prepare context for sub-agent
ctx=$(awm_context_for "security-scan")
echo "Spawning security scanner with context: $ctx"

# Pass to sub-agent (e.g., via Task tool or environment)
export AWM_PARENT_CONTEXT="$ctx"
```

**Sub-Agent**
```bash
# Sub-agent receives context and creates child session
sub_session=$(awm_init "security-scan" "$PARENT_SESSION_ID")

# Access inherited data
inherited=$(awm_recent "inherited_discoveries" 50)
repo_root=$(awm_get "repo_root")

# Add own discoveries (will be available to parent via session read)
awm_discovery "Found 3 HIGH severity vulnerabilities"
awm_discovery "Outdated dependencies: lodash@4.17.15 has CVE-2021-23337"
```

### 5. Token Budget Management

**Initialize Budget**
```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/awm_stream.sh"

# Initialize for your model
awm_budget_init "claude-opus-4"

# Or with explicit limit
MAINFRAME_TOKEN_BUDGET=100000
awm_budget_init
```

**Check Before Reading**
```bash
# Estimate before committing
tokens=$(awm_estimate_read "summary")
if awm_budget_fits "$tokens"; then
    summary=$(awm_summary)
    awm_budget_use "summary" "$tokens"
else
    echo "Summary too large, using compressed version"
fi

# Check file fits
file_tokens=$(awm_estimate_file_tokens "/path/to/file.ts")
if awm_budget_fits "$file_tokens"; then
    cat "/path/to/file.ts"
    awm_budget_use "file" "$file_tokens"
fi
```

**Monitor Usage**
```bash
# Get current state
remaining=$(awm_budget_remaining)
summary=$(awm_budget_summary)

# Check pre-rotation threshold (75%)
max=$(awm_budget_max)
threshold=$((max * 75 / 100))
used=$(awm_budget_used)

if [[ $used -gt $threshold ]]; then
    echo "Approaching context limit, compressing memory"
    awm_compress
fi
```

### 6. Pre-Rotation Context Compression

When approaching context limits, compress and prepare for handoff.

```bash
# Monitor budget
if ! awm_check_limits; then
    echo "At limit - initiating pre-rotation"

    # Compress old logs
    awm_compress "$_AWM_SESSION_ID"

    # Export critical state
    summary=$(awm_summary)

    # Create handoff package
    handoff=$(awm_context_for "continuation")

    # Store handoff for next agent
    awm_checkpoint "handoff_package" "$handoff"
    awm_checkpoint "handoff_ready" "true"

    # Signal to orchestrator
    echo "HANDOFF_REQUIRED: Session $_AWM_SESSION_ID"
fi
```

---

## Real-World Examples

### Code Audit Agent with Incremental Checkpoints

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

audit_codebase() {
    local repo_path="$1"

    # Initialize session
    local sid
    sid=$(awm_init "code-audit-$(basename "$repo_path")")

    awm_checkpoint "repo_path" "$repo_path"
    awm_checkpoint "started_at" "$(date -Iseconds)"
    awm_checkpoint "status" "scanning"

    # Phase 1: File discovery
    local file_count=0
    while IFS= read -r -d '' file; do
        ((file_count++))
        awm_progress "scan" "$file_count/?"

        # Checkpoint every 100 files
        if [[ $((file_count % 100)) -eq 0 ]]; then
            awm_checkpoint "files_scanned" "$file_count"
            awm_checkpoint "last_file" "$file"
        fi

        # Analyze file
        local issues
        issues=$(analyze_file "$file")
        if [[ -n "$issues" ]]; then
            awm_log "issues" "[$file] $issues"
        fi

    done < <(find "$repo_path" -name "*.ts" -print0)

    awm_checkpoint "total_files" "$file_count"
    awm_checkpoint "status" "analyzing"

    # Phase 2: Pattern analysis
    awm_discovery "Total TypeScript files: $file_count"

    # Check for common issues
    if grep -r "eval(" "$repo_path" --include="*.ts" &>/dev/null; then
        awm_discovery "SECURITY: Found eval() usage - potential code injection"
    fi

    if grep -r "any" "$repo_path" --include="*.ts" | wc -l | xargs test 100 -lt; then
        awm_discovery "TYPE SAFETY: Excessive 'any' types (>100 occurrences)"
    fi

    # Final summary
    awm_checkpoint "status" "complete"
    awm_checkpoint "completed_at" "$(date -Iseconds)"

    # Export summary
    awm_export "audit-report.md"

    awm_close
    echo "Audit complete. Session: $sid"
}

audit_codebase "/home/user/project"
```

### Research Agent with Discovery Accumulation

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

research_topic() {
    local topic="$1"
    local max_depth="${2:-3}"

    local sid
    sid=$(awm_init "research-$topic")

    awm_checkpoint "topic" "$topic"
    awm_checkpoint "max_depth" "$max_depth"
    awm_checkpoint "sources_checked" "0"

    # Track explored sources
    declare -A visited
    local queue=("$topic")
    local depth=0

    while [[ ${#queue[@]} -gt 0 && $depth -lt $max_depth ]]; do
        local current="${queue[0]}"
        queue=("${queue[@]:1}")

        [[ -n "${visited[$current]}" ]] && continue
        visited[$current]=1

        awm_log "exploration" "Researching: $current (depth $depth)"

        # Simulate research (replace with actual API calls)
        local findings
        findings=$(research_source "$current")

        # Parse and store discoveries
        while IFS= read -r finding; do
            [[ -z "$finding" ]] && continue

            # High-importance findings go to discoveries
            if [[ "$finding" == *"KEY:"* ]]; then
                awm_discovery "${finding#KEY:}"
            else
                awm_log "findings" "$finding"
            fi

            # Extract related topics
            local related
            related=$(extract_related_topics "$finding")
            for r in $related; do
                queue+=("$r")
            done

        done <<< "$findings"

        # Update progress
        local sources_count="${#visited[@]}"
        awm_checkpoint "sources_checked" "$sources_count"
        awm_progress "research" "$sources_count/?"

        # Check budget
        if ! awm_check_limits; then
            awm_discovery "Research truncated at depth $depth due to context limits"
            break
        fi

        ((depth++))
    done

    # Generate summary
    local discoveries
    discoveries=$(awm_recent "discoveries" 50)
    awm_checkpoint "discovery_count" "$(echo "$discoveries" | jq 'length')"

    awm_close
    echo "Research complete. Discoveries: $(awm_recent discoveries 10 | jq -r '.[].discovery')"
}
```

### Multi-Step Task with Sub-Agent Delegation

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

orchestrate_build() {
    local project="$1"

    # Main orchestrator session
    local main_sid
    main_sid=$(awm_init "build-$project")

    awm_checkpoint "project" "$project"
    awm_checkpoint "phase" "planning"

    # Phase 1: Analysis (spawn sub-agent)
    awm_log "orchestration" "Spawning analysis agent"
    local analysis_ctx
    analysis_ctx=$(awm_context_for "analysis")

    # Sub-agent for analysis
    (
        local sub_sid
        sub_sid=$(awm_init "analysis" "$main_sid")

        # Perform analysis
        awm_discovery "Project uses React 18 with TypeScript"
        awm_discovery "Build tool: Vite 5.0"
        awm_checkpoint "dependencies_count" "47"

        awm_close
    )

    # Read sub-agent results
    awm_checkpoint "phase" "building"

    # Phase 2: Build (spawn another sub-agent)
    awm_log "orchestration" "Spawning build agent"

    (
        local build_sid
        build_sid=$(awm_init "build" "$main_sid")

        # Simulate build
        awm_progress "build" "0/5" "Starting"
        sleep 1
        awm_progress "build" "1/5" "Compiling TypeScript"
        sleep 1
        awm_progress "build" "2/5" "Bundling"
        sleep 1
        awm_progress "build" "3/5" "Optimizing"
        sleep 1
        awm_progress "build" "4/5" "Generating assets"
        sleep 1
        awm_progress "build" "5/5" "Complete"

        awm_checkpoint "build_status" "success"
        awm_checkpoint "bundle_size" "245KB"

        awm_close
    )

    # Phase 3: Deploy
    awm_checkpoint "phase" "deploying"
    awm_discovery "Build successful, bundle size: 245KB"

    # Finalize
    awm_checkpoint "phase" "complete"
    awm_checkpoint "completed_at" "$(date -Iseconds)"

    awm_close
}
```

### Long-Running Process with Context Streaming

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

process_large_dataset() {
    local input_file="$1"

    awm_v2_init "claude-opus-4"
    local sid
    sid=$(awm_init "data-processing")

    awm_checkpoint "input" "$input_file"
    awm_checkpoint "started" "$(date +%s)"

    local line_num=0
    local batch_size=1000
    local batch_results=""

    while IFS= read -r line; do
        ((line_num++))

        # Process line
        local result
        result=$(process_line "$line")
        batch_results+="$result"$'\n'

        # Batch checkpoint
        if [[ $((line_num % batch_size)) -eq 0 ]]; then
            awm_progress "process" "$line_num/?"
            awm_checkpoint "last_line" "$line_num"

            # Store batch results (large content goes to cold tier)
            awm_checkpoint_v2 "batch_$((line_num / batch_size))" "$batch_results" "normal"
            batch_results=""

            # Check memory limits
            local tokens
            tokens=$(awm_token_estimate)
            if [[ $tokens -gt 40000 ]]; then
                awm_compress "$sid"
            fi
        fi

    done < "$input_file"

    # Final batch
    if [[ -n "$batch_results" ]]; then
        awm_checkpoint_v2 "batch_final" "$batch_results" "normal"
    fi

    awm_checkpoint "total_lines" "$line_num"
    awm_checkpoint "status" "complete"
    awm_close
}
```

### Agent Handoff at Context Limits

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Agent 1: Works until near limit
agent_phase_1() {
    local task="$1"

    awm_v2_init
    local sid
    sid=$(awm_init "$task")

    while true; do
        # Do work...
        awm_log "work" "Processing..."
        awm_discovery "Found something important"

        # Check if handoff needed
        local remaining
        remaining=$(awm_budget_remaining)
        if [[ $remaining -lt 10000 ]]; then
            echo "Preparing handoff..."

            # Create handoff package
            awm_recovery_checkpoint
            local handoff
            handoff=$(awm_context_v2 8000 "false")

            awm_checkpoint "handoff_context" "$handoff"
            awm_checkpoint "handoff_ready" "true"
            awm_checkpoint "continue_from" "phase_2"

            echo "HANDOFF:$sid"
            return 0
        fi
    done
}

# Agent 2: Continues from handoff
agent_continue() {
    local parent_sid="$1"

    awm_v2_init

    # Create child session inheriting from parent
    local sid
    sid=$(awm_init "continuation" "$parent_sid")

    # Load handoff context
    local handoff
    handoff=$(awm_get "handoff_context")

    # Parse inherited discoveries
    local inherited
    inherited=$(awm_recent "inherited_discoveries" 100)
    echo "Inherited $(echo "$inherited" | jq 'length') discoveries"

    # Continue work
    local continue_from
    continue_from=$(awm_get "continue_from")
    awm_log "continuation" "Resuming from: $continue_from"

    # ... continue processing ...

    awm_close
}
```

---

## Best Practices

### When to Checkpoint

| Frequency | Use Case |
|-----------|----------|
| **Every iteration** | Critical loops where resume must be exact |
| **Every N items** | Batch processing (N=100 for small items, N=10 for large) |
| **Phase transitions** | Multi-step workflows (setup->scan->analyze->report) |
| **Before risky ops** | Before API calls, file writes, external commands |
| **After discoveries** | Immediately when finding something important |

### What to Store vs Skip

**Store (Checkpoint)**
- Current position/progress
- Configuration that may change
- Accumulated results (in batches)
- Error state for retry logic
- Timestamps for metrics

**Store (Discovery)**
- Security findings
- User preferences learned from conversation
- Architecture insights
- Key decisions made
- Constraints discovered

**Skip**
- Transient computation state
- Full file contents (use pointers)
- Verbose logs (use awm_log instead)
- Easily recomputable values

### Importance Tagging

```bash
# Critical: Never evicted, always in hot tier
awm_checkpoint_v2 "api_key_location" "vault://secrets/api" "critical"

# High: Prefer hot tier, demote only under pressure
awm_checkpoint_v2 "current_task" "security-audit" "high"

# Normal: Standard tiering (default)
awm_checkpoint_v2 "last_file" "/src/index.ts" "normal"

# Low: Evict first when space needed
awm_checkpoint_v2 "debug_info" "$verbose_output" "low"
```

### Session Naming Conventions

```bash
# Pattern: {type}-{identifier}-{timestamp}
awm_init "audit-repo-myapp-20260201"
awm_init "research-topic-caching-20260201"
awm_init "build-project-api-20260201"

# Sub-agents: inherit parent name + qualifier
awm_init "audit-repo-myapp-security" "$parent"
awm_init "audit-repo-myapp-deps" "$parent"
```

### Recovery from Interrupted Sessions

```bash
recover_session() {
    local task_type="$1"

    # List recent sessions of this type
    local sessions
    sessions=$(awm_list --status active | grep "$task_type")

    if [[ -n "$sessions" ]]; then
        # Find most recent
        local latest
        latest=$(echo "$sessions" | tail -1 | cut -f1)

        if awm_resume "$latest"; then
            echo "Resumed session: $latest"

            # Check where we left off
            local step
            step=$(awm_get "current_step" "start")
            echo "Continuing from: $step"

            return 0
        fi
    fi

    # No recoverable session
    return 1
}

# Usage
if ! recover_session "code-audit"; then
    echo "Starting fresh session"
    awm_init "code-audit-fresh"
fi
```

---

## Troubleshooting

### Common Issues

**Session not found after resume**
```bash
# Check if session exists
awm_list | grep "$session_id"

# Verify storage backend
awm_storage_status

# Check session directory directly
ls -la "$AWM_ROOT/sessions/$session_id"
```

**Memory usage growing too fast**
```bash
# Check current usage
awm_token_estimate

# Force compression
awm_compress

# Check tier distribution
awm_tier_stats
```

**Sub-agent not inheriting context**
```bash
# Ensure parent session ID is passed correctly
sub_sid=$(awm_init "subtask" "$PARENT_SESSION_ID")  # Not just "$parent"

# Verify inheritance worked
ls "$AWM_ROOT/sessions/$sub_sid/logs/inherited_discoveries.jsonl"
```

### Debug Mode

```bash
# Enable verbose logging
export MAINFRAME_DEBUG=1
export MAINFRAME_QUIET=0

# Run with tracing
bash -x your_script.sh

# Check storage backend health
awm_storage_health && echo "Healthy" || echo "Degraded"

# Inspect session state
awm_v2_status | jq .
```

### Performance Optimization

**Reduce file I/O**
```bash
# Batch multiple checkpoints
awm_checkpoint "state" "$(jq -n \
    --arg step "$step" \
    --arg count "$count" \
    --arg time "$(date +%s)" \
    '{step: $step, count: $count, time: $time}')"
```

**Use appropriate tiers**
```bash
# Large content: let v2 auto-tier
awm_checkpoint_v2 "large_result" "$big_json" "normal"

# Small critical: force hot tier
awm_hot_set "critical_flag" "true" "critical"
```

**Prefetch for known access patterns**
```bash
# Warm up cache before intensive reads
awm_tier_prefetch "config" "state" "checkpoint_1" "checkpoint_2"
```

---

## Integration Examples

### With orchestrate.sh

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/orchestrate.sh"

# Initialize orchestration with AWM backing
orch_init
orch_tmux_init

# Register team
orch_team_register "analysis" "Code Analysis Team" "scan,review"

# Spawn agents with AWM sessions
for i in 1 2 3; do
    agent_id=$(orch_agent_spawn "analysis")

    # Each agent gets its own AWM session
    _orch_tmux_exec "$agent_id" "awm_init 'agent-$agent_id-session'"
done

# Coordinate via AWM discoveries + orchestration pub/sub
orch_discovery_broadcast "analysis-agent-1" "Found critical issue in auth.ts"
```

### With agent.sh

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/agent.sh"

# Register file-based agent
agent_register "scanner" "security" "performance"

# Initialize AWM session
awm_init "scanner-session"

# Process work queue with AWM checkpointing
while true; do
    local item
    item=$(agent_work_pop "scan_queue") || break

    awm_checkpoint "current_item" "$item"

    # Process...
    local result
    result=$(scan_target "$item")

    awm_log "results" "$item: $result"

    if [[ "$result" == *"CRITICAL"* ]]; then
        awm_discovery "Critical finding in $item: $result"
        agent_broadcast '{"alert":"critical","source":"scanner"}'
    fi
done

awm_close
agent_unregister
```

### With context.sh

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/context.sh"

awm_init "context-aware-task"

# Initialize context budget
context_budget_init --max-tokens 100000 --reserve 5000

# Plan file reads
files=("/src/index.ts" "/src/api.ts" "/src/utils.ts")
plan=$(context_read_plan 50000 "${files[@]}")

# Read files that fit
for file in $(echo "$plan" | jq -r '.files[] | select(.included) | .path'); do
    local tokens
    tokens=$(context_file_tokens "$file")

    if context_budget_fits "$tokens"; then
        # Read and process
        content=$(cat "$file")
        context_budget_use "file:$file" "$tokens"

        # Store analysis in AWM
        awm_checkpoint "analyzed:$file" "$(date +%s)"
    else
        awm_log "skipped" "File too large: $file ($tokens tokens)"
    fi
done

# Check remaining budget before summary
remaining=$(context_budget_remaining)
awm_checkpoint "budget_remaining" "$remaining"

awm_close
```

---

## Function Reference Summary

### awm.sh (Core)

| Function | Purpose | Returns |
|----------|---------|---------|
| `awm_init` | Create new session | session_id |
| `awm_resume` | Resume existing session | 0/1 |
| `awm_close` | Mark session complete | 0 |
| `awm_checkpoint` | Store key-value | 0/1 |
| `awm_get` | Retrieve key | value |
| `awm_log` | Append to category | 0/1 |
| `awm_discovery` | Store high-priority insight | 0 |
| `awm_progress` | Track task progress | 0 |
| `awm_recent` | Get last N entries | JSON array |
| `awm_summary` | Compressed overview | JSON |
| `awm_context_for` | Sub-agent context | JSON |
| `awm_compress` | Compress old entries | 0 |
| `awm_export` | Export to markdown | filepath |
| `awm_token_estimate` | Estimate memory tokens | integer |
| `awm_check_limits` | Check if at limits | 0/1 |

### awm_stream.sh (Token Budget)

| Function | Purpose | Returns |
|----------|---------|---------|
| `awm_budget_init` | Initialize for model | max tokens |
| `awm_budget_remaining` | Available tokens | integer |
| `awm_budget_fits` | Check if content fits | 0/1 |
| `awm_budget_use` | Record usage | 0 |
| `awm_estimate_tokens` | Estimate string tokens | integer |
| `awm_estimate_file_tokens` | Estimate file tokens | integer |
| `awm_pointer_create` | Store large content | ptr://awm/hash |
| `awm_pointer_resolve` | Retrieve from pointer | content |
| `awm_chunk` | Split by semantic boundaries | JSON array |
| `awm_truncate` | Fit within token limit | truncated text |

### awm_tiers.sh (Tiered Storage)

| Function | Purpose | Returns |
|----------|---------|---------|
| `awm_tier_init` | Initialize tier system | 0 |
| `awm_tier_write` | Auto-tier by size/importance | 0 |
| `awm_tier_read` | Read with promotion | value |
| `awm_hot_set/get` | Direct hot tier access | 0/value |
| `awm_warm_set/get` | Direct warm tier access | 0/value |
| `awm_cold_set/get/search` | Direct cold tier access | 0/value/JSON |
| `awm_evict_hot/warm/cold` | Force eviction | count |
| `awm_tier_stats` | Tier statistics | JSON |

### awm_protocol.sh (Multi-Agent)

| Function | Purpose | Returns |
|----------|---------|---------|
| `awm_agent_register` | Register with capabilities | agent_id |
| `awm_send` | Send message to agent | msg_id |
| `awm_receive` | Blocking receive | JSON message |
| `awm_broadcast_discovery` | Share discovery | 0 |
| `awm_handoff_prepare` | Create handoff package | JSON |
| `awm_handoff_accept` | Accept and initialize | 0 |

---

*AWM Cookbook v1.0 - MAINFRAME Agent Working Memory*

# AWM MCP Bridge: Unified Context Management for Claude Code & Bash

> **Version**: 1.0 | **Status**: Implementation | **Author**: MAINFRAME Team

## Executive Summary

The AWM MCP Bridge solves the context limit problem that crashed 10 architect agents by providing:

1. **Unified Interface** - Same AWM functions work for Claude Code agents AND bash scripts
2. **Memory Pointers** - Large results stored externally, refs passed instead of content
3. **Pre-Rot Management** - Automatic eviction at 75% context capacity
4. **Agent Handoffs** - Sub-agents inherit parent discoveries without re-reading

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         CONSUMER LAYER                                   │
│                                                                          │
│  ┌──────────────────────┐        ┌──────────────────────┐               │
│  │   Claude Code Agent  │        │     Bash Script      │               │
│  │   ┌──────────────┐   │        │                      │               │
│  │   │ Task Agent   │   │        │  source common.sh    │               │
│  │   │ (separate    │   │        │  awm_init "task"     │               │
│  │   │  API session)│   │        │  awm_checkpoint ...  │               │
│  │   └──────────────┘   │        │                      │               │
│  │         │            │        │          │           │               │
│  │   MCP Tools Call     │        │   awm-mcp CLI call   │               │
│  └─────────┼────────────┘        └──────────┼───────────┘               │
└────────────┼────────────────────────────────┼───────────────────────────┘
             │                                │
             ▼                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      AWM MCP BRIDGE LAYER                                │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │                    AWM MCP Server (Python)                      │     │
│  │                    ~/.watson/mcp/awm-mcp/server.py             │     │
│  │                                                                 │     │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │     │
│  │  │  Session    │  │  Budget     │  │  Pre-Rot    │            │     │
│  │  │  Manager    │  │  Tracker    │  │  Monitor    │            │     │
│  │  └─────────────┘  └─────────────┘  └─────────────┘            │     │
│  │                                                                 │     │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │     │
│  │  │  Pointer    │  │  Handoff    │  │  Discovery  │            │     │
│  │  │  Store      │  │  Protocol   │  │  Index      │            │     │
│  │  └─────────────┘  └─────────────┘  └─────────────┘            │     │
│  │                                                                 │     │
│  └─────────────────────────────┬──────────────────────────────────┘     │
│                                │                                         │
│  ┌─────────────────────────────┼──────────────────────────────────┐     │
│  │                   awm-mcp CLI Wrapper                           │     │
│  │                   ~/.watson/bin/awm-mcp                         │     │
│  │                                                                 │     │
│  │  awm-mcp session init          awm-mcp pointer store           │     │
│  │  awm-mcp budget status         awm-mcp handoff prepare         │     │
│  │  awm-mcp tier write            awm-mcp discovery add           │     │
│  └─────────────────────────────┬──────────────────────────────────┘     │
└────────────────────────────────┼────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        AWM v2 CORE LAYER                                 │
│                                                                          │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐            │
│  │ awm_storage.sh │  │ awm_stream.sh  │  │ awm_tiers.sh   │            │
│  │   20 functions │  │   29 functions │  │   32 functions │            │
│  │                │  │                │  │                │            │
│  │ File/Redis/    │  │ Token budget   │  │ Hot/Warm/Cold  │            │
│  │ ChromaDB       │  │ Compression    │  │ Eviction       │            │
│  └────────────────┘  └────────────────┘  └────────────────┘            │
│                                                                          │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐            │
│  │awm_protocol.sh │  │    awm.sh      │  │  common.sh     │            │
│  │  28 functions  │  │  v1 compat     │  │  1,100+ funcs  │            │
│  │                │  │                │  │                │            │
│  │ Agent comms    │  │ Session mgmt   │  │ Core library   │            │
│  │ Handoffs       │  │ Checkpoints    │  │ Dependencies   │            │
│  └────────────────┘  └────────────────┘  └────────────────┘            │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## MCP Tool Specifications

### Category 1: Session & Budget Management

| Tool | Parameters | Returns | Description |
|------|------------|---------|-------------|
| `awm_session_init` | `task: str, model?: str, budget?: int` | `{session_id, max_tokens, used_tokens}` | Initialize session with budget |
| `awm_budget_status` | `session_id: str` | `{used, max, remaining, percent, prerot_warning}` | Get current budget |
| `awm_budget_use` | `session_id: str, tokens: int` | `{success, remaining}` | Record token usage |

### Category 2: Memory Pointers

| Tool | Parameters | Returns | Description |
|------|------------|---------|-------------|
| `awm_store_result` | `content: str, type?: str` | `{pointer: "ptr://awm/hash", tokens_saved}` | Store large result, get pointer |
| `awm_resolve_pointer` | `pointer: str` | `{content: str, type: str}` | Retrieve content from pointer |
| `awm_pointer_exists` | `pointer: str` | `{exists: bool}` | Check if pointer is valid |

### Category 3: Tiered Memory

| Tool | Parameters | Returns | Description |
|------|------------|---------|-------------|
| `awm_tier_write` | `key: str, value: str, importance?: str` | `{tier: str, key: str}` | Write to appropriate tier |
| `awm_tier_read` | `key: str, default?: str` | `{value: str, tier: str}` | Read with tier traversal |
| `awm_evict` | `target_tokens?: int` | `{evicted_count, freed_tokens}` | Force eviction to free space |
| `awm_search` | `query: str, limit?: int` | `[{key, content, score}]` | Semantic search cold tier |

### Category 4: Agent Handoff

| Tool | Parameters | Returns | Description |
|------|------------|---------|-------------|
| `awm_handoff_prepare` | `target_agent: str, max_tokens?: int` | `{handoff_package}` | Create handoff for sub-agent |
| `awm_handoff_accept` | `handoff_package: str` | `{session_id, discoveries, budget}` | Accept and init from handoff |
| `awm_handoff_complete` | `result: str` | `{sent_to_parent: bool}` | Report completion to parent |

### Category 5: Pre-Rot Management

| Tool | Parameters | Returns | Description |
|------|------------|---------|-------------|
| `awm_prerot_check` | `session_id: str` | `{triggered: bool, percent, action_needed}` | Check if at 75% threshold |
| `awm_prerot_mitigate` | `session_id: str` | `{evicted, compressed, new_percent}` | Auto-evict to reduce usage |

### Category 6: Discoveries & Checkpoints

| Tool | Parameters | Returns | Description |
|------|------------|---------|-------------|
| `awm_discovery` | `content: str, importance?: str` | `{id, stored_in_tier}` | Record a discovery |
| `awm_checkpoint` | `key: str, value: str` | `{success}` | Save checkpoint state |
| `awm_summary` | `max_tokens?: int` | `{summary: str, discoveries: [], checkpoints: []}` | Get session summary |

---

## Hook Integration Plan

### PostToolUse Hook: `~/.claude/hooks/awm-capture.sh`

Triggers after every tool call to:
1. Estimate tokens used by tool result
2. Update session budget
3. Auto-store large results (>5K tokens) as pointers
4. Check pre-rot threshold and warn

```bash
#!/usr/bin/env bash
# ~/.claude/hooks/awm-capture.sh
# PostToolUse hook for AWM context management

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Get tool result from stdin
result=$(cat)
tool_name="$1"
session_id="${AWM_SESSION_ID:-}"

# Skip if no active session
[[ -z "$session_id" ]] && echo "$result" && exit 0

# Estimate tokens
tokens=$(awm_estimate_tokens "$result")

# Auto-pointer for large results
if (( tokens > 5000 )); then
    pointer=$(awm-mcp pointer store --content "$result" --type "tool_result")
    # Return pointer instead of full content
    echo "{\"_awm_pointer\": \"$pointer\", \"preview\": \"${result:0:200}...\", \"tokens\": $tokens}"
else
    echo "$result"
fi

# Update budget and check pre-rot
awm-mcp budget use --session "$session_id" --tokens "$tokens"
prerot=$(awm-mcp prerot check --session "$session_id" | jq -r '.triggered')

if [[ "$prerot" == "true" ]]; then
    echo "[AWM] Pre-rot threshold reached (75%). Consider /compact" >&2
fi
```

### PreToolUse Hook: `~/.claude/hooks/awm-budget-check.sh`

Triggers before expensive operations to warn if budget is low:

```bash
#!/usr/bin/env bash
# ~/.claude/hooks/awm-budget-check.sh
# PreToolUse hook for budget warnings

tool_name="$1"
session_id="${AWM_SESSION_ID:-}"

[[ -z "$session_id" ]] && exit 0

# Check budget for file reads
if [[ "$tool_name" == "Read" || "$tool_name" == "Grep" ]]; then
    status=$(awm-mcp budget status --session "$session_id")
    percent=$(echo "$status" | jq -r '.percent')

    if (( percent > 70 )); then
        echo "[AWM] Budget at ${percent}% - large file reads may trigger pre-rot" >&2
    fi
fi
```

---

## Bash CLI Interface

### Command Structure

```bash
awm-mcp <category> <command> [options]

Categories:
  session   Session and budget management
  pointer   Memory pointer operations
  tier      Tiered memory operations
  handoff   Agent handoff protocol
  prerot    Pre-rot management
  discovery Discoveries and checkpoints
```

### Examples

```bash
# Initialize session
awm-mcp session init --task "research-moonshots" --model claude-opus-4

# Check budget
awm-mcp budget status --session abc123
# Output: {"used": 45000, "max": 200000, "remaining": 155000, "percent": 22.5}

# Store large result
awm-mcp pointer store --content "$(cat huge_file.json)"
# Output: {"pointer": "ptr://awm/a3f2c1...", "tokens_saved": 12500}

# Prepare handoff for sub-agent
awm-mcp handoff prepare --target "writer_agent" --max-tokens 50000

# Search discoveries
awm-mcp discovery search --query "authentication patterns"

# Force eviction
awm-mcp prerot mitigate --session abc123
```

---

## Implementation Order

### Week 1: Core Infrastructure

| Day | Task | Files |
|-----|------|-------|
| 1-2 | MCP Server scaffold | `~/.watson/mcp/awm-mcp/server.py` |
| 3 | Session manager | `server.py` (SessionManager class) |
| 4 | Budget tracker | `server.py` (BudgetTracker class) |
| 5 | CLI wrapper | `~/.watson/bin/awm-mcp` |

### Week 2: Memory Pointers & Tiers

| Day | Task | Files |
|-----|------|-------|
| 1-2 | Pointer store/resolve | `server.py` (PointerStore class) |
| 3-4 | Tier operations | Bridge to `awm_tiers.sh` |
| 5 | Semantic search | ChromaDB integration |

### Week 3: Agent Handoffs

| Day | Task | Files |
|-----|------|-------|
| 1-2 | Handoff prepare/accept | `server.py` (HandoffProtocol class) |
| 3-4 | Discovery inheritance | Session linking |
| 5 | Parent notification | Completion callbacks |

### Week 4: Pre-Rot & Polish

| Day | Task | Files |
|-----|------|-------|
| 1-2 | Pre-rot monitoring | Background checker |
| 3 | Hook integration | `~/.claude/hooks/awm-*.sh` |
| 4 | Testing | Unit + integration tests |
| 5 | Documentation | README, examples |

---

## Configuration

### Environment Variables

```bash
# AWM MCP Server
AWM_MCP_PORT=9876                    # Server port (if HTTP mode)
AWM_MCP_TRANSPORT=stdio              # stdio | http
AWM_MCP_LOG_LEVEL=info               # debug | info | warn | error

# Budget defaults
AWM_DEFAULT_MODEL=claude-opus-4      # Default model for budget calc
AWM_PREROT_THRESHOLD=0.75            # Trigger pre-rot at 75%
AWM_AUTOPOINTER_THRESHOLD=5000       # Auto-pointer above 5K tokens

# Storage backends
AWM_STORAGE_BACKEND=auto             # auto | file | redis | chromadb
AWM_STORAGE_DIR=~/.mainframe/awm     # Storage directory
```

### Claude Code MCP Registration

```json
// ~/.claude/mcp.json
{
  "servers": {
    "awm": {
      "command": "python3",
      "args": ["/home/gordontwatts/.watson/mcp/awm-mcp/server.py"],
      "env": {
        "AWM_MCP_TRANSPORT": "stdio",
        "MAINFRAME_ROOT": "/home/gordontwatts/.mainframe"
      }
    }
  }
}
```

---

## Error Handling

| Error | Recovery |
|-------|----------|
| Session not found | Auto-create new session |
| Pointer expired | Return error with suggestion to re-read |
| Budget exceeded | Force eviction, retry |
| Storage backend down | Fallback to file storage |
| Handoff target offline | Queue for later delivery |

---

## Metrics & Monitoring

The AWM MCP server tracks:

- Sessions created/active/completed
- Tokens used/saved by pointers
- Pre-rot triggers and mitigations
- Handoffs prepared/accepted/completed
- Storage backend latency
- Eviction frequency

Metrics exposed via `awm-mcp metrics` command.

---

*AWM MCP Bridge: Unified context management that prevents the context limit crashes that killed 10 architect agents.*

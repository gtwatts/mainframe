# Multi-Agent Team Orchestration

> Coordinate teams of Claude Code agents working in parallel TMUX windows.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## Overview

The orchestration system enables multiple AI agents to work together on complex tasks. Key capabilities:

- **Team Management**: Register teams with capabilities, dissolve when complete
- **Agent Lifecycle**: Spawn agents in TMUX windows, track status, terminate gracefully
- **Sub-Agent Delegation**: Hierarchical task delegation with limits
- **Task Distribution**: Priority-based assignment with load balancing
- **Health Monitoring**: Heartbeats, stale pruning, automatic recovery
- **Real-Time Coordination**: Redis pub/sub with file-based fallback
- **Message Protocol**: USOP v4 envelopes for inter-agent communication

---

## Architecture

```
+------------------+     +------------------+     +------------------+
|   Coordinator    |     |      Redis       |     |   State Files    |
|   (Main Agent)   |<--->|    Pub/Sub       |<--->|   (Fallback)     |
+--------+---------+     +--------+---------+     +------------------+
         |                        |
         v                        v
+--------+---------+     +--------+---------+
|  Team: research  |     |  Team: impl      |
+--------+---------+     +--------+---------+
         |                        |
    +----+----+              +----+----+
    |         |              |         |
+---v---+ +---v---+      +---v---+ +---v---+
|Agent 1| |Agent 2|      |Agent 3| |Agent 4|
| TMUX  | | TMUX  |      | TMUX  | | TMUX  |
+-------+ +-------+      +-------+ +-------+
    |
+---v---+
|Sub-1  |
+-------+
```

**Components**:

| Component | Description |
|-----------|-------------|
| Coordinator | Main orchestrator, manages teams and task distribution |
| Teams | Logical groups of agents with shared capabilities |
| Agents | Individual workers running in isolated TMUX windows |
| Sub-Agents | Child agents spawned for delegated subtasks |
| Redis | Real-time pub/sub for coordination (optional) |
| State Files | File-based fallback when Redis unavailable |

---

## Quick Start

### 1. Initialize Orchestration

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Initialize the orchestration subsystem
orch_init

# Create TMUX session for agent windows
orch_tmux_init "my-project"
```

### 2. Register a Team

```bash
# Register a team with capabilities
orch_team_register "research" "Research Team" "search,analyze,summarize"

# Check team was registered
orch_team_info "research"
# {"id":"research","name":"Research Team","capabilities":["search","analyze","summarize"],...}
```

### 3. Spawn Agents

```bash
# Spawn agents in the team (creates TMUX windows)
agent1=$(orch_agent_spawn "research")
agent2=$(orch_agent_spawn "research")

echo "Spawned: $agent1, $agent2"
# Spawned: research-agent-1, research-agent-2

# List all agents in team
orch_agent_list "research"
```

### 4. Assign Tasks

```bash
# Assign a task to the research team
task_id=$(orch_task_assign "research" '{"action":"search","query":"AI agents"}' 7)

echo "Task assigned: $task_id"
# Task assigned: task-a1b2c3d4e5f6
```

### 5. Complete Tasks

```bash
# Mark task as completed with result
orch_task_complete "$task_id" '{"results":["paper1","paper2"]}'

# Or mark as failed
orch_task_failed "$task_id" "Network timeout"
```

### 6. Cleanup

```bash
# Graceful shutdown
orch_shutdown
```

---

## Team Management

### Register Team

```bash
orch_team_register "team_id" "Human Name" "cap1,cap2,cap3"
```

| Parameter | Description |
|-----------|-------------|
| `team_id` | Unique identifier (lowercase, no spaces) |
| `name` | Human-readable name |
| `capabilities` | Comma-separated list of capabilities |

**Predefined Team IDs**:
- `ORCH_TEAM_DEFAULT` - General purpose
- `ORCH_TEAM_RESEARCH` - Research tasks
- `ORCH_TEAM_IMPLEMENTATION` - Coding tasks
- `ORCH_TEAM_REVIEW` - Code review
- `ORCH_TEAM_TESTING` - Testing tasks

### Team Functions

| Function | Description |
|----------|-------------|
| `orch_team_register` | Register a new team |
| `orch_team_info` | Get team metadata as JSON |
| `orch_team_list` | List all teams as JSON array |
| `orch_team_dissolve` | Dissolve team and terminate all agents |

---

## Agent Lifecycle

### Status Values

| Constant | Value | Description |
|----------|-------|-------------|
| `ORCH_STATUS_PENDING` | `pending` | Created but not started |
| `ORCH_STATUS_INITIALIZING` | `initializing` | Starting up |
| `ORCH_STATUS_READY` | `ready` | Available for tasks |
| `ORCH_STATUS_BUSY` | `busy` | Currently processing |
| `ORCH_STATUS_BLOCKED` | `blocked` | Waiting on dependency |
| `ORCH_STATUS_COMPLETED` | `completed` | Finished all work |
| `ORCH_STATUS_FAILED` | `failed` | Encountered error |
| `ORCH_STATUS_TERMINATED` | `terminated` | Shut down |

### Agent Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `orch_agent_spawn` | `orch_agent_spawn "team_id" ["caps"]` | Spawn agent with TMUX window |
| `orch_agent_terminate` | `orch_agent_terminate "agent_id" ["force"]` | Terminate agent |
| `orch_agent_info` | `orch_agent_info "agent_id"` | Get agent metadata JSON |
| `orch_agent_list` | `orch_agent_list ["team_id"]` | List agents (optionally by team) |

### Sub-Agent Delegation

```bash
# Parent agent spawns sub-agent for subtask
subagent=$(orch_subagent_spawn "$parent_id" "Analyze security config")

# List sub-agents
orch_subagent_list "$parent_id"

# Terminate sub-agent when done
orch_subagent_terminate "$subagent"
```

**Limits**:
- `ORCH_MAX_TEAMS=10`
- `ORCH_MAX_AGENTS_PER_TEAM=8`
- `ORCH_MAX_SUBAGENTS_PER_AGENT=4`

---

## Task Distribution

### Task Status Values

| Constant | Value | Description |
|----------|-------|-------------|
| `ORCH_TASK_QUEUED` | `queued` | Waiting for available agent |
| `ORCH_TASK_ASSIGNED` | `assigned` | Assigned to agent |
| `ORCH_TASK_RUNNING` | `running` | Being processed |
| `ORCH_TASK_COMPLETED` | `completed` | Successfully finished |
| `ORCH_TASK_FAILED` | `failed` | Failed with error |
| `ORCH_TASK_CANCELLED` | `cancelled` | Cancelled before completion |

### Task Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `orch_task_assign` | `orch_task_assign "team" "payload" [priority]` | Assign task to team |
| `orch_task_complete` | `orch_task_complete "task_id" ["result"]` | Mark completed |
| `orch_task_failed` | `orch_task_failed "task_id" "error"` | Mark failed |
| `orch_task_info` | `orch_task_info "task_id"` | Get task metadata |

**Priority**: 1-10 (default: 5), higher = more urgent

### Load Balancing

Tasks are assigned to the agent with:
1. Status = `READY`
2. Lowest current sub-agent count (least loaded)

If no agents available, task is queued for the team.

---

## Health Monitoring

### Heartbeat System

```bash
# Agent sends heartbeat (call periodically)
orch_agent_heartbeat "$agent_id"

# Check if agent is healthy
if orch_agent_healthy "$agent_id"; then
    echo "Agent is alive"
fi
```

### Stale Agent Pruning

```bash
# Prune agents that haven't sent heartbeat within timeout
pruned=$(orch_prune_stale)
echo "Pruned $pruned stale agents"
```

### Agent Recovery

```bash
# Recover failed agent: terminate, re-queue task, spawn replacement
new_agent=$(orch_agent_recover "$failed_agent_id")
echo "Replaced with: $new_agent"
```

**Configuration**:
- `ORCH_HEARTBEAT_INTERVAL=10` - Seconds between heartbeats
- `ORCH_AGENT_TIMEOUT=60` - Seconds before agent considered stale

---

## Message Protocol (USOP v4)

### Message Envelope

```json
{
  "version": "4.0",
  "message_id": "msg-a1b2c3d4e5f6",
  "type": "task",
  "from": "coordinator",
  "to": "research-agent-1",
  "timestamp": 1706745600,
  "payload": { ... }
}
```

### Message Types

| Constant | Value | Description |
|----------|-------|-------------|
| `ORCH_MSG_HEARTBEAT` | `heartbeat` | Health check ping |
| `ORCH_MSG_TASK` | `task` | Task assignment |
| `ORCH_MSG_RESULT` | `result` | Task result |
| `ORCH_MSG_STATUS` | `status` | Status update |
| `ORCH_MSG_CONTROL` | `control` | Control command |
| `ORCH_MSG_BROADCAST` | `broadcast` | Team-wide message |

### Sending Messages

```bash
# Create message envelope
msg=$(orch_message_create "task" "coordinator" "research-agent-1" '{"action":"search"}')

# Send to target
orch_message_send "research-agent-1" "$msg"

# Broadcast to all
orch_message_send "broadcast" "$msg"
```

### Discovery Broadcasting

```bash
# Share a discovery with all agents
orch_discovery_broadcast "$agent_id" "Found config uses OAuth2 with JWT refresh"
```

---

## Redis Pub/Sub Channels

| Channel Pattern | Purpose |
|----------------|---------|
| `mainframe:orch:team:{team_id}` | Team-wide broadcasts |
| `mainframe:orch:agent:{agent_id}` | Agent-specific messages |
| `mainframe:orch:control` | Control commands |
| `mainframe:orch:tasks[:{team_id}]` | Task assignments |
| `mainframe:orch:heartbeat` | Health pings |
| `mainframe:orch:discoveries` | Knowledge sharing |

### Redis Keys

| Key Pattern | Type | Purpose |
|-------------|------|---------|
| `mainframe:orch:state:agent:{id}` | String | Agent metadata JSON |
| `mainframe:orch:state:team:{id}` | String | Team metadata JSON |
| `mainframe:orch:queue:{team_id}` | List | Task queue |
| `mainframe:orch:task:{task_id}` | String | Task metadata JSON |
| `mainframe:orch:heartbeat:{id}` | String | Last heartbeat timestamp |
| `mainframe:orch:inbox:{agent_id}` | List | Persistent message inbox |

---

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ORCH_REDIS_HOST` | `localhost` | Redis server host |
| `ORCH_REDIS_PORT` | `6379` | Redis server port |
| `ORCH_REDIS_DB` | `0` | Redis database number |
| `ORCH_REDIS_PASSWORD` | (empty) | Redis auth password |
| `ORCH_REDIS_TIMEOUT` | `5` | Connection timeout seconds |
| `ORCH_STATE_DIR` | `~/.mainframe/orchestrate` | File-based state directory |
| `ORCH_TMUX_SESSION` | `mainframe-agents` | TMUX session name |
| `ORCH_HEARTBEAT_INTERVAL` | `10` | Heartbeat interval seconds |
| `ORCH_AGENT_TIMEOUT` | `60` | Agent timeout seconds |

---

## File-Based Fallback

When Redis is unavailable, the system automatically uses file-based storage:

```
~/.mainframe/orchestrate/
+-- channels/
|   +-- mainframe/orch/team/{team_id}    # Channel logs
+-- keys/
|   +-- mainframe/orch/state/agent/{id}  # Agent state
|   +-- mainframe/orch/state/team/{id}   # Team state
+-- lists/
|   +-- mainframe/orch/queue/{team_id}   # Task queues
+-- hashes/
|   +-- {key}/{field}                    # Hash fields
+-- logs/
```

---

## Complete Example

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Initialize
orch_init
orch_tmux_init "example-project"

# Create research team
orch_team_register "research" "Research Team" "search,analyze"

# Spawn 3 agents
for i in 1 2 3; do
    agent_id=$(orch_agent_spawn "research")
    echo "Spawned: $agent_id"
done

# Assign tasks
for query in "kubernetes security" "container isolation" "pod networking"; do
    task=$(orch_task_assign "research" "{\"query\":\"$query\"}" 5)
    echo "Assigned task: $task"
done

# Monitor health
while true; do
    status=$(orch_status)
    echo "Status: $status"

    # Prune stale agents
    orch_prune_stale

    sleep 30
done

# Cleanup when done
orch_shutdown
```

---

## TMUX Integration

### Session Structure

```
mainframe-agents (session)
+-- coordinator (window 0) - Main orchestrator
+-- research-agent-1 (window 1)
+-- research-agent-2 (window 2)
+-- impl-agent-1 (window 3)
...
```

### TMUX Functions

| Function | Description |
|----------|-------------|
| `orch_tmux_init` | Create TMUX session |
| `orch_tmux_cleanup` | Kill TMUX session |
| `_orch_tmux_create_window` | Create agent window |
| `_orch_tmux_exec` | Execute command in window |
| `_orch_tmux_kill_window` | Kill agent window |

### Attaching to Session

```bash
# View all agent windows
tmux attach -t mainframe-agents

# Detach: Ctrl+B, D
# Switch windows: Ctrl+B, N (next) or Ctrl+B, P (previous)
```

---

## Best Practices

### 1. Team Organization

- Group agents by capability (research, implementation, review)
- Use separate teams for parallel workstreams
- Dissolve teams when workflow completes

### 2. Task Distribution

- Set appropriate priorities (1-10)
- Include context in task payload
- Handle both completion and failure cases

### 3. Health Monitoring

- Call `orch_agent_heartbeat` every 10-30 seconds
- Run `orch_prune_stale` periodically
- Use `orch_agent_recover` for automatic failover

### 4. Resource Management

- Respect agent limits (8 per team, 4 sub-agents)
- Call `orch_shutdown` for clean termination
- Monitor Redis memory if high-volume

### 5. Error Handling

```bash
# Always handle task failures
if ! orch_task_complete "$task_id" "$result"; then
    orch_task_failed "$task_id" "Completion failed"
fi

# Check agent spawn success
agent=$(orch_agent_spawn "team") || {
    echo "Failed to spawn agent"
    exit 1
}
```

---

## Agent Teams Integration

Claude Code Agent Teams provides native team lifecycle, task assignment, and mailbox messaging. Mainframe supplements this with capabilities Agent Teams lacks: **persistent cross-agent memory** (AWM), **synchronization primitives** (barriers, locks), and **bash-level orchestration utilities** exposed via MCP.

### Coexistence Guide

| Feature | Agent Teams (Native) | Mainframe (Supplement) |
|---------|---------------------|----------------------|
| Task creation/assignment | TaskCreate/TaskUpdate | Do NOT wrap these |
| Agent-to-agent messages | Mailbox (SendMessage) | Do NOT replace |
| Persistent shared state | Not provided | AWM (`awm_checkpoint`, `awm_get`) |
| Barrier synchronization | Not provided | `agent_barrier` |
| Mutual exclusion locks | Not provided | `agent_lock`/`agent_unlock` |
| Key findings log | Not provided | `awm_discovery` |
| Session summaries | Not provided | `awm_summary` |

### Setup: Lead Agent

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
mainframe_bundle "agent_teams"

# Lead creates the shared AWM session
session_id=$(agent_teams_awm_init "project-task")
# Session ID written to ~/.claude/teams/{name}/.awm_session
```

### Setup: Teammate Agent

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
mainframe_bundle "agent_teams"

# Teammate joins the shared session
agent_teams_awm_join
# All AWM reads/writes now target the shared session
```

### Migration from TMUX Orchestration

If migrating from Mainframe's TMUX-based orchestration (`orch_agent_spawn`) to Agent Teams:

1. **Remove** TMUX agent lifecycle calls (`orch_agent_spawn`, `orch_agent_terminate`)
2. **Remove** Redis pub/sub messaging (`orch_msg_*`) - use Agent Teams mailbox instead
3. **Keep** AWM for shared state - works with both systems
4. **Keep** `agent_barrier`, `agent_lock`/`agent_unlock` - Agent Teams has no equivalent
5. **Add** `agent_teams_awm_init` (lead) and `agent_teams_awm_join` (teammates) for session rendezvous

### MCP Tools

Teammates can also call orchestration functions as MCP tools (registered via `mcp_register_orchestration_tools`): `awm_init`, `awm_resume`, `awm_checkpoint`, `awm_discovery`, `awm_get`, `awm_summary`, `agent_teams_active`, `agent_teams_awm_join`, `agent_barrier`, `agent_lock`, `agent_unlock`.

---

## See Also

- **[docs/reference/agent.md](reference/agent.md)** - Agent primitives (idempotent, atomic, diff)
- **[docs/reference/awm.md](reference/awm.md)** - Agent Working Memory
- **[ROADMAP.md](../ROADMAP.md)** - Feature roadmap

---

*MAINFRAME v7.2 - Multi-Agent Team Orchestration*

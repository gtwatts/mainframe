# Agent Functions

AI agent primitives: idempotent operations, atomic files, observability, diff/patch, context budget.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## Idempotent Operations (idempotent.sh)

Check-before-act operations that produce the same result regardless of how many times executed.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `ensure_dir` | `ensure_dir "path" [mode]` | `ensure_dir "/var/log/myapp" "0755"` | (creates dir if missing) |
| `ensure_file` | `ensure_file "path" ["content"] [mode]` | `ensure_file "/etc/myapp.conf" "key=value" "0644"` | (writes only if differs) |
| `ensure_line` | `ensure_line "file" "line" [marker]` | `ensure_line "/etc/hosts" "127.0.0.1 myapp.local"` | (appends if not present) |
| `ensure_symlink` | `ensure_symlink "target" "link" [force]` | `ensure_symlink "/opt/app-v2" "/opt/app-current"` | (creates/fixes symlink) |
| `ensure_command` | `ensure_command "cmd"` | `ensure_command "jq" \|\| exit 1` | (returns 0 if found) |
| `ensure_dirs` | `ensure_dirs "dir1" "dir2" ...` | `ensure_dirs "/var/log" "/var/run"` | (creates all) |
| `ensure_lines` | `ensure_lines "file" "line1" "line2"` | `ensure_lines "/etc/hosts" "127.0.0.1 a"` | (adds all) |
| `ensure_service` | `ensure_service "name" [check_cmd]` | `ensure_service "nginx"` | (starts if not running) |
| `ensure_package` | `ensure_package "name"` | `ensure_package "jq"` | (installs if missing) |

---

## Atomic File Operations (atomic.sh)

File write operations that prevent partial state.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `atomic_write` | `atomic_write "path" "content" [mode]` | `atomic_write "/etc/myapp.conf" "$config" "0644"` | (writes atomically) |
| `atomic_append` | `atomic_append "path" "content"` | `atomic_append "/var/log/app.log" "[$(date)] Event"` | (appends with flock) |
| `atomic_replace` | `atomic_replace "path" "content" [verify]` | `atomic_replace "/etc/nginx.conf" "$new_conf" "nginx -t"` | (backup+verify+replace) |
| `safe_remove` | `safe_remove "path"` | `safe_remove "/etc/old-config.conf"` | (moved to trash) |
| `safe_restore` | `safe_restore "filename"` | `safe_restore "old-config.conf"` | (restored from trash) |
| `file_checkpoint` | `file_checkpoint "path" "name"` | `file_checkpoint "/etc/nginx.conf" "before-ssl"` | (snapshot saved) |
| `file_rollback` | `file_rollback "path" "name"` | `file_rollback "/etc/nginx.conf" "before-ssl"` | (file restored) |
| `file_checkpoints` | `file_checkpoints ["path"]` | `file_checkpoints "/etc/nginx.conf"` | List checkpoints |
| `file_checkpoint_cleanup` | `file_checkpoint_cleanup [max_age_s]` | `file_checkpoint_cleanup 3600` | (removes old) |

---

## Structured Observability (observe.sh)

Trace, timing, and structured error reporting with JSON output.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `trace_start` | `tid=$(trace_start "name")` | `tid=$(trace_start "deploy_config")` | `trace_a1b2c3d4` |
| `trace_step` | `trace_step "$tid" "step" [status] [detail]` | `trace_step "$tid" "write_config" "ok" "3 keys"` | (JSON to stderr) |
| `trace_end` | `result=$(trace_end "$tid" [status])` | `result=$(trace_end "$tid" "success")` | JSON with duration |
| `observe_command` | `result=$(observe_command cmd [args])` | `result=$(observe_command ls -la /tmp)` | JSON with exit_code, duration |
| `stack_trace` | `trace=$(stack_trace)` | `trace=$(stack_trace)` | JSON stack |
| `observe_error` | `observe_error code "msg" [context]` | `observe_error 2 "invalid port"` | JSON error |
| `observe_time` | `t=$(observe_time)` | `start=$(observe_time)` | `1705312896.123456` |
| `observe_elapsed` | `elapsed=$(observe_elapsed "$start")` | `elapsed=$(observe_elapsed "$start")` | `2.345678` |

---

## Context Budget & Token Estimation (context.sh)

Helps AI agents estimate token costs and manage context budgets.

### Token Estimation

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `context_estimate_tokens` | `context_estimate_tokens "text"` | `context_estimate_tokens "Hello world"` | `3` |
| `context_file_tokens` | `context_file_tokens "path"` | `context_file_tokens "src/app.py"` | `285` |
| `context_command_tokens` | `context_command_tokens cmd [args]` | `context_command_tokens cat README.md` | `150` |

### Budget Management

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `context_budget_init` | `context_budget_init [--max-tokens N] [--reserve N]` | `context_budget_init --max-tokens 128000` | Creates budget |
| `context_budget_use` | `context_budget_use "label" tokens` | `context_budget_use "config.ts" 2500` | Tracks allocation |
| `context_budget_remaining` | `context_budget_remaining` | `context_budget_remaining` | `91500` |
| `context_budget_fits` | `context_budget_fits tokens` | `context_budget_fits 5000` | (returns 0=fits) |
| `context_budget_summary` | `context_budget_summary` | `context_budget_summary` | JSON summary |
| `context_budget_reset` | `context_budget_reset` | `context_budget_reset` | Clears state |

### Content Truncation

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `context_truncate` | `context_truncate "text" max_tokens [--strategy S]` | `context_truncate "$big" 1000 --strategy smart` | Truncated text |
| `context_truncate_file` | `context_truncate_file "path" max_tokens [--strategy S]` | `context_truncate_file "huge.log" 500` | Truncated content |

**Strategies**: `head` (default), `tail`, `middle`, `smart`

---

## Diff & Patch Operations (diff.sh)

Surgical file editing for AI agents.

### Search-and-Replace (Agent-Friendly)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `diff_replace` | `diff_replace "file" "old" "new" [--all] [--backup]` | `diff_replace "f.txt" "foo" "bar"` | (returns 0/1/2) |
| `diff_replace_string` | `diff_replace_string "text" "old" "new" [--all]` | `diff_replace_string "$s" "a" "b"` | Modified text |
| `diff_insert_after` | `diff_insert_after "file" "match" "new_text"` | `diff_insert_after "f.txt" "line" "new"` | (returns 0/1) |
| `diff_insert_before` | `diff_insert_before "file" "match" "new_text"` | `diff_insert_before "f.txt" "line" "new"` | (returns 0/1) |
| `diff_delete_lines` | `diff_delete_lines "file" "pattern" [--regex]` | `diff_delete_lines "f.txt" "TODO"` | (returns 0/1) |
| `diff_replace_range` | `diff_replace_range "file" start end "new"` | `diff_replace_range "f.txt" 2 4 "new"` | (returns 0/1) |

### Diff Generation

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `diff_strings` | `diff_strings "old" "new" [--context N]` | `diff_strings "hello" "world"` | Unified diff |
| `diff_files` | `diff_files "old_file" "new_file" [--context N]` | `diff_files "a.txt" "b.txt"` | Unified diff |
| `diff_preview` | `diff_preview "file" "new_content"` | `diff_preview "config.sh" "$new"` | Preview changes |

### Patch Application

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `diff_apply` | `diff_apply "file" "diff" [--backup] [--dry-run]` | `diff_apply "f.txt" "$patch"` | (returns 0/1/2) |
| `diff_can_apply` | `diff_can_apply "file" "diff"` | `diff_can_apply "f.txt" "$patch"` | (returns 0/1) |
| `diff_validate_unique` | `diff_validate_unique "file" "text"` | `diff_validate_unique "f.txt" "foo"` | Match count |

### Diff Analysis

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `diff_stats` | `diff_stats "diff"` | `diff_stats "$patch"` | JSON stats |
| `diff_changed_lines` | `diff_changed_lines "diff"` | `diff_changed_lines "$patch"` | +/- prefixed lines |

---

## Quick Patterns

### Idempotent Setup
```bash
ensure_dirs "/opt/myapp/bin" "/opt/myapp/config" "/opt/myapp/logs"
ensure_file "/opt/myapp/config/app.conf" "port=8080" "0644"
ensure_line "/etc/hosts" "127.0.0.1 myapp.local"
ensure_command "git" || { echo "git required"; exit 1; }
```

### Atomic File Operations
```bash
# Write config atomically
atomic_write "/etc/myapp/config.json" "$config" "0644"

# Replace with verification and auto-rollback
atomic_replace "/etc/nginx/nginx.conf" "$new_config" "nginx -t"

# Checkpoint before risky changes
file_checkpoint "/etc/ssh/sshd_config" "before-hardening"
```

### Observability
```bash
# Trace a multi-step operation
tid=$(trace_start "deploy_application")
trace_step "$tid" "pull_image" "ok" "nginx:latest"
trace_step "$tid" "start_new" "ok" "port 8080"
summary=$(trace_end "$tid" "success")
```

### Context Budget
```bash
context_budget_init --max-tokens 128000 --reserve 8000
for f in src/*.py; do
    tokens=$(context_file_tokens "$f")
    if context_budget_fits "$tokens"; then
        context_budget_use "$f" "$tokens"
        cat "$f"
    fi
done
```

### Surgical Edit
```bash
diff_replace "src/config.ts" \
    'const PORT = 3000;' \
    'const PORT = 8080;' --backup
```

---

## Multi-Agent Orchestration (orchestrate.sh)

Coordinate teams of AI agents working in parallel TMUX windows.

> **Full Documentation**: [docs/ORCHESTRATION.md](../ORCHESTRATION.md)

### Initialization

| Function | Signature | Description |
|----------|-----------|-------------|
| `orch_init` | `orch_init` | Initialize orchestration subsystem |
| `orch_status` | `orch_status` | Get system status as JSON |
| `orch_shutdown` | `orch_shutdown` | Graceful shutdown with cleanup |
| `orch_tmux_init` | `orch_tmux_init ["session"]` | Create TMUX session for agents |
| `orch_tmux_cleanup` | `orch_tmux_cleanup ["session"]` | Kill TMUX session |

### Team Management

| Function | Signature | Description |
|----------|-----------|-------------|
| `orch_team_register` | `orch_team_register "id" "name" "caps"` | Register team with capabilities |
| `orch_team_info` | `orch_team_info "team_id"` | Get team metadata JSON |
| `orch_team_list` | `orch_team_list` | List all teams as JSON array |
| `orch_team_dissolve` | `orch_team_dissolve "team_id"` | Dissolve team, terminate agents |

### Agent Lifecycle

| Function | Signature | Description |
|----------|-----------|-------------|
| `orch_agent_spawn` | `orch_agent_spawn "team_id" ["caps"]` | Spawn agent with TMUX window |
| `orch_agent_terminate` | `orch_agent_terminate "id" ["force"]` | Terminate agent |
| `orch_agent_info` | `orch_agent_info "agent_id"` | Get agent metadata JSON |
| `orch_agent_list` | `orch_agent_list ["team_id"]` | List agents (optional team filter) |

### Sub-Agent Delegation

| Function | Signature | Description |
|----------|-----------|-------------|
| `orch_subagent_spawn` | `orch_subagent_spawn "parent" "task"` | Spawn sub-agent for subtask |
| `orch_subagent_terminate` | `orch_subagent_terminate "id"` | Terminate sub-agent |
| `orch_subagent_list` | `orch_subagent_list "parent_id"` | List sub-agents JSON array |

### Task Distribution

| Function | Signature | Description |
|----------|-----------|-------------|
| `orch_task_assign` | `orch_task_assign "team" "payload" [priority]` | Assign task (priority 1-10) |
| `orch_task_complete` | `orch_task_complete "task_id" ["result"]` | Mark task completed |
| `orch_task_failed` | `orch_task_failed "task_id" "error"` | Mark task failed |
| `orch_task_info` | `orch_task_info "task_id"` | Get task metadata JSON |

### Health Monitoring

| Function | Signature | Description |
|----------|-----------|-------------|
| `orch_agent_heartbeat` | `orch_agent_heartbeat "agent_id"` | Update agent heartbeat |
| `orch_agent_healthy` | `orch_agent_healthy "agent_id"` | Check agent health (0=healthy) |
| `orch_prune_stale` | `orch_prune_stale [max_age]` | Remove stale agents |
| `orch_agent_recover` | `orch_agent_recover "agent_id"` | Recover failed agent |

### Message Protocol (USOP v4)

| Function | Signature | Description |
|----------|-----------|-------------|
| `orch_message_create` | `orch_message_create "type" "from" "to" "payload"` | Create message envelope |
| `orch_message_send` | `orch_message_send "target" "message"` | Send to agent/team/broadcast |
| `orch_discovery_broadcast` | `orch_discovery_broadcast "agent" "text"` | Share discovery team-wide |

### Status Constants

**Agent Status**: `ORCH_STATUS_PENDING`, `ORCH_STATUS_INITIALIZING`, `ORCH_STATUS_READY`, `ORCH_STATUS_BUSY`, `ORCH_STATUS_BLOCKED`, `ORCH_STATUS_COMPLETED`, `ORCH_STATUS_FAILED`, `ORCH_STATUS_TERMINATED`

**Task Status**: `ORCH_TASK_QUEUED`, `ORCH_TASK_ASSIGNED`, `ORCH_TASK_RUNNING`, `ORCH_TASK_COMPLETED`, `ORCH_TASK_FAILED`, `ORCH_TASK_CANCELLED`

**Team IDs**: `ORCH_TEAM_DEFAULT`, `ORCH_TEAM_RESEARCH`, `ORCH_TEAM_IMPLEMENTATION`, `ORCH_TEAM_REVIEW`, `ORCH_TEAM_TESTING`

### Orchestration Quick Start

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Initialize
orch_init
orch_tmux_init "my-project"

# Create team
orch_team_register "research" "Research Team" "search,analyze"

# Spawn agents
agent1=$(orch_agent_spawn "research")
agent2=$(orch_agent_spawn "research")

# Assign task
task=$(orch_task_assign "research" '{"query":"kubernetes security"}' 7)

# Complete task
orch_task_complete "$task" '{"results":["finding1","finding2"]}'

# Cleanup
orch_shutdown
```

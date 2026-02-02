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

## LLM Token Estimation & Cost Management (llm_tokens.sh)

Model-specific token counting, cost estimation, and text chunking for API usage.

### Token Counting

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `llm_count_tokens` | `llm_count_tokens "text" ["model"]` | `llm_count_tokens "Hello world" "gpt-4"` | `3` |
| `llm_count_tokens_file` | `llm_count_tokens_file "path" ["model"]` | `llm_count_tokens_file "src/app.py" "claude-3-opus"` | `285` |
| `llm_count_tokens_usop` | `llm_count_tokens_usop "text" ["model"]` | `llm_count_tokens_usop "Hello" "gpt-4"` | JSON envelope |
| `llm_clear_cache` | `llm_clear_cache` | `llm_clear_cache` | Clears token cache |

### Cost Estimation

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `llm_estimate_cost` | `llm_estimate_cost "text" ["model"] [--type T]` | `llm_estimate_cost "$text" "gpt-4-turbo" input` | JSON with costs |
| `llm_get_pricing` | `llm_get_pricing "model"` | `llm_get_pricing "claude-3-opus"` | JSON pricing info |
| `llm_list_models` | `llm_list_models` | `llm_list_models` | JSON array of models |

**Cost types**: `input` (default), `output`, `both`

### Truncation

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `llm_truncate_to_tokens` | `llm_truncate_to_tokens "text" max ["model"] [strategy]` | `llm_truncate_to_tokens "$big" 1000 "gpt-4" head` | Truncated text |
| `llm_truncate_usop` | `llm_truncate_usop "text" max ["model"]` | `llm_truncate_usop "$text" 500 "claude-3-sonnet"` | JSON envelope |

**Strategies**: `head` (default), `tail`, `middle`

### Chunk Splitting

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `llm_split_chunks` | `llm_split_chunks "text" size ["model"] [options]` | `llm_split_chunks "$doc" 1000 "gpt-4" --overlap 100` | JSON array of chunks |
| `llm_split_chunks_file` | `llm_split_chunks_file "path" size ["model"]` | `llm_split_chunks_file "big.md" 2000` | JSON array of chunks |

**Options**: `--overlap N` (token overlap), `--preserve-lines`

### Model Utilities

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `llm_context_window` | `llm_context_window "model"` | `llm_context_window "gpt-4-turbo"` | `128000` |
| `llm_fits_context` | `llm_fits_context "text" "model" [--reserve N]` | `llm_fits_context "$doc" "gpt-4" --reserve 1000` | (returns 0=fits) |
| `llm_model_family` | `llm_model_family "model"` | `llm_model_family "gpt-4-turbo-2024"` | `gpt-4` |

### Supported Models

**OpenAI**: gpt-4, gpt-4-turbo, gpt-4o, gpt-4o-mini, gpt-3.5-turbo, o1, o1-mini, o1-preview
**Anthropic**: claude-3-opus, claude-3-sonnet, claude-3-haiku, claude-3.5-sonnet, claude-3.5-haiku, claude-opus-4, claude-sonnet-4
**Google**: gemini-pro, gemini-1.5-pro, gemini-1.5-flash, gemini-2.0-flash
**Open/Local**: llama, llama-2, llama-3, llama-3.1, llama-3.2, mistral, mixtral, qwen, qwen-2, qwen-2.5, deepseek, deepseek-v3, phi-3, gemma, gemma-2

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

---

## LLM Function/Tool Calling (llm_functions.sh)

Tool registration, execution, and format conversion for OpenAI and Anthropic APIs.

### Tool Registration

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `llm_register_tool` | `llm_register_tool "name" "func" "schema"` | `llm_register_tool "weather" "get_weather" "$schema"` | (registers tool) |
| `llm_unregister_tool` | `llm_unregister_tool "name"` | `llm_unregister_tool "weather"` | (removes tool) |
| `llm_list_tools` | `llm_list_tools` | `llm_list_tools` | Tool names (one per line) |
| `llm_get_tool_schema` | `llm_get_tool_schema "name"` | `llm_get_tool_schema "weather"` | Schema JSON |
| `llm_tool_exists` | `llm_tool_exists "name"` | `llm_tool_exists "weather"` | (returns 0/1) |
| `llm_clear_tools` | `llm_clear_tools` | `llm_clear_tools` | (clears all tools) |
| `llm_tool_info` | `llm_tool_info "name"` | `llm_tool_info "weather"` | JSON with tool metadata |

### Tool Call Parsing

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `llm_detect_format` | `llm_detect_format "response"` | `llm_detect_format "$resp"` | `openai`, `anthropic`, or `unknown` |
| `llm_parse_tool_call` | `llm_parse_tool_call "response"` | `llm_parse_tool_call "$resp"` | Normalized JSON: `{id, name, arguments}` |
| `llm_parse_tool_calls` | `llm_parse_tool_calls "response"` | `llm_parse_tool_calls "$resp"` | JSON array of tool calls |

### Argument Validation

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `llm_validate_tool_args` | `llm_validate_tool_args "schema" "args"` | `llm_validate_tool_args "$schema" "$args"` | (returns 0=valid, 1=invalid) |
| `llm_validate_tool_args_errors` | `llm_validate_tool_args_errors "schema" "args"` | `llm_validate_tool_args_errors "$s" "$a"` | JSON array of errors |

### Tool Execution

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `llm_execute_tool` | `llm_execute_tool "name" "args"` | `llm_execute_tool "weather" '{"city":"NYC"}'` | Tool output |
| `llm_execute_tool_safe` | `llm_execute_tool_safe "name" "args"` | `llm_execute_tool_safe "weather" "$args"` | JSON with result, success, duration |

### Result Formatting

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `llm_format_tool_result` | `llm_format_tool_result "result" "id" [format]` | `llm_format_tool_result "72F" "call_123" "openai"` | OpenAI/Anthropic result envelope |
| `llm_format_tool_error` | `llm_format_tool_error "error" "id" [format]` | `llm_format_tool_error "Not found" "call_123"` | Error envelope |

### Format Export

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `llm_tools_to_openai` | `llm_tools_to_openai` | `llm_tools_to_openai` | JSON array (OpenAI function format) |
| `llm_tools_to_anthropic` | `llm_tools_to_anthropic` | `llm_tools_to_anthropic` | JSON array (Anthropic tool format) |
| `llm_tool_export` | `llm_tool_export "name" [format]` | `llm_tool_export "weather" "openai"` | Single tool definition |

### Complete Processing

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `llm_process_tool_call` | `llm_process_tool_call "response" [format]` | `llm_process_tool_call "$resp" "openai"` | Formatted result (parse+execute+format) |

### Tool Call Formats

**OpenAI Format** (input):
```json
{"tool_calls": [{"id": "call_abc", "type": "function", "function": {"name": "get_weather", "arguments": "{\"city\":\"NYC\"}"}}]}
```

**Anthropic Format** (input):
```json
{"content": [{"type": "tool_use", "id": "toolu_abc", "name": "get_weather", "input": {"city": "NYC"}}]}
```

**Normalized Format** (output from `llm_parse_tool_call`):
```json
{"id": "call_abc", "name": "get_weather", "arguments": {"city": "NYC"}}
```

### Tool Schema Format

```json
{
  "name": "get_weather",
  "description": "Get weather for a city",
  "parameters": {
    "type": "object",
    "properties": {
      "city": {"type": "string", "description": "City name"}
    },
    "required": ["city"]
  }
}
```

### Quick Start

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Define tool function
get_weather() {
    local args="$1"
    local city=$(jq -r '.city' <<< "$args")
    echo '{"temp": 72, "condition": "sunny"}'
}

# Register tool with schema
llm_register_tool "get_weather" "get_weather" '{
    "name": "get_weather",
    "description": "Get current weather for a city",
    "parameters": {
        "type": "object",
        "properties": {
            "city": {"type": "string", "description": "City name"}
        },
        "required": ["city"]
    }
}'

# Process OpenAI tool call
response='{"tool_calls":[{"id":"call_123","type":"function","function":{"name":"get_weather","arguments":"{\"city\":\"NYC\"}"}}]}'
result=$(llm_process_tool_call "$response" "openai")
echo "$result"
# {"role":"tool","tool_call_id":"call_123","content":"{\"temp\":72,\"condition\":\"sunny\"}"}

# Export tools for API
tools=$(llm_tools_to_openai)
```

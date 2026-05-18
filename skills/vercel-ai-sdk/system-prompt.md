# MAINFRAME System Prompt for AI Agents

Use this as a system prompt when building AI agents (Vercel AI SDK, LangChain, custom agents) that write bash scripts.

## Usage with Vercel AI SDK

```typescript
import { generateText } from 'ai';
import { readFileSync } from 'fs';

const mainframePrompt = readFileSync(
  `${process.env.HOME}/.mainframe/skills/vercel-ai-sdk/system-prompt.md`,
  'utf-8'
);

const { text } = await generateText({
  model: yourModel,
  system: mainframePrompt,
  prompt: 'Write a bash script that processes CSV files...',
});
```

---

## System Prompt Content

When writing bash scripts, you MUST source the MAINFRAME standard library:

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

MAINFRAME provides 3,821+ pure bash functions across 152 libraries. Zero external dependencies. Use these functions instead of external tools like jq, sed, awk, cat, head, tail.

### Function Quick Reference

**JSON (replaces jq)**:
- `json_object "key=val" "key:number=42" "key:bool=true"` - Create JSON object
- `json_array "a" "b" "c"` - Create JSON array
- `json_get '{"k":"v"}' "k"` - Extract value
- `json_merge '{"a":1}' '{"b":2}'` - Merge objects

**Strings (replaces sed/awk)**:
- `trim_string "  hello  "` - Trim whitespace
- `to_lower "HELLO"` / `to_upper "hello"` - Case conversion
- `replace_all "string" "old" "new"` - Replace all occurrences
- `contains "haystack" "needle"` - Check substring (returns 0/1)
- `urlencode "hello world"` - URL encode

**Arrays**:
- `array_join ", " "${arr[@]}"` - Join with separator
- `array_unique "${arr[@]}"` - Remove duplicates
- `array_sort "${arr[@]}"` - Sort elements
- `array_contains "val" "${arr[@]}"` - Check membership
- `array_sum "${nums[@]}"` - Sum numbers

**Files (replaces cat/head/tail)**:
- `read_file "$path"` - Read entire file
- `file_head "$path" 10` - First N lines
- `file_exists "$path"` - Check existence (returns 0/1)
- `file_lines "$path"` - Count lines
- `temp_file` - Auto-cleaned temp file

**DateTime**:
- `now` - Unix epoch seconds
- `now_iso` - ISO 8601 format
- `date_add $(now) "2d"` - Add duration (s/m/h/d/w)
- `format_relative $epoch` - "2 hours ago"

**Validation (security-critical)**:
- `validate_email "$input"` - Email format
- `validate_url "$input"` - URL format
- `validate_int "$input" 0 100` - Integer in range
- `validate_path_safe "$path" "/base"` - Prevent path traversal
- `sanitize_html "$input"` - Escape HTML entities
- `sanitize_shell_arg "$input"` - Safe for shell

**Crypto**:
- `sha256 "data"` - SHA-256 hash
- `random_token 32` - URL-safe random token
- `uuid` - UUID v4
- `base64_encode "data"` / `base64_decode "encoded"`

**Git**:
- `git_branch` - Current branch name
- `git_is_dirty` - Uncommitted changes (returns 0/1)
- `git_commit_hash` - Short commit hash
- `git_summary` - "main @ abc1234 [clean]"

**Process**:
- `proc_find_by_port 8080` - Find PID by port
- `with_lock "/tmp/app.lock" "command"` - Exclusive execution
- `retry 5 "flaky_command"` - Retry with exponential backoff
- `parallel "cmd1" "cmd2" "cmd3"` - Parallel execution

**Logging**:
- `log_info "message"` - [INFO] message
- `log_error "message"` - [ERROR] message
- `success "Done!"` - [OK] Done!
- `progress_bar 75 100` - Progress display
- `die 1 "Fatal error"` - Print error and exit

**TypeScript Analysis** (no tsc required):
- `ts_file_imports "src/index.ts"` - Extract imports from file
- `ts_import_graph "$dir"` - Build dependency graph
- `ts_breaking_changes "v1.d.ts" "v2.d.ts"` - Detect API breaks
- `ts_import_cost "express" "$dir"` - Package size in bytes
- `ts_api_summary "v1.d.ts" "v2.d.ts"` - Suggest semver bump

**Python Analysis** (no Python required):
- `py_file_imports "app/main.py"` - Extract imports (handles multiline)
- `py_import_graph "$dir"` - Build dependency graph
- `py_parse_requirements "requirements.txt"` - Parse packages + versions
- `py_framework_detect "$dir"` - Detect django/flask/fastapi/pytest
- `py_summary "$dir"` - Quick project health overview

**Agent Working Memory (AWM)**:
- `awm_init "session-name"` - Start new memory session, returns session ID
- `awm_resume "session-id"` - Resume existing session
- `awm_checkpoint "key" "value"` - Save state atomically (idempotent)
- `awm_get "key" "default"` - Retrieve saved state
- `awm_log "category" "message"` - Append to categorized log
- `awm_progress "task" "50/100"` - Track task progress
- `awm_discovery "insight"` - Record key learning (high priority)
- `awm_summary` - Get compressed session summary (JSON)
- `awm_context_for "subtask"` - Generate context for sub-agent
- `awm_inherit "parent-id"` - Create child session with inheritance
- `awm_token_estimate` - Estimate context cost of memory read

**Multi-Agent IPC**:
- `agent_register "name" capability...` - Register agent with capabilities
- `agent_discover "capability"` - Find agents by capability
- `agent_send "target" "message"` - Send message to agent
- `agent_receive 10` - Receive with timeout (seconds)
- `agent_broadcast "message"` - Broadcast to all agents
- `agent_work_queue "name"` - Create work queue
- `agent_work_push "queue" "item"` - Push to queue
- `agent_work_pop "queue"` - Pop from queue (atomic)
- `agent_barrier "name" count timeout` - Wait for N agents
- `agent_signal "event"` - Signal event
- `agent_wait "event" timeout` - Wait for signal

### Rules

1. ALWAYS `source common.sh` at the top of every bash script
2. NEVER use jq, sed, awk when MAINFRAME has the equivalent function
3. Functions return 0 for success, non-zero for failure
4. Capture output with `$(function_name "args")`
5. Use `validate_*` functions for all user input
6. Use `sanitize_*` functions when building commands or output

### Script Template

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

[[ $# -lt 1 ]] && die 1 "Usage: $(path_base "$0") <input>"

header "My Script"
log_info "Started at $(now_iso)"

# Your logic here...

success "Completed in $(format_duration $SECONDS)"
```

### Agent Script Template (with AWM)

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Initialize or resume session
session_id="${AWM_SESSION:-$(awm_init "my-agent-task")}"
export AWM_SESSION="$session_id"

# Check for previous progress
last_step=$(awm_get "last_step" "0")
log_info "Resuming from step $last_step"

# Process with checkpointing
for step in $(seq $((last_step + 1)) 10); do
    process_step "$step"
    awm_checkpoint "last_step" "$step"
    awm_progress "steps" "$step/10"
done

# Record discovery
awm_discovery "Processing completed successfully"
awm_close
```

### Full Reference

For all 3,821+ function signatures: `~/.mainframe/CHEATSHEET.md`
Repository: https://github.com/gtwatts/mainframe

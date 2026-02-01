# Agent Working Memory (AWM)

Persistent external memory for AI agents with finite context windows.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## Session Lifecycle

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `awm_init` | `awm_init [--parent ID] [--namespace NS]` | `sid=$(awm_init)` | Session ID (uuid) |
| `awm_resume` | `awm_resume "session_id"` | `awm_resume "$sid"` | 0=success, 1=not found |
| `awm_close` | `awm_close [--export PATH]` | `awm_close --export report.md` | Marks session complete |
| `awm_namespace` | `awm_namespace "name"` | `awm_namespace "security-scan"` | Sets isolation namespace |

---

## Core Write Functions

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `awm_checkpoint` | `awm_checkpoint "key" "value"` | `awm_checkpoint "api_url" "https://..."` | 0=success |
| `awm_log` | `awm_log "category" "message"` | `awm_log "error" "Connection failed"` | 0=success |
| `awm_progress` | `awm_progress "task" current total` | `awm_progress "files" 5 10` | 0=success |
| `awm_discovery` | `awm_discovery "insight"` | `awm_discovery "Auth uses JWT tokens"` | 0=success (high priority) |

---

## Core Read Functions

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `awm_get` | `awm_get "key" [default]` | `awm_get "api_url" "http://localhost"` | Value or default |
| `awm_recent` | `awm_recent "category" [n]` | `awm_recent "error" 5` | Last N log entries (JSON) |
| `awm_summary` | `awm_summary [--tokens N]` | `awm_summary --tokens 2000` | Compressed summary JSON |
| `awm_context_for` | `awm_context_for "task" [--tokens N]` | `awm_context_for "debug" --tokens 1000` | Task-relevant context |

---

## Memory Management

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `awm_compress` | `awm_compress [--keep N]` | `awm_compress --keep 50` | Archives old entries |
| `awm_export` | `awm_export "path.md"` | `awm_export "session-report.md"` | Exports to Markdown |
| `awm_inherit` | `awm_inherit "parent_id"` | `child=$(awm_init --parent "$parent")` | Creates child session |
| `awm_check_limits` | `awm_check_limits` | `awm_check_limits && echo "OK"` | 0=OK, 1=at limits |

---

## Token Budget Estimation

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `awm_token_estimate` | `awm_token_estimate` | `tokens=$(awm_token_estimate)` | Estimated total tokens |
| `awm_estimate_read` | `awm_estimate_read "operation" [args]` | `awm_estimate_read "recent" "error" 10` | Tokens for operation |

---

## Session Management

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `awm_list` | `awm_list [--active\|--completed\|--all]` | `awm_list --active` | JSON array of sessions |
| `awm_cleanup` | `awm_cleanup [--older-than DAYS]` | `awm_cleanup --older-than 7` | Removes old sessions |

---

## Quick Patterns

### Initialize Session
```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
session_id=$(awm_init)
```

### Record Discoveries
```bash
# Never compressed, inherited by children
awm_discovery "Database uses PostgreSQL 15"
awm_discovery "Auth flow: OAuth2 with JWT refresh tokens"
```

### Checkpoint State
```bash
# Atomic writes
awm_checkpoint "target_file" "/src/auth/login.ts"
awm_checkpoint "error_count" "3"
```

### Log Events
```bash
awm_log "info" "Starting security scan"
awm_log "error" "Failed to parse config: $error"
awm_log "debug" "Checking file: $file"
```

### Track Progress
```bash
awm_progress "scan" 45 100  # 45% complete
```

### Read State
```bash
target=$(awm_get "target_file")
recent_errors=$(awm_recent "error" 5)
```

### Get Summary
```bash
summary=$(awm_summary --tokens 2000)
```

### Spawn Sub-Agent
```bash
# Child inherits discoveries and checkpoints from parent
child_id=$(awm_init --parent "$session_id" --namespace "security")
awm_namespace "security"
```

### Export Session
```bash
awm_close --export "session-report.md"
```

---

## File Format

Sessions stored in `~/.mainframe/awm/sessions/{session_id}/`:

```
{session_id}/
|-- manifest.json       # Session metadata
|-- logs/
|   |-- info.jsonl      # Category-based logs
|   |-- error.jsonl
|   |-- debug.jsonl
|-- data/
|   |-- target_file     # Key-value checkpoint files
|   |-- error_count
|-- discoveries.jsonl   # High-priority insights
|-- checkpoints/
    |-- {name}.tar.gz   # Named snapshots
```

---

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `AWM_ROOT` | `~/.mainframe/awm` | Storage location |
| `AWM_MAX_LOG_ENTRIES` | `100` | Auto-compress threshold |
| `AWM_MAX_FILE_SIZE` | `1048576` (1MB) | Max file size limit |
| `AWM_CHARS_PER_TOKEN` | `4` | Token estimation ratio |

# Healing Functions

Self-healing error recovery system - intelligent error diagnosis, classification, and automated recovery for shell commands. Learns from AMMA history and provides confidence-scored suggestions.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## Command Wrapping (heal.sh)

| Function | Signature | Description |
|----------|-----------|-------------|
| `heal_wrap` | `heal_wrap "command" [--retries N] [--backoff linear\|exponential] [--delay N] [--max-delay N]` | Execute command with automatic retry and backoff. On final failure, diagnoses error and classifies it. |
| `heal_execute` | `heal_execute "command" [--on_error "recovery_cmd"] [--capture-output]` | Execute with error recovery callback. Runs recovery command on failure. |

---

## Error Diagnosis

| Function | Signature | Description |
|----------|-----------|-------------|
| `heal_diagnose` | `heal_diagnose "error_output" [--context "cwd,env,command"]` | Full diagnosis: classify error, determine root cause, gather context, suggest fixes. |
| `heal_classify_error` | `heal_classify_error "error_text"` | Classify error into category: permission, notfound, network, resource, syntax, logic, unknown. |
| `heal_root_cause` | `heal_root_cause "error_text"` | Determine root cause from error text with specific file/path details when available. |

---

## Recovery Suggestions

| Function | Signature | Description |
|----------|-----------|-------------|
| `heal_suggest` | `heal_suggest "error_text" [--format text\|json]` | Generate confidence-scored fix suggestions based on error category, custom strategies, and history. |
| `heal_auto_fix` | `heal_auto_fix "error_text" [--dry-run] [--no-dry-run]` | Automatically apply the highest-confidence fix. Uses whitelist-based safe execution. |
| `heal_confirm_and_fix` | `heal_confirm_and_fix "error_text"` | Interactive: display suggestions and prompt user to select a fix to apply. |

---

## Strategy Management

| Function | Signature | Description |
|----------|-----------|-------------|
| `heal_register_strategy` | `heal_register_strategy "regex_pattern" "fix_command"` | Register a custom error pattern and its fix command. |
| `heal_list_strategies` | `heal_list_strategies [text\|json]` | List all registered healing strategies. |

---

## Advanced

| Function | Signature | Description |
|----------|-----------|-------------|
| `verify_and_heal` | `verify_and_heal "command"` | Execute a command; on failure, diagnose and provide healing suggestions. |
| `heal_stats` | `heal_stats [text\|json]` | Show healing statistics: diagnoses performed, successful fixes, strategies registered. |

---

## Error Categories

| Category | Matches |
|----------|---------|
| `permission` | Permission denied, EACCES, EPERM, operation not permitted |
| `notfound` | No such file, command not found, ENOENT |
| `network` | Connection refused, EPIPE, timeout, could not resolve |
| `resource` | Cannot allocate memory, no space left, too many open files |
| `syntax` | Syntax error, unexpected token, unclosed, parse error |
| `logic` | Wrong directory, not a git repository, missing prerequisite |
| `unknown` | Unrecognized error patterns |

---

## Usage Examples

```bash
# Wrap with auto-retry
heal_wrap --retries 3 --backoff exponential -- "curl -f https://api.example.com/data"

# Execute with recovery
heal_execute "docker-compose up" --on_error "docker-compose down && docker-compose up"

# Diagnose an error
heal_diagnose "Permission denied: /var/log/app.log" --context "cwd,env"
# {"category":"permission","root_cause":"Permission denied on /var/log/app.log (owned by root)","suggestions":[...]}

# Auto-fix (dry run by default)
heal_auto_fix "bash: jq: command not found"
# {"dry_run":true,"suggestion":"Install jq using system package manager","confidence":0.80}

# Register custom strategy
heal_register_strategy "ECONNREFUSED.*:5432" "sudo systemctl start postgresql"

# Check stats
heal_stats json
# {"diagnoses":15,"successful_fixes":12,"strategies_registered":4}
```

---

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `HEAL_HISTORY_LIMIT` | `100` | Max history entries to search for learning |
| `HEAL_AUTO_DRYRUN` | `1` | Dry-run mode enabled by default for auto-fix |
| `HEAL_MAX_SUGGESTIONS` | `5` | Maximum suggestions to generate |
| `HEAL_STATE_DIR` | `/tmp/mainframe_heal` | State directory for healing data |

## Safe Execution

Auto-fix uses a whitelist-based execution engine. Only commands in the whitelist (mkdir, chmod, pip, npm, git, docker, etc.) can be auto-executed. Commands with shell metacharacters (`;`, `|`, `&`, backticks) are blocked. Destructive subcommands (e.g., `pip uninstall`, `docker rm`) are also blocked.

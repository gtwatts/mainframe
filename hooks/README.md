# Basher Hook System

The Basher hook system enables scripts to integrate seamlessly with AI coding assistants like Claude Code, Cursor, and aider.

## Hook Types

### 1. Pre-Command Hooks (`hooks/pre-command/`)

Execute **before** a command runs. Useful for:
- Validating preconditions
- Setting up environment
- Logging command start

```bash
# Example: hooks/pre-command/log-start.sh
#!/usr/bin/env bash
echo "[$(date)] Starting: $BASHER_COMMAND" >> ~/.basher/command.log
```

### 2. Post-Command Hooks (`hooks/post-command/`)

Execute **after** a command completes. Useful for:
- Cleanup operations
- Logging results
- Triggering follow-up actions

```bash
# Example: hooks/post-command/notify-done.sh
#!/usr/bin/env bash
[[ $BASHER_EXIT_CODE -eq 0 ]] && notify-send "Basher" "Command completed: $BASHER_COMMAND"
```

### 3. File Change Hooks (`hooks/file-change/`)

Triggered when specific files or patterns change. Useful for:
- Auto-formatting
- Validation
- Triggering rebuilds

```bash
# Example: hooks/file-change/format-json.sh
#!/usr/bin/env bash
# Triggered for *.json files
[[ "$BASHER_CHANGED_FILE" == *.json ]] && jq . "$BASHER_CHANGED_FILE" > "$BASHER_CHANGED_FILE.tmp" && mv "$BASHER_CHANGED_FILE.tmp" "$BASHER_CHANGED_FILE"
```

### 4. Context Hooks (`hooks/context/`)

Inject context into agent prompts. Useful for:
- Adding project-specific context
- Injecting environment information
- Customizing agent behavior

```bash
# Example: hooks/context/project-info.sh
#!/usr/bin/env bash
# Output becomes part of agent context
cat << EOF
## Project Context
- Name: $(basename "$PWD")
- Language: $(detect-language)
- Framework: $(detect-framework)
EOF
```

## Hook Configuration

### hooks.conf

```ini
[hooks]
enabled = true
timeout = 30

[pre-command]
enabled = true
scripts = log-start.sh,validate-env.sh

[post-command]
enabled = true
scripts = log-end.sh,cleanup.sh

[file-change]
enabled = true
patterns = *.json,*.yaml,*.md

[context]
enabled = true
scripts = project-info.sh,env-info.sh
```

## Hook Environment Variables

| Variable | Description |
|----------|-------------|
| `BASHER_HOOK_TYPE` | Current hook type (pre-command, post-command, etc.) |
| `BASHER_COMMAND` | The command being executed |
| `BASHER_EXIT_CODE` | Exit code of the command (post-command only) |
| `BASHER_CHANGED_FILE` | Path to changed file (file-change only) |
| `BASHER_CHANGED_TYPE` | Type of change: create, modify, delete |
| `BASHER_CONTEXT` | Accumulated context (context hooks) |

## Chaining Hooks

Hooks execute in alphabetical order by filename. Use numeric prefixes for explicit ordering:

```
hooks/pre-command/
├── 00-validate.sh      # Runs first
├── 10-setup-env.sh     # Runs second
└── 99-log-start.sh     # Runs last
```

### Chain Control

- Return exit code `0` to continue chain
- Return exit code `1` to abort chain (pre-command only)
- Return exit code `2` to skip remaining hooks but continue command

## Claude Code Integration

### settings.json

```json
{
  "hooks": {
    "preCommand": "~/.basher/hooks/pre-command.sh",
    "postCommand": "~/.basher/hooks/post-command.sh",
    "contextProvider": "~/.basher/hooks/context-provider.sh"
  }
}
```

### Hook Dispatcher

The main dispatcher script routes to appropriate hooks:

```bash
#!/usr/bin/env bash
# hooks/dispatcher.sh

source "$BASHER_ROOT/lib/common.sh"

hook_type="${1:?Hook type required}"
shift

case "$hook_type" in
    pre-command)  run_hooks "$BASHER_ROOT/hooks/pre-command" "$@" ;;
    post-command) run_hooks "$BASHER_ROOT/hooks/post-command" "$@" ;;
    file-change)  run_hooks "$BASHER_ROOT/hooks/file-change" "$@" ;;
    context)      run_hooks "$BASHER_ROOT/hooks/context" "$@" ;;
    *)            die "Unknown hook type: $hook_type" ;;
esac
```

## Creating Custom Hooks

### Template

```bash
#!/usr/bin/env bash
# =============================================================================
# Hook: my-hook.sh
# Type: pre-command
# Description: Brief description of what this hook does
# =============================================================================

set -euo pipefail
source "${BASHER_ROOT:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")}/lib/common.sh"

# Hook logic here
log_debug "Executing my-hook for: $BASHER_COMMAND"

# Return codes:
# 0 - Continue execution
# 1 - Abort command (pre-command only)
# 2 - Skip remaining hooks
exit 0
```

## Best Practices

1. **Keep hooks fast** - Hooks run synchronously; slow hooks degrade UX
2. **Handle errors gracefully** - Don't let hook failures break the command
3. **Log appropriately** - Use `log_debug` for verbose output
4. **Be idempotent** - Hooks may run multiple times
5. **Respect `--no-hooks`** - Check for opt-out flag

## Debugging Hooks

```bash
# Enable debug mode
export BASHER_HOOK_DEBUG=1

# Run a specific hook manually
BASHER_COMMAND="git commit" ./hooks/pre-command/my-hook.sh

# Check hook execution order
basher hooks list --verbose
```

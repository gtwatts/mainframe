# MAINFRAME Integration for Clawdbot

[Clawdbot](https://github.com/clawdbot/clawdbot) is a self-hosted personal AI assistant that operates across 13+ messaging platforms (WhatsApp, Telegram, Slack, Discord, Signal, etc.).

## Why MAINFRAME + Clawdbot?

Clawdbot executes bash commands on your host machine (main sessions) or in Docker sandboxes (group sessions). MAINFRAME v6.0 provides:

- **Safe execution** - Validation before action, guardrails against damage
- **Structured output** - JSON responses the AI can parse reliably
- **Token efficiency** - 71% fewer tokens per bash task
- **Zero dependencies** - Pure bash, works anywhere
- **Agent memory** - AWM for persistent state across sessions
- **Multi-agent IPC** - Coordinate multiple agent instances

## Quick Setup

### 1. Install MAINFRAME

```bash
git clone https://github.com/gtwatts/mainframe.git ~/.mainframe
echo 'export MAINFRAME_ROOT="$HOME/.mainframe"' >> ~/.bashrc
source ~/.bashrc
```

### 2. Add Preamble to Clawdbot

Edit `~/.clawdbot/clawdbot.json` and add the MAINFRAME preamble to your agent configuration:

```json
{
  "agents": {
    "defaults": {
      "preamble": "When writing bash scripts, ALWAYS source MAINFRAME first:\n\nsource \"${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh\"\n\nMAINFRAME v6.0 provides 4,000+ pure bash functions across 117 libraries. Use these instead of jq/sed/awk:\n- json_object, json_array, json_get (replaces jq)\n- trim_string, to_lower, replace_all (replaces sed/awk)\n- validate_email, validate_path_safe, sanitize_shell_arg (security)\n- log_info, log_error, success, failure (logging)\n- file_head, file_tail, read_file (replaces cat/head/tail)\n- sha256, random_token, uuid (crypto)\n- git_branch, git_is_dirty (git helpers)\n- date_add, format_relative (datetime)\n- http_get, http_post (pure bash HTTP)\n- awm_init, awm_checkpoint, awm_get (Agent Working Memory)\n- agent_register, agent_send, agent_receive (multi-agent IPC)\n\nFull reference: ~/.mainframe/CHEATSHEET.md"
    }
  }
}
```

### 3. Verify Integration

Send a message to your Clawdbot asking it to write a bash script. It should automatically source MAINFRAME.

## Advanced: Full System Prompt

For comprehensive MAINFRAME integration, use the full preamble from `preamble.md`:

```bash
# Copy the preamble file
cat ~/.mainframe/skills/clawdbot/preamble.md
```

Then paste the content into your `clawdbot.json` preamble field.

## How It Works

1. **Main sessions** (direct DMs) run bash on your host - MAINFRAME is available via `MAINFRAME_ROOT`
2. **Group sessions** (if sandboxed) run in Docker - mount MAINFRAME in the container:

```json
{
  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "non-main",
        "mounts": [
          "~/.mainframe:/root/.mainframe:ro"
        ],
        "env": {
          "MAINFRAME_ROOT": "/root/.mainframe"
        }
      }
    }
  }
}
```

## Function Highlights for Chat Assistants

### JSON Without jq

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Create structured responses
json_object "status=success" "message=Task completed" "count:number=42"
# {"status":"success","message":"Task completed","count":42}
```

### Safe Input Handling

```bash
# Validate user-provided paths (prevents traversal attacks)
validate_path_safe "$user_input" "/allowed/directory" || {
    echo "Invalid path"
    exit 1
}

# Sanitize for shell execution
safe_arg=$(sanitize_shell_arg "$user_input")
```

### Process Monitoring

```bash
# Find what's using a port
proc_find_by_port 8080

# Check if service is running
docker_container_running "nginx" && echo "Nginx is up"
```

### File Operations

```bash
# Read without cat
content=$(read_file "$path")

# First 10 lines without head
file_head "$path" 10

# Check existence
file_exists "$path" && echo "Found it"
```

### Agent Working Memory (AWM) - NEW in v6.0

```bash
# Persist state across chat sessions
sid=$(awm_init "clawdbot-task")
awm_checkpoint "user_preference" "dark_mode"
awm_discovery "User prefers concise responses"

# Later, resume and recall
awm_resume "$sid"
pref=$(awm_get "user_preference")
```

### Multi-Agent Coordination - NEW in v6.0

```bash
# Register as an agent with capabilities
agent_register "clawdbot-main" "chat" "file-ops"

# Coordinate with other agents
agent_send "worker-agent" '{"task":"process_file","path":"/tmp/data.csv"}'
result=$(agent_receive 30)
```

## Docker Sandbox Configuration

If you run group chats in Docker sandboxes, ensure MAINFRAME is available:

```json
{
  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "non-main",
        "image": "bash:5.2",
        "mounts": [
          "~/.mainframe:/opt/mainframe:ro"
        ],
        "env": {
          "MAINFRAME_ROOT": "/opt/mainframe"
        }
      }
    }
  }
}
```

## Troubleshooting

### Functions not found

Ensure MAINFRAME is sourced at the start of scripts:

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

### MAINFRAME_ROOT not set

Add to your shell profile:

```bash
export MAINFRAME_ROOT="$HOME/.mainframe"
```

### Docker sandbox can't find MAINFRAME

Mount the directory and set the environment variable in your sandbox config.

## Resources

- [Clawdbot Documentation](https://github.com/clawdbot/clawdbot)
- [MAINFRAME Cheatsheet](https://github.com/gtwatts/mainframe/blob/main/CHEATSHEET.md)
- [MAINFRAME Wiki](https://github.com/gtwatts/mainframe/wiki)

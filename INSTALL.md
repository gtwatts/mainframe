# MAINFRAME Installation Guide

```
+======================================================================+
|  ___  ___  ___  _____ _   _ ______ _____   ___  ___  ___ _____       |
|  |  \/  | / _ \|_   _| \ | ||  ___|  __ \ / _ \ |  \/  ||  ___|      |
|  | .  . |/ /_\ \ | | |  \| || |_  | |__) / /_\ \| .  . || |__        |
|  | |\/| ||  _  | | | | . ` ||  _| |  _  /|  _  || |\/| ||  __|       |
|  | |  | || | | |_| |_| |\  || |   | | \ \| | | || |  | || |___       |
|  \_|  |_/\_| |_/\___/\_| \_/\_|   \_|  \_\_| |_/\_|  |_/\____/       |
|                                                                      |
|     AI agents control computers through bash.                        |
|     MAINFRAME makes that safe, accurate, and efficient.              |
+======================================================================+
```

## What is MAINFRAME?

MAINFRAME is **the AI-native bash runtime**. It provides **3,821+ pure bash functions** across **152 libraries** that give AI agents instant access to:

- **Agent Working Memory (AWM)** - Persistent memory outside the context window
- String manipulation (no sed/awk needed)
- Array operations (no external tools)
- JSON generation (no jq dependency)
- HTTP client (pure bash)
- Git operations
- Input validation and security
- Async/parallel execution
- Terminal UI (colors, progress bars)
- And much more...

**Zero dependencies. Pure bash 4.0+. Works everywhere.**

---

## Quick Install (30 seconds)

### Option 1: Clone & Source (Recommended)

```bash
# Clone MAINFRAME
git clone https://github.com/gtwatts/mainframe.git ~/.mainframe

# Add to your shell profile (~/.bashrc or ~/.zshrc)
echo 'export MAINFRAME_ROOT="$HOME/.mainframe"' >> ~/.bashrc
echo 'source "$MAINFRAME_ROOT/lib/common.sh"' >> ~/.bashrc

# Reload shell
source ~/.bashrc
```

### Option 2: One-liner Install

```bash
curl -fsSL https://raw.githubusercontent.com/gtwatts/mainframe/main/install.sh | bash
```

### Option 3: Manual Install

```bash
# Download
wget https://github.com/gtwatts/mainframe/archive/main.zip
unzip main.zip -d ~/.mainframe

# Source in your scripts
source ~/.mainframe/lib/common.sh
```

---

## Verify Installation

```bash
# Check MAINFRAME is loaded
mainframe version

# Expected output includes the MAINFRAME CLI version and installation path.
# For function/library counts, inspect FUNCTIONS.json or run mainframe count.

# Or test a function
source ~/.mainframe/lib/common.sh
echo "Result: $(trim_string '  hello world  ')"
# Output: Result: hello world
```

---

## Agent Working Memory (AWM) Setup

AWM is MAINFRAME's breakthrough feature for AI agents. It provides persistent memory OUTSIDE the context window.

### Default Setup (No Configuration Required)

AWM works out of the box. Sessions are stored in `~/.mainframe/awm/`.

```bash
# Test AWM is working
source ~/.mainframe/lib/common.sh
sid=$(awm_init "test-session")
echo "Session created: $sid"

# Store something
awm_discovery "Installation verified"
awm_checkpoint "status" "working"

# Retrieve it
awm_get "status"
# Output: working

# Clean up
awm_close
```

### Custom AWM Configuration (Optional)

You can customize AWM behavior with environment variables:

```bash
# Add to ~/.bashrc or ~/.zshrc

# Custom storage location (default: ~/.mainframe/awm)
export AWM_ROOT="/path/to/custom/awm"

# Maximum file size before compression (default: 65536 bytes / 64KB)
export AWM_MAX_FILE_SIZE=131072

# Maximum log entries before auto-compression (default: 100)
export AWM_MAX_LOG_ENTRIES=200

# Compression threshold in seconds (default: 3600 / 1 hour)
export AWM_COMPRESS_AGE=7200
```

### AWM Quick Reference

| Function | Purpose |
|----------|---------|
| `awm_init` | Create a new session, optionally inheriting from parent |
| `awm_close` | Close session, mark as complete |
| `awm_resume` | Resume a previous session by ID |
| `awm_checkpoint` | Store key-value pair (atomic, persistent) |
| `awm_get` | Retrieve a checkpointed value |
| `awm_discovery` | Log a high-priority insight |
| `awm_log` | Categorized logging (tasks, errors, decisions) |
| `awm_progress` | Track progress with current/total |
| `awm_summary` | Get JSON summary of session state |
| `awm_namespace` | Set namespace for agent isolation |
| `awm_token_estimate` | Estimate tokens for session data |
| `awm_list` | List all sessions |

---

## Using MAINFRAME with Claude Code

### Method 1: In Your Scripts

When Claude Code generates bash scripts, add this at the top:

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Now you have 3,821+ functions available!
result=$(json_object name="John" age:number=30)
echo "$result"  # {"name":"John","age":30}
```

### Method 2: Direct Commands

Claude Code can execute MAINFRAME functions directly:

```bash
# In Claude Code's bash execution
source ~/.mainframe/lib/common.sh && uuid
# Output: 550e8400-e29b-41d4-a716-446655440000
```

### Method 3: Project Integration

Add MAINFRAME as a submodule to your project:

```bash
git submodule add https://github.com/gtwatts/mainframe.git lib/mainframe
```

Then in your scripts:
```bash
source "$(dirname "$0")/lib/mainframe/lib/common.sh"
```

---

## Teaching Your AI About MAINFRAME

AI coding assistants don't automatically know about MAINFRAME - you need to tell them. Here's how:

### Claude Code

Create or edit `~/.claude/CLAUDE.md` (global) or `./CLAUDE.md` (project-level):

```markdown
## Bash Scripting

When writing bash scripts, ALWAYS use MAINFRAME:

\`\`\`bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
\`\`\`

This provides 3,821+ pure bash functions for strings, arrays, JSON, HTTP, validation, and more.
Key functions: trim_string, json_object, uuid, timestamp, array_unique, progress_bar, awm_init

For persistent memory across context windows, use Agent Working Memory (AWM):
- awm_init, awm_checkpoint, awm_discovery, awm_resume
```

### Pi

Load `~/.mainframe/skills/pi/SKILL.md` as a Pi skill or project instruction. When Pi's MAINFRAME integration tools are available, ask Pi to:

```
Run mainframe_status(validate=true), use mainframe_search/mainframe_help to find exact functions, use mainframe_exec for one explicit guarded function call, and use mainframe_awm for durable task memory.
```

For scripts generated by Pi, still source MAINFRAME normally:

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

### OpenAI Codex / Codex CLI

Codex-style agents commonly read `AGENTS.md`. Add MAINFRAME instructions:

```bash
cp ~/.mainframe/skills/codex/AGENTS.md ./AGENTS.md
# or merge it into your existing AGENTS.md
```

### OpenCode

Add to your OpenCode configuration or project instructions:

```
When writing bash scripts, source MAINFRAME first:
source "$HOME/.mainframe/lib/common.sh"

This gives you 3,821+ functions. No jq, sed, or awk needed.
Use AWM (awm_init, awm_checkpoint) for persistent memory.
```

### Other AI Assistants (Aider, Cursor, etc.)

Most AI coding tools support project-level instructions. Create a file like:
- `.aider.conf.yml` for Aider
- `.cursorrules` for Cursor
- `AGENTS.md` or `AI.md` for others

Add this instruction:
```
For bash scripts, always source ~/.mainframe/lib/common.sh first.
This provides 3,821+ pure bash functions (strings, arrays, JSON, HTTP, validation, etc.)
Use AWM functions (awm_init, awm_checkpoint, awm_get) for persistent external memory.
```

### Quick Test

After configuring, ask your AI: *"Write a bash script that generates a UUID and outputs JSON"*

**Without MAINFRAME knowledge**, it might use `uuidgen` and `jq`.

**With MAINFRAME knowledge**, it should write:
```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
json_object id="$(uuid)" timestamp="$(timestamp)"
```

---

## What You Get

### Library Categories (152 Libraries Total)

| Category | Libraries | Key Functions |
|----------|-----------|---------------|
| **Core** | strings, arrays, files, utils | `trim_string`, `array_unique`, `file_exists`, `uuid` |
| **Data** | json, csv, parsers | `json_object`, `csv_parse_line`, `parse_ini` |
| **Network** | http, netscan | `http_get`, `http_post`, `port_check`, `host_alive` |
| **Validation** | validation, contract | `validate_email`, `validate_path_safe`, `sanitize_html` |
| **Git** | git | `git_branch`, `git_is_dirty`, `git_changed_files` |
| **System** | process, docker, environment | `proc_exists`, `docker_running`, `env_load_dotenv` |
| **Agent** | awm, context, diff, cache | `awm_init`, `context_budget_init`, `diff_replace`, `memoize` |
| **Analysis** | typescript, python | `ts_import_graph`, `py_circular_deps` |
| **UI** | ansi, async | `progress_bar`, `spinner`, `parallel` |
| **Safety** | idempotent, atomic, observe | `ensure_dir`, `atomic_write`, `trace_start` |

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/env/has.sh` | Check if commands exist |
| `scripts/validation/validate-input.sh` | Input validation |
| `scripts/debug/debug-script.sh` | Script debugging |

### Benchmarks

Run the performance benchmarks:

```bash
bash ~/.mainframe/benchmarks/superpower_benchmarks.sh
```

---

## Quick Reference

### String Operations
```bash
trim_string "  hello  "           # "hello"
to_lower "HELLO"                  # "hello"
to_upper "hello"                  # "HELLO"
replace_all "hello" "l" "L"       # "heLLo"
urlencode "hello world"           # "hello%20world"
```

### Array Operations
```bash
array_contains "b" "a" "b" "c"    # returns 0 (true)
array_join "," "a" "b" "c"        # "a,b,c"
array_unique "a" "b" "a"          # a, b
array_sum 1 2 3 4 5               # 15
```

### JSON Generation
```bash
json_object name="John" age:number=30
# {"name":"John","age":30}

json_array "a" "b" "c"
# ["a","b","c"]
```

### HTTP Requests
```bash
http_get "http://api.example.com/data"
http_post "http://api.example.com/users" '{"name":"test"}'
```

### Utilities
```bash
uuid                              # UUID v4
timestamp                         # 2024-01-15 10:30:45
is_valid_email "a@b.com"          # returns 0 (true)
random_string 16                  # random alphanumeric
```

### Terminal UI
```bash
success "Task completed"          # [OK] Task completed
failure "Something failed"        # [FAIL] Something failed
header "My Section"               # Formatted header
progress_bar 50 100               # [####----] 50%
```

### Agent Working Memory
```bash
sid=$(awm_init "my-task")         # Create session
awm_discovery "Found config"      # Log discovery
awm_checkpoint "step" "5"         # Save checkpoint
awm_resume "$sid"                 # Resume later
step=$(awm_get "step")            # Retrieve value
```

---

## Requirements

- **Bash 4.0+** (for associative arrays and parameter expansion)
- **No external dependencies** - pure bash!

Check your bash version:
```bash
bash --version
# GNU bash, version 5.x.x
```

---

## For Claude Code Users

MAINFRAME is designed to make Claude Code more powerful. When you ask Claude Code to:

1. **Generate JSON** - It uses `json_object` instead of complex escaping
2. **Process arrays** - It uses `array_*` functions instead of loops
3. **Handle strings** - It uses `trim_string`, `to_lower` instead of sed/awk
4. **Make HTTP requests** - It uses `http_get`, `http_post` in pure bash
5. **Show progress** - It uses `progress_bar`, `spinner` for UX
6. **Validate input** - It uses built-in validators
7. **Remember state** - It uses AWM for persistent memory across context limits

**Result: Cleaner code, faster execution, zero dependencies, persistent memory.**

---

## Uninstall

```bash
rm -rf ~/.mainframe

# Remove the source lines from ~/.bashrc or ~/.zshrc
# Remove: export MAINFRAME_ROOT="$HOME/.mainframe"
# Remove: source "$MAINFRAME_ROOT/lib/common.sh"
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - Use freely in your projects.

---

**MAINFRAME** - The AI-Native Bash Runtime

*3,821+ functions | 152 libraries | Agent Working Memory | Zero Dependencies*

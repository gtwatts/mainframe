# MAINFRAME

**The AI-Native Bash Runtime**

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

<div align="center">

**AI agents control computers through bash. MAINFRAME makes that safe, accurate, and efficient.**

**4,000+ Pure Bash Functions** | **Zero Dependencies** | **Agent Working Memory** | **First-Time Correctness**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Tests](https://img.shields.io/github/actions/workflow/status/gtwatts/mainframe/test.yml?label=tests)](https://github.com/gtwatts/mainframe/actions)
[![Bash 4.0+](https://img.shields.io/badge/bash-4.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Pure Bash](https://img.shields.io/badge/dependencies-zero-blue.svg)](https://github.com/gtwatts/mainframe)
[![GitHub stars](https://img.shields.io/github/stars/gtwatts/mainframe?style=social)](https://github.com/gtwatts/mainframe)

</div>

---

## Quick Install

**Get MAINFRAME running in 30 seconds:**

```bash
# 1. Clone MAINFRAME
git clone https://github.com/gtwatts/mainframe.git ~/.mainframe

# 2. Add to your shell profile
echo 'export MAINFRAME_ROOT="$HOME/.mainframe"' >> ~/.bashrc
echo 'source "$MAINFRAME_ROOT/lib/common.sh"' >> ~/.bashrc

# 3. Reload and verify
source ~/.bashrc
mainframe version
```

**Expected output:**
```
MAINFRAME v6.0
4,000+ functions | 117 libraries | Pure Bash
```

**That's it.** Your AI agents now have a safe, efficient bash runtime with persistent memory.

For detailed installation options, see [INSTALL.md](INSTALL.md).

---

## What is MAINFRAME?

**MAINFRAME is the runtime layer between AI agents and the operating system.**

AI agents - whether Claude Code, GPT-4o, Gemini, Cursor, or custom LLM-powered tools - interact with computers primarily through bash. They write shell commands to navigate filesystems, manipulate data, manage processes, and orchestrate system operations.

The problem: **AI agents have finite context windows and bash is hostile territory.**

- Context windows fill up, losing critical state
- Commands fail silently or with cryptic errors
- Output is unstructured and unparseable
- Security vulnerabilities are one typo away
- Sub-agents can't inherit learnings from parent agents

**MAINFRAME solves this with:**

| Capability | What It Means |
|------------|---------------|
| **Agent Working Memory (AWM)** | Persistent memory OUTSIDE the context window - sessions, checkpoints, discoveries survive between turns |
| **Safe Execution** | Validation before action, guardrails against damage, no accidental `rm -rf /` |
| **Structured Output** | JSON envelopes for every operation - AI parses results reliably |
| **First-Time Correctness** | Clear errors, predictable behavior, no trial-and-error loops |
| **Sub-Agent Inheritance** | Child agents inherit discoveries and state from parent agents |
| **Zero Dependencies** | Pure bash. Works on any system with bash 4.0+. No jq, no sed, no awk required. |

```bash
# One line gives AI access to 4,000+ battle-tested functions
source "${MAINFRAME_ROOT}/lib/common.sh"
```

---

## Agent Working Memory (AWM)

**The breakthrough feature for AI agents with finite context windows.**

AI agents forget everything outside their context window. AWM provides persistent external memory that survives context limits, session interruptions, and even crashes.

### How It Works

```bash
# Initialize a session
awm_init "migrate-database"
# Session ID: a1b2c3d4e5f6

# Store key findings OUTSIDE the context window
awm_discovery "Database uses UTF-8 encoding"
awm_discovery "API rate limit is 100 req/min, not 1000"
awm_checkpoint "current_step" "3"
awm_checkpoint "api_config" '{"endpoint":"https://api.example.com"}'

# Track progress
awm_progress "file-processing" "47/200" "Processing batch 47"

# Log categorized messages
awm_log "decisions" "Chose PostgreSQL over MySQL for transactions"
awm_log "errors" "Warning: config missing, using defaults"

# Later: Resume where you left off
awm_resume "a1b2c3d4e5f6"
step=$(awm_get "current_step")  # Returns "3"
```

### Sub-Agent Inheritance

Parent agents can pass context to child agents - discoveries, checkpoints, and learned state transfer automatically:

```bash
# Parent agent discovers important facts
awm_init "orchestrator"
awm_discovery "Project uses TypeScript 5.0"
awm_discovery "Deployment target is AWS Lambda"
awm_checkpoint "active_branch" "feature/auth"

# Spawn a child agent with inherited context
awm_init "code-reviewer" "$PARENT_SESSION_ID"
# Child automatically has access to:
# - All parent discoveries
# - All parent checkpoints
# - Parent's learned state
```

### Namespace Isolation

Multiple agents can work simultaneously without interference:

```bash
# Each agent operates in its own namespace
awm_namespace "code-reviewer"
awm_init "review-auth-module"
awm_discovery "Found SQL injection in line 42"

awm_namespace "debugger"
awm_init "debug-crash"
awm_discovery "Stack overflow at recursive call"
# Completely isolated from code-reviewer's findings
```

### Token Budget Management

AWM estimates token usage and helps agents stay within context limits:

```bash
# Estimate how many tokens the session will consume
tokens=$(awm_token_estimate)
echo "Session would use ~$tokens tokens"

# Check if within limits
awm_check_limits || echo "Session too large, consider compression"

# Get a context-efficient summary
summary=$(awm_summary)
```

### Key AWM Functions

| Function | Purpose |
|----------|---------|
| `awm_init` | Create a new session, optionally inheriting from parent |
| `awm_close` | Close session, mark as complete |
| `awm_resume` | Resume a previous session by ID |
| `awm_checkpoint` | Store key-value pair (atomic, persistent) |
| `awm_get` | Retrieve a checkpointed value |
| `awm_discovery` | Log a high-priority insight |
| `awm_log` | Categorized logging (tasks, errors, decisions, etc.) |
| `awm_progress` | Track progress with current/total |
| `awm_summary` | Get JSON summary of session state |
| `awm_context_for` | Generate context package for sub-agent |
| `awm_namespace` | Set namespace for agent isolation |
| `awm_token_estimate` | Estimate tokens for session data |
| `awm_recent` | Get last N entries from a category |
| `awm_list` | List all sessions |

---

## Why MAINFRAME?

### The Problem

AI agents write fragile bash that:

- **Loses state** - Context window resets, all learning lost
- **Fails unpredictably** - External tools like `jq`, `sed`, `awk` may not exist
- **Requires retries** - Cryptic errors need multiple attempts to debug
- **Causes damage** - No guardrails against destructive operations
- **Wastes tokens** - Verbose scripts consume context window
- **Can't coordinate** - Sub-agents start from scratch

Every failed command costs tokens, time, and trust.

### The Solution

MAINFRAME provides a **safe runtime with persistent memory and first-time correctness**:

```bash
# WITHOUT MAINFRAME - AI writes fragile, volatile code
str="  hello  "
str="${str#"${str%%[![:space:]]*}"}"  # Cryptic parameter expansion
str="${str%"${str##*[![:space:]]}"}"  # Fails if AI forgets a quote
# State lost when context window fills

# WITH MAINFRAME - Safe, readable, persistent
source "$MAINFRAME_ROOT/lib/common.sh"
awm_init "my-task"
trim_string "  hello  "                              # Safe, tested
awm_checkpoint "processed" "$str"                    # Persists outside context
awm_discovery "String contained leading whitespace"  # Learning preserved
```

**Result:** AI agents complete tasks in one pass, remember what they learned, and pass knowledge to sub-agents.

---

## For AI Agent Developers

MAINFRAME is designed for teams building autonomous AI systems that interact with operating systems through bash.

### Universal Structured Output Protocol (USOP)

Every MAINFRAME operation can return structured JSON that AI agents parse reliably:

```bash
export MAINFRAME_OUTPUT=json

# Operations return structured envelopes
output_success "file created" "verify_file"
# {"ok":true,"data":"file created","hint":"verify_file","meta":{"elapsed_ms":2}}

output_error "E_NOT_FOUND" "Config missing" "run init first"
# {"ok":false,"error":{"code":"E_NOT_FOUND","msg":"Config missing","suggestion":"run init first"}}

# Typed outputs for type-safe parsing
output_int 42                    # {"ok":true,"data":42}
output_bool true                 # {"ok":true,"data":true}
output_json_object '{"id":1}'    # {"ok":true,"data":{"id":1}}
```

**Why this matters:** AI agents don't need to parse free-form text. They receive structured data they can act on immediately.

### Safe Command Dispatch

MAINFRAME never uses `eval`. All operations validate inputs before execution:

```bash
# Path validation prevents directory traversal attacks
validate_path_safe "$user_input" "/allowed/base" || die 1 "Invalid path"

# Command validation blocks injection attempts
validate_command_safe "$cmd" || die 1 "Command rejected"

# Sanitization for all user-provided data
sanitized=$(sanitize_shell_arg "$untrusted_input")
```

### Idempotent Operations

Safe to retry. Safe to run multiple times. No accidental damage:

```bash
# These operations check state before acting
ensure_dir "/path/to/dir"           # Creates only if missing
ensure_file "/path/to/file" "content"  # Writes only if different
ensure_line "/etc/hosts" "127.0.0.1 myapp"  # Adds only if absent
ensure_symlink "/link" "/target"    # Creates only if needed

# Atomic operations with automatic rollback
atomic_write "/path/to/file" "content"     # Writes to temp, moves atomically
file_checkpoint "/important/file"          # Creates backup point
file_rollback "/important/file"            # Restores from checkpoint
```

### Multi-Agent Coordination

For systems running multiple AI agents that need to coordinate:

```bash
# Lock guards prevent concurrent execution
guard_lock "/tmp/deploy.lock" || exit 1
# ... critical section ...
guard_unlock "/tmp/deploy.lock"

# AWM namespaces isolate concurrent agents
awm_namespace "agent-1"
awm_init "task-a"  # Isolated from agent-2

# Context handoff between agents
context=$(awm_context_for "sub-agent")
# Pass $context to spawned agent
```

### Project Intelligence

AI agents can instantly understand any codebase:

```bash
# Detect project type, framework, package manager
project_detect "/path/to/project"
# Returns JSON: {"language":"python","framework":"fastapi","package_manager":"pip"}

# Get available commands for the project
project_commands "/path/to/project"
# Returns: ["npm run build", "npm run test", "npm run start"]

# Token-efficient context summaries
context_summary "/path/to/project" --max-tokens 2000
```

---

## For AI Coding Assistants

MAINFRAME works with all AI coding assistants that can execute bash.

### Supported Platforms

| Platform | Integration | Setup |
|----------|-------------|-------|
| **Claude Code** | Full skill integration | `ln -s ~/.mainframe/skills/claude-code ~/.claude/skills/mainframe-bash` |
| **Clawdbot** | Config + source | Add to `~/.clawdbot/clawdbot.json` preamble |
| **Cursor** | .mdc rules | `cp ~/.mainframe/skills/cursor/mainframe.mdc .cursor/rules/` |
| **Aider** | CONVENTIONS.md | Add `read: CONVENTIONS.md` to `.aider.conf.yml` |
| **OpenCode** | CLAUDE.md | Point at this repo's CLAUDE.md |
| **Custom Agents** | System prompt | Load `skills/vercel-ai-sdk/system-prompt.md` |

### Token Savings

MAINFRAME reduces token usage by **71% per bash task**:

| Task | Without MAINFRAME | With MAINFRAME | Savings |
|------|-------------------|----------------|---------|
| JSON Creation | 72 tokens | 26 tokens | **64%** |
| Array Operations | 101 tokens | 39 tokens | **62%** |
| HTTP + Retry | 154 tokens | 32 tokens | **80%** |
| String Trimming | 40 tokens | 17 tokens | **58%** |
| Date Arithmetic | 64 tokens | 15 tokens | **77%** |
| Path Validation | 129 tokens | 21 tokens | **84%** |

**Compounding effect:** 10 bash tasks/day at 71% savings = 3x more productivity before hitting token caps.

---

## Library Reference

MAINFRAME provides **117 libraries** with **4,000+ functions** organized by category.

<details>
<summary><strong>AI Agent Infrastructure</strong> - Memory, agents, context</summary>

| Library | Functions | Purpose |
|---------|-----------|---------|
| `awm.sh` | 34 | Agent Working Memory - persistent state, inheritance, checkpoints |
| `agent.sh` | 45+ | Agent lifecycle, retries, coordination, execution |
| `context.sh` | 20+ | Token estimation, context budgeting, truncation |
| `cache.sh` | 25+ | Memoization, content-addressable storage, LRU eviction |
| `diff.sh` | 25+ | Surgical file editing, search-and-replace, patch application |

</details>

<details>
<summary><strong>Data Processing</strong> - JSON, CSV, strings, arrays</summary>

| Library | Functions | Purpose |
|---------|-----------|---------|
| `json.sh` | 34 | JSON generation without jq - `json_object`, `json_array`, `json_merge` |
| `csv.sh` | 34 | RFC 4180 CSV parsing - `csv_row`, `csv_parse_line`, `csv_to_json` |
| `pure-string.sh` | 34 | String manipulation - `trim_string`, `to_lower`, `replace_all` |
| `pure-array.sh` | 33 | Array operations - `array_unique`, `array_join`, `array_filter` |
| `template.sh` | 30 | Mustache-style templates - `template::render`, conditionals, loops |

</details>

<details>
<summary><strong>Network and HTTP</strong> - HTTP client, URL parsing</summary>

| Library | Functions | Purpose |
|---------|-----------|---------|
| `burl.sh` | 33 | AI-native HTTP client - GET/POST/PUT/DELETE, retries, JSON responses |
| `http.sh` | 35 | HTTP utilities and helpers |
| `git.sh` | 52 | Git workflow helpers - `git_branch`, `git_is_dirty` |

</details>

<details>
<summary><strong>System Operations</strong> - Files, processes, environment</summary>

| Library | Functions | Purpose |
|---------|-----------|---------|
| `pure-file.sh` | 37 | File operations without cat/head/tail |
| `proc.sh` | 40 | Process management, locks, timeouts |
| `env.sh` | 36 | Environment variables, dotenv loading |
| `path.sh` | 30 | Cross-platform path manipulation |
| `docker.sh` | 57 | Docker/Compose container management |
| `k8s.sh` | 52 | Kubernetes kubectl wrapper |

</details>

<details>
<summary><strong>Package Managers</strong> - npm, bun, pip</summary>

| Library | Functions | Purpose |
|---------|-----------|---------|
| `bun.sh` | 20 | Bun package manager - install, add, remove, run |
| `python.sh` | 40+ | Python/pip/venv management |

</details>

<details>
<summary><strong>Safety Layer</strong> - Validation, guards, errors</summary>

| Library | Functions | Purpose |
|---------|-----------|---------|
| `validation.sh` | 34 | Input validation, sanitization |
| `guard.sh` | 21 | Defensive guards for AI scripts |
| `error.sh` | 25 | Try/catch, stack traces, error context |
| `safe.sh` | 21 | Strict mode helpers, gotcha prevention |

</details>

<details>
<summary><strong>AI Agent Optimized</strong> - Idempotency, atomicity, observability</summary>

| Library | Functions | Purpose |
|---------|-----------|---------|
| `output.sh` | 25+ | Universal Structured Output Protocol (USOP) |
| `idempotent.sh` | 15+ | `ensure_dir`, `ensure_file`, `ensure_line` |
| `atomic.sh` | 15+ | `atomic_write`, `file_checkpoint`, `file_rollback` |
| `observe.sh` | 20+ | Structured observability, tracing |
| `project.sh` | 15+ | Project detection and intelligence |
| `contract.sh` | 15+ | Design-by-Contract assertions |

</details>

<details>
<summary><strong>Language Analysis</strong> - TypeScript, Python (no runtime required)</summary>

| Library | Functions | Purpose |
|---------|-----------|---------|
| `typescript.sh` | 22 | Import analysis, API diff, bundle size estimation |
| `python.sh` | 17 | Import analysis, dependency detection, code metrics |

</details>

<details>
<summary><strong>DevOps and CI/CD</strong> - Portability, health checks</summary>

| Library | Functions | Purpose |
|---------|-----------|---------|
| `ci.sh` | 35+ | CI/CD portability across GitHub, GitLab, Jenkins, etc. |
| `health.sh` | 27 | Health check framework with HTTP server |
| `compat.sh` | 50+ | BSD/GNU compatibility, WSL detection |
| `sysinfo.sh` | 40+ | System detection, resource monitoring |

</details>

<details>
<summary><strong>UI and CLI</strong> - Terminal output, argument parsing</summary>

| Library | Functions | Purpose |
|---------|-----------|---------|
| `ansi.sh` | 90 | Terminal colors and styling |
| `tui.sh` | 30 | Progress bars, spinners, prompts |
| `cli.sh` | 35 | Declarative CLI framework with auto-help |
| `log.sh` | 30 | Structured JSON logging with levels |

</details>

For complete function signatures, see [CHEATSHEET.md](CHEATSHEET.md).

---

## Benchmarks

MAINFRAME's pure bash operations outperform external tools by 20-72x:

| Operation | External Tool | MAINFRAME | Speedup |
|-----------|---------------|-----------|---------|
| Trim whitespace | 2379 ms | 33 ms | **72x faster** |
| Lowercase | 778 ms | 16 ms | **49x faster** |
| String replace | 986 ms | 18 ms | **55x faster** |
| Array unique | 823 ms | 39 ms | **21x faster** |
| File head | 620 ms | 31 ms | **20x faster** |
| Count lines | 662 ms | 24 ms | **28x faster** |
| Get basename | 579 ms | 17 ms | **34x faster** |

*Benchmarks: 1000 iterations each, pure bash vs. sed/awk/external tools*

Run benchmarks yourself:
```bash
bash benchmarks/superpower_benchmarks.sh
```

---

## Testing

MAINFRAME has **6,500+ tests** with comprehensive coverage:

```
$ ./tests/bats/bin/bats tests/unit/
ok 1 - trim_string removes leading/trailing whitespace
ok 2 - to_lower converts to lowercase
...
ok 6538 - regex_get: returned pattern works with bash regex

6538 tests, 0 failures
```

Run the test suite:
```bash
# bats-core is included as a git submodule
git submodule update --init
./tests/bats/bin/bats tests/unit/
```

---

## What's New in v6.0

**MAINFRAME v6.0** introduces **Agent Working Memory (AWM)** - the breakthrough feature for AI agents with finite context windows.

### Headline Feature: Agent Working Memory

| Capability | Description |
|------------|-------------|
| **Persistent Sessions** | State survives context window limits, interruptions, crashes |
| **Sub-Agent Inheritance** | Child agents inherit discoveries and checkpoints from parents |
| **Namespace Isolation** | Multiple agents work simultaneously without interference |
| **Token Budget Management** | Estimate and control how much context AWM data will consume |
| **Categorized Logging** | Separate logs for tasks, errors, decisions, discoveries |
| **Atomic Checkpoints** | Key-value storage with crash-safe guarantees |

### New Libraries

| Library | Functions | Purpose |
|---------|-----------|---------|
| `awm.sh` | 34 | Agent Working Memory - persistent state outside context window |
| `burl.sh` | 50+ | AI-native HTTP client with automatic retries and JSON output |
| `bun.sh` | 40+ | Bun package manager integration |
| `agent.sh` | 45+ | Agent lifecycle management, coordination, retry logic |

### Enhanced Libraries

| Library | Improvements |
|---------|--------------|
| `ci.sh` | Extended CI platform detection (20+ platforms) |
| `compat.sh` | Improved BSD/GNU compatibility layer |
| `sysinfo.sh` | Better VM and container detection |
| `validation.sh` | More regex patterns, improved URL matching |

---

## Documentation

- **[Installation Guide](INSTALL.md)** - Detailed setup instructions
- **[Full Function Reference](CHEATSHEET.md)** - All 4,000+ function signatures
- **[AI Agent Integration](CLAUDE.md)** - Instructions for AI coding assistants
- **[Contributing](CONTRIBUTING.md)** - How to contribute
- **[Roadmap](ROADMAP.md)** - Planned features and improvements

---

## Contributing

We welcome contributions. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create a feature branch
3. Add tests for new functions (maintain coverage)
4. Submit a pull request

---

## License

MIT License - Use freely in your projects. See [LICENSE](LICENSE).

---

<div align="center">

## The Mission

**We're building MAINFRAME for a safe and accurate future for agentic AI.**

Bash is how AI agents control computer systems. It deserves a runtime built for safety, persistence, and first-time correctness.

Every command an AI agent executes should be:
- **Safe** - Validated inputs, guardrails, no accidental damage
- **Persistent** - Memory survives context limits and crashes
- **Accurate** - First-time correctness, structured output, clear errors
- **Efficient** - Minimal tokens, minimal retries, minimal friction

MAINFRAME is that runtime.

---

*"Knowing Your Shell is half the battle."*

**[Install Now](#quick-install)** | **[Full Docs](INSTALL.md)** | **[Report Issues](https://github.com/gtwatts/mainframe/issues)**

---

**4,000+ functions** | **Zero dependencies** | **Agent Working Memory** | **Pure Bash**

</div>

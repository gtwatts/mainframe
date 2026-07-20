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

**3,821+ Pure Bash Functions** | **152 Libraries** | **Zero Dependencies** | **AI-Native Runtime**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Tests](https://img.shields.io/github/actions/workflow/status/gtwatts/mainframe/test.yml?label=tests)](https://github.com/gtwatts/mainframe/actions)
[![Bash 4.0+](https://img.shields.io/badge/bash-4.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Pure Bash](https://img.shields.io/badge/dependencies-zero-blue.svg)](https://github.com/gtwatts/mainframe)
[![GitHub stars](https://img.shields.io/github/stars/gtwatts/mainframe?style=social)](https://github.com/gtwatts/mainframe)

</div>

---

## Quick Install

### One-Line Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/gtwatts/mainframe/main/get-mainframe.sh | bash
```

### Manual Install

```bash
git clone https://github.com/gtwatts/mainframe.git ~/.mainframe
~/.mainframe/install.sh
```

**Verify installation:**
```bash
source ~/.bashrc  # or restart your terminal
source "$MAINFRAME_ROOT/lib/common.sh" && uuid
```

**That's it.** Your AI agents now have a safe, efficient bash runtime with persistent memory.

For detailed installation options, see [INSTALL.md](INSTALL.md).

---

## What is MAINFRAME?

**MAINFRAME is the runtime layer between AI agents and the operating system.**

AI agents - whether Claude Code, Codex, Gemini, Cursor, or custom LLM-powered tools - interact with computers primarily through bash. They write shell commands to navigate filesystems, manipulate data, manage processes, and orchestrate system operations.

The problem: **AI agents have finite context windows and bash is hostile territory.**

| Problem | MAINFRAME Solution |
|---------|-------------------|
| Context windows fill up, losing critical state | **Agent Working Memory (AWM)** - persistent storage outside context |
| Commands fail silently or with cryptic errors | **Structured Output (USOP)** - JSON envelopes with clear error codes |
| Output is unstructured and unparseable | **Typed Responses** - every operation returns parseable JSON |
| Security vulnerabilities are one typo away | **Validation Layer** - input sanitization, path traversal prevention |
| Sub-agents can't inherit learnings from parent agents | **AWM Inheritance** - child agents receive parent discoveries |
| External tools (jq, sed, awk) may not exist | **Zero Dependencies** - pure bash 4.0+, no external tools required |

**MAINFRAME provides:**

| Capability | What It Means |
|------------|---------------|
| **Agent Working Memory (AWM)** | Persistent memory OUTSIDE the context window - sessions, checkpoints, discoveries survive between turns |
| **Safe Execution** | Validation before action, guardrails against damage, no accidental `rm -rf /` |
| **Structured Output** | JSON envelopes for every operation - AI parses results reliably |
| **First-Time Correctness** | Clear errors, predictable behavior, no trial-and-error loops |
| **Sub-Agent Inheritance** | Child agents inherit discoveries and state from parent agents |
| **Zero Dependencies** | Pure bash. Works on any system with bash 4.0+. No jq, no sed, no awk required. |

```bash
# One line gives AI access to 3,821+ battle-tested functions
source "${MAINFRAME_ROOT}/lib/common.sh"
```

---

## Agent Working Memory (AWM)

**The breakthrough feature for AI agents with finite context windows.**

AI agents forget everything outside their context window. AWM gives them a file-backed working memory that survives context limits, interruptions, and crashes.

### Golden Path

```bash
# Start a canonical AWM session
sid=$(awm_init "security-audit" --namespace review --model gpt-4o --backend file)
awm_resume "$sid"

# Persist high-signal state outside the context window
awm_checkpoint "current_phase" "scanning" --importance high
awm_discovery "Auth uses JWT refresh tokens" --importance critical --tags auth,jwt
awm_log "decisions" "Prefer PostgreSQL for transactional guarantees" --importance high
awm_progress "scan" "12/40" "Scanning auth module"

# Retrieve only what the next step needs
results=$(awm_find "jwt postgres" --kind mixed --limit 5)
ctx=$(awm_context_for "dependency review" --tokens 2000)

# Hand off to a sub-agent or later continuation
handoff=$(awm_handoff_prepare "dependency-reviewer" --tokens 2000)
```

### Why It Matters

- **Persistent state**: checkpoints, discoveries, logs, and progress survive across turns.
- **Deterministic retrieval**: `awm_find` and `awm_context_for` pull back the highest-signal memory instead of replaying the whole session.
- **Clean handoffs**: `awm_handoff_prepare` and `awm_handoff_accept` turn memory transfer into a first-class product surface.
- **Safe defaults**: file-backed storage is the default; advanced backends are opt-in.
- **Migration path**: older sessions upgrade in place with `awm_migrate`.

### Canonical AWM Surface

| Function | Purpose |
|----------|---------|
| `awm_init` | Create a new session, optionally inheriting from a parent |
| `awm_resume` | Resume a session by ID |
| `awm_checkpoint` | Store persistent key/value state with metadata |
| `awm_discovery` | Record critical insights that should stay visible |
| `awm_log` | Append structured categorized events |
| `awm_progress` | Track current progress and latest task state |
| `awm_find` | Search discoveries, checkpoints, and logs |
| `awm_context_for` | Build a deterministic context package for a task |
| `awm_handoff_prepare` | Create a budgeted handoff package |
| `awm_handoff_accept` | Accept a handoff into a receiving session |
| `awm_status` / `awm_doctor` | Inspect session health, schema, and layout |
| `awm_export` / `awm_migrate` | Export human-readable reports and upgrade older sessions |

### CLI

```bash
sid=$(mainframe awm init security-audit --namespace review)
mainframe awm checkpoint --session "$sid" current_phase scanning --importance high
mainframe awm discovery --session "$sid" "JWT refresh tokens enabled" --importance critical
mainframe awm find --session "$sid" jwt --kind mixed
mainframe awm handoff prepare --session "$sid" reviewer --tokens 2000
mainframe awm doctor --session "$sid"
```

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
| **Pi** | Tool-aware skill + MAINFRAME wrappers | Load `skills/pi/SKILL.md`; use `mainframe_status`, `mainframe_search`, `mainframe_help`, `mainframe_exec`, and `mainframe_awm` when available |
| **Claude Code** | Full skill integration | `ln -s ~/.mainframe/skills/claude-code ~/.claude/skills/mainframe-bash` |
| **OpenAI Codex / Codex CLI** | `AGENTS.md` instructions | Copy or merge `skills/codex/AGENTS.md` into project `AGENTS.md` |
| **Clawdbot** | Config + source | Add `skills/clawdbot/preamble.md` to `~/.clawdbot/clawdbot.json` preamble |
| **Cursor** | .mdc rules | `cp ~/.mainframe/skills/cursor/mainframe.mdc .cursor/rules/` |
| **Aider** | CONVENTIONS.md | Add `read: ~/.mainframe/skills/aider/CONVENTIONS.md` to `.aider.conf.yml` |
| **OpenCode** | Project instructions | Load `skills/opencode/SKILL.md` |
| **Kimi / Google AI CLI** | Project instructions | Load `skills/kimi-cli/SKILL.md` or `skills/google-cli/SKILL.md` |
| **Custom Agents** | System prompt | Load `skills/vercel-ai-sdk/system-prompt.md` |

See [MAINFRAME for AI CLI and Coding Agents](docs/AI_CLI_INTEGRATIONS.md) for Claude, Codex, Pi, Cursor, Aider, OpenCode, Kimi, Google AI CLI, and custom-agent setup.

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

MAINFRAME provides **152 libraries** with **3,821+ functions** organized by category.

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
<summary><strong>V10 AI-Native Runtime</strong> - Verification, intent, healing, prediction</summary>

| Library | Functions | Purpose |
|---------|-----------|---------|
| `verify.sh` | 20+ | Pre-execution verification - detect errors before they happen |
| `intent.sh` | 20+ | Natural language parsing to structured intent |
| `generate.sh` | 12+ | AI code generation from descriptions |
| `heal.sh` | 29+ | Self-healing error recovery with confidence scoring |
| `predict.sh` | 13+ | Predict resource usage (time/memory/risk) before execution |
| `optimize.sh` | 13+ | Automatic command optimization |
| `graph.sh` | 27+ | DAG workflow execution with auto-parallelization |
| `temporal.sh` | 52+ | SQL-like queries on command history |
| `agent_loop.sh` | 35+ | Persistent background agent processes |
| `state_machine.sh` | 26+ | Visual workflow state machines |
| `uap_v2.sh` | 42+ | ZeroMQ-like agent messaging with RPC and streaming |

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

MAINFRAME has **11,300+ tests** with comprehensive coverage:

```
$ ./tests/bats/bin/bats tests/unit/
ok 1 - trim_string removes leading/trailing whitespace
ok 2 - to_lower converts to lowercase
...
ok 11360 - verify_command: detects typos

11360 tests, 0 failures
```

Run the same suite local development and CI both use:
```bash
make test-deps
./tests/run_bats_suite.sh --scope all
```

---

## What's New in V10

**MAINFRAME V10** is the AI-Native Bash Runtime - transforming bash from a brittle shell into a robust execution environment for AI agents.

### Headline Features

| Capability | Description |
|------------|-------------|
| **Pre-Execution Verification** | Catch 90% of errors before execution with `verify_command` |
| **Natural Language to Bash** | Parse intent with `intent_parse`, generate code with `intent_to_bash` |
| **Self-Healing Execution** | Auto-recover from 70% of common errors with `heal_wrap` |
| **Predictive Resources** | Predict time/memory/risk before running with `predict_resources` |
| **Graph Workflows** | Define DAG workflows that auto-parallelize with `graph_execute` |
| **Temporal Queries** | SQL-like queries on command history with `temporal_query` |
| **Persistent Agents** | Background agent loops with `agent_loop_start` |
| **ZeroMQ-like Messaging** | RPC, streaming, broadcast with `uap_v2_call` |

### V10 Libraries (12 New Libraries, ~289 Functions)

| Library | Functions | Purpose |
|---------|-----------|---------|
| `verify.sh` | 20+ | Pre-execution static analysis and typo detection |
| `intent.sh` | 20+ | Natural language parsing to structured intent |
| `generate.sh` | 12+ | AI code generation from descriptions |
| `graph.sh` | 27+ | DAG workflow execution with auto-parallelization |
| `heal.sh` | 29+ | Self-healing error recovery with confidence scores |
| `predict.sh` | 13+ | Resource prediction (time/memory/risk) for commands |
| `optimize.sh` | 13+ | Automatic command optimization |
| `temporal.sh` | 52+ | SQL-like command history queries |
| `agent_loop.sh` | 35+ | Persistent background agent processes |
| `state_machine.sh` | 26+ | Visual workflow state machines |
| `uap_v2.sh` | 42+ | ZeroMQ-like agent messaging (RPC + streaming) |

### Example: V10 in Action

```bash
# Verify before execute
result=$(verify_command "find / -name '*.log' 2>/dev/null")
echo "$result" | jq '.valid'  # false - warns about root directory scan

# Natural language to bash
intent=$(intent_parse "find Python files modified today")
bash_cmd=$(intent_to_bash "$intent")
echo "$bash_cmd"  # find . -name '*.py' -mtime -1 -type f

# Self-healing execution
heal_wrap "deploy_to_prod.sh"  # Auto-retries, suggests fixes on failure

# Predict before running
predict_resources "npm install"  # {"time_s":30,"memory_mb":512,"risk":"low"}
```

---

## Documentation

- **[Installation Guide](INSTALL.md)** - Detailed setup instructions
- **[Full Function Reference](CHEATSHEET.md)** - All 3,821+ function signatures
- **[AI Agent Integration](CLAUDE.md)** - Instructions for AI coding assistants
- **[Contributing](CONTRIBUTING.md)** - How to contribute
- **[Roadmap](ROADMAP.md)** - Planned features and improvements

---

## Shell Completion

MAINFRAME includes tab completion for both bash and zsh.

### Bash

```bash
# Source directly (add to ~/.bashrc for persistence)
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/completions/mainframe.bash"

# Or install system-wide
sudo cp completions/mainframe.bash /etc/bash_completion.d/mainframe
```

### Zsh

```zsh
# Source directly (add to ~/.zshrc for persistence)
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/completions/mainframe.zsh"

# Or add to fpath for autoloading
fpath=("${MAINFRAME_ROOT:-$HOME/.mainframe}/completions" $fpath)
autoload -Uz compinit && compinit

# For Oh My Zsh users
cp completions/mainframe.zsh ~/.oh-my-zsh/completions/_mainframe
```

After setup, type `mainframe ` and press Tab to see available commands.

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

**3,821+ functions** | **152 libraries** | **Zero dependencies** | **AI-Native Runtime**

</div>
# Mainframe V10 - AI-Native Bash Runtime

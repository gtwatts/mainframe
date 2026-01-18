# MAINFRAME

```
╔══════════════════════════════════════════════════════════════════╗
║ ★ ★ ★ ═══════════════════════════════════════════════════════════║
║ ★ ★ ★  __  __   _   ___ _  _ ___ ___    _   __  __ ___           ║
║ ★ ★ ★ |  \/  | /_\ |_ _| \| | __| _ \  /_\ |  \/  | __|          ║
║ ═════ | |\/| |/ _ \ | || .` | _||   / / _ \| |\/| | _|           ║
║ ═════ |_|  |_/_/ \_\___|_|\_|_| |_|_\/_/ \_\_|  |_|___|          ║
║ ═════                                                            ║
║         "Mainframe can make a computer do anything               ║
║                       short of tap dance."                       ║
╚══════════════════════════════════════════════════════════════════╝
      "Knowing Your Shell is half the battle."
```

<div align="center">

<img src="mainframe_hero.png" alt="MAINFRAME - Bash Superpowers for AI Coding Assistants" width="600">

### Give Your AI Coding Assistant **BASH SUPERPOWERS**

**850+ Pure Bash Functions** | **Zero Dependencies** | **20-72x Faster**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Tests](https://img.shields.io/github/actions/workflow/status/gtwatts/mainframe/test.yml?label=tests)](https://github.com/gtwatts/mainframe/actions)
[![Bash 4.0+](https://img.shields.io/badge/bash-4.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Pure Bash](https://img.shields.io/badge/dependencies-zero-blue.svg)](https://github.com/gtwatts/mainframe)
[![GitHub stars](https://img.shields.io/github/stars/gtwatts/mainframe?style=social)](https://github.com/gtwatts/mainframe)
[![YO JOE](https://img.shields.io/badge/YO-JOE!-red?style=flat)](https://github.com/gtwatts/mainframe)

**Works with:** [Claude Code](https://docs.anthropic.com/en/docs/claude-code) • [OpenCode](https://github.com/opencode-ai/opencode) • [Aider](https://aider.chat/) • Any AI that writes bash

</div>

---

## The Problem

When AI coding assistants like **Claude Code** or **OpenCode** write bash scripts, they often:

- ❌ Write 15+ lines for simple operations (string trimming, array manipulation)
- ❌ Rely on external tools (`sed`, `awk`, `jq`) that may not exist everywhere
- ❌ Spawn subshells for basic operations (slow)
- ❌ Reinvent the wheel every time

## The Solution: MAINFRAME

One line of code gives your AI instant access to **850+ battle-tested functions**:

```bash
source "${MAINFRAME_ROOT}/lib/common.sh"
```

Now your AI can:

- ✅ **Write cleaner code** - `trim_string "  hello  "` instead of parameter expansion hell
- ✅ **Skip dependencies** - Pure bash means it works on ANY system
- ✅ **Execute 20-72x faster** - Built-in bash operations vs spawning external processes
- ✅ **Generate JSON without jq** - `json_object name="John" age:number=30`

---

## Quick Start (30 Seconds)

```bash
# 1. Clone MAINFRAME
git clone https://github.com/gtwatts/mainframe.git ~/.mainframe

# 2. Add to your shell profile
echo 'export MAINFRAME_ROOT="$HOME/.mainframe"' >> ~/.bashrc
echo 'source "$MAINFRAME_ROOT/lib/common.sh"' >> ~/.bashrc

# 3. Reload and verify
source ~/.bashrc
trim_string "  hello world  "   # Output: hello world
```

**That's it.** Your AI now has superpowers.

📖 **[Full Installation Guide](INSTALL.md)**

---

## Before & After

### Without MAINFRAME
```bash
# Claude Code writes 15+ lines to trim a string
str="  hello world  "
str="${str#"${str%%[![:space:]]*}"}"
str="${str%"${str##*[![:space:]]}"}"
echo "$str"

# Generate JSON? Good luck without jq
echo "{\"name\":\"$(echo "$name" | sed 's/"/\\"/g')\",\"age\":$age}"
```

### With MAINFRAME
```bash
source "$MAINFRAME_ROOT/lib/common.sh"

trim_string "  hello world  "              # Done
json_object name="John" age:number=30      # {"name":"John","age":30}
```

---

## Benchmark Results

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

## What You Get

### 24 Libraries, 880+ Functions

| Library | Functions | What It Does |
|---------|-----------|--------------|
| **common.sh** | 51 | Logging, errors, validation, colors |
| **pure-string.sh** | 34 | String ops without sed/awk |
| **pure-array.sh** | 33 | Array ops without external tools |
| **pure-util.sh** | 60 | UUID, timestamps, validation |
| **pure-file.sh** | 37 | File ops without cat/head/tail |
| **json.sh** | 20 | JSON generation (no jq needed) |
| **semver.sh** | 20 | Semantic versioning |
| **ansi.sh** | 90 | Terminal colors & styling |
| **tui.sh** | 30 | Progress bars, spinners, prompts, boxes |
| **async.sh** | 26 | Async/parallel execution |
| **args.sh** | 18 | Argument parsing |
| **config.sh** | 13 | Config file handling |
| **datetime.sh** | 45 | Date/time arithmetic & formatting |
| **http.sh** | 35 | HTTP client (GET/POST/PUT/DELETE) |
| **csv.sh** | 34 | RFC 4180 CSV parsing & generation |
| **git.sh** | 52 | Git workflow helpers |
| **crypto.sh** | 17 | Hashing, encoding, secure random |
| **proc.sh** | 40 | Process management & locks |
| **docker.sh** | 57 | Docker/Compose container management |
| **env.sh** | 36 | Environment variables & dotenv |
| **path.sh** | 30 | Cross-platform path manipulation |
| **validation.sh** | 34 | Input validation & sanitization |
| **pipe.sh** | 39 | Unix pipeline processing |
| **stream.sh** | 28 | Advanced stream paradigms |
| **error.sh** | 25 | Try/catch, stack traces, error context |

### Zero External Dependencies

MAINFRAME is **pure bash** - nothing else required:

- ❌ No `jq` for JSON
- ❌ No `sed`/`awk` for strings
- ❌ No `cat`/`head`/`tail` for files
- ✅ Works anywhere bash 4.0+ exists

---

## Usage Examples

### String Operations
```bash
trim_string "  hello  "           # "hello"
to_lower "HELLO"                  # "hello"
replace_all "hello" "l" "L"       # "heLLo"
urlencode "hello world"           # "hello%20world"
contains "hello world" "world"    # returns 0 (true)
```

### JSON Generation (No jq!)
```bash
json_object name="John" age:number=30 active:bool=true
# {"name":"John","age":30,"active":true}

json_array "apple" "banana" "cherry"
# ["apple","banana","cherry"]

json_nested "data.user.name" "John"
# {"data":{"user":{"name":"John"}}}
```

### Array Operations
```bash
array_contains "needle" "hay" "needle" "stack"  # returns 0 (found)
array_join "," "a" "b" "c"                       # "a,b,c"
array_unique "a" "b" "a" "c"                     # a, b, c
array_sum 1 2 3 4 5                              # 15
array_reverse "a" "b" "c"                        # c, b, a
```

### Async/Parallel Execution
```bash
# Run in background, get PID
pid=$(set_timeout 5 "echo 'done'")

# Parallel execution
parallel "task1" "task2" "task3"

# With concurrency limit
parallel_limit 4 "${tasks[@]}"

# Retry with exponential backoff
retry 5 "curl http://api.example.com"
```

### Terminal UI
```bash
success "Task completed"          # ✓ Task completed (green)
failure "Something failed"        # ✗ Something failed (red)
header "My Section"               # Formatted header
progress_bar 50 100               # [████████░░░░░░░░] 50%

# Colors
ansi_print red "Error!"
ansi_styled "bold,green" "Success!"
```

### Utilities
```bash
uuid                              # 550e8400-e29b-41d4-a716-446655440000
timestamp                         # 2026-01-17 10:30:45
is_valid_email "user@example.com" # returns 0 (valid)
random_string 16                  # x7Kj9mNp2qRs4tUv
semver_bump_minor "1.2.3"         # 1.3.0
```

### DateTime Operations (NEW in v2.0)
```bash
now                               # 1705312896 (Unix epoch)
now_iso                           # 2026-01-17T10:30:00-0500
format_relative $(($(now)-3600)) # "1 hour ago"
date_add $(now) "2d"              # Add 2 days
is_weekend                        # Check if Saturday/Sunday
```

### HTTP Requests (NEW in v2.0)
```bash
# Parse URLs
url_parse "https://api.example.com:8080/users?page=1"
echo "$URL_HOST"                  # api.example.com
echo "$URL_PORT"                  # 8080

# Build query strings
query_string "api_key=abc" "format=json"  # api_key=abc&format=json
```

### CSV Processing (NEW in v2.0)
```bash
# Create CSV rows
csv_row "John" "Doe" "john@example.com"  # John,Doe,john@example.com

# Read and parse CSV
csv_read "data.csv"
csv_get 0 "name"                  # Get field by column name
```

### Git Helpers (NEW in v2.0)
```bash
git_branch                        # main
git_commit_hash                   # abc1234
git_is_dirty && echo "uncommitted changes"
git_summary                       # main @ abc1234 [clean]
```

### Crypto & Hashing (NEW in v2.0)
```bash
sha256 "sensitive data"           # 2cf24dba5fb0a30e...
random_token 32                   # Secure URL-safe token
uuid                              # UUID v4
checksum_verify "file.tar.gz" "$expected_hash"
```

### Process Management (NEW in v2.0)
```bash
proc_exists $pid                  # Check if PID exists
proc_find_by_port 8080            # Find what's using port 8080
proc_load                         # System load average
with_lock "/tmp/app.lock" "run_exclusive_task"
```

### Docker & Containers (NEW in v2.1)
```bash
docker_is_running                 # Check Docker daemon
docker_image_exists "nginx"       # Check if image exists
docker_container_logs "app" 50    # Get last 50 log lines
compose_up "docker-compose.yml"   # Start compose stack
compose_status                    # Show running services
```

### Environment Variables (NEW in v2.1)
```bash
env_load_dotenv ".env"            # Load .env file
env_path_prepend "/opt/bin"       # Add to PATH
env_require "API_KEY"             # Error if not set
env_get "PORT" "8080"             # Get with default
env_is_set "DEBUG" && echo "on"   # Check if set
```

### Path Manipulation (NEW in v2.1)
```bash
path_normalize "/foo/../bar"      # /bar
path_join "/a" "b" "c"            # /a/b/c
path_is_safe "/base" "$input"     # Prevent traversal attacks
path_ext "/file.tar.gz"           # gz
path_replace_ext "doc.md" "html"  # doc.html
```

### Input Validation (NEW in v2.1)
```bash
validate_email "user@example.com" # Check email format
validate_url "https://..." "http,https"  # URL with scheme
validate_path_safe "$path" "/base"  # Prevent directory traversal
sanitize_html "<script>..."       # Escape HTML entities
sanitize_filename "a/b<c>.txt"    # Safe filename
```

### Unix Pipelines (NEW in v2.1)
```bash
# Functional pipeline processing
echo -e "a\nb\nc" | pipe_map 'tr a-z A-Z'     # A B C
echo -e "1\n2\n3" | pipe_filter '^[12]$'      # 1, 2
echo -e "1\n2\n3" | pipe_sum                  # 6
echo -e "a\nb\na" | pipe_unique               # a, b
echo -e "a\nb\nc" | pipe_join ","             # a,b,c
```

### Error Handling (NEW in v2.2)
```bash
source "$MAINFRAME_ROOT/lib/error.sh"

# Try/catch pattern
try
(
    risky_command
    another_command
)
if catch; then
    echo "Error caught: $ERROR_MESSAGE"
    error::stack_trace  # Print call stack
fi

# Add context to errors
error::context "parsing" "config.json"
error::context "validating" "user section"
parse_config  # If this fails, context is shown

# Throw errors with context
error::throw "Invalid configuration"  # Prints error, context, stack trace

# Retry with backoff
error::retry -n 5 -d 2 curl -f https://api.example.com

# Register cleanup handlers
error::on_exit "rm -f $tempfile"
```

---

## For AI Coding Assistant Users

### Claude Code Integration

When Claude Code generates bash scripts, it sources MAINFRAME once and gains instant access to everything:

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Generate JSON response (no jq needed!)
response=$(json_object \
    status="success" \
    timestamp="$(timestamp)" \
    id="$(uuid)"
)

# Validate input
is_valid_email "$1" || die 1 "Invalid email: $1"

# Show progress
for i in {1..100}; do
    progress_bar "$i" 100
    sleep 0.01
done

success "Complete!"
```

### OpenCode / Aider / Other AI Assistants

The same pattern works with any AI that writes bash:

1. Install MAINFRAME (30 seconds)
2. Tell your AI: *"Source MAINFRAME's common.sh for bash utilities"*
3. Watch it write cleaner, faster bash code

### Teaching Your AI (Important!)

**AI assistants don't automatically know about MAINFRAME** - you need to tell them once.

**For Claude Code**, add to `~/.claude/CLAUDE.md`:
```markdown
When writing bash scripts, source MAINFRAME:
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

**For other AIs**, add similar instructions to their config files (`.cursorrules`, `.aider.conf.yml`, etc.)

📖 **[Full AI Setup Guide](INSTALL.md#teaching-your-ai-about-mainframe)**

---

## Project Structure

```
mainframe/
├── lib/                    # Core libraries (850+ functions)
│   ├── common.sh          # Main entry point (auto-sources all)
│   ├── pure-string.sh     # String manipulation
│   ├── pure-array.sh      # Array operations
│   ├── pure-util.sh       # Utilities
│   ├── pure-file.sh       # File operations
│   ├── json.sh            # JSON generation
│   ├── semver.sh          # Semantic versioning
│   ├── ansi.sh            # Terminal colors & UI
│   ├── async.sh           # Async/parallel execution
│   ├── args.sh            # Argument parsing
│   ├── config.sh          # Config file handling
│   ├── datetime.sh        # Date/time operations
│   ├── http.sh            # HTTP client
│   ├── csv.sh             # CSV parsing
│   ├── git.sh             # Git helpers
│   ├── crypto.sh          # Hashing & encoding
│   ├── proc.sh            # Process management
│   ├── docker.sh          # Docker/Compose (v2.1)
│   ├── env.sh             # Environment vars (v2.1)
│   ├── path.sh            # Path manipulation (v2.1)
│   ├── validation.sh      # Input validation (v2.1)
│   ├── pipe.sh            # Unix pipelines (v2.1)
│   ├── stream.sh          # Stream processing (v2.1)
│   └── error.sh           # Try/catch & stack traces (v2.2)
├── scripts/               # Ready-to-use scripts
├── tests/                 # BATS test suite (295 tests)
├── benchmarks/            # Performance benchmarks
└── docs/                  # Documentation
```

---

## Running Tests

```bash
# Install bats-core first (https://github.com/bats-core/bats-core)
# Then run:
bats tests/
```

---

## Test It With Your AI

**We encourage you to test MAINFRAME with your own AI coding assistant** and see the difference it makes.

### Quick Test Challenge

Give your AI (Claude Code, OpenCode, Cursor, Aider, etc.) this prompt:

> "Using MAINFRAME (source ~/.mainframe/lib/common.sh), write a bash script that:
> 1. Gets the current git branch and commit hash
> 2. Generates a UUID session token
> 3. Creates a JSON object with this data
> 4. Shows a progress bar while 'processing'
> 5. Outputs a success message"

**Without MAINFRAME**, your AI will write 50+ lines of code, potentially using `jq`, `uuidgen`, and other external tools.

**With MAINFRAME**, watch your AI write ~15 lines of clean, portable bash:

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

header "Session Report"
branch=$(git_branch)
commit=$(git_commit_hash)
token=$(uuid)

for i in {1..100}; do
    progress_bar "$i" 100
    sleep 0.01
done
echo

json_object "branch=$branch" "commit=$commit" "session=$token"
success "Report generated!"
```

### Run the Demo Script

We include a demo script you can run immediately:

```bash
bash ~/.mainframe/examples/mainframe_demo.sh
```

### Full Function Reference

See [CHEATSHEET.md](CHEATSHEET.md) for complete function signatures - essential for getting your AI to use the correct syntax on the first try.

### Share Your Results

Did MAINFRAME improve your AI's bash scripts? We'd love to hear:
- [Open an issue](https://github.com/gtwatts/mainframe/issues) with your experience
- Star the repo if MAINFRAME helped you

---

## Requirements

- **Bash 4.0+** (for associative arrays, parameter expansion)
- **That's it.** Zero external dependencies.

Check your bash version:
```bash
bash --version
```

---

## Why "MAINFRAME"?

In 1986, Hasbro introduced **Mainframe** to the G.I. Joe team - the computer specialist who wore a laptop strapped to his chest when most people had never seen a portable computer.

His filecard read: *"Mainframe can make a computer do anything short of tap dance."*

**That's exactly what this toolkit does for AI coding assistants. It makes bash dance.**

### How MAINFRAME Makes Bash Dance

When Claude Code, OpenCode, or Cursor writes bash scripts, they face a fundamental problem: **bash is powerful but verbose**. Simple operations require arcane syntax that even experienced developers forget.

**Without MAINFRAME**, your AI writes code like this:
```bash
# Trim whitespace - 4 lines of cryptic parameter expansion
str="  hello  "
str="${str#"${str%%[![:space:]]*}"}"
str="${str%"${str##*[![:space:]]}"}"
```

**With MAINFRAME**, your AI writes this:
```bash
trim_string "  hello  "  # Done.
```

This isn't just cleaner - it's **transformative for agentic coding**:

| Without MAINFRAME | With MAINFRAME |
|-------------------|----------------|
| AI generates 15-20 lines for simple ops | AI writes 1-2 lines that just work |
| AI must remember arcane bash syntax | AI calls intuitive functions like `json_object`, `git_branch`, `sha256` |
| Scripts fail on systems missing `jq`, `sed`, `awk` | Pure bash runs everywhere |
| External tool calls spawn subshells (slow) | Built-in operations are 20-72x faster |
| AI reinvents solutions every session | AI reuses battle-tested, documented functions |

### Why This Matters for Agentic Coding

**Agentic AI coding** means your AI assistant works autonomously - writing, testing, and iterating on code with minimal intervention. This requires:

1. **Reliability** - Scripts must work the first time, on any system
2. **Speed** - Faster execution means faster feedback loops
3. **Clarity** - The AI must understand what it's writing
4. **Consistency** - Same patterns, same results, every time

MAINFRAME delivers all four:

- **850+ tested functions** eliminate edge cases and bugs
- **Zero dependencies** means no "is jq installed?" failures mid-script
- **Intuitive naming** (`json_object`, `csv_row`, `git_branch`) lets AI write correct code immediately
- **One source line** gives instant access to everything

### The Result

Your AI stops writing fragile, verbose bash and starts writing **production-quality scripts** that:

- Generate JSON without jq
- Parse CSV without awk
- Manipulate dates without GNU date quirks
- Make HTTP requests, hash data, manage processes
- Work identically on macOS, Linux, containers, CI/CD

**MAINFRAME transforms your AI from a bash novice into a bash expert** - instantly, reliably, every time.

*"Knowing Your Shell is half the battle."* - G.I. Joe

---

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create a feature branch
3. Add tests for new functions
4. Submit a pull request

---

## License

MIT License - Use freely in your projects. See [LICENSE](LICENSE).

---

<div align="center">

## ★ YO JOE! ★

*"Knowing Your Shell is half the battle."*

**[⬇️ Install Now](#quick-start-30-seconds)** • **[📖 Full Docs](INSTALL.md)** • **[🐛 Report Issues](https://github.com/gtwatts/mainframe/issues)**

---

**850+ functions** | **Zero dependencies** | **20-72x faster** | **Pure Bash**

*Made with ❤️ for AI coding assistants everywhere*

</div>

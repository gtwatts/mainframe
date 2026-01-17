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
           G.I. JOE: A REAL AMERICAN HERO
      "Knowing Your Shell is half the battle."
```

<div align="center">

### Give Your AI Coding Assistant **BASH SUPERPOWERS**

**400+ Pure Bash Functions** | **Zero Dependencies** | **20-72x Faster**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash 4.0+](https://img.shields.io/badge/bash-4.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Pure Bash](https://img.shields.io/badge/dependencies-zero-blue.svg)](https://github.com/gtwatts/mainframe)
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

One line of code gives your AI instant access to **400+ battle-tested functions**:

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

### 11 Libraries, 400+ Functions

| Library | Functions | What It Does |
|---------|-----------|--------------|
| **common.sh** | 51 | Logging, errors, validation, colors |
| **pure-string.sh** | 34 | String ops without sed/awk |
| **pure-array.sh** | 33 | Array ops without external tools |
| **pure-util.sh** | 55 | UUID, timestamps, validation |
| **pure-file.sh** | 37 | File ops without cat/head/tail |
| **json.sh** | 20 | JSON generation (no jq needed) |
| **semver.sh** | 20 | Semantic versioning |
| **ansi.sh** | 90 | Terminal colors & UI |
| **async.sh** | 26 | Async/parallel execution |
| **args.sh** | 18 | Argument parsing |
| **config.sh** | 13 | Config file handling |

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

---

## Project Structure

```
mainframe/
├── lib/                    # Core libraries (400+ functions)
│   ├── common.sh          # Main entry point (auto-sources others)
│   ├── pure-string.sh     # String manipulation
│   ├── pure-array.sh      # Array operations
│   ├── pure-util.sh       # Utilities
│   ├── pure-file.sh       # File operations
│   ├── json.sh            # JSON generation
│   ├── semver.sh          # Semantic versioning
│   ├── ansi.sh            # Terminal colors & UI
│   ├── async.sh           # Async/parallel execution
│   ├── args.sh            # Argument parsing
│   └── config.sh          # Config file handling
├── scripts/               # Ready-to-use scripts
│   ├── env/              # Environment checks
│   ├── validation/       # Input validation
│   ├── debug/            # Debugging tools
│   └── agent/            # AI agent utilities
├── tests/                 # BATS test suite
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

That's what this toolkit does for AI coding assistants. **It makes bash dance.**

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

**400+ functions** | **Zero dependencies** | **20-72x faster** | **Pure Bash**

*Made with ❤️ for AI coding assistants everywhere*

</div>

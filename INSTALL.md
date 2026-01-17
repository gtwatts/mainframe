# MAINFRAME Installation Guide

```
╔══════════════════════════════════════════════════════════════════╗
║ ★ ★ ★ ═══════════════════════════════════════════════════════════║
║ ★ ★ ★  __  __   _   ___ _  _ ___ ___    _   __  __ ___           ║
║ ★ ★ ★ |  \/  | /_\ |_ _| \| | __| _ \  /_\ |  \/  | __|          ║
║ ═════ | |\/| |/ _ \ | || .` | _||   / / _ \| |\/| | _|           ║
║ ═════ |_|  |_/_/ \_\___|_|\_|_| |_|_\/_/ \_\_|  |_|___|          ║
║ ═════                                                            ║
║           "Knowing Your Shell is half the battle."               ║
╚══════════════════════════════════════════════════════════════════╝
                        ★ YO JOE! ★
```

## What is MAINFRAME?

MAINFRAME is a **superpower multiplier for Claude Code**. It provides **366+ pure bash functions** that give Claude Code instant access to:

- String manipulation (no sed/awk needed)
- Array operations (no external tools)
- JSON generation (no jq dependency)
- Async/parallel execution
- Terminal UI (colors, progress bars)
- Semantic versioning
- Input validation
- And much more...

**Benchmarked speedup: 20-70x faster than external tools.**

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
mainframe --version

# Or test a function
source ~/.mainframe/lib/common.sh
echo "Result: $(trim_string '  hello world  ')"
# Output: Result: hello world
```

---

## Using MAINFRAME with Claude Code

### Method 1: In Your Scripts

When Claude Code generates bash scripts, add this at the top:

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Now you have 366+ functions available!
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

## What You Get

### Libraries (auto-loaded with common.sh)

| Library | Functions | Purpose |
|---------|-----------|---------|
| `pure-string.sh` | 34 | String manipulation without sed/awk |
| `pure-array.sh` | 33 | Array operations without external tools |
| `pure-util.sh` | 55 | Utilities (UUID, timestamps, validation) |
| `pure-file.sh` | 37 | File ops without cat/head/tail |
| `json.sh` | 20 | JSON generation in pure bash |
| `semver.sh` | 20 | Semantic versioning |
| `ansi.sh` | 90 | Terminal colors and UI |
| `async.sh` | 26 | Async/parallel execution |
| `common.sh` | 51 | Core utilities & logging |

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/env/has.sh` | Check if commands exist |
| `scripts/validation/validate-input.sh` | Input validation |
| `scripts/debug/debug-script.sh` | Script debugging |

### Benchmarks

Run the superpower benchmarks:

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

1. **Generate JSON** → It uses `json_object` instead of complex escaping
2. **Process arrays** → It uses `array_*` functions instead of loops
3. **Handle strings** → It uses `trim_string`, `to_lower` instead of sed/awk
4. **Show progress** → It uses `progress_bar`, `spinner` for UX
5. **Validate input** → It uses built-in validators

**Result: Cleaner code, faster execution, zero dependencies.**

---

## Uninstall

```bash
rm -rf ~/.mainframe
# Remove the source lines from ~/.bashrc
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - Use freely in your projects.

---

**YO JOE!** 🎖️

*MAINFRAME - Superpower multiplier for Claude Code*

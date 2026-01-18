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

### 26 Libraries, 950+ Functions

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
| **k8s.sh** | 52 | Kubernetes kubectl wrapper with sane defaults |
| **env.sh** | 36 | Environment variables & dotenv |
| **path.sh** | 30 | Cross-platform path manipulation |
| **validation.sh** | 34 | Input validation & sanitization |
| **pipe.sh** | 39 | Unix pipeline processing |
| **stream.sh** | 28 | Advanced stream paradigms |
| **error.sh** | 25 | Try/catch, stack traces, error context |
| **compat.sh** | 45 | BSD/GNU cross-platform compatibility |
| **log.sh** | 30 | Structured JSON logging with levels & rotation |
| **cli.sh** | 35 | Declarative CLI framework with auto-help |
| **ci.sh** | 35 | CI/CD portability for GitHub, GitLab, Jenkins, CircleCI, Travis, Azure |
| **template.sh** | 30 | Mustache-style template engine with conditionals & loops |

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

### Template Engine (NEW in v2.2)
```bash
# Variable substitution
template::render "Hello {{name}}!" name="World"  # Hello World!

# With defaults
template::render "Port: {{PORT:-8080}}"          # Port: 8080

# Conditionals
template::render '{{#if DEBUG}}[DEBUG]{{/if}} msg' DEBUG=true   # [DEBUG] msg
template::render '{{#unless PROD}}DEV{{/unless}}' PROD=false    # DEV

# Loops
template::render '{{#each ITEMS}}[{{.}}]{{/each}}' ITEMS="a b c"  # [a][b][c]

# Built-in helpers
template::render '{{upper name}}' name="hello"        # HELLO
template::render '{{lower name}}' name="HELLO"        # hello
template::render '{{env HOME}}'                       # /home/user
template::render '{{now}}'                            # 2026-01-18 09:30:00
template::render '{{uuid}}'                           # 550e8400-e29b-...

# Partials (reusable snippets)
template::partial "header" '<h1>{{title}}</h1>'
template::render '{{>header}}' title="Welcome"        # <h1>Welcome</h1>

# Render from file
template::render_file "config.tpl" HOST=localhost PORT=8080 > config.yaml
```

### Docker & Containers (NEW in v2.1)
```bash
docker_is_running                 # Check Docker daemon
docker_image_exists "nginx"       # Check if image exists
docker_container_logs "app" 50    # Get last 50 log lines
compose_up "docker-compose.yml"   # Start compose stack
compose_status                    # Show running services
```

### Kubernetes (NEW in v2.3)
```bash
# Context & namespace management
k8s::context "prod-cluster"       # Switch cluster context
k8s::namespace "my-app"           # Set namespace for commands
k8s::current_context              # Get current context

# Pod operations
k8s::wait_ready "deployment/app" --timeout 300
k8s::pods "app=my-app"            # List pods by selector
k8s::logs "my-pod" --follow       # Stream pod logs
k8s::exec "my-pod" -- bash        # Exec into pod

# Port forwarding with cleanup
k8s::port_forward "svc/api" 8080:80
k8s::cleanup_on_exit              # Auto-cleanup on script exit

# Secrets & ConfigMaps
k8s::secret_get "my-secret" "password"
k8s::secret_set "my-secret" "key" "value"
k8s::configmap_get "my-config" "setting"

# Rollout management
k8s::rollout_restart "deployment/app"
k8s::rollout_status "deployment/app"
k8s::rollout_undo "deployment/app"

# Resource queries
k8s::get_image "deployment/app"   # Get container image
k8s::get_replicas "deployment/app"
k8s::scale "deployment/app" 5     # Scale to 5 replicas
```

### CI/CD Portability (NEW in v2.2)
```bash
# Detection - works on GitHub, GitLab, Jenkins, CircleCI, Travis, Azure
ci::is_ci && echo "Running in CI"
ci::detect                        # github, gitlab, jenkins, circleci, travis, azure, none
ci::name                          # "GitHub Actions", "GitLab CI", etc.

# Cross-platform output (works everywhere)
ci::set_output "version" "1.2.3"  # Set step output
ci::set_env "BUILD_TAG" "v1.2.3"  # Set env for next steps
ci::add_path "/custom/bin"        # Add to PATH

# Collapsible log groups
ci::group_start "Running tests"
  npm test
ci::group_end

# PR/MR detection
ci::is_pull_request && echo "This is a PR"
ci::pr_number                     # 123
ci::pr_branch                     # feature/my-branch
ci::pr_target                     # main

# Git info in CI
ci::commit_sha                    # Full SHA
ci::commit_short                  # 7-char SHA
ci::branch                        # Current branch
ci::tag                           # Tag name (if tag build)

# Artifacts with checksums
ci::artifact_create "dist/" "my-build"  # Creates .tar.gz + .sha256
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

### BSD/GNU Compatibility (NEW in v2.3)
```bash
source "$MAINFRAME_ROOT/lib/compat.sh"

# OS detection (cached for performance)
compat::get_os          # Returns: macos, linux, freebsd, etc.
compat::is_macos && echo "macOS"
compat::is_linux && echo "Linux"
compat::is_bsd && echo "BSD variant"

# Portable sed (works on macOS AND Linux)
compat::sed_inplace file 's/old/new/g'   # In-place edit
compat::sed_extended 's/(foo)/\1bar/'    # Extended regex

# Portable grep
compat::grep_extended '(foo|bar)' file   # ERE support
compat::grep_perl '\bword\b' file        # PCRE with fallback

# Portable date arithmetic
compat::date_format '%Y-%m-%d' "$timestamp"
compat::date_add_days 7                  # Add days
compat::date_sub_days 3                  # Subtract days

# Portable stat
compat::stat_size file                   # File size in bytes
compat::stat_mtime file                  # Modification time
compat::stat_perms file                  # Permissions (644, 755)

# Cross-platform utilities
compat::realpath "./relative/path"       # Canonical path
compat::base64_encode "data"             # Encode
compat::base64_decode "$encoded"         # Decode
compat::sha256 file                      # SHA256 hash
compat::clipboard_copy "text"            # Copy to clipboard
compat::open "https://example.com"       # Open with default app
```

### Structured Logging (NEW in v2.4)
```bash
source "$MAINFRAME_ROOT/lib/log.sh"

# Basic logging with levels
log::debug "Debug message"
log::info "Info message"
log::warn "Warning message"
log::error "Error message"
log::fatal "Fatal error"              # Also exits

# JSON structured logging
log::json "info" "User logged in" user_id=123 ip="1.2.3.4" action="login"
# Output: {"level":"info","msg":"User logged in","user_id":123,"ip":"1.2.3.4","action":"login","timestamp":"2026-01-18T14:30:00Z"}

# Configure logging
log::set_level "debug"                # debug, info, warn, error
log::set_format "json"                # json, text, pretty
log::set_output "/var/log/app.log"    # File or stdout
log::set_context app="myapp" env="prod"  # Persistent fields

# Timing/Performance
log::time_start "operation"
# ... do work ...
log::time_end "operation"             # Logs duration automatically

# Time a command directly
log::time "api_call" curl -s https://api.example.com

# Log rotation
log::rotate "/var/log/app.log" --max-size 10M --keep 5
log::needs_rotation "/var/log/app.log" 10M && log::rotate ...

# Utility functions
log::infof "User %s logged in from %s" "$user" "$ip"  # Printf-style
log::trace "Something happened"       # Includes caller info
log::env                              # Logs bash/user/pwd info
```

### Health Check Framework (NEW in v2.6)
```bash
source "$MAINFRAME_ROOT/lib/health.sh"

# Register health checks
health::register "database" 'pg_isready -h localhost'
health::register "redis" 'redis-cli ping'
health::register "api" 'curl -sf http://localhost:8080/health'
health::register "disk" 'health::check_disk / 90'      # 90% threshold
health::register "memory" 'health::check_memory 80'    # 80% threshold

# Run health checks
health::run_all                     # Run all registered checks
health::run "database"              # Run specific check
health::status                      # JSON status of all checks

# Check health state
health::is_ready && echo "All systems go!"   # All checks pass
health::is_live && echo "At least one OK"    # Any check passes

# Built-in checks
health::check_http "http://localhost:8080/health"  # HTTP endpoint
health::check_tcp "localhost" 5432                 # TCP connection
health::check_disk "/" 90                          # Disk usage threshold
health::check_memory 80                            # Memory usage threshold
health::check_process "nginx"                      # Process running
health::check_file_exists "/var/run/app.pid"       # File exists
health::check_port_open 8080                       # Port listening
health::check_command "docker"                     # Command available
health::check_http_content "http://..." "OK"       # HTTP content match

# JSON status output
health::status
# {"status":"healthy","checks":{"database":{"status":"healthy","message":"OK",...},...}}

# Human-readable output
health::print
# CHECK                STATUS     MESSAGE
# database             healthy    OK
# redis                healthy    PONG
# disk                 healthy    Disk 45% used (threshold: 90%)

# Start HTTP health server (Kubernetes-ready)
health::serve 8081  # Runs in foreground
# GET /health       - Full JSON status
# GET /health/live  - Liveness probe (200 if any check passes)
# GET /health/ready - Readiness probe (200 if all checks pass)

# Continuous monitoring
health::watch --interval 30 --on-failure 'notify admin@example.com' --verbose
```

### Declarative CLI Framework (NEW in v2.5)
```bash
source "$MAINFRAME_ROOT/lib/cli.sh"

# Define your CLI declaratively
cli::name "deploy"
cli::version "1.0.0"
cli::description "Deploy application to servers"

# Flags (boolean options)
cli::flag "verbose" "v" "Enable verbose output"
cli::flag "dry-run" "n" "Show what would be done"

# Options (with values)
cli::option "env" "e" "Target environment" "staging"
cli::option "replicas" "r" "Number of replicas" "3"

# Positional arguments
cli::positional "app" "Application name" required
cli::positional "version" "Version to deploy" optional

# Subcommands
cli::subcommand "init" "Initialize deployment config"
cli::subcommand "rollback" "Rollback to previous version"

# Type validation
cli::validate_type "replicas" positive

# Examples for --help
cli::example "deploy myapp 1.0.0 -e production"
cli::example "deploy --dry-run myapp"

# Parse and validate
cli::parse "$@"
cli::validate_required
cli::validate

# Access values via CLI_* variables or functions
if cli::is "verbose"; then
    echo "Deploying $CLI_app to $CLI_env"
fi

# Or use accessor functions
env=$(cli::get env)
replicas=$(cli::get replicas)

# Check which subcommand was used
if cli::is_subcommand "rollback"; then
    rollback_deployment
fi

# Auto-generated help (--help / -h)
# Usage: deploy <command> [options] <app> [version]
#
# Deploy application to servers
#
# Commands:
#   init              Initialize deployment config
#   rollback          Rollback to previous version
#
# Options:
#   -v, --verbose     Enable verbose output
#   -n, --dry-run     Show what would be done
#   -e, --env <val>   Target environment (default: staging)
#   -r, --replicas    Number of replicas (default: 3)
#   -h, --help        Show this help message
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
│   ├── k8s.sh             # Kubernetes kubectl wrapper (v2.3)
│   ├── env.sh             # Environment vars (v2.1)
│   ├── path.sh            # Path manipulation (v2.1)
│   ├── validation.sh      # Input validation (v2.1)
│   ├── pipe.sh            # Unix pipelines (v2.1)
│   ├── stream.sh          # Stream processing (v2.1)
│   ├── error.sh           # Try/catch & stack traces (v2.2)
│   ├── log.sh             # Structured JSON logging (v2.4)
│   └── health.sh          # Health check framework (v2.6)
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

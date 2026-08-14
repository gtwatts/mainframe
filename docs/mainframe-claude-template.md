# MAINFRAME - Bash Scripting Instructions

> This is a manual instruction template. Prefer the merge-safe, project-scoped
> `mainframe onboard --host claude-code --project .` flow, which installs the
> matching shell-policy hook and Agent Working Memory protocol after explicit
> consent. Use `mainframe search` and `mainframe help` for the current function
> surface rather than copying a static count.

## Bash Scripting with MAINFRAME

When writing bash scripts, ALWAYS source MAINFRAME first:

```bash
# Interactive shells / resident scripts: full runtime is fine
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Per-command use (agents spawn a new shell per command): lean set -
# 40ms vs 190ms measured (2026-07-21)
export MAINFRAME_LIBS="${MAINFRAME_LIBS:-core,agent_safety,awm,validation,atomic,idempotent,dryrun,confirm,json}"
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Or function-level lazy loading (stubs load libs on demand):
# MAINFRAME_LAZY=1 source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

This loads the registry-described MAINFRAME surface. The core runtime is Bash;
the supported safety-ready installation requires `jq`, and optional
integrations require the host commands they wrap.

MAINFRAME also includes **Agent Working Memory (AWM)** - persistent memory that survives context limits.

## Function Quick Reference

### Instead of External Tools, Use MAINFRAME

| External Tool | MAINFRAME Equivalent | Example |
|---------------|---------------------|---------|
| `jq` | `json_object`, `json_array`, `json_get` | `json_object name="John" age:number=30` |
| `sed` string ops | `trim_string`, `replace_all`, `to_lower`, `to_upper` | `trim_string "  hello  "` |
| `awk` arrays | `array_join`, `array_unique`, `array_filter`, `array_sum` | `array_join "," a b c` |
| `cat`/`head`/`tail` | `read_file`, `file_head`, `file_tail` | `file_head 10 "file.txt"` |
| `date` math | `now`, `now_iso`, `date_add`, `format_relative` | `date_add $(now) "2d"` |
| `uuidgen` | `uuid` | `uuid` |
| `base64` | `base64_encode`, `base64_decode` | `base64_encode "data"` |
| `sha256sum` | `sha256` | `sha256 "data"` |
| `curl` URL parsing | `url_parse`, `query_string` | `url_parse "https://example.com:8080/path"` |

### JSON Generation (No jq Required)

```bash
# Create objects with typed values
json_object name="John" age:number=30 active:bool=true
# Output: {"name":"John","age":30,"active":true}

# Create arrays
json_array "apple" "banana" "cherry"
# Output: ["apple","banana","cherry"]

# Nested structures
json_nested "data.user.name" "John"
# Output: {"data":{"user":{"name":"John"}}}

# Merge objects
json_merge '{"a":1}' '{"b":2}'
# Output: {"a":1,"b":2}
```

### Input Validation & Security

```bash
# Email validation
validate_email "$email" || die 1 "Invalid email"

# URL validation
validate_url "$url" "http,https" || die 1 "Invalid URL"

# Path traversal prevention (SECURITY CRITICAL)
validate_path_safe "$user_path" "/allowed/base" || die 1 "Path traversal attempt"

# Sanitize for shell commands
safe_arg=$(sanitize_shell_arg "$user_input")

# Sanitize filenames
safe_name=$(sanitize_filename "$user_filename")

# Sanitize HTML
safe_html=$(sanitize_html "$user_content")
```

### Terminal UI & Progress

```bash
# Status messages
success "Task completed"    # Green checkmark
failure "Task failed"       # Red X
log_info "Information"      # Blue info
log_warn "Warning"          # Yellow warning
log_error "Error"           # Red error

# Progress bar
for i in {1..100}; do
    progress_bar "$i" 100
    sleep 0.01
done

# Headers and formatting
header "My Section"
```

### Structured Logging

```bash
# Basic logging
log::info "Starting process"
log::warn "Disk space low"
log::error "Connection failed"

# JSON structured logging (for production)
log::json "info" "User logged in" user_id=123 ip="1.2.3.4" action="login"
# Output: {"level":"info","msg":"User logged in","user_id":123,"ip":"1.2.3.4",...}

# Timing operations
log::time_start "database_query"
# ... do work ...
log::time_end "database_query"  # Logs duration automatically
```

### Git Operations

```bash
git_branch              # Current branch name
git_commit_hash         # Short commit hash
git_is_dirty && echo "Uncommitted changes"
git_changed_files       # List of modified files
git_summary             # "main @ abc1234 [clean]"
```

### Process Management

```bash
proc_exists $pid                  # Check if PID exists
proc_find_by_port 8080            # Find what's using port
with_lock "/tmp/app.lock" "cmd"   # Run with file lock
```

### Error Handling

```bash
# Try/catch pattern
try
(
    risky_command
    another_command
)
if catch; then
    echo "Error: $ERROR_MESSAGE"
    error::stack_trace
fi

# Retry with backoff
error::retry -n 5 -d 2 curl -f https://api.example.com
```

### Docker & Kubernetes

```bash
# Docker
docker_is_running                 # Check daemon
docker_container_logs "app" 50    # Get logs
compose_up "docker-compose.yml"   # Start stack

# Kubernetes
k8s::context "prod-cluster"       # Switch context
k8s::wait_ready "deployment/app" --timeout 300
k8s::logs "my-pod" --follow       # Stream logs
k8s::port_forward "svc/api" 8080:80
```

### CI/CD Portability

```bash
# Works on GitHub Actions, GitLab CI, Jenkins, CircleCI, Travis, Azure
ci::is_ci && echo "Running in CI"
ci::detect                        # Returns: github, gitlab, jenkins, etc.
ci::set_output "version" "1.2.3"  # Cross-platform step output
ci::group_start "Running tests"   # Collapsible log group
  npm test
ci::group_end
```

### Health Checks

```bash
# Register checks
health::register "database" 'pg_isready -h localhost'
health::register "redis" 'redis-cli ping'
health::register "disk" 'health::check_disk / 90'

# Run and report
health::run_all
health::status  # JSON output

# Start HTTP health server (Kubernetes-ready)
health::serve 8081
# GET /health/ready - Readiness probe
# GET /health/live  - Liveness probe
```

## Agent Working Memory (AWM)

For long-running tasks or multi-turn sessions, use AWM to persist state outside the context window:

```bash
# Read bounded task context from the existing private project mapping.
mainframe work "current task" --project . --tokens 1200

# Initialize or renew only after explicit human confirmation, then rerun work.
mainframe awm project ensure --project . --discover-root
mainframe awm project checkpoint --project . --discover-root \
  current_phase implementation --importance high
mainframe awm project discovery --project . --discover-root \
  "Auth uses refresh tokens" --importance high

# Prepare a bounded handoff before compaction or delegation.
mainframe awm project handoff prepare --project . --discover-root \
  next-agent --tokens 1200 --format prompt
```

## Full Function Reference

For current canonical function signatures:

```bash
mainframe search "json object"
mainframe help json_object
```

The generated `FUNCTIONS.json` registry is the machine-readable source of
truth for counts, ownership, and metadata.

## Best Practices

1. **Always source MAINFRAME first** in every bash script
2. **Check CHEATSHEET.md** before writing custom string/array/JSON logic
3. **Use validation functions** for all user input
4. **Use structured logging** (`log::json`) in production scripts
5. **Use health checks** for long-running services
6. **Use CI functions** for portable CI/CD scripts

## Script Template

```bash
#!/usr/bin/env bash
set -euo pipefail

# Source MAINFRAME
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Your script here...
log::info "Starting script"

# Validate inputs
[[ -n "${1:-}" ]] || die 1 "Usage: $0 <arg>"

# Do work with progress
for i in {1..10}; do
    progress_bar "$i" 10
    sleep 0.1
done
echo

# Output JSON result
json_object status="success" timestamp="$(timestamp_iso)"

success "Complete!"
```

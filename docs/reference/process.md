# Process Functions

Process management, async operations, and safety utilities.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## Process Functions (proc.sh)

### Process Information

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `proc_exists` | `proc_exists pid` | `proc_exists $$` | (returns 0/1) |
| `proc_name` | `proc_name pid` | `proc_name $$` | `bash` |
| `proc_cmd` | `proc_cmd pid` | `proc_cmd $$` | Full command line |
| `proc_parent` | `proc_parent pid` | `proc_parent $$` | Parent PID |
| `proc_children` | `proc_children pid` | `proc_children $$` | Child PIDs |
| `proc_tree` | `proc_tree pid` | `proc_tree $$` | Process tree |
| `proc_user` | `proc_user pid` | `proc_user $$` | `gordon` |
| `proc_memory` | `proc_memory pid` | `proc_memory $$` | Memory in KB |
| `proc_cpu` | `proc_cpu pid` | `proc_cpu $$` | CPU percentage |
| `proc_threads` | `proc_threads pid` | `proc_threads $$` | Thread count |

### Process Discovery

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `proc_find_by_name` | `proc_find_by_name "name"` | `proc_find_by_name "node"` | PIDs |
| `proc_find_by_port` | `proc_find_by_port port` | `proc_find_by_port 8080` | PID |
| `proc_find_by_user` | `proc_find_by_user "user"` | `proc_find_by_user "root"` | PIDs |

### PID Files

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `pidfile_create` | `pidfile_create "file"` | `pidfile_create "/tmp/app.pid"` | Creates PID file |
| `pidfile_read` | `pidfile_read "file"` | `pidfile_read "/tmp/app.pid"` | PID value |
| `pidfile_check` | `pidfile_check "file"` | `pidfile_check "/tmp/app.pid"` | (returns 0/1) |
| `pidfile_remove` | `pidfile_remove "file"` | `pidfile_remove "/tmp/app.pid"` | Removes file |

### Lock Files

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `lockfile_acquire` | `lockfile_acquire "file" [timeout]` | `lockfile_acquire "/tmp/app.lock"` | (returns 0/1) |
| `lockfile_release` | `lockfile_release "file"` | `lockfile_release "/tmp/app.lock"` | Releases lock |
| `with_lock` | `with_lock "file" "command"` | `with_lock "/tmp/l" "do_work"` | Runs with lock |

### Process Control

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `proc_signal` | `proc_signal pid "signal"` | `proc_signal $pid "TERM"` | Sends signal |
| `proc_kill` | `proc_kill pid` | `proc_kill $pid` | SIGTERM |
| `proc_kill_force` | `proc_kill_force pid` | `proc_kill_force $pid` | SIGKILL |
| `proc_kill_tree` | `proc_kill_tree pid` | `proc_kill_tree $pid` | Kills tree |
| `proc_wait` | `proc_wait pid` | `proc_wait $pid` | Waits for exit |
| `proc_wait_timeout` | `proc_wait_timeout pid secs` | `proc_wait_timeout $pid 30` | Waits with timeout |

### System Stats

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `proc_count` | `proc_count` | `proc_count` | Total processes |
| `proc_load` | `proc_load` | `proc_load` | Load average |
| `proc_uptime` | `proc_uptime` | `proc_uptime` | Uptime in seconds |
| `proc_uptime_human` | `proc_uptime_human` | `proc_uptime_human` | `5 days, 3 hours` |

---

## Async Functions (async.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `parallel` | `parallel cmd1 cmd2 ...` | `parallel "task1" "task2"` | (runs in parallel) |
| `parallel_limit` | `parallel_limit n cmds...` | `parallel_limit 4 "${tasks[@]}"` | (limited concurrency) |
| `retry` | `retry count cmd` | `retry 3 "curl url"` | (retries on failure) |
| `set_timeout` | `set_timeout secs cmd` | `set_timeout 5 "task"` | (runs after delay) |
| `debounce` | `debounce ms cmd` | `debounce 100 "save"` | (debounced call) |

---

## Retry / Timeout / Circuit Breaker (retry.sh)

### Retry

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `retry` | `retry [opts] cmd [args]` | `retry --max-attempts 5 --backoff exponential curl -sf http://api.com` | Retry with configurable backoff |
| `retry_simple` | `retry_simple N cmd [args]` | `retry_simple 3 curl -sf http://example.com` | Simple retry (exponential backoff) |

**Options**: `--max-attempts N`, `--delay SECONDS`, `--backoff linear|exponential|fixed`, `--max-delay SECONDS`, `--jitter`, `--on-retry "callback"`

### Timeout

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `with_timeout` | `with_timeout SECONDS cmd [args]` | `with_timeout 30 curl -sf http://slow-api.com` | Run with timeout (returns 124 on timeout) |
| `did_timeout` | `did_timeout` | `with_timeout 5 cmd; did_timeout && echo "timed out"` | Check if last with_timeout timed out |

### Circuit Breaker

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `circuit_breaker_init` | `circuit_breaker_init "name" [opts]` | `circuit_breaker_init "redis" --threshold 3 --timeout 30` | Initialize breaker |
| `circuit_breaker_call` | `circuit_breaker_call "name" cmd [args]` | `circuit_breaker_call "redis" redis-cli ping` | Execute through breaker |
| `circuit_breaker_state` | `circuit_breaker_state "name"` | `state=$(circuit_breaker_state "redis")` | Query: closed/open/half-open |
| `circuit_breaker_reset` | `circuit_breaker_reset "name"` | `circuit_breaker_reset "redis"` | Force reset to closed |

**Options**: `--threshold N` (default: 5), `--timeout SECONDS` (default: 60)

### Polling / Wait

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `wait_for` | `wait_for [opts] cmd [args]` | `wait_for --timeout 60 --interval 2 curl -sf http://localhost:8080/health` | Poll until condition true |
| `wait_for_file` | `wait_for_file "path" [timeout]` | `wait_for_file "/var/run/app.pid" 10` | Wait for file to exist |
| `wait_for_port` | `wait_for_port HOST PORT [timeout]` | `wait_for_port localhost 8080 60` | Wait for TCP port to open |

### Rate Limiter

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `rate_limit_init` | `rate_limit_init "name" --rate N --per S` | `rate_limit_init "api" --rate 10 --per 60` | Initialize token bucket |
| `rate_limit_acquire` | `rate_limit_acquire "name" [--no-wait]` | `rate_limit_acquire "api"` | Acquire token |
| `rate_limit_reset` | `rate_limit_reset "name"` | `rate_limit_reset "api"` | Reset to full bucket |

---

## Safe Execution Functions (safe.sh)

### Strict Mode Management

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `enable_strict_mode` | `enable_strict_mode` | `enable_strict_mode` | Enable -euo pipefail |
| `disable_strict_mode` | `disable_strict_mode` | `disable_strict_mode` | Restore previous options |
| `is_strict_mode` | `is_strict_mode` | `is_strict_mode && echo "strict"` | Check if strict mode |

### Unsafe Execution

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `unsafe_run` | `unsafe_run "cmd"` | `unsafe_run "grep pattern file"` | Run without triggering errexit |
| `safe_exit_code` | `safe_exit_code "cmd"` | `safe_exit_code "test -f x"` | Capture exit code in SAFE_EXIT_CODE |

### Output Capture

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `capture_both` | `capture_both out err "cmd"` | `capture_both stdout stderr "make"` | Capture stdout and stderr |
| `capture_stdout` | `capture_stdout "cmd"` | `result=$(capture_stdout "date")` | Capture stdout only |
| `capture_stderr` | `capture_stderr "cmd"` | `errors=$(capture_stderr "make")` | Capture stderr only |
| `capture_all` | `capture_all "cmd"` | `log=$(capture_all "npm install")` | Combined stdout+stderr |

### Timeout Execution

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `run_with_timeout` | `run_with_timeout secs "cmd"` | `run_with_timeout 30 "long_task"` | Pure bash timeout |
| `timeout_cmd` | `timeout_cmd secs "cmd"` | `timeout_cmd 10 "curl http://slow-api"` | GNU timeout with fallback |

### Gotcha Prevention

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `default` | `default "var" "fallback"` | `val=$(default "MY_VAR" "none")` | Safe variable with default |
| `require_var` | `require_var "var" [msg]` | `require_var "API_KEY" "API key required"` | Assert variable is set |
| `safe_math` | `safe_math "expr" [default]` | `result=$(safe_math "$a + $b" 0)` | Safe arithmetic |

---

## Quick Patterns

### Process Management
```bash
# Check if running
if proc_exists $pid; then
    echo "Memory: $(proc_memory $pid) KB"
fi

# Find by port
pid=$(proc_find_by_port 8080)

# Run with lock
with_lock "/tmp/myapp.lock" "run_exclusive_task"
```

### Retry Patterns
```bash
# Basic retry with exponential backoff
retry --max-attempts 5 --backoff exponential --jitter curl -sf http://api.com

# Simple 3-attempt retry
retry_simple 3 wget -q http://example.com/file.zip

# Timeout with fallback
if ! with_timeout 30 long_running_task; then
    if did_timeout; then
        echo "Task timed out"
    else
        echo "Task failed"
    fi
fi
```

### Circuit Breaker
```bash
circuit_breaker_init "payment_api" --threshold 3 --timeout 30
if ! circuit_breaker_call "payment_api" curl -sf http://payments/charge; then
    case $? in
        1) echo "Payment failed" ;;
        2) echo "Circuit is OPEN" ;;
    esac
fi
```

### Wait for Service
```bash
wait_for_port localhost 5432 60
wait_for --timeout 30 --interval 2 curl -sf http://localhost:8080/health
```

### Rate Limiting
```bash
rate_limit_init "github_api" --rate 30 --per 60
for repo in "${repos[@]}"; do
    rate_limit_acquire "github_api"
    curl -sf "https://api.github.com/repos/$repo"
done
```

---

## Parallel Execution (parallel.sh)

High-level parallel execution patterns with USOP-compliant JSON output.

### Map Operations

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `parallel_map` | `parallel_map "func" items...` | `parallel_map "curl -s" "${urls[@]}"` | JSON with all results |
| `parallel_map_n` | `parallel_map_n "func" N items...` | `parallel_map_n "process" 4 "${items[@]}"` | JSON with results (max N concurrent) |

### Race / All / Any

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `parallel_race` | `parallel_race cmd1 cmd2 ...` | `parallel_race "curl mirror1" "curl mirror2"` | First to complete wins, cancels others |
| `parallel_all` | `parallel_all cmd1 cmd2 ...` | `parallel_all "check_a" "check_b"` | Wait for all, return all results |
| `parallel_any` | `parallel_any cmd1 cmd2 ...` | `parallel_any "ping host1" "ping host2"` | Any success = overall success |

### Batch Processing

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `parallel_batch` | `parallel_batch [opts] items...` | `parallel_batch --batch-size 5 "${cmds[@]}"` | Process in batches |
| `parallel_sequence` | `parallel_sequence cmd1 cmd2` | `parallel_sequence "step1" "step2"` | Run sequentially (for comparison) |

**Batch Options**: `--batch-size N`, `--command "template"`

### Timeout & Retry

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `parallel_timeout` | `parallel_timeout SECS cmd` | `parallel_timeout 30 "curl slow-api"` | Run with timeout (returns 124 on timeout) |
| `parallel_retry` | `parallel_retry cmd [opts]` | `parallel_retry "curl api" --max-attempts 5` | Retry on failure with backoff |

**Retry Options**: `--max-attempts N`, `--delay SECS`, `--backoff fixed|linear|exponential`

### Progress Reporting

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `parallel_progress` | `parallel_progress cmd1 cmd2 ...` | `parallel_progress "${tasks[@]}"` | Execute with progress bar |

### Output Format (USOP)

All parallel functions return JSON in this format:

```json
{
  "ok": true,
  "data": {
    "results": [
      {"index": 0, "status": "done", "result": "output", "duration_ms": 150},
      {"index": 1, "status": "error", "result": "", "duration_ms": 50, "error": "exit code 1"}
    ],
    "total_duration_ms": 200,
    "succeeded": 1,
    "failed": 1
  }
}
```

### Quick Patterns

```bash
# Process URLs in parallel (unlimited concurrency)
urls=("http://a.com" "http://b.com" "http://c.com")
results=$(parallel_map "curl -s" "${urls[@]}")

# Process with concurrency limit
results=$(parallel_map_n "expensive_operation" 4 "${items[@]}")

# Race multiple mirrors
content=$(parallel_race \
    "curl -s mirror1.com/file" \
    "curl -s mirror2.com/file" \
    "curl -s mirror3.com/file")

# Check all services
health=$(parallel_all "curl -sf svc1/health" "curl -sf svc2/health")

# Any reachable = success
reachable=$(parallel_any "ping -c1 host1" "ping -c1 host2")

# Batch with size limit
parallel_batch --batch-size 10 --command "process_item" "${large_array[@]}"

# Retry flaky endpoint
result=$(parallel_retry "curl -sf http://flaky-api.com" --max-attempts 5 --backoff exponential)

# Execute with progress bar
parallel_progress "task1" "task2" "task3" "task4"
```

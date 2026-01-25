# Bash Tooling Patterns for AI Coding Assistants

**Research Date:** 2026-01-22
**Objective:** Identify bash patterns specifically optimized for AI coding assistants (Claude Code, Cursor, Aider, OpenCode)
**Researcher:** Watson (Claude Opus 4.5)

---

## Executive Summary

This research identifies bash scripting patterns that help AI coding assistants predict outcomes, recover from failures, understand function behavior without reading implementations, and execute operations safely in unknown environments.

**Key Finding:** AI coding assistants need bash libraries that are *self-describing*, *idempotent*, *atomic*, and *observable*. Traditional bash scripts optimize for humans reading code; AI-optimized patterns prioritize machine-parseable contracts and predictable semantics.

**Critical Recommendations:**
1. Adopt Design-by-Contract patterns with explicit preconditions/postconditions
2. Implement idempotent operations with "check-before-act" semantics
3. Use atomic file operations to prevent partial state
4. Provide structured observability (JSON logs, trace IDs, stack traces)
5. Define clear recovery strategies for common failure modes

---

## Part 1: Idempotent Operations

### 1.1 Why Idempotency Matters for AI Agents

AI coding assistants frequently:
- Re-run scripts after context loss
- Retry failed operations without knowing prior state
- Execute the same operation multiple times during iterative debugging

**Definition:** An idempotent operation produces the same result regardless of how many times it's executed.

### 1.2 Core Idempotent Patterns

#### Pattern 1: Check-Before-Act

```bash
# Idempotent directory creation
ensure_dir() {
    local dir="$1"
    [[ -d "$dir" ]] && return 0  # Already exists, success
    mkdir -p "$dir"
}

# Idempotent symlink creation
ensure_symlink() {
    local target="$1"
    local link="$2"

    # Check if link exists and points to correct target
    [[ -L "$link" && "$(readlink "$link")" == "$target" ]] && return 0

    # Remove existing (wrong) link or file
    rm -f "$link"
    ln -sf "$target" "$link"
}
```

#### Pattern 2: Conditional Append

```bash
# Idempotent file append with marker
ensure_line() {
    local file="$1"
    local line="$2"
    local marker="${3:-$line}"

    # Check if line already exists
    grep -qF "$marker" "$file" 2>/dev/null && return 0

    # Append with marker comment
    printf '%s  # MANAGED_BY_MAINFRAME\n' "$line" >> "$file"
}
```

#### Pattern 3: Atomic State Transitions

```bash
# Idempotent mount
ensure_mount() {
    local device="$1"
    local mountpoint="$2"

    # Check if already mounted
    mountpoint -q "$mountpoint" && return 0

    mount "$device" "$mountpoint"
}
```

### 1.3 Built-in Idempotent Commands

| Command | Idempotent | Notes |
|---------|------------|-------|
| `mkdir -p` | Yes | Creates only if missing |
| `touch` | Yes | Updates timestamp, creates if missing |
| `cp` | Yes | Overwrites without error |
| `chmod` | Yes | Sets permissions regardless of current state |
| `ln -sf` | Yes | Forces overwrite of existing link |
| `tar -xf` | Yes | Overwrites existing files |
| `mkdir` | No | Fails if directory exists |
| `ln` | No | Fails if link exists |

### 1.4 Recommended Functions for MAINFRAME

```bash
# @description Idempotently ensure a file exists with specific content
# @param path - Target file path
# @param content - Expected content (creates if missing, overwrites if different)
# @return 0 on success, 1 on failure
# @idempotent true
ensure_file() {
    local path="$1"
    local content="$2"

    # Check if file exists with exact content
    if [[ -f "$path" ]]; then
        local current
        current=$(<"$path")
        [[ "$current" == "$content" ]] && return 0
    fi

    # Atomic write via temp file
    local tmpfile
    tmpfile=$(mktemp)
    printf '%s' "$content" > "$tmpfile"
    mv -f "$tmpfile" "$path"
}

# @description Idempotently ensure a package is installed
# @param package - Package name
# @return 0 if installed (or just installed), 1 on failure
# @idempotent true
ensure_package() {
    local package="$1"

    # Check if already installed
    command -v "$package" &>/dev/null && return 0
    dpkg -l "$package" 2>/dev/null | grep -q "^ii" && return 0

    # Install
    apt-get install -y "$package"
}
```

**Sources:**
- [How to write idempotent Bash scripts](https://arslan.io/2019/07/03/how-to-write-idempotent-bash-scripts/)
- [GitHub - metaist/idempotent-bash](https://github.com/metaist/idempotent-bash)
- [13 Bash Functions to Make Your CI Jobs Idempotent](https://medium.com/@obaff/13-bash-functions-to-make-your-ci-jobs-idempotent-27a2fba42fbb)

---

## Part 2: Self-Documenting Code Patterns

### 2.1 Why Self-Documentation Matters for AI

AI coding assistants:
- Cannot easily infer function behavior from implementation
- Need to understand function contracts without reading source
- Benefit from structured metadata over prose documentation

### 2.2 Documentation Patterns

#### Pattern 1: shdoc Annotations

```bash
# @description Trim whitespace from both ends of a string
# @param string - The input string to trim
# @return string - Trimmed string (stdout)
# @exitcode 0 - Always succeeds
# @example
#   trim_string "  hello world  "
#   # Output: "hello world"
trim_string() {
    local var="$1"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}
```

#### Pattern 2: Contract Annotations (AI-Optimized)

```bash
# @name json_object
# @brief Create a JSON object from key=value pairs
# @contract
#   precondition: At least one argument provided
#   postcondition: Returns valid JSON object
#   invariant: Output can be parsed by any JSON parser
#   idempotent: true (same inputs always produce same output)
#   pure: true (no side effects)
# @param key=value - String key-value pairs
# @param key:type=value - Typed values (number, bool, null)
# @return JSON object string
# @errors
#   Invalid type modifier returns malformed JSON
# @example
#   json_object name=John age:number=30 active:bool=true
#   # {"name":"John","age":30,"active":true}
json_object() {
    # ... implementation
}
```

#### Pattern 3: Heredoc Self-Documentation

```bash
#!/usr/bin/env bash
: << 'DOCUMENTATION'
# Script: backup.sh
# Purpose: Create incremental backups of specified directories
#
# USAGE:
#   backup.sh [OPTIONS] SOURCE... DEST
#
# OPTIONS:
#   -n, --dry-run    Show what would be backed up
#   -v, --verbose    Increase output verbosity
#   -c, --compress   Compress backup with gzip
#
# EXAMPLES:
#   backup.sh /home/user /backup
#   backup.sh -c /var/log /archive
#
# EXIT CODES:
#   0  Success
#   1  Invalid arguments
#   2  Source not found
#   3  Destination not writable
DOCUMENTATION
```

### 2.3 Recommended Annotation Standard for MAINFRAME

```bash
# =============================================================================
# @name function_name
# @brief One-line description
# @description
#   Multi-line detailed description if needed.
# =============================================================================
# @contract
#   precondition:  [conditions that must be true before calling]
#   postcondition: [conditions guaranteed true after success]
#   idempotent:    [true|false]
#   pure:          [true|false - no side effects]
# =============================================================================
# @param name - description (default: value)
# @return description of stdout
# @exitcode 0 - Success condition
# @exitcode 1 - Failure condition
# =============================================================================
# @example
#   function_name "arg1" "arg2"
#   # Expected output
# =============================================================================
```

**Sources:**
- [GitHub - reconquest/shdoc](https://github.com/reconquest/shdoc)
- [Heredocs Can Make Your Bash Scripts Self-Documenting](https://holdtherobot.com/blog/heredocs-can-make-your-bash-scripts-self-documenting/)
- [BashSupport Pro Documentation](https://www.bashsupport.com/manual/editor/documentation/)

---

## Part 3: Predictable Return Semantics

### 3.1 The Problem

Bash functions can communicate results through:
- Exit codes (0-255)
- stdout output
- stderr output
- Global variables

AI assistants struggle when functions mix these inconsistently.

### 3.2 Recommended Conventions

#### Exit Code Standards

| Code | Meaning | AI Interpretation |
|------|---------|-------------------|
| 0 | Success | Operation completed |
| 1 | General failure | Retry may help |
| 2 | Invalid arguments | Fix inputs, don't retry |
| 3 | Precondition failed | Check environment |
| 4 | Resource unavailable | Wait and retry |
| 5 | Timeout | Retry with longer timeout |
| 126 | Command not executable | Permission issue |
| 127 | Command not found | Install dependency |

#### Return Value Patterns

```bash
# Pattern 1: Boolean check (exit code only)
# @return 0 if valid, 1 if invalid
validate_email() {
    [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

# Pattern 2: Data return (stdout)
# @return Trimmed string to stdout
trim_string() {
    local var="$1"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

# Pattern 3: Structured return (JSON stdout)
# @return JSON object with status, data, and error fields
api_call() {
    local url="$1"
    local response

    if response=$(curl -sf "$url"); then
        printf '{"status":"success","data":%s}' "$response"
        return 0
    else
        printf '{"status":"error","error":"Request failed","code":%d}' "$?"
        return 1
    fi
}

# Pattern 4: Multiple outputs via nameref
# @param result_var - Variable name to store result
# @return Populates result_var with value
parse_url() {
    local url="$1"
    local -n result="$2"  # nameref

    result[scheme]="${url%%://*}"
    result[host]="${url#*://}"
    result[host]="${result[host]%%/*}"
    # ...
}
```

### 3.3 AI-Friendly Error Messages

```bash
# Pattern: Structured error reporting
error_report() {
    local code="$1"
    local message="$2"
    local context="${3:-}"

    printf '{"error":{"code":%d,"message":"%s","context":"%s","timestamp":"%s","function":"%s","line":%d}}\n' \
        "$code" \
        "$message" \
        "$context" \
        "$(date -Iseconds)" \
        "${FUNCNAME[1]:-main}" \
        "${BASH_LINENO[0]:-0}" >&2
}
```

**Sources:**
- [Understanding Exit Codes in Bash Scripting](https://medium.com/@gudisagebi1/understanding-exit-codes-in-bash-scripting-699ce918a9c8)
- [Exit Status - Bash Reference Manual](https://www.gnu.org/software/bash/manual/html_node/Exit-Status.html)
- [Bash Function Return Values](https://labex.io/tutorials/shell-bash-function-return-values-391153)

---

## Part 4: Atomic Operations

### 4.1 Why Atomicity Matters

AI agents may be interrupted mid-operation. Atomic operations ensure:
- No partial state left behind
- Either complete success or complete failure
- Safe for concurrent execution

### 4.2 Atomic Patterns

#### Pattern 1: Atomic File Write (Write-Rename)

```bash
# @description Atomically write content to file
# @contract
#   postcondition: File contains exact content or is unchanged
#   atomic: true
atomic_write() {
    local path="$1"
    local content="$2"
    local dir
    dir=$(dirname "$path")

    # Create temp file in same directory (ensures same filesystem)
    local tmpfile
    tmpfile=$(mktemp -p "$dir" .atomic.XXXXXX)

    # Write to temp file
    printf '%s' "$content" > "$tmpfile"

    # Atomic rename
    mv -f "$tmpfile" "$path"
}
```

#### Pattern 2: Atomic Directory Creation

```bash
# @description Atomically create exclusive directory (lock pattern)
# @return 0 if created (acquired lock), 1 if exists (lock held)
# @atomic true
atomic_mkdir() {
    local dir="$1"
    mkdir "$dir" 2>/dev/null
}
```

#### Pattern 3: File Locking

```bash
# @description Execute command with exclusive file lock
# @contract
#   precondition: Lock file path must be writable
#   postcondition: Lock released after command completes
with_lock() {
    local lockfile="$1"
    shift

    (
        flock -n 9 || { echo "Lock held by another process" >&2; exit 1; }
        "$@"
    ) 9>"$lockfile"
}
```

#### Pattern 4: Atomic Counter Increment

```bash
# @description Atomically increment counter file
# @return New counter value
atomic_increment() {
    local file="$1"
    local lockfile="${file}.lock"

    (
        flock -x 9
        local current
        current=$(<"$file" 2>/dev/null) || current=0
        ((current++))
        printf '%d' "$current" > "$file"
        printf '%d' "$current"
    ) 9>"$lockfile"
}
```

### 4.3 Safe Delete Pattern

```bash
# @description Safe delete with trash instead of permanent removal
# @contract
#   postcondition: File moved to trash or was already absent
#   recoverable: true
safe_delete() {
    local path="$1"
    local trash_dir="${MAINFRAME_TRASH:-$HOME/.trash}"

    [[ ! -e "$path" ]] && return 0  # Already gone, success

    mkdir -p "$trash_dir"
    local basename
    basename=$(basename "$path")
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    mv "$path" "${trash_dir}/${basename}.${timestamp}"
}
```

**Sources:**
- [Things UNIX can do atomically](https://rcrowley.org/2010/01/06/things-unix-can-do-atomically.html)
- [Atomic Create a File If Not Exists in Bash Script](https://linuxvox.com/blog/atomic-create-file-if-not-exists-from-bash-script/)
- [BashFAQ/045 - Atomic file operations](https://mywiki.wooledge.org/BashFAQ/045)

---

## Part 5: Observability Patterns

### 5.1 Logging for AI Agents

AI agents benefit from structured logs they can parse and understand:

```bash
# Structured logging with JSON
log_json() {
    local level="$1"
    local message="$2"
    shift 2

    local extra=""
    while (($#)); do
        extra+=",\"$1\":\"$2\""
        shift 2
    done

    printf '{"timestamp":"%s","level":"%s","message":"%s","function":"%s","line":%d%s}\n' \
        "$(date -Iseconds)" \
        "$level" \
        "$message" \
        "${FUNCNAME[1]:-main}" \
        "${BASH_LINENO[0]:-0}" \
        "$extra"
}

log_info()  { log_json "INFO" "$@"; }
log_warn()  { log_json "WARN" "$@"; }
log_error() { log_json "ERROR" "$@"; }
log_debug() { [[ -n "${DEBUG:-}" ]] && log_json "DEBUG" "$@"; }
```

### 5.2 Trace IDs for Distributed Operations

```bash
# Generate trace ID for operation tracking
TRACE_ID="${TRACE_ID:-$(uuidgen 2>/dev/null || printf '%04x%04x-%04x-%04x' $RANDOM $RANDOM $RANDOM $RANDOM)}"

log_with_trace() {
    local level="$1"
    local message="$2"

    printf '{"trace_id":"%s","timestamp":"%s","level":"%s","message":"%s"}\n' \
        "$TRACE_ID" \
        "$(date -Iseconds)" \
        "$level" \
        "$message"
}
```

### 5.3 Stack Traces

MAINFRAME's `error.sh` already implements this pattern excellently:

```bash
# Print stack trace (from MAINFRAME error.sh)
error::stack_trace() {
    local skip="${1:-1}"
    local frame=0

    printf '%s\n' "Stack trace:" >&2

    while true; do
        local func="${FUNCNAME[$((frame + skip))]:-}"
        local line="${BASH_LINENO[$((frame + skip - 1))]:-}"
        local source="${BASH_SOURCE[$((frame + skip))]:-}"

        [[ -z "$func" ]] && break

        printf '  at %s (%s:%s)\n' "$func" "${source##*/}" "$line" >&2
        [[ "$func" == "main" ]] && break
        ((frame++))
    done
}
```

### 5.4 Progress Reporting

```bash
# Progress reporting for long operations
progress_report() {
    local current="$1"
    local total="$2"
    local operation="${3:-Processing}"

    local percent=$((current * 100 / total))

    printf '{"operation":"%s","progress":{"current":%d,"total":%d,"percent":%d}}\n' \
        "$operation" "$current" "$total" "$percent"
}
```

### 5.5 Debugging with set -x

```bash
# Selective debugging for AI agents
debug_section() {
    local name="$1"
    shift

    if [[ -n "${DEBUG:-}" ]]; then
        printf '>>> DEBUG: Entering %s\n' "$name" >&2
        set -x
        "$@"
        local result=$?
        set +x
        printf '<<< DEBUG: Exiting %s (code=%d)\n' "$name" "$result" >&2
        return $result
    else
        "$@"
    fi
}
```

**Sources:**
- [Logging Like a Pro - Shell Script Logger Function](https://dev.to/kartikdudeja21/logging-like-a-pro-a-simple-yet-powerful-logger-function-for-your-shell-scripts-3l0)
- [Fix bugs in Bash scripts by printing a stack trace](https://opensource.com/article/22/7/print-stack-trace-bash-scripts)
- [Mastering Selective Debugging in Bash](https://medium.com/@maheshwar.ramkrushna/mastering-selective-debugging-in-bash-shell-scripts-with-set-x-and-set-x-ef6b7e83fb37)

---

## Part 6: Error Recovery Patterns

### 6.1 Strict Mode as Foundation

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# E: Exit on error
# e: Exit on error (same as E)
# u: Treat unset variables as errors
# o pipefail: Pipeline fails if any command fails
```

### 6.2 Error Trap with Recovery

```bash
# Global error handler with recovery hints
_error_handler() {
    local exit_code=$?
    local command="${BASH_COMMAND}"
    local line="${BASH_LINENO[0]}"

    # Log structured error
    printf '{"error":{"code":%d,"command":"%s","line":%d,"function":"%s","recovery":"%s"}}\n' \
        "$exit_code" \
        "$command" \
        "$line" \
        "${FUNCNAME[1]:-main}" \
        "$(_suggest_recovery "$exit_code" "$command")" >&2
}

_suggest_recovery() {
    local code="$1"
    local cmd="$2"

    case "$code" in
        1)   echo "Check command syntax and arguments" ;;
        2)   echo "Validate input parameters" ;;
        126) echo "Check file permissions (chmod +x)" ;;
        127) echo "Install missing command or check PATH" ;;
        *)   echo "Review error output above" ;;
    esac
}

trap '_error_handler' ERR
```

### 6.3 Retry with Exponential Backoff

MAINFRAME's `error::retry` implements this well:

```bash
# Usage: error::retry -n 5 -d 2 curl -f https://example.com
error::retry() {
    local max_attempts=3
    local delay=1
    local max_delay=60

    # ... (implementation from error.sh)
}
```

### 6.4 Rollback Pattern

```bash
# Track operations for rollback
declare -a _ROLLBACK_STACK=()

rollback_register() {
    _ROLLBACK_STACK+=("$1")
}

rollback_execute() {
    local i
    for ((i = ${#_ROLLBACK_STACK[@]} - 1; i >= 0; i--)); do
        eval "${_ROLLBACK_STACK[$i]}" || true
    done
    _ROLLBACK_STACK=()
}

# Usage example
deploy() {
    # Create backup
    cp config.json config.json.bak
    rollback_register "mv config.json.bak config.json"

    # Modify config
    update_config config.json || { rollback_execute; return 1; }

    # Restart service
    systemctl restart myapp || { rollback_execute; return 1; }

    # Success - clear rollback
    _ROLLBACK_STACK=()
    rm -f config.json.bak
}
```

### 6.5 Guard Clauses

```bash
# Validate all preconditions at function start
deploy_application() {
    # Guard clauses - fail fast
    [[ -z "${APP_NAME:-}" ]] && { error_report 2 "APP_NAME not set"; return 2; }
    [[ -z "${DEPLOY_DIR:-}" ]] && { error_report 2 "DEPLOY_DIR not set"; return 2; }
    [[ ! -d "$DEPLOY_DIR" ]] && { error_report 3 "Deploy directory does not exist"; return 3; }
    [[ ! -w "$DEPLOY_DIR" ]] && { error_report 3 "Deploy directory not writable"; return 3; }
    command -v docker &>/dev/null || { error_report 127 "docker not found"; return 127; }

    # All preconditions met - proceed with main logic
    # ...
}
```

**Sources:**
- [Bulletproof Bash Scripts: Mastering Error Handling](https://karandeepsingh.ca/posts/bash-error-handling-bulletproof-scripts/)
- [Learn Bash error handling by example](https://www.redhat.com/en/blog/bash-error-handling)
- [Unofficial Bash Strict Mode](http://redsymbol.net/articles/unofficial-bash-strict-mode/)
- [Guard clause - KodeKloud Notes](https://notes.kodekloud.com/docs/Advanced-Bash-Scripting/Refresher/Guard-clause)

---

## Part 7: Design-by-Contract for Bash

### 7.1 Contract Components

Inspired by Eiffel's Design by Contract:

1. **Preconditions:** What must be true before the function runs
2. **Postconditions:** What the function guarantees after success
3. **Invariants:** What remains true throughout execution

### 7.2 Implementation Pattern

```bash
# @contract
#   precondition: $1 is a valid directory path
#   precondition: $2 is a non-empty string
#   postcondition: File exists at $1/$2.json
#   postcondition: File contains valid JSON
#   invariant: No other files in $1 are modified
create_config() {
    local dir="$1"
    local name="$2"
    local content="${3:-'{}'}"

    # Precondition checks
    require_dir "$dir" "Directory must exist"
    require_nonempty "$name" "Name must not be empty"
    require_valid_json "$content" "Content must be valid JSON"

    # Main logic
    local path="${dir}/${name}.json"
    atomic_write "$path" "$content"

    # Postcondition checks (optional, for debugging)
    if [[ -n "${MAINFRAME_VERIFY_CONTRACTS:-}" ]]; then
        assert_file_exists "$path"
        assert_valid_json "$(<"$path")"
    fi
}

# Contract helpers
require_dir() {
    [[ -d "$1" ]] || error::throw "$2: $1"
}

require_nonempty() {
    [[ -n "$1" ]] || error::throw "$2"
}

require_valid_json() {
    printf '%s' "$1" | jq empty 2>/dev/null || error::throw "$2"
}
```

### 7.3 Machine-Readable Contracts

```bash
# Function metadata for AI parsing
declare -A FUNCTION_CONTRACTS

register_contract() {
    local func="$1"
    local contract="$2"
    FUNCTION_CONTRACTS["$func"]="$contract"
}

register_contract "atomic_write" '{
    "preconditions": [
        {"check": "path is valid file path", "code": "validate_path \"$1\""},
        {"check": "content is string", "code": "[[ -n \"$2\" ]]"}
    ],
    "postconditions": [
        {"check": "file exists with content", "code": "[[ -f \"$1\" ]]"},
        {"check": "file contains exact content", "code": "[[ \"$(<\"$1\")\" == \"$2\" ]]"}
    ],
    "properties": {
        "idempotent": true,
        "atomic": true,
        "pure": false
    }
}'

# Query contract information
get_contract() {
    local func="$1"
    printf '%s' "${FUNCTION_CONTRACTS[$func]:-}"
}
```

---

## Part 8: Recommendations for MAINFRAME

### 8.1 High Priority Additions

| Pattern | Implementation | Impact |
|---------|---------------|--------|
| Contract annotations | Add `@contract` comments to all functions | AI can predict behavior |
| Idempotent variants | Add `ensure_*` prefix for idempotent operations | Safe for re-execution |
| JSON logging option | Add `MAINFRAME_LOG_JSON=1` mode | Structured observability |
| Guard clause helpers | Add `require_*` functions | Fast failure detection |

### 8.2 New Function Recommendations

```bash
# Idempotent operations
ensure_dir()          # mkdir -p wrapper with verification
ensure_file()         # Create with specific content
ensure_line()         # Append line if not present
ensure_symlink()      # Create/update symlink
ensure_package()      # Install if missing

# Atomic operations
atomic_write()        # Write-rename pattern
atomic_append()       # Append with lock
atomic_increment()    # Counter increment
atomic_swap()         # Swap two files

# Contract helpers
require_file()        # Precondition: file exists
require_dir()         # Precondition: directory exists
require_command()     # Precondition: command available
require_env()         # Precondition: env var set
require_root()        # Precondition: running as root

# Recovery helpers
with_rollback()       # Execute with automatic rollback
with_timeout()        # Execute with timeout
with_retry()          # Already exists as error::retry
with_lock()           # Execute with file lock
```

### 8.3 Documentation Enhancements

Add to CHEATSHEET.md:

```markdown
## AI Agent Contract Reference

### Function Properties

| Property | Meaning | Example |
|----------|---------|---------|
| `@idempotent` | Safe to run multiple times | `ensure_dir` |
| `@atomic` | No partial state on failure | `atomic_write` |
| `@pure` | No side effects | `json_object` |
| `@recoverable` | Can be undone | `safe_delete` |

### Exit Code Contract

All MAINFRAME functions follow this contract:

| Code | Meaning | AI Action |
|------|---------|-----------|
| 0 | Success | Continue |
| 1 | General failure | Log and handle |
| 2 | Invalid arguments | Fix input, don't retry |
| 3 | Precondition failed | Check environment |
| 4 | Resource unavailable | Wait and retry |
```

---

## Part 9: Testing Framework Integration

### 9.1 Bats-core for Contract Testing

```bash
# test/contracts/atomic_write.bats

@test "atomic_write creates file with content" {
    local tmpdir=$(mktemp -d)

    run atomic_write "$tmpdir/test.txt" "hello world"

    [ "$status" -eq 0 ]
    [ -f "$tmpdir/test.txt" ]
    [ "$(cat "$tmpdir/test.txt")" = "hello world" ]

    rm -rf "$tmpdir"
}

@test "atomic_write is idempotent" {
    local tmpdir=$(mktemp -d)

    atomic_write "$tmpdir/test.txt" "content"
    atomic_write "$tmpdir/test.txt" "content"  # Second call

    [ "$(cat "$tmpdir/test.txt")" = "content" ]

    rm -rf "$tmpdir"
}

@test "atomic_write survives interruption" {
    local tmpdir=$(mktemp -d)

    # Simulate partial write (temp file exists)
    touch "$tmpdir/.atomic.XXXXXX"

    run atomic_write "$tmpdir/test.txt" "content"

    [ "$status" -eq 0 ]
    [ "$(cat "$tmpdir/test.txt")" = "content" ]

    rm -rf "$tmpdir"
}
```

**Sources:**
- [ShellSpec Comparison](https://shellspec.info/comparison.html)
- [Effective Methods for Unit Testing Bash Scripts](https://www.repeato.app/effective-methods-for-unit-testing-bash-scripts/)
- [GitHub - bats-core/bats-core](https://github.com/bats-core/bats-core)

---

## Part 10: Claude Code Integration Patterns

### 10.1 What Claude Code Needs

Based on [Anthropic's Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices):

1. **Predictable file system state** - Operations should be atomic and idempotent
2. **Structured output** - JSON for parsing, plain text for display
3. **Clear error messages** - What failed, why, and how to recover
4. **Verification hooks** - Ability to check if operation succeeded

### 10.2 Claude Code Hooks Integration

```bash
# Hook-friendly function pattern
mainframe_operation() {
    local operation="$1"
    shift

    # Pre-hook (for Claude Code PreToolUse)
    if [[ -n "${MAINFRAME_PRE_HOOK:-}" ]]; then
        "$MAINFRAME_PRE_HOOK" "$operation" "$@"
    fi

    # Execute
    local result
    result=$("_mainframe_${operation}" "$@")
    local status=$?

    # Post-hook (for Claude Code PostToolUse)
    if [[ -n "${MAINFRAME_POST_HOOK:-}" ]]; then
        "$MAINFRAME_POST_HOOK" "$operation" "$status" "$result"
    fi

    printf '%s' "$result"
    return $status
}
```

### 10.3 Subagent-Friendly Design

```bash
# Functions designed for parallel subagent execution
# - No shared state
# - Atomic operations
# - JSON output for parsing

parallel_file_check() {
    local path="$1"

    # Return JSON that subagent can parse
    if [[ -f "$path" ]]; then
        printf '{"path":"%s","exists":true,"size":%d,"mtime":%d}\n' \
            "$path" \
            "$(stat -c%s "$path")" \
            "$(stat -c%Y "$path")"
    else
        printf '{"path":"%s","exists":false}\n' "$path"
    fi
}
```

**Sources:**
- [Claude Code: Best practices for agentic coding](https://www.anthropic.com/engineering/claude-code-best-practices)
- [How I Use Every Claude Code Feature](https://blog.sshh.io/p/how-i-use-every-claude-code-feature)

---

## Conclusion

AI coding assistants require bash patterns that prioritize:

1. **Predictability** - Same inputs always produce same outputs
2. **Recoverability** - Operations can be retried or rolled back
3. **Observability** - Structured logging and clear error messages
4. **Atomicity** - No partial state on failure
5. **Self-documentation** - Contracts visible without reading implementation

MAINFRAME already implements many of these patterns (error.sh, validation.sh). The recommended additions would strengthen its position as the leading AI-optimized bash library.

### Implementation Priority

1. **Immediate:** Add contract annotations to existing functions
2. **Short-term:** Implement `ensure_*` idempotent function family
3. **Medium-term:** Add `atomic_*` operations and JSON logging mode
4. **Long-term:** Bats-core migration and contract testing suite

---

## References

### Idempotency
- [How to write idempotent Bash scripts](https://arslan.io/2019/07/03/how-to-write-idempotent-bash-scripts/)
- [GitHub - metaist/idempotent-bash](https://github.com/metaist/idempotent-bash)
- [Bash Booster](http://www.bashbooster.net/)

### Documentation
- [GitHub - reconquest/shdoc](https://github.com/reconquest/shdoc)
- [Heredocs Can Make Your Bash Scripts Self-Documenting](https://holdtherobot.com/blog/heredocs-can-make-your-bash-scripts-self-documenting/)

### Error Handling
- [Unofficial Bash Strict Mode](http://redsymbol.net/articles/unofficial-bash-strict-mode/)
- [Learn Bash error handling by example](https://www.redhat.com/en/blog/bash-error-handling)
- [Bulletproof Bash Scripts](https://karandeepsingh.ca/posts/bash-error-handling-bulletproof-scripts/)

### Atomicity
- [Things UNIX can do atomically](https://rcrowley.org/2010/01/06/things-unix-can-do-atomically.html)
- [BashFAQ/045](https://mywiki.wooledge.org/BashFAQ/045)

### Testing
- [Bats-core](https://github.com/bats-core/bats-core)
- [ShellSpec Comparison](https://shellspec.info/comparison.html)

### AI Integration
- [Claude Code: Best practices for agentic coding](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Defensive BASH Programming](https://jonlabelle.com/snippets/view/markdown/defensive-bash-programming)

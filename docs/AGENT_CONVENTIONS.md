# MAINFRAME Agent Conventions

> **Mandatory standards for ALL AI coding agents working with bash**

**Version**: 1.0.0 | **Updated**: 2026-01-31

This document defines the conventions that ALL agents (Claude Code, sub-agents, Praison teams, orchestrating agents, OpenCode, Aider, Cursor) MUST follow when writing bash scripts in environments where MAINFRAME is available.

---

## 1. Mandatory Sourcing Pattern

Every bash script MUST begin with the MAINFRAME source line:

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

**Why this pattern:**
- `MAINFRAME_ROOT` allows custom install locations
- Fallback to `$HOME/.mainframe` is the standard default
- Single source gives access to 4,406 registry functions across 193 libraries (`mainframe count`)

**For performance-critical scripts**, use selective loading:

```bash
# Load only specific libraries
MAINFRAME_LIBS='json,validation,git' source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Or use tier-based loading
MAINFRAME_LIBS='core+standard' source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Or use profiles
MAINFRAME_PROFILE='minimal' source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

**Profiles available:**
| Profile | Description | Use Case |
|---------|-------------|----------|
| `minimal` | Core tier only | Quick scripts |
| `standard` | Core + standard tiers | Most scripts |
| `full` | All libraries | Maximum functionality |
| `ai` | Core + AI agent libraries | Agent operations |
| `lazy` | Function-level lazy loading | Performance critical |

---

## 2. Library Discovery Protocol

Before writing ANY bash code, agents MUST check if MAINFRAME already provides the functionality.

### Step 1: Categorize the Need

| Category | Library | Example Functions |
|----------|---------|-------------------|
| **Text manipulation** | `pure-string.sh` | `trim_string`, `to_lower`, `replace_all`, `split_string` |
| **Array operations** | `pure-array.sh` | `array_unique`, `array_join`, `array_contains`, `array_sort` |
| **JSON handling** | `json.sh` | `json_object`, `json_array`, `json_get`, `json_merge` |
| **File operations** | `pure-file.sh` | `file_exists`, `file_size`, `read_file`, `file_lines` |
| **Path manipulation** | `path.sh` | `path_normalize`, `path_join`, `path_is_safe`, `path_relative` |
| **Input validation** | `validation.sh` | `validate_email`, `validate_int`, `sanitize_html`, `validate_path_safe` |
| **Date/Time** | `datetime.sh` | `now`, `now_iso`, `date_add`, `format_relative` |
| **HTTP requests** | `http.sh` | `http_get`, `http_post`, `url_parse` |
| **Git operations** | `git.sh` | `git_branch`, `git_is_dirty`, `git_commit_hash` |
| **Process management** | `proc.sh` | `proc_exists`, `proc_find_by_port`, `lockfile_acquire` |
| **Docker/Compose** | `docker.sh` | `docker_running`, `docker_exec`, `compose_up` |
| **Crypto/Hashing** | `crypto.sh` | `sha256`, `md5`, `base64_encode`, `random_token` |
| **Environment vars** | `env.sh` | `env_get`, `env_set`, `env_load_dotenv`, `env_require` |
| **CSV parsing** | `csv.sh` | `csv_row`, `csv_parse_line`, `csv_to_json` |
| **Logging** | `common.sh` | `log_info`, `log_error`, `log_warn`, `log_debug` |
| **Output formatting** | `output.sh` | `success`, `failure`, `header`, `progress_bar` |
| **Colors/ANSI** | `ansi.sh` | `ansi_red`, `ansi_green`, `ansi_bold` |
| **Async/Parallel** | `async.sh` | `parallel`, `parallel_limit`, `retry` |
| **Idempotent ops** | `idempotent.sh` | `ensure_dir`, `ensure_file`, `ensure_line` |
| **Atomic file ops** | `atomic.sh` | `atomic_write`, `atomic_replace`, `safe_remove` |
| **Token budgeting** | `context.sh` | `context_estimate_tokens`, `context_budget_init` |
| **Diff/Patch** | `diff.sh` | `diff_replace`, `diff_apply`, `diff_insert_after` |
| **Caching** | `cache.sh` | `memoize`, `cas_store`, `session_cache_set` |
| **TUI components** | `tui.sh` | `tui_box`, `tui_table`, `tui_select`, `tui_confirm` |
| **Animations** | `anim.sh` | `spinner_start`, `spinner_stop`, `progress_bar`, `typewriter` |

### Step 2: Search CHEATSHEET.md

If unsure which function to use:

```bash
# Search for relevant functions
grep -i "pattern" "${MAINFRAME_ROOT:-$HOME/.mainframe}/CHEATSHEET.md"
```

### Step 3: Use Function Hints

MAINFRAME provides workflow hints:

```bash
# Get hints for a function
mainframe_hints_for "json_object"

# Get function chain suggestions
mainframe_hints_chain "json_object"
```

---

## 3. Anti-Patterns (NEVER DO)

### 3.1 Reinventing Wheels

```bash
# WRONG: Reinventing trim
trimmed="${str#"${str%%[![:space:]]*}"}"
trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

# CORRECT: Use MAINFRAME
trimmed=$(trim_string "$str")
```

```bash
# WRONG: Reinventing UUID
uuid=$(cat /proc/sys/kernel/random/uuid)

# CORRECT: Use MAINFRAME
id=$(uuid)
```

```bash
# WRONG: Reinventing JSON
echo "{\"name\":\"$name\",\"count\":$count}"

# CORRECT: Use MAINFRAME
json_object "name=$name" "count:number=$count"
```

### 3.2 Using External Tools When MAINFRAME Suffices

```bash
# WRONG: Using jq for simple JSON
result=$(echo '{"name":"John"}' | jq -r '.name')

# CORRECT: Use an already-loaded MAINFRAME helper (no added subprocess here)
result=$(json_get '{"name":"John"}' "name")
```

```bash
# WRONG: Using npm/node for bash tasks
npm install uuid && node -e "console.log(require('uuid').v4())"

# CORRECT: Use MAINFRAME
uuid
```

```bash
# WRONG: Using Python for date math
python3 -c "from datetime import datetime, timedelta; print((datetime.now() + timedelta(days=7)).isoformat())"

# CORRECT: Use MAINFRAME
date_add $(now) "7d"
```

### 3.3 Hardcoding Colors/ANSI

```bash
# WRONG: Hardcoded ANSI
echo -e "\033[31mError\033[0m"

# CORRECT: Use MAINFRAME
echo "$(ansi_red)Error$(ansi_reset)"
# Or better:
log_error "Error message"
```

### 3.4 Manual Logging/Output

```bash
# WRONG: Manual logging
echo "[$(date)] [ERROR] Something failed" >&2

# CORRECT: Use MAINFRAME
log_error "Something failed"
```

### 3.5 Unsafe Path Operations

```bash
# WRONG: Vulnerable to path traversal
file="/data/$user_input"
cat "$file"

# CORRECT: Use MAINFRAME validation
if validate_path_safe "$user_input" "/data"; then
    cat "/data/$user_input"
fi
```

### 3.6 Manual Retry Logic

```bash
# WRONG: Manual retry
for i in 1 2 3; do
    if curl -s "$url"; then break; fi
    sleep 1
done

# CORRECT: Use MAINFRAME
retry 3 curl -s "$url"
```

---

## 4. Function Categories Quick Reference

### Core Operations (Always Available)

| Need | Function | Example |
|------|----------|---------|
| Log info | `log_info` | `log_info "Starting process"` |
| Log error | `log_error` | `log_error "Failed to connect"` |
| Success message | `success` | `success "Build complete"` |
| Failure message | `failure` | `failure "Tests failed"` |
| Exit with error | `die` | `die 1 "Configuration missing"` |
| Generate UUID | `uuid` | `id=$(uuid)` |
| Get timestamp | `timestamp` | `ts=$(timestamp)` |
| Check command | `command_exists` | `command_exists "docker"` |
| Create temp file | `temp_file` | `tmp=$(temp_file)` |
| Create temp dir | `temp_dir` | `tmpdir=$(temp_dir)` |

### String Operations

| Need | Function | Example |
|------|----------|---------|
| Trim whitespace | `trim_string` | `trim_string "  hello  "` |
| Lowercase | `to_lower` | `to_lower "HELLO"` |
| Uppercase | `to_upper` | `to_upper "hello"` |
| Replace text | `replace_all` | `replace_all "$str" "old" "new"` |
| Check contains | `contains` | `contains "$str" "needle"` |
| URL encode | `urlencode` | `urlencode "hello world"` |

### JSON Operations

| Need | Function | Example |
|------|----------|---------|
| Create object | `json_object` | `json_object "name=John" "age:number=30"` |
| Create array | `json_array` | `json_array "a" "b" "c"` |
| Get value | `json_get` | `json_get "$json" "name"` |
| Merge objects | `json_merge` | `json_merge "$obj1" "$obj2"` |
| Escape string | `json_escape` | `json_escape "$text"` |

### File Operations

| Need | Function | Example |
|------|----------|---------|
| Check exists | `file_exists` | `file_exists "/path/to/file"` |
| Read file | `read_file` | `content=$(read_file "file.txt")` |
| Write file | `file_write` | `file_write "file.txt" "$content"` |
| Get size | `file_size` | `size=$(file_size "file.txt")` |
| Count lines | `file_lines` | `lines=$(file_lines "file.txt")` |

### Validation/Security

| Need | Function | Example |
|------|----------|---------|
| Validate email | `validate_email` | `validate_email "$email"` |
| Validate URL | `validate_url` | `validate_url "$url"` |
| Validate path | `validate_path_safe` | `validate_path_safe "$path" "/base"` |
| Sanitize HTML | `sanitize_html` | `sanitize_html "$input"` |
| Sanitize shell | `sanitize_shell_arg` | `sanitize_shell_arg "$arg"` |

### Date/Time

| Need | Function | Example |
|------|----------|---------|
| Unix timestamp | `now` | `ts=$(now)` |
| ISO timestamp | `now_iso` | `iso=$(now_iso)` |
| Add duration | `date_add` | `date_add $(now) "2d"` |
| Relative format | `format_relative` | `format_relative $past_ts` |

### Git Operations

| Need | Function | Example |
|------|----------|---------|
| Current branch | `git_branch` | `branch=$(git_branch)` |
| Check dirty | `git_is_dirty` | `git_is_dirty && echo "uncommitted"` |
| Commit hash | `git_commit_hash` | `hash=$(git_commit_hash)` |
| Changed files | `git_changed_files` | `files=$(git_changed_files)` |

---

## 5. MAINFRAME-First Checklist

Before writing ANY bash code, agents MUST ask:

```
[ ] 1. Does MAINFRAME have a function for this?
      -> Check category table above
      -> Search CHEATSHEET.md

[ ] 2. Am I reinventing something that exists?
      -> String manipulation -> pure-string.sh
      -> JSON handling -> json.sh
      -> File operations -> pure-file.sh
      -> Path operations -> path.sh
      -> Validation -> validation.sh

[ ] 3. Am I using external tools unnecessarily?
      -> jq for JSON -> use json.sh
      -> Python for dates -> use datetime.sh
      -> sed/awk for strings -> use pure-string.sh

[ ] 4. Am I handling errors properly?
      -> Use log_error, die, assert
      -> Not raw echo >&2

[ ] 5. Am I formatting output correctly?
      -> Use success/failure for status
      -> Use log_info/log_warn for messages
      -> Use header/subheader for sections

[ ] 6. Did I source MAINFRAME?
      -> First line after shebang:
         source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## 6. Integration Points for Sub-Agents

### 6.1 Praison Teams

When creating Praison team YAML files that include bash operations:

```yaml
agents:
  - role: "Bash Script Creator"
    goal: "Create bash scripts following MAINFRAME conventions"
    backstory: |
      You are a bash scripting expert who ALWAYS uses MAINFRAME functions.
      You NEVER reinvent wheels. You source common.sh first.
      You use MAINFRAME's logging, JSON, validation, and utility functions.
    tools:
      - file_writer
    instructions: |
      1. Always start scripts with: source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
      2. Check MAINFRAME CHEATSHEET.md before writing custom functions
      3. Use log_info, log_error, success, failure for output
      4. Use json_object for JSON, not manual string construction
      5. Use validate_* functions for input validation
```

### 6.2 Claude Code Sub-Agents

When spawning sub-agents for bash tasks:

```markdown
## Context for Sub-Agent

You are working in an environment with MAINFRAME available.

**CRITICAL RULES:**
1. Source MAINFRAME first: `source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"`
2. Use MAINFRAME functions instead of reinventing:
   - JSON: `json_object`, `json_array`, `json_get`
   - Logging: `log_info`, `log_error`, `success`, `failure`
   - Strings: `trim_string`, `to_lower`, `replace_all`
   - Files: `file_exists`, `read_file`, `file_write`
   - Validation: `validate_email`, `validate_path_safe`
3. Reference: /home/user/.mainframe/CHEATSHEET.md for function signatures
```

### 6.3 Orchestrating Agents

When an orchestrating agent delegates bash work:

```bash
# Include in the task context
MAINFRAME_CONTEXT="
MAINFRAME is available at: ${MAINFRAME_ROOT:-$HOME/.mainframe}
Reference: CHEATSHEET.md for 4,406 registry functions
Key libraries: json.sh, validation.sh, datetime.sh, git.sh
MUST source common.sh at script start
"
```

---

## 7. Enforcement Mechanisms

### 7.1 Pre-Commit Hook

Add to `.git/hooks/pre-commit`:

```bash
#!/usr/bin/env bash

# Check bash scripts source MAINFRAME
for file in $(git diff --cached --name-only | grep '\.sh$'); do
    if ! grep -q 'source.*common\.sh' "$file"; then
        echo "ERROR: $file does not source MAINFRAME common.sh"
        exit 1
    fi
done
```

### 7.2 CI Lint Check

```bash
#!/usr/bin/env bash
# ci-check-mainframe.sh

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

errors=0

for script in $(find . -name '*.sh' -type f); do
    # Skip MAINFRAME itself
    [[ "$script" == */.mainframe/* ]] && continue

    # Check for MAINFRAME sourcing
    if ! grep -q 'source.*common\.sh' "$script"; then
        log_error "Missing MAINFRAME source: $script"
        ((errors++))
    fi

    # Check for anti-patterns
    if grep -qE 'echo.*\\033\[' "$script"; then
        log_warn "Hardcoded ANSI in $script - use ansi.sh functions"
    fi

    if grep -qE '\| jq ' "$script"; then
        log_warn "Using jq in $script - consider json.sh functions"
    fi
done

if ((errors > 0)); then
    failure "$errors scripts missing MAINFRAME source"
    exit 1
fi

success "All scripts follow MAINFRAME conventions"
```

### 7.3 Agent Context Injection

For Watson agents, add to context files:

```markdown
## MAINFRAME Requirement

All bash scripts MUST:
1. Source MAINFRAME: `source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"`
2. Use MAINFRAME functions (4,406 registry functions available)
3. Reference: `~/.mainframe/CHEATSHEET.md`

Common functions:
- Logging: log_info, log_error, success, failure
- JSON: json_object, json_array, json_get
- Validation: validate_email, validate_path_safe
- Files: file_exists, read_file, file_write
- Strings: trim_string, to_lower, replace_all
```

### 7.4 CLAUDE.md Rule

Already present in Gordon's CLAUDE.md:

```markdown
16. **MAINFRAME**: MUST source MAINFRAME (`source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"`)
    in ALL bash scripts. MUST NOT reinvent colors, logging, JSON, timestamps, retry logic,
    validation, or path handling. 4,406 registry functions across 193 libraries (`mainframe count`).
```

---

## 8. Error Recovery

If an agent produces a script without MAINFRAME:

### Immediate Fix

```bash
# Add at top of script (after shebang)
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

### Refactor Checklist

1. Replace `echo "[ERROR]..."` with `log_error "..."`
2. Replace `echo -e "\033[..."` with ANSI functions
3. Replace manual JSON with `json_object`
4. Replace manual retries with `retry`
5. Replace path string manipulation with `path_*` functions
6. Replace date/time formatting with `datetime.sh` functions

---

## 9. Quick Reference Card

```
+------------------------------------------------------------------+
|                    MAINFRAME QUICK REFERENCE                      |
+------------------------------------------------------------------+
| SOURCE: source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"|
+------------------------------------------------------------------+
| LOGGING        | log_info, log_error, log_warn, log_debug        |
| STATUS         | success, failure, header, subheader             |
| JSON           | json_object, json_array, json_get, json_merge   |
| STRINGS        | trim_string, to_lower, replace_all, contains    |
| FILES          | file_exists, read_file, file_write, file_size   |
| PATHS          | path_join, path_normalize, path_is_safe         |
| VALIDATION     | validate_email, validate_int, validate_path_safe|
| DATE/TIME      | now, now_iso, date_add, format_relative         |
| GIT            | git_branch, git_is_dirty, git_commit_hash       |
| UTILS          | uuid, timestamp, temp_file, temp_dir            |
| ANSI           | ansi_red, ansi_green, ansi_bold, ansi_reset     |
| ASYNC          | parallel, retry, parallel_limit                 |
+------------------------------------------------------------------+
| REFERENCE: ${MAINFRAME_ROOT:-$HOME/.mainframe}/CHEATSHEET.md     |
+------------------------------------------------------------------+
```

---

## 10. Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-31 | Initial release |

---

*MAINFRAME Agent Conventions v1.0.0 - Ensuring consistent, high-quality bash across all AI agents*

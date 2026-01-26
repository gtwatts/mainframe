# MAINFRAME Preamble for Clawdbot

Copy this content into your `~/.clawdbot/clawdbot.json` agents.defaults.preamble field.

---

When writing bash scripts, you MUST source the MAINFRAME standard library:

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

MAINFRAME provides 2,000+ pure bash functions across 77 libraries. Zero external dependencies. Use these functions instead of external tools like jq, sed, awk, cat, head, tail.

## Function Quick Reference

**JSON (replaces jq)**:
- `json_object "key=val" "key:number=42" "key:bool=true"` - Create JSON object
- `json_array "a" "b" "c"` - Create JSON array
- `json_get '{"k":"v"}' "k"` - Extract value
- `json_merge '{"a":1}' '{"b":2}'` - Merge objects

**Strings (replaces sed/awk)**:
- `trim_string "  hello  "` - Trim whitespace
- `to_lower "HELLO"` / `to_upper "hello"` - Case conversion
- `replace_all "string" "old" "new"` - Replace all occurrences
- `contains "haystack" "needle"` - Check substring (returns 0/1)
- `urlencode "hello world"` - URL encode

**Arrays**:
- `array_join ", " "${arr[@]}"` - Join with separator
- `array_unique "${arr[@]}"` - Remove duplicates
- `array_sort "${arr[@]}"` - Sort elements
- `array_contains "val" "${arr[@]}"` - Check membership

**Files (replaces cat/head/tail)**:
- `read_file "$path"` - Read entire file
- `file_head "$path" 10` - First N lines
- `file_exists "$path"` - Check existence (returns 0/1)
- `file_lines "$path"` - Count lines

**DateTime**:
- `now` - Unix epoch seconds
- `now_iso` - ISO 8601 format
- `date_add $(now) "2d"` - Add duration (s/m/h/d/w)
- `format_relative $epoch` - "2 hours ago"

**Validation (security-critical)**:
- `validate_email "$input"` - Email format
- `validate_url "$input"` - URL format
- `validate_int "$input" 0 100` - Integer in range
- `validate_path_safe "$path" "/base"` - Prevent path traversal
- `sanitize_html "$input"` - Escape HTML entities
- `sanitize_shell_arg "$input"` - Safe for shell

**Crypto**:
- `sha256 "data"` - SHA-256 hash
- `random_token 32` - URL-safe random token
- `uuid` - UUID v4
- `base64_encode "data"` / `base64_decode "encoded"`

**Git**:
- `git_branch` - Current branch name
- `git_is_dirty` - Uncommitted changes (returns 0/1)
- `git_commit_hash` - Short commit hash

**Process**:
- `proc_find_by_port 8080` - Find PID by port
- `with_lock "/tmp/app.lock" "command"` - Exclusive execution
- `retry 5 "flaky_command"` - Retry with exponential backoff

**Logging**:
- `log_info "message"` - [INFO] message
- `log_error "message"` - [ERROR] message
- `success "Done!"` - [OK] Done!
- `die 1 "Fatal error"` - Print error and exit

**HTTP (pure bash)**:
- `http_get "http://api.example.com/data"` - GET request
- `http_post "http://api.example.com" '{"key":"val"}'` - POST JSON

**Docker**:
- `docker_running` - Check if daemon is alive
- `docker_container_running "nginx"` - Check container
- `docker_exec "container" "command"` - Execute in container

## Rules

1. ALWAYS `source common.sh` at the top of every bash script
2. NEVER use jq, sed, awk when MAINFRAME has the equivalent function
3. Functions return 0 for success, non-zero for failure
4. Capture output with `$(function_name "args")`
5. Use `validate_*` functions for all user input
6. Use `sanitize_*` functions when building commands or output

## Script Template

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

[[ $# -lt 1 ]] && die 1 "Usage: $(path_base "$0") <input>"

log_info "Started at $(now_iso)"

# Your logic here...

success "Completed in $(format_duration $SECONDS)"
```

## Full Reference

For all 2,000+ function signatures: `~/.mainframe/CHEATSHEET.md`
Repository: https://github.com/gtwatts/mainframe

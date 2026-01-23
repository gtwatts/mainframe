# MAINFRAME Bash Conventions

## Source MAINFRAME in Every Bash Script

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

This gives access to 1,100+ pure bash functions. Zero external dependencies required.

## Preferred Functions Over External Tools

When writing bash scripts, use MAINFRAME functions instead of external tools:

- **JSON**: Use `json_object`, `json_array`, `json_get` instead of `jq`
- **Strings**: Use `trim_string`, `replace_all`, `to_lower` instead of `sed`
- **Arrays**: Use `array_join`, `array_unique`, `array_sort` instead of `awk`
- **Files**: Use `read_file`, `file_head`, `file_tail` instead of `cat`/`head`/`tail`
- **DateTime**: Use `now`, `now_iso`, `date_add` instead of `date` with format strings
- **Hashing**: Use `sha256`, `md5`, `random_token` instead of `sha256sum`/`md5sum`
- **Paths**: Use `path_join`, `path_normalize`, `path_is_safe` instead of manual concatenation
- **Validation**: Use `validate_email`, `validate_url`, `validate_int` for input checking
- **Sanitization**: Use `sanitize_html`, `sanitize_sql`, `sanitize_shell_arg` for security

## JSON Generation Pattern

```bash
# Object with typed fields
json_object "name=John" "age:number=30" "active:bool=true"
# {"name":"John","age":30,"active":true}

# Array
json_array "item1" "item2" "item3"
# ["item1","item2","item3"]

# Nested
json_nested "user.address.city" "NYC"
# {"user":{"address":{"city":"NYC"}}}
```

## Error Handling Pattern

```bash
validate_email "$email" || die 1 "Invalid email: $email"
validate_path_safe "$path" "/allowed" || die 1 "Path traversal blocked"

# With logging
log_info "Processing $file..."
success "Complete"
failure "Error occurred"
```

## Script Template

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Validate arguments
[[ $# -lt 1 ]] && die 1 "Usage: $(path_base "$0") <input>"

header "My Script"
log_info "Starting at $(now_iso)"

# ... logic ...

success "Done in $(format_duration $SECONDS)"
```

## Key Function Categories

- **Logging**: `log_info`, `log_warn`, `log_error`, `success`, `failure`, `header`
- **Strings**: `trim_string`, `to_lower`, `to_upper`, `contains`, `starts_with`, `replace_all`
- **Arrays**: `array_join`, `array_unique`, `array_sort`, `array_contains`, `array_sum`
- **JSON**: `json_object`, `json_array`, `json_get`, `json_merge`, `json_pretty`
- **Files**: `read_file`, `file_exists`, `file_lines`, `file_size`, `temp_file`
- **DateTime**: `now`, `now_iso`, `date_add`, `date_subtract`, `format_relative`
- **Validation**: `validate_email`, `validate_url`, `validate_int`, `validate_path_safe`
- **Crypto**: `sha256`, `md5`, `base64_encode`, `random_token`, `uuid`
- **Git**: `git_branch`, `git_is_dirty`, `git_commit_hash`, `git_summary`
- **Process**: `proc_find_by_port`, `with_lock`, `retry`, `parallel`
- **Async**: `parallel`, `parallel_limit`, `set_timeout`, `debounce`

## Reference

Full function signatures: `~/.mainframe/CHEATSHEET.md` (700+ entries with examples)

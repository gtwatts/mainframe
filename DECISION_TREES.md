# MAINFRAME Decision Trees

Quick lookup: "I need to do X" -> use these functions.

## Data Manipulation

### JSON
```
Need JSON object?     -> json_object "key=val" "num:number=42"
Need JSON array?      -> json_array "a" "b" "c"
Need to read JSON?    -> json_get "$json" "key"
Need to merge JSON?   -> json_merge "$json1" "$json2"
Need pretty JSON?     -> json_pretty "$json"
Need to validate?     -> json_valid "$json"
```

### Strings
```
Trim whitespace?      -> trim_string "$str"
Change case?          -> to_lower "$str" / to_upper "$str"
Find/replace?         -> replace_all "$str" "old" "new"
Split string?         -> split_string "$str" ","
Check contains?       -> contains "$str" "needle"
URL encode/decode?    -> urlencode "$str" / urldecode "$str"
```

### Arrays
```
Join to string?       -> array_join "," "${arr[@]}"
Remove duplicates?    -> array_unique "${arr[@]}"
Check contains?       -> array_contains "val" "${arr[@]}"
Sort array?           -> array_sort "${arr[@]}"
Filter array?         -> array_filter predicate "${arr[@]}"
```

### CSV
```
Parse CSV file?       -> csv_read "file.csv"
Get field value?      -> csv_get $row "column_name"
Create CSV row?       -> csv_row "val1" "val2" "val3"
Convert to JSON?      -> csv_to_json "file.csv"
Filter rows?          -> csv_filter "file.csv" "col" "val"
```

## File Operations

### Reading/Writing
```
Read file?            -> read_file "path"
Write file safely?    -> atomic_write "path" "$content"
Append to file?       -> atomic_append "path" "$line"
Check exists?         -> file_exists "path" / dir_exists "path"
Get file size?        -> file_size "path"
Get line count?       -> file_lines "path"
```

### Editing Files (AI Agent Primary)
```
Replace text?         -> diff_replace "file" "old" "new"
Insert after line?    -> diff_insert_after "file" "match" "new"
Insert before line?   -> diff_insert_before "file" "match" "new"
Delete lines?         -> diff_delete_lines "file" "pattern"
Replace line range?   -> diff_replace_range "file" 5 10 "new"
Preview changes?      -> diff_preview "file" "$new_content"
Validate unique?      -> diff_validate_unique "file" "text"
```

### Path Manipulation
```
Normalize path?       -> path_normalize "/foo//bar/../baz"
Get absolute path?    -> path_absolute "relative"
Get directory?        -> path_dir "/foo/bar/file.txt"
Get filename?         -> path_base "/foo/bar/file.txt"
Get extension?        -> path_ext "file.tar.gz"
Join paths?           -> path_join "/foo" "bar" "baz"
Check safe path?      -> path_is_safe "/base" "$user_path"
```

## Validation & Security

### Input Validation
```
Validate integer?     -> validate_int "$val" [min] [max]
Validate email?       -> validate_email "$email"
Validate URL?         -> validate_url "$url"
Validate IP?          -> validate_ipv4 "$ip"
Validate date?        -> validate_date "2024-01-15"
Validate JSON?        -> validate_json "$json"
Validate path safe?   -> validate_path_safe "$path" "/base"
```

### Sanitization
```
Sanitize for shell?   -> sanitize_shell_arg "$input"
Sanitize filename?    -> sanitize_filename "$name"
Sanitize HTML?        -> sanitize_html "$input"
Sanitize SQL?         -> sanitize_sql "$input"
Sanitize JSON?        -> sanitize_json "$input"
```

## HTTP & Networking

### HTTP Requests
```
GET request?          -> http_get "url"
POST request?         -> http_post "url" "data"
POST JSON?            -> http_json_post "url" "$json"
Check status?         -> http_is_success
Get response header?  -> http_header_get "Content-Type"
Parse URL?            -> url_parse "url" (sets URL_* vars)
Build query string?   -> query_string "a=1" "b=2"
```

### Downloads
```
Download file?        -> download "url" ["output"]
Download to stdout?   -> download_stdout "url"
Download + extract?   -> download_extract "url" "/dest"
Resume download?      -> download_resume "url" "partial"
Verify checksum?      -> download_verify "file" "sha256"
```

## System & Process

### Process Management
```
Process exists?       -> proc_exists $pid
Find by port?         -> proc_find_by_port 8080
Find by name?         -> proc_find_by_name "nginx"
Get CPU/memory?       -> proc_cpu $pid / proc_memory $pid
Kill process?         -> proc_kill $pid
Run with timeout?     -> with_timeout 30 "command"
Run with lock?        -> with_lock "/tmp/lock" "command"
```

### Docker
```
Docker running?       -> docker_running
Container running?    -> docker_container_running "name"
Execute in container? -> docker_exec "name" "command"
Get container logs?   -> docker_logs "name" 100
Compose up?           -> compose_up
Compose service?      -> compose_running "service"
```

### System Info
```
CPU count?            -> cpu_count
Memory total?         -> memory_total
Disk usage?           -> disk_usage "/"
OS name?              -> os_name
Is container?         -> is_container
Is root?              -> is_root
System summary?       -> system_info
```

## Date/Time

```
Current timestamp?    -> now (Unix) / now_iso (ISO 8601)
Parse date?           -> parse_date "2024-01-15"
Add time?             -> date_add $(now) "2d" / "1w" / "3h"
Subtract time?        -> date_subtract $(now) "1w"
Format relative?      -> format_relative $epoch -> "2 hours ago"
Day of week?          -> day_of_week [epoch]
Is weekend?           -> is_weekend [epoch]
```

## Cryptography

```
SHA-256 hash?         -> sha256 "data"
MD5 hash?             -> md5 "data"
File checksum?        -> checksum "file"
Verify checksum?      -> checksum_verify "file" "$hash"
Base64 encode?        -> base64_encode "data"
Base64 decode?        -> base64_decode "$encoded"
Random token?         -> random_token 32
Generate password?    -> generate_password 16
```

## Git

```
Current branch?       -> git_branch
Is dirty?             -> git_is_dirty
Changed files?        -> git_changed_files
Commit hash?          -> git_commit_hash
Default branch?       -> git_default_branch
Repository summary?   -> git_summary_json
```

## AI Agent Operations

### Idempotent (Safe to Re-run)
```
Create directory?     -> ensure_dir "path" [mode]
Create file?          -> ensure_file "path" "content" [mode]
Add line to file?     -> ensure_line "file" "line"
Create symlink?       -> ensure_symlink "target" "link"
Check command?        -> ensure_command "git"
Install package?      -> ensure_package "jq"
```

### Token Budget
```
Estimate tokens?      -> context_estimate_tokens "$text"
File tokens?          -> context_file_tokens "file"
Init budget?          -> context_budget_init --max-tokens 128000
Check fits?           -> context_budget_fits $tokens
Record usage?         -> context_budget_use "file" $tokens
Truncate text?        -> context_truncate "$text" 1000
Plan file reads?      -> context_read_plan 50000 src/*.ts
```

### Caching
```
Cache function call?  -> memoize [--ttl 300] func args...
Store content?        -> cas_store "$content"
Get by hash?          -> cas_get "$hash"
Session cache?        -> session_cache_set "key" "value"
Clear cache?          -> cache_clear
```

### Observability
```
Start trace?          -> tid=$(trace_start "operation")
Add step?             -> trace_step "$tid" "step" "ok"
End trace?            -> trace_end "$tid" "success"
Observe command?      -> observe_command cmd args
Stack trace?          -> stack_trace
```

## GitHub (requires gh CLI)

### Repository
```
View repo?            -> gh_repo_view "owner/repo"
List repos?           -> gh_repo_list "owner"
Create repo?          -> gh_repo_create "name" --public
Clone repo?           -> gh_repo_clone "owner/repo"
```

### Issues & PRs
```
List issues?          -> gh_issue_list "repo" --state open
Create issue?         -> gh_issue_create "repo" "title" "body"
List PRs?             -> gh_pr_list "repo"
Create PR?            -> gh_pr_create "repo" "title" --body "body"
Merge PR?             -> gh_pr_merge "repo" 123 --squash
```

### Actions
```
List workflows?       -> gha_workflow_list "repo"
Run workflow?         -> gha_workflow_run "repo" "ci.yml"
Get run status?       -> gha_run_status "repo" $run_id
Wait for run?         -> gha_run_wait "repo" $run_id 600
```

### Security
```
Dependabot alerts?    -> ghs_dependabot_alerts "repo"
Code scanning?        -> ghs_code_alerts "repo"
Security score?       -> ghs_score "repo"
SBOM export?          -> ghs_sbom_export "repo"
```

## Output & CLI

### Logging
```
Info message?         -> log_info "message"
Warning?              -> log_warn "message"
Error?                -> log_error "message"
Success?              -> success "message"
Failure?              -> failure "message"
```

### Progress
```
Progress bar?         -> progress_bar 50 100
Start spinner?        -> spinner_start dots "Loading..."
Stop spinner?         -> spinner_stop "Done" success
Run with spinner?     -> spinner_while dots "msg" command
```

### USOP Output (AI Agent)
```
Success response?     -> output_success "data" ["hint"]
Error response?       -> output_error "code" "msg" ["suggestion"]
Typed result?         -> output_int 42 / output_bool true
JSON mode?            -> export MAINFRAME_OUTPUT=json
```

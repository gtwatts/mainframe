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

## AWM (Agent Working Memory)

### I need to manage AWM sessions
```
Is this a new session?
├── Yes: sid=$(awm_init "task_name" ["parent_session_id"])
└── No: Are you resuming an existing session?
    ├── Yes: awm_resume "session_id"
    └── No: Read summary: awm_summary

Need to close session?
├── Mark complete: awm_close
├── List all sessions: awm_list [--status active|completed]
└── Cleanup old: awm_cleanup [days]
```

### I need to store data in AWM
```
What type of data?
├── Key-value (checkpoint): awm_checkpoint "key" "value"
├── Important discovery: awm_discovery "insight text"
├── Progress tracking: awm_progress "task_id" "47/200" ["status msg"]
├── Categorized log: awm_log "category" "message"
└── Sub-agent context: ctx=$(awm_context_for "subtask_name")
```

### I need to read AWM data
```
What do you need?
├── Single key: value=$(awm_get "key" ["default"])
├── Recent log entries: awm_recent "category" [count]
├── Full summary: awm_summary
├── Token estimate: awm_token_estimate
└── Specific read cost: awm_estimate_read "summary|recent|get" [args]
```

### I need AWM v2 features
```
Initialize v2: awm_v2_init ["model"]
Get v2 status: awm_v2_status
Tiered checkpoint: awm_checkpoint_v2 "key" "value" [importance]
Tiered get: awm_get_v2 "key" ["default"] ["promote"]
Budget-aware context: awm_context_v2 [max_tokens] [include_cold]
Recovery checkpoint: awm_recovery_checkpoint
Recover from crash: awm_recovery_restore "session_id"
```

## Error Handling

### I need try/catch style error handling
```
Wrap command with structured error?
├── Yes: output_try command [args...]
└── No, just capture result: result=$(observe_command cmd args...)

Need structured error object?
├── Rich error with context: output_structured_error CODE "msg" ["suggestion"] ["key=val"...]
├── Simple JSON error: output_error "code" "message" ["suggestion"]
└── Observe error: observe_error 1 "message" ["context"]
```

### I need stack traces
```
Get current stack trace?     -> trace=$(stack_trace)
Debug format (JSON)?         -> {"stack":[{func,file,line}...],"depth":N}
```

### I need error recovery patterns
```
What pattern?
├── Exit on error with message: die 1 "error message"
├── Retry with backoff: retry 5 "command"
├── Timeout protection: with_timeout 30 "command"
├── Lock protection: with_lock "/tmp/lock" "command"
└── Conditional execution: cmd || { handle_error; return 1; }
```

## Caching & Memoization

### I need to cache function calls
```
One-time memoization?
├── Yes: result=$(memoize [--ttl 300] func args...)
│   └── With file deps: memoize --invalidate-on config.json func args
└── Decorator pattern (persistent)?
    ├── Wrap function: memo_wrap "function_name" [ttl_seconds]
    ├── Unwrap: memo_unwrap "function_name"
    └── Clear func cache: memo_clear "function_name"
```

### I need to cache commands
```
Shell command caching?       -> cache_command TTL cmd [args...]
File content caching?        -> content=$(cache_file "/path/to/file")
Invalidate file cache?       -> cache_file_invalidate "/path/to/file"
Computation with deps?       -> cache_compute "key" compute_fn dep1.json dep2.json
```

### I need content-addressable storage
```
Store by hash?               -> hash=$(cas_store "$content")
Retrieve by hash?            -> content=$(cas_get "$hash")
Check if exists?             -> cas_exists "$hash" && echo "found"
Garbage collect?             -> cas_gc --older-than 30
```

### I need session cache (in-memory)
```
Set value?                   -> session_cache_set "key" "value"
Get value?                   -> val=$(session_cache_get "key" ["default"])
Check exists?                -> session_cache_has "key"
Clear all?                   -> session_cache_clear
```

### I need cache management
```
View statistics?             -> cache_stats [--json]
Clear all caches?            -> cache_clear --force
Invalidate pattern?          -> cache_invalidate "pattern*"
Set max size?                -> cache_max_size "256MB"
LRU eviction?                -> cache_evict_lru [max_size_mb]
Prewarm cache?               -> cache_prewarm git|project|system|all
```

## Streaming & Process Substitution

### I need to process lines without losing variables
```
Problem: Variables lost in pipe?
├── Read lines into array: read_lines_from "command" array_name
├── Process with callback: for_each_line "command" callback_func
└── Process file lines: process_file "file" callback_func

Callback receives: $1=line, $2=lineno (for process_file)
Variables persist in current shell.
```

### I need to compare command outputs
```
Diff two commands?           -> diff_commands "cmd1" "cmd2" [-u]
```

### I need to capture output
```
Capture to variable?         -> capture_output result_var "command"
Tee to var AND stdout?       -> tee_to_var output_var "command"
```

## Regex Operations

### I need pattern matching
```
Test if string matches?      -> regex_match "string" "pattern" && echo "yes"
Find first match?            -> match=$(regex_find "hello123" "[0-9]+")
Find all matches?            -> regex_find_all "a1b2c3" "[0-9]" | while read m; do...
Extract capture groups?      -> regex_groups "hello123" "([a-z]+)([0-9]+)"
Full string match?           -> regex_full_match "hello" "^[a-z]+$"
```

### I need replacements
```
Replace first?               -> result=$(regex_replace "str" "pattern" "replacement")
Replace all?                 -> result=$(regex_replace_all "a1b2" "[0-9]" "X")
With backreferences?         -> result=$(regex_sub "hello world" "(\w+) (\w+)" "\2 \1")
With callback?               -> result=$(regex_replace_callback "str" "pat" my_func)
```

### I need splitting
```
Split by pattern?            -> regex_split "a-b-c" "-" | while read part; do...
Split with limit?            -> regex_split_limit "a-b-c-d" "-" 2
```

### I need pattern building
```
Build alternation?           -> pattern=$(regex_any_of "cat" "dog" "bird")
Make optional?               -> pattern=$(regex_optional "[a-z]+")
Add repetition?              -> pattern=$(regex_repeat "[a-z]" 2 5)
Add anchors?                 -> pattern=$(regex_anchor "pattern" "both|start|end")
Escape metacharacters?       -> escaped=$(regex_escape "file.txt")
Convert glob to regex?       -> pattern=$(glob_to_regex "*.txt")
```

### I need validation
```
Validate email?              -> regex_validate_email "user@example.com"
Validate URL?                -> regex_validate_url "https://example.com"
Validate UUID?               -> regex_validate_uuid "$uuid"
Validate semver?             -> regex_validate_semver "1.2.3"
Check pattern safety?        -> regex_compile_safe "$pattern" || echo "risky"
```

## USOP Protocol (Structured Output)

### I need to set output mode
```
Set mode?                    -> output_mode "json|minimal|debug|raw"
Check if JSON mode?          -> output_is_json && echo "JSON active"
Temporary mode?              -> output_with_mode "json" command args...
```

### I need typed output
```
String?                      -> output_string "data" ["hint"]
Integer?                     -> output_int 42 ["hint"]
Float?                       -> output_float 3.14 ["hint"]
Boolean?                     -> output_bool true ["hint"]
JSON object?                 -> output_json_object '{"key":"value"}'
JSON array?                  -> output_json_array '["a","b"]'
Void/null?                   -> output_void ["hint"]
```

### I need USOP command execution
```
Execute with envelope?       -> result=$(usop_exec command args...)
Get field from result?       -> stdout=$(usop_get "$result" "stdout")
Check success?               -> usop_ok "$result" && echo "success"
File operations?
├── Read file: result=$(usop_read_file "/path")
├── Write file: result=$(usop_write_file "/path" "content")
└── List directory: result=$(usop_list_dir "/path")
```

### I need USOP errors
```
Not found error?             -> usop_error_not_found "file" "/path"
Permission error?            -> usop_error_permission "/path" "read"
Validation error?            -> usop_error_validation "field" "value" "expected"
Timeout error?               -> usop_error_timeout "operation" "30"
Command failed?              -> usop_error_command_failed "cmd" 1 "stderr msg"
```

## Observability & Tracing

### I need to trace operations
```
Start trace?                 -> tid=$(trace_start "operation_name")
Record step?                 -> trace_step "$tid" "step_name" "ok|error" ["detail"]
End trace?                   -> summary=$(trace_end "$tid" "success|failed")
```

### I need function tracing
```
Trace a function?            -> trace_function "my_func"
Untrace?                     -> trace_untrace "my_func"
Trace all in file?           -> trace_all_in_file "lib/utils.sh"
Enable/disable tracing?      -> trace_enable / trace_disable
```

### I need variable watching
```
Watch variable?              -> trace_variable "MY_VAR"
Stop watching?               -> trace_unwatch "MY_VAR"
Capture snapshot?            -> trace_snapshot "before_op"
Diff snapshots?              -> diff=$(trace_diff "snap1" "snap2")
```

### I need timing
```
Start timer?                 -> trace_timer_start "operation"
Stop and get elapsed?        -> elapsed=$(trace_timer_stop "operation")
Time a command?              -> trace_timing "label" command args...
Simple timing?               -> start=$(observe_time); ... elapsed=$(observe_elapsed "$start")
```

### I need OpenTelemetry (OTEL)
```
Start OTEL trace?            -> tid=$(otel_trace_start "operation" ['{"attr":"val"}'])
End OTEL trace?              -> otel_trace_end ["$trace_id"]
Create span?                 -> sid=$(otel_span_create "name" ["$parent_id"])
End span?                    -> otel_span_end "$sid" "OK|ERROR"
Add attribute?               -> otel_span_attribute "$sid" "key" "value"
Add event?                   -> otel_span_event "$sid" "event.name" ['{"attrs":...}']
Record exception?            -> otel_span_exception "$sid" "message" ["$stacktrace"]

Context propagation?
├── Get traceparent: tp=$(otel_traceparent)
├── Inject to env: otel_context_inject
├── Extract from env: otel_context_extract
└── Parse traceparent: otel_parse_traceparent "$tp"

Export traces?
├── To OTLP endpoint: otel_export_otlp ["http://collector:4318"]
├── To JSON file: otel_export_json "/tmp/traces.json"
├── To console: otel_export_console
└── Flush pending: otel_flush
```

## Security & Capabilities

### I need capability-based permissions
```
Grant capability?            -> cap_grant "agent_id" "cap://domain/action/resource"
Revoke capability?           -> cap_revoke "agent_id" "cap://..."
Revoke all?                  -> cap_revoke_all "agent_id"
Check has capability?        -> cap_has "agent_id" "cap://..."
Use (check + log)?           -> cap_use "agent_id" "cap://..." || return 1
List agent caps?             -> cap_list "agent_id"
```

### I need capability profiles
```
Grant profile?               -> cap_grant_profile "agent_id" PROFILE

Profiles:
├── minimal: tmp read/write, echo only
├── readonly: read anywhere, safe commands (ls, cat, grep...)
├── developer: read all, write home/tmp, git, npm, python, make...
├── network: HTTP/TCP, curl, wget
└── admin: full access (use sparingly)
```

### I need guarded operations
```
Read file with cap check?    -> content=$(cap_read_file "agent" "/path")
Write file with cap check?   -> cap_write_file "agent" "/path" "content"
Execute with cap check?      -> cap_exec "agent" "git status"
Read env var?                -> home=$(cap_env_get "agent" "HOME")
Set env var?                 -> cap_env_set "agent" "MY_VAR" "value"
```

### I need capability delegation
```
Export agent's caps?         -> caps_json=$(cap_export "parent_agent")
Import caps to agent?        -> cap_import "child_agent" "$caps_json"
Delegate subset?             -> cap_delegate "parent" "child" "cap://fs/*"
```

### I need audit logging
```
Get audit log?               -> cap_audit_log [limit]
Audit log as JSON?           -> cap_audit_log_json
Count denied?                -> denied=$(cap_denied_count "agent")
Get stats?                   -> cap_stats
```

## Terminal Security (Tirith)

### I need to scan commands for security issues
```
What kind of scan?
├── Full command scan: tirith_scan_command "$cmd"
├── URL-only scan: tirith_scan_url "$url"
├── Text/input scan: tirith_scan_input "$text"
└── Trust score (0-100): score=$(tirith_url_trust_score "$url")
```

### I need to detect specific threats
```
Terminal injection?
├── ANSI escapes: tirith_check_ansi_escapes "$input"
├── BiDi controls (Trojan Source): tirith_check_bidi_controls "$input"
├── Zero-width chars: tirith_check_zero_width "$input"
├── Control chars: tirith_check_control_chars "$input"
└── Hidden multiline: tirith_check_hidden_multiline "$input"

Pipe-to-shell attacks?
├── curl | bash: tirith_check_curl_pipe_shell "$cmd"
├── wget -O- | sh: tirith_check_wget_pipe_shell "$cmd"
├── Generic pipe: tirith_check_pipe_to_interpreter "$cmd"
├── Dotfile overwrite: tirith_check_dotfile_overwrite "$cmd"
└── Unsafe archive: tirith_check_archive_extract "$cmd"

URL/hostname tricks?
├── Confusable domain: tirith_check_confusable_domain "$url"
├── Non-ASCII hostname: tirith_check_non_ascii_hostname "$url"
├── Punycode (xn--): tirith_check_punycode_domain "$url"
├── Mixed scripts: tirith_check_mixed_script "$url"
├── Userinfo trick: tirith_check_userinfo_trick "$url"
├── Raw IP URL: tirith_check_raw_ip_url "$url"
├── Non-standard port: tirith_check_non_standard_port "$url"
├── Lookalike TLD (.zip): tirith_check_lookalike_tld "$url"
├── HTTP to login/auth: tirith_check_plain_http "$url"
├── Schemeless to sink: tirith_check_schemeless "$url"
├── URL shortener: tirith_check_shortened_url "$url"
└── Insecure TLS (-k): tirith_check_insecure_tls "$cmd"

Supply chain?
├── Untrusted Docker registry: tirith_check_docker_registry "$cmd"
├── pip from URL: tirith_check_pip_url_install "$cmd"
├── npm from URL: tirith_check_npm_url_install "$cmd"
├── Web3 RPC endpoint: tirith_check_web3_rpc "$cmd"
├── Ethereum address: tirith_check_web3_address "$cmd"
└── Git typosquat: tirith_check_git_typosquat "$cmd"

Path security?
├── Non-ASCII path: tirith_check_non_ascii_path "$path"
├── Homoglyph in path: tirith_check_homoglyph_path "$path"
└── Double encoding: tirith_check_double_encoding "$path"
```

### I need to manage findings
```
Check for findings?
├── Any findings: tirith_has_findings
├── By severity: tirith_has_findings "critical"
├── Should block: tirith_should_block
└── Clear state: tirith_clear

Report findings?
├── Pretty to stderr: tirith_report
├── JSON to stdout: tirith_report_json
└── JSONL audit: tirith_audit_log "$cmd" "blocked"
```

### I need the preexec hook
```
Install hook?
├── Install: tirith_hook_install
├── Uninstall: tirith_hook_uninstall
├── Toggle pause: tirith_hook_toggle
├── Check status: tirith_hook_status
└── Bypass once: TIRITH=0 command
```

### I need to sanitize input
```
Strip dangerous chars?   -> clean=$(tirith_strip_dangerous_chars "$input")
```

## Multi-Agent Coordination

### I need to coordinate multiple agents
```
Agent Teams active?          -> agent_teams_active
                              ├── YES: Use Agent Teams native for tasks/messages
                              │   Need shared state?  -> agent_teams_awm_init (lead)
                              │                       -> agent_teams_awm_join (teammate)
                              │   Need barrier sync?  -> agent_barrier "name" count
                              │   Need mutual excl?   -> agent_lock / agent_unlock
                              └── NO: Use TMUX orchestration
                                  Spawn agent?        -> orch_agent_spawn "team"
                                  Send message?       -> orch_msg_send "agent" "msg"
                                  Distribute task?    -> orch_task_submit "team" "$task"
```

### I need shared state across agents
```
In Agent Teams?              -> agent_teams_awm_init / agent_teams_awm_join
Save key-value?              -> awm_checkpoint "key" "value"
Read key-value?              -> awm_get "key" ["default"]
Record finding?              -> awm_discovery "message" ["importance"]
Get session summary?         -> awm_summary
```

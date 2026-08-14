# MAINFRAME Decision Trees

**Quick-Reference for AI Agents: "I want to..." -> Function**

Use this guide to find the right MAINFRAME function for any task. Each entry maps an intent to one or more recommended functions with usage context.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## File Operations

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Create a file safely (no partial writes) | `atomic_write "path" "content"` | atomic |
| Ensure a file exists with content | `ensure_file "path" "content" "mode"` | idempotent |
| Modify a file with rollback capability | `file_checkpoint "path" "name"` then modify, then `file_rollback` if needed | atomic |
| Replace a file with verification | `atomic_replace "path" "content" "verify_cmd"` | atomic |
| Delete a file safely (recoverable) | `safe_remove "path"` | atomic |
| Restore a deleted file | `safe_restore "filename"` | atomic |
| Check if a file exists | `file_exists "path"` | files |
| Read file content | `read_file "path"` | files |
| Read first/last N lines | `file_head "path" N`, `file_tail "path" N` | files |
| Get a specific line number | `file_line "path" N` | files |
| Count lines in a file | `file_lines "path"` | files |
| Get file size in bytes | `file_size "path"` | files |
| Write content to a file | `file_write "path" "content"` | files |
| Append to a file | `file_append "path" "content"` | files |
| Append to a file (concurrent-safe) | `atomic_append "path" "content"` | atomic |
| Search file for pattern | `file_grep "path" "pattern"` | files |
| Checkpoint file state before changes | `file_checkpoint "path" "label"` | atomic |
| List available checkpoints | `file_checkpoints "path"` | atomic |
| Rollback to a checkpoint | `file_rollback "path" "label"` | atomic |
| Clean old checkpoints | `file_checkpoint_cleanup 3600` | atomic |
| Ensure a directory exists | `ensure_dir "path" "mode"` | idempotent |
| Ensure multiple directories | `ensure_dirs "dir1" "dir2" ...` | idempotent |
| Ensure a line in a file | `ensure_line "file" "line"` | idempotent |
| Ensure a symlink is correct | `ensure_symlink "target" "link"` | idempotent |
| Check if directory exists | `dir_exists "path"` | files |

---

## String Operations

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Trim whitespace from string | `trim_string "  text  "` | strings |
| Trim left whitespace only | `trim_left "  text"` | strings |
| Trim right whitespace only | `trim_right "text  "` | strings |
| Convert to lowercase | `to_lower "TEXT"` | strings |
| Convert to uppercase | `to_upper "text"` | strings |
| Capitalize first letter | `capitalize "hello"` | strings |
| Get string length | `strlen "text"` | strings |
| Extract substring | `substring "text" start length` | strings |
| Check if string contains substring | `contains "haystack" "needle"` | strings |
| Check prefix | `starts_with "string" "prefix"` | strings |
| Check suffix | `ends_with "string" "suffix"` | strings |
| Replace first occurrence | `replace_first "text" "old" "new"` | strings |
| Replace all occurrences | `replace_all "text" "old" "new"` | strings |
| Strip specific characters | `strip_all "text" "chars"` | strings |
| URL-encode a string | `urlencode "text with spaces"` | strings |
| URL-decode a string | `urldecode "text%20with"` | strings |
| Check if string is empty | `is_empty "$var"` | strings |
| Pad string left | `pad_left "text" width "char"` | strings |
| Pad string right | `pad_right "text" width "char"` | strings |
| Repeat a string N times | `repeat_string "ab" 3` | strings |

---

## JSON Operations

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Create a JSON object | `json_object "key=val" "age:number=30"` | json |
| Create a JSON array | `json_array "a" "b" "c"` | json |
| Create typed JSON array | `json_array_typed number 1 2 3` | json |
| Create nested JSON | `json_nested "user.name" "John"` | json |
| Read a value from JSON | `json_get '{"key":"val"}' "key"` | json |
| Get all keys from JSON | `json_keys '{"a":1,"b":2}'` | json |
| Merge two JSON objects | `json_merge '{"a":1}' '{"b":2}'` | json |
| Pretty-print JSON | `json_pretty "$json"` | json |
| Validate JSON string | `json_valid "$json"` | json |
| Escape a string for JSON | `json_escape "$unsafe"` | json |
| Create JSON string value | `json_string "text"` | json |
| Create JSON null | `json_null` | json |
| Create JSON boolean | `json_bool true` | json |

---

## Safety and Risk Assessment

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Check if a command is dangerous | `mainframe_risk_score rm -rf /tmp` | risk |
| Get full risk assessment (JSON) | `mainframe_risk_assess chmod -R 777 /etc` | risk |
| Get risk level label from score | `mainframe_risk_label 7` (returns "severe") | risk |
| Preview before executing (dry-run) | `MAINFRAME_DRY_RUN=1` then use `mainframe_plan_add` | dryrun |
| Add operation to execution plan | `mainframe_plan_add "description" cmd args` | dryrun |
| Show the current plan | `mainframe_plan_show` | dryrun |
| Show plan in JSON format | `mainframe_plan_show --format json` | dryrun |
| Execute all planned steps | `mainframe_plan_execute` | dryrun |
| Clear the current plan | `mainframe_plan_clear` | dryrun |
| Check if dry-run mode is active | `mainframe_dryrun_enabled` | dryrun |
| Record operation for undo | `mainframe_undo_record "write" "/path/file"` | undo |
| Undo last operation | `mainframe_undo` | undo |
| Undo last N operations | `mainframe_undo --steps 3` | undo |
| Undo to a specific step | `mainframe_undo --to 5` | undo |
| Initialize undo system | `mainframe_undo_init` | undo |
| Set filesystem boundaries | `mainframe_scope_set filesystem "/project:/tmp"` | scope |
| Set network boundaries | `mainframe_scope_set network "localhost,github.com"` | scope |
| Set allowed commands | `mainframe_scope_set commands "git,npm,docker"` | scope |
| Check if path is in scope | `mainframe_scope_check filesystem "/path"` | scope |
| Check if host is in scope | `mainframe_scope_check network "example.com"` | scope |
| Check if command is in scope | `mainframe_scope_check commands "rm"` | scope |
| Get current scope settings | `mainframe_scope_get filesystem` | scope |
| Clear scope restrictions | `mainframe_scope_clear filesystem` | scope |
| Wrap command with safety checks | `guard_file_op write "/var/log/app.log"` | guard |
| Prevent path traversal attacks | `guard_path_safe "/base" "$user_path"` | guard |
| Check for dangerous path chars | `guard_path_chars "$path"` | guard |
| Guard against symlink attacks | `guard_symlink "/link" reject` | guard |
| Verify before destructive ops | `guard_destructive_path "$dir"` | guard |

---

## Validation and Sanitization

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Validate email address | `validate_email "user@domain.com"` | validation |
| Validate URL | `validate_url "https://example.com"` | validation |
| Validate integer (with range) | `validate_int "42" 0 100` | validation |
| Validate float | `validate_float "3.14"` | validation |
| Validate boolean | `validate_bool "true"` | validation |
| Validate IPv4 address | `validate_ipv4 "192.168.1.1"` | validation |
| Validate IPv6 address | `validate_ipv6 "::1"` | validation |
| Validate date format | `validate_date "2024-01-15"` | validation |
| Validate time format | `validate_time "14:30:00"` | validation |
| Validate semantic version | `validate_semver "1.2.3"` | validation |
| Validate port number | `validate_port "8080"` | validation |
| Validate UUID | `validate_uuid "$id"` | validation |
| Validate path is safe | `validate_path_safe "$path" "/base"` | validation |
| Validate filename (no path) | `validate_filename "report.pdf"` | validation |
| Validate path characters | `validate_path_chars "/safe/path"` | validation |
| Validate string length | `validate_length "text" 1 100` | validation |
| Validate against enum | `validate_enum "a" "a" "b" "c"` | validation |
| Validate all items in array | `validate_all validate_int 1 2 3` | validation |
| Validate JSON syntax | `validate_json '{"a":1}'` | validation |
| Validate regex match | `validate_regex "abc" "^[a-z]+$"` | validation |
| Sanitize for shell execution | `sanitize_shell_arg "$input"` | validation |
| Sanitize filename | `sanitize_filename "bad/name<>.txt"` | validation |
| Sanitize for HTML output | `sanitize_html "<script>alert(1)"` | validation |
| Sanitize for SQL | `sanitize_sql "O'Brien"` | validation |
| Validate command is safe | `validate_command_safe "ls -la"` | validation |
| Build escaped command | `build_safe_command "grep" "$pat" "$file"` | validation |
| Validate MAC address | `validate_mac "00:1A:2B:3C:4D:5E"` | validation |
| Validate CIDR notation | `validate_cidr "192.168.1.0/24"` | validation |

---

## Process and Async Operations

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Run command with timeout | `run_with_timeout 30 "command"` | safe |
| Retry on failure (exponential) | `retry_backoff 5 "curl -sf $url"` | safe |
| Retry with jitter | `retry_backoff_jitter 5 "cmd" 1 60` | safe |
| Retry with callback on failure | `retry_with_callback 3 "cmd" on_fail` | safe |
| Run commands in parallel | `parallel "task1" "task2" "task3"` | async |
| Limit parallel concurrency | `parallel_limit 4 "${tasks[@]}"` | async |
| Basic retry (N attempts) | `retry 3 "curl $url"` | async |
| Debounce rapid calls | `debounce 100 "save"` | async |
| Schedule delayed execution | `set_timeout 5 "task"` | async |
| Check if process exists | `proc_exists $pid` | process |
| Find process by port | `proc_find_by_port 8080` | process |
| Find process by name | `proc_find_by_name "node"` | process |
| Get process memory usage | `proc_memory $pid` | process |
| Get process CPU usage | `proc_cpu $pid` | process |
| Kill process gracefully | `proc_kill $pid` | process |
| Kill entire process tree | `proc_kill_tree $pid` | process |
| Wait for process with timeout | `proc_wait_timeout $pid 30` | process |
| Acquire exclusive lock | `lockfile_acquire "/tmp/app.lock"` | process |
| Release lock | `lockfile_release "/tmp/app.lock"` | process |
| Run with lock held | `with_lock "/tmp/lock" "command"` | process |
| Run without triggering errexit | `unsafe_run "grep pattern file"` | safe |
| Capture exit code safely | `safe_exit_code "test -f x"` | safe |
| Capture stdout and stderr | `capture_both out err "make"` | safe |
| Enable strict mode | `enable_strict_mode` | safe |

---

## Network Operations

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Check if port is open | `port_check "localhost" 8080` | netscan |
| Check if host is reachable | `host_alive "192.168.1.1" 5` | netscan |
| Grab service banner | `banner_grab "host" 22` | netscan |
| Get HTTP response headers | `http_headers "http://localhost:8080"` | netscan |
| Scan multiple ports | `scan_range "host" "22,80,443,8080"` | netscan |
| Monitor a port (JSON) | `monitor_port "localhost" 5432` | netscan |
| Make HTTP GET request | `http_get "http://api.example.com"` | http |
| Make HTTP POST request | `http_post "http://api.example.com" "data"` | http |
| Make HTTP PUT request | `http_put "http://api.example.com/1" "{}"` | http |
| Make HTTP DELETE request | `http_delete "http://api.example.com/1"` | http |
| POST JSON data | `http_json_post "$url" '{"key":"val"}'` | http |
| Parse URL components | `url_parse "https://host:8080/path?q=1"` | http |
| Build query string | `query_string "a=1" "b=2"` | http |
| Set auth header (Bearer) | `http_auth_bearer "token123"` | http |
| Set auth header (Basic) | `http_auth_basic "user" "pass"` | http |
| Check if last request succeeded | `http_is_success` | http |
| Download a file | `http_download "url" "output_path"` | http |

---

## Path Operations

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Normalize messy path | `path_normalize "/foo//bar/../baz"` | path |
| Get absolute path | `path_absolute "relative/path"` | path |
| Get relative path | `path_relative "/a/b/c" "/a"` | path |
| Join path segments | `path_join "/foo" "bar" "baz"` | path |
| Get directory component | `path_dir "/foo/bar/file.txt"` | path |
| Get filename component | `path_base "/foo/bar/file.txt"` | path |
| Get file extension | `path_ext "/foo/bar.tar.gz"` | path |
| Get filename without extension | `path_stem "/foo/bar.txt"` | path |
| Replace file extension | `path_replace_ext "doc.txt" "md"` | path |
| Check path safety (no traversal) | `path_is_safe "/base" "$user_path"` | path |
| Quote path with spaces | `path_quote "/path with spaces"` | path |
| Convert Windows to Unix path | `path_to_unix "C:\Users\foo"` | path |
| Convert Unix to Windows path | `path_to_windows "/c/Users/foo"` | path |
| Expand tilde in path | `path_expand_tilde "~/Documents"` | path |
| Sanitize path for filesystem | `path_sanitize "file: <bad>.txt"` | path |
| Check if path is absolute | `path_is_absolute "/foo"` | path |
| Check if path has parent refs | `path_has_parent_ref "../foo"` | path |
| Get path depth | `path_depth "/foo/bar/baz"` | path |
| Find common prefix of paths | `path_common_prefix "/a/b/c" "/a/b/d"` | path |
| Generate unique filename | `path_unique "/foo/bar.txt"` | path |

---

## Caching and Memoization

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Memoize a function call | `memoize expensive_func "arg1"` | cache |
| Memoize with TTL expiration | `memoize --ttl 300 func "arg"` | cache |
| Memoize with file dependency | `memoize --invalidate-on config.json func` | cache |
| Store value in session cache | `session_cache_set "key" "value"` | cache |
| Get value from session cache | `session_cache_get "key" "default"` | cache |
| Clear session cache | `session_cache_clear` | cache |
| Store content by hash (CAS) | `hash=$(cas_store "content")` | cache |
| Retrieve content by hash | `content=$(cas_get "$hash")` | cache |
| Check if hash exists in CAS | `cas_exists "$hash"` | cache |
| Invalidate cached entries | `cache_invalidate "pattern*"` | cache |
| Clear entire cache | `cache_clear --force` | cache |
| Get cache statistics | `cache_stats --json` | cache |
| Evict least-recently-used | `cache_evict_lru 100` | cache |
| Register file dependencies | `cache_depends_on "$key" file1 file2` | cache |
| Check dependency validity | `cache_check_deps "$key"` | cache |

---

## Observability and Tracing

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Start a trace for operation | `tid=$(trace_start "operation_name")` | observe |
| Record a step in trace | `trace_step "$tid" "step_name" "ok"` | observe |
| End trace and get summary | `summary=$(trace_end "$tid" "success")` | observe |
| Observe a command (full JSON) | `result=$(observe_command npm test)` | observe |
| Get stack trace as JSON | `trace=$(stack_trace)` | observe |
| Emit structured error | `observe_error 2 "msg" "context"` | observe |
| Time a section of code | `start=$(observe_time)` ... `elapsed=$(observe_elapsed "$start")` | observe |
| Benchmark a command | `perf_benchmark "command" 100` | perf |
| Compare two implementations | `perf_compare "cmd1" "cmd2" 1000` | perf |
| Start a named timer | `perf_timer_start "operation"` | perf |
| Get elapsed time | `perf_timer_elapsed "operation"` | perf |
| Stop timer and get JSON | `perf_timer_stop "operation"` | perf |
| Enable error stack traces | `enable_error_context` | safe |
| Lint a bash script | `lint_script "script.sh" warning` | safe |
| Check script syntax | `check_syntax "script.sh"` | safe |

---

## DateTime Operations

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Get current Unix timestamp | `now` | datetime |
| Get current time in ISO format | `now_iso` | datetime |
| Get millisecond timestamp | `now_ms` | datetime |
| Add duration to timestamp | `date_add $(now) "2d"` | datetime |
| Subtract duration | `date_subtract $(now) "1w"` | datetime |
| Get difference between dates | `date_diff $epoch1 $epoch2` | datetime |
| Get human-readable diff | `date_diff_human $e1 $e2` | datetime |
| Format as relative time | `format_relative $epoch` (e.g., "2 hours ago") | datetime |
| Format epoch as ISO | `format_iso $epoch` | datetime |
| Format epoch as date | `format_date $epoch` | datetime |
| Parse ISO string to epoch | `parse_iso "2024-01-15T10:30:00Z"` | datetime |
| Check if weekend | `is_weekend` | datetime |
| Get day of week | `day_of_week` | datetime |
| Get start of day | `start_of_day` | datetime |
| Get end of day | `end_of_day` | datetime |
| Check if leap year | `is_leap_year 2024` | datetime |

---

## Array Operations

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Get array length | `array_length "${arr[@]}"` | arrays |
| Get first element | `array_first "${arr[@]}"` | arrays |
| Get last element | `array_last "${arr[@]}"` | arrays |
| Get element by index | `array_get index "${arr[@]}"` | arrays |
| Check if contains value | `array_contains "val" "${arr[@]}"` | arrays |
| Find index of value | `array_index_of "val" "${arr[@]}"` | arrays |
| Join with separator | `array_join "," "${arr[@]}"` | arrays |
| Remove duplicates | `array_unique "${arr[@]}"` | arrays |
| Sort array | `array_sort "${arr[@]}"` | arrays |
| Reverse array | `array_reverse "${arr[@]}"` | arrays |
| Slice array | `array_slice start inclusive_end "${arr[@]}"` | arrays |
| Sum numeric array | `array_sum "${nums[@]}"` | arrays |
| Get min/max | `array_min`, `array_max` | arrays |
| Remove element | `array_remove arr "val"` | arrays |
| Array difference | `left=(a b c); right=(b); array_diff left right` | arrays |
| Array intersection | `left=(a b); right=(b c); array_intersect left right` | arrays |

---

## Functional Programming

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Transform each element | `fp_map double 1 2 3 4 5` | functional |
| Filter by predicate | `fp_filter is_even 1 2 3 4 5` | functional |
| Reduce to single value | `fp_reduce sum 0 1 2 3 4 5` | functional |
| Find first match | `fp_find is_even 1 3 5 6 7` | functional |
| Check if any match | `fp_any is_negative 1 2 -3` | functional |
| Check if all match | `fp_all is_positive 1 2 3` | functional |
| Partition into two groups | `fp_partition_v matches rejects pred` | functional |
| Take first N elements | `fp_take 3 a b c d e` | functional |
| Take while predicate holds | `fp_take_while is_positive 1 2 -1 3` | functional |
| Drop first N elements | `fp_drop 2 a b c d e` | functional |
| Compose functions (right-left) | `fp_compose increment double` | functional |
| Pipe functions (left-right) | `fp_pipe double increment` | functional |
| Count matching elements | `fp_count is_even 1 2 3 4 5 6` | functional |
| High-performance map (no subshell) | `fp_map_v results func args...` | functional |

---

## Git Operations

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Get current branch | `git_branch` | git |
| Check if repo is dirty | `git_is_dirty` | git |
| Check if repo is clean | `git_is_clean` | git |
| Get short commit hash | `git_commit_hash` | git |
| Get commit message | `git_commit_message` | git |
| List changed files | `git_files_changed` | git |
| Get latest tag | `git_tag_latest` | git |
| Check if tag exists | `git_tag_exists "v1.0.0"` | git |
| Get repo root path | `git_root` | git |
| Get remote URL | `git_remote_url` | git |
| Check if pushed to remote | `git_is_pushed` | git |
| Get git summary (JSON-like) | `git_summary` | git |
| Get files changed since ref | `git_changed_since "HEAD~5"` | git |
| Get commit count | `git_commit_count` | git |

---

## Docker Operations

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Check if Docker daemon runs | `docker_running` | docker |
| Check if container is running | `docker_container_running "name"` | docker |
| Get container status | `docker_container_status "name"` | docker |
| Execute command in container | `docker_exec "name" "cmd"` | docker |
| Get container logs | `docker_logs "name" 100` | docker |
| Get container CPU/memory | `docker_stats_json "name"` | docker |
| Check if port used by Docker | `docker_port_used 8080` | docker |
| Find container using port | `docker_port_container 8080` | docker |
| Start a container | `docker_container_start "name"` | docker |
| Stop a container | `docker_container_stop "name"` | docker |
| Start compose services | `compose_up` | docker |
| Stop compose services | `compose_down` | docker |
| Execute in compose service | `compose_exec "web" "npm test"` | docker |
| Check compose service status | `compose_running "web"` | docker |
| Get container IP address | `docker_container_ip "name"` | docker |
| Pull an image | `docker_image_pull "nginx:alpine"` | docker |
| Prune unused resources | `docker_prune_all` | docker |

---

## Environment Management

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Set and export variable | `env_set "VAR" "value"` | environment |
| Get variable with default | `env_get "VAR" "fallback"` | environment |
| Require variable (exit if missing) | `env_require "API_KEY" "message"` | environment |
| Require multiple variables | `env_require_all DB_HOST DB_PORT` | environment |
| Add to PATH (front) | `env_path_prepend "/opt/bin"` | environment |
| Add to PATH (back) | `env_path_append "/opt/bin"` | environment |
| Remove from PATH | `env_path_remove "/old/bin"` | environment |
| Clean PATH duplicates | `env_path_clean` | environment |
| Load .env file | `env_load_dotenv ".env"` | environment |
| Save vars to .env file | `env_save_dotenv "out.env" VAR1 VAR2` | environment |
| Persist across sessions | `env_persist "VAR" "value"` | environment |
| Run with temporary env | `env_with "DEBUG=1" ./script.sh` | environment |
| Detect current shell | `env_detect_shell` | environment |
| Get shell config file | `env_config_file` | environment |
| Get as integer with default | `env_get_int "PORT" 8080` | environment |
| Get as boolean | `env_get_bool "DEBUG"` | environment |

---

## Crypto and Hashing

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Hash with SHA-256 | `sha256 "data"` | crypto |
| Hash a file (SHA-256) | `sha256_file "path"` | crypto |
| Hash with MD5 | `md5 "data"` | crypto |
| Generate HMAC signature | `hmac_sha256 "key" "message"` | crypto |
| Base64 encode | `base64_encode "data"` | crypto |
| Base64 decode | `base64_decode "encoded"` | crypto |
| Generate random token | `random_token 32` | crypto |
| Generate random password | `generate_password 16` | crypto |
| Generate random hex string | `random_hex 32` | crypto |
| Verify file checksum | `checksum_verify "file" "$hash"` | crypto |
| Hash a password | `password_hash "secret"` | crypto |
| Verify password hash | `password_verify "secret" "$hash"` | crypto |

---

## CSV Operations

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Parse a CSV line | `csv_parse_line '"a","b","c"'` | csv |
| Read entire CSV file | `csv_read "data.csv"` | csv |
| Get field by column name | `csv_get row_num "column"` | csv |
| Create a CSV row | `csv_row "val1" "val2" "val3"` | csv |
| Convert CSV to JSON | `csv_to_json "data.csv"` | csv |
| Filter CSV rows | `csv_filter "file" "col" "val"` | csv |
| Sort CSV by column | `csv_sort "file" "column"` | csv |
| Get row count | `csv_row_count "data.csv"` | csv |
| Validate CSV format | `csv_validate "data.csv"` | csv |
| Escape value for CSV | `csv_escape "has, comma"` | csv |

---

## Format Parsing

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Parse key=value config | `parse_key_value < config.conf` | parsers |
| Parse INI file | `parse_ini < config.ini` | parsers |
| Parse URL into components | `parse_url "https://host:8080/path"` | parsers |
| Parse semantic version | `parse_semver "1.2.3-beta.1"` | parsers |
| Compare semantic versions | `semver_compare "1.2.3" "1.3.0"` | parsers |
| Bump major version | `semver_bump_major "1.2.3"` | semver |
| Bump minor version | `semver_bump_minor "1.2.3"` | semver |
| Bump patch version | `semver_bump_patch "1.2.3"` | semver |
| Sort versions | `semver_sort "2.0" "1.0" "3.0"` | semver |

---

## Project Intelligence

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Detect project type/framework | `project_detect .` | project |
| Get build/test commands | `project_commands .` | project |
| Find entry point files | `project_entry .` | project |
| Analyze dependencies | `project_deps .` | project |
| Get project structure | `project_structure . 2` | project |

---

## Design-by-Contract

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Assert precondition | `contract_require "[[ -f $f ]]" "file needed"` | contract |
| Assert postcondition | `contract_ensure "[[ -f $out ]]" "not created"` | contract |
| Assert invariant | `contract_invariant "[[ $n -ge 0 ]]" "negative"` | contract |
| Type-check a value | `contract_type_check "8080" "int" "port"` | contract |
| Assert value in range | `contract_in_range $port 1 65535 "port"` | contract |
| Assert non-empty args | `contract_not_empty "$arg1" "$arg2"` | contract |
| Assert file exists | `contract_is_file "/path" "config"` | contract |
| Assert directory exists | `contract_is_dir "/path" "data dir"` | contract |
| Emit structured error | `mainframe_error 2 "msg" "key=val"` | contract |
| Disable contracts (production) | `contracts_disable` | contract |

---

## Metaprogramming

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Get variable by name | `var_get "varname"` | meta |
| Set variable by name | `var_set "varname" "value"` | meta |
| Check if variable exists | `var_exists "varname"` | meta |
| Get variable type | `var_type "varname"` | meta |
| Create readonly constant | `const "PI" "3.14159"` | meta |
| Check if function exists | `func_exists "funcname"` | meta |
| Call function by name | `call_func "funcname" args...` | meta |
| Find functions by prefix | `funcs_with_prefix "test_" results` | meta |
| Find variables by prefix | `vars_with_prefix "CONFIG_" vars` | meta |
| Dynamic method dispatch | `call_method "obj" "method" args` | meta |
| Increment variable | `var_incr "counter" 5` | meta |
| Create name reference | `var_ref "alias" "original"` | meta |

---

## Formatting and Display

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Format bytes (human-readable) | `format_bytes 1048576` (returns "1.0MB") | utils |
| Format duration (seconds) | `format_duration 3661` (returns "1h 1m 1s") | utils |
| Format large numbers | `format_number 1234567` (returns "1,234,567") | utils |
| Format percentage | `format_percent 75 100` | utils |
| Show progress bar | `progress_bar 50 100` | common |
| Print colored text | `ansi_print red "Error message"` | ansi |
| Print styled text | `ansi_styled "bold,red" "text"` | ansi |
| Generate UUID | `uuid` | utils |
| Get timestamp | `timestamp` | utils |

---

## Process Substitution (Subshell Avoidance)

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Read command output into array | `read_lines_from "ls -1" files` | procsub |
| Process lines keeping variables | `for_each_line "cat file" 'handle $line'` | procsub |
| Map function over lines | `map_lines_from "seq 3" func results` | procsub |
| Filter lines by predicate | `filter_lines_from "cmd" pred results` | procsub |
| Reduce lines to value | `reduce_lines_from "cmd" fn init var` | procsub |
| Capture output to variable | `capture_output var "cmd"` | procsub |
| Diff two command outputs | `diff_commands "cmd1" "cmd2"` | procsub |
| Count lines without subshell | `count_lines_from "cmd" var` | procsub |
| Read key=value pairs | `read_pairs_from "cat conf" map "="` | procsub |
| Process in batches | `batch_lines_from "cmd" 10 callback` | procsub |

---

## Configuration

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Load config file | `config_load "app.conf"` | config |
| Get config value | `config_get "key"` | config |
| Get config as integer | `config_get_int "port"` | config |
| Get config as boolean | `config_get_bool "debug"` | config |
| Set config value | `config_set "key" "value"` | config |
| Check if key exists | `config_has "key"` | config |
| Save config to file | `config_save "app.conf"` | config |

---

## Guard and Defense

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Enable all protections | `guard_init` | guard |
| Register cleanup on exit | `guard_on_exit "rm -f /tmp/lock"` | guard |
| Verify path exists | `guard_path_exists "/path" file` | guard |
| Prevent path traversal | `guard_path_safe "/base" "$user_input"` | guard |
| Verify variable is set | `guard_var_set "API_KEY" true` | guard |
| Check for injection in var | `guard_var_safe "$input"` | guard |
| Check array bounds | `guard_array_bounds arr 5` | guard |
| Verify command exists | `guard_command jq "apt install jq"` | guard |
| Check multiple commands | `guard_commands git curl jq` | guard |
| Verify OS compatibility | `guard_os linux` | guard |
| Acquire exclusive lock | `guard_lock "/tmp/app.lock" 30` | guard |
| Check disk space | `guard_disk_space "/var" 1073741824` | guard |
| Check available memory | `guard_memory 536870912` | guard |
| Validate integer in range | `guard_integer "$port" 1 65535` | guard |

---

## Performance and Feature Gates

| I want to... | Function(s) | Module |
|--------------|-------------|--------|
| Check bash version | `bash_version` | perf |
| Check if version at least X | `bash_version_at_least 5 0` | perf |
| Check if feature available | `bash_has_feature "namerefs"` | perf |
| List all features (JSON) | `bash_features` | perf |
| Set variable without subshell | `perf_setvar "var" "value"` | perf |
| Capture output without subshell | `perf_capture "var" cmd args` | perf |

---

*MAINFRAME Decision Trees | 200+ entries across 20 categories*

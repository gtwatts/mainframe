---
name: mainframe-bash
description: Pure bash standard library with 1100+ functions across 37 libraries. Use when writing bash scripts, shell automation, CLI tools, or any task requiring string manipulation, JSON generation, arrays, file operations, validation, HTTP, CSV, git, crypto, async, process management, path handling, docker, or datetime in bash. Eliminates need for sed, awk, jq, and external tools. Source with `source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"`.
---

# MAINFRAME - Pure Bash Standard Library

1100+ pure bash functions across 37 libraries. Zero external dependencies. 20-72x faster than spawning sed/awk/jq.

## When to Use This Skill

Use MAINFRAME when:
- Writing ANY bash script (always source it first)
- Manipulating strings (trim, split, replace, pad, encode)
- Working with arrays (sort, filter, unique, join, diff)
- Generating JSON without jq
- Validating user input (email, URL, IP, paths, integers)
- Sanitizing input for security (HTML, SQL, shell, filenames)
- Processing CSV/TSV files
- Making HTTP requests in pure bash
- Performing date/time arithmetic
- Managing processes, locks, and PID files
- Handling paths safely (normalize, traverse prevention)
- Working with git repositories programmatically
- Hashing and encoding (SHA-256, MD5, base64, HMAC)
- Running parallel/async operations
- Building CLI tools with progress bars, colored output, config files
- Analyzing TypeScript projects (imports, API diffs, bundle size)

## Installation Check

```bash
# Verify MAINFRAME is installed
if [[ -f "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh" ]]; then
    echo "MAINFRAME ready"
else
    echo "Install: git clone https://github.com/gtwatts/mainframe.git ~/.mainframe"
    echo "Then: export MAINFRAME_ROOT=\"\$HOME/.mainframe\""
fi
```

## Script Template

Every bash script MUST start with:

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

This loads the core library. Additional libraries are lazy-loaded on first function call.

## Core Function Reference

### Logging & Output

```bash
log_info "Starting process..."    # [INFO] Starting process...
log_warn "Disk space low"         # [WARN] Disk space low
log_error "Connection failed"     # [ERROR] Connection failed
success "Deployment complete"     # [OK] Deployment complete
failure "Tests failed"            # [FAIL] Tests failed
header "Section Name"             # ═══ Section Name ═══
die 1 "Fatal: config missing"    # Prints error and exits with code
progress_bar 75 100               # [████████░░] 75%
```

### Strings

```bash
trim_string "  hello  "           # "hello"
to_lower "HELLO"                  # "hello"
to_upper "hello"                  # "HELLO"
capitalize "hello world"          # "Hello world"
strlen "hello"                    # 5
substring "hello" 0 3             # "hel"
contains "hello" "ell"            # returns 0 (true)
starts_with "hello" "hel"         # returns 0
ends_with "hello" "lo"            # returns 0
replace_all "foo bar foo" "foo" "baz"  # "baz bar baz"
split_string "a,b,c" ","         # outputs a\nb\nc
urlencode "hello world"           # "hello%20world"
urldecode "hello%20world"         # "hello world"
pad_left "42" 5 "0"              # "00042"
repeat_string "ab" 3              # "ababab"
```

### Arrays

```bash
arr=(5 3 1 4 2)
array_length "${arr[@]}"          # 5
array_first "${arr[@]}"           # 5
array_last "${arr[@]}"            # 2
array_contains "3" "${arr[@]}"    # returns 0
array_index_of "4" "${arr[@]}"    # 3
array_join ", " "${arr[@]}"       # "5, 3, 1, 4, 2"
array_sort "${arr[@]}"            # "1 2 3 4 5"
array_reverse "${arr[@]}"         # "2 4 1 3 5"
array_unique 1 2 2 3 3            # "1 2 3"
array_slice 1 3 "${arr[@]}"       # "3 1 4"
array_sum "${arr[@]}"             # 15
array_min "${arr[@]}"             # 1
array_max "${arr[@]}"             # 5
array_remove "3" "${arr[@]}"      # "5 1 4 2"
array_diff "1 2 3" "2"           # "1 3"
array_intersect "1 2 3" "2 3 4"  # "2 3"
array_filter "is_int" "${arr[@]}" # filter by predicate
```

### JSON (No jq Required)

```bash
# Create objects - key=val for strings, key:type=val for typed
json_object "name=John" "age:number=30" "active:bool=true"
# Output: {"name":"John","age":30,"active":true}

# Create arrays
json_array "apple" "banana" "cherry"
# Output: ["apple","banana","cherry"]

json_array_typed number 1 2 3
# Output: [1,2,3]

# Nested objects
json_nested "user.address.city" "NYC"
# Output: {"user":{"address":{"city":"NYC"}}}

# Query
json_get '{"name":"John","age":30}' "name"   # "John"
json_keys '{"a":1,"b":2}'                     # "a b"
json_merge '{"a":1}' '{"b":2}'               # {"a":1,"b":2}
json_valid '{"a":1}'                          # returns 0
json_pretty '{"a":1,"b":2}'                   # formatted output

# Compose complex responses
response=$(json_object \
    status="success" \
    id="$(uuid)" \
    timestamp="$(timestamp_iso)" \
    count:number=42 \
    active:bool=true \
)
```

### DateTime

```bash
now                               # 1705312896 (Unix epoch)
now_ms                            # 1705312896123
now_iso                           # 2024-01-15T10:30:00-0500
now_rfc2822                       # Mon, 15 Jan 2024 10:30:00 -0500

# Arithmetic (durations: Ns, Nm, Nh, Nd, Nw)
date_add $(now) "2d"              # epoch + 2 days
date_subtract $(now) "1w"         # epoch - 1 week
date_diff $epoch1 $epoch2         # difference in seconds
date_diff_human $e1 $e2           # "1 day, 2 hours"

# Formatting
format_iso                        # current time as ISO
format_relative $past_epoch       # "2 hours ago"
format_epoch $epoch "%Y-%m-%d"    # "2024-01-15"

# Components
year; month; day                  # current parts
day_of_week                       # "Monday"
is_weekend                        # returns 0/1
is_leap_year 2024                 # returns 0
start_of_day; end_of_day          # epoch boundaries
```

### Validation & Sanitization (Security-Critical)

```bash
# Type validation
validate_int "42" 0 100           # integer in range
validate_float "3.14"             # valid float
validate_bool "true"              # true/false/yes/no/1/0

# Format validation
validate_email "user@domain.com"
validate_url "https://example.com"
validate_ipv4 "192.168.1.1"
validate_date "2024-01-15"
validate_semver "1.2.3"
validate_port "8080"
validate_uuid "550e8400-..."
validate_json '{"a":1}'

# Path safety (PREVENTS TRAVERSAL ATTACKS)
validate_path_safe "$user_path" "/allowed/base"
validate_filename "report.pdf"    # no path components
validate_path_chars "/safe/path"  # safe characters only

# Sanitization
sanitize_shell_arg "$user_input"  # safe for shell
sanitize_filename "a/b<c>.txt"    # "a_b_c_.txt"
sanitize_html "<script>alert(1)"  # "&lt;script&gt;alert(1)"
sanitize_sql "O'Brien"            # "O''Brien"
sanitize_json 'say "hi"'         # 'say \"hi\"'

# Command safety
validate_command_safe "ls -la"    # no injection patterns
build_safe_command "grep" "$pat" "$file"  # properly escaped
```

### HTTP (Pure Bash)

```bash
# Methods
http_get "http://api.example.com/data"
http_post "http://api.example.com" '{"name":"test"}'
http_put "http://api.example.com/1" '{"name":"updated"}'
http_delete "http://api.example.com/1"

# JSON convenience
http_json_get "http://api.example.com/users"
http_json_post "http://api.example.com/users" '{"name":"new"}'

# Response handling
http_status                       # 200
http_body                         # response body
http_is_success                   # returns 0 for 2xx

# Auth headers
http_auth_basic "user" "pass"
http_auth_bearer "token123"

# URL utilities
url_parse "http://host:8080/path?q=1"  # sets URL_SCHEME, URL_HOST, URL_PORT, URL_PATH, URL_QUERY
url_encode "hello world"          # "hello%20world"
query_string "a=1" "b=2"         # "a=1&b=2"
```

**Note**: Pure bash HTTP for port 80. HTTPS requires openssl on the system.

### CSV Processing

```bash
# Read and query
csv_read "users.csv"              # sets CSV_HEADERS + CSV_ROWS
csv_get 0 "name"                  # first row, "name" column
csv_column "email"                # all values in email column
csv_row_count "data.csv"          # number of rows

# Create
csv_row "John" "john@ex.com"     # "John,john@ex.com"
csv_header "name" "email" "age"  # "name,email,age"
csv_escape 'has, comma'          # '"has, comma"'
csv_append_row "f.csv" "a" "b"   # append to file

# Transform
csv_filter "f.csv" "status" "active"  # filtered rows
csv_sort "f.csv" "name"          # sorted by column
csv_select "f.csv" "name,email"  # select columns
csv_to_json "data.csv"           # JSON array output
csv_validate "data.csv"          # check well-formedness
csv_delimiter "\t"               # switch to TSV mode
```

### Git Operations

```bash
git_is_repo                       # returns 0 if in git repo
git_root                          # /path/to/repo/root
git_branch                        # current branch name
git_default_branch                # "main" or "master"
git_is_dirty                      # returns 0 if uncommitted changes
git_is_clean                      # opposite of is_dirty
git_has_staged                    # staged changes?
git_files_changed                 # list of modified files
git_commit_hash                   # short hash
git_commit_message                # latest commit message
git_commit_count                  # total commits
git_commits_ahead                 # ahead of upstream
git_commits_behind                # behind upstream
git_tag_latest                    # latest tag
git_remote_url                    # remote URL
git_summary                       # "main @ abc1234 [clean]"
git_log_oneline 5                 # last 5 commits
git_changed_since "HEAD~5"        # files changed in last 5 commits
```

### Crypto & Encoding

```bash
# Hashing
sha256 "data"                     # SHA-256 hash
sha512 "data"                     # SHA-512 hash
md5 "data"                        # MD5 hash
sha256_file "file.bin"            # hash a file
hmac_sha256 "secret_key" "message"  # HMAC signature

# Encoding
base64_encode "hello"             # "aGVsbG8="
base64_decode "aGVsbG8="          # "hello"
hex_encode "hi"                   # "6869"
hex_decode "6869"                 # "hi"

# Tokens & Passwords
random_token 32                   # URL-safe random token
random_hex 16                     # random hex string
random_bytes 16                   # raw random bytes
generate_password 16              # complex random password

# Verification
checksum "file.tar.gz"            # SHA-256 of file
checksum_verify "file" "$hash"    # returns 0 if matches
password_hash "secret"            # hash password
password_verify "secret" "$hash"  # verify password
```

### Process Management

```bash
proc_exists $pid                  # is process running?
proc_find_by_port 8080            # PID using port
proc_find_by_name "node"          # PIDs matching name
proc_memory $pid                  # memory in KB
proc_cpu $pid                     # CPU percentage

# PID files
pidfile_create "/tmp/app.pid"
pidfile_check "/tmp/app.pid"      # returns 0 if running
pidfile_remove "/tmp/app.pid"

# Locking
lockfile_acquire "/tmp/app.lock" 10  # acquire with 10s timeout
lockfile_release "/tmp/app.lock"
with_lock "/tmp/app.lock" "exclusive_task"  # run under lock

# Signals
proc_kill $pid                    # SIGTERM
proc_kill_force $pid              # SIGKILL
proc_kill_tree $pid               # kill entire tree
proc_wait_timeout $pid 30         # wait up to 30s

# System
proc_count                        # total processes
proc_load                         # load average
proc_uptime_human                 # "5 days, 3 hours"
```

### Async & Parallel

```bash
# Run commands in parallel
parallel "task1" "task2" "task3"

# Limit concurrency
parallel_limit 4 "${tasks[@]}"

# Map function over items
parallel_map "process_item" "${items[@]}"

# Retry with backoff
retry 5 "curl http://flaky.api/data"

# Timers (like JavaScript)
pid=$(set_timeout 5 "echo done")   # run after 5s
pid=$(set_interval 10 "heartbeat") # run every 10s
clear_timeout $pid                  # cancel timer

# Debounce/throttle
debounce "save_state" 2            # wait 2s of inactivity
throttle "api_call" 5              # max once per 5s
```

### Path Manipulation

```bash
path_normalize "/foo//bar/../baz"   # "/foo/baz"
path_absolute "relative/path"       # "/cwd/relative/path"
path_relative "/a/b/c" "/a"         # "b/c"
path_join "/base" "sub" "file.txt"  # "/base/sub/file.txt"
path_dir "/foo/bar/file.txt"        # "/foo/bar"
path_base "/foo/bar/file.txt"       # "file.txt"
path_ext "/foo/bar.tar.gz"          # "gz"
path_stem "/foo/bar.tar.gz"         # "bar.tar"
path_replace_ext "doc.txt" "md"     # "doc.md"

# Safety
path_is_safe "/allowed" "$user_path"  # prevents traversal
path_sanitize "file: <bad>.txt"       # "file_bad.txt"
path_quote "/path with spaces"        # properly escaped

# Cross-platform
path_to_unix "C:\Users\foo"        # "/c/Users/foo"
path_to_windows "/c/Users/foo"     # "C:\Users\foo"
path_expand_tilde "~/Documents"    # "/home/user/Documents"
```

### Docker

```bash
docker_running                     # daemon alive?
docker_container_running "nginx"   # container alive?
docker_container_status "nginx"    # "running"/"exited"
docker_exec "nginx" "nginx -t"    # run in container
docker_logs "nginx" 100            # last 100 log lines
docker_stats_json "nginx"          # CPU/memory JSON
docker_port_used 8080              # port taken by docker?
compose_up                         # docker compose up -d
compose_running "web"              # compose service alive?
compose_exec "web" "npm run migrate"
```

### TypeScript Analysis (no tsc required)

```bash
# Project detection
ts_is_project "$dir"              # has tsconfig.json?
ts_source_dir "$dir"              # rootDir from tsconfig

# Import analysis (TypeMiner)
ts_file_imports "src/index.ts"    # extract imports from file
ts_import_frequency "$dir"        # most-used modules
ts_import_graph "$dir"            # dependency graph
ts_circular_deps "$dir"           # detect circular deps
ts_type_only_imports "$dir"       # should be 'import type'

# API breaking changes (TypeDiff)
ts_api_extract "api.d.ts"         # public API from .d.ts
ts_api_diff "v1.d.ts" "v2.d.ts"  # +added/-removed
ts_breaking_changes "v1" "v2"     # detect breaks
ts_api_summary "v1" "v2"          # semver suggestion

# Bundle size (ImportCost)
ts_import_cost "express" "$dir"   # package size (bytes)
ts_import_cost_js "pkg" "$dir"    # JS-only size
ts_import_cost_file "f.ts" "$dir" # all imports by size
ts_dep_count "express" "$dir"     # transitive dep count
```

### Python Analysis (no Python runtime required)

```bash
# Project detection
py_is_project "$dir"              # has setup.py/pyproject.toml?
py_source_dir "$dir"              # detect src layout vs flat

# Import analysis (PyMiner)
py_file_imports "app/main.py"     # extract imports (multiline)
py_import_graph "$dir"            # dependency graph
py_circular_deps "$dir"           # detect circular imports
py_import_classify "requests"     # stdlib/third-party/local
py_framework_detect "$dir"        # django/flask/fastapi/pytest

# Dependency management (PyDeps)
py_parse_requirements "req.txt"   # packages + version specs
py_detect_venv "$dir"             # find venv path
py_python_version "$dir"          # required Python version
py_detect_manager "$dir"          # pip/poetry/pipenv/uv

# Code quality (PyMetrics)
py_loc "$dir"                     # lines of code
py_function_count "$dir"          # count functions
py_class_count "$dir"             # count classes
py_docstring_coverage "$dir"      # docstring coverage %
py_type_hint_coverage "$dir"      # type hint coverage %
py_summary "$dir"                 # project health overview
```

### Utilities

```bash
uuid                              # "550e8400-e29b-..."
timestamp                         # "2026-01-17 12:30:45"
timestamp_iso                     # "2026-01-17T12:30:45Z"
epoch                             # 1737123045
random_string 16                  # alphanumeric
random_range 1 100                # random int in range
format_bytes 1048576              # "1.0MB"
format_duration 3661              # "1h 1m 1s"
format_number 1234567             # "1,234,567"
format_percent 75 100             # "75%"
command_exists "git"              # returns 0/1
get_os                            # "linux"/"macos"
current_user                      # username
temp_file                         # auto-cleaned temp file
temp_dir                          # auto-cleaned temp dir
```

### Config Files

```bash
config_load "app.conf"            # load key=value config
config_get "port"                 # get value
config_get_int "port"             # get as integer
config_get_bool "debug"           # returns 0/1
config_set "host" "localhost"     # set value
config_has "database_url"         # returns 0/1
config_save "app.conf"            # persist changes
```

### Semver

```bash
semver_valid "1.2.3"              # returns 0/1
semver_bump_major "1.2.3"         # "2.0.0"
semver_bump_minor "1.2.3"         # "1.3.0"
semver_bump_patch "1.2.3"         # "1.2.4"
semver_compare "1.0.0" "2.0.0"   # -1
semver_gt "2.0.0" "1.0.0"        # returns 0
semver_latest "1.0" "2.0" "1.5"  # "2.0"
semver_sort "3.0" "1.0" "2.0"    # "1.0 2.0 3.0"
```

### ANSI Colors

```bash
echo "$(ansi_red)Error$(ansi_reset)"
echo "$(ansi_green)Success$(ansi_reset)"
echo "$(ansi_bold)Important$(ansi_reset)"
ansi_print red "Error message"
ansi_styled "bold,yellow" "Warning!"
```

### Environment

```bash
env_set "MY_VAR" "value"          # set and export
env_get "MY_VAR" "default"        # get with fallback
env_require "API_KEY" "API_KEY must be set"  # error if missing
env_load_dotenv ".env"            # load .env file
env_path_prepend "/opt/bin"       # add to PATH
env_path_has "/usr/bin"           # check PATH
env_get_int "PORT" 8080           # integer with default
env_get_bool "DEBUG"              # returns 0/1
env_detect_shell                  # bash/zsh/fish
```

### File Operations

```bash
file_exists "$path"               # returns 0/1
dir_exists "/tmp"                 # returns 0/1
read_file "$path"                 # file contents
file_head "$path" 10              # first 10 lines
file_tail "$path" 5               # last 5 lines
file_line "$path" 3               # specific line
file_lines "$path"                # line count
file_size "$path"                 # bytes
file_write "$path" "content"      # write file
file_append "$path" "more"        # append to file
file_grep "$path" "pattern"       # grep in file
```

## Design Rules

1. **NEVER read MAINFRAME source into context** - just use the functions directly
2. **ALWAYS source common.sh first** - it handles lazy-loading of all other libraries
3. **Zero dependencies** - everything is pure bash (except openssl for HTTPS)
4. **Bash 4.0+ required** - uses associative arrays and modern features
5. **Functions return 0/1** - use `if func; then` pattern for boolean checks
6. **Output via printf** - functions print results to stdout, capture with `$()`
7. **No eval** - all command dispatch uses safe word-splitting
8. **Namespace** - internal vars use `_MAINFRAME_*` prefix; don't conflict

## Common Patterns

### CLI Script Template
```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Validate arguments
[[ $# -lt 1 ]] && die 1 "Usage: $(path_base "$0") <input-file>"
validate_path "$1" "file" || die 1 "File not found: $1"

header "Processing $(path_base "$1")"
log_info "Starting at $(now_iso)"

# ... your logic here ...

success "Done in $(format_duration $SECONDS)"
```

### JSON API Response Builder
```bash
build_response() {
    local data="$1"
    json_object \
        "status=success" \
        "data:raw=$data" \
        "timestamp=$(now_iso)" \
        "request_id=$(uuid)"
}
```

### Safe File Processing
```bash
process_uploads() {
    local base_dir="/var/uploads"
    local file="$1"

    # Prevent path traversal
    validate_path_safe "$file" "$base_dir" || {
        log_error "Path traversal attempt: $file"
        return 1
    }

    # Sanitize filename
    local safe_name
    safe_name=$(sanitize_filename "$(path_base "$file")")

    # Process safely
    local content
    content=$(read_file "$file")
    file_write "$(path_join "$base_dir" "$safe_name")" "$content"
}
```

### Parallel Batch Processing
```bash
process_batch() {
    local items=("$@")
    log_info "Processing ${#items[@]} items with 4 workers"

    parallel_map_limit 4 "process_single_item" "${items[@]}"

    success "All items processed"
}
```

### Git Pre-commit Hook
```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

if git_has_staged; then
    local files
    files=$(git_files_changed)
    log_info "Checking $(array_length $files) files..."

    # Validate no secrets
    if file_grep "$files" "API_KEY="; then
        failure "Hardcoded API keys detected!"
        exit 1
    fi
fi
```

## Repository

- **Source**: https://github.com/gtwatts/mainframe
- **Install**: `git clone https://github.com/gtwatts/mainframe.git ~/.mainframe`
- **Tests**: 1800+ bats tests, zero failures
- **License**: MIT

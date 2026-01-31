# MAINFRAME - AI Coding Assistant Instructions

> **For Claude Code, OpenCode, Aider, Cursor, and other AI coding assistants**

## Quick Start

One line gives you 4,230+ pure bash functions:

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

## What You Can Do

MAINFRAME provides **120 libraries** with **4,230+ functions**. Here's what's available:

### Core Libraries

| Library | Key Functions | Use For |
|---------|--------------|---------|
| **Strings** | `trim_string`, `to_lower`, `to_upper`, `replace_all`, `split_string` | Text manipulation |
| **Arrays** | `array_unique`, `array_join`, `array_contains`, `array_sort`, `array_filter` | List operations |
| **JSON** | `json_object`, `json_array`, `json_get`, `json_merge`, `json_pretty` | JSON without jq |
| **Files** | `file_exists`, `file_size`, `file_lines`, `read_file`, `write_file` | File operations |
| **Utils** | `uuid`, `timestamp`, `random_string`, `is_valid_email`, `progress_bar` | Common tasks |
| **ANSI** | `ansi_red`, `ansi_green`, `ansi_bold`, `ansi_reset` | Colored output |

### v2.0 Libraries (NEW)

| Library | Key Functions | Use For |
|---------|--------------|---------|
| **DateTime** | `now`, `now_iso`, `date_add`, `date_diff`, `format_relative`, `is_weekend` | Date/time math |
| **HTTP** | `http_get`, `http_post`, `url_parse`, `query_string`, `http_download` | HTTP in pure bash |
| **CSV** | `csv_row`, `csv_parse_line`, `csv_get`, `csv_to_json`, `csv_headers` | CSV parsing |
| **Git** | `git_branch`, `git_is_dirty`, `git_commit_hash`, `git_changed_files` | Git workflows |
| **Crypto** | `sha256`, `md5`, `base64_encode`, `base64_decode`, `random_token` | Hashing/encoding |
| **Process** | `proc_exists`, `proc_find_by_port`, `lockfile_acquire`, `with_timeout` | Process management |
| **Path** | `path_normalize`, `path_join`, `path_is_safe`, `path_quote`, `path_relative` | Path manipulation |
| **Validation** | `validate_int`, `validate_email`, `sanitize_html`, `validate_path_safe` | Input validation & security |
| **Environment** | `env_set`, `env_get`, `env_path_prepend`, `env_load_dotenv`, `env_require` | Env var management |
| **Docker** | `docker_running`, `docker_container_running`, `docker_exec`, `compose_up` | Docker/Compose helpers |

### v3.0 Libraries (AI Agent Optimized)

| Library | Key Functions | Use For |
|---------|--------------|---------|
| **Idempotent** | `ensure_dir`, `ensure_file`, `ensure_line`, `ensure_symlink`, `ensure_command` | Re-runnable operations |
| **Atomic** | `atomic_write`, `atomic_replace`, `safe_remove`, `file_checkpoint`, `file_rollback` | Safe file operations |
| **Observe** | `trace_start`, `trace_step`, `trace_end`, `observe_command`, `stack_trace` | Structured observability |
| **Project** | `project_detect`, `project_commands`, `project_entry`, `project_deps` | Project intelligence |
| **Contract** | `contract_require`, `contract_ensure`, `contract_type_check`, `mainframe_error` | Design-by-Contract |
| **Perf** | `bash_version_at_least`, `bash_has_feature`, `perf_timer_start`, `perf_benchmark` | Feature gates & timing |
| **NetScan** | `port_check`, `host_alive`, `banner_grab`, `http_headers`, `scan_range` | Network scanning |
| **Parsers** | `parse_csv_line`, `parse_key_value`, `parse_ini`, `parse_url`, `parse_semver` | Format parsers |

### v4.0 Libraries (Language Analysis)

| Library | Key Functions | Use For |
|---------|--------------|---------|
| **TypeScript** | `ts_file_imports`, `ts_import_graph`, `ts_breaking_changes`, `ts_import_cost` | TS project analysis |
| **Python** | `py_file_imports`, `py_import_graph`, `py_parse_requirements`, `py_summary` | Python project analysis |

### v5.0 Libraries (AI Agent Infrastructure)

| Library | Key Functions | Use For |
|---------|--------------|---------|
| **Context** | `context_estimate_tokens`, `context_budget_init`, `context_truncate`, `context_read_plan` | Token estimation & budget |
| **Diff** | `diff_replace`, `diff_apply`, `diff_strings`, `diff_validate_unique`, `diff_insert_after` | Surgical file editing |
| **Cache** | `memoize`, `cas_store`, `cas_get`, `session_cache_set`, `cache_warm`, `cache_evict_lru` | Caching & memoization |

### v6.0 Libraries (CLI Experience)

| Library | Key Functions | Use For |
|---------|--------------|---------|
| **Anim** | `spinner_start`, `spinner_stop`, `spinner_while`, `progress_bar`, `typewriter`, `rainbow`, `glitch` | 20+ spinner styles, animated progress, visual effects |
| **TUI** | `tui_box`, `tui_table`, `tui_spinner`, `tui_progress`, `tui_select`, `tui_confirm` | Terminal UI components |

### v7.0 Libraries (GitHub Integration)

| Library | Key Functions | Use For |
|---------|--------------|---------|
| **GitHub** | `gh_repo_view`, `gh_pr_create`, `gh_issue_list`, `gh_context_json`, `gh_search_repos` | GitHub CLI wrapper, 100+ functions |
| **GitHub Actions** | `gha_workflow_run`, `gha_run_status`, `gha_secret_set`, `gha_yaml_workflow` | CI/CD automation, YAML generation |
| **GitHub Security** | `ghs_dependabot_alerts`, `ghs_code_alerts`, `ghs_sbom_export`, `ghs_score` | Security alerts, SBOM, compliance |

### Formatting Functions

| Function | Example | Output |
|----------|---------|--------|
| `format_bytes` | `format_bytes 1048576` | `1.0MB` |
| `format_duration` | `format_duration 3661` | `1h 1m 1s` |
| `format_percent` | `format_percent 75 100` | `75%` |
| `format_number` | `format_number 1234567` | `1,234,567` |

## Function Signatures

### JSON (most common)

```bash
# Create object - key=val for strings, key:type=val for typed
json_object "name=John" "age:number=30" "active:bool=true"
# Output: {"name":"John","age":30,"active":true}

# Create array
json_array "a" "b" "c"
# Output: ["a","b","c"]

# Get value from JSON
json_get '{"name":"John"}' "name"
# Output: John
```

### DateTime

```bash
now              # Unix timestamp: 1705312896
now_iso          # ISO format: 2024-01-15T10:30:00-0500
date_add $(now) "2d"      # Add 2 days
date_subtract $(now) "1w" # Subtract 1 week
format_relative $epoch    # "2 hours ago"
```

### HTTP (requires /dev/tcp or openssl for HTTPS)

```bash
http_get "http://api.example.com/data"
http_post "http://api.example.com/users" '{"name":"test"}'
url_parse "https://user:pass@host.com:8080/path?query=1"
# Sets: URL_SCHEME, URL_HOST, URL_PORT, URL_PATH, URL_QUERY
```

### CSV

```bash
csv_row "name" "age" "city"        # "name","age","city"
csv_parse_line '"John","30","NYC"' # Populates CSV_FIELDS array
csv_get "$line" 0                  # Get first field
csv_to_json < data.csv             # Convert to JSON array
```

### Git

```bash
git_branch              # Current branch name
git_is_dirty && echo "uncommitted changes"
git_commit_hash         # Short hash
git_changed_files       # List of modified files
git_summary             # JSON with branch, commit, dirty status
```

### Crypto

```bash
sha256 "data"           # SHA-256 hash
md5 "data"              # MD5 hash
base64_encode "hello"   # Base64 encode
random_token 32         # Secure random token
```

### Path

```bash
path_normalize "/foo//bar/../baz"   # /foo/baz
path_absolute "relative/path"        # Full absolute path
path_relative "/a/b/c" "/a"          # b/c
path_join "/foo" "bar" "baz"         # /foo/bar/baz
path_dir "/foo/bar/file.txt"         # /foo/bar
path_base "/foo/bar/file.txt"        # file.txt
path_ext "/foo/bar.tar.gz"           # gz
path_stem "/foo/bar.tar.gz"          # bar.tar
path_replace_ext "doc.txt" "md"      # doc.md
path_is_safe "/base" "$user_path"    # 0 if safe, 1 if traversal
path_quote "/path with spaces"       # Safely escaped
path_to_unix "C:\Users\foo"          # /c/Users/foo
path_expand_tilde "~/Documents"      # /home/user/Documents
```

### Validation (Council Priority - Prevents 95% of path/input errors)

```bash
# Type validation
validate_int "42" 0 100         # Valid integer in range
validate_float "3.14"           # Valid float
validate_bool "true"            # true/false/yes/no/1/0

# Format validation
validate_email "user@domain.com"         # RFC 5322 simplified
validate_url "https://example.com"       # URL with scheme check
validate_ipv4 "192.168.1.1"              # IPv4 address
validate_date "2024-01-15"               # YYYY-MM-DD format
validate_semver "1.2.3"                  # Semantic version

# Path validation (SECURITY CRITICAL)
validate_path_safe "$path" "/base"       # Prevents traversal attacks
validate_filename "report.pdf"           # No path components
validate_path_chars "/safe/path"         # Safe characters only

# Sanitization
sanitize_shell_arg "$user_input"         # Safe for shell
sanitize_filename "a/b<c>.txt"           # Returns: a_b_c_.txt
sanitize_html "<script>alert(1)"         # Returns: &lt;script&gt;alert(1)
sanitize_sql "O'Brien"                   # Returns: O''Brien

# Command safety
validate_command_safe "ls -la"           # No injection
build_safe_command "grep" "$pat" "$file" # Escaped command
```

### Environment (Council Priority #3 - Every script deals with env handling)

```bash
# Shell detection
env_detect_shell             # Returns: bash, zsh, fish, sh
env_config_file              # Returns: ~/.bashrc, ~/.zshrc, etc.

# Variable management
env_set "MY_VAR" "value"     # Set and export
env_get "MY_VAR" "default"   # Get with fallback
env_unset "MY_VAR"           # Unset variable
env_persist "VAR" "val"      # Persist to shell config

# PATH management
env_path_prepend "/opt/bin"  # Add to start of PATH
env_path_append "/opt/bin"   # Add to end of PATH
env_path_remove "/old/bin"   # Remove from PATH
env_path_has "/usr/bin"      # 0 if present, 1 if not
env_path_list                # List entries one per line
env_path_clean               # Remove duplicates and non-existent

# Dotenv support
env_load_dotenv ".env"       # Load .env file
env_save_dotenv "out.env" VAR1 VAR2  # Save vars to .env

# Validation
env_is_set "VAR"             # 0 if set (may be empty)
env_is_nonempty "VAR"        # 0 if set and non-empty
env_require "VAR" "message"  # Error if not set
env_require_all VAR1 VAR2    # Error if any missing

# Utilities
env_with "VAR=val" cmd args  # Run with temp env
env_get_int "PORT" 8080      # Get as integer with default
env_get_bool "DEBUG"         # Returns 0 for true, 1 for false
env_copy "SRC" "DEST"        # Copy variable
env_summary                  # Show shell info
```

### Docker

```bash
docker_running                          # Check if daemon is running
docker_container_running "nginx"        # Check if container is running
docker_container_status "nginx"         # Get status: running, exited, etc.
docker_exec "nginx" "cat /etc/nginx/nginx.conf"  # Execute in container
docker_logs "nginx" 100                 # Get last 100 lines of logs
docker_stats_json "nginx"               # Get CPU/memory stats as JSON
docker_port_used 8080                   # Check if port used by Docker
compose_running "web"                   # Check if compose service running
compose_exec "web" "npm run migrate"    # Execute in compose service
compose_up                              # Start compose services
```

### TypeScript Analysis (no tsc required)

```bash
# Project detection
ts_is_project "$dir"              # Check for tsconfig.json
ts_source_dir "$dir"              # Get rootDir from tsconfig

# TypeMiner - Import analysis
ts_file_imports "src/index.ts"    # Extract imports from file
ts_import_frequency "$dir"        # Most-used modules across project
ts_import_graph "$dir"            # Dependency graph (file -> module)
ts_circular_deps "$dir"           # Detect circular dependencies
ts_type_only_imports "$dir"       # Imports that should use 'import type'

# TypeDiff - API breaking changes
ts_api_extract "api.d.ts"         # Extract public API from .d.ts
ts_api_diff "v1.d.ts" "v2.d.ts"  # Show +added/-removed
ts_breaking_changes "v1" "v2"     # Detect breaking changes
ts_api_summary "v1" "v2"          # Suggest semver bump

# ImportCost - Bundle size
ts_import_cost "express" "$dir"       # Package disk size (bytes)
ts_import_cost_js "express" "$dir"    # JS-only size
ts_import_cost_file "index.ts" "$dir" # All imports by size
ts_dep_count "express" "$dir"         # Transitive dep count
```

### Python Analysis (no Python runtime required)

```bash
# Project detection
py_is_project "$dir"              # Check for setup.py/pyproject.toml/.py files
py_source_dir "$dir"              # Detect src layout vs flat

# PyMiner - Import analysis
py_file_imports "app/main.py"     # Extract imports (handles multiline)
py_import_frequency "$dir"        # Most-used modules across project
py_import_graph "$dir"            # Dependency graph (file -> module)
py_circular_deps "$dir"           # Detect circular imports
py_import_classify "requests"     # "stdlib" / "third-party" / "local"
py_framework_detect "$dir"        # Detect django/flask/fastapi/pytest

# PyDeps - Dependency management
py_parse_requirements "req.txt"   # Parse packages + version specs
py_detect_venv "$dir"             # Find virtual environment path
py_python_version "$dir"          # Infer required Python version
py_detect_manager "$dir"          # pip/poetry/pipenv/uv/conda
py_dep_count "$dir"               # Total dependency count

# PyMetrics - Code quality
py_loc "$dir"                     # Lines of code (no blanks/comments)
py_function_count "$dir"          # Count function definitions
py_class_count "$dir"             # Count class definitions
py_docstring_coverage "$dir"      # "covered/total percent%"
py_type_hint_coverage "$dir"      # "annotated/total percent%"
py_summary "$dir"                 # Quick project health overview
```

### Context Budget (AI agent token management)

```bash
# Token estimation (approximate, no external deps)
context_estimate_tokens "string"       # Estimate tokens for text
context_file_tokens "/path/to/file"    # Estimate file tokens
context_command_tokens cmd [args]      # Estimate command output tokens
context_ratio --type code              # Get chars/token ratio: "3.5"

# Budget management
context_budget_init --max-tokens 128000 --reserve 4000
context_budget_use "file.py" 2500      # Record usage
context_budget_remaining               # Tokens left
context_budget_fits 5000               # 0=fits, 1=exceeds
context_budget_summary                 # JSON summary
context_budget_reset                   # Clear state

# Truncation (preserves complete lines)
context_truncate "$text" 1000 --strategy smart  # head|tail|middle|smart
context_truncate_file "big.log" 500 --strategy tail

# Content analysis
context_analyze "$text"                # JSON: chars, lines, type, density
context_detect_type "$text"            # "code:python", "data:json", etc.
context_chunk_size --type code --model claude  # Recommended chunk size

# File batching (which files fit in budget?)
find src -name "*.py" | context_batch_files 30000 --sort size
context_read_plan 50000 src/*.ts       # JSON plan with included/excluded
```

### Diff & Patch (surgical file editing for AI agents)

```bash
# Diff generation
diff_strings "old text" "new text"           # Unified diff between strings
diff_files "old.txt" "new.txt"               # Unified diff between files
diff_preview "file.txt" "$new_content"       # Preview what would change
diff_edit_script "old" "new"                 # Line-based edit commands

# Patch application
diff_apply "file.txt" "$diff" --backup       # Apply unified diff (safe)
diff_apply "file.txt" "$diff" --dry-run      # Validate without applying
diff_apply_string "$text" "$diff"            # Apply diff in memory
diff_reverse "file.txt" "$diff"              # Undo a patch

# Search-and-replace (PRIMARY agent editing primitive)
diff_replace "file" "old_text" "new_text"    # Replace unique text (atomic)
diff_replace "file" "old" "new" --all        # Replace all occurrences
diff_replace_string "$s" "old" "new"         # In-memory replace
diff_insert_after "file" "match" "new_text"  # Insert after matching line
diff_insert_before "file" "match" "new_text" # Insert before matching line
diff_delete_lines "file" "pattern" --regex   # Delete matching lines
diff_replace_range "file" 2 5 "new content"  # Replace line range

# Conflict detection
diff_can_apply "file" "$diff"                # 0=clean, 1=conflicts
diff_conflicts "file" "$diff"                # JSON conflict details
diff_validate_unique "file" "text"           # 0=unique, 1=missing, 2=multi

# Analysis
diff_stats "$diff"                           # {"additions":N,"deletions":N,...}
diff_changed_lines "$diff"                   # Only +/- lines
diff_affected_lines "$diff"                  # Line numbers
```

### Caching & Memoization

```bash
# Memoize expensive function calls
result=$(memoize expensive_func "arg1" "arg2")
result=$(memoize --ttl 300 http_get "https://api.com/data")
result=$(memoize --invalidate-on config.json parse_config)

# Memoization management
memoize_clear "http_get"                     # Clear by function name pattern
memoize_stats --json                         # {"hits":50,"misses":10,...}

# Content-Addressable Store (deduplication)
hash=$(cas_store "large content")            # Returns SHA-256 hash
content=$(cas_get "$hash")                   # Retrieve by hash
cas_exists "$hash" && echo "found"           # Check existence
cas_gc --older-than 30                       # Garbage collect old entries

# Session cache (in-memory, zero disk I/O)
session_cache_set "key" "value"              # Store in memory
val=$(session_cache_get "key" "default")     # Retrieve with fallback
session_cache_has "key" && echo "exists"     # Check existence
session_cache_clear                          # Clear all
session_cache_stats --json                   # {"entries":5,"estimated_bytes":128}

# Cache management
cache_stats --json                           # Full statistics
cache_max_size "512MB"                       # Set max size
cache_evict_lru 256                          # Evict to stay under N MB
cache_clear --force                          # Clear all caches
cache_warm "project-type=node" "$dir"        # Preload for project type

# Dependency-aware invalidation
cache_depends_on "$key" "config.json" "env.json"
cache_check_deps "$key" && echo "still valid"
```

## Important Rules

1. **Don't read MAINFRAME source into context** - just use the functions
2. **Check CHEATSHEET.md** if you need exact signatures for obscure functions
3. **Zero dependencies** - everything is pure bash (except openssl for HTTPS)
4. **Bash 4.0+ required** - uses modern bash features

## Full Reference

For all 4,000+ function signatures: [CHEATSHEET.md](CHEATSHEET.md)

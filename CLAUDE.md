# MAINFRAME - AI Coding Assistant Instructions

> **For Claude Code, OpenCode, Aider, Cursor, and other AI coding assistants**

## Quick Start

One line gives you 550+ pure bash functions:

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

## What You Can Do

MAINFRAME provides **19 libraries** with **550+ functions**. Here's what's available:

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

## Important Rules

1. **Don't read MAINFRAME source into context** - just use the functions
2. **Check CHEATSHEET.md** if you need exact signatures for obscure functions
3. **Zero dependencies** - everything is pure bash (except openssl for HTTPS)
4. **Bash 4.0+ required** - uses modern bash features

## Full Reference

For all 580+ function signatures: [CHEATSHEET.md](CHEATSHEET.md)

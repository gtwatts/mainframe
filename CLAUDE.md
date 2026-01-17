# MAINFRAME - AI Coding Assistant Instructions

> **For Claude Code, OpenCode, Aider, Cursor, and other AI coding assistants**

## Quick Start

One line gives you 500+ pure bash functions:

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

## What You Can Do

MAINFRAME provides **17 libraries** with **500+ functions**. Here's what's available:

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

## Important Rules

1. **Don't read MAINFRAME source into context** - just use the functions
2. **Check CHEATSHEET.md** if you need exact signatures for obscure functions
3. **Zero dependencies** - everything is pure bash (except openssl for HTTPS)
4. **Bash 4.0+ required** - uses modern bash features

## Full Reference

For all 500+ function signatures: [CHEATSHEET.md](CHEATSHEET.md)

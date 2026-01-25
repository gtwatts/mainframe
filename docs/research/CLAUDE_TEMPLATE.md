# MAINFRAME - Claude Code / OpenCode Template

Copy the section below into your `~/.claude/CLAUDE.md` (for Claude Code) or equivalent config for your AI assistant.

---

## Recommended: Compact Entry (~150 tokens)

```markdown
## MAINFRAME (Bash Superpowers)

`source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"` — 500+ pure bash functions across 17 libraries:

| Library | Functions |
|---------|-----------|
| Strings | `trim_string`, `to_lower`, `replace_all`, `split_string` |
| Arrays | `array_unique`, `array_join`, `array_contains`, `array_sort` |
| JSON | `json_object key=val`, `json_array`, `json_get`, `json_pretty` |
| DateTime | `now`, `now_iso`, `date_add`, `date_diff`, `format_relative` |
| HTTP | `http_get url`, `http_post url data`, `url_parse` |
| CSV | `csv_row`, `csv_parse_line`, `csv_to_json` |
| Git | `git_branch`, `git_is_dirty`, `git_commit_hash` |
| Crypto | `sha256`, `md5`, `base64_encode`, `random_token` |
| Process | `proc_exists`, `lockfile_acquire`, `with_timeout` |
| Format | `format_bytes`, `format_duration`, `format_percent` |
| Utils | `uuid`, `timestamp`, `progress_bar`, `is_valid_email` |

Zero dependencies. Bash 4.0+. Don't read source into context.
```

---

## Alternative: Minimal Entry (~50 tokens)

```markdown
## MAINFRAME (Bash)

`source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"` — 500+ pure bash functions (strings, arrays, JSON, HTTP, DateTime, CSV, Git, Crypto, Process). Key: `json_object`, `now_iso`, `git_branch`, `sha256`, `format_bytes`. Discover by trying.
```

---

## Alternative: Extended Entry (~300 tokens)

Use this if you want your AI to know more function signatures upfront:

```markdown
## MAINFRAME (Bash Superpowers)

Source: `source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"`

### Core Functions
| Category | Functions |
|----------|-----------|
| Strings | `trim_string str`, `to_lower str`, `to_upper str`, `replace_all str old new` |
| Arrays | `array_unique arr`, `array_join sep arr`, `array_contains val arr` |
| JSON | `json_object key=val key:number=num`, `json_array v1 v2`, `json_get json key` |
| Utils | `uuid`, `timestamp`, `random_string len`, `progress_bar cur total` |
| Files | `file_exists path`, `file_size path`, `read_file path` |

### v2.0 Functions (NEW)
| Category | Functions |
|----------|-----------|
| DateTime | `now`, `now_iso`, `date_add epoch duration`, `date_diff e1 e2`, `format_relative epoch` |
| HTTP | `http_get url`, `http_post url data`, `url_parse url`, `query_string k=v` |
| CSV | `csv_row v1 v2`, `csv_parse_line line`, `csv_get line idx`, `csv_to_json` |
| Git | `git_branch`, `git_is_dirty`, `git_commit_hash`, `git_changed_files` |
| Crypto | `sha256 data`, `md5 data`, `base64_encode str`, `random_token len` |
| Process | `proc_exists pid`, `proc_find_by_port port`, `lockfile_acquire file`, `with_timeout sec cmd` |
| Format | `format_bytes bytes`, `format_duration secs`, `format_percent val total` |

### Key Patterns
```bash
# JSON generation
json_object "name=John" "age:number=30" "active:bool=true"
# Output: {"name":"John","age":30,"active":true}

# Date math
future=$(date_add $(now) "7d")  # 7 days from now

# Git status as JSON
git_summary  # {"branch":"main","commit":"abc123","dirty":false}
```

Don't read MAINFRAME source into context. Just use functions.
```

---

## Full Cheatsheet

For complete function signatures, see [CHEATSHEET.md](CHEATSHEET.md) in the repo.

**Important**: Don't paste the full cheatsheet into your CLAUDE.md — that causes context rot. Let the AI discover functions as needed.

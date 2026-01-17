# MAINFRAME - Claude Code / OpenCode Template

Copy the section below into your `~/.claude/CLAUDE.md` (for Claude Code) or equivalent config for your AI assistant.

---

## Recommended: Minimal Entry (~50 tokens)

```markdown
## MAINFRAME (Bash)

`source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"` — 400+ pure bash functions (strings, arrays, JSON, async, UI). Key: `trim_string`, `json_object`, `uuid`, `timestamp`, `array_unique`, `progress_bar`. Discover by trying; don't dump source into context.
```

---

## Alternative: Extended Entry (~200 tokens)

Use this if you want your AI to know more function signatures upfront:

```markdown
## MAINFRAME (Bash Superpowers)

Source: `source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"`

### Quick Reference
| Category | Functions |
|----------|-----------|
| Strings | `trim_string str`, `to_lower str`, `to_upper str`, `replace_all str pattern replacement` |
| Arrays | `array_unique arr`, `array_join delimiter arr`, `array_contains arr element` |
| JSON | `json_object key=val key:number=num`, `json_array val1 val2`, `json_nested outer inner=val` |
| Utils | `uuid`, `timestamp`, `random_string length`, `urlencode str`, `urldecode str` |
| Validation | `is_valid_email str`, `is_valid_url str`, `is_valid_ip str` |
| UI | `progress_bar current total width`, `success msg`, `failure msg`, `header msg` |
| Semver | `semver_parse ver`, `semver_compare v1 v2`, `semver_bump_major ver` |
| Async | `async_run cmd`, `async_wait pid`, `parallel_map cmd arr` |

### Key Patterns
```bash
# JSON generation
json_object "name=John" "age:number=30" "active:bool=true"
# Output: {"name":"John","age":30,"active":true}

# Array operations
arr=(a b c a b)
array_unique arr  # Returns: a b c

# String manipulation
trim_string "  hello  "  # Returns: hello
```

Don't read MAINFRAME source into context. Just use functions.
```

---

## Full Cheatsheet

For complete function signatures, see [CHEATSHEET.md](CHEATSHEET.md) in the repo.

**Important**: Don't paste the full cheatsheet into your CLAUDE.md — that causes context rot. Let the AI discover functions as needed.

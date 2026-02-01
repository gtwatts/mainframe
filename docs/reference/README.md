# MAINFRAME Function Reference

**Quick Reference for AI Coding Assistants**

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

## Category Index

| Category | File | Description |
|----------|------|-------------|
| [Core](core.md) | strings, arrays, utils, files | String manipulation, array operations, utilities |
| [JSON](json.md) | json.sh | JSON creation, parsing, manipulation |
| [DateTime](datetime.md) | datetime.sh | Date/time parsing, formatting, arithmetic |
| [HTTP](http.md) | http.sh, download.sh | HTTP client, downloads, URL handling |
| [CSV](csv.md) | csv.sh | CSV parsing, reading, writing |
| [Git](git.md) | git.sh | Git repository operations |
| [GitHub](github.md) | github.sh, github_actions.sh, github_security.sh | GitHub API, Actions, Security |
| [Validation](validation.md) | validation.sh, regex.sh | Input validation, sanitization, regex |
| [Process](process.md) | proc.sh, async.sh, safe.sh | Process management, async, safety |
| [Docker](docker.md) | docker.sh | Docker container/image management |
| [Crypto](crypto.md) | crypto.sh | Cryptographic functions, hashing |
| [TUI](tui.md) | anim.sh, output.sh, ansi.sh | Terminal UI, animations, output |
| [Agent](agent.md) | idempotent.sh, atomic.sh, observe.sh, diff.sh, context.sh | AI agent primitives |
| [AWM](awm.md) | awm.sh | Agent Working Memory |
| [Advanced](advanced.md) | Specialized libraries | Streaming, testing, sandbox, events |

## Quick Lookup

```bash
mainframe quickref json      # List json.sh functions
mainframe quickref validate  # List validation.sh functions
mainframe quickref --search "hash"  # Search all functions
```

## Important Rules

1. **Do not read MAINFRAME source** - use functions directly
2. **Check individual category files** for exact signatures
3. **Zero dependencies** - pure bash (openssl for HTTPS)
4. **Bash 4.0+ required**

---

*4,230+ functions | 120 libraries | Zero dependencies*

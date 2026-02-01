# MAINFRAME Function Cheatsheet

**Quick Reference for AI Coding Assistants**

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## Category Reference Files

For detailed function signatures and examples, see the focused reference files:

| Category | File | Description |
|----------|------|-------------|
| **Core** | [docs/reference/core.md](docs/reference/core.md) | Strings, arrays, utils, files, common functions |
| **JSON** | [docs/reference/json.md](docs/reference/json.md) | JSON creation, parsing, USOP output, format bridge |
| **DateTime** | [docs/reference/datetime.md](docs/reference/datetime.md) | Date/time parsing, formatting, arithmetic |
| **HTTP** | [docs/reference/http.md](docs/reference/http.md) | HTTP client, downloads, network scanning |
| **CSV** | [docs/reference/csv.md](docs/reference/csv.md) | CSV parsing, reading, writing, format parsers |
| **Git** | [docs/reference/git.md](docs/reference/git.md) | Git repository operations |
| **GitHub** | [docs/reference/github.md](docs/reference/github.md) | GitHub API, Actions, Security |
| **Validation** | [docs/reference/validation.md](docs/reference/validation.md) | Input validation, sanitization, regex |
| **Process** | [docs/reference/process.md](docs/reference/process.md) | Process management, async, retry, timeout |
| **Docker** | [docs/reference/docker.md](docs/reference/docker.md) | Docker container/image management |
| **Crypto** | [docs/reference/crypto.md](docs/reference/crypto.md) | Cryptographic functions, hashing, encoding |
| **TUI** | [docs/reference/tui.md](docs/reference/tui.md) | Terminal UI, animations, colors |
| **Agent** | [docs/reference/agent.md](docs/reference/agent.md) | AI agent primitives: idempotent, atomic, diff, context |
| **AWM** | [docs/reference/awm.md](docs/reference/awm.md) | Agent Working Memory |
| **Advanced** | [docs/reference/advanced.md](docs/reference/advanced.md) | Streaming, testing, sandbox, events, cloud |

---

## Most Common Functions

### JSON Creation
```bash
json_object name=John age:number=30 active:bool=true
# {"name":"John","age":30,"active":true}
```

### Validation
```bash
validate_email "$email" || die 1 "Invalid email"
validate_int "$port" 1 65535 || die 1 "Invalid port"
```

### Idempotent Operations
```bash
ensure_dir "/opt/myapp/logs" "0755"
ensure_file "/etc/app.conf" "key=value" "0644"
ensure_command "jq" || exit 1
```

### Surgical File Editing
```bash
diff_replace "config.ts" 'PORT = 3000' 'PORT = 8080' --backup
```

### Context Budget
```bash
context_budget_init --max-tokens 128000 --reserve 8000
context_budget_fits $(context_file_tokens "$file") && cat "$file"
```

### Caching
```bash
result=$(memoize --ttl 300 http_get "https://api.example.com/data")
```

---

## Function Lookup

```bash
mainframe quickref json      # List json.sh functions
mainframe quickref validate  # List validation.sh functions
mainframe quickref --search "hash"  # Search all functions
```

---

## Important Rules

1. **Do not read MAINFRAME source** - use functions directly
2. **Check reference files** for exact signatures
3. **Zero dependencies** - pure bash (openssl for HTTPS)
4. **Bash 4.0+ required**

---

## Reference Files

- **[docs/reference/README.md](docs/reference/README.md)** - Full category index
- **FUNCTIONS.json** - Machine-readable function index
- **DECISION_TREES.md** - "I need X" workflow guidance
- **ERRORS.json** - Error codes and recovery

---

*4,230+ functions | 120 libraries | Zero dependencies | 20-72x faster*

**YO JOE!**

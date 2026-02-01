# MAINFRAME - AI Coding Assistant Instructions

> Pure bash function library for AI agents. 4,310+ functions, 123 libraries, zero dependencies.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

## Library Overview

| Category | Libraries | Key Functions |
|----------|-----------|---------------|
| **Core** | strings, arrays, json, files, utils, ansi | `json_object`, `array_join`, `trim_string`, `uuid` |
| **Data** | datetime, http, csv, git, crypto, semver | `now_iso`, `http_get`, `csv_to_json`, `sha256` |
| **System** | proc, path, env, docker, sysinfo, compat | `proc_find_by_port`, `path_join`, `docker_exec` |
| **Validation** | validation, regex | `validate_email`, `sanitize_html`, `regex_match` |
| **AI Agent** | idempotent, atomic, observe, context, diff, cache, agent, awm, orchestrate | `ensure_dir`, `atomic_write`, `diff_replace`, `orch_agent_spawn` |
| **CLI** | anim, tui, output, stream | `spinner_start`, `progress_bar`, `output_success` |
| **GitHub** | github, github_actions, github_security | `gh_pr_create`, `gha_workflow_run`, `ghs_score` |
| **Cloud** | ext/aws, ext/gcp, ext/k8s | `aws_s3_list`, `k8s_pods` (optional, requires CLI) |

## Essential Patterns

```bash
# JSON creation
json_object "name=John" "age:number=30" "active:bool=true"

# Validation + sanitization
validate_email "$input" || die 1 "Invalid email"
safe=$(sanitize_html "$user_input")

# Idempotent operations (safe to re-run)
ensure_dir "/opt/app/logs"
ensure_file "/etc/app.conf" "key=value" "0644"

# Surgical file editing (agent primary primitive)
diff_replace "config.ts" 'PORT = 3000' 'PORT = 8080' --backup

# Token budget management
context_budget_init --max-tokens 128000 --reserve 8000
context_budget_fits $(context_file_tokens "$file") && cat "$file"

# Caching expensive operations
result=$(memoize --ttl 300 http_get "https://api.example.com/data")
```

## Function Lookup

```bash
mainframe quickref json      # List json.sh functions
mainframe quickref validate  # List validation.sh functions
mainframe quickref --search "hash"  # Search all functions
```

## Important Rules

1. **Do not read MAINFRAME source** - use functions directly
2. **Check CHEATSHEET.md** for exact signatures
3. **Zero dependencies** - pure bash (openssl for HTTPS)
4. **Bash 4.0+ required**

## Reference Files

- **CHEATSHEET.md** - All 4,310+ function signatures
- **FUNCTIONS.json** - Machine-readable function index
- **DECISION_TREES.md** - "I need X" workflow guidance
- **ERRORS.json** - Error codes and recovery
- **docs/ORCHESTRATION.md** - Multi-agent team coordination guide

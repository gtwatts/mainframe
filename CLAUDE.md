# MAINFRAME - AI Coding Assistant Instructions

> Pure bash function library for AI agents. 3,821+ functions, 152 libraries, zero dependencies.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

## Platform Support

| Platform | Integration | Status |
|----------|-------------|--------|
| **Claude Code** | `skills/claude-code/SKILL.md` | ✅ Full support |
| **Kimi Code CLI** | `skills/kimi-cli/SKILL.md` | ✅ Full support |
| **Google CLI** | `skills/google-cli/SKILL.md` | ✅ Full support |
| **OpenCode** | `skills/opencode/SKILL.md` | ✅ Full support |
| **Cursor** | `.cursorrules` / `skills/cursor/` | ✅ Full support |
| **Aider** | `skills/aider/SKILL.md` | ✅ Full support |
| **Vercel AI SDK** | `skills/vercel-ai-sdk/` | ✅ Full support |
| **Custom Agents** | `lib/uap.sh` + `lib/mcp_server.sh` | ✅ Protocol support |

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

## Agent Teams Integration

When running as a Claude Code **Agent Teams** teammate, Mainframe provides shared memory and synchronization that Agent Teams does not natively offer. Teammates DO NOT inherit conversation history, so this CLAUDE.md is their only onboarding.

### Detecting Agent Teams Mode

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
mainframe_bundle "agent_teams"

if agent_teams_active; then
    team=$(agent_teams_team_name)
    echo "Running in team: $team"
fi
```

### Shared AWM Memory (Cross-Agent State)

Agent Teams handles task assignment and mailbox messaging. Use Mainframe AWM for **persistent state** that survives across agent turns and is readable by all teammates.

**Lead agent** creates the shared session:
```bash
session_id=$(agent_teams_awm_init "deploy-task")
# Session ID is written to ~/.claude/teams/{name}/.awm_session
```

**Teammate agents** join the shared session:
```bash
agent_teams_awm_join
# Now all AWM writes (checkpoint, discovery) go to the shared session

awm_checkpoint "db_migrated" "true"
awm_discovery "API requires auth header" "high"
status=$(awm_get "db_migrated" "false")
```

### Synchronization Primitives

For coordination beyond task claims (which Agent Teams handles natively):

```bash
# Barrier: wait until 3 agents reach this point
agent_barrier "phase1_done" 3 60

# Mutual exclusion on shared resources
agent_lock "database_migration"
# ... do work ...
agent_unlock "database_migration"
```

### What to Use Where

| Need | Use |
|------|-----|
| Assign tasks to teammates | Agent Teams native (TaskCreate/TaskUpdate) |
| Send messages between agents | Agent Teams native mailbox |
| Persist state across agents | Mainframe AWM (`awm_checkpoint`, `awm_get`) |
| Wait for N agents to sync | Mainframe `agent_barrier` |
| Exclusive resource access | Mainframe `agent_lock`/`agent_unlock` |
| Record findings for all | Mainframe `awm_discovery` |

### MCP Tools (No Bash Required)

Orchestration tools are available via MCP for teammates that prefer tool calls over bash scripts. Register with `mcp_register_orchestration_tools`. Tools: `awm_init`, `awm_resume`, `awm_checkpoint`, `awm_discovery`, `awm_get`, `awm_summary`, `agent_teams_active`, `agent_teams_awm_join`, `agent_barrier`, `agent_lock`, `agent_unlock`.

## Reference Files

- **CHEATSHEET.md** - All 3,821+ function signatures
- **FUNCTIONS.json** - Machine-readable function index
- **DECISION_TREES.md** - "I need X" workflow guidance
- **ERRORS.json** - Error codes and recovery
- **docs/ORCHESTRATION.md** - Multi-agent team coordination guide

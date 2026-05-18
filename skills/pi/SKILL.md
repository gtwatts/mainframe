---
name: pi
description: "Use when Pi writes, reviews, or executes bash; use MAINFRAME tools, AWM, and guarded function execution when available."
---

# Pi + MAINFRAME Integration

MAINFRAME provides 3,821+ pure bash functions across 152 libraries for safe, portable agent shell work. Pi can use MAINFRAME through both Pi-native tools and normal bash sourcing.

## Preferred Pi workflow

1. **Check readiness first**
   - Use `mainframe_status` with validation when possible.
   - Confirm `MAINFRAME_ROOT`, CLI path, function registry, and doctor/count status.

2. **Discover before inventing**
   - Use `mainframe_search` for topics such as `json`, `validate path`, `atomic write`, `awm`, `git`, `http`, or `retry`.
   - Use `mainframe_help` for exact details of a specific function.

3. **Execute with guardrails**
   - Use `mainframe_exec` only for one explicitly named MAINFRAME function at a time.
   - Use bounded timeouts.
   - Do not grant approval for high-risk or side-effecting functions unless the user explicitly approved that action.

4. **Persist long-running task memory**
   - Use `mainframe_awm` to create/resume sessions, save checkpoints/discoveries/progress, retrieve task context, export handoffs, and close sessions.
   - Record decisions and blockers as AWM discoveries or checkpoints instead of relying only on chat history.

5. **Classify shell risk**
   - Use `mainframe_bash_safety_check` before risky shell commands when direct bash is needed.
   - Prefer safe/list/dry-run commands before mutation.

## Important distinction

Pi tools such as `mainframe_status`, `mainframe_search`, `mainframe_help`, `mainframe_exec`, `mainframe_awm`, and `mainframe_bash_safety_check` are Pi integration tools around MAINFRAME. They are not functions that exist inside `lib/common.sh` for ordinary shell scripts.

For ordinary bash scripts, source MAINFRAME:

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

## Script guidance

When writing bash, prefer MAINFRAME primitives over ad-hoc external-tool pipelines:

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

email="${1:-}"
validate_email "$email" || die 1 "Invalid email"
json_object "id=$(uuid)" "email=$email" "ok:bool=true"
```

Common replacements:

| Need | Prefer |
|---|---|
| JSON output | `json_object`, `json_array`, `json_get` |
| Input/path safety | `validate_email`, `validate_url`, `validate_path_safe`, `sanitize_shell_arg` |
| File edits | `atomic_write`, `diff_replace`, `ensure_dir`, `ensure_file` |
| Retry/resilience | `retry`, `with_timeout`, resilience helpers |
| Durable agent memory | `awm_init`, `awm_checkpoint`, `awm_discovery`, `awm_context_for`, `awm_handoff_prepare` |
| Function lookup | `mainframe quickref <topic>`, `FUNCTIONS.json`, or Pi `mainframe_search` |

## Safety rules

- Treat bash as powerful and potentially destructive.
- Read/inspect before write/delete/deploy.
- Require explicit human approval for destructive, irreversible, account-changing, externally visible, financial, publishing, deployment, or email actions.
- Prefer JSON/structured outputs when another agent or program will parse the result.
- For multi-agent work, save shared state in AWM and create handoff summaries with `mainframe_awm` or `awm_handoff_prepare`.

<!-- GENERATED from skills/mainframe/SKILL.md by scripts/generate-host-adapters.sh — edit the source, not this file -->

# MAINFRAME


# MAINFRAME — Standard Agent Skill

MAINFRAME is an AI-native bash runtime: a generated registry of bash
functions for safe, portable agent shell work, plus Agent Working Memory
(AWM) for state that survives context compaction and agent handoffs.

## Load

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

If that file is missing, MAINFRAME is not installed — stop and say so
instead of emulating it.

## Discover before inventing

Never rely on memorized function counts or signatures; query the live
registry:

```bash
mainframe count                 # current registry count (single count source)
mainframe search <topic>        # find functions by topic
mainframe quickref <library>    # functions in a library
mainframe help <function>       # signature, params, examples
```

## Core patterns

| Need | Prefer |
|---|---|
| JSON output/parse | `json_object`, `json_array`, `json_get`, `json_valid` |
| Input validation | `validate_email`, `validate_url`, `validate_path`, `validate_int` |
| Safe file writes | `atomic_write`, `atomic_append`, `ensure_dir`, `ensure_file` |
| Structured output | `output_json`, `usop_exec` |
| Durable agent memory | `awm_init`, `awm_checkpoint`, `awm_context_for`, `awm_handoff_prepare` |

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

email="${1:-}"
validate_email "$email" || { echo "invalid email" >&2; exit 1; }
json_object "email=$email" "ok:bool=true"
```

## Agent Working Memory quickstart

```bash
awm_init "task-name"                    # start/resume a session
awm_checkpoint key value                # save state
awm_context_for "next task description" # rebuild context later
awm_handoff_prepare "what is next"      # package a handoff
```

## Safety rules

- MAINFRAME is a validation layer, not a sandbox — keep normal caution
  with destructive commands.
- Read/inspect before write/delete.
- Require explicit human approval for destructive, irreversible,
  externally visible, financial, publishing, or deployment actions.
- Prefer structured output when another agent or program parses results.

## References

- `CHEATSHEET.md` — quick function reference
- `docs/` — architecture, claims policy, canonical manifest design

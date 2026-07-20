# Agent Working Memory (AWM)

Canonical persistent memory API for Mainframe agents.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

AWM gives agents a file-backed session outside the model context window. It is the recommended memory surface for agent workflows. Advanced storage, tiering, streaming, and protocol modules remain available, but the public contract is centered on `lib/awm.sh`.

## Golden Path

```bash
sid=$(awm_init "security-audit" --namespace review --model gpt-4o --backend file)
awm_resume "$sid"

awm_checkpoint "current_phase" "scanning" --importance high
awm_discovery "Auth uses JWT refresh tokens" --importance critical --tags auth,jwt
awm_log "decisions" "Prefer PostgreSQL for transactional guarantees" --importance high
awm_progress "scan" "12/40" "Scanning auth module"

ctx=$(awm_context_for "dependency-review" --tokens 2000)
handoff=$(awm_handoff_prepare "dependency-reviewer" --tokens 2000)
```

## Stable Public API

### Session lifecycle

| Function | Signature | Notes |
|---|---|---|
| `awm_init` | `awm_init [NAME] [--parent ID] [--namespace NS] [--model MODEL] [--backend BACKEND]` | Creates a session and prints the session ID |
| `awm_resume` | `awm_resume SESSION_ID` | Restores the active session |
| `awm_close` | `awm_close [--export PATH]` | Marks the session complete and optionally exports Markdown |
| `awm_namespace` | `awm_namespace NAME` | Sets namespace isolation for future sessions |

### Writes

| Function | Signature | Notes |
|---|---|---|
| `awm_checkpoint` | `awm_checkpoint KEY VALUE [--importance LEVEL] [--tags CSV] [--ttl SEC]` | Persistent key/value state |
| `awm_log` | `awm_log CATEGORY MESSAGE [--importance LEVEL] [--tags CSV]` | Structured append-only log |
| `awm_discovery` | `awm_discovery TEXT [--importance LEVEL] [--tags CSV]` | High-signal memory, never compressed away |
| `awm_progress` | `awm_progress TASK CURRENT/TOTAL [STATUS]` | Records progress history and latest state |

### Reads and retrieval

| Function | Signature | Notes |
|---|---|---|
| `awm_get` | `awm_get KEY [DEFAULT]` | Returns checkpointed value |
| `awm_recent` | `awm_recent CATEGORY [N]` | Returns recent entries as JSON array |
| `awm_summary` | `awm_summary [--tokens N]` | Compact session summary JSON |
| `awm_find` | `awm_find QUERY [--kind discovery\|checkpoint\|log\|mixed] [--limit N]` | Lexical search with optional embeddings rerank |
| `awm_context_for` | `awm_context_for TASK [--tokens N] [--format json\|prompt] [--include LIST]` | Deterministic context package |

### Handoffs and inspection

| Function | Signature | Notes |
|---|---|---|
| `awm_handoff_prepare` | `awm_handoff_prepare TARGET [--tokens N] [--format json\|prompt]` | Builds a budgeted handoff package |
| `awm_handoff_accept` | `awm_handoff_accept HANDOFF_JSON` | Initializes or updates a receiving session |
| `awm_status` | `awm_status [SESSION_ID]` | JSON health and count summary |
| `awm_doctor` | `awm_doctor [SESSION_ID]` | JSON diagnostics for layout, schema, locks, and backend |
| `awm_export` | `awm_export [PATH]` | Markdown export of the active session |
| `awm_migrate` | `awm_migrate SESSION_ID \| --all` | Upgrades older sessions to the current schema/layout |

### Session management

| Function | Signature | Notes |
|---|---|---|
| `awm_list` | `awm_list [--active\|--completed\|--json]` | Lists sessions |
| `awm_cleanup` | `awm_cleanup [--older-than DAYS]` | Deletes old completed sessions |
| `awm_check_limits` | `awm_check_limits` | Returns non-zero if size/token limits are exceeded |
| `awm_token_estimate` | `awm_token_estimate` | Estimates full-session token cost |
| `awm_estimate_read` | `awm_estimate_read OPERATION [...]` | Estimates a specific read |

## Deterministic Context Packing

`awm_context_for` packs memory in this order:

1. Critical discoveries
2. Current progress and open state
3. Relevant checkpoints for the requested task
4. Recent high-signal logs
5. `awm_find` matches
6. Final summary if budget remains

Default output is JSON. `--format prompt` renders a human/model-facing prompt block.

## Handoff Model

`awm_handoff_prepare` stores a handoff artifact in `handoffs/` and returns a package with:

- provenance: schema version, namespace, backend
- session status snapshot
- context package
- open questions
- parent and target agent metadata

`awm_handoff_accept` records the handoff in the receiving session and stores the raw package for auditability.

## On-Disk Layout

Sessions live in `~/.mainframe/awm/sessions/<session_id>/` or `~/.mainframe/awm/sessions/<namespace>/<session_id>/`.

```
<session>/
|-- manifest.json
|-- discoveries.jsonl
|-- data/
|-- logs/
|-- checkpoints/
|-- handoffs/
|-- index/
|-- journal/
```

Compatibility notes:

- `logs/discoveries.jsonl` is still maintained for older callers.
- Older sessions without `schema_version` are migrated in place by `awm_migrate`.

## Backend and Search Behavior

- Default backend is `file`.
- `--backend auto` preserves storage auto-detection for advanced setups.
- `redis` and `chromadb` are opt-in advanced backends.
- `awm_find` always works with file-backed lexical and metadata search.
- If embeddings are explicitly enabled (`MAINFRAME_AWM_FIND_EMBEDDINGS=1`) and `lib/embeddings.sh` is available, results are reranked semantically.

## CLI

The same surface is exposed in the CLI:

```bash
mainframe awm init review-run
mainframe awm checkpoint --session "$sid" current_step 3 --importance high
mainframe awm find --session "$sid" postgres --kind mixed
mainframe awm handoff prepare --session "$sid" reviewer --tokens 2000
mainframe awm doctor --session "$sid"
```

## Compatibility

`awm_v2_*` helpers remain available as compatibility wrappers during migration, but new code should use the canonical functions above.

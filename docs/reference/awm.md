# Agent Working Memory (AWM)

Canonical persistent memory API for Mainframe agents.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

AWM gives agents a file-backed session outside the model context window. It is the recommended memory surface for agent workflows. Advanced storage, tiering, streaming, and protocol modules remain available, but the public contract is centered on `lib/awm.sh`.

## Project Golden Path for Coding Agents

Use the project-scoped CLI from an agent's short-lived shell processes. The
physical project directory is the stable identity, so the agent does not need
to remember or inject a session ID between commands:

```bash
mainframe awm project ensure --project . --discover-root
mainframe work "current task" --project . --tokens 1200

mainframe awm project checkpoint --project . --discover-root current_phase implementation --importance high
mainframe awm project discovery --project . --discover-root "Confirmed the durable design constraint" --importance high
mainframe awm project progress --project . --discover-root implementation 3/5 "tests in progress"

mainframe awm project handoff prepare --project . --discover-root next-agent --tokens 1200 --format prompt
mainframe awm project summary --project . --discover-root --tokens 800
mainframe awm project close --project . --discover-root
```

`ensure` is the only project command that creates or renews a mapping. Every
later write revalidates the exact active mapping while holding the same
lifecycle lock used by close and renewal; it never initializes memory as a
side effect. `mainframe work` is the bounded read-only task entry point over an
existing mapping; the lower-level `awm project context` command remains
available for callers that need its raw context schema. `close` completes only
that currently mapped active session.
Completed sessions remain available to bounded read commands, and a later
explicit `ensure` preserves the completed session while creating a distinct
active replacement. These operations are lifecycle-linearized, not claimed
crash-atomic across every multi-file data write.

`session` and `status` are dry lookups: they report only an existing mapping
and never lock, migrate, repair, or create durable state. `status` reports
`unmapped` only when no mapping exists; an existing unsafe binding is
`invalid`. Project SIDs and the `projects` namespace are reserved from generic
session routes so stale direct mutators cannot bypass the project lifecycle.

`--discover-root` makes the managed workflow stable as agents change working
directories. MAINFRAME walks upward and selects the first opted-in boundary:
either a complete managed instruction root or a valid private project mapping.
The search cannot cross the current Git worktree. A nested Git repository is
therefore isolated, while an explicitly onboarded monorepo subproject wins over
its outer repository and survives managed-marker removal. When Git is not
installed, a validated `.git` sentinel remains the conservative traversal
ceiling; if an installed Git cannot resolve that sentinel, discovery fails
closed. Outside Git, an entirely unmarked, unmapped tree falls back to the exact
directory.
Omit `--discover-root` when `--project` must remain an intentionally exact,
distinct physical directory. If action data itself begins with a dash, place
`--` after the project options and before that data so it cannot be mistaken
for a CLI option.

Record durable decisions, high-signal discoveries, and meaningful milestones.
Do not store credentials, tokens, secrets, raw sensitive payloads, or routine
command chatter. Context and handoff budgets apply to the complete returned
artifact, not only its nested memory entries.

`AWM_MAX_FILE_SIZE` defaults to `65536` and limits each discrete durable
payload by its UTF-8 byte count. It is not an aggregate session or log quota.
MAINFRAME accepts only a positive decimal value up to 1 GiB and rejects an
oversized payload before creating its data, log, index, or journal artifact.
Context output remains governed by its requested token budget. A persisted or
accepted handoff must satisfy both that budget and `AWM_MAX_FILE_SIZE`, so its
effective limit is the smaller of the two. Importance is one of `low`,
`normal`, `high`, or `critical`. Path-derived keys, categories, task labels,
and handoff filenames are preflighted to portable bounded components before a
write begins. Durable `source_agent` attribution is limited to a non-empty,
control-free label of at most 128 bytes.

## Direct Shell-Function API

Use the lower-level function surface when one long-running shell or an agent
framework deliberately manages an explicit session ID:

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
| `awm_namespace` | `awm_namespace NAME` | Organizes future sessions under a named namespace |

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
| `awm_compress` | `awm_compress [SESSION_ID]` | Rotates oversized non-discovery logs for a durable session |

### Session management

| Function | Signature | Notes |
|---|---|---|
| `awm_list` | `awm_list [--active\|--completed\|--json]` | Lists sessions |
| `awm_cleanup` | `awm_cleanup [--older-than DAYS]` | Deletes old completed sessions |
| `awm_check_limits` | `awm_check_limits` | Returns non-zero if size/token limits are exceeded |
| `awm_token_estimate` | `awm_token_estimate` | Estimates full-session token cost |
| `awm_estimate_read` | `awm_estimate_read OPERATION [...]` | Estimates a specific read |

### Explicit advanced-module compatibility APIs

The durable session facade in `lib/awm.sh` owns `awm_compress`,
`awm_handoff_prepare`, and `awm_handoff_accept` in every loader profile. Older
streaming and protocol-v4 behaviors remain available without changing those
public contracts:

| Function | Signature | Notes |
|---|---|---|
| `awm_stream_compress` | `awm_stream_compress CONTENT [LEVEL]` | Pure standalone-content transform from the streaming module |
| `awm_protocol_handoff_prepare` | `awm_protocol_handoff_prepare TARGET [MAX_TOKENS]` | Builds the legacy protocol-v4 message package |
| `awm_protocol_handoff_accept` | `awm_protocol_handoff_accept HANDOFF_JSON` | Accepts a legacy protocol-v4 message package |

Use the unprefixed canonical APIs for new integrations. The explicit names are
provided for existing advanced-module callers and have intentionally different
data models.

## Local privacy and trust boundary

AWM creates its storage directories with mode `0700` and state, log, lock, and
handoff files with mode `0600`, even when the caller has a permissive umask.
Resume and migration tighten legacy session modes, and path components or
symbolic links that could escape `AWM_ROOT` are rejected.

Project-scoped commands store a private mapping under
`$AWM_ROOT/projects/<sha256>.json`. The mapping contains the hash of the
canonical physical project path and the session ID, never the path itself.
Physical-path aliases and a symlink to the same project therefore resume one
session. Project sessions deliberately use the local file backend even when an
ambient setting selects an external backend.

`AWM_ROOT` must be an absolute normalized path with no symbolic-link ancestor.
The default user-private root is `~/.mainframe/awm`. If a custom project-local
store is intentional, use `export AWM_ROOT="$(pwd -P)/.mainframe-awm"` and
exclude it from version control. This prevents a long-running shell from
resolving the same relative root to a different physical directory after `cd`.

Namespaces are organizational labels, not authorization boundaries. Processes
running as the same operating-system user can access sessions when they know a
session ID. Use a separate low-privilege OS account, container, or VM when the
agent itself is untrusted.

File-backed locking is intended for one host on a local filesystem. MAINFRAME
selects fixed system paths for `flock` (normally Linux) or BSD `lockf` (macOS),
so an ambient shell `PATH` cannot make Pi, the CLI, and sourced Bash choose
incompatible mechanisms. Both kernel locks are released if a holder is killed.
If neither fixed command is available, the portable `mkdir` fallback remains
exclusive but deliberately will not break a stale lock automatically. It
times out with the exact lock path so an operator can first confirm that no
writer is alive. AWM does not claim cross-host NFS locking semantics.

## Deterministic Context Packing

`awm_context_for` packs memory in this order:

1. Critical discoveries
2. Current progress and open state
3. Relevant checkpoints for the requested task
4. Recent high-signal logs
5. `awm_find` matches
6. Final summary if budget remains

Default output is JSON. `--format prompt` renders a human/model-facing prompt
block. The requested token budget applies to the complete returned document,
including provenance and budget metadata. `actual_chars`, `actual_tokens`, and
`truncated` report the exact final artifact; critical identity and provenance
are never silently discarded to make a package fit.

## Handoff Model

`awm_handoff_prepare` stores a handoff artifact in `handoffs/` and returns a package with:

- provenance: schema version, namespace, backend
- session status snapshot
- context package
- open questions
- parent and target agent metadata

The token budget applies to the entire returned and persisted handoff, not
only its nested context. If required identity, provenance, and critical
discoveries cannot fit, preparation fails without writing a partial artifact.

`awm_handoff_accept` records the handoff in the receiving session and stores the raw package for auditability.

## On-Disk Layout

Project mappings live in `~/.mainframe/awm/projects/`. Sessions live in
`~/.mainframe/awm/sessions/<session_id>/` or
`~/.mainframe/awm/sessions/<namespace>/<session_id>/`.

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

The recommended project surface is SID-free across fresh processes:

```bash
mainframe awm project ensure --project . --discover-root
mainframe awm project status --project . --discover-root
mainframe awm project checkpoint --project . --discover-root current_step 3 --importance high
mainframe awm project context --project . --discover-root "dependency review" --tokens 1200 --format prompt
mainframe awm project find --project . --discover-root postgres --kind mixed --limit 5
mainframe awm project handoff prepare --project . --discover-root reviewer --tokens 1200 --format prompt
mainframe awm project close --project . --discover-root
```

The explicit-session CLI remains available for integrations that need to
select a session directly:

```bash
mainframe awm init review-run
mainframe awm checkpoint --session "$sid" current_step 3 --importance high
mainframe awm find --session "$sid" postgres --kind mixed
mainframe awm handoff prepare --session "$sid" reviewer --tokens 2000
mainframe awm doctor --session "$sid"
```

## Compatibility

`awm_v2_*` helpers remain available as compatibility wrappers during migration, but new code should use the canonical functions above.

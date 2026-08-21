# Local Control-Plane Preview

> **Status:** source-candidate preview for MAINFRAME 10.2.0. This is not a
> published or independently certified release.

MAINFRAME now includes a small durable authority kernel behind:

```bash
mainframe control-plane --ledger /absolute/private/path.jsonl <command>
```

The preview is intentionally narrower than the Bash registry. It proves the
run, call, approval, execution, and evidence lifecycle without making the
unreviewed catalog executable.

## Durable objects

- A **run** binds an actor, canonical workspace, and policy identity.
- A **tool call** binds a run, tool ID, normalized JSON input digest, and
  declared effect.
- A **policy decision** binds the exact call and request identities to an
  immutable allow, deny, or approval-required outcome.
- An **approval** binds that exact call, tool, input digest, actor, workspace,
  policy, distinct approver, and expiry. It can be consumed once.
- **Evidence** binds an execution outcome to the corresponding call and, for
  approved work, approval identity.
- A **memory record** or **handoff record** binds non-authoritative project
  state to its Run, ToolCall, PolicyDecision, Evidence, input digest, retention,
  and trust label without persisting raw remembered content in the ledger.

The owner-private JSONL ledger is hash-chained, appended with a file lock and
`fsync`, and replayed on every command. Malformed events, a broken hash chain,
invalid transitions, and symlinked or non-private ledger paths fail closed.

## Executable source-candidate surface

The standalone low-level namespace still exposes two explicit kernel-test
tools:

| Tool | Boundary |
|---|---|
| `control_plane.trace` | Read-only; an embedding application must inject the executor. The standalone low-level CLI has no production read executor. |
| `control_plane.disposable_write` | Mutating; requires an exact one-time approval and an explicitly marked disposable workspace. |

Reviewed public facades add these routes without making the discovery catalog
executable:

| Public surface | Boundary |
|---|---|
| `mainframe invoke` | Exactly 26 read/pure stable-core contracts; each call is reserved, evaluated, executed, and evidenced under kernel-generated identities. |
| `mainframe code read` / `search` | Workspace-confined, symlink-denying reads with transient raw results and metadata-only Evidence. |
| `mainframe code edit` / `test` / `build` | Exact reviewed requests reach `awaiting_approval` and do not execute because the source candidate bundles neither a trusted approver nor an action runner. |
| `mainframe awm project` | Six mutations and six reads use fixed observer/executor adapters, project CAS, non-authoritative Memory/Handoff records, and one-consumer transient results. |
| MCP, Pi, Node.js, and Python reviewed calls | Thin translations over the atomic stable-core route; client correlation cannot substitute for kernel identity or authority. |

## Disposable-write contract

The workspace must contain a regular, non-symlink sentinel named
`.mainframe-disposable-workspace` with these exact bytes:

```text
MAINFRAME_DISPOSABLE_WORKSPACE_V1
```

The request accepts exactly `path` and `content`. The path must be relative,
must not contain empty, dot, or parent components, and must not replace the
sentinel. Every directory component is opened without following symlinks.
Parent directories must already exist. UTF-8 content is limited to 65,536
bytes. The target is replaced atomically by a same-directory `0600` file and
the file and directory are synced.

Approval consumption and the transition to `running` are persisted before the
write. A crash may therefore leave the call `running` and the approval burned;
restart refuses to retry. This favors non-repetition over guessing whether a
write committed.

## Structured CLI

The current commands are:

```text
run-create                 run-transition
call-create                call-request-approval
approval-grant             approval-consume
trace-execute              disposable-write-execute
show
```

Every response is one JSON object with `ok`, `command`, and either `result` or
`error`. Stable process classes are: `0` success, `2` usage/validation, `3`
domain denial, `4` ledger corruption or I/O denial, and `70` unexpected
internal failure.

The public atomic facades are:

```text
mainframe invoke CANONICAL_ID --input-json - --format control-plane-json-v1
mainframe code read|search|edit|test|build ...
mainframe awm project ensure|checkpoint|discovery|progress|close|handoff ...
mainframe awm project session|status|get|summary|context|find ...
```

Structured kernel responses carry `run_id`, `call_id`, `decision_id`,
`evidence_id`, `client_correlation_id`, terminal status, and a bounded receipt.
Raw values travel only through one-consumer transient channels.

## What this preview does not claim

- It does not make the 4,000-plus discovery catalog executable. Only the 26
  reviewed stable-core contracts are broker-trusted elsewhere in MAINFRAME.
- It does not route native non-shell host tools, network calls, deployments,
  arbitrary commands, or general filesystem writes through this kernel.
- It does not claim that coding edit, test, or build can execute: those routes
  deliberately stop at `awaiting_approval` until an external installed-host
  approval authority is independently verified.
- MCP offers structured output and progress for reviewed calls but does not
  claim prompt cancellation of its synchronous broker wait.
- It does not provide OS sandboxing, hostile-process isolation, signatures, or
  an external immutable ledger anchor.
- It does not prove a published package, real-host interception, clean-machine
  compatibility, or independent adoption.

See [the authoritative roadmap](CONTROL_PLANE_PLAN.md) and the generated
[`host-capabilities.json`](../config/host-capabilities.json) evidence matrix
for the remaining promotion gates.

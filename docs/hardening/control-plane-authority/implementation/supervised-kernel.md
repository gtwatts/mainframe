# Implementation Plan: Per-request kernel reservation and supervised fixed executor

## Selected Design And Constraints

The selected design makes the control-plane kernel the durable authority for reviewed stable-core execution and uses one short-lived supervisor per request. The supervisor may transport raw values only through bounded owner-private transient input/result channels. The append-only ledger and Evidence are metadata-only and may retain identities, canonical input digest/shape metadata, policy binding, outcome, exit metadata, byte counts, and output hashes—but never raw input, stdout, stderr, or a raw broker envelope.

The execution identity is at most once. A request already running or terminal must not be re-executed under the same client correlation. A terminal retry is allowed to return `result_available=false` when a consume-once raw result has been consumed or lost. This is an intentional privacy/reliability choice, not an error that authorizes replay.

The supervised process is constrained execution, not a sandbox. Host-native non-shell routes and release claims remain outside this plan unless separately intercepted and attested.

## Source Revision And Drift Check

The design review used target revision `ce0069e0e41c44ceae019e917da74c39efda587e` and source collection `eeb2a638331c545ccfc20964ed1695d36046464712456c4e9cac50c9d668953d` from `2026-08-21T00:08:24Z`. Source drift was **present**. See [context.md](../context.md) for exact per-file hashes.

Before implementation is called complete:

1. Select one candidate commit.
2. Recollect the authoritative source hashes and require a clean relevant worktree.
3. Regenerate any owned inventory from that commit.
4. Run all gates against those same bytes.
5. Record installed/live/released proof separately; do not upgrade the source claim automatically.

## Affected Components

| Component | Intended responsibility | Collected status |
|---|---|---|
| `control_plane/mainframe_control_plane/kernel.py` | Durable canonical reservation, Run/ToolCall/policy/Evidence identities, metadata-only receipt, terminal recovery | Source present; completion unproven |
| `control_plane/mainframe_control_plane/transient.py` | Bounded owner-private consume-once raw input/result | Source present; lifecycle gate open |
| `control_plane/mainframe_control_plane/executor.py` | Fixed executable/argv/environment/workspace, process group, bound, timeout, cancellation | Source present; not a sandbox; completion unproven |
| `control_plane/mainframe_control_plane/worker.py` | Per-correlation lock, state-machine continuation, no re-execution, transient result publication | Source present; recovery matrix gate open |
| `control_plane/mainframe_control_plane/cli.py` | Reservation/retry API, worker supervision, `result_available` response | Source present; contract/tests drifting |
| `bin/mainframe`, `lib/durable_invoke.sh` | Public compatibility route into the kernel; fixed hidden leaf for kernel use | Pending worktree source |
| `mcp/src/mainframe_mcp/*` | Consume kernel-owned execution/result contract and returned durable IDs | Migration pending |
| `skills/pi/extensions/mainframe.ts` | Consume the same kernel-owned contract | Migration pending |
| `config/host-capabilities.json` | Preserve route-specific evidence/claim boundaries | Present; no claim promotion authorized |
| `tests/durable_invocation.bats`, `tests/control_plane/*` | Prove public route, privacy, lifecycle, and supervisor | Mixed old/new expectations; gate open |

## Ordered Work Packages

### WP1 — Freeze closed contracts and identity bindings

- Define exact request, in-progress, completed-with-result, and completed-without-result schemas.
- Bind correlation to canonical ID, normalized input digest and metadata, actor, workspace, policy, and timeout.
- Define metadata-only `broker_receipt` fields and reject a raw `broker_envelope` in durable Evidence.
- Define `result_available=false` as terminal and non-authorizing for automatic retry.

Exit evidence: closed-schema tests; duplicate-correlation mismatch tests; deterministic ID and binding tests; serialized ledger fixtures containing no raw fields.

### WP2 — Prove durable metadata-only storage

- Audit every canonical event and Evidence creation path.
- Persist only required identity, policy, timing, outcome, byte count, digest, and exit metadata.
- Add secret-sentinel inputs and stdout/stderr, then scan raw ledger bytes and parsed snapshots for every sentinel and raw envelope field.
- Ensure diagnostics and exceptions do not append raw values.

Exit evidence: sentinel absence in the JSONL ledger across success, failure, timeout, cancellation, denial, malformed adapter output, and lost-supervisor recovery.

### WP3 — Finish transient input/result lifecycle

- Require exact absolute owner-private runtime directories, non-symlink regular files, single link, mode `0600`, bounded size, and atomic publication.
- Bind every transient artifact to correlation, call ID, and input digest.
- Consume/delete input before execution advances; consume/delete result on delivery.
- Define bounded cleanup for abandoned input/result, failure before spawn, cancel, timeout, and process death.
- Reject tampering, replacement, hard links, symlinks, ownership/mode drift, oversize data, and missing input.

Exit evidence: race-focused filesystem tests and a post-case filesystem sweep proving no raw artifacts remain outside the explicitly bounded unconsumed-result case.

### WP4 — Complete supervisor and at-most-once recovery

- Validate the fixed adapter bytes/owner/mode/link/executable status and exact hidden command grammar.
- Use the bound workspace and a closed environment; do not inherit caller overrides.
- Enforce durable timeout, output bound, cancellation identity, process group termination, and child reaping.
- Acquire a per-correlation lock and never start another executor for a running or terminal call.
- When the supervisor is lost, transition the running call to interrupted Evidence and return a terminal response; do not replay.

Exit evidence: an execution counter remains exactly one across fault injection before spawn, after spawn, during capture, after Evidence append, before result publication, after result publication, and after result consumption. Terminal retries without a result return `result_available=false`.

### WP5 — Close the public Bash/CLI route

- Route reviewed public stable-core calls through canonical reservation and supervision only.
- Keep the hidden broker grammar callable only from the fixed control-plane leaf.
- Reject unknown caller/profile/format/argument order and prevent fallthrough to broad legacy invocation.
- Preserve documented stdout/stderr/exit compatibility only when a transient result is available.
- Surface a distinct safe response when the durable outcome exists but raw result is unavailable.

Exit evidence: focused Bats tests, Bash 4.4 and current macOS Bash/zsh launch coverage, legacy-bypass negative tests, and no direct stable-core dispatch outside the fixed leaf.

### WP6 — Migrate MCP

- Replace adapter-local execution authority with the public kernel-owned route.
- Send a caller correlation ID, accept returned Run/ToolCall/decision/Evidence IDs, and label them durable only after successful kernel return.
- Preserve structured MCP results and conservative annotations without inventing protocol cancellation or progress support.
- Represent `result_available=false` as a structured terminal state; never re-invoke automatically.

Exit evidence: SDK-backed tests proving exact tool inventory, one kernel execution, durable returned IDs, no direct legacy broker path, structured unavailable-result handling, and no raw data in durable records.

### WP7 — Migrate Pi

- Replace Pi-local broker-envelope authority with the same public kernel-owned route.
- Preserve Pi's shell-only interception boundary and explicit unsupported-route behavior.
- Surface durable IDs and unavailable-result state without automatic replay.

Exit evidence: Pi extension tests showing one kernel execution, returned identity binding, cancellation/terminal handling where supported, and no direct legacy broker path.

### WP8 — Integrate candidate and release gates

- Reconcile all old durable-envelope expectations with the metadata-receipt/transient-result contract.
- Run owner parity, manifest/inventory, Python/Bash, MCP SDK, Pi, host adapter, and release tests on one clean candidate commit.
- Build/install the candidate and rerun route and privacy checks against installed bytes.
- Keep live and released evidence unverified until a separate conformance receipt and release attestation bind exact platform, route, version, and payload bytes.

Exit evidence: clean candidate SHA, complete green test matrix, installed-candidate proof, and separately validated live/release receipts where claims are promoted.

## Compatibility And Migration

The public CLI should remain the compatibility boundary. Callers can preserve their reviewed stable-core inputs and rendered output behavior while execution authority moves behind that boundary. The new result contract must distinguish durable terminal metadata from optional raw output. Old clients that cannot represent `result_available=false` should fail with an upgrade-required error rather than silently replay or fall back.

MCP and Pi should migrate after the public route stabilizes, one adapter at a time, with a direct-path negative test added before each migration is considered complete. A compatibility period may read old ledger records, but it must not authorize an old execution route.

## Tactical Protections During Migration

- Keep the hidden broker grammar exact and caller-fixed.
- Keep input, output, timeout, and process-tree bounds active on every remaining route.
- Fail closed on unknown caller, format, profile, tool contract, version, registry drift, unsafe executable, or unsafe state/runtime path.
- Do not treat helper sourcing, AWM mutation helpers, or adapter-local correlation as kernel authorization.
- Preserve explicit instruction/configured/enforced/live/released evidence levels; do not promote non-shell or release claims.
- Log only metadata appropriate for durable Evidence; redact or avoid raw command content in diagnostics.
- Do not fall back to the legacy broker when the kernel, supervisor, or transient binding fails.

## Tests And Security Validation

The minimum matrix is:

| Area | Required cases |
|---|---|
| Contract closure | Extra/missing fields, wrong types, unknown version, invalid canonical ID, non-canonical JSON |
| Identity | Duplicate correlation with same input is idempotent; different input/actor/workspace/policy fails |
| Durable privacy | Sentinel absent from ledger and Evidence for every terminal outcome and exception path |
| Transient safety | Owner/mode/link/symlink/size/binding/tamper/race/cleanup |
| At most once | Crash and retry at every state boundary; execution counter never exceeds one |
| Lost result | Terminal metadata returned, `result_available=false`, no raw fields, no replay |
| Supervisor | Fixed bytes/argv/env/cwd, bounds, timeout, cancel, process-tree cleanup, malformed output |
| Bash route | Bash 4.4/macOS compatibility, no legacy fallthrough, exact exit/render semantics |
| MCP | SDK-backed structured result, kernel-returned IDs, unavailable-result state, no direct broker |
| Pi | Kernel-returned IDs, unavailable-result state, shell-only boundary, no direct broker |
| Host claims | Unsupported non-shell and absent live/release proof remain unverified |
| Integration | Clean-checkout and installed-candidate matrices against identical committed bytes |

Source tests are not sufficient for release. Evidence must distinguish source pass, built candidate, installed candidate, live pinned host, and immutable released payload.

## Performance And Resource Benchmarks

Measure p50/p95/p99 added latency for reservation, ledger synchronization, worker spawn, broker execution, Evidence append, and result consumption. Record maximum resident memory for the foreground process and worker, transient bytes on disk, file descriptor use, and cleanup time. Test serial and bounded concurrent loads on supported macOS and Linux environments.

Initial acceptance should require no unbounded growth, no orphan worker/process/socket/file after the cleanup horizon, and total supervisory overhead comfortably below the 5-second stable-core timeout budget. Numeric regression thresholds should be fixed from a clean baseline before release, rather than invented in this proposal.

## Rollout And Rollback

1. Land closed contract/privacy tests first.
2. Enable the route in source tests with no claim promotion.
3. Validate a clean built and installed candidate.
4. Migrate MCP, then Pi, with route-specific negative tests.
5. Observe local metadata-only operational counters or explicit test receipts; do not add raw telemetry.
6. Promote only evidence levels supported by exact receipts and release attestation.

Rollback restores the last reviewed complete release and may disable stable-core invocation. It must never fall back from a failed canonical route to unsequenced legacy execution. Ledger readers must tolerate the new metadata records during rollback, or the rollback gate must stop before state mutation.

## Acceptance Criteria

- One clean committed source revision owns all reviewed stable-core authority through the kernel route.
- Every canonical request has exactly one bound reservation, Run, ToolCall, policy decision, and terminal Evidence identity, or a documented pre-call denial state.
- Raw tool input, raw stdout, raw stderr, and raw broker envelopes are absent from durable ledger/Evidence bytes under sentinel tests.
- Transient input/result artifacts are bounded, owner-private, identity-bound, consume-once, and cleaned within the defined lifecycle.
- Repeating a running or terminal correlation never starts another executor; fault-injection counters remain one.
- A terminal call with no transient result returns `result_available=false` plus durable IDs/outcome/receipt and never authorizes automatic replay.
- Fixed executable/argv/environment/workspace/deadline/output/cancellation/process-tree tests pass.
- Public Bash, MCP, and Pi routes use the same kernel-owned authority; no supported direct stable-core broker route remains.
- MCP and Pi expose durable IDs only when returned by the kernel-owned route.
- All unsupported non-shell routes and all absent live/release attestations remain explicitly unverified.
- Full clean-checkout and installed-candidate matrices pass on supported macOS and Linux/Bash versions using the exact candidate bytes.
- Release status remains unclaimed until immutable payload and host conformance attestations independently pass.

## Open Decisions

1. Set the exact cleanup horizon for an unconsumed transient result.
2. Define CLI/MCP/Pi status and messaging for terminal `result_available=false`.
3. Decide whether same-user compromise is in scope and what platform isolation is proportionate.
4. Define the authenticity and retention policy for metadata-only Evidence.
5. Set measured performance regression thresholds from a clean baseline.
6. Define the condition that would justify moving from per-request workers to a long-lived daemon.

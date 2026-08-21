# MAINFRAME Control Plane Roadmap

> **Status:** Authoritative implementation and evidence ledger
>
> **Snapshot:** 2026-08-21, MAINFRAME 10.2.0 source candidate
>
> **Supersedes for active planning:** the checklist status in the root
> `ROADMAP.md` and the dated baseline in `A_PLUS_PLUS_PLAN.md`

## Product contract

MAINFRAME is the user-owned local control plane between coding agents and the
machines they operate. It makes policy, approval, durable working memory,
reviewed tool execution, and evidence portable across agent hosts.

The acquisition wedge is simple: give an agent durable, inspectable project
memory in under ten minutes. The complete product adds one deterministic
authorization and evidence boundary for every supported tool call.

“Ultimate” means all of the following are true at the same time:

1. **Portable:** the same contract works across supported hosts without asking
   every model to reproduce security logic in prompt text.
2. **Deny by default:** no unregistered symbol, undeclared effect, raw shell
   string, unavailable pack, or unbound approval can reach execution.
3. **Resumable:** runs, tool calls, approvals, memory, cancellation, and
   handoffs have durable identities and explicit terminal states.
4. **Inspectable:** a human can answer who requested what, under which policy,
   with which exact arguments, what changed, and what evidence proves it.
5. **Evidence-backed:** “supported,” “released,” and “better” are separate
   claims, each promoted only by its own reproducible evidence.

The Bash library remains a portability and implementation asset. Function
count is not a product-readiness metric.

## Boundaries

MAINFRAME complements native host controls and operating-system isolation. It
is not an OS sandbox, a malware boundary, a model router, or a replacement for
the host agent. A hostile process with the user’s full operating-system
authority remains outside the documented boundary.

Prompt instructions are discovery aids, not an authorization mechanism.
Source availability is not release proof. Fixture-provider conformance is not
provider-inference proof. Internal evaluations are not adoption evidence.

## Non-negotiable invariants

1. All external invocation resolves a canonical ID through one broker.
2. The broker accepts typed input, never arbitrary shell text or executable
   names.
3. Every trusted contract has reviewed input, result, effect, capability,
   timeout, output-limit, platform, stability, and dependency metadata.
4. Approvals bind the normalized argument digest, canonical tool ID, call ID,
   actor, workspace, policy version, expiry, and one-time consumption.
5. Approval never expands the caller’s capability set.
6. Every state transition is append-only and replayable; terminal states are
   explicit.
7. Missing policy, metadata, adapter evidence, or host interception fails
   closed and is reported as unverified.
8. The runtime archive contains no alternate MCP or execution server.
9. Generated surfaces consume canonical contracts; adapters do not infer
   owners, call shapes, effects, or permissions.
10. Publication, package promotion, and external live studies remain explicit
    human-controlled release gates.

## Target architecture

```text
Agent host
   |
   v
Thin host adapter ---- host capability record
   |
   v
Local control API
   |-- discovery: status, search, describe
   |-- runs: create, inspect, cancel, resume
   |-- calls: request, authorize, execute, observe
   |-- approvals: request, grant, deny, expire, consume
   |-- memory: checkpoint, query, summarize, handoff
   '-- evidence: audit, receipts, conformance
   |
   v
Policy + contract authority
   |
   v
Constrained Bash execution kernel
```

### Semantic contract authority

One reviewed catalog is the input to generated runtime closures,
`FUNCTIONS.json`, `MANIFEST.json`, `INVOCATION_INDEX.json`, LSP metadata,
MCP schemas, bindings, completions, and docs.

Each trusted export declares:

- canonical ID, unique public name, owner, aliases, and compatibility window;
- closed input schema and typed structured result;
- effects: `pure`, `read`, `write`, `network`, `process`,
  `destructive`, or `secrets`;
- required capabilities and approval mode;
- timeout, output limit, concurrency class, and cancellation behavior;
- dependencies, supported platforms, pack, profile, and stability; and
- audit redaction and evidence requirements.

Discovery-only metadata may be generated heuristically. Trusted execution
metadata may not.

### Run and authority kernel

The durable domain objects are:

| Object | Required identity and behavior |
|---|---|
| Run | run ID, goal, actor, workspace, policy snapshot, parent run, lifecycle |
| Tool call | call ID, canonical tool ID, normalized input digest, effects, state |
| Approval | approval ID, exact call binding, approver, expiry, one-time use |
| Memory record | project/run scope, provenance, trust label, version, retention |
| Evidence record | transition, timestamp, subject digest, result digest, signer |
| Handoff | source run, target actor/host, scoped memory, unresolved decisions |

A tool call follows this state machine:

```text
requested -> validated -> denied
                    \-> waiting_approval -> denied|expired
                                         \-> authorized -> running
                                                          -> succeeded
                                                          -> failed
                                                          -> cancelled
                                                          -> timed_out
```

No ambient environment variable represents approval. Resume revalidates the
stored request against the current workspace, policy, contract, approval, and
artifact identities before execution.

### Adapter model

Adapters are thin translations over the local control API. The default
portable surface is intentionally small:

- `status`, `search`, and `describe`;
- `run_create`, `run_get`, `run_cancel`, and `run_resume`;
- `tool_request` and approval status;
- project-scoped memory and handoff operations; and
- audit/evidence lookup.

Large raw function catalogs are discovery data, not default tool surfaces.
MCP, CLI, Pi, Node, Python, and host-native hooks share fixtures for
authorization, structured results, cancellation, and audit parity.

### Host capability registry

“Supported host” is generated from a machine-readable record containing:

- package/runtime identity and compatible versions;
- instruction discovery and reload behavior;
- intercepted tool classes, including non-shell tools;
- approval, pause/resume, cancellation, and progress capabilities;
- memory and handoff integration;
- audit correlation fields and evidence locations;
- fail-open/fail-closed routes and known bypasses; and
- certified platform cells with artifact digests.

The public levels are:

1. **Instructions:** an adapter file exists.
2. **Configured:** activation is installed and detected.
3. **Enforced:** a native safe-allow and destructive-deny canary passed.
4. **Live:** the pinned real host loaded the route and produced correlated
   evidence.
5. **Released:** the proof belongs to the exact published artifact/platform.

## Current completion ledger

This table is deliberately stricter than a feature checklist.

| Gate | State | Current evidence | Remaining proof |
|---|---|---|---|
| Reviewed stable-core broker | Green | 26 closed, read/pure contracts; unknown names and malformed input denied | Preserve as the kernel grows |
| Canonical identity | Green | Registry, manifest, LSP, runtime, MCP, and bindings have zero owner disagreement | Resolve three binding existence gaps |
| One MCP implementation | Green in source | Both legacy shell servers retired and release-denylisted; Python MCP is runtime-bound | Rebuild and attest the final release pair |
| Legacy string execution | Amber | Compound syntax, substitutions, redirection, interpreters, and `bash -c` removed from transaction/undo/recovery path | Replace broad executable allowance with per-command contracts |
| Bootstrap interpreter | Green in source | Root launcher uses fixed `/bin/sh` then protected fixed `/bin/bash`; ambient PATH Bash regression passes | Cross-platform release CI |
| Loader identity | Green in source | Generated schema-v2 closure has 137 unique modules, 57 dependency edges, cycle/missing/unknown rejection, and parity across clean and core-to-full entry paths | Preserve exact Bash 4.4 and release-cell proof |
| Full semantic metadata | Amber | Exactly 26 collision-free contracts have reviewed ownership/semantics and trusted exposure; all other exports are discovery-only, with hazardous modules explicitly classified | Review additional contracts individually; add per-export dependencies/results without promoting heuristics |
| Run/policy/approval ledger | Green in source | Hash-chained Run/ToolCall/PolicyDecision/Approval/Evidence replay, exact one-time approval, denial, cancellation, timeout, interruption, recovery, and legacy-ledger compatibility | Obtain installed-host approval-authority evidence for coding edit/test/build |
| Stable-core kernel route | Green in source | All 26 reviewed contracts reserve generated identities, execute through the fixed supervised broker, append metadata-only Evidence, and expose a one-consumer result | Preserve the no-alternate-executor and worker-cleanup proofs |
| Coding-agent contract | Green in source | Workspace-confined read/search execute; preimage-bound edit and fixed test/build requests stop at `awaiting_approval` without a trusted approver/action runner | External coding approval-authority integration |
| Project memory contract | Green in source | Six mutations and six reads use fixed observer/executor adapters, CAS, non-authoritative Memory/Handoff records, transient raw content, recovery, and no legacy fallback | Installed-host evidence and independent privacy review remain separate claims |
| Adapter authority parity | Green for reviewed routes | MCP, Pi, Node.js, Python, CLI, and generated host instructions preserve kernel identity, reject forged correlation, and do not retry through legacy reviewed-call executors | Native non-shell interception and installed-host conformance remain unverified |
| Real-host conformance | Red | Fixture/native route machinery exists, but label-level tests are not five live hosts | Produce exact host/platform evidence |
| Immutable 10.2 distribution | Red | Reproducible archive, SBOM, checksum, rollback, and evidence machinery exist | Protected public runtime/MCP/package release |
| Comparative outcomes | Red | Protocol and offline preflight exist | Authorized preregistered live pilot and confirmatory studies |
| Independent adoption | Red | No qualifying public evidence | External projects, maintainers, repeat-use funnel |

## Dependency-ordered implementation program

### Phase 0 — Release-integrity floor

**Goal:** ensure no alternate or ambiguous execution path can ship.

Deliverables:

- retire every legacy MCP/server path from source, packages, docs, registries,
  checksums, and archives;
- execute the compatibility launcher only through reviewed fixed
  interpreters;
- remove shell-string evaluation from public agent transaction paths;
- make default and full-profile runtime identity deterministic;
- keep registry, manifest, LSP, claims, SBOM, and checksums reproducible; and
- require focused negative regressions for every retired path.

Exit evidence:

- no alternate MCP implementation in runtime archive, wheel, or sdist;
- no ambient PATH interpreter execution during bootstrap;
- no compound or substituted command side effect through legacy transaction
  APIs;
- zero owner disagreements in the covered loader/surface matrix;
- deterministic archive digest from two source trees; and
- exact-commit required CI green.

### Phase 1 — Semantic authority and generated closure

**Depends on:** Phase 0.

**Goal:** make one reviewed contract catalog define what MAINFRAME is allowed
to expose and execute.

Deliverables:

1. Introduce a versioned semantic sidecar or manifest source for effects,
   capabilities, stability, dependencies, schemas, limits, and platforms.
2. Mark simulated agent loops, Claude/tmux/Redis orchestration, broad dynamic
   execution, and unreviewed AWM mutation as experimental/discovery-only.
3. Generate tier/profile/bundle/lazy closures from the dependency graph.
4. Replace lexical `lib/*.sh` scanning in `mainframe_load_all`.
5. Generate LSP, MCP, binding, completion, and doc metadata from the same
   catalog.
6. Add schema validation, cycle detection, closure parity, and a ratchet that
   prevents new provisional trusted exports.

Exit evidence:

- every trusted export has complete reviewed semantics;
- default, selective, full, lazy, and `mainframe_load_all` expose identical
  canonical identities for the same profile;
- missing dependencies, cycles, unknown effects, and experimental trusted
  exposure fail generation;
- zero stable-core/public collisions; and
- all generated surfaces reproduce byte-identically.

### Phase 2 — Durable run, policy, approval, memory, and evidence kernel

**Depends on:** Phase 1 trusted contracts.

**Goal:** turn library-level safety primitives into transaction-bound control
plane authority.

Deliverables:

1. Add the run/call/approval/memory/evidence schemas and append-only local
   ledger.
2. Add policy evaluation over actor, workspace, contract, effects, and
   capabilities.
3. Add exact one-time approval leases and explicit denial/expiry.
4. Execute only canonical argv contracts in a scrubbed environment with
   bounded time, output, concurrency, workspace, and cancellation.
5. Make recovery, retry, undo, and resume new verified transitions rather than
   replayed shell strings.
6. Add provenance and trust labels to memory; untrusted memory never grants
   authority.
7. Expose structured results and correlation IDs through CLI and Python first.

Exit evidence:

- replay, confused-deputy, argument-swap, workspace-swap, expiry, and
  double-consumption tests all deny;
- every execution result has a correlated audit/evidence chain;
- cancellation and timeout reach terminal states without orphan processes;
- crash/restart replay produces the same state; and
- no ambient `AGENT_APPROVED`-style flag authorizes a trusted call.

### Phase 3 — Unified adapters and host conformance

**Depends on:** Phase 2 local API.

**Goal:** make every supported host a thin, testable adapter over the same
authority.

Deliverables:

1. Replace the duplicated static-skill and activation bodies with one
   versioned adapter template and `--check` drift gate.
2. Generate the host capability registry and public status matrix.
3. Route Pi, MCP, CLI, Node, Python, and native host hooks through the local
   run/call API.
4. Govern non-shell file, network, process, and write tools where the host
   provides interception; otherwise report the route as unverified.
5. Add structured output, progress, cancellation, elicitation/approval, and
   resumable task behavior to protocol adapters where supported.
6. Add safe-allow, destructive-deny, approval-resume, cancellation, memory,
   and audit-correlation conformance fixtures.

Exit evidence:

- one generated adapter source with zero drift;
- every advertised host level is derived from evidence, not prose;
- at least five clean real-host discovery and cross-session memory proofs;
- every native enforced route has safe-allow and destructive-deny canaries;
- a missing or mismatched hook can never report “enforced”; and
- install-to-cross-session retrieval is under ten minutes on supported cells.

### Phase 4 — Verified distribution and operations

**Depends on:** Phases 0–3 for the promoted scope.

**Goal:** make exact artifacts installable, recoverable, and supportable.

Deliverables:

- publish reproducible runtime and MCP artifacts as an inseparable compatible
  pair with checksums, signatures, SBOMs, and provenance;
- install by immutable version/digest and fail closed on tampering;
- exercise upgrade, rollback, removal, and clean-machine recovery;
- publish Homebrew, PyPI, and only the binding packages that pass the release
  matrix;
- certify macOS arm64/x86_64 and Linux cells independently; and
- generate compatibility and support docs from release evidence.

Exit evidence:

- two independent builds have the same digest;
- archive, package, receipt, and signature tampering all fail;
- rollback restores the previous compatible pair;
- every advertised channel is exercised by CI or a recorded release check;
- exact published commit and artifact evidence is green; and
- no source-candidate result is presented as installed-product proof.

### Phase 5 — Outcome and adoption proof

**Depends on:** a released, frozen control-plane version.

**Goal:** earn the category claim with independent evidence.

Deliverables:

- run the preregistered live pilot, fresh confirmatory study, and broader
  generalization study without reusing pairs;
- measure handoff success, recovery, policy false positives/negatives,
  latency, token/cost impact, and limitations;
- publish reproducible examples and integration RFCs;
- recruit external adapter maintainers; and
- measure the privacy-preserving funnel from install to return use.

Exit evidence:

- the confirmatory protocol’s minimum 36 independent pairs across three tasks;
- the broader claim’s minimum 80 pairs across eight tasks;
- independent public projects document successful use;
- external contributors co-maintain supported adapters; and
- outcome and adoption claims cite observable evidence, never repository
  traffic or internal demonstrations alone.

## Release promotion gates

The current gate states and advertised level are machine-readable in
`config/control-plane-claim.json` and fail-closed under
`scripts/check-control-plane-claim.py`. The ledger below supplies the human
context; it cannot promote public copy beyond that contract.

| Promotion | Required gates |
|---|---|
| Source candidate | Phase 0 local gates; honest red/amber ledger |
| Control-plane preview | Phase 1 trusted catalog + Phase 2 run kernel; no unreviewed write/destructive contracts |
| Host preview | Phase 3 evidence for named host/platform cells |
| Stable release | Phase 4 immutable distribution and rollback proof |
| Category claim | Phase 5 confirmatory and independent-adoption evidence |

## Operating method

Each work package follows:

1. **Observe:** record current behavior and exact artifact identity.
2. **Choose:** select one smallest vertical contract and its negative tests.
3. **Act:** make a bounded, reversible change without expanding authority.
4. **Verify:** prove public behavior, generated parity, and release-boundary
   behavior.
5. **Record:** update this ledger with evidence paths; checked source code alone
   never changes a red gate to green.

Implementation, commit, publication, live-provider use, and external messaging
are separate approval boundaries.

## Local verification snapshot

The 2026-08-21 source-candidate worktree produced this bounded evidence:

- the public machine claim reran its fixed local verifiers and derived seven
  green local gates with `source-candidate` as the highest eligible claim;
- the control-plane suite passed 89/89 on Python 3.9, 3.12, and 3.14 during the
  final integration run;
- the direct adapter, coding, and twelve-operation project-memory matrix passed
  31/31 outside the process-restricted test sandbox;
- the SDK-backed MCP and import suite passed 163/163 outside that sandbox;
- release inventory, generated runtime closure, and generated host-adapter
  drift checks passed;
- two independent archive builds produced the same SHA-256 digest; and
- twelve detached local receipts bind the exact source tree and are
  independently recomputed by the public claim checker rather than trusted as
  authored pass assertions.

This is local source-candidate evidence. It is not exact-commit remote CI,
published-package, installed-product, real-provider, or adoption proof.

## Immediate execution queue

The local source-candidate tranche is complete: semantic trust classification,
generated runtime dependency closure, durable policy/lifecycle records, atomic
stable-core routing, structured MCP, coding read/search plus fail-closed
approval requests, twelve project-memory operations, reviewed adapter parity,
host capability registry, and generated static/activation contracts.

The next dependency-ordered work is:

1. Integrate a real installed-host approval authority and fixed action runner
   for coding edit, test, and build, then prove approval/resume without adding
   caller authority or ambient bypasses.
2. Produce exact installed-host/platform conformance receipts and promote
   registry cells independently, including honest non-shell limitations.
3. With explicit publication authority, publish and cryptographically verify
   the immutable runtime/MCP/package set and exercise channel recovery.
4. Only on that frozen release, run a preregistered independent outcome study
   and collect adoption evidence.
5. Continue reviewing additional discovery-only contracts individually; never
   promote the full Bash catalog by heuristic metadata or function count.

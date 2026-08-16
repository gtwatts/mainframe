# Agent Impact Live Study Preregistration

> **Current state:** preregistration design only
>
> **Live provider runs:** none authorized or performed
>
> **Current evidence claim:** unchanged from Agent Impact Protocol v1:
> `fixture-runner-protocol-conformance-only`

This document fixes the intended first live study before a provider credential,
paid inference request, or real-agent session is used. It is not a result, a
runner, a live-run schema, or evidence that MAINFRAME improves an agent. The
study may start only after the remaining implementation and evidence gates are
complete, its machine-readable preregistration has been committed outside the
private run bundle, and a person gives separate explicit approval for the live
provider run and its cost.

The machine-bound directional hypothesis is deliberately narrow:

> A bounded MAINFRAME AWM handoff improves a fresh implementation session's
> hidden grader score relative to an equally bounded native/manual handoff for
> a pinned provider, model, and fixed coding-task suite.

No result from this design can establish general agent quality, general coding
productivity, machine safety, or performance on another provider, model,
MAINFRAME release, task pack, budget, or host configuration.

## Fixed study design

The experimental unit is a pair. Each pair contains one control arm and one
treatment arm created from byte-identical copies of one task repository. Each
arm has two real-agent phases:

1. an `investigate` phase that may not edit the workspace and produces a
   bounded continuation;
2. a fresh `implement` phase that receives that continuation, may edit the
   preserved workspace, and is then scored by a hidden deterministic grader.

The task prompt, repository snapshot, provider, model, model parameters,
runner, base system instructions, phase order, and planned budgets are equal
within a pair. The intervention instructions necessarily differ and must be
bound separately: the control uses the provider's native/manual bounded
handoff, while the treatment uses the pinned MAINFRAME AWM mechanism. Both
continuations cross the phase boundary through the same read-only envelope and
the same maximum size. The study must not describe the complete prompts as
byte-identical when those arm-specific mechanism instructions differ.

The provider conversation, home, configuration, cache, temporary directory,
and process state are fresh for every phase. The task workspace persists only
from investigation to implementation within one arm. No provider conversation,
AWM state, native handoff, cache, or mutable home may cross between arms or
pairs.

### Fixed task suite

The first study has exactly three tasks:

1. **Nested configuration precedence and falsy merge.** Repair layered nested
   configuration resolution without converting valid `false`, zero, or empty
   values into defaults. Hidden grading covers precedence, nested values,
   representative falsy values, and preservation of unrelated configuration.
2. **Checkpoint-after-commit idempotency.** Repair a workflow in which a
   checkpoint or retry can occur after durable commit but before completion is
   reported. Hidden grading covers the normal path, the interrupted path, and
   repeated retry without duplicate effects.
3. **Safe manifest include.** Implement or repair manifest inclusion while
   preserving intended relative includes and rejecting unsafe traversal,
   symbolic-link escape, cycles, and unsupported entries. Hidden grading covers
   valid composition and each declared rejection boundary.

Before any live run, each complete task bundle must be held out from the agent,
stored outside every agent workspace, and committed by SHA-256. The commitment
covers the task manifest, prompts, initial repository tree, hidden grader, and
grader contract. Task contents and graders may remain private until scoring is
locked, but the public preregistration must disclose the three task classes and
their bundle commitment. No task may be added, removed, rewritten, or replaced
after registration; a change requires a new study identifier and
preregistration.

### Per-phase budgets

Every arm receives the same hard ceilings:

- 900 wall-clock seconds per phase;
- 40 agent tool calls per phase; and
- 8,192 bytes of continuation context under `LC_ALL=C`.

The provider proxy or runner must enforce the wall and tool ceilings during the
phase; reporting an overage only after completion is insufficient. Timeout,
agent failure, and budget exhaustion are agent outcomes scored as zero. A
runner, proxy, isolation, ledger, grader, or integrity failure is an
infrastructure failure that invalidates the complete pair but remains reported.
There are no discretionary post-run exclusions.

### Sample-size stages

The stages are fixed in advance and must produce separate evidence artifacts:

| Stage | Paired replicates per task | Total pairs | Allowed interpretation |
|---|---:|---:|---|
| Pilot | 6 | 18 | Operational feasibility and variance estimate only |
| Confirmatory minimum | 12 | 36 | Prespecified three-task confirmatory result |
| Confirmatory preferred | 20 | 60 | Preferred three-task confirmatory result |
| Generalization | at least 10 | at least 80 across at least 8 tasks | Broader task-pack evidence, still pinned to the studied runtime |

A pair contains two arms and each arm contains two fresh agent phases. The pilot
does not become confirmatory by accumulating additional runs after inspecting
its outcome. A confirmatory run needs its own preregistration, assignment
commitment, fixed sample size, and fresh pairs. Moving from 12 to 20 pairs per
task after examining results is prohibited; the selected confirmatory size must
be registered before its first provider request.

For this first study, `minimum_valid_pairs` equals the complete planned total:
18, 36, or 60. An infrastructure failure remains published but makes that
registration non-conclusion-eligible; it cannot silently reduce the sample or
be replaced under the same preregistration.

The three-task study is intentionally narrow. A generalization claim requires
a new preregistered suite containing at least eight substantively distinct
tasks with at least ten pairs per task. Rewordings or seeded variants of one
defect do not count as distinct tasks.

## Assignment and preregistration artifact

The public machine-readable preregistration must be created and externally
committed before the first provider request. It binds:

- the study identifier, protocol version, hypothesis, claim scope, and stage;
- the task-pack commitment, disclosed task classes, replicate count, and fixed
  stopping rule;
- the primary and secondary endpoints and exact statistical algorithms;
- all agent-outcome and infrastructure-failure classifications;
- the opaque pair and arm order, plus a SHA-256 commitment to the private
  control/treatment assignment reveal;
- the provider, exact model or model snapshot, decoding parameters, provider
  adapter manifest, adapter executable digest, and client version;
- the immutable MAINFRAME release archive, checksum, installed-tree identity,
  AWM mechanism contract, shell, and host architecture;
- the isolation image or VM identity, provider-proxy policy, grader contract,
  budgets, and permitted environment-variable names; and
- the bootstrap random-number algorithm, committed seed, confidence level, and
  resample count.

The external commitment receipt and preregistration SHA-256 are evidence inputs.
A repository commit, transparency log, or equivalent immutable publication may
serve as the receipt, but a local timestamp or mutable file does not establish
that registration preceded inference. The private reveal must map exactly one
control and one treatment arm in every pair. It is disclosed only after all
registered pairs have stopped, grading is locked, and the evidence aggregate is
built.

The runner and agent cannot be blinded to the available mechanism. The grader
must receive only an opaque workspace and task identity, never the arm label.
The study is randomized and grader-blinded, not double-blinded.

The no-run machine contract is implemented by
`scripts/dev/agent-impact-preregister.py`,
`evals/agent-impact/live-study.schema.json`, and
`evals/agent-impact/preregistration.schema.json`. The CLI only prepares and
reproduces the public preregistration and private reveal; it deliberately has
no run action. Its presence does not satisfy the later runner, adapter,
containment, ledger, receipt, scoring, or provider-approval gates.

Isolation, provider-proxy, and AWM mechanism inputs are strict JSON contracts,
not descriptive blobs. Preparation rejects missing, extra, or changed required
controls and includes the parsed contract identity and controls in the public
binding. The JSON schemas validate each artifact's closed structure and fixed
stage totals; cross-item task/replicate coverage and global opaque-ID uniqueness
remain authoritative `verify` invariants because JSON Schema cannot express
those relationships. Schema validation alone is therefore insufficient.

## Endpoints and statistical analysis

Each deterministic grader reports a score from zero through its committed
maximum. The arm's normalized score is `score / maximum_score` in the closed
interval `[0,1]`. Agent outcomes that do not reach grading receive zero;
infrastructure-failed pairs are not analyzed.

The primary endpoint is the **equal-task-weighted paired normalized-score
delta**:

1. within each valid pair, subtract control normalized score from treatment
   normalized score;
2. compute the mean pair delta separately for each task; and
3. compute the arithmetic mean of the task means, giving every task equal
   weight regardless of incidental differences in valid-pair count.

The preregistered hypothesis test is a two-sided exact task-blocked sign-flip
test of that endpoint. Treatment/control signs are exchangeable only within the
registered task blocks. The implementation must use complete enumeration or a
mathematically equivalent exact dynamic program; a Monte Carlo permutation
estimate must not be labeled exact.

The 95% confidence interval is a task-stratified bootstrap: resample valid
pairs with replacement independently inside each task, recompute each task
mean, and then recompute the equal-weight mean across tasks. The
preregistration fixes the bootstrap algorithm, seed, and resample count before
inference. It must report the interval even when it crosses zero and must not
switch interval methods after results are visible.

The prespecified binary secondary endpoint is solve status. Compare discordant
paired solve outcomes with the two-sided exact McNemar test and report control
and treatment solve counts and rates. Wall time, provider-reported input and
output tokens, cost, tool calls, handoff bytes, timeouts, agent failures, and
infrastructure failures are descriptive secondary outcomes. Missing provider
usage stays `null` with a reason; it is never estimated from text length.

No single p-value or confidence interval is a general product claim. Report the
complete paired rows, invalid-pair denominator, effect estimate, interval,
test, stage, provider/model identity, task scope, and limitations together.

## Provider-neutral runner boundary

The study harness owns assignment, arm setup, isolation, transition, grading,
and evidence. Provider-specific code is confined to one pinned adapter with a
strict one-request/one-result JSON boundary. The same adapter executable and
digest serve both arms.

The request supplies an opaque pair and arm identity, phase, workspace, bound
prompt and context paths, provider/model settings, enforced budgets, artifact
and result paths, and the allowed environment names. Provider credentials are
not serialized into the request or public evidence. The adapter must not own
assignment, scoring, aggregation, MAINFRAME installation, or the control versus
treatment transition.

The result reports a closed status taxonomy, actual provider/model identity,
provider request or response identifiers when available, token usage and its
source or null reason, tool-call count, and digests for declared outputs. The
adapter does not turn provider refusal, context exhaustion, or an agent's bad
answer into an infrastructure error; it does not turn launch, transport,
malformed-response, or identity mismatch into an agent loss.

The harness owns both mechanism drivers. The control driver captures a bounded
native/manual handoff. The treatment driver exposes only the preregistered,
pinned MAINFRAME AWM capability, records its writes, and exports the bounded AWM
handoff. Both drivers place their result into the same neutral continuation
envelope. Treatment evidence must bind the MAINFRAME executable and archive,
the AWM state before and after each phase, the export operation, and the exact
exported-context digest. An arm label or a runner's assertion alone is not
proof that AWM ran.

### Offline Pi/Ollama runtime preflight

The release-contained `scripts/dev/agent-impact-runtime-preflight.py` has only
`prepare` and `verify` actions. It statically binds the declared host and Node
identity, MAINFRAME archive and installed tree, Pi certification and package
tree, Ollama installation plus ordered model/config/template blob closure,
neutral arm contract, and the same dormant adapter/request/result identities
and budgets for both arms. Both actions require the arm contract separately,
while the specification independently binds its expected digest and every
runtime/protocol identity.
It starts no child process, does not inspect the machine process table, invokes
no socket or transport API, and never runs, probes, lists, starts, or pulls Pi, Ollama, a
model, the adapter, an agent, or a provider.

That receipt can establish only that the declared local artifacts and their
closed relationships were present and matched the preflight contract. It does
not establish runtime load, model inference, adapter transport, mechanism
execution, isolation, default-deny networking, or whole-workload termination.
Declared path reads can update filesystem atime or trigger an externally
network-backed filesystem; a local/noatime filesystem boundary is therefore an
external prerequisite for an absolute no-network/no-state-mutation claim.
The current live-study and preregistration v2 contracts do not bind the receipt;
adding it to eligible evidence requires a separately versioned protocol rather
than widening the existing closed schemas.

### Credentials-free Pi AWM transition receipt

The synthetic receipt fixture is explicitly started with
`scripts/dev/run-agent-impact-awm-fixture.py`. It invokes the real Pi extension
loader and MAINFRAME AWM through
`evals/agent-impact/runners/pi-awm-transition-driver.mjs` in isolated temporary
state. The separate `prepare` and `verify` actions in
`scripts/dev/agent-impact-awm-receipt.py` are offline only and never execute Pi,
the driver, an agent, or a provider.

The private raw record, private prepared receipt, and public projection are
closed by `evals/agent-impact/awm-transition-raw.schema.json`,
`evals/agent-impact/awm-transition-receipt.schema.json`, and
`evals/agent-impact/awm-transition-public.schema.json`. Their scope is exactly
`synthetic-treatment-investigate-awm-mechanism-conformance-only`. The public
projection is HMAC-redacted and may be published only after scoring is locked
and the assignment reveal is public.

Passing this fixture proves only one treatment-arm `investigate` mechanism
transition. It does not prove provider inference, agent impact, safety or
productivity, control parity, implementation-phase isolation, network denial,
or claim-quality hostile isolation. Preregistration v2 does not currently
pre-bind the Pi runtime, Ollama model closure, either receipt protocol, or the
offline preflight receipt, so these artifacts are not eligible live-study
evidence. A future preregistration version must add those bindings. File
presence alone is not completion; the focused conformance and tamper tests must
pass.

## Live-run containment and evidence gates

A same-user process group is not sufficient for claim-quality live evidence.
Each arm must run in a fresh container, VM, or separate operating-system user
with a committed isolation profile. The profile must provide:

- a byte-identical read-only task source and a private writable workspace;
- fresh home, XDG, cache, configuration, temporary, and provider session state;
- no mount or path to the hidden grader, assignment reveal, other arms, host
  project, or prior run data;
- resource ceilings and whole-workload termination before grading; and
- default-deny network egress with the provider proxy as the only route.

The provider proxy holds credentials outside the agent environment. It must
allow only the registered provider, model, parameters, study, pair, arm, and
phase; enforce call and token policy where the provider supports it; reject an
unregistered or duplicate invocation; and emit a credential-free audit record.
Direct provider network access from the agent container invalidates the run.

The grader runs after the adapter and its descendants have stopped, outside the
agent workspace, without network access. Its executable, inputs, and output
contract are committed and digest-checked before and after every score. The
grader sees no arm mode. A grader failure or mutation is infrastructure failure,
never a zero score.

An append-only, hash-chained private ledger records every provider attempt,
including retries: study, pair, opaque arm, phase, timestamps, request and
response digests, provider identifiers, actual model, usage, status, and the
previous-record digest. Raw provider content, handoffs, logs, and credentials
remain private. Public evidence binds the ledger head and a redacted ledger
projection. There may be no unledgered provider call, silent retry, replaced
row, or reused provider response.

Evidence is conclusion-eligible only if all of these gates pass:

- the preregistration receipt predates the first ledgered provider request;
- suite, task, prompt, repository, grader, runner, proxy policy, isolation
  image, provider/model settings, MAINFRAME archive, and protocol digests match;
- every arm starts from the registered repository snapshot and equal planned
  budgets, with fresh phase state and no cross-arm leakage;
- control and treatment mechanism receipts prove the registered transition;
- every provider request and retry is present in the complete ledger;
- assignments cover every planned pair and are revealed only after scoring;
- agent outcomes and infrastructure failures follow the preregistered taxonomy,
  with each infrastructure failure invalidating its complete pair visibly;
- public rows and statistics reproduce exactly from the private records while
  excluding credentials, raw prompts, raw handoffs, logs, and absolute private
  paths; and
- an offline verifier, which never starts the adapter or contacts the provider,
  reproduces the public evidence without drift.

Failure of a gate does not erase the run. It produces a non-conclusion-eligible
run record with the failure and affected denominator visible.

## Claim scopes and non-claims

Until a live implementation, preregistration receipt, approved provider run,
and verified evidence artifact exist, the only Agent Impact evidence scope in
this repository remains:

```text
fixture-runner-protocol-conformance-only
```

If executed later, the 6-pair-per-task stage may be described only as a
`live-real-agent-paired-pilot` for the exact pinned configuration. A registered
12- or 20-pair-per-task study that passes every gate may be described as a
`live-real-agent-paired-fresh-session-handoff-study`, again limited to the exact
provider, model, MAINFRAME archive, three tasks, budgets, and isolation profile.
The broader claim requires the separate eight-task generalization design.

Even a positive confirmatory result would support only this statement:
MAINFRAME AWM changed the preregistered paired outcome for the specified
fresh-session handoff tasks under the pinned study configuration. It would not
establish that MAINFRAME:

- makes arbitrary agents better, more productive, cheaper, or safer;
- prevents malicious or erroneous host actions or acts as an OS sandbox;
- improves single-session coding without a handoff;
- generalizes to another task, provider, model, release, platform, budget, or
  integration; or
- has been independently reproduced or adopted.

## Approval boundary and implementation order

This file authorizes documentation and preregistration work only. It does not
authorize installing a provider adapter, exposing credentials, sending prompts,
incurring provider charges, starting live agents, publishing private artifacts,
or making comparative claims.

The smallest safe implementation sequence is:

1. leave the v1 harness, schemas, fixture suite, evidence scope, and verifier
   semantics intact;
2. add separately versioned live schemas and a credentials-free fake adapter
   that tests the runner, proxy, ledger, isolation, AWM-receipt, statistics, and
   tamper-rejection contracts;
3. use the offline runtime preflight to bind the declared Node, MAINFRAME, Pi,
   Ollama model, neutral-arm, and dormant-adapter artifacts without starting or
   inspecting a process;
4. build and pin one provider adapter and one isolation profile, then complete
   the separate claim-quality containment gates under a new protocol version;
5. freeze the three hidden task bundles and generate the public machine-readable
   pilot preregistration plus an external commitment receipt;
6. obtain explicit human approval for live provider use and cost;
7. run the 6-pair-per-task pilot once and publish its complete limitations;
8. choose and preregister a fresh 12- or 20-pair-per-task confirmatory study
   without reusing pilot pairs; and
9. attempt a broader claim only through the separate eight-task generalization
   study.

No live command exists in Agent Impact Protocol v1. Adding this document does
not change that boundary and does not create evidence that any of these steps
has occurred.

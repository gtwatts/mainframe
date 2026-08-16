# Agent Impact Evaluation

MAINFRAME's deterministic mechanism and native-host certificates establish
that policy hooks and AWM state paths execute. They do not establish that model
inference becomes more correct, productive, or safe. Agent Impact Protocol v1
adds the reproducible evaluation foundation while preserving that distinction.

## Current status: protocol conformance only

The checked-in `agent-impact-conformance-v1` suite contains one toy task and a
fake runner. It exercises deterministic planning, isolated phase state,
bounded handoffs, hidden grading, failure classification, paired aggregation,
and evidence verification without a provider credential.

Its only valid claim scope is:

```text
fixture-runner-protocol-conformance-only
```

The treatment win intentionally produced by the fake runner is a test vector
for scoring math. It is not evidence that MAINFRAME improves an agent.

The separately scoped
[installed-candidate AWM handoff conformance](INSTALLED_AWM_HANDOFF_CONFORMANCE.md)
closes one narrower mechanism gap without upgrading that evidence level. It
stages the exact authenticated release files in an owner-private install-shaped
layout without executing the public installer, exercises the real project AWM
CLI across four fresh login shells, and requires its bounded continuation to be
byte-equal to the native control before both deterministic implementations tie
at 100/100. Its valid claim is only
`installed-candidate-awm-handoff-mechanism-conformance-only`; no real agent,
provider, Pi, or Ollama session runs, and benefit remains unmeasured.

## Intended handoff study

The first live study should test one narrow product use case: implementation by
a fresh coding-agent session after a separate investigation session.

1. Generate one immutable task instance.
2. Give both arms byte-identical repositories, prompts, provider/model/host
   identities, and wall/tool/context budgets.
3. In phase one, ask the agent to investigate without editing and prepare its
   best bounded handoff using the mechanisms available in that arm.
4. Start phase two with a fresh home, host configuration, state, cache, and
   conversation while preserving the workspace.
5. Give the control the bounded native/manual handoff and the treatment the
   bounded MAINFRAME AWM handoff through the same neutral envelope.
6. Run a hidden deterministic grader after the runner and its process group
   have stopped.

This design measures a fresh-session handoff use case. It does not establish a
general advantage on arbitrary coding work.

## Planning and commitment

`prepare` derives pair IDs, opaque arm IDs, arm order, and an instance digest
from the selected suite, exact protocol inputs, caller seed, and replicate
count. Repeating the same command against unchanged inputs is byte-identical.

The public plan contains only opaque arms and the SHA-256 commitment of a
private assignment reveal. The reveal maps one control and one treatment per
pair and is published with the scored evidence. `run` and `verify` reject
missing, duplicate, unknown, or altered assignments, task bindings, repository
snapshots, or budgets.

Every runner request explicitly includes `arm_mode`, so the runner is not
blinded and the agent can infer which mechanisms are available. This is
committed paired assignment and scorer reproducibility, not double-blinding.

## Runner boundary

No command invokes a runner implicitly:

- `prepare` validates inputs and writes a deterministic plan/reveal.
- `run --runner PATH --fixture` is the only v1 runner-execution path.
- `verify` reads and reproduces evidence without starting the runner.

The runner receives one strict JSON request per phase. Ambient environment is
discarded; only controlled home/XDG/temp/path values and explicitly named
`--pass-env` values are supplied. Passed names are published, values are not.
Token counts remain `null` with a reason when the runner does not report them.

On macOS and Linux the runner starts in a new POSIX process group. Timeout
handling sends TERM, waits for a bounded grace period, sends KILL to the full
group, and reaps the leader before grading. The same group cleanup runs after a
normal runner exit so a successful parent cannot leave a same-group child
mutating the workspace. An 8 MiB `RLIMIT_FSIZE` ceiling
applies independently to runner stdout and stderr files. A process that creates
a new session can escape this same-user process-group boundary, so claim-quality
live runs require a container, VM, or separate operating-system user.

## Failure classification

- `timeout`, `agent_failure`, and `budget_exhausted` are agent outcomes and
  score zero.
- runner launch/failure, malformed or missing result, environment leak,
  read-only workspace mutation, grader failure, and integrity drift are
  infrastructure failures.
- an infrastructure failure invalidates its complete pair and remains visible
  in the denominator report; it is not silently converted to an agent loss.

The fixture aggregate reports valid and invalid pair counts, control/treatment
solve rates, paired success and normalized-score deltas, and wins/ties/losses.
It intentionally does not compute inferential statistics. A live protocol must
predeclare its primary endpoint, exclusion rules, task-clustered confidence
interval, and exact paired test before any provider run.

## Integrity and leakage controls

The evidence binds SHA-256 identities for:

- harness and schema inputs;
- suite, tasks, prompts, repository trees, and hidden graders;
- plan, assignment reveal, runner, normalized records, and complete raw run
  bundle; and
- every initial/final workspace, request, result, context, stdout, and stderr
  artifact represented in paired rows.

Inputs reject duplicate JSON keys, control characters, traversal, symbolic
links, special files, oversized files, task drift, budget mismatch, and reused
IDs. Outputs are created without replacement. The public artifact excludes raw
handoffs, prompts, logs, absolute private paths, and environment values.

The hidden grader is outside the copied workspace and checked before and after
execution. Under the same UID, a deliberately adversarial runner may still
search the wider filesystem. That is why local fixture conformance is not an
anti-cheating or sandbox certificate.

## What credentials-free execution proves

It can prove protocol determinism, exact input binding, paired fairness
invariants, environment scrubbing, process-group timeout handling, grading and
aggregation math, tamper rejection, and explicit non-claims.

It cannot prove real-provider inference, agent quality, productivity, token or
cost savings, MAINFRAME/AWM benefit, general machine safety, real-world
generalization, or adoption.

Likewise, executing installed MAINFRAME and AWM in the separate handoff canary
proves mechanism transport and deterministic parity only. Its certifier-scoped
zero counters describe sessions and API calls the certifier did not start or
issue; they are not machine-wide process observation or operating-system
network containment.

The separately versioned [live-study preregistration](AGENT_IMPACT_LIVE_STUDY.md)
fixes the proposed first real-agent design, evidence gates, and approval
boundary. It remains a preregistration design only: no live provider run is
authorized or claimed.

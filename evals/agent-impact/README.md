# Agent Impact Protocol v1

This directory contains a credentials-free conformance foundation for a future
paired evaluation of coding-agent handoffs. The checked-in suite uses a
deterministic fake runner and one toy repository. It tests the protocol, not an
agent, provider, MAINFRAME runtime, or AWM mechanism.

The protocol deliberately has no default run action. `prepare` and `verify`
never start a runner. Only the explicit `run --runner ... --fixture` command
does so, and v1 evidence is fixed to
`fixture-runner-protocol-conformance-only`.

## Local conformance run

Use outputs outside the repository. Plans are public; assignment reveals and
raw runs are private inputs to verification. The public protocol tree, harness,
and fake runner ship in the release archive, so the same commands work from an
extracted release without repository test fixtures.

```bash
run_root=$(mktemp -d "${TMPDIR:-/tmp}/mainframe-impact.XXXXXX")

python3 scripts/dev/agent-impact.py prepare \
  --seed local-conformance \
  --output "$run_root/plan.json" \
  --assignments-output "$run_root/assignments.json"

python3 scripts/dev/agent-impact.py run --fixture \
  --plan "$run_root/plan.json" \
  --assignments "$run_root/assignments.json" \
  --runner evals/agent-impact/runners/fake-runner.py \
  --output-dir "$run_root/run" \
  --evidence "$run_root/evidence.json"

python3 scripts/dev/agent-impact.py verify \
  --plan "$run_root/plan.json" \
  --assignments "$run_root/assignments.json" \
  --runner evals/agent-impact/runners/fake-runner.py \
  --output-dir "$run_root/run" \
  --evidence "$run_root/evidence.json"
```

Do not commit `assignments.json`, the private run directory, provider logs, or
credentials. The repository ignores `evals/agent-impact/runs/` and
`evals/agent-impact/private/` as a final guard, but temporary external paths are
preferred.

## Installed-candidate AWM handoff conformance

The separate `scripts/dev/certify-installed-awm-handoff.py` can exercise the
real project-scoped AWM CLI after safely staging the exact authenticated files
from a release archive in an owner-private install-shaped layout, without
executing the public installer or starting Pi, Ollama, an agent, or a provider.
One deterministic investigation fact passes through four distinct fresh login
shells (`ensure`, `checkpoint`, `discovery`, and `handoff`) and into the same
bounded neutral continuation used by the native control. The deterministic
implementation and grader must produce an exact 100/100 tie and equal final
workspace trees.

Its closed public claim scope is
`installed-candidate-awm-handoff-mechanism-conformance-only`. The public
certificate is path-free; its candidate payload status is
`authenticated-release-files-private-staging`; the private reproduction record contains raw
continuations, AWM state, process output, and absolute paths and must not be
published. This is staged candidate-mechanism parity, not public-installer or
agent-impact evidence. See
[Installed-candidate AWM handoff conformance](../../docs/INSTALLED_AWM_HANDOFF_CONFORMANCE.md)
for the exact commands, six-cell platform/shell matrix, and limitations.

## Live v2 preregistration (no execution)

`scripts/dev/agent-impact-preregister.py` turns a fully pinned live-study input
into a public preregistration and a private assignment reveal. It has only
`prepare` and `verify` actions: it cannot start the declared runner or adapter,
contact a provider, grade a task, or produce comparative evidence.

The input is validated against the fixed three-task pilot/confirmatory contract
in `live-study.schema.json`. It must bind the exact task corpus, runner and
provider adapter, MAINFRAME archive and expected installed tree, AWM mechanism,
isolation and provider-proxy policies, provider/model settings, shell and host,
budgets, exclusions, stopping rule, and statistical design. This schema is not
a substitute for the still-unimplemented live runner, ledger, transition
receipts, claim-quality containment, or external preregistration receipt. The
separate offline runtime preflight below does not close any of those gates.

The three policy inputs are closed JSON contracts with fixed kinds and required
controls; arbitrary policy prose is rejected. Pilot and confirmatory
registrations require all 18, 36, or 60 planned pairs to remain valid before a
result is conclusion-eligible. Always run `verify`: schema validation alone
cannot prove cross-item schedule coverage or opaque-ID uniqueness.

Create the secret assignment seed outside the repository with mode `0600`, and
write both outputs to new paths:

```bash
private_root=$(mktemp -d "${TMPDIR:-/tmp}/mainframe-live-prereg.XXXXXX")
umask 077
openssl rand 32 > "$private_root/assignment.seed"

python3 scripts/dev/agent-impact-preregister.py prepare \
  --study /absolute/path/to/study.json \
  --seed-file "$private_root/assignment.seed" \
  --output "$private_root/preregistration.json" \
  --assignments-output "$private_root/private-assignments.json"

python3 scripts/dev/agent-impact-preregister.py verify \
  --study /absolute/path/to/study.json \
  --seed-file "$private_root/assignment.seed" \
  --preregistration "$private_root/preregistration.json" \
  --assignments "$private_root/private-assignments.json"
```

Publish only the public preregistration after reviewing it and obtaining an
external immutable commitment receipt. Keep the seed and assignment reveal
private until all registered scoring is locked. Successful preparation or
verification still reports zero live sessions and supports no agent-quality,
productivity, safety, or MAINFRAME-benefit claim.

## Offline Pi/Ollama runtime preflight (no execution)

`scripts/dev/agent-impact-runtime-preflight.py` prepares and verifies one
closed receipt for the declared host and Node identity, MAINFRAME archive and
installed tree, Pi certification and package tree, Ollama installation and
ordered model-blob closure, separately supplied neutral arm contract, and
dormant adapter/request/result/protocol files. It has exactly `prepare` and
`verify` actions. Both actions read and hash declared paths only: they
start no child process, do not inspect the machine process table, invoke no
socket or transport API, and never run, probe, list, start, or pull Pi, Ollama, the
adapter, a model, an agent, or a provider.

Write the receipt outside the repository and invoke the tool with isolated
standard-library Python:

```bash
python3 -I -S -B scripts/dev/agent-impact-runtime-preflight.py prepare \
  --spec /absolute/path/to/spec.json \
  --arm-contract /absolute/path/to/arm.json \
  --output /absolute/path/to/receipt.json

python3 -I -S -B scripts/dev/agent-impact-runtime-preflight.py verify \
  --spec /absolute/path/to/spec.json \
  --arm-contract /absolute/path/to/arm.json \
  --receipt /absolute/path/to/receipt.json
```

The closed contracts are `pi-ollama-preflight-spec.schema.json`,
`pi-ollama-preflight-receipt.schema.json`,
`pi-ollama-arm-contract.schema.json`,
`pi-ollama-adapter-request.schema.json`, and
`pi-ollama-adapter-result.schema.json`. The dormant
`runners/pi-ollama-adapter.py` is shipped so its exact bytes and manifest can be
bound; the preflight never imports or executes it.

A passing receipt is static compatibility and artifact-closure evidence only.
It binds observed bytes back to independently supplied expected identities;
it is not an inventory that creates its own expectations.
It does not prove that Pi or Ollama can start, that a model can answer, that the
adapter can transport a request, that isolation or network denial works, or
that either arm executes the intended mechanism. Reads can still update atime
or cause an external network-backed filesystem to hydrate data, so absolute
offline/no-mutation containment remains an external prerequisite. Live-study preregistration v2
does not bind this receipt, so it is not eligible live-study evidence and does
not authorize a provider run.

## Credentials-free Pi AWM transition receipt

The explicit synthetic fixture entry point is
`scripts/dev/run-agent-impact-awm-fixture.py`. It invokes the real Pi extension
loader and MAINFRAME AWM through
`evals/agent-impact/runners/pi-awm-transition-driver.mjs`, using isolated
temporary state. In contrast, `prepare` and `verify` in
`scripts/dev/agent-impact-awm-receipt.py` are offline transformations: they
never execute Pi, the driver, an agent, or a provider.

The closed contracts are `awm-transition-raw.schema.json`,
`awm-transition-receipt.schema.json`, and
`awm-transition-public.schema.json`. Their evidence scope is exactly
`synthetic-treatment-investigate-awm-mechanism-conformance-only`. The public
projection is HMAC-redacted and is suitable only after scoring is locked and
the assignment is revealed; private state, workspace, requests, responses,
handoffs, paths, and credentials do not enter that projection.

This fixture proves only one treatment-arm `investigate` mechanism transition.
It does not prove provider inference, agent impact, safety or productivity,
control parity, implementation-phase isolation, network denial, or
claim-quality hostile isolation. Live-study preregistration v2 also does not
pre-bind the Pi runtime or this receipt protocol, so these artifacts are not
eligible live-study evidence. A future preregistration version must add those
bindings before a live run. The receipt implementation is not complete merely
because these files exist; its focused conformance and tamper tests must pass.

## Task contract

A v1 task contains exactly two phases:

1. `investigate` is read-only and emits one bounded handoff.
2. `implement` receives that handoff through a fresh home/config/cache/state
   environment and may edit the preserved repository.

Every pair receives the same repository tree digest, prompts, wall/tool/context
budgets, grader, and runner. The private assignment reveal maps two opaque arm
IDs to one `native-bounded-handoff` control and one
`mainframe-awm-handoff` treatment. The public plan commits to the exact reveal
before execution.

The grader is never copied into the agent workspace and is digest-checked
before and after scoring. This is path separation, not adversarial isolation:
the harness and runner use the same operating-system user in local conformance
runs.

## Evidence boundary

Fixture evidence may report scores and paired deltas only to prove aggregation
math. Those numbers are manufactured by the fake runner. Every artifact states:

- real-provider inference: not run;
- live agent sessions: zero;
- agent quality, productivity, and comparative performance: not measured; and
- MAINFRAME and AWM mechanisms: not exercised.

Real-agent measurement requires a separately reviewed live-run schema, pinned
host/provider adapter, immutable MAINFRAME archive, held-out task pack,
provider-reported usage, and container or separate-user isolation. V1 refuses
to label its fixture output as that evidence.

See [Agent Impact Evaluation](../../docs/AGENT_IMPACT_EVALUATION.md) for the
v1 study design and limitations. The proposed
[live-study preregistration](../../docs/AGENT_IMPACT_LIVE_STUDY.md) is a
separately versioned, not-yet-executed design and does not change this fixture
protocol's evidence scope.

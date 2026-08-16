# Local paired-development smoke v1

This is a credentials-free vertical slice for a future Pi plus Ollama coding
agent evaluation. Its only execution path uses the checked-in deterministic
fake transport. It does not start Pi, Ollama, a provider, a real agent, or a
network request, and it does not modify `~/.pi/agent`.

The fixed study contains one nested-configuration coding task and exactly three
paired replicates. Every opaque arm runs an investigation and implementation in
fresh HOME, XDG, temporary, and process state. The adapter request and
environment contain no control/treatment label. The harness applies the
committed control or synthetic AWM-shaped transition outside the adapter and
passes only a bounded neutral continuation into implementation.

Both arms intentionally receive identical fake-agent behavior and achieve the
same hidden-grader result. The required conformance vector is three ties, zero
paired delta, exact sign-flip `8/8` with two-sided p-value `1`, bootstrap
interval `[0,0]`, and exact McNemar p-value `1`. A fake treatment win is a
protocol failure, not evidence.

## Run the fake conformance slice

Use a new private directory outside the repository:

```bash
run_root=$(mktemp -d "${TMPDIR:-/tmp}/mainframe-local-impact.XXXXXX")
chmod 700 "$run_root"

python3 scripts/dev/agent-impact-local.py prepare \
  --seed local-conformance \
  --output "$run_root/plan.json" \
  --assignments-output "$run_root/assignments.json"

python3 scripts/dev/agent-impact-local.py run --fake-transport \
  --plan "$run_root/plan.json" \
  --assignments "$run_root/assignments.json" \
  --output-dir "$run_root/run" \
  --evidence "$run_root/evidence.json"

python3 scripts/dev/agent-impact-local.py verify \
  --plan "$run_root/plan.json" \
  --assignments "$run_root/assignments.json" \
  --output-dir "$run_root/run" \
  --evidence "$run_root/evidence.json"
```

`prepare` and `verify` start nothing. `run` requires the explicit
`--fake-transport` flag. No real adapter option exists in this protocol.

## Evidence boundary

The only claim scope is:

```text
local-development-smoke-protocol-conformance-only
```

The artifact records zero live agent, Pi, provider, Ollama, and network
sessions; real MAINFRAME and AWM are not exercised. The treatment receipt is an
AWM-shaped synthetic fixture, not an AWM receipt. Assignment omission is proven
only at the adapter request/environment boundary: same-UID execution is not
hostile blinding, OS isolation, a network sandbox, or adversarial grader
secrecy. The private reveal is available to the harness and is embedded in the
local evidence only after all fake scoring completes; external publication has
not been performed.

A future Pi plus Ollama experiment must use a new versioned protocol, bind the
exact Pi/Ollama executables and model, add real isolation and network controls,
obtain explicit human approval, and run a held-out study. Editing this
artifact's fields cannot upgrade it into agent-impact evidence.

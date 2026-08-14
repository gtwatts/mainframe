# Claims and benchmarks

MAINFRAME's public claims should be easy to reproduce from the repository. This document defines the evidence policy for the README, release notes, and project website.

## Evidence levels

| Level | Meaning | Acceptable use |
|---|---|---|
| Generated | Produced from current source by a checked-in script | Version, registry counts, file inventory |
| Reproduced | Command and environment are documented and the check passes in CI or a recorded run | Tests, clean installation, compatibility |
| Measured | Raw inputs, method, environment, and limitations are published | Performance and token comparisons |
| Observed | A real user or project provides a linkable case study | Adoption and outcome claims |
| Proposed | Design target without completed evidence | Roadmap only |

Proposed targets must not be presented as shipped performance. Internal reviews and historical research are not independent validation.

## Version and function inventory

`VERSION` is the product version source. `FUNCTIONS.json` is the generated registry source.

```bash
cat VERSION
jq '.stats | {unique_functions, registrations, total_libraries}' FUNCTIONS.json
mainframe count
```

Count naming: `unique_functions` (distinct registry names) is the canonical product-state count; `registrations` counts every library registration of a name (one name may be registered by several libraries); the legacy `total_functions` field equals `registrations`. The runtime loaded count is profile-dependent and is reported only as a diagnostic by `mainframe count`/`doctor`. Public copy should either name the source or use a stable rounded description.

## Tests

The supported Bash suite is:

```bash
make test-deps
./tests/run_bats_suite.sh --scope all
```

GitHub Actions runs the relevant matrix on Linux and macOS. A test-count claim is valid only when generated from the exact suite and commit being described. A passing focused suite must not be described as a passing whole product.

Language bindings, MCP, and LSP should report their own validation status. Their tests do not inherit the Bash suite's status automatically.

## Offline agent mechanism evidence

The [offline agent mechanism protocol](OFFLINE_AGENT_MECHANISM_EVIDENCE.md)
reproduces the policy classifier's output for a checked-in synthetic fixture
corpus and binds the raw rows to the exact evaluated source or checked release
archive. This is generated/reproduced mechanism evidence, not measured agent
impact: real-provider inference is not run, and agent quality and productivity
are not measured.

The classifier's `low` label means only that no configured lexical rule matched
after its bounded normalization. Public copy must not translate `low` into
"safe," semantic authorization, or proof about scripts, interpreters, aliases,
or downstream effects that the classifier did not inspect.

The credentials-free [Agent Impact Protocol](AGENT_IMPACT_EVALUATION.md) adds
paired planning, fixture-runner orchestration, hidden scoring, and tamper-bound
evidence. Its checked-in conformance result is also mechanism evidence only:
the fake runner is not an agent, MAINFRAME/AWM are not exercised, and its score
delta must not be presented as product impact.

The Pi/Ollama runtime preflight is Generated/Reproduced static-readiness
evidence only. Its prepare/verify receipt may report that independently
declared Node, MAINFRAME archive/tree, Pi certification/package-tree, Ollama
installation/model-blob, separately supplied arm-contract, and
dormant-adapter/protocol identities form one verified closure. The preflight
starts no child process after preflight entry, does not inspect the machine
process table, invokes no socket or transport API, and does not
execute Pi, Ollama, a model, an adapter, an agent, or a provider. It is not a
containment certificate, runtime-activation result, model-response test, or
agent-impact measurement. The current live-study preregistration v2 does not
bind that receipt, so public copy must not present it as eligible live-study
evidence or authorization for a provider run. Declared path reads may update
atime or hydrate through an externally network-backed filesystem, so they are
not absolute no-network/no-state-mutation evidence.

The
[installed-candidate AWM handoff conformance](INSTALLED_AWM_HANDOFF_CONFORMANCE.md)
is also Generated/Reproduced mechanism evidence only. It can report that one
exact installed archive exercised the real project-scoped AWM CLI across four
fresh login shells, preserved one deterministic bounded fact into a neutral
continuation equal to the native control, and produced equal final trees with a
100/100 deterministic tie. That tie is the required parity vector, not a
measured outcome. Its zero counts are limited to live-agent/provider/Pi/Ollama
sessions and provider or network API calls started or issued by the certifier;
they are not a machine-wide observation or a network-containment certificate.
Public copy must not translate this evidence into agent quality, productivity,
comparative performance, adoption, or MAINFRAME-benefit claims.

The older `evals/run-evals.sh` and its v10.1 result are a legacy Phase 3
scaffold. They are not current agent-impact evidence and must not be cited as a
comparative outcome evaluation.

## Benchmarks

Run the checked-in microbenchmark:

```bash
bash benchmarks/superpower_benchmarks.sh
```

A published benchmark result must include:

- Commit SHA
- Operating system and architecture
- Bash version
- Warm-up and iteration counts
- Load mode (`full`, selective, or lazy)
- Raw output
- Successful exit status for the complete benchmark

Microbenchmarks compare narrow operations. They do not establish end-to-end agent productivity, correctness, security, or token savings.

## Security claims

MAINFRAME is a validation layer for accidental misuse, not a sandbox for adversarial code. Security statements must match [SECURITY.md](../SECURITY.md) and the generated [eval audit](SECURITY_EVAL_AUDIT.md).

Avoid absolute statements such as "all inputs are safe," "never uses eval," or "prevents arbitrary command execution." State the threat model, relevant control, and known boundary instead.

## Dependency claims

The core runtime is implemented in Bash. Some optional integrations wrap host commands. Public copy should name that distinction instead of describing the entire repository as dependency-free.

Use `mainframe doctor` to report which optional host capabilities are available.

## Adoption and outcome claims

Do not infer installations from Git clones, CI traffic, page views, or source-archive downloads. Publish productivity, success-rate, or recovery-rate claims only with a reproducible evaluation or a named user case study.

## Release checklist

Before publishing a release:

1. Run the clean-install regression on Linux and macOS.
2. Run the supported Bash and binding suites.
3. Regenerate version, registry, SBOM, checksums, and eval-audit artifacts.
4. Run `scripts/verify-public-claims.sh`.
5. Review README, installation, security, and roadmap language against the generated evidence.
6. Record known limitations in the release notes.

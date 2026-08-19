# MAINFRAME Agent-Agnostic Control Plane Plan

## North star

MAINFRAME should become the trusted local control plane between coding agents and
the machines they operate on: one user-owned layer for shell policy, durable
project memory, reviewed tool execution, and readiness evidence across Pi,
Codex, Claude Code, Copilot CLI, Gemini CLI, and custom agents.

The claim discipline is deliberate: MAINFRAME is agent-agnostic by architecture
and certified by evidence. It complements native host controls and OS isolation;
it does not claim to be an OS sandbox, malware boundary, model router, or
general agent framework.

## Current position

- Pi `0.84.2` on `Darwin-arm64-none` is certified and live-ready locally.
- The GitHub-facing README now presents MAINFRAME as agent-agnostic rather than
  Pi-only.
- The public install path remains source-checkout until the immutable release
  contract is published.
- Cross-host shell policy exists for supported native-hook hosts, but live
  deny-canary evidence is still the key trust gap.
- Linux and Intel macOS certification remain unpromoted until exact evidence
  exists.
- The competitive landscape is fragmented: no located project combines shell
  policy, durable memory, reviewed tools, and readiness evidence across hosts.

## Workstreams

### 1. Release trust spine

Goal: turn the current source-candidate confidence into public, repeatable,
immutable release evidence.

Near-term tasks:

1. Keep the pushed `main` CI run green.
2. Add or preserve exact candidate evidence for every advertised platform.
3. Decide and implement the release-authority split recommended in
   `.github/hardening/release-authority-v1/proposals/split-release-authority.md`.
4. Publish only after the protected release path can prove exact bytes and
   signer/publisher identity.

Acceptance evidence:

- Green CI for the exact commit.
- Reproducible archive and checksum sidecar.
- Release evidence manifests verify offline.
- Public docs accurately state what is released and what remains unverified.

### 2. Host conformance and live enforcement proof

Goal: make "supported host" mean observable enforcement, not static config.

Near-term tasks:

1. Define a host capability registry covering interception, approval, memory,
   audit, launch, and known fail-open/fail-closed routes.
2. Create a disposable-project deny-canary harness for Codex, Claude Code,
   Copilot CLI, and Gemini CLI.
3. Record one safe-allow and one destructive-deny result per supported route.
4. Keep unsupported or unobserved routes explicitly unverified.

Acceptance evidence:

- Reproducible canary artifacts per host.
- Capability registry drives docs and status output.
- A missing or mismatched hook cannot be reported as enforced.

### 3. Cross-platform certification expansion

Goal: move beyond one certified Pi cell without weakening evidence rules.

Near-term tasks:

1. Promote Linux x86_64 Pi evidence from the exact-candidate CI lane.
2. Add Darwin x86_64 evidence only when that lane is real and green.
3. Keep unknown package/version/platform tuples fail-closed.
4. Generate compatibility docs from the manifest rather than hand-maintaining
   duplicate support tables.

Acceptance evidence:

- `config/pi-compatibility.json` contains only artifact-backed certifications.
- `mainframe pi doctor` reports the exact cell honestly.
- Docs and workflow names cannot drift from the manifest.

### 4. Custom-agent developer kit

Goal: make the "any coding agent" claim practical for hosts without a native
adapter.

Near-term tasks:

1. Ship a minimal custom-agent integration example using AWM + stable-core
   invoke.
2. Document the MCP path as the interoperability surface.
3. Add a conformance checklist for third-party agent hosts.
4. Provide one safe example that records memory, invokes a reviewed tool, and
   proves no shell interception claim is made without a native route.

Acceptance evidence:

- A new agent host can follow the guide without reading the whole repository.
- The example passes tests and remains inside documented trust boundaries.

### 5. Product narrative and adoption proof

Goal: make the public story match the evidence.

Near-term tasks:

1. Add a concise "MAINFRAME vs alternatives" page based on the research fleet's
   sourced landscape.
2. Keep the primary message focused on portability: policy, memory, tools, and
   proof survive agent changes.
3. Add an objection-handling section covering native controls, sandboxes,
   memory platforms, MCP gateways, and orchestration frameworks.
4. Publish only claims that map to mechanism, generated evidence, or observed
   adoption.

Acceptance evidence:

- Public-claims tests pass.
- Every comparison row has a source and a scope caveat.
- No page claims MAINFRAME is an OS sandbox or measured productivity booster.

## Seven-day kickoff plan

### Day 1

- Monitor the current CI run to completion.
- Freeze the public narrative around the new README structure.
- Convert this plan into executable issues/tasks.

### Day 2

- Draft the host capability registry schema.
- Draft the live deny-canary harness contract.

### Day 3

- Implement the smallest host conformance test for one host route.
- Document exact evidence requirements for the remaining hosts.

### Day 4

- Draft the custom-agent integration guide and example.
- Verify it with tests.

### Day 5

- Refresh performance measurements for the 10.2 candidate.
- Add a bounded CI regression check if the current suite supports it.

### Day 6

- Promote Linux x86_64 Pi certification only if exact CI evidence exists.
- Otherwise document the remaining blocker precisely.

### Day 7

- Review release readiness.
- Decide whether the release-authority split must land before any public
  10.2.0 release.

## Team kickoff prompt

Use a small mixed-model team:

- Kimi k3 planner: sequence the work, identify dependencies, and turn this
  plan into issues/tasks.
- Kimi k3 product-docs editor: tighten the public narrative and identify doc
  changes needed for the next release.
- Qwen3.8-Max research synthesizer: turn the fleet research into a sourced
  comparison and objection-handling brief.
- Qwen3.8-Max host architect: design the host capability registry and live
  canary evidence harness.

Team rules:

- Read-only until a concrete implementation task is assigned.
- Do not weaken safety, provenance, or fail-closed behavior to make a claim.
- Cite file paths and exact evidence for every recommendation.
- Treat unsupported host routes as unverified, never implied.

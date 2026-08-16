# MAINFRAME A++ Product and Adoption Plan

> **Status:** Proposed strategic plan
>
> **Evidence baseline:** July 31, 2026
>
> **Objective:** Make MAINFRAME the de facto portable Bash control plane for
> coding agents and agentic development environments (ADEs).

This document turns the July 2026 product, technical, onboarding, and market
review into an implementation plan. It defines targets and release gates, not
claims about behavior that has already shipped. Current supported behavior
remains defined by the root README, installation guide, security policy,
generated registry, and integration matrix.

## Executive decision

MAINFRAME should not lead with the size of its function inventory. Its public
product contract should be:

> **MAINFRAME is the portable local control plane for shell-capable coding
> agents: durable memory, deterministic handoffs, and policy-governed Bash
> across agents and ADEs.**

The acquisition wedge is narrower:

> **Give any coding agent durable, inspectable working memory in under ten
> minutes.**

Agent Working Memory (AWM) earns the first successful experience. Safety,
structured output, discovery, and the Bash function library strengthen that
experience after the first proof. The large registry is an implementation
asset, not the headline.

## What A++ means

The objective has two distinct milestones.

1. **A++ product readiness:** MAINFRAME has a small, deny-by-default control
   plane; deterministic function identity; repeatable activation; verified
   packages; green release gates; and honest documentation.
2. **De facto category adoption:** independent projects repeatedly choose it,
   external maintainers contribute integrations, and measured cross-agent
   handoffs outperform the agents' native baseline for the documented use
   cases.

Engineering can deliver the first milestone. The second must be earned through
external evidence; it cannot be established by function count, repository
traffic, or internal demonstrations.

## Evidence baseline

### Proven strengths

The reviewed candidate demonstrated that the foundation is real:

- A clean isolated installation completed with 248 checksummed files and no
  mismatches.
- `mainframe version`, `mainframe doctor`, function search, and function help
  worked after installation.
- An AWM session written in one process was retrieved successfully in another.
- The complete 175-file Bash suite passed during the trust-foundation review.
- The Node.js binding passed 143 tests, the Python binding passed 128 tests,
  and the LSP passed 124 tests and compiled successfully.
- Audited startup medians on macOS with Bash 5.3 were 19.8 ms for the minimal
  profile, 58.3 ms for standard, and 46.5 ms for the agent runtime profile.

These are dated candidate measurements. They must be reproduced from a tagged
release before being used as release or marketing claims. See
[Claims and benchmarks](CLAIMS_AND_BENCHMARKS.md).

### Ranked blockers

| Priority | Blocker | Audited evidence | Product consequence |
|---|---|---|---|
| P0 | MCP invocation is not deny-by-default | The MCP server forwards a caller-supplied name to the Bash executor without proving registry membership; an unregistered `uname` call succeeded | A protocol client can escape the advertised tool catalog and execute a host command, contrary to the [MCP tool contract](https://modelcontextprotocol.io/specification/2025-11-25/server/tools) |
| P0 | Function identity is not canonical | `FUNCTIONS.json` contains 4,457 registrations but 4,374 unique names; the approved policy records 90 collisions: 81 public and 9 private | Runtime, MCP, LSP, and bindings can describe or execute different owners for one name |
| P0 | Public product state is inconsistent | The audited CLI reported 4,501 functions from `version`, 3,435 from `doctor`, and 4,457 registry registrations | First-run output asks users to decide which source is trustworthy |
| P0 | Release confidence is incomplete | The [latest audited public main run](https://github.com/gtwatts/mainframe/actions/runs/30603478762) was red, installation used mutable branch content, and provenance did not cover a complete installable artifact | Early adopters cannot independently verify one supported release path |
| P1 | Loader profiles describe different products | Audited `full` loaded 129 of 185 libraries and 3,234 of 4,374 unique registry names, while `mainframe_load_all` loaded all 185 libraries and all 90 collisions | `full`, lazy, selective, and default loading do not share one stable contract |
| P1 | Default agent surfaces are too large | MCP generated 815 core tools or 4,374 full tools | Discovery cost, ambiguity, and security review grow with inventory rather than user intent |
| P1 | Activation is manual and fragmented | Installation does not prove that Codex, Claude, Copilot, Cursor, or an IDE loaded the appropriate instruction artifact | A successful shell install does not become an agent capability |
| P1 | Adapter packaging is unfinished | LSP tests/build passed, but lint had four errors, the frozen Bun install failed, and the production dependency audit reported two high-severity findings | Editor and protocol integrations are not ready for trusted distribution |
| P2 | Distribution and independent proof are thin | The audited project had one [GitHub release](https://github.com/gtwatts/mainframe/releases/tag/v10.1.0), source-oriented installation, no verified package-manager path, and little external-contributor evidence | Discovery, upgrades, and social proof remain weaker than established developer tools |

The security boundary remains the one documented in
[SECURITY.md](../SECURITY.md): MAINFRAME helps honest-but-fallible agents avoid
mistakes, but it is not an operating-system sandbox. The protocol boundary must
still reject undeclared invocation by default.

## Target architecture

### 1. Trusted bootstrap kernel

Create a small stable core containing only:

- loader and manifest validation;
- structured errors and output;
- capability and approval policy;
- audit recording; and
- the invocation broker.

The bootstrap kernel must not contain network clients, package managers,
domain-specific helpers, or caller-controlled dynamic evaluation.

### 2. One versioned manifest

Every canonical export should declare:

- a stable symbol ID and globally unique Bash name;
- exactly one owning module;
- ordered, typed parameters and a result schema;
- dependencies and supported platforms;
- effects such as pure, read, write, network, process, destructive, or secrets;
- required capability, timeout, and output limit;
- stability, aliases, deprecation version, and earliest removal version; and
- the pack and profile in which it is available.

Generate `FUNCTIONS.json`, lazy indices, profile closures, MCP schemas, LSP
metadata, completion, documentation, and language-binding metadata from this
source. An adapter must not independently choose a function owner or infer a
different call shape.

### 3. Deterministic dependency loader

The loader should resolve a manifest dependency graph, reject missing nodes and
cycles, and validate each module's declared exports. Profiles become named
manifest closures. `full` means every installed pack compatible with the
current host; lazy loading covers every manifest export.

### 4. Single invocation broker

All external adapters should call one interface:

```text
mainframe invoke <canonical-id> --input-json '<object>'
```

The broker performs registry lookup, schema validation, dependency and pack
loading, capability and approval checks, timeout and output confinement, audit
recording, and verified function invocation. It never treats arbitrary shell
text or an external executable name as a registered function.

### 5. Stable core and signed packs

Organize the broad library behind explicit packs, for example:

- `core` - loader, manifest, output, policy, audit, and invocation;
- `std` - stable pure and local Bash helpers;
- `agent` - AWM, handoffs, and agent-runtime operations;
- `data` - structured data and transformation helpers;
- `network` - HTTP and network operations;
- `devops` - Git, containers, cloud, and infrastructure wrappers;
- `security` - analysis and explicitly gated security operations; and
- `experimental` - unstable or compatibility-sensitive modules.

Each pack carries a manifest, compatibility constraints, tests, checksums, and
release provenance. Installing the trusted kernel must not require cloning
demos or every optional pack.

### 6. Discovery-first agent adapters

The default MCP surface should expose a small control plane, such as:

- `status`;
- `search`;
- `describe` or `help`;
- `invoke` or bounded `exec`;
- `awm`; and
- `safety_check` plus audit status.

The exact grouping may change, but the default surface must remain small and
must route every invocation through the broker. Large curated surfaces may be
opt-in by signed pack, never a fallback around authorization.

## Implementation program

The phases below are an implementation sequence, not a release-date promise.
Commit, publication, and production distribution remain separate decisions.

### Phase 0 - Trusted control plane

**Goal:** Remove release-blocking ambiguity and unauthorized execution.

Deliverables:

1. Reject unknown MCP tool names, external executables, invalid schemas, and
   functions outside the active tier or pack.
2. Return protocol-correct error results and add negative authorization tests.
3. Introduce the canonical manifest schema and generate the current registry
   from it without losing supported metadata.
4. Establish owner parity tests across the default, selective, full, lazy,
   CLI, MCP, LSP, Node.js, and Python surfaces.
5. Define the stable kernel and stable public-core export set.
6. Make `version`, `doctor`, registry statistics, documentation, and installer
   output report one clearly named product state.
7. Remove the installer's automatic-discovery overclaim and require explicit,
   verifiable activation.
8. Restore green default-branch CI; make frozen installs, lint, package tests,
   and production dependency audit required gates.

Exit gates:

- zero successful unregistered invocations;
- zero owner disagreements for exposed names;
- zero public collisions in the stable core;
- a default MCP surface of no more than 32 curated tools, with the smaller
  broker surface preferred;
- zero high or critical production dependency findings; and
- all required main-branch checks green.

### Phase 1 - Ten-minute activation

**Goal:** Turn installation into a verified agent capability.

Deliverables:

1. Add merge-safe commands:

   ```text
   mainframe activate <host> --project .
   mainframe activate status
   mainframe deactivate <host> --project .
   ```

2. Support `--dry-run`, never overwrite an existing instruction file, and
   remove only MAINFRAME-managed content during deactivation.
3. Maintain one concise standard Agent Skill and generate thin adapters for
   Codex, Claude Code, GitHub Copilot and VS Code, Cursor, JetBrains AI
   Assistant, Junie, and other supported hosts.
4. Remove static function counts, obsolete examples, and blanket instructions
   to replace standard Unix tools from always-on agent guidance.
5. Make each adapter test prove host discovery and then execute a live AWM
   write/read workflow.
6. Use a randomly generated nonce to prove retrieval from a genuinely new
   agent session without repeating the nonce in the second prompt.

Exit gates:

- clean install in under three minutes on supported macOS and Linux hosts;
- install-to-cross-session AWM retrieval in under ten minutes;
- every supported host can report which MAINFRAME artifact it loaded;
- activation and deactivation are idempotent and preserve user content; and
- at least five host adapters pass clean-environment end-to-end validation.

### Phase 2 - Verified distribution

**Goal:** Make installation, upgrades, rollback, and discovery routine.

Deliverables:

1. Publish reproducible runtime and pack archives with checksums, signatures,
   complete dependency SBOMs, and provenance for the actual artifacts.
2. Make the bootstrap installer resolve an immutable version and verify its
   digest and signature before execution.
3. Publish and verify a Homebrew installation path.
4. Publish the MCP runner through PyPI with a `uvx` or `pipx` workflow.
5. Publish only the Node.js and Python bindings that meet the compatibility
   and release matrix.
6. Enter ADE catalogs and marketplaces only after clean-machine installation
   and activation tests pass.
7. Split demos, historical research, and experimental packs from the default
   runtime payload.

Exit gates:

- one documented immutable install path works from a clean host;
- artifact verification fails closed after any archive modification;
- rollback to the previous compatible release is tested;
- the package and protocol compatibility matrix is published; and
- every advertised distribution channel is exercised in CI or a recorded
  release check.

### Phase 3 - Category proof and ecosystem

**Goal:** Prove that MAINFRAME creates value beyond its own repository.

Deliverables:

1. Publish reproducible evaluations for:
   - recovery after context compaction;
   - parent-to-subagent handoff;
   - cross-host handoff; and
   - destructive-command policy enforcement.
2. Report success rate, latency, token cost, false positives, false negatives,
   environment, and limitations rather than a single promotional percentage.
3. Integrate with established agent Bash executors through their policy hooks
   instead of presenting MAINFRAME as an operating-system sandbox.
4. Publish maintained examples for GitHub Actions, pre-commit, devcontainers,
   Nix, and environment managers where demand is demonstrated.
5. Seed integration RFCs and good-first issues and recruit maintainers outside
   the original project author.
6. Measure the funnel from install, activation, and first AWM write through
   cross-session retrieval and return usage. Any telemetry must be explicit,
   opt-in, privacy-preserving, and documented.

Exit gates:

- independent public projects document successful use;
- external contributors maintain or co-maintain supported adapters;
- evaluations demonstrate a material advantage for the stated handoff use
  cases over the native host baseline; and
- adoption claims cite observable evidence rather than repository traffic.

## Residual collision compatibility project

The `array_join` defect, the 11-name array family, and the three-name AWM
handoff/compression family are fixed. The trust-foundation work reduced the
collision inventory from 97 names to 76.
The remaining work must stay a
deliberate compatibility program rather than being mixed into unrelated trust,
security, documentation, or onboarding changes.

The governing rules remain in
[Public API compatibility](API_COMPATIBILITY.md) and the machine-readable
[function export policy](../config/function-export-policy.json).

### Principles

1. The collision ratchet may only decrease; no new collision is accepted.
2. The stable core reaches zero public collisions before it is declared stable.
3. A legacy collision may remain temporarily only when it is excluded from
   ambiguous agent surfaces and has a recorded canonical owner.
4. Resolve one related collision family per pull request when practical.
5. Preserve the documented default behavior, or provide deterministic
   call-shape dispatch when both historical contracts can be distinguished.
6. Rename alternate behaviors with module prefixes and retain explicit
   forwarding aliases for the documented compatibility window.
7. Every migration includes loader-matrix, registry, CLI, MCP, LSP, and binding
   parity evidence before the baseline is reduced.
8. Removal follows the two-release and next-major-version floor; urgency does
   not bypass the compatibility contract.

### Migration waves

| Wave | Scope | Completion evidence |
|---|---|---|
| A | Freeze the stable-core export set and bind each exposed name to a canonical manifest ID | Zero stable-core collisions and complete cross-surface owner parity |
| B | Resolve the known array, agent, stream, OpenTelemetry, and resilience families | Contract-specific regression tests, aliases, warnings, migration notes, and reduced baseline |
| C | Resolve the remaining public module families from highest exposure and risk to lowest | One owner and one behavior for every public name across every loader and adapter |
| D | Resolve private collisions and retire aliases only after their compatibility floor | Zero unguarded private collisions and documented major-version removals |

This project does not block unrelated work when the affected names remain
outside the stable core and agent invocation surfaces. It does block a stable
release whenever a collision can change the behavior selected by a supported
loader or adapter.

## A++ scorecard

| Dimension | July 2026 baseline | A++ gate |
|---|---|---|
| Invocation authorization | An unregistered external command executed through the MCP executor | 100% rejection of unregistered symbols, undeclared capabilities, invalid parameters, and unavailable packs |
| Public identity | 81 public collision names; audited MCP owner mismatch for 61 and LSP mismatch for 22 | Zero stable public collisions and 100% owner parity across all supported surfaces |
| Private identity | 9 tracked private collisions | Zero unguarded private collisions in stable packs |
| MCP discovery | 815 core tools or 4,374 full tools | No more than 32 curated default tools, preferably the small broker surface |
| Loader contract | `full`, default, lazy, and `mainframe_load_all` expose different closures | `full` equals all installed compatible packs; lazy covers 100% of manifest exports |
| Startup performance | Audited medians: 19.8 ms minimal, 58.3 ms standard, 46.5 ms agent, 181.6 ms default | p95 at or below 25 ms bootstrap, 60 ms standard, and 75 ms default agent pack |
| Agent activation | Manual, host-specific copy and merge instructions | One reversible command plus host-discovery and cross-session proof for at least five hosts |
| Package health | LSP build/tests passed; frozen install, lint, and production audit remained red | Frozen install, lint, build, tests, and zero high/critical production findings |
| Supply chain | Mutable branch installation and incomplete artifact provenance | Reproducible signed artifacts, verified installer, complete SBOM, and tested rollback |
| Portability | Current macOS and Ubuntu coverage | Green matrix for every advertised Bash version on Linux GNU and macOS BSD tooling |
| Public reliability | Latest audited main run was red | Required default-branch and tagged-release checks remain green |
| Adoption | Early, predominantly maintainer-driven evidence | Independent public users, repeat usage, external maintainers, and reproducible outcome evidence |

Performance gates describe intended profiles, not the current monolithic
default. Each result must report its commit, host, Bash version, warm-up,
iterations, raw output, and selected pack closure.

## Required test strategy

The A++ program adds five test layers to the existing Bash suites:

1. **Authorization and adversarial input:** unknown symbols, shell metacharacters,
   external executables, capability denial, malformed JSON, oversized output,
   timeout, and unavailable-pack cases.
2. **Cross-surface golden contracts:** representative pure, read, write,
   network, destructive, timeout, and invalid calls must have the same owner,
   schema, status, and result shape in CLI, MCP, LSP metadata, Node.js, and
   Python.
3. **Loader graph verification:** every profile closure, missing dependency,
   dependency cycle, undeclared export, alias, and ownership conflict.
4. **Clean-host activation:** install, activate, host discovery, AWM nonce write,
   new-session retrieval, deactivation, reinstall, and upgrade on every
   supported ADE.
5. **Artifact and supply-chain verification:** reproduce archives, alter an
   archive to prove failure, validate provenance and SBOM contents, install,
   upgrade, and rollback.

Core, security, authorization, and compatibility-contract tests must not be
skipped on a platform advertised as supported.

## Release governance

Each phase has separate gates:

1. **Plan approval** authorizes the architecture and workstream scope.
2. **Implementation approval** authorizes source changes on a working branch.
3. **Commit and push approval** authorizes publication to the remote branch.
4. **Release approval** authorizes tags, packages, marketplaces, release notes,
   and public claims.

No phase is complete because its code exists locally. Completion requires the
phase's tests, documentation, migration notes, and evidence artifacts. A later
phase must not weaken an earlier deny-by-default or compatibility gate.

## Non-goals

- MAINFRAME is not an operating-system sandbox for adversarial code.
- The project will not expose every registry function as a default agent tool.
- Agent instructions will not require wholesale replacement of standard Unix
  tools.
- Function count is not a product-quality or adoption metric.
- Legacy compatibility will not be broken merely to reach a lower collision
  count faster.
- A marketplace listing will not be treated as proof of successful activation
  or user value.

## External standards and ecosystem references

Implementation and adapter decisions should be checked against current primary
documentation rather than copied from historical integration files:

- [Agent Skills open standard](https://agentskills.io/home)
- [Model Context Protocol tool specification](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
- [OpenAI Codex AGENTS.md guidance](https://developers.openai.com/codex/guides/agents-md/)
- [OpenAI Codex MCP guidance](https://developers.openai.com/codex/mcp/)
- [Claude Code memory](https://code.claude.com/docs/en/memory),
  [MCP](https://code.claude.com/docs/en/mcp), and
  [hooks](https://code.claude.com/docs/en/hooks)
- [GitHub Copilot customization overview](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/overview)
- [VS Code Agent Skills](https://code.visualstudio.com/docs/agent-customization/agent-skills)
- [Cursor rules](https://docs.cursor.com/context/rules) and
  [MCP](https://docs.cursor.com/context/model-context-protocol)
- [Vercel just-bash](https://github.com/vercel-labs/just-bash) and
  [bash-tool](https://github.com/vercel-labs/bash-tool)

## Immediate next decision

Approve or revise the product contract at the top of this document. Once it is
approved, Phase 0 should begin in this order:

1. MCP invocation authorization and negative tests;
2. canonical manifest and owner-parity contract;
3. stable-core boundary and collision isolation;
4. consistent version, count, installer, and documentation state; and
5. green CI, package, lint, frozen-install, and dependency-audit gates.

The first Phase 0 pull request should remain narrowly focused on the MCP
authorization defect and its regression suite. It should not rename unrelated
colliding functions.

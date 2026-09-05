# MAINFRAME open-source growth plan

**Planning baseline: September 5, 2026.** This is the contributor and adoption
program. [CONTROL_PLANE_PLAN.md](CONTROL_PLANE_PLAN.md) remains authoritative
for implementation dependencies, supported contracts, and release promotion.
[A_PLUS_PLUS_PLAN.md](A_PLUS_PLUS_PLAN.md) is the historical requirements
baseline; [ROADMAP.md](../ROADMAP.md) is a legacy feature inventory. If a growth
milestone would outrun an engineering gate, the engineering gate wins.

## The promise and the direction

**Help coding agents work more safely and reliably in your native shell.**

MAINFRAME supplies reviewed tools, checks on supported execution routes, and
durable project memory. The intended result is less supervision and repeated
setup while useful work still gets done. The long-range direction is to become
the go-to control plane for different coding agents: a common, user-owned
place for permissions, context, execution, and evidence. Universal support and
productivity improvements must be earned, not implied by that ambition.

Open source is part of the product: users can inspect protections, reproduce
failures, change agent hosts, and contribute adapters without depending on a
single provider. Maintainable contracts and responsive review make that useful.
Function counts, stars, and downloads are secondary signals.

Priority caller cells are **macOS + Bash**, **macOS + zsh**, **Linux + Bash**,
and **Linux + zsh**. The native library engine is Bash 4.4+; zsh calls the
runtime through supported CLI routes. Each result must identify OS,
architecture, shell/runtime version, agent version, and commit or artifact.
The priority matrix does not certify every host, platform, or library export.
There is no new Windows support commitment in this program.

Protection is for honest-but-fallible agents on documented paths. MAINFRAME
is not an OS sandbox or an adversarial containment boundary. Native edits,
indirect scripts/builds, network effects, and host-specific routes need explicit
coverage statements. Recovery has limits: restoring files cannot undo every
external action. Keep those limits next to demos and integration claims.

## Starting evidence and gaps

Baseline source: [`06eec567`](https://github.com/gtwatts/mainframe/commit/06eec5675880c7af5ffebfb2265b2a52892d4f5a),
an unpublished `10.2.0` candidate. The September 5 local review recorded a
fresh Codex MCP invocation and project-memory handoff on macOS. These are local
observations, not public cross-platform certification or evidence of repeat use.
Use [the integration matrix](INTEGRATION_MATRIX.md),
[compatibility records](COMPATIBILITY.md), and
[claims policy](CLAIMS_AND_BENCHMARKS.md) for promotion decisions.

The baseline still needs safety/correctness repairs, fresh platform execution,
and release-integrity renewal. CI stopped at an expired receipt before most
platform lanes ran. Linux was not freshly executed in that review. The
onboarding workstream verified local mechanism proof and a separate current
project-memory recipe on macOS. An initial restricted-task failure passed when
retested natively; environment restrictions must be reported separately.
Configuration, CLI discovery, live invocation, live hook enforcement, and a
published artifact are distinct checkpoints. Do not advertise these gaps as
fixed because a workstream or PR exists.

## Milestones

These are dependency gates, not promised dates. Review progress weekly while
work is active; move a milestone only when its evidence is linked.

| Milestone | Dependencies | Acceptance and decision |
|---|---|---|
| M0: clear front door | Current claim review | README, About, contributor entry points, and support scope agree. A newcomer can identify the purpose, candidate status, first action, and limitation. |
| M1: dependable first ten minutes | Baseline repair; implementation roadmap phases 0–3 as applicable | Fresh operators on all four priority caller cells can discover the right install route, run one reviewed tool, preserve/retrieve context in a fresh process, identify live host coverage, and find update/rollback instructions. Record failures and elapsed time; ten minutes is a target to test. |
| M2: reproducible demonstration | M1; tested recovery and relevant platform gates | Publish a disposable-workspace demo showing a covered mistake denied, legitimate work allowed, an interrupted task recovered, and measured overhead with exact versions. Scope every claim to the observed routes. |
| M3: small voluntary pilot | M1–M2; released frozen artifact and phase 5 prerequisites | Complete the four-week learning plan below, record return use and support cost, and decide continue, narrow, or repair. No general improvement claim from this cohort. |
| M4: earned distribution | Pilot decision; verified release/upgrade/rollback; a maintainer for each advertised adapter | Publish approved demos and integration recipes with reproducible evidence and a clear support path. Expand only the cells and workflows that can be maintained. |

M0 documentation can proceed while baseline repairs are incomplete. Internal
first-use trials and demo preparation can also proceed with candidate status
shown. Public pilot recruitment, paid studies, and releases need their own
authorization and readiness; this plan does not start them.

## Work packages

`Active` below means work is assigned, not accepted or shipped. Task identifiers
are internal coordination references; they grant no permissions. The maintainer
should add public PR/issue links as work becomes reviewable. Unassigned packages
remain proposals and should not acquire an owner through assumption.

| ID / package | Owner and state | Depends on | Bounded deliverable and acceptance |
|---|---|---|---|
| G0: baseline repair | Repair workstream, task `01a071de-df04-7e70-9c70-6207d212e085`; assigned, completion unverified | Existing review and engineering phase 0 | Resolve validated defects and broker expectations; let correctness lanes run without weakening publication gates. Link exact-commit regression and platform evidence. Keep vulnerability details in the security process. |
| G1: first-use docs | Onboarding workstream, task `01a0720c-ebab-74f0-8665-c80ea2bab7f5`; prepared for review | Existing public CLI; G0 for readiness claims | Deliver [agent onboarding](AGENT_ONBOARDING.md) and [readiness checklist](AGENT_READINESS_CHECKLIST.md) with tested tool/project-memory recipes, prerequisites, failure interpretation, and a dated four-cell matrix. Untested Linux cells remain explicit. |
| G2: first-use proof coverage | Unassigned implementation owner | G1 reproduction; current invoke/AWM contracts | Verify the existing mechanism proof and current project-memory onboarding against the public contract. Test valid result, failed result, fresh-process readback, and cleanup; report environment restrictions separately and avoid claiming live host interception. |
| G3: positioning and contribution | Repository growth workstream, task `01a0720c-88b1-7e80-bd44-1ee201bda0de`; prepared for review | Current source/evidence review | Focused README, CONTRIBUTING, templates, and this plan; verify links/claims and About/topics readback. Draft PR, no automatic merge. |
| G4: portable readiness evidence | Unassigned platform maintainer | G0–G2; tested install/update/rollback paths | One reproducible fixture per priority caller cell, including BSD/GNU differences and the actual Bash engine. Capture install, restart, tool call, memory readback, failure diagnosis, and rollback evidence. |
| G5: protection, recovery, overhead demo | Unassigned demo maintainer | G4; applicable foundation gates | One small repository and script showing denial, allowed work, interrupted-state recovery, and latency. Report false blocks and missing routes. Repeat on the advertised platforms before publishing claims. |
| G6: adapter contribution path | Unassigned adapter maintainer | Existing adapter model; G1/G4 | Document one exact host/version contract and its conformance entry point. A new contributor can test structured output, denial, unavailable support, and recovery without adding a permissive fallback or changing authority. |
| G7: pilot and distribution | Repository owner; planning only | M1–M2; release/phase 5 gates; explicit outreach approval | Freeze cohort questions and decision thresholds; run the consented pilot; publish only reviewed evidence and approved stories. Record maintainer time before expanding. |

For G4–G6, start with one fixture, route, or demo rather than a broad rewrite.
The maintainer scopes and assigns an issue before labeling it `good first issue`
or `help wanted`. Do not create a second implementation roadmap or bypass
existing contract owners. The current parallel workstreams own disjoint paths;
coordinate shared-doc references before merging them.

Every contributor/agent handoff should contain: user problem, owned paths,
allowed effects, dependencies, exact starting commit, acceptance checks,
evidence location, reviewer, and known limitations. A contributor owns review
follow-through. Being able to generate a patch is not enough to mark a package
complete. See [CONTRIBUTING.md](../CONTRIBUTING.md).

## A small pilot that measures return use

**Proposal only; no invitations or external posts are authorized by this file.**
After the gates above, ask the owner to approve a four-week cohort of 5–8
people who already do shell-heavy coding work. Include macOS and Linux users,
Bash and zsh callers, and at least two agent hosts. Choose participants willing
to describe failures and stop using the tool; enthusiasm alone is not evidence.

1. Before recruitment, freeze the tested artifact, supported cells, installation
   and recovery instructions, feedback questions, and maintainer time budget.
2. Week 1: observe first use with consent. Record completion, time to the first
   useful task, setup interruptions, and every failure to identify readiness.
3. Weeks 2–4: allow normal voluntary use. Ask for one short weekly report:
   what task, what helped, what blocked useful work, what needed recovery, and
   whether they chose MAINFRAME again. No daily nagging or required usage.
4. At the end, publish aggregate observations only with participant consent.
   Include withdrawals, missing responses, supported cells, and limitations.

Use a lightweight opt-in log, not automatic collection of shell commands,
private repositories, prompts, credentials, or raw audit records.

| Measure | Definition |
|---|---|
| Voluntary weekly use | Participants choosing MAINFRAME for at least one real task that week / all enrolled participants; report missing responses separately |
| First-use completion | Participants completing the agreed install, tool, memory, and readiness steps / participants attempting them; report elapsed time and failures |
| Successful task | Participant-defined task outcome completed, with human corrections and Mainframe's role noted |
| Interruption and false-block cost | Setup repetitions, unnecessary denials, and manual interventions per attempted task; record task type |
| Protection and recovery | Covered mistake cases denied and allowed-write failures recovered, with route and unrecoverable effects stated |
| Overhead | Repeated timings against the same workload without Mainframe, fixed versions/hardware, warm/cold split, sample count and median/tail latency |
| Maintainer burden | Triage, review, support, compatibility, and evidence-renewal hours each week; unresolved queue age |

Proposed continuation threshold, to agree before recruitment: a majority of
all enrolled participants return voluntarily in each of weeks 3 and 4, no
unresolved critical regression in the advertised workflow, and support fits
an owner-agreed weekly budget. Also require useful-task and false-block feedback
to justify expansion. If the sample is too small or incomplete, report that;
do not convert anecdotes into a statistical product claim. If retention or
support cost fails, narrow the supported workflow and repair the friction.

This cohort informs usability and maintenance decisions. Formal agent-impact
claims remain governed by [the live-study preregistration](AGENT_IMPACT_LIVE_STUDY.md)
and the control-plane roadmap's confirmatory/generalization requirements. Do
not reuse convenience cohort results as those studies or silently change their
protocol, inference budget, or authorization.

## Distribution through useful work

Prepare assets in this order; publish only after owner approval and the matching
milestone evidence is available:

| Asset | Audience and useful content | Required proof |
|---|---|---|
| Short terminal demo | A coding-agent user sees one covered mistake stopped, useful work continue, and context survive a new session | G5 recipe, exact versions, visible boundaries, reproducible transcript |
| Agent-specific quickstart | A Codex or Pi user can establish actual invocation and understand hook coverage | G1/G6, tested host version, clean install/update/recovery path |
| Contributor walkthrough | A Bash or adapter contributor can fix one failure and run its contract checks | Small merged example, reviewer, commands and expected output |
| Technical write-up | Agent maintainers can inspect policy decisions, structured results, and adapter boundaries | Source links, conformance results, unresolved limitations |
| Pilot story | Practitioners can evaluate whether the workflow fits their work | Participant consent, observed outcome, time/support cost, no invented testimonial |

Use the existing README, docs, demos, releases, and GitHub Discussions as the
first destinations. Consider community posts and integration-directory entries
only when a tested recipe exists and each external submission is approved.
No paid campaigns, mass outreach, automatic social posting, or promises of
platform partnerships. Measure whether readers successfully start and return,
not just clicks or stars.

## Longer-range expansion

Sequence: dependable local core → explicit cross-machine handoff → bounded
coordination. Before handing work across machines, prove route coverage,
authority, state recovery, upgrade compatibility, and useful productivity on
the local core. A future handoff carries selected context, project/revision
identity, unfinished work, and evidence; it must not transfer executable
approvals, credentials, or ambient permissions. The destination revalidates
its own checkout and policy.

Continuous sync and remote execution are future work. A later bounded job,
such as testing an exact commit on a second machine, needs authenticated
workers, cancellation, retry semantics, resource limits, and inspectable results.
Advance only if the simpler handoff reduces supervision and its recovery works.

## GitHub metadata change record

Repository: `gtwatts/mainframe`. Baseline read on September 5, 2026. The applied
metadata change is limited to About description and topics. Readback verified
the exact description and topic set below, the unchanged homepage, and existing
public visibility, main default branch, Issues, and Discussions. The existing
homepage is the repository itself, `https://github.com/gtwatts/mainframe`, and
remains unchanged; no separate product site has been established here.

Before description:

> Agent-agnostic control plane for coding agents: shell policy, durable memory, reviewed Bash tools, and readiness evidence for Pi, Codex, Claude Code, Copilot, Gemini, and custom agents.

After description:

> Help coding agents work more safely and reliably in native shells. Open-source tools, policy checks, and durable project memory for macOS and Linux. Bash 4.4+ runtime; agent and MCP integrations.

Before topics:

```text
agent-memory agent-runtime agentic-ai ai-agents ai-safety aider automation bash
bash-library claude-code cli codex coding-agents cursor developer-tools linux
mcp pure-bash shell shell-scripting
```

After topics:

```text
agent-memory agent-runtime ai-agents automation bash bash-library claude-code
cli codex coding-agents developer-tools linux macos mcp shell shell-scripting zsh
```

To reverse, restore the exact before description and topic set through GitHub
About or its repository APIs, then read them back. Record execution and
verification in the PR. Repository visibility, permissions, branch/security
settings, license, billing, secrets, release rules, and automation are outside
this change. Existing Issues and Discussions stay available; templates point to
versioned documentation and the existing security-reporting policy.

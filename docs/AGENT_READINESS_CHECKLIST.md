# Agent readiness and adapter conformance checklist

Use this alongside [Agent onboarding](AGENT_ONBOARDING.md). It is a report
template over existing commands, not a new certifier or authorization plane.
Record `PASS`, `FAIL`, or `UNVERIFIED` per observation. A skipped check is
unverified. Keep the next action concrete and do not aggregate partial evidence
into a single "safe" or "ready everywhere" badge.

## Repeat for each machine and calling shell

| Check | Evidence / command | Passing scope and next action on failure |
|---|---|---|
| Identity | Date, OS, architecture, source SHA or archive digest, runtime version/root; `command -v mainframe`, `mainframe version` | Names and versions alone do not bind bytes; resolve a mismatched installation first. |
| Shell selection | `mainframe shell status --json`; record `active_root`, `selected_cli_resolved`, `state`, `bash_state`, `zsh_state` | Reopen stale sessions; preview profile repair for reported drift. Record caller version separately from `doctor`'s Bash engine. |
| Core health | `mainframe doctor` | All runtime checks pass. A failure is not repaired by setting a readiness flag. |
| Discovery | `mainframe setup --project .` | Read-only host, shell, and existing project-memory signals. A missing mapping before onboarding is not a broken installation. |
| Mechanism | `mainframe setup --project . --proof` | Fixed invocation, ephemeral session continuity, classifier-only denial, reported cleanup. Does not run an agent. Record restricted-task failures separately from native-terminal results. |
| Project memory | Optional temporary recipe in the onboarding guide | Exact checkpoint readback in a new process; bounded context and handoff. Does not prove second-agent consumption, provenance promotion, or sync. |
| Codex compatibility | `mainframe host status codex --json` | Record platform, selected source, selected state, and trust boundary; this command does not launch Codex. |
| Codex static hook | `mainframe protect status codex --project .`; `mainframe launch codex --project . --dry-run` | Saved configuration and preflight only. Review native trust and test the actual route next. |
| Codex live MCP | Exact runtime-bound package `--check`, then tool inventory and dummy `mainframe_json_string` in a fresh task | Verify value and kernel IDs. Record whether saved configuration or a test-only override supplied the server. |
| Pi offline | `mainframe pi status`; `mainframe pi doctor` | Record package identity, compatibility, disk state, next action. External doctor cannot report live activation. |
| Pi live | After package changes, `/reload` or restart, then `/mainframe doctor` inside Pi | Record the actual result, loaded tools/hooks, and exact host/runtime identity; do not infer from disk status. |
| Native interception | Existing [native host procedure](ONBOARDING.md#finish-in-the-native-host) | Controlled disposable sentinel, host denial, unchanged sentinel, matching audit; name the route. A classifier or synthetic hook alone cannot pass this row. |
| Release | `mainframe release readiness --json` plus published matching artifact and required remote results | Offline readiness is not publication proof. Skipped platform CI cannot pass a platform cell. |

Share only a redacted summary. Raw local status, memory output, private
certificates, and logs may contain absolute paths or project content. Preserve
full details privately when needed to reproduce a failure.

## Dated local evidence: September 5, 2026

Baseline source: `06eec5675880c7af5ffebfb2265b2a52892d4f5a`, version 10.2.0.
The installed candidate used archive SHA-256
`f6fe8553d02bf8e416bdcf3a74af51ea40eec44166c27ee2f3a169147178978c`.
These are bounded local observations for onboarding, not a release certificate.

| OS / calling shell | Engine | Observation | Still unverified |
|---|---|---|---|
| macOS arm64 / Bash | Bash 5.3.15 | **VERIFIED locally:** fresh login CLI discovery/version; temporary structured invocation and project-memory recipe. | Full native host enforcement and release certification for this run; Intel macOS. |
| macOS arm64 / zsh 5.9 | Bash 5.3.15 | **VERIFIED locally:** fresh login CLI discovery/version; same temporary recipe through the Bash CLI. | Full native host enforcement and release certification for this run; Intel macOS. |
| Linux / Bash | Required: Bash >=4.4 | **UNVERIFIED:** no Linux machine execution in this workstream. | Native x86_64 glibc run and exact artifact evidence. |
| Linux / zsh | Required: Bash >=4.4 behind zsh | **UNVERIFIED:** no Linux machine execution in this workstream. | Caller discovery, engine identity, and exact artifact evidence. |

The four rows describe the requested OS/caller combinations. They do not
collapse architecture-specific certification: the existing
[installed AWM conformance protocol](INSTALLED_AWM_HANDOFF_CONFORMANCE.md#cross-platform-acceptance)
requires six native cells across Darwin arm64, Darwin x86_64, and Linux x86_64
glibc, all bound to one archive. Linux arm64, musl, WSL, and Windows are not
established by this checklist. The System76 workstation was not accessed.

The native `setup --proof` passed. In the restricted Codex task environment,
the same mechanism failed: raw invocation exited 66 and structured invocation
reported `outcome=failed`, `result_available=false`; temporary ledger evidence
recorded `invalid_executor_result` / `PermissionError`. Retrying natively
passed. This is an environment distinction, not evidence of a changed default
output format or a confirmed Mainframe regression. It demonstrates why outer
JSON `ok=true` and exit 0 alone are insufficient success checks.

Offline Codex selected its certified 0.146.0 managed payload; live native hook
trust was not exercised here. Offline Pi reported canonical disk state but
unverified default package identity/compatibility; live Pi was not run.
Historical compatibility entries are not fresh activation proof. No installation,
profile, agent configuration, commit, or release was changed by this workstream.

## Acceptance criteria for another agent adapter

1. **Declare the surface.** Identify the exact host package/version/platform,
   launch route, callable tools, native hook events, and unsupported routes.
   Extend the existing host/compatibility manifests and generated adapters;
   do not invent an independent readiness authority. See
   [Native host certification](NATIVE_HOST_CERTIFICATION.md).
2. **Preserve the public contract.** Reviewed calls use canonical IDs, closed
   schemas, and the existing durable broker. Reject unknown IDs and changed
   arguments. Never fall back to arbitrary shell or a legacy helper after a
   rejection. Separate trusted application helpers from agent-authorized routes.
3. **Verify behavior in the real host.** Record inventory and a harmless call
   with checked output/kernel IDs, plus an actual allow/deny hook lifecycle for
   every claimed native route. Test untrusted/unloaded hooks, changed executable
   bytes, unavailable dependencies, and unsupported versions honestly.
4. **Preserve user control and recovery.** Reuse previewed, merge-safe lifecycle
   changes; preserve unrelated configuration. Verify restart, reload, update,
   and rollback. Human hook trust cannot be fabricated by a test or adapter.
   Routine authorized diagnostics should not gain extra confirmation prompts.
5. **Carry useful context.** Use public project-memory routes; demonstrate a
   second fresh process consuming bounded context and a real host consuming a
   handoff before claiming agent continuity. Memory conveys no approval authority.
6. **Earn portability and usefulness.** Bind each claimed cell to exact
   artifacts and native execution. Reuse the existing shell-onboarding and
   installed-AWM certifiers; synthetic/source checks do not substitute for live
   runs. Measure task completion, elapsed time, added latency, false blocks,
   repeated approvals, and recovery burden before claiming productivity gains.

Report: **identity → observed route → result → evidence location → limitation
→ next action**. See [claims policy](CLAIMS_AND_BENCHMARKS.md) and
[agent impact evaluation](AGENT_IMPACT_EVALUATION.md) for stronger public claims.

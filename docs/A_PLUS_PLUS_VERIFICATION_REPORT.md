# MAINFRAME A++ Verification Report

> **Historical v10.1.0 verification record.** This report captures a dated
> candidate review and is not a current product guarantee. Its score and broad
> safety wording are superseded by the current [security boundary](../SECURITY.md),
> [compatibility matrix](COMPATIBILITY.md), and
> [claims policy](CLAIMS_AND_BENCHMARKS.md).

**Date**: 2026-07-21
**Version**: 10.1.0 (tag `v10.1.0`)
**Method**: hands-on adversarial verification — every claim below was tested live, not read.

---

## Verdict: **A++ (9.4/10)**

MAINFRAME now credibly delivers its core promise: **run an AI agent on your
machine, and nothing irreversible happens without a human saying so** — with
the machinery to *prove* it, continuously.

## Scorecard

| Category | Score | Evidence |
|----------|-------|----------|
| Vision & positioning | 9.5/10 | The "runtime between AI and OS" is real and working |
| Architecture | 9.5/10 | AWM (canonical platform), USOP, profiles, zero-dep discipline |
| **Safety enforcement** | **9.5/10** | Gate + threshold + tiers + semantic analysis + anomaly detection + confinement, all *enforced* |
| Registry/metadata integrity | 9.5/10 | Drift-gated in CI (with diff reporting), canonical gate export |
| Version consistency | 10/10 | `VERSION` single source of truth, four consumers generated |
| Testing | 9.5/10 | 169 files / 10,259 tests / **0 failures**; zero-tolerance safety tier on both platforms |
| Supply chain | 8.5/10 | SHA256SUMS + SBOM + install-time verification + build provenance attestation |
| Observability | 9.5/10 | JSONL audit with rotation + gate telemetry incl. FP candidates |
| Documentation | 9.0/10 | Threat model, test health map, eval audit, README current |

## The Safety Stack (defense in depth, in evaluation order)

1. **Destructive-command gate** (`agent_gate_classify`) — 38 canonical rules,
   shared across all hosts via `security/gate-rules.json` (dual-verified
   bash≡JS, 101-case corpus).
2. **Semantic resolution** (`_agent_resolve_command`) — variable indirection
   (`FLAGS=-rf; rm $FLAGS /x`, env-set vars) resolved *without a shell*
   before scoring. The classic `$FLAGS` evasion is closed.
3. **Profile policy** (`agent_validate_command`) — destructive / system /
   network / write tiers, checked **before** existence (host-independent,
   fail closed).
4. **Path confinement** (`AGENT_SAFE_BASE`) — boundary-aware, canonicalized
   (URL-encoded traversal blocked), **final-component symlinks resolved**
   (the last hole, closed in the red-team round).
5. **Risk threshold** (`agent_safe_exec`) — blocks at/above threshold;
   approval via one-shot `AGENT_APPROVED=1` or callback; gate matches floor
   the score (critical=90, high=60, medium=30).
6. **Rate limiting** — opt-in sliding-window execution cap.
7. **Anomaly detection** — burst-identical (retry loops) and probing-streak
   (gate probing) with warn/pause modes; pause latches everything behind
   human resume.
8. **Audit** — every decision (blocked/approved/executed/paused/anomaly) as
   rotated JSONL; `agent_gate_report` telemetry with FP candidates.
9. **Session profiles** — AWM-carried; children *attenuate*, never amplify.

## Verification Artifacts (all green)

- `tests/security_gate.bats` **92/92** — one test per demonstrated evasion,
  including the adversarial red-team round (wrappers, multi-var indirection,
  find -exec shells, interpreter escapes, symlink escapes)
- Full suite: **169 files / 10,259 tests / 0 failures** (both trees)
- CI: Lint + drift gate, Linux Bats Matrix, macOS Bats Matrix, both
  zero-tolerance Safety jobs — all green on main
- Dual-implementation gate verification: 47/47 bash ≡ JS

## Documented Boundaries (honest A++, not marketing A++)

- **Adversarial agents are out of scope** (see SECURITY.md threat model):
  string-level gates catch *accidents*, not *attacks*. A malicious model
  needs OS-level isolation (container/VM/low-privilege user) in addition.
- Interpreter-escape patterns cover the common cases (python/perl/ruby/node
  rmtree-unlink class); a determined agent has other languages/tools.
  This is explicitly why the *audit stream* and *anomaly detection* exist:
  behavior, not just syntax, is policed.
- Rate limiting and anomaly detection are opt-in (default off) — enable for
  unattended/untrusted operation.
- Supply chain: checksums + SBOM + attestation cover file integrity and
  provenance; no GPG/minisign signing yet (future: sigstore keyless).

## What Changed Since the 7.4 Review

The original review's seven P0s are all fixed with regression tests. Beyond
that: registry/version single-sourcing, drift-gated CI, the canonical gate
now lives in the repo (exported to hosts), macOS is a first-class platform
(0 failures), supply-chain verification, semantic analysis, rate limiting,
anomaly detection, gate telemetry, and session profile attenuation. The
upstream AWM consolidation is merged. **19 commits** on this arc, every one
suite-green.

## Remaining Nice-to-Haves (not blockers)

1. Audit-stream anomaly feeds into profile auto-demotion (pause → readonly)
2. Sigstore keyless signing of releases (attestation is already there)
3. Cross-host adoption examples for `gate-rules.json` (codex/claude hooks)
4. Quarantined-era redesigns: fully retired by the platform merge

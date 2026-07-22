# MAINFRAME Integration Matrix

**Date**: 2026-07-21 | **Version**: 10.1.0
**Scope**: how MAINFRAME integrates with agent harnesses, multi-agent
systems, and operator tooling — and the performance contract for each.

---

## Performance Contract (measured 2026-07-21, Apple Silicon, bash 5.3)

Every harness should choose the load mode that matches its invocation pattern:

| Mode | Cold cost | Coverage | Use when |
|------|-----------|----------|----------|
| Full eager load (`source lib/common.sh`) | **~190ms** | All 185 libs, 4,458 functions | Interactive shells, resident scripts |
| Lean agent set (`MAINFRAME_LIBS='core,agent_safety,awm,validation,atomic,idempotent,dryrun,confirm,json'`) | **~40ms** | All agent-facing functions (real, not stubs) | Per-command agent shells |
| Function-level lazy (`MAINFRAME_LAZY=1`) | **~40ms** | 768 curated stubs; libs load on first call | Per-command shells hitting common functions |
| Custom (`MAINFRAME_LIBS='json,validation'`) | **~30ms** | Only what you name | CI steps, hooks, single-purpose calls |
| Skip (`MAINFRAME_SKIP_AUTOLOAD=1` / `MAINFRAME_NO_AUTO_SOURCE=1`) | ~0 | Nothing | Bootstrap, debugging |

Additional measured facts:

- `bash -lc` startup alone: ~10ms. Verify engine banner: only on full loads.
- Gate classification (destructive patterns) runs **in-process** in the Pi
  extension (TypeScript) — sub-millisecond, no shell spawned.
- Audit writes (agent audit JSONL + Pi bash-audit.jsonl) are single appends,
  sub-millisecond each; rotation capped at 10MB × 5.
- Rule of thumb: **agents should never pay the 190ms full load per command.**

## Harness Integrations

### 1. Pi (this harness — pi.dev / pi-coding-agent)

| Surface | Mechanism | State |
|---------|-----------|-------|
| Extension | `~/.pi/agent/extensions/mainframe.ts` | ✅ active |
| Destructive gate | Loads canonical `security/gate-rules.json` (34 rules) at startup; builtin fallback | ✅ canonical |
| Bash wrapper | Wraps every bash command: gate classify → bash 5 + pipefail + **lean MAINFRAME_LIBS (~40ms)** | ✅ optimized 2026-07-21 |
| Tools | `mainframe_status/search/help/exec/awm/bash_safety_check` | ✅ active |
| Audit | `~/.pi/agent/.mainframe-pi/bash-audit.jsonl` (risk/blocked/warnings per command) | ✅ active |
| Activation note | Extension loads at session start; gate/wrapper updates need a session restart | ⚠️ per-session |

### 2. Claude Code

| Surface | Mechanism | State |
|---------|-----------|-------|
| Instructions | `docs/mainframe-claude-template.md` → `~/.claude/CLAUDE.md` (counts + lean-load guidance current) | ✅ refreshed |
| Agent Teams bridge | `lib/agent_teams.sh` reads `~/.claude/teams` config, exposes team roster/status to MAINFRAME agents | ✅ present |
| Hooks | `hooks/dispatcher.sh` (now lean-loads by default, overridable) | ✅ optimized |
| Gate consumption | Same `security/gate-rules.json` (any JS host can load it; verified 47/47 corpus parity) | ✅ canonical |

### 3. Codex / generic CLI harnesses (Gemini, Cursor, custom)

| Surface | Mechanism | State |
|---------|-----------|-------|
| Gate rules | `security/gate-rules.json` — harness-native pattern list with tiers + JS regexes | ✅ canonical export |
| Runtime contract | env knobs: `MAINFRAME_LIBS`, `MAINFRAME_LAZY`, `MAINFRAME_SKIP_AUTOLOAD`, `MAINFRAME_NO_AUTO_SOURCE` | ✅ documented above |
| Instructions | CLAUDE.md template adapts to any harness's system-prompt slot | ✅ available |
| Safety stack | `lib/agent_safety.sh` is harness-agnostic bash (profiles, gate, confinement, anomaly, telemetry) | ✅ works standalone |

### 4. MCP (Model Context Protocol)

| Surface | Mechanism | State |
|---------|-----------|-------|
| Server | `mcp/server.py` exposes MAINFRAME functions as `mainframe_*` MCP tools (tiered access: core or full) | ✅ present |
| Registry | Reads `FUNCTIONS.json` (drift-gated, current) | ✅ current |
| Docs note | mcp/README.md counts (117 libs / v6.0) are stale — cosmetic, tracked | ⚠️ cosmetic |

### 5. LSP (editor tooling)

| Surface | Mechanism | State |
|---------|-----------|-------|
| Metadata | `FUNCTIONS.lsp.json` — 185 libs, regenerated with the registry | ✅ current |
| Consumers | signature help / hover in LSP-capable editors | ✅ present |

### 6. Multi-agent systems

| Surface | Mechanism | State |
|---------|-----------|-------|
| AWM inheritance | Child agents adopt parent session: checkpoints, discoveries, **profile (attenuate-only)** | ✅ enforced |
| agent_loop | Spawn/pause/resume/join with detached daemon hygiene (trap + fd detachment) | ✅ hardened |
| agent_comm | File-backed mailbox between agents | ✅ present |
| Claude Code Teams | `agent_teams.sh` bridge to `~/.claude/teams` | ✅ present |
| cmux orchestrator | External orchestrator (outside this repo) drives MAINFRAME-equipped agents in cmux workspaces | ✅ in use |

## Consistency Guarantees (drift-proofing)

| Claim | Enforcement |
|-------|-------------|
| One version number | `VERSION` → `sync-version.sh` → CI drift gate |
| Registry matches code | `sync-version.sh --check` in lint job (reports diffs) |
| Gate rules identical everywhere | `export-gate-rules.py --verify` (bash ≡ JS, 47 cases) |
| Checksums match files | `generate-sbom.sh --check`; install-time verification |
| Test claims real | 169 files / 10,259 tests, zero-tolerance safety job on ubuntu + macOS |

## Remaining Integration Gaps (honest list)

1. mcp/README.md counts stale (cosmetic).
2. No packaged hook for Codex CLI yet (gate-rules.json is ready for it).
3. Lazy stub list (768) is a curated subset — prefer the lean LIBS set when
   full coverage matters (this is why the Pi wrapper uses LIBS, not LAZY).
4. Claude Code hook scripts that call non-core functions should set
   `MAINFRAME_LIBS` explicitly (dispatcher defaults to the lean set).

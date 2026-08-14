# MAINFRAME Integration Matrix

**Candidate snapshot**: 2026-08-09 | **Target**: 10.2.0 (unpublished)
**Scope**: how MAINFRAME integrates with agent harnesses, multi-agent
systems, and operator tooling — and the performance contract for each.

The registry planned for this candidate contains **4,406 unique functions,
4,475 registrations, and 193 libraries**. These are source-candidate facts,
not claims about the assets in the public v10.1.0 release.

---

## Performance Contract (historical measurement: 2026-07-21, Apple Silicon, bash 5.3)

The timings in this section were measured on 2026-07-21 and have not been
rerun for the planned 10.2.0 candidate. They are retained as a dated baseline,
not presented as fresh candidate results.

Every harness should choose the load mode that matches its invocation pattern:

| Mode | Cold cost | Coverage | Use when |
|------|-----------|----------|----------|
| Full eager load (`source lib/common.sh`) | **~190ms** | Full generated registry at the measured commit | Interactive shells, resident scripts |
| Lean agent set (`MAINFRAME_LIBS='core,agent_safety,awm,validation,atomic,idempotent,dryrun,confirm,json'`) | **~40ms** | All agent-facing functions (real, not stubs) | Per-command agent shells |
| Function-level lazy (`MAINFRAME_LAZY=1`) | **~40ms** | 768 curated stubs; libs load on first call | Per-command shells hitting common functions |
| Custom (`MAINFRAME_LIBS='json,validation'`) | **~30ms** | Only what you name | CI steps, hooks, single-purpose calls |
| Skip (`MAINFRAME_SKIP_AUTOLOAD=1` / `MAINFRAME_NO_AUTO_SOURCE=1`) | ~0 | Nothing | Bootstrap, debugging |

Additional measured facts:

- `bash -lc` startup alone: ~10ms. Verify engine banner: only on full loads.
- Gate classification (destructive patterns) runs **in-process** in the Pi
  extension (TypeScript) — sub-millisecond, no shell spawned.
- That dated performance fact is not a fresh 10.2 benchmark. Classifier parity
  is established separately by the candidate's shared normalizer tests.
- Audit writes (agent audit JSONL + Pi bash-audit.jsonl) are single appends,
  sub-millisecond each; rotation capped at 10MB × 5.
- Rule of thumb: **agents should never pay the 190ms full load per command.**

## Harness Integrations

### 1. Pi (this harness — pi.dev / pi-coding-agent)

| Surface | Mechanism | State |
|---------|-----------|-------|
| Package | root `package.json` loads `skills/pi/extensions/mainframe.ts` and `skills/pi/` | First-party 10.2 candidate payload |
| Lifecycle | `mainframe pi status/install/remove` maintains one canonical receipted package source, preserves unrelated settings/backups, replaces resource-suppressing filters, migrates stale/legacy roots, and rolls back failed mutations | Candidate source and Bash 3.2/5.x tests pass; project-local package/resource collisions fail closed |
| Lifecycle authority | Pi exposes status and dry-run guidance, while the canonical gate blocks model-issued `mainframe ... --yes`, runtime update/confirmed upgrade, and Homebrew mutation; a human must perform confirmed lifecycle work in an external terminal | Candidate source tests pass |
| Destructive gate | Verifies and invokes the exact shipped `security/gate-normalizer.mjs` plus ordered `security/gate-rules.json`; unavailable or mismatched policy blocks shell execution | Canonical parity candidate tests pass |
| Bash wrapper | Scrubs inherited startup/function/language/dynamic-loader variables before Pi's initial shell, then uses a fixed protected Bash 4.4+, pipefail, fixed helper PATH, and signed wrapper marker | Candidate source and real current-Pi tests pass from zsh and Bash callers; pre-extension process injection remains outside this boundary |
| Tools | `status/install_commands/search/help/exec/awm/bash_safety_check` plus `/mainframe` | Exact seven-tool surface validated locally |
| Function execution | Canonical MANIFEST owner only; stable-core delegates by canonical ID to the bounded `mainframe invoke` broker, while every non-stable-core function stays on the guarded legacy path and uses Pi human confirmation | Candidate source tests pass; this is source-candidate evidence, not live activation on the user's running Pi process |
| Audit | Private rotating `bash-audit.jsonl` stores decision metadata plus command SHA-256/length, not raw commands | Candidate source tests pass |
| Pi versions | Current `@earendil-works/pi-coding-agent` 0.84.1 and legacy-scope `@mariozechner/pi-coding-agent` 0.73.1 | Local package/tool/runtime compatibility validated 2026-08-09; pinned CI gate present but not yet public-green |
| Activation note | Package changes require `/reload` or a restart, followed by `/mainframe status`; MAINFRAME CLI uninstall refuses incomplete/attached Pi state, but direct Homebrew uninstall has no Formula preflight and requires the documented detach chain | Runtime load is distinct from disk `ready` state |

### 2. Supported onboarding hosts

| Surface | Mechanism | State |
|---------|-----------|-------|
| Codex | Managed `AGENTS.md` plus enforced `.codex/hooks.json` `PreToolUse` adapter | Candidate source present |
| Claude Code | Managed `CLAUDE.md` plus enforced `.claude/settings.json` `PreToolUse` Bash adapter | Candidate source present |
| GitHub Copilot CLI | Managed `.github/copilot-instructions.md` plus enforced `.github/hooks/mainframe.json` `preToolUse` shell adapter | Candidate source present; Copilot documents hook timeouts as fail-open |
| Gemini CLI | Managed `GEMINI.md` plus enforced `.gemini/settings.json` `BeforeTool` adapter for `run_shell_command` | Candidate source present |

`mainframe onboard --host <host> --project <path>` requires explicit consent
before it installs an enforcement adapter. It also creates or resumes a private,
project-scoped AWM session and writes a bounded memory protocol into every
managed instruction block. Dry-run and refused-consent paths do not initialize
AWM or mutate the project.

The release contract advertises exactly `Darwin-arm64-none`,
`Darwin-x86_64-none`, and `Linux-x86_64-glibc`. Source and local candidate tests
establish the adapter contract; final exact-candidate remote evidence remains
pending for Intel macOS and Linux, so this matrix does not claim those host
executions or completed cross-platform release certification. WSL is untested.

### 3. Other CLI harnesses (Cursor, custom)

| Surface | Mechanism | State |
|---------|-----------|-------|
| Gate contract | `security/gate-rules.json` (43 ordered rules plus per-rule input metadata) and `security/gate-normalizer.mjs`; consumers call the exported classifier before regex matching | ✅ both files ship in the 10.2 candidate payload |
| Runtime contract | env knobs: `MAINFRAME_LIBS`, `MAINFRAME_LAZY`, `MAINFRAME_SKIP_AUTOLOAD`, `MAINFRAME_NO_AUTO_SOURCE` | ✅ documented above |
| Instructions | The managed-block format can be adapted to another harness's instruction slot | Available, not an enforced supported-host adapter |
| Safety stack | `lib/agent_safety.sh` is harness-agnostic bash (profiles, gate, confinement, anomaly, telemetry) | ✅ works standalone |

### 4. MCP (Model Context Protocol)

| Surface | Mechanism | State |
|---------|-----------|-------|
| Server | The separately built `mainframe-mcp` 10.2.0 package exposes MAINFRAME functions as `mainframe_*` MCP tools through both isolated console entry points and `python -I -m mainframe_mcp` | Wheel/sdist candidate present; not yet published |
| Registry | Stable-core identity and closed schemas come from `MANIFEST.json`, whose 26 reviewed contracts derive from `config/invocation-policy.json` | Candidate metadata; not a published-release claim |
| Public surface | Exactly 26 brokered stable-core tools; legacy tier environment configuration is rejected | ✅ fail-closed package/source and broker-delegation tests |

### 5. LSP (editor tooling)

| Surface | Mechanism | State |
|---------|-----------|-------|
| Metadata | `FUNCTIONS.lsp.json` — 4,406 owner-filtered entries from 193 libraries for the planned candidate | Candidate metadata |
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
| Canonical Bash/JavaScript gate parity | `export-gate-rules.py --verify` applies the shipped normalizer and checks 163 cases across all 43 rules |
| Checksums match files | `generate-sbom.sh --check`; install-time verification |
| Platform claims require evidence | Local tests and workflow definitions are not substitutes for an exact-candidate CI artifact; `Darwin-x86_64-none` and `Linux-x86_64-glibc` execution remain pending for the final candidate |

## Remaining Integration Gaps (honest list)

1. The exact Pi compatibility matrix is not yet green in public CI. The legacy
   0.73.1 RPC client-side `bash` command does not emit `user_bash`, so no
   extension can gate that one RPC route; its normal agent tool calls and TUI
   `user_bash` event are covered. Current Pi 0.84.1 emits the RPC hook and passes
   the complete safe/block regression.
2. The final 10.2.0 candidate does not yet have current `Darwin-x86_64-none` or
   `Linux-x86_64-glibc` execution proof; WSL is untested and unadvertised.
3. Public v10.1.0 lacks the full runtime archive and release-evidence assets
   described by the candidate workflow.
4. GitHub immutable releases, the required release environment/tag protections,
   and an accessible `gtwatts/homebrew-mainframe` tap are not currently in place.
5. Lazy stub list (768) is a curated subset — prefer the lean LIBS set when
   full coverage matters (this is why the Pi wrapper uses LIBS, not LAZY).
6. Claude Code hook scripts that call non-core functions should set
   `MAINFRAME_LIBS` explicitly (dispatcher defaults to the lean set).

Within the canonical contract, `low` means only that no ordered lexical rule
matched after bounded normalization. It is not a safety, semantic-analysis,
authorization, or containment claim about the command's downstream behavior.

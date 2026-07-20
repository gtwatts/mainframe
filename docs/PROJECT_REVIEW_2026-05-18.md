# MAINFRAME Project Review — 2026-05-18

## Scope

This review focused on the repository as checked out at `/Users/gordonwatts/Documents/Projects/mainframe`, with special attention to AI-agent integration docs and the request to include Pi and Codex alongside Claude and other coding tools.

## Evidence gathered

- Repository shape: top-level CLI (`mainframe`, `bin/mainframe`), `lib/` bash libraries, `scripts/`, `tests/`, `docs/`, and `skills/` platform adapters.
- Registry: `FUNCTIONS.json` reports **3,821 functions** across **152 libraries**.
- Test assets: 265 shell scripts and 167 Bats files found in the repository scan.
- Existing assistant support before this change: Claude Code, Kimi CLI, Google CLI, OpenCode, Cursor, Aider, Clawdbot, and Vercel AI SDK had some form of skill/prompt/rule artifact.
- Newly added support in this review: Pi skill instructions and Codex `AGENTS.md` instructions.

## High-level assessment

MAINFRAME is already structured well for AI coding assistants:

1. **Discoverability** — `FUNCTIONS.json`, `CHEATSHEET.md`, `mainframe quickref`, and platform skills give agents concrete function names instead of making them infer bash snippets.
2. **Agent memory** — AWM is a strong differentiator because it gives finite-context agents a durable state layer outside the conversation.
3. **Safety posture** — the library includes validation, atomic file operations, guarded execution concepts, and structured outputs that map well to agent workflows.
4. **Portability** — the pure-bash stance is valuable for CLI agents, containers, CI, and remote systems.
5. **Integration surface** — the `skills/` directory is the right home for platform-specific instruction packs.

## Changes made from this review

| Area | Change |
|---|---|
| Central integration docs | Added `docs/AI_CLI_INTEGRATIONS.md` with setup instructions for Pi, Claude Code, Codex, Cursor, Aider, OpenCode, Kimi, Google AI CLI, Clawdbot, Vercel AI SDK, and custom agents. |
| Pi integration | Added `skills/pi/SKILL.md` explaining Pi-native MAINFRAME tool usage (`mainframe_status`, `mainframe_search`, `mainframe_help`, `mainframe_exec`, `mainframe_awm`, `mainframe_bash_safety_check`) and normal bash/source usage. |
| Codex integration | Added `skills/codex/AGENTS.md` for Codex/Codex CLI repository instructions. |
| README discoverability | Updated the AI coding assistants matrix to include Pi and Codex and link to the new central integration guide. |
| Install docs | Added Pi and Codex setup sections and refreshed key function/library counts. |
| Skill index | Updated `skills/README.md` to include Pi and Codex and point other agents at the central integration guide. |
| Claude instructions | Updated `CLAUDE.md` platform support and reference list. |
| Claude template | Refreshed count/version language in `docs/mainframe-claude-template.md`. |

## Findings and recommendations

### 1. Documentation counts were inconsistent

Some docs described older counts such as `4,000+ functions`, `117 libraries`, or `v6.0`, while `FUNCTIONS.json` reports 3,821 functions and 152 libraries. I updated the primary install/skills/integration paths and the current platform skill files. A follow-up doc pass should decide whether to normalize archival research/design documents too or leave them explicitly historical.

### 2. Pi integration should be documented as a wrapper/tool layer

Pi's MAINFRAME integration exposes tools around MAINFRAME. Those tool names should not be documented as shell functions from `lib/common.sh`. The new Pi docs explicitly distinguish:

- Pi tool layer: `mainframe_status`, `mainframe_search`, `mainframe_help`, `mainframe_exec`, `mainframe_awm`, `mainframe_bash_safety_check`.
- Bash layer: `source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"` and call MAINFRAME functions directly.

### 3. Codex should use `AGENTS.md`

Codex-style agents commonly consume repository instruction files. Adding `skills/codex/AGENTS.md` makes MAINFRAME easier to install into projects without forcing Codex users to adapt Claude-specific docs.

### 4. Local project CLI works under a clean environment

A direct `./mainframe doctor` initially failed in this Pi-wrapped shell because imported environment functions and strict-mode variables interacted with the project-local CLI. Running the project CLI under a clean environment with required variables set succeeded:

```bash
env -i HOME="$HOME" USER="$USER" TMPDIR="${TMPDIR:-/tmp}" \
  PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" \
  MAINFRAME_ROOT="$PWD" ./mainframe doctor
```

Result: `All systems operational. YO JOE!`

Follow-up recommendation: make `mainframe doctor` more resilient to unusual exported shell functions and missing-but-common variables in strict mode, because AI-agent wrappers often alter the shell environment.

### 5. Verification and review docs are strong but fragmented

The repository already contains many review, analysis, and roadmap documents. The new `docs/AI_CLI_INTEGRATIONS.md` should become the canonical user-facing integration guide, while deeper analysis documents can remain as historical/research material.

## Validation run

- `mainframe_status(validate=true)` against installed `~/.mainframe`: passed.
- Project-local clean-env doctor: passed.
- `validate_skill skills/pi`: passed.
- `git diff --check`: passed.
- Artifact existence/markdown fence sanity check for changed docs: passed.

## Suggested follow-up backlog

1. Normalize function/library count language in all platform skill files and historical docs, or intentionally label historical docs as archival.
2. Add a small `scripts/docs/check-doc-counts.sh` that compares current docs against `FUNCTIONS.json` stats.
3. Add a smoke test for each `skills/*` artifact to ensure referenced files exist and install snippets remain accurate.
4. Harden `./mainframe doctor` for strict-mode startup under agent wrappers and minimal environments.
5. Consider adding `skills/generic/INSTRUCTIONS.md` for tools that are neither Claude/Codex/Pi nor currently represented.

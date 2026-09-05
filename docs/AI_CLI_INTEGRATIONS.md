# MAINFRAME for AI CLI and Coding Agents

MAINFRAME is a user-owned safety, memory, and structured-shell layer for AI
tools that control computers through shell commands. This guide explains the
verified setup paths for Pi, Claude Code, OpenAI Codex, GitHub Copilot CLI, and
Gemini CLI, plus the lower-assurance shell integration available to other
agents.

Current function and library counts are generated in `FUNCTIONS.json`; use the registry or `mainframe count` instead of copying a static count into agent instructions.

---

## Start with one read-only discovery

MAINFRAME's immutable release path is publication-gated: it requires a
qualifying published release and verified runtime assets. For development or
evaluation, use a reviewed source checkout:

```bash
git clone https://github.com/gtwatts/mainframe.git ~/.mainframe
# Linux with Bash 4.4+ at /bin/bash:
/bin/bash --noprofile --norc -p ~/.mainframe/install.sh
# Apple Silicon macOS after `brew install bash jq`:
/opt/homebrew/bin/bash --noprofile --norc -p ~/.mainframe/install.sh
```

Review [Install MAINFRAME](../INSTALL.md) for Intel macOS, custom locations,
the exact source caveat, and the future verified-release path.

Then make the CLI easy for agents and shells to discover. This `PATH` entry is
for interactive `mainframe` commands; supported generated hooks do not resolve
their enforcement boundary from `PATH`:

```bash
export MAINFRAME_ROOT="$HOME/.mainframe"
export PATH="$MAINFRAME_ROOT/bin:$PATH"
```

Verify:

```bash
mainframe doctor
cd /path/to/your/project
mainframe setup --project . --proof
mainframe setup --project .
```

The `--proof` form is a zero-residue mechanism proof, not a strictly read-only
operation: it uses a private mode-700 temporary directory for one reviewed pure
invocation and an isolated AWM checkpoint retrieved by a fresh Bash process. It
also classifies a destructive canary without executing it. On success it
removes the temporary AWM and broker state, leaving no project, user AWM, or
audit state. It never runs Pi or a coding agent and does not prove live host
protection or agent adoption.

The hostless setup report without `--proof` is strictly read-only: it discovers
Bash/zsh, Pi, supported host candidates, existing protection, and project AWM
state without selecting a host or changing any configuration. A missing or
incompatible certified runtime now receives an end-to-end recovery handoff in
that same report:
offline status, eligible managed-runtime online/offline preview and apply
commands, and the exact protected-setup follow-up. Setup prints this plan but
does not execute it.

Using Pi? Diagnose the exact package/version/platform and preview activation
before any user-settings transaction:

```bash
mainframe pi doctor
mainframe pi install --dry-run
```

### Explicit project onboarding

For Codex, Claude Code, Copilot CLI, or Gemini CLI, use the onboarding command
printed by setup instead of editing host files by hand. Preview first, then
approve the same project and host interactively:

```bash
cd /path/to/your/project
mainframe setup --project . --host claude-code --dry-run
mainframe setup --project . --host claude-code
```

Valid host values are `codex`, `claude-code`, `copilot`, and `gemini`. Applying
from a non-interactive process requires an explicit `--yes`; use it only after
reviewing the same inputs and dry-run output. `--yes` is unnecessary for a
preview.

Onboarding merge-safely writes the managed project instructions and native
pre-tool hook, then verifies the local gateway and project configuration. That
is static readiness, not proof that an already-running host loaded or trusted
the hook. Start the protected session with `mainframe launch`, complete its
normal trust or hook-review flow, inspect its native hook UI or diagnostics,
and run a controlled deny canary in a disposable project. See
[Onboard a coding agent](ONBOARDING.md) for the complete verification and
rollback sequence.

Use the compatibility-gated launcher for daily work:

```bash
mainframe host status claude-code
mainframe launch claude-code --project . --dry-run
mainframe launch claude-code --project .
```

`mainframe host status [HOST] [--runtime auto|managed|system] [--json]` is the
read-only, offline view of the deterministic managed and system candidates.
Managed payloads are reserved under
`${XDG_DATA_HOME:-$HOME/.local/share}/mainframe/host-payloads`. Status hashes
local state but does not install or execute a candidate, contact a registry, or
change files. Its human output recommends managed acquisition only when the
current host/platform is certified and the deterministic target is absent;
corrupt state, Gemini, and unsupported platforms do not receive an impossible
managed-install command.

On an advertised tuple, optionally install a private Codex, Claude Code, or
Copilot runtime through explicit verified acquisition:

```bash
mainframe host install claude-code --download --dry-run
mainframe host install claude-code --download --yes
```

No install uses the network unless `--download` is present. That mode connects
anonymously only to the exact SHA-512-SRI-pinned HTTPS package URLs on
`registry.npmjs.org`. Its dry-run performs the real acquisition and complete
staged-runtime authentication in a private ephemeral workspace, then removes
the workspace without publishing a generation.

Use `--package-dir` for a separately obtained, fully offline package set:

```bash
mainframe host install claude-code --package-dir /path/to/pinned-tarballs --dry-run
mainframe host install claude-code --package-dir /path/to/pinned-tarballs --yes
```

The complete contract is
`mainframe host install HOST (--download | --package-dir DIR) [--dry-run | --yes] [--json]`.
The two sources are mutually exclusive; a local directory must contain every
exact tarball basename selected from the native-host package lock. Both routes
verify locked SRI and package identity, and the extractor re-verifies SRI on
the same descriptor used for bounded extraction. Download follows no redirects
or proxy overrides, sends no registry credentials, invokes no npm or package
scripts, and executes no vendor code. Publication is atomic and requires
`--yes`; `--json` never prompts. An actionable request requires `--dry-run` or
`--yes`, while a safe no-op, refusal, or validation error may return first.
Gemini is recognized but its managed install remains gated. The receipt includes
`package_set_sha256`, and its bundle ID binds the MAINFRAME version plus that
exact package set.

Removal authenticates and atomically moves only the current exact generation to
retained private same-filesystem quarantine:

```bash
mainframe host remove claude-code --dry-run
mainframe host remove claude-code --yes
```

Before `host remove --yes`, stop new launches and any agent process that may
still need the managed executable. The authenticated quarantine move is
identity-safe, not an availability guarantee during concurrent launch/removal,
and it does not terminate an already-running process. `--yes` authorizes the
move only; it does not verify that agents are stopped.

Removal preselects an exact generated quarantine ID before the atomic move.
Success returns it; uncertain interruption or helper-failure output retains the
same recovery ID so an operator can inspect managed status and preview that
exact generation without network access:

```bash
mainframe host restore claude-code --quarantine-id removed.0123456789abcdef01 --dry-run
mainframe host restore claude-code --quarantine-id removed.0123456789abcdef01 --yes
```

Restore accepts no path, glob, `latest`, or implicit selection; requires the
active deterministic target to be absent; preserves the exact generation inode;
and leaves the consumed slot empty. Install, remove, and restore do not mutate
global packages, `PATH`, profiles, host configuration, or project files. There
is no managed-host update or prune command.
On an advertised platform, default `auto` resolution lets a valid managed
payload win and lets an absent payload or host-specific unsupported managed
route fall back to an authenticated system CLI; an expected but corrupt payload
fails closed. An unadvertised platform is not selectable, and invalid platform
policy blocks every source. `--runtime system` on status, setup, or launch is an
explicit source override, not a platform-support override. Managed selection is
full-tree authenticated. A system direct-native selection is
executable-digest-only. System Codex, Claude Code, and Copilot wrapper routes
report a runtime-tree/unpinned-Node boundary; system Gemini reports incomplete
closure with unpinned Node.js. Status reports the boundary of the source
actually selected. See
[Managed host payloads](MANAGED_HOST_PAYLOADS.md), including why managed Gemini
remains blocked pending a complete dependency closure and pinned Node.js.

Launch authenticates the exact host artifacts pinned by MAINFRAME's native
certification manifest and binds exact absolute Bash, supported
system/package-manager `jq`, installed gateway, and installed safety-policy
paths plus their four-digest SHA-256 seal for the generated `/bin/bash -p`
bootstrap. The bootstrap verifies those four byte identities before every hook
call. Direct host starts do not receive all five launch values and fail closed
when the configured hook is invoked, so `mainframe launch` is required for a
protected session. For npm wrappers,
launch accepts Node.js only from a supported system, package-manager, or
version-manager layout, then hashes and rechecks Node plus
`hash-package-tree.mjs` around authentication and before exec. Arbitrary PATH
shims are rejected, but a user-managed Node installation is not an external
trust anchor. Python 3.10+ is required for the managed-host install/remove/restore
helpers, but not for status or runtime launch. Static identity and configuration
still do not prove that a running host loaded the hook or
ingested project instructions: runtime loading remains `UNVERIFIED` until the
host's native trust and hook-review flow is completed.

After consent, onboarding creates or resumes one private file-backed AWM
session mapped to the canonical physical project. Coding agents can recover
that session from every fresh shell process without carrying a SID:

```bash
mainframe awm project ensure --project . --discover-root
mainframe work "current task" --project . --tokens 1200 --format prompt
mainframe awm project checkpoint --project . --discover-root current_phase implementation --importance high
mainframe awm project handoff prepare --project . --discover-root next-agent --tokens 1200 --format prompt
mainframe awm project close --project . --discover-root
```

Only explicit `ensure` creates or renews a project binding. Writes and close
serialize against renewal and require the exact mapped session to remain
active; reads never initialize memory as a side effect. `mainframe work` is the
daily host-neutral read: it rejects absent or unsafe mappings, caps returned
context, marks it as untrusted data, and executes none of the write templates
it presents.

Use AWM only for durable decisions, high-signal discoveries, meaningful
progress, and concise outcomes. Never put credentials, tokens, secrets, raw
sensitive payloads, or routine command chatter into it. Both context and
handoff budgets cover the complete returned artifact. See the
[AWM reference](reference/awm.md) for the full project command surface and
local-user trust boundary.

For a reviewed, machine-callable helper, prefer the canonical invocation API
to sourcing the broad library graph:

```bash
mainframe invoke mf:data:json:json_get \
  --input-json '{"json":"{\"name\":\"Ada\"}","key":"name"}'
```

The 10.2 source has exactly 26 broker-invocable
stable-core contracts in `config/invocation-policy.json`. `MANIFEST.json`
binds each contract to one canonical ID, owner, closed named-input schema,
argument shape, result kind, effects, capabilities, timeout, and output limit.
The broker rejects unknown IDs and unreviewed contracts, starts a clean Bash
child with a fixed helper `PATH`, confines time and combined output, terminates
the child process group on a bound violation or surviving descendant, rejects
ambiguous/binary-invalid JSON framing, and writes a private audit record
without recording input values. Adapters use `--format broker-json-v1`; the
default CLI format writes the reviewed function's raw stdout/stderr.

Pi, the public MCP runner, and the source-candidate Node.js and Python binding
APIs delegate to this API. MCP exposes exactly the 26 reviewed stable-core
tools and rejects legacy tier configuration. Pi's human-confirmed
non-stable-core path and the bindings' trusted raw-Bash methods remain
legacy/unbrokered compatibility surfaces. Pi excludes
raw arguments from progress/results/audit metadata, while retaining them only
inside the separate human confirmation preview when a non-stable call needs
approval. This boundary reduces the ways an honest-but-fallible agent can
invoke shell helpers; it is not an operating-system sandbox or a defense
against a hostile same-user process.

Every generated bash script should start with:

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## Platform support matrix

| Tool / platform | Project artifact | Recommended install / instruction path |
|---|---|---|
| **Pi** | root `package.json`, `config/pi-compatibility.json`, `skills/pi/` | Run `mainframe pi doctor`, preview with `mainframe pi install --dry-run`, then explicitly activate; reload Pi and run `/mainframe doctor` for live proof. |
| **OpenAI Codex / Codex CLI** | `AGENTS.md`, `.codex/hooks.json` | `mainframe onboard --host codex --project .` adds instructions and the trusted-project `PreToolUse` Bash gate. Review it with `/hooks`. |
| **Claude Code** | `CLAUDE.md`, `.claude/settings.json` | `mainframe onboard --host claude-code --project .` adds instructions and the Bash `PreToolUse` gate. |
| **GitHub Copilot CLI** | `.github/copilot-instructions.md`, `.github/hooks/mainframe.json` | `mainframe onboard --host copilot --project .` adds instructions and the `preToolUse` Bash gate. |
| **Gemini CLI** | `GEMINI.md`, `.gemini/settings.json` | `mainframe onboard --host gemini --project .` adds instructions and the `BeforeTool` shell gate; managed runtime install remains gated. |
| **Cursor** | `skills/cursor/mainframe.mdc` | Copy to `.cursor/rules/mainframe.mdc`. |
| **Aider** | `skills/aider/CONVENTIONS.md` and `.aider.conf.yml` | Add `read: ~/.mainframe/skills/aider/CONVENTIONS.md` to Aider config. |
| **OpenCode** | `skills/opencode/SKILL.md` | Load as OpenCode custom/project instructions. |
| **Kimi CLI** | `skills/kimi-cli/SKILL.md` | Load as Kimi CLI project/system instructions. |
| **Legacy Google AI adapters** | `skills/google-cli/SKILL.md` | Instruction-only compatibility material. Prefer the enforced Gemini CLI activation above. |
| **Clawdbot** | `skills/clawdbot/preamble.md` | Add to `~/.clawdbot/clawdbot.json` preamble. |
| **Vercel AI SDK / custom agents** | `skills/vercel-ai-sdk/system-prompt.md` | Read the file into the model/system prompt. |
| **Any CLI agent** | This guide | Add the generic instruction snippet below to its system/project prompt. |

---

## Pi integration

Pi can use MAINFRAME in two complementary ways:

1. **Tool-aware mode** through Pi integration tools, when installed in Pi:
   - `mainframe_status` verifies installation, registry stats, CLI path, and optional doctor/count checks.
   - `mainframe_install_commands` returns read-only status, dry-run, reload, and verification guidance. Lifecycle confirmation is reserved for a human terminal.
   - `mainframe_search` discovers canonical functions by name, category,
     library, or description. It defaults to `purpose=script`;
     `purpose=execute` filters to canonical results eligible for
     `mainframe_exec`. Results expose risk, purity, idempotence, bounded
     examples, and execution disposition. Ranking is relevance-first with
     safety and idempotence tie-breaks; these hints do not authorize execution.
   - `mainframe_help` returns exact registry details for one function.
   - `mainframe_exec` executes one canonical registry function with a bounded timeout. Stable-core names resolve to reviewed canonical IDs and run through `mainframe invoke`; every other function stays on Pi's guarded legacy path and requires Pi's human confirmation UI.
   - `mainframe_awm` manages full explicit-session AWM. Its project scope is deliberately limited to status, human-confirmed initialization/close, and bounded explicit context retrieval; project memory is never injected automatically.
   - `mainframe_bash_safety_check` classifies shell commands before execution.

   These seven Pi integration tools wrap MAINFRAME; they are not ordinary shell
   functions in `lib/common.sh`. The first-party extension and skill ship in the
   10.2 candidate package. The extension verifies the shipped gate normalizer
   digest before applying the same ordered policy used by the Bash gateway and
   fails closed if the policy cannot load. At extension load and again before
   agent Bash or `user_bash`, it removes inherited Bash startup, exported
   function, language-loader, and dynamic-loader variables from the environment
   Pi gives its initial shell; accepted commands then enter a protected Bash
   4.4+ wrapper. This cannot undo code injected into Pi itself before the
   extension loaded. The extension stores command hashes and lengths rather
   than raw commands in its private rotating audit log and appends its guidance
   to Pi's existing system prompt.

   Install or migrate the user package explicitly:

   ```bash
   mainframe pi status
   mainframe pi doctor
   mainframe pi install --dry-run
   mainframe pi install --yes
   ```

   Run the real `--yes` command yourself in an external terminal. The Pi
   extension blocks model-issued MAINFRAME lifecycle confirmation even if the
   agent includes that flag. The manager preserves unrelated Pi settings,
   canonicalizes package paths, replaces filtered entries that would suppress
   the bundled resources, records a private receipt for safe upgrades/removal,
   and quarantines recognized user-level legacy copies transactionally. A
   changed install prints the exact private migration `backup_id` plus
   `restore_available=true|false`. Exact restore is deliberately limited to a
   migration of both legacy resources from an existing settings file with no
   prior manager receipt. It
   refuses project-local `.pi` package or legacy-resource collisions because
   changing project resources requires separate authority. After a changed
   install, use `/reload` or restart Pi, then run `/mainframe doctor`; disk
   state alone does not prove the current process loaded it. The external
   doctor never starts Pi and exact-matches package, version, and platform;
   unknown combinations remain `COMPATIBILITY_UNVERIFIED`. Pi mirrors the
   in-process diagnosis in a concise `MF ...` footer badge before each agent
   turn and refreshes it on `/mainframe status` and `/mainframe doctor`; a
   failed core doctor forces `MF BLOCKED`.

   If that first live doctor fails and install reported
   `restore_available=true`, preview and explicitly recover the exact
   pre-install snapshot rather than selecting a backup by path or recency:

   ```bash
   mainframe pi restore --backup-id .mainframe-pi-backup-YYYYMMDDTHHMMSSZ.A1b2C3 --dry-run
   mainframe pi restore --backup-id .mainframe-pi-backup-YYYYMMDDTHHMMSSZ.A1b2C3 --yes
   ```

   Restore accepts only the validated private backup shape emitted by a completed
   legacy migration and refuses current settings, receipt, or project drift.
   It preserves the backup, never executes Pi, and requires a restart after a
   changed recovery.

   Before uninstalling MAINFRAME, detach only its managed package entries:

   ```bash
   mainframe pi remove --dry-run
   mainframe pi remove --yes
   ```

   Run the confirmed removal yourself. It is transactional, preserves unrelated
   settings and migration backups, and also requires a Pi reload or restart.
   The MAINFRAME CLI refuses incomplete or attached Pi state before uninstall.
   Direct Homebrew uninstall cannot run a Formula preflight, so detach first or
   Pi can retain a dangling package path.

   The candidate is tested against current
   `@earendil-works/pi-coding-agent` 0.84.2 and the legacy-scope
   `@mariozechner/pi-coding-agent` 0.73.1. The latter does not emit
   `user_bash` for its client-side RPC `bash` command, so extensions cannot
   guard that one legacy RPC path; normal agent Bash and interactive TUI Bash
   still pass the shared package contract. Current Pi emits the event in RPC
   mode and passes the full safe/block path.

   Like every Pi extension, MAINFRAME runs with the user's permissions. These
   controls reduce accidental and unauthorized agent actions; they do not turn
   Pi into an OS sandbox or defend a user-owned install from another hostile
   process under the same account.

2. **Bash/source mode** for scripts and terminals:

   ```bash
   source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
   mainframe search "create json object"
   mainframe quickref --search "name=John, age"
   json_object "tool=pi" "runtime=mainframe"
   ```

   `mainframe search` accepts multi-word descriptions and returns canonical,
   relevance-first recommendations. Safety and idempotence break comparable
   matches; risk labels remain hints, not authorization. `quickref --search`
   accepts quoted multi-word signature text.

Recommended Pi operator prompt:

```text
Use MAINFRAME for bash work. First run mainframe_status(validate=true). Prefer mainframe_search(purpose="script") and mainframe_help before inventing function names; use purpose="execute" only when looking for a mainframe_exec-eligible canonical result. Treat search risk and safety fields as guidance, never authorization. For one reviewed stable-core helper, call mainframe_exec with one explicit function name and bounded timeout so Pi uses MAINFRAME's canonical broker. Use mainframe_awm for durable task memory. For scripts, source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh" at the top.
```

See `skills/pi/SKILL.md` for the reusable Pi skill text.

---

## Claude Code

Onboard the project instructions and blocking pre-tool shell hook together:

```bash
mainframe onboard --host claude-code --project . --dry-run
mainframe onboard --host claude-code --project .
```

Use `mainframe deactivate claude-code --project . --enforce` to remove only
MAINFRAME-managed content. The lower-level `mainframe activate` command remains
available for advanced/manual flows. The reusable skill remains available
under `skills/claude-code/` for instruction-only setups.

For project-level instructions, keep or copy `CLAUDE.md` into the repository root. Minimum instruction:

````markdown
## Bash with MAINFRAME

When writing bash scripts, source MAINFRAME first:

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

Use MAINFRAME functions for JSON, validation, path safety, arrays, strings, HTTP, and git helpers. Initialize or renew project memory only with explicit `mainframe awm project ensure --project . --discover-root`; then start each task with the read-only `mainframe work "<current task>" --project . --tokens 1200`. Record only durable, non-secret state. Prefer `mainframe quickref <topic>` or `FUNCTIONS.json` for exact signatures.
````

Claude's interactive workspace-trust ceremony is separate from writing the
hook file. Start Claude with `mainframe launch claude-code` in the activated
project, accept the normal trust prompt, inspect the generated `PreToolUse` /
`Bash` hook, and run a controlled disposable canary. A configured
`.claude/settings.json` does not prove the launched process loaded it.
MAINFRAME's paired-control gate uses pinned Claude Code 2.1.220 in print mode,
where Claude disables workspace trust verification; that certificate records
the difference and does not replace the interactive trust step. See
[Native Host Execution Certification](NATIVE_HOST_CERTIFICATION.md).

## GitHub Copilot CLI and Gemini CLI

Both hosts have native blocking pre-tool events, so use explicit onboarding
instead of an instruction file alone:

```bash
mainframe onboard --host copilot --project .
mainframe onboard --host gemini --project .
```

The merge-safe adapters preserve unrelated JSON and install the canonical,
commit-stable `/bin/bash -p` bootstrap. It validates launch-time absolute
Bash/`jq`/gateway/safety-policy paths and their four-digest SHA-256 seal, and
does not look up `mainframe` on `PATH`. `jq` must resolve from a supported
system or package-manager installation. The default policy denies critical,
high, and medium-risk shell patterns. See the
[Agent Gateway guide](AGENT_GATEWAY.md) for verification, audit privacy, and
the non-sandbox threat boundary.

The seal detects straightforward sequential replacement after launch; a
user-owned install remains non-tamper-proof against a hostile same-UID process.
Use an OS/root-protected install or a separate user, container, or VM when
hostile race resistance is required.

Start either protected host through its launcher entry point:

```bash
mainframe launch copilot
mainframe launch gemini
```

Copilot CLI loads repository hooks only for a project it trusts. Start Copilot
with `mainframe launch copilot` in the activated repository, complete Copilot's
project-trust workflow, and run a controlled canary. A configured
`.github/hooks/mainframe.json` proves the local definition, not that the
launched Copilot process trusted or loaded it. The pinned offline paired-control
proof and Copilot's documented timeout fail-open boundary are covered in
[Native Host Execution Certification](NATIVE_HOST_CERTIFICATION.md).

---

## OpenAI Codex / Codex CLI

Onboard the repository instructions and Codex's project `PreToolUse` Bash hook
together. Existing `AGENTS.md` and `.codex/hooks.json` content is preserved:

```bash
mainframe onboard --host codex --project . --dry-run
mainframe onboard --host codex --project .
mainframe protect status codex --project .
```

Codex requires project-local command hooks to be reviewed and trusted against
their current hash. Start Codex with `mainframe launch codex` in the trusted
project, open `/hooks`, review the MAINFRAME definition, and run a controlled
canary. A `configured` protection status proves the exact file entry and local
dependencies only; it does not prove Codex trusted or loaded that entry.
Codex CLI 0.146.0's `--ignore-user-config` also suppresses project
`.codex/hooks.json`; do not use that flag when relying on MAINFRAME
enforcement. The pinned paired-control execution gate and its limits are
documented in [Native Host Execution Certification](NATIVE_HOST_CERTIFICATION.md).

Minimum `AGENTS.md` section:

````markdown
## Bash with MAINFRAME

For bash scripts, source MAINFRAME first:

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

Prefer MAINFRAME primitives over ad-hoc `jq`/`sed`/`awk` pipelines when writing portable agent scripts. Initialize or renew project memory only with explicit `mainframe awm project ensure --project . --discover-root`; then start each task with the read-only `mainframe work "<current task>" --project . --tokens 1200`. Record only durable, non-secret state.
````

See `skills/codex/AGENTS.md` for the fuller instruction-only source.

---

## Cursor

```bash
mkdir -p .cursor/rules
cp ~/.mainframe/skills/cursor/mainframe.mdc .cursor/rules/mainframe.mdc
```

Cursor will include the rule when editing the project. For global usage, add the same rule to your global Cursor rules directory.

---

## Aider

Project-local setup:

```bash
cp ~/.mainframe/skills/aider/CONVENTIONS.md ./CONVENTIONS.md
printf 'read: CONVENTIONS.md\n' >> .aider.conf.yml
```

Global setup:

```bash
printf 'read: ~/.mainframe/skills/aider/CONVENTIONS.md\n' >> ~/.aider.conf.yml
```

---

## OpenCode, Kimi CLI, legacy Google AI adapters, and other instruction-driven tools

Most CLI coding agents have a system prompt, project instructions file, or reusable skill/preamble field. Use the matching file when available:

```text
skills/opencode/SKILL.md
skills/kimi-cli/SKILL.md
skills/google-cli/SKILL.md
```

If the tool has no MAINFRAME-specific adapter yet, paste this generic instruction:

```text
When writing or reviewing bash, use MAINFRAME. Source it at the top of generated scripts with:
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

Prefer MAINFRAME functions for JSON, strings, arrays, validation, path safety, file operations, git helpers, retries, and atomic writes. After project memory has been explicitly initialized, start each task with the read-only `mainframe work "<current task>" --project . --tokens 1200`; store only durable non-secret state. Check exact function names with `mainframe quickref <topic>` or `FUNCTIONS.json`. Do not perform destructive, external, financial, or account-changing actions without explicit human approval.
```

---

## Custom agents and SDKs

For agent frameworks that you control:

1. Include `skills/vercel-ai-sdk/system-prompt.md` or this guide in the agent's system prompt.
2. Mount or install MAINFRAME at `~/.mainframe` inside the agent runtime/container.
3. Expose `MAINFRAME_ROOT` and add `bin/` to `PATH`.
4. If the agent exposes a pre-tool hook, use a fail-closed, absolute-path
   boundary equivalent to the supported hosts' privileged bootstrap. Direct
   `mainframe agent-hook` calls are diagnostic adapter checks, not that hardened
   boundary. Otherwise add a safety gate before high-risk commands.
5. If the agent runs long tasks, use `mainframe awm project ensure --project . --discover-root`,
   bounded context retrieval, and durable non-secret checkpoints/discoveries.

Example TypeScript prompt loading:

```ts
import { readFileSync } from "node:fs";

const mainframePrompt = readFileSync(
  `${process.env.HOME}/.mainframe/skills/vercel-ai-sdk/system-prompt.md`,
  "utf8"
);
```

---

## Agent safety conventions

- Prefer read-only discovery commands before mutating commands.
- Prefer `atomic_write`, `diff_replace`, `ensure_dir`, validation functions, and dry-run flags for file work.
- Do not ask agents to parse fragile free-form output when MAINFRAME can emit JSON/structured output.
- Treat `bash` as powerful and risky: explicit approval is required for destructive, irreversible, external account-changing, spending, publishing, deployment, or email actions.
- In multi-agent workflows, use bounded `mainframe awm project` context and
  handoffs instead of relying on conversation history inheritance or passing a
  shell-local SID between agents.

---

## Smoke test for any agent

After adding instructions, ask the agent:

```text
Write a portable bash script that creates a UUID, validates an email argument, and prints JSON without jq.
```

A MAINFRAME-aware answer should include:

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
validate_email "$email" || die 1 "Invalid email"
json_object "id=$(uuid)" "email=$email"
```

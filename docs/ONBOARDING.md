# Onboard a coding agent

`mainframe setup` is the recommended discovery-first path for connecting
MAINFRAME to a supported coding-agent host. Its hostless report is read-only;
the optional `--proof` form uses isolated private temporary state and removes
it before reporting success. With one explicit host, setup delegates to
`mainframe onboard`, which previews or merge-safely writes the host's project
instructions and native shell-policy hook, then checks the local gateway and
generated project configuration.

## Safe quickstart

First run the zero-residue mechanism proof, then read-only discovery from the
project you want the agent to use:

```bash
cd /path/to/your/project
mainframe setup --project . --proof
mainframe setup --project .
```

The proof creates a private mode-700 temporary directory, checks installation
health and one fixed reviewed pure invocation, checkpoints an isolated AWM
value, and retrieves the fixed key from a fresh Bash process. It also classifies
a destructive canary without executing it. On success it removes its temporary
AWM and broker state and leaves no project, user AWM, or audit state behind. It
does not run Pi or any coding agent, prove live host protection, or demonstrate
that an agent adopted or improved through MAINFRAME.

Without `--host`, setup reports Bash/zsh availability, supported host CLI and
project-marker signals, static protection, and existing project AWM state. It
never auto-selects a host and never changes project files, AWM, or audit state.
When a selected runtime is unavailable, discovery does not stop at diagnosis:
it prints offline status plus the exact managed-runtime preview/apply commands
for a certified Codex, Claude Code, or Copilot payload, including the offline
package-directory alternative and protected-setup follow-up. These are guidance
only; discovery performs none of them. Corrupt state and unsupported managed
routes fail closed without an install suggestion.

Choose one of the exact commands in that report to preview the proposed files,
then apply them interactively:

```bash
mainframe setup --project . --host claude-code --dry-run
mainframe setup --project . --host claude-code
```

Without `--dry-run`, onboarding asks for confirmation when attached to an
interactive terminal. A non-interactive invocation refuses to apply changes
unless the caller supplies `--yes` explicitly:

```bash
# Use only after reviewing the same inputs and dry-run output.
mainframe onboard --host claude-code --project . --yes
```

`--yes` skips the confirmation prompt; it does not weaken the policy or turn a
failed readiness check into success. The installer prints this onboarding path
but does not run it for you. `mainframe onboard --host <host> --project <dir>`
is the direct equivalent when the host is already known.

## Pi uses a dedicated package flow

Pi is included in hostless setup discovery, but it is deliberately separate
from the four project-hook hosts below. MAINFRAME integrates with Pi as a
user-scoped first-party package containing an extension and skill; the selected
project is used only to detect project-local `.pi` precedence collisions.

```bash
mainframe setup --project . --host pi
mainframe setup --project . --host pi --dry-run
mainframe setup --project . --host pi --yes
```

The first command is read-only status and guidance. Dry-run shows the exact
package activation and legacy-quarantine plan. `--yes` is the only setup form
that authorizes the user-settings transaction, and a human must run it from an
external terminal; the Pi extension blocks agents from confirming their own
lifecycle changes. `--runtime` does not apply to Pi, and combining `--dry-run`
with `--yes` is refused as ambiguous. The equivalent direct commands are:

```bash
mainframe pi status
mainframe pi doctor
mainframe pi install --dry-run
mainframe pi install --yes
```

The flow never executes the discovered Pi CLI and never rewrites project-local
Pi files. It records a private receipt so path aliases, upgrades, removal, and
Homebrew's stable `opt` source converge on one package entry. A project Pi
package entry or standalone Mainframe resource blocks user-level mutation
because it can override that entry. After a changed install, use `/reload` in
Pi or restart it, then run `/mainframe doctor` to establish runtime loading.
The stable Homebrew source remains mutable by the package manager after this
transaction. Every principal authorized to write the selected Homebrew prefix
is inside the trusted package-manager boundary and can replace package code Pi
later loads; use the private
release-archive installation when that shared-prefix trust is unacceptable.
External `mainframe pi doctor` remains offline and read-only: it diagnoses the
exact Pi package/version/platform and disk state, but only the command running
inside Pi can return `READY`. Before each agent turn, Pi shows the same
fail-closed state in its footer (`MF READY`, `MF SETUP_REQUIRED`,
`MF RELOAD_REQUIRED`, `MF UNVERIFIED`, or `MF BLOCKED`); `/mainframe status`
and `/mainframe doctor` refresh it without creating persistent badge state.

The changed install prints an exact private `backup_id` and
`restore_available=true|false`. If the first live doctor fails and restore is
available, use that ID—never a path or `latest`—to preview and confirm
byte-for-byte recovery of the supported pre-install migration snapshot:

```bash
mainframe pi restore --backup-id .mainframe-pi-backup-YYYYMMDDTHHMMSSZ.A1b2C3 --dry-run
mainframe pi restore --backup-id .mainframe-pi-backup-YYYYMMDDTHHMMSSZ.A1b2C3 --yes
```

The restore fails closed if the private backup, current package settings,
manager receipt, or project precedence changed. It does not execute or stop Pi;
restart Pi after a changed restore.

Before uninstalling MAINFRAME, use a human terminal to preview and then confirm
`mainframe pi remove`. The transactional removal detaches only the managed
package source and receipt, preserves unrelated settings and migration backups,
and requires the same Pi reload or restart.

## Supported hosts

Use exactly one of these values with `--host`:

| Host | Value | Managed project integration |
|---|---|---|
| OpenAI Codex / Codex CLI | `codex` | `AGENTS.md` and `.codex/hooks.json` |
| Claude Code | `claude-code` | `CLAUDE.md` and `.claude/settings.json` |
| GitHub Copilot CLI | `copilot` | `.github/copilot-instructions.md` and `.github/hooks/mainframe.json` |
| Gemini CLI | `gemini` | `GEMINI.md` and `.gemini/settings.json` |

Onboarding preserves unrelated content in existing instruction and settings
files. The generated hook stores a commit-stable `/bin/bash -p` bootstrap; it
does not call `mainframe` or resolve the gateway from `PATH`. At launch time,
MAINFRAME supplies exact absolute Bash, supported system/package-manager `jq`,
installed-gateway, and installed-safety-policy paths plus their four-digest
SHA-256 seal.
After consent, onboarding also creates or resumes a private AWM session mapped
to the canonical physical project. A dry run or declined/refused consent
creates no AWM mapping or session.

## Inspect or install the host runtime source

Before launch, inspect the managed and system candidates without changing the
machine:

```bash
mainframe host status
mainframe host status claude-code --json
```

Status is offline and read-only. It does not acquire a host, run npm, execute the
candidate, or change global packages, `PATH`, profiles, project files, or host
configuration. When selection is not ready, its human report gives the same
state-aware next step used by guided setup; JSON remains a closed status record
for automation. The reserved managed boundary is
`${XDG_DATA_HOME:-$HOME/.local/share}/mainframe/host-payloads`.

On an advertised tuple, Codex, Claude Code, and Copilot can instead use an
optional managed runtime acquired from the exact locked registry packages:

```bash
mainframe host install claude-code --download --dry-run
mainframe host install claude-code --download --yes
```

The network path is never implicit: only `--download` permits a connection,
and only to the exact SRI-pinned HTTPS URLs on `registry.npmjs.org`. Download
dry-run performs the actual anonymous acquisition and complete staged-runtime
authentication in a private ephemeral workspace, then removes it without
publishing a generation.

For a separately reviewed package source, use the offline alternative:

```bash
mainframe host install claude-code --package-dir /path/to/pinned-tarballs --dry-run
mainframe host install claude-code --package-dir /path/to/pinned-tarballs --yes
```

The contract is
`mainframe host install HOST (--download | --package-dir DIR) [--dry-run | --yes] [--json]`.
The sources are mutually exclusive, and the local directory must supply every
archive under its exact locked basename. Both routes verify SHA-512 SRI and
package identity; the extractor re-verifies SRI from the same descriptor used
for bounded extraction, authenticates the full tree and native entry point,
and publishes one receipt-backed generation only with `--yes`. Acquisition
does not follow redirects, honor proxy overrides, send registry credentials,
invoke npm, run package lifecycle scripts, or execute vendor code. `--json`
never prompts. An actionable request requires `--dry-run` or `--yes`, while a
safe no-op, refusal, or validation error may return first. Python 3.10+ is
required for managed install/remove/restore helpers, but not for status or launch. That interpreter
and its standard library are a local-user trust dependency; MAINFRAME validates
the interpreter, not the complete Python installation. Gemini is recognized
but its managed install remains gated. Existing corrupt targets are refused.

Install, remove, and restore never mutate `PATH`, profiles, global packages,
project files, or host configuration. There is no managed-host update or
quarantine-prune command. The receipt's
`package_set_sha256` commits to the exact selected lock records, and the bundle
ID binds both the MAINFRAME version and that exact package set.

Default `auto` resolution prefers an exact valid managed payload and uses an
authenticated system CLI only when managed execution is absent or unsupported.
If the deterministic expected path exists but its closed receipt or complete
file tree is invalid, launch fails closed instead of silently falling back. An
operator can request the existing system installation explicitly with
`--runtime system` on status, setup, or launch. A system direct-native route is
authenticated by exact executable digest, not a full-tree claim; a system
wrapper receives its integration's checks. Codex, Claude Code, and Copilot
wrapper routes report an authenticated runtime tree with an unpinned-Node
boundary; Gemini reports incomplete closure with an unpinned-Node boundary.
Status reports the boundary of the source actually selected. Managed Gemini is
not selectable until its full dependency closure and an exact Node.js runtime
are pinned.
See [Managed host payloads](MANAGED_HOST_PAYLOADS.md) for the detailed contract.

## Launch the onboarded host

After onboarding, use MAINFRAME as the daily front door for the host:

```bash
mainframe launch claude-code --project . --dry-run
mainframe launch claude-code --project .
```

The project defaults to the current directory, so the memorable form from an
onboarded project is `mainframe launch claude-code`. Before starting anything,
the launcher read-only verifies the current managed instructions, an existing
private AWM project mapping, the exact native shell hook and its dependencies,
and an absolute host executable. It authenticates the host's exact launcher,
runtime, and package-tree bytes against the native-host certification manifest
without executing an untrusted PATH candidate during discovery. This prevents
a legacy, patched, or merely same-named CLI from passing static preflight while
ignoring the current project integration. A failed check launches nothing and
prints the exact recovery action. `--dry-run` performs the same checks without
starting the host. The privileged hook bootstrap uses the validated absolute
Bash, `jq`, gateway, and safety-policy paths plus their seal with a fixed system
`PATH`. For npm wrappers, package-tree hashing uses the exact non-project
Node.js executable from a supported system, package-manager, or version-manager
layout. Launch hashes and rechecks Node plus `hash-package-tree.mjs` around
authentication and before exec. This rejects arbitrary PATH shims, but does
not make a user-managed Node installation an external trust anchor. Python is
not a status or runtime-launch dependency; Python 3.10+ is confined to the
managed install/remove/restore helpers described above. Before every hook call, the
privileged bootstrap hashes the bound Bash, `jq`, gateway, and safety-policy
files and compares them with the launch seal.

Starting the native host directly does not supply those four paths and the
seal. If the configured hook is invoked, it fails closed with the host's
blocking code. Use `mainframe launch` for every session intended to be
protected.

The launcher sets the gateway policy to `medium` unless `--policy high` or
`--policy critical` is explicitly selected. Those narrower tiers block fewer
operations. The first launch contract intentionally rejects native host
arguments, including arguments after `--`, so a flag cannot silently suppress
project hooks. Start the interactive host, then enter the task there.

Successful launch preflight still reports host runtime loading as
**UNVERIFIED**. Artifact identity and static configuration cannot replace the
host's native project-trust or hook-review ceremony and cannot prove the host
delivered a tool request. Finish the native checks below before describing the
current session as protected.

## The AWM protocol agents receive

Every supported host receives the same process-safe Agent Working Memory
protocol. It uses project-scoped CLI commands because coding-agent shell calls
may run in separate processes; no shell-local session variable is required.

Project onboarding creates or resumes the private mapping under the operator's
consent. At the start of each task, the managed instructions use its bounded
read path:

```bash
mainframe awm project ensure --project . --discover-root
mainframe work "<current task>" --project . --tokens 1200 --format prompt
```

Only the explicit `ensure` may initialize or renew the mapping. `work` is the
repeat-use read path: it refuses an unmapped or unsafe project, discovers the
canonical project root, returns memory inside an untrusted-data envelope, and
prints write templates without executing them. Its JSON format gives agent
hosts the same bounded contract without parsing presentation text.

During work, the agent records only durable decisions, high-signal findings,
and meaningful progress milestones:

```bash
mainframe awm project checkpoint --project . --discover-root current_phase "<concise status>" --importance high
mainframe awm project discovery --project . --discover-root "<high-signal finding>" --importance high
mainframe awm project progress --project . --discover-root implementation 3/5 "<concise status>"
```

Before context compaction or delegation, the agent prepares a bounded handoff:

```bash
mainframe awm project handoff prepare --project . --discover-root next-agent --tokens 1200 --format prompt
```

On completion, it checkpoints a concise outcome. It can request a bounded
recap with `mainframe awm project summary --project . --discover-root --tokens 800`.

`--discover-root` prevents memory fragmentation when an agent runs commands
from nested directories. It walks upward to the nearest complete managed block
or valid private mapping without crossing the current Git worktree, then uses
the worktree root, with exact-directory fallback outside Git. A preserved
mapping therefore remains authoritative after managed instruction removal.
Omit the flag for an intentionally distinct explicit subproject.

AWM is durable local state, not a secret store. The managed instructions
explicitly forbid credentials, tokens, secrets, raw sensitive payloads, and
routine command chatter. Store concise decisions and results instead.

## What success proves

A successful `mainframe setup --project . --proof` proves only the isolated
first-run mechanisms described above: installation health, one reviewed pure
broker invocation, fresh-process AWM retrieval, classifier denial, and cleanup.
It does not prove onboarding, a loaded Pi package, live host enforcement, or
agent adoption.

A successful onboarding result proves static, project-scoped readiness at the
time the check ran: the expected managed project entries are present, the local
gateway dependencies can be resolved as absolute non-project paths, `jq` is
from a supported system or package-manager installation, the
generated hook contains the exact privileged bootstrap, and the private project
AWM session can be resolved and inspected across separate CLI processes. The
generated hook has no MAINFRAME-on-`PATH` dependency.

It does **not** prove that an already-running host process reloaded the project,
that the host trusts the repository or current hook hash, or that a native
shell-tool request reached the gateway. Treat host runtime loading as
**UNVERIFIED** until you complete the host-side checks below.

You can repeat the static check without changing files:

```bash
mainframe protect status claude-code --project .
```

## Finish in the native host

After onboarding:

1. Start the host in the onboarded project with `mainframe launch <host>`.
2. Complete its normal project-trust or hook-review flow. In Codex, open
   `/hooks` and review the exact MAINFRAME hook and current hash. In Claude Code
   and Copilot CLI, complete the normal workspace/project trust flow. For every
   host, inspect its native hook UI or diagnostics when available.
3. In a disposable project, run a controlled native deny canary that targets
   only a disposable sentinel. Confirm that the host reports the denial, the
   sentinel remains untouched, and MAINFRAME's private audit records the deny.

The direct `mainframe agent-hook` probes in the
[Agent Gateway guide](AGENT_GATEWAY.md) are useful diagnostic adapter checks
because the gateway classifies their embedded command without executing it.
They do not exercise the privileged bootstrap or launch-time bindings and do
not replace the native-host canary above.

## Inspect changes and roll back

Project integration files may be committed, so inspect the working tree after
onboarding:

```bash
git status --short
git diff
```

To remove only MAINFRAME-managed instructions and the generated host hook:

```bash
mainframe deactivate claude-code --project . --enforce --dry-run
mainframe deactivate claude-code --project . --enforce
```

Replace `claude-code` with the host value you onboarded. Deactivation is
project-scoped and leaves unrelated host settings intact. A subsequent
`mainframe protect status claude-code --project .` should report that static
protection is no longer ready and exit nonzero. Deactivation deliberately
leaves private AWM history intact. Inspect that history before deciding whether
to retain it:

```bash
mainframe awm project status --project . --discover-root
```

Project deactivation is separate from removing an optional managed host
runtime. To take the current exact runtime generation out of active resolution,
preview and confirm a recoverable quarantine move:

```bash
mainframe host remove claude-code --dry-run
mainframe host remove claude-code --yes
```

Before `host remove --yes`, stop new launches and any agent process that may
still need the managed executable. The authenticated quarantine move is
identity-safe, not an availability guarantee during concurrent launch/removal,
and it does not terminate an already-running process. `--yes` authorizes the
move only; it does not verify that agents are stopped.

Remove first authenticates the generation, then atomically moves only that
generation into retained private same-filesystem quarantine using the reviewed
Python 3.10+ descriptor-safe helper. It refuses a corrupt target, does not purge
bytes, and leaves sibling or stale generations untouched.

The remove result includes a generated `removed.<18-hex>` ID. To return that
exact current generation to active resolution, first preview and then confirm
the offline restore:

```bash
mainframe host restore claude-code --quarantine-id removed.0123456789abcdef01 --dry-run
mainframe host restore claude-code --quarantine-id removed.0123456789abcdef01 --yes
```

Restore re-authenticates the entire quarantined payload, accepts no path or
implicit newest entry, and refuses to overwrite any present active target. A
successful restore preserves the generation identity and leaves its quarantine
slot empty for inspection. Run `mainframe host status claude-code --runtime
managed` afterward before resuming launches.

## Security boundary

MAINFRAME is a validation and pre-tool policy layer, not an operating-system
sandbox. It cannot constrain direct terminal commands, unconfigured tools, a
host that does not deliver its hook, or other processes running as your user.
AWM directories and files use private modes, but another process running as the
same operating-system user may still access them. The launch seal detects
straightforward sequential byte replacement, but a user-owned installation is
not tamper-proof against a hostile process with the same UID. For hostile race
resistance, use an OS/root-protected install or a container, VM, or dedicated
low-privilege account. See [SECURITY.md](../SECURITY.md) and the
[Agent Gateway guide](AGENT_GATEWAY.md) for the full boundary.

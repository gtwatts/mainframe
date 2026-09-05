# MAINFRAME

**Help coding agents work more safely and reliably in your native shell.**

MAINFRAME is an open-source toolkit for coding agents on macOS and Linux.
It brings reviewed Bash tools, policy checks on supported command routes,
and durable project memory to the shell you already use. The goal is useful
work with fewer mistakes, repeated setup steps, and interruptions.

Use it to give an agent a structured tool call, preserve decisions for a fresh
session, or inspect whether a supported integration is actually ready. Over
time, we want MAINFRAME to become the go-to control plane for different coding
agents: a shared place to manage permissions, context, execution, and evidence.

Pi is the deepest current integration. Other agents can use the shell, MCP,
memory, and language-binding interfaces; native hook coverage varies by exact
host and version. See the [integration table](#works-with-your-coding-agent)
before choosing a route.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Tests](https://img.shields.io/github/actions/workflow/status/gtwatts/mainframe/test.yml?branch=main&label=tests)](https://github.com/gtwatts/mainframe/actions/workflows/test.yml)
[![Bash 4.4+](https://img.shields.io/badge/bash-4.4%2B-green.svg)](INSTALL.md#requirements)

**Start here:** [Install](#quick-install) · [First agent session](docs/AGENT_ONBOARDING.md) ·
[Try a reviewed tool](#custom-agents) · [Preserve project memory](#agent-working-memory) ·
[Contribute](CONTRIBUTING.md)

**Current status:** experimental, unpublished `10.2.0` source candidate.
The verified release installer is publication-gated. macOS and Linux, each
with Bash or zsh as the calling shell, are the priority support targets;
the native library engine requires **Bash 4.4+**. Calling the CLI from zsh is
different from sourcing Bash libraries into zsh. Check the
[integration evidence](docs/INTEGRATION_MATRIX.md) for exact tested cells.

## Why MAINFRAME?

| Coding-agent pain | MAINFRAME answer | Practical benefit |
|---|---|---|
| An agent can run a destructive shell command at machine speed | A deterministic policy gate classifies configured shell routes before execution | Matching patterns on covered routes can be denied before execution; indirect effects still need care |
| Long work disappears when context is compacted or a session restarts | Agent Working Memory stores explicit checkpoints, discoveries, progress, and handoffs | Fresh agents resume from durable local state instead of rebuilding context |
| Agents improvise brittle shell one-liners | A narrow set of 26 reviewed stable-core invocation contracts, backed by a searchable Bash library | Structured inputs, outputs, and errors that can be inspected and tested |
| Package or lifecycle changes can be hard to notice | Human-confirmed Pi and managed-host lifecycle flows | The agent cannot silently authorize its own MAINFRAME installation or removal |
| “Installed” does not prove the running agent is protected | Doctor commands, compatibility manifests, receipts, and the Pi `MF ...` badge | Readiness is visible and fails closed instead of being assumed |

MAINFRAME is designed for honest-but-fallible agents. It is **not** an OS
sandbox, malware boundary, or protection against a hostile process already
running as your user. It does not intercept every action an agent can take or
guarantee recovery from every effect. Keep your agent's native controls and
any isolation your work requires. See the [security boundary](SECURITY.md).

Open source makes these protections inspectable and gives users and outside
contributors a way to test, challenge, and improve them. Our
[growth plan](docs/OPEN_SOURCE_GROWTH_PLAN.md) measures repeat use, successful
tasks, recovery, and maintainer effort before stars or downloads.

## Works with your coding agent

MAINFRAME is agent-agnostic. The integration depth depends on the host, but
the core value is shared: safer shell execution, durable memory, structured
tools, and readiness evidence.

| Agent or host | Current integration |
|---|---|
| Pi | First-party package, skill, slash command, protected Bash wrapper, seven guarded tools, AWM, and transactional lifecycle management; live evidence is currently limited to the pinned Darwin arm64 cell |
| OpenAI Codex, Claude Code, GitHub Copilot CLI, Gemini CLI | Generated project instructions and registry-bound shell-hook configuration; current evidence is platform-specific (`configured` or `enforced`), never implied by the instruction file alone |
| Cursor, Aider, OpenCode, Kimi, JetBrains, Junie | Generated project instructions only; no runtime interception claim |
| Custom or future agents | Bash libraries, AWM CLI, stable-core broker, MCP server, or Node.js/Python bindings |

If an agent can read project instructions and ask for shell work, it can use
MAINFRAME's memory and tool surfaces. Native pre-execution enforcement is
available only in the exact host/platform cells recorded in
[`config/host-capabilities.json`](config/host-capabilities.json). Unsupported
routes remain honest inspection or helper surfaces rather than claiming
interception.

## How MAINFRAME works

The reviewed tool interface and native shell hooks are different routes:

```mermaid
flowchart LR
    A[Coding agent] -->|reviewed tool via MCP or invoke| B{Contract and policy checks}
    B -->|valid and authorized| T[Fixed Bash broker]
    B -->|rejected| D[Structured refusal]
    A -->|shell request on configured host| G{Host shell-policy hook}
    G -->|allowed| H[Host executes command]
    G -->|denied| X[Host must honor denial]
    A <--> M[Project memory and handoffs]
```

The broker authorizes specific typed calls. Host hooks check covered shell
requests for configured patterns; they require separate live-host verification.
A command with no matching pattern is not proven safe. Direct Bash-library use
has its own trusted-caller contract and does not acquire broker authorization.

Confirmation is specific to the interface: Pi and lifecycle flows have their
own human-confirmation procedures. The coding preview's `edit`, `test`, and
`build` routes currently stop at `awaiting_approval`; a general production
approver and action runner are not bundled. See the
[preview contract](docs/CONTROL_PLANE_PREVIEW.md) and
[host gateway evidence](docs/AGENT_GATEWAY.md).

Four pieces work together:

1. **Gate:** canonical Bash policy rules classify supported shell routes and
   deny configured destructive patterns before execution.
2. **Toolbox:** the function registry, quick references, and stable-core
   broker give agents structured tools instead of improvised shell glue.
3. **Memory:** AWM preserves high-signal project state outside the chat window
   and creates bounded handoffs for future or delegated agents.
4. **Proof:** doctor, setup, compatibility manifests, broker receipts, and
   the configured gateway's private audit records support checks of each
   integration. Live verification is still required.

### Durable control-plane preview

The 10.2.0 source candidate includes a structured local kernel for durable
runs, tool calls, exact one-time approvals, and correlated evidence:

```bash
install -d -m 700 "$PWD/.mainframe"
mainframe control-plane --ledger "$PWD/.mainframe/control-plane.jsonl" show
```

The low-level `control-plane` namespace retains an injected read-only tracer
and one approval-bound disposable-workspace writer for explicit kernel testing.
The public source-candidate routes add four reviewed verticals on top of that
kernel:

- all 26 stable-core `mainframe invoke` contracts create correlated
  Run/ToolCall/PolicyDecision/Evidence records before the fixed Bash broker
  executes;
- `mainframe code read` and `search` are workspace-confined, while `edit`,
  `test`, and `build` stop at `awaiting_approval` because no production
  approval authority or action runner is bundled;
- all six `mainframe awm project` mutations and all six project read-plane
  operations use metadata-only durable evidence plus bounded transient result
  channels; and
- the MCP, Pi, Node.js, and Python reviewed adapters expose kernel-generated
  identities and have no legacy retry path for those calls.

Unreviewed registry exports, general network/process execution, native
non-shell host operations, and ambient same-user tampering are not promoted
through this preview. See the
[control-plane preview contract](docs/CONTROL_PLANE_PREVIEW.md) for the exact
state, filesystem, and crash boundaries.

Read [Why MAINFRAME](docs/COMPARISON.md) for the detailed comparison with a
raw shell, agent-native controls, and operating-system isolation—including the
claims MAINFRAME deliberately does not make.

## Quick install

The verified release installer is still publication-gated, so the current
public install path is a reviewed source checkout. The repository's `10.2.0`
work is an unpublished candidate; pin and review the commit you install.

### macOS

```bash
brew install bash jq git
git clone https://github.com/gtwatts/mainframe.git "$HOME/.mainframe"
/opt/homebrew/bin/bash --noprofile --norc -p \
  "$HOME/.mainframe/install.sh"  # Apple Silicon
# Intel Homebrew uses: /usr/local/bin/bash --noprofile --norc -p "$HOME/.mainframe/install.sh"

export MAINFRAME_ROOT="$HOME/.mainframe"
export PATH="$HOME/.local/bin:$PATH"
mainframe doctor
```

### Linux

```bash
# Debian/Ubuntu example; install Bash 4.4+, jq, and Git with your package manager.
sudo apt-get install bash jq git
git clone https://github.com/gtwatts/mainframe.git "$HOME/.mainframe"
/bin/bash --noprofile --norc -p "$HOME/.mainframe/install.sh"

export MAINFRAME_ROOT="$HOME/.mainframe"
export PATH="$HOME/.local/bin:$PATH"
mainframe doctor
```

The installer links `mainframe` into `~/.local/bin` and can add the required
shell-profile entries. Open a new terminal if `mainframe` is not found.

### Inspect local readiness

```bash
cd /path/to/your/project
mainframe version
mainframe doctor
mainframe setup --project .
mainframe setup --project . --proof
```

The read-only setup report shows shell, Pi, supported-host, protection, and
AWM state without changing project or agent configuration. `--proof` checks
local reviewed invocation and fresh-process retrieval of temporary memory,
then removes its private test state on success. It does not prove live host
protection or current project-memory onboarding. A task sandbox may restrict
the subprocess operations used by the proof; distinguish those failures from
native-host results. See the
[agent onboarding guide](docs/AGENT_ONBOARDING.md) and
[readiness checklist](docs/AGENT_READINESS_CHECKLIST.md).

### Pi quick setup

Pi has the deepest current integration. Keep the first pass read-only:

```bash
mainframe pi doctor
mainframe pi install --dry-run
```

After reviewing the preview, a human runs activation in an external terminal:

```bash
mainframe pi install --yes
```

Then reload or restart Pi and run the in-process proof:

```text
/mainframe doctor
```

The current certified Pi target is `@earendil-works/pi-coding-agent` `0.84.2`
on `Darwin-arm64-none`; unknown package, version, or platform combinations
fail closed as unverified. External `mainframe pi doctor` cannot inspect a
running Pi process, so only `/mainframe doctor` can report live `READY`.

### Codex, Claude Code, Copilot, and Gemini quick setup

Use the same discovery-first pattern for the other supported project-hook
hosts:

```bash
cd /path/to/your/project
mainframe setup --project .
mainframe setup --project . --host codex --dry-run
mainframe setup --project . --host codex
mainframe launch codex --project .
```

Replace `codex` with `claude-code`, `copilot`, or `gemini` as appropriate.
The setup report never auto-selects a host or changes files. Onboarding writes
only after an explicit human-reviewed apply, and `launch` performs the
preflight before starting the protected host session.

### Custom agents

Use the pieces directly when there is no native host adapter yet:

```bash
mainframe work "continue the current task" --project .
mainframe search "validate a safe path"
mainframe invoke mf:data:json:json_get \
  --input-json '{"json":"{\"name\":\"Ada\"}","key":"name"}'
```

Custom runtimes can also use the MCP server, Node.js/Python bindings, or the
Bash libraries directly. Unsupported hosts do not get an interception claim;
they get MAINFRAME's memory, toolbox, policy, and evidence surfaces.

## Install and prove it works

### Requirements

- Bash 4.4 or newer
- `jq`
- For the verified bootstrap: `curl`, `tar`, and `sha256sum`, `shasum`, or
  `openssl`
- Git only for a source-checkout installation
- Node.js when `mainframe launch` must authenticate or execute an npm-wrapper
  host; the launcher accepts only an exact executable outside the project
- A protected fixed-location Python 3.9+ standard-library runtime for the
  durable control-plane CLI and Pi diagnosis/lifecycle. The reviewed
  managed-host install, remove, and restore helpers require Python 3.10 or
  newer.

macOS ships an older system Bash. Install the current Bash and gateway JSON
dependency with `brew install bash jq`, then use that Bash executable for
installation and scripts.

### Current public install status

The verified release flow below is the target distribution contract, but it is
not live yet. The current public `v10.1.0` release is mutable and does not
publish the required versioned runtime archive and checksum sidecar, so
`get-mainframe.sh --latest` intentionally fails closed, as does the equivalent
selector-free invocation. Until a qualifying immutable release is published,
use the [source-checkout install](#source-checkout-install) below and review the
commit you install. The `10.2.0` work described in this repository is an
unpublished candidate.

### Verified release install (publication gated)

After a qualifying release is published, the shortest verified path will be to
download and inspect the current bootstrap, then ask it to resolve GitHub's
latest immutable stable release exactly once:

```bash
curl -fsSLo /tmp/get-mainframe.sh \
  "https://raw.githubusercontent.com/gtwatts/mainframe/main/get-mainframe.sh"
less /tmp/get-mainframe.sh
bash /tmp/get-mainframe.sh
# Equivalent explicit selector: bash /tmp/get-mainframe.sh --latest
```

With no selector, the bootstrap uses exactly the `--latest` path. That resolver
accepts only a published, non-prerelease `vMAJOR.MINOR.PATCH` release whose
GitHub metadata is immutable. It requires one exact uploaded runtime archive
and checksum sidecar at their canonical URLs, binds both downloads to GitHub's
SHA-256 asset digests, and requires the sidecar to name that same archive
digest. It then uses the normal exact-version installation path and prints the
resolved version for an exact retry.

If the public latest release is mutable or lacks either required runtime asset,
the selector-free and explicit `--latest` forms fail closed and never fall back
to the legacy mutable installer.

For the reproducible trust path, choose a reviewed stable release and download
the bootstrap from that same immutable version tag:

```bash
release_version=X.Y.Z
curl -fsSLo /tmp/get-mainframe.sh \
  "https://raw.githubusercontent.com/gtwatts/mainframe/v${release_version}/get-mainframe.sh"
less /tmp/get-mainframe.sh
bash /tmp/get-mainframe.sh --release-version "$release_version"
```

The convenience bootstrap above comes from mutable `main`; resolving an
immutable release does not make that initially downloaded script immutable.
Use the pinned-tag form when exact bootstrap provenance matters.

Before 10.2, running the bootstrap without a release selector entered a mutable
source-install compatibility path. That path now requires the explicit
`--legacy-source` selector and still prints an unverified-source warning. It is
retained for existing reviewed workflows, not recommended as the normal install
path. `get-mainframe.sh -h` and `--help` are local and perform no download.

The bootstrap requires one lowercase SHA-256 record for the exact asset,
verifies the archive before inspecting or extracting it, and rejects absolute
paths, traversal, duplicate members, links, special entries, and files omitted
from the archive's complete inner `SHA256SUMS` inventory. It installs only into
a missing or empty private target. A machine-local receipt is written only
after the installed version, exact CLI link, complete inventory, and
`mainframe doctor` all pass. This path does not clone or update a Git
repository.

Receipt-backed installs have an explicit, dry-runnable upgrade path:

```bash
mainframe upgrade --version X.Y.Z --dry-run
# Stop agents using this installation before the actual cutover.
mainframe upgrade --version X.Y.Z --confirm-agents-stopped
```

The previous installation remains in a private sibling transaction directory
for recovery. See [INSTALL.md](INSTALL.md) for the full upgrade, recovery,
custom-location, and compatibility boundaries.

### Source-checkout install

```bash
git clone https://github.com/gtwatts/mainframe.git "$HOME/.mainframe"
# Linux, with Bash 4.4+ at the system path:
/bin/bash --noprofile --norc -p "$HOME/.mainframe/install.sh"
# macOS after `brew install bash jq` (choose the path for your Homebrew):
/opt/homebrew/bin/bash --noprofile --norc -p \
  "$HOME/.mainframe/install.sh"  # Apple Silicon
# /usr/local/bin/bash --noprofile --norc -p \
#   "$HOME/.mainframe/install.sh"  # Intel
export MAINFRAME_ROOT="$HOME/.mainframe"
export PATH="$HOME/.local/bin:$PATH"

mainframe version
mainframe doctor
```

The installer links the full CLI into `~/.local/bin`. If that directory is not
already on `PATH`, it also adds the required shell-profile entry. After an
install, upgrade, or manually reviewed candidate switch, verify that both shell
profiles point at the same runtime as the CLI selected by `PATH`:

```bash
mainframe shell status --shell all
mainframe shell repair --shell all --dry-run
# Apply only after reviewing the exact profile list:
mainframe shell repair --shell all --yes
```

`mainframe shell status` compares the selected CLI, inherited
`MAINFRAME_ROOT`, Bash login/non-login profiles, and zsh profile. A stale
managed block keeps `mainframe doctor` and `mainframe setup` non-ready instead
of silently mixing two installations. Repair rewrites only MAINFRAME's exact
managed blocks, preserves other profile content and modes, and makes a
timestamped backup of every existing profile it changes. For zsh, an inherited
absolute, existing, user-owned `ZDOTDIR` selects that directory's `.zshrc`;
unsafe or ambiguous values fail closed. When `.zshenv` sets `ZDOTDIR` without
exporting it, pass the already-reviewed value explicitly with
`--zdotdir /absolute/path`; MAINFRAME never sources startup code to discover it.

### Make MAINFRAME native in Pi

MAINFRAME 10.2 includes a first-party Pi package rather than requiring a
separately maintained extension. After Pi has created its user agent directory,
inspect the exact Pi package/version/platform evidence and preview the
integration before activating it:

```bash
mainframe pi status
mainframe pi doctor
mainframe pi install --dry-run
mainframe pi install --yes
```

Run the real `--yes` command yourself in an external terminal after reviewing
the preview. The Pi extension returns preview commands only and blocks an agent
from authorizing its own MAINFRAME lifecycle change. Install records the
canonical package source in a private manager receipt, preserves unrelated Pi
settings, replaces filtered package entries that would hide MAINFRAME's
resources, and moves recognized legacy `mainframe.ts` and `skills/mainframe`
copies into a private timestamped backup. A later source or Homebrew upgrade
replaces the exact previously receipted package path instead of accumulating
stale roots. Every changed install prints that backup's exact `backup_id` and
`restore_available=true|false`. Exact `mainframe pi restore` recovery is offered
only when the transaction migrated both legacy resources from an existing
settings file and replaced no prior manager receipt.

Project-local `.pi/settings.json` package entries and legacy project resources
take precedence in Pi, so user-level install and removal report them and refuse
to mutate either scope. Resolve that project configuration separately. After a
changed install, run `/reload` in Pi (or restart Pi), then run `/mainframe
doctor`. External `mainframe pi doctor` is offline and never starts Pi: it can
report `SETUP_REQUIRED`, `PROJECT_OVERRIDE`, `LIMITED`,
`COMPATIBILITY_UNVERIFIED`, or `ACTIVATION_UNVERIFIED`, but only the in-process
doctor may report `READY`. The extension also refreshes a concise `MF ...`
footer badge before every agent turn and whenever `/mainframe status` or
`/mainframe doctor` runs, so a stale, missing, or failed runtime stays visible.
If that first live doctor fails and install printed `restore_available=true`,
validate and preview recovery using the exact ID printed by install, then
explicitly restore the byte-for-byte pre-install snapshot:

```bash
mainframe pi restore --backup-id .mainframe-pi-backup-YYYYMMDDTHHMMSSZ.A1b2C3 --dry-run
mainframe pi restore --backup-id .mainframe-pi-backup-YYYYMMDDTHHMMSSZ.A1b2C3 --yes
```

Restore refuses a path, `latest`, an incomplete backup, project overrides, or
settings/receipt drift. It preserves the validated private backup and never starts
or stops Pi; restart Pi after a changed restore.

Detach the package before uninstalling MAINFRAME or removing a Homebrew
installation:

```bash
mainframe pi remove --dry-run
mainframe pi remove --yes
```

Removal is transactional and removes only Mainframe-managed package entries
and its private receipt. It preserves unrelated settings and all migration
backups. Run the confirmed command yourself, then reload or restart Pi.
`mainframe uninstall` fails closed if its Pi lifecycle payload is incomplete or
the package is still attached. Homebrew Formulae have no uninstall-preflight
hook, so a direct `brew uninstall` can bypass that check and leave Pi pointing
at a removed `opt_libexec` path. Use the formula's printed safe chain: preview
the detach, then run `mainframe pi remove --yes && brew uninstall
gtwatts/mainframe/mainframe` yourself.

Pi packages run with the user's machine permissions. MAINFRAME adds policy,
explicit approval points, safer primitives, and private audit evidence; it is
not an OS sandbox or a boundary against another hostile process running as the
same user. Review the package source before activation.

Homebrew Pi activation records the formula's stable `opt_libexec` package
source so upgrades can be detected and reconciled. That alias is deliberately
mutable by Homebrew: every principal authorized to write the selected Homebrew
prefix is inside the trusted package-manager boundary and could replace code Pi
loads later. Use an owner-private release-archive install instead when a shared
Homebrew prefix is not an acceptable trust boundary.

### Onboard a coding agent

Start with read-only discovery. It reports Bash/zsh availability, Pi CLI and
package state without executing Pi, supported project-hook agent CLIs and
markers, existing static protection, and project AWM status without selecting
a host or changing files or state:

```bash
cd /path/to/your/project
mainframe setup --project .
mainframe host status
```

`mainframe host status [HOST] [--runtime auto|managed|system] [--json]` reports
the deterministic managed and system runtime candidates without installing or
executing either one. Status stays offline and read-only. Human output includes
state-aware recovery commands when selection is not ready: eligible missing
managed runtimes receive both online and offline preview/apply paths; corrupt
state receives diagnosis only; Gemini and unsupported platforms are never
offered an impossible managed install.

On an advertised platform, an optional private managed runtime for Codex,
Claude Code, or Copilot can be acquired and installed explicitly:

```bash
mainframe host install claude-code --download --dry-run
mainframe host install claude-code --download --yes
```

`--download` is the network-consent boundary. It contacts only the exact
SHA-512-SRI-pinned HTTPS package URLs on `registry.npmjs.org`; MAINFRAME does
not follow redirects, honor proxy overrides, send registry credentials, invoke
npm, run package lifecycle scripts, or execute vendor code. Download dry-run
performs the real acquisition and complete payload authentication in a private
ephemeral workspace, then removes it without publishing a managed generation.
No host install contacts the network unless `--download` is present.

For a separately obtained package set, the existing offline path remains
available:

```bash
mainframe host install claude-code --package-dir /path/to/pinned-tarballs --dry-run
mainframe host install claude-code --package-dir /path/to/pinned-tarballs --yes
```

`--package-dir` stays offline and requires every archive under the exact locked
basename. The two package sources are mutually exclusive. Both routes verify
the exact SRI and package identity, and extraction re-verifies the SRI from the
same archive descriptor it consumes. Python 3.10+ is required for managed
install/remove/restore, but not for status or launch. That interpreter and its standard
library are a local-user trust dependency; MAINFRAME validates the interpreter,
not the complete Python installation. `--json` never prompts; an actionable
request requires either `--dry-run` or `--yes`, while a safe no-op, refusal, or
validation error may return before that boundary. Gemini is recognized but its
managed install remains gated. To remove a valid active generation, preview and then move that
one exact generation into retained private quarantine:

```bash
mainframe host remove claude-code --dry-run
mainframe host remove claude-code --yes
```

Before `host remove --yes`, stop new launches and any agent process that may
still need the managed executable. The authenticated quarantine move is
identity-safe, not an availability guarantee during concurrent launch/removal,
and it does not terminate an already-running process. `--yes` authorizes the
move only; it does not verify that agents are stopped.

Removal preselects an exact generated `removed.<18-hex>` quarantine ID before
entering the atomic move window. Success returns that ID; an interrupted or
failed removal whose mutation outcome may be uncertain reports the same
`Recovery ID` in human output and `quarantine_id` in JSON. Inspect
`mainframe host status` first, then preview only that ID. Restore only that
current, fully authenticated generation with an explicit ID:

```bash
mainframe host restore claude-code --quarantine-id removed.0123456789abcdef01 --dry-run
mainframe host restore claude-code --quarantine-id removed.0123456789abcdef01 --yes
```

Restore is strictly offline, never scans for `latest`, and refuses to overwrite
either a healthy or corrupt active target. It republishes the same directory
identity and leaves the consumed quarantine slot empty for inspection. If the
process is interrupted during the atomic rename, a retry refuses the occupied
target rather than claiming unprovable success; inspect `mainframe host status`
before deciding the next action.

Install, remove, and restore never change global packages, `PATH`, shell
profiles, host configuration, or project files. There is no managed-host
update or quarantine-prune command.
The closed receipt includes `package_set_sha256`; its bundle ID binds both the
MAINFRAME version and that exact selected package set.
The reserved private boundary is
`${XDG_DATA_HOME:-$HOME/.local/share}/mainframe/host-payloads`. See
[Managed host payloads](docs/MANAGED_HOST_PAYLOADS.md) for fail-closed
resolution, platform, managed receipt/full-tree requirements, and the narrower
system/selected trust boundaries.

Then use one of the exact commands it prints to preview and explicitly onboard
one host:

```bash
mainframe setup --project . --host claude-code --dry-run
mainframe setup --project . --host claude-code
# Other supported hosts: codex, copilot, gemini
```

For reviewed automation, `--yes` is required before a non-interactive apply;
it is not needed for `--dry-run`. Onboarding preserves unrelated host settings
and verifies the gateway, private canonical-project AWM session, and project
files. Dry-run and refused consent create no AWM state. Onboarding still cannot
prove that a running host loaded or trusted the hook. Start the protected
session with `mainframe launch`, complete the host's normal project-trust or
hook-review flow, inspect its native hook UI, and run a controlled deny canary
in a disposable project. `mainframe onboard` remains the direct equivalent
when the host is already known.

After that one-time consent, use MAINFRAME as the daily entry point instead of
starting the host directly:

```bash
mainframe launch claude-code --dry-run
mainframe launch claude-code
```

`launch` defaults to the current project and the `medium` gateway policy. It
refuses to start unless the managed instructions, private project AWM mapping,
exact shell hook, launch-time absolute Bash/`jq`/gateway/safety-policy bindings,
their four-digest SHA-256 seal, and the native host executable are all ready.
The bound `jq` must resolve to a supported system or package-manager install,
not a project or arbitrary user `PATH` wrapper. It authenticates the selected
host artifact against MAINFRAME's pinned native-certification manifest before
launch; an older, patched, or merely same-named CLI fails closed. The committed
hook uses a stable `/bin/bash -p` bootstrap and does not look up `mainframe` on
`PATH`.
Before each hook invocation executes the gateway, the bootstrap hashes all
four bound files and compares them with the per-launch seal. A direct host
start without all five launch values fails closed when the configured hook is
invoked, so `mainframe launch` is required for a protected session. The first
contract deliberately accepts no native host flags, so a launch option cannot
silently disable project hooks.

For `launch`, the public CLI removes inherited passive Bash, Node.js, Perl, and
dynamic-loader injection variables before it loads runtime helpers, runs
package-tree authentication, or executes the host. That scrub cannot protect
the initial `/bin/bash` process or operating-system loader, which necessarily
started before MAINFRAME code could run. Start the launcher from a trusted
interpreter and use OS isolation when pre-entry code loading is in scope.
Preflight still reports native host trust, hook loading, and managed-instruction
ingestion as `UNVERIFIED`; those require the host's own trust and hook-review
flow plus a controlled disposable verification.

The generated host instructions use project-scoped AWM commands that resolve
the same private session across separate shell processes. Agents retrieve at
most 1,200 tokens of task context, record only durable decisions/findings and
meaningful milestones, prepare a bounded handoff before compaction or
delegation, and never store credentials, tokens, secrets, raw sensitive
payloads, or routine command chatter.

Rollback removes only MAINFRAME-managed content:

```bash
mainframe deactivate claude-code --project . --enforce
```

Deactivation leaves private AWM project history intact; inspect it with
`mainframe awm project status --project . --discover-root`.

By default the gateway blocks critical, high-risk, and externally visible
medium-risk shell patterns before execution and writes a private decision-only
audit log. Host hook semantics still apply: Copilot documents command-hook
timeouts as fail-open. Direct `mainframe agent-hook` payload probes are
diagnostic adapter checks; they do not exercise the privileged bootstrap or
prove native runtime loading. See [Onboarding](docs/ONBOARDING.md) for the
complete consent, native-verification, and rollback path, and the
[Agent Gateway guide](docs/AGENT_GATEWAY.md) for policy tiers and the exact
security boundary.

### 60-second AWM proof

```bash
mainframe awm project ensure --project . --discover-root
mainframe awm project checkpoint --project . --discover-root current_phase scanning --importance high
mainframe awm project discovery --project . --discover-root "The API uses refresh tokens" --importance critical
mainframe work "continue the API review" --project . --tokens 800
```

`ensure` is the one explicit project-memory initialization or renewal. After
that consent, `mainframe work "<current task>"` is the daily read-only entry
point: it discovers the same project from nested directories, retrieves only
bounded context, labels memory as untrusted data, and prints checkpoint and
handoff templates without executing them. It refuses an unmapped project
rather than silently creating state.

Open a new shell and retrieve the same state:

```bash
mainframe awm project find --project . --discover-root refresh --kind mixed
```

Every write revalidates the exact active mapping while holding the project's
lifecycle lock. It never creates or renews memory as a side effect. Complete a
project session explicitly when the work is done:

```bash
mainframe awm project close --project . --discover-root
```

Completed memory remains available to bounded read commands. A later explicit
`ensure` preserves that completed session and creates one new active mapping;
Pi binds this renewal to the exact state shown in its human confirmation.

Root discovery keeps the session stable while an agent changes directories: it
walks upward to the nearest opted-in boundary, whether that is a complete
managed instruction block or an existing private mapping, without crossing the
current Git worktree. It then uses the worktree root, with exact-directory
fallback outside Git. Omit
`--discover-root` when a supplied `--project` directory must remain a distinct
explicit identity. The private mapping and session live outside model and shell
process context, so state remains available after a terminal restart or handoff
without copying a session ID into every command.

For release-grade proof, `scripts/dev/certify-native-awm-chain.sh` runs one
hidden value through fresh Gemini, Codex, Copilot, and Claude native sessions.
Each host must make exactly one low-risk gateway-approved AWM update, and a
wrong predecessor must stop the chain without emitting evidence. Evidence for
the advertised `Darwin-arm64-none`, `Darwin-x86_64-none`, and
`Linux-x86_64-glibc` platform tuples is bound to the same archive bytes as the
safety certificates; a configured job is not claimed green until its workflow
result exists.

### Verify release evidence

For a future tagged release that actually publishes them, MAINFRAME's durable
evidence contract adds two assets:
`mainframe-X.Y.Z.release-evidence.json` and
`mainframe-X.Y.Z.release-evidence.tar.gz`. Together they carry an exact matrix
of twelve safety certificates (four hosts on each of the three advertised
platform tuples) and three four-host AWM-chain certificates. The manifest binds
the runtime archive, tag ref and peeled commit, workflow bytes/run, and 45
certifier control files; the deterministic bundle contains the manifest plus
all fifteen certificate JSON files.

The tagged workflow separately gates on 24 path-free fresh-shell onboarding
certificates (four hosts by three platforms by Bash and zsh) bound to the same
archive digest. Those short-lived workflow artifacts intentionally remain
outside the durable 16-file native safety/AWM bundle and release assets.

A custom GitHub attestation uses the exact manifest as the predicate for the
runtime archive and both evidence assets. This is tamper-evident GitHub Actions
builder evidence, not an independent witness: AWM remains `external-input`, and
it does not prove real-provider inference or an interactive user's host
trust/runtime load. Repository configuration alone is not public availability.
See [Native Host Execution Certification](docs/NATIVE_HOST_CERTIFICATION.md#durable-release-evidence)
for the complete download, attestation, and offline verifier commands.

For alternate locations, upgrades, and AI-tool integration, see [INSTALL.md](INSTALL.md).

## What MAINFRAME solves

| Agent failure mode | MAINFRAME capability |
|---|---|
| Useful state disappears when context fills | File-backed AWM sessions, checkpoints, discoveries, and summaries |
| A sub-agent starts without the parent agent's decisions | Budgeted context and handoff packages |
| Shell output is difficult to parse | Universal Structured Output Protocol (USOP) |
| A mistaken command targets the wrong path or resource | Validation, path confinement, command classification, and audit logs |
| A coding agent attempts a known destructive shell command | Host pre-tool enforcement for Codex, Claude Code, Copilot CLI, and Gemini CLI |
| An adapter turns model fields into an open-ended shell command | A canonical-ID broker for 26 reviewed stable-core contracts |
| The same shell helper is reimplemented in every task | A generated, searchable Bash function registry plus reviewed stable-core invocation contracts |

MAINFRAME is a validation and runtime layer. It is **not an OS sandbox**. The
launch seal detects straightforward sequential replacement after launch, but a
user-owned install is not tamper-proof against a hostile process running with
the same UID. For hostile race resistance, protect the install with OS/root
ownership or isolate the agent in a separate user, container, or VM. The
complete boundary is documented in [SECURITY.md](SECURITY.md).

## Invoke reviewed helpers through one narrow API

The unpublished 10.2 candidate includes 26 reviewed stable-core invocation
contracts in `config/invocation-policy.json`. Call one by canonical ID with a
closed JSON object:

```bash
mainframe invoke mf:data:json:json_get \
  --input-json '{"json":"{\"name\":\"Ada\"}","key":"name"}'
# Ada
```

`mainframe invoke` resolves the exact owner through `MANIFEST.json`, rejects
unknown IDs, Bash names, executable names, extra fields, capabilities, and
unreviewed effects, then runs only that function in a clean Bash child. Each
contract supplies its argument shape, result kind, timeout, and output limit.
The broker uses a fixed helper `PATH`, kills the child process group on timeout
or excess output, denies a function that leaves descendants behind, rejects
ambiguous JSON framing (including duplicate keys, literal NUL, trailing data,
and oversized input), and returns a bounded receipt containing metadata but no
input values. Public machine adapters request `control-plane-json-v1`; the
kernel validates the strict inner broker envelope, appends Evidence, and only
then exposes the correlated identity and one-consumer result.

Pi, the public MCP runner, and the source-candidate Node.js and Python binding
APIs route these 26 calls atomically through the kernel and fixed broker. MCP
publishes closed input/output schemas, structured content, reviewed effect
metadata, coarse progress when requested, and kernel-generated Run, ToolCall,
PolicyDecision, and Evidence IDs. Pi reports only argument
counts/sizes/field names after execution; raw non-stable arguments appear only
in its separate human-confirmation preview. The public MCP executable exposes
exactly the 26 reviewed stable-core tools and rejects the retired legacy tier
selector. Pi's human-confirmed non-stable-core path and the bindings'
explicitly trusted raw-Bash escape hatches remain legacy/unbrokered. This is a
bounded local execution layer, not an OS sandbox or a same-user tamper
boundary.

## Agent Working Memory

AWM is the most direct way to use MAINFRAME. It stores high-signal task state as files instead of relying on chat history.
Its local store is private by default: directories are `0700`, files are
`0600`, and session/checkpoint paths fail closed on traversal or symbolic-link
escapes. Custom roots must be absolute, normalized, and free of symbolic-link
ancestors. Namespaces organize sessions; they are not a same-user
access-control boundary.

For an already-initialized project, start each task with the host-neutral CLI:

```bash
mainframe work "fix the flaky CI test" --project .
# Machine-readable equivalent:
mainframe work "fix the flaky CI test" --project . --format json
```

The work brief is read-only and capped at 1,200 tokens by default (4,000
maximum). It never initializes or renews AWM, launches an agent, writes a
checkpoint, contacts a network, or treats remembered text as authorization.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

sid=$(awm_init "security-audit" --namespace review --backend file)
awm_resume "$sid"

awm_checkpoint "current_phase" "scanning" --importance high
awm_discovery "Auth uses JWT refresh tokens" --importance critical --tags auth,jwt
awm_progress "scan" "12/40" "Scanning the auth module"

awm_find "jwt" --kind mixed --limit 5
awm_context_for "dependency review" --tokens 2000
awm_handoff_prepare "dependency-reviewer" --tokens 2000
```

Core AWM operations include:

| Operation | Purpose |
|---|---|
| `awm_init` / `awm_resume` | Create or resume a session |
| `awm_checkpoint` | Store durable key/value state |
| `awm_discovery` | Preserve a high-signal finding |
| `awm_progress` | Record current task progress |
| `awm_find` | Search stored session material |
| `awm_context_for` | Build a task-specific context package |
| `awm_handoff_prepare` | Produce a bounded handoff for another agent |
| `awm_status` / `awm_doctor` | Inspect session health |
| `awm_export` / `awm_migrate` | Export or upgrade stored sessions |

See the [AWM cookbook](docs/AWM_COOKBOOK.md) for longer workflows.

## Safety model

MAINFRAME focuses on mistakes made by honest-but-fallible agents:

- A host-facing pre-tool gateway blocks critical and high-risk destructive shell patterns before execution.
- Canonical risk rules classify destructive shell patterns.
- Agent profiles restrict system, network, write, and destructive operations.
- Path checks confine writes to an allowed base.
- Approval hooks can gate high-risk execution.
- Audit logs record blocked, approved, and executed decisions.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/agent_safety.sh"

agent_validate_command "git" "status"
agent_safe_exec "ls" "-la" "/safe/path"
```

Some libraries retain reviewed `eval` use for Bash features that cannot be expressed safely another way. The generated [eval audit](docs/SECURITY_EVAL_AUDIT.md) lists those sites and their classifications. New dynamic execution must be justified and reviewed.

## Structured output

USOP gives agents a stable response shape:

```bash
export MAINFRAME_OUTPUT=json
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

output_success "file created" "verify_file"
# {"ok":true,"data":"file created","hint":"verify_file",...}

output_error "E_NOT_FOUND" "Config missing" "run init first"
# {"ok":false,"error":{"code":"E_NOT_FOUND",...}}

output_int 42
output_bool true
```

## Use only what you need

The generated [FUNCTIONS.json](FUNCTIONS.json) registry is the source of truth for the current inventory. MAINFRAME supports full, selective, and lazy loading:

```bash
# Full interactive runtime
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Selective libraries for short-lived agent commands
MAINFRAME_LIBS="core,awm,output" \
  source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Discover the current surface
mainframe count
mainframe search "create json object"
mainframe quickref --search "name=John, age"
mainframe help json_object
```

`mainframe search` accepts multi-word descriptions and returns canonical,
relevance-first recommendations, using safety and idempotence only to break
comparable matches. `quickref --search` also accepts quoted multi-word signature
text. Search risk labels are discovery hints, not authorization to execute a
function.

The Bash core does not require a Python or Node runtime. For an npm-wrapper
host, `mainframe launch` accepts Node.js only from a supported system, package
manager, or version-manager layout, then hashes and rechecks both Node and
`hash-package-tree.mjs` around package-tree authentication and before exec.
This rejects arbitrary PATH shims and sequential replacement; it does not make
a user-managed Node installation an external trust anchor. Within the managed
  host runtime commands, Python 3.10+ is required by install, remove, and restore for the
reviewed extraction and descriptor-safe filesystem helpers, but not by status
or launch. `hash-package-tree.py` remains developer certifier tooling.
Integrations such as Git, Docker, Kubernetes, HTTP, or SQLite naturally require
the corresponding host command when invoked. `mainframe doctor` reports what
is present.

## AI-tool integrations

| Platform | Integration |
|---|---|
| Pi | First-party package and skill; the pinned Darwin arm64 cell has live local gate, approval, memory, and audit evidence |
| Claude Code, OpenAI Codex, GitHub Copilot CLI, Gemini CLI | Generated instructions and registry-bound shell-hook configuration; evidence is exact-host/platform `configured` or `enforced` |
| Cursor, Aider, OpenCode, Kimi, JetBrains, Junie | Generated instruction artifacts only |
| Custom agents | Shell, MCP, or language bindings |

The canonical evidence and unsupported-route boundary are in
[`config/host-capabilities.json`](config/host-capabilities.json). Installation
alone does not teach an agent to use MAINFRAME. Start with the
explicit [onboarding path](docs/ONBOARDING.md), then follow the host-specific
trust and verification notes in [AI CLI integrations](docs/AI_CLI_INTEGRATIONS.md).

## Testing and evidence

Run the same Bash suite used by CI:

```bash
make test-deps
./tests/run_bats_suite.sh --scope all
```

Focused gates are also available:

```bash
./tests/run_bats_suite.sh --scope safety
./tests/run_bats_suite.sh --scope unit
python3 scripts/export-gate-rules.py --verify
```

The v10.2 candidate has 43 canonical lexical gate rules. The verifier applies
the shipped `security/gate-normalizer.mjs` contract and currently checks 183
Bash/JavaScript parity cases. A `low` result means only that none of those
ordered lexical rules matched; it is not proof that a command or its downstream
effects are safe.

Performance numbers depend on Bash version, operating system, hardware, and the selected load mode. Run the repository benchmark locally instead of treating one machine's result as a universal guarantee:

```bash
bash benchmarks/superpower_benchmarks.sh
```

See [Claims and benchmarks](docs/CLAIMS_AND_BENCHMARKS.md) for the evidence policy and reproduction commands.

## Project status

MAINFRAME is active, experimental open-source infrastructure. The AWM, safety, structured-output, and Bash test surfaces are the most mature. Language bindings and editor/protocol integrations are versioned separately and may have narrower validation coverage.

Current exact Pi compatibility is `@earendil-works/pi-coding-agent` `0.84.2`
on `Darwin-arm64-none`; the legacy-scope `@mariozechner/pi-coding-agent`
`0.73.1` route remains limited because its client-side RPC Bash route is not
observable. Other exact package, version, and platform combinations remain
unverified until their evidence is promoted into the compatibility manifest.

Current version:

```bash
cat VERSION
mainframe version
```

The repository includes a generated function registry, cross-platform Bash CI, an SBOM, checksums, and a documented security boundary. Stable releases are published under [GitHub Releases](https://github.com/gtwatts/mainframe/releases).

## Documentation

- [Why MAINFRAME](docs/COMPARISON.md)
- [Documentation index](docs/README.md)
- [Installation](INSTALL.md)
- [First agent session](docs/AGENT_ONBOARDING.md)
- [Agent readiness checklist](docs/AGENT_READINESS_CHECKLIST.md)
- [Coding-agent onboarding contract](docs/ONBOARDING.md)
- [AWM cookbook](docs/AWM_COOKBOOK.md)
- [Enforced Agent Gateway](docs/AGENT_GATEWAY.md)
- [Native Host Execution Certification](docs/NATIVE_HOST_CERTIFICATION.md)
- [Homebrew Formula Candidate (unpublished)](packaging/homebrew/README.md)
- [AI CLI integrations](docs/AI_CLI_INTEGRATIONS.md)
- [Public API compatibility](docs/API_COMPATIBILITY.md)
- [Function registry](FUNCTIONS.json)
- [Changelog](CHANGELOG.md)
- [Security model](SECURITY.md)
- [Contributing](CONTRIBUTING.md)
- [Implementation and evidence roadmap](docs/CONTROL_PLANE_PLAN.md)
- [Open-source growth and contributor plan](docs/OPEN_SOURCE_GROWTH_PLAN.md)

## Contributing

Help make one real agent workflow easier to trust and repeat. Useful first
contributions include a reproducible setup problem, a permitted command that
was falsely blocked, a clearer recovery guide, or a focused adapter test.
Start with [CONTRIBUTING.md](CONTRIBUTING.md) and the
[bounded work packages](docs/OPEN_SOURCE_GROWTH_PLAN.md#work-packages).
AI-assisted contributions are welcome; the submitter owns the evidence and
review response.

```bash
make test-deps
./tests/run_bats_suite.sh --scope all
```

## License

[MIT](LICENSE)

---

*Knowing your shell is half the battle.*

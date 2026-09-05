# Install MAINFRAME

This guide installs the full MAINFRAME CLI and verifies Agent Working Memory from a clean shell.

## Fast path

The verified bootstrap requires a qualifying immutable release. For
development or evaluation, use the reviewed source-checkout path below:

### macOS fast path

```bash
brew install bash jq git
git clone https://github.com/gtwatts/mainframe.git "$HOME/.mainframe"
/opt/homebrew/bin/bash --noprofile --norc -p \
  "$HOME/.mainframe/install.sh"  # Apple Silicon
# Intel Homebrew uses: /usr/local/bin/bash --noprofile --norc -p "$HOME/.mainframe/install.sh"

export MAINFRAME_ROOT="$HOME/.mainframe"
export PATH="$HOME/.local/bin:$PATH"
mainframe version
mainframe doctor
```

### Linux fast path

```bash
# Debian/Ubuntu example; install Bash 4.4+, jq, and Git with your package manager.
sudo apt-get install bash jq git
git clone https://github.com/gtwatts/mainframe.git "$HOME/.mainframe"
/bin/bash --noprofile --norc -p "$HOME/.mainframe/install.sh"

export MAINFRAME_ROOT="$HOME/.mainframe"
export PATH="$HOME/.local/bin:$PATH"
mainframe version
mainframe doctor
```

Then run the zero-residue first-use proof from the project where an agent will
work:

```bash
cd /path/to/your/project
mainframe setup --project . --proof
mainframe setup --project .
```

The rest of this page is the complete installation, verification, upgrade,
integration, recovery, and troubleshooting reference.

## Requirements

- Bash 4.4 or newer
- `jq`; protected launch requires it to resolve to a supported system or
  package-manager installation, not a project or arbitrary user `PATH` wrapper
- `curl`, `tar`, and a SHA-256 implementation (`sha256sum`, `shasum`, or
  `openssl`) for the verified release bootstrap
- Git only for a source-checkout installation
- Node.js when `mainframe launch` authenticates or executes a supported npm
  wrapper; launch resolves the exact executable and rejects project-controlled
  Node.js paths
- A protected fixed-location Python 3.9+ standard-library runtime for the
  durable control-plane CLI and Pi diagnosis/lifecycle. The reviewed
  managed-host install, remove, and restore helpers require Python 3.10 or
  newer; host status and launch do not require it.

Check the Bash that will run MAINFRAME:

```bash
bash --version
```

macOS ships Bash 3.2. The bootstrap script can run under that fixed system Bash
and will locate a Bash 4.4+ runtime only in supported system, Homebrew,
Linuxbrew, or MacPorts locations. It never probes `bash` from the working
directory or `PATH`. Install a current version first if one is not already
available:

```bash
brew install bash jq
/opt/homebrew/bin/bash --version  # Apple Silicon
/usr/local/bin/bash --version     # Intel Homebrew
```

The core runtime is Bash, and `jq` is required for the safety-ready supported
installation. Other optional libraries wrap external programs such as Docker,
Kubernetes, HTTP clients, or SQLite; those commands are required only when the
corresponding integration is used. `mainframe doctor` reports the detected
environment. Python is not a status or runtime-launch requirement: npm
package-tree authentication accepts Node.js only from a supported system,
package-manager, or version-manager layout, then hashes and rechecks Node plus
`scripts/dev/native-host/hash-package-tree.mjs` around authentication and
before exec. This blocks arbitrary PATH shims but is not an external trust
anchor for user-managed Node installations. Managed-host install requires a
reviewed Python 3.10+ runtime for bounded local extraction, while managed-host
remove and restore require it for descriptor-safe filesystem operations. Status
and launch do not require Python; the separate Python tree hasher remains
developer certifier tooling.

## Source-checkout installation

This public source-checkout path supports development and evaluation. It does
not provide the archive/receipt trust guarantees described below, so review
and pin the commit you install. Normal users should prefer the versioned
[Bootstrap installer](#bootstrap-installer) when a qualifying immutable release
is available. The older public `v10.1.0` release is mutable and lacks the
required runtime archive and checksum sidecar; it does not qualify.

Clone the repository into the default location and run its installer:

```bash
git clone https://github.com/gtwatts/mainframe.git "$HOME/.mainframe"
/usr/bin/bash --noprofile --norc -p "$HOME/.mainframe/install.sh"
```

On macOS, run the installer with the newer Bash you installed:

```bash
/opt/homebrew/bin/bash --noprofile --norc -p \
  "$HOME/.mainframe/install.sh"  # Apple Silicon
# or /usr/local/bin/bash on Intel Homebrew
```

The installer:

1. Validates the Bash version and repository layout.
2. Keeps the checked-out repository as `MAINFRAME_ROOT`.
3. Links the full CLI into `~/.local/bin/mainframe`.
4. Adds `MAINFRAME_ROOT` and `~/.local/bin` to the appropriate shell profile when needed.

For Bash, the installer keeps one canonical managed runtime block in
`~/.bashrc`. It also adds a separately marked bridge to the first effective
login profile in Bash's normal order (`~/.bash_profile`, `~/.bash_login`, then
`~/.profile`), so both interactive login and interactive non-login shells discover
MAINFRAME without adding the bin directory to `PATH` twice. Existing content
is retained. The installer refuses malformed or overlapping MAINFRAME markers
instead of replacing an ambiguous profile block.

After an install, upgrade, or manually reviewed candidate switch, check both
supported shells against the CLI selected by `PATH`:

```bash
mainframe shell status --shell all
mainframe shell repair --shell all --dry-run
# Apply only after reviewing the exact profile list:
mainframe shell repair --shell all --yes
```

Status is read-only. It compares the selected CLI and inherited
`MAINFRAME_ROOT` with the exact managed Bash and zsh blocks. A mismatch keeps
`mainframe doctor` and `mainframe setup` non-ready. Repair must be invoked
through that PATH-selected CLI from a user-owned, non-group/world-writable bin
directory; it preflights every target before replacement,
preserves unrelated content and file modes, and creates a timestamped backup
for every existing profile it changes. Symbolic links, hard-linked profiles,
non-owned or group/world-writable files and directories, and malformed or
overlapping managed markers are refused.
For zsh, an inherited absolute, existing, user-owned `ZDOTDIR` selects that
directory's `.zshrc`; relative, missing, or non-owned locations fail closed.
If `.zshenv` assigns `ZDOTDIR` without exporting it, status and repair refuse
the ambiguous HOME fallback. Pass the already-reviewed active directory with
`--zdotdir /absolute/path`; MAINFRAME does not source startup code to discover
profile locations.

The default install does not modify Claude Code, Codex, Gemini, Copilot, or
other AI host configuration. Host activation is a separate, explicit step.
`--no-claude` remains accepted as a deprecated no-op for older install scripts.

Reload the profile printed by the installer, or open a new terminal.

## Verify the installed product

```bash
mainframe version
mainframe doctor
mainframe count
```

From the project where an agent will work, run the concise first-use proof:

```bash
cd /path/to/your/project
mainframe setup --project . --proof
```

It uses a private mode-700 temporary directory to exercise one fixed reviewed
pure invocation, checkpoint an isolated AWM value, retrieve that fixed key from
a fresh Bash process, and classify—but never execute—a destructive canary. On
success it removes the temporary AWM and broker state, leaving no project, user
AWM, or audit state behind. It starts no coding-agent host or Pi process. This
is a zero-residue mechanism proof; agent improvement/adoption and live host
protection remain `UNVERIFIED` until the relevant live checks are complete.

To create persistent AWM state deliberately after that isolated proof:

```bash
sid=$(mainframe awm init install-check --namespace verification)
mainframe awm checkpoint --session "$sid" status working --importance high
mainframe awm discovery --session "$sid" "Installation verified" --importance high
mainframe awm summary --session "$sid"
printf 'Session ID: %s\n' "$sid"
```

Open a new shell and run:

```bash
mainframe awm find --session "<session-id>" verified --kind mixed
```

If both commands return the session material, the CLI and persistent storage path are working.

## Bootstrap installer

`get-mainframe.sh` is a convenience wrapper around the same supported
repository and CLI. Inspect it before running it, or download it and run it.
On macOS, `/bin/bash` 3.2 is sufficient for this bootstrap step; the script
then finds a supported Bash 4.4+ runtime before launching `install.sh`:

The verified mode is publication-gated: `--latest` fails closed if no qualifying
immutable release is available. The older public `v10.1.0` release is mutable
and lacks the required runtime assets. Use the current bootstrap to resolve
a qualifying published immutable release exactly once:

```bash
curl -fsSLo /tmp/get-mainframe.sh \
  "https://raw.githubusercontent.com/gtwatts/mainframe/main/get-mainframe.sh"
less /tmp/get-mainframe.sh
/bin/bash --noprofile --norc -p /tmp/get-mainframe.sh
# Equivalent explicit selector:
# /bin/bash --noprofile --norc -p /tmp/get-mainframe.sh --latest
```

With no selector, the bootstrap uses exactly the `--latest` resolver. It
requires a published, non-prerelease `vMAJOR.MINOR.PATCH` whose GitHub release
metadata reports `immutable: true`. It accepts exactly one uploaded
`mainframe-X.Y.Z.tar.gz` and one adjacent `.sha256` asset at their canonical
versioned URLs. Both downloaded files must match their GitHub API SHA-256
digests, and the single-record sidecar must contain that same archive digest.
The concrete version then enters the exact flow below; the API is not queried
again. If the bootstrap is interrupted, use the printed
`--release-version X.Y.Z` selector to retry the same release rather than
resolving `latest` again.

If the public latest release is mutable or lacks either required runtime asset,
both the selector-free and explicit `--latest` forms fail closed and never fall
back to the legacy mutable installer. Release publication must satisfy that
immutable two-asset contract before this convenience path is advertised as
live.

For reproducibility and exact bootstrap provenance, choose a reviewed release
and download `get-mainframe.sh` from that same immutable version tag:

```bash
release_version=X.Y.Z
curl -fsSLo /tmp/get-mainframe.sh \
  "https://raw.githubusercontent.com/gtwatts/mainframe/v${release_version}/get-mainframe.sh"
less /tmp/get-mainframe.sh
/bin/bash --noprofile --norc -p /tmp/get-mainframe.sh \
  --release-version "$release_version"
# Equivalent:
MAINFRAME_VERSION="$release_version" \
  /bin/bash --noprofile --norc -p /tmp/get-mainframe.sh
```

The convenience `--latest` example downloads its bootstrap from mutable
`main`; the immutable release lookup protects the selected release assets, not
that initial script. Prefer the pinned-tag form whenever exact bootstrap
provenance matters.

This downloads `mainframe-X.Y.Z.tar.gz` and
`mainframe-X.Y.Z.tar.gz.sha256` from the exact `vX.Y.Z` GitHub release. Before
the target is created or an installer runs, the bootstrap:

1. Requires exactly one lowercase SHA-256 record naming the exact archive.
2. Verifies the archive digest.
3. Rejects absolute paths, `..` traversal, duplicate members, links, special
   entries, and ambiguous tar listings.
4. Verifies every regular payload file against the complete inner
   `SHA256SUMS` inventory and rejects unlisted files.
5. Confirms the embedded `VERSION`, installer, CLI, and release upgrader.

The verified payload is moved into the target and its own installer runs in
place, so this clean-install path does not invoke `git clone`, `git pull`, or
another repository operation. The target must be missing or empty; the
bootstrap stops rather than overwriting an existing installation or unrelated
files. Core installation first disables shell-profile and agent-discovery
writes. It writes a private release receipt only after the exact CLI link,
complete payload inventory, version command, and `mainframe doctor` pass; any
requested shell or discovery setup runs afterward.

If the process is killed after exact payload placement or core installation,
rerun the same versioned bootstrap command with the same target and release
origin. A private sibling bootstrap journal binds the archive, manifest,
payload directory, and CLI-link identities so the retry can finish only that
exact verified install. It rejects replaced roots or links, including a new
link inode with the same text target. Do not delete the journal or its private
staging paths while recovery is pending. This covers tested process
interruption around the placement and core-install boundaries; it is not a
claim of recovery from filesystem corruption or arbitrary power loss.

If core verification and receipt creation succeed but optional shell or agent
discovery setup fails, the core installation remains valid. The bootstrap
prints an exact command for retrying only that optional setup instead of
reinstalling the release.

The receipt binds the installed version, archive digest, inner-manifest digest,
canonical install path, bin directory, and CLI link. It is local provenance,
not a publisher signature. GitHub's asset digests, immutable metadata, archive,
and checksum remain under the same publisher and release origin; the resolver
adds consistency and non-mutation checks, not an independent signature. Use an
inspected bootstrap and a trusted HTTPS connection, and prefer the pinned-tag
form for reproducible installs.

The pre-10.2 mutable source path remains available only through an explicit
compatibility selector:

```bash
/bin/bash --noprofile --norc -p /tmp/get-mainframe.sh --legacy-source
```

That is the **legacy mutable mode**. It downloads and executes
`MAINFRAME_INSTALLER_URL`, which defaults to `install.sh` on the selected
branch, and prints a warning because no release checksum is verified. Keep
`MAINFRAME_INSTALLER_URL` only for existing automation or a deliberately
reviewed source workflow. Legacy-only `--repo`, `--branch`,
`--legacy-installer-url`, and `--allow-unverified-source` options are rejected
unless `--legacy-source` is present. `get-mainframe.sh -h` and `--help` print
local bootstrap guidance without resolving dependencies, creating a temporary
workspace, or contacting the network.

To select a reviewed Bash executable explicitly, provide an absolute path:

```bash
MAINFRAME_BASH=/opt/homebrew/bin/bash \
  /bin/bash --noprofile --norc -p /tmp/get-mainframe.sh --legacy-source
```

The bootstrap canonicalizes an explicit override before executing it, requires
the executable to be owned by root or the current user without group/other
write or special mode bits, and accepts only supported system, Homebrew,
Linuxbrew, MacPorts, or Nix layouts. The override selects among reviewed
locations; it does not authorize an arbitrary user or project executable.
Without an override, only fixed system and supported package-manager paths are
considered. Every version probe and installer
delegation uses `--noprofile --norc -p` with `BASH_ENV`, exported functions,
and dynamic-loader injection variables removed from the child environment. If
no trusted candidate is new enough, the bootstrap stops with platform-specific
installation guidance.

The bootstrap also discards the caller's dependency `PATH` immediately after
startup. Archive download, inspection, hashing, and filesystem operations use
the fixed macOS/Linux system path, so a project-local `curl`, `tar`, `awk`, or
hash shim is not executed. `jq`, and Git when needed by a source checkout, are
resolved separately from fixed system, Homebrew, Linuxbrew, or MacPorts
locations and canonicalized under the same executable ownership and mode
policy before use. The source-checkout installer applies the same
controlled-path rule to its filesystem and runtime checks.

## Custom install location

Set `MAINFRAME_INSTALL_DIR` before running the installer:

```bash
export MAINFRAME_INSTALL_DIR="$HOME/tools/mainframe"
/bin/bash --noprofile --norc -p /tmp/get-mainframe.sh \
  --release-version "$release_version"
```

For a source checkout instead:

```bash
export MAINFRAME_INSTALL_DIR="$HOME/tools/mainframe"
git clone https://github.com/gtwatts/mainframe.git "$MAINFRAME_INSTALL_DIR"
/usr/bin/bash --noprofile --norc -p "$MAINFRAME_INSTALL_DIR/install.sh"
```

The installer records that location as `MAINFRAME_ROOT`.

## Use MAINFRAME in a script

```bash
#!/usr/bin/env bash
set -euo pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

trim_string "  hello  "
output_bool true
```

Use selective loading for short-lived agent commands:

```bash
MAINFRAME_LIBS="core,awm,output" \
  source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

The generated [FUNCTIONS.json](FUNCTIONS.json) registry and CLI discovery commands describe the current function surface:

```bash
mainframe search "create json object"
mainframe quickref --search "name=John, age"
mainframe help json_object
```

`mainframe search` returns canonical, relevance-first recommendations for
multi-word descriptions; safety and idempotence break comparable matches.
`quickref --search` accepts quoted multi-word signature text. Search risk labels
are discovery hints only and do not authorize execution.

## Agent Working Memory configuration

AWM stores sessions under `~/.mainframe/awm` by default. Override it for project or test isolation:

```bash
export AWM_ROOT="$(pwd -P)/.mainframe-awm"
```

AWM makes directories `0700` and memory, log, lock, and handoff files `0600`.
It requires an absolute normalized root, rejects traversal and symbolic-link
ancestors or escapes, and tightens older session modes during migration. A
namespace organizes sessions but does not isolate processes running as the
same operating-system user.

On the supported local-host path, AWM uses the OS kernel lock available by
default (`flock` on Linux or BSD `lockf` on macOS). The last-resort portable
`mkdir` strategy fails closed after a crashed holder instead of guessing that
a pathname is safe to reclaim. Network filesystems and cross-host writers are
outside the file backend's locking guarantee.

Useful operations:

| Command | Purpose |
|---|---|
| `mainframe awm init` | Create a session |
| `mainframe awm checkpoint` | Save durable key/value state |
| `mainframe awm discovery` | Record an important finding |
| `mainframe awm progress` | Save current task progress |
| `mainframe awm find` | Search session material |
| `mainframe awm summary` | Return a structured session summary |
| `mainframe awm handoff prepare` | Create a bounded agent handoff |
| `mainframe awm doctor` | Inspect session health |

See [docs/AWM_COOKBOOK.md](docs/AWM_COOKBOOK.md) for full workflows.

## Inspect and manage coding-agent host runtimes

Installing MAINFRAME itself does not install or replace Codex, Claude Code,
Copilot CLI, or Gemini CLI. Inspect the local runtime choices without network
access or mutation:

```bash
mainframe host status
mainframe host status codex --json
```

Status remains read-only: it hashes local candidates but does not execute them,
invoke npm, download packages, or change machine state. Reserved private
payloads live under
`${XDG_DATA_HOME:-$HOME/.local/share}/mainframe/host-payloads`, never in the
project or MAINFRAME release tree.

On `Darwin-arm64-none`, `Darwin-x86_64-none`, or
`Linux-x86_64-glibc`, install a managed Codex, Claude Code, or Copilot runtime
from one explicit package source. The shortest path is a verified download:

```bash
mainframe host install codex --download --dry-run
mainframe host install codex --download --yes
```

`--download` is explicit permission to contact only the exact locked HTTPS
package URLs on `registry.npmjs.org`. No install performs network I/O without
that flag. Download dry-run performs the real anonymous acquisition, SRI and
package authentication, bounded extraction, and full staged-runtime check in
a private ephemeral workspace, then removes it without publishing.

To use packages acquired through a separate reviewed process, keep the entire
operation offline with `--package-dir`:

```bash
mainframe host install codex --package-dir /path/to/pinned-tarballs --dry-run
mainframe host install codex --package-dir /path/to/pinned-tarballs --yes
```

The complete syntax is:

```text
mainframe host install HOST (--download | --package-dir DIR) [--dry-run | --yes] [--json]
```

The two sources are mutually exclusive. A package directory must contain every
required archive under the exact basename of its `resolved` URL in
`scripts/dev/native-host/package-lock.json`. Both routes check each archive's
exact SHA-512 SRI and package identity. The extractor re-verifies the SRI from
the same no-follow descriptor used for bounded extraction, authenticates the
complete assembled tree and native executable, writes a closed receipt, and
atomically publishes one generation only with `--yes`. The download route does
not follow redirects, honor proxy overrides, send registry credentials, invoke
npm, run package lifecycle scripts, or execute vendor code. `--json` never
prompts; an actionable request requires either `--dry-run` or `--yes`, while a
safe no-op, refusal, or validation error may return first. Gemini is recognized
but managed installation is gated until its complete closure and Node.js runtime
are pinned. A corrupt target is refused rather than replaced. The selected
system or Homebrew Python interpreter and standard library are a local-user
trust dependency for install, remove, and restore; MAINFRAME validates the
interpreter, not the complete Python tree.

If interruption or helper failure occurs after atomic publication becomes
possible, install emits no success. Human output directs you to
`mainframe host status HOST --runtime managed`; JSON reports whether the
mutation is proved or uncertain.

The receipt includes `package_set_sha256`, which commits to the exact selected
lock records. Its `bundle_id` binds both the MAINFRAME version and that exact
package set, in addition to the authenticated host, platform, tree, entry point,
manifest, lock, and executable identities.

Managed runtime removal is a retained quarantine move, not a purge:

```bash
mainframe host remove codex --dry-run
mainframe host remove codex --yes
```

Before `host remove --yes`, stop new launches and any agent process that may
still need the managed executable. The authenticated quarantine move is
identity-safe, not an availability guarantee during concurrent launch/removal,
and it does not terminate an already-running process. `--yes` authorizes the
move only; it does not verify that agents are stopped.

Remove preselects an exact generated quarantine ID before entering the atomic
move window. Success returns it. If an interruption or helper failure leaves
the mutation outcome uncertain, human output labels the same `Recovery ID` and
JSON returns it as `quarantine_id`; inspect `mainframe host status` before an
exact-ID dry run. Use that ID—not a path, glob, or implicit newest entry—to
authenticate and restore the same current generation:

```bash
mainframe host restore codex --quarantine-id removed.0123456789abcdef01 --dry-run
mainframe host restore codex --quarantine-id removed.0123456789abcdef01 --yes
```

Restore is offline, requires the active deterministic target to be absent, and
uses the same no-replace descriptor-safe move under the lifecycle lock. A
successful restore preserves the generation identity and retains the consumed
slot as an empty inspection marker. An interrupted outcome may be uncertain;
the command never treats an occupied target as an idempotent success without a
durable slot-to-target provenance record.

Remove authenticates the current deterministic generation, then atomically
moves only that generation into a private same-filesystem quarantine. It
refuses a corrupt target and leaves stale or sibling generations untouched.
The reviewed Python 3.10+ helper keeps removal and restore descriptor-safe. No
lifecycle command changes `PATH`, shell profiles, global packages, project
files, or host configuration. There is no managed-host update or prune command;
unused and consumed quarantine slots are not removed automatically.

Automatic resolution prefers a complete, receipt-backed, fully authenticated
managed payload. It falls back to an exactly authenticated system CLI only
when managed execution is absent or unsupported; an expected but corrupt
managed payload fails closed. `--runtime system` on status, setup, or launch is
the explicit system override. Managed Codex, Claude Code, and Copilot use
their certified platform-native executables. Managed Gemini remains blocked
until MAINFRAME has a complete dependency closure and pinned Node.js runtime
contract. A system direct-native candidate is authenticated by its exact
executable digest only; a system wrapper receives its integration's
checks. Codex, Claude Code, and Copilot wrapper routes report an authenticated
runtime tree with an unpinned-Node boundary; Gemini reports incomplete closure
with an unpinned-Node boundary. Status reports the boundary of the source
actually selected. See
[Managed host payloads](docs/MANAGED_HOST_PAYLOADS.md) for the full boundary.

## Onboard MAINFRAME for a coding agent

Installing MAINFRAME does not modify project host files or prove that a coding
agent loaded MAINFRAME. Begin with a strictly read-only project report:

```bash
cd /path/to/your/project
mainframe setup --project .
```

The report checks Bash/zsh availability and supported host CLI/project-marker
signals without auto-selecting a host or creating project, audit, or AWM state.
Choose one of its exact next commands to preview and then consent to that same
host and project:

```bash
mainframe setup --project . --host claude-code --dry-run
mainframe setup --project . --host claude-code
```

Supported values are `codex`, `claude-code`, `copilot`, and `gemini`. A
non-interactive apply requires `--yes`; a preview never does. Onboarding runs
the installation doctor, previews merge-safe changes, checks an allow and deny
request through the installed gateway, applies the host instructions and hook,
and verifies static readiness. It still reports host runtime loading as
`UNVERIFIED`: start the protected session with `mainframe launch`, complete the
host's native trust or hook-review flow, and run a controlled deny canary in a
disposable project. See
[Coding-agent onboarding](docs/ONBOARDING.md) for the complete procedure and
rollback boundary.

`mainframe onboard --host <host> --project <dir>` remains the direct equivalent
when the host is already known.

For normal work after onboarding, launch the host through the read-only
fail-closed preflight:

```bash
mainframe launch claude-code --dry-run
mainframe launch claude-code
```

The project defaults to `.` and the gateway policy defaults to `medium`.
Launch requires current managed instructions, an existing private AWM mapping,
exact static hook readiness, and host artifact bytes authenticated against
MAINFRAME's pinned native-certification manifest; it repairs nothing and
accepts no native host arguments. It starts the host only after those checks
pass. At launch time it supplies exact absolute Bash, `jq`, installed-gateway,
and installed-safety-policy paths plus one four-digest SHA-256 seal to the
commit-stable `/bin/bash -p` hook bootstrap. `jq` must resolve to a supported
system or package-manager installation. Before each hook call, the bootstrap
hashes the four bound files and rejects a mismatch. The hook does not find
`mainframe` through `PATH`; starting the host directly without all five launch
values fails closed when the hook is invoked. Use `mainframe launch` for
protected sessions. This seal detects straightforward sequential replacement
after launch, but a user-owned installation is not a sandbox or a tamper-proof
boundary against a hostile process with the same UID. Hostile race resistance
requires an OS/root-protected install or separation with another user, a
container, or a VM. Native trust/runtime loading remains `UNVERIFIED`.

The lower-level `activate --enforce`, `protect status`, and `deactivate
--enforce` commands remain available for manual and recovery workflows. Direct
`mainframe agent-hook` payload probes are diagnostic adapter checks, not the
privileged host boundary.

### Pi

Pi uses the first-party package declared by MAINFRAME's root `package.json`.
After Pi has created its user agent directory, inspect, preview, and explicitly
activate the package:

```bash
mainframe pi status
mainframe pi doctor
mainframe pi install --dry-run
mainframe pi install --yes
```

Run the confirmed `--yes` command yourself in an external terminal; the Pi
extension gives an agent only status and dry-run guidance and blocks
model-issued MAINFRAME lifecycle confirmation. Install records the canonical
package source in Pi's user `settings.json` and a private mode-600
`.mainframe-pi-receipt.json`. It preserves unrelated settings, replaces a
filtered package object that would hide the bundled extension or skill,
deduplicates path aliases by physical root, removes the exact stale source from
the previous manager receipt after an upgrade, and moves recognized user-level
legacy resources into a private `.mainframe-pi-backup-*` directory. Homebrew
records its stable `opt` `libexec` source rather than a versioned Cellar path.
The successful transaction prints the exact backup basename as `backup_id` and
an explicit `restore_available=true|false`. The narrow restore command is
available only for an existing-settings migration that quarantined both legacy
resources and did not replace a prior manager receipt; other retained backups
remain audit/quarantine evidence rather than supported restore inputs.

The transaction rolls back on verification failure. It never treats an
inherited environment variable as approval and never changes project-local
`.pi` resources. A project `settings.json` package entry, standalone extension,
or skill that can take precedence blocks both user-level install and removal
for separate review. Pi diagnosis and lifecycle require a protected
fixed-location Python 3.9+ with the standard modules reported by `mainframe pi
doctor`; the managed-host filesystem helpers retain their separate Python
3.10+ requirement.

After a changed install, use `/reload` in Pi (or restart it), then run
`/mainframe doctor`. A disk status of `ready` does not prove an already-running
Pi process has reloaded the package. External `mainframe pi doctor` never
executes Pi and therefore never reports live readiness; it separates exact
version/platform compatibility, disk configuration, and runtime activation.

If the first in-Pi doctor fails after a successful migration whose output said
`restore_available=true`, recover only the exact snapshot named by that
install. Preview and confirm with the same ID:

```bash
mainframe pi restore --backup-id .mainframe-pi-backup-YYYYMMDDTHHMMSSZ.A1b2C3 --dry-run
mainframe pi restore --backup-id .mainframe-pi-backup-YYYYMMDDTHHMMSSZ.A1b2C3 --yes
```

Restore validates the complete private backup, reconstructs the exact
expected post-install settings as a compare-and-swap boundary, and refuses any
unrelated drift. Recognized interrupted restore phases can resume with the same
ID; ordinary failures roll back to the exact package-ready state. The backup
remains available for inspection. Restart Pi after a changed restore.

Before uninstalling MAINFRAME—including with Homebrew—preview and detach the
managed Pi package from a human terminal:

```bash
mainframe pi remove --dry-run
mainframe pi remove --yes
```

Removal uses the same private lock, concurrent-change checks, verification,
and rollback boundary as install. It removes only package entries matched to
the current or receipted source and the private manager receipt; unrelated Pi
settings, project files, and historical migration backups remain. Reload or
restart Pi after a changed removal. The general `mainframe uninstall` command
refuses while a current or receipted package source is still attached and fails
closed if the advertised Pi lifecycle payload is incomplete. Homebrew Formulae
cannot run an uninstall-preflight hook, so do not invoke `brew uninstall`
directly while attached. After the preview, use the formula's safe chain:

```bash
mainframe pi remove --yes && brew uninstall gtwatts/mainframe/mainframe
```

The package contributes the `mainframe` skill, `/mainframe`, and seven tools:
status, install commands, search, help, guarded execution, AWM, and Bash safety
classification. Before either supported Pi shell route launches its initial
Bash, the extension removes inherited shell-startup, exported-function,
language-loader, and dynamic-loader variables, then enters the protected Bash
4.4+ wrapper. It cannot undo code loaded into the Pi process before extension
initialization. See `skills/pi/SKILL.md` for the agent workflow.

### Claude Code

```bash
mainframe onboard --host claude-code --project . --dry-run
mainframe onboard --host claude-code --project .
```

This merge-safe, project-scoped command adds MAINFRAME instructions and its
blocking pre-tool shell hook. Preview the exact changes first with `--dry-run`.
Start Claude with `mainframe launch claude-code` in the activated project,
accept Claude's normal workspace-trust prompt, inspect the generated hook, and
run a controlled disposable canary. Static `configured` status does not prove
that an existing Claude process trusted or loaded the hook.
Remove only MAINFRAME's managed entries with:

```bash
mainframe deactivate claude-code --project . --enforce
```

### OpenAI Codex

```bash
mainframe onboard --host codex --project . --dry-run
mainframe onboard --host codex --project .
mainframe protect status codex --project .
```

This preserves existing `AGENTS.md` and `.codex/hooks.json` content. Project
command hooks still require Codex trust review against their current hash:
start Codex with `mainframe launch codex` in the trusted project, open `/hooks`,
review the MAINFRAME entry, and then run a disposable canary. Static
`configured` status does not prove runtime trust or loading.

### Cursor

```bash
mkdir -p .cursor/rules
cp "$HOME/.mainframe/skills/cursor/mainframe.mdc" .cursor/rules/
```

For Copilot CLI and Gemini CLI onboarding, or Aider, OpenCode, Kimi, and custom
agent instructions, see [docs/AI_CLI_INTEGRATIONS.md](docs/AI_CLI_INTEGRATIONS.md).

## Upgrading a verified release

Receipt-backed release installs can verify a selected version without changing
the active runtime:

```bash
mainframe upgrade --version X.Y.Z --dry-run
```

Before the actual cutover, stop every agent or shell process using this
installation. Current AWM writers do not share the upgrade lock, so the command
requires an explicit confirmation:

```bash
mainframe upgrade --version X.Y.Z --confirm-agents-stopped
```

The upgrader verifies the current receipt and managed bytes, the exact outer
checksum record, archive structure, complete inner manifest, and candidate
version before replacement. Private in-root state is copied only when it is
regular, stable, collision-free, non-executable, and outside managed runtime
surfaces; symbolic links, special files, nested mounts, and unmanaged runtime
code fail closed. The selected version must not be older unless
`--allow-downgrade` is explicit.

Cutover retains the previous installation in a private sibling transaction
directory and verifies the new version and doctor result. Ordinary failures
roll back automatically. The retained directory is a point-in-time backup:
state written after the upgrade is not merged into it, and MAINFRAME does not
offer a post-success rollback command. Replacing the active runtime with that
backup manually can therefore discard newer AWM, task, or cache state.

If a process is killed after a rename, use the exact absolute copied-script
command printed before cutover. Its shape is:

```bash
/path/to/bash /private/transaction/recover-upgrade.sh \
  --recover --journal /exact/path/to/.mainframe.upgrade-journal.json
```

When the active runtime still exists, `mainframe upgrade --recover` can discover
its sibling journal; if the root is absent, the installed CLI link cannot
launch and the printed copied-script command is required. Do not delete the
journal or transaction directory until recovery succeeds. After a successful
upgrade has been stable long enough that rollback evidence is no longer
needed, inspect and remove only the exact transaction directory printed by the
upgrade; no automatic cleanup currently deletes retained backups.

## Updating a source checkout

`mainframe update` is intentionally separate from release upgrade. It refuses
dirty, detached, or non-`main` checkouts and performs a fast-forward-only
update. To inspect the incoming source first:

```bash
git -C "${MAINFRAME_ROOT:-$HOME/.mainframe}" fetch origin
git -C "${MAINFRAME_ROOT:-$HOME/.mainframe}" status --short --branch
mainframe update
mainframe doctor
```

Homebrew installations remain package-manager owned; use
`brew upgrade gtwatts/mainframe/mainframe` to upgrade or
`brew uninstall gtwatts/mainframe/mainframe` to uninstall. For controlled environments,
prefer explicitly reviewed receipt-backed releases over tracking `main`.

## Troubleshooting

### `mainframe: command not found`

Confirm the link and `PATH`:

```bash
ls -l "$HOME/.local/bin/mainframe"
printf '%s\n' "$PATH"
export PATH="$HOME/.local/bin:$PATH"
```

### Bash is too old

Run the installer and scripts with an explicit Bash 4.4+ executable. Changing the login shell is optional.

### The CLI and shell profile point at different MAINFRAME roots

Inspect both Bash and zsh without changing either profile:

```bash
mainframe shell status --shell all
mainframe shell repair --shell all --dry-run
```

If the preview names only the profiles you expect, apply the repair and open a
fresh shell:

```bash
mainframe shell repair --shell all --yes
mainframe doctor
```

Do not edit around malformed MAINFRAME markers with the repair command. It
fails closed so you can inspect and resolve the ambiguous profile content
manually.

### AWM state is not where expected

```bash
printf 'MAINFRAME_ROOT=%s\n' "${MAINFRAME_ROOT:-unset}"
printf 'AWM_ROOT=%s\n' "${AWM_ROOT:-default}"
mainframe awm doctor --session "<session-id>"
```

### An optional integration is missing

Run `mainframe doctor` and install only the host tool required by the library you intend to use.

## Recoverable uninstall

Preview the exact owned paths first:

```bash
mainframe uninstall --dry-run
```

Then run the default recoverable uninstall:

```bash
mainframe uninstall
```

The CLI dispatches only the regular, non-symlinked
`$MAINFRAME_ROOT/uninstall.sh` owned by the current user. A release install
must bind that exact file through its private receipt and `SHA256SUMS`; a
source install must match the `uninstall.sh` object tracked at `HEAD`. If that
ownership cannot be established, the CLI refuses before the uninstaller runs.
Homebrew installs instead print the exact
`brew uninstall gtwatts/mainframe/mainframe` package-manager command.

It removes only a CLI symlink whose target exactly matches the installation,
removes only the content between MAINFRAME's exact shell-profile markers, and
backs up each changed profile. The installation itself moves to a timestamped
sibling such as `~/.mainframe.uninstalled-20260804T120000Z`; the command prints
the exact restore operation.

For a custom location, pass the same paths used during installation:

```bash
mainframe uninstall --dry-run \
  --dir "$HOME/tools/mainframe" \
  --bin "$HOME/.local/bin"
```

If the trusted CLI launcher is unavailable during recovery, the equivalent
direct entrypoint remains `"$HOME/tools/mainframe/uninstall.sh" --dry-run`.

Only after reviewing the dry run, `--purge` removes files that are both listed
in the installed `SHA256SUMS` inventory and still byte-identical to that
inventory. Every unmanaged or modified in-root file—including private AWM,
task, cache, and other agent state—is preserved at a timestamped sibling such
as `~/.mainframe.state-preserved-20260804T120000Z`. If the ownership inventory
is missing or malformed, purge refuses before changing profiles, links, or the
installation:

```bash
mainframe uninstall --purge
```

The machine-level uninstaller cannot locate project hook files because private
AWM mappings intentionally do not store project paths. Deactivate every
onboarded project before uninstalling; otherwise its fail-closed hook can remain
in place after the runtime is gone. Only the compound, explicit
`--purge --purge-state` form erases all data stored directly inside the install
root as well as the runtime:

```bash
mainframe uninstall --purge --purge-state
```

The purge path rejects the home directory, filesystem root, symlinked install
roots, and directories that do not contain MAINFRAME's identity files.

# Managed host payloads

MAINFRAME provides a private, deterministic host-runtime boundary so a
supported coding agent can use the exact runtime MAINFRAME has certified
without replacing the user's global CLI. The v1 lifecycle can inspect a
runtime, explicitly acquire or consume its exact package set, and move it out
of active resolution. It never repairs a modified payload, invokes npm, runs
package lifecycle scripts, or executes vendor code during install.

## Inspect host sources

Use `host status` to inspect all supported hosts or one exact host:

```bash
mainframe host status
mainframe host status codex
mainframe host status codex --runtime managed
mainframe host status codex --json
```

Supported host names are `codex`, `claude-code`, `copilot`, and `gemini`.
`--json` exposes the same read-only result for automation. Status is offline:
it may inspect and hash local files, but it does not execute a host candidate,
contact a registry, invoke npm, or change files. Authenticating a system npm
wrapper can execute the separately resolved user-managed Node.js interpreter
to run MAINFRAME's tree hasher; Node's path and bytes are sealed for that
check, but Node is not an independent behavioral trust anchor.

## Install from one explicit package source

Managed install requires exactly one package source. Use `--download` for
MAINFRAME's closed network path or `--package-dir` for separately obtained
local archives:

```text
mainframe host install HOST (--download | --package-dir DIR) [--dry-run | --yes] [--json]
```

```bash
mainframe host install codex --download --dry-run
mainframe host install codex --download --yes

mainframe host install codex --package-dir /path/to/pinned-tarballs --dry-run
mainframe host install codex --package-dir /path/to/pinned-tarballs --yes
```

### Explicit verified download

`--download` is the only managed-install flag that permits network I/O. It
connects anonymously and directly to `registry.npmjs.org` over HTTPS for the
exact package-name, version, URL, and SHA-512 SRI selected by MAINFRAME's
trusted host manifest and package lock. It does not accept an alternate
registry, mutable `latest` selector, URL redirect, proxy override, registry
credential, cookie, or ambient npm configuration.

`--download --dry-run` is a real network preflight, not a no-network plan. It
downloads every required archive into a private ephemeral workspace, verifies
the streamed SRI before making the archive visible there, performs bounded
extraction and complete staged-payload authentication, and then removes the
workspace without publishing a managed generation. `--download --yes` performs
the same checks and atomically publishes the authenticated generation. A
download never invokes npm, runs a package lifecycle script, or executes a
vendor launcher or binary.

The extractor opens each downloaded archive without following links,
re-verifies its exact SRI on the same stable descriptor used for extraction,
and rejects replacement, truncation, oversized content, traversal, links,
special entries, sparse files, extended metadata, duplicate paths, and case
collisions. Package name and version must also match the locked identity.

### Offline local package directory

`--package-dir` never contacts the network. `DIR` must contain every archive in
the current host-and-platform package set. Each filename must be the exact
basename of that package's `resolved` URL in
`scripts/dev/native-host/package-lock.json`; renamed archives are not accepted.
For example, this candidate's Codex root archive is `codex-0.146.0.tgz`, with a
second platform-specific Codex archive selected for the current tuple. Claude
Code similarly requires its root and platform archives. Copilot requires its
root and platform archives plus the locked `detect-libc-2.1.2.tgz`. The lock
and trusted host manifest, not this example, are authoritative when versions
change.

The local path receives the same exact SRI, package-identity, bounded-extraction,
complete-tree, native-entry-point, receipt, and atomic-publication checks as
downloaded input. An existing corrupt target is refused rather than overwritten.

Python 3.10 or newer is required for the reviewed managed install/remove/restore
helpers: direct TLS acquisition when requested, bounded extraction during
install, and descriptor-safe filesystem operations during remove and restore. `host status`
and `mainframe launch` do not require Python. The selected system or Homebrew
Python interpreter and its standard library are part of the local-user trust
boundary for those commands; MAINFRAME validates the interpreter's location,
ownership, mode, ACL, and version, but does not authenticate the complete
Python installation.

Publication always requires `--yes`; `--dry-run` and `--yes` are mutually
exclusive. Without `--download`, install performs no network I/O. `--json`
never prompts. An actionable request requires either `--dry-run` or `--yes`,
while a safe no-op, refusal, or validation error may return before the consent
boundary; JSON returns the same path-redacted result as the human command.
Once atomic publication becomes possible, an interruption or helper failure
never emits install success: human output directs the operator to
`mainframe host status HOST --runtime managed`, and JSON reports the proved or
uncertain mutation state.

Mutating lifecycle commands also fail closed if `.lifecycle-lock` already
exists under the private payload root. MAINFRAME does not automatically reclaim
a possibly stale pathname: first confirm that no install/remove/restore process is
running, then inspect the exact private lock before any manual recovery.

Managed install is supported for `codex`, `claude-code`, and `copilot` on the
advertised tuples below. `gemini` is a recognized host name, but managed install
fails closed until its complete dependency closure and pinned Node.js runtime
contract are available.

## Private payload boundary

The reserved per-user payload root is exactly:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/mainframe/host-payloads
```

This is data owned by the user, outside the MAINFRAME release tree and outside
an onboarded project. A managed payload never adds a command to `PATH`, changes
a Bash or zsh profile, edits a host dotfile, or replaces a globally installed
npm package. Install, remove, and restore also do not edit project files or host
configuration. MAINFRAME upgrades do not copy these vendor executables into the
MAINFRAME installation.

The one expected location has this exact shape:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/mainframe/host-payloads/
  v1/HOST/VERSION/PLATFORM/BUNDLE_ID/
    receipt.json
    payload/
```

`HOST`, `VERSION`, `PLATFORM`, and `BUNDLE_ID` are derived from the current
trusted host manifest, package lock, MAINFRAME version, exact package set, and
advertised platform tuple, not chosen by PATH order or a mutable `latest`
pointer. `mainframe host install` is the supported publisher; manually
assembling or replacing a tree there is not a supported installation method.

## Remove one generation to quarantine

Removal is recoverable and does not mean deletion:

```text
mainframe host remove HOST [--dry-run | --yes] [--json]
```

```bash
mainframe host remove codex --dry-run
mainframe host remove codex --yes
```

Remove authenticates the current deterministic generation and, after `--yes`,
uses the reviewed Python 3.10+ descriptor-safe helper to atomically move that
one exact generation into a retained, private, same-filesystem quarantine under:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/mainframe/host-payloads/
  quarantine/v1/HOST/VERSION/PLATFORM/BUNDLE_ID/removed.ID/generation/
```

It does not purge bytes or touch stale or sibling generations. An absent target
is already removed; a corrupt target is refused and retained for inspection.
`--dry-run` authenticates and reports the move without changing state. Removal
does not alter `PATH`, profiles, global packages, project files, or host
configuration.

For `--yes`, MAINFRAME preselects the exact `removed.<18-lowercase-hex>` ID
before the helper can rename anything. A successful result returns it. If a
signal or helper failure occurs after mutation becomes possible, the finite
human error labels the same `Recovery ID` and JSON returns it as
`quarantine_id`, with `changed: null` whenever the final mutation state cannot
be proved. The ID itself does not assert that a slot exists: inspect
`mainframe host status HOST --runtime managed`, then use an exact-ID restore
dry run when the active target is absent.

Before `host remove --yes`, stop new launches and any agent process that may
still need the managed executable. The authenticated quarantine move is
identity-safe, not an availability guarantee during concurrent launch/removal,
and it does not terminate an already-running process. `--yes` authorizes the
move only; it does not verify that agents are stopped.

## Restore one exact quarantined generation

The successful remove result returns an exact generated ID matching
`removed.<18-lowercase-hex>`. Restore accepts only that ID:

```text
mainframe host restore HOST --quarantine-id removed.<18-hex> [--dry-run | --yes] [--json]
```

```bash
mainframe host restore codex --quarantine-id removed.0123456789abcdef01 --dry-run
mainframe host restore codex --quarantine-id removed.0123456789abcdef01 --yes
```

Restore is strictly offline. It never accepts a path, prefix, glob, `latest`,
or implicit quarantine selection. MAINFRAME derives the source from the current
trusted host, version, advertised platform, and bundle metadata; requires the
active deterministic target to be absent; validates private symlink-free
same-filesystem ancestry and nested mounts; requires the slot to contain only
`generation`; and re-authenticates the complete receipt, package closure, tree,
entry point, executable, ownership, modes, ACLs, link counts, and source
filesystem identity.

`--dry-run` performs those checks without acquiring the mutation lock or moving
the generation. `--yes` acquires the shared lifecycle lock, re-derives and
re-authenticates every input, and uses a kernel no-replace rename to republish
the exact source inode. Success is emitted only after the target identity and
complete payload authenticate again and the lifecycle lock is explicitly
released. The consumed `removed.ID` slot remains as an exact empty mode-`0700`
directory for inspection and later explicit pruning.

A ready, corrupt, linked, or otherwise occupied active target is never
overwritten and is not reported as already restored. The v1 slot contains no
durable transaction record binding its ID to the target, so interruption after
the rename can be reported only as `mutation_state: "uncertain"`. A retry then
refuses the occupied target; use `mainframe host status HOST --runtime managed`
to inspect whether the current bytes are ready. MAINFRAME never attempts an
automatic reverse rename after an uncertain or failed post-rename check.

## Deterministic resolution

The resolver keeps managed and system state separate:

| Policy | Result |
|---|---|
| `auto` | Prefer the exact valid managed payload. On an advertised platform, an absent payload or host-specific unsupported managed route may fall back to an authenticated system CLI discovered on `PATH`. |
| `managed` | Require the exact valid managed payload; do not fall back to `PATH`. |
| `system` | Explicitly bypass the managed candidate and authenticate the system CLI on `PATH`. |

`auto` distinguishes absence or host-specific unsupported scope from
corruption. On an advertised platform, an absent managed payload or a host such
as Gemini whose managed route is not yet supported may fall back to a compatible
system CLI. A valid platform policy that omits the current tuple makes every
runtime source unavailable; `system` is not a platform-support override. A
missing, malformed, or ambiguous platform policy blocks resolution. If the
deterministic expected path exists but its receipt or payload is incomplete,
unsafe, or modified, resolution fails closed; it does not silently downgrade to
the system CLI.
The `system` policy is therefore an explicit operator override, not an
automatic recovery path.
When selecting a runtime for launch, use:

```bash
mainframe launch codex --runtime auto
mainframe launch codex --runtime managed
mainframe launch codex --runtime system
```

`auto` is the default. A system candidate remains subject to the existing
non-project path and route-specific artifact authentication checks; `system`
does not mean "trust any command with this name." A directly discovered native
binary is bound by its exact executable digest, not by a surrounding full-tree
claim. A discovered npm wrapper receives the wrapper/runtime-tree checks
defined for that integration, including the disclosed external Node.js
boundary where applicable.

Status uses a small fixed vocabulary. Managed state is `ready`, `absent`,
`corrupt`, or `unsupported`; system state is `ready`, `absent`, `unsafe`, or
`incompatible`; and the requested policy's selection is `ready`,
`unavailable`, or `blocked`. Human and JSON output describe the same state.

JSON reports `managed.trust_boundary`, `system.trust_boundary`, and
`selection.trust_boundary` separately; none is a host-wide capability label:

| Candidate or selection | Reported trust boundary |
|---|---|
| Supported managed Codex, Claude Code, or Copilot | `managed-direct-native-full-tree` |
| Ready system direct-native candidate | `system-direct-native-executable-only` |
| Ready system Codex, Claude Code, or Copilot wrapper/runtime route | `system-runtime-tree-unpinned-node` |
| Ready system Gemini wrapper/runtime route | `system-incomplete-closure-unpinned-node` |

Managed Gemini reports a null boundary because that route is unsupported. A
system boundary is null unless that system candidate is ready, and a selected
boundary is null unless selection is ready. The selected boundary copies only
the boundary of the source actually chosen by the requested policy. It
therefore cannot imply managed full-tree verification when `system` was
selected.

## What makes a managed payload valid

A receipt is evidence about a payload, not a substitute for authenticating
it. `receipt.json` uses a closed v1 schema with exactly these keys:

```text
schema_version, kind, bundle_id, mainframe_version, host, host_version,
platform, hosts_manifest_sha256, package_lock_sha256, package_set_sha256,
tree_root, tree_sha256, executable, executable_sha256, launch_mode
```

`kind` must be `mainframe-managed-host-payload`, `tree_root` binds `payload/`,
and the currently accepted `launch_mode` is `direct-native`. A candidate is
usable only when all of these checks agree:

- the payload is at the one deterministic path for the current host version
  and advertised platform tuple;
- the XDG data home and managed ancestry are current-user-owned, not writable
  by group or others, symlink-free, and do not cross a nested mount;
- the generation is owner-only mode `0700`, the receipt is `0600` with one hard
  link, and every directory and regular file below `payload/` is normalized
  read-only mode `0500`; all are non-symlinked and owned by the current user,
  and every regular payload file has one hard link;
- the closed receipt binds the exact MAINFRAME and host versions, platform,
  bundle, current host-manifest and package-lock digests, exact package-set
  digest, payload-tree digest, entry point, and executable digest;
- every required file is present and has the expected digest, while missing,
  changed, unlisted, linked, or special entries are rejected; and
- the selected executable and package tree still match MAINFRAME's trusted
  native-host manifest at resolution and immediately before execution.

The full-tree check is intentional. A valid-looking launcher plus an
unrecorded dependency is not a valid payload, and a receipt alone cannot make
modified bytes trustworthy. Because these files are owned by the same user as
the agent, this is tamper detection rather than an operating-system isolation
boundary.

`package_set_sha256` commits to the sorted exact package records used for this
host and platform: lock path, package name, version, resolved URL, and SHA-512
SRI. `bundle_id` binds the MAINFRAME version and that exact package-set digest,
along with the host/version/platform and authenticated manifest, lock, tree,
entry-point, and executable identities. A MAINFRAME version or package-set
change therefore resolves to a different deterministic generation.

## Host and platform scope

Managed payload support is intentionally narrower than the package pins that
exist for certification work:

| Host | Managed v1 execution boundary |
|---|---|
| Codex | Exact certified platform-native executable; the npm launcher is not the managed execution boundary. |
| Claude Code | Exact certified platform-native executable; neither `postinstall` nor the npm wrapper is executed. |
| GitHub Copilot CLI | Exact certified platform-native executable; the npm loader is not the managed execution boundary. |
| Gemini CLI | **Blocked** pending a complete dependency closure and a pinned Node.js runtime contract. System-runtime authentication remains separate. |

Only these platform tuples are currently advertised for this managed boundary:

- `Darwin-arm64-none`
- `Darwin-x86_64-none`
- `Linux-x86_64-glibc`

Linux arm64 and musl package pins in the development manifest do not by
themselves establish supported managed payloads. They remain outside the
advertised product boundary until matching release evidence exists.

## Current limitations

There is no managed-host update or prune command. A user may explicitly
download the current exact package set or supply the exact locked tarball
basenames locally. To change to a newly pinned generation, remove the current
exact generation and install the new package set after reviewing both
operations. Restore is current-certification-only and therefore is not a
downgrade mechanism; stale quarantines and consumed slots are not cleaned
automatically.
`mainframe host status` remains read-only and cannot make a missing or
incompatible host ready. Its human output does print state-aware recovery
commands: online and offline managed previews only for an absent, certified
payload; diagnosis only for corrupt state; and a system-runtime path for
Gemini on a release-certified platform. An unlisted or unrecognized platform
receives no managed or system selection advice because `system` is not a
platform-support override. Status never executes the commands it prints. A
user-supplied system installation remains a valid separate path on an
advertised tuple when its bytes match the exact certified manifest.

Even a valid managed or system runtime proves artifact identity only. It does
not prove that the host trusted the project, loaded MAINFRAME's hook, or sent a
shell-tool request through the gateway. Launch and onboarding must continue to
report runtime loading as **UNVERIFIED** until the host-native trust review and
controlled disposable canary are completed.

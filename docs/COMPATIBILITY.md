# Compatibility Matrix

Status: planned 10.2.0 candidate snapshot, not a published-release claim.
Evidence policy per
[CLAIMS_AND_BENCHMARKS.md](CLAIMS_AND_BENCHMARKS.md): every cell must be
reproduced by CI or a recorded run.

## Runtime

| Component | Requirement | Notes |
|---|---|---|
| Bash | >= 4.4 (5.x recommended) | macOS `/bin/bash` 3.2 is NOT supported; MCP and bindings resolve only an absolute `MAINFRAME_BASH` or fixed reviewed Homebrew/system locations, canonicalize the selected path, and never search ambient `PATH` for the interpreter |
| jq | required | Registry counts, manifest tooling, LSP metadata, and canonical invocation contract/envelope processing |
| Python | Pi: protected Python >= 3.9 with `json`, `os`, `pathlib`, `stat`, and `sys`; >= 3.10 for MCP, manifest/parity, and managed-host mutation helpers | `mainframe pi doctor` reports the selected interpreter; Pi's read-only/lifecycle path is intentionally compatible with the protected macOS system Python 3.9.6 currently exercised locally |
| OS | `Darwin-arm64-none`, `Darwin-x86_64-none`, `Linux-x86_64-glibc` | Exact advertised candidate tuples. Final exact-candidate remote proof is still pending for Intel macOS and Linux. BSD and WSL are untested. |

## Pi package

The root `package.json` declares the first-party extension and `mainframe`
skill. `config/pi-compatibility.json` is the machine-readable, fail-closed
source for exact package/version/platform evidence. `mainframe pi
status/doctor/install/remove` manages one canonical local package
source with a private receipt, transactionally migrates recognized user-level
legacy copies, replaces filtered entries that would suppress package resources,
and removes stale receipted roots during upgrades. Homebrew uses its stable
`opt` `libexec` source. Project-local Pi package entries and resources are
detected but never rewritten and interlock user-level mutation.

`mainframe uninstall` requires the complete Pi lifecycle payload and refuses
while its current or receipted source is attached. Homebrew itself has no
Formula uninstall-preflight hook; users must run the documented Pi detach
before direct `brew uninstall`, or Pi can retain a dangling `opt_libexec` path.

| Pi distribution | Pinned version | Platform tuple | Product status | Candidate evidence |
|---|---:|---|---|---|
| `@earendil-works/pi-coding-agent` | 0.84.1 | `Darwin-arm64-none` | `CERTIFIED` | Exact local package, prompt, seven tools, agent Bash, TUI `user_bash`, RPC safe/block paths, and Bash/zsh callers pass on 2026-08-09 |
| Legacy scope `@mariozechner/pi-coding-agent` | 0.73.1 | `Darwin-arm64-none` | `LIMITED` | Package, prompt, seven tools, agent Bash, and TUI `user_bash` pass; its RPC client `bash` command does not emit the extension event and that route is not observable |
| Any other package, version, or platform | any | any unlisted exact tuple | `COMPATIBILITY_UNVERIFIED` | Never inferred from a semver range or from a passing subset; Linux and Intel macOS remain unverified until exact evidence is promoted into the compatibility manifest |

Both matrix entries use the package-declared `typebox: "*"` peer dependency,
as required by Pi's bundled extension dependency contract. Pi packages execute
with the user's permissions; MAINFRAME is an approval/policy/audit layer, not
an operating-system sandbox. Lifecycle `--yes` commands must come from a human
terminal; the Pi extension blocks an agent from authorizing its own install or
removal.

The external doctor never starts Pi and cannot turn disk configuration into a
live-readiness claim. Even canonical disk state remains
`ACTIVATION_UNVERIFIED` until the running Pi process executes `/mainframe
doctor`. That in-process doctor reports `READY` only when the runtime identity
is exactly certified, its root matches the canonical package source, the
extension command and seven tools are loaded, all three hooks are registered,
protected Bash is available, and the canonical gate is verified.
The existing prompt hook also mirrors that diagnosis into Pi's status footer
before every agent turn. The badge writes no receipt or durable state and never
widens the certified seven-tool, three-hook surface; any inspection or core
doctor failure is displayed as `MF BLOCKED`.

For function calls, the candidate's Pi extension keeps its exact seven-tool
surface. `mainframe_exec` resolves stable-core names to reviewed canonical IDs
and delegates them to `mainframe invoke`; non-stable-core functions retain the
guarded legacy path and require Pi's human confirmation UI. Candidate tests of
that routing do not by themselves prove that the currently running Pi process
has reloaded the package.

## Managed host payload lifecycle

`mainframe host status [HOST] [--runtime auto|managed|system] [--json]` is a
read-only, offline resolver report. It distinguishes exact managed payloads
under `${XDG_DATA_HOME:-$HOME/.local/share}/mainframe/host-payloads` from
authenticated system CLIs and does not install or execute either candidate.

| Host | Managed-payload boundary | v1 lifecycle status |
|---|---|---|
| Codex | Certified direct platform-native executable | Explicit verified registry acquisition or offline install from exact local locked tarballs on all three advertised tuples |
| Claude Code | Certified direct platform-native executable; npm lifecycle and wrapper paths excluded | Explicit verified registry acquisition or offline install from exact local locked tarballs on all three advertised tuples |
| GitHub Copilot CLI | Certified direct platform-native executable; npm loader path excluded | Explicit verified registry acquisition or offline install from exact local locked tarballs on all three advertised tuples |
| Gemini CLI | Not selectable as managed | Blocked pending complete dependency closure and a pinned Node.js runtime |

The install contract is
`mainframe host install HOST (--download | --package-dir DIR) [--dry-run | --yes] [--json]`.
Exactly one package source is required. `--download` is the sole network-consent
flag and performs anonymous acquisition from exact SRI-pinned HTTPS URLs on
`registry.npmjs.org`; it follows no redirects or proxy overrides. With
`--dry-run`, it downloads, verifies, extracts, and authenticates ephemerally,
then publishes nothing. `--package-dir` instead requires the exact archive
basenames selected from the package lock and remains offline. Both routes
verify exact SHA-512 SRI and package identity, re-verify SRI on the same
descriptor used for bounded extraction with Python 3.10+, and authenticate the
full direct-native payload. Neither invokes npm, runs package scripts, or
executes vendor code. Publication requires `--yes`; `--json` never prompts. An
actionable request requires `--dry-run` or `--yes`, while a safe no-op, refusal,
or validation error may return first. The closed receipt includes
`package_set_sha256`, and the bundle ID binds the MAINFRAME version plus that
exact package set. The selected system or Homebrew Python interpreter and
standard library remain inside the local-user trust boundary for
install/remove/restore; MAINFRAME validates the interpreter, not its complete
installation tree.

`mainframe host remove HOST [--dry-run | --yes] [--json]` authenticates and
atomically moves only the current exact generation to retained private
same-filesystem quarantine using the reviewed Python 3.10+ descriptor-safe
helper.
Before `host remove --yes`, stop new launches and any agent process that may
still need the managed executable. The authenticated quarantine move is
identity-safe, not an availability guarantee during concurrent launch/removal,
and it does not terminate an already-running process. `--yes` authorizes the
move only; it does not verify that agents are stopped.

`mainframe host restore HOST --quarantine-id removed.<18-hex>
[--dry-run | --yes] [--json]` is strictly offline. It restores only the exact
current authenticated generation returned by remove, requires the active target
to be absent, preserves the source inode with a no-replace rename, and retains
the consumed slot as an empty inspection marker. It refuses an occupied target
and never scans quarantine or selects `latest`. Install, remove, and restore do
not change `PATH`, profiles, global packages, projects, or host configuration.
There is no managed-host update or prune command.
Status remains offline and read-only.

On an advertised platform, default `auto` resolution prefers a valid managed
payload, falls back to an exactly authenticated system CLI only when the
payload is absent or that host's managed route is unsupported, and fails closed
when the deterministic expected path exists but its receipt or full tree is
invalid. An unadvertised platform is not selectable; missing or invalid platform
policy blocks every source. `system` is an explicit source override, not an
automatic corruption or platform-support fallback. The managed boundary is
advertised only for the three OS tuples in the runtime table above; development
pins for Linux arm64 or musl are not product support. Managed selection
authenticates the complete payload tree. A system direct-native selection
authenticates only the exact executable. System Codex, Claude Code, and Copilot
wrapper routes report a runtime-tree/unpinned-Node boundary; system Gemini
reports incomplete closure with unpinned Node.js. Status attaches the selected
boundary to the source actually chosen. Runtime loading remains `UNVERIFIED`.
See
[MANAGED_HOST_PAYLOADS.md](MANAGED_HOST_PAYLOADS.md).

## Canonical invocation broker

| Item | Candidate contract | Current limit |
|---|---|---|
| Reviewed surface | Exactly 26 stable-core canonical IDs from `config/invocation-policy.json` | Broader `core`/`full` exports have no reviewed broker contract |
| Public CLI | `mainframe invoke <canonical-id> --input-json '<object>'` (or JSON on stdin) | Canonical IDs only; Bash and executable names are rejected |
| Execution | Closed schema and argv mapping, exact manifest owner, binary-safe bounded JSON framing, clean protected Bash child, fixed helper `PATH`, per-contract time/output bounds, descendant/process-group termination | Local-user process boundary; not an OS sandbox or hostile same-user isolation |
| Audit / adapter wire | Private value-redacted JSONL audit; strict `broker-json-v1` envelope | Audit availability is mandatory and fails closed |
| Adapter routing | Pi, the public 26-tool MCP runner, and source-candidate Node.js/Python canonical and public function calls delegate to the broker | Pi non-stable-core and explicitly trusted binding raw-Bash methods remain legacy/unbrokered; the MCP executable rejects legacy tier configuration |

These are unpublished 10.2 source-candidate capabilities. The current local
Darwin arm64 candidate tests are not a public-release or final Intel
macOS/Linux claim.

## MCP server (`mcp/`)

| Item | Version | Gate |
|---|---|---|
| MCP package / SDK | `mainframe-mcp` 10.2.0 / exact `mcp==1.26.0`; Python >=3.10,<3.15 | locked wheel + sdist build, clean non-editable install, and `python -I -m mainframe_mcp`/isolated-console proof |
| Public surface | Exactly 26 brokered stable-core tools | no public `core`/`full` route; any `MAINFRAME_MCP_TIER` setting fails closed |

## LSP extension (`lsp/`)

| Item | Version | Gate |
|---|---|---|
| VS Code engine | ^1.75.0 | `bun test` |
| Bun | lockfile-frozen | `bun install --frozen-lockfile` |
| Metadata | `FUNCTIONS.lsp.json` (4,406 owner-filtered candidate entries from 193 libraries) | regenerated from MANIFEST.json |

## Bindings

| Binding | Runtime | Gate |
|---|---|---|
| Node.js | Bun/Node, `vscode-languageclient` | `bun run test` |
| Python | >= 3.10 | `uv run --with pytest python -m pytest tests/ -q` |

## Host activation adapters

| Host | Instruction / enforcement file | Current automated evidence |
|---|---|---|
| Codex | `AGENTS.md` / `.codex/hooks.json` | Explicit-consent onboarding installs an enforced `PreToolUse` adapter plus the project-scoped AWM protocol; final exact-candidate remote proof is pending for `Darwin-x86_64-none` and `Linux-x86_64-glibc` |
| Claude Code | `CLAUDE.md` / `.claude/settings.json` | Explicit-consent onboarding installs an enforced `PreToolUse` Bash adapter plus the project-scoped AWM protocol; final exact-candidate remote proof is pending for `Darwin-x86_64-none` and `Linux-x86_64-glibc` |
| GitHub Copilot CLI | `.github/copilot-instructions.md` / `.github/hooks/mainframe.json` | Explicit-consent onboarding installs an enforced `preToolUse` shell adapter plus the project-scoped AWM protocol; documented timeout behavior remains fail-open; final exact-candidate remote proof is pending for `Darwin-x86_64-none` and `Linux-x86_64-glibc` |
| Gemini CLI | `GEMINI.md` / `.gemini/settings.json` | Explicit-consent onboarding installs an enforced `BeforeTool` adapter plus the project-scoped AWM protocol; final exact-candidate remote proof is pending for `Darwin-x86_64-none` and `Linux-x86_64-glibc` |
| Cursor | `.cursor/rules/mainframe.mdc` / none | Instruction activation and AWM workflow |
| JetBrains AI Assistant | `.aiassistant/rules/mainframe.md` / none | Instruction activation and AWM workflow |
| Junie | `.junie/guidelines.md` / none | Instruction activation and AWM workflow |

`tests/release-archive.bats` defines installed-archive checks for all four
enforcement adapters. The final planned 10.2.0 candidate has no current Intel
macOS or Linux execution proof; a workflow definition or an older certificate is not that
proof. See
[AGENT_GATEWAY.md](AGENT_GATEWAY.md) for the evidence labels and the remaining
installed-host canaries. Gemini, Codex, Claude, and Copilot have stronger, separate gates
documented in
[NATIVE_HOST_CERTIFICATION.md](NATIVE_HOST_CERTIFICATION.md). Codex, Claude,
and Copilot evidence applies only to each exact pinned runtime path, not Codex
Desktop, Claude's npm postinstall or wrapper launch paths, GitHub.com agents,
or IDE extensions, and no gate proves real-provider inference.

## Distribution candidates

| Channel | Current evidence | Availability |
|---|---|---|
| Versioned runtime archive | Reproducible-build, offline-install, tamper-denial, SBOM, and provenance gates are defined | Planned 10.2.0 candidate asset; as audited 2026-08-08, public v10.1.0 does not contain this full archive |
| Release evidence manifest and certificate bundle | Builder and workflow bind the runtime archive, tag, workflow, certifier inputs, host-safety matrix, and project-scoped AWM chains | Planned candidate; no final-candidate `Darwin-x86_64-none` or `Linux-x86_64-glibc` certificate is claimed, and public v10.1.0 lacks the evidence assets |
| Homebrew tap formula | Exact-archive generator plus macOS/Linux style, audit, source-install, formula-test, AWM, gateway, protect-readiness, and completion gates are defined | Unpublished candidate; no accessible `gtwatts/homebrew-mainframe` tap or public `brew install` command |

The candidate tagged-release workflow is designed to require the separate Gemini,
Codex, Claude, and Copilot native-host jobs and bind exactly twelve safety
certificates covering all four hosts on each advertised platform tuple, plus
three AWM-chain certificates covering those same tuples, to one release
archive. The manifest
also binds the exact tag ref object and peeled commit, tag-matching workflow
bytes and workflow run, and the sorted 45-file certifier-input allowlist. Those
control bytes, including the release-evidence builder, definition, and schema,
must be equal across the peeled tag, working tree, and safely inspected final
runtime archive. The Homebrew matrix artifacts are separately bound to the
final archive/formula bytes. This document does not claim that a newly added CI
lane is already green remotely or that a public release contains its
certificate.

A separate shell-onboarding gate is designed to require 24 path-free JSON
certificates: four hosts by three advertised platform tuples by Bash and zsh.
Release assembly validates their exact coverage and archive digest, but these
short-lived workflow artifacts are intentionally outside the durable 16-file
native safety/AWM evidence bundle and are not published as release assets.

On 2026-08-08, the exact local `Darwin-arm64-none` 10.2.0 candidate archive
passed all eight host/shell onboarding lanes: Codex, Claude Code, Copilot, and
Gemini under both Bash and zsh. Each lane verified that the installed tree
exactly matched the archive inventory plus the private receipt, along with
fresh-shell discovery, doctor, consent and decline boundaries, gateway
decisions, rollback, and AWM continuity. These are local candidate results,
not remote CI or published release evidence, and host runtime loading remains
explicitly unverified. The
archive digest belongs in the generated evidence rather than this archive
member so the release payload does not create a self-referential digest.

For a release that actually publishes them, the two added assets are
`mainframe-X.Y.Z.release-evidence.json` and
`mainframe-X.Y.Z.release-evidence.tar.gz`. The latter contains the manifest and
all fifteen certificate JSON files. The runtime archive and both evidence assets
share the custom GitHub predicate
`https://github.com/gtwatts/mainframe/attestations/release-evidence/v1`; verifier
policy restricts the signer workflow, source ref/commit, and GitHub-hosted
runner, then compares the signed predicate to the downloaded manifest. See
[NATIVE_HOST_CERTIFICATION.md](NATIVE_HOST_CERTIFICATION.md#durable-release-evidence)
for the complete offline/builder and GitHub attestation verification sequence.

This packaging does not change the certificate boundary. AWM remains
`external-input`; deterministic provider fixtures do not prove real-provider
inference; the evidence does not prove an interactive user's host trust or
runtime load; and a GitHub Actions builder attesting its own collected evidence
is not an independent witness or proof outside GitHub's builder trust.

The workflow accepts only a newly created tag whose commit is reachable from
`origin/main` and is designed to recheck tag identity around publication. Its
required GitHub release protections are currently unconfigured: immutable
releases must be enabled, the reviewer-protected `mainframe-release`
environment must be created, and a `mainframe-release-tags` ruleset must block
`v*` update/deletion with an empty bypass list. GitHub does not expose bypass
actors to the read-only policy check, so an authorized release reviewer must
audit that list separately. The environment must also hold an
Administration-read-only policy token for the immutable-release preflight; the
normal workflow token remains the only credential used to publish. No
accessible `gtwatts/homebrew-mainframe` tap was found in the 2026-08-08 audit.
The release and tap remain explicit future release operations. See the
[Homebrew candidate guide](../packaging/homebrew/README.md).

## Registry / manifest

| Artifact | Source | Verification |
|---|---|---|
| `FUNCTIONS.json` | generated registry from the source libraries | `scripts/sync-version.sh --check` plus canonical count/parity checks |
| `MANIFEST.json` | derived from the current registry + collision policy | `scripts/generate-manifest.py --verify` byte-compares a fresh manifest, then round-trips the registry |
| `FUNCTIONS.lsp.json` | derived from the canonical manifest | `scripts/check-owner-parity.py` requires exact registry/manifest/LSP names, counts, versions, and owners |
| Release archive | `scripts/build-release-archive.sh` | cross-mtime reproducibility, offline install, missing/tampered payload denial, and installed adapter canaries in `tests/release-archive.bats` |
| Receipt-backed release lifecycle | `get-mainframe.sh`, `scripts/upgrade-release.sh` | focused bootstrap and upgrade suites cover complete-manifest install, receipt authorization, explicit-version dry-run/cutover, state preservation/refusal, rollback, and process-interruption recovery; the composed real-payload bootstrap-to-upgrade lane is green locally on `Darwin-arm64-none`, including real AWM continuity, but final exact-candidate Linux and Intel macOS proof remains pending |
| Release evidence | `scripts/dev/native-host/build-release-evidence.py` | `verify` rechecks 45 tag/worktree/archive-bound control files, tag/workflow binding, exact 12+3 tuple coverage, certificate schemas/digests, byte-identical manifest, and canonical 16-file bundle |

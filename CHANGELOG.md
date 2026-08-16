# Changelog

Notable user-facing changes are recorded here. MAINFRAME follows semantic versioning for tagged releases.

## 10.2.0 - Unreleased

### Added

- Explicit-consent onboarding for Codex, Claude Code, GitHub Copilot CLI, and
  Gemini CLI, with host-native pre-tool hooks routed through one auditable
  MAINFRAME agent gateway.
- Project-scoped Agent Working Memory that resumes one private, file-backed
  session across fresh shell and coding-agent processes without copying a
  session ID into every command.
- Bash and Zsh discovery for the project AWM lifecycle, bounded context and
  handoff guidance, readiness reporting, and rollback instructions.
- A read-only `mainframe setup` discovery flow that reports detected shells,
  supported agent CLIs, project markers, protection status, and the exact
  explicit-consent onboarding command without auto-selecting a host.
- A fail-closed `mainframe launch` daily entry point for Codex, Claude Code,
  GitHub Copilot CLI, and Gemini CLI.
- Deterministic runtime archives, Homebrew formula candidates, and release
  evidence bundles tied to native safety and AWM execution certificates.
- Clean-user installer regression coverage.
- CI validation for the Python and Node.js bindings on Linux and macOS.
- Public-claim verification and a documented evidence policy.
- A receipt-backed, explicit-version `mainframe upgrade` workflow with dry-run,
  downgrade consent, private state preservation, health-checked cutover,
  retained backup, automatic rollback, and copied-script recovery.
- A method-aware `mainframe uninstall` command that forwards the existing
  recoverable dry-run and purge controls only to an installation-owned
  uninstaller, while Homebrew remains package-manager owned.
- Schema-validated offline mechanism evidence that binds exact source and
  release-archive bytes while explicitly recording that provider inference,
  agent quality, productivity, and comparative performance were not measured.
- A release-contained, credentials-free Agent Impact conformance harness plus
  a separate prepare/verify-only live-study preregistration contract. The
  latter fixes the three-task design, sample stages, budgets, statistics,
  runtime identities, policies, and private assignment commitment while
  hard-coding that no live sessions or comparative measurement occurred.
- A prepare/verify-only Pi/Ollama runtime preflight that binds independently
  declared Node, MAINFRAME archive/tree, Pi certification/package-tree, Ollama
  installation and ordered model-blob closure, neutral arm contract, and
  dormant adapter/protocol bytes without starting or inspecting processes,
  invoking a socket/transport API, or making the receipt eligible under the existing
  live-study preregistration v2.
- A synthetic treatment-arm receipt path that loads the exact shipped Pi
  extension, performs one real `init` -> `checkpoint` -> `handoff_prepare` AWM
  transition in isolated temporary state, and derives an offline HMAC-committed
  public projection without disclosing private AWM content. This is mechanism
  conformance only; it does not run a provider or claim an agent-quality,
  productivity, comparative-performance, or machine-safety improvement.
- Public API compatibility policy, deprecation-warning helper, and an exact
  function-collision CI ratchet.
- Documentation index, CODEOWNERS, and Dependabot configuration.
- Candidate paired-control execution-certification drivers and CI/release gates
  for pinned Gemini, Codex, Claude Code, and GitHub Copilot CLIs across
  `Darwin-arm64-none`, `Darwin-x86_64-none`, and `Linux-x86_64-glibc`, with exact
  native runtime identities. The source and workflow definitions do not claim
  final-candidate Intel macOS or Linux execution; those claims require their
  green evidence artifacts. Claude uses a fixed synthetic bearer accepted only
  by its loopback fixture; no user credential is supplied.
- A combined native four-host AWM-chain certifier and strict evidence schema.
  It proves one hidden value crosses fresh, separate Gemini, Codex, Copilot,
  and Claude host state through exactly one low-risk allowed tool action per
  host. Every positive certificate binds an exact missing-predecessor probe,
  whole-document context/handoff budgets, runtime versions, shared execution
  boundaries, and loopback request-body hygiene.
- A path-free fresh-shell onboarding certifier and workflow gates for the exact
  24-lane matrix of four enforced hosts, three advertised platforms, and
  Bash/zsh. A workflow definition is not a claim that a newly added lane is
  green. Tagged release assembly binds every successful lane to the final
  archive while keeping these short-lived gate artifacts outside the durable
  native safety/AWM bundle.
- An explicit-source managed-host lifecycle for Codex, Claude Code, and GitHub
  Copilot CLI. `--download` acquires only the exact SRI-pinned registry closure
  through a bounded anonymous same-descriptor verifier; `--package-dir` stays
  offline. Neither path invokes npm, package scripts, or vendor code, and both
  authenticate the complete direct-native payload before dry-run cleanup or
  atomic publication. Removal moves an authenticated generation to recoverable
  private quarantine and returns its exact preselected ID, including in
  uncertain interruption/failure recovery output; offline restore
  re-authenticates that current generation and atomically republishes the same
  inode only when the active target is absent.
- A first-party Pi package with a canonical-policy Bash wrapper, seven native
  tools, the `mainframe` skill and slash command, guarded registry execution,
  private hash-only command auditing, and a transactional `mainframe pi`
  lifecycle manager that preserves unrelated settings, records one canonical
  package source in a private receipt, migrates stale and legacy roots, and
  supports verified rollback-safe removal before MAINFRAME uninstall.
- A read-only `mainframe pi doctor` and machine-readable exact
  package/version/platform compatibility manifest. The external doctor never
  starts Pi; `/mainframe doctor` is the separate in-process proof for the
  canonical package, seven tools, three hooks, protected Bash, and verified
  safety gate.
- A canonical `mainframe invoke <canonical-id> --input-json <object>` broker
  for the 26 reviewed stable-core contracts in
  `config/invocation-policy.json`, with closed named-input schemas,
  manifest-bound owners and argument shapes, clean-child execution, time and
  output confinement, process-group termination, private value-redacted audit
  records, and a strict `broker-json-v1` adapter envelope.

### Changed

- Replaced the shipped legacy v6 feature comparison and its unsupported
  outcome claims with a current, claim-verified buyer guide that distinguishes
  MAINFRAME from raw shells, host-native controls, and OS isolation.
- Promoted discovery-only `mainframe setup --project .` and the Pi doctor/dry-run
  branch to the README, top-level help, and AI integration guide. Setup now
  prints only actionable Pi steps when Pi has not created its user directory.
- Guided setup and human host status now close the missing-runtime handoff with
  state-aware online/offline managed acquisition commands and exact protected
  setup follow-up. Corrupt state remains diagnosis-only, and unsupported
  managed routes are never presented as installable.
- Homebrew caveats and CLI uninstall guidance now require deactivating every
  onboarded project as well as detaching Pi before removing the keg, avoiding
  stranded fail-closed project hooks and dangling Pi package paths.
- Runtime lifecycle mutation is reserved for a human terminal: the canonical
  gate blocks MAINFRAME source update, confirmed release upgrade, explicit
  `--yes`, and Homebrew upgrade/uninstall routes, while the Pi extension exposes
  status/dry-run guidance and blocks in-agent Pi install, setup, removal, and
  MAINFRAME uninstall. Project package overrides fail closed,
  package filters that suppress bundled resources are repaired explicitly, the
  audit path follows `PI_CODING_AGENT_DIR`, and Homebrew records its stable
  `opt_libexec` source across formula upgrades.
- MAINFRAME CLI uninstall now fails closed when an advertised Pi lifecycle
  payload is incomplete or attached. The Homebrew formula prints an atomic
  detach-then-uninstall command and discloses Homebrew's unavoidable lack of a
  Formula uninstall-preflight hook.
- Pi now scrubs inherited Bash startup, exported-function, language-loader, and
  dynamic-loader variables before its initial agent Bash and `user_bash`
  processes, closing the pre-wrapper `BASH_ENV` execution window.
- Pi readiness no longer collapses host compatibility, disk configuration, and
  live activation into one optimistic status. Unlisted versions/platforms fail
  closed as `COMPATIBILITY_UNVERIFIED`, the known legacy RPC gap is `LIMITED`,
  and only a certified canonical package loaded in the current Pi process can
  report `READY`.
- Pi stable-core execution and the public MCP runner now delegate by canonical
  ID to the shared invocation broker. The MCP executable exposes exactly the
  26 reviewed stable-core tools and rejects legacy tier configuration. Pi's
  human-confirmed non-stable-core path remains legacy/unbrokered.
- Node.js and Python canonical/public function calls now use the same reviewed
  broker contracts; their raw Bash APIs remain explicitly trusted escape
  hatches. Managed-launcher discovery precedes stale legacy roots, while an
  invalid explicit root or Bash override fails closed.
- The broker now reads bounded JSON through EOF without Bash string rewriting,
  rejects duplicate keys, literal NUL, delayed trailing bytes, and oversized
  requests, enforces result-kind output semantics, and tears down descendants
  on completion or termination. Pi no longer copies raw function arguments
  into progress, result, or audit metadata.

- Release publication code is tag-only and fail-closed for exact asset
  inventory and post-publication attestation verification. A reviewer-protected
  environment, immutable-release policy, and protected release tags remain
  repository-administrator prerequisites; source code does not configure them.
- Local release preparation now requires exact FUNCTIONS, MANIFEST, LSP, and
  exported host-policy parity before producing candidate artifacts.
- CI and local test setup now bind Bats libraries, `uv`, and the GNU Bash 4.4
  compatibility lane to reviewed versions and digests instead of moving
  dependency branches or installer scripts.
- Historical value-proof and technical-report drafts with unverified outcome
  figures are repository-only research: release payloads exclude them, and the
  public-claim gate rejects those figures if they return to current guidance.
- The full `bin/mainframe` command is now the canonical installed CLI; the root command remains a compatibility launcher.
- Versioned bootstrap now verifies complete inner-manifest coverage, defers
  optional shell/agent-discovery writes until after health verification, and
  writes a private receipt only for an exact, healthy installed runtime.
- Versioned bootstrap now resumes only exact journal-bound payload and CLI-link
  identities after tested process interruption, rejects same-target link
  replacement, and reports optional setup failures as receipt-backed partial
  success with an exact setup-only retry command.
- `mainframe update` is now reserved for clean, main-branch source checkouts
  and uses fetch plus fast-forward-only merge; receipt-backed releases use
  `mainframe upgrade`, while Homebrew retains package-manager ownership.
- The README now leads with Agent Working Memory, its safety boundary, and a reproducible first-use path.
- Guided setup and launch now distinguish an executable name from a compatible
  host: the exact pinned native-certification version and host-specific
  capability surface must match before launch, so legacy same-named CLIs fail
  closed instead of silently ignoring current instructions or hooks.
- Release preparation reads `VERSION`, validates generated state, and does not publish from the local `make release` command.
- Language binding documentation describes source installation until registry packages are published.
- Canonical function ownership no longer depends on loader order for
  `format_date`, `http_headers`, core string predicates, or absolute/relative
  path predicates. The tracked duplicate-name inventory is reduced from 97 to
  90 and may only decrease.
- AWM context and handoff token budgets now cover the complete artifact with
  exact byte/token metadata, and the CLI fast path preserves config-file
  profile and library precedence.
- File-backed AWM locking now prefers kernel-released `flock` on Linux and BSD
  `lockf` on macOS. The portable `mkdir` fallback times out fail-closed instead
  of attempting an ABA-prone stale pathname recovery.
- Managed host hooks now contain one machine-independent `/bin/bash -p`
  bootstrap. `mainframe launch` supplies reviewed absolute Bash, supported
  system/package-manager jq, installed gateway, and installed safety-policy
  paths plus their four-digest SHA-256 seal at runtime. Every hook invocation
  verifies those byte identities; starting a configured host directly leaves
  the hook fail-closed, and `mainframe agent-hook` remains a diagnostic
  interface.
- Host discovery authenticates exact entrypoint, native executable, and npm
  package-tree bytes without executing an untrusted candidate for version or
  help output. npm tree hashing rejects arbitrary PATH Node shims, accepts
  supported system/package-manager/version-manager layouts, and hashes and
  rechecks Node plus the JavaScript hasher around authentication and before
  exec. A user-managed Node is not presented as an external trust anchor; the
  Python implementation remains an independent development certifier.
- Protection status no longer treats a directly callable canary as proof that
  a native host loaded its hook. Runtime loading remains `UNVERIFIED` until a
  native-host control/protected execution certificate proves it.

### Fixed

- Bash installs now use one idempotent `~/.bashrc` runtime block plus a narrow
  managed login-profile bridge, so genuine login and interactive non-login
  shells both discover MAINFRAME without duplicating `PATH`. Install and
  uninstall refuse malformed or overlapping markers and preserve foreign
  profile content.
- Runtime purge now removes only byte-identical checksum-owned files and
  preserves every unmanaged or modified in-root file beside the installation;
  erasing all in-root state requires the separate `--purge-state` flag, and the
  uninstaller warns that project hook files require project-level deactivation.
- `mainframe doctor` and the full runtime now tolerate agent/minimal shell
  environments where `USER` and `LOGNAME` are unset, deriving a safe account
  name only when healing guidance needs one.
- Canonical manifest/LSP checks now detect stale checked-in artifacts instead
  of validating only a fresh in-memory reconstruction.
- Host-policy export preserves all 43 source rules, including executable-word
  markers, structured `rm` flag tiers, dynamic-evaluation denial, inline Git
  aliases, raw-device redirects, and the marker-aware fork-bomb matcher. The
  10.2 runtime payload ships both `security/gate-rules.json` and its declared
  `security/gate-normalizer.mjs`; 163 corpus cases prove Bash/JavaScript tier
  parity through that normalizer-backed contract.
- Project AWM bindings reject path disclosure, unsafe modes, symbolic-link
  redirection, malformed mappings, and same-ID cross-namespace resolution.
- Managed project AWM now follows agents through nested working directories
  across all seven activation hosts while preserving explicit subprojects,
  private-mapping continuity, and nested Git repository boundaries.
- Project AWM `session` and `status` lookups are now strictly read-only, report
  unsafe existing bindings as invalid, and reject control characters in the
  private storage root before filesystem access.
- Project AWM rejects malformed common options and invalid action grammar
  before creating a mapping; `--` explicitly protects flag-looking data.
- Gate-policy `--check`, `--verify`, and `--help` modes are read-only, so an
  enforcement check cannot silently invalidate release checksums.
- Installer repository URLs, in-place clone handling, shell configuration, and CLI path resolution.
- Release install and upgrade locks now verify exact atomic owner publication;
  directory-shaped collisions and live owners fail closed on macOS and Linux.
- Upgrade recovery rejects broad, noncanonical, traversing, symbolic, and
  transaction-external paths, and verifies the restored receipt, manifest,
  version, and doctor result before clearing its journal.
- Release upgrade now rejects or safely restores directory-substitution races
  at both candidate and old-runtime placement, and its health probes accept
  valid CLIs with large trailing version output without `pipefail`/SIGPIPE
  false failures.
- The `array_join` export collision that changed its documented signature after loading `lib/common.sh`.
- The remaining 11-function array collision family now has one loader-stable
  public contract: historical `array_*` names retain the documented
  `pure-array` behavior, named-array variants use `collection_*`, and the
  bounds-checked variant is `safe_array_get`. The collision ratchet falls from
  90 total/81 public to 79 total/70 public, including lazy and selective loads.
- The three-function AWM collision family now has one loader-stable durable
  facade: `awm_compress`, `awm_handoff_prepare`, and `awm_handoff_accept`
  remain owned by `lib/awm.sh`; the distinct legacy behaviors are available as
  `awm_stream_compress`, `awm_protocol_handoff_prepare`, and
  `awm_protocol_handoff_accept`. The collision ratchet falls from 79 total/70
  public to 76 total/67 public across default, selective, lazy, and load-all
  paths.
- Ambiguous `mainframe help` lookups now report competing registry owners and
  fail clearly instead of concatenating incompatible records.
- The overwritten same-file `template::render` definition.
- Node.js binding execution on macOS systems whose `/bin/bash` is too old for MAINFRAME.
- Binding function-name and source-library validation so caller input cannot become shell syntax.
- The scheduled-CI uptime wrapper test, which compared two advancing clock reads for exact equality.
- Stale supported-version, Bash-version, package-availability, test-count, and dependency claims in current documentation.
- AWM arithmetic-expression injection in public numeric arguments, relative or
  symbolic-link-ancestor roots, concurrent category/compression data loss, and
  permanently stale macOS mkdir locks.
- Agent-gateway execution now ignores inherited Bash startup state, exported
  shell functions, and project-controlled `PATH` tools, normalizes every
  bootstrap or gateway error to a blocking status, and writes the decision
  through a pre-opened, validated audit descriptor.
- Protected launch now removes inherited passive Bash, Node.js, Perl, and
  `LD_*`/`DYLD_*` code-loader variables before runtime helpers, package-tree
  authentication, and host exec. This protection begins after the initial
  `/bin/bash` interpreter and its operating-system loader have already started;
  it cannot undo code loaded before MAINFRAME's first instruction.
- Dynamic shell evaluation patterns now fail closed in both Bash and exported
  JavaScript policy. Sequential post-launch replacement of the bound Bash,
  `jq`, gateway, or safety-policy bytes is detected by the launch seal. This is
  deliberate mistake/tamper detection, not a same-UID sandbox guarantee.

## 10.1.0 - 2026-07-21

- Expanded Agent Working Memory, safety-gate, integration, and registry surfaces.
- Added release SBOM, checksum, and provenance preparation.
- Added selective loading guidance for short-lived agent commands.

See the [v10.1.0 GitHub release](https://github.com/gtwatts/mainframe/releases/tag/v10.1.0) for the published release record.

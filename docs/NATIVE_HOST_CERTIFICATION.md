# Native Host Execution Certification

Static hook configuration is necessary, but it is not proof that a coding
agent loaded the hook or routed a shell call through it. MAINFRAME's native
host certifier launches a pinned, published host CLI in a disposable project
and proves the complete pre-execution path.

Gemini CLI, Codex CLI, Claude Code, and GitHub Copilot CLI are the implemented
drivers. The Codex driver pins the stable npm-distributed `@openai/codex` CLI
at exactly 0.146.0; the Claude driver pins Anthropic's stable
`@anthropic-ai/claude-code` release at exactly 2.1.220; and the Copilot driver
pins `@github/copilot` at exactly 1.0.78.

## What the Gemini gate proves

The certifier builds the current deterministic MAINFRAME archive, verifies its
SHA-256 sidecar, rejects unsafe archive entries, installs that archive into an
isolated home, and runs `mainframe doctor`. It then uses Gemini CLI 0.53.1's
first-party `--fake-responses` mechanism, so no model account or external model
credential is needed.

Two otherwise equivalent native runs make marker absence meaningful:

1. The **control** project has MAINFRAME instructions but no enforcement hook.
   Gemini must execute the disposable `tofu destroy -auto-approve` sentinel
   exactly once.
2. The **protected** project is activated with `--enforce`. Gemini must load
   the project `BeforeTool` hook, report MAINFRAME's denial, continue its model
   loop, create exactly one private audit record, and never execute the
   sentinel.

The sentinel is a temporary executable placed first on an isolated `PATH`; it
does not invoke OpenTofu, Terraform, or any infrastructure service. The audit
record contains only host, event, tool, risk, rule, and decision metadata. The
raw command and random marker nonce are excluded from the evidence artifact.

## What the Codex gate proves

The Codex driver applies the same archive-install and paired-control proof to
the published `@openai/codex` CLI. It verifies the 0.146.0 JavaScript launcher
with its npm integrity and digest, plus the exact Darwin or Linux platform
package selected for the runner with its npm integrity and native executable
digest. A separate tree digest covers the combined wrapper-plus-platform
snapshot that Codex actually executes.

For Codex, the certifier starts a fresh loopback-only Responses API fixture on
`127.0.0.1` for each paired run. Each server accepts exactly two
credential-free requests: the first returns one `exec_command` call with the
exact disposable sentinel in its `cmd` field. The second returns the
completion text only after Codex submits the matching `function_call_output`.
Credential headers, unexpected paths, extra requests, and an incorrect
protected-run denial are rejected. No external OpenAI or model-provider
credential is supplied. Startup update checks, in-app updates, web search,
apps, plugins, analytics, feedback, telemetry exporters, and request
compression are disabled for the disposable proof. Strict config parsing makes
unknown or renamed settings fail instead of silently weakening that isolation.

The fixture materializes both the disposable `tofu` sentinel and certified
Bash as absolute paths, explicitly supplies that Bash in the `exec_command`,
sets `allow_login_shell=false`, clears shell snapshots, and supplies
`BASH_ENV=/dev/null`. Codex therefore runs the sentinel with the
certifier-selected non-login Bash; user login/profile files are not loaded,
and PATH changes cannot redirect the sentinel.

The control run must execute the sentinel exactly once. The protected run must
load the generated Codex `PreToolUse` / `Bash` hook, return MAINFRAME's denial
to the CLI, complete the fixture loop, emit exactly one private audit record,
and execute the sentinel zero times.

Headless certification passes Codex's `--dangerously-bypass-hook-trust` flag
only so the already-vetted generated hook can run without a persisted
interactive trust decision in the disposable workspace. The flag bypasses
Codex's separate hook-trust prompt; it does not bypass MAINFRAME's decision,
disable the hook, or make an unreviewed hook safe. Normal user activation must
still review and trust the exact entry with Codex's `/hooks` UI.

The 0.146.0 certifier deliberately uses an empty isolated `CODEX_HOME` instead
of `--ignore-user-config`: in this version, that flag also suppresses the
project `.codex/hooks.json`. Do not launch a protected project with
`--ignore-user-config` and infer that MAINFRAME's hook is still enforced.

## What the Claude gate proves

The Claude driver applies the same installed-archive and paired-control proof
to the published `@anthropic-ai/claude-code` release. It validates the root
package and selected platform package against exact npm integrities and
canonical tree digests. The lock and host manifest also pin the exact version
and npm integrity for all six Darwin/Linux optional-platform dependencies,
without claiming their uninstalled package trees were executed or rehashed on
the current runner.

The selected executable digest and release metadata are repository pins derived
from Anthropic's signed 2.1.220 release manifest. Evidence records the pinned
manifest, detached-signature, signing-key fingerprint, release commit, and
build-date values for traceability. The certifier does not refetch those
upstream files or repeat detached-signature verification during each run, so
the repository pins remain part of the trusted certification input.

The npm install runs with lifecycle scripts disabled. The certifier therefore
invokes the selected optional platform package's native `claude` binary
directly from a private read-only snapshot. It records that launch mode and
that `cli-wrapper.cjs` was not executed. This proves the native binary and
MAINFRAME hook path; it does not certify npm postinstall copying, the root
stub, `.bin/claude`, or the fallback wrapper.

Each run uses fresh `HOME`, `CLAUDE_CONFIG_DIR`, and XDG directories. Claude
runs in print mode with only the project settings source, a strict empty MCP
configuration, only the `Bash` execution tool, `dontAsk` permission mode, and
an exact allow rule for the disposable sentinel. The driver does not use
`--bare` or `--safe-mode`, because those modes disable project hooks. Because
managed settings outrank both project and CLI settings, the driver also fails
closed if it detects Claude's documented system files, drop-in directory,
organization `CLAUDE.md`, managed MCP file, or macOS managed-preferences
domain.

For each paired run, a loopback-only Anthropic Messages fixture accepts exactly
two streaming requests. It requires one fixed synthetic bearer and rejects
API-key or OAuth credential headers; no user or real Anthropic credential is
supplied. The first response requests the exact PATH-first
`tofu destroy -auto-approve` sentinel. The second completes only after Claude
returns the matching successful control result or exact protected hook denial.
The synthetic bearer, raw command, and marker nonce are excluded from evidence.

The control project must execute the sentinel exactly once. The protected
project contains only MAINFRAME's generated `PreToolUse` / `Bash` hook; Claude
must emit one hook-start event, one exit-2 hook response containing MAINFRAME's
denial, one matching private audit record, and zero sentinel executions.

Claude print mode disables workspace-trust verification, which the evidence
records explicitly. Interactive users must still accept Claude's normal
workspace-trust prompt, restart or enter the activated project, inspect the
hook, and run a controlled canary. Loopback routing and disabled nonessential
traffic constrain this deterministic proof, but they are not an OS-enforced
network sandbox.

## What the Copilot gate proves

The Copilot driver applies the same installed-archive and paired-control proof
to the published `@github/copilot` CLI. It verifies the npm wrapper, its
`detect-libc` dependency, and the exact Darwin, Linux glibc, or Linux musl
native package selected by the official launcher. The evidence binds npm
integrities, the launcher and native executable digests, and a canonical hash
of the private wrapper-plus-dependency-plus-platform runtime that actually ran.

Each run uses a fresh `COPILOT_HOME`, an exact `trustedFolders` entry for only
that disposable project, and Copilot's supported default repository-hook path.
The certifier does not force an internal hook feature flag. This trust seed is
necessary because noninteractive prompt mode skips repository hooks for an
untrusted folder; normal users must trust the project through Copilot's own
workflow before relying on its hooks.

Copilot runs with `COPILOT_OFFLINE=true`, a loopback-only OpenAI-compatible
Chat Completions provider, only the `bash` tool available, built-in MCP servers
disabled, and remote, update, custom-instruction, and Bash-environment loading
disabled. The fixture accepts exactly two streaming requests per run. It first
returns one `bash` call for the PATH-first disposable
`tofu destroy -auto-approve` sentinel, then completes only after Copilot returns
the matching tool result. No provider or GitHub credential is supplied. The
stable CLI currently emits an empty `Authorization: Bearer` placeholder; the
fixture permits only an absent or empty placeholder and rejects any non-empty
authorization or API-key header.

The control project has the same instructions and project trust but no hook;
Copilot must report a successful `bash` tool completion and execute the marker
exactly once. The protected project contains the canonical
`.github/hooks/mainframe.json`; Copilot must report the exact generic denial
`Denied by preToolUse hook: hook exited with code 2`, create one private
MAINFRAME audit record, and execute the marker zero times. The generic host
message is linked to MAINFRAME by that exact audit tuple and the generated hook
digest.

Copilot documents nonzero command-hook exits as fail-closed for `preToolUse`,
but hook timeouts as fail-open. The certificate proves the prompt-mode call
completed before timeout on the pinned CLI and runner; it does not turn this
host mechanism into an operating-system sandbox.

## What the four-host AWM chain proves

The destructive-command gates above answer whether MAINFRAME can stop one
known high-risk shell call. The separate AWM-chain certifier tests the other
half of the product contract: whether pinned native agents can use one safe
shell action each to carry useful state forward without exposing that state in
the published evidence.

One caller-supplied MAINFRAME archive and its adjacent SHA-256 sidecar are
verified, safely extracted, and installed exactly once. The certifier creates
one project-local file-backed AWM session with a 256-bit random seed confined
to the harness, private AWM store, and in-memory loopback request guards. It
then launches Gemini, Codex, Copilot, and Claude with fresh, separate host state
in that order. Every host receives the same static shell command and must:

1. read only its expected predecessor checkpoint;
2. derive and write its own attributed checkpoint;
3. pass the installed MAINFRAME gateway as exactly one `low / none / allow`
   action; and
4. emit the host-specific success event expected by the native driver.

The project, installation, AWM root/session, operating-system user, and
`TMPDIR` are intentionally shared; this is not process, container, or user
isolation. Each host instead receives a separate home, config, state, and cache
directory. Only that host's reviewed hook is staged immediately before launch,
preventing compatible hook formats from being loaded twice by another CLI.
After Claude, the certifier requires the ordered five-checkpoint provenance
chain, validates private modes with `awm doctor`, and creates bounded final
context and handoff artifacts. It verifies whole-document byte/token math,
provenance, inclusion of the final chain value, nested-context structure, and
byte equality between the returned and persisted handoff. Those private
artifacts and checkpoint values are represented in public evidence by hashes
and structural facts only; raw values, credentials, provider requests,
absolute private paths, and run logs are excluded.

Every positive certification invocation also launches a fresh Codex state
after Gemini with a deliberately missing predecessor. The loopback provider
must observe exactly two requests and the exact missing-key result; the tool
must exit 42 without writing its checkpoint, and no later host may start before
that rejection. Only then does the certifier launch the positive Codex state
and continue the chain. `--negative-wrong-predecessor` exposes the same probe
as a standalone diagnostic that skips the positive path and emits no evidence.
This makes the positive certificate itself a dependency proof rather than four
independent canned writes.

The provider fixtures bind their requests to a call ID and the static command
digest. The installed gateway audit format currently proves the host/event/
tool/policy tuple but does not include that digest or call ID, so the evidence
records gateway command correlation as unavailable instead of claiming it.
The Codex, Copilot, and Claude loopback servers reject raw seed/checkpoint
values and the exact AWM root in request bodies and persist only safe counters,
booleans, and reason enums. Native coding agents normally send disposable cwd
or configuration-path metadata to their provider; the certificate records
that those paths may be observed and does not mislabel them as secret. The
private AWM root and values remain the enforced boundary.

The AWM chain does not prove provider inference quality, arbitrary-agent
planning, cross-user secrecy, or safe execution of commands outside the
configured hook path. The file backend is local-user private, not an operating
system sandbox or authorization service.

## Run it locally

Requirements are Bash 4.4+, `jq`, Python 3.10+, Git, and npm. Gemini and Codex
require Node.js 20+; the Claude and Copilot npm installations and certificates
require Node.js 22+:

Every direct certificate command performs its own native-platform admission
before it inspects optional host packages or starts a disposable workspace. On
Darwin it rejects Rosetta and an x86 process on Apple Silicon. The selected
Bash, Node runtime, and native host executable are read from one descriptor,
checked as 64-bit Mach-O or ELF for the admitted process architecture, rejected
when group- or other-writable, and rebound after the run before evidence is
written. The privileged gateway Bash and jq receive the same admission and
final recheck, and revalidation after initial host admission uses a private,
read-only snapshot of the release-bound validator. Shell onboarding applies
the same admission to its selected Bash or zsh and the Bash that executes
MAINFRAME. These are pre/post pathname-byte
bindings; they do not establish isolation from a concurrent process under the
same local account, physical Linux hardware, or absence of virtualization.

```bash
npm ci --prefix scripts/dev/native-host \
  --ignore-scripts --no-audit --no-fund

scripts/dev/certify-native-host.sh gemini
scripts/dev/certify-native-host.sh codex
scripts/dev/certify-native-host.sh claude
scripts/dev/certify-native-host.sh copilot
```

To certify the usefulness chain, first build or obtain one candidate archive
and its adjacent `.sha256` sidecar. The positive run includes its own bound
wrong-predecessor probe:

```bash
archive="dist/mainframe-$(tr -d '[:space:]' < VERSION).tar.gz"

scripts/dev/certify-native-awm-chain.sh \
  --archive "$archive" \
  --output dist/native-awm-chain-evidence.json
```

For a standalone no-evidence diagnostic, use a fresh output pathname and add
`--negative-wrong-predecessor`. The certifier refuses to overwrite any
pre-existing output, including a prior positive certificate.

The combined certifier never regenerates release metadata. This keeps the
certified archive an explicit immutable input and prevents a test run from
silently changing the bytes it claims to cover.

On macOS, select the Homebrew Bash explicitly when needed:

```bash
MAINFRAME_BASH="$(brew --prefix bash)/bin/bash" \
  "$(brew --prefix bash)/bin/bash" \
  scripts/dev/certify-native-host.sh gemini

mainframe_bash="$(brew --prefix bash)/bin/bash"
MAINFRAME_BASH="$mainframe_bash" "$mainframe_bash" \
  scripts/dev/certify-native-awm-chain.sh \
  --archive "$archive" \
  --output dist/native-awm-chain-evidence.json
```

The default evidence paths are `dist/native-host-gemini-evidence.json`,
`dist/native-host-codex-evidence.json`,
`dist/native-host-claude-evidence.json`, and
`dist/native-host-copilot-evidence.json`; the combined default is
`dist/native-awm-chain-evidence.json`. Use `--archive PATH` to certify an
existing candidate and its adjacent `PATH.sha256`, `--output PATH` to select an
evidence destination, or `--keep-workdir` to retain diagnostic logs. Evidence
destinations are no-clobber. Failed runs retain their private diagnostic
workspace and do not emit a successful certificate.

Release CI also passes `--prepare-release-metadata`. That option records the
checkout commit and clean/dirty state first, then regenerates the deterministic
SBOM/checksum inputs with the commit's source epoch before building. It cannot
be combined with `--archive`; supplied archives remain deliberately unbound to
the certifier checkout.

## Evidence contract

Successful Gemini evidence conforms to
`scripts/dev/native-host/evidence.schema.json`; Codex evidence conforms to
`scripts/dev/native-host/codex-evidence.schema.json`; Claude evidence conforms
to `scripts/dev/native-host/claude-evidence.schema.json`; and Copilot evidence
conforms to `scripts/dev/native-host/copilot-evidence.schema.json`. All four
record:

- `certification: execution-certified`;
- the exact host and MAINFRAME versions, npm package integrity, canonical
  package-tree identity, and host executable identity;
- archive and generated hook-config SHA-256 digests;
- OS and architecture;
- whether the archive was built from the current workspace or supplied as an
  external input; workspace commit/dirty state is informational only, and an
  external archive is deliberately not attributed to the certifier checkout;
- one control execution and zero protected executions.

The combined usefulness evidence conforms to
`scripts/dev/native-host/awm-chain-evidence.schema.json`. It binds the one
installed archive, selected native runtime identities, fixture digests,
Darwin/Linux platform, shared private AWM session, ordered host positions,
single low-risk gateway allow per host, measured host versions, exact
context/handoff budget and persistence proofs, request-body hygiene, truthful
shared/separate execution boundaries, and the positive-bound fail-closed
wrong-predecessor receipt.

Gemini requires exactly one `gemini / BeforeTool / run_shell_command / high /
terraform-destroy / deny` audit tuple with file mode `0600`. Codex additionally
records the selected platform package, launcher and fixture digests, exactly
two loopback Responses requests per run (four total), and exactly one `codex / PreToolUse / Bash /
high / terraform-destroy / deny` audit tuple with file mode `0600`.

Claude additionally records the selected native platform package, direct
binary launch mode, root/platform/runtime tree identities, repository-pinned
upstream release metadata, fixture and fixture-server digests, print-mode trust
boundary, synthetic-bearer credential mode, and exactly two loopback Messages
requests per run (four total). Its protected run requires one `claude /
PreToolUse / Bash / high / terraform-destroy / deny` audit tuple with file mode
`0600`.

Every safety certificate records the normalized host `system_libc` value
(`none` on Darwin, `glibc` or `musl` on Linux). Copilot and Claude retain their
legacy `libc` field and require it to equal `system_libc`. Copilot additionally
binds OS, architecture, and libc as one platform identity; its wrapper
dependency, selected native package, launcher,
fixture, and runtime-tree identities; exact isolated-project trust mode; two
Chat Completions requests per run (four total); and one `copilot / PreToolUse /
bash / high / terraform-destroy / deny` tuple with file mode `0600`.

The workflow defines separate `native-host-gemini`, `native-host-codex`,
`native-host-claude`, `native-host-copilot`, and `native-host-awm-chain` CI
jobs over the canonical candidate tuples `Darwin-arm64-none`,
`Darwin-x86_64-none`, and `Linux-x86_64-glibc`. A platform claim belongs to a
specific green workflow result, host executable digest, and archive digest;
the existence of the script or job alone is not a passing result. This
document does not claim that a newly added lane is already green remotely.

Tagged release builds are configured to require all four safety jobs and the
combined usefulness job, download the unique twelve safety artifacts plus three
platform-tuple AWM-chain artifacts, and require every evidence archive digest to
match the exact archive that is later attested and transferred to publishing.
That release binding does not itself claim that a public release containing
the new certificates already exists.

Each certifier copies its pinned runtime into a private, read-only workspace and
rehashes the executable inputs before use. Its direct entry point also admits
the current native process independently of the CI wrapper and rechecks the
selected executable-image bindings before evidence publication. Gemini records its complete package
tree. Codex records its wrapper launcher, native executable, and complete
wrapper-plus-selected-platform tree. Claude records its root package, selected
native platform package, direct executable, and complete root-plus-platform
tree. Copilot records its wrapper launcher, native executable, dependency
integrity, and complete wrapper-plus-dependency-plus-selected-platform tree.
Native runtime identity is therefore not reduced to a small launcher.

`mainframe protect status` intentionally continues to report
`Runtime load: UNVERIFIED`. A CI certificate for a pinned host version cannot
prove that an arbitrary user process has reloaded a changed project config.

## Shell-onboarding evidence

The separate `shell-onboarding` matrix exercises Bash and zsh for each of the
four enforced hosts on every advertised platform tuple. Each successful lane
writes one strict `shell-onboarding-evidence.schema.json` certificate containing
only the MAINFRAME version and archive digest, host, shell, actual OS,
architecture and system libc, `installed_payload: exact`, and
`runtime_load: unverified`. The closed schema has no path-valued field, and the
certifier records `private_paths_embedded: false` only after the installed,
fresh-shell, consent, privacy, AWM, rollback, native-platform admission, and
selected-shell/runtime-Bash binding checks finish.

For a tagged candidate, `release-build` is configured to download and validate
exactly 24 unique host/platform/shell certificates and require every
`archive_sha256` to equal the final release archive. These certificates are a
workflow release gate, not durable release assets: they are deliberately not
passed to `build-release-evidence.py` and are not members of the 16-file native
safety/AWM evidence bundle below. The workflow definition does not itself
claim that those lanes have already passed remotely.

## Durable release evidence

The tagged-release workflow is configured to publish two additional evidence
assets beside the runtime archive. This is a release-candidate contract, not a
claim that the assets are already public: use it only for a release whose GitHub
release page actually contains both files.

| Asset | Contents |
|---|---|
| `mainframe-X.Y.Z.release-evidence.json` | The schema-validated manifest that binds the release, archive, workflow run, certifier inputs, certificate inventory, and publication contract. |
| `mainframe-X.Y.Z.release-evidence.tar.gz` | A deterministic 16-file bundle containing a byte-identical `release-evidence.json` plus the fifteen certificate JSON files described by the manifest. |

The certificate inventory is exact, not a minimum:

- twelve safety certificates: Gemini, Codex, Copilot, and Claude on each of
  `Darwin-arm64-none`, `Darwin-x86_64-none`, and `Linux-x86_64-glibc`; and
- three four-host AWM-chain certificates: one run for each advertised tuple.

The release manifest preserves the AWM certificate's
`archive_origin: external-input` value. Matching that external archive's digest
to the release archive does not retroactively attribute the AWM run to its
certifier checkout.

### What is bound

`scripts/dev/native-host/build-release-evidence.py` creates and verifies this
contract fail-closed:

- **Archive:** exact name, media type, byte size, and SHA-256 for
  `mainframe-X.Y.Z.tar.gz`. The builder safely streams the final archive,
  rejects unsafe paths, duplicates, non-regular members, links, unsupported
  metadata, non-normalized modes/ownership/timestamps, and size-limit
  violations, and requires every certifier control file to be present.
- **Tag:** stable version, tag name and full ref, Git object format, exact tag
  ref object ID, peeled commit ID, and the commit timestamp used as
  `SOURCE_DATE_EPOCH`. The checkout `HEAD` must equal the peeled commit.
- **Workflow:** `.github/workflows/test.yml` must be byte-equal to the file at
  the peeled tag commit; its SHA-256, run ID, and run attempt are recorded.
- **Certifier inputs:** the sorted 45-file allowlist in
  `scripts/dev/native-host/certifier-inputs.json` covers the native safety,
  AWM, and shell-onboarding harnesses and schemas, fixtures, host/dependency
  pins, evidence validator, native-executable validator, safe
  extraction, deterministic archive controls, and the release-evidence builder,
  input definition, platform definition, and schema themselves. Every listed
  byte sequence must be equal across the peeled tag, working tree, and final
  runtime archive. The
  manifest records the definition digest, every file digest and role, and a
  canonical aggregate digest; the release-evidence schema is also referenced
  and hashed directly by the manifest.
- **Certificates:** each bundled certificate is schema-validated and hashed.
  Safety records must be `execution-certified`, cover exactly four hosts by the
  three advertised OS/architecture/system-libc tuples, identify a clean
  workspace build at the peeled tag commit, and match the release archive
  digest. AWM records must be `native-awm-chain-execution-certified`, cover each
  advertised tuple exactly once, remain `external-input`, and match that same
  archive digest. Missing, duplicate, mixed, or unadvertised tuples fail closed.
- **Bundle:** member names and order, regular-file type, mode `0644`, normalized
  ownership, commit-epoch timestamps, expanded/compressed limits, and canonical
  tar/gzip bytes are checked. The bundled manifest must be byte-identical to the
  separately published manifest, and all certificate records are recomputed
  from the bundled bytes.

The build job passes the manifest and bundle SHA-256 values to the protected
publish job. That job compares the transferred bytes to those values, reruns
the builder's `verify` command from the tag checkout, publishes both evidence
assets in the same immutable release, and verifies both release assets after
publication.

### Custom GitHub attestation

The build job uses GitHub's attestation service with this custom predicate type:

```text
https://github.com/gtwatts/mainframe/attestations/release-evidence/v1
```

The exact manifest is the predicate for three subjects: the runtime archive,
the manifest itself, and the certificate bundle. Build and publish jobs require
the signer workflow, peeled source commit, tag ref, and GitHub-hosted-runner
boundary, then compare the verified predicate object to the downloaded manifest
instead of accepting only a matching predicate-type string.

### Verify a release that contains the assets

Run this from a fresh temporary directory after substituting a release version
whose GitHub release page contains both evidence assets. It verifies GitHub's
immutable release assets, the custom attestation on all three subjects, the tag
and workflow bindings, the exact certifier-input graph, the canonical bundle,
and every bundled certificate:

```bash
release_version=X.Y.Z
release_tag="v$release_version"
export GH_REPO=gtwatts/mainframe

verify_root="$(mktemp -d)"
source_dir="$verify_root/source"
asset_dir="$verify_root/assets"
mkdir -p "$asset_dir"

git clone --no-checkout "https://github.com/$GH_REPO.git" "$source_dir"
git -C "$source_dir" fetch --force origin \
  "refs/tags/$release_tag:refs/tags/$release_tag"
tag_ref_sha="$(git -C "$source_dir" rev-parse "refs/tags/$release_tag")"
tag_commit="$(git -C "$source_dir" rev-parse "refs/tags/$release_tag^{commit}")"
git -C "$source_dir" checkout --detach "$tag_commit"

gh release download "$release_tag" --dir "$asset_dir" \
  --pattern "mainframe-$release_version.tar.gz" \
  --pattern "mainframe-$release_version.release-evidence.json" \
  --pattern "mainframe-$release_version.release-evidence.tar.gz"

archive="$asset_dir/mainframe-$release_version.tar.gz"
manifest="$asset_dir/mainframe-$release_version.release-evidence.json"
bundle="$asset_dir/mainframe-$release_version.release-evidence.tar.gz"

gh release verify "$release_tag"
gh release verify-asset "$release_tag" "$archive"
gh release verify-asset "$release_tag" "$manifest"
gh release verify-asset "$release_tag" "$bundle"

predicate_type="https://github.com/gtwatts/mainframe/attestations/release-evidence/v1"
for subject in "$archive" "$manifest" "$bundle"; do
  verification="$(gh attestation verify "$subject" \
    --repo "$GH_REPO" \
    --predicate-type "$predicate_type" \
    --signer-workflow "$GH_REPO/.github/workflows/test.yml" \
    --source-digest "$tag_commit" \
    --source-ref "refs/tags/$release_tag" \
    --deny-self-hosted-runners \
    --format json)"
  jq -e --arg predicate_type "$predicate_type" --slurpfile manifest "$manifest" '
    any(.[].verificationResult.statement;
      .predicateType == $predicate_type and .predicate == $manifest[0])
  ' <<<"$verification" >/dev/null
done

python3 "$source_dir/scripts/dev/native-host/build-release-evidence.py" verify \
  --repo-root "$source_dir" \
  --repository "$GH_REPO" \
  --version "$release_version" \
  --tag "$release_tag" \
  --tag-ref "refs/tags/$release_tag" \
  --tag-ref-sha "$tag_ref_sha" \
  --tag-commit-sha "$tag_commit" \
  --workflow-run-id "$(jq -er '.release.workflow.run_id' "$manifest")" \
  --workflow-run-attempt "$(jq -er '.release.workflow.run_attempt' "$manifest")" \
  --source-date-epoch "$(jq -er '.release.source_date_epoch' "$manifest")" \
  --archive "$archive" \
  --manifest "$manifest" \
  --bundle "$bundle"
```

The final command emits JSON with `status: valid` and the verified manifest and
bundle SHA-256 values. The builder itself is one of the 45 bound control files;
a modified worktree verifier fails the tag/worktree/archive byte-equality check.

## Boundary

These gates prove installed-host hook discovery, native payload compatibility,
MAINFRAME policy evaluation, denial propagation, and absence of sentinel
execution for the exact pinned CLI, archive, executable, and platform in the
evidence. Deterministic fake or loopback responses replace provider inference;
therefore the gates do not prove a real model-provider call or model quality.

The release manifest and custom attestation make the evidence durable and
tamper-evident; they do not add a second certifier. The same GitHub Actions
builder collects the certificates, creates the predicate, and requests the
attestation. Verification therefore remains inside GitHub-hosted Actions,
GitHub OIDC/attestation, repository, tag, and pinned-workflow trust. It is not an
independent witness and proves nothing outside that builder trust boundary.

The release evidence also does not prove that an interactive user accepted a
host's project or hook trust prompt, or that the user's currently running host
loaded the hook. Those checks remain local onboarding requirements. AWM remains
an `external-input` certificate even when its archive digest equals the release
archive.

The Codex result is specifically for the npm-distributed `@openai/codex` CLI;
the Claude result is specifically for the pinned optional-package native
binary from `@anthropic-ai/claude-code`; and the Copilot result is specifically
for the npm-distributed `@github/copilot` CLI. They do not certify Codex
Desktop, the ChatGPT app, Claude's npm postinstall or wrapper launch paths,
GitHub.com agent sessions, IDE Copilot extensions, a live model service,
arbitrary third-party hooks, or another host integration. No gate turns the
hook into an operating-system or network sandbox. Processes or tools that
bypass the configured host event remain outside MAINFRAME's control.

Host references:

- [Gemini CLI configuration and `--fake-responses`](https://geminicli.com/docs/reference/configuration/)
- [Gemini CLI hook reference](https://geminicli.com/docs/hooks/reference/)
- [Pinned Gemini hook integration tests](https://github.com/google-gemini/gemini-cli/blob/v0.53.1/integration-tests/hooks-system.test.ts)
- [Codex hooks](https://developers.openai.com/codex/hooks)
- [Codex custom model providers](https://developers.openai.com/codex/config-advanced/#custom-model-providers)
- [Pinned Codex hook integration tests](https://github.com/openai/codex/blob/rust-v0.146.0/codex-rs/core/tests/suite/hooks.rs)
- [Claude Code hooks](https://code.claude.com/docs/en/hooks)
- [Claude Code CLI reference](https://code.claude.com/docs/en/cli-usage)
- [Claude Code permissions and workspace trust](https://code.claude.com/docs/en/permissions)
- [Claude Code environment variables](https://code.claude.com/docs/en/env-vars)
- [Copilot CLI offline mode](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli#offline-mode)
- [Copilot CLI BYOK providers](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-byok-models)
- [Copilot CLI hooks](https://docs.github.com/en/copilot/reference/hooks-reference)
- [Pinned Copilot CLI release](https://github.com/github/copilot-cli/releases/tag/v1.0.78)

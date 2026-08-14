# Homebrew Formula Candidate (Unpublished)

This directory contains build and test inputs for a future MAINFRAME Homebrew
tap. It is **not a published installation path**. No `brew install` command in
this document is currently offered to users, and the generated formula must not
be copied to a public tap until every publish gate below passes.

As audited on 2026-08-04, no accessible `gtwatts/homebrew-mainframe` tap was
found. The planned v10.2.0 formula is a source candidate, not a publication
claim. Public v10.1.0 also lacks the full runtime archive and release-evidence
assets required by this candidate process.

Homebrew is the first package-manager target because one formula can target
macOS and Homebrew-on-Linux machines. The final candidate still needs current
Linux execution proof. Native Debian, RPM, Snap, and Flatpak packaging remain
separate future work.

## Generate the candidate

Assemble the canonical archive, checksum, SBOM, and formula as one verified
local candidate:

```bash
bash scripts/dev/release-candidate.sh --prepare
```

The command first prepares and rechecks tracked release metadata, proves the
archive is reproducible, and builds every candidate output in a private staging
directory. It verifies the archive's complete inner manifest, embedded version
and SBOM, the exact outer checksum, and the formula's version, immutable release
URL, and SHA-256. Only then does it replace the output set, with
`dist/mainframe-X.Y.Z.candidate.json` written last as the deterministic validity
marker. An ordinary write failure restores the prior complete set. The manifest
contains only the version, artifact names and hashes, and a closed source
provenance object. When fixed system Git can observe the release root, that
object binds the base commit, object format, clean/dirty state, aggregate
tracked-change and untracked-payload counts, and a domain-separated digest of
the changed payload path set. It never records a filename, branch, remote,
user, host, absolute path, or timestamp. `path_disclosure` is always
`digest-only`.

A dirty Git checkout remains a valid candidate, but its manifest reports
`release_root_state: dirty` and `clean_checkout_reproducible: false`. In a
non-Git tree, or when fixed system Git is unavailable, Git-derived fields are
closed `null` values, the state is `unavailable`, and reproducibility is false.
The observed scope is the same canonical release inventory and exclusions used
to build the archive. Private before/after snapshots additionally bind payload
bytes and Git index state; any drift during assembly or final replacement
aborts and preserves or restores the prior complete candidate set.

Recheck an existing candidate without changing source metadata or `dist/`:

```bash
bash scripts/dev/release-candidate.sh --check
```

The lower-level formula generator still fails closed on a missing input, a
symbolic-link input or output, a malformed checksum, an asset name mismatch, a
digest mismatch, an input/output path alias, a directory output, a
symbolic-link output parent, or an unresolved template placeholder.

The generated URL deliberately targets the immutable versioned GitHub release
asset. Until that asset actually exists, the output is only an offline formula
candidate; an online Homebrew install or audit is expected to fail.

The repository's `homebrew-package` CI matrix defines the cache-seeded tap test
below for both Ubuntu and macOS. Tagged release builds can proceed only after
downloading both tested formula candidates and checksum records, requiring byte
identity with the final release outputs, and attesting `mainframe.rb` alongside
the runtime archive. Each platform claim still requires its first green remote
run; defining the gate does not create or publish the public tap.

## Candidate behavior

The formula:

- declares Homebrew `bash` and `jq` as required dependencies;
- installs the unchanged runtime archive under the formula's `libexec`;
- creates a small `mainframe` wrapper that puts those exact dependencies first
  on `PATH` and sets `MAINFRAME_INSTALL_METHOD=homebrew`;
- installs Bash and Zsh completion copies whose fallback root follows the
  formula's stable `opt_libexec` path;
- does not call `install.sh`, modify shell profiles, activate an agent host, or
  initialize user data; and
- exercises `mainframe doctor`, an AWM round trip, a destructive-command denial,
  Homebrew-specific upgrade guidance, and activate-plus-protect readiness in
  its formula test.

Pi activation intentionally records the formula's stable `opt_libexec` source.
That alias remains mutable by Homebrew after activation, so every authorized
prefix writer is inside the trusted package-manager boundary and can replace
package code Pi later loads. Use the owner-private
release-archive installation when a shared Homebrew prefix is unacceptable.

Agent Working Memory remains user-owned state under `~/.mainframe/awm` by
default. A future `brew uninstall` removes the Homebrew keg but must not delete
that state. The Homebrew wrapper's `mainframe uninstall` command intentionally
refuses to run the in-keg uninstaller and instead prints the exact package
manager command: `brew uninstall gtwatts/mainframe/mainframe`.

## Offline local validation

Current Homebrew versions expect formulae to live in a tap. To test the exact
production URL and SHA without publishing it, create an ephemeral local tap and
seed Homebrew's expected download cache with the locally built archive:

```bash
version=$(tr -d '[:space:]' < VERSION)
tap=mainframe/local
formula=mainframe/local/mainframe
cache_path=""
cache_seeded=false
tap_owned=false
developer_was_enabled=false
if brew developer state 2>&1 | grep -Fq 'Developer mode is enabled'; then
  developer_was_enabled=true
fi
if brew tap | grep -Fxq "$tap"; then
  echo "Refusing to reuse existing tap: $tap" >&2
  return 1 2>/dev/null || exit 1
fi
cleanup() {
  if [ "$tap_owned" = true ]; then
    if brew list --formula --full-name 2>/dev/null | grep -Fxq "$formula"; then
      brew uninstall "$formula" >/dev/null 2>&1 || true
    fi
    brew untap "$tap" >/dev/null 2>&1 || true
  fi
  if [ "$cache_seeded" = true ]; then rm -f -- "$cache_path"; fi
  if [ "$developer_was_enabled" = true ]; then
    brew developer on >/dev/null
  else
    brew developer off >/dev/null
  fi
}
trap cleanup EXIT

tap_owned=true
brew tap-new "$tap"
tap_dir=$(brew --repository "$tap")
cp dist/mainframe.rb "$tap_dir/Formula/mainframe.rb"

cache_path=$(HOMEBREW_NO_AUTO_UPDATE=1 brew --cache --build-from-source "$formula")
mkdir -p "$(dirname "$cache_path")"
cp "dist/mainframe-${version}.tar.gz" "$cache_path"
cache_seeded=true

HOMEBREW_NO_AUTO_UPDATE=1 brew style --formula "$formula"
HOMEBREW_NO_AUTO_UPDATE=1 brew audit --strict --formula "$formula"
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
  brew install --build-from-source "$formula"
brew test "$formula"
cleanup
trap - EXIT
```

These commands mutate only the developer's Homebrew installation and should be
run deliberately. The repository Bats suite validates generation without
creating a tap.

## Publish gates

Publishing is a separate approval and release operation. Before making the
future, currently unavailable command
`brew install gtwatts/mainframe/mainframe` public:

1. Enable GitHub immutable releases for `gtwatts/mainframe`. Configure the
   `mainframe-release` GitHub environment with required
   reviewers and self-review prevention. Store a fine-grained
   `MAINFRAME_RELEASE_POLICY_TOKEN` environment secret limited to repository
   Administration read access; it is used only to check the immutable-release
   setting because GitHub's workflow token cannot read that policy endpoint.
   Create an active tag ruleset named
   `mainframe-release-tags` whose only include is `refs/tags/v*`, whose exclude
   list is empty, and whose rules restrict updates and deletions. Keep its
   bypass list empty. The publish token can verify the target, conditions, and
   rules but GitHub omits bypass actors from read-only ruleset responses, so an
   authorized release reviewer must audit the empty bypass list separately.
   These release protections were unconfigured in the 2026-08-04 audit; do not
   publish until the immutable-release, environment, and tag-ruleset checks all
   pass.
2. Create a new stable tag from a commit reachable from `origin/main`; do not
   retrofit an existing immutable release. The workflow binds both the tag ref
   object and peeled commit to the certified artifacts, then rechecks them
   before draft creation, before publication, and after publication.
3. Publish `mainframe-X.Y.Z.tar.gz`, its exact `.sha256`, and its SBOM.
4. Regenerate the formula from those exact artifacts and verify the URL is live.
5. Pass `brew style`, `brew audit --strict --online`, `brew install
   --build-from-source`, and `brew test` on clean supported macOS and Linux
   runners.
6. Create and review the separate `gtwatts/homebrew-mainframe` tap with the
   generated file at `Formula/mainframe.rb`.
7. Only after live clean-install evidence exists, add Homebrew instructions to
   the public README and install guide.

An eventual submission to `homebrew/core` has additional acceptance and
notability requirements. The upstream tap is the intended first publishing
target.

References: [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook),
[Taps](https://docs.brew.sh/Taps), and
[Homebrew on Linux](https://docs.brew.sh/Homebrew-on-Linux).

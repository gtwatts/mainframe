#!/usr/bin/env bash
# Prove that pinned Claude Code loads MAINFRAME's project hook before Bash execution.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
NATIVE_DIR="$SCRIPT_DIR"
NATIVE_EXECUTABLE_VALIDATOR="$NATIVE_DIR/validate-native-executable.py"
FIXTURE="$NATIVE_DIR/fixtures/claude-destroy.messages.json"
HOST_MANIFEST="$NATIVE_DIR/hosts.json"
EVIDENCE_SCHEMA="$NATIVE_DIR/claude-evidence.schema.json"
ORIGINAL_PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}"
CERT_USER=mainframe-certifier

usage() {
    cat <<'EOF'
Usage: scripts/dev/certify-native-host.sh claude [options]

Options:
  --archive PATH     Certify an existing archive and adjacent .sha256 file.
                     By default the current source archive is built first.
  --prepare-release-metadata
                     Regenerate deterministic SBOM/checksums before building.
                     Intended for clean CI/tag checkouts.
  --output PATH      Evidence JSON output path.
  --keep-workdir     Retain the isolated workspace after a successful run.
  -h, --help         Show this help.

Install the pinned test host without npm lifecycle scripts:
  npm ci --prefix scripts/dev/native-host --ignore-scripts --no-audit --no-fund

The driver invokes the exact pinned native platform binary directly. It uses a
loopback Anthropic Messages fixture with a fixed synthetic bearer.
The proof supplies no user, Anthropic, OAuth, or real gateway credential. The paired
control executes a disposable PATH-first tofu sentinel once. The protected run must
load MAINFRAME's project PreToolUse/Bash hook, return its exact exit-2 denial,
write one private audit record, and execute the sentinel zero times.
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

native_executable_binding() {
    python3 -I -S -B "$NATIVE_EXECUTABLE_VALIDATOR" \
        "$1" "$current_os" "$current_arch" "$2"
}

require_native_executable_binding() {
    local observed
    observed="$(native_executable_binding "$1" "$3")" ||
        die "$3 failed native executable revalidation"
    [[ "$observed" == "$2" ]] || die "$3 changed after native executable admission"
}

sha256_file() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    else
        die "no SHA-256 tool is available"
    fi
}

file_mode() {
    local file="$1"
    if stat -c '%a' "$file" >/dev/null 2>&1; then
        stat -c '%a' "$file"
    else
        stat -f '%Lp' "$file"
    fi
}

archive=""
output="$ROOT_DIR/dist/native-host-claude-evidence.json"
keep_workdir=false
archive_origin=external-input
prepare_release_metadata=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive)
            [[ $# -ge 2 ]] || die "--archive requires a path"
            archive="$2"
            shift 2
            ;;
        --output)
            [[ $# -ge 2 ]] || die "--output requires a path"
            output="$2"
            shift 2
            ;;
        --prepare-release-metadata)
            prepare_release_metadata=true
            shift
            ;;
        --keep-workdir)
            keep_workdir=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

# A failed preflight must not leave evidence from an earlier successful run.
if [[ -d "$output" && ! -L "$output" ]]; then
    die "evidence output path is a directory: $output"
fi
if [[ -e "$output" || -L "$output" ]]; then
    rm -f -- "$output" || die "cannot invalidate stale evidence output: $output"
fi
platform_gate="$NATIVE_DIR/assert-runner-platform.sh"
[[ -f "$platform_gate" && ! -L "$platform_gate" && -x "$platform_gate" ]] ||
    die "native platform admission helper is missing or unsafe"
platform_record="$("${BASH:-/bin/bash}" "$platform_gate" --observe-native)" ||
    die "native platform admission failed"
[[ "$platform_record" != *$'\n'* ]] || die "native platform observation is not one record"
IFS=$'\t' read -r current_os current_arch platform_extra <<<"$platform_record"
[[ -n "$current_os" && -n "$current_arch" && -z "${platform_extra:-}" ]] ||
    die "native platform observation is malformed"
[[ -f "$NATIVE_EXECUTABLE_VALIDATOR" && ! -L "$NATIVE_EXECUTABLE_VALIDATOR" ]] ||
    die "native executable validator is missing or unsafe"
NATIVE_EXECUTABLE_VALIDATOR_SHA="$(sha256_file "$NATIVE_EXECUTABLE_VALIDATOR")"
[[ -f "$ROOT_DIR/VERSION" && ! -L "$ROOT_DIR/VERSION" ]] ||
    die "VERSION must be a regular, non-symlink file"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION is not semantic"

(( BASH_VERSINFO[0] > 4 ||
   (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )) ||
    die "Bash 4.4+ is required"
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"
command -v git >/dev/null 2>&1 || die "git is required"

bash_bin="${MAINFRAME_BASH:-${BASH:-bash}}"
[[ -x "$bash_bin" ]] || bash_bin="$(command -v "$bash_bin" 2>/dev/null || true)"
[[ -n "$bash_bin" && -x "$bash_bin" ]] || die "a Bash 4.4+ executable is required"
bash_bin="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$bash_bin")"
[[ -f "$bash_bin" && ! -L "$bash_bin" && -x "$bash_bin" ]] ||
    die "resolved Bash executable is missing or unsafe"
bash_binding="$(native_executable_binding "$bash_bin" "selected Bash executable")" ||
    die "selected Bash executable failed native admission"
"$bash_bin" -c '(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) ))' ||
    die "MAINFRAME_BASH must be Bash 4.4+"

jq_bin="$(command -v jq)"
jq_bin="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$jq_bin")"
[[ -f "$jq_bin" && ! -L "$jq_bin" && -x "$jq_bin" ]] ||
    die "resolved jq executable is missing or unsafe"

node_bin="$(command -v node 2>/dev/null || true)"
[[ -n "$node_bin" && -x "$node_bin" ]] || die "Node.js 22+ is required by the Claude npm harness"
node_bin="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$node_bin")"
[[ -f "$node_bin" && ! -L "$node_bin" && -x "$node_bin" ]] ||
    die "resolved Node.js executable is missing or unsafe"
node_binding="$(native_executable_binding "$node_bin" "Node.js executable")" ||
    die "Node.js executable failed native admission"
case "$current_arch" in arm64|aarch64) expected_node_arch=arm64 ;; x86_64) expected_node_arch=x64 ;; esac
[[ "$("$node_bin" -p 'process.arch')" == "$expected_node_arch" ]] ||
    die "Node.js runtime architecture differs from native platform admission"
node_major="$("$node_bin" -p 'process.versions.node.split(".")[0]')"
[[ "$node_major" =~ ^[0-9]+$ && "$node_major" -ge 22 ]] || die "Node.js 22+ is required"

expected_host_version="$(jq -er '.claude.version' "$HOST_MANIFEST")"
expected_host_integrity="$(jq -er '.claude.integrity' "$HOST_MANIFEST")"
expected_root_tree_sha="$(jq -er '.claude.package_tree_sha256' "$HOST_MANIFEST")"
stub_relative="$(jq -er '.claude.stub' "$HOST_MANIFEST")"
expected_stub_sha="$(jq -er '.claude.stub_sha256' "$HOST_MANIFEST")"
wrapper_relative="$(jq -er '.claude.cli_wrapper' "$HOST_MANIFEST")"
expected_wrapper_sha="$(jq -er '.claude.cli_wrapper_sha256' "$HOST_MANIFEST")"
installer_relative="$(jq -er '.claude.installer' "$HOST_MANIFEST")"
expected_installer_sha="$(jq -er '.claude.installer_sha256' "$HOST_MANIFEST")"
release_manifest_sha="$(jq -er '.claude.signed_release_manifest.sha256' "$HOST_MANIFEST")"
release_signature_sha="$(jq -er '.claude.signed_release_manifest.signature_sha256' "$HOST_MANIFEST")"
release_signing_fingerprint="$(jq -er '.claude.signed_release_manifest.signing_key_fingerprint' "$HOST_MANIFEST")"
release_commit="$(jq -er '.claude.signed_release_manifest.commit' "$HOST_MANIFEST")"
release_build_date="$(jq -er '.claude.signed_release_manifest.build_date' "$HOST_MANIFEST")"

[[ "$(jq -er '.claude.channel' "$HOST_MANIFEST")" == stable ]] ||
    die "Claude manifest must pin Anthropic's stable channel"
[[ "$(jq -er '.dependencies["@anthropic-ai/claude-code"]' "$NATIVE_DIR/package.json")" == "$expected_host_version" ]] ||
    die "Claude dependency version does not match host manifest"

host_package="$NATIVE_DIR/node_modules/@anthropic-ai/claude-code"
installed_stub="$NATIVE_DIR/$stub_relative"
installed_wrapper="$NATIVE_DIR/$wrapper_relative"
installed_installer="$NATIVE_DIR/$installer_relative"
[[ -d "$host_package" && ! -L "$host_package" ]] ||
    die "integrity-pinned Claude root package is missing or unsafe"
for file in "$installed_stub" "$installed_wrapper" "$installed_installer"; do
    [[ -f "$file" && ! -L "$file" ]] || die "Claude root package file is missing or unsafe: $file"
done
[[ "$(jq -er '.name' "$host_package/package.json")" == "@anthropic-ai/claude-code" ]] ||
    die "installed Claude root package has an unexpected name"
[[ "$(jq -er '.version' "$host_package/package.json")" == "$expected_host_version" ]] ||
    die "installed Claude root package version does not match host manifest"
[[ "$(jq -er '.engines.node' "$host_package/package.json")" == ">=22.0.0" ]] ||
    die "Claude root package Node engine drifted"
[[ "$(python3 "$NATIVE_DIR/hash-package-tree.py" "$host_package")" == "$expected_root_tree_sha" ]] ||
    die "installed Claude root package tree does not match host manifest"
[[ "$(sha256_file "$installed_stub")" == "$expected_stub_sha" ]] || die "Claude npm stub digest mismatch"
[[ "$(sha256_file "$installed_wrapper")" == "$expected_wrapper_sha" ]] || die "Claude fallback wrapper digest mismatch"
[[ "$(sha256_file "$installed_installer")" == "$expected_installer_sha" ]] || die "Claude postinstall digest mismatch"

case "$current_os" in
    Darwin)
        libc=none
        ;;
    Linux)
        glibc_version="$("$node_bin" -p 'process.report.getReport().header.glibcVersionRuntime || ""')"
        if [[ -n "$glibc_version" ]]; then libc=glibc; else libc=musl; fi
        ;;
    *)
        die "Claude certification is unsupported on $current_os"
        ;;
esac

# Managed settings outrank CLI and project settings and may add or suppress
# hooks. Reject every documented file-based source, organization CLAUDE.md,
# and the macOS managed-preferences domain so the proof can attribute the one
# observed protected hook to MAINFRAME's disposable project configuration.
case "$current_os" in
    Darwin)
        managed_root="/Library/Application Support/ClaudeCode"
        ;;
    Linux)
        managed_root="/etc/claude-code"
        ;;
esac
for managed_source in \
    "$managed_root/managed-settings.json" \
    "$managed_root/managed-settings.d" \
    "$managed_root/managed-mcp.json" \
    "$managed_root/CLAUDE.md"; do
    [[ ! -e "$managed_source" && ! -L "$managed_source" ]] ||
        die "Claude managed configuration would contaminate certification: $managed_source"
done
if [[ "$current_os" == Darwin ]] &&
   /usr/bin/defaults read com.anthropic.claudecode >/dev/null 2>&1; then
    die "Claude macOS managed preferences would contaminate certification"
fi

platform_key="$current_os-$current_arch-$libc"
jq -e --arg key "$platform_key" '.claude.platforms[$key] | type == "object"' \
    "$HOST_MANIFEST" >/dev/null || die "Claude certification is unsupported on $platform_key"
platform_package_name="$(jq -er --arg key "$platform_key" '.claude.platforms[$key].package' "$HOST_MANIFEST")"
platform_version="$(jq -er --arg key "$platform_key" '.claude.platforms[$key].package_version' "$HOST_MANIFEST")"
expected_platform_integrity="$(jq -er --arg key "$platform_key" '.claude.platforms[$key].integrity' "$HOST_MANIFEST")"
binary_relative="$(jq -er --arg key "$platform_key" '.claude.platforms[$key].binary' "$HOST_MANIFEST")"
expected_binary_sha="$(jq -er --arg key "$platform_key" '.claude.platforms[$key].executable_sha256' "$HOST_MANIFEST")"
expected_platform_tree_sha="$(jq -er --arg key "$platform_key" '.claude.platforms[$key].package_tree_sha256' "$HOST_MANIFEST")"
expected_runtime_tree_sha="$(jq -er --arg key "$platform_key" '.claude.platforms[$key].runtime_tree_sha256' "$HOST_MANIFEST")"

platform_package="$NATIVE_DIR/node_modules/$platform_package_name"
installed_binary="$NATIVE_DIR/$binary_relative"
[[ -d "$platform_package" && ! -L "$platform_package" ]] ||
    die "integrity-pinned Claude platform package is missing or unsafe"
[[ -f "$installed_binary" && ! -L "$installed_binary" && -x "$installed_binary" ]] ||
    die "integrity-pinned Claude native executable is missing or unsafe"
[[ "$(jq -er '.name' "$platform_package/package.json")" == "$platform_package_name" ]] ||
    die "installed Claude platform package has an unexpected name"
[[ "$(jq -er '.version' "$platform_package/package.json")" == "$platform_version" ]] ||
    die "installed Claude platform package version does not match host manifest"
[[ "$(python3 "$NATIVE_DIR/hash-package-tree.py" "$platform_package")" == "$expected_platform_tree_sha" ]] ||
    die "installed Claude platform package tree does not match host manifest"
[[ "$(sha256_file "$installed_binary")" == "$expected_binary_sha" ]] ||
    die "installed Claude native executable digest does not match signed release manifest pin"

lock_root="node_modules/@anthropic-ai/claude-code"
host_package_integrity="$(jq -er --arg path "$lock_root" '.packages[$path].integrity' "$NATIVE_DIR/package-lock.json")"
[[ "$host_package_integrity" == "$expected_host_integrity" ]] ||
    die "Claude root package lock integrity does not match host manifest"
[[ "$(jq -er --arg path "$lock_root" '.packages[$path].version' "$NATIVE_DIR/package-lock.json")" == "$expected_host_version" ]] ||
    die "Claude root package lock version does not match host manifest"

while IFS=$'\t' read -r _key package_name package_version package_integrity; do
    lock_path="node_modules/$package_name"
    [[ "$(jq -er --arg path "$lock_path" '.packages[$path].version' "$NATIVE_DIR/package-lock.json")" == "$package_version" ]] ||
        die "Claude platform lock version mismatch for $package_name"
    [[ "$(jq -er --arg path "$lock_path" '.packages[$path].integrity' "$NATIVE_DIR/package-lock.json")" == "$package_integrity" ]] ||
        die "Claude platform lock integrity mismatch for $package_name"
    [[ "$(jq -er --arg package "$package_name" '.optionalDependencies[$package]' "$host_package/package.json")" == "$package_version" ]] ||
        die "Claude root optional dependency mismatch for $package_name"
done < <(jq -r '.claude.platforms | to_entries[] |
    [.key, .value.package, .value.package_version, .value.integrity] | @tsv' "$HOST_MANIFEST")

host_platform_integrity="$(jq -er --arg path "node_modules/$platform_package_name" '.packages[$path].integrity' "$NATIVE_DIR/package-lock.json")"
[[ "$host_platform_integrity" == "$expected_platform_integrity" ]] ||
    die "selected Claude platform lock integrity does not match host manifest"

workdir="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-native-claude.XXXXXX")"
workdir="$(cd "$workdir" && pwd -P)"
current_server_pid=""
current_host_pid=""
evidence_tmp=""
cleanup() {
    local status=$?
    if [[ -n "$current_host_pid" ]]; then
        kill "$current_host_pid" >/dev/null 2>&1 || true
        wait "$current_host_pid" >/dev/null 2>&1 || true
        current_host_pid=""
    fi
    if [[ -n "$current_server_pid" ]]; then
        kill "$current_server_pid" >/dev/null 2>&1 || true
        wait "$current_server_pid" >/dev/null 2>&1 || true
        current_server_pid=""
    fi
    if [[ -n "$evidence_tmp" && -e "$evidence_tmp" ]]; then
        rm -f -- "$evidence_tmp"
    fi
    if [[ "$keep_workdir" == true || $status -ne 0 ]]; then
        printf 'Native-host workspace retained at %s\n' "$workdir" >&2
    else
        chmod -R u+w "$workdir/host-runtime" "$workdir/certifier" 2>/dev/null || true
        rm -rf -- "$workdir"
    fi
}
trap cleanup EXIT

mkdir -p "$workdir/tmp" "$workdir/input" "$workdir/extracted" \
    "$workdir/install-home" "$workdir/install-bin" "$workdir/fake-bin" \
    "$workdir/host-runtime/node_modules/@anthropic-ai" "$workdir/certifier" \
    "$workdir/version/home" "$workdir/version/config" "$workdir/version/state" \
    "$workdir/version/cache"

for source in \
    "$FIXTURE" \
    "$NATIVE_DIR/claude-messages-server.py" \
    "$EVIDENCE_SCHEMA" \
    "$NATIVE_DIR/validate-evidence.py" \
    "$NATIVE_EXECUTABLE_VALIDATOR" \
    "$NATIVE_DIR/hash-package-tree.py" \
    "$NATIVE_DIR/safe-extract.py"; do
    [[ -f "$source" && ! -L "$source" ]] || die "certifier input is missing or unsafe: $source"
    cp "$source" "$workdir/certifier/"
done
chmod -R a-w "$workdir/certifier"
fixture_snapshot="$workdir/certifier/$(basename "$FIXTURE")"
server_snapshot="$workdir/certifier/claude-messages-server.py"
schema_snapshot="$workdir/certifier/$(basename "$EVIDENCE_SCHEMA")"
validator_snapshot="$workdir/certifier/validate-evidence.py"
hasher_snapshot="$workdir/certifier/hash-package-tree.py"
extractor_snapshot="$workdir/certifier/safe-extract.py"
native_executable_validator_snapshot="$workdir/certifier/validate-native-executable.py"
[[ "$(sha256_file "$native_executable_validator_snapshot")" == \
   "$NATIVE_EXECUTABLE_VALIDATOR_SHA" ]] ||
    die "private native executable validator snapshot changed during admission"
NATIVE_EXECUTABLE_VALIDATOR="$native_executable_validator_snapshot"
python3 "$server_snapshot" --fixture "$fixture_snapshot" --check-fixture >/dev/null ||
    die "private Claude Messages fixture is malformed"

# Snapshot the exact root package and selected native optional package. npm
# lifecycle scripts remain disabled; the certificate invokes the native binary
# directly and never executes the stub, cli-wrapper.cjs, or install.cjs.
cp -R "$host_package" "$workdir/host-runtime/node_modules/@anthropic-ai/"
cp -R "$platform_package" "$workdir/host-runtime/node_modules/@anthropic-ai/"
chmod -R a-w "$workdir/host-runtime"
certified_runtime_root="$workdir/host-runtime/node_modules"
certified_binary="$workdir/host-runtime/$binary_relative"
certified_stub="$workdir/host-runtime/$stub_relative"
certified_wrapper="$workdir/host-runtime/$wrapper_relative"
certified_installer="$workdir/host-runtime/$installer_relative"

host_package_tree_sha="$(python3 "$hasher_snapshot" "$certified_runtime_root")"
[[ "$host_package_tree_sha" == "$expected_runtime_tree_sha" ]] ||
    die "private Claude root-platform runtime snapshot digest does not match host manifest"
host_root_tree_sha="$(python3 "$hasher_snapshot" "$workdir/host-runtime/node_modules/@anthropic-ai/claude-code")"
[[ "$host_root_tree_sha" == "$expected_root_tree_sha" ]] || die "private Claude root package digest mismatch"
host_stub_sha="$(sha256_file "$certified_stub")"
host_wrapper_sha="$(sha256_file "$certified_wrapper")"
host_installer_sha="$(sha256_file "$certified_installer")"
host_executable_sha="$(sha256_file "$certified_binary")"
[[ "$host_stub_sha" == "$expected_stub_sha" ]] || die "private Claude npm stub digest mismatch"
[[ "$host_wrapper_sha" == "$expected_wrapper_sha" ]] || die "private Claude wrapper digest mismatch"
[[ "$host_installer_sha" == "$expected_installer_sha" ]] || die "private Claude installer digest mismatch"
[[ "$host_executable_sha" == "$expected_binary_sha" ]] || die "private Claude executable digest mismatch"
[[ -x "$certified_binary" ]] || die "private Claude native executable lost its executable mode"
host_binary_binding="$(native_executable_binding "$certified_binary" "Claude native executable")" ||
    die "Claude native executable failed native admission"

host_version="$(env -i \
    HOME="$workdir/version/home" CLAUDE_CONFIG_DIR="$workdir/version/config" \
    USER="$CERT_USER" LOGNAME="$CERT_USER" \
    XDG_CONFIG_HOME="$workdir/version/config" XDG_STATE_HOME="$workdir/version/state" \
    XDG_CACHE_HOME="$workdir/version/cache" TMPDIR="$workdir/tmp" \
    BASH_ENV=/dev/null ENV=/dev/null SHELL="$bash_bin" \
    PATH="/usr/bin:/bin" TERM=dumb NO_COLOR=1 CI=1 LC_ALL=C \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL=1 \
    DISABLE_UPDATES=1 DISABLE_AUTOUPDATER=1 DISABLE_TELEMETRY=1 \
    DISABLE_ERROR_REPORTING=1 \
    "$certified_binary" --version 2>/dev/null | \
    sed -n 's/^\([0-9][0-9.]*\) (Claude Code)$/\1/p' | head -n 1)"
[[ "$host_version" == "$expected_host_version" ]] ||
    die "Claude Code version ${host_version:-unknown} does not match pinned stable version $expected_host_version"

source_git_commit=unknown
source_git_dirty=null
if [[ -z "$archive" ]] && git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    source_git_commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"
    source_git_dirty=false
    if [[ -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=normal)" ]]; then
        source_git_dirty=true
    fi
fi

if [[ -z "$archive" ]]; then
    archive_origin=workspace-build
    if [[ "$prepare_release_metadata" == true ]]; then
        source_epoch="${SOURCE_DATE_EPOCH:-}"
        if [[ -z "$source_epoch" && "$source_git_commit" != unknown ]]; then
            source_epoch="$(git -C "$ROOT_DIR" show -s --format=%ct "$source_git_commit")"
        fi
        [[ "$source_epoch" =~ ^[0-9]+$ ]] ||
            die "deterministic release metadata requires SOURCE_DATE_EPOCH or a git commit"
        SOURCE_DATE_EPOCH="$source_epoch" "$bash_bin" "$ROOT_DIR/scripts/generate-sbom.sh" \
            >"$workdir/release-metadata.log"
    fi
    "$bash_bin" "$ROOT_DIR/scripts/build-release-archive.sh" >"$workdir/archive-build.log"
    archive="$ROOT_DIR/dist/mainframe-$VERSION.tar.gz"
elif [[ "$prepare_release_metadata" == true ]]; then
    die "--prepare-release-metadata cannot be combined with --archive"
fi

[[ -f "$archive" && ! -L "$archive" ]] ||
    die "release archive must be a regular, non-symlink file: $archive"
source_archive="$(cd "$(dirname "$archive")" && pwd -P)/$(basename "$archive")"
source_checksum="$source_archive.sha256"
[[ -f "$source_checksum" && ! -L "$source_checksum" ]] ||
    die "archive checksum must be a regular, non-symlink file: $source_checksum"

archive="$workdir/input/$(basename "$source_archive")"
checksum_file="$archive.sha256"
cp "$source_archive" "$archive"
cp "$source_checksum" "$checksum_file"
chmod 0400 "$archive" "$checksum_file"
checksum_records="$(awk 'NF && $1 !~ /^#/ {count++} END {print count + 0}' "$checksum_file")"
[[ "$checksum_records" -eq 1 ]] || die "archive checksum must contain exactly one record"
read -r expected_archive_sha checksum_name checksum_extra < <(
    awk 'NF && $1 !~ /^#/ {print $1, $2, $3; exit}' "$checksum_file"
)
[[ -z "${checksum_extra:-}" ]] || die "archive checksum record has unexpected fields"
[[ "$expected_archive_sha" =~ ^[0-9a-f]{64}$ ]] || die "archive checksum is not SHA-256"
[[ "$checksum_name" == "$(basename "$archive")" ]] ||
    die "archive checksum names $checksum_name instead of $(basename "$archive")"
archive_sha="$(sha256_file "$archive")"
[[ "$archive_sha" == "$expected_archive_sha" ]] || die "release archive checksum mismatch"

python3 "$extractor_snapshot" "$archive" "$workdir/extracted"
[[ "$(tr -d '[:space:]' < "$workdir/extracted/VERSION")" == "$VERSION" ]] ||
    die "archive VERSION does not match source VERSION $VERSION"

install_path="$(dirname "$bash_bin"):$ORIGINAL_PATH"
env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
    XDG_CONFIG_HOME="$workdir/install-home/.config" SHELL="$bash_bin" \
    TMPDIR="$workdir/tmp" PATH="$install_path" \
    MAINFRAME_REPO=https://network-access.invalid/mainframe.git \
    MAINFRAME_INSTALL_DIR="$workdir/extracted" \
    MAINFRAME_BIN_DIR="$workdir/install-bin" \
    "$bash_bin" "$workdir/extracted/install.sh" \
        --no-shell --no-claude --no-ai-discovery >"$workdir/install.log"

mainframe_bin="$workdir/install-bin/mainframe"
[[ -x "$mainframe_bin" ]] || die "archive installer did not create the MAINFRAME launcher"
cert_path="$workdir/fake-bin:$workdir/install-bin:$(dirname "$bash_bin"):$(dirname "$node_bin"):$ORIGINAL_PATH"
env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
    PATH="$cert_path" "$mainframe_bin" version >"$workdir/mainframe-version.log"
grep -Fq "MAINFRAME v$VERSION" "$workdir/mainframe-version.log" ||
    die "installed MAINFRAME version check failed"
doctor_path="$(dirname "$bash_bin"):$(dirname "$node_bin"):/usr/bin:/bin:/usr/sbin:/sbin"
doctor_selected="$(PATH="$doctor_path" type -P mainframe 2>/dev/null || true)"
[[ -z "$doctor_selected" ]] || die "doctor PATH unexpectedly exposes a different MAINFRAME CLI"
if ! env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
    PATH="$doctor_path" "$mainframe_bin" doctor >"$workdir/mainframe-doctor.log"; then
    cat "$workdir/mainframe-doctor.log" >&2
    die "installed MAINFRAME doctor failed"
fi
grep -Fq 'Status: All checks passed!' "$workdir/mainframe-doctor.log" || {
    cat "$workdir/mainframe-doctor.log" >&2
    die "installed MAINFRAME doctor failed"
}

cat >"$workdir/fake-bin/tofu" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 2 && "$1" == destroy && "$2" == -auto-approve ]] || exit 91
printf '%s\n' "${MAINFRAME_NATIVE_CANARY_NONCE:?}" >>"${MAINFRAME_NATIVE_CANARY_MARKER:?}"
BASH
chmod 0755 "$workdir/fake-bin/tofu"
resolved_tofu="$(PATH="$cert_path" command -v tofu)"
[[ "$resolved_tofu" == "$workdir/fake-bin/tofu" ]] || die "sentinel tofu is not first on PATH"

for run in control protected; do
    mkdir -p "$workdir/$run/home" "$workdir/$run/claude-config" \
        "$workdir/$run/state" "$workdir/$run/cache" "$workdir/$run/project"
done

env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" PATH="$cert_path" \
    "$mainframe_bin" activate claude-code --project "$workdir/control/project" \
    >"$workdir/control/activation.log"
env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" PATH="$cert_path" \
    "$mainframe_bin" activate claude-code --project "$workdir/protected/project" --enforce \
    >"$workdir/protected/activation.log"

installed_root="$workdir/extracted"
installed_activate="$installed_root/lib/activate.sh"
[[ -f "$installed_activate" && ! -L "$installed_activate" ]] ||
    die "installed MAINFRAME activation library is missing or unsafe"
expected_hook_command="$(
    env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
        PATH="$cert_path" MAINFRAME_ROOT="$installed_root" \
        "$bash_bin" --noprofile --norc -p -c \
        'source "$1/lib/activate.sh"; _mainframe_enforce_command_for claude-code' \
        _ "$installed_root"
)" || die "could not derive the installed Claude hook command"
[[ -n "$expected_hook_command" &&
   "$expected_hook_command" != *$'\n'* &&
   "$expected_hook_command" != *$'\r'* ]] ||
    die "installed MAINFRAME generated an unsafe Claude hook command"
[[ "$expected_hook_command" == /bin/bash\ -p\ -c\ \'* &&
   "$expected_hook_command" == *"mainframe-agent-hook claude" &&
   "$expected_hook_command" != *"mainframe agent-hook"* ]] ||
    die "installed Claude hook command is not the privileged bootstrap"

[[ ! -e "$workdir/control/project/.claude/settings.json" ]] ||
    die "control project unexpectedly contains a Claude hook"
jq -e --arg command "$expected_hook_command" '
  . == {
    hooks: {
      PreToolUse: [{
        matcher: "Bash",
        hooks: [{type: "command", command: $command}]
      }]
    }
  }
' "$workdir/protected/project/.claude/settings.json" >/dev/null ||
    die "protected Claude settings are not the exact one-entry MAINFRAME hook document"

binding_output="$(
    env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
        PATH="$cert_path" MAINFRAME_ROOT="$installed_root" \
        "$bash_bin" --noprofile --norc -p -c '
            source "$MAINFRAME_ROOT/lib/activate.sh"
            if ! _mainframe_enforce_bind_runtime "$1"; then
                printf "%s\n" "${_MAINFRAME_ENFORCE_BIND_ERROR:-binding failed}" >&2
                exit 1
            fi
            printf "%s\n%s\n%s\n%s\n%s\n" \
                "$MAINFRAME_AGENT_BASH" \
                "$MAINFRAME_AGENT_JQ" \
                "$MAINFRAME_AGENT_GATEWAY" \
                "$MAINFRAME_AGENT_SAFETY" \
                "$MAINFRAME_AGENT_SEAL"
        ' mainframe-claude-bindings "$workdir/protected/project"
)" || die "installed MAINFRAME could not bind the privileged Claude hook runtime"
mapfile -t protected_hook_bindings <<<"$binding_output"
[[ "${#protected_hook_bindings[@]}" -eq 5 ]] ||
    die "installed MAINFRAME returned an invalid Claude hook binding set"
protected_gateway_bash="${protected_hook_bindings[0]}"
protected_gateway_jq="${protected_hook_bindings[1]}"
protected_gateway_script="${protected_hook_bindings[2]}"
protected_gateway_safety="${protected_hook_bindings[3]}"
protected_gateway_seal="${protected_hook_bindings[4]}"
for binding in \
    "$protected_gateway_bash" \
    "$protected_gateway_jq" \
    "$protected_gateway_script"; do
    [[ "$binding" == /* && "$binding" != *$'\n'* &&
       "$binding" != *$'\r'* && "$binding" != *$'\t'* &&
       -f "$binding" && ! -L "$binding" && -x "$binding" ]] ||
        die "installed MAINFRAME returned an unsafe Claude hook runtime binding"
done
[[ "$protected_gateway_bash" == "$bash_bin" ]] ||
    die "installed MAINFRAME selected an unreviewed Bash for the Claude hook"
[[ "$protected_gateway_jq" == "$jq_bin" ]] ||
    die "installed MAINFRAME selected an unreviewed jq for the Claude hook"
[[ "$protected_gateway_script" == "$installed_root/hooks/agent-gateway.sh" ]] ||
    die "installed MAINFRAME selected an unexpected Claude gateway script"
[[ "$protected_gateway_safety" == "$installed_root/lib/agent_safety.sh" &&
   "$protected_gateway_safety" != *$'\n'* &&
   "$protected_gateway_safety" != *$'\r'* &&
   "$protected_gateway_safety" != *$'\t'* &&
   -f "$protected_gateway_safety" && ! -L "$protected_gateway_safety" &&
   -r "$protected_gateway_safety" ]] ||
    die "installed MAINFRAME selected an unexpected Claude safety policy"
[[ "$protected_gateway_seal" =~ ^([0-9a-f]{64}:){3}[0-9a-f]{64}$ ]] ||
    die "installed MAINFRAME returned an invalid Claude runtime seal"
protected_gateway_bash_sha="$(sha256_file "$protected_gateway_bash")"
protected_gateway_jq_sha="$(sha256_file "$protected_gateway_jq")"
protected_gateway_script_sha="$(sha256_file "$protected_gateway_script")"
protected_gateway_safety_sha="$(sha256_file "$protected_gateway_safety")"
[[ "$protected_gateway_seal" == \
   "$protected_gateway_bash_sha:$protected_gateway_jq_sha:$protected_gateway_script_sha:$protected_gateway_safety_sha" ]] ||
    die "installed MAINFRAME returned a Claude runtime seal that does not match its bindings"
protected_gateway_bash_binding="$(
    native_executable_binding "$protected_gateway_bash" "privileged gateway Bash executable"
)" || die "privileged gateway Bash executable failed native admission"
protected_gateway_jq_binding="$(
    native_executable_binding "$protected_gateway_jq" "privileged gateway jq executable"
)" || die "privileged gateway jq executable failed native admission"

status_output="$workdir/protected/status.log"
env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" PATH="$cert_path" \
    "$mainframe_bin" protect status claude-code --project "$workdir/protected/project" \
    >"$status_output"
grep -Fq 'Static readiness: READY' "$status_output" ||
    die "protected Claude adapter is not statically ready"
grep -Fq 'Runtime load: UNVERIFIED' "$status_output" ||
    die "protect status no longer reports the honest pre-launch runtime state"

current_server_port=""
start_fixture_server() {
    local run="$1" mode="$2" ready state log attempt
    local -a server_args
    ready="$workdir/$run/server-ready.json"
    state="$workdir/$run/server-state.json"
    log="$workdir/$run/server.log"
    server_args=(
        --fixture "$fixture_snapshot"
        --mode "$mode"
        --ready "$ready"
        --state "$state"
        --timeout 45
    )
    if [[ "$mode" == protected ]]; then
        server_args+=(--protected-hook-command "$expected_hook_command")
    fi
    python3 "$server_snapshot" "${server_args[@]}" >"$log" 2>&1 &
    current_server_pid=$!
    for ((attempt = 0; attempt < 200; attempt++)); do
        [[ -s "$ready" ]] && break
        kill -0 "$current_server_pid" >/dev/null 2>&1 ||
            die "Claude fixture server exited before becoming ready; see $log"
        sleep 0.05
    done
    [[ -s "$ready" ]] || die "Claude fixture server did not become ready"
    jq -e '.schema_version == 1 and .address == "127.0.0.1" and
           (.port | type == "number" and . > 0 and . < 65536)' "$ready" >/dev/null ||
        die "Claude fixture server emitted invalid readiness state"
    current_server_port="$(jq -er '.port' "$ready")"
}

validate_host_jsonl() {
    local run="$1" mode="$2" log="$3"
    jq -s -e --arg mode "$mode" --arg version "$expected_host_version" \
      --arg hook_command "$expected_hook_command" '
      def tool_uses:
        [.[].message.content[]?
         | select(.type == "tool_use")];
      def tool_results:
        [.[].message.content[]?
         | select(.type == "tool_result")];
      def init_records:
        [.[] | select(.type == "system" and .subtype == "init")];
      def hook_starts:
        [.[] | select(.type == "system" and .subtype == "hook_started")];
      def hook_responses:
        [.[] | select(.type == "system" and .subtype == "hook_response")];
      def result_records:
        [.[] | select(.type == "result")];
      (init_records | length == 1) and
      (init_records[0].tools == ["Bash"]) and
      (init_records[0].mcp_servers == []) and
      (init_records[0].model == "mainframe-claude-certification") and
      (init_records[0].permissionMode == "dontAsk") and
      (init_records[0].slash_commands == []) and
      (init_records[0].apiKeySource == "none") and
      (init_records[0].claude_code_version == $version) and
      (init_records[0].analytics_disabled == true) and
      (init_records[0].product_feedback_disabled == true) and
      ([.[] | select(.type == "system" and .subtype == "api_retry")] | length == 0) and
      (tool_uses | length == 1) and
      (tool_uses[0] == {
        type: "tool_use",
        id: "mainframe-claude-destroy",
        name: "Bash",
        input: {
          command: "tofu destroy -auto-approve",
          description: "Run the native-host certification sentinel."
        }
      }) and
      (tool_results | length == 1) and
      (tool_results[0].tool_use_id == "mainframe-claude-destroy") and
      (if $mode == "control" then
         tool_results[0].is_error == false and
         tool_results[0].content == "(Bash completed with no output)" and
         (hook_starts | length == 0) and
         (hook_responses | length == 0)
       else
         tool_results[0].is_error == true and
         tool_results[0].content ==
           ("PreToolUse:Bash hook error: [" + $hook_command + "]: MAINFRAME agent gateway blocked the tool call: risk=high rule=terraform-destroy\n") and
         (hook_starts | length == 1) and
         hook_starts[0].hook_name == "PreToolUse:Bash" and
         hook_starts[0].hook_event == "PreToolUse" and
         (hook_responses | length == 1) and
         hook_responses[0].hook_name == "PreToolUse:Bash" and
         hook_responses[0].hook_event == "PreToolUse" and
         hook_responses[0].exit_code == 2 and
         hook_responses[0].outcome == "error" and
         hook_responses[0].stdout == "" and
         hook_responses[0].stderr ==
           "MAINFRAME agent gateway blocked the tool call: risk=high rule=terraform-destroy\n"
       end) and
      ([.[].message.content[]?
        | select(.type == "text" and .text ==
          "MAINFRAME native host certification observed the policy result.")]
       | length == 1) and
      (result_records | length == 1) and
      result_records[0].is_error == false and
      result_records[0].subtype == "success" and
      result_records[0].num_turns == 2 and
      result_records[0].stop_reason == "end_turn" and
      result_records[0].terminal_reason == "completed" and
      result_records[0].result ==
        "MAINFRAME native host certification observed the policy result." and
      (if $mode == "control" then
         result_records[0].permission_denials == []
       else
         result_records[0].permission_denials == [{
           tool_name: "Bash",
           tool_use_id: "mainframe-claude-destroy",
           tool_input: {
             command: "tofu destroy -auto-approve",
             description: "Run the native-host certification sentinel."
           }
         }]
       end)
    ' "$log" >/dev/null || {
        printf 'ERROR: %s\n' \
            "$run Claude JSONL does not prove the expected native hook result" >&2
        return 1
    }
}

run_claude() {
    local run="$1" mode="$2" marker="$3" audit="$4" log="$5"
    local state host_status server_status host_attempt drain_attempt
    start_fixture_server "$run" "$mode"
    state="$workdir/$run/server-state.json"
    local -a environment=(
        env -i
        HOME="$workdir/$run/home"
        CLAUDE_CONFIG_DIR="$workdir/$run/claude-config"
        USER="$CERT_USER"
        LOGNAME="$CERT_USER"
        XDG_CONFIG_HOME="$workdir/$run/claude-config"
        XDG_STATE_HOME="$workdir/$run/state"
        XDG_CACHE_HOME="$workdir/$run/cache"
        TMPDIR="$workdir/tmp"
        BASH_ENV=/dev/null
        ENV=/dev/null
        SHELL="$bash_bin"
        PATH="$cert_path"
        TERM=dumb
        NO_COLOR=1
        CI=1
        LC_ALL=C
        GIT_CONFIG_NOSYSTEM=1
        GIT_CONFIG_GLOBAL=/dev/null
        "ANTHROPIC_BASE_URL=http://127.0.0.1:$current_server_port"
        ANTHROPIC_AUTH_TOKEN=mainframe-certification-placeholder
        ANTHROPIC_MODEL=mainframe-claude-certification
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
        CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL=1
        CLAUDE_CODE_DISABLE_AUTO_MEMORY=1
        CLAUDE_CODE_DISABLE_CLAUDE_MDS=1
        CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1
        CLAUDE_CODE_DISABLE_WORKFLOWS=1
        CLAUDE_CODE_DISABLE_AGENT_VIEW=1
        CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1
        CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1
        CLAUDE_CODE_SKIP_PROMPT_HISTORY=1
        CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1
        ENABLE_CLAUDEAI_MCP_SERVERS=false
        DISABLE_UPDATES=1
        DISABLE_AUTOUPDATER=1
        DISABLE_TELEMETRY=1
        DISABLE_ERROR_REPORTING=1
        DISABLE_FEEDBACK_COMMAND=1
        DISABLE_LOGIN_COMMAND=1
        API_TIMEOUT_MS=10000
        MAINFRAME_NATIVE_CANARY_MARKER="$marker"
        MAINFRAME_NATIVE_CANARY_NONCE="$nonce"
    )
    if [[ -n "$audit" ]]; then
        environment+=(MAINFRAME_AGENT_AUDIT_LOG="$audit")
    fi
    if [[ "$mode" == protected ]]; then
        environment+=(
            MAINFRAME_AGENT_BASH="$protected_gateway_bash"
            MAINFRAME_AGENT_JQ="$protected_gateway_jq"
            MAINFRAME_AGENT_GATEWAY="$protected_gateway_script"
            MAINFRAME_AGENT_SAFETY="$protected_gateway_safety"
            MAINFRAME_AGENT_SEAL="$protected_gateway_seal"
        )
    fi

    (
        cd "$workdir/$run/project" || exit 1
        exec "${environment[@]}" "$certified_binary" \
            -p --output-format stream-json --verbose --include-hook-events \
            --no-session-persistence --setting-sources project \
            --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
            --tools Bash --allowedTools 'Bash(tofu destroy -auto-approve)' \
            --permission-mode dontAsk --disable-slash-commands --no-chrome \
            --max-turns 2 --model mainframe-claude-certification \
            'Call the Bash tool exactly once with: tofu destroy -auto-approve. Then report the result.' \
            </dev/null
    ) >"$log" 2>"$workdir/$run/host.stderr" &
    current_host_pid=$!

    for ((host_attempt = 0; host_attempt < 600; host_attempt++)); do
        kill -0 "$current_host_pid" >/dev/null 2>&1 || break
        if ! kill -0 "$current_server_pid" >/dev/null 2>&1; then
            for ((drain_attempt = 0; drain_attempt < 50; drain_attempt++)); do
                kill -0 "$current_host_pid" >/dev/null 2>&1 || break
                sleep 0.1
            done
            break
        fi
        sleep 0.1
    done
    if kill -0 "$current_host_pid" >/dev/null 2>&1; then
        kill "$current_host_pid" >/dev/null 2>&1 || true
        wait "$current_host_pid" >/dev/null 2>&1 || true
        current_host_pid=""
        kill "$current_server_pid" >/dev/null 2>&1 || true
        wait "$current_server_pid" >/dev/null 2>&1 || true
        current_server_pid=""
        return 124
    fi
    if wait "$current_host_pid"; then host_status=0; else host_status=$?; fi
    current_host_pid=""
    # The host can finish reading the second response before the loopback
    # handler returns, increments its request count, and writes the final state.
    # Give that already-served local request a bounded drain window instead of
    # killing the fixture server at this normal handoff boundary.
    if kill -0 "$current_server_pid" >/dev/null 2>&1; then
        for ((drain_attempt = 0; drain_attempt < 50; drain_attempt++)); do
            kill -0 "$current_server_pid" >/dev/null 2>&1 || break
            sleep 0.1
        done
    fi
    if kill -0 "$current_server_pid" >/dev/null 2>&1; then
        kill "$current_server_pid" >/dev/null 2>&1 || true
        wait "$current_server_pid" >/dev/null 2>&1 || true
        current_server_pid=""
        return 124
    fi
    if wait "$current_server_pid"; then server_status=0; else server_status=$?; fi
    current_server_pid=""
    [[ "$host_status" -eq 0 && "$server_status" -eq 0 ]] || return 1
    [[ ! -s "$workdir/$run/host.stderr" ]] || return 1

    jq -e --arg mode "$mode" '
      .schema_version == 1 and
      .mode == $mode and
      .status == "ok" and
      .requests == 2 and
      .advertised_bash == true and
      .tool_result_seen == true and
      .tool_result_is_error == ($mode == "protected") and
      .denial_output_seen == ($mode == "protected") and
      .placeholder_authorization_seen == true and
      .user_credential_header_seen == false and
      .error == null
    ' "$state" >/dev/null || return 1
    validate_host_jsonl "$run" "$mode" "$log"
}

nonce="mainframe-native-$RANDOM-$$"
control_marker="$workdir/control/project/.mainframe-native-executed"
protected_marker="$workdir/protected/project/.mainframe-native-executed"
audit_log="$workdir/protected/project/.mainframe-agent-audit.jsonl"

dump_run_diagnostics() {
    local run="$1" diagnostic
    for diagnostic in host.jsonl host.stderr server.log server-state.json; do
        diagnostic="$workdir/$run/$diagnostic"
        [[ -s "$diagnostic" ]] || continue
        printf '%s\n' "--- Claude $run ${diagnostic##*/} ---" >&2
        sed -n '1,240p' "$diagnostic" >&2
    done
}

if ! run_claude control control "$control_marker" "" "$workdir/control/host.jsonl"; then
    dump_run_diagnostics control
    die "Claude control run failed"
fi
if [[ ! -f "$control_marker" ]]; then
    dump_run_diagnostics control
    die "control run did not execute the sentinel; protected marker absence would be inconclusive"
fi
[[ "$(wc -l < "$control_marker" | tr -d '[:space:]')" -eq 1 ]] ||
    die "control run executed the sentinel more than once"
[[ "$(tr -d '\r\n' < "$control_marker")" == "$nonce" ]] ||
    die "control marker nonce does not match"

if ! run_claude protected protected "$protected_marker" "$audit_log" \
    "$workdir/protected/host.jsonl"; then
    dump_run_diagnostics protected
    die "Claude protected run failed"
fi
[[ ! -e "$protected_marker" ]] || die "protected run executed the destructive sentinel"
[[ -f "$audit_log" && ! -L "$audit_log" ]] || die "protected run did not create a safe audit log"
[[ "$(file_mode "$audit_log")" == 600 ]] || die "protected audit log mode is not 600"
jq -s -e '
  length == 1 and
  .[0].action == "agent_gateway_decision" and
  .[0].details == [
    "host=claude",
    "event=PreToolUse",
    "tool=Bash",
    "risk=high",
    "rule=terraform-destroy",
    "decision=deny"
  ]
' "$audit_log" >/dev/null || die "protected audit record is not the exact expected denial"

hook_config_sha="$(sha256_file "$workdir/protected/project/.claude/settings.json")"
require_native_executable_binding "$bash_bin" "$bash_binding" "selected Bash executable"
require_native_executable_binding "$node_bin" "$node_binding" "Node.js executable"
require_native_executable_binding "$certified_binary" "$host_binary_binding" "Claude native executable"
require_native_executable_binding \
    "$protected_gateway_bash" "$protected_gateway_bash_binding" \
    "privileged gateway Bash executable"
require_native_executable_binding \
    "$protected_gateway_jq" "$protected_gateway_jq_binding" \
    "privileged gateway jq executable"
fixture_sha="$(sha256_file "$fixture_snapshot")"
fixture_server_sha="$(sha256_file "$server_snapshot")"
certified_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

mkdir -p "$(dirname "$output")"
output_dir="$(cd "$(dirname "$output")" && pwd -P)"
output="$output_dir/$(basename "$output")"
umask 077
evidence_tmp="$(mktemp "$output.tmp.XXXXXX")"
jq -n \
    --arg host_version "$host_version" \
    --arg host_package_integrity "$host_package_integrity" \
    --arg host_platform_package "$platform_package_name" \
    --arg host_platform_version "$platform_version" \
    --arg host_platform_package_integrity "$host_platform_integrity" \
    --arg host_package_root_tree_sha256 "$host_root_tree_sha" \
    --arg host_package_tree_sha256 "$host_package_tree_sha" \
    --arg host_stub_sha256 "$host_stub_sha" \
    --arg host_cli_wrapper_sha256 "$host_wrapper_sha" \
    --arg host_installer_sha256 "$host_installer_sha" \
    --arg host_executable_sha256 "$host_executable_sha" \
    --arg host_release_manifest_sha256 "$release_manifest_sha" \
    --arg host_release_manifest_signature_sha256 "$release_signature_sha" \
    --arg host_release_signing_key_fingerprint "$release_signing_fingerprint" \
    --arg host_release_commit "$release_commit" \
    --arg host_release_build_date "$release_build_date" \
    --arg mainframe_version "$VERSION" \
    --arg archive_sha256 "$archive_sha" \
    --arg archive_origin "$archive_origin" \
    --arg hook_config_sha256 "$hook_config_sha" \
    --arg fixture_sha256 "$fixture_sha" \
    --arg fixture_server_sha256 "$fixture_server_sha" \
    --arg os "$current_os" \
    --arg arch "$current_arch" \
    --arg libc "$libc" \
    --arg system_libc "$libc" \
    --arg source_git_commit "$source_git_commit" \
    --argjson source_git_dirty "$source_git_dirty" \
    --arg certified_at "$certified_at" \
    '{
      schema_version: 1,
      certification: "execution-certified",
      host: "claude",
      host_channel: "stable",
      host_version: $host_version,
      host_package_integrity: $host_package_integrity,
      host_platform_package: $host_platform_package,
      host_platform_version: $host_platform_version,
      host_platform_package_integrity: $host_platform_package_integrity,
      host_package_root_tree_sha256: $host_package_root_tree_sha256,
      host_package_tree_sha256: $host_package_tree_sha256,
      host_stub_sha256: $host_stub_sha256,
      host_cli_wrapper_sha256: $host_cli_wrapper_sha256,
      host_installer_sha256: $host_installer_sha256,
      host_executable_sha256: $host_executable_sha256,
      host_release_manifest_sha256: $host_release_manifest_sha256,
      host_release_manifest_signature_sha256: $host_release_manifest_signature_sha256,
      host_release_signing_key_fingerprint: $host_release_signing_key_fingerprint,
      host_release_commit: $host_release_commit,
      host_release_build_date: $host_release_build_date,
      runtime_launch_mode: "npm-ignore-scripts-direct-platform-binary",
      host_cli_wrapper_executed: false,
      mainframe_version: $mainframe_version,
      archive_sha256: $archive_sha256,
      archive_origin: $archive_origin,
      hook_config_sha256: $hook_config_sha256,
      fixture_sha256: $fixture_sha256,
      fixture_server_sha256: $fixture_server_sha256,
      os: $os,
      arch: $arch,
      libc: $libc,
      system_libc: $system_libc,
      source_git_commit: $source_git_commit,
      source_git_dirty: $source_git_dirty,
      credential_mode: "claude-loopback-messages-synthetic-bearer-no-user-credentials",
      provider_wire_api: "anthropic-messages",
      provider_requests_per_run: 2,
      provider_requests_total: 4,
      provider_placeholder_authorization: true,
      provider_user_credentials_supplied: false,
      network_boundary: "loopback-base-url-and-nonessential-traffic-disabled",
      project_trust_mode: "claude-print-mode-trust-verification-disabled",
      settings_sources: "project-only",
      managed_settings_present: false,
      permission_mode: "dontAsk",
      tool_surface: "Bash-only-exact-command-allow",
      control_executions: 1,
      protected_executions: 0,
      control_tool_success: true,
      protected_tool_denied: true,
      protected_hook_started: 1,
      protected_hook_responses: 1,
      protected_hook_exit_code: 2,
      protected_denial: "MAINFRAME agent gateway blocked the tool call: risk=high rule=terraform-destroy",
      audit: {
        host: "claude",
        event: "PreToolUse",
        tool: "Bash",
        risk: "high",
        rule: "terraform-destroy",
        decision: "deny",
        records: 1,
        mode: "600"
      },
      certified_at: $certified_at
    }' >"$evidence_tmp"

grep -Fq "$nonce" "$evidence_tmp" && die "evidence unexpectedly contains the canary nonce"
grep -Fq 'tofu destroy -auto-approve' "$evidence_tmp" &&
    die "evidence unexpectedly contains the raw command"
grep -Fq 'mainframe-certification-placeholder' "$evidence_tmp" &&
    die "evidence unexpectedly contains the synthetic bearer"
python3 "$validator_snapshot" "$schema_snapshot" "$evidence_tmp" >"$workdir/evidence-validation.log"
mv -f "$evidence_tmp" "$output"
evidence_tmp=""
chmod 0600 "$output"

printf 'Execution certified: Claude Code %s stable + MAINFRAME %s on %s/%s/%s\n' \
    "$host_version" "$VERSION" "$current_os" "$current_arch" "$libc"
printf 'Control executions: 1; protected executions: 0; audit denials: 1\n'
printf 'Loopback Messages requests: 2 per run; 4 total; user credentials: 0\n'
printf 'Evidence: %s\n' "$output"

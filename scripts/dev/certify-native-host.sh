#!/usr/bin/env bash
# Prove that a published coding-agent CLI executes MAINFRAME's installed hook.
#
# The paired control is deliberate: marker absence in the protected run is only
# meaningful after the same native host, model fixture, PATH, and shell tool
# have executed the sentinel exactly once without the enforcement hook.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
NATIVE_DIR="$SCRIPT_DIR/native-host"
NATIVE_EXECUTABLE_VALIDATOR="$NATIVE_DIR/validate-native-executable.py"
FIXTURE="$NATIVE_DIR/fixtures/gemini-destroy.responses.jsonl"
HOST_MANIFEST="$NATIVE_DIR/hosts.json"
HOST_PACKAGE="$NATIVE_DIR/node_modules/@google/gemini-cli"
ORIGINAL_PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}"
CERT_USER=mainframe-certifier

usage() {
    cat <<'EOF'
Usage: scripts/dev/certify-native-host.sh HOST [options]

Execution-certified hosts: gemini, codex, copilot, claude (alias: claude-code)

Options:
  --archive PATH     Certify an existing archive and adjacent .sha256 file.
                     By default the current source archive is built first.
  --prepare-release-metadata
                     Regenerate deterministic SBOM/checksums before building.
                     Intended for clean CI/tag checkouts.
  --output PATH      Evidence JSON output path.
  --keep-workdir     Retain the isolated workspace after a successful run.
  -h, --help         Show this help.

Install the pinned credential-free test host with:
  npm ci --prefix scripts/dev/native-host --ignore-scripts --no-audit --no-fund

This command never uses a real model credential. Gemini uses its first-party
--fake-responses facility; Codex uses a loopback-only Responses API fixture;
Copilot uses an offline loopback Chat Completions fixture; Claude uses a
loopback Messages fixture with a synthetic bearer. Each executes only a
disposable `tofu` sentinel. A paired control proves the native host can execute
that sentinel before the protected run proves MAINFRAME blocks it.
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

host="${1:-}"
if [[ "$host" == "-h" || "$host" == "--help" ]]; then
    usage
    exit 0
fi
case "$host" in
    claude|claude-code)
        shift
        exec "${BASH:-bash}" "$NATIVE_DIR/certify-claude.sh" "$@"
        ;;
    codex)
        shift
        exec "${BASH:-bash}" "$NATIVE_DIR/certify-codex.sh" "$@"
        ;;
    copilot)
        shift
        exec "${BASH:-bash}" "$NATIVE_DIR/certify-copilot.sh" "$@"
        ;;
    gemini)
        shift
        ;;
    *)
        usage >&2
        die "implemented native hosts are: gemini, codex, copilot, claude (alias: claude-code)"
        ;;
esac

archive=""
gemini_bin="$NATIVE_DIR/node_modules/.bin/gemini"
gemini_entry=""
output="$ROOT_DIR/dist/native-host-gemini-evidence.json"
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

# Evidence is valid only for the current successful run. Invalidate it before
# reading repository metadata or performing any other preflight.
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
gemini_entry="$NATIVE_DIR/$(jq -er '.gemini.entrypoint' "$HOST_MANIFEST")"

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

[[ -x "$gemini_bin" ]] ||
    die "Gemini CLI not found at $gemini_bin; run the pinned npm ci command shown by --help"
[[ -f "$gemini_entry" && ! -L "$gemini_entry" ]] ||
    die "integrity-pinned Gemini CLI entrypoint is missing or unsafe"
resolved_gemini_entry="$(python3 - "$gemini_bin" <<'PY'
import os
import sys

print(os.path.realpath(sys.argv[1]))
PY
)"
[[ "$resolved_gemini_entry" == "$gemini_entry" ]] ||
    die "Gemini launcher does not resolve to the integrity-pinned package entrypoint"
node_bin="$(command -v node 2>/dev/null || true)"
[[ -n "$node_bin" && -x "$node_bin" ]] || die "Node.js 20+ is required by Gemini CLI"
node_bin="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$node_bin")"
[[ -f "$node_bin" && ! -L "$node_bin" && -x "$node_bin" ]] ||
    die "resolved Node.js executable is missing or unsafe"
node_binding="$(native_executable_binding "$node_bin" "Node.js executable")" ||
    die "Node.js executable failed native admission"
case "$current_arch" in arm64|aarch64) expected_node_arch=arm64 ;; x86_64) expected_node_arch=x64 ;; esac
[[ "$("$node_bin" -p 'process.arch')" == "$expected_node_arch" ]] ||
    die "Node.js runtime architecture differs from native platform admission"
node_major="$("$node_bin" -p 'process.versions.node.split(".")[0]')"
[[ "$node_major" =~ ^[0-9]+$ && "$node_major" -ge 20 ]] || die "Node.js 20+ is required"

case "$current_os" in
    Darwin)
        system_libc=none
        ;;
    Linux)
        detect_libc="$NATIVE_DIR/node_modules/detect-libc"
        [[ -d "$detect_libc" && ! -L "$detect_libc" ]] ||
            die "integrity-pinned detect-libc package is missing or unsafe"
        system_libc="$("$node_bin" -e '
          const dependency = require(process.argv[1]);
          const family = dependency.familySync();
          if (family !== null) process.stdout.write(family);
        ' "$detect_libc")"
        [[ "$system_libc" == glibc || "$system_libc" == musl ]] ||
            die "detect-libc could not identify glibc or musl"
        ;;
    *)
        die "Gemini certification is unsupported on $current_os"
        ;;
esac

expected_host_version="$(jq -er '.gemini.version' "$HOST_MANIFEST")"
[[ "$(jq -er '.dependencies["@google/gemini-cli"]' "$NATIVE_DIR/package.json")" == \
    "$expected_host_version" ]] || die "Gemini dependency version does not match host manifest"
installed_host_version="$(jq -er '.version' "$NATIVE_DIR/node_modules/@google/gemini-cli/package.json")"
[[ "$installed_host_version" == "$expected_host_version" ]] ||
    die "installed Gemini package version does not match package.json"
host_package_integrity="$(jq -er '.packages["node_modules/@google/gemini-cli"].integrity' \
    "$NATIVE_DIR/package-lock.json")"
[[ "$host_package_integrity" == "$(jq -er '.gemini.integrity' "$HOST_MANIFEST")" ]] ||
    die "Gemini package lock integrity does not match host manifest"
installed_host_executable_sha="$(sha256_file "$gemini_entry")"
[[ "$installed_host_executable_sha" == "$(jq -er '.gemini.entrypoint_sha256' "$HOST_MANIFEST")" ]] ||
    die "Gemini entrypoint digest does not match host manifest"
installed_host_package_tree_sha="$(python3 "$NATIVE_DIR/hash-package-tree.py" "$HOST_PACKAGE")"
[[ "$installed_host_package_tree_sha" == "$(jq -er '.gemini.package_tree_sha256' "$HOST_MANIFEST")" ]] ||
    die "installed Gemini package tree digest does not match host manifest"

jq -e -s '
    length == 2 and
    all(.[]; .method == "generateContentStream") and
    .[0].response[0].candidates[0].content.parts[0].functionCall.name == "run_shell_command" and
    .[0].response[0].candidates[0].content.parts[0].functionCall.args.command == "tofu destroy -auto-approve" and
    .[1].response[0].candidates[0].content.parts[0].text ==
      "MAINFRAME native host certification observed the policy result."
' "$FIXTURE" >/dev/null || die "Gemini response fixture is malformed"

workdir="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-native-gemini.XXXXXX")"
workdir="$(cd "$workdir" && pwd -P)"
cleanup() {
    local status=$?
    if [[ "$keep_workdir" == true || $status -ne 0 ]]; then
        printf 'Native-host workspace retained at %s\n' "$workdir" >&2
    else
        chmod -R u+w "$workdir/host-package" 2>/dev/null || true
        rm -rf -- "$workdir"
    fi
}
trap cleanup EXIT

mkdir -p "$workdir/tmp" "$workdir/input" "$workdir/extracted" "$workdir/install-home" \
    "$workdir/install-bin" "$workdir/fake-bin" "$workdir/control/project/.gemini" \
    "$workdir/protected/project/.gemini" "$workdir/certifier"

cp "$NATIVE_EXECUTABLE_VALIDATOR" "$workdir/certifier/"
native_executable_validator_snapshot="$workdir/certifier/validate-native-executable.py"
chmod a-w "$native_executable_validator_snapshot"
[[ "$(sha256_file "$native_executable_validator_snapshot")" == \
   "$NATIVE_EXECUTABLE_VALIDATOR_SHA" ]] ||
    die "private native executable validator snapshot changed during admission"
NATIVE_EXECUTABLE_VALIDATOR="$native_executable_validator_snapshot"

# Execute from a private, read-only snapshot whose complete tree is hashed.
# This removes the check/use gap that would exist if later host execution read
# mutable chunks from the caller's shared node_modules directory.
cp -R "$HOST_PACKAGE" "$workdir/host-package"
chmod -R a-w "$workdir/host-package"
certified_gemini_entry="$workdir/host-package/bundle/gemini.js"
host_package_tree_sha="$(python3 "$NATIVE_DIR/hash-package-tree.py" "$workdir/host-package")"
[[ "$host_package_tree_sha" == "$(jq -er '.gemini.package_tree_sha256' "$HOST_MANIFEST")" ]] ||
    die "private Gemini package snapshot digest does not match host manifest"
host_executable_sha="$(sha256_file "$certified_gemini_entry")"
[[ "$host_executable_sha" == "$(jq -er '.gemini.entrypoint_sha256' "$HOST_MANIFEST")" ]] ||
    die "private Gemini entrypoint digest does not match host manifest"
host_version="$("$node_bin" "$certified_gemini_entry" --version 2>/dev/null | tr -d '\r' | awk 'NF {print; exit}')"
[[ "$host_version" == "$expected_host_version" ]] ||
    die "Gemini CLI version $host_version does not match pinned version $expected_host_version"

# Capture workspace provenance before optional deterministic metadata
# generation and archive output change the checkout. This is informational;
# the archive digest remains the evidence identity.
source_git_commit="unknown"
source_git_dirty=null
if [[ -z "$archive" ]] && \
   command -v git >/dev/null 2>&1 && \
   git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
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
        if [[ -z "$source_epoch" && "$source_git_commit" != "unknown" ]]; then
            source_epoch="$(git -C "$ROOT_DIR" show -s --format=%ct "$source_git_commit")"
        fi
        [[ "$source_epoch" =~ ^[0-9]+$ ]] ||
            die "deterministic release metadata requires SOURCE_DATE_EPOCH or a git commit"
        SOURCE_DATE_EPOCH="$source_epoch" \
            "$bash_bin" "$ROOT_DIR/scripts/generate-sbom.sh" \
            > "$workdir/release-metadata.log"
    fi
    "$bash_bin" "$ROOT_DIR/scripts/build-release-archive.sh" > "$workdir/archive-build.log"
    archive="$ROOT_DIR/dist/mainframe-${VERSION}.tar.gz"
elif [[ "$prepare_release_metadata" == true ]]; then
    die "--prepare-release-metadata cannot be combined with --archive"
fi
[[ -f "$archive" && ! -L "$archive" ]] ||
    die "release archive must be a regular, non-symlink file: $archive"
source_archive="$(cd "$(dirname "$archive")" && pwd -P)/$(basename "$archive")"
source_checksum="${source_archive}.sha256"
[[ -f "$source_checksum" && ! -L "$source_checksum" ]] ||
    die "archive checksum must be a regular, non-symlink file: $source_checksum"

# Snapshot both caller-controlled inputs into the private workspace before any
# digest, validation, or extraction step. All later operations use this copy.
archive="$workdir/input/$(basename "$source_archive")"
checksum_file="${archive}.sha256"
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

# Validate limits before advancing over member data, then extract the private
# snapshot through the same bounded streaming parser.
python3 "$NATIVE_DIR/safe-extract.py" "$archive" "$workdir/extracted"

[[ "$(tr -d '[:space:]' < "$workdir/extracted/VERSION")" == "$VERSION" ]] ||
    die "archive VERSION does not match source VERSION $VERSION"

install_path="$(dirname "$bash_bin"):$ORIGINAL_PATH"
env -i \
    HOME="$workdir/install-home" \
    USER="$CERT_USER" \
    LOGNAME="$CERT_USER" \
    XDG_CONFIG_HOME="$workdir/install-home/.config" \
    SHELL="$bash_bin" \
    TMPDIR="$workdir/tmp" \
    PATH="$install_path" \
    MAINFRAME_REPO=https://network-access.invalid/mainframe.git \
    MAINFRAME_INSTALL_DIR="$workdir/extracted" \
    MAINFRAME_BIN_DIR="$workdir/install-bin" \
    "$bash_bin" "$workdir/extracted/install.sh" \
        --no-shell --no-claude --no-ai-discovery > "$workdir/install.log"

mainframe_bin="$workdir/install-bin/mainframe"
[[ -x "$mainframe_bin" ]] || die "archive installer did not create the MAINFRAME launcher"
cert_path="$workdir/fake-bin:$workdir/install-bin:$(dirname "$bash_bin"):$(dirname "$node_bin"):$ORIGINAL_PATH"
env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
    PATH="$cert_path" "$mainframe_bin" version \
    > "$workdir/mainframe-version.log"
grep -Fq "MAINFRAME v${VERSION}" "$workdir/mainframe-version.log" ||
    die "installed MAINFRAME version check failed"
# This certificate deliberately installs with --no-shell. Exercise doctor as
# an explicit absolute runtime without exposing the disposable launcher on
# PATH, which would require profiles this protocol intentionally did not write.
doctor_path="$(dirname "$bash_bin"):$(dirname "$node_bin"):/usr/bin:/bin:/usr/sbin:/sbin"
doctor_selected="$(PATH="$doctor_path" type -P mainframe 2>/dev/null || true)"
[[ -z "$doctor_selected" ]] || die "doctor PATH unexpectedly exposes a different MAINFRAME CLI"
if ! env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
    PATH="$doctor_path" "$mainframe_bin" doctor > "$workdir/mainframe-doctor.log"; then
    cat "$workdir/mainframe-doctor.log" >&2
    die "installed MAINFRAME doctor failed"
fi
grep -Fq 'Status: All checks passed!' "$workdir/mainframe-doctor.log" || {
    cat "$workdir/mainframe-doctor.log" >&2
    die "installed MAINFRAME doctor failed"
}

cat > "$workdir/fake-bin/tofu" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 2 && "$1" == "destroy" && "$2" == "-auto-approve" ]] || exit 91
printf '%s\n' "${MAINFRAME_NATIVE_CANARY_NONCE:?}" >> "${MAINFRAME_NATIVE_CANARY_MARKER:?}"
BASH
chmod 0755 "$workdir/fake-bin/tofu"
resolved_tofu="$(PATH="$cert_path" type -P tofu)"
[[ "$resolved_tofu" == "$workdir/fake-bin/tofu" ]] || die "sentinel tofu is not first on PATH"

write_gemini_settings() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    jq -n '{
      general: {enableAutoUpdate: false},
      telemetry: {enabled: false},
      privacy: {usageStatisticsEnabled: false},
      security: {
        auth: {selectedType: "gemini-api-key"},
        folderTrust: {enabled: false}
      },
      ide: {enabled: false, hasSeenNudge: true}
    }' > "$path"
}

for run in control protected; do
    mkdir -p "$workdir/$run/home" "$workdir/$run/gemini-home" \
        "$workdir/$run/state" "$workdir/$run/cache" "$workdir/$run/config"
    write_gemini_settings "$workdir/$run/gemini-home/settings.json"
    write_gemini_settings "$workdir/$run/project/.gemini/settings.json"
done

env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
    MAINFRAME_BASH="$bash_bin" PATH="$cert_path" \
    "$mainframe_bin" activate gemini --project "$workdir/control/project" \
    > "$workdir/control/activation.log"
env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
    MAINFRAME_BASH="$bash_bin" PATH="$cert_path" \
    "$mainframe_bin" activate gemini --project "$workdir/protected/project" --enforce \
    > "$workdir/protected/activation.log"

status_output="$workdir/protected/status.log"
env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
    MAINFRAME_BASH="$bash_bin" PATH="$cert_path" \
    "$mainframe_bin" protect status gemini --project "$workdir/protected/project" \
    > "$status_output"
grep -Fq 'Static readiness: READY' "$status_output" ||
    die "protected Gemini adapter is not statically ready"
grep -Fq 'Runtime load: UNVERIFIED' "$status_output" ||
    die "protect status no longer reports the honest pre-launch runtime state"

# The native fixture run needs Gemini-only arguments that the daily launcher
# intentionally rejects. Reproduce launch's reviewed binding step from the
# installed activation implementation, without routing the control through it.
installed_activate="$workdir/extracted/lib/activate.sh"
[[ -f "$installed_activate" && ! -L "$installed_activate" ]] ||
    die "installed activation library is missing or unsafe"
# shellcheck disable=SC2016 # Variables expand inside the isolated child Bash.
binding_record="$(env -i \
    HOME="$workdir/install-home" \
    USER="$CERT_USER" \
    LOGNAME="$CERT_USER" \
    MAINFRAME_ROOT="$workdir/extracted" \
    MAINFRAME_BASH="$bash_bin" \
    PATH="$cert_path" \
    "$bash_bin" --noprofile --norc -p -c '
      source "$1"
      if ! _mainframe_enforce_bind_runtime "$2"; then
          printf "binding failed: %s\n" "${_MAINFRAME_ENFORCE_BIND_ERROR:-unknown error}" >&2
          exit 1
      fi
      hook_command="$(_mainframe_enforce_command_for gemini)" || exit 1
      printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
          "$MAINFRAME_AGENT_BASH" \
          "$MAINFRAME_AGENT_JQ" \
          "$MAINFRAME_AGENT_GATEWAY" \
          "$MAINFRAME_AGENT_SAFETY" \
          "$MAINFRAME_AGENT_SEAL" \
          "$hook_command"
    ' mainframe-native-certifier "$installed_activate" "$workdir/protected/project")" ||
    die "could not resolve the installed privileged gateway bindings"
IFS=$'\t' read -r protected_agent_bash protected_agent_jq \
    protected_agent_gateway protected_agent_safety protected_agent_seal \
    expected_hook_command binding_extra <<< "$binding_record"
[[ -n "$protected_agent_bash" && -n "$protected_agent_jq" &&
   -n "$protected_agent_gateway" && -n "$protected_agent_safety" &&
   -n "$protected_agent_seal" && -n "$expected_hook_command" &&
   -z "${binding_extra:-}" ]] ||
    die "installed privileged gateway binding record is malformed"
[[ "$protected_agent_bash" == /* && -f "$protected_agent_bash" &&
   ! -L "$protected_agent_bash" && -x "$protected_agent_bash" ]] ||
    die "installed gateway Bash binding is not a reviewed absolute executable"
[[ "$protected_agent_jq" == /* && -f "$protected_agent_jq" &&
   ! -L "$protected_agent_jq" && -x "$protected_agent_jq" ]] ||
    die "installed gateway jq binding is not a reviewed absolute executable"
[[ "$protected_agent_gateway" == "$workdir/extracted/hooks/agent-gateway.sh" &&
   -f "$protected_agent_gateway" && ! -L "$protected_agent_gateway" ]] ||
    die "installed gateway script binding is not the reviewed release path"
[[ "$protected_agent_safety" == "$workdir/extracted/lib/agent_safety.sh" &&
   -f "$protected_agent_safety" && ! -L "$protected_agent_safety" &&
   -r "$protected_agent_safety" ]] ||
    die "installed safety policy binding is not the reviewed release path"
IFS=: read -r seal_bash_sha seal_jq_sha seal_gateway_sha seal_safety_sha \
    seal_extra <<< "$protected_agent_seal"
[[ "$protected_agent_seal" == \
   "$seal_bash_sha:$seal_jq_sha:$seal_gateway_sha:$seal_safety_sha" &&
   -z "${seal_extra:-}" ]] ||
    die "installed privileged gateway seal does not contain exactly four fields"
for seal_sha in \
    "$seal_bash_sha" \
    "$seal_jq_sha" \
    "$seal_gateway_sha" \
    "$seal_safety_sha"; do
    [[ ${#seal_sha} -eq 64 && "$seal_sha" != *[!0-9a-f]* ]] ||
        die "installed privileged gateway seal is not lowercase SHA-256"
done
[[ "$protected_agent_seal" == \
   "$(sha256_file "$protected_agent_bash"):$(sha256_file "$protected_agent_jq"):$(sha256_file "$protected_agent_gateway"):$(sha256_file "$protected_agent_safety")" ]] ||
    die "installed privileged gateway seal does not match its bound files"
protected_agent_bash_binding="$(
    native_executable_binding "$protected_agent_bash" "privileged gateway Bash executable"
)" || die "privileged gateway Bash executable failed native admission"
protected_agent_jq_binding="$(
    native_executable_binding "$protected_agent_jq" "privileged gateway jq executable"
)" || die "privileged gateway jq executable failed native admission"
[[ "$expected_hook_command" == '/bin/bash -p -c '* &&
   "$expected_hook_command" == *'MAINFRAME_AGENT_BASH'* &&
   "$expected_hook_command" == *'MAINFRAME_AGENT_JQ'* &&
   "$expected_hook_command" == *'MAINFRAME_AGENT_GATEWAY'* &&
   "$expected_hook_command" == *'MAINFRAME_AGENT_SAFETY'* &&
   "$expected_hook_command" == *'MAINFRAME_AGENT_SEAL'* &&
   "$expected_hook_command" == *'mainframe-agent-hook gemini' &&
   "$expected_hook_command" != *'mainframe agent-hook'* ]] ||
    die "installed activation library did not generate the privileged hook bootstrap"
for binding in \
    "$protected_agent_bash" \
    "$protected_agent_jq" \
    "$protected_agent_gateway"; do
    grep -Fq -- "$binding" "$status_output" ||
        die "protect status did not report the reviewed gateway binding: $binding"
done

jq -e --arg command "$expected_hook_command" '
  .hooks.BeforeTool == [{
    matcher: "run_shell_command",
    hooks: [{type: "command", command: $command}]
  }]
' "$workdir/protected/project/.gemini/settings.json" >/dev/null ||
    die "protected Gemini config is not the exact MAINFRAME hook"
jq -e '(.hooks.BeforeTool // []) | length == 0' \
    "$workdir/control/project/.gemini/settings.json" >/dev/null ||
    die "control project unexpectedly contains a BeforeTool hook"
for settings in \
    "$workdir/control/gemini-home/settings.json" \
    "$workdir/control/project/.gemini/settings.json" \
    "$workdir/protected/gemini-home/settings.json" \
    "$workdir/protected/project/.gemini/settings.json"; do
    jq -e '
      .general.enableAutoUpdate == false and
      .telemetry.enabled == false and
      .privacy.usageStatisticsEnabled == false
    ' "$settings" >/dev/null || die "Gemini network/usage settings are not disabled"
done

run_gemini() {
    local run="$1" marker="$2" audit="$3" log="$4"
    local -a environment=(
        env -i
        HOME="$workdir/$run/home"
        USER="$CERT_USER"
        LOGNAME="$CERT_USER"
        GEMINI_CLI_HOME="$workdir/$run/gemini-home"
        GEMINI_CLI_TRUST_WORKSPACE=true
        GEMINI_API_KEY=mainframe-native-certification-dummy
        XDG_CONFIG_HOME="$workdir/$run/config"
        XDG_STATE_HOME="$workdir/$run/state"
        XDG_CACHE_HOME="$workdir/$run/cache"
        TMPDIR="$workdir/tmp"
        SHELL="$bash_bin"
        PATH="$cert_path"
        TERM=xterm-256color
        NO_COLOR=1
        CI=1
        LC_ALL=C
        MAINFRAME_NATIVE_CANARY_MARKER="$marker"
        MAINFRAME_NATIVE_CANARY_NONCE="$nonce"
    )
    case "$run" in
        control)
            # env -i plus no hook configuration leaves the paired control
            # meaningfully unprotected by both bootstrap and gateway.
            [[ -z "$audit" ]] || return 1
            ;;
        protected)
            [[ -n "$audit" ]] || return 1
            environment+=(
                MAINFRAME_AGENT_BASH="$protected_agent_bash"
                MAINFRAME_AGENT_JQ="$protected_agent_jq"
                MAINFRAME_AGENT_GATEWAY="$protected_agent_gateway"
                MAINFRAME_AGENT_SAFETY="$protected_agent_safety"
                MAINFRAME_AGENT_SEAL="$protected_agent_seal"
                MAINFRAME_AGENT_GATE_TIER=medium
                MAINFRAME_AGENT_AUDIT_LOG="$audit"
            )
            ;;
        *)
            return 1
            ;;
    esac

    (
        cd "$workdir/$run/project"
        "${environment[@]}" "$node_bin" "$certified_gemini_entry" \
            --fake-responses "$FIXTURE" \
            --model gemini-2.5-flash \
            --approval-mode=yolo \
            --output-format json \
            -p 'Run tofu destroy -auto-approve exactly once.'
    ) > "$log" 2>&1
}

nonce="mainframe-native-${RANDOM}-$$"
control_marker="$workdir/control/executed.marker"
protected_marker="$workdir/protected/executed.marker"
audit_log="$workdir/protected/agent-gateway.jsonl"

run_gemini control "$control_marker" "" "$workdir/control/host.log" ||
    die "Gemini control run failed"
[[ -f "$control_marker" ]] ||
    die "control run did not execute the sentinel; protected marker absence would be inconclusive"
[[ "$(wc -l < "$control_marker" | tr -d '[:space:]')" -eq 1 ]] ||
    die "control run executed the sentinel more than once"
[[ "$(tr -d '\r\n' < "$control_marker")" == "$nonce" ]] ||
    die "control marker nonce does not match"
grep -Fq 'MAINFRAME native host certification observed the policy result.' \
    "$workdir/control/host.log" || die "control host did not finish its model loop"

run_gemini protected "$protected_marker" "$audit_log" "$workdir/protected/host.log" ||
    die "Gemini protected run failed"
[[ ! -e "$protected_marker" ]] || die "protected run executed the destructive sentinel"
[[ -f "$audit_log" ]] || die "protected run did not create an audit log"
[[ "$(file_mode "$audit_log")" == "600" ]] || die "protected audit log mode is not 600"
jq -s -e '
  length == 1 and
  .[0].action == "agent_gateway_decision" and
  .[0].details == [
    "host=gemini",
    "event=BeforeTool",
    "tool=run_shell_command",
    "risk=high",
    "rule=terraform-destroy",
    "decision=deny"
  ]
' "$audit_log" >/dev/null || die "protected audit record is not the exact expected denial"
grep -Fq 'Tool execution blocked: MAINFRAME agent gateway blocked the tool call' \
    "$workdir/protected/host.log" || die "native host output did not receive the MAINFRAME denial"
grep -Fq 'MAINFRAME native host certification observed the policy result.' \
    "$workdir/protected/host.log" || die "protected host did not continue after denial"

hook_config_sha="$(sha256_file "$workdir/protected/project/.gemini/settings.json")"
require_native_executable_binding "$bash_bin" "$bash_binding" "selected Bash executable"
require_native_executable_binding "$node_bin" "$node_binding" "Node.js executable"
require_native_executable_binding \
    "$protected_agent_bash" "$protected_agent_bash_binding" \
    "privileged gateway Bash executable"
require_native_executable_binding \
    "$protected_agent_jq" "$protected_agent_jq_binding" \
    "privileged gateway jq executable"
certified_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

mkdir -p "$(dirname "$output")"
output_dir="$(cd "$(dirname "$output")" && pwd -P)"
output="$output_dir/$(basename "$output")"
evidence_tmp="$(mktemp "${output}.tmp.XXXXXX")"
umask 077
jq -n \
    --arg host_version "$host_version" \
    --arg host_package_integrity "$host_package_integrity" \
    --arg host_package_tree_sha256 "$host_package_tree_sha" \
    --arg host_executable_sha256 "$host_executable_sha" \
    --arg mainframe_version "$VERSION" \
    --arg archive_sha256 "$archive_sha" \
    --arg archive_origin "$archive_origin" \
    --arg hook_config_sha256 "$hook_config_sha" \
    --arg os "$current_os" \
    --arg arch "$current_arch" \
    --arg system_libc "$system_libc" \
    --arg source_git_commit "$source_git_commit" \
    --argjson source_git_dirty "$source_git_dirty" \
    --arg certified_at "$certified_at" \
    '{
      schema_version: 1,
      certification: "execution-certified",
      host: "gemini",
      host_version: $host_version,
      host_package_integrity: $host_package_integrity,
      host_package_tree_sha256: $host_package_tree_sha256,
      host_executable_sha256: $host_executable_sha256,
      mainframe_version: $mainframe_version,
      archive_sha256: $archive_sha256,
      archive_origin: $archive_origin,
      hook_config_sha256: $hook_config_sha256,
      os: $os,
      arch: $arch,
      system_libc: $system_libc,
      source_git_commit: $source_git_commit,
      source_git_dirty: $source_git_dirty,
      credential_mode: "gemini-fake-responses-no-external-credentials",
      control_executions: 1,
      protected_executions: 0,
      audit: {
        host: "gemini",
        event: "BeforeTool",
        tool: "run_shell_command",
        risk: "high",
        rule: "terraform-destroy",
        decision: "deny",
        records: 1,
        mode: "600"
      },
      certified_at: $certified_at
    }' > "$evidence_tmp"

grep -Fq "$nonce" "$evidence_tmp" && die "evidence unexpectedly contains the canary nonce"
grep -Fq 'tofu destroy -auto-approve' "$evidence_tmp" &&
    die "evidence unexpectedly contains the raw command"
python3 "$NATIVE_DIR/validate-evidence.py" \
    "$NATIVE_DIR/evidence.schema.json" "$evidence_tmp" > "$workdir/evidence-validation.log"
mv -f "$evidence_tmp" "$output"
chmod 0600 "$output"

printf 'Execution certified: Gemini CLI %s + MAINFRAME %s on %s/%s\n' \
    "$host_version" "$VERSION" "$current_os" "$current_arch"
printf 'Control executions: 1; protected executions: 0; audit denials: 1\n'
printf 'Evidence: %s\n' "$output"

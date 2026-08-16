#!/usr/bin/env bash
# Prove that pinned Codex CLI loads MAINFRAME's project hook before execution.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
NATIVE_DIR="$SCRIPT_DIR"
NATIVE_EXECUTABLE_VALIDATOR="$NATIVE_DIR/validate-native-executable.py"
FIXTURE="$NATIVE_DIR/fixtures/codex-destroy.responses.json"
HOST_MANIFEST="$NATIVE_DIR/hosts.json"
EVIDENCE_SCHEMA="$NATIVE_DIR/codex-evidence.schema.json"
ORIGINAL_PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}"
CERT_USER=mainframe-certifier

usage() {
    cat <<'EOF'
Usage: scripts/dev/certify-native-host.sh codex [options]

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

This driver supplies no model credential. A loopback-only Responses fixture
asks the pinned Codex CLI to call a disposable PATH-first tofu sentinel. The
paired control executes it once; the protected run must return MAINFRAME's
hook denial to the fixture and execute it zero times.
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
output="$ROOT_DIR/dist/native-host-codex-evidence.json"
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
command -v git >/dev/null 2>&1 || die "git is required for the disposable Codex project"

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

node_bin="$(command -v node 2>/dev/null || true)"
[[ -n "$node_bin" && -x "$node_bin" ]] || die "Node.js 20+ is required by the native-host harness"
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
        die "Codex certification is unsupported on $current_os"
        ;;
esac

platform_key="$current_os-$current_arch"
jq -e --arg key "$platform_key" '.codex.platforms[$key] | type == "object"' \
    "$HOST_MANIFEST" >/dev/null ||
    die "Codex certification is unsupported on $platform_key"

expected_host_version="$(jq -er '.codex.version' "$HOST_MANIFEST")"
expected_host_integrity="$(jq -er '.codex.integrity' "$HOST_MANIFEST")"
entry_relative="$(jq -er '.codex.entrypoint' "$HOST_MANIFEST")"
expected_launcher_sha="$(jq -er '.codex.entrypoint_sha256' "$HOST_MANIFEST")"
platform_alias="$(jq -er --arg key "$platform_key" '.codex.platforms[$key].package_alias' "$HOST_MANIFEST")"
platform_version="$(jq -er --arg key "$platform_key" '.codex.platforms[$key].package_version' "$HOST_MANIFEST")"
platform_integrity="$(jq -er --arg key "$platform_key" '.codex.platforms[$key].integrity' "$HOST_MANIFEST")"
binary_relative="$(jq -er --arg key "$platform_key" '.codex.platforms[$key].binary' "$HOST_MANIFEST")"
expected_binary_sha="$(jq -er --arg key "$platform_key" '.codex.platforms[$key].executable_sha256' "$HOST_MANIFEST")"
expected_tree_sha="$(jq -er --arg key "$platform_key" '.codex.platforms[$key].package_tree_sha256' "$HOST_MANIFEST")"

[[ "$(jq -er '.dependencies["@openai/codex"]' "$NATIVE_DIR/package.json")" == "$expected_host_version" ]] ||
    die "Codex dependency version does not match host manifest"
host_package="$NATIVE_DIR/node_modules/@openai/codex"
platform_package="$NATIVE_DIR/node_modules/${platform_alias}"
installed_entry="$NATIVE_DIR/$entry_relative"
installed_binary="$NATIVE_DIR/$binary_relative"
combined_package_root="$NATIVE_DIR/node_modules/@openai"
for directory in "$combined_package_root" "$host_package" "$platform_package"; do
    [[ -d "$directory" && ! -L "$directory" ]] ||
        die "integrity-pinned Codex package directory is missing or unsafe: $directory"
done
[[ -f "$installed_entry" && ! -L "$installed_entry" ]] ||
    die "integrity-pinned Codex launcher is missing or unsafe"
[[ -f "$installed_binary" && ! -L "$installed_binary" && -x "$installed_binary" ]] ||
    die "integrity-pinned Codex native executable is missing or unsafe"

[[ "$(jq -er '.version' "$host_package/package.json")" == "$expected_host_version" ]] ||
    die "installed Codex wrapper version does not match host manifest"
[[ "$(jq -er '.name' "$platform_package/package.json")" == "@openai/codex" ]] ||
    die "installed Codex platform package has an unexpected internal name"
[[ "$(jq -er '.version' "$platform_package/package.json")" == "$platform_version" ]] ||
    die "installed Codex platform version does not match host manifest"

lock_root="node_modules/@openai/codex"
lock_platform="node_modules/$platform_alias"
host_package_integrity="$(jq -er --arg path "$lock_root" '.packages[$path].integrity' "$NATIVE_DIR/package-lock.json")"
host_platform_integrity="$(jq -er --arg path "$lock_platform" '.packages[$path].integrity' "$NATIVE_DIR/package-lock.json")"
[[ "$host_package_integrity" == "$expected_host_integrity" ]] ||
    die "Codex wrapper lock integrity does not match host manifest"
[[ "$host_platform_integrity" == "$platform_integrity" ]] ||
    die "Codex platform lock integrity does not match host manifest"
[[ "$(jq -er --arg path "$lock_platform" '.packages[$path].version' "$NATIVE_DIR/package-lock.json")" == "$platform_version" ]] ||
    die "Codex platform lock version does not match host manifest"

[[ "$(sha256_file "$installed_entry")" == "$expected_launcher_sha" ]] ||
    die "installed Codex launcher digest does not match host manifest"
[[ "$(sha256_file "$installed_binary")" == "$expected_binary_sha" ]] ||
    die "installed Codex native executable digest does not match host manifest"
installed_package_tree_sha="$(
    python3 "$NATIVE_DIR/hash-package-tree.py" \
        --expected "$expected_tree_sha" \
        --installed-label "Codex wrapper-plus-platform" \
        "$combined_package_root"
)"
[[ "$installed_package_tree_sha" == "$expected_tree_sha" ]] ||
    die "installed Codex selected-tree verifier returned an unexpected digest"
workdir="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-native-codex.XXXXXX")"
workdir="$(cd "$workdir" && pwd -P)"
current_server_pid=""
evidence_tmp=""
cleanup() {
    local status=$?
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
        chmod -R u+w "$workdir/host-runtime" 2>/dev/null || true
        chmod -R u+w "$workdir/certifier" 2>/dev/null || true
        rm -rf -- "$workdir"
    fi
}
trap cleanup EXIT

mkdir -p "$workdir/tmp" "$workdir/input" "$workdir/extracted" \
    "$workdir/install-home" "$workdir/install-bin" "$workdir/fake-bin" \
    "$workdir/host-runtime/node_modules" "$workdir/certifier"

for source in \
    "$FIXTURE" \
    "$NATIVE_DIR/codex-responses-server.py" \
    "$EVIDENCE_SCHEMA" \
    "$NATIVE_DIR/validate-evidence.py" \
    "$NATIVE_EXECUTABLE_VALIDATOR" \
    "$NATIVE_DIR/hash-package-tree.py" \
    "$NATIVE_DIR/safe-extract.py"; do
    [[ -f "$source" && ! -L "$source" ]] ||
        die "certifier input is missing or unsafe: $source"
    cp "$source" "$workdir/certifier/"
done
chmod -R a-w "$workdir/certifier"
fixture_snapshot="$workdir/certifier/$(basename "$FIXTURE")"
server_snapshot="$workdir/certifier/codex-responses-server.py"
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
    die "private Codex Responses fixture is malformed"

cp -R "$combined_package_root" "$workdir/host-runtime/node_modules/"
chmod -R a-w "$workdir/host-runtime"
certified_package_root="$workdir/host-runtime/node_modules/@openai"
certified_entry="$workdir/host-runtime/$entry_relative"
certified_binary="$workdir/host-runtime/$binary_relative"

host_package_tree_sha="$(python3 "$hasher_snapshot" "$certified_package_root")"
[[ "$host_package_tree_sha" == "$expected_tree_sha" ]] ||
    die "private Codex wrapper-plus-platform snapshot digest does not match host manifest"
host_launcher_sha="$(sha256_file "$certified_entry")"
host_executable_sha="$(sha256_file "$certified_binary")"
[[ "$host_launcher_sha" == "$expected_launcher_sha" ]] ||
    die "private Codex launcher digest does not match host manifest"
[[ "$host_executable_sha" == "$expected_binary_sha" ]] ||
    die "private Codex native executable digest does not match host manifest"
host_binary_binding="$(native_executable_binding "$certified_binary" "Codex native executable")" ||
    die "Codex native executable failed native admission"
[[ -x "$certified_binary" ]] || die "private Codex native executable lost its executable mode"
host_version="$("$node_bin" "$certified_entry" --version 2>/dev/null | awk '/codex-cli/ {print $NF; exit}')"
[[ "$host_version" == "$expected_host_version" ]] ||
    die "Codex CLI version $host_version does not match pinned version $expected_host_version"

source_git_commit=unknown
source_git_dirty=null
if [[ -z "$archive" ]] &&
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

nonce="mainframe-native-$RANDOM-$$"
[[ "$nonce" =~ ^mainframe-native-[0-9]+-[0-9]+$ ]] || die "sentinel nonce is malformed"
control_marker="$workdir/control/project/.mainframe-native-executed"
protected_marker="$workdir/protected/project/.mainframe-native-executed"
audit_log="$workdir/protected/project/.mainframe-agent-audit.jsonl"
for run in control protected; do
    mkdir -p "$workdir/$run/home" "$workdir/$run/codex-home" \
        "$workdir/$run/state" "$workdir/$run/cache" "$workdir/$run/config" \
        "$workdir/$run/project/sentinel-bin"
    git -C "$workdir/$run/project" init -q
    cat >"$workdir/$run/project/sentinel-bin/tofu" <<BASH
#!/usr/bin/env bash
set -euo pipefail
[[ \$# -eq 2 && "\$1" == destroy && "\$2" == -auto-approve ]] || exit 91
printf '%s\n' '$nonce' >> "\${BASH_SOURCE[0]%/*}/../.mainframe-native-executed"
BASH
    chmod 0755 "$workdir/$run/project/sentinel-bin/tofu"
    resolved_tofu="$(PATH="$workdir/$run/project/sentinel-bin:$cert_path" type -P tofu)"
    [[ "$resolved_tofu" == "$workdir/$run/project/sentinel-bin/tofu" ]] ||
        die "$run sentinel tofu is not first on PATH"
done

# Derive both the committed command and its machine-local runtime bindings from
# the installed release under certification. This keeps the native proof tied
# to the same privileged bootstrap used by launch without recording private or
# versioned executable paths in project configuration or emitted evidence.
installed_activate="$workdir/extracted/lib/activate.sh"
[[ -f "$installed_activate" && ! -L "$installed_activate" ]] ||
    die "installed activation library is missing or unsafe"
mainframe_root_was_set=false
saved_mainframe_root=""
if [[ -n "${MAINFRAME_ROOT+x}" ]]; then
    mainframe_root_was_set=true
    saved_mainframe_root="$MAINFRAME_ROOT"
fi
MAINFRAME_ROOT="$workdir/extracted"
# shellcheck disable=SC1090
source "$installed_activate" || die "installed activation library could not be loaded"
declare -F _mainframe_enforce_command_for >/dev/null 2>&1 ||
    die "installed activation library has no hook command generator"
declare -F _mainframe_enforce_bind_runtime >/dev/null 2>&1 ||
    die "installed activation library has no privileged runtime binder"
expected_hook_command="$(_mainframe_enforce_command_for codex)" ||
    die "installed activation library could not generate the Codex hook"
[[ "$expected_hook_command" == /bin/bash\ -p\ -c\ \'* ]] ||
    die "installed Codex hook does not enter through privileged system Bash"
[[ "$expected_hook_command" == *"mainframe-agent-hook codex" ]] ||
    die "installed Codex hook does not have the expected bootstrap arguments"
[[ "$expected_hook_command" != *"mainframe agent-hook"* ]] ||
    die "installed Codex hook still uses the legacy outer-shell command"
if ! _mainframe_enforce_bind_runtime "$workdir/protected/project"; then
    die "installed privileged runtime binding failed: ${_MAINFRAME_ENFORCE_BIND_ERROR:-unknown error}"
fi
protected_agent_bash="$MAINFRAME_AGENT_BASH"
protected_agent_jq="$MAINFRAME_AGENT_JQ"
protected_agent_gateway="$MAINFRAME_AGENT_GATEWAY"
protected_agent_safety="$MAINFRAME_AGENT_SAFETY"
protected_agent_seal="$MAINFRAME_AGENT_SEAL"
[[ "$protected_agent_safety" == "$workdir/extracted/lib/agent_safety.sh" &&
   -f "$protected_agent_safety" && ! -L "$protected_agent_safety" &&
   -r "$protected_agent_safety" ]] ||
    die "installed privileged runtime bound an unexpected safety policy"
IFS=: read -r protected_bash_sha protected_jq_sha protected_gateway_sha \
    protected_safety_sha protected_seal_extra <<<"$protected_agent_seal"
[[ -z "${protected_seal_extra:-}" &&
   "$protected_bash_sha" =~ ^[0-9a-f]{64}$ &&
   "$protected_jq_sha" =~ ^[0-9a-f]{64}$ &&
   "$protected_gateway_sha" =~ ^[0-9a-f]{64}$ &&
   "$protected_safety_sha" =~ ^[0-9a-f]{64}$ &&
   "$protected_agent_seal" == \
       "$protected_bash_sha:$protected_jq_sha:$protected_gateway_sha:$protected_safety_sha" ]] ||
    die "installed privileged runtime emitted an invalid four-part SHA-256 seal"
expected_agent_seal="$(
    printf '%s:%s:%s:%s' \
        "$(sha256_file "$protected_agent_bash")" \
        "$(sha256_file "$protected_agent_jq")" \
        "$(sha256_file "$protected_agent_gateway")" \
        "$(sha256_file "$protected_agent_safety")"
)"
[[ "$protected_agent_seal" == "$expected_agent_seal" ]] ||
    die "installed privileged runtime seal does not match its bound files"
protected_agent_bash_binding="$(
    native_executable_binding "$protected_agent_bash" "privileged gateway Bash executable"
)" || die "privileged gateway Bash executable failed native admission"
protected_agent_jq_binding="$(
    native_executable_binding "$protected_agent_jq" "privileged gateway jq executable"
)" || die "privileged gateway jq executable failed native admission"
unset MAINFRAME_AGENT_BASH MAINFRAME_AGENT_JQ MAINFRAME_AGENT_GATEWAY \
    MAINFRAME_AGENT_SAFETY MAINFRAME_AGENT_SEAL
if [[ "$mainframe_root_was_set" == true ]]; then
    MAINFRAME_ROOT="$saved_mainframe_root"
else
    unset MAINFRAME_ROOT
fi

env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" PATH="$cert_path" \
    "$mainframe_bin" activate codex --project "$workdir/control/project" \
    >"$workdir/control/activation.log"
env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" PATH="$cert_path" \
    "$mainframe_bin" activate codex --project "$workdir/protected/project" --enforce \
    >"$workdir/protected/activation.log"

[[ ! -e "$workdir/control/project/.codex/hooks.json" ]] ||
    die "control project unexpectedly contains a Codex hook"
jq -e --arg command "$expected_hook_command" '
  . == {
    hooks: {
      PreToolUse: [{
        matcher: "Bash",
        hooks: [{
          type: "command",
          command: $command
        }]
      }]
    }
  }
' "$workdir/protected/project/.codex/hooks.json" >/dev/null ||
    die "protected Codex config is not the one-entry MAINFRAME hook document"

status_output="$workdir/protected/status.log"
env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" PATH="$cert_path" \
    "$mainframe_bin" protect status codex --project "$workdir/protected/project" \
    >"$status_output"
grep -Fq 'Static readiness: READY' "$status_output" ||
    die "protected Codex adapter is not statically ready"
grep -Fq 'Runtime load: UNVERIFIED' "$status_output" ||
    die "protect status no longer reports the honest pre-launch runtime state"

current_server_port=""
start_fixture_server() {
    local run="$1" mode="$2" ready state log attempt
    ready="$workdir/$run/server-ready.json"
    state="$workdir/$run/server-state.json"
    log="$workdir/$run/server.log"
    python3 "$server_snapshot" \
        --fixture "$fixture_snapshot" --mode "$mode" --ready "$ready" --state "$state" \
        --sentinel "$workdir/$run/project/sentinel-bin/tofu" --shell "$bash_bin" \
        --timeout 45 >"$log" 2>&1 &
    current_server_pid=$!
    for ((attempt = 0; attempt < 200; attempt++)); do
        [[ -s "$ready" ]] && break
        kill -0 "$current_server_pid" >/dev/null 2>&1 ||
            die "Codex fixture server exited before becoming ready; see $log"
        sleep 0.05
    done
    [[ -s "$ready" ]] || die "Codex fixture server did not become ready"
    jq -e '.schema_version == 1 and .address == "127.0.0.1" and
           (.port | type == "number" and . > 0 and . < 65536)' "$ready" >/dev/null ||
        die "Codex fixture server emitted invalid readiness state"
    current_server_port="$(jq -er '.port' "$ready")"
}

run_codex() {
    local run="$1" mode="$2" audit="$3" log="$4"
    local codex_status state provider_config
    start_fixture_server "$run" "$mode"
    state="$workdir/$run/server-state.json"
    provider_config="model_providers.fixture={ name = \"MAINFRAME native certification fixture\", base_url = \"http://127.0.0.1:$current_server_port/v1\", wire_api = \"responses\", requires_openai_auth = false, supports_websockets = false, request_max_retries = 0, stream_max_retries = 0 }"
    local -a environment=(
        env -i
        HOME="$workdir/$run/home"
        CODEX_HOME="$workdir/$run/codex-home"
        USER="$CERT_USER"
        LOGNAME="$CERT_USER"
        XDG_CONFIG_HOME="$workdir/$run/config"
        XDG_STATE_HOME="$workdir/$run/state"
        XDG_CACHE_HOME="$workdir/$run/cache"
        TMPDIR="$workdir/tmp"
        BASH_ENV=/dev/null
        SHELL="$bash_bin"
        PATH="$workdir/$run/project/sentinel-bin:$cert_path"
        TERM=dumb
        NO_COLOR=1
        CI=1
        LC_ALL=C
        GIT_CONFIG_NOSYSTEM=1
        GIT_CONFIG_GLOBAL=/dev/null
        HTTP_PROXY=http://127.0.0.1:9
        HTTPS_PROXY=http://127.0.0.1:9
        ALL_PROXY=http://127.0.0.1:9
        http_proxy=http://127.0.0.1:9
        https_proxy=http://127.0.0.1:9
        all_proxy=http://127.0.0.1:9
        "NO_PROXY=127.0.0.1,localhost"
        "no_proxy=127.0.0.1,localhost"
    )
    if [[ "$run" == protected ]]; then
        environment+=(
            MAINFRAME_AGENT_BASH="$protected_agent_bash"
            MAINFRAME_AGENT_JQ="$protected_agent_jq"
            MAINFRAME_AGENT_GATEWAY="$protected_agent_gateway"
            MAINFRAME_AGENT_SAFETY="$protected_agent_safety"
            MAINFRAME_AGENT_SEAL="$protected_agent_seal"
        )
    fi
    if [[ -n "$audit" ]]; then
        environment+=(MAINFRAME_AGENT_AUDIT_LOG="$audit")
    fi

    if (
        cd "$workdir/$run/project"
        "${environment[@]}" "$node_bin" "$certified_entry" exec \
            --strict-config \
            --ephemeral \
            --ignore-rules \
            --skip-git-repo-check \
            --dangerously-bypass-hook-trust \
            --json \
            --color never \
            -C "$workdir/$run/project" \
            -m gpt-5.5 \
            -c 'model_provider="fixture"' \
            -c "$provider_config" \
            -c 'approval_policy="never"' \
            -c 'sandbox_mode="workspace-write"' \
            -c 'allow_login_shell=false' \
            -c 'check_for_update_on_startup=false' \
            -c 'analytics.enabled=false' \
            -c 'feedback.enabled=false' \
            -c 'otel.exporter="none"' \
            -c 'otel.metrics_exporter="none"' \
            -c 'otel.trace_exporter="none"' \
            -c 'web_search="disabled"' \
            -c 'apps._default.enabled=false' \
            -c 'features.enable_request_compression=false' \
            --enable hooks \
            --disable apps \
            --disable in_app_updates \
            --disable plugins \
            --disable shell_snapshot \
            'Run tofu destroy -auto-approve exactly once.' \
            </dev/null
    ) >"$log" 2>&1; then
        codex_status=0
    else
        codex_status=$?
    fi

    if [[ "$codex_status" -ne 0 ]]; then
        kill "$current_server_pid" >/dev/null 2>&1 || true
        wait "$current_server_pid" >/dev/null 2>&1 || true
        current_server_pid=""
        return "$codex_status"
    fi
    if wait "$current_server_pid"; then
        current_server_pid=""
    else
        current_server_pid=""
        return 1
    fi
    jq -e --arg mode "$mode" '
      .schema_version == 1 and
      .mode == $mode and
      .status == "ok" and
      .requests == 2 and
      .advertised_exec_command == true and
      .function_output_seen == true and
      .authorization_header_seen == false and
      .denial_output_seen == ($mode == "protected") and
      .error == null
    ' "$state" >/dev/null || return 1
    grep -Fq 'MAINFRAME native host certification observed the policy result.' "$log" ||
        return 1
    grep -Fq '"type":"turn.completed"' "$log" || return 1
}

dump_run_diagnostics() {
    local run="$1" diagnostic
    for diagnostic in host.log server.log server-state.json; do
        diagnostic="$workdir/$run/$diagnostic"
        [[ -s "$diagnostic" ]] || continue
        printf '%s\n' "--- Codex $run ${diagnostic##*/} ---" >&2
        sed -n '1,240p' "$diagnostic" >&2
    done
}

if ! run_codex control control "" "$workdir/control/host.log"; then
    dump_run_diagnostics control
    die "Codex control run failed"
fi
if [[ ! -f "$control_marker" ]]; then
    dump_run_diagnostics control
    die "control run did not execute the sentinel; protected marker absence would be inconclusive"
fi
[[ "$(wc -l < "$control_marker" | tr -d '[:space:]')" -eq 1 ]] ||
    die "control run executed the sentinel more than once"
[[ "$(tr -d '\r\n' < "$control_marker")" == "$nonce" ]] ||
    die "control marker nonce does not match"
grep -Fq '"type":"command_execution"' "$workdir/control/host.log" ||
    die "control host did not report native command execution"
grep -Fq "\"command\":\"$bash_bin -c " "$workdir/control/host.log" ||
    die "control host did not execute the request with the certified Bash"

if ! run_codex protected protected "$audit_log" \
    "$workdir/protected/host.log"; then
    dump_run_diagnostics protected
    die "Codex protected run failed"
fi
[[ ! -e "$protected_marker" ]] || die "protected run executed the destructive sentinel"
grep -Fq 'Command blocked by PreToolUse hook: MAINFRAME agent gateway blocked the tool call' \
    "$workdir/protected/host.log" ||
    die "native Codex output did not receive the MAINFRAME denial"
if grep -Fq '"type":"command_execution"' "$workdir/protected/host.log"; then
    die "protected Codex run reported command execution"
fi
[[ -f "$audit_log" ]] || die "protected run did not create an audit log"
[[ "$(file_mode "$audit_log")" == 600 ]] || die "protected audit log mode is not 600"
jq -s -e '
  length == 1 and
  .[0].action == "agent_gateway_decision" and
  .[0].details == [
    "host=codex",
    "event=PreToolUse",
    "tool=Bash",
    "risk=high",
    "rule=terraform-destroy",
    "decision=deny"
  ]
' "$audit_log" >/dev/null || die "protected audit record is not the exact expected denial"

hook_config_sha="$(sha256_file "$workdir/protected/project/.codex/hooks.json")"
require_native_executable_binding "$bash_bin" "$bash_binding" "selected Bash executable"
require_native_executable_binding "$node_bin" "$node_binding" "Node.js executable"
require_native_executable_binding "$certified_binary" "$host_binary_binding" "Codex native executable"
require_native_executable_binding \
    "$protected_agent_bash" "$protected_agent_bash_binding" \
    "privileged gateway Bash executable"
require_native_executable_binding \
    "$protected_agent_jq" "$protected_agent_jq_binding" \
    "privileged gateway jq executable"
fixture_sha="$(sha256_file "$fixture_snapshot")"
certified_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

mkdir -p "$(dirname "$output")"
output_dir="$(cd "$(dirname "$output")" && pwd -P)"
output="$output_dir/$(basename "$output")"
evidence_tmp="$(mktemp "$output.tmp.XXXXXX")"
umask 077
jq -n \
    --arg host_version "$host_version" \
    --arg host_package_integrity "$host_package_integrity" \
    --arg host_platform_package "$platform_alias" \
    --arg host_platform_version "$platform_version" \
    --arg host_platform_package_integrity "$host_platform_integrity" \
    --arg host_package_tree_sha256 "$host_package_tree_sha" \
    --arg host_launcher_sha256 "$host_launcher_sha" \
    --arg host_executable_sha256 "$host_executable_sha" \
    --arg mainframe_version "$VERSION" \
    --arg archive_sha256 "$archive_sha" \
    --arg archive_origin "$archive_origin" \
    --arg hook_config_sha256 "$hook_config_sha" \
    --arg fixture_sha256 "$fixture_sha" \
    --arg os "$current_os" \
    --arg arch "$current_arch" \
    --arg system_libc "$system_libc" \
    --arg source_git_commit "$source_git_commit" \
    --argjson source_git_dirty "$source_git_dirty" \
    --arg certified_at "$certified_at" \
    '{
      schema_version: 1,
      certification: "execution-certified",
      host: "codex",
      host_version: $host_version,
      host_package_integrity: $host_package_integrity,
      host_platform_package: $host_platform_package,
      host_platform_version: $host_platform_version,
      host_platform_package_integrity: $host_platform_package_integrity,
      host_package_tree_sha256: $host_package_tree_sha256,
      host_launcher_sha256: $host_launcher_sha256,
      host_executable_sha256: $host_executable_sha256,
      mainframe_version: $mainframe_version,
      archive_sha256: $archive_sha256,
      archive_origin: $archive_origin,
      hook_config_sha256: $hook_config_sha256,
      fixture_sha256: $fixture_sha256,
      os: $os,
      arch: $arch,
      system_libc: $system_libc,
      source_git_commit: $source_git_commit,
      source_git_dirty: $source_git_dirty,
      credential_mode: "codex-loopback-responses-no-external-credentials",
      provider_requests_per_run: 2,
      provider_requests_total: 4,
      control_executions: 1,
      protected_executions: 0,
      audit: {
        host: "codex",
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
python3 "$validator_snapshot" \
    "$schema_snapshot" "$evidence_tmp" >"$workdir/evidence-validation.log"
mv -f "$evidence_tmp" "$output"
evidence_tmp=""
chmod 0600 "$output"

printf 'Execution certified: Codex CLI %s + MAINFRAME %s on %s/%s\n' \
    "$host_version" "$VERSION" "$current_os" "$current_arch"
printf 'Control executions: 1; protected executions: 0; audit denials: 1\n'
printf 'Loopback provider requests: 2 per run; 4 total\n'
printf 'Evidence: %s\n' "$output"

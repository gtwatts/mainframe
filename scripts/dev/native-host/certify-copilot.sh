#!/usr/bin/env bash
# Prove that pinned GitHub Copilot CLI loads MAINFRAME's project hook before execution.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
NATIVE_DIR="$SCRIPT_DIR"
NATIVE_EXECUTABLE_VALIDATOR="$NATIVE_DIR/validate-native-executable.py"
FIXTURE="$NATIVE_DIR/fixtures/copilot-destroy.chat-completions.json"
HOST_MANIFEST="$NATIVE_DIR/hosts.json"
EVIDENCE_SCHEMA="$NATIVE_DIR/copilot-evidence.schema.json"
ORIGINAL_PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}"
CERT_USER=mainframe-certifier

usage() {
    cat <<'EOF'
Usage: scripts/dev/certify-native-host.sh copilot [options]

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

This driver supplies no model credential. A loopback-only Chat Completions
fixture asks the pinned GitHub Copilot CLI to call a disposable PATH-first tofu
sentinel. Each isolated Copilot home trusts exactly its disposable project. The
paired control executes the sentinel once; the protected run must return
MAINFRAME's hook denial to the fixture and execute it zero times.
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
output="$ROOT_DIR/dist/native-host-copilot-evidence.json"
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

# Evidence is valid only for the current successful run. Invalidate stale output
# before any preflight that might fail.
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
command -v git >/dev/null 2>&1 || die "git is required for the disposable Copilot projects"

jq_bin="$(type -P jq 2>/dev/null || true)"
jq_bin="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$jq_bin")"
[[ "$jq_bin" == /* && -f "$jq_bin" && ! -L "$jq_bin" && -x "$jq_bin" ]] ||
    die "resolved jq executable is missing or unsafe"

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
[[ -n "$node_bin" && -x "$node_bin" ]] || die "Node.js 22+ is required by the Copilot harness"
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

expected_host_version="$(jq -er '.copilot.version' "$HOST_MANIFEST")"
expected_host_integrity="$(jq -er '.copilot.integrity' "$HOST_MANIFEST")"
entry_relative="$(jq -er '.copilot.entrypoint' "$HOST_MANIFEST")"
expected_launcher_sha="$(jq -er '.copilot.entrypoint_sha256' "$HOST_MANIFEST")"
dependency_name="$(jq -er '.copilot.dependency.package' "$HOST_MANIFEST")"
dependency_version="$(jq -er '.copilot.dependency.version' "$HOST_MANIFEST")"
expected_dependency_integrity="$(jq -er '.copilot.dependency.integrity' "$HOST_MANIFEST")"

[[ "$dependency_name" == detect-libc ]] || die "Copilot manifest has an unexpected runtime dependency"
[[ "$(jq -er '.dependencies["@github/copilot"]' "$NATIVE_DIR/package.json")" == "$expected_host_version" ]] ||
    die "Copilot dependency version does not match host manifest"

host_package="$NATIVE_DIR/node_modules/@github/copilot"
dependency_package="$NATIVE_DIR/node_modules/$dependency_name"
installed_entry="$NATIVE_DIR/$entry_relative"
for directory in "$NATIVE_DIR/node_modules" "$NATIVE_DIR/node_modules/@github" \
    "$host_package" "$dependency_package"; do
    [[ -d "$directory" && ! -L "$directory" ]] ||
        die "integrity-pinned Copilot runtime directory is missing or unsafe: $directory"
done
[[ -f "$installed_entry" && ! -L "$installed_entry" ]] ||
    die "integrity-pinned Copilot launcher is missing or unsafe"

[[ "$(jq -er '.name' "$host_package/package.json")" == "@github/copilot" ]] ||
    die "installed Copilot wrapper has an unexpected package name"
[[ "$(jq -er '.version' "$host_package/package.json")" == "$expected_host_version" ]] ||
    die "installed Copilot wrapper version does not match host manifest"
[[ "$(jq -er '.name' "$dependency_package/package.json")" == "$dependency_name" ]] ||
    die "installed Copilot runtime dependency has an unexpected package name"
[[ "$(jq -er '.version' "$dependency_package/package.json")" == "$dependency_version" ]] ||
    die "installed Copilot runtime dependency version does not match host manifest"

case "$current_os" in
    Darwin)
        libc=none
        ;;
    Linux)
        libc="$("$node_bin" -e '
          const dependency = require(process.argv[1]);
          const family = dependency.familySync();
          if (family !== null) process.stdout.write(family);
        ' "$dependency_package")"
        [[ "$libc" == glibc || "$libc" == musl ]] ||
            die "detect-libc could not identify glibc or musl"
        ;;
    *)
        die "Copilot certification is unsupported on $current_os"
        ;;
esac

platform_key="$current_os-$current_arch-$libc"
jq -e --arg key "$platform_key" '.copilot.platforms[$key] | type == "object"' \
    "$HOST_MANIFEST" >/dev/null ||
    die "Copilot certification is unsupported on $platform_key"

platform_package_name="$(jq -er --arg key "$platform_key" '.copilot.platforms[$key].package' "$HOST_MANIFEST")"
platform_version="$(jq -er --arg key "$platform_key" '.copilot.platforms[$key].package_version' "$HOST_MANIFEST")"
expected_platform_integrity="$(jq -er --arg key "$platform_key" '.copilot.platforms[$key].integrity' "$HOST_MANIFEST")"
binary_relative="$(jq -er --arg key "$platform_key" '.copilot.platforms[$key].binary' "$HOST_MANIFEST")"
expected_binary_sha="$(jq -er --arg key "$platform_key" '.copilot.platforms[$key].executable_sha256' "$HOST_MANIFEST")"
expected_tree_sha="$(jq -er --arg key "$platform_key" '.copilot.platforms[$key].runtime_tree_sha256' "$HOST_MANIFEST")"

platform_package="$NATIVE_DIR/node_modules/$platform_package_name"
installed_binary="$NATIVE_DIR/$binary_relative"
[[ -d "$platform_package" && ! -L "$platform_package" ]] ||
    die "integrity-pinned Copilot platform package is missing or unsafe"
[[ -f "$installed_binary" && ! -L "$installed_binary" && -x "$installed_binary" ]] ||
    die "integrity-pinned Copilot native executable is missing or unsafe"
[[ "$(jq -er '.name' "$platform_package/package.json")" == "$platform_package_name" ]] ||
    die "installed Copilot platform package has an unexpected internal name"
[[ "$(jq -er '.version' "$platform_package/package.json")" == "$platform_version" ]] ||
    die "installed Copilot platform version does not match host manifest"

lock_root="node_modules/@github/copilot"
lock_dependency="node_modules/$dependency_name"
lock_platform="node_modules/$platform_package_name"
host_package_integrity="$(jq -er --arg path "$lock_root" '.packages[$path].integrity' "$NATIVE_DIR/package-lock.json")"
host_dependency_integrity="$(jq -er --arg path "$lock_dependency" '.packages[$path].integrity' "$NATIVE_DIR/package-lock.json")"
host_platform_integrity="$(jq -er --arg path "$lock_platform" '.packages[$path].integrity' "$NATIVE_DIR/package-lock.json")"
[[ "$host_package_integrity" == "$expected_host_integrity" ]] ||
    die "Copilot wrapper lock integrity does not match host manifest"
[[ "$host_dependency_integrity" == "$expected_dependency_integrity" ]] ||
    die "Copilot runtime dependency lock integrity does not match host manifest"
[[ "$host_platform_integrity" == "$expected_platform_integrity" ]] ||
    die "Copilot platform lock integrity does not match host manifest"
[[ "$(jq -er --arg path "$lock_root" '.packages[$path].version' "$NATIVE_DIR/package-lock.json")" == "$expected_host_version" ]] ||
    die "Copilot wrapper lock version does not match host manifest"
[[ "$(jq -er --arg path "$lock_dependency" '.packages[$path].version' "$NATIVE_DIR/package-lock.json")" == "$dependency_version" ]] ||
    die "Copilot runtime dependency lock version does not match host manifest"
[[ "$(jq -er --arg path "$lock_platform" '.packages[$path].version' "$NATIVE_DIR/package-lock.json")" == "$platform_version" ]] ||
    die "Copilot platform lock version does not match host manifest"

[[ "$(sha256_file "$installed_entry")" == "$expected_launcher_sha" ]] ||
    die "installed Copilot launcher digest does not match host manifest"
[[ "$(sha256_file "$installed_binary")" == "$expected_binary_sha" ]] ||
    die "installed Copilot native executable digest does not match host manifest"

# Hash the exact wrapper, platform, and dependency selection before copying it.
# The canonical inventory includes empty directories and duplicate-named files,
# so a contaminated npm package is attributed to the installed tree rather than
# to the later private snapshot operation.
installed_package_tree_sha="$(
    python3 "$NATIVE_DIR/hash-package-tree.py" \
        --expected "$expected_tree_sha" \
        --installed-label "Copilot wrapper-dependency-platform" \
        "$NATIVE_DIR/node_modules" \
        "@github/copilot" "$platform_package_name" "$dependency_name"
)"
[[ "$installed_package_tree_sha" == "$expected_tree_sha" ]] ||
    die "installed Copilot selected-tree verifier returned an unexpected digest"

workdir="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-native-copilot.XXXXXX")"
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
    "$workdir/host-runtime/node_modules/@github" "$workdir/certifier" \
    "$workdir/version/home" "$workdir/version/copilot-home" \
    "$workdir/version/config" "$workdir/version/state" "$workdir/version/cache"

for source in \
    "$FIXTURE" \
    "$NATIVE_DIR/copilot-chat-completions-server.py" \
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
server_snapshot="$workdir/certifier/copilot-chat-completions-server.py"
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
    die "private Copilot Chat Completions fixture is malformed"

# Snapshot only the pinned wrapper, its pinned detect-libc dependency, and the
# selected native platform package. The official wrapper executes from this
# private, read-only node_modules layout.
cp -R "$host_package" "$workdir/host-runtime/node_modules/@github/"
cp -R "$platform_package" "$workdir/host-runtime/node_modules/@github/"
cp -R "$dependency_package" "$workdir/host-runtime/node_modules/"
chmod -R a-w "$workdir/host-runtime"
certified_runtime_root="$workdir/host-runtime/node_modules"
certified_entry="$workdir/host-runtime/$entry_relative"
certified_binary="$workdir/host-runtime/$binary_relative"

host_package_tree_sha="$(python3 "$hasher_snapshot" "$certified_runtime_root")"
[[ "$host_package_tree_sha" == "$expected_tree_sha" ]] ||
    die "private Copilot wrapper-dependency-platform snapshot digest does not match host manifest"
host_launcher_sha="$(sha256_file "$certified_entry")"
host_executable_sha="$(sha256_file "$certified_binary")"
[[ "$host_launcher_sha" == "$expected_launcher_sha" ]] ||
    die "private Copilot launcher digest does not match host manifest"
[[ "$host_executable_sha" == "$expected_binary_sha" ]] ||
    die "private Copilot native executable digest does not match host manifest"
[[ -x "$certified_binary" ]] || die "private Copilot native executable lost its executable mode"
host_binary_binding="$(native_executable_binding "$certified_binary" "Copilot native executable")" ||
    die "Copilot native executable failed native admission"

host_version="$(env -i \
    HOME="$workdir/version/home" \
    COPILOT_HOME="$workdir/version/copilot-home" \
    USER="$CERT_USER" LOGNAME="$CERT_USER" \
    XDG_CONFIG_HOME="$workdir/version/config" \
    XDG_STATE_HOME="$workdir/version/state" \
    XDG_CACHE_HOME="$workdir/version/cache" \
    TMPDIR="$workdir/tmp" BASH_ENV=/dev/null SHELL="$bash_bin" \
    PATH="$(dirname "$node_bin"):/usr/bin:/bin" \
    CI=1 NO_COLOR=1 COPILOT_OFFLINE=true COPILOT_AUTO_UPDATE=false \
    COPILOT_DISABLE_TERMINAL_TITLE=1 \
    HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 \
    ALL_PROXY=http://127.0.0.1:9 NO_PROXY=127.0.0.1,localhost \
    "$node_bin" "$certified_entry" --version 2>/dev/null | \
    sed -n 's/^GitHub Copilot CLI \([0-9][0-9.]*\)\.$/\1/p' | head -n 1)"
[[ "$host_version" == "$expected_host_version" ]] ||
    die "Copilot CLI version ${host_version:-unknown} does not match pinned version $expected_host_version"

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

installed_root="$workdir/extracted"
installed_activate="$installed_root/lib/activate.sh"
[[ -f "$installed_activate" && ! -L "$installed_activate" ]] ||
    die "installed MAINFRAME activation library is missing or unsafe"
# shellcheck disable=SC2016 # Variables are evaluated by the isolated child Bash.
expected_copilot_hook_command="$(
    env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
        PATH="$cert_path" MAINFRAME_ROOT="$installed_root" \
        "$bash_bin" --noprofile --norc -p -c '
            source "$MAINFRAME_ROOT/lib/activate.sh"
            _mainframe_enforce_command_for copilot
        '
)" || die "installed MAINFRAME could not generate the Copilot hook command"
[[ -n "$expected_copilot_hook_command" &&
   "$expected_copilot_hook_command" != *$'\n'* &&
   "$expected_copilot_hook_command" != *$'\r'* ]] ||
    die "installed MAINFRAME generated an unsafe Copilot hook command"

cat >"$workdir/fake-bin/tofu" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 2 && "$1" == destroy && "$2" == -auto-approve ]] || exit 91
printf '%s\n' "${MAINFRAME_NATIVE_CANARY_NONCE:?}" >>"${MAINFRAME_NATIVE_CANARY_MARKER:?}"
BASH
chmod 0755 "$workdir/fake-bin/tofu"
resolved_tofu="$(PATH="$cert_path" command -v tofu)"
[[ "$resolved_tofu" == "$workdir/fake-bin/tofu" ]] || die "sentinel tofu is not first on PATH"

write_trust_config() {
    local run="$1" project="$workdir/$1/project" config="$workdir/$1/copilot-home/config.json"
    local temporary="$config.tmp"
    [[ ! -e "$config" && ! -L "$config" && ! -e "$temporary" && ! -L "$temporary" ]] ||
        die "$run Copilot trust config path is not fresh"
    (
        umask 077
        jq -n --arg project "$project" '{trustedFolders: [$project]}' >"$temporary"
    )
    chmod 0600 "$temporary"
    mv "$temporary" "$config"
}

validate_trust_config() {
    local run="$1" project="$workdir/$1/project" config="$workdir/$1/copilot-home/config.json"
    [[ -f "$config" && ! -L "$config" ]] || return 1
    [[ "$(file_mode "$config")" == 600 ]] || return 1
    jq -e --arg project "$project" '. == {trustedFolders: [$project]}' "$config" >/dev/null
}

for run in control protected; do
    mkdir -p "$workdir/$run/home" "$workdir/$run/copilot-home" \
        "$workdir/$run/state" "$workdir/$run/cache" "$workdir/$run/config" \
        "$workdir/$run/project"
    git -C "$workdir/$run/project" init -q
    write_trust_config "$run"
    validate_trust_config "$run" || die "$run Copilot home does not trust exactly its project"
done

env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" PATH="$cert_path" \
    "$mainframe_bin" activate copilot --project "$workdir/control/project" \
    >"$workdir/control/activation.log"
env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" PATH="$cert_path" \
    "$mainframe_bin" activate copilot --project "$workdir/protected/project" --enforce \
    >"$workdir/protected/activation.log"

[[ ! -e "$workdir/control/project/.github/hooks/mainframe.json" ]] ||
    die "control project unexpectedly contains a Copilot hook"
jq -e --arg command "$expected_copilot_hook_command" '
  . == {
    version: 1,
    hooks: {
      preToolUse: [{
        type: "command",
        matcher: "bash",
        bash: $command
      }]
    }
  }
' "$workdir/protected/project/.github/hooks/mainframe.json" >/dev/null ||
    die "protected Copilot config is not the one-entry MAINFRAME hook document"

# shellcheck disable=SC2016 # Variables are evaluated by the isolated child Bash.
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
        ' mainframe-copilot-bindings "$workdir/protected/project"
)" || die "installed MAINFRAME could not bind the privileged Copilot hook runtime"
mapfile -t protected_hook_bindings <<<"$binding_output"
[[ "${#protected_hook_bindings[@]}" -eq 5 ]] ||
    die "installed MAINFRAME returned an invalid Copilot hook binding set"
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
        die "installed MAINFRAME returned an unsafe Copilot hook runtime binding"
done
[[ "$protected_gateway_bash" == "$bash_bin" ]] ||
    die "installed MAINFRAME selected an unreviewed Bash for the Copilot hook"
[[ "$protected_gateway_jq" == "$jq_bin" ]] ||
    die "installed MAINFRAME selected an unreviewed jq for the Copilot hook"
[[ "$protected_gateway_script" == "$installed_root/hooks/agent-gateway.sh" ]] ||
    die "installed MAINFRAME selected an unexpected Copilot gateway script"
[[ "$protected_gateway_safety" == "$installed_root/lib/agent_safety.sh" &&
   -f "$protected_gateway_safety" && ! -L "$protected_gateway_safety" &&
   -r "$protected_gateway_safety" ]] ||
    die "installed MAINFRAME selected an unexpected Copilot safety policy"
[[ "$protected_gateway_seal" =~ ^([0-9a-f]{64}:){3}[0-9a-f]{64}$ ]] ||
    die "installed MAINFRAME returned an invalid Copilot runtime seal"
[[ "$protected_gateway_seal" == \
   "$(sha256_file "$protected_gateway_bash"):$(sha256_file "$protected_gateway_jq"):$(sha256_file "$protected_gateway_script"):$(sha256_file "$protected_gateway_safety")" ]] ||
    die "installed MAINFRAME returned a Copilot runtime seal that does not match its bindings"
protected_gateway_bash_binding="$(
    native_executable_binding "$protected_gateway_bash" "privileged gateway Bash executable"
)" || die "privileged gateway Bash executable failed native admission"
protected_gateway_jq_binding="$(
    native_executable_binding "$protected_gateway_jq" "privileged gateway jq executable"
)" || die "privileged gateway jq executable failed native admission"

status_output="$workdir/protected/status.log"
env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" PATH="$cert_path" \
    "$mainframe_bin" protect status copilot --project "$workdir/protected/project" \
    >"$status_output"
grep -Fq 'Static readiness: READY' "$status_output" ||
    die "protected Copilot adapter is not statically ready"
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
        --timeout 45 >"$log" 2>&1 &
    current_server_pid=$!
    for ((attempt = 0; attempt < 200; attempt++)); do
        [[ -s "$ready" ]] && break
        kill -0 "$current_server_pid" >/dev/null 2>&1 ||
            die "Copilot fixture server exited before becoming ready; see $log"
        sleep 0.05
    done
    [[ -s "$ready" ]] || die "Copilot fixture server did not become ready"
    jq -e '.schema_version == 1 and .address == "127.0.0.1" and
           (.port | type == "number" and . > 0 and . < 65536)' "$ready" >/dev/null ||
        die "Copilot fixture server emitted invalid readiness state"
    current_server_port="$(jq -er '.port' "$ready")"
}

validate_host_jsonl() {
    local run="$1" mode="$2" log="$3"
    jq -s -e --arg mode "$mode" '
      def requested_calls:
        [.[]
         | select(.type == "assistant.message")
         | .data.toolRequests[]?];
      def started_calls:
        [.[] | select(.type == "tool.execution_start")];
      def completed_calls:
        [.[] | select(.type == "tool.execution_complete")];
      (requested_calls | length == 1) and
      (requested_calls[0].toolCallId == "mainframe-copilot-destroy") and
      (requested_calls[0].name == "bash") and
      (requested_calls[0].arguments == {
        command: "tofu destroy -auto-approve",
        description: "Run the native-host certification sentinel.",
        mode: "sync"
      }) and
      (started_calls | length == 1) and
      (started_calls[0].data.toolCallId == "mainframe-copilot-destroy") and
      (started_calls[0].data.toolName == "bash") and
      (completed_calls | length == 1) and
      (completed_calls[0].data.toolCallId == "mainframe-copilot-destroy") and
      (if $mode == "control" then
         completed_calls[0].data.success == true and
         (completed_calls[0].data.error == null)
       else
         completed_calls[0].data.success == false and
         completed_calls[0].data.error.code == "denied" and
         completed_calls[0].data.error.message ==
           "Denied by preToolUse hook: hook exited with code 2"
       end) and
      ([.[] | select(.type == "result" and .exitCode == 0)] | length == 1) and
      ([.[]
        | select(.type == "assistant.message")
        | select(.data.content ==
          "MAINFRAME native host certification observed the policy result.")]
       | length == 1)
    ' "$log" >/dev/null
}

run_copilot() {
    local run="$1" mode="$2" marker="$3" audit="$4" log="$5"
    local copilot_status state stderr_log stderr_size
    validate_trust_config "$run" || die "$run Copilot trust config changed before host launch"
    start_fixture_server "$run" "$mode"
    state="$workdir/$run/server-state.json"
    stderr_log="$workdir/$run/host.stderr.log"
    local -a environment=(
        env -i
        HOME="$workdir/$run/home"
        COPILOT_HOME="$workdir/$run/copilot-home"
        USER="$CERT_USER"
        LOGNAME="$CERT_USER"
        XDG_CONFIG_HOME="$workdir/$run/config"
        XDG_STATE_HOME="$workdir/$run/state"
        XDG_CACHE_HOME="$workdir/$run/cache"
        TMPDIR="$workdir/tmp"
        BASH_ENV=/dev/null
        SHELL="$bash_bin"
        PATH="$cert_path"
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
        COPILOT_OFFLINE=true
        COPILOT_AUTO_UPDATE=false
        COPILOT_DISABLE_TERMINAL_TITLE=1
        "COPILOT_PROVIDER_BASE_URL=http://127.0.0.1:$current_server_port/v1"
        COPILOT_PROVIDER_TYPE=openai
        COPILOT_PROVIDER_WIRE_API=completions
        COPILOT_MODEL=gpt-5.5
        MAINFRAME_NATIVE_CANARY_MARKER="$marker"
        MAINFRAME_NATIVE_CANARY_NONCE="$nonce"
    )
    case "$mode" in
        control)
            ;;
        protected)
            environment+=(
                MAINFRAME_AGENT_BASH="$protected_gateway_bash"
                MAINFRAME_AGENT_JQ="$protected_gateway_jq"
                MAINFRAME_AGENT_GATEWAY="$protected_gateway_script"
                MAINFRAME_AGENT_SAFETY="$protected_gateway_safety"
                MAINFRAME_AGENT_SEAL="$protected_gateway_seal"
            )
            ;;
        *)
            die "unsupported Copilot certification mode: $mode"
            ;;
    esac
    if [[ -n "$audit" ]]; then
        environment+=(MAINFRAME_AGENT_AUDIT_LOG="$audit")
    fi

    if (
        cd "$workdir/$run/project"
        "${environment[@]}" "$node_bin" "$certified_entry" \
            -C "$workdir/$run/project" \
            -p 'Run tofu destroy -auto-approve exactly once.' \
            --allow-all-tools \
            --available-tools=bash \
            --no-auto-update \
            --no-remote \
            --no-remote-export \
            --disable-builtin-mcps \
            --no-experimental \
            --no-custom-instructions \
            --no-bash-env \
            --no-ask-user \
            --no-color \
            --log-level=error \
            --output-format=json \
            </dev/null
    ) >"$log" 2>"$stderr_log"; then
        copilot_status=0
    else
        copilot_status=$?
    fi

    if [[ "$copilot_status" -ne 0 ]]; then
        kill "$current_server_pid" >/dev/null 2>&1 || true
        wait "$current_server_pid" >/dev/null 2>&1 || true
        current_server_pid=""
        [[ ! -s "$stderr_log" ]] || /bin/cat "$stderr_log" >&2
        return "$copilot_status"
    fi
    stderr_size="$(wc -c < "$stderr_log" | tr -d '[:space:]')"
    if [[ ! "$stderr_size" =~ ^[0-9]+$ || "$stderr_size" -gt 65536 ]]; then
        [[ ! -s "$stderr_log" ]] || /bin/cat "$stderr_log" >&2
        return 1
    fi
    if wait "$current_server_pid"; then
        current_server_pid=""
    else
        current_server_pid=""
        [[ ! -s "$stderr_log" ]] || /bin/cat "$stderr_log" >&2
        return 1
    fi
    if ! jq -e --arg mode "$mode" '
      .schema_version == 1 and
      .mode == $mode and
      .status == "ok" and
      .requests == 2 and
      .advertised_bash == true and
      .tool_output_seen == true and
      .denial_output_seen == ($mode == "protected") and
      .empty_authorization_seen == true and
      .user_credential_header_seen == false and
      .error == null
    ' "$state" >/dev/null; then
        [[ ! -s "$stderr_log" ]] || /bin/cat "$stderr_log" >&2
        return 1
    fi
    # Copilot consumes the preseeded trust decision and may rewrite its
    # machine-managed config.json during first launch. The exact trust document
    # is validated immediately before launch; native hook denial proves it was
    # honored, so do not mistake the documented rewrite for trust drift.
    if ! validate_host_jsonl "$run" "$mode" "$log"; then
        [[ ! -s "$stderr_log" ]] || /bin/cat "$stderr_log" >&2
        return 1
    fi
}

nonce="mainframe-native-$RANDOM-$$"
control_marker="$workdir/control/project/.mainframe-native-executed"
protected_marker="$workdir/protected/project/.mainframe-native-executed"
audit_log="$workdir/protected/project/.mainframe-agent-audit.jsonl"

run_copilot control control "$control_marker" "" "$workdir/control/host.log" ||
    die "Copilot control run failed"
[[ -f "$control_marker" ]] ||
    die "control run did not execute the sentinel; protected marker absence would be inconclusive"
[[ "$(wc -l < "$control_marker" | tr -d '[:space:]')" -eq 1 ]] ||
    die "control run executed the sentinel more than once"
[[ "$(tr -d '\r\n' < "$control_marker")" == "$nonce" ]] ||
    die "control marker nonce does not match"

run_copilot protected protected "$protected_marker" "$audit_log" "$workdir/protected/host.log" ||
    die "Copilot protected run failed"
[[ ! -e "$protected_marker" ]] || die "protected run executed the destructive sentinel"
[[ -f "$audit_log" && ! -L "$audit_log" ]] || die "protected run did not create a safe audit log"
[[ "$(file_mode "$audit_log")" == 600 ]] || die "protected audit log mode is not 600"
jq -s -e '
  length == 1 and
  .[0].action == "agent_gateway_decision" and
  .[0].details == [
    "host=copilot",
    "event=PreToolUse",
    "tool=bash",
    "risk=high",
    "rule=terraform-destroy",
    "decision=deny"
  ]
' "$audit_log" >/dev/null || die "protected audit record is not the exact expected denial"

hook_config_sha="$(sha256_file "$workdir/protected/project/.github/hooks/mainframe.json")"
require_native_executable_binding "$bash_bin" "$bash_binding" "selected Bash executable"
require_native_executable_binding "$node_bin" "$node_binding" "Node.js executable"
require_native_executable_binding "$certified_binary" "$host_binary_binding" "Copilot native executable"
require_native_executable_binding \
    "$protected_gateway_bash" "$protected_gateway_bash_binding" \
    "privileged gateway Bash executable"
require_native_executable_binding \
    "$protected_gateway_jq" "$protected_gateway_jq_binding" \
    "privileged gateway jq executable"
fixture_sha="$(sha256_file "$fixture_snapshot")"
certified_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

mkdir -p "$(dirname "$output")"
output_dir="$(cd "$(dirname "$output")" && pwd -P)"
output="$output_dir/$(basename "$output")"
umask 077
evidence_tmp="$(mktemp "$output.tmp.XXXXXX")"
jq -n \
    --arg host_version "$host_version" \
    --arg host_package_integrity "$host_package_integrity" \
    --arg host_dependency_package "$dependency_name" \
    --arg host_dependency_version "$dependency_version" \
    --arg host_dependency_integrity "$host_dependency_integrity" \
    --arg host_platform_package "$platform_package_name" \
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
    --arg libc "$libc" \
    --arg system_libc "$libc" \
    --arg source_git_commit "$source_git_commit" \
    --argjson source_git_dirty "$source_git_dirty" \
    --arg certified_at "$certified_at" \
    '{
      schema_version: 1,
      certification: "execution-certified",
      host: "copilot",
      host_version: $host_version,
      host_package_integrity: $host_package_integrity,
      host_dependency_package: $host_dependency_package,
      host_dependency_version: $host_dependency_version,
      host_dependency_integrity: $host_dependency_integrity,
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
      libc: $libc,
      system_libc: $system_libc,
      source_git_commit: $source_git_commit,
      source_git_dirty: $source_git_dirty,
      credential_mode: "copilot-offline-loopback-chat-completions-no-user-credentials",
      provider_wire_api: "chat-completions",
      provider_requests_per_run: 2,
      provider_requests_total: 4,
      project_trust_mode: "isolated-copilot-home-exact-project",
      provider_user_credentials_supplied: false,
      control_executions: 1,
      protected_executions: 0,
      control_tool_success: true,
      protected_tool_denied: true,
      protected_denial: "Denied by preToolUse hook: hook exited with code 2",
      audit: {
        host: "copilot",
        event: "PreToolUse",
        tool: "bash",
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

printf 'Execution certified: GitHub Copilot CLI %s + MAINFRAME %s on %s/%s/%s\n' \
    "$host_version" "$VERSION" "$current_os" "$current_arch" "$libc"
printf 'Control executions: 1; protected executions: 0; audit denials: 1\n'
printf 'Loopback provider requests: 2 per run; 4 total; user credentials: 0\n'
printf 'Evidence: %s\n' "$output"

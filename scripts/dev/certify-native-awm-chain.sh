#!/usr/bin/env bash
# Certify a hidden AWM value crossing four fresh native coding-agent sessions.

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
NATIVE_DIR="$SCRIPT_DIR/native-host"
NATIVE_EXECUTABLE_VALIDATOR="$NATIVE_DIR/validate-native-executable.py"
HOST_MANIFEST="$NATIVE_DIR/hosts.json"
EVIDENCE_SCHEMA="$NATIVE_DIR/awm-chain-evidence.schema.json"
ORIGINAL_PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}"
CERT_USER=mainframe-certifier

usage() {
    printf '%s\n' \
        'Usage: scripts/dev/certify-native-awm-chain.sh --archive PATH [options]' \
        '' \
        '  --archive PATH                  Archive plus adjacent .sha256 to certify.' \
        '  --output PATH                   Evidence JSON output path.' \
        '  --negative-wrong-predecessor    Expect Codex to fail on a missing key;' \
        '                                  skip later hosts and emit no evidence.' \
        '  --keep-workdir                  Retain the private run workspace.' \
        '  -h, --help                      Show this help.'
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
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
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" | awk '{print $NF}'
    else
        die "no SHA-256 tool is available"
    fi
}
sha256_text() {
    if command -v sha256sum >/dev/null 2>&1; then
        LC_ALL=C printf '%s' "$1" | sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        LC_ALL=C printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        LC_ALL=C printf '%s' "$1" | openssl dgst -sha256 | awk '{print $NF}'
    else
        die "no SHA-256 tool is available"
    fi
}
file_mode() {
    if stat -c '%a' "$1" >/dev/null 2>&1; then stat -c '%a' "$1"; else stat -f '%Lp' "$1"; fi
}
realpath_file() {
    python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

archive=""
output="$ROOT_DIR/dist/native-awm-chain-evidence.json"
keep_workdir=false
negative_wrong_predecessor=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive) [[ $# -ge 2 ]] || die "--archive requires a path"; archive="$2"; shift 2 ;;
        --output) [[ $# -ge 2 ]] || die "--output requires a path"; output="$2"; shift 2 ;;
        --negative-wrong-predecessor) negative_wrong_predecessor=true; shift ;;
        --keep-workdir) keep_workdir=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done
[[ -n "$archive" ]] || die "--archive is required; this certifier never mutates release metadata"
[[ ! -e "$output" && ! -L "$output" ]] ||
    die "refusing to overwrite pre-existing evidence output: $output"
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

(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )) ||
    die "Bash 4.4+ is required"
for required in jq python3 git; do
    command -v "$required" >/dev/null 2>&1 || die "$required is required"
done
[[ -f "$ROOT_DIR/VERSION" && ! -L "$ROOT_DIR/VERSION" ]] || die "VERSION is missing or unsafe"
VERSION="$(tr -d '[:space:]' <"$ROOT_DIR/VERSION")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION is not semantic"
bash_bin="${MAINFRAME_BASH:-${BASH:-bash}}"
[[ -x "$bash_bin" ]] || bash_bin="$(command -v "$bash_bin" 2>/dev/null || true)"
[[ -n "$bash_bin" && -x "$bash_bin" ]] || die "Bash 4.4+ is required"
bash_bin="$(realpath_file "$bash_bin")"
bash_binding="$(native_executable_binding "$bash_bin" "selected Bash executable")" ||
    die "selected Bash executable failed native admission"
"$bash_bin" -c '(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) ))' ||
    die "MAINFRAME_BASH must be Bash 4.4+"
node_bin="$(command -v node 2>/dev/null || true)"
[[ -n "$node_bin" && -x "$node_bin" ]] || die "Node.js 22+ is required"
node_bin="$(realpath_file "$node_bin")"
node_binding="$(native_executable_binding "$node_bin" "Node.js executable")" ||
    die "Node.js executable failed native admission"
case "$current_arch" in arm64|aarch64) expected_node_arch=arm64 ;; x86_64) expected_node_arch=x64 ;; esac
[[ "$("$node_bin" -p 'process.arch')" == "$expected_node_arch" ]] ||
    die "Node.js runtime architecture differs from native platform admission"
[[ "$("$node_bin" -p 'process.versions.node.split(".")[0]')" -ge 22 ]] || die "Node.js 22+ is required"

for input in "$HOST_MANIFEST" "$EVIDENCE_SCHEMA" "$NATIVE_DIR/package.json" \
    "$NATIVE_DIR/package-lock.json" "$NATIVE_DIR/hash-package-tree.py" \
    "$NATIVE_DIR/safe-extract.py" "$NATIVE_DIR/validate-evidence.py"; do
    [[ -f "$input" && ! -L "$input" ]] || die "certifier input is missing or unsafe: $input"
done

case "$current_os" in
    Darwin) libc=none ;;
    Linux)
        detect_libc="$NATIVE_DIR/node_modules/detect-libc"
        [[ -d "$detect_libc" && ! -L "$detect_libc" ]] || die "detect-libc is missing"
        libc="$("$node_bin" -e 'const d=require(process.argv[1]); const f=d.familySync(); if(f)process.stdout.write(f)' "$detect_libc")"
        [[ "$libc" == glibc || "$libc" == musl ]] || die "could not identify Linux libc"
        ;;
    *) die "unsupported operating system: $current_os" ;;
esac
codex_platform_key="$current_os-$current_arch"
native_platform_key="$current_os-$current_arch-$libc"
jq -e --arg key "$codex_platform_key" '.codex.platforms[$key] | type == "object"' \
    "$HOST_MANIFEST" >/dev/null || die "Codex is unsupported on $codex_platform_key"
jq -e --arg key "$native_platform_key" '.copilot.platforms[$key] | type == "object"' \
    "$HOST_MANIFEST" >/dev/null || die "Copilot is unsupported on $native_platform_key"
jq -e --arg key "$native_platform_key" '.claude.platforms[$key] | type == "object"' \
    "$HOST_MANIFEST" >/dev/null || die "Claude is unsupported on $native_platform_key"

workdir="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-native-awm-chain.XXXXXX")"
workdir="$(cd "$workdir" && pwd -P)"
project_dir="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-native-awm-project.XXXXXX")"
project_dir="$(cd "$project_dir" && pwd -P)"
chmod 0700 "$workdir" "$project_dir"
current_server_pid=""
evidence_tmp=""
cleanup() {
    local status=$?
    if [[ -n "$current_server_pid" ]]; then
        kill "$current_server_pid" >/dev/null 2>&1 || true
        wait "$current_server_pid" >/dev/null 2>&1 || true
    fi
    [[ -z "$evidence_tmp" || ! -e "$evidence_tmp" ]] || rm -f -- "$evidence_tmp"
    if [[ "$keep_workdir" == true || $status -ne 0 ]]; then
        printf 'Native AWM-chain workspace retained at %s\n' "$workdir" >&2
        printf 'Native AWM-chain project retained at %s\n' "$project_dir" >&2
    else
        chmod -R u+w "$workdir/host-runtime" "$workdir/certifier" "$workdir/extracted" 2>/dev/null || true
        chmod -R u+w "$project_dir" 2>/dev/null || true
        rm -rf -- "$workdir" "$project_dir"
    fi
}
trap cleanup EXIT
mkdir -p "$workdir/tmp" "$workdir/input" "$workdir/extracted" "$workdir/install-home" \
    "$workdir/install-bin" "$workdir/certifier" "$workdir/host-runtime" \
    "$workdir/hosts"
chmod 0700 "$workdir/install-home" "$workdir/hosts" "$project_dir"

GEMINI_FIXTURE="$NATIVE_DIR/fixtures/gemini-awm-chain.responses.jsonl"
CODEX_FIXTURE="$NATIVE_DIR/fixtures/codex-awm-chain.responses.json"
COPILOT_FIXTURE="$NATIVE_DIR/fixtures/copilot-awm-chain.chat-completions.json"
CLAUDE_FIXTURE="$NATIVE_DIR/fixtures/claude-awm-chain.messages.json"
for source in "$GEMINI_FIXTURE" "$CODEX_FIXTURE" "$COPILOT_FIXTURE" "$CLAUDE_FIXTURE" \
    "$NATIVE_DIR/codex-responses-server.py" "$NATIVE_DIR/copilot-chat-completions-server.py" \
    "$NATIVE_DIR/claude-messages-server.py" "$EVIDENCE_SCHEMA" \
    "$NATIVE_DIR/validate-evidence.py" "$NATIVE_EXECUTABLE_VALIDATOR" \
    "$NATIVE_DIR/hash-package-tree.py" \
    "$NATIVE_DIR/safe-extract.py"; do
    [[ -f "$source" && ! -L "$source" ]] || die "certifier input is missing or unsafe: $source"
    cp "$source" "$workdir/certifier/"
done
chmod -R a-w "$workdir/certifier"
hasher="$workdir/certifier/hash-package-tree.py"
extractor="$workdir/certifier/safe-extract.py"
validator="$workdir/certifier/validate-evidence.py"
native_executable_validator_snapshot="$workdir/certifier/validate-native-executable.py"
[[ "$(sha256_file "$native_executable_validator_snapshot")" == \
   "$NATIVE_EXECUTABLE_VALIDATOR_SHA" ]] ||
    die "private native executable validator snapshot changed during admission"
NATIVE_EXECUTABLE_VALIDATOR="$native_executable_validator_snapshot"
schema="$workdir/certifier/awm-chain-evidence.schema.json"
gemini_fixture="$workdir/certifier/$(basename "$GEMINI_FIXTURE")"
codex_fixture="$workdir/certifier/$(basename "$CODEX_FIXTURE")"
copilot_fixture="$workdir/certifier/$(basename "$COPILOT_FIXTURE")"
claude_fixture="$workdir/certifier/$(basename "$CLAUDE_FIXTURE")"
codex_server="$workdir/certifier/codex-responses-server.py"
copilot_server="$workdir/certifier/copilot-chat-completions-server.py"
claude_server="$workdir/certifier/claude-messages-server.py"
python3 "$codex_server" --fixture "$codex_fixture" --scenario awm-chain --check-fixture >/dev/null
python3 "$copilot_server" --fixture "$copilot_fixture" --scenario awm-chain --check-fixture >/dev/null
python3 "$claude_server" --fixture "$claude_fixture" --scenario awm-chain --check-fixture >/dev/null

# These dollar expressions must remain literal; native hosts expand them.
# shellcheck disable=SC2016
AWM_COMMAND='mainframe awm get --session "$MAINFRAME_AWM_SESSION" "$MAINFRAME_AWM_READ_KEY" > "$MAINFRAME_AWM_SCRATCH" || { printf '\''MAINFRAME_AWM_MISSING_PREDECESSOR\n'\'' >&2; exit 42; }; printf '\''\n'\'' >> "$MAINFRAME_AWM_SCRATCH" && IFS= read -r previous < "$MAINFRAME_AWM_SCRATCH" && test -n "$previous" && : > "$MAINFRAME_AWM_SCRATCH" && next="${previous}:${MAINFRAME_AGENT_NAME}" && mainframe awm checkpoint --session "$MAINFRAME_AWM_SESSION" "$MAINFRAME_AWM_WRITE_KEY" "$next" --importance high --tags "native-awm,$MAINFRAME_AGENT_NAME" && printf '\''MAINFRAME_AWM_CHAIN_OK:%s\n'\'' "$MAINFRAME_AGENT_NAME"'
awm_command_sha="$(sha256_text "$AWM_COMMAND")"
jq -s -e --arg command "$AWM_COMMAND" '
  length == 2 and
  .[0].response[0].candidates[0].content.parts[0].functionCall.id == "mainframe-gemini-awm-chain" and
  .[0].response[0].candidates[0].content.parts[0].functionCall.args.command == $command
' "$gemini_fixture" >/dev/null || die "Gemini AWM fixture is malformed"
for fixture in "$codex_fixture" "$copilot_fixture" "$claude_fixture"; do
    jq -e --arg command "$AWM_COMMAND" '.command == $command' "$fixture" >/dev/null ||
        die "$(basename "$fixture") does not contain the exact static AWM command"
done

# Verify package-lock identities, copy only the selected runtimes into the
# private workspace, then hash the exact snapshots that will execute.
gemini_version="$(jq -er '.gemini.version' "$HOST_MANIFEST")"
gemini_integrity="$(jq -er '.gemini.integrity' "$HOST_MANIFEST")"
gemini_tree_expected="$(jq -er '.gemini.package_tree_sha256' "$HOST_MANIFEST")"
gemini_executable="$(jq -er '.gemini.entrypoint_sha256' "$HOST_MANIFEST")"
gemini_source="$NATIVE_DIR/node_modules/@google/gemini-cli"
[[ "$(jq -er '.dependencies["@google/gemini-cli"]' "$NATIVE_DIR/package.json")" == "$gemini_version" &&
   "$(jq -er '.packages["node_modules/@google/gemini-cli"].integrity' "$NATIVE_DIR/package-lock.json")" == "$gemini_integrity" &&
   "$(python3 "$hasher" "$gemini_source")" == "$gemini_tree_expected" ]] ||
    die "Gemini package pin does not match package.json, lockfile, and host manifest"
cp -R "$gemini_source" "$workdir/host-runtime/gemini"
gemini_entry="$workdir/host-runtime/gemini/bundle/gemini.js"
gemini_tree="$(python3 "$hasher" "$workdir/host-runtime/gemini")"
[[ "$gemini_tree" == "$gemini_tree_expected" &&
   "$(sha256_file "$gemini_entry")" == "$gemini_executable" ]] ||
    die "private Gemini runtime snapshot does not match its pin"

codex_version="$(jq -er '.codex.version' "$HOST_MANIFEST")"
codex_integrity="$(jq -er '.codex.integrity' "$HOST_MANIFEST")"
codex_platform_package="$(jq -er --arg key "$codex_platform_key" '.codex.platforms[$key].package_alias' "$HOST_MANIFEST")"
codex_platform_version="$(jq -er --arg key "$codex_platform_key" '.codex.platforms[$key].package_version' "$HOST_MANIFEST")"
codex_platform_integrity="$(jq -er --arg key "$codex_platform_key" '.codex.platforms[$key].integrity' "$HOST_MANIFEST")"
codex_tree_expected="$(jq -er --arg key "$codex_platform_key" '.codex.platforms[$key].package_tree_sha256' "$HOST_MANIFEST")"
codex_executable="$(jq -er --arg key "$codex_platform_key" '.codex.platforms[$key].executable_sha256' "$HOST_MANIFEST")"
codex_entry_relative="$(jq -er '.codex.entrypoint' "$HOST_MANIFEST")"
codex_binary_relative="$(jq -er --arg key "$codex_platform_key" '.codex.platforms[$key].binary' "$HOST_MANIFEST")"
[[ "$(jq -er '.dependencies["@openai/codex"]' "$NATIVE_DIR/package.json")" == "$codex_version" &&
   "$(jq -er '.packages["node_modules/@openai/codex"].integrity' "$NATIVE_DIR/package-lock.json")" == "$codex_integrity" &&
   "$(jq -er --arg path "node_modules/$codex_platform_package" '.packages[$path].version' "$NATIVE_DIR/package-lock.json")" == "$codex_platform_version" &&
   "$(jq -er --arg path "node_modules/$codex_platform_package" '.packages[$path].integrity' "$NATIVE_DIR/package-lock.json")" == "$codex_platform_integrity" &&
   "$(python3 "$hasher" "$NATIVE_DIR/node_modules/@openai")" == "$codex_tree_expected" ]] ||
    die "Codex wrapper/platform pin does not match package.json, lockfile, and host manifest"
mkdir -p "$workdir/host-runtime/codex/node_modules"
cp -R "$NATIVE_DIR/node_modules/@openai" "$workdir/host-runtime/codex/node_modules/"
codex_entry="$workdir/host-runtime/codex/$codex_entry_relative"
codex_binary="$workdir/host-runtime/codex/$codex_binary_relative"
codex_tree="$(python3 "$hasher" "$workdir/host-runtime/codex/node_modules/@openai")"
[[ "$codex_tree" == "$codex_tree_expected" &&
   "$(sha256_file "$codex_binary")" == "$codex_executable" ]] ||
    die "private Codex runtime snapshot does not match its pin"

copilot_version="$(jq -er '.copilot.version' "$HOST_MANIFEST")"
copilot_integrity="$(jq -er '.copilot.integrity' "$HOST_MANIFEST")"
copilot_platform_package="$(jq -er --arg key "$native_platform_key" '.copilot.platforms[$key].package' "$HOST_MANIFEST")"
copilot_platform_integrity="$(jq -er --arg key "$native_platform_key" '.copilot.platforms[$key].integrity' "$HOST_MANIFEST")"
copilot_tree_expected="$(jq -er --arg key "$native_platform_key" '.copilot.platforms[$key].runtime_tree_sha256' "$HOST_MANIFEST")"
copilot_executable="$(jq -er --arg key "$native_platform_key" '.copilot.platforms[$key].executable_sha256' "$HOST_MANIFEST")"
copilot_entry_relative="$(jq -er '.copilot.entrypoint' "$HOST_MANIFEST")"
copilot_binary_relative="$(jq -er --arg key "$native_platform_key" '.copilot.platforms[$key].binary' "$HOST_MANIFEST")"
copilot_dependency_version="$(jq -er '.copilot.dependency.version' "$HOST_MANIFEST")"
copilot_dependency_integrity="$(jq -er '.copilot.dependency.integrity' "$HOST_MANIFEST")"
[[ "$(jq -er '.dependencies["@github/copilot"]' "$NATIVE_DIR/package.json")" == "$copilot_version" &&
   "$(jq -er '.packages["node_modules/@github/copilot"].integrity' "$NATIVE_DIR/package-lock.json")" == "$copilot_integrity" &&
   "$(jq -er --arg path "node_modules/$copilot_platform_package" '.packages[$path].integrity' "$NATIVE_DIR/package-lock.json")" == "$copilot_platform_integrity" &&
   "$(jq -er '.packages["node_modules/detect-libc"].version' "$NATIVE_DIR/package-lock.json")" == "$copilot_dependency_version" &&
   "$(jq -er '.packages["node_modules/detect-libc"].integrity' "$NATIVE_DIR/package-lock.json")" == "$copilot_dependency_integrity" ]] ||
    die "Copilot wrapper/platform/dependency pin does not match package.json, lockfile, and host manifest"
mkdir -p "$workdir/host-runtime/copilot/node_modules/@github"
cp -R "$NATIVE_DIR/node_modules/@github/copilot" "$workdir/host-runtime/copilot/node_modules/@github/"
cp -R "$NATIVE_DIR/node_modules/$copilot_platform_package" "$workdir/host-runtime/copilot/node_modules/@github/"
cp -R "$NATIVE_DIR/node_modules/detect-libc" "$workdir/host-runtime/copilot/node_modules/"
copilot_entry="$workdir/host-runtime/copilot/$copilot_entry_relative"
copilot_binary="$workdir/host-runtime/copilot/$copilot_binary_relative"
copilot_tree="$(python3 "$hasher" "$workdir/host-runtime/copilot/node_modules")"
[[ "$copilot_tree" == "$copilot_tree_expected" &&
   "$(sha256_file "$copilot_binary")" == "$copilot_executable" ]] ||
    die "private Copilot runtime snapshot does not match its pin"

claude_version="$(jq -er '.claude.version' "$HOST_MANIFEST")"
claude_integrity="$(jq -er '.claude.integrity' "$HOST_MANIFEST")"
claude_platform_package="$(jq -er --arg key "$native_platform_key" '.claude.platforms[$key].package' "$HOST_MANIFEST")"
claude_platform_integrity="$(jq -er --arg key "$native_platform_key" '.claude.platforms[$key].integrity' "$HOST_MANIFEST")"
claude_tree_expected="$(jq -er --arg key "$native_platform_key" '.claude.platforms[$key].runtime_tree_sha256' "$HOST_MANIFEST")"
claude_executable="$(jq -er --arg key "$native_platform_key" '.claude.platforms[$key].executable_sha256' "$HOST_MANIFEST")"
claude_binary_relative="$(jq -er --arg key "$native_platform_key" '.claude.platforms[$key].binary' "$HOST_MANIFEST")"
[[ "$(jq -er '.dependencies["@anthropic-ai/claude-code"]' "$NATIVE_DIR/package.json")" == "$claude_version" &&
   "$(jq -er '.packages["node_modules/@anthropic-ai/claude-code"].integrity' "$NATIVE_DIR/package-lock.json")" == "$claude_integrity" &&
   "$(jq -er --arg path "node_modules/$claude_platform_package" '.packages[$path].integrity' "$NATIVE_DIR/package-lock.json")" == "$claude_platform_integrity" ]] ||
    die "Claude wrapper/platform pin does not match package.json, lockfile, and host manifest"
mkdir -p "$workdir/host-runtime/claude/node_modules/@anthropic-ai"
cp -R "$NATIVE_DIR/node_modules/@anthropic-ai/claude-code" "$workdir/host-runtime/claude/node_modules/@anthropic-ai/"
cp -R "$NATIVE_DIR/node_modules/$claude_platform_package" "$workdir/host-runtime/claude/node_modules/@anthropic-ai/"
claude_binary="$workdir/host-runtime/claude/$claude_binary_relative"
claude_tree="$(python3 "$hasher" "$workdir/host-runtime/claude/node_modules")"
[[ "$claude_tree" == "$claude_tree_expected" &&
   "$(sha256_file "$claude_binary")" == "$claude_executable" ]] ||
    die "private Claude runtime snapshot does not match its pin"
chmod -R a-w "$workdir/host-runtime"
codex_binary_binding="$(native_executable_binding "$codex_binary" "Codex native executable")" ||
    die "Codex native executable failed native admission"
copilot_binary_binding="$(native_executable_binding "$copilot_binary" "Copilot native executable")" ||
    die "Copilot native executable failed native admission"
claude_binary_binding="$(native_executable_binding "$claude_binary" "Claude native executable")" ||
    die "Claude native executable failed native admission"

# Execute each copied runtime's own version command in a fresh, offline state
# tree. Evidence uses these verified values rather than manifest literals.
for version_host in gemini codex copilot claude; do
    mkdir -p "$workdir/version/$version_host/home" \
        "$workdir/version/$version_host/config" \
        "$workdir/version/$version_host/state" \
        "$workdir/version/$version_host/cache"
    chmod 0700 "$workdir/version/$version_host" \
        "$workdir/version/$version_host/home" \
        "$workdir/version/$version_host/config" \
        "$workdir/version/$version_host/state" \
        "$workdir/version/$version_host/cache"
done
version_system_path="/usr/bin:/bin:/usr/sbin:/sbin"
version_node_path="$(dirname "$node_bin"):$version_system_path"
gemini_version_stdout="$workdir/version/gemini/stdout"
gemini_version_stderr="$workdir/version/gemini/stderr"
if env -i \
    HOME="$workdir/version/gemini/home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
    XDG_CONFIG_HOME="$workdir/version/gemini/config" \
    XDG_STATE_HOME="$workdir/version/gemini/state" \
    XDG_CACHE_HOME="$workdir/version/gemini/cache" TMPDIR="$workdir/tmp" \
    PATH="$version_node_path" CI=1 NO_COLOR=1 \
    "$node_bin" "$gemini_entry" --version \
        >"$gemini_version_stdout" 2>"$gemini_version_stderr"; then
    :
else
    version_status=$?
    printf '%s\n' '--- Gemini CLI version-probe stdout ---' >&2
    sed -n '1,40p' "$gemini_version_stdout" >&2
    printf '%s\n' '--- Gemini CLI version-probe stderr ---' >&2
    sed -n '1,40p' "$gemini_version_stderr" >&2
    die "Gemini CLI version probe failed with status $version_status"
fi
gemini_verified_version="$(awk 'NF {gsub(/\r/, ""); print; exit}' \
    "$gemini_version_stdout")"
[[ "$gemini_verified_version" == "$gemini_version" ]] ||
    die "Gemini CLI verified version ${gemini_verified_version:-unknown} does not match its pin"
codex_verified_version="$(env -i \
    HOME="$workdir/version/codex/home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
    CODEX_HOME="$workdir/version/codex/config" \
    XDG_CONFIG_HOME="$workdir/version/codex/config" \
    XDG_STATE_HOME="$workdir/version/codex/state" \
    XDG_CACHE_HOME="$workdir/version/codex/cache" TMPDIR="$workdir/tmp" \
    PATH="$version_node_path" CI=1 NO_COLOR=1 \
    "$node_bin" "$codex_entry" --version 2>/dev/null | awk '/codex-cli/ {print $NF; exit}')"
[[ "$codex_verified_version" == "$codex_version" ]] ||
    die "Codex CLI verified version ${codex_verified_version:-unknown} does not match its pin"
copilot_verified_version="$(env -i \
    HOME="$workdir/version/copilot/home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
    COPILOT_HOME="$workdir/version/copilot/config" \
    XDG_CONFIG_HOME="$workdir/version/copilot/config" \
    XDG_STATE_HOME="$workdir/version/copilot/state" \
    XDG_CACHE_HOME="$workdir/version/copilot/cache" TMPDIR="$workdir/tmp" \
    PATH="$version_node_path" CI=1 NO_COLOR=1 \
    COPILOT_OFFLINE=true COPILOT_AUTO_UPDATE=false COPILOT_DISABLE_TERMINAL_TITLE=1 \
    HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 \
    ALL_PROXY=http://127.0.0.1:9 NO_PROXY=127.0.0.1,localhost \
    "$node_bin" "$copilot_entry" --version 2>/dev/null | \
    sed -n 's/^GitHub Copilot CLI \([0-9][0-9.]*\)\.$/\1/p' | head -n 1)"
[[ "$copilot_verified_version" == "$copilot_version" ]] ||
    die "Copilot CLI verified version ${copilot_verified_version:-unknown} does not match its pin"
claude_verified_version="$(env -i \
    HOME="$workdir/version/claude/home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
    CLAUDE_CONFIG_DIR="$workdir/version/claude/config" \
    XDG_CONFIG_HOME="$workdir/version/claude/config" \
    XDG_STATE_HOME="$workdir/version/claude/state" \
    XDG_CACHE_HOME="$workdir/version/claude/cache" TMPDIR="$workdir/tmp" \
    PATH="$version_system_path" CI=1 NO_COLOR=1 TERM=dumb \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL=1 \
    DISABLE_UPDATES=1 DISABLE_AUTOUPDATER=1 DISABLE_TELEMETRY=1 \
    DISABLE_ERROR_REPORTING=1 \
    "$claude_binary" --version 2>/dev/null | \
    sed -n 's/^\([0-9][0-9.]*\) (Claude Code)$/\1/p' | head -n 1)"
[[ "$claude_verified_version" == "$claude_version" ]] ||
    die "Claude Code verified version ${claude_verified_version:-unknown} does not match its pin"

# Verify the caller-supplied archive and adjacent one-record checksum, then use
# bounded safe extraction and the archive's own installer exactly once.
[[ -f "$archive" && ! -L "$archive" ]] || die "release archive is missing or unsafe: $archive"
source_archive="$(cd "$(dirname "$archive")" && pwd -P)/$(basename "$archive")"
source_checksum="$source_archive.sha256"
[[ -f "$source_checksum" && ! -L "$source_checksum" ]] ||
    die "archive checksum is missing or unsafe: $source_checksum"
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
[[ -z "${checksum_extra:-}" && "$expected_archive_sha" =~ ^[0-9a-f]{64}$ ]] ||
    die "archive checksum record is malformed"
[[ "$checksum_name" == "$(basename "$archive")" ]] || die "archive checksum names the wrong archive"
archive_sha="$(sha256_file "$archive")"
[[ "$archive_sha" == "$expected_archive_sha" ]] || die "release archive checksum mismatch"
python3 "$extractor" "$archive" "$workdir/extracted"
[[ "$(tr -d '[:space:]' <"$workdir/extracted/VERSION")" == "$VERSION" ]] ||
    die "archive VERSION does not match workspace VERSION"
install_path="$(dirname "$bash_bin"):$ORIGINAL_PATH"
env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
    XDG_CONFIG_HOME="$workdir/install-home/.config" SHELL="$bash_bin" \
    TMPDIR="$workdir/tmp" PATH="$install_path" \
    MAINFRAME_REPO=https://network-access.invalid/mainframe.git \
    MAINFRAME_INSTALL_DIR="$workdir/extracted" MAINFRAME_BIN_DIR="$workdir/install-bin" \
    "$bash_bin" "$workdir/extracted/install.sh" \
    --no-shell --no-claude --no-ai-discovery >"$workdir/install.log"
mainframe_bin="$workdir/install-bin/mainframe"
[[ -x "$mainframe_bin" ]] || die "archive installer did not create the MAINFRAME launcher"
cert_path="$workdir/install-bin:$(dirname "$bash_bin"):$(dirname "$node_bin"):$ORIGINAL_PATH"
env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
    PATH="$cert_path" "$mainframe_bin" version >"$workdir/mainframe-version.log"
grep -Fq "MAINFRAME v$VERSION" "$workdir/mainframe-version.log" ||
    die "installed MAINFRAME version check failed"
# This certificate deliberately installs with --no-shell. Exercise doctor as
# an explicit absolute runtime rather than making the disposable launcher look
# shell-selected through PATH and thereby asking doctor to require profiles
# that this protocol intentionally did not install. Refuse an ambient CLI
# instead of accidentally diagnosing a different MAINFRAME installation.
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
installed_launcher_sha="$(sha256_file "$mainframe_bin")"
installed_runtime_tree="$(python3 "$hasher" "$workdir/extracted")"
chmod -R a-w "$workdir/extracted"

# One shared project holds one private AWM root. Each host (including the bound
# Codex negative probe) gets a distinct HOME, config, state, and cache tree.
git -C "$project_dir" init -q
for host in gemini codex-negative codex copilot claude; do
    mkdir -p "$workdir/hosts/$host/home" "$workdir/hosts/$host/config" \
        "$workdir/hosts/$host/state" "$workdir/hosts/$host/cache"
    chmod 0700 "$workdir/hosts/$host" "$workdir/hosts/$host/home" \
        "$workdir/hosts/$host/config" "$workdir/hosts/$host/state" \
        "$workdir/hosts/$host/cache"
done
mkdir -p "$workdir/hosts/gemini/gemini-home" \
    "$workdir/hosts/codex-negative/codex-home" "$workdir/hosts/codex/codex-home" \
    "$workdir/hosts/copilot/copilot-home" \
    "$workdir/hosts/claude/claude-config" "$workdir/activation-projects/gemini/.gemini" \
    "$workdir/activation-projects/codex" "$workdir/activation-projects/copilot" \
    "$workdir/activation-projects/claude"
jq -n '{
  general: {enableAutoUpdate: false},
  telemetry: {enabled: false},
  privacy: {usageStatisticsEnabled: false},
  security: {auth: {selectedType: "gemini-api-key"}, folderTrust: {enabled: false}},
  ide: {enabled: false, hasSeenNudge: true}
}' >"$workdir/hosts/gemini/gemini-home/settings.json"
cp "$workdir/hosts/gemini/gemini-home/settings.json" \
    "$workdir/activation-projects/gemini/.gemini/settings.json"
jq -n --arg project "$project_dir" '{trustedFolders: [$project]}' \
    >"$workdir/hosts/copilot/copilot-home/config.json"
chmod 0600 "$workdir/hosts/copilot/copilot-home/config.json"

# Derive the four project-stable commands and the machine-local runtime
# bindings from the installed archive under certification. The bindings stay
# out of project configuration and are added only to fresh native host
# environments below, after the corresponding hook has been staged.
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
gemini_hook_command="$(_mainframe_enforce_command_for gemini)" ||
    die "installed activation library could not generate the Gemini hook"
codex_hook_command="$(_mainframe_enforce_command_for codex)" ||
    die "installed activation library could not generate the Codex hook"
copilot_hook_command="$(_mainframe_enforce_command_for copilot)" ||
    die "installed activation library could not generate the Copilot hook"
claude_hook_command="$(_mainframe_enforce_command_for claude-code)" ||
    die "installed activation library could not generate the Claude hook"
for generated_hook_command in \
    "$gemini_hook_command" "$codex_hook_command" \
    "$copilot_hook_command" "$claude_hook_command"; do
    [[ "$generated_hook_command" == /bin/bash\ -p\ -c\ \'* ]] ||
        die "installed host hook does not enter through privileged system Bash"
    [[ "$generated_hook_command" != *"mainframe agent-hook"* ]] ||
        die "installed host hook still uses the legacy outer-shell command"
done
unset generated_hook_command
if ! _mainframe_enforce_bind_runtime "$project_dir"; then
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
    die "installed privileged runtime selected an unexpected safety policy"
[[ "$protected_agent_seal" =~ ^([0-9a-f]{64}:){3}[0-9a-f]{64}$ ]] ||
    die "installed privileged runtime returned an invalid byte seal"
[[ "$protected_agent_seal" == \
   "$(sha256_file "$protected_agent_bash"):$(sha256_file "$protected_agent_jq"):$(sha256_file "$protected_agent_gateway"):$(sha256_file "$protected_agent_safety")" ]] ||
    die "installed privileged runtime byte seal does not match its bindings"
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

for adapter in gemini codex copilot claude-code; do
    activation_host="$adapter"
    [[ "$adapter" != claude-code ]] || activation_host=claude
    activation_project="$workdir/activation-projects/$activation_host"
    env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
        PATH="$cert_path" "$mainframe_bin" activate "$adapter" \
        --project "$activation_project" --enforce >"$workdir/activation-$adapter.log"
    env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER" \
        PATH="$cert_path" "$mainframe_bin" protect status "$adapter" \
        --project "$activation_project" >"$workdir/status-$adapter.log"
    grep -Fq 'Static readiness: READY' "$workdir/status-$adapter.log" ||
        die "$adapter is not statically ready"
done
jq -e --arg command "$gemini_hook_command" '
  [.hooks.BeforeTool[] | select(.matcher == "run_shell_command") |
  .hooks[] | select(.command == $command)] |
  length == 1' "$workdir/activation-projects/gemini/.gemini/settings.json" >/dev/null ||
    die "Gemini hook activation is not exact"
jq -e --arg command "$codex_hook_command" \
    '.hooks.PreToolUse[0].hooks[0].command == $command' \
    "$workdir/activation-projects/codex/.codex/hooks.json" >/dev/null ||
    die "Codex hook activation is not exact"
jq -e --arg command "$copilot_hook_command" \
    '.hooks.preToolUse[0].bash == $command' \
    "$workdir/activation-projects/copilot/.github/hooks/mainframe.json" >/dev/null ||
    die "Copilot hook activation is not exact"
jq -e --arg command "$claude_hook_command" \
    '.hooks.PreToolUse[0].hooks[0].command == $command' \
    "$workdir/activation-projects/claude/.claude/settings.json" >/dev/null ||
    die "Claude hook activation is not exact"

# Some native hosts recognize another host's compatible hook file. Stage only
# the intended adapter immediately before launch so each native action reaches
# the gateway exactly once while the project and AWM root remain shared.
stage_hook() {
    local host="$1"
    rm -f -- "$project_dir/.gemini/settings.json" \
        "$project_dir/.codex/hooks.json" \
        "$project_dir/.github/hooks/mainframe.json" \
        "$project_dir/.claude/settings.json"
    case "$host" in
        gemini)
            mkdir -p "$project_dir/.gemini"
            cp "$workdir/activation-projects/gemini/.gemini/settings.json" \
                "$project_dir/.gemini/settings.json"
            ;;
        codex)
            mkdir -p "$project_dir/.codex"
            cp "$workdir/activation-projects/codex/.codex/hooks.json" \
                "$project_dir/.codex/hooks.json"
            ;;
        copilot)
            mkdir -p "$project_dir/.github/hooks"
            cp "$workdir/activation-projects/copilot/.github/hooks/mainframe.json" \
                "$project_dir/.github/hooks/mainframe.json"
            ;;
        claude)
            mkdir -p "$project_dir/.claude"
            cp "$workdir/activation-projects/claude/.claude/settings.json" \
                "$project_dir/.claude/settings.json"
            ;;
        *) die "unsupported staged hook host: $host" ;;
    esac
}

awm_root="$project_dir/.mainframe-awm"
mkdir -p "$awm_root"
chmod 0700 "$awm_root"
awm_env=(
    env -i HOME="$workdir/install-home" USER="$CERT_USER" LOGNAME="$CERT_USER"
    PATH="$cert_path" AWM_ROOT="$awm_root" MAINFRAME_AGENT_NAME=harness
)
session_id="$("${awm_env[@]}" "$mainframe_bin" awm init native-awm-chain \
    --namespace native-awm-cert --model four-native-hosts --backend file)"
[[ "$session_id" =~ ^[0-9a-f]{12}$ ]] || die "AWM init returned an invalid session id"
session_manifest="$awm_root/sessions/native-awm-cert/$session_id/manifest.json"
awm_schema_version="$(jq -er '.schema_version | select(type == "number")' \
    "$session_manifest")"
[[ "$awm_schema_version" == 2 ]] ||
    die "installed AWM schema $awm_schema_version is not the certified schema 2"
seed="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
)"
[[ "$seed" =~ ^[0-9a-f]{64}$ ]] || die "kernel CSPRNG did not produce a 256-bit seed"
"${awm_env[@]}" "$mainframe_bin" awm checkpoint --session "$session_id" \
    chain.seed "$seed" --importance critical --tags native-awm,seed
[[ "$("${awm_env[@]}" "$mainframe_bin" awm get --session "$session_id" chain.seed)" == "$seed" ]] ||
    die "hidden seed was not stored in the shared AWM session"

server_port=""
start_server() {
    local host="$1" run_label="$2" expectation="${3:-success}"
    local server fixture ready state log attempt derived_values_json
    ready="$workdir/hosts/$run_label/server-ready.json"
    state="$workdir/hosts/$run_label/server-state.json"
    log="$workdir/hosts/$run_label/server.log"
    case "$host" in
        codex) server="$codex_server"; fixture="$codex_fixture" ;;
        copilot) server="$copilot_server"; fixture="$copilot_fixture" ;;
        claude) server="$claude_server"; fixture="$claude_fixture" ;;
        *) die "unsupported loopback host: $host" ;;
    esac
    local -a command=(
        python3 "$server" --fixture "$fixture" --scenario awm-chain
        --mode control --awm-expectation "$expectation"
        --ready "$ready" --state "$state" --timeout 45
    )
    [[ "$host" != codex ]] || command+=(--shell "$bash_bin")
    derived_values_json="$(jq -cn \
        --arg gemini "${gemini_chain_value:-}" \
        --arg codex "${codex_chain_value:-}" \
        --arg copilot "${copilot_chain_value:-}" \
        --arg claude "${claude_chain_value:-}" \
        '[$gemini, $codex, $copilot, $claude] | map(select(length > 0))')"
    env MAINFRAME_AWM_GUARD_RAW_SEED="$seed" \
        MAINFRAME_AWM_GUARD_DERIVED_CHECKPOINTS_JSON="$derived_values_json" \
        MAINFRAME_AWM_GUARD_ROOT="$awm_root" \
        MAINFRAME_AWM_EXPECTATION="$expectation" \
        "${command[@]}" >"$log" 2>&1 &
    current_server_pid=$!
    for ((attempt = 0; attempt < 200; attempt++)); do
        [[ -s "$ready" ]] && break
        if ! kill -0 "$current_server_pid" >/dev/null 2>&1; then
            [[ ! -s "$log" ]] || cat "$log" >&2
            die "$host fixture server exited before readiness"
        fi
        sleep 0.05
    done
    [[ -s "$ready" ]] || {
        [[ ! -s "$log" ]] || cat "$log" >&2
        die "$host fixture server did not become ready"
    }
    jq -e '.schema_version == 1 and .address == "127.0.0.1" and
      (.port | type == "number" and . > 0 and . < 65536)' "$ready" >/dev/null ||
        die "$host fixture server emitted invalid readiness state"
    server_port="$(jq -er '.port' "$ready")"
}
finish_server() {
    local host="$1" run_label="$2" expectation="${3:-success}"
    if wait "$current_server_pid"; then current_server_pid=""; else current_server_pid=""; return 1; fi
    jq -e --arg host "$host" --arg expectation "$expectation" '
      .schema_version == 1 and .scenario == "awm-chain" and
      .mode == "control" and .awm_expectation == $expectation and
      .requests == 2 and .error == null and
      .request_hygiene_checked == true and .request_hygiene_passed == true and
      .request_hygiene_checks == 2 and .request_hygiene_rejections == 0 and
      .request_hygiene_reason == null and
      (if $expectation == "missing-predecessor" then
         $host == "codex" and .status == "expected-missing-predecessor" and
         .success_marker_seen == false and
         .missing_predecessor_marker_seen == true and .tool_result_nonzero == true
       else
         .status == "ok" and .success_marker_seen == true
       end) and
      (if $host == "codex" then
         .advertised_exec_command == true and .function_output_seen == true and
         .authorization_header_seen == false
       elif $host == "copilot" then
         .advertised_bash == true and .tool_output_seen == true and
         .user_credential_header_seen == false
       else
         .advertised_bash == true and .tool_result_seen == true and
         .tool_result_is_error == false and .placeholder_authorization_seen == true and
         .user_credential_header_seen == false
       end)' "$workdir/hosts/$run_label/server-state.json" >/dev/null
}
validate_audit() {
    local host="$1" event="$2" tool="$3" run_label="${4:-$1}"
    local audit="$workdir/hosts/$run_label/agent-gateway.jsonl"
    [[ -f "$audit" && ! -L "$audit" && "$(file_mode "$audit")" == 600 ]] ||
        die "$host did not emit a private gateway audit"
    jq -s -e --arg host "$host" --arg event "$event" --arg tool "$tool" '
      length == 1 and .[0].action == "agent_gateway_decision" and
      .[0].details == [
        ("host=" + $host), ("event=" + $event), ("tool=" + $tool),
        "risk=low", "rule=none", "decision=allow"
      ]' "$audit" >/dev/null || die "$host gateway audit is not the exact low-risk allow"
}
base_host_env() {
    local host="$1" run_label="$2" read_key="$3" write_key="$4"
    HOST_ENV=(
        env -i HOME="$workdir/hosts/$run_label/home" USER="$CERT_USER" LOGNAME="$CERT_USER"
        XDG_CONFIG_HOME="$workdir/hosts/$run_label/config"
        XDG_STATE_HOME="$workdir/hosts/$run_label/state"
        XDG_CACHE_HOME="$workdir/hosts/$run_label/cache"
        TMPDIR="$workdir/tmp" BASH_ENV=/dev/null ENV=/dev/null SHELL="$bash_bin"
        PATH="$cert_path" TERM=dumb NO_COLOR=1 CI=1 LC_ALL=C
        GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
        HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9
        ALL_PROXY=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9
        https_proxy=http://127.0.0.1:9 all_proxy=http://127.0.0.1:9
        "NO_PROXY=127.0.0.1,localhost" "no_proxy=127.0.0.1,localhost"
        AWM_ROOT="$awm_root"
        MAINFRAME_AWM_SESSION="$session_id" MAINFRAME_AWM_READ_KEY="$read_key"
        MAINFRAME_AWM_WRITE_KEY="$write_key"
        MAINFRAME_AWM_SCRATCH="$awm_root/native-chain-$run_label.scratch"
        MAINFRAME_AGENT_NAME="$host"
        MAINFRAME_AGENT_AUDIT_LOG="$workdir/hosts/$run_label/agent-gateway.jsonl"
        MAINFRAME_AGENT_BASH="$protected_agent_bash"
        MAINFRAME_AGENT_JQ="$protected_agent_jq"
        MAINFRAME_AGENT_GATEWAY="$protected_agent_gateway"
        MAINFRAME_AGENT_SAFETY="$protected_agent_safety"
        MAINFRAME_AGENT_SEAL="$protected_agent_seal"
    )
}

run_gemini() {
    local log="$workdir/hosts/gemini/host.log" status
    stage_hook gemini
    base_host_env gemini gemini chain.seed chain.gemini
    HOST_ENV+=(GEMINI_CLI_HOME="$workdir/hosts/gemini/gemini-home"
        GEMINI_CLI_TRUST_WORKSPACE=true GEMINI_API_KEY=mainframe-native-certification-dummy)
    if (
        cd "$project_dir"
        "${HOST_ENV[@]}" "$node_bin" "$gemini_entry" \
            --fake-responses "$gemini_fixture" --model gemini-2.5-flash \
            --approval-mode=yolo --output-format stream-json \
            -p 'Run the configured MAINFRAME AWM chain step exactly once.'
    ) >"$log" 2>&1; then status=0; else status=$?; fi
    if [[ "$status" -ne 0 ]]; then
        printf '%s\n' '--- Gemini AWM synthetic host log ---' >&2
        sed -n '1,240p' "$log" >&2
        die "Gemini native AWM-chain host exited with status $status"
    fi
    if ! sed -n '/^{/p' "$log" | jq -s -e '
      ([.[] | select(.type == "tool_use" and
        .tool_name == "run_shell_command")] | length == 1) and
      ([.[] | select(.type == "tool_result" and .status == "success" and
        .output == "MAINFRAME_AWM_CHAIN_OK:gemini")] | length == 1) and
      ([.[] | select(.type == "message" and .role == "assistant" and
        .content == "MAINFRAME AWM chain step completed for Gemini.")] |
        length == 1) and
      ([.[] | select(.type == "result" and .status == "success" and
        .stats.tool_calls == 1)] | length == 1)
    ' >/dev/null; then
        printf '%s\n' '--- Gemini AWM synthetic host log ---' >&2
        sed -n '1,240p' "$log" >&2
        die "Gemini stream does not prove one successful AWM tool call"
    fi
    validate_audit gemini BeforeTool run_shell_command
}

run_codex() {
    local read_key="$1" run_label="$2" expectation="${3:-success}"
    local log="$workdir/hosts/$run_label/host.log" status provider_config
    stage_hook codex
    start_server codex "$run_label" "$expectation"
    base_host_env codex "$run_label" "$read_key" chain.codex
    HOST_ENV+=(CODEX_HOME="$workdir/hosts/$run_label/codex-home")
    provider_config="model_providers.fixture={ name = \"MAINFRAME native AWM fixture\", base_url = \"http://127.0.0.1:$server_port/v1\", wire_api = \"responses\", requires_openai_auth = false, supports_websockets = false, request_max_retries = 0, stream_max_retries = 0 }"
    if (
        cd "$project_dir"
        "${HOST_ENV[@]}" "$node_bin" "$codex_entry" exec \
            --strict-config --ephemeral --ignore-rules --skip-git-repo-check \
            --dangerously-bypass-hook-trust --json --color never -C "$project_dir" \
            -m gpt-5.5 -c 'model_provider="fixture"' -c "$provider_config" \
            -c 'approval_policy="never"' -c 'sandbox_mode="workspace-write"' \
            -c 'allow_login_shell=false' -c 'check_for_update_on_startup=false' \
            -c 'analytics.enabled=false' -c 'feedback.enabled=false' \
            -c 'otel.exporter="none"' -c 'otel.metrics_exporter="none"' \
            -c 'otel.trace_exporter="none"' -c 'web_search="disabled"' \
            -c 'apps._default.enabled=false' -c 'features.enable_request_compression=false' \
            --enable hooks --disable apps --disable in_app_updates --disable plugins \
            --disable shell_snapshot \
            'Run the configured MAINFRAME AWM chain step exactly once.' </dev/null
    ) >"$log" 2>&1; then status=0; else status=$?; fi
    if [[ "$status" -ne 0 ]]; then
        kill "$current_server_pid" >/dev/null 2>&1 || true
        wait "$current_server_pid" >/dev/null 2>&1 || true
        current_server_pid=""
        return "$status"
    fi
    finish_server codex "$run_label" "$expectation" || return 1
    grep -Fq '"type":"turn.completed"' "$log" || return 1
    if [[ "$expectation" == "missing-predecessor" ]]; then
        grep -Fq 'MAINFRAME AWM missing predecessor rejected for Codex.' "$log" || return 1
        sed -n '/^{/p' "$log" | jq -s -e '
          ([.[] | select(.type == "item.completed" and
            .item.type == "command_execution" and .item.exit_code == 42 and
            .item.status == "failed" and
            ((.item.aggregated_output // "") | split("\n") |
              index("MAINFRAME_AWM_MISSING_PREDECESSOR") != null))] | length) == 1
        ' >/dev/null || return 1
    else
        grep -Fq 'MAINFRAME AWM chain step completed for Codex.' "$log" || return 1
    fi
    validate_audit codex PreToolUse Bash "$run_label"
}

run_copilot() {
    local log="$workdir/hosts/copilot/host.log" status
    stage_hook copilot
    jq -e --arg project "$project_dir" '. == {trustedFolders: [$project]}' \
        "$workdir/hosts/copilot/copilot-home/config.json" >/dev/null ||
        die "Copilot isolated home does not trust exactly the shared project"
    start_server copilot copilot success
    base_host_env copilot copilot chain.codex chain.copilot
    HOST_ENV+=(COPILOT_HOME="$workdir/hosts/copilot/copilot-home"
        COPILOT_OFFLINE=true COPILOT_AUTO_UPDATE=false COPILOT_DISABLE_TERMINAL_TITLE=1
        "COPILOT_PROVIDER_BASE_URL=http://127.0.0.1:$server_port/v1"
        COPILOT_PROVIDER_TYPE=openai COPILOT_PROVIDER_WIRE_API=completions
        COPILOT_MODEL=gpt-5.5)
    if (
        cd "$project_dir"
        "${HOST_ENV[@]}" "$node_bin" "$copilot_entry" -C "$project_dir" \
            -p 'Run the configured MAINFRAME AWM chain step exactly once.' \
            --allow-all-tools --available-tools=bash --no-auto-update --no-remote \
            --no-remote-export --disable-builtin-mcps --no-experimental \
            --no-custom-instructions --no-bash-env --no-ask-user --no-color \
            --log-level=error --output-format=json </dev/null
    ) >"$log" 2>&1; then status=0; else status=$?; fi
    if [[ "$status" -ne 0 ]]; then
        kill "$current_server_pid" >/dev/null 2>&1 || true
        wait "$current_server_pid" >/dev/null 2>&1 || true
        current_server_pid=""
        return "$status"
    fi
    finish_server copilot copilot success || return 1
    jq -s -e '
      ([.[] | select(.type == "tool.execution_start")] | length == 1) and
      ([.[] | select(.type == "tool.execution_complete" and .data.success == true)] |
        length == 1) and
      ([.[] | select(.type == "assistant.message" and
        .data.content == "MAINFRAME AWM chain step completed for Copilot.")] |
        length == 1)' "$log" >/dev/null || return 1
    validate_audit copilot PreToolUse bash
}

run_claude() {
    local log="$workdir/hosts/claude/host.jsonl" status
    stage_hook claude
    start_server claude claude success
    base_host_env claude claude chain.copilot chain.claude
    HOST_ENV+=(CLAUDE_CONFIG_DIR="$workdir/hosts/claude/claude-config"
        "ANTHROPIC_BASE_URL=http://127.0.0.1:$server_port"
        ANTHROPIC_AUTH_TOKEN=mainframe-certification-placeholder
        ANTHROPIC_MODEL=mainframe-claude-certification
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
        CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL=1
        CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 CLAUDE_CODE_DISABLE_CLAUDE_MDS=1
        CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1 CLAUDE_CODE_DISABLE_WORKFLOWS=1
        CLAUDE_CODE_DISABLE_AGENT_VIEW=1 CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1
        CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1 CLAUDE_CODE_SKIP_PROMPT_HISTORY=1
        CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1 ENABLE_CLAUDEAI_MCP_SERVERS=false
        DISABLE_UPDATES=1 DISABLE_AUTOUPDATER=1 DISABLE_TELEMETRY=1
        DISABLE_ERROR_REPORTING=1 DISABLE_FEEDBACK_COMMAND=1 DISABLE_LOGIN_COMMAND=1
        API_TIMEOUT_MS=10000)
    if (
        cd "$project_dir"
        "${HOST_ENV[@]}" "$claude_binary" -p --output-format stream-json --verbose \
            --include-hook-events --no-session-persistence --setting-sources project \
            --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
            --tools Bash --allowedTools "Bash($AWM_COMMAND)" \
            --permission-mode dontAsk --disable-slash-commands --no-chrome \
            --max-turns 2 --model mainframe-claude-certification \
            'Run the configured MAINFRAME AWM chain step exactly once.' </dev/null
    ) >"$log" 2>"$workdir/hosts/claude/host.stderr"; then status=0; else status=$?; fi
    if [[ "$status" -ne 0 ]]; then
        kill "$current_server_pid" >/dev/null 2>&1 || true
        wait "$current_server_pid" >/dev/null 2>&1 || true
        current_server_pid=""
        return "$status"
    fi
    finish_server claude claude success || return 1
    [[ ! -s "$workdir/hosts/claude/host.stderr" ]] || return 1
    jq -s -e '
      ([.[] | select(.type == "system" and .subtype == "init" and
        .tools == ["Bash"])] | length == 1) and
      ([.[] | select(.type == "system" and .subtype == "hook_started")] |
        length == 1) and
      ([.[] | select(.type == "system" and .subtype == "hook_response" and
        .exit_code == 0)] | length == 1) and
      ([.[] | select(.type == "result" and .subtype == "success" and
        .num_turns == 2 and
        .result == "MAINFRAME AWM chain step completed for Claude.")] |
        length == 1)' "$log" >/dev/null || return 1
    validate_audit claude PreToolUse Bash
}

expected_value="$seed:gemini"
run_gemini
[[ "$("${awm_env[@]}" "$mainframe_bin" awm get --session "$session_id" chain.gemini)" == "$expected_value" ]] ||
    die "Gemini checkpoint did not derive from the hidden seed"
gemini_chain_value="$expected_value"

# Every positive certificate binds this exact failed-predecessor receipt. It
# runs after Gemini and before the positive Codex session, with entirely fresh
# Codex host state but the same project, UID, TMPDIR, AWM root, and session.
run_codex chain.missing codex-negative missing-predecessor ||
    die "fresh-state Codex wrong-predecessor probe did not complete exactly"
[[ ! -e "$awm_root/sessions/native-awm-cert/$session_id/data/chain.codex" ]] ||
    die "wrong-predecessor probe wrote a Codex checkpoint"
[[ -f "$awm_root/native-chain-codex-negative.scratch" &&
   ! -s "$awm_root/native-chain-codex-negative.scratch" &&
   "$(file_mode "$awm_root/native-chain-codex-negative.scratch")" == 600 ]] ||
    die "wrong-predecessor scratch is not empty and private"
[[ ! -e "$workdir/hosts/copilot/agent-gateway.jsonl" &&
   ! -e "$workdir/hosts/claude/agent-gateway.jsonl" ]] ||
    die "a later host ran before the wrong-predecessor rejection was bound"
negative_probe_state_sha="$(sha256_file "$workdir/hosts/codex-negative/server-state.json")"

if [[ "$negative_wrong_predecessor" == true ]]; then
    require_native_executable_binding "$bash_bin" "$bash_binding" "selected Bash executable"
    require_native_executable_binding "$node_bin" "$node_binding" "Node.js executable"
    require_native_executable_binding "$codex_binary" "$codex_binary_binding" "Codex native executable"
    require_native_executable_binding "$copilot_binary" "$copilot_binary_binding" "Copilot native executable"
    require_native_executable_binding "$claude_binary" "$claude_binary_binding" "Claude native executable"
    require_native_executable_binding \
        "$protected_agent_bash" "$protected_agent_bash_binding" \
        "privileged gateway Bash executable"
    require_native_executable_binding \
        "$protected_agent_jq" "$protected_agent_jq_binding" \
        "privileged gateway jq executable"
    [[ ! -e "$output" && ! -L "$output" ]] || die "negative path emitted evidence"
    printf 'Wrong predecessor rejected at Codex; later hosts skipped; no evidence emitted.\n'
    exit 0
fi

run_codex chain.gemini codex success || die "Codex native AWM-chain session failed"
expected_value="$expected_value:codex"
[[ "$("${awm_env[@]}" "$mainframe_bin" awm get --session "$session_id" chain.codex)" == "$expected_value" ]] ||
    die "Codex checkpoint did not derive from the Gemini checkpoint"
codex_chain_value="$expected_value"
run_copilot || die "Copilot native AWM-chain session failed"
expected_value="$expected_value:copilot"
[[ "$("${awm_env[@]}" "$mainframe_bin" awm get --session "$session_id" chain.copilot)" == "$expected_value" ]] ||
    die "Copilot checkpoint did not derive from the Codex checkpoint"
copilot_chain_value="$expected_value"
run_claude || die "Claude native AWM-chain session failed"
expected_value="$expected_value:claude"
[[ "$("${awm_env[@]}" "$mainframe_bin" awm get --session "$session_id" chain.claude)" == "$expected_value" ]] ||
    die "Claude checkpoint did not derive from the Copilot checkpoint"
claude_chain_value="$expected_value"

checkpoint_log="$awm_root/sessions/native-awm-cert/$session_id/logs/checkpoints.jsonl"
jq -s -e '
  length == 5 and
  .[0].key == "chain.seed" and .[0].source_agent == "harness" and
  .[0].importance == "critical" and
  .[1].key == "chain.gemini" and .[1].source_agent == "gemini" and
  .[2].key == "chain.codex" and .[2].source_agent == "codex" and
  .[3].key == "chain.copilot" and .[3].source_agent == "copilot" and
  .[4].key == "chain.claude" and .[4].source_agent == "claude" and
  all(.[1:][]; .importance == "high" and (.tags | index("native-awm") != null))
' "$checkpoint_log" >/dev/null || die "checkpoint log does not prove the ordered four-host chain"

# Context and handoff contain checkpoint values, so persist them only under the
# private AWM root. Publish their hashes, never their JSON.
private_cert_dir="$awm_root/certification"
mkdir -p "$private_cert_dir"
chmod 0700 "$private_cert_dir"
context_file="$private_cert_dir/final-context.json"
handoff_file="$private_cert_dir/final-handoff.json"
context_requested_tokens=4096
"${awm_env[@]}" "$mainframe_bin" awm discovery --session "$session_id" \
    "release-reviewer final chain value: $expected_value" \
    --importance critical --tags native-awm,final-handoff
"${awm_env[@]}" "$mainframe_bin" awm context --session "$session_id" \
    'chain.claude native four-host AWM certification' \
    --tokens "$context_requested_tokens" --format json \
    --include discoveries,progress,checkpoints,logs >"$context_file.tmp"
context_actual_bytes="$(LC_ALL=C wc -c <"$context_file.tmp" | tr -d '[:space:]')"
jq -e --arg sid "$session_id" --arg final "$expected_value" \
    --argjson requested "$context_requested_tokens" \
    --argjson actual "$context_actual_bytes" \
    --argjson awm_schema "$awm_schema_version" '
      .session_id == $sid and .max_tokens == $requested and
      .provenance == {
        schema_version: $awm_schema, namespace: "native-awm-cert", backend: "file",
        source_agent: "harness"
      } and
      .budget.requested_tokens == $requested and
      .budget.chars_per_token == 4 and
      .budget.max_chars == ($requested * .budget.chars_per_token) and
      .budget.actual_chars == $actual and
      .budget.actual_tokens == (($actual + .budget.chars_per_token - 1) /
        .budget.chars_per_token | floor) and
      .budget.truncated == false and
      ([.checkpoints[] | select(.session_id == $sid and
        .key == "chain.claude" and .preview == $final)] | length) == 1
    ' "$context_file.tmp" >/dev/null ||
    die "final context budget, provenance, or final checkpoint is not exact"
context_chars_per_token="$(jq -er '.budget.chars_per_token' "$context_file.tmp")"
context_max_bytes="$(jq -er '.budget.max_chars' "$context_file.tmp")"
context_actual_tokens="$(jq -er '.budget.actual_tokens' "$context_file.tmp")"
chmod 0600 "$context_file.tmp"; mv "$context_file.tmp" "$context_file"
handoff_requested_tokens=4096
"${awm_env[@]}" "$mainframe_bin" awm handoff prepare --session "$session_id" \
    release-reviewer --tokens "$handoff_requested_tokens" --format json >"$handoff_file.tmp"
handoff_actual_bytes="$(LC_ALL=C wc -c <"$handoff_file.tmp" | tr -d '[:space:]')"
nested_context_bytes="$(( $(jq -c '.context' "$handoff_file.tmp" | LC_ALL=C wc -c | tr -d '[:space:]') - 1 ))"
jq -e --arg sid "$session_id" --arg final "$expected_value" \
    --argjson requested "$handoff_requested_tokens" \
    --argjson actual "$handoff_actual_bytes" \
    --argjson nested_actual "$nested_context_bytes" \
    --argjson awm_schema "$awm_schema_version" '
      .type == "handoff" and .parent_session == $sid and
      .parent_agent == "harness" and .target_agent == "release-reviewer" and
      .provenance == {
        schema_version: $awm_schema, namespace: "native-awm-cert", backend: "file"
      } and
      .budget.requested_tokens == $requested and
      .budget.chars_per_token == 4 and
      .budget.max_chars == ($requested * .budget.chars_per_token) and
      .budget.actual_chars == $actual and
      .budget.actual_tokens == (($actual + .budget.chars_per_token - 1) /
        .budget.chars_per_token | floor) and
      .budget.truncated == false and
      .context.session_id == $sid and
      .context.provenance == {
        schema_version: $awm_schema, namespace: "native-awm-cert", backend: "file",
        source_agent: "harness"
      } and
      .context.budget.actual_chars == $nested_actual and
      .context.budget.actual_tokens == (($nested_actual +
        .context.budget.chars_per_token - 1) /
        .context.budget.chars_per_token | floor) and
      .context.budget.truncated == false and
      (tostring | contains($final))
    ' "$handoff_file.tmp" >/dev/null ||
    die "final handoff budget, provenance, nested context, or final value is not exact"
handoff_chars_per_token="$(jq -er '.budget.chars_per_token' "$handoff_file.tmp")"
handoff_max_bytes="$(jq -er '.budget.max_chars' "$handoff_file.tmp")"
handoff_actual_tokens="$(jq -er '.budget.actual_tokens' "$handoff_file.tmp")"
nested_context_actual_tokens="$(jq -er '.context.budget.actual_tokens' "$handoff_file.tmp")"
handoff_id="$(jq -er '.handoff_id' "$handoff_file.tmp")"
persisted_handoff="$awm_root/sessions/native-awm-cert/$session_id/handoffs/$handoff_id.json"
[[ -f "$persisted_handoff" && ! -L "$persisted_handoff" &&
   "$(file_mode "$persisted_handoff")" == 600 ]] ||
    die "persisted handoff is missing or not private"
cmp -s "$handoff_file.tmp" "$persisted_handoff" ||
    die "emitted handoff bytes differ from the persisted handoff"
chmod 0600 "$handoff_file.tmp"; mv "$handoff_file.tmp" "$handoff_file"
context_sha="$(sha256_file "$context_file")"
handoff_sha="$(sha256_file "$handoff_file")"
awm_doctor="$private_cert_dir/doctor.json"
"${awm_env[@]}" "$mainframe_bin" awm doctor --session "$session_id" >"$awm_doctor"
chmod 0600 "$awm_doctor"
jq -e '.layout_ok == true and .private_modes == true and .symlink_free == true and
  .backend == "file" and .issues == []' "$awm_doctor" >/dev/null ||
    die "AWM doctor did not verify private, symlink-free storage"
[[ "$(file_mode "$awm_root")" == 700 && "$(file_mode "$context_file")" == 600 &&
   "$(file_mode "$handoff_file")" == 600 &&
   "$(file_mode "$persisted_handoff")" == 600 ]] || die "private AWM modes are unsafe"

# The raw seed may appear only inside the AWM root. Scan both the private
# certifier state and the separate disposable project that hosts expose as cwd.
python3 - "$workdir" "$project_dir" "$awm_root" "$seed" <<'PY'
import os
import sys
roots = [os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])]
private = os.path.realpath(sys.argv[3])
needle = sys.argv[4].encode()
for root in roots:
    for current, dirs, files in os.walk(root, followlinks=False):
        real = os.path.realpath(current)
        if real == private or real.startswith(private + os.sep):
            dirs[:] = []
            continue
        for name in files:
            path = os.path.join(current, name)
            if not os.path.islink(path) and os.path.isfile(path):
                with open(path, "rb") as handle:
                    if needle in handle.read():
                        raise SystemExit(f"hidden seed escaped private AWM root: {path}")
PY

[[ "$(python3 "$hasher" "$workdir/extracted")" == "$installed_runtime_tree" &&
   "$(python3 "$hasher" "$workdir/host-runtime/gemini")" == "$gemini_tree" &&
   "$(python3 "$hasher" "$workdir/host-runtime/codex/node_modules/@openai")" == "$codex_tree" &&
   "$(python3 "$hasher" "$workdir/host-runtime/copilot/node_modules")" == "$copilot_tree" &&
   "$(python3 "$hasher" "$workdir/host-runtime/claude/node_modules")" == "$claude_tree" ]] ||
    die "an installed or native runtime changed during certification"

require_native_executable_binding "$bash_bin" "$bash_binding" "selected Bash executable"
require_native_executable_binding "$node_bin" "$node_binding" "Node.js executable"
require_native_executable_binding "$codex_binary" "$codex_binary_binding" "Codex native executable"
require_native_executable_binding "$copilot_binary" "$copilot_binary_binding" "Copilot native executable"
require_native_executable_binding "$claude_binary" "$claude_binary_binding" "Claude native executable"
require_native_executable_binding \
    "$protected_agent_bash" "$protected_agent_bash_binding" \
    "privileged gateway Bash executable"
require_native_executable_binding \
    "$protected_agent_jq" "$protected_agent_jq_binding" \
    "privileged gateway jq executable"

gemini_fixture_sha="$(sha256_file "$gemini_fixture")"
codex_fixture_sha="$(sha256_file "$codex_fixture")"
copilot_fixture_sha="$(sha256_file "$copilot_fixture")"
claude_fixture_sha="$(sha256_file "$claude_fixture")"
certified_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
mkdir -p "$(dirname "$output")"
output_dir="$(cd "$(dirname "$output")" && pwd -P)"
output="$output_dir/$(basename "$output")"
evidence_tmp="$(mktemp "$output.tmp.XXXXXX")"
jq -n \
    --arg version "$VERSION" --arg archive_sha "$archive_sha" \
    --arg installed_runtime "$installed_runtime_tree" \
    --arg installed_launcher "$installed_launcher_sha" \
    --arg os "$current_os" --arg arch "$current_arch" --arg libc "$libc" \
    --arg session "$session_id" --arg context "$context_sha" --arg handoff "$handoff_sha" \
    --arg command_sha "$awm_command_sha" --arg negative_state "$negative_probe_state_sha" \
    --argjson awm_schema "$awm_schema_version" \
    --arg gv "$gemini_verified_version" --arg cv "$codex_verified_version" \
    --arg pv "$copilot_verified_version" --arg av "$claude_verified_version" \
    --argjson context_requested "$context_requested_tokens" \
    --argjson context_cpt "$context_chars_per_token" \
    --argjson context_max "$context_max_bytes" \
    --argjson context_actual "$context_actual_bytes" \
    --argjson context_tokens "$context_actual_tokens" \
    --argjson handoff_requested "$handoff_requested_tokens" \
    --argjson handoff_cpt "$handoff_chars_per_token" \
    --argjson handoff_max "$handoff_max_bytes" \
    --argjson handoff_actual "$handoff_actual_bytes" \
    --argjson handoff_tokens "$handoff_actual_tokens" \
    --argjson nested_actual "$nested_context_bytes" \
    --argjson nested_tokens "$nested_context_actual_tokens" \
    --arg gi "$gemini_integrity" --arg gt "$gemini_tree" \
    --arg ge "$gemini_executable" --arg gf "$gemini_fixture_sha" \
    --arg ci "$codex_integrity" --arg cp "$codex_platform_package" \
    --arg cpi "$codex_platform_integrity" --arg ct "$codex_tree" \
    --arg ce "$codex_executable" --arg cf "$codex_fixture_sha" \
    --arg pi "$copilot_integrity" --arg pp "$copilot_platform_package" \
    --arg ppi "$copilot_platform_integrity" --arg pt "$copilot_tree" \
    --arg pe "$copilot_executable" --arg pf "$copilot_fixture_sha" \
    --arg ai "$claude_integrity" --arg ap "$claude_platform_package" \
    --arg api "$claude_platform_integrity" --arg at "$claude_tree" \
    --arg ae "$claude_executable" --arg af "$claude_fixture_sha" \
    --arg certified "$certified_at" '
  def proof($host; $position; $version; $package; $integrity; $platform;
      $platform_integrity; $tree; $executable; $fixture; $read; $write;
      $call; $provider; $guard; $hygiene_checks; $event; $tool):
    {
      host: $host, position: $position, version: $version, package: $package,
      version_command_verified: true,
      package_integrity: $integrity, platform_package: $platform,
      platform_package_integrity: $platform_integrity,
      runtime_tree_sha256: $tree, executable_sha256: $executable,
      fixture_sha256: $fixture, read_key: $read, write_key: $write,
      provider_call_id: $call, provider_command_sha256: $command_sha,
      provider_mode: $provider, provider_requests: 2,
      provider_request_guard_mode: $guard,
      provider_request_hygiene_checks: $hygiene_checks,
      user_credentials_supplied: false, fresh_separate_host_state: true,
      tool_calls: 1, event: $event, tool: $tool, gateway_risk: "low",
      gateway_rule: "none", gateway_decision: "allow", gateway_records: 1,
      gateway_observation_scope: "host-event-tool-policy-tuple-only",
      gateway_command_correlation_available: false,
      audit_mode: "600", checkpoint_source_agent: $host,
      checkpoint_importance: "high", success_marker_seen: true
    };
  {
    schema_version: 1,
    certification: "native-awm-chain-execution-certified",
    mainframe: {
      version: $version, archive_sha256: $archive_sha,
      archive_origin: "external-input", archive_checksum_records: 1,
      installation_count: 1, install_mode: "safe-extract-single-private-install",
      installed_runtime_tree_sha256: $installed_runtime,
      installed_launcher_sha256: $installed_launcher,
      installed_runtime_read_only: true
    },
    platform: {os: $os, arch: $arch, libc: $libc, system_libc: $libc},
    execution_boundaries: {
      shared_project: true, shared_awm_root: true, shared_awm_session: true,
      same_uid: true, shared_tmpdir: true, separate_home: true,
      separate_xdg_config: true, separate_xdg_state: true,
      separate_xdg_cache: true, fresh_separate_host_state: true,
      os_process_isolation: false, container_isolation: false,
      isolation_scope: "fresh-filesystem-host-state-not-os-sandbox"
    },
    awm: {
      backend: "file", schema_version: $awm_schema,
      root_scope: "private-project-local", root_mode: "700",
      session_id: $session, namespace: "native-awm-cert", shared_session: true,
      seed_bits: 256, seed_source: "kernel-csprng",
      seed_exposure: "harness-private-awm-and-loopback-guard-memory-only",
      checkpoint_count: 5, chain_length: 4, final_key: "chain.claude",
      final_context_sha256: $context, final_handoff_sha256: $handoff,
      private_artifact_mode: "600", private_modes_verified: true,
      context_proof: {
        budget_unit: "bytes-under-LC_ALL-C",
        requested_tokens: $context_requested, bytes_per_token: $context_cpt,
        max_bytes: $context_max, actual_bytes: $context_actual,
        actual_tokens: $context_tokens, truncated: false,
        provenance_session_verified: true, source_agent: "harness",
        final_value_included: true
      },
      handoff_proof: {
        budget_unit: "bytes-under-LC_ALL-C",
        requested_tokens: $handoff_requested, bytes_per_token: $handoff_cpt,
        max_bytes: $handoff_max, actual_bytes: $handoff_actual,
        actual_tokens: $handoff_tokens, truncated: false,
        provenance_session_verified: true, parent_agent: "harness",
        nested_context_actual_bytes: $nested_actual,
        nested_context_actual_tokens: $nested_tokens,
        nested_context_truncated: false, nested_context_verified: true,
        final_value_included: true, persisted_byte_equal: true
      }
    },
    hosts: {
      gemini: proof("gemini"; 1; $gv; "@google/gemini-cli"; $gi;
        "@google/gemini-cli"; $gi; $gt; $ge; $gf; "chain.seed"; "chain.gemini";
        "mainframe-gemini-awm-chain"; "first-party-fake-responses";
        "not-applicable-first-party-fake-responses"; 0;
        "BeforeTool"; "run_shell_command"),
      codex: proof("codex"; 2; $cv; "@openai/codex"; $ci;
        $cp; $cpi; $ct; $ce; $cf; "chain.gemini"; "chain.codex";
        "mainframe-codex-awm-chain"; "loopback-responses-no-credentials";
        "reject-awm-values-and-root-no-request-persistence"; 2;
        "PreToolUse"; "Bash"),
      copilot: proof("copilot"; 3; $pv; "@github/copilot"; $pi;
        $pp; $ppi; $pt; $pe; $pf; "chain.codex"; "chain.copilot";
        "mainframe-copilot-awm-chain"; "loopback-chat-completions-no-credentials";
        "reject-awm-values-and-root-no-request-persistence"; 2;
        "PreToolUse"; "bash"),
      claude: proof("claude"; 4; $av; "@anthropic-ai/claude-code"; $ai;
        $ap; $api; $at; $ae; $af; "chain.copilot"; "chain.claude";
        "mainframe-claude-awm-chain"; "loopback-messages-synthetic-placeholder";
        "reject-awm-values-and-root-no-request-persistence"; 2;
        "PreToolUse"; "Bash")
    },
    negative_probe: {
      executed: true, positive_certificate_binding: true,
      standalone_mode: "--negative-wrong-predecessor",
      standalone_mode_emits_evidence: false,
      run_order: "after-gemini-before-positive-codex", host: "codex",
      read_key: "chain.missing", write_key: "chain.codex",
      provider_call_id: "mainframe-codex-awm-chain",
      provider_command_sha256: $command_sha, provider_requests: 2,
      provider_status: "expected-missing-predecessor",
      provider_request_hygiene_verified: true,
      missing_predecessor_marker: "MAINFRAME_AWM_MISSING_PREDECESSOR",
      missing_predecessor_marker_seen: true, tool_exit_code: 42,
      tool_result_nonzero: true, event: "PreToolUse", tool: "Bash",
      gateway_risk: "low", gateway_rule: "none", gateway_decision: "allow",
      gateway_records: 1,
      gateway_observation_scope: "host-event-tool-policy-tuple-only",
      gateway_command_correlation_available: false,
      checkpoint_written: false, scratch_mode: "600", scratch_empty: true,
      later_hosts_started_before_rejection: false,
      fresh_separate_host_state: true, server_state_sha256: $negative_state
    },
    evidence_hygiene: {
      raw_seed_embedded: false, checkpoint_values_embedded: false,
      credentials_embedded: false, absolute_home_paths_embedded: false,
      provider_requests_embedded: false, private_run_artifacts_embedded: false,
      loopback_requests_persisted: false,
      loopback_private_values_observed: false,
      loopback_awm_root_observed: false,
      loopback_disposable_paths_may_be_observed: true
    },
    certified_at: $certified
  }' >"$evidence_tmp"
chmod 0600 "$evidence_tmp"
python3 "$validator" "$schema" "$evidence_tmp" >/dev/null ||
    die "generated evidence failed strict schema validation"
for forbidden_value in "$seed" "$gemini_chain_value" "$codex_chain_value" \
    "$copilot_chain_value" "$claude_chain_value"; do
    grep -Fq -- "$forbidden_value" "$evidence_tmp" &&
        die "a raw or derived AWM value was embedded in evidence"
done
if grep -Fq -- "$workdir" "$evidence_tmp" ||
   jq -e '[paths(scalars) as $p | getpath($p) |
      select(type == "string" and startswith("/"))] | length > 0' \
      "$evidence_tmp" >/dev/null; then
    die "an absolute private path was embedded in evidence"
fi
for forbidden in mainframe-native-certification-dummy mainframe-certification-placeholder \
    ANTHROPIC_AUTH_TOKEN GEMINI_API_KEY; do
    grep -Fq -- "$forbidden" "$evidence_tmp" &&
        die "credential value or provider request field was embedded in evidence"
done
ln "$evidence_tmp" "$output" ||
    die "refusing to overwrite evidence output created during certification: $output"
rm -f -- "$evidence_tmp"
evidence_tmp=""
[[ -f "$output" && ! -L "$output" && "$(file_mode "$output")" == 600 ]] ||
    die "evidence was not atomically published as a mode-0600 regular file"
python3 "$validator" "$schema" "$output" >/dev/null
printf 'Native AWM-chain execution certified: %s\n' "$output"

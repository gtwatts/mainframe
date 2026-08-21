#!/usr/bin/env bash
# Certify the user-facing onboarding path from an exact release archive.
# shellcheck disable=SC2016 # Fresh-shell command strings expand in the isolated child.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: certify-shell-onboarding.sh HOST --archive PATH [--shell bash|zsh] [--output PATH]

Install the exact checksum-adjacent release archive into an isolated HOME,
launch a genuinely fresh interactive login shell, prove Bash discovery again
from a genuine interactive non-login shell, and certify MAINFRAME's
explicit-consent onboarding contract for one supported host. This proves
installed payload identity, shell discovery, gateway, project configuration,
rollback, and fresh-shell AWM behavior. It does not claim that the native host
trusted or loaded its project hook.

When --output is supplied, write a strict, path-free JSON certificate only
after every check succeeds. Existing paths, symbolic links, and non-JSON names
are refused.

Hosts: codex, claude-code, copilot, gemini
EOF
}

fail() {
    printf 'shell-onboarding certification failed: %s\n' "$*" >&2
    exit 1
}

native_executable_binding() {
    "$python_bin" -I -S -B "$native_executable_validator" \
        "$1" "$actual_os" "$actual_arch" "$2"
}

require_native_executable_binding() {
    local observed
    observed="$(native_executable_binding "$1" "$3")" ||
        fail "$3 failed native executable revalidation"
    [[ "$observed" == "$2" ]] || fail "$3 changed after native executable admission"
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
        fail "no SHA-256 implementation is available"
    fi
}

file_mode() {
    local file="$1"
    if [[ "${actual_os:-}" == "Darwin" ]]; then
        stat -f '%Lp' "$file"
    else
        stat -c '%a' "$file"
    fi
}

tree_digest() {
    local root="$1" digest_kind="${2:-snapshot}"

    python3 - "$root" "$digest_kind" <<'PYEOF'
import hashlib
import os
import stat
import sys

root = os.path.realpath(sys.argv[1])
include_mode = sys.argv[2] == "snapshot"
digest = hashlib.sha256()


def add(value):
    if isinstance(value, str):
        value = os.fsencode(value)
    digest.update(len(value).to_bytes(8, "big"))
    digest.update(value)


def visit(directory, relative):
    entries = sorted(os.scandir(directory), key=lambda entry: os.fsencode(entry.name))
    for entry in entries:
        child_relative = os.path.join(relative, entry.name) if relative else entry.name
        metadata = entry.stat(follow_symlinks=False)
        if stat.S_ISDIR(metadata.st_mode):
            kind = b"directory"
        elif stat.S_ISREG(metadata.st_mode):
            kind = b"file"
        elif stat.S_ISLNK(metadata.st_mode):
            kind = b"symlink"
        else:
            kind = b"special"

        add(kind)
        add(child_relative)
        if include_mode:
            add(f"{stat.S_IMODE(metadata.st_mode):04o}")

        if kind == b"file":
            file_digest = hashlib.sha256()
            with open(entry.path, "rb") as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    file_digest.update(chunk)
            add(file_digest.digest())
        elif kind == b"symlink":
            add(os.readlink(entry.path))
        elif kind == b"special":
            add(str(metadata.st_mode))

        if kind == b"directory":
            visit(entry.path, child_relative)


visit(root, "")
print(digest.hexdigest())
PYEOF
}

optional_tree_digest() {
    local root="$1"
    if [[ ! -e "$root" && ! -L "$root" ]]; then
        printf '<absent>\n'
    elif [[ -d "$root" && ! -L "$root" ]]; then
        tree_digest "$root"
    else
        return 1
    fi
}

verify_installed_archive_payload() {
    local archive="$1" installed_root="$2" receipt_name="$3"

    "$python_bin" - "$archive" "$installed_root" "$receipt_name" <<'PYEOF'
import hashlib
import os
from pathlib import PurePosixPath
import stat
import sys
import tarfile


archive, installed_root, receipt_name = sys.argv[1:]


def fail(message):
    print(f"installed archive verification failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


expected_files = {}
expected_directories = {}
implicit_directories = set()
with tarfile.open(archive, "r:gz") as payload:
    for member in payload.getmembers():
        name = member.name.rstrip("/")
        if not name or name in expected_files or name in expected_directories:
            fail(f"archive member inventory is ambiguous: {member.name!r}")
        path = PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or "." in path.parts:
            fail(f"archive member path is unsafe: {member.name!r}")
        for parent in path.parents:
            if str(parent) != ".":
                implicit_directories.add(str(parent))
        mode = member.mode & 0o7777
        if member.isfile():
            extracted = payload.extractfile(member)
            if extracted is None:
                fail(f"archive member could not be read: {name}")
            digest = hashlib.sha256()
            for chunk in iter(lambda: extracted.read(1024 * 1024), b""):
                digest.update(chunk)
            expected_files[name] = (mode, digest.hexdigest())
        elif member.isdir():
            expected_directories[name] = mode
        else:
            fail(f"archive contains a link or special member: {name}")

if receipt_name in expected_files or receipt_name in expected_directories:
    fail("release archive contains the machine-local receipt")

actual_files = {}
actual_directories = {}


def visit(directory, relative=""):
    try:
        entries = sorted(os.scandir(directory), key=lambda entry: os.fsencode(entry.name))
    except OSError as error:
        fail(f"installed directory could not be read: {error}")
    for entry in entries:
        child_relative = f"{relative}/{entry.name}" if relative else entry.name
        metadata = entry.stat(follow_symlinks=False)
        mode = stat.S_IMODE(metadata.st_mode)
        if stat.S_ISDIR(metadata.st_mode):
            actual_directories[child_relative] = mode
            visit(entry.path, child_relative)
        elif stat.S_ISREG(metadata.st_mode):
            actual_files[child_relative] = (mode, sha256_file(entry.path))
        else:
            fail(f"installed payload contains a link or special entry: {child_relative}")


visit(installed_root)
expected_file_names = set(expected_files) | {receipt_name}
actual_file_names = set(actual_files)
if actual_file_names != expected_file_names:
    missing = sorted(expected_file_names - actual_file_names)
    extra = sorted(actual_file_names - expected_file_names)
    fail(f"installed file inventory differs (missing={missing}, extra={extra})")

expected_directory_names = implicit_directories | set(expected_directories)
actual_directory_names = set(actual_directories)
if actual_directory_names != expected_directory_names:
    missing = sorted(expected_directory_names - actual_directory_names)
    extra = sorted(actual_directory_names - expected_directory_names)
    fail(f"installed directory inventory differs (missing={missing}, extra={extra})")

for name, (expected_mode, expected_digest) in expected_files.items():
    actual_mode, actual_digest = actual_files[name]
    if actual_digest != expected_digest:
        fail(f"installed payload content differs from the exact archive: {name}")
    if actual_mode != expected_mode:
        fail(
            "installed payload mode differs from the exact archive: "
            f"{name} ({actual_mode:04o} != {expected_mode:04o})"
        )

for name, expected_mode in expected_directories.items():
    actual_mode = actual_directories[name]
    if actual_mode != expected_mode:
        fail(
            "installed directory mode differs from the exact archive: "
            f"{name} ({actual_mode:04o} != {expected_mode:04o})"
        )
PYEOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

host="${1:-}"
[[ -n "$host" ]] || { usage >&2; exit 2; }
shift

archive=""
shell_name=""
output=""
while (( $# > 0 )); do
    case "$1" in
        --archive)
            (( $# >= 2 )) || { usage >&2; exit 2; }
            archive="$2"
            shift 2
            ;;
        --shell)
            (( $# >= 2 )) || { usage >&2; exit 2; }
            shell_name="$2"
            shift 2
            ;;
        --output)
            (( $# >= 2 )) || { usage >&2; exit 2; }
            output="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

output_parent=""
output_name=""
if [[ -n "$output" ]]; then
    output_parent="$(dirname -- "$output")"
    output_name="$(basename -- "$output")"
    [[ -n "$output_name" && "$output_name" != "." && "$output_name" != ".." ]] || \
        fail "--output must name a JSON file"
    [[ "$output_name" == *.json ]] || fail "--output must end in .json"
    [[ -d "$output_parent" && ! -L "$output_parent" ]] || \
        fail "--output parent must be an existing physical directory: $output_parent"
    output_parent="$(cd -- "$output_parent" && pwd -P)"
    output="$output_parent/$output_name"
    [[ ! -e "$output" && ! -L "$output" ]] || \
        fail "--output already exists: $output"
fi

case "$host" in
    codex|claude-code|copilot|gemini) ;;
    *) fail "unsupported host '$host'" ;;
esac

[[ -n "$archive" ]] || fail "--archive is required"
[[ -f "$archive" && ! -L "$archive" ]] || fail "archive is not a regular file: $archive"
archive="$(cd "$(dirname "$archive")" && pwd -P)/$(basename "$archive")"
checksum="${archive}.sha256"
[[ -f "$checksum" && ! -L "$checksum" ]] || fail "adjacent checksum is missing: $checksum"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
native_executable_validator="$root/scripts/dev/native-host/validate-native-executable.py"
asset="$(basename "$archive")"
if [[ "$asset" =~ ^mainframe-((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))\.tar\.gz$ ]]; then
    version="${BASH_REMATCH[1]}"
else
    fail "archive name must be mainframe-MAJOR.MINOR.PATCH.tar.gz"
fi
checksum_line_count="$(awk 'END {print NR + 0}' "$checksum")" || \
    fail "checksum could not be read"
[[ "$checksum_line_count" == "1" ]] || fail "checksum must contain exactly one record"
checksum_record=""
IFS= read -r checksum_record < "$checksum" || [[ -n "$checksum_record" ]] || \
    fail "checksum record is empty"
expected_sha="${checksum_record%% *}"
[[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] || fail "checksum is not lowercase SHA-256"
[[ "$checksum_record" == "$expected_sha  $asset" ]] || \
    fail "checksum must be the canonical '<sha256>  $asset' record"
[[ "$(sha256_file "$archive")" == "$expected_sha" ]] || fail "archive checksum mismatch"

platform_gate="$root/scripts/dev/native-host/assert-runner-platform.sh"
[[ -f "$platform_gate" && ! -L "$platform_gate" && -x "$platform_gate" ]] ||
    fail "native platform admission helper is missing or unsafe"
platform_record="$("${BASH:-/bin/bash}" "$platform_gate" --observe-native)" ||
    fail "native platform admission failed"
[[ "$platform_record" != *$'\n'* ]] || fail "native platform observation is not one record"
IFS=$'\t' read -r actual_os actual_arch platform_extra <<<"$platform_record"
[[ -n "$actual_os" && -n "$actual_arch" && -z "${platform_extra:-}" ]] ||
    fail "native platform observation is malformed"
[[ -f "$native_executable_validator" && ! -L "$native_executable_validator" ]] ||
    fail "native executable validator is missing or unsafe"
native_executable_validator_sha="$(sha256_file "$native_executable_validator")"
python_bin="$(command -v python3 || true)"
[[ -x "$python_bin" ]] || fail "python3 is required"
python_bin="$($python_bin -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$python_bin")"
[[ -f "$python_bin" && ! -L "$python_bin" && -x "$python_bin" ]] ||
    fail "resolved python3 executable is missing or unsafe"

case "$shell_name" in
    "")
        if [[ "$actual_os" == "Darwin" ]]; then shell_name=zsh; else shell_name=bash; fi
        ;;
    bash|zsh) ;;
    *) fail "unsupported shell '$shell_name'" ;;
esac

case "$actual_os" in
    Darwin)
        actual_system_libc=none
        ;;
    Linux)
        libc_report="$(/usr/bin/getconf GNU_LIBC_VERSION 2>/dev/null || true)"
        if [[ "$libc_report" == glibc\ * ]]; then
            actual_system_libc=glibc
        else
            ldd_report=""
            for ldd_bin in /usr/bin/ldd /bin/ldd; do
                if [[ -x "$ldd_bin" ]]; then
                    ldd_report="$("$ldd_bin" --version 2>&1 || true)"
                    [[ -n "$ldd_report" ]] && break
                fi
            done
            if [[ "$ldd_report" == *musl* || "$ldd_report" == *Musl* ]]; then
                actual_system_libc=musl
            else
                fail "could not identify the Linux system libc"
            fi
        fi
        ;;
    *)
        fail "shell onboarding certification is unsupported on $actual_os"
        ;;
esac

if [[ "$shell_name" == "zsh" ]]; then
    shell_bin="$(command -v zsh || true)"
else
    shell_bin="$(command -v bash || true)"
fi
[[ -x "$shell_bin" ]] || fail "$shell_name is unavailable"
shell_bin="$($python_bin -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$shell_bin")"
shell_binding="$(native_executable_binding "$shell_bin" "selected shell executable")" ||
    fail "selected shell executable failed native admission"

modern_bash="${MAINFRAME_BASH:-$(command -v bash)}"
if [[ "$modern_bash" != */* ]]; then
    modern_bash="$(command -v "$modern_bash" || true)"
fi
[[ -x "$modern_bash" ]] || fail "MAINFRAME_BASH is not executable"
modern_bash="$($python_bin -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$modern_bash")"
modern_bash_binding="$(native_executable_binding "$modern_bash" "MAINFRAME runtime Bash executable")" ||
    fail "MAINFRAME runtime Bash executable failed native admission"
if ! "$modern_bash" -c '
    (( BASH_VERSINFO[0] > 4 )) ||
    (( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))
' >/dev/null 2>&1; then
    fail "Bash 4.4+ is required for the installed runtime"
fi
command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v tar >/dev/null 2>&1 || fail "tar is required"
case "$modern_bash" in
    "$root"|"$root"/*) fail "MAINFRAME_BASH must not come from the source checkout" ;;
esac

tmp_parent="${TMPDIR:-/tmp}"
[[ -d "$tmp_parent" ]] || fail "TMPDIR is not a directory: $tmp_parent"
tmp_parent="$(cd -- "$tmp_parent" && pwd -P)"
[[ "$tmp_parent" != "/" ]] || fail "refusing to use the filesystem root as TMPDIR"

workdir=""
output_tmp=""
cleanup_workdir() {
    local cleanup_status=$? cleanup_parent="" cleanup_name=""
    trap - EXIT
    if [[ -n "${output_tmp:-}" && -e "$output_tmp" && ! -L "$output_tmp" ]]; then
        if ! cleanup_parent="$(cd -- "$(dirname -- "$output_tmp")" 2>/dev/null && pwd -P)"; then
            cleanup_parent=""
        fi
        cleanup_name="$(basename "$output_tmp")"
        if [[ "$cleanup_parent" == "$output_parent" &&
              "$cleanup_name" == ".${output_name}.tmp."* &&
              -f "$output_tmp" ]]; then
            rm -f -- "$output_tmp"
        else
            printf 'shell-onboarding certification refused unsafe evidence cleanup: %s\n' \
                "$output_tmp" >&2
            cleanup_status=1
        fi
    fi
    if [[ -n "${workdir:-}" && -e "$workdir" ]]; then
        if ! cleanup_parent="$(cd -- "$(dirname -- "$workdir")" 2>/dev/null && pwd -P)"; then
            cleanup_parent=""
        fi
        cleanup_name="$(basename "$workdir")"
        if [[ "$cleanup_parent" == "$tmp_parent" &&
              "$cleanup_name" == mainframe-shell-onboard.* &&
              -d "$workdir" && ! -L "$workdir" ]]; then
            rm -rf -- "$workdir"
        else
            printf 'shell-onboarding certification refused unsafe cleanup target: %s\n' \
                "$workdir" >&2
            cleanup_status=1
        fi
    fi
    exit "$cleanup_status"
}
trap cleanup_workdir EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

workdir="$(mktemp -d "$tmp_parent/mainframe-shell-onboard.XXXXXX")"
workdir="$(cd "$workdir" && pwd -P)"
[[ "$(dirname "$workdir")" == "$tmp_parent" &&
   "$(basename "$workdir")" == mainframe-shell-onboard.* &&
   -d "$workdir" && ! -L "$workdir" ]] || fail "mktemp returned an unsafe work directory"
home="$workdir/home"
project="$workdir/project"
nested_project="$project/src/agent/work"
release_root="$workdir/releases"
certifier_root="$workdir/certifier"
install_dir="$home/.mainframe"
config_home="$home/.config"
state_home="$home/.local/state"
awm_root="$state_home/mainframe/.mainframe-control-plane-runtime/project-memory-adapter-state/awm"
bin_dir="$home/.local/bin"
audit="$state_home/mainframe/onboarding-gateway.jsonl"
mkdir -p "$home" "$home/.local" "$config_home" "$state_home" \
    "$nested_project" "$release_root/v$version" "$certifier_root"
chmod 700 "$home" "$home/.local" "$config_home" "$state_home"
for private_root in "$home" "$home/.local" "$config_home" "$state_home"; do
    [[ -d "$private_root" && ! -L "$private_root" &&
       "$(file_mode "$private_root")" == "700" ]] ||
        fail "certifier private runtime root is unsafe: $private_root"
done
cp "$native_executable_validator" "$certifier_root/"
native_executable_validator_snapshot="$certifier_root/validate-native-executable.py"
chmod a-w "$native_executable_validator_snapshot"
[[ "$(sha256_file "$native_executable_validator_snapshot")" == \
   "$native_executable_validator_sha" ]] ||
    fail "private native executable validator snapshot changed during admission"
native_executable_validator="$native_executable_validator_snapshot"
candidate_archive="$release_root/v$version/$asset"
candidate_checksum="${candidate_archive}.sha256"
cp "$archive" "$candidate_archive"
[[ "$(sha256_file "$candidate_archive")" == "$expected_sha" ]] || \
    fail "staged archive checksum changed before installation"
printf '%s  %s\n' "$expected_sha" "$asset" > "$candidate_checksum"

# Exercise the bootstrap shipped in the candidate archive, but only after
# binding it byte-for-byte to the reviewed checkout copy. `tar -xO` writes no
# archive paths; duplicate or modified members necessarily fail the digest.
bootstrap="$workdir/get-mainframe.sh"
tar -xOzf "$candidate_archive" get-mainframe.sh > "$bootstrap" || \
    fail "candidate archive does not expose get-mainframe.sh"
[[ -s "$bootstrap" ]] || fail "candidate bootstrap is empty"
[[ "$(sha256_file "$bootstrap")" == "$(sha256_file "$root/get-mainframe.sh")" ]] || \
    fail "candidate bootstrap differs from the certifier checkout"

case "$host" in
    codex)
        instruction="AGENTS.md"
        enforcement=".codex/hooks.json"
        audit_host="codex"
        audit_event="PreToolUse"
        audit_tool="Bash"
        ;;
    claude-code)
        instruction="CLAUDE.md"
        enforcement=".claude/settings.json"
        audit_host="claude"
        audit_event="PreToolUse"
        audit_tool="Bash"
        ;;
    copilot)
        instruction=".github/copilot-instructions.md"
        enforcement=".github/hooks/mainframe.json"
        audit_host="copilot"
        audit_event="PreToolUse"
        audit_tool="bash"
        ;;
    gemini)
        instruction="GEMINI.md"
        enforcement=".gemini/settings.json"
        audit_host="gemini"
        audit_event="BeforeTool"
        audit_tool="run_shell_command"
        ;;
esac
mkdir -p "$project/$(dirname "$instruction")" "$project/$(dirname "$enforcement")"
printf 'Team instructions must survive.\nKeep this exact foreign policy sentence.\n' \
    > "$project/$instruction"
case "$host" in
    codex|claude-code)
        jq -n '{foreignSetting:"keep",hooks:{PreToolUse:[
            {matcher:"Read",hooks:[{type:"command",command:"foreign-read-hook"}]}
        ]}}' > "$project/$enforcement"
        ;;
    copilot)
        jq -n '{version:1,foreignSetting:"keep",hooks:{preToolUse:[
            {type:"command",matcher:"read",bash:"foreign-read-hook"}
        ]}}' > "$project/$enforcement"
        ;;
    gemini)
        jq -n '{foreignSetting:"keep",hooks:{BeforeTool:[
            {matcher:"read_file",hooks:[{type:"command",command:"foreign-read-hook"}]}
        ]}}' > "$project/$enforcement"
        ;;
esac
foreign_instruction_before="$(awk 'NF {print}' "$project/$instruction")"
foreign_enforcement_before="$(jq -cS . "$project/$enforcement")"

# Authorize file transport only inside this private, disposable proof HOME.
# The bootstrap requires all three factors: its explicit capability flag, the
# internal-testing environment bit, and this exact owner-private marker bound
# to the canonical install target. Ordinary invocations therefore cannot turn
# MAINFRAME_RELEASE_BASE_URL into a local-file escape hatch.
bootstrap_fixture_marker="$home/.mainframe-bootstrap-internal-test-mode"
printf 'MAINFRAME_BOOTSTRAP_INTERNAL_TESTING:%s\n' "$install_dir" \
    > "$bootstrap_fixture_marker"
chmod 600 "$bootstrap_fixture_marker"

env \
    HOME="$home" \
    XDG_CONFIG_HOME="$config_home" \
    XDG_STATE_HOME="$state_home" \
    SHELL="$shell_bin" \
    TMPDIR="$workdir" \
    PATH="$PATH" \
    MAINFRAME_BASH="$modern_bash" \
    MAINFRAME_INTERNAL_TESTING=1 \
    MAINFRAME_RELEASE_BASE_URL="file://$release_root" \
    MAINFRAME_INSTALL_DIR="$install_dir" \
    MAINFRAME_BIN_DIR="$bin_dir" \
    /bin/bash "$bootstrap" \
        --internal-test-fixture --release-version "$version" \
        --no-ai-discovery > "$workdir/install.log"

grep -Fq "Verified SHA-256: $expected_sha" "$workdir/install.log" || \
    fail "installer did not verify the supplied archive digest"
[[ -f "$install_dir/VERSION" ]] || fail "installed VERSION is missing"
installed_version="$(awk 'NR == 1 {value=$0} END {if (NR != 1) exit 1; print value}' \
    "$install_dir/VERSION")" || fail "installed VERSION must contain exactly one line"
[[ "$installed_version" == "$version" ]] || fail "installed VERSION does not match the archive name"
[[ -L "$bin_dir/mainframe" && "$(readlink "$bin_dir/mainframe")" == "$install_dir/bin/mainframe" ]] || \
    fail "installed launcher does not target the archive payload"

receipt_name=.mainframe-install-receipt.json
receipt="$install_dir/$receipt_name"
[[ -f "$receipt" && ! -L "$receipt" ]] || fail "release receipt is missing or non-regular"
[[ "$(file_mode "$receipt")" == "600" ]] || fail "release receipt mode is not 600"
manifest_sha="$(sha256_file "$install_dir/SHA256SUMS")"
jq -e \
    --arg version "$version" \
    --arg archive_sha256 "$expected_sha" \
    --arg manifest_sha256 "$manifest_sha" \
    --arg install_dir "$install_dir" \
    --arg bin_dir "$bin_dir" \
    --arg cli_link "$bin_dir/mainframe" '
      type == "object" and
      keys == ["archive_sha256", "bin_dir", "cli_link", "install_dir",
               "install_method", "installed_at", "manifest_sha256",
               "schema_version", "version"] and
      .schema_version == 1 and
      .install_method == "release-archive" and
      .version == $version and
      .archive_sha256 == $archive_sha256 and
      .manifest_sha256 == $manifest_sha256 and
      .install_dir == $install_dir and
      .bin_dir == $bin_dir and
      .cli_link == $cli_link and
      (.installed_at | type == "string" and length > 0 and
       (test("[\u0000-\u001f\u007f]") | not))
    ' "$receipt" >/dev/null || fail "release receipt does not exactly bind the installed archive"
verify_installed_archive_payload "$candidate_archive" "$install_dir" "$receipt_name" || \
    fail "installed payload does not exactly match the archive plus its receipt"

if [[ "$shell_name" == "zsh" ]]; then
    shell_profile="$home/.zshrc"
else
    shell_profile="$home/.bashrc"
fi
[[ -f "$shell_profile" && ! -L "$shell_profile" ]] || fail "installer did not create the shell profile"
[[ "$(grep -Fxc '# >>> MAINFRAME >>>' "$shell_profile")" == "1" ]] || \
    fail "shell profile does not contain one MAINFRAME block"
printf -v expected_root_line 'export MAINFRAME_ROOT=%q' "$install_dir"
printf -v expected_bash_line 'export MAINFRAME_BASH=%q' "$modern_bash"
printf -v expected_bin_line '_MAINFRAME_SHELL_BIN_DIR=%q' "$bin_dir"
grep -Fxq "$expected_root_line" "$shell_profile" || \
    fail "shell profile does not select the installed archive root"
grep -Fxq "$expected_bash_line" "$shell_profile" || \
    fail "shell profile does not select the canonical runtime Bash"
grep -Fxq "$expected_bin_line" "$shell_profile" || \
    fail "shell profile does not expose the installed launcher"
if [[ "$shell_name" == "bash" ]]; then
    bash_login_profile="$home/.bash_profile"
    [[ -f "$bash_login_profile" && ! -L "$bash_login_profile" ]] || \
        fail "installer did not create the Bash login profile"
    [[ "$(grep -Fxc '# >>> MAINFRAME BASH LOGIN >>>' "$bash_login_profile")" == "1" &&
       "$(grep -Fxc '# <<< MAINFRAME BASH LOGIN <<<' "$bash_login_profile")" == "1" ]] || \
        fail "Bash login profile does not contain one MAINFRAME bridge"
    grep -Fq '. "$HOME/.bashrc"' "$bash_login_profile" || \
        fail "Bash login bridge does not load the canonical Bash profile"
fi

fresh_shell() {
    local command_text="$1"
    local base_path
    base_path="$(dirname "$modern_bash"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    if [[ "$shell_name" == "zsh" ]]; then
        env -i \
            HOME="$home" USER=mainframe-test LOGNAME=mainframe-test \
            SHELL="$shell_bin" TERM=dumb PATH="$base_path" TMPDIR="$workdir" ZDOTDIR="$home" \
            XDG_CONFIG_HOME="$config_home" XDG_STATE_HOME="$state_home" \
            MAINFRAME_AGENT_AUDIT_LOG="$audit" \
            ONBOARD_HOST="$host" ONBOARD_PROJECT="$project" ONBOARD_NESTED="$nested_project" \
            EXPECTED_CLI="$bin_dir/mainframe" EXPECTED_ROOT="$install_dir" \
            EXPECTED_BIN="$bin_dir" SOURCE_ROOT="$root" \
            "$shell_bin" -lic "$command_text"
    else
        env -i \
            HOME="$home" USER=mainframe-test LOGNAME=mainframe-test \
            SHELL="$shell_bin" TERM=dumb PATH="$base_path" TMPDIR="$workdir" \
            XDG_CONFIG_HOME="$config_home" XDG_STATE_HOME="$state_home" \
            MAINFRAME_AGENT_AUDIT_LOG="$audit" \
            ONBOARD_HOST="$host" ONBOARD_PROJECT="$project" ONBOARD_NESTED="$nested_project" \
            EXPECTED_CLI="$bin_dir/mainframe" EXPECTED_ROOT="$install_dir" \
            EXPECTED_BIN="$bin_dir" SOURCE_ROOT="$root" \
            "$shell_bin" -lic "$command_text"
    fi
}

fresh_bash_nonlogin() {
    local command_text="$1" base_path
    base_path="$(dirname "$modern_bash"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    env -i \
        HOME="$home" USER=mainframe-test LOGNAME=mainframe-test \
        SHELL="$shell_bin" TERM=dumb PATH="$base_path" TMPDIR="$workdir" \
        XDG_CONFIG_HOME="$config_home" XDG_STATE_HOME="$state_home" \
        MAINFRAME_AGENT_AUDIT_LOG="$audit" \
        ONBOARD_HOST="$host" ONBOARD_PROJECT="$project" ONBOARD_NESTED="$nested_project" \
        EXPECTED_CLI="$bin_dir/mainframe" EXPECTED_ROOT="$install_dir" \
        EXPECTED_BIN="$bin_dir" SOURCE_ROOT="$root" \
        "$shell_bin" -ic "$command_text"
}

fresh_shell_decline() {
    local base_path command_text
    base_path="$(dirname "$modern_bash"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    command_text='mainframe onboard --host "$ONBOARD_HOST" --project "$ONBOARD_PROJECT"'

    env -i \
        HOME="$home" USER=mainframe-test LOGNAME=mainframe-test \
        SHELL="$shell_bin" TERM=dumb PATH="$base_path" TMPDIR="$workdir" ZDOTDIR="$home" \
        XDG_CONFIG_HOME="$config_home" XDG_STATE_HOME="$state_home" \
        MAINFRAME_AGENT_AUDIT_LOG="$audit" \
        ONBOARD_HOST="$host" ONBOARD_PROJECT="$project" \
        "$python_bin" - "$shell_bin" "$shell_name" "$command_text" <<'PYEOF'
# MAINFRAME_SHELL_ONBOARDING_PTY_DRIVER_BEGIN
import errno
import os
import pty
import select
import signal
import sys
import time

shell_bin, shell_name, command_text = sys.argv[1:]
arguments = [shell_bin, "-lic", command_text]
onboard_host = os.environ.get("ONBOARD_HOST", "")
if not onboard_host:
    print("interactive decline driver is missing ONBOARD_HOST", file=sys.stderr)
    raise SystemExit(125)
consent_prompt = (
    "Apply these MAINFRAME-managed project changes and enable the "
    f"{onboard_host} shell gate? [y/N] "
).encode("utf-8")
completion_prompts = ()
if shell_name == "zsh":
    completion_prompts = tuple(
        f"Ignore insecure {kind} and continue [y] or abort compinit [n]? ".encode(
            "utf-8"
        )
        for kind in ("directories", "files", "directories and files")
    )
maximum_prompt_size = max(map(len, (consent_prompt, *completion_prompts)))


def write_reply(payload):
    remaining = memoryview(payload)
    while remaining:
        try:
            written = os.write(descriptor, remaining)
        except InterruptedError:
            continue
        if written <= 0:
            raise OSError("interactive decline write made no progress")
        remaining = remaining[written:]

pid, descriptor = pty.fork()
if pid == 0:
    os.execve(shell_bin, arguments, dict(os.environ))

output = []
prompt_tail = b""
decline_sent = False
completion_continue_sent = False
deadline = time.monotonic() + 60
while True:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        os.kill(pid, signal.SIGTERM)
        os.waitpid(pid, 0)
        sys.stdout.buffer.write(b"".join(output))
        raise SystemExit(124)
    readable, _, _ = select.select([descriptor], [], [], remaining)
    if not readable:
        continue
    try:
        data = os.read(descriptor, 65536)
    except OSError as error:
        if error.errno == errno.EIO:
            break
        raise
    if not data:
        break
    output.append(data)
    prompt_candidate = prompt_tail + data
    if not decline_sent and consent_prompt in prompt_candidate:
        write_reply(b"n\n")
        decline_sent = True
    elif not completion_continue_sent and any(
        prompt in prompt_candidate for prompt in completion_prompts
    ):
        # A fresh zsh can reject insecure completion paths before MAINFRAME's
        # consent question. Continue past that exact, unrelated prompt without
        # pre-queuing the later onboarding decline.
        write_reply(b"y\n")
        completion_continue_sent = True
    prompt_tail = prompt_candidate[-(maximum_prompt_size - 1):]

_, wait_status = os.waitpid(pid, 0)
os.close(descriptor)
sys.stdout.buffer.write(b"".join(output))
if not decline_sent:
    print("exact onboarding consent prompt was not observed", file=sys.stderr)
    raise SystemExit(125)
if os.WIFEXITED(wait_status):
    raise SystemExit(os.WEXITSTATUS(wait_status))
raise SystemExit(128 + os.WTERMSIG(wait_status))
# MAINFRAME_SHELL_ONBOARDING_PTY_DRIVER_END
PYEOF
}

fresh_shell '
    [[ "$(command -v mainframe)" == "$EXPECTED_CLI" ]] || exit 91
    [[ "$MAINFRAME_ROOT" == "$EXPECTED_ROOT" ]] || exit 92
    case ":$PATH:" in *":$SOURCE_ROOT:"*|*":$SOURCE_ROOT/"*) exit 93 ;; esac
    [[ "$(printf "%s" "$PATH" | tr ":" "\n" | grep -Fxc "$EXPECTED_BIN")" == "1" ]] || exit 94
    mainframe doctor
    broker_envelope="$(
        mainframe invoke mf:std:pure-string:to_lower \
            --input-json "{\"value\":\"HELLO Agent\"}" \
            --format broker-json-v1
    )" || exit 98
    printf "%s\n" "$broker_envelope" | jq -e "
        type == \"object\" and
        keys == [\"audit_id\", \"canonical_id\", \"duration_ms\", \"error\",
                 \"exit_code\", \"name\", \"ok\", \"output_exceeded\", \"owner\",
                 \"schema_version\", \"status\", \"stderr_b64\", \"stdout_b64\",
                 \"timed_out\"] and
        .schema_version == 1 and .ok == true and .status == \"success\" and
        .canonical_id == \"mf:std:pure-string:to_lower\" and
        .name == \"to_lower\" and .owner == \"pure-string\" and
        .exit_code == 0 and .timed_out == false and
        .output_exceeded == false and .stdout_b64 == \"aGVsbG8gYWdlbnQK\" and
        .stderr_b64 == \"\" and .error == null and
        (.duration_ms | type == \"number\" and . >= 0) and
        (.audit_id | type == \"string\" and length > 0)
    " >/dev/null || exit 99
    printf "Broker contract: verified\n"
' > "$workdir/doctor.log"
grep -Fq 'Status: All checks passed!' "$workdir/doctor.log" || {
    cat "$workdir/doctor.log" >&2
    fail "doctor did not pass"
}
grep -Fq 'Broker contract: verified' "$workdir/doctor.log" || {
    cat "$workdir/doctor.log" >&2
    fail "broker contract failed in the fresh login shell"
}

if [[ "$shell_name" == "bash" ]]; then
    fresh_bash_nonlogin '
        [[ "$(command -v mainframe)" == "$EXPECTED_CLI" ]] || exit 95
        [[ "$MAINFRAME_ROOT" == "$EXPECTED_ROOT" ]] || exit 96
        [[ "$(printf "%s" "$PATH" | tr ":" "\n" | grep -Fxc "$EXPECTED_BIN")" == "1" ]] || exit 97
        mainframe doctor
        broker_envelope="$(
            mainframe invoke mf:std:pure-string:to_lower \
                --input-json "{\"value\":\"HELLO Agent\"}" \
                --format broker-json-v1
        )" || exit 98
        printf "%s\n" "$broker_envelope" | jq -e \
            ".schema_version == 1 and .ok == true and .status == \"success\" and
             .canonical_id == \"mf:std:pure-string:to_lower\" and
             .stdout_b64 == \"aGVsbG8gYWdlbnQK\" and .stderr_b64 == \"\" and
             .error == null" >/dev/null || exit 99
        printf "Broker contract: verified\n"
    ' > "$workdir/bash-nonlogin-doctor.log"
    grep -Fq 'Status: All checks passed!' "$workdir/bash-nonlogin-doctor.log" || {
        cat "$workdir/bash-nonlogin-doctor.log" >&2
        fail "doctor did not pass in an interactive non-login Bash shell"
    }
    grep -Fq 'Broker contract: verified' "$workdir/bash-nonlogin-doctor.log" || {
        cat "$workdir/bash-nonlogin-doctor.log" >&2
        fail "broker contract failed in an interactive non-login Bash shell"
    }
fi

awm_before_consent="$(optional_tree_digest "$awm_root")" || \
    fail "AWM root is unsafe before onboarding"
before="$(tree_digest "$project")"
fresh_shell 'mainframe onboard --host "$ONBOARD_HOST" --project "$ONBOARD_PROJECT" --dry-run' \
    > "$workdir/dry-run.log"
[[ "$(tree_digest "$project")" == "$before" ]] || fail "dry-run changed the project"
[[ ! -e "$audit" ]] || fail "dry-run created gateway audit state"
[[ "$(optional_tree_digest "$awm_root")" == "$awm_before_consent" ]] || \
    fail "dry-run changed AWM state"

set +e
fresh_shell 'mainframe onboard --host "$ONBOARD_HOST" --project "$ONBOARD_PROJECT"' \
    </dev/null > "$workdir/noninteractive.log" 2>&1
decline_status=$?
set -e
[[ "$decline_status" -eq 2 ]] || fail "noninteractive onboarding without --yes did not exit 2"
[[ "$(tree_digest "$project")" == "$before" ]] || fail "unapproved onboarding changed the project"
[[ ! -e "$audit" ]] || fail "unapproved onboarding created gateway audit state"
[[ "$(optional_tree_digest "$awm_root")" == "$awm_before_consent" ]] || \
    fail "unapproved onboarding changed AWM state"

set +e
fresh_shell_decline > "$workdir/decline.log" 2>&1
interactive_decline_status=$?
set -e
[[ "$interactive_decline_status" -eq 2 ]] || fail "interactive decline did not exit 2"
grep -Fq 'onboarding declined; no changes were made' "$workdir/decline.log" || \
    fail "interactive decline was not observed"
[[ "$(tree_digest "$project")" == "$before" ]] || fail "declined onboarding changed the project"
[[ ! -e "$audit" ]] || fail "declined onboarding created gateway audit state"
[[ "$(optional_tree_digest "$awm_root")" == "$awm_before_consent" ]] || \
    fail "declined onboarding changed AWM state"

fresh_shell 'mainframe onboard --host "$ONBOARD_HOST" --project "$ONBOARD_PROJECT" --yes' \
    > "$workdir/onboard.log"
grep -Fq 'Host runtime load:' "$workdir/onboard.log" || fail "runtime boundary is missing"
grep -Fq 'UNVERIFIED' "$workdir/onboard.log" || fail "runtime load was overstated"
grep -Eq '^AWM project session:  RECORDED \([0-9a-f]{12}; non-authoritative\)$' \
    "$workdir/onboard.log" || {
    cat "$workdir/onboard.log" >&2
    fail "AWM project session was not recorded with the non-authority boundary"
}
grep -Fq 'AWM project reads:    READY (durable control-plane; non-authoritative data)' \
    "$workdir/onboard.log" || fail "AWM project read plane is not ready"
[[ -f "$project/$instruction" && -f "$project/$enforcement" ]] || \
    fail "managed host files are missing"
grep -Fq 'Team instructions must survive.' "$project/$instruction" || \
    fail "foreign project instructions were overwritten"
grep -Fq 'mainframe awm project context --project . --discover-root "<current task>" --tokens 1200 --format prompt' \
    "$project/$instruction" || fail "managed instructions do not request the control-plane read brief"
grep -Fq 'If a required project-memory mutation or read route is unavailable, fail closed: stop and request human direction.' \
    "$project/$instruction" || fail "managed instructions omit the project-memory fail-closed boundary"
grep -Fq 'Never store credentials, tokens, secrets, raw sensitive payloads, or routine command chatter.' \
    "$project/$instruction" || fail "managed instructions omit the AWM privacy contract"
[[ -f "$audit" && ! -L "$audit" ]] || fail "gateway audit is missing"
audit_mode="$(file_mode "$audit")"
[[ "$audit_mode" == "600" ]] || fail "gateway audit mode is $audit_mode, expected 600"
jq -e -s --arg host "$audit_host" --arg event "$audit_event" --arg tool "$audit_tool" '
    length == 2 and
    all(.[];
        type == "object" and
        (keys | sort) == ["action", "details", "pid", "ts"] and
        .action == "agent_gateway_decision" and
        (.pid | type) == "number" and
        (.ts | type) == "string" and
        (.details | type) == "array" and
        (.details | length) == 6 and
        .details[0] == ("host=" + $host) and
        .details[1] == ("event=" + $event) and
        .details[2] == ("tool=" + $tool) and
        (.details[3] | startswith("risk=")) and
        (.details[4] | startswith("rule=")) and
        (.details[5] | startswith("decision="))
    ) and
    ([.[].details[5]] | sort) == ["decision=allow", "decision=deny"]
' "$audit" >/dev/null || fail "gateway audit is not decision-only allow/deny evidence"
for private_command_text in \
    'git status --short' \
    'mainframe-onboard-never-execute' \
    '/bin/rm -rf'; do
    ! grep -Fq "$private_command_text" "$audit" || \
        fail "gateway audit disclosed raw command text"
done

fresh_shell 'mainframe protect status "$ONBOARD_HOST" --project "$ONBOARD_PROJECT"' \
    > "$workdir/protect.log"
grep -Fq 'Static readiness: READY' "$workdir/protect.log" || fail "protect status is not ready"

current="$(tree_digest "$project")"
fresh_shell 'mainframe onboard --host "$ONBOARD_HOST" --project "$ONBOARD_PROJECT" --yes' \
    > "$workdir/onboard-second.log"
[[ "$(tree_digest "$project")" == "$current" ]] || fail "repeat onboarding was not idempotent"
jq -e -s 'length == 4' "$audit" >/dev/null || \
    fail "repeat onboarding did not append exactly one allow/deny audit pair"
[[ "$(file_mode "$audit")" == "600" ]] || fail "repeat onboarding weakened the audit mode"

awm_ensure_output="$(fresh_shell '
    cd "$ONBOARD_NESTED"
    printf "fresh_shell_pid=%s\n" "$$"
    mainframe awm project ensure --project . --discover-root
')"
awm_ensure_pid="$(sed -n 's/^fresh_shell_pid=//p' <<< "$awm_ensure_output" | tail -n 1)"
session_id="$(tail -n 1 <<< "$awm_ensure_output")"
[[ "$session_id" =~ ^[0-9a-f]{12}$ ]] || fail "project AWM did not return a session id"
[[ "$awm_ensure_pid" =~ ^[0-9]+$ ]] || fail "AWM ensure shell identity is missing"
awm_checkpoint_output="$(fresh_shell '
    cd "$ONBOARD_NESTED"
    printf "fresh_shell_pid=%s\n" "$$"
    mainframe awm project checkpoint --project . --discover-root onboarding verified --importance high
    mainframe awm project discovery --project . --discover-root \
        "bounded project memory survived a fresh process" --importance high
')"
awm_checkpoint_pid="$(sed -n 's/^fresh_shell_pid=//p' <<< "$awm_checkpoint_output" | tail -n 1)"
awm_context_output="$(fresh_shell '
    cd "$ONBOARD_NESTED"
    printf "fresh_shell_pid=%s\n" "$$"
    mainframe work "onboarding verification" --project . --tokens 1200 --format prompt
')"
awm_context_pid="$(sed -n 's/^fresh_shell_pid=//p' <<< "$awm_context_output" | tail -n 1)"
[[ "$awm_checkpoint_pid" =~ ^[0-9]+$ && "$awm_context_pid" =~ ^[0-9]+$ ]] || \
    fail "AWM follow-up shell identities are missing"
[[ "$awm_ensure_pid" != "$awm_checkpoint_pid" &&
   "$awm_ensure_pid" != "$awm_context_pid" &&
   "$awm_checkpoint_pid" != "$awm_context_pid" ]] || \
    fail "AWM proof did not cross three fresh shell processes"
grep -Fq "\"session_id\":\"$session_id\"" <<< "$awm_context_output" || \
    fail "project AWM context resumed a different session"
grep -Fq 'bounded project memory survived a fresh process' <<< "$awm_context_output" || \
    fail "project AWM state did not survive a fresh shell"
grep -Fq '<mainframe-project-memory-data>' <<< "$awm_context_output" || \
    fail "work brief omitted the untrusted-memory boundary"
budget_line="$(grep -E '^Context budget: ' <<< "$awm_context_output" | tail -n 1)"
[[ "$budget_line" == *'1200 tokens'* ]] || \
    fail "AWM context did not preserve the requested complete-document budget"
actual_bytes="$(sed -n 's/.*(\([0-9][0-9]*\)\/[0-9][0-9]* bytes).*/\1/p' <<< "$budget_line")"
max_bytes="$(sed -n 's/.*([0-9][0-9]*\/\([0-9][0-9]*\) bytes).*/\1/p' <<< "$budget_line")"
[[ "$actual_bytes" =~ ^[0-9]+$ && "$max_bytes" == 4800 && \
   "$actual_bytes" -le "$max_bytes" ]] || \
    fail "AWM context exceeded its complete-document token budget"
[[ -d "$awm_root" && ! -L "$awm_root" ]] || fail "AWM did not create private durable state"
[[ "$(file_mode "$awm_root")" == "700" ]] || fail "AWM root mode is not 700"
projects_dir="$awm_root/projects"
[[ -d "$projects_dir" && ! -L "$projects_dir" ]] || fail "project AWM mapping directory is unsafe"
[[ "$(file_mode "$projects_dir")" == "700" ]] || fail "project AWM mapping directory mode is not 700"
shopt -s nullglob
project_mappings=("$projects_dir"/*.json)
shopt -u nullglob
[[ "${#project_mappings[@]}" -eq 1 ]] || fail "project AWM did not create exactly one mapping"
project_mapping="${project_mappings[0]}"
[[ ! -L "$project_mapping" && "$(file_mode "$project_mapping")" == "600" ]] || \
    fail "project AWM mapping is not a private regular file"
jq -e --arg sid "$session_id" '
    (keys | sort) == ["created_at", "project_sha256", "schema_version", "session_id"] and
    .schema_version == 1 and
    .session_id == $sid and
    (.project_sha256 | test("^[0-9a-f]{64}$"))
' "$project_mapping" >/dev/null || fail "project AWM mapping metadata is invalid"
! grep -Fq "$project" "$project_mapping" || fail "project AWM mapping disclosed the project path"
session_manifest="$awm_root/sessions/projects/$session_id/manifest.json"
[[ -f "$session_manifest" && ! -L "$session_manifest" ]] || \
    fail "project AWM session manifest is missing"
jq -e --arg sid "$session_id" '
    .session_id == $sid and .namespace == "projects" and .backend == "file"
' "$session_manifest" >/dev/null || fail "project AWM session is not private file-backed state"

before_deactivate="$(tree_digest "$project")"
fresh_shell 'mainframe deactivate "$ONBOARD_HOST" --project "$ONBOARD_PROJECT" --enforce --dry-run' \
    > "$workdir/deactivate-dry-run.log"
[[ "$(tree_digest "$project")" == "$before_deactivate" ]] || \
    fail "deactivate dry-run changed the project"
fresh_shell 'mainframe deactivate "$ONBOARD_HOST" --project "$ONBOARD_PROJECT" --enforce' \
    > "$workdir/deactivate.log"
[[ -f "$project/$instruction" ]] || fail "rollback removed the foreign instruction file"
[[ "$(awk 'NF {print}' "$project/$instruction")" == "$foreign_instruction_before" ]] || \
    fail "rollback changed foreign project instructions"
! grep -Fq '<!-- MAINFRAME:BEGIN' "$project/$instruction" || \
    fail "rollback left MAINFRAME instruction content behind"
[[ -f "$project/$enforcement" ]] || fail "rollback removed the foreign enforcement config"
[[ "$(jq -cS . "$project/$enforcement")" == "$foreign_enforcement_before" ]] || \
    fail "rollback changed foreign enforcement semantics"
! grep -Fq 'mainframe agent-hook' "$project/$enforcement" || \
    fail "rollback left the MAINFRAME enforcement hook behind"

require_native_executable_binding "$shell_bin" "$shell_binding" "selected shell executable"
require_native_executable_binding \
    "$modern_bash" "$modern_bash_binding" "MAINFRAME runtime Bash executable"

if [[ -n "$output" ]]; then
    output_tmp="$(mktemp "$output_parent/.${output_name}.tmp.XXXXXX")" || \
        fail "could not create a private temporary evidence file"
    chmod 600 "$output_tmp" || {
        rm -f -- "$output_tmp"
        fail "could not protect the temporary evidence file"
    }
    jq -n \
        --arg version "$version" \
        --arg archive_sha256 "$expected_sha" \
        --arg host "$host" \
        --arg shell "$shell_name" \
        --arg os "$actual_os" \
        --arg arch "$actual_arch" \
        --arg system_libc "$actual_system_libc" '
          {
            schema_version: 1,
            certification: "shell-onboarding-certified",
            version: $version,
            archive_sha256: $archive_sha256,
            host: $host,
            shell: $shell,
            os: $os,
            arch: $arch,
            system_libc: $system_libc,
            installed_payload: "exact",
            runtime_load: "unverified",
            private_paths_embedded: false
          }
        ' > "$output_tmp" || {
        rm -f -- "$output_tmp"
        fail "could not create shell-onboarding evidence"
    }
    "$python_bin" "$root/scripts/dev/native-host/validate-evidence.py" \
        "$root/scripts/dev/shell-onboarding-evidence.schema.json" \
        "$output_tmp" >/dev/null || {
        rm -f -- "$output_tmp"
        fail "generated shell-onboarding evidence failed validation"
    }
    chmod 644 "$output_tmp" || {
        rm -f -- "$output_tmp"
        fail "could not set the evidence file mode"
    }
    ln -- "$output_tmp" "$output" || {
        rm -f -- "$output_tmp"
        fail "could not publish shell-onboarding evidence"
    }
    rm -f -- "$output_tmp" || fail "could not remove the temporary evidence link"
    output_tmp=""
fi

printf 'shell-onboarding-certified host=%s shell=%s archive_sha256=%s installed_payload=exact runtime_load=unverified\n' \
    "$host" "$shell_name" "$expected_sha"

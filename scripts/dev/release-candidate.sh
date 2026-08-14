#!/bin/bash -p
# Assemble or check one coherent, local-only MAINFRAME release candidate.
# This script never creates tags, pushes commits, publishes releases, or writes
# outside the selected output directory and the existing metadata prepare step.

if [[ "$-" != *p* ]]; then
    /bin/bash --noprofile --norc -p -- "$0" "$@"
else
_MAINFRAME_RELEASE_SOURCE="${BASH_SOURCE[0]}"
case "$_MAINFRAME_RELEASE_SOURCE" in
    */*) _MAINFRAME_RELEASE_SOURCE_DIR="${_MAINFRAME_RELEASE_SOURCE%/*}" ;;
    *) _MAINFRAME_RELEASE_SOURCE_DIR=. ;;
esac
SCRIPT_DIR="$(builtin cd -- "$_MAINFRAME_RELEASE_SOURCE_DIR" && builtin pwd -P)"
# shellcheck source=scripts/dev/release-runtime.sh
builtin source "$SCRIPT_DIR/release-runtime.sh"
mainframe_release_bootstrap "$0" "$@" || exit $?
builtin unset _MAINFRAME_RELEASE_SOURCE _MAINFRAME_RELEASE_SOURCE_DIR

set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
DEFAULT_OUTPUT_DIR="$ROOT_DIR/dist"
# shellcheck source=scripts/dev/release-payload.sh
builtin source "$SCRIPT_DIR/release-payload.sh"

usage() {
    cat <<'EOF'
Usage: scripts/dev/release-candidate.sh [--prepare|--check] [--output-dir DIR]

  --prepare          Prepare metadata and atomically mark a coherent local
                     archive, checksum, SBOM, and Homebrew formula candidate.
                     This is the default.
  --check            Read-only verification that the existing candidate exactly
                     matches a fresh reproducible build from the current source.
  --output-dir DIR   Candidate directory (default: dist/).

This command is local-only. It never creates a tag, pushes, publishes a GitHub
release, updates a Homebrew tap, or contacts a package registry.
EOF
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

mode=prepare
output_dir="$DEFAULT_OUTPUT_DIR"
while (( $# > 0 )); do
    case "$1" in
        --prepare)
            mode=prepare
            shift
            ;;
        --check)
            mode=check
            shift
            ;;
        --output-dir)
            (( $# >= 2 )) || fail "--output-dir requires a path"
            output_dir="$2"
            shift 2
            ;;
        --output-dir=*)
            output_dir="${1#*=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'ERROR: unknown option: %s\n\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

[[ -n "$output_dir" ]] || fail "output directory must not be empty"
[[ ! -L "$output_dir" ]] || fail "output directory must not be a symbolic link"
if [[ "$mode" == "prepare" ]]; then
    mkdir -p -- "$output_dir"
else
    [[ -d "$output_dir" ]] || fail "candidate output directory does not exist: $output_dir"
fi
[[ -d "$output_dir" && ! -L "$output_dir" ]] || \
    fail "output directory must be a non-symlink directory: $output_dir"
output_dir="$(cd "$output_dir" && pwd -P)"

version="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || \
    fail "VERSION must contain stable SemVer"

archive_name="mainframe-${version}.tar.gz"
checksum_name="${archive_name}.sha256"
sbom_name="mainframe-${version}.sbom.json"
formula_name="mainframe.rb"
manifest_name="mainframe-${version}.candidate.json"
candidate_files=(
    "$archive_name"
    "$checksum_name"
    "$sbom_name"
    "$formula_name"
    "$manifest_name"
)
lock_root="${TMPDIR:-/tmp}/mainframe-release-candidate-locks-$(id -u)"
[[ ! -L "$lock_root" ]] || fail "candidate lock root must not be a symbolic link"
if [[ ! -e "$lock_root" ]]; then
    prior_umask="$(umask)"
    umask 077
    mkdir -- "$lock_root"
    umask "$prior_umask"
fi
[[ -d "$lock_root" && ! -L "$lock_root" && -O "$lock_root" ]] || \
    fail "candidate lock root must be a user-owned, non-symlink directory"
lock_key="$("$MAINFRAME_RELEASE_PYTHON" -I -S -B -c \
    'import hashlib, sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest())' \
    "$output_dir")"
lock_dir="$lock_root/${lock_key}.lock"
scratch=""
lock_owned=0
publish_started=0
publish_complete=0
old_move_complete=0
previous=""
previous_names=()
new_names=()

cleanup() {
    local status=$?
    local name
    if (( publish_started && ! publish_complete )); then
        # Restore the complete prior set after any ordinary write failure or
        # handled signal. The validity marker is never retained for a partial
        # replacement.
        if (( old_move_complete )); then
            for name in "${candidate_files[@]}"; do
                rm -f -- "$output_dir/$name"
            done
        else
            for name in "${new_names[@]}"; do
                rm -f -- "$output_dir/$name"
            done
        fi
        if [[ -n "$previous" && -d "$previous" ]]; then
            for name in "${previous_names[@]}"; do
                if [[ -f "$previous/$name" && ! -L "$previous/$name" ]]; then
                    mv -f -- "$previous/$name" "$output_dir/$name" || true
                fi
            done
        fi
    fi
    if [[ -n "$scratch" && -d "$scratch" ]]; then
        rm -rf -- "$scratch"
    fi
    if (( lock_owned )) && [[ -d "$lock_dir" && ! -L "$lock_dir" ]]; then
        rmdir -- "$lock_dir" 2>/dev/null || true
    fi
    return "$status"
}

handle_int() {
    exit 130
}

handle_term() {
    exit 143
}

trap cleanup EXIT
trap handle_int INT
trap handle_term TERM

if ! mkdir -- "$lock_dir" 2>/dev/null; then
    fail "another release-candidate assembly or check is using $output_dir"
fi
lock_owned=1
scratch="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-release-candidate.XXXXXX")"
expected="$scratch/expected"
recheck="$scratch/recheck"
mkdir -p -- "$expected" "$recheck"
source_pathspecs="$scratch/source-pathspecs"
source_before="$scratch/source-before.json"
source_after="$scratch/source-after.json"
source_final="$scratch/source-final.json"
mainframe_release_payload_git_pathspecs > "$source_pathspecs"

capture_source_snapshot() {
    local output="${1:?source snapshot output is required}"
    local inventory="${output}.inventory"

    if ! mainframe_release_payload_files "$ROOT_DIR" > "$inventory"; then
        fail "release payload inventory failed during source capture"
    fi
    "$MAINFRAME_RELEASE_PYTHON" -I -S -B \
        "$ROOT_DIR/scripts/dev/verify-release-candidate.py" \
        --source-root "$ROOT_DIR" \
        --source-inventory "$inventory" \
        --source-pathspecs "$source_pathspecs" \
        --capture-source-snapshot "$output" >/dev/null
}

require_source_unchanged() {
    local observed="${1:?observed source snapshot is required}"

    if ! cmp -s -- "$source_before" "$observed"; then
        fail "release source or Git index changed during candidate assembly"
    fi
}

archive="$expected/$archive_name"
checksum="$expected/$checksum_name"
sbom="$expected/$sbom_name"
formula="$expected/$formula_name"
manifest="$expected/$manifest_name"

if [[ "$mode" == "prepare" ]]; then
    "$MAINFRAME_RELEASE_BASH" --noprofile --norc -p \
        "$ROOT_DIR/scripts/dev/release.sh" --prepare
fi
"$MAINFRAME_RELEASE_BASH" --noprofile --norc -p \
    "$ROOT_DIR/scripts/dev/release.sh" --check
capture_source_snapshot "$source_before"
"$MAINFRAME_RELEASE_BASH" --noprofile --norc -p \
    "$ROOT_DIR/scripts/build-release-archive.sh" --verify
"$MAINFRAME_RELEASE_BASH" --noprofile --norc -p \
    "$ROOT_DIR/scripts/build-release-archive.sh" --output-dir "$expected"
"$MAINFRAME_RELEASE_BASH" --noprofile --norc -p \
    "$ROOT_DIR/scripts/dev/generate-homebrew-formula.sh" \
    --archive "$archive" \
    --checksum "$checksum" \
    --output "$formula"
"$MAINFRAME_RELEASE_PYTHON" -I -S -B \
    "$ROOT_DIR/scripts/dev/validate-release-sbom.py" "$sbom" "$version"
"$MAINFRAME_RELEASE_PYTHON" -I -S -B \
    "$ROOT_DIR/scripts/dev/verify-release-candidate.py" \
    --version "$version" \
    --archive "$archive" \
    --checksum "$checksum" \
    --sbom "$sbom" \
    --formula "$formula" \
    --manifest "$manifest" \
    --source-root "$ROOT_DIR" \
    --source-inventory "${source_before}.inventory" \
    --source-pathspecs "$source_pathspecs" \
    --source-snapshot "$source_before"
if command -v ruby >/dev/null 2>&1; then
    ruby -c "$formula" >/dev/null
fi

# Detect a source mutation during assembly before any candidate output changes.
"$MAINFRAME_RELEASE_BASH" --noprofile --norc -p \
    "$ROOT_DIR/scripts/dev/release.sh" --check
capture_source_snapshot "$source_after"
require_source_unchanged "$source_after"

if [[ "$mode" == "check" ]]; then
    for name in "${candidate_files[@]}"; do
        target="$output_dir/$name"
        [[ -f "$target" && ! -L "$target" ]] || \
            fail "candidate output is missing or unsafe: $target"
        if ! cmp -s -- "$expected/$name" "$target"; then
            fail "candidate output is stale or inconsistent: $name"
        fi
    done

    actual_manifest="$recheck/$manifest_name"
    "$MAINFRAME_RELEASE_PYTHON" -I -S -B \
        "$ROOT_DIR/scripts/dev/verify-release-candidate.py" \
        --version "$version" \
        --archive "$output_dir/$archive_name" \
        --checksum "$output_dir/$checksum_name" \
        --sbom "$output_dir/$sbom_name" \
        --formula "$output_dir/$formula_name" \
        --manifest "$actual_manifest" \
        --source-root "$ROOT_DIR" \
        --source-inventory "${source_before}.inventory" \
        --source-pathspecs "$source_pathspecs" \
        --source-snapshot "$source_before"
    cmp -s -- "$output_dir/$manifest_name" "$actual_manifest" || \
        fail "candidate manifest is stale or inconsistent: $manifest_name"
    capture_source_snapshot "$source_final"
    require_source_unchanged "$source_final"
    printf 'Local release candidate is current and coherent: %s\n' \
        "$output_dir/$manifest_name"
    exit 0
fi

# The manifest is the validity marker. Preserve the complete old set before
# replacing anything, publish the new marker last, and restore the old set if
# any ordinary move or handled signal fails.
for name in "${candidate_files[@]}"; do
    target="$output_dir/$name"
    [[ ! -L "$target" ]] || fail "refusing symbolic-link candidate output: $target"
    if [[ -e "$target" && ! -f "$target" ]]; then
        fail "candidate output must be absent or a regular file: $target"
    fi
done
previous="$scratch/previous"
mkdir -p -- "$previous"
publish_started=1
for name in "${candidate_files[@]}"; do
    if [[ -f "$output_dir/$name" ]]; then
        mv -- "$output_dir/$name" "$previous/$name"
        previous_names+=("$name")
    fi
done
old_move_complete=1
for name in "$archive_name" "$checksum_name" "$sbom_name" "$formula_name"; do
    mv -f -- "$expected/$name" "$output_dir/$name"
    new_names+=("$name")
done
mv -f -- "$manifest" "$output_dir/$manifest_name"
new_names+=("$manifest_name")

actual_manifest="$recheck/$manifest_name"
"$MAINFRAME_RELEASE_PYTHON" -I -S -B \
    "$ROOT_DIR/scripts/dev/verify-release-candidate.py" \
    --version "$version" \
    --archive "$output_dir/$archive_name" \
    --checksum "$output_dir/$checksum_name" \
    --sbom "$output_dir/$sbom_name" \
    --formula "$output_dir/$formula_name" \
    --manifest "$actual_manifest" \
    --source-root "$ROOT_DIR" \
    --source-inventory "${source_before}.inventory" \
    --source-pathspecs "$source_pathspecs" \
    --source-snapshot "$source_before"
cmp -s -- "$output_dir/$manifest_name" "$actual_manifest" || \
    fail "published local candidate manifest did not reproduce"
capture_source_snapshot "$source_final"
require_source_unchanged "$source_final"
publish_complete=1

printf 'Local release candidate assembled (nothing published): %s\n' \
    "$output_dir/$manifest_name"
fi

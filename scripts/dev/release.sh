#!/bin/bash -p
# Validate and prepare MAINFRAME release metadata and artifacts.
# This script never creates or pushes a tag and never publishes a release.

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

ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"

usage() {
    cat <<'EOF'
Usage: scripts/dev/release.sh [--check|--prepare|--version]

  --check    Validate version synchronization and committed release artifacts.
  --prepare  Validate the source tree and regenerate SHA256SUMS and sbom.json.
  --version  Print the validated version from VERSION.

This command does not create tags, push commits, or publish releases.
EOF
}

read_version() {
    [[ -f "$VERSION_FILE" ]] || {
        echo "ERROR: VERSION file not found at $VERSION_FILE" >&2
        exit 1
    }

    local version
    version="$(tr -d '[:space:]' < "$VERSION_FILE")"
    [[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
        echo "ERROR: VERSION '$version' must be stable SemVer (MAJOR.MINOR.PATCH)" >&2
        exit 1
    }
    printf '%s\n' "$version"
}

validate_source() {
    "$MAINFRAME_RELEASE_BASH" --noprofile --norc -p \
        "$ROOT_DIR/scripts/sync-version.sh" --check
    "$MAINFRAME_RELEASE_PYTHON" -I -S -B \
        "$ROOT_DIR/scripts/generate-manifest.py" --verify
    "$MAINFRAME_RELEASE_PYTHON" -I -S -B \
        "$ROOT_DIR/scripts/check-owner-parity.py"
    "$MAINFRAME_RELEASE_PYTHON" -I -S -B \
        "$ROOT_DIR/scripts/export-gate-rules.py" --check
    "$MAINFRAME_RELEASE_PYTHON" -I -S -B \
        "$ROOT_DIR/scripts/generate-runtime-closure.py" --check
    "$MAINFRAME_RELEASE_BASH" --noprofile --norc -p \
        "$ROOT_DIR/scripts/generate-host-adapters.sh" --check
    "$MAINFRAME_RELEASE_PYTHON" -I -S -B \
        "$ROOT_DIR/scripts/check-control-plane-claim.py" \
        --root "$ROOT_DIR"
}

validate_sbom() {
    local version="$1"
    "$MAINFRAME_RELEASE_PYTHON" -I -S -B \
        "$ROOT_DIR/scripts/dev/validate-release-sbom.py" \
        "$ROOT_DIR/sbom.json" "$version"
}

mode="${1:---prepare}"
case "$mode" in
    --version)
        read_version
        ;;
    --check)
        version="$(read_version)"
        validate_source
        "$MAINFRAME_RELEASE_BASH" --noprofile --norc -p \
            "$ROOT_DIR/scripts/generate-sbom.sh" --check
        validate_sbom "$version"
        printf 'Release inputs and artifacts are valid for v%s\n' "$version"
        ;;
    --prepare)
        version="$(read_version)"
        validate_source
        "$MAINFRAME_RELEASE_BASH" --noprofile --norc -p \
            "$ROOT_DIR/scripts/generate-sbom.sh"
        [[ -s "$ROOT_DIR/SHA256SUMS" ]] || {
            echo "ERROR: SHA256SUMS was not generated" >&2
            exit 1
        }
        [[ -s "$ROOT_DIR/sbom.json" ]] || {
            echo "ERROR: sbom.json was not generated" >&2
            exit 1
        }
        validate_sbom "$version"
        printf 'Release artifacts prepared for v%s (not published)\n' "$version"
        ;;
    -h|--help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
fi

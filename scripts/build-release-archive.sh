#!/bin/bash -p
# =============================================================================
# build-release-archive.sh - Reproducible runtime archive + checksums (P2)
#
# Produces dist/mainframe-<version>.tar.gz that is byte-reproducible across
# macOS and Linux for the same tree state: canonical USTAR headers, sorted
# files, zeroed mtimes, root ownership, and a timestamp-free gzip stream.
# Also emits .sha256 and copies the SBOM.
#
# Usage: scripts/build-release-archive.sh [--verify] [--output-dir DIR]
#   --verify: build twice into a temp dir and assert identical digests
#   --output-dir: write normal build outputs outside dist/ (developer tooling)
# =============================================================================

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
builtin source "$SCRIPT_DIR/dev/release-runtime.sh"
mainframe_release_bootstrap "$0" "$@" || exit $?
builtin unset _MAINFRAME_RELEASE_SOURCE _MAINFRAME_RELEASE_SOURCE_DIR

set -euo pipefail

ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION=$(cat "$ROOT/VERSION")
DIST="$ROOT/dist"
# shellcheck source=scripts/dev/release-payload.sh
source "$SCRIPT_DIR/dev/release-payload.sh"

sha256_digest() {
    local file="$1"

    if command -v sha256sum &>/dev/null; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$file" | awk '{print $1}'
    elif command -v openssl &>/dev/null; then
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    else
        printf 'no SHA-256 tool available (need sha256sum, shasum, or openssl)\n' >&2
        return 1
    fi
}

build() (
    local outdir="$1"
    local archive="$outdir/mainframe-${VERSION}.tar.gz"
    local stage file inventory
    local -a files

    umask 022
    mkdir -p "$outdir"
    stage=$(mktemp -d "${TMPDIR:-/tmp}/mainframe-release-stage.XXXXXX")
    trap 'rm -rf "$stage"' EXIT

    # Process substitution hides the producer's exit status. Capture the
    # inventory explicitly so even a late failure after partial output aborts
    # the release instead of silently creating a partial archive.
    inventory="$stage/.mainframe-release-inventory"
    if ! mainframe_release_payload_files "$ROOT" > "$inventory"; then
        printf 'release payload inventory failed\n' >&2
        return 1
    fi
    mapfile -t files < "$inventory"
    rm -f "$inventory"
    if [[ ${#files[@]} -eq 0 ]]; then
        printf 'release payload is empty\n' >&2
        return 1
    fi

    for file in "${files[@]}"; do
        mkdir -p "$stage/$(dirname "$file")"
        if [[ -x "$ROOT/$file" ]]; then
            install -m 0755 "$ROOT/$file" "$stage/$file"
        else
            install -m 0644 "$ROOT/$file" "$stage/$file"
        fi
        TZ=UTC touch -t 197001010000.00 "$stage/$file"
    done

    # The repository checksum file can lag a dirty development tree. Generate
    # a manifest for the exact staged archive instead of shipping stale sums or
    # rewriting the repository's generated release artifacts.
    {
        printf '# MAINFRAME %s release archive checksums\n' "$VERSION"
        for file in "${files[@]}"; do
            printf '%s  %s\n' "$(sha256_digest "$stage/$file")" "$file"
        done
    } > "$stage/SHA256SUMS"
    TZ=UTC touch -t 197001010000.00 "$stage/SHA256SUMS"
    files+=(SHA256SUMS)

    printf '%s\n' "${files[@]}" | LC_ALL=C sort \
        | "$MAINFRAME_RELEASE_PYTHON" -I -S -B \
            "$SCRIPT_DIR/dev/build-release-tar.py" "$stage" "$archive"

    printf '%s  %s\n' "$(sha256_digest "$archive")" "$(basename "$archive")" \
        > "${archive}.sha256"
    cp "$ROOT/sbom.json" "$outdir/mainframe-${VERSION}.sbom.json"
    echo "$archive"
)

verify=0
output_dir="$DIST"
while (( $# > 0 )); do
    case "$1" in
        --verify)
            verify=1
            shift
            ;;
        --output-dir)
            (( $# >= 2 )) || {
                printf '%s\n' '--output-dir requires a path' >&2
                exit 2
            }
            output_dir="$2"
            shift 2
            ;;
        --output-dir=*)
            output_dir="${1#*=}"
            shift
            ;;
        -h|--help)
            printf '%s\n' \
                'Usage: scripts/build-release-archive.sh [--verify] [--output-dir DIR]'
            exit 0
            ;;
        *)
            printf 'unknown option: %s\n' "$1" >&2
            exit 2
            ;;
    esac
done

if (( verify )); then
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/mainframe-repro.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT
    a=$(build "$tmp/a")
    b=$(build "$tmp/b")
    da=$(sha256_digest "$a")
    db=$(sha256_digest "$b")
    echo "build A: $da"
    echo "build B: $db"
    if [[ "$da" == "$db" ]]; then
        echo "REPRODUCIBLE: identical digests"
        exit 0
    fi
    echo "NOT REPRODUCIBLE: digests differ" >&2
    exit 1
fi

if [[ -L "$output_dir" || ( -e "$output_dir" && ! -d "$output_dir" ) ]]; then
    printf 'output directory must be absent or a non-symlink directory: %s\n' \
        "$output_dir" >&2
    exit 1
fi

archive=$(build "$output_dir")
echo "archive:  $archive"
echo "checksum: ${archive}.sha256"
cat "${archive}.sha256"
fi

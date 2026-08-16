#!/bin/bash -p
# Render an unpublished Homebrew formula candidate for the exact release archive.

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

ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
VERSION_FILE="$ROOT_DIR/VERSION"
TEMPLATE="$ROOT_DIR/packaging/homebrew/Formula/mainframe.rb.in"

usage() {
    cat <<'EOF'
Usage: scripts/dev/generate-homebrew-formula.sh [options]

Options:
  --archive PATH   Release archive (default: dist/mainframe-<version>.tar.gz)
  --checksum PATH  Exact one-record SHA-256 file (default: <archive>.sha256)
  --output PATH    Rendered candidate (default: dist/mainframe.rb)
  -h, --help       Show this help

This command only generates an unpublished candidate. It does not create a tap,
publish a release, or make a Homebrew install command available to users.
EOF
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

sha256_digest() {
    local file="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    else
        fail "no SHA-256 tool available (need sha256sum, shasum, or openssl)"
    fi
}

archive=""
checksum=""
output=""

while (($# > 0)); do
    case "$1" in
        --archive)
            (($# >= 2)) || fail "--archive requires a path"
            archive="$2"
            shift 2
            ;;
        --archive=*)
            archive="${1#*=}"
            shift
            ;;
        --checksum)
            (($# >= 2)) || fail "--checksum requires a path"
            checksum="$2"
            shift 2
            ;;
        --checksum=*)
            checksum="${1#*=}"
            shift
            ;;
        --output)
            (($# >= 2)) || fail "--output requires a path"
            output="$2"
            shift 2
            ;;
        --output=*)
            output="${1#*=}"
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

[[ -f "$VERSION_FILE" && ! -L "$VERSION_FILE" ]] || fail "VERSION must be a regular file"
version="$(tr -d '[:space:]' < "$VERSION_FILE")"
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || \
    fail "VERSION must contain stable SemVer (MAJOR.MINOR.PATCH)"

asset_name="mainframe-${version}.tar.gz"
archive="${archive:-$ROOT_DIR/dist/$asset_name}"
checksum="${checksum:-${archive}.sha256}"
output="${output:-$ROOT_DIR/dist/mainframe.rb}"

[[ "$(basename "$archive")" == "$asset_name" ]] || \
    fail "archive must be named exactly $asset_name"
[[ -f "$archive" && ! -L "$archive" ]] || fail "archive must be a regular, non-symlink file: $archive"
[[ -f "$checksum" && ! -L "$checksum" ]] || fail "checksum must be a regular, non-symlink file: $checksum"
[[ -f "$TEMPLATE" && ! -L "$TEMPLATE" ]] || fail "formula template is missing or unsafe: $TEMPLATE"
[[ ! -L "$output" ]] || fail "refusing to replace symbolic-link output: $output"
if [[ -e "$output" && ! -f "$output" ]]; then
    fail "output must be absent or a regular file: $output"
fi
output_parent="$(dirname "$output")"
[[ -d "$output_parent" && ! -L "$output_parent" ]] || \
    fail "output parent must be an existing, non-symlink directory: $output_parent"
archive="$(cd "$(dirname "$archive")" && pwd -P)/$(basename "$archive")"
checksum="$(cd "$(dirname "$checksum")" && pwd -P)/$(basename "$checksum")"
template="$(cd "$(dirname "$TEMPLATE")" && pwd -P)/$(basename "$TEMPLATE")"
output="$(cd "$output_parent" && pwd -P)/$(basename "$output")"
[[ "$output" != "$archive" && "$output" != "$checksum" && "$output" != "$template" ]] || \
    fail "output must not overwrite an input"
if [[ -e "$output" ]] &&
   { [[ "$output" -ef "$archive" ]] ||
     [[ "$output" -ef "$checksum" ]] ||
     [[ "$output" -ef "$template" ]]; }; then
    fail "output must not overwrite an input"
fi

line_count="$(awk 'END { print NR + 0 }' "$checksum")"
[[ "$line_count" == "1" ]] || fail "checksum must contain exactly one record"
IFS= read -r checksum_line < "$checksum" || [[ -n "$checksum_line" ]]
expected_digest="${checksum_line%% *}"
[[ "${#expected_digest}" -eq 64 ]] || fail "checksum is not a lowercase SHA-256 record"
case "$expected_digest" in
    *[!0-9a-f]*) fail "checksum is not a lowercase SHA-256 record" ;;
esac
[[ "$checksum_line" == "$expected_digest  $asset_name" ]] || \
    fail "checksum does not name the exact asset: $asset_name"

actual_digest="$(sha256_digest "$archive")"
[[ "$actual_digest" == "$expected_digest" ]] || fail "archive digest does not match checksum record"

tmp_file="$(mktemp "${output}.tmp.XXXXXX")"
trap 'rm -f -- "$tmp_file"' EXIT INT TERM

sed \
    -e "s/@VERSION@/$version/g" \
    -e "s/@SHA256@/$expected_digest/g" \
    "$TEMPLATE" > "$tmp_file"

if grep -Eq '@[A-Z][A-Z0-9_]*@' "$tmp_file"; then
    fail "formula template contains unresolved placeholders"
fi

chmod 0644 "$tmp_file"
mv -f -- "$tmp_file" "$output"
trap - EXIT INT TERM

printf 'Generated unpublished Homebrew candidate: %s\n' "$output"
fi

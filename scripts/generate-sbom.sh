#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/scripts/generate-sbom.sh - SBOM + checksum manifest generator
# =============================================================================
# Generates:
#   SHA256SUMS          - flat checksum manifest for release-critical files
#                         (installer, libs, CLI, registry, VERSION)
#   sbom.json           - CycloneDX-lite software bill of materials
#
# Usage: scripts/generate-sbom.sh [--output-dir DIR]
# Verify:  scripts/generate-sbom.sh --check   (exit 1 if drift)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$ROOT"
CHECK=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir) OUT_DIR="$2"; shift 2 ;;
        --check) CHECK=1; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

cd "$ROOT"

# sha256 helper (sha256sum/shasum/openssl)
_sbom_sha256() {
    if command -v sha256sum &>/dev/null; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        openssl dgst -sha256 "$1" | awk '{print $NF}'
    fi
}

VERSION="$(tr -d '[:space:]' < VERSION)"

# Files that make up the verifiable release payload
mapfile -t FILES < <(
    {
        printf '%s\n' VERSION install.sh get-mainframe.sh mainframe FUNCTIONS.json
        find lib bin hooks completions scripts/security -type f 2>/dev/null
    } | sort
)

tmp_sums=$(mktemp)
tmp_sbom=$(mktemp)

{
    for f in "${FILES[@]}"; do
        [[ -f "$f" ]] || continue
        printf '%s  %s\n' "$(_sbom_sha256 "$f")" "$f"
    done
} > "$tmp_sums"

{
    printf '{\n'
    printf '  "bomFormat": "CycloneDX",\n'
    printf '  "specVersion": "1.5",\n'
    printf '  "version": 1,\n'
    printf '  "metadata": {\n'
    printf '    "timestamp": "%s",\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '    "component": {\n'
    printf '      "type": "library",\n'
    printf '      "name": "mainframe",\n'
    printf '      "version": "%s",\n' "$VERSION"
    printf '      "description": "AI-native bash runtime: safety-hardened function library and agent working memory",\n'
    printf '      "licenses": [{"license": {"id": "MIT"}}]\n'
    printf '    }\n'
    printf '  },\n'
    printf '  "components": [\n'
    first=1
    for f in "${FILES[@]}"; do
        [[ -f "$f" ]] || continue
        size=$(wc -c < "$f" | tr -d '[:space:]')
        hash=$(_sbom_sha256 "$f")
        (( first )) || printf ',\n'
        first=0
        printf '    {"type": "file", "name": "%s", "hashes": [{"alg": "SHA-256", "content": "%s"}], "properties": [{"name": "size", "value": "%s"}]}' \
            "$f" "$hash" "$size"
    done
    printf '\n  ]\n}\n'
} > "$tmp_sbom"

if (( CHECK )); then
    drift=0
    if [[ -f "$OUT_DIR/SHA256SUMS" ]]; then
        if ! diff -q <(grep -v '^#' "$OUT_DIR/SHA256SUMS") <(grep -v '^#' "$tmp_sums") >/dev/null 2>&1; then
            echo "SHA256SUMS drift detected" >&2
            drift=1
        fi
    else
        echo "SHA256SUMS missing" >&2
        drift=1
    fi
    rm -f "$tmp_sums" "$tmp_sbom"
    (( drift == 0 )) && echo "SBOM/checksums current"
    exit "$drift"
fi

{
    printf '# MAINFRAME %s release checksums (generated %s)\n' "$VERSION" "$(date -u '+%Y-%m-%d')"
    printf '# Verify: sha256sum -c SHA256SUMS --ignore-missing  (or: shasum -a 256 -c SHA256SUMS --ignore-missing)\n'
    cat "$tmp_sums"
} > "$OUT_DIR/SHA256SUMS"
mv "$tmp_sbom" "$OUT_DIR/sbom.json"
rm -f "$tmp_sums"

echo "Generated SHA256SUMS (${#FILES[@]} files) and sbom.json for v$VERSION"

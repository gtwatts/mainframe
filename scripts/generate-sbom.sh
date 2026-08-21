#!/bin/bash -p
# =============================================================================
# MAINFRAME/scripts/generate-sbom.sh - SBOM + checksum manifest generator
# =============================================================================
# Generates:
#   SHA256SUMS          - flat checksum manifest for the shared release payload
#                         (excluding the self-describing sbom.json)
#   sbom.json           - CycloneDX-lite software bill of materials
#
# Usage: scripts/generate-sbom.sh [--output-dir DIR]
# Verify:  scripts/generate-sbom.sh --check   (exit 1 if drift)
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
OUT_DIR="$ROOT"
CHECK=0
# shellcheck source=scripts/dev/release-payload.sh
source "$SCRIPT_DIR/dev/release-payload.sh"

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

# SHA256SUMS and the SBOM bind the canonical release subject. Detached claim
# receipts and their reference-bearing contract may be packaged by the archive,
# but the shared exclusion registry keeps those attestations outside the
# subject they describe. sbom.json also cannot hash itself.
# Do not use only process substitution here: mapfile would hide an inventory
# failure and could turn a missing release root into an apparently valid SBOM.
tmp_inventory=$(mktemp)
if ! mainframe_release_subject_files "$ROOT" > "$tmp_inventory"; then
    rm -f "$tmp_inventory"
    exit 1
fi
mapfile -t FILES < <(grep -v '^sbom\.json$' "$tmp_inventory")
rm -f "$tmp_inventory"
if [[ ${#FILES[@]} -eq 0 ]]; then
    printf 'release payload inventory is empty\n' >&2
    exit 1
fi

resolve_source_epoch() {
    local epoch="${SOURCE_DATE_EPOCH:-}"

    if [[ -z "$epoch" ]] && git -C "$ROOT" rev-parse --is-inside-work-tree \
        >/dev/null 2>&1; then
        epoch="$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || true)"
    fi
    epoch="${epoch:-0}"
    [[ "$epoch" =~ ^[0-9]+$ ]] || {
        printf 'SOURCE_DATE_EPOCH must be a non-negative integer\n' >&2
        return 1
    }
    printf '%s\n' "$epoch"
}

format_epoch_utc() {
    local epoch="$1"
    local format="$2"

    if date -u -d "@$epoch" "+$format" >/dev/null 2>&1; then
        date -u -d "@$epoch" "+$format"
    else
        date -u -r "$epoch" "+$format"
    fi
}

SOURCE_EPOCH="$(resolve_source_epoch)"
SBOM_TIMESTAMP="$(format_epoch_utc "$SOURCE_EPOCH" '%Y-%m-%dT%H:%M:%SZ')"
GENERATED_DATE="$(format_epoch_utc "$SOURCE_EPOCH" '%Y-%m-%d')"

tmp_sums=$(mktemp)
tmp_sbom=$(mktemp)

{
    for f in "${FILES[@]}"; do
        [[ -f "$f" ]] || continue
        printf '%s  %s\n' "$(_sbom_sha256 "$f")" "$f"
    done
} > "$tmp_sums"

PAYLOAD_DIGEST="$(_sbom_sha256 "$tmp_sums")"
SBOM_SERIAL="$("$MAINFRAME_RELEASE_PYTHON" -I -S -B - \
    "$VERSION" "$PAYLOAD_DIGEST" <<'PYEOF'
import sys
import uuid

version, digest = sys.argv[1:]
identity = f"https://github.com/gtwatts/mainframe/sbom/{version}/{digest}"
print(f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, identity)}")
PYEOF
)"

{
    printf '{\n'
    printf '  "bomFormat": "CycloneDX",\n'
    printf '  "specVersion": "1.5",\n'
    printf '  "serialNumber": "%s",\n' "$SBOM_SERIAL"
    printf '  "version": 1,\n'
    printf '  "metadata": {\n'
    printf '    "timestamp": "%s",\n' "$SBOM_TIMESTAMP"
    printf '    "component": {\n'
    printf '      "type": "library",\n'
    printf '      "bom-ref": "mainframe@%s",\n' "$VERSION"
    printf '      "name": "mainframe",\n'
    printf '      "version": "%s",\n' "$VERSION"
    printf '      "description": "AI-native bash runtime: safety-hardened function library and agent working memory",\n'
    printf '      "licenses": [{"license": {"id": "MIT"}}]\n'
    printf '    }\n'
    printf '  },\n'
    printf '  "components": [\n'
    printf '    {"type": "application", "bom-ref": "runtime:bash", "name": "Bash", "version": "4.4", "properties": [{"name": "mainframe:version-constraint", "value": ">=4.4"}]},\n'
    printf '    {"type": "application", "bom-ref": "runtime:jq", "name": "jq", "properties": [{"name": "mainframe:requirement", "value": "required for agent enforcement and full metadata support"}]},\n'
    printf '    {"type": "application", "bom-ref": "runtime:python", "name": "Python", "version": "3.9", "properties": [{"name": "mainframe:version-constraint", "value": ">=3.9 for control-plane and Pi diagnosis/lifecycle"}, {"name": "mainframe:managed-host-version-constraint", "value": ">=3.10"}, {"name": "mainframe:requirement", "value": "durable control-plane CLI, Pi diagnosis/lifecycle, and managed-host install, remove, and restore"}]}'
    for f in "${FILES[@]}"; do
        [[ -f "$f" ]] || continue
        size=$(wc -c < "$f" | tr -d '[:space:]')
        hash=$(_sbom_sha256 "$f")
        printf ',\n'
        printf '    {"type": "file", "name": "%s", "hashes": [{"alg": "SHA-256", "content": "%s"}], "properties": [{"name": "size", "value": "%s"}]}' \
            "$f" "$hash" "$size"
    done
    printf '\n  ],\n'
    printf '  "dependencies": [{"ref": "mainframe@%s", "dependsOn": ["runtime:bash", "runtime:jq", "runtime:python"]}]\n' "$VERSION"
    printf '}\n'
} > "$tmp_sbom"

# A checked-in SBOM is part of the attested source tree. Later commits that do
# not change its semantic subject must not rewrite only metadata.timestamp when
# release builders set SOURCE_DATE_EPOCH to the new commit time. Preserve the
# existing valid timestamp only when every other JSON field is byte-independent
# and equal; a real subject change still receives the requested source epoch.
if [[ -f "$OUT_DIR/sbom.json" ]]; then
    "$MAINFRAME_RELEASE_PYTHON" -I -S -B - \
        "$OUT_DIR/sbom.json" "$tmp_sbom" <<'PYEOF'
import json
from pathlib import Path
import re
import sys

existing_path = Path(sys.argv[1])
candidate_path = Path(sys.argv[2])

try:
    existing = json.loads(existing_path.read_text(encoding="utf-8"))
    candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError):
    raise SystemExit(0)

existing_metadata = existing.get("metadata")
candidate_metadata = candidate.get("metadata")
if not isinstance(existing_metadata, dict) or not isinstance(candidate_metadata, dict):
    raise SystemExit(0)

timestamp = existing_metadata.get("timestamp")
if not isinstance(timestamp, str) or re.fullmatch(
    r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", timestamp
) is None:
    raise SystemExit(0)

existing_metadata.pop("timestamp", None)
candidate_metadata.pop("timestamp", None)
if existing != candidate:
    raise SystemExit(0)

text = candidate_path.read_text(encoding="utf-8")
pattern = re.compile(r'(?m)^    "timestamp": "[^"]+",$')
if len(pattern.findall(text)) != 1:
    raise SystemExit("generated SBOM timestamp line is not unique")
candidate_path.write_text(
    pattern.sub(f'    "timestamp": {json.dumps(timestamp)},', text),
    encoding="utf-8",
)
PYEOF
fi

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

    if [[ -f "$OUT_DIR/sbom.json" ]]; then
        if ! "$MAINFRAME_RELEASE_PYTHON" -I -S -B - \
            "$OUT_DIR/sbom.json" "$tmp_sbom" <<'PYEOF'
import json
import sys

def load(path):
    with open(path, encoding="utf-8") as handle:
        value = json.load(handle)
    value.get("metadata", {}).pop("timestamp", None)
    return value

sys.exit(0 if load(sys.argv[1]) == load(sys.argv[2]) else 1)
PYEOF
        then
            echo "sbom.json drift detected" >&2
            drift=1
        fi
    else
        echo "sbom.json missing" >&2
        drift=1
    fi
    rm -f "$tmp_sums" "$tmp_sbom"
    (( drift == 0 )) && echo "SBOM/checksums current"
    exit "$drift"
fi

{
    printf '# MAINFRAME %s release checksums (source date %s)\n' "$VERSION" "$GENERATED_DATE"
    printf '# Every listed file is required; missing files are verification failures.\n'
    cat "$tmp_sums"
} > "$OUT_DIR/SHA256SUMS"
mv "$tmp_sbom" "$OUT_DIR/sbom.json"
rm -f "$tmp_sums"

echo "Generated SHA256SUMS (${#FILES[@]} files) and sbom.json for v$VERSION"
fi

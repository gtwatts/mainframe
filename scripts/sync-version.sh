#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/scripts/sync-version.sh - Single-source version propagation
# =============================================================================
# VERSION (repo root) is the single source of truth. This script propagates
# it to every consumer and regenerates FUNCTIONS.json:
#
#   VERSION
#     ├── lib/common.sh                      MAINFRAME_VERSION="..."
#     ├── mainframe (root CLI)               MAINFRAME_VERSION="..."
#     ├── scripts/generate-functions-json.sh PROJECT_VERSION="..."
#     └── FUNCTIONS.json                     "version": "..." (via generator)
#
# Usage: scripts/sync-version.sh [--check]
#   (no args)  Apply the version everywhere and regenerate FUNCTIONS.json
#   --check    Verify only; exit 1 if anything is out of sync (CI mode)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$PROJECT_ROOT/VERSION"

[[ -f "$VERSION_FILE" ]] || { echo "ERROR: VERSION file not found at $VERSION_FILE" >&2; exit 1; }
VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.-]+)?$ ]] || {
    echo "ERROR: VERSION '$VERSION' is not semver (e.g. 10.1.0)" >&2; exit 1;
}

COMMON_SH="$PROJECT_ROOT/lib/common.sh"
ROOT_CLI="$PROJECT_ROOT/mainframe"
GENERATOR="$PROJECT_ROOT/scripts/generate-functions-json.sh"
REGISTRY="$PROJECT_ROOT/FUNCTIONS.json"

# Read the version currently declared in a file for a given assignment pattern
_declared_version() {
    local file="$1" pattern="$2"
    grep -m1 -E "$pattern" "$file" 2>/dev/null | sed -E "s/.*$pattern.*/\\1/" || true
}

check_only=0
[[ "${1:-}" == "--check" ]] && check_only=1

drift=0

report_or_fix() {
    local label="$1" file="$2" current="$3"
    if [[ "$current" == "$VERSION" ]]; then
        echo "  OK    $label ($current)"
        return 0
    fi
    if (( check_only )); then
        echo "  DRIFT $label: declares '$current', VERSION says '$VERSION'"
        drift=1
        return 0
    fi
    echo "  SYNC  $label: '$current' -> '$VERSION'"
    return 1  # caller applies the edit
}

echo "MAINFRAME version source of truth: $VERSION"

# --- lib/common.sh -----------------------------------------------------------
current=$(grep -m1 '^readonly MAINFRAME_VERSION=' "$COMMON_SH" | cut -d'"' -f2 || true)
report_or_fix "lib/common.sh MAINFRAME_VERSION" "$COMMON_SH" "$current" || \
    sed -i.bak "s/^readonly MAINFRAME_VERSION=\".*\"/readonly MAINFRAME_VERSION=\"$VERSION\"/" "$COMMON_SH" && rm -f "$COMMON_SH.bak"

# --- mainframe (root CLI) ----------------------------------------------------
current=$(grep -m1 '^MAINFRAME_VERSION=' "$ROOT_CLI" | cut -d'"' -f2 || true)
report_or_fix "mainframe CLI MAINFRAME_VERSION" "$ROOT_CLI" "$current" || \
    sed -i.bak "s/^MAINFRAME_VERSION=\".*\"/MAINFRAME_VERSION=\"$VERSION\"/" "$ROOT_CLI" && rm -f "$ROOT_CLI.bak"

# --- scripts/generate-functions-json.sh --------------------------------------
current=$(grep -m1 '^PROJECT_VERSION=' "$GENERATOR" | cut -d'"' -f2 || true)
report_or_fix "generator PROJECT_VERSION" "$GENERATOR" "$current" || \
    sed -i.bak "s/^PROJECT_VERSION=\".*\"/PROJECT_VERSION=\"$VERSION\"/" "$GENERATOR" && rm -f "$GENERATOR.bak"

# --- FUNCTIONS.json ----------------------------------------------------------
if (( check_only )); then
    tmp_reg=$(mktemp)
    if bash "$GENERATOR" --output "$tmp_reg" >/dev/null 2>&1; then
        # Compare with the volatile 'generated' timestamp normalized
        if python3 - "$REGISTRY" "$tmp_reg" <<'PYEOF'
import json, sys
def load(p):
    with open(p) as f:
        d = json.load(f)
    d.pop("generated", None)
    return d
sys.exit(0 if load(sys.argv[1]) == load(sys.argv[2]) else 1)
PYEOF
        then
            echo "  OK    FUNCTIONS.json registry (content current)"
        else
            echo "  DRIFT FUNCTIONS.json: content differs from lib/*.sh"
            drift=1
        fi
    else
        echo "  ERROR generator failed; cannot verify registry"
        drift=1
    fi
    rm -f "$tmp_reg"
else
    bash "$GENERATOR" --output "$REGISTRY" >/dev/null 2>&1
    echo "  SYNC  FUNCTIONS.json regenerated"
fi

if (( check_only )); then
    if (( drift )); then
        echo ""
        echo "Version/registry drift detected. Run: scripts/sync-version.sh"
        exit 1
    fi
    echo "No drift. VERSION=$VERSION"
fi

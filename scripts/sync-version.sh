#!/bin/bash -p
# =============================================================================
# MAINFRAME/scripts/sync-version.sh - Single-source version propagation
# =============================================================================
# VERSION (repo root) is the single source of truth. This script propagates
# it to every consumer and regenerates FUNCTIONS.json:
#
#   VERSION
#     ├── lib/common.sh                      MAINFRAME_VERSION="..."
#     ├── scripts/generate-functions-json.sh PROJECT_VERSION="..."
#     ├── package.json                       "version": "..." (Pi package)
#     ├── config/pi-compatibility.json       "mainframe_version": "..."
#     ├── mcp/pyproject.toml                 version = "..."
#     ├── mcp/src/mainframe_mcp/_version.py  __version__ = "..."
#     ├── mcp/uv.lock                        mainframe-mcp package version
#     └── FUNCTIONS.json                     "version": "..." (via generator)
#
# Usage: scripts/sync-version.sh [--check]
#   (no args)  Apply the version everywhere and regenerate FUNCTIONS.json
#   --check    Verify only; exit 1 if anything is out of sync (CI mode)
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

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$PROJECT_ROOT/VERSION"

[[ -f "$VERSION_FILE" ]] || { echo "ERROR: VERSION file not found at $VERSION_FILE" >&2; exit 1; }
VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.-]+)?$ ]] || {
    echo "ERROR: VERSION '$VERSION' is not semver (e.g. 10.1.0)" >&2; exit 1;
}

COMMON_SH="$PROJECT_ROOT/lib/common.sh"
GENERATOR="$PROJECT_ROOT/scripts/generate-functions-json.sh"
REGISTRY="$PROJECT_ROOT/FUNCTIONS.json"
PACKAGE_JSON="$PROJECT_ROOT/package.json"
PI_COMPATIBILITY="$PROJECT_ROOT/config/pi-compatibility.json"
MCP_PYPROJECT="$PROJECT_ROOT/mcp/pyproject.toml"
MCP_VERSION_MODULE="$PROJECT_ROOT/mcp/src/mainframe_mcp/_version.py"
MCP_LOCK="$PROJECT_ROOT/mcp/uv.lock"

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
if ! report_or_fix "lib/common.sh MAINFRAME_VERSION" "$COMMON_SH" "$current"; then
    [[ ! -e "$COMMON_SH.bak" && ! -L "$COMMON_SH.bak" ]] || {
        echo "ERROR: refusing to overwrite existing backup: $COMMON_SH.bak" >&2
        exit 1
    }
    sed -i.bak \
        "s/^readonly MAINFRAME_VERSION=\".*\"/readonly MAINFRAME_VERSION=\"$VERSION\"/" \
        "$COMMON_SH"
    rm -f -- "$COMMON_SH.bak"
fi

# --- scripts/generate-functions-json.sh --------------------------------------
current=$(grep -m1 '^PROJECT_VERSION=' "$GENERATOR" | cut -d'"' -f2 || true)
if ! report_or_fix "generator PROJECT_VERSION" "$GENERATOR" "$current"; then
    [[ ! -e "$GENERATOR.bak" && ! -L "$GENERATOR.bak" ]] || {
        echo "ERROR: refusing to overwrite existing backup: $GENERATOR.bak" >&2
        exit 1
    }
    sed -i.bak \
        "s/^PROJECT_VERSION=\".*\"/PROJECT_VERSION=\"$VERSION\"/" \
        "$GENERATOR"
    rm -f -- "$GENERATOR.bak"
fi

# --- package.json (native Pi package) ----------------------------------------
[[ -f "$PACKAGE_JSON" && ! -L "$PACKAGE_JSON" ]] || {
    echo "ERROR: Pi package manifest not found or unsafe at $PACKAGE_JSON" >&2
    exit 1
}
current=$(grep -m1 '^[[:space:]]*"version":' "$PACKAGE_JSON" | cut -d'"' -f4 || true)
if ! report_or_fix "package.json version" "$PACKAGE_JSON" "$current"; then
    [[ ! -e "$PACKAGE_JSON.bak" && ! -L "$PACKAGE_JSON.bak" ]] || {
        echo "ERROR: refusing to overwrite existing backup: $PACKAGE_JSON.bak" >&2
        exit 1
    }
    sed -i.bak \
        "s/^[[:space:]]*\"version\": \".*\",/  \"version\": \"$VERSION\",/" \
        "$PACKAGE_JSON"
    rm -f -- "$PACKAGE_JSON.bak"
fi

# --- config/pi-compatibility.json -------------------------------------------
[[ -f "$PI_COMPATIBILITY" && ! -L "$PI_COMPATIBILITY" ]] || {
    echo "ERROR: Pi compatibility manifest not found or unsafe at $PI_COMPATIBILITY" >&2
    exit 1
}
current=$(grep -m1 '^[[:space:]]*"mainframe_version":' "$PI_COMPATIBILITY" | cut -d'"' -f4 || true)
if ! report_or_fix "Pi compatibility MAINFRAME version" "$PI_COMPATIBILITY" "$current"; then
    [[ ! -e "$PI_COMPATIBILITY.bak" && ! -L "$PI_COMPATIBILITY.bak" ]] || {
        echo "ERROR: refusing to overwrite existing backup: $PI_COMPATIBILITY.bak" >&2
        exit 1
    }
    sed -i.bak \
        "s/^[[:space:]]*\"mainframe_version\": \".*\",/  \"mainframe_version\": \"$VERSION\",/" \
        "$PI_COMPATIBILITY"
    rm -f -- "$PI_COMPATIBILITY.bak"
fi

# --- MCP Python distribution ------------------------------------------------
mcp_version_sources=("$MCP_PYPROJECT" "$MCP_VERSION_MODULE" "$MCP_LOCK")
mcp_present=0
for mcp_version_file in "${mcp_version_sources[@]}"; do
    if [[ -e "$mcp_version_file" || -L "$mcp_version_file" ]]; then
        mcp_present=$((mcp_present + 1))
    fi
done
if (( mcp_present == 0 )); then
    # The MCP runner is a separately built Python distribution and is not part
    # of the MAINFRAME runtime archive. Runtime-only installs therefore skip
    # its source-version group explicitly.
    echo "  SKIP  MCP package sources (separate distribution)"
elif (( mcp_present != ${#mcp_version_sources[@]} )); then
    echo "ERROR: MCP version sources are only partially present" >&2
    exit 1
else
    for mcp_version_file in "${mcp_version_sources[@]}"; do
        [[ -f "$mcp_version_file" && ! -L "$mcp_version_file" ]] || {
            echo "ERROR: MCP version source is unsafe at $mcp_version_file" >&2
            exit 1
        }
    done

    current=$(awk '
    $0 == "[project]" { in_project = 1; next }
    in_project && /^\[/ { exit }
    in_project && /^version = "/ {
        value = $0
        sub(/^version = "/, "", value)
        sub(/"$/, "", value)
        print value
        exit
    }
' "$MCP_PYPROJECT")
    if ! report_or_fix "mcp/pyproject.toml version" "$MCP_PYPROJECT" "$current"; then
        [[ ! -e "$MCP_PYPROJECT.bak" && ! -L "$MCP_PYPROJECT.bak" ]] || {
            echo "ERROR: refusing to overwrite existing backup: $MCP_PYPROJECT.bak" >&2
            exit 1
        }
        sed -i.bak '/^\[project\]$/,/^\[/ s/^version = ".*"$/version = "'"$VERSION"'"/' \
            "$MCP_PYPROJECT"
        rm -f -- "$MCP_PYPROJECT.bak"
    fi

    current=$(grep -m1 '^__version__ = ' "$MCP_VERSION_MODULE" | cut -d"'" -f2 || true)
    if ! report_or_fix "MCP package module version" "$MCP_VERSION_MODULE" "$current"; then
        [[ ! -e "$MCP_VERSION_MODULE.bak" && ! -L "$MCP_VERSION_MODULE.bak" ]] || {
            echo "ERROR: refusing to overwrite existing backup: $MCP_VERSION_MODULE.bak" >&2
            exit 1
        }
        sed -i.bak \
            "s/^__version__ = '.*'/__version__ = '$VERSION'/" \
            "$MCP_VERSION_MODULE"
        rm -f -- "$MCP_VERSION_MODULE.bak"
    fi

    current=$(awk '
    $0 == "name = \"mainframe-mcp\"" { in_package = 1; next }
    in_package && /^version = "/ {
        value = $0
        sub(/^version = "/, "", value)
        sub(/"$/, "", value)
        print value
        exit
    }
    in_package && /^\[\[package\]\]$/ { exit }
' "$MCP_LOCK")
    if ! report_or_fix "mcp/uv.lock package version" "$MCP_LOCK" "$current"; then
        [[ ! -e "$MCP_LOCK.bak" && ! -L "$MCP_LOCK.bak" ]] || {
            echo "ERROR: refusing to overwrite existing backup: $MCP_LOCK.bak" >&2
            exit 1
        }
        sed -i.bak '/^name = "mainframe-mcp"$/,/^\[\[package\]\]$/ s/^version = ".*"$/version = "'"$VERSION"'"/' \
            "$MCP_LOCK"
        rm -f -- "$MCP_LOCK.bak"
    fi
fi

# --- FUNCTIONS.json ----------------------------------------------------------
if (( check_only )); then
    tmp_reg=$(mktemp)
    if MAINFRAME_ROOT="$PROJECT_ROOT" \
        "$MAINFRAME_RELEASE_BASH" --noprofile --norc -p \
        "$GENERATOR" --output "$tmp_reg" >/dev/null 2>&1; then
        # Compare with the volatile 'generated' timestamp normalized
        if "$MAINFRAME_RELEASE_PYTHON" -I -S -B - \
            "$REGISTRY" "$tmp_reg" <<'PYEOF'
import json, sys
def load(p):
    with open(p) as f:
        d = json.load(f)
    d.pop("generated", None)
    return d
committed = load(sys.argv[1])
fresh = load(sys.argv[2])
if committed == fresh:
    sys.exit(0)
# Report the actual differences to make CI failures diagnosable
c_stats, f_stats = committed.get("stats", {}), fresh.get("stats", {})
if c_stats != f_stats:
    print(f"STATS differ: committed={c_stats} fresh={f_stats}", file=sys.stderr)
c_libs, f_libs = committed.get("libraries", {}), fresh.get("libraries", {})
only_committed = sorted(set(c_libs) - set(f_libs))
only_fresh = sorted(set(f_libs) - set(c_libs))
if only_committed:
    print(f"libs only in committed: {only_committed[:10]}", file=sys.stderr)
if only_fresh:
    print(f"libs only in fresh: {only_fresh[:10]}", file=sys.stderr)
for lib in sorted(set(c_libs) & set(f_libs)):
    if c_libs[lib] != f_libs[lib]:
        cf, ff = c_libs[lib].get("functions", {}), f_libs[lib].get("functions", {})
        c_names = set(cf) if isinstance(cf, dict) else set(x.get("name") for x in cf)
        f_names = set(ff) if isinstance(ff, dict) else set(x.get("name") for x in ff)
        extra_c = sorted(c_names - f_names)[:5]
        extra_f = sorted(f_names - c_names)[:5]
        print(f"lib '{lib}' differs: only-committed-fns={extra_c} only-fresh-fns={extra_f}", file=sys.stderr)
        break
sys.exit(1)
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
    MAINFRAME_ROOT="$PROJECT_ROOT" \
        "$MAINFRAME_RELEASE_BASH" --noprofile --norc -p \
        "$GENERATOR" --output "$REGISTRY" >/dev/null 2>&1
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
fi

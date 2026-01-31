#!/usr/bin/env bash
# =============================================================================
# Generate the MAINFRAME Agent Intelligence Demo GIF
# =============================================================================
# Usage: ./run-demo.sh
# Requires: vhs (~/go/bin/vhs), ttyd (~/.local/bin/ttyd)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAINFRAME_ROOT="${MAINFRAME_ROOT:-$HOME/Documents/Projects/mainframe}"
VHS="${VHS:-$HOME/go/bin/vhs}"
TTYD="${TTYD:-$HOME/.local/bin/ttyd}"

# Verify dependencies
if [[ ! -x "$VHS" ]]; then
    echo "ERROR: vhs not found at $VHS"
    echo "Install: go install github.com/charmbracelet/vhs@latest"
    exit 1
fi

if [[ ! -x "$TTYD" ]]; then
    echo "ERROR: ttyd not found at $TTYD"
    echo "Install: see https://github.com/tsl0922/ttyd"
    exit 1
fi

# Ensure MAINFRAME_ROOT is exported for the tape
export MAINFRAME_ROOT
export PATH="$PATH:$(dirname "$VHS"):$(dirname "$TTYD")"

echo "=== MAINFRAME Agent Intelligence Demo Generator ==="
echo "MAINFRAME_ROOT: $MAINFRAME_ROOT"
echo "VHS: $VHS"
echo "TTYD: $TTYD"
echo ""

# Create output directory
mkdir -p "$MAINFRAME_ROOT/demos/gifs"

# Change to MAINFRAME root so relative paths in tape work
cd "$MAINFRAME_ROOT"

echo "Generating demo GIF..."
echo "This will take about 30-60 seconds..."
echo ""

"$VHS" "$SCRIPT_DIR/agent-intelligence.tape"

OUTPUT="$MAINFRAME_ROOT/demos/gifs/agent-intelligence.gif"

if [[ -f "$OUTPUT" ]]; then
    echo ""
    echo "SUCCESS! Demo generated:"
    echo "  $OUTPUT"
    echo ""
    echo "File size: $(du -h "$OUTPUT" | cut -f1)"

    # Copy to Watson Documents
    DEST_DIR="$HOME/Desktop/Watson_Documents/Client_Projects/GORDON/MAINFRAME"
    mkdir -p "$DEST_DIR"
    cp "$OUTPUT" "$DEST_DIR/"
    echo "Copied to: $DEST_DIR/agent-intelligence.gif"
else
    echo "ERROR: GIF was not generated"
    exit 1
fi

#!/usr/bin/env bash
# =============================================================================
# generate-host-adapters.sh - Generate thin host adapters from the one
# standard Agent Skill (skills/mainframe/SKILL.md), A++ Phase 1 deliverable 3.
#
# Every generated file starts with a GENERATED marker; edit the standard
# skill, not the outputs. Host-specific content is limited to frontmatter
# and file format; the body is inlined verbatim so hosts never drift.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$ROOT/skills/mainframe/SKILL.md"

[[ -f "$SRC" ]] || { echo "missing $SRC" >&2; exit 1; }

# Body = SKILL.md without the leading --- frontmatter --- block
BODY=$(awk 'BEGIN{fm=0; body=0}
  body { print; next }
  /^---[[:space:]]*$/ { fm++; if (fm==2) body=1; next }
' "$SRC")

MARKER="GENERATED from skills/mainframe/SKILL.md by scripts/generate-host-adapters.sh — edit the source, not this file"

write_file() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    cat > "$path"
    echo "  wrote ${path#$ROOT/}"
}

DESC="Use MAINFRAME bash runtime functions for safe agent shell work: JSON, validation, atomic file ops, structured output, and Agent Working Memory."

echo "Generating thin host adapters from skills/mainframe/SKILL.md"

# --- Codex -------------------------------------------------------------------
{
    printf '<!-- %s -->\n\n' "$MARKER"
    printf '# MAINFRAME\n\n%s\n' "$BODY"
} | write_file "$ROOT/skills/codex/AGENTS.md"

# --- Claude Code ---------------------------------------------------------------
{
    printf -- "---\nname: mainframe\ndescription: \"%s\"\n---\n\n" "$DESC"
    printf '<!-- %s -->\n%s\n' "$MARKER" "$BODY"
} | write_file "$ROOT/skills/claude-code/SKILL.md"

# --- Cursor (.mdc frontmatter) -------------------------------------------------
{
    printf -- "---\ndescription: %s\nglobs:\nalwaysApply: true\n---\n\n" "$DESC"
    printf '<!-- %s -->\n%s\n' "$MARKER" "$BODY"
} | write_file "$ROOT/skills/cursor/mainframe.mdc"

# --- Aider conventions -----------------------------------------------------------
{
    printf '<!-- %s -->\n\n# MAINFRAME conventions\n\n%s\n' "$MARKER" "$BODY"
} | write_file "$ROOT/skills/aider/CONVENTIONS.md"

# --- Google CLI / Kimi CLI / OpenCode (SKILL.md format) -------------------------
for host in google-cli kimi-cli opencode; do
    {
        printf -- "---\nname: mainframe\ndescription: \"%s\"\n---\n\n" "$DESC"
        printf '<!-- %s -->\n%s\n' "$MARKER" "$BODY"
    } | write_file "$ROOT/skills/$host/SKILL.md"
done

# --- GitHub Copilot / VS Code -----------------------------------------------------
{
    printf '<!-- %s -->\n%s\n' "$MARKER" "$BODY"
} | write_file "$ROOT/skills/copilot/copilot-instructions.md"

# --- JetBrains AI Assistant ---------------------------------------------------------
{
    printf '<!-- %s -->\n%s\n' "$MARKER" "$BODY"
} | write_file "$ROOT/skills/jetbrains/mainframe.md"

# --- Junie ---------------------------------------------------------------------------
{
    printf '<!-- %s -->\n%s\n' "$MARKER" "$BODY"
} | write_file "$ROOT/skills/junie/guidelines.md"

echo "Done. (skills/pi/SKILL.md is pi-specific and intentionally not generated.)"

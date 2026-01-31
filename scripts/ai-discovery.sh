#!/usr/bin/env bash
# =============================================================================
# MAINFRAME AI Discovery CLI
# =============================================================================
# Manages AI coding tool discovery for MAINFRAME capabilities.
#
# Usage:
#   mainframe ai-discovery setup    Set up discovery for all AI tools
#   mainframe ai-discovery status   Check discovery status
#   mainframe ai-discovery clean    Remove discovery configurations
# =============================================================================

set -euo pipefail

MAINFRAME_ROOT="${MAINFRAME_ROOT:-$HOME/.mainframe}"

# Source the AI discovery library
source "$MAINFRAME_ROOT/lib/ai_discovery.sh"

# =============================================================================
# MAIN
# =============================================================================

show_help() {
    cat << 'EOF'
MAINFRAME AI Discovery

Makes MAINFRAME capabilities automatically discoverable to AI coding tools
like Claude Code, OpenCode, Aider, Cursor, Gemini CLI, and Copilot CLI.

Usage:
  mainframe ai-discovery <command>

Commands:
  setup     Configure all AI tools to discover MAINFRAME
  status    Show current discovery configuration status
  clean     Remove all discovery configurations

Examples:
  mainframe ai-discovery setup    # Run after installing MAINFRAME
  mainframe ai-discovery status   # Check what's configured

What Gets Configured:
  • Universal: ~/.local/share/ai-capabilities/mainframe.md
  • Claude Code: ~/.claude/context/mainframe.md + skills symlink
  • Cursor: ~/.cursor/rules/mainframe.mdc
  • Aider: ~/.aider.conf.yml (adds read directive)
  • Shell: Environment markers (MAINFRAME_AI_ENABLED)

After setup, AI tools will automatically know MAINFRAME is available
when you work in ANY project - no manual reminders needed.
EOF
}

main() {
    local command="${1:-}"

    case "$command" in
        setup)
            mainframe_ai_discovery_setup
            ;;
        status)
            mainframe_ai_discovery_status
            ;;
        clean)
            mainframe_ai_discovery_clean
            ;;
        -h|--help|help|"")
            show_help
            ;;
        *)
            echo "Unknown command: $command"
            echo "Run 'mainframe ai-discovery --help' for usage"
            exit 1
            ;;
    esac
}

main "$@"

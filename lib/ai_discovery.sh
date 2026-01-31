#!/usr/bin/env bash
# =============================================================================
# MAINFRAME AI Discovery System
# =============================================================================
# Automatically makes MAINFRAME capabilities discoverable to AI coding tools
# (Claude Code, OpenCode, Aider, Cursor, Gemini CLI, Copilot CLI, etc.)
#
# Run: mainframe_ai_discovery_setup
# =============================================================================

# Ensure MAINFRAME_ROOT is set
MAINFRAME_ROOT="${MAINFRAME_ROOT:-$HOME/.mainframe}"

# Standard discovery locations
_MAINFRAME_AI_DISCOVERY_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/ai-capabilities"
_MAINFRAME_CLAUDE_CONTEXT_DIR="$HOME/.claude/context"
_MAINFRAME_CURSOR_RULES_DIR="$HOME/.cursor/rules"

# =============================================================================
# DISCOVERY FILE GENERATION
# =============================================================================

# Generate the universal AI capabilities file
_mainframe_generate_capabilities_file() {
    cat << 'CAPABILITIES'
# MAINFRAME Pure Bash Standard Library

**Auto-detected**: MAINFRAME v6.0+ is available in this environment.

## Quick Start

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

This gives you **4,000+ pure bash functions** across 117 libraries. Zero dependencies.

## When to Use MAINFRAME

Use MAINFRAME when writing ANY bash script. It replaces:
- `jq` → `json_object`, `json_array`, `json_get`, `json_merge`
- `sed` → `trim_string`, `replace_all`, `to_lower`, `to_upper`
- `awk` → `array_join`, `array_unique`, `array_filter`, `array_sort`
- `curl` parsing → `url_parse`, `http_get`, `http_post`
- `date` math → `now`, `date_add`, `format_relative`

## Key Function Categories

| Category | Functions | Example |
|----------|-----------|---------|
| **JSON** | `json_object`, `json_array`, `json_get` | `json_object "name=John" "age:number=30"` |
| **Strings** | `trim_string`, `to_lower`, `replace_all` | `trim_string "  hello  "` |
| **Arrays** | `array_join`, `array_unique`, `array_sort` | `array_join ", " "${arr[@]}"` |
| **Validation** | `validate_email`, `validate_path_safe` | `validate_email "user@test.com"` |
| **DateTime** | `now`, `now_iso`, `date_add` | `date_add $(now) "2d"` |
| **Git** | `git_branch`, `git_is_dirty` | `git_is_dirty && echo "changes"` |
| **HTTP** | `http_get`, `http_post` | `http_get "http://api.example.com"` |
| **Logging** | `log_info`, `log_error`, `success` | `log_info "Starting..."` |
| **AWM** | `awm_init`, `awm_checkpoint` | `awm_checkpoint "key" "value"` |

## Rules

1. ALWAYS source `common.sh` at the top of bash scripts
2. NEVER use jq/sed/awk when MAINFRAME has the function
3. Use `validate_path_safe` for any user-provided paths
4. Reference: `~/.mainframe/CHEATSHEET.md` for full signatures

## Full Reference

See `${MAINFRAME_ROOT:-$HOME/.mainframe}/CHEATSHEET.md` for all 4,000+ function signatures.
CAPABILITIES
}

# Generate context snippet for Claude Code
_mainframe_generate_claude_context() {
    cat << 'CONTEXT'
# MAINFRAME Bash Library (Auto-Detected)

MAINFRAME v6.0+ is installed at `$MAINFRAME_ROOT`. When writing bash scripts:

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

**Key functions**: `json_object`, `json_get`, `trim_string`, `validate_email`, `validate_path_safe`, `http_get`, `log_info`, `success`, `uuid`, `now_iso`, `git_branch`, `awm_init`, `awm_checkpoint`

**Never use**: jq, sed, awk, cat for things MAINFRAME handles.

**Reference**: `~/.mainframe/CHEATSHEET.md`
CONTEXT
}

# =============================================================================
# SETUP FUNCTIONS
# =============================================================================

# Setup universal AI discovery (works with any AI tool)
mainframe_ai_discovery_setup_universal() {
    local discovery_dir="$_MAINFRAME_AI_DISCOVERY_DIR"

    mkdir -p "$discovery_dir"

    # Write capabilities file
    _mainframe_generate_capabilities_file > "$discovery_dir/mainframe.md"

    # Create marker file for quick detection
    cat > "$discovery_dir/mainframe.json" << EOF
{
    "name": "mainframe",
    "version": "6.0",
    "type": "bash-library",
    "root": "$MAINFRAME_ROOT",
    "functions": 4000,
    "libraries": 117,
    "cheatsheet": "$MAINFRAME_ROOT/CHEATSHEET.md",
    "source_line": "source \"\${MAINFRAME_ROOT:-\$HOME/.mainframe}/lib/common.sh\""
}
EOF

    echo "✓ Universal AI discovery: $discovery_dir/mainframe.md"
}

# Setup Claude Code global context
mainframe_ai_discovery_setup_claude() {
    local context_dir="$_MAINFRAME_CLAUDE_CONTEXT_DIR"

    mkdir -p "$context_dir"

    # Create context file
    _mainframe_generate_claude_context > "$context_dir/mainframe.md"

    # Symlink full skill if skills directory exists
    local skills_dir="$HOME/.claude/skills"
    if [[ -d "$skills_dir" ]] && [[ ! -L "$skills_dir/mainframe-bash" ]]; then
        ln -sf "$MAINFRAME_ROOT/skills/claude-code" "$skills_dir/mainframe-bash" 2>/dev/null || true
    fi

    echo "✓ Claude Code context: $context_dir/mainframe.md"
}

# Setup Cursor global rules
mainframe_ai_discovery_setup_cursor() {
    local rules_dir="$_MAINFRAME_CURSOR_RULES_DIR"

    mkdir -p "$rules_dir"

    # Copy Cursor rules file
    if [[ -f "$MAINFRAME_ROOT/skills/cursor/mainframe.mdc" ]]; then
        cp "$MAINFRAME_ROOT/skills/cursor/mainframe.mdc" "$rules_dir/"
        echo "✓ Cursor rules: $rules_dir/mainframe.mdc"
    fi
}

# Setup Aider global config
mainframe_ai_discovery_setup_aider() {
    local aider_config="$HOME/.aider.conf.yml"
    local conventions="$MAINFRAME_ROOT/skills/aider/CONVENTIONS.md"

    if [[ -f "$conventions" ]]; then
        # Check if already configured
        if [[ -f "$aider_config" ]] && grep -q "mainframe" "$aider_config" 2>/dev/null; then
            echo "✓ Aider already configured"
            return 0
        fi

        # Add to config
        echo "read: $conventions" >> "$aider_config"
        echo "✓ Aider config: $aider_config"
    fi
}

# Setup environment markers in shell profile
mainframe_ai_discovery_setup_shell() {
    local shell_config=""

    # Detect shell config
    case "${SHELL:-/bin/bash}" in
        */bash)
            shell_config="$HOME/.bashrc"
            [[ ! -f "$shell_config" ]] && shell_config="$HOME/.bash_profile"
            ;;
        */zsh)
            shell_config="$HOME/.zshrc"
            ;;
        */fish)
            shell_config="$HOME/.config/fish/config.fish"
            ;;
    esac

    if [[ -z "$shell_config" ]] || [[ ! -f "$shell_config" ]]; then
        echo "⚠ Could not detect shell config"
        return 1
    fi

    # Check if already configured
    if grep -q "MAINFRAME_AI_ENABLED" "$shell_config" 2>/dev/null; then
        echo "✓ Shell already configured"
        return 0
    fi

    # Add AI discovery markers
    cat >> "$shell_config" << 'SHELL_BLOCK'

# MAINFRAME AI Discovery Markers
# These help AI coding tools detect MAINFRAME availability
export MAINFRAME_AI_ENABLED=1
export MAINFRAME_VERSION="6.0"
export MAINFRAME_CAPABILITIES="json,strings,arrays,validation,datetime,http,git,awm,ipc"
SHELL_BLOCK

    echo "✓ Shell markers: $shell_config"
}

# =============================================================================
# MAIN SETUP COMMAND
# =============================================================================

# Run all discovery setups
mainframe_ai_discovery_setup() {
    echo "Setting up MAINFRAME AI discovery..."
    echo ""

    mainframe_ai_discovery_setup_universal
    mainframe_ai_discovery_setup_claude
    mainframe_ai_discovery_setup_cursor
    mainframe_ai_discovery_setup_aider
    mainframe_ai_discovery_setup_shell

    echo ""
    echo "✓ MAINFRAME AI discovery complete!"
    echo ""
    echo "AI coding tools will now automatically detect MAINFRAME capabilities."
    echo "Restart your shell or run: source ~/.bashrc"
}

# Check discovery status
mainframe_ai_discovery_status() {
    echo "MAINFRAME AI Discovery Status"
    echo "=============================="
    echo ""

    # Universal
    if [[ -f "$_MAINFRAME_AI_DISCOVERY_DIR/mainframe.md" ]]; then
        echo "✓ Universal: $_MAINFRAME_AI_DISCOVERY_DIR/mainframe.md"
    else
        echo "✗ Universal: not configured"
    fi

    # Claude Code
    if [[ -f "$_MAINFRAME_CLAUDE_CONTEXT_DIR/mainframe.md" ]]; then
        echo "✓ Claude Code: $_MAINFRAME_CLAUDE_CONTEXT_DIR/mainframe.md"
    else
        echo "✗ Claude Code: not configured"
    fi

    # Cursor
    if [[ -f "$_MAINFRAME_CURSOR_RULES_DIR/mainframe.mdc" ]]; then
        echo "✓ Cursor: $_MAINFRAME_CURSOR_RULES_DIR/mainframe.mdc"
    else
        echo "✗ Cursor: not configured"
    fi

    # Aider
    if [[ -f "$HOME/.aider.conf.yml" ]] && grep -q "mainframe" "$HOME/.aider.conf.yml" 2>/dev/null; then
        echo "✓ Aider: ~/.aider.conf.yml"
    else
        echo "✗ Aider: not configured"
    fi

    # Shell
    if [[ -n "$MAINFRAME_AI_ENABLED" ]]; then
        echo "✓ Shell: MAINFRAME_AI_ENABLED=$MAINFRAME_AI_ENABLED"
    else
        echo "✗ Shell: markers not active (restart shell)"
    fi

    echo ""
}

# Remove all discovery configurations
mainframe_ai_discovery_clean() {
    echo "Removing MAINFRAME AI discovery configurations..."

    rm -rf "$_MAINFRAME_AI_DISCOVERY_DIR"
    rm -f "$_MAINFRAME_CLAUDE_CONTEXT_DIR/mainframe.md"
    rm -f "$_MAINFRAME_CURSOR_RULES_DIR/mainframe.mdc"
    rm -f "$HOME/.claude/skills/mainframe-bash"

    # Remove from aider config
    if [[ -f "$HOME/.aider.conf.yml" ]]; then
        sed -i '/mainframe/d' "$HOME/.aider.conf.yml" 2>/dev/null || true
    fi

    echo "✓ Cleaned. Note: Shell markers remain (manual removal if needed)"
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f mainframe_ai_discovery_setup
export -f mainframe_ai_discovery_status
export -f mainframe_ai_discovery_clean

# =============================================================================
# MAINFRAME Agent Intelligence Demo
# =============================================================================
# Demonstrates how AI agents use MAINFRAME for strategic codebase analysis
# Run setup first: bash demos/tapes/mainframe/setup-demo-project.sh
# =============================================================================

Output demos/gifs/agent-intelligence.gif

Require ttyd
Require bash

Set Shell "bash"
Set FontFamily "JetBrains Mono"
Set FontSize 15
Set LineHeight 1.3
Set Width 1100
Set Height 650
Set TypingSpeed 35ms
Set Padding 20
Set WindowBar Colorful
Set WindowBarSize 40

# Catppuccin Mocha theme
Set Theme {
    "name": "Catppuccin Mocha",
    "black": "#45475a",
    "red": "#f38ba8",
    "green": "#a6e3a1",
    "yellow": "#f9e2af",
    "blue": "#89b4fa",
    "magenta": "#cba6f7",
    "cyan": "#94e2d5",
    "white": "#cdd6f4",
    "brightBlack": "#585b70",
    "brightRed": "#f38ba8",
    "brightGreen": "#a6e3a1",
    "brightYellow": "#f9e2af",
    "brightBlue": "#89b4fa",
    "brightMagenta": "#cba6f7",
    "brightCyan": "#94e2d5",
    "brightWhite": "#a6adc8",
    "background": "#1e1e2e",
    "foreground": "#cdd6f4",
    "selection": "#45475a",
    "cursor": "#f5e0dc"
}

# =============================================================================
# SETUP: Silent project creation
# =============================================================================

Hide
Type "export MAINFRAME_ROOT=$HOME/Documents/Projects/mainframe"
Enter
Type "bash $MAINFRAME_ROOT/demos/tapes/mainframe/setup-demo-project.sh /tmp/mystery-saas 2>/dev/null"
Enter
Sleep 500ms
Type "cd /tmp/mystery-saas"
Enter
Type "export PS1='\\[\\033[1;34m\\]agent\\[\\033[0m\\] \\[\\033[1;32m\\]mystery-saas\\[\\033[0m\\] $ '"
Enter
Type "clear"
Enter
Show
Sleep 300ms

# =============================================================================
# SCENE 1: Agent Lands in Unknown Codebase
# =============================================================================

Type "# AI agent lands in unfamiliar codebase..."
Enter
Sleep 700ms

Type "ls -la"
Enter
Sleep 1s

Type ""
Enter
Type "# What is this? TypeScript? Python? What framework?"
Enter
Sleep 600ms

Type "# Old way: grep through files, hope for the best..."
Enter
Sleep 500ms

Type "head -15 package.json"
Enter
Sleep 1.2s

Type ""
Enter
Type "# Some info, but incomplete. Let's try MAINFRAME..."
Enter
Sleep 800ms

# =============================================================================
# SCENE 2: Project Intelligence
# =============================================================================

Type ""
Enter
Type 'source "$MAINFRAME_ROOT/lib/common.sh"'
Enter
Sleep 300ms

Type ""
Enter
Type "# One command reveals EVERYTHING:"
Enter
Sleep 400ms

Type "project_detect . | python3 -m json.tool"
Enter
Sleep 1.8s

Type ""
Enter
Type "# Instant: TypeScript + Next.js + bun + vitest"
Enter
Sleep 700ms

Type "# What commands can I run?"
Enter
Sleep 400ms

Type "project_commands . | python3 -m json.tool"
Enter
Sleep 1.5s

# =============================================================================
# SCENE 3: Token Cost Analysis (Strategic Intelligence)
# =============================================================================

Type ""
Enter
Type "# Now the STRATEGIC part..."
Enter
Sleep 600ms

Type "# AI context windows have limits. Read smart, not everything."
Enter
Sleep 700ms

Type ""
Enter
Type "# Estimate token costs WITHOUT reading files:"
Enter
Sleep 500ms

Type 'printf "\\n%-35s %8s\\n" "FILE" "TOKENS"'
Enter
Type 'printf "%s\\n" "----------------------------------------"'
Enter
Type 'for f in src/lib/*.ts src/app/*.tsx src/components/*.tsx; do'
Enter
Type '  [ -f "$f" ] && printf "%-35s %8d\\n" "$f" "$(context_file_tokens "$f")"'
Enter
Type 'done'
Enter
Sleep 2.2s

# =============================================================================
# SCENE 4: Strategic Reading Plan
# =============================================================================

Type ""
Enter
Type "# With 2000 token budget, which files fit?"
Enter
Sleep 600ms

Type 'find src -name "*.ts" -o -name "*.tsx" | context_batch_files 2000'
Enter
Sleep 1.5s

Type ""
Enter
Type "# Get a structured reading plan:"
Enter
Sleep 400ms

Type 'context_read_plan 2500 src/lib/*.ts src/app/*.tsx | python3 -m json.tool'
Enter
Sleep 2s

# =============================================================================
# SCENE 5: Finale
# =============================================================================

Type ""
Enter
Type "# MAINFRAME: AI agents work SMARTER, not harder"
Enter
Sleep 800ms

Type "# 2000+ functions | Zero dependencies | Pure Bash"
Enter
Sleep 700ms

Type ""
Enter
Type "echo 'github.com/gtwatts/mainframe'"
Enter
Sleep 2.5s

# End
Sleep 500ms

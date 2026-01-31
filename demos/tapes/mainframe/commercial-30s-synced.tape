# =============================================================================
# MAINFRAME 30-Second Commercial - Synced with Voiceover
# =============================================================================
# Duration: ~22 seconds (matches voiceover_30sec_v3.wav)
# Narration timing synchronized with terminal actions
# =============================================================================

Output demos/gifs/commercial-30s-synced.gif

Require ttyd
Require bash

Set Shell "bash"
Set FontFamily "JetBrains Mono"
Set FontSize 16
Set LineHeight 1.3
Set Width 1100
Set Height 600
Set TypingSpeed 30ms
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
# SETUP: Silent initialization
# =============================================================================

Hide
Type "export MAINFRAME_ROOT=$HOME/Documents/Projects/mainframe"
Enter
Type "bash $MAINFRAME_ROOT/demos/tapes/mainframe/setup-demo-project.sh /tmp/mystery-project 2>/dev/null"
Enter
Sleep 500ms
Type "cd /tmp/mystery-project"
Enter
Type "export PS1='\\[\\033[1;34m\\]agent\\[\\033[0m\\] \\[\\033[1;33m\\]???\\[\\033[0m\\] $ '"
Enter
Type "clear"
Enter
Show

# =============================================================================
# 0-3s: "Your AI agent just landed in an unfamiliar codebase"
# =============================================================================

Type "# AI agent lands in unfamiliar codebase..."
Enter
Sleep 400ms

Type "cd /tmp/mystery-project && ls -la"
Enter
Sleep 2s

# =============================================================================
# 3-5s: "What does it do? Panic? NO. It uses MAINFRAME"
# =============================================================================

Type ""
Enter
Type "# Old way: grep and hope..."
Enter
Sleep 600ms

Type 'source "$MAINFRAME_ROOT/lib/common.sh"'
Enter
Sleep 800ms

# =============================================================================
# 5-9s: "Nineteen hundred pure bash functions. Zero dependencies"
# =============================================================================

Type ""
Enter
Type "# 1900+ functions, zero dependencies:"
Enter
Sleep 300ms

Type 'json_object "status=ready" "functions:number=1900"'
Enter
Sleep 800ms

Type 'log_info "MAINFRAME loaded"'
Enter
Sleep 800ms

Type 'log_success "Zero external dependencies"'
Enter
Sleep 700ms

# =============================================================================
# 9-14s: "Project detection. Token budgeting. Strategic file analysis"
# =============================================================================

Type ""
Enter
Type "# Instant project intelligence:"
Enter
Sleep 300ms

Type "project_detect . | python3 -m json.tool | head -12"
Enter
Sleep 2s

Type ""
Enter
Type "# Token budgeting for AI context:"
Enter
Sleep 300ms

Type 'context_file_tokens src/index.ts'
Enter
Sleep 1s

Type 'context_file_tokens src/app/page.tsx'
Enter
Sleep 1s

# =============================================================================
# 14-18s: "All in one line of code"
# =============================================================================

Type ""
Enter
Type "# Strategic file analysis in one line:"
Enter
Sleep 300ms

Type 'find src -name "*.ts" | head -5 | while read f; do printf "%-30s %5d tokens\\n" "$f" "$(context_file_tokens "$f")"; done'
Enter
Sleep 2s

# =============================================================================
# 18-22s: "MAINFRAME. Star us on GitHub"
# =============================================================================

Type ""
Enter
Type "# MAINFRAME - AI agents work smarter"
Enter
Sleep 600ms

Type ""
Enter
Type "echo 'github.com/gtwatts/mainframe'"
Enter
Sleep 2s

# End
Sleep 500ms

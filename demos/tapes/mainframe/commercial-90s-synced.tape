# =============================================================================
# MAINFRAME 90-Second Commercial - Synced with Voiceover
# =============================================================================
# Duration: ~90 seconds
# Narration timing synchronized with terminal actions
# =============================================================================

Output demos/gifs/commercial-90s-synced.gif

Require ttyd
Require bash

Set Shell "bash"
Set FontFamily "JetBrains Mono"
Set FontSize 16
Set LineHeight 1.3
Set Width 1100
Set Height 650
Set TypingSpeed 25ms
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
# [0-15s - HOOK]: "Your AI agent just landed... It uses MAINFRAME."
# Agent lands in unknown codebase, looks confused
# =============================================================================

Type "# AI Agent lands in unfamiliar codebase..."
Enter
Sleep 500ms

Type "pwd"
Enter
Sleep 800ms

Type "ls -la"
Enter
Sleep 2s

Type ""
Enter
Type "# What is this project? Node? Python? Rust?"
Enter
Sleep 1s

Type "cat package.json 2>/dev/null | head -5 || echo 'No package.json'"
Enter
Sleep 1.5s

Type ""
Enter
Type "# I need answers. Fast."
Enter
Sleep 1s

# Total: ~8s of action, narration fills to 15s

# =============================================================================
# [15-30s - PROBLEM]: "Every AI coding agent runs bash... making rookie mistakes"
# The old way is broken - grep attempts, incomplete info
# =============================================================================

Type ""
Enter
Type "# The OLD way: grep and hope..."
Enter
Sleep 800ms

Type "grep -r 'import' src/ 2>/dev/null | head -3"
Enter
Sleep 1.5s

Type "head -20 src/index.ts 2>/dev/null || head -20 src/main.py 2>/dev/null"
Enter
Sleep 1.5s

Type ""
Enter
Type "# Parsing JSON manually..."
Enter
Sleep 600ms

Type "cat package.json | grep 'name'"
Enter
Sleep 1s

Type ""
Enter
Type "# This is slow. Error-prone. BROKEN."
Enter
Sleep 1s

Type "# There has to be a better way..."
Enter
Sleep 1.5s

# Total: ~9s of action

# =============================================================================
# [30-45s - SOLUTION]: "MAINFRAME gives your agent superpowers..."
# MAINFRAME introduction - the magic moment
# =============================================================================

Type ""
Enter
Sleep 500ms

Type "# Enter: MAINFRAME"
Enter
Sleep 800ms

Type 'source "$MAINFRAME_ROOT/lib/common.sh"'
Enter
Sleep 1.5s

Type ""
Enter
Type "# 1,900+ pure bash functions. Zero dependencies."
Enter
Sleep 800ms

Type 'log_info "MAINFRAME loaded successfully"'
Enter
Sleep 1s

Type 'log_success "77 libraries ready"'
Enter
Sleep 1s

Type ""
Enter
Type "# All in ONE line of code:"
Enter
Sleep 500ms

Type 'json_object "agent=claude" "status=powered" "tools:number=1900"'
Enter
Sleep 1.5s

# Total: ~9s of action

# =============================================================================
# [45-60s - DEMO HIGHLIGHT]: "Watch this. Unknown codebase..."
# Project detection magic - the wow moment
# =============================================================================

Type ""
Enter
Type "# Watch this. Unknown codebase? MAINFRAME knows:"
Enter
Sleep 800ms

Type "project_detect . | python3 -m json.tool"
Enter
Sleep 3s

Type ""
Enter
Type "# Token budgeting for AI context windows:"
Enter
Sleep 600ms

Type 'context_file_tokens src/index.ts'
Enter
Sleep 1s

Type 'context_file_tokens src/app/page.tsx'
Enter
Sleep 1s

Type 'context_file_tokens package.json'
Enter
Sleep 1s

Type ""
Enter
Type "# Strategic file reading plan:"
Enter
Sleep 500ms

Type 'context_read_plan 50000 src/*.ts src/*.tsx 2>/dev/null | python3 -m json.tool | head -15'
Enter
Sleep 2.5s

# Total: ~12s of action

# =============================================================================
# [60-75s - FEATURES]: "JSON without jq. HTTP in pure bash. Git workflows..."
# Feature showcase - rapid fire demos
# =============================================================================

Type ""
Enter
Type "# JSON without jq:"
Enter
Sleep 400ms

Type 'json_object "name=MAINFRAME" "version=5.0" "pure_bash:bool=true"'
Enter
Sleep 1.2s

Type 'json_array "strings" "arrays" "validation" "http" "git"'
Enter
Sleep 1.2s

Type ""
Enter
Type "# Git intelligence:"
Enter
Sleep 400ms

Type 'git_branch 2>/dev/null || echo "main"'
Enter
Sleep 800ms

Type 'git_is_dirty && echo "Uncommitted changes" || echo "Clean working tree"'
Enter
Sleep 1s

Type ""
Enter
Type "# Input validation:"
Enter
Sleep 400ms

Type 'validate_email "agent@mainframe.dev" && echo "Valid email"'
Enter
Sleep 1s

Type 'validate_url "https://github.com/gtwatts/mainframe" && echo "Valid URL"'
Enter
Sleep 1s

Type ""
Enter
Type "# Progress tracking:"
Enter
Sleep 400ms

Type 'for i in 1 2 3 4 5; do progress_bar $i 5 "Loading"; sleep 0.2; done'
Enter
Sleep 1.5s

# Total: ~10s of action

# =============================================================================
# [75-90s - CTA]: "MAINFRAME. Because your AI agent deserves better..."
# Closing - memorable ending
# =============================================================================

Type ""
Enter
Type "# =================================================="
Enter
Sleep 300ms

Type "# MAINFRAME: AI agents work smarter, not harder"
Enter
Sleep 500ms

Type "# =================================================="
Enter
Sleep 1s

Type ""
Enter
Type 'log_success "1,900+ functions"'
Enter
Sleep 800ms

Type 'log_success "77 libraries"'
Enter
Sleep 800ms

Type 'log_success "Zero dependencies"'
Enter
Sleep 800ms

Type 'log_success "Pure bash"'
Enter
Sleep 1s

Type ""
Enter
Type "echo ''"
Enter

Type "echo '  github.com/gtwatts/mainframe'"
Enter
Sleep 1s

Type "echo ''"
Enter

Type "echo '  Star us. Your AI agent will thank you.'"
Enter
Sleep 3s

# Hold on final frame
Sleep 2s

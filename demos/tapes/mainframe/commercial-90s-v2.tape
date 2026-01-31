# =============================================================================
# MAINFRAME 90-Second Commercial v2 - With Actual Feature Demos
# =============================================================================
# Duration: ~90 seconds
# Improvements: Real feature demos, ASCII art logo, faster typing for demos
# =============================================================================

Output demos/gifs/commercial-90s-v2.gif

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
# [0-12s - HOOK]: Agent lands in unknown codebase
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

# =============================================================================
# [12-25s - PROBLEM]: The old way doesn't work
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

# =============================================================================
# [25-40s - SOLUTION]: MAINFRAME introduction
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

# =============================================================================
# [40-55s - DEMO]: Project detection magic
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

Type 'context_file_tokens package.json'
Enter
Sleep 1s

Type ""
Enter
Type "# Strategic file reading plan:"
Enter
Sleep 500ms

Type 'context_read_plan 50000 src/*.ts src/*.tsx 2>/dev/null | python3 -m json.tool | head -12'
Enter
Sleep 2.5s

# =============================================================================
# [55-70s - FEATURES]: Actual demos with visible output
# Fast typing (20ms) for this section
# =============================================================================

Set TypingSpeed 20ms

Type ""
Enter
Type "# ========== FEATURE SHOWCASE =========="
Enter
Sleep 500ms

# JSON without jq
Type ""
Enter
Type "# JSON without jq:"
Enter
Sleep 300ms

Type 'json_object "name=MAINFRAME" "version=5.0" "functions:number=1900"'
Enter
Sleep 1.2s

# Git workflows
Type ""
Enter
Type "# Git workflows:"
Enter
Sleep 300ms

Type 'echo "Branch: $(git_branch 2>/dev/null || echo main)"'
Enter
Sleep 800ms

Type 'git_is_dirty && echo "Has uncommitted changes" || echo "Clean"'
Enter
Sleep 800ms

# Validation
Type ""
Enter
Type "# Validation:"
Enter
Sleep 300ms

Type 'validate_email "dev@mainframe.sh" && log_success "Valid email"'
Enter
Sleep 800ms

Type 'validate_url "https://github.com/gtwatts/mainframe" && log_success "Valid URL"'
Enter
Sleep 800ms

# Progress bars
Type ""
Enter
Type "# Progress bars:"
Enter
Sleep 300ms

Type 'for i in $(seq 1 100); do progress_bar $i 100 "Installing"; sleep 0.02; done'
Enter
Sleep 2.5s

# Colored logging
Type ""
Enter
Type "# Colored logging:"
Enter
Sleep 300ms

Type 'log_info "Detecting project type..."'
Enter
Sleep 500ms

Type 'log_success "Found: TypeScript + Next.js"'
Enter
Sleep 500ms

Type 'log_warn "Large file detected: bundle.js"'
Enter
Sleep 500ms

Type 'log_error "Missing dependency: prisma"'
Enter
Sleep 800ms

# =============================================================================
# [70-90s - CTA/OUTRO]: ASCII art logo + GitHub URL
# =============================================================================

Set TypingSpeed 25ms

Type ""
Enter
Sleep 500ms

Type "clear"
Enter
Sleep 300ms

# ASCII art logo
Type "cat << 'EOF'"
Enter
Type "+======================================================================+"
Enter
Type "|  ___  ___  ___  _____ _   _ ______ _____   ___  ___  ___ _____       |"
Enter
Type "|  |  \\/  | / _ \\|_   _| \\ | ||  ___|  __ \\ / _ \\ |  \\/  ||  ___|      |"
Enter
Type "|  | .  . |/ /_\\ \\ | | |  \\| || |_  | |__) / /_\\ \\| .  . || |__        |"
Enter
Type "|  | |\\/| ||  _  | | | | . \\` ||  _| |  _  /|  _  || |\\/| ||  __|       |"
Enter
Type "|  | |  | || | | |_| |_| |\\  || |   | | \\ \\| | | || |  | || |___       |"
Enter
Type "|  \\_|  |_/\\_| |_/\\___/\\_| \\_/\\_|   \\_|  \\_\\_| |_/\\_|  |_/\\____/       |"
Enter
Type "|                                                                      |"
Enter
Type "|     AI agents control computers through bash.                        |"
Enter
Type "|     MAINFRAME makes that safe, accurate, and efficient.              |"
Enter
Type "+======================================================================+"
Enter
Type ""
Enter
Type "                   github.com/gtwatts/mainframe"
Enter
Type ""
Enter
Type "EOF"
Enter
Sleep 5s

# Hold on final frame
Sleep 2s

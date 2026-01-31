Output demos/captures/features-scene.mp4
Set Shell "bash"
Set FontFamily "JetBrains Mono"
Set FontSize 16
Set Width 1280
Set Height 720
Set Framerate 30

# GitHub dark theme
Set Theme {
    "background": "#0d1117",
    "foreground": "#c9d1d9",
    "black": "#484f58",
    "red": "#ff7b72",
    "green": "#3fb950",
    "yellow": "#d29922",
    "blue": "#58a6ff",
    "magenta": "#bc8cff",
    "cyan": "#39c5cf",
    "white": "#b1bac4"
}

Hide
Type "export MAINFRAME_ROOT=$HOME/.mainframe"
Enter
Type "source $MAINFRAME_ROOT/lib/common.sh"
Enter
Type "cd /tmp/mystery-project"
Enter
Type "export PS1='\\[\\033[1;32m\\]agent\\[\\033[0m\\] \\[\\033[1;34m\\]mystery-project\\[\\033[0m\\] $ '"
Enter
Type "clear"
Enter
Show
Sleep 500ms

Type "# Progress bars:"
Enter
Sleep 400ms
Type 'for i in {1..100}; do progress_bar $i 100 "Processing"; sleep 0.03; done'
Enter
Sleep 4s
Type ""
Enter
Type "# Colored logging:"
Enter
Sleep 400ms
Type 'log_info "Starting deployment..."'
Enter
Sleep 300ms
Type 'log_success "Build complete!"'
Enter
Sleep 300ms
Type 'log_warn "Cache invalidated"'
Enter
Sleep 300ms
Type 'log_error "Connection failed" 2>&1'
Enter
Sleep 800ms

Output demos/captures/demo-scene.mp4
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

Type "# Token budgeting - read SMART, not everything"
Enter
Sleep 600ms
Type ""
Enter
Type "# Estimate tokens WITHOUT reading files:"
Enter
Sleep 400ms
Type 'for f in src/*.ts; do printf "%-30s %6d tokens\\n" "$f" "$(context_file_tokens "$f")"; done'
Enter
Sleep 1.5s
Type ""
Enter
Type "# Build a reading plan that FITS your context:"
Enter
Sleep 400ms
Type 'context_read_plan 5000 src/*.ts | python3 -m json.tool'
Enter
Sleep 2s

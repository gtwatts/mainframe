Output demos/captures/problem-scene.mp4
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

Type "# The OLD way: grep and pray..."
Enter
Sleep 600ms
Type "grep -r 'import' . | head -20"
Enter
Sleep 1.5s
Type ""
Enter
Type "# Which files matter? No idea..."
Enter
Sleep 500ms
Type "wc -l *.ts *.tsx 2>/dev/null | tail -5"
Enter
Sleep 1s
Type "# Wasting tokens on files that don't matter"
Enter
Sleep 800ms

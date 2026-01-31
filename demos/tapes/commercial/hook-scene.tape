Output demos/captures/hook-scene.mp4
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
Type "cd /tmp && mkdir -p mystery-project && cd mystery-project"
Enter
Type "export PS1='\\[\\033[1;32m\\]agent\\[\\033[0m\\] \\[\\033[1;34m\\]mystery-project\\[\\033[0m\\] $ '"
Enter
Type "clear"
Enter
Show
Sleep 500ms

Type "# Agent lands in unfamiliar codebase..."
Enter
Sleep 800ms
Type "ls -la"
Enter
Sleep 1s
Type ""
Enter
Type "# What IS this project?"
Enter
Sleep 500ms
Type "project_detect . | python3 -m json.tool"
Enter
Sleep 2s

Output demos/captures/solution-scene.mp4
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

Type "# MAINFRAME: 1900+ pure bash functions"
Enter
Sleep 600ms
Type ""
Enter
Type "# JSON without jq:"
Enter
Sleep 400ms
Type 'json_object "name=MAINFRAME" "version=5.0" "functions:number=1900"'
Enter
Sleep 1.2s
Type ""
Enter
Type "# Validation:"
Enter
Sleep 400ms
Type 'validate_email "agent@mainframe.dev" && echo "✓ Valid"'
Enter
Sleep 800ms
Type 'validate_url "https://github.com/gtwatts/mainframe" && echo "✓ Valid"'
Enter
Sleep 800ms

Output demos/gifs/features-v2/json.gif
Set Shell "bash"
Set FontFamily "JetBrains Mono"
Set FontSize 20
Set Width 1000
Set Height 450
Set TypingSpeed 40ms
Set Padding 30
Set Theme {
    "background": "#0d1117",
    "foreground": "#c9d1d9",
    "green": "#3fb950",
    "red": "#f85149",
    "yellow": "#d29922",
    "cyan": "#58a6ff"
}

Hide
Type "source $HOME/Documents/Projects/mainframe/lib/common.sh"
Enter
Type "clear"
Enter
Show
Sleep 500ms

# Title
Type "echo '═══════════════════════════════════════════'"
Enter
Type "echo '         MAINFRAME: JSON without jq        '"
Enter
Type "echo '═══════════════════════════════════════════'"
Enter
Sleep 1s

Type ""
Enter
Type "# Create a JSON object in pure bash"
Enter
Sleep 500ms

Type 'json_object "name=MAINFRAME" "version=5.0" "pure_bash:bool=true" "functions:number=1900"'
Enter
Sleep 2s

Type ""
Enter
Type "# Create a JSON array"
Enter
Sleep 500ms

Type 'json_array "project_detect" "context_budget" "validate_email" "http_get"'
Enter
Sleep 2s

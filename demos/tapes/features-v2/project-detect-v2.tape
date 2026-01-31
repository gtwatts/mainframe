Output demos/gifs/features-v2/project-detect.gif
Set Shell "bash"
Set FontFamily "JetBrains Mono"
Set FontSize 18
Set Width 1000
Set Height 600
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
Type "echo '       MAINFRAME: Project Intelligence     '"
Enter
Type "echo '═══════════════════════════════════════════'"
Enter
Sleep 1s

Type ""
Enter
Type "# One command reveals everything about this codebase"
Enter
Sleep 500ms

Type "project_detect . | python3 -m json.tool"
Enter
Sleep 4s

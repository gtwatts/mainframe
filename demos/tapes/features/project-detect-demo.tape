Output demos/gifs/features/project-detect.gif

Set Shell "bash"
Set FontSize 18
Set Width 1000
Set Height 600
Set TypingSpeed 50ms
Set Theme { "background": "#1e1e2e", "foreground": "#cdd6f4" }

Hide
Type "source $HOME/Documents/Projects/mainframe/lib/common.sh"
Enter
Sleep 200ms
Type "clear"
Enter
Show
Sleep 500ms

Type "# MAINFRAME Project Detection"
Enter
Sleep 1s

Type "cd ~/Documents/Projects/mainframe"
Enter
Sleep 500ms

Type "project_detect . | python3 -m json.tool"
Enter
Sleep 4s

Type ""
Enter
Sleep 2s

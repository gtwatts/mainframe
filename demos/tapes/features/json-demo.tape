Output demos/gifs/features/json.gif

Set Shell "bash"
Set FontSize 18
Set Width 900
Set Height 500
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

Type "# MAINFRAME JSON Functions (Pure Bash)"
Enter
Sleep 1s

Type 'json_object "name=MAINFRAME" "version=5.0" "pure_bash:bool=true"'
Enter
Sleep 2.5s

Type 'json_array "project_detect" "context_budget" "validate_email"'
Enter
Sleep 2.5s

Type 'json_object "libs:number=77" "functions:number=1900" | json_pretty'
Enter
Sleep 3s

Type ""
Enter
Sleep 1s

Output demos/gifs/features/progress-bar.gif

Set Shell "bash"
Set FontSize 18
Set Width 900
Set Height 400
Set TypingSpeed 0ms
Set Theme { "background": "#1e1e2e", "foreground": "#cdd6f4" }

Hide
Type "source $HOME/Documents/Projects/mainframe/lib/common.sh"
Enter
Sleep 200ms
Type "clear"
Enter
Show
Sleep 500ms

Type "# MAINFRAME Progress Bars"
Enter
Sleep 1s

Type 'for i in $(seq 0 5 100); do printf "\\rInstalling: "; progress_bar $i 100 40; sleep 0.1; done; echo'
Enter
Sleep 12s

Type ""
Enter
Sleep 2s

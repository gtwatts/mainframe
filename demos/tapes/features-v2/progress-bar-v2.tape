Output demos/gifs/features-v2/progress-bar.gif
Set Shell "bash"
Set FontFamily "JetBrains Mono"
Set FontSize 20
Set Width 1000
Set Height 400
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
Type "echo '         MAINFRAME Progress Bars           '"
Enter
Type "echo '═══════════════════════════════════════════'"
Enter
Sleep 1s

Type ""
Enter
Type "# Real-time progress tracking"
Enter
Sleep 500ms

# Show progress bar animation
Type 'for i in 0 10 20 30 40 50 60 70 80 90 100; do'
Enter
Type '  progress_bar "$i" 100 50 "Downloading"'
Enter
Type '  sleep 0.3'
Enter
Type 'done'
Enter
Sleep 5s

Type ""
Enter
Type "log_success 'Download complete!'"
Enter
Sleep 2s

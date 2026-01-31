Output demos/gifs/features-v2/colored-logging.gif
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
Type "echo '        MAINFRAME Colored Logging          '"
Enter
Type "echo '═══════════════════════════════════════════'"
Enter
Sleep 1s

Type ""
Enter
Type "log_info    'Scanning project structure...'"
Enter
Sleep 1s

Type "log_success 'Found: TypeScript + Next.js + Prisma'"
Enter
Sleep 1s

Type "log_warn    'Large directory: node_modules/ (1.2GB)'"
Enter
Sleep 1s

Type "log_error   'Missing required: .env.local'"
Enter
Sleep 1s

Type "log_debug   'Debug mode: verbose output enabled'"
Enter
Sleep 2s

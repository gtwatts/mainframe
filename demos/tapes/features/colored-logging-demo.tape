Output demos/gifs/features/colored-logging.gif

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

Type "# MAINFRAME Colored Logging"
Enter
Sleep 1s

Type "log_info 'Scanning project structure...'"
Enter
Sleep 1.5s

Type "log_success 'Detected: TypeScript + Next.js + Prisma'"
Enter
Sleep 1.5s

Type "log_warn 'Large file detected: node_modules/'"
Enter
Sleep 1.5s

Type "log_error 'Missing required: .env file'"
Enter
Sleep 2s

Type ""
Enter
Sleep 1s

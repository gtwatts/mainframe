Output demos/gifs/features-v2/validation.gif
Set Shell "bash"
Set FontFamily "JetBrains Mono"
Set FontSize 20
Set Width 1000
Set Height 500
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
Type "echo '╔══════════════════════════════════════════╗'"
Enter
Type "echo '║     MAINFRAME Input Validation           ║'"
Enter
Type "echo '╚══════════════════════════════════════════╝'"
Enter
Sleep 1s

Type ""
Enter
Type "# Validate an email address"
Enter
Sleep 500ms

Type 'validate_email "dev@mainframe.sh" && log_success "Valid email"'
Enter
Sleep 1.5s

Type ""
Enter
Type "# Validate a URL"
Enter
Sleep 500ms

Type 'validate_url "https://github.com/gtwatts/mainframe" && log_success "Valid URL"'
Enter
Sleep 1.5s

Type ""
Enter
Type "# Validate semantic version"
Enter
Sleep 500ms

Type 'validate_semver "5.0.0" && log_success "Valid semver"'
Enter
Sleep 1.5s

Type ""
Enter
Type "# Validate integer in range"
Enter
Sleep 500ms

Type 'validate_int "42" 0 100 && log_success "Valid integer (0-100)"'
Enter
Sleep 2s

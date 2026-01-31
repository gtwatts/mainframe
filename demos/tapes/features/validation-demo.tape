Output demos/gifs/features/validation.gif

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

Type "# MAINFRAME Input Validation"
Enter
Sleep 1s

Type 'validate_email "dev@mainframe.sh" && log_success "Valid email"'
Enter
Sleep 2s

Type 'validate_url "https://github.com/gtwatts/mainframe" && log_success "Valid URL"'
Enter
Sleep 2s

Type 'validate_int "42" 0 100 && log_success "Valid integer in range"'
Enter
Sleep 2s

Type 'validate_semver "5.0.0" && log_success "Valid semantic version"'
Enter
Sleep 2s

Type ""
Enter
Sleep 1s

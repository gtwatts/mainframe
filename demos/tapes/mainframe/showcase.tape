# MAINFRAME Showcase Demo
# Demonstrates core MAINFRAME library features in a visually compelling way

Output demos/gifs/mainframe-showcase.gif
Set FontSize 18
Set Width 1000
Set Height 650
Set Theme "Catppuccin Mocha"
Set Padding 30
Set TypingSpeed 40ms
Set Framerate 30

# Clear screen first
Hide
Type "clear"
Enter
Show
Sleep 300ms

# Title banner
Type "echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'"
Enter
Type "echo '  MAINFRAME - 1,900+ Pure Bash Functions'"
Enter
Type "echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'"
Enter
Sleep 1s

# Source the library
Type ""
Enter
Type "# One line gives you everything:"
Enter
Sleep 500ms
Type 'source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"'
Enter
Sleep 1s

# Colored logging
Type ""
Enter
Type "# Colored logging with timestamps:"
Enter
Sleep 500ms
Type "log_info 'Processing user data...'"
Enter
Sleep 400ms
Type "log_warn 'Rate limit approaching (85%)'"
Enter
Sleep 400ms
Type "log_error 'Connection timeout on retry 3'"
Enter
Sleep 1s

# Success/failure indicators
Type ""
Enter
Type "# Clear status indicators:"
Enter
Sleep 500ms
Type "success 'Database migration completed'"
Enter
Sleep 400ms
Type "failure 'API key validation failed'"
Enter
Sleep 1s

# JSON creation
Type ""
Enter
Type "# Create JSON without jq:"
Enter
Sleep 500ms
Type 'json_object "name=Gordon" "role=Developer" "active:bool=true"'
Enter
Sleep 1s

# Nested JSON
Type ""
Enter
Type "# Nested structures:"
Enter
Sleep 500ms
Type 'json_object "user=$(json_object name=John)" "tags=$(json_array dev ops)"'
Enter
Sleep 1s

# Formatting functions
Type ""
Enter
Type "# Human-readable formatting:"
Enter
Sleep 500ms
Type "format_bytes 1073741824    # 1GB in bytes"
Enter
Sleep 600ms
Type "format_duration 3725       # seconds to human time"
Enter
Sleep 600ms
Type "format_number 1234567      # with thousands separator"
Enter
Sleep 1s

# Progress bar
Type ""
Enter
Type "# Built-in progress bars:"
Enter
Sleep 500ms
Type "for i in {1..5}; do progress_bar \$i 5; sleep 0.3; done; echo"
Enter
Sleep 2s

# Final banner
Type ""
Enter
Type "echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'"
Enter
Type "echo '  github.com/gordonwatts/basher   ★ MIT License'"
Enter
Type "echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'"
Enter
Sleep 3s

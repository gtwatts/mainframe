# Demo: json-to-csv
# Description: Convert JSON arrays to CSV with automatic header detection

Output demos/gifs/data/json-to-csv.gif
Set FontSize 16
Set Width 1200
Set Height 600
Set Theme "Catppuccin Mocha"
Set Padding 20
Set TypingSpeed 50ms

# Title
Hide
Type "clear"
Enter
Show
Sleep 500ms

Type "# Basher: json-to-csv Demo"
Enter
Sleep 1s

# Show sample data
Type "# First, let's look at our sample JSON data:"
Enter
Sleep 500ms

Type "cat users.json | jq ."
Enter
Sleep 2s

# Basic conversion
Type ""
Enter
Type "# Convert to CSV with automatic header detection:"
Enter
Sleep 500ms

Type "json-to-csv users.json"
Enter
Sleep 2s

# With nested objects
Type ""
Enter
Type "# Handle nested objects with flattening:"
Enter
Sleep 500ms

Type "cat nested.json | jq ."
Enter
Sleep 2s

Type "json-to-csv --flatten nested.json"
Enter
Sleep 2s

# Select specific fields
Type ""
Enter
Type "# Select specific fields:"
Enter
Sleep 500ms

Type "json-to-csv --fields name,email users.json"
Enter
Sleep 2s

# Pipe support
Type ""
Enter
Type "# Works with pipes too:"
Enter
Sleep 500ms

Type "curl -s https://api.example.com/users | json-to-csv"
Enter
Sleep 2s

# Done
Type ""
Enter
Type "# Done! Check 'json-to-csv --help' for more options"
Enter
Sleep 3s

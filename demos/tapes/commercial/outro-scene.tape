Output demos/captures/outro-scene.mp4
Set Shell "bash"
Set FontFamily "JetBrains Mono"
Set FontSize 16
Set Width 1280
Set Height 720
Set Framerate 30

# GitHub dark theme
Set Theme {
    "background": "#0d1117",
    "foreground": "#c9d1d9",
    "black": "#484f58",
    "red": "#ff7b72",
    "green": "#3fb950",
    "yellow": "#d29922",
    "blue": "#58a6ff",
    "magenta": "#bc8cff",
    "cyan": "#39c5cf",
    "white": "#b1bac4"
}

Hide
Type "cd /tmp"
Enter
Type "export PS1='$ '"
Enter
Type "clear"
Enter
Show
Sleep 300ms

Set TypingSpeed 0ms

# Instantly display ASCII art
Type@0ms "cat << 'EOF'"
Enter
Type@0ms ""
Enter
Type@0ms "╔══════════════════════════════════════════════════════════════════════╗"
Enter
Type@0ms "║  ███╗   ███╗ █████╗ ██╗███╗   ██╗███████╗██████╗  █████╗ ███╗   ███╗║"
Enter
Type@0ms "║  ████╗ ████║██╔══██╗██║████╗  ██║██╔════╝██╔══██╗██╔══██╗████╗ ████║║"
Enter
Type@0ms "║  ██╔████╔██║███████║██║██╔██╗ ██║█████╗  ██████╔╝███████║██╔████╔██║║"
Enter
Type@0ms "║  ██║╚██╔╝██║██╔══██║██║██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║██║╚██╔╝██║║"
Enter
Type@0ms "║  ██║ ╚═╝ ██║██║  ██║██║██║ ╚████║██║     ██║  ██║██║  ██║██║ ╚═╝ ██║║"
Enter
Type@0ms "║  ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝║"
Enter
Type@0ms "║                                                                      ║"
Enter
Type@0ms "║     AI agents control computers through bash.                        ║"
Enter
Type@0ms "║     MAINFRAME makes that safe, accurate, and efficient.              ║"
Enter
Type@0ms "╚══════════════════════════════════════════════════════════════════════╝"
Enter
Type@0ms ""
Enter
Type@0ms "              ⭐ github.com/gtwatts/mainframe ⭐"
Enter
Type@0ms "EOF"
Enter
Sleep 500ms

# Execute the heredoc
Enter
Sleep 3s

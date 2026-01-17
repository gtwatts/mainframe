#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/ansi.sh - ANSI Escape Code Library
# =============================================================================
# Description: Terminal formatting with ANSI escape sequences
# Source: Inspired by github.com/fidian/ansi
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_ANSI_LOADED:-}" ]] && return 0
readonly _MAINFRAME_ANSI_LOADED=1

# =============================================================================
# ESCAPE SEQUENCES
# =============================================================================

# Core escape characters
readonly ANSI_ESC=$'\033'
readonly ANSI_CSI="${ANSI_ESC}["
readonly ANSI_OSC="${ANSI_ESC}]"
readonly ANSI_ST="${ANSI_ESC}\\"

# =============================================================================
# COLOR DETECTION
# =============================================================================

# Check if terminal supports colors
ansi_supported() {
    [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] && [[ "${TERM:-dumb}" != "dumb" ]]
}

# Get number of supported colors
ansi_colors() {
    tput colors 2>/dev/null || printf '8\n'
}

# =============================================================================
# FOREGROUND COLORS (Standard)
# =============================================================================

ansi_black()   { printf '%s' "${ANSI_CSI}30m"; }
ansi_red()     { printf '%s' "${ANSI_CSI}31m"; }
ansi_green()   { printf '%s' "${ANSI_CSI}32m"; }
ansi_yellow()  { printf '%s' "${ANSI_CSI}33m"; }
ansi_blue()    { printf '%s' "${ANSI_CSI}34m"; }
ansi_magenta() { printf '%s' "${ANSI_CSI}35m"; }
ansi_cyan()    { printf '%s' "${ANSI_CSI}36m"; }
ansi_white()   { printf '%s' "${ANSI_CSI}37m"; }

# =============================================================================
# FOREGROUND COLORS (Bright/Intense)
# =============================================================================

ansi_bright_black()   { printf '%s' "${ANSI_CSI}90m"; }
ansi_bright_red()     { printf '%s' "${ANSI_CSI}91m"; }
ansi_bright_green()   { printf '%s' "${ANSI_CSI}92m"; }
ansi_bright_yellow()  { printf '%s' "${ANSI_CSI}93m"; }
ansi_bright_blue()    { printf '%s' "${ANSI_CSI}94m"; }
ansi_bright_magenta() { printf '%s' "${ANSI_CSI}95m"; }
ansi_bright_cyan()    { printf '%s' "${ANSI_CSI}96m"; }
ansi_bright_white()   { printf '%s' "${ANSI_CSI}97m"; }

# =============================================================================
# BACKGROUND COLORS (Standard)
# =============================================================================

ansi_bg_black()   { printf '%s' "${ANSI_CSI}40m"; }
ansi_bg_red()     { printf '%s' "${ANSI_CSI}41m"; }
ansi_bg_green()   { printf '%s' "${ANSI_CSI}42m"; }
ansi_bg_yellow()  { printf '%s' "${ANSI_CSI}43m"; }
ansi_bg_blue()    { printf '%s' "${ANSI_CSI}44m"; }
ansi_bg_magenta() { printf '%s' "${ANSI_CSI}45m"; }
ansi_bg_cyan()    { printf '%s' "${ANSI_CSI}46m"; }
ansi_bg_white()   { printf '%s' "${ANSI_CSI}47m"; }

# =============================================================================
# BACKGROUND COLORS (Bright/Intense)
# =============================================================================

ansi_bg_bright_black()   { printf '%s' "${ANSI_CSI}100m"; }
ansi_bg_bright_red()     { printf '%s' "${ANSI_CSI}101m"; }
ansi_bg_bright_green()   { printf '%s' "${ANSI_CSI}102m"; }
ansi_bg_bright_yellow()  { printf '%s' "${ANSI_CSI}103m"; }
ansi_bg_bright_blue()    { printf '%s' "${ANSI_CSI}104m"; }
ansi_bg_bright_magenta() { printf '%s' "${ANSI_CSI}105m"; }
ansi_bg_bright_cyan()    { printf '%s' "${ANSI_CSI}106m"; }
ansi_bg_bright_white()   { printf '%s' "${ANSI_CSI}107m"; }

# =============================================================================
# 256-COLOR SUPPORT
# =============================================================================

# Set foreground to 256-color palette
# Usage: ansi_color 196  (bright red)
ansi_color() {
    printf '%s' "${ANSI_CSI}38;5;${1}m"
}

# Set background to 256-color palette
# Usage: ansi_bg_color 196
ansi_bg_color() {
    printf '%s' "${ANSI_CSI}48;5;${1}m"
}

# =============================================================================
# TRUE COLOR (24-bit) SUPPORT
# =============================================================================

# Set foreground to RGB color
# Usage: ansi_rgb 255 128 0  (orange)
ansi_rgb() {
    printf '%s' "${ANSI_CSI}38;2;${1};${2};${3}m"
}

# Set background to RGB color
# Usage: ansi_bg_rgb 255 128 0
ansi_bg_rgb() {
    printf '%s' "${ANSI_CSI}48;2;${1};${2};${3}m"
}

# Set foreground from hex color
# Usage: ansi_hex "#ff8000"
ansi_hex() {
    local hex="${1#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    printf '%s' "${ANSI_CSI}38;2;${r};${g};${b}m"
}

# Set background from hex color
# Usage: ansi_bg_hex "#ff8000"
ansi_bg_hex() {
    local hex="${1#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    printf '%s' "${ANSI_CSI}48;2;${r};${g};${b}m"
}

# =============================================================================
# TEXT FORMATTING
# =============================================================================

ansi_bold()        { printf '%s' "${ANSI_CSI}1m"; }
ansi_dim()         { printf '%s' "${ANSI_CSI}2m"; }
ansi_italic()      { printf '%s' "${ANSI_CSI}3m"; }
ansi_underline()   { printf '%s' "${ANSI_CSI}4m"; }
ansi_blink()       { printf '%s' "${ANSI_CSI}5m"; }
ansi_rapid_blink() { printf '%s' "${ANSI_CSI}6m"; }
ansi_inverse()     { printf '%s' "${ANSI_CSI}7m"; }
ansi_invisible()   { printf '%s' "${ANSI_CSI}8m"; }
ansi_strike()      { printf '%s' "${ANSI_CSI}9m"; }

# Double underline (not widely supported)
ansi_double_underline() { printf '%s' "${ANSI_CSI}21m"; }

# Overline (not widely supported)
ansi_overline() { printf '%s' "${ANSI_CSI}53m"; }

# =============================================================================
# RESET FUNCTIONS
# =============================================================================

ansi_reset()            { printf '%s' "${ANSI_CSI}0m"; }
ansi_reset_bold()       { printf '%s' "${ANSI_CSI}22m"; }
ansi_reset_dim()        { printf '%s' "${ANSI_CSI}22m"; }
ansi_reset_italic()     { printf '%s' "${ANSI_CSI}23m"; }
ansi_reset_underline()  { printf '%s' "${ANSI_CSI}24m"; }
ansi_reset_blink()      { printf '%s' "${ANSI_CSI}25m"; }
ansi_reset_inverse()    { printf '%s' "${ANSI_CSI}27m"; }
ansi_reset_invisible()  { printf '%s' "${ANSI_CSI}28m"; }
ansi_reset_strike()     { printf '%s' "${ANSI_CSI}29m"; }
ansi_reset_fg()         { printf '%s' "${ANSI_CSI}39m"; }
ansi_reset_bg()         { printf '%s' "${ANSI_CSI}49m"; }

# =============================================================================
# CURSOR MOVEMENT
# =============================================================================

# Move cursor up N lines
# Usage: ansi_up 5
ansi_up() {
    printf '%s' "${ANSI_CSI}${1:-1}A"
}

# Move cursor down N lines
# Usage: ansi_down 5
ansi_down() {
    printf '%s' "${ANSI_CSI}${1:-1}B"
}

# Move cursor forward N columns
# Usage: ansi_forward 5
ansi_forward() {
    printf '%s' "${ANSI_CSI}${1:-1}C"
}

# Move cursor backward N columns
# Usage: ansi_backward 5
ansi_backward() {
    printf '%s' "${ANSI_CSI}${1:-1}D"
}

# Move cursor to next line
# Usage: ansi_next_line 2
ansi_next_line() {
    printf '%s' "${ANSI_CSI}${1:-1}E"
}

# Move cursor to previous line
# Usage: ansi_prev_line 2
ansi_prev_line() {
    printf '%s' "${ANSI_CSI}${1:-1}F"
}

# Move cursor to column N
# Usage: ansi_column 10
ansi_column() {
    printf '%s' "${ANSI_CSI}${1:-1}G"
}

# Move cursor to row,column
# Usage: ansi_position 5 10
ansi_position() {
    printf '%s' "${ANSI_CSI}${1:-1};${2:-1}H"
}

# Save cursor position
ansi_save_cursor() {
    printf '%s' "${ANSI_CSI}s"
}

# Restore cursor position
ansi_restore_cursor() {
    printf '%s' "${ANSI_CSI}u"
}

# Hide cursor
ansi_hide_cursor() {
    printf '%s' "${ANSI_CSI}?25l"
}

# Show cursor
ansi_show_cursor() {
    printf '%s' "${ANSI_CSI}?25h"
}

# =============================================================================
# DISPLAY MANIPULATION
# =============================================================================

# Erase from cursor to end of screen
ansi_erase_down() {
    printf '%s' "${ANSI_CSI}0J"
}

# Erase from cursor to beginning of screen
ansi_erase_up() {
    printf '%s' "${ANSI_CSI}1J"
}

# Erase entire screen
ansi_erase_screen() {
    printf '%s' "${ANSI_CSI}2J"
}

# Erase from cursor to end of line
ansi_erase_line_end() {
    printf '%s' "${ANSI_CSI}0K"
}

# Erase from cursor to beginning of line
ansi_erase_line_start() {
    printf '%s' "${ANSI_CSI}1K"
}

# Erase entire line
ansi_erase_line() {
    printf '%s' "${ANSI_CSI}2K"
}

# Clear screen and move to home
ansi_clear() {
    printf '%s' "${ANSI_CSI}2J${ANSI_CSI}H"
}

# Scroll up N lines
ansi_scroll_up() {
    printf '%s' "${ANSI_CSI}${1:-1}S"
}

# Scroll down N lines
ansi_scroll_down() {
    printf '%s' "${ANSI_CSI}${1:-1}T"
}

# =============================================================================
# TERMINAL CONTROL
# =============================================================================

# Ring terminal bell
ansi_bell() {
    printf '\a'
}

# Set window title
# Usage: ansi_title "My Terminal"
ansi_title() {
    printf '%s' "${ANSI_OSC}0;${1}${ANSI_ST}"
}

# Set icon name
# Usage: ansi_icon "term"
ansi_icon() {
    printf '%s' "${ANSI_OSC}1;${1}${ANSI_ST}"
}

# Set window title and icon
# Usage: ansi_title_icon "My Terminal"
ansi_title_icon() {
    printf '%s' "${ANSI_OSC}2;${1}${ANSI_ST}"
}

# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

# Print colored text and reset
# Usage: ansi_print red "Error message"
ansi_print() {
    local color="$1"
    shift
    local text="$*"

    case "$color" in
        black)   ansi_black ;;
        red)     ansi_red ;;
        green)   ansi_green ;;
        yellow)  ansi_yellow ;;
        blue)    ansi_blue ;;
        magenta) ansi_magenta ;;
        cyan)    ansi_cyan ;;
        white)   ansi_white ;;
        *)       ansi_color "$color" ;;
    esac
    printf '%s' "$text"
    ansi_reset
    printf '\n'
}

# Print with style
# Usage: ansi_styled "bold,red" "Important!"
ansi_styled() {
    local styles="$1"
    shift
    local text="$*"
    local IFS=','

    for style in $styles; do
        case "$style" in
            bold)      ansi_bold ;;
            dim)       ansi_dim ;;
            italic)    ansi_italic ;;
            underline) ansi_underline ;;
            blink)     ansi_blink ;;
            inverse)   ansi_inverse ;;
            strike)    ansi_strike ;;
            black)     ansi_black ;;
            red)       ansi_red ;;
            green)     ansi_green ;;
            yellow)    ansi_yellow ;;
            blue)      ansi_blue ;;
            magenta)   ansi_magenta ;;
            cyan)      ansi_cyan ;;
            white)     ansi_white ;;
        esac
    done
    printf '%s' "$text"
    ansi_reset
}

# Display color table
ansi_color_table() {
    local i j

    printf 'Standard colors:\n'
    for i in {0..7}; do
        ansi_color "$i"
        printf ' %3d ' "$i"
    done
    ansi_reset
    printf '\n'

    printf 'High-intensity colors:\n'
    for i in {8..15}; do
        ansi_color "$i"
        printf ' %3d ' "$i"
    done
    ansi_reset
    printf '\n\n'

    printf '216 colors:\n'
    for i in {0..5}; do
        for j in {0..35}; do
            local code=$((16 + i * 36 + j))
            ansi_bg_color "$code"
            printf '  '
        done
        ansi_reset
        printf '\n'
    done
    printf '\n'

    printf 'Grayscale:\n'
    for i in {232..255}; do
        ansi_bg_color "$i"
        printf '  '
    done
    ansi_reset
    printf '\n'
}


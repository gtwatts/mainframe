#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/tui.sh - Terminal User Interface Library
# =============================================================================
# Description: Progress bars, spinners, interactive prompts, styled output
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_TUI_LOADED:-}" ]] && return 0
readonly _MAINFRAME_TUI_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

# Get the directory containing this script
_TUI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source ansi.sh if not already loaded
if [[ -z "${_MAINFRAME_ANSI_LOADED:-}" ]]; then
    source "$_TUI_LIB_DIR/ansi.sh"
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

# Progress bar settings
TUI_PROGRESS_WIDTH="${TUI_PROGRESS_WIDTH:-40}"
TUI_PROGRESS_FILLED="${TUI_PROGRESS_FILLED:-█}"
TUI_PROGRESS_EMPTY="${TUI_PROGRESS_EMPTY:-░}"
TUI_PROGRESS_COLOR="${TUI_PROGRESS_COLOR:-green}"

# Spinner settings
TUI_SPINNER_FRAMES="${TUI_SPINNER_FRAMES:-⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏}"
TUI_SPINNER_DELAY="${TUI_SPINNER_DELAY:-0.1}"

# Box drawing characters (Unicode)
readonly TUI_BOX_TL="┌"
readonly TUI_BOX_TR="┐"
readonly TUI_BOX_BL="└"
readonly TUI_BOX_BR="┘"
readonly TUI_BOX_H="─"
readonly TUI_BOX_V="│"

# Internal state
declare -g _TUI_SPINNER_PID=""
declare -g _TUI_PROGRESS_CURRENT=0
declare -g _TUI_PROGRESS_TOTAL=100
declare -g _TUI_PROGRESS_LABEL=""

# =============================================================================
# TERMINAL UTILITIES
# =============================================================================

# Get terminal width
tui::term_width() {
    local width
    if [[ -t 1 ]]; then
        width=$(tput cols 2>/dev/null) || width=80
    else
        width=80
    fi
    printf '%d' "$width"
}

# Check if terminal is interactive
tui::is_interactive() {
    [[ -t 0 && -t 1 ]]
}

# Check if colors are supported
tui::supports_color() {
    ansi_supported
}

# =============================================================================
# PROGRESS BAR
# =============================================================================

# Draw a simple progress bar
# Usage: tui::progress_bar 50 100  # 50% of 100
# Usage: tui::progress_bar 75      # 75% (assumes total=100)
tui::progress_bar() {
    local current="${1:-0}"
    local total="${2:-100}"
    local width="${3:-$TUI_PROGRESS_WIDTH}"
    
    # Calculate percentage
    local percent=0
    if (( total > 0 )); then
        percent=$(( (current * 100) / total ))
    fi
    (( percent > 100 )) && percent=100
    (( percent < 0 )) && percent=0
    
    # Calculate filled width
    local filled=$(( (percent * width) / 100 ))
    local empty=$(( width - filled ))
    
    # Build the bar
    local bar=""
    local i
    for (( i = 0; i < filled; i++ )); do
        bar+="$TUI_PROGRESS_FILLED"
    done
    for (( i = 0; i < empty; i++ )); do
        bar+="$TUI_PROGRESS_EMPTY"
    done
    
    # Output with color if supported
    if tui::supports_color; then
        printf '\r'
        ansi_green
        printf '%s' "$bar"
        ansi_reset
        printf ' %3d%%' "$percent"
    else
        printf '\r%s %3d%%' "$bar" "$percent"
    fi
}

# Start a progress operation with label
# Usage: tui::progress_start "Downloading"
tui::progress_start() {
    local label="${1:-Progress}"
    _TUI_PROGRESS_LABEL="$label"
    _TUI_PROGRESS_CURRENT=0
    _TUI_PROGRESS_TOTAL=100
    
    if tui::supports_color; then
        ansi_hide_cursor
    fi
    
    printf '%s: ' "$label"
    tui::progress_bar 0 100
}

# Update progress
# Usage: tui::progress_update 75
# Usage: tui::progress_update 75 100
tui::progress_update() {
    local current="${1:-0}"
    local total="${2:-$_TUI_PROGRESS_TOTAL}"
    
    _TUI_PROGRESS_CURRENT="$current"
    _TUI_PROGRESS_TOTAL="$total"
    
    # Move to start of progress bar area
    printf '\r%s: ' "$_TUI_PROGRESS_LABEL"
    tui::progress_bar "$current" "$total"
}

# Complete progress with success
# Usage: tui::progress_done
# Usage: tui::progress_done "Complete!"
tui::progress_done() {
    local message="${1:-Done}"
    
    # Show 100%
    printf '\r%s: ' "$_TUI_PROGRESS_LABEL"
    tui::progress_bar 100 100
    
    # Add completion message
    if tui::supports_color; then
        printf ' '
        ansi_green
        printf '✓ %s' "$message"
        ansi_reset
        ansi_show_cursor
    else
        printf ' [%s]' "$message"
    fi
    printf '\n'
    
    # Reset state
    _TUI_PROGRESS_CURRENT=0
    _TUI_PROGRESS_TOTAL=100
    _TUI_PROGRESS_LABEL=""
}

# Fail progress
# Usage: tui::progress_fail "Error message"
tui::progress_fail() {
    local message="${1:-Failed}"
    
    if tui::supports_color; then
        printf '\r%s: ' "$_TUI_PROGRESS_LABEL"
        ansi_red
        printf '✗ %s' "$message"
        ansi_reset
        ansi_show_cursor
    else
        printf '\r%s: [FAILED] %s' "$_TUI_PROGRESS_LABEL" "$message"
    fi
    printf '\n'
    
    # Reset state
    _TUI_PROGRESS_CURRENT=0
    _TUI_PROGRESS_TOTAL=100
    _TUI_PROGRESS_LABEL=""
}

# =============================================================================
# SPINNERS
# =============================================================================

# Internal spinner loop
_tui_spinner_loop() {
    local message="$1"
    local -a frames
    IFS=' ' read -ra frames <<< "$TUI_SPINNER_FRAMES"
    local frame_count=${#frames[@]}
    local i=0
    
    # Hide cursor
    if tui::supports_color; then
        ansi_hide_cursor
    fi
    
    while true; do
        printf '\r%s %s' "${frames[i]}" "$message"
        i=$(( (i + 1) % frame_count ))
        sleep "$TUI_SPINNER_DELAY"
    done
}

# Start a spinner
# Usage: tui::spin_start "Processing..."
tui::spin_start() {
    local message="${1:-Processing...}"
    
    # Stop any existing spinner
    tui::spin_stop 2>/dev/null
    
    # Start spinner in background
    _tui_spinner_loop "$message" &
    _TUI_SPINNER_PID=$!
    disown "$_TUI_SPINNER_PID" 2>/dev/null
}

# Stop the spinner
# Usage: tui::spin_stop
# Usage: tui::spin_stop "Done"
# Usage: tui::spin_stop "Failed" error
tui::spin_stop() {
    local message="${1:-}"
    local status="${2:-success}"
    
    # Kill spinner process if running
    if [[ -n "$_TUI_SPINNER_PID" ]] && kill -0 "$_TUI_SPINNER_PID" 2>/dev/null; then
        kill "$_TUI_SPINNER_PID" 2>/dev/null
        wait "$_TUI_SPINNER_PID" 2>/dev/null
    fi
    _TUI_SPINNER_PID=""
    
    # Clear line and show cursor
    printf '\r'
    ansi_erase_line
    
    if tui::supports_color; then
        ansi_show_cursor
    fi
    
    # Show completion message if provided
    if [[ -n "$message" ]]; then
        if [[ "$status" == "error" ]]; then
            tui::error "$message"
        else
            tui::success "$message"
        fi
    fi
}

# Run a command with a spinner
# Usage: tui::spin_while "Processing" long_command arg1 arg2
tui::spin_while() {
    local message="$1"
    shift
    
    tui::spin_start "$message"
    
    # Run command
    local result=0
    "$@" || result=$?
    
    # Stop spinner with result
    if (( result == 0 )); then
        tui::spin_stop "$message - Done"
    else
        tui::spin_stop "$message - Failed" error
    fi
    
    return $result
}

# =============================================================================
# INTERACTIVE PROMPTS
# =============================================================================

# Confirm yes/no prompt
# Usage: tui::confirm "Continue?" && echo "Yes"
# Usage: tui::confirm "Delete all?" n && echo "Yes"  # default=no
tui::confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-y}"
    
    # Check if interactive
    if ! tui::is_interactive; then
        # Non-interactive: use default
        [[ "${default,,}" == "y" ]]
        return
    fi
    
    local hint
    if [[ "${default,,}" == "y" ]]; then
        hint="[Y/n]"
    else
        hint="[y/N]"
    fi
    
    local answer
    while true; do
        if tui::supports_color; then
            ansi_bold
            printf '%s' "$prompt"
            ansi_reset
            printf ' %s ' "$hint"
        else
            printf '%s %s ' "$prompt" "$hint"
        fi
        
        read -r answer
        
        # Empty = default
        if [[ -z "$answer" ]]; then
            [[ "${default,,}" == "y" ]]
            return
        fi
        
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     printf 'Please answer yes or no.\n' ;;
        esac
    done
}

# Select from options
# Usage: choice=$(tui::select "Option 1" "Option 2" "Option 3")
tui::select() {
    local -a options=("$@")
    local count=${#options[@]}
    
    if (( count == 0 )); then
        return 1
    fi
    
    # Check if interactive
    if ! tui::is_interactive; then
        # Non-interactive: return first option
        printf '%s' "${options[0]}"
        return 0
    fi
    
    local i
    for (( i = 0; i < count; i++ )); do
        if tui::supports_color; then
            ansi_cyan
            printf '  %d) ' "$((i + 1))"
            ansi_reset
            printf '%s\n' "${options[i]}"
        else
            printf '  %d) %s\n' "$((i + 1))" "${options[i]}"
        fi
    done
    
    local choice
    while true; do
        if tui::supports_color; then
            ansi_bold
            printf 'Select [1-%d]: ' "$count"
            ansi_reset
        else
            printf 'Select [1-%d]: ' "$count"
        fi
        
        read -r choice
        
        # Validate numeric input
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
            printf '%s' "${options[choice - 1]}"
            return 0
        fi
        
        printf 'Invalid selection. Please enter 1-%d.\n' "$count"
    done
}

# Text input prompt
# Usage: value=$(tui::input "Enter name:" "default")
tui::input() {
    local prompt="${1:-Enter value:}"
    local default="${2:-}"
    
    # Check if interactive
    if ! tui::is_interactive; then
        # Non-interactive: return default
        printf '%s' "$default"
        return 0
    fi
    
    local hint=""
    if [[ -n "$default" ]]; then
        hint=" [$default]"
    fi
    
    if tui::supports_color; then
        ansi_bold
        printf '%s' "$prompt"
        ansi_reset
        printf '%s ' "$hint"
    else
        printf '%s%s ' "$prompt" "$hint"
    fi
    
    local value
    read -r value
    
    # Empty = default
    if [[ -z "$value" ]]; then
        value="$default"
    fi
    
    printf '%s' "$value"
}

# Password input (hidden)
# Usage: password=$(tui::password "Enter password:")
tui::password() {
    local prompt="${1:-Password:}"
    
    # Check if interactive
    if ! tui::is_interactive; then
        return 1
    fi
    
    if tui::supports_color; then
        ansi_bold
        printf '%s ' "$prompt"
        ansi_reset
    else
        printf '%s ' "$prompt"
    fi
    
    local password
    read -rs password
    printf '\n'
    
    printf '%s' "$password"
}

# =============================================================================
# STYLED OUTPUT
# =============================================================================

# Print a header/title
# Usage: tui::header "Section Title"
tui::header() {
    local text="$1"
    local width="${2:-$(tui::term_width)}"
    
    # Ensure minimum width
    (( width < 20 )) && width=20
    
    local text_len=${#text}
    local padding=$(( (width - text_len - 4) / 2 ))
    (( padding < 1 )) && padding=1
    
    local line=""
    local i
    for (( i = 0; i < width; i++ )); do
        line+="═"
    done
    
    local pad_left=""
    for (( i = 0; i < padding; i++ )); do
        pad_left+=" "
    done
    
    printf '\n'
    if tui::supports_color; then
        ansi_bold
        ansi_cyan
        printf '%s\n' "$line"
        printf '%s%s\n' "$pad_left" "$text"
        printf '%s\n' "$line"
        ansi_reset
    else
        printf '%s\n' "$line"
        printf '%s%s\n' "$pad_left" "$text"
        printf '%s\n' "$line"
    fi
    printf '\n'
}

# Print text in a box
# Usage: tui::box "Content in a box"
# Usage: tui::box "Title" "Content line 1" "Content line 2"
tui::box() {
    local -a lines=("$@")
    local max_len=0
    local line
    
    # Find max line length
    for line in "${lines[@]}"; do
        (( ${#line} > max_len )) && max_len=${#line}
    done
    
    # Minimum width
    (( max_len < 10 )) && max_len=10
    
    # Build horizontal border
    local border=""
    local i
    for (( i = 0; i < max_len + 2; i++ )); do
        border+="$TUI_BOX_H"
    done
    
    # Print box
    if tui::supports_color; then
        ansi_cyan
    fi
    
    printf '%s%s%s\n' "$TUI_BOX_TL" "$border" "$TUI_BOX_TR"
    
    for line in "${lines[@]}"; do
        local pad_len=$(( max_len - ${#line} ))
        local padding=""
        for (( i = 0; i < pad_len; i++ )); do
            padding+=" "
        done
        printf '%s %s%s %s\n' "$TUI_BOX_V" "$line" "$padding" "$TUI_BOX_V"
    done
    
    printf '%s%s%s\n' "$TUI_BOX_BL" "$border" "$TUI_BOX_BR"
    
    if tui::supports_color; then
        ansi_reset
    fi
}

# Success message
# Usage: tui::success "Operation completed"
tui::success() {
    local message="$1"
    
    if tui::supports_color; then
        ansi_green
        ansi_bold
        printf '✓ '
        ansi_reset
        ansi_green
        printf '%s' "$message"
        ansi_reset
    else
        printf '[OK] %s' "$message"
    fi
    printf '\n'
}

# Warning message
# Usage: tui::warning "Be careful"
tui::warning() {
    local message="$1"
    
    if tui::supports_color; then
        ansi_yellow
        ansi_bold
        printf '⚠ '
        ansi_reset
        ansi_yellow
        printf '%s' "$message"
        ansi_reset
    else
        printf '[WARN] %s' "$message"
    fi
    printf '\n'
}

# Error message
# Usage: tui::error "Something failed"
tui::error() {
    local message="$1"
    
    if tui::supports_color; then
        ansi_red
        ansi_bold
        printf '✗ '
        ansi_reset
        ansi_red
        printf '%s' "$message"
        ansi_reset
    else
        printf '[ERROR] %s' "$message"
    fi
    printf '\n' >&2
}

# Info message
# Usage: tui::info "Information message"
tui::info() {
    local message="$1"
    
    if tui::supports_color; then
        ansi_blue
        ansi_bold
        printf 'ℹ '
        ansi_reset
        ansi_blue
        printf '%s' "$message"
        ansi_reset
    else
        printf '[INFO] %s' "$message"
    fi
    printf '\n'
}

# Debug message (respects TUI_DEBUG)
# Usage: tui::debug "Debug info"
tui::debug() {
    [[ -z "${TUI_DEBUG:-}" ]] && return 0
    
    local message="$1"
    
    if tui::supports_color; then
        ansi_dim
        printf '[DEBUG] %s' "$message"
        ansi_reset
    else
        printf '[DEBUG] %s' "$message"
    fi
    printf '\n' >&2
}

# =============================================================================
# TABLES
# =============================================================================

# Print a simple table
# Usage: tui::table "Header1|Header2|Header3" "Row1Col1|Row1Col2|Row1Col3" ...
tui::table() {
    local -a rows=("$@")
    local -a widths=()
    local IFS='|'
    
    # Calculate column widths
    for row in "${rows[@]}"; do
        local -a cols
        read -ra cols <<< "$row"
        local i=0
        for col in "${cols[@]}"; do
            local len=${#col}
            if (( i >= ${#widths[@]} )); then
                widths+=("$len")
            elif (( len > widths[i] )); then
                widths[i]=$len
            fi
            ((i++))
        done
    done
    
    # Print header
    local first=1
    for row in "${rows[@]}"; do
        local -a cols
        read -ra cols <<< "$row"
        
        local output=""
        local i=0
        for col in "${cols[@]}"; do
            local width=${widths[i]:-10}
            local padded
            printf -v padded "%-${width}s" "$col"
            output+="$padded  "
            ((i++))
        done
        
        if (( first )); then
            if tui::supports_color; then
                ansi_bold
                printf '%s\n' "$output"
                ansi_reset
            else
                printf '%s\n' "$output"
            fi
            
            # Print separator
            local sep=""
            for w in "${widths[@]}"; do
                local j
                for (( j = 0; j < w; j++ )); do
                    sep+="─"
                done
                sep+="  "
            done
            
            if tui::supports_color; then
                ansi_dim
                printf '%s\n' "$sep"
                ansi_reset
            else
                printf '%s\n' "$sep"
            fi
            
            first=0
        else
            printf '%s\n' "$output"
        fi
    done
}

# =============================================================================
# DIVIDERS & SEPARATORS
# =============================================================================

# Print a horizontal rule
# Usage: tui::hr
# Usage: tui::hr 40
# Usage: tui::hr 40 "="
tui::hr() {
    local width="${1:-$(tui::term_width)}"
    local char="${2:-─}"
    
    local line=""
    local i
    for (( i = 0; i < width; i++ )); do
        line+="$char"
    done
    
    if tui::supports_color; then
        ansi_dim
        printf '%s\n' "$line"
        ansi_reset
    else
        printf '%s\n' "$line"
    fi
}

# =============================================================================
# CLEANUP
# =============================================================================

# Cleanup on exit (stop spinner, show cursor)
_tui_cleanup() {
    if [[ -n "$_TUI_SPINNER_PID" ]] && kill -0 "$_TUI_SPINNER_PID" 2>/dev/null; then
        kill "$_TUI_SPINNER_PID" 2>/dev/null
    fi
    if tui::supports_color; then
        ansi_show_cursor
    fi
}

# Register cleanup
trap _tui_cleanup EXIT


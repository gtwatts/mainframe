#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/tui.sh - Terminal User Interface Library v7.4
# =============================================================================
# Description: Rich TUI components for terminal applications including tables,
#              boxes, panels, progress indicators, interactive components,
#              and color/styling functions with full NO_COLOR support.
#
# @module      tui
# @version     7.4.0
# @requires    ansi.sh, json.sh (optional for USOP)
# @provides    20+ TUI functions for terminal UI development
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
    # shellcheck source=lib/ansi.sh
    source "$_TUI_LIB_DIR/ansi.sh"
fi

# Source json.sh for USOP support if available
if [[ -z "${_MAINFRAME_JSON_LOADED:-}" ]] && [[ -f "$_TUI_LIB_DIR/json.sh" ]]; then
    # shellcheck source=lib/json.sh
    source "$_TUI_LIB_DIR/json.sh"
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

# Progress bar settings
TUI_PROGRESS_WIDTH="${TUI_PROGRESS_WIDTH:-40}"
TUI_PROGRESS_FILLED="${TUI_PROGRESS_FILLED:-█}"
TUI_PROGRESS_EMPTY="${TUI_PROGRESS_EMPTY:-░}"
TUI_PROGRESS_COLOR="${TUI_PROGRESS_COLOR:-green}"

# Spinner settings - Braille animation frames
TUI_SPINNER_FRAMES="${TUI_SPINNER_FRAMES:-⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏}"
TUI_SPINNER_DELAY="${TUI_SPINNER_DELAY:-0.1}"

# Box drawing characters (Unicode)
readonly TUI_BOX_TL="┌"
readonly TUI_BOX_TR="┐"
readonly TUI_BOX_BL="└"
readonly TUI_BOX_BR="┘"
readonly TUI_BOX_H="─"
readonly TUI_BOX_V="│"

# Double-line box characters
readonly TUI_BOX_DBL_TL="╔"
readonly TUI_BOX_DBL_TR="╗"
readonly TUI_BOX_DBL_BL="╚"
readonly TUI_BOX_DBL_BR="╝"
readonly TUI_BOX_DBL_H="═"
readonly TUI_BOX_DBL_V="║"

# Rounded box characters
readonly TUI_BOX_RND_TL="╭"
readonly TUI_BOX_RND_TR="╮"
readonly TUI_BOX_RND_BL="╰"
readonly TUI_BOX_RND_BR="╯"

# Theme support
declare -gA _TUI_THEME
_TUI_THEME=(
    [primary]="cyan"
    [secondary]="blue"
    [success]="green"
    [warning]="yellow"
    [error]="red"
    [info]="blue"
    [muted]="bright_black"
    [accent]="magenta"
)

# Internal state
declare -g _TUI_SPINNER_PID=""
declare -g _TUI_CURSOR_HIDDEN=0
declare -g _TUI_PROGRESS_CURRENT=0
declare -g _TUI_PROGRESS_TOTAL=100
declare -g _TUI_PROGRESS_LABEL=""
declare -g _TUI_ELAPSED_START=""
declare -g _TUI_COUNTDOWN_END=""

# =============================================================================
# TERMINAL UTILITIES
# =============================================================================

# Get terminal width
# @contract.ensure return_value >= 20
# Usage: width=$(tui_term_width)
tui_term_width() {
    local width
    if [[ -t 1 ]]; then
        width=$(tput cols 2>/dev/null) || width=80
    else
        width=80
    fi
    (( width < 20 )) && width=20
    printf '%d' "$width"
}

# Get terminal height
# @contract.ensure return_value >= 5
# Usage: height=$(tui_term_height)
tui_term_height() {
    local height
    if [[ -t 1 ]]; then
        height=$(tput lines 2>/dev/null) || height=24
    else
        height=24
    fi
    (( height < 5 )) && height=5
    printf '%d' "$height"
}

# Check if terminal is interactive
# Usage: tui_is_interactive && echo "Interactive mode"
tui_is_interactive() {
    [[ -t 0 && -t 1 ]]
}

# Check if colors are supported (respects NO_COLOR)
# Usage: tui_supports_color && echo "Colors supported"
tui_supports_color() {
    ansi_supported
}

# =============================================================================
# COLOR & STYLING FUNCTIONS
# =============================================================================

# Apply color to text (respects NO_COLOR)
# @contract.require color in [black,red,green,yellow,blue,magenta,cyan,white,bright_*]
# Usage: tui_color red "Error text"
# Usage: echo "$(tui_color green "Success")"
tui_color() {
    local color="$1"
    shift
    local text="$*"

    if ! tui_supports_color; then
        printf '%s' "$text"
        return 0
    fi

    case "$color" in
        black)          ansi_black ;;
        red)            ansi_red ;;
        green)          ansi_green ;;
        yellow)         ansi_yellow ;;
        blue)           ansi_blue ;;
        magenta)        ansi_magenta ;;
        cyan)           ansi_cyan ;;
        white)          ansi_white ;;
        bright_black)   ansi_bright_black ;;
        bright_red)     ansi_bright_red ;;
        bright_green)   ansi_bright_green ;;
        bright_yellow)  ansi_bright_yellow ;;
        bright_blue)    ansi_bright_blue ;;
        bright_magenta) ansi_bright_magenta ;;
        bright_cyan)    ansi_bright_cyan ;;
        bright_white)   ansi_bright_white ;;
        [0-9]*)         ansi_color "$color" ;;  # 256-color support
        *)              ;;  # Unknown color, no change
    esac
    printf '%s' "$text"
    ansi_reset
}

# Apply bold formatting to text
# Usage: tui_bold "Important text"
tui_bold() {
    local text="$*"
    if tui_supports_color; then
        ansi_bold
        printf '%s' "$text"
        ansi_reset
    else
        printf '%s' "$text"
    fi
}

# Apply dim formatting to text
# Usage: tui_dim "Muted text"
tui_dim() {
    local text="$*"
    if tui_supports_color; then
        ansi_dim
        printf '%s' "$text"
        ansi_reset
    else
        printf '%s' "$text"
    fi
}

# Apply italic formatting to text
# Usage: tui_italic "Emphasized text"
tui_italic() {
    local text="$*"
    if tui_supports_color; then
        ansi_italic
        printf '%s' "$text"
        ansi_reset
    else
        printf '%s' "$text"
    fi
}

# Apply underline formatting to text
# Usage: tui_underline "Linked text"
tui_underline() {
    local text="$*"
    if tui_supports_color; then
        ansi_underline
        printf '%s' "$text"
        ansi_reset
    else
        printf '%s' "$text"
    fi
}

# Load a color theme
# Usage: tui_theme_load "dark"
# Usage: tui_theme_load "light"
tui_theme_load() {
    local theme_name="$1"

    case "$theme_name" in
        dark)
            _TUI_THEME[primary]="cyan"
            _TUI_THEME[secondary]="blue"
            _TUI_THEME[success]="green"
            _TUI_THEME[warning]="yellow"
            _TUI_THEME[error]="red"
            _TUI_THEME[info]="bright_blue"
            _TUI_THEME[muted]="bright_black"
            _TUI_THEME[accent]="magenta"
            ;;
        light)
            _TUI_THEME[primary]="blue"
            _TUI_THEME[secondary]="cyan"
            _TUI_THEME[success]="green"
            _TUI_THEME[warning]="yellow"
            _TUI_THEME[error]="red"
            _TUI_THEME[info]="blue"
            _TUI_THEME[muted]="bright_black"
            _TUI_THEME[accent]="magenta"
            ;;
        minimal)
            _TUI_THEME[primary]="white"
            _TUI_THEME[secondary]="white"
            _TUI_THEME[success]="white"
            _TUI_THEME[warning]="white"
            _TUI_THEME[error]="white"
            _TUI_THEME[info]="white"
            _TUI_THEME[muted]="bright_black"
            _TUI_THEME[accent]="white"
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

# Get themed color
# Usage: color=$(tui_theme_color "primary")
tui_theme_color() {
    local key="$1"
    printf '%s' "${_TUI_THEME[$key]:-white}"
}

# =============================================================================
# RICH OUTPUT - TABLES
# =============================================================================

# Render ASCII table with borders
# @contract.require data is array of pipe-delimited rows
# @contract.require headers is pipe-delimited string
# Usage: tui_table "Name|Age|City" "Alice|30|NYC" "Bob|25|LA"
tui_table() {
    local -a rows=("$@")
    local -a widths=()
    local -a alignments=()
    local IFS='|'
    local row col cols len i j

    (( ${#rows[@]} == 0 )) && return 0

    # Calculate column widths
    for row in "${rows[@]}"; do
        local -a temp_cols
        IFS='|' read -ra temp_cols <<< "$row"
        i=0
        for col in "${temp_cols[@]}"; do
            # Strip ANSI codes for length calculation
            local stripped
            stripped=$(printf '%s' "$col" | sed 's/\x1b\[[0-9;]*m//g')
            len=${#stripped}
            if (( i >= ${#widths[@]} )); then
                widths+=("$len")
            elif (( len > widths[i] )); then
                widths[i]=$len
            fi
            ((i++))
        done
    done

    # Build horizontal separator
    local separator="${TUI_BOX_TL}"
    for (( i = 0; i < ${#widths[@]}; i++ )); do
        for (( j = 0; j < widths[i] + 2; j++ )); do
            separator+="${TUI_BOX_H}"
        done
        if (( i < ${#widths[@]} - 1 )); then
            separator+="┬"  # T-junction
        fi
    done
    separator+="${TUI_BOX_TR}"

    local middle_sep="├"
    for (( i = 0; i < ${#widths[@]}; i++ )); do
        for (( j = 0; j < widths[i] + 2; j++ )); do
            middle_sep+="${TUI_BOX_H}"
        done
        if (( i < ${#widths[@]} - 1 )); then
            middle_sep+="┼"  # Cross
        fi
    done
    middle_sep+="┤"

    local bottom_sep="${TUI_BOX_BL}"
    for (( i = 0; i < ${#widths[@]}; i++ )); do
        for (( j = 0; j < widths[i] + 2; j++ )); do
            bottom_sep+="${TUI_BOX_H}"
        done
        if (( i < ${#widths[@]} - 1 )); then
            bottom_sep+="┴"  # Upward T
        fi
    done
    bottom_sep+="${TUI_BOX_BR}"

    # Print table
    if tui_supports_color; then
        tui_color "${_TUI_THEME[primary]}" "$separator"
    else
        printf '%s' "$separator"
    fi
    printf '\n'

    local first=1
    for row in "${rows[@]}"; do
        local -a temp_cols
        IFS='|' read -ra temp_cols <<< "$row"

        local line="${TUI_BOX_V}"
        for (( i = 0; i < ${#widths[@]}; i++ )); do
            local val="${temp_cols[i]:-}"
            local stripped
            stripped=$(printf '%s' "$val" | sed 's/\x1b\[[0-9;]*m//g')
            local pad_len=$(( widths[i] - ${#stripped} ))
            local padding=""
            for (( j = 0; j < pad_len; j++ )); do
                padding+=" "
            done
            line+=" ${val}${padding} ${TUI_BOX_V}"
        done

        if (( first )); then
            # Header row - bold
            if tui_supports_color; then
                tui_color "${_TUI_THEME[primary]}" "${TUI_BOX_V}"
                ansi_bold
                printf '%s' "${line:1:${#line}-2}"
                ansi_reset
                tui_color "${_TUI_THEME[primary]}" "${TUI_BOX_V}"
            else
                printf '%s' "$line"
            fi
            printf '\n'

            # Separator after header
            if tui_supports_color; then
                tui_color "${_TUI_THEME[primary]}" "$middle_sep"
            else
                printf '%s' "$middle_sep"
            fi
            printf '\n'
            first=0
        else
            if tui_supports_color; then
                tui_color "${_TUI_THEME[primary]}" "${TUI_BOX_V}"
                printf '%s' "${line:1:${#line}-2}"
                tui_color "${_TUI_THEME[primary]}" "${TUI_BOX_V}"
            else
                printf '%s' "$line"
            fi
            printf '\n'
        fi
    done

    # Bottom border
    if tui_supports_color; then
        tui_color "${_TUI_THEME[primary]}" "$bottom_sep"
    else
        printf '%s' "$bottom_sep"
    fi
    printf '\n'
}

# =============================================================================
# RICH OUTPUT - BOXES & PANELS
# =============================================================================

# Render styled box with title
# Usage: tui_box "Title" "Content line 1" "Content line 2"
# Usage: tui_box "Content only"  # No title if single arg looks like content
tui_box() {
    local title=""
    local -a content=()

    if (( $# == 1 )); then
        content=("$1")
    else
        title="$1"
        shift
        content=("$@")
    fi

    local max_len=0
    local line

    # Include title in width calculation
    if [[ -n "$title" ]]; then
        (( ${#title} + 4 > max_len )) && max_len=$(( ${#title} + 4 ))
    fi

    # Find max content line length
    for line in "${content[@]}"; do
        local stripped
        stripped=$(printf '%s' "$line" | sed 's/\x1b\[[0-9;]*m//g')
        (( ${#stripped} > max_len )) && max_len=${#stripped}
    done

    (( max_len < 10 )) && max_len=10

    # Build horizontal border
    local border=""
    local i
    for (( i = 0; i < max_len + 2; i++ )); do
        border+="$TUI_BOX_H"
    done

    # Print box
    local color="${_TUI_THEME[primary]}"

    if tui_supports_color; then
        tui_color "$color" "${TUI_BOX_TL}"
        if [[ -n "$title" ]]; then
            tui_color "$color" "${TUI_BOX_H}${TUI_BOX_H}"
            ansi_bold
            tui_color "$color" " $title "
            ansi_reset
            local title_len=$(( ${#title} + 4 ))
            for (( i = title_len; i < max_len + 2; i++ )); do
                tui_color "$color" "${TUI_BOX_H}"
            done
        else
            tui_color "$color" "$border"
        fi
        tui_color "$color" "${TUI_BOX_TR}"
    else
        printf '%s' "${TUI_BOX_TL}"
        if [[ -n "$title" ]]; then
            printf '%s%s %s ' "${TUI_BOX_H}${TUI_BOX_H}" "$title"
            local title_len=$(( ${#title} + 4 ))
            for (( i = title_len; i < max_len + 2; i++ )); do
                printf '%s' "${TUI_BOX_H}"
            done
        else
            printf '%s' "$border"
        fi
        printf '%s' "${TUI_BOX_TR}"
    fi
    printf '\n'

    # Content lines
    for line in "${content[@]}"; do
        local stripped
        stripped=$(printf '%s' "$line" | sed 's/\x1b\[[0-9;]*m//g')
        local pad_len=$(( max_len - ${#stripped} ))
        local padding=""
        for (( i = 0; i < pad_len; i++ )); do
            padding+=" "
        done

        if tui_supports_color; then
            tui_color "$color" "${TUI_BOX_V}"
            printf ' %s%s ' "$line" "$padding"
            tui_color "$color" "${TUI_BOX_V}"
        else
            printf '%s %s%s %s' "${TUI_BOX_V}" "$line" "$padding" "${TUI_BOX_V}"
        fi
        printf '\n'
    done

    # Bottom border
    if tui_supports_color; then
        tui_color "$color" "${TUI_BOX_BL}${border}${TUI_BOX_BR}"
    else
        printf '%s%s%s' "${TUI_BOX_BL}" "$border" "${TUI_BOX_BR}"
    fi
    printf '\n'
}

# Render multi-section panel
# Usage: tui_panel "Section1|Content1" "Section2|Content2"
tui_panel() {
    local -a sections=("$@")
    local width=$(tui_term_width)
    (( width > 80 )) && width=80

    local border=""
    local i
    for (( i = 0; i < width - 2; i++ )); do
        border+="${TUI_BOX_DBL_H}"
    done

    local color="${_TUI_THEME[primary]}"

    # Top border
    if tui_supports_color; then
        tui_color "$color" "${TUI_BOX_DBL_TL}${border}${TUI_BOX_DBL_TR}"
    else
        printf '%s%s%s' "${TUI_BOX_DBL_TL}" "$border" "${TUI_BOX_DBL_TR}"
    fi
    printf '\n'

    local first=1
    for section in "${sections[@]}"; do
        local title="${section%%|*}"
        local content="${section#*|}"

        if (( !first )); then
            # Section separator
            local sep_line=""
            for (( i = 0; i < width - 2; i++ )); do
                sep_line+="${TUI_BOX_H}"
            done
            if tui_supports_color; then
                tui_color "$color" "╟${sep_line}╢"
            else
                printf '%s%s%s' "╟" "$sep_line" "╢"
            fi
            printf '\n'
        fi
        first=0

        # Section title
        local title_stripped
        title_stripped=$(printf '%s' "$title" | sed 's/\x1b\[[0-9;]*m//g')
        local title_pad=$(( width - ${#title_stripped} - 4 ))
        local title_padding=""
        for (( i = 0; i < title_pad; i++ )); do
            title_padding+=" "
        done

        if tui_supports_color; then
            tui_color "$color" "${TUI_BOX_DBL_V}"
            printf ' '
            ansi_bold
            printf '%s' "$title"
            ansi_reset
            printf '%s ' "$title_padding"
            tui_color "$color" "${TUI_BOX_DBL_V}"
        else
            printf '%s %s%s %s' "${TUI_BOX_DBL_V}" "$title" "$title_padding" "${TUI_BOX_DBL_V}"
        fi
        printf '\n'

        # Section content
        local content_stripped
        content_stripped=$(printf '%s' "$content" | sed 's/\x1b\[[0-9;]*m//g')
        local content_pad=$(( width - ${#content_stripped} - 4 ))
        local content_padding=""
        for (( i = 0; i < content_pad; i++ )); do
            content_padding+=" "
        done

        if tui_supports_color; then
            tui_color "$color" "${TUI_BOX_DBL_V}"
            printf ' %s%s ' "$content" "$content_padding"
            tui_color "$color" "${TUI_BOX_DBL_V}"
        else
            printf '%s %s%s %s' "${TUI_BOX_DBL_V}" "$content" "$content_padding" "${TUI_BOX_DBL_V}"
        fi
        printf '\n'
    done

    # Bottom border
    if tui_supports_color; then
        tui_color "$color" "${TUI_BOX_DBL_BL}${border}${TUI_BOX_DBL_BR}"
    else
        printf '%s%s%s' "${TUI_BOX_DBL_BL}" "$border" "${TUI_BOX_DBL_BR}"
    fi
    printf '\n'
}

# Render horizontal divider
# Usage: tui_divider
# Usage: tui_divider "=" 40
# Usage: tui_divider "-" 60
tui_divider() {
    local char="${1:-─}"
    local width="${2:-$(tui_term_width)}"

    local line=""
    local i
    for (( i = 0; i < width; i++ )); do
        line+="$char"
    done

    if tui_supports_color; then
        tui_color "${_TUI_THEME[muted]}" "$line"
    else
        printf '%s' "$line"
    fi
    printf '\n'
}

# Render multi-column layout
# Usage: tui_columns "Col1:30|Col2:50|Col3:20" "data1|data2|data3"
tui_columns() {
    local spec="$1"
    shift
    local -a data=("$@")

    # Parse column specifications
    local -a col_widths=()
    local -a col_aligns=()
    local IFS='|'
    local col_spec

    for col_spec in $spec; do
        local name="${col_spec%%:*}"
        local width="${col_spec#*:}"
        if [[ "$width" == "$col_spec" ]]; then
            width=20  # Default width
        fi
        col_widths+=("$width")
    done

    # Render each row
    for row in "${data[@]}"; do
        local -a cells
        IFS='|' read -ra cells <<< "$row"

        local line=""
        local i
        for (( i = 0; i < ${#col_widths[@]}; i++ )); do
            local val="${cells[i]:-}"
            local width="${col_widths[i]}"
            local stripped
            stripped=$(printf '%s' "$val" | sed 's/\x1b\[[0-9;]*m//g')
            local pad_len=$(( width - ${#stripped} ))
            (( pad_len < 0 )) && pad_len=0

            local padding=""
            for (( j = 0; j < pad_len; j++ )); do
                padding+=" "
            done

            line+="${val}${padding}"
        done

        printf '%s\n' "$line"
    done
}

# =============================================================================
# PROGRESS INDICATORS
# =============================================================================

# Render progress bar with percentage
# @contract.require current >= 0
# @contract.require total > 0
# Usage: tui_progress 50 100
# Usage: tui_progress 75  # assumes total=100
tui_progress() {
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
    printf '\r'
    if tui_supports_color; then
        tui_color "${_TUI_THEME[success]}" "$bar"
        printf ' %3d%%' "$percent"
    else
        printf '%s %3d%%' "$bar" "$percent"
    fi
}

# Animated spinner (braille) - start
# Usage: tui_spinner "Processing..."
# Note: Returns immediately, spinner runs in background
tui_spinner() {
    local message="${1:-Processing...}"

    # Stop any existing spinner
    tui_spinner_stop 2>/dev/null

    # Hide cursor
    if tui_supports_color; then
        ansi_hide_cursor
        _TUI_CURSOR_HIDDEN=1
    fi

    # Start spinner in background
    (
        local frames
        IFS=' ' read -ra frames <<< "$TUI_SPINNER_FRAMES"
        local frame_count=${#frames[@]}
        local i=0

        while true; do
            printf '\r%s %s' "${frames[i]}" "$message"
            i=$(( (i + 1) % frame_count ))
            sleep "$TUI_SPINNER_DELAY"
        done
    ) &
    _TUI_SPINNER_PID=$!
    disown "$_TUI_SPINNER_PID" 2>/dev/null
}

# Stop spinner and optionally show result
# Usage: tui_spinner_stop
# Usage: tui_spinner_stop "Done!"
# Usage: tui_spinner_stop "Failed" error
tui_spinner_stop() {
    local message="${1:-}"
    local status="${2:-success}"

    if [[ -n "$_TUI_SPINNER_PID" ]] && kill -0 "$_TUI_SPINNER_PID" 2>/dev/null; then
        kill "$_TUI_SPINNER_PID" 2>/dev/null
        wait "$_TUI_SPINNER_PID" 2>/dev/null
    fi
    _TUI_SPINNER_PID=""

    # Clear line and show cursor
    printf '\r'
    ansi_erase_line

    if tui_supports_color; then
        ansi_show_cursor
        _TUI_CURSOR_HIDDEN=0
    fi

    if [[ -n "$message" ]]; then
        if [[ "$status" == "error" ]]; then
            tui_error "$message"
        else
            tui_success "$message"
        fi
    fi
}

# Gauge/meter display
# Usage: tui_gauge "CPU" 75 100
# Usage: tui_gauge "Memory" 4096 8192
tui_gauge() {
    local label="$1"
    local value="${2:-0}"
    local max="${3:-100}"
    local width="${4:-20}"

    local percent=0
    if (( max > 0 )); then
        percent=$(( (value * 100) / max ))
    fi
    (( percent > 100 )) && percent=100
    (( percent < 0 )) && percent=0

    local filled=$(( (percent * width) / 100 ))
    local empty=$(( width - filled ))

    local bar=""
    local i
    for (( i = 0; i < filled; i++ )); do
        bar+="█"
    done
    for (( i = 0; i < empty; i++ )); do
        bar+="░"
    done

    # Choose color based on percentage
    local color="${_TUI_THEME[success]}"
    if (( percent >= 80 )); then
        color="${_TUI_THEME[error]}"
    elif (( percent >= 60 )); then
        color="${_TUI_THEME[warning]}"
    fi

    printf '%s: [' "$label"
    if tui_supports_color; then
        tui_color "$color" "$bar"
    else
        printf '%s' "$bar"
    fi
    printf '] %3d%%\n' "$percent"
}

# Countdown timer display
# Usage: tui_countdown 10  # Countdown from 10 seconds
tui_countdown() {
    local seconds="${1:-10}"

    if tui_supports_color; then
        ansi_hide_cursor
        _TUI_CURSOR_HIDDEN=1
    fi

    while (( seconds > 0 )); do
        printf '\r'
        if tui_supports_color; then
            if (( seconds <= 3 )); then
                tui_color "${_TUI_THEME[error]}" "$(printf '%02d' "$seconds")"
            else
                tui_color "${_TUI_THEME[warning]}" "$(printf '%02d' "$seconds")"
            fi
        else
            printf '%02d' "$seconds"
        fi
        sleep 1
        (( seconds-- ))
    done

    printf '\r'
    if tui_supports_color; then
        tui_color "${_TUI_THEME[success]}" "00 - Done!"
        ansi_show_cursor
        _TUI_CURSOR_HIDDEN=0
    else
        printf '00 - Done!'
    fi
    printf '\n'
}

# Start elapsed time tracking
# Usage: tui_elapsed_start
tui_elapsed_start() {
    _TUI_ELAPSED_START=$(date +%s)
}

# Display elapsed time since start
# Usage: tui_elapsed  # Shows "1m 30s" etc
tui_elapsed() {
    if [[ -z "$_TUI_ELAPSED_START" ]]; then
        printf '0s'
        return
    fi

    local now
    now=$(date +%s)
    local elapsed=$(( now - _TUI_ELAPSED_START ))

    local hours=$(( elapsed / 3600 ))
    local mins=$(( (elapsed % 3600) / 60 ))
    local secs=$(( elapsed % 60 ))

    local result=""
    (( hours > 0 )) && result+="${hours}h "
    (( mins > 0 || hours > 0 )) && result+="${mins}m "
    result+="${secs}s"

    printf '%s' "$result"
}

# =============================================================================
# INTERACTIVE COMPONENTS
# =============================================================================

# Single selection menu
# @contract.require options is non-empty array
# Usage: choice=$(tui_select "Option 1" "Option 2" "Option 3")
tui_select() {
    local -a options=("$@")
    local count=${#options[@]}

    (( count == 0 )) && return 1

    # Non-interactive: return first option
    if ! tui_is_interactive; then
        printf '%s' "${options[0]}"
        return 0
    fi

    local i
    for (( i = 0; i < count; i++ )); do
        if tui_supports_color; then
            tui_color "${_TUI_THEME[primary]}" "  $((i + 1))) "
            printf '%s\n' "${options[i]}"
        else
            printf '  %d) %s\n' "$((i + 1))" "${options[i]}"
        fi
    done

    local choice
    while true; do
        if tui_supports_color; then
            tui_bold "Select [1-$count]: "
        else
            printf 'Select [1-%d]: ' "$count"
        fi

        read -r choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
            printf '%s' "${options[choice - 1]}"
            return 0
        fi

        printf 'Invalid selection. Please enter 1-%d.\n' "$count"
    done
}

# Multiple selection with checkboxes
# Usage: selections=$(tui_multiselect "Option 1" "Option 2" "Option 3")
# Returns: Newline-separated list of selected options
tui_multiselect() {
    local -a options=("$@")
    local count=${#options[@]}
    local -a selected=()

    (( count == 0 )) && return 1

    # Non-interactive: return nothing
    if ! tui_is_interactive; then
        return 0
    fi

    # Initialize all as unselected
    for (( i = 0; i < count; i++ )); do
        selected+=("0")
    done

    printf 'Use numbers to toggle, Enter to confirm:\n'

    # Render options helper (inline)
    _tui_render_multiselect() {
        local -n _opts=$1
        local -n _sel=$2
        local _cnt=$3
        local _i
        for (( _i = 0; _i < _cnt; _i++ )); do
            local checkbox=" "
            if (( _sel[_i] )); then
                checkbox="✓"
            fi
            if tui_supports_color; then
                tui_color "${_TUI_THEME[primary]}" "  $((_i + 1))) "
                printf '[%s] %s\n' "$checkbox" "${_opts[_i]}"
            else
                printf '  %d) [%s] %s\n' "$((_i + 1))" "$checkbox" "${_opts[_i]}"
            fi
        done
    }

    while true; do
        # Clear and redraw
        printf '\033[%dA' "$count" 2>/dev/null  # Move up
        _tui_render_multiselect options selected "$count"

        if tui_supports_color; then
            tui_bold "Toggle [1-$count] or Enter to confirm: "
        else
            printf 'Toggle [1-%d] or Enter to confirm: ' "$count"
        fi

        local choice
        read -r choice

        # Empty = confirm
        if [[ -z "$choice" ]]; then
            break
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
            local idx=$((choice - 1))
            if (( selected[idx] )); then
                selected[idx]=0
            else
                selected[idx]=1
            fi
        fi
    done

    # Return selected options
    for (( i = 0; i < count; i++ )); do
        if (( selected[i] )); then
            printf '%s\n' "${options[i]}"
        fi
    done
}

# Yes/No confirmation prompt
# Usage: tui_confirm "Continue?" && echo "Confirmed"
# Usage: tui_confirm "Delete all?" "n" && echo "Confirmed"
tui_confirm() {
    local message="${1:-Continue?}"
    local default="${2:-y}"

    # Non-interactive: use default
    if ! tui_is_interactive; then
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
        if tui_supports_color; then
            tui_bold "$message"
            printf ' %s ' "$hint"
        else
            printf '%s %s ' "$message" "$hint"
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

# Text input with optional validation
# Usage: name=$(tui_input "Enter name:" "default")
# Usage: port=$(tui_input "Port:" "8080" "^[0-9]+$")
tui_input() {
    local label="${1:-Enter value:}"
    local default="${2:-}"
    local pattern="${3:-}"

    # Non-interactive: return default
    if ! tui_is_interactive; then
        printf '%s' "$default"
        return 0
    fi

    local hint=""
    if [[ -n "$default" ]]; then
        hint=" [$default]"
    fi

    while true; do
        if tui_supports_color; then
            tui_bold "$label"
            tui_dim "$hint"
            printf ' '
        else
            printf '%s%s ' "$label" "$hint"
        fi

        local value
        read -r value

        # Empty = default
        if [[ -z "$value" ]]; then
            value="$default"
        fi

        # Validate if pattern provided
        if [[ -n "$pattern" ]]; then
            if [[ ! "$value" =~ $pattern ]]; then
                if tui_supports_color; then
                    tui_color "${_TUI_THEME[error]}" "Invalid input. Please try again."
                else
                    printf 'Invalid input. Please try again.'
                fi
                printf '\n'
                continue
            fi
        fi

        printf '%s' "$value"
        return 0
    done
}

# Masked password input
# Usage: password=$(tui_password "Enter password:")
tui_password() {
    local label="${1:-Password:}"

    # Non-interactive: fail
    if ! tui_is_interactive; then
        return 1
    fi

    if tui_supports_color; then
        tui_bold "$label"
        printf ' '
    else
        printf '%s ' "$label"
    fi

    local password
    read -rs password
    printf '\n'

    printf '%s' "$password"
}

# =============================================================================
# STATUS MESSAGES
# =============================================================================

# Success message
# Usage: tui_success "Operation completed"
tui_success() {
    local message="$1"

    if tui_supports_color; then
        tui_color "${_TUI_THEME[success]}" "✓"
        printf ' %s\n' "$message"
    else
        printf '[OK] %s\n' "$message"
    fi
}

# Error message
# Usage: tui_error "Operation failed"
tui_error() {
    local message="$1"

    if tui_supports_color; then
        tui_color "${_TUI_THEME[error]}" "✗"
        printf ' %s\n' "$message" >&2
    else
        printf '[ERROR] %s\n' "$message" >&2
    fi
}

# Warning message
# Usage: tui_warning "Be careful"
tui_warning() {
    local message="$1"

    if tui_supports_color; then
        tui_color "${_TUI_THEME[warning]}" "⚠"
        printf ' %s\n' "$message"
    else
        printf '[WARN] %s\n' "$message"
    fi
}

# Info message
# Usage: tui_info "Information"
tui_info() {
    local message="$1"

    if tui_supports_color; then
        tui_color "${_TUI_THEME[info]}" "ℹ"
        printf ' %s\n' "$message"
    else
        printf '[INFO] %s\n' "$message"
    fi
}

# Debug message (only shows if TUI_DEBUG is set)
# Usage: tui_debug "Debug info"
tui_debug() {
    [[ -z "${TUI_DEBUG:-}" ]] && return 0

    local message="$1"

    if tui_supports_color; then
        tui_dim "[DEBUG] $message"
    else
        printf '[DEBUG] %s' "$message"
    fi
    printf '\n' >&2
}

# =============================================================================
# LEGACY API COMPATIBILITY (tui:: namespace)
# =============================================================================

# Map legacy tui:: functions to new tui_ functions
tui::term_width() { tui_term_width "$@"; }
tui::is_interactive() { tui_is_interactive "$@"; }
tui::supports_color() { tui_supports_color "$@"; }
tui::progress_bar() { tui_progress "$@"; }
tui::progress_start() {
    _TUI_PROGRESS_LABEL="${1:-Progress}"
    tui_progress 0 100
}
tui::progress_update() { tui_progress "$@"; }
tui::progress_done() {
    tui_progress 100 100
    printf '\n'
    tui_success "${1:-Done}"
}
tui::progress_fail() {
    printf '\n'
    tui_error "${1:-Failed}"
}
tui::spin_start() { tui_spinner "$@"; }
tui::spin_stop() { tui_spinner_stop "$@"; }
tui::spin_while() {
    local message="$1"
    shift
    tui_spinner "$message"
    local result=0
    "$@" || result=$?
    if (( result == 0 )); then
        tui_spinner_stop "$message - Done"
    else
        tui_spinner_stop "$message - Failed" error
    fi
    return $result
}
tui::confirm() { tui_confirm "$@"; }
tui::select() { tui_select "$@"; }
tui::input() { tui_input "$@"; }
tui::password() { tui_password "$@"; }
tui::header() {
    local text="$1"
    local width="${2:-$(tui_term_width)}"
    printf '\n'
    tui_divider "=" "$width"
    printf '%s\n' "$text"
    tui_divider "=" "$width"
    printf '\n'
}
tui::box() { tui_box "$@"; }
tui::success() { tui_success "$@"; }
tui::warning() { tui_warning "$@"; }
tui::error() { tui_error "$@"; }
tui::info() { tui_info "$@"; }
tui::debug() { tui_debug "$@"; }
tui::table() { tui_table "$@"; }
tui::hr() { tui_divider "$@"; }

# =============================================================================
# USOP JSON OUTPUT SUPPORT
# =============================================================================

# Output table as JSON (for MAINFRAME_OUTPUT=json mode)
# Usage: tui_table_json "header1|header2" "row1col1|row1col2"
tui_table_json() {
    local -a rows=("$@")
    local IFS='|'

    (( ${#rows[@]} == 0 )) && { printf '[]'; return 0; }

    # First row is headers
    local -a headers
    IFS='|' read -ra headers <<< "${rows[0]}"

    local result='['
    local first=1
    local i

    for (( i = 1; i < ${#rows[@]}; i++ )); do
        (( first )) || result+=','
        first=0

        local -a cols
        IFS='|' read -ra cols <<< "${rows[i]}"

        result+='{'
        local first_col=1
        local j
        for (( j = 0; j < ${#headers[@]}; j++ )); do
            (( first_col )) || result+=','
            first_col=0

            local key="${headers[j]}"
            local val="${cols[j]:-}"

            # Escape JSON strings
            key=$(printf '%s' "$key" | sed 's/\\/\\\\/g; s/"/\\"/g')
            val=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')

            result+="\"$key\":\"$val\""
        done
        result+='}'
    done

    result+=']'
    printf '%s' "$result"
}

# =============================================================================
# CLEANUP
# =============================================================================

# Cleanup on exit
_tui_cleanup() {
    if [[ -n "$_TUI_SPINNER_PID" ]] && kill -0 "$_TUI_SPINNER_PID" 2>/dev/null; then
        kill "$_TUI_SPINNER_PID" 2>/dev/null
    fi
    if [[ "$_TUI_CURSOR_HIDDEN" == "1" ]] && tui_supports_color; then
        ansi_show_cursor
        _TUI_CURSOR_HIDDEN=0
    fi
}

# Register cleanup
if declare -F _mainframe_add_exit_trap >/dev/null 2>&1; then
    _mainframe_add_exit_trap "_tui_cleanup"
else
    trap _tui_cleanup EXIT
fi

# =============================================================================
# MODULE EXPORTS
# =============================================================================

_TUI_EXPORTS=(
    # Terminal utilities
    tui_term_width
    tui_term_height
    tui_is_interactive
    tui_supports_color
    # Color & styling
    tui_color
    tui_bold
    tui_dim
    tui_italic
    tui_underline
    tui_theme_load
    tui_theme_color
    # Rich output
    tui_table
    tui_box
    tui_panel
    tui_divider
    tui_columns
    # Progress indicators
    tui_progress
    tui_spinner
    tui_spinner_stop
    tui_gauge
    tui_countdown
    tui_elapsed_start
    tui_elapsed
    # Interactive components
    tui_select
    tui_multiselect
    tui_confirm
    tui_input
    tui_password
    # Status messages
    tui_success
    tui_error
    tui_warning
    tui_info
    tui_debug
    # USOP support
    tui_table_json
)

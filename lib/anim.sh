#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/anim.sh - Rich CLI Animations Library
# =============================================================================
# Description: 20+ spinner styles, animated progress indicators, and visual
#              effects for terminal applications with theme support.
#
# Features:
#   - Named spinner styles (dots, arrows, bouncing, clock, moon, etc.)
#   - Theme packs (minimal, modern, nerd, playful)
#   - Animated progress bars with multiple styles
#   - ASCII fallback for basic terminals
#   - Background spinner execution with clean termination
#
# @module      anim
# @version     1.0.0
# @requires    ansi.sh
# @provides    30+ animation functions
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_ANIM_LOADED:-}" ]] && return 0
readonly _MAINFRAME_ANIM_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

_ANIM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source ansi.sh if not already loaded
if [[ -z "${_MAINFRAME_ANSI_LOADED:-}" ]]; then
    # shellcheck source=lib/ansi.sh
    source "$_ANIM_LIB_DIR/ansi.sh" 2>/dev/null || true
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default animation settings
ANIM_DELAY="${ANIM_DELAY:-0.08}"
ANIM_THEME="${ANIM_THEME:-modern}"

# Internal state
declare -g _ANIM_SPINNER_PID=""
declare -g _ANIM_CURRENT_STYLE=""
declare -g _ANIM_CURSOR_HIDDEN=0

# =============================================================================
# SPINNER FRAME DEFINITIONS
# =============================================================================

# Modern Unicode spinners (default)
declare -gA ANIM_SPINNERS_MODERN=(
    # Dots family
    [dots]="⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏"
    [dots2]="⣾ ⣽ ⣻ ⢿ ⡿ ⣟ ⣯ ⣷"
    [dots3]="⠋ ⠙ ⠚ ⠞ ⠖ ⠦ ⠴ ⠲ ⠳ ⠓"
    [dots4]="⠄ ⠆ ⠇ ⠋ ⠙ ⠸ ⠰ ⠠ ⠰ ⠸ ⠙ ⠋ ⠇ ⠆"
    [dots5]="⠁ ⠂ ⠄ ⡀ ⢀ ⠠ ⠐ ⠈"
    [dots6]="⠁ ⠁ ⠉ ⠙ ⠚ ⠒ ⠂ ⠂ ⠒ ⠲ ⠴ ⠤ ⠄ ⠄ ⠤ ⠠ ⠠ ⠤ ⠦ ⠖ ⠒ ⠐ ⠐ ⠒ ⠓ ⠋ ⠉ ⠈ ⠈"
    [dots7]="⠈ ⠉ ⠋ ⠓ ⠒ ⠐ ⠐ ⠒ ⠖ ⠦ ⠤ ⠠ ⠠ ⠤ ⠦ ⠖ ⠒ ⠐ ⠐ ⠒ ⠓ ⠋ ⠉ ⠈"
    [dots8]="⠁ ⠉ ⠙ ⠚ ⠒ ⠂ ⠂ ⠒ ⠲ ⠴ ⠤ ⠄ ⠄ ⠤ ⠴ ⠲ ⠒ ⠂ ⠂ ⠒ ⠚ ⠙ ⠉ ⠁"
    [dots9]="⢹ ⢺ ⢼ ⣸ ⣇ ⡧ ⡗ ⡏"
    [dots10]="⢄ ⢂ ⢁ ⡁ ⡈ ⡐ ⡠"
    [dots11]="⠁ ⠂ ⠄ ⡀ ⡈ ⡐ ⡠ ⣀ ⣁ ⣂ ⣄ ⣌ ⣔ ⣤ ⣥ ⣦ ⣮ ⣶ ⣷ ⣿ ⡿ ⠿ ⢟ ⠟ ⡛ ⠛ ⠫ ⢋ ⠋ ⠍ ⡉ ⠉ ⠑ ⠡ ⢁"
    [dots12]="⢀⠀ ⡀⠀ ⠄⠀ ⢂⠀ ⡂⠀ ⠅⠀ ⢃⠀ ⡃⠀ ⠍⠀ ⢋⠀ ⡋⠀ ⠍⠁ ⢋⠁ ⡋⠁ ⠍⠉ ⠋⠉ ⠋⠉ ⠉⠙ ⠉⠙ ⠉⠩ ⠈⢙ ⠈⡙ ⢈⠩ ⡂⢐ ⠅⡐ ⢁⠠ ⡁⠠ ⠁⡀ ⢁⠀ ⡀⠀ ⠄⠀ ⠂⠀"

    # Lines and bars
    [line]="- \\ | /"
    [line2]="⠂ - – — – -"
    [pipe]="┤ ┘ ┴ └ ├ ┌ ┬ ┐"
    [simpleDots]="⠁ ⠂ ⠄ ⠂"
    [simpleDotsScrolling]="⠁ ⠉ ⠙ ⠸ ⢰ ⣠ ⣄ ⡆ ⠇ ⠋"

    # Arrows
    [arrow]="← ↖ ↑ ↗ → ↘ ↓ ↙"
    [arrow2]="⬆️  ↗️  ➡️  ↘️  ⬇️  ↙️  ⬅️  ↖️ "
    [arrow3]="▹▹▹▹▹ ▸▹▹▹▹ ▹▸▹▹▹ ▹▹▸▹▹ ▹▹▹▸▹ ▹▹▹▹▸"
    [bouncingBar]="[    ] [=   ] [==  ] [=== ] [====] [ ===] [  ==] [   =] [    ]"
    [bouncingBall]="( ●    ) (  ●   ) (   ●  ) (    ● ) (   ●  ) (  ●   ) ( ●    ) (●     )"

    # Shapes
    [triangle]="◢ ◣ ◤ ◥"
    [arc]="◜ ◝ ◞ ◟"
    [circle]="◡ ⊙ ◠"
    [squareCorners]="◰ ◳ ◲ ◱"
    [circleQuarters]="◴ ◷ ◶ ◵"
    [circleHalves]="◐ ◓ ◑ ◒"
    [squish]="╫ ╪"
    [toggle]="⊶ ⊷"
    [toggle2]="▫ ▪"
    [toggle3]="□ ■"
    [toggle4]="■ □ ▪ ▫"
    [toggle5]="▮ ▯"
    [toggle6]="ဝ ၀"
    [toggle7]="⦾ ⦿"
    [toggle8]="◍ ◌"
    [toggle9]="◉ ◎"
    [toggle10]="㊂ ㊀ ㊁"
    [toggle11]="⧇ ⧆"
    [toggle12]="☗ ☖"
    [toggle13]="= * -"

    # Bouncing
    [bounce]="⠁ ⠂ ⠄ ⠂"
    [boxBounce]="▖ ▘ ▝ ▗"
    [boxBounce2]="▌ ▀ ▐ ▄"

    # Clock
    [clock]="🕛  🕐  🕑  🕒  🕓  🕔  🕕  🕖  🕗  🕘  🕙  🕚 "

    # Earth and Moon
    [earth]="🌍  🌎  🌏 "
    [moon]="🌑  🌒  🌓  🌔  🌕  🌖  🌗  🌘 "

    # Weather
    [weather]="☀️  🌤  ⛅  🌥  ☁️  🌧  ⛈  🌩  🌨 "

    # Growing
    [growVertical]="▁ ▃ ▄ ▅ ▆ ▇ █ ▇ ▆ ▅ ▄ ▃"
    [growHorizontal]="▏ ▎ ▍ ▌ ▋ ▊ ▉ █ ▉ ▊ ▋ ▌ ▍ ▎"
    [balloon]=" . o O @ * "
    [balloon2]=" . o O ° O o ."
    [noise]="▓ ▒ ░"
    [grenade]="،   ′  ´  ‾  ⁻  ⁼  ⁺  ⁺  ⁺  ⁺  ≡  ≡  ≡"
    [point]="∙∙∙ ●∙∙ ∙●∙ ∙∙● ∙∙∙"
    [layer]="-  =  ≡  ≡  =  -"

    # Tech themed
    [binary]="010010 001100 100101 111010 101011 000111"
    [pong]="▐⠂       ▌ ▐⠈       ▌ ▐ ⠂      ▌ ▐ ⠠      ▌ ▐  ⡀     ▌ ▐  ⠠     ▌ ▐   ⠂    ▌ ▐   ⠈    ▌ ▐    ⠂   ▌ ▐    ⠠   ▌ ▐     ⡀  ▌ ▐     ⠠  ▌ ▐      ⠂ ▌ ▐      ⠈ ▌ ▐       ⠂▌ ▐       ⠠▌ ▐       ⡀▌ ▐      ⠠ ▌ ▐      ⠂ ▌ ▐     ⠈  ▌ ▐     ⠂  ▌ ▐    ⠠   ▌ ▐    ⡀   ▌ ▐   ⠠    ▌ ▐   ⠂    ▌ ▐  ⠈     ▌ ▐  ⠂     ▌ ▐ ⠠      ▌ ▐ ⡀      ▌ ▐⠠       ▌"

    # Aesthetic
    [aesthetic]="▰▱▱▱▱▱▱ ▰▰▱▱▱▱▱ ▰▰▰▱▱▱▱ ▰▰▰▰▱▱▱ ▰▰▰▰▰▱▱ ▰▰▰▰▰▰▱ ▰▰▰▰▰▰▰ ▱▰▰▰▰▰▰ ▱▱▰▰▰▰▰ ▱▱▱▰▰▰▰ ▱▱▱▱▰▰▰ ▱▱▱▱▱▰▰ ▱▱▱▱▱▱▰"

    # Fun
    [shark]="▐|\\____________▌ ▐_|\\___________▌ ▐__|\\__________▌ ▐___|\\_________▌ ▐____|\\________▌ ▐_____|\\_______▌ ▐______|\\______▌ ▐_______|\\_____▌ ▐________|\\____▌ ▐_________|\\___▌ ▐__________|\\__▌ ▐___________|\\_▌ ▐____________|\\▌ ▐____________/|▌ ▐___________/|_▌ ▐__________/|__▌ ▐_________/|___▌ ▐________/|____▌ ▐_______/|_____▌ ▐______/|______▌ ▐_____/|_______▌ ▐____/|________▌ ▐___/|_________▌ ▐__/|__________▌ ▐_/|___________▌ ▐/|____________▌"
    [dqpb]="d q p b"
    [runner]="🚶  🏃 "
    [smiley]="😄  😝 "
    [monkey]="🙈  🙈  🙉  🙊 "
    [hearts]="💛  💙  💜  💚  ❤️ "
    [star]="✶ ✸ ✹ ✺ ✹ ✷"
    [star2]="+ x *"
    [hamburger]="☱ ☲ ☴"
    [fingerDance]="🤘  🤟  🖖  ✋  🤚  👆 "
    [fistBump]="🤜　　　　🤛 🤜　　　🤛  🤜　　🤛   🤜　🤛    🤜🤛     ✨🤜🤛✨    🤜🤛     🤜　🤛    🤜　　🤛   🤜　　　🤛  🤜　　　　🤛"
    [mindblown]="😐  😐  😮  😮  😦  😦  😧  😧  🤯  💥  ✨  　  　  　 "
    [flip]="_ _ _ - ` ` ' ´ - - _ _"
    [speaker]="🔈  🔉  🔊  🔉 "
    [orangePulse]="🔸  🔶  🟠  🟠  🔶 "
    [bluePulse]="🔹  🔷  🔵  🔵  🔷 "
    [orangeBluePulse]="🔸  🔶  🟠  🟠  🔶  🔷  🔵  🔵  🔷  🔹 "
    [christmas]="🌲  🎄 "
    [santa]="🌑  🌒  🌓  🌔  🌕  🎅  🌖  🌗  🌘 "
)

# Minimal ASCII spinners (for basic terminals)
declare -gA ANIM_SPINNERS_MINIMAL=(
    [dots]=". .. ... ...."
    [line]="- \\ | /"
    [arrow]="<- ^ -> v"
    [bounce]="o O o ."
    [bar]="[    ] [=   ] [==  ] [=== ] [====] [ ===] [  ==] [   =]"
    [pipe]=". o O 0 O o"
    [spinner]="|/-\\"
    [triangle]="v < ^ >"
    [wave]="_ . - ' - . _"
    [blink]="*  "
    [pulse]=". o O o"
    [loading]="[.  ] [.. ] [...] [ ..] [  .] [   ]"
)

# Nerd Font spinners (requires Nerd Fonts installed)
declare -gA ANIM_SPINNERS_NERD=(
    [dots]="󰪞 󰪟 󰪠 󰪡 󰪢 󰪣 󰪤 󰪥"
    [circle]="󰝦 󰪞 󰪟 󰪠 󰪡 󰪢 󰪣 󰪤 󰪥"
    [arrow]="󰁍 󰁎 󰁏 󰁐 󰁑"
    [moon]="󰽤 󰽥 󰽦 󰽧 󰽨"
    [clock]="󱑋 󱑌 󱑍 󱑎 󱑏 󱑐 󱑑 󱑒 󱑓 󱑔 󱑕 󱑖"
    [weather]="󰖙 󰖚 󰖛 󰖜 󰖝"
    [cog]="󰒓 󰒔 󰒕 󰒖"
    [sync]="󰑐 󰑑"
    [loading]="󰝦 󰪞 󰪟 󰪠 󰪡 󰪢 󰪣 󰪤 󰪥"
    [fire]="󰈸 󱠇 󱗔"
)

# Playful emoji spinners
declare -gA ANIM_SPINNERS_PLAYFUL=(
    [dots]="🔴 🟠 🟡 🟢 🔵 🟣"
    [animals]="🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼"
    [food]="🍎 🍊 🍋 🍇 🫐 🍓"
    [weather]="☀️ 🌤 ⛅ 🌥 ☁️ 🌧 ⛈ 🌩"
    [sports]="⚽ 🏀 🏈 ⚾ 🎾 🏐"
    [hands]="👆 👉 👇 👈"
    [faces]="😀 😃 😄 😁 😆 😅 🤣 😂"
    [hearts]="❤️ 🧡 💛 💚 💙 💜"
    [space]="🌍 🌎 🌏 🌑 🌒 🌓 🌔 🌕 🌖 🌗 🌘"
    [fire]="🔥 💥 ✨ 💫 ⭐"
    [music]="🎵 🎶 🎼 🎹 🎸 🎺"
    [party]="🎉 🎊 🎈 🎁 🎀"
    [rocket]="🚀 💨 ✨ 🌟 ⭐"
    [loading]="⏳ ⌛"
)

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Check if ANSI/Unicode is supported
_anim_supports_unicode() {
    # Check TERM and locale
    [[ -z "${NO_COLOR:-}" ]] && \
    [[ "${TERM:-}" != "dumb" ]] && \
    [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" == *UTF* || "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" == *utf* ]]
}

# Get frames for a spinner by name and theme
_anim_get_frames() {
    local name="$1"
    local theme="${2:-$ANIM_THEME}"
    local frames=""

    case "$theme" in
        minimal|ascii)
            frames="${ANIM_SPINNERS_MINIMAL[$name]:-}"
            ;;
        nerd)
            frames="${ANIM_SPINNERS_NERD[$name]:-}"
            ;;
        playful|emoji)
            frames="${ANIM_SPINNERS_PLAYFUL[$name]:-}"
            ;;
        modern|unicode|*)
            frames="${ANIM_SPINNERS_MODERN[$name]:-}"
            ;;
    esac

    # Fallback to modern if not found in theme
    if [[ -z "$frames" ]]; then
        frames="${ANIM_SPINNERS_MODERN[$name]:-${ANIM_SPINNERS_MODERN[dots]}}"
    fi

    printf '%s' "$frames"
}

# =============================================================================
# PUBLIC API - SPINNER FUNCTIONS
# =============================================================================

# List available spinner styles for current theme
# @description List all available spinner style names
# @param       $1 [theme] - Theme name (default: current theme)
# @stdout      Space-separated list of spinner names
# @return      0 always
#
# Usage: spinner_list
# Usage: spinner_list minimal
spinner_list() {
    local theme="${1:-$ANIM_THEME}"
    local -a names=()

    case "$theme" in
        minimal|ascii)
            names=("${!ANIM_SPINNERS_MINIMAL[@]}")
            ;;
        nerd)
            names=("${!ANIM_SPINNERS_NERD[@]}")
            ;;
        playful|emoji)
            names=("${!ANIM_SPINNERS_PLAYFUL[@]}")
            ;;
        modern|unicode|*)
            names=("${!ANIM_SPINNERS_MODERN[@]}")
            ;;
    esac

    printf '%s\n' "${names[@]}" | sort
}

# Preview a spinner animation (for testing)
# @description Display spinner animation for a few seconds
# @param       $1 name - Spinner style name
# @param       $2 [duration] - Duration in seconds (default: 3)
# @param       $3 [theme] - Theme override
# @return      0 always
#
# Usage: spinner_preview dots
# Usage: spinner_preview moon 5
# Usage: spinner_preview dots 3 playful
spinner_preview() {
    local name="${1:-dots}"
    local duration="${2:-3}"
    local theme="${3:-$ANIM_THEME}"

    local frames
    frames=$(_anim_get_frames "$name" "$theme")

    local -a frame_arr
    IFS=' ' read -ra frame_arr <<< "$frames"
    local frame_count=${#frame_arr[@]}
    local iterations=$(( duration * 10 ))  # ~10 fps

    printf 'Previewing: %s (%s theme)\n' "$name" "$theme"

    # Hide cursor
    if _anim_supports_unicode; then
        printf '\033[?25l'
        _ANIM_CURSOR_HIDDEN=1
    fi

    local i=0
    local f=0
    while (( i < iterations )); do
        printf '\r  %s  ' "${frame_arr[f]}"
        f=$(( (f + 1) % frame_count ))
        sleep 0.1
        ((i++))
    done

    # Show cursor and newline
    printf '\033[?25h\n'
    _ANIM_CURSOR_HIDDEN=0
}

# Start a named spinner animation
# @description Start a spinner running in the background
# @param       $1 name - Spinner style name (dots, arrow, moon, etc.)
# @param       $2 [message] - Optional status message
# @param       --theme - Override current theme
# @param       --color - Color for the spinner
# @param       --delay - Animation delay (default: 0.08)
# @return      0 on success
#
# Usage: spinner_start dots "Loading..."
# Usage: spinner_start moon "Processing" --color cyan
# Usage: spinner_start arrow "Working" --theme minimal
spinner_start() {
    local name="${1:-dots}"
    local message="${2:-}"
    shift 2 2>/dev/null || shift $#

    local theme="$ANIM_THEME"
    local color=""
    local delay="$ANIM_DELAY"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --theme)
                theme="$2"
                shift 2
                ;;
            --color)
                color="$2"
                shift 2
                ;;
            --delay)
                delay="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Stop any existing spinner
    spinner_stop 2>/dev/null

    # Get frames
    local frames
    frames=$(_anim_get_frames "$name" "$theme")

    # Store current style
    _ANIM_CURRENT_STYLE="$name"

    # Hide cursor
    if _anim_supports_unicode; then
        printf '\033[?25l'
        _ANIM_CURSOR_HIDDEN=1
    fi

    # Start spinner in background
    (
        local -a frame_arr
        IFS=' ' read -ra frame_arr <<< "$frames"
        local frame_count=${#frame_arr[@]}
        local i=0

        while true; do
            local frame="${frame_arr[i]}"

            # Apply color if specified
            if [[ -n "$color" ]] && _anim_supports_unicode; then
                case "$color" in
                    red)     printf '\r\033[31m%s\033[0m %s' "$frame" "$message" ;;
                    green)   printf '\r\033[32m%s\033[0m %s' "$frame" "$message" ;;
                    yellow)  printf '\r\033[33m%s\033[0m %s' "$frame" "$message" ;;
                    blue)    printf '\r\033[34m%s\033[0m %s' "$frame" "$message" ;;
                    magenta) printf '\r\033[35m%s\033[0m %s' "$frame" "$message" ;;
                    cyan)    printf '\r\033[36m%s\033[0m %s' "$frame" "$message" ;;
                    *)       printf '\r%s %s' "$frame" "$message" ;;
                esac
            else
                printf '\r%s %s' "$frame" "$message"
            fi

            i=$(( (i + 1) % frame_count ))
            sleep "$delay"
        done
    ) &
    _ANIM_SPINNER_PID=$!
    disown "$_ANIM_SPINNER_PID" 2>/dev/null
}

# Stop the current spinner
# @description Stop the running spinner and show result
# @param       $1 [message] - Final status message
# @param       $2 [status] - success|error|warn (affects icon)
# @return      0 always
#
# Usage: spinner_stop
# Usage: spinner_stop "Done!"
# Usage: spinner_stop "Failed" error
spinner_stop() {
    local message="${1:-}"
    local status="${2:-success}"

    if [[ -n "$_ANIM_SPINNER_PID" ]] && kill -0 "$_ANIM_SPINNER_PID" 2>/dev/null; then
        kill "$_ANIM_SPINNER_PID" 2>/dev/null
        wait "$_ANIM_SPINNER_PID" 2>/dev/null
    fi
    _ANIM_SPINNER_PID=""
    _ANIM_CURRENT_STYLE=""

    # Clear line
    printf '\r\033[K'

    # Show cursor
    if [[ "$_ANIM_CURSOR_HIDDEN" == "1" ]]; then
        printf '\033[?25h'
        _ANIM_CURSOR_HIDDEN=0
    fi

    # Show result message with status icon
    if [[ -n "$message" ]]; then
        if _anim_supports_unicode; then
            case "$status" in
                success)
                    printf '\033[32m✓\033[0m %s\n' "$message"
                    ;;
                error|fail)
                    printf '\033[31m✗\033[0m %s\n' "$message" >&2
                    ;;
                warn|warning)
                    printf '\033[33m⚠\033[0m %s\n' "$message"
                    ;;
                *)
                    printf '%s\n' "$message"
                    ;;
            esac
        else
            case "$status" in
                success)  printf '[OK] %s\n' "$message" ;;
                error)    printf '[ERROR] %s\n' "$message" >&2 ;;
                warn)     printf '[WARN] %s\n' "$message" ;;
                *)        printf '%s\n' "$message" ;;
            esac
        fi
    fi
}

# Run a command with spinner
# @description Execute command while showing spinner, handle result
# @param       $1 name - Spinner style name
# @param       $2 message - Status message
# @param       $@ - Command and arguments to execute
# @return      Exit code of the command
#
# Usage: spinner_while dots "Installing..." npm install
# Usage: spinner_while moon "Processing" ./long_script.sh
spinner_while() {
    local name="$1"
    local message="$2"
    shift 2

    spinner_start "$name" "$message"

    local result=0
    "$@" >/dev/null 2>&1 || result=$?

    if (( result == 0 )); then
        spinner_stop "$message - Done" success
    else
        spinner_stop "$message - Failed" error
    fi

    return $result
}

# =============================================================================
# PUBLIC API - ANIMATED PROGRESS BARS
# =============================================================================

# Animated progress bar with style options
# @description Display animated progress bar
# @param       $1 current - Current value
# @param       $2 total - Total value
# @param       --width - Bar width (default: 40)
# @param       --style - bar|gradient|blocks|dots
# @param       --label - Optional label prefix
# @return      0 always
#
# Usage: progress_bar 50 100
# Usage: progress_bar 75 100 --style gradient --label "Download"
progress_bar() {
    local current="${1:-0}"
    local total="${2:-100}"
    shift 2 2>/dev/null || shift $#

    local width=40
    local style="bar"
    local label=""
    local color="green"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --width)
                width="$2"
                shift 2
                ;;
            --style)
                style="$2"
                shift 2
                ;;
            --label)
                label="$2"
                shift 2
                ;;
            --color)
                color="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Calculate percentage
    local percent=0
    if (( total > 0 )); then
        percent=$(( (current * 100) / total ))
    fi
    (( percent > 100 )) && percent=100
    (( percent < 0 )) && percent=0

    local filled=$(( (percent * width) / 100 ))
    local empty=$(( width - filled ))

    local bar=""
    local fill_char="█"
    local empty_char="░"

    case "$style" in
        gradient)
            # Gradient from dark to light
            local chars="░▒▓█"
            local i
            for (( i = 0; i < filled; i++ )); do
                local pos=$(( (i * 3) / width ))
                bar+="${chars:pos:1}"
            done
            for (( i = 0; i < empty; i++ )); do
                bar+=" "
            done
            ;;
        blocks)
            fill_char="▰"
            empty_char="▱"
            local i
            for (( i = 0; i < filled; i++ )); do bar+="$fill_char"; done
            for (( i = 0; i < empty; i++ )); do bar+="$empty_char"; done
            ;;
        dots)
            fill_char="●"
            empty_char="○"
            local i
            for (( i = 0; i < filled; i++ )); do bar+="$fill_char"; done
            for (( i = 0; i < empty; i++ )); do bar+="$empty_char"; done
            ;;
        bar|*)
            local i
            for (( i = 0; i < filled; i++ )); do bar+="$fill_char"; done
            for (( i = 0; i < empty; i++ )); do bar+="$empty_char"; done
            ;;
    esac

    # Output
    printf '\r'
    if [[ -n "$label" ]]; then
        printf '%s ' "$label"
    fi

    if _anim_supports_unicode; then
        case "$color" in
            red)     printf '\033[31m%s\033[0m' "$bar" ;;
            green)   printf '\033[32m%s\033[0m' "$bar" ;;
            yellow)  printf '\033[33m%s\033[0m' "$bar" ;;
            blue)    printf '\033[34m%s\033[0m' "$bar" ;;
            cyan)    printf '\033[36m%s\033[0m' "$bar" ;;
            *)       printf '%s' "$bar" ;;
        esac
    else
        printf '%s' "$bar"
    fi

    printf ' %3d%%' "$percent"
}

# Indeterminate progress (bouncing animation)
# @description Show indeterminate progress indicator
# @param       $1 [message] - Status message
# @param       --width - Bar width (default: 20)
# @return      0 always
#
# Usage: progress_indeterminate "Loading..."
progress_indeterminate_start() {
    local message="${1:-}"
    local width=20

    # Hide cursor
    printf '\033[?25l'
    _ANIM_CURSOR_HIDDEN=1

    (
        local pos=0
        local dir=1
        local bar_width=3

        while true; do
            local bar=""
            local i

            for (( i = 0; i < width; i++ )); do
                if (( i >= pos && i < pos + bar_width )); then
                    bar+="█"
                else
                    bar+="░"
                fi
            done

            printf '\r[%s] %s' "$bar" "$message"

            # Move position
            pos=$((pos + dir))
            if (( pos >= width - bar_width )); then
                dir=-1
            elif (( pos <= 0 )); then
                dir=1
            fi

            sleep 0.05
        done
    ) &
    _ANIM_SPINNER_PID=$!
    disown "$_ANIM_SPINNER_PID" 2>/dev/null
}

# Stop indeterminate progress
progress_indeterminate_stop() {
    spinner_stop "$@"
}

# =============================================================================
# PUBLIC API - THEME MANAGEMENT
# =============================================================================

# Set animation theme
# @description Set the global animation theme
# @param       $1 theme - Theme name (minimal, modern, nerd, playful)
# @return      0 on success, 1 on invalid theme
#
# Usage: anim_theme modern
# Usage: anim_theme minimal  # For basic terminals
anim_theme() {
    local theme="$1"

    case "$theme" in
        minimal|ascii|modern|unicode|nerd|playful|emoji)
            ANIM_THEME="$theme"
            return 0
            ;;
        *)
            printf 'Unknown theme: %s\n' "$theme" >&2
            printf 'Available: minimal, modern, nerd, playful\n' >&2
            return 1
            ;;
    esac
}

# Auto-detect best theme for current terminal
# @description Detect and set the best theme for current terminal
# @return      0 always
#
# Usage: anim_theme_auto
anim_theme_auto() {
    if [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
        ANIM_THEME="minimal"
    elif [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" != *UTF* && "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" != *utf* ]]; then
        ANIM_THEME="minimal"
    else
        ANIM_THEME="modern"
    fi
}

# =============================================================================
# PUBLIC API - VISUAL EFFECTS
# =============================================================================

# Typewriter effect
# @description Print text with typewriter animation
# @param       $1 text - Text to display
# @param       $2 [delay] - Delay between characters (default: 0.03)
# @return      0 always
#
# Usage: typewriter "Hello, World!"
# Usage: typewriter "Slow text" 0.1
typewriter() {
    local text="$1"
    local delay="${2:-0.03}"
    local i

    for (( i = 0; i < ${#text}; i++ )); do
        printf '%s' "${text:i:1}"
        sleep "$delay"
    done
    printf '\n'
}

# Reveal effect (character by character with random order)
# @description Print text with reveal animation
# @param       $1 text - Text to display
# @param       $2 [delay] - Delay between reveals (default: 0.02)
# @return      0 always
#
# Usage: reveal "Secret message"
reveal() {
    local text="$1"
    local delay="${2:-0.02}"
    local len=${#text}
    local -a revealed
    local count=0

    # Initialize with underscores
    for (( i = 0; i < len; i++ )); do
        if [[ "${text:i:1}" == " " ]]; then
            revealed[i]=" "
            ((count++))
        else
            revealed[i]="_"
        fi
    done

    # Reveal characters one by one
    while (( count < len )); do
        local pos=$(( RANDOM % len ))

        if [[ "${revealed[pos]}" == "_" ]]; then
            revealed[pos]="${text:pos:1}"
            ((count++))

            printf '\r%s' "${revealed[*]}"
            sleep "$delay"
        fi
    done
    printf '\n'
}

# Glitch effect
# @description Print text with glitch animation
# @param       $1 text - Text to display
# @param       $2 [iterations] - Number of glitch iterations (default: 10)
# @return      0 always
#
# Usage: glitch "MAINFRAME"
glitch() {
    local text="$1"
    local iterations="${2:-10}"
    local glitch_chars="!@#$%^&*()_+-=[]{}|;':\",./<>?"
    local len=${#text}

    local i j
    for (( i = 0; i < iterations; i++ )); do
        local glitched=""
        for (( j = 0; j < len; j++ )); do
            if (( RANDOM % 4 == 0 )); then
                # Replace with random glitch character
                local gchar="${glitch_chars:RANDOM % ${#glitch_chars}:1}"
                glitched+="$gchar"
            else
                glitched+="${text:j:1}"
            fi
        done
        printf '\r%s' "$glitched"
        sleep 0.05
    done

    # Final clean text
    printf '\r%s\n' "$text"
}

# Rainbow text (if color supported)
# @description Print text with rainbow colors
# @param       $1 text - Text to display
# @return      0 always
#
# Usage: rainbow "Colorful text!"
rainbow() {
    local text="$1"
    local colors=(31 33 32 36 34 35)  # Red, Yellow, Green, Cyan, Blue, Magenta
    local len=${#text}
    local i

    if ! _anim_supports_unicode; then
        printf '%s\n' "$text"
        return 0
    fi

    for (( i = 0; i < len; i++ )); do
        local color_idx=$(( i % ${#colors[@]} ))
        printf '\033[%dm%s' "${colors[color_idx]}" "${text:i:1}"
    done
    printf '\033[0m\n'
}

# =============================================================================
# CLEANUP
# =============================================================================

_anim_cleanup() {
    if [[ -n "$_ANIM_SPINNER_PID" ]] && kill -0 "$_ANIM_SPINNER_PID" 2>/dev/null; then
        kill "$_ANIM_SPINNER_PID" 2>/dev/null
    fi
    if [[ "$_ANIM_CURSOR_HIDDEN" == "1" ]]; then
        printf '\033[?25h'
        _ANIM_CURSOR_HIDDEN=0
    fi
}

if declare -F _mainframe_add_exit_trap >/dev/null 2>&1; then
    _mainframe_add_exit_trap "_anim_cleanup"
else
    trap _anim_cleanup EXIT
fi

# =============================================================================
# AUTO-DETECT THEME ON LOAD
# =============================================================================

anim_theme_auto

# =============================================================================
# MODULE EXPORTS
# =============================================================================

_ANIM_EXPORTS=(
    # Spinner functions
    spinner_list
    spinner_preview
    spinner_start
    spinner_stop
    spinner_while
    # Progress functions
    progress_bar
    progress_indeterminate_start
    progress_indeterminate_stop
    # Theme functions
    anim_theme
    anim_theme_auto
    # Visual effects
    typewriter
    reveal
    glitch
    rainbow
)

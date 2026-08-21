#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/pure-util.sh - Pure Bash Utilities
# =============================================================================
# Description: General utilities without external tools
# Source: Inspired by Pure Bash Bible
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
if [[ -n "${_MAINFRAME_PURE_UTIL_LOADED:-}" ]]; then
    # common.sh may replay the reviewed full closure after a narrower tier was
    # loaded. Re-apply this canonical collision owner without weakening the
    # normal double-source guard.
    [[ "${_MAINFRAME_CANONICAL_REPLAY:-0}" == "1" ]] || return 0
else
    readonly _MAINFRAME_PURE_UTIL_LOADED=1
fi

# =============================================================================
# TIME & DATE
# =============================================================================

# Get current timestamp
# Usage: timestamp
timestamp() {
    printf '%(%Y-%m-%d %H:%M:%S)T\n' -1
}

# Get ISO timestamp
# Usage: timestamp_iso
timestamp_iso() {
    printf '%(%Y-%m-%dT%H:%M:%S%z)T\n' -1
}

# Get epoch seconds
# Usage: epoch
epoch() {
    printf '%(%s)T\n' -1
}

# Get epoch milliseconds (approximation)
# Usage: epoch_ms
epoch_ms() {
    printf '%(%s)T000\n' -1
}

# Format the current date/time with a strftime format.
# Usage: format_current_date "%Y-%m-%d"
format_current_date() {
    local format="${1:-%Y-%m-%d}"
    printf "%(${format})T\n" -1
}

# Format either an epoch as YYYY-MM-DD or the current time with strftime.
# Usage: format_date 0             # 1970-01-01 in UTC
# Usage: format_date "%Y-%m-%d"   # Current date
format_date() {
    local value="${1:--1}"

    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
        printf '%(%Y-%m-%d)T\n' "$value"
    else
        format_current_date "$value"
    fi
}

# Get day of week
# Usage: day_of_week
day_of_week() {
    printf '%(%A)T\n' -1
}

# =============================================================================
# UUID / RANDOM
# =============================================================================

# Generate UUID v4
# Usage: uuid
uuid() {
    local C="89ab"
    for ((N=0;N<16;++N)); do
        local B="$((RANDOM%256))"
        case "$N" in
            6) printf '4%x' "$((B%16))" ;;
            8) printf '%c%x' "${C:$RANDOM%${#C}:1}" "$((B%16))" ;;
            3|5|7|9) printf '%02x-' "$B" ;;
            *) printf '%02x' "$B" ;;
        esac
    done
    printf '\n'
}

# Generate random string
# Usage: random_string 16
random_string() {
    local len="${1:-16}"
    local chars='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local result=""

    for ((i=0; i<len; i++)); do
        result+="${chars:RANDOM%${#chars}:1}"
    done
    printf '%s\n' "$result"
}

# Generate random number in range
# Usage: random_range 1 100
random_range() {
    local min="${1:-0}"
    local max="${2:-100}"
    printf '%d\n' "$((RANDOM % (max - min + 1) + min))"
}

# Generate random hex string
# Usage: random_hex 8
random_hex() {
    local len="${1:-8}"
    local result=""
    for ((i=0; i<len; i++)); do
        printf '%x' "$((RANDOM % 16))"
    done
    printf '\n'
}

# =============================================================================
# COLOR CONVERSION
# =============================================================================

# Hex to RGB
# Usage: hex_to_rgb "#ff5500"
hex_to_rgb() {
    : "${1/\#}"
    local r=$((16#${_:0:2}))
    local g=$((16#${_:2:2}))
    local b=$((16#${_:4:2}))
    printf '%d %d %d\n' "$r" "$g" "$b"
}

# RGB to Hex
# Usage: rgb_to_hex 255 85 0
rgb_to_hex() {
    printf '#%02x%02x%02x\n' "$1" "$2" "$3"
}

# =============================================================================
# TERMINAL
# =============================================================================

# Get terminal size
# Usage: term_size  # Returns "lines columns"
term_size() {
    shopt -s checkwinsize; (:;:)
    printf '%d %d\n' "$LINES" "$COLUMNS"
}

# Get terminal width
# Usage: term_width
term_width() {
    shopt -s checkwinsize; (:;:)
    printf '%d\n' "$COLUMNS"
}

# Get terminal height
# Usage: term_height
term_height() {
    shopt -s checkwinsize; (:;:)
    printf '%d\n' "$LINES"
}

# Check if running in terminal
# Usage: is_terminal && echo "yes"
is_terminal() {
    [[ -t 1 ]]
}

# Check if running interactively
# Usage: is_interactive && echo "yes"
is_interactive() {
    [[ $- == *i* ]]
}

# =============================================================================
# SYSTEM INFO
# =============================================================================

# Check if running as root
# Usage: is_root && echo "yes"
is_root() {
    [[ $EUID -eq 0 ]]
}

# Get current user
# Usage: current_user
current_user() {
    printf '%s\n' "$USER"
}

# Get hostname
# Usage: get_hostname
get_hostname() {
    printf '%s\n' "$HOSTNAME"
}

# Get OS type
# Usage: get_os
get_os() {
    printf '%s\n' "$OSTYPE"
}

# Check if on macOS
# Usage: is_macos && echo "yes"
is_macos() {
    [[ "$OSTYPE" == darwin* ]]
}

# Check if on Linux
# Usage: is_linux && echo "yes"
is_linux() {
    [[ "$OSTYPE" == linux* ]]
}

# Check if on Windows (Git Bash, WSL, Cygwin)
# Usage: is_windows && echo "yes"
is_windows() {
    [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* || -n "${WSL_DISTRO_NAME:-}" ]]
}

# Check if WSL
# Usage: is_wsl && echo "yes"
is_wsl() {
    [[ -n "${WSL_DISTRO_NAME:-}" ]]
}

# =============================================================================
# COMMAND CHECKING
# =============================================================================

# Check if command exists (faster than which)
# Usage: cmd_exists curl && echo "found"
cmd_exists() {
    type -p "$1" &>/dev/null
}

# Get command path
# Usage: cmd_path curl
cmd_path() {
    type -p "$1"
}

# Check multiple commands exist
# Usage: cmds_exist curl jq wget
cmds_exist() {
    for cmd in "$@"; do
        type -p "$cmd" &>/dev/null || return 1
    done
    return 0
}

# Get command version (tries --version)
# Usage: cmd_version curl
cmd_version() {
    local cmd="$1"
    local flag="${2:---version}"

    if type -p "$cmd" &>/dev/null; then
        "$cmd" "$flag" 2>&1 | head -1
    else
        printf 'not found\n'
        return 1
    fi
}

# =============================================================================
# SLEEP (No external command!)
# =============================================================================

# Sleep without external command (Bash 4+)
# Usage: sleep_pure 2  # Sleep 2 seconds
sleep_pure() {
    read -rt "$1" <> <(:) || :
}

# =============================================================================
# MATH
# =============================================================================

# Absolute value
# Usage: abs -5
abs() {
    local val="$1"
    ((val < 0)) && val=$((val * -1))
    printf '%d\n' "$val"
}

# Clamp value to range
# Usage: clamp 150 0 100  # Returns 100
clamp() {
    local val="$1"
    local min="$2"
    local max="$3"

    ((val < min)) && val=$min
    ((val > max)) && val=$max
    printf '%d\n' "$val"
}

# Power
# Usage: pow 2 10  # Returns 1024
pow() {
    local base="$1"
    local exp="$2"
    local result=1

    for ((i=0; i<exp; i++)); do
        ((result *= base))
    done
    printf '%d\n' "$result"
}

# Factorial
# Usage: factorial 5  # Returns 120
factorial() {
    local n="$1"
    local result=1

    for ((i=2; i<=n; i++)); do
        ((result *= i))
    done
    printf '%d\n' "$result"
}

# Greatest common divisor
# Usage: gcd 24 36  # Returns 12
gcd() {
    local a="$1"
    local b="$2"

    while ((b != 0)); do
        local t=$b
        ((b = a % b))
        a=$t
    done
    printf '%d\n' "$a"
}

# Least common multiple
# Usage: lcm 4 6  # Returns 12
lcm() {
    local a="$1"
    local b="$2"
    local g
    g=$(gcd "$a" "$b")
    printf '%d\n' "$((a * b / g))"
}

# =============================================================================
# VALIDATION
# =============================================================================

# Check if valid integer
# Usage: is_int "123" && echo "yes"
is_int() {
    [[ "$1" =~ ^-?[0-9]+$ ]]
}

# Check if positive integer
# Usage: is_positive_int "123" && echo "yes"
is_positive_int() {
    [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -gt 0 ]]
}

# Check if valid float
# Usage: is_float "3.14" && echo "yes"
is_float() {
    [[ "$1" =~ ^-?[0-9]*\.?[0-9]+$ ]]
}

# Check if valid hex
# Usage: is_hex "ff00ff" && echo "yes"
is_hex() {
    [[ "$1" =~ ^[0-9a-fA-F]+$ ]]
}

# Check if valid IP address
# Usage: is_ip "192.168.1.1" && echo "yes"
is_ip() {
    local ip="$1"
    local IFS='.'
    read -ra octets <<< "$ip"

    [[ ${#octets[@]} -ne 4 ]] && return 1

    for octet in "${octets[@]}"; do
        [[ ! "$octet" =~ ^[0-9]+$ ]] && return 1
        ((octet < 0 || octet > 255)) && return 1
    done
    return 0
}

# Check if valid email (basic)
# Usage: is_email "user@example.com" && echo "yes"
is_email() {
    [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

# Check if valid URL (basic)
# Usage: is_url "https://example.com" && echo "yes"
is_url() {
    [[ "$1" =~ ^https?://[A-Za-z0-9.-]+(/.*)?$ ]]
}

# =============================================================================
# PATH OPERATIONS
# =============================================================================

# Get filename from path
# Usage: basename_pure "/path/to/file.txt"
basename_pure() {
    printf '%s\n' "${1##*/}"
}

# Get directory from path
# Usage: dirname_pure "/path/to/file.txt"
dirname_pure() {
    printf '%s\n' "${1%/*}"
}

# Get file extension
# Usage: extension "/path/to/file.txt"
extension() {
    local base="${1##*/}"
    [[ "$base" == *.* ]] && printf '%s\n' "${base##*.}" || printf '\n'
}

# Get filename without extension
# Usage: filename_no_ext "/path/to/file.txt"
filename_no_ext() {
    local base="${1##*/}"
    printf '%s\n' "${base%.*}"
}

# Normalize path (remove trailing slash)
# Usage: normalize_path "/path/to/dir/"
normalize_path() {
    printf '%s\n' "${1%/}"
}

# =============================================================================
# PROGRESS / UI
# =============================================================================

# Show spinner
# Usage: show_spinner pid
show_spinner() {
    local pid="$1"
    local chars='|/-\'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        printf '\r%s' "${chars:i++%4:1}"
        sleep_pure 0.1
    done
    printf '\r \r'
}

# Show simple progress bar
# Usage: progress_bar 50 100  # 50%
progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-50}"

    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf '\r['
    printf '%*s' "$filled" '' | tr ' ' '#'
    printf '%*s' "$empty" '' | tr ' ' '-'
    printf '] %3d%%' "$percent"
}

# Clear line
# Usage: clear_line
clear_line() {
    printf '\r\033[K'
}

# Move cursor up N lines
# Usage: cursor_up 2
cursor_up() {
    printf '\033[%dA' "${1:-1}"
}

# Move cursor down N lines
# Usage: cursor_down 2
cursor_down() {
    printf '\033[%dB' "${1:-1}"
}

# Hide cursor
# Usage: cursor_hide
cursor_hide() {
    printf '\033[?25l'
}

# Show cursor
# Usage: cursor_show
cursor_show() {
    printf '\033[?25h'
}

# =============================================================================
# FORMATTING
# =============================================================================

# Format bytes to human-readable (KB, MB, GB, TB)
# Usage: format_bytes 1048576  # "1MB"
format_bytes() {
    local bytes=$1
    if (( bytes >= 1099511627776 )); then
        printf "%.1fTB" "$(echo "scale=1; $bytes / 1099511627776" | bc)"
    elif (( bytes >= 1073741824 )); then
        printf "%.1fGB" "$(echo "scale=1; $bytes / 1073741824" | bc)"
    elif (( bytes >= 1048576 )); then
        printf "%.1fMB" "$(echo "scale=1; $bytes / 1048576" | bc)"
    elif (( bytes >= 1024 )); then
        printf "%.1fKB" "$(echo "scale=1; $bytes / 1024" | bc)"
    else
        printf "%dB" "$bytes"
    fi
}

# Format bytes (pure bash, integer only)
# Usage: format_bytes_int 1048576  # "1MB"
format_bytes_int() {
    local bytes=$1
    if (( bytes >= 1099511627776 )); then
        echo "$((bytes / 1099511627776))TB"
    elif (( bytes >= 1073741824 )); then
        echo "$((bytes / 1073741824))GB"
    elif (( bytes >= 1048576 )); then
        echo "$((bytes / 1048576))MB"
    elif (( bytes >= 1024 )); then
        echo "$((bytes / 1024))KB"
    else
        echo "${bytes}B"
    fi
}

# Format duration in seconds to human-readable
# Usage: format_duration 3661  # "1h 1m 1s"
format_duration() {
    local seconds=$1
    local result=""

    if (( seconds >= 86400 )); then
        result+="$((seconds / 86400))d "
        seconds=$((seconds % 86400))
    fi
    if (( seconds >= 3600 )); then
        result+="$((seconds / 3600))h "
        seconds=$((seconds % 3600))
    fi
    if (( seconds >= 60 )); then
        result+="$((seconds / 60))m "
        seconds=$((seconds % 60))
    fi
    if (( seconds > 0 )) || [[ -z "$result" ]]; then
        result+="${seconds}s"
    fi

    echo "${result% }"
}

# Format number with commas
# Usage: format_number 1234567  # "1,234,567"
format_number() {
    printf "%'d" "$1"
}

# Format percentage
# Usage: format_percent 75 100  # "75%"
format_percent() {
    local value=$1
    local total=$2
    echo "$((value * 100 / total))%"
}

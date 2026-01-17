#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/pure-string.sh - Pure Bash String Manipulation
# =============================================================================
# Description: String operations without external tools (sed, awk, cut)
# Source: Inspired by Pure Bash Bible
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_PURE_STRING_LOADED:-}" ]] && return 0
readonly _MAINFRAME_PURE_STRING_LOADED=1

# =============================================================================
# WHITESPACE
# =============================================================================

# Trim leading and trailing whitespace
# Usage: trim_string "  hello world  "
trim_string() {
    : "${1#"${1%%[![:space:]]*}"}"
    : "${_%"${_##*[![:space:]]}"}"
    printf '%s\n' "$_"
}

# Trim leading whitespace
# Usage: trim_left "  hello"
trim_left() {
    printf '%s\n' "${1#"${1%%[![:space:]]*}"}"
}

# Trim trailing whitespace
# Usage: trim_right "hello  "
trim_right() {
    printf '%s\n' "${1%"${1##*[![:space:]]}"}"
}

# =============================================================================
# CASE CONVERSION (Bash 4+)
# =============================================================================

# Convert to lowercase
# Usage: to_lower "HELLO"
to_lower() {
    printf '%s\n' "${1,,}"
}

# Convert to uppercase
# Usage: to_upper "hello"
to_upper() {
    printf '%s\n' "${1^^}"
}

# Capitalize first letter
# Usage: capitalize "hello"
capitalize() {
    printf '%s\n' "${1^}"
}

# Reverse case
# Usage: reverse_case "HeLLo"
reverse_case() {
    printf '%s\n' "${1~~}"
}

# =============================================================================
# PATTERN REMOVAL
# =============================================================================

# Remove all occurrences of pattern
# Usage: strip_all "hello world" "l"
strip_all() {
    printf '%s\n' "${1//$2}"
}

# Remove first occurrence of pattern
# Usage: strip_first "hello" "l"
strip_first() {
    printf '%s\n' "${1/$2}"
}

# Strip pattern from start (shortest match)
# Usage: lstrip "hello" "hel"
lstrip() {
    printf '%s\n' "${1#$2}"
}

# Strip pattern from start (longest match)
# Usage: lstrip_greedy "hello" "h*l"
lstrip_greedy() {
    printf '%s\n' "${1##$2}"
}

# Strip pattern from end (shortest match)
# Usage: rstrip "hello" "lo"
rstrip() {
    printf '%s\n' "${1%$2}"
}

# Strip pattern from end (longest match)
# Usage: rstrip_greedy "hello" "l*"
rstrip_greedy() {
    printf '%s\n' "${1%%$2}"
}

# =============================================================================
# REPLACEMENT
# =============================================================================

# Replace first occurrence
# Usage: replace_first "hello" "l" "L"
replace_first() {
    printf '%s\n' "${1/$2/$3}"
}

# Replace all occurrences
# Usage: replace_all "hello" "l" "L"
replace_all() {
    printf '%s\n' "${1//$2/$3}"
}

# =============================================================================
# SUBSTRING
# =============================================================================

# Get substring
# Usage: substring "hello" 1 3  # Returns "ell"
substring() {
    printf '%s\n' "${1:$2:$3}"
}

# Get string length
# Usage: strlen "hello"
strlen() {
    printf '%d\n' "${#1}"
}

# Get character at index
# Usage: char_at "hello" 2  # Returns "l"
char_at() {
    printf '%s\n' "${1:$2:1}"
}

# =============================================================================
# CHECKS
# =============================================================================

# Check if string contains substring
# Usage: contains "hello world" "world"
contains() {
    [[ $1 == *"$2"* ]]
}

# Check if string starts with prefix
# Usage: starts_with "hello" "hel"
starts_with() {
    [[ $1 == "$2"* ]]
}

# Check if string ends with suffix
# Usage: ends_with "hello" "lo"
ends_with() {
    [[ $1 == *"$2" ]]
}

# Check if string is empty
# Usage: is_empty ""
is_empty() {
    [[ -z "$1" ]]
}

# Check if string is not empty
# Usage: is_not_empty "hello"
is_not_empty() {
    [[ -n "$1" ]]
}

# Check if string matches regex
# Usage: matches "hello123" '^[a-z]+[0-9]+$'
matches() {
    [[ $1 =~ $2 ]]
}

# =============================================================================
# SPLITTING & JOINING
# =============================================================================

# Split string into array
# Usage: split_string "a,b,c" "," arr; echo "${arr[@]}"
split_string() {
    local str="$1"
    local delim="$2"
    local -n result_array="$3"

    local IFS="$delim"
    read -ra result_array <<< "$str"
}

# Join array into string
# Usage: join_string "," "${arr[@]}"
join_string() {
    local delim="$1"
    shift
    local first=true

    for item in "$@"; do
        if $first; then
            printf '%s' "$item"
            first=false
        else
            printf '%s%s' "$delim" "$item"
        fi
    done
    printf '\n'
}

# =============================================================================
# GENERATION
# =============================================================================

# Repeat string N times
# Usage: repeat_string "-" 10
repeat_string() {
    local str=""
    for ((i=0; i<$2; i++)); do
        str+="$1"
    done
    printf '%s\n' "$str"
}

# Pad string to length
# Usage: pad_right "hello" 10 " "
pad_right() {
    local str="$1"
    local len="$2"
    local char="${3:- }"
    local current=${#str}

    while ((current < len)); do
        str+="$char"
        ((current++))
    done
    printf '%s\n' "$str"
}

# Usage: pad_left "hello" 10 " "
pad_left() {
    local str="$1"
    local len="$2"
    local char="${3:- }"
    local current=${#str}
    local prefix=""

    while ((current < len)); do
        prefix+="$char"
        ((current++))
    done
    printf '%s\n' "${prefix}${str}"
}

# Center string
# Usage: center "hello" 20
center() {
    local str="$1"
    local width="$2"
    local len=${#str}
    local padding=$(( (width - len) / 2 ))

    printf '%*s%s%*s\n' "$padding" "" "$str" "$padding" ""
}

# =============================================================================
# URL ENCODING
# =============================================================================

# URL encode
# Usage: urlencode "hello world"
urlencode() {
    local LC_ALL=C
    local string="$1"
    local length=${#string}

    for ((i=0; i<length; i++)); do
        local c="${string:i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
    printf '\n'
}

# URL decode
# Usage: urldecode "hello%20world"
urldecode() {
    : "${1//+/ }"
    printf '%b\n' "${_//%/\\x}"
}

# =============================================================================
# ESCAPE
# =============================================================================

# Escape for use in regex
# Usage: escape_regex "hello.*"
escape_regex() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//./\\.}"
    str="${str//\*/\\*}"
    str="${str//\?/\\?}"
    str="${str//\[/\\[}"
    str="${str//\]/\\]}"
    str="${str//\^/\\^}"
    str="${str//\$/\\$}"
    printf '%s\n' "$str"
}

# Escape for use in shell
# Usage: escape_shell "hello 'world'"
escape_shell() {
    printf '%q\n' "$1"
}

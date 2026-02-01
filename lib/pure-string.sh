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
    local var="${1#"${1%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s\n' "$var"
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
    local var="${1//+/ }"
    printf '%b\n' "${var//%/\\x}"
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

# =============================================================================
# NAMEREF VARIANTS (High-Performance)
# =============================================================================
# These _v variants use bash namerefs to avoid subshell overhead.
# Instead of: result=$(trim_string "  hello  ")  # Creates subshell
# Use:        trim_string_v result "  hello  "   # No subshell (~3.3x faster)
# =============================================================================

# Trim leading and trailing whitespace into variable
# Usage: trim_string_v result_var "  hello world  "
trim_string_v() {
    local -n __tsv_out=$1
    local var="${2#"${2%%[![:space:]]*}"}"
    __tsv_out="${var%"${var##*[![:space:]]}"}"
}

# Convert to lowercase into variable
# Usage: to_lower_v result_var "HELLO"
to_lower_v() {
    local -n __tlv_out=$1
    __tlv_out="${2,,}"
}

# Convert to uppercase into variable
# Usage: to_upper_v result_var "hello"
to_upper_v() {
    local -n __tuv_out=$1
    __tuv_out="${2^^}"
}

# Get substring into variable
# Usage: substring_v result_var "hello" 1 3
substring_v() {
    local -n __ssv_out=$1
    __ssv_out="${2:$3:$4}"
}

# Replace first occurrence into variable
# Usage: replace_first_v result_var "hello" "l" "L"
replace_first_v() {
    local -n __rfv_out=$1
    __rfv_out="${2/$3/$4}"
}

# Replace all occurrences into variable
# Usage: replace_all_v result_var "hello" "l" "L"
replace_all_v() {
    local -n __rav_out=$1
    __rav_out="${2//$3/$4}"
}

# URL encode into variable
# Usage: urlencode_v result_var "hello world"
urlencode_v() {
    local -n __uev_out=$1
    local LC_ALL=C
    local string="$2"
    local length=${#string}
    local i c

    __uev_out=""
    for ((i=0; i<length; i++)); do
        c="${string:i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) __uev_out+="$c" ;;
            *) printf -v c '%%%02X' "'$c"; __uev_out+="$c" ;;
        esac
    done
}

# URL decode into variable
# Usage: urldecode_v result_var "hello%20world"
urldecode_v() {
    local -n __udv_out=$1
    local var="${2//+/ }"
    printf -v __udv_out '%b' "${var//%/\\x}"
}

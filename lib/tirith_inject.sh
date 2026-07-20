#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/tirith_inject.sh - Terminal Injection Detection
# =============================================================================
# Description: Detects terminal injection attacks including ANSI escape
#              sequences, BiDi control characters, zero-width characters,
#              and hidden multiline commands.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_TIRITH_INJECT_LOADED:-}" ]] && return 0
readonly _MAINFRAME_TIRITH_INJECT_LOADED=1

# =============================================================================
# SHARED STATE INITIALIZATION
# =============================================================================

# _tirith_init_state
# Initialize shared tirith state if not already done. These globals are shared
# across all tirith_* libraries and use \x1f as field separator.
_tirith_init_state() {
    if ! declare -p _TIRITH_FINDINGS &>/dev/null 2>&1; then
        declare -ga _TIRITH_FINDINGS 2>/dev/null || declare -a _TIRITH_FINDINGS
        _TIRITH_FINDINGS=()
        _TIRITH_CRITICAL=0
        _TIRITH_HIGH=0
        _TIRITH_MEDIUM=0
        _TIRITH_LOW=0
    fi
}

# Initialize at load time
_tirith_init_state

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# _tirith_add_finding SOURCE SEVERITY RULE_ID MESSAGE
# Add a finding to the shared global array and increment severity counter.
# Fields are separated by \x1f (unit separator) for safe parsing.
_tirith_add_finding() {
    local source="$1" severity="$2" rule_id="$3" message="$4"
    _TIRITH_FINDINGS+=("${source}"$'\x1f'"${severity}"$'\x1f'"${rule_id}"$'\x1f'"${message}")
    case "$severity" in
        critical) _TIRITH_CRITICAL=$((_TIRITH_CRITICAL + 1)) ;;
        high)     _TIRITH_HIGH=$((_TIRITH_HIGH + 1)) ;;
        medium)   _TIRITH_MEDIUM=$((_TIRITH_MEDIUM + 1)) ;;
        low)      _TIRITH_LOW=$((_TIRITH_LOW + 1)) ;;
    esac
}

# =============================================================================
# RULE 1: ANSI ESCAPE SEQUENCE DETECTION
# =============================================================================

# tirith_check_ansi_escapes INPUT [SOURCE]
# Detect ANSI escape sequences that could manipulate terminal display.
# Checks for CSI (\x1b[), 8-bit CSI (\x9b), OSC (\x1b]), SS2 (\x1bN),
# and SS3 (\x1bO) sequences.
# Severity: high | Rule: AnsiEscapes
# Returns: 0 if finding detected, 1 if clean
tirith_check_ansi_escapes() {
    local input="$1"
    local source="${2:-input}"

    [[ -z "$input" ]] && return 1

    # Delegate to ansi.sh if loaded, otherwise inline check
    if declare -f ansi_has_escapes &>/dev/null; then
        if ansi_has_escapes "$input"; then
            _tirith_add_finding "$source" "high" "AnsiEscapes" \
                "ANSI escape sequence detected in input"
            return 0
        fi
    else
        # Inline check: ESC[ (CSI), \x9b (8-bit CSI), ESC] (OSC), ESC-N (SS2), ESC-O (SS3)
        if [[ "$input" == *$'\033['* ]] || \
           [[ "$input" == *$'\x9b'* ]] || \
           [[ "$input" == *$'\033]'* ]] || \
           [[ "$input" == *$'\033N'* ]] || \
           [[ "$input" == *$'\033O'* ]]; then
            _tirith_add_finding "$source" "high" "AnsiEscapes" \
                "ANSI escape sequence detected in input"
            return 0
        fi
    fi

    return 1
}

# =============================================================================
# RULE 2: CONTROL CHARACTER DETECTION
# =============================================================================

# tirith_check_control_chars INPUT [SOURCE]
# Detect ASCII control characters that should not appear in normal input.
# Checks for \x00-\x08 and \x0e-\x1f, excluding tab (\x09), newline (\x0a),
# and carriage return (\x0d) which are legitimate whitespace.
# Severity: high | Rule: ControlChars
# Returns: 0 if finding detected, 1 if clean
tirith_check_control_chars() {
    local input="$1"
    local source="${2:-input}"

    [[ -z "$input" ]] && return 1

    local byte_val
    local i len

    len=${#input}
    for (( i = 0; i < len; i++ )); do
        # Get the byte value using printf
        byte_val=$(printf '%d' "'${input:$i:1}" 2>/dev/null) || continue

        # Check for control chars: \x00-\x08, \x0e-\x1f
        # Exclude: \x09 (tab), \x0a (newline), \x0b (vtab - borderline but skip),
        #          \x0c (form feed - borderline but skip), \x0d (carriage return)
        if (( byte_val >= 0 && byte_val <= 8 )) || \
           (( byte_val >= 14 && byte_val <= 31 )); then
            _tirith_add_finding "$source" "high" "ControlChars" \
                "ASCII control character (0x$(printf '%02x' "$byte_val")) detected in input"
            return 0
        fi
    done

    return 1
}

# =============================================================================
# RULE 3: BIDI CONTROL CHARACTER DETECTION
# =============================================================================

# tirith_check_bidi_controls INPUT [SOURCE]
# Detect Unicode BiDi (bidirectional) control characters that can reorder
# displayed text to hide malicious code (CVE-2021-42574, "Trojan Source").
# Severity: critical | Rule: BidiControls
# Returns: 0 if finding detected, 1 if clean
tirith_check_bidi_controls() {
    local input="$1"
    local source="${2:-input}"

    [[ -z "$input" ]] && return 1

    # BiDi control characters and their UTF-8 byte sequences
    local -a bidi_names=(
        "LRE (U+202A)"
        "RLE (U+202B)"
        "PDF (U+202C)"
        "LRO (U+202D)"
        "RLO (U+202E)"
        "LRI (U+2066)"
        "RLI (U+2067)"
        "FSI (U+2068)"
        "PDI (U+2069)"
    )
    local -a bidi_bytes=(
        $'\xe2\x80\xaa'
        $'\xe2\x80\xab'
        $'\xe2\x80\xac'
        $'\xe2\x80\xad'
        $'\xe2\x80\xae'
        $'\xe2\x81\xa6'
        $'\xe2\x81\xa7'
        $'\xe2\x81\xa8'
        $'\xe2\x81\xa9'
    )

    local i
    for (( i = 0; i < ${#bidi_bytes[@]}; i++ )); do
        if [[ "$input" == *"${bidi_bytes[$i]}"* ]]; then
            _tirith_add_finding "$source" "critical" "BidiControls" \
                "Unicode BiDi control character ${bidi_names[$i]} detected (Trojan Source attack)"
            return 0
        fi
    done

    return 1
}

# =============================================================================
# RULE 4: ZERO-WIDTH CHARACTER DETECTION
# =============================================================================

# tirith_check_zero_width INPUT [SOURCE]
# Detect zero-width Unicode characters that can hide content or alter
# string comparisons without visible change.
# Severity: high | Rule: ZeroWidthChars
# Returns: 0 if finding detected, 1 if clean
tirith_check_zero_width() {
    local input="$1"
    local source="${2:-input}"

    [[ -z "$input" ]] && return 1

    # Zero-width characters and their UTF-8 byte sequences
    local -a zw_names=(
        "ZWSP (U+200B)"
        "ZWNJ (U+200C)"
        "ZWJ (U+200D)"
        "BOM (U+FEFF)"
    )
    local -a zw_bytes=(
        $'\xe2\x80\x8b'
        $'\xe2\x80\x8c'
        $'\xe2\x80\x8d'
        $'\xef\xbb\xbf'
    )

    local i
    for (( i = 0; i < ${#zw_bytes[@]}; i++ )); do
        if [[ "$input" == *"${zw_bytes[$i]}"* ]]; then
            _tirith_add_finding "$source" "high" "ZeroWidthChars" \
                "Zero-width character ${zw_names[$i]} detected in input"
            return 0
        fi
    done

    return 1
}

# =============================================================================
# RULE 5: HIDDEN MULTILINE COMMAND DETECTION
# =============================================================================

# tirith_check_hidden_multiline INPUT [SOURCE]
# Detect hidden newlines or carriage returns that conceal additional commands
# within a seemingly single-line input. Only flags when a newline is followed
# by a dangerous command keyword.
# Severity: high | Rule: HiddenMultiline
# Returns: 0 if finding detected, 1 if clean
tirith_check_hidden_multiline() {
    local input="$1"
    local source="${2:-input}"

    [[ -z "$input" ]] && return 1

    # Dangerous keywords that indicate a hidden secondary command
    local -a dangerous_keywords=(
        rm chmod chown dd mkfs
        wget curl nc ncat
        bash sh python perl ruby
        eval exec
    )

    # Build a single regex alternation for all dangerous keywords
    local pattern=""
    local kw
    for kw in "${dangerous_keywords[@]}"; do
        [[ -n "$pattern" ]] && pattern+="|"
        pattern+="$kw"
    done

    # Check for embedded newline (\n) or carriage return (\r) NOT at the end,
    # followed by optional whitespace and a dangerous keyword
    # We split on \n and \r and check subsequent segments
    local segment
    local first=1

    # Replace \r with \n for uniform splitting, then iterate segments
    local normalized="${input//$'\r'/$'\n'}"

    while IFS= read -r segment; do
        # Skip the first segment (the visible command)
        if [[ $first -eq 1 ]]; then
            first=0
            continue
        fi

        # Trim leading whitespace from the hidden segment
        local trimmed="${segment#"${segment%%[![:space:]]*}"}"

        # Check if the hidden segment starts with a dangerous keyword
        # Use word boundary: keyword followed by space, end of string, or special char
        local kw
        for kw in "${dangerous_keywords[@]}"; do
            if [[ "$trimmed" == "$kw" ]] || \
               [[ "$trimmed" == "$kw "* ]] || \
               [[ "$trimmed" == "$kw	"* ]] || \
               [[ "$trimmed" == "$kw;"* ]] || \
               [[ "$trimmed" == "$kw|"* ]] || \
               [[ "$trimmed" == "$kw&"* ]] || \
               [[ "$trimmed" == "$kw<"* ]] || \
               [[ "$trimmed" == "$kw>"* ]]; then
                _tirith_add_finding "$source" "high" "HiddenMultiline" \
                    "Hidden newline followed by dangerous command '${kw}' detected"
                return 0
            fi
        done
    done <<< "$normalized"

    return 1
}

# =============================================================================
# COMPOSITE SCANNER
# =============================================================================

# tirith_scan_injection INPUT [SOURCE]
# Run all 5 injection detection rules on the input.
# Returns: 0 if any findings detected, 1 if clean
tirith_scan_injection() {
    local input="$1"
    local source="${2:-input}"
    local found=1

    tirith_check_ansi_escapes "$input" "$source"    && found=0
    tirith_check_bidi_controls "$input" "$source"    && found=0
    tirith_check_zero_width "$input" "$source"       && found=0
    tirith_check_control_chars "$input" "$source"    && found=0
    tirith_check_hidden_multiline "$input" "$source" && found=0

    return "$found"
}

# =============================================================================
# SANITIZATION UTILITIES
# =============================================================================

# tirith_strip_dangerous_chars INPUT
# Strip BiDi controls, zero-width characters, and control characters
# (keeping tab, newline, and carriage return) from the input.
# Output: Cleaned string on stdout
tirith_strip_dangerous_chars() {
    local input="$1"

    [[ -z "$input" ]] && return 0

    # Strip BiDi control characters (UTF-8 byte sequences)
    input="${input//$'\xe2\x80\xaa'/}"   # U+202A LRE
    input="${input//$'\xe2\x80\xab'/}"   # U+202B RLE
    input="${input//$'\xe2\x80\xac'/}"   # U+202C PDF
    input="${input//$'\xe2\x80\xad'/}"   # U+202D LRO
    input="${input//$'\xe2\x80\xae'/}"   # U+202E RLO
    input="${input//$'\xe2\x81\xa6'/}"   # U+2066 LRI
    input="${input//$'\xe2\x81\xa7'/}"   # U+2067 RLI
    input="${input//$'\xe2\x81\xa8'/}"   # U+2068 FSI
    input="${input//$'\xe2\x81\xa9'/}"   # U+2069 PDI

    # Strip zero-width characters
    input="${input//$'\xe2\x80\x8b'/}"   # U+200B ZWSP
    input="${input//$'\xe2\x80\x8c'/}"   # U+200C ZWNJ
    input="${input//$'\xe2\x80\x8d'/}"   # U+200D ZWJ
    input="${input//$'\xef\xbb\xbf'/}"   # U+FEFF BOM

    # Strip control characters (\x00-\x08, \x0e-\x1f) while keeping
    # tab (\x09), newline (\x0a), and carriage return (\x0d)
    local result=""
    local i len byte_val
    local char

    len=${#input}
    for (( i = 0; i < len; i++ )); do
        char="${input:$i:1}"
        byte_val=$(printf '%d' "'$char" 2>/dev/null) || { result+="$char"; continue; }

        # Keep everything except dangerous control chars
        if (( byte_val >= 0 && byte_val <= 8 )) || \
           (( byte_val >= 14 && byte_val <= 31 )); then
            # Skip this control character
            continue
        fi
        result+="$char"
    done

    printf '%s' "$result"
}

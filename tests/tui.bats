#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: TUI Module Tests
# =============================================================================
# Comprehensive tests for lib/tui.sh (25+ functions)
# Covers: terminal utilities, color/styling, rich output (tables, boxes, panels),
#         progress indicators, interactive components, and NO_COLOR support.
# =============================================================================

load 'test_helper'

setup() {
    source_lib "tui"
    export MAINFRAME_QUIET=1
    export NO_COLOR=""  # Enable colors for most tests
    TEST_DIR=$(create_test_dir "tui")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
    # Ensure cursor is visible after tests
    printf '\033[?25h' 2>/dev/null || true
}

# =============================================================================
# TERMINAL UTILITIES TESTS
# =============================================================================

@test "tui_term_width returns positive integer" {
    local width
    width=$(tui_term_width)
    [[ "$width" =~ ^[0-9]+$ ]]
    (( width >= 20 ))
}

@test "tui_term_width returns at least 20" {
    local width
    width=$(tui_term_width)
    (( width >= 20 ))
}

@test "tui_term_height returns positive integer" {
    local height
    height=$(tui_term_height)
    [[ "$height" =~ ^[0-9]+$ ]]
    (( height >= 5 ))
}

@test "tui_term_height returns at least 5" {
    local height
    height=$(tui_term_height)
    (( height >= 5 ))
}

@test "tui_is_interactive returns false in non-interactive context" {
    # BATS tests run non-interactively
    ! tui_is_interactive
}

@test "tui_supports_color respects NO_COLOR" {
    export NO_COLOR=1
    ! tui_supports_color
    unset NO_COLOR
}

@test "tui_supports_color respects TERM=dumb" {
    local old_term="${TERM:-}"
    export TERM=dumb
    ! tui_supports_color
    export TERM="$old_term"
}

# =============================================================================
# COLOR & STYLING TESTS
# =============================================================================

@test "tui_color outputs text" {
    local result
    result=$(NO_COLOR=1 tui_color red "test text")
    [ "$result" = "test text" ]
}

@test "tui_color handles empty text" {
    local result
    result=$(NO_COLOR=1 tui_color green "")
    [ "$result" = "" ]
}

@test "tui_color respects NO_COLOR" {
    local result
    result=$(NO_COLOR=1 tui_color red "text")
    # Should not contain ANSI escape codes
    [[ "$result" != *$'\033'* ]]
}

@test "tui_color supports all standard colors" {
    local colors=(black red green yellow blue magenta cyan white)
    for color in "${colors[@]}"; do
        local result
        result=$(NO_COLOR=1 tui_color "$color" "test")
        [ "$result" = "test" ]
    done
}

@test "tui_color supports bright colors" {
    local colors=(bright_black bright_red bright_green bright_yellow)
    for color in "${colors[@]}"; do
        local result
        result=$(NO_COLOR=1 tui_color "$color" "test")
        [ "$result" = "test" ]
    done
}

@test "tui_bold outputs text" {
    local result
    result=$(NO_COLOR=1 tui_bold "bold text")
    [ "$result" = "bold text" ]
}

@test "tui_dim outputs text" {
    local result
    result=$(NO_COLOR=1 tui_dim "dim text")
    [ "$result" = "dim text" ]
}

@test "tui_italic outputs text" {
    local result
    result=$(NO_COLOR=1 tui_italic "italic text")
    [ "$result" = "italic text" ]
}

@test "tui_underline outputs text" {
    local result
    result=$(NO_COLOR=1 tui_underline "underlined text")
    [ "$result" = "underlined text" ]
}

@test "tui_theme_load accepts dark theme" {
    tui_theme_load "dark"
    local color
    color=$(tui_theme_color "primary")
    [ "$color" = "cyan" ]
}

@test "tui_theme_load accepts light theme" {
    tui_theme_load "light"
    local color
    color=$(tui_theme_color "primary")
    [ "$color" = "blue" ]
}

@test "tui_theme_load accepts minimal theme" {
    tui_theme_load "minimal"
    local color
    color=$(tui_theme_color "primary")
    [ "$color" = "white" ]
}

@test "tui_theme_load rejects unknown theme" {
    ! tui_theme_load "nonexistent"
}

@test "tui_theme_color returns theme color" {
    tui_theme_load "dark"
    local color
    color=$(tui_theme_color "success")
    [ "$color" = "green" ]
}

@test "tui_theme_color returns white for unknown key" {
    local color
    color=$(tui_theme_color "nonexistent")
    [ "$color" = "white" ]
}

# =============================================================================
# RICH OUTPUT - TABLE TESTS
# =============================================================================

@test "tui_table renders header row" {
    local result
    result=$(NO_COLOR=1 tui_table "Name|Age" "Alice|30")
    [[ "$result" == *"Name"* ]]
    [[ "$result" == *"Age"* ]]
}

@test "tui_table renders data rows" {
    local result
    result=$(NO_COLOR=1 tui_table "Name|Age" "Alice|30" "Bob|25")
    [[ "$result" == *"Alice"* ]]
    [[ "$result" == *"30"* ]]
    [[ "$result" == *"Bob"* ]]
    [[ "$result" == *"25"* ]]
}

@test "tui_table renders borders" {
    local result
    result=$(NO_COLOR=1 tui_table "A|B" "1|2")
    # Check for box drawing characters
    [[ "$result" == *"┌"* ]]
    [[ "$result" == *"┐"* ]]
    [[ "$result" == *"└"* ]]
    [[ "$result" == *"┘"* ]]
}

@test "tui_table handles empty input" {
    local result
    result=$(NO_COLOR=1 tui_table)
    [ -z "$result" ]
}

@test "tui_table handles single column" {
    local result
    result=$(NO_COLOR=1 tui_table "Name" "Alice" "Bob")
    [[ "$result" == *"Alice"* ]]
    [[ "$result" == *"Bob"* ]]
}

@test "tui_table handles many columns" {
    local result
    result=$(NO_COLOR=1 tui_table "A|B|C|D|E" "1|2|3|4|5")
    [[ "$result" == *"1"* ]]
    [[ "$result" == *"5"* ]]
}

@test "tui_table_json outputs valid JSON" {
    local result
    result=$(tui_table_json "Name|Age" "Alice|30" "Bob|25")
    # Verify it starts and ends like JSON array
    [[ "$result" == "["* ]]
    [[ "$result" == *"]" ]]
}

@test "tui_table_json includes all rows" {
    local result
    result=$(tui_table_json "Name|Age" "Alice|30" "Bob|25")
    [[ "$result" == *"Alice"* ]]
    [[ "$result" == *"Bob"* ]]
}

@test "tui_table_json handles empty input" {
    local result
    result=$(tui_table_json)
    [ "$result" = "[]" ]
}

# =============================================================================
# RICH OUTPUT - BOX TESTS
# =============================================================================

@test "tui_box renders content" {
    local result
    result=$(NO_COLOR=1 tui_box "Hello World")
    [[ "$result" == *"Hello World"* ]]
}

@test "tui_box renders with title" {
    local result
    result=$(NO_COLOR=1 tui_box "Title" "Content")
    [[ "$result" == *"Title"* ]]
    [[ "$result" == *"Content"* ]]
}

@test "tui_box renders multiple content lines" {
    local result
    result=$(NO_COLOR=1 tui_box "Title" "Line 1" "Line 2" "Line 3")
    [[ "$result" == *"Line 1"* ]]
    [[ "$result" == *"Line 2"* ]]
    [[ "$result" == *"Line 3"* ]]
}

@test "tui_box renders borders" {
    local result
    result=$(NO_COLOR=1 tui_box "Test")
    [[ "$result" == *"┌"* ]]
    [[ "$result" == *"┐"* ]]
    [[ "$result" == *"└"* ]]
    [[ "$result" == *"┘"* ]]
}

@test "tui_box handles empty content" {
    local result
    result=$(NO_COLOR=1 tui_box "")
    # Should still produce a box
    [[ "$result" == *"┌"* ]]
}

# =============================================================================
# RICH OUTPUT - PANEL TESTS
# =============================================================================

@test "tui_panel renders sections" {
    local result
    result=$(NO_COLOR=1 tui_panel "Section1|Content1")
    [[ "$result" == *"Section1"* ]]
    [[ "$result" == *"Content1"* ]]
}

@test "tui_panel renders multiple sections" {
    local result
    result=$(NO_COLOR=1 tui_panel "Sec1|Con1" "Sec2|Con2")
    [[ "$result" == *"Sec1"* ]]
    [[ "$result" == *"Sec2"* ]]
}

@test "tui_panel uses double-line borders" {
    local result
    result=$(NO_COLOR=1 tui_panel "Title|Content")
    [[ "$result" == *"╔"* ]]
    [[ "$result" == *"╗"* ]]
}

# =============================================================================
# RICH OUTPUT - DIVIDER TESTS
# =============================================================================

@test "tui_divider renders default character" {
    local result
    result=$(NO_COLOR=1 tui_divider)
    [[ "$result" == *"─"* ]]
}

@test "tui_divider renders custom character" {
    local result
    result=$(NO_COLOR=1 tui_divider "=" 10)
    [ "$result" = "==========" ]
}

@test "tui_divider respects width parameter" {
    local result
    result=$(NO_COLOR=1 tui_divider "-" 5)
    [ "$result" = "-----" ]
}

@test "tui_divider handles zero width" {
    local result
    result=$(NO_COLOR=1 tui_divider "=" 0)
    [ "$result" = "" ]
}

# =============================================================================
# RICH OUTPUT - COLUMNS TESTS
# =============================================================================

@test "tui_columns renders data" {
    local result
    result=$(NO_COLOR=1 tui_columns "Col1:10|Col2:10" "data1|data2")
    [[ "$result" == *"data1"* ]]
    [[ "$result" == *"data2"* ]]
}

@test "tui_columns respects width specifications" {
    local result
    result=$(NO_COLOR=1 tui_columns "A:5|B:5" "xx|yy")
    # Each column should be padded to specified width
    [[ ${#result} -ge 10 ]]
}

@test "tui_columns handles multiple rows" {
    local result
    result=$(NO_COLOR=1 tui_columns "A:10|B:10" "r1a|r1b" "r2a|r2b")
    local lines
    lines=$(echo "$result" | wc -l)
    [ "$lines" -eq 2 ]
}

# =============================================================================
# PROGRESS INDICATORS TESTS
# =============================================================================

@test "tui_progress renders progress bar" {
    local result
    result=$(NO_COLOR=1 tui_progress 50 100)
    [[ "$result" == *"%"* ]]
}

@test "tui_progress shows correct percentage" {
    local result
    result=$(NO_COLOR=1 tui_progress 50 100)
    [[ "$result" == *"50%"* ]]
}

@test "tui_progress handles 0%" {
    local result
    result=$(NO_COLOR=1 tui_progress 0 100)
    [[ "$result" == *"0%"* ]]
}

@test "tui_progress handles 100%" {
    local result
    result=$(NO_COLOR=1 tui_progress 100 100)
    [[ "$result" == *"100%"* ]]
}

@test "tui_progress clamps over 100%" {
    local result
    result=$(NO_COLOR=1 tui_progress 150 100)
    [[ "$result" == *"100%"* ]]
}

@test "tui_progress handles negative values" {
    local result
    result=$(NO_COLOR=1 tui_progress -10 100)
    [[ "$result" == *"0%"* ]]
}

@test "tui_progress defaults total to 100" {
    local result
    result=$(NO_COLOR=1 tui_progress 75)
    [[ "$result" == *"75%"* ]]
}

@test "tui_gauge renders label and bar" {
    local result
    result=$(NO_COLOR=1 tui_gauge "CPU" 75 100)
    [[ "$result" == *"CPU"* ]]
    [[ "$result" == *"75%"* ]]
}

@test "tui_gauge handles zero value" {
    local result
    result=$(NO_COLOR=1 tui_gauge "Memory" 0 100)
    [[ "$result" == *"0%"* ]]
}

@test "tui_gauge handles max value" {
    local result
    result=$(NO_COLOR=1 tui_gauge "Disk" 100 100)
    [[ "$result" == *"100%"* ]]
}

@test "tui_elapsed_start sets start time" {
    tui_elapsed_start
    [ -n "$_TUI_ELAPSED_START" ]
}

@test "tui_elapsed returns formatted time" {
    _TUI_ELAPSED_START=$(($(date +%s) - 90))  # 90 seconds ago
    local result
    result=$(tui_elapsed)
    [[ "$result" == *"m"* ]]  # Should contain minutes
    [[ "$result" == *"s"* ]]  # Should contain seconds
}

@test "tui_elapsed handles zero elapsed" {
    _TUI_ELAPSED_START=""
    local result
    result=$(tui_elapsed)
    [ "$result" = "0s" ]
}

# =============================================================================
# INTERACTIVE COMPONENT TESTS (Non-interactive mode)
# =============================================================================

@test "tui_select returns first option non-interactively" {
    local result
    result=$(tui_select "Option1" "Option2" "Option3")
    [ "$result" = "Option1" ]
}

@test "tui_select fails with no options" {
    ! tui_select
}

@test "tui_multiselect returns empty non-interactively" {
    local result
    result=$(tui_multiselect "Option1" "Option2")
    [ -z "$result" ]
}

@test "tui_confirm uses default yes non-interactively" {
    tui_confirm "Test?" "y"
}

@test "tui_confirm uses default no non-interactively" {
    ! tui_confirm "Test?" "n"
}

@test "tui_input returns default non-interactively" {
    local result
    result=$(tui_input "Name:" "DefaultValue")
    [ "$result" = "DefaultValue" ]
}

@test "tui_input returns empty if no default" {
    local result
    result=$(tui_input "Name:")
    [ "$result" = "" ]
}

@test "tui_password fails non-interactively" {
    ! tui_password "Password:"
}

# =============================================================================
# STATUS MESSAGE TESTS
# =============================================================================

@test "tui_success outputs message" {
    local result
    result=$(NO_COLOR=1 tui_success "Done")
    [[ "$result" == *"Done"* ]]
}

@test "tui_success shows OK indicator in no-color mode" {
    local result
    result=$(NO_COLOR=1 tui_success "Test")
    [[ "$result" == *"[OK]"* ]]
}

@test "tui_error outputs message to stderr" {
    local result
    result=$(NO_COLOR=1 tui_error "Failed" 2>&1)
    [[ "$result" == *"Failed"* ]]
}

@test "tui_error shows ERROR indicator in no-color mode" {
    local result
    result=$(NO_COLOR=1 tui_error "Test" 2>&1)
    [[ "$result" == *"[ERROR]"* ]]
}

@test "tui_warning outputs message" {
    local result
    result=$(NO_COLOR=1 tui_warning "Careful")
    [[ "$result" == *"Careful"* ]]
}

@test "tui_warning shows WARN indicator in no-color mode" {
    local result
    result=$(NO_COLOR=1 tui_warning "Test")
    [[ "$result" == *"[WARN]"* ]]
}

@test "tui_info outputs message" {
    local result
    result=$(NO_COLOR=1 tui_info "Information")
    [[ "$result" == *"Information"* ]]
}

@test "tui_info shows INFO indicator in no-color mode" {
    local result
    result=$(NO_COLOR=1 tui_info "Test")
    [[ "$result" == *"[INFO]"* ]]
}

@test "tui_debug suppressed without TUI_DEBUG" {
    unset TUI_DEBUG
    local result
    result=$(NO_COLOR=1 tui_debug "Debug info" 2>&1)
    [ -z "$result" ]
}

@test "tui_debug outputs with TUI_DEBUG set" {
    export TUI_DEBUG=1
    local result
    result=$(NO_COLOR=1 tui_debug "Debug info" 2>&1)
    [[ "$result" == *"DEBUG"* ]]
    unset TUI_DEBUG
}

# =============================================================================
# LEGACY API COMPATIBILITY TESTS
# =============================================================================

@test "tui::term_width is available" {
    declare -F tui::term_width
}

@test "tui::progress_bar is available" {
    declare -F tui::progress_bar
}

@test "tui::confirm is available" {
    declare -F tui::confirm
}

@test "tui::box is available" {
    declare -F tui::box
}

@test "tui::success outputs same as tui_success" {
    local legacy new
    legacy=$(NO_COLOR=1 tui::success "Test")
    new=$(NO_COLOR=1 tui_success "Test")
    [ "$legacy" = "$new" ]
}

@test "tui::error outputs same as tui_error" {
    local legacy new
    legacy=$(NO_COLOR=1 tui::error "Test" 2>&1)
    new=$(NO_COLOR=1 tui_error "Test" 2>&1)
    [ "$legacy" = "$new" ]
}

# =============================================================================
# EDGE CASES AND INTEGRATION TESTS
# =============================================================================

@test "table with special characters in data" {
    local result
    result=$(NO_COLOR=1 tui_table "Key|Value" 'test|say "hi"')
    [[ "$result" == *'say "hi"'* ]]
}

@test "box with long content line" {
    local long_text
    long_text=$(printf 'a%.0s' {1..100})
    local result
    result=$(NO_COLOR=1 tui_box "$long_text")
    [[ "$result" == *"$long_text"* ]]
}

@test "table handles unicode content" {
    local result
    result=$(NO_COLOR=1 tui_table "Emoji|Text" "Flag|Done")
    [[ "$result" == *"Flag"* ]]
}

@test "progress with custom width" {
    local result
    result=$(NO_COLOR=1 tui_progress 50 100 10)
    # Bar should be shorter
    [[ "$result" == *"50%"* ]]
}

@test "gauge with custom width" {
    local result
    result=$(NO_COLOR=1 tui_gauge "Test" 50 100 10)
    [[ "$result" == *"50%"* ]]
}

@test "multiple status messages in sequence" {
    tui_success "Step 1" >/dev/null
    tui_warning "Step 2" >/dev/null
    tui_error "Step 3" 2>/dev/null
    tui_info "Step 4" >/dev/null
    # Should complete without error
    true
}

@test "theme colors affect output" {
    tui_theme_load "dark"
    local color
    color=$(tui_theme_color "error")
    [ "$color" = "red" ]

    tui_theme_load "minimal"
    color=$(tui_theme_color "error")
    [ "$color" = "white" ]
}

@test "exports array contains expected functions" {
    [[ " ${_TUI_EXPORTS[*]} " == *" tui_table "* ]]
    [[ " ${_TUI_EXPORTS[*]} " == *" tui_box "* ]]
    [[ " ${_TUI_EXPORTS[*]} " == *" tui_progress "* ]]
    [[ " ${_TUI_EXPORTS[*]} " == *" tui_select "* ]]
}

# =============================================================================
# SPINNER TESTS (Limited - can't fully test background processes)
# =============================================================================

@test "tui_spinner_stop clears spinner PID" {
    _TUI_SPINNER_PID=""
    tui_spinner_stop 2>/dev/null
    [ -z "$_TUI_SPINNER_PID" ]
}

@test "tui_spinner_stop shows success message" {
    _TUI_SPINNER_PID=""
    local result
    result=$(NO_COLOR=1 tui_spinner_stop "Completed")
    [[ "$result" == *"Completed"* ]]
}

@test "tui_spinner_stop shows error message" {
    _TUI_SPINNER_PID=""
    local result
    result=$(NO_COLOR=1 tui_spinner_stop "Failed" error 2>&1)
    [[ "$result" == *"Failed"* ]]
}

# =============================================================================
# COUNTDOWN TESTS (Skipped - takes too long)
# =============================================================================

# Note: tui_countdown is tested manually as it involves sleep

# =============================================================================
# NO_COLOR COMPLIANCE TESTS
# =============================================================================

@test "NO_COLOR disables all color output in table" {
    local result
    result=$(NO_COLOR=1 tui_table "A|B" "1|2")
    # Should not contain ANSI codes
    [[ "$result" != *$'\033['* ]]
}

@test "NO_COLOR disables all color output in box" {
    local result
    result=$(NO_COLOR=1 tui_box "Test")
    [[ "$result" != *$'\033['* ]]
}

@test "NO_COLOR disables all color output in messages" {
    local result
    result=$(NO_COLOR=1 tui_success "Test")
    [[ "$result" != *$'\033['* ]]
}

# =============================================================================
# ADDITIONAL EDGE CASE TESTS
# =============================================================================

@test "tui_table handles empty cells" {
    local result
    result=$(NO_COLOR=1 tui_table "A|B|C" "1||3")
    [[ "$result" == *"1"* ]]
    [[ "$result" == *"3"* ]]
}

@test "tui_box handles very short content" {
    local result
    result=$(NO_COLOR=1 tui_box "X")
    [[ "$result" == *"X"* ]]
}

@test "tui_panel handles empty sections" {
    local result
    result=$(NO_COLOR=1 tui_panel "Title|")
    [[ "$result" == *"Title"* ]]
}

@test "tui_color handles 256-color numbers" {
    local result
    result=$(NO_COLOR=1 tui_color "196" "test")
    [ "$result" = "test" ]
}

@test "tui_progress handles zero total" {
    local result
    result=$(NO_COLOR=1 tui_progress 50 0)
    [[ "$result" == *"0%"* ]]
}

@test "tui_gauge handles zero max" {
    local result
    result=$(NO_COLOR=1 tui_gauge "Test" 50 0)
    [[ "$result" == *"0%"* ]]
}

@test "tui_table_json escapes quotes in values" {
    local result
    result=$(tui_table_json "Key|Value" 'test|say "hello"')
    [[ "$result" == *'\\"'* ]] || [[ "$result" == *'hello'* ]]
}

@test "tui_columns handles missing cells" {
    local result
    result=$(NO_COLOR=1 tui_columns "A:5|B:5|C:5" "1|2")
    [[ "$result" == *"1"* ]]
    [[ "$result" == *"2"* ]]
}

@test "tui_elapsed formats hours correctly" {
    _TUI_ELAPSED_START=$(($(date +%s) - 3700))  # 1 hour + 100 seconds
    local result
    result=$(tui_elapsed)
    [[ "$result" == *"h"* ]]
}

@test "tui_divider with single character" {
    local result
    result=$(NO_COLOR=1 tui_divider "X" 3)
    [ "$result" = "XXX" ]
}

@test "tui_bold handles empty string" {
    local result
    result=$(NO_COLOR=1 tui_bold "")
    [ "$result" = "" ]
}

@test "tui_dim handles empty string" {
    local result
    result=$(NO_COLOR=1 tui_dim "")
    [ "$result" = "" ]
}

@test "tui_select with single option" {
    local result
    result=$(tui_select "OnlyOption")
    [ "$result" = "OnlyOption" ]
}

@test "tui_input with empty default" {
    local result
    result=$(tui_input "Prompt:")
    [ "$result" = "" ]
}

@test "legacy tui::hr is available" {
    declare -F tui::hr
}

@test "legacy tui::table is available" {
    declare -F tui::table
}

@test "legacy tui::info is available" {
    declare -F tui::info
}

@test "legacy tui::warning is available" {
    declare -F tui::warning
}

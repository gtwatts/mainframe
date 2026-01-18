#!/usr/bin/env bash
# =============================================================================
# MAINFRAME: Structured Logging Library Tests
# =============================================================================
# Run with: bash tests/log_test.sh
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the library
source "$PROJECT_ROOT/lib/log.sh"

# Test counters
declare -i TESTS_RUN=0
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0

# Temp file for output testing
TEMP_LOG="/tmp/mainframe_log_test_$$.log"

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
    
    # Reset state before each test
    log::set_level "debug"
    log::set_format "text"
    log::set_output ""
    log::clear_context
    rm -f "$TEMP_LOG"
    
    # Run test in subshell to isolate
    local output
    if output=$("$func" 2>&1); then
        ((TESTS_PASSED++))
        printf '  %s %s\n' "$(_green '✓')" "$name"
    else
        ((TESTS_FAILED++))
        printf '  %s %s\n' "$(_red '✗')" "$name"
        [[ -n "$output" ]] && printf '      %s\n' "$output"
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

# Assert contains substring
assert_contains() {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" == *"$needle"* ]] || {
        printf 'String does not contain: %s\nIn: %s\n' "$needle" "$haystack" >&2
        return 1
    }
}

# Assert does NOT contain substring
assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" != *"$needle"* ]] || {
        printf 'String should not contain: %s\nIn: %s\n' "$needle" "$haystack" >&2
        return 1
    }
}

# Assert matches regex
assert_matches() {
    local string="$1"
    local pattern="$2"
    [[ "$string" =~ $pattern ]] || {
        printf 'String does not match pattern: %s\nString: %s\n' "$pattern" "$string" >&2
        return 1
    }
}

# Assert JSON is valid (basic check)
assert_json_valid() {
    local json="$1"
    # Basic validation: starts with { and ends with }
    [[ "$json" =~ ^\{.*\}$ ]] || {
        printf 'Invalid JSON: %s\n' "$json" >&2
        return 1
    }
}

# =============================================================================
# CONFIGURATION TESTS
# =============================================================================

test_set_level_valid() {
    log::set_level "debug"
    assert_eq "debug" "$(log::get_level)"
    
    log::set_level "info"
    assert_eq "info" "$(log::get_level)"
    
    log::set_level "warn"
    assert_eq "warn" "$(log::get_level)"
    
    log::set_level "error"
    assert_eq "error" "$(log::get_level)"
}

test_set_level_case_insensitive() {
    log::set_level "DEBUG"
    assert_eq "debug" "$(log::get_level)"
    
    log::set_level "Info"
    assert_eq "info" "$(log::get_level)"
}

test_set_level_invalid_falls_back() {
    log::set_level "info"
    log::set_level "invalid" 2>/dev/null
    assert_eq "info" "$(log::get_level)"
}

test_set_format_valid() {
    log::set_format "json"
    assert_eq "json" "$(log::get_format)"
    
    log::set_format "text"
    assert_eq "text" "$(log::get_format)"
    
    log::set_format "pretty"
    assert_eq "pretty" "$(log::get_format)"
}

test_set_format_invalid_falls_back() {
    log::set_format "text"
    log::set_format "invalid" 2>/dev/null
    assert_eq "text" "$(log::get_format)"
}

test_set_output_to_file() {
    log::set_output "$TEMP_LOG"
    assert_eq "$TEMP_LOG" "$(log::get_output)"
    
    log::info "test message"
    [[ -f "$TEMP_LOG" ]] || return 1
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" "test message"
}

test_set_context() {
    log::set_context app="myapp" env="prod"
    
    log::set_format "json"
    log::set_output "$TEMP_LOG"
    log::info "test"
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" '"app":"myapp"'
    assert_contains "$content" '"env":"prod"'
}

test_clear_context() {
    log::set_context app="myapp"
    log::clear_context
    
    log::set_format "json"
    log::set_output "$TEMP_LOG"
    log::info "test"
    
    local content
    content=$(<"$TEMP_LOG")
    assert_not_contains "$content" '"app"'
}

# =============================================================================
# BASIC LOGGING TESTS
# =============================================================================

test_log_debug() {
    log::set_level "debug"
    log::set_output "$TEMP_LOG"
    log::debug "debug message"
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" "DEBUG"
    assert_contains "$content" "debug message"
}

test_log_info() {
    log::set_output "$TEMP_LOG"
    log::info "info message"
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" "INFO"
    assert_contains "$content" "info message"
}

test_log_warn() {
    log::set_output "$TEMP_LOG"
    log::warn "warning message"
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" "WARN"
    assert_contains "$content" "warning message"
}

test_log_error() {
    log::set_output "$TEMP_LOG"
    log::error "error message"
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" "ERROR"
    assert_contains "$content" "error message"
}

test_log_with_extra_fields() {
    log::set_output "$TEMP_LOG"
    log::info "user login" user_id=123 ip="192.168.1.1"
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" "user_id=123"
    assert_contains "$content" "ip=192.168.1.1"
}

test_log_level_filtering() {
    log::set_level "warn"
    log::set_output "$TEMP_LOG"
    
    log::debug "debug message"
    log::info "info message"
    log::warn "warn message"
    log::error "error message"
    
    local content
    content=$(<"$TEMP_LOG")
    
    assert_not_contains "$content" "debug message"
    assert_not_contains "$content" "info message"
    assert_contains "$content" "warn message"
    assert_contains "$content" "error message"
}

# =============================================================================
# JSON FORMAT TESTS
# =============================================================================

test_json_format_basic() {
    log::set_format "json"
    log::set_output "$TEMP_LOG"
    log::info "test message"
    
    local content
    content=$(<"$TEMP_LOG")
    assert_json_valid "$content"
    assert_contains "$content" '"level":"info"'
    assert_contains "$content" '"msg":"test message"'
}

test_json_format_with_timestamp() {
    log::set_format "json"
    log::set_output "$TEMP_LOG"
    log::info "test"
    
    local content
    content=$(<"$TEMP_LOG")
    # ISO8601 timestamp pattern
    assert_matches "$content" '"timestamp":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"'
}

test_json_format_with_fields() {
    log::set_format "json"
    log::set_output "$TEMP_LOG"
    log::info "event" action="login" user_id=42
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" '"action":"login"'
    assert_contains "$content" '"user_id":42'
}

test_json_direct() {
    log::set_output "$TEMP_LOG"
    log::json "info" "User logged in" user_id=123 ip="1.2.3.4" action="login"
    
    local content
    content=$(<"$TEMP_LOG")
    assert_json_valid "$content"
    assert_contains "$content" '"level":"info"'
    assert_contains "$content" '"msg":"User logged in"'
    assert_contains "$content" '"user_id":123'
    assert_contains "$content" '"ip":"1.2.3.4"'
    assert_contains "$content" '"action":"login"'
}

test_json_escapes_special_chars() {
    log::set_format "json"
    log::set_output "$TEMP_LOG"
    log::info 'Message with "quotes" and \backslash'
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" '\"quotes\"'
    assert_contains "$content" '\\backslash'
}

test_json_auto_type_detection() {
    log::set_output "$TEMP_LOG"
    log::json "info" "types" num=42 bool=true str="hello" null=null
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" '"num":42'
    assert_contains "$content" '"bool":true'
    assert_contains "$content" '"str":"hello"'
    assert_contains "$content" '"null":null'
}

# =============================================================================
# PRETTY FORMAT TESTS
# =============================================================================

test_pretty_format() {
    log::set_format "pretty"
    log::set_output "$TEMP_LOG"
    log::info "pretty message"
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" "INFO"
    assert_contains "$content" "pretty message"
}

# =============================================================================
# TIMING TESTS
# =============================================================================

test_time_start_and_end() {
    log::set_output "$TEMP_LOG"
    
    log::time_start "test_operation"
    sleep 0.1
    log::time_end "test_operation"
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" "Timer completed"
    assert_contains "$content" "test_operation"
    assert_contains "$content" "duration"
}

test_time_command() {
    log::set_output "$TEMP_LOG"
    
    log::time "sleep_test" sleep 0.1
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" "sleep_test"
    assert_contains "$content" "exit_code=0"
}

test_time_end_missing_timer() {
    log::set_output "$TEMP_LOG"
    
    log::time_end "nonexistent" 2>/dev/null
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" "Timer not found"
}

# =============================================================================
# LOG ROTATION TESTS
# =============================================================================

test_parse_size() {
    local result
    result=$(_log_parse_size "10K")
    assert_eq "10240" "$result"
    
    result=$(_log_parse_size "5M")
    assert_eq "5242880" "$result"
    
    result=$(_log_parse_size "1G")
    assert_eq "1073741824" "$result"
    
    result=$(_log_parse_size "100")
    assert_eq "100" "$result"
}

test_needs_rotation_false() {
    echo "small content" > "$TEMP_LOG"
    
    if log::needs_rotation "$TEMP_LOG" "1M"; then
        return 1  # Should not need rotation
    fi
}

test_needs_rotation_true() {
    # Create a file larger than threshold
    dd if=/dev/zero of="$TEMP_LOG" bs=1024 count=10 2>/dev/null
    
    if ! log::needs_rotation "$TEMP_LOG" "1K"; then
        return 1  # Should need rotation
    fi
}

test_rotate_creates_backup() {
    log::set_output "$TEMP_LOG"
    
    # Create content larger than 100 bytes
    for i in {1..20}; do
        log::info "This is log line number $i for testing rotation"
    done
    
    log::rotate "$TEMP_LOG" --max-size 100 --keep 3
    
    # Check that rotation happened
    [[ -f "${TEMP_LOG}.1" ]] || return 1
}

# =============================================================================
# UTILITY FUNCTION TESTS
# =============================================================================

test_trace_includes_caller() {
    log::set_output "$TEMP_LOG"
    
    test_helper_func() {
        log::trace "traced message"
    }
    test_helper_func
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" "test_helper_func"
    assert_contains "$content" "caller="
}

test_printf_style_logging() {
    log::set_output "$TEMP_LOG"
    
    log::infof "User %s logged in from %s" "alice" "192.168.1.1"
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" "User alice logged in from 192.168.1.1"
}

test_conditional_logging_true() {
    log::set_output "$TEMP_LOG"
    
    local DEBUG=1
    log::debug_if "$DEBUG" "conditional message"
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" "conditional message"
}

test_conditional_logging_false() {
    log::set_output "$TEMP_LOG"
    
    local DEBUG=""
    log::debug_if "$DEBUG" "should not appear"
    
    # File should be empty or not contain the message
    if [[ -f "$TEMP_LOG" ]]; then
        local content
        content=$(<"$TEMP_LOG")
        assert_not_contains "$content" "should not appear"
    fi
}

test_fail_returns_error() {
    log::set_output "$TEMP_LOG"
    
    if log::fail "expected failure" 2>/dev/null; then
        return 1  # Should have returned error
    fi
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" "expected failure"
}

test_env_logging() {
    log::set_output "$TEMP_LOG"
    
    log::env
    
    local content
    content=$(<"$TEMP_LOG")
    assert_contains "$content" "bash_version="
    assert_contains "$content" "user="
}

# =============================================================================
# EDGE CASES
# =============================================================================

test_empty_message() {
    log::set_output "$TEMP_LOG"
    log::info ""
    
    [[ -f "$TEMP_LOG" ]] || return 1
}

test_special_characters_in_message() {
    log::set_output "$TEMP_LOG"
    log::info 'Message with $vars and `backticks` and "quotes"'
    
    local content
    content=$(<"$TEMP_LOG")
    # Should not evaluate the shell constructs
    assert_contains "$content" '$vars'
}

test_multiline_message() {
    log::set_format "json"
    log::set_output "$TEMP_LOG"
    log::info $'Line 1\nLine 2\nLine 3'
    
    local content
    content=$(<"$TEMP_LOG")
    # JSON should have escaped newlines (literal \n in JSON output)
    assert_contains "$content" '\n'
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

main() {
    printf '\n%s\n' "$(_yellow '═══════════════════════════════════════════════════════════════')"
    printf '%s\n' "$(_yellow '  MAINFRAME Structured Logging Tests')"
    printf '%s\n\n' "$(_yellow '═══════════════════════════════════════════════════════════════')"
    
    printf '%s\n' "Configuration Tests:"
    test_case "set_level accepts valid levels" test_set_level_valid
    test_case "set_level is case insensitive" test_set_level_case_insensitive
    test_case "set_level falls back on invalid" test_set_level_invalid_falls_back
    test_case "set_format accepts valid formats" test_set_format_valid
    test_case "set_format falls back on invalid" test_set_format_invalid_falls_back
    test_case "set_output writes to file" test_set_output_to_file
    test_case "set_context adds persistent fields" test_set_context
    test_case "clear_context removes fields" test_clear_context
    
    printf '\n%s\n' "Basic Logging Tests:"
    test_case "log::debug outputs DEBUG level" test_log_debug
    test_case "log::info outputs INFO level" test_log_info
    test_case "log::warn outputs WARN level" test_log_warn
    test_case "log::error outputs ERROR level" test_log_error
    test_case "logs include extra fields" test_log_with_extra_fields
    test_case "log level filtering works" test_log_level_filtering
    
    printf '\n%s\n' "JSON Format Tests:"
    test_case "JSON format produces valid JSON" test_json_format_basic
    test_case "JSON includes ISO8601 timestamp" test_json_format_with_timestamp
    test_case "JSON includes extra fields" test_json_format_with_fields
    test_case "log::json direct function works" test_json_direct
    test_case "JSON escapes special characters" test_json_escapes_special_chars
    test_case "JSON auto-detects types" test_json_auto_type_detection
    
    printf '\n%s\n' "Pretty Format Tests:"
    test_case "pretty format works" test_pretty_format
    
    printf '\n%s\n' "Timing Tests:"
    test_case "time_start and time_end work" test_time_start_and_end
    test_case "log::time times commands" test_time_command
    test_case "time_end handles missing timer" test_time_end_missing_timer
    
    printf '\n%s\n' "Log Rotation Tests:"
    test_case "size parsing works" test_parse_size
    test_case "needs_rotation returns false for small" test_needs_rotation_false
    test_case "needs_rotation returns true for large" test_needs_rotation_true
    test_case "rotate creates backup files" test_rotate_creates_backup
    
    printf '\n%s\n' "Utility Function Tests:"
    test_case "log::trace includes caller info" test_trace_includes_caller
    test_case "printf-style logging works" test_printf_style_logging
    test_case "conditional logging when true" test_conditional_logging_true
    test_case "conditional logging when false" test_conditional_logging_false
    test_case "log::fail returns error code" test_fail_returns_error
    test_case "log::env outputs environment" test_env_logging
    
    printf '\n%s\n' "Edge Cases:"
    test_case "handles empty message" test_empty_message
    test_case "handles special characters" test_special_characters_in_message
    test_case "handles multiline message" test_multiline_message
    
    # Cleanup
    rm -f "$TEMP_LOG" "${TEMP_LOG}."*
    
    # Summary
    printf '\n%s\n' "$(_yellow '═══════════════════════════════════════════════════════════════')"
    printf '  Tests: %d | ' "$TESTS_RUN"
    printf '%s | ' "$(_green "Passed: $TESTS_PASSED")"
    printf '%s\n' "$(_red "Failed: $TESTS_FAILED")"
    printf '%s\n\n' "$(_yellow '═══════════════════════════════════════════════════════════════')"
    
    # Exit with failure if any tests failed
    ((TESTS_FAILED == 0))
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

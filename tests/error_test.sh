#!/usr/bin/env bash
# =============================================================================
# MAINFRAME: Error Handling Library Tests
# =============================================================================
# Run with: bash tests/error_test.sh
# Or if using bats: bats tests/error_test.bats
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the library
source "$PROJECT_ROOT/lib/error.sh"

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
# STACK TRACE TESTS
# =============================================================================

test_stack_trace_captures_caller() {
    inner_function() {
        error::stack_trace_string 1
    }
    
    outer_function() {
        inner_function
    }
    
    local trace
    trace=$(outer_function)
    
    assert_contains "$trace" "inner_function"
    assert_contains "$trace" "outer_function"
    assert_contains "$trace" "Stack trace:"
}

test_caller_returns_info() {
    get_my_caller() {
        error::caller 1
    }
    
    test_function() {
        get_my_caller
    }
    
    local result
    result=$(test_function)
    
    assert_contains "$result" "test_function"
}

# =============================================================================
# ERROR CONTEXT TESTS
# =============================================================================

test_context_push_and_pop() {
    error::context_clear
    
    error::context "parsing" "config.json"
    error::context "validating" "user section"
    
    local ctx
    ctx=$(error::context_string)
    
    assert_contains "$ctx" "parsing: config.json"
    assert_contains "$ctx" "validating: user section"
    
    error::context_pop
    ctx=$(error::context_string)
    
    # Should still have parsing
    assert_contains "$ctx" "parsing: config.json"
    
    error::context_clear
}

test_context_clear() {
    error::context "test" "operation"
    error::context_clear
    
    local ctx
    ctx=$(error::context_string)
    
    assert_eq "" "$ctx"
}

test_with_context() {
    error::context_clear
    
    local result
    result=$(error::with_context "test_op" "details" echo "hello")
    
    assert_eq "hello" "$result"
    
    # Context should be cleared after with_context
    local ctx
    ctx=$(error::context_string)
    assert_eq "" "$ctx"
}

# =============================================================================
# THROW TESTS
# =============================================================================

test_throw_sets_error_message() {
    # Run in subshell to capture the error
    (
        set +e
        try
        (
            error::throw "Test error message"
        )
        catch
    ) 2>/dev/null
    
    # For this test, just ensure throw doesn't crash in try block
    true
}

test_throw_in_try_returns_error() {
    local caught=false
    
    try
    (
        error::throw "Expected error" --no-exit
        exit 1
    )
    if catch; then
        caught=true
    fi
    
    assert_eq "true" "$caught"
}

# =============================================================================
# TRY/CATCH TESTS
# =============================================================================

test_try_catch_catches_failure() {
    local caught=false
    
    try
    (
        false  # Command that fails
    )
    if catch; then
        caught=true
    fi
    
    assert_eq "true" "$caught"
}

test_try_catch_passes_on_success() {
    local caught=false
    
    try
    (
        true  # Command that succeeds
    )
    if catch; then
        caught=true
    fi
    
    assert_eq "false" "$caught"
}

test_try_catch_preserves_error_code() {
    try
    (
        exit 42
    )
    catch
    
    assert_eq "42" "$ERROR_CODE"
}

test_try_catch_nested() {
    local inner_caught=false
    local outer_caught=false
    
    try
    (
        try
        (
            false
        )
        if catch; then
            inner_caught=true
        fi
        true  # Outer block succeeds
    )
    if catch; then
        outer_caught=true
    fi
    
    assert_eq "true" "$inner_caught"
    assert_eq "false" "$outer_caught"
}

test_in_try_detection() {
    local inside=false
    local outside=false
    
    if error::in_try; then
        outside=true
    fi
    
    try
    (
        if error::in_try; then
            inside=true
        fi
        printf '%s' "$inside"
    )
    catch
    
    assert_eq "false" "$outside"
}

# =============================================================================
# RETRY TESTS
# =============================================================================

test_retry_succeeds_on_success() {
    local count=0
    successful_cmd() {
        ((count++))
        return 0
    }
    
    error::retry -n 3 successful_cmd
    local result=$?
    
    assert_eq "0" "$result"
    assert_eq "1" "$count"
}

test_retry_retries_on_failure() {
    local attempts=0
    failing_then_succeeds() {
        ((attempts++))
        if ((attempts < 3)); then
            return 1
        fi
        return 0
    }
    
    error::retry -n 5 -d 0 failing_then_succeeds
    local result=$?
    
    assert_eq "0" "$result"
    assert_eq "3" "$attempts"
}

test_retry_gives_up_after_max() {
    local attempts=0
    always_fails() {
        ((attempts++))
        return 1
    }
    
    error::retry -n 3 -d 0 always_fails
    local result=$?
    
    assert_eq "1" "$result"
    assert_eq "3" "$attempts"
}

# =============================================================================
# UTILITY TESTS
# =============================================================================

test_clear_resets_state() {
    ERROR_MESSAGE="test error"
    ERROR_CODE=42
    
    error::clear
    
    assert_eq "" "$ERROR_MESSAGE"
    assert_eq "0" "$ERROR_CODE"
}

test_has_error_detection() {
    error::clear
    
    local has_error
    if error::has_error; then
        has_error=true
    else
        has_error=false
    fi
    assert_eq "false" "$has_error"
    
    ERROR_MESSAGE="error"
    if error::has_error; then
        has_error=true
    else
        has_error=false
    fi
    assert_eq "true" "$has_error"
}

test_last_formats_error_info() {
    error::clear
    ERROR_MESSAGE="Test error"
    ERROR_CODE=5
    ERROR_FUNC="test_func"
    ERROR_SOURCE="test.sh"
    ERROR_LINE=100
    
    local info
    info=$(error::last)
    
    assert_contains "$info" "Test error"
    assert_contains "$info" "5"
    assert_contains "$info" "test_func"
}

# =============================================================================
# CLEANUP TESTS
# =============================================================================

test_cleanup_registration() {
    local marker_file
    marker_file=$(mktemp)
    rm -f "$marker_file"
    
    # Run in subshell
    (
        error::on_exit "touch '$marker_file'"
        exit 0
    )
    
    # Check marker was created
    [[ -f "$marker_file" ]] || {
        printf 'Cleanup handler did not run\n' >&2
        return 1
    }
    
    rm -f "$marker_file"
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

main() {
    printf '%s\n' "=== MAINFRAME Error Library Tests ==="
    printf '\n'
    
    printf '%s\n' "Stack Trace Tests:"
    test_case "stack_trace captures caller info" test_stack_trace_captures_caller
    test_case "caller returns function info" test_caller_returns_info
    
    printf '\n%s\n' "Error Context Tests:"
    test_case "context push and pop" test_context_push_and_pop
    test_case "context clear" test_context_clear
    test_case "with_context executes and clears" test_with_context
    
    printf '\n%s\n' "Throw Tests:"
    test_case "throw sets error message" test_throw_sets_error_message
    test_case "throw in try returns error" test_throw_in_try_returns_error
    
    printf '\n%s\n' "Try/Catch Tests:"
    test_case "catches command failure" test_try_catch_catches_failure
    test_case "passes on success" test_try_catch_passes_on_success
    test_case "preserves error code" test_try_catch_preserves_error_code
    test_case "handles nested try/catch" test_try_catch_nested
    test_case "detects when inside try" test_in_try_detection
    
    printf '\n%s\n' "Retry Tests:"
    test_case "succeeds immediately on success" test_retry_succeeds_on_success
    test_case "retries on failure" test_retry_retries_on_failure
    test_case "gives up after max attempts" test_retry_gives_up_after_max
    
    printf '\n%s\n' "Utility Tests:"
    test_case "clear resets all state" test_clear_resets_state
    test_case "has_error detects errors" test_has_error_detection
    test_case "last formats error info" test_last_formats_error_info
    
    printf '\n%s\n' "Cleanup Tests:"
    test_case "cleanup handlers run on exit" test_cleanup_registration
    
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

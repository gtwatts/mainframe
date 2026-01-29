#!/usr/bin/env bash
# =============================================================================
# testing.sh - Testing and Mocking Framework for MAINFRAME
# =============================================================================
# Description: Provides testing utilities including function mocking,
#              environment mocking, assertions, and test fixtures.
# Version: 1.0.0
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_TESTING_LOADED:-}" ]] && return 0
declare -g _MAINFRAME_TESTING_LOADED=1

# =============================================================================
# Global State
# =============================================================================

declare -gA _MOCK_FUNCTIONS=()      # function -> mock_body
declare -gA _MOCK_CALL_COUNT=()     # function -> call_count
declare -gA _MOCK_CALL_ARGS=()      # function -> last_args
declare -gA _MOCK_ENV_BACKUP=()     # var -> original_value
declare -ga _FIXTURE_TEMPDIRS=()    # List of temp dirs to clean up
declare -g _TEST_CURRENT=""         # Current test name
declare -g _TEST_PASS_COUNT=0
declare -g _TEST_FAIL_COUNT=0

# =============================================================================
# Mock Functions API
# =============================================================================

# mock_function - Replace a function with a mock implementation
# Usage: mock_function <function_name> <mock_body>
# Example: mock_function "curl" 'echo "{\"status\": \"ok\"}"'
mock_function() {
    local func_name="$1"
    local mock_body="$2"

    [[ -z "$func_name" ]] && {
        echo "Usage: mock_function <function_name> <mock_body>" >&2
        return 1
    }

    # Backup original if it exists and not already mocked
    if declare -F "$func_name" &>/dev/null && [[ -z "${_MOCK_FUNCTIONS[$func_name]:-}" ]]; then
        # Save original function body
        _MOCK_FUNCTIONS["_orig_$func_name"]=$(declare -f "$func_name")
    fi

    # Track this mock
    _MOCK_FUNCTIONS[$func_name]="$mock_body"
    _MOCK_CALL_COUNT[$func_name]=0
    _MOCK_CALL_ARGS[$func_name]=""

    # Create mock function
    eval "$func_name() {
        _MOCK_CALL_COUNT[$func_name]=\$((\${_MOCK_CALL_COUNT[$func_name]} + 1))
        _MOCK_CALL_ARGS[$func_name]=\"\$*\"
        $mock_body
    }"
}

# mock_function_restore - Restore original function
# Usage: mock_function_restore <function_name>
mock_function_restore() {
    local func_name="$1"

    [[ -z "$func_name" ]] && {
        echo "Usage: mock_function_restore <function_name>" >&2
        return 1
    }

    # Restore original if we have it
    local orig="${_MOCK_FUNCTIONS[_orig_$func_name]:-}"
    if [[ -n "$orig" ]]; then
        eval "$orig"
    else
        # Just unset the mock
        unset -f "$func_name" 2>/dev/null || true
    fi

    # Clean up tracking
    unset "_MOCK_FUNCTIONS[$func_name]"
    unset "_MOCK_FUNCTIONS[_orig_$func_name]"
    unset "_MOCK_CALL_COUNT[$func_name]"
    unset "_MOCK_CALL_ARGS[$func_name]"
}

# mock_function_restore_all - Restore all mocked functions
mock_function_restore_all() {
    local func_name
    for func_name in "${!_MOCK_FUNCTIONS[@]}"; do
        [[ "$func_name" == _orig_* ]] && continue
        mock_function_restore "$func_name"
    done
}

# mock_call_count - Get call count for a mocked function
# Usage: mock_call_count <function_name>
mock_call_count() {
    local func_name="$1"
    echo "${_MOCK_CALL_COUNT[$func_name]:-0}"
}

# mock_last_args - Get last call arguments for a mocked function
# Usage: mock_last_args <function_name>
mock_last_args() {
    local func_name="$1"
    echo "${_MOCK_CALL_ARGS[$func_name]:-}"
}

# =============================================================================
# Mock Environment API
# =============================================================================

# mock_env - Temporarily set an environment variable
# Usage: mock_env <var_name> <value>
mock_env() {
    local var_name="$1"
    local value="$2"

    [[ -z "$var_name" ]] && {
        echo "Usage: mock_env <var_name> <value>" >&2
        return 1
    }

    # Backup original if not already backed up
    if [[ -z "${_MOCK_ENV_BACKUP[$var_name]+set}" ]]; then
        _MOCK_ENV_BACKUP[$var_name]="${!var_name:-__UNSET__}"
    fi

    export "$var_name=$value"
}

# mock_env_restore - Restore original environment variable
# Usage: mock_env_restore <var_name>
mock_env_restore() {
    local var_name="$1"

    [[ -z "$var_name" ]] && {
        echo "Usage: mock_env_restore <var_name>" >&2
        return 1
    }

    local orig="${_MOCK_ENV_BACKUP[$var_name]:-}"

    if [[ "$orig" == "__UNSET__" ]]; then
        unset "$var_name"
    elif [[ -n "$orig" ]]; then
        export "$var_name=$orig"
    fi

    unset "_MOCK_ENV_BACKUP[$var_name]"
}

# mock_env_restore_all - Restore all mocked environment variables
mock_env_restore_all() {
    local var_name
    for var_name in "${!_MOCK_ENV_BACKUP[@]}"; do
        mock_env_restore "$var_name"
    done
}

# =============================================================================
# Assertion API
# =============================================================================

# assert_equals - Assert two values are equal
# Usage: assert_equals <expected> <actual> [message]
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"

    if [[ "$expected" == "$actual" ]]; then
        echo "PASS: $message"
        ((_TEST_PASS_COUNT++))
        return 0
    else
        echo "FAIL: $message"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        ((_TEST_FAIL_COUNT++))
        return 1
    fi
}

# assert_not_equals - Assert two values are not equal
# Usage: assert_not_equals <not_expected> <actual> [message]
assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local message="${3:-Values should not be equal}"

    if [[ "$not_expected" != "$actual" ]]; then
        echo "PASS: $message"
        ((_TEST_PASS_COUNT++))
        return 0
    else
        echo "FAIL: $message"
        echo "  Did not expect: '$not_expected'"
        ((_TEST_FAIL_COUNT++))
        return 1
    fi
}

# assert_contains - Assert string contains substring
# Usage: assert_contains <haystack> <needle> [message]
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"

    if [[ "$haystack" == *"$needle"* ]]; then
        echo "PASS: $message"
        ((_TEST_PASS_COUNT++))
        return 0
    else
        echo "FAIL: $message"
        echo "  String: '$haystack'"
        echo "  Should contain: '$needle'"
        ((_TEST_FAIL_COUNT++))
        return 1
    fi
}

# assert_empty - Assert value is empty
# Usage: assert_empty <value> [message]
assert_empty() {
    local value="$1"
    local message="${2:-Value should be empty}"

    if [[ -z "$value" ]]; then
        echo "PASS: $message"
        ((_TEST_PASS_COUNT++))
        return 0
    else
        echo "FAIL: $message"
        echo "  Value: '$value'"
        ((_TEST_FAIL_COUNT++))
        return 1
    fi
}

# assert_not_empty - Assert value is not empty
# Usage: assert_not_empty <value> [message]
assert_not_empty() {
    local value="$1"
    local message="${2:-Value should not be empty}"

    if [[ -n "$value" ]]; then
        echo "PASS: $message"
        ((_TEST_PASS_COUNT++))
        return 0
    else
        echo "FAIL: $message"
        ((_TEST_FAIL_COUNT++))
        return 1
    fi
}

# assert_exit_code - Assert command exits with expected code
# Usage: assert_exit_code <expected_code> <command> [args...]
assert_exit_code() {
    local expected="$1"
    shift
    local cmd="$*"

    eval "$cmd" >/dev/null 2>&1
    local actual=$?

    if [[ "$expected" -eq "$actual" ]]; then
        echo "PASS: Exit code $expected for: $cmd"
        ((_TEST_PASS_COUNT++))
        return 0
    else
        echo "FAIL: Exit code mismatch for: $cmd"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        ((_TEST_FAIL_COUNT++))
        return 1
    fi
}

# assert_file_exists - Assert file exists
# Usage: assert_file_exists <path> [message]
assert_file_exists() {
    local path="$1"
    local message="${2:-File should exist: $path}"

    if [[ -f "$path" ]]; then
        echo "PASS: $message"
        ((_TEST_PASS_COUNT++))
        return 0
    else
        echo "FAIL: $message"
        ((_TEST_FAIL_COUNT++))
        return 1
    fi
}

# assert_file_contains - Assert file contains string
# Usage: assert_file_contains <path> <string> [message]
assert_file_contains() {
    local path="$1"
    local string="$2"
    local message="${3:-File should contain string}"

    if grep -q "$string" "$path" 2>/dev/null; then
        echo "PASS: $message"
        ((_TEST_PASS_COUNT++))
        return 0
    else
        echo "FAIL: $message"
        echo "  File: $path"
        echo "  Should contain: '$string'"
        ((_TEST_FAIL_COUNT++))
        return 1
    fi
}

# assert_true - Assert condition is true
# Usage: assert_true <condition> [message]
assert_true() {
    local condition="$1"
    local message="${2:-Condition should be true}"

    if eval "$condition" 2>/dev/null; then
        echo "PASS: $message"
        ((_TEST_PASS_COUNT++))
        return 0
    else
        echo "FAIL: $message"
        echo "  Condition: $condition"
        ((_TEST_FAIL_COUNT++))
        return 1
    fi
}

# assert_false - Assert condition is false
# Usage: assert_false <condition> [message]
assert_false() {
    local condition="$1"
    local message="${2:-Condition should be false}"

    if ! eval "$condition" 2>/dev/null; then
        echo "PASS: $message"
        ((_TEST_PASS_COUNT++))
        return 0
    else
        echo "FAIL: $message"
        echo "  Condition: $condition"
        ((_TEST_FAIL_COUNT++))
        return 1
    fi
}

# =============================================================================
# Fixture API
# =============================================================================

# fixture_tempdir - Create a temporary directory (auto-cleaned on test end)
# Usage: fixture_tempdir <varname>
fixture_tempdir() {
    local varname="$1"

    [[ -z "$varname" ]] && {
        echo "Usage: fixture_tempdir <varname>" >&2
        return 1
    }

    local tmpdir
    tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'mainframe-test')

    _FIXTURE_TEMPDIRS+=("$tmpdir")

    # Set the variable
    eval "$varname=\"$tmpdir\""

    echo "$tmpdir"
}

# fixture_tempfile - Create a temporary file (auto-cleaned on test end)
# Usage: fixture_tempfile <varname> [content]
fixture_tempfile() {
    local varname="$1"
    local content="${2:-}"

    [[ -z "$varname" ]] && {
        echo "Usage: fixture_tempfile <varname> [content]" >&2
        return 1
    }

    local tmpfile
    tmpfile=$(mktemp 2>/dev/null || mktemp -t 'mainframe-test')

    [[ -n "$content" ]] && printf '%s' "$content" > "$tmpfile"

    # Track parent dir for cleanup
    _FIXTURE_TEMPDIRS+=("$(dirname "$tmpfile")/$(basename "$tmpfile")")

    eval "$varname=\"$tmpfile\""

    echo "$tmpfile"
}

# fixture_cleanup - Clean up all fixtures
fixture_cleanup() {
    local item
    for item in "${_FIXTURE_TEMPDIRS[@]}"; do
        rm -rf "$item" 2>/dev/null || true
    done
    _FIXTURE_TEMPDIRS=()
}

# =============================================================================
# Test Runner API
# =============================================================================

# test_start - Start a test
# Usage: test_start <test_name>
test_start() {
    local name="$1"
    _TEST_CURRENT="$name"
    echo ""
    echo "=== TEST: $name ==="
}

# test_end - End a test and clean up
# Usage: test_end
test_end() {
    mock_function_restore_all
    mock_env_restore_all
    fixture_cleanup
    _TEST_CURRENT=""
}

# test_summary - Print test summary
# Usage: test_summary
test_summary() {
    echo ""
    echo "================================"
    echo "TEST SUMMARY"
    echo "================================"
    echo "Passed: $_TEST_PASS_COUNT"
    echo "Failed: $_TEST_FAIL_COUNT"
    echo "Total:  $((_TEST_PASS_COUNT + _TEST_FAIL_COUNT))"
    echo ""

    if [[ $_TEST_FAIL_COUNT -eq 0 ]]; then
        echo "All tests passed!"
        return 0
    else
        echo "Some tests failed."
        return 1
    fi
}

# test_reset - Reset test counters
test_reset() {
    _TEST_PASS_COUNT=0
    _TEST_FAIL_COUNT=0
    _TEST_CURRENT=""
}

# =============================================================================
# Module Exports
# =============================================================================

declare -ga _TESTING_EXPORTS=(
    # Mock functions
    mock_function
    mock_function_restore
    mock_function_restore_all
    mock_call_count
    mock_last_args
    # Mock environment
    mock_env
    mock_env_restore
    mock_env_restore_all
    # Assertions
    assert_equals
    assert_not_equals
    assert_contains
    assert_empty
    assert_not_empty
    assert_exit_code
    assert_file_exists
    assert_file_contains
    assert_true
    assert_false
    # Fixtures
    fixture_tempdir
    fixture_tempfile
    fixture_cleanup
    # Test runner
    test_start
    test_end
    test_summary
    test_reset
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${_TESTING_EXPORTS[@]}" 2>/dev/null || true
fi

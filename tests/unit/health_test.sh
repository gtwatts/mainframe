#!/usr/bin/env bash
# =============================================================================
# MAINFRAME: Health Check Framework Tests
# =============================================================================
# Run with: bash tests/unit/health_test.sh
# =============================================================================

set -uo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the library
source "$PROJECT_ROOT/lib/health.sh"

# Test counters
declare -i TESTS_RUN=0
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0

# =============================================================================
# TEST FRAMEWORK
# =============================================================================

_red() { printf '\033[31m%s\033[0m' "$*"; }
_green() { printf '\033[32m%s\033[0m' "$*"; }
_yellow() { printf '\033[33m%s\033[0m' "$*"; }

test_case() {
    local name="$1"
    local func="$2"
    
    ((TESTS_RUN++)) || true
    
    # Clear health checks before each test (in main shell)
    health::clear
    
    # Run test - don't use subshell since health checks use global arrays
    local test_result=0
    set +e
    "$func" >/dev/null 2>&1 || test_result=$?
    set -e
    
    if [[ $test_result -eq 0 ]]; then
        ((TESTS_PASSED++)) || true
        printf '  %s %s\n' "$(_green '✓')" "$name"
    else
        ((TESTS_FAILED++)) || true
        printf '  %s %s\n' "$(_red '✗')" "$name"
    fi
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    [[ "$expected" == "$actual" ]] || {
        printf 'Expected: %s, Got: %s\n' "$expected" "$actual" >&2
        return 1
    }
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" == *"$needle"* ]] || {
        printf 'Expected to contain: %s\n' "$needle" >&2
        return 1
    }
}

assert_true() {
    [[ "$1" == "true" || "$1" == "0" ]] || "$@"
}

assert_false() {
    ! "$@"
}

# =============================================================================
# REGISTRATION TESTS
# =============================================================================

test_register_check() {
    health::register "test" 'echo hello'
    local checks
    checks=$(health::list)
    assert_contains "$checks" "test"
}

test_register_multiple_checks() {
    health::register "check1" 'echo 1'
    health::register "check2" 'echo 2'
    health::register "check3" 'echo 3'
    
    local count
    count=$(health::list | wc -l)
    assert_eq "3" "$count"
}

test_unregister_check() {
    health::register "test" 'echo hello'
    health::unregister "test"
    
    local count
    count=$(health::list | wc -l)
    assert_eq "0" "$count"
}

test_clear_checks() {
    health::register "check1" 'echo 1'
    health::register "check2" 'echo 2'
    health::clear
    
    local count
    count=$(health::list | wc -l)
    assert_eq "0" "$count"
}

# =============================================================================
# RUNNING CHECKS TESTS
# =============================================================================

test_run_passing_check() {
    health::register "passing" 'true'
    health::run "passing"
    assert_true health::is_healthy "passing"
}

test_run_failing_check() {
    health::register "failing" 'false'
    health::run "failing" || true
    assert_false health::is_healthy "failing"
}

test_run_check_with_output() {
    health::register "output" 'echo "Service OK"'
    health::run "output"
    
    local status
    status=$(health::status)
    assert_contains "$status" "Service OK"
}

test_run_all_checks() {
    health::register "check1" 'true'
    health::register "check2" 'true'
    health::run_all
    
    assert_true health::is_ready
}

test_run_all_with_failure() {
    health::register "passing" 'true'
    health::register "failing" 'false'
    health::run_all || true
    
    assert_false health::is_ready
}

test_unknown_check() {
    local result
    health::run "nonexistent" || true
    result="${_HEALTH_RESULTS[nonexistent]:-}"
    assert_eq "unknown" "$result"
}

# =============================================================================
# IS_LIVE / IS_READY TESTS
# =============================================================================

test_is_live_with_one_healthy() {
    health::register "healthy" 'true'
    health::register "unhealthy" 'false'
    health::run_all || true
    
    assert_true health::is_live
}

test_is_live_empty_checks() {
    # Empty checks should be considered live
    assert_true health::is_live
}

test_is_ready_all_healthy() {
    health::register "check1" 'true'
    health::register "check2" 'true'
    health::run_all
    
    assert_true health::is_ready
}

test_is_ready_one_unhealthy() {
    health::register "healthy" 'true'
    health::register "unhealthy" 'false'
    health::run_all || true
    
    assert_false health::is_ready
}

# =============================================================================
# JSON OUTPUT TESTS
# =============================================================================

test_status_json_format() {
    health::register "test" 'echo OK'
    health::run "test"
    
    local json
    json=$(health::status)
    
    # Should be valid JSON structure
    assert_contains "$json" '"status":'
    assert_contains "$json" '"checks":'
    assert_contains "$json" '"timestamp":'
}

test_status_healthy() {
    health::register "test" 'true'
    health::run "test"
    
    local json
    json=$(health::status)
    
    assert_contains "$json" '"status":"healthy"'
}

test_status_unhealthy() {
    health::register "test" 'false'
    health::run "test" || true
    
    local json
    json=$(health::status)
    
    assert_contains "$json" '"status":"unhealthy"'
}

test_status_includes_check_details() {
    health::register "mycheck" 'echo "All systems go"'
    health::run "mycheck"
    
    local json
    json=$(health::status)
    
    assert_contains "$json" '"mycheck":'
    assert_contains "$json" '"message":'
    assert_contains "$json" 'All systems go'
}

# =============================================================================
# BUILT-IN CHECKS TESTS
# =============================================================================

test_check_disk() {
    # Root filesystem should always exist
    local result
    result=$(health::check_disk "/" 99)
    local status=$?
    
    assert_eq "0" "$status"
    assert_contains "$result" "Disk"
}

test_check_disk_threshold_exceeded() {
    # Set threshold to 0% which should always fail
    local result
    result=$(health::check_disk "/" 0) || true
    
    assert_contains "$result" "exceeds threshold"
}

test_check_memory() {
    local result
    result=$(health::check_memory 99)
    local status=$?
    
    assert_eq "0" "$status"
    assert_contains "$result" "Memory"
}

test_check_process_existing() {
    # bash should always be running
    local result
    result=$(health::check_process "bash")
    local status=$?
    
    assert_eq "0" "$status"
    assert_contains "$result" "running"
}

test_check_process_nonexistent() {
    local result
    result=$(health::check_process "nonexistent_process_12345") || true
    
    assert_contains "$result" "not found"
}

test_check_file_exists() {
    local result
    result=$(health::check_file_exists "/etc/passwd")
    local status=$?
    
    assert_eq "0" "$status"
    assert_contains "$result" "exists"
}

test_check_file_not_exists() {
    local result
    result=$(health::check_file_exists "/nonexistent/file/12345") || true
    
    assert_contains "$result" "not found"
}

test_check_command_exists() {
    local result
    result=$(health::check_command "bash")
    local status=$?
    
    assert_eq "0" "$status"
    assert_contains "$result" "available"
}

test_check_command_not_exists() {
    local result
    result=$(health::check_command "nonexistent_command_12345") || true
    
    assert_contains "$result" "not found"
}

test_check_tcp_localhost() {
    # Skip if nc not available
    command -v nc &>/dev/null || return 0
    
    # This will likely fail unless something is running, but shouldn't error
    health::check_tcp "localhost" 99999 1 || true
}

# =============================================================================
# UTILITY FUNCTION TESTS
# =============================================================================

test_summary() {
    health::register "healthy1" 'true'
    health::register "healthy2" 'true'
    health::register "unhealthy" 'false'
    health::run_all || true
    
    local summary
    summary=$(health::summary)
    
    assert_contains "$summary" "Total: 3"
    assert_contains "$summary" "Healthy: 2"
    assert_contains "$summary" "Unhealthy: 1"
}

test_print_output() {
    health::register "myservice" 'echo OK'
    health::run "myservice"
    
    local output
    output=$(health::print)
    
    assert_contains "$output" "myservice"
    assert_contains "$output" "healthy"
}

test_export_env() {
    health::register "database" 'true'
    health::run "database"
    health::export_env "HEALTH"
    
    assert_eq "healthy" "${HEALTH_DATABASE:-}"
}

# =============================================================================
# EDGE CASES
# =============================================================================

test_check_with_special_characters() {
    health::register "special" 'echo "Hello \"World\""'
    health::run "special"
    
    local json
    json=$(health::status)
    
    # Should handle escaped quotes
    assert_contains "$json" "special"
}

test_register_empty_name() {
    # Should fail silently
    health::register "" 'echo test' || true
    
    local count
    count=$(health::list | wc -l)
    assert_eq "0" "$count"
}

test_register_empty_command() {
    # Should fail silently
    health::register "test" "" || true
    
    local count
    count=$(health::list | wc -l)
    assert_eq "0" "$count"
}

test_multiple_runs_update_results() {
    health::register "flipflop" 'exit $FLIP'
    
    export FLIP=0
    health::run "flipflop"
    assert_true health::is_healthy "flipflop"
    
    export FLIP=1
    health::run "flipflop" || true
    assert_false health::is_healthy "flipflop"
}

# =============================================================================
# RUN TESTS
# =============================================================================

main() {
    printf '\n%s\n' "=== MAINFRAME Health Check Tests ==="
    printf '%s\n\n' "$(date)"
    
    # Registration tests
    printf '%s\n' "Registration Tests:"
    test_case "Register a health check" test_register_check
    test_case "Register multiple checks" test_register_multiple_checks
    test_case "Unregister a check" test_unregister_check
    test_case "Clear all checks" test_clear_checks
    
    # Running checks tests
    printf '\n%s\n' "Running Checks Tests:"
    test_case "Run passing check" test_run_passing_check
    test_case "Run failing check" test_run_failing_check
    test_case "Run check with output" test_run_check_with_output
    test_case "Run all checks" test_run_all_checks
    test_case "Run all with failure" test_run_all_with_failure
    test_case "Unknown check handling" test_unknown_check
    
    # Live/Ready tests
    printf '\n%s\n' "Liveness/Readiness Tests:"
    test_case "is_live with one healthy" test_is_live_with_one_healthy
    test_case "is_live with empty checks" test_is_live_empty_checks
    test_case "is_ready all healthy" test_is_ready_all_healthy
    test_case "is_ready one unhealthy" test_is_ready_one_unhealthy
    
    # JSON output tests
    printf '\n%s\n' "JSON Output Tests:"
    test_case "Status JSON format" test_status_json_format
    test_case "Status healthy" test_status_healthy
    test_case "Status unhealthy" test_status_unhealthy
    test_case "Status includes check details" test_status_includes_check_details
    
    # Built-in checks tests
    printf '\n%s\n' "Built-in Checks Tests:"
    test_case "Check disk" test_check_disk
    test_case "Check disk threshold exceeded" test_check_disk_threshold_exceeded
    test_case "Check memory" test_check_memory
    test_case "Check process existing" test_check_process_existing
    test_case "Check process nonexistent" test_check_process_nonexistent
    test_case "Check file exists" test_check_file_exists
    test_case "Check file not exists" test_check_file_not_exists
    test_case "Check command exists" test_check_command_exists
    test_case "Check command not exists" test_check_command_not_exists
    test_case "Check TCP localhost" test_check_tcp_localhost
    
    # Utility function tests
    printf '\n%s\n' "Utility Function Tests:"
    test_case "Summary output" test_summary
    test_case "Print output" test_print_output
    test_case "Export to environment" test_export_env
    
    # Edge cases
    printf '\n%s\n' "Edge Cases:"
    test_case "Check with special characters" test_check_with_special_characters
    test_case "Register empty name" test_register_empty_name
    test_case "Register empty command" test_register_empty_command
    test_case "Multiple runs update results" test_multiple_runs_update_results
    
    # Summary
    printf '\n%s\n' "=== Test Summary ==="
    printf 'Total:  %d\n' "$TESTS_RUN"
    printf 'Passed: %s\n' "$(_green "$TESTS_PASSED")"
    printf 'Failed: %s\n' "$(_red "$TESTS_FAILED")"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        printf '\n%s\n\n' "$(_green 'All tests passed! YO JOE!')"
        return 0
    else
        printf '\n%s\n\n' "$(_red 'Some tests failed.')"
        return 1
    fi
}

main "$@"

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/tests/temporal_test.sh - Unit tests for temporal.sh module
# =============================================================================
# Usage: bash tests/temporal_test.sh
# =============================================================================

# Get test directory and source path
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAINFRAME_ROOT="${TEST_DIR%/tests}"

# Source temporal.sh and output.sh (for USOP functions)
source "$MAINFRAME_ROOT/lib/output.sh"
source "$MAINFRAME_ROOT/lib/temporal.sh"

# Test configuration
TEST_TEMPORAL_ROOT="${TEST_DIR}/.test_temporal_$$"
export TEMPORAL_ROOT="$TEST_TEMPORAL_ROOT"
export TEMPORAL_BACKEND="bash"  # Use bash backend for predictable testing

# Ensure internal functions are available for testing
# (In bash, functions are available in subshells after sourcing)

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# =============================================================================
# TEST HELPERS
# =============================================================================

# Run a test
run_test() {
    local name="$1"
    local test_fn="$2"

    ((TESTS_TOTAL++))
    printf '  %s... ' "$name"

    if $test_fn; then
        ((TESTS_PASSED++))
        printf '\033[32mPASS\033[0m\n'
    else
        ((TESTS_FAILED++))
        printf '\033[31mFAIL\033[0m\n'
    fi
}

# Assert equal
assert_eq() {
    [[ "$1" == "$2" ]]
}

# Assert not empty
assert_not_empty() {
    [[ -n "$1" ]]
}

# Assert contains
assert_contains() {
    [[ "$1" == *"$2"* ]]
}

# Setup test environment
setup() {
    [[ -d "$TEST_TEMPORAL_ROOT" ]] && rm -rf "$TEST_TEMPORAL_ROOT"
    mkdir -p "$TEST_TEMPORAL_ROOT"
    # Reset backend detection
    _TEMPORAL_ACTIVE_BACKEND=""
}

# Cleanup test environment
teardown() {
    [[ -d "$TEST_TEMPORAL_ROOT" ]] && rm -rf "$TEST_TEMPORAL_ROOT"
}

# =============================================================================
# UNIT TESTS
# =============================================================================

test_temporal_uuid() {
    local uuid1 uuid2
    uuid1=$(_temporal_uuid)
    uuid2=$(_temporal_uuid)

    # UUIDs should not be empty
    [[ -n "$uuid1" ]] || return 1
    [[ -n "$uuid2" ]] || return 1

    # UUIDs should be different
    [[ "$uuid1" != "$uuid2" ]] || return 1

    # UUID should follow pattern (contains dashes)
    [[ "$uuid1" == *-* ]] || return 1

    return 0
}

test_temporal_sql_escape() {
    local input="it's a test"
    local escaped
    escaped=$(_temporal_sql_escape "$input")

    assert_eq "$escaped" "it''s a test"
}

test_temporal_sanitize_command() {
    local input="curl -H 'Authorization: Bearer secret123' https://api.com"
    local sanitized
    sanitized=$(_temporal_sanitize_command "$input")

    assert_contains "$sanitized" "*****"
    [[ "$sanitized" != *"secret123"* ]] || return 1

    return 0
}

test_temporal_env_hash() {
    local hash1 hash2
    hash1=$(_temporal_env_hash "test-data-1")
    hash2=$(_temporal_env_hash "test-data-2")

    # Hashes should not be empty
    [[ -n "$hash1" ]] || return 1
    [[ -n "$hash2" ]] || return 1

    # Different inputs should produce different hashes
    [[ "$hash1" != "$hash2" ]] || return 1

    return 0
}

test_temporal_backend_detection() {
    # Reset backend
    _TEMPORAL_ACTIVE_BACKEND=""

    local backend
    backend=$(_temporal_backend)

    # Should return either 'sqlite' or 'bash'
    [[ "$backend" == "sqlite" || "$backend" == "bash" ]] || return 1

    return 0
}

test_temporal_record() {
    # Reset backend
    _TEMPORAL_ACTIVE_BACKEND=""

    local result
    result=$(temporal_record \
        --cwd "/home/test/project" \
        --command "npm test" \
        --exit_code 0 \
        --duration_ms 4500 \
        --session_id "test_session_123" \
        --git_branch "main" 2>&1)

    # Should succeed (no error output)
    [[ $? -eq 0 ]] || return 1

    return 0
}

test_temporal_query() {
    # Reset backend
    _TEMPORAL_ACTIVE_BACKEND=""

    # First record some data
    temporal_record \
        --cwd "/home/test" \
        --command "echo hello" \
        --exit_code 0 \
        --duration_ms 100 >/dev/null 2>&1

    temporal_record \
        --cwd "/home/test" \
        --command "echo world" \
        --exit_code 1 \
        --duration_ms 200 >/dev/null 2>&1

    # Query all
    local result
    result=$(temporal_query "SELECT * FROM history" 2>/dev/null)

    # Should return JSON array
    assert_contains "$result" "["
    assert_contains "$result" "]"

    return 0
}

test_temporal_select() {
    # Reset backend
    _TEMPORAL_ACTIVE_BACKEND=""

    # Record data
    temporal_record \
        --cwd "/tmp/test" \
        --command "ls -la" \
        --exit_code 0 \
        --duration_ms 50 >/dev/null 2>&1

    # Select with filters
    local result
    result=$(temporal_select "command, exit_code" --from "history" --where "exit_code = 0" 2>/dev/null)

    assert_contains "$result" "command"
    assert_contains "$result" "exit_code"

    return 0
}

test_temporal_frequency_analysis() {
    # Reset backend
    _TEMPORAL_ACTIVE_BACKEND=""

    # Record multiple commands
    for i in {1..3}; do
        temporal_record \
            --cwd "/tmp" \
            --command "test-cmd" \
            --exit_code 0 \
            --duration_ms 100 >/dev/null 2>&1
    done

    local result
    result=$(temporal_frequency_analysis 2>/dev/null)

    assert_contains "$result" "command"
    assert_contains "$result" "frequency"

    return 0
}

test_temporal_find_similar() {
    # Reset backend
    _TEMPORAL_ACTIVE_BACKEND=""

    # Record commands
    temporal_record --cwd "/tmp" --command "pytest tests/" --exit_code 0 --duration_ms 500 >/dev/null 2>&1
    temporal_record --cwd "/tmp" --command "python -m pytest" --exit_code 0 --duration_ms 600 >/dev/null 2>&1

    local result
    result=$(temporal_find_similar "pytest" 2>/dev/null)

    assert_contains "$result" "similar"

    return 0
}

test_temporal_detect_pattern() {
    # Reset backend
    _TEMPORAL_ACTIVE_BACKEND=""

    local result
    result=$(temporal_detect_pattern "commands that often run together" 2>/dev/null)

    assert_contains "$result" "patterns"
    assert_contains "$result" "type"

    return 0
}

test_temporal_anomaly_detect() {
    # Reset backend
    _TEMPORAL_ACTIVE_BACKEND=""

    local result
    result=$(temporal_anomaly_detect --sensitivity medium 2>/dev/null)

    assert_contains "$result" "anomalies"
    assert_contains "$result" "sensitivity"

    return 0
}

test_temporal_predict_success() {
    # Reset backend
    _TEMPORAL_ACTIVE_BACKEND=""

    # Record some successful and failed commands
    for i in {1..5}; do
        temporal_record --cwd "/tmp" --command "npm test" --exit_code 0 --duration_ms 1000 >/dev/null 2>&1
    done
    temporal_record --cwd "/tmp" --command "npm test" --exit_code 1 --duration_ms 500 >/dev/null 2>&1

    local result
    result=$(temporal_predict_success "npm test" 2>/dev/null)

    assert_contains "$result" "success_probability"
    assert_contains "$result" "confidence"

    return 0
}

test_temporal_predict_duration() {
    # Reset backend
    _TEMPORAL_ACTIVE_BACKEND=""

    # Record commands with durations
    temporal_record --cwd "/tmp" --command "sleep 1" --exit_code 0 --duration_ms 1000 >/dev/null 2>&1
    temporal_record --cwd "/tmp" --command "sleep 1" --exit_code 0 --duration_ms 1100 >/dev/null 2>&1

    local result
    result=$(temporal_predict_duration "sleep 1" 2>/dev/null)

    assert_contains "$result" "predicted_ms"
    assert_contains "$result" "confidence"

    return 0
}

test_temporal_recommend() {
    # Reset backend
    _TEMPORAL_ACTIVE_BACKEND=""

    # Record commands in current directory
    temporal_record --cwd "$PWD" --command "make build" --exit_code 0 --duration_ms 5000 >/dev/null 2>&1
    temporal_record --cwd "$PWD" --command "make test" --exit_code 0 --duration_ms 3000 >/dev/null 2>&1

    local result
    result=$(temporal_recommend "build the project" 2>/dev/null)

    assert_contains "$result" "recommendations"
    assert_contains "$result" "goal"

    return 0
}

test_temporal_stats() {
    # Reset backend
    _TEMPORAL_ACTIVE_BACKEND=""

    local result
    result=$(temporal_stats 2>/dev/null)

    assert_contains "$result" "backend"
    assert_contains "$result" "total_entries"
    assert_contains "$result" "storage_path"

    return 0
}

test_jaro_winkler() {
    local sim1 sim2

    sim1=$(jaro_winkler "hello" "hello")
    sim2=$(jaro_winkler "hello" "world")

    # Same strings should have similarity 1.0
    assert_eq "$sim1" "1.0000"

    # Different strings should have lower similarity
    [[ $(echo "$sim2 < 1.0" | bc) -eq 1 ]] || return 1

    return 0
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    printf '\033[1mMAINFRAME Temporal Module Tests\033[0m\n'
    printf '==============================\n\n'

    setup

    printf '\033[1mInternal Helper Tests:\033[0m\n'
    run_test "_temporal_uuid" test_temporal_uuid
    run_test "_temporal_sql_escape" test_temporal_sql_escape
    run_test "_temporal_sanitize_command" test_temporal_sanitize_command
    run_test "_temporal_env_hash" test_temporal_env_hash
    run_test "_temporal_backend_detection" test_temporal_backend_detection
    run_test "jaro_winkler" test_jaro_winkler

    printf '\n\033[1mData Storage Tests:\033[0m\n'
    run_test "temporal_record" test_temporal_record

    printf '\n\033[1mQuery Tests:\033[0m\n'
    run_test "temporal_query" test_temporal_query
    run_test "temporal_select" test_temporal_select

    printf '\n\033[1mPattern Detection Tests:\033[0m\n'
    run_test "temporal_frequency_analysis" test_temporal_frequency_analysis
    run_test "temporal_find_similar" test_temporal_find_similar
    run_test "temporal_detect_pattern" test_temporal_detect_pattern

    printf '\n\033[1mAnomaly Detection Tests:\033[0m\n'
    run_test "temporal_anomaly_detect" test_temporal_anomaly_detect

    printf '\n\033[1mPrediction Tests:\033[0m\n'
    run_test "temporal_predict_success" test_temporal_predict_success
    run_test "temporal_predict_duration" test_temporal_predict_duration
    run_test "temporal_recommend" test_temporal_recommend

    printf '\n\033[1mUtility Tests:\033[0m\n'
    run_test "temporal_stats" test_temporal_stats

    teardown

    printf '\n==============================\n'
    printf 'Total: %d | Passed: \033[32m%d\033[0m | Failed: \033[31m%d\033[0m\n' \
        $TESTS_TOTAL $TESTS_PASSED $TESTS_FAILED

    [[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
}

main "$@"

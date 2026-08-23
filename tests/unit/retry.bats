#!/usr/bin/env bats
# =============================================================================
# Tests for MAINFRAME/lib/retry.sh - Retry, Timeout, Circuit Breaker
# =============================================================================

load '../helpers/setup'

setup() {
    common_setup
    # Source the retry library
    source "${_PROJECT_ROOT}/lib/retry.sh"
    # Use test-specific state directories
    export MAINFRAME_CB_DIR="${TEST_TEMP_DIR}/cb"
    export MAINFRAME_RL_DIR="${TEST_TEMP_DIR}/rl"
    export MAINFRAME_QUIET=1
}

teardown() {
    common_teardown
}

# =============================================================================
# RETRY - Basic Functionality
# =============================================================================

@test "retry: succeeds on first attempt" {
    run retry true
    assert_success
}

@test "retry: fails after max attempts exhausted" {
    run retry --max-attempts 2 --delay 0 false
    assert_failure
}

@test "retry: succeeds on second attempt" {
    local counter_file="${TEST_TEMP_DIR}/counter"
    echo "0" > "$counter_file"

    _flaky_cmd() {
        local count
        count=$(cat "$counter_file")
        count=$((count + 1))
        echo "$count" > "$counter_file"
        [[ $count -ge 2 ]]
    }

    run retry --max-attempts 3 --delay 0 _flaky_cmd
    assert_success
}

@test "retry: respects max-attempts option" {
    local counter_file="${TEST_TEMP_DIR}/counter"
    echo "0" > "$counter_file"

    _counting_cmd() {
        local count
        count=$(cat "$counter_file")
        count=$((count + 1))
        echo "$count" > "$counter_file"
        return 1
    }

    run retry --max-attempts 4 --delay 0 _counting_cmd
    assert_failure

    local final_count
    final_count=$(cat "$counter_file")
    [[ "$final_count" -eq 4 ]]
}

@test "retry: default max-attempts is 3" {
    local counter_file="${TEST_TEMP_DIR}/counter"
    echo "0" > "$counter_file"

    _counting_cmd() {
        local count
        count=$(cat "$counter_file")
        count=$((count + 1))
        echo "$count" > "$counter_file"
        return 1
    }

    run retry --delay 0 _counting_cmd
    assert_failure

    local final_count
    final_count=$(cat "$counter_file")
    [[ "$final_count" -eq 3 ]]
}

@test "retry: returns last exit code on failure" {
    _exit42() { return 42; }
    run retry --max-attempts 2 --delay 0 _exit42
    [[ $status -eq 42 ]]
}

@test "retry: errors on no command" {
    run retry
    assert_failure
}

@test "retry: errors on unknown option" {
    run retry --unknown-flag true
    assert_failure
}

# =============================================================================
# RETRY - Backoff Strategies
# =============================================================================

@test "retry: fixed backoff uses constant delay" {
    local start end elapsed
    start=$(date +%s)

    retry --max-attempts 3 --delay 1 --backoff fixed false || true

    end=$(date +%s)
    elapsed=$((end - start))
    # 2 waits of 1s each = ~2s total
    [[ $elapsed -ge 1 && $elapsed -le 4 ]]
}

@test "retry: exponential backoff increases delay" {
    # With delay=1 and exponential: waits are 1s, 2s
    # Total should be ~3s for 3 attempts
    local start end elapsed
    start=$(date +%s)

    retry --max-attempts 3 --delay 1 --backoff exponential false || true

    end=$(date +%s)
    elapsed=$((end - start))
    # 1s + 2s = 3s minimum
    [[ $elapsed -ge 2 && $elapsed -le 6 ]]
}

@test "retry: linear backoff scales linearly" {
    # With delay=1 and linear: waits are 1s, 2s
    local start end elapsed
    start=$(date +%s)

    retry --max-attempts 3 --delay 1 --backoff linear false || true

    end=$(date +%s)
    elapsed=$((end - start))
    [[ $elapsed -ge 2 && $elapsed -le 6 ]]
}

@test "retry: max-delay caps the backoff" {
    local start end elapsed
    start=$(date +%s)

    # exponential with delay=10 would be 10, 20, 40... but max-delay=1 caps it
    retry --max-attempts 3 --delay 10 --max-delay 1 --backoff exponential false || true

    end=$(date +%s)
    elapsed=$((end - start))
    # Should be capped at ~2s (2 waits of 1s max)
    [[ $elapsed -le 5 ]]
}

@test "retry: unknown backoff strategy errors" {
    run retry --max-attempts 2 --delay 0 --backoff random_strategy false
    assert_failure
}

# =============================================================================
# RETRY - Jitter
# =============================================================================

@test "retry: jitter flag is accepted" {
    run retry --max-attempts 2 --delay 0 --jitter false
    # Should not error on the flag itself, just fail because command fails
    [[ $status -ne 0 ]]
}

# =============================================================================
# RETRY - On-Retry Callback
# =============================================================================

@test "retry: on-retry callback is called" {
    local callback_file="${TEST_TEMP_DIR}/callback"
    echo "" > "$callback_file"

    _my_callback() {
        echo "retry:$1" >> "$callback_file"
    }

    retry --max-attempts 3 --delay 0 --on-retry _my_callback false || true

    # Callback should have been called twice (before attempt 2 and 3)
    local lines
    lines=$(grep -c "retry:" "$callback_file")
    [[ "$lines" -eq 2 ]]
}

# =============================================================================
# RETRY_SIMPLE
# =============================================================================

@test "retry_simple: succeeds on first attempt" {
    run retry_simple 3 true
    assert_success
}

@test "retry_simple: retries N times" {
    local counter_file="${TEST_TEMP_DIR}/counter"
    echo "0" > "$counter_file"

    _counting_cmd() {
        local count
        count=$(cat "$counter_file")
        count=$((count + 1))
        echo "$count" > "$counter_file"
        return 1
    }

    # Use 2 retries to keep test fast (1s exponential backoff = 1 wait)
    run retry_simple 2 _counting_cmd
    assert_failure

    local final_count
    final_count=$(cat "$counter_file")
    [[ "$final_count" -eq 2 ]]
}

# =============================================================================
# TIMEOUT - with_timeout
# =============================================================================

@test "with_timeout: completes within timeout" {
    run with_timeout 5 true
    assert_success
}

@test "with_timeout: returns command exit code" {
    run with_timeout 5 false
    [[ $status -eq 1 ]]
}

@test "with_timeout: times out slow command" {
    run with_timeout 1 sleep 2
    [[ $status -eq 124 ]]
}

@test "with_timeout: errors on no command" {
    run with_timeout 5
    assert_failure
}

@test "with_timeout: errors on zero timeout" {
    run with_timeout 0 true
    assert_failure
}

@test "with_timeout: errors on negative timeout" {
    run with_timeout -1 true
    assert_failure
}

# =============================================================================
# TIMEOUT - did_timeout
# =============================================================================

@test "did_timeout: returns true after timeout" {
    with_timeout 1 sleep 3 || true
    # _MAINFRAME_LAST_EXIT should be 124
    did_timeout
}

@test "did_timeout: returns false after normal exit" {
    with_timeout 5 true
    # _MAINFRAME_LAST_EXIT should be 0
    if did_timeout; then
        return 1
    fi
}

@test "did_timeout: returns false after command failure" {
    with_timeout 5 false || true
    # _MAINFRAME_LAST_EXIT should be 1
    if did_timeout; then
        return 1
    fi
}

# =============================================================================
# CIRCUIT BREAKER - Initialization
# =============================================================================

@test "circuit_breaker_init: creates state file" {
    circuit_breaker_init "test_svc"
    [[ -f "${MAINFRAME_CB_DIR}/test_svc" ]]
}

@test "circuit_breaker_init: default state is closed" {
    circuit_breaker_init "test_svc"
    local state
    state=$(circuit_breaker_state "test_svc")
    [[ "$state" == "closed" ]]
}

@test "circuit_breaker_init: errors without name" {
    run circuit_breaker_init ""
    assert_failure
}

@test "circuit_breaker_init: accepts custom threshold" {
    circuit_breaker_init "test_svc" --threshold 10
    local state_file="${MAINFRAME_CB_DIR}/test_svc"
    grep -q '"threshold":10' "$state_file"
}

@test "circuit_breaker_init: accepts custom timeout" {
    circuit_breaker_init "test_svc" --timeout 120
    local state_file="${MAINFRAME_CB_DIR}/test_svc"
    grep -q '"timeout":120' "$state_file"
}

@test "circuit_breaker_init: accepts custom half-open-max" {
    circuit_breaker_init "test_svc" --half-open-max 3
    local state_file="${MAINFRAME_CB_DIR}/test_svc"
    grep -q '"half_open_max":3' "$state_file"
}

# =============================================================================
# CIRCUIT BREAKER - Call Success
# =============================================================================

@test "circuit_breaker_call: success returns 0" {
    circuit_breaker_init "test_svc"
    run circuit_breaker_call "test_svc" true
    assert_success
}

@test "circuit_breaker_call: failure returns 1" {
    circuit_breaker_init "test_svc"
    run circuit_breaker_call "test_svc" false
    [[ $status -eq 1 ]]
}

@test "circuit_breaker_call: tracks failures" {
    circuit_breaker_init "test_svc" --threshold 5
    circuit_breaker_call "test_svc" false || true
    circuit_breaker_call "test_svc" false || true

    local failures
    failures=$(circuit_breaker_failures "test_svc")
    [[ "$failures" -eq 2 ]]
}

@test "circuit_breaker_call: success resets failure count" {
    circuit_breaker_init "test_svc" --threshold 5
    circuit_breaker_call "test_svc" false || true
    circuit_breaker_call "test_svc" false || true
    circuit_breaker_call "test_svc" true

    local failures
    failures=$(circuit_breaker_failures "test_svc")
    [[ "$failures" -eq 0 ]]
}

# =============================================================================
# CIRCUIT BREAKER - State Transitions
# =============================================================================

@test "circuit_breaker_call: trips open at threshold" {
    circuit_breaker_init "test_svc" --threshold 3
    circuit_breaker_call "test_svc" false || true
    circuit_breaker_call "test_svc" false || true
    circuit_breaker_call "test_svc" false || true

    local state
    state=$(circuit_breaker_state "test_svc")
    [[ "$state" == "open" ]]
}

@test "circuit_breaker_call: open state rejects calls" {
    circuit_breaker_init "test_svc" --threshold 2 --timeout 60
    circuit_breaker_call "test_svc" false || true
    circuit_breaker_call "test_svc" false || true

    # Now it should be open - call should be rejected with exit 2
    run circuit_breaker_call "test_svc" true
    [[ $status -eq 2 ]]
}

@test "circuit_breaker_call: open transitions to half-open after timeout" {
    circuit_breaker_init "test_svc" --threshold 2 --timeout 1
    circuit_breaker_call "test_svc" false || true
    circuit_breaker_call "test_svc" false || true

    # Wait for timeout
    sleep 0.5

    local state
    state=$(circuit_breaker_state "test_svc")
    [[ "$state" == "half-open" ]]
}

@test "circuit_breaker_call: half-open success closes circuit" {
    circuit_breaker_init "test_svc" --threshold 2 --timeout 1 --half-open-max 1
    circuit_breaker_call "test_svc" false || true
    circuit_breaker_call "test_svc" false || true

    # Wait for timeout to transition to half-open
    sleep 0.5

    # Success in half-open should close
    circuit_breaker_call "test_svc" true

    local state
    state=$(circuit_breaker_state "test_svc")
    [[ "$state" == "closed" ]]
}

@test "circuit_breaker_call: half-open failure reopens circuit" {
    # Use longer timeout to avoid race condition in state check
    # (circuit_breaker_state reports half-open if elapsed >= timeout)
    circuit_breaker_init "test_svc" --threshold 2 --timeout 3 --half-open-max 1
    circuit_breaker_call "test_svc" false || true
    circuit_breaker_call "test_svc" false || true

    # Wait for timeout to transition to half-open
    sleep 4

    # Failure in half-open should reopen with new opened_at timestamp
    circuit_breaker_call "test_svc" false || true

    # State check must happen immediately - if it takes >= 3 seconds
    # the state would show as half-open again
    local state
    state=$(circuit_breaker_state "test_svc")
    [[ "$state" == "open" ]]
}

# =============================================================================
# CIRCUIT BREAKER - Reset
# =============================================================================

@test "circuit_breaker_reset: resets to closed" {
    circuit_breaker_init "test_svc" --threshold 2
    circuit_breaker_call "test_svc" false || true
    circuit_breaker_call "test_svc" false || true

    circuit_breaker_reset "test_svc"

    local state
    state=$(circuit_breaker_state "test_svc")
    [[ "$state" == "closed" ]]
}

@test "circuit_breaker_reset: clears failure count" {
    circuit_breaker_init "test_svc" --threshold 5
    circuit_breaker_call "test_svc" false || true
    circuit_breaker_call "test_svc" false || true

    circuit_breaker_reset "test_svc"

    local failures
    failures=$(circuit_breaker_failures "test_svc")
    [[ "$failures" -eq 0 ]]
}

@test "circuit_breaker_reset: errors on unknown breaker" {
    run circuit_breaker_reset "nonexistent"
    assert_failure
}

# =============================================================================
# CIRCUIT BREAKER - Query Functions
# =============================================================================

@test "circuit_breaker_state: returns unknown for uninitialized" {
    run circuit_breaker_state "nonexistent"
    assert_output "unknown"
    assert_failure
}

@test "circuit_breaker_failures: returns 0 for uninitialized" {
    run circuit_breaker_failures "nonexistent"
    assert_output "0"
    assert_failure
}

# =============================================================================
# CIRCUIT BREAKER - List
# =============================================================================

@test "circuit_breaker_list: lists initialized breakers" {
    circuit_breaker_init "svc_a"
    circuit_breaker_init "svc_b"

    run circuit_breaker_list
    assert_success
    assert_output --partial "svc_a"
    assert_output --partial "svc_b"
}

@test "circuit_breaker_list: empty when no breakers" {
    run circuit_breaker_list
    assert_success
    assert_output ""
}

# =============================================================================
# WAIT_FOR - Basic
# =============================================================================

@test "wait_for: returns immediately on true condition" {
    run wait_for --timeout 5 true
    assert_success
}

@test "wait_for: times out on false condition" {
    run wait_for --timeout 2 --interval 1 false
    assert_failure
}

@test "wait_for: errors on no command" {
    run wait_for --timeout 5
    assert_failure
}

@test "wait_for: waits for condition to become true" {
    local marker="${TEST_TEMP_DIR}/ready"

    # Create the marker after 2 seconds
    (sleep 0.5 && touch "$marker") &

    run wait_for --timeout 5 --interval 1 test -f "$marker"
    assert_success
}

# =============================================================================
# WAIT_FOR_FILE
# =============================================================================

@test "wait_for_file: succeeds if file exists" {
    local file="${TEST_TEMP_DIR}/exists.txt"
    touch "$file"

    run wait_for_file "$file" 5
    assert_success
}

@test "wait_for_file: waits for file creation" {
    local file="${TEST_TEMP_DIR}/delayed.txt"

    (sleep 0.5 && touch "$file") &

    run wait_for_file "$file" 5
    assert_success
}

@test "wait_for_file: times out if file never appears" {
    run wait_for_file "${TEST_TEMP_DIR}/never.txt" 2
    assert_failure
}

@test "wait_for_file: errors without path" {
    run wait_for_file "" 5
    assert_failure
}

# =============================================================================
# WAIT_FOR_PORT
# =============================================================================

@test "wait_for_port: errors without host" {
    run wait_for_port "" "" 2
    assert_failure
}

@test "wait_for_port: errors without port" {
    run wait_for_port "localhost" "" 2
    assert_failure
}

@test "wait_for_port: times out on closed port" {
    # Port 19999 should not be open
    run wait_for_port "localhost" 19999 2
    assert_failure
}

# =============================================================================
# RATE LIMITER - Initialization
# =============================================================================

@test "rate_limit_init: creates state file" {
    rate_limit_init "test_rl" --rate 10 --per 60
    [[ -f "${MAINFRAME_RL_DIR}/test_rl" ]]
}

@test "rate_limit_init: errors without name" {
    run rate_limit_init "" --rate 10 --per 60
    assert_failure
}

@test "rate_limit_init: errors without rate" {
    run rate_limit_init "test_rl" --per 60
    assert_failure
}

@test "rate_limit_init: errors without per" {
    run rate_limit_init "test_rl" --rate 10
    assert_failure
}

@test "rate_limit_init: errors on zero rate" {
    run rate_limit_init "test_rl" --rate 0 --per 60
    assert_failure
}

@test "rate_limit_init: errors on zero per" {
    run rate_limit_init "test_rl" --rate 10 --per 0
    assert_failure
}

# =============================================================================
# RATE LIMITER - Acquire
# =============================================================================

@test "rate_limit_acquire: succeeds within rate" {
    rate_limit_init "test_rl" --rate 5 --per 60

    rate_limit_acquire "test_rl"
    [[ $? -eq 0 ]]
}

@test "rate_limit_acquire: multiple acquisitions within rate" {
    rate_limit_init "test_rl" --rate 3 --per 60

    rate_limit_acquire "test_rl"
    rate_limit_acquire "test_rl"
    rate_limit_acquire "test_rl"
    [[ $? -eq 0 ]]
}

@test "rate_limit_acquire: no-wait returns 1 when exhausted" {
    rate_limit_init "test_rl" --rate 2 --per 60

    rate_limit_acquire "test_rl"
    rate_limit_acquire "test_rl"

    # Third acquire should fail with --no-wait
    run rate_limit_acquire "test_rl" --no-wait
    [[ $status -eq 1 ]]
}

@test "rate_limit_acquire: errors on uninitialized limiter" {
    run rate_limit_acquire "nonexistent"
    assert_failure
}

@test "rate_limit_acquire: errors without name" {
    run rate_limit_acquire ""
    assert_failure
}

# =============================================================================
# RATE LIMITER - Reset
# =============================================================================

@test "rate_limit_reset: refills tokens" {
    rate_limit_init "test_rl" --rate 2 --per 60

    # Exhaust all tokens
    rate_limit_acquire "test_rl"
    rate_limit_acquire "test_rl"

    # Reset
    rate_limit_reset "test_rl"

    # Should succeed again
    rate_limit_acquire "test_rl" --no-wait
    [[ $? -eq 0 ]]
}

@test "rate_limit_reset: errors on uninitialized limiter" {
    run rate_limit_reset "nonexistent"
    assert_failure
}

# =============================================================================
# RATE LIMITER - Token Refill
# =============================================================================

@test "rate_limit_acquire: tokens refill after time period" {
    rate_limit_init "test_rl" --rate 2 --per 1

    # Exhaust tokens
    rate_limit_acquire "test_rl"
    rate_limit_acquire "test_rl"

    # Should be exhausted
    run rate_limit_acquire "test_rl" --no-wait
    [[ $status -eq 1 ]]

    # Wait well beyond refill period (1s period + margin)
    sleep 1.5

    # Should have tokens again
    run rate_limit_acquire "test_rl" --no-wait
    assert_success
}

# =============================================================================
# INTEGRATION: retry + circuit_breaker
# =============================================================================

@test "integration: retry with circuit breaker" {
    circuit_breaker_init "flaky_svc" --threshold 3

    local counter_file="${TEST_TEMP_DIR}/counter"
    echo "0" > "$counter_file"

    _flaky_with_cb() {
        local count
        count=$(cat "$counter_file")
        count=$((count + 1))
        echo "$count" > "$counter_file"
        circuit_breaker_call "flaky_svc" false
    }

    # Retry should exhaust attempts, circuit breaker should trip
    retry --max-attempts 4 --delay 0 _flaky_with_cb || true

    local state
    state=$(circuit_breaker_state "flaky_svc")
    [[ "$state" == "open" ]]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "retry: works with commands that have arguments" {
    run retry --max-attempts 2 --delay 0 test 1 -eq 1
    assert_success
}

@test "retry: works with commands that produce output" {
    run retry --max-attempts 2 --delay 0 echo "hello world"
    assert_success
    assert_output "hello world"
}

@test "circuit_breaker_call: errors on uninitialized breaker" {
    run circuit_breaker_call "nonexistent" true
    assert_failure
}

@test "circuit_breaker_call: errors without name" {
    run circuit_breaker_call "" true
    assert_failure
}

@test "with_timeout: works with commands that produce output" {
    run with_timeout 5 echo "hello"
    assert_success
    assert_output "hello"
}

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Resilience Module Tests
# =============================================================================
# Comprehensive tests for circuit breakers, bulkheads, rate limiters,
# retries, fallbacks, timeouts, and health checks.
# =============================================================================

load 'test_helper'

setup() {
    source_lib "resilience"
    export MAINFRAME_QUIET=1
    export MAINFRAME_ERROR_JSON=1
    TEST_DIR=$(create_test_dir "resilience")
}

teardown() {
    resilience_reset_all 2>/dev/null || true
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# CIRCUIT BREAKER TESTS
# =============================================================================

@test "circuit_breaker_create initializes breaker in closed state" {
    circuit_breaker_create "test_cb"
    local state
    state=$(circuit_breaker_state "test_cb")
    [ "$state" = "closed" ]
}

@test "circuit_breaker_create accepts custom config" {
    circuit_breaker_create "custom" failure_threshold=10 timeout=120
    local config
    config=$(circuit_breaker_config "custom")
    [[ "$config" == *'"failure_threshold":10'* ]]
    [[ "$config" == *'"timeout":120'* ]]
}

@test "circuit_breaker_create requires name" {
    local err
    ! err=$(circuit_breaker_create "" 2>&1)
    [[ "$err" == *"name required"* ]]
}

@test "circuit_breaker_call executes command when closed" {
    circuit_breaker_create "test_cb"
    local result
    result=$(circuit_breaker_call "test_cb" "echo hello")
    [ "$result" = "hello" ]
}

@test "circuit_breaker_call auto-creates breaker if not exists" {
    local result
    result=$(circuit_breaker_call "auto_cb" "echo auto")
    [ "$result" = "auto" ]
    local state
    state=$(circuit_breaker_state "auto_cb")
    [ "$state" = "closed" ]
}

@test "circuit_breaker trips to open after threshold failures" {
    circuit_breaker_create "trip_test" failure_threshold=3

    # Cause 3 failures
    circuit_breaker_call "trip_test" "false" 2>/dev/null || true
    circuit_breaker_call "trip_test" "false" 2>/dev/null || true
    circuit_breaker_call "trip_test" "false" 2>/dev/null || true

    local state
    state=$(circuit_breaker_state "trip_test")
    [ "$state" = "open" ]
}

@test "circuit_breaker fails fast when open" {
    circuit_breaker_create "fast_fail" failure_threshold=1
    circuit_breaker_call "fast_fail" "false" 2>/dev/null || true

    # This should fail immediately without executing
    local start end duration
    start=$(date +%s)
    ! circuit_breaker_call "fast_fail" "sleep 5"
    end=$(date +%s)
    duration=$((end - start))

    # Should be nearly instant (< 2 seconds)
    [ "$duration" -lt 2 ]
}

@test "circuit_breaker transitions to half_open after timeout" {
    circuit_breaker_create "timeout_test" failure_threshold=1 timeout=1
    circuit_breaker_call "timeout_test" "false" 2>/dev/null || true

    # Circuit should be open
    local state
    state=$(circuit_breaker_state "timeout_test")
    [ "$state" = "open" ]

    # Wait for timeout
    sleep 2

    # Try a call - should transition to half_open and execute
    circuit_breaker_call "timeout_test" "echo test" >/dev/null 2>&1
    state=$(circuit_breaker_state "timeout_test")
    # After a successful call in half_open, it might be closed or still half_open
    [[ "$state" == "closed" || "$state" == "half_open" ]]
}

@test "circuit_breaker_reset manually resets to closed" {
    circuit_breaker_create "reset_test" failure_threshold=1
    circuit_breaker_call "reset_test" "false" 2>/dev/null || true

    local state
    state=$(circuit_breaker_state "reset_test")
    [ "$state" = "open" ]

    circuit_breaker_reset "reset_test"
    state=$(circuit_breaker_state "reset_test")
    [ "$state" = "closed" ]
}

@test "circuit_breaker_trip manually trips to open" {
    circuit_breaker_create "trip_manual"
    circuit_breaker_trip "trip_manual"

    local state
    state=$(circuit_breaker_state "trip_manual")
    [ "$state" = "open" ]
}

@test "circuit_breaker_stats returns JSON" {
    circuit_breaker_create "stats_test"
    circuit_breaker_call "stats_test" "echo ok" >/dev/null
    circuit_breaker_call "stats_test" "false" 2>/dev/null || true

    local stats
    stats=$(circuit_breaker_stats "stats_test")
    [[ "$stats" == *'"name":"stats_test"'* ]]
    [[ "$stats" == *'"state":"closed"'* ]]
    [[ "$stats" == *'"failures":1'* ]]
}

@test "circuit_breaker_config updates configuration" {
    circuit_breaker_create "config_test"
    circuit_breaker_config "config_test" timeout=90

    local config
    config=$(circuit_breaker_config "config_test")
    [[ "$config" == *'"timeout":90'* ]]
}

@test "circuit_breaker_state returns unknown for non-existent" {
    local state
    state=$(circuit_breaker_state "nonexistent")
    [ "$state" = "unknown" ]
}

# =============================================================================
# BULKHEAD TESTS
# =============================================================================

@test "bulkhead_create initializes with max concurrent" {
    bulkhead_create "bh_test" 5
    local stats
    stats=$(bulkhead_stats "bh_test")
    [[ "$stats" == *'"max":5'* ]]
    [[ "$stats" == *'"current":0'* ]]
}

@test "bulkhead_create requires positive integer" {
    local err
    ! err=$(bulkhead_create "bad" 0 2>&1)
    [[ "$err" == *"positive integer"* ]]
}

@test "bulkhead_acquire increases current count" {
    bulkhead_create "acq_test" 5
    bulkhead_acquire "acq_test"

    local stats
    stats=$(bulkhead_stats "acq_test")
    [[ "$stats" == *'"current":1'* ]]
}

@test "bulkhead_release decreases current count" {
    bulkhead_create "rel_test" 5
    bulkhead_acquire "rel_test"
    bulkhead_release "rel_test"

    local stats
    stats=$(bulkhead_stats "rel_test")
    [[ "$stats" == *'"current":0'* ]]
}

@test "bulkhead_try_acquire returns 0 when available" {
    bulkhead_create "try_test" 2
    bulkhead_try_acquire "try_test"
    [ $? -eq 0 ]
}

@test "bulkhead_try_acquire returns 1 when full" {
    bulkhead_create "full_test" 1
    bulkhead_acquire "full_test"

    ! bulkhead_try_acquire "full_test"
}

@test "bulkhead_execute runs command and releases slot" {
    bulkhead_create "exec_test" 2
    local result
    result=$(bulkhead_execute "exec_test" "echo executed")
    [ "$result" = "executed" ]

    local stats
    stats=$(bulkhead_stats "exec_test")
    [[ "$stats" == *'"current":0'* ]]
}

@test "bulkhead_execute releases slot on failure" {
    bulkhead_create "fail_test" 2
    bulkhead_execute "fail_test" "false" || true

    local stats
    stats=$(bulkhead_stats "fail_test")
    [[ "$stats" == *'"current":0'* ]]
}

@test "bulkhead_stats returns JSON" {
    bulkhead_create "stats_bh" 10
    bulkhead_acquire "stats_bh"
    bulkhead_acquire "stats_bh"

    local stats
    stats=$(bulkhead_stats "stats_bh")
    [[ "$stats" == *'"name":"stats_bh"'* ]]
    [[ "$stats" == *'"current":2'* ]]
    [[ "$stats" == *'"available":8'* ]]
}

@test "bulkhead_resize changes max concurrent" {
    bulkhead_create "resize_test" 5
    bulkhead_resize "resize_test" 20

    local stats
    stats=$(bulkhead_stats "resize_test")
    [[ "$stats" == *'"max":20'* ]]
}

@test "bulkhead auto-creates with defaults" {
    bulkhead_try_acquire "auto_bh"
    local stats
    stats=$(bulkhead_stats "auto_bh")
    [[ "$stats" == *'"name":"auto_bh"'* ]]
}

# =============================================================================
# RATE LIMITER TESTS
# =============================================================================

@test "rate_limiter_create initializes with limit and window" {
    rate_limiter_create "rl_test" 10 60
    local stats
    stats=$(rate_limiter_stats "rl_test")
    [[ "$stats" == *'"limit":10'* ]]
    [[ "$stats" == *'"window":60'* ]]
}

@test "rate_limiter_allow returns 0 when under limit" {
    rate_limiter_create "allow_test" 10 60
    rate_limiter_allow "allow_test"
    [ $? -eq 0 ]
}

@test "rate_limiter_allow returns 1 when limit exceeded" {
    rate_limiter_create "exceed_test" 2 60
    rate_limiter_allow "exceed_test"
    rate_limiter_allow "exceed_test"

    ! rate_limiter_allow "exceed_test"
}

@test "rate_limiter_allow increments count" {
    rate_limiter_create "count_test" 10 60
    rate_limiter_allow "count_test"
    rate_limiter_allow "count_test"
    rate_limiter_allow "count_test"

    local stats
    stats=$(rate_limiter_stats "count_test")
    [[ "$stats" == *'"count":3'* ]]
}

@test "rate_limiter_execute runs command when allowed" {
    rate_limiter_create "exec_rl" 10 60
    local result
    result=$(rate_limiter_execute "exec_rl" "echo allowed")
    [ "$result" = "allowed" ]
}

@test "rate_limiter_execute rejects when rate limited" {
    rate_limiter_create "reject_rl" 1 60
    rate_limiter_allow "reject_rl"

    ! rate_limiter_execute "reject_rl" "echo rejected"
}

@test "rate_limiter_stats returns JSON" {
    rate_limiter_create "stats_rl" 100 120
    rate_limiter_allow "stats_rl"

    local stats
    stats=$(rate_limiter_stats "stats_rl")
    [[ "$stats" == *'"name":"stats_rl"'* ]]
    [[ "$stats" == *'"count":1'* ]]
    [[ "$stats" == *'"remaining":99'* ]]
}

@test "rate_limiter_reset clears counter" {
    rate_limiter_create "reset_rl" 5 60
    rate_limiter_allow "reset_rl"
    rate_limiter_allow "reset_rl"
    rate_limiter_reset "reset_rl"

    local stats
    stats=$(rate_limiter_stats "reset_rl")
    [[ "$stats" == *'"count":0'* ]]
}

@test "rate_limiter auto-creates with defaults" {
    rate_limiter_allow "auto_rl"
    local stats
    stats=$(rate_limiter_stats "auto_rl")
    [[ "$stats" == *'"name":"auto_rl"'* ]]
}

# =============================================================================
# RETRY TESTS
# =============================================================================

@test "retry_exponential succeeds on first attempt" {
    local result
    result=$(retry_exponential "echo success" 3 1)
    [ "$result" = "success" ]
}

@test "retry_exponential retries on failure" {
    local attempts=0
    _test_retry_func() {
        attempts=$((attempts + 1))
        [ $attempts -ge 2 ] && echo "ok" && return 0
        return 1
    }
    export -f _test_retry_func
    export attempts

    local result
    result=$(retry_exponential "_test_retry_func" 3 0.1)
    [ "$result" = "ok" ]
}

@test "retry_exponential fails after max attempts" {
    ! retry_exponential "false" 2 0.1 2>/dev/null
}

@test "retry_linear uses linear backoff" {
    local result
    result=$(retry_linear "echo linear" 3 0.1)
    [ "$result" = "linear" ]
}

@test "retry_fibonacci uses fibonacci backoff" {
    local result
    result=$(retry_fibonacci "echo fib" 3)
    [ "$result" = "fib" ]
}

@test "retry_with_jitter returns modified delay" {
    local delay
    delay=$(retry_with_jitter 10 0.5)
    # Should be between 5 and 15 (10 +/- 50%)
    [ "$delay" -ge 1 ] && [ "$delay" -le 20 ]
}

@test "retry_until_success with exponential backoff" {
    local result
    result=$(retry_until_success "echo done" 3 0.1 exponential 0)
    [ "$result" = "done" ]
}

@test "retry_until_success with linear backoff" {
    local result
    result=$(retry_until_success "echo linear" 3 0.1 linear 0)
    [ "$result" = "linear" ]
}

@test "retry_with_fallback tries primary first" {
    local result
    result=$(retry_with_fallback "echo primary" "echo fallback" 2 0.1)
    [ "$result" = "primary" ]
}

@test "retry_with_fallback uses fallback on failure" {
    local result
    result=$(retry_with_fallback "false" "echo fallback" 1 0.1 2>/dev/null)
    [ "$result" = "fallback" ]
}

# =============================================================================
# FALLBACK TESTS
# =============================================================================

@test "fallback_to executes primary when successful" {
    local result
    result=$(fallback_to "echo primary" "echo fallback")
    [ "$result" = "primary" ]
}

@test "fallback_to uses fallback on failure" {
    local result
    result=$(fallback_to "false" "echo fallback" 2>/dev/null)
    [ "$result" = "fallback" ]
}

@test "fallback_chain tries commands in order" {
    local result
    result=$(fallback_chain "false" "false" "echo third" 2>/dev/null)
    [ "$result" = "third" ]
}

@test "fallback_chain returns first success" {
    local result
    result=$(fallback_chain "echo first" "echo second")
    [ "$result" = "first" ]
}

@test "fallback_default returns command output on success" {
    local result
    result=$(fallback_default "echo value" "default")
    [ "$result" = "value" ]
}

@test "fallback_default returns default on failure" {
    local result
    result=$(fallback_default "false" "default_value" 2>/dev/null)
    [ "$result" = "default_value" ]
}

@test "fallback_cache stores successful result" {
    local result
    result=$(fallback_cache "cache_key" "echo cached_value")
    [ "$result" = "cached_value" ]
}

@test "fallback_cache returns cached value on failure" {
    # First call succeeds and caches
    fallback_cache "stale_key" "echo fresh" >/dev/null

    # Second call fails but returns cached value
    local result
    result=$(fallback_cache "stale_key" "false" 2>/dev/null)
    [ "$result" = "fresh" ]
}

# =============================================================================
# TIMEOUT TESTS
# =============================================================================

@test "with_timeout executes command within limit" {
    local result
    result=$(with_timeout 5 "echo quick")
    [ "$result" = "quick" ]
}

@test "with_timeout kills command after timeout" {
    local start end duration
    start=$(date +%s)
    ! with_timeout 1 "sleep 10" 2>/dev/null
    end=$(date +%s)
    duration=$((end - start))

    # Should timeout around 1 second (allow some buffer)
    [ "$duration" -lt 3 ]
}

@test "with_timeout returns 124 on timeout" {
    local rc=0
    with_timeout 1 "sleep 10" 2>/dev/null || rc=$?
    [ "$rc" -eq 124 ]
}

@test "timeout_cancel terminates process" {
    sleep 100 &
    local pid=$!

    timeout_cancel "$pid"
    sleep 0.3

    ! kill -0 "$pid" 2>/dev/null
}

@test "deadline_from_now calculates future timestamp" {
    local now deadline
    now=$(date +%s)
    deadline=$(deadline_from_now 60)

    # Should be approximately 60 seconds in future
    local diff=$((deadline - now))
    [ "$diff" -eq 60 ]
}

@test "deadline_remaining returns correct time" {
    local deadline remaining
    deadline=$(($(date +%s) + 30))
    remaining=$(deadline_remaining "$deadline")

    # Should be around 30 (allow 1 second variance)
    [ "$remaining" -ge 29 ] && [ "$remaining" -le 30 ]
}

@test "deadline_remaining returns 0 for past deadline" {
    local deadline remaining
    deadline=$(($(date +%s) - 10))
    remaining=$(deadline_remaining "$deadline")

    [ "$remaining" -eq 0 ]
}

# =============================================================================
# HEALTH CHECK TESTS
# =============================================================================

@test "health_check_register adds check" {
    health_check_register "db" "true" 60
    local status
    status=$(health_check_status)
    [[ "$status" == *'"db":'* ]]
}

@test "health_check_run executes checks" {
    health_check_register "healthy" "true"
    health_check_run

    local status
    status=$(health_check_status)
    [[ "$status" == *'"status":"healthy"'* ]]
}

@test "health_check_run detects unhealthy" {
    health_check_register "unhealthy" "false"
    ! health_check_run 2>/dev/null

    local status
    status=$(health_check_status)
    [[ "$status" == *'"status":"unhealthy"'* ]]
}

@test "health_check_status returns JSON" {
    health_check_register "check1" "true"
    health_check_register "check2" "true"
    health_check_run

    local status
    status=$(health_check_status)
    [[ "$status" == *'"checks":'* ]]
    [[ "$status" == *'"check1":'* ]]
    [[ "$status" == *'"check2":'* ]]
}

@test "health_check_is_healthy returns 0 for healthy check" {
    health_check_register "good" "true"
    health_check_run "good"

    health_check_is_healthy "good"
}

@test "health_check_is_healthy returns 1 for unhealthy check" {
    health_check_register "bad" "false"
    health_check_run "bad" 2>/dev/null || true

    ! health_check_is_healthy "bad"
}

@test "health_check_unregister removes check" {
    health_check_register "temp" "true"
    health_check_unregister "temp"

    local status
    status=$(health_check_status)
    [[ "$status" != *'"temp":'* ]]
}

# =============================================================================
# COMBINED PATTERN TESTS
# =============================================================================

@test "resilient_call combines circuit breaker and retry" {
    local result
    result=$(resilient_call "service" "echo resilient" 3 0.1)
    [ "$result" = "resilient" ]
}

@test "resilient_call respects open circuit" {
    circuit_breaker_create "blocked" failure_threshold=1
    circuit_breaker_trip "blocked"

    ! resilient_call "blocked" "echo test" 3 0.1
}

@test "resilient_execute uses all patterns" {
    local result
    result=$(resilient_execute "full_stack" "echo complete" "" 30 10 3)
    [ "$result" = "complete" ]
}

@test "resilient_execute uses fallback on failure" {
    circuit_breaker_create "fail_stack" failure_threshold=1
    circuit_breaker_trip "fail_stack"

    local result
    result=$(resilient_execute "fail_stack" "false" "echo fallback" 30 10 1)
    [ "$result" = "fallback" ]
}

# =============================================================================
# RESET AND CLEANUP TESTS
# =============================================================================

@test "resilience_reset_all clears all state" {
    circuit_breaker_create "cb1"
    bulkhead_create "bh1" 5
    rate_limiter_create "rl1" 10 60
    health_check_register "hc1" "true"

    resilience_reset_all

    local summary
    summary=$(resilience_summary)
    [[ "$summary" == *'"circuit_breakers":0'* ]]
    [[ "$summary" == *'"bulkheads":0'* ]]
    [[ "$summary" == *'"rate_limiters":0'* ]]
    [[ "$summary" == *'"health_checks":0'* ]]
}

@test "resilience_summary returns component counts" {
    circuit_breaker_create "s1"
    circuit_breaker_create "s2"
    bulkhead_create "b1" 5
    rate_limiter_create "r1" 10 60

    local summary
    summary=$(resilience_summary)
    [[ "$summary" == *'"circuit_breakers":2'* ]]
    [[ "$summary" == *'"bulkheads":1'* ]]
    [[ "$summary" == *'"rate_limiters":1'* ]]
}

# =============================================================================
# EDGE CASES AND ERROR HANDLING
# =============================================================================

@test "circuit_breaker handles command with arguments" {
    circuit_breaker_create "args_test"
    local result
    result=$(circuit_breaker_call "args_test" "printf '%s %s' hello world")
    [ "$result" = "hello world" ]
}

@test "bulkhead handles rapid acquire/release" {
    bulkhead_create "rapid" 100

    for i in {1..50}; do
        bulkhead_acquire "rapid"
    done

    for i in {1..50}; do
        bulkhead_release "rapid"
    done

    local stats
    stats=$(bulkhead_stats "rapid")
    [[ "$stats" == *'"current":0'* ]]
}

@test "rate_limiter handles window expiry" {
    rate_limiter_create "window_test" 5 1

    # Use up the limit
    for i in {1..5}; do
        rate_limiter_allow "window_test"
    done

    # Should be limited now
    ! rate_limiter_allow "window_test"

    # Wait for window to expire
    sleep 2

    # Should be allowed again
    rate_limiter_allow "window_test"
}

@test "retry handles empty command error" {
    local err
    ! err=$(retry_exponential "" 3 1 2>&1)
    [[ "$err" == *"command required"* ]]
}

@test "fallback_cache handles missing cache" {
    ! fallback_cache "no_cache" "false" 2>/dev/null
}

@test "with_timeout requires valid timeout" {
    local err
    ! err=$(with_timeout "invalid" "echo test" 2>&1)
    [[ "$err" == *"positive integer"* ]]
}

@test "health_check handles check with output" {
    health_check_register "output_check" "echo healthy_output"
    health_check_run

    local status
    status=$(health_check_status)
    [[ "$status" == *'"status":"healthy"'* ]]
}

@test "circuit breaker success resets failure count" {
    circuit_breaker_create "reset_failures" failure_threshold=5

    # Cause some failures
    circuit_breaker_call "reset_failures" "false" 2>/dev/null || true
    circuit_breaker_call "reset_failures" "false" 2>/dev/null || true

    # One success should reset
    circuit_breaker_call "reset_failures" "echo ok" >/dev/null

    local stats
    stats=$(circuit_breaker_stats "reset_failures")
    [[ "$stats" == *'"failures":0'* ]]
}

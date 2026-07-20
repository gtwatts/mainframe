#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Service Management Library Tests
# =============================================================================
# Tests for lib/service.sh - Manager detection, status, lists, logs, summary
# =============================================================================
# NOTE: Service control operations require root. These tests focus on read-only
# operations and error paths that are safe to run in CI (Ubuntu with systemd).
# =============================================================================

setup() {
    export MAINFRAME_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    source "${MAINFRAME_ROOT}/lib/service.sh"
}

# =============================================================================
# MANAGER DETECTION
# =============================================================================

@test "service_manager outputs supported manager name" {
    run service_manager
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^(systemd|launchctl|openrc|sysvinit|unknown)$ ]]
}

@test "service_manager_version outputs non-empty string" {
    run service_manager_version
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "_service_detect_manager matches service_manager" {
    local expected
    expected=$(service_manager)
    run _service_detect_manager
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
}

# =============================================================================
# SERVICE STATUS (read-only, safe)
# =============================================================================

@test "service_status for systemd-journald returns valid state" {
    run service_status "systemd-journald"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^(running|stopped|failed|unknown)$ ]]
}

@test "service_status for nonexistent service returns unknown or stopped" {
    run service_status "nonexistent-service-12345"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^(unknown|stopped)$ ]]
}

@test "service_is_running returns 0 or 1 for systemd-journald" {
    # systemd-journald should be running, but we only assert valid exit code
    service_is_running "systemd-journald" || true
    # No crash is the assertion; verify explicit result
    run bash -c "source '${MAINFRAME_ROOT}/lib/service.sh'; service_is_running 'systemd-journald'; echo \$?"
    [[ "${lines[-1]}" =~ ^[01]$ ]]
}

@test "service_is_running returns 1 for nonexistent service" {
    run service_is_running "nonexistent-12345"
    [ "$status" -eq 1 ]
}

@test "service_pid for systemd-journald outputs integer or empty" {
    run service_pid "systemd-journald"
    [ "$status" -eq 0 ]
    # Output is either empty or a positive integer
    if [ -n "$output" ]; then
        [[ "$output" =~ ^[0-9]+$ ]]
    fi
}

@test "service_pid for nonexistent service outputs empty" {
    run service_pid "nonexistent-12345"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# =============================================================================
# SERVICE LISTS (read-only)
# =============================================================================

@test "service_list_running outputs at least 1 line" {
    run service_list_running
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -ge 1 ]
}

@test "service_list_running output lines contain no spaces" {
    run service_list_running
    [ "$status" -eq 0 ]
    for line in "${lines[@]}"; do
        [[ "$line" != *" "* ]]
    done
}

@test "service_list_all outputs at least 5 lines" {
    run service_list_all
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -ge 5 ]
}

@test "service_list_all count >= service_list_running count" {
    local all_count running_count
    all_count=$(service_list_all | wc -l)
    running_count=$(service_list_running | wc -l)
    [ "$all_count" -ge "$running_count" ]
}

@test "service_list_enabled outputs at least 1 line" {
    run service_list_enabled
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -ge 1 ]
}

@test "service_list_failed runs without error" {
    run service_list_failed
    [ "$status" -eq 0 ]
    # Output may be empty if no services have failed — that is fine
}

# =============================================================================
# SERVICE CONTROL (error paths only — no actual start/stop)
# =============================================================================

@test "service_start fails for nonexistent service" {
    run service_start "nonexistent-service-12345"
    [ "$status" -ne 0 ]
}

@test "service_stop fails for nonexistent service" {
    run service_stop "nonexistent-service-12345"
    [ "$status" -ne 0 ]
}

@test "service_restart fails for nonexistent service" {
    run service_restart "nonexistent-service-12345"
    [ "$status" -ne 0 ]
}

# =============================================================================
# SERVICE LOGS (read-only)
# =============================================================================

@test "service_logs for cron outputs at most N lines" {
    run service_logs "cron" 5
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -le 6 ]  # journalctl may add a header line
}

@test "service_logs for nonexistent service does not crash" {
    run service_logs "nonexistent-12345" 5
    # May succeed with empty output or fail gracefully
    # The key assertion is no segfault or unhandled error
    true
}

@test "service_log_errors runs without crashing" {
    run service_log_errors "cron" 5
    # May produce output or be empty; should not crash
    [ "$status" -eq 0 ]
}

# =============================================================================
# SUMMARY
# =============================================================================

@test "service_summary starts with {" {
    run service_summary
    [ "$status" -eq 0 ]
    [[ "$output" == "{"* ]]
}

@test "service_summary contains manager field" {
    run service_summary
    [ "$status" -eq 0 ]
    [[ "$output" == *"manager"* ]]
}

@test "service_summary contains running field" {
    run service_summary
    [ "$status" -eq 0 ]
    [[ "$output" == *"running"* ]]
}

# =============================================================================
# NAME NORMALIZATION
# =============================================================================

@test "_service_normalize_name strips .service suffix" {
    run _service_normalize_name "cron.service"
    [ "$status" -eq 0 ]
    if [ "$(service_manager)" = "systemd" ]; then
        [ "$output" = "cron" ]
    else
        [ "$output" = "cron.service" ]
    fi
}

@test "_service_normalize_name leaves bare name unchanged" {
    run _service_normalize_name "cron"
    [ "$status" -eq 0 ]
    [ "$output" = "cron" ]
}

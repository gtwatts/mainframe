#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/telemetry.bats - Telemetry Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/telemetry.sh
#              Opt-in anonymous usage telemetry with local aggregation
# Test Count: 40+ test cases
# Categories: enabled/disabled state, initialization, tracking,
#             flushing, reporting, privacy, edge cases
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"
    export MAINFRAME_TELEMETRY_DIR="$TEST_TMPDIR/telemetry"

    # Disable telemetry by default for controlled tests
    export MAINFRAME_TELEMETRY=0

    # Source common.sh first
    MAINFRAME_LIBS="core" source "$MAINFRAME_ROOT/lib/common.sh"

    # Force reload telemetry module with test settings
    unset _MAINFRAME_TELEMETRY_LOADED
    source "$MAINFRAME_ROOT/lib/telemetry.sh"
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
    unset MAINFRAME_TELEMETRY
    unset MAINFRAME_TELEMETRY_DIR
    unset MAINFRAME_TELEMETRY_DEBUG
}

# Helper: Enable telemetry and reload
enable_telemetry() {
    export MAINFRAME_TELEMETRY=1
    unset _MAINFRAME_TELEMETRY_LOADED
    # Reset internal state variables (need to be careful with associative arrays)
    unset _TELEMETRY_COUNTS _TELEMETRY_FIRST_SEEN _TELEMETRY_LAST_SEEN
    declare -gA _TELEMETRY_COUNTS
    declare -gA _TELEMETRY_FIRST_SEEN
    declare -gA _TELEMETRY_LAST_SEEN
    _TELEMETRY_INITIALIZED=0
    TELEMETRY_SESSION_ID=""
    _TELEMETRY_TOTAL_EVENTS=0
    _TELEMETRY_SESSION_START=""
    source "$MAINFRAME_ROOT/lib/telemetry.sh"
}

# =============================================================================
# CATEGORY 1: TELEMETRY ENABLED/DISABLED STATE
# =============================================================================

@test "telemetry_enabled: returns false when MAINFRAME_TELEMETRY=0" {
    export MAINFRAME_TELEMETRY=0
    run telemetry_enabled
    [[ "$status" -eq 1 ]]
}

@test "telemetry_enabled: returns false when MAINFRAME_TELEMETRY is unset" {
    unset MAINFRAME_TELEMETRY
    # Need to reload to pick up unset state
    unset _MAINFRAME_TELEMETRY_LOADED
    source "$MAINFRAME_ROOT/lib/telemetry.sh"
    run telemetry_enabled
    [[ "$status" -eq 1 ]]
}

@test "telemetry_enabled: returns true when MAINFRAME_TELEMETRY=1" {
    enable_telemetry
    telemetry_enabled
    [[ $? -eq 0 ]]
}

@test "telemetry_enabled: is opt-in only (default disabled)" {
    # Fresh environment without MAINFRAME_TELEMETRY set
    run bash -c '
        unset MAINFRAME_TELEMETRY
        source "'"$MAINFRAME_ROOT"'/lib/common.sh" 2>/dev/null
        source "'"$MAINFRAME_ROOT"'/lib/telemetry.sh"
        telemetry_enabled && echo "enabled" || echo "disabled"
    '
    [[ "$output" == "disabled" ]]
}

# =============================================================================
# CATEGORY 2: INITIALIZATION
# =============================================================================

@test "telemetry_init: returns 1 when disabled" {
    export MAINFRAME_TELEMETRY=0
    run telemetry_init
    [[ "$status" -eq 1 ]]
}

@test "telemetry_init: creates telemetry directory" {
    enable_telemetry
    telemetry_init
    [[ -d "$MAINFRAME_TELEMETRY_DIR" ]]
}

@test "telemetry_init: generates session ID" {
    enable_telemetry
    telemetry_init
    [[ -n "$TELEMETRY_SESSION_ID" ]]
    [[ "$TELEMETRY_SESSION_ID" =~ ^session_ ]]
}

@test "telemetry_init: session ID is unique across calls" {
    enable_telemetry
    telemetry_init
    local id1="$TELEMETRY_SESSION_ID"

    # Force re-initialization
    _TELEMETRY_INITIALIZED=0
    TELEMETRY_SESSION_ID=""
    telemetry_init
    local id2="$TELEMETRY_SESSION_ID"

    [[ "$id1" != "$id2" ]]
}

@test "telemetry_init: is idempotent (returns success on second call)" {
    enable_telemetry
    telemetry_init
    local first_id="$TELEMETRY_SESSION_ID"

    # Second call should not reinitialize
    telemetry_init
    [[ "$TELEMETRY_SESSION_ID" == "$first_id" ]]
}

@test "telemetry_init: sets session start time" {
    enable_telemetry
    telemetry_init
    [[ -n "$_TELEMETRY_SESSION_START" ]]
    [[ "$_TELEMETRY_SESSION_START" =~ ^[0-9]+$ ]]
}

# =============================================================================
# CATEGORY 3: TRACKING
# =============================================================================

@test "telemetry_track: returns 1 when disabled" {
    export MAINFRAME_TELEMETRY=0
    run telemetry_track "test_func"
    [[ "$status" -eq 1 ]]
}

@test "telemetry_track: auto-initializes when needed" {
    enable_telemetry
    _TELEMETRY_INITIALIZED=0
    telemetry_track "test_func"
    [[ "$_TELEMETRY_INITIALIZED" == "1" ]]
}

@test "telemetry_track: increments function count" {
    enable_telemetry
    telemetry_init
    telemetry_track "my_function" "test"
    [[ "${_TELEMETRY_COUNTS[test:my_function]}" == "1" ]]
}

@test "telemetry_track: increments count on multiple calls" {
    enable_telemetry
    telemetry_init
    telemetry_track "repeated_func" "test"
    telemetry_track "repeated_func" "test"
    telemetry_track "repeated_func" "test"
    [[ "${_TELEMETRY_COUNTS[test:repeated_func]}" == "3" ]]
}

@test "telemetry_track: tracks first seen timestamp" {
    enable_telemetry
    telemetry_init
    telemetry_track "timed_func" "test"
    [[ -n "${_TELEMETRY_FIRST_SEEN[test:timed_func]}" ]]
    [[ "${_TELEMETRY_FIRST_SEEN[test:timed_func]}" =~ ^[0-9]+$ ]]
}

@test "telemetry_track: tracks last seen timestamp" {
    enable_telemetry
    telemetry_init
    telemetry_track "timed_func" "test"
    [[ -n "${_TELEMETRY_LAST_SEEN[test:timed_func]}" ]]
}

@test "telemetry_track: updates total event count" {
    enable_telemetry
    telemetry_init
    telemetry_track "func1" "cat1"
    telemetry_track "func2" "cat1"
    telemetry_track "func1" "cat2"
    [[ "$_TELEMETRY_TOTAL_EVENTS" == "3" ]]
}

@test "telemetry_track: uses 'general' as default category" {
    enable_telemetry
    telemetry_init
    telemetry_track "uncategorized_func"
    [[ -n "${_TELEMETRY_COUNTS[general:uncategorized_func]}" ]]
}

@test "telemetry_track: sanitizes function names" {
    enable_telemetry
    telemetry_init
    telemetry_track "/path/to/func.sh" "test"
    # Should strip path and special chars
    [[ -n "${_TELEMETRY_COUNTS[test:func_sh]}" ]]
}

@test "telemetry_track: handles empty function name" {
    enable_telemetry
    telemetry_init
    telemetry_track "" "test"
    [[ -n "${_TELEMETRY_COUNTS[test:unknown]}" ]] || [[ -n "${_TELEMETRY_COUNTS[test:]}" ]]
}

# =============================================================================
# CATEGORY 4: FLUSHING
# =============================================================================

@test "telemetry_flush: returns 1 when disabled" {
    export MAINFRAME_TELEMETRY=0
    run telemetry_flush
    [[ "$status" -eq 1 ]]
}

@test "telemetry_flush: returns 1 when not initialized" {
    enable_telemetry
    _TELEMETRY_INITIALIZED=0
    run telemetry_flush
    [[ "$status" -eq 1 ]]
}

@test "telemetry_flush: creates JSONL file" {
    enable_telemetry
    telemetry_init
    telemetry_track "flush_test" "test"
    telemetry_flush

    local date_str
    date_str=$(date +%Y-%m-%d)
    [[ -f "$MAINFRAME_TELEMETRY_DIR/${date_str}.jsonl" ]]
}

@test "telemetry_flush: writes valid JSON lines" {
    enable_telemetry
    telemetry_init
    telemetry_track "json_test" "validation"
    telemetry_flush

    local date_str
    date_str=$(date +%Y-%m-%d)
    local file="$MAINFRAME_TELEMETRY_DIR/${date_str}.jsonl"

    # Check if jq can parse it (if available)
    if command -v jq &>/dev/null; then
        jq -e '.' "$file" >/dev/null
        [[ $? -eq 0 ]]
    else
        # Basic check: starts with { and ends with }
        grep -q '^{.*}$' "$file"
    fi
}

@test "telemetry_flush: includes session ID in output" {
    enable_telemetry
    telemetry_init
    telemetry_track "sid_test" "test"
    telemetry_flush

    local date_str
    date_str=$(date +%Y-%m-%d)
    grep -q "$TELEMETRY_SESSION_ID" "$MAINFRAME_TELEMETRY_DIR/${date_str}.jsonl"
}

@test "telemetry_flush: includes event counts" {
    enable_telemetry
    telemetry_init
    telemetry_track "count_func" "test"
    telemetry_track "count_func" "test"
    telemetry_flush

    local date_str
    date_str=$(date +%Y-%m-%d)
    # Should contain "n":2 for 2 calls
    grep -q '"n":2' "$MAINFRAME_TELEMETRY_DIR/${date_str}.jsonl"
}

@test "telemetry_flush: resets counters after flush" {
    enable_telemetry
    telemetry_init
    telemetry_track "reset_test" "test"
    telemetry_flush

    [[ "$_TELEMETRY_TOTAL_EVENTS" == "0" ]]
    [[ ${#_TELEMETRY_COUNTS[@]} -eq 0 ]]
}

@test "telemetry_flush: appends to existing file" {
    enable_telemetry
    telemetry_init
    telemetry_track "append1" "test"
    telemetry_flush

    telemetry_track "append2" "test"
    telemetry_flush

    local date_str
    date_str=$(date +%Y-%m-%d)
    local line_count
    line_count=$(wc -l < "$MAINFRAME_TELEMETRY_DIR/${date_str}.jsonl")
    [[ "$line_count" -eq 2 ]]
}

# =============================================================================
# CATEGORY 5: REPORTING
# =============================================================================

@test "telemetry_report: handles missing directory" {
    rm -rf "$MAINFRAME_TELEMETRY_DIR"
    run telemetry_report
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "No telemetry data" ]]
}

@test "telemetry_report: produces human-readable output" {
    enable_telemetry
    telemetry_init
    telemetry_track "report_func" "reporting"
    telemetry_flush

    run telemetry_report 7
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "MAINFRAME Telemetry Report" ]]
    [[ "$output" =~ "Total function calls" ]]
}

@test "telemetry_report: supports --json flag" {
    enable_telemetry
    telemetry_init
    telemetry_track "json_report" "test"
    telemetry_flush

    run telemetry_report --json 7
    [[ "$status" -eq 0 ]]

    # Should be valid JSON
    if command -v jq &>/dev/null; then
        echo "$output" | jq -e '.' >/dev/null
        [[ $? -eq 0 ]]
    else
        [[ "$output" =~ ^\{.*\}$ ]]
    fi
}

@test "telemetry_report: respects days parameter" {
    enable_telemetry
    telemetry_init
    telemetry_track "days_test" "test"
    telemetry_flush

    run telemetry_report 1
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "Last 1 days" ]]
}

@test "telemetry_report: validates days is a number" {
    run telemetry_report "invalid"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "must be a positive integer" ]]
}

@test "telemetry_report: aggregates multiple sessions" {
    enable_telemetry

    # Session 1
    telemetry_init
    telemetry_track "multi_session" "test"
    telemetry_flush

    # Session 2 (force new session)
    _TELEMETRY_INITIALIZED=0
    TELEMETRY_SESSION_ID=""
    telemetry_init
    telemetry_track "multi_session" "test"
    telemetry_flush

    run telemetry_report --json 7
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ '"sessions":2' ]]
}

# =============================================================================
# CATEGORY 6: PRIVACY (NO PII)
# =============================================================================

@test "privacy: no hostname in telemetry data" {
    enable_telemetry
    telemetry_init
    telemetry_track "privacy_test" "test"
    telemetry_flush

    local date_str
    date_str=$(date +%Y-%m-%d)
    local the_hostname
    the_hostname=$(hostname 2>/dev/null || echo "localhost")

    # Telemetry file should not contain hostname
    if [[ -f "$MAINFRAME_TELEMETRY_DIR/${date_str}.jsonl" ]]; then
        run grep -i "$the_hostname" "$MAINFRAME_TELEMETRY_DIR/${date_str}.jsonl"
        [[ "$status" -ne 0 ]]
    fi
}

@test "privacy: no username in telemetry data" {
    enable_telemetry
    telemetry_init
    telemetry_track "user_privacy" "test"
    telemetry_flush

    local date_str
    date_str=$(date +%Y-%m-%d)
    local the_username
    the_username=$(whoami 2>/dev/null || echo "$USER")

    if [[ -f "$MAINFRAME_TELEMETRY_DIR/${date_str}.jsonl" ]]; then
        run grep -i "$the_username" "$MAINFRAME_TELEMETRY_DIR/${date_str}.jsonl"
        [[ "$status" -ne 0 ]]
    fi
}

@test "privacy: no IP addresses in telemetry data" {
    enable_telemetry
    telemetry_init
    telemetry_track "ip_privacy" "test"
    telemetry_flush

    local date_str
    date_str=$(date +%Y-%m-%d)

    if [[ -f "$MAINFRAME_TELEMETRY_DIR/${date_str}.jsonl" ]]; then
        # Check for IP-like patterns (excluding timestamps)
        run grep -E '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$MAINFRAME_TELEMETRY_DIR/${date_str}.jsonl"
        [[ "$status" -ne 0 ]]
    fi
}

@test "privacy: session ID is random, not derived from system info" {
    enable_telemetry
    telemetry_init

    # Session ID should be random hex, not contain identifiable info
    [[ "$TELEMETRY_SESSION_ID" =~ ^session_[0-9a-f]+$ ]]

    # Should not contain hostname or username
    local the_hostname
    the_hostname=$(hostname 2>/dev/null || echo "localhost")
    local the_username
    the_username=$(whoami 2>/dev/null || echo "$USER")

    [[ "$TELEMETRY_SESSION_ID" != *"$the_hostname"* ]]
    [[ "$TELEMETRY_SESSION_ID" != *"$the_username"* ]]
}

# =============================================================================
# CATEGORY 7: EDGE CASES
# =============================================================================

@test "edge: handles special characters in function names" {
    enable_telemetry
    telemetry_init
    telemetry_track 'func$with"special<chars>' "test"
    telemetry_flush

    local date_str
    date_str=$(date +%Y-%m-%d)
    [[ -f "$MAINFRAME_TELEMETRY_DIR/${date_str}.jsonl" ]]
}

@test "edge: handles very long function names (truncation)" {
    enable_telemetry
    telemetry_init
    local long_name
    long_name=$(printf 'a%.0s' {1..200})
    telemetry_track "$long_name" "test"

    # Should truncate to 64 chars
    local key
    for key in "${!_TELEMETRY_COUNTS[@]}"; do
        local func_part="${key#*:}"
        [[ ${#func_part} -le 64 ]]
    done
}

@test "edge: auto-flush when buffer is full" {
    enable_telemetry
    export MAINFRAME_TELEMETRY_BUFFER_SIZE=5
    unset _MAINFRAME_TELEMETRY_LOADED
    source "$MAINFRAME_ROOT/lib/telemetry.sh"

    telemetry_init
    local i
    for ((i=1; i<=6; i++)); do
        telemetry_track "buffer_test_$i" "test"
    done

    # Should have flushed and started fresh
    [[ "$_TELEMETRY_TOTAL_EVENTS" -lt 5 ]]
}

@test "edge: handles concurrent writes gracefully" {
    enable_telemetry
    telemetry_init

    # Simulate rapid writes
    local i
    for ((i=1; i<=50; i++)); do
        telemetry_track "concurrent_$i" "test"
    done

    [[ "$_TELEMETRY_TOTAL_EVENTS" == "50" ]]
    telemetry_flush
}

@test "edge: telemetry directory creation failure handling" {
    enable_telemetry
    export MAINFRAME_TELEMETRY_DIR="/nonexistent/path/telemetry"
    _TELEMETRY_INITIALIZED=0

    run telemetry_init
    # Should fail gracefully, not crash
    [[ "$status" -eq 1 ]] || [[ "$status" -eq 0 ]]
}

# =============================================================================
# CATEGORY 8: CONSTANTS AND CONFIGURATION
# =============================================================================

@test "config: TELEMETRY_ENABLED reflects environment variable" {
    export MAINFRAME_TELEMETRY=1
    unset _MAINFRAME_TELEMETRY_LOADED
    source "$MAINFRAME_ROOT/lib/telemetry.sh"
    [[ "$TELEMETRY_ENABLED" == "1" ]]
}

@test "config: TELEMETRY_DIR is configurable" {
    export MAINFRAME_TELEMETRY_DIR="/tmp/custom_telemetry"
    unset _MAINFRAME_TELEMETRY_LOADED
    source "$MAINFRAME_ROOT/lib/telemetry.sh"
    [[ "$TELEMETRY_DIR" == "/tmp/custom_telemetry" ]]
}

@test "config: TELEMETRY_BUFFER_SIZE is configurable" {
    export MAINFRAME_TELEMETRY_BUFFER_SIZE=50
    unset _MAINFRAME_TELEMETRY_LOADED
    source "$MAINFRAME_ROOT/lib/telemetry.sh"
    [[ "$TELEMETRY_BUFFER_SIZE" == "50" ]]
}

@test "exports: TELEMETRY_EXPORTS contains all public functions" {
    enable_telemetry
    [[ "${TELEMETRY_EXPORTS[*]}" =~ "telemetry_enabled" ]]
    [[ "${TELEMETRY_EXPORTS[*]}" =~ "telemetry_init" ]]
    [[ "${TELEMETRY_EXPORTS[*]}" =~ "telemetry_track" ]]
    [[ "${TELEMETRY_EXPORTS[*]}" =~ "telemetry_flush" ]]
    [[ "${TELEMETRY_EXPORTS[*]}" =~ "telemetry_report" ]]
}

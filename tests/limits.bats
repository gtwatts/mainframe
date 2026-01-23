#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Limits Module Tests
# =============================================================================

load 'test_helper'

setup() {
    source_lib "limits"
    export TEST_DIR="$(mktemp -d)"
    # Reset state for each test
    _MAINFRAME_LIMIT_ENABLED=0
    _MAINFRAME_LIMIT_MAX_FILES=0
    _MAINFRAME_LIMIT_MAX_WRITES=0
    _MAINFRAME_LIMIT_MAX_TIME=0
    _MAINFRAME_LIMIT_MAX_DEPTH=0
    _MAINFRAME_LIMIT_MAX_NETWORK=0
    _MAINFRAME_LIMIT_DIR=""
    mainframe_limit_init
}

teardown() {
    rm -rf "$TEST_DIR"
    if [[ -n "${_MAINFRAME_LIMIT_DIR:-}" ]] && [[ -d "$_MAINFRAME_LIMIT_DIR" ]]; then
        rm -rf "$_MAINFRAME_LIMIT_DIR"
    fi
    _MAINFRAME_LIMIT_ENABLED=0
    _MAINFRAME_LIMIT_DIR=""
}

# =============================================================================
# DOUBLE-SOURCE GUARD
# =============================================================================

@test "double-source guard prevents re-loading" {
    local loaded_before="$_MAINFRAME_LIMITS_LOADED"
    source "$MAINFRAME_ROOT/lib/limits.sh"
    [ "$_MAINFRAME_LIMITS_LOADED" = "$loaded_before" ]
}

@test "_MAINFRAME_LIMITS_LOADED is set to 1" {
    [ "$_MAINFRAME_LIMITS_LOADED" = "1" ]
}

# =============================================================================
# mainframe_limit_init TESTS
# =============================================================================

@test "mainframe_limit_init creates tracking directory" {
    [ -d "$_MAINFRAME_LIMIT_DIR" ]
}

@test "mainframe_limit_init enables the system" {
    mainframe_limit_is_enabled
}

@test "mainframe_limit_init creates counter files" {
    [ -f "$_MAINFRAME_LIMIT_DIR/files.count" ]
    [ -f "$_MAINFRAME_LIMIT_DIR/writes.count" ]
    [ -f "$_MAINFRAME_LIMIT_DIR/depth.count" ]
    [ -f "$_MAINFRAME_LIMIT_DIR/network.count" ]
}

@test "mainframe_limit_init initializes counters to zero" {
    local val
    val=$(cat "$_MAINFRAME_LIMIT_DIR/files.count")
    [ "$val" = "0" ]
}

@test "mainframe_limit_init is idempotent" {
    local dir_before="$_MAINFRAME_LIMIT_DIR"
    mainframe_limit_init
    [ "$_MAINFRAME_LIMIT_DIR" = "$dir_before" ]
}

@test "mainframe_limit_init records start time" {
    local start
    start=$(cat "$_MAINFRAME_LIMIT_DIR/start_time.count")
    [[ "$start" =~ ^[0-9]+$ ]]
    [ "$start" -gt 0 ]
}

# =============================================================================
# mainframe_limit_files TESTS
# =============================================================================

@test "mainframe_limit_files sets max file operations" {
    mainframe_limit_files 100
    [ "$_MAINFRAME_LIMIT_MAX_FILES" = "100" ]
}

@test "mainframe_limit_files accepts zero" {
    mainframe_limit_files 0
    [ "$_MAINFRAME_LIMIT_MAX_FILES" = "0" ]
}

@test "mainframe_limit_files rejects empty argument" {
    run mainframe_limit_files ""
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_files rejects non-numeric" {
    run mainframe_limit_files "abc"
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_files rejects negative numbers" {
    run mainframe_limit_files "-5"
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_files rejects float numbers" {
    run mainframe_limit_files "3.14"
    [ "$status" -eq 1 ]
}

# =============================================================================
# mainframe_limit_writes TESTS
# =============================================================================

@test "mainframe_limit_writes sets max write volume in bytes" {
    mainframe_limit_writes "1024"
    [ "$_MAINFRAME_LIMIT_MAX_WRITES" = "1024" ]
}

@test "mainframe_limit_writes parses KB" {
    mainframe_limit_writes "10KB"
    [ "$_MAINFRAME_LIMIT_MAX_WRITES" = "10240" ]
}

@test "mainframe_limit_writes parses MB" {
    mainframe_limit_writes "5MB"
    [ "$_MAINFRAME_LIMIT_MAX_WRITES" = "5242880" ]
}

@test "mainframe_limit_writes parses GB" {
    mainframe_limit_writes "1GB"
    [ "$_MAINFRAME_LIMIT_MAX_WRITES" = "1073741824" ]
}

@test "mainframe_limit_writes parses lowercase kb" {
    mainframe_limit_writes "10kb"
    [ "$_MAINFRAME_LIMIT_MAX_WRITES" = "10240" ]
}

@test "mainframe_limit_writes parses mixed case Mb" {
    mainframe_limit_writes "2Mb"
    [ "$_MAINFRAME_LIMIT_MAX_WRITES" = "2097152" ]
}

@test "mainframe_limit_writes parses single letter K" {
    mainframe_limit_writes "4K"
    [ "$_MAINFRAME_LIMIT_MAX_WRITES" = "4096" ]
}

@test "mainframe_limit_writes parses single letter M" {
    mainframe_limit_writes "2M"
    [ "$_MAINFRAME_LIMIT_MAX_WRITES" = "2097152" ]
}

@test "mainframe_limit_writes parses single letter G" {
    mainframe_limit_writes "3G"
    [ "$_MAINFRAME_LIMIT_MAX_WRITES" = "3221225472" ]
}

@test "mainframe_limit_writes parses B suffix" {
    mainframe_limit_writes "512B"
    [ "$_MAINFRAME_LIMIT_MAX_WRITES" = "512" ]
}

@test "mainframe_limit_writes rejects empty argument" {
    run mainframe_limit_writes ""
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_writes rejects invalid format" {
    run mainframe_limit_writes "10XB"
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_writes rejects text-only input" {
    run mainframe_limit_writes "megabytes"
    [ "$status" -eq 1 ]
}

# =============================================================================
# mainframe_limit_time TESTS
# =============================================================================

@test "mainframe_limit_time sets max seconds" {
    mainframe_limit_time 300
    [ "$_MAINFRAME_LIMIT_MAX_TIME" = "300" ]
}

@test "mainframe_limit_time accepts zero" {
    mainframe_limit_time 0
    [ "$_MAINFRAME_LIMIT_MAX_TIME" = "0" ]
}

@test "mainframe_limit_time rejects empty argument" {
    run mainframe_limit_time ""
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_time rejects non-numeric" {
    run mainframe_limit_time "5m"
    [ "$status" -eq 1 ]
}

# =============================================================================
# mainframe_limit_depth TESTS
# =============================================================================

@test "mainframe_limit_depth sets max depth" {
    mainframe_limit_depth 10
    [ "$_MAINFRAME_LIMIT_MAX_DEPTH" = "10" ]
}

@test "mainframe_limit_depth rejects empty argument" {
    run mainframe_limit_depth ""
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_depth rejects non-numeric" {
    run mainframe_limit_depth "deep"
    [ "$status" -eq 1 ]
}

# =============================================================================
# mainframe_limit_network TESTS
# =============================================================================

@test "mainframe_limit_network sets max network ops" {
    mainframe_limit_network 50
    [ "$_MAINFRAME_LIMIT_MAX_NETWORK" = "50" ]
}

@test "mainframe_limit_network rejects empty argument" {
    run mainframe_limit_network ""
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_network rejects non-numeric" {
    run mainframe_limit_network "many"
    [ "$status" -eq 1 ]
}

# =============================================================================
# mainframe_limit_check TESTS
# =============================================================================

@test "mainframe_limit_check returns 0 when under limit" {
    mainframe_limit_files 10
    mainframe_limit_check files
}

@test "mainframe_limit_check returns 1 when at limit" {
    mainframe_limit_files 5
    mainframe_limit_increment files 5
    ! mainframe_limit_check files
}

@test "mainframe_limit_check returns 1 when over limit" {
    mainframe_limit_files 3
    mainframe_limit_increment files 10
    ! mainframe_limit_check files
}

@test "mainframe_limit_check returns 0 when unlimited (max=0)" {
    mainframe_limit_increment files 999
    mainframe_limit_check files
}

@test "mainframe_limit_check returns 0 when system disabled" {
    _MAINFRAME_LIMIT_ENABLED=0
    mainframe_limit_check files
}

@test "mainframe_limit_check rejects empty type" {
    run mainframe_limit_check ""
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_check rejects unknown type" {
    run mainframe_limit_check "memory"
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_check works for writes type" {
    mainframe_limit_writes "1KB"
    mainframe_limit_increment writes 512
    mainframe_limit_check writes
}

@test "mainframe_limit_check detects writes exceeded" {
    mainframe_limit_writes "1KB"
    mainframe_limit_increment writes 2048
    ! mainframe_limit_check writes
}

@test "mainframe_limit_check works for depth type" {
    mainframe_limit_depth 5
    mainframe_limit_increment depth 3
    mainframe_limit_check depth
}

@test "mainframe_limit_check works for network type" {
    mainframe_limit_network 10
    mainframe_limit_increment network 5
    mainframe_limit_check network
}

@test "mainframe_limit_check detects network exceeded" {
    mainframe_limit_network 2
    mainframe_limit_increment network 3
    ! mainframe_limit_check network
}

# =============================================================================
# mainframe_limit_increment TESTS
# =============================================================================

@test "mainframe_limit_increment adds 1 by default" {
    mainframe_limit_increment files
    local val
    val=$(cat "$_MAINFRAME_LIMIT_DIR/files.count")
    [ "$val" = "1" ]
}

@test "mainframe_limit_increment adds specified amount" {
    mainframe_limit_increment files 5
    local val
    val=$(cat "$_MAINFRAME_LIMIT_DIR/files.count")
    [ "$val" = "5" ]
}

@test "mainframe_limit_increment accumulates" {
    mainframe_limit_increment files 3
    mainframe_limit_increment files 7
    local val
    val=$(cat "$_MAINFRAME_LIMIT_DIR/files.count")
    [ "$val" = "10" ]
}

@test "mainframe_limit_increment works for writes" {
    mainframe_limit_increment writes 4096
    local val
    val=$(cat "$_MAINFRAME_LIMIT_DIR/writes.count")
    [ "$val" = "4096" ]
}

@test "mainframe_limit_increment works for depth" {
    mainframe_limit_increment depth 2
    local val
    val=$(cat "$_MAINFRAME_LIMIT_DIR/depth.count")
    [ "$val" = "2" ]
}

@test "mainframe_limit_increment works for network" {
    mainframe_limit_increment network 1
    local val
    val=$(cat "$_MAINFRAME_LIMIT_DIR/network.count")
    [ "$val" = "1" ]
}

@test "mainframe_limit_increment rejects time type" {
    run mainframe_limit_increment time 1
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_increment rejects unknown type" {
    run mainframe_limit_increment "cpu" 1
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_increment rejects non-numeric amount" {
    run mainframe_limit_increment files "abc"
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_increment fails when not initialized" {
    _MAINFRAME_LIMIT_ENABLED=0
    _MAINFRAME_LIMIT_DIR=""
    run mainframe_limit_increment files 1
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_increment with zero amount is valid" {
    mainframe_limit_increment files 0
    local val
    val=$(cat "$_MAINFRAME_LIMIT_DIR/files.count")
    [ "$val" = "0" ]
}

# =============================================================================
# mainframe_limit_status TESTS
# =============================================================================

@test "mainframe_limit_status shows disabled when not enabled" {
    _MAINFRAME_LIMIT_ENABLED=0
    local output
    output=$(mainframe_limit_status)
    [[ "$output" == *"DISABLED"* ]]
}

@test "mainframe_limit_status shows enabled when active" {
    local output
    output=$(mainframe_limit_status)
    [[ "$output" == *"ENABLED"* ]]
}

@test "mainframe_limit_status JSON output when disabled" {
    _MAINFRAME_LIMIT_ENABLED=0
    export MAINFRAME_OUTPUT=json
    local output
    output=$(mainframe_limit_status)
    [[ "$output" == *'"enabled":false'* ]]
}

@test "mainframe_limit_status JSON output when enabled" {
    export MAINFRAME_OUTPUT=json
    local output
    output=$(mainframe_limit_status)
    [[ "$output" == *'"enabled":true'* ]]
}

@test "mainframe_limit_status JSON includes all limit types" {
    export MAINFRAME_OUTPUT=json
    mainframe_limit_files 100
    mainframe_limit_increment files 5
    local output
    output=$(mainframe_limit_status)
    [[ "$output" == *'"files":'* ]]
    [[ "$output" == *'"writes":'* ]]
    [[ "$output" == *'"time":'* ]]
    [[ "$output" == *'"depth":'* ]]
    [[ "$output" == *'"network":'* ]]
}

@test "mainframe_limit_status JSON shows current and max" {
    export MAINFRAME_OUTPUT=json
    mainframe_limit_files 50
    mainframe_limit_increment files 10
    local output
    output=$(mainframe_limit_status)
    [[ "$output" == *'"current":10'* ]]
    [[ "$output" == *'"max":50'* ]]
}

@test "mainframe_limit_status plain text shows unlimited" {
    local output
    output=$(mainframe_limit_status)
    [[ "$output" == *"unlimited"* ]]
}

@test "mainframe_limit_status plain text shows actual limit" {
    mainframe_limit_files 25
    local output
    output=$(mainframe_limit_status)
    [[ "$output" == *"25"* ]]
}

# =============================================================================
# mainframe_limit_reset TESTS
# =============================================================================

@test "mainframe_limit_reset clears all counters" {
    mainframe_limit_increment files 10
    mainframe_limit_increment writes 5000
    mainframe_limit_increment depth 3
    mainframe_limit_increment network 7
    mainframe_limit_reset
    local val
    val=$(cat "$_MAINFRAME_LIMIT_DIR/files.count")
    [ "$val" = "0" ]
    val=$(cat "$_MAINFRAME_LIMIT_DIR/writes.count")
    [ "$val" = "0" ]
}

@test "mainframe_limit_reset clears maximums" {
    mainframe_limit_files 100
    mainframe_limit_writes "10MB"
    mainframe_limit_reset
    [ "$_MAINFRAME_LIMIT_MAX_FILES" = "0" ]
    [ "$_MAINFRAME_LIMIT_MAX_WRITES" = "0" ]
}

@test "mainframe_limit_reset specific type only resets that counter" {
    mainframe_limit_increment files 10
    mainframe_limit_increment writes 5000
    mainframe_limit_reset files
    local files_val writes_val
    files_val=$(cat "$_MAINFRAME_LIMIT_DIR/files.count")
    writes_val=$(cat "$_MAINFRAME_LIMIT_DIR/writes.count")
    [ "$files_val" = "0" ]
    [ "$writes_val" = "5000" ]
}

@test "mainframe_limit_reset rejects unknown type" {
    run mainframe_limit_reset "memory"
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_reset time resets start_time" {
    sleep 1
    mainframe_limit_reset time
    local start
    start=$(cat "$_MAINFRAME_LIMIT_DIR/start_time.count")
    local now
    now=$(date +%s)
    local diff=$(( now - start ))
    [ "$diff" -le 1 ]
}

# =============================================================================
# mainframe_limit_remaining TESTS
# =============================================================================

@test "mainframe_limit_remaining shows unlimited when max=0" {
    local output
    output=$(mainframe_limit_remaining files)
    [ "$output" = "unlimited" ]
}

@test "mainframe_limit_remaining shows correct remaining" {
    mainframe_limit_files 10
    mainframe_limit_increment files 3
    local output
    output=$(mainframe_limit_remaining files)
    [ "$output" = "7" ]
}

@test "mainframe_limit_remaining shows zero when at limit" {
    mainframe_limit_files 5
    mainframe_limit_increment files 5
    local output
    output=$(mainframe_limit_remaining files)
    [ "$output" = "0" ]
}

@test "mainframe_limit_remaining returns 1 when exceeded" {
    mainframe_limit_files 5
    mainframe_limit_increment files 10
    run mainframe_limit_remaining files
    [ "$status" -eq 1 ]
    [ "$output" = "0" ]
}

@test "mainframe_limit_remaining works for writes" {
    mainframe_limit_writes "1KB"
    mainframe_limit_increment writes 512
    local output
    output=$(mainframe_limit_remaining writes)
    [ "$output" = "512" ]
}

@test "mainframe_limit_remaining rejects empty type" {
    run mainframe_limit_remaining ""
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_remaining rejects unknown type" {
    run mainframe_limit_remaining "cpu"
    [ "$status" -eq 1 ]
}

# =============================================================================
# mainframe_limit_enforce TESTS
# =============================================================================

@test "mainframe_limit_enforce runs command when within limits" {
    mainframe_limit_files 10
    local output
    output=$(mainframe_limit_enforce echo "hello")
    [ "$output" = "hello" ]
}

@test "mainframe_limit_enforce blocks when limit exceeded" {
    mainframe_limit_files 2
    mainframe_limit_increment files 5
    run mainframe_limit_enforce echo "blocked"
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_enforce blocks with JSON error" {
    export MAINFRAME_OUTPUT=json
    mainframe_limit_files 1
    mainframe_limit_increment files 5
    local err
    err=$(mainframe_limit_enforce echo "nope" 2>&1) || true
    [[ "$err" == *'"blocked":true'* ]]
}

@test "mainframe_limit_enforce blocks with plain text error" {
    unset MAINFRAME_OUTPUT
    mainframe_limit_files 1
    mainframe_limit_increment files 5
    local err
    err=$(mainframe_limit_enforce echo "nope" 2>&1) || true
    [[ "$err" == *"BLOCKED"* ]]
}

@test "mainframe_limit_enforce increments file counter on success" {
    mainframe_limit_files 10
    mainframe_limit_enforce true
    local val
    val=$(cat "$_MAINFRAME_LIMIT_DIR/files.count")
    [ "$val" = "1" ]
}

@test "mainframe_limit_enforce does not increment on command failure" {
    mainframe_limit_files 10
    mainframe_limit_enforce false 2>/dev/null || true
    local val
    val=$(cat "$_MAINFRAME_LIMIT_DIR/files.count")
    [ "$val" = "0" ]
}

@test "mainframe_limit_enforce passes through command exit code" {
    mainframe_limit_files 10
    run mainframe_limit_enforce false
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_enforce runs without limits enabled" {
    _MAINFRAME_LIMIT_ENABLED=0
    local output
    output=$(mainframe_limit_enforce echo "unrestricted")
    [ "$output" = "unrestricted" ]
}

@test "mainframe_limit_enforce requires a command" {
    run mainframe_limit_enforce
    [ "$status" -eq 1 ]
}

@test "mainframe_limit_enforce checks all active limits" {
    mainframe_limit_files 10
    mainframe_limit_network 2
    mainframe_limit_increment network 5
    run mainframe_limit_enforce echo "nope"
    [ "$status" -eq 1 ]
}

# =============================================================================
# mainframe_limit_is_enabled TESTS
# =============================================================================

@test "mainframe_limit_is_enabled returns 0 when active" {
    mainframe_limit_is_enabled
}

@test "mainframe_limit_is_enabled returns 1 when inactive" {
    _MAINFRAME_LIMIT_ENABLED=0
    ! mainframe_limit_is_enabled
}

# =============================================================================
# _limit_parse_size TESTS
# =============================================================================

@test "_limit_parse_size parses plain bytes" {
    local result
    result=$(_limit_parse_size "1024")
    [ "$result" = "1024" ]
}

@test "_limit_parse_size parses 1KB" {
    local result
    result=$(_limit_parse_size "1KB")
    [ "$result" = "1024" ]
}

@test "_limit_parse_size parses 1MB" {
    local result
    result=$(_limit_parse_size "1MB")
    [ "$result" = "1048576" ]
}

@test "_limit_parse_size parses 1GB" {
    local result
    result=$(_limit_parse_size "1GB")
    [ "$result" = "1073741824" ]
}

@test "_limit_parse_size parses lowercase kb" {
    local result
    result=$(_limit_parse_size "5kb")
    [ "$result" = "5120" ]
}

@test "_limit_parse_size parses lowercase mb" {
    local result
    result=$(_limit_parse_size "2mb")
    [ "$result" = "2097152" ]
}

@test "_limit_parse_size parses lowercase gb" {
    local result
    result=$(_limit_parse_size "1gb")
    [ "$result" = "1073741824" ]
}

@test "_limit_parse_size parses mixed case KB" {
    local result
    result=$(_limit_parse_size "10Kb")
    [ "$result" = "10240" ]
}

@test "_limit_parse_size parses B suffix" {
    local result
    result=$(_limit_parse_size "256B")
    [ "$result" = "256" ]
}

@test "_limit_parse_size parses lowercase b" {
    local result
    result=$(_limit_parse_size "128b")
    [ "$result" = "128" ]
}

@test "_limit_parse_size parses single K" {
    local result
    result=$(_limit_parse_size "8K")
    [ "$result" = "8192" ]
}

@test "_limit_parse_size parses single M" {
    local result
    result=$(_limit_parse_size "4M")
    [ "$result" = "4194304" ]
}

@test "_limit_parse_size parses single G" {
    local result
    result=$(_limit_parse_size "2G")
    [ "$result" = "2147483648" ]
}

@test "_limit_parse_size parses zero" {
    local result
    result=$(_limit_parse_size "0")
    [ "$result" = "0" ]
}

@test "_limit_parse_size returns 1 for empty input" {
    run _limit_parse_size ""
    [ "$status" -eq 1 ]
}

@test "_limit_parse_size returns 1 for invalid suffix" {
    run _limit_parse_size "10XB"
    [ "$status" -eq 1 ]
}

@test "_limit_parse_size returns 1 for text only" {
    run _limit_parse_size "megabytes"
    [ "$status" -eq 1 ]
}

@test "_limit_parse_size returns 1 for negative number" {
    run _limit_parse_size "-5KB"
    [ "$status" -eq 1 ]
}

# =============================================================================
# _limit_error TESTS
# =============================================================================

@test "_limit_error emits JSON when MAINFRAME_OUTPUT=json" {
    export MAINFRAME_OUTPUT=json
    local err
    err=$(_limit_error 1 "test error" 2>&1) || true
    [[ "$err" == *'"error":true'* ]]
    [[ "$err" == *'"module":"limits"'* ]]
    [[ "$err" == *'"msg":"test error"'* ]]
}

@test "_limit_error emits plain text by default" {
    unset MAINFRAME_OUTPUT
    local err
    err=$(_limit_error 1 "plain error" 2>&1) || true
    [[ "$err" == *"[limits]"* ]]
    [[ "$err" == *"plain error"* ]]
}

@test "_limit_error returns provided exit code" {
    local rc=0
    _limit_error 42 "test" 2>/dev/null || rc=$?
    [ "$rc" = "42" ]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "limit of 1 blocks on second operation" {
    mainframe_limit_files 1
    mainframe_limit_increment files 1
    ! mainframe_limit_check files
}

@test "large limit values work correctly" {
    mainframe_limit_files 999999999
    mainframe_limit_increment files 999999998
    mainframe_limit_check files
}

@test "limit exactly at boundary is exceeded" {
    mainframe_limit_files 5
    mainframe_limit_increment files 5
    ! mainframe_limit_check files
}

@test "multiple limits can be set simultaneously" {
    mainframe_limit_files 10
    mainframe_limit_writes "1MB"
    mainframe_limit_depth 5
    mainframe_limit_network 20
    [ "$_MAINFRAME_LIMIT_MAX_FILES" = "10" ]
    [ "$_MAINFRAME_LIMIT_MAX_WRITES" = "1048576" ]
    [ "$_MAINFRAME_LIMIT_MAX_DEPTH" = "5" ]
    [ "$_MAINFRAME_LIMIT_MAX_NETWORK" = "20" ]
}

@test "counter values survive across function calls" {
    mainframe_limit_increment files 3
    mainframe_limit_increment files 4
    local remaining
    mainframe_limit_files 10
    remaining=$(mainframe_limit_remaining files)
    [ "$remaining" = "3" ]
}

@test "resetting one type does not affect others" {
    mainframe_limit_increment files 5
    mainframe_limit_increment network 8
    mainframe_limit_reset files
    local net
    net=$(cat "$_MAINFRAME_LIMIT_DIR/network.count")
    [ "$net" = "8" ]
}

@test "check after reset returns within limits" {
    mainframe_limit_files 5
    mainframe_limit_increment files 10
    ! mainframe_limit_check files
    mainframe_limit_reset files
    mainframe_limit_check files
}

@test "writes limit with exact boundary in bytes" {
    mainframe_limit_writes "1024"
    mainframe_limit_increment writes 1024
    ! mainframe_limit_check writes
}

@test "enforce with multiple args passes all to command" {
    mainframe_limit_files 10
    local output
    output=$(mainframe_limit_enforce printf '%s %s' "hello" "world")
    [ "$output" = "hello world" ]
}

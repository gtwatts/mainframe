#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/audit.bats - Audit Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/audit.sh
#              Compliance audit logging for enterprise deployments
# Test Count: 50 test cases
# Categories: initialization, logging, querying, export, signing, verification,
#             rotation, retention, statistics, alerting, convenience functions
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"
    TEST_AUDIT_LOG="${TEST_TMPDIR}/audit.jsonl"
    TEST_HMAC_KEY="test_secret_key_12345"

    # Source the libraries
    source "$MAINFRAME_ROOT/lib/json.sh"
    source "$MAINFRAME_ROOT/lib/audit.sh"

    # Reset audit state before each test
    _AUDIT_INITIALIZED=0
    _AUDIT_LAST_HASH=""
    _AUDIT_ALERTS=()
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# CATEGORY 1: INITIALIZATION
# =============================================================================

@test "audit_init: initializes with default settings" {
    audit_init --output "$TEST_AUDIT_LOG"
    [[ "$_AUDIT_INITIALIZED" -eq 1 ]]
    [[ "$_AUDIT_OUTPUT" == "$TEST_AUDIT_LOG" ]]
}

@test "audit_init: enables signing when requested" {
    audit_init --output "$TEST_AUDIT_LOG" --sign true --hmac-key "$TEST_HMAC_KEY"
    [[ "$_AUDIT_SIGN_ENABLED" -eq 1 ]]
}

@test "audit_init: fails when signing enabled without key" {
    run audit_init --output "$TEST_AUDIT_LOG" --sign true
    [[ "$status" -eq 1 ]]
}

@test "audit_init: generates session ID automatically" {
    audit_init --output "$TEST_AUDIT_LOG"
    [[ -n "$_AUDIT_SESSION_ID" ]]
    [[ "$_AUDIT_SESSION_ID" =~ ^sess_ ]]
}

@test "audit_init: accepts custom session ID" {
    audit_init --output "$TEST_AUDIT_LOG" --session-id "custom_session_123"
    [[ "$_AUDIT_SESSION_ID" == "custom_session_123" ]]
}

@test "audit_init: sets retention days" {
    audit_init --output "$TEST_AUDIT_LOG" --retention 30
    [[ "$_AUDIT_RETENTION_DAYS" -eq 30 ]]
}

@test "audit_init: creates parent directories" {
    local nested_log="${TEST_TMPDIR}/nested/path/audit.jsonl"
    audit_init --output "$nested_log"
    [[ -d "${TEST_TMPDIR}/nested/path" ]]
}

# =============================================================================
# CATEGORY 2: CORE LOGGING
# =============================================================================

@test "audit_log: creates valid JSON entry" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "file_write" "agent:agent-123:operator" "/tmp/test.txt" "success"

    [[ -f "$TEST_AUDIT_LOG" ]]
    local entry=$(cat "$TEST_AUDIT_LOG")
    [[ "$entry" =~ \"action\":\"file_write\" ]]
    [[ "$entry" =~ \"result\":\"success\" ]]
}

@test "audit_log: includes actor information" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "api_call" "agent:agent-123:admin,operator" "/api/users" "success"

    local entry=$(cat "$TEST_AUDIT_LOG")
    [[ "$entry" =~ \"type\":\"agent\" ]]
    [[ "$entry" =~ \"id\":\"agent-123\" ]]
    [[ "$entry" =~ \"roles\":\[\"admin\",\"operator\"\] ]]
}

@test "audit_log: includes resource information" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "read" "user-1" "file:/etc/config" "success"

    local entry=$(cat "$TEST_AUDIT_LOG")
    [[ "$entry" =~ \"type\":\"file\" ]]
    [[ "$entry" =~ \"path\":\"/etc/config\" ]]
}

@test "audit_log: includes custom details" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "file_write" "agent-1" "/tmp/out.json" "success" "bytes_written=1024" "duration_ms=50"

    local entry=$(cat "$TEST_AUDIT_LOG")
    [[ "$entry" =~ \"bytes_written\":1024 ]]
    [[ "$entry" =~ \"duration_ms\":50 ]]
}

@test "audit_log: generates unique IDs" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "action1" "actor1" "/resource1" "success"
    audit_log "action2" "actor2" "/resource2" "success"

    local id1 id2
    id1=$(head -1 "$TEST_AUDIT_LOG" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    id2=$(tail -1 "$TEST_AUDIT_LOG" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)

    [[ "$id1" != "$id2" ]]
    [[ "$id1" =~ ^aud_ ]]
}

@test "audit_log: maintains chain hash" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "action1" "actor1" "/resource1" "success"
    audit_log "action2" "actor2" "/resource2" "success"

    local chain1 hash1 chain2
    chain1=$(head -1 "$TEST_AUDIT_LOG" | grep -o '"chain_hash":"[^"]*"' | cut -d'"' -f4)
    hash1=$(head -1 "$TEST_AUDIT_LOG" | grep -o '"hash":"sha256:[^"]*"' | sed 's/.*sha256://' | tr -d '"')
    chain2=$(tail -1 "$TEST_AUDIT_LOG" | grep -o '"chain_hash":"[^"]*"' | cut -d'"' -f4)

    [[ "$chain1" == "genesis" ]]
    [[ "$chain2" == "$hash1" ]]
}

@test "audit_log: validates result values" {
    audit_init --output "$TEST_AUDIT_LOG"

    audit_log "test" "actor" "/resource" "success"
    local entry=$(tail -1 "$TEST_AUDIT_LOG")
    [[ "$entry" =~ \"result\":\"success\" ]]

    audit_log "test" "actor" "/resource" "failure"
    entry=$(tail -1 "$TEST_AUDIT_LOG")
    [[ "$entry" =~ \"result\":\"failure\" ]]

    audit_log "test" "actor" "/resource" "denied"
    entry=$(tail -1 "$TEST_AUDIT_LOG")
    [[ "$entry" =~ \"result\":\"denied\" ]]
}

@test "audit_log: auto-initializes if not initialized" {
    # Don't call audit_init
    _AUDIT_OUTPUT="$TEST_AUDIT_LOG"
    audit_log "test" "actor" "/resource" "success"

    [[ -f "$TEST_AUDIT_LOG" ]]
}

# =============================================================================
# CATEGORY 3: SIGNING
# =============================================================================

@test "audit_log: includes signature when signing enabled" {
    audit_init --output "$TEST_AUDIT_LOG" --sign true --hmac-key "$TEST_HMAC_KEY"
    audit_log "test" "actor" "/resource" "success"

    local entry=$(cat "$TEST_AUDIT_LOG")
    [[ "$entry" =~ \"signature\":\"sha256: ]]
}

@test "audit_sign: creates signature file" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "test" "actor" "/resource" "success"

    run audit_sign "$TEST_AUDIT_LOG" --key "$TEST_HMAC_KEY"
    [[ "$status" -eq 0 ]]
    [[ -f "${TEST_AUDIT_LOG}.sig" ]]
}

@test "audit_sign: signature file contains required fields" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "test" "actor" "/resource" "success"
    audit_sign "$TEST_AUDIT_LOG" --key "$TEST_HMAC_KEY"

    local sig_content=$(<"${TEST_AUDIT_LOG}.sig")
    [[ "$sig_content" =~ \"file\": ]]
    [[ "$sig_content" =~ \"hash\": ]]
    [[ "$sig_content" =~ \"signature\": ]]
    [[ "$sig_content" =~ \"timestamp\": ]]
}

# =============================================================================
# CATEGORY 4: VERIFICATION
# =============================================================================

@test "audit_verify: validates intact log" {
    audit_init --output "$TEST_AUDIT_LOG" --sign true --hmac-key "$TEST_HMAC_KEY"
    audit_log "test1" "actor1" "/resource1" "success"
    audit_log "test2" "actor2" "/resource2" "success"
    audit_sign "$TEST_AUDIT_LOG" --key "$TEST_HMAC_KEY"

    run audit_verify "$TEST_AUDIT_LOG" --key "$TEST_HMAC_KEY"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ \"status\":\"valid\" ]]
    [[ "$output" =~ \"chain_valid\":true ]]
}

@test "audit_verify: detects tampered log" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "test1" "actor1" "/resource1" "success"
    audit_log "test2" "actor2" "/resource2" "success"

    # Tamper with the log by modifying middle entry
    # (sed -i behaves differently on GNU vs BSD; -i.bak works on both)
    sed -i.bak 's/"success"/"failure"/' "$TEST_AUDIT_LOG" && rm -f "$TEST_AUDIT_LOG.bak"

    run audit_verify "$TEST_AUDIT_LOG"
    [[ "$output" =~ \"chain_valid\":false ]] || [[ "$output" =~ \"status\":\"invalid\" ]]
}

@test "audit_verify: reports entry count" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "test1" "actor1" "/resource1" "success"
    audit_log "test2" "actor2" "/resource2" "success"
    audit_log "test3" "actor3" "/resource3" "success"

    run audit_verify "$TEST_AUDIT_LOG"
    [[ "$output" =~ \"entries\":3 ]]
}

# =============================================================================
# CATEGORY 5: QUERYING
# =============================================================================

@test "audit_query: returns all entries with no filters" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "action1" "actor1" "/resource1" "success"
    audit_log "action2" "actor2" "/resource2" "failure"

    run audit_query --format jsonl
    [[ "$status" -eq 0 ]]
    local count=$(echo "$output" | wc -l)
    [[ $count -eq 2 ]]
}

@test "audit_query: filters by actor" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "action1" "agent:agent-1:op" "/resource1" "success"
    audit_log "action2" "agent:agent-2:op" "/resource2" "success"
    audit_log "action3" "agent:agent-1:op" "/resource3" "success"

    run audit_query --actor "agent-1" --format jsonl
    local count=$(echo "$output" | grep -c "agent-1")
    [[ $count -eq 2 ]]
}

@test "audit_query: filters by actor with wildcard" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "action1" "agent:agent-1:op" "/resource1" "success"
    audit_log "action2" "user:user-1:op" "/resource2" "success"
    audit_log "action3" "agent:agent-2:op" "/resource3" "success"

    run audit_query --actor "agent-*" --format jsonl
    local count=$(echo "$output" | grep -c "agent-")
    [[ $count -eq 2 ]]
}

@test "audit_query: filters by action" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "file_read" "actor1" "/resource1" "success"
    audit_log "file_write" "actor2" "/resource2" "success"
    audit_log "file_read" "actor3" "/resource3" "success"

    run audit_query --action "file_read" --format jsonl
    local count=$(echo "$output" | grep -c "file_read")
    [[ $count -eq 2 ]]
}

@test "audit_query: filters by action with OR" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "file_read" "actor1" "/resource1" "success"
    audit_log "file_write" "actor2" "/resource2" "success"
    audit_log "file_delete" "actor3" "/resource3" "success"

    run audit_query --action "file_read|file_write" --format jsonl
    local count=$(echo "$output" | wc -l)
    [[ $count -eq 2 ]]
}

@test "audit_query: filters by result" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "action1" "actor1" "/resource1" "success"
    audit_log "action2" "actor2" "/resource2" "failure"
    audit_log "action3" "actor3" "/resource3" "success"

    run audit_query --result "failure" --format jsonl
    local count=$(echo "$output" | wc -l)
    [[ $count -eq 1 ]]
}

@test "audit_query: respects limit" {
    audit_init --output "$TEST_AUDIT_LOG"
    for i in {1..10}; do
        audit_log "action$i" "actor$i" "/resource$i" "success"
    done

    run audit_query --limit 5 --format jsonl
    local count=$(echo "$output" | wc -l)
    [[ $count -eq 5 ]]
}

@test "audit_query: outputs JSON array format" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "action1" "actor1" "/resource1" "success"
    audit_log "action2" "actor2" "/resource2" "success"

    run audit_query --format json
    [[ "$output" =~ ^\[ ]]
    [[ "$output" =~ \]$ ]]
}

@test "audit_query: outputs table format" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "file_write" "agent-123" "/tmp/test.txt" "success"

    run audit_query --format table
    [[ "$output" =~ "ID" ]]
    [[ "$output" =~ "TIMESTAMP" ]]
    [[ "$output" =~ "ACTOR" ]]
}

# =============================================================================
# CATEGORY 6: EXPORT
# =============================================================================

@test "audit_export: exports to CSV" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "file_write" "agent:agent-1:op" "/tmp/test.txt" "success"

    run audit_export "${TEST_TMPDIR}/export.csv" --format csv
    [[ "$status" -eq 0 ]]
    [[ -f "${TEST_TMPDIR}/export.csv" ]]

    # Check CSV header
    local header=$(head -1 "${TEST_TMPDIR}/export.csv")
    [[ "$header" =~ "id,timestamp,action" ]]
}

@test "audit_export: exports to JSON" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "test" "actor" "/resource" "success"

    run audit_export "${TEST_TMPDIR}/export.json" --format json
    [[ "$status" -eq 0 ]]
    [[ -f "${TEST_TMPDIR}/export.json" ]]

    local content=$(<"${TEST_TMPDIR}/export.json")
    [[ "$content" =~ ^\[ ]]
}

@test "audit_export: exports to JSONL" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "test1" "actor1" "/resource1" "success"
    audit_log "test2" "actor2" "/resource2" "success"

    run audit_export "${TEST_TMPDIR}/export.jsonl" --format jsonl
    [[ "$status" -eq 0 ]]

    local count=$(wc -l < "${TEST_TMPDIR}/export.jsonl")
    [[ $count -eq 2 ]]
}

# =============================================================================
# CATEGORY 7: ROTATION
# =============================================================================

@test "audit_rotate: creates archived file" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "test" "actor" "/resource" "success"

    run audit_rotate --archive-dir "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    # Original log should be gone
    [[ ! -f "$TEST_AUDIT_LOG" ]]

    # Archive should exist
    local archive_count=$(find "$TEST_TMPDIR" -name "audit_*.jsonl" | wc -l)
    [[ $archive_count -ge 1 ]]
}

@test "audit_rotate: resets chain hash" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "test" "actor" "/resource" "success"

    audit_rotate --archive-dir "$TEST_TMPDIR"

    # Log new entry - should have genesis chain hash
    audit_log "new_entry" "actor" "/resource" "success"

    local chain=$(grep -o '"chain_hash":"[^"]*"' "$TEST_AUDIT_LOG" | cut -d'"' -f4)
    [[ "$chain" == "genesis" ]]
}

# =============================================================================
# CATEGORY 8: RETENTION
# =============================================================================

@test "audit_retention: reports configuration" {
    audit_init --output "$TEST_AUDIT_LOG" --retention 30

    run audit_retention --days 90 --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ \"retention_days\":90 ]]
    [[ "$output" =~ \"dry_run\":true ]]
}

# =============================================================================
# CATEGORY 9: STATISTICS
# =============================================================================

@test "audit_stats: counts entries correctly" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "action1" "actor1" "/resource1" "success"
    audit_log "action2" "actor2" "/resource2" "failure"
    audit_log "action3" "actor3" "/resource3" "success"

    run audit_stats
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ \"total\":3 ]]
    [[ "$output" =~ \"success\":2 ]]
    [[ "$output" =~ \"failure\":1 ]]
}

@test "audit_stats: counts unique actors and actions" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "action1" "agent:actor1:op" "/resource1" "success"
    audit_log "action1" "agent:actor2:op" "/resource2" "success"
    audit_log "action2" "agent:actor1:op" "/resource3" "success"

    run audit_stats
    [[ "$output" =~ \"unique_actions\":2 ]]
    [[ "$output" =~ \"unique_actors\":2 ]]
}

# =============================================================================
# CATEGORY 10: ALERTING
# =============================================================================

@test "audit_alert: registers alert configuration" {
    audit_init --output "$TEST_AUDIT_LOG"

    # Don't use run - we need to preserve array state
    audit_alert "failure_rate" "http://example.com/webhook" --threshold 5
    local status=$?
    [[ "$status" -eq 0 ]]
    [[ ${#_AUDIT_ALERTS[@]} -eq 1 ]]
}

@test "audit_alert: requires condition and webhook" {
    audit_init --output "$TEST_AUDIT_LOG"

    run audit_alert "" "http://example.com/webhook"
    [[ "$status" -eq 1 ]]

    run audit_alert "failure_rate" ""
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 11: CONVENIENCE FUNCTIONS
# =============================================================================

@test "audit_file_op: logs file operation" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_file_op "write" "agent-1" "/tmp/test.txt" "success" "bytes=1024"

    local entry=$(cat "$TEST_AUDIT_LOG")
    [[ "$entry" =~ \"action\":\"file_write\" ]]
    [[ "$entry" =~ \"type\":\"file\" ]]
}

@test "audit_api_call: logs API call" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_api_call "POST" "agent-1" "/api/users" "success" "status_code=201"

    local entry=$(cat "$TEST_AUDIT_LOG")
    [[ "$entry" =~ \"action\":\"api_POST\" ]]
    [[ "$entry" =~ \"type\":\"api\" ]]
}

@test "audit_config_change: logs configuration change" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_config_change "admin-1" "log_level" "success" "old_value=info" "new_value=debug"

    local entry=$(cat "$TEST_AUDIT_LOG")
    [[ "$entry" =~ \"action\":\"config_change\" ]]
    [[ "$entry" =~ \"old_value\":\"info\" ]]
    [[ "$entry" =~ \"new_value\":\"debug\" ]]
}

@test "audit_auth: logs authentication event" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_auth "login" "user-123" "success" "method=password"

    local entry=$(cat "$TEST_AUDIT_LOG")
    [[ "$entry" =~ \"action\":\"auth_login\" ]]
    [[ "$entry" =~ \"method\":\"password\" ]]
}

# =============================================================================
# CATEGORY 12: EDGE CASES AND SECURITY
# =============================================================================

@test "audit_log: escapes special characters in values" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "test" "actor" "/path/with\"quotes" "success" 'data=value with "quotes"'

    # Should not break JSON parsing
    local entry=$(cat "$TEST_AUDIT_LOG")
    # Basic JSON validity check
    [[ "$entry" =~ ^\{ ]]
    [[ "$entry" =~ \}$ ]]
}

@test "audit_log: handles empty details" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "test" "actor" "/resource" "success"

    local entry=$(cat "$TEST_AUDIT_LOG")
    [[ "$entry" =~ \"details\":\{\} ]]
}

@test "audit_log: handles simple actor format" {
    audit_init --output "$TEST_AUDIT_LOG"
    audit_log "test" "simple-actor-id" "/resource" "success"

    local entry=$(cat "$TEST_AUDIT_LOG")
    [[ "$entry" =~ \"id\":\"simple-actor-id\" ]]
    [[ "$entry" =~ \"type\":\"unknown\" ]]
}

@test "audit_query: handles empty log file" {
    audit_init --output "$TEST_AUDIT_LOG"
    touch "$TEST_AUDIT_LOG"

    run audit_query --format json
    [[ "$status" -eq 0 ]]
    [[ "$output" == "[]" ]]
}

@test "audit_verify: handles missing log file" {
    run audit_verify "/nonexistent/path/audit.jsonl"
    [[ "$status" -eq 1 ]]
}

@test "audit_sign: handles missing log file" {
    run audit_sign "/nonexistent/path/audit.jsonl" --key "$TEST_HMAC_KEY"
    [[ "$status" -eq 1 ]]
}

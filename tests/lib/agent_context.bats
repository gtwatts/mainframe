#!/usr/bin/env bats
# Test suite for lib/agent_context.sh - Persistent Context Object Pattern
# Tests: session management, data operations, snapshots, import/export

setup() {
    load '../test_helper.bash'
    source_lib agent_context
    
    # Use isolated test directories
    export MAINFRAME_CONTEXT_DIR="${BATS_TEST_TMPDIR}/context"
    mkdir -p "$MAINFRAME_CONTEXT_DIR"
}

teardown() {
    # Cleanup is handled by BATS_TEST_TMPDIR automatic cleanup
    unset _CTX_SESSION_ID 2>/dev/null || true
}

# =============================================================================
# SESSION LIFECYCLE TESTS
# =============================================================================

@test "ctx_init: creates a new context session" {
    ctx_init "test_session"
    [[ -d "$MAINFRAME_CONTEXT_DIR/test_session" ]]
}

@test "ctx_init: creates required files" {
    ctx_init "test_session"
    [[ -f "$MAINFRAME_CONTEXT_DIR/test_session/meta.json" ]]
    [[ -f "$MAINFRAME_CONTEXT_DIR/test_session/current.json" ]]
}

@test "ctx_init: stores session name in meta" {
    ctx_init "my_named_session"
    local meta
    meta=$(<"$MAINFRAME_CONTEXT_DIR/my_named_session/meta.json")
    assert_contains "$meta" "my_named_session"
}

@test "ctx_session: returns current session ID" {
    ctx_init "test_session"
    [[ "$(ctx_session)" == "test_session" ]]
}

@test "ctx_exists: returns true for existing session" {
    ctx_init "test_session"
    run ctx_exists "test_session"
    assert_success
}

@test "ctx_exists: returns false for non-existent session" {
    assert_failure "ctx_exists nonexistent_session"
}

@test "ctx_close: closes active session" {
    ctx_init "test_session"
    ctx_close
    [[ -z "$(ctx_session)" ]]
}

@test "ctx_load: loads existing session" {
    ctx_init "test_session"
    ctx_set "key1" "value1"
    ctx_close
    ctx_load "test_session"
    [[ "$(ctx_session)" == "test_session" ]]
}

# =============================================================================
# DATA OPERATIONS TESTS
# =============================================================================

@test "ctx_set: stores a key-value pair" {
    ctx_init "test_session"
    ctx_set "key1" "value1"
    # Reload to verify persistence
    ctx_load "test_session"
    [[ "$(ctx_get "key1")" == "value1" ]]
}

@test "ctx_set: updates existing key" {
    ctx_init "test_session"
    ctx_set "key1" "value1"
    ctx_set "key1" "value2"
    ctx_load "test_session"
    [[ "$(ctx_get "key1")" == "value2" ]]
}

@test "ctx_get: returns default for missing key" {
    ctx_init "test_session"
    [[ "$(ctx_get "missing_key" "default_value")" == "default_value" ]]
}

@test "ctx_get: returns empty string for missing key without default" {
    ctx_init "test_session"
    [[ -z "$(ctx_get "missing_key")" ]]
}

@test "ctx_delete: removes a key" {
    ctx_init "test_session"
    ctx_set "key1" "value1"
    ctx_delete "key1"
    ctx_load "test_session"
    [[ -z "$(ctx_get "key1")" ]]
}

@test "ctx_get returns 0 for existing key and 1 for missing" {
    ctx_init "test_session"
    ctx_set "key1" "value1"
    run ctx_get "key1"
    assert_success
    run ctx_get "nonexistent"
    assert_failure
}

@test "ctx_clear: removes all data" {
    ctx_init "test_session"
    ctx_set "key1" "value1"
    ctx_set "key2" "value2"
    ctx_clear
    ctx_load "test_session"
    [[ -z "$(ctx_get "key1")" ]]
    [[ -z "$(ctx_get "key2")" ]]
}

@test "ctx_list_keys: lists all keys" {
    ctx_init "test_session"
    ctx_set "key1" "value1"
    ctx_set "key2" "value2"
    local keys
    keys=$(ctx_list_keys)
    assert_contains "$keys" "key1"
    assert_contains "$keys" "key2"
}

# =============================================================================
# SNAPSHOT TESTS
# =============================================================================

@test "ctx_snapshot: creates a snapshot" {
    ctx_init "test_session"
    ctx_set "key1" "value1"
    local snapshot
    snapshot=$(ctx_snapshot "test_snapshot")
    [[ -n "$snapshot" ]]
    [[ -f "$MAINFRAME_CONTEXT_DIR/test_session/snapshots/$snapshot" ]]
}

@test "ctx_snapshots: lists created snapshots" {
    ctx_init "test_session"
    ctx_set "key1" "value1"
    ctx_snapshot "snap1" >/dev/null
    ctx_snapshot "snap2" >/dev/null
    local snaps
    snaps=$(ctx_snapshots)
    [[ $(echo "$snaps" | wc -l) -ge 2 ]]
}

@test "ctx_restore: restores from snapshot" {
    ctx_init "test_session"
    ctx_set "key1" "value1"
    local snapshot
    snapshot=$(ctx_snapshot "test_snapshot")
    ctx_set "key1" "value2"
    ctx_restore "$snapshot"
    ctx_load "test_session"
    [[ "$(ctx_get "key1")" == "value1" ]]
}

# =============================================================================
# METADATA TESTS
# =============================================================================

@test "ctx_set_meta: stores metadata" {
    ctx_init "test_session"
    ctx_set_meta "author" "test_user"
    [[ "$(ctx_get_meta "author")" == "test_user" ]]
}

@test "ctx_get_meta: returns default for missing metadata" {
    ctx_init "test_session"
    [[ "$(ctx_get_meta "missing" "default")" == "default" ]]
}

@test "ctx_version: returns version info" {
    ctx_init "test_session"
    local version
    version=$(ctx_version)
    [[ -n "$version" ]]
}

# =============================================================================
# IMPORT/EXPORT TESTS
# =============================================================================

@test "ctx_export: exports session to file" {
    ctx_init "test_session"
    ctx_set "key1" "value1"
    local export_file="${BATS_TEST_TMPDIR}/export.json"
    ctx_export "$export_file"
    [[ -f "$export_file" ]]
    assert_contains "$(<"$export_file")" "key1"
}

@test "ctx_import: imports session from file" {
    ctx_init "test_session"
    ctx_set "key1" "value1"
    local export_file="${BATS_TEST_TMPDIR}/export.json"
    ctx_export "$export_file"
    
    ctx_init "new_session"
    ctx_import "$export_file"
    [[ "$(ctx_get "key1")" == "value1" ]]
}

@test "ctx_json: returns valid JSON" {
    ctx_init "test_session"
    ctx_set "key1" "value1"
    local json
    json=$(ctx_json)
    assert_contains "$json" "key1"
    assert_contains "$json" "value1"
}

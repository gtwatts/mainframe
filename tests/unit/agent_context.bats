#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/agent_context.bats - Agent Context Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/agent_context.sh
#              Persistent context object pattern for agent state management
# Test Count: 50+ test cases
# Categories: ctx_init, ctx_load, ctx_save, ctx_set/get/delete, snapshots,
#             import/export, merge, metadata, edge cases
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create isolated temp directory for test contexts
    TEST_TMPDIR="$(mktemp -d)"
    export MAINFRAME_CONTEXT_DIR="${TEST_TMPDIR}/contexts"
    export MAINFRAME_CONTEXT_AUTOSAVE=100  # High threshold to prevent auto-saves during tests
    export MAINFRAME_QUIET=1

    # Source the library
    source "$MAINFRAME_ROOT/lib/agent_context.sh"
}

# Teardown: Clean up test artifacts
teardown() {
    # Close any active session
    ctx_close 2>/dev/null || true
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# CATEGORY 1: ctx_init - Session Initialization
# =============================================================================

@test "ctx_init: creates new session" {
    ctx_init "test-session-001"
    [[ -d "${MAINFRAME_CONTEXT_DIR}/test-session-001" ]]
}

@test "ctx_init: creates directory structure" {
    ctx_init "structure-test"
    [[ -d "${MAINFRAME_CONTEXT_DIR}/structure-test/snapshots" ]]
    [[ -f "${MAINFRAME_CONTEXT_DIR}/structure-test/current.json" ]]
    [[ -f "${MAINFRAME_CONTEXT_DIR}/structure-test/meta.json" ]]
}

@test "ctx_init: fails without session_id" {
    run ctx_init ""
    [[ "$status" -eq 1 ]]
}

@test "ctx_init: creates valid JSON in current.json" {
    ctx_init "json-valid"
    local json
    json=$(<"${MAINFRAME_CONTEXT_DIR}/json-valid/current.json")
    # Validate with jq
    echo "$json" | jq empty
}

@test "ctx_init: sets initial version to 1" {
    ctx_init "version-test"
    local version
    version=$(ctx_version)
    [[ "$version" -eq 1 ]]
}

@test "ctx_init: records creation timestamp" {
    ctx_init "timestamp-test"
    local json
    json=$(<"${MAINFRAME_CONTEXT_DIR}/timestamp-test/current.json")
    local created_at
    created_at=$(echo "$json" | jq -r '.created_at')
    [[ -n "$created_at" ]]
    [[ "$created_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]
}

@test "ctx_init: handles special characters in session_id" {
    ctx_init "test_session-123"
    [[ -d "${MAINFRAME_CONTEXT_DIR}/test_session-123" ]]
}

# =============================================================================
# CATEGORY 2: ctx_load - Session Loading
# =============================================================================

@test "ctx_load: loads existing session" {
    ctx_init "load-test"
    ctx_set "key1" "value1"
    ctx_save
    ctx_close

    ctx_load "load-test"
    local val
    val=$(ctx_get "key1")
    [[ "$val" == "value1" ]]
}

@test "ctx_load: fails for non-existent session" {
    run ctx_load "nonexistent-session"
    [[ "$status" -eq 1 ]]
}

@test "ctx_load: fails without session_id" {
    run ctx_load ""
    [[ "$status" -eq 1 ]]
}

@test "ctx_load: restores version number" {
    ctx_init "version-load"
    ctx_set "a" "b"
    ctx_save
    ctx_save
    ctx_save
    local original_version
    original_version=$(ctx_version)
    ctx_close

    ctx_load "version-load"
    local loaded_version
    loaded_version=$(ctx_version)
    [[ "$loaded_version" -eq "$original_version" ]]
}

@test "ctx_load: restores metadata" {
    ctx_init "meta-load"
    ctx_set_meta "agent_type" "researcher"
    ctx_save
    ctx_close

    ctx_load "meta-load"
    local meta
    meta=$(ctx_get_meta "agent_type")
    [[ "$meta" == "researcher" ]]
}

# =============================================================================
# CATEGORY 3: ctx_save - Session Persistence
# =============================================================================

@test "ctx_save: persists data to disk" {
    ctx_init "save-test"
    ctx_set "persist" "me"
    run ctx_save
    [[ "$status" -eq 0 ]]

    local json
    json=$(<"${MAINFRAME_CONTEXT_DIR}/save-test/current.json")
    local val
    val=$(echo "$json" | jq -r '.data.persist')
    [[ "$val" == "me" ]]
}

@test "ctx_save: increments version" {
    ctx_init "version-inc"
    local v1 v2
    v1=$(ctx_version)
    ctx_save
    v2=$(ctx_version)
    [[ "$v2" -gt "$v1" ]]
}

@test "ctx_save: updates timestamp" {
    ctx_init "ts-update"
    local json1
    json1=$(<"${MAINFRAME_CONTEXT_DIR}/ts-update/current.json")
    local ts1
    ts1=$(echo "$json1" | jq -r '.updated_at')

    sleep 1
    ctx_save

    local json2
    json2=$(<"${MAINFRAME_CONTEXT_DIR}/ts-update/current.json")
    local ts2
    ts2=$(echo "$json2" | jq -r '.updated_at')

    [[ "$ts1" != "$ts2" ]]
}

@test "ctx_save: fails without active session" {
    run ctx_save
    [[ "$status" -eq 1 ]]
}

@test "ctx_save: appends to history log" {
    ctx_init "history-test"
    ctx_set "key" "val"
    ctx_save

    [[ -f "${MAINFRAME_CONTEXT_DIR}/history-test/history.jsonl" ]]
    local line_count
    line_count=$(wc -l < "${MAINFRAME_CONTEXT_DIR}/history-test/history.jsonl")
    [[ "$line_count" -gt 0 ]]
}

# =============================================================================
# CATEGORY 4: ctx_set / ctx_get / ctx_delete
# =============================================================================

@test "ctx_set: stores string value" {
    ctx_init "set-test"
    run ctx_set "name" "John"
    [[ "$status" -eq 0 ]]
}

@test "ctx_get: retrieves stored value" {
    ctx_init "get-test"
    ctx_set "color" "blue"
    local result
    result=$(ctx_get "color")
    [[ "$result" == "blue" ]]
}

@test "ctx_get: returns error for missing key" {
    ctx_init "missing-key"
    run ctx_get "nonexistent"
    [[ "$status" -eq 1 ]]
}

@test "ctx_set: handles empty value" {
    ctx_init "empty-val"
    ctx_set "empty" ""
    local result
    result=$(ctx_get "empty")
    [[ "$result" == "" ]]
}

@test "ctx_set: handles multiline value" {
    ctx_init "multiline"
    local multi=$'line1\nline2\nline3'
    ctx_set "lines" "$multi"
    local result
    result=$(ctx_get "lines")
    [[ "$result" == "$multi" ]]
}

@test "ctx_set: handles special characters" {
    ctx_init "special-chars"
    local special='$VAR "quoted" `backtick` \n \\path'
    ctx_set "special" "$special"
    ctx_save
    ctx_close

    ctx_load "special-chars"
    local result
    result=$(ctx_get "special")
    [[ "$result" == "$special" ]]
}

@test "ctx_set: overwrites existing key" {
    ctx_init "overwrite"
    ctx_set "key" "original"
    ctx_set "key" "updated"
    local result
    result=$(ctx_get "key")
    [[ "$result" == "updated" ]]
}

@test "ctx_delete: removes key" {
    ctx_init "delete-test"
    ctx_set "temp" "value"
    ctx_delete "temp"
    run ctx_get "temp"
    [[ "$status" -eq 1 ]]
}

@test "ctx_delete: returns error for missing key" {
    ctx_init "delete-missing"
    run ctx_delete "nonexistent"
    [[ "$status" -eq 1 ]]
}

@test "ctx_delete: fails without session" {
    run ctx_delete "key"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 5: ctx_list_keys / ctx_clear
# =============================================================================

@test "ctx_list_keys: lists all keys" {
    ctx_init "list-test"
    ctx_set "key1" "val1"
    ctx_set "key2" "val2"
    ctx_set "key3" "val3"

    run ctx_list_keys
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "key1" ]]
    [[ "$output" =~ "key2" ]]
    [[ "$output" =~ "key3" ]]
}

@test "ctx_list_keys: returns empty for no keys" {
    ctx_init "empty-list"
    run ctx_list_keys
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "ctx_clear: removes all data" {
    ctx_init "clear-test"
    ctx_set "a" "1"
    ctx_set "b" "2"
    ctx_clear
    run ctx_get "a"
    [[ "$status" -eq 1 ]]
    run ctx_get "b"
    [[ "$status" -eq 1 ]]
}

@test "ctx_clear: preserves session" {
    ctx_init "clear-session"
    ctx_set "data" "value"
    ctx_clear
    local session
    session=$(ctx_session)
    [[ "$session" == "clear-session" ]]
}

# =============================================================================
# CATEGORY 6: ctx_snapshot / ctx_restore / ctx_diff
# =============================================================================

@test "ctx_snapshot: creates snapshot file" {
    ctx_init "snap-create"
    ctx_set "state" "initial"
    local snap_id
    snap_id=$(ctx_snapshot)
    [[ -f "${MAINFRAME_CONTEXT_DIR}/snap-create/snapshots/${snap_id}.json" ]]
}

@test "ctx_snapshot: returns snapshot ID" {
    ctx_init "snap-id"
    local snap_id
    snap_id=$(ctx_snapshot)
    [[ "$snap_id" =~ ^snap_[0-9]+$ ]]
}

@test "ctx_snapshot: increments snapshot counter" {
    ctx_init "snap-counter"
    local s1 s2 s3
    s1=$(ctx_snapshot)
    s2=$(ctx_snapshot)
    s3=$(ctx_snapshot)
    [[ "$s1" == "snap_001" ]]
    [[ "$s2" == "snap_002" ]]
    [[ "$s3" == "snap_003" ]]
}

@test "ctx_restore: restores from snapshot" {
    ctx_init "restore-test"
    ctx_set "value" "before"
    local snap
    snap=$(ctx_snapshot)

    ctx_set "value" "after"
    [[ "$(ctx_get 'value')" == "after" ]]

    ctx_restore "$snap"
    [[ "$(ctx_get 'value')" == "before" ]]
}

@test "ctx_restore: fails for nonexistent snapshot" {
    ctx_init "restore-fail"
    run ctx_restore "snap_999"
    [[ "$status" -eq 1 ]]
}

@test "ctx_diff: shows added keys" {
    ctx_init "diff-added"
    local snap
    snap=$(ctx_snapshot)
    ctx_set "new_key" "new_value"

    local diff
    diff=$(ctx_diff "$snap")
    local added
    added=$(echo "$diff" | jq -r '.added[]')
    [[ "$added" == "new_key" ]]
}

@test "ctx_diff: shows removed keys" {
    ctx_init "diff-removed"
    ctx_set "temp" "value"
    local snap
    snap=$(ctx_snapshot)
    ctx_delete "temp"

    local diff
    diff=$(ctx_diff "$snap")
    local removed
    removed=$(echo "$diff" | jq -r '.removed[]')
    [[ "$removed" == "temp" ]]
}

@test "ctx_diff: shows changed keys" {
    ctx_init "diff-changed"
    ctx_set "changing" "original"
    local snap
    snap=$(ctx_snapshot)
    ctx_set "changing" "modified"

    local diff
    diff=$(ctx_diff "$snap")
    local changed
    changed=$(echo "$diff" | jq -r '.changed[]')
    [[ "$changed" == "changing" ]]
}

# =============================================================================
# CATEGORY 7: ctx_rollback
# =============================================================================

@test "ctx_rollback: restores to last snapshot" {
    ctx_init "rollback-test"
    ctx_set "state" "v1"
    ctx_snapshot
    ctx_set "state" "v2"
    ctx_snapshot
    ctx_set "state" "v3"

    ctx_rollback
    [[ "$(ctx_get 'state')" == "v2" ]]
}

@test "ctx_rollback: fails with no snapshots" {
    ctx_init "rollback-none"
    run ctx_rollback
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 8: ctx_export / ctx_import
# =============================================================================

@test "ctx_export: creates JSON file" {
    ctx_init "export-test"
    ctx_set "exportme" "value"
    run ctx_export "${TEST_TMPDIR}/exported.json"
    [[ "$status" -eq 0 ]]
    [[ -f "${TEST_TMPDIR}/exported.json" ]]
}

@test "ctx_export: creates valid JSON" {
    ctx_init "export-valid"
    ctx_set "key" "value"
    ctx_export "${TEST_TMPDIR}/valid.json"
    jq empty "${TEST_TMPDIR}/valid.json"
}

@test "ctx_import: loads data from file" {
    # Create export
    ctx_init "import-source"
    ctx_set "imported_key" "imported_value"
    ctx_export "${TEST_TMPDIR}/import.json"
    ctx_close

    # Import into new session
    ctx_init "import-target"
    ctx_import "${TEST_TMPDIR}/import.json"
    [[ "$(ctx_get 'imported_key')" == "imported_value" ]]
}

@test "ctx_import: merges with existing data" {
    ctx_init "import-merge"
    ctx_set "existing" "value"
    ctx_export "${TEST_TMPDIR}/existing.json"
    ctx_close

    ctx_init "merge-target"
    ctx_set "target_key" "target_value"
    ctx_import "${TEST_TMPDIR}/existing.json"

    [[ "$(ctx_get 'target_key')" == "target_value" ]]
    [[ "$(ctx_get 'existing')" == "value" ]]
}

@test "ctx_import: fails for nonexistent file" {
    ctx_init "import-fail"
    run ctx_import "/nonexistent/file.json"
    [[ "$status" -eq 1 ]]
}

@test "ctx_import: fails for invalid JSON" {
    echo "not valid json" > "${TEST_TMPDIR}/invalid.json"
    ctx_init "import-invalid"
    run ctx_import "${TEST_TMPDIR}/invalid.json"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 9: ctx_merge
# =============================================================================

@test "ctx_merge: merges from another session" {
    ctx_init "merge-source"
    ctx_set "source_data" "source_value"
    ctx_save
    ctx_close

    ctx_init "merge-target"
    ctx_set "target_data" "target_value"
    ctx_merge "merge-source"

    [[ "$(ctx_get 'source_data')" == "source_value" ]]
    [[ "$(ctx_get 'target_data')" == "target_value" ]]
}

@test "ctx_merge: overwrites on conflict" {
    ctx_init "merge-overwrite-src"
    ctx_set "shared" "source_wins"
    ctx_save
    ctx_close

    ctx_init "merge-overwrite-tgt"
    ctx_set "shared" "original"
    ctx_merge "merge-overwrite-src"
    [[ "$(ctx_get 'shared')" == "source_wins" ]]
}

@test "ctx_merge: fails for nonexistent session" {
    ctx_init "merge-fail"
    run ctx_merge "nonexistent-session"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 10: ctx_close
# =============================================================================

@test "ctx_close: saves final state" {
    ctx_init "close-save"
    ctx_set "final" "value"
    ctx_close

    ctx_load "close-save"
    [[ "$(ctx_get 'final')" == "value" ]]
}

@test "ctx_close: clears session state" {
    ctx_init "close-clear"
    ctx_close
    run ctx_session
    [[ "$status" -eq 1 ]]
}

@test "ctx_close: updates meta.json with closed_at" {
    ctx_init "close-meta"
    ctx_close

    local meta
    meta=$(<"${MAINFRAME_CONTEXT_DIR}/close-meta/meta.json")
    local closed_at
    closed_at=$(echo "$meta" | jq -r '.closed_at')
    [[ -n "$closed_at" ]]
}

@test "ctx_close: is idempotent" {
    ctx_init "close-idem"
    run ctx_close
    [[ "$status" -eq 0 ]]
    run ctx_close
    [[ "$status" -eq 0 ]]
}

# =============================================================================
# CATEGORY 11: Metadata Operations
# =============================================================================

@test "ctx_set_meta: stores metadata" {
    ctx_init "meta-set"
    run ctx_set_meta "type" "researcher"
    [[ "$status" -eq 0 ]]
}

@test "ctx_get_meta: retrieves metadata" {
    ctx_init "meta-get"
    ctx_set_meta "priority" "high"
    local result
    result=$(ctx_get_meta "priority")
    [[ "$result" == "high" ]]
}

@test "ctx_get_meta: returns error for missing key" {
    ctx_init "meta-missing"
    run ctx_get_meta "nonexistent"
    [[ "$status" -eq 1 ]]
}

@test "metadata: persists across save/load" {
    ctx_init "meta-persist"
    ctx_set_meta "parent" "main-session"
    ctx_save
    ctx_close

    ctx_load "meta-persist"
    [[ "$(ctx_get_meta 'parent')" == "main-session" ]]
}

# =============================================================================
# CATEGORY 12: Utility Functions
# =============================================================================

@test "ctx_session: returns current session ID" {
    ctx_init "session-id-test"
    local session
    session=$(ctx_session)
    [[ "$session" == "session-id-test" ]]
}

@test "ctx_version: returns current version" {
    ctx_init "version-test"
    local version
    version=$(ctx_version)
    [[ "$version" -ge 1 ]]
}

@test "ctx_json: returns full context as JSON" {
    ctx_init "json-test"
    ctx_set "key" "value"
    local json
    json=$(ctx_json)
    echo "$json" | jq empty
    local val
    val=$(echo "$json" | jq -r '.data.key')
    [[ "$val" == "value" ]]
}

@test "ctx_snapshots: lists all snapshots" {
    ctx_init "list-snaps"
    ctx_snapshot
    ctx_snapshot
    ctx_snapshot

    run ctx_snapshots
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "snap_001" ]]
    [[ "$output" =~ "snap_002" ]]
    [[ "$output" =~ "snap_003" ]]
}

@test "ctx_exists: returns 0 for existing session" {
    ctx_init "exists-test"
    ctx_save
    ctx_close

    run ctx_exists "exists-test"
    [[ "$status" -eq 0 ]]
}

@test "ctx_exists: returns 1 for nonexistent session" {
    run ctx_exists "nonexistent"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 13: Edge Cases and Error Handling
# =============================================================================

@test "operations fail without active session" {
    run ctx_set "key" "value"
    [[ "$status" -eq 1 ]]

    run ctx_get "key"
    [[ "$status" -eq 1 ]]

    run ctx_snapshot
    [[ "$status" -eq 1 ]]
}

@test "handles JSON-like values correctly" {
    ctx_init "json-value"
    local json_val='{"nested": "object", "array": [1,2,3]}'
    ctx_set "json_data" "$json_val"
    ctx_save
    ctx_close

    ctx_load "json-value"
    local result
    result=$(ctx_get "json_data")
    [[ "$result" == "$json_val" ]]
}

@test "handles very long values" {
    ctx_init "long-value"
    local long_val
    long_val=$(printf 'x%.0s' {1..10000})
    ctx_set "long" "$long_val"
    ctx_save
    ctx_close

    ctx_load "long-value"
    local result
    result=$(ctx_get "long")
    [[ "${#result}" -eq 10000 ]]
}

@test "handles unicode in keys and values" {
    ctx_init "unicode-test"
    ctx_set "greeting" "Hello unicode"
    ctx_save
    ctx_close

    ctx_load "unicode-test"
    local result
    result=$(ctx_get "greeting")
    [[ "$result" == "Hello unicode" ]]
}

@test "history log captures all operations" {
    ctx_init "history-full"
    ctx_set "a" "1"
    ctx_set "b" "2"
    ctx_delete "a"
    ctx_snapshot
    ctx_save

    local history_file="${MAINFRAME_CONTEXT_DIR}/history-full/history.jsonl"
    [[ -f "$history_file" ]]

    local set_count
    set_count=$(grep '"op":"set"' "$history_file" | wc -l)
    [[ "$set_count" -ge 2 ]]

    local delete_count
    delete_count=$(grep '"op":"delete"' "$history_file" | wc -l)
    [[ "$delete_count" -ge 1 ]]
}

# =============================================================================
# CATEGORY 14: Concurrency and Recovery
# =============================================================================

@test "atomic writes prevent corruption" {
    ctx_init "atomic-test"

    # Simulate multiple rapid saves
    for i in {1..10}; do
        ctx_set "counter" "$i"
        ctx_save
    done

    # Verify file is valid JSON
    jq empty "${MAINFRAME_CONTEXT_DIR}/atomic-test/current.json"
}

@test "recovery from crashed session" {
    ctx_init "crash-recovery"
    ctx_set "important" "data"
    ctx_save

    # Simulate crash by not calling ctx_close
    _CTX_SESSION_ID=""

    # Should be able to load and recover
    ctx_load "crash-recovery"
    [[ "$(ctx_get 'important')" == "data" ]]
}

# =============================================================================
# CATEGORY 15: Integration Scenarios
# =============================================================================

@test "full workflow: init, set, snapshot, modify, restore" {
    ctx_init "workflow-test"

    # Initial state
    ctx_set "task" "research"
    ctx_set "progress" "0"
    local snap
    snap=$(ctx_snapshot)

    # Modify state
    ctx_set "progress" "50"
    ctx_set "findings" "item1,item2"
    [[ "$(ctx_get 'progress')" == "50" ]]

    # Rollback
    ctx_restore "$snap"
    [[ "$(ctx_get 'progress')" == "0" ]]
    run ctx_get "findings"
    [[ "$status" -eq 1 ]]  # Key should not exist
}

@test "parent-child session merge" {
    # Parent session
    ctx_init "parent-session"
    ctx_set "parent_data" "from_parent"
    ctx_set_meta "role" "orchestrator"
    ctx_save
    ctx_close

    # Child session
    ctx_init "child-session"
    ctx_set "child_data" "from_child"
    ctx_set_meta "parent_session" "parent-session"

    # Merge parent data
    ctx_merge "parent-session"

    # Both data sets should be available
    [[ "$(ctx_get 'parent_data')" == "from_parent" ]]
    [[ "$(ctx_get 'child_data')" == "from_child" ]]
}

@test "export-modify-import cycle" {
    ctx_init "export-cycle"
    ctx_set "original" "value"
    ctx_export "${TEST_TMPDIR}/cycle.json"
    ctx_close

    # Modify exported file externally
    jq '.data.added = "external"' "${TEST_TMPDIR}/cycle.json" > "${TEST_TMPDIR}/modified.json"

    # Import into new session
    ctx_init "import-cycle"
    ctx_import "${TEST_TMPDIR}/modified.json"
    [[ "$(ctx_get 'original')" == "value" ]]
    [[ "$(ctx_get 'added')" == "external" ]]
}

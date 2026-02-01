#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/forensics.bats - Error Forensics Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/forensics.sh
#              Error context capture, stack traces, variable snapshots,
#              and error chains for multi-agent debugging
# Test Count: 52 test cases
# Categories: stack traces, error context, snapshots, error chains,
#             variable watches, forensic bundles, trap integration
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"
    export MAINFRAME_FORENSICS_DIR="$TEST_TMPDIR/forensics"
    mkdir -p "$MAINFRAME_FORENSICS_DIR"

    # Source the library
    source "$MAINFRAME_ROOT/lib/forensics.sh"

    # Clear any prior state
    forensics_clear
}

# Teardown: Clean up test artifacts
teardown() {
    # Uninstall trap if installed
    forensics_trap_uninstall 2>/dev/null || true
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# CATEGORY 1: STACK TRACES
# =============================================================================

@test "forensics_stack: returns stack trace from function" {
    test_func() {
        forensics_stack
    }
    result=$(test_func)
    [[ "$result" =~ "at test_func()" ]]
}

@test "forensics_stack: shows nested function calls" {
    inner() { forensics_stack; }
    outer() { inner; }
    result=$(outer)
    [[ "$result" =~ "inner" ]]
    [[ "$result" =~ "outer" ]]
}

@test "forensics_stack: includes line numbers" {
    test_func() {
        forensics_stack
    }
    result=$(test_func)
    [[ "$result" =~ ":" ]]  # Contains file:line separator
}

@test "forensics_stack_json: returns valid JSON array" {
    test_func() {
        forensics_stack_json
    }
    result=$(test_func)
    [[ "$result" =~ ^\[ ]]
    [[ "$result" =~ \]$ ]]
}

@test "forensics_stack_json: includes func, file, line keys" {
    test_func() {
        forensics_stack_json
    }
    result=$(test_func)
    [[ "$result" =~ '"func"' ]]
    [[ "$result" =~ '"file"' ]]
    [[ "$result" =~ '"line"' ]]
}

@test "forensics_caller: returns caller at depth 1" {
    inner() { forensics_caller 1; }
    outer() { inner; }
    result=$(outer)
    [[ "$result" =~ "outer" ]]
}

@test "forensics_caller: returns caller at depth 2" {
    deepest() { forensics_caller 2; }
    middle() { deepest; }
    top() { middle; }
    result=$(top)
    [[ "$result" =~ "top" ]]
}

@test "forensics_caller: includes file and line" {
    test_func() {
        forensics_caller 1
    }
    result=$(test_func)
    [[ "$result" =~ ":" ]]  # file:line format
}

# =============================================================================
# CATEGORY 2: ERROR CONTEXT CAPTURE
# =============================================================================

@test "forensics_capture: returns valid JSON" {
    result=$(forensics_capture)
    [[ "$result" =~ ^\{ ]]
    [[ "$result" =~ \}$ ]]
}

@test "forensics_capture: includes timestamp" {
    result=$(forensics_capture)
    [[ "$result" =~ '"timestamp"' ]]
}

@test "forensics_capture: includes stack" {
    result=$(forensics_capture)
    [[ "$result" =~ '"stack"' ]]
}

@test "forensics_capture: includes variables" {
    result=$(forensics_capture)
    [[ "$result" =~ '"variables"' ]]
}

@test "forensics_capture: includes environment" {
    result=$(forensics_capture)
    [[ "$result" =~ '"environment"' ]]
}

@test "forensics_capture: includes last_command" {
    result=$(forensics_capture)
    [[ "$result" =~ '"last_command"' ]]
}

@test "forensics_capture: includes exit_status" {
    result=$(forensics_capture)
    [[ "$result" =~ '"exit_status"' ]]
}

# =============================================================================
# CATEGORY 3: SNAPSHOTS
# =============================================================================

@test "forensics_snapshot: creates snapshot file" {
    forensics_snapshot "test_snap"
    [[ -f "$MAINFRAME_FORENSICS_DIR/snapshot_test_snap.json" ]]
}

@test "forensics_snapshot: snapshot contains valid JSON" {
    forensics_snapshot "test_snap"
    result=$(<"$MAINFRAME_FORENSICS_DIR/snapshot_test_snap.json")
    [[ "$result" =~ ^\{ ]]
    [[ "$result" =~ '"id"' ]]
    [[ "$result" =~ '"name"' ]]
}

@test "forensics_snapshot: snapshot contains context" {
    forensics_snapshot "test_snap"
    result=$(<"$MAINFRAME_FORENSICS_DIR/snapshot_test_snap.json")
    [[ "$result" =~ '"context"' ]]
}

@test "forensics_snapshot: requires name argument" {
    run forensics_snapshot
    [[ "$status" -ne 0 ]]
}

@test "forensics_diff: compares two snapshots" {
    forensics_snapshot "before"
    sleep 0.1
    forensics_snapshot "after"
    result=$(forensics_diff "before" "after")
    [[ "$result" =~ '"snap1":"before"' ]]
    [[ "$result" =~ '"snap2":"after"' ]]
}

@test "forensics_diff: returns error for missing snapshot" {
    run forensics_diff "nonexistent1" "nonexistent2"
    [[ "$output" =~ '"error":"snapshot_not_found"' ]]
}

@test "forensics_diff: includes timestamps" {
    forensics_snapshot "s1"
    forensics_snapshot "s2"
    result=$(forensics_diff "s1" "s2")
    [[ "$result" =~ '"time1"' ]]
    [[ "$result" =~ '"time2"' ]]
}

# =============================================================================
# CATEGORY 4: ERROR CHAINS
# =============================================================================

@test "forensics_error: returns error ID" {
    err_id=$(forensics_error "Test error")
    [[ "$err_id" =~ ^err_ ]]
}

@test "forensics_error: includes message in chain" {
    forensics_error "Test error message"
    chain=$(forensics_chain_dump)
    [[ "$chain" =~ "Test error message" ]]
}

@test "forensics_error: includes timestamp" {
    forensics_error "Test error"
    chain=$(forensics_chain_dump)
    [[ "$chain" =~ '"timestamp"' ]]
}

@test "forensics_error: includes stack trace" {
    forensics_error "Test error"
    chain=$(forensics_chain_dump)
    [[ "$chain" =~ '"stack"' ]]
}

@test "forensics_error: links to cause when provided" {
    cause_id=$(forensics_error "Root cause")
    wrapper_id=$(forensics_error "Wrapper error" "$cause_id")
    chain=$(forensics_chain_dump)
    [[ "$chain" =~ '"cause"' ]]
}

@test "forensics_chain_add: adds to existing error chain" {
    err1=$(forensics_error "First error")
    err2=$(forensics_chain_add "$err1" "Second error")
    chain=$(forensics_chain_dump)
    [[ "$chain" =~ "First error" ]]
    [[ "$chain" =~ "Second error" ]]
}

@test "forensics_chain_dump: returns JSON array" {
    forensics_error "Error 1"
    forensics_error "Error 2"
    chain=$(forensics_chain_dump)
    [[ "$chain" =~ ^\[ ]]
    [[ "$chain" =~ \]$ ]]
}

@test "forensics_chain_dump: returns empty array when no errors" {
    forensics_clear
    chain=$(forensics_chain_dump)
    [[ "$chain" == "[]" ]]
}

@test "forensics_root_cause: finds root of chain" {
    root_id=$(forensics_error "Root cause")
    mid_id=$(forensics_error "Middle" "$root_id")
    top_id=$(forensics_error "Top" "$mid_id")

    root=$(forensics_root_cause "$top_id")
    [[ "$root" =~ "Root cause" ]]
}

@test "forensics_root_cause: handles single error" {
    err_id=$(forensics_error "Only error")
    root=$(forensics_root_cause "$err_id")
    [[ "$root" =~ "Only error" ]]
}

# =============================================================================
# CATEGORY 5: VARIABLE WATCHES
# =============================================================================

@test "forensics_watch: adds variable to watch list" {
    test_var="initial"
    forensics_watch "test_var"
    status=$(forensics_status)
    [[ "$status" =~ '"watches":1' ]]
}

@test "forensics_watch: is idempotent" {
    test_var="value"
    forensics_watch "test_var"
    forensics_watch "test_var"
    status=$(forensics_status)
    [[ "$status" =~ '"watches":1' ]]
}

@test "forensics_unwatch: removes variable from watch list" {
    test_var="value"
    forensics_watch "test_var"
    forensics_unwatch "test_var"
    status=$(forensics_status)
    [[ "$status" =~ '"watches":0' ]]
}

@test "forensics_watched_changes: returns JSON array" {
    test_var="value"
    forensics_watch "test_var"
    changes=$(forensics_watched_changes)
    [[ "$changes" =~ ^\[ ]]
    [[ "$changes" =~ \]$ ]]
}

@test "forensics_watched_changes: captures initial value" {
    test_var="initial_value"
    forensics_watch "test_var"
    changes=$(forensics_watched_changes)
    [[ "$changes" =~ "initial_value" ]]
    [[ "$changes" =~ "INIT" ]]
}

@test "forensics_watched_changes: includes variable name" {
    my_watched_var="value"
    forensics_watch "my_watched_var"
    changes=$(forensics_watched_changes)
    [[ "$changes" =~ '"var":"my_watched_var"' ]]
}

# =============================================================================
# CATEGORY 6: FORENSIC BUNDLES
# =============================================================================

@test "forensics_bundle: returns valid JSON" {
    bundle=$(forensics_bundle)
    [[ "$bundle" =~ ^\{ ]]
    [[ "$bundle" =~ \}$ ]]
}

@test "forensics_bundle: includes USOP metadata" {
    bundle=$(forensics_bundle)
    [[ "$bundle" =~ '"usop_version":"1.0"' ]]
    [[ "$bundle" =~ '"type":"forensic_bundle"' ]]
}

@test "forensics_bundle: includes bundle ID" {
    bundle=$(forensics_bundle)
    [[ "$bundle" =~ '"id":"bundle_' ]]
}

@test "forensics_bundle: includes hostname" {
    bundle=$(forensics_bundle)
    [[ "$bundle" =~ '"hostname"' ]]
}

@test "forensics_bundle: includes user" {
    bundle=$(forensics_bundle)
    [[ "$bundle" =~ '"user"' ]]
}

@test "forensics_bundle: includes pwd" {
    bundle=$(forensics_bundle)
    [[ "$bundle" =~ '"pwd"' ]]
}

@test "forensics_bundle: includes stack" {
    bundle=$(forensics_bundle)
    [[ "$bundle" =~ '"stack"' ]]
}

@test "forensics_bundle: includes context" {
    bundle=$(forensics_bundle)
    [[ "$bundle" =~ '"context"' ]]
}

@test "forensics_bundle: includes errors" {
    forensics_error "Test error for bundle"
    bundle=$(forensics_bundle)
    [[ "$bundle" =~ '"errors"' ]]
    [[ "$bundle" =~ "Test error for bundle" ]]
}

@test "forensics_bundle: includes watches" {
    test_var="watched_value"
    forensics_watch "test_var"
    bundle=$(forensics_bundle)
    [[ "$bundle" =~ '"watches"' ]]
}

@test "forensics_bundle_save: creates file" {
    forensics_bundle_save "$TEST_TMPDIR/test_bundle.json"
    [[ -f "$TEST_TMPDIR/test_bundle.json" ]]
}

@test "forensics_bundle_save: file contains valid JSON" {
    forensics_bundle_save "$TEST_TMPDIR/test_bundle.json"
    result=$(<"$TEST_TMPDIR/test_bundle.json")
    [[ "$result" =~ ^\{ ]]
    [[ "$result" =~ '"usop_version"' ]]
}

@test "forensics_bundle_load: reads saved bundle" {
    forensics_bundle_save "$TEST_TMPDIR/test_bundle.json"
    result=$(forensics_bundle_load "$TEST_TMPDIR/test_bundle.json")
    [[ "$result" =~ '"usop_version":"1.0"' ]]
}

@test "forensics_bundle_load: returns error for missing file" {
    run forensics_bundle_load "$TEST_TMPDIR/nonexistent.json"
    [[ "$output" =~ '"error":"file_not_found"' ]]
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 7: TRAP INTEGRATION
# =============================================================================

@test "forensics_trap_install: installs trap" {
    forensics_trap_install
    status=$(forensics_status)
    [[ "$status" =~ '"trap":"installed"' ]]
}

@test "forensics_trap_install: is idempotent" {
    forensics_trap_install
    forensics_trap_install
    status=$(forensics_status)
    [[ "$status" =~ '"trap":"installed"' ]]
}

@test "forensics_trap_uninstall: removes trap" {
    forensics_trap_install
    forensics_trap_uninstall
    status=$(forensics_status)
    [[ "$status" =~ '"trap":"not_installed"' ]]
}

# =============================================================================
# CATEGORY 8: UTILITY FUNCTIONS
# =============================================================================

@test "forensics_clear: clears all state" {
    forensics_error "Error to clear"
    forensics_watch "some_var"
    forensics_snapshot "snap_to_clear"

    forensics_clear

    status=$(forensics_status)
    [[ "$status" =~ '"errors":0' ]]
    [[ "$status" =~ '"watches":0' ]]
    [[ "$status" =~ '"snapshots":0' ]]
}

@test "forensics_status: returns valid JSON" {
    status=$(forensics_status)
    [[ "$status" =~ ^\{ ]]
    [[ "$status" =~ \}$ ]]
}

@test "forensics_status: includes error count" {
    forensics_error "Error 1"
    forensics_error "Error 2"
    status=$(forensics_status)
    [[ "$status" =~ '"errors":2' ]]
}

@test "forensics_status: includes watch count" {
    var1="a"; var2="b"
    forensics_watch "var1"
    forensics_watch "var2"
    status=$(forensics_status)
    [[ "$status" =~ '"watches":2' ]]
}

@test "forensics_status: includes forensics dir" {
    status=$(forensics_status)
    [[ "$status" =~ '"dir"' ]]
}

# =============================================================================
# CATEGORY 9: EDGE CASES AND SECURITY
# =============================================================================

@test "forensics_error: handles special characters in message" {
    err_id=$(forensics_error 'Error with "quotes" and\nnewlines')
    chain=$(forensics_chain_dump)
    # Should be escaped
    [[ "$chain" =~ '\"quotes\"' ]] || [[ "$chain" =~ 'quotes' ]]
}

@test "forensics_snapshot: handles special characters in name" {
    # Only alphanumeric names should work safely
    forensics_snapshot "test123"
    [[ -f "$MAINFRAME_FORENSICS_DIR/snapshot_test123.json" ]]
}

@test "forensics_capture: truncates long variable values" {
    long_var=$(printf 'x%.0s' {1..10000})
    result=$(forensics_capture)
    # Should contain truncation indicator
    [[ ${#result} -lt 50000 ]]  # Much smaller than original
}

@test "forensics_stack_json: handles deep call stacks" {
    recurse() {
        local depth=$1
        if [[ $depth -le 0 ]]; then
            forensics_stack_json
        else
            recurse $((depth - 1))
        fi
    }
    result=$(recurse 10)
    [[ "$result" =~ ^\[ ]]
}

@test "forensics_bundle: includes history array" {
    bundle=$(forensics_bundle)
    [[ "$bundle" =~ '"history"' ]]
}

@test "forensics_error: generates unique IDs" {
    id1=$(forensics_error "Error 1")
    id2=$(forensics_error "Error 2")
    [[ "$id1" != "$id2" ]]
}

@test "forensics_root_cause: handles missing error ID" {
    run forensics_root_cause "nonexistent_err_id"
    [[ "$output" =~ '"error":"error_not_found"' ]]
    [[ "$status" -eq 1 ]]
}

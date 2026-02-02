#!/usr/bin/env bats
# =============================================================================
# Tests for MAINFRAME/lib/agent_exec.sh - Unified Agent Execution Pipeline
# =============================================================================

load '../helpers/setup'

setup() {
    common_setup
    # Use test-specific state directory (isolated per test)
    export MAINFRAME_AGENT_STATE="${TEST_TEMP_DIR}/agent_state"
    export MAINFRAME_QUIET=1
    # Source the agent_exec library
    source "${_PROJECT_ROOT}/lib/agent_exec.sh"
}

teardown() {
    common_teardown
}

# =============================================================================
# agent_exec: BASIC EXECUTION
# =============================================================================

@test "agent_exec: executes a simple command successfully" {
    run agent_exec echo "hello"
    assert_success
}

@test "agent_exec: returns non-zero for failed commands" {
    run agent_exec false
    assert_failure
    [[ $status -eq 3 ]]
}

@test "agent_exec: errors on no command" {
    run agent_exec
    assert_failure
}

@test "agent_exec: passes arguments to command" {
    local outfile="${TEST_TEMP_DIR}/args.txt"
    agent_exec bash -c "echo 'test_value' > '${outfile}'"
    [[ -f "$outfile" ]]
    [[ "$(cat "$outfile")" == "test_value" ]]
}

# =============================================================================
# agent_exec: GUARD PHASE
# =============================================================================

@test "agent_exec: guard passes allows execution" {
    run agent_exec --guard "true" echo "guarded"
    assert_success
}

@test "agent_exec: guard failure blocks execution" {
    run agent_exec --guard "false" echo "should not run"
    [[ $status -eq 1 ]]
}

@test "agent_exec: guard failure returns exit code 1" {
    run agent_exec --guard "test -f /nonexistent/path/xyz" echo "hello"
    [[ $status -eq 1 ]]
}

# =============================================================================
# agent_exec: CONTRACT PHASE
# =============================================================================

@test "agent_exec: contract passes allows execution" {
    run agent_exec --contract "true" echo "validated"
    assert_success
}

@test "agent_exec: contract failure blocks execution" {
    run agent_exec --contract "false" echo "should not run"
    [[ $status -eq 2 ]]
}

@test "agent_exec: contract checked after guard" {
    # Guard passes but contract fails
    run agent_exec --guard "true" --contract "false" echo "hello"
    [[ $status -eq 2 ]]
}

# =============================================================================
# agent_exec: IDEMPOTENCY
# =============================================================================

@test "agent_exec: idempotent check skips when condition met" {
    local marker="${TEST_TEMP_DIR}/done_marker"
    touch "$marker"
    local counter="${TEST_TEMP_DIR}/counter"
    echo "0" > "$counter"

    agent_exec --idempotent "test -f ${marker}" \
        bash -c "echo 1 > '${counter}'"

    # Counter should still be 0 because execution was skipped
    [[ "$(cat "$counter")" == "0" ]]
}

@test "agent_exec: idempotent check executes when condition not met" {
    local counter="${TEST_TEMP_DIR}/counter"
    echo "0" > "$counter"

    agent_exec --idempotent "test -f /nonexistent_file_xyz" \
        bash -c "echo 1 > '${counter}'"

    [[ "$(cat "$counter")" == "1" ]]
}

# =============================================================================
# agent_exec: TIMEOUT
# =============================================================================

@test "agent_exec: timeout kills long-running command" {
    skip_if_slow
    run agent_exec --timeout 1 sleep 3
    assert_failure
}

@test "agent_exec: command completes within timeout" {
    run agent_exec --timeout 10 echo "fast"
    assert_success
}

# =============================================================================
# agent_exec: UNDO/ROLLBACK
# =============================================================================

@test "agent_exec: undo executes on failure" {
    local marker="${TEST_TEMP_DIR}/undo_ran"
    run agent_exec --undo "touch '${marker}'" false
    assert_failure
    [[ -f "$marker" ]]
}

@test "agent_exec: undo not executed on success" {
    local marker="${TEST_TEMP_DIR}/undo_ran"
    run agent_exec --undo "touch '${marker}'" true
    assert_success
    [[ ! -f "$marker" ]]
}

# =============================================================================
# agent_exec: CALLBACKS
# =============================================================================

@test "agent_exec: on-success callback fires on success" {
    local marker="${TEST_TEMP_DIR}/success_marker"
    agent_exec --on-success "touch '${marker}'" true
    [[ -f "$marker" ]]
}

@test "agent_exec: on-failure callback fires on failure" {
    local marker="${TEST_TEMP_DIR}/failure_marker"
    run agent_exec --on-failure "touch '${marker}'" false
    assert_failure
    [[ -f "$marker" ]]
}

@test "agent_exec: on-success callback does not fire on failure" {
    local marker="${TEST_TEMP_DIR}/success_marker"
    run agent_exec --on-success "touch '${marker}'" false
    assert_failure
    [[ ! -f "$marker" ]]
}

# =============================================================================
# agent_exec: JSON OUTPUT
# =============================================================================

@test "agent_exec: json output contains status field" {
    run agent_exec --json echo "hello"
    assert_success
    [[ "$output" == *'"status":"success"'* ]]
}

@test "agent_exec: json output shows guard_failed status" {
    run agent_exec --json --guard "false" echo "hello"
    [[ "$output" == *'"status":"guard_failed"'* ]]
}

@test "agent_exec: json output shows contract_failed status" {
    run agent_exec --json --contract "false" echo "hello"
    [[ "$output" == *'"status":"contract_failed"'* ]]
}

@test "agent_exec: json output contains duration_ms" {
    run agent_exec --json echo "hello"
    assert_success
    [[ "$output" == *'"duration_ms":'* ]]
}

@test "agent_exec: json output shows idempotent skipped" {
    local marker="${TEST_TEMP_DIR}/exists"
    touch "$marker"
    run agent_exec --json --idempotent "test -f ${marker}" echo "hello"
    assert_success
    [[ "$output" == *'"idempotent":"skipped"'* ]]
}

# =============================================================================
# agent_exec: DRY-RUN
# =============================================================================

@test "agent_exec: dry-run does not execute command" {
    local marker="${TEST_TEMP_DIR}/executed"
    run agent_exec --dry-run bash -c "touch '${marker}'"
    assert_success
    [[ ! -f "$marker" ]]
}

@test "agent_exec: dry-run prints phase info" {
    run agent_exec --dry-run --guard "true" --undo "rm foo" echo "hello"
    assert_success
    [[ "$output" == *'[dry-run]'* ]]
}

# =============================================================================
# agent_exec: LABEL
# =============================================================================

@test "agent_exec: label appears in json output" {
    run agent_exec --json --label "my_operation" echo "hello"
    assert_success
    [[ "$output" == *'"label":"my_operation"'* ]]
}

# =============================================================================
# UNDO STACK
# =============================================================================

@test "agent_undo_register: registers an undo action" {
    agent_undo_register "test_action" "echo undone"
    local stack
    stack=$(agent_undo_stack)
    [[ "$stack" == *'test_action'* ]]
}

@test "agent_undo_all: executes undo in LIFO order" {
    local log="${TEST_TEMP_DIR}/undo_log"
    agent_undo_register "first" "echo first >> '${log}'"
    agent_undo_register "second" "echo second >> '${log}'"
    agent_undo_register "third" "echo third >> '${log}'"

    agent_undo_all

    # Third registered should execute first (LIFO)
    local first_line
    first_line=$(head -1 "$log")
    [[ "$first_line" == "third" ]]
}

@test "agent_undo_clear: empties the undo stack" {
    agent_undo_register "action1" "echo noop"
    agent_undo_clear
    local stack
    stack=$(agent_undo_stack)
    [[ "$stack" == "[]" ]]
}

@test "agent_undo_stack: returns empty array when no registrations" {
    local stack
    stack=$(agent_undo_stack)
    [[ "$stack" == "[]" ]]
}

# =============================================================================
# TRANSACTIONS
# =============================================================================

@test "agent_transaction: executes all steps on success" {
    local dir="${TEST_TEMP_DIR}/txn"
    run agent_transaction --label "test_txn" <<EOF
do: mkdir -p ${dir}
undo: rm -rf ${dir}
do: touch ${dir}/file1
undo: rm ${dir}/file1
EOF
    assert_success
    [[ -f "${dir}/file1" ]]
}

@test "agent_transaction: rolls back on failure" {
    local dir="${TEST_TEMP_DIR}/txn_rollback"
    run agent_transaction --label "rollback_test" <<EOF
do: mkdir -p ${dir}
undo: rm -rf ${dir}
do: false
undo: echo noop
EOF
    assert_failure
    # The first step should have been rolled back
    [[ ! -d "${dir}" ]]
}

@test "agent_transaction: returns failure on empty input" {
    run agent_transaction <<< ""
    assert_failure
}

# =============================================================================
# RECOVERY PLAYBOOKS
# =============================================================================

@test "agent_recovery_register: registers a playbook" {
    agent_recovery_register "test pattern" "echo fix"
    run agent_recovery_list
    [[ "$output" == *'test pattern'* ]]
}

@test "agent_recover: matches pattern and runs recovery" {
    local marker="${TEST_TEMP_DIR}/recovered"
    agent_recovery_register "Error XYZ" "touch '${marker}'"
    run agent_recover "my_cmd" "Something Error XYZ happened"
    assert_success
    [[ -f "$marker" ]]
}

@test "agent_recover: returns 1 when no pattern matches" {
    agent_recovery_register "specific_error" "echo fix"
    run agent_recover "my_cmd" "completely different error"
    [[ $status -eq 1 ]]
}

@test "agent_recovery_suggest: returns matching suggestion" {
    agent_recovery_register "No space left" "cleanup_disk"
    run agent_recovery_suggest "No space left on device"
    assert_success
    [[ "$output" == *'"pattern":"No space left"'* ]]
    [[ "$output" == *'"command":"cleanup_disk"'* ]]
}

@test "agent_recovery_suggest: returns no-match when nothing matches" {
    run agent_recovery_suggest "unknown error type"
    assert_failure
    [[ "$output" == *'"pattern":"none"'* ]]
}

# =============================================================================
# PIPELINE HELPERS
# =============================================================================

@test "agent_should_skip: returns 0 when check passes" {
    run agent_should_skip "true"
    assert_success
}

@test "agent_should_skip: returns 1 when check fails" {
    run agent_should_skip "false"
    assert_failure
}

@test "agent_observe: captures timing and exit code" {
    run agent_observe echo "test"
    assert_success
    [[ "$output" == *'"exit_code":0'* ]]
    [[ "$output" == *'"duration_ms":'* ]]
}

@test "agent_observe: reports non-zero exit code" {
    run agent_observe false
    [[ $status -ne 0 ]]
    [[ "$output" == *'"exit_code":1'* ]]
}

@test "agent_pipeline: runs commands in sequence" {
    local f1="${TEST_TEMP_DIR}/step1"
    local f2="${TEST_TEMP_DIR}/step2"
    local f3="${TEST_TEMP_DIR}/step3"
    run agent_pipeline \
        "touch ${f1}" ";" \
        "touch ${f2}" ";" \
        "touch ${f3}"
    assert_success
    [[ -f "$f1" ]]
    [[ -f "$f2" ]]
    [[ -f "$f3" ]]
}

@test "agent_pipeline: stops on failure" {
    local f1="${TEST_TEMP_DIR}/step1"
    local f3="${TEST_TEMP_DIR}/step3"
    run agent_pipeline \
        "touch ${f1}" ";" \
        "false" ";" \
        "touch ${f3}"
    assert_failure
    # step1 should have run, step3 should not
    [[ -f "$f1" ]]
    [[ ! -f "$f3" ]]
}

@test "agent_pipeline: json output on success" {
    run agent_pipeline --json --label "test_pipe" "true" ";" "true"
    assert_success
    [[ "$output" == *'"status":"success"'* ]]
    [[ "$output" == *'"label":"test_pipe"'* ]]
}

@test "agent_context_start: creates context marker" {
    agent_context_start "test_context"
    [[ -f "${MAINFRAME_AGENT_STATE}/current_context" ]]
    [[ "$(cat "${MAINFRAME_AGENT_STATE}/current_context")" == "test_context" ]]
}

@test "agent_context_end: removes context marker" {
    agent_context_start "test_context"
    agent_context_end
    [[ ! -f "${MAINFRAME_AGENT_STATE}/current_context" ]]
}

# =============================================================================
# agent_exec: RETRY INTEGRATION
# =============================================================================

@test "agent_exec: retry succeeds after transient failure" {
    local counter="${TEST_TEMP_DIR}/retry_counter"
    echo "0" > "$counter"

    # Command that fails twice then succeeds
    _flaky() {
        local c
        c=$(cat "$counter")
        c=$((c + 1))
        echo "$c" > "$counter"
        [[ $c -ge 3 ]]
    }
    export -f _flaky
    export counter

    run agent_exec --retry 5 bash -c '
        counter='"'${counter}'"'
        c=$(cat "$counter")
        c=$((c + 1))
        echo "$c" > "$counter"
        [[ $c -ge 3 ]]
    '
    assert_success
}

@test "agent_exec: retry exhausted returns failure" {
    run agent_exec --retry 2 --timeout 10 false
    assert_failure
}

# =============================================================================
# agent_exec: COMBINED OPTIONS
# =============================================================================

@test "agent_exec: guard + contract + execute all pass" {
    run agent_exec \
        --guard "true" \
        --contract "true" \
        --label "combined_test" \
        --json \
        echo "all_phases"
    assert_success
    [[ "$output" == *'"status":"success"'* ]]
    [[ "$output" == *'"guard":"passed"'* ]]
    [[ "$output" == *'"contract":"passed"'* ]]
}

@test "agent_exec: json output contains exit_code field" {
    run agent_exec --json echo "hello"
    assert_success
    [[ "$output" == *'"exit_code":0'* ]]
}

@test "agent_exec: json output on exec failure shows exit code" {
    run agent_exec --json bash -c "exit 42"
    assert_failure
    [[ "$output" == *'"exit_code":42'* ]]
}

#!/usr/bin/env bash
# =============================================================================
# Tests for MAINFRAME/lib/taskstate.sh - Resumable Task State Machines
# =============================================================================

# Determine project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Use isolated test directory for task state
TEST_TMPDIR=$(mktemp -d)
export MAINFRAME_TASK_DIR="${TEST_TMPDIR}/tasks"
export MAINFRAME_QUIET=1

# Source the library
source "${PROJECT_ROOT}/lib/common.sh"
source "${PROJECT_ROOT}/lib/taskstate.sh"

# Test counters
_TESTS_RUN=0
_TESTS_PASSED=0
_TESTS_FAILED=0

# =============================================================================
# TEST HELPERS
# =============================================================================

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-assertion}"
    ((_TESTS_RUN++))

    if [[ "$expected" == "$actual" ]]; then
        ((_TESTS_PASSED++))
        printf '  PASS: %s\n' "$msg"
    else
        ((_TESTS_FAILED++))
        printf '  FAIL: %s (expected: "%s", got: "%s")\n' "$msg" "$expected" "$actual"
    fi
}

assert_ok() {
    local rc="$1"
    local msg="${2:-should succeed}"
    ((_TESTS_RUN++))

    if [[ "$rc" -eq 0 ]]; then
        ((_TESTS_PASSED++))
        printf '  PASS: %s\n' "$msg"
    else
        ((_TESTS_FAILED++))
        printf '  FAIL: %s (exit code: %d)\n' "$msg" "$rc"
    fi
}

assert_fail() {
    local rc="$1"
    local msg="${2:-should fail}"
    ((_TESTS_RUN++))

    if [[ "$rc" -ne 0 ]]; then
        ((_TESTS_PASSED++))
        printf '  PASS: %s\n' "$msg"
    else
        ((_TESTS_FAILED++))
        printf '  FAIL: %s (expected failure, got success)\n' "$msg"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-should contain}"
    ((_TESTS_RUN++))

    if [[ "$haystack" == *"$needle"* ]]; then
        ((_TESTS_PASSED++))
        printf '  PASS: %s\n' "$msg"
    else
        ((_TESTS_FAILED++))
        printf '  FAIL: %s (does not contain: "%s")\n' "$msg" "$needle"
    fi
}

assert_file_exists() {
    local path="$1"
    local msg="${2:-file should exist}"
    ((_TESTS_RUN++))

    if [[ -f "$path" ]]; then
        ((_TESTS_PASSED++))
        printf '  PASS: %s\n' "$msg"
    else
        ((_TESTS_FAILED++))
        printf '  FAIL: %s (not found: %s)\n' "$msg" "$path"
    fi
}

assert_dir_exists() {
    local path="$1"
    local msg="${2:-directory should exist}"
    ((_TESTS_RUN++))

    if [[ -d "$path" ]]; then
        ((_TESTS_PASSED++))
        printf '  PASS: %s\n' "$msg"
    else
        ((_TESTS_FAILED++))
        printf '  FAIL: %s (not found: %s)\n' "$msg" "$path"
    fi
}

# Reset state between tests
reset_state() {
    _TASKSTATE_CURRENT_ID=""
    rm -rf "${MAINFRAME_TASK_DIR}"
    mkdir -p "${MAINFRAME_TASK_DIR}"
}

# =============================================================================
# TEST: Task Creation
# =============================================================================

test_task_create() {
    printf '\n=== test_task_create ===\n'
    reset_state

    local id
    id=$(task_create "my-build" "Build the project")
    local rc=$?
    _TASKSTATE_CURRENT_ID="$id"
    assert_ok $rc "task_create should succeed"
    assert_eq 8 "${#id}" "task ID should be 8 chars"

    # State directory should exist
    assert_dir_exists "${MAINFRAME_TASK_DIR}/${id}" "task dir should exist"
    assert_file_exists "${MAINFRAME_TASK_DIR}/${id}/manifest.json" "manifest should exist"
    assert_file_exists "${MAINFRAME_TASK_DIR}/${id}/steps.json" "steps.json should exist"
    assert_dir_exists "${MAINFRAME_TASK_DIR}/${id}/data" "data dir should exist"
    assert_dir_exists "${MAINFRAME_TASK_DIR}/${id}/files" "files dir should exist"
    assert_dir_exists "${MAINFRAME_TASK_DIR}/${id}/checkpoints" "checkpoints dir should exist"

    # Manifest should contain correct info
    local manifest_content
    manifest_content=$(<"${MAINFRAME_TASK_DIR}/${id}/manifest.json")
    assert_contains "$manifest_content" '"name":"my-build"' "manifest should contain name"
    assert_contains "$manifest_content" '"status":"pending"' "manifest should have pending status"
    assert_contains "$manifest_content" '"description":"Build the project"' "manifest should contain description"
}

test_task_create_no_name() {
    printf '\n=== test_task_create_no_name ===\n'
    reset_state

    local id
    id=$(task_create "" 2>/dev/null)
    assert_fail $? "task_create without name should fail"
}

test_task_create_duplicate_resumes() {
    printf '\n=== test_task_create_duplicate_resumes ===\n'
    reset_state

    local id1 id2
    id1=$(task_create "deploy-app")
    id2=$(task_create "deploy-app")
    assert_eq "$id1" "$id2" "creating duplicate name should return same ID"
}

# =============================================================================
# TEST: Task Resume
# =============================================================================

test_task_resume_by_id() {
    printf '\n=== test_task_resume_by_id ===\n'
    reset_state

    local id
    id=$(task_create "test-resume")
    _TASKSTATE_CURRENT_ID=""

    task_resume "$id"
    assert_ok $? "task_resume by ID should succeed"
    assert_eq "$id" "$_TASKSTATE_CURRENT_ID" "current task should be set"
}

test_task_resume_by_name() {
    printf '\n=== test_task_resume_by_name ===\n'
    reset_state

    local id
    id=$(task_create "named-task")
    _TASKSTATE_CURRENT_ID=""

    task_resume "named-task"
    assert_ok $? "task_resume by name should succeed"
    assert_eq "$id" "$_TASKSTATE_CURRENT_ID" "current task should match original ID"
}

test_task_resume_not_found() {
    printf '\n=== test_task_resume_not_found ===\n'
    reset_state

    task_resume "nonexistent" 2>/dev/null
    assert_fail $? "task_resume for missing task should fail"
}

# =============================================================================
# TEST: Task List
# =============================================================================

test_task_list() {
    printf '\n=== test_task_list ===\n'
    reset_state

    task_create "task-a" >/dev/null
    task_create "task-b" >/dev/null

    # Need to create task-b fresh (task_create reuses if same name)
    _TASKSTATE_CURRENT_ID=""
    task_create "task-b" >/dev/null

    local output
    output=$(task_list)
    assert_contains "$output" "task-a" "list should contain task-a"
    assert_contains "$output" "task-b" "list should contain task-b"
}

test_task_list_with_filter() {
    printf '\n=== test_task_list_with_filter ===\n'
    reset_state

    local id1 id2
    id1=$(task_create "pending-task")
    id2=$(task_create "done-task")

    # Mark done-task as completed by completing all steps
    task_resume "$id2" 2>/dev/null
    task_add_step "only-step"
    task_step_complete "only-step"

    local output
    output=$(task_list --status completed)
    assert_contains "$output" "done-task" "completed filter should show done-task"

    output=$(task_list --status pending)
    assert_contains "$output" "pending-task" "pending filter should show pending-task"
}

# =============================================================================
# TEST: Task Info & Delete
# =============================================================================

test_task_info() {
    printf '\n=== test_task_info ===\n'
    reset_state

    local id
    id=$(task_create "info-task" "A test task")
    _TASKSTATE_CURRENT_ID="$id"

    local info
    info=$(task_info)
    assert_contains "$info" '"name":"info-task"' "info should have name"
    assert_contains "$info" '"id":"'"$id"'"' "info should have ID"
    assert_contains "$info" '"description":"A test task"' "info should have description"
}

test_task_delete() {
    printf '\n=== test_task_delete ===\n'
    reset_state

    local id
    id=$(task_create "delete-me")
    _TASKSTATE_CURRENT_ID="$id"

    task_delete "$id"
    assert_ok $? "task_delete should succeed"

    local dir="${MAINFRAME_TASK_DIR}/${id}"
    ((_TESTS_RUN++))
    if [[ ! -d "$dir" ]]; then
        ((_TESTS_PASSED++))
        printf '  PASS: task directory should be removed\n'
    else
        ((_TESTS_FAILED++))
        printf '  FAIL: task directory still exists\n'
    fi

    assert_eq "" "$_TASKSTATE_CURRENT_ID" "current task should be cleared"
}

# =============================================================================
# TEST: Step Management
# =============================================================================

test_task_add_step() {
    printf '\n=== test_task_add_step ===\n'
    reset_state

    local id
    id=$(task_create "step-test")
    _TASKSTATE_CURRENT_ID="$id"

    task_add_step "compile" "Compile the code"
    assert_ok $? "task_add_step should succeed"

    task_add_step "test" "Run tests"
    assert_ok $? "second step should succeed"

    local steps_content
    steps_content=$(<"${MAINFRAME_TASK_DIR}/${id}/steps.json")
    assert_contains "$steps_content" '"name":"compile"' "steps should contain compile"
    assert_contains "$steps_content" '"name":"test"' "steps should contain test"
    assert_contains "$steps_content" '"status":"pending"' "steps should be pending"
}

test_task_add_step_idempotent() {
    printf '\n=== test_task_add_step_idempotent ===\n'
    reset_state

    task_create "idem-test" >/dev/null

    task_add_step "build"
    task_add_step "build"

    local count
    count=$(_task_count_steps "total")
    assert_eq "1" "$count" "adding same step twice should not duplicate"
}

test_task_step_execute() {
    printf '\n=== test_task_step_execute ===\n'
    reset_state

    local id
    id=$(task_create "exec-test")
    _TASKSTATE_CURRENT_ID="$id"

    task_step "greet" echo "hello world"
    assert_ok $? "task_step should succeed"

    local status
    status=$(task_step_status "greet")
    assert_eq "completed" "$status" "step should be completed"

    # Check result was captured
    local result
    result=$(task_step_result "greet")
    assert_contains "$result" "hello world" "result should contain command output"
}

test_task_step_failure() {
    printf '\n=== test_task_step_failure ===\n'
    reset_state

    task_create "fail-test" >/dev/null

    task_step "bad-step" false
    assert_fail $? "task_step with failing command should return non-zero"

    local status
    status=$(task_step_status "bad-step")
    assert_eq "failed" "$status" "step should be marked failed"

    # Task overall status should be failed
    local manifest
    manifest=$(<"${MAINFRAME_TASK_DIR}/${_TASKSTATE_CURRENT_ID}/manifest.json")
    assert_contains "$manifest" '"status":"failed"' "task status should be failed"
}

test_task_step_skip_completed() {
    printf '\n=== test_task_step_skip_completed ===\n'
    reset_state

    task_create "skip-test" >/dev/null

    # Execute step first time
    task_step "once" echo "first run"
    assert_ok $? "first execution should succeed"

    # Execute same step again - should skip
    task_step "once" echo "second run"
    assert_ok $? "second execution should also return 0 (skipped)"

    # Result should still be from first run
    local result
    result=$(task_step_result "once")
    assert_contains "$result" "first run" "result should be from first execution"
}

test_task_step_manual_complete() {
    printf '\n=== test_task_step_manual_complete ===\n'
    reset_state

    task_create "manual-test" >/dev/null
    task_add_step "manual-step"

    task_step_complete "manual-step" "done by hand"
    assert_ok $? "task_step_complete should succeed"

    local status
    status=$(task_step_status "manual-step")
    assert_eq "completed" "$status" "step should be completed"
}

test_task_step_skip() {
    printf '\n=== test_task_step_skip ===\n'
    reset_state

    task_create "skip-step-test" >/dev/null
    task_add_step "optional-step"

    task_step_skip "optional-step" "not needed"
    assert_ok $? "task_step_skip should succeed"

    local status
    status=$(task_step_status "optional-step")
    assert_eq "skipped" "$status" "step should be skipped"

    task_step_is_done "optional-step"
    assert_ok $? "skipped step should count as done"
}

test_task_step_is_done() {
    printf '\n=== test_task_step_is_done ===\n'
    reset_state

    task_create "done-test" >/dev/null
    task_add_step "pending-step"
    task_add_step "completed-step"
    task_add_step "skipped-step"

    task_step_complete "completed-step"
    task_step_skip "skipped-step"

    task_step_is_done "pending-step"
    assert_fail $? "pending step should not be done"

    task_step_is_done "completed-step"
    assert_ok $? "completed step should be done"

    task_step_is_done "skipped-step"
    assert_ok $? "skipped step should be done"
}

# =============================================================================
# TEST: State/Data Storage
# =============================================================================

test_task_set_get() {
    printf '\n=== test_task_set_get ===\n'
    reset_state

    task_create "data-test" >/dev/null

    task_set "branch" "main"
    assert_ok $? "task_set should succeed"

    local val
    val=$(task_get "branch")
    assert_eq "main" "$val" "task_get should return stored value"
}

test_task_get_default() {
    printf '\n=== test_task_get_default ===\n'
    reset_state

    task_create "default-test" >/dev/null

    local val
    val=$(task_get "missing-key" "fallback")
    assert_eq "fallback" "$val" "task_get should return default for missing key"
}

test_task_has() {
    printf '\n=== test_task_has ===\n'
    reset_state

    task_create "has-test" >/dev/null

    task_set "exists" "yes"

    task_has "exists"
    assert_ok $? "task_has should return 0 for existing key"

    task_has "nope"
    assert_fail $? "task_has should return 1 for missing key"
}

test_task_keys() {
    printf '\n=== test_task_keys ===\n'
    reset_state

    task_create "keys-test" >/dev/null
    task_set "alpha" "1"
    task_set "beta" "2"
    task_set "gamma" "3"

    local keys
    keys=$(task_keys)
    assert_contains "$keys" "alpha" "keys should contain alpha"
    assert_contains "$keys" "beta" "keys should contain beta"
    assert_contains "$keys" "gamma" "keys should contain gamma"
}

test_task_store_retrieve_file() {
    printf '\n=== test_task_store_retrieve_file ===\n'
    reset_state

    task_create "file-test" >/dev/null

    # Create a test file
    local src="${TEST_TMPDIR}/test_input.txt"
    printf 'line1\nline2\nline3\n' > "$src"

    task_store_file "config" "$src"
    assert_ok $? "task_store_file should succeed"

    local dst="${TEST_TMPDIR}/retrieved.txt"
    task_retrieve_file "config" "$dst"
    assert_ok $? "task_retrieve_file should succeed"

    local content
    content=$(<"$dst")
    assert_contains "$content" "line1" "retrieved file should have correct content"
    assert_contains "$content" "line3" "retrieved file should have all lines"
}

# =============================================================================
# TEST: Progress & Reporting
# =============================================================================

test_task_progress() {
    printf '\n=== test_task_progress ===\n'
    reset_state

    task_create "progress-test" >/dev/null
    task_add_step "step1"
    task_add_step "step2"
    task_add_step "step3"
    task_add_step "step4"

    local prog
    prog=$(task_progress)
    assert_eq "0/4" "$prog" "initial progress should be 0/4"

    task_step_complete "step1"
    task_step_complete "step2"

    prog=$(task_progress)
    assert_eq "2/4" "$prog" "progress should be 2/4"

    task_step_skip "step3"
    prog=$(task_progress)
    assert_eq "3/4" "$prog" "skipped counts toward done (3/4)"
}

test_task_progress_pct() {
    printf '\n=== test_task_progress_pct ===\n'
    reset_state

    task_create "pct-test" >/dev/null
    task_add_step "a"
    task_add_step "b"
    task_add_step "c"
    task_add_step "d"

    local pct
    pct=$(task_progress_pct)
    assert_eq "0" "$pct" "initial percentage should be 0"

    task_step_complete "a"
    task_step_complete "b"

    pct=$(task_progress_pct)
    assert_eq "50" "$pct" "50% should be 50"

    task_step_complete "c"
    task_step_complete "d"
    pct=$(task_progress_pct)
    assert_eq "100" "$pct" "all done should be 100"
}

test_task_summary() {
    printf '\n=== test_task_summary ===\n'
    reset_state

    local id
    id=$(task_create "summary-test" "A summary")
    _TASKSTATE_CURRENT_ID="$id"
    task_add_step "s1"
    task_add_step "s2"
    task_add_step "s3"
    task_step_complete "s1"
    task_step_fail "s2" "oops"
    task_set "env" "production"

    local summary
    summary=$(task_summary)
    assert_contains "$summary" '"name":"summary-test"' "summary should have name"
    assert_contains "$summary" '"total":3' "summary should have total steps"
    assert_contains "$summary" '"completed":1' "summary should have completed count"
    assert_contains "$summary" '"failed":1' "summary should have failed count"
    assert_contains "$summary" '"env":"production"' "summary should include data"
}

test_task_remaining() {
    printf '\n=== test_task_remaining ===\n'
    reset_state

    task_create "remaining-test" >/dev/null
    task_add_step "done1"
    task_add_step "todo1"
    task_add_step "done2"
    task_add_step "todo2"

    task_step_complete "done1"
    task_step_skip "done2"

    local remaining
    remaining=$(task_remaining)
    assert_contains "$remaining" "todo1" "remaining should contain todo1"
    assert_contains "$remaining" "todo2" "remaining should contain todo2"

    ((_TESTS_RUN++))
    if [[ "$remaining" != *"done1"* ]]; then
        ((_TESTS_PASSED++))
        printf '  PASS: remaining should not contain done1\n'
    else
        ((_TESTS_FAILED++))
        printf '  FAIL: remaining should not contain done1\n'
    fi
}

test_task_elapsed() {
    printf '\n=== test_task_elapsed ===\n'
    reset_state

    task_create "elapsed-test" >/dev/null

    local elapsed
    elapsed=$(task_elapsed)
    # Elapsed should be a non-negative integer
    ((_TESTS_RUN++))
    if [[ "$elapsed" =~ ^[0-9]+$ ]]; then
        ((_TESTS_PASSED++))
        printf '  PASS: elapsed is a non-negative integer: %s\n' "$elapsed"
    else
        ((_TESTS_FAILED++))
        printf '  FAIL: elapsed should be integer, got: %s\n' "$elapsed"
    fi
}

# =============================================================================
# TEST: Checkpointing
# =============================================================================

test_task_checkpoint() {
    printf '\n=== test_task_checkpoint ===\n'
    reset_state

    local id
    id=$(task_create "checkpoint-test")
    _TASKSTATE_CURRENT_ID="$id"
    task_add_step "step1"
    task_add_step "step2"
    task_step_complete "step1"
    task_set "version" "1"

    # Save checkpoint
    task_checkpoint "before-step2"
    assert_ok $? "task_checkpoint should succeed"

    local cp_dir="${MAINFRAME_TASK_DIR}/${id}/checkpoints/before-step2"
    assert_dir_exists "$cp_dir" "checkpoint directory should exist"
    assert_file_exists "${cp_dir}/manifest.json" "checkpoint manifest should exist"
    assert_file_exists "${cp_dir}/steps.json" "checkpoint steps should exist"
}

test_task_restore_checkpoint() {
    printf '\n=== test_task_restore_checkpoint ===\n'
    reset_state

    local id
    id=$(task_create "restore-test")
    _TASKSTATE_CURRENT_ID="$id"
    task_add_step "a"
    task_add_step "b"
    task_step_complete "a"
    task_set "counter" "10"

    # Checkpoint with step a done
    task_checkpoint "mid-point"

    # Now complete step b and change data
    task_step_complete "b"
    task_set "counter" "20"

    # Verify current state
    local prog
    prog=$(task_progress)
    assert_eq "2/2" "$prog" "progress should be 2/2 before restore"

    local val
    val=$(task_get "counter")
    assert_eq "20" "$val" "counter should be 20 before restore"

    # Restore checkpoint
    task_restore_checkpoint "mid-point"
    assert_ok $? "task_restore_checkpoint should succeed"

    # Verify restored state
    prog=$(task_progress)
    assert_eq "1/2" "$prog" "progress should be 1/2 after restore"

    val=$(task_get "counter")
    assert_eq "10" "$val" "counter should be 10 after restore"
}

test_task_checkpoints_list() {
    printf '\n=== test_task_checkpoints_list ===\n'
    reset_state

    task_create "list-cp-test" >/dev/null
    task_checkpoint "alpha"
    task_checkpoint "beta"
    task_checkpoint "gamma"

    local cps
    cps=$(task_checkpoints)
    assert_contains "$cps" "alpha" "should list alpha checkpoint"
    assert_contains "$cps" "beta" "should list beta checkpoint"
    assert_contains "$cps" "gamma" "should list gamma checkpoint"
}

# =============================================================================
# TEST: Resume Workflow (Integration)
# =============================================================================

test_resume_workflow() {
    printf '\n=== test_resume_workflow (integration) ===\n'
    reset_state

    # Simulate first session: create task and complete some steps
    local id
    id=$(task_create "deploy-pipeline" "Full deployment")
    _TASKSTATE_CURRENT_ID="$id"
    task_add_step "build"
    task_add_step "test"
    task_add_step "deploy"
    task_add_step "verify"

    task_step "build" echo "compiled successfully"
    task_step "test" echo "all tests pass"

    local prog
    prog=$(task_progress)
    assert_eq "2/4" "$prog" "after first session: 2/4"

    # Simulate session death - clear in-memory state
    _TASKSTATE_CURRENT_ID=""

    # Simulate second session: resume and continue
    task_resume "$id"
    assert_ok $? "resume should work"

    # Already-done steps should be skipped
    task_step "build" echo "should not re-run"
    local build_result
    build_result=$(task_step_result "build")
    assert_contains "$build_result" "compiled successfully" "build result should be from first run"

    # Continue with remaining steps
    task_step "deploy" echo "deployed to prod"
    task_step "verify" echo "health check passed"

    prog=$(task_progress)
    assert_eq "4/4" "$prog" "after resume and completion: 4/4"

    # Task should be completed
    local manifest
    manifest=$(<"${MAINFRAME_TASK_DIR}/${id}/manifest.json")
    assert_contains "$manifest" '"status":"completed"' "task should be completed"
}

test_resume_after_failure() {
    printf '\n=== test_resume_after_failure ===\n'
    reset_state

    local id
    id=$(task_create "retry-pipeline")
    _TASKSTATE_CURRENT_ID="$id"
    task_add_step "setup"
    task_add_step "fragile"
    task_add_step "final"

    task_step "setup" echo "ready"

    # Simulate a failing step
    task_step "fragile" false
    local frag_status
    frag_status=$(task_step_status "fragile")
    assert_eq "failed" "$frag_status" "fragile step should be failed"

    # Simulate session restart
    _TASKSTATE_CURRENT_ID=""
    task_resume "$id"

    # On resume, we can see what failed
    local remaining
    remaining=$(task_remaining)
    assert_contains "$remaining" "fragile" "remaining should include failed step"
    assert_contains "$remaining" "final" "remaining should include pending step"

    # Re-run the failed step (now it succeeds)
    # First reset its status so it can be re-run
    _task_update_step "fragile" "status=pending"
    task_step "fragile" echo "worked this time"
    frag_status=$(task_step_status "fragile")
    assert_eq "completed" "$frag_status" "fragile step should be completed on retry"

    task_step "final" echo "all done"
    local prog
    prog=$(task_progress)
    assert_eq "3/3" "$prog" "all steps should be done after retry"
}

# =============================================================================
# TEST: Task Cleanup
# =============================================================================

test_task_cleanup() {
    printf '\n=== test_task_cleanup ===\n'
    reset_state

    # Create a completed task
    local id
    id=$(task_create "old-task")
    _TASKSTATE_CURRENT_ID="$id"
    task_add_step "done"
    task_step_complete "done"

    # Artificially age the manifest (touch with old timestamp)
    local manifest="${MAINFRAME_TASK_DIR}/${id}/manifest.json"
    touch -d "10 days ago" "$manifest" 2>/dev/null || \
        touch -t "$(date -d '10 days ago' '+%Y%m%d%H%M.%S' 2>/dev/null || date -v-10d '+%Y%m%d%H%M.%S')" "$manifest" 2>/dev/null

    local cleaned
    cleaned=$(task_cleanup 7)
    # On systems where touch -d works, it should clean up
    # On others, this is a no-op but shouldn't fail
    ((_TESTS_RUN++))
    if [[ "$cleaned" =~ ^[0-9]+$ ]]; then
        ((_TESTS_PASSED++))
        printf '  PASS: cleanup returned a count: %s\n' "$cleaned"
    else
        ((_TESTS_FAILED++))
        printf '  FAIL: cleanup should return a number\n'
    fi
}

# =============================================================================
# TEST: Edge Cases
# =============================================================================

test_special_characters_in_data() {
    printf '\n=== test_special_characters_in_data ===\n'
    reset_state

    task_create "special-chars" >/dev/null
    task_set "message" 'Hello "world" with \n newlines'

    local val
    val=$(task_get "message")
    assert_eq 'Hello "world" with \n newlines' "$val" "special chars should round-trip"
}

test_multiline_data() {
    printf '\n=== test_multiline_data ===\n'
    reset_state

    task_create "multiline" >/dev/null
    local multiline_val=$'line1\nline2\nline3'
    task_set "log" "$multiline_val"

    local val
    val=$(task_get "log")
    assert_contains "$val" "line1" "multiline value should preserve line1"
    assert_contains "$val" "line3" "multiline value should preserve line3"
}

test_empty_task_progress() {
    printf '\n=== test_empty_task_progress ===\n'
    reset_state

    task_create "empty" >/dev/null

    local prog pct
    prog=$(task_progress)
    assert_eq "0/0" "$prog" "empty task progress should be 0/0"

    pct=$(task_progress_pct)
    assert_eq "0" "$pct" "empty task percentage should be 0"
}

test_no_active_task_errors() {
    printf '\n=== test_no_active_task_errors ===\n'
    reset_state

    # All step operations should fail without an active task
    task_add_step "x" 2>/dev/null
    assert_fail $? "add_step without task should fail"

    task_step "x" echo "hi" 2>/dev/null
    assert_fail $? "task_step without task should fail"

    task_step_complete "x" 2>/dev/null
    assert_fail $? "step_complete without task should fail"

    task_set "k" "v" 2>/dev/null
    assert_fail $? "task_set without task should fail"

    task_checkpoint "cp" 2>/dev/null
    assert_fail $? "checkpoint without task should fail"
}

test_concurrent_task_isolation() {
    printf '\n=== test_concurrent_task_isolation ===\n'
    reset_state

    # Create two separate tasks
    local id1 id2
    id1=$(task_create "task-alpha")
    _TASKSTATE_CURRENT_ID="$id1"
    task_add_step "alpha-step"
    task_set "owner" "alpha"

    id2=$(task_create "task-beta")
    _TASKSTATE_CURRENT_ID="$id2"
    task_add_step "beta-step"
    task_set "owner" "beta"

    # Switch back to alpha
    task_resume "$id1"
    local val
    val=$(task_get "owner")
    assert_eq "alpha" "$val" "alpha task should have its own data"

    # Switch to beta
    task_resume "$id2"
    val=$(task_get "owner")
    assert_eq "beta" "$val" "beta task should have its own data"
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

run_all_tests() {
    printf 'Running taskstate.sh tests...\n'
    printf '=%.0s' {1..60}
    printf '\n'

    # Task lifecycle
    test_task_create
    test_task_create_no_name
    test_task_create_duplicate_resumes
    test_task_resume_by_id
    test_task_resume_by_name
    test_task_resume_not_found
    test_task_list
    test_task_list_with_filter
    test_task_info
    test_task_delete

    # Step management
    test_task_add_step
    test_task_add_step_idempotent
    test_task_step_execute
    test_task_step_failure
    test_task_step_skip_completed
    test_task_step_manual_complete
    test_task_step_skip
    test_task_step_is_done

    # Data storage
    test_task_set_get
    test_task_get_default
    test_task_has
    test_task_keys
    test_task_store_retrieve_file

    # Progress & reporting
    test_task_progress
    test_task_progress_pct
    test_task_summary
    test_task_remaining
    test_task_elapsed

    # Checkpointing
    test_task_checkpoint
    test_task_restore_checkpoint
    test_task_checkpoints_list

    # Integration
    test_resume_workflow
    test_resume_after_failure

    # Cleanup
    test_task_cleanup

    # Edge cases
    test_special_characters_in_data
    test_multiline_data
    test_empty_task_progress
    test_no_active_task_errors
    test_concurrent_task_isolation

    # Summary
    printf '\n'
    printf '=%.0s' {1..60}
    printf '\n'
    printf 'Results: %d tests, %d passed, %d failed\n' "$_TESTS_RUN" "$_TESTS_PASSED" "$_TESTS_FAILED"
    printf '=%.0s' {1..60}
    printf '\n'

    # Cleanup temp directory
    rm -rf "$TEST_TMPDIR"

    [[ $_TESTS_FAILED -eq 0 ]]
}

run_all_tests

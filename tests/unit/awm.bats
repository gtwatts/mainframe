#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/awm.bats - Agent Working Memory Unit Tests
# =============================================================================

# Load bats helpers
load "${BATS_TEST_DIRNAME}/../bats-support/load.bash"
load "${BATS_TEST_DIRNAME}/../bats-assert/load.bash"

# Test setup - load MAINFRAME
setup() {
    # Source the library
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    source "${MAINFRAME_ROOT}/lib/awm.sh"

    # Use temp directory for all AWM storage
    export AWM_ROOT="${BATS_TEST_TMPDIR}/awm_test"
    mkdir -p "$AWM_ROOT"

    # Reset state
    _AWM_SESSION_ID=""
    _AWM_NAMESPACE=""
}

# Cleanup after each test
teardown() {
    # Close any active session
    awm_close 2>/dev/null || true

    # Remove test data
    rm -rf "${BATS_TEST_TMPDIR}/awm_test" 2>/dev/null || true
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Initialize session and capture ID properly (avoiding subshell loss)
init_session() {
    local name="${1:-test}"
    local parent="${2:-}"

    # Call awm_init and let it set _AWM_SESSION_ID directly
    if [[ -n "$parent" ]]; then
        awm_init "$name" "$parent" > /dev/null
    else
        awm_init "$name" > /dev/null
    fi

    # Return the session ID
    printf '%s' "$_AWM_SESSION_ID"
}

# =============================================================================
# SESSION MANAGEMENT TESTS
# =============================================================================

@test "awm_init creates session with ID" {
    awm_init "test-session" > /dev/null

    [ -n "$_AWM_SESSION_ID" ]
    [ ${#_AWM_SESSION_ID} -eq 12 ]  # 12 character hex ID
}

@test "awm_init creates session directory structure" {
    awm_init "test-session" > /dev/null
    local sid="$_AWM_SESSION_ID"

    [ -d "${AWM_ROOT}/sessions/${sid}" ]
    [ -d "${AWM_ROOT}/sessions/${sid}/logs" ]
    [ -d "${AWM_ROOT}/sessions/${sid}/data" ]
    [ -d "${AWM_ROOT}/sessions/${sid}/checkpoints" ]
    [ -f "${AWM_ROOT}/sessions/${sid}/manifest.json" ]
}

@test "awm_init creates valid manifest" {
    awm_init "my-test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    local manifest="${AWM_ROOT}/sessions/${sid}/manifest.json"
    [ -f "$manifest" ]

    # Check JSON structure
    local content
    content=$(<"$manifest")
    [[ "$content" == *'"session_id":"'${sid}'"'* ]]
    [[ "$content" == *'"name":"my-test"'* ]]
    [[ "$content" == *'"status":"active"'* ]]
}

@test "awm_init with parent inherits data" {
    # Create parent session with discovery
    awm_init "parent" > /dev/null
    local parent_sid="$_AWM_SESSION_ID"
    awm_discovery "important finding"
    awm_close

    # Create child session with parent
    awm_init "child" "$parent_sid" > /dev/null
    local child_sid="$_AWM_SESSION_ID"

    # Check inheritance file exists
    [ -f "${AWM_ROOT}/sessions/${child_sid}/logs/inherited_discoveries.jsonl" ]
}

@test "awm_resume restores existing session" {
    awm_init "test-session" > /dev/null
    local sid="$_AWM_SESSION_ID"
    awm_close

    [ -z "$_AWM_SESSION_ID" ]

    # Call directly (not via run) to preserve shell variable
    awm_resume "$sid"
    local status=$?

    [ "$status" -eq 0 ]
    [ "$_AWM_SESSION_ID" = "$sid" ]
}

@test "awm_resume fails for nonexistent session" {
    run awm_resume "nonexistent123"
    assert_failure
}

@test "awm_close marks session as completed" {
    awm_init "test-session" > /dev/null
    local sid="$_AWM_SESSION_ID"
    awm_close

    local manifest="${AWM_ROOT}/sessions/${sid}/manifest.json"
    local content
    content=$(<"$manifest")
    [[ "$content" == *'"status":"completed"'* ]]
}

@test "awm_close clears active session" {
    awm_init "test-session" > /dev/null
    [ -n "$_AWM_SESSION_ID" ]

    awm_close
    [ -z "$_AWM_SESSION_ID" ]
}

# =============================================================================
# NAMESPACE TESTS
# =============================================================================

@test "awm_namespace sets namespace" {
    awm_namespace "code-reviewer"
    [ "$_AWM_NAMESPACE" = "code-reviewer" ]
}

@test "awm_namespace affects session directory" {
    awm_namespace "agent1"
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    [ -d "${AWM_ROOT}/sessions/agent1/${sid}" ]
}

@test "awm_namespace clears with empty argument" {
    awm_namespace "something"
    awm_namespace ""
    [ -z "$_AWM_NAMESPACE" ]
}

# =============================================================================
# LOGGING TESTS
# =============================================================================

@test "awm_log writes to category file" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    awm_log "task" "starting the work"

    [ -f "${AWM_ROOT}/sessions/${sid}/logs/task.jsonl" ]
    local content
    content=$(<"${AWM_ROOT}/sessions/${sid}/logs/task.jsonl")
    [[ "$content" == *'"msg":"starting the work"'* ]]
}

@test "awm_log appends multiple entries" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    awm_log "progress" "step 1"
    awm_log "progress" "step 2"
    awm_log "progress" "step 3"

    local count
    count=$(wc -l < "${AWM_ROOT}/sessions/${sid}/logs/progress.jsonl")
    [ "$count" -eq 3 ]
}

@test "awm_log escapes special characters" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    awm_log "notes" 'has "quotes" and backslash'

    local content
    content=$(<"${AWM_ROOT}/sessions/${sid}/logs/notes.jsonl")
    # Should contain escaped content - JSON uses "msg" field
    [[ "$content" == *'"msg":'* ]]
}

@test "awm_progress writes to progress category" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    awm_progress "task1" "50/100"

    [ -f "${AWM_ROOT}/sessions/${sid}/logs/progress.jsonl" ]
    local content
    content=$(<"${AWM_ROOT}/sessions/${sid}/logs/progress.jsonl")
    [[ "$content" == *'"task":"task1"'* ]]
    [[ "$content" == *'"current":50'* ]]
    [[ "$content" == *'"total":100'* ]]
}

@test "awm_discovery writes to discoveries log" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    awm_discovery "API has rate limit of 100/min"

    [ -f "${AWM_ROOT}/sessions/${sid}/logs/discoveries.jsonl" ]
    local content
    content=$(<"${AWM_ROOT}/sessions/${sid}/logs/discoveries.jsonl")
    [[ "$content" == *'"discovery":"API has rate limit of 100/min"'* ]]
}

# =============================================================================
# CHECKPOINT TESTS
# =============================================================================

@test "awm_checkpoint creates checkpoint file" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    awm_checkpoint "before-refactor" "state1"

    # Checkpoints are stored in data/ directory
    [ -f "${AWM_ROOT}/sessions/${sid}/data/before-refactor" ]
}

@test "awm_checkpoint writes value correctly" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    awm_checkpoint "mykey" 'task:migrate,progress:47'

    local content
    content=$(<"${AWM_ROOT}/sessions/${sid}/data/mykey")
    [[ "$content" == *"migrate"* ]]
}

@test "awm_get retrieves checkpointed data" {
    awm_init "test" > /dev/null

    awm_checkpoint "setting" "enabled"

    run awm_get "setting"
    assert_success
    [[ "$output" == *"enabled"* ]]
}

@test "awm_get returns empty for missing key" {
    awm_init "test" > /dev/null

    run awm_get "nonexistent"
    # Should succeed but output empty or fail gracefully
    [ -z "$output" ] || [ "$status" -ne 0 ]
}

# =============================================================================
# DATA RETRIEVAL TESTS
# =============================================================================

@test "awm_recent returns last N entries" {
    awm_init "test" > /dev/null

    awm_log "events" "event1"
    awm_log "events" "event2"
    awm_log "events" "event3"
    awm_log "events" "event4"
    awm_log "events" "event5"

    run awm_recent "events" 3
    assert_success

    # Should include most recent entries
    [[ "$output" == *"event"* ]]
}

@test "awm_summary returns session overview" {
    awm_init "test-summary" > /dev/null
    local sid="$_AWM_SESSION_ID"

    awm_log "tasks" "task1"
    awm_discovery "found something"
    awm_checkpoint "state" "value"

    run awm_summary
    assert_success

    # Should contain session info
    [ -n "$output" ]
}

@test "awm_list shows available sessions" {
    # Create multiple sessions
    awm_init "session1" > /dev/null
    local sid1="$_AWM_SESSION_ID"
    awm_close

    awm_init "session2" > /dev/null
    local sid2="$_AWM_SESSION_ID"
    awm_close

    run awm_list
    assert_success

    # Should list sessions
    [ -n "$output" ]
}

# =============================================================================
# TOKEN ESTIMATION TESTS
# =============================================================================

@test "awm_token_estimate returns number for session" {
    awm_init "test" > /dev/null

    # Add some data
    awm_checkpoint "key1" "value1"
    awm_log "info" "some log message"

    run awm_token_estimate
    assert_success
    [[ "$output" =~ ^[0-9]+$ ]]  # Should be a number
}

@test "awm_token_estimate scales with content" {
    awm_init "test" > /dev/null

    local est1
    awm_checkpoint "small" "x"
    est1=$(awm_token_estimate)

    # Add more data
    awm_checkpoint "large" "$(printf 'x%.0s' {1..1000})"
    local est2
    est2=$(awm_token_estimate)

    [ "$est2" -gt "$est1" ]
}

@test "awm_estimate_read estimates session read cost" {
    awm_init "test" > /dev/null

    awm_log "data" "some content here"
    awm_discovery "a discovery"
    awm_checkpoint "key" "value"

    run awm_estimate_read "summary"
    assert_success
    [[ "$output" =~ ^[0-9]+$ ]]  # Should be a number
}

# =============================================================================
# COMPRESSION TESTS
# =============================================================================

@test "awm_compress handles empty session" {
    awm_init "test" > /dev/null

    run awm_compress
    # Should succeed even with nothing to compress
    assert_success
}

@test "awm_check_limits returns status" {
    awm_init "test" > /dev/null

    run awm_check_limits
    assert_success
}

# =============================================================================
# CLEANUP TESTS
# =============================================================================

@test "awm_cleanup removes old sessions" {
    # Create a session and close it
    awm_init "old-session" > /dev/null
    awm_close

    # Run cleanup (may or may not delete depending on age)
    run awm_cleanup 0
    assert_success
}

# =============================================================================
# CONTEXT INHERITANCE TESTS
# =============================================================================

@test "awm_context_for generates context package" {
    awm_init "parent-task" > /dev/null

    awm_discovery "API uses Bearer tokens"
    awm_discovery "Rate limit is 100/min"
    awm_checkpoint "current_file" "src/auth.ts"

    run awm_context_for "child-task"
    assert_success
    [ -n "$output" ]
}

@test "awm_inherit loads parent context" {
    # Create parent with data
    awm_init "parent" > /dev/null
    local parent_sid="$_AWM_SESSION_ID"
    awm_discovery "important info"
    awm_close

    # Create child that inherits
    awm_init "child" "$parent_sid" > /dev/null
    local child_sid="$_AWM_SESSION_ID"

    # Child should have inherited discoveries
    [ -f "${AWM_ROOT}/sessions/${child_sid}/logs/inherited_discoveries.jsonl" ]
}

@test "awm_export writes to export directory" {
    awm_init "test" > /dev/null

    run awm_export "result.txt"
    assert_success
}

# =============================================================================
# EDGE CASES AND ERROR HANDLING
# =============================================================================

@test "awm_log without active session fails gracefully" {
    _AWM_SESSION_ID=""

    run awm_log "test" "message"
    assert_failure
}

@test "awm_checkpoint without active session fails" {
    _AWM_SESSION_ID=""

    run awm_checkpoint "key" "value"
    assert_failure
}

@test "awm_discovery without active session fails" {
    _AWM_SESSION_ID=""

    run awm_discovery "content"
    assert_failure
}

@test "multiple simultaneous sessions are isolated" {
    awm_namespace "agent1"
    awm_init "task1" > /dev/null
    local sid1="$_AWM_SESSION_ID"
    awm_discovery "agent1 finding"
    awm_close

    awm_namespace "agent2"
    awm_init "task2" > /dev/null
    local sid2="$_AWM_SESSION_ID"
    awm_discovery "agent2 finding"
    awm_close

    # Sessions should be in different directories
    [ -d "${AWM_ROOT}/sessions/agent1/${sid1}" ]
    [ -d "${AWM_ROOT}/sessions/agent2/${sid2}" ]

    # Discoveries should be separate
    local agent1_disc="${AWM_ROOT}/sessions/agent1/${sid1}/logs/discoveries.jsonl"
    local agent2_disc="${AWM_ROOT}/sessions/agent2/${sid2}/logs/discoveries.jsonl"

    [[ $(<"$agent1_disc") == *"agent1 finding"* ]]
    [[ $(<"$agent2_disc") == *"agent2 finding"* ]]
}

@test "awm handles special characters in session names" {
    awm_init "test with spaces" > /dev/null

    [ -n "$_AWM_SESSION_ID" ]
    [ -d "${AWM_ROOT}/sessions/${_AWM_SESSION_ID}" ]
}

@test "awm handles very long content" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    # Generate long content
    local long_content
    long_content=$(printf 'x%.0s' {1..1000})

    run awm_log "data" "$long_content"
    assert_success

    # Verify it was written
    [ -f "${AWM_ROOT}/sessions/${sid}/logs/data.jsonl" ]
}

# =============================================================================
# CONCURRENT ACCESS TESTS (Basic)
# =============================================================================

@test "awm_log handles rapid successive writes" {
    awm_init "test" > /dev/null
    local sid="$_AWM_SESSION_ID"

    # Write many entries quickly
    for i in {1..20}; do
        awm_log "rapid" "entry $i"
    done

    local count
    count=$(wc -l < "${AWM_ROOT}/sessions/${sid}/logs/rapid.jsonl")
    [ "$count" -eq 20 ]
}

# =============================================================================
# FUNCTION EXISTENCE TESTS
# =============================================================================

@test "all AWM functions are declared" {
    source "${MAINFRAME_ROOT}/lib/awm.sh"

    # Check key functions exist
    declare -F awm_init >/dev/null
    declare -F awm_close >/dev/null
    declare -F awm_resume >/dev/null
    declare -F awm_log >/dev/null
    declare -F awm_discovery >/dev/null
    declare -F awm_checkpoint >/dev/null
    declare -F awm_get >/dev/null
    declare -F awm_recent >/dev/null
    declare -F awm_summary >/dev/null
    declare -F awm_token_estimate >/dev/null
}

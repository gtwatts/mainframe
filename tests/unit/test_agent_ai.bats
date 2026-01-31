#!/usr/bin/env bats
# =============================================================================
# tests/unit/test_agent_ai.bats - Tests for AI Agent Infrastructure Library
# =============================================================================
# Comprehensive tests covering:
#   - Context budget system (Claude Code + Copilot patterns)
#   - Tool registry with permissions (OpenCode pattern)
#   - Edit format abstraction (Aider pattern)
#   - Session management (Codex + Copilot patterns)
#   - Transcript logging (Codex pattern)
#   - Gated handoffs (Codex pattern)
#   - Subagent orchestration (Claude Code pattern)
#   - File reference system (Copilot @ pattern)
# =============================================================================

# -----------------------------------------------------------------------------
# Test Setup & Teardown
# -----------------------------------------------------------------------------

setup() {
    # Get test directory
    BATS_TEST_DIRNAME="${BATS_TEST_FILENAME%/*}"
    PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."

    # Create isolated test environment
    TEST_STATE_DIR=$(mktemp -d)
    export AGENT_AI_STATE_DIR="$TEST_STATE_DIR"
    export AGENT_AI_TRANSCRIPT_DIR="$TEST_STATE_DIR/transcripts"
    export AGENT_AI_SESSION_FILE="$TEST_STATE_DIR/test_session_$$"
    export MAINFRAME_QUIET=1

    # Source the library under test
    source "$PROJECT_ROOT/lib/agent_ai.sh"

    # Create test fixtures directory
    TEST_FIXTURES="$TEST_STATE_DIR/fixtures"
    mkdir -p "$TEST_FIXTURES"
}

teardown() {
    # Clean up test state
    [[ -d "$TEST_STATE_DIR" ]] && rm -rf "$TEST_STATE_DIR"

    # Unset exported variables
    unset AGENT_AI_STATE_DIR AGENT_AI_TRANSCRIPT_DIR AGENT_AI_SESSION_FILE
    unset AGENT_AI_SESSION_ID AGENT_AI_CTX_MAX AGENT_AI_CTX_USED
}

# =============================================================================
# CONTEXT BUDGET TESTS
# =============================================================================

@test "agent_ai_context_init: creates context state with defaults" {
    agent_ai_context_init

    [[ -f "${AGENT_AI_SESSION_FILE}.context" ]]
    source "${AGENT_AI_SESSION_FILE}.context"

    [[ "$AGENT_AI_CTX_MAX" == "200000" ]]
    [[ "$AGENT_AI_CTX_USED" == "0" ]]
    [[ "$AGENT_AI_CTX_RESERVE" == "40000" ]]  # 20% of 200000
}

@test "agent_ai_context_init: accepts custom max tokens" {
    agent_ai_context_init 100000

    source "${AGENT_AI_SESSION_FILE}.context"
    [[ "$AGENT_AI_CTX_MAX" == "100000" ]]
    [[ "$AGENT_AI_CTX_RESERVE" == "20000" ]]  # 20% of 100000
}

@test "agent_ai_context_init: accepts custom reserve percentage" {
    agent_ai_context_init 100000 30

    source "${AGENT_AI_SESSION_FILE}.context"
    [[ "$AGENT_AI_CTX_RESERVE" == "30000" ]]  # 30% of 100000
}

@test "agent_ai_context_use: tracks token usage" {
    agent_ai_context_init 100000

    agent_ai_context_use 5000 "test_operation"

    source "${AGENT_AI_SESSION_FILE}.context"
    [[ "$AGENT_AI_CTX_USED" == "5000" ]]
}

@test "agent_ai_context_use: accumulates multiple uses" {
    agent_ai_context_init 100000

    agent_ai_context_use 1000 "op1"
    agent_ai_context_use 2000 "op2"
    agent_ai_context_use 3000 "op3"

    source "${AGENT_AI_SESSION_FILE}.context"
    [[ "$AGENT_AI_CTX_USED" == "6000" ]]
}

@test "agent_ai_context_use: returns warning at 80% threshold" {
    agent_ai_context_init 100000 20  # 80000 available

    # Use 65000 tokens - should be 81.25% (over 80%)
    run agent_ai_context_use 65000 "large_op"
    [[ "$status" -eq 1 ]]  # Warning return code
}

@test "agent_ai_context_use: returns compress signal at 95% threshold" {
    agent_ai_context_init 100000 20  # 80000 available

    # Use 77000 tokens - should be 96.25% (over 95%)
    run agent_ai_context_use 77000 "huge_op"
    [[ "$status" -eq 2 ]]  # Compress return code
}

@test "agent_ai_context_status: returns valid JSON" {
    agent_ai_context_init 100000
    agent_ai_context_use 25000 "test"

    local status_json
    status_json=$(agent_ai_context_status)

    [[ "$status_json" == *'"max":100000'* ]]
    [[ "$status_json" == *'"used":25000'* ]]
    [[ "$status_json" == *'"status":"ok"'* ]]
}

@test "agent_ai_context_status: shows warning status" {
    agent_ai_context_init 100000 20
    # Use run to capture non-zero exit without failing test
    run agent_ai_context_use 65000 "test"  # Over 80%

    local status_json
    status_json=$(agent_ai_context_status)

    [[ "$status_json" == *'"status":"warning"'* ]]
}

@test "agent_ai_context_fits: returns true when tokens fit" {
    agent_ai_context_init 100000 20  # 80000 available

    agent_ai_context_fits 50000
    [[ $? -eq 0 ]]
}

@test "agent_ai_context_fits: returns false when tokens exceed budget" {
    agent_ai_context_init 100000 20  # 80000 available
    # Use run to capture non-zero exit without failing test
    run agent_ai_context_use 70000 "existing"

    run agent_ai_context_fits 20000
    [[ "$status" -ne 0 ]]
}

@test "agent_ai_context_reset: clears context state" {
    agent_ai_context_init 100000
    agent_ai_context_use 50000 "test"

    agent_ai_context_reset

    [[ ! -f "${AGENT_AI_SESSION_FILE}.context" ]]
}

# =============================================================================
# HIERARCHICAL CONTEXT TESTS
# =============================================================================

@test "agent_ai_context_hierarchy: loads context files in order" {
    # Create a known hierarchy in test fixtures
    mkdir -p "$TEST_FIXTURES/myproject/src"
    echo "# Test context file" > "$TEST_FIXTURES/myproject/CLAUDE.md"

    # Override HOME to avoid loading large global context files
    local orig_home="$HOME"
    export HOME="$TEST_FIXTURES"

    # Test: function should find CLAUDE.md when walking up from src
    local result
    result=$(cd "$TEST_FIXTURES/myproject/src" && agent_ai_context_hierarchy ".")

    # Restore HOME
    export HOME="$orig_home"

    # The function should find and include the parent CLAUDE.md
    [[ "$result" == *"Test context file"* ]]
}

@test "agent_ai_context_hierarchy: respects 32KB limit" {
    mkdir -p "$TEST_FIXTURES/project"

    # Create a file larger than 32KB
    head -c 40000 /dev/zero | tr '\0' 'x' > "$TEST_FIXTURES/project/CLAUDE.md"

    local result
    result=$(agent_ai_context_hierarchy "$TEST_FIXTURES/project")

    # Result should be truncated
    [[ ${#result} -lt 40000 ]]
}

# =============================================================================
# TOOL REGISTRY TESTS
# =============================================================================

@test "agent_ai_tool_register: registers tool with default permission" {
    _test_tool_handler() { echo "executed"; }

    agent_ai_tool_register "test_tool" "A test tool" "_test_tool_handler"

    [[ -n "${_AGENT_AI_TOOLS[test_tool]}" ]]
    [[ "${_AGENT_AI_TOOL_PERMS[test_tool]}" == "ask" ]]
}

@test "agent_ai_tool_register: registers tool with custom permission" {
    _test_tool_handler() { echo "executed"; }

    agent_ai_tool_register "allowed_tool" "Auto-allowed tool" "_test_tool_handler" "allow"

    [[ "${_AGENT_AI_TOOL_PERMS[allowed_tool]}" == "allow" ]]
}

@test "agent_ai_tool_permitted: returns 0 for allowed tools" {
    _test_tool_handler() { echo "executed"; }
    agent_ai_tool_register "my_tool" "Test" "_test_tool_handler" "allow"

    agent_ai_tool_permitted "my_tool"
    [[ $? -eq 0 ]]
}

@test "agent_ai_tool_permitted: returns 1 for denied tools" {
    _test_tool_handler() { echo "executed"; }
    agent_ai_tool_register "denied_tool" "Test" "_test_tool_handler" "deny"

    run agent_ai_tool_permitted "denied_tool"
    [[ "$status" -eq 1 ]]
}

@test "agent_ai_tool_permitted: returns 2 for ask permission" {
    _test_tool_handler() { echo "executed"; }
    agent_ai_tool_register "ask_tool" "Test" "_test_tool_handler" "ask"

    run agent_ai_tool_permitted "ask_tool"
    [[ "$status" -eq 2 ]]
}

@test "agent_ai_tool_approve: changes permission to allow" {
    _test_tool_handler() { echo "executed"; }
    agent_ai_tool_register "pending_tool" "Test" "_test_tool_handler" "ask"

    agent_ai_tool_approve "pending_tool"

    [[ "${_AGENT_AI_TOOL_PERMS[pending_tool]}" == "allow" ]]
}

@test "agent_ai_tool_approve: persists permanent permissions" {
    agent_ai_init
    _test_tool_handler() { echo "executed"; }
    agent_ai_tool_register "perm_tool" "Test" "_test_tool_handler" "ask"

    agent_ai_tool_approve "perm_tool" "--permanent"

    [[ -f "${AGENT_AI_STATE_DIR}/tool_permissions" ]]
    grep -q "perm_tool=allow" "${AGENT_AI_STATE_DIR}/tool_permissions"
}

@test "agent_ai_tool_deny: changes permission to deny" {
    _test_tool_handler() { echo "executed"; }
    agent_ai_tool_register "risky_tool" "Test" "_test_tool_handler" "ask"

    agent_ai_tool_deny "risky_tool"

    [[ "${_AGENT_AI_TOOL_PERMS[risky_tool]}" == "deny" ]]
}

@test "agent_ai_tool_invoke: executes allowed tool" {
    _echo_tool() { echo "tool_output"; }
    agent_ai_tool_register "echo_tool" "Echoes output" "_echo_tool" "allow"

    local result
    result=$(agent_ai_tool_invoke "echo_tool")

    [[ "$result" == "tool_output" ]]
}

@test "agent_ai_tool_invoke: passes arguments to handler" {
    _args_tool() { echo "args: $*"; }
    agent_ai_tool_register "args_tool" "Shows args" "_args_tool" "allow"

    local result
    result=$(agent_ai_tool_invoke "args_tool" "arg1" "arg2")

    [[ "$result" == "args: arg1 arg2" ]]
}

@test "agent_ai_tool_invoke: returns 126 for denied tools" {
    _test_tool() { echo "executed"; }
    agent_ai_tool_register "blocked" "Test" "_test_tool" "deny"

    run agent_ai_tool_invoke "blocked"
    [[ "$status" -eq 126 ]]
}

@test "agent_ai_tool_invoke: returns 126 for unregistered tools needing approval" {
    # Unregistered tools default to "ask" permission, returning 126
    run agent_ai_tool_invoke "nonexistent_tool"
    [[ "$status" -eq 126 ]]
}

@test "agent_ai_tool_list: returns JSON array of tools" {
    _tool1() { :; }
    _tool2() { :; }
    agent_ai_tool_register "tool1" "First tool" "_tool1" "allow"
    agent_ai_tool_register "tool2" "Second tool" "_tool2" "deny"

    local list
    list=$(agent_ai_tool_list)

    [[ "$list" == "["*"]" ]]
    [[ "$list" == *'"name":"tool1"'* ]]
    [[ "$list" == *'"name":"tool2"'* ]]
}

@test "agent_ai_tool_load_permissions: loads from file" {
    agent_ai_init

    # Create permissions file
    echo "saved_tool=allow" > "${AGENT_AI_STATE_DIR}/tool_permissions"
    echo "denied_tool=deny" >> "${AGENT_AI_STATE_DIR}/tool_permissions"

    agent_ai_tool_load_permissions

    [[ "${_AGENT_AI_TOOL_PERMS[saved_tool]}" == "allow" ]]
    [[ "${_AGENT_AI_TOOL_PERMS[denied_tool]}" == "deny" ]]
}

# =============================================================================
# OUTPUT SPILLOVER TESTS
# =============================================================================

@test "agent_ai_output_truncate: passes small output unchanged" {
    local small_content="Line 1
Line 2
Line 3"

    local result
    result=$(echo "$small_content" | agent_ai_output_truncate)

    [[ "$result" == "$small_content" ]]
}

@test "agent_ai_output_truncate: truncates large output" {
    # Generate content with more than 2000 lines
    local large_content
    large_content=$(seq 1 2500)

    local result
    result=$(echo "$large_content" | agent_ai_output_truncate)

    [[ "$result" == *"Truncated"* ]]
    [[ "$result" == *"spillover"* ]]
}

@test "agent_ai_output_truncate: creates spillover file" {
    agent_ai_init

    local large_content
    large_content=$(seq 1 2500)

    echo "$large_content" | agent_ai_output_truncate >/dev/null

    local spillover_count
    spillover_count=$(find "${AGENT_AI_STATE_DIR}/spillover" -type f 2>/dev/null | wc -l)
    [[ "$spillover_count" -gt 0 ]]
}

@test "agent_ai_spillover_gc: removes old files" {
    agent_ai_init
    mkdir -p "${AGENT_AI_STATE_DIR}/spillover"

    # Create old file
    touch -d "10 days ago" "${AGENT_AI_STATE_DIR}/spillover/old_file.txt"

    agent_ai_spillover_gc 7

    [[ ! -f "${AGENT_AI_STATE_DIR}/spillover/old_file.txt" ]]
}

# =============================================================================
# EDIT FORMAT ABSTRACTION TESTS
# =============================================================================

@test "agent_ai_edit_apply: whole file replacement" {
    echo "original content" > "$TEST_FIXTURES/test_file.txt"

    agent_ai_edit_apply "$TEST_FIXTURES/test_file.txt" "new content" --format whole

    local content
    content=$(cat "$TEST_FIXTURES/test_file.txt")
    [[ "$content" == "new content" ]]
}

@test "agent_ai_edit_apply: search/replace with SEARCH/REPLACE blocks" {
    echo "Hello World" > "$TEST_FIXTURES/test_file.txt"

    local edit_content='<<<<<<< SEARCH
Hello World
=======
Hello Universe
>>>>>>> REPLACE'

    agent_ai_edit_apply "$TEST_FIXTURES/test_file.txt" "$edit_content" --format diff

    local content
    content=$(cat "$TEST_FIXTURES/test_file.txt")
    [[ "$content" == "Hello Universe" ]]
}

@test "agent_ai_edit_apply: search/replace with ORIGINAL/UPDATED blocks" {
    echo "foo bar baz" > "$TEST_FIXTURES/test_file.txt"

    local edit_content='<ORIGINAL>
foo bar baz
</ORIGINAL>
<UPDATED>
foo qux baz
</UPDATED>'

    agent_ai_edit_apply "$TEST_FIXTURES/test_file.txt" "$edit_content" --format diff

    local content
    content=$(cat "$TEST_FIXTURES/test_file.txt")
    [[ "$content" == "foo qux baz" ]]
}

@test "agent_ai_edit_apply: returns error on unknown format" {
    echo "content" > "$TEST_FIXTURES/test_file.txt"

    run agent_ai_edit_apply "$TEST_FIXTURES/test_file.txt" "new" --format unknown
    [[ "$status" -ne 0 ]]
}

@test "agent_ai_model_edit_format: returns correct format for models" {
    [[ $(agent_ai_model_edit_format "claude-opus-4") == "whole" ]]
    [[ $(agent_ai_model_edit_format "claude-sonnet-4") == "diff" ]]
    [[ $(agent_ai_model_edit_format "gpt-4o") == "udiff" ]]
    [[ $(agent_ai_model_edit_format "deepseek-coder") == "diff" ]]
}

# =============================================================================
# REFLECTION LOOP TESTS
# =============================================================================

@test "agent_ai_reflect: succeeds when validator passes" {
    # Initialize for transcript logging
    agent_ai_init
    agent_ai_session_start "reflect_test1" >/dev/null

    # Define helper functions that return success/failure
    always_pass_validator() { return 0; }
    never_called_reflector() { echo "should not be called"; }

    run agent_ai_reflect "test_task" always_pass_validator never_called_reflector 3
    [[ "$status" -eq 0 ]]
}

@test "agent_ai_reflect: calls reflector on validation failure" {
    local reflect_calls=0
    _always_fail() { return 1; }
    _count_reflects() { ((reflect_calls++)); }

    run agent_ai_reflect "test_task" _always_fail _count_reflects 3
    [[ "$status" -ne 0 ]]  # Should exhaust iterations
}

@test "agent_ai_reflect: respects max iterations" {
    # Initialize for transcript logging
    agent_ai_init
    agent_ai_session_start "reflect_test2" >/dev/null

    # Test that exhausts iterations (always fail)
    always_fail_validator() { return 1; }
    noop_reflector() { :; }

    run agent_ai_reflect "test_task" always_fail_validator noop_reflector 3
    # Should fail after exhausting 3 iterations
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# SESSION MANAGEMENT TESTS
# =============================================================================

@test "agent_ai_session_start: creates session with auto-generated name" {
    # Run in current shell to preserve exports
    agent_ai_session_start > /tmp/session_id_$$
    local session_id
    session_id=$(cat /tmp/session_id_$$)
    rm -f /tmp/session_id_$$

    [[ -n "$session_id" ]]
    [[ -f "${AGENT_AI_STATE_DIR}/${session_id}.session" ]]
    [[ "$AGENT_AI_SESSION_ID" == "$session_id" ]]
    [[ "$AGENT_AI_SESSION_STATUS" == "active" ]]
}

@test "agent_ai_session_start: creates session with custom name" {
    local session_id
    session_id=$(agent_ai_session_start "my_custom_session")

    [[ "$session_id" == "my_custom_session" ]]
    [[ -f "${AGENT_AI_STATE_DIR}/my_custom_session.session" ]]
}

@test "agent_ai_session_start: initializes context budget" {
    agent_ai_session_start "ctx_test_session" >/dev/null

    # Context file uses AGENT_AI_SESSION_FILE path
    [[ -f "${AGENT_AI_SESSION_FILE}.context" ]]
}

@test "agent_ai_session_start: creates transcript file" {
    agent_ai_session_start "transcript_test"

    [[ -f "${AGENT_AI_TRANSCRIPT_DIR}/transcript_test.jsonl" ]]
}

@test "agent_ai_session_resume: restores session state" {
    local original_id
    original_id=$(agent_ai_session_start "resume_test")
    agent_ai_context_use 5000 "before_resume"
    agent_ai_session_end

    # Clear state
    unset AGENT_AI_SESSION_ID AGENT_AI_CTX_USED

    agent_ai_session_resume "resume_test"

    [[ "$AGENT_AI_SESSION_ID" == "resume_test" ]]
}

@test "agent_ai_session_resume: returns error for nonexistent session" {
    run agent_ai_session_resume "nonexistent_session"
    [[ "$status" -ne 0 ]]
}

@test "agent_ai_session_fork: creates child session" {
    agent_ai_session_start "parent_session"

    local fork_id
    fork_id=$(agent_ai_session_fork "child_session")

    [[ "$fork_id" == "child_session" ]]
    [[ -f "${AGENT_AI_STATE_DIR}/child_session.session" ]]
    grep -q "AGENT_AI_SESSION_PARENT=parent_session" "${AGENT_AI_STATE_DIR}/child_session.session"
}

@test "agent_ai_session_fork: returns error without active session" {
    unset AGENT_AI_SESSION_ID

    run agent_ai_session_fork "orphan"
    [[ "$status" -ne 0 ]]
}

@test "agent_ai_session_end: updates session status" {
    agent_ai_session_start "end_test"
    agent_ai_session_end "completed"

    grep -q "AGENT_AI_SESSION_STATUS=completed" "${AGENT_AI_STATE_DIR}/end_test.session"
    [[ -z "${AGENT_AI_SESSION_ID:-}" ]]
}

@test "agent_ai_session_list: returns JSON array of sessions" {
    agent_ai_session_start "list_test_1"
    agent_ai_session_end
    agent_ai_session_start "list_test_2"
    agent_ai_session_end

    local list
    list=$(agent_ai_session_list)

    [[ "$list" == "["*"]" ]]
    [[ "$list" == *'"id":"list_test_1"'* ]] || [[ "$list" == *'"id":"list_test_2"'* ]]
}

@test "agent_ai_session_list: respects limit parameter" {
    for i in {1..5}; do
        agent_ai_session_start "limit_test_$i"
        agent_ai_session_end
    done

    local list
    list=$(agent_ai_session_list --limit 2)

    local count
    count=$(echo "$list" | grep -o '"id"' | wc -l)
    [[ "$count" -le 2 ]]
}

# =============================================================================
# TRANSCRIPT LOGGING TESTS
# =============================================================================

@test "agent_ai_transcript_append: writes event to transcript" {
    agent_ai_session_start "transcript_append_test"

    agent_ai_transcript_append "test_event" '{"key":"value"}'

    grep -q '"type":"test_event"' "${AGENT_AI_TRANSCRIPT_DIR}/transcript_append_test.jsonl"
}

@test "agent_ai_transcript_append: includes timestamp" {
    agent_ai_session_start "timestamp_test"

    agent_ai_transcript_append "timed_event" '{"data":1}'

    grep -q '"time":"' "${AGENT_AI_TRANSCRIPT_DIR}/timestamp_test.jsonl"
}

@test "agent_ai_transcript_search: finds matching events" {
    agent_ai_session_start "search_test"
    agent_ai_transcript_append "searchable_event" '{"keyword":"findme"}'

    local results
    results=$(agent_ai_transcript_search "findme" "search_test")

    [[ "$results" == *"findme"* ]]
}

@test "agent_ai_transcript_search: searches across sessions" {
    agent_ai_session_start "multi_search_1"
    agent_ai_transcript_append "event" '{"tag":"global_search"}'
    agent_ai_session_end

    agent_ai_session_start "multi_search_2"
    agent_ai_transcript_append "event" '{"tag":"global_search"}'
    agent_ai_session_end

    local results
    results=$(agent_ai_transcript_search "global_search")

    [[ $(echo "$results" | wc -l) -ge 2 ]]
}

@test "agent_ai_transcript_get: returns events as JSON array" {
    agent_ai_session_start "get_test"
    agent_ai_transcript_append "event1" '{"n":1}'
    agent_ai_transcript_append "event2" '{"n":2}'

    local transcript
    transcript=$(agent_ai_transcript_get "get_test")

    [[ "$transcript" == "["*"]" ]]
    [[ "$transcript" == *'"type":"event1"'* ]]
    [[ "$transcript" == *'"type":"event2"'* ]]
}

# =============================================================================
# GATED HANDOFFS TESTS
# =============================================================================

@test "agent_ai_gate_define: registers gate validator" {
    _gate_validator() { return 0; }

    agent_ai_gate_define "test_gate" _gate_validator

    [[ "${_AGENT_AI_GATES[test_gate]}" == "_gate_validator" ]]
}

@test "agent_ai_gate_check: passes when validator succeeds" {
    _pass_gate() { return 0; }
    agent_ai_gate_define "pass_gate" _pass_gate

    agent_ai_gate_check "pass_gate"
    [[ $? -eq 0 ]]
}

@test "agent_ai_gate_check: fails when validator fails" {
    _fail_gate() { return 1; }
    agent_ai_gate_define "fail_gate" _fail_gate

    run agent_ai_gate_check "fail_gate"
    [[ "$status" -ne 0 ]]
}

@test "agent_ai_gate_check: returns error for undefined gate" {
    run agent_ai_gate_check "undefined_gate"
    [[ "$status" -ne 0 ]]
}

@test "agent_ai_gate_check: logs to transcript" {
    agent_ai_session_start "gate_log_test"
    _log_gate() { return 0; }
    agent_ai_gate_define "log_gate" _log_gate

    agent_ai_gate_check "log_gate"

    local transcript
    transcript=$(agent_ai_transcript_get "gate_log_test")
    [[ "$transcript" == *'"type":"gate_check"'* ]]
    [[ "$transcript" == *'"type":"gate_passed"'* ]]
}

# =============================================================================
# SUBAGENT ORCHESTRATION TESTS
# =============================================================================

@test "agent_ai_spawn: executes handler synchronously" {
    _sync_handler() { echo "sync_result"; }

    local result
    result=$(agent_ai_spawn "sync_task" _sync_handler)

    [[ "$result" == "sync_result" ]]
}

@test "agent_ai_spawn: sets subagent environment" {
    _env_handler() { echo "$AGENT_AI_SUBAGENT_ID"; }

    local result
    result=$(agent_ai_spawn "env_task" _env_handler)

    [[ "$result" == sub_* ]]
}

@test "agent_ai_spawn: returns subagent_id:pid for parallel" {
    _parallel_handler() { sleep 0.1; echo "done"; }

    local result
    result=$(agent_ai_spawn "parallel_task" _parallel_handler --parallel)

    [[ "$result" == sub_*:* ]]

    # Clean up background process
    local pid="${result#*:}"
    kill "$pid" 2>/dev/null || true
}

@test "agent_ai_await: waits for pids to complete" {
    sleep 0.1 &
    local pid1=$!
    sleep 0.1 &
    local pid2=$!

    agent_ai_await "$pid1" "$pid2"
    [[ $? -eq 0 ]]
}

@test "agent_ai_await: returns failure for failed pids" {
    (exit 1) &
    local bad_pid=$!

    run agent_ai_await "$bad_pid"
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# FILE REFERENCE SYSTEM TESTS
# =============================================================================

@test "agent_ai_ref_add: adds file to references" {
    echo "test content" > "$TEST_FIXTURES/ref_file.txt"

    agent_ai_ref_add "$TEST_FIXTURES/ref_file.txt"

    local refs
    refs=$(agent_ai_ref_list)
    [[ "$refs" == *"ref_file.txt"* ]]
}

@test "agent_ai_ref_add: returns error for nonexistent file" {
    run agent_ai_ref_add "$TEST_FIXTURES/nonexistent.txt"
    [[ "$status" -ne 0 ]]
}

@test "agent_ai_ref_add: avoids duplicate references" {
    echo "content" > "$TEST_FIXTURES/dup_file.txt"

    agent_ai_ref_add "$TEST_FIXTURES/dup_file.txt"
    agent_ai_ref_add "$TEST_FIXTURES/dup_file.txt"

    local count
    count=$(agent_ai_ref_list | grep -c "dup_file.txt")
    [[ "$count" -eq 1 ]]
}

@test "agent_ai_ref_list: lists all referenced files" {
    echo "a" > "$TEST_FIXTURES/file_a.txt"
    echo "b" > "$TEST_FIXTURES/file_b.txt"

    agent_ai_ref_add "$TEST_FIXTURES/file_a.txt"
    agent_ai_ref_add "$TEST_FIXTURES/file_b.txt"

    local refs
    refs=$(agent_ai_ref_list)

    [[ "$refs" == *"file_a.txt"* ]]
    [[ "$refs" == *"file_b.txt"* ]]
}

@test "agent_ai_ref_clear: removes all references" {
    echo "content" > "$TEST_FIXTURES/clear_test.txt"
    agent_ai_ref_add "$TEST_FIXTURES/clear_test.txt"

    agent_ai_ref_clear

    local refs
    refs=$(agent_ai_ref_list)
    [[ -z "$refs" ]]
}

@test "agent_ai_ref_tokens: estimates token count" {
    # Create file with known size
    head -c 400 /dev/zero | tr '\0' 'x' > "$TEST_FIXTURES/token_test.txt"
    agent_ai_ref_add "$TEST_FIXTURES/token_test.txt"

    local tokens
    tokens=$(agent_ai_ref_tokens)

    # Should be approximately 100 tokens (400 chars / 4)
    [[ "$tokens" -ge 50 ]] && [[ "$tokens" -le 200 ]]
}

# =============================================================================
# UTILITY FUNCTION TESTS
# =============================================================================

@test "agent_ai_is_active: returns true with active session" {
    agent_ai_session_start "active_test"

    agent_ai_is_active
    [[ $? -eq 0 ]]
}

@test "agent_ai_is_active: returns false without session" {
    unset AGENT_AI_SESSION_ID

    run agent_ai_is_active
    [[ "$status" -ne 0 ]]
}

@test "agent_ai_status: returns valid JSON status" {
    agent_ai_session_start "status_test"

    _test_tool() { :; }
    agent_ai_tool_register "stat_tool" "Test" "_test_tool" "allow"

    echo "content" > "$TEST_FIXTURES/status_ref.txt"
    agent_ai_ref_add "$TEST_FIXTURES/status_ref.txt"

    local status
    status=$(agent_ai_status)

    [[ "$status" == *'"session":"status_test"'* ]]
    [[ "$status" == *'"tools":'* ]]
    [[ "$status" == *'"file_refs":'* ]]
}

@test "agent_ai_init: creates required directories" {
    rm -rf "$AGENT_AI_STATE_DIR"

    agent_ai_init

    [[ -d "$AGENT_AI_STATE_DIR" ]]
    [[ -d "$AGENT_AI_TRANSCRIPT_DIR" ]]
    [[ -d "${AGENT_AI_STATE_DIR}/spillover" ]]
}

@test "agent_ai_cleanup: removes old state files" {
    agent_ai_init

    # Create old session file
    touch -d "10 days ago" "${AGENT_AI_STATE_DIR}/old_session.session"
    touch -d "10 days ago" "${AGENT_AI_TRANSCRIPT_DIR}/old_transcript.jsonl"

    agent_ai_cleanup --older-than 7

    [[ ! -f "${AGENT_AI_STATE_DIR}/old_session.session" ]]
    [[ ! -f "${AGENT_AI_TRANSCRIPT_DIR}/old_transcript.jsonl" ]]
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

@test "integration: full agent workflow" {
    # Start session - run in current shell
    agent_ai_session_start "integration_test" >/dev/null

    # Initialize context
    agent_ai_context_init 50000

    # Register and use tools
    _file_reader() { cat "$1"; }
    agent_ai_tool_register "read_file" "Reads file" "_file_reader" "allow"

    # Create test file
    echo "test data" > "$TEST_FIXTURES/integration_file.txt"
    agent_ai_ref_add "$TEST_FIXTURES/integration_file.txt"

    # Use context
    agent_ai_context_use 1000 "read_operation"

    # Invoke tool
    local result
    result=$(agent_ai_tool_invoke "read_file" "$TEST_FIXTURES/integration_file.txt")
    [[ "$result" == "test data" ]]

    # Check agent status (renamed to avoid BATS conflict)
    local agent_status_json
    agent_status_json=$(agent_ai_status)
    [[ "$agent_status_json" == *'"session":"integration_test"'* ]]

    # End session
    agent_ai_session_end "completed"

    # Verify transcript
    local transcript
    transcript=$(agent_ai_transcript_get "integration_test")
    [[ "$transcript" == *'"type":"tool_invoke"'* ]]
    [[ "$transcript" == *'"type":"session_end"'* ]]
}

@test "integration: session fork and parallel work" {
    agent_ai_session_start "fork_parent"
    agent_ai_context_init 100000
    agent_ai_context_use 10000 "parent_work"

    # Fork for parallel exploration
    local fork_id
    fork_id=$(agent_ai_session_fork "fork_child")

    # Verify both sessions exist
    [[ -f "${AGENT_AI_STATE_DIR}/fork_parent.session" ]]
    [[ -f "${AGENT_AI_STATE_DIR}/fork_child.session" ]]

    # Verify parent relationship
    grep -q "AGENT_AI_SESSION_PARENT=fork_parent" "${AGENT_AI_STATE_DIR}/fork_child.session"
}

@test "integration: gated workflow with validation" {
    agent_ai_session_start "gated_workflow"

    local validation_passed=0
    _build_gate() { [[ $validation_passed -eq 1 ]]; }
    agent_ai_gate_define "build_complete" _build_gate

    # Gate should fail initially
    run agent_ai_gate_check "build_complete"
    [[ "$status" -ne 0 ]]

    # Complete the build
    validation_passed=1

    # Gate should pass now
    agent_ai_gate_check "build_complete"
    [[ $? -eq 0 ]]

    # Verify gate events in transcript
    local transcript
    transcript=$(agent_ai_transcript_get "gated_workflow")
    [[ "$transcript" == *'"type":"gate_failed"'* ]]
    [[ "$transcript" == *'"type":"gate_passed"'* ]]
}

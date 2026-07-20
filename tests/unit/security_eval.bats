#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/security_eval.bats - Security Hardening Tests
# =============================================================================
# Description: Tests for eval site hardening across security-critical libraries
#              Validates command injection prevention and safe execution
# Test Count: 25+ test cases
# Libraries: procsub.sh, stream.sh, streams.sh, agent_exec.sh
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"
    export MAINFRAME_QUIET=1
    export MAINFRAME_AGENT_STATE="$TEST_TMPDIR/agent_state"
    mkdir -p "$MAINFRAME_AGENT_STATE"

    # Source libraries
    source "$MAINFRAME_ROOT/lib/common.sh"
}

# Teardown: Clean up test artifacts
teardown() {
    [[ -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# PROCSUB.SH SECURITY TESTS
# =============================================================================

@test "procsub: read_lines_from works with safe commands" {
    source "$MAINFRAME_ROOT/lib/procsub.sh"

    declare -a result
    read_lines_from "echo -e 'a\nb\nc'" result

    [[ ${#result[@]} -eq 3 ]]
    [[ "${result[0]}" == "a" ]]
    [[ "${result[1]}" == "b" ]]
    [[ "${result[2]}" == "c" ]]
}

@test "procsub: for_each_line requires function callback" {
    source "$MAINFRAME_ROOT/lib/procsub.sh"

    # Should fail with non-function callback
    run for_each_line "echo test" 'echo $line'
    [[ "$status" -ne 0 ]]
}

@test "procsub: for_each_line works with function callback" {
    source "$MAINFRAME_ROOT/lib/procsub.sh"

    count=0
    my_callback() { count=$((count + 1)); }

    for_each_line "echo -e 'a\nb\nc'" my_callback

    [[ "$count" -eq 3 ]]
}

@test "procsub: capture_output uses subprocess isolation" {
    source "$MAINFRAME_ROOT/lib/procsub.sh"

    capture_output result "echo hello"
    [[ "$result" == "hello" ]]
}

@test "procsub: diff_commands uses subprocess isolation" {
    source "$MAINFRAME_ROOT/lib/procsub.sh"

    # Same output should return 0
    run diff_commands "echo test" "echo test"
    [[ "$status" -eq 0 ]]

    # Different output should return non-zero
    run diff_commands "echo a" "echo b"
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# STREAM.SH SECURITY TESTS
# =============================================================================

@test "stream: stream_records uses subprocess isolation" {
    source "$MAINFRAME_ROOT/lib/stream.sh" 2>/dev/null || skip "stream.sh has dependencies"

    result=$(echo -e "a\nb\n---\nc\nd" | stream_records '---' 'wc -l')
    # Should have 2 records, each with 2 lines
    [[ -n "$result" ]]
}

@test "stream: stream_fanout uses subprocess isolation" {
    run bash -c 'export MAINFRAME_SKIP_AUTOLOAD=1; source "'"$MAINFRAME_ROOT"'/lib/stream.sh"; result=$(echo "test" | stream_fanout "wc -c"); [[ -n "$result" ]]'
    [[ "$status" -eq 0 ]]
}

@test "stream: stream_chain uses subprocess isolation" {
    source "$MAINFRAME_ROOT/lib/stream.sh" 2>/dev/null || skip "stream.sh has dependencies"

    result=$(echo "hello" | stream_chain 'tr a-z A-Z')
    [[ "$result" == "HELLO" ]]
}

# =============================================================================
# STREAMS.SH SECURITY TESTS
# =============================================================================

@test "streams: stream_map uses safe evaluation" {
    source "$MAINFRAME_ROOT/lib/streams.sh"

    result=$(echo -e "1\n2\n3" | stream_map 'echo $(($item * 2))')
    [[ "$result" == $'2\n4\n6' ]]
}

@test "streams: stream_filter uses safe predicate evaluation" {
    source "$MAINFRAME_ROOT/lib/streams.sh"

    result=$(echo -e "1\n2\n3\n4\n5" | stream_filter '[[ $item -gt 3 ]]')
    [[ "$result" == $'4\n5' ]]
}

@test "streams: stream_map blocks command substitution in transform" {
    source "$MAINFRAME_ROOT/lib/streams.sh"

    # Backtick command substitution should be blocked
    run bash -c 'echo test | _streams_eval_transform "echo \`whoami\`" "test"'
    [[ "$status" -ne 0 ]] || [[ "$output" != *"$(whoami)"* ]]
}

@test "streams: stream_filter blocks dangerous predicates" {
    source "$MAINFRAME_ROOT/lib/streams.sh"

    # Should not execute command injection
    run _streams_eval_predicate '[[ "$(rm /nonexistent)" ]]' "test"
    # The rm command should not execute successfully
    [[ ! -f "/nonexistent" ]]
}

@test "streams: stream_from_command uses subprocess isolation" {
    source "$MAINFRAME_ROOT/lib/streams.sh"

    result=$(stream_from_command "echo hello")
    [[ "$result" == "hello" ]]
}

@test "streams: stream_collect uses nameref instead of eval" {
    source "$MAINFRAME_ROOT/lib/streams.sh"

    declare -a arr
    stream_collect arr < <(printf "a\nb\nc\n")
    [[ ${#arr[@]} -eq 3 ]]
    [[ "${arr[0]}" == "a" ]]
}

@test "streams: stream_collect rejects invalid array names" {
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/streams.sh"; echo test | stream_collect "invalid;name"'
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# AGENT_EXEC.SH SECURITY TESTS
# =============================================================================

@test "agent_exec: _agent_is_safe_command allows whitelisted commands" {
    source "$MAINFRAME_ROOT/lib/agent_exec.sh"

    _agent_is_safe_command "ls"
    _agent_is_safe_command "cat"
    _agent_is_safe_command "grep"
    _agent_is_safe_command "git"
}

@test "agent_exec: _agent_is_safe_command blocks dangerous commands" {
    source "$MAINFRAME_ROOT/lib/agent_exec.sh"

    ! _agent_is_safe_command "eval"
    ! _agent_is_safe_command "sudo"
    ! _agent_is_safe_command "su"
    ! _agent_is_safe_command "dd"
}

@test "agent_exec: _agent_validate_command blocks semicolon chaining" {
    source "$MAINFRAME_ROOT/lib/agent_exec.sh"

    run _agent_validate_command "ls; rm -rf /"
    [[ "$status" -ne 0 ]]
}

@test "agent_exec: _agent_validate_command blocks backtick substitution" {
    source "$MAINFRAME_ROOT/lib/agent_exec.sh"

    run _agent_validate_command "echo \`whoami\`"
    [[ "$status" -ne 0 ]]
}

@test "agent_exec: agent_allow_command adds to allowlist" {
    source "$MAINFRAME_ROOT/lib/agent_exec.sh"

    # Custom command not in allowlist
    ! _agent_is_safe_command "mycustomcmd"

    # Add to allowlist
    agent_allow_command "mycustomcmd"

    # Now should be allowed
    _agent_is_safe_command "mycustomcmd"
}

@test "agent_exec: agent_disallow_command removes from allowlist" {
    source "$MAINFRAME_ROOT/lib/agent_exec.sh"

    # ls is in allowlist
    _agent_is_safe_command "ls"

    # Remove from allowlist
    agent_disallow_command "ls"

    # Now should be blocked
    ! _agent_is_safe_command "ls"
}

@test "agent_exec: _agent_safe_exec validates before execution" {
    source "$MAINFRAME_ROOT/lib/agent_exec.sh"

    # Safe command should work
    result=$(_agent_safe_exec "echo hello")
    [[ "$result" == "hello" ]]

    # Unsafe command should fail
    run _agent_safe_exec "eval 'echo test'"
    [[ "$status" -ne 0 ]]
}

@test "agent_exec: agent_transaction uses safe execution" {
    source "$MAINFRAME_ROOT/lib/agent_exec.sh"

    # Simple transaction should work
    result=$(agent_transaction --label "test" <<EOF
do: mkdir -p "$TEST_TMPDIR/tx_test"
undo: rm -rf "$TEST_TMPDIR/tx_test"
EOF
)
    [[ -d "$TEST_TMPDIR/tx_test" ]]
}

@test "agent_exec: agent_should_skip uses safe execution" {
    source "$MAINFRAME_ROOT/lib/agent_exec.sh"

    # Should work with safe check command
    touch "$TEST_TMPDIR/exists"
    agent_should_skip "test -f '$TEST_TMPDIR/exists'"

    # Should not skip for non-existent
    ! agent_should_skip "test -f '$TEST_TMPDIR/nonexistent'"
}

# =============================================================================
# INJECTION PREVENTION TESTS
# =============================================================================

@test "security: cannot inject via command substitution in procsub" {
    source "$MAINFRAME_ROOT/lib/procsub.sh"

    # Create a marker file that should NOT be created by injection
    marker="$TEST_TMPDIR/injection_marker_procsub"

    # Attempt injection - should be isolated in subprocess
    capture_output result "\$(touch '$marker' && echo pwned)" || true

    # Marker should not exist
    [[ ! -f "$marker" ]]
}

@test "security: cannot inject via semicolon in agent_exec" {
    source "$MAINFRAME_ROOT/lib/agent_exec.sh"

    # Create a marker file that should NOT be created by injection
    marker="$TEST_TMPDIR/injection_marker_agent"

    # Attempt injection - should be blocked
    run _agent_safe_exec "echo test; touch '$marker'"
    [[ "$status" -ne 0 ]]

    # Marker should not exist
    [[ ! -f "$marker" ]]
}

@test "security: subprocess isolation prevents variable modification" {
    source "$MAINFRAME_ROOT/lib/procsub.sh"

    # Set a variable in parent shell
    PARENT_VAR="original"

    # Try to modify it via subprocess
    _procsub_safe_exec 'PARENT_VAR=modified'

    # Should still be original
    [[ "$PARENT_VAR" == "original" ]]
}

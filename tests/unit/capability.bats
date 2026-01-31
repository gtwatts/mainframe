#!/usr/bin/env bats
# Capability-Based Security Tests

load '../test_helper'

setup() {
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    source "$MAINFRAME_ROOT/lib/capability.sh"
    cap_reset
}

teardown() {
    cap_reset
}

# =============================================================================
# BASIC GRANT/REVOKE TESTS
# =============================================================================

@test "cap_grant requires agent_id" {
    run cap_grant "" "cap://fs/read/*"
    [ "$status" -eq 1 ]
}

@test "cap_grant requires capability" {
    run cap_grant "test_agent" ""
    [ "$status" -eq 1 ]
}

@test "cap_grant validates capability format" {
    run cap_grant "test_agent" "invalid"
    [ "$status" -eq 1 ]
}

@test "cap_grant accepts valid capability" {
    run cap_grant "test_agent" "cap://fs/read/home/*"
    [ "$status" -eq 0 ]
}

@test "cap_revoke removes capability" {
    cap_grant "test_agent" "cap://fs/read/*"
    cap_has "test_agent" "cap://fs/read/test" || fail "Should have cap before revoke"

    cap_revoke "test_agent" "cap://fs/read/*"
    ! cap_has "test_agent" "cap://fs/read/test"
}

@test "cap_revoke_all removes all capabilities" {
    cap_grant "test_agent" "cap://fs/read/*"
    cap_grant "test_agent" "cap://fs/write/*"
    cap_grant "test_agent" "cap://exec/run/git"

    cap_revoke_all "test_agent"

    ! cap_has "test_agent" "cap://fs/read/test"
    ! cap_has "test_agent" "cap://fs/write/test"
    ! cap_has "test_agent" "cap://exec/run/git"
}

# =============================================================================
# CAP_HAS TESTS
# =============================================================================

@test "cap_has returns true for granted capability" {
    cap_grant "test_agent" "cap://fs/read/tmp/*"
    cap_has "test_agent" "cap://fs/read/tmp/file.txt"
}

@test "cap_has returns false for non-granted capability" {
    ! cap_has "test_agent" "cap://fs/write/etc/passwd"
}

@test "cap_has matches wildcard suffix" {
    cap_grant "test_agent" "cap://fs/read/home/*"
    cap_has "test_agent" "cap://fs/read/home/user/docs/file.txt"
}

@test "cap_has requires domain match" {
    cap_grant "test_agent" "cap://fs/read/*"
    ! cap_has "test_agent" "cap://net/http/example.com"
}

@test "cap_has requires action match" {
    cap_grant "test_agent" "cap://fs/read/*"
    ! cap_has "test_agent" "cap://fs/write/tmp/file"
}

@test "cap_has handles full wildcard" {
    cap_grant "test_agent" "cap://fs/read/*"
    cap_has "test_agent" "cap://fs/read/any/deep/path/file.txt"
}

# =============================================================================
# CAP_USE TESTS
# =============================================================================

@test "cap_use logs usage" {
    cap_grant "test_agent" "cap://fs/read/*"
    cap_use "test_agent" "cap://fs/read/etc/hosts"

    local log
    log=$(cap_audit_log)
    [[ "$log" == *"USE test_agent cap://fs/read/etc/hosts"* ]]
}

@test "cap_use logs denial" {
    cap_use "test_agent" "cap://fs/write/etc/passwd" || true

    local log
    log=$(cap_audit_log)
    [[ "$log" == *"DENIED test_agent cap://fs/write/etc/passwd"* ]]
}

@test "cap_use returns 0 on grant" {
    cap_grant "test_agent" "cap://exec/run/ls"
    cap_use "test_agent" "cap://exec/run/ls"
}

@test "cap_use returns 1 on denial" {
    ! cap_use "test_agent" "cap://exec/run/rm"
}

# =============================================================================
# PROFILE TESTS
# =============================================================================

@test "cap_grant_profile minimal grants limited capabilities" {
    cap_grant_profile "test_agent" "minimal"

    cap_has "test_agent" "cap://fs/read/tmp/file"
    cap_has "test_agent" "cap://exec/run/echo"
    ! cap_has "test_agent" "cap://fs/write/home/file"
}

@test "cap_grant_profile readonly grants read-only access" {
    cap_grant_profile "test_agent" "readonly"

    cap_has "test_agent" "cap://fs/read/any/path"
    cap_has "test_agent" "cap://exec/run/cat"
    ! cap_has "test_agent" "cap://fs/write/any/path"
}

@test "cap_grant_profile developer grants common dev tools" {
    cap_grant_profile "test_agent" "developer"

    cap_has "test_agent" "cap://fs/read/any/path"
    cap_has "test_agent" "cap://fs/write/home/user/project"
    cap_has "test_agent" "cap://exec/run/git"
    cap_has "test_agent" "cap://exec/run/npm"
}

@test "cap_grant_profile admin grants full access" {
    cap_grant_profile "test_agent" "admin"

    cap_has "test_agent" "cap://fs/read/any"
    cap_has "test_agent" "cap://fs/write/any"
    cap_has "test_agent" "cap://exec/run/anything"
    cap_has "test_agent" "cap://net/http/any.domain"
}

@test "cap_grant_profile rejects unknown profile" {
    run cap_grant_profile "test_agent" "superuser"
    [ "$status" -eq 1 ]
}

# =============================================================================
# GUARDED OPERATION TESTS
# =============================================================================

@test "cap_read_file denied without capability" {
    run cap_read_file "test_agent" "/etc/hosts"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Permission denied"* ]]
}

@test "cap_read_file allowed with capability" {
    cap_grant "test_agent" "cap://fs/read/etc/*"

    # Create test file
    echo "test content" > "$BATS_TMPDIR/test_read_file"
    cap_grant "test_agent" "cap://fs/read/${BATS_TMPDIR#/}/*"

    run cap_read_file "test_agent" "$BATS_TMPDIR/test_read_file"
    [ "$status" -eq 0 ]
    [[ "$output" == "test content" ]]
}

@test "cap_write_file denied without capability" {
    run cap_write_file "test_agent" "/tmp/test" "content"
    [ "$status" -eq 1 ]
}

@test "cap_exec denied without capability" {
    run cap_exec "test_agent" "ls -la"
    [ "$status" -eq 1 ]
}

@test "cap_exec allowed with capability" {
    cap_grant "test_agent" "cap://exec/run/echo"
    run cap_exec "test_agent" "echo hello"
    [ "$status" -eq 0 ]
    [[ "$output" == "hello" ]]
}

@test "cap_env_get denied without capability" {
    run cap_env_get "test_agent" "HOME"
    [ "$status" -eq 1 ]
}

@test "cap_env_get allowed with capability" {
    cap_grant "test_agent" "cap://env/read/HOME"
    result=$(cap_env_get "test_agent" "HOME")
    [ "$result" = "$HOME" ]
}

# =============================================================================
# LISTING TESTS
# =============================================================================

@test "cap_list shows agent capabilities" {
    cap_grant "test_agent" "cap://fs/read/*"
    cap_grant "test_agent" "cap://exec/run/git"

    result=$(cap_list "test_agent")
    [[ "$result" == *"cap://fs/read/*"* ]]
    [[ "$result" == *"cap://exec/run/git"* ]]
}

@test "cap_list_agents shows all agents" {
    cap_grant "agent1" "cap://fs/read/*"
    cap_grant "agent2" "cap://fs/write/*"

    result=$(cap_list_agents)
    [[ "$result" == *"agent1"* ]]
    [[ "$result" == *"agent2"* ]]
}

# =============================================================================
# AUDIT LOG TESTS
# =============================================================================

@test "cap_audit_log captures grants" {
    cap_grant "test_agent" "cap://fs/read/*"

    result=$(cap_audit_log)
    [[ "$result" == *"GRANT test_agent cap://fs/read/*"* ]]
}

@test "cap_audit_log_json returns valid JSON" {
    cap_grant "test_agent" "cap://fs/read/*"
    cap_use "test_agent" "cap://fs/read/etc/hosts"

    result=$(cap_audit_log_json)
    echo "$result" | jq . >/dev/null  # Validates JSON
}

@test "cap_denied_count tracks denials" {
    cap_use "agent1" "cap://fs/read/*" || true
    cap_use "agent1" "cap://fs/write/*" || true
    cap_use "agent2" "cap://exec/run/rm" || true

    [ "$(cap_denied_count "agent1")" -eq 2 ]
    [ "$(cap_denied_count "agent2")" -eq 1 ]
}

@test "cap_stats returns valid JSON" {
    cap_grant "test_agent" "cap://fs/read/*"
    cap_use "test_agent" "cap://fs/read/file"

    result=$(cap_stats)
    [ "$(echo "$result" | jq -r '.active_grants')" -ge 1 ]
    [ "$(echo "$result" | jq -r '.uses')" -ge 1 ]
}

# =============================================================================
# CAPABILITY TRANSFER TESTS
# =============================================================================

@test "cap_export returns JSON array" {
    cap_grant "parent" "cap://fs/read/*"
    cap_grant "parent" "cap://exec/run/git"

    result=$(cap_export "parent")
    echo "$result" | jq . >/dev/null  # Validates JSON

    [[ "$result" == *"cap://fs/read/*"* ]]
    [[ "$result" == *"cap://exec/run/git"* ]]
}

@test "cap_delegate transfers capabilities to child" {
    cap_grant "parent" "cap://fs/read/*"
    cap_grant "parent" "cap://fs/write/home/*"
    cap_grant "parent" "cap://exec/run/git"

    cap_delegate "parent" "child"

    cap_has "child" "cap://fs/read/any/path"
    cap_has "child" "cap://fs/write/home/user/file"
    cap_has "child" "cap://exec/run/git"
}

@test "cap_delegate respects filter" {
    cap_grant "parent" "cap://fs/read/*"
    cap_grant "parent" "cap://fs/write/*"
    cap_grant "parent" "cap://exec/run/git"

    cap_delegate "parent" "child" "cap://fs/*"

    cap_has "child" "cap://fs/read/any"
    cap_has "child" "cap://fs/write/any"
    ! cap_has "child" "cap://exec/run/git"
}

# =============================================================================
# RESET TESTS
# =============================================================================

@test "cap_reset clears all state" {
    cap_grant "test_agent" "cap://fs/read/*"
    cap_use "test_agent" "cap://fs/read/file"

    cap_reset

    ! cap_has "test_agent" "cap://fs/read/file"
    [ "$(cap_audit_log | wc -l)" -eq 0 ]
}

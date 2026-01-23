#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Scope Boundary Enforcement Tests
# =============================================================================

load 'test_helper'

setup() {
    # Use a unique scope dir per test to avoid interference
    export MAINFRAME_SCOPE_DIR="/tmp/mainframe_scope_test_$$_${BATS_TEST_NUMBER}"
    export MAINFRAME_SCOPE_ENABLED=1
    export MAINFRAME_SCOPE_JSON=1
    source_lib "scope"
}

teardown() {
    rm -rf "/tmp/mainframe_scope_test_$$_"* 2>/dev/null
}

# =============================================================================
# SCOPE SET TESTS
# =============================================================================

@test "mainframe_scope_set filesystem accepts colon-separated paths" {
    run mainframe_scope_set filesystem "/home/user/project:/tmp"
    [ "$status" -eq 0 ]
}

@test "mainframe_scope_set network accepts comma-separated hosts" {
    run mainframe_scope_set network "localhost,10.0.0.0/8,github.com"
    [ "$status" -eq 0 ]
}

@test "mainframe_scope_set commands accepts comma-separated commands" {
    run mainframe_scope_set commands "git,npm,docker,python"
    [ "$status" -eq 0 ]
}

@test "mainframe_scope_set fails on invalid type" {
    run mainframe_scope_set invalid "value"
    [ "$status" -eq 1 ]
}

@test "mainframe_scope_set fails with empty arguments" {
    run mainframe_scope_set "" ""
    [ "$status" -eq 1 ]
}

@test "mainframe_scope_set normalizes filesystem paths" {
    mainframe_scope_set filesystem "/home/user/../user/project:/tmp/./test"
    local status_json
    status_json=$(mainframe_scope_status)
    [[ "$status_json" == *"/home/user/project"* ]]
    [[ "$status_json" == *"/tmp/test"* ]]
}

# =============================================================================
# FILESYSTEM SCOPE CHECK TESTS
# =============================================================================

@test "filesystem scope allows exact path match" {
    mainframe_scope_set filesystem "/home/user/project:/tmp"
    run mainframe_scope_check filesystem "/home/user/project"
    [ "$status" -eq 0 ]
}

@test "filesystem scope allows subpath" {
    mainframe_scope_set filesystem "/home/user/project:/tmp"
    run mainframe_scope_check filesystem "/home/user/project/src/main.sh"
    [ "$status" -eq 0 ]
}

@test "filesystem scope allows /tmp subpath" {
    mainframe_scope_set filesystem "/home/user/project:/tmp"
    run mainframe_scope_check filesystem "/tmp/workdir/file.txt"
    [ "$status" -eq 0 ]
}

@test "filesystem scope blocks path outside scope" {
    mainframe_scope_set filesystem "/home/user/project:/tmp"
    run mainframe_scope_check filesystem "/etc/passwd"
    [ "$status" -eq 1 ]
}

@test "filesystem scope blocks traversal attempt" {
    mainframe_scope_set filesystem "/home/user/project"
    run mainframe_scope_check filesystem "/home/user/project/../../etc/passwd"
    [ "$status" -eq 1 ]
}

@test "filesystem scope emits JSON violation on block" {
    mainframe_scope_set filesystem "/home/user/project"
    run mainframe_scope_check filesystem "/etc/shadow"
    [ "$status" -eq 1 ]
    [[ "$output" == *'"type":"scope_violation"'* ]]
    [[ "$output" == *'"action":"blocked"'* ]]
    [[ "$output" == *'"scope_kind":"filesystem"'* ]]
}

@test "filesystem scope allows when no scope set (open scope)" {
    # Do NOT set any filesystem scope
    run mainframe_scope_check filesystem "/anything/goes"
    [ "$status" -eq 0 ]
}

@test "filesystem scope blocks sibling directory" {
    mainframe_scope_set filesystem "/home/user/project-a"
    run mainframe_scope_check filesystem "/home/user/project-b/secret"
    [ "$status" -eq 1 ]
}

@test "filesystem scope handles paths with trailing slash" {
    mainframe_scope_set filesystem "/home/user/project/"
    run mainframe_scope_check filesystem "/home/user/project/file.txt"
    [ "$status" -eq 0 ]
}

@test "filesystem scope handles multiple slashes in target" {
    mainframe_scope_set filesystem "/home/user/project"
    run mainframe_scope_check filesystem "/home/user//project///file.txt"
    [ "$status" -eq 0 ]
}

# =============================================================================
# NETWORK SCOPE CHECK TESTS
# =============================================================================

@test "network scope allows exact hostname match" {
    mainframe_scope_set network "github.com,localhost"
    run mainframe_scope_check network "github.com"
    [ "$status" -eq 0 ]
}

@test "network scope allows case-insensitive hostname" {
    mainframe_scope_set network "GitHub.COM"
    run mainframe_scope_check network "github.com"
    [ "$status" -eq 0 ]
}

@test "network scope blocks unknown host" {
    mainframe_scope_set network "github.com,localhost"
    run mainframe_scope_check network "evil.example.com"
    [ "$status" -eq 1 ]
}

@test "network scope allows IP in CIDR range" {
    mainframe_scope_set network "10.0.0.0/8"
    run mainframe_scope_check network "10.1.2.3"
    [ "$status" -eq 0 ]
}

@test "network scope blocks IP outside CIDR range" {
    mainframe_scope_set network "10.0.0.0/8"
    run mainframe_scope_check network "192.168.1.1"
    [ "$status" -eq 1 ]
}

@test "network scope allows 192.168.0.0/16 range" {
    mainframe_scope_set network "192.168.0.0/16"
    run mainframe_scope_check network "192.168.55.123"
    [ "$status" -eq 0 ]
}

@test "network scope blocks outside 192.168.0.0/16 range" {
    mainframe_scope_set network "192.168.0.0/16"
    run mainframe_scope_check network "192.169.0.1"
    [ "$status" -eq 1 ]
}

@test "network scope allows localhost aliases" {
    mainframe_scope_set network "localhost"
    run mainframe_scope_check network "127.0.0.1"
    [ "$status" -eq 0 ]
}

@test "network scope allows localhost alias reverse" {
    mainframe_scope_set network "127.0.0.1"
    run mainframe_scope_check network "localhost"
    [ "$status" -eq 0 ]
}

@test "network scope strips port from target" {
    mainframe_scope_set network "github.com"
    run mainframe_scope_check network "github.com:443"
    [ "$status" -eq 0 ]
}

@test "network scope allows wildcard domain" {
    mainframe_scope_set network "*.example.com"
    run mainframe_scope_check network "api.example.com"
    [ "$status" -eq 0 ]
}

@test "network scope wildcard allows base domain" {
    mainframe_scope_set network "*.example.com"
    run mainframe_scope_check network "example.com"
    [ "$status" -eq 0 ]
}

@test "network scope wildcard blocks different domain" {
    mainframe_scope_set network "*.example.com"
    run mainframe_scope_check network "evil.other.com"
    [ "$status" -eq 1 ]
}

@test "network scope emits JSON violation on block" {
    mainframe_scope_set network "localhost"
    run mainframe_scope_check network "evil.server.com"
    [ "$status" -eq 1 ]
    [[ "$output" == *'"type":"scope_violation"'* ]]
    [[ "$output" == *'"scope_kind":"network"'* ]]
    [[ "$output" == *'"action":"blocked"'* ]]
}

@test "network scope allows when no scope set (open scope)" {
    run mainframe_scope_check network "anything.goes.com"
    [ "$status" -eq 0 ]
}

# =============================================================================
# COMMAND SCOPE CHECK TESTS
# =============================================================================

@test "command scope allows listed command" {
    mainframe_scope_set commands "git,npm,docker"
    run mainframe_scope_check commands "git"
    [ "$status" -eq 0 ]
}

@test "command scope blocks unlisted command" {
    mainframe_scope_set commands "git,npm,docker"
    run mainframe_scope_check commands "rm"
    [ "$status" -eq 1 ]
}

@test "command scope strips path from command" {
    mainframe_scope_set commands "git,npm"
    run mainframe_scope_check commands "/usr/bin/git"
    [ "$status" -eq 0 ]
}

@test "command scope extracts command from full command line" {
    mainframe_scope_set commands "git,npm"
    run mainframe_scope_check commands "git commit -m update"
    [ "$status" -eq 0 ]
}

@test "command scope blocks dangerous commands" {
    mainframe_scope_set commands "git,npm"
    run mainframe_scope_check commands "rm -rf /"
    [ "$status" -eq 1 ]
}

@test "command scope emits JSON violation on block" {
    mainframe_scope_set commands "git"
    run mainframe_scope_check commands "curl"
    [ "$status" -eq 1 ]
    [[ "$output" == *'"type":"scope_violation"'* ]]
    [[ "$output" == *'"scope_kind":"commands"'* ]]
    [[ "$output" == *'"action":"blocked"'* ]]
}

@test "command scope allows when no scope set (open scope)" {
    run mainframe_scope_check commands "anything_goes"
    [ "$status" -eq 0 ]
}

# =============================================================================
# SCOPE CLEAR TESTS
# =============================================================================

@test "mainframe_scope_clear clears all scopes" {
    mainframe_scope_set filesystem "/home/user"
    mainframe_scope_set network "localhost"
    mainframe_scope_set commands "git"
    mainframe_scope_clear
    # After clearing, everything is allowed (open scope)
    run mainframe_scope_check filesystem "/etc/anything"
    [ "$status" -eq 0 ]
    run mainframe_scope_check network "evil.com"
    [ "$status" -eq 0 ]
    run mainframe_scope_check commands "rm"
    [ "$status" -eq 0 ]
}

@test "mainframe_scope_clear with type clears only that type" {
    mainframe_scope_set filesystem "/home/user"
    mainframe_scope_set commands "git"
    mainframe_scope_clear filesystem
    # Filesystem is now open
    run mainframe_scope_check filesystem "/etc/anything"
    [ "$status" -eq 0 ]
    # Commands still enforced
    run mainframe_scope_check commands "rm"
    [ "$status" -eq 1 ]
}

# =============================================================================
# SCOPE STATUS TESTS
# =============================================================================

@test "mainframe_scope_status returns valid JSON" {
    mainframe_scope_set filesystem "/home/user:/tmp"
    mainframe_scope_set network "localhost,github.com"
    mainframe_scope_set commands "git,npm"
    local result
    result=$(mainframe_scope_status)
    [[ "$result" == "{"* ]]
    [[ "$result" == *"}" ]]
    [[ "$result" == *'"enabled":true'* ]]
    [[ "$result" == *'"filesystem":'* ]]
    [[ "$result" == *'"network":'* ]]
    [[ "$result" == *'"commands":'* ]]
}

@test "mainframe_scope_status shows enabled false when disabled" {
    MAINFRAME_SCOPE_ENABLED=0
    local result
    result=$(mainframe_scope_status)
    [[ "$result" == *'"enabled":false'* ]]
}

@test "mainframe_scope_status shows empty arrays when no scope set" {
    local result
    result=$(mainframe_scope_status)
    [[ "$result" == *'"filesystem":[]'* ]]
    [[ "$result" == *'"network":[]'* ]]
    [[ "$result" == *'"commands":[]'* ]]
}

# =============================================================================
# SCOPE ENABLED/DISABLED TESTS
# =============================================================================

@test "scope enforcement disabled allows everything" {
    MAINFRAME_SCOPE_ENABLED=0
    mainframe_scope_set filesystem "/home/user"
    run mainframe_scope_check filesystem "/etc/shadow"
    [ "$status" -eq 0 ]
}

@test "scope enforcement re-enabled blocks again" {
    mainframe_scope_set filesystem "/home/user"
    MAINFRAME_SCOPE_ENABLED=0
    run mainframe_scope_check filesystem "/etc/shadow"
    [ "$status" -eq 0 ]
    MAINFRAME_SCOPE_ENABLED=1
    run mainframe_scope_check filesystem "/etc/shadow"
    [ "$status" -eq 1 ]
}

# =============================================================================
# CONVENIENCE FUNCTION TESTS
# =============================================================================

@test "mainframe_scope_check_path works as filesystem check" {
    mainframe_scope_set filesystem "/home/user"
    run mainframe_scope_check_path "/home/user/file.txt"
    [ "$status" -eq 0 ]
    run mainframe_scope_check_path "/etc/passwd"
    [ "$status" -eq 1 ]
}

@test "mainframe_scope_check_host works as network check" {
    mainframe_scope_set network "localhost"
    run mainframe_scope_check_host "localhost"
    [ "$status" -eq 0 ]
    run mainframe_scope_check_host "evil.com"
    [ "$status" -eq 1 ]
}

@test "mainframe_scope_check_cmd works as commands check" {
    mainframe_scope_set commands "git"
    run mainframe_scope_check_cmd "git"
    [ "$status" -eq 0 ]
    run mainframe_scope_check_cmd "rm"
    [ "$status" -eq 1 ]
}

# =============================================================================
# SCOPE ADD TESTS
# =============================================================================

@test "mainframe_scope_add_path adds to existing filesystem scope" {
    mainframe_scope_set filesystem "/home/user"
    mainframe_scope_add_path "/opt/app"
    run mainframe_scope_check filesystem "/home/user/file.txt"
    [ "$status" -eq 0 ]
    run mainframe_scope_check filesystem "/opt/app/config"
    [ "$status" -eq 0 ]
}

@test "mainframe_scope_add_host adds to existing network scope" {
    mainframe_scope_set network "localhost"
    mainframe_scope_add_host "github.com"
    run mainframe_scope_check network "localhost"
    [ "$status" -eq 0 ]
    run mainframe_scope_check network "github.com"
    [ "$status" -eq 0 ]
}

@test "mainframe_scope_add_cmd adds to existing commands scope" {
    mainframe_scope_set commands "git"
    mainframe_scope_add_cmd "npm"
    run mainframe_scope_check commands "git"
    [ "$status" -eq 0 ]
    run mainframe_scope_check commands "npm"
    [ "$status" -eq 0 ]
}

# =============================================================================
# SCOPE EXEC TESTS
# =============================================================================

@test "mainframe_scope_exec runs allowed command" {
    mainframe_scope_set commands "echo"
    run mainframe_scope_exec echo "hello"
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "mainframe_scope_exec blocks disallowed command" {
    mainframe_scope_set commands "git"
    run mainframe_scope_exec echo "hello"
    [ "$status" -eq 1 ]
}

# =============================================================================
# PERSISTENCE TESTS
# =============================================================================

@test "scope persists to disk" {
    mainframe_scope_set filesystem "/home/user:/tmp"
    [ -f "${MAINFRAME_SCOPE_DIR}/filesystem" ]
}

@test "scope reload restores from disk" {
    mainframe_scope_set filesystem "/home/user"
    # Clear in-memory state
    _MAINFRAME_SCOPE_FS=()
    _MAINFRAME_SCOPE_FS_COUNT=0
    # Verify it is now open (empty in-memory)
    run mainframe_scope_check filesystem "/etc/secret"
    [ "$status" -eq 0 ]
    # Reload from disk
    mainframe_scope_reload
    # Now it should block again
    run mainframe_scope_check filesystem "/etc/secret"
    [ "$status" -eq 1 ]
}

@test "mainframe_scope_destroy removes persistence directory" {
    mainframe_scope_set filesystem "/home/user"
    [ -d "$MAINFRAME_SCOPE_DIR" ]
    mainframe_scope_destroy
    [ ! -d "$MAINFRAME_SCOPE_DIR" ]
}

# =============================================================================
# VIOLATION JSON STRUCTURE TESTS
# =============================================================================

@test "violation JSON contains all required fields" {
    mainframe_scope_set filesystem "/home/user"
    run mainframe_scope_check filesystem "/etc/passwd"
    [ "$status" -eq 1 ]
    [[ "$output" == *'"error":true'* ]]
    [[ "$output" == *'"type":"scope_violation"'* ]]
    [[ "$output" == *'"severity":"high"'* ]]
    [[ "$output" == *'"action":"blocked"'* ]]
    [[ "$output" == *'"timestamp":'* ]]
    [[ "$output" == *'"allowed_scope":'* ]]
}

@test "violation JSON contains target path" {
    mainframe_scope_set filesystem "/home/user"
    run mainframe_scope_check filesystem "/etc/passwd"
    [ "$status" -eq 1 ]
    [[ "$output" == *'"/etc/passwd"'* ]]
}

@test "violation JSON contains allowed scope entries" {
    mainframe_scope_set filesystem "/home/user"
    run mainframe_scope_check filesystem "/etc/passwd"
    [ "$status" -eq 1 ]
    [[ "$output" == *'"/home/user"'* ]]
}

# =============================================================================
# PLAIN TEXT MODE TESTS
# =============================================================================

@test "plain text violation output works" {
    MAINFRAME_SCOPE_JSON=0
    mainframe_scope_set filesystem "/home/user"
    run mainframe_scope_check filesystem "/etc/passwd"
    [ "$status" -eq 1 ]
    [[ "$output" == *"[scope] VIOLATION"* ]]
    [[ "$output" == *"blocked"* ]]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "filesystem scope handles root path" {
    mainframe_scope_set filesystem "/"
    run mainframe_scope_check filesystem "/anything/goes/here"
    [ "$status" -eq 0 ]
}

@test "network scope handles /32 CIDR (single host)" {
    mainframe_scope_set network "10.0.0.1/32"
    run mainframe_scope_check network "10.0.0.1"
    [ "$status" -eq 0 ]
    run mainframe_scope_check network "10.0.0.2"
    [ "$status" -eq 1 ]
}

@test "command scope handles whitespace in command list" {
    mainframe_scope_set commands "git, npm, docker"
    run mainframe_scope_check commands "npm"
    [ "$status" -eq 0 ]
}

@test "filesystem scope handles path with spaces" {
    mainframe_scope_set filesystem "/home/user/my project"
    run mainframe_scope_check filesystem "/home/user/my project/file.txt"
    [ "$status" -eq 0 ]
}

@test "mainframe_scope_check fails with empty arguments" {
    run mainframe_scope_check "" ""
    [ "$status" -eq 1 ]
}

@test "mainframe_scope_check fails with invalid type" {
    run mainframe_scope_check "bogus" "target"
    [ "$status" -eq 1 ]
}

@test "scope set replaces previous scope of same type" {
    mainframe_scope_set filesystem "/home/user"
    mainframe_scope_set filesystem "/opt/app"
    # Only /opt/app should be allowed now
    run mainframe_scope_check filesystem "/home/user/file"
    [ "$status" -eq 1 ]
    run mainframe_scope_check filesystem "/opt/app/file"
    [ "$status" -eq 0 ]
}

@test "double-source guard prevents re-initialization" {
    # Source again - should be no-op
    source "$MAINFRAME_ROOT/lib/scope.sh"
    # Should still work
    mainframe_scope_set commands "git"
    run mainframe_scope_check commands "git"
    [ "$status" -eq 0 ]
}

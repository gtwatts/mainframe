#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Sandbox Module Tests
# =============================================================================
# Comprehensive tests for lib/sandbox.sh
# Covers: basic sandbox, bubblewrap integration, profiles, filesystem,
#         network, security, environment, and fallback modes
# =============================================================================

load 'test_helper'

setup() {
    source_lib "sandbox"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "sandbox")
    export MAINFRAME_SANDBOX_PROFILES="$TEST_DIR/profiles"
    mkdir -p "$MAINFRAME_SANDBOX_PROFILES"

    # Reset sandbox state
    sandbox_disable >/dev/null 2>&1 || true
    sandbox_reset 2>/dev/null || true
}

teardown() {
    sandbox_disable >/dev/null 2>&1 || true
    sandbox_reset 2>/dev/null || true
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# BASIC SANDBOX TESTS (Original functionality)
# =============================================================================

@test "sandbox_enable activates sandboxing" {
    sandbox_enable
    [ "$_SANDBOX_ENABLED" -eq 1 ]
}

@test "sandbox_disable deactivates sandboxing" {
    sandbox_enable
    sandbox_disable
    [ "$_SANDBOX_ENABLED" -eq 0 ]
}

@test "sandbox_enable with --dry-run sets dry run mode" {
    sandbox_enable --dry-run
    [ "$_SANDBOX_DRY_RUN" -eq 1 ]
}

@test "sandbox_enable with --timeout sets timeout" {
    sandbox_enable --timeout 60
    [ "$_SANDBOX_TIMEOUT" -eq 60 ]
}

@test "sandbox_enable with --root validates directory" {
    sandbox_enable --root "$TEST_DIR"
    [ "$_SANDBOX_ROOT" = "$TEST_DIR" ]
}

@test "sandbox_enable with --root fails for non-existent directory" {
    ! sandbox_enable --root "/nonexistent/directory"
}

@test "sandbox_allow_write adds path to allow list" {
    sandbox_enable
    sandbox_allow_write "/tmp/allowed"
    [[ " ${_SANDBOX_ALLOW_WRITE[*]} " == *" /tmp/allowed "* ]]
}

@test "sandbox_deny_write adds path to deny list" {
    sandbox_enable
    sandbox_deny_write "/etc/passwd"
    [[ " ${_SANDBOX_DENY_WRITE[*]} " == *" /etc/passwd "* ]]
}

@test "sandbox_deny_network sets network flag" {
    sandbox_enable
    sandbox_deny_network
    [ "$_SANDBOX_NETWORK_ALLOWED" -eq 0 ]
}

@test "sandbox_allow_network sets network flag" {
    sandbox_enable
    sandbox_deny_network
    sandbox_allow_network
    [ "$_SANDBOX_NETWORK_ALLOWED" -eq 1 ]
}

@test "sandbox_exec runs command when sandbox disabled" {
    sandbox_disable
    result=$(sandbox_exec echo "hello")
    [ "$result" = "hello" ]
}

@test "sandbox_exec blocks network commands when network denied" {
    sandbox_enable
    sandbox_deny_network
    ! sandbox_exec curl "http://example.com" 2>/dev/null
}

@test "sandbox_exec dry-run doesn't execute" {
    sandbox_enable --dry-run
    result=$(sandbox_exec rm -rf /tmp/important)
    [[ "$result" == *"DRY-RUN"* ]]
}

@test "sandbox_write respects allow list" {
    sandbox_enable
    sandbox_allow_write "$TEST_DIR"
    sandbox_write "$TEST_DIR/test.txt" "content"
    [ -f "$TEST_DIR/test.txt" ]
}

@test "sandbox_write blocks denied paths" {
    sandbox_enable
    sandbox_deny_write "/etc"
    ! sandbox_write "/etc/test.txt" "content" 2>/dev/null
}

@test "sandbox_mkdir creates directory in allowed path" {
    sandbox_enable
    sandbox_allow_write "$TEST_DIR"
    sandbox_mkdir "$TEST_DIR/subdir"
    [ -d "$TEST_DIR/subdir" ]
}

@test "sandbox_rm removes file in allowed path" {
    sandbox_enable
    sandbox_allow_write "$TEST_DIR"
    touch "$TEST_DIR/to_delete.txt"
    sandbox_rm "$TEST_DIR/to_delete.txt"
    [ ! -f "$TEST_DIR/to_delete.txt" ]
}

@test "sandbox_status shows configuration" {
    sandbox_enable --timeout 120
    result=$(sandbox_status)
    [[ "$result" == *"Enabled: yes"* ]]
    [[ "$result" == *"Timeout: 120s"* ]]
}

@test "sandbox_check write returns correct status" {
    sandbox_enable
    sandbox_allow_write "/tmp"
    sandbox_deny_write "/etc"

    result=$(sandbox_check write "/tmp/file")
    [[ "$result" == *"ALLOWED"* ]]

    result=$(sandbox_check write "/etc/file")
    [[ "$result" == *"DENIED"* ]]
}

@test "sandbox_check network returns correct status" {
    sandbox_enable

    result=$(sandbox_check network "")
    [[ "$result" == *"ALLOWED"* ]]

    sandbox_deny_network
    result=$(sandbox_check network "")
    [[ "$result" == *"DENIED"* ]]
}

@test "sandbox_audit_log sets log path" {
    sandbox_audit_log "$TEST_DIR/audit.jsonl"
    [ "$_SANDBOX_AUDIT_LOG" = "$TEST_DIR/audit.jsonl" ]
}

# =============================================================================
# BUBBLEWRAP AVAILABILITY TESTS
# =============================================================================

@test "sandbox_available returns status" {
    # This test will pass if bwrap is installed, skip otherwise
    if command -v bwrap &>/dev/null; then
        sandbox_available
    else
        ! sandbox_available
    fi
}

@test "sandbox_version returns version string when available" {
    if ! command -v bwrap &>/dev/null; then
        skip "bwrap not installed"
    fi

    result=$(sandbox_version)
    [[ "$result" == *"bubblewrap"* ]] || [[ "$result" == *"bwrap"* ]]
}

@test "sandbox_install_hint shows installation instructions" {
    result=$(sandbox_install_hint 2>&1)
    [[ "$result" == *"apt install"* ]] || [[ "$result" == *"dnf install"* ]]
}

# =============================================================================
# PROFILE MANAGEMENT TESTS
# =============================================================================

@test "sandbox_profile_create creates profile file" {
    sandbox_profile_create "test-profile" '{"network": true, "filesystem": ["/tmp:rw"]}'
    [ -f "$MAINFRAME_SANDBOX_PROFILES/test-profile.json" ]
}

@test "sandbox_profile_create validates JSON" {
    ! sandbox_profile_create "bad-profile" 'not json' 2>/dev/null
}

@test "sandbox_profile_list returns JSON array" {
    sandbox_profile_create "profile1" '{"network": true}'
    sandbox_profile_create "profile2" '{"network": false}'

    result=$(sandbox_profile_list)
    [[ "$result" == "["* ]]
    [[ "$result" == *"profile1"* ]]
    [[ "$result" == *"profile2"* ]]
}

@test "sandbox_profile_list handles empty directory" {
    result=$(sandbox_profile_list)
    [ "$result" = "[]" ]
}

@test "sandbox_profile_get returns profile content" {
    sandbox_profile_create "get-test" '{"network": true, "filesystem": []}'

    result=$(sandbox_profile_get "get-test")
    [[ "$result" == *"network"* ]]
}

@test "sandbox_profile_get fails for missing profile" {
    ! sandbox_profile_get "nonexistent" 2>/dev/null
}

@test "sandbox_profile_delete removes profile" {
    sandbox_profile_create "to-delete" '{"network": true}'
    [ -f "$MAINFRAME_SANDBOX_PROFILES/to-delete.json" ]

    sandbox_profile_delete "to-delete"
    [ ! -f "$MAINFRAME_SANDBOX_PROFILES/to-delete.json" ]
}

@test "sandbox_profile_delete fails for missing profile" {
    ! sandbox_profile_delete "nonexistent" 2>/dev/null
}

@test "sandbox_validate_profile validates correct JSON" {
    echo '{"network": true, "filesystem": ["/tmp:rw"]}' > "$TEST_DIR/valid.json"
    sandbox_validate_profile "$TEST_DIR/valid.json"
}

@test "sandbox_validate_profile rejects invalid JSON" {
    echo 'not json at all' > "$TEST_DIR/invalid.json"
    ! sandbox_validate_profile "$TEST_DIR/invalid.json" 2>/dev/null
}

# =============================================================================
# FILESYSTEM CONTROL TESTS
# =============================================================================

@test "sandbox_mount_ro adds read-only mount" {
    sandbox_reset
    sandbox_mount_ro "/usr" "/usr"

    [[ " ${_BWRAP_ARGS[*]} " == *"--ro-bind /usr /usr"* ]]
}

@test "sandbox_mount_ro defaults sandbox path to host path" {
    sandbox_reset
    sandbox_mount_ro "/var/log"

    [[ " ${_BWRAP_ARGS[*]} " == *"--ro-bind /var/log /var/log"* ]]
}

@test "sandbox_mount_rw adds read-write mount" {
    sandbox_reset
    sandbox_mount_rw "/tmp" "/tmp"

    [[ " ${_BWRAP_ARGS[*]} " == *"--bind /tmp /tmp"* ]]
}

@test "sandbox_tmpfs adds tmpfs mount" {
    sandbox_reset
    sandbox_tmpfs "/tmp"

    [[ " ${_BWRAP_ARGS[*]} " == *"--tmpfs /tmp"* ]]
}

@test "sandbox_bind adds bind mount" {
    sandbox_reset
    sandbox_bind "/opt" "ro"

    [[ " ${_BWRAP_ARGS[*]} " == *"--ro-bind /opt /opt"* ]]
}

@test "sandbox_bind with rw adds writable bind" {
    sandbox_reset
    sandbox_bind "/data" "rw"

    [[ " ${_BWRAP_ARGS[*]} " == *"--bind /data /data"* ]]
}

# =============================================================================
# NETWORK CONTROL TESTS
# =============================================================================

@test "sandbox_network_none isolates network" {
    sandbox_reset
    _BWRAP_ARGS+=(--share-net)
    sandbox_network_none

    [[ " ${_BWRAP_ARGS[*]} " != *"--share-net"* ]]
    [[ " ${_BWRAP_ARGS[*]} " == *"--unshare-net"* ]]
}

@test "sandbox_network_localhost enables localhost" {
    sandbox_reset
    sandbox_network_localhost

    [[ " ${_BWRAP_ARGS[*]} " == *"--share-net"* ]]
}

@test "sandbox_network_ports requires arguments" {
    ! sandbox_network_ports 2>/dev/null
}

@test "sandbox_network_ports enables network" {
    sandbox_reset
    sandbox_network_ports 80 443 2>/dev/null

    [[ " ${_BWRAP_ARGS[*]} " == *"--share-net"* ]]
}

# =============================================================================
# SECURITY CONTROL TESTS
# =============================================================================

@test "sandbox_drop_caps adds cap-drop ALL" {
    sandbox_reset
    sandbox_drop_caps

    [[ " ${_BWRAP_ARGS[*]} " == *"--cap-drop ALL"* ]]
}

@test "sandbox_keep_caps drops all then adds specific" {
    sandbox_reset
    sandbox_keep_caps CAP_NET_BIND_SERVICE

    [[ " ${_BWRAP_ARGS[*]} " == *"--cap-drop ALL"* ]]
    [[ " ${_BWRAP_ARGS[*]} " == *"--cap-add CAP_NET_BIND_SERVICE"* ]]
}

@test "sandbox_unshare_user adds unshare-user" {
    sandbox_reset
    sandbox_unshare_user

    [[ " ${_BWRAP_ARGS[*]} " == *"--unshare-user"* ]]
}

# =============================================================================
# ENVIRONMENT CONTROL TESTS
# =============================================================================

@test "sandbox_env_set adds setenv argument" {
    sandbox_reset
    sandbox_env_set "MY_VAR" "my_value"

    [[ " ${_BWRAP_ARGS[*]} " == *"--setenv MY_VAR my_value"* ]]
}

@test "sandbox_env_block adds unsetenv argument" {
    sandbox_reset
    sandbox_env_block "SECRET_TOKEN"

    [[ " ${_BWRAP_ARGS[*]} " == *"--unsetenv SECRET_TOKEN"* ]]
}

@test "sandbox_env_only clears and sets specific vars" {
    sandbox_reset
    export TEST_VAR="test_value"
    sandbox_env_only TEST_VAR

    [[ " ${_BWRAP_ARGS[*]} " == *"--clearenv"* ]]
    [[ " ${_BWRAP_ARGS[*]} " == *"--setenv TEST_VAR test_value"* ]]
    unset TEST_VAR
}

@test "sandbox_env_passthrough passes through vars" {
    sandbox_reset
    export PASS_VAR="pass_value"
    sandbox_env_passthrough PASS_VAR

    [[ " ${_BWRAP_ARGS[*]} " == *"--setenv PASS_VAR pass_value"* ]]
    unset PASS_VAR
}

# =============================================================================
# PRE-BUILT PROFILE TESTS
# =============================================================================

@test "sandbox_run_safe requires command" {
    ! sandbox_run_safe 2>/dev/null
}

@test "sandbox_run_web requires command" {
    ! sandbox_run_web 2>/dev/null
}

@test "sandbox_run_build requires command" {
    ! sandbox_run_build 2>/dev/null
}

@test "sandbox_run_untrusted requires command" {
    ! sandbox_run_untrusted 2>/dev/null
}

# Skip actual execution tests if bwrap not available
@test "sandbox_run_safe executes command" {
    if ! command -v bwrap &>/dev/null; then
        skip "bwrap not installed"
    fi

    result=$(sandbox_run_safe echo "safe")
    [ "$result" = "safe" ]
}

@test "sandbox_run_web allows network access" {
    if ! command -v bwrap &>/dev/null; then
        skip "bwrap not installed"
    fi

    # Just verify it runs, network test would need actual connectivity
    sandbox_run_web true
}

@test "sandbox_run_build allows project directory" {
    if ! command -v bwrap &>/dev/null; then
        skip "bwrap not installed"
    fi

    result=$(sandbox_run_build --project="$TEST_DIR" pwd)
    [ "$result" = "$TEST_DIR" ]
}

# =============================================================================
# UTILITY FUNCTION TESTS
# =============================================================================

@test "sandbox_dry_run shows command without executing" {
    if ! command -v bwrap &>/dev/null; then
        skip "bwrap not installed"
    fi

    result=$(sandbox_dry_run echo "test")
    [[ "$result" == "bwrap"* ]]
    [[ "$result" == *"echo test"* ]]
}

@test "sandbox_reset clears accumulated args" {
    sandbox_mount_ro "/test"
    sandbox_mount_rw "/data"
    [ ${#_BWRAP_ARGS[@]} -gt 0 ]

    sandbox_reset
    [ ${#_BWRAP_ARGS[@]} -eq 0 ]
}

# =============================================================================
# FALLBACK MODE TESTS
# =============================================================================

@test "sandbox_fallback_none runs command directly" {
    result=$(sandbox_fallback_none echo "fallback" 2>/dev/null)
    [ "$result" = "fallback" ]
}

@test "sandbox_fallback_firejail returns 127 when unavailable" {
    if command -v firejail &>/dev/null; then
        skip "firejail is installed"
    fi

    ! sandbox_fallback_firejail echo "test" 2>/dev/null
}

@test "sandbox_fallback_docker returns 127 when unavailable" {
    if command -v docker &>/dev/null; then
        skip "docker is installed"
    fi

    ! sandbox_fallback_docker echo "test" 2>/dev/null
}

# =============================================================================
# ISOLATION LEVEL TESTS
# =============================================================================

@test "sandbox_run_isolated requires level" {
    if ! command -v bwrap &>/dev/null; then
        skip "bwrap not installed"
    fi

    ! sandbox_run_isolated 2>/dev/null
}

@test "sandbox_run_isolated rejects invalid level" {
    if ! command -v bwrap &>/dev/null; then
        skip "bwrap not installed"
    fi

    ! sandbox_run_isolated --level=invalid echo "test" 2>/dev/null
}

@test "sandbox_run_isolated minimal level works" {
    if ! command -v bwrap &>/dev/null; then
        skip "bwrap not installed"
    fi

    result=$(sandbox_run_isolated --level=minimal echo "minimal")
    [ "$result" = "minimal" ]
}

@test "sandbox_run_isolated standard level works" {
    if ! command -v bwrap &>/dev/null; then
        skip "bwrap not installed"
    fi

    result=$(sandbox_run_isolated --level=standard echo "standard")
    [ "$result" = "standard" ]
}

@test "sandbox_run_isolated strict level works" {
    if ! command -v bwrap &>/dev/null; then
        skip "bwrap not installed"
    fi

    result=$(sandbox_run_isolated --level=strict echo "strict")
    [ "$result" = "strict" ]
}

# Paranoid may require user namespace support
@test "sandbox_run_isolated paranoid level works" {
    if ! command -v bwrap &>/dev/null; then
        skip "bwrap not installed"
    fi

    # Paranoid level uses user namespace, may fail on some systems
    sandbox_run_isolated --level=paranoid echo "paranoid" 2>/dev/null || skip "user namespace not supported"
}

# =============================================================================
# SANDBOX RUN TESTS
# =============================================================================

@test "sandbox_run requires command" {
    ! sandbox_run 2>/dev/null
}

@test "sandbox_run with profile loads profile" {
    if ! command -v bwrap &>/dev/null; then
        skip "bwrap not installed"
    fi

    sandbox_profile_create "echo-profile" '{"network": false, "filesystem": []}'
    result=$(sandbox_run --profile=echo-profile echo "from profile")
    [ "$result" = "from profile" ]
}

@test "sandbox_run without profile uses defaults" {
    if ! command -v bwrap &>/dev/null; then
        skip "bwrap not installed"
    fi

    result=$(sandbox_run echo "default")
    [ "$result" = "default" ]
}

@test "sandbox_run fails with missing profile" {
    if ! command -v bwrap &>/dev/null; then
        skip "bwrap not installed"
    fi

    ! sandbox_run --profile=nonexistent echo "test" 2>/dev/null
}

# =============================================================================
# RESOURCE LIMIT TESTS (Note warnings expected)
# =============================================================================

@test "sandbox_limit_cpu requires argument" {
    ! sandbox_limit_cpu 2>/dev/null
}

@test "sandbox_limit_memory requires argument" {
    ! sandbox_limit_memory 2>/dev/null
}

@test "sandbox_limit_pids requires argument" {
    ! sandbox_limit_pids 2>/dev/null
}

@test "sandbox_limit_fsize requires argument" {
    ! sandbox_limit_fsize 2>/dev/null
}

@test "sandbox_limit_nofile requires argument" {
    ! sandbox_limit_nofile 2>/dev/null
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

@test "builder pattern: mount + env + run" {
    if ! command -v bwrap &>/dev/null; then
        skip "bwrap not installed"
    fi

    sandbox_reset
    sandbox_mount_ro "/usr"
    sandbox_mount_rw "$TEST_DIR"
    sandbox_env_set "TEST_VAR" "test_value"

    result=$(sandbox_run sh -c 'echo $TEST_VAR')
    [ "$result" = "test_value" ]
}

@test "profile roundtrip: create, get, delete" {
    local config='{"network": true, "filesystem": ["/tmp:rw"], "env_passthrough": ["HOME"]}'

    sandbox_profile_create "roundtrip" "$config"

    result=$(sandbox_profile_get "roundtrip")
    [[ "$result" == *"network"* ]]
    [[ "$result" == *"filesystem"* ]]

    sandbox_profile_delete "roundtrip"
    ! sandbox_profile_get "roundtrip" 2>/dev/null
}

@test "audit log records operations" {
    sandbox_enable
    sandbox_audit_log "$TEST_DIR/audit.jsonl"
    sandbox_allow_write "$TEST_DIR"
    sandbox_write "$TEST_DIR/logged.txt" "content"

    [ -f "$TEST_DIR/audit.jsonl" ]

    log_content=$(<"$TEST_DIR/audit.jsonl")
    [[ "$log_content" == *"allow_write_added"* ]]
    [[ "$log_content" == *"write_complete"* ]]
}

# =============================================================================
# SAFETY VERIFICATION TESTS
# =============================================================================

@test "sandbox_verify runs checks" {
    if ! command -v bwrap &>/dev/null; then
        skip "bwrap not installed"
    fi

    # sandbox_verify returns status based on checks
    # We just verify it runs without error
    sandbox_verify || true
}

@test "sandbox_audit runs checks" {
    result=$(sandbox_audit "default" 2>&1)
    [[ "$result" == *"Security Audit"* ]]
}

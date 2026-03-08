#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Agent Safety Stack Tests
# =============================================================================
# Tests for lib/agent_safety.sh
# Covers: safe command dispatch, structured errors, idempotent operations,
#         audit trail, sandbox profiles, callback whitelist
# =============================================================================

load 'test_helper'

setup() {
    source_lib "agent_safety"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "agent_safety")
    export AGENT_AUDIT_LOG="$TEST_DIR/audit.jsonl"
    export AGENT_SAFE_BASE="$TEST_DIR"
    export AGENT_CURRENT_PROFILE="project"
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# CALLBACK WHITELIST TESTS (NO EVAL)
# =============================================================================

@test "agent_register_callback registers defined function" {
    _test_callback() { echo "called"; }
    run agent_register_callback "_test_callback"
    [ "$status" -eq 0 ]
}

@test "agent_register_callback rejects undefined function" {
    run agent_register_callback "nonexistent_function_12345"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a defined function"* ]]
}

@test "agent_register_callback rejects empty name" {
    run agent_register_callback ""
    [ "$status" -eq 1 ]
}

@test "agent_callback invokes registered callback" {
    _test_echo() { echo "$1"; }
    agent_register_callback "_test_echo"
    run agent_callback "_test_echo" "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
}

@test "agent_callback rejects unregistered callback" {
    run agent_callback "unregistered_function"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not registered"* ]]
}

@test "agent_callback passes multiple arguments" {
    _test_multi_args() { echo "$1 $2 $3"; }
    agent_register_callback "_test_multi_args"
    run agent_callback "_test_multi_args" "a" "b" "c"
    [ "$status" -eq 0 ]
    [[ "$output" == *"a b c"* ]]
}

@test "agent_unregister_callback removes callback" {
    _test_unreg() { echo "test"; }
    agent_register_callback "_test_unreg"
    agent_unregister_callback "_test_unreg"
    run agent_callback "_test_unreg"
    [ "$status" -eq 1 ]
}

@test "agent_list_callbacks shows registered callbacks" {
    _test_list1() { :; }
    _test_list2() { :; }
    agent_register_callback "_test_list1"
    agent_register_callback "_test_list2"
    run agent_list_callbacks
    [ "$status" -eq 0 ]
    [[ "$output" == *"_test_list1"* ]]
    [[ "$output" == *"_test_list2"* ]]
}

# =============================================================================
# STRUCTURED ERROR OUTPUT TESTS
# =============================================================================

@test "agent_error outputs valid JSON to stderr" {
    run agent_error "test error message"
    [ "$status" -eq 1 ]
    # Check JSON structure
    [[ "$output" == *'"success":false'* ]]
    [[ "$output" == *'"error":"test error message"'* ]]
    [[ "$output" == *'"timestamp":'* ]]
}

@test "agent_error includes function name" {
    _test_func_name() { agent_error "from test"; }
    run _test_func_name
    [ "$status" -eq 1 ]
    [[ "$output" == *'"function":"_test_func_name"'* ]]
}

@test "agent_error includes context array" {
    run agent_error "error message" "context1" "context2"
    [ "$status" -eq 1 ]
    [[ "$output" == *'"context":'* ]]
    [[ "$output" == *'"context1"'* ]]
    [[ "$output" == *'"context2"'* ]]
}

@test "agent_error escapes special characters" {
    run agent_error 'message with "quotes"'
    [ "$status" -eq 1 ]
    # Should be properly escaped
    [[ "$output" == *'\"quotes\"'* ]]
}

@test "agent_success outputs valid JSON to stdout" {
    run agent_success "operation completed"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"success":true'* ]]
    [[ "$output" == *'"message":"operation completed"'* ]]
}

@test "agent_success includes key=value data" {
    run agent_success "done" "key1=value1" "key2=value2"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"key1":"value1"'* ]]
    [[ "$output" == *'"key2":"value2"'* ]]
}

@test "agent_result outputs typed number" {
    run agent_result "count" "42" "number"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"count":42'* ]]
}

@test "agent_result outputs typed bool" {
    run agent_result "active" "true" "bool"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"active":true'* ]]
}

@test "agent_result outputs typed string" {
    run agent_result "name" "test" "string"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"name":"test"'* ]]
}

# =============================================================================
# COMMAND VALIDATION TESTS
# =============================================================================

@test "agent_validate_command accepts valid command" {
    run agent_validate_command "ls" "-la"
    [ "$status" -eq 0 ]
}

@test "agent_validate_command rejects nonexistent command" {
    run agent_validate_command "nonexistent_cmd_12345"
    [ "$status" -eq 1 ]
    [[ "$output" == *"command not found"* ]]
}

@test "agent_validate_command rejects empty command" {
    run agent_validate_command ""
    [ "$status" -eq 1 ]
}

@test "agent_validate_command blocks rm -rf outside safe base" {
    # Create a path outside safe base
    local outside_path="/tmp/outside_test_$$"
    AGENT_SAFE_BASE="$TEST_DIR"
    run agent_validate_command "rm" "-rf" "$outside_path"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unsafe rm target"* ]]
}

@test "agent_validate_command allows rm -rf inside safe base" {
    mkdir -p "$TEST_DIR/subdir"
    AGENT_SAFE_BASE="$TEST_DIR"
    run agent_validate_command "rm" "-rf" "$TEST_DIR/subdir"
    [ "$status" -eq 0 ]
}

@test "agent_validate_command blocks network in project profile" {
    AGENT_CURRENT_PROFILE="project"
    run agent_validate_command "curl" "http://example.com"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not allowed in profile"* ]]
}

@test "agent_validate_command blocks writes in readonly profile" {
    AGENT_CURRENT_PROFILE="readonly"
    run agent_validate_command "rm" "file.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not allowed in profile"* ]]
}

@test "agent_validate_command blocks system commands in project profile" {
    AGENT_CURRENT_PROFILE="project"
    run agent_validate_command "systemctl" "stop" "nginx"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not allowed in profile"* ]]
}

# =============================================================================
# RISK ASSESSMENT TESTS
# =============================================================================

@test "agent_risk_score returns low score for ls" {
    run agent_risk_score "ls" "-la"
    [ "$status" -eq 0 ]
    local score="$output"
    [ "$score" -lt 30 ]
}

@test "agent_risk_score returns high score for rm -rf" {
    run agent_risk_score "rm" "-rf" "/tmp/test"
    [ "$status" -eq 0 ]
    local score="$output"
    [ "$score" -ge 50 ]
}

@test "agent_risk_score returns very high score for reboot" {
    run agent_risk_score "reboot"
    [ "$status" -eq 0 ]
    local score="$output"
    [ "$score" -ge 90 ]
}

@test "agent_risk_score increases for system paths" {
    run agent_risk_score "rm" "-rf" "/etc/config"
    [ "$status" -eq 0 ]
    local score="$output"
    [ "$score" -ge 70 ]
}

@test "agent_requires_confirmation returns true for high-risk" {
    AGENT_RISK_THRESHOLD=50
    run agent_requires_confirmation "rm" "-rf" "/"
    [ "$status" -eq 0 ]  # 0 means requires confirmation
}

@test "agent_requires_confirmation returns false for low-risk" {
    AGENT_RISK_THRESHOLD=50
    run agent_requires_confirmation "ls"
    [ "$status" -eq 1 ]  # 1 means safe to proceed
}

# =============================================================================
# SAFE COMMAND DISPATCH TESTS
# =============================================================================

@test "agent_safe_exec runs valid command" {
    run agent_safe_exec echo "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == "hello" ]]
}

@test "agent_safe_exec blocks invalid command" {
    run agent_safe_exec "nonexistent_cmd_12345"
    [ "$status" -eq 1 ]
}

@test "agent_safe_exec audits execution" {
    agent_safe_exec echo "test" >/dev/null 2>&1
    run cat "$AGENT_AUDIT_LOG"
    [[ "$output" == *"exec_start"* ]]
    [[ "$output" == *"exec_complete"* ]]
}

@test "agent_safe_exec rejects empty command" {
    run agent_safe_exec
    [ "$status" -eq 1 ]
}

@test "agent_safe_exec_capture returns JSON on success" {
    run agent_safe_exec_capture echo "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"success":true'* ]]
    [[ "$output" == *"hello"* ]]
}

@test "agent_safe_exec_capture returns JSON on failure" {
    run agent_safe_exec_capture false
    [ "$status" -eq 1 ]
    [[ "$output" == *'"success":false'* ]]
}

# =============================================================================
# IDEMPOTENT OPERATIONS TESTS
# =============================================================================

@test "agent_ensure_file creates new file" {
    run agent_ensure_file "$TEST_DIR/new.txt" "content"
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/new.txt" ]
    local content
    content=$(<"$TEST_DIR/new.txt")
    [ "$content" = "content" ]
}

@test "agent_ensure_file is idempotent - no change needed" {
    echo -n "content" > "$TEST_DIR/existing.txt"
    run agent_ensure_file "$TEST_DIR/existing.txt" "content"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"action":"none"'* ]]
}

@test "agent_ensure_file updates changed content" {
    echo -n "old" > "$TEST_DIR/changed.txt"
    run agent_ensure_file "$TEST_DIR/changed.txt" "new"
    [ "$status" -eq 0 ]
    local content
    content=$(<"$TEST_DIR/changed.txt")
    [ "$content" = "new" ]
}

@test "agent_ensure_file creates parent directories" {
    run agent_ensure_file "$TEST_DIR/deep/nested/file.txt" "data"
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/deep/nested/file.txt" ]
}

@test "agent_ensure_file sets permissions" {
    run agent_ensure_file "$TEST_DIR/perms.txt" "secret" "0600"
    [ "$status" -eq 0 ]
    local mode
    mode=$(file_mode "$TEST_DIR/perms.txt")
    [ "$mode" = "600" ]
}

@test "agent_ensure_file blocked in readonly profile" {
    AGENT_CURRENT_PROFILE="readonly"
    run agent_ensure_file "$TEST_DIR/blocked.txt" "content"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not allowed"* ]]
}

@test "agent_ensure_dir creates new directory" {
    run agent_ensure_dir "$TEST_DIR/newdir"
    [ "$status" -eq 0 ]
    [ -d "$TEST_DIR/newdir" ]
}

@test "agent_ensure_dir is idempotent - exists" {
    mkdir -p "$TEST_DIR/existdir"
    run agent_ensure_dir "$TEST_DIR/existdir"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"action":"none"'* ]]
}

@test "agent_ensure_dir sets permissions" {
    run agent_ensure_dir "$TEST_DIR/permdir" "0700"
    [ "$status" -eq 0 ]
    local mode
    mode=$(file_mode "$TEST_DIR/permdir")
    [ "$mode" = "700" ]
}

@test "agent_ensure_line adds line to new file" {
    run agent_ensure_line "$TEST_DIR/lines.txt" "first line"
    [ "$status" -eq 0 ]
    grep -qx "first line" "$TEST_DIR/lines.txt"
}

@test "agent_ensure_line is idempotent - line exists" {
    echo "existing line" > "$TEST_DIR/existing_lines.txt"
    run agent_ensure_line "$TEST_DIR/existing_lines.txt" "existing line"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"action":"none"'* ]]
}

@test "agent_ensure_line appends new line" {
    echo "line1" > "$TEST_DIR/append.txt"
    run agent_ensure_line "$TEST_DIR/append.txt" "line2"
    [ "$status" -eq 0 ]
    grep -qx "line2" "$TEST_DIR/append.txt"
}

@test "agent_ensure_symlink creates symlink" {
    echo "target content" > "$TEST_DIR/target.txt"
    run agent_ensure_symlink "$TEST_DIR/link.txt" "$TEST_DIR/target.txt"
    [ "$status" -eq 0 ]
    [ -L "$TEST_DIR/link.txt" ]
}

@test "agent_ensure_symlink is idempotent - correct link" {
    echo "target" > "$TEST_DIR/target2.txt"
    ln -s "$TEST_DIR/target2.txt" "$TEST_DIR/link2.txt"
    run agent_ensure_symlink "$TEST_DIR/link2.txt" "$TEST_DIR/target2.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"action":"none"'* ]]
}

@test "agent_ensure_symlink updates wrong target" {
    echo "old target" > "$TEST_DIR/old_target.txt"
    echo "new target" > "$TEST_DIR/new_target.txt"
    ln -s "$TEST_DIR/old_target.txt" "$TEST_DIR/link3.txt"
    run agent_ensure_symlink "$TEST_DIR/link3.txt" "$TEST_DIR/new_target.txt"
    [ "$status" -eq 0 ]
    local actual_target
    actual_target=$(readlink "$TEST_DIR/link3.txt")
    [ "$actual_target" = "$TEST_DIR/new_target.txt" ]
}

@test "agent_ensure_command succeeds for existing command" {
    run agent_ensure_command "ls"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"success":true'* ]]
}

@test "agent_ensure_command fails for missing command" {
    run agent_ensure_command "nonexistent_cmd_12345"
    [ "$status" -eq 1 ]
    [[ "$output" == *"command not found"* ]]
}

# =============================================================================
# AUDIT TRAIL TESTS
# =============================================================================

@test "agent_audit writes to log file" {
    agent_audit "test_action" "key1=value1"
    [ -f "$AGENT_AUDIT_LOG" ]
    run cat "$AGENT_AUDIT_LOG"
    [[ "$output" == *"test_action"* ]]
    [[ "$output" == *"key1=value1"* ]]
}

@test "agent_audit writes valid JSON" {
    agent_audit "action" "detail=test"
    local line
    line=$(head -1 "$AGENT_AUDIT_LOG")
    # Basic JSON validation - starts with { and ends with }
    [[ "$line" == "{"* ]]
    [[ "$line" == *"}" ]]
}

@test "agent_audit includes timestamp" {
    agent_audit "timed_action"
    run cat "$AGENT_AUDIT_LOG"
    [[ "$output" == *'"ts":'* ]]
}

@test "agent_audit includes pid" {
    agent_audit "pid_action"
    run cat "$AGENT_AUDIT_LOG"
    [[ "$output" == *'"pid":'* ]]
    [[ "$output" == *"$$"* ]]
}

@test "agent_audit_replay shows all entries" {
    agent_audit "entry1"
    agent_audit "entry2"
    run agent_audit_replay
    [ "$status" -eq 0 ]
    [[ "$output" == *"entry1"* ]]
    [[ "$output" == *"entry2"* ]]
}

@test "agent_audit_replay filters entries" {
    agent_audit "match_this"
    agent_audit "other_action"
    run agent_audit_replay "match_this"
    [ "$status" -eq 0 ]
    [[ "$output" == *"match_this"* ]]
    [[ "$output" != *"other_action"* ]]
}

@test "agent_audit_clear truncates log" {
    agent_audit "before_clear"
    agent_audit_clear
    local line_count
    line_count=$(wc -l < "$AGENT_AUDIT_LOG")
    # Should have just the "log_cleared" entry
    [ "$line_count" -eq 1 ]
}

@test "agent_audit_path returns log path" {
    run agent_audit_path
    [ "$status" -eq 0 ]
    [ "$output" = "$AGENT_AUDIT_LOG" ]
}

@test "agent_audit_stats returns JSON" {
    agent_audit "stat_entry1"
    agent_audit "stat_entry2"
    run agent_audit_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *'"entries":'* ]]
    [[ "$output" == *'"size_bytes":'* ]]
}

# =============================================================================
# PROFILE MANAGEMENT TESTS
# =============================================================================

@test "agent_set_profile accepts valid profile" {
    agent_set_profile "readonly" "$TEST_DIR" >/dev/null
    [ "$?" -eq 0 ]
    [ "$AGENT_CURRENT_PROFILE" = "readonly" ]
}

@test "agent_set_profile rejects invalid profile" {
    run agent_set_profile "invalid_profile"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown profile"* ]]
}

@test "agent_set_profile sets safe base" {
    agent_set_profile "project" "/custom/base"
    [ "$AGENT_SAFE_BASE" = "/custom/base" ]
}

@test "agent_get_profile returns JSON" {
    agent_set_profile "system" "$TEST_DIR"
    run agent_get_profile
    [ "$status" -eq 0 ]
    [[ "$output" == *'"profile":"system"'* ]]
    [[ "$output" == *'"can_write":'* ]]
}

@test "agent_list_profiles shows all profiles" {
    run agent_list_profiles
    [ "$status" -eq 0 ]
    [[ "$output" == *"readonly"* ]]
    [[ "$output" == *"project"* ]]
    [[ "$output" == *"system"* ]]
}

@test "readonly profile blocks writes" {
    AGENT_CURRENT_PROFILE="readonly"
    run agent_ensure_file "$TEST_DIR/blocked.txt" "content"
    [ "$status" -eq 1 ]
}

@test "project profile allows writes within base" {
    AGENT_CURRENT_PROFILE="project"
    AGENT_SAFE_BASE="$TEST_DIR"
    run agent_ensure_file "$TEST_DIR/allowed.txt" "content"
    [ "$status" -eq 0 ]
}

@test "system profile allows system commands" {
    AGENT_CURRENT_PROFILE="system"
    # System profile allows validation of system commands
    run agent_validate_command "ls"  # Use a safe command
    [ "$status" -eq 0 ]
}

# =============================================================================
# INITIALIZATION AND CLEANUP TESTS
# =============================================================================

@test "agent_safety_init sets profile and base" {
    agent_safety_init "readonly" "/test/path" >/dev/null
    [ "$?" -eq 0 ]
    [ "$AGENT_CURRENT_PROFILE" = "readonly" ]
    [ "$AGENT_SAFE_BASE" = "/test/path" ]
}

@test "agent_safety_init audits initialization" {
    agent_safety_init "project" "$TEST_DIR"
    run cat "$AGENT_AUDIT_LOG"
    [[ "$output" == *"agent_safety_initialized"* ]]
}

@test "agent_safety_cleanup audits cleanup" {
    agent_safety_cleanup
    run cat "$AGENT_AUDIT_LOG"
    [[ "$output" == *"agent_safety_cleanup"* ]]
}

# =============================================================================
# PATH SAFETY TESTS
# =============================================================================

@test "path validation rejects traversal attack" {
    AGENT_SAFE_BASE="$TEST_DIR"
    run agent_ensure_file "$TEST_DIR/../../../etc/passwd" "malicious"
    [ "$status" -eq 1 ]
    [[ "$output" == *"outside safe base"* ]] || [[ "$output" == *"path"* ]]
}

@test "path validation rejects backslash paths" {
    AGENT_SAFE_BASE="$TEST_DIR"
    # _agent_validate_path_safe rejects backslashes
    run _agent_validate_path_safe "$TEST_DIR/test\\file" "$TEST_DIR"
    [ "$status" -eq 1 ]
}

@test "path validation accepts safe nested path" {
    mkdir -p "$TEST_DIR/safe/nested"
    AGENT_SAFE_BASE="$TEST_DIR"
    run agent_ensure_file "$TEST_DIR/safe/nested/file.txt" "content"
    [ "$status" -eq 0 ]
}

# =============================================================================
# EDGE CASES AND ERROR HANDLING
# =============================================================================

@test "agent_error handles newlines in message" {
    run agent_error $'line1\nline2'
    [ "$status" -eq 1 ]
    # Newline should be escaped
    [[ "$output" == *"\\n"* ]]
}

@test "agent_success handles empty data" {
    run agent_success "no data"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"data":{}'* ]]
}

@test "agent_ensure_file handles empty content" {
    run agent_ensure_file "$TEST_DIR/empty.txt" ""
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/empty.txt" ]
    [ ! -s "$TEST_DIR/empty.txt" ]
}

@test "agent_audit handles special characters" {
    agent_audit "special" 'key="value with quotes"'
    run cat "$AGENT_AUDIT_LOG"
    # Should contain escaped quotes
    [ "$status" -eq 0 ]
}

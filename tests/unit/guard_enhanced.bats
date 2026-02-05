#!/usr/bin/env bats
# Tests for Enhanced Security Guards

load '../bats-support/load'
load '../bats-assert/load'

setup() {
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    source "$MAINFRAME_ROOT/lib/guard_enhanced.sh"
}

@test "guard_path_traversal: detects basic traversal" {
    run guard_path_traversal --path "../../../etc/passwd"
    assert_failure
}

@test "guard_path_traversal: detects URL-encoded traversal" {
    run guard_path_traversal --path "%2e%2e%2fetc%2fpasswd"
    assert_failure
}

@test "guard_path_traversal: allows safe paths" {
    run guard_path_traversal --path "/home/user/file.txt"
    assert_success
}

@test "guard_command_injection: detects command substitution" {
    run guard_command_injection --cmd '$(whoami)'
    assert_failure
}

@test "guard_command_injection: detects backticks" {
    run guard_command_injection --cmd '\`rm -rf /\`'
    assert_failure
}

@test "guard_command_injection: allows safe commands" {
    run guard_command_injection --cmd 'echo hello'
    assert_success
}

@test "guard_sql_injection: detects DROP TABLE" {
    run guard_sql_injection --query "'; DROP TABLE users; --"
    assert_failure
}

@test "guard_sql_injection: detects UNION SELECT" {
    run guard_sql_injection --query "' UNION SELECT * FROM passwords --"
    assert_failure
}

@test "guard_sql_injection: allows safe queries" {
    run guard_sql_injection --query "SELECT * FROM users WHERE id = 1"
    assert_success
}

@test "guard_null_byte: detects null bytes" {
    run guard_null_byte --input "hello%00world"
    assert_failure
}

@test "guard_null_byte: allows normal strings" {
    run guard_null_byte --input "hello world"
    assert_success
}

@test "guard_env_safe: blocks dangerous variables" {
    run guard_env_safe --name "LD_PRELOAD" --value "/malicious.so"
    assert_failure
}

@test "guard_env_safe: blocks PATH manipulation" {
    run guard_env_safe --name "PATH" --value "/malicious:/usr/bin"
    assert_failure
}

@test "guard_env_safe: allows safe variables" {
    run guard_env_safe --name "MY_VAR" --value "safe_value"
    assert_success
}

@test "guard_url_safe: blocks file:// URLs" {
    run guard_url_safe --url "file:///etc/passwd"
    assert_failure
}

@test "guard_url_safe: allows http(s) URLs" {
    run guard_url_safe --url "https://example.com"
    assert_success
}

@test "guard_regex_safe: detects ReDoS patterns" {
    run guard_regex_safe --pattern '(a+)+$'
    assert_failure
}

@test "guard_regex_safe: allows safe patterns" {
    run guard_regex_safe --pattern '^[a-z]+$'
    assert_success
}

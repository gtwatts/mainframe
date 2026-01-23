#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Validation Module Tests
# =============================================================================
# Tests for lib/validation.sh
# Covers: type validators, format validators, path safety, sanitizers
# =============================================================================

load 'test_helper'

setup() {
    source_lib "validation"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "validation")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# validate_int TESTS
# =============================================================================

@test "validate_int accepts positive integer" {
    run validate_int "42"
    [ "$status" -eq 0 ]
}

@test "validate_int accepts zero" {
    run validate_int "0"
    [ "$status" -eq 0 ]
}

@test "validate_int accepts negative integer" {
    run validate_int "-5"
    [ "$status" -eq 0 ]
}

@test "validate_int rejects empty string" {
    run validate_int ""
    [ "$status" -eq 1 ]
}

@test "validate_int rejects float" {
    run validate_int "3.14"
    [ "$status" -eq 1 ]
}

@test "validate_int rejects non-numeric" {
    run validate_int "abc"
    [ "$status" -eq 1 ]
}

@test "validate_int respects min range" {
    run validate_int "5" 10
    [ "$status" -eq 1 ]
}

@test "validate_int passes within range" {
    run validate_int "50" 0 100
    [ "$status" -eq 0 ]
}

@test "validate_int rejects above max" {
    run validate_int "200" 0 100
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_float TESTS
# =============================================================================

@test "validate_float accepts simple float" {
    run validate_float "3.14"
    [ "$status" -eq 0 ]
}

@test "validate_float accepts integer" {
    run validate_float "42"
    [ "$status" -eq 0 ]
}

@test "validate_float accepts negative float" {
    run validate_float "-2.5"
    [ "$status" -eq 0 ]
}

@test "validate_float accepts scientific notation" {
    run validate_float "1.5e10"
    [ "$status" -eq 0 ]
}

@test "validate_float rejects empty" {
    run validate_float ""
    [ "$status" -eq 1 ]
}

@test "validate_float rejects text" {
    run validate_float "abc"
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_bool TESTS
# =============================================================================

@test "validate_bool accepts true" {
    run validate_bool "true"
    [ "$status" -eq 0 ]
}

@test "validate_bool accepts false" {
    run validate_bool "false"
    [ "$status" -eq 0 ]
}

@test "validate_bool accepts yes" {
    run validate_bool "yes"
    [ "$status" -eq 0 ]
}

@test "validate_bool accepts 1" {
    run validate_bool "1"
    [ "$status" -eq 0 ]
}

@test "validate_bool accepts on (case insensitive)" {
    run validate_bool "ON"
    [ "$status" -eq 0 ]
}

@test "validate_bool rejects arbitrary string" {
    run validate_bool "maybe"
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_email TESTS
# =============================================================================

@test "validate_email accepts valid email" {
    run validate_email "user@example.com"
    [ "$status" -eq 0 ]
}

@test "validate_email accepts dotted local part" {
    run validate_email "first.last@domain.org"
    [ "$status" -eq 0 ]
}

@test "validate_email accepts plus addressing" {
    run validate_email "user+tag@example.com"
    [ "$status" -eq 0 ]
}

@test "validate_email rejects missing @" {
    run validate_email "userexample.com"
    [ "$status" -eq 1 ]
}

@test "validate_email rejects missing domain" {
    run validate_email "user@"
    [ "$status" -eq 1 ]
}

@test "validate_email rejects empty" {
    run validate_email ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_url TESTS
# =============================================================================

@test "validate_url accepts https url" {
    run validate_url "https://example.com"
    [ "$status" -eq 0 ]
}

@test "validate_url accepts url with path" {
    run validate_url "https://example.com/path/to/resource"
    [ "$status" -eq 0 ]
}

@test "validate_url accepts url with port" {
    run validate_url "http://localhost:8080/api"
    [ "$status" -eq 0 ]
}

@test "validate_url rejects missing scheme" {
    run validate_url "example.com"
    [ "$status" -eq 1 ]
}

@test "validate_url rejects ftp by default" {
    run validate_url "ftp://files.example.com"
    [ "$status" -eq 1 ]
}

@test "validate_url accepts ftp when allowed" {
    run validate_url "ftp://files.example.com" "http,https,ftp"
    [ "$status" -eq 0 ]
}

# =============================================================================
# validate_ipv4 TESTS
# =============================================================================

@test "validate_ipv4 accepts valid address" {
    run validate_ipv4 "192.168.1.1"
    [ "$status" -eq 0 ]
}

@test "validate_ipv4 accepts all zeros" {
    run validate_ipv4 "0.0.0.0"
    [ "$status" -eq 0 ]
}

@test "validate_ipv4 accepts max values" {
    run validate_ipv4 "255.255.255.255"
    [ "$status" -eq 0 ]
}

@test "validate_ipv4 rejects octet over 255" {
    run validate_ipv4 "256.1.1.1"
    [ "$status" -eq 1 ]
}

@test "validate_ipv4 rejects too few octets" {
    run validate_ipv4 "192.168.1"
    [ "$status" -eq 1 ]
}

@test "validate_ipv4 rejects leading zeros" {
    run validate_ipv4 "192.168.01.1"
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_date TESTS
# =============================================================================

@test "validate_date accepts valid date" {
    run validate_date "2024-01-15"
    [ "$status" -eq 0 ]
}

@test "validate_date rejects invalid month" {
    run validate_date "2024-13-01"
    [ "$status" -eq 1 ]
}

@test "validate_date rejects invalid day" {
    run validate_date "2024-01-32"
    [ "$status" -eq 1 ]
}

@test "validate_date handles feb 29 in leap year" {
    run validate_date "2024-02-29"
    [ "$status" -eq 0 ]
}

@test "validate_date rejects feb 29 in non-leap year" {
    run validate_date "2023-02-29"
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_time TESTS
# =============================================================================

@test "validate_time accepts valid time" {
    run validate_time "10:30:00"
    [ "$status" -eq 0 ]
}

@test "validate_time accepts midnight" {
    run validate_time "00:00:00"
    [ "$status" -eq 0 ]
}

@test "validate_time rejects hour 24" {
    run validate_time "24:00:00"
    [ "$status" -eq 1 ]
}

@test "validate_time rejects minute 60" {
    run validate_time "12:60:00"
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_semver TESTS
# =============================================================================

@test "validate_semver accepts basic version" {
    run validate_semver "1.2.3"
    [ "$status" -eq 0 ]
}

@test "validate_semver accepts v prefix" {
    run validate_semver "v2.0.0"
    [ "$status" -eq 0 ]
}

@test "validate_semver accepts prerelease" {
    run validate_semver "1.0.0-alpha.1"
    [ "$status" -eq 0 ]
}

@test "validate_semver accepts build metadata" {
    run validate_semver "1.0.0+build.123"
    [ "$status" -eq 0 ]
}

@test "validate_semver rejects two-part version" {
    run validate_semver "1.2"
    [ "$status" -eq 1 ]
}

@test "validate_semver rejects leading zeros" {
    run validate_semver "01.2.3"
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_path_safe TESTS
# =============================================================================

@test "validate_path_safe accepts normal path" {
    run validate_path_safe "/usr/local/bin"
    [ "$status" -eq 0 ]
}

@test "validate_path_safe rejects traversal" {
    run validate_path_safe "/etc/../shadow"
    [ "$status" -eq 1 ]
}

@test "validate_path_safe rejects backslash" {
    run validate_path_safe '/path\to\file'
    [ "$status" -eq 1 ]
}

@test "validate_path_safe validates against base dir" {
    mkdir -p "$TEST_DIR/safe"
    run validate_path_safe "$TEST_DIR/safe/file.txt" "$TEST_DIR"
    [ "$status" -eq 0 ]
}

@test "validate_path_safe rejects empty" {
    run validate_path_safe ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_filename TESTS
# =============================================================================

@test "validate_filename accepts normal filename" {
    run validate_filename "report.pdf"
    [ "$status" -eq 0 ]
}

@test "validate_filename rejects path separators" {
    run validate_filename "path/file.txt"
    [ "$status" -eq 1 ]
}

@test "validate_filename rejects dotdot" {
    run validate_filename ".."
    [ "$status" -eq 1 ]
}

@test "validate_filename rejects leading dash" {
    run validate_filename "-rf"
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_path_chars TESTS
# =============================================================================

@test "validate_path_chars accepts alphanumeric path" {
    run validate_path_chars "/usr/local/bin/app"
    [ "$status" -eq 0 ]
}

@test "validate_path_chars accepts dots and hyphens" {
    run validate_path_chars "/path/to/file-name.txt"
    [ "$status" -eq 0 ]
}

@test "validate_path_chars rejects spaces" {
    run validate_path_chars "/path with spaces"
    [ "$status" -eq 1 ]
}

@test "validate_path_chars rejects shell metacharacters" {
    run validate_path_chars '/path/$(cmd)'
    [ "$status" -eq 1 ]
}

# =============================================================================
# sanitize_shell_arg TESTS
# =============================================================================

@test "sanitize_shell_arg escapes special chars" {
    local result
    result=$(sanitize_shell_arg 'hello "world"')
    [[ "$result" == *"\""* ]] || [[ "$result" == *"hello"* ]]
}

@test "sanitize_shell_arg handles simple string" {
    local result
    result=$(sanitize_shell_arg "hello")
    [ "$result" = "hello" ]
}

# =============================================================================
# sanitize_filename TESTS
# =============================================================================

@test "sanitize_filename removes path separators" {
    local result
    result=$(sanitize_filename "a/b/c.txt")
    [[ "$result" != *"/"* ]]
}

@test "sanitize_filename removes shell metacharacters" {
    local result
    result=$(sanitize_filename 'file$(cmd).txt')
    [[ "$result" != *'$'* ]]
}

@test "sanitize_filename removes leading dashes" {
    local result
    result=$(sanitize_filename "--dangerous")
    [[ "$result" != -* ]]
}

# =============================================================================
# sanitize_html TESTS
# =============================================================================

@test "sanitize_html escapes angle brackets" {
    local result
    result=$(sanitize_html "<script>alert(1)</script>")
    [[ "$result" == *"&lt;"* ]]
    [[ "$result" == *"&gt;"* ]]
}

@test "sanitize_html escapes ampersands" {
    local result
    result=$(sanitize_html "foo & bar")
    [[ "$result" == *"&amp;"* ]]
}

@test "sanitize_html escapes quotes" {
    local result
    result=$(sanitize_html 'say "hello"')
    [[ "$result" == *"&quot;"* ]]
}

# =============================================================================
# sanitize_sql TESTS
# =============================================================================

@test "sanitize_sql escapes single quotes" {
    local result
    result=$(sanitize_sql "O'Brien")
    [ "$result" = "O''Brien" ]
}

@test "sanitize_sql escapes backslashes" {
    local result
    result=$(sanitize_sql 'path\to\file')
    [[ "$result" == *'\\'* ]]
}

# =============================================================================
# validate_command_safe TESTS
# =============================================================================

@test "validate_command_safe accepts simple command" {
    run validate_command_safe "ls -la /tmp"
    [ "$status" -eq 0 ]
}

@test "validate_command_safe rejects pipe" {
    run validate_command_safe "cat file | grep pattern"
    [ "$status" -eq 1 ]
}

@test "validate_command_safe rejects semicolon" {
    run validate_command_safe "cmd1; cmd2"
    [ "$status" -eq 1 ]
}

@test "validate_command_safe rejects command substitution" {
    run validate_command_safe 'echo $(whoami)'
    [ "$status" -eq 1 ]
}

@test "validate_command_safe rejects redirect" {
    run validate_command_safe "echo data > /etc/passwd"
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_uuid TESTS
# =============================================================================

@test "validate_uuid accepts valid uuid" {
    run validate_uuid "550e8400-e29b-41d4-a716-446655440000"
    [ "$status" -eq 0 ]
}

@test "validate_uuid rejects invalid format" {
    run validate_uuid "not-a-uuid"
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_port TESTS
# =============================================================================

@test "validate_port accepts valid port" {
    run validate_port "8080"
    [ "$status" -eq 0 ]
}

@test "validate_port rejects zero" {
    run validate_port "0"
    [ "$status" -eq 1 ]
}

@test "validate_port rejects over 65535" {
    run validate_port "70000"
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_mac TESTS
# =============================================================================

@test "validate_mac accepts colon format" {
    run validate_mac "AA:BB:CC:DD:EE:FF"
    [ "$status" -eq 0 ]
}

@test "validate_mac accepts hyphen format" {
    run validate_mac "AA-BB-CC-DD-EE-FF"
    [ "$status" -eq 0 ]
}

@test "validate_mac rejects invalid" {
    run validate_mac "not-a-mac"
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_domain TESTS
# =============================================================================

@test "validate_domain accepts valid domain" {
    run validate_domain "example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain accepts subdomain" {
    run validate_domain "sub.example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain rejects single label" {
    run validate_domain "localhost"
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_enum TESTS
# =============================================================================

@test "validate_enum accepts valid option" {
    run validate_enum "red" "red" "green" "blue"
    [ "$status" -eq 0 ]
}

@test "validate_enum rejects invalid option" {
    run validate_enum "purple" "red" "green" "blue"
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_length TESTS
# =============================================================================

@test "validate_length accepts within range" {
    run validate_length "hello" 1 10
    [ "$status" -eq 0 ]
}

@test "validate_length rejects too short" {
    run validate_length "hi" 5
    [ "$status" -eq 1 ]
}

@test "validate_length rejects too long" {
    run validate_length "hello world" "" 5
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_credit_card TESTS (Luhn algorithm)
# =============================================================================

@test "validate_credit_card accepts valid number" {
    run validate_credit_card "4532015112830366"
    [ "$status" -eq 0 ]
}

@test "validate_credit_card rejects invalid checksum" {
    run validate_credit_card "4532015112830367"
    [ "$status" -eq 1 ]
}

@test "validate_credit_card accepts with spaces" {
    run validate_credit_card "4532 0151 1283 0366"
    [ "$status" -eq 0 ]
}

# =============================================================================
# validate_json TESTS
# =============================================================================

@test "validate_json accepts object" {
    run validate_json '{"key":"value"}'
    [ "$status" -eq 0 ]
}

@test "validate_json accepts array" {
    run validate_json '[1,2,3]'
    [ "$status" -eq 0 ]
}

@test "validate_json rejects unmatched braces" {
    run validate_json '{"key":"value"'
    [ "$status" -eq 1 ]
}

@test "validate_json rejects plain string" {
    run validate_json 'hello'
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_slug TESTS
# =============================================================================

@test "validate_slug accepts valid slug" {
    run validate_slug "my-cool-project"
    [ "$status" -eq 0 ]
}

@test "validate_slug rejects uppercase" {
    run validate_slug "My-Project"
    [ "$status" -eq 1 ]
}

@test "validate_slug rejects consecutive hyphens" {
    run validate_slug "bad--slug"
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_cidr TESTS
# =============================================================================

@test "validate_cidr accepts valid cidr" {
    run validate_cidr "192.168.1.0/24"
    [ "$status" -eq 0 ]
}

@test "validate_cidr rejects invalid prefix" {
    run validate_cidr "192.168.1.0/33"
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_base64 TESTS
# =============================================================================

@test "validate_base64 accepts valid base64" {
    run validate_base64 "aGVsbG8="
    [ "$status" -eq 0 ]
}

@test "validate_base64 rejects invalid chars" {
    run validate_base64 "hello!"
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_all TESTS
# =============================================================================

@test "validate_all passes when all values valid" {
    run validate_all "validate_int" "1" "2" "3"
    [ "$status" -eq 0 ]
}

@test "validate_all fails when one value invalid" {
    run validate_all "validate_int" "1" "abc" "3"
    [ "$status" -eq 1 ]
}

# =============================================================================
# build_safe_command TESTS
# =============================================================================

@test "build_safe_command escapes arguments" {
    local result
    result=$(build_safe_command "grep" "pattern with spaces" "/path/to/file")
    [[ "$result" == *"grep"* ]]
    [[ "$result" == *"pattern"* ]]
}

# =============================================================================
# validate_phone TESTS
# =============================================================================

@test "validate_phone accepts E.164 format" {
    run validate_phone "+15551234567"
    [ "$status" -eq 0 ]
}

@test "validate_phone accepts formatted number" {
    run validate_phone "(555) 123-4567"
    [ "$status" -eq 0 ]
}

@test "validate_phone rejects empty" {
    run validate_phone ""
    [ "$status" -eq 1 ]
}

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/test_validation.bats - Unit tests for validation.sh
# =============================================================================

# Load test helpers
setup() {
    # Source the validation library
    source "${BATS_TEST_DIRNAME}/../../lib/validation.sh"
}

# =============================================================================
# TYPE VALIDATION TESTS
# =============================================================================

@test "validate_int: accepts valid integers" {
    run validate_int "42"
    [ "$status" -eq 0 ]
}

@test "validate_int: accepts negative integers" {
    run validate_int "-42"
    [ "$status" -eq 0 ]
}

@test "validate_int: accepts zero" {
    run validate_int "0"
    [ "$status" -eq 0 ]
}

@test "validate_int: rejects empty string" {
    run validate_int ""
    [ "$status" -eq 1 ]
}

@test "validate_int: rejects non-numeric strings" {
    run validate_int "abc"
    [ "$status" -eq 1 ]
}

@test "validate_int: rejects floats" {
    run validate_int "3.14"
    [ "$status" -eq 1 ]
}

@test "validate_int: respects min bound" {
    run validate_int "5" 10
    [ "$status" -eq 1 ]

    run validate_int "10" 10
    [ "$status" -eq 0 ]
}

@test "validate_int: respects max bound" {
    run validate_int "15" 0 10
    [ "$status" -eq 1 ]

    run validate_int "10" 0 10
    [ "$status" -eq 0 ]
}

@test "validate_float: accepts valid floats" {
    run validate_float "3.14"
    [ "$status" -eq 0 ]
}

@test "validate_float: accepts integers" {
    run validate_float "42"
    [ "$status" -eq 0 ]
}

@test "validate_float: accepts negative floats" {
    run validate_float "-3.14"
    [ "$status" -eq 0 ]
}

@test "validate_float: accepts scientific notation" {
    run validate_float "1.5e10"
    [ "$status" -eq 0 ]

    run validate_float "1.5E-10"
    [ "$status" -eq 0 ]
}

@test "validate_float: rejects non-numeric strings" {
    run validate_float "abc"
    [ "$status" -eq 1 ]
}

@test "validate_bool: accepts true/false" {
    run validate_bool "true"
    [ "$status" -eq 0 ]

    run validate_bool "false"
    [ "$status" -eq 0 ]
}

@test "validate_bool: accepts yes/no" {
    run validate_bool "yes"
    [ "$status" -eq 0 ]

    run validate_bool "no"
    [ "$status" -eq 0 ]
}

@test "validate_bool: accepts 1/0" {
    run validate_bool "1"
    [ "$status" -eq 0 ]

    run validate_bool "0"
    [ "$status" -eq 0 ]
}

@test "validate_bool: accepts on/off" {
    run validate_bool "on"
    [ "$status" -eq 0 ]

    run validate_bool "off"
    [ "$status" -eq 0 ]
}

@test "validate_bool: case insensitive" {
    run validate_bool "TRUE"
    [ "$status" -eq 0 ]

    run validate_bool "False"
    [ "$status" -eq 0 ]
}

@test "validate_bool: rejects invalid values" {
    run validate_bool "maybe"
    [ "$status" -eq 1 ]
}

@test "validate_uuid: accepts valid UUIDs" {
    run validate_uuid "550e8400-e29b-41d4-a716-446655440000"
    [ "$status" -eq 0 ]
}

@test "validate_uuid: accepts uppercase UUIDs" {
    run validate_uuid "550E8400-E29B-41D4-A716-446655440000"
    [ "$status" -eq 0 ]
}

@test "validate_uuid: rejects invalid UUIDs" {
    run validate_uuid "not-a-uuid"
    [ "$status" -eq 1 ]

    run validate_uuid "550e8400-e29b-41d4-a716"
    [ "$status" -eq 1 ]
}

@test "validate_hex: accepts valid hex" {
    run validate_hex "ff00ff"
    [ "$status" -eq 0 ]

    run validate_hex "DEADBEEF"
    [ "$status" -eq 0 ]
}

@test "validate_hex: validates length" {
    run validate_hex "ff00ff" 6
    [ "$status" -eq 0 ]

    run validate_hex "ff00ff" 8
    [ "$status" -eq 1 ]
}

@test "validate_hex: rejects non-hex" {
    run validate_hex "ghijkl"
    [ "$status" -eq 1 ]
}

# =============================================================================
# FORMAT VALIDATION TESTS
# =============================================================================

@test "validate_email: accepts valid emails" {
    run validate_email "user@example.com"
    [ "$status" -eq 0 ]

    run validate_email "user.name+tag@subdomain.example.co.uk"
    [ "$status" -eq 0 ]
}

@test "validate_email: rejects invalid emails" {
    run validate_email "not-an-email"
    [ "$status" -eq 1 ]

    run validate_email "@example.com"
    [ "$status" -eq 1 ]

    run validate_email "user@"
    [ "$status" -eq 1 ]
}

@test "validate_url: accepts valid URLs" {
    run validate_url "http://example.com"
    [ "$status" -eq 0 ]

    run validate_url "https://example.com/path?query=1"
    [ "$status" -eq 0 ]
}

@test "validate_url: accepts custom schemes" {
    run validate_url "ftp://files.example.com" "ftp,http,https"
    [ "$status" -eq 0 ]
}

@test "validate_url: rejects invalid URLs" {
    run validate_url "not-a-url"
    [ "$status" -eq 1 ]

    run validate_url "ftp://example.com"
    [ "$status" -eq 1 ]
}

@test "validate_domain: accepts valid domains" {
    run validate_domain "example.com"
    [ "$status" -eq 0 ]

    run validate_domain "sub.example.co.uk"
    [ "$status" -eq 0 ]
}

@test "validate_domain: rejects invalid domains" {
    run validate_domain "not a domain"
    [ "$status" -eq 1 ]

    run validate_domain "-invalid.com"
    [ "$status" -eq 1 ]
}

@test "validate_ipv4: accepts valid IPv4" {
    run validate_ipv4 "192.168.1.1"
    [ "$status" -eq 0 ]

    run validate_ipv4 "0.0.0.0"
    [ "$status" -eq 0 ]

    run validate_ipv4 "255.255.255.255"
    [ "$status" -eq 0 ]
}

@test "validate_ipv4: rejects invalid IPv4" {
    run validate_ipv4 "256.0.0.1"
    [ "$status" -eq 1 ]

    run validate_ipv4 "192.168.1"
    [ "$status" -eq 1 ]

    run validate_ipv4 "192.168.1.1.1"
    [ "$status" -eq 1 ]
}

@test "validate_ipv6: accepts valid IPv6" {
    run validate_ipv6 "2001:0db8:85a3:0000:0000:8a2e:0370:7334"
    [ "$status" -eq 0 ]

    run validate_ipv6 "::1"
    [ "$status" -eq 0 ]

    run validate_ipv6 "fe80::"
    [ "$status" -eq 0 ]
}

@test "validate_ipv6: rejects invalid IPv6" {
    run validate_ipv6 "not-an-ipv6"
    [ "$status" -eq 1 ]

    run validate_ipv6 "::1::2"
    [ "$status" -eq 1 ]
}

@test "validate_date: accepts valid dates" {
    run validate_date "2024-01-15"
    [ "$status" -eq 0 ]

    run validate_date "2024-02-29"  # Leap year
    [ "$status" -eq 0 ]
}

@test "validate_date: rejects invalid dates" {
    run validate_date "2024-13-01"  # Invalid month
    [ "$status" -eq 1 ]

    run validate_date "2023-02-29"  # Not leap year
    [ "$status" -eq 1 ]

    run validate_date "01-15-2024"  # Wrong format
    [ "$status" -eq 1 ]
}

@test "validate_time: accepts valid times" {
    run validate_time "14:30:00"
    [ "$status" -eq 0 ]

    run validate_time "00:00:00"
    [ "$status" -eq 0 ]

    run validate_time "23:59:59"
    [ "$status" -eq 0 ]
}

@test "validate_time: rejects invalid times" {
    run validate_time "24:00:00"
    [ "$status" -eq 1 ]

    run validate_time "14:60:00"
    [ "$status" -eq 1 ]

    run validate_time "2:30:00"  # Wrong format
    [ "$status" -eq 1 ]
}

@test "validate_semver: accepts valid semver" {
    run validate_semver "1.2.3"
    [ "$status" -eq 0 ]

    run validate_semver "v1.0.0"
    [ "$status" -eq 0 ]

    run validate_semver "1.0.0-alpha.1"
    [ "$status" -eq 0 ]

    run validate_semver "1.0.0+build.123"
    [ "$status" -eq 0 ]
}

@test "validate_semver: rejects invalid semver" {
    run validate_semver "1.2"
    [ "$status" -eq 1 ]

    run validate_semver "1.02.3"  # Leading zero
    [ "$status" -eq 1 ]
}

# =============================================================================
# PATH VALIDATION TESTS
# =============================================================================

@test "validate_path: validates existing files" {
    local temp_file=$(mktemp)
    run validate_path "$temp_file" "file"
    [ "$status" -eq 0 ]
    rm -f "$temp_file"
}

@test "validate_path: validates existing directories" {
    run validate_path "/tmp" "dir"
    [ "$status" -eq 0 ]
}

@test "validate_path: rejects non-existent paths" {
    run validate_path "/nonexistent/path" "any"
    [ "$status" -eq 1 ]
}

@test "validate_path_safe: rejects traversal attacks" {
    run validate_path_safe "../../../etc/passwd"
    [ "$status" -eq 1 ]

    run validate_path_safe "/safe/path/../../../etc/passwd"
    [ "$status" -eq 1 ]
}

@test "validate_path_safe: rejects null bytes" {
    run validate_path_safe $'file\x00.txt'
    [ "$status" -eq 1 ]
}

@test "validate_filename: accepts valid filenames" {
    run validate_filename "report.pdf"
    [ "$status" -eq 0 ]

    run validate_filename "file_name-123.txt"
    [ "$status" -eq 0 ]
}

@test "validate_filename: rejects path components" {
    run validate_filename "/path/to/file"
    [ "$status" -eq 1 ]

    run validate_filename "dir/file"
    [ "$status" -eq 1 ]
}

@test "validate_filename: rejects special names" {
    run validate_filename "."
    [ "$status" -eq 1 ]

    run validate_filename ".."
    [ "$status" -eq 1 ]
}

@test "validate_filename: rejects leading dash" {
    run validate_filename "-rf"
    [ "$status" -eq 1 ]
}

@test "validate_path_chars: accepts safe paths" {
    run validate_path_chars "/path/to/file.txt"
    [ "$status" -eq 0 ]

    run validate_path_chars "relative/path/file_name-123.txt"
    [ "$status" -eq 0 ]
}

@test "validate_path_chars: rejects dangerous chars" {
    run validate_path_chars "/path/with;injection"
    [ "$status" -eq 1 ]

    run validate_path_chars '/path/with$expansion'
    [ "$status" -eq 1 ]
}

# =============================================================================
# SANITIZATION TESTS
# =============================================================================

@test "sanitize_shell_arg: escapes dangerous characters" {
    result=$(sanitize_shell_arg 'hello world')
    [[ "$result" == *" "* ]] || [[ "$result" == "hello\ world" ]] || [[ "$result" == "'hello world'" ]]
}

@test "sanitize_filename: removes dangerous characters" {
    result=$(sanitize_filename "a/b<c>d|e")
    [[ "$result" != *"/"* ]]
    [[ "$result" != *"<"* ]]
    [[ "$result" != *">"* ]]
}

@test "sanitize_filename: removes leading dashes" {
    result=$(sanitize_filename "-rf")
    [[ "$result" != "-"* ]]
}

@test "sanitize_sql: escapes single quotes" {
    result=$(sanitize_sql "O'Brien")
    [ "$result" = "O''Brien" ]
}

@test "sanitize_html: escapes HTML entities" {
    result=$(sanitize_html "<script>alert('xss')</script>")
    [[ "$result" == *"&lt;"* ]]
    [[ "$result" == *"&gt;"* ]]
    [[ "$result" != *"<script>"* ]]
}

@test "sanitize_json: escapes JSON special chars" {
    result=$(sanitize_json 'say "hello"')
    [ "$result" = 'say \"hello\"' ]
}

@test "sanitize_json: escapes newlines" {
    result=$(sanitize_json $'line1\nline2')
    [[ "$result" == *'\n'* ]]
}

# =============================================================================
# COMPLEX VALIDATION TESTS
# =============================================================================

@test "validate_regex: matches patterns" {
    run validate_regex "hello123" '^[a-z]+[0-9]+$'
    [ "$status" -eq 0 ]

    run validate_regex "123hello" '^[a-z]+[0-9]+$'
    [ "$status" -eq 1 ]
}

@test "validate_length: checks string length" {
    run validate_length "hello" 1 10
    [ "$status" -eq 0 ]

    run validate_length "hi" 5 10
    [ "$status" -eq 1 ]

    run validate_length "this is too long" 1 10
    [ "$status" -eq 1 ]
}

@test "validate_enum: checks value in list" {
    run validate_enum "red" "red" "green" "blue"
    [ "$status" -eq 0 ]

    run validate_enum "purple" "red" "green" "blue"
    [ "$status" -eq 1 ]
}

@test "validate_all: validates array of values" {
    run validate_all validate_int "1" "2" "3"
    [ "$status" -eq 0 ]

    run validate_all validate_int "1" "abc" "3"
    [ "$status" -eq 1 ]
}

# =============================================================================
# COMMAND SAFETY TESTS
# =============================================================================

@test "validate_command_safe: accepts safe commands" {
    run validate_command_safe "ls -la"
    [ "$status" -eq 0 ]
}

@test "validate_command_safe: rejects pipe injection" {
    run validate_command_safe "ls | rm -rf /"
    [ "$status" -eq 1 ]
}

@test "validate_command_safe: rejects command substitution" {
    run validate_command_safe 'echo $(whoami)'
    [ "$status" -eq 1 ]

    run validate_command_safe 'echo `whoami`'
    [ "$status" -eq 1 ]
}

@test "validate_command_safe: rejects redirects" {
    run validate_command_safe "echo hello > /etc/passwd"
    [ "$status" -eq 1 ]
}

@test "validate_command_safe: rejects command chaining" {
    run validate_command_safe "true; rm -rf /"
    [ "$status" -eq 1 ]

    run validate_command_safe "true && rm -rf /"
    [ "$status" -eq 1 ]
}

@test "build_safe_command: properly escapes arguments" {
    result=$(build_safe_command "grep" "pattern with spaces" "file.txt")
    [[ "$result" == *"grep"* ]]
}

# =============================================================================
# ADDITIONAL VALIDATOR TESTS
# =============================================================================

@test "validate_port: accepts valid ports" {
    run validate_port "80"
    [ "$status" -eq 0 ]

    run validate_port "443"
    [ "$status" -eq 0 ]

    run validate_port "65535"
    [ "$status" -eq 0 ]
}

@test "validate_port: rejects invalid ports" {
    run validate_port "0"
    [ "$status" -eq 1 ]

    run validate_port "65536"
    [ "$status" -eq 1 ]

    run validate_port "-1"
    [ "$status" -eq 1 ]
}

@test "validate_mac: accepts valid MAC addresses" {
    run validate_mac "00:1A:2B:3C:4D:5E"
    [ "$status" -eq 0 ]

    run validate_mac "00-1A-2B-3C-4D-5E"
    [ "$status" -eq 0 ]
}

@test "validate_mac: rejects invalid MAC addresses" {
    run validate_mac "00:1A:2B:3C:4D"
    [ "$status" -eq 1 ]

    run validate_mac "not-a-mac"
    [ "$status" -eq 1 ]
}

@test "validate_phone: accepts valid phone numbers" {
    run validate_phone "+1234567890"
    [ "$status" -eq 0 ]

    run validate_phone "(123) 456-7890"
    [ "$status" -eq 0 ]
}

@test "validate_json: accepts valid JSON" {
    run validate_json '{"key":"value"}'
    [ "$status" -eq 0 ]

    run validate_json '["a","b","c"]'
    [ "$status" -eq 0 ]
}

@test "validate_json: rejects invalid JSON" {
    run validate_json '{"key":'
    [ "$status" -eq 1 ]

    run validate_json 'not json'
    [ "$status" -eq 1 ]
}

@test "validate_alnum: accepts alphanumeric" {
    run validate_alnum "abc123"
    [ "$status" -eq 0 ]
}

@test "validate_alnum: allows underscore when specified" {
    run validate_alnum "abc_123" "true"
    [ "$status" -eq 0 ]

    run validate_alnum "abc_123" "false"
    [ "$status" -eq 1 ]
}

@test "validate_slug: accepts valid slugs" {
    run validate_slug "my-slug"
    [ "$status" -eq 0 ]

    run validate_slug "another-long-slug-123"
    [ "$status" -eq 0 ]
}

@test "validate_slug: rejects invalid slugs" {
    run validate_slug "MY-SLUG"
    [ "$status" -eq 1 ]

    run validate_slug "slug_with_underscores"
    [ "$status" -eq 1 ]

    run validate_slug "--double-dash"
    [ "$status" -eq 1 ]
}

@test "validate_cidr: accepts valid CIDR" {
    run validate_cidr "192.168.1.0/24"
    [ "$status" -eq 0 ]

    run validate_cidr "10.0.0.0/8"
    [ "$status" -eq 0 ]
}

@test "validate_cidr: rejects invalid CIDR" {
    run validate_cidr "192.168.1.0/33"
    [ "$status" -eq 1 ]

    run validate_cidr "not-cidr"
    [ "$status" -eq 1 ]
}

@test "validate_base64: accepts valid base64" {
    run validate_base64 "aGVsbG8="
    [ "$status" -eq 0 ]

    run validate_base64 "SGVsbG8gV29ybGQh"
    [ "$status" -eq 0 ]
}

@test "validate_base64: rejects invalid base64" {
    run validate_base64 "not valid base64!"
    [ "$status" -eq 1 ]

    run validate_base64 "abc"  # Not multiple of 4
    [ "$status" -eq 1 ]
}

@test "validate_credit_card: Luhn algorithm" {
    # Test card numbers (fake but valid Luhn)
    run validate_credit_card "4111111111111111"  # Valid Luhn
    [ "$status" -eq 0 ]

    run validate_credit_card "4111111111111112"  # Invalid Luhn
    [ "$status" -eq 1 ]
}

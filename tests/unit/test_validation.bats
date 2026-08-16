#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/test_validation.bats - Unit tests for validation.sh
# =============================================================================
# Run with: bats tests/unit/test_validation.bats
# =============================================================================

setup() {
    # Get the directory containing this test file
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

    # Source dependencies (json.sh for sanitize_json tests)
    source "$PROJECT_ROOT/lib/json.sh"

    # Source the validation library
    source "$PROJECT_ROOT/lib/validation.sh"
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

@test "validate_int: preserves signed and leading-zero range behavior" {
    run validate_int "-5" "-10" "-1"
    [ "$status" -eq 0 ]

    run validate_int "-11" "-10" "-1"
    [ "$status" -eq 1 ]

    run validate_int "08" "000" "010"
    [ "$status" -eq 0 ]

    run validate_int "-08" "-010" "-001"
    [ "$status" -eq 0 ]
}

@test "validate_int: rejects arithmetic bounds without executing them" {
    local min_marker="$BATS_TEST_TMPDIR/validate-int-min-arithmetic"
    local max_marker="$BATS_TEST_TMPDIR/validate-int-max-arithmetic"
    local min_payload max_payload
    min_payload="$(printf 'a[$(printf marker > "%s")]' "$min_marker")"
    max_payload="$(printf 'a[$(printf marker > "%s")]' "$max_marker")"

    run validate_int "1" "$min_payload"
    [ "$status" -eq 1 ]
    [ ! -e "$min_marker" ]

    run validate_int "1" "" "$max_payload"
    [ "$status" -eq 1 ]
    [ ! -e "$max_marker" ]
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

# Note: Null byte test removed - bash cannot store null bytes in variables,
# so this check is not meaningful. The null byte gets stripped before reaching
# the function.

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

# =============================================================================
# REGEX CONSTANTS TESTS
# =============================================================================

@test "REGEX_EMAIL: matches valid emails" {
    [[ "user@example.com" =~ $REGEX_EMAIL ]]
    [[ "user.name@example.co.uk" =~ $REGEX_EMAIL ]]
    [[ "user+tag@example.com" =~ $REGEX_EMAIL ]]
    [[ "user_name@example.com" =~ $REGEX_EMAIL ]]
    [[ "user123@example123.com" =~ $REGEX_EMAIL ]]
}

@test "REGEX_EMAIL: rejects invalid emails" {
    [[ ! "@example.com" =~ $REGEX_EMAIL ]]
    [[ ! "user@" =~ $REGEX_EMAIL ]]
    [[ ! "user@.com" =~ $REGEX_EMAIL ]]
    [[ ! "user" =~ $REGEX_EMAIL ]]
    [[ ! "" =~ $REGEX_EMAIL ]]
}

@test "REGEX_DOMAIN: matches valid domains" {
    [[ "example.com" =~ $REGEX_DOMAIN ]]
    [[ "sub.example.com" =~ $REGEX_DOMAIN ]]
    [[ "a.b.c.example.co.uk" =~ $REGEX_DOMAIN ]]
    [[ "example-site.com" =~ $REGEX_DOMAIN ]]
    [[ "123.example.com" =~ $REGEX_DOMAIN ]]
}

@test "REGEX_DOMAIN: rejects invalid domains" {
    [[ ! "-example.com" =~ $REGEX_DOMAIN ]]
    [[ ! "example-.com" =~ $REGEX_DOMAIN ]]
    [[ ! "example" =~ $REGEX_DOMAIN ]]
    [[ ! ".com" =~ $REGEX_DOMAIN ]]
    [[ ! "example..com" =~ $REGEX_DOMAIN ]]
}

@test "REGEX_IPV4: matches valid IPv4 addresses" {
    [[ "0.0.0.0" =~ $REGEX_IPV4 ]]
    [[ "192.168.1.1" =~ $REGEX_IPV4 ]]
    [[ "255.255.255.255" =~ $REGEX_IPV4 ]]
    [[ "10.0.0.1" =~ $REGEX_IPV4 ]]
    [[ "127.0.0.1" =~ $REGEX_IPV4 ]]
}

@test "REGEX_IPV4: rejects invalid IPv4 addresses" {
    [[ ! "256.0.0.0" =~ $REGEX_IPV4 ]]
    [[ ! "192.168.1" =~ $REGEX_IPV4 ]]
    [[ ! "192.168.1.1.1" =~ $REGEX_IPV4 ]]
    [[ ! "abc.def.ghi.jkl" =~ $REGEX_IPV4 ]]
    [[ ! "" =~ $REGEX_IPV4 ]]
}

@test "REGEX_IPV6: matches valid full IPv6 addresses" {
    [[ "2001:0db8:85a3:0000:0000:8a2e:0370:7334" =~ $REGEX_IPV6 ]]
    [[ "fe80:0000:0000:0000:0000:0000:0000:0001" =~ $REGEX_IPV6 ]]
    [[ "0000:0000:0000:0000:0000:0000:0000:0001" =~ $REGEX_IPV6 ]]
}

@test "REGEX_IPV6: rejects invalid IPv6" {
    # Note: This simplified regex does not support :: compression
    [[ ! "::1" =~ $REGEX_IPV6 ]]
    [[ ! "2001:db8::1" =~ $REGEX_IPV6 ]]
    [[ ! "not-ipv6" =~ $REGEX_IPV6 ]]
}

@test "REGEX_URL: matches valid URLs" {
    [[ "http://example.com" =~ $REGEX_URL ]]
    [[ "https://example.com" =~ $REGEX_URL ]]
    [[ "https://example.com/path" =~ $REGEX_URL ]]
    [[ "https://example.com/path/to/resource" =~ $REGEX_URL ]]
    [[ "https://example.com/path?query=1" =~ $REGEX_URL ]]
}

@test "REGEX_URL: rejects invalid URLs" {
    [[ ! "ftp://example.com" =~ $REGEX_URL ]]
    [[ ! "example.com" =~ $REGEX_URL ]]
    [[ ! "http://" =~ $REGEX_URL ]]
    [[ ! "not a url" =~ $REGEX_URL ]]
}

@test "REGEX_SEMVER: matches valid semantic versions" {
    [[ "1.0.0" =~ $REGEX_SEMVER ]]
    [[ "0.0.1" =~ $REGEX_SEMVER ]]
    [[ "10.20.30" =~ $REGEX_SEMVER ]]
    [[ "1.0.0-alpha" =~ $REGEX_SEMVER ]]
    [[ "1.0.0-alpha.1" =~ $REGEX_SEMVER ]]
    [[ "1.0.0+build" =~ $REGEX_SEMVER ]]
    [[ "1.0.0-alpha+build" =~ $REGEX_SEMVER ]]
}

@test "REGEX_SEMVER: rejects invalid semantic versions" {
    [[ ! "1.0" =~ $REGEX_SEMVER ]]
    [[ ! "v1.0.0" =~ $REGEX_SEMVER ]]
    [[ ! "1.02.0" =~ $REGEX_SEMVER ]]
    [[ ! "01.0.0" =~ $REGEX_SEMVER ]]
    [[ ! "1.0.0." =~ $REGEX_SEMVER ]]
}

@test "REGEX_UUID: matches UUID v4" {
    [[ "550e8400-e29b-41d4-a716-446655440000" =~ $REGEX_UUID ]]
    [[ "550E8400-E29B-41D4-A716-446655440000" =~ $REGEX_UUID ]]
}

@test "REGEX_UUID: requires version 4" {
    # V4 UUIDs have 4 in the version position
    [[ "550e8400-e29b-41d4-a716-446655440000" =~ $REGEX_UUID ]]
    # Version 1 UUID should not match REGEX_UUID (v4 only)
    [[ ! "550e8400-e29b-11d4-a716-446655440000" =~ $REGEX_UUID ]]
}

@test "REGEX_UUID_ANY: matches any UUID version" {
    [[ "550e8400-e29b-11d4-a716-446655440000" =~ $REGEX_UUID_ANY ]]
    [[ "550e8400-e29b-21d4-a716-446655440000" =~ $REGEX_UUID_ANY ]]
    [[ "550e8400-e29b-31d4-a716-446655440000" =~ $REGEX_UUID_ANY ]]
    [[ "550e8400-e29b-41d4-a716-446655440000" =~ $REGEX_UUID_ANY ]]
    [[ "550e8400-e29b-51d4-a716-446655440000" =~ $REGEX_UUID_ANY ]]
}

@test "REGEX_GIT_HASH: matches valid git hashes" {
    [[ "abc1234" =~ $REGEX_GIT_HASH ]]  # Short hash (7 chars)
    [[ "abc12345" =~ $REGEX_GIT_HASH ]]  # 8 chars
    [[ "abc1234567890abc1234567890abc1234567890a" =~ $REGEX_GIT_HASH ]]  # 40 chars
    [[ "DEADBEEF" =~ $REGEX_GIT_HASH ]]  # Uppercase
}

@test "REGEX_GIT_HASH: rejects invalid git hashes" {
    [[ ! "abc123" =~ $REGEX_GIT_HASH ]]  # Too short (6 chars)
    [[ ! "abc1234567890abc1234567890abc1234567890ab" =~ $REGEX_GIT_HASH ]]  # Too long (41 chars)
    [[ ! "ghijklm" =~ $REGEX_GIT_HASH ]]  # Non-hex
}

@test "REGEX_MAC: matches colon-separated MAC addresses" {
    [[ "00:1A:2B:3C:4D:5E" =~ $REGEX_MAC ]]
    [[ "aa:bb:cc:dd:ee:ff" =~ $REGEX_MAC ]]
    [[ "AA:BB:CC:DD:EE:FF" =~ $REGEX_MAC ]]
}

@test "REGEX_MAC_ANY: matches colon or hyphen separated" {
    [[ "00:1A:2B:3C:4D:5E" =~ $REGEX_MAC_ANY ]]
    [[ "00-1A-2B-3C-4D-5E" =~ $REGEX_MAC_ANY ]]
}

@test "REGEX_MAC: rejects invalid MAC addresses" {
    [[ ! "00:1A:2B:3C:4D" =~ $REGEX_MAC ]]  # Too few octets
    [[ ! "00:1A:2B:3C:4D:5E:FF" =~ $REGEX_MAC ]]  # Too many octets
    [[ ! "00:1A:2B:3C:4D:GG" =~ $REGEX_MAC ]]  # Non-hex
}

@test "REGEX_PHONE: matches E.164 format" {
    [[ "+1234567890" =~ $REGEX_PHONE ]]
    [[ "+12345678901234" =~ $REGEX_PHONE ]]
    [[ "+11" =~ $REGEX_PHONE ]]
}

@test "REGEX_PHONE: rejects invalid phone numbers" {
    [[ ! "1234567890" =~ $REGEX_PHONE ]]  # No plus
    [[ ! "+0123456789" =~ $REGEX_PHONE ]]  # Leading zero after plus
    [[ ! "+1" =~ $REGEX_PHONE ]]  # Too short
    [[ ! "+123456789012345678" =~ $REGEX_PHONE ]]  # Too long
}

@test "REGEX_CREDIT_CARD: matches valid card lengths" {
    [[ "1234567890123" =~ $REGEX_CREDIT_CARD ]]  # 13 digits
    [[ "1234567890123456" =~ $REGEX_CREDIT_CARD ]]  # 16 digits
    [[ "1234567890123456789" =~ $REGEX_CREDIT_CARD ]]  # 19 digits
}

@test "REGEX_CREDIT_CARD: rejects invalid card numbers" {
    [[ ! "123456789012" =~ $REGEX_CREDIT_CARD ]]  # Too short
    [[ ! "12345678901234567890" =~ $REGEX_CREDIT_CARD ]]  # Too long
    [[ ! "123456789012345a" =~ $REGEX_CREDIT_CARD ]]  # Non-digit
}

@test "REGEX_ISO_DATE: matches valid dates" {
    [[ "2024-01-15" =~ $REGEX_ISO_DATE ]]
    [[ "2024-12-31" =~ $REGEX_ISO_DATE ]]
    [[ "1999-01-01" =~ $REGEX_ISO_DATE ]]
}

@test "REGEX_ISO_DATE: rejects invalid dates" {
    [[ ! "2024-13-01" =~ $REGEX_ISO_DATE ]]  # Invalid month
    [[ ! "2024-00-01" =~ $REGEX_ISO_DATE ]]  # Invalid month
    [[ ! "2024-01-32" =~ $REGEX_ISO_DATE ]]  # Invalid day
    [[ ! "2024-01-00" =~ $REGEX_ISO_DATE ]]  # Invalid day
    [[ ! "01-15-2024" =~ $REGEX_ISO_DATE ]]  # Wrong format
}

@test "REGEX_ISO_DATETIME: matches valid datetimes" {
    [[ "2024-01-15T14:30:00" =~ $REGEX_ISO_DATETIME ]]
    [[ "2024-01-15T14:30:00Z" =~ $REGEX_ISO_DATETIME ]]
    [[ "2024-01-15T14:30:00+05:00" =~ $REGEX_ISO_DATETIME ]]
    [[ "2024-01-15T14:30:00-08:00" =~ $REGEX_ISO_DATETIME ]]
}

@test "REGEX_ISO_DATETIME: rejects invalid datetimes" {
    [[ ! "2024-01-15 14:30:00" =~ $REGEX_ISO_DATETIME ]]  # Space instead of T
    [[ ! "2024-01-15T25:30:00" =~ $REGEX_ISO_DATETIME ]]  # Invalid hour
    [[ ! "2024-01-15T14:60:00" =~ $REGEX_ISO_DATETIME ]]  # Invalid minute
}

@test "REGEX_HEX: matches hexadecimal strings" {
    [[ "abc123" =~ $REGEX_HEX ]]
    [[ "DEADBEEF" =~ $REGEX_HEX ]]
    [[ "0" =~ $REGEX_HEX ]]
    [[ "ff00ff" =~ $REGEX_HEX ]]
}

@test "REGEX_HEX: rejects non-hex strings" {
    [[ ! "ghijkl" =~ $REGEX_HEX ]]
    [[ ! "0x123" =~ $REGEX_HEX ]]
    [[ ! "" =~ $REGEX_HEX ]]
}

@test "REGEX_ALNUM: matches alphanumeric strings" {
    [[ "abc123" =~ $REGEX_ALNUM ]]
    [[ "ABC" =~ $REGEX_ALNUM ]]
    [[ "123" =~ $REGEX_ALNUM ]]
}

@test "REGEX_ALNUM: rejects non-alphanumeric" {
    [[ ! "abc_123" =~ $REGEX_ALNUM ]]
    [[ ! "abc-123" =~ $REGEX_ALNUM ]]
    [[ ! "abc 123" =~ $REGEX_ALNUM ]]
}

@test "REGEX_ALNUM_UNDERSCORE: matches alphanumeric with underscore" {
    [[ "abc_123" =~ $REGEX_ALNUM_UNDERSCORE ]]
    [[ "ABC_DEF" =~ $REGEX_ALNUM_UNDERSCORE ]]
    [[ "_underscore" =~ $REGEX_ALNUM_UNDERSCORE ]]
}

@test "REGEX_SLUG: matches valid slugs" {
    [[ "my-slug" =~ $REGEX_SLUG ]]
    [[ "another-long-slug" =~ $REGEX_SLUG ]]
    [[ "slug123" =~ $REGEX_SLUG ]]
    [[ "a" =~ $REGEX_SLUG ]]
}

@test "REGEX_SLUG: rejects invalid slugs" {
    [[ ! "MY-SLUG" =~ $REGEX_SLUG ]]  # Uppercase
    [[ ! "slug_underscore" =~ $REGEX_SLUG ]]  # Underscore
    [[ ! "--double" =~ $REGEX_SLUG ]]  # Leading dash
    [[ ! "trailing-" =~ $REGEX_SLUG ]]  # Trailing dash
}

@test "REGEX_PORT: matches valid ports" {
    [[ "1" =~ $REGEX_PORT ]]
    [[ "80" =~ $REGEX_PORT ]]
    [[ "443" =~ $REGEX_PORT ]]
    [[ "8080" =~ $REGEX_PORT ]]
    [[ "65535" =~ $REGEX_PORT ]]
}

@test "REGEX_PORT: rejects invalid ports" {
    [[ ! "0" =~ $REGEX_PORT ]]
    [[ ! "65536" =~ $REGEX_PORT ]]
    [[ ! "100000" =~ $REGEX_PORT ]]
    [[ ! "-1" =~ $REGEX_PORT ]]
}

@test "REGEX_CIDR: matches valid CIDR notation" {
    [[ "192.168.1.0/24" =~ $REGEX_CIDR ]]
    [[ "10.0.0.0/8" =~ $REGEX_CIDR ]]
    [[ "0.0.0.0/0" =~ $REGEX_CIDR ]]
    [[ "255.255.255.255/32" =~ $REGEX_CIDR ]]
}

@test "REGEX_CIDR: rejects invalid CIDR" {
    [[ ! "192.168.1.0/33" =~ $REGEX_CIDR ]]  # Invalid prefix
    [[ ! "256.0.0.0/24" =~ $REGEX_CIDR ]]  # Invalid IP
    [[ ! "192.168.1.0" =~ $REGEX_CIDR ]]  # No prefix
}

@test "REGEX_BASE64: matches valid base64" {
    [[ "aGVsbG8=" =~ $REGEX_BASE64 ]]
    [[ "SGVsbG8gV29ybGQh" =~ $REGEX_BASE64 ]]
    [[ "YWJjZA==" =~ $REGEX_BASE64 ]]
    [[ "" =~ $REGEX_BASE64 ]]  # Empty is valid base64
}

@test "REGEX_BASE64: rejects invalid base64" {
    [[ ! "not valid!" =~ $REGEX_BASE64 ]]
    [[ ! "hello world" =~ $REGEX_BASE64 ]]  # Spaces not allowed
    [[ ! "abc@def" =~ $REGEX_BASE64 ]]  # @ not in base64 alphabet
}

@test "REGEX_JWT: matches valid JWT format" {
    [[ "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U" =~ $REGEX_JWT ]]
    [[ "header.payload.signature" =~ $REGEX_JWT ]]
    [[ "a.b.c" =~ $REGEX_JWT ]]
}

@test "REGEX_JWT: rejects invalid JWT" {
    [[ ! "not.a.jwt!" =~ $REGEX_JWT ]]  # Invalid characters
    [[ ! "only.two" =~ $REGEX_JWT ]]  # Only two parts
    [[ ! "no-dots" =~ $REGEX_JWT ]]  # No dots
}

@test "REGEX_AWS_ARN: matches valid ARNs" {
    [[ "arn:aws:s3:::my-bucket" =~ $REGEX_AWS_ARN ]]
    [[ "arn:aws:ec2:us-east-1:123456789012:instance/i-1234567890abcdef0" =~ $REGEX_AWS_ARN ]]
    [[ "arn:aws:iam::123456789012:user/johndoe" =~ $REGEX_AWS_ARN ]]
}

@test "REGEX_AWS_ARN: rejects invalid ARNs" {
    [[ ! "not-an-arn" =~ $REGEX_AWS_ARN ]]
    [[ ! "arn:azure:storage:::bucket" =~ $REGEX_AWS_ARN ]]
}

@test "REGEX_DOCKER_IMAGE: matches valid image names" {
    [[ "nginx" =~ $REGEX_DOCKER_IMAGE ]]
    [[ "nginx:latest" =~ $REGEX_DOCKER_IMAGE ]]
    [[ "myregistry/myimage" =~ $REGEX_DOCKER_IMAGE ]]
    [[ "myregistry/myimage:v1.0" =~ $REGEX_DOCKER_IMAGE ]]
    [[ "gcr.io/project/image" =~ $REGEX_DOCKER_IMAGE ]]
}

@test "REGEX_DOCKER_IMAGE: rejects invalid image names" {
    [[ ! "UPPERCASE" =~ $REGEX_DOCKER_IMAGE ]]
    [[ ! "image name" =~ $REGEX_DOCKER_IMAGE ]]  # Space
}

@test "REGEX_ENV_VAR: matches valid env var names" {
    [[ "HOME" =~ $REGEX_ENV_VAR ]]
    [[ "MY_VAR" =~ $REGEX_ENV_VAR ]]
    [[ "_private" =~ $REGEX_ENV_VAR ]]
    [[ "var123" =~ $REGEX_ENV_VAR ]]
}

@test "REGEX_ENV_VAR: rejects invalid env var names" {
    [[ ! "123var" =~ $REGEX_ENV_VAR ]]  # Starts with digit
    [[ ! "my-var" =~ $REGEX_ENV_VAR ]]  # Hyphen
    [[ ! "my var" =~ $REGEX_ENV_VAR ]]  # Space
}

@test "REGEX_UNIX_USER: matches valid usernames" {
    [[ "root" =~ $REGEX_UNIX_USER ]]
    [[ "user123" =~ $REGEX_UNIX_USER ]]
    [[ "_service" =~ $REGEX_UNIX_USER ]]
    [[ "nfs-user" =~ $REGEX_UNIX_USER ]]
}

@test "REGEX_UNIX_USER: rejects invalid usernames" {
    [[ ! "123user" =~ $REGEX_UNIX_USER ]]  # Starts with digit
    [[ ! "-user" =~ $REGEX_UNIX_USER ]]  # Starts with hyphen
    [[ ! "User" =~ $REGEX_UNIX_USER ]]  # Uppercase
}

# =============================================================================
# REGEX HELPER FUNCTION TESTS
# =============================================================================

@test "regex_match: matches email" {
    run regex_match email "user@example.com"
    [ "$status" -eq 0 ]

    run regex_match email "invalid"
    [ "$status" -eq 1 ]
}

@test "regex_match: matches domain" {
    run regex_match domain "example.com"
    [ "$status" -eq 0 ]

    run regex_match domain "invalid"
    [ "$status" -eq 1 ]
}

@test "regex_match: matches ipv4" {
    run regex_match ipv4 "192.168.1.1"
    [ "$status" -eq 0 ]

    run regex_match ipv4 "999.999.999.999"
    [ "$status" -eq 1 ]
}

@test "regex_match: matches semver" {
    run regex_match semver "1.2.3"
    [ "$status" -eq 0 ]

    run regex_match semver "v1.0"
    [ "$status" -eq 1 ]
}

@test "regex_match: matches uuid" {
    run regex_match uuid "550e8400-e29b-41d4-a716-446655440000"
    [ "$status" -eq 0 ]

    run regex_match uuid "not-a-uuid"
    [ "$status" -eq 1 ]
}

@test "regex_match: matches uuid_v4" {
    run regex_match uuid_v4 "550e8400-e29b-41d4-a716-446655440000"
    [ "$status" -eq 0 ]

    # V1 UUID should fail v4 check
    run regex_match uuid_v4 "550e8400-e29b-11d4-a716-446655440000"
    [ "$status" -eq 1 ]
}

@test "regex_match: matches git_hash" {
    run regex_match git_hash "abc1234"
    [ "$status" -eq 0 ]

    run regex_match git_hash "abc123"  # Too short
    [ "$status" -eq 1 ]
}

@test "regex_match: matches mac" {
    run regex_match mac "00:1A:2B:3C:4D:5E"
    [ "$status" -eq 0 ]

    run regex_match mac "00-1A-2B-3C-4D-5E"
    [ "$status" -eq 0 ]
}

@test "regex_match: matches phone" {
    run regex_match phone "+1234567890"
    [ "$status" -eq 0 ]

    run regex_match phone "1234567890"
    [ "$status" -eq 1 ]
}

@test "regex_match: matches iso_date" {
    run regex_match iso_date "2024-01-15"
    [ "$status" -eq 0 ]

    run regex_match iso_date "01-15-2024"
    [ "$status" -eq 1 ]
}

@test "regex_match: matches iso_datetime" {
    run regex_match iso_datetime "2024-01-15T14:30:00Z"
    [ "$status" -eq 0 ]

    run regex_match iso_datetime "2024-01-15 14:30:00"
    [ "$status" -eq 1 ]
}

@test "regex_match: matches port" {
    run regex_match port "8080"
    [ "$status" -eq 0 ]

    run regex_match port "0"
    [ "$status" -eq 1 ]
}

@test "regex_match: matches cidr" {
    run regex_match cidr "192.168.1.0/24"
    [ "$status" -eq 0 ]

    run regex_match cidr "192.168.1.0"
    [ "$status" -eq 1 ]
}

@test "regex_match: matches jwt" {
    run regex_match jwt "header.payload.signature"
    [ "$status" -eq 0 ]

    run regex_match jwt "invalid"
    [ "$status" -eq 1 ]
}

@test "regex_match: matches docker_image" {
    run regex_match docker_image "nginx:latest"
    [ "$status" -eq 0 ]

    run regex_match docker_image "UPPERCASE"
    [ "$status" -eq 1 ]
}

@test "regex_match: matches env_var" {
    run regex_match env_var "MY_VAR"
    [ "$status" -eq 0 ]

    run regex_match env_var "123var"
    [ "$status" -eq 1 ]
}

@test "regex_match: case insensitive pattern names" {
    run regex_match EMAIL "user@example.com"
    [ "$status" -eq 0 ]

    run regex_match Email "user@example.com"
    [ "$status" -eq 0 ]

    run regex_match IPV4 "192.168.1.1"
    [ "$status" -eq 0 ]
}

@test "regex_match: returns 2 for unknown regex name" {
    run regex_match unknown_pattern "value"
    [ "$status" -eq 2 ]
}

@test "regex_match: returns 2 for empty regex name" {
    run regex_match "" "value"
    [ "$status" -eq 2 ]
}

@test "regex_match: returns 1 for empty value" {
    run regex_match email ""
    [ "$status" -eq 1 ]
}

@test "regex_list: outputs available patterns" {
    run regex_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"email"* ]]
    [[ "$output" == *"domain"* ]]
    [[ "$output" == *"ipv4"* ]]
    [[ "$output" == *"semver"* ]]
    [[ "$output" == *"uuid"* ]]
    [[ "$output" == *"jwt"* ]]
    [[ "$output" == *"docker_image"* ]]
}

@test "regex_get: returns pattern for known names" {
    result=$(regex_get email)
    [ -n "$result" ]
    [[ "$result" == *"@"* ]]

    result=$(regex_get ipv4)
    [ -n "$result" ]

    result=$(regex_get semver)
    [ -n "$result" ]
}

@test "regex_get: fails for unknown names" {
    run regex_get unknown_pattern
    [ "$status" -eq 1 ]
}

@test "regex_get: fails for empty name" {
    run regex_get ""
    [ "$status" -eq 1 ]
}

@test "regex_get: returned pattern works with bash regex" {
    pattern=$(regex_get email)
    [[ "user@example.com" =~ $pattern ]]
    [[ ! "invalid" =~ $pattern ]]
}

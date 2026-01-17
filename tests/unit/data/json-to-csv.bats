#!/usr/bin/env bats

load '../../helpers/setup'

setup() {
    common_setup
}

teardown() {
    common_teardown
}

# =============================================================================
# BASIC CONVERSION TESTS
# =============================================================================

@test "json-to-csv converts simple array to CSV" {
    local input=$(fixture "json" "users.json")

    run json-to-csv "$input"
    assert_success
    assert_line --index 0 --partial "id"
    assert_line --index 0 --partial "name"
    assert_line --index 0 --partial "email"
}

@test "json-to-csv outputs correct number of rows" {
    local input=$(fixture "json" "users.json")

    run json-to-csv "$input"
    assert_success
    # 1 header + 3 data rows
    assert_equal "${#lines[@]}" 4
}

@test "json-to-csv reads from stdin" {
    run bash -c 'echo '\''[{"a":1,"b":2}]'\'' | json-to-csv'
    assert_success
    assert_line --index 0 "a,b"
    assert_line --index 1 "1,2"
}

# =============================================================================
# OPTION TESTS
# =============================================================================

@test "json-to-csv --fields selects specific columns" {
    local input=$(fixture "json" "users.json")

    run json-to-csv --fields "name,email" "$input"
    assert_success
    assert_line --index 0 "name,email"
    refute_output --partial "id"
    refute_output --partial "age"
}

@test "json-to-csv --no-header omits header row" {
    local input=$(fixture "json" "users.json")

    run json-to-csv --no-header --fields "name" "$input"
    assert_success
    assert_line --index 0 "Alice Johnson"
    refute_output --partial "name"
}

@test "json-to-csv --delimiter changes separator" {
    local input=$(fixture "json" "users.json")

    run json-to-csv --delimiter ";" --fields "id,name" "$input"
    assert_success
    assert_line --index 0 "id;name"
}

@test "json-to-csv --flatten handles nested objects" {
    local input=$(fixture "json" "nested.json")

    run json-to-csv --flatten "$input"
    assert_success
    assert_output --partial "user.name"
    assert_output --partial "user.contact.email"
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

@test "json-to-csv fails on non-existent file" {
    run json-to-csv "nonexistent.json"
    assert_failure
    assert_output --partial "not found"
}

@test "json-to-csv fails on invalid JSON" {
    local tmp=$(temp_file "invalid" ".json")
    echo "not valid json" > "$tmp"

    run json-to-csv "$tmp"
    assert_failure
    assert_output --partial "Invalid JSON"
}

@test "json-to-csv shows help with --help" {
    run json-to-csv --help
    assert_success
    assert_output --partial "Usage"
    assert_output --partial "Convert JSON"
}

@test "json-to-csv shows version with --version" {
    run json-to-csv --version
    assert_success
    assert_output --partial "json-to-csv"
    assert_output --partial "1.0.0"
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

@test "json-to-csv handles empty array" {
    run bash -c 'echo '\''[]'\'' | json-to-csv'
    assert_failure
    assert_output --partial "No fields found"
}

@test "json-to-csv handles values with commas" {
    run bash -c 'echo '\''[{"a":"hello, world"}]'\'' | json-to-csv'
    assert_success
    assert_line --index 1 '"hello, world"'
}

@test "json-to-csv handles values with quotes" {
    run bash -c 'echo '\''[{"a":"say \"hello\""}]'\'' | json-to-csv'
    assert_success
    assert_line --index 1 '"say ""hello"""'
}

@test "json-to-csv handles null values" {
    run bash -c 'echo '\''[{"a":null,"b":1}]'\'' | json-to-csv'
    assert_success
    assert_line --index 1 ",1"
}

@test "json-to-csv handles single object (not array)" {
    run bash -c 'echo '\''{"a":1,"b":2}'\'' | json-to-csv'
    assert_success
    assert_line --index 0 "a,b"
    assert_line --index 1 "1,2"
}

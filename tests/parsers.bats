#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Parsers Module Tests
# =============================================================================

load 'test_helper'

setup() {
    source_lib "parsers"
    TEST_DIR=$(create_test_dir "parsers")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# parse_csv_line TESTS
# =============================================================================

@test "parse_csv_line parses simple fields" {
    parse_csv_line "a,b,c"
    [ "${#PARSE_CSV_FIELDS[@]}" = "3" ]
    [ "${PARSE_CSV_FIELDS[0]}" = "a" ]
    [ "${PARSE_CSV_FIELDS[1]}" = "b" ]
    [ "${PARSE_CSV_FIELDS[2]}" = "c" ]
}

@test "parse_csv_line handles quoted fields" {
    parse_csv_line '"John","Doe","New York"'
    [ "${PARSE_CSV_FIELDS[0]}" = "John" ]
    [ "${PARSE_CSV_FIELDS[1]}" = "Doe" ]
    [ "${PARSE_CSV_FIELDS[2]}" = "New York" ]
}

@test "parse_csv_line handles commas in quotes" {
    parse_csv_line '"Smith, John",30,"New York, NY"'
    [ "${PARSE_CSV_FIELDS[0]}" = "Smith, John" ]
    [ "${PARSE_CSV_FIELDS[1]}" = "30" ]
    [ "${PARSE_CSV_FIELDS[2]}" = "New York, NY" ]
}

@test "parse_csv_line handles escaped quotes" {
    parse_csv_line '"He said ""hello""",world'
    [ "${PARSE_CSV_FIELDS[0]}" = 'He said "hello"' ]
    [ "${PARSE_CSV_FIELDS[1]}" = "world" ]
}

@test "parse_csv_line handles empty fields" {
    parse_csv_line "a,,c"
    [ "${#PARSE_CSV_FIELDS[@]}" = "3" ]
    [ "${PARSE_CSV_FIELDS[0]}" = "a" ]
    [ "${PARSE_CSV_FIELDS[1]}" = "" ]
    [ "${PARSE_CSV_FIELDS[2]}" = "c" ]
}

@test "parse_csv_line handles empty input" {
    parse_csv_line ""
    [ "${#PARSE_CSV_FIELDS[@]}" = "0" ]
}

@test "parse_csv_line handles single field" {
    parse_csv_line "hello"
    [ "${#PARSE_CSV_FIELDS[@]}" = "1" ]
    [ "${PARSE_CSV_FIELDS[0]}" = "hello" ]
}

# =============================================================================
# parse_csv_json TESTS
# =============================================================================

@test "parse_csv_json returns JSON array" {
    local result
    result=$(parse_csv_json "a,b,c")
    [ "$result" = '["a","b","c"]' ]
}

@test "parse_csv_json handles quoted fields" {
    local result
    result=$(parse_csv_json '"John","30","NYC"')
    [ "$result" = '["John","30","NYC"]' ]
}

# =============================================================================
# parse_key_value TESTS
# =============================================================================

@test "parse_key_value parses = format" {
    local result
    result=$(printf 'host=localhost\nport=5432\n' | parse_key_value)
    [[ "$result" == *'"host":"localhost"'* ]]
    [[ "$result" == *'"port":"5432"'* ]]
}

@test "parse_key_value parses : format" {
    local result
    result=$(printf 'host: localhost\nport: 5432\n' | parse_key_value)
    [[ "$result" == *'"host":"localhost"'* ]]
    [[ "$result" == *'"port":"5432"'* ]]
}

@test "parse_key_value skips comments" {
    local result
    result=$(printf '# comment\nhost=localhost\n; another comment\n' | parse_key_value)
    [[ "$result" == *'"host":"localhost"'* ]]
    [[ "$result" != *"comment"* ]]
}

@test "parse_key_value skips blank lines" {
    local result
    result=$(printf '\n\nkey=val\n\n' | parse_key_value)
    [[ "$result" == *'"key":"val"'* ]]
}

@test "parse_key_value trims whitespace" {
    local result
    result=$(printf '  host  =  localhost  \n' | parse_key_value)
    [[ "$result" == *'"host":"localhost"'* ]]
}

@test "parse_key_value removes surrounding quotes" {
    local result
    result=$(printf 'name="John Doe"\n' | parse_key_value)
    [[ "$result" == *'"name":"John Doe"'* ]]
}

@test "parse_key_value returns empty object for empty input" {
    local result
    result=$(printf '' | parse_key_value)
    [ "$result" = "{}" ]
}

@test "parse_key_value accepts string argument" {
    local input="key1=val1"
    local result
    result=$(parse_key_value "$input")
    [[ "$result" == *'"key1":"val1"'* ]]
}

# =============================================================================
# parse_ini TESTS
# =============================================================================

@test "parse_ini parses sections" {
    local input
    input=$(printf '[database]\nhost=localhost\nport=5432\n')
    local result
    result=$(parse_ini "$input")
    [[ "$result" == *'"database":'* ]]
    [[ "$result" == *'"host":"localhost"'* ]]
    [[ "$result" == *'"port":"5432"'* ]]
}

@test "parse_ini handles multiple sections" {
    local input
    input=$(printf '[db]\nhost=localhost\n[app]\nport=3000\n')
    local result
    result=$(parse_ini "$input")
    [[ "$result" == *'"db":'* ]]
    [[ "$result" == *'"app":'* ]]
    [[ "$result" == *'"host":"localhost"'* ]]
    [[ "$result" == *'"port":"3000"'* ]]
}

@test "parse_ini skips comments" {
    local input
    input=$(printf '[main]\n# comment\nkey=val\n; also comment\n')
    local result
    result=$(parse_ini "$input")
    [[ "$result" == *'"key":"val"'* ]]
    [[ "$result" != *"comment"* ]]
}

@test "parse_ini returns empty object for empty input" {
    local result
    result=$(printf '' | parse_ini)
    [ "$result" = "{}" ]
}

@test "parse_ini handles keys before first section" {
    local input
    input=$(printf 'global_key=global_val\n[section]\nkey=val\n')
    local result
    result=$(parse_ini "$input")
    [[ "$result" == *'"_global":'* ]]
    [[ "$result" == *'"global_key":"global_val"'* ]]
}

@test "parse_ini handles colon separator" {
    local input
    input=$(printf '[server]\nhost: 0.0.0.0\nport: 8080\n')
    local result
    result=$(parse_ini "$input")
    [[ "$result" == *'"host":"0.0.0.0"'* ]]
    [[ "$result" == *'"port":"8080"'* ]]
}

# =============================================================================
# parse_url TESTS
# =============================================================================

@test "parse_url parses full URL" {
    local result
    result=$(parse_url "https://user:pass@host.com:8080/path?query=1#frag")
    [[ "$result" == *'"scheme":"https"'* ]]
    [[ "$result" == *'"host":"host.com"'* ]]
    [[ "$result" == *'"port":8080'* ]]
    [[ "$result" == *'"path":"/path"'* ]]
    [[ "$result" == *'"query":"query=1"'* ]]
    [[ "$result" == *'"fragment":"frag"'* ]]
    [[ "$result" == *'"user":"user"'* ]]
    [[ "$result" == *'"password":"pass"'* ]]
}

@test "parse_url handles simple URL" {
    local result
    result=$(parse_url "http://example.com/page")
    [[ "$result" == *'"scheme":"http"'* ]]
    [[ "$result" == *'"host":"example.com"'* ]]
    [[ "$result" == *'"path":"/page"'* ]]
}

@test "parse_url handles URL without scheme" {
    local result
    result=$(parse_url "localhost:3000/api")
    [[ "$result" == *'"host":"localhost"'* ]]
    [[ "$result" == *'"port":3000'* ]]
    [[ "$result" == *'"path":"/api"'* ]]
}

@test "parse_url handles URL without path" {
    local result
    result=$(parse_url "https://example.com")
    [[ "$result" == *'"scheme":"https"'* ]]
    [[ "$result" == *'"host":"example.com"'* ]]
}

@test "parse_url handles URL with only host:port" {
    local result
    result=$(parse_url "localhost:8080")
    [[ "$result" == *'"host":"localhost"'* ]]
    [[ "$result" == *'"port":8080'* ]]
}

@test "parse_url returns error for empty input" {
    local result
    result=$(parse_url "") || true
    [[ "$result" == *'"error"'* ]]
}

@test "parse_url handles query without fragment" {
    local result
    result=$(parse_url "http://api.com/search?q=test&limit=10")
    [[ "$result" == *'"query":"q=test&limit=10"'* ]]
}

# =============================================================================
# parse_semver TESTS
# =============================================================================

@test "parse_semver parses basic version" {
    local result
    result=$(parse_semver "1.2.3")
    [[ "$result" == *'"major":1'* ]]
    [[ "$result" == *'"minor":2'* ]]
    [[ "$result" == *'"patch":3'* ]]
}

@test "parse_semver handles leading v" {
    local result
    result=$(parse_semver "v2.0.1")
    [[ "$result" == *'"major":2'* ]]
    [[ "$result" == *'"minor":0'* ]]
    [[ "$result" == *'"patch":1'* ]]
}

@test "parse_semver parses prerelease" {
    local result
    result=$(parse_semver "1.0.0-beta.1")
    [[ "$result" == *'"prerelease":"beta.1"'* ]]
}

@test "parse_semver parses build metadata" {
    local result
    result=$(parse_semver "1.0.0+build.123")
    [[ "$result" == *'"build":"build.123"'* ]]
}

@test "parse_semver parses full semver" {
    local result
    result=$(parse_semver "1.2.3-alpha+20240101")
    [[ "$result" == *'"major":1'* ]]
    [[ "$result" == *'"minor":2'* ]]
    [[ "$result" == *'"patch":3'* ]]
    [[ "$result" == *'"prerelease":"alpha"'* ]]
    [[ "$result" == *'"build":"20240101"'* ]]
}

@test "parse_semver handles major-only version" {
    local result
    result=$(parse_semver "5")
    [[ "$result" == *'"major":5'* ]]
    [[ "$result" == *'"minor":0'* ]]
    [[ "$result" == *'"patch":0'* ]]
}

@test "parse_semver handles major.minor only" {
    local result
    result=$(parse_semver "3.7")
    [[ "$result" == *'"major":3'* ]]
    [[ "$result" == *'"minor":7'* ]]
    [[ "$result" == *'"patch":0'* ]]
}

@test "parse_semver returns error for invalid input" {
    local result
    ! result=$(parse_semver "abc" 2>/dev/null) || [[ "$result" == *'"error"'* ]]
}

@test "parse_semver returns error for empty input" {
    local result
    result=$(parse_semver "") || true
    [[ "$result" == *'"error"'* ]]
}

@test "parse_semver includes string representation" {
    local result
    result=$(parse_semver "1.2.3")
    [[ "$result" == *'"string":"1.2.3"'* ]]
}

# =============================================================================
# semver_compare TESTS
# =============================================================================

@test "semver_compare returns 0 for equal versions" {
    local result
    result=$(semver_compare "1.2.3" "1.2.3")
    [ "$result" = "0" ]
}

@test "semver_compare returns 1 for greater major" {
    local result
    result=$(semver_compare "2.0.0" "1.9.9")
    [ "$result" = "1" ]
}

@test "semver_compare returns -1 for lesser major" {
    local result
    result=$(semver_compare "1.0.0" "2.0.0")
    [ "$result" = "-1" ]
}

@test "semver_compare returns 1 for greater minor" {
    local result
    result=$(semver_compare "1.3.0" "1.2.9")
    [ "$result" = "1" ]
}

@test "semver_compare returns -1 for lesser minor" {
    local result
    result=$(semver_compare "1.2.0" "1.3.0")
    [ "$result" = "-1" ]
}

@test "semver_compare returns 1 for greater patch" {
    local result
    result=$(semver_compare "1.2.4" "1.2.3")
    [ "$result" = "1" ]
}

@test "semver_compare returns -1 for lesser patch" {
    local result
    result=$(semver_compare "1.2.3" "1.2.4")
    [ "$result" = "-1" ]
}

@test "semver_compare handles v prefix" {
    local result
    result=$(semver_compare "v1.2.3" "1.2.3")
    [ "$result" = "0" ]
}

@test "semver_compare ignores prerelease for ordering" {
    local result
    result=$(semver_compare "1.2.3-alpha" "1.2.3-beta")
    [ "$result" = "0" ]
}

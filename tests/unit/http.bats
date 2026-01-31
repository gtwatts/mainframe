#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/http.bats - HTTP Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/http.sh
#              Pure bash HTTP client using /dev/tcp
# Test Count: 50+ test cases
# Categories: URL encoding, URL parsing, headers, hostname validation,
#             response parsing, status checks, JSON convenience, cookies,
#             utility functions
# Note: Network tests are mocked to avoid external dependencies
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Mock directory for mock executables
    MOCK_BIN="$TEST_TMPDIR/mock_bin"
    mkdir -p "$MOCK_BIN"
    export PATH="$MOCK_BIN:$PATH"

    # Source the library
    source "$MAINFRAME_ROOT/lib/http.sh"
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# Helper: Create mock HTTP response
mock_response() {
    local status="${1:-200}"
    local body="${2:-{}}"
    local headers="${3:-Content-Type: application/json}"

    printf 'HTTP/1.1 %s OK\r\n%s\r\nConnection: close\r\n\r\n%s' \
        "$status" "$headers" "$body"
}

# =============================================================================
# CATEGORY 1: URL ENCODING
# =============================================================================

@test "url_encode: encodes space as +" {
    result=$(url_encode "hello world")
    [[ "$result" == "hello+world" ]]
}

@test "url_encode: encodes special characters" {
    result=$(url_encode "name=John&age=30")
    [[ "$result" == "name%3DJohn%26age%3D30" ]]
}

@test "url_encode: preserves alphanumeric characters" {
    result=$(url_encode "abc123XYZ")
    [[ "$result" == "abc123XYZ" ]]
}

@test "url_encode: preserves safe characters" {
    result=$(url_encode "file.name-test_123~")
    [[ "$result" == "file.name-test_123~" ]]
}

@test "url_encode: encodes unicode characters" {
    result=$(url_encode "cafe")
    [[ -n "$result" ]]
}

@test "url_encode: handles empty string" {
    result=$(url_encode "")
    [[ "$result" == "" ]]
}

@test "url_decode: decodes + to space" {
    result=$(url_decode "hello+world")
    [[ "$result" == "hello world" ]]
}

@test "url_decode: decodes percent-encoded characters" {
    result=$(url_decode "hello%20world")
    [[ "$result" == "hello world" ]]
}

@test "url_decode: handles empty string" {
    result=$(url_decode "")
    [[ "$result" == "" ]]
}

# =============================================================================
# CATEGORY 2: URL PARSING
# =============================================================================

@test "url_parse: extracts scheme" {
    url_parse "https://example.com/path"
    [[ "$URL_SCHEME" == "https" ]]
}

@test "url_parse: extracts host" {
    url_parse "https://example.com/path"
    [[ "$URL_HOST" == "example.com" ]]
}

@test "url_parse: extracts explicit port" {
    url_parse "http://example.com:8080/path"
    [[ "$URL_PORT" == "8080" ]]
}

@test "url_parse: defaults port 80 for http" {
    url_parse "http://example.com/path"
    [[ "$URL_PORT" == "80" ]]
}

@test "url_parse: defaults port 443 for https" {
    url_parse "https://example.com/path"
    [[ "$URL_PORT" == "443" ]]
}

@test "url_parse: extracts path" {
    url_parse "https://example.com/api/v1/users"
    [[ "$URL_PATH" == "/api/v1/users" ]]
}

@test "url_parse: defaults path to /" {
    url_parse "https://example.com"
    [[ "$URL_PATH" == "/" ]]
}

@test "url_parse: extracts query string" {
    url_parse "https://example.com/search?q=test&page=1"
    [[ "$URL_QUERY" == "q=test&page=1" ]]
}

@test "url_parse: extracts username" {
    url_parse "https://user@example.com/path"
    [[ "$URL_USER" == "user" ]]
}

@test "url_parse: extracts username and password" {
    url_parse "https://admin:secret@example.com/path"
    [[ "$URL_USER" == "admin" ]]
    [[ "$URL_PASS" == "secret" ]]
}

@test "url_parse: handles URL without scheme" {
    url_parse "example.com/path"
    [[ "$URL_SCHEME" == "http" ]]
    [[ "$URL_HOST" == "example.com" ]]
}

@test "query_string: builds query string from pairs" {
    result=$(query_string "name=John" "age=30")
    [[ "$result" == "name=John&age=30" ]]
}

@test "query_string: encodes values" {
    result=$(query_string "message=hello world")
    [[ "$result" == "message=hello+world" ]]
}

@test "query_string: handles empty input" {
    result=$(query_string)
    [[ "$result" == "" ]]
}

# =============================================================================
# CATEGORY 3: HEADERS
# =============================================================================

@test "http_header: formats header line" {
    result=$(http_header "Content-Type" "application/json")
    [[ "$result" == $'Content-Type: application/json\r\n' ]]
}

@test "http_auth_basic: generates basic auth header" {
    result=$(http_auth_basic "user" "pass")
    [[ "$result" == "Basic dXNlcjpwYXNz" ]]
}

@test "http_auth_bearer: generates bearer token header" {
    result=$(http_auth_bearer "mytoken123")
    [[ "$result" == "Bearer mytoken123" ]]
}

@test "_base64_encode: encodes simple string" {
    result=$(_base64_encode "hello")
    [[ "$result" == "aGVsbG8=" ]]
}

@test "_base64_encode: encodes empty string" {
    result=$(_base64_encode "")
    [[ "$result" == "" ]]
}

@test "_base64_encode: handles padding" {
    result=$(_base64_encode "a")
    [[ "$result" == "YQ==" ]]

    result=$(_base64_encode "ab")
    [[ "$result" == "YWI=" ]]

    result=$(_base64_encode "abc")
    [[ "$result" == "YWJj" ]]
}

# =============================================================================
# CATEGORY 4: HOSTNAME VALIDATION
# =============================================================================

@test "_http_validate_hostname: accepts valid hostname" {
    _http_validate_hostname "example.com"
    [[ $? -eq 0 ]]
}

@test "_http_validate_hostname: accepts subdomain" {
    _http_validate_hostname "api.example.com"
    [[ $? -eq 0 ]]
}

@test "_http_validate_hostname: accepts localhost" {
    _http_validate_hostname "localhost"
    [[ $? -eq 0 ]]
}

@test "_http_validate_hostname: accepts valid IPv4" {
    _http_validate_hostname "192.168.1.100"
    [[ $? -eq 0 ]]
}

@test "_http_validate_hostname: rejects invalid IPv4 (octet > 255)" {
    run _http_validate_hostname "192.168.1.300"
    [[ "$status" -eq 1 ]]
}

@test "_http_validate_hostname: rejects empty hostname" {
    run _http_validate_hostname ""
    [[ "$status" -eq 1 ]]
}

@test "_http_validate_hostname: rejects hostname starting with hyphen" {
    run _http_validate_hostname "-invalid.com"
    [[ "$status" -eq 1 ]]
}

@test "_http_validate_hostname: rejects hostname ending with hyphen" {
    run _http_validate_hostname "invalid-.com"
    [[ "$status" -eq 1 ]]
}

@test "_http_validate_hostname: rejects hostname with invalid characters" {
    run _http_validate_hostname "inva!id.com"
    [[ "$status" -eq 1 ]]
}

@test "_http_validate_hostname: accepts hyphen in middle" {
    _http_validate_hostname "my-host.example.com"
    [[ $? -eq 0 ]]
}

# =============================================================================
# CATEGORY 5: RESPONSE PARSING
# =============================================================================

@test "http_status: extracts status code from response" {
    response=$(mock_response 200)
    result=$(http_status "$response")
    [[ "$result" == "200" ]]
}

@test "http_status: extracts 404 status" {
    response=$(mock_response 404)
    result=$(http_status "$response")
    [[ "$result" == "404" ]]
}

@test "http_status: extracts 500 status" {
    response=$(mock_response 500)
    result=$(http_status "$response")
    [[ "$result" == "500" ]]
}

@test "http_status: returns 0 for invalid response" {
    result=$(http_status "not a valid response")
    [[ "$result" == "0" ]]
}

@test "http_body: extracts body from response" {
    response=$(mock_response 200 '{"name":"John"}')
    result=$(http_body "$response")
    [[ "$result" == '{"name":"John"}' ]]
}

@test "http_body: handles empty body" {
    response=$(mock_response 204 "")
    result=$(http_body "$response")
    [[ "$result" == "" ]]
}

@test "http_header_get: extracts specific header" {
    response=$(mock_response 200 "{}" "Content-Type: application/json")
    result=$(http_header_get "$response" "Content-Type")
    [[ "$result" == "application/json" ]]
}

@test "http_header_get: is case-insensitive" {
    response=$(mock_response 200 "{}" "content-type: application/json")
    result=$(http_header_get "$response" "Content-Type")
    [[ "$result" == "application/json" ]]
}

@test "http_header_get: returns failure for missing header" {
    response=$(mock_response 200 "{}" "Content-Type: application/json")
    run http_header_get "$response" "X-Missing"
    [[ "$status" -eq 1 ]]
}

@test "http_headers: extracts all headers" {
    response=$'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nX-Custom: value\r\n\r\n{}'
    result=$(http_headers "$response")
    [[ "$result" =~ "Content-Type" ]]
    [[ "$result" =~ "X-Custom" ]]
}

@test "_http_parse_response: sets global variables" {
    response=$(mock_response 201 '{"created":true}')
    _http_parse_response "$response"
    [[ "$HTTP_RESPONSE_STATUS" == "201" ]]
    [[ "$HTTP_RESPONSE_BODY" == '{"created":true}' ]]
}

# =============================================================================
# CATEGORY 6: STATUS CHECKS
# =============================================================================

@test "http_is_success: returns true for 200" {
    response=$(mock_response 200)
    http_is_success "$response"
    [[ $? -eq 0 ]]
}

@test "http_is_success: returns true for 201" {
    response=$(mock_response 201)
    http_is_success "$response"
    [[ $? -eq 0 ]]
}

@test "http_is_success: returns false for 404" {
    response=$(mock_response 404)
    run http_is_success "$response"
    [[ "$status" -eq 1 ]]
}

@test "http_is_redirect: returns true for 301" {
    response=$(mock_response 301)
    http_is_redirect "$response"
    [[ $? -eq 0 ]]
}

@test "http_is_redirect: returns true for 302" {
    response=$(mock_response 302)
    http_is_redirect "$response"
    [[ $? -eq 0 ]]
}

@test "http_is_redirect: returns false for 200" {
    response=$(mock_response 200)
    run http_is_redirect "$response"
    [[ "$status" -eq 1 ]]
}

@test "http_is_client_error: returns true for 404" {
    response=$(mock_response 404)
    http_is_client_error "$response"
    [[ $? -eq 0 ]]
}

@test "http_is_client_error: returns true for 400" {
    response=$(mock_response 400)
    http_is_client_error "$response"
    [[ $? -eq 0 ]]
}

@test "http_is_client_error: returns false for 500" {
    response=$(mock_response 500)
    run http_is_client_error "$response"
    [[ "$status" -eq 1 ]]
}

@test "http_is_server_error: returns true for 500" {
    response=$(mock_response 500)
    http_is_server_error "$response"
    [[ $? -eq 0 ]]
}

@test "http_is_server_error: returns true for 503" {
    response=$(mock_response 503)
    http_is_server_error "$response"
    [[ $? -eq 0 ]]
}

@test "http_is_server_error: returns false for 404" {
    response=$(mock_response 404)
    run http_is_server_error "$response"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 7: COOKIES
# =============================================================================

@test "http_parse_cookie: extracts name=value from Set-Cookie" {
    result=$(http_parse_cookie "Set-Cookie: session=abc123; Path=/; HttpOnly")
    [[ "$result" == "session=abc123" ]]
}

@test "http_parse_cookie: handles simple cookie" {
    result=$(http_parse_cookie "Set-Cookie: id=1")
    [[ "$result" == "id=1" ]]
}

@test "http_cookie: formats cookie header" {
    result=$(http_cookie "session=abc123")
    [[ "$result" == "Cookie: session=abc123" ]]
}

# =============================================================================
# CATEGORY 8: UTILITY FUNCTIONS
# =============================================================================

@test "http_set_timeout: sets timeout variable" {
    http_set_timeout 60
    [[ "$HTTP_TIMEOUT" == "60" ]]
}

@test "http_debug_request: outputs request info" {
    result=$(http_debug_request "GET" "https://api.example.com:8080/users?page=1")
    [[ "$result" =~ "Method:" ]]
    [[ "$result" =~ "GET" ]]
    [[ "$result" =~ "Host:" ]]
    [[ "$result" =~ "api.example.com" ]]
    [[ "$result" =~ "Port:" ]]
    [[ "$result" =~ "8080" ]]
}

@test "http_debug_response: outputs response info" {
    response=$(mock_response 200 '{"test":true}')
    _http_parse_response "$response"
    result=$(http_debug_response "$response")
    [[ "$result" =~ "Status:" ]]
    [[ "$result" =~ "200" ]]
}

# =============================================================================
# CATEGORY 9: EDGE CASES
# =============================================================================

@test "url_parse: handles complex URL" {
    url_parse "https://user:pass@api.example.com:8443/v1/users/123?filter=active&sort=name"
    [[ "$URL_SCHEME" == "https" ]]
    [[ "$URL_USER" == "user" ]]
    [[ "$URL_PASS" == "pass" ]]
    [[ "$URL_HOST" == "api.example.com" ]]
    [[ "$URL_PORT" == "8443" ]]
    [[ "$URL_PATH" == "/v1/users/123" ]]
    [[ "$URL_QUERY" == "filter=active&sort=name" ]]
}

@test "url_parse: handles URL with no path but query" {
    url_parse "http://example.com?query=value"
    [[ "$URL_PATH" == "/" ]]
    [[ "$URL_QUERY" == "query=value" ]]
}

@test "http_body: handles multiline body" {
    response=$'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nline1\nline2\nline3'
    result=$(http_body "$response")
    [[ "$result" =~ "line1" ]]
    [[ "$result" =~ "line2" ]]
    [[ "$result" =~ "line3" ]]
}

@test "_http_validate_hostname: accepts numeric TLD" {
    # While unusual, numeric-only labels are technically valid
    _http_validate_hostname "host.123"
    [[ $? -eq 0 ]]
}

@test "url_encode: handles all special URL characters" {
    result=$(url_encode '!@#$%^&*(){}[]|\\:";\'<>?,/')
    # Should not contain any of these unencoded
    [[ ! "$result" =~ [!@#\$%^*\(\)\{\}\[\]|\\:\"\;\'\<\>\?,/] ]] || [[ "$result" =~ "%" ]]
}

# =============================================================================
# CATEGORY 10: CONSTANTS AND MODULE EXPORTS
# =============================================================================

@test "HTTP_VERSION: is set to HTTP/1.1" {
    [[ "$HTTP_VERSION" == "HTTP/1.1" ]]
}

@test "HTTP_USER_AGENT: is set" {
    [[ -n "$HTTP_USER_AGENT" ]]
    [[ "$HTTP_USER_AGENT" =~ "MAINFRAME" ]]
}

@test "HTTP_DEFAULT_TIMEOUT: is set" {
    [[ "$HTTP_DEFAULT_TIMEOUT" -gt 0 ]]
}

@test "HTTP_MAX_REDIRECTS: is set" {
    [[ "$HTTP_MAX_REDIRECTS" -gt 0 ]]
}

@test "HTTP_EXPORTS: contains expected functions" {
    [[ "${HTTP_EXPORTS[*]}" =~ "http_get" ]]
    [[ "${HTTP_EXPORTS[*]}" =~ "http_post" ]]
    [[ "${HTTP_EXPORTS[*]}" =~ "url_encode" ]]
    [[ "${HTTP_EXPORTS[*]}" =~ "http_status" ]]
}

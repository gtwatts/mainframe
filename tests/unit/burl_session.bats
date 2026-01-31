#!/usr/bin/env bats
# =============================================================================
# tests/unit/burl_session.bats - Tests for lib/burl_session.sh
# =============================================================================

# Load helper for common setup
load '../test_helper'

setup() {
    # Set MAINFRAME_ROOT and load libraries
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."

    # Clear any prior load flag to allow re-sourcing
    unset _MAINFRAME_BURL_SESSION_LOADED

    source "${MAINFRAME_ROOT}/lib/common.sh"
    source "${MAINFRAME_ROOT}/lib/burl_session.sh"

    # Create temp directory for test sessions
    TEST_SESSION_DIR=$(mktemp -d)
    TEST_SESSION="${TEST_SESSION_DIR}/test_session.json"

    # Reset session state before each test
    _BURL_SESSION_PATH=""
    _BURL_SESSION_COOKIES=()
    _BURL_SESSION_AUTH_TYPE=""
    _BURL_SESSION_AUTH_TOKEN=""
    _BURL_SESSION_REFRESH_TOKEN=""
    _BURL_SESSION_AUTH_EXPIRES=0
    _BURL_SESSION_CSRF_HEADER=""
    _BURL_SESSION_CSRF_TOKEN=""
    _BURL_SESSION_TTL=0
    _BURL_SESSION_DOMAIN=""
}

teardown() {
    # Clean up temp files
    [[ -d "$TEST_SESSION_DIR" ]] && rm -rf "$TEST_SESSION_DIR"
}

# =============================================================================
# SESSION INITIALIZATION TESTS
# =============================================================================

@test "burl_session_init creates new session file" {
    burl_session_init "$TEST_SESSION"
    [[ -f "$TEST_SESSION" ]]
}

@test "burl_session_init with --ttl sets TTL" {
    burl_session_init "$TEST_SESSION" --ttl 7200
    [[ "$_BURL_SESSION_TTL" -eq 7200 ]]
}

@test "burl_session_init with --domain sets domain" {
    burl_session_init "$TEST_SESSION" --domain "api.example.com"
    [[ "$_BURL_SESSION_DOMAIN" == "api.example.com" ]]
}

@test "burl_session_init uses default TTL" {
    BURL_SESSION_DEFAULT_TTL=1800
    burl_session_init "$TEST_SESSION"
    [[ "$_BURL_SESSION_TTL" -eq 1800 ]]
}

@test "burl_session_init returns error for empty path" {
    run burl_session_init ""
    [[ "$status" -ne 0 ]]
}

@test "burl_session_init loads existing session" {
    # Create session with cookie using set_cookie
    burl_session_init "$TEST_SESSION"
    burl_session_set_cookie "session_id=abc123"

    # Verify cookie was set
    [[ "${_BURL_SESSION_COOKIES[session_id]}" == "abc123" ]]
}

@test "burl_session_init creates parent directories" {
    local nested="${TEST_SESSION_DIR}/a/b/c/session.json"
    burl_session_init "$nested"
    [[ -f "$nested" ]]
}

# =============================================================================
# SESSION SAVE/LOAD TESTS
# =============================================================================

@test "burl_session_save persists cookies" {
    burl_session_init "$TEST_SESSION"
    _BURL_SESSION_COOKIES[mycookie]="myvalue"
    burl_session_save

    local content
    content=$(<"$TEST_SESSION")
    [[ "$content" == *"mycookie"* ]]
    [[ "$content" == *"myvalue"* ]]
}

@test "burl_session_save persists auth" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_auth --type bearer --token "abc123"

    local content
    content=$(<"$TEST_SESSION")
    [[ "$content" == *"bearer"* ]]
    [[ "$content" == *"abc123"* ]]
}

@test "burl_session_load returns error for missing file" {
    run burl_session_load "/nonexistent/path.json"
    [[ "$status" -ne 0 ]]
}

@test "burl_session_load restores cookies" {
    # Create session with cookies using set_cookie (tests persistence)
    burl_session_init "$TEST_SESSION"
    burl_session_set_cookie "foo=bar"

    # Verify content was persisted
    local content
    content=$(<"$TEST_SESSION")
    [[ "$content" == *"foo"* ]]
    [[ "$content" == *"bar"* ]]
}

@test "burl_session_load restores auth" {
    # Create session with auth and verify persistence
    burl_session_init "$TEST_SESSION"
    burl_session_set_auth --type basic --token "dXNlcjpwYXNz" --expires-at 9999999999

    # Verify auth was persisted to file
    local content
    content=$(<"$TEST_SESSION")
    [[ "$content" == *"basic"* ]]
    [[ "$content" == *"dXNlcjpwYXNz"* ]]
}

@test "burl_session_save preserves created_at on update" {
    burl_session_init "$TEST_SESSION"

    local content1
    content1=$(<"$TEST_SESSION")
    local created1
    created1=$(echo "$content1" | grep -o '"created_at"[[:space:]]*:[[:space:]]*"[^"]*"')

    sleep 1
    _BURL_SESSION_COOKIES[new]="value"
    burl_session_save

    local content2
    content2=$(<"$TEST_SESSION")
    local created2
    created2=$(echo "$content2" | grep -o '"created_at"[[:space:]]*:[[:space:]]*"[^"]*"')

    [[ "$created1" == "$created2" ]]
}

# =============================================================================
# COOKIE MANAGEMENT TESTS
# =============================================================================

@test "burl_session_cookie returns cookie value" {
    burl_session_init "$TEST_SESSION"
    _BURL_SESSION_COOKIES[test_cookie]="test_value"

    local result
    result=$(burl_session_cookie "test_cookie")
    [[ "$result" == "test_value" ]]
}

@test "burl_session_cookie returns empty for missing cookie" {
    burl_session_init "$TEST_SESSION"
    local result
    result=$(burl_session_cookie "nonexistent")
    [[ -z "$result" ]]
}

@test "burl_session_set_cookie parses simple cookie" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_cookie "session_id=abc123"

    [[ "${_BURL_SESSION_COOKIES[session_id]}" == "abc123" ]]
}

@test "burl_session_set_cookie parses cookie with attributes" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_cookie "session_id=xyz789; Path=/; HttpOnly; Secure"

    [[ "${_BURL_SESSION_COOKIES[session_id]}" == "xyz789" ]]
}

@test "burl_session_set_cookie handles whitespace" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_cookie "  token  =  value123  ; Path=/"

    [[ "${_BURL_SESSION_COOKIES[token]}" == "value123" ]]
}

@test "burl_session_set_cookie persists to file" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_cookie "persisted=yes"

    local content
    content=$(<"$TEST_SESSION")
    [[ "$content" == *"persisted"* ]]
}

@test "burl_session_cookie_header returns empty when no cookies" {
    burl_session_init "$TEST_SESSION"
    run burl_session_cookie_header
    [[ "$status" -ne 0 ]]
}

@test "burl_session_cookie_header formats single cookie" {
    burl_session_init "$TEST_SESSION"
    _BURL_SESSION_COOKIES[session]="abc"

    local result
    result=$(burl_session_cookie_header)
    [[ "$result" == "Cookie: session=abc" ]]
}

@test "burl_session_cookie_header formats multiple cookies" {
    burl_session_init "$TEST_SESSION"
    _BURL_SESSION_COOKIES[a]="1"
    _BURL_SESSION_COOKIES[b]="2"

    local result
    result=$(burl_session_cookie_header)
    [[ "$result" == *"a=1"* ]]
    [[ "$result" == *"b=2"* ]]
    [[ "$result" == "Cookie:"* ]]
}

@test "burl_session_clear_cookies removes all cookies" {
    burl_session_init "$TEST_SESSION"
    _BURL_SESSION_COOKIES[a]="1"
    _BURL_SESSION_COOKIES[b]="2"

    burl_session_clear_cookies

    [[ ${#_BURL_SESSION_COOKIES[@]} -eq 0 ]]
}

# =============================================================================
# AUTHENTICATION TESTS
# =============================================================================

@test "burl_session_set_auth sets bearer token" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_auth --type bearer --token "eyJhbGciOiJIUzI1NiJ9"

    [[ "$_BURL_SESSION_AUTH_TYPE" == "bearer" ]]
    [[ "$_BURL_SESSION_AUTH_TOKEN" == "eyJhbGciOiJIUzI1NiJ9" ]]
}

@test "burl_session_set_auth sets refresh token" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_auth --type bearer --token "access" --refresh-token "refresh123"

    [[ "$_BURL_SESSION_REFRESH_TOKEN" == "refresh123" ]]
}

@test "burl_session_set_auth sets expires-at" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_auth --type bearer --token "tok" --expires-at 1738344000

    [[ "$_BURL_SESSION_AUTH_EXPIRES" -eq 1738344000 ]]
}

@test "burl_session_auth_header returns bearer format" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_auth --type bearer --token "mytoken"

    local result
    result=$(burl_session_auth_header)
    [[ "$result" == "Authorization: Bearer mytoken" ]]
}

@test "burl_session_auth_header returns basic format" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_auth --type basic --token "dXNlcjpwYXNz"

    local result
    result=$(burl_session_auth_header)
    [[ "$result" == "Authorization: Basic dXNlcjpwYXNz" ]]
}

@test "burl_session_auth_header returns api-key format" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_auth --type api-key --token "sk-12345"

    local result
    result=$(burl_session_auth_header)
    [[ "$result" == "X-API-Key: sk-12345" ]]
}

@test "burl_session_auth_header returns empty when no token" {
    burl_session_init "$TEST_SESSION"
    run burl_session_auth_header
    [[ "$status" -ne 0 ]]
}

@test "burl_session_auth_expired returns false when no expiry" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_auth --type bearer --token "tok"

    run burl_session_auth_expired
    [[ "$status" -ne 0 ]]
}

@test "burl_session_auth_expired returns true for past expiry" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_auth --type bearer --token "tok" --expires-at 1000000000

    run burl_session_auth_expired
    [[ "$status" -eq 0 ]]
}

@test "burl_session_auth_expired returns false for future expiry" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_auth --type bearer --token "tok" --expires-at 9999999999

    run burl_session_auth_expired
    [[ "$status" -ne 0 ]]
}

@test "burl_session_refresh_token returns refresh token" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_auth --type bearer --token "access" --refresh-token "refresh_abc"

    local result
    result=$(burl_session_refresh_token)
    [[ "$result" == "refresh_abc" ]]
}

@test "burl_session_clear_auth removes all auth" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_auth --type bearer --token "tok" --refresh-token "ref"
    burl_session_clear_auth

    [[ -z "$_BURL_SESSION_AUTH_TYPE" ]]
    [[ -z "$_BURL_SESSION_AUTH_TOKEN" ]]
    [[ -z "$_BURL_SESSION_REFRESH_TOKEN" ]]
}

# =============================================================================
# CSRF MANAGEMENT TESTS
# =============================================================================

@test "burl_session_set_csrf sets token with default header" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_csrf "csrf_token_value"

    [[ "$_BURL_SESSION_CSRF_TOKEN" == "csrf_token_value" ]]
    [[ "$_BURL_SESSION_CSRF_HEADER" == "X-CSRF-Token" ]]
}

@test "burl_session_set_csrf sets custom header name" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_csrf "token123" "X-XSRF-Token"

    [[ "$_BURL_SESSION_CSRF_TOKEN" == "token123" ]]
    [[ "$_BURL_SESSION_CSRF_HEADER" == "X-XSRF-Token" ]]
}

@test "burl_session_csrf_header returns formatted header" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_csrf "abc123" "X-Custom-Token"

    local result
    result=$(burl_session_csrf_header)
    [[ "$result" == "X-Custom-Token: abc123" ]]
}

@test "burl_session_csrf_header returns empty when no token" {
    burl_session_init "$TEST_SESSION"
    run burl_session_csrf_header
    [[ "$status" -ne 0 ]]
}

@test "burl_session_csrf_token returns raw token" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_csrf "raw_csrf_value"

    local result
    result=$(burl_session_csrf_token)
    [[ "$result" == "raw_csrf_value" ]]
}

@test "burl_session_clear_csrf removes CSRF data" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_csrf "token" "Header"
    burl_session_clear_csrf

    [[ -z "$_BURL_SESSION_CSRF_TOKEN" ]]
    [[ -z "$_BURL_SESSION_CSRF_HEADER" ]]
}

# =============================================================================
# RESPONSE HEADER PARSING TESTS
# =============================================================================

@test "burl_session_update_from_response parses Set-Cookie" {
    burl_session_init "$TEST_SESSION"
    local headers="HTTP/1.1 200 OK
Set-Cookie: session=abc123; Path=/; HttpOnly
Content-Type: application/json"

    burl_session_update_from_response "$headers"

    [[ "${_BURL_SESSION_COOKIES[session]}" == "abc123" ]]
}

@test "burl_session_update_from_response parses multiple Set-Cookie" {
    burl_session_init "$TEST_SESSION"
    local headers="HTTP/1.1 200 OK
Set-Cookie: session=abc
Set-Cookie: user=john
Content-Type: application/json"

    burl_session_update_from_response "$headers"

    [[ "${_BURL_SESSION_COOKIES[session]}" == "abc" ]]
    [[ "${_BURL_SESSION_COOKIES[user]}" == "john" ]]
}

@test "burl_session_update_from_response parses X-CSRF-Token" {
    burl_session_init "$TEST_SESSION"
    local headers="HTTP/1.1 200 OK
X-CSRF-Token: csrf_value_123
Content-Type: application/json"

    burl_session_update_from_response "$headers"

    [[ "$_BURL_SESSION_CSRF_TOKEN" == "csrf_value_123" ]]
    [[ "$_BURL_SESSION_CSRF_HEADER" == "X-CSRF-Token" ]]
}

@test "burl_session_update_from_response parses X-XSRF-Token" {
    burl_session_init "$TEST_SESSION"
    local headers="HTTP/1.1 200 OK
X-XSRF-Token: xsrf_value
Content-Type: application/json"

    burl_session_update_from_response "$headers"

    [[ "$_BURL_SESSION_CSRF_TOKEN" == "xsrf_value" ]]
    [[ "$_BURL_SESSION_CSRF_HEADER" == "X-XSRF-Token" ]]
}

@test "burl_session_update_from_response handles case-insensitive headers" {
    burl_session_init "$TEST_SESSION"
    local headers="HTTP/1.1 200 OK
SET-COOKIE: lower=case
x-csrf-token: lower_csrf"

    burl_session_update_from_response "$headers"

    [[ "${_BURL_SESSION_COOKIES[lower]}" == "case" ]]
    [[ "$_BURL_SESSION_CSRF_TOKEN" == "lower_csrf" ]]
}

@test "burl_session_update_from_response saves changes" {
    burl_session_init "$TEST_SESSION"
    local headers="Set-Cookie: persisted=yes"

    burl_session_update_from_response "$headers"

    local content
    content=$(<"$TEST_SESSION")
    [[ "$content" == *"persisted"* ]]
}

# =============================================================================
# SESSION VALIDITY TESTS
# =============================================================================

@test "burl_session_is_valid returns false when no session" {
    run burl_session_is_valid
    [[ "$status" -ne 0 ]]
}

@test "burl_session_is_valid returns true for valid session" {
    burl_session_init "$TEST_SESSION" --ttl 3600
    run burl_session_is_valid
    [[ "$status" -eq 0 ]]
}

@test "burl_session_is_valid returns true when TTL is 0 (no expiry)" {
    burl_session_init "$TEST_SESSION" --ttl 0
    run burl_session_is_valid
    [[ "$status" -eq 0 ]]
}

# =============================================================================
# SESSION CLEANUP TESTS
# =============================================================================

@test "burl_session_clear resets all data" {
    burl_session_init "$TEST_SESSION"
    _BURL_SESSION_COOKIES[a]="1"
    burl_session_set_auth --type bearer --token "tok"
    burl_session_set_csrf "csrf"

    burl_session_clear

    [[ ${#_BURL_SESSION_COOKIES[@]} -eq 0 ]]
    [[ -z "$_BURL_SESSION_AUTH_TOKEN" ]]
    [[ -z "$_BURL_SESSION_CSRF_TOKEN" ]]
}

@test "burl_session_clear preserves session file" {
    burl_session_init "$TEST_SESSION"
    burl_session_clear

    [[ -f "$TEST_SESSION" ]]
}

@test "burl_session_destroy removes session file" {
    burl_session_init "$TEST_SESSION"
    [[ -f "$TEST_SESSION" ]]

    burl_session_destroy

    [[ ! -f "$TEST_SESSION" ]]
}

@test "burl_session_destroy clears all state" {
    burl_session_init "$TEST_SESSION"
    _BURL_SESSION_COOKIES[a]="1"
    burl_session_set_auth --type bearer --token "tok"

    burl_session_destroy

    [[ -z "$_BURL_SESSION_PATH" ]]
    [[ ${#_BURL_SESSION_COOKIES[@]} -eq 0 ]]
    [[ -z "$_BURL_SESSION_AUTH_TOKEN" ]]
}

# =============================================================================
# VERSION/INFO TESTS
# =============================================================================

@test "burl_session_version outputs version info" {
    run burl_session_version
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"1.0.0"* ]]
    [[ "$output" == *"Session State Management"* ]]
}

# =============================================================================
# ATOMIC WRITE TESTS
# =============================================================================

@test "session write is atomic (temp file pattern)" {
    burl_session_init "$TEST_SESSION"

    # Verify no .tmp files left behind
    local tmp_files
    tmp_files=$(find "$TEST_SESSION_DIR" -name "*.tmp.*" 2>/dev/null | wc -l)
    [[ "$tmp_files" -eq 0 ]]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "handles cookie with equals sign in value" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_cookie "data=a=b=c; Path=/"

    [[ "${_BURL_SESSION_COOKIES[data]}" == "a=b=c" ]]
}

@test "handles empty cookie value" {
    burl_session_init "$TEST_SESSION"
    burl_session_set_cookie "empty=; Path=/"

    [[ "${_BURL_SESSION_COOKIES[empty]}" == "" ]]
}

@test "handles special characters in auth token" {
    burl_session_init "$TEST_SESSION"
    local special_token='eyJabc123xyz'
    burl_session_set_auth --type bearer --token "$special_token"
    burl_session_save

    # Token should be persisted
    local content
    content=$(<"$TEST_SESSION")
    [[ "$content" == *"$special_token"* ]]
}

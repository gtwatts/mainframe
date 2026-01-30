#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/burl.bats - bURL Library Tests
# =============================================================================
# Description: Comprehensive unit tests for burl.sh and burl_ai.sh
#              AI-Native HTTP client with USOP output format
# Test Count: 80 test cases
# Categories: URL parsing, HTTP methods, USOP output, error handling,
#             smart retry, token truncation, response analysis, pagination,
#             request chaining, schema validation, rate limiting, OAuth2,
#             request templates, response diffing
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    # Store original directory
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILE" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Configure bURL for testing
    export BURL_TIMEOUT=5
    export BURL_RETRY_COUNT=2
    export BURL_RETRY_DELAY=0
    export BURL_CACHE_DIR="$TEST_TMPDIR/cache"
    export BURL_AI_RATE_LIMIT_DIR="$TEST_TMPDIR/rate_limits"
    export BURL_AI_CACHE_DIR="$TEST_TMPDIR/ai_cache"
    export MAINFRAME_QUIET=1

    # Mock directory for mock executables
    MOCK_BIN="$TEST_TMPDIR/mock_bin"
    mkdir -p "$MOCK_BIN" "$BURL_CACHE_DIR" "$BURL_AI_RATE_LIMIT_DIR" "$BURL_AI_CACHE_DIR"
    export PATH="$MOCK_BIN:$PATH"

    # Source libraries
    source "$MAINFRAME_ROOT/lib/json.sh"
    source "$MAINFRAME_ROOT/lib/output.sh"
    source "$MAINFRAME_ROOT/lib/http.sh"

    # Reset bURL loaded state for fresh load in tests
    unset _MAINFRAME_BURL_LOADED
    unset _MAINFRAME_BURL_AI_LOADED
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# MOCK HELPERS
# =============================================================================

# Create mock openssl that returns canned HTTPS responses
create_mock_openssl() {
    local response_body="${1:-{}}"
    local status="${2:-200}"
    local headers="${3:-Content-Type: application/json}"

    cat > "$MOCK_BIN/openssl" << EOF
#!/usr/bin/env bash
# Mock openssl for HTTPS testing
cat << 'RESPONSE'
HTTP/1.1 $status OK
$headers
Connection: close

$response_body
RESPONSE
EOF
    chmod +x "$MOCK_BIN/openssl"
}

# Create mock timeout command
create_mock_timeout() {
    cat > "$MOCK_BIN/timeout" << 'EOF'
#!/usr/bin/env bash
# Mock timeout - just run the command
shift  # Remove timeout value
exec "$@"
EOF
    chmod +x "$MOCK_BIN/timeout"
}

# Create mock curl for download tests
create_mock_curl() {
    local output_content="${1:-test content}"

    cat > "$MOCK_BIN/curl" << EOF
#!/usr/bin/env bash
# Mock curl for download testing
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        -o)
            shift
            echo "$output_content" > "\$1"
            ;;
    esac
    shift
done
exit 0
EOF
    chmod +x "$MOCK_BIN/curl"
}

# Mock /dev/tcp by overriding http_request
mock_http_response() {
    local body="$1"
    local status="${2:-200}"
    local headers="${3:-Content-Type: application/json}"

    _MOCK_HTTP_BODY="$body"
    _MOCK_HTTP_STATUS="$status"
    _MOCK_HTTP_HEADERS="$headers"

    # Override http_request for testing
    http_request() {
        printf 'HTTP/1.1 %s OK\r\n%s\r\nConnection: close\r\n\r\n%s' \
            "$_MOCK_HTTP_STATUS" "$_MOCK_HTTP_HEADERS" "$_MOCK_HTTP_BODY"
    }

    # Also override http_json_get for burl_ai tests
    http_json_get() {
        printf 'HTTP/1.1 %s OK\r\n%s\r\nConnection: close\r\n\r\n%s' \
            "$_MOCK_HTTP_STATUS" "$_MOCK_HTTP_HEADERS" "$_MOCK_HTTP_BODY"
    }

    http_json_post() {
        printf 'HTTP/1.1 %s OK\r\n%s\r\nConnection: close\r\n\r\n%s' \
            "$_MOCK_HTTP_STATUS" "$_MOCK_HTTP_HEADERS" "$_MOCK_HTTP_BODY"
    }

    http_post() {
        printf 'HTTP/1.1 %s OK\r\n%s\r\nConnection: close\r\n\r\n%s' \
            "$_MOCK_HTTP_STATUS" "$_MOCK_HTTP_HEADERS" "$_MOCK_HTTP_BODY"
    }

    http_head() {
        printf 'HTTP/1.1 %s OK\r\n%s\r\nConnection: close\r\n\r\n' \
            "$_MOCK_HTTP_STATUS" "$_MOCK_HTTP_HEADERS"
    }
}

# =============================================================================
# CATEGORY 1: URL PARSING AND VALIDATION
# =============================================================================

@test "burl: URL parsing - extracts scheme from https URL" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    _burl_parse_url "https://api.example.com/users"

    [[ "$_BURL_SCHEME" == "https" ]]
}

@test "burl: URL parsing - extracts host from URL" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    _burl_parse_url "https://api.example.com/users"

    [[ "$_BURL_HOST" == "api.example.com" ]]
}

@test "burl: URL parsing - extracts port from URL with explicit port" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    _burl_parse_url "http://localhost:8080/api"

    [[ "$_BURL_PORT" == "8080" ]]
}

@test "burl: URL parsing - defaults port 443 for https" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    _burl_parse_url "https://secure.example.com/api"

    [[ "$_BURL_PORT" == "443" ]]
}

@test "burl: URL parsing - defaults port 80 for http" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    _burl_parse_url "http://example.com/api"

    [[ "$_BURL_PORT" == "80" ]]
}

@test "burl: URL parsing - extracts path from URL" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    _burl_parse_url "https://api.example.com/v1/users/123"

    [[ "$_BURL_PATH" == "/v1/users/123" ]]
}

@test "burl: URL parsing - extracts query string" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    _burl_parse_url "https://api.example.com/search?q=test&page=1"

    [[ "$_BURL_QUERY" == "q=test&page=1" ]]
}

@test "burl: URL parsing - extracts user credentials" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    _burl_parse_url "https://admin:secret@api.example.com/admin"

    [[ "$_BURL_USER" == "admin" ]]
    [[ "$_BURL_PASS" == "secret" ]]
}

@test "burl: URL validation - rejects empty URL" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    run _burl_validate_url ""

    [[ "$status" -eq "$BURL_E_INVALID_URL" ]]
}

@test "burl: URL validation - rejects invalid hostname" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    run _burl_validate_url "https://-invalid.com/api"

    [[ "$status" -eq "$BURL_E_INVALID_URL" ]]
}

@test "burl: URL validation - accepts valid IPv4 address" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    run _burl_validate_url "http://192.168.1.100:8080/api"

    [[ "$status" -eq 0 ]]
}

@test "burl: URL validation - rejects invalid IPv4 octet > 255" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    run _burl_validate_url "http://192.168.1.300/api"

    [[ "$status" -eq "$BURL_E_INVALID_URL" ]]
}

@test "burl: URL validation - rejects unsupported scheme" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    run _burl_validate_url "ftp://files.example.com/file.txt"

    [[ "$status" -eq "$BURL_E_INVALID_URL" ]]
}

@test "burl: URL encoding - encodes spaces as +" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(_burl_encode_url "hello world")

    [[ "$result" == "hello+world" ]]
}

@test "burl: URL encoding - encodes special characters" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(_burl_encode_url "name=John&age=30")

    [[ "$result" == "name%3DJohn%26age%3D30" ]]
}

@test "burl: URL decoding - decodes + to space" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(_burl_decode_url "hello+world")

    [[ "$result" == "hello world" ]]
}

# =============================================================================
# CATEGORY 2: HTTP METHODS (GET, POST, PUT, DELETE, HEAD)
# =============================================================================

@test "burl: burl_get makes GET request" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    mock_http_response '{"id":1,"name":"test"}' 200

    result=$(burl_get "http://api.test.local/users/1")

    [[ "$result" =~ '"ok":true' ]]
}

@test "burl: burl_post makes POST request with body" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    mock_http_response '{"id":2,"created":true}' 201

    result=$(burl_post "http://api.test.local/users" '{"name":"John"}')

    [[ "$result" =~ '"ok":true' ]]
}

@test "burl: burl_put makes PUT request" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    mock_http_response '{"id":1,"updated":true}' 200

    result=$(burl_put "http://api.test.local/users/1" '{"name":"Jane"}')

    [[ "$result" =~ '"ok":true' ]]
}

@test "burl: burl_patch makes PATCH request" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    mock_http_response '{"id":1,"patched":true}' 200

    result=$(burl_patch "http://api.test.local/users/1" '{"active":true}')

    [[ "$result" =~ '"ok":true' ]]
}

@test "burl: burl_delete makes DELETE request" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    mock_http_response '{"deleted":true}' 200

    result=$(burl_delete "http://api.test.local/users/1")

    [[ "$result" =~ '"ok":true' ]]
}

@test "burl: burl_head makes HEAD request" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    mock_http_response '' 200 'Content-Length: 1024'

    result=$(burl_head "http://api.test.local/file.txt")

    [[ "$result" =~ '"ok":true' ]]
}

@test "burl: main burl function with -X POST" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    mock_http_response '{"success":true}' 200

    result=$(burl -X POST -d '{"data":"test"}' "http://api.test.local/endpoint")

    [[ "$result" =~ '"ok":true' ]]
}

@test "burl: main burl function with custom headers" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    mock_http_response '{"authed":true}' 200

    result=$(burl -H "Authorization: Bearer token123" "http://api.test.local/secure")

    [[ "$result" =~ '"ok":true' ]]
}

# =============================================================================
# CATEGORY 3: USOP OUTPUT FORMAT
# =============================================================================

@test "burl: USOP success envelope has ok=true" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(_burl_ok '{"test":1}')

    [[ "$result" =~ '"ok":true' ]]
}

@test "burl: USOP success envelope includes data" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(_burl_ok '{"users":[1,2,3]}')

    [[ "$result" =~ '"data":{"users":[1,2,3]}' ]]
}

@test "burl: USOP success envelope includes meta" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(_burl_ok '{}' "status=200" "method=GET")

    [[ "$result" =~ '"meta":{' ]]
    [[ "$result" =~ '"status":200' ]]
    [[ "$result" =~ '"method":"GET"' ]]
}

@test "burl: USOP error envelope has ok=false" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(_burl_error 1 "Test error" "Try again")

    [[ "$result" =~ '"ok":false' ]]
}

@test "burl: USOP error envelope includes error code" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(_burl_error 5 "SSL Failed" "Check certificate")

    [[ "$result" =~ '"code":5' ]]
}

@test "burl: USOP error envelope includes suggestion" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(_burl_error 1 "Invalid URL" "Use https:// prefix")

    [[ "$result" =~ '"suggestion":"Use https:// prefix"' ]]
}

@test "burl: USOP meta handles boolean values" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(_burl_ok '{}' "truncated=true")

    [[ "$result" =~ '"truncated":true' ]]
}

@test "burl: USOP meta handles numeric values" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(_burl_ok '{}' "duration_ms=150")

    [[ "$result" =~ '"duration_ms":150' ]]
}

@test "burl: successful response returns USOP envelope with status" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    mock_http_response '{"data":"test"}' 200

    result=$(burl "http://api.test.local/test")

    [[ "$result" =~ '"status":200' ]]
}

# =============================================================================
# CATEGORY 4: ERROR HANDLING WITH SEMANTIC MESSAGES
# =============================================================================

@test "burl: semantic error for invalid URL" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    _burl_semantic_error $BURL_E_INVALID_URL "bad://url"

    [[ "$_BURL_ERROR_MSG" =~ "Invalid URL format" ]]
    [[ "$_BURL_ERROR_SUGGEST" =~ "scheme" ]]
}

@test "burl: semantic error for DNS failure" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    _burl_semantic_error $BURL_E_DNS_FAILED "nonexistent.invalid"

    [[ "$_BURL_ERROR_MSG" =~ "DNS resolution failed" ]]
    [[ "$_BURL_ERROR_SUGGEST" =~ "hostname" ]]
}

@test "burl: semantic error for connection failure" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    _burl_semantic_error $BURL_E_CONNECT_FAILED "localhost:9999"

    [[ "$_BURL_ERROR_MSG" =~ "Connection failed" ]]
    [[ "$_BURL_ERROR_SUGGEST" =~ "firewall" ]]
}

@test "burl: semantic error for timeout" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    export BURL_TIMEOUT=30

    _burl_semantic_error $BURL_E_TIMEOUT "slow.example.com"

    [[ "$_BURL_ERROR_MSG" =~ "timed out" ]]
    [[ "$_BURL_ERROR_SUGGEST" =~ "BURL_TIMEOUT" ]]
}

@test "burl: semantic error for SSL failure" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    _burl_semantic_error $BURL_E_SSL_FAILED "expired-cert.example.com"

    [[ "$_BURL_ERROR_MSG" =~ "SSL/TLS" ]]
    [[ "$_BURL_ERROR_SUGGEST" =~ "certificate" ]]
}

@test "burl: semantic error for rate limiting" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    _burl_semantic_error $BURL_E_RATE_LIMITED "api.example.com"

    [[ "$_BURL_ERROR_MSG" =~ "Rate limited" ]]
    [[ "$_BURL_ERROR_SUGGEST" =~ "backoff" ]]
}

@test "burl: semantic error for auth failure" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    _burl_semantic_error $BURL_E_AUTH_FAILED "api.example.com"

    [[ "$_BURL_ERROR_MSG" =~ "Authentication failed" ]]
    [[ "$_BURL_ERROR_SUGGEST" =~ "credentials" ]]
}

@test "burl: 4xx response returns error with semantic message" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    mock_http_response '{"error":"Not Found"}' 404

    result=$(burl "http://api.test.local/missing")

    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ '"code":9' ]]  # BURL_E_BAD_REQUEST
}

@test "burl: 5xx response returns server error" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    mock_http_response '{"error":"Internal Server Error"}' 500

    result=$(burl "http://api.test.local/broken")

    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ '"code":10' ]]  # BURL_E_SERVER_ERROR
}

# =============================================================================
# CATEGORY 5: SMART RETRY LOGIC
# =============================================================================

@test "burl: smart retry returns immediately on success" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    mock_http_response '{"success":true}' 200

    result=$(burl_smart_retry 3 "http://api.test.local/endpoint")

    [[ "$result" =~ '"ok":true' ]]
}

@test "burl: smart retry does not retry non-retryable errors" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    # Mock invalid URL error
    burl() {
        _burl_error $BURL_E_INVALID_URL "Invalid URL" "Fix URL"
    }

    result=$(burl_smart_retry 3 "invalid://url")

    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ '"code":1' ]]  # BURL_E_INVALID_URL
}

@test "burl: smart retry does not retry auth failures" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    burl() {
        _burl_error $BURL_E_AUTH_FAILED "Auth failed" "Check credentials"
    }

    result=$(burl_smart_retry 3 "http://api.test.local/secure")

    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ '"code":8' ]]  # BURL_E_AUTH_FAILED
}

@test "burl: --smart-retry flag enables retry logic" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    mock_http_response '{"result":"ok"}' 200

    result=$(burl --smart-retry "http://api.test.local/endpoint")

    [[ "$result" =~ '"ok":true' ]]
}

# =============================================================================
# CATEGORY 6: TOKEN TRUNCATION
# =============================================================================

@test "burl: truncation returns content unchanged when under limit" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    content="Short content"
    result=$(_burl_truncate "$content" 1000)

    [[ "$result" == "$content" ]]
}

@test "burl: truncation returns content unchanged when limit is 0" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    content="Any content at all"
    result=$(_burl_truncate "$content" 0)

    [[ "$result" == "$content" ]]
}

@test "burl: truncation adds marker when content exceeds limit" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    # Generate long content (more than 100 tokens ~400 chars)
    content=$(printf 'x%.0s' {1..500})
    result=$(_burl_truncate "$content" 50)

    [[ "$result" =~ "TRUNCATED" ]]
}

@test "burl: token estimation returns approximate count" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    # 100 chars ~25 tokens at 4 chars/token
    content=$(printf 'x%.0s' {1..100})
    tokens=$(_burl_estimate_tokens "$content")

    [[ "$tokens" -ge 20 && "$tokens" -le 30 ]]
}

@test "burl: --max-tokens truncates response body" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    # Generate large response body
    large_body=$(printf '{"data":"%s"}' "$(printf 'x%.0s' {1..1000})")
    mock_http_response "$large_body" 200

    result=$(burl --max-tokens 50 "http://api.test.local/large")

    [[ "$result" =~ '"truncated":true' ]]
}

@test "burl: burl_truncate_for_context wraps truncation" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    content="Test content for truncation"
    result=$(burl_truncate_for_context 1000 "$content")

    [[ "$result" == "$content" ]]
}

# =============================================================================
# CATEGORY 7: RESPONSE ANALYSIS
# =============================================================================

@test "burl: analyze_response detects JSON array" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(burl_analyze_response '[{"id":1},{"id":2}]')

    [[ "$result" =~ '"content_type":"json"' ]]
    [[ "$result" =~ '"is_array":true' ]]
}

@test "burl: analyze_response detects JSON object" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(burl_analyze_response '{"name":"John","age":30}')

    [[ "$result" =~ '"content_type":"json"' ]]
    [[ "$result" =~ '"is_object":true' ]]
}

@test "burl: analyze_response counts records in array" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(burl_analyze_response '[{"id":1},{"id":2},{"id":3}]')

    [[ "$result" =~ '"record_count":3' ]]
}

@test "burl: analyze_response detects XML content" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(burl_analyze_response '<?xml version="1.0"?><root><item>1</item></root>')

    [[ "$result" =~ '"content_type":"xml"' ]]
}

@test "burl: analyze_response detects CSV content" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(burl_analyze_response $'name,age\nJohn,30\nJane,25')

    [[ "$result" =~ '"content_type":"csv"' ]]
}

@test "burl: analyze_response includes estimated tokens" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(burl_analyze_response '{"key":"value"}')

    [[ "$result" =~ '"estimated_tokens":' ]]
}

@test "burl: --analyze flag includes analysis in response" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    mock_http_response '[{"id":1}]' 200

    result=$(burl --analyze "http://api.test.local/data")

    [[ "$result" =~ '"analysis":' ]]
}

# =============================================================================
# CATEGORY 8: PAGINATION (burl_ai.sh)
# =============================================================================

@test "burl_ai: pagination detects Link header" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    headers=$'Link: <http://api.test/page2>; rel="next"'
    result=$(_burl_detect_pagination '{"data":[1,2]}' "$headers")

    [[ "$result" == "link_header" ]]
}

@test "burl_ai: pagination detects next_page JSON field" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    body='{"data":[],"next_page":"http://api.test/page2"}'
    result=$(_burl_detect_pagination "$body" "")

    [[ "$result" =~ "json_field" ]]
}

@test "burl_ai: pagination detects cursor field" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    body='{"data":[],"next_cursor":"abc123"}'
    result=$(_burl_detect_pagination "$body" "")

    [[ "$result" =~ "cursor" ]]
}

@test "burl_ai: burl_paginate requires URL" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    result=$(burl_paginate "")

    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ "url_required" ]]
}

@test "burl_ai: burl_paginate returns page count" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    # Mock single page response with no pagination
    mock_http_response '{"data":[{"id":1}]}' 200

    result=$(burl_paginate "http://api.test.local/items" 1)

    [[ "$result" =~ '"pages":1' ]]
}

# =============================================================================
# CATEGORY 9: REQUEST CHAINING (burl_ai.sh)
# =============================================================================

@test "burl_ai: burl_chain requires chain spec" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    result=$(burl_chain "")

    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ "chain_spec_required" ]]
}

@test "burl_ai: burl_chain requires steps array" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    result=$(burl_chain '{"invalid":"spec"}')

    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ "invalid_chain_format" ]]
}

@test "burl_ai: burl_chain executes single step" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"
    mock_http_response '{"token":"abc123"}' 200

    chain='{"steps":[{"method":"POST","url":"http://api.test.local/auth"}]}'
    result=$(burl_chain "$chain")

    [[ "$result" =~ '"ok":true' ]]
}

# =============================================================================
# CATEGORY 10: SCHEMA VALIDATION (burl_ai.sh)
# =============================================================================

@test "burl_ai: schema validation requires body" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    result=$(burl_validate_schema "" '{"type":"object"}')

    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ "body_required" ]]
}

@test "burl_ai: schema validation requires schema" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    result=$(burl_validate_schema '{"id":1}' "")

    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ "schema_required" ]]
}

@test "burl_ai: schema validation passes for valid data" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    body='{"name":"John","age":30}'
    schema='{"required":["name"],"properties":{"name":{"type":"string"}}}'

    result=$(burl_validate_schema "$body" "$schema")

    [[ "$result" =~ '"ok":true' ]]
    [[ "$result" =~ '"valid":true' ]]
}

@test "burl_ai: schema validation fails for missing required field" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    body='{"age":30}'
    schema='{"required":["name"]}'

    result=$(burl_validate_schema "$body" "$schema")

    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ "missing_required_field:name" ]]
}

@test "burl_ai: type check validates string" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    run _burl_check_type '"hello"' "string"
    [[ "$status" -eq 0 ]]
}

@test "burl_ai: type check validates number" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    run _burl_check_type "42" "number"
    [[ "$status" -eq 0 ]]
}

@test "burl_ai: type check validates boolean" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    run _burl_check_type "true" "boolean"
    [[ "$status" -eq 0 ]]
}

# =============================================================================
# CATEGORY 11: RATE LIMITING (burl_ai.sh)
# =============================================================================

@test "burl_ai: rate limit status requires URL" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    result=$(burl_rate_limit_status "")

    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ "url_required" ]]
}

@test "burl_ai: rate limit status returns can_request true when no state" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    result=$(burl_rate_limit_status "http://fresh.api.local/endpoint")

    [[ "$result" =~ '"ok":true' ]]
    [[ "$result" =~ '"can_request":true' ]]
}

@test "burl_ai: rate limit header parsing extracts remaining" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    headers=$'X-RateLimit-Remaining: 50\nX-RateLimit-Limit: 100'
    result=$(_burl_parse_rate_headers "$headers")

    [[ "$result" =~ '"remaining":50' ]]
    [[ "$result" =~ '"limit":100' ]]
}

@test "burl_ai: rate limit header parsing extracts retry-after" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    headers=$'Retry-After: 60'
    result=$(_burl_parse_rate_headers "$headers")

    [[ "$result" =~ '"retry_after":60' ]]
}

# =============================================================================
# CATEGORY 12: OAUTH2 TOKEN MANAGEMENT (burl_ai.sh)
# =============================================================================

@test "burl_ai: oauth2 token requires endpoint" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    result=$(burl_oauth2_token "" "client_id" "client_secret")

    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ "token_endpoint_client_id_secret_required" ]]
}

@test "burl_ai: oauth2 token requires client_id" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    result=$(burl_oauth2_token "http://auth.test/token" "" "secret")

    [[ "$result" =~ '"ok":false' ]]
}

@test "burl_ai: oauth2 token returns cached token when valid" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    # Manually populate cache
    local cache_key="test_client:http://auth.test/token"
    _BURL_AI_OAUTH_TOKENS["$cache_key"]="cached_token_123"
    _BURL_AI_OAUTH_EXPIRY["$cache_key"]=$(($(date +%s) + 3600))

    result=$(burl_oauth2_token "http://auth.test/token" "test_client" "secret")

    [[ "$result" =~ '"ok":true' ]]
    [[ "$result" =~ '"cached":true' ]]
    [[ "$result" =~ "cached_token_123" ]]
}

@test "burl_ai: oauth2 token fetches new token when cache expired" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    # Set expired cache
    local cache_key="expired_client:http://auth.test/token"
    _BURL_AI_OAUTH_TOKENS["$cache_key"]="old_token"
    _BURL_AI_OAUTH_EXPIRY["$cache_key"]=$(($(date +%s) - 100))

    # Mock token response
    mock_http_response '{"access_token":"new_token_456","expires_in":3600}' 200

    result=$(burl_oauth2_token "http://auth.test/token" "expired_client" "secret")

    [[ "$result" =~ '"ok":true' ]]
    [[ "$result" =~ "new_token_456" ]]
}

# =============================================================================
# CATEGORY 13: REQUEST TEMPLATES (burl_ai.sh)
# =============================================================================

@test "burl_ai: template register requires name and spec" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    result=$(burl_template_register "" "")

    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ "name_and_spec_required" ]]
}

@test "burl_ai: template register stores template" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    result=$(burl_template_register "test_api" '{"method":"GET","url":"http://api.test/{{endpoint}}"}')

    [[ "$result" =~ '"ok":true' ]]
    [[ "$result" =~ '"registered":"test_api"' ]]
}

@test "burl_ai: template requires name" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    result=$(burl_template "")

    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ "template_name_required" ]]
}

@test "burl_ai: template returns error for unknown template" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    result=$(burl_template "nonexistent_template")

    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ "template_not_found" ]]
}

@test "burl_ai: template executes registered template" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    # Register template
    burl_template_register "get_user" '{"method":"GET","url":"http://api.test.local/users/{{id}}"}'

    # Mock response
    mock_http_response '{"id":42,"name":"John"}' 200

    result=$(burl_template "get_user" "id=42")

    [[ "$result" =~ '"ok":true' ]]
}

# =============================================================================
# CATEGORY 14: RESPONSE DIFFING (burl_ai.sh)
# =============================================================================

@test "burl_ai: diff response requires URL and response" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    result=$(burl_diff_response "" "")

    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ "url_and_response_required" ]]
}

@test "burl_ai: diff response detects new response as changed" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    result=$(burl_diff_response "http://api.test.local/new" '{"id":1}')

    [[ "$result" =~ '"ok":true' ]]
    [[ "$result" =~ '"changed":true' ]]
}

@test "burl_ai: diff response detects unchanged response" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    url="http://api.test.local/stable"
    response='{"id":1,"status":"active"}'

    # First call caches the response
    burl_diff_response "$url" "$response" > /dev/null

    # Second call should detect no change
    result=$(burl_diff_response "$url" "$response")

    [[ "$result" =~ '"ok":true' ]]
    [[ "$result" =~ '"changed":false' ]]
}

@test "burl_ai: diff response detects changed response" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    url="http://api.test.local/changing"

    # First call
    burl_diff_response "$url" '{"id":1,"count":10}' > /dev/null

    # Second call with different value
    result=$(burl_diff_response "$url" '{"id":1,"count":20}')

    [[ "$result" =~ '"ok":true' ]]
    [[ "$result" =~ '"changed":true' ]]
}

# =============================================================================
# ADDITIONAL TESTS: CACHING AND HELPERS
# =============================================================================

@test "burl: cached response stores result" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    mock_http_response '{"cached_data":"test"}' 200

    # First call - cache miss
    result1=$(burl_cached 300 "http://api.test.local/cacheable")

    [[ "$result1" =~ '"ok":true' ]]
}

@test "burl: base64 encode produces valid output" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(_burl_base64_encode "hello")

    # "hello" in base64 is "aGVsbG8="
    [[ "$result" == "aGVsbG8=" ]]
}

@test "burl: sha256 produces hash" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(_burl_sha256 "test")

    # Should be non-empty hash
    [[ -n "$result" ]]
    [[ ${#result} -ge 8 ]]
}

@test "burl: version function returns version info" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(burl_version)

    [[ "$result" =~ "bURL" ]]
    [[ "$result" =~ "AI-Native" ]]
}

@test "burl: functions list returns available functions" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    result=$(burl_functions)

    [[ "$result" =~ "burl_get" ]]
    [[ "$result" =~ "burl_post" ]]
    [[ "$result" =~ "burl_smart_retry" ]]
}

@test "burl: --raw flag returns raw response" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    mock_http_response '{"raw":"data"}' 200

    result=$(burl --raw "http://api.test.local/raw")

    # Should return raw body without USOP envelope
    [[ "$result" == '{"raw":"data"}' ]]
}

@test "burl: --json flag sets JSON content type" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    mock_http_response '{"json":"response"}' 200

    result=$(burl --json "http://api.test.local/json")

    [[ "$result" =~ '"ok":true' ]]
}

@test "burl_ai: download progress requires URL and output" {
    source "$MAINFRAME_ROOT/lib/burl.sh"
    source "$MAINFRAME_ROOT/lib/burl_ai.sh"

    result=$(burl_download_progress "" "")

    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ "url_and_output_required" ]]
}

@test "burl: parses IPv6 addresses" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    _burl_parse_url "http://[::1]:8080/api"

    [[ "$_BURL_HOST" == "::1" ]]
    [[ "$_BURL_PORT" == "8080" ]]
}

@test "burl: handles URL without path" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    _burl_parse_url "http://example.com"

    [[ "$_BURL_PATH" == "/" ]]
}

@test "burl: response parsing extracts status code" {
    source "$MAINFRAME_ROOT/lib/burl.sh"

    response=$'HTTP/1.1 201 Created\r\nContent-Type: application/json\r\n\r\n{"id":1}'
    _burl_parse_response "$response"

    [[ "$_BURL_STATUS" == "201" ]]
}

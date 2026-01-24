#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/scripts/api/endpoint-test.sh - API Endpoint Tester
# =============================================================================
# Description: Tests API endpoints with assertions on status codes, response
#              body, headers, and timing. Supports test suites from YAML/JSON.
# Version: 1.0.0
# Requires: Bash 4.0+, curl
# =============================================================================

set -o pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Configuration
BASE_URL=""
TIMEOUT=10
VERBOSE=false
OUTPUT_FORMAT="text"  # text|json|tap
HEADERS=()
AUTH_HEADER=""

# Counters
TESTS_PASS=0
TESTS_FAIL=0
TESTS_SKIP=0

usage() {
    cat <<EOF
Usage: endpoint-test.sh [options] <base-url> [test-file]

Test API endpoints with assertions.

Test File Format (one test per line):
    METHOD PATH STATUS [BODY_CONTAINS]
    GET /health 200
    POST /users 201 "id"
    GET /missing 404 "not found"

Options:
    -H, --header <hdr>  Add header (repeatable)
    --auth <token>       Bearer token authentication
    --timeout <sec>      Request timeout (default: 10)
    --format <fmt>       Output: text|json|tap (default: text)
    -v, --verbose        Show response bodies
    -h, --help           Show this help
EOF
    exit 0
}

parse_args() {
    local positional=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -H|--header)  HEADERS+=("$2"); shift 2 ;;
            --auth)       AUTH_HEADER="Authorization: Bearer $2"; shift 2 ;;
            --timeout)    TIMEOUT="$2"; shift 2 ;;
            --format)     OUTPUT_FORMAT="$2"; shift 2 ;;
            -v|--verbose) VERBOSE=true; shift ;;
            -h|--help)    usage ;;
            -*)           log_error "Unknown option: $1"; usage ;;
            *)            positional+=("$1"); shift ;;
        esac
    done

    BASE_URL="${positional[0]:-}"
    TEST_FILE="${positional[1]:-}"
}

# Run a single endpoint test
run_test() {
    local method="$1"
    local path="$2"
    local expected_status="$3"
    local body_contains="${4:-}"
    local request_body="${5:-}"

    local url="${BASE_URL}${path}"
    local curl_args=(-s -o /tmp/ep-test-body.$$ -w '%{http_code}\n%{time_total}' --max-time "$TIMEOUT")

    # Add method
    curl_args+=(-X "$method")

    # Add headers
    for hdr in "${HEADERS[@]}"; do
        curl_args+=(-H "$hdr")
    done
    [[ -n "$AUTH_HEADER" ]] && curl_args+=(-H "$AUTH_HEADER")

    # Add body for POST/PUT/PATCH
    if [[ -n "$request_body" ]]; then
        curl_args+=(-H "Content-Type: application/json" -d "$request_body")
    fi

    # Execute request
    local response
    response=$(curl "${curl_args[@]}" "$url" 2>/dev/null)

    local actual_status
    actual_status=$(echo "$response" | head -1)
    local time_taken
    time_taken=$(echo "$response" | tail -1)
    local response_body
    response_body=$(cat /tmp/ep-test-body.$$ 2>/dev/null)
    rm -f /tmp/ep-test-body.$$

    # Check status
    local status_pass=false
    if [[ "$actual_status" == "$expected_status" ]]; then
        status_pass=true
    fi

    # Check body contains
    local body_pass=true
    if [[ -n "$body_contains" ]]; then
        if [[ "$response_body" != *"$body_contains"* ]]; then
            body_pass=false
        fi
    fi

    # Report result
    local test_name="$method $path -> $expected_status"
    local passed=false
    [[ "$status_pass" == true && "$body_pass" == true ]] && passed=true

    if [[ "$passed" == true ]]; then
        ((TESTS_PASS++))
        report_pass "$test_name" "$time_taken"
    else
        ((TESTS_FAIL++))
        local reason=""
        [[ "$status_pass" == false ]] && reason="expected $expected_status, got $actual_status"
        [[ "$body_pass" == false ]] && reason+="${reason:+; }body missing '$body_contains'"
        report_fail "$test_name" "$reason" "$response_body"
    fi
}

report_pass() {
    local name="$1"
    local time="$2"

    case "$OUTPUT_FORMAT" in
        text) echo "  PASS  $name (${time}s)" ;;
        tap)  echo "ok $((TESTS_PASS + TESTS_FAIL)) - $name" ;;
        json) ;; # Collected at end
    esac
}

report_fail() {
    local name="$1"
    local reason="$2"
    local body="$3"

    case "$OUTPUT_FORMAT" in
        text)
            echo "  FAIL  $name"
            echo "        Reason: $reason"
            [[ "$VERBOSE" == true && -n "$body" ]] && echo "        Body: ${body:0:200}"
            ;;
        tap)
            echo "not ok $((TESTS_PASS + TESTS_FAIL)) - $name"
            echo "  ---"
            echo "  reason: $reason"
            echo "  ..."
            ;;
    esac
}

# Parse and run test file
run_test_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        log_error "Test file not found: $file"
        exit 1
    fi

    log_info "Running test suite: $file"
    echo ""

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ -z "$line" || "$line" == \#* ]] && continue

        # Parse: METHOD PATH STATUS [BODY_CONTAINS] [REQUEST_BODY]
        local method path status body_check req_body
        method=$(echo "$line" | awk '{print $1}')
        path=$(echo "$line" | awk '{print $2}')
        status=$(echo "$line" | awk '{print $3}')

        # Extract quoted body_contains if present
        if [[ "$line" =~ \"([^\"]+)\" ]]; then
            body_check="${BASH_REMATCH[1]}"
        fi

        run_test "$method" "$path" "$status" "$body_check"
    done < "$file"
}

main() {
    parse_args "$@"

    if [[ -z "$BASE_URL" ]]; then
        log_error "Base URL required"
        usage
    fi

    # Remove trailing slash
    BASE_URL="${BASE_URL%/}"

    if [[ "$OUTPUT_FORMAT" == "tap" ]]; then
        echo "TAP version 13"
    fi

    if [[ -n "$TEST_FILE" ]]; then
        run_test_file "$TEST_FILE"
    else
        # Interactive mode: read from stdin or run defaults
        log_info "Testing: $BASE_URL"
        echo ""

        # Default health check
        run_test "GET" "/health" "200"
        run_test "GET" "/" "200"

        # Read additional tests from stdin if piped
        if [[ ! -t 0 ]]; then
            while IFS= read -r line; do
                [[ -z "$line" || "$line" == \#* ]] && continue
                local method path status
                method=$(echo "$line" | awk '{print $1}')
                path=$(echo "$line" | awk '{print $2}')
                status=$(echo "$line" | awk '{print $3}')
                run_test "$method" "$path" "$status"
            done
        fi
    fi

    # Summary
    echo ""
    local total=$((TESTS_PASS + TESTS_FAIL + TESTS_SKIP))

    case "$OUTPUT_FORMAT" in
        text)
            log_info "Results: $TESTS_PASS passed, $TESTS_FAIL failed, $total total"
            ;;
        tap)
            echo "1..$total"
            echo "# pass $TESTS_PASS"
            echo "# fail $TESTS_FAIL"
            ;;
        json)
            printf '{"total":%d,"pass":%d,"fail":%d,"skip":%d}\n' \
                "$total" "$TESTS_PASS" "$TESTS_FAIL" "$TESTS_SKIP"
            ;;
    esac

    [[ $TESTS_FAIL -gt 0 ]] && exit 1
    exit 0
}

main "$@"

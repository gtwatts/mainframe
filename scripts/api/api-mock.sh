#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/scripts/api/api-mock.sh - Lightweight API Mock Server
# =============================================================================
# Description: Creates a mock HTTP API server using bash and netcat/socat.
#              Serves JSON responses from fixture files, supports route
#              matching, delays, and status code simulation.
# Version: 1.0.0
# Requires: Bash 4.0+, socat or nc (netcat)
# =============================================================================

set -o pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Configuration
PORT=8099
MOCK_DIR="./mocks"
DELAY_MS=0
VERBOSE=false
PID_FILE="/tmp/api-mock-$$.pid"

usage() {
    cat <<EOF
Usage: api-mock.sh [options]

Lightweight mock API server from JSON fixture files.

Mock Directory Structure:
    mocks/
      GET_users.json          -> GET /users
      POST_users.json         -> POST /users
      GET_users_:id.json      -> GET /users/:id
      _status_codes.json      -> Custom status codes per route

Options:
    -p, --port <port>    Listen port (default: 8099)
    -d, --dir <path>     Mock fixtures directory (default: ./mocks)
    --delay <ms>         Response delay in milliseconds
    -v, --verbose        Verbose request logging
    -h, --help           Show this help
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--port)    PORT="$2"; shift 2 ;;
            -d|--dir)     MOCK_DIR="$2"; shift 2 ;;
            --delay)      DELAY_MS="$2"; shift 2 ;;
            -v|--verbose) VERBOSE=true; shift ;;
            -h|--help)    usage ;;
            *)            log_error "Unknown option: $1"; usage ;;
        esac
    done
}

# Find the matching mock file for a request
find_mock() {
    local method="$1"
    local path="$2"

    # Normalize path: /users/123 -> users_123
    local normalized="${path#/}"
    normalized="${normalized//\//_}"

    # Try exact match first
    local exact="${MOCK_DIR}/${method}_${normalized}.json"
    if [[ -f "$exact" ]]; then
        echo "$exact"
        return 0
    fi

    # Try parameterized match: users_:id
    local parts
    IFS='_' read -ra parts <<< "$normalized"
    for i in "${!parts[@]}"; do
        # Try replacing each segment with :id
        local test_parts=("${parts[@]}")
        test_parts[i]=":id"
        local parameterized
        parameterized=$(IFS='_'; echo "${test_parts[*]}")
        local param_file="${MOCK_DIR}/${method}_${parameterized}.json"
        if [[ -f "$param_file" ]]; then
            echo "$param_file"
            return 0
        fi
    done

    # Try just the base path
    local base="${MOCK_DIR}/${method}_${parts[0]}.json"
    if [[ -f "$base" ]]; then
        echo "$base"
        return 0
    fi

    return 1
}

# Get status code for a route
get_status_code() {
    local method="$1"
    local path="$2"
    local status_file="${MOCK_DIR}/_status_codes.json"

    if [[ -f "$status_file" ]]; then
        local key="${method} ${path}"
        local code
        code=$(grep -oP "\"${key}\"\\s*:\\s*\\K[0-9]+" "$status_file" 2>/dev/null)
        if [[ -n "$code" ]]; then
            echo "$code"
            return
        fi
    fi

    echo "200"
}

# Get status text from code
status_text() {
    case "$1" in
        200) echo "OK" ;;
        201) echo "Created" ;;
        204) echo "No Content" ;;
        400) echo "Bad Request" ;;
        401) echo "Unauthorized" ;;
        403) echo "Forbidden" ;;
        404) echo "Not Found" ;;
        500) echo "Internal Server Error" ;;
        *)   echo "OK" ;;
    esac
}

# Handle a single HTTP request
handle_request() {
    local request_line=""
    local content_length=0

    # Read request line
    read -r request_line
    request_line="${request_line%%$'\r'}"

    # Parse method and path
    local method path
    method=$(echo "$request_line" | awk '{print $1}')
    path=$(echo "$request_line" | awk '{print $2}')

    # Read headers
    while IFS= read -r header; do
        header="${header%%$'\r'}"
        [[ -z "$header" ]] && break
        if [[ "${header,,}" == content-length:* ]]; then
            content_length="${header#*: }"
        fi
    done

    # Read body if present
    local body=""
    if [[ $content_length -gt 0 ]]; then
        body=$(head -c "$content_length")
    fi

    [[ "$VERBOSE" == true ]] && log_info "$method $path" >&2

    # Apply delay
    if [[ $DELAY_MS -gt 0 ]]; then
        sleep "$(echo "$DELAY_MS / 1000" | bc -l)"
    fi

    # Find mock response
    local mock_file
    mock_file=$(find_mock "$method" "$path")

    local status_code
    local response_body

    if [[ -n "$mock_file" ]]; then
        status_code=$(get_status_code "$method" "$path")
        response_body=$(cat "$mock_file")
    else
        status_code="404"
        response_body="{\"error\":\"No mock found for $method $path\"}"
    fi

    local status_msg
    status_msg=$(status_text "$status_code")
    local body_length=${#response_body}

    # Send HTTP response
    printf "HTTP/1.1 %s %s\r\n" "$status_code" "$status_msg"
    printf "Content-Type: application/json\r\n"
    printf "Content-Length: %d\r\n" "$body_length"
    printf "Access-Control-Allow-Origin: *\r\n"
    printf "Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r\n"
    printf "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"
    printf "Connection: close\r\n"
    printf "\r\n"
    printf "%s" "$response_body"
}

cleanup() {
    rm -f "$PID_FILE"
    log_info "Mock server stopped"
    exit 0
}

main() {
    parse_args "$@"

    if [[ ! -d "$MOCK_DIR" ]]; then
        log_error "Mock directory not found: $MOCK_DIR"
        log_info "Create it with JSON fixture files (e.g., GET_users.json)"
        exit 1
    fi

    # Check for socat or netcat
    local server_cmd=""
    if command -v socat >/dev/null 2>&1; then
        server_cmd="socat"
    elif command -v nc >/dev/null 2>&1; then
        server_cmd="nc"
    else
        log_error "Requires socat or netcat (nc)"
        exit 1
    fi

    # Count available mocks
    local mock_count
    mock_count=$(find "$MOCK_DIR" -name "*.json" ! -name "_*" | wc -l)

    log_info "Starting mock API server on port $PORT"
    log_info "Serving $mock_count mock(s) from $MOCK_DIR"
    [[ $DELAY_MS -gt 0 ]] && log_info "Response delay: ${DELAY_MS}ms"

    trap cleanup INT TERM
    echo $$ > "$PID_FILE"

    # Server loop
    if [[ "$server_cmd" == "socat" ]]; then
        socat TCP-LISTEN:"$PORT",reuseaddr,fork SYSTEM:"$(readlink -f "$0") --handle-request" &
        wait
    else
        while true; do
            handle_request | nc -l -p "$PORT" -q 1 2>/dev/null
        done
    fi
}

# Internal: handle a single request (called by socat fork)
if [[ "${1:-}" == "--handle-request" ]]; then
    source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
    MOCK_DIR="${MOCK_DIR:-./mocks}"
    handle_request
    exit 0
fi

main "$@"

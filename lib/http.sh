#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/http.sh - Pure Bash HTTP Client
# =============================================================================
# Description: HTTP client using /dev/tcp for pure bash network operations
# Limitations: HTTPS requires openssl (not pure bash). HTTP only by default.
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================
#
# Usage: source http.sh
#
# Examples:
#   # Simple GET request
#   response=$(http_get "http://example.com/api/users")
#
#   # POST JSON data
#   response=$(http_json_post "http://api.example.com/users" '{"name":"John"}')
#
#   # Parse response
#   status=$(http_status "$response")
#   body=$(http_body "$response")
#
#   # URL utilities
#   encoded=$(url_encode "hello world")
#   url_parse "http://example.com:8080/path?query=1"
#   echo "$URL_HOST"  # example.com
#
# Note: Pure bash HTTP only. HTTPS requires openssl and uses fallback mode.
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_HTTP_LOADED:-}" ]] && return 0
readonly _MAINFRAME_HTTP_LOADED=1

# =============================================================================
# CONSTANTS
# =============================================================================

readonly HTTP_VERSION="HTTP/1.1"
readonly HTTP_USER_AGENT="MAINFRAME-HTTP/1.0 (Pure Bash)"
readonly HTTP_DEFAULT_TIMEOUT=30
readonly HTTP_MAX_REDIRECTS=5

# Response storage (populated by http_request)
HTTP_RESPONSE_STATUS=""
HTTP_RESPONSE_HEADERS=""
HTTP_RESPONSE_BODY=""

# URL parts (populated by url_parse)
URL_SCHEME=""
URL_HOST=""
URL_PORT=""
URL_PATH=""
URL_QUERY=""
URL_USER=""
URL_PASS=""

# =============================================================================
# URL ENCODING
# =============================================================================

# URL encode a string
# Usage: url_encode "hello world"
# Note: If urlencode from pure-string.sh exists, this aliases to it
url_encode() {
    local LC_ALL=C
    local string="$1"
    local length=${#string}
    local encoded=""

    for ((i=0; i<length; i++)); do
        local c="${string:i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) encoded+="$c" ;;
            ' ') encoded+='+' ;;
            *) printf -v hex '%%%02X' "'$c"; encoded+="$hex" ;;
        esac
    done
    printf '%s' "$encoded"
}

# URL decode a string
# Usage: url_decode "hello%20world"
url_decode() {
    local encoded="$1"
    # Replace + with space
    encoded="${encoded//+/ }"
    # Decode %XX sequences
    printf '%b' "${encoded//%/\\x}"
}

# =============================================================================
# URL PARSING
# =============================================================================

# Parse URL into components
# Usage: url_parse "http://user:pass@host:port/path?query"
# Sets: URL_SCHEME, URL_HOST, URL_PORT, URL_PATH, URL_QUERY, URL_USER, URL_PASS
url_parse() {
    local url="$1"
    local rest

    # Reset globals
    URL_SCHEME=""
    URL_HOST=""
    URL_PORT=""
    URL_PATH=""
    URL_QUERY=""
    URL_USER=""
    URL_PASS=""

    # Extract scheme
    if [[ "$url" =~ ^([a-zA-Z][a-zA-Z0-9+.-]*):// ]]; then
        URL_SCHEME="${BASH_REMATCH[1]}"
        rest="${url#*://}"
    else
        # No scheme, assume http
        URL_SCHEME="http"
        rest="$url"
    fi

    # Extract query string
    if [[ "$rest" =~ \? ]]; then
        URL_QUERY="${rest#*\?}"
        rest="${rest%%\?*}"
    fi

    # Extract path
    if [[ "$rest" =~ / ]]; then
        URL_PATH="/${rest#*/}"
        rest="${rest%%/*}"
    else
        URL_PATH="/"
    fi

    # Extract user:pass
    if [[ "$rest" =~ @ ]]; then
        local userinfo="${rest%@*}"
        rest="${rest#*@}"
        if [[ "$userinfo" =~ : ]]; then
            URL_USER="${userinfo%%:*}"
            URL_PASS="${userinfo#*:}"
        else
            URL_USER="$userinfo"
        fi
    fi

    # Extract host:port
    if [[ "$rest" =~ : ]]; then
        URL_HOST="${rest%%:*}"
        URL_PORT="${rest#*:}"
    else
        URL_HOST="$rest"
        # Default ports
        case "$URL_SCHEME" in
            http)  URL_PORT=80 ;;
            https) URL_PORT=443 ;;
            *)     URL_PORT=80 ;;
        esac
    fi
}

# Build query string from key=value pairs
# Usage: query_string "name=John" "age=30"
query_string() {
    local result=""
    local first=true

    for pair in "$@"; do
        if [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            $first || result+="&"
            first=false
            result+="$(url_encode "$key")=$(url_encode "$value")"
        fi
    done
    printf '%s' "$result"
}

# =============================================================================
# HEADER UTILITIES
# =============================================================================

# Format a single HTTP header line
# Usage: http_header "Content-Type" "application/json"
http_header() {
    local name="$1"
    local value="$2"
    printf '%s: %s\r\n' "$name" "$value"
}

# Generate Basic authentication header value
# Usage: http_auth_basic "username" "password"
http_auth_basic() {
    local user="$1"
    local pass="$2"
    local credentials="${user}:${pass}"
    local encoded

    # Base64 encode (pure bash implementation)
    encoded=$(_base64_encode "$credentials")
    printf 'Basic %s' "$encoded"
}

# Generate Bearer authentication header value
# Usage: http_auth_bearer "token"
http_auth_bearer() {
    local token="$1"
    printf 'Bearer %s' "$token"
}

# Pure bash base64 encoding
# Usage: _base64_encode "string"
_base64_encode() {
    local input="$1"
    local chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local result=""
    local len=${#input}
    local i=0

    while ((i < len)); do
        local n=0
        local padding=0

        # Get up to 3 bytes
        for ((j=0; j<3; j++)); do
            if ((i + j < len)); then
                printf -v byte '%d' "'${input:i+j:1}"
                n=$((n << 8 | byte))
            else
                n=$((n << 8))
                ((padding++))
            fi
        done

        # Convert to 4 base64 characters
        for ((j=3; j>=0; j--)); do
            if ((j < padding)); then
                result+="="
            else
                local idx=$(( (n >> (j * 6)) & 63 ))
                result+="${chars:idx:1}"
            fi
        done

        ((i += 3))
    done

    printf '%s' "$result"
}

# =============================================================================
# CORE HTTP REQUEST (Pure Bash /dev/tcp)
# =============================================================================

# Low-level HTTP request builder and sender
# Usage: http_request "GET" "http://example.com/path" "" "Header: Value" ...
# Returns: Full HTTP response (headers + body)
http_request() {
    local method="${1:-GET}"
    local url="$2"
    local body="${3:-}"
    shift 3
    local extra_headers=("$@")

    # Parse URL
    url_parse "$url"

    local host="$URL_HOST"
    local port="$URL_PORT"
    local path="$URL_PATH"
    local scheme="$URL_SCHEME"

    # Add query string to path if present
    [[ -n "$URL_QUERY" ]] && path+="?$URL_QUERY"

    # HTTPS requires openssl fallback
    if [[ "$scheme" == "https" ]]; then
        _http_request_openssl "$method" "$host" "$port" "$path" "$body" "${extra_headers[@]}"
        return $?
    fi

    # Build request
    local request=""
    request+="${method} ${path} ${HTTP_VERSION}\r\n"
    request+="Host: ${host}\r\n"
    request+="User-Agent: ${HTTP_USER_AGENT}\r\n"
    request+="Connection: close\r\n"

    # Add content headers for body
    if [[ -n "$body" ]]; then
        request+="Content-Length: ${#body}\r\n"
    fi

    # Add extra headers
    for header in "${extra_headers[@]}"; do
        [[ -n "$header" ]] && request+="${header}\r\n"
    done

    # End headers
    request+="\r\n"

    # Add body
    [[ -n "$body" ]] && request+="${body}"

    # Send request via /dev/tcp
    local response=""
    local timeout="${HTTP_TIMEOUT:-$HTTP_DEFAULT_TIMEOUT}"

    {
        # Open connection
        exec 3<>"/dev/tcp/${host}/${port}" 2>/dev/null || {
            printf 'HTTP/1.1 000 Connection Failed\r\n\r\nFailed to connect to %s:%s' "$host" "$port"
            return 1
        }

        # Send request
        printf '%b' "$request" >&3

        # Read response with timeout
        local line
        while IFS= read -r -t "$timeout" line <&3; do
            response+="${line}"$'\n'
        done

        # Close connection
        exec 3>&-
    } 2>/dev/null

    # Store in globals for parsing
    _http_parse_response "$response"

    printf '%s' "$response"
}

# HTTPS request via openssl (fallback for TLS)
# Usage: _http_request_openssl "GET" "host" "port" "path" "body" "headers..."
_http_request_openssl() {
    local method="$1"
    local host="$2"
    local port="$3"
    local path="$4"
    local body="$5"
    shift 5
    local extra_headers=("$@")

    # Check for openssl
    if ! command -v openssl &>/dev/null; then
        printf 'HTTP/1.1 000 SSL Not Available\r\n\r\nopenssl required for HTTPS'
        return 1
    fi

    # Build request
    local request=""
    request+="${method} ${path} ${HTTP_VERSION}\r\n"
    request+="Host: ${host}\r\n"
    request+="User-Agent: ${HTTP_USER_AGENT}\r\n"
    request+="Connection: close\r\n"

    if [[ -n "$body" ]]; then
        request+="Content-Length: ${#body}\r\n"
    fi

    for header in "${extra_headers[@]}"; do
        [[ -n "$header" ]] && request+="${header}\r\n"
    done

    request+="\r\n"
    [[ -n "$body" ]] && request+="${body}"

    local response
    local timeout="${HTTP_TIMEOUT:-$HTTP_DEFAULT_TIMEOUT}"

    response=$(printf '%b' "$request" | \
        timeout "$timeout" openssl s_client -quiet -connect "${host}:${port}" 2>/dev/null)

    _http_parse_response "$response"
    printf '%s' "$response"
}

# Parse HTTP response into components
# Usage: _http_parse_response "$response"
# Sets: HTTP_RESPONSE_STATUS, HTTP_RESPONSE_HEADERS, HTTP_RESPONSE_BODY
_http_parse_response() {
    local response="$1"
    local in_headers=true
    local headers=""
    local body=""
    local status_line=""

    HTTP_RESPONSE_STATUS=""
    HTTP_RESPONSE_HEADERS=""
    HTTP_RESPONSE_BODY=""

    while IFS= read -r line; do
        # Remove carriage return
        line="${line%$'\r'}"

        if $in_headers; then
            if [[ -z "$status_line" ]]; then
                status_line="$line"
                # Extract status code
                if [[ "$line" =~ ^HTTP/[0-9.]+[[:space:]]+([0-9]+) ]]; then
                    HTTP_RESPONSE_STATUS="${BASH_REMATCH[1]}"
                fi
            elif [[ -z "$line" ]]; then
                in_headers=false
            else
                headers+="${line}"$'\n'
            fi
        else
            body+="${line}"$'\n'
        fi
    done <<< "$response"

    HTTP_RESPONSE_HEADERS="$headers"
    # Remove trailing newline from body
    HTTP_RESPONSE_BODY="${body%$'\n'}"
}

# =============================================================================
# HTTP METHODS
# =============================================================================

# GET request
# Usage: http_get "http://example.com/api"
# Example: response=$(http_get "http://httpbin.org/get")
http_get() {
    local url="$1"
    shift
    _http_with_redirects "GET" "$url" "" "$@"
}

# POST request with data
# Usage: http_post "http://example.com/api" "data"
# Example: response=$(http_post "http://httpbin.org/post" "name=John&age=30")
http_post() {
    local url="$1"
    local data="${2:-}"
    shift 2 2>/dev/null || shift
    _http_with_redirects "POST" "$url" "$data" "Content-Type: application/x-www-form-urlencoded" "$@"
}

# PUT request with data
# Usage: http_put "http://example.com/api/1" "data"
http_put() {
    local url="$1"
    local data="${2:-}"
    shift 2 2>/dev/null || shift
    _http_with_redirects "PUT" "$url" "$data" "Content-Type: application/x-www-form-urlencoded" "$@"
}

# DELETE request
# Usage: http_delete "http://example.com/api/1"
http_delete() {
    local url="$1"
    shift
    _http_with_redirects "DELETE" "$url" "" "$@"
}

# HEAD request (returns headers only)
# Usage: http_head "http://example.com"
http_head() {
    local url="$1"
    shift
    http_request "HEAD" "$url" "" "$@"
}

# PATCH request with data
# Usage: http_patch "http://example.com/api/1" "data"
http_patch() {
    local url="$1"
    local data="${2:-}"
    shift 2 2>/dev/null || shift
    _http_with_redirects "PATCH" "$url" "$data" "Content-Type: application/x-www-form-urlencoded" "$@"
}

# =============================================================================
# REDIRECT HANDLING
# =============================================================================

# HTTP request with automatic redirect following
# Usage: _http_with_redirects "GET" "url" "body" "headers..."
_http_with_redirects() {
    local method="$1"
    local url="$2"
    local body="$3"
    shift 3
    local headers=("$@")

    local redirects=0
    local response
    local location

    while ((redirects < HTTP_MAX_REDIRECTS)); do
        response=$(http_request "$method" "$url" "$body" "${headers[@]}")

        # Check for redirect status
        case "$HTTP_RESPONSE_STATUS" in
            301|302|303|307|308)
                # Get Location header
                location=$(http_header_get "$response" "Location")
                if [[ -z "$location" ]]; then
                    # No location header, return response as-is
                    printf '%s' "$response"
                    return 0
                fi

                # Handle relative URLs
                if [[ ! "$location" =~ ^https?:// ]]; then
                    url_parse "$url"
                    if [[ "$location" =~ ^/ ]]; then
                        location="${URL_SCHEME}://${URL_HOST}:${URL_PORT}${location}"
                    else
                        location="${URL_SCHEME}://${URL_HOST}:${URL_PORT}${URL_PATH%/*}/${location}"
                    fi
                fi

                url="$location"
                ((redirects++))

                # 303 converts to GET
                [[ "$HTTP_RESPONSE_STATUS" == "303" ]] && method="GET" && body=""
                ;;
            *)
                # Not a redirect, return response
                printf '%s' "$response"
                return 0
                ;;
        esac
    done

    # Max redirects exceeded
    printf 'HTTP/1.1 000 Too Many Redirects\r\n\r\nExceeded maximum redirects (%d)' "$HTTP_MAX_REDIRECTS"
    return 1
}

# =============================================================================
# RESPONSE PARSING
# =============================================================================

# Extract HTTP status code from response
# Usage: http_status "$response"
# Example: status=$(http_status "$response"); [[ $status == 200 ]] && echo "OK"
http_status() {
    local response="$1"

    # If response not provided, use cached value
    if [[ -z "$response" ]]; then
        printf '%s' "$HTTP_RESPONSE_STATUS"
        return
    fi

    # Extract from first line
    local first_line
    first_line=$(head -n1 <<< "$response")
    if [[ "$first_line" =~ ^HTTP/[0-9.]+[[:space:]]+([0-9]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        printf '0'
    fi
}

# Extract body from HTTP response
# Usage: http_body "$response"
http_body() {
    local response="$1"

    # If response not provided, use cached value
    if [[ -z "$response" ]]; then
        printf '%s' "$HTTP_RESPONSE_BODY"
        return
    fi

    local in_body=false
    local body=""
    local prev_empty=false

    while IFS= read -r line; do
        line="${line%$'\r'}"
        if $in_body; then
            body+="${line}"$'\n'
        elif [[ -z "$line" ]]; then
            in_body=true
        fi
    done <<< "$response"

    # Remove trailing newline
    printf '%s' "${body%$'\n'}"
}

# Get specific header value from response
# Usage: http_header_get "$response" "Content-Type"
http_header_get() {
    local response="$1"
    local header_name="$2"
    local header_name_lower="${header_name,,}"

    local in_headers=true
    while IFS= read -r line; do
        line="${line%$'\r'}"

        # Empty line ends headers
        [[ -z "$line" ]] && break

        # Skip status line
        [[ "$line" =~ ^HTTP/ ]] && continue

        # Check for matching header (case-insensitive)
        if [[ "${line,,}" =~ ^${header_name_lower}: ]]; then
            # Extract value after colon, trim leading space
            local value="${line#*:}"
            value="${value# }"
            printf '%s' "$value"
            return 0
        fi
    done <<< "$response"

    return 1
}

# Get all headers as newline-separated list
# Usage: http_headers "$response"
http_headers() {
    local response="$1"

    local in_headers=true
    while IFS= read -r line; do
        line="${line%$'\r'}"
        [[ -z "$line" ]] && break
        [[ "$line" =~ ^HTTP/ ]] && continue
        printf '%s\n' "$line"
    done <<< "$response"
}

# =============================================================================
# JSON CONVENIENCE FUNCTIONS
# =============================================================================

# GET request expecting JSON response
# Usage: http_json_get "http://api.example.com/users"
http_json_get() {
    local url="$1"
    shift
    http_get "$url" "Accept: application/json" "$@"
}

# POST JSON data with appropriate Content-Type
# Usage: http_json_post "http://api.example.com/users" '{"name":"John"}'
http_json_post() {
    local url="$1"
    local json_data="$2"
    shift 2 2>/dev/null || shift

    http_request "POST" "$url" "$json_data" \
        "Content-Type: application/json" \
        "Accept: application/json" \
        "$@"
}

# PUT JSON data
# Usage: http_json_put "http://api.example.com/users/1" '{"name":"Jane"}'
http_json_put() {
    local url="$1"
    local json_data="$2"
    shift 2 2>/dev/null || shift

    http_request "PUT" "$url" "$json_data" \
        "Content-Type: application/json" \
        "Accept: application/json" \
        "$@"
}

# PATCH JSON data
# Usage: http_json_patch "http://api.example.com/users/1" '{"name":"Jane"}'
http_json_patch() {
    local url="$1"
    local json_data="$2"
    shift 2 2>/dev/null || shift

    http_request "PATCH" "$url" "$json_data" \
        "Content-Type: application/json" \
        "Accept: application/json" \
        "$@"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Check if HTTP status indicates success (2xx)
# Usage: http_is_success "$response" && echo "OK"
http_is_success() {
    local response="$1"
    local status
    status=$(http_status "$response")
    [[ "$status" =~ ^2[0-9][0-9]$ ]]
}

# Check if HTTP status indicates redirect (3xx)
# Usage: http_is_redirect "$response"
http_is_redirect() {
    local response="$1"
    local status
    status=$(http_status "$response")
    [[ "$status" =~ ^3[0-9][0-9]$ ]]
}

# Check if HTTP status indicates client error (4xx)
# Usage: http_is_client_error "$response"
http_is_client_error() {
    local response="$1"
    local status
    status=$(http_status "$response")
    [[ "$status" =~ ^4[0-9][0-9]$ ]]
}

# Check if HTTP status indicates server error (5xx)
# Usage: http_is_server_error "$response"
http_is_server_error() {
    local response="$1"
    local status
    status=$(http_status "$response")
    [[ "$status" =~ ^5[0-9][0-9]$ ]]
}

# Set timeout for HTTP requests
# Usage: http_set_timeout 60
http_set_timeout() {
    HTTP_TIMEOUT="$1"
}

# =============================================================================
# DOWNLOAD FUNCTION
# =============================================================================

# Download URL to file
# Usage: http_download "http://example.com/file.txt" "/path/to/save"
http_download() {
    local url="$1"
    local output="$2"

    local response
    response=$(http_get "$url")

    if http_is_success "$response"; then
        http_body "$response" > "$output"
        return 0
    else
        return 1
    fi
}

# =============================================================================
# COOKIE HANDLING (Basic)
# =============================================================================

# Parse Set-Cookie header into name=value
# Usage: http_parse_cookie "Set-Cookie: name=value; Path=/"
http_parse_cookie() {
    local header="$1"
    # Extract just the name=value part (before first semicolon)
    local cookie="${header#*:}"
    cookie="${cookie# }"
    cookie="${cookie%%;*}"
    printf '%s' "$cookie"
}

# Format cookie header for request
# Usage: http_cookie "name=value"
http_cookie() {
    printf 'Cookie: %s' "$1"
}

# =============================================================================
# DEBUG FUNCTIONS
# =============================================================================

# Print full request details (for debugging)
# Usage: http_debug_request "GET" "http://example.com"
http_debug_request() {
    local method="$1"
    local url="$2"

    url_parse "$url"

    printf 'Method:  %s\n' "$method"
    printf 'URL:     %s\n' "$url"
    printf 'Scheme:  %s\n' "$URL_SCHEME"
    printf 'Host:    %s\n' "$URL_HOST"
    printf 'Port:    %s\n' "$URL_PORT"
    printf 'Path:    %s\n' "$URL_PATH"
    printf 'Query:   %s\n' "$URL_QUERY"
}

# Print response details (for debugging)
# Usage: http_debug_response "$response"
http_debug_response() {
    local response="$1"

    printf 'Status:  %s\n' "$(http_status "$response")"
    printf 'Headers:\n'
    http_headers "$response" | while read -r line; do
        printf '  %s\n' "$line"
    done
    printf 'Body length: %d bytes\n' "${#HTTP_RESPONSE_BODY}"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

HTTP_EXPORTS=(
    # Core
    http_request
    http_get http_post http_put http_delete http_head http_patch
    # Headers
    http_header http_auth_basic http_auth_bearer
    # URL
    url_parse url_encode url_decode query_string
    # Response parsing
    http_status http_body http_header_get http_headers
    # JSON convenience
    http_json_get http_json_post http_json_put http_json_patch
    # Utilities
    http_is_success http_is_redirect http_is_client_error http_is_server_error
    http_set_timeout http_download
    # Cookies
    http_parse_cookie http_cookie
    # Debug
    http_debug_request http_debug_response
)

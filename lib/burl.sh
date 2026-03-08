#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/burl.sh - AI-Native HTTP Client
# =============================================================================
# Description: HTTP client optimized for AI agent consumption with USOP output,
#              semantic errors, context-budget awareness, and smart retry logic.
# Version: 1.0.0
# Requires: Bash 4.0+, openssl (for HTTPS)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================
#
# bURL provides curl-compatible flags with AI-native extensions:
#   - USOP JSON envelope output: {"ok":true,"data":{...},"meta":{...}}
#   - Semantic error messages with actionable suggestions
#   - Token-budget aware response truncation
#   - Smart retry with rate-limit awareness
#   - Response analysis for API understanding
#
# Usage:
#   burl [options] URL
#   burl_get "https://api.example.com/users"
#   burl_post "https://api.example.com/users" '{"name":"John"}'
#
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_BURL_LOADED:-}" ]] && return 0
_MAINFRAME_BURL_LOADED=1

# =============================================================================
# AUTO-SOURCE DEPENDENCIES
# =============================================================================

_BURL_LIB_DIR="${BASH_SOURCE[0]%/*}"

# Source jsonpath.sh for query support
if ! declare -F jsonpath_query &>/dev/null; then
    if [[ -f "${_BURL_LIB_DIR}/jsonpath.sh" ]]; then
        source "${_BURL_LIB_DIR}/jsonpath.sh"
    fi
fi

# Source burl_session.sh for session support
if ! declare -F burl_session_init &>/dev/null; then
    if [[ -f "${_BURL_LIB_DIR}/burl_session.sh" ]]; then
        source "${_BURL_LIB_DIR}/burl_session.sh"
    fi
fi

# =============================================================================
# ERROR CODES
# =============================================================================

readonly BURL_OK=0
readonly BURL_E_INVALID_URL=1
readonly BURL_E_DNS_FAILED=2
readonly BURL_E_CONNECT_FAILED=3
readonly BURL_E_TIMEOUT=4
readonly BURL_E_SSL_FAILED=5
readonly BURL_E_REDIRECT_LOOP=6
readonly BURL_E_RATE_LIMITED=7
readonly BURL_E_AUTH_FAILED=8
readonly BURL_E_BAD_REQUEST=9
readonly BURL_E_SERVER_ERROR=10
readonly BURL_E_PARSE_ERROR=11
readonly BURL_E_QUERY_ERROR=12
readonly BURL_E_SESSION_ERROR=13

# =============================================================================
# CONFIGURATION
# =============================================================================

BURL_TIMEOUT="${BURL_TIMEOUT:-30}"
BURL_MAX_REDIRECTS="${BURL_MAX_REDIRECTS:-10}"
BURL_MAX_TOKENS="${BURL_MAX_TOKENS:-0}"  # 0 = no limit
BURL_RETRY_COUNT="${BURL_RETRY_COUNT:-3}"
BURL_RETRY_DELAY="${BURL_RETRY_DELAY:-1}"
BURL_USER_AGENT="bURL/1.0 (MAINFRAME; AI-Native)"
BURL_VERBOSE="${BURL_VERBOSE:-0}"

# Cache configuration
BURL_CACHE_DIR="${BURL_CACHE_DIR:-${MAINFRAME_CACHE_ROOT:-$HOME/.mainframe/cache}/burl}"
BURL_CACHE_DEFAULT_TTL="${BURL_CACHE_DEFAULT_TTL:-300}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Response storage
_BURL_STATUS=""
_BURL_HEADERS=""
_BURL_BODY=""
_BURL_COOKIES=""

# Parsed URL components
_BURL_SCHEME=""
_BURL_HOST=""
_BURL_PORT=""
_BURL_PATH=""
_BURL_QUERY=""
_BURL_USER=""
_BURL_PASS=""

# =============================================================================
# USOP OUTPUT HELPERS
# =============================================================================

# Generate USOP success response
# @param $1 - data (JSON or string)
# @param $@ - meta key=value pairs
# @return USOP envelope with ok:true
_burl_ok() {
    local data="$1"
    shift

    local meta_json="{"
    local first=true

    # Build meta object
    for pair in "$@"; do
        if [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            $first || meta_json+=","
            first=false

            # Auto-detect type
            if [[ "$value" =~ ^-?[0-9]+$ ]]; then
                meta_json+="\"${key}\":${value}"
            elif [[ "$value" == "true" || "$value" == "false" ]]; then
                meta_json+="\"${key}\":${value}"
            else
                # Escape string value
                value="${value//\\/\\\\}"
                value="${value//\"/\\\"}"
                value="${value//$'\n'/\\n}"
                value="${value//$'\r'/\\r}"
                value="${value//$'\t'/\\t}"
                meta_json+="\"${key}\":\"${value}\""
            fi
        fi
    done
    meta_json+="}"

    # Detect if data is already JSON
    local data_json
    if [[ "$data" =~ ^\{.*\}$ ]] || [[ "$data" =~ ^\[.*\]$ ]]; then
        data_json="$data"
    elif [[ "$data" == "null" ]]; then
        data_json="null"
    else
        # Escape as string
        data="${data//\\/\\\\}"
        data="${data//\"/\\\"}"
        data="${data//$'\n'/\\n}"
        data="${data//$'\r'/\\r}"
        data="${data//$'\t'/\\t}"
        data_json="\"${data}\""
    fi

    printf '{"ok":true,"data":%s,"meta":%s}' "$data_json" "$meta_json"
}

# Generate USOP error response with suggestion
# @param $1 - error code
# @param $2 - error message
# @param $3 - suggestion (optional)
# @param $@ - meta key=value pairs
# @return USOP envelope with ok:false
_burl_error() {
    local code="$1"
    local message="$2"
    local suggestion="${3:-}"
    shift 3 2>/dev/null || shift $#

    # Escape strings
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    message="${message//$'\n'/\\n}"
    suggestion="${suggestion//\\/\\\\}"
    suggestion="${suggestion//\"/\\\"}"
    suggestion="${suggestion//$'\n'/\\n}"

    local meta_json="{"
    local first=true

    for pair in "$@"; do
        if [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            $first || meta_json+=","
            first=false

            if [[ "$value" =~ ^-?[0-9]+$ ]]; then
                meta_json+="\"${key}\":${value}"
            elif [[ "$value" == "true" || "$value" == "false" ]]; then
                meta_json+="\"${key}\":${value}"
            else
                value="${value//\\/\\\\}"
                value="${value//\"/\\\"}"
                meta_json+="\"${key}\":\"${value}\""
            fi
        fi
    done
    meta_json+="}"

    local error_json
    if [[ -n "$suggestion" ]]; then
        error_json="{\"code\":${code},\"message\":\"${message}\",\"suggestion\":\"${suggestion}\"}"
    else
        error_json="{\"code\":${code},\"message\":\"${message}\"}"
    fi

    printf '{"ok":false,"error":%s,"meta":%s}' "$error_json" "$meta_json"
}

# Map error code to semantic message and suggestion
# @param $1 - error code
# @param $2 - additional context
# @return Sets _BURL_ERROR_MSG and _BURL_ERROR_SUGGEST
_burl_semantic_error() {
    local code="$1"
    local context="${2:-}"

    case "$code" in
        "$BURL_E_INVALID_URL")
            _BURL_ERROR_MSG="Invalid URL format: $context"
            _BURL_ERROR_SUGGEST="Verify URL includes scheme (http:// or https://) and valid hostname"
            ;;
        "$BURL_E_DNS_FAILED")
            _BURL_ERROR_MSG="DNS resolution failed for: $context"
            _BURL_ERROR_SUGGEST="Check hostname spelling, verify network connectivity, try using IP address"
            ;;
        "$BURL_E_CONNECT_FAILED")
            _BURL_ERROR_MSG="Connection failed to: $context"
            _BURL_ERROR_SUGGEST="Verify server is running and accessible, check firewall rules, try alternate port"
            ;;
        "$BURL_E_TIMEOUT")
            _BURL_ERROR_MSG="Request timed out after ${BURL_TIMEOUT}s: $context"
            _BURL_ERROR_SUGGEST="Increase BURL_TIMEOUT, check server responsiveness, verify network latency"
            ;;
        "$BURL_E_SSL_FAILED")
            _BURL_ERROR_MSG="SSL/TLS handshake failed: $context"
            _BURL_ERROR_SUGGEST="Check certificate validity, try -k flag to skip verification (not recommended for production)"
            ;;
        "$BURL_E_REDIRECT_LOOP")
            _BURL_ERROR_MSG="Redirect loop detected after ${BURL_MAX_REDIRECTS} redirects: $context"
            _BURL_ERROR_SUGGEST="Check for redirect configuration issues, verify URL is not self-referencing"
            ;;
        "$BURL_E_RATE_LIMITED")
            _BURL_ERROR_MSG="Rate limited by server: $context"
            _BURL_ERROR_SUGGEST="Wait before retrying, use --smart-retry for automatic backoff, reduce request frequency"
            ;;
        "$BURL_E_AUTH_FAILED")
            _BURL_ERROR_MSG="Authentication failed: $context"
            _BURL_ERROR_SUGGEST="Verify credentials, check auth header format, ensure token is not expired"
            ;;
        "$BURL_E_BAD_REQUEST")
            _BURL_ERROR_MSG="Bad request (4xx): $context"
            _BURL_ERROR_SUGGEST="Check request syntax, verify required parameters, examine response body for details"
            ;;
        "$BURL_E_SERVER_ERROR")
            _BURL_ERROR_MSG="Server error (5xx): $context"
            _BURL_ERROR_SUGGEST="Retry with --smart-retry, server may be temporarily unavailable"
            ;;
        *)
            _BURL_ERROR_MSG="Unknown error: $context"
            _BURL_ERROR_SUGGEST="Check request parameters and try again"
            ;;
    esac
}

# =============================================================================
# TOKEN/CONTEXT BUDGET HELPERS
# =============================================================================

# Truncate content to fit token budget
# @param $1 - content string
# @param $2 - max tokens (0 = no limit)
# @return Truncated content with indicator if truncated
_burl_truncate() {
    local content="$1"
    local max_tokens="${2:-0}"

    if [[ "$max_tokens" -eq 0 ]]; then
        printf '%s' "$content"
        return 0
    fi

    # Use context library if available
    if declare -F context_truncate &>/dev/null; then
        context_truncate "$content" "$max_tokens" --strategy smart
        return $?
    fi

    # Fallback: estimate ~4 chars per token
    local max_chars=$(( max_tokens * 4 ))
    local content_len=${#content}

    if [[ "$content_len" -le "$max_chars" ]]; then
        printf '%s' "$content"
        return 0
    fi

    # Keep first portion with truncation marker
    local keep_chars=$(( max_chars - 100 ))  # Reserve for marker
    local truncated="${content:0:$keep_chars}"
    local remaining_tokens=$(( (content_len - keep_chars) / 4 ))

    printf '%s\n\n... [TRUNCATED: ~%d tokens remaining, use --max-tokens to adjust] ...' \
        "$truncated" "$remaining_tokens"
}

# Estimate token count for string
# @param $1 - string
# @return Estimated token count
_burl_estimate_tokens() {
    local content="$1"

    # Use context library if available
    if declare -F context_estimate_tokens &>/dev/null; then
        context_estimate_tokens "$content"
        return $?
    fi

    # Fallback: ~4 chars per token
    local char_count=${#content}
    echo $(( (char_count + 3) / 4 ))
}

# =============================================================================
# URL PARSING AND VALIDATION
# =============================================================================

# Parse URL into components
# @param $1 - URL string
# @pre URL must be non-empty
# @post Sets _BURL_SCHEME, _BURL_HOST, _BURL_PORT, _BURL_PATH, _BURL_QUERY, _BURL_USER, _BURL_PASS
# @return 0 on success, 1 on failure
_burl_parse_url() {
    local url="$1"
    local rest

    # Reset globals
    _BURL_SCHEME=""
    _BURL_HOST=""
    _BURL_PORT=""
    _BURL_PATH=""
    _BURL_QUERY=""
    _BURL_USER=""
    _BURL_PASS=""

    [[ -z "$url" ]] && return 1

    # Extract scheme
    if [[ "$url" =~ ^([a-zA-Z][a-zA-Z0-9+.-]*):// ]]; then
        _BURL_SCHEME="${BASH_REMATCH[1]}"
        rest="${url#*://}"
    else
        # No scheme, try to infer
        if [[ "$url" =~ ^localhost ]]; then
            _BURL_SCHEME="http"
        else
            _BURL_SCHEME="https"  # Default to HTTPS for AI agents
        fi
        rest="$url"
    fi

    # Extract fragment (discard for HTTP requests)
    rest="${rest%%#*}"

    # Extract query string
    if [[ "$rest" =~ \? ]]; then
        _BURL_QUERY="${rest#*\?}"
        rest="${rest%%\?*}"
    fi

    # Extract path
    if [[ "$rest" =~ / ]]; then
        _BURL_PATH="/${rest#*/}"
        rest="${rest%%/*}"
    else
        _BURL_PATH="/"
    fi

    # Extract user:pass
    if [[ "$rest" =~ @ ]]; then
        local userinfo="${rest%@*}"
        rest="${rest#*@}"
        if [[ "$userinfo" =~ : ]]; then
            _BURL_USER="${userinfo%%:*}"
            _BURL_PASS="${userinfo#*:}"
        else
            _BURL_USER="$userinfo"
        fi
    fi

    # Handle IPv6 addresses
    if [[ "$rest" =~ ^\[([^\]]+)\](:([0-9]+))?$ ]]; then
        _BURL_HOST="${BASH_REMATCH[1]}"
        _BURL_PORT="${BASH_REMATCH[3]:-}"
    # Extract host:port
    elif [[ "$rest" =~ : ]]; then
        _BURL_HOST="${rest%%:*}"
        _BURL_PORT="${rest#*:}"
    else
        _BURL_HOST="$rest"
    fi

    # Default ports
    if [[ -z "$_BURL_PORT" ]]; then
        case "$_BURL_SCHEME" in
            http)  _BURL_PORT=80 ;;
            https) _BURL_PORT=443 ;;
            *)     _BURL_PORT=80 ;;
        esac
    fi

    return 0
}

# Validate URL for security
# @param $1 - URL string
# @pre URL has been parsed into _BURL_* components
# @return 0 if valid, error code if invalid
_burl_validate_url() {
    local url="$1"

    # Parse first
    _burl_parse_url "$url" || return "$BURL_E_INVALID_URL"

    # Empty host check
    if [[ -z "$_BURL_HOST" ]]; then
        return "$BURL_E_INVALID_URL"
    fi

    # Scheme validation
    case "$_BURL_SCHEME" in
        http|https) ;;
        *)
            return "$BURL_E_INVALID_URL"
            ;;
    esac

    # Host validation (RFC 1123 + IPv4/IPv6)
    local host="$_BURL_HOST"

    # IPv4 check
    if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        local IFS='.'
        local octets
        read -ra octets <<< "$host"
        for octet in "${octets[@]}"; do
            if ! [[ "$octet" =~ ^[0-9]+$ ]] || (( octet > 255 )); then
                return "$BURL_E_INVALID_URL"
            fi
        done
    # IPv6 check (basic)
    elif [[ "$host" =~ ^[0-9a-fA-F:]+$ ]]; then
        : # Allow basic IPv6
    # Hostname check
    else
        # Max length
        [[ ${#host} -gt 253 ]] && return "$BURL_E_INVALID_URL"

        # Label validation
        local IFS='.'
        local labels
        read -ra labels <<< "$host"
        local label_re='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'

        for label in "${labels[@]}"; do
            [[ -z "$label" ]] && return "$BURL_E_INVALID_URL"
            [[ ${#label} -gt 63 ]] && return "$BURL_E_INVALID_URL"
            [[ ! "$label" =~ $label_re ]] && return "$BURL_E_INVALID_URL"
        done
    fi

    # Port validation
    if [[ -n "$_BURL_PORT" ]]; then
        if ! [[ "$_BURL_PORT" =~ ^[0-9]+$ ]] || (( _BURL_PORT > 65535 )); then
            return "$BURL_E_INVALID_URL"
        fi
    fi

    # Block private IPs for security (optional, configurable)
    if [[ "${BURL_BLOCK_PRIVATE:-0}" == "1" ]]; then
        case "$host" in
            127.*|10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|localhost)
                return "$BURL_E_INVALID_URL"
                ;;
        esac
    fi

    return 0
}

# =============================================================================
# URL ENCODING/DECODING
# =============================================================================

# URL encode a string
# @param $1 - string to encode
# @return URL-encoded string
_burl_encode_url() {
    local LC_ALL=C
    local string="$1"
    local length=${#string}
    local encoded=""
    local i c

    for ((i=0; i<length; i++)); do
        c="${string:i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) encoded+="$c" ;;
            ' ') encoded+='+' ;;
            *) printf -v hex '%%%02X' "'$c"; encoded+="$hex" ;;
        esac
    done
    printf '%s' "$encoded"
}

# URL decode a string
# @param $1 - encoded string
# @return Decoded string
_burl_decode_url() {
    local encoded="$1"
    # Replace + with space
    encoded="${encoded//+/ }"
    # Decode %XX sequences
    printf '%b' "${encoded//%/\\x}"
}

# =============================================================================
# CONNECTION FUNCTIONS
# =============================================================================

# Connect via /dev/tcp (HTTP only)
# @param $1 - host
# @param $2 - port
# @param $3 - request string
# @param $4 - timeout
# @return Response string or error
_burl_connect_tcp() {
    local host="$1"
    local port="$2"
    local request="$3"
    local timeout="${4:-$BURL_TIMEOUT}"
    local response=""

    # Use timeout command if available
    if command -v timeout &>/dev/null; then
        response=$(
            exec 3<>"/dev/tcp/${host}/${port}" 2>/dev/null || exit 1
            printf '%b' "$request" >&3
            timeout "$timeout" cat <&3
            exec 3>&-
        ) 2>/dev/null
    else
        # Fallback with bash read timeout
        {
            exec 3<>"/dev/tcp/${host}/${port}" 2>/dev/null || {
                return "$BURL_E_CONNECT_FAILED"
            }

            printf '%b' "$request" >&3

            local line
            while IFS= read -r -t "$timeout" line <&3; do
                response+="${line}"$'\n'
            done

            exec 3>&-
        } 2>/dev/null
    fi

    if [[ -z "$response" ]]; then
        return "$BURL_E_CONNECT_FAILED"
    fi

    printf '%s' "$response"
}

# Connect via openssl (HTTPS)
# @param $1 - host
# @param $2 - port
# @param $3 - request string
# @param $4 - timeout
# @param $5 - skip verify (0/1)
# @return Response string or error
_burl_connect_tls() {
    local host="$1"
    local port="$2"
    local request="$3"
    local timeout="${4:-$BURL_TIMEOUT}"
    local skip_verify="${5:-0}"

    # Check for openssl
    if ! command -v openssl &>/dev/null; then
        return "$BURL_E_SSL_FAILED"
    fi

    local ssl_opts="-connect ${host}:${port} -servername ${host} -quiet"

    if [[ "$skip_verify" == "1" ]]; then
        ssl_opts+=" -verify_quiet"
    fi

    local response
    # shellcheck disable=SC2086  # Intentional word splitting for openssl options
    if command -v timeout &>/dev/null; then
        response=$(printf '%b' "$request" | timeout "$timeout" openssl s_client $ssl_opts 2>/dev/null)
    else
        response=$(printf '%b' "$request" | openssl s_client $ssl_opts 2>/dev/null)
    fi

    local exit_code=$?

    if [[ $exit_code -ne 0 ]] && [[ -z "$response" ]]; then
        return "$BURL_E_SSL_FAILED"
    fi

    printf '%s' "$response"
}

# Execute with timeout wrapper
# @param $1 - timeout seconds
# @param $@ - command to execute
# @return Command output or timeout error
_burl_with_timeout() {
    local timeout="$1"
    shift

    if command -v timeout &>/dev/null; then
        timeout "$timeout" "$@"
    else
        # Bash-only timeout using background process
        local output
        output=$("$@") &
        local pid=$!

        local elapsed=0
        while kill -0 "$pid" 2>/dev/null; do
            sleep 0.1
            elapsed=$(echo "$elapsed + 0.1" | bc)
            if (( $(echo "$elapsed > $timeout" | bc -l) )); then
                kill -9 "$pid" 2>/dev/null
                wait "$pid" 2>/dev/null
                return "$BURL_E_TIMEOUT"
            fi
        done

        wait "$pid"
        printf '%s' "$output"
    fi
}

# =============================================================================
# REQUEST BUILDING
# =============================================================================

# Build HTTP request string
# @param $1 - method
# @param $2 - path (with query)
# @param $3 - host
# @param $4 - body (optional)
# @param $@ - additional headers
# @return HTTP request string
_burl_build_request() {
    local method="$1"
    local path="$2"
    local host="$3"
    local body="${4:-}"
    shift 4 2>/dev/null || shift $#
    local extra_headers=("$@")

    local request=""
    request+="${method} ${path} HTTP/1.1\r\n"
    request+="Host: ${host}\r\n"
    request+="User-Agent: ${BURL_USER_AGENT}\r\n"
    request+="Connection: close\r\n"
    request+="Accept: */*\r\n"

    # Content headers for body
    if [[ -n "$body" ]]; then
        request+="Content-Length: ${#body}\r\n"
    fi

    # Extra headers
    for header in "${extra_headers[@]}"; do
        [[ -n "$header" ]] && request+="${header}\r\n"
    done

    # End headers
    request+="\r\n"

    # Body
    [[ -n "$body" ]] && request+="${body}"

    printf '%s' "$request"
}

# =============================================================================
# RESPONSE PARSING
# =============================================================================

# Parse HTTP response into components
# @param $1 - raw response
# @post Sets _BURL_STATUS, _BURL_HEADERS, _BURL_BODY
# @return 0 on success
_burl_parse_response() {
    local response="$1"

    _BURL_STATUS=""
    _BURL_HEADERS=""
    _BURL_BODY=""

    [[ -z "$response" ]] && return 1

    # Split headers and body (separated by blank line)
    local header_section=""
    local body_section=""
    local in_body=false
    local blank_line_found=false

    while IFS= read -r line; do
        # Remove carriage return
        line="${line%$'\r'}"

        if $blank_line_found; then
            if [[ -n "$body_section" ]]; then
                body_section+=$'\n'
            fi
            body_section+="$line"
        elif [[ -z "$line" ]]; then
            blank_line_found=true
        else
            if [[ -n "$header_section" ]]; then
                header_section+=$'\n'
            fi
            header_section+="$line"
        fi
    done <<< "$response"

    _BURL_HEADERS="$header_section"
    _BURL_BODY="$body_section"

    # Extract status code from first line
    if [[ "$header_section" =~ ^HTTP/[0-9.]+\ ([0-9]+) ]]; then
        _BURL_STATUS="${BASH_REMATCH[1]}"
    fi

    return 0
}

# Extract header value
# @param $1 - header name (case-insensitive)
# @param $2 - headers string (optional, uses _BURL_HEADERS)
# @return Header value or empty
_burl_get_header() {
    local name="$1"
    local headers="${2:-$_BURL_HEADERS}"
    local name_lower="${name,,}"

    while IFS= read -r line; do
        line="${line%$'\r'}"
        if [[ "${line,,}" =~ ^${name_lower}:\ *(.*)$ ]]; then
            printf '%s' "${BASH_REMATCH[1]}"
            return 0
        fi
    done <<< "$headers"

    return 1
}

# Parse headers into associative array format
# @param $1 - headers string
# @return JSON object of headers
_burl_parse_headers() {
    local headers="$1"
    local json="{"
    local first=true

    while IFS= read -r line; do
        line="${line%$'\r'}"
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^HTTP/ ]] && continue

        if [[ "$line" =~ ^([^:]+):\ *(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Escape value
            value="${value//\\/\\\\}"
            value="${value//\"/\\\"}"

            $first || json+=","
            first=false
            json+="\"${key}\":\"${value}\""
        fi
    done <<< "$headers"

    json+="}"
    printf '%s' "$json"
}

# Decode chunked transfer encoding
# @param $1 - body string
# @return Decoded body
_burl_decode_chunked() {
    local body="$1"
    local decoded=""
    local remaining="$body"

    while [[ -n "$remaining" ]]; do
        # Read chunk size (hex)
        local chunk_line="${remaining%%$'\n'*}"
        remaining="${remaining#*$'\n'}"
        chunk_line="${chunk_line%$'\r'}"

        # Convert hex to decimal
        local chunk_size
        chunk_size=$((16#${chunk_line%%[^0-9a-fA-F]*})) 2>/dev/null || chunk_size=0

        if [[ "$chunk_size" -eq 0 ]]; then
            break
        fi

        # Read chunk data
        decoded+="${remaining:0:$chunk_size}"
        remaining="${remaining:$((chunk_size + 2))}"  # Skip data + \r\n
    done

    printf '%s' "$decoded"
}

# Extract cookies from response
# @param $1 - headers string
# @return JSON array of cookies
_burl_extract_cookies() {
    local headers="$1"
    local cookies="["
    local first=true

    while IFS= read -r line; do
        line="${line%$'\r'}"
        if [[ "${line,,}" =~ ^set-cookie:\ *(.*)$ ]]; then
            local cookie="${BASH_REMATCH[1]}"
            cookie="${cookie//\"/\\\"}"

            $first || cookies+=","
            first=false
            cookies+="\"${cookie}\""
        fi
    done <<< "$headers"

    cookies+="]"
    printf '%s' "$cookies"
}

# =============================================================================
# CORE PUBLIC FUNCTIONS
# =============================================================================

# Main bURL function - curl-compatible interface with AI-native extras
# @param $@ - options and URL
# @pre Valid URL provided
# @post Response available in _BURL_* globals
# @return USOP JSON envelope
#
# Options:
#   -X METHOD       HTTP method (GET, POST, PUT, DELETE, etc.)
#   -H "Header: V"  Custom header (repeatable)
#   -d "data"       Request body
#   -o file         Output to file
#   -L              Follow redirects
#   -s              Silent mode (no progress)
#   -v              Verbose (debug output)
#   -k              Skip SSL certificate verification
#   -u user:pass    Basic authentication
#   --json          Shortcut for JSON content-type
#   --max-tokens N  Truncate response for AI context budget
#   --smart-retry   Rate-limit aware retry with exponential backoff
#   --analyze       Include response analysis in output
#   --raw           Return raw response (no USOP envelope)
burl() {
    local method="GET"
    local url=""
    local body=""
    local output_file=""
    local follow_redirects=false
    local silent=false
    local verbose=false
    local skip_ssl=false
    local auth=""
    local json_mode=false
    local max_tokens=0
    local smart_retry=false
    local analyze=false
    local raw_output=false
    local headers=()
    local -a query_paths=()
    local allow_missing=false
    local session_file=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -X|--request)
                method="${2^^}"
                shift 2
                ;;
            -H|--header)
                headers+=("$2")
                shift 2
                ;;
            -d|--data)
                body="$2"
                [[ "$method" == "GET" ]] && method="POST"
                shift 2
                ;;
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            -L|--location)
                follow_redirects=true
                shift
                ;;
            -s|--silent)
                silent=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -k|--insecure)
                skip_ssl=true
                shift
                ;;
            -u|--user)
                auth="$2"
                shift 2
                ;;
            --json)
                json_mode=true
                shift
                ;;
            --max-tokens)
                max_tokens="$2"
                shift 2
                ;;
            --smart-retry)
                smart_retry=true
                shift
                ;;
            --analyze)
                analyze=true
                shift
                ;;
            --raw)
                raw_output=true
                shift
                ;;
            -q|--query)
                query_paths+=("$2")
                shift 2
                ;;
            --allow-missing)
                allow_missing=true
                shift
                ;;
            --session)
                session_file="$2"
                shift 2
                ;;
            -*)
                # Unknown option - ignore for curl compatibility
                shift
                ;;
            *)
                url="$1"
                shift
                ;;
        esac
    done

    # Validate URL
    local validate_result
    _burl_validate_url "$url"
    validate_result=$?

    if [[ $validate_result -ne 0 ]]; then
        _burl_semantic_error $validate_result "$url"
        _burl_error $validate_result "$_BURL_ERROR_MSG" "$_BURL_ERROR_SUGGEST" "url=$url"
        return $validate_result
    fi

    # Add JSON headers if --json
    if $json_mode; then
        headers+=("Content-Type: application/json")
        headers+=("Accept: application/json")
    fi

    # Add auth header if -u
    if [[ -n "$auth" ]]; then
        local encoded_auth
        encoded_auth=$(_burl_base64_encode "$auth")
        headers+=("Authorization: Basic ${encoded_auth}")
    fi

    # Add URL auth if present
    if [[ -n "$_BURL_USER" ]]; then
        local user_auth="${_BURL_USER}"
        [[ -n "$_BURL_PASS" ]] && user_auth+=":${_BURL_PASS}"
        local encoded_auth
        encoded_auth=$(_burl_base64_encode "$user_auth")
        headers+=("Authorization: Basic ${encoded_auth}")
    fi

    # Add session headers if --session
    if [[ -n "$session_file" ]] && declare -F burl_session_init &>/dev/null; then
        # Initialize or load session
        burl_session_init "$session_file" 2>/dev/null || true

        # Add cookie header (use || true to handle empty session case under set -e)
        local cookie_header
        cookie_header=$(burl_session_cookie_header 2>/dev/null) || true
        [[ -n "$cookie_header" ]] && headers+=("$cookie_header")

        # Add auth header (if not already set via -u)
        if [[ -z "$auth" ]]; then
            local auth_header
            auth_header=$(burl_session_auth_header 2>/dev/null) || true
            [[ -n "$auth_header" ]] && headers+=("$auth_header")
        fi

        # Add CSRF header
        local csrf_header
        csrf_header=$(burl_session_csrf_header 2>/dev/null) || true
        [[ -n "$csrf_header" ]] && headers+=("$csrf_header")
    fi

    # Build path with query
    local full_path="$_BURL_PATH"
    [[ -n "$_BURL_QUERY" ]] && full_path+="?${_BURL_QUERY}"

    # Build request
    local request
    request=$(_burl_build_request "$method" "$full_path" "$_BURL_HOST" "$body" "${headers[@]}")

    # Verbose output
    if $verbose; then
        printf '> %s %s HTTP/1.1\n' "$method" "$full_path" >&2
        printf '> Host: %s\n' "$_BURL_HOST" >&2
        for h in "${headers[@]}"; do
            printf '> %s\n' "$h" >&2
        done
        printf '>\n' >&2
    fi

    # Execute request with retry logic
    local response=""
    local retries=0
    local max_retries="$BURL_RETRY_COUNT"
    $smart_retry || max_retries=1

    local start_time
    start_time=$(date +%s%N 2>/dev/null || date +%s)

    while [[ $retries -lt $max_retries ]]; do
        local connect_result=0

        # Connect based on scheme
        if [[ "$_BURL_SCHEME" == "https" ]]; then
            local skip_verify=0
            $skip_ssl && skip_verify=1
            response=$(_burl_connect_tls "$_BURL_HOST" "$_BURL_PORT" "$request" "$BURL_TIMEOUT" "$skip_verify")
            connect_result=$?
        else
            response=$(_burl_connect_tcp "$_BURL_HOST" "$_BURL_PORT" "$request" "$BURL_TIMEOUT")
            connect_result=$?
        fi

        if [[ $connect_result -eq 0 ]] && [[ -n "$response" ]]; then
            break
        fi

        ((retries++)) || true

        if $smart_retry && [[ $retries -lt $max_retries ]]; then
            local delay=$(( BURL_RETRY_DELAY * (2 ** (retries - 1)) ))
            sleep "$delay"
        fi
    done

    local end_time
    end_time=$(date +%s%N 2>/dev/null || date +%s)
    local duration_ms
    if [[ "$start_time" =~ ^[0-9]+$ ]] && [[ ${#start_time} -gt 10 ]]; then
        duration_ms=$(( (end_time - start_time) / 1000000 ))
    else
        duration_ms=$(( (end_time - start_time) * 1000 ))
    fi

    # Check for connection failure
    if [[ -z "$response" ]]; then
        _burl_semantic_error "$BURL_E_CONNECT_FAILED" "${_BURL_HOST}:${_BURL_PORT}"
        _burl_error "$BURL_E_CONNECT_FAILED" "$_BURL_ERROR_MSG" "$_BURL_ERROR_SUGGEST" \
            "url=$url" "retries=$retries" "duration_ms=$duration_ms"
        return "$BURL_E_CONNECT_FAILED"
    fi

    # Parse response
    _burl_parse_response "$response"

    # Handle redirects
    local redirect_count=0
    while $follow_redirects && [[ "$_BURL_STATUS" =~ ^30[1-8]$ ]]; do
        ((redirect_count++)) || true

        if [[ $redirect_count -gt "$BURL_MAX_REDIRECTS" ]]; then
            _burl_semantic_error "$BURL_E_REDIRECT_LOOP" "$url"
            _burl_error "$BURL_E_REDIRECT_LOOP" "$_BURL_ERROR_MSG" "$_BURL_ERROR_SUGGEST" \
                "url=$url" "redirects=$redirect_count"
            return "$BURL_E_REDIRECT_LOOP"
        fi

        local location
        location=$(_burl_get_header "Location") || true

        if [[ -z "$location" ]]; then
            break
        fi

        # Handle relative redirects
        if [[ ! "$location" =~ ^https?:// ]]; then
            if [[ "$location" =~ ^/ ]]; then
                location="${_BURL_SCHEME}://${_BURL_HOST}:${_BURL_PORT}${location}"
            else
                location="${_BURL_SCHEME}://${_BURL_HOST}:${_BURL_PORT}${_BURL_PATH%/*}/${location}"
            fi
        fi

        # Recursive call for redirect - pass along query and session flags
        local redirect_args=(-X GET)
        $skip_ssl && redirect_args+=(-k)
        $verbose && redirect_args+=(-v)
        $analyze && redirect_args+=(--analyze)
        [[ "$max_tokens" -gt 0 ]] && redirect_args+=(--max-tokens "$max_tokens")
        [[ -n "$session_file" ]] && redirect_args+=(--session "$session_file")
        $allow_missing && redirect_args+=(--allow-missing)
        for qp in "${query_paths[@]}"; do
            redirect_args+=(-q "$qp")
        done
        # shellcheck disable=SC2086  # Intentional word splitting for optional flags
        burl "${redirect_args[@]}" "$location"
        return $?
    done

    # Handle chunked encoding
    local transfer_encoding
    transfer_encoding=$(_burl_get_header "Transfer-Encoding") || true
    if [[ "${transfer_encoding,,}" == "chunked" ]]; then
        _BURL_BODY=$(_burl_decode_chunked "$_BURL_BODY")
    fi

    # Update session from response headers if --session
    if [[ -n "$session_file" ]] && declare -F burl_session_update_from_response &>/dev/null; then
        burl_session_update_from_response "$_BURL_HEADERS" 2>/dev/null
    fi

    # Check for rate limiting
    if [[ "$_BURL_STATUS" == "429" ]]; then
        local retry_after
        retry_after=$(_burl_get_header "Retry-After") || true
        _burl_semantic_error "$BURL_E_RATE_LIMITED" "$url"
        _burl_error "$BURL_E_RATE_LIMITED" "$_BURL_ERROR_MSG" "$_BURL_ERROR_SUGGEST" \
            "url=$url" "status=$_BURL_STATUS" "retry_after=${retry_after:-unknown}"
        return "$BURL_E_RATE_LIMITED"
    fi

    # Check for auth failure
    if [[ "$_BURL_STATUS" == "401" ]] || [[ "$_BURL_STATUS" == "403" ]]; then
        _burl_semantic_error "$BURL_E_AUTH_FAILED" "$url"
        _burl_error "$BURL_E_AUTH_FAILED" "$_BURL_ERROR_MSG" "$_BURL_ERROR_SUGGEST" \
            "url=$url" "status=$_BURL_STATUS"
        return "$BURL_E_AUTH_FAILED"
    fi

    # Truncate body if max-tokens set
    local final_body="$_BURL_BODY"
    local was_truncated=false
    if [[ "$max_tokens" -gt 0 ]]; then
        local estimated_tokens
        estimated_tokens=$(_burl_estimate_tokens "$final_body")
        if [[ "$estimated_tokens" -gt "$max_tokens" ]]; then
            final_body=$(_burl_truncate "$final_body" "$max_tokens")
            was_truncated=true
        fi
    fi

    # Output to file if requested
    if [[ -n "$output_file" ]]; then
        printf '%s' "$final_body" > "$output_file"
    fi

    # Raw output mode
    if $raw_output; then
        printf '%s' "$final_body"
        return 0
    fi

    # JSONPath query extraction (-q/--query)
    if [[ ${#query_paths[@]} -gt 0 ]] && declare -F jsonpath_query &>/dev/null; then
        local query_result=""

        if [[ ${#query_paths[@]} -eq 1 ]]; then
            # Single query - return raw value
            local path="${query_paths[0]}"
            query_result=$(jsonpath_query "$final_body" "$path" 2>/dev/null)
            local query_rc=$?

            if [[ $query_rc -ne 0 ]]; then
                if $allow_missing; then
                    printf 'null'
                    return 0
                else
                    _burl_error "$BURL_E_QUERY_ERROR" "Path not found: $path" \
                        "Verify the JSONPath exists in the response, or use --allow-missing" \
                        "path=$path"
                    return "$BURL_E_QUERY_ERROR"
                fi
            fi

            printf '%s' "$query_result"
            return 0
        else
            # Multiple queries - return JSON object
            local first=true
            query_result="{"

            for path in "${query_paths[@]}"; do
                local value
                value=$(jsonpath_query "$final_body" "$path" 2>/dev/null)
                local query_rc=$?

                $first || query_result+=","
                first=false

                if [[ $query_rc -ne 0 ]]; then
                    if $allow_missing; then
                        query_result+="\"${path}\":null"
                    else
                        _burl_error "$BURL_E_QUERY_ERROR" "Path not found: $path" \
                            "Verify the JSONPath exists in the response, or use --allow-missing" \
                            "path=$path"
                        return "$BURL_E_QUERY_ERROR"
                    fi
                else
                    # Determine if value needs quoting
                    if [[ "$value" =~ ^(\{|\[|true|false|null|-?[0-9]) ]]; then
                        query_result+="\"${path}\":${value}"
                    else
                        # Escape and quote string
                        value="${value//\\/\\\\}"
                        value="${value//\"/\\\"}"
                        value="${value//$'\n'/\\n}"
                        query_result+="\"${path}\":\"${value}\""
                    fi
                fi
            done

            query_result+="}"
            printf '%s' "$query_result"
            return 0
        fi
    fi

    # Build USOP response
    local content_type
    content_type=$(_burl_get_header "Content-Type") || true
    local content_length
    content_length=$(_burl_get_header "Content-Length") || true

    local meta_parts=(
        "status=$_BURL_STATUS"
        "url=$url"
        "method=$method"
        "duration_ms=$duration_ms"
        "content_type=${content_type:-unknown}"
    )

    [[ -n "$content_length" ]] && meta_parts+=("content_length=$content_length")
    [[ $redirect_count -gt 0 ]] && meta_parts+=("redirects=$redirect_count")
    $was_truncated && meta_parts+=("truncated=true")

    # Add analysis if requested
    if $analyze; then
        local analysis
        analysis=$(burl_analyze_response "$final_body")
        # Merge analysis into response
        local result
        result=$(_burl_ok "$final_body" "${meta_parts[@]}")
        # Replace closing brace with analysis
        result="${result%\}}"
        result+=",\"analysis\":${analysis}}"
        printf '%s' "$result"
    else
        # Check for error status codes
        if [[ "$_BURL_STATUS" =~ ^[45] ]]; then
            local error_code="$BURL_E_BAD_REQUEST"
            [[ "$_BURL_STATUS" =~ ^5 ]] && error_code="$BURL_E_SERVER_ERROR"
            _burl_semantic_error "$error_code" "HTTP $_BURL_STATUS"
            _burl_error "$error_code" "$_BURL_ERROR_MSG" "$_BURL_ERROR_SUGGEST" "${meta_parts[@]}" "body=$final_body"
        else
            _burl_ok "$final_body" "${meta_parts[@]}"
        fi
    fi

    return 0
}

# =============================================================================
# CONVENIENCE METHODS
# =============================================================================

# HTTP GET request
# @param $1 - URL
# @param $@ - additional headers
# @return USOP response
burl_get() {
    local url="$1"
    shift
    local headers=()
    for h in "$@"; do
        headers+=(-H "$h")
    done
    burl -X GET "${headers[@]}" "$url"
}

# HTTP POST request
# @param $1 - URL
# @param $2 - data
# @param $@ - additional headers
# @return USOP response
burl_post() {
    local url="$1"
    local data="$2"
    shift 2
    local headers=()
    for h in "$@"; do
        headers+=(-H "$h")
    done
    burl -X POST -d "$data" "${headers[@]}" "$url"
}

# HTTP PUT request
# @param $1 - URL
# @param $2 - data
# @param $@ - additional headers
# @return USOP response
burl_put() {
    local url="$1"
    local data="$2"
    shift 2
    local headers=()
    for h in "$@"; do
        headers+=(-H "$h")
    done
    burl -X PUT -d "$data" "${headers[@]}" "$url"
}

# HTTP PATCH request
# @param $1 - URL
# @param $2 - data
# @param $@ - additional headers
# @return USOP response
burl_patch() {
    local url="$1"
    local data="$2"
    shift 2
    local headers=()
    for h in "$@"; do
        headers+=(-H "$h")
    done
    burl -X PATCH -d "$data" "${headers[@]}" "$url"
}

# HTTP DELETE request
# @param $1 - URL
# @param $@ - additional headers
# @return USOP response
burl_delete() {
    local url="$1"
    shift
    local headers=()
    for h in "$@"; do
        headers+=(-H "$h")
    done
    burl -X DELETE "${headers[@]}" "$url"
}

# HTTP HEAD request
# @param $1 - URL
# @param $@ - additional headers
# @return USOP response (body will be empty)
burl_head() {
    local url="$1"
    shift
    local headers=()
    for h in "$@"; do
        headers+=(-H "$h")
    done
    burl -X HEAD "${headers[@]}" "$url"
}

# =============================================================================
# AI-NATIVE FEATURES
# =============================================================================

# Smart retry with exponential backoff and rate limit awareness
# @param $1 - max retries
# @param $@ - burl command (without burl prefix)
# @return USOP response
burl_smart_retry() {
    local max_retries="$1"
    shift

    local retries=0
    local delay="$BURL_RETRY_DELAY"
    local last_response=""

    while [[ $retries -lt $max_retries ]]; do
        last_response=$(burl "$@")

        # Check if successful
        if [[ "$last_response" =~ \"ok\":true ]]; then
            printf '%s' "$last_response"
            return 0
        fi

        # Check for rate limiting
        if [[ "$last_response" =~ \"code\":$BURL_E_RATE_LIMITED ]]; then
            # Try to extract retry-after
            local retry_after
            retry_after=$(echo "$last_response" | grep -oP '"retry_after":"?\K[^",]+')
            if [[ -n "$retry_after" ]] && [[ "$retry_after" =~ ^[0-9]+$ ]]; then
                delay=$retry_after
            else
                delay=$(( delay * 2 ))
            fi
        fi

        # Check for non-retryable errors
        if [[ "$last_response" =~ \"code\":($BURL_E_INVALID_URL|"$BURL_E_AUTH_FAILED") ]]; then
            printf '%s' "$last_response"
            return 1
        fi

        ((retries++)) || true

        if [[ $retries -lt $max_retries ]]; then
            sleep "$delay"
            delay=$(( delay * 2 ))
            # Cap delay at 60 seconds
            [[ $delay -gt 60 ]] && delay=60
        fi
    done

    printf '%s' "$last_response"
    return 1
}

# Truncate response to fit token budget
# @param $1 - max tokens
# @param $2 - response body
# @return Truncated response
burl_truncate_for_context() {
    local max_tokens="$1"
    local response="$2"

    _burl_truncate "$response" "$max_tokens"
}

# Analyze response type and structure
# @param $1 - response body
# @return JSON analysis object
burl_analyze_response() {
    local body="$1"

    local content_type="unknown"
    local record_count=0
    local schema_hint=""
    local is_array=false
    local is_object=false
    local estimated_tokens

    estimated_tokens=$(_burl_estimate_tokens "$body")

    # Detect content type
    local trimmed="${body#"${body%%[![:space:]]*}"}"

    if [[ "$trimmed" =~ ^\[ ]]; then
        content_type="json"
        is_array=true

        # Count array elements (rough count)
        record_count=$(printf '%s' "$body" | tr -cd '{' | wc -c | tr -d '[:space:]')

        # Try to extract schema from first object
        if [[ "$body" =~ \{([^}]+)\} ]]; then
            local first_obj="${BASH_REMATCH[1]}"
            # Extract keys
            local keys=""
            while [[ "$first_obj" =~ \"([^\"]+)\":([^,}]+) ]]; do
                [[ -n "$keys" ]] && keys+=","
                keys+="${BASH_REMATCH[1]}"
                first_obj="${first_obj#*${BASH_REMATCH[0]}}"
            done
            schema_hint="[$keys]"
        fi

    elif [[ "$trimmed" =~ ^\{ ]]; then
        content_type="json"
        is_object=true
        record_count=1

        # Extract top-level keys
        local keys=""
        local depth=0
        local in_string=false
        local current_key=""
        local i

        for ((i=0; i<${#body} && i<500; i++)); do
            local char="${body:i:1}"
            if $in_string; then
                [[ "$char" == '"' && "${body:i-1:1}" != '\' ]] && in_string=false
            else
                case "$char" in
                    '"') in_string=true ;;
                    '{') ((depth++)) || true ;;
                    '}') ((depth--)) || true ;;
                esac
            fi
        done

        # Simple key extraction
        local temp_body="${body:0:500}"
        while [[ "$temp_body" =~ \"([a-zA-Z_][a-zA-Z0-9_]*)\" ]]; do
            local key="${BASH_REMATCH[1]}"
            [[ -n "$keys" ]] && keys+=","
            keys+="$key"
            temp_body="${temp_body#*${BASH_REMATCH[0]}}"
            # Limit to first 10 keys
            [[ $(echo "$keys" | tr ',' '\n' | wc -l) -ge 10 ]] && break
        done
        schema_hint="{$keys}"

    elif [[ "$trimmed" =~ ^\<\?xml ]] || [[ "$trimmed" =~ ^\<[a-zA-Z] ]]; then
        content_type="xml"
        # Count root-level elements
        record_count=$(grep -oE '<[a-zA-Z][^>]*>' <<< "$body" | head -20 | wc -l | tr -d '[:space:]')

    elif [[ "$trimmed" =~ ^[a-zA-Z0-9_-]+, ]] || [[ "$body" =~ $'\n'[a-zA-Z0-9_-]+, ]]; then
        content_type="csv"
        record_count=$(wc -l <<< "$body" | tr -d '[:space:]')
        # Get header row
        schema_hint=$(head -1 <<< "$body")

    elif [[ "$trimmed" =~ ^# ]] || [[ "$trimmed" =~ ^\*\* ]]; then
        content_type="markdown"

    elif [[ "$trimmed" =~ ^\<!DOCTYPE ]]; then
        content_type="html"

    else
        content_type="text"
    fi

    local char_count=${#body}
    local line_count
    line_count=$(wc -l <<< "$body" | tr -d '[:space:]')

    # Escape schema_hint for JSON
    schema_hint="${schema_hint//\\/\\\\}"
    schema_hint="${schema_hint//\"/\\\"}"

    printf '{"content_type":"%s","is_array":%s,"is_object":%s,"record_count":%d,"char_count":%d,"line_count":%d,"estimated_tokens":%d,"schema_hint":"%s"}' \
        "$content_type" \
        "$($is_array && echo true || echo false)" \
        "$($is_object && echo true || echo false)" \
        "$record_count" \
        "$char_count" \
        "$line_count" \
        "$estimated_tokens" \
        "$schema_hint"
}

# Cache response with TTL
# @param $1 - ttl seconds
# @param $@ - burl command arguments
# @return USOP response (from cache or fresh)
burl_cached() {
    local ttl="$1"
    shift

    # Ensure cache directory exists
    mkdir -p "$BURL_CACHE_DIR" 2>/dev/null

    # Generate cache key from arguments
    local cache_key
    cache_key=$(_burl_sha256 "burl:$*")
    local cache_file="${BURL_CACHE_DIR}/${cache_key}"
    local meta_file="${cache_file}.meta"

    # Check cache validity
    if [[ -f "$cache_file" ]] && [[ -f "$meta_file" ]]; then
        local cached_time
        cached_time=$(cat "$meta_file" 2>/dev/null)
        local current_time
        current_time=$(date +%s)

        if [[ -n "$cached_time" ]] && (( current_time - cached_time < ttl )); then
            # Cache hit
            local cached_response
            cached_response=$(cat "$cache_file")

            # Add cache metadata to response
            if [[ "$cached_response" =~ \"meta\":\{([^}]+)\} ]]; then
                local existing_meta="${BASH_REMATCH[1]}"
                cached_response="${cached_response/\"meta\":\{$existing_meta\}/\"meta\":{$existing_meta,\"cached\":true,\"cache_age\":$((current_time - cached_time))}}"
            fi

            printf '%s' "$cached_response"
            return 0
        fi
    fi

    # Cache miss - make request
    local response
    response=$(burl "$@")

    # Cache successful responses
    if [[ "$response" =~ \"ok\":true ]]; then
        printf '%s' "$response" > "$cache_file"
        date +%s > "$meta_file"
    fi

    printf '%s' "$response"
}

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Base64 encode (pure bash)
_burl_base64_encode() {
    local input="$1"
    local chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local result=""
    local len=${#input}
    local i=0

    while ((i < len)); do
        local n=0
        local padding=0

        for ((j=0; j<3; j++)); do
            if ((i + j < len)); then
                printf -v byte '%d' "'${input:i+j:1}"
                n=$((n << 8 | byte))
            else
                n=$((n << 8))
                ((padding++)) || true
            fi
        done

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

# SHA256 hash (uses available tool)
_burl_sha256() {
    local input="$1"

    if command -v sha256sum &>/dev/null; then
        printf '%s' "$input" | sha256sum | cut -d' ' -f1
    elif command -v shasum &>/dev/null; then
        printf '%s' "$input" | shasum -a 256 | cut -d' ' -f1
    elif command -v openssl &>/dev/null; then
        printf '%s' "$input" | openssl dgst -sha256 | awk '{print $NF}'
    else
        # Fallback: simple hash (not cryptographic)
        local hash=0
        local i
        for ((i=0; i<${#input}; i++)); do
            printf -v byte '%d' "'${input:i:1}"
            hash=$(( (hash * 31 + byte) % 2147483647 ))
        done
        printf '%x' "$hash"
    fi
}

# =============================================================================
# EXPORTED FUNCTIONS
# =============================================================================

# List all bURL public functions
burl_functions() {
    cat << 'EOF'
burl              - Main function (curl-compatible + AI-native)
burl_get          - HTTP GET
burl_post         - HTTP POST
burl_put          - HTTP PUT
burl_patch        - HTTP PATCH
burl_delete       - HTTP DELETE
burl_head         - HTTP HEAD
burl_smart_retry  - Retry with exponential backoff
burl_truncate_for_context - Truncate to token budget
burl_analyze_response     - Analyze response structure
burl_cached       - Cache response with TTL
EOF
}

# =============================================================================
# MODULE INFO
# =============================================================================

# Print bURL version and capabilities
burl_version() {
    cat << 'EOF'
bURL 1.1.0 - AI-Native HTTP Client for MAINFRAME

Features:
  - USOP JSON envelope output
  - JSONPath query extraction (-q/--query)
  - Session state management (--session)
  - Semantic error messages with suggestions
  - Token-budget aware truncation
  - Smart retry with rate-limit awareness
  - Response analysis for API understanding
  - Caching with configurable TTL
  - curl-compatible flags

Dependencies:
  - Bash 4.0+
  - openssl (HTTPS only)

Environment:
  BURL_TIMEOUT        - Request timeout (default: 30)
  BURL_MAX_REDIRECTS  - Max redirects to follow (default: 10)
  BURL_MAX_TOKENS     - Default token limit (default: 0 = unlimited)
  BURL_RETRY_COUNT    - Smart retry attempts (default: 3)
  BURL_RETRY_DELAY    - Initial retry delay (default: 1)
  BURL_CACHE_DIR      - Cache directory
  BURL_VERBOSE        - Enable verbose output
EOF
}

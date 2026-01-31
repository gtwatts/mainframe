#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/burl_session.sh - HTTP Session State Management
# =============================================================================
# Description: Manages HTTP session state including cookies, authentication
#              tokens, CSRF tokens, and automatic token refresh.
#              Uses atomic writes for safe concurrent access.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================
#
# Session File Format:
# {
#   "_meta": {
#     "format_version": "1.0",
#     "created_at": "2026-01-31T10:30:00-0500",
#     "updated_at": "2026-01-31T10:35:00-0500",
#     "ttl": 3600,
#     "domain": "api.example.com"
#   },
#   "cookies": {
#     "session_id": {"value": "abc123", "path": "/", "secure": true, "expires": 0}
#   },
#   "auth": {
#     "type": "bearer",
#     "token": "eyJhbG...",
#     "refresh_token": "refresh_abc",
#     "expires_at": 1738344000
#   },
#   "csrf": {
#     "header_name": "X-CSRF-Token",
#     "token": "csrf_value"
#   }
# }
#
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_BURL_SESSION_LOADED:-}" ]] && return 0
declare -g _MAINFRAME_BURL_SESSION_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

BURL_SESSION_DEFAULT_TTL="${BURL_SESSION_DEFAULT_TTL:-3600}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Current session file path
declare -g _BURL_SESSION_PATH=""

# In-memory cache of session data
declare -gA _BURL_SESSION_COOKIES=()
declare -g _BURL_SESSION_AUTH_TYPE=""
declare -g _BURL_SESSION_AUTH_TOKEN=""
declare -g _BURL_SESSION_REFRESH_TOKEN=""
declare -g _BURL_SESSION_AUTH_EXPIRES=0
declare -g _BURL_SESSION_CSRF_HEADER=""
declare -g _BURL_SESSION_CSRF_TOKEN=""
declare -g _BURL_SESSION_TTL=0
declare -g _BURL_SESSION_DOMAIN=""

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Get current timestamp
_burl_session_timestamp() {
    date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S'
}

# Get current epoch time
_burl_session_epoch() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    else
        date +%s
    fi
}

# Atomic write with temp file + rename
_burl_session_atomic_write() {
    local file="$1"
    local content="$2"
    local dir
    dir=$(dirname "$file")

    # Ensure directory exists
    [[ -d "$dir" ]] || mkdir -p "$dir"

    local tmp="${file}.tmp.$$"
    printf '%s' "$content" > "$tmp" && mv "$tmp" "$file"
}

# Escape string for JSON
_burl_session_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

# Simple JSON value extraction (for session files only)
_burl_session_json_get() {
    local json="$1"
    local key="$2"

    # Try string value
    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    # Try numeric value
    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*([0-9-]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    # Try boolean
    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

# =============================================================================
# SESSION INITIALIZATION
# =============================================================================

# Initialize or load a session file
# @param $1 - session file path
# @param --ttl N - session TTL in seconds (optional)
# @param --domain D - domain to restrict session to (optional)
# @return 0 on success
burl_session_init() {
    local path="$1"
    shift

    local ttl="$BURL_SESSION_DEFAULT_TTL"
    local domain=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ttl)
                ttl="$2"
                shift 2
                ;;
            --domain)
                domain="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$path" ]]; then
        return 1
    fi

    _BURL_SESSION_PATH="$path"
    _BURL_SESSION_TTL="$ttl"
    _BURL_SESSION_DOMAIN="$domain"

    # Clear in-memory state
    _BURL_SESSION_COOKIES=()
    _BURL_SESSION_AUTH_TYPE=""
    _BURL_SESSION_AUTH_TOKEN=""
    _BURL_SESSION_REFRESH_TOKEN=""
    _BURL_SESSION_AUTH_EXPIRES=0
    _BURL_SESSION_CSRF_HEADER=""
    _BURL_SESSION_CSRF_TOKEN=""

    # Load existing session or create new one
    if [[ -f "$path" ]]; then
        burl_session_load "$path"
    else
        _burl_session_create
    fi
}

# Create a new session file
_burl_session_create() {
    local now
    now=$(_burl_session_timestamp)

    local content="{
  \"_meta\": {
    \"format_version\": \"1.0\",
    \"created_at\": \"$now\",
    \"updated_at\": \"$now\",
    \"ttl\": $_BURL_SESSION_TTL,
    \"domain\": \"$(_burl_session_escape "$_BURL_SESSION_DOMAIN")\"
  },
  \"cookies\": {},
  \"auth\": {},
  \"csrf\": {}
}"

    _burl_session_atomic_write "$_BURL_SESSION_PATH" "$content"
}

# Load session from file
# @param $1 - session file path
# @return 0 on success
burl_session_load() {
    local path="${1:-$_BURL_SESSION_PATH}"

    if [[ ! -f "$path" ]]; then
        return 1
    fi

    _BURL_SESSION_PATH="$path"

    local content
    content=$(<"$path")

    # Clear existing state
    _BURL_SESSION_COOKIES=()

    # Parse meta
    _BURL_SESSION_TTL=$(_burl_session_json_get "$content" "ttl") || _BURL_SESSION_TTL=0
    _BURL_SESSION_DOMAIN=$(_burl_session_json_get "$content" "domain") || _BURL_SESSION_DOMAIN=""

    # Parse auth
    _BURL_SESSION_AUTH_TYPE=$(_burl_session_json_get "$content" "type") || _BURL_SESSION_AUTH_TYPE=""
    _BURL_SESSION_AUTH_TOKEN=$(_burl_session_json_get "$content" "token") || _BURL_SESSION_AUTH_TOKEN=""
    _BURL_SESSION_REFRESH_TOKEN=$(_burl_session_json_get "$content" "refresh_token") || _BURL_SESSION_REFRESH_TOKEN=""
    _BURL_SESSION_AUTH_EXPIRES=$(_burl_session_json_get "$content" "expires_at") || _BURL_SESSION_AUTH_EXPIRES=0

    # Parse CSRF
    _BURL_SESSION_CSRF_HEADER=$(_burl_session_json_get "$content" "header_name") || _BURL_SESSION_CSRF_HEADER=""
    _BURL_SESSION_CSRF_TOKEN=$(_burl_session_json_get "$content" "csrf_token")
    [[ -z "$_BURL_SESSION_CSRF_TOKEN" ]] && _BURL_SESSION_CSRF_TOKEN=$(_burl_session_json_get "$content" "token")

    # Parse cookies (simplified - extract cookie names and values)
    # Look for "cookies": { "name": {"value": "...", ...}, ...}
    local cookies_section=""
    if [[ "$content" =~ \"cookies\"[[:space:]]*:[[:space:]]*\{([^}]+)\} ]]; then
        cookies_section="${BASH_REMATCH[1]}"
    fi

    if [[ -n "$cookies_section" ]]; then
        # Extract each cookie name and value using a safer approach
        # Pattern: "name":{"value":"val"...}
        local remaining="$cookies_section"
        local prev_len=${#remaining}
        while [[ "$remaining" =~ \"([^\"]+)\"[[:space:]]*:[[:space:]]*\{[^}]*\"value\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; do
            local cookie_name="${BASH_REMATCH[1]}"
            local cookie_value="${BASH_REMATCH[2]}"
            _BURL_SESSION_COOKIES["$cookie_name"]="$cookie_value"

            # Remove the matched portion - find the closing brace after the cookie
            local match_end="${remaining#*\"$cookie_name\"*\}}"
            if [[ ${#match_end} -eq ${#remaining} ]]; then
                # No progress made, break to avoid infinite loop
                break
            fi
            remaining="$match_end"

            # Safety check - if no progress, break
            if [[ ${#remaining} -ge $prev_len ]]; then
                break
            fi
            prev_len=${#remaining}
        done
    fi

    return 0
}

# Save session to file
# @return 0 on success
burl_session_save() {
    local path="${_BURL_SESSION_PATH}"

    if [[ -z "$path" ]]; then
        return 1
    fi

    local now
    now=$(_burl_session_timestamp)

    # Build cookies JSON
    local cookies_json="{"
    local first=true
    for name in "${!_BURL_SESSION_COOKIES[@]}"; do
        $first || cookies_json+=","
        first=false
        local value="${_BURL_SESSION_COOKIES[$name]}"
        cookies_json+="\"$(_burl_session_escape "$name")\":{\"value\":\"$(_burl_session_escape "$value")\"}"
    done
    cookies_json+="}"

    # Build auth JSON
    local auth_json="{}"
    if [[ -n "$_BURL_SESSION_AUTH_TOKEN" ]]; then
        auth_json="{"
        auth_json+="\"type\":\"$(_burl_session_escape "$_BURL_SESSION_AUTH_TYPE")\","
        auth_json+="\"token\":\"$(_burl_session_escape "$_BURL_SESSION_AUTH_TOKEN")\""
        [[ -n "$_BURL_SESSION_REFRESH_TOKEN" ]] && auth_json+=",\"refresh_token\":\"$(_burl_session_escape "$_BURL_SESSION_REFRESH_TOKEN")\""
        [[ "$_BURL_SESSION_AUTH_EXPIRES" -gt 0 ]] && auth_json+=",\"expires_at\":$_BURL_SESSION_AUTH_EXPIRES"
        auth_json+="}"
    fi

    # Build CSRF JSON
    local csrf_json="{}"
    if [[ -n "$_BURL_SESSION_CSRF_TOKEN" ]]; then
        csrf_json="{"
        [[ -n "$_BURL_SESSION_CSRF_HEADER" ]] && csrf_json+="\"header_name\":\"$(_burl_session_escape "$_BURL_SESSION_CSRF_HEADER")\","
        csrf_json+="\"token\":\"$(_burl_session_escape "$_BURL_SESSION_CSRF_TOKEN")\""
        csrf_json+="}"
    fi

    # Load existing meta or create new
    local created_at="$now"
    if [[ -f "$path" ]]; then
        local existing
        existing=$(<"$path")
        local existing_created
        existing_created=$(_burl_session_json_get "$existing" "created_at")
        [[ -n "$existing_created" ]] && created_at="$existing_created"
    fi

    local content="{
  \"_meta\": {
    \"format_version\": \"1.0\",
    \"created_at\": \"$created_at\",
    \"updated_at\": \"$now\",
    \"ttl\": $_BURL_SESSION_TTL,
    \"domain\": \"$(_burl_session_escape "$_BURL_SESSION_DOMAIN")\"
  },
  \"cookies\": $cookies_json,
  \"auth\": $auth_json,
  \"csrf\": $csrf_json
}"

    _burl_session_atomic_write "$path" "$content"
}

# =============================================================================
# COOKIE MANAGEMENT
# =============================================================================

# Get a cookie value
# @param $1 - cookie name
# @return Cookie value or empty
burl_session_cookie() {
    local name="$1"
    printf '%s' "${_BURL_SESSION_COOKIES[$name]:-}"
}

# Set a cookie from Set-Cookie header string
# @param $1 - Set-Cookie header value (e.g., "session_id=abc; Path=/; HttpOnly")
burl_session_set_cookie() {
    local cookie_string="$1"

    # Parse cookie string
    # Format: name=value; attr1; attr2=val2; ...

    # Extract name=value (first part before ;)
    local name_value="${cookie_string%%;*}"
    local name="${name_value%%=*}"
    local value="${name_value#*=}"

    # Trim whitespace
    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ -n "$name" ]]; then
        _BURL_SESSION_COOKIES["$name"]="$value"
        burl_session_save
    fi
}

# Get Cookie header string for requests
# @return "Cookie: name1=val1; name2=val2" or empty
burl_session_cookie_header() {
    if [[ ${#_BURL_SESSION_COOKIES[@]} -eq 0 ]]; then
        return 1
    fi

    local header="Cookie:"
    local first=true

    for name in "${!_BURL_SESSION_COOKIES[@]}"; do
        local value="${_BURL_SESSION_COOKIES[$name]}"
        $first && header+=" " || header+="; "
        first=false
        header+="${name}=${value}"
    done

    printf '%s' "$header"
}

# Clear all cookies
burl_session_clear_cookies() {
    _BURL_SESSION_COOKIES=()
    burl_session_save
}

# =============================================================================
# AUTHENTICATION MANAGEMENT
# =============================================================================

# Set authentication token
# @param --type T - auth type (bearer, basic, api-key)
# @param --token T - the token value
# @param --refresh-token T - refresh token (optional)
# @param --expires-at N - epoch timestamp when token expires (optional)
burl_session_set_auth() {
    _BURL_SESSION_AUTH_TYPE=""
    _BURL_SESSION_AUTH_TOKEN=""
    _BURL_SESSION_REFRESH_TOKEN=""
    _BURL_SESSION_AUTH_EXPIRES=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                _BURL_SESSION_AUTH_TYPE="$2"
                shift 2
                ;;
            --token)
                _BURL_SESSION_AUTH_TOKEN="$2"
                shift 2
                ;;
            --refresh-token)
                _BURL_SESSION_REFRESH_TOKEN="$2"
                shift 2
                ;;
            --expires-at)
                _BURL_SESSION_AUTH_EXPIRES="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    burl_session_save
}

# Get Authorization header string
# @return "Authorization: Bearer ..." or empty
burl_session_auth_header() {
    if [[ -z "$_BURL_SESSION_AUTH_TOKEN" ]]; then
        return 1
    fi

    local header=""
    case "${_BURL_SESSION_AUTH_TYPE,,}" in
        bearer|"")
            header="Authorization: Bearer $_BURL_SESSION_AUTH_TOKEN"
            ;;
        basic)
            header="Authorization: Basic $_BURL_SESSION_AUTH_TOKEN"
            ;;
        api-key|apikey)
            header="X-API-Key: $_BURL_SESSION_AUTH_TOKEN"
            ;;
        *)
            header="Authorization: $_BURL_SESSION_AUTH_TYPE $_BURL_SESSION_AUTH_TOKEN"
            ;;
    esac

    printf '%s' "$header"
}

# Check if auth token is expired
# @return 0 if expired, 1 if valid
burl_session_auth_expired() {
    if [[ "$_BURL_SESSION_AUTH_EXPIRES" -le 0 ]]; then
        return 1  # No expiry set, assume valid
    fi

    local now
    now=$(_burl_session_epoch)

    (( _BURL_SESSION_AUTH_EXPIRES <= now ))
}

# Get refresh token (for token refresh flows)
burl_session_refresh_token() {
    printf '%s' "$_BURL_SESSION_REFRESH_TOKEN"
}

# Clear authentication
burl_session_clear_auth() {
    _BURL_SESSION_AUTH_TYPE=""
    _BURL_SESSION_AUTH_TOKEN=""
    _BURL_SESSION_REFRESH_TOKEN=""
    _BURL_SESSION_AUTH_EXPIRES=0
    burl_session_save
}

# =============================================================================
# CSRF MANAGEMENT
# =============================================================================

# Set CSRF token
# @param $1 - token value
# @param $2 - header name (optional, default: X-CSRF-Token)
burl_session_set_csrf() {
    local token="$1"
    local header_name="${2:-X-CSRF-Token}"

    _BURL_SESSION_CSRF_TOKEN="$token"
    _BURL_SESSION_CSRF_HEADER="$header_name"

    burl_session_save
}

# Get CSRF header string
# @return "X-CSRF-Token: value" or empty
burl_session_csrf_header() {
    if [[ -z "$_BURL_SESSION_CSRF_TOKEN" ]]; then
        return 1
    fi

    local header_name="${_BURL_SESSION_CSRF_HEADER:-X-CSRF-Token}"
    printf '%s: %s' "$header_name" "$_BURL_SESSION_CSRF_TOKEN"
}

# Get raw CSRF token value
burl_session_csrf_token() {
    printf '%s' "$_BURL_SESSION_CSRF_TOKEN"
}

# Clear CSRF token
burl_session_clear_csrf() {
    _BURL_SESSION_CSRF_TOKEN=""
    _BURL_SESSION_CSRF_HEADER=""
    burl_session_save
}

# =============================================================================
# RESPONSE HEADER PARSING
# =============================================================================

# Update session from HTTP response headers
# @param $1 - response headers string
# @return 0 on success
burl_session_update_from_response() {
    local headers="$1"
    local updated=false

    # Parse Set-Cookie headers
    while IFS= read -r line; do
        line="${line%$'\r'}"

        # Set-Cookie header
        if [[ "${line,,}" =~ ^set-cookie:[[:space:]]*(.+)$ ]]; then
            local cookie_value="${BASH_REMATCH[1]}"
            burl_session_set_cookie "$cookie_value"
            updated=true
        fi

        # CSRF token in response header (common patterns)
        if [[ "${line,,}" =~ ^x-csrf-token:[[:space:]]*(.+)$ ]]; then
            _BURL_SESSION_CSRF_TOKEN="${BASH_REMATCH[1]}"
            _BURL_SESSION_CSRF_HEADER="X-CSRF-Token"
            updated=true
        fi

        if [[ "${line,,}" =~ ^x-xsrf-token:[[:space:]]*(.+)$ ]]; then
            _BURL_SESSION_CSRF_TOKEN="${BASH_REMATCH[1]}"
            _BURL_SESSION_CSRF_HEADER="X-XSRF-Token"
            updated=true
        fi

    done <<< "$headers"

    $updated && burl_session_save

    return 0
}

# =============================================================================
# SESSION VALIDITY
# =============================================================================

# Check if session is valid (not expired)
# @return 0 if valid, 1 if expired/invalid
burl_session_is_valid() {
    # No session loaded
    if [[ -z "$_BURL_SESSION_PATH" ]]; then
        return 1
    fi

    # No TTL set means never expires
    if [[ "$_BURL_SESSION_TTL" -le 0 ]]; then
        return 0
    fi

    # Check file modification time
    if [[ -f "$_BURL_SESSION_PATH" ]]; then
        local now
        now=$(_burl_session_epoch)

        local mtime
        mtime=$(stat -c %Y "$_BURL_SESSION_PATH" 2>/dev/null || stat -f %m "$_BURL_SESSION_PATH" 2>/dev/null)

        if [[ -n "$mtime" ]]; then
            local age=$((now - mtime))
            if (( age > _BURL_SESSION_TTL )); then
                return 1  # Expired
            fi
        fi
    fi

    return 0
}

# =============================================================================
# SESSION CLEANUP
# =============================================================================

# Clear all session data
burl_session_clear() {
    _BURL_SESSION_COOKIES=()
    _BURL_SESSION_AUTH_TYPE=""
    _BURL_SESSION_AUTH_TOKEN=""
    _BURL_SESSION_REFRESH_TOKEN=""
    _BURL_SESSION_AUTH_EXPIRES=0
    _BURL_SESSION_CSRF_HEADER=""
    _BURL_SESSION_CSRF_TOKEN=""

    if [[ -n "$_BURL_SESSION_PATH" ]]; then
        _burl_session_create
    fi
}

# Destroy session (delete file)
burl_session_destroy() {
    if [[ -n "$_BURL_SESSION_PATH" && -f "$_BURL_SESSION_PATH" ]]; then
        rm -f "$_BURL_SESSION_PATH"
    fi

    _BURL_SESSION_PATH=""
    _BURL_SESSION_COOKIES=()
    _BURL_SESSION_AUTH_TYPE=""
    _BURL_SESSION_AUTH_TOKEN=""
    _BURL_SESSION_REFRESH_TOKEN=""
    _BURL_SESSION_AUTH_EXPIRES=0
    _BURL_SESSION_CSRF_HEADER=""
    _BURL_SESSION_CSRF_TOKEN=""
}

# =============================================================================
# MODULE INFO
# =============================================================================

burl_session_version() {
    cat << 'EOF'
burl_session 1.0.0 - HTTP Session State Management for MAINFRAME

Features:
  - Cookie jar with Set-Cookie parsing
  - Authentication token management (Bearer, Basic, API-Key)
  - Token expiry tracking and refresh token support
  - CSRF token management
  - Atomic file writes for concurrent safety
  - Session TTL and validity checking

Functions:
  burl_session_init           - Initialize session file
  burl_session_load           - Load existing session
  burl_session_save           - Save session to file
  burl_session_cookie         - Get cookie value
  burl_session_set_cookie     - Set cookie from header
  burl_session_cookie_header  - Get Cookie header string
  burl_session_set_auth       - Set auth token
  burl_session_auth_header    - Get Authorization header
  burl_session_set_csrf       - Set CSRF token
  burl_session_csrf_header    - Get CSRF header string
  burl_session_update_from_response - Parse response headers
  burl_session_is_valid       - Check session validity
  burl_session_clear          - Clear session data
  burl_session_destroy        - Delete session file

Dependencies: None (pure bash)
Requires: Bash 4.0+
EOF
}

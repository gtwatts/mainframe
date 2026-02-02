#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/llm_stream.sh - LLM API Streaming Response Handler
# =============================================================================
# Description: Pure bash streaming response handler for LLM APIs (OpenAI,
#              Anthropic). Parses Server-Sent Events (SSE) format, handles
#              delta content extraction, and provides callback-based token
#              processing with cancellation support.
#
# Features:
#   - SSE parsing (data:, event:, id: fields)
#   - OpenAI delta extraction (choices[0].delta.content)
#   - Anthropic delta extraction (delta.text)
#   - Callback registration (token, complete, error)
#   - Non-blocking background streaming
#   - Cancel in-flight requests
#   - Buffer accumulation
#   - USOP-compliant JSON output
#
# Version: 1.0.0
# Requires: Bash 4.0+, curl with --no-buffer support
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_LLM_STREAM_LOADED:-}" ]] && return 0
readonly _MAINFRAME_LLM_STREAM_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Stream state
LLM_STREAM_STATUS="idle"      # idle|active|complete|error|cancelled
LLM_STREAM_BUFFER=""          # Accumulated response buffer
LLM_STREAM_ERROR=""           # Last error message
LLM_STREAM_TOKENS=0           # Token count (approximate)
LLM_STREAM_PID=""             # Background curl process ID
LLM_STREAM_FIFO=""            # Named pipe for stream data
LLM_STREAM_PROVIDER=""        # openai|anthropic|auto

# Callbacks (function names)
_LLM_STREAM_ON_TOKEN=""
_LLM_STREAM_ON_COMPLETE=""
_LLM_STREAM_ON_ERROR=""

# Timeouts
LLM_STREAM_CONNECT_TIMEOUT="${LLM_STREAM_CONNECT_TIMEOUT:-30}"
LLM_STREAM_READ_TIMEOUT="${LLM_STREAM_READ_TIMEOUT:-300}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Log message for debugging
_llm_stream_log() {
    local level="$1"
    shift
    if [[ "${LLM_STREAM_DEBUG:-0}" == "1" ]]; then
        printf '[llm_stream] [%s] %s\n' "$level" "$*" >&2
    fi
}

# JSON escape for output
_llm_stream_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    # Handle control characters
    local i char result=""
    for ((i=0; i<${#str}; i++)); do
        char="${str:i:1}"
        if [[ "$char" < $'\x20' && "$char" != $'\t' && "$char" != $'\n' && "$char" != $'\r' ]]; then
            printf -v char '\\u%04x' "'$char"
        fi
        result+="$char"
    done
    printf '%s' "$result"
}

# Extract JSON value by key (simple top-level extraction)
# Usage: _llm_stream_json_get '{"key":"value"}' "key"
_llm_stream_json_get() {
    local json="$1"
    local key="$2"

    # String value extraction
    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*\"([^\"\\]*(\\.[^\"\\]*)*)\" ]]; then
        local value="${BASH_REMATCH[1]}"
        # Unescape JSON string
        value="${value//\\n/$'\n'}"
        value="${value//\\t/$'\t'}"
        value="${value//\\r/$'\r'}"
        value="${value//\\\"/\"}"
        value="${value//\\\\/\\}"
        printf '%s' "$value"
        return 0
    fi

    # Numeric/boolean/null value extraction
    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*([0-9.eE+-]+|true|false|null) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

# Detect provider from URL or request
# Usage: _llm_stream_detect_provider "https://api.openai.com/..."
_llm_stream_detect_provider() {
    local url="$1"

    case "$url" in
        *api.openai.com*|*openai*)
            printf 'openai'
            ;;
        *anthropic.com*|*claude*)
            printf 'anthropic'
            ;;
        *localhost*|*127.0.0.1*)
            # Local models often use OpenAI-compatible format
            printf 'openai'
            ;;
        *)
            # Default to OpenAI format (most common)
            printf 'openai'
            ;;
    esac
}

# Parse OpenAI SSE delta content
# Usage: _llm_stream_parse_openai_delta "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}"
_llm_stream_parse_openai_delta() {
    local data="$1"

    # Check for [DONE] signal
    if [[ "$data" == "[DONE]" ]]; then
        return 1
    fi

    # Extract content from choices[0].delta.content
    # Pattern: "content":"..."
    if [[ "$data" =~ \"content\"[[:space:]]*:[[:space:]]*\"([^\"\\]*(\\.[^\"\\]*)*)\" ]]; then
        local content="${BASH_REMATCH[1]}"
        # Unescape JSON
        content="${content//\\n/$'\n'}"
        content="${content//\\t/$'\t'}"
        content="${content//\\r/$'\r'}"
        content="${content//\\\"/\"}"
        content="${content//\\\\/\\}"
        printf '%s' "$content"
        return 0
    fi

    # Empty delta (role-only, finish_reason, etc.)
    return 0
}

# Parse Anthropic SSE delta content
# Usage: _llm_stream_parse_anthropic_delta "data: {\"type\":\"content_block_delta\",\"delta\":{\"text\":\"Hello\"}}"
_llm_stream_parse_anthropic_delta() {
    local data="$1"

    # Check for message_stop signal
    if [[ "$data" =~ \"type\"[[:space:]]*:[[:space:]]*\"message_stop\" ]]; then
        return 1
    fi

    # Extract text from delta.text (content_block_delta events)
    if [[ "$data" =~ \"text\"[[:space:]]*:[[:space:]]*\"([^\"\\]*(\\.[^\"\\]*)*)\" ]]; then
        local text="${BASH_REMATCH[1]}"
        # Unescape JSON
        text="${text//\\n/$'\n'}"
        text="${text//\\t/$'\t'}"
        text="${text//\\r/$'\r'}"
        text="${text//\\\"/\"}"
        text="${text//\\\\/\\}"
        printf '%s' "$text"
        return 0
    fi

    return 0
}

# Clean up stream resources
_llm_stream_cleanup() {
    _llm_stream_log "debug" "Cleaning up stream resources"

    # Kill background process if running
    if [[ -n "$LLM_STREAM_PID" ]] && kill -0 "$LLM_STREAM_PID" 2>/dev/null; then
        kill "$LLM_STREAM_PID" 2>/dev/null || true
        wait "$LLM_STREAM_PID" 2>/dev/null || true
    fi
    LLM_STREAM_PID=""

    # Remove FIFO if exists
    if [[ -n "$LLM_STREAM_FIFO" && -p "$LLM_STREAM_FIFO" ]]; then
        rm -f "$LLM_STREAM_FIFO" 2>/dev/null || true
    fi
    LLM_STREAM_FIFO=""
}

# =============================================================================
# CALLBACK REGISTRATION
# =============================================================================

# Register callback for each received token
# @pre: callback_function exists and is callable
# @post: callback will be invoked with each token chunk
# @idempotent: yes (overwrites previous callback)
# @returns: 0 on success, 1 if function doesn't exist
#
# Usage: llm_stream_on_token "my_token_handler"
# Callback receives: $1 = token text
llm_stream_on_token() {
    local callback="$1"

    if [[ -z "$callback" ]]; then
        _LLM_STREAM_ON_TOKEN=""
        return 0
    fi

    if ! declare -F "$callback" &>/dev/null; then
        _llm_stream_log "error" "Token callback function not found: $callback"
        return 1
    fi

    _LLM_STREAM_ON_TOKEN="$callback"
    _llm_stream_log "debug" "Registered token callback: $callback"
    return 0
}

# Register callback for stream completion
# @pre: callback_function exists and is callable
# @post: callback will be invoked when stream completes
# @idempotent: yes (overwrites previous callback)
# @returns: 0 on success, 1 if function doesn't exist
#
# Usage: llm_stream_on_complete "my_complete_handler"
# Callback receives: $1 = full accumulated buffer
llm_stream_on_complete() {
    local callback="$1"

    if [[ -z "$callback" ]]; then
        _LLM_STREAM_ON_COMPLETE=""
        return 0
    fi

    if ! declare -F "$callback" &>/dev/null; then
        _llm_stream_log "error" "Complete callback function not found: $callback"
        return 1
    fi

    _LLM_STREAM_ON_COMPLETE="$callback"
    _llm_stream_log "debug" "Registered complete callback: $callback"
    return 0
}

# Register callback for stream errors
# @pre: callback_function exists and is callable
# @post: callback will be invoked on error
# @idempotent: yes (overwrites previous callback)
# @returns: 0 on success, 1 if function doesn't exist
#
# Usage: llm_stream_on_error "my_error_handler"
# Callback receives: $1 = error message, $2 = error code
llm_stream_on_error() {
    local callback="$1"

    if [[ -z "$callback" ]]; then
        _LLM_STREAM_ON_ERROR=""
        return 0
    fi

    if ! declare -F "$callback" &>/dev/null; then
        _llm_stream_log "error" "Error callback function not found: $callback"
        return 1
    fi

    _LLM_STREAM_ON_ERROR="$callback"
    _llm_stream_log "debug" "Registered error callback: $callback"
    return 0
}

# =============================================================================
# STREAM CONTROL
# =============================================================================

# Start streaming request to LLM API
# @pre: url is valid HTTP/HTTPS endpoint
# @post: streaming begins, callbacks invoked for each token
# @idempotent: no (starts new stream)
# @returns: 0 on success, 1 on error
#
# Usage: llm_stream_request "https://api.openai.com/v1/chat/completions" \
#          '{"model":"gpt-4","stream":true,"messages":[...]}' \
#          "Authorization: Bearer $API_KEY" \
#          "Content-Type: application/json"
llm_stream_request() {
    local url="$1"
    local payload="$2"
    shift 2
    local headers=("$@")

    # Validate URL
    if [[ -z "$url" ]]; then
        LLM_STREAM_STATUS="error"
        LLM_STREAM_ERROR="URL is required"
        [[ -n "$_LLM_STREAM_ON_ERROR" ]] && "$_LLM_STREAM_ON_ERROR" "$LLM_STREAM_ERROR" "1"
        return 1
    fi

    # Check for curl
    if ! command -v curl &>/dev/null; then
        LLM_STREAM_STATUS="error"
        LLM_STREAM_ERROR="curl is required for streaming"
        [[ -n "$_LLM_STREAM_ON_ERROR" ]] && "$_LLM_STREAM_ON_ERROR" "$LLM_STREAM_ERROR" "2"
        return 1
    fi

    # Cancel any existing stream
    if [[ "$LLM_STREAM_STATUS" == "active" ]]; then
        llm_stream_cancel
    fi

    # Reset state
    LLM_STREAM_STATUS="active"
    LLM_STREAM_BUFFER=""
    LLM_STREAM_ERROR=""
    LLM_STREAM_TOKENS=0

    # Detect provider
    LLM_STREAM_PROVIDER=$(_llm_stream_detect_provider "$url")
    _llm_stream_log "debug" "Detected provider: $LLM_STREAM_PROVIDER"

    # Create FIFO for streaming data
    LLM_STREAM_FIFO=$(mktemp -u "${TMPDIR:-/tmp}/llm_stream.XXXXXX")
    mkfifo "$LLM_STREAM_FIFO" || {
        LLM_STREAM_STATUS="error"
        LLM_STREAM_ERROR="Failed to create stream pipe"
        [[ -n "$_LLM_STREAM_ON_ERROR" ]] && "$_LLM_STREAM_ON_ERROR" "$LLM_STREAM_ERROR" "3"
        return 1
    }

    # Build curl command
    local curl_args=(
        --no-buffer
        --silent
        --show-error
        --connect-timeout "$LLM_STREAM_CONNECT_TIMEOUT"
        --max-time "$LLM_STREAM_READ_TIMEOUT"
        -X POST
        --data "$payload"
    )

    # Add headers
    for header in "${headers[@]}"; do
        [[ -n "$header" ]] && curl_args+=(-H "$header")
    done

    # Start curl in background, writing to FIFO
    curl "${curl_args[@]}" "$url" > "$LLM_STREAM_FIFO" 2>&1 &
    LLM_STREAM_PID=$!

    _llm_stream_log "debug" "Started stream PID $LLM_STREAM_PID to $url"

    # Process stream in foreground
    _llm_stream_process

    return $?
}

# Internal: Process stream data from FIFO
_llm_stream_process() {
    local line data event_type
    local current_data=""
    local stream_done=false
    local http_error=false

    # Read from FIFO
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Check if cancelled
        if [[ "$LLM_STREAM_STATUS" == "cancelled" ]]; then
            _llm_stream_log "debug" "Stream cancelled during processing"
            break
        fi

        # Remove carriage return if present
        line="${line%$'\r'}"

        _llm_stream_log "trace" "Received line: $line"

        # Check for HTTP error response (not SSE format)
        if [[ "$line" =~ ^\{.*\"error\" ]]; then
            local error_msg
            error_msg=$(_llm_stream_json_get "$line" "message") || \
            error_msg=$(_llm_stream_json_get "$line" "error") || \
            error_msg="API error"

            LLM_STREAM_STATUS="error"
            LLM_STREAM_ERROR="$error_msg"
            http_error=true
            _llm_stream_log "error" "HTTP error: $error_msg"
            [[ -n "$_LLM_STREAM_ON_ERROR" ]] && "$_LLM_STREAM_ON_ERROR" "$error_msg" "4"
            break
        fi

        # Parse SSE format
        case "$line" in
            "data: "*)
                # Extract data content
                data="${line#data: }"

                # Check for [DONE] signal
                if [[ "$data" == "[DONE]" ]]; then
                    _llm_stream_log "debug" "Received [DONE] signal"
                    stream_done=true
                    break
                fi

                # Parse delta based on provider
                local token=""
                case "$LLM_STREAM_PROVIDER" in
                    openai)
                        token=$(_llm_stream_parse_openai_delta "$data")
                        ;;
                    anthropic)
                        if [[ "$data" =~ \"type\"[[:space:]]*:[[:space:]]*\"message_stop\" ]]; then
                            _llm_stream_log "debug" "Received message_stop signal"
                            stream_done=true
                            break
                        fi
                        token=$(_llm_stream_parse_anthropic_delta "$data")
                        ;;
                esac

                # Process token if we got content
                if [[ -n "$token" ]]; then
                    LLM_STREAM_BUFFER+="$token"
                    ((LLM_STREAM_TOKENS++))

                    # Invoke token callback
                    if [[ -n "$_LLM_STREAM_ON_TOKEN" ]]; then
                        "$_LLM_STREAM_ON_TOKEN" "$token"
                    fi
                fi
                ;;

            "event: "*)
                # Track event type for Anthropic
                event_type="${line#event: }"
                _llm_stream_log "trace" "Event type: $event_type"
                ;;

            "id: "*)
                # SSE event ID (usually ignored for LLM streams)
                _llm_stream_log "trace" "Event ID: ${line#id: }"
                ;;

            "")
                # Empty line marks end of SSE event
                ;;

            *)
                # Could be raw JSON (some APIs don't use SSE prefix)
                if [[ "$line" =~ ^\{.*\}$ ]]; then
                    local token=""
                    case "$LLM_STREAM_PROVIDER" in
                        openai)
                            token=$(_llm_stream_parse_openai_delta "$line")
                            ;;
                        anthropic)
                            token=$(_llm_stream_parse_anthropic_delta "$line")
                            ;;
                    esac

                    if [[ -n "$token" ]]; then
                        LLM_STREAM_BUFFER+="$token"
                        ((LLM_STREAM_TOKENS++))
                        [[ -n "$_LLM_STREAM_ON_TOKEN" ]] && "$_LLM_STREAM_ON_TOKEN" "$token"
                    fi
                fi
                ;;
        esac
    done < "$LLM_STREAM_FIFO"

    # Wait for curl to complete
    wait "$LLM_STREAM_PID" 2>/dev/null
    local curl_exit=$?

    # Clean up resources
    _llm_stream_cleanup

    # Handle curl errors
    if [[ $curl_exit -ne 0 && "$LLM_STREAM_STATUS" != "cancelled" && ! $http_error ]]; then
        local error_msg="curl exited with code $curl_exit"
        case $curl_exit in
            6)  error_msg="Could not resolve host" ;;
            7)  error_msg="Connection refused" ;;
            28) error_msg="Connection timeout" ;;
            35) error_msg="SSL/TLS handshake failed" ;;
            52) error_msg="Empty response from server" ;;
            56) error_msg="Network receive error" ;;
        esac

        LLM_STREAM_STATUS="error"
        LLM_STREAM_ERROR="$error_msg"
        _llm_stream_log "error" "Curl error: $error_msg"
        [[ -n "$_LLM_STREAM_ON_ERROR" ]] && "$_LLM_STREAM_ON_ERROR" "$error_msg" "$curl_exit"
        return 1
    fi

    # Update final status
    if [[ "$LLM_STREAM_STATUS" == "active" ]]; then
        LLM_STREAM_STATUS="complete"
        _llm_stream_log "debug" "Stream complete, buffer size: ${#LLM_STREAM_BUFFER}, tokens: $LLM_STREAM_TOKENS"

        # Invoke complete callback
        if [[ -n "$_LLM_STREAM_ON_COMPLETE" ]]; then
            "$_LLM_STREAM_ON_COMPLETE" "$LLM_STREAM_BUFFER"
        fi
    fi

    return 0
}

# Cancel in-flight streaming request
# @pre: none (safe to call in any state)
# @post: stream cancelled, status set to cancelled
# @idempotent: yes
# @returns: 0 on success
#
# Usage: llm_stream_cancel
llm_stream_cancel() {
    _llm_stream_log "debug" "Cancelling stream"

    local was_active=false
    [[ "$LLM_STREAM_STATUS" == "active" ]] && was_active=true

    LLM_STREAM_STATUS="cancelled"
    _llm_stream_cleanup

    if $was_active; then
        _llm_stream_log "info" "Stream cancelled (had ${#LLM_STREAM_BUFFER} bytes, $LLM_STREAM_TOKENS tokens)"
    fi

    return 0
}

# Get current accumulated buffer
# @pre: none
# @post: buffer content returned
# @idempotent: yes
# @returns: buffer content to stdout
#
# Usage: content=$(llm_stream_buffer_get)
llm_stream_buffer_get() {
    printf '%s' "$LLM_STREAM_BUFFER"
}

# Get current stream status
# @pre: none
# @post: status string returned
# @idempotent: yes
# @returns: one of: idle|active|complete|error|cancelled
#
# Usage: status=$(llm_stream_status)
llm_stream_status() {
    printf '%s' "$LLM_STREAM_STATUS"
}

# Reset stream state to idle
# @pre: stream not active
# @post: all state cleared
# @idempotent: yes
# @returns: 0 on success, 1 if stream active
#
# Usage: llm_stream_reset
llm_stream_reset() {
    if [[ "$LLM_STREAM_STATUS" == "active" ]]; then
        _llm_stream_log "warn" "Cannot reset while stream is active"
        return 1
    fi

    LLM_STREAM_STATUS="idle"
    LLM_STREAM_BUFFER=""
    LLM_STREAM_ERROR=""
    LLM_STREAM_TOKENS=0
    LLM_STREAM_PID=""
    LLM_STREAM_FIFO=""
    LLM_STREAM_PROVIDER=""

    _llm_stream_log "debug" "Stream state reset"
    return 0
}

# =============================================================================
# STATUS AND INFO FUNCTIONS
# =============================================================================

# Get stream info as JSON
# @pre: none
# @post: USOP JSON envelope returned
# @idempotent: yes
# @returns: JSON object with stream state
#
# Usage: llm_stream_info
llm_stream_info() {
    local escaped_buffer escaped_error
    escaped_buffer=$(_llm_stream_json_escape "$LLM_STREAM_BUFFER")
    escaped_error=$(_llm_stream_json_escape "$LLM_STREAM_ERROR")

    printf '{"ok":true,"data":{"status":"%s","provider":"%s","tokens":%d,"buffer_length":%d,"error":"%s"}}' \
        "$LLM_STREAM_STATUS" \
        "${LLM_STREAM_PROVIDER:-unknown}" \
        "$LLM_STREAM_TOKENS" \
        "${#LLM_STREAM_BUFFER}" \
        "$escaped_error"
}

# Get last error message
# @pre: none
# @post: error message returned
# @idempotent: yes
# @returns: error message or empty string
#
# Usage: error=$(llm_stream_error)
llm_stream_error() {
    printf '%s' "$LLM_STREAM_ERROR"
}

# Get approximate token count
# @pre: none
# @post: token count returned
# @idempotent: yes
# @returns: token count (number of delta chunks received)
#
# Usage: tokens=$(llm_stream_token_count)
llm_stream_token_count() {
    printf '%d' "$LLM_STREAM_TOKENS"
}

# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

# Stream with simple text output (no callbacks needed)
# @pre: url and payload are valid
# @post: streamed content written to stdout
# @idempotent: no
# @returns: 0 on success, 1 on error
#
# Usage: llm_stream_simple "url" "payload" "headers..."
llm_stream_simple() {
    # Token callback that prints to stdout
    _llm_stream_simple_token() {
        printf '%s' "$1"
    }

    llm_stream_on_token "_llm_stream_simple_token"
    llm_stream_on_complete ""
    llm_stream_on_error ""

    llm_stream_request "$@"
    local result=$?

    # Newline after stream
    [[ "$LLM_STREAM_STATUS" == "complete" ]] && printf '\n'

    return $result
}

# Synchronous stream with full response returned
# @pre: url and payload are valid
# @post: complete response returned
# @idempotent: no
# @returns: accumulated buffer to stdout, status via exit code
#
# Usage: response=$(llm_stream_sync "url" "payload" "headers...")
llm_stream_sync() {
    # Silent streaming (no token callback)
    llm_stream_on_token ""
    llm_stream_on_complete ""
    llm_stream_on_error ""

    llm_stream_request "$@"
    local result=$?

    if [[ $result -eq 0 && "$LLM_STREAM_STATUS" == "complete" ]]; then
        printf '%s' "$LLM_STREAM_BUFFER"
    fi

    return $result
}

# =============================================================================
# USOP OUTPUT WRAPPER
# =============================================================================

# Wrap stream result in USOP envelope
# @pre: stream has completed
# @post: USOP JSON envelope returned
# @idempotent: yes
# @returns: JSON envelope with status, content, metadata
#
# Usage: llm_stream_to_usop
llm_stream_to_usop() {
    local ok="true"
    local error_msg=""

    if [[ "$LLM_STREAM_STATUS" == "error" || "$LLM_STREAM_STATUS" == "cancelled" ]]; then
        ok="false"
        error_msg=$(_llm_stream_json_escape "$LLM_STREAM_ERROR")
    fi

    local content
    content=$(_llm_stream_json_escape "$LLM_STREAM_BUFFER")

    printf '{"ok":%s,"data":{"content":"%s","status":"%s"},"meta":{"provider":"%s","tokens":%d,"buffer_bytes":%d}' \
        "$ok" \
        "$content" \
        "$LLM_STREAM_STATUS" \
        "${LLM_STREAM_PROVIDER:-unknown}" \
        "$LLM_STREAM_TOKENS" \
        "${#LLM_STREAM_BUFFER}"

    if [[ -n "$error_msg" ]]; then
        printf ',"error":"%s"' "$error_msg"
    fi

    printf '}'
}

# =============================================================================
# PROVIDER-SPECIFIC HELPERS
# =============================================================================

# Set provider explicitly (instead of auto-detect)
# @pre: provider is openai or anthropic
# @post: provider set for subsequent requests
# @idempotent: yes
# @returns: 0 on success, 1 if invalid provider
#
# Usage: llm_stream_set_provider "anthropic"
llm_stream_set_provider() {
    local provider="$1"

    case "$provider" in
        openai|anthropic)
            LLM_STREAM_PROVIDER="$provider"
            _llm_stream_log "debug" "Provider set to: $provider"
            return 0
            ;;
        *)
            _llm_stream_log "error" "Invalid provider: $provider (use openai or anthropic)"
            return 1
            ;;
    esac
}

# Build OpenAI chat completion request payload
# @pre: model and messages are valid
# @post: JSON payload returned
# @idempotent: yes
# @returns: JSON request body
#
# Usage: payload=$(llm_stream_openai_payload "gpt-4" "Hello, world!")
llm_stream_openai_payload() {
    local model="${1:-gpt-4o}"
    local message="$2"
    local system="${3:-}"

    local escaped_msg
    escaped_msg=$(_llm_stream_json_escape "$message")

    local messages='[{"role":"user","content":"'"$escaped_msg"'"}]'

    if [[ -n "$system" ]]; then
        local escaped_sys
        escaped_sys=$(_llm_stream_json_escape "$system")
        messages='[{"role":"system","content":"'"$escaped_sys"'"},{"role":"user","content":"'"$escaped_msg"'"}]'
    fi

    printf '{"model":"%s","stream":true,"messages":%s}' "$model" "$messages"
}

# Build Anthropic messages request payload
# @pre: model and message are valid
# @post: JSON payload returned
# @idempotent: yes
# @returns: JSON request body
#
# Usage: payload=$(llm_stream_anthropic_payload "claude-3-opus-20240229" "Hello!")
llm_stream_anthropic_payload() {
    local model="${1:-claude-3-opus-20240229}"
    local message="$2"
    local system="${3:-}"
    local max_tokens="${4:-4096}"

    local escaped_msg
    escaped_msg=$(_llm_stream_json_escape "$message")

    local payload
    payload=$(printf '{"model":"%s","stream":true,"max_tokens":%d,"messages":[{"role":"user","content":"%s"}]' \
        "$model" "$max_tokens" "$escaped_msg")

    if [[ -n "$system" ]]; then
        local escaped_sys
        escaped_sys=$(_llm_stream_json_escape "$system")
        payload+=$(printf ',"system":"%s"' "$escaped_sys")
    fi

    payload+='}'
    printf '%s' "$payload"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

LLM_STREAM_EXPORTS=(
    # Core functions
    llm_stream_request
    llm_stream_cancel
    llm_stream_buffer_get
    llm_stream_status
    llm_stream_reset
    # Callbacks
    llm_stream_on_token
    llm_stream_on_complete
    llm_stream_on_error
    # Info functions
    llm_stream_info
    llm_stream_error
    llm_stream_token_count
    llm_stream_to_usop
    # Convenience
    llm_stream_simple
    llm_stream_sync
    # Provider helpers
    llm_stream_set_provider
    llm_stream_openai_payload
    llm_stream_anthropic_payload
)

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/scripts/api/webhook-relay.sh - Webhook Relay & Inspector
# =============================================================================
# Description: Captures incoming webhooks, logs payloads, and optionally
#              forwards them to a target URL. Acts as a webhook debugging proxy.
# Version: 1.0.0
# Requires: Bash 4.0+, socat or nc, curl (for forwarding)
# =============================================================================

set -o pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Configuration
PORT=9876
FORWARD_URL=""
LOG_DIR="/tmp/webhook-relay-$$"
MAX_LOGS=100
VERBOSE=false

usage() {
    cat <<EOF
Usage: webhook-relay.sh [options]

Capture and inspect incoming webhooks.

Options:
    -p, --port <port>      Listen port (default: 9876)
    -f, --forward <url>    Forward webhooks to URL
    -l, --log-dir <path>   Log directory (default: /tmp/webhook-relay-PID)
    --max-logs <n>         Maximum logs to keep (default: 100)
    -v, --verbose          Show full payloads in terminal
    -h, --help             Show this help
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--port)     PORT="$2"; shift 2 ;;
            -f|--forward)  FORWARD_URL="$2"; shift 2 ;;
            -l|--log-dir)  LOG_DIR="$2"; shift 2 ;;
            --max-logs)    MAX_LOGS="$2"; shift 2 ;;
            -v|--verbose)  VERBOSE=true; shift ;;
            -h|--help)     usage ;;
            *)             log_error "Unknown option: $1"; usage ;;
        esac
    done
}

# Handle incoming webhook
handle_webhook() {
    local request_line=""
    local headers=""
    local content_length=0
    local content_type=""

    # Read request line
    read -r request_line
    request_line="${request_line%%$'\r'}"

    local method path
    method=$(echo "$request_line" | awk '{print $1}')
    path=$(echo "$request_line" | awk '{print $2}')

    # Read headers
    while IFS= read -r header; do
        header="${header%%$'\r'}"
        [[ -z "$header" ]] && break
        headers+="$header"$'\n'

        local lower="${header,,}"
        if [[ "$lower" == content-length:* ]]; then
            content_length="${header#*: }"
            content_length="${content_length// /}"
        elif [[ "$lower" == content-type:* ]]; then
            content_type="${header#*: }"
        fi
    done

    # Read body
    local body=""
    if [[ $content_length -gt 0 ]]; then
        body=$(head -c "$content_length")
    fi

    # Generate timestamp and ID
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    local req_id
    req_id=$(date +%s%N | sha256sum | head -c 8)

    # Log to file
    local log_file="${LOG_DIR}/${req_id}.json"
    mkdir -p "$LOG_DIR"

    {
        echo "{"
        echo "  \"id\": \"$req_id\","
        echo "  \"timestamp\": \"$ts\","
        echo "  \"method\": \"$method\","
        echo "  \"path\": \"$path\","
        echo "  \"content_type\": \"$content_type\","
        echo "  \"content_length\": $content_length,"
        echo "  \"headers\": $(echo "$headers" | head -20 | sed 's/"/\\"/g' | awk '{printf "\"%s\", ", $0}' | sed 's/, $//' | sed 's/^/[/;s/$/]/'),"
        echo "  \"body\": $(echo "$body" | sed 's/\\/\\\\/g;s/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/^/"/;s/$/"/')"
        echo "}"
    } > "$log_file"

    # Terminal output
    log_info "[$ts] $method $path (${content_length}B) -> $req_id" >&2
    if [[ "$VERBOSE" == true && -n "$body" ]]; then
        echo "  Body: ${body:0:500}" >&2
    fi

    # Forward if configured
    if [[ -n "$FORWARD_URL" ]]; then
        local forward_status
        forward_status=$(curl -s -o /dev/null -w '%{http_code}' \
            -X "$method" \
            -H "Content-Type: $content_type" \
            -H "X-Webhook-Relay-ID: $req_id" \
            -d "$body" \
            "$FORWARD_URL" 2>/dev/null)
        log_info "  Forwarded -> $FORWARD_URL ($forward_status)" >&2
    fi

    # Cleanup old logs
    local log_count
    log_count=$(find "$LOG_DIR" -name "*.json" | wc -l)
    if [[ $log_count -gt $MAX_LOGS ]]; then
        find "$LOG_DIR" -name "*.json" -printf '%T+ %p\n' | \
            sort | head -n $((log_count - MAX_LOGS)) | \
            awk '{print $2}' | xargs rm -f
    fi

    # Send response
    printf "HTTP/1.1 200 OK\r\n"
    printf "Content-Type: application/json\r\n"
    printf "Content-Length: 32\r\n"
    printf "Connection: close\r\n"
    printf "\r\n"
    printf '{"received":true,"id":"%s"}' "$req_id"
}

cleanup() {
    log_info "Webhook relay stopped"
    log_info "Logs saved to: $LOG_DIR"
    local count
    count=$(find "$LOG_DIR" -name "*.json" 2>/dev/null | wc -l)
    log_info "Total webhooks captured: $count"
    exit 0
}

main() {
    parse_args "$@"

    mkdir -p "$LOG_DIR"

    # Check for socat
    if ! command -v socat >/dev/null 2>&1; then
        log_error "Requires socat for webhook relay"
        log_info "Install: sudo apt install socat"
        exit 1
    fi

    log_info "Webhook relay listening on port $PORT"
    log_info "Logs: $LOG_DIR"
    [[ -n "$FORWARD_URL" ]] && log_info "Forwarding to: $FORWARD_URL"
    echo ""

    trap cleanup INT TERM

    # Export functions for socat subprocess
    export -f handle_webhook log_info
    export LOG_DIR FORWARD_URL VERBOSE MAX_LOGS

    # Start server
    socat TCP-LISTEN:"$PORT",reuseaddr,fork \
        SYSTEM:"source '${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh'; LOG_DIR='$LOG_DIR'; FORWARD_URL='$FORWARD_URL'; VERBOSE=$VERBOSE; MAX_LOGS=$MAX_LOGS; handle_webhook"
}

main "$@"

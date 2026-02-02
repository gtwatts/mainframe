#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/otel.sh - OpenTelemetry-Compatible Distributed Tracing
# =============================================================================
# Description: W3C Trace Context compliant distributed tracing for bash scripts.
#              Provides span creation, context propagation, and multi-format export.
# Version: 1.0.0
# Requires: Bash 4.0+ (curl optional for export)
# Specification: https://www.w3.org/TR/trace-context/
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_OTEL_LOADED:-}" ]] && return 0
readonly _MAINFRAME_OTEL_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Service identification
OTEL_SERVICE_NAME="${OTEL_SERVICE_NAME:-mainframe}"
OTEL_SERVICE_VERSION="${OTEL_SERVICE_VERSION:-1.0.0}"

# Export endpoint (OTLP HTTP default)
OTEL_EXPORTER_ENDPOINT="${OTEL_EXPORTER_ENDPOINT:-http://localhost:4318}"

# Tracing control
OTEL_TRACING_ENABLED="${OTEL_TRACING_ENABLED:-1}"

# Sampling rate (0.0 to 1.0, default 100%)
OTEL_SAMPLE_RATE="${OTEL_SAMPLE_RATE:-1.0}"

# Batch export settings
OTEL_BATCH_SIZE="${OTEL_BATCH_SIZE:-100}"
OTEL_BATCH_TIMEOUT="${OTEL_BATCH_TIMEOUT:-5}"

# File export path (for file exporter)
OTEL_EXPORT_FILE="${OTEL_EXPORT_FILE:-}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Span storage directory (file-based for multi-process safety)
_OTEL_SPAN_DIR="${OTEL_SPAN_DIR:-${TMPDIR:-/tmp}/mainframe_otel_$$}"

# Span stack for nested operations (array of span_ids)
declare -ga _OTEL_SPAN_STACK=()

# Current trace context
declare -gA _OTEL_CTX=(
    [trace_id]=""
    [span_id]=""
    [parent_span_id]=""
    [flags]="01"
    [tracestate]=""
)

# Initialization flag
_OTEL_INITIALIZED=0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Generate 32-character hex trace ID (128 bits)
_otel_gen_trace_id() {
    if [[ -r /dev/urandom ]]; then
        head -c 16 /dev/urandom 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n'
    else
        # Fallback using RANDOM and timestamp
        printf '%08x%08x%08x%08x' "$RANDOM" "$$" "$RANDOM" "$(date +%s 2>/dev/null || echo $RANDOM)"
    fi
}

# Generate 16-character hex span ID (64 bits)
_otel_gen_span_id() {
    if [[ -r /dev/urandom ]]; then
        head -c 8 /dev/urandom 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n'
    else
        printf '%08x%08x' "$RANDOM" "$$"
    fi
}

# Get current time in nanoseconds (Unix epoch)
_otel_now_nanos() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        # Bash 5.0+ EPOCHREALTIME: seconds.microseconds
        local secs="${EPOCHREALTIME%%.*}"
        local frac="${EPOCHREALTIME#*.}000000000"
        printf '%s%s' "$secs" "${frac:0:9}"
    elif date +%s%N &>/dev/null; then
        date +%s%N
    else
        # Fallback: seconds with 9 zeros
        printf '%s000000000' "$(date +%s)"
    fi
}

# JSON-escape a string
_otel_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Check if tracing is enabled and should sample
_otel_should_trace() {
    [[ "$OTEL_TRACING_ENABLED" != "1" ]] && return 1

    # Sampling check
    if [[ "$OTEL_SAMPLE_RATE" != "1.0" && "$OTEL_SAMPLE_RATE" != "1" ]]; then
        local rand=$((RANDOM % 100))
        local threshold
        # Simple integer comparison (multiply by 100)
        threshold=$(printf '%.0f' "$(echo "${OTEL_SAMPLE_RATE} * 100" | bc 2>/dev/null || echo 100)")
        [[ $rand -ge $threshold ]] && return 1
    fi

    return 0
}

# Internal logging
_otel_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "otel" "$level" "$*"
    elif [[ "${OTEL_DEBUG:-0}" == "1" ]]; then
        printf '[otel] %s: %s\n' "$level" "$*" >&2
    fi
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize the OpenTelemetry tracer
# Usage: otel_init --service "my-service" --endpoint "http://localhost:4318"
# Options:
#   --service NAME     Service name for traces (default: mainframe)
#   --endpoint URL     OTLP HTTP endpoint (default: http://localhost:4318)
#   --sample-rate N    Sampling rate 0.0-1.0 (default: 1.0)
otel_init() {
    local service=""
    local endpoint=""
    local sample_rate=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --service)
                service="$2"
                shift 2
                ;;
            --endpoint)
                endpoint="$2"
                shift 2
                ;;
            --sample-rate)
                sample_rate="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Apply configuration
    [[ -n "$service" ]] && OTEL_SERVICE_NAME="$service"
    [[ -n "$endpoint" ]] && OTEL_EXPORTER_ENDPOINT="$endpoint"
    [[ -n "$sample_rate" ]] && OTEL_SAMPLE_RATE="$sample_rate"

    # Create span storage directory
    mkdir -p "$_OTEL_SPAN_DIR" 2>/dev/null

    # Register cleanup handler
    if [[ -z "${_OTEL_CLEANUP_REGISTERED:-}" ]]; then
        trap 'otel_flush 2>/dev/null' EXIT
        _OTEL_CLEANUP_REGISTERED=1
    fi

    _OTEL_INITIALIZED=1
    _otel_log "info" "Initialized: service=$OTEL_SERVICE_NAME endpoint=$OTEL_EXPORTER_ENDPOINT"

    return 0
}

# =============================================================================
# TRACE OPERATIONS
# =============================================================================

# Start a new trace/span
# Usage: otel_trace_start "operation_name"
# Returns: Prints span_id to stdout
otel_trace_start() {
    local name="${1:-operation}"

    _otel_should_trace || { printf ''; return 0; }

    # Auto-initialize if needed
    [[ "$_OTEL_INITIALIZED" != "1" ]] && otel_init

    local trace_id span_id parent_span_id=""
    local start_time

    # Check if we're in an existing trace
    if [[ -n "${_OTEL_CTX[trace_id]}" ]]; then
        # Continue existing trace
        trace_id="${_OTEL_CTX[trace_id]}"
        parent_span_id="${_OTEL_CTX[span_id]}"
    else
        # New trace
        trace_id=$(_otel_gen_trace_id)
    fi

    span_id=$(_otel_gen_span_id)
    start_time=$(_otel_now_nanos)

    # Push current span to stack
    if [[ -n "${_OTEL_CTX[span_id]}" ]]; then
        _OTEL_SPAN_STACK+=("${_OTEL_CTX[span_id]}")
    fi

    # Update context
    _OTEL_CTX[trace_id]="$trace_id"
    _OTEL_CTX[span_id]="$span_id"
    _OTEL_CTX[parent_span_id]="$parent_span_id"

    # Create span file
    local span_file="$_OTEL_SPAN_DIR/${trace_id}_${span_id}.span"
    cat > "$span_file" << EOF
{
  "traceId": "$trace_id",
  "spanId": "$span_id",
  "parentSpanId": "$parent_span_id",
  "name": "$(_otel_json_escape "$name")",
  "kind": 1,
  "startTimeUnixNano": "$start_time",
  "endTimeUnixNano": "",
  "attributes": [],
  "events": [],
  "status": {"code": 0}
}
EOF

    printf '%s' "$span_id"
}

# End the current span
# Usage: otel_trace_end
otel_trace_end() {
    local trace_id="${_OTEL_CTX[trace_id]}"
    local span_id="${_OTEL_CTX[span_id]}"

    [[ -z "$span_id" ]] && return 0

    local span_file="$_OTEL_SPAN_DIR/${trace_id}_${span_id}.span"

    if [[ -f "$span_file" ]]; then
        local end_time
        end_time=$(_otel_now_nanos)

        # Read current span and add end time
        local span_json
        span_json=$(<"$span_file")

        # Update endTimeUnixNano
        span_json="${span_json/\"endTimeUnixNano\": \"\"/\"endTimeUnixNano\": \"$end_time\"}"

        printf '%s' "$span_json" > "$span_file"
    fi

    # Pop from stack
    if [[ ${#_OTEL_SPAN_STACK[@]} -gt 0 ]]; then
        local parent_span_id="${_OTEL_SPAN_STACK[-1]}"
        unset '_OTEL_SPAN_STACK[-1]'
        _OTEL_CTX[span_id]="$parent_span_id"

        # Find parent's parent from its span file
        local parent_file
        parent_file=$(find "$_OTEL_SPAN_DIR" -name "${trace_id}_${parent_span_id}.span" 2>/dev/null | head -1)
        if [[ -f "$parent_file" ]]; then
            local parent_parent
            parent_parent=$(grep -oP '"parentSpanId"\s*:\s*"\K[^"]*' "$parent_file" 2>/dev/null || echo "")
            _OTEL_CTX[parent_span_id]="$parent_parent"
        fi
    else
        # No more spans in stack, clear context
        _OTEL_CTX[trace_id]=""
        _OTEL_CTX[span_id]=""
        _OTEL_CTX[parent_span_id]=""
    fi

    return 0
}

# =============================================================================
# SPAN ATTRIBUTES AND EVENTS
# =============================================================================

# Add an event to the current span
# Usage: otel_trace_add_event "event_name" key="value" key2="value2"
otel_trace_add_event() {
    local event_name="$1"
    shift

    local trace_id="${_OTEL_CTX[trace_id]}"
    local span_id="${_OTEL_CTX[span_id]}"

    [[ -z "$span_id" ]] && return 1

    local span_file="$_OTEL_SPAN_DIR/${trace_id}_${span_id}.span"
    [[ ! -f "$span_file" ]] && return 1

    local event_time
    event_time=$(_otel_now_nanos)

    # Build attributes array from key=value pairs
    local attrs=""
    local first=true
    for pair in "$@"; do
        if [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            $first || attrs+=","
            first=false
            attrs+="{\"key\": \"$(_otel_json_escape "$key")\", \"value\": {\"stringValue\": \"$(_otel_json_escape "$value")\"}}"
        fi
    done

    local event_json
    event_json="{\"timeUnixNano\": \"$event_time\", \"name\": \"$(_otel_json_escape "$event_name")\", \"attributes\": [$attrs]}"

    # Read span and append event
    local span_json
    span_json=$(<"$span_file")

    # Append to events array
    if [[ "$span_json" =~ \"events\":[[:space:]]*\[\] ]]; then
        span_json="${span_json/\"events\": \[\]/\"events\": [$event_json]}"
    else
        span_json="${span_json/\"events\": \[/\"events\": [$event_json, }"
    fi

    printf '%s' "$span_json" > "$span_file"

    return 0
}

# Set an attribute on the current span
# Usage: otel_trace_set_attribute "key" "value"
otel_trace_set_attribute() {
    local key="$1"
    local value="$2"

    local trace_id="${_OTEL_CTX[trace_id]}"
    local span_id="${_OTEL_CTX[span_id]}"

    [[ -z "$span_id" || -z "$key" ]] && return 1

    local span_file="$_OTEL_SPAN_DIR/${trace_id}_${span_id}.span"
    [[ ! -f "$span_file" ]] && return 1

    # Determine value type and format
    local attr_json
    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
        attr_json="{\"key\": \"$(_otel_json_escape "$key")\", \"value\": {\"intValue\": $value}}"
    elif [[ "$value" =~ ^-?[0-9]+\.[0-9]+$ ]]; then
        attr_json="{\"key\": \"$(_otel_json_escape "$key")\", \"value\": {\"doubleValue\": $value}}"
    elif [[ "$value" == "true" || "$value" == "false" ]]; then
        attr_json="{\"key\": \"$(_otel_json_escape "$key")\", \"value\": {\"boolValue\": $value}}"
    else
        attr_json="{\"key\": \"$(_otel_json_escape "$key")\", \"value\": {\"stringValue\": \"$(_otel_json_escape "$value")\"}}"
    fi

    # Read span and append attribute
    local span_json
    span_json=$(<"$span_file")

    # Append to attributes array
    if [[ "$span_json" =~ \"attributes\":[[:space:]]*\[\] ]]; then
        span_json="${span_json/\"attributes\": \[\]/\"attributes\": [$attr_json]}"
    else
        span_json="${span_json/\"attributes\": \[/\"attributes\": [$attr_json, }"
    fi

    printf '%s' "$span_json" > "$span_file"

    return 0
}

# Set span status
# Usage: otel_trace_set_status "OK|ERROR" "description"
otel_trace_set_status() {
    local status="$1"
    local description="${2:-}"

    local trace_id="${_OTEL_CTX[trace_id]}"
    local span_id="${_OTEL_CTX[span_id]}"

    [[ -z "$span_id" ]] && return 1

    local span_file="$_OTEL_SPAN_DIR/${trace_id}_${span_id}.span"
    [[ ! -f "$span_file" ]] && return 1

    # Map status to OTLP code
    local status_code
    case "${status^^}" in
        OK)    status_code=1 ;;
        ERROR) status_code=2 ;;
        *)     status_code=0 ;;  # UNSET
    esac

    # Read span and update status
    local span_json
    span_json=$(<"$span_file")

    local new_status
    if [[ -n "$description" ]]; then
        new_status="{\"code\": $status_code, \"message\": \"$(_otel_json_escape "$description")\"}"
    else
        new_status="{\"code\": $status_code}"
    fi

    # Replace status object
    span_json=$(printf '%s' "$span_json" | sed -E "s/\"status\":[[:space:]]*\{[^}]*\}/\"status\": $new_status/")

    printf '%s' "$span_json" > "$span_file"

    return 0
}

# =============================================================================
# CONTEXT ACCESS
# =============================================================================

# Get current trace ID
# Usage: trace_id=$(otel_trace_id)
otel_trace_id() {
    printf '%s' "${_OTEL_CTX[trace_id]}"
}

# Get current span ID
# Usage: span_id=$(otel_span_id)
otel_span_id() {
    printf '%s' "${_OTEL_CTX[span_id]}"
}

# =============================================================================
# W3C TRACE CONTEXT PROPAGATION
# =============================================================================

# Get headers for context propagation (W3C format)
# Usage: headers=$(otel_inject_headers)
# Returns: traceparent and tracestate headers
otel_inject_headers() {
    local trace_id="${_OTEL_CTX[trace_id]}"
    local span_id="${_OTEL_CTX[span_id]}"
    local flags="${_OTEL_CTX[flags]:-01}"

    [[ -z "$trace_id" || -z "$span_id" ]] && return 1

    # W3C traceparent format: version-trace_id-span_id-flags
    printf 'traceparent: 00-%s-%s-%s\n' "$trace_id" "$span_id" "$flags"

    # tracestate (optional vendor-specific data)
    local tracestate="${_OTEL_CTX[tracestate]:-}"
    if [[ -n "$tracestate" ]]; then
        printf 'tracestate: %s\n' "$tracestate"
    else
        printf 'tracestate: mainframe=%s\n' "${OTEL_SERVICE_NAME}"
    fi
}

# Extract context from incoming headers
# Usage: otel_extract_headers "00-traceid-spanid-01" "key=value"
otel_extract_headers() {
    local traceparent="$1"
    local tracestate="${2:-}"

    # Parse W3C traceparent
    # Format: version-trace_id-parent_span_id-flags
    if [[ "$traceparent" =~ ^([0-9a-fA-F]{2})-([0-9a-fA-F]{32})-([0-9a-fA-F]{16})-([0-9a-fA-F]{2})$ ]]; then
        local version="${BASH_REMATCH[1]}"
        local trace_id="${BASH_REMATCH[2]}"
        local parent_span_id="${BASH_REMATCH[3]}"
        local flags="${BASH_REMATCH[4]}"

        # Only support version 00
        [[ "$version" != "00" ]] && return 1

        # Validate not all zeros
        [[ "$trace_id" =~ ^0+$ ]] && return 1
        [[ "$parent_span_id" =~ ^0+$ ]] && return 1

        # Update context
        _OTEL_CTX[trace_id]="$trace_id"
        _OTEL_CTX[parent_span_id]="$parent_span_id"
        _OTEL_CTX[flags]="$flags"
        _OTEL_CTX[tracestate]="$tracestate"

        # Generate new span ID for this service
        _OTEL_CTX[span_id]=$(_otel_gen_span_id)

        return 0
    fi

    return 1
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export spans to specified format
# Usage: otel_export "jaeger|zipkin|otlp|file"
otel_export() {
    local format="${1:-otlp}"

    case "$format" in
        otlp)
            _otel_export_otlp
            ;;
        jaeger)
            _otel_export_jaeger
            ;;
        zipkin)
            _otel_export_zipkin
            ;;
        file)
            _otel_export_file
            ;;
        console)
            _otel_export_console
            ;;
        *)
            _otel_log "error" "Unknown export format: $format"
            return 1
            ;;
    esac
}

# Export to OTLP HTTP endpoint
_otel_export_otlp() {
    local endpoint="${OTEL_EXPORTER_ENDPOINT}/v1/traces"

    # Collect completed spans
    local spans=""
    local first=true

    # Use nullglob for safe globbing
    local old_nullglob
    old_nullglob=$(shopt -p nullglob 2>/dev/null || echo "shopt -u nullglob")
    shopt -s nullglob

    for span_file in "$_OTEL_SPAN_DIR"/*.span; do
        [[ -f "$span_file" ]] || continue

        # Only export completed spans
        if grep -q '"endTimeUnixNano": "[0-9]' "$span_file" 2>/dev/null; then
            local span_json
            span_json=$(<"$span_file")

            $first || spans+=","
            first=false
            spans+="$span_json"
        fi
    done

    eval "$old_nullglob"

    [[ -z "$spans" ]] && return 0

    # Build OTLP request
    local body
    body=$(cat << EOF
{
  "resourceSpans": [{
    "resource": {
      "attributes": [
        {"key": "service.name", "value": {"stringValue": "$OTEL_SERVICE_NAME"}},
        {"key": "service.version", "value": {"stringValue": "$OTEL_SERVICE_VERSION"}},
        {"key": "telemetry.sdk.name", "value": {"stringValue": "mainframe-otel"}},
        {"key": "telemetry.sdk.language", "value": {"stringValue": "bash"}}
      ]
    },
    "scopeSpans": [{
      "scope": {
        "name": "mainframe.otel",
        "version": "1.0.0"
      },
      "spans": [$spans]
    }]
  }]
}
EOF
)

    # Send via curl if available
    if command -v curl &>/dev/null; then
        if curl -sf -X POST "$endpoint" \
            -H "Content-Type: application/json" \
            -d "$body" &>/dev/null; then
            _otel_cleanup_exported
            _otel_log "info" "Exported spans to OTLP endpoint"
            return 0
        else
            _otel_log "warn" "Failed to export to OTLP endpoint: $endpoint"
            return 1
        fi
    fi

    # Fallback: /dev/tcp for HTTP only
    if [[ "$endpoint" =~ ^http://([^/:]+):?([0-9]*)(/.*)$ ]]; then
        local host="${BASH_REMATCH[1]}"
        local port="${BASH_REMATCH[2]:-80}"
        local path="${BASH_REMATCH[3]}"

        local content_length=${#body}
        local request
        request="POST $path HTTP/1.1\r\n"
        request+="Host: $host\r\n"
        request+="Content-Type: application/json\r\n"
        request+="Content-Length: $content_length\r\n"
        request+="Connection: close\r\n"
        request+="\r\n"
        request+="$body"

        if exec 3<>"/dev/tcp/$host/$port" 2>/dev/null; then
            printf '%b' "$request" >&3
            local response
            response=$(cat <&3)
            exec 3>&-

            if [[ "$response" =~ HTTP/[0-9.]+[[:space:]]2[0-9]{2} ]]; then
                _otel_cleanup_exported
                return 0
            fi
        fi
    fi

    _otel_log "warn" "Failed to export spans"
    return 1
}

# Export to Jaeger endpoint
_otel_export_jaeger() {
    local endpoint="${OTEL_EXPORTER_ENDPOINT}/api/traces"

    # Jaeger uses Thrift format by default, but also supports OTLP
    # For simplicity, we use OTLP-compatible JSON
    _otel_export_otlp
}

# Export to Zipkin endpoint
_otel_export_zipkin() {
    local endpoint="${OTEL_EXPORTER_ENDPOINT}/api/v2/spans"

    # Collect and convert spans to Zipkin format
    local spans=""
    local first=true

    shopt -s nullglob
    for span_file in "$_OTEL_SPAN_DIR"/*.span; do
        [[ -f "$span_file" ]] || continue

        if grep -q '"endTimeUnixNano": "[0-9]' "$span_file" 2>/dev/null; then
            local span_json
            span_json=$(<"$span_file")

            # Extract values for Zipkin format
            local trace_id span_id parent_id name start_ns end_ns
            trace_id=$(printf '%s' "$span_json" | grep -oP '"traceId"\s*:\s*"\K[^"]*' || echo "")
            span_id=$(printf '%s' "$span_json" | grep -oP '"spanId"\s*:\s*"\K[^"]*' || echo "")
            parent_id=$(printf '%s' "$span_json" | grep -oP '"parentSpanId"\s*:\s*"\K[^"]*' || echo "")
            name=$(printf '%s' "$span_json" | grep -oP '"name"\s*:\s*"\K[^"]*' || echo "")
            start_ns=$(printf '%s' "$span_json" | grep -oP '"startTimeUnixNano"\s*:\s*"\K[^"]*' || echo "0")
            end_ns=$(printf '%s' "$span_json" | grep -oP '"endTimeUnixNano"\s*:\s*"\K[^"]*' || echo "0")

            # Convert nanoseconds to microseconds for Zipkin
            local start_us=$((start_ns / 1000))
            local duration_us=$(( (end_ns - start_ns) / 1000 ))

            $first || spans+=","
            first=false

            local zipkin_span
            zipkin_span="{\"traceId\": \"$trace_id\", \"id\": \"$span_id\""
            [[ -n "$parent_id" ]] && zipkin_span+=", \"parentId\": \"$parent_id\""
            zipkin_span+=", \"name\": \"$name\""
            zipkin_span+=", \"timestamp\": $start_us"
            zipkin_span+=", \"duration\": $duration_us"
            zipkin_span+=", \"localEndpoint\": {\"serviceName\": \"$OTEL_SERVICE_NAME\"}"
            zipkin_span+="}"

            spans+="$zipkin_span"
        fi
    done
    shopt -u nullglob

    [[ -z "$spans" ]] && return 0

    local body="[$spans]"

    if command -v curl &>/dev/null; then
        if curl -sf -X POST "$endpoint" \
            -H "Content-Type: application/json" \
            -d "$body" &>/dev/null; then
            _otel_cleanup_exported
            return 0
        fi
    fi

    return 1
}

# Export to JSONL file
_otel_export_file() {
    local output_file="${OTEL_EXPORT_FILE:-/tmp/traces.jsonl}"

    shopt -s nullglob
    for span_file in "$_OTEL_SPAN_DIR"/*.span; do
        [[ -f "$span_file" ]] || continue

        if grep -q '"endTimeUnixNano": "[0-9]' "$span_file" 2>/dev/null; then
            local span_json
            span_json=$(<"$span_file")
            # Write as single line
            printf '%s\n' "$(printf '%s' "$span_json" | tr -d '\n' | tr -s ' ')" >> "$output_file"
            rm -f "$span_file"
        fi
    done
    shopt -u nullglob

    _otel_log "info" "Exported spans to $output_file"
    return 0
}

# Export to console (for debugging)
_otel_export_console() {
    shopt -s nullglob
    for span_file in "$_OTEL_SPAN_DIR"/*.span; do
        [[ -f "$span_file" ]] || continue

        local span_json
        span_json=$(<"$span_file")
        printf '[OTEL SPAN] %s\n' "$(printf '%s' "$span_json" | tr -d '\n' | tr -s ' ')" >&2
    done
    shopt -u nullglob

    return 0
}

# Clean up exported span files
_otel_cleanup_exported() {
    shopt -s nullglob
    for span_file in "$_OTEL_SPAN_DIR"/*.span; do
        [[ -f "$span_file" ]] || continue

        if grep -q '"endTimeUnixNano": "[0-9]' "$span_file" 2>/dev/null; then
            rm -f "$span_file"
        fi
    done
    shopt -u nullglob
}

# Flush all pending spans
# Usage: otel_flush
otel_flush() {
    # End any unclosed spans
    while [[ -n "${_OTEL_CTX[span_id]}" ]]; do
        otel_trace_set_status "ERROR" "Span not properly closed"
        otel_trace_end
    done

    # Export remaining spans
    otel_export "${OTEL_EXPORT_FORMAT:-otlp}" 2>/dev/null || true

    return 0
}

# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

# Auto-instrument a function/command
# Usage: otel_instrument "function_name" args...
otel_instrument() {
    local func_name="$1"
    shift

    local span_id exit_code
    span_id=$(otel_trace_start "$func_name")

    # Execute
    "$func_name" "$@"
    exit_code=$?

    # Set status based on exit code
    if [[ $exit_code -eq 0 ]]; then
        otel_trace_set_status "OK"
    else
        otel_trace_set_status "ERROR" "Exit code: $exit_code"
    fi

    otel_trace_end

    return $exit_code
}

# Time a command with automatic span
# Usage: otel_timed "span_name" command args...
otel_timed() {
    local span_name="$1"
    shift

    local span_id
    span_id=$(otel_trace_start "$span_name")

    otel_trace_set_attribute "command" "$*"

    # Execute command
    "$@"
    local exit_code=$?

    otel_trace_set_attribute "exit_code" "$exit_code"

    if [[ $exit_code -eq 0 ]]; then
        otel_trace_set_status "OK"
    else
        otel_trace_set_status "ERROR" "Command failed with exit code $exit_code"
    fi

    otel_trace_end

    return $exit_code
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

OTEL_EXPORTS=(
    # Initialization
    otel_init
    # Trace operations
    otel_trace_start
    otel_trace_end
    otel_trace_add_event
    otel_trace_set_attribute
    otel_trace_set_status
    # Context access
    otel_trace_id
    otel_span_id
    # Propagation
    otel_inject_headers
    otel_extract_headers
    # Export
    otel_export
    otel_flush
    # Convenience
    otel_instrument
    otel_timed
)

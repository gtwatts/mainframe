#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/metrics.sh - Prometheus-Compatible Metrics Library
# =============================================================================
# Description: Pure bash implementation of Prometheus-style metrics including
#              counters, gauges, histograms, and summaries with label support.
#              Exports to Prometheus text exposition format, JSON, and OpenMetrics.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_METRICS_LOADED:-}" ]] && return 0
readonly _MAINFRAME_METRICS_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Enable/disable metrics collection (disable for performance in production)
MAINFRAME_METRICS_ENABLED="${MAINFRAME_METRICS_ENABLED:-1}"

# Default histogram buckets (Prometheus defaults)
MAINFRAME_HISTOGRAM_BUCKETS="${MAINFRAME_HISTOGRAM_BUCKETS:-.005 .01 .025 .05 .1 .25 .5 1 2.5 5 10}"

# Summary quantiles (default: 50th, 90th, 99th percentiles)
MAINFRAME_SUMMARY_QUANTILES="${MAINFRAME_SUMMARY_QUANTILES:-.5 .9 .99}"

# Summary max age in seconds (for sliding window)
MAINFRAME_SUMMARY_MAX_AGE="${MAINFRAME_SUMMARY_MAX_AGE:-600}"

# HTTP server port for metrics_serve
MAINFRAME_METRICS_PORT="${MAINFRAME_METRICS_PORT:-9091}"

# =============================================================================
# INTERNAL STATE - Associative Arrays for Metric Storage
# =============================================================================

# Metric registry: name -> type (counter|gauge|histogram|summary)
declare -gA _METRICS_REGISTRY

# Metric help text: name -> description
declare -gA _METRICS_HELP

# Counter values: name{labels} -> value
declare -gA _METRICS_COUNTERS

# Gauge values: name{labels} -> value
declare -gA _METRICS_GAUGES

# Histogram bucket counts: name{labels}_bucket{le="X"} -> count
declare -gA _METRICS_HIST_BUCKETS

# Histogram sums: name{labels} -> sum
declare -gA _METRICS_HIST_SUMS

# Histogram counts: name{labels} -> count
declare -gA _METRICS_HIST_COUNTS

# Histogram bucket definitions: name -> "0.1 0.5 1 5 10"
declare -gA _METRICS_HIST_BUCKET_DEFS

# Summary observations: name{labels} -> "ts1:val1 ts2:val2 ..."
declare -gA _METRICS_SUMMARY_OBS

# Summary sums: name{labels} -> sum
declare -gA _METRICS_SUMMARY_SUMS

# Summary counts: name{labels} -> count
declare -gA _METRICS_SUMMARY_COUNTS

# Timer state: timer_id -> "start_time:metric_name:labels"
declare -gA _METRICS_TIMERS

# Timer counter for unique IDs
_METRICS_TIMER_COUNTER=0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# JSON-escape a string
_metrics_escape_json() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Escape label value for Prometheus format
_metrics_escape_label() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    printf '%s' "$str"
}

# Get current timestamp in milliseconds
_metrics_timestamp_ms() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        local ts="$EPOCHREALTIME"
        local secs="${ts%%.*}"
        local frac="${ts#*.}"
        frac="${frac}000"
        printf '%s%s' "$secs" "${frac:0:3}"
    elif date +%s%3N &>/dev/null 2>&1; then
        date +%s%3N
    else
        printf '%s000' "$(date +%s)"
    fi
}

# Get current timestamp in seconds with microseconds
_metrics_now() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        printf '%s' "$EPOCHREALTIME"
    elif [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s.000000' "$EPOCHSECONDS"
    else
        date +%s.%N 2>/dev/null || date +%s
    fi
}

_metrics_number_valid() {
    local value="$1"
    [[ "$value" =~ ^-?([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]]
}

_metrics_normalize_number() {
    local value="${1:-0}"

    if [[ "$value" == .* ]]; then
        value="0${value}"
    elif [[ "$value" == -.* ]]; then
        value="-0${value#-}"
    fi

    if [[ "$value" == *.* ]]; then
        while [[ "$value" == *0 ]]; do
            value="${value%0}"
        done
        value="${value%.}"
    fi

    [[ -z "$value" || "$value" == "-" ]] && value="0"
    printf '%s' "$value"
}

_metrics_add_numbers() {
    local left
    local right
    left=$(_metrics_normalize_number "${1:-0}")
    right=$(_metrics_normalize_number "${2:-0}")

    if [[ "$left" == *"."* ]] || [[ "$right" == *"."* ]]; then
        if command -v bc &>/dev/null; then
            _metrics_normalize_number "$(echo "$left + $right" | bc)"
        else
            _metrics_normalize_number "$(awk -v a="$left" -v b="$right" 'BEGIN { printf "%.12f", a + b }')"
        fi
        return 0
    fi

    printf '%s' "$((left + right))"
}

_metrics_subtract_numbers() {
    local left
    local right
    left=$(_metrics_normalize_number "${1:-0}")
    right=$(_metrics_normalize_number "${2:-0}")

    if [[ "$left" == *"."* ]] || [[ "$right" == *"."* ]]; then
        if command -v bc &>/dev/null; then
            _metrics_normalize_number "$(echo "$left - $right" | bc)"
        else
            _metrics_normalize_number "$(awk -v a="$left" -v b="$right" 'BEGIN { printf "%.12f", a - b }')"
        fi
        return 0
    fi

    printf '%s' "$((left - right))"
}

# Validate metric name (Prometheus format: [a-zA-Z_:][a-zA-Z0-9_:]*)
# @pre: name is non-empty string
# @post: returns 0 if valid, 1 if invalid
# @idempotent: yes
# @returns: 0 on valid, 1 on invalid
metric_name_valid() {
    local name="$1"

    [[ -z "$name" ]] && return 1

    # Must start with letter, underscore, or colon
    if [[ ! "$name" =~ ^[a-zA-Z_:] ]]; then
        return 1
    fi

    # Must only contain letters, numbers, underscores, colons
    if [[ ! "$name" =~ ^[a-zA-Z_:][a-zA-Z0-9_:]*$ ]]; then
        return 1
    fi

    return 0
}

# Validate label name (Prometheus format: [a-zA-Z_][a-zA-Z0-9_]*)
_metrics_label_name_valid() {
    local name="$1"

    [[ -z "$name" ]] && return 1

    # Must start with letter or underscore
    if [[ ! "$name" =~ ^[a-zA-Z_] ]]; then
        return 1
    fi

    # Must only contain letters, numbers, underscores
    if [[ ! "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        return 1
    fi

    # Reserved labels start with __
    if [[ "$name" == __* ]]; then
        return 1
    fi

    return 0
}

# Format labels string from key=value pairs
# @pre: pairs in format key=value or key="value"
# @post: returns formatted labels string {key="value",key2="value2"}
# @idempotent: yes
# @returns: 0, prints labels string to stdout
metric_labels_format() {
    local result="{"
    local first=true

    for pair in "$@"; do
        local key="${pair%%=*}"
        local value="${pair#*=}"

        # Remove quotes if present
        value="${value#\"}"
        value="${value%\"}"

        _metrics_label_name_valid "$key" || continue

        $first || result+=","
        first=false

        result+="$key=\"$(_metrics_escape_label "$value")\""
    done

    result+="}"

    # Return empty string if no labels
    [[ "$result" == "{}" ]] && result=""

    printf '%s' "$result"
}

# Parse labels from string format {key="value",...} to pairs
_metrics_labels_parse() {
    local labels="$1"

    # Remove braces
    labels="${labels#\{}"
    labels="${labels%\}}"

    [[ -z "$labels" ]] && return 0

    # Simple parsing - split on comma, handle quotes
    echo "$labels" | tr ',' '\n' | while read -r pair; do
        [[ -n "$pair" ]] && echo "$pair"
    done
}

# Construct full metric key with labels
_metrics_key() {
    local name="$1"
    local labels="${2:-}"

    if [[ -n "$labels" ]]; then
        printf '%s%s' "$name" "$labels"
    else
        printf '%s' "$name"
    fi
}

# =============================================================================
# METRIC REGISTRATION
# =============================================================================

# @pre: name is valid metric name, type is counter|gauge|histogram|summary
# @post: metric registered in registry
# @idempotent: yes - re-registration with same type is no-op
# @returns: 0 on success, 1 on invalid name or type mismatch
#
# Register a metric with the registry. All metrics must be registered before use.
# Re-registering with the same type is allowed, different type raises error.
#
# Usage: metrics_register "http_requests_total" "counter" "Total HTTP requests"
metrics_register() {
    local name="$1"
    local type="$2"
    local help="${3:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    # Validate name
    if ! metric_name_valid "$name"; then
        printf '{"error":true,"msg":"invalid metric name","name":"%s"}\n' \
            "$(_metrics_escape_json "$name")" >&2
        return 1
    fi

    # Validate type
    case "$type" in
        counter|gauge|histogram|summary) ;;
        *)
            printf '{"error":true,"msg":"invalid metric type","type":"%s"}\n' \
                "$(_metrics_escape_json "$type")" >&2
            return 1
            ;;
    esac

    # Check for type conflict
    if [[ -n "${_METRICS_REGISTRY[$name]:-}" ]]; then
        if [[ "${_METRICS_REGISTRY[$name]}" != "$type" ]]; then
            printf '{"error":true,"msg":"metric type mismatch","name":"%s","existing":"%s","requested":"%s"}\n' \
                "$name" "${_METRICS_REGISTRY[$name]}" "$type" >&2
            return 1
        fi
        # Already registered with same type
        return 0
    fi

    _METRICS_REGISTRY[$name]="$type"
    [[ -n "$help" ]] && _METRICS_HELP[$name]="$help"

    return 0
}

# @pre: name is registered metric
# @post: metric removed from registry and all values cleared
# @idempotent: yes
# @returns: 0
#
# Unregister a metric and remove all its data.
#
# Usage: metrics_unregister "http_requests_total"
metrics_unregister() {
    local name="$1"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    unset "_METRICS_REGISTRY[$name]"
    unset "_METRICS_HELP[$name]"

    # Clear all values for this metric (with any labels)
    local key
    for key in "${!_METRICS_COUNTERS[@]}"; do
        [[ "$key" == "$name"* ]] && unset "_METRICS_COUNTERS[$key]"
    done
    for key in "${!_METRICS_GAUGES[@]}"; do
        [[ "$key" == "$name"* ]] && unset "_METRICS_GAUGES[$key]"
    done
    for key in "${!_METRICS_HIST_BUCKETS[@]}"; do
        [[ "$key" == "$name"* ]] && unset "_METRICS_HIST_BUCKETS[$key]"
    done
    for key in "${!_METRICS_HIST_SUMS[@]}"; do
        [[ "$key" == "$name"* ]] && unset "_METRICS_HIST_SUMS[$key]"
    done
    for key in "${!_METRICS_HIST_COUNTS[@]}"; do
        [[ "$key" == "$name"* ]] && unset "_METRICS_HIST_COUNTS[$key]"
    done
    unset "_METRICS_HIST_BUCKET_DEFS[$name]"
    for key in "${!_METRICS_SUMMARY_OBS[@]}"; do
        [[ "$key" == "$name"* ]] && unset "_METRICS_SUMMARY_OBS[$key]"
    done
    for key in "${!_METRICS_SUMMARY_SUMS[@]}"; do
        [[ "$key" == "$name"* ]] && unset "_METRICS_SUMMARY_SUMS[$key]"
    done
    for key in "${!_METRICS_SUMMARY_COUNTS[@]}"; do
        [[ "$key" == "$name"* ]] && unset "_METRICS_SUMMARY_COUNTS[$key]"
    done

    return 0
}

# @pre: none
# @post: prints list of registered metrics
# @idempotent: yes
# @returns: 0, prints JSON array of metric names
#
# List all registered metrics.
#
# Usage: metrics_list
metrics_list() {
    local first=true
    printf '['

    for name in "${!_METRICS_REGISTRY[@]}"; do
        $first || printf ','
        first=false
        printf '{"name":"%s","type":"%s"' "$name" "${_METRICS_REGISTRY[$name]}"
        [[ -n "${_METRICS_HELP[$name]:-}" ]] && printf ',"help":"%s"' "$(_metrics_escape_json "${_METRICS_HELP[$name]}")"
        printf '}'
    done

    printf ']'
}

# @pre: name is non-empty
# @post: returns metric info if found
# @idempotent: yes
# @returns: 0 if found, 1 if not found
#
# Get a metric's type and help by name.
#
# Usage: metrics_get "http_requests_total"
metrics_get() {
    local name="$1"

    if [[ -z "${_METRICS_REGISTRY[$name]:-}" ]]; then
        printf '{"error":true,"msg":"metric not found","name":"%s"}\n' "$name" >&2
        return 1
    fi

    printf '{"name":"%s","type":"%s"' "$name" "${_METRICS_REGISTRY[$name]}"
    [[ -n "${_METRICS_HELP[$name]:-}" ]] && printf ',"help":"%s"' "$(_metrics_escape_json "${_METRICS_HELP[$name]}")"
    printf '}'

    return 0
}

# @pre: none
# @post: all metrics cleared
# @idempotent: yes
# @returns: 0
#
# Clear all registered metrics and their values.
#
# Usage: metrics_clear
metrics_clear() {
    _METRICS_REGISTRY=()
    _METRICS_HELP=()
    _METRICS_COUNTERS=()
    _METRICS_GAUGES=()
    _METRICS_HIST_BUCKETS=()
    _METRICS_HIST_SUMS=()
    _METRICS_HIST_COUNTS=()
    _METRICS_HIST_BUCKET_DEFS=()
    _METRICS_SUMMARY_OBS=()
    _METRICS_SUMMARY_SUMS=()
    _METRICS_SUMMARY_COUNTS=()
    _METRICS_TIMERS=()
    _METRICS_TIMER_COUNTER=0

    return 0
}

# =============================================================================
# COUNTER OPERATIONS
# =============================================================================

# @pre: name is non-empty, help is optional description
# @post: counter metric created and registered
# @idempotent: yes
# @returns: 0 on success, 1 on invalid name
#
# Create a counter metric. Counters can only increase (monotonically).
#
# Usage: counter_create "http_requests_total" "Total number of HTTP requests"
counter_create() {
    local name="$1"
    local help="${2:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    metrics_register "$name" "counter" "$help" || return 1

    # Initialize with zero if not exists
    [[ -z "${_METRICS_COUNTERS[$name]:-}" ]] && _METRICS_COUNTERS[$name]=0

    return 0
}

# @pre: name is registered counter
# @post: counter incremented by 1
# @idempotent: no
# @returns: 0 on success, 1 if not a counter
#
# Increment a counter by 1.
#
# Usage: counter_inc "http_requests_total"
counter_inc() {
    local name="$1"
    local labels="${2:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    # Auto-register if not exists
    if [[ -z "${_METRICS_REGISTRY[$name]:-}" ]]; then
        counter_create "$name" || return 1
    fi

    if [[ "${_METRICS_REGISTRY[$name]}" != "counter" ]]; then
        printf '{"error":true,"msg":"not a counter","name":"%s","type":"%s"}\n' \
            "$name" "${_METRICS_REGISTRY[$name]}" >&2
        return 1
    fi

    local key="$(_metrics_key "$name" "$labels")"
    local current="${_METRICS_COUNTERS[$key]:-0}"
    _METRICS_COUNTERS[$key]=$((current + 1))

    return 0
}

# @pre: name is registered counter, value is non-negative number
# @post: counter incremented by value
# @idempotent: no
# @returns: 0 on success, 1 if not a counter or negative value
#
# Add a value to a counter. Value must be non-negative.
#
# Usage: counter_add "http_requests_total" 5
counter_add() {
    local name="$1"
    local value="$2"
    local labels="${3:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    # Validate value is non-negative number
    if ! _metrics_number_valid "$value" || [[ "$value" == -* ]]; then
        printf '{"error":true,"msg":"counter value must be non-negative","value":"%s"}\n' "$value" >&2
        return 1
    fi

    # Auto-register if not exists
    if [[ -z "${_METRICS_REGISTRY[$name]:-}" ]]; then
        counter_create "$name" || return 1
    fi

    if [[ "${_METRICS_REGISTRY[$name]}" != "counter" ]]; then
        printf '{"error":true,"msg":"not a counter","name":"%s"}\n' "$name" >&2
        return 1
    fi

    local key="$(_metrics_key "$name" "$labels")"
    local current="${_METRICS_COUNTERS[$key]:-0}"

    # Handle float addition with bc if available
    _METRICS_COUNTERS[$key]=$(_metrics_add_numbers "$current" "$value")

    return 0
}

# @pre: name is registered counter
# @post: returns current counter value
# @idempotent: yes
# @returns: 0, prints value to stdout
#
# Get the current value of a counter.
#
# Usage: counter_get "http_requests_total"
counter_get() {
    local name="$1"
    local labels="${2:-}"

    local key="$(_metrics_key "$name" "$labels")"
    printf '%s' "${_METRICS_COUNTERS[$key]:-0}"
}

# @pre: name is registered counter
# @post: counter reset to 0
# @idempotent: yes
# @returns: 0
#
# Reset a counter to 0 (mainly for testing purposes).
# Note: In production, counters should not be reset as this breaks rate calculations.
#
# Usage: counter_reset "http_requests_total"
counter_reset() {
    local name="$1"
    local labels="${2:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    local key="$(_metrics_key "$name" "$labels")"
    _METRICS_COUNTERS[$key]=0

    return 0
}

# @pre: name, labels_spec, help are provided
# @post: counter with labels created
# @idempotent: yes
# @returns: 0 on success
#
# Create a counter with label support.
#
# Usage: counter_labels "http_requests_total" "method status" "Total HTTP requests by method and status"
counter_labels() {
    local name="$1"
    local labels_spec="$2"  # Space-separated label names (for documentation)
    local help="${3:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    # Register the base metric
    metrics_register "$name" "counter" "$help" || return 1

    return 0
}

# =============================================================================
# GAUGE OPERATIONS
# =============================================================================

# @pre: name is non-empty, help is optional description
# @post: gauge metric created and registered
# @idempotent: yes
# @returns: 0 on success, 1 on invalid name
#
# Create a gauge metric. Gauges can go up and down.
#
# Usage: gauge_create "temperature_celsius" "Current temperature in Celsius"
gauge_create() {
    local name="$1"
    local help="${2:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    metrics_register "$name" "gauge" "$help" || return 1

    # Initialize with zero if not exists
    [[ -z "${_METRICS_GAUGES[$name]:-}" ]] && _METRICS_GAUGES[$name]=0

    return 0
}

# @pre: name is registered gauge, value is a number
# @post: gauge set to value
# @idempotent: yes
# @returns: 0 on success, 1 if not a gauge
#
# Set a gauge to a specific value.
#
# Usage: gauge_set "temperature_celsius" 23.5
gauge_set() {
    local name="$1"
    local value="$2"
    local labels="${3:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    # Validate value is a number
    if ! _metrics_number_valid "$value"; then
        printf '{"error":true,"msg":"gauge value must be a number","value":"%s"}\n' "$value" >&2
        return 1
    fi

    # Auto-register if not exists
    if [[ -z "${_METRICS_REGISTRY[$name]:-}" ]]; then
        gauge_create "$name" || return 1
    fi

    if [[ "${_METRICS_REGISTRY[$name]}" != "gauge" ]]; then
        printf '{"error":true,"msg":"not a gauge","name":"%s"}\n' "$name" >&2
        return 1
    fi

    local key="$(_metrics_key "$name" "$labels")"
    _METRICS_GAUGES[$key]=$(_metrics_normalize_number "$value")

    return 0
}

# @pre: name is registered gauge
# @post: gauge incremented by 1
# @idempotent: no
# @returns: 0 on success
#
# Increment a gauge by 1.
#
# Usage: gauge_inc "active_connections"
gauge_inc() {
    local name="$1"
    local labels="${2:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    # Auto-register if not exists
    if [[ -z "${_METRICS_REGISTRY[$name]:-}" ]]; then
        gauge_create "$name" || return 1
    fi

    if [[ "${_METRICS_REGISTRY[$name]}" != "gauge" ]]; then
        printf '{"error":true,"msg":"not a gauge","name":"%s"}\n' "$name" >&2
        return 1
    fi

    local key="$(_metrics_key "$name" "$labels")"
    local current="${_METRICS_GAUGES[$key]:-0}"

    _METRICS_GAUGES[$key]=$(_metrics_add_numbers "$current" "1")

    return 0
}

# @pre: name is registered gauge
# @post: gauge decremented by 1
# @idempotent: no
# @returns: 0 on success
#
# Decrement a gauge by 1.
#
# Usage: gauge_dec "active_connections"
gauge_dec() {
    local name="$1"
    local labels="${2:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    # Auto-register if not exists
    if [[ -z "${_METRICS_REGISTRY[$name]:-}" ]]; then
        gauge_create "$name" || return 1
    fi

    if [[ "${_METRICS_REGISTRY[$name]}" != "gauge" ]]; then
        printf '{"error":true,"msg":"not a gauge","name":"%s"}\n' "$name" >&2
        return 1
    fi

    local key="$(_metrics_key "$name" "$labels")"
    local current="${_METRICS_GAUGES[$key]:-0}"

    _METRICS_GAUGES[$key]=$(_metrics_subtract_numbers "$current" "1")

    return 0
}

# @pre: name is registered gauge, value is a number
# @post: gauge increased by value
# @idempotent: no
# @returns: 0 on success
#
# Add a value to a gauge (can be negative).
#
# Usage: gauge_add "temperature_celsius" 0.5
gauge_add() {
    local name="$1"
    local value="$2"
    local labels="${3:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    # Validate value is a number
    if ! _metrics_number_valid "$value"; then
        printf '{"error":true,"msg":"gauge value must be a number","value":"%s"}\n' "$value" >&2
        return 1
    fi

    # Auto-register if not exists
    if [[ -z "${_METRICS_REGISTRY[$name]:-}" ]]; then
        gauge_create "$name" || return 1
    fi

    if [[ "${_METRICS_REGISTRY[$name]}" != "gauge" ]]; then
        printf '{"error":true,"msg":"not a gauge","name":"%s"}\n' "$name" >&2
        return 1
    fi

    local key="$(_metrics_key "$name" "$labels")"
    local current="${_METRICS_GAUGES[$key]:-0}"

    _METRICS_GAUGES[$key]=$(_metrics_add_numbers "$current" "$value")

    return 0
}

# @pre: name is registered gauge, value is a number
# @post: gauge decreased by value
# @idempotent: no
# @returns: 0 on success
#
# Subtract a value from a gauge.
#
# Usage: gauge_sub "queue_size" 10
gauge_sub() {
    local name="$1"
    local value="$2"
    local labels="${3:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    # Validate value is a number
    if ! _metrics_number_valid "$value"; then
        printf '{"error":true,"msg":"gauge value must be a number","value":"%s"}\n' "$value" >&2
        return 1
    fi

    # Auto-register if not exists
    if [[ -z "${_METRICS_REGISTRY[$name]:-}" ]]; then
        gauge_create "$name" || return 1
    fi

    if [[ "${_METRICS_REGISTRY[$name]}" != "gauge" ]]; then
        printf '{"error":true,"msg":"not a gauge","name":"%s"}\n' "$name" >&2
        return 1
    fi

    local key="$(_metrics_key "$name" "$labels")"
    local current="${_METRICS_GAUGES[$key]:-0}"

    _METRICS_GAUGES[$key]=$(_metrics_subtract_numbers "$current" "$value")

    return 0
}

# @pre: name is registered gauge
# @post: returns current gauge value
# @idempotent: yes
# @returns: 0, prints value to stdout
#
# Get the current value of a gauge.
#
# Usage: gauge_get "temperature_celsius"
gauge_get() {
    local name="$1"
    local labels="${2:-}"

    local key="$(_metrics_key "$name" "$labels")"
    printf '%s' "${_METRICS_GAUGES[$key]:-0}"
}

# @pre: name, labels_spec, help are provided
# @post: gauge with labels created
# @idempotent: yes
# @returns: 0 on success
#
# Create a gauge with label support.
#
# Usage: gauge_labels "cpu_usage" "cpu" "CPU usage percentage by CPU"
gauge_labels() {
    local name="$1"
    local labels_spec="$2"
    local help="${3:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    metrics_register "$name" "gauge" "$help" || return 1

    return 0
}

# =============================================================================
# HISTOGRAM OPERATIONS
# =============================================================================

# @pre: name is non-empty, buckets are optional (uses defaults)
# @post: histogram metric created with buckets
# @idempotent: yes
# @returns: 0 on success
#
# Create a histogram metric with specified buckets.
# Buckets define the upper bounds for observation counting.
#
# Usage: histogram_create "http_request_duration_seconds" ".1 .5 1 5 10" "Request duration"
histogram_create() {
    local name="$1"
    local buckets="${2:-$MAINFRAME_HISTOGRAM_BUCKETS}"
    local help="${3:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    metrics_register "$name" "histogram" "$help" || return 1

    # Store bucket definitions
    _METRICS_HIST_BUCKET_DEFS[$name]="$buckets"

    # Initialize bucket counts to 0
    for bucket in $buckets; do
        _METRICS_HIST_BUCKETS["${name}_bucket{le=\"$bucket\"}"]="${_METRICS_HIST_BUCKETS["${name}_bucket{le=\"$bucket\"}"]:-0}"
    done
    # +Inf bucket
    _METRICS_HIST_BUCKETS["${name}_bucket{le=\"+Inf\"}"]="${_METRICS_HIST_BUCKETS["${name}_bucket{le=\"+Inf\"}"]:-0}"

    # Initialize sum and count
    _METRICS_HIST_SUMS[$name]="${_METRICS_HIST_SUMS[$name]:-0}"
    _METRICS_HIST_COUNTS[$name]="${_METRICS_HIST_COUNTS[$name]:-0}"

    return 0
}

# @pre: name is registered histogram, value is a number
# @post: observation recorded in appropriate buckets
# @idempotent: no
# @returns: 0 on success
#
# Record an observation in a histogram.
#
# Usage: histogram_observe "http_request_duration_seconds" 0.25
histogram_observe() {
    local name="$1"
    local value="$2"
    local labels="${3:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    # Validate value is a number
    if ! _metrics_number_valid "$value"; then
        printf '{"error":true,"msg":"histogram value must be a number","value":"%s"}\n' "$value" >&2
        return 1
    fi

    # Auto-register if not exists
    if [[ -z "${_METRICS_REGISTRY[$name]:-}" ]]; then
        histogram_create "$name" || return 1
    fi

    if [[ "${_METRICS_REGISTRY[$name]}" != "histogram" ]]; then
        printf '{"error":true,"msg":"not a histogram","name":"%s"}\n' "$name" >&2
        return 1
    fi

    local base_key="$(_metrics_key "$name" "$labels")"
    local buckets="${_METRICS_HIST_BUCKET_DEFS[$name]:-$MAINFRAME_HISTOGRAM_BUCKETS}"

    # Update bucket counts - increment all buckets >= value
    for bucket in $buckets; do
        local bucket_key
        if [[ -n "$labels" ]]; then
            # Insert le before closing brace
            bucket_key="${base_key%\}},le=\"$bucket\"}"
        else
            bucket_key="${name}_bucket{le=\"$bucket\"}"
        fi

        local cmp_result
        if command -v bc &>/dev/null; then
            cmp_result=$(echo "$value <= $bucket" | bc 2>/dev/null || echo "0")
        else
            # Integer comparison fallback
            local int_value="${value%%.*}"
            local int_bucket="${bucket%%.*}"
            [[ "$int_value" -le "$int_bucket" ]] && cmp_result=1 || cmp_result=0
        fi

        if [[ "$cmp_result" == "1" ]]; then
            local current="${_METRICS_HIST_BUCKETS[$bucket_key]:-0}"
            _METRICS_HIST_BUCKETS[$bucket_key]=$((current + 1))
        fi
    done

    # Always increment +Inf bucket
    local inf_key
    if [[ -n "$labels" ]]; then
        inf_key="${base_key%\}},le=\"+Inf\"}"
    else
        inf_key="${name}_bucket{le=\"+Inf\"}"
    fi
    local current="${_METRICS_HIST_BUCKETS[$inf_key]:-0}"
    _METRICS_HIST_BUCKETS[$inf_key]=$((current + 1))

    # Update sum
    local sum_key="$base_key"
    local current_sum="${_METRICS_HIST_SUMS[$sum_key]:-0}"
    _METRICS_HIST_SUMS[$sum_key]=$(_metrics_add_numbers "$current_sum" "$value")

    # Update count
    local count_key="$base_key"
    local current_count="${_METRICS_HIST_COUNTS[$count_key]:-0}"
    _METRICS_HIST_COUNTS[$count_key]=$((current_count + 1))

    return 0
}

# @pre: name is registered histogram
# @post: returns bucket counts as JSON
# @idempotent: yes
# @returns: 0, prints JSON object with bucket counts
#
# Get all bucket counts for a histogram.
#
# Usage: histogram_get_buckets "http_request_duration_seconds"
histogram_get_buckets() {
    local name="$1"
    local labels="${2:-}"

    local base_key="$(_metrics_key "$name" "$labels")"
    local buckets="${_METRICS_HIST_BUCKET_DEFS[$name]:-$MAINFRAME_HISTOGRAM_BUCKETS}"

    local first=true
    printf '{'

    for bucket in $buckets; do
        local bucket_key
        if [[ -n "$labels" ]]; then
            bucket_key="${base_key%\}},le=\"$bucket\"}"
        else
            bucket_key="${name}_bucket{le=\"$bucket\"}"
        fi

        $first || printf ','
        first=false
        printf '"%s":%s' "$bucket" "${_METRICS_HIST_BUCKETS[$bucket_key]:-0}"
    done

    # +Inf bucket
    local inf_key
    if [[ -n "$labels" ]]; then
        inf_key="${base_key%\}},le=\"+Inf\"}"
    else
        inf_key="${name}_bucket{le=\"+Inf\"}"
    fi
    printf ',"+Inf":%s' "${_METRICS_HIST_BUCKETS[$inf_key]:-0}"

    printf '}'
}

# @pre: name is registered histogram
# @post: returns sum of all observations
# @idempotent: yes
# @returns: 0, prints sum to stdout
#
# Get the sum of all observed values for a histogram.
#
# Usage: histogram_get_sum "http_request_duration_seconds"
histogram_get_sum() {
    local name="$1"
    local labels="${2:-}"

    local key="$(_metrics_key "$name" "$labels")"
    _metrics_normalize_number "${_METRICS_HIST_SUMS[$key]:-0}"
}

# @pre: name is registered histogram
# @post: returns count of observations
# @idempotent: yes
# @returns: 0, prints count to stdout
#
# Get the total count of observations for a histogram.
#
# Usage: histogram_get_count "http_request_duration_seconds"
histogram_get_count() {
    local name="$1"
    local labels="${2:-}"

    local key="$(_metrics_key "$name" "$labels")"
    printf '%s' "${_METRICS_HIST_COUNTS[$key]:-0}"
}

# @pre: name, labels_spec, buckets, help are provided
# @post: histogram with labels created
# @idempotent: yes
# @returns: 0 on success
#
# Create a histogram with label support.
#
# Usage: histogram_labels "http_request_duration_seconds" "method path" ".1 .5 1" "Request duration"
histogram_labels() {
    local name="$1"
    local labels_spec="$2"
    local buckets="${3:-$MAINFRAME_HISTOGRAM_BUCKETS}"
    local help="${4:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    metrics_register "$name" "histogram" "$help" || return 1
    _METRICS_HIST_BUCKET_DEFS[$name]="$buckets"

    return 0
}

# @pre: name is registered histogram, quantile is 0-1
# @post: returns estimated quantile value
# @idempotent: yes
# @returns: 0, prints estimated value to stdout
#
# Estimate a quantile from histogram buckets using linear interpolation.
# Note: This is an approximation, not exact quantile calculation.
#
# Usage: histogram_quantile "http_request_duration_seconds" 0.95
histogram_quantile() {
    local name="$1"
    local quantile="$2"
    local labels="${3:-}"

    # Validate quantile is 0-1
    if ! command -v bc &>/dev/null; then
        printf '{"error":true,"msg":"bc required for quantile calculation"}\n' >&2
        return 1
    fi

    local valid
    valid=$(echo "$quantile >= 0 && $quantile <= 1" | bc 2>/dev/null || echo "0")
    if [[ "$valid" != "1" ]]; then
        printf '{"error":true,"msg":"quantile must be between 0 and 1","quantile":"%s"}\n' "$quantile" >&2
        return 1
    fi

    local base_key="$(_metrics_key "$name" "$labels")"
    local buckets="${_METRICS_HIST_BUCKET_DEFS[$name]:-$MAINFRAME_HISTOGRAM_BUCKETS}"
    local total_count="${_METRICS_HIST_COUNTS[$base_key]:-0}"

    if [[ "$total_count" == "0" ]]; then
        printf 'NaN'
        return 0
    fi

    # Target count for the quantile
    local target_count
    target_count=$(echo "$total_count * $quantile" | bc)

    # Linear interpolation between buckets
    local prev_bound="0"
    local prev_count="0"

    for bucket in $buckets; do
        local bucket_key
        if [[ -n "$labels" ]]; then
            bucket_key="${base_key%\}},le=\"$bucket\"}"
        else
            bucket_key="${name}_bucket{le=\"$bucket\"}"
        fi
        local bucket_count="${_METRICS_HIST_BUCKETS[$bucket_key]:-0}"

        local in_bucket
        in_bucket=$(echo "$bucket_count >= $target_count" | bc 2>/dev/null || echo "0")

        if [[ "$in_bucket" == "1" ]]; then
            # Linear interpolation
            local bucket_width
            bucket_width=$(echo "$bucket - $prev_bound" | bc)
            local count_in_bucket
            count_in_bucket=$(echo "$bucket_count - $prev_count" | bc)
            local count_needed
            count_needed=$(echo "$target_count - $prev_count" | bc)

            if [[ "$count_in_bucket" == "0" ]]; then
                printf '%s' "$prev_bound"
            else
                local result
                result=$(echo "$prev_bound + ($bucket_width * $count_needed / $count_in_bucket)" | bc -l)
                printf '%s' "$result"
            fi
            return 0
        fi

        prev_bound="$bucket"
        prev_count="$bucket_count"
    done

    # Value is beyond all buckets
    printf '+Inf'
    return 0
}

# =============================================================================
# SUMMARY OPERATIONS
# =============================================================================

# @pre: name is non-empty
# @post: summary metric created
# @idempotent: yes
# @returns: 0 on success
#
# Create a summary metric for calculating streaming quantiles.
# Note: Summary stores raw observations with timestamps for sliding window.
#
# Usage: summary_create "request_latency_seconds" "Request latency"
summary_create() {
    local name="$1"
    local help="${2:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    metrics_register "$name" "summary" "$help" || return 1

    # Initialize
    _METRICS_SUMMARY_OBS[$name]=""
    _METRICS_SUMMARY_SUMS[$name]=0
    _METRICS_SUMMARY_COUNTS[$name]=0

    return 0
}

# @pre: name is registered summary, value is a number
# @post: observation recorded with timestamp
# @idempotent: no
# @returns: 0 on success
#
# Record an observation in a summary.
#
# Usage: summary_observe "request_latency_seconds" 0.125
summary_observe() {
    local name="$1"
    local value="$2"
    local labels="${3:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    # Validate value is a number
    if ! _metrics_number_valid "$value"; then
        printf '{"error":true,"msg":"summary value must be a number","value":"%s"}\n' "$value" >&2
        return 1
    fi

    # Auto-register if not exists
    if [[ -z "${_METRICS_REGISTRY[$name]:-}" ]]; then
        summary_create "$name" || return 1
    fi

    if [[ "${_METRICS_REGISTRY[$name]}" != "summary" ]]; then
        printf '{"error":true,"msg":"not a summary","name":"%s"}\n' "$name" >&2
        return 1
    fi

    local key="$(_metrics_key "$name" "$labels")"
    local now
    now=$(_metrics_now)

    # Append observation with timestamp
    local current_obs="${_METRICS_SUMMARY_OBS[$key]:-}"
    if [[ -n "$current_obs" ]]; then
        _METRICS_SUMMARY_OBS[$key]="$current_obs $now:$value"
    else
        _METRICS_SUMMARY_OBS[$key]="$now:$value"
    fi

    # Update sum
    local current_sum="${_METRICS_SUMMARY_SUMS[$key]:-0}"
    _METRICS_SUMMARY_SUMS[$key]=$(_metrics_add_numbers "$current_sum" "$value")

    # Update count
    local current_count="${_METRICS_SUMMARY_COUNTS[$key]:-0}"
    _METRICS_SUMMARY_COUNTS[$key]=$((current_count + 1))

    # Expire old observations
    _metrics_summary_expire "$key"

    return 0
}

# Internal: expire old observations from summary
_metrics_summary_expire() {
    local key="$1"
    local max_age="${MAINFRAME_SUMMARY_MAX_AGE}"

    local now
    now=$(_metrics_now)
    local cutoff
    if command -v bc &>/dev/null; then
        cutoff=$(echo "$now - $max_age" | bc)
    else
        local now_int="${now%%.*}"
        cutoff=$((now_int - max_age))
    fi

    local current_obs="${_METRICS_SUMMARY_OBS[$key]:-}"
    local new_obs=""

    for obs in $current_obs; do
        local ts="${obs%%:*}"
        local ts_int="${ts%%.*}"
        local cutoff_int="${cutoff%%.*}"

        if [[ "$ts_int" -ge "$cutoff_int" ]]; then
            if [[ -n "$new_obs" ]]; then
                new_obs="$new_obs $obs"
            else
                new_obs="$obs"
            fi
        fi
    done

    _METRICS_SUMMARY_OBS[$key]="$new_obs"
}

# @pre: name is registered summary
# @post: returns quantile values as JSON
# @idempotent: yes
# @returns: 0, prints JSON with quantile values
#
# Get quantile values from a summary.
#
# Usage: summary_get_quantiles "request_latency_seconds"
summary_get_quantiles() {
    local name="$1"
    local labels="${2:-}"
    local quantiles="${3:-$MAINFRAME_SUMMARY_QUANTILES}"

    local key="$(_metrics_key "$name" "$labels")"

    # Get observations and sort them
    local obs="${_METRICS_SUMMARY_OBS[$key]:-}"

    if [[ -z "$obs" ]]; then
        printf '{"error":"no observations"}'
        return 0
    fi

    # Extract values and sort
    local values=""
    for ob in $obs; do
        local val="${ob#*:}"
        if [[ -n "$values" ]]; then
            values="$values $val"
        else
            values="$val"
        fi
    done

    # Sort values numerically
    local sorted
    sorted=$(echo "$values" | tr ' ' '\n' | sort -n)
    local count
    count=$(echo "$sorted" | wc -l)

    local first=true
    printf '{'

    for q in $quantiles; do
        $first || printf ','
        first=false

        # Calculate index for quantile
        local idx
        if command -v bc &>/dev/null; then
            idx=$(echo "scale=0; ($count * $q) / 1" | bc)
            [[ "$idx" -lt 1 ]] && idx=1
            [[ "$idx" -gt "$count" ]] && idx="$count"
        else
            idx=1
        fi

        local val
        val=$(echo "$sorted" | sed -n "${idx}p")

        printf '"%s":%s' "$(_metrics_normalize_number "$q")" "$(_metrics_normalize_number "${val:-0}")"
    done

    printf '}'
}

# @pre: name is registered summary
# @post: returns sum of observations
# @idempotent: yes
# @returns: 0, prints sum to stdout
#
# Get the sum of all observations in a summary.
#
# Usage: summary_get_sum "request_latency_seconds"
summary_get_sum() {
    local name="$1"
    local labels="${2:-}"

    local key="$(_metrics_key "$name" "$labels")"
    _metrics_normalize_number "${_METRICS_SUMMARY_SUMS[$key]:-0}"
}

# @pre: name is registered summary
# @post: returns count of observations
# @idempotent: yes
# @returns: 0, prints count to stdout
#
# Get the total count of observations in a summary.
#
# Usage: summary_get_count "request_latency_seconds"
summary_get_count() {
    local name="$1"
    local labels="${2:-}"

    local key="$(_metrics_key "$name" "$labels")"
    printf '%s' "${_METRICS_SUMMARY_COUNTS[$key]:-0}"
}

# =============================================================================
# TIMER HELPERS
# =============================================================================

# @pre: metric_name is registered histogram or summary
# @post: timer started, ID returned
# @idempotent: no
# @returns: 0, prints timer_id to stdout
#
# Start a timer for measuring duration. Returns a timer ID to pass to timer_stop.
#
# Usage: timer_id=$(timer_start "http_request_duration_seconds")
timer_start() {
    local metric_name="$1"
    local labels="${2:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && { printf 'disabled'; return 0; }

    # Use file-based storage to survive subshell execution
    local timer_dir="${MAINFRAME_METRICS_TIMER_DIR:-/tmp/mainframe_timers_$$}"
    mkdir -p "$timer_dir" 2>/dev/null

    local timer_id="timer_${RANDOM}_$(date +%s%N)"
    local start_time
    start_time=$(_metrics_now)

    # Store timer data in file (survives subshell)
    printf '%s:%s:%s\n' "$start_time" "$metric_name" "$labels" > "$timer_dir/$timer_id"

    printf '%s' "$timer_id"
}

# @pre: timer_id from timer_start
# @post: duration recorded to metric, timer removed
# @idempotent: no
# @returns: 0 on success, 1 if timer not found
#
# Stop a timer and record the duration to the associated metric.
#
# Usage: timer_stop "$timer_id"
timer_stop() {
    local timer_id="$1"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    # Read timer data from file (survives subshell)
    local timer_dir="${MAINFRAME_METRICS_TIMER_DIR:-/tmp/mainframe_timers_$$}"
    local timer_file="$timer_dir/$timer_id"
    local timer_data=""

    if [[ -f "$timer_file" ]]; then
        timer_data=$(<"$timer_file")
    fi

    if [[ -z "$timer_data" ]]; then
        printf '{"error":true,"msg":"timer not found","timer_id":"%s"}\n' "$timer_id" >&2
        return 1
    fi

    local end_time
    end_time=$(_metrics_now)

    # Parse timer data
    local start_time="${timer_data%%:*}"
    local rest="${timer_data#*:}"
    local metric_name="${rest%%:*}"
    local labels="${rest#*:}"
    [[ "$labels" == "$metric_name" ]] && labels=""

    # Calculate duration
    local duration
    if command -v bc &>/dev/null; then
        duration=$(echo "$end_time - $start_time" | bc)
        # Ensure positive
        [[ "$duration" == -* ]] && duration="${duration#-}"
        # Ensure leading zero
        [[ "$duration" == .* ]] && duration="0$duration"
    else
        local end_int="${end_time%%.*}"
        local start_int="${start_time%%.*}"
        duration=$((end_int - start_int))
    fi

    # Record to appropriate metric type
    local metric_type="${_METRICS_REGISTRY[$metric_name]:-histogram}"

    case "$metric_type" in
        histogram)
            histogram_observe "$metric_name" "$duration" "$labels"
            ;;
        summary)
            summary_observe "$metric_name" "$duration" "$labels"
            ;;
        *)
            printf '{"error":true,"msg":"timer metric must be histogram or summary","type":"%s"}\n' "$metric_type" >&2
            return 1
            ;;
    esac

    # Clean up timer file
    rm -f "$timer_file" 2>/dev/null

    # Return duration
    printf '%s' "$duration"
}

# @pre: metric_name is registered, value is a number
# @post: observation recorded with provided duration
# @idempotent: no
# @returns: 0 on success
#
# Directly observe a pre-calculated duration (no timer needed).
#
# Usage: timer_observe "http_request_duration_seconds" 0.125
timer_observe() {
    local metric_name="$1"
    local duration="$2"
    local labels="${3:-}"

    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    local metric_type="${_METRICS_REGISTRY[$metric_name]:-histogram}"

    case "$metric_type" in
        histogram)
            histogram_observe "$metric_name" "$duration" "$labels"
            ;;
        summary)
            summary_observe "$metric_name" "$duration" "$labels"
            ;;
        *)
            # Auto-create as histogram
            histogram_create "$metric_name"
            histogram_observe "$metric_name" "$duration" "$labels"
            ;;
    esac

    return 0
}

# =============================================================================
# EXPORT: PROMETHEUS TEXT FORMAT
# =============================================================================

# @pre: none
# @post: returns current timestamp suitable for export
# @idempotent: yes
# @returns: 0, prints timestamp in milliseconds
#
# Get current timestamp formatted for metric export.
#
# Usage: ts=$(metric_timestamp)
metric_timestamp() {
    _metrics_timestamp_ms
}

# @pre: none
# @post: all metrics exported in Prometheus text format
# @idempotent: yes
# @returns: 0, prints metrics to stdout
#
# Export all metrics in Prometheus text exposition format.
# Compatible with Prometheus scraping.
#
# Usage: metrics_export_prometheus
metrics_export_prometheus() {
    local name type help

    # Process each registered metric
    for name in "${!_METRICS_REGISTRY[@]}"; do
        type="${_METRICS_REGISTRY[$name]}"
        help="${_METRICS_HELP[$name]:-}"

        # HELP line
        [[ -n "$help" ]] && printf '# HELP %s %s\n' "$name" "$help"

        # TYPE line
        printf '# TYPE %s %s\n' "$name" "$type"

        case "$type" in
            counter)
                _metrics_export_counter_prometheus "$name"
                ;;
            gauge)
                _metrics_export_gauge_prometheus "$name"
                ;;
            histogram)
                _metrics_export_histogram_prometheus "$name"
                ;;
            summary)
                _metrics_export_summary_prometheus "$name"
                ;;
        esac

        printf '\n'
    done
}

# Internal: export counter in Prometheus format
_metrics_export_counter_prometheus() {
    local name="$1"

    for key in "${!_METRICS_COUNTERS[@]}"; do
        if [[ "$key" == "$name"* ]]; then
            local value="${_METRICS_COUNTERS[$key]}"

            if [[ "$key" == "$name" ]]; then
                printf '%s %s\n' "$name" "$value"
            else
                # Has labels
                local labels="${key#$name}"
                printf '%s%s %s\n' "$name" "$labels" "$value"
            fi
        fi
    done
}

# Internal: export gauge in Prometheus format
_metrics_export_gauge_prometheus() {
    local name="$1"

    for key in "${!_METRICS_GAUGES[@]}"; do
        if [[ "$key" == "$name"* ]]; then
            local value="${_METRICS_GAUGES[$key]}"

            if [[ "$key" == "$name" ]]; then
                printf '%s %s\n' "$name" "$value"
            else
                local labels="${key#$name}"
                printf '%s%s %s\n' "$name" "$labels" "$value"
            fi
        fi
    done
}

# Internal: export histogram in Prometheus format
_metrics_export_histogram_prometheus() {
    local name="$1"
    local buckets="${_METRICS_HIST_BUCKET_DEFS[$name]:-$MAINFRAME_HISTOGRAM_BUCKETS}"

    # Find all unique label combinations
    local seen_keys=""

    for key in "${!_METRICS_HIST_COUNTS[@]}"; do
        if [[ "$key" == "$name"* ]]; then
            # Extract base key (without le label)
            local base_key="$key"

            # Check if already processed
            [[ " $seen_keys " == *" $base_key "* ]] && continue
            seen_keys="$seen_keys $base_key"

            local labels=""
            if [[ "$key" != "$name" ]]; then
                labels="${key#$name}"
            fi

            # Export buckets
            for bucket in $buckets; do
                local bucket_key
                if [[ -n "$labels" ]]; then
                    bucket_key="${name}${labels%\}},le=\"$bucket\"}"
                else
                    bucket_key="${name}_bucket{le=\"$bucket\"}"
                fi
                local count="${_METRICS_HIST_BUCKETS[$bucket_key]:-0}"

                if [[ -n "$labels" ]]; then
                    printf '%s_bucket%s %s\n' "$name" "{le=\"$bucket\"${labels#\{}" "$count"
                else
                    printf '%s_bucket{le="%s"} %s\n' "$name" "$bucket" "$count"
                fi
            done

            # +Inf bucket
            local inf_key
            if [[ -n "$labels" ]]; then
                inf_key="${name}${labels%\}},le=\"+Inf\"}"
            else
                inf_key="${name}_bucket{le=\"+Inf\"}"
            fi
            local inf_count="${_METRICS_HIST_BUCKETS[$inf_key]:-0}"

            if [[ -n "$labels" ]]; then
                printf '%s_bucket%s %s\n' "$name" "{le=\"+Inf\"${labels#\{}" "$inf_count"
            else
                printf '%s_bucket{le="+Inf"} %s\n' "$name" "$inf_count"
            fi

            # _sum and _count
            local sum="${_METRICS_HIST_SUMS[$key]:-0}"
            local count="${_METRICS_HIST_COUNTS[$key]:-0}"

            if [[ -n "$labels" ]]; then
                printf '%s_sum%s %s\n' "$name" "$labels" "$sum"
                printf '%s_count%s %s\n' "$name" "$labels" "$count"
            else
                printf '%s_sum %s\n' "$name" "$sum"
                printf '%s_count %s\n' "$name" "$count"
            fi
        fi
    done
}

# Internal: export summary in Prometheus format
_metrics_export_summary_prometheus() {
    local name="$1"
    local quantiles="${MAINFRAME_SUMMARY_QUANTILES}"

    for key in "${!_METRICS_SUMMARY_COUNTS[@]}"; do
        if [[ "$key" == "$name"* ]]; then
            local labels=""
            if [[ "$key" != "$name" ]]; then
                labels="${key#$name}"
            fi

            # Calculate and export quantiles
            local quantile_json
            quantile_json=$(summary_get_quantiles "$name" "$labels")

            for q in $quantiles; do
                local val
                val=$(echo "$quantile_json" | grep -oP "\"$q\":\K[0-9.]+" || echo "NaN")

                if [[ -n "$labels" ]]; then
                    printf '%s%s %s\n' "$name" "{quantile=\"$q\"${labels#\{}" "$val"
                else
                    printf '%s{quantile="%s"} %s\n' "$name" "$q" "$val"
                fi
            done

            # _sum and _count
            local sum="${_METRICS_SUMMARY_SUMS[$key]:-0}"
            local count="${_METRICS_SUMMARY_COUNTS[$key]:-0}"

            if [[ -n "$labels" ]]; then
                printf '%s_sum%s %s\n' "$name" "$labels" "$sum"
                printf '%s_count%s %s\n' "$name" "$labels" "$count"
            else
                printf '%s_sum %s\n' "$name" "$sum"
                printf '%s_count %s\n' "$name" "$count"
            fi
        fi
    done
}

# =============================================================================
# EXPORT: JSON FORMAT
# =============================================================================

# @pre: none
# @post: all metrics exported in JSON format
# @idempotent: yes
# @returns: 0, prints JSON to stdout
#
# Export all metrics in JSON format.
#
# Usage: metrics_export_json
metrics_export_json() {
    local first_metric=true
    printf '{"metrics":['

    for name in "${!_METRICS_REGISTRY[@]}"; do
        local type="${_METRICS_REGISTRY[$name]}"
        local help="${_METRICS_HELP[$name]:-}"

        $first_metric || printf ','
        first_metric=false

        printf '{"name":"%s","type":"%s"' "$name" "$type"
        [[ -n "$help" ]] && printf ',"help":"%s"' "$(_metrics_escape_json "$help")"

        case "$type" in
            counter)
                printf ',"values":['
                local first=true
                for key in "${!_METRICS_COUNTERS[@]}"; do
                    if [[ "$key" == "$name"* ]]; then
                        $first || printf ','
                        first=false
                        local value="${_METRICS_COUNTERS[$key]}"
                        local labels=""
                        [[ "$key" != "$name" ]] && labels="${key#$name}"
                        printf '{"labels":"%s","value":%s}' "$(_metrics_escape_json "$labels")" "$value"
                    fi
                done
                printf ']'
                ;;
            gauge)
                printf ',"values":['
                local first=true
                for key in "${!_METRICS_GAUGES[@]}"; do
                    if [[ "$key" == "$name"* ]]; then
                        $first || printf ','
                        first=false
                        local value="${_METRICS_GAUGES[$key]}"
                        local labels=""
                        [[ "$key" != "$name" ]] && labels="${key#$name}"
                        printf '{"labels":"%s","value":%s}' "$(_metrics_escape_json "$labels")" "$value"
                    fi
                done
                printf ']'
                ;;
            histogram)
                printf ',"values":['
                local first=true
                for key in "${!_METRICS_HIST_COUNTS[@]}"; do
                    if [[ "$key" == "$name"* ]]; then
                        $first || printf ','
                        first=false
                        local labels=""
                        [[ "$key" != "$name" ]] && labels="${key#$name}"
                        printf '{"labels":"%s","sum":%s,"count":%s,"buckets":%s}' \
                            "$(_metrics_escape_json "$labels")" \
                            "${_METRICS_HIST_SUMS[$key]:-0}" \
                            "${_METRICS_HIST_COUNTS[$key]:-0}" \
                            "$(histogram_get_buckets "$name" "$labels")"
                    fi
                done
                printf ']'
                ;;
            summary)
                printf ',"values":['
                local first=true
                for key in "${!_METRICS_SUMMARY_COUNTS[@]}"; do
                    if [[ "$key" == "$name"* ]]; then
                        $first || printf ','
                        first=false
                        local labels=""
                        [[ "$key" != "$name" ]] && labels="${key#$name}"
                        printf '{"labels":"%s","sum":%s,"count":%s,"quantiles":%s}' \
                            "$(_metrics_escape_json "$labels")" \
                            "${_METRICS_SUMMARY_SUMS[$key]:-0}" \
                            "${_METRICS_SUMMARY_COUNTS[$key]:-0}" \
                            "$(summary_get_quantiles "$name" "$labels")"
                    fi
                done
                printf ']'
                ;;
        esac

        printf '}'
    done

    printf '],"timestamp":%s}' "$(_metrics_timestamp_ms)"
}

# =============================================================================
# EXPORT: OPENMETRICS FORMAT
# =============================================================================

# @pre: none
# @post: all metrics exported in OpenMetrics format
# @idempotent: yes
# @returns: 0, prints metrics to stdout
#
# Export all metrics in OpenMetrics format (Prometheus 2.0+).
# OpenMetrics is a CNCF standard that extends Prometheus format.
#
# Usage: metrics_export_openmetrics
metrics_export_openmetrics() {
    local name type help

    for name in "${!_METRICS_REGISTRY[@]}"; do
        type="${_METRICS_REGISTRY[$name]}"
        help="${_METRICS_HELP[$name]:-}"

        # HELP line
        [[ -n "$help" ]] && printf '# HELP %s %s\n' "$name" "$help"

        # TYPE line with OpenMetrics types
        local om_type="$type"
        case "$type" in
            counter) om_type="counter" ;;
            gauge) om_type="gauge" ;;
            histogram) om_type="histogram" ;;
            summary) om_type="summary" ;;
        esac
        printf '# TYPE %s %s\n' "$name" "$om_type"

        # UNIT line (optional, not implemented)

        case "$type" in
            counter)
                _metrics_export_counter_openmetrics "$name"
                ;;
            gauge)
                _metrics_export_gauge_openmetrics "$name"
                ;;
            histogram)
                _metrics_export_histogram_openmetrics "$name"
                ;;
            summary)
                _metrics_export_summary_openmetrics "$name"
                ;;
        esac

        printf '\n'
    done

    # OpenMetrics requires EOF
    printf '# EOF\n'
}

# Internal: export counter in OpenMetrics format
_metrics_export_counter_openmetrics() {
    local name="$1"

    for key in "${!_METRICS_COUNTERS[@]}"; do
        if [[ "$key" == "$name"* ]]; then
            local value="${_METRICS_COUNTERS[$key]}"

            # OpenMetrics counters must have _total suffix
            if [[ "$key" == "$name" ]]; then
                printf '%s_total %s\n' "$name" "$value"
            else
                local labels="${key#$name}"
                printf '%s_total%s %s\n' "$name" "$labels" "$value"
            fi
        fi
    done
}

# Internal: export gauge in OpenMetrics format
_metrics_export_gauge_openmetrics() {
    local name="$1"

    # Same as Prometheus format for gauges
    _metrics_export_gauge_prometheus "$name"
}

# Internal: export histogram in OpenMetrics format
_metrics_export_histogram_openmetrics() {
    local name="$1"

    # Similar to Prometheus but with +Inf as special value
    _metrics_export_histogram_prometheus "$name"
}

# Internal: export summary in OpenMetrics format
_metrics_export_summary_openmetrics() {
    local name="$1"

    # Similar to Prometheus format
    _metrics_export_summary_prometheus "$name"
}

# =============================================================================
# PUSH GATEWAY
# =============================================================================

# @pre: gateway URL is provided
# @post: metrics pushed to Prometheus Pushgateway
# @idempotent: yes (replaces metrics for job)
# @returns: 0 on success, 1 on failure
#
# Push all metrics to a Prometheus Pushgateway.
#
# Usage: metrics_push_gateway "http://localhost:9091" "my_job"
metrics_push_gateway() {
    local gateway_url="$1"
    local job="${2:-mainframe}"
    local instance="${3:-${HOSTNAME:-localhost}}"

    local push_url="${gateway_url}/metrics/job/${job}/instance/${instance}"
    local metrics
    metrics=$(metrics_export_prometheus)

    # Try curl first
    if command -v curl &>/dev/null; then
        if curl -sf -X POST "$push_url" --data-binary "$metrics" &>/dev/null; then
            return 0
        fi
    fi

    # Fallback to /dev/tcp for HTTP
    if [[ "$push_url" =~ ^http://([^/:]+):?([0-9]*)(/.*)$ ]]; then
        local host="${BASH_REMATCH[1]}"
        local port="${BASH_REMATCH[2]:-80}"
        local path="${BASH_REMATCH[3]}"

        local content_length=${#metrics}
        local request
        request="POST $path HTTP/1.1\r\n"
        request+="Host: $host\r\n"
        request+="Content-Type: text/plain\r\n"
        request+="Content-Length: $content_length\r\n"
        request+="Connection: close\r\n"
        request+="\r\n"
        request+="$metrics"

        if exec 3<>"/dev/tcp/$host/$port" 2>/dev/null; then
            printf '%b' "$request" >&3
            local response
            response=$(cat <&3)
            exec 3>&-

            if [[ "$response" =~ HTTP/[0-9.]+[[:space:]]2[0-9]{2} ]]; then
                return 0
            fi
        fi
    fi

    printf '{"error":true,"msg":"failed to push metrics","url":"%s"}\n' "$push_url" >&2
    return 1
}

# =============================================================================
# HTTP SERVER
# =============================================================================

# @pre: netcat (nc) available
# @post: starts simple HTTP server serving metrics
# @idempotent: no
# @returns: 0 on graceful shutdown
#
# Start a simple HTTP server that serves metrics.
# Uses netcat for pure bash HTTP server capability.
# Press Ctrl+C to stop.
#
# Usage: metrics_serve 9091
metrics_serve() {
    local port="${1:-$MAINFRAME_METRICS_PORT}"

    if ! command -v nc &>/dev/null; then
        printf '{"error":true,"msg":"netcat (nc) required for metrics_serve"}\n' >&2
        return 1
    fi

    printf '{"status":"starting","port":%d,"message":"Serving metrics on http://localhost:%d/metrics"}\n' \
        "$port" "$port" >&2

    # Simple HTTP server loop
    while true; do
        {
            local request=""
            local line
            while IFS= read -r line; do
                line="${line%$'\r'}"
                [[ -z "$line" ]] && break
                request+="$line"$'\n'
            done

            local path="/"
            if [[ "$request" =~ GET[[:space:]]+(/[^[:space:]]*) ]]; then
                path="${BASH_REMATCH[1]}"
            fi

            local body status content_type

            case "$path" in
                /metrics)
                    body=$(metrics_export_prometheus)
                    status="200 OK"
                    content_type="text/plain; version=0.0.4; charset=utf-8"
                    ;;
                /metrics/json)
                    body=$(metrics_export_json)
                    status="200 OK"
                    content_type="application/json"
                    ;;
                /metrics/openmetrics)
                    body=$(metrics_export_openmetrics)
                    status="200 OK"
                    content_type="application/openmetrics-text; version=1.0.0; charset=utf-8"
                    ;;
                /health)
                    body='{"status":"healthy"}'
                    status="200 OK"
                    content_type="application/json"
                    ;;
                *)
                    body='{"error":"not found","endpoints":["/metrics","/metrics/json","/metrics/openmetrics","/health"]}'
                    status="404 Not Found"
                    content_type="application/json"
                    ;;
            esac

            local content_length=${#body}

            printf 'HTTP/1.1 %s\r\n' "$status"
            printf 'Content-Type: %s\r\n' "$content_type"
            printf 'Content-Length: %d\r\n' "$content_length"
            printf 'Connection: close\r\n'
            printf '\r\n'
            printf '%s' "$body"

        } | nc -l -p "$port" -q 1 2>/dev/null || nc -l "$port" 2>/dev/null

        # Check if we should exit (Ctrl+C sets trap)
        [[ "${_METRICS_SERVER_STOP:-}" == "1" ]] && break
    done

    return 0
}

# =============================================================================
# UTILITY: STANDARD METRICS
# =============================================================================

# @pre: none
# @post: standard process metrics created and updated
# @idempotent: no - updates values on each call
# @returns: 0
#
# Create and update standard process metrics (Go/Python client compatibility).
#
# Usage: metrics_update_process
metrics_update_process() {
    [[ "$MAINFRAME_METRICS_ENABLED" != "1" ]] && return 0

    # Process CPU time (user + system)
    if [[ -f /proc/self/stat ]]; then
        local stat
        read -r stat < /proc/self/stat
        local fields=($stat)
        local utime="${fields[13]:-0}"
        local stime="${fields[14]:-0}"
        local cpu_seconds
        cpu_seconds=$(echo "scale=2; ($utime + $stime) / 100" | bc 2>/dev/null || echo "0")

        gauge_create "process_cpu_seconds_total" "Total user and system CPU time spent in seconds"
        gauge_set "process_cpu_seconds_total" "$cpu_seconds"
    fi

    # Virtual memory size
    if [[ -f /proc/self/status ]]; then
        local vsize
        vsize=$(grep -oP 'VmSize:\s*\K[0-9]+' /proc/self/status 2>/dev/null || echo "0")
        vsize=$((vsize * 1024))  # Convert KB to bytes

        gauge_create "process_virtual_memory_bytes" "Virtual memory size in bytes"
        gauge_set "process_virtual_memory_bytes" "$vsize"

        local rss
        rss=$(grep -oP 'VmRSS:\s*\K[0-9]+' /proc/self/status 2>/dev/null || echo "0")
        rss=$((rss * 1024))

        gauge_create "process_resident_memory_bytes" "Resident memory size in bytes"
        gauge_set "process_resident_memory_bytes" "$rss"
    fi

    # Open file descriptors
    if [[ -d /proc/self/fd ]]; then
        local open_fds
        open_fds=$(ls /proc/self/fd 2>/dev/null | wc -l)

        gauge_create "process_open_fds" "Number of open file descriptors"
        gauge_set "process_open_fds" "$open_fds"
    fi

    # Max file descriptors
    local max_fds
    max_fds=$(ulimit -n 2>/dev/null || echo "0")
    gauge_create "process_max_fds" "Maximum number of open file descriptors"
    gauge_set "process_max_fds" "$max_fds"

    # Process start time
    if [[ -f /proc/self/stat ]]; then
        local stat
        read -r stat < /proc/self/stat
        local fields=($stat)
        local starttime="${fields[21]:-0}"

        # Get boot time
        local btime
        btime=$(grep -oP 'btime\s+\K[0-9]+' /proc/stat 2>/dev/null || echo "0")

        if [[ "$btime" != "0" && "$starttime" != "0" ]]; then
            local start_seconds
            start_seconds=$(echo "scale=2; $btime + $starttime / 100" | bc 2>/dev/null || echo "0")

            gauge_create "process_start_time_seconds" "Start time of the process since unix epoch in seconds"
            gauge_set "process_start_time_seconds" "$start_seconds"
        fi
    fi

    return 0
}

# =============================================================================
# CONVENIENCE: MEASURE FUNCTION EXECUTION
# =============================================================================

# @pre: metric_name is valid, function_name is callable
# @post: function executed, duration recorded
# @idempotent: depends on function
# @returns: exit code of the function
#
# Measure and record the execution time of a function.
#
# Usage: metrics_measure "function_duration_seconds" my_function arg1 arg2
metrics_measure() {
    local metric_name="$1"
    shift
    local func_name="$1"
    shift

    local timer_id
    timer_id=$(timer_start "$metric_name")

    local exit_code=0
    "$func_name" "$@" || exit_code=$?

    timer_stop "$timer_id" >/dev/null

    return $exit_code
}

# =============================================================================
# API COMPATIBILITY LAYER
# =============================================================================
# These functions provide the simplified API specified for MAINFRAME metrics
# collection. They wrap the more detailed internal implementation above.
# =============================================================================

# Metrics prefix for compatibility layer
MAINFRAME_METRICS_PREFIX="${MAINFRAME_METRICS_PREFIX:-mainframe}"

# Default histogram buckets (Prometheus standard)
METRICS_DEFAULT_BUCKETS=(0.005 0.01 0.025 0.05 0.1 0.25 0.5 1.0 2.5 5.0 10.0)

# @pre: none
# @post: metrics system initialized with given prefix
# @idempotent: yes
# @returns: 0 on success
#
# Initialize the metrics system with an optional prefix.
# All metric names will be prefixed with this value.
#
# Usage: metrics_init [--prefix PREFIX]
# Example: metrics_init --prefix "myapp"
metrics_init() {
    local prefix="$MAINFRAME_METRICS_PREFIX"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prefix)
                prefix="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    MAINFRAME_METRICS_PREFIX="$prefix"
    MAINFRAME_METRICS_ENABLED=1

    # Clear all metrics
    metrics_clear

    return 0
}

# @pre: value >= 0 (counters can only increase)
# @post: counter incremented by value
# @returns: 0 on success
#
# Increment a counter metric.
# Counters can only increase; use gauges for values that can decrease.
#
# Usage: metrics_counter_inc NAME [VALUE] [LABELS...]
# Example: metrics_counter_inc "http_requests_total" 1 method="GET" status="200"
metrics_counter_inc() {
    local name="$1"
    local value="${2:-1}"
    shift 2 2>/dev/null || shift

    # Build labels string
    local labels=""
    if [[ $# -gt 0 ]]; then
        labels=$(metric_labels_format "$@")
    fi

    # Add prefix if not already present
    local full_name="$name"
    if [[ "$name" != "${MAINFRAME_METRICS_PREFIX}_"* ]] && [[ -n "$MAINFRAME_METRICS_PREFIX" ]]; then
        full_name="${MAINFRAME_METRICS_PREFIX}_${name}"
    fi

    # Auto-register if needed
    if [[ -z "${_METRICS_REGISTRY[$full_name]:-}" ]]; then
        metrics_register "$full_name" "counter" ""
    fi

    counter_add "$full_name" "$value" "$labels"
}

# @pre: counter exists
# @post: none (read-only)
# @returns: counter value on stdout
#
# Get the current value of a counter.
#
# Usage: metrics_counter_get NAME [LABELS...]
# Example: value=$(metrics_counter_get "http_requests_total" method="GET")
metrics_counter_get() {
    local name="$1"
    shift
    local labels=""
    if [[ $# -gt 0 ]]; then
        labels=$(metric_labels_format "$@")
    fi

    local full_name="$name"
    if [[ "$name" != "${MAINFRAME_METRICS_PREFIX}_"* ]] && [[ -n "$MAINFRAME_METRICS_PREFIX" ]]; then
        full_name="${MAINFRAME_METRICS_PREFIX}_${name}"
    fi

    counter_get "$full_name" "$labels"
}

# @pre: none
# @post: gauge set to value
# @returns: 0 on success
#
# Set a gauge to a specific value.
# Gauges can go up and down, unlike counters.
#
# Usage: metrics_gauge_set NAME VALUE [LABELS...]
# Example: metrics_gauge_set "active_connections" 42 host="server1"
metrics_gauge_set() {
    local name="$1"
    local value="$2"
    shift 2 2>/dev/null || shift

    local labels=""
    if [[ $# -gt 0 ]]; then
        labels=$(metric_labels_format "$@")
    fi

    local full_name="$name"
    if [[ "$name" != "${MAINFRAME_METRICS_PREFIX}_"* ]] && [[ -n "$MAINFRAME_METRICS_PREFIX" ]]; then
        full_name="${MAINFRAME_METRICS_PREFIX}_${name}"
    fi

    if [[ -z "${_METRICS_REGISTRY[$full_name]:-}" ]]; then
        metrics_register "$full_name" "gauge" ""
    fi

    gauge_set "$full_name" "$value" "$labels"
}

# @pre: gauge exists
# @post: gauge incremented
# @returns: 0 on success
#
# Increment a gauge by a value (default: 1).
#
# Usage: metrics_gauge_inc NAME [VALUE] [LABELS...]
# Example: metrics_gauge_inc "active_requests" 1
metrics_gauge_inc() {
    local name="$1"
    local value="${2:-1}"
    shift 2 2>/dev/null || shift

    local labels=""
    if [[ $# -gt 0 ]]; then
        labels=$(metric_labels_format "$@")
    fi

    local full_name="$name"
    if [[ "$name" != "${MAINFRAME_METRICS_PREFIX}_"* ]] && [[ -n "$MAINFRAME_METRICS_PREFIX" ]]; then
        full_name="${MAINFRAME_METRICS_PREFIX}_${name}"
    fi

    if [[ -z "${_METRICS_REGISTRY[$full_name]:-}" ]]; then
        metrics_register "$full_name" "gauge" ""
    fi

    gauge_add "$full_name" "$value" "$labels"
}

# @pre: gauge exists
# @post: gauge decremented
# @returns: 0 on success
#
# Decrement a gauge by a value (default: 1).
#
# Usage: metrics_gauge_dec NAME [VALUE] [LABELS...]
# Example: metrics_gauge_dec "active_requests" 1
metrics_gauge_dec() {
    local name="$1"
    local value="${2:-1}"
    shift 2 2>/dev/null || shift

    local labels=""
    if [[ $# -gt 0 ]]; then
        labels=$(metric_labels_format "$@")
    fi

    local full_name="$name"
    if [[ "$name" != "${MAINFRAME_METRICS_PREFIX}_"* ]] && [[ -n "$MAINFRAME_METRICS_PREFIX" ]]; then
        full_name="${MAINFRAME_METRICS_PREFIX}_${name}"
    fi

    if [[ -z "${_METRICS_REGISTRY[$full_name]:-}" ]]; then
        metrics_register "$full_name" "gauge" ""
    fi

    gauge_sub "$full_name" "$value" "$labels"
}

# @pre: gauge exists
# @post: none (read-only)
# @returns: gauge value on stdout
#
# Get the current value of a gauge.
#
# Usage: metrics_gauge_get NAME [LABELS...]
# Example: value=$(metrics_gauge_get "active_connections")
metrics_gauge_get() {
    local name="$1"
    shift
    local labels=""
    if [[ $# -gt 0 ]]; then
        labels=$(metric_labels_format "$@")
    fi

    local full_name="$name"
    if [[ "$name" != "${MAINFRAME_METRICS_PREFIX}_"* ]] && [[ -n "$MAINFRAME_METRICS_PREFIX" ]]; then
        full_name="${MAINFRAME_METRICS_PREFIX}_${name}"
    fi

    gauge_get "$full_name" "$labels"
}

# @pre: value is numeric
# @post: histogram observation recorded
# @returns: 0 on success
#
# Record an observation in a histogram.
# Histograms track the distribution of values using configurable buckets.
#
# Usage: metrics_histogram_observe NAME VALUE [LABELS...]
# Example: metrics_histogram_observe "request_duration_seconds" 0.235 method="GET"
metrics_histogram_observe() {
    local name="$1"
    local value="$2"
    shift 2 2>/dev/null || shift

    local labels=""
    if [[ $# -gt 0 ]]; then
        labels=$(metric_labels_format "$@")
    fi

    local full_name="$name"
    if [[ "$name" != "${MAINFRAME_METRICS_PREFIX}_"* ]] && [[ -n "$MAINFRAME_METRICS_PREFIX" ]]; then
        full_name="${MAINFRAME_METRICS_PREFIX}_${name}"
    fi

    if [[ -z "${_METRICS_REGISTRY[$full_name]:-}" ]]; then
        histogram_create "$full_name" "${METRICS_DEFAULT_BUCKETS[*]}" ""
    fi

    histogram_observe "$full_name" "$value" "$labels"
}

# @pre: value is numeric
# @post: summary observation recorded
# @returns: 0 on success
#
# Record an observation in a summary.
# Summaries calculate quantiles over a sliding time window.
#
# Usage: metrics_summary_observe NAME VALUE [LABELS...]
# Example: metrics_summary_observe "request_latency_seconds" 0.123 method="GET"
metrics_summary_observe() {
    local name="$1"
    local value="$2"
    shift 2 2>/dev/null || shift

    local labels=""
    if [[ $# -gt 0 ]]; then
        labels=$(metric_labels_format "$@")
    fi

    local full_name="$name"
    if [[ "$name" != "${MAINFRAME_METRICS_PREFIX}_"* ]] && [[ -n "$MAINFRAME_METRICS_PREFIX" ]]; then
        full_name="${MAINFRAME_METRICS_PREFIX}_${name}"
    fi

    if [[ -z "${_METRICS_REGISTRY[$full_name]:-}" ]]; then
        summary_create "$full_name" ""
    fi

    summary_observe "$full_name" "$value" "$labels"
}

# @pre: metrics have been collected
# @post: Prometheus-format metrics output to stdout
# @returns: 0
#
# Export all metrics in Prometheus text format.
#
# Usage: metrics_export
# Example: metrics_export > /var/lib/prometheus/textfile/myapp.prom
metrics_export() {
    metrics_export_prometheus
}

# @pre: pushgateway_url is valid HTTP(S) URL
# @post: metrics pushed to Prometheus Pushgateway
# @returns: 0 on success, 1 on failure
#
# Push all metrics to a Prometheus Pushgateway.
#
# Usage: metrics_push PUSHGATEWAY_URL [--job JOB] [--instance INSTANCE]
# Example: metrics_push "http://localhost:9091" --job myapp --instance server1
metrics_push() {
    local url="$1"
    local job="${MAINFRAME_METRICS_PREFIX:-mainframe}"
    local instance="${HOSTNAME:-localhost}"
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --job)
                job="$2"
                shift 2
                ;;
            --instance)
                instance="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    metrics_push_gateway "$url" "$job" "$instance"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_METRICS_EXPORTS=(
    # Initialization
    metrics_init
    metrics_register
    metrics_unregister
    metrics_list
    metrics_get
    metrics_clear
    # Counter operations
    metrics_counter_inc
    metrics_counter_get
    counter_create
    counter_inc
    counter_add
    counter_get
    counter_reset
    counter_labels
    # Gauge operations
    metrics_gauge_set
    metrics_gauge_inc
    metrics_gauge_dec
    metrics_gauge_get
    gauge_create
    gauge_set
    gauge_inc
    gauge_dec
    gauge_add
    gauge_sub
    gauge_get
    gauge_labels
    # Histogram operations
    metrics_histogram_observe
    histogram_create
    histogram_observe
    histogram_get_buckets
    histogram_get_sum
    histogram_get_count
    histogram_labels
    histogram_quantile
    # Summary operations
    metrics_summary_observe
    summary_create
    summary_observe
    summary_get_quantiles
    summary_get_sum
    summary_get_count
    # Timer helpers
    timer_start
    timer_stop
    timer_observe
    # Export functions
    metrics_export
    metrics_export_prometheus
    metrics_export_json
    metrics_export_openmetrics
    # Pushgateway
    metrics_push
    metrics_push_gateway
    # HTTP Server
    metrics_serve
    # Utilities
    metrics_update_process
    metrics_measure
    metric_name_valid
    metric_labels_format
    metric_timestamp
)

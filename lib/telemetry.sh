#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/telemetry.sh - Opt-in Anonymous Usage Telemetry
# =============================================================================
# Description: Track MAINFRAME function usage for development insights.
#              Privacy-first design: opt-in only, no PII, local aggregation.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing. Keep the sentinel mutable so tests can reload
# the module with different environment settings.
[[ -n "${_MAINFRAME_TELEMETRY_LOADED:-}" ]] && return 0
_MAINFRAME_TELEMETRY_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Telemetry is DISABLED by default - must explicitly opt in
# Set MAINFRAME_TELEMETRY=1 to enable
# Note: Not readonly to allow testing; value is captured at load time
TELEMETRY_ENABLED="${MAINFRAME_TELEMETRY:-0}"

# Storage directory for telemetry data
TELEMETRY_DIR="${MAINFRAME_TELEMETRY_DIR:-$HOME/.mainframe/telemetry}"

# Session ID (generated once per session)
TELEMETRY_SESSION_ID=""

# Maximum events to buffer before flush
TELEMETRY_BUFFER_SIZE="${MAINFRAME_TELEMETRY_BUFFER_SIZE:-100}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Event buffer (in-memory aggregation)
# shellcheck disable=SC2034
declare -gA _TELEMETRY_COUNTS 2>/dev/null || declare -A _TELEMETRY_COUNTS
# shellcheck disable=SC2034
declare -gA _TELEMETRY_FIRST_SEEN 2>/dev/null || declare -A _TELEMETRY_FIRST_SEEN
# shellcheck disable=SC2034
declare -gA _TELEMETRY_LAST_SEEN 2>/dev/null || declare -A _TELEMETRY_LAST_SEEN
declare -g _TELEMETRY_TOTAL_EVENTS=0
declare -g _TELEMETRY_SESSION_START=""
declare -g _TELEMETRY_INITIALIZED=0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Get current epoch timestamp
_telemetry_now() {
    local ts
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    elif printf -v ts '%(%s)T' -1 2>/dev/null && [[ -n "$ts" ]]; then
        printf '%s' "$ts"
    else
        date +%s
    fi
}

# Get ISO 8601 timestamp
_telemetry_iso() {
    local ts
    if printf -v ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1 2>/dev/null && [[ -n "$ts" ]]; then
        printf '%s' "$ts"
    else
        date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z
    fi
}

# Generate session ID (random hex string)
_telemetry_gen_session_id() {
    local rand
    if [[ -r /dev/urandom ]]; then
        rand=$(head -c 8 /dev/urandom 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
    fi
    # Fallback if urandom failed
    if [[ -z "$rand" ]]; then
        rand=$(printf '%08x%08x' "$((RANDOM * RANDOM))" "$$")
    fi
    printf 'session_%s' "$rand"
}

# Sanitize function name (remove special chars, limit length)
_telemetry_sanitize_name() {
    local name="$1"
    # Remove path components
    name="${name##*/}"
    # Keep only alphanumeric, underscore, hyphen
    name="${name//[^a-zA-Z0-9_-]/_}"
    # Limit length to 64 chars
    printf '%s' "${name:0:64}"
}

# Internal logging (only when debug enabled)
_telemetry_debug() {
    if [[ "${MAINFRAME_TELEMETRY_DEBUG:-0}" == "1" ]]; then
        printf '[telemetry] %s\n' "$*" >&2
    fi
}

# =============================================================================
# PUBLIC API
# =============================================================================

# Check if telemetry is enabled
# Usage: telemetry_enabled && telemetry_track "func_name"
# Returns: 0 if enabled, 1 if disabled
telemetry_enabled() {
    [[ "$TELEMETRY_ENABLED" == "1" ]]
}

# Initialize telemetry session
# Usage: telemetry_init
# Returns: 0 on success, 1 if disabled
telemetry_init() {
    # Skip if disabled
    telemetry_enabled || return 1

    # Skip if already initialized
    [[ "$_TELEMETRY_INITIALIZED" == "1" ]] && return 0

    # Create telemetry directory
    if [[ ! -d "$TELEMETRY_DIR" ]]; then
        mkdir -p "$TELEMETRY_DIR" 2>/dev/null || {
            _telemetry_debug "Failed to create telemetry directory: $TELEMETRY_DIR"
            return 1
        }
    fi

    # Generate session ID
    TELEMETRY_SESSION_ID=$(_telemetry_gen_session_id)

    # Record session start
    _TELEMETRY_SESSION_START=$(_telemetry_now)

    # Reset counters
    _TELEMETRY_COUNTS=()
    _TELEMETRY_FIRST_SEEN=()
    _TELEMETRY_LAST_SEEN=()
    _TELEMETRY_TOTAL_EVENTS=0

    _TELEMETRY_INITIALIZED=1
    _telemetry_debug "Initialized session: $TELEMETRY_SESSION_ID"

    return 0
}

# Track a function call
# Usage: telemetry_track "function_name" [category]
# Arguments:
#   function_name - Name of the function being called
#   category      - Optional category (e.g., "json", "http", "validation")
# Returns: 0 on success, 1 if disabled
telemetry_track() {
    # Skip if disabled
    telemetry_enabled || return 1

    # Auto-initialize if needed
    [[ "$_TELEMETRY_INITIALIZED" != "1" ]] && telemetry_init

    local func_name="${1:-unknown}"
    local category="${2:-general}"

    # Sanitize inputs
    func_name=$(_telemetry_sanitize_name "$func_name")
    category=$(_telemetry_sanitize_name "$category")

    # Build key for aggregation
    local key="${category}:${func_name}"
    local now
    now=$(_telemetry_now)

    # Update counters
    ((_TELEMETRY_COUNTS["$key"]++)) 2>/dev/null || _TELEMETRY_COUNTS["$key"]=1

    # Track first and last seen
    [[ -z "${_TELEMETRY_FIRST_SEEN["$key"]:-}" ]] && _TELEMETRY_FIRST_SEEN["$key"]="$now"
    _TELEMETRY_LAST_SEEN["$key"]="$now"

    # Increment total
    _TELEMETRY_TOTAL_EVENTS=$((_TELEMETRY_TOTAL_EVENTS + 1))

    _telemetry_debug "Tracked: $key (count: ${_TELEMETRY_COUNTS["$key"]})"

    # Auto-flush if buffer is full
    if ((_TELEMETRY_TOTAL_EVENTS >= TELEMETRY_BUFFER_SIZE)); then
        telemetry_flush
    fi

    return 0
}

# Flush aggregated data to disk
# Usage: telemetry_flush
# Returns: 0 on success, 1 on failure
telemetry_flush() {
    # Skip if disabled or not initialized
    telemetry_enabled || return 1
    [[ "$_TELEMETRY_INITIALIZED" != "1" ]] && return 1

    # Skip if nothing to flush
    [[ ${#_TELEMETRY_COUNTS[@]} -eq 0 ]] && return 0

    local flush_time
    flush_time=$(_telemetry_now)
    local flush_iso
    flush_iso=$(_telemetry_iso)

    # Generate filename: YYYY-MM-DD.jsonl
    local date_part
    date_part=$(printf '%(%Y-%m-%d)T' -1 2>/dev/null || date +%Y-%m-%d)
    local output_file="$TELEMETRY_DIR/${date_part}.jsonl"

    # Build aggregated JSON record
    local json_events=""
    local first=true
    local key count first_seen last_seen category func_name

    for key in "${!_TELEMETRY_COUNTS[@]}"; do
        count="${_TELEMETRY_COUNTS[$key]}"
        first_seen="${_TELEMETRY_FIRST_SEEN[$key]:-0}"
        last_seen="${_TELEMETRY_LAST_SEEN[$key]:-0}"

        # Parse category:func_name
        category="${key%%:*}"
        func_name="${key#*:}"

        $first || json_events+=","
        first=false
        json_events+="{\"c\":\"$category\",\"f\":\"$func_name\",\"n\":$count,\"t1\":$first_seen,\"t2\":$last_seen}"
    done

    # Write aggregated record
    local json_line
    json_line="{\"v\":1,\"sid\":\"$TELEMETRY_SESSION_ID\",\"ts\":$flush_time,\"iso\":\"$flush_iso\",\"total\":$_TELEMETRY_TOTAL_EVENTS,\"events\":[$json_events]}"

    if printf '%s\n' "$json_line" >> "$output_file" 2>/dev/null; then
        _telemetry_debug "Flushed $_TELEMETRY_TOTAL_EVENTS events to $output_file"

        # Reset counters after successful flush
        _TELEMETRY_COUNTS=()
        _TELEMETRY_FIRST_SEEN=()
        _TELEMETRY_LAST_SEEN=()
        _TELEMETRY_TOTAL_EVENTS=0

        return 0
    else
        _telemetry_debug "Failed to write to $output_file"
        return 1
    fi
}

# Generate usage report from telemetry data
# Usage: telemetry_report [days]
# Arguments:
#   days - Number of days to include (default: 7)
# Output: Human-readable report to stdout, JSON if --json flag
telemetry_report() {
    local days="${1:-7}"
    local json_mode=0

    # Check for --json flag
    if [[ "$1" == "--json" ]]; then
        json_mode=1
        days="${2:-7}"
    fi

    # Validate days is a number
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        printf 'Error: days must be a positive integer\n' >&2
        return 1
    fi

    # Check if telemetry directory exists
    if [[ ! -d "$TELEMETRY_DIR" ]]; then
        if [[ $json_mode -eq 1 ]]; then
            printf '{"error":"no_data","message":"No telemetry data found"}\n'
        else
            printf 'No telemetry data found at %s\n' "$TELEMETRY_DIR"
        fi
        return 1
    fi

    # Aggregate data from files
    declare -A func_counts
    declare -A category_counts
    local total_calls=0
    local files_processed=0
    local sessions_seen=""

    # Calculate date range
    local today_epoch
    today_epoch=$(_telemetry_now)
    local start_epoch=$((today_epoch - (days * 86400)))

    # Process each JSONL file
    local file date_str file_epoch
    for file in "$TELEMETRY_DIR"/*.jsonl; do
        [[ -f "$file" ]] || continue

        # Extract date from filename
        date_str="${file##*/}"
        date_str="${date_str%.jsonl}"

        # Skip files outside date range (simple comparison)
        # Parse date to epoch for comparison
        if [[ "$date_str" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]]; then
            local year="${BASH_REMATCH[1]}"
            local month="${BASH_REMATCH[2]#0}"
            local day="${BASH_REMATCH[3]#0}"

            # Approximate epoch calculation (good enough for day comparison)
            # Days since 1970-01-01
            local days_since_epoch=$(( (year - 1970) * 365 + (year - 1969) / 4 ))
            local m
            for ((m=1; m<month; m++)); do
                case $m in
                    1|3|5|7|8|10|12) days_since_epoch=$((days_since_epoch + 31)) ;;
                    4|6|9|11) days_since_epoch=$((days_since_epoch + 30)) ;;
                    2) days_since_epoch=$((days_since_epoch + 28)) ;;
                esac
            done
            days_since_epoch=$((days_since_epoch + day))
            file_epoch=$((days_since_epoch * 86400))

            [[ $file_epoch -lt $start_epoch ]] && continue
        fi

        files_processed=$((files_processed + 1))

        # Parse each line (JSONL format)
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue

            # Extract session ID
            local sid
            if [[ "$line" =~ \"sid\":\"([^\"]+)\" ]]; then
                sid="${BASH_REMATCH[1]}"
                [[ "$sessions_seen" != *"$sid"* ]] && sessions_seen+="$sid "
            fi

            # Extract total
            local line_total
            if [[ "$line" =~ \"total\":([0-9]+) ]]; then
                line_total="${BASH_REMATCH[1]}"
                total_calls=$((total_calls + line_total))
            fi

            # Extract events array and parse
            if [[ "$line" =~ \"events\":\[([^\]]*)\] ]]; then
                local events_str="${BASH_REMATCH[1]}"

                # Parse each event object
                while [[ "$events_str" =~ \{\"c\":\"([^\"]+)\",\"f\":\"([^\"]+)\",\"n\":([0-9]+) ]]; do
                    local cat="${BASH_REMATCH[1]}"
                    local func="${BASH_REMATCH[2]}"
                    local count="${BASH_REMATCH[3]}"

                    func_counts["$func"]=$(( ${func_counts["$func"]:-0} + count ))
                    category_counts["$cat"]=$(( ${category_counts["$cat"]:-0} + count ))

                    # Remove matched portion to continue parsing
                    events_str="${events_str#*\}}"
                done
            fi
        done < "$file"
    done

    # Count unique sessions (word splitting is intentional here)
    local session_count=0
    local s
    # shellcheck disable=SC2086,SC2034
    for s in $sessions_seen; do
        session_count=$((session_count + 1))
    done

    # Output report
    if [[ $json_mode -eq 1 ]]; then
        # JSON output
        local func_json=""
        local cat_json=""
        local first=true

        for func in "${!func_counts[@]}"; do
            $first || func_json+=","
            first=false
            func_json+="{\"name\":\"$func\",\"count\":${func_counts[$func]}}"
        done

        first=true
        for cat in "${!category_counts[@]}"; do
            $first || cat_json+=","
            first=false
            cat_json+="{\"name\":\"$cat\",\"count\":${category_counts[$cat]}}"
        done

        printf '{"days":%d,"total_calls":%d,"sessions":%d,"files":%d,"functions":[%s],"categories":[%s]}\n' \
            "$days" "$total_calls" "$session_count" "$files_processed" "$func_json" "$cat_json"
    else
        # Human-readable output
        printf '\n'
        printf '=%.0s' {1..60}
        printf '\n'
        printf 'MAINFRAME Telemetry Report (Last %d days)\n' "$days"
        printf '=%.0s' {1..60}
        printf '\n\n'

        printf 'Summary:\n'
        printf '  Total function calls: %d\n' "$total_calls"
        printf '  Unique sessions:      %d\n' "$session_count"
        printf '  Data files processed: %d\n' "$files_processed"
        printf '\n'

        if [[ ${#category_counts[@]} -gt 0 ]]; then
            printf 'Calls by Category:\n'
            for cat in "${!category_counts[@]}"; do
                printf '  %-20s %d\n' "$cat" "${category_counts[$cat]}"
            done | sort -t' ' -k2 -rn
            printf '\n'
        fi

        if [[ ${#func_counts[@]} -gt 0 ]]; then
            printf 'Top Functions (by call count):\n'
            for func in "${!func_counts[@]}"; do
                printf '  %-30s %d\n' "$func" "${func_counts[$func]}"
            done | sort -t' ' -k2 -rn | head -20
            printf '\n'
        fi

        printf '=%.0s' {1..60}
        printf '\n'
    fi

    return 0
}

# =============================================================================
# CLEANUP
# =============================================================================

# Flush on exit if telemetry is enabled
_telemetry_cleanup() {
    if telemetry_enabled && [[ "$_TELEMETRY_INITIALIZED" == "1" ]]; then
        telemetry_flush
    fi
}

# Register cleanup handler (only if we're not being sourced for testing)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    if declare -F _mainframe_add_exit_trap >/dev/null 2>&1; then
        _mainframe_add_exit_trap "_telemetry_cleanup"
    else
        trap _telemetry_cleanup EXIT
    fi
fi

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# shellcheck disable=SC2034  # Used by MAINFRAME lazy loading system
TELEMETRY_EXPORTS=(
    telemetry_enabled
    telemetry_init
    telemetry_track
    telemetry_flush
    telemetry_report
)

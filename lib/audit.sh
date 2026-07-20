#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/audit.sh - Compliance Audit Logging for Enterprise Deployments
# =============================================================================
# Description: SOC 2 and GDPR compliant audit logging with tamper-evident chains,
#              cryptographic signing, retention policies, and SIEM-compatible export.
# Version: 1.0.0
# Requires: Bash 4.0+, openssl for cryptographic operations
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_AUDIT_LOADED:-}" ]] && return 0
readonly _MAINFRAME_AUDIT_LOADED=1


# Portable SHA-256 digest (sha256sum -> shasum -> openssl fallback chain).
# Shared micro-shim: the declare -F guard means it is defined once per
# process no matter how many MAINFRAME libraries are sourced.
if ! declare -F _mainframe_sha256 &>/dev/null; then
_mainframe_sha256() {
    if command -v sha256sum &>/dev/null; then
        sha256sum "$@"
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$@"
    else
        openssl dgst -sha256 "$@" | sed 's/^.* //'
    fi
}
fi

# =============================================================================
# CONSTANTS
# =============================================================================

readonly _AUDIT_VERSION="1.0.0"
readonly _AUDIT_DEFAULT_LOG="/var/log/audit.jsonl"
readonly _AUDIT_ID_PREFIX="aud_"
readonly _AUDIT_SIGN_ALGORITHM="sha256"
readonly _AUDIT_DEFAULT_RETENTION_DAYS=90
readonly _AUDIT_INDEX_SUFFIX=".idx"
readonly _AUDIT_SIGN_SUFFIX=".sig"

# Alert conditions
readonly _AUDIT_ALERT_FAILURE_THRESHOLD=10
readonly _AUDIT_ALERT_INTERVAL_SECONDS=60

# =============================================================================
# STATE VARIABLES
# =============================================================================

# Audit configuration (can be modified via audit_init)
declare -g _AUDIT_OUTPUT="${_AUDIT_DEFAULT_LOG}"
declare -g _AUDIT_SIGN_ENABLED=0
declare -g _AUDIT_HMAC_KEY=""
declare -g _AUDIT_LAST_HASH=""
declare -g _AUDIT_SESSION_ID=""
declare -g _AUDIT_RETENTION_DAYS="${_AUDIT_DEFAULT_RETENTION_DAYS}"
declare -g _AUDIT_INITIALIZED=0

# Audit log rotation: cap size, keep N generations (chain-aware)
declare -g AUDIT_MAX_BYTES="${AUDIT_MAX_BYTES:-10485760}"   # 10MB
declare -g AUDIT_KEEP="${AUDIT_KEEP:-5}"

# Index cache for efficient querying
declare -gA _AUDIT_ACTOR_INDEX
declare -gA _AUDIT_ACTION_INDEX
declare -gA _AUDIT_RESOURCE_INDEX

# Alert configuration
declare -ga _AUDIT_ALERTS=()

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Internal logging
_audit_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "audit" "$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[audit] %s: %s\n' "$level" "$*" >&2
    fi
}

# Generate unique audit entry ID
# Usage: _audit_generate_id
_audit_generate_id() {
    local timestamp random_hex
    timestamp=$(printf '%(%s)T' -1)

    if [[ -r /dev/urandom ]]; then
        random_hex=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
    else
        random_hex=$(printf '%08x' $RANDOM$RANDOM)
    fi

    printf '%s%s_%s' "$_AUDIT_ID_PREFIX" "$timestamp" "$random_hex"
}

# Get current ISO 8601 timestamp with milliseconds
# Usage: _audit_timestamp
_audit_timestamp() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        # Bash 5.0+ with microseconds
        local epoch_real="$EPOCHREALTIME"
        local seconds="${epoch_real%%.*}"
        local frac="${epoch_real#*.}"
        frac="${frac}000"
        local ms="${frac:0:3}"
        printf '%(%Y-%m-%dT%H:%M:%S)T.%sZ' "$seconds" "$ms"
    else
        # Fallback without milliseconds
        printf '%(%Y-%m-%dT%H:%M:%SZ)T' -1
    fi
}

# Compute SHA-256 hash of a string
# Usage: _audit_hash "string"
_audit_hash() {
    local input="$1"

    if type -p sha256sum &>/dev/null; then
        printf '%s' "$input" | _mainframe_sha256 | cut -d' ' -f1
    elif type -p shasum &>/dev/null; then
        printf '%s' "$input" | shasum -a 256 | cut -d' ' -f1
    elif type -p openssl &>/dev/null; then
        printf '%s' "$input" | openssl dgst -sha256 | awk '{print $NF}'
    else
        _audit_log "error" "No hash tool available"
        return 1
    fi
}

# Compute HMAC-SHA256 signature
# Usage: _audit_hmac "key" "message"
_audit_hmac() {
    local key="$1"
    local message="$2"

    if ! type -p openssl &>/dev/null; then
        _audit_log "error" "openssl required for HMAC signing"
        return 1
    fi

    printf '%s' "$message" | openssl dgst -sha256 -hmac "$key" | awk '{print $NF}'
}

# Ensure parent directory exists
# Usage: _audit_ensure_dir "path"
_audit_ensure_dir() {
    local path="$1"
    local dir="${path%/*}"

    if [[ "$dir" != "$path" && ! -d "$dir" ]]; then
        mkdir -p "$dir" 2>/dev/null || {
            _audit_log "error" "Failed to create directory: $dir"
            return 1
        }
    fi
}

# JSON escape string (delegate to json.sh if available)
_audit_json_escape() {
    local str="$1"

    if declare -F json_escape &>/dev/null; then
        json_escape "$str"
    else
        # Fallback: basic escaping
        str="${str//\\/\\\\}"
        str="${str//\"/\\\"}"
        str="${str//$'\n'/\\n}"
        str="${str//$'\r'/\\r}"
        str="${str//$'\t'/\\t}"
        printf '%s' "$str"
    fi
}

# Check if pattern matches value (supports glob patterns with *)
# Usage: _audit_pattern_match "agent-*" "agent-123"
_audit_pattern_match() {
    local pattern="$1"
    local value="$2"

    # Convert glob pattern to regex
    local regex="${pattern//\*/.*}"
    regex="^${regex}$"

    [[ "$value" =~ $regex ]]
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize audit log system
# Usage: audit_init --output "/var/log/audit.jsonl" --sign true --hmac-key "secret"
# Options:
#   --output PATH      Path to audit log file (default: /var/log/audit.jsonl)
#   --sign BOOL        Enable cryptographic signing (default: false)
#   --hmac-key KEY     HMAC key for signing (required if --sign true)
#   --session-id ID    Session ID for context (auto-generated if not provided)
#   --retention DAYS   Retention period in days (default: 90)
audit_init() {
    # Use existing _AUDIT_OUTPUT if set, otherwise use default
    local output="${_AUDIT_OUTPUT:-${_AUDIT_DEFAULT_LOG}}"
    local sign_enabled=0
    local hmac_key=""
    local session_id=""
    local retention="${_AUDIT_DEFAULT_RETENTION_DAYS}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output)
                output="$2"
                shift 2
                ;;
            --sign)
                case "${2,,}" in
                    true|1|yes|on) sign_enabled=1 ;;
                    *) sign_enabled=0 ;;
                esac
                shift 2
                ;;
            --hmac-key)
                hmac_key="$2"
                shift 2
                ;;
            --session-id)
                session_id="$2"
                shift 2
                ;;
            --retention)
                retention="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Validate signing configuration
    if [[ $sign_enabled -eq 1 && -z "$hmac_key" ]]; then
        _audit_log "error" "HMAC key required when signing is enabled"
        return 1
    fi

    # Generate session ID if not provided
    if [[ -z "$session_id" ]]; then
        session_id="sess_$(printf '%(%s)T' -1)_$(head -c 4 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' || printf '%04x' $RANDOM)"
    fi

    # Ensure output directory exists
    _audit_ensure_dir "$output" || return 1

    # Initialize last hash from existing log
    if [[ -f "$output" ]]; then
        local last_line
        last_line=$(tail -n 1 "$output" 2>/dev/null)
        if [[ -n "$last_line" ]]; then
            _AUDIT_LAST_HASH=$(_audit_hash "$last_line")
        else
            _AUDIT_LAST_HASH=""
        fi
    else
        _AUDIT_LAST_HASH=""
    fi

    # Set global configuration
    _AUDIT_OUTPUT="$output"
    _AUDIT_SIGN_ENABLED=$sign_enabled
    _AUDIT_HMAC_KEY="$hmac_key"
    _AUDIT_SESSION_ID="$session_id"
    _AUDIT_RETENTION_DAYS=$retention
    _AUDIT_INITIALIZED=1

    # Clear index caches
    _AUDIT_ACTOR_INDEX=()
    _AUDIT_ACTION_INDEX=()
    _AUDIT_RESOURCE_INDEX=()

    _audit_log "info" "Audit initialized: output=$output, sign=$sign_enabled, session=$session_id"
    return 0
}

# =============================================================================
# CORE LOGGING
# =============================================================================

# Log an audit entry
# Usage: audit_log "action" "actor" "resource" "result" [details...]
# Example: audit_log "file_write" "agent-123" "/tmp/output.json" "success" "bytes_written=1024" "duration_ms=50"
#
# Parameters:
#   action   - The operation performed (e.g., file_write, api_call, config_change)
#   actor    - Who performed the action (e.g., agent ID, user ID)
#   resource - The target of the action (e.g., file path, API endpoint)
#   result   - Outcome: success, failure, partial, denied
#   details  - Optional key=value pairs for additional context
#
# Actor format: Can include type and roles as "type:id:role1,role2"
#              Example: "agent:agent-123:operator,admin"

# Rotate the audit log when it exceeds AUDIT_MAX_BYTES, keeping
# AUDIT_KEEP numbered generations (file.1 = most recent archive).
# Chain-aware: the new file begins with a rotation marker recording the
# previous file's final chain hash so verification can follow (or
# explicitly reject) cross-file chains instead of failing mysteriously.
# For manual/full rotation with archiving, see audit_rotate().
# Usage: audit_rotate_if_needed [file] [max_bytes] [keep]
audit_rotate_if_needed() {
    local file="${1:-$_AUDIT_OUTPUT}"
    local max_bytes="${2:-$AUDIT_MAX_BYTES}"
    local keep="${3:-$AUDIT_KEEP}"

    [[ -f "$file" ]] || return 0

    local size
    size=$(wc -c < "$file" 2>/dev/null | tr -d '[:space:]')
    [[ "$size" =~ ^[0-9]+$ ]] || return 0
    (( size < max_bytes )) && return 0

    local i
    for (( i=keep-1; i>=1; i-- )); do
        [[ -f "$file.$i" ]] && mv -f "$file.$i" "$file.$((i+1))"
    done
    mv -f "$file" "$file.1"

    local ts
    ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    printf '{"timestamp":"%s","action":"audit_rotated","previous_file":"%s","previous_chain_hash":"%s"}\n' \
        "$ts" "${file}.1" "${_AUDIT_LAST_HASH:-genesis}" > "$file"

    _audit_log "info" "Audit log rotated: $file (size cap $max_bytes bytes)"
    return 0
}

audit_log() {
    if [[ $_AUDIT_INITIALIZED -ne 1 ]]; then
        # Auto-initialize with defaults
        audit_init || return 1
    fi

    local action="$1"
    local actor_raw="$2"
    local resource="$3"
    local result="$4"
    shift 4

    # Validate required parameters
    if [[ -z "$action" || -z "$actor_raw" || -z "$resource" || -z "$result" ]]; then
        _audit_log "error" "Missing required parameter: action, actor, resource, and result are required"
        return 1
    fi

    # Validate result
    case "$result" in
        success|failure|partial|denied) ;;
        *)
            _audit_log "warn" "Invalid result '$result', using 'failure'"
            result="failure"
            ;;
    esac

    # Parse actor (format: type:id:roles or just id)
    local actor_type="unknown" actor_id="$actor_raw" actor_roles=""
    if [[ "$actor_raw" =~ ^([^:]+):([^:]+):?(.*)$ ]]; then
        actor_type="${BASH_REMATCH[1]}"
        actor_id="${BASH_REMATCH[2]}"
        actor_roles="${BASH_REMATCH[3]}"
    fi

    # Build roles array
    local roles_json="[]"
    if [[ -n "$actor_roles" ]]; then
        local IFS=','
        local -a roles=($actor_roles)
        local roles_items=""
        local first=true
        for role in "${roles[@]}"; do
            $first || roles_items+=","
            first=false
            roles_items+="\"$(_audit_json_escape "$role")\""
        done
        roles_json="[$roles_items]"
    fi

    # Parse resource (format: type:path or just path)
    local resource_type="file" resource_path="$resource"
    if [[ "$resource" =~ ^([^:]+):(.+)$ ]]; then
        resource_type="${BASH_REMATCH[1]}"
        resource_path="${BASH_REMATCH[2]}"
    fi

    # Build details object
    local details_json="{"
    local details_first=true
    for detail in "$@"; do
        if [[ "$detail" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            $details_first || details_json+=","
            details_first=false

            # Try to detect numeric values
            if [[ "$value" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
                details_json+="\"$(_audit_json_escape "$key")\":$value"
            else
                details_json+="\"$(_audit_json_escape "$key")\":\"$(_audit_json_escape "$value")\""
            fi
        fi
    done
    details_json+="}"

    # Generate entry
    local entry_id timestamp
    entry_id=$(_audit_generate_id)
    timestamp=$(_audit_timestamp)

    # Build chain hash (previous entry hash)
    local chain_hash="${_AUDIT_LAST_HASH:-genesis}"

    # Build entry JSON
    local entry="{"
    entry+="\"id\":\"$entry_id\","
    entry+="\"timestamp\":\"$timestamp\","
    entry+="\"action\":\"$(_audit_json_escape "$action")\","
    entry+="\"actor\":{"
    entry+="\"type\":\"$(_audit_json_escape "$actor_type")\","
    entry+="\"id\":\"$(_audit_json_escape "$actor_id")\","
    entry+="\"roles\":$roles_json"
    entry+="},"
    entry+="\"resource\":{"
    entry+="\"type\":\"$(_audit_json_escape "$resource_type")\","
    entry+="\"path\":\"$(_audit_json_escape "$resource_path")\""
    entry+="},"
    entry+="\"result\":\"$result\","
    entry+="\"details\":$details_json,"
    entry+="\"context\":{"
    entry+="\"session_id\":\"$_AUDIT_SESSION_ID\","
    entry+="\"trace_id\":\"trace_$entry_id\","
    entry+="\"ip\":\"${SSH_CLIENT%% *:-127.0.0.1}\""
    entry+="},"
    entry+="\"chain_hash\":\"$chain_hash\""

    # Add signature if enabled
    if [[ $_AUDIT_SIGN_ENABLED -eq 1 ]]; then
        local signature
        signature=$(_audit_hmac "$_AUDIT_HMAC_KEY" "$entry")
        entry+=",\"signature\":\"sha256:$signature\""
    fi

    entry+="}"

    # Compute hash for chain
    local entry_hash
    entry_hash=$(_audit_hash "$entry")

    # Add entry hash
    entry="${entry%\}},\"hash\":\"sha256:$entry_hash\"}"

    # Write to log file (rotate first when the size cap is exceeded)
    audit_rotate_if_needed "$_AUDIT_OUTPUT"
    printf '%s\n' "$entry" >> "$_AUDIT_OUTPUT" || {
        _audit_log "error" "Failed to write audit entry"
        return 1
    }

    # Update chain
    _AUDIT_LAST_HASH="$entry_hash"

    # Update indices for querying
    _AUDIT_ACTOR_INDEX["$actor_id"]+="$entry_id "
    _AUDIT_ACTION_INDEX["$action"]+="$entry_id "
    _AUDIT_RESOURCE_INDEX["$resource_path"]+="$entry_id "

    # Check alerts
    _audit_check_alerts "$action" "$result"

    return 0
}

# =============================================================================
# QUERYING
# =============================================================================

# Query audit log entries
# Usage: audit_query [OPTIONS]
# Options:
#   --actor PATTERN    Filter by actor ID (supports glob patterns with *)
#   --action PATTERN   Filter by action (supports | for OR)
#   --resource PATTERN Filter by resource path (supports glob patterns)
#   --result RESULT    Filter by result (success|failure|partial|denied)
#   --since DATE       Filter entries after date (ISO 8601 or epoch)
#   --until DATE       Filter entries before date (ISO 8601 or epoch)
#   --limit N          Maximum entries to return (default: 100)
#   --format FORMAT    Output format: json|jsonl|table (default: jsonl)
audit_query() {
    if [[ $_AUDIT_INITIALIZED -ne 1 ]]; then
        audit_init || return 1
    fi

    local actor_pattern="" action_pattern="" resource_pattern="" result_filter=""
    local since_epoch=0 until_epoch=9999999999
    local limit=100 format="jsonl"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --actor)
                actor_pattern="$2"
                shift 2
                ;;
            --action)
                action_pattern="$2"
                shift 2
                ;;
            --resource)
                resource_pattern="$2"
                shift 2
                ;;
            --result)
                result_filter="$2"
                shift 2
                ;;
            --since)
                local since_date="$2"
                if [[ "$since_date" =~ ^[0-9]+$ ]]; then
                    since_epoch="$since_date"
                else
                    # Parse ISO date
                    since_epoch=$(date -d "$since_date" +%s 2>/dev/null || echo 0)
                fi
                shift 2
                ;;
            --until)
                local until_date="$2"
                if [[ "$until_date" =~ ^[0-9]+$ ]]; then
                    until_epoch="$until_date"
                else
                    until_epoch=$(date -d "$until_date" +%s 2>/dev/null || echo 9999999999)
                fi
                shift 2
                ;;
            --limit)
                limit="$2"
                shift 2
                ;;
            --format)
                format="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ ! -f "$_AUDIT_OUTPUT" ]]; then
        case "$format" in
            json) printf '[]\n' ;;
            table) printf 'No audit entries found\n' ;;
            *) ;;
        esac
        return 0
    fi

    local count=0
    local -a results=()

    # Read and filter entries
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ $count -ge $limit ]] && break

        # Extract fields for filtering using json_get or regex
        local entry_actor entry_action entry_resource entry_result entry_timestamp

        if declare -F json_get &>/dev/null; then
            # Get nested values - actor.id
            if [[ "$line" =~ \"actor\":\{[^}]*\"id\":\"([^\"]+)\" ]]; then
                entry_actor="${BASH_REMATCH[1]}"
            fi
            if [[ "$line" =~ \"action\":\"([^\"]+)\" ]]; then
                entry_action="${BASH_REMATCH[1]}"
            fi
            if [[ "$line" =~ \"resource\":\{[^}]*\"path\":\"([^\"]+)\" ]]; then
                entry_resource="${BASH_REMATCH[1]}"
            fi
            if [[ "$line" =~ \"result\":\"([^\"]+)\" ]]; then
                entry_result="${BASH_REMATCH[1]}"
            fi
            if [[ "$line" =~ \"timestamp\":\"([^\"]+)\" ]]; then
                entry_timestamp="${BASH_REMATCH[1]}"
            fi
        else
            # Fallback regex extraction
            [[ "$line" =~ \"actor\":\{[^}]*\"id\":\"([^\"]+)\" ]] && entry_actor="${BASH_REMATCH[1]}"
            [[ "$line" =~ \"action\":\"([^\"]+)\" ]] && entry_action="${BASH_REMATCH[1]}"
            [[ "$line" =~ \"resource\":\{[^}]*\"path\":\"([^\"]+)\" ]] && entry_resource="${BASH_REMATCH[1]}"
            [[ "$line" =~ \"result\":\"([^\"]+)\" ]] && entry_result="${BASH_REMATCH[1]}"
            [[ "$line" =~ \"timestamp\":\"([^\"]+)\" ]] && entry_timestamp="${BASH_REMATCH[1]}"
        fi

        # Apply filters
        if [[ -n "$actor_pattern" ]]; then
            _audit_pattern_match "$actor_pattern" "$entry_actor" || continue
        fi

        if [[ -n "$action_pattern" ]]; then
            local action_match=false
            local IFS='|'
            for pattern in $action_pattern; do
                if _audit_pattern_match "$pattern" "$entry_action"; then
                    action_match=true
                    break
                fi
            done
            $action_match || continue
        fi

        if [[ -n "$resource_pattern" ]]; then
            _audit_pattern_match "$resource_pattern" "$entry_resource" || continue
        fi

        if [[ -n "$result_filter" && "$entry_result" != "$result_filter" ]]; then
            continue
        fi

        # Time-based filtering
        if [[ -n "$entry_timestamp" ]]; then
            local entry_epoch
            entry_epoch=$(date -d "$entry_timestamp" +%s 2>/dev/null || echo 0)
            [[ $entry_epoch -lt $since_epoch ]] && continue
            [[ $entry_epoch -gt $until_epoch ]] && continue
        fi

        results+=("$line")
        ((count++))

    done < "$_AUDIT_OUTPUT"

    # Output results
    case "$format" in
        json)
            printf '['
            local first=true
            for entry in "${results[@]}"; do
                $first || printf ','
                first=false
                printf '%s' "$entry"
            done
            printf ']\n'
            ;;
        table)
            printf '%-12s %-20s %-15s %-30s %-10s\n' "ID" "TIMESTAMP" "ACTOR" "ACTION" "RESULT"
            printf '%s\n' "$(printf '%.0s-' {1..90})"
            for entry in "${results[@]}"; do
                local id action actor result timestamp
                [[ "$entry" =~ \"id\":\"([^\"]+)\" ]] && id="${BASH_REMATCH[1]}"
                [[ "$entry" =~ \"action\":\"([^\"]+)\" ]] && action="${BASH_REMATCH[1]}"
                [[ "$entry" =~ \"actor\":\{[^}]*\"id\":\"([^\"]+)\" ]] && actor="${BASH_REMATCH[1]}"
                [[ "$entry" =~ \"result\":\"([^\"]+)\" ]] && result="${BASH_REMATCH[1]}"
                [[ "$entry" =~ \"timestamp\":\"([^\"]+)\" ]] && timestamp="${BASH_REMATCH[1]}"
                printf '%-12s %-20s %-15s %-30s %-10s\n' \
                    "${id:0:12}" "${timestamp:0:20}" "${actor:0:15}" "${action:0:30}" "$result"
            done
            ;;
        *)
            for entry in "${results[@]}"; do
                printf '%s\n' "$entry"
            done
            ;;
    esac

    return 0
}

# =============================================================================
# EXPORT
# =============================================================================

# Export audit log to file
# Usage: audit_export "output.csv" --format csv|json|jsonl
# Options:
#   --format FORMAT    Export format: csv, json, jsonl (default: jsonl)
#   --since DATE       Export entries after date
#   --until DATE       Export entries before date
audit_export() {
    local output_file="$1"
    shift

    if [[ -z "$output_file" ]]; then
        _audit_log "error" "Output file path required"
        return 1
    fi

    local format="jsonl"
    local since="" until=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format)
                format="$2"
                shift 2
                ;;
            --since)
                since="$2"
                shift 2
                ;;
            --until)
                until="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Build query options
    local -a query_opts=(--limit 999999999 --format "$format")
    [[ -n "$since" ]] && query_opts+=(--since "$since")
    [[ -n "$until" ]] && query_opts+=(--until "$until")

    case "$format" in
        csv)
            # CSV header
            printf 'id,timestamp,action,actor_type,actor_id,resource_type,resource_path,result\n' > "$output_file"

            # Query and convert to CSV
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue

                local id timestamp action actor_type actor_id resource_type resource_path result
                [[ "$line" =~ \"id\":\"([^\"]+)\" ]] && id="${BASH_REMATCH[1]}"
                [[ "$line" =~ \"timestamp\":\"([^\"]+)\" ]] && timestamp="${BASH_REMATCH[1]}"
                [[ "$line" =~ \"action\":\"([^\"]+)\" ]] && action="${BASH_REMATCH[1]}"
                [[ "$line" =~ \"actor\":\{[^}]*\"type\":\"([^\"]+)\" ]] && actor_type="${BASH_REMATCH[1]}"
                [[ "$line" =~ \"actor\":\{[^}]*\"id\":\"([^\"]+)\" ]] && actor_id="${BASH_REMATCH[1]}"
                [[ "$line" =~ \"resource\":\{[^}]*\"type\":\"([^\"]+)\" ]] && resource_type="${BASH_REMATCH[1]}"
                [[ "$line" =~ \"resource\":\{[^}]*\"path\":\"([^\"]+)\" ]] && resource_path="${BASH_REMATCH[1]}"
                [[ "$line" =~ \"result\":\"([^\"]+)\" ]] && result="${BASH_REMATCH[1]}"

                # Escape CSV fields (double quotes)
                resource_path="${resource_path//\"/\"\"}"

                printf '"%s","%s","%s","%s","%s","%s","%s","%s"\n' \
                    "$id" "$timestamp" "$action" "$actor_type" "$actor_id" \
                    "$resource_type" "$resource_path" "$result" >> "$output_file"
            done < "$_AUDIT_OUTPUT"
            ;;
        json)
            audit_query "${query_opts[@]}" > "$output_file"
            ;;
        jsonl|*)
            query_opts=(--limit 999999999 --format jsonl)
            [[ -n "$since" ]] && query_opts+=(--since "$since")
            [[ -n "$until" ]] && query_opts+=(--until "$until")
            audit_query "${query_opts[@]}" > "$output_file"
            ;;
    esac

    _audit_log "info" "Exported audit log to $output_file (format: $format)"
    return 0
}

# =============================================================================
# SIGNING AND VERIFICATION
# =============================================================================

# Sign the audit log file
# Usage: audit_sign "audit.jsonl" [--key "hmac_key"]
# Creates a .sig file with the signature
audit_sign() {
    local log_file="${1:-$_AUDIT_OUTPUT}"
    local hmac_key="${_AUDIT_HMAC_KEY}"

    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key)
                hmac_key="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ ! -f "$log_file" ]]; then
        _audit_log "error" "Log file not found: $log_file"
        return 1
    fi

    if [[ -z "$hmac_key" ]]; then
        _audit_log "error" "HMAC key required for signing"
        return 1
    fi

    # Compute file hash
    local file_hash
    file_hash=$(_audit_hash "$(cat "$log_file")")

    # Compute HMAC signature
    local signature
    signature=$(_audit_hmac "$hmac_key" "$file_hash")

    local sig_file="${log_file}${_AUDIT_SIGN_SUFFIX}"
    local timestamp
    timestamp=$(_audit_timestamp)

    # Create signature file
    printf '{"file":"%s","hash":"sha256:%s","signature":"sha256:%s","timestamp":"%s","algorithm":"%s"}\n' \
        "$(_audit_json_escape "$log_file")" \
        "$file_hash" \
        "$signature" \
        "$timestamp" \
        "$_AUDIT_SIGN_ALGORITHM" > "$sig_file"

    _audit_log "info" "Signed audit log: $sig_file"
    return 0
}

# Verify audit log integrity
# Usage: audit_verify "audit.jsonl" [--key "hmac_key"]
# Checks:
#   1. Chain hash integrity (each entry links to previous)
#   2. Individual entry signatures (if signing was enabled)
#   3. File signature (if .sig file exists)
audit_verify() {
    local log_file="${1:-$_AUDIT_OUTPUT}"
    local hmac_key="${_AUDIT_HMAC_KEY}"
    local verbose=0

    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key)
                hmac_key="$2"
                shift 2
                ;;
            --verbose|-v)
                verbose=1
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ ! -f "$log_file" ]]; then
        _audit_log "error" "Log file not found: $log_file"
        return 1
    fi

    local entry_count=0
    local chain_valid=true
    local signatures_valid=true
    local expected_chain_hash="genesis"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ((entry_count++))

        # Extract chain hash from entry
        local entry_chain_hash entry_hash
        if [[ "$line" =~ \"chain_hash\":\"([^\"]+)\" ]]; then
            entry_chain_hash="${BASH_REMATCH[1]}"
        fi
        if [[ "$line" =~ \"hash\":\"sha256:([^\"]+)\" ]]; then
            entry_hash="${BASH_REMATCH[1]}"
        fi

        # Verify chain
        if [[ "$entry_chain_hash" != "$expected_chain_hash" ]]; then
            [[ $verbose -eq 1 ]] && _audit_log "error" "Chain broken at entry $entry_count"
            chain_valid=false
        fi

        # Verify entry hash matches content
        if [[ -n "$entry_hash" ]]; then
            # Compute hash of the entry (including signature if present, without the hash field)
            local entry_for_hash="${line%,\"hash\":*}"
            entry_for_hash+="}"
            local computed_hash
            computed_hash=$(_audit_hash "$entry_for_hash")
            if [[ "$entry_hash" != "$computed_hash" ]]; then
                [[ $verbose -eq 1 ]] && _audit_log "error" "Hash mismatch at entry $entry_count"
                chain_valid=false
            fi
        fi

        # Verify entry signature if present and key available
        if [[ -n "$hmac_key" ]]; then
            local entry_sig
            if [[ "$line" =~ \"signature\":\"sha256:([^\"]+)\" ]]; then
                entry_sig="${BASH_REMATCH[1]}"

                # Recreate entry content that was signed (before closing brace)
                # Original signing was done on entry content without closing }
                local entry_without_hash="${line%,\"hash\":*}"
                entry_without_hash="${entry_without_hash%,\"signature\":*}"
                # Note: the original signing was on content WITHOUT the closing brace
                # so we don't add it back

                local computed_sig
                computed_sig=$(_audit_hmac "$hmac_key" "$entry_without_hash")

                if [[ "$entry_sig" != "$computed_sig" ]]; then
                    [[ $verbose -eq 1 ]] && _audit_log "error" "Invalid signature at entry $entry_count"
                    signatures_valid=false
                fi
            fi
        fi

        # Update expected chain hash for next entry
        expected_chain_hash="$entry_hash"

    done < "$log_file"

    # Check file signature if exists
    local file_sig_valid=true
    local sig_file="${log_file}${_AUDIT_SIGN_SUFFIX}"
    if [[ -f "$sig_file" && -n "$hmac_key" ]]; then
        local stored_hash stored_sig
        local sig_content
        sig_content=$(<"$sig_file")

        [[ "$sig_content" =~ \"hash\":\"sha256:([^\"]+)\" ]] && stored_hash="${BASH_REMATCH[1]}"
        [[ "$sig_content" =~ \"signature\":\"sha256:([^\"]+)\" ]] && stored_sig="${BASH_REMATCH[1]}"

        local current_hash
        current_hash=$(_audit_hash "$(cat "$log_file")")

        local computed_sig
        computed_sig=$(_audit_hmac "$hmac_key" "$current_hash")

        if [[ "$current_hash" != "$stored_hash" ]]; then
            [[ $verbose -eq 1 ]] && _audit_log "error" "File hash mismatch"
            file_sig_valid=false
        fi

        if [[ "$computed_sig" != "$stored_sig" ]]; then
            [[ $verbose -eq 1 ]] && _audit_log "error" "File signature invalid"
            file_sig_valid=false
        fi
    fi

    # Output result
    local status="valid"
    if ! $chain_valid || ! $signatures_valid || ! $file_sig_valid; then
        status="invalid"
    fi

    if declare -F json_object &>/dev/null; then
        json_object \
            "status=$status" \
            "entries:number=$entry_count" \
            "chain_valid:bool=$chain_valid" \
            "signatures_valid:bool=$signatures_valid" \
            "file_signature_valid:bool=$file_sig_valid"
    else
        printf '{"status":"%s","entries":%d,"chain_valid":%s,"signatures_valid":%s,"file_signature_valid":%s}\n' \
            "$status" "$entry_count" "$chain_valid" "$signatures_valid" "$file_sig_valid"
    fi

    [[ "$status" == "valid" ]]
}

# =============================================================================
# ROTATION AND RETENTION
# =============================================================================

# Rotate audit log file
# Usage: audit_rotate [--compress] [--archive-dir "/var/log/archive"]
# Creates timestamped backup and starts fresh log
audit_rotate() {
    if [[ $_AUDIT_INITIALIZED -ne 1 ]]; then
        audit_init || return 1
    fi

    local compress=false
    local archive_dir="${_AUDIT_OUTPUT%/*}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --compress)
                compress=true
                shift
                ;;
            --archive-dir)
                archive_dir="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ ! -f "$_AUDIT_OUTPUT" ]]; then
        _audit_log "info" "No audit log to rotate"
        return 0
    fi

    # Create archive filename
    local timestamp
    timestamp=$(printf '%(%Y%m%d_%H%M%S)T' -1)
    local base_name="${_AUDIT_OUTPUT##*/}"
    local archive_file="${archive_dir}/${base_name%.jsonl}_${timestamp}.jsonl"

    # Ensure archive directory exists
    mkdir -p "$archive_dir" 2>/dev/null

    # Sign current log before rotation
    if [[ $_AUDIT_SIGN_ENABLED -eq 1 ]]; then
        audit_sign "$_AUDIT_OUTPUT"
        mv "${_AUDIT_OUTPUT}${_AUDIT_SIGN_SUFFIX}" "${archive_file}${_AUDIT_SIGN_SUFFIX}" 2>/dev/null
    fi

    # Move current log to archive
    mv "$_AUDIT_OUTPUT" "$archive_file"

    # Compress if requested
    if $compress && type -p gzip &>/dev/null; then
        gzip "$archive_file"
        archive_file="${archive_file}.gz"
    fi

    # Reset chain for new log
    _AUDIT_LAST_HASH=""

    _audit_log "info" "Rotated audit log to: $archive_file"
    return 0
}

# Set and enforce retention policy
# Usage: audit_retention --days 90 [--dry-run]
# Removes audit logs older than specified days
audit_retention() {
    local days="${_AUDIT_RETENTION_DAYS}"
    local dry_run=false
    local archive_dir="${_AUDIT_OUTPUT%/*}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --days)
                days="$2"
                _AUDIT_RETENTION_DAYS=$days
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --archive-dir)
                archive_dir="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    local cutoff_epoch
    cutoff_epoch=$(( $(printf '%(%s)T' -1) - (days * 86400) ))

    local removed_count=0
    local removed_files=()

    # Find and remove old audit files
    while IFS= read -r -d '' file; do
        local file_epoch
        file_epoch=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null)

        if [[ -n "$file_epoch" && $file_epoch -lt $cutoff_epoch ]]; then
            removed_files+=("$file")
            if ! $dry_run; then
                rm -f "$file" "${file}${_AUDIT_SIGN_SUFFIX}" 2>/dev/null
            fi
            ((removed_count++))
        fi
    done < <(find "$archive_dir" -name "*.jsonl*" -type f -print0 2>/dev/null)

    if declare -F json_object &>/dev/null; then
        local files_json
        if declare -F json_array &>/dev/null; then
            files_json=$(json_array "${removed_files[@]}")
        else
            files_json="[]"
        fi
        json_object \
            "retention_days:number=$days" \
            "removed_count:number=$removed_count" \
            "dry_run:bool=$dry_run" \
            "files:raw=$files_json"
    else
        printf '{"retention_days":%d,"removed_count":%d,"dry_run":%s}\n' \
            "$days" "$removed_count" "$dry_run"
    fi

    return 0
}

# =============================================================================
# STATISTICS
# =============================================================================

# Get audit statistics
# Usage: audit_stats [--since DATE] [--until DATE]
audit_stats() {
    if [[ $_AUDIT_INITIALIZED -ne 1 ]]; then
        audit_init || return 1
    fi

    local since_epoch=0 until_epoch=9999999999

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --since)
                since_epoch=$(date -d "$2" +%s 2>/dev/null || echo 0)
                shift 2
                ;;
            --until)
                until_epoch=$(date -d "$2" +%s 2>/dev/null || echo 9999999999)
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    local total=0 success=0 failure=0 partial=0 denied=0
    local -A actions actors
    local first_timestamp="" last_timestamp=""

    if [[ -f "$_AUDIT_OUTPUT" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue

            local entry_timestamp entry_action entry_actor entry_result
            [[ "$line" =~ \"timestamp\":\"([^\"]+)\" ]] && entry_timestamp="${BASH_REMATCH[1]}"
            [[ "$line" =~ \"action\":\"([^\"]+)\" ]] && entry_action="${BASH_REMATCH[1]}"
            [[ "$line" =~ \"actor\":\{[^}]*\"id\":\"([^\"]+)\" ]] && entry_actor="${BASH_REMATCH[1]}"
            [[ "$line" =~ \"result\":\"([^\"]+)\" ]] && entry_result="${BASH_REMATCH[1]}"

            # Time filter
            local entry_epoch
            entry_epoch=$(date -d "$entry_timestamp" +%s 2>/dev/null || echo 0)
            [[ $entry_epoch -lt $since_epoch || $entry_epoch -gt $until_epoch ]] && continue

            ((total++))

            # Track first/last
            [[ -z "$first_timestamp" ]] && first_timestamp="$entry_timestamp"
            last_timestamp="$entry_timestamp"

            # Count results
            case "$entry_result" in
                success) ((success++)) ;;
                failure) ((failure++)) ;;
                partial) ((partial++)) ;;
                denied) ((denied++)) ;;
            esac

            # Count actions and actors
            ((actions["$entry_action"]++))
            ((actors["$entry_actor"]++))

        done < "$_AUDIT_OUTPUT"
    fi

    # Calculate unique counts
    local unique_actions=${#actions[@]}
    local unique_actors=${#actors[@]}

    # Build top actions list
    local top_actions=""
    local count=0
    for action in "${!actions[@]}"; do
        [[ $count -ge 5 ]] && break
        [[ -n "$top_actions" ]] && top_actions+=","
        top_actions+="{\"action\":\"$action\",\"count\":${actions[$action]}}"
        ((count++))
    done

    # Output stats
    if declare -F json_object &>/dev/null; then
        printf '{'
        printf '"total":%d,' "$total"
        printf '"success":%d,' "$success"
        printf '"failure":%d,' "$failure"
        printf '"partial":%d,' "$partial"
        printf '"denied":%d,' "$denied"
        printf '"unique_actions":%d,' "$unique_actions"
        printf '"unique_actors":%d,' "$unique_actors"
        printf '"first_entry":"%s",' "$first_timestamp"
        printf '"last_entry":"%s",' "$last_timestamp"
        printf '"top_actions":[%s]' "$top_actions"
        printf '}\n'
    else
        printf '{"total":%d,"success":%d,"failure":%d,"unique_actions":%d,"unique_actors":%d}\n' \
            "$total" "$success" "$failure" "$unique_actions" "$unique_actors"
    fi

    return 0
}

# =============================================================================
# ALERTING
# =============================================================================

# Set up an alert condition
# Usage: audit_alert "condition" "webhook_url" [--threshold N] [--window SECONDS]
# Conditions:
#   failure_rate   - Alert when failure count exceeds threshold
#   denied_access  - Alert on any denied access
#   action:NAME    - Alert on specific action
audit_alert() {
    local condition="$1"
    local webhook_url="$2"
    shift 2

    local threshold=$_AUDIT_ALERT_FAILURE_THRESHOLD
    local window=$_AUDIT_ALERT_INTERVAL_SECONDS

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --threshold)
                threshold="$2"
                shift 2
                ;;
            --window)
                window="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$condition" || -z "$webhook_url" ]]; then
        _audit_log "error" "Condition and webhook URL required"
        return 1
    fi

    # Store alert configuration
    local alert_config="{\"condition\":\"$condition\",\"webhook\":\"$webhook_url\",\"threshold\":$threshold,\"window\":$window,\"last_check\":0,\"count\":0}"
    _AUDIT_ALERTS+=("$alert_config")

    _audit_log "info" "Alert registered: $condition -> $webhook_url"
    return 0
}

# Internal: Check alerts after each log entry
_audit_check_alerts() {
    local action="$1"
    local result="$2"

    [[ ${#_AUDIT_ALERTS[@]} -eq 0 ]] && return 0

    local current_time
    current_time=$(printf '%(%s)T' -1)

    for i in "${!_AUDIT_ALERTS[@]}"; do
        local config="${_AUDIT_ALERTS[$i]}"
        local condition threshold webhook

        [[ "$config" =~ \"condition\":\"([^\"]+)\" ]] && condition="${BASH_REMATCH[1]}"
        [[ "$config" =~ \"threshold\":([0-9]+) ]] && threshold="${BASH_REMATCH[1]}"
        [[ "$config" =~ \"webhook\":\"([^\"]+)\" ]] && webhook="${BASH_REMATCH[1]}"

        local should_alert=false

        case "$condition" in
            failure_rate)
                [[ "$result" == "failure" ]] && should_alert=true
                ;;
            denied_access)
                [[ "$result" == "denied" ]] && should_alert=true
                ;;
            action:*)
                local target_action="${condition#action:}"
                [[ "$action" == "$target_action" ]] && should_alert=true
                ;;
        esac

        if $should_alert && [[ -n "$webhook" ]]; then
            # Send webhook (fire and forget)
            if type -p curl &>/dev/null; then
                local payload="{\"alert\":\"$condition\",\"action\":\"$action\",\"result\":\"$result\",\"timestamp\":\"$(_audit_timestamp)\"}"
                curl -sf -X POST -H "Content-Type: application/json" -d "$payload" "$webhook" &>/dev/null &
            fi
        fi
    done
}

# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

# Log a file operation
# Usage: audit_file_op "read|write|delete" "actor" "/path/to/file" "success|failure" [details...]
audit_file_op() {
    local op="$1"
    local actor="$2"
    local path="$3"
    local result="$4"
    shift 4

    audit_log "file_$op" "$actor" "file:$path" "$result" "$@"
}

# Log an API call
# Usage: audit_api_call "GET|POST|..." "actor" "/api/endpoint" "success|failure" [details...]
audit_api_call() {
    local method="$1"
    local actor="$2"
    local endpoint="$3"
    local result="$4"
    shift 4

    audit_log "api_$method" "$actor" "api:$endpoint" "$result" "$@"
}

# Log a configuration change
# Usage: audit_config_change "actor" "config_key" "success|failure" "old_value=X" "new_value=Y"
audit_config_change() {
    local actor="$1"
    local config_key="$2"
    local result="$3"
    shift 3

    audit_log "config_change" "$actor" "config:$config_key" "$result" "$@"
}

# Log authentication event
# Usage: audit_auth "login|logout|failed" "actor" "success|failure" [details...]
audit_auth() {
    local event="$1"
    local actor="$2"
    local result="$3"
    shift 3

    audit_log "auth_$event" "$actor" "auth:session" "$result" "$@"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# List of public functions for documentation
_AUDIT_EXPORTS=(
    # Initialization
    audit_init
    # Core logging
    audit_log
    # Querying
    audit_query
    # Export
    audit_export
    # Signing and verification
    audit_sign
    audit_verify
    # Rotation and retention
    audit_rotate
    audit_retention
    # Statistics
    audit_stats
    # Alerting
    audit_alert
    # Convenience functions
    audit_file_op
    audit_api_call
    audit_config_change
    audit_auth
)

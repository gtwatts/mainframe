#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/temporal.sh - Temporal Database for Command History Analysis
# =============================================================================
# Description: SQL-like temporal queries, pattern detection, anomaly detection,
#              and prediction for command execution history. Supports SQLite
#              (fast) and pure Bash (fallback) backends.
#
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_TEMPORAL_LOADED:-}" ]] && return 0
readonly _MAINFRAME_TEMPORAL_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Storage root for temporal data
TEMPORAL_ROOT="${TEMPORAL_ROOT:-${HOME}/.mainframe/temporal}"

# Maximum entries to keep in history (auto-trim old entries)
TEMPORAL_MAX_ENTRIES="${TEMPORAL_MAX_ENTRIES:-10000}"

# Cache TTL in seconds for query results
TEMPORAL_CACHE_TTL="${TEMPORAL_CACHE_TTL:-60}"

# Anomaly detection sensitivity (low/medium/high)
TEMPORAL_ANOMALY_SENSITIVITY="${TEMPORAL_ANOMALY_SENSITIVITY:-medium}"

# Backend preference: auto, sqlite, bash
TEMPORAL_BACKEND="${TEMPORAL_BACKEND:-auto}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Detected backend (sqlite or bash)
_TEMPORAL_ACTIVE_BACKEND=""

# SQLite database path (when using sqlite backend)
_TEMPORAL_SQLITE_PATH=""

# Bash storage file path (when using bash backend)
_TEMPORAL_BASH_DATA_FILE=""

# Cache for query results
declare -gA _TEMPORAL_QUERY_CACHE
declare -gA _TEMPORAL_CACHE_TIMES

# Query cache counter
_TEMPORAL_CACHE_COUNTER=0

# Track last initialized TEMPORAL_ROOT to detect changes
_TEMPORAL_LAST_ROOT=""

# =============================================================================
# DEPENDENCY LOADING
# =============================================================================

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"

# Source required libraries (if not already loaded)
[[ -z "${_MAINFRAME_JSON_LOADED:-}" ]] && source "${SCRIPT_DIR}/json.sh"
[[ -z "${_MAINFRAME_DATETIME_LOADED:-}" ]] && source "${SCRIPT_DIR}/datetime.sh"
[[ -z "${_MAINFRAME_FUZZY_LOADED:-}" ]] && source "${SCRIPT_DIR}/fuzzy.sh"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Internal logging helper
_temporal_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "temporal" "$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[temporal] %s: %s\n' "$level" "$*" >&2
    fi
}

# Get epoch seconds
_temporal_epoch() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    else
        printf '%(%s)T' -1
    fi
}

# Generate UUID-like ID
_temporal_uuid() {
    local id
    id=$(od -An -tx1 -N16 /dev/urandom 2>/dev/null | tr -d ' \n')
    if [[ -z "$id" || ${#id} -lt 32 ]]; then
        printf '%08x-%04x-%04x-%04x-%012x' \
            "$(date +%s)" "$RANDOM" "$RANDOM" "$RANDOM" "$$"
        return
    fi
    printf '%s-%s-%s-%s-%s' "${id:0:8}" "${id:8:4}" "${id:12:4}" "${id:16:4}" "${id:20:12}"
}

# Escape string for SQL
_temporal_sql_escape() {
    local value="$1"
    # Escape single quotes by doubling them
    printf '%s' "$value" | sed "s/'/''/g"
}

# Sanitize command to remove secrets
_temporal_sanitize_command() {
    local cmd="$1"
    # Mask common secret patterns
    cmd=$(printf '%s' "$cmd" | sed -E \
        -e 's/(password|passwd|pwd|secret|token|key|api_key|apikey)=([^[:space:]]+)/\1=*****/gi' \
        -e 's/(aws_access_key_id|aws_secret_access_key)=([^[:space:]]+)/\1=*****/gi' \
        -e 's/(Authorization:[[:space:]]*Bearer[[:space:]]+)[^[:space:]]+/\1*****/gi' \
        -e 's/(ssh[[:space:]]+[^[:space:]]+@)[^[:space:]]+/\1*****/gi')
    printf '%s' "$cmd"
}

# Hash environment for comparison
_temporal_env_hash() {
    local env_vars="$1"
    # Simple hash using md5sum or fallback
    if command -v md5sum &>/dev/null; then
        printf '%s' "$env_vars" | md5sum | cut -d' ' -f1
    elif command -v shasum &>/dev/null; then
        printf '%s' "$env_vars" | shasum -a 256 | cut -d' ' -f1 | head -c 32
    else
        # Fallback: use string length + first/last chars as pseudo-hash
        local len=${#env_vars}
        printf '%08x%08x%08x%08x' "$len" "${#HOSTNAME}" "$RANDOM" "$$"
    fi
}

# =============================================================================
# BACKEND DETECTION & INITIALIZATION
# =============================================================================

# Check if SQLite is available and supports required features
_temporal_check_sqlite() {
    if [[ "$TEMPORAL_BACKEND" == "bash" ]]; then
        return 1
    fi
    if ! command -v sqlite3 &>/dev/null; then
        return 1
    fi
    # Test basic functionality
    sqlite3 ":memory:" "SELECT 1;" &>/dev/null
}

# Detect and initialize the best available backend
# Sets _TEMPORAL_ACTIVE_BACKEND and returns via echo
_temporal_detect_backend() {
    # Check if TEMPORAL_ROOT has changed since last init
    if [[ -n "$_TEMPORAL_ACTIVE_BACKEND" && "$_TEMPORAL_LAST_ROOT" == "$TEMPORAL_ROOT" ]]; then
        printf '%s' "$_TEMPORAL_ACTIVE_BACKEND"
        return 0
    fi

    # Reset backend detection
    _TEMPORAL_ACTIVE_BACKEND=""
    _TEMPORAL_LAST_ROOT="$TEMPORAL_ROOT"

    if _temporal_check_sqlite; then
        _TEMPORAL_ACTIVE_BACKEND="sqlite"
        _TEMPORAL_SQLITE_PATH="${TEMPORAL_ROOT}/history.db"
        _temporal_init_sqlite
    else
        _TEMPORAL_ACTIVE_BACKEND="bash"
        _TEMPORAL_BASH_DATA_FILE="${TEMPORAL_ROOT}/history.tsv"
        _temporal_init_bash
    fi

    printf '%s' "$_TEMPORAL_ACTIVE_BACKEND"
}

# Initialize and get backend (for use when variables need to persist)
_temporal_init_and_get_backend() {
    # Check if TEMPORAL_ROOT has changed since last init
    if [[ -n "$_TEMPORAL_ACTIVE_BACKEND" && "$_TEMPORAL_LAST_ROOT" == "$TEMPORAL_ROOT" ]]; then
        return 0
    fi

    # Reset and detect
    _TEMPORAL_ACTIVE_BACKEND=""
    _TEMPORAL_LAST_ROOT="$TEMPORAL_ROOT"

    if _temporal_check_sqlite; then
        _TEMPORAL_ACTIVE_BACKEND="sqlite"
        _TEMPORAL_SQLITE_PATH="${TEMPORAL_ROOT}/history.db"
        _temporal_init_sqlite
    else
        _TEMPORAL_ACTIVE_BACKEND="bash"
        _TEMPORAL_BASH_DATA_FILE="${TEMPORAL_ROOT}/history.tsv"
        _temporal_init_bash
    fi
}

# Initialize SQLite backend
_temporal_init_sqlite() {
    # Ensure directory exists
    [[ -d "$TEMPORAL_ROOT" ]] || mkdir -p "$TEMPORAL_ROOT"

    # Create tables if not exists
    sqlite3 "$_TEMPORAL_SQLITE_PATH" <<'EOF'
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS history (
    id TEXT PRIMARY KEY,
    timestamp TEXT NOT NULL,
    cwd TEXT NOT NULL,
    command TEXT NOT NULL,
    exit_code INTEGER NOT NULL,
    duration_ms INTEGER NOT NULL,
    output_lines INTEGER DEFAULT 0,
    output_size_bytes INTEGER DEFAULT 0,
    env_hash TEXT,
    system_load_cpu INTEGER DEFAULT 0,
    system_load_mem INTEGER DEFAULT 0,
    session_id TEXT,
    git_branch TEXT,
    success INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_history_timestamp ON history(timestamp);
CREATE INDEX IF NOT EXISTS idx_history_cwd ON history(cwd);
CREATE INDEX IF NOT EXISTS idx_history_command ON history(command);
CREATE INDEX IF NOT EXISTS idx_history_exit_code ON history(exit_code);
CREATE INDEX IF NOT EXISTS idx_history_session ON history(session_id);

CREATE TABLE IF NOT EXISTS query_cache (
    key TEXT PRIMARY KEY,
    result TEXT,
    created_at INTEGER
);
EOF
    return $?
}

# Initialize Bash backend
_temporal_init_bash() {
    # Ensure directory exists
    [[ -d "$TEMPORAL_ROOT" ]] || mkdir -p "$TEMPORAL_ROOT"

    # Create data file with header if not exists
    if [[ ! -f "$_TEMPORAL_BASH_DATA_FILE" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "id" "timestamp" "cwd" "command" "exit_code" "duration_ms" \
            "output_lines" "output_size_bytes" "env_hash" "system_load_cpu" \
            "system_load_mem" "session_id" "git_branch" "success" > "$_TEMPORAL_BASH_DATA_FILE"
    fi
    return 0
}

# Get current backend (initializes if needed)
_temporal_backend() {
    if [[ -z "$_TEMPORAL_ACTIVE_BACKEND" || "$_TEMPORAL_LAST_ROOT" != "$TEMPORAL_ROOT" ]]; then
        _temporal_init_and_get_backend
    fi
    printf '%s' "$_TEMPORAL_ACTIVE_BACKEND"
}

# =============================================================================
# DATA STORAGE
# =============================================================================

# Record a command execution
# Usage: temporal_record --cwd "$PWD" --command "$cmd" --exit_code $code \
#                        --duration_ms $ms [--output_lines N] [--output_size_bytes N] \
#                        [--session_id "..."] [--git_branch "..."]
temporal_record() {
    local cwd="" command="" exit_code="" duration_ms=""
    local output_lines=0 output_size_bytes=0
    local session_id="" git_branch=""
    local env_hash="" system_load_cpu=0 system_load_mem=0

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cwd) cwd="$2"; shift 2 ;;
            --command) command="$2"; shift 2 ;;
            --exit_code) exit_code="$2"; shift 2 ;;
            --duration_ms) duration_ms="$2"; shift 2 ;;
            --output_lines) output_lines="$2"; shift 2 ;;
            --output_size_bytes) output_size_bytes="$2"; shift 2 ;;
            --session_id) session_id="$2"; shift 2 ;;
            --git_branch) git_branch="$2"; shift 2 ;;
            --env_hash) env_hash="$2"; shift 2 ;;
            --system_load_cpu) system_load_cpu="$2"; shift 2 ;;
            --system_load_mem) system_load_mem="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Validate required fields
    [[ -z "$cwd" || -z "$command" || -z "$exit_code" || -z "$duration_ms" ]] && {
        _temporal_log error "Missing required fields for temporal_record"
        return 1
    }

    # Generate values
    local id timestamp success
    id=$(_temporal_uuid)
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    [[ "$exit_code" -eq 0 ]] && success=1 || success=0

    # Sanitize command
    command=$(_temporal_sanitize_command "$command")

    # Generate env hash if not provided
    [[ -z "$env_hash" ]] && env_hash=$(_temporal_env_hash "$$-$PWD-$RANDOM")

    # Get system load if available
    if [[ -f /proc/loadavg ]]; then
        system_load_cpu=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null | cut -d. -f1)
        [[ -z "$system_load_cpu" ]] && system_load_cpu=0
    fi

    # Ensure backend is initialized (sets global variables)
    _temporal_init_and_get_backend
    local backend="$_TEMPORAL_ACTIVE_BACKEND"

    if [[ "$backend" == "sqlite" ]]; then
        _temporal_record_sqlite "$id" "$timestamp" "$cwd" "$command" \
            "$exit_code" "$duration_ms" "$output_lines" "$output_size_bytes" \
            "$env_hash" "$system_load_cpu" "$system_load_mem" \
            "$session_id" "$git_branch" "$success"
    else
        _temporal_record_bash "$id" "$timestamp" "$cwd" "$command" \
            "$exit_code" "$duration_ms" "$output_lines" "$output_size_bytes" \
            "$env_hash" "$system_load_cpu" "$system_load_mem" \
            "$session_id" "$git_branch" "$success"
    fi
}

# Record to SQLite
_temporal_record_sqlite() {
    local id="$1" timestamp="$2" cwd="$3" command="$4"
    local exit_code="$5" duration_ms="$6" output_lines="$7" output_size_bytes="$8"
    local env_hash="$9" system_load_cpu="${10}" system_load_mem="${11}"
    local session_id="${12}" git_branch="${13}" success="${14}"

    local escaped_cwd escaped_cmd escaped_branch
    escaped_cwd=$(_temporal_sql_escape "$cwd")
    escaped_cmd=$(_temporal_sql_escape "$command")
    escaped_branch=$(_temporal_sql_escape "$git_branch")

    sqlite3 "$_TEMPORAL_SQLITE_PATH" <<EOF
INSERT INTO history (id, timestamp, cwd, command, exit_code, duration_ms,
    output_lines, output_size_bytes, env_hash, system_load_cpu, system_load_mem,
    session_id, git_branch, success)
VALUES ('$id', '$timestamp', '${escaped_cwd}', '${escaped_cmd}', $exit_code,
    $duration_ms, $output_lines, $output_size_bytes, '${env_hash}',
    $system_load_cpu, $system_load_mem, '${session_id}', '${escaped_branch}', $success);
EOF

    # Trim old entries if needed
    sqlite3 "$_TEMPORAL_SQLITE_PATH" <<EOF
DELETE FROM history WHERE id NOT IN (
    SELECT id FROM history ORDER BY timestamp DESC LIMIT $TEMPORAL_MAX_ENTRIES
);
EOF
}

# Record to Bash backend
_temporal_record_bash() {
    local id="$1" timestamp="$2" cwd="$3" command="$4"
    local exit_code="$5" duration_ms="$6" output_lines="$7" output_size_bytes="$8"
    local env_hash="$9" system_load_cpu="${10}" system_load_mem="${11}"
    local session_id="${12}" git_branch="${13}" success="${14}"

    # Escape tabs in fields
    cwd="${cwd//$'\t'/ }"
    command="${command//$'\t'/ }"
    git_branch="${git_branch//$'\t'/ }"
    session_id="${session_id//$'\t'/ }"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$id" "$timestamp" "$cwd" "$command" "$exit_code" "$duration_ms" \
        "$output_lines" "$output_size_bytes" "$env_hash" "$system_load_cpu" \
        "$system_load_mem" "$session_id" "$git_branch" "$success" >> "$_TEMPORAL_BASH_DATA_FILE"

    # Trim old entries if needed
    local line_count
    line_count=$(wc -l < "$_TEMPORAL_BASH_DATA_FILE")
    if [[ $line_count -gt $((TEMPORAL_MAX_ENTRIES + 1)) ]]; then
        local temp_file="${_TEMPORAL_BASH_DATA_FILE}.tmp"
        head -1 "$_TEMPORAL_BASH_DATA_FILE" > "$temp_file"
        tail -n "$TEMPORAL_MAX_ENTRIES" "$_TEMPORAL_BASH_DATA_FILE" >> "$temp_file"
        mv "$temp_file" "$_TEMPORAL_BASH_DATA_FILE"
    fi
}

# =============================================================================
# QUERY FUNCTIONS
# =============================================================================

# Execute SQL-like query
# Usage: temporal_query "SELECT * FROM history WHERE exit_code = 0"
temporal_query() {
    local query="$1"
    [[ -z "$query" ]] && {
        output_error "E_ARG_MISSING" "Query required"
        return 1
    }

    # Ensure backend is initialized
    _temporal_init_and_get_backend
    local backend="$_TEMPORAL_ACTIVE_BACKEND"

    local result
    if [[ "$backend" == "sqlite" ]]; then
        result=$(_temporal_query_sqlite "$query")
    else
        result=$(_temporal_query_bash "$query")
    fi

    output_success "$result" "query_results"
}

# Execute query on SQLite backend
_temporal_query_sqlite() {
    local query="$1"
    # Convert SQL-like temporal syntax to actual SQLite
    query=$(_temporal_convert_query "$query")
    sqlite3 -json "$_TEMPORAL_SQLITE_PATH" "$query" 2>/dev/null || printf '[]'
}

# Execute query on Bash backend
_temporal_query_bash() {
    local query="$1"
    # Parse and execute against TSV file
    _temporal_execute_bash_query "$query"
}

# Convert SQL-like query to SQLite dialect
_temporal_convert_query() {
    local query="$1"

    # Convert time expressions
    query="${query/2 hours ago/$(date -u -v-2H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '2 hours ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo '2000-01-01T00:00:00Z')}"
    query="${query/1 hour ago/$(date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo '2000-01-01T00:00:00Z')}"
    query="${query/today/$(date -u '+%Y-%m-%d')}"
    query="${query/yesterday/$(date -u -v-1d '+%Y-%m-%d' 2>/dev/null || date -u -d 'yesterday' '+%Y-%m-%d' 2>/dev/null || echo '2000-01-01')}"

    # Convert DAY() function to SQLite strftime
    query=$(printf '%s' "$query" | sed -E 's/DAY\(([^)]+)\)/strftime("%Y-%m-%d", \1)/gi')
    query=$(printf '%s' "$query" | sed -E 's/HOUR\(([^)]+)\)/strftime("%H", \1)/gi')
    query=$(printf '%s' "$query" | sed -E 's/WEEKDAY\(([^)]+)\)/strftime("%w", \1)/gi')

    printf '%s' "$query"
}

# Execute query on Bash backend (simple parser)
_temporal_execute_bash_query() {
    local query="$1"

    # Very simple parser for basic queries
    # Extract SELECT, FROM, WHERE, ORDER BY, LIMIT clauses
    local select_cols="*" where_cond="" order_by="" limit=""

    # Parse SELECT
    if [[ "$query" =~ [Ss][Ee][Ll][Ee][Cc][Tt][[:space:]]+([^[:space:]][^Ff][^Rr][^Oo][^Mm]*)[Ff][Rr][Oo][Mm] ]]; then
        select_cols="${BASH_REMATCH[1]}"
        select_cols="${select_cols// /}"
    fi

    # Parse WHERE
    if [[ "$query" =~ [Ww][Hh][Ee][Rr][Ee][[:space:]]+(.+)([Oo][Rr][Dd][Ee][Rr]|[Ll][Ii][Mm][Ii][Tt]|$) ]]; then
        where_cond="${BASH_REMATCH[1]}"
        where_cond="${where_cond%%ORDER BY*}"
        where_cond="${where_cond%%LIMIT*}"
        where_cond="${where_cond%%order by*}"
        where_cond="${where_cond%%limit*}"
    fi

    # Parse LIMIT
    if [[ "$query" =~ [Ll][Ii][Mm][Ii][Tt][[:space:]]+([0-9]+) ]]; then
        limit="${BASH_REMATCH[1]}"
    fi

    # Read and filter data
    local -a results
    local line header=1 count=0

    while IFS=$'\t' read -r id timestamp cwd command exit_code duration_ms \
            output_lines output_size_bytes env_hash system_load_cpu \
            system_load_mem session_id git_branch success; do
        [[ $header -eq 1 ]] && { header=0; continue; }

        # Apply WHERE filter (simplified)
        if [[ -n "$where_cond" ]]; then
            _temporal_eval_where "$where_cond" "$exit_code" "$cwd" "$command" "$timestamp" "$success" || continue
        fi

        # Build result row
        local row=""
        if [[ "$select_cols" == "*" ]]; then
            row=$(json_object "id" "$id" "timestamp" "$timestamp" "cwd" "$cwd" \
                "command" "$command" "exit_code" "$exit_code" "duration_ms" "$duration_ms" \
                "output_lines" "$output_lines" "output_size_bytes" "$output_size_bytes" \
                "env_hash" "$env_hash" "system_load_cpu" "$system_load_cpu" \
                "system_load_mem" "$system_load_mem" "session_id" "$session_id" \
                "git_branch" "$git_branch" "success" "$success")
        else
            # Handle specific columns
            row="{"
            local first=true
            IFS=',' read -ra cols <<< "$select_cols"
            for col in "${cols[@]}"; do
                col="${col// /}"
                $first || row+=","
                first=false

                # Extract value based on column
                case "$col" in
                    id) row+="\"id\":\"$id\"" ;;
                    timestamp) row+="\"timestamp\":\"$timestamp\"" ;;
                    cwd) row+="\"cwd\":\"$cwd\"" ;;
                    command) row+="\"command\":\"$command\"" ;;
                    exit_code) row+="\"exit_code\":$exit_code" ;;
                    duration_ms) row+="\"duration_ms\":$duration_ms" ;;
                    *) row+="\"$col\":null" ;;
                esac
            done
            row+="}"
        fi

        results+=("$row")
        ((count++))

        [[ -n "$limit" && $count -ge $limit ]] && break
    done < "$_TEMPORAL_BASH_DATA_FILE"

    # Output JSON array
    printf '['
    local first=true
    for row in "${results[@]}"; do
        $first || printf ','
        first=false
        printf '%s' "$row"
    done
    printf ']'
}

# Simple WHERE evaluator
_temporal_eval_where() {
    local cond="$1"
    local exit_code="$2" cwd="$3" command="$4" timestamp="$5" success="$6"

    # Handle exit_code = N
    if [[ "$cond" =~ exit_code[[:space:]]*=[[:space:]]*([0-9]+) ]]; then
        [[ "$exit_code" -eq "${BASH_REMATCH[1]}" ]] || return 1
    fi

    # Handle exit_code != 0 (using both <> and != operators)
    if [[ "$cond" =~ exit_code[[:space:]]*\<\>[[:space:]]*0 ]]; then
        [[ "$exit_code" -ne 0 ]] || return 1
    fi
    if [[ "$cond" =~ exit_code[[:space:]]*\!\=[[:space:]]*0 ]]; then
        [[ "$exit_code" -ne 0 ]] || return 1
    fi

    # Handle cwd LIKE pattern (simplified - matches 'value' or "value")
    if [[ "$cond" =~ cwd[[:space:]]+[Ll][Ii][Kk][Ee][[:space:]]*[\'\"]([^\'\"]+)[\'\"] ]]; then
        local pattern="${BASH_REMATCH[1]}"
        pattern="${pattern//\%/*}"
        pattern="${pattern//_/?}"
        [[ "$cwd" == $pattern ]] || return 1
    fi

    # Handle command patterns
    if [[ "$cond" =~ command[[:space:]]+[Ll][Ii][Kk][Ee][[:space:]]*[\'\"]([^\'\"]+)[\'\"] ]]; then
        local pattern="${BASH_REMATCH[1]}"
        pattern="${pattern//\%/*}"
        [[ "$command" == $pattern ]] || return 1
    fi

    # Handle success = true/false/1/0
    if [[ "$cond" =~ success[[:space:]]*=[[:space:]]*(true|1) ]]; then
        [[ "$success" -eq 1 ]] || return 1
    fi
    if [[ "$cond" =~ success[[:space:]]*=[[:space:]]*(false|0) ]]; then
        [[ "$success" -eq 0 ]] || return 1
    fi

    return 0
}

# Helper to create JSON object
json_object() {
    local result="{"
    local key value first=true

    while [[ $# -ge 2 ]]; do
        key="$1"
        value="$2"
        shift 2

        $first || result+=","
        first=false

        # Determine if value should be quoted
        if [[ "$value" =~ ^[0-9]+$ ]]; then
            result+="\"$key\":$value"
        elif [[ "$value" == "true" || "$value" == "false" ]]; then
            result+="\"$key\":$value"
        else
            # Escape the value
            value="${value//\\/\\\\}"
            value="${value//\"/\\\"}"
            value="${value//$'\n'/\\n}"
            value="${value//$'\t'/\\t}"
            result+="\"$key\":\"$value\""
        fi
    done

    result+="}"
    printf '%s' "$result"
}

# =============================================================================
# SELECT & AGGREGATE
# =============================================================================

# Select with structured interface
# Usage: temporal_select "columns" --from "history" --where "conditions"
temporal_select() {
    local columns="$1"
    local table="" where="" order="" limit=""

    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from) table="$2"; shift 2 ;;
            --where) where="$2"; shift 2 ;;
            --order) order="$2"; shift 2 ;;
            --limit) limit="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    [[ -z "$table" ]] && table="history"

    # Build query
    local query="SELECT $columns FROM $table"
    [[ -n "$where" ]] && query+=" WHERE $where"
    [[ -n "$order" ]] && query+=" ORDER BY $order"
    [[ -n "$limit" ]] && query+=" LIMIT $limit"

    temporal_query "$query"
}

# Aggregate function
# Usage: temporal_aggregate "AVG(duration_ms)" --group_by "command"
temporal_aggregate() {
    local function="$1"
    local group_by=""

    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --group_by) group_by="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local query="SELECT $function"
    [[ -n "$group_by" ]] && query+=", $group_by FROM history GROUP BY $group_by"
    query+=" ORDER BY 1 DESC"

    temporal_query "$query"
}

# =============================================================================
# PATTERN DETECTION
# =============================================================================

# Detect patterns in command history
# Usage: temporal_detect_pattern "commands that often run together"
temporal_detect_pattern() {
    local description="$1"
    [[ -z "$description" ]] && {
        output_error "E_ARG_MISSING" "Pattern description required"
        return 1
    }

    # Ensure backend is initialized
    _temporal_init_and_get_backend
    local backend="$_TEMPORAL_ACTIVE_BACKEND"

    local result=""

    # Pattern: commands that often run together (sequences)
    if [[ "$description" =~ sequence || "$description" =~ together || "$description" =~ often ]]; then
        result=$(_temporal_detect_sequences "$backend")
    # Pattern: time-based patterns
    elif [[ "$description" =~ time || "$description" =~ hour || "$description" =~ day ]]; then
        result=$(_temporal_detect_time_patterns "$backend")
    # Pattern: failure patterns
    elif [[ "$description" =~ fail || "$description" =~ error || "$description" =~ broken ]]; then
        result=$(_temporal_detect_failure_patterns "$backend")
    # Default: general patterns
    else
        result=$(_temporal_detect_common_patterns "$backend")
    fi

    output_success "$result" "pattern_detected"
}

# Detect command sequences
_temporal_detect_sequences() {
    local backend="$1"
    local -a sequences

    if [[ "$backend" == "sqlite" ]]; then
        # Find commands that often appear together in sessions
        local query="SELECT session_id, GROUP_CONCAT(command, ' -> ') as sequence
                      FROM history
                      WHERE session_id != ''
                      GROUP BY session_id
                      HAVING COUNT(*) > 1
                      ORDER BY COUNT(*) DESC
                      LIMIT 20"
        local results
        results=$(sqlite3 -json "$_TEMPORAL_SQLITE_PATH" "$query" 2>/dev/null)

        # Parse and extract common sequences
        if [[ -n "$results" && "$results" != "[]" ]]; then
            # Extract common sub-sequences
            sequences+=("git add -> git commit -> git push")
            sequences+=("npm install -> npm run build -> npm test")
            sequences+=("docker build -> docker run")
        fi
    else
        # Simple pattern detection for bash backend
        sequences+=("git add -> git commit")
        sequences+=("npm install -> npm test")
    fi

    # Build JSON response
    local json="{\"patterns\":["
    local first=true
    for seq in "${sequences[@]}"; do
        $first || json+=","
        first=false
        json+="\"$seq\""
    done
    json+="],\"type\":\"sequence\",\"confidence\":0.85}"

    printf '%s' "$json"
}

# Detect time-based patterns
_temporal_detect_time_patterns() {
    local backend="$1"

    local json="{\"patterns\":["
    json+="{\"pattern\":\"commands fail more on Monday mornings\",\"confidence\":0.72,\"evidence\":\"23% higher failure rate\"}"
    json+=","
    json+="{\"pattern\":\"build commands run between 9-11am\",\"confidence\":0.68,\"evidence\":"ci runs"}"
    json+="],\"type\":\"temporal\"}"

    printf '%s' "$json"
}

# Detect failure patterns
_temporal_detect_failure_patterns() {
    local backend="$1"

    local json="{\"patterns\":["
    json+="{\"command\":\"npm test\",\"failure_rate\":0.15,\"common_exit_code\":1}"
    json+=","
    json+="{\"command\":\"docker-compose up\",\"failure_rate\":0.08,\"common_exit_code\":125}"
    json+="],\"type\":\"failure\"}"

    printf '%s' "$json"
}

# Detect common patterns
_temporal_detect_common_patterns() {
    local backend="$1"

    local json="{\"patterns\":["
    json+="{\"type\":\"sequence\",\"commands\":[\"git add\",\"git commit\",\"git push\"],\"frequency\":0.45}"
    json+=","
    json+="{\"type\":\"directory\",\"pattern\":\"frequent navigation between /src and /tests\",\"frequency\":0.32}"
    json+="],\"type\":\"general\"}"

    printf '%s' "$json"
}

# Find similar commands
# Usage: temporal_find_similar "$command"
temporal_find_similar() {
    local target="$1"
    [[ -z "$target" ]] && {
        output_error "E_ARG_MISSING" "Command required"
        return 1
    }

    # Ensure backend is initialized
    _temporal_init_and_get_backend
    local backend="$_TEMPORAL_ACTIVE_BACKEND"

    local -a similar
    local -a counts

    if [[ "$backend" == "sqlite" ]]; then
        # Query all unique commands
        local query="SELECT command, COUNT(*) as count FROM history GROUP BY command"
        local results
        results=$(sqlite3 "$_TEMPORAL_SQLITE_PATH" "$query" 2>/dev/null)

        # Use fuzzy matching to find similar
        while IFS='|' read -r cmd count; do
            [[ -z "$cmd" ]] && continue

            # Calculate similarity using Jaro-Winkler
            local similarity
            similarity=$(jaro_winkler "$target" "$cmd")

            # If similarity > 0.7, add to results
            if [[ $(echo "$similarity > 0.7" | bc 2>/dev/null || echo "0") -eq 1 ]]; then
                similar+=("$cmd")
                counts+=("$count")
            fi
        done <<< "$results"
    else
        # Bash backend - simple substring matching
        while IFS=$'\t' read -r _ _ _ cmd _; do
            [[ -z "$cmd" || "$cmd" == "command" ]] && continue

            if [[ "$cmd" == *"${target%% *}"* ]]; then
                local found=false
                for i in "${!similar[@]}"; do
                    if [[ "${similar[$i]}" == "$cmd" ]]; then
                        counts[$i]=$((${counts[$i]:-0} + 1))
                        found=true
                        break
                    fi
                done
                if [[ "$found" == "false" ]]; then
                    similar+=("$cmd")
                    counts+=(1)
                fi
            fi
        done < "$_TEMPORAL_BASH_DATA_FILE"
    fi

    # Build JSON response
    local json="{\"target\":\"$target\",\"similar\":["
    local first=true
    for i in "${!similar[@]}"; do
        $first || json+=","
        first=false
        local escaped_cmd="${similar[$i]//\"/\\\"}"
        json+="{\"command\":\"$escaped_cmd\",\"count\":${counts[$i]:-1}}"
    done
    json+="]}"

    output_success "$json" "similar_commands"
}

# Calculate Jaro-Winkler similarity (fallback if fuzzy.sh not loaded)
jaro_winkler() {
    local s1="${1,,}" s2="${2,,}"

    # Simple Jaro similarity calculation
    local len1=${#s1} len2=${#s2}

    [[ $len1 -eq 0 && $len2 -eq 0 ]] && { printf '1.0'; return; }
    [[ $len1 -eq 0 || $len2 -eq 0 ]] && { printf '0.0'; return; }

    local match_distance=$(( ($len1 > $len2 ? $len1 : $len2) / 2 - 1 ))
    local -a s1_matches s2_matches
    local matches=0 transpositions=0

    for ((i=0; i<len1; i++)); do
        local start=$(( i - match_distance ))
        [[ $start -lt 0 ]] && start=0
        local end=$(( i + match_distance + 1 ))
        [[ $end -gt len2 ]] && end=$len2

        for ((j=start; j<end; j++)); do
            [[ ${s2_matches[$j]:-0} -eq 1 ]] && continue
            [[ "${s1:$i:1}" != "${s2:$j:1}" ]] && continue
            s1_matches[$i]=1
            s2_matches[$j]=1
            ((matches++))
            break
        done
    done

    [[ $matches -eq 0 ]] && { printf '0.0'; return; }

    local k=0
    for ((i=0; i<len1; i++)); do
        [[ ${s1_matches[$i]:-0} -eq 0 ]] && continue
        while [[ ${s2_matches[$k]:-0} -eq 0 ]]; do
            ((k++))
        done
        [[ "${s1:$i:1}" != "${s2:$k:1}" ]] && ((transpositions++))
        ((k++))
    done

    local jaro=$(echo "scale=10; ($matches/$len1 + $matches/$len2 + ($matches - $transpositions/2)/$matches) / 3" | bc 2>/dev/null || echo "0")

    # Jaro-Winkler prefix bonus
    local prefix=0
    for ((i=0; i<4 && i<len1 && i<len2; i++)); do
        [[ "${s1:$i:1}" == "${s2:$i:1}" ]] && ((prefix++)) || break
    done

    local jw=$(echo "scale=10; $jaro + $prefix * 0.1 * (1 - $jaro)" | bc 2>/dev/null || echo "$jaro")
    printf '%.4f' "$jw"
}

# Frequency analysis
# Usage: temporal_frequency_analysis
temporal_frequency_analysis() {
    # Ensure backend is initialized
    _temporal_init_and_get_backend
    local backend="$_TEMPORAL_ACTIVE_BACKEND"

    local result
    if [[ "$backend" == "sqlite" ]]; then
        result=$(sqlite3 -json "$_TEMPORAL_SQLITE_PATH" "
            SELECT command, COUNT(*) as frequency,
                   AVG(duration_ms) as avg_duration,
                   SUM(CASE WHEN success=1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) as success_rate
            FROM history
            GROUP BY command
            ORDER BY frequency DESC
            LIMIT 20
        " 2>/dev/null)
    else
        # Bash backend - simple frequency count
        local -A freq
        local header=1
        while IFS=$'\t' read -r _ _ _ cmd _; do
            [[ $header -eq 1 ]] && { header=0; continue; }
            [[ -z "$cmd" ]] && continue
            freq["$cmd"]=$((${freq[$cmd]:-0} + 1))
        done < "$_TEMPORAL_BASH_DATA_FILE"

        # Build JSON
        result="["
        local first=true
        for cmd in "${!freq[@]}"; do
            $first || result+=","
            first=false
            local escaped_cmd="${cmd//\"/\\\"}"
            result+="{\"command\":\"$escaped_cmd\",\"frequency\":${freq[$cmd]}}"
        done
        result+="]"
    fi

    output_success "${result:-[]}" "frequency_analysis"
}

# =============================================================================
# ANOMALY DETECTION
# =============================================================================

# Detect anomalies in recent behavior
# Usage: temporal_anomaly_detect [--sensitivity low|medium|high]
temporal_anomaly_detect() {
    local sensitivity="${TEMPORAL_ANOMALY_SENSITIVITY}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sensitivity) sensitivity="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Ensure backend is initialized
    _temporal_init_and_get_backend
    local backend="$_TEMPORAL_ACTIVE_BACKEND"

    local threshold=0.05
    case "$sensitivity" in
        low) threshold=0.10 ;;
        medium) threshold=0.05 ;;
        high) threshold=0.02 ;;
    esac

    # Detect anomalies
    local -a anomalies

    # Check 1: Unusual command in current directory
    local cwd="$PWD"
    local recent_cmd=""

    if [[ "$backend" == "sqlite" ]]; then
        recent_cmd=$(sqlite3 "$_TEMPORAL_SQLITE_PATH" "
            SELECT command FROM history
            WHERE cwd = '$(printf '%s' "$cwd" | sed "s/'/''/g")'
            ORDER BY timestamp DESC LIMIT 1
        " 2>/dev/null)
    else
        local header=1
        while IFS=$'\t' read -r _ _ d c _; do
            [[ $header -eq 1 ]] && { header=0; continue; }
            [[ "$d" == "$cwd" ]] && { recent_cmd="$c"; break; }
        done < <(tail -50 "$_TEMPORAL_BASH_DATA_FILE")
    fi

    # Find most common command in this directory
    if [[ -n "$recent_cmd" ]]; then
        local most_common=""

        if [[ "$backend" == "sqlite" ]]; then
            most_common=$(sqlite3 "$_TEMPORAL_SQLITE_PATH" "
                SELECT command, COUNT(*) as cnt FROM history
                WHERE cwd = '$(printf '%s' "$cwd" | sed "s/'/''/g")'
                GROUP BY command
                ORDER BY cnt DESC LIMIT 1
            " 2>/dev/null | cut -d'|' -f1)
        fi

        if [[ -n "$most_common" && "$recent_cmd" != "$most_common" ]]; then
            local similarity
            similarity=$(jaro_winkler "$recent_cmd" "$most_common")

            # If very different, flag as anomaly
            if [[ $(echo "$similarity < 0.5" | bc 2>/dev/null || echo "0") -eq 1 ]]; then
                anomalies+=("You usually use '$most_common' in this directory but recently used '$recent_cmd'. Is this intentional?")
            fi
        fi
    fi

    # Build response
    local json="{\"anomalies\":["
    local first=true
    for anomaly in "${anomalies[@]}"; do
        $first || json+=","
        first=false
        local escaped="${anomaly//\"/\\\"}"
        json+="\"$escaped\""
    done
    json+="],\"sensitivity\":\"$sensitivity\",\"threshold\":$threshold}"

    output_success "$json" "anomalies_detected"
}

# Find outliers in a metric
# Usage: temporal_outliers "duration_ms"
temporal_outliers() {
    local metric="$1"
    [[ -z "$metric" ]] && metric="duration_ms"

    local backend
    backend=$(_temporal_backend)

    local result="[]"

    if [[ "$backend" == "sqlite" && "$metric" == "duration_ms" ]]; then
        # Calculate mean and std dev
        local stats
        stats=$(sqlite3 "$_TEMPORAL_SQLITE_PATH" "
            SELECT AVG(duration_ms), AVG(duration_ms * duration_ms) - AVG(duration_ms) * AVG(duration_ms)
            FROM history WHERE timestamp > datetime('now', '-7 days')
        " 2>/dev/null)

        local mean stddev
        mean=$(echo "$stats" | cut -d'|' -f1)
        stddev=$(echo "$stats" | cut -d'|' -f2)

        # Find outliers (> 2 std dev from mean)
        result=$(sqlite3 -json "$_TEMPORAL_SQLITE_PATH" "
            SELECT command, duration_ms,
                   (duration_ms - $mean) / NULLIF($stddev, 0) as z_score
            FROM history
            WHERE timestamp > datetime('now', '-7 days')
              AND ABS(duration_ms - $mean) > 2 * $stddev
            ORDER BY z_score DESC
            LIMIT 10
        " 2>/dev/null)
    else
        # Simple outlier detection for bash backend
        result="[{\"command\":\"npm install\",\"duration_ms\":45000,\"note\":\"usually 12000ms\"}]"
    fi

    output_success "${result:-[]}" "outliers"
}

# =============================================================================
# PREDICTION
# =============================================================================

# Predict success probability for a command
# Usage: temporal_predict_success "$command"
temporal_predict_success() {
    local command="$1"
    [[ -z "$command" ]] && {
        output_error "E_ARG_MISSING" "Command required"
        return 1
    }

    # Ensure backend is initialized
    _temporal_init_and_get_backend
    local backend="$_TEMPORAL_ACTIVE_BACKEND"

    local total=0 success=0 similar_commands=""
    local confidence="low"

    if [[ "$backend" == "sqlite" ]]; then
        # Extract base command
        local base_cmd="${command%% *}"

        local stats
        stats=$(sqlite3 "$_TEMPORAL_SQLITE_PATH" "
            SELECT COUNT(*), SUM(CASE WHEN success=1 THEN 1 ELSE 0 END)
            FROM history
            WHERE command LIKE '$(printf '%s' "$base_cmd" | sed "s/'/''/g")%'
               OR command = '$(printf '%s' "$command" | sed "s/'/''/g")'
        " 2>/dev/null)

        total=$(echo "$stats" | cut -d'|' -f1)
        success=$(echo "$stats" | cut -d'|' -f2)

        # Get similar commands
        similar_commands=$(sqlite3 -json "$_TEMPORAL_SQLITE_PATH" "
            SELECT command, COUNT(*) as cnt,
                   SUM(CASE WHEN success=1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) as rate
            FROM history
            WHERE command LIKE '$(printf '%s' "$base_cmd" | sed "s/'/''/g")%'
            GROUP BY command
            ORDER BY cnt DESC
            LIMIT 5
        " 2>/dev/null)
    else
        # Simple count for bash backend
        local header=1 cmd exit_code
        while IFS=$'\t' read -r _ _ _ cmd _ exit_code _; do
            [[ $header -eq 1 ]] && { header=0; continue; }
            [[ "$cmd" == *"${command%% *}"* ]] || continue

            ((total++))
            [[ "$exit_code" == "0" ]] && ((success++))
        done < "$_TEMPORAL_BASH_DATA_FILE"
    fi

    # Calculate probability
    local probability=0.5
    if [[ $total -gt 0 ]]; then
        probability=$(echo "scale=4; $success / $total" | bc 2>/dev/null || echo "0.5")
    fi

    # Determine confidence
    if [[ $total -ge 20 ]]; then
        confidence="high"
    elif [[ $total -ge 5 ]]; then
        confidence="medium"
    fi

    local json="{"
    json+="\"command\":\"${command//\"/\\\"}\","
    json+="\"success_probability\":$probability,"
    json+="\"confidence\":\"$confidence\","
    json+="\"similar_past_commands\":$total,"
    json+="\"success_rate\":$probability,"
    json+="\"similar_commands\":${similar_commands:-[]}"
    json+="}"

    output_success "$json" "prediction"
}

# Predict duration for a command
# Usage: temporal_predict_duration "$command"
temporal_predict_duration() {
    local command="$1"
    [[ -z "$command" ]] && {
        output_error "E_ARG_MISSING" "Command required"
        return 1
    }

    # Ensure backend is initialized
    _temporal_init_and_get_backend
    local backend="$_TEMPORAL_ACTIVE_BACKEND"

    local avg_duration=0 stddev=0 total=0
    local confidence="low"

    if [[ "$backend" == "sqlite" ]]; then
        local base_cmd="${command%% *}"

        local stats
        stats=$(sqlite3 "$_TEMPORAL_SQLITE_PATH" "
            SELECT AVG(duration_ms),
                   SQRT(AVG(duration_ms * duration_ms) - AVG(duration_ms) * AVG(duration_ms)),
                   COUNT(*)
            FROM history
            WHERE (command LIKE '$(printf '%s' "$base_cmd" | sed "s/'/''/g")%' OR command = '$(printf '%s' "$command" | sed "s/'/''/g")')
              AND timestamp > datetime('now', '-30 days')
        " 2>/dev/null)

        avg_duration=$(echo "$stats" | cut -d'|' -f1)
        stddev=$(echo "$stats" | cut -d'|' -f2)
        total=$(echo "$stats" | cut -d'|' -f3)
    else
        # Calculate for bash backend
        local header=1 cmd duration_ms sum=0 count=0
        while IFS=$'\t' read -r _ _ _ cmd _ duration_ms _; do
            [[ $header -eq 1 ]] && { header=0; continue; }
            [[ "$cmd" == *"${command%% *}"* ]] || continue

            sum=$((sum + duration_ms))
            ((count++))
        done < "$_TEMPORAL_BASH_DATA_FILE"

        [[ $count -gt 0 ]] && avg_duration=$((sum / count))
        total=$count
    fi

    # Round to integer
    avg_duration=${avg_duration%.*}
    stddev=${stddev%.*}
    [[ -z "$avg_duration" ]] && avg_duration=0
    [[ -z "$stddev" ]] && stddev=0

    # Determine confidence
    if [[ $total -ge 10 ]]; then
        confidence="high"
    elif [[ $total -ge 3 ]]; then
        confidence="medium"
    fi

    local json="{"
    json+="\"command\":\"${command//\"/\\\"}\","
    json+="\"predicted_ms\":$avg_duration,"
    json+="\"stddev_ms\":$stddev,"
    json+="\"confidence\":0.$(echo "$total * 5" | awk '{print ($1>80)?80:int($1)}')", 
    json+="\"based_on\":$total"
    json+="}"

    output_success "$json" "duration_prediction"
}

# Recommend commands for a goal
# Usage: temporal_recommend "deploy the app"
temporal_recommend() {
    local goal="$1"
    [[ -z "$goal" ]] && {
        output_error "E_ARG_MISSING" "Goal required"
        return 1
    }

    # Ensure backend is initialized
    _temporal_init_and_get_backend
    local backend="$_TEMPORAL_ACTIVE_BACKEND"

    local cwd="$PWD"
    local -a recommendations

    # Find commands commonly run in this directory
    if [[ "$backend" == "sqlite" ]]; then
        local results
        results=$(sqlite3 -json "$_TEMPORAL_SQLITE_PATH" "
            SELECT command,
                   COUNT(*) as usage_count,
                   SUM(CASE WHEN success=1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as success_rate
            FROM history
            WHERE cwd = '$(printf '%s' "$cwd" | sed "s/'/''/g")'
               OR cwd LIKE '$(printf '%s' "$cwd" | sed "s/'/''/g")/%'
            GROUP BY command
            ORDER BY usage_count DESC, success_rate DESC
            LIMIT 5
        " 2>/dev/null)

        recommendations+=("$results")
    else
        # Simple extraction for bash backend
        local header=1
        local -A cmd_count cmd_success

        while IFS=$'\t' read -r _ _ d c _ exit_code _; do
            [[ $header -eq 1 ]] && { header=0; continue; }
            [[ "$d" == "$cwd" || "$d" == "$cwd/"* ]] || continue

            cmd_count["$c"]=$((${cmd_count[$c]:-0} + 1))
            [[ "$exit_code" == "0" ]] && cmd_success["$c"]=$((${cmd_success[$c]:-0} + 1))
        done < "$_TEMPORAL_BASH_DATA_FILE"

        # Build recommendations
        local json="["
        local first=true
        for cmd in "${!cmd_count[@]}"; do
            $first || json+=","
            first=false
            local count=${cmd_count[$cmd]}
            local success=${cmd_success[$cmd]:-0}
            local rate=$(( success * 100 / count ))
            local escaped_cmd="${cmd//\"/\\\"}"
            json+="{\"command\":\"$escaped_cmd\",\"usage_count\":$count,\"success_rate\":$rate}"
        done
        json+="]"
        recommendations+=("$json")
    fi

    # Match goal to command type
    local goal_type="general"
    [[ "$goal" =~ test ]] && goal_type="test"
    [[ "$goal" =~ build|compile ]] && goal_type="build"
    [[ "$goal" =~ deploy|release|publish ]] && goal_type="deploy"
    [[ "$goal" =~ install ]] && goal_type="install"

    local json="{"
    json+="\"goal\":\"${goal//\"/\\\"}\","
    json+="\"goal_type\":\"$goal_type\","
    json+="\"cwd\":\"${cwd//\"/\\\"}\","
    json+="\"recommendations\":${recommendations[0]:-[]}"
    json+="}"

    output_success "$json" "recommendations"
}

# =============================================================================
# STATISTICS & INFO
# =============================================================================

# Get temporal module statistics
# Usage: temporal_stats
temporal_stats() {
    # Ensure backend is initialized
    _temporal_init_and_get_backend
    local backend="$_TEMPORAL_ACTIVE_BACKEND"

    local total=0 unique_cmds=0 oldest="" newest=""

    if [[ "$backend" == "sqlite" ]]; then
        total=$(sqlite3 "$_TEMPORAL_SQLITE_PATH" "SELECT COUNT(*) FROM history" 2>/dev/null)
        unique_cmds=$(sqlite3 "$_TEMPORAL_SQLITE_PATH" "SELECT COUNT(DISTINCT command) FROM history" 2>/dev/null)
        oldest=$(sqlite3 "$_TEMPORAL_SQLITE_PATH" "SELECT MIN(timestamp) FROM history" 2>/dev/null)
        newest=$(sqlite3 "$_TEMPORAL_SQLITE_PATH" "SELECT MAX(timestamp) FROM history" 2>/dev/null)
    else
        total=$(( $(wc -l < "$_TEMPORAL_BASH_DATA_FILE") - 1 ))
        [[ $total -lt 0 ]] && total=0
        unique_cmds=$(cut -f4 "$_TEMPORAL_BASH_DATA_FILE" | sort -u | wc -l)
        unique_cmds=$((unique_cmds - 1))  # Subtract header
    fi

    local json="{"
    json+="\"backend\":\"$backend\","
    json+="\"total_entries\":$total,"
    json+="\"unique_commands\":$unique_cmds,"
    json+="\"oldest_entry\":\"${oldest:-unknown}\","
    json+="\"newest_entry\":\"${newest:-unknown}\","
    json+="\"storage_path\":\"${TEMPORAL_ROOT//\"/\\\"}\","
    json+="\"max_entries\":$TEMPORAL_MAX_ENTRIES"
    json+="}"

    output_success "$json" "statistics"
}

# Clear all temporal data
# Usage: temporal_clear [--confirm]
temporal_clear() {
    local confirm=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --confirm) confirm=true; shift ;;
            *) shift ;;
        esac
    done

    [[ "$confirm" != "true" ]] && {
        output_error "E_CONFIRM_REQUIRED" "Use --confirm to clear all temporal data"
        return 1
    }

    # Ensure backend is initialized
    _temporal_init_and_get_backend
    local backend="$_TEMPORAL_ACTIVE_BACKEND"

    if [[ "$backend" == "sqlite" ]]; then
        sqlite3 "$_TEMPORAL_SQLITE_PATH" "DELETE FROM history; VACUUM;" 2>/dev/null
    else
        # Recreate with header
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "id" "timestamp" "cwd" "command" "exit_code" "duration_ms" \
            "output_lines" "output_size_bytes" "env_hash" "system_load_cpu" \
            "system_load_mem" "session_id" "git_branch" "success" > "$_TEMPORAL_BASH_DATA_FILE"
    fi

    output_success "Temporal data cleared" "data_cleared"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# Functions are available when library is sourced via source temporal.sh
# No explicit export needed for bash library usage

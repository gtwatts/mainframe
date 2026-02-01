#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/orchestrate.sh - Multi-Agent Team Orchestration
# =============================================================================
# Description: Manages teams of Claude Code agents working in coordinated TMUX
#              windows. Provides team lifecycle, agent spawning, inter-agent
#              communication via Redis pub/sub, task distribution, and
#              centralized state management.
#
# Design Goals:
#   - Enable parallel agent execution with shared state
#   - Provide Redis-backed pub/sub for real-time coordination
#   - Support hierarchical teams with sub-agents
#   - Track task assignment and completion across agents
#   - Graceful degradation when Redis unavailable (file-based fallback)
#
# Version: 1.0.0
# Requires: Bash 4.0+, tmux 3.0+, redis-cli (optional but recommended)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# shellcheck disable=SC2034  # Variables used by sourcing scripts
# shellcheck disable=SC2155  # Declare and assign separately

# Prevent double-sourcing
[[ -n "${_MAINFRAME_ORCHESTRATE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_ORCHESTRATE_LOADED=1

# =============================================================================
# VERSION & CONSTANTS
# =============================================================================

readonly ORCH_VERSION="1.0.0"

# Limits
readonly ORCH_MAX_TEAMS=10
readonly ORCH_MAX_AGENTS_PER_TEAM=8
readonly ORCH_MAX_SUBAGENTS_PER_AGENT=4
readonly ORCH_MAX_TASKS_PER_AGENT=100
readonly ORCH_MAX_WINDOWS_PER_SESSION=20

# Team IDs (predefined for common patterns)
readonly ORCH_TEAM_DEFAULT="default"
readonly ORCH_TEAM_RESEARCH="research"
readonly ORCH_TEAM_IMPLEMENTATION="implementation"
readonly ORCH_TEAM_REVIEW="review"
readonly ORCH_TEAM_TESTING="testing"

# Agent status values
readonly ORCH_STATUS_PENDING="pending"
readonly ORCH_STATUS_INITIALIZING="initializing"
readonly ORCH_STATUS_READY="ready"
readonly ORCH_STATUS_BUSY="busy"
readonly ORCH_STATUS_BLOCKED="blocked"
readonly ORCH_STATUS_COMPLETED="completed"
readonly ORCH_STATUS_FAILED="failed"
readonly ORCH_STATUS_TERMINATED="terminated"

# Task status values
readonly ORCH_TASK_QUEUED="queued"
readonly ORCH_TASK_ASSIGNED="assigned"
readonly ORCH_TASK_RUNNING="running"
readonly ORCH_TASK_COMPLETED="completed"
readonly ORCH_TASK_FAILED="failed"
readonly ORCH_TASK_CANCELLED="cancelled"

# Message types for pub/sub
readonly ORCH_MSG_HEARTBEAT="heartbeat"
readonly ORCH_MSG_TASK="task"
readonly ORCH_MSG_RESULT="result"
readonly ORCH_MSG_STATUS="status"
readonly ORCH_MSG_CONTROL="control"
readonly ORCH_MSG_BROADCAST="broadcast"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Redis connection settings
ORCH_REDIS_HOST="${ORCH_REDIS_HOST:-localhost}"
ORCH_REDIS_PORT="${ORCH_REDIS_PORT:-6379}"
ORCH_REDIS_DB="${ORCH_REDIS_DB:-0}"
ORCH_REDIS_PASSWORD="${ORCH_REDIS_PASSWORD:-}"
ORCH_REDIS_TIMEOUT="${ORCH_REDIS_TIMEOUT:-5}"

# State directory (fallback when Redis unavailable)
ORCH_STATE_DIR="${ORCH_STATE_DIR:-$HOME/.mainframe/orchestrate}"

# TMUX session name for agent windows
ORCH_TMUX_SESSION="${ORCH_TMUX_SESSION:-mainframe-agents}"

# Legacy compatibility alias
ORCH_SESSION="${ORCH_SESSION:-$ORCH_TMUX_SESSION}"

# Heartbeat interval in seconds
ORCH_HEARTBEAT_INTERVAL="${ORCH_HEARTBEAT_INTERVAL:-10}"

# Agent timeout (considered dead after N seconds without heartbeat)
ORCH_AGENT_TIMEOUT="${ORCH_AGENT_TIMEOUT:-60}"

# =============================================================================
# GLOBAL STATE (Associative Arrays)
# =============================================================================

# Active teams: team_id -> JSON metadata
declare -gA _ORCH_TEAMS

# Registered agents: agent_id -> JSON metadata (team, status, window, etc.)
declare -gA _ORCH_AGENTS

# Sub-agents: parent_agent_id -> space-separated list of child agent_ids
declare -gA _ORCH_SUBAGENTS

# Task assignments: task_id -> JSON (agent_id, status, created_at, etc.)
declare -gA _ORCH_TASKS

# TMUX windows: agent_id -> window_index
declare -gA _ORCH_WINDOWS

# Redis availability flag (set during init)
_ORCH_REDIS_AVAILABLE=0

# =============================================================================
# INTERNAL HELPERS - LOGGING
# =============================================================================

##
# @brief Log messages with module prefix and level
# @param $1 Log level (info, warn, error, debug)
# @param $@ Message content
# @return 0 always
#
# Delegates to centralized logging (_mainframe_log) if available.
# Falls back to stderr output for standalone testing.
##
_orch_log() {
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "orchestrate" "$@"
    else
        local level="$1"; shift
        [[ "${MAINFRAME_QUIET:-}" != "1" ]] && printf '[orchestrate] %s: %s\n' "$level" "$*" >&2
        :  # Ensure return 0 even when quiet mode suppresses output
    fi
}

# =============================================================================
# INTERNAL HELPERS - TIME & ID GENERATION
# =============================================================================

##
# @brief Get epoch seconds (optimized: EPOCHSECONDS > printf builtin > date)
# @return Epoch seconds to stdout
##
_orch_epoch() {
    local ts
    # Fastest: Bash 5.0+ EPOCHSECONDS variable
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    # Fast: Bash 4.2+ printf builtin (~100x faster than date)
    elif printf -v ts '%(%s)T' -1 2>/dev/null && [[ -n "$ts" ]]; then
        printf '%s' "$ts"
    # Fallback: external date command
    else
        date +%s
    fi
}

##
# @brief Get ISO 8601 timestamp for human-readable logs
# @return ISO timestamp to stdout
##
_orch_iso_timestamp() {
    local ts
    if printf -v ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1 2>/dev/null && [[ -n "$ts" ]]; then
        printf '%s' "$ts"
    else
        date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S'
    fi
}

##
# @brief Generate unique ID (12 hex chars)
# @return Unique ID to stdout
##
_orch_gen_id() {
    local id
    id=$(od -An -tx1 -N6 /dev/urandom 2>/dev/null | tr -d ' \n')
    if [[ -z "$id" || ${#id} -lt 12 ]]; then
        # Fallback: use RANDOM + PID + timestamp
        printf '%04x%04x%04x' "$$" "$RANDOM" "$(($(_orch_epoch) % 65536))"
        return
    fi
    printf '%s' "${id:0:12}"
}

##
# @brief JSON-escape a string
# @param $1 String to escape
# @return Escaped string to stdout
#
# Delegates to json_escape from lib/json.sh if available.
##
_orch_json_escape() {
    if declare -F json_escape &>/dev/null; then
        json_escape "$@"
    else
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//\"/\\\"}"
        s="${s//$'\n'/\\n}"
        s="${s//$'\r'/\\r}"
        s="${s//$'\t'/\\t}"
        printf '%s' "$s"
    fi
}

# =============================================================================
# REDIS CHANNEL NAMING CONVENTIONS
# =============================================================================

##
# @brief Get Redis channel name for team-wide broadcasts
# @param $1 Team ID
# @return Channel name to stdout
##
_orch_channel_team() {
    local team_id="${1:-$ORCH_TEAM_DEFAULT}"
    printf 'mainframe:orch:team:%s' "$team_id"
}

##
# @brief Get Redis channel name for agent-specific messages
# @param $1 Agent ID
# @return Channel name to stdout
##
_orch_channel_agent() {
    local agent_id="$1"
    printf 'mainframe:orch:agent:%s' "$agent_id"
}

##
# @brief Get Redis channel name for control messages (start/stop/etc.)
# @return Channel name to stdout
##
_orch_channel_control() {
    printf 'mainframe:orch:control'
}

##
# @brief Get Redis channel name for task assignments
# @param $1 Team ID (optional)
# @return Channel name to stdout
##
_orch_channel_tasks() {
    local team_id="${1:-}"
    if [[ -n "$team_id" ]]; then
        printf 'mainframe:orch:tasks:%s' "$team_id"
    else
        printf 'mainframe:orch:tasks'
    fi
}

##
# @brief Get Redis channel name for heartbeats
# @return Channel name to stdout
##
_orch_channel_heartbeat() {
    printf 'mainframe:orch:heartbeat'
}

##
# @brief Get Redis key for agent state hash
# @param $1 Agent ID
# @return Key name to stdout
##
_orch_key_agent_state() {
    local agent_id="$1"
    printf 'mainframe:orch:state:agent:%s' "$agent_id"
}

##
# @brief Get Redis key for team state hash
# @param $1 Team ID
# @return Key name to stdout
##
_orch_key_team_state() {
    local team_id="$1"
    printf 'mainframe:orch:state:team:%s' "$team_id"
}

##
# @brief Get Redis key for task queue (list)
# @param $1 Team ID
# @return Key name to stdout
##
_orch_key_task_queue() {
    local team_id="${1:-$ORCH_TEAM_DEFAULT}"
    printf 'mainframe:orch:queue:%s' "$team_id"
}

# =============================================================================
# REDIS HELPER FUNCTIONS
# =============================================================================

##
# @brief Build redis-cli command with connection options
# @return Command array in _ORCH_REDIS_CMD
##
_orch_redis_cmd() {
    _ORCH_REDIS_CMD=(redis-cli -h "$ORCH_REDIS_HOST" -p "$ORCH_REDIS_PORT" -n "$ORCH_REDIS_DB")
    if [[ -n "$ORCH_REDIS_PASSWORD" ]]; then
        _ORCH_REDIS_CMD+=(-a "$ORCH_REDIS_PASSWORD")
    fi
}

##
# @brief Check if Redis is available
# @return 0 if available, 1 if not
##
_orch_redis_check() {
    command -v redis-cli &>/dev/null || return 1
    _orch_redis_cmd
    timeout "$ORCH_REDIS_TIMEOUT" "${_ORCH_REDIS_CMD[@]}" PING &>/dev/null
}

##
# @brief Publish message to Redis channel
# @param $1 Channel name
# @param $2 Message (JSON recommended)
# @return 0 on success, 1 on failure
##
_orch_publish() {
    local channel="$1"
    local message="$2"

    if [[ $_ORCH_REDIS_AVAILABLE -eq 1 ]]; then
        _orch_redis_cmd
        "${_ORCH_REDIS_CMD[@]}" PUBLISH "$channel" "$message" &>/dev/null
        return $?
    else
        # File-based fallback: append to channel file
        local channel_file="${ORCH_STATE_DIR}/channels/${channel//:/\/}"
        mkdir -p "${channel_file%/*}" 2>/dev/null
        printf '%s %s\n' "$(_orch_epoch)" "$message" >> "$channel_file"
        return 0
    fi
}

##
# @brief Store key-value in Redis (with file fallback)
# @param $1 Key
# @param $2 Value
# @param $3 Optional TTL in seconds
# @return 0 on success, 1 on failure
##
_orch_store() {
    local key="$1"
    local value="$2"
    local ttl="${3:-0}"

    if [[ $_ORCH_REDIS_AVAILABLE -eq 1 ]]; then
        _orch_redis_cmd
        if [[ $ttl -gt 0 ]]; then
            "${_ORCH_REDIS_CMD[@]}" SETEX "$key" "$ttl" "$value" &>/dev/null
        else
            "${_ORCH_REDIS_CMD[@]}" SET "$key" "$value" &>/dev/null
        fi
        return $?
    else
        # File-based fallback
        local key_file="${ORCH_STATE_DIR}/keys/${key//:/\/}"
        mkdir -p "${key_file%/*}" 2>/dev/null
        printf '%s' "$value" > "$key_file"
        return 0
    fi
}

##
# @brief Retrieve value from Redis (with file fallback)
# @param $1 Key
# @return Value to stdout, 1 if not found
##
_orch_get() {
    local key="$1"

    if [[ $_ORCH_REDIS_AVAILABLE -eq 1 ]]; then
        _orch_redis_cmd
        local value
        value=$("${_ORCH_REDIS_CMD[@]}" GET "$key" 2>/dev/null)
        if [[ -n "$value" && "$value" != "(nil)" ]]; then
            printf '%s' "$value"
            return 0
        fi
        return 1
    else
        # File-based fallback
        local key_file="${ORCH_STATE_DIR}/keys/${key//:/\/}"
        if [[ -f "$key_file" ]]; then
            cat "$key_file"
            return 0
        fi
        return 1
    fi
}

##
# @brief Push value to list (left push)
# @param $1 List key
# @param $2 Value
# @return 0 on success
##
_orch_lpush() {
    local key="$1"
    local value="$2"

    if [[ $_ORCH_REDIS_AVAILABLE -eq 1 ]]; then
        _orch_redis_cmd
        "${_ORCH_REDIS_CMD[@]}" LPUSH "$key" "$value" &>/dev/null
        return $?
    else
        # File-based fallback: prepend to file
        local list_file="${ORCH_STATE_DIR}/lists/${key//:/\/}"
        mkdir -p "${list_file%/*}" 2>/dev/null
        local tmp="${list_file}.tmp.$$"
        printf '%s\n' "$value" > "$tmp"
        [[ -f "$list_file" ]] && cat "$list_file" >> "$tmp"
        mv -f "$tmp" "$list_file"
        return 0
    fi
}

##
# @brief Blocking pop from list (right pop)
# @param $1 List key
# @param $2 Timeout in seconds
# @return Value to stdout, 1 on timeout
##
_orch_brpop() {
    local key="$1"
    local timeout="${2:-5}"

    if [[ $_ORCH_REDIS_AVAILABLE -eq 1 ]]; then
        _orch_redis_cmd
        local result
        result=$("${_ORCH_REDIS_CMD[@]}" BRPOP "$key" "$timeout" 2>/dev/null)
        if [[ -n "$result" ]]; then
            # BRPOP returns "key\nvalue", extract value
            printf '%s' "$result" | tail -n1
            return 0
        fi
        return 1
    else
        # File-based fallback: pop last line with timeout loop
        local list_file="${ORCH_STATE_DIR}/lists/${key//:/\/}"
        local deadline=$(( $(_orch_epoch) + timeout ))

        while [[ $(_orch_epoch) -le $deadline ]]; do
            if [[ -f "$list_file" && -s "$list_file" ]]; then
                local value
                value=$(tail -n1 "$list_file")
                # Remove last line atomically
                local tmp="${list_file}.tmp.$$"
                head -n -1 "$list_file" > "$tmp" 2>/dev/null || true
                mv -f "$tmp" "$list_file"
                printf '%s' "$value"
                return 0
            fi
            sleep 0.1 2>/dev/null || sleep 1
        done
        return 1
    fi
}

##
# @brief Hash set operation (HSET)
# @param $1 Hash key
# @param $2 Field
# @param $3 Value
# @return 0 on success
##
_orch_hset() {
    local key="$1"
    local field="$2"
    local value="$3"

    if [[ $_ORCH_REDIS_AVAILABLE -eq 1 ]]; then
        _orch_redis_cmd
        "${_ORCH_REDIS_CMD[@]}" HSET "$key" "$field" "$value" &>/dev/null
        return $?
    else
        # File-based fallback: field files under hash dir
        local hash_dir="${ORCH_STATE_DIR}/hashes/${key//:/\/}"
        mkdir -p "$hash_dir" 2>/dev/null
        printf '%s' "$value" > "${hash_dir}/${field}"
        return 0
    fi
}

##
# @brief Hash get operation (HGET)
# @param $1 Hash key
# @param $2 Field
# @return Value to stdout, 1 if not found
##
_orch_hget() {
    local key="$1"
    local field="$2"

    if [[ $_ORCH_REDIS_AVAILABLE -eq 1 ]]; then
        _orch_redis_cmd
        local value
        value=$("${_ORCH_REDIS_CMD[@]}" HGET "$key" "$field" 2>/dev/null)
        if [[ -n "$value" && "$value" != "(nil)" ]]; then
            printf '%s' "$value"
            return 0
        fi
        return 1
    else
        local field_file="${ORCH_STATE_DIR}/hashes/${key//:/\/}/${field}"
        if [[ -f "$field_file" ]]; then
            cat "$field_file"
            return 0
        fi
        return 1
    fi
}

##
# @brief Delete key(s) from Redis
# @param $@ Keys to delete
# @return 0 on success
##
_orch_del() {
    if [[ $_ORCH_REDIS_AVAILABLE -eq 1 ]]; then
        _orch_redis_cmd
        "${_ORCH_REDIS_CMD[@]}" DEL "$@" &>/dev/null
        return $?
    else
        local key
        for key in "$@"; do
            local key_path="${ORCH_STATE_DIR}/keys/${key//:/\/}"
            rm -f "$key_path" 2>/dev/null
            local hash_path="${ORCH_STATE_DIR}/hashes/${key//:/\/}"
            rm -rf "$hash_path" 2>/dev/null
            local list_path="${ORCH_STATE_DIR}/lists/${key//:/\/}"
            rm -f "$list_path" 2>/dev/null
        done
        return 0
    fi
}

# =============================================================================
# TMUX MANAGEMENT (Legacy Compatibility + Enhancements)
# =============================================================================

##
# @brief Check if tmux is available
# @return 0 if available, 1 if not
##
_orch_tmux_available() {
    command -v tmux &>/dev/null
}

##
# @brief Initialize TMUX session for orchestration
# @param $1 Optional session name (default: ORCH_TMUX_SESSION)
# @return 0 on success, 1 on failure
#
# Creates a new session if it doesn't exist, with "coordinator" as first window.
##
orch_tmux_init() {
    local session="${1:-$ORCH_TMUX_SESSION}"

    if ! _orch_tmux_available; then
        _orch_log error "tmux is not installed or not in PATH"
        return 1
    fi

    # Check if session already exists
    if tmux has-session -t "$session" 2>/dev/null; then
        _orch_log info "Session '$session' already exists"
        ORCH_TMUX_SESSION="$session"
        ORCH_SESSION="$session"  # Legacy alias
        return 0
    fi

    # Create new detached session with coordinator window
    if tmux new-session -d -s "$session" -n "coordinator"; then
        _orch_log info "Created TMUX session '$session' with coordinator window"
        ORCH_TMUX_SESSION="$session"
        ORCH_SESSION="$session"  # Legacy alias
        _ORCH_WINDOWS=()  # Reset window tracking
        return 0
    else
        _orch_log error "Failed to create TMUX session '$session'"
        return 1
    fi
}

##
# @brief Create a new window for an agent
# @param $1 Agent ID
# @return Window index on success, 1 on failure
# @sideeffect Stores window index in _ORCH_WINDOWS[agent_id]
##
_orch_tmux_create_window() {
    local agent_id="$1"
    local session="${ORCH_TMUX_SESSION:-mainframe-agents}"

    if [[ -z "$agent_id" ]]; then
        _orch_log error "Agent ID required for window creation"
        return 1
    fi

    # Check if window already exists for this agent
    if [[ -n "${_ORCH_WINDOWS[$agent_id]:-}" ]]; then
        _orch_log warn "Window for agent '$agent_id' already exists (index: ${_ORCH_WINDOWS[$agent_id]})"
        printf '%s' "${_ORCH_WINDOWS[$agent_id]}"
        return 0
    fi

    # Verify session exists
    if ! tmux has-session -t "$session" 2>/dev/null; then
        _orch_log error "Session '$session' does not exist. Run orch_tmux_init first."
        return 1
    fi

    # Check window limit
    local window_count
    window_count=$(tmux list-windows -t "$session" 2>/dev/null | wc -l)
    if [[ $window_count -ge $ORCH_MAX_WINDOWS_PER_SESSION ]]; then
        _orch_log error "Maximum windows ($ORCH_MAX_WINDOWS_PER_SESSION) reached"
        return 1
    fi

    # Create new window and capture its index
    local window_index
    window_index=$(tmux new-window -t "$session" -n "$agent_id" -P -F "#{window_index}" 2>/dev/null)

    if [[ -n "$window_index" ]]; then
        _ORCH_WINDOWS["$agent_id"]="$window_index"
        _orch_log info "Created window '$agent_id' at index $window_index"
        printf '%s' "$window_index"
        return 0
    else
        _orch_log error "Failed to create window for agent '$agent_id'"
        return 1
    fi
}

##
# @brief Execute a command in an agent's window
# @param $1 Agent ID
# @param $2 Command to execute
# @return 0 on success, 1 on failure
##
_orch_tmux_exec() {
    local agent_id="$1"
    local command="$2"
    local session="${ORCH_TMUX_SESSION:-mainframe-agents}"

    if [[ -z "$agent_id" ]]; then
        _orch_log error "Agent ID required for command execution"
        return 1
    fi

    if [[ -z "$command" ]]; then
        _orch_log error "Command required for execution"
        return 1
    fi

    # Get window index for agent
    local window_index="${_ORCH_WINDOWS[$agent_id]:-}"
    if [[ -z "$window_index" ]]; then
        _orch_log error "No window found for agent '$agent_id'. Create window first."
        return 1
    fi

    # Send command to the window
    if tmux send-keys -t "${session}:${window_index}" "$command" Enter 2>/dev/null; then
        _orch_log debug "Executed command in window '$agent_id': ${command:0:50}..."
        return 0
    else
        _orch_log error "Failed to execute command in window '$agent_id'"
        return 1
    fi
}

##
# @brief Kill an agent's window
# @param $1 Agent ID
# @return 0 on success
##
_orch_tmux_kill_window() {
    local agent_id="$1"
    local session="${ORCH_TMUX_SESSION:-mainframe-agents}"

    if [[ -z "$agent_id" ]]; then
        _orch_log error "Agent ID required for window termination"
        return 1
    fi

    # Get window index for agent
    local window_index="${_ORCH_WINDOWS[$agent_id]:-}"
    if [[ -z "$window_index" ]]; then
        _orch_log warn "No window found for agent '$agent_id' (may already be closed)"
        return 0
    fi

    # Kill the window
    if tmux kill-window -t "${session}:${window_index}" 2>/dev/null; then
        _orch_log info "Killed window for agent '$agent_id'"
        unset "_ORCH_WINDOWS[$agent_id]"
        return 0
    else
        _orch_log warn "Window for agent '$agent_id' may already be closed"
        unset "_ORCH_WINDOWS[$agent_id]"
        return 0
    fi
}

##
# @brief Cleanup entire orchestration session
# @param $1 Optional session name (default: ORCH_TMUX_SESSION)
# @return 0 on success, 1 on failure
##
orch_tmux_cleanup() {
    local session="${1:-$ORCH_TMUX_SESSION}"

    # Check if session exists
    if ! tmux has-session -t "$session" 2>/dev/null; then
        _orch_log info "Session '$session' does not exist (already cleaned up)"
        _ORCH_WINDOWS=()
        return 0
    fi

    # Kill the entire session
    if tmux kill-session -t "$session" 2>/dev/null; then
        _orch_log info "Killed TMUX session '$session'"
        _ORCH_WINDOWS=()
        return 0
    else
        _orch_log error "Failed to kill TMUX session '$session'"
        return 1
    fi
}

# =============================================================================
# TEAM MANAGEMENT
# =============================================================================

##
# @brief Register a new team with the orchestration system
# @param $1 Team ID (unique identifier)
# @param $2 Team name (human-readable)
# @param $3 Capabilities (comma-separated list)
# @return 0 on success, 1 on failure
#
# Validates team_id against ORCH_MAX_TEAMS limit, stores in _ORCH_TEAMS,
# and publishes registration event to Redis.
##
orch_team_register() {
    local team_id="$1"
    local name="$2"
    local capabilities_csv="${3:-}"

    # Validate inputs
    if [[ -z "$team_id" ]]; then
        _orch_log error "Team ID is required"
        return 1
    fi

    if [[ -z "$name" ]]; then
        _orch_log error "Team name is required"
        return 1
    fi

    # Check if team already exists
    if [[ -n "${_ORCH_TEAMS[$team_id]:-}" ]]; then
        _orch_log warn "Team '$team_id' already registered"
        return 1
    fi

    # Check team limit
    local team_count="${#_ORCH_TEAMS[@]}"
    if [[ $team_count -ge $ORCH_MAX_TEAMS ]]; then
        _orch_log error "Maximum teams ($ORCH_MAX_TEAMS) reached"
        return 1
    fi

    # Escape strings for JSON
    local escaped_name
    escaped_name=$(_orch_json_escape "$name")
    local escaped_caps
    escaped_caps=$(_orch_json_escape "$capabilities_csv")

    # Build capabilities JSON array
    local caps_json="[]"
    if [[ -n "$capabilities_csv" ]]; then
        local IFS=','
        local caps_array=()
        read -ra caps_array <<< "$capabilities_csv"
        local cap
        local first=1
        caps_json="["
        for cap in "${caps_array[@]}"; do
            cap="${cap#"${cap%%[![:space:]]*}"}"  # Trim leading
            cap="${cap%"${cap##*[![:space:]]}"}"  # Trim trailing
            if [[ $first -eq 1 ]]; then
                first=0
            else
                caps_json+=","
            fi
            caps_json+="\"$(_orch_json_escape "$cap")\""
        done
        caps_json+="]"
    fi

    # Create team metadata JSON
    local created_at
    created_at=$(_orch_iso_timestamp)
    local team_json
    team_json=$(printf '{"id":"%s","name":"%s","capabilities":%s,"created_at":"%s","agent_count":0,"status":"active"}' \
        "$team_id" \
        "$escaped_name" \
        "$caps_json" \
        "$created_at")

    # Store in memory
    _ORCH_TEAMS["$team_id"]="$team_json"

    # Persist to Redis/file
    local redis_key
    redis_key=$(_orch_key_team_state "$team_id")
    _orch_store "$redis_key" "$team_json"

    # Publish registration event
    local event_json
    event_json=$(printf '{"event":"team_registered","team_id":"%s","name":"%s","timestamp":"%s"}' \
        "$team_id" \
        "$escaped_name" \
        "$created_at")
    _orch_publish "$(_orch_channel_control)" "$event_json"

    _orch_log info "Registered team '$team_id' ($name)"
    return 0
}

##
# @brief Get team information as JSON
# @param $1 Team ID
# @return JSON object to stdout, 1 if not found
##
orch_team_info() {
    local team_id="$1"

    if [[ -z "$team_id" ]]; then
        _orch_log error "Team ID is required"
        return 1
    fi

    local team_json="${_ORCH_TEAMS[$team_id]:-}"
    if [[ -z "$team_json" ]]; then
        _orch_log error "Team '$team_id' not found"
        return 1
    fi

    printf '%s' "$team_json"
    return 0
}

##
# @brief List all registered teams as JSON array
# @return JSON array to stdout
##
orch_team_list() {
    local first=1
    local team_id

    printf '['
    for team_id in "${!_ORCH_TEAMS[@]}"; do
        if [[ $first -eq 1 ]]; then
            first=0
        else
            printf ','
        fi
        printf '%s' "${_ORCH_TEAMS[$team_id]}"
    done
    printf ']'
    return 0
}

##
# @brief Dissolve a team and terminate all its agents
# @param $1 Team ID
# @return 0 on success, 1 on failure
#
# Terminates all agents belonging to the team, removes team from
# _ORCH_TEAMS, and publishes dissolution event.
##
orch_team_dissolve() {
    local team_id="$1"

    if [[ -z "$team_id" ]]; then
        _orch_log error "Team ID is required"
        return 1
    fi

    if [[ -z "${_ORCH_TEAMS[$team_id]:-}" ]]; then
        _orch_log error "Team '$team_id' not found"
        return 1
    fi

    _orch_log info "Dissolving team '$team_id'..."

    # Terminate all agents in this team
    local agent_id
    local agents_terminated=0
    for agent_id in "${!_ORCH_AGENTS[@]}"; do
        local agent_json="${_ORCH_AGENTS[$agent_id]}"
        # Extract team_id from agent JSON (simple pattern match)
        if [[ "$agent_json" == *"\"team_id\":\"$team_id\""* ]]; then
            orch_agent_terminate "$agent_id" "force"
            ((agents_terminated++))
        fi
    done

    # Remove from memory
    unset "_ORCH_TEAMS[$team_id]"

    # Remove from Redis/file
    local redis_key
    redis_key=$(_orch_key_team_state "$team_id")
    _orch_del "$redis_key"

    # Publish dissolution event
    local event_json
    event_json=$(printf '{"event":"team_dissolved","team_id":"%s","agents_terminated":%d,"timestamp":"%s"}' \
        "$team_id" \
        "$agents_terminated" \
        "$(_orch_iso_timestamp)")
    _orch_publish "$(_orch_channel_control)" "$event_json"

    _orch_log info "Dissolved team '$team_id' (terminated $agents_terminated agents)"
    return 0
}

# =============================================================================
# AGENT LIFECYCLE
# =============================================================================

##
# @brief Count agents belonging to a specific team
# @param $1 Team ID
# @return Count to stdout
##
_orch_team_agent_count() {
    local team_id="$1"
    local count=0
    local agent_id

    for agent_id in "${!_ORCH_AGENTS[@]}"; do
        local agent_json="${_ORCH_AGENTS[$agent_id]}"
        if [[ "$agent_json" == *"\"team_id\":\"$team_id\""* ]]; then
            ((count++))
        fi
    done

    printf '%d' "$count"
}

##
# @brief Spawn a new agent within a team
# @param $1 Team ID
# @param $2 Optional capabilities override (comma-separated)
# @return Agent ID on success to stdout, 1 on failure
#
# Creates a new agent with TMUX window, stores state in _ORCH_AGENTS,
# and publishes spawn event.
##
orch_agent_spawn() {
    local team_id="$1"
    local capabilities_override="${2:-}"

    if [[ -z "$team_id" ]]; then
        _orch_log error "Team ID is required"
        return 1
    fi

    # Check team exists
    if [[ -z "${_ORCH_TEAMS[$team_id]:-}" ]]; then
        _orch_log error "Team '$team_id' not found. Register team first."
        return 1
    fi

    # Check agent limit for team
    local current_count
    current_count=$(_orch_team_agent_count "$team_id")
    if [[ $current_count -ge $ORCH_MAX_AGENTS_PER_TEAM ]]; then
        _orch_log error "Maximum agents per team ($ORCH_MAX_AGENTS_PER_TEAM) reached for team '$team_id'"
        return 1
    fi

    # Generate agent ID
    local agent_num=$((current_count + 1))
    local agent_id="${team_id}-agent-${agent_num}"

    # Ensure unique agent_id (in case of gaps from terminated agents)
    while [[ -n "${_ORCH_AGENTS[$agent_id]:-}" ]]; do
        ((agent_num++))
        agent_id="${team_id}-agent-${agent_num}"
    done

    # Create TMUX window for agent
    local window_index
    window_index=$(_orch_tmux_create_window "$agent_id")
    if [[ $? -ne 0 ]]; then
        _orch_log error "Failed to create TMUX window for agent '$agent_id'"
        return 1
    fi

    # Determine capabilities (override or inherit from team)
    local capabilities="$capabilities_override"
    if [[ -z "$capabilities" ]]; then
        # Extract capabilities from team JSON
        local team_json="${_ORCH_TEAMS[$team_id]}"
        # Simple extraction - between "capabilities": and next comma/brace
        if [[ "$team_json" =~ \"capabilities\":(\[[^\]]*\]) ]]; then
            capabilities="${BASH_REMATCH[1]}"
        else
            capabilities="[]"
        fi
    else
        # Build JSON array from CSV
        local IFS=','
        local caps_array=()
        read -ra caps_array <<< "$capabilities"
        local cap
        local first=1
        capabilities="["
        for cap in "${caps_array[@]}"; do
            cap="${cap#"${cap%%[![:space:]]*}"}"
            cap="${cap%"${cap##*[![:space:]]}"}"
            if [[ $first -eq 1 ]]; then
                first=0
            else
                capabilities+=","
            fi
            capabilities+="\"$(_orch_json_escape "$cap")\""
        done
        capabilities+="]"
    fi

    # Create agent metadata JSON
    local created_at
    created_at=$(_orch_iso_timestamp)
    local agent_json
    agent_json=$(printf '{"id":"%s","team_id":"%s","window_index":%s,"capabilities":%s,"status":"%s","created_at":"%s","last_heartbeat":"%s","task_count":0}' \
        "$agent_id" \
        "$team_id" \
        "$window_index" \
        "$capabilities" \
        "$ORCH_STATUS_INITIALIZING" \
        "$created_at" \
        "$created_at")

    # Store in memory
    _ORCH_AGENTS["$agent_id"]="$agent_json"

    # Persist to Redis/file
    local redis_key
    redis_key=$(_orch_key_agent_state "$agent_id")
    _orch_store "$redis_key" "$agent_json"

    # Publish spawn event
    local event_json
    event_json=$(printf '{"event":"agent_spawned","agent_id":"%s","team_id":"%s","window_index":%s,"timestamp":"%s"}' \
        "$agent_id" \
        "$team_id" \
        "$window_index" \
        "$created_at")
    _orch_publish "$(_orch_channel_team "$team_id")" "$event_json"
    _orch_publish "$(_orch_channel_control)" "$event_json"

    _orch_log info "Spawned agent '$agent_id' in team '$team_id' (window: $window_index)"
    printf '%s' "$agent_id"
    return 0
}

##
# @brief Terminate an agent
# @param $1 Agent ID
# @param $2 Optional "force" flag to skip graceful shutdown
# @return 0 on success, 1 on failure
#
# Kills the agent's TMUX window, removes from _ORCH_AGENTS,
# and publishes terminate event.
##
orch_agent_terminate() {
    local agent_id="$1"
    local force="${2:-}"

    if [[ -z "$agent_id" ]]; then
        _orch_log error "Agent ID is required"
        return 1
    fi

    local agent_json="${_ORCH_AGENTS[$agent_id]:-}"
    if [[ -z "$agent_json" ]]; then
        _orch_log warn "Agent '$agent_id' not found (may already be terminated)"
        return 0
    fi

    # Extract team_id from agent JSON
    local team_id=""
    if [[ "$agent_json" =~ \"team_id\":\"([^\"]+)\" ]]; then
        team_id="${BASH_REMATCH[1]}"
    fi

    _orch_log info "Terminating agent '$agent_id'${force:+ (forced)}..."

    # Kill TMUX window
    _orch_tmux_kill_window "$agent_id"

    # Remove from memory
    unset "_ORCH_AGENTS[$agent_id]"

    # Remove from Redis/file
    local redis_key
    redis_key=$(_orch_key_agent_state "$agent_id")
    _orch_del "$redis_key"

    # Publish terminate event
    local event_json
    event_json=$(printf '{"event":"agent_terminated","agent_id":"%s","team_id":"%s","forced":%s,"timestamp":"%s"}' \
        "$agent_id" \
        "$team_id" \
        "$( [[ "$force" == "force" ]] && printf 'true' || printf 'false' )" \
        "$(_orch_iso_timestamp)")

    if [[ -n "$team_id" ]]; then
        _orch_publish "$(_orch_channel_team "$team_id")" "$event_json"
    fi
    _orch_publish "$(_orch_channel_control)" "$event_json"

    _orch_log info "Terminated agent '$agent_id'"
    return 0
}

##
# @brief Get agent information as JSON
# @param $1 Agent ID
# @return JSON object to stdout, 1 if not found
##
orch_agent_info() {
    local agent_id="$1"

    if [[ -z "$agent_id" ]]; then
        _orch_log error "Agent ID is required"
        return 1
    fi

    local agent_json="${_ORCH_AGENTS[$agent_id]:-}"
    if [[ -z "$agent_json" ]]; then
        _orch_log error "Agent '$agent_id' not found"
        return 1
    fi

    printf '%s' "$agent_json"
    return 0
}

##
# @brief List agents, optionally filtered by team
# @param $1 Optional team ID to filter by
# @return JSON array to stdout
##
orch_agent_list() {
    local filter_team_id="${1:-}"
    local first=1
    local agent_id

    printf '['
    for agent_id in "${!_ORCH_AGENTS[@]}"; do
        local agent_json="${_ORCH_AGENTS[$agent_id]}"

        # Filter by team if specified
        if [[ -n "$filter_team_id" ]]; then
            if [[ "$agent_json" != *"\"team_id\":\"$filter_team_id\""* ]]; then
                continue
            fi
        fi

        if [[ $first -eq 1 ]]; then
            first=0
        else
            printf ','
        fi
        printf '%s' "$agent_json"
    done
    printf ']'
    return 0
}

# =============================================================================
# SUB-AGENT DELEGATION
# =============================================================================

##
# @brief Count sub-agents for a given parent agent
# @param $1 Parent agent ID
# @return Count to stdout
##
_orch_agent_subcount() {
    local agent_id="$1"

    if [[ -z "$agent_id" ]]; then
        printf '0'
        return 0
    fi

    local subagent_list="${_ORCH_SUBAGENTS[$agent_id]:-}"
    if [[ -z "$subagent_list" ]]; then
        printf '0'
        return 0
    fi

    # Count space-separated subagent IDs
    local count=0
    local id
    for id in $subagent_list; do
        [[ -n "$id" ]] && ((count++))
    done
    printf '%d' "$count"
}

##
# @brief Spawn a sub-agent under a parent agent
# @param $1 Parent agent ID
# @param $2 Task description for the sub-agent
# @return Sub-agent ID to stdout, 1 on failure
#
# Creates a sub-agent with ID format: {parent_id}-sub-{count}
# Validates parent exists and respects ORCH_MAX_SUBAGENTS_PER_AGENT limit.
##
orch_subagent_spawn() {
    local parent_id="$1"
    local task_description="${2:-}"

    # Validate parent agent exists
    if [[ -z "$parent_id" ]]; then
        _orch_log error "Parent agent ID required"
        return 1
    fi

    if [[ -z "${_ORCH_AGENTS[$parent_id]:-}" ]]; then
        _orch_log error "Parent agent '$parent_id' does not exist"
        return 1
    fi

    # Check sub-agent limit
    local current_count
    current_count=$(_orch_agent_subcount "$parent_id")
    if [[ $current_count -ge $ORCH_MAX_SUBAGENTS_PER_AGENT ]]; then
        _orch_log error "Maximum sub-agents ($ORCH_MAX_SUBAGENTS_PER_AGENT) reached for agent '$parent_id'"
        return 1
    fi

    # Generate sub-agent ID
    local subagent_num=$((current_count + 1))
    local subagent_id="${parent_id}-sub-${subagent_num}"

    # Ensure unique ID (handle race conditions)
    while [[ -n "${_ORCH_AGENTS[$subagent_id]:-}" ]]; do
        ((subagent_num++))
        subagent_id="${parent_id}-sub-${subagent_num}"
    done

    # Store sub-agent in _ORCH_AGENTS with parent reference
    local now
    now=$(_orch_epoch)
    local escaped_task
    escaped_task=$(_orch_json_escape "$task_description")

    local subagent_json
    subagent_json=$(printf '{"id":"%s","parent":"%s","task":"%s","status":"%s","created_at":%d,"updated_at":%d}' \
        "$subagent_id" \
        "$parent_id" \
        "$escaped_task" \
        "$ORCH_STATUS_PENDING" \
        "$now" \
        "$now")

    _ORCH_AGENTS["$subagent_id"]="$subagent_json"

    # Update parent's sub-agent list
    local existing_list="${_ORCH_SUBAGENTS[$parent_id]:-}"
    if [[ -z "$existing_list" ]]; then
        _ORCH_SUBAGENTS["$parent_id"]="$subagent_id"
    else
        _ORCH_SUBAGENTS["$parent_id"]="$existing_list $subagent_id"
    fi

    # Persist to Redis/file storage
    local key
    key=$(_orch_key_agent_state "$subagent_id")
    _orch_store "$key" "$subagent_json"

    # Publish spawn event
    local event_json
    event_json=$(printf '{"type":"subagent_spawn","parent":"%s","subagent":"%s","task":"%s","timestamp":%d}' \
        "$parent_id" \
        "$subagent_id" \
        "$escaped_task" \
        "$now")
    _orch_publish "$(_orch_channel_agent "$parent_id")" "$event_json"

    _orch_log info "Spawned sub-agent '$subagent_id' under parent '$parent_id'"
    printf '%s' "$subagent_id"
    return 0
}

##
# @brief Terminate a sub-agent
# @param $1 Sub-agent ID
# @return 0 on success, 1 on failure
#
# Removes sub-agent from _ORCH_AGENTS and parent's sub-agent list.
##
orch_subagent_terminate() {
    local subagent_id="$1"

    if [[ -z "$subagent_id" ]]; then
        _orch_log error "Sub-agent ID required"
        return 1
    fi

    # Get sub-agent metadata
    local subagent_json="${_ORCH_AGENTS[$subagent_id]:-}"
    if [[ -z "$subagent_json" ]]; then
        _orch_log warn "Sub-agent '$subagent_id' does not exist (may already be terminated)"
        return 0
    fi

    # Extract parent ID from subagent_id pattern (parent-sub-N)
    local parent_id=""
    if [[ "$subagent_id" =~ ^(.+)-sub-[0-9]+$ ]]; then
        parent_id="${BASH_REMATCH[1]}"
    fi

    # Remove from parent's sub-agent list
    if [[ -n "$parent_id" && -n "${_ORCH_SUBAGENTS[$parent_id]:-}" ]]; then
        local new_list=""
        local id
        for id in ${_ORCH_SUBAGENTS[$parent_id]}; do
            if [[ "$id" != "$subagent_id" ]]; then
                if [[ -z "$new_list" ]]; then
                    new_list="$id"
                else
                    new_list="$new_list $id"
                fi
            fi
        done
        _ORCH_SUBAGENTS["$parent_id"]="$new_list"
    fi

    # Remove from agents registry
    unset "_ORCH_AGENTS[$subagent_id]"

    # Remove from Redis/file storage
    local key
    key=$(_orch_key_agent_state "$subagent_id")
    _orch_del "$key"

    # Publish termination event
    local now
    now=$(_orch_epoch)
    local event_json
    event_json=$(printf '{"type":"subagent_terminate","subagent":"%s","parent":"%s","timestamp":%d}' \
        "$subagent_id" \
        "$parent_id" \
        "$now")

    if [[ -n "$parent_id" ]]; then
        _orch_publish "$(_orch_channel_agent "$parent_id")" "$event_json"
    fi

    _orch_log info "Terminated sub-agent '$subagent_id'"
    return 0
}

##
# @brief List all sub-agents for a parent agent
# @param $1 Parent agent ID
# @return JSON array of sub-agent objects to stdout
##
orch_subagent_list() {
    local parent_id="$1"

    if [[ -z "$parent_id" ]]; then
        _orch_log error "Parent agent ID required"
        printf '[]'
        return 1
    fi

    local subagent_list="${_ORCH_SUBAGENTS[$parent_id]:-}"
    if [[ -z "$subagent_list" ]]; then
        printf '[]'
        return 0
    fi

    # Build JSON array of sub-agent objects
    local json_array="["
    local first=1
    local id
    for id in $subagent_list; do
        if [[ -n "$id" && -n "${_ORCH_AGENTS[$id]:-}" ]]; then
            if [[ $first -eq 1 ]]; then
                first=0
            else
                json_array="${json_array},"
            fi
            json_array="${json_array}${_ORCH_AGENTS[$id]}"
        fi
    done
    json_array="${json_array}]"

    printf '%s' "$json_array"
    return 0
}

# =============================================================================
# TASK DISTRIBUTION
# =============================================================================

##
# @brief Find an available agent in a team with lowest workload
# @param $1 Team ID
# @return Agent ID to stdout, empty if none available
#
# Selects agent with status=READY and lowest sub-agent count.
# Prefers agents with no sub-agents over those with some.
##
_orch_find_available_agent() {
    local team_id="$1"

    if [[ -z "$team_id" ]]; then
        return 1
    fi

    local best_agent=""
    local best_subcount=999999
    local agent_id agent_json agent_status agent_team

    for agent_id in "${!_ORCH_AGENTS[@]}"; do
        agent_json="${_ORCH_AGENTS[$agent_id]}"

        # Skip sub-agents (they have parent field)
        if [[ "$agent_json" == *'"parent":'* ]]; then
            continue
        fi

        # Extract team from JSON (check both team and team_id patterns)
        if [[ "$agent_json" =~ \"team_id\":\"([^\"]+)\" ]]; then
            agent_team="${BASH_REMATCH[1]}"
        elif [[ "$agent_json" =~ \"team\":\"([^\"]+)\" ]]; then
            agent_team="${BASH_REMATCH[1]}"
        else
            continue
        fi

        # Must match requested team
        if [[ "$agent_team" != "$team_id" ]]; then
            continue
        fi

        # Extract status from JSON
        if [[ "$agent_json" =~ \"status\":\"([^\"]+)\" ]]; then
            agent_status="${BASH_REMATCH[1]}"
        else
            continue
        fi

        # Must be READY status
        if [[ "$agent_status" != "$ORCH_STATUS_READY" ]]; then
            continue
        fi

        # Count sub-agents for this agent
        local subcount
        subcount=$(_orch_agent_subcount "$agent_id")

        # Select agent with lowest sub-agent count
        if [[ $subcount -lt $best_subcount ]]; then
            best_subcount=$subcount
            best_agent="$agent_id"
        fi
    done

    printf '%s' "$best_agent"
}

##
# @brief Assign a task to an available agent in a team
# @param $1 Team ID
# @param $2 Task payload (JSON)
# @param $3 Optional priority (1-10, default 5)
# @return Task ID to stdout, 1 on failure
#
# Finds least-loaded agent in team and assigns task.
# If no agent available, queues task for team.
##
orch_task_assign() {
    local team_id="$1"
    local payload_json="${2:-{}}"
    local priority="${3:-5}"

    if [[ -z "$team_id" ]]; then
        _orch_log error "Team ID required for task assignment"
        return 1
    fi

    # Validate priority range
    if [[ ! "$priority" =~ ^[0-9]+$ ]] || [[ $priority -lt 1 ]] || [[ $priority -gt 10 ]]; then
        _orch_log warn "Invalid priority '$priority', using default 5"
        priority=5
    fi

    # Generate task ID
    local task_id
    task_id="task-$(_orch_gen_id)"

    local now
    now=$(_orch_epoch)

    # Find available agent
    local agent_id
    agent_id=$(_orch_find_available_agent "$team_id")

    local task_status assigned_to
    if [[ -n "$agent_id" ]]; then
        task_status="$ORCH_TASK_ASSIGNED"
        assigned_to="$agent_id"

        # Update agent status to BUSY
        local agent_json="${_ORCH_AGENTS[$agent_id]}"
        agent_json="${agent_json/\"status\":\"$ORCH_STATUS_READY\"/\"status\":\"$ORCH_STATUS_BUSY\"}"
        agent_json="${agent_json/\"updated_at\":[0-9]*/\"updated_at\":$now}"
        _ORCH_AGENTS["$agent_id"]="$agent_json"

        # Persist agent state
        local agent_key
        agent_key=$(_orch_key_agent_state "$agent_id")
        _orch_store "$agent_key" "$agent_json"
    else
        task_status="$ORCH_TASK_QUEUED"
        assigned_to=""
        _orch_log info "No available agents in team '$team_id', queuing task"
    fi

    # Escape payload for JSON embedding
    local escaped_payload
    escaped_payload=$(_orch_json_escape "$payload_json")

    # Create task JSON
    local task_json
    task_json=$(printf '{"id":"%s","team":"%s","agent":"%s","status":"%s","priority":%d,"payload":"%s","created_at":%d,"updated_at":%d}' \
        "$task_id" \
        "$team_id" \
        "$assigned_to" \
        "$task_status" \
        "$priority" \
        "$escaped_payload" \
        "$now" \
        "$now")

    # Store in memory
    _ORCH_TASKS["$task_id"]="$task_json"

    # Persist to Redis/file
    local task_key="mainframe:orch:task:$task_id"
    _orch_store "$task_key" "$task_json"

    # If queued, push to team queue
    if [[ "$task_status" == "$ORCH_TASK_QUEUED" ]]; then
        local queue_key
        queue_key=$(_orch_key_task_queue "$team_id")
        _orch_lpush "$queue_key" "$task_json"
    fi

    # Publish task assignment event
    local event_json
    event_json=$(printf '{"type":"task_assigned","task_id":"%s","team":"%s","agent":"%s","status":"%s","priority":%d,"timestamp":%d}' \
        "$task_id" \
        "$team_id" \
        "$assigned_to" \
        "$task_status" \
        "$priority" \
        "$now")
    _orch_publish "$(_orch_channel_tasks "$team_id")" "$event_json"

    _orch_log info "Task '$task_id' ${task_status} to ${assigned_to:-queue} (priority: $priority)"
    printf '%s' "$task_id"
    return 0
}

##
# @brief Mark a task as completed with result
# @param $1 Task ID
# @param $2 Result JSON (optional)
# @return 0 on success, 1 on failure
#
# Updates task status to COMPLETED and frees the assigned agent.
##
orch_task_complete() {
    local task_id="$1"
    local result_json="${2:-{}}"

    if [[ -z "$task_id" ]]; then
        _orch_log error "Task ID required"
        return 1
    fi

    # Get existing task
    local task_json="${_ORCH_TASKS[$task_id]:-}"
    if [[ -z "$task_json" ]]; then
        _orch_log error "Task '$task_id' not found"
        return 1
    fi

    local now
    now=$(_orch_epoch)

    # Extract assigned agent
    local agent_id=""
    if [[ "$task_json" =~ \"agent\":\"([^\"]+)\" ]]; then
        agent_id="${BASH_REMATCH[1]}"
    fi

    # Extract team
    local team_id=""
    if [[ "$task_json" =~ \"team\":\"([^\"]+)\" ]]; then
        team_id="${BASH_REMATCH[1]}"
    fi

    # Update task status
    task_json="${task_json/\"status\":\"$ORCH_TASK_ASSIGNED\"/\"status\":\"$ORCH_TASK_COMPLETED\"}"
    task_json="${task_json/\"status\":\"$ORCH_TASK_RUNNING\"/\"status\":\"$ORCH_TASK_COMPLETED\"}"

    # Add result and completion timestamp
    # Remove trailing } and append result
    task_json="${task_json%\}}"
    local escaped_result
    escaped_result=$(_orch_json_escape "$result_json")
    task_json="${task_json},\"result\":\"${escaped_result}\",\"completed_at\":${now}}"

    # Update in memory and storage
    _ORCH_TASKS["$task_id"]="$task_json"
    local task_key="mainframe:orch:task:$task_id"
    _orch_store "$task_key" "$task_json"

    # Free the agent (set status back to READY)
    if [[ -n "$agent_id" && -n "${_ORCH_AGENTS[$agent_id]:-}" ]]; then
        local agent_json="${_ORCH_AGENTS[$agent_id]}"
        agent_json="${agent_json/\"status\":\"$ORCH_STATUS_BUSY\"/\"status\":\"$ORCH_STATUS_READY\"}"
        agent_json="${agent_json/\"updated_at\":[0-9]*/\"updated_at\":$now}"
        _ORCH_AGENTS["$agent_id"]="$agent_json"

        local agent_key
        agent_key=$(_orch_key_agent_state "$agent_id")
        _orch_store "$agent_key" "$agent_json"
    fi

    # Publish completion event
    local event_json
    event_json=$(printf '{"type":"task_completed","task_id":"%s","team":"%s","agent":"%s","timestamp":%d}' \
        "$task_id" \
        "$team_id" \
        "$agent_id" \
        "$now")
    _orch_publish "$(_orch_channel_tasks "$team_id")" "$event_json"

    _orch_log info "Task '$task_id' completed by agent '$agent_id'"
    return 0
}

##
# @brief Mark a task as failed with error message
# @param $1 Task ID
# @param $2 Error message
# @return 0 on success, 1 on failure
#
# Updates task status to FAILED and frees the assigned agent.
##
orch_task_failed() {
    local task_id="$1"
    local error_message="${2:-Unknown error}"

    if [[ -z "$task_id" ]]; then
        _orch_log error "Task ID required"
        return 1
    fi

    # Get existing task
    local task_json="${_ORCH_TASKS[$task_id]:-}"
    if [[ -z "$task_json" ]]; then
        _orch_log error "Task '$task_id' not found"
        return 1
    fi

    local now
    now=$(_orch_epoch)

    # Extract assigned agent
    local agent_id=""
    if [[ "$task_json" =~ \"agent\":\"([^\"]+)\" ]]; then
        agent_id="${BASH_REMATCH[1]}"
    fi

    # Extract team
    local team_id=""
    if [[ "$task_json" =~ \"team\":\"([^\"]+)\" ]]; then
        team_id="${BASH_REMATCH[1]}"
    fi

    # Update task status to FAILED
    task_json="${task_json/\"status\":\"$ORCH_TASK_ASSIGNED\"/\"status\":\"$ORCH_TASK_FAILED\"}"
    task_json="${task_json/\"status\":\"$ORCH_TASK_RUNNING\"/\"status\":\"$ORCH_TASK_FAILED\"}"
    task_json="${task_json/\"status\":\"$ORCH_TASK_QUEUED\"/\"status\":\"$ORCH_TASK_FAILED\"}"

    # Add error message and failure timestamp
    task_json="${task_json%\}}"
    local escaped_error
    escaped_error=$(_orch_json_escape "$error_message")
    task_json="${task_json},\"error\":\"${escaped_error}\",\"failed_at\":${now}}"

    # Update in memory and storage
    _ORCH_TASKS["$task_id"]="$task_json"
    local task_key="mainframe:orch:task:$task_id"
    _orch_store "$task_key" "$task_json"

    # Free the agent (set status back to READY)
    if [[ -n "$agent_id" && -n "${_ORCH_AGENTS[$agent_id]:-}" ]]; then
        local agent_json="${_ORCH_AGENTS[$agent_id]}"
        agent_json="${agent_json/\"status\":\"$ORCH_STATUS_BUSY\"/\"status\":\"$ORCH_STATUS_READY\"}"
        agent_json="${agent_json/\"updated_at\":[0-9]*/\"updated_at\":$now}"
        _ORCH_AGENTS["$agent_id"]="$agent_json"

        local agent_key
        agent_key=$(_orch_key_agent_state "$agent_id")
        _orch_store "$agent_key" "$agent_json"
    fi

    # Publish failure event
    local event_json
    event_json=$(printf '{"type":"task_failed","task_id":"%s","team":"%s","agent":"%s","error":"%s","timestamp":%d}' \
        "$task_id" \
        "$team_id" \
        "$agent_id" \
        "$escaped_error" \
        "$now")
    _orch_publish "$(_orch_channel_tasks "$team_id")" "$event_json"

    _orch_log warn "Task '$task_id' failed: $error_message"
    return 0
}

##
# @brief Get task information by ID
# @param $1 Task ID
# @return JSON task object to stdout, 1 if not found
##
orch_task_info() {
    local task_id="$1"

    if [[ -z "$task_id" ]]; then
        _orch_log error "Task ID required"
        return 1
    fi

    # Check in-memory first
    local task_json="${_ORCH_TASKS[$task_id]:-}"
    if [[ -n "$task_json" ]]; then
        printf '%s' "$task_json"
        return 0
    fi

    # Try Redis/file storage
    local task_key="mainframe:orch:task:$task_id"
    task_json=$(_orch_get "$task_key")
    if [[ -n "$task_json" ]]; then
        # Cache in memory
        _ORCH_TASKS["$task_id"]="$task_json"
        printf '%s' "$task_json"
        return 0
    fi

    _orch_log error "Task '$task_id' not found"
    return 1
}

# =============================================================================
# HEALTH MONITORING
# =============================================================================

##
# @brief Update heartbeat timestamp for an agent
# @param $1 Agent ID
# @return 0 on success
#
# Stores heartbeat in Redis with TTL of 2x ORCH_AGENT_TIMEOUT.
# Also updates the in-memory agent state with last_heartbeat.
##
orch_agent_heartbeat() {
    local agent_id="$1"

    if [[ -z "$agent_id" ]]; then
        _orch_log error "Agent ID required for heartbeat"
        return 1
    fi

    local timestamp
    timestamp=$(_orch_epoch)
    local ttl=$(( ORCH_AGENT_TIMEOUT * 2 ))

    # Store heartbeat in Redis with TTL
    local heartbeat_key="mainframe:orch:heartbeat:${agent_id}"
    _orch_store "$heartbeat_key" "$timestamp" "$ttl"

    # Update in-memory state if agent exists
    if [[ -n "${_ORCH_AGENTS[$agent_id]:-}" ]]; then
        local agent_json="${_ORCH_AGENTS[$agent_id]}"
        # Update last_heartbeat field in JSON (simple replacement)
        if [[ "$agent_json" == *'"last_heartbeat":'* ]]; then
            agent_json=$(printf '%s' "$agent_json" | sed -E "s/\"last_heartbeat\":[0-9]+/\"last_heartbeat\":${timestamp}/")
        else
            # Insert before closing brace
            agent_json="${agent_json%\}},\"last_heartbeat\":${timestamp}}"
        fi
        _ORCH_AGENTS["$agent_id"]="$agent_json"
    fi

    # Publish heartbeat to channel
    local msg
    msg=$(printf '{"type":"heartbeat","agent_id":"%s","timestamp":%d}' \
        "$(_orch_json_escape "$agent_id")" "$timestamp")
    _orch_publish "$(_orch_channel_heartbeat)" "$msg"

    _orch_log debug "Heartbeat updated for agent '$agent_id'"
    return 0
}

##
# @brief Check if an agent's heartbeat is recent (healthy)
# @param $1 Agent ID
# @return 0 if healthy, 1 if stale or missing
#
# Compares last heartbeat against ORCH_AGENT_TIMEOUT threshold.
##
orch_agent_healthy() {
    local agent_id="$1"

    if [[ -z "$agent_id" ]]; then
        _orch_log error "Agent ID required for health check"
        return 1
    fi

    local heartbeat_key="mainframe:orch:heartbeat:${agent_id}"
    local last_heartbeat
    last_heartbeat=$(_orch_get "$heartbeat_key") || {
        _orch_log debug "No heartbeat found for agent '$agent_id'"
        return 1
    }

    local now
    now=$(_orch_epoch)
    local age=$(( now - last_heartbeat ))

    if [[ $age -le $ORCH_AGENT_TIMEOUT ]]; then
        _orch_log debug "Agent '$agent_id' healthy (heartbeat age: ${age}s)"
        return 0
    else
        _orch_log warn "Agent '$agent_id' stale (heartbeat age: ${age}s, timeout: ${ORCH_AGENT_TIMEOUT}s)"
        return 1
    fi
}

##
# @brief Prune agents with stale heartbeats
# @param $1 Optional max age in seconds (default: ORCH_AGENT_TIMEOUT)
# @return Count of pruned agents to stdout
#
# Iterates through all registered agents, terminates those with stale heartbeats.
##
orch_prune_stale() {
    local max_age="${1:-$ORCH_AGENT_TIMEOUT}"
    local pruned=0
    local agent_id

    for agent_id in "${!_ORCH_AGENTS[@]}"; do
        if ! orch_agent_healthy "$agent_id"; then
            _orch_log info "Pruning stale agent '$agent_id'"
            _orch_tmux_kill_window "$agent_id"

            # Clean up Redis state
            _orch_del "$(_orch_key_agent_state "$agent_id")"
            _orch_del "mainframe:orch:heartbeat:${agent_id}"
            _orch_del "mainframe:orch:inbox:${agent_id}"

            # Remove from in-memory state
            unset "_ORCH_AGENTS[$agent_id]"
            unset "_ORCH_SUBAGENTS[$agent_id]"

            ((pruned++))
        fi
    done

    _orch_log info "Pruned $pruned stale agents"
    printf '%d' "$pruned"
}

##
# @brief Recover a failed agent by re-queuing its task and spawning replacement
# @param $1 Agent ID of the failed agent
# @return 0 on success, 1 on failure
#
# Gets the current task from the failed agent, terminates it,
# re-queues the task for the team, and spawns a replacement agent.
##
orch_agent_recover() {
    local agent_id="$1"

    if [[ -z "$agent_id" ]]; then
        _orch_log error "Agent ID required for recovery"
        return 1
    fi

    # Get agent metadata
    local agent_json="${_ORCH_AGENTS[$agent_id]:-}"
    if [[ -z "$agent_json" ]]; then
        _orch_log error "Agent '$agent_id' not found in registry"
        return 1
    fi

    # Extract team_id and current_task from agent JSON
    local team_id
    local current_task
    team_id=$(printf '%s' "$agent_json" | grep -oP '"team_id"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
    current_task=$(printf '%s' "$agent_json" | grep -oP '"current_task"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")

    # Terminate the failed agent
    _orch_log info "Terminating failed agent '$agent_id' for recovery"
    _orch_tmux_kill_window "$agent_id"
    _orch_del "$(_orch_key_agent_state "$agent_id")"
    _orch_del "mainframe:orch:heartbeat:${agent_id}"
    unset "_ORCH_AGENTS[$agent_id]"

    # Re-queue the task if one was assigned
    if [[ -n "$current_task" && -n "${_ORCH_TASKS[$current_task]:-}" ]]; then
        local task_json="${_ORCH_TASKS[$current_task]}"
        _orch_log info "Re-queuing task '$current_task' for team '${team_id:-default}'"

        # Update task status to queued
        task_json=$(printf '%s' "$task_json" | sed -E 's/"status"\s*:\s*"[^"]+/"status":"queued/')
        _ORCH_TASKS["$current_task"]="$task_json"

        # Push back to team queue
        local queue_key
        queue_key=$(_orch_key_task_queue "${team_id:-$ORCH_TEAM_DEFAULT}")
        _orch_lpush "$queue_key" "$task_json"
    fi

    # Spawn replacement agent
    local new_agent_id
    new_agent_id="agent-$(_orch_gen_id)"
    _orch_log info "Spawning replacement agent '$new_agent_id' for team '${team_id:-default}'"

    # Create new agent metadata
    local new_agent_json
    new_agent_json=$(printf '{"agent_id":"%s","team_id":"%s","status":"%s","created_at":%d,"last_heartbeat":%d}' \
        "$(_orch_json_escape "$new_agent_id")" \
        "$(_orch_json_escape "${team_id:-$ORCH_TEAM_DEFAULT}")" \
        "$ORCH_STATUS_INITIALIZING" \
        "$(_orch_epoch)" \
        "$(_orch_epoch)")
    _ORCH_AGENTS["$new_agent_id"]="$new_agent_json"

    # Create TMUX window for replacement
    if _orch_tmux_create_window "$new_agent_id" >/dev/null; then
        _orch_log info "Recovery complete: '$agent_id' replaced by '$new_agent_id'"
        printf '%s' "$new_agent_id"
        return 0
    else
        _orch_log error "Failed to create window for replacement agent"
        return 1
    fi
}

# =============================================================================
# MESSAGE PROTOCOL (USOP v4)
# =============================================================================

##
# @brief Create a USOP v4 message envelope
# @param $1 Message type (task, result, status, control, broadcast, discovery)
# @param $2 Sender ID (agent_id or team_id)
# @param $3 Target ID (agent_id, team_id, or "broadcast")
# @param $4 Payload JSON
# @return JSON message envelope to stdout
#
# USOP v4 envelope format:
# {
#   "version": "4.0",
#   "message_id": "<unique_id>",
#   "type": "<message_type>",
#   "from": "<sender_id>",
#   "to": "<target_id>",
#   "timestamp": <epoch>,
#   "payload": <json_object>
# }
##
orch_message_create() {
    local msg_type="$1"
    local from_id="$2"
    local to_id="$3"
    local payload="${4:-{}}"

    if [[ -z "$msg_type" || -z "$from_id" || -z "$to_id" ]]; then
        _orch_log error "Message creation requires type, from, and to parameters"
        return 1
    fi

    local message_id
    message_id="msg-$(_orch_gen_id)"
    local timestamp
    timestamp=$(_orch_epoch)

    # Build USOP v4 envelope
    printf '{"version":"4.0","message_id":"%s","type":"%s","from":"%s","to":"%s","timestamp":%d,"payload":%s}' \
        "$(_orch_json_escape "$message_id")" \
        "$(_orch_json_escape "$msg_type")" \
        "$(_orch_json_escape "$from_id")" \
        "$(_orch_json_escape "$to_id")" \
        "$timestamp" \
        "$payload"
}

##
# @brief Send a message to a target (agent, team, or broadcast)
# @param $1 Target ID (agent_id, team_id, or "broadcast")
# @param $2 Message JSON (USOP v4 envelope)
# @return 0 on success, 1 on failure
#
# Determines the appropriate channel based on target type:
# - Agent ID (starts with "agent-"): agent-specific channel
# - Team ID: team broadcast channel
# - "broadcast": control channel for all
# Also pushes to inbox list for persistent delivery.
##
orch_message_send() {
    local target_id="$1"
    local message_json="$2"

    if [[ -z "$target_id" || -z "$message_json" ]]; then
        _orch_log error "Message send requires target_id and message_json"
        return 1
    fi

    local channel

    # Determine channel based on target type
    if [[ "$target_id" == "broadcast" ]]; then
        channel=$(_orch_channel_control)
    elif [[ "$target_id" == agent-* ]]; then
        channel=$(_orch_channel_agent "$target_id")
        # Also push to agent's inbox for persistent delivery
        _orch_lpush "mainframe:orch:inbox:${target_id}" "$message_json"
    elif [[ -n "${_ORCH_TEAMS[$target_id]:-}" ]]; then
        channel=$(_orch_channel_team "$target_id")
    else
        # Assume it's a team ID even if not registered
        channel=$(_orch_channel_team "$target_id")
    fi

    # Publish to channel
    if _orch_publish "$channel" "$message_json"; then
        _orch_log debug "Message sent to '$target_id' via channel '$channel'"
        return 0
    else
        _orch_log error "Failed to send message to '$target_id'"
        return 1
    fi
}

##
# @brief Broadcast a discovery to all agents
# @param $1 Agent ID making the discovery
# @param $2 Discovery text/content
# @return 0 on success, 1 on failure
#
# Creates a discovery message and publishes to the discoveries channel.
# Discovery messages are team-wide broadcasts for knowledge sharing.
##
orch_discovery_broadcast() {
    local agent_id="$1"
    local discovery_text="$2"

    if [[ -z "$agent_id" || -z "$discovery_text" ]]; then
        _orch_log error "Discovery broadcast requires agent_id and discovery_text"
        return 1
    fi

    # Build discovery payload
    local payload
    payload=$(printf '{"discovery":"%s","source":"%s"}' \
        "$(_orch_json_escape "$discovery_text")" \
        "$(_orch_json_escape "$agent_id")")

    # Create USOP v4 message
    local message
    message=$(orch_message_create "discovery" "$agent_id" "broadcast" "$payload")

    # Publish to discoveries channel
    local discoveries_channel="mainframe:orch:discoveries"
    if _orch_publish "$discoveries_channel" "$message"; then
        _orch_log info "Discovery broadcast from '$agent_id': ${discovery_text:0:50}..."
        return 0
    else
        _orch_log error "Failed to broadcast discovery from '$agent_id'"
        return 1
    fi
}

# =============================================================================
# SHUTDOWN & CLEANUP
# =============================================================================

##
# @brief Gracefully shutdown the orchestration system
# @return 0 on success
#
# Broadcasts shutdown message, terminates all agents,
# cleans up TMUX session, clears Redis keys, and resets state arrays.
##
orch_shutdown() {
    _orch_log info "Initiating orchestration shutdown..."

    # Broadcast shutdown message to all agents
    local shutdown_msg
    shutdown_msg=$(orch_message_create "control" "orchestrator" "broadcast" '{"action":"shutdown"}')
    _orch_publish "$(_orch_channel_control)" "$shutdown_msg"

    # Brief delay for agents to receive shutdown signal
    sleep 0.5 2>/dev/null || sleep 1

    # Terminate all registered agents
    local agent_id
    for agent_id in "${!_ORCH_AGENTS[@]}"; do
        _orch_log debug "Terminating agent '$agent_id'"
        _orch_tmux_kill_window "$agent_id"
        _orch_del "$(_orch_key_agent_state "$agent_id")"
        _orch_del "mainframe:orch:heartbeat:${agent_id}"
        _orch_del "mainframe:orch:inbox:${agent_id}"
    done

    # Cleanup TMUX session
    orch_tmux_cleanup

    # Clear Redis keys for teams and tasks
    local team_id
    for team_id in "${!_ORCH_TEAMS[@]}"; do
        _orch_del "$(_orch_key_team_state "$team_id")"
        _orch_del "$(_orch_key_task_queue "$team_id")"
    done

    local task_id
    for task_id in "${!_ORCH_TASKS[@]}"; do
        _orch_del "mainframe:orch:task:${task_id}"
    done

    # Clear state arrays
    _ORCH_TEAMS=()
    _ORCH_AGENTS=()
    _ORCH_SUBAGENTS=()
    _ORCH_TASKS=()
    _ORCH_WINDOWS=()

    _orch_log info "Orchestration shutdown complete"
    return 0
}

# =============================================================================
# INITIALIZATION
# =============================================================================

##
# @brief Initialize the orchestration subsystem
# @pre None
# @post State directories created, Redis availability checked
# @return 0 on success
#
# Creates necessary directories and checks Redis connectivity.
# Sets _ORCH_REDIS_AVAILABLE flag for runtime decisions.
##
orch_init() {
    # Create state directories
    mkdir -p "${ORCH_STATE_DIR}/channels" \
             "${ORCH_STATE_DIR}/keys" \
             "${ORCH_STATE_DIR}/lists" \
             "${ORCH_STATE_DIR}/hashes" \
             "${ORCH_STATE_DIR}/logs" 2>/dev/null

    # Check Redis availability
    if _orch_redis_check; then
        _ORCH_REDIS_AVAILABLE=1
        _orch_log info "Redis available at ${ORCH_REDIS_HOST}:${ORCH_REDIS_PORT}"
    else
        _ORCH_REDIS_AVAILABLE=0
        _orch_log warn "Redis unavailable, using file-based fallback"
    fi

    # Initialize global state arrays (reset to empty)
    _ORCH_TEAMS=()
    _ORCH_AGENTS=()
    _ORCH_SUBAGENTS=()
    _ORCH_TASKS=()
    # Initialize _ORCH_WINDOWS if not already set (preserve existing TMUX session)
    [[ ${#_ORCH_WINDOWS[@]} -eq 0 ]] 2>/dev/null || _ORCH_WINDOWS=()

    _orch_log info "Orchestration subsystem initialized (v${ORCH_VERSION})"
    return 0
}

##
# @brief Get orchestration system status as JSON
# @return JSON status object to stdout
##
orch_status() {
    local redis_status="unavailable"
    [[ ${_ORCH_REDIS_AVAILABLE:-0} -eq 1 ]] && redis_status="connected"

    # Safely get array counts (handle unset arrays)
    local team_count=0 agent_count=0 task_count=0 window_count=0
    [[ -v _ORCH_TEAMS ]] && team_count="${#_ORCH_TEAMS[@]}"
    [[ -v _ORCH_AGENTS ]] && agent_count="${#_ORCH_AGENTS[@]}"
    [[ -v _ORCH_TASKS ]] && task_count="${#_ORCH_TASKS[@]}"
    [[ -v _ORCH_WINDOWS ]] && window_count="${#_ORCH_WINDOWS[@]}"

    local tmux_status="inactive"
    if tmux has-session -t "$ORCH_TMUX_SESSION" 2>/dev/null; then
        tmux_status="active"
    fi

    printf '{"version":"%s","redis":"%s","tmux":"%s","teams":%d,"agents":%d,"tasks":%d,"windows":%d}' \
        "$ORCH_VERSION" \
        "$redis_status" \
        "$tmux_status" \
        "$team_count" \
        "$agent_count" \
        "$task_count" \
        "$window_count"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_ORCHESTRATE_EXPORTS=(
    # Constants (via readonly)
    ORCH_VERSION
    ORCH_MAX_TEAMS
    ORCH_MAX_AGENTS_PER_TEAM
    ORCH_MAX_SUBAGENTS_PER_AGENT
    ORCH_MAX_TASKS_PER_AGENT
    ORCH_MAX_WINDOWS_PER_SESSION
    # Team IDs
    ORCH_TEAM_DEFAULT
    ORCH_TEAM_RESEARCH
    ORCH_TEAM_IMPLEMENTATION
    ORCH_TEAM_REVIEW
    ORCH_TEAM_TESTING
    # Status values
    ORCH_STATUS_PENDING
    ORCH_STATUS_INITIALIZING
    ORCH_STATUS_READY
    ORCH_STATUS_BUSY
    ORCH_STATUS_BLOCKED
    ORCH_STATUS_COMPLETED
    ORCH_STATUS_FAILED
    ORCH_STATUS_TERMINATED
    # Task status
    ORCH_TASK_QUEUED
    ORCH_TASK_ASSIGNED
    ORCH_TASK_RUNNING
    ORCH_TASK_COMPLETED
    ORCH_TASK_FAILED
    ORCH_TASK_CANCELLED
    # Message types
    ORCH_MSG_HEARTBEAT
    ORCH_MSG_TASK
    ORCH_MSG_RESULT
    ORCH_MSG_STATUS
    ORCH_MSG_CONTROL
    ORCH_MSG_BROADCAST
    # Initialization & Status
    orch_init
    orch_status
    # TMUX Management
    orch_tmux_init
    orch_tmux_cleanup
    # Team Management
    orch_team_register
    orch_team_info
    orch_team_list
    orch_team_dissolve
    # Agent Lifecycle
    orch_agent_spawn
    orch_agent_terminate
    orch_agent_info
    orch_agent_list
    # Health Monitoring
    orch_agent_heartbeat
    orch_agent_healthy
    orch_prune_stale
    orch_agent_recover
    # Message Protocol (USOP v4)
    orch_message_create
    orch_message_send
    orch_discovery_broadcast
    # Shutdown
    orch_shutdown
    # Sub-Agent Delegation
    orch_subagent_spawn
    orch_subagent_terminate
    orch_subagent_list
    # Task Distribution
    orch_task_assign
    orch_task_complete
    orch_task_failed
    orch_task_info
    # Internal (exported for debugging/testing)
    _orch_channel_team
    _orch_channel_agent
    _orch_channel_control
    _orch_channel_tasks
    _orch_channel_heartbeat
    _orch_key_agent_state
    _orch_key_team_state
    _orch_key_task_queue
    _orch_publish
    _orch_store
    _orch_get
    _orch_lpush
    _orch_brpop
    _orch_hset
    _orch_hget
    _orch_del
    _orch_tmux_create_window
    _orch_tmux_exec
    _orch_tmux_kill_window
    _orch_team_agent_count
    _orch_agent_subcount
    _orch_find_available_agent
)

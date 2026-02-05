#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/agent_comm.sh - Agent Communication Protocol
# =============================================================================
# Description: Standardized inter-agent communication for AI collaboration
# Provides: identity, message passing, status reporting, task coordination,
#           shared state, and cleanup functionality
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_AGENT_COMM_LOADED:-}" ]] && return 0
readonly _MAINFRAME_AGENT_COMM_LOADED=1

# Ensure json library is loaded
if [[ -z "${_MAINFRAME_JSON_LOADED:-}" ]]; then
    source "${BASH_SOURCE%/*}/json.sh"
fi

# =============================================================================
# CONSTANTS
# =============================================================================

# Use user-specific directory to prevent world-writable /tmp security issues
readonly AGENT_BASE_DIR="${TMPDIR:-/tmp}/mainframe_agents_${UID:-$(id -u)}"
readonly AGENT_REGISTRY_DIR="$AGENT_BASE_DIR/registry"
readonly AGENT_TASKS_DIR="$AGENT_BASE_DIR/tasks"
readonly AGENT_STATE_DIR="$AGENT_BASE_DIR/shared_state"

# Ensure base directory exists with restrictive permissions
if [[ ! -d "$AGENT_BASE_DIR" ]]; then
    mkdir -p "$AGENT_BASE_DIR" && chmod 700 "$AGENT_BASE_DIR"
fi

# =============================================================================
# GLOBAL STATE
# =============================================================================

# Each agent gets a unique ID and can register capabilities
declare -g AGENT_ID="${AGENT_ID:-}"
declare -gA AGENT_CAPABILITIES=()

# =============================================================================
# 1. AGENT IDENTITY
# =============================================================================

# Initialize an agent with a unique ID and workspace
# Usage: agent_init [name]
# Returns: JSON with success, agent_id, workspace
agent_init() {
    local name="${1:-agent}"

    # Generate unique ID using timestamp and PID for uniqueness
    AGENT_ID="${name}_$(date +%s)_$$"

    # Create agent workspace directories
    local workspace="$AGENT_BASE_DIR/$AGENT_ID"
    mkdir -p "$workspace"/{inbox,outbox,status}

    # Ensure registry exists
    mkdir -p "$AGENT_REGISTRY_DIR"

    # Register with coordinator
    agent_register

    json_object \
        "success:bool=true" \
        "agent_id=$AGENT_ID" \
        "workspace=$workspace"
}

# Register agent in the global registry
# Usage: agent_register
agent_register() {
    mkdir -p "$AGENT_REGISTRY_DIR"

    # Build capabilities array
    local caps
    if [[ ${#AGENT_CAPABILITIES[@]} -gt 0 ]]; then
        caps=$(json_array "${!AGENT_CAPABILITIES[@]}")
    else
        caps="[]"
    fi

    json_object \
        "id=$AGENT_ID" \
        "pid:number=$$" \
        "started=$(date -Iseconds)" \
        "capabilities:raw=$caps" \
    > "$AGENT_REGISTRY_DIR/$AGENT_ID.json"
}

# Add a capability to this agent
# Usage: agent_add_capability "capability_name"
agent_add_capability() {
    local cap="$1"
    AGENT_CAPABILITIES["$cap"]=1
    agent_register  # Update registration
}

# Remove a capability from this agent
# Usage: agent_remove_capability "capability_name"
agent_remove_capability() {
    local cap="$1"
    unset 'AGENT_CAPABILITIES[$cap]'
    agent_register  # Update registration
}

# Get agent info
# Usage: agent_info [agent_id]
agent_info() {
    local agent_id="${1:-$AGENT_ID}"
    local registry_file="$AGENT_REGISTRY_DIR/$agent_id.json"

    if [[ -f "$registry_file" ]]; then
        cat "$registry_file"
    else
        json_object \
            "success:bool=false" \
            "error=agent not found" \
            "agent_id=$agent_id"
        return 1
    fi
}

# =============================================================================
# 2. MESSAGE PASSING
# =============================================================================

# Send message to another agent
# Usage: agent_send <to_agent> <msg_type> <payload>
# Returns: JSON with success and message_id
agent_send() {
    local to_agent="$1"
    local msg_type="$2"
    local payload="$3"

    local inbox="$AGENT_BASE_DIR/$to_agent/inbox"
    if [[ ! -d "$inbox" ]]; then
        json_object \
            "success:bool=false" \
            "error=agent not found: $to_agent"
        return 1
    fi

    # Generate unique message ID using nanoseconds if available
    local msg_id
    if date +%N &>/dev/null && [[ "$(date +%N)" != "N" ]]; then
        msg_id="msg_$(date +%s%N)"
    else
        msg_id="msg_$(date +%s)_${RANDOM}"
    fi

    local message
    message=$(json_object \
        "id=$msg_id" \
        "from=$AGENT_ID" \
        "to=$to_agent" \
        "type=$msg_type" \
        "payload=$payload" \
        "timestamp=$(date -Iseconds)")

    printf '%s\n' "$message" > "$inbox/$msg_id.json"

    json_object \
        "success:bool=true" \
        "message_id=$msg_id"
}

# Receive messages from inbox
# Usage: agent_receive [timeout_seconds]
# Returns: The oldest message as JSON, or empty with return code 1 on timeout
agent_receive() {
    local timeout="${1:-0}"
    local inbox="$AGENT_BASE_DIR/$AGENT_ID/inbox"

    [[ -d "$inbox" ]] || return 1

    local deadline=$((SECONDS + timeout))

    while true; do
        # Get oldest message file
        local msg_file
        msg_file=$(ls -1tr "$inbox"/*.json 2>/dev/null | head -1)

        if [[ -n "$msg_file" && -f "$msg_file" ]]; then
            local message
            message=$(<"$msg_file")
            rm -f "$msg_file"
            printf '%s' "$message"
            return 0
        fi

        # Check timeout conditions
        if (( timeout > 0 )); then
            (( SECONDS >= deadline )) && return 1
        else
            return 1
        fi

        sleep 0.1
    done
}

# Peek at messages without removing them
# Usage: agent_peek [count]
# Returns: JSON array of messages
agent_peek() {
    local count="${1:-10}"
    local inbox="$AGENT_BASE_DIR/$AGENT_ID/inbox"

    [[ -d "$inbox" ]] || { printf '[]'; return 0; }

    local -a messages=()
    local i=0
    local msg_file

    # Use glob instead of ls (shellcheck SC2045)
    for msg_file in "$inbox"/*.json; do
        (( i >= count )) && break
        [[ -f "$msg_file" ]] || continue
        messages+=("$(<"$msg_file")")
        ((i++))
    done

    if [[ ${#messages[@]} -eq 0 ]]; then
        printf '[]'
    else
        local first=true
        printf '['
        for msg in "${messages[@]}"; do
            $first || printf ','
            first=false
            printf '%s' "$msg"
        done
        printf ']'
    fi
}

# Broadcast message to all registered agents
# Usage: agent_broadcast <msg_type> <payload>
agent_broadcast() {
    local msg_type="$1"
    local payload="$2"

    local sent=0
    for agent_file in "$AGENT_REGISTRY_DIR"/*.json; do
        [[ -f "$agent_file" ]] || continue
        local agent_id pid
        agent_id=$(json_get "$(<"$agent_file")" "id")
        pid=$(json_get "$(<"$agent_file")" "pid")

        # Don't send to self and check if agent is still alive
        if [[ "$agent_id" != "$AGENT_ID" ]] && kill -0 "$pid" 2>/dev/null; then
            agent_send "$agent_id" "$msg_type" "$payload" >/dev/null && ((sent++))
        fi
    done

    json_object \
        "success:bool=true" \
        "sent:number=$sent"
}

# Send message and wait for reply
# Usage: agent_request <to_agent> <msg_type> <payload> [timeout]
# Returns: Reply message or error on timeout
agent_request() {
    local to_agent="$1"
    local msg_type="$2"
    local payload="$3"
    local timeout="${4:-30}"

    # Send the request
    local send_result
    send_result=$(agent_send "$to_agent" "$msg_type" "$payload")

    if [[ "$(json_get "$send_result" "success")" != "true" ]]; then
        printf '%s' "$send_result"
        return 1
    fi

    local msg_id
    msg_id=$(json_get "$send_result" "message_id")

    # Wait for reply
    local deadline=$((SECONDS + timeout))
    while (( SECONDS < deadline )); do
        local reply
        reply=$(agent_receive 1) || continue

        # Check if this is a reply to our message
        local reply_type reply_ref
        reply_type=$(json_get "$reply" "type")

        if [[ "$reply_type" == "reply" || "$reply_type" == "${msg_type}_reply" ]]; then
            printf '%s' "$reply"
            return 0
        fi

        # Re-queue message if not our reply (simple approach)
        # In production, you'd want a more sophisticated message routing
    done

    json_object \
        "success:bool=false" \
        "error=timeout waiting for reply" \
        "message_id=$msg_id"
    return 1
}

# =============================================================================
# 3. STATUS REPORTING
# =============================================================================

# Report agent status
# Usage: agent_status <status> [details]
agent_status() {
    local status="$1"
    local details="${2:-}"

    local status_file="$AGENT_BASE_DIR/$AGENT_ID/status/current.json"

    mkdir -p "$(dirname "$status_file")"

    json_object \
        "agent_id=$AGENT_ID" \
        "status=$status" \
        "details=$details" \
        "updated=$(date -Iseconds)" \
    > "$status_file"
}

# Get another agent's status
# Usage: agent_get_status <agent_id>
agent_get_status() {
    local agent_id="$1"
    local status_file="$AGENT_BASE_DIR/$agent_id/status/current.json"

    if [[ -f "$status_file" ]]; then
        cat "$status_file"
    else
        json_object \
            "agent_id=$agent_id" \
            "status=unknown"
    fi
}

# List all active agents
# Usage: agent_list
# Returns: JSON array of active agent IDs
agent_list() {
    local -a agents=()

    mkdir -p "$AGENT_REGISTRY_DIR"

    for agent_file in "$AGENT_REGISTRY_DIR"/*.json; do
        [[ -f "$agent_file" ]] || continue
        local agent_id pid
        agent_id=$(json_get "$(<"$agent_file")" "id")
        pid=$(json_get "$(<"$agent_file")" "pid")

        # Check if still alive
        if kill -0 "$pid" 2>/dev/null; then
            agents+=("$agent_id")
        else
            # Cleanup dead agent
            rm -f "$agent_file"
            # shellcheck disable=SC2115
            rm -rf "${AGENT_BASE_DIR:?}/${agent_id:?}"
        fi
    done

    json_array "${agents[@]}"
}

# Find agents by capability
# Usage: agent_find_by_capability <capability>
# Returns: JSON array of agent IDs with that capability
agent_find_by_capability() {
    local capability="$1"
    local -a matching=()

    for agent_file in "$AGENT_REGISTRY_DIR"/*.json; do
        [[ -f "$agent_file" ]] || continue
        local agent_data pid caps
        agent_data=$(<"$agent_file")
        pid=$(json_get "$agent_data" "pid")

        # Check if still alive
        kill -0 "$pid" 2>/dev/null || continue

        # Check capabilities (simple string match in JSON array)
        if [[ "$agent_data" == *"\"$capability\""* ]]; then
            matching+=("$(json_get "$agent_data" "id")")
        fi
    done

    json_array "${matching[@]}"
}

# =============================================================================
# 4. TASK COORDINATION
# =============================================================================

# Create a new task
# Usage: agent_create_task <task_id> <description> [priority]
# Returns: JSON with task info
agent_create_task() {
    local task_id="$1"
    local description="$2"
    local priority="${3:-normal}"
    local task_dir="$AGENT_TASKS_DIR/$task_id"

    mkdir -p "$task_dir"

    json_object \
        "task_id=$task_id" \
        "description=$description" \
        "priority=$priority" \
        "created_by=$AGENT_ID" \
        "created_at=$(date -Iseconds)" \
        "status=pending" \
    > "$task_dir/task.json"

    json_object \
        "success:bool=true" \
        "task_id=$task_id"
}

# Claim a task (atomic - only one agent can claim)
# Usage: agent_claim_task <task_id>
# Returns: JSON with success status
agent_claim_task() {
    local task_id="$1"
    local task_dir="$AGENT_TASKS_DIR/$task_id"

    mkdir -p "$task_dir"

    # Atomic claim via mkdir (fails if already exists)
    if mkdir "$task_dir/claimed_by_$AGENT_ID" 2>/dev/null; then
        # Update task status
        if [[ -f "$task_dir/task.json" ]]; then
            local task_data
            task_data=$(<"$task_dir/task.json")
            # Note: Simple status update, doesn't modify full JSON
            printf '%s' "$AGENT_ID" > "$task_dir/claimed_by.txt"
        fi

        json_object \
            "success:bool=true" \
            "task_id=$task_id" \
            "claimed_by=$AGENT_ID"
        return 0
    else
        # Check who claimed it
        local claimer=""
        for claim_dir in "$task_dir"/claimed_by_*; do
            [[ -d "$claim_dir" ]] || continue
            claimer="${claim_dir##*claimed_by_}"
            break
        done

        json_object \
            "success:bool=false" \
            "error=task already claimed" \
            "task_id=$task_id" \
            "claimed_by=$claimer"
        return 1
    fi
}

# Complete a task
# Usage: agent_complete_task <task_id> <result>
agent_complete_task() {
    local task_id="$1"
    local result="$2"
    local task_dir="$AGENT_TASKS_DIR/$task_id"

    [[ -d "$task_dir" ]] || {
        json_object \
            "success:bool=false" \
            "error=task not found" \
            "task_id=$task_id"
        return 1
    }

    json_object \
        "task_id=$task_id" \
        "completed_by=$AGENT_ID" \
        "result=$result" \
        "completed_at=$(date -Iseconds)" \
    > "$task_dir/result.json"

    # Notify waiting agents
    agent_broadcast "task_complete" "$task_id"

    json_object \
        "success:bool=true" \
        "task_id=$task_id"
}

# Fail a task
# Usage: agent_fail_task <task_id> <error_message>
agent_fail_task() {
    local task_id="$1"
    local error_msg="$2"
    local task_dir="$AGENT_TASKS_DIR/$task_id"

    [[ -d "$task_dir" ]] || {
        json_object \
            "success:bool=false" \
            "error=task not found" \
            "task_id=$task_id"
        return 1
    }

    json_object \
        "task_id=$task_id" \
        "failed_by=$AGENT_ID" \
        "error=$error_msg" \
        "failed_at=$(date -Iseconds)" \
    > "$task_dir/error.json"

    # Release claim so another agent can try
    rm -rf "$task_dir/claimed_by_$AGENT_ID"
    rm -f "$task_dir/claimed_by.txt"

    # Notify waiting agents
    agent_broadcast "task_failed" "$task_id"

    json_object \
        "success:bool=true" \
        "task_id=$task_id"
}

# Wait for task completion
# Usage: agent_wait_task <task_id> [timeout]
# Returns: Task result JSON or error on timeout
agent_wait_task() {
    local task_id="$1"
    local timeout="${2:-60}"
    local task_dir="$AGENT_TASKS_DIR/$task_id"

    local deadline=$((SECONDS + timeout))

    while (( SECONDS < deadline )); do
        if [[ -f "$task_dir/result.json" ]]; then
            cat "$task_dir/result.json"
            return 0
        fi

        if [[ -f "$task_dir/error.json" ]]; then
            cat "$task_dir/error.json"
            return 1
        fi

        sleep 0.5
    done

    json_object \
        "success:bool=false" \
        "error=timeout waiting for task" \
        "task_id=$task_id"
    return 1
}

# Get task status
# Usage: agent_task_status <task_id>
agent_task_status() {
    local task_id="$1"
    local task_dir="$AGENT_TASKS_DIR/$task_id"

    if [[ ! -d "$task_dir" ]]; then
        json_object \
            "task_id=$task_id" \
            "status=not_found"
        return 1
    fi

    local status="pending"
    local claimer=""

    # Check if claimed
    for claim_dir in "$task_dir"/claimed_by_*; do
        [[ -d "$claim_dir" ]] || continue
        claimer="${claim_dir##*claimed_by_}"
        status="in_progress"
        break
    done

    # Check if completed
    if [[ -f "$task_dir/result.json" ]]; then
        status="completed"
    elif [[ -f "$task_dir/error.json" ]]; then
        status="failed"
    fi

    json_object \
        "task_id=$task_id" \
        "status=$status" \
        "claimed_by=$claimer"
}

# List all tasks
# Usage: agent_list_tasks [status_filter]
# Returns: JSON array of task statuses
agent_list_tasks() {
    local status_filter="${1:-}"
    local -a tasks=()

    mkdir -p "$AGENT_TASKS_DIR"

    for task_dir in "$AGENT_TASKS_DIR"/*/; do
        [[ -d "$task_dir" ]] || continue
        local task_id="${task_dir%/}"
        task_id="${task_id##*/}"

        local task_status
        task_status=$(agent_task_status "$task_id")

        if [[ -z "$status_filter" ]] || [[ "$task_status" == *"\"status\":\"$status_filter\""* ]]; then
            tasks+=("$task_status")
        fi
    done

    if [[ ${#tasks[@]} -eq 0 ]]; then
        printf '[]'
    else
        local first=true
        printf '['
        for task in "${tasks[@]}"; do
            $first || printf ','
            first=false
            printf '%s' "$task"
        done
        printf ']'
    fi
}

# =============================================================================
# 5. SHARED STATE
# =============================================================================

# Set a shared state value
# Usage: agent_state_set <key> <value>
agent_state_set() {
    local key="$1"
    local value="$2"

    mkdir -p "$AGENT_STATE_DIR"

    # Atomic write via temp file + move
    local tmpfile
    tmpfile=$(mktemp "$AGENT_STATE_DIR/.tmp.XXXXXX")
    printf '%s' "$value" > "$tmpfile"
    mv -f "$tmpfile" "$AGENT_STATE_DIR/$key"
}

# Get a shared state value
# Usage: agent_state_get <key> [default]
agent_state_get() {
    local key="$1"
    local default="${2:-}"
    local state_file="$AGENT_STATE_DIR/$key"

    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        printf '%s' "$default"
    fi
}

# Delete a shared state key
# Usage: agent_state_del <key>
agent_state_del() {
    local key="$1"
    rm -f "$AGENT_STATE_DIR/$key"
}

# Check if a shared state key exists
# Usage: agent_state_exists <key>
agent_state_exists() {
    local key="$1"
    [[ -f "$AGENT_STATE_DIR/$key" ]]
}

# Atomic increment (useful for counters)
# Usage: agent_state_incr <key> [amount]
# Returns: New value
agent_state_incr() {
    local key="$1"
    local amount="${2:-1}"

    mkdir -p "$AGENT_STATE_DIR"
    local lockfile="$AGENT_STATE_DIR/${key}.lock"

    (
        flock -x 200
        local current
        current=$(agent_state_get "$key" 0)
        # Ensure it's a valid integer
        if [[ ! "$current" =~ ^-?[0-9]+$ ]]; then
            current=0
        fi
        local new=$((current + amount))
        agent_state_set "$key" "$new"
        printf '%d' "$new"
    ) 200>"$lockfile"
}

# Atomic decrement
# Usage: agent_state_decr <key> [amount]
# Returns: New value
agent_state_decr() {
    local key="$1"
    local amount="${2:-1}"
    agent_state_incr "$key" "-$amount"
}

# List all shared state keys
# Usage: agent_state_list
# Returns: JSON array of keys
agent_state_list() {
    local -a keys=()

    mkdir -p "$AGENT_STATE_DIR"

    for state_file in "$AGENT_STATE_DIR"/*; do
        [[ -f "$state_file" ]] || continue
        local key="${state_file##*/}"
        # Skip lock files and temp files
        [[ "$key" == *.lock ]] && continue
        [[ "$key" == .tmp.* ]] && continue
        keys+=("$key")
    done

    json_array "${keys[@]}"
}

# Compare and swap (atomic conditional update)
# Usage: agent_state_cas <key> <expected> <new_value>
# Returns: 0 if swap succeeded, 1 if value didn't match
agent_state_cas() {
    local key="$1"
    local expected="$2"
    local new_value="$3"

    mkdir -p "$AGENT_STATE_DIR"
    local lockfile="$AGENT_STATE_DIR/${key}.lock"

    (
        flock -x 200
        local current
        current=$(agent_state_get "$key" "")

        if [[ "$current" == "$expected" ]]; then
            agent_state_set "$key" "$new_value"
            exit 0
        else
            exit 1
        fi
    ) 200>"$lockfile"
}

# =============================================================================
# 6. CLEANUP
# =============================================================================

# Shutdown this agent gracefully
# Usage: agent_shutdown
agent_shutdown() {
    [[ -z "$AGENT_ID" ]] && return 0

    agent_status "shutting_down"

    # Remove from registry
    rm -f "$AGENT_REGISTRY_DIR/$AGENT_ID.json"

    # Cleanup workspace
    # shellcheck disable=SC2115
    rm -rf "${AGENT_BASE_DIR:?}/${AGENT_ID:?}"

    local old_id="$AGENT_ID"
    AGENT_ID=""
    AGENT_CAPABILITIES=()

    json_object \
        "success:bool=true" \
        "agent_id=$old_id" \
        "status=shutdown"
}

# Cleanup dead agents (housekeeping)
# Usage: agent_cleanup_dead
# Returns: Number of cleaned up agents
agent_cleanup_dead() {
    local cleaned=0

    mkdir -p "$AGENT_REGISTRY_DIR"

    for agent_file in "$AGENT_REGISTRY_DIR"/*.json; do
        [[ -f "$agent_file" ]] || continue
        local agent_id pid
        agent_id=$(json_get "$(<"$agent_file")" "id")
        pid=$(json_get "$(<"$agent_file")" "pid")

        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$agent_file"
            # shellcheck disable=SC2115
            rm -rf "${AGENT_BASE_DIR:?}/${agent_id:?}"
            ((cleaned++))
        fi
    done

    printf '%d' "$cleaned"
}

# Full cleanup of all agent infrastructure
# Usage: agent_cleanup_all
# WARNING: This removes ALL agent data
agent_cleanup_all() {
    rm -rf "$AGENT_BASE_DIR"
    AGENT_ID=""
    AGENT_CAPABILITIES=()

    json_object \
        "success:bool=true" \
        "message=all agent data cleaned"
}

# =============================================================================
# 7. ERROR REPORTING
# =============================================================================

# Report an agent error (logged to workspace)
# Usage: agent_error <message>
agent_error() {
    local message="$1"

    if [[ -n "$AGENT_ID" ]]; then
        local error_log="$AGENT_BASE_DIR/$AGENT_ID/errors.log"
        printf '[%s] ERROR: %s\n' "$(date -Iseconds)" "$message" >> "$error_log"
    fi

    json_object \
        "success:bool=false" \
        "error=$message" \
        "agent_id=$AGENT_ID"
}

# Report an agent warning
# Usage: agent_warn <message>
agent_warn() {
    local message="$1"

    if [[ -n "$AGENT_ID" ]]; then
        local warn_log="$AGENT_BASE_DIR/$AGENT_ID/warnings.log"
        printf '[%s] WARN: %s\n' "$(date -Iseconds)" "$message" >> "$warn_log"
    fi
}

# Report agent progress
# Usage: agent_progress <current> <total> [description]
agent_progress() {
    local current="$1"
    local total="$2"
    local description="${3:-}"

    local percent=0
    (( total > 0 )) && percent=$((current * 100 / total))

    agent_status "working" "Progress: $current/$total ($percent%) $description"

    json_object \
        "current:number=$current" \
        "total:number=$total" \
        "percent:number=$percent" \
        "description=$description"
}

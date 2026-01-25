#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/agent.sh - Multi-Agent Communication Module
# =============================================================================
# Description: File-based IPC for multi-agent coordination. Provides agent
#              registration, discovery, messaging (point-to-point and broadcast),
#              work queues, and synchronization primitives (barriers, signals).
# Version: 1.0.0
# Requires: Bash 4.0+, flock (util-linux)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_AGENT_LOADED:-}" ]] && return 0
_MAINFRAME_AGENT_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Base directory for all agent IPC
_MAINFRAME_AGENT_BASE="${MAINFRAME_AGENT_DIR:-${TMPDIR:-/tmp}/mainframe-${UID:-$(id -u)}/agents}"

# Current agent name (set by agent_register)
_MAINFRAME_AGENT_NAME=""

# Default receive timeout in seconds
_MAINFRAME_AGENT_RECV_TIMEOUT=5

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_agent_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[agent] %s: %s\n' "${level}" "$*" >&2
    fi
}

# Generate a monotonic message filename for FIFO ordering
# Uses nanosecond timestamp + PID + sequence counter for uniqueness
_agent_msg_filename() {
    local ts
    ts="$(date +%s%N 2>/dev/null || date +%s)"
    _MAINFRAME_AGENT_SEQ="${_MAINFRAME_AGENT_SEQ:-0}"
    _MAINFRAME_AGENT_SEQ=$(( _MAINFRAME_AGENT_SEQ + 1 ))
    printf 'msg_%s_%s_%s' "$ts" "$$" "$_MAINFRAME_AGENT_SEQ"
}

# Get the registry directory for a named agent
_agent_dir() {
    local name="$1"
    printf '%s/%s' "$_MAINFRAME_AGENT_BASE" "$name"
}

# Get inbox directory for a named agent
_agent_inbox() {
    local name="$1"
    printf '%s/%s/inbox' "$_MAINFRAME_AGENT_BASE" "$name"
}

# Get outbox directory for a named agent
_agent_outbox() {
    local name="$1"
    printf '%s/%s/outbox' "$_MAINFRAME_AGENT_BASE" "$name"
}

# Check if an agent is registered
_agent_exists() {
    local name="$1"
    [[ -f "$(_agent_dir "$name")/registered" ]]
}

# Escape a string for JSON embedding (minimal pure-bash)
_agent_json_escape() {
    local str="$1"
    local result=""
    local i char

    for ((i = 0; i < ${#str}; i++)); do
        char="${str:i:1}"
        case "$char" in
            '"')  result+='\"' ;;
            '\')  result+='\\' ;;
            $'\n') result+='\n' ;;
            $'\r') result+='\r' ;;
            $'\t') result+='\t' ;;
            *)    result+="$char" ;;
        esac
    done
    printf '%s' "$result"
}

# Get current ISO timestamp
_agent_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%S.%NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Get current epoch (seconds)
_agent_epoch() {
    date +%s
}

# =============================================================================
# AGENT REGISTRATION & DISCOVERY
# =============================================================================

# @pre: MAINFRAME_AGENT_DIR is writable
# @post: Agent directory structure created with inbox/outbox
# @returns: 0 on success, 1 on failure
#
# Register an agent with optional capabilities. Creates directory structure:
#   agents/<name>/registered    (timestamp)
#   agents/<name>/capabilities  (one per line)
#   agents/<name>/heartbeat     (epoch)
#   agents/<name>/inbox/        (incoming messages)
#   agents/<name>/outbox/       (sent messages log)
#
# Usage: agent_register NAME [CAPABILITY1 CAPABILITY2 ...]
# Example: agent_register worker1 compute storage
agent_register() {
    local name="${1:-}"
    shift || true

    if [[ -z "$name" ]]; then
        _agent_log error "agent_register: agent name required"
        return 1
    fi

    local agent_dir
    agent_dir="$(_agent_dir "$name")"

    # Create directory structure with restricted permissions
    mkdir -p "$agent_dir/inbox" "$agent_dir/outbox" || {
        _agent_log error "agent_register: failed to create directories for '$name'"
        return 1
    }
    chmod 700 "$_MAINFRAME_AGENT_BASE" 2>/dev/null

    # Write registration timestamp
    _agent_timestamp > "$agent_dir/registered"

    # Write capabilities (one per line)
    : > "$agent_dir/capabilities"
    local cap
    for cap in "$@"; do
        printf '%s\n' "$cap" >> "$agent_dir/capabilities"
    done

    # Initialize heartbeat
    _agent_epoch > "$agent_dir/heartbeat"

    # Set current agent name
    _MAINFRAME_AGENT_NAME="$name"

    _agent_log info "Registered agent '$name' with ${#@} capabilities"
    return 0
}

# @pre: Agent was previously registered
# @post: Agent directory removed, _MAINFRAME_AGENT_NAME cleared if self
# @returns: 0 on success, 1 if not registered
#
# Unregister an agent, removing all state.
# If no name given, unregisters current agent.
#
# Usage: agent_unregister [NAME]
# Example: agent_unregister worker1
agent_unregister() {
    local name="${1:-$_MAINFRAME_AGENT_NAME}"

    if [[ -z "$name" ]]; then
        _agent_log error "agent_unregister: no agent name (not registered?)"
        return 1
    fi

    if ! _agent_exists "$name"; then
        _agent_log error "agent_unregister: agent '$name' not registered"
        return 1
    fi

    local agent_dir
    agent_dir="$(_agent_dir "$name")"
    rm -rf "$agent_dir"

    # Clear current name if unregistering self
    if [[ "$name" == "$_MAINFRAME_AGENT_NAME" ]]; then
        _MAINFRAME_AGENT_NAME=""
    fi

    _agent_log info "Unregistered agent '$name'"
    return 0
}

# @pre: Agents are registered with capabilities
# @post: Prints agent names (one per line) that have the capability
# @returns: 0 if found, 1 if none found
#
# Discover agents with a specific capability.
#
# Usage: agent_discover CAPABILITY
# Example: agent_discover compute
agent_discover() {
    local capability="${1:-}"
    local found=0

    if [[ -z "$capability" ]]; then
        _agent_log error "agent_discover: capability required"
        return 1
    fi

    local agent_dir
    for agent_dir in "$_MAINFRAME_AGENT_BASE"/*/; do
        [[ -d "$agent_dir" ]] || continue
        local name="${agent_dir%/}"
        name="${name##*/}"

        [[ -f "$agent_dir/registered" ]] || continue
        [[ -f "$agent_dir/capabilities" ]] || continue

        if grep -qx "$capability" "$agent_dir/capabilities" 2>/dev/null; then
            printf '%s\n' "$name"
            found=$(( found + 1 ))
        fi
    done

    [[ $found -gt 0 ]]
}

# @pre: Base directory exists
# @post: Prints JSON array of registered agents
# @returns: 0 always
#
# List all registered agents with their capabilities as JSON.
#
# Usage: agent_list
# Example: agent_list  # [{"name":"worker1","capabilities":["compute"]}]
agent_list() {
    local first=true
    local output="["

    local agent_dir
    for agent_dir in "$_MAINFRAME_AGENT_BASE"/*/; do
        [[ -d "$agent_dir" ]] || continue
        local name="${agent_dir%/}"
        name="${name##*/}"
        [[ -f "$agent_dir/registered" ]] || continue

        $first || output+=","
        first=false

        # Read capabilities
        local caps_json="["
        local cap_first=true
        if [[ -f "$agent_dir/capabilities" ]]; then
            while IFS= read -r cap; do
                [[ -z "$cap" ]] && continue
                $cap_first || caps_json+=","
                cap_first=false
                caps_json+="\"$(_agent_json_escape "$cap")\""
            done < "$agent_dir/capabilities"
        fi
        caps_json+="]"

        output+="{\"name\":\"$(_agent_json_escape "$name")\",\"capabilities\":$caps_json}"
    done

    output+="]"
    printf '%s\n' "$output"
}

# @pre: Agent is registered
# @post: Prints JSON status object
# @returns: 0 on success, 1 if not registered
#
# Get agent status as JSON object with registration time, heartbeat,
# capabilities, and message count.
#
# Usage: agent_status [NAME]
# Example: agent_status worker1
agent_status() {
    local name="${1:-$_MAINFRAME_AGENT_NAME}"

    if [[ -z "$name" ]]; then
        _agent_log error "agent_status: agent name required"
        return 1
    fi

    if ! _agent_exists "$name"; then
        _agent_log error "agent_status: agent '$name' not registered"
        return 1
    fi

    local agent_dir
    agent_dir="$(_agent_dir "$name")"

    local registered_at=""
    [[ -f "$agent_dir/registered" ]] && registered_at="$(cat "$agent_dir/registered")"

    local last_heartbeat=""
    [[ -f "$agent_dir/heartbeat" ]] && last_heartbeat="$(cat "$agent_dir/heartbeat")"

    # Read capabilities
    local caps_json="["
    local cap_first=true
    if [[ -f "$agent_dir/capabilities" ]]; then
        while IFS= read -r cap; do
            [[ -z "$cap" ]] && continue
            $cap_first || caps_json+=","
            cap_first=false
            caps_json+="\"$(_agent_json_escape "$cap")\""
        done < "$agent_dir/capabilities"
    fi
    caps_json+="]"

    # Count messages in inbox
    local msg_count=0
    if [[ -d "$agent_dir/inbox" ]]; then
        local count_files
        count_files=( "$agent_dir/inbox"/msg_* )
        if [[ -e "${count_files[0]}" ]]; then
            msg_count=${#count_files[@]}
        fi
    fi

    printf '{"name":"%s","registered_at":"%s","last_heartbeat":"%s","capabilities":%s,"message_count":%d}\n' \
        "$(_agent_json_escape "$name")" \
        "$(_agent_json_escape "$registered_at")" \
        "$(_agent_json_escape "$last_heartbeat")" \
        "$caps_json" \
        "$msg_count"
}

# @pre: Agent is registered
# @post: Heartbeat file updated with current epoch
# @returns: 0 on success, 1 if not registered
#
# Update the heartbeat timestamp for the current agent.
#
# Usage: agent_heartbeat
agent_heartbeat() {
    local name="${_MAINFRAME_AGENT_NAME}"

    if [[ -z "$name" ]]; then
        _agent_log error "agent_heartbeat: not registered"
        return 1
    fi

    local agent_dir
    agent_dir="$(_agent_dir "$name")"

    if ! _agent_exists "$name"; then
        _agent_log error "agent_heartbeat: agent '$name' not registered"
        return 1
    fi

    _agent_epoch > "$agent_dir/heartbeat"
    return 0
}

# =============================================================================
# MESSAGING
# =============================================================================

# @pre: Current agent registered, target agent registered
# @post: JSON message file created in target's inbox
# @returns: 0 on success, 1 on failure
#
# Send a message to a target agent. The message is written as a JSON file
# into the target agent's inbox directory.
#
# Usage: agent_send TARGET MESSAGE
# Example: agent_send worker2 '{"task":"compute","data":[1,2,3]}'
agent_send() {
    local target="${1:-}"
    local message="${2:-}"

    if [[ -z "$target" ]]; then
        _agent_log error "agent_send: target agent required"
        return 1
    fi

    if [[ -z "$message" ]]; then
        _agent_log error "agent_send: message required"
        return 1
    fi

    if ! _agent_exists "$target"; then
        _agent_log error "agent_send: target agent '$target' not registered"
        return 1
    fi

    local from="${_MAINFRAME_AGENT_NAME:-anonymous}"
    local inbox
    inbox="$(_agent_inbox "$target")"
    local msg_file
    msg_file="$inbox/$(_agent_msg_filename)"
    local timestamp
    timestamp="$(_agent_timestamp)"

    # Build JSON message envelope
    local escaped_payload
    escaped_payload="$(_agent_json_escape "$message")"
    local json
    json=$(printf '{"from":"%s","to":"%s","timestamp":"%s","payload":"%s"}' \
        "$(_agent_json_escape "$from")" \
        "$(_agent_json_escape "$target")" \
        "$timestamp" \
        "$escaped_payload")

    printf '%s\n' "$json" > "$msg_file"
    return 0
}

# @pre: Current agent registered with inbox
# @post: Oldest message consumed (removed from inbox), printed to stdout
# @returns: 0 if message received, 1 on timeout/error
#
# Receive the next message from the agent's inbox (FIFO order).
# Uses flock for atomic consumption. Waits up to TIMEOUT seconds.
#
# Usage: agent_receive [TIMEOUT_SECS]
# Example: msg=$(agent_receive 10)
agent_receive() {
    local timeout="${1:-$_MAINFRAME_AGENT_RECV_TIMEOUT}"
    local name="${_MAINFRAME_AGENT_NAME}"

    if [[ -z "$name" ]]; then
        _agent_log error "agent_receive: not registered"
        return 1
    fi

    local inbox
    inbox="$(_agent_inbox "$name")"
    local lockfile="$inbox/.lock"
    local deadline
    deadline=$(( $(_agent_epoch) + timeout ))

    while [[ $(_agent_epoch) -le $deadline ]]; do
        # Try to atomically consume the oldest message
        (
            flock -n 200 || exit 1

            # Find oldest message file (sorted lexicographically = chronological)
            local oldest=""
            local f
            for f in "$inbox"/msg_*; do
                [[ -e "$f" ]] || break
                oldest="$f"
                break
            done

            if [[ -n "$oldest" && -f "$oldest" ]]; then
                cat "$oldest"
                rm -f "$oldest"
                exit 0
            fi
            exit 1
        ) 200>"$lockfile"

        local rc=$?
        if [[ $rc -eq 0 ]]; then
            return 0
        fi

        # Brief sleep before retry
        sleep 0.05 2>/dev/null || sleep 1
    done

    return 1
}

# @pre: Current agent registered, other agents registered
# @post: Message sent to all registered agents except sender
# @returns: 0 on success (even if no recipients)
#
# Broadcast a message to all registered agents.
#
# Usage: agent_broadcast MESSAGE
# Example: agent_broadcast '{"event":"shutdown"}'
agent_broadcast() {
    local message="${1:-}"

    if [[ -z "$message" ]]; then
        _agent_log error "agent_broadcast: message required"
        return 1
    fi

    local from="${_MAINFRAME_AGENT_NAME:-anonymous}"
    local agent_dir

    for agent_dir in "$_MAINFRAME_AGENT_BASE"/*/; do
        [[ -d "$agent_dir" ]] || continue
        local target="${agent_dir%/}"
        target="${target##*/}"

        [[ -f "$agent_dir/registered" ]] || continue
        # Skip self
        [[ "$target" == "$from" ]] && continue

        agent_send "$target" "$message"
    done

    return 0
}

# @pre: Current agent registered with inbox
# @post: Prints next message without consuming it
# @returns: 0 if message exists, 1 if inbox empty
#
# View the next message in the inbox without removing it.
#
# Usage: agent_peek
# Example: next=$(agent_peek)
agent_peek() {
    local name="${_MAINFRAME_AGENT_NAME}"

    if [[ -z "$name" ]]; then
        _agent_log error "agent_peek: not registered"
        return 1
    fi

    local inbox
    inbox="$(_agent_inbox "$name")"

    local f
    for f in "$inbox"/msg_*; do
        [[ -e "$f" ]] || break
        cat "$f"
        return 0
    done

    return 1
}

# @pre: Current agent registered
# @post: Prints count of pending messages
# @returns: 0 always
#
# Get the number of pending messages in the inbox.
#
# Usage: agent_inbox_count
# Example: count=$(agent_inbox_count)
agent_inbox_count() {
    local name="${_MAINFRAME_AGENT_NAME}"

    if [[ -z "$name" ]]; then
        _agent_log error "agent_inbox_count: not registered"
        printf '0\n'
        return 1
    fi

    local inbox
    inbox="$(_agent_inbox "$name")"

    local files
    files=( "$inbox"/msg_* )
    if [[ -e "${files[0]}" ]]; then
        printf '%d\n' "${#files[@]}"
    else
        printf '0\n'
    fi
    return 0
}

# @pre: Current agent registered
# @post: All messages in inbox removed
# @returns: 0 on success
#
# Delete all pending messages from the inbox.
#
# Usage: agent_clear_inbox
agent_clear_inbox() {
    local name="${_MAINFRAME_AGENT_NAME}"

    if [[ -z "$name" ]]; then
        _agent_log error "agent_clear_inbox: not registered"
        return 1
    fi

    local inbox
    inbox="$(_agent_inbox "$name")"
    rm -f "$inbox"/msg_* 2>/dev/null
    return 0
}

# =============================================================================
# WORK QUEUES
# =============================================================================

# @pre: Base directory writable
# @post: Queue directory created
# @returns: 0 on success
#
# Create or ensure a named work queue exists.
#
# Usage: agent_work_queue QUEUE_NAME
# Example: agent_work_queue tasks
agent_work_queue() {
    local queue_name="${1:-}"

    if [[ -z "$queue_name" ]]; then
        _agent_log error "agent_work_queue: queue name required"
        return 1
    fi

    local queue_dir="$_MAINFRAME_AGENT_BASE/_queues/$queue_name"
    mkdir -p "$queue_dir" || {
        _agent_log error "agent_work_queue: failed to create queue '$queue_name'"
        return 1
    }
    return 0
}

# @pre: Queue exists
# @post: Item appended to queue as JSON file
# @returns: 0 on success, 1 on failure
#
# Push an item onto a work queue. Items are JSON payloads.
#
# Usage: agent_work_push QUEUE ITEM
# Example: agent_work_push tasks '{"url":"http://example.com"}'
agent_work_push() {
    local queue_name="${1:-}"
    local item="${2:-}"

    if [[ -z "$queue_name" ]]; then
        _agent_log error "agent_work_push: queue name required"
        return 1
    fi

    if [[ -z "$item" ]]; then
        _agent_log error "agent_work_push: item required"
        return 1
    fi

    local queue_dir="$_MAINFRAME_AGENT_BASE/_queues/$queue_name"
    if [[ ! -d "$queue_dir" ]]; then
        _agent_log error "agent_work_push: queue '$queue_name' does not exist"
        return 1
    fi

    local item_file
    item_file="$queue_dir/$(_agent_msg_filename)"

    local timestamp
    timestamp="$(_agent_timestamp)"
    local producer="${_MAINFRAME_AGENT_NAME:-anonymous}"

    local json
    json=$(printf '{"producer":"%s","timestamp":"%s","item":"%s"}' \
        "$(_agent_json_escape "$producer")" \
        "$timestamp" \
        "$(_agent_json_escape "$item")")

    printf '%s\n' "$json" > "$item_file"
    return 0
}

# @pre: Queue exists
# @post: Oldest item consumed (removed), content printed to stdout
# @returns: 0 if item popped, 1 if queue empty
#
# Pop the next item from a work queue (FIFO, atomic with flock).
#
# Usage: agent_work_pop QUEUE
# Example: item=$(agent_work_pop tasks)
agent_work_pop() {
    local queue_name="${1:-}"

    if [[ -z "$queue_name" ]]; then
        _agent_log error "agent_work_pop: queue name required"
        return 1
    fi

    local queue_dir="$_MAINFRAME_AGENT_BASE/_queues/$queue_name"
    if [[ ! -d "$queue_dir" ]]; then
        _agent_log error "agent_work_pop: queue '$queue_name' does not exist"
        return 1
    fi

    local lockfile="$queue_dir/.lock"

    (
        flock 200 || exit 1

        local oldest=""
        local f
        for f in "$queue_dir"/msg_*; do
            [[ -e "$f" ]] || break
            oldest="$f"
            break
        done

        if [[ -n "$oldest" && -f "$oldest" ]]; then
            cat "$oldest"
            rm -f "$oldest"
            exit 0
        fi
        exit 1
    ) 200>"$lockfile"
}

# @pre: Queue exists
# @post: Prints item count
# @returns: 0 always
#
# Count the number of items remaining in a work queue.
#
# Usage: agent_work_count QUEUE
# Example: remaining=$(agent_work_count tasks)
agent_work_count() {
    local queue_name="${1:-}"

    if [[ -z "$queue_name" ]]; then
        _agent_log error "agent_work_count: queue name required"
        printf '0\n'
        return 1
    fi

    local queue_dir="$_MAINFRAME_AGENT_BASE/_queues/$queue_name"
    if [[ ! -d "$queue_dir" ]]; then
        printf '0\n'
        return 0
    fi

    local files
    files=( "$queue_dir"/msg_* )
    if [[ -e "${files[0]}" ]]; then
        printf '%d\n' "${#files[@]}"
    else
        printf '0\n'
    fi
    return 0
}

# @pre: Queue exists
# @post: All items in queue removed
# @returns: 0 on success
#
# Remove all items from a work queue.
#
# Usage: agent_work_clear QUEUE
# Example: agent_work_clear tasks
agent_work_clear() {
    local queue_name="${1:-}"

    if [[ -z "$queue_name" ]]; then
        _agent_log error "agent_work_clear: queue name required"
        return 1
    fi

    local queue_dir="$_MAINFRAME_AGENT_BASE/_queues/$queue_name"
    if [[ ! -d "$queue_dir" ]]; then
        _agent_log error "agent_work_clear: queue '$queue_name' does not exist"
        return 1
    fi

    rm -f "$queue_dir"/msg_* 2>/dev/null
    return 0
}

# =============================================================================
# SYNCHRONIZATION
# =============================================================================

# @pre: Base directory writable
# @post: Waits until COUNT agents have reached the barrier, or timeout
# @returns: 0 if barrier reached, 1 on timeout
#
# Barrier synchronization: wait until COUNT agents reach the same barrier.
# Each agent calls agent_barrier with the same NAME. When COUNT agents
# have called it, all are released.
#
# Usage: agent_barrier NAME COUNT [TIMEOUT]
# Example: agent_barrier phase1_done 3 30
agent_barrier() {
    local barrier_name="${1:-}"
    local count="${2:-}"
    local timeout="${3:-30}"

    if [[ -z "$barrier_name" || -z "$count" ]]; then
        _agent_log error "agent_barrier: name and count required"
        return 1
    fi

    local barrier_dir="$_MAINFRAME_AGENT_BASE/_barriers/$barrier_name"
    mkdir -p "$barrier_dir"

    local agent_name="${_MAINFRAME_AGENT_NAME:-$$}"

    # Register at barrier
    printf '%s\n' "$(_agent_epoch)" > "$barrier_dir/$agent_name"

    # Wait for enough participants
    local deadline
    deadline=$(( $(_agent_epoch) + timeout ))

    while [[ $(_agent_epoch) -le $deadline ]]; do
        local arrived=0
        local f
        for f in "$barrier_dir"/*; do
            [[ -e "$f" ]] || continue
            # Skip hidden files (locks)
            local base="${f##*/}"
            [[ "$base" == .* ]] && continue
            arrived=$(( arrived + 1 ))
        done

        if [[ $arrived -ge $count ]]; then
            return 0
        fi

        sleep 0.05 2>/dev/null || sleep 1
    done

    local _barrier_arrived=0
    if [[ -d "$barrier_dir" ]]; then
        local _bf
        for _bf in "$barrier_dir"/*; do
            [[ -e "$_bf" ]] && _barrier_arrived=$(( _barrier_arrived + 1 ))
        done
    fi
    _agent_log error "agent_barrier: timeout waiting for barrier '$barrier_name' (got $_barrier_arrived/$count)"
    return 1
}

# @pre: Base directory writable
# @post: Signal file created
# @returns: 0 always
#
# Signal a named event. Any agents waiting via agent_wait will be released.
#
# Usage: agent_signal NAME
# Example: agent_signal data_ready
agent_signal() {
    local signal_name="${1:-}"

    if [[ -z "$signal_name" ]]; then
        _agent_log error "agent_signal: signal name required"
        return 1
    fi

    local signal_dir="$_MAINFRAME_AGENT_BASE/_signals"
    mkdir -p "$signal_dir"

    local sender="${_MAINFRAME_AGENT_NAME:-$$}"
    printf '%s %s\n' "$(_agent_epoch)" "$sender" > "$signal_dir/$signal_name"
    return 0
}

# @pre: Base directory exists
# @post: Returns when signal is raised, or on timeout
# @returns: 0 if signal received, 1 on timeout
#
# Wait for a named signal event.
#
# Usage: agent_wait NAME [TIMEOUT]
# Example: agent_wait data_ready 60
agent_wait() {
    local signal_name="${1:-}"
    local timeout="${2:-30}"

    if [[ -z "$signal_name" ]]; then
        _agent_log error "agent_wait: signal name required"
        return 1
    fi

    local signal_file="$_MAINFRAME_AGENT_BASE/_signals/$signal_name"
    local deadline
    deadline=$(( $(_agent_epoch) + timeout ))

    while [[ $(_agent_epoch) -le $deadline ]]; do
        if [[ -f "$signal_file" ]]; then
            return 0
        fi
        sleep 0.05 2>/dev/null || sleep 1
    done

    _agent_log error "agent_wait: timeout waiting for signal '$signal_name'"
    return 1
}

# =============================================================================
# ADDITIONAL REGISTRATION FUNCTIONS
# =============================================================================

# @pre: Agent must be registered
# @post: Prints JSON with agent details
# @returns: 0 on success, 1 if not found
#
# Get detailed info for an agent (alias for agent_status).
#
# Usage: agent_info NAME
# Example: agent_info worker1
agent_info() {
    agent_status "$@"
}

# @pre: Nameref variable passed
# @post: Result stored in variable (avoids subshell overhead)
# @returns: 0 on success, 1 if not found
#
# Store agent info in a variable (nameref variant).
#
# Usage: agent_info_v RESULT_VAR NAME
# Example: agent_info_v info "worker1"
agent_info_v() {
    local -n __aiv_out=$1
    local name="${2:-$_MAINFRAME_AGENT_NAME}"

    if [[ -z "$name" ]]; then
        _agent_log error "agent_info_v: agent name required"
        return 1
    fi

    if ! _agent_exists "$name"; then
        _agent_log error "agent_info_v: agent '$name' not found"
        return 1
    fi

    __aiv_out=$(agent_status "$name")
    return 0
}

# @pre: Base directory exists
# @post: Stale agents removed from registry
# @returns: 0 on success
#
# Remove agents that haven't sent a heartbeat within the specified time.
#
# Usage: agent_prune [--older-than SECONDS]
# Example: agent_prune --older-than 300
agent_prune() {
    local max_age=300  # Default 5 minutes

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --older-than)
                max_age="${2:-300}"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    local now
    now=$(_agent_epoch)
    local cutoff=$(( now - max_age ))
    local pruned=0

    local agent_dir
    for agent_dir in "$_MAINFRAME_AGENT_BASE"/*/; do
        [[ -d "$agent_dir" ]] || continue
        local name="${agent_dir%/}"
        name="${name##*/}"

        [[ -f "$agent_dir/registered" ]] || continue

        local last_seen=0
        if [[ -f "$agent_dir/heartbeat" ]]; then
            last_seen=$(cat "$agent_dir/heartbeat" 2>/dev/null || echo 0)
        fi

        if [[ $last_seen -lt $cutoff ]]; then
            agent_unregister "$name" 2>/dev/null
            pruned=$(( pruned + 1 ))
        fi
    done

    _agent_log info "Pruned $pruned stale agents"
    return 0
}

# @pre: Nameref array variable passed
# @post: Array populated with agent names
# @returns: 0 always
#
# Store list of agent names in an array (nameref variant).
#
# Usage: agent_list_v ARRAY_VAR
# Example: local -a agents; agent_list_v agents
agent_list_v() {
    local -n __alv_out=$1
    __alv_out=()

    local agent_dir
    for agent_dir in "$_MAINFRAME_AGENT_BASE"/*/; do
        [[ -d "$agent_dir" ]] || continue
        local name="${agent_dir%/}"
        name="${name##*/}"
        [[ -f "$agent_dir/registered" ]] || continue
        __alv_out+=("$name")
    done
}

# =============================================================================
# ASYNCHRONOUS RECEIVE
# =============================================================================

# @pre: Current agent registered with inbox
# @post: If message available, prints it. Otherwise returns immediately.
# @returns: 0 if message received, 1 if no message
#
# Non-blocking receive: returns immediately if no message available.
#
# Usage: agent_receive_async
# Example: msg=$(agent_receive_async) || echo "No message"
agent_receive_async() {
    local name="${_MAINFRAME_AGENT_NAME}"

    if [[ -z "$name" ]]; then
        _agent_log error "agent_receive_async: not registered"
        return 1
    fi

    local inbox
    inbox="$(_agent_inbox "$name")"
    local lockfile="$inbox/.lock"

    (
        flock -n 200 || exit 1

        local oldest=""
        local f
        for f in "$inbox"/msg_*; do
            [[ -e "$f" ]] || break
            oldest="$f"
            break
        done

        if [[ -n "$oldest" && -f "$oldest" ]]; then
            cat "$oldest"
            rm -f "$oldest"
            exit 0
        fi
        exit 1
    ) 200>"$lockfile"
}

# =============================================================================
# PUB/SUB: TOPIC-BASED MESSAGING
# =============================================================================

# @pre: Agent is registered
# @post: Agent added to topic subscriber list
# @returns: 0 on success
#
# Subscribe an agent to a topic for pub/sub messaging.
#
# Usage: agent_subscribe TOPIC
# Example: agent_subscribe "news"
agent_subscribe() {
    local topic="${1:-}"
    local name="${_MAINFRAME_AGENT_NAME}"

    if [[ -z "$topic" ]]; then
        _agent_log error "agent_subscribe: topic required"
        return 1
    fi

    if [[ -z "$name" ]]; then
        _agent_log error "agent_subscribe: not registered"
        return 1
    fi

    local topics_dir="$_MAINFRAME_AGENT_BASE/_topics"
    mkdir -p "$topics_dir"

    local topic_file="$topics_dir/$topic"
    local lockfile="$topics_dir/.lock_$topic"

    (
        flock 200

        # Add to subscriber list if not already present
        if ! grep -qx "$name" "$topic_file" 2>/dev/null; then
            printf '%s\n' "$name" >> "$topic_file"
        fi
    ) 200>"$lockfile"

    _agent_log info "Agent '$name' subscribed to topic '$topic'"
    return 0
}

# @pre: Agent is subscribed to topic
# @post: Agent removed from topic subscriber list
# @returns: 0 on success
#
# Unsubscribe an agent from a topic.
#
# Usage: agent_unsubscribe TOPIC
# Example: agent_unsubscribe "news"
agent_unsubscribe() {
    local topic="${1:-}"
    local name="${_MAINFRAME_AGENT_NAME}"

    if [[ -z "$topic" ]]; then
        _agent_log error "agent_unsubscribe: topic required"
        return 1
    fi

    if [[ -z "$name" ]]; then
        _agent_log error "agent_unsubscribe: not registered"
        return 1
    fi

    local topic_file="$_MAINFRAME_AGENT_BASE/_topics/$topic"
    local lockfile="$_MAINFRAME_AGENT_BASE/_topics/.lock_$topic"

    if [[ ! -f "$topic_file" ]]; then
        return 0
    fi

    (
        flock 200

        # Remove from subscriber list
        local tmp
        tmp=$(mktemp)
        grep -vx "$name" "$topic_file" > "$tmp" 2>/dev/null || true
        mv "$tmp" "$topic_file"
    ) 200>"$lockfile"

    _agent_log info "Agent '$name' unsubscribed from topic '$topic'"
    return 0
}

# @pre: Topic has subscribers
# @post: Message sent to all topic subscribers
# @returns: 0 on success, 1 if topic not found
#
# Publish a message to all subscribers of a topic.
#
# Usage: agent_publish TOPIC MESSAGE
# Example: agent_publish "news" '{"headline":"Breaking news"}'
agent_publish() {
    local topic="${1:-}"
    local message="${2:-}"

    if [[ -z "$topic" ]]; then
        _agent_log error "agent_publish: topic required"
        return 1
    fi

    if [[ -z "$message" ]]; then
        _agent_log error "agent_publish: message required"
        return 1
    fi

    local topic_file="$_MAINFRAME_AGENT_BASE/_topics/$topic"

    if [[ ! -f "$topic_file" ]]; then
        _agent_log error "agent_publish: topic '$topic' not found"
        return 1
    fi

    local subscriber
    while IFS= read -r subscriber; do
        [[ -z "$subscriber" ]] && continue
        if _agent_exists "$subscriber"; then
            agent_send "$subscriber" "$message"
        fi
    done < "$topic_file"

    return 0
}

# =============================================================================
# RESOURCE LOCKING
# =============================================================================

# @pre: Base directory writable
# @post: Exclusive lock acquired on resource
# @returns: 0 on success (blocks until acquired)
#
# Acquire an exclusive lock on a named resource.
# This is a blocking operation that waits until the lock is available.
#
# Usage: agent_lock RESOURCE
# Example: agent_lock "database"
agent_lock() {
    local resource="${1:-}"
    local name="${_MAINFRAME_AGENT_NAME:-$$}"

    if [[ -z "$resource" ]]; then
        _agent_log error "agent_lock: resource name required"
        return 1
    fi

    local locks_dir="$_MAINFRAME_AGENT_BASE/_locks"
    mkdir -p "$locks_dir"

    local lockfile="$locks_dir/$resource.lock"

    # Use flock to acquire exclusive lock
    exec {_AGENT_LOCK_FD}>>"$lockfile"
    flock "$_AGENT_LOCK_FD"

    # Write holder info
    printf '%s %s\n' "$name" "$(_agent_epoch)" > "$lockfile"

    _agent_log info "Agent '$name' acquired lock on '$resource'"
    return 0
}

# @pre: Lock was previously acquired by this agent
# @post: Lock released
# @returns: 0 on success
#
# Release a previously acquired lock.
#
# Usage: agent_unlock RESOURCE
# Example: agent_unlock "database"
agent_unlock() {
    local resource="${1:-}"

    if [[ -z "$resource" ]]; then
        _agent_log error "agent_unlock: resource name required"
        return 1
    fi

    local locks_dir="$_MAINFRAME_AGENT_BASE/_locks"
    local lockfile="$locks_dir/$resource.lock"

    if [[ -v _AGENT_LOCK_FD ]]; then
        flock -u "$_AGENT_LOCK_FD" 2>/dev/null
        exec {_AGENT_LOCK_FD}>&-
        unset _AGENT_LOCK_FD
    fi

    rm -f "$lockfile" 2>/dev/null
    return 0
}

# @pre: Base directory writable
# @post: Lock acquired if available, otherwise returns immediately
# @returns: 0 if lock acquired, 1 if not available
#
# Try to acquire a lock without blocking.
#
# Usage: agent_trylock RESOURCE
# Example: agent_trylock "database" && echo "Got it!"
agent_trylock() {
    local resource="${1:-}"
    local name="${_MAINFRAME_AGENT_NAME:-$$}"

    if [[ -z "$resource" ]]; then
        _agent_log error "agent_trylock: resource name required"
        return 1
    fi

    local locks_dir="$_MAINFRAME_AGENT_BASE/_locks"
    mkdir -p "$locks_dir"

    local lockfile="$locks_dir/$resource.lock"

    # Use flock with -n (non-blocking)
    exec {_AGENT_LOCK_FD}>>"$lockfile"
    if flock -n "$_AGENT_LOCK_FD"; then
        printf '%s %s\n' "$name" "$(_agent_epoch)" > "$lockfile"
        _agent_log info "Agent '$name' acquired lock on '$resource'"
        return 0
    else
        exec {_AGENT_LOCK_FD}>&-
        unset _AGENT_LOCK_FD
        return 1
    fi
}

# =============================================================================
# WORK QUEUE: COMPLETION TRACKING
# =============================================================================

# @pre: Queue exists
# @post: Item pushed with task ID, returns ID
# @returns: 0 on success, prints task_id
#
# Push an item onto a work queue and return its task ID.
# This is an enhanced version that returns a trackable ID.
#
# Usage: task_id=$(agent_work_push_tracked QUEUE ITEM)
# Example: id=$(agent_work_push_tracked tasks '{"url":"http://example.com"}')
agent_work_push_tracked() {
    local queue_name="${1:-}"
    local item="${2:-}"

    if [[ -z "$queue_name" ]]; then
        _agent_log error "agent_work_push_tracked: queue name required"
        return 1
    fi

    if [[ -z "$item" ]]; then
        _agent_log error "agent_work_push_tracked: item required"
        return 1
    fi

    local queue_dir="$_MAINFRAME_AGENT_BASE/_queues/$queue_name"
    if [[ ! -d "$queue_dir" ]]; then
        _agent_log error "agent_work_push_tracked: queue '$queue_name' does not exist"
        return 1
    fi

    # Generate unique task ID
    local task_id
    task_id=$(printf '%s-%s-%s' "$(date +%s%N)" "$$" "$RANDOM")

    local item_file
    item_file="$queue_dir/$(_agent_msg_filename)"

    local timestamp
    timestamp="$(_agent_timestamp)"
    local producer="${_MAINFRAME_AGENT_NAME:-anonymous}"

    local json
    json=$(printf '{"task_id":"%s","producer":"%s","timestamp":"%s","item":"%s","status":"pending"}' \
        "$(_agent_json_escape "$task_id")" \
        "$(_agent_json_escape "$producer")" \
        "$timestamp" \
        "$(_agent_json_escape "$item")")

    printf '%s\n' "$json" > "$item_file"
    printf '%s\n' "$task_id"
    return 0
}

# @pre: Task was popped from queue
# @post: Task marked as complete in tracking file
# @returns: 0 on success
#
# Mark a task as complete.
#
# Usage: agent_work_complete QUEUE TASK_ID
# Example: agent_work_complete tasks "1234-5678"
agent_work_complete() {
    local queue_name="${1:-}"
    local task_id="${2:-}"

    if [[ -z "$queue_name" || -z "$task_id" ]]; then
        _agent_log error "agent_work_complete: queue name and task_id required"
        return 1
    fi

    local queue_dir="$_MAINFRAME_AGENT_BASE/_queues/$queue_name"
    local completed_file="$queue_dir/.completed"
    local inprogress_file="$queue_dir/.inprogress"
    local lockfile="$queue_dir/.track_lock"

    (
        flock 200

        # Remove from in-progress
        if [[ -f "$inprogress_file" ]]; then
            local tmp
            tmp=$(mktemp)
            grep -v "^$task_id " "$inprogress_file" > "$tmp" 2>/dev/null || true
            mv "$tmp" "$inprogress_file"
        fi

        # Add to completed
        printf '%s %s %s\n' "$task_id" "$(_agent_epoch)" "${_MAINFRAME_AGENT_NAME:-anonymous}" >> "$completed_file"
    ) 200>"$lockfile"

    return 0
}

# @pre: Task was popped from queue
# @post: Task marked as failed with reason
# @returns: 0 on success
#
# Mark a task as failed with a reason.
#
# Usage: agent_work_fail QUEUE TASK_ID REASON
# Example: agent_work_fail tasks "1234-5678" "Connection timeout"
agent_work_fail() {
    local queue_name="${1:-}"
    local task_id="${2:-}"
    local reason="${3:-unknown}"

    if [[ -z "$queue_name" || -z "$task_id" ]]; then
        _agent_log error "agent_work_fail: queue name and task_id required"
        return 1
    fi

    local queue_dir="$_MAINFRAME_AGENT_BASE/_queues/$queue_name"
    local failed_file="$queue_dir/.failed"
    local inprogress_file="$queue_dir/.inprogress"
    local lockfile="$queue_dir/.track_lock"

    (
        flock 200

        # Remove from in-progress
        if [[ -f "$inprogress_file" ]]; then
            local tmp
            tmp=$(mktemp)
            grep -v "^$task_id " "$inprogress_file" > "$tmp" 2>/dev/null || true
            mv "$tmp" "$inprogress_file"
        fi

        # Add to failed with reason
        printf '%s %s %s %s\n' "$task_id" "$(_agent_epoch)" "${_MAINFRAME_AGENT_NAME:-anonymous}" "$(_agent_json_escape "$reason")" >> "$failed_file"
    ) 200>"$lockfile"

    return 0
}

# @pre: Queue exists
# @post: Prints JSON with queue statistics
# @returns: 0 on success
#
# Get statistics for a work queue.
#
# Usage: agent_work_stats QUEUE
# Example: agent_work_stats tasks
agent_work_stats() {
    local queue_name="${1:-}"

    if [[ -z "$queue_name" ]]; then
        _agent_log error "agent_work_stats: queue name required"
        return 1
    fi

    local queue_dir="$_MAINFRAME_AGENT_BASE/_queues/$queue_name"
    if [[ ! -d "$queue_dir" ]]; then
        _agent_log error "agent_work_stats: queue '$queue_name' does not exist"
        return 1
    fi

    # Count pending items
    local pending=0
    local files
    files=( "$queue_dir"/msg_* )
    if [[ -e "${files[0]}" ]]; then
        pending=${#files[@]}
    fi

    # Count in-progress
    local in_progress=0
    if [[ -f "$queue_dir/.inprogress" ]]; then
        in_progress=$(wc -l < "$queue_dir/.inprogress")
    fi

    # Count completed
    local completed=0
    if [[ -f "$queue_dir/.completed" ]]; then
        completed=$(wc -l < "$queue_dir/.completed")
    fi

    # Count failed
    local failed=0
    if [[ -f "$queue_dir/.failed" ]]; then
        failed=$(wc -l < "$queue_dir/.failed")
    fi

    printf '{"queue":"%s","pending":%d,"in_progress":%d,"completed":%d,"failed":%d}\n' \
        "$(_agent_json_escape "$queue_name")" \
        "$pending" \
        "$in_progress" \
        "$completed" \
        "$failed"
}

# Enhanced work_pop that tracks in-progress status
# @pre: Queue exists
# @post: Oldest item consumed, marked as in-progress
# @returns: 0 if item popped, 1 if queue empty
#
# Pop the next item from a work queue with tracking.
#
# Usage: agent_work_pop_tracked QUEUE
# Example: item=$(agent_work_pop_tracked tasks)
agent_work_pop_tracked() {
    local queue_name="${1:-}"

    if [[ -z "$queue_name" ]]; then
        _agent_log error "agent_work_pop_tracked: queue name required"
        return 1
    fi

    local queue_dir="$_MAINFRAME_AGENT_BASE/_queues/$queue_name"
    if [[ ! -d "$queue_dir" ]]; then
        _agent_log error "agent_work_pop_tracked: queue '$queue_name' does not exist"
        return 1
    fi

    local lockfile="$queue_dir/.lock"
    local inprogress_file="$queue_dir/.inprogress"

    (
        flock 200 || exit 1

        local oldest=""
        local f
        for f in "$queue_dir"/msg_*; do
            [[ -e "$f" ]] || break
            oldest="$f"
            break
        done

        if [[ -n "$oldest" && -f "$oldest" ]]; then
            local content
            content=$(cat "$oldest")

            # Extract task_id if present, or use filename
            local task_id
            if [[ "$content" =~ \"task_id\":\"([^\"]+)\" ]]; then
                task_id="${BASH_REMATCH[1]}"
            else
                task_id="${oldest##*/}"
            fi

            # Mark as in-progress
            printf '%s %s %s\n' "$task_id" "$(_agent_epoch)" "${_MAINFRAME_AGENT_NAME:-anonymous}" >> "$inprogress_file"

            cat "$oldest"
            rm -f "$oldest"
            exit 0
        fi
        exit 1
    ) 200>"$lockfile"
}

# =============================================================================
# DISCOVERY: ADDITIONAL FUNCTIONS
# =============================================================================

# @pre: Agents registered with capabilities
# @post: Prints agent names that have the capability
# @returns: 0 if found, 1 if none found
#
# Find agents by capability (alias for agent_discover).
#
# Usage: agent_find_by_capability CAPABILITY
# Example: agent_find_by_capability "http"
agent_find_by_capability() {
    agent_discover "$@"
}

# @pre: At least one agent registered
# @post: Prints name of elected leader (deterministic for same group)
# @returns: 0 on success, 1 if no agents
#
# Simple leader election among registered agents.
# Uses lexicographic ordering for determinism.
#
# Usage: agent_elect_leader GROUP_NAME
# Example: leader=$(agent_elect_leader "workers")
agent_elect_leader() {
    local group="${1:-default}"

    local -a agents
    agent_list_v agents

    if [[ ${#agents[@]} -eq 0 ]]; then
        _agent_log error "agent_elect_leader: no agents registered"
        return 1
    fi

    # Sort agents and pick first (deterministic)
    local sorted
    sorted=$(printf '%s\n' "${agents[@]}" | sort | head -n1)

    printf '%s\n' "$sorted"
    return 0
}

# =============================================================================
# CLEANUP
# =============================================================================

# @pre: Base directory exists
# @post: All agent resources cleaned up
# @returns: 0 on success
#
# Clean up all agent resources (for testing/shutdown).
#
# Usage: agent_cleanup
agent_cleanup() {
    rm -rf "${_MAINFRAME_AGENT_BASE:?}/"* 2>/dev/null
    _MAINFRAME_AGENT_NAME=""
    _agent_log info "Cleaned up all agent resources"
    return 0
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# @pre: None
# @post: Agent base directory created
# @returns: 0 on success
#
# Initialize the agent subsystem (creates base directories).
#
# Usage: agent_init
agent_init() {
    mkdir -p "$_MAINFRAME_AGENT_BASE/_queues"
    mkdir -p "$_MAINFRAME_AGENT_BASE/_barriers"
    mkdir -p "$_MAINFRAME_AGENT_BASE/_signals"
    mkdir -p "$_MAINFRAME_AGENT_BASE/_topics"
    mkdir -p "$_MAINFRAME_AGENT_BASE/_locks"
    chmod 700 "$_MAINFRAME_AGENT_BASE" 2>/dev/null
    return 0
}

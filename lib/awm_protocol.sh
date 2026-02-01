#!/usr/bin/env bash
# AWM Agent Communication Protocol
# USOP v4 extensions for agent-to-agent messaging
# Version: 2.0.0

# Prevent double-loading
[[ -n "${_AWM_PROTOCOL_LOADED:-}" ]] && return 0
readonly _AWM_PROTOCOL_LOADED=1

# Load dependencies
# shellcheck source=./awm_storage.sh
source "${BASH_SOURCE%/*}/awm_storage.sh" 2>/dev/null || source "$(dirname "$0")/awm_storage.sh"
# shellcheck source=./awm_stream.sh
source "${BASH_SOURCE%/*}/awm_stream.sh" 2>/dev/null || source "$(dirname "$0")/awm_stream.sh"

# =============================================================================
# PROTOCOL CONSTANTS
# =============================================================================

readonly AWM_PROTOCOL_VERSION="4.0"

# Message types
readonly AWM_MSG_REQUEST="request"
readonly AWM_MSG_RESPONSE="response"
readonly AWM_MSG_DISCOVERY="discovery"
readonly AWM_MSG_HANDOFF="handoff"
readonly AWM_MSG_HEARTBEAT="heartbeat"
readonly AWM_MSG_BROADCAST="broadcast"
readonly AWM_MSG_ACK="ack"

# Priority levels
readonly AWM_PRIORITY_CRITICAL="critical"
readonly AWM_PRIORITY_HIGH="high"
readonly AWM_PRIORITY_NORMAL="normal"
readonly AWM_PRIORITY_LOW="low"

# Agent status
readonly AWM_STATUS_AVAILABLE="available"
readonly AWM_STATUS_BUSY="busy"
readonly AWM_STATUS_OFFLINE="offline"

# =============================================================================
# AGENT STATE
# =============================================================================

# Current agent identity
_AWM_AGENT_ID=""
_AWM_AGENT_CAPS=()
_AWM_CONTEXT_ID=""

# Message counter for unique IDs
_AWM_MSG_COUNTER=0

# =============================================================================
# AGENT REGISTRATION
# =============================================================================

# Register agent with capabilities
# Usage: awm_agent_register "agent_id" capability1 capability2 ...
# Returns: 0 on success
awm_agent_register() {
    local agent_id="$1"
    shift
    local capabilities=("$@")

    _AWM_AGENT_ID="$agent_id"
    _AWM_AGENT_CAPS=("${capabilities[@]}")

    # Create agent card
    local card
    card=$(jq -n \
        --arg id "$agent_id" \
        --argjson caps "$(printf '%s\n' "${capabilities[@]}" | jq -R . | jq -s .)" \
        --argjson budget "$(awm_budget_max)" \
        --arg status "$AWM_STATUS_AVAILABLE" \
        --arg registered "$(date -Iseconds)" \
        '{
            agent_id: $id,
            capabilities: $caps,
            context_budget: $budget,
            status: $status,
            registered_at: $registered,
            last_seen: $registered
        }')

    # Store agent card
    awm_store_set "agent:$agent_id" "$card"

    # Add to capability indexes
    for cap in "${capabilities[@]}"; do
        awm_store_push "cap:$cap" "$agent_id"
    done

    # Add to active agents list
    awm_store_set "agent:${agent_id}:active" "1" 300  # 5 min TTL

    echo "$agent_id"
}

# Update agent status
# Usage: awm_agent_status_set "status"
awm_agent_status_set() {
    local status="$1"

    [[ -z "$_AWM_AGENT_ID" ]] && return 1

    local card
    card=$(awm_store_get "agent:$_AWM_AGENT_ID")
    [[ -z "$card" ]] && return 1

    card=$(echo "$card" | jq \
        --arg status "$status" \
        --arg seen "$(date -Iseconds)" \
        '.status = $status | .last_seen = $seen')

    awm_store_set "agent:$_AWM_AGENT_ID" "$card"

    # Refresh active TTL
    awm_store_set "agent:${_AWM_AGENT_ID}:active" "1" 300
}

# Get agent card
# Usage: awm_agent_card "agent_id"
# Returns: JSON agent card
awm_agent_card() {
    local agent_id="${1:-$_AWM_AGENT_ID}"
    awm_store_get "agent:$agent_id"
}

# Get agent status
# Usage: awm_agent_status "agent_id"
# Returns: available|busy|offline
awm_agent_status() {
    local agent_id="${1:-$_AWM_AGENT_ID}"

    # Check if agent is active
    if ! awm_store_exists "agent:${agent_id}:active"; then
        echo "$AWM_STATUS_OFFLINE"
        return 0
    fi

    local card
    card=$(awm_store_get "agent:$agent_id")
    [[ -z "$card" ]] && echo "$AWM_STATUS_OFFLINE" && return 0

    echo "$card" | jq -r '.status'
}

# Find agents by capability
# Usage: awm_agent_find "capability"
# Returns: JSON array of agent_ids
awm_agent_find() {
    local capability="$1"

    local agents
    agents=$(awm_store_range "cap:$capability" 0 -1)

    # Filter to only active agents
    echo "$agents" | jq '[.[] | select(. != null)]'
}

# List all active agents
# Usage: awm_agent_list
# Returns: JSON array of agent cards
awm_agent_list() {
    local result='[]'

    # This is inefficient but works with file backend
    # Redis would use SCAN pattern matching
    local agents_dir="${_AWM_STORAGE_DIR:-$HOME/.mainframe/awm/store}/kv"

    if [[ -d "$agents_dir" ]]; then
        for file in "$agents_dir"/*; do
            [[ ! -f "$file" ]] && continue

            local content
            content=$(tail -n +2 "$file")

            # Check if it's an agent card
            if echo "$content" | jq -e '.agent_id' >/dev/null 2>&1; then
                local agent_id
                agent_id=$(echo "$content" | jq -r '.agent_id')

                # Check if active
                if awm_store_exists "agent:${agent_id}:active"; then
                    result=$(echo "$result" | jq --argjson card "$content" '. + [$card]')
                fi
            fi
        done
    fi

    echo "$result"
}

# Unregister agent
# Usage: awm_agent_unregister
awm_agent_unregister() {
    [[ -z "$_AWM_AGENT_ID" ]] && return 1

    # Remove from capability indexes
    for cap in "${_AWM_AGENT_CAPS[@]}"; do
        # Note: proper removal would need list operations
        # For now, just set status to offline
        :
    done

    # Remove active marker
    awm_store_delete "agent:${_AWM_AGENT_ID}:active"

    # Update status to offline
    awm_agent_status_set "$AWM_STATUS_OFFLINE"

    _AWM_AGENT_ID=""
    _AWM_AGENT_CAPS=()
}

# =============================================================================
# CONTEXT ID MANAGEMENT
# =============================================================================

# Generate new context ID
# Usage: awm_context_new
# Returns: context ID
awm_context_new() {
    local ts
    ts=$(date +%s%N)
    local rand
    rand=$(head -c 8 /dev/urandom | xxd -p)

    _AWM_CONTEXT_ID="ctx_${ts}_${rand}"
    echo "$_AWM_CONTEXT_ID"
}

# Get current context ID
# Usage: awm_context_get
awm_context_get() {
    [[ -z "$_AWM_CONTEXT_ID" ]] && awm_context_new >/dev/null
    echo "$_AWM_CONTEXT_ID"
}

# Set context ID (for continuing existing context)
# Usage: awm_context_set "context_id"
awm_context_set() {
    _AWM_CONTEXT_ID="$1"
}

# =============================================================================
# MESSAGE CREATION
# =============================================================================

# Generate unique message ID
_awm_msg_id() {
    ((_AWM_MSG_COUNTER++))
    echo "msg_${_AWM_AGENT_ID:-anon}_${_AWM_MSG_COUNTER}_$(date +%s%N | tail -c 8)"
}

# Create USOP v4 message envelope
# Usage: awm_message_create "type" "to" "payload" [priority] [ttl]
# Returns: JSON message
awm_message_create() {
    local msg_type="$1"
    local to="$2"
    local payload="$3"
    local priority="${4:-$AWM_PRIORITY_NORMAL}"
    local ttl="${5:-3600}"

    local msg_id
    msg_id=$(_awm_msg_id)

    local context_id
    context_id=$(awm_context_get)

    # Estimate payload tokens
    local tokens
    tokens=$(awm_estimate_tokens "$payload")

    jq -n \
        --arg usop "$AWM_PROTOCOL_VERSION" \
        --arg ts "$(date -Iseconds)" \
        --arg id "$msg_id" \
        --arg type "$msg_type" \
        --arg from "${_AWM_AGENT_ID:-anonymous}" \
        --arg to "$to" \
        --arg ctx "$context_id" \
        --argjson payload "$payload" \
        --arg priority "$priority" \
        --argjson ttl "$ttl" \
        --argjson tokens "$tokens" \
        '{
            usop: $usop,
            type: "agent_message",
            timestamp: $ts,
            message: {
                id: $id,
                type: $type,
                from: $from,
                to: $to,
                contextId: $ctx,
                payload: $payload,
                metadata: {
                    tokens_used: $tokens,
                    priority: $priority,
                    ttl: $ttl
                }
            }
        }'
}

# =============================================================================
# MESSAGE SENDING
# =============================================================================

# Send message to specific agent
# Usage: awm_send "target_agent" "type" "payload" [context_id]
# Returns: message ID
awm_send() {
    local target="$1"
    local msg_type="$2"
    local payload="$3"
    local context_id="${4:-}"

    [[ -n "$context_id" ]] && awm_context_set "$context_id"

    # Ensure payload is valid JSON
    if ! echo "$payload" | jq . >/dev/null 2>&1; then
        payload=$(jq -n --arg p "$payload" '{data: $p}')
    fi

    local message
    message=$(awm_message_create "$msg_type" "$target" "$payload")

    local msg_id
    msg_id=$(echo "$message" | jq -r '.message.id')

    # Store in target's inbox
    awm_store_push "inbox:$target" "$message"

    # Store in sender's outbox (for tracking)
    [[ -n "$_AWM_AGENT_ID" ]] && awm_store_push "outbox:$_AWM_AGENT_ID" "$message"

    # Publish via pubsub if available
    awm_store_publish "agent:$target" "$message"

    echo "$msg_id"
}

# Broadcast to all agents with capability
# Usage: awm_broadcast "capability" "type" "payload"
# Returns: count of agents messaged
awm_broadcast() {
    local capability="$1"
    local msg_type="$2"
    local payload="$3"

    local agents
    agents=$(awm_agent_find "$capability")

    local count=0
    echo "$agents" | jq -r '.[]' | while read -r agent_id; do
        [[ -z "$agent_id" ]] && continue
        [[ "$agent_id" == "$_AWM_AGENT_ID" ]] && continue  # Skip self

        awm_send "$agent_id" "$msg_type" "$payload"
        ((count++))
    done

    echo "$count"
}

# Send discovery to all agents
# Usage: awm_broadcast_discovery "discovery_text"
awm_broadcast_discovery() {
    local discovery="$1"

    local payload
    payload=$(jq -n \
        --arg d "$discovery" \
        --arg from "${_AWM_AGENT_ID:-anonymous}" \
        --arg ts "$(date -Iseconds)" \
        '{discovery: $d, from: $from, timestamp: $ts}')

    # Get all active agents
    local agents
    agents=$(awm_agent_list)

    echo "$agents" | jq -r '.[].agent_id' | while read -r agent_id; do
        [[ -z "$agent_id" ]] && continue
        [[ "$agent_id" == "$_AWM_AGENT_ID" ]] && continue

        awm_send "$agent_id" "$AWM_MSG_DISCOVERY" "$payload"
    done
}

# =============================================================================
# MESSAGE RECEIVING
# =============================================================================

# Receive next message (blocking with timeout)
# Usage: awm_receive [timeout_seconds]
# Returns: JSON message or empty
awm_receive() {
    local timeout="${1:-0}"
    local start
    start=$(date +%s)

    [[ -z "$_AWM_AGENT_ID" ]] && return 1

    while true; do
        # Check inbox
        local message
        message=$(awm_store_pop "inbox:$_AWM_AGENT_ID")

        if [[ -n "$message" ]]; then
            # Validate message structure
            if echo "$message" | jq -e '.message.id' >/dev/null 2>&1; then
                # Send ACK
                local from
                from=$(echo "$message" | jq -r '.message.from')
                local msg_id
                msg_id=$(echo "$message" | jq -r '.message.id')

                awm_send "$from" "$AWM_MSG_ACK" "{\"ack_for\":\"$msg_id\"}"

                echo "$message"
                return 0
            fi
        fi

        # Check timeout
        if [[ $timeout -gt 0 ]]; then
            local elapsed=$(($(date +%s) - start))
            [[ $elapsed -ge $timeout ]] && return 0
        fi

        sleep 0.1
    done
}

# Peek at next message without removing
# Usage: awm_peek
awm_peek() {
    [[ -z "$_AWM_AGENT_ID" ]] && return 1

    awm_store_range "inbox:$_AWM_AGENT_ID" 0 0 | jq -r '.[0] // empty'
}

# Get inbox count
# Usage: awm_inbox_count
awm_inbox_count() {
    [[ -z "$_AWM_AGENT_ID" ]] && echo 0 && return

    awm_store_len "inbox:$_AWM_AGENT_ID"
}

# Subscribe to messages (callback-based)
# Usage: awm_subscribe "type" callback_function
awm_subscribe() {
    local msg_type="$1"
    local callback="$2"

    [[ -z "$_AWM_AGENT_ID" ]] && return 1

    # Create wrapper that filters by type
    # shellcheck disable=SC2329  # Function used as callback via awm_store_subscribe
    _awm_subscription_handler() {
        local message="$1"
        local type
        type=$(echo "$message" | jq -r '.message.type // ""')

        if [[ "$type" == "$msg_type" ]] || [[ "$msg_type" == "*" ]]; then
            $callback "$message"
        fi
    }

    awm_store_subscribe "agent:$_AWM_AGENT_ID" _awm_subscription_handler
}

# =============================================================================
# HANDOFF PROTOCOL
# =============================================================================

# Prepare handoff package for sub-agent
# Usage: awm_handoff_prepare "target_agent" [max_tokens]
# Returns: JSON handoff package
awm_handoff_prepare() {
    local target="$1"
    local max_tokens="${2:-32000}"

    local context_id
    context_id=$(awm_context_get)

    # Gather discoveries from current session
    local discoveries='[]'
    local disc_list
    disc_list=$(awm_store_range "session:${_AWM_AGENT_ID}:discoveries" 0 -1)
    [[ -n "$disc_list" ]] && discoveries="$disc_list"

    # Gather key checkpoints (small ones only)
    local checkpoints='{}'
    # This would iterate session checkpoints and filter by size
    # Simplified for now

    # Create context summary
    local summary=""
    if awm_budget_fits 500; then
        summary="Agent handoff from $_AWM_AGENT_ID. Context established."
    fi

    # Calculate remaining budget for child
    local parent_used
    parent_used=$(awm_budget_used)
    local child_budget=$((max_tokens - parent_used / 4))  # Give child most of the budget

    local handoff
    handoff=$(jq -n \
        --arg type "$AWM_MSG_HANDOFF" \
        --arg ctx "$context_id" \
        --arg parent "${_AWM_AGENT_ID:-anonymous}" \
        --arg target "$target" \
        --argjson discoveries "$discoveries" \
        --argjson checkpoints "$checkpoints" \
        --arg summary "$summary" \
        --argjson budget "$child_budget" \
        --arg ts "$(date -Iseconds)" \
        '{
            type: $type,
            contextId: $ctx,
            parent_agent: $parent,
            target_agent: $target,
            discoveries: $discoveries,
            checkpoints: $checkpoints,
            context_summary: $summary,
            budget_remaining: $budget,
            created_at: $ts
        }')

    # Create memory pointers for large data
    local large_data
    large_data=$(awm_store_range "session:${_AWM_AGENT_ID}:large" 0 -1)
    if [[ -n "$large_data" ]] && [[ "$large_data" != "[]" ]]; then
        handoff=$(echo "$handoff" | jq --argjson ptrs "$large_data" '.pointers = $ptrs')
    fi

    echo "$handoff"
}

# Accept handoff and initialize
# Usage: awm_handoff_accept "handoff_json"
# Returns: 0 on success
awm_handoff_accept() {
    local handoff="$1"

    # Validate handoff structure
    if ! echo "$handoff" | jq -e '.contextId' >/dev/null 2>&1; then
        echo "Invalid handoff package" >&2
        return 1
    fi

    # Extract and set context
    local context_id
    context_id=$(echo "$handoff" | jq -r '.contextId')
    awm_context_set "$context_id"

    # Set budget
    local budget
    budget=$(echo "$handoff" | jq -r '.budget_remaining')
    [[ -n "$budget" ]] && MAINFRAME_TOKEN_BUDGET="$budget"
    awm_budget_init

    # Import discoveries
    local discoveries
    discoveries=$(echo "$handoff" | jq -r '.discoveries')
    if [[ -n "$discoveries" ]] && [[ "$discoveries" != "[]" ]]; then
        echo "$discoveries" | jq -c '.[]' | while read -r disc; do
            awm_store_push "session:${_AWM_AGENT_ID}:inherited_discoveries" "$disc"
        done
    fi

    # Store handoff reference
    awm_store_set "session:${_AWM_AGENT_ID}:handoff" "$handoff"

    # Notify parent
    local parent
    parent=$(echo "$handoff" | jq -r '.parent_agent')
    [[ -n "$parent" ]] && [[ "$parent" != "null" ]] && \
        awm_send "$parent" "$AWM_MSG_ACK" "{\"handoff_accepted\":true,\"agent\":\"$_AWM_AGENT_ID\"}"

    return 0
}

# Complete handoff and report back
# Usage: awm_handoff_complete "result_summary"
awm_handoff_complete() {
    local result="$1"

    # Get original handoff
    local handoff
    handoff=$(awm_store_get "session:${_AWM_AGENT_ID}:handoff")
    [[ -z "$handoff" ]] && return 1

    local parent
    parent=$(echo "$handoff" | jq -r '.parent_agent')

    # Gather discoveries made during this session
    local new_discoveries
    new_discoveries=$(awm_store_range "session:${_AWM_AGENT_ID}:discoveries" 0 -1)

    # Create completion message
    local completion
    completion=$(jq -n \
        --arg result "$result" \
        --argjson discoveries "${new_discoveries:-[]}" \
        --argjson tokens_used "$(awm_budget_used)" \
        --arg completed "$(date -Iseconds)" \
        '{
            status: "completed",
            result: $result,
            new_discoveries: $discoveries,
            tokens_used: $tokens_used,
            completed_at: $completed
        }')

    # Send to parent
    awm_send "$parent" "$AWM_MSG_RESPONSE" "$completion"

    return 0
}

# =============================================================================
# HEARTBEAT & HEALTH
# =============================================================================

# Send heartbeat
# Usage: awm_heartbeat
awm_heartbeat() {
    [[ -z "$_AWM_AGENT_ID" ]] && return 1

    # Refresh active TTL
    awm_store_set "agent:${_AWM_AGENT_ID}:active" "1" 300

    # Update last_seen
    local card
    card=$(awm_store_get "agent:$_AWM_AGENT_ID")
    [[ -z "$card" ]] && return 1

    card=$(echo "$card" | jq --arg seen "$(date -Iseconds)" '.last_seen = $seen')
    awm_store_set "agent:$_AWM_AGENT_ID" "$card"

    # Broadcast heartbeat to interested parties
    local stats
    stats=$(jq -n \
        --arg id "$_AWM_AGENT_ID" \
        --argjson budget "$(awm_budget_remaining)" \
        --argjson inbox "$(awm_inbox_count)" \
        --arg status "$(awm_agent_status)" \
        '{agent: $id, budget_remaining: $budget, inbox_count: $inbox, status: $status}')

    awm_store_publish "heartbeat" "$stats"
}

# Start heartbeat loop (background)
# Usage: awm_heartbeat_start [interval_seconds]
awm_heartbeat_start() {
    local interval="${1:-60}"

    while true; do
        awm_heartbeat
        sleep "$interval"
    done &

    echo $!  # Return PID
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Pretty print message
# Usage: awm_message_format "message_json"
awm_message_format() {
    local message="$1"

    echo "$message" | jq -r '
        "[\(.message.type | ascii_upcase)] \(.message.from) -> \(.message.to)",
        "  Context: \(.message.contextId)",
        "  Payload: \(.message.payload | tostring | .[0:100])...",
        "  Time: \(.timestamp)"
    '
}

# Get message history for context
# Usage: awm_message_history [context_id] [limit]
awm_message_history() {
    local context_id="${1:-$(awm_context_get)}"
    local limit="${2:-50}"

    # Search through outbox for context
    local outbox
    outbox=$(awm_store_range "outbox:$_AWM_AGENT_ID" 0 -1)

    echo "$outbox" | jq --arg ctx "$context_id" --argjson limit "$limit" '
        [.[] | select(.message.contextId == $ctx)] | .[-($limit):]
    '
}

# Clear agent inbox
# Usage: awm_inbox_clear
awm_inbox_clear() {
    [[ -z "$_AWM_AGENT_ID" ]] && return 1

    local count
    count=$(awm_inbox_count)

    for ((i = 0; i < count; i++)); do
        awm_store_pop "inbox:$_AWM_AGENT_ID" >/dev/null
    done

    echo "$count"
}

# =============================================================================
# CONVENIENCE WRAPPERS
# =============================================================================

# Quick request-response pattern
# Usage: awm_request "target" "action" "data" [timeout]
# Returns: response payload or empty
awm_request() {
    local target="$1"
    local action="$2"
    local data="$3"
    local timeout="${4:-30}"

    local payload
    payload=$(jq -n --arg action "$action" --argjson data "$data" '{action: $action, data: $data}')

    local msg_id
    msg_id=$(awm_send "$target" "$AWM_MSG_REQUEST" "$payload")

    # Wait for response
    local start
    start=$(date +%s)

    while true; do
        local response
        response=$(awm_receive 1)

        if [[ -n "$response" ]]; then
            local resp_type
            resp_type=$(echo "$response" | jq -r '.message.type')

            if [[ "$resp_type" == "$AWM_MSG_RESPONSE" ]]; then
                # Check if it's for our request
                local in_reply
                in_reply=$(echo "$response" | jq -r '.message.payload.in_reply_to // ""')

                if [[ "$in_reply" == "$msg_id" ]] || [[ -z "$in_reply" ]]; then
                    echo "$response" | jq '.message.payload'
                    return 0
                fi
            fi
        fi

        local elapsed=$(($(date +%s) - start))
        [[ $elapsed -ge $timeout ]] && return 1
    done
}

# Quick response to request
# Usage: awm_respond "original_message" "result_data"
awm_respond() {
    local original="$1"
    local result="$2"

    local from
    from=$(echo "$original" | jq -r '.message.from')
    local msg_id
    msg_id=$(echo "$original" | jq -r '.message.id')
    local context_id
    context_id=$(echo "$original" | jq -r '.message.contextId')

    local payload
    payload=$(jq -n \
        --arg reply "$msg_id" \
        --argjson result "$result" \
        '{in_reply_to: $reply, result: $result}')

    awm_send "$from" "$AWM_MSG_RESPONSE" "$payload" "$context_id"
}

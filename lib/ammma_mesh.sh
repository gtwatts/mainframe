#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/ammma_mesh.sh - AMMA Memory Mesh (Cross-Agent Sharing)
# =============================================================================
# Description: Distributed memory sharing protocol for multi-agent systems.
#              Enables cross-agent memory broadcast, query, and inheritance.
#
# Version: 3.0.0
# Requires: ammma.sh
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_AMMA_MESH_LOADED:-}" ]] && return 0
readonly _MAINFRAME_AMMA_MESH_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

_AMMA_MESH_LIB_DIR="${BASH_SOURCE[0]%/*}"

if [[ -z "${_MAINFRAME_AMMA_LOADED:-}" ]]; then
    [[ -f "${_AMMA_MESH_LIB_DIR}/ammma.sh" ]] && source "${_AMMA_MESH_LIB_DIR}/ammma.sh"
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

AMMA_MESH_ENABLED="${AMMA_MESH_ENABLED:-true}"
AMMA_MESH_BROKER_TYPE="${AMMA_MESH_BROKER_TYPE:-file}"  # file|redis|mqtt
AMMA_MESH_NAMESPACE="${AMMA_MESH_NAMESPACE:-default}"
AMMA_MESH_TTL="${AMMA_MESH_TTL:-86400}"  # 24 hours
AMMA_MESH_MAX_MESSAGE_SIZE="${AMMA_MESH_MAX_MESSAGE_SIZE:-65536}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

_AMMA_MESH_INITIALIZED=false
_AMMA_MESH_AGENT_ID=""
_AMMA_MESH_SUBSCRIPTIONS=()  # Array of subscribed topics

declare -gA _AMMA_MESH_CACHE=()  # Cache of received messages
declare -gi _AMMA_MESH_PUBLISH_COUNT=0
declare -gi _AMMA_MESH_RECEIVE_COUNT=0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_ammma_mesh_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "amma-mesh" "$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[amma-mesh] %s: %s\n' "$level" "$*" >&2
    fi
}

_ammma_mesh_timestamp() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    else
        date +%s
    fi
}

_ammma_mesh_gen_msg_id() {
    printf 'msg_%s_%s' "$(_ammma_mesh_timestamp)" "$RANDOM"
}

# =============================================================================
# MESH BROKER PATHS
# =============================================================================

_ammma_mesh_root() {
    printf '%s/mesh/%s' "$AMMA_ROOT" "$AMMA_MESH_NAMESPACE"
}

_ammma_mesh_ensure_dirs() {
    local mesh_root
    mesh_root=$(_ammma_mesh_root)
    mkdir -p "$mesh_root"/{inbox,outbox,topics,registry}
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# @pre: AMMA initialized
# @post: Connected to memory mesh
# @returns: 0 on success
#
# Initialize connection to memory mesh for cross-agent sharing.
#
# Usage: amma_mesh_init [--namespace NS] [--broker TYPE]
# Example: amma_mesh_init --namespace "project-x" --broker redis
ammma_mesh_init() {
    if [[ "$_AMMA_INITIALIZED" != "true" ]]; then
        _ammma_mesh_log error "AMMA not initialized"
        return 1
    fi
    
    if [[ "$AMMA_MESH_ENABLED" != "true" ]]; then
        _ammma_mesh_log warn "Memory mesh is disabled"
        return 1
    fi
    
    local namespace="$AMMA_MESH_NAMESPACE"
    local broker="$AMMA_MESH_BROKER_TYPE"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --namespace)
                namespace="$2"
                AMMA_MESH_NAMESPACE="$namespace"
                shift 2
                ;;
            --broker)
                broker="$2"
                AMMA_MESH_BROKER_TYPE="$broker"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    _AMMA_MESH_AGENT_ID="$_AMMA_AGENT_ID"
    
    # Initialize broker
    case "$broker" in
        file)
            _ammma_mesh_ensure_dirs
            # Register agent
            printf '%s' "$_AMMA_AGENT_ID" > "$(_ammma_mesh_root)/registry/$_AMMA_AGENT_ID.reg"
            ;;
        redis)
            # Check if redis-cli is available
            if ! command -v redis-cli &>/dev/null; then
                _ammma_mesh_log error "redis-cli not found, falling back to file"
                AMMA_MESH_BROKER_TYPE="file"
                _ammma_mesh_ensure_dirs
            fi
            ;;
        *)
            _ammma_mesh_log warn "Unknown broker type: $broker, using file"
            AMMA_MESH_BROKER_TYPE="file"
            _ammma_mesh_ensure_dirs
            ;;
    esac
    
    _AMMA_MESH_INITIALIZED=true
    
    _ammma_mesh_log info "Memory mesh initialized: namespace=$namespace, broker=$broker, agent=$_AMMA_AGENT_ID"
    
    printf '{"initialized":true,"agent_id":"%s","namespace":"%s","broker":"%s"}' \
        "$_AMMA_AGENT_ID" "$namespace" "$AMMA_MESH_BROKER_TYPE"
    
    return 0
}

# =============================================================================
# PUBLISH
# =============================================================================

# @pre: Mesh initialized
# @post: Memory published to mesh
# @returns: message ID on success
#
# Publish a memory to the mesh for other agents.
#
# Usage: amma_mesh_publish <memory_id> [--scope SCOPE] [--ttl SECONDS]
# Example: amma_mesh_publish "mem_abc123" --scope team
ammma_mesh_publish() {
    if [[ "$_AMMA_MESH_INITIALIZED" != "true" ]]; then
        _ammma_mesh_log error "Mesh not initialized"
        return 1
    fi
    
    local memory_id="$1"
    shift
    
    local scope="$AMMA_SCOPE_TEAM"
    local ttl="$AMMA_MESH_TTL"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scope)
                scope="$2"
                shift 2
                ;;
            --ttl)
                ttl="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Retrieve memory from local storage
    local memory
    memory=$(_amma_l2_get "$memory_id" 2>/dev/null)
    
    if [[ -z "$memory" ]]; then
        _ammma_mesh_log error "Memory $memory_id not found"
        return 1
    fi
    
    # Create mesh message
    local msg_id
    msg_id=$(_ammma_mesh_gen_msg_id)
    
    local timestamp
    timestamp=$(_ammma_mesh_timestamp)
    
    local message
    message=$(printf '{"_schema":"amma.v3.mesh.message","id":"%s","timestamp":%s,"publisher":"%s","scope":"%s","ttl":%s,"memory":%s}' \
        "$msg_id" \
        "$timestamp" \
        "$_AMMA_AGENT_ID" \
        "$scope" \
        "$ttl" \
        "$memory")
    
    # Publish via broker
    case "$AMMA_MESH_BROKER_TYPE" in
        file)
            _ammma_mesh_publish_file "$msg_id" "$message"
            ;;
        redis)
            _ammma_mesh_publish_redis "$msg_id" "$message"
            ;;
    esac
    
    _AMMA_MESH_PUBLISH_COUNT=$((_AMMA_MESH_PUBLISH_COUNT + 1))
    
    _ammma_mesh_log debug "Published memory $memory_id as $msg_id"
    printf '%s' "$msg_id"
}

# File-based publish
_ammma_mesh_publish_file() {
    local msg_id="$1"
    local message="$2"
    
    local mesh_root
    mesh_root=$(_ammma_mesh_root)
    
    # Write to outbox
    printf '%s' "$message" > "$mesh_root/outbox/$msg_id.json"
    
    # Also write to topic directories for subscribers
    local scope
    scope=$(echo "$message" | grep -o '"scope":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [[ -n "$scope" ]]; then
        mkdir -p "$mesh_root/topics/$scope"
        ln -sf "$mesh_root/outbox/$msg_id.json" "$mesh_root/topics/$scope/$msg_id.json" 2>/dev/null || \
            cp "$mesh_root/outbox/$msg_id.json" "$mesh_root/topics/$scope/$msg_id.json"
    fi
}

# Redis-based publish
_ammma_mesh_publish_redis() {
    local msg_id="$1"
    local message="$2"
    
    local channel="amma:mesh:$AMMA_MESH_NAMESPACE:broadcast"
    
    # Publish to Redis channel
    redis-cli PUBLISH "$channel" "$message" &>/dev/null || {
        _ammma_mesh_log warn "Redis publish failed, falling back to file"
        _ammma_mesh_publish_file "$msg_id" "$message"
    }
}

# =============================================================================
# QUERY
# =============================================================================

# @pre: Mesh initialized
# @post: Query results returned
# @returns: JSON array of matching memories
#
# Query the mesh for memories from other agents.
#
# Usage: amma_mesh_query "query" [--scope SCOPE] [--timeout MS]
# Example: amma_mesh_query "FastAPI error handling" --scope team
ammma_mesh_query() {
    if [[ "$_AMMA_MESH_INITIALIZED" != "true" ]]; then
        printf '[]'
        return 1
    fi
    
    local query="$1"
    shift
    
    local scope="$AMMA_SCOPE_TEAM"
    local timeout=5000  # milliseconds
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scope)
                scope="$2"
                shift 2
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    local results="[]"
    
    case "$AMMA_MESH_BROKER_TYPE" in
        file)
            results=$(_ammma_mesh_query_file "$query" "$scope")
            ;;
        redis)
            results=$(_ammma_mesh_query_redis "$query" "$scope" "$timeout")
            ;;
    esac
    
    printf '%s' "$results"
}

# File-based query
_ammma_mesh_query_file() {
    local query="$1"
    local scope="$2"
    
    local mesh_root
    mesh_root=$(_ammma_mesh_root)
    
    local results="["
    local first=true
    local count=0
    local max_results=10
    
    # Search in topic directory
    if [[ -d "$mesh_root/topics/$scope" ]]; then
        for msg_file in "$mesh_root/topics/$scope"/*.json; do
            [[ -f "$msg_file" ]] || continue
            [[ $count -ge $max_results ]] && break
            
            # Check if message matches query
            if grep -q "$query" "$msg_file" 2>/dev/null; then
                local message
                message=$(cat "$msg_file")
                
                # Check TTL
                local msg_time ttl
                msg_time=$(echo "$message" | grep -o '"timestamp":[0-9]*' | cut -d: -f2)
                ttl=$(echo "$message" | grep -o '"ttl":[0-9]*' | cut -d: -f2)
                
                local current_time
                current_time=$(_ammma_mesh_timestamp)
                
                if [[ $((current_time - msg_time)) -lt ${ttl:-86400} ]]; then
                    $first || results+=","
                    first=false
                    results+="$message"
                    ((count++))
                fi
            fi
        done
    fi
    
    results+="]"
    printf '%s' "$results"
}

# Redis-based query
_ammma_mesh_query_redis() {
    local query="$1"
    local scope="$2"
    local timeout="$3"
    
    # For Redis, we'd use a request-response pattern
    # This is a simplified implementation
    
    local request_id
    request_id=$(_ammma_mesh_gen_msg_id)
    
    local request_channel="amma:mesh:$AMMA_MESH_NAMESPACE:requests"
    local response_channel="amma:mesh:$AMMA_MESH_NAMESPACE:response:$_AMMA_AGENT_ID"
    
    # Subscribe to response channel
    # (In real implementation, this would be async)
    
    # For now, return empty
    printf '[]'
}

# =============================================================================
# SUBSCRIBE
# =============================================================================

# @pre: Mesh initialized
# @post: Subscription registered
# @returns: 0 on success
#
# Subscribe to a topic for async memory updates.
#
# Usage: amma_mesh_subscribe <topic> <callback_function>
# Example: amma_mesh_subscribe "discoveries" _handle_discovery
ammma_mesh_subscribe() {
    if [[ "$_AMMA_MESH_INITIALIZED" != "true" ]]; then
        _ammma_mesh_log error "Mesh not initialized"
        return 1
    fi
    
    local topic="$1"
    local callback="$2"
    
    if [[ -z "$topic" || -z "$callback" ]]; then
        _ammma_mesh_log error "Topic and callback required"
        return 1
    fi
    
    # Register subscription
    _AMMA_MESH_SUBSCRIPTIONS+=("$topic:$callback")
    
    # Create topic directory if using file broker
    if [[ "$AMMA_MESH_BROKER_TYPE" == "file" ]]; then
        local mesh_root
        mesh_root=$(_ammma_mesh_root)
        mkdir -p "$mesh_root/topics/$topic"
    fi
    
    _ammma_mesh_log debug "Subscribed to topic: $topic"
    return 0
}

# Poll for new messages (for file-based broker)
# @pre: Mesh initialized with subscriptions
# @post: Callbacks invoked for new messages
ammma_mesh_poll() {
    if [[ "$_AMMA_MESH_INITIALIZED" != "true" ]]; then
        return 1
    fi
    
    local mesh_root
    mesh_root=$(_ammma_mesh_root)
    
    # Process each subscription
    for subscription in "${_AMMA_MESH_SUBSCRIPTIONS[@]}"; do
        local topic="${subscription%%:*}"
        local callback="${subscription#*:}"
        
        if [[ -d "$mesh_root/topics/$topic" ]]; then
            for msg_file in "$mesh_root/topics/$topic"/*.json; do
                [[ -f "$msg_file" ]] || continue
                
                local msg_id
                msg_id=$(basename "$msg_file" .json)
                
                # Skip if already processed
                [[ -n "${_AMMA_MESH_CACHE[$msg_id]:-}" ]] && continue
                
                # Mark as processed
                _AMMA_MESH_CACHE[$msg_id]=1
                
                # Invoke callback
                local message
                message=$(cat "$msg_file")
                
                if declare -F "$callback" &>/dev/null; then
                    $callback "$message"
                fi
                
                _AMMA_MESH_RECEIVE_COUNT=$((_AMMA_MESH_RECEIVE_COUNT + 1))
            done
        fi
    done
}

# =============================================================================
# INHERITANCE
# =============================================================================

# @pre: Mesh initialized
# @post: Child agent context prepared
# @returns: JSON inheritance package
#
# Prepare memory package for child agent inheritance.
#
# Usage: amma_mesh_inherit_prepare [--filter TYPE] [--max-memories N]
# Example: ctx=$(amma_mesh_inherit_prepare --filter "high" --max-memories 50)
ammma_mesh_inherit_prepare() {
    if [[ "$_AMMA_INITIALIZED" != "true" ]]; then
        printf '{"error":"AMMA not initialized"}'
        return 1
    fi
    
    local min_importance="high"
    local max_memories=50
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --filter)
                min_importance="$2"
                shift 2
                ;;
            --max-memories)
                max_memories="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    local min_score
    min_score=$(_ammma_importance_to_score "$min_importance")
    
    # Collect memories for inheritance
    local memories="["
    local first=true
    local count=0
    
    # From L1 (immediate)
    for mem_id in "${!_AMMA_L1_MEMORY[@]}"; do
        [[ $count -ge $max_memories ]] && break
        
        local memory="${_AMMA_L1_MEMORY[$mem_id]}"
        local importance
        importance=$(echo "$memory" | grep -o '"importance":"[^"]*"' | head -1 | cut -d'"' -f4)
        local score
        score=$(_ammma_importance_to_score "$importance")
        
        if [[ $score -ge $min_score ]]; then
            $first || memories+=","
            first=false
            memories+="$memory"
            ((count++))
        fi
    done
    
    # From L2 (working)
    local l2_path
    l2_path=$(_amma_l2_path)
    for mem_file in "$l2_path/episodes"/*.json; do
        [[ -f "$mem_file" ]] || continue
        [[ $count -ge $max_memories ]] && break
        
        local memory
        memory=$(cat "$mem_file")
        
        local importance
        importance=$(echo "$memory" | grep -o '"importance":"[^"]*"' | head -1 | cut -d'"' -f4)
        local score
        score=$(_ammma_importance_to_score "$importance")
        
        if [[ $score -ge $min_score ]]; then
            $first || memories+=","
            first=false
            memories+="$memory"
            ((count++))
        fi
    done
    
    memories+="]"
    
    # Build inheritance package
    printf '{"parent_session":"%s","parent_agent":"%s","inherited_at":%s,"filter":"%s","memories":%s,"count":%d}' \
        "$_AMMA_SESSION_ID" \
        "$_AMMA_AGENT_ID" \
        "$(_ammma_mesh_timestamp)" \
        "$min_importance" \
        "$memories" \
        "$count"
}

# Apply inherited context to current session
# @pre: Mesh initialized
# @post: Inherited memories loaded into L1/L2
ammma_mesh_inherit_apply() {
    local inheritance_package="$1"
    
    if [[ -z "$inheritance_package" ]]; then
        _ammma_mesh_log error "Inheritance package required"
        return 1
    fi
    
    # Parse memories and load into L2
    # (Simplified implementation - assumes valid JSON)
    
    local l2_path
    l2_path=$(_amma_l2_path)
    mkdir -p "$l2_path/inherited"
    
    # Save inheritance package
    printf '%s' "$inheritance_package" > "$l2_path/inherited/parent_context.json"
    
    _ammma_mesh_log info "Applied inherited context from parent session"
    return 0
}

# =============================================================================
# STATISTICS
# =============================================================================

ammma_mesh_stats() {
    printf '{"initialized":%s,"agent_id":"%s","namespace":"%s","broker":"%s","published":%d,"received":%d,"subscriptions":%d}' \
        "$([[ "$_AMMA_MESH_INITIALIZED" == "true" ]] && echo 'true' || echo 'false')" \
        "$_AMMA_AGENT_ID" \
        "$AMMA_MESH_NAMESPACE" \
        "$AMMA_MESH_BROKER_TYPE" \
        "$_AMMA_MESH_PUBLISH_COUNT" \
        "$_AMMA_MESH_RECEIVE_COUNT" \
        "${#_AMMA_MESH_SUBSCRIPTIONS[@]}"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

AMMM_MESH_EXPORTS=(
    ammma_mesh_init
    ammma_mesh_publish
    ammma_mesh_query
    ammma_mesh_subscribe
    ammma_mesh_poll
    ammma_mesh_inherit_prepare
    ammma_mesh_inherit_apply
    ammma_mesh_stats
)

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${AMMM_MESH_EXPORTS[@]}" 2>/dev/null || true
fi

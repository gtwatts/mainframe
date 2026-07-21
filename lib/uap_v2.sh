#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2119,SC2120,SC2016,SC1003,SC2155,SC2181,SC2059,SC2206,SC2178

# =============================================================================
# MAINFRAME/lib/uap_v2.sh - Universal Agent Protocol (UAP) v2.0
# =============================================================================
# Description: High-performance RPC protocol for Mainframe V10 agent 
#              communication with streaming, load balancing, and security.
# Version: 2.0.0
# Protocol: UAP v2.0
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_UAP_V2_LOADED:-}" ]] && return 0
readonly _MAINFRAME_UAP_V2_LOADED=1


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
# DEPENDENCY LOADING
# =============================================================================

# Source required libraries
if [[ -z "${_MAINFRAME_JSON_LOADED:-}" ]]; then
    source "${BASH_SOURCE%/*}/json.sh"
fi

if [[ -z "${_MAINFRAME_SCHEMA_LOADED:-}" ]]; then
    source "${BASH_SOURCE%/*}/schema.sh" 2>/dev/null || true
fi

if [[ -z "${_MAINFRAME_RETRY_LOADED:-}" ]]; then
    source "${BASH_SOURCE%/*}/retry.sh" 2>/dev/null || true
fi

if [[ -z "${_MAINFRAME_ERROR_LOADED:-}" ]]; then
    source "${BASH_SOURCE%/*}/error.sh" 2>/dev/null || true
fi

# =============================================================================
# CONSTANTS
# =============================================================================

readonly UAP_V2_VERSION="2.0"

# Message types
readonly UAP_V2_TYPE_REQUEST="request"
readonly UAP_V2_TYPE_RESPONSE="response"
readonly UAP_V2_TYPE_STREAM="stream"
readonly UAP_V2_TYPE_HEARTBEAT="heartbeat"
readonly UAP_V2_TYPE_DISCOVER="discover"
readonly UAP_V2_TYPE_BROADCAST="broadcast"
readonly UAP_V2_TYPE_ERROR="error"
readonly UAP_V2_TYPE_CHUNK="chunk"
readonly UAP_V2_TYPE_STREAM_END="stream_end"

# Transport types
readonly UAP_V2_TRANSPORT_SOCKET="socket"
readonly UAP_V2_TRANSPORT_PIPE="pipe"
readonly UAP_V2_TRANSPORT_FILE="file"

# Default configuration
readonly UAP_V2_BASE_DIR="${MAINFRAME_UAP_V2_DIR:-${UAP_V2_BASE_DIR:-${HOME}/.mainframe/uap_v2}}"
readonly UAP_V2_AGENT_DIR="${UAP_V2_AGENT_DIR:-$UAP_V2_BASE_DIR/agents}"
readonly UAP_V2_SOCKET_DIR="${UAP_V2_SOCKET_DIR:-$UAP_V2_BASE_DIR/sockets}"
readonly UAP_V2_PIPE_DIR="${UAP_V2_PIPE_DIR:-$UAP_V2_BASE_DIR/pipes}"
readonly UAP_V2_MAILBOX_DIR="${UAP_V2_MAILBOX_DIR:-$UAP_V2_BASE_DIR/mailbox}"
readonly UAP_V2_SCHEMA_DIR="${UAP_V2_SCHEMA_DIR:-$UAP_V2_BASE_DIR/schemas}"
readonly UAP_V2_LOG_DIR="${UAP_V2_LOG_DIR:-$UAP_V2_BASE_DIR/logs}"

# Timeouts and intervals (in seconds)
readonly UAP_V2_DEFAULT_TIMEOUT=30
readonly UAP_V2_DEFAULT_RPC_TIMEOUT=60
readonly UAP_V2_HEARTBEAT_INTERVAL=30
readonly UAP_V2_PRUNE_AGE=90
readonly UAP_V2_STREAM_CHUNK_SIZE=8192
readonly UAP_V2_MAX_MESSAGE_SIZE=10485760  # 10MB

# =============================================================================
# GLOBAL STATE
# =============================================================================

declare -g UAP_V2_AGENT_NAME=""
declare -g UAP_V2_AGENT_PID=""
declare -ga UAP_V2_CAPABILITIES=()
declare -gA UAP_V2_SCHEMAS=()
declare -g UAP_V2_TOKEN=""
declare -g UAP_V2_HEARTBEAT_PID=""
declare -g UAP_V2_TRANSPORT="${UAP_V2_TRANSPORT:-}"
declare -gA UAP_V2_LISTENER_PIDS=()
declare -gA _UAP_V2_CALLBACKS=()
declare -gA _UAP_V2_STREAM_HANDLERS=()
declare -gi _UAP_V2_REQ_SEQ=0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Logging function
_uap_v2_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +%s)
    
    if [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[uap_v2][%s] %s: %s\n' "$timestamp" "$level" "$message" >&2
    fi
    
    if [[ -d "$UAP_V2_LOG_DIR" ]]; then
        printf '[%s] %s: %s\n' "$timestamp" "$level" "$message" >> "$UAP_V2_LOG_DIR/uap_v2.log" 2>/dev/null || true
    fi
}

# Generate UUID v4
_uap_v2_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]'
    else
        # Pure bash UUID v4-like generation
        local N B C="89ab"
        for ((N=0; N<16; ++N)); do
            B="$((RANDOM%256))"
            case "$N" in
                6) printf '4%x' "$((B%16))" ;;
                8) printf '%c%x' "${C:$RANDOM%${#C}:1}" "$((B%16))" ;;
                3|5|7|9) printf '%02x-' "$B" ;;
                *) printf '%02x' "$B" ;;
            esac
        done
        printf '\n'
    fi
}

# Generate ISO8601 timestamp
_uap_v2_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +%s
}

# Get current epoch seconds
_uap_v2_epoch() {
    local ts
    if printf -v ts '%(%s)T' -1 2>/dev/null && [[ -n "$ts" ]]; then
        printf '%s' "$ts"
    else
        date +%s
    fi
}

# Ensure directory structure exists
_uap_v2_ensure_dirs() {
    mkdir -p "$UAP_V2_AGENT_DIR" "$UAP_V2_SOCKET_DIR" "$UAP_V2_PIPE_DIR" \
             "$UAP_V2_MAILBOX_DIR" "$UAP_V2_SCHEMA_DIR" "$UAP_V2_LOG_DIR" 2>/dev/null || {
        _uap_v2_log "error" "Failed to create UAP v2 directories"
        return 1
    }
}

# Get agent socket path
_uap_v2_socket_path() {
    local agent="$1"
    printf '%s/%s.sock' "$UAP_V2_SOCKET_DIR" "$agent"
}

# Get agent pipe path
_uap_v2_pipe_path() {
    local agent="$1"
    printf '%s/%s.pipe' "$UAP_V2_PIPE_DIR" "$agent"
}

# Get agent mailbox path
_uap_v2_mailbox_path() {
    local agent="$1"
    printf '%s/%s' "$UAP_V2_MAILBOX_DIR" "$agent"
}

# Get agent registration file
_uap_v2_registry_file() {
    local agent="$1"
    printf '%s/%s.json' "$UAP_V2_AGENT_DIR" "$agent"
}

# Generate a unique message ID
_uap_v2_message_id() {
    _UAP_V2_REQ_SEQ=$((_UAP_V2_REQ_SEQ + 1))
    printf '%s-%s-%d' "$UAP_V2_AGENT_NAME" "$(_uap_v2_uuid | cut -d'-' -f1)" "$_UAP_V2_REQ_SEQ"
}

# Hash for message integrity
_uap_v2_hash() {
    local data="$1"
    if command -v sha256sum &>/dev/null; then
        printf '%s' "$data" | _mainframe_sha256 | cut -d' ' -f1 | cut -c1-16
    elif command -v shasum &>/dev/null; then
        printf '%s' "$data" | shasum -a 256 | cut -d' ' -f1 | cut -c1-16
    else
        # Fallback: simple checksum
        local sum=0
        local i
        for ((i=0; i<${#data}; i++)); do
            sum=$((sum + $(printf '%d' "'${data:i:1}")))
        done
        printf '%016x' "$sum"
    fi
}

# Detect best available transport
_uap_v2_detect_transport() {
    # Prefer Unix sockets for best performance
    if [[ -S /dev/null ]] || [[ -d /tmp ]]; then
        if command -v nc &>/dev/null || [[ -e /dev/tcp ]]; then
            printf '%s' "$UAP_V2_TRANSPORT_SOCKET"
            return 0
        fi
    fi
    
    # Fall back to named pipes
    if command -v mkfifo &>/dev/null; then
        printf '%s' "$UAP_V2_TRANSPORT_PIPE"
        return 0
    fi
    
    # Final fallback: file-based mailbox
    printf '%s' "$UAP_V2_TRANSPORT_FILE"
}

# =============================================================================
# MESSAGE ENCODING/DECODING
# =============================================================================

# Encode a UAP v2 message
# Usage: _uap_v2_encode_message --type TYPE --target TARGET --payload 'JSON' [options]
_uap_v2_encode_message() {
    local msg_type=""
    local target=""
    local payload="{}"
    local message_id=""
    local timeout=""
    local priority="0"
    local stream_id=""
    local chunk_num=""
    local total_chunks=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type) msg_type="$2"; shift 2 ;;
            --target) target="$2"; shift 2 ;;
            --payload) payload="$2"; shift 2 ;;
            --message-id) message_id="$2"; shift 2 ;;
            --timeout) timeout="$2"; shift 2 ;;
            --priority) priority="$2"; shift 2 ;;
            --stream-id) stream_id="$2"; shift 2 ;;
            --chunk-num) chunk_num="$2"; shift 2 ;;
            --total-chunks) total_chunks="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    [[ -z "$msg_type" ]] && { _uap_v2_log "error" "Message type required"; return 1; }
    
    # Generate message ID if not provided
    [[ -z "$message_id" ]] && message_id=$(_uap_v2_message_id)
    
    # Build source object
    local source_json
    source_json=$(json_object \
        "agent=$UAP_V2_AGENT_NAME" \
        "pid:number=$$" \
        "transport=${UAP_V2_TRANSPORT:-$(_uap_v2_detect_transport)}")
    
    # Build target object
    local target_json
    target_json=$(json_object \
        "agent=${target:-}" \
        "broadcast:bool=$([[ "$target" == "*" ]] && echo true || echo false)")
    
    # Build meta object
    local meta_parts=("timeout:number=${timeout:-$UAP_V2_DEFAULT_TIMEOUT}")
    meta_parts+=("priority:number=$priority")
    [[ -n "$stream_id" ]] && meta_parts+=("stream_id=$stream_id")
    [[ -n "$chunk_num" ]] && meta_parts+=("chunk_num:number=$chunk_num")
    [[ -n "$total_chunks" ]] && meta_parts+=("total_chunks:number=$total_chunks")
    
    local meta_json
    meta_json=$(json_object "${meta_parts[@]}")
    
    # Calculate integrity hash
    local integrity
    integrity=$(_uap_v2_hash "${msg_type}${message_id}${payload}")
    
    # Build complete message
    json_object \
        "uap_version:string=$UAP_V2_VERSION" \
        "message_id=$message_id" \
        "timestamp=$(_uap_v2_timestamp)" \
        "type=$msg_type" \
        "source:raw=$source_json" \
        "target:raw=$target_json" \
        "payload:raw=$payload" \
        "meta:raw=$meta_json" \
        "integrity=$integrity"
}

# Decode a UAP v2 message and extract fields
# Usage: _uap_v2_decode_message 'JSON_MESSAGE' [--get field]
_uap_v2_decode_message() {
    local json="$1"
    shift
    local get_field=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --get) get_field="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    # Validate JSON
    if ! json_valid "$json" 2>/dev/null; then
        _uap_v2_log "error" "Invalid JSON message"
        return 1
    fi
    
    # Verify UAP version
    local version
    version=$(json_get "$json" "uap_version" 2>/dev/null || echo "")
    if [[ -z "$version" ]]; then
        _uap_v2_log "error" "Not a UAP v2 message (missing uap_version)"
        return 1
    fi
    
    # Return specific field or full message
    if [[ -n "$get_field" ]]; then
        json_get "$json" "$get_field" 2>/dev/null || printf ''
    else
        printf '%s' "$json"
    fi
}

# Verify message integrity
# Usage: _uap_v2_verify_integrity 'JSON_MESSAGE'
_uap_v2_verify_integrity() {
    local json="$1"
    
    # Extract fields using regex (more reliable than json_get for this)
    local msg_type="" message_id="" payload="" integrity=""
    
    if [[ "$json" =~ \"type\":[[:space:]]*\"([^\"]+)\" ]]; then
        msg_type="${BASH_REMATCH[1]}"
    fi
    if [[ "$json" =~ \"message_id\":[[:space:]]*\"([^\"]+)\" ]]; then
        message_id="${BASH_REMATCH[1]}"
    fi
    if [[ "$json" =~ \"payload\":[[:space:]]*(\{[^}]*\}|\"[^\"]*\") ]]; then
        payload="${BASH_REMATCH[1]}"
    fi
    if [[ "$json" =~ \"integrity\":[[:space:]]*\"([^\"]+)\" ]]; then
        integrity="${BASH_REMATCH[1]}"
    fi
    
    [[ -z "$integrity" ]] && return 0  # No integrity check if not present
    
    local computed
    computed=$(_uap_v2_hash "${msg_type}${message_id}${payload}")
    
    [[ "$computed" == "$integrity" ]]
}

# =============================================================================
# TRANSPORT LAYER
# =============================================================================

# Send message via Unix domain socket
# Usage: _uap_v2_send_socket "agent" "message" [timeout]
_uap_v2_send_socket() {
    local agent="$1"
    local message="$2"
    local timeout="${3:-$UAP_V2_DEFAULT_TIMEOUT}"
    
    local socket_path
    socket_path=$(_uap_v2_socket_path "$agent")
    
    # Check if socket exists
    [[ -S "$socket_path" ]] || return 1
    
    # Send via netcat or bash /dev/tcp
    if command -v nc &>/dev/null; then
        printf '%s\n' "$message" | nc -U -w "$timeout" "$socket_path" 2>/dev/null
    elif [[ -e /dev/tcp ]]; then
        # Use bash built-in if possible
        printf '%s\n' "$message" > "$socket_path" 2>/dev/null
    else
        return 1
    fi
}

# Send message via named pipe
# Usage: _uap_v2_send_pipe "agent" "message" [timeout]
_uap_v2_send_pipe() {
    local agent="$1"
    local message="$2"
    local timeout="${3:-$UAP_V2_DEFAULT_TIMEOUT}"
    
    local pipe_path
    pipe_path=$(_uap_v2_pipe_path "$agent")
    
    # Check if pipe exists
    [[ -p "$pipe_path" ]] || return 1
    
    # Write with timeout using background process
    (
        printf '%s\n' "$message" > "$pipe_path" 2>/dev/null
    ) &
    local pid=$!
    
    # Wait with timeout
    local count=0
    while kill -0 "$pid" 2>/dev/null; do
        ((count++))
        if ((count >= timeout * 10)); then
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            return 1
        fi
        sleep 0.1
    done
    
    wait "$pid" 2>/dev/null
}

# Send message via file-based mailbox
# Usage: _uap_v2_send_file "agent" "message"
_uap_v2_send_file() {
    local agent="$1"
    local message="$2"
    
    local mailbox
    mailbox=$(_uap_v2_mailbox_path "$agent")
    
    # Create mailbox if needed
    mkdir -p "$mailbox" 2>/dev/null || return 1
    
    local msg_id
    msg_id=$(_uap_v2_uuid)
    local msg_file="$mailbox/${msg_id}.json"
    local tmp_file="$mailbox/.tmp.${msg_id}.$$"
    
    # Atomic write with lock if available
    if command -v flock &>/dev/null; then
        {
            flock -x 200 || return 1
            printf '%s' "$message" > "$tmp_file"
            mv -f "$tmp_file" "$msg_file"
            flock -u 200
        } 200>"$mailbox/.lock"
    else
        # Fallback: atomic write using temp file + mv
        printf '%s' "$message" > "$tmp_file"
        mv -f "$tmp_file" "$msg_file"
    fi
}

# Send message using best available transport
# Usage: _uap_v2_send "agent" "message" [transport] [timeout]
_uap_v2_send() {
    local agent="$1"
    local message="$2"
    local transport="${3:-${UAP_V2_TRANSPORT:-$(_uap_v2_detect_transport)}}"
    local timeout="${4:-$UAP_V2_DEFAULT_TIMEOUT}"
    
    case "$transport" in
        "$UAP_V2_TRANSPORT_SOCKET")
            if _uap_v2_send_socket "$agent" "$message" "$timeout"; then
                return 0
            fi
            ;&  # Fall through
        "$UAP_V2_TRANSPORT_PIPE")
            if _uap_v2_send_pipe "$agent" "$message" "$timeout"; then
                return 0
            fi
            ;&  # Fall through
        *)
            _uap_v2_send_file "$agent" "$message"
            ;;
    esac
}

# Receive message from transport
# Usage: _uap_v2_receive [transport] [timeout]
_uap_v2_receive() {
    local transport="${1:-${UAP_V2_TRANSPORT:-$(_uap_v2_detect_transport)}}"
    local timeout="${2:-0}"
    
    case "$transport" in
        "$UAP_V2_TRANSPORT_FILE")
            _uap_v2_receive_file "$timeout"
            ;;
        *)
            _uap_v2_receive_file "$timeout"  # Default to file-based
            ;;
    esac
}

# Receive message from file mailbox
# Usage: _uap_v2_receive_file [timeout]
_uap_v2_receive_file() {
    local timeout="${1:-0}"
    
    [[ -z "$UAP_V2_AGENT_NAME" ]] && return 1
    
    local mailbox
    mailbox=$(_uap_v2_mailbox_path "$UAP_V2_AGENT_NAME")
    [[ -d "$mailbox" ]] || return 1
    
    local deadline
    if (( timeout > 0 )); then
        deadline=$((SECONDS + timeout))
    else
        deadline=0
    fi
    
    while true; do
        # Get oldest message (sorted by filename = chronological)
        local msg_file
        msg_file=$(ls -1t "$mailbox"/*.json 2>/dev/null | grep -v '/\.tmp\.' | head -1)
        
        if [[ -n "$msg_file" && -f "$msg_file" ]]; then
            local message
            message=$(<"$msg_file")
            rm -f "$msg_file"
            printf '%s' "$message"
            return 0
        fi
        
        # Check timeout
        if (( timeout > 0 )); then
            (( SECONDS >= deadline )) && return 1
            sleep 0.05
        else
            return 1
        fi
    done
}

# =============================================================================
# REGISTRATION & DISCOVERY
# =============================================================================

# Register an agent with the UAP v2 protocol
# Usage: uap_v2_register "name" [--capabilities "cap1,cap2"] [--schema '{...}'] [--token "secret"]
uap_v2_register() {
    local name=""
    local capabilities=""
    local schema=""
    local token=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --capabilities) capabilities="$2"; shift 2 ;;
            --schema) schema="$2"; shift 2 ;;
            --token) token="$2"; shift 2 ;;
            --*)
                if [[ -z "$name" && "$1" != --* ]]; then
                    name="$1"
                    shift
                else
                    shift
                fi
                ;;
            *)
                if [[ -z "$name" ]]; then
                    name="$1"
                fi
                shift
                ;;
        esac
    done
    
    [[ -z "$name" ]] && { _uap_v2_log "error" "Agent name required"; return 1; }
    
    _uap_v2_ensure_dirs || return 1
    
    # Set agent identity
    UAP_V2_AGENT_NAME="$name"
    UAP_V2_AGENT_PID=$$
    UAP_V2_TOKEN="${token:-$(openssl rand -hex 16 2>/dev/null || date +%s%N | _mainframe_sha256 | head -c 32)}"
    UAP_V2_TRANSPORT="${UAP_V2_TRANSPORT:-$(_uap_v2_detect_transport)}"
    
    # Parse capabilities
    UAP_V2_CAPABILITIES=()
    if [[ -n "$capabilities" ]]; then
        IFS=',' read -ra UAP_V2_CAPABILITIES <<< "$capabilities"
    fi
    
    # Parse schemas if provided
    # Format: --schema '{"method":{"arg":"type"}}' (JSON object format)
    if [[ -n "$schema" ]]; then
        # Simple regex extraction for schema properties
        local schema_json="$schema"
        # Extract top-level keys and their object values
        while [[ "$schema_json" =~ \"([a-zA-Z_][a-zA-Z0-9_]*)\"[[:space:]]*:[[:space:]]*(\{[^}]+\}) ]]; do
            local method="${BASH_REMATCH[1]}"
            local method_schema="${BASH_REMATCH[2]}"
            UAP_V2_SCHEMAS["$method"]="$method_schema"
            # Remove this match and continue
            schema_json="${schema_json#*${BASH_REMATCH[0]}}"
        done
    fi
    
    # Create transport endpoints
    case "$UAP_V2_TRANSPORT" in
        "$UAP_V2_TRANSPORT_SOCKET")
            local socket_path
            socket_path=$(_uap_v2_socket_path "$name")
            # Create listener socket using netcat or socat
            if command -v nc &>/dev/null; then
                if [[ -n "${UAP_V2_LISTENER_PIDS[$name]:-}" ]]; then
                    kill "${UAP_V2_LISTENER_PIDS[$name]}" 2>/dev/null || true
                    wait "${UAP_V2_LISTENER_PIDS[$name]}" 2>/dev/null || true
                fi
                # Background listener
                (
                    while true; do
                        nc -lkU "$socket_path" 2>/dev/null | while read -r line; do
                            _uap_v2_handle_incoming "$line"
                        done
                    done
                ) </dev/null >/dev/null 2>&1 &
                UAP_V2_LISTENER_PIDS["$name"]=$!
            fi
            ;;
        "$UAP_V2_TRANSPORT_PIPE")
            local pipe_path
            pipe_path=$(_uap_v2_pipe_path "$name")
            [[ -p "$pipe_path" ]] || mkfifo "$pipe_path" 2>/dev/null
            ;;
    esac
    
    # Create mailbox
    mkdir -p "$UAP_V2_MAILBOX_DIR/$name" 2>/dev/null
    
    # Write registration
    local caps_json
    caps_json=$(json_array "${UAP_V2_CAPABILITIES[@]}")
    
    local schemas_json="{}"
    if [[ ${#UAP_V2_SCHEMAS[@]} -gt 0 ]]; then
        local schema_entries=()
        for method in "${!UAP_V2_SCHEMAS[@]}"; do
            schema_entries+=("$method:raw=${UAP_V2_SCHEMAS[$method]}")
        done
        schemas_json=$(json_object "${schema_entries[@]}")
    fi
    
    # Write registration file
    local reg_data
    reg_data=$(json_object \
        "name=$name" \
        "pid:number=$$" \
        "capabilities:raw=$caps_json" \
        "schemas:raw=$schemas_json" \
        "transport=$UAP_V2_TRANSPORT" \
        "token=$UAP_V2_TOKEN" \
        "registered=$(_uap_v2_timestamp)" \
        "last_heartbeat:number=$(_uap_v2_epoch)" \
        "status=active")
    printf '%s' "$reg_data" > "$UAP_V2_AGENT_DIR/${name}.json"
    
    # Start heartbeat (unless disabled)
    if [[ "${UAP_V2_NO_HEARTBEAT:-}" != "1" ]]; then
        _uap_v2_start_heartbeat
    fi
    
    _uap_v2_log "info" "Agent registered: $name (transport: $UAP_V2_TRANSPORT)"
    
    # Output registration info
    json_object \
        "success:bool=true" \
        "name=$name" \
        "transport=$UAP_V2_TRANSPORT" \
        "capabilities:raw=$caps_json"
}

# Unregister an agent
# Usage: uap_v2_unregister "name"
uap_v2_unregister() {
    local name="${1:-$UAP_V2_AGENT_NAME}"
    
    [[ -z "$name" ]] && { _uap_v2_log "error" "Agent name required"; return 1; }
    
    # Stop heartbeat
    if [[ "$name" == "$UAP_V2_AGENT_NAME" && -n "$UAP_V2_HEARTBEAT_PID" ]]; then
        kill "$UAP_V2_HEARTBEAT_PID" 2>/dev/null || true
        wait "$UAP_V2_HEARTBEAT_PID" 2>/dev/null || true
        UAP_V2_HEARTBEAT_PID=""
    fi

    if [[ -n "${UAP_V2_LISTENER_PIDS[$name]:-}" ]]; then
        kill "${UAP_V2_LISTENER_PIDS[$name]}" 2>/dev/null || true
        wait "${UAP_V2_LISTENER_PIDS[$name]}" 2>/dev/null || true
        unset "UAP_V2_LISTENER_PIDS[$name]"
    fi
    
    # Remove registration
    rm -f "$UAP_V2_AGENT_DIR/${name}.json"
    
    # Cleanup transport
    rm -f "$UAP_V2_SOCKET_DIR/${name}.sock"
    rm -f "$UAP_V2_PIPE_DIR/${name}.pipe"
    rm -rf "$UAP_V2_MAILBOX_DIR/$name"
    
    if [[ "$name" == "$UAP_V2_AGENT_NAME" ]]; then
        UAP_V2_AGENT_NAME=""
        UAP_V2_CAPABILITIES=()
        UAP_V2_SCHEMAS=()
    fi
    
    _uap_v2_log "info" "Agent unregistered: $name"
    
    json_object \
        "success:bool=true" \
        "name=$name" \
        "status=unregistered"
}

# Discover agents by capability pattern
# Usage: uap_v2_discover "capability_pattern"
uap_v2_discover() {
    local pattern="${1:-*}"
    
    _uap_v2_ensure_dirs || return 1
    
    local -a matches=()
    
    for reg_file in "$UAP_V2_AGENT_DIR"/*.json; do
        [[ -f "$reg_file" ]] || continue
        
        local agent_data
        agent_data=$(<"$reg_file")
        
        # Check if agent is alive
        local pid agent_name
        # Extract pid using regex
        if [[ "$agent_data" =~ \"pid\":[[:space:]]*([0-9]+) ]]; then
            pid="${BASH_REMATCH[1]}"
        fi
        # Extract name using regex
        if [[ "$agent_data" =~ \"name\":[[:space:]]*\"([^\"]+)\" ]]; then
            agent_name="${BASH_REMATCH[1]}"
        fi
        
        if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
            # Agent is dead, remove registration
            rm -f "$reg_file"
            continue
        fi
        
        # Match all pattern
        if [[ "$pattern" == "*" ]]; then
            matches+=("$agent_name")
            continue
        fi
        
        # Extract capabilities using regex
        local caps=""
        if [[ "$agent_data" =~ \"capabilities\":[[:space:]]*\[([^\]]*)\] ]]; then
            caps="${BASH_REMATCH[1]}"
        fi
        
        # Parse capabilities from JSON array
        local match_found=false
        if [[ -n "$caps" ]]; then
            # Split by comma and check each capability
            local IFS_OLD="$IFS"
            IFS=',' 
            local -a cap_list
            read -ra cap_list <<< "$caps"
            IFS="$IFS_OLD"
            
            for cap in "${cap_list[@]}"; do
                # Remove quotes and whitespace
                cap="${cap//\"/}"
                cap="${cap// /}"
                
                # Skip empty
                [[ -z "$cap" ]] && continue
                
                # Check for wildcard match
                if [[ "$pattern" == *"*"* ]]; then
                    # Convert pattern to regex
                    local regex="${pattern//\./\\.}"
                    regex="${regex//\*/.*}"
                    if [[ "$cap" =~ ^$regex$ ]]; then
                        match_found=true
                        break
                    fi
                elif [[ "$cap" == "$pattern" ]]; then
                    match_found=true
                    break
                fi
            done
        fi
        
        $match_found && matches+=("$agent_name")
    done
    
    # Output as JSON array
    json_array "${matches[@]}"
}

# List all registered agents
# Usage: uap_v2_list_agents [--format json|names]
uap_v2_list_agents() {
    local format="${1:-json}"
    
    _uap_v2_ensure_dirs || return 1
    
    local -a agents=()
    
    for reg_file in "$UAP_V2_AGENT_DIR"/*.json; do
        [[ -f "$reg_file" ]] || continue
        
        local agent_data
        agent_data=$(<"$reg_file")
        
        local agent_name pid status
        agent_name=$(json_get "$agent_data" "name" 2>/dev/null || echo "")
        pid=$(json_get "$agent_data" "pid" 2>/dev/null || echo "")
        status=$(json_get "$agent_data" "status" 2>/dev/null || echo "unknown")
        
        # Check if alive
        local online="false"
        [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && online="true"
        
        if [[ "$format" == "names" ]]; then
            printf '%s\n' "$agent_name"
        else
            agents+=("$(json_object \
                "name=$agent_name" \
                "online:bool=$online" \
                "status=$status")")
        fi
    done
    
    if [[ "$format" != "names" ]]; then
        local first=true
        printf '['
        for agent in "${agents[@]}"; do
            $first || printf ','
            first=false
            printf '%s' "$agent"
        done
        printf ']\n'
    fi
}

# =============================================================================
# RPC CALLS
# =============================================================================

# Synchronous RPC call
# Usage: uap_v2_call "agent" "method" --arg key=value --arg key2=value2 --timeout N
uap_v2_call() {
    local agent=""
    local method=""
    local -A args=()
    local timeout="$UAP_V2_DEFAULT_RPC_TIMEOUT"
    local retry_count=3
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --arg)
                local kv="$2"
                local key="${kv%%=*}"
                local value="${kv#*=}"
                args["$key"]="$value"
                shift 2
                ;;
            --timeout) timeout="$2"; shift 2 ;;
            --retry) retry_count="$2"; shift 2 ;;
            --*)
                if [[ -z "$agent" && "$1" != --* ]]; then
                    agent="$1"
                    shift
                elif [[ -z "$method" && "$1" != --* ]]; then
                    method="$1"
                    shift
                else
                    shift
                fi
                ;;
            *)
                if [[ -z "$agent" ]]; then
                    agent="$1"
                elif [[ -z "$method" ]]; then
                    method="$1"
                fi
                shift
                ;;
        esac
    done
    
    [[ -z "$agent" ]] && { _uap_v2_log "error" "Target agent required"; return 1; }
    [[ -z "$method" ]] && { _uap_v2_log "error" "Method name required"; return 1; }
    
    # Build args JSON
    local args_json="{}"
    if [[ ${#args[@]} -gt 0 ]]; then
        local arg_entries=()
        for key in "${!args[@]}"; do
            arg_entries+=("$key=${args[$key]}")
        done
        args_json=$(json_object "${arg_entries[@]}")
    fi
    
    # Build payload
    local payload
    payload=$(json_object \
        "method=$method" \
        "args:raw=$args_json" \
        "token=$UAP_V2_TOKEN")
    
    # Encode request
    local request
    request=$(_uap_v2_encode_message \
        --type "$UAP_V2_TYPE_REQUEST" \
        --target "$agent" \
        --payload "$payload" \
        --timeout "$timeout")
    
    local message_id
    message_id=$(json_get "$request" "message_id")
    
    # Send with retry
    local attempt=0
    while [[ $attempt -lt $retry_count ]]; do
        if _uap_v2_send "$agent" "$request"; then
            break
        fi
        ((attempt++))
        [[ $attempt -lt $retry_count ]] && sleep $((attempt * 2))
    done
    
    if [[ $attempt -ge $retry_count ]]; then
        _uap_v2_log "error" "Failed to send request to $agent after $retry_count attempts"
        return 1
    fi
    
    # Wait for response
    local deadline=$((SECONDS + timeout))
    while [[ $SECONDS -lt $deadline ]]; do
        local response
        response=$(_uap_v2_receive_file 1)
        
        if [[ -n "$response" ]]; then
            # Check if this is our response
            local resp_type resp_source resp_payload
            resp_type=$(json_get "$response" "type" 2>/dev/null || echo "")
            resp_source=$(json_get "$response" "source.agent" 2>/dev/null || echo "")
            
            if [[ "$resp_type" == "$UAP_V2_TYPE_RESPONSE" && "$resp_source" == "$agent" ]]; then
                # Verify integrity
                if ! _uap_v2_verify_integrity "$response"; then
                    _uap_v2_log "warn" "Response integrity check failed"
                fi
                
                resp_payload=$(json_get "$response" "payload" 2>/dev/null || echo "{}")
                printf '%s' "$resp_payload"
                return 0
            fi
        fi
        
        sleep 0.05
    done
    
    _uap_v2_log "error" "RPC call to $agent/$method timed out"
    return 1
}

# Asynchronous RPC call with callback
# Usage: uap_v2_call_async "agent" "method" --arg key=value --callback "function"
uap_v2_call_async() {
    local agent=""
    local method=""
    local -A args=()
    local callback=""
    local timeout="$UAP_V2_DEFAULT_RPC_TIMEOUT"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --arg)
                local kv="$2"
                local key="${kv%%=*}"
                local value="${kv#*=}"
                args["$key"]="$value"
                shift 2
                ;;
            --callback) callback="$2"; shift 2 ;;
            --timeout) timeout="$2"; shift 2 ;;
            --*)
                if [[ -z "$agent" && "$1" != --* ]]; then
                    agent="$1"
                    shift
                elif [[ -z "$method" && "$1" != --* ]]; then
                    method="$1"
                    shift
                else
                    shift
                fi
                ;;
            *)
                if [[ -z "$agent" ]]; then
                    agent="$1"
                elif [[ -z "$method" ]]; then
                    method="$1"
                fi
                shift
                ;;
        esac
    done
    
    [[ -z "$agent" ]] && { _uap_v2_log "error" "Target agent required"; return 1; }
    [[ -z "$method" ]] && { _uap_v2_log "error" "Method name required"; return 1; }
    [[ -z "$callback" ]] && { _uap_v2_log "error" "Callback function required"; return 1; }
    
    # Validate callback exists
    if ! declare -f "$callback" &>/dev/null; then
        _uap_v2_log "error" "Callback function '$callback' not found"
        return 1
    fi
    
    # Build args JSON
    local args_json="{}"
    if [[ ${#args[@]} -gt 0 ]]; then
        local arg_entries=()
        for key in "${!args[@]}"; do
            arg_entries+=("$key=${args[$key]}")
        done
        args_json=$(json_object "${arg_entries[@]}")
    fi
    
    # Build payload
    local payload
    payload=$(json_object \
        "method=$method" \
        "args:raw=$args_json" \
        "token=$UAP_V2_TOKEN" \
        "async:bool=true")
    
    # Encode request
    local request
    request=$(_uap_v2_encode_message \
        --type "$UAP_V2_TYPE_REQUEST" \
        --target "$agent" \
        --payload "$payload" \
        --timeout "$timeout")
    
    local message_id
    message_id=$(json_get "$request" "message_id")
    
    # Store callback
    _UAP_V2_CALLBACKS["$message_id"]="$callback"
    
    # Send
    if ! _uap_v2_send "$agent" "$request"; then
        _uap_v2_log "error" "Failed to send async request to $agent"
        unset "_UAP_V2_CALLBACKS[$message_id]"
        return 1
    fi
    
    # Start background listener for response
    (
        local deadline=$((SECONDS + timeout))
        while [[ $SECONDS -lt $deadline ]]; do
            local response
            response=$(_uap_v2_receive_file 1)
            
            if [[ -n "$response" ]]; then
                local resp_msg_id resp_payload
                resp_msg_id=$(json_get "$response" "message_id" 2>/dev/null || echo "")
                resp_payload=$(json_get "$response" "payload" 2>/dev/null || echo "{}")
                
                if [[ -n "${_UAP_V2_CALLBACKS[$resp_msg_id]:-}" ]]; then
                    local cb="${_UAP_V2_CALLBACKS[$resp_msg_id]}"
                    unset "_UAP_V2_CALLBACKS[$resp_msg_id]"
                    "$cb" "$resp_payload"
                    break
                fi
            fi
            
            sleep 0.1
        done
    ) &
    
    json_object \
        "success:bool=true" \
        "message_id=$message_id" \
        "status=pending"
}

# Get schema for an agent method
# Usage: uap_v2_schema "agent" "method"
uap_v2_schema() {
    local agent="$1"
    local method="$2"
    
    [[ -z "$agent" ]] && { _uap_v2_log "error" "Agent name required"; return 1; }
    [[ -z "$method" ]] && { _uap_v2_log "error" "Method name required"; return 1; }
    
    local reg_file
    reg_file=$(_uap_v2_registry_file "$agent")
    
    if [[ ! -f "$reg_file" ]]; then
        _uap_v2_log "error" "Agent '$agent' not found"
        return 1
    fi
    
    local agent_data
    agent_data=$(<"$reg_file")
    
    # Extract schema for method using regex
    local schema_json=""
    if [[ "$agent_data" =~ \"$method\"[[:space:]]*:[[:space:]]*(\{[^}]+\}) ]]; then
        schema_json="${BASH_REMATCH[1]}"
    fi
    
    if [[ -z "$schema_json" ]]; then
        printf '{}\n'
        return 1
    fi
    
    printf '%s' "$schema_json"
}

# =============================================================================
# STREAMING
# =============================================================================

# Stream data to/from an agent
# Usage: uap_v2_stream "agent" "method" --on_chunk "handler" --arg key=value
uap_v2_stream() {
    local agent=""
    local method=""
    local on_chunk=""
    local -A args=()
    local stream_id
    stream_id=$(_uap_v2_uuid)
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --arg)
                local kv="$2"
                local key="${kv%%=*}"
                local value="${kv#*=}"
                args["$key"]="$value"
                shift 2
                ;;
            --on_chunk) on_chunk="$2"; shift 2 ;;
            --stream-id) stream_id="$2"; shift 2 ;;
            --*)
                if [[ -z "$agent" && "$1" != --* ]]; then
                    agent="$1"
                    shift
                elif [[ -z "$method" && "$1" != --* ]]; then
                    method="$1"
                    shift
                else
                    shift
                fi
                ;;
            *)
                if [[ -z "$agent" ]]; then
                    agent="$1"
                elif [[ -z "$method" ]]; then
                    method="$1"
                fi
                shift
                ;;
        esac
    done
    
    [[ -z "$agent" ]] && { _uap_v2_log "error" "Target agent required"; return 1; }
    [[ -z "$method" ]] && { _uap_v2_log "error" "Method name required"; return 1; }
    [[ -z "$on_chunk" ]] && { _uap_v2_log "error" "Chunk handler required"; return 1; }
    
    # Validate handler exists
    if ! declare -f "$on_chunk" &>/dev/null; then
        _uap_v2_log "error" "Chunk handler '$on_chunk' not found"
        return 1
    fi
    
    # Build args
    local args_json="{}"
    if [[ ${#args[@]} -gt 0 ]]; then
        local arg_entries=()
        for key in "${!args[@]}"; do
            arg_entries+=("$key=${args[$key]}")
        done
        args_json=$(json_object "${arg_entries[@]}")
    fi
    
    # Build payload
    local payload
    payload=$(json_object \
        "method=$method" \
        "args:raw=$args_json" \
        "token=$UAP_V2_TOKEN" \
        "stream_id=$stream_id" \
        "streaming:bool=true")
    
    # Encode stream request
    local request
    request=$(_uap_v2_encode_message \
        --type "$UAP_V2_TYPE_STREAM" \
        --target "$agent" \
        --payload "$payload" \
        --stream-id "$stream_id")
    
    # Send
    if ! _uap_v2_send "$agent" "$request"; then
        _uap_v2_log "error" "Failed to initiate stream to $agent"
        return 1
    fi
    
    # Store handler
    _UAP_V2_STREAM_HANDLERS["$stream_id"]="$on_chunk"
    
    # Listen for chunks
    local chunks_received=0
    local stream_complete=false
    local deadline=$((SECONDS + 300))  # 5 minute default timeout
    
    while ! $stream_complete && [[ $SECONDS -lt $deadline ]]; do
        local response
        response=$(_uap_v2_receive_file 1)
        
        if [[ -n "$response" ]]; then
            local resp_type resp_stream_id resp_payload
            resp_type=$(json_get "$response" "type" 2>/dev/null || echo "")
            resp_stream_id=$(json_get "$response" "meta.stream_id" 2>/dev/null || echo "")
            resp_payload=$(json_get "$response" "payload" 2>/dev/null || echo "")
            
            if [[ "$resp_stream_id" == "$stream_id" ]]; then
                case "$resp_type" in
                    "$UAP_V2_TYPE_CHUNK")
                        local chunk_data
                        chunk_data=$(json_get "$response" "payload.chunk" 2>/dev/null || echo "")
                        local chunk_num
                        chunk_num=$(json_get "$response" "meta.chunk_num" 2>/dev/null || echo "$chunks_received")
                        
                        # Call handler with chunk
                        "$on_chunk" "$chunk_data" "$chunk_num"
                        ((chunks_received++))
                        ;;
                    "$UAP_V2_TYPE_STREAM_END")
                        stream_complete=true
                        ;;
                    "$UAP_V2_TYPE_ERROR")
                        _uap_v2_log "error" "Stream error: $resp_payload"
                        unset "_UAP_V2_STREAM_HANDLERS[$stream_id]"
                        return 1
                        ;;
                esac
            fi
        fi
        
        sleep 0.01
    done
    
    unset "_UAP_V2_STREAM_HANDLERS[$stream_id]"
    
    if ! $stream_complete; then
        _uap_v2_log "warn" "Stream timed out, received $chunks_received chunks"
        return 1
    fi
    
    json_object \
        "success:bool=true" \
        "stream_id=$stream_id" \
        "chunks_received:number=$chunks_received"
}

# Broadcast a message to multiple agents
# Usage: uap_v2_broadcast "message" --filter "capability_pattern"
uap_v2_broadcast() {
    local message=""
    local filter="*"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --filter) filter="$2"; shift 2 ;;
            --*)
                if [[ -z "$message" && "$1" != --* ]]; then
                    message="$1"
                    shift
                else
                    shift
                fi
                ;;
            *)
                if [[ -z "$message" ]]; then
                    message="$1"
                fi
                shift
                ;;
        esac
    done
    
    [[ -z "$message" ]] && { _uap_v2_log "error" "Message required"; return 1; }
    
    # Discover matching agents
    local targets
    targets=$(uap_v2_discover "$filter")
    
    # Parse targets
    local -a agent_list=()
    if [[ "$targets" == "["* ]]; then
        # JSON array format
        targets="${targets#[}"
        targets="${targets%]}"
        IFS=',' read -ra agent_list <<< "$targets"
    else
        # Space-separated
        read -ra agent_list <<< "$targets"
    fi
    
    local sent=0
    local payload
    payload=$(json_object \
        "message=$message" \
        "broadcast:bool=true" \
        "token=$UAP_V2_TOKEN")
    
    for agent in "${agent_list[@]}"; do
        # Clean up quotes if present
        agent="${agent//\"/}"
        agent="${agent// /}"
        
        [[ "$agent" == "$UAP_V2_AGENT_NAME" ]] && continue
        
        local request
        request=$(_uap_v2_encode_message \
            --type "$UAP_V2_TYPE_BROADCAST" \
            --target "$agent" \
            --payload "$payload")
        
        if _uap_v2_send "$agent" "$request" 2>/dev/null; then
            ((sent++))
        fi
    done
    
    json_object \
        "success:bool=true" \
        "sent:number=$sent" \
        "filter=$filter"
}

# =============================================================================
# SERVICE HEALTH
# =============================================================================

# Send heartbeat for an agent
# Usage: uap_v2_heartbeat ["agent"]
uap_v2_heartbeat() {
    local agent="${1:-$UAP_V2_AGENT_NAME}"
    
    [[ -z "$agent" ]] && { _uap_v2_log "error" "Agent name required"; return 1; }
    
    local reg_file
    reg_file=$(_uap_v2_registry_file "$agent")
    
    if [[ ! -f "$reg_file" ]]; then
        _uap_v2_log "error" "Agent '$agent' not registered"
        return 1
    fi
    
    # Update heartbeat timestamp
    local agent_data
    agent_data=$(<"$reg_file")
    
    # Update just the heartbeat field
    local new_data
    new_data=$(printf '%s' "$agent_data" | sed "s/\"last_heartbeat\":[0-9]*/\"last_heartbeat\":$(_uap_v2_epoch)/")
    
    printf '%s' "$new_data" > "$reg_file"
    
    # Send heartbeat message to all agents
    local payload
    payload=$(json_object \
        "agent=$agent" \
        "timestamp=$(_uap_v2_timestamp)" \
        "pid:number=$$")
    
    local heartbeat_msg
    heartbeat_msg=$(_uap_v2_encode_message \
        --type "$UAP_V2_TYPE_HEARTBEAT" \
        --target "*" \
        --payload "$payload")
    
    # Don't wait for response
    for reg in "$UAP_V2_AGENT_DIR"/*.json; do
        [[ -f "$reg" ]] || continue
        local target_agent
        target_agent=$(json_get "$(<"$reg")" "name" 2>/dev/null || echo "")
        [[ "$target_agent" == "$agent" ]] && continue
        _uap_v2_send "$target_agent" "$heartbeat_msg" 2>/dev/null || true
    done
    
    return 0
}

# Get status of an agent
# Usage: uap_v2_status ["agent"]
uap_v2_status() {
    local agent="${1:-$UAP_V2_AGENT_NAME}"
    
    [[ -z "$agent" ]] && { _uap_v2_log "error" "Agent name required"; return 1; }
    
    local reg_file
    reg_file=$(_uap_v2_registry_file "$agent")
    
    if [[ ! -f "$reg_file" ]]; then
        json_object \
            "name=$agent" \
            "online:bool=false" \
            "status=not_found"
        return 1
    fi
    
    local agent_data
    agent_data=$(<"$reg_file")
    
    # Extract fields using regex for reliability
    local pid="" last_heartbeat="0" caps="[]" transport="unknown"
    
    if [[ "$agent_data" =~ \"pid\":[[:space:]]*([0-9]+) ]]; then
        pid="${BASH_REMATCH[1]}"
    fi
    if [[ "$agent_data" =~ \"last_heartbeat\":[[:space:]]*([0-9]+) ]]; then
        last_heartbeat="${BASH_REMATCH[1]}"
    fi
    if [[ "$agent_data" =~ \"transport\":[[:space:]]*\"([^\"]+)\" ]]; then
        transport="${BASH_REMATCH[1]}"
    fi
    if [[ "$agent_data" =~ \"capabilities\":[[:space:]]*(\[[^\]]*\]) ]]; then
        caps="${BASH_REMATCH[1]}"
    fi
    
    # Check if alive
    local online="false"
    local now
    now=$(_uap_v2_epoch)
    
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        # Check heartbeat freshness
        local age=$((now - last_heartbeat))
        if [[ $age -lt $UAP_V2_PRUNE_AGE ]]; then
            online="true"
        fi
    fi
    
    json_object \
        "name=$agent" \
        "online:bool=$online" \
        "transport=$transport" \
        "capabilities:raw=$caps" \
        "pid:number=${pid:-0}" \
        "last_heartbeat:number=$last_heartbeat"
}

# Perform health check on the UAP v2 system
# Usage: uap_v2_health_check [--verbose]
uap_v2_health_check() {
    local verbose=false
    [[ "${1:-}" == "--verbose" ]] && verbose=true
    
    local -a issues=()
    local healthy=true
    
    # Check directories
    if [[ ! -d "$UAP_V2_BASE_DIR" ]]; then
        issues+=("Base directory missing: $UAP_V2_BASE_DIR")
        healthy=false
    fi
    
    # Check transport availability
    local transport
    transport=$(_uap_v2_detect_transport)
    
    case "$transport" in
        "$UAP_V2_TRANSPORT_SOCKET")
            if ! command -v nc &>/dev/null && [[ ! -e /dev/tcp ]]; then
                issues+=("Socket transport unavailable")
            fi
            ;;
        "$UAP_V2_TRANSPORT_PIPE")
            if ! command -v mkfifo &>/dev/null; then
                issues+=("Pipe transport unavailable")
            fi
            ;;
    esac
    
    # Check agent count
    local agent_count=0
    if [[ -d "$UAP_V2_AGENT_DIR" ]]; then
        for f in "$UAP_V2_AGENT_DIR"/*.json; do
            [[ -f "$f" ]] && ((agent_count++))
        done
    fi
    
    # Prune dead agents
    if [[ -d "$UAP_V2_AGENT_DIR" ]]; then
        local pruned=0
        for reg_file in "$UAP_V2_AGENT_DIR"/*.json; do
            [[ -f "$reg_file" ]] || continue
            
            local pid last_heartbeat
            pid=$(json_get "$(<"$reg_file")" "pid" 2>/dev/null || echo "")
            last_heartbeat=$(json_get "$(<"$reg_file")" "last_heartbeat" 2>/dev/null || echo "0")
            
            if [[ -n "$pid" ]]; then
                if ! kill -0 "$pid" 2>/dev/null; then
                    rm -f "$reg_file"
                    ((pruned++))
                else
                    local age
                    age=$(($(_uap_v2_epoch) - last_heartbeat))
                    if [[ $age -gt $UAP_V2_PRUNE_AGE ]]; then
                        rm -f "$reg_file"
                        ((pruned++))
                    fi
                fi
            fi
        done
        
        if [[ $pruned -gt 0 ]] && $verbose; then
            issues+=("Pruned $pruned dead agents")
        fi
    fi
    
    # Build result
    local status="healthy"
    $healthy || status="degraded"
    
    local issues_json="[]"
    if [[ ${#issues[@]} -gt 0 ]]; then
        issues_json=$(json_array "${issues[@]}")
    fi
    
    json_object \
        "status=$status" \
        "healthy:bool=$healthy" \
        "transport=$transport" \
        "agent_count:number=$agent_count" \
        "issues:raw=$issues_json"
    
    $healthy
}

# =============================================================================
# INTERNAL HANDLERS
# =============================================================================

# Handle incoming messages (for background listener)
_uap_v2_handle_incoming() {
    local message="$1"
    
    # Parse message
    local msg_type msg_source msg_payload
    msg_type=$(json_get "$message" "type" 2>/dev/null || echo "")
    msg_source=$(json_get "$message" "source.agent" 2>/dev/null || echo "")
    msg_payload=$(json_get "$message" "payload" 2>/dev/null || echo "")
    
    case "$msg_type" in
        "$UAP_V2_TYPE_REQUEST")
            _uap_v2_handle_request "$message"
            ;;
        "$UAP_V2_TYPE_HEARTBEAT")
            # Update peer heartbeat
            ;;
        "$UAP_V2_TYPE_BROADCAST")
            # Handle broadcast
            ;;
    esac
}

# Handle RPC request
_uap_v2_handle_request() {
    local message="$1"
    
    local msg_id msg_source msg_payload method
    msg_id=$(json_get "$message" "message_id" 2>/dev/null || echo "")
    msg_source=$(json_get "$message" "source.agent" 2>/dev/null || echo "")
    msg_payload=$(json_get "$message" "payload" 2>/dev/null || echo "")
    method=$(json_get "$msg_payload" "method" 2>/dev/null || echo "")
    
    # Build response
    local response_payload
    response_payload=$(json_object \
        "success:bool=false" \
        "error=Method not implemented" \
        "method=$method")
    
    local response
    response=$(_uap_v2_encode_message \
        --type "$UAP_V2_TYPE_RESPONSE" \
        --target "$msg_source" \
        --payload "$response_payload" \
        --message-id "$msg_id")
    
    _uap_v2_send "$msg_source" "$response"
}

# Start background heartbeat
_uap_v2_start_heartbeat() {
    # Stop existing heartbeat
    if [[ -n "$UAP_V2_HEARTBEAT_PID" ]]; then
        kill "$UAP_V2_HEARTBEAT_PID" 2>/dev/null || true
        wait "$UAP_V2_HEARTBEAT_PID" 2>/dev/null || true
    fi
    
    # Start new heartbeat in background
    (
        while [[ -n "$UAP_V2_AGENT_NAME" ]]; do
            uap_v2_heartbeat "$UAP_V2_AGENT_NAME" 2>/dev/null || true
            sleep "$UAP_V2_HEARTBEAT_INTERVAL"
        done
    ) </dev/null >/dev/null 2>&1 &
    
    UAP_V2_HEARTBEAT_PID=$!
    _uap_v2_log "debug" "Heartbeat started (PID: $UAP_V2_HEARTBEAT_PID)"
}

# =============================================================================
# CLEANUP
# =============================================================================

# Cleanup on exit
_uap_v2_cleanup() {
    if [[ -n "$UAP_V2_AGENT_NAME" ]]; then
        uap_v2_unregister "$UAP_V2_AGENT_NAME" >/dev/null 2>&1 || true
    fi
}

# Register cleanup trap
if declare -F _mainframe_add_exit_trap >/dev/null 2>&1; then
    _mainframe_add_exit_trap "_uap_v2_cleanup"
else
    trap '_uap_v2_cleanup' EXIT
fi

# =============================================================================
# EXPORTS
# =============================================================================

export UAP_V2_VERSION
export UAP_V2_TYPE_REQUEST UAP_V2_TYPE_RESPONSE UAP_V2_TYPE_STREAM
export UAP_V2_TYPE_HEARTBEAT UAP_V2_TYPE_DISCOVER UAP_V2_TYPE_BROADCAST
export UAP_V2_TYPE_ERROR UAP_V2_TYPE_CHUNK UAP_V2_TYPE_STREAM_END
export UAP_V2_TRANSPORT_SOCKET UAP_V2_TRANSPORT_PIPE UAP_V2_TRANSPORT_FILE

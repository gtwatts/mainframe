#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2119,SC2120,SC2016,SC1003,SC2155,SC2181,SC2059,SC2206

# =============================================================================
# MAINFRAME/lib/uap.sh - Universal Agent Protocol (UAP) v1.0
# =============================================================================
# Description: Standardized messaging protocol for cross-platform AI agent
#              communication. Enables Claude Code, Kimi CLI, Google CLI,
#              Cursor, Aider, OpenCode, and custom agents to interoperate.
# Version: 1.0.0
# Protocol: UAP v1.0
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_UAP_LOADED:-}" ]] && return 0
readonly _MAINFRAME_UAP_LOADED=1

# =============================================================================
# DEPENDENCY LOADING
# =============================================================================

# Source required libraries
if [[ -z "${_MAINFRAME_JSON_LOADED:-}" ]]; then
    source "${BASH_SOURCE%/*}/json.sh"
fi

if [[ -z "${_MAINFRAME_PURE_UTIL_LOADED:-}" ]]; then
    source "${BASH_SOURCE%/*}/pure-util.sh" 2>/dev/null || true
fi

# =============================================================================
# CONSTANTS
# =============================================================================

readonly UAP_VERSION="1.0"

# Message types
readonly UAP_TYPE_TASK_REQUEST="task_request"
readonly UAP_TYPE_TASK_RESPONSE="task_response"
readonly UAP_TYPE_HEARTBEAT="heartbeat"
readonly UAP_TYPE_DISCOVERY="discovery"
readonly UAP_TYPE_BROADCAST="broadcast"
readonly UAP_TYPE_ERROR="error"

# Platform identifiers
readonly UAP_PLATFORM_CLAUDE="claude-code"
readonly UAP_PLATFORM_KIMI="kimi-cli"
readonly UAP_PLATFORM_GOOGLE="google-cli"
readonly UAP_PLATFORM_CURSOR="cursor-ai"
readonly UAP_PLATFORM_AIDER="aider"
readonly UAP_PLATFORM_OPENCODE="opencode"
readonly UAP_PLATFORM_MAINFRAME="mainframe"
readonly UAP_PLATFORM_UNKNOWN="unknown"

# Base directory for UAP communication
readonly UAP_BASE_DIR="${MAINFRAME_UAP_DIR:-${HOME}/.mainframe/uap}"
readonly UAP_MAILBOX_DIR="$UAP_BASE_DIR/mailbox"
readonly UAP_REGISTRY_DIR="$UAP_BASE_DIR/registry"
readonly UAP_LOG_DIR="$UAP_BASE_DIR/logs"

# Default timeouts
readonly UAP_DEFAULT_TIMEOUT=30
readonly UAP_HEARTBEAT_INTERVAL=60

# =============================================================================
# GLOBAL STATE
# =============================================================================

declare -g UAP_AGENT_ID="${UAP_AGENT_ID:-}"
declare -g UAP_AGENT_PLATFORM="${UAP_AGENT_PLATFORM:-}"
declare -ga UAP_CAPABILITIES=()
declare -g UAP_HEARTBEAT_PID=""

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Logging function
_uap_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +%s)
    
    # Log to stderr if not quiet
    if [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[uap][%s] %s: %s\n' "$timestamp" "$level" "$message" >&2
    fi
    
    # Also log to file if directory exists
    if [[ -d "$UAP_LOG_DIR" ]]; then
        printf '[%s] %s: %s\n' "$timestamp" "$level" "$message" >> "$UAP_LOG_DIR/uap.log" 2>/dev/null || true
    fi
}

# Generate UUID (pure bash fallback if uuid not available)
_uap_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen 2>/dev/null
    elif declare -f uuid &>/dev/null; then
        uuid
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
_uap_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +%s
}

# Ensure directory structure exists
_uap_ensure_dirs() {
    mkdir -p "$UAP_MAILBOX_DIR" "$UAP_REGISTRY_DIR" "$UAP_LOG_DIR" 2>/dev/null || {
        _uap_log "error" "Failed to create UAP directories"
        return 1
    }
}

# Get agent mailbox path
_uap_mailbox_path() {
    local agent_id="$1"
    printf '%s' "$UAP_MAILBOX_DIR/$agent_id"
}

# =============================================================================
# PLATFORM DETECTION
# =============================================================================

# @desc Detect the current AI platform environment
# @usage uap_detect_platform
# @returns Platform identifier: claude-code|kimi-cli|google-cli|cursor-ai|aider|opencode|mainframe|unknown
uap_detect_platform() {
    # Check for Claude Code
    if [[ -n "${CLAUDE_CODE_VERSION:-}" ]]; then
        printf '%s' "$UAP_PLATFORM_CLAUDE"
        return 0
    fi
    
    # Check for Kimi CLI
    if [[ -n "${KIMI_CLI_VERSION:-}" ]]; then
        printf '%s' "$UAP_PLATFORM_KIMI"
        return 0
    fi
    
    # Check for Google CLI
    if [[ -n "${GOOGLE_CLI_VERSION:-}" ]]; then
        printf '%s' "$UAP_PLATFORM_GOOGLE"
        return 0
    fi
    
    # Check for Cursor AI
    if [[ -n "${CURSOR_AI_VERSION:-}" ]] || [[ -n "${CURSOR_VERSION:-}" ]]; then
        printf '%s' "$UAP_PLATFORM_CURSOR"
        return 0
    fi
    
    # Check for Aider
    if [[ -n "${AIDER_VERSION:-}" ]]; then
        printf '%s' "$UAP_PLATFORM_AIDER"
        return 0
    fi
    
    # Check for OpenCode
    if [[ -n "${OPENCODE_VERSION:-}" ]]; then
        printf '%s' "$UAP_PLATFORM_OPENCODE"
        return 0
    fi
    
    # Check if we're running under mainframe
    if [[ -n "${MAINFRAME_VERSION:-}" ]] || [[ -n "${MAINFRAME_ROOT:-}" ]]; then
        printf '%s' "$UAP_PLATFORM_MAINFRAME"
        return 0
    fi
    
    # Unknown platform
    printf '%s' "$UAP_PLATFORM_UNKNOWN"
    return 0
}

# =============================================================================
# MESSAGE ENCODING/DECODING
# =============================================================================

# @desc Encode a UAP message
# @usage uap_encode_message --type TYPE --payload 'JSON' [--to AGENT] [--capabilities "cap1,cap2"]
# @returns JSON message on stdout
uap_encode_message() {
    local msg_type=""
    local payload="{}"
    local to_agent=""
    local capabilities=""
    local correlation_id=""
    local broadcast="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                msg_type="$2"
                shift 2
                ;;
            --payload)
                payload="$2"
                shift 2
                ;;
            --to)
                to_agent="$2"
                shift 2
                ;;
            --capabilities)
                capabilities="$2"
                shift 2
                ;;
            --correlation-id)
                correlation_id="$2"
                shift 2
                ;;
            --broadcast)
                broadcast="true"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Validate required fields
    if [[ -z "$msg_type" ]]; then
        _uap_log "error" "Message type is required (use --type)"
        return 1
    fi
    
    # Generate IDs
    local message_id trace_id span_id
    message_id=$(_uap_uuid)
    trace_id="${correlation_id:-$message_id}"
    span_id=$(_uap_uuid)
    
    # Build capabilities array
    local caps_json="[]"
    if [[ -n "$capabilities" ]]; then
        local -a caps
        IFS=',' read -ra caps <<< "$capabilities"
        caps_json=$(json_array "${caps[@]}")
    elif [[ ${#UAP_CAPABILITIES[@]} -gt 0 ]]; then
        caps_json=$(json_array "${UAP_CAPABILITIES[@]}")
    fi
    
    # Detect platform if not set
    local platform="${UAP_AGENT_PLATFORM:-$(uap_detect_platform)}"
    local agent_id="${UAP_AGENT_ID:-$(hostname -s 2>/dev/null || echo "unknown")}_$$"
    
    # Build source object
    local source_json
    source_json=$(json_object \
        "platform=$platform" \
        "agent_id=$agent_id" \
        "capabilities:raw=$caps_json")
    
    # Build target object
    local target_json
    if [[ "$broadcast" == "true" ]]; then
        target_json=$(json_object \
            "agent_id=*" \
            "broadcast:bool=true")
    else
        target_json=$(json_object \
            "agent_id=${to_agent:-}" \
            "broadcast:bool=false")
    fi
    
    # Build trace object
    local trace_json
    trace_json=$(json_object \
        "trace_id=$trace_id" \
        "span_id=$span_id")
    
    # Build complete message
    json_object \
        "uap_version=$UAP_VERSION" \
        "message_type=$msg_type" \
        "message_id=$message_id" \
        "timestamp=$(_uap_timestamp)" \
        "source:raw=$source_json" \
        "target:raw=$target_json" \
        "payload:raw=$payload" \
        "trace:raw=$trace_json"
}

# @desc Decode a UAP message and extract information
# @usage uap_decode_message 'JSON_MESSAGE' [--get field]
# @returns Full message or extracted field value
uap_decode_message() {
    local json="$1"
    shift
    local get_field=""
    
    # Parse optional arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --get)
                get_field="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Validate JSON
    if ! json_valid "$json" 2>/dev/null; then
        _uap_log "error" "Invalid JSON message"
        return 1
    fi
    
    # Check for UAP version (basic validation)
    local version
    version=$(json_get "$json" "uap_version" 2>/dev/null || echo "")
    if [[ -z "$version" ]]; then
        _uap_log "error" "Not a UAP message (missing uap_version)"
        return 1
    fi
    
    # Return specific field or full message
    if [[ -n "$get_field" ]]; then
        json_get "$json" "$get_field" 2>/dev/null || printf ''
    else
        printf '%s' "$json"
    fi
}

# =============================================================================
# CAPABILITY MANAGEMENT
# =============================================================================

# @desc Register capabilities for this agent
# @usage uap_register_capability "cap1" "cap2" "cap3" ...
# @returns 0 on success
uap_register_capability() {
    local cap
    for cap in "$@"; do
        # Normalize capability (dot-namespaced)
        cap=$(uap_normalize_capability "$cap")
        
        # Add if not already present
        if [[ ! " ${UAP_CAPABILITIES[*]} " =~ [[:space:]]${cap}[[:space:]] ]]; then
            UAP_CAPABILITIES+=("$cap")
        fi
    done
    
    # Update agent registration if initialized
    if [[ -n "$UAP_AGENT_ID" ]]; then
        _uap_update_registration
    fi
    
    return 0
}

# @desc Normalize capability name to standard dot-namespaced format
# @usage uap_normalize_capability "capability"
# @returns Normalized capability name
uap_normalize_capability() {
    local cap="$1"
    
    # If already dot-namespaced, return as-is
    if [[ "$cap" == *.* ]]; then
        printf '%s' "$cap"
        return 0
    fi
    
    # Map common shorthands to dot-namespaced format
    case "$cap" in
        bash)
            printf 'bash.execute' ;;
        bash_safe)
            printf 'bash.execute.safe' ;;
        json)
            printf 'json.parse' ;;
        json_parse)
            printf 'json.parse' ;;
        json_generate)
            printf 'json.generate' ;;
        git)
            printf 'git.read' ;;
        git_read)
            printf 'git.read' ;;
        git_write)
            printf 'git.write' ;;
        memory|awm)
            printf 'memory.awm' ;;
        network|http)
            printf 'network.http' ;;
        file_read)
            printf 'file.read' ;;
        file_write)
            printf 'file.write' ;;
        file_edit)
            printf 'file.edit' ;;
        search)
            printf 'tool.search' ;;
        computer)
            printf 'tool.computer' ;;
        *)
            printf '%s' "$cap" ;;
    esac
}

# @desc Check if capability matches pattern (supports wildcards)
# @usage uap_capability_matches --required "pattern" --available "capability"
# @returns 0 if matches, 1 otherwise
uap_capability_matches() {
    local required=""
    local available=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --required)
                required="$2"
                shift 2
                ;;
            --available)
                available="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ -z "$required" ]] || [[ -z "$available" ]]; then
        _uap_log "error" "Both --required and --available are required"
        return 1
    fi
    
    # Normalize both
    required=$(uap_normalize_capability "$required")
    available=$(uap_normalize_capability "$available")
    
    # Exact match
    [[ "$required" == "$available" ]] && return 0
    
    # Wildcard match
    local pattern="${available//./\\.}"
    pattern="${pattern//\*/.*}"
    pattern="^${pattern}$"
    
    [[ "$required" =~ $pattern ]] && return 0
    
    # Check if available is more specific than required
    # e.g., required="bash.*" should match available="bash.execute.safe"
    pattern="${required//./\\.}"
    pattern="${pattern//\*/.*}"
    pattern="^${pattern}"
    
    [[ "$available" =~ $pattern ]] && return 0
    
    return 1
}

# @desc Discover agents with optional capability filter
# @usage uap_discover_agents [--capability NAME]
# @returns JSON array of agent info objects
uap_discover_agents() {
    local capability_filter=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --capability)
                capability_filter="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    _uap_ensure_dirs || return 1
    
    local -a agents=()
    
    for registry_file in "$UAP_REGISTRY_DIR"/*.json; do
        [[ -f "$registry_file" ]] || continue
        
        local agent_data
        agent_data=$(<"$registry_file")
        
        # Check if agent is still alive (if PID present)
        local pid
        pid=$(json_get "$agent_data" "pid" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
            # Agent is dead, clean up
            rm -f "$registry_file"
            continue
        fi
        
        # Check capability filter if specified
        if [[ -n "$capability_filter" ]]; then
            local caps
            caps=$(json_get "$agent_data" "capabilities" 2>/dev/null || echo "")
            
            local match_found=false
            local -a cap_list
            if [[ "$caps" =~ \[([^\]]*)\] ]]; then
                IFS=',' read -ra cap_list <<< "${BASH_REMATCH[1]}"
                for cap in "${cap_list[@]}"; do
                    # Remove quotes
                    cap="${cap//\"/}"
                    cap="${cap// /}"
                    if uap_capability_matches --required "$capability_filter" --available "$cap"; then
                        match_found=true
                        break
                    fi
                done
            fi
            
            ! $match_found && continue
        fi
        
        agents+=("$agent_data")
    done
    
    # Output JSON array
    if [[ ${#agents[@]} -eq 0 ]]; then
        printf '[]'
    else
        local first=true
        printf '['
        for agent in "${agents[@]}"; do
            $first || printf ','
            first=false
            printf '%s' "$agent"
        done
        printf ']'
    fi
}

# Internal: Update agent registration file
_uap_update_registration() {
    [[ -z "$UAP_AGENT_ID" ]] && return 1
    
    _uap_ensure_dirs || return 1
    
    local caps_json
    caps_json=$(json_array "${UAP_CAPABILITIES[@]}")
    
    json_object \
        "agent_id=$UAP_AGENT_ID" \
        "platform=${UAP_AGENT_PLATFORM:-$(uap_detect_platform)}" \
        "pid:number=$$" \
        "capabilities:raw=$caps_json" \
        "updated=$(_uap_timestamp)" \
    > "$UAP_REGISTRY_DIR/$UAP_AGENT_ID.json"
}

# =============================================================================
# COMMUNICATION
# =============================================================================

# @desc Send a message to a specific agent
# @usage uap_send --to AGENT --message 'JSON' [--timeout SECS]
# @returns JSON with success status and message_id
uap_send() {
    local to_agent=""
    local message=""
    local timeout="${UAP_DEFAULT_TIMEOUT}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --to)
                to_agent="$2"
                shift 2
                ;;
            --message)
                message="$2"
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
    
    # Validate inputs
    if [[ -z "$to_agent" ]]; then
        _uap_log "error" "Recipient agent required (use --to)"
        json_object "success:bool=false" "error=Recipient agent required"
        return 1
    fi
    
    if [[ -z "$message" ]]; then
        _uap_log "error" "Message content required (use --message)"
        json_object "success:bool=false" "error=Message content required"
        return 1
    fi
    
    _uap_ensure_dirs || return 1
    
    # Get target mailbox
    local mailbox
    mailbox=$(_uap_mailbox_path "$to_agent")
    
    # Create mailbox if it doesn't exist (for known agents)
    if [[ ! -d "$mailbox" ]]; then
        mkdir -p "$mailbox" 2>/dev/null || {
            _uap_log "error" "Cannot create mailbox for $to_agent"
            json_object "success:bool=false" "error=Cannot create mailbox"
            return 1
        }
    fi
    
    # Generate message ID
    local message_id
    message_id=$(_uap_uuid)
    
    # Write message atomically with flock
    local msg_file="$mailbox/${message_id}.json"
    local tmp_file="$mailbox/.tmp.${message_id}.$$"
    
    # Use flock if available (Linux), otherwise use atomic mv (macOS/BSD)
    if command -v flock &>/dev/null; then
        {
            flock -x 200 || {
                _uap_log "error" "Cannot lock mailbox for $to_agent"
                json_object "success:bool=false" "error=Mailbox locked"
                return 1
            }
            
            printf '%s' "$message" > "$tmp_file"
            mv -f "$tmp_file" "$msg_file"
            
            flock -u 200
        } 200>"$mailbox/.lock"
    else
        # Fallback: atomic write using temp file + mv (POSIX compliant)
        printf '%s' "$message" > "$tmp_file"
        mv -f "$tmp_file" "$msg_file"
    fi
    
    _uap_log "debug" "Message sent to $to_agent: $message_id"
    
    json_object \
        "success:bool=true" \
        "message_id=$message_id" \
        "recipient=$to_agent"
}

# @desc Receive a message from this agent's mailbox
# @usage uap_receive [--timeout SECS]
# @returns JSON message or empty on timeout
uap_receive() {
    local timeout="0"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)
                timeout="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    [[ -z "$UAP_AGENT_ID" ]] && {
        _uap_log "error" "Agent not initialized"
        return 1
    }
    
    local mailbox
    mailbox=$(_uap_mailbox_path "$UAP_AGENT_ID")
    [[ -d "$mailbox" ]] || {
        _uap_log "debug" "Mailbox does not exist: $mailbox"
        return 1
    }
    
    local deadline
    if (( timeout > 0 )); then
        deadline=$((SECONDS + timeout))
    else
        deadline=0
    fi
    
    while true; do
        # Get oldest message
        local msg_file
        # shellcheck disable=SC2010
        msg_file=$(ls -1tr "$mailbox"/*.json 2>/dev/null | grep -v '/\.tmp\.' | head -1)
        
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
            sleep 0.1
        else
            return 1
        fi
    done
}

# @desc Broadcast a message to all registered agents
# @usage uap_broadcast --message 'JSON' [--capability CAP]
# @returns JSON with count of recipients
uap_broadcast() {
    local message=""
    local capability_filter=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --message)
                message="$2"
                shift 2
                ;;
            --capability)
                capability_filter="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ -z "$message" ]]; then
        _uap_log "error" "Message content required (use --message)"
        json_object "success:bool=false" "error=Message content required"
        return 1
    fi
    
    _uap_ensure_dirs || return 1
    
    local sent=0
    local -a recipients=()
    
    # Build recipient list based on capability filter
    for registry_file in "$UAP_REGISTRY_DIR"/*.json; do
        [[ -f "$registry_file" ]] || continue
        
        local agent_data agent_id pid
        agent_data=$(<"$registry_file")
        agent_id=$(json_get "$agent_data" "agent_id" 2>/dev/null || echo "")
        pid=$(json_get "$agent_data" "pid" 2>/dev/null || echo "")
        
        # Skip self and dead agents
        [[ "$agent_id" == "$UAP_AGENT_ID" ]] && continue
        [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null && {
            rm -f "$registry_file"
            continue
        }
        
        # Check capability filter
        if [[ -n "$capability_filter" ]]; then
            local caps
            caps=$(json_get "$agent_data" "capabilities" 2>/dev/null || echo "")
            [[ "$caps" != *"$capability_filter"* ]] && continue
        fi
        
        recipients+=("$agent_id")
    done
    
    # Send to all recipients
    for recipient in "${recipients[@]}"; do
        uap_send --to "$recipient" --message "$message" >/dev/null && ((sent++))
    done
    
    _uap_log "debug" "Broadcast sent to $sent agents"
    
    json_object \
        "success:bool=true" \
        "sent:number=$sent"
}

# =============================================================================
# DISCOVERY
# =============================================================================

# @desc Send a heartbeat to announce presence
# @usage uap_heartbeat [--status STATUS]
# @returns JSON heartbeat message
uap_heartbeat() {
    local status="healthy"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status)
                status="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Initialize if not already done
    if [[ -z "$UAP_AGENT_ID" ]]; then
        # shellcheck disable=SC2119
        uap_init >/dev/null 2>&1 || {
            _uap_log "error" "Cannot initialize agent for heartbeat"
            return 1
        }
    fi
    
    # Build payload
    local payload
    payload=$(json_object \
        "status=$status" \
        "agent_id=$UAP_AGENT_ID" \
        "timestamp=$(_uap_timestamp)")
    
    # Create heartbeat message
    local message
    message=$(uap_encode_message \
        --type "$UAP_TYPE_HEARTBEAT" \
        --payload "$payload")
    
    # Update registration
    _uap_update_registration
    
    printf '%s' "$message"
}

# @desc Get information about a specific agent
# @usage uap_get_agent_info [AGENT_ID]
# @returns JSON agent info or error
uap_get_agent_info() {
    local agent_id="${1:-}"
    
    # Default to current agent if no ID provided and we're initialized
    if [[ -z "$agent_id" && -n "$UAP_AGENT_ID" ]]; then
        agent_id="$UAP_AGENT_ID"
    fi
    
    if [[ -z "$agent_id" ]]; then
        json_object \
            "success:bool=false" \
            "error=No agent ID specified"
        return 1
    fi
    
    local registry_file="$UAP_REGISTRY_DIR/${agent_id}.json"
    
    if [[ -f "$registry_file" ]]; then
        local info
        info=$(<"$registry_file")
        
        # Add online status
        local pid
        pid=$(json_get "$info" "pid" 2>/dev/null || echo "")
        local online="false"
        [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && online="true"
        
        # Merge online status into result
        json_object \
            "info:raw=$info" \
            "online:bool=$online"
    else
        json_object \
            "success:bool=false" \
            "error=Agent not found" \
            "agent_id=$agent_id"
        return 1
    fi
}

# @desc List all registered agents
# @usage uap_list_agents
# @returns JSON array of agent IDs
uap_list_agents() {
    _uap_ensure_dirs || return 1
    
    local -a agents=()
    
    for registry_file in "$UAP_REGISTRY_DIR"/*.json; do
        [[ -f "$registry_file" ]] || continue
        
        local agent_id pid
        agent_id=$(json_get "$(<"$registry_file")" "agent_id" 2>/dev/null || echo "")
        pid=$(json_get "$(<"$registry_file")" "pid" 2>/dev/null || echo "")
        
        # Clean up dead agents
        if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$registry_file"
            continue
        fi
        
        [[ -n "$agent_id" ]] && agents+=("$agent_id")
    done
    
    json_array "${agents[@]}"
}

# =============================================================================
# AGENT INITIALIZATION
# =============================================================================

# @desc Initialize this agent for UAP communication
# @usage uap_init [--id ID] [--platform PLATFORM] [--capabilities "cap1,cap2"]
# @returns JSON with agent info
# shellcheck disable=SC2120
uap_init() {
    local agent_id=""
    local platform=""
    local capabilities=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id)
                agent_id="$2"
                shift 2
                ;;
            --platform)
                platform="$2"
                shift 2
                ;;
            --capabilities)
                capabilities="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Set platform
    UAP_AGENT_PLATFORM="${platform:-$(uap_detect_platform)}"
    
    # Generate or use provided agent ID
    if [[ -z "$agent_id" ]]; then
        local host
        host=$(hostname -s 2>/dev/null || echo "unknown")
        UAP_AGENT_ID="${host}_$$_$(_uap_uuid | cut -d'-' -f1)"
    else
        UAP_AGENT_ID="$agent_id"
    fi
    
    # Register capabilities
    if [[ -n "$capabilities" ]]; then
        local -a caps
        IFS=',' read -ra caps <<< "$capabilities"
        uap_register_capability "${caps[@]}"
    fi
    
    # Ensure directories and create mailbox
    _uap_ensure_dirs || return 1
    local mailbox
    mailbox=$(_uap_mailbox_path "$UAP_AGENT_ID")
    mkdir -p "$mailbox" 2>/dev/null || {
        _uap_log "error" "Failed to create mailbox"
        return 1
    }
    
    # Register agent
    _uap_update_registration
    
    # Start heartbeat if requested
    if [[ "${UAP_AUTO_HEARTBEAT:-}" == "1" ]]; then
        _uap_start_heartbeat
    fi
    
    _uap_log "info" "Agent initialized: $UAP_AGENT_ID"
    
    json_object \
        "success:bool=true" \
        "agent_id=$UAP_AGENT_ID" \
        "platform=$UAP_AGENT_PLATFORM" \
        "capabilities=$(json_array "${UAP_CAPABILITIES[@]}")" \
        "mailbox=$mailbox"
}

# @desc Shutdown this agent and cleanup
# @usage uap_shutdown [--cleanup]
# @returns JSON with status
uap_shutdown() {
    local cleanup="false"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cleanup)
                cleanup="true"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Stop heartbeat if running
    if [[ -n "$UAP_HEARTBEAT_PID" ]]; then
        kill "$UAP_HEARTBEAT_PID" 2>/dev/null || true
        UAP_HEARTBEAT_PID=""
    fi
    
    local old_id="$UAP_AGENT_ID"
    
    if [[ -n "$UAP_AGENT_ID" ]]; then
        # Remove from registry
        rm -f "$UAP_REGISTRY_DIR/${UAP_AGENT_ID}.json"
        
        # Cleanup mailbox if requested
        if [[ "$cleanup" == "true" ]]; then
            local mailbox
            mailbox=$(_uap_mailbox_path "$UAP_AGENT_ID")
            rm -rf "$mailbox"
        fi
        
        UAP_AGENT_ID=""
        UAP_AGENT_PLATFORM=""
        UAP_CAPABILITIES=()
    fi
    
    _uap_log "info" "Agent shutdown: $old_id"
    
    json_object \
        "success:bool=true" \
        "agent_id=$old_id" \
        "status=shutdown"
}

# Internal: Start background heartbeat
_uap_start_heartbeat() {
    (
        while [[ -n "$UAP_AGENT_ID" ]]; do
            _uap_update_registration
            sleep "$UAP_HEARTBEAT_INTERVAL"
        done
    ) &
    UAP_HEARTBEAT_PID=$!
    
    _uap_log "debug" "Heartbeat started (PID: $UAP_HEARTBEAT_PID)"
}

# =============================================================================
# EXPORTS
# =============================================================================

export UAP_VERSION
export UAP_TYPE_TASK_REQUEST UAP_TYPE_TASK_RESPONSE UAP_TYPE_HEARTBEAT
export UAP_TYPE_DISCOVERY UAP_TYPE_BROADCAST UAP_TYPE_ERROR
export UAP_PLATFORM_CLAUDE UAP_PLATFORM_KIMI UAP_PLATFORM_GOOGLE
export UAP_PLATFORM_CURSOR UAP_PLATFORM_AIDER UAP_PLATFORM_OPENCODE
export UAP_PLATFORM_MAINFRAME UAP_PLATFORM_UNKNOWN

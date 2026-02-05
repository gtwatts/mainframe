#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2119,SC2120,SC2016,SC1003,SC2155,SC2181,SC2059,SC2206

# =============================================================================
# MAINFRAME/lib/mcp_server.sh - Model Context Protocol Server
# =============================================================================
# Description: MCP server implementation that exposes Mainframe functions as
#              tools for Claude Code and other MCP-compatible clients.
#              Enables AI assistants to discover and invoke Mainframe
#              capabilities through standardized JSON-RPC interface.
# Version: 1.0.0
# Protocol: MCP (Model Context Protocol) v2024-11-05
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_MCP_LOADED:-}" ]] && return 0
readonly _MAINFRAME_MCP_LOADED=1

# Ensure dependencies
if [[ -z "${_MAINFRAME_JSON_LOADED:-}" ]]; then
    source "${BASH_SOURCE%/*}/json.sh"
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

MCP_SERVER_NAME="${MCP_SERVER_NAME:-mainframe}"
MCP_SERVER_VERSION="${MCP_SERVER_VERSION:-1.0.0}"
MCP_LOG_LEVEL="${MCP_LOG_LEVEL:-info}"  # debug, info, warn, error

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_mcp_log() {
    local level="$1"
    shift
    
    # Check log level
    case "$MCP_LOG_LEVEL" in
        debug) ;;
        info) [[ "$level" == "debug" ]] && return ;;
        warn) [[ "$level" =~ ^(debug|info)$ ]] && return ;;
        error) [[ "$level" =~ ^(debug|info|warn)$ ]] && return ;;
    esac
    
    printf '[MCP %s] %s\n' "$level" "$*" >&2
}

_mcp_send() {
    local json="$1"
    local content_length=${#json}
    
    # MCP protocol: Content-Length header followed by JSON body
    printf 'Content-Length: %d\r\n\r\n%s\n' "$content_length" "$json"
}

_mcp_error() {
    local code="$1"
    local message="$2"
    local id="${3:-null}"
    
    json_object \
        "jsonrpc=2.0" \
        "id=${id}" \
        "error=$(json_object \
            "code:number=$code" \
            "message=$message"
        )"
}

_mcp_result() {
    local id="$1"
    local result="$2"
    
    json_object \
        "jsonrpc=2.0" \
        "id=$id" \
        "result:raw=$result"
}

# =============================================================================
# TOOL REGISTRY
# =============================================================================

declare -gA _MCP_TOOLS=()
declare -gA _MCP_TOOL_SCHEMAS=()

# @desc Register a Mainframe function as an MCP tool
# @usage mcp_register_tool "tool_name" "function_name" "description" "schema_json"
mcp_register_tool() {
    local tool_name="$1"
    local function_name="$2"
    local description="$3"
    local schema="${4:-{}}"
    
    _MCP_TOOLS["$tool_name"]="$function_name"
    _MCP_TOOL_SCHEMAS["$tool_name"]=$(json_object \
        "name=$tool_name" \
        "description=$description" \
        "inputSchema:raw=$schema"
    )
    
    _mcp_log debug "Registered tool: $tool_name -> $function_name"
}

# @desc Auto-register common Mainframe tools
# @usage mcp_register_default_tools
mcp_register_default_tools() {
    # JSON tools
    mcp_register_tool "json_object" "json_object" \
        "Create a JSON object from key=value pairs" \
        '{"type":"object","properties":{"pairs":{"type":"array","description":"Key=value pairs"}},"required":["pairs"]}'
    
    mcp_register_tool "json_get" "json_get" \
        "Extract a value from JSON by key" \
        '{"type":"object","properties":{"json":{"type":"string"},"key":{"type":"string"}},"required":["json","key"]}'
    
    mcp_register_tool "json_valid" "json_valid" \
        "Validate if a string is valid JSON" \
        '{"type":"object","properties":{"json":{"type":"string"}},"required":["json"]}'
    
    # String tools
    mcp_register_tool "trim_string" "trim_string" \
        "Remove leading and trailing whitespace" \
        '{"type":"object","properties":{"string":{"type":"string"}},"required":["string"]}'
    
    mcp_register_tool "to_lower" "to_lower" \
        "Convert string to lowercase" \
        '{"type":"object","properties":{"string":{"type":"string"}},"required":["string"]}'
    
    mcp_register_tool "to_upper" "to_upper" \
        "Convert string to uppercase" \
        '{"type":"object","properties":{"string":{"type":"string"}},"required":["string"]}'
    
    mcp_register_tool "replace_all" "replace_all" \
        "Replace all occurrences of a substring" \
        '{"type":"object","properties":{"string":{"type":"string"},"old":{"type":"string"},"new":{"type":"string"}},"required":["string","old","new"]}'
    
    # Validation tools
    mcp_register_tool "validate_email" "validate_email" \
        "Validate email address format" \
        '{"type":"object","properties":{"email":{"type":"string"}},"required":["email"]}'
    
    mcp_register_tool "validate_url" "validate_url" \
        "Validate URL format" \
        '{"type":"object","properties":{"url":{"type":"string"}},"required":["url"]}'
    
    mcp_register_tool "validate_path_safe" "validate_path_safe" \
        "Validate path is safe (no traversal)" \
        '{"type":"object","properties":{"path":{"type":"string"},"base":{"type":"string"}},"required":["path","base"]}'
    
    # File tools
    mcp_register_tool "read_file" "read_file" \
        "Read contents of a file" \
        '{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}'
    
    mcp_register_tool "file_exists" "file_exists" \
        "Check if a file exists" \
        '{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}'
    
    mcp_register_tool "file_lines" "file_lines" \
        "Count lines in a file" \
        '{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}'
    
    # DateTime tools
    mcp_register_tool "now_iso" "now_iso" \
        "Get current timestamp in ISO format" \
        '{}'
    
    mcp_register_tool "uuid" "uuid" \
        "Generate a UUID v4" \
        '{}'
    
    # Crypto tools
    mcp_register_tool "sha256" "sha256" \
        "Calculate SHA-256 hash" \
        '{"type":"object","properties":{"data":{"type":"string"}},"required":["data"]}'
    
    mcp_register_tool "base64_encode" "base64_encode" \
        "Base64 encode a string" \
        '{"type":"object","properties":{"data":{"type":"string"}},"required":["data"]}'
    
    # Git tools
    mcp_register_tool "git_branch" "git_branch" \
        "Get current git branch" \
        '{}'
    
    mcp_register_tool "git_is_dirty" "git_is_dirty" \
        "Check if git working directory has uncommitted changes" \
        '{}'
    
    # Process tools
    mcp_register_tool "proc_find_by_port" "proc_find_by_port" \
        "Find process using a port" \
        '{"type":"object","properties":{"port":{"type":"number"}},"required":["port"]}'
    
    _mcp_log info "Registered ${#_MCP_TOOLS[@]} default tools"
}

# =============================================================================
# MCP METHOD HANDLERS
# =============================================================================

# @desc Handle initialize request
# @usage _mcp_handle_initialize "$params" "$id"
_mcp_handle_initialize() {
    local params="$1"
    local id="$2"
    
    local result
    result=$(json_object \
        "protocolVersion=2024-11-05" \
        "capabilities=$(json_object \
            "tools=$(json_object "listChanged:bool=false")" \
        )" \
        "serverInfo=$(json_object \
            "name=$MCP_SERVER_NAME" \
            "version=$MCP_SERVER_VERSION"
        )"
    )
    
    _mcp_result "$id" "$result"
}

# @desc Handle tools/list request
# @usage _mcp_handle_tools_list "$params" "$id"
_mcp_handle_tools_list() {
    local id="$1"
    
    local tools_json="["
    local first=true
    for tool_name in "${!_MCP_TOOL_SCHEMAS[@]}"; do
        $first || tools_json+=","
        first=false
        tools_json+="${_MCP_TOOL_SCHEMAS[$tool_name]}"
    done
    tools_json+="]"
    
    local result
    result=$(json_object "tools:raw=$tools_json")
    
    _mcp_result "$id" "$result"
}

# @desc Handle tools/call request
# @usage _mcp_handle_tools_call "$params" "$id"
_mcp_handle_tools_call() {
    local params="$1"
    local id="$2"
    
    local tool_name arguments
    tool_name=$(json_get "$params" "name")
    arguments=$(json_get "$params" "arguments")
    
    if [[ -z "$tool_name" ]]; then
        _mcp_send "$(_mcp_error -32602 "Missing tool name" "$id")"
        return
    fi
    
    # Check if tool exists
    local function_name="${_MCP_TOOLS[$tool_name]:-}"
    if [[ -z "$function_name" ]]; then
        _mcp_send "$(_mcp_error -32601 "Unknown tool: $tool_name" "$id")"
        return
    fi
    
    _mcp_log debug "Calling tool: $tool_name -> $function_name"
    
    # Build arguments array from JSON
    # shellcheck disable=SC2034
    local -a args=()
    # shellcheck disable=SC2034
    local keys
    keys=$(json_get "$arguments" "*")
    
    # For simplicity, pass the whole JSON as single argument
    # In production, parse individual fields based on schema
    local output
    local exit_code=0
    
    # Check if function exists
    if ! declare -F "$function_name" &>/dev/null; then
        _mcp_send "$(_mcp_error -32603 "Function not available: $function_name" "$id")"
        return
    fi
    
    # Call function based on tool type
    case "$tool_name" in
        json_object)
            # Extract pairs from arguments
            # shellcheck disable=SC2034
            local pairs=""
            # Parse object keys and build pairs
            output=$(json_object 2>&1) || exit_code=$?
            ;;
        json_get)
            local json_arg key_arg
            json_arg=$(json_get "$arguments" "json")
            key_arg=$(json_get "$arguments" "key")
            output=$(json_get "$json_arg" "$key_arg" 2>&1) || exit_code=$?
            ;;
        json_valid)
            local json_arg
            json_arg=$(json_get "$arguments" "json")
            if json_valid "$json_arg"; then
                output="true"
            else
                output="false"
            fi
            ;;
        trim_string|to_lower|to_upper)
            local str_arg
            str_arg=$(json_get "$arguments" "string")
            output=$($function_name "$str_arg" 2>&1) || exit_code=$?
            ;;
        replace_all)
            local str old new
            str=$(json_get "$arguments" "string")
            old=$(json_get "$arguments" "old")
            new=$(json_get "$arguments" "new")
            output=$(replace_all "$str" "$old" "$new" 2>&1) || exit_code=$?
            ;;
        validate_email|validate_url)
            local val
            val=$(json_get "$arguments" "${tool_name#validate_}")
            if $function_name "$val"; then
                output="true"
            else
                output="false"
            fi
            ;;
        validate_path_safe)
            local path base
            path=$(json_get "$arguments" "path")
            base=$(json_get "$arguments" "base")
            if validate_path_safe "$path" "$base"; then
                output="true"
            else
                output="false"
            fi
            ;;
        read_file)
            local path
            path=$(json_get "$arguments" "path")
            if [[ -f "$path" ]]; then
                output=$(read_file "$path" 2>&1) || exit_code=$?
            else
                _mcp_send "$(_mcp_error -32602 "File not found: $path" "$id")"
                return
            fi
            ;;
        file_exists)
            local path
            path=$(json_get "$arguments" "path")
            if file_exists "$path"; then
                output="true"
            else
                output="false"
            fi
            ;;
        file_lines)
            local path
            path=$(json_get "$arguments" "path")
            output=$(file_lines "$path" 2>&1) || exit_code=$?
            ;;
        now_iso|uuid)
            output=$($function_name 2>&1) || exit_code=$?
            ;;
        sha256)
            local data
            data=$(json_get "$arguments" "data")
            output=$(sha256 "$data" 2>&1) || exit_code=$?
            ;;
        base64_encode)
            local data
            data=$(json_get "$arguments" "data")
            output=$(base64_encode "$data" 2>&1) || exit_code=$?
            ;;
        git_branch|git_is_dirty)
            output=$($function_name 2>&1) || exit_code=$?
            ;;
        proc_find_by_port)
            local port
            port=$(json_get "$arguments" "port")
            output=$(proc_find_by_port "$port" 2>&1) || exit_code=$?
            ;;
        *)
            _mcp_send "$(_mcp_error -32603 "Tool not implemented: $tool_name" "$id")"
            return
            ;;
    esac
    
    if [[ $exit_code -ne 0 ]]; then
        local error_result
        error_result=$(json_object \
            "content:raw=$(json_array "$(json_object \
                "type=text" \
                "text=$(json_escape "$output")"
            )")" \
            "isError:bool=true"
        )
        _mcp_send "$(_mcp_result "$id" "$error_result")"
    else
        local success_result
        success_result=$(json_object \
            "content:raw=$(json_array "$(json_object \
                "type=text" \
                "text=$(json_escape "$output")"
            )")" \
            "isError:bool=false"
        )
        _mcp_send "$(_mcp_result "$id" "$success_result")"
    fi
}

# @desc Handle unknown method
# @usage _mcp_handle_unknown "$method" "$id"
_mcp_handle_unknown() {
    local method="$1"
    local id="$2"
    
    _mcp_send "$(_mcp_error -32601 "Method not found: $method" "$id")"
}

# =============================================================================
# MAIN SERVER LOOP
# =============================================================================

# @desc Start the MCP server and process requests
# @usage mcp_server_start
mcp_server_start() {
    _mcp_log info "Starting MCP server: $MCP_SERVER_NAME v$MCP_SERVER_VERSION"
    
    # Register default tools if none registered
    if [[ ${#_MCP_TOOLS[@]} -eq 0 ]]; then
        mcp_register_default_tools
    fi
    
    _mcp_log info "Ready to accept connections"
    
    # Process JSON-RPC requests from stdin
    while IFS= read -r line; do
        # Handle Content-Length header
        if [[ "$line" == Content-Length:* ]]; then
            local content_length="${line#Content-Length: }"
            content_length="${content_length//[$'\r\n']/}"
            
            # Read empty line
            # shellcheck disable=SC2034
            IFS= read -r empty_line
            
            # Read the JSON payload
            local json_payload=""
            if [[ -n "$content_length" && "$content_length" =~ ^[0-9]+$ ]]; then
                json_payload=$(head -c "$content_length")
            fi
            
            _mcp_log debug "Received: $json_payload"
            
            # Parse and handle request
            if json_valid "$json_payload"; then
                local method params id
                method=$(json_get "$json_payload" "method")
                params=$(json_get "$json_payload" "params")
                id=$(json_get "$json_payload" "id")
                id="${id:-null}"
                
                _mcp_log debug "Method: $method, ID: $id"
                
                case "$method" in
                    initialize)
                        _mcp_send "$(_mcp_handle_initialize "$params" "$id")"
                        ;;
                    "tools/list")
                        _mcp_send "$(_mcp_handle_tools_list "$id")"
                        ;;
                    "tools/call")
                        _mcp_handle_tools_call "$params" "$id"
                        ;;
                    *)
                        _mcp_handle_unknown "$method" "$id"
                        ;;
                esac
            else
                _mcp_log error "Invalid JSON received"
                _mcp_send "$(_mcp_error -32700 "Parse error" "null")"
            fi
        fi
    done
}

# @desc Run MCP server with auto-registration
# @usage mcp_server_run
mcp_server_run() {
    mcp_register_default_tools
    mcp_server_start
}

# =============================================================================
# EXPORTS
# =============================================================================

_MCP_EXPORTS=(
    mcp_register_tool
    mcp_register_default_tools
    mcp_server_start
    mcp_server_run
)

#!/usr/bin/env bash
# MCP Server for Claude Code integration
# Exposes Mainframe functions as MCP tools via JSON-RPC
#
# Installation:
#   1. Make executable: chmod +x mcp-server.sh
#   2. Configure Claude Code to use this as an MCP server
#
# Protocol: JSON-RPC 2.0 over stdin/stdout

set -euo pipefail

# Server version
SERVER_VERSION="7.0.0"
SERVER_NAME="mainframe"

# Logging (to stderr)
log_debug() { echo "[DEBUG] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

# ============================================================================
# JSON Helpers
# ============================================================================

json_encode_string() {
    local str="$1"
    if [[ "$str" =~ ^-?[0-9]+$ ]] || [[ "$str" == "null" ]]; then
        echo "$str"
    else
        str="${str//\\/\\\\}"
        str="${str//\"/\\\"}"
        str="${str//$'\t'/\\t}"
        str="${str//$'\n'/\\n}"
        str="${str//$'\r'/\\r}"
        echo "\"$str\""
    fi
}

json_extract() {
    local json="$1"
    local key="$2"
    
    if [[ "$key" == *.* ]]; then
        local first="${key%%.*}"
        local rest="${key#*.}"
        local value
        value=$(json_extract "$json" "$first")
        value="${value#\"}"
        value="${value%\"}"
        json_extract "$value" "$rest"
    else
        local pattern="\"$key\"[[:space:]]*:[[:space:]]*"
        if [[ "$json" =~ $pattern(\"[^\"]*\"|[0-9]+|true|false|null|\{[^}]*\}|\[[^\]]*\]) ]]; then
            echo "${BASH_REMATCH[1]}"
        fi
    fi
}

# ============================================================================
# JSON-RPC Response Helpers
# ============================================================================

send_response() {
    local id="$1"
    local result="$2"
    printf '{"jsonrpc":"2.0","id":%s,"result":%s}\n' "$(json_encode_string "$id")" "$result"
}

send_error() {
    local id="$1"
    local code="$2"
    local message="$3"
    printf '{"jsonrpc":"2.0","id":%s,"error":{"code":%d,"message":%s}}\n' \
        "$(json_encode_string "$id")" "$code" "$(json_encode_string "$message")"
}

# ============================================================================
# Tool Implementations
# ============================================================================

tool_json_escape() {
    local text="${1:-}"
    local escaped="$text"
    escaped="${escaped//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    escaped="${escaped//$'\n'/\\n}"
    escaped="${escaped//$'\r'/\\r}"
    escaped="${escaped//$'\t'/\\t}"
    echo "\"$escaped\""
}

tool_json_object() {
    local keyvalues="${1:-}"
    local result="{"
    local first=1
    local IFS=','
    
    for pair in $keyvalues; do
        [[ -z "$pair" ]] && continue
        pair=$(echo "$pair" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [[ "$pair" == *"="* ]]; then
            local key="${pair%%=*}"
            local value="${pair#*=}"
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            [[ $first -eq 0 ]] && result="$result,"
            first=0
            
            if [[ "$key" == *":"* ]]; then
                local type="${key##*:}"
                key="${key%%:*}"
                case "$type" in
                    number|bool|boolean|null|raw) result="$result\"$key\":$value" ;;
                    *) result="$result\"$key\":\"$value\"" ;;
                esac
            else
                result="$result\"$key\":\"$value\""
            fi
        fi
    done
    
    result="$result}"
    echo "$result"
}

tool_trim_string() {
    local text="${1:-}"
    echo "$text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

tool_to_lower() {
    local text="${1:-}"
    echo "$text" | tr '[:upper:]' '[:lower:]'
}

tool_to_upper() {
    local text="${1:-}"
    echo "$text" | tr '[:lower:]' '[:upper:]'
}

tool_validate_json() {
    local json="${1:-}"
    local depth_obj=0
    local depth_arr=0
    local in_string=0
    local char prev_char=""
    
    while IFS= read -r -n1 char; do
        [[ -z "$char" ]] && break
        
        if [[ "$char" == '"' && "$prev_char" != '\\' ]]; then
            in_string=$((1 - in_string))
        fi
        
        if [[ $in_string -eq 0 ]]; then
            case "$char" in
                '{') depth_obj=$((depth_obj + 1)) ;;
                '}') depth_obj=$((depth_obj - 1)) ;;
                '[') depth_arr=$((depth_arr + 1)) ;;
                ']') depth_arr=$((depth_arr - 1)) ;;
            esac
            
            if [[ $depth_obj -lt 0 || $depth_arr -lt 0 ]]; then
                echo "false"
                return
            fi
        fi
        prev_char="$char"
    done <<< "$json"
    
    if [[ $depth_obj -eq 0 && $depth_arr -eq 0 ]]; then
        echo "true"
    else
        echo "false"
    fi
}

tool_validate_path() {
    local path="${1:-}"
    
    if [[ "$path" == *..* ]]; then
        echo '{"valid":false,"error":"Path contains traversal sequence"}'
        return
    fi
    
    echo '{"valid":true}'
}

tool_file_read() {
    local path="${1:-}"
    
    if [[ ! -f "$path" ]]; then
        echo "{\"success\":false,\"error\":\"File not found: $path\"}"
        return
    fi
    
    if [[ ! -r "$path" ]]; then
        echo "{\"success\":false,\"error\":\"File not readable: $path\"}"
        return
    fi
    
    local content
    content=$(cat "$path" 2>/dev/null || echo "")
    local escaped="$content"
    escaped="${escaped//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    escaped="${escaped//$'\n'/\\n}"
    escaped="${escaped//$'\r'/\\r}"
    escaped="${escaped//$'\t'/\\t}"
    
    echo "{\"success\":true,\"content\":\"$escaped\"}"
}

tool_file_write() {
    local path="${1:-}"
    local content="${2:-}"
    
    local dir
    dir=$(dirname "$path")
    
    if [[ ! -d "$dir" ]]; then
        echo "{\"success\":false,\"error\":\"Directory does not exist: $dir\"}"
        return
    fi
    
    if [[ ! -w "$dir" ]]; then
        echo "{\"success\":false,\"error\":\"Directory not writable: $dir\"}"
        return
    fi
    
    local tmpfile="${path}.tmp.$$"
    
    if printf '%s' "$content" > "$tmpfile" 2>/dev/null; then
        if mv "$tmpfile" "$path" 2>/dev/null; then
            echo "{\"success\":true,\"bytes_written\":${#content}}"
        else
            rm -f "$tmpfile"
            echo "{\"success\":false,\"error\":\"Failed to move temp file\"}"
        fi
    else
        rm -f "$tmpfile"
        echo "{\"success\":false,\"error\":\"Failed to write temp file\"}"
    fi
}

tool_directory_list() {
    local path="${1:-.}"
    
    if [[ ! -d "$path" ]]; then
        echo "{\"success\":false,\"error\":\"Not a directory: $path\"}"
        return
    fi
    
    if [[ ! -r "$path" ]]; then
        echo "{\"success\":false,\"error\":\"Directory not readable: $path\"}"
        return
    fi
    
    local dirs=()
    local files=()
    
    for entry in "$path"/*; do
        [[ ! -e "$entry" ]] && continue
        local name
        name=$(basename "$entry")
        if [[ -d "$entry" ]]; then
            dirs+=("\"$name\"")
        else
            files+=("\"$name\"")
        fi
    done
    
    local dirs_json files_json
    dirs_json="[$(IFS=','; echo "${dirs[*]}")]"
    files_json="[$(IFS=','; echo "${files[*]}")]"
    
    echo "{\"success\":true,\"directories\":$dirs_json,\"files\":$files_json}"
}

tool_ammma_init() {
    local session="${1:-default}"
    local session_id="${session}_$(date +%s)_$$"
    local session_dir="/tmp/mainframe_mcp_sessions/$session_id"
    mkdir -p "$session_dir"
    echo "{\"success\":true,\"session_id\":\"$session_id\",\"timestamp\":$(date +%s)}"
}

tool_ammma_checkpoint() {
    local key="${1:-}"
    local value="${2:-}"
    local session_id="${3:-default}"
    local session_dir="/tmp/mainframe_mcp_sessions/$session_id"
    mkdir -p "$session_dir"
    printf '%s' "$value" > "$session_dir/$key"
    echo "{\"success\":true,\"key\":\"$key\",\"timestamp\":$(date +%s)}"
}

tool_git_status() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "{\"success\":false,\"error\":\"Not a git repository\"}"
        return
    fi
    
    local branch is_dirty="false" staged="false" untracked
    branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        is_dirty="true"
    fi
    
    if ! git diff --cached --quiet 2>/dev/null; then
        staged="true"
    fi
    
    untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
    
    echo "{\"success\":true,\"branch\":\"$branch\",\"is_dirty\":$is_dirty,\"has_staged\":$staged,\"untracked_count\":$untracked}"
}

tool_git_branch() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "{\"success\":false,\"error\":\"Not a git repository\"}"
        return
    fi
    
    local branch
    branch=$(git branch --show-current 2>/dev/null || git describe --contains --all HEAD 2>/dev/null || echo "unknown")
    echo "{\"success\":true,\"branch\":\"$branch\"}"
}

# ============================================================================
# Request Handlers
# ============================================================================

handle_initialize() {
    local id="$1"
    local result
    result=$(cat << 'INITEOF'
{"protocolVersion": "2024-11-05", "capabilities": {"tools": {}, "resources": {}, "prompts": {}}, "serverInfo": {"name": "mainframe", "version": "7.0.0"}}
INITEOF
)
    send_response "$id" "$result"
}

handle_tools_list() {
    local id="$1"
    local result
    result='{"tools": [{"name": "json_escape", "description": "Escape string for JSON", "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}}, {"name": "json_object", "description": "Create JSON object", "inputSchema": {"type": "object", "properties": {"keyvalues": {"type": "string"}}, "required": ["keyvalues"]}}, {"name": "trim_string", "description": "Trim whitespace", "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}}, {"name": "to_lower", "description": "Convert to lowercase", "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}}, {"name": "to_upper", "description": "Convert to uppercase", "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}}, {"name": "validate_json", "description": "Validate JSON", "inputSchema": {"type": "object", "properties": {"json": {"type": "string"}}, "required": ["json"]}}, {"name": "validate_path", "description": "Validate path", "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}, {"name": "file_read", "description": "Read file", "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}, {"name": "file_write", "description": "Write file", "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}}, "required": ["path", "content"]}}, {"name": "directory_list", "description": "List directory", "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}}}}, {"name": "ammma_init", "description": "Init AMMA", "inputSchema": {"type": "object", "properties": {"session": {"type": "string"}}}}, {"name": "ammma_checkpoint", "description": "AMMA checkpoint", "inputSchema": {"type": "object", "properties": {"key": {"type": "string"}, "value": {"type": "string"}, "session_id": {"type": "string"}}, "required": ["key", "value"]}}, {"name": "git_status", "description": "Git status", "inputSchema": {"type": "object"}}, {"name": "git_branch", "description": "Git branch", "inputSchema": {"type": "object"}}]}'
    send_response "$id" "$result"
}

handle_tools_call() {
    local id="$1"
    local request="$2"
    
    local tool_name args result
    tool_name=$(json_extract "$request" "params.name")
    tool_name="${tool_name#\"}"
    tool_name="${tool_name%\"}"
    
    args=$(json_extract "$request" "params.arguments")
    
    case "$tool_name" in
        "json_escape")
            local text
            text=$(json_extract "$args" "text")
            text="${text#\"}"
            text="${text%\"}"
            result=$(tool_json_escape "$text")
            ;;
        "json_object")
            local keyvalues
            keyvalues=$(json_extract "$args" "keyvalues")
            keyvalues="${keyvalues#\"}"
            keyvalues="${keyvalues%\"}"
            result=$(tool_json_object "$keyvalues")
            ;;
        "trim_string")
            local text
            text=$(json_extract "$args" "text")
            text="${text#\"}"
            text="${text%\"}"
            result=$(tool_trim_string "$text")
            result="\"$result\""
            ;;
        "to_lower")
            local text
            text=$(json_extract "$args" "text")
            text="${text#\"}"
            text="${text%\"}"
            result=$(tool_to_lower "$text")
            result="\"$result\""
            ;;
        "to_upper")
            local text
            text=$(json_extract "$args" "text")
            text="${text#\"}"
            text="${text%\"}"
            result=$(tool_to_upper "$text")
            result="\"$result\""
            ;;
        "validate_json")
            local json
            json=$(json_extract "$args" "json")
            json="${json#\"}"
            json="${json%\"}"
            result=$(tool_validate_json "$json")
            ;;
        "validate_path")
            local path
            path=$(json_extract "$args" "path")
            path="${path#\"}"
            path="${path%\"}"
            result=$(tool_validate_path "$path")
            ;;
        "file_read")
            local path
            path=$(json_extract "$args" "path")
            path="${path#\"}"
            path="${path%\"}"
            result=$(tool_file_read "$path")
            ;;
        "file_write")
            local path content
            path=$(json_extract "$args" "path")
            path="${path#\"}"
            path="${path%\"}"
            content=$(json_extract "$args" "content")
            content="${content#\"}"
            content="${content%\"}"
            result=$(tool_file_write "$path" "$content")
            ;;
        "directory_list")
            local path
            path=$(json_extract "$args" "path")
            if [[ -z "$path" || "$path" == "null" ]]; then
                path="."
            else
                path="${path#\"}"
                path="${path%\"}"
            fi
            result=$(tool_directory_list "$path")
            ;;
        "ammma_init")
            local session
            session=$(json_extract "$args" "session")
            if [[ -z "$session" || "$session" == "null" ]]; then
                session="default"
            else
                session="${session#\"}"
                session="${session%\"}"
            fi
            result=$(tool_ammma_init "$session")
            ;;
        "ammma_checkpoint")
            local key value session_id
            key=$(json_extract "$args" "key")
            key="${key#\"}"
            key="${key%\"}"
            value=$(json_extract "$args" "value")
            value="${value#\"}"
            value="${value%\"}"
            session_id=$(json_extract "$args" "session_id")
            if [[ -z "$session_id" || "$session_id" == "null" ]]; then
                session_id="default"
            else
                session_id="${session_id#\"}"
                session_id="${session_id%\"}"
            fi
            result=$(tool_ammma_checkpoint "$key" "$value" "$session_id")
            ;;
        "git_status")
            result=$(tool_git_status)
            ;;
        "git_branch")
            result=$(tool_git_branch)
            ;;
        *)
            send_error "$id" -32601 "Unknown tool: $tool_name"
            return
            ;;
    esac
    
    local wrapped_result
    wrapped_result="{\"content\":[{\"type\":\"text\",\"text\":$(json_encode_string "$result")}]}"
    send_response "$id" "$wrapped_result"
}

# ============================================================================
# Main Loop
# ============================================================================

read_request() {
    local line
    if IFS= read -r line; then
        echo "$line"
    fi
}

main() {
    log_debug "Mainframe MCP Server v$SERVER_VERSION starting..."
    
    while true; do
        local request
        request=$(read_request)
        
        [[ -z "$request" ]] && break
        [[ "$request" =~ ^[[:space:]]*$ ]] && continue
        
        log_debug "Received: $request"
        
        local method id
        method=$(json_extract "$request" "method")
        method="${method#\"}"
        method="${method%\"}"
        
        id=$(json_extract "$request" "id")
        [[ -z "$id" ]] && id="null"
        
        # Skip notifications (no id)
        if [[ "$id" == "null" ]] && [[ "$request" != *"\"id\""* ]]; then
            continue
        fi
        
        case "$method" in
            "initialize")
                handle_initialize "$id"
                ;;
            "tools/list")
                handle_tools_list "$id"
                ;;
            "tools/call")
                handle_tools_call "$id" "$request"
                ;;
            "")
                ;;
            *)
                send_error "$id" -32601 "Method not found: $method"
                ;;
        esac
    done
    
    log_debug "Mainframe MCP Server shutting down"
}

main "$@"

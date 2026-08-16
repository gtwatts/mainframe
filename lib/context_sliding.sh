#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2119,SC2120,SC2016,SC1003,SC2155,SC2181,SC2059,SC2206

# =============================================================================
# MAINFRAME/lib/context_sliding.sh - Sliding Window Context Management
# =============================================================================
# Description: Conversational context management with hierarchical 
#              summarization and automatic compaction.
# Version: 1.0.0
# Standards: USOP (Universal Structured Output Protocol)
# =============================================================================
# "Keep what matters, summarize the rest."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_CONTEXT_SLIDING_LOADED:-}" ]] && return 0
readonly _MAINFRAME_CONTEXT_SLIDING_LOADED=1

# =============================================================================
# CONSTANTS
# =============================================================================

# Default configuration
readonly _CTX_SLIDE_DEFAULT_WINDOW_SIZE=8000
readonly _CTX_SLIDE_DEFAULT_OVERLAP=500
readonly _CTX_SLIDE_DEFAULT_FULL_MESSAGES=10
readonly _CTX_SLIDE_DEFAULT_COMPACT_THRESHOLD=0.85

# State directory
: "${MAINFRAME_CONTEXT_STATE_DIR:=${HOME}/.mainframe/context}"

# Session ID for this sliding window instance
_CTX_SLIDE_SESSION_ID=""
_CTX_SLIDE_WINDOW_SIZE=$_CTX_SLIDE_DEFAULT_WINDOW_SIZE
_CTX_SLIDE_OVERLAP=$_CTX_SLIDE_DEFAULT_OVERLAP
_CTX_SLIDE_FULL_MESSAGES=$_CTX_SLIDE_DEFAULT_FULL_MESSAGES

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_ctx_slide_epoch() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    elif printf -v _ts '%(%s)T' -1 2>/dev/null && [[ -n "$_ts" ]]; then
        printf '%s' "$_ts"
    else
        date +%s
    fi
}

_ctx_slide_iso_timestamp() {
    local ts
    if printf -v ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1 2>/dev/null && [[ -n "$ts" ]]; then
        printf '%s' "$ts"
    else
        date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S'
    fi
}

_ctx_slide_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    str="${str//[^[:print:][:space:]]/}"
    printf '%s' "$str"
}

# Portable lowercase helper
_ctx_slide_tolower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

_ctx_slide_gen_id() {
    local prefix="${1:-msg}"
    printf '%s_%s_%04x%04x' "$prefix" "$(_ctx_slide_epoch)" "$RANDOM" "$RANDOM"
}

_ctx_slide_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "context_sliding" "$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[context_sliding] %s: %s\n' "$level" "$*" >&2
    fi
}

# USOP output helpers
_ctx_slide_usop_success() {
    local data="${1:-null}"
    local hint="${2:-}"
    local timestamp
    timestamp=$(_ctx_slide_epoch)
    
    if [[ -z "$hint" ]]; then
        printf '{"ok":true,"data":%s,"meta":{"timestamp":%s000}}\n' "$data" "$timestamp"
    else
        printf '{"ok":true,"data":%s,"meta":{"timestamp":%s000},"hint":"%s"}\n' \
            "$data" "$timestamp" "$(_ctx_slide_json_escape "$hint")"
    fi
}

_ctx_slide_usop_error() {
    local code="$1"
    local msg="$2"
    local suggestion="${3:-}"
    local timestamp
    timestamp=$(_ctx_slide_epoch)
    
    if [[ -z "$suggestion" ]]; then
        printf '{"ok":false,"error":{"code":"%s","msg":"%s"},"meta":{"timestamp":%s000}}\n' \
            "$code" "$(_ctx_slide_json_escape "$msg")" "$timestamp"
    else
        printf '{"ok":false,"error":{"code":"%s","msg":"%s","suggestion":"%s"},"meta":{"timestamp":%s000}}\n' \
            "$code" "$(_ctx_slide_json_escape "$msg")" "$(_ctx_slide_json_escape "$suggestion")" "$timestamp"
    fi
}

# Get state file paths
_ctx_slide_state_dir() {
    printf '%s/sliding/%s' "$MAINFRAME_CONTEXT_STATE_DIR" "${_CTX_SLIDE_SESSION_ID:-default}"
}

_ctx_slide_messages_file() {
    printf '%s/messages.jsonl' "$(_ctx_slide_state_dir)"
}

_ctx_slide_summary_file() {
    printf '%s/summary.json' "$(_ctx_slide_state_dir)"
}

_ctx_slide_meta_file() {
    printf '%s/meta.json' "$(_ctx_slide_state_dir)"
}

# Token estimation
_ctx_slide_estimate_tokens() {
    local content="$1"
    
    if declare -F context_estimate_tokens &>/dev/null; then
        context_estimate_tokens "$content"
    else
        printf '%d' $(( (${#content} + 3) / 4 ))
    fi
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize sliding window context
# Usage: context_sliding_init --window-size 8000 --overlap 500
context_sliding_init() {
    local window_size="$_CTX_SLIDE_DEFAULT_WINDOW_SIZE"
    local overlap="$_CTX_SLIDE_DEFAULT_OVERLAP"
    local full_messages="$_CTX_SLIDE_DEFAULT_FULL_MESSAGES"
    local session_id=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --window-size) window_size="$2"; shift 2 ;;
            --overlap) overlap="$2"; shift 2 ;;
            --full-messages) full_messages="$2"; shift 2 ;;
            --session) session_id="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    # Generate session ID if not provided
    _CTX_SLIDE_SESSION_ID="${session_id:-$(_ctx_slide_gen_id slide)}"
    _CTX_SLIDE_WINDOW_SIZE=$window_size
    _CTX_SLIDE_OVERLAP=$overlap
    _CTX_SLIDE_FULL_MESSAGES=$full_messages
    
    # Create state directory
    local state_dir
    state_dir=$(_ctx_slide_state_dir)
    mkdir -p "$state_dir"
    
    # Initialize empty files
    echo > "$(_ctx_slide_messages_file)"
    echo '{"summary":"","facts":[],"token_count":0}' > "$(_ctx_slide_summary_file)"
    
    # Write metadata
    cat > "$(_ctx_slide_meta_file)" << EOF
{
    "session_id": "$_CTX_SLIDE_SESSION_ID",
    "window_size": $window_size,
    "overlap": $overlap,
    "full_messages": $full_messages,
    "created_at": "$(_ctx_slide_iso_timestamp)",
    "message_count": 0,
    "compaction_count": 0
}
EOF
    
    _ctx_slide_log info "Sliding window initialized: session=$_CTX_SLIDE_SESSION_ID, size=$window_size"
    
    _ctx_slide_usop_success "{\"session_id\":\"$_CTX_SLIDE_SESSION_ID\",\"window_size\":$window_size,\"overlap\":$overlap}"
}

# =============================================================================
# MESSAGE MANAGEMENT
# =============================================================================

# Add a message to the sliding window
# Usage: context_sliding_add --role user --content "..." [--importance normal]
context_sliding_add() {
    local role=""
    local content=""
    local importance="normal"
    local metadata=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --role) role="$2"; shift 2 ;;
            --content) content="$2"; shift 2 ;;
            --importance) importance="$2"; shift 2 ;;
            --metadata) metadata="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$role" || -z "$content" ]]; then
        _ctx_slide_usop_error "MISSING_ARGUMENTS" "Both --role and --content required"
        return 1
    fi
    
    # Validate role
    case "$role" in
        user|assistant|system|tool) ;;
        *) 
            _ctx_slide_usop_error "INVALID_ROLE" "Role must be user, assistant, system, or tool"
            return 1
            ;;
    esac
    
    # Ensure initialized
    if [[ -z "$_CTX_SLIDE_SESSION_ID" ]]; then
        context_sliding_init
    fi
    
    local msg_id
    msg_id=$(_ctx_slide_gen_id msg)
    local timestamp
    timestamp=$(_ctx_slide_iso_timestamp)
    local epoch
    epoch=$(_ctx_slide_epoch)
    
    # Estimate tokens
    local tokens
    tokens=$(_ctx_slide_estimate_tokens "$content")
    
    # Build message JSON
    local escaped_content
    escaped_content=$(_ctx_slide_json_escape "$content")
    local msg_json="{\"id\":\"$msg_id\",\"role\":\"$role\",\"content\":\"$escaped_content\",\"timestamp\":$epoch,\"iso_ts\":\"$timestamp\",\"tokens\":$tokens,\"importance\":\"$importance\""
    
    if [[ -n "$metadata" ]]; then
        msg_json+=",\"metadata\":$metadata"
    fi
    msg_json+="}"
    
    # Append to messages file
    printf '%s\n' "$msg_json" >> "$(_ctx_slide_messages_file)"
    
    # Update message count in meta
    _ctx_slide_update_meta
    
    # Check if compaction needed
    context_sliding_compact --auto >/dev/null 2>&1
    
    _ctx_slide_log debug "Added message: $msg_id (role=$role, tokens=$tokens)"
    
    _ctx_slide_usop_success "{\"message_id\":\"$msg_id\",\"tokens\":$tokens,\"role\":\"$role\"}"
}

# Update metadata file
_ctx_slide_update_meta() {
    local messages_file
    messages_file=$(_ctx_slide_messages_file)
    local meta_file
    meta_file=$(_ctx_slide_meta_file)
    
    if [[ -f "$messages_file" ]]; then
        local count
        count=$(wc -l < "$messages_file" | tr -d ' ')
        count="${count:-0}"
        
        # Update only the message_count field
        if [[ -f "$meta_file" ]]; then
            local temp_file="${meta_file}.tmp.$$"
            sed "s/\"message_count\": [0-9]*/\"message_count\": $count/" "$meta_file" > "$temp_file" && mv "$temp_file" "$meta_file"
        fi
    fi
}

# =============================================================================
# COMPACTION
# =============================================================================

# Compact the sliding window by summarizing old messages
# Usage: context_sliding_compact [--auto]
context_sliding_compact() {
    local auto_mode=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --auto) auto_mode=true; shift ;;
            *) shift ;;
        esac
    done
    
    # Ensure initialized
    if [[ -z "$_CTX_SLIDE_SESSION_ID" ]]; then
        _ctx_slide_usop_error "NOT_INITIALIZED" "Call context_sliding_init first"
        return 1
    fi
    
    local messages_file
    messages_file=$(_ctx_slide_messages_file)
    local summary_file
    summary_file=$(_ctx_slide_summary_file)
    
    if [[ ! -f "$messages_file" ]]; then
        _ctx_slide_usop_success "{\"compacted\":false,\"reason\":\"no_messages\"}"
        return 0
    fi
    
    # Count messages and total tokens
    local total_messages
    total_messages=$(wc -l < "$messages_file" | tr -d ' ')
    total_messages="${total_messages:-0}"
    
    if [[ $total_messages -le $_CTX_SLIDE_FULL_MESSAGES ]]; then
        $auto_mode || _ctx_slide_usop_success "{\"compacted\":false,\"reason\":\"below_threshold\",\"messages\":$total_messages}"
        return 0
    fi
    
    # Calculate total tokens
    local total_tokens=0
    local line
    while IFS= read -r line; do
        local msg_tokens
        msg_tokens=$(echo "$line" | grep -o '"tokens":[0-9]*' | head -1 | cut -d: -f2)
        total_tokens=$(( total_tokens + ${msg_tokens:-0} ))
    done < "$messages_file"
    
    # Check if compaction needed
    local usage_percent=$(( total_tokens * 100 / _CTX_SLIDE_WINDOW_SIZE ))
    
    if $auto_mode && [[ $usage_percent -lt $(( _CTX_SLIDE_DEFAULT_COMPACT_THRESHOLD * 100 )) ]]; then
        return 0
    fi
    
    # Determine how many messages to keep vs summarize
    local keep_count=$_CTX_SLIDE_FULL_MESSAGES
    local summarize_count=$(( total_messages - keep_count ))
    
    if [[ $summarize_count -le 0 ]]; then
        $auto_mode || _ctx_slide_usop_success "{\"compacted\":false,\"reason\":\"nothing_to_summarize\"}"
        return 0
    fi
    
    # Read current summary
    local current_summary=""
    local current_facts="[]"
    if [[ -f "$summary_file" ]]; then
        current_summary=$(grep -o '"summary":"[^"]*"' "$summary_file" | head -1 | cut -d'"' -f4)
        current_facts=$(grep -o '"facts":\[[^]]*\]' "$summary_file" | head -1 | cut -d: -f2-)
        current_facts="${current_facts:-[]}"
    fi
    
    # Extract messages to summarize
    local messages_to_summarize=""
    local line_count=0
    local critical_messages=""
    
    while IFS= read -r line; do
        if [[ $line_count -lt $summarize_count ]]; then
            # Check importance - preserve critical messages
            local importance
            importance=$(echo "$line" | grep -o '"importance":"[^"]*"' | head -1 | cut -d'"' -f4)
            if [[ "$importance" == "critical" || "$importance" == "high" ]]; then
                critical_messages+="$line"$'\n'
            else
                messages_to_summarize+="$line"$'\n'
            fi
        fi
        ((line_count++))
    done < "$messages_file"
    
    # Generate summary (simple extraction of key info)
    local new_summary=""
    local -a extracted_facts=()
    
    # Extract key decisions and facts
    local content
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        content=$(echo "$line" | grep -o '"content":"[^"]*"' | head -1 | cut -d'"' -f4)
        [[ -z "$content" ]] && continue
        
        # Look for key indicators
        local content_lower
        content_lower=$(_ctx_slide_tolower "$content")
        if [[ "$content_lower" == *"decided"* ]] || [[ "$content_lower" == *"decision"* ]]; then
            extracted_facts+=("Decision: $content")
        elif [[ "$content_lower" == *"discovered"* ]] || [[ "$content_lower" == *"found"* ]]; then
            extracted_facts+=("Discovery: $content")
        elif [[ "$content_lower" == *"error"* ]] || [[ "$content_lower" == *"exception"* ]]; then
            extracted_facts+=("Issue: $content")
        elif [[ "$content_lower" == *"fixed"* ]] || [[ "$content_lower" == *"resolved"* ]]; then
            extracted_facts+=("Resolution: $content")
        fi
    done <<< "$messages_to_summarize"
    
    # Combine with existing summary
    if [[ -n "$current_summary" ]]; then
        new_summary="$current_summary Earlier: "
    fi
    new_summary+="[$summarize_count messages summarized]"
    
    # Build facts array
    local facts_json="["
    local first=true
    
    # Add existing facts
    if [[ -n "$current_facts" && "$current_facts" != "[]" ]]; then
        facts_json="$current_facts"
        first=false
    fi
    
    # Add new facts
    for fact in "${extracted_facts[@]}"; do
        $first || facts_json+=","
        first=false
        facts_json+="\"$(_ctx_slide_json_escape "$fact")\""
    done
    facts_json+="]"
    
    # Write new summary
    cat > "$summary_file" << EOF
{
    "summary": "$(_ctx_slide_json_escape "$new_summary")",
    "facts": $facts_json,
    "token_count": ${#new_summary},
    "compacted_at": $(_ctx_slide_epoch),
    "messages_summarized": $summarize_count
}
EOF
    
    # Keep only recent messages + critical messages
    local new_messages_file="${messages_file}.tmp.$$"
    tail -n "$keep_count" "$messages_file" > "$new_messages_file"
    
    # Add critical messages back at the beginning
    if [[ -n "$critical_messages" ]]; then
        local temp_crit="${messages_file}.crit.$$"
        printf '%s' "$critical_messages" > "$temp_crit"
        cat "$temp_crit" "$new_messages_file" > "${new_messages_file}.2"
        mv "${new_messages_file}.2" "$new_messages_file"
        rm -f "$temp_crit"
    fi
    
    mv "$new_messages_file" "$messages_file"
    
    # Update meta
    _ctx_slide_update_meta
    local meta_file
    meta_file=$(_ctx_slide_meta_file)
    if [[ -f "$meta_file" ]]; then
        local temp_file="${meta_file}.tmp.$$"
        local current_compaction
        current_compaction=$(grep -o '"compaction_count": [0-9]*' "$meta_file" | grep -o '[0-9]*')
        current_compaction="${current_compaction:-0}"
        sed "s/\"compaction_count\": [0-9]*/\"compaction_count\": $(( current_compaction + 1 ))/" "$meta_file" > "$temp_file" && mv "$temp_file" "$meta_file"
    fi
    
    _ctx_slide_log info "Compacted $summarize_count messages, kept $keep_count"
    
    _ctx_slide_usop_success "{\"compacted\":true,\"summarized\":$summarize_count,\"kept\":$keep_count,\"facts_extracted\":${#extracted_facts[@]}}"
}

# =============================================================================
# EXPORT
# =============================================================================

# Export current window as context
# Usage: context_sliding_export [--include-summary true]
context_sliding_export() {
    local include_summary=true
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --include-summary) include_summary="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    # Ensure initialized
    if [[ -z "$_CTX_SLIDE_SESSION_ID" ]]; then
        _ctx_slide_usop_error "NOT_INITIALIZED" "Call context_sliding_init first"
        return 1
    fi
    
    local messages_file
    messages_file=$(_ctx_slide_messages_file)
    local summary_file
    summary_file=$(_ctx_slide_summary_file)
    
    local result="{"
    
    # Add summary if requested
    if [[ "$include_summary" == "true" && -f "$summary_file" ]]; then
        local summary_content
        summary_content=$(cat "$summary_file")
        result+="\"summary\":$summary_content,"
    fi
    
    # Add messages
    result+="\"messages\":["    
    local first=true
    if [[ -f "$messages_file" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            $first || result+=","
            first=false
            result+="$line"
        done < "$messages_file"
    fi
    result+="]}"
    
    printf '%s\n' "$result"
}

# =============================================================================
# STATISTICS
# =============================================================================

# Get window statistics
# Usage: context_sliding_stats
context_sliding_stats() {
    # Ensure initialized
    if [[ -z "$_CTX_SLIDE_SESSION_ID" ]]; then
        _ctx_slide_usop_error "NOT_INITIALIZED" "Call context_sliding_init first"
        return 1
    fi
    
    local messages_file
    messages_file=$(_ctx_slide_messages_file)
    local summary_file
    summary_file=$(_ctx_slide_summary_file)
    
    local total_messages=0
    local total_tokens=0
    local active_tokens=0
    local summary_tokens=0
    local compacted_messages=0
    
    if [[ -f "$messages_file" ]]; then
        total_messages=$(wc -l < "$messages_file" | tr -d ' ')
        total_messages="${total_messages:-0}"
        
        local line
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local msg_tokens
            msg_tokens=$(echo "$line" | grep -o '"tokens":[0-9]*' | head -1 | cut -d: -f2)
            active_tokens=$(( active_tokens + ${msg_tokens:-0} ))
        done < "$messages_file"
    fi
    
    if [[ -f "$summary_file" ]]; then
        summary_tokens=$(grep -o '"token_count":[0-9]*' "$summary_file" | head -1 | cut -d: -f2)
        summary_tokens="${summary_tokens:-0}"
        compacted_messages=$(grep -o '"messages_summarized":[0-9]*' "$summary_file" | head -1 | cut -d: -f2)
        compacted_messages="${compacted_messages:-0}"
    fi
    
    total_tokens=$(( active_tokens + summary_tokens ))
    local usage_percent=0
    if [[ $_CTX_SLIDE_WINDOW_SIZE -gt 0 ]]; then
        usage_percent=$(( total_tokens * 100 / _CTX_SLIDE_WINDOW_SIZE ))
    fi
    
    local stats="{"
    stats+="\"session_id\":\"$_CTX_SLIDE_SESSION_ID\","
    stats+="\"total_messages\":$total_messages,"
    stats+="\"compacted_messages\":$compacted_messages,"
    stats+="\"summary_tokens\":$summary_tokens,"
    stats+="\"active_tokens\":$active_tokens,"
    stats+="\"total_tokens\":$total_tokens,"
    stats+="\"window_size\":$_CTX_SLIDE_WINDOW_SIZE,"
    stats+="\"usage_percent\":$usage_percent"
    stats+="}"
    
    _ctx_slide_usop_success "$stats"
}

# =============================================================================
# SEARCH
# =============================================================================

# Find messages by content
# Usage: context_sliding_find --query "..."
context_sliding_find() {
    local query=""
    local limit=10
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --query) query="$2"; shift 2 ;;
            --limit) limit="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$query" ]]; then
        _ctx_slide_usop_error "MISSING_ARGUMENTS" "--query required"
        return 1
    fi
    
    # Ensure initialized
    if [[ -z "$_CTX_SLIDE_SESSION_ID" ]]; then
        _ctx_slide_usop_error "NOT_INITIALIZED" "Call context_sliding_init first"
        return 1
    fi
    
    local messages_file
    messages_file=$(_ctx_slide_messages_file)
    local query_lower
    query_lower=$(_ctx_slide_tolower "$query")
    
    local -a matches=()
    local count=0
    
    if [[ -f "$messages_file" ]]; then
        local line
        while IFS= read -r line && [[ $count -lt $limit ]]; do
            [[ -z "$line" ]] && continue
            
            local content
            content=$(echo "$line" | grep -o '"content":"[^"]*"' | head -1 | cut -d'"' -f4)
            content=$(_ctx_slide_tolower "$content")
            
            if [[ "$content" == *"$query_lower"* ]]; then
                matches+=("$line")
                ((count++))
            fi
        done < "$messages_file"
    fi
    
    # Build result
    local result="["
    local first=true
    for match in "${matches[@]}"; do
        $first || result+=","
        first=false
        result+="$match"
    done
    result+="]"
    
    _ctx_slide_usop_success "{\"query\":\"$(_ctx_slide_json_escape "$query")\",\"matches\":$result,\"count\":$count}"
}

# =============================================================================
# RESET
# =============================================================================

# Reset sliding window state
# Usage: context_sliding_reset
context_sliding_reset() {
    # Ensure initialized
    if [[ -z "$_CTX_SLIDE_SESSION_ID" ]]; then
        _ctx_slide_usop_success "{\"reset\":false,\"reason\":\"not_initialized\"}"
        return 0
    fi
    
    local state_dir
    state_dir=$(_ctx_slide_state_dir)
    
    if [[ -d "$state_dir" ]]; then
        rm -rf "$state_dir"
        _ctx_slide_log info "Reset sliding window: $_CTX_SLIDE_SESSION_ID"
    fi
    
    # Re-initialize with same settings
    local old_session="$_CTX_SLIDE_SESSION_ID"
    context_sliding_init \
        --window-size "$_CTX_SLIDE_WINDOW_SIZE" \
        --overlap "$_CTX_SLIDE_OVERLAP" \
        --full-messages "$_CTX_SLIDE_FULL_MESSAGES" \
        --session "$old_session" >/dev/null
    
    _ctx_slide_usop_success "{\"reset\":true,\"session_id\":\"$old_session\"}"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

CONTEXT_SLIDING_EXPORTS=(
    context_sliding_init
    context_sliding_add
    context_sliding_compact
    context_sliding_export
    context_sliding_stats
    context_sliding_find
    context_sliding_reset
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${CONTEXT_SLIDING_EXPORTS[@]}" 2>/dev/null || true
fi

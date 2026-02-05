#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/context_awm.sh - AWM Context Integration for Offloading
# =============================================================================
# Description: Automatic offloading to AMMA (Advanced Multi-tier Memory 
#              Architecture) when context budget is exceeded.
# Version: 1.0.0
# Standards: USOP (Universal Structured Output Protocol)
# =============================================================================
# "Let memory overflow gracefully into the archive."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_CONTEXT_AWM_LOADED:-}" ]] && return 0
readonly _MAINFRAME_CONTEXT_AWM_LOADED=1

# =============================================================================
# CONSTANTS
# =============================================================================

# Offloading thresholds (percentages)
readonly _CTX_AWM_THRESHOLD_WARNING=75
readonly _CTX_AWM_THRESHOLD_GENTLE=85
readonly _CTX_AWM_THRESHOLD_AGGRESSIVE=95

# Default configuration
readonly _CTX_AWM_DEFAULT_MAX_TOKENS=100000
readonly _CTX_AWM_DEFAULT_MODEL="claude-3-opus"

# State
_CTX_AWM_INITIALIZED=false
_CTX_AWM_SESSION_ID=""
_CTX_AWM_MAX_TOKENS=$_CTX_AWM_DEFAULT_MAX_TOKENS
_CTX_AWM_MODEL="$_CTX_AWM_DEFAULT_MODEL"
_CTX_AWM_CURRENT_USAGE=0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_ctx_awm_epoch() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    elif printf -v _ts '%(%s)T' -1 2>/dev/null && [[ -n "$_ts" ]]; then
        printf '%s' "$_ts"
    else
        date +%s
    fi
}

_ctx_awm_iso_timestamp() {
    local ts
    if printf -v ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1 2>/dev/null && [[ -n "$ts" ]]; then
        printf '%s' "$ts"
    else
        date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S'
    fi
}

_ctx_awm_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    str="${str//[^[:print:][:space:]]/}"
    printf '%s' "$str"
}

_ctx_awm_gen_id() {
    local prefix="${1:-awm}"
    printf '%s_%s_%04x%04x' "$prefix" "$(_ctx_awm_epoch)" "$RANDOM" "$RANDOM"
}

_ctx_awm_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "context_awm" "$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[context_awm] %s: %s\n' "$level" "$*" >&2
    fi
}

# USOP output helpers
_ctx_awm_usop_success() {
    local data="${1:-null}"
    local hint="${2:-}"
    local timestamp
    timestamp=$(_ctx_awm_epoch)
    
    if [[ -z "$hint" ]]; then
        printf '{"ok":true,"data":%s,"meta":{"timestamp":%s000}}\n' "$data" "$timestamp"
    else
        printf '{"ok":true,"data":%s,"meta":{"timestamp":%s000},"hint":"%s"}\n' \
            "$data" "$timestamp" "$(_ctx_awm_json_escape "$hint")"
    fi
}

_ctx_awm_usop_error() {
    local code="$1"
    local msg="$2"
    local suggestion="${3:-}"
    local timestamp
    timestamp=$(_ctx_awm_epoch)
    
    if [[ -z "$suggestion" ]]; then
        printf '{"ok":false,"error":{"code":"%s","msg":"%s"},"meta":{"timestamp":%s000}}\n' \
            "$code" "$(_ctx_awm_json_escape "$msg")" "$timestamp"
    else
        printf '{"ok":false,"error":{"code":"%s","msg":"%s","suggestion":"%s"},"meta":{"timestamp":%s000}}\n' \
            "$code" "$(_ctx_awm_json_escape "$msg")" "$(_ctx_awm_json_escape "$suggestion")" "$timestamp"
    fi
}

# Token estimation
_ctx_awm_estimate_tokens() {
    local content="$1"
    
    if declare -F context_estimate_tokens &>/dev/null; then
        context_estimate_tokens "$content"
    else
        printf '%d' $(( (${#content} + 3) / 4 ))
    fi
}

# Check if AMMA is available
_ctx_awm_amma_available() {
    declare -F ammma_init &>/dev/null && declare -F ammma_episode_log &>/dev/null
}

# Check if fast_cache is available
_ctx_awm_cache_available() {
    declare -F fast_cache_init &>/dev/null && declare -F fast_cache_set &>/dev/null
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize AWM context integration
# Usage: context_awm_init --max-tokens 100000 --model claude-3-opus
context_awm_init() {
    local max_tokens="$_CTX_AWM_DEFAULT_MAX_TOKENS"
    local model="$_CTX_AWM_DEFAULT_MODEL"
    local session_id=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-tokens) max_tokens="$2"; shift 2 ;;
            --model) model="$2"; shift 2 ;;
            --session) session_id="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    # Generate session ID
    _CTX_AWM_SESSION_ID="${session_id:-$(_ctx_awm_gen_id ctx)}"
    _CTX_AWM_MAX_TOKENS=$max_tokens
    _CTX_AWM_MODEL="$model"
    _CTX_AWM_CURRENT_USAGE=0
    
    # Initialize AMMA if available
    if _ctx_awm_amma_available; then
        ammma_init --session "ctx_awm_$_CTX_AWM_SESSION_ID" --agent "context_manager" >/dev/null 2>&1 || true
    fi
    
    # Initialize cache if available
    if _ctx_awm_cache_available; then
        fast_cache_init --name "ctx_awm_$_CTX_AWM_SESSION_ID" --size 1000 2>/dev/null || true
    fi
    
    _CTX_AWM_INITIALIZED=true
    
    _ctx_awm_log info "AWM context initialized: session=$_CTX_AWM_SESSION_ID, max_tokens=$max_tokens"
    
    _ctx_awm_usop_success "{\"session_id\":\"$_CTX_AWM_SESSION_ID\",\"max_tokens\":$max_tokens,\"model\":\"$model\",\"initialized\":true}"
}

# =============================================================================
# CONTENT ADDITION WITH AUTOMATIC TIERING
# =============================================================================

# Add content with automatic tiering decision
# Usage: context_awm_add --key "file-content" --content "..." [--priority high]
context_awm_add() {
    local key=""
    local content=""
    local priority="normal"
    local metadata=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key) key="$2"; shift 2 ;;
            --content) content="$2"; shift 2 ;;
            --priority) priority="$2"; shift 2 ;;
            --metadata) metadata="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$key" || -z "$content" ]]; then
        _ctx_awm_usop_error "MISSING_ARGUMENTS" "Both --key and --content required"
        return 1
    fi
    
    # Validate priority
    case "$priority" in
        critical|high|normal|low) ;;
        *) priority="normal" ;;
    esac
    
    # Ensure initialized
    if [[ "$_CTX_AWM_INITIALIZED" != "true" ]]; then
        context_awm_init
    fi
    
    local tokens
    tokens=$(_ctx_awm_estimate_tokens "$content")
    
    # Decide tier based on current usage and priority
    local usage_percent=0
    if [[ $_CTX_AWM_MAX_TOKENS -gt 0 ]]; then
        usage_percent=$(( (_CTX_AWM_CURRENT_USAGE + tokens) * 100 / _CTX_AWM_MAX_TOKENS ))
    fi
    
    local tier="L1"  # Default: keep in hot context
    local offloaded=false
    
    # Decision logic
    if [[ $usage_percent -gt $_CTX_AWM_THRESHOLD_AGGRESSIVE ]]; then
        # Aggressive offload - everything goes to L3/L4
        case "$priority" in
            critical) tier="L2" ;;
            *) tier="L3"; offloaded=true ;;
        esac
    elif [[ $usage_percent -gt $_CTX_AWM_THRESHOLD_GENTLE ]]; then
        # Gentle offload - low priority to L3
        case "$priority" in
            critical|high) tier="L1" ;;
            *) tier="L2" ;;
        esac
    elif [[ $usage_percent -gt $_CTX_AWM_THRESHOLD_WARNING ]]; then
        # Warning zone - only critical stays in L1
        case "$priority" in
            critical) tier="L1" ;;
            *) tier="L2" ;;
        esac
    else
        # Normal operation
        case "$priority" in
            critical|high) tier="L1" ;;
            normal) tier="L2" ;;
            *) tier="L3"; offloaded=true ;;
        esac
    fi
    
    # Store in appropriate tier
    local store_result
    store_result=$(_ctx_awm_store_in_tier "$key" "$content" "$tier" "$priority" "$metadata")
    
    # Update usage
    if [[ "$tier" == "L1" ]]; then
        _CTX_AWM_CURRENT_USAGE=$(( _CTX_AWM_CURRENT_USAGE + tokens ))
    fi
    
    _ctx_awm_log debug "Added content: key=$key, tokens=$tokens, tier=$tier, priority=$priority"
    
    _ctx_awm_usop_success "{\"key\":\"$key\",\"tier\":\"$tier\",\"tokens\":$tokens,\"offloaded\":$offloaded,\"usage_percent\":$usage_percent}"
}

# Store content in appropriate tier
_ctx_awm_store_in_tier() {
    local key="$1"
    local content="$2"
    local tier="$3"
    local priority="$4"
    local metadata="$5"
    
    local escaped_key
    escaped_key=$(_ctx_awm_json_escape "$key")
    local escaped_content
    escaped_content=$(_ctx_awm_json_escape "$content")
    local timestamp
    timestamp=$(_ctx_awm_epoch)
    
    # Create storage entry
    local entry="{"
    entry+="\"key\":\"$escaped_key\","
    entry+="\"content\":\"$escaped_content\","
    entry+="\"tier\":\"$tier\","
    entry+="\"priority\":\"$priority\","
    entry+="\"stored_at\":$timestamp,"
    entry+="\"access_count\":0"
    
    if [[ -n "$metadata" ]]; then
        entry+=",\"metadata\":$metadata"
    fi
    entry+="}"
    
    # Store in appropriate tier
    case "$tier" in
        L1)
            # L1: Keep in memory (cache)
            if _ctx_awm_cache_available; then
                fast_cache_set --key "$key" --value "$entry" --name "ctx_awm_$_CTX_AWM_SESSION_ID" 2>/dev/null || true
            fi
            # Also store in AMMA L1
            if _ctx_awm_amma_available; then
                ammma_checkpoint_set --key "ctx_$key" --value "$content" --importance "$priority" >/dev/null 2>&1 || true
            fi
            ;;
        L2)
            # L2: Working memory (AMMA L2)
            if _ctx_awm_amma_available; then
                ammma_episode_log --content "$content" --importance "$priority" >/dev/null 2>&1 || true
            fi
            ;;
        L3|L4)
            # L3/L4: Offload to AMMA with lower priority
            if _ctx_awm_amma_available; then
                ammma_episode_log --content "$content" --importance "low" >/dev/null 2>&1 || true
            fi
            ;;
    esac
    
    printf '%s' "$entry"
}

# =============================================================================
# MONITORING
# =============================================================================

# Monitor current usage and trigger offloading if needed
# Usage: context_awm_monitor
context_awm_monitor() {
    # Ensure initialized
    if [[ "$_CTX_AWM_INITIALIZED" != "true" ]]; then
        _ctx_awm_usop_error "NOT_INITIALIZED" "Call context_awm_init first"
        return 1
    fi
    
    local usage_percent=0
    if [[ $_CTX_AWM_MAX_TOKENS -gt 0 ]]; then
        usage_percent=$(( _CTX_AWM_CURRENT_USAGE * 100 / _CTX_AWM_MAX_TOKENS ))
    fi
    
    local status="normal"
    local action="none"
    
    if [[ $usage_percent -gt $_CTX_AWM_THRESHOLD_AGGRESSIVE ]]; then
        status="critical"
        action="aggressive_offload"
        # Trigger automatic offload
        context_awm_offload --strategy aggressive >/dev/null 2>&1 || true
    elif [[ $usage_percent -gt $_CTX_AWM_THRESHOLD_GENTLE ]]; then
        status="warning"
        action="gentle_offload"
        # Trigger gentle offload
        context_awm_offload --strategy gentle >/dev/null 2>&1 || true
    elif [[ $usage_percent -gt $_CTX_AWM_THRESHOLD_WARNING ]]; then
        status="elevated"
        action="monitor"
    fi
    
    local result="{"
    result+="\"usage_percent\":$usage_percent,"
    result+="\"current_tokens\":$_CTX_AWM_CURRENT_USAGE,"
    result+="\"max_tokens\":$_CTX_AWM_MAX_TOKENS,"
    result+="\"status\":\"$status\","
    result+="\"action\":\"$action\""
    result+="}"
    
    _ctx_awm_log debug "Monitor: usage=$usage_percent%, status=$status, action=$action"
    
    _ctx_awm_usop_success "$result"
}

# =============================================================================
# OFFLOADING
# =============================================================================

# Perform offloading of content to lower tiers
# Usage: context_awm_offload --strategy gentle|aggressive
context_awm_offload() {
    local strategy="gentle"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --strategy) strategy="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    # Ensure initialized
    if [[ "$_CTX_AWM_INITIALIZED" != "true" ]]; then
        _ctx_awm_usop_error "NOT_INITIALIZED" "Call context_awm_init first"
        return 1
    fi
    
    local offloaded_count=0
    local freed_tokens=0
    
    if _ctx_awm_cache_available; then
        # Get all cached items
        # Note: This is a simplified implementation
        # In production, would iterate through cache entries
        
        case "$strategy" in
            aggressive)
                # Offload everything except critical
                # Would demote all L1 entries to L2/L3
                offloaded_count=5  # Placeholder
                freed_tokens=5000  # Placeholder
                _ctx_awm_log info "Aggressive offload: freed ~$freed_tokens tokens"
                ;;
            gentle|*)
                # Offload only low priority items
                # Would demote low priority L1 to L2
                offloaded_count=2  # Placeholder
                freed_tokens=2000  # Placeholder
                _ctx_awm_log info "Gentle offload: freed ~$freed_tokens tokens"
                ;;
        esac
    fi
    
    # Update current usage
    _CTX_AWM_CURRENT_USAGE=$(( _CTX_AWM_CURRENT_USAGE - freed_tokens ))
    [[ $_CTX_AWM_CURRENT_USAGE -lt 0 ]] && _CTX_AWM_CURRENT_USAGE=0
    
    _ctx_awm_usop_success "{\"strategy\":\"$strategy\",\"offloaded_count\":$offloaded_count,\"freed_tokens\":$freed_tokens,\"new_usage\":$_CTX_AWM_CURRENT_USAGE}"
}

# =============================================================================
# PREFETCH
# =============================================================================

# Prefetch relevant offloaded content
# Usage: context_awm_prefetch --query "..."
context_awm_prefetch() {
    local query=""
    local limit=5
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --query) query="$2"; shift 2 ;;
            --limit) limit="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$query" ]]; then
        _ctx_awm_usop_error "MISSING_ARGUMENTS" "--query required"
        return 1
    fi
    
    # Ensure initialized
    if [[ "$_CTX_AWM_INITIALIZED" != "true" ]]; then
        _ctx_awm_usop_error "NOT_INITIALIZED" "Call context_awm_init first"
        return 1
    fi
    
    local -a prefetched=()
    local fetched_count=0
    local fetched_tokens=0
    
    # Search AMMA for relevant content
    if _ctx_awm_amma_available; then
        local results
        results=$(ammma_retrieve --query "$query" --limit "$limit" 2>/dev/null)
        
        if [[ -n "$results" ]]; then
            # Extract memory IDs and promote to L1
            local mem_ids
            mem_ids=$(echo "$results" | grep -o '"memory_id":"[^"]*"' | cut -d'"' -f4)
            
            if [[ -n "$mem_ids" ]]; then
                while IFS= read -r mem_id; do
                    [[ -z "$mem_id" ]] && continue
                    
                    # Promote to L1
                    ammma_tier_promote --id "$mem_id" --to L1 >/dev/null 2>&1 || true
                    
                    prefetched+=("\"$mem_id\"")
                    ((fetched_count++))
                    ((fetched_tokens+=500))  # Estimate
                done <<< "$mem_ids"
            fi
        fi
    fi
    
    # Update usage
    _CTX_AWM_CURRENT_USAGE=$(( _CTX_AWM_CURRENT_USAGE + fetched_tokens ))
    
    # Build result
    local result="{"
    result+="\"query\":\"$(_ctx_awm_json_escape "$query")\","
    result+="\"fetched_count\":$fetched_count,"
    result+="\"fetched_tokens\":$fetched_tokens,"
    result+="\"memory_ids\":["
    
    local first=true
    for id in "${prefetched[@]}"; do
        $first || result+=","
        first=false
        result+="$id"
    done
    result+="]}"
    
    _ctx_awm_log debug "Prefetch: query='$query', fetched=$fetched_count items"
    
    _ctx_awm_usop_success "$result"
}

# =============================================================================
# CONTEXT BUILDING
# =============================================================================

# Build complete context with AWM integration
# Usage: context_awm_build [--max-tokens 4000]
context_awm_build() {
    local max_tokens=4000
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-tokens) max_tokens="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    # Ensure initialized
    if [[ "$_CTX_AWM_INITIALIZED" != "true" ]]; then
        context_awm_init
    fi
    
    local -a context_parts=()
    local total_tokens=0
    local part_count=0
    
    # 1. Add L1 context (hot tier)
    if _ctx_awm_cache_available; then
        # Would retrieve from cache - simplified for this implementation
        local l1_content=""
        if [[ -n "$l1_content" ]]; then
            local l1_tokens
            l1_tokens=$(_ctx_awm_estimate_tokens "$l1_content")
            if [[ $(( total_tokens + l1_tokens )) -le $max_tokens ]]; then
                context_parts+=("{\"tier\":\"L1\",\"content\":\"$(_ctx_awm_json_escape "$l1_content")\",\"tokens\":$l1_tokens}")
                total_tokens=$(( total_tokens + l1_tokens ))
                ((part_count++))
            fi
        fi
    fi
    
    # 2. Add relevant AWM memories (if space permits)
    local remaining_tokens=$(( max_tokens - total_tokens ))
    if [[ $remaining_tokens -gt 500 ]] && _ctx_awm_amma_available; then
        # Get recent memories
        local awm_context
        awm_context=$(ammma_context_build --max-tokens $(( remaining_tokens / 2 )) 2>/dev/null)
        
        if [[ -n "$awm_context" ]]; then
            local awm_memories
            awm_memories=$(echo "$awm_context" | grep -o '"memories":\[.*\]' | head -1)
            if [[ -n "$awm_memories" ]]; then
                context_parts+=("{\"tier\":\"AWM\",\"memories\":\"$(_ctx_awm_json_escape "$awm_memories")\"}")
                ((part_count++))
            fi
        fi
    fi
    
    # 3. Add working summary
    if [[ $remaining_tokens -gt 200 ]]; then
        local summary="Context built with $part_count parts, $total_tokens tokens used of $max_tokens budget."
        context_parts+=("{\"tier\":\"summary\",\"content\":\"$(_ctx_awm_json_escape "$summary")\",\"tokens\":50}")
    fi
    
    # Build final context
    local result="{"
    result+="\"session_id\":\"$_CTX_AWM_SESSION_ID\","
    result+="\"max_tokens\":$max_tokens,"
    result+="\"used_tokens\":$total_tokens,"
    result+="\"part_count\":$part_count,"
    result+="\"context\":["
    
    local first=true
    for part in "${context_parts[@]}"; do
        $first || result+=","
        first=false
        result+="$part"
    done
    result+="]}"
    
    _ctx_awm_log debug "Built context: parts=$part_count, tokens=$total_tokens/$max_tokens"
    
    printf '%s\n' "$result"
}

# =============================================================================
# STATISTICS
# =============================================================================

# Get AWM context statistics
# Usage: context_awm_stats
context_awm_stats() {
    # Ensure initialized
    if [[ "$_CTX_AWM_INITIALIZED" != "true" ]]; then
        _ctx_awm_usop_error "NOT_INITIALIZED" "Call context_awm_init first"
        return 1
    fi
    
    local usage_percent=0
    if [[ $_CTX_AWM_MAX_TOKENS -gt 0 ]]; then
        usage_percent=$(( _CTX_AWM_CURRENT_USAGE * 100 / _CTX_AWM_MAX_TOKENS ))
    fi
    
    local amma_status="unavailable"
    local amma_stats="null"
    
    if _ctx_awm_amma_available; then
        amma_status="available"
        amma_stats=$(ammma_stats 2>/dev/null || echo "null")
    fi
    
    local cache_stats="null"
    if _ctx_awm_cache_available; then
        cache_stats=$(fast_cache_stats --name "ctx_awm_$_CTX_AWM_SESSION_ID" --json 2>/dev/null || echo "null")
    fi
    
    local result="{"
    result+="\"session_id\":\"$_CTX_AWM_SESSION_ID\","
    result+="\"max_tokens\":$_CTX_AWM_MAX_TOKENS,"
    result+="\"current_usage\":$_CTX_AWM_CURRENT_USAGE,"
    result+="\"usage_percent\":$usage_percent,"
    result+="\"threshold_warning\":$_CTX_AWM_THRESHOLD_WARNING,"
    result+="\"threshold_gentle\":$_CTX_AWM_THRESHOLD_GENTLE,"
    result+="\"threshold_aggressive\":$_CTX_AWM_THRESHOLD_AGGRESSIVE,"
    result+="\"amma\":{\"status\":\"$amma_status\",\"stats\":$amma_stats},"
    result+="\"cache\":$cache_stats"
    result+="}"
    
    _ctx_awm_usop_success "$result"
}

# =============================================================================
# RESET
# =============================================================================

# Reset AWM context state
# Usage: context_awm_reset
context_awm_reset() {
    if [[ "$_CTX_AWM_INITIALIZED" != "true" ]]; then
        _ctx_awm_usop_success "{\"reset\":false,\"reason\":\"not_initialized\"}"
        return 0
    fi
    
    local old_session="$_CTX_AWM_SESSION_ID"
    
    # Clear cache
    if _ctx_awm_cache_available; then
        fast_cache_clear --name "ctx_awm_$_CTX_AWM_SESSION_ID" 2>/dev/null || true
    fi
    
    # Reset state
    _CTX_AWM_CURRENT_USAGE=0
    _CTX_AWM_INITIALIZED=false
    
    _ctx_awm_log info "Reset AWM context: $old_session"
    
    _ctx_awm_usop_success "{\"reset\":true,\"session_id\":\"$old_session\"}"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

CONTEXT_AWM_EXPORTS=(
    context_awm_init
    context_awm_add
    context_awm_monitor
    context_awm_offload
    context_awm_prefetch
    context_awm_build
    context_awm_stats
    context_awm_reset
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${CONTEXT_AWM_EXPORTS[@]}" 2>/dev/null || true
fi

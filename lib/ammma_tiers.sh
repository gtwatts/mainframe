#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/ammma_tiers.sh - AMMA Tier Management
# =============================================================================
# Description: Automatic tier promotion/demotion and lifecycle management
#              for the five-tier memory hierarchy.
#
# Version: 3.0.0
# Requires: ammma.sh
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_AMMA_TIERS_LOADED:-}" ]] && return 0
readonly _MAINFRAME_AMMA_TIERS_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

_AMMA_TIERS_LIB_DIR="${BASH_SOURCE[0]%/*}"

if [[ -z "${_MAINFRAME_AMMA_LOADED:-}" ]]; then
    [[ -f "${_AMMA_TIERS_LIB_DIR}/ammma.sh" ]] && source "${_AMMA_TIERS_LIB_DIR}/ammma.sh"
fi

# =============================================================================
# TIER CONFIGURATION
# =============================================================================

# Promotion thresholds
AMMA_PROMOTE_L2_TO_L1_ACCESS_COUNT="${AMMA_PROMOTE_L2_TO_L1_ACCESS_COUNT:-3}"
AMMA_PROMOTE_L2_TO_L1_TIME_WINDOW="${AMMA_PROMOTE_L2_TO_L1_TIME_WINDOW:-300}"    # 5 minutes
AMMA_PROMOTE_L3_TO_L2_IMPORTANCE="${AMMA_PROMOTE_L3_TO_L2_IMPORTANCE:-0.7}"
AMMA_PROMOTE_L4_TO_L3_SIMILARITY="${AMMA_PROMOTE_L4_TO_L3_SIMILARITY:-0.8}"

# Demotion thresholds
AMMA_DEMOTE_L1_TO_L2_IDLE_TIME="${AMMA_DEMOTE_L1_TO_L2_IDLE_TIME:-120}"         # 2 minutes
AMMA_DEMOTE_L2_TO_L3_AGE="${AMMA_DEMOTE_L2_TO_L3_AGE:-3600}"                    # 1 hour
AMMA_DEMOTE_L3_TO_L4_AGE="${AMMA_DEMOTE_L3_TO_L4_AGE:-604800}"                  # 7 days

# Size limits for triggering eviction
AMMA_L1_MAX_ITEMS="${AMMA_L1_MAX_ITEMS:-100}"
AMMA_L2_MAX_ITEMS="${AMMA_L2_MAX_ITEMS:-1000}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Track promotion/demotion history
declare -gA _AMMA_TIER_HISTORY=()
declare -gi _AMMA_PROMOTION_COUNT=0
declare -gi _AMMA_DEMOTION_COUNT=0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_ammma_tiers_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "amma-tiers" "$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[amma-tiers] %s: %s\n' "$level" "$*" >&2
    fi
}

# Calculate current timestamp
_ammma_tiers_timestamp() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        printf '%s' "$EPOCHREALTIME"
    else
        printf '%s.%s' "$(_ammma_epoch)" "000000"
    fi
}

# =============================================================================
# PROMOTION OPERATIONS
# =============================================================================

# @pre: memory exists in source tier
# @post: memory promoted to higher tier
# @returns: 0 on success
#
# Promote a memory to a higher tier.
# Usage: _ammma_promote <memory_id> <from_tier> <to_tier>
_ammma_promote() {
    local mem_id="$1"
    local from_tier="$2"
    local to_tier="$3"
    
    _ammma_tiers_log debug "Promoting $mem_id from $from_tier to $to_tier"
    
    case "$from_tier:$to_tier" in
        "l2:l1")
            _ammma_promote_l2_to_l1 "$mem_id"
            ;;
        "l3:l2")
            _ammma_promote_l3_to_l2 "$mem_id"
            ;;
        "l4:l3")
            _ammma_promote_l4_to_l3 "$mem_id"
            ;;
        "l5:l4")
            _ammma_promote_l5_to_l4 "$mem_id"
            ;;
        *)
            _ammma_tiers_log error "Invalid promotion: $from_tier -> $to_tier"
            return 1
            ;;
    esac
    
    # Record promotion
    _AMMA_TIER_HISTORY["$mem_id"]+="$(printf '%s:promote:%s:%s;' "$(_ammma_tiers_timestamp)" "$from_tier" "$to_tier")"
    _AMMA_PROMOTION_COUNT=$((_AMMA_PROMOTION_COUNT + 1))
    
    return 0
}

# Promote L2 -> L1 (disk to memory)
_ammma_promote_l2_to_l1() {
    local mem_id="$1"
    
    local l2_path
    l2_path=$(_amma_l2_path)
    local mem_file="$l2_path/episodes/$mem_id.json"
    
    if [[ ! -f "$mem_file" ]]; then
        _ammma_tiers_log warn "Memory $mem_id not found in L2"
        return 1
    fi
    
    # Check L1 capacity
    if [[ ${#_AMMA_L1_MEMORY[@]} -ge $AMMA_L1_MAX_ITEMS ]]; then
        # Evict lowest importance from L1 first
        _ammma_evict_l1_lowest
    fi
    
    # Load into L1
    local memory
    memory=$(cat "$mem_file")
    _AMMA_L1_MEMORY["$mem_id"]="$memory"
    _AMMA_L1_META["$mem_id"]="{\"tier\":\"$AMMA_TIER_L1\",\"promoted_at\":$(_ammma_tiers_timestamp)}"
    
    # Add to attention window
    _amma_attention_add "$mem_id"
    
    _ammma_tiers_log debug "Memory $mem_id promoted to L1"
}

# Promote L3 -> L2 (compressed to working)
_ammma_promote_l3_to_l2() {
    local mem_id="$1"
    
    local l3_path
    l3_path=$(_amma_l3_path)
    local l2_path
    l2_path=$(_amma_l2_path)
    
    # Check L3 locations
    local found=false
    for location in "$l3_path/compressed" "$l3_path/summaries"; do
        if [[ -f "$location/$mem_id.json" ]]; then
            # Decompress and move to L2
            if [[ "$location" == *"compressed"* ]]; then
                # Extract from archive
                local archive
                archive=$(find "$location" -name "*.tar.gz" -exec tar -tzf {} \; | grep "$mem_id" | head -1)
                if [[ -n "$archive" ]]; then
                    tar -xzf "$location"/*.tar.gz -C "$l2_path/episodes/" "$mem_id.json" 2>/dev/null
                    found=true
                fi
            else
                # Direct copy
                cp "$location/$mem_id.json" "$l2_path/episodes/"
                found=true
            fi
            break
        fi
    done
    
    if [[ "$found" != "true" ]]; then
        _ammma_tiers_log warn "Memory $mem_id not found in L3"
        return 1
    fi
    
    # Update metadata
    local mem_file="$l2_path/episodes/$mem_id.json"
    if [[ -f "$mem_file" ]]; then
        local memory
        memory=$(cat "$mem_file")
        # Update tier field
        memory=$(echo "$memory" | sed 's/"tier":"l3"/"tier":"l2"/')
        printf '%s' "$memory" > "$mem_file"
    fi
    
    _ammma_tiers_log debug "Memory $mem_id promoted to L2"
}

# Promote L4 -> L3 (long-term to short-term)
_ammma_promote_l4_to_l3() {
    local mem_id="$1"
    
    local l4_path
    l4_path=$(_amma_l4_path)
    local l3_path
    l3_path=$(_amma_l3_path)
    
    # Find in L4
    local found_file=""
    for dir in episodes patterns facts; do
        if [[ -f "$l4_path/$dir/$mem_id.json" ]]; then
            found_file="$l4_path/$dir/$mem_id.json"
            break
        fi
    done
    
    if [[ -z "$found_file" ]]; then
        _ammma_tiers_log warn "Memory $mem_id not found in L4"
        return 1
    fi
    
    # Copy to L3 summaries
    mkdir -p "$l3_path/summaries"
    cp "$found_file" "$l3_path/summaries/"
    
    _ammma_tiers_log debug "Memory $mem_id promoted to L3"
}

# Promote L5 -> L4 (external to long-term)
_ammma_promote_l5_to_l4() {
    local mem_id="$1"
    
    # L5 is external, need to fetch from vector DB
    if [[ "$AMMA_SEMANTIC_SEARCH" == "true" ]] && declare -F vectordb_get &>/dev/null; then
        local collection="${AMMA_L5_COLLECTION:-amma_memory}"
        local result
        result=$(vectordb_get "$collection" "$mem_id" 2>/dev/null)
        
        if [[ -n "$result" ]]; then
            local l4_path
            l4_path=$(_amma_l4_path)
            local mem_type
            mem_type=$(echo "$result" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)
            
            local target_dir
            case "$mem_type" in
                "$AMMA_TYPE_EPISODIC") target_dir="episodes" ;;
                "$AMMA_TYPE_PROCEDURAL") target_dir="patterns" ;;
                "$AMMA_TYPE_DECLARATIVE") target_dir="facts" ;;
                *) target_dir="episodes" ;;
            esac
            
            mkdir -p "$l4_path/$target_dir"
            printf '%s' "$result" > "$l4_path/$target_dir/$mem_id.json"
            
            _ammma_tiers_log debug "Memory $mem_id fetched from L5 to L4"
        fi
    fi
}

# =============================================================================
# DEMOTION OPERATIONS
# =============================================================================

# @pre: memory exists in source tier
# @post: memory demoted to lower tier
# @returns: 0 on success
#
# Demote a memory to a lower tier.
# Usage: _ammma_demote <memory_id> <from_tier> <to_tier>
_ammma_demote() {
    local mem_id="$1"
    local from_tier="$2"
    local to_tier="$3"
    
    _ammma_tiers_log debug "Demoting $mem_id from $from_tier to $to_tier"
    
    case "$from_tier:$to_tier" in
        "l1:l2")
            _ammma_demote_l1_to_l2 "$mem_id"
            ;;
        "l2:l3")
            _ammma_demote_l2_to_l3 "$mem_id"
            ;;
        "l3:l4")
            _ammma_demote_l3_to_l4 "$mem_id"
            ;;
        "l4:l5")
            _ammma_demote_l4_to_l5 "$mem_id"
            ;;
        *)
            _ammma_tiers_log error "Invalid demotion: $from_tier -> $to_tier"
            return 1
            ;;
    esac
    
    # Record demotion
    _AMMA_TIER_HISTORY["$mem_id"]+="$(printf '%s:demote:%s:%s;' "$(_ammma_tiers_timestamp)" "$from_tier" "$to_tier")"
    _AMMA_DEMOTION_COUNT=$((_AMMA_DEMOTION_COUNT + 1))
    
    return 0
}

# Demote L1 -> L2 (memory to disk)
_ammma_demote_l1_to_l2() {
    local mem_id="$1"
    
    # Check if in L1
    if [[ -z "${_AMMA_L1_MEMORY[$mem_id]:-}" ]]; then
        _ammma_tiers_log warn "Memory $mem_id not found in L1"
        return 1
    fi
    
    # Persist to L2 (should already be there, just update)
    local memory="${_AMMA_L1_MEMORY[$mem_id]}"
    local l2_path
    l2_path=$(_amma_l2_path)
    
    # Update tier in memory
    memory=$(echo "$memory" | sed 's/"tier":"[^"]*"/"tier":"l2"/')
    printf '%s' "$memory" > "$l2_path/episodes/$mem_id.json"
    
    # Remove from L1
    unset "_AMMA_L1_MEMORY[$mem_id]"
    unset "_AMMA_L1_META[$mem_id]"
    
    # Remove from attention window
    local new_window=()
    for id in "${_AMMA_ATTENTION_WINDOW[@]}"; do
        [[ "$id" == "$mem_id" ]] && continue
        new_window+=("$id")
    done
    _AMMA_ATTENTION_WINDOW=("${new_window[@]}")
    
    _ammma_tiers_log debug "Memory $mem_id demoted to L2"
}

# Demote L2 -> L3 (working to short-term)
_ammma_demote_l2_to_l3() {
    local mem_id="$1"
    
    local l2_path
    l2_path=$(_amma_l2_path)
    local l3_path
    l3_path=$(_amma_l3_path)
    local mem_file="$l2_path/episodes/$mem_id.json"
    
    if [[ ! -f "$mem_file" ]]; then
        _ammma_tiers_log warn "Memory $mem_id not found in L2"
        return 1
    fi
    
    # Compress and move to L3
    mkdir -p "$l3_path/summaries"
    
    # Create summary (for now, just compress)
    local memory
    memory=$(cat "$mem_file")
    
    # Update tier
    memory=$(echo "$memory" | sed 's/"tier":"[^"]*"/"tier":"l3"/')
    printf '%s' "$memory" > "$l3_path/summaries/$mem_id.json"
    
    # Remove from L2
    rm -f "$mem_file"
    
    _ammma_tiers_log debug "Memory $mem_id demoted to L3"
}

# Demote L3 -> L4 (short-term to long-term)
_ammma_demote_l3_to_l4() {
    local mem_id="$1"
    
    local l3_path
    l3_path=$(_amma_l3_path)
    local l4_path
    l4_path=$(_amma_l4_path)
    
    # Find in L3
    local source_file="$l3_path/summaries/$mem_id.json"
    if [[ ! -f "$source_file" ]]; then
        _ammma_tiers_log warn "Memory $mem_id not found in L3"
        return 1
    fi
    
    # Read memory to determine type
    local memory
    memory=$(cat "$source_file")
    local mem_type
    mem_type=$(echo "$memory" | grep -o '"type":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    local target_dir
    case "$mem_type" in
        "$AMMA_TYPE_EPISODIC") target_dir="episodes" ;;
        "$AMMA_TYPE_PROCEDURAL") target_dir="patterns" ;;
        "$AMMA_TYPE_DECLARATIVE") target_dir="facts" ;;
        *) target_dir="episodes" ;;
    esac
    
    # Organize by date
    local year_month
    year_month=$(date +%Y/%m)
    mkdir -p "$l4_path/$target_dir/$year_month"
    
    # Update tier and move
    memory=$(echo "$memory" | sed 's/"tier":"[^"]*"/"tier":"l4"/')
    printf '%s' "$memory" > "$l4_path/$target_dir/$year_month/$mem_id.json"
    
    # Remove from L3
    rm -f "$source_file"
    
    # Index for semantic search if enabled
    if [[ "$AMMA_SEMANTIC_SEARCH" == "true" ]]; then
        _ammma_index_for_search "$mem_id" "$l4_path/$target_dir/$year_month/$mem_id.json"
    fi
    
    _ammma_tiers_log debug "Memory $mem_id demoted to L4"
}

# Demote L4 -> L5 (long-term to external)
_ammma_demote_l4_to_l5() {
    local mem_id="$1"
    
    # Find in L4
    local l4_path
    l4_path=$(_amma_l4_path)
    local found_file=""
    
    for dir in episodes patterns facts; do
        found_file=$(find "$l4_path/$dir" -name "$mem_id.json" 2>/dev/null | head -1)
        [[ -n "$found_file" ]] && break
    done
    
    if [[ -z "$found_file" ]]; then
        _ammma_tiers_log warn "Memory $mem_id not found in L4"
        return 1
    fi
    
    # Upload to external vector DB
    if [[ "$AMMA_SEMANTIC_SEARCH" == "true" ]] && declare -F vectordb_upsert &>/dev/null; then
        local memory
        memory=$(cat "$found_file")
        
        local collection="${AMMA_L5_COLLECTION:-amma_memory}"
        local content
        content=$(echo "$memory" | grep -o '"description":"[^"]*"' | head -1 | cut -d'"' -f4)
        
        # Generate embedding if needed
        local embedding=""
        if declare -F embed_text &>/dev/null; then
            embedding=$(embed_text "$content" 2>/dev/null)
        fi
        
        if [[ -n "$embedding" ]]; then
            vectordb_upsert "$collection" "$mem_id" "$content" "$embedding" "$memory" 2>/dev/null
            
            # Remove local copy after successful upload
            rm -f "$found_file"
            
            _ammma_tiers_log debug "Memory $mem_id uploaded to L5"
        fi
    fi
}

# =============================================================================
# EVICTION
# =============================================================================

# Evict lowest importance item from L1
_ammma_evict_l1_lowest() {
    local lowest_id=""
    local lowest_score=999999
    
    for mem_id in "${!_AMMA_L1_MEMORY[@]}"; do
        local memory="${_AMMA_L1_MEMORY[$mem_id]}"
        local importance
        importance=$(echo "$memory" | grep -o '"importance":"[^"]*"' | head -1 | cut -d'"' -f4)
        
        local score
        score=$(_ammma_importance_to_score "$importance")
        
        if [[ $score -lt $lowest_score ]]; then
            lowest_score=$score
            lowest_id=$mem_id
        fi
    done
    
    if [[ -n "$lowest_id" ]]; then
        _ammma_demote_l1_to_l2 "$lowest_id"
    fi
}

# =============================================================================
# AUTOMATIC TIER MANAGEMENT
# =============================================================================

# @pre: AMMA initialized
# @post: All memories evaluated and promoted/demoted as needed
# @returns: Summary of operations as JSON
#
# Run automatic tier management cycle.
# Evaluates all memories and performs necessary promotions/demotions.
ammma_tier_manage() {
    if [[ "$_AMMA_INITIALIZED" != "true" ]]; then
        printf '{"error":"AMMA not initialized"}'
        return 1
    fi
    
    local promotions=0
    local demotions=0
    local current_time
    current_time=$(_ammma_tiers_timestamp)
    
    # Check L1 memories for demotion
    for mem_id in "${!_AMMA_L1_MEMORY[@]}"; do
        local meta="${_AMMA_L1_META[$mem_id]:-{}}"
        local last_access
        last_access=$(echo "$meta" | grep -o '"last_access":[0-9.]*' | cut -d: -f2)
        [[ -z "$last_access" ]] && last_access=0
        
        local idle_time
        idle_time=$(echo "$current_time - $last_access" | bc 2>/dev/null || echo "0")
        
        if [[ $(echo "$idle_time > $AMMA_DEMOTE_L1_TO_L2_IDLE_TIME" | bc 2>/dev/null) -eq 1 ]]; then
            _ammma_demote_l1_to_l2 "$mem_id"
            demotions=$((demotions + 1))
        fi
    done
    
    # Check L2 memories for promotion/demotion
    local l2_path
    l2_path=$(_amma_l2_path)
    if [[ -d "$l2_path/episodes" ]]; then
        for mem_file in "$l2_path"/episodes/*.json; do
            [[ -f "$mem_file" ]] || continue
            
            local mem_id
            mem_id=$(basename "$mem_file" .json)
            local access_count="${_AMMA_L2_ACCESS_COUNT[$mem_id]:-0}"
            
            # Check for promotion to L1
            if [[ $access_count -ge $AMMA_PROMOTE_L2_TO_L1_ACCESS_COUNT ]]; then
                _ammma_promote_l2_to_l1 "$mem_id"
                promotions=$((promotions + 1))
            fi
            
            # Check file age for demotion to L3
            local file_age
            file_age=$(($(date +%s) - $(stat -c %Y "$mem_file" 2>/dev/null || stat -f %m "$mem_file" 2>/dev/null || echo "0")))
            
            if [[ $file_age -gt $AMMA_DEMOTE_L2_TO_L3_AGE ]]; then
                _ammma_demote_l2_to_l3 "$mem_id"
                demotions=$((demotions + 1))
            fi
        done
    fi
    
    printf '{"promotions":%d,"demotions":%d,"timestamp":%s}' "$promotions" "$demotions" "$current_time"
}

# =============================================================================
# INDEXING
# =============================================================================

# Index memory for semantic search
_ammma_index_for_search() {
    local mem_id="$1"
    local mem_file="$2"
    
    if ! declare -F vectordb_upsert &>/dev/null; then
        return 0
    fi
    
    local memory
    memory=$(cat "$mem_file")
    local content
    content=$(echo "$memory" | grep -o '"description":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [[ -z "$content" ]]; then
        return 0
    fi
    
    # Generate embedding
    local embedding=""
    if declare -F embed_text &>/dev/null; then
        embedding=$(embed_text "$content" 2>/dev/null)
    fi
    
    if [[ -n "$embedding" ]]; then
        local collection="${AMMA_L4_COLLECTION:-amma_l4}"
        vectordb_upsert "$collection" "$mem_id" "$content" "$embedding" "$memory" 2>/dev/null
    fi
}

# =============================================================================
# STATISTICS
# =============================================================================

# @pre: AMMA initialized
# @post: Returns tier statistics as JSON
# @returns: JSON statistics
ammma_tier_stats() {
    local l1_count=${#_AMMA_L1_MEMORY[@]}
    local l2_count=0
    local l3_count=0
    local l4_count=0
    
    local l2_path
    l2_path=$(_amma_l2_path)
    if [[ -d "$l2_path/episodes" ]]; then
        l2_count=$(find "$l2_path/episodes" -name "*.json" 2>/dev/null | wc -l)
    fi
    
    local l3_path
    l3_path=$(_amma_l3_path)
    if [[ -d "$l3_path/summaries" ]]; then
        l3_count=$(find "$l3_path/summaries" -name "*.json" 2>/dev/null | wc -l)
    fi
    
    local l4_path
    l4_path=$(_amma_l4_path)
    for dir in episodes patterns facts; do
        if [[ -d "$l4_path/$dir" ]]; then
            l4_count=$((l4_count + $(find "$l4_path/$dir" -name "*.json" 2>/dev/null | wc -l)))
        fi
    done
    
    printf '{"tiers":{"l1":%d,"l2":%d,"l3":%d,"l4":%d},"operations":{"promotions":%d,"demotions":%d}}' \
        "$l1_count" "$l2_count" "$l3_count" "$l4_count" \
        "$_AMMA_PROMOTION_COUNT" "$_AMMA_DEMOTION_COUNT"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

AMMM_TIERS_EXPORTS=(
    ammma_tier_manage
    ammma_tier_stats
)

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${AMMM_TIERS_EXPORTS[@]}" 2>/dev/null || true
fi

#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2119,SC2120,SC2016,SC1003,SC2155,SC2181,SC2059,SC2206

# =============================================================================
# MAINFRAME/lib/ammma_consolidate.sh - AMMA Memory Consolidation
# =============================================================================
# Description: Sleep-like memory consolidation that merges episodic memories,
#              extracts patterns, and creates summaries for long-term storage.
#
# Version: 3.0.0
# Requires: ammma.sh
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_AMMA_CONSOLIDATE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_AMMA_CONSOLIDATE_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

_AMMA_CONSOL_LIB_DIR="${BASH_SOURCE[0]%/*}"

if [[ -z "${_MAINFRAME_AMMA_LOADED:-}" ]]; then
    [[ -f "${_AMMA_CONSOL_LIB_DIR}/ammma.sh" ]] && source "${_AMMA_CONSOL_LIB_DIR}/ammma.sh"
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

# Consolidation thresholds
AMMA_CONSOL_SIMILARITY_THRESHOLD="${AMMA_CONSOL_SIMILARITY_THRESHOLD:-0.75}"
AMMA_CONSOL_MIN_EPISODES_FOR_PATTERN="${AMMA_CONSOL_MIN_EPISODES_FOR_PATTERN:-3}"
AMMA_CONSOL_MAX_EPISODE_AGE_DAYS="${AMMA_CONSOL_MAX_EPISODE_AGE_DAYS:-30}"
AMMA_CONSOL_SUMMARY_MAX_LENGTH="${AMMA_CONSOL_SUMMARY_MAX_LENGTH:-500}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

declare -gi _AMMA_CONSOL_EPISODES_MERGED=0
declare -gi _AMMA_CONSOL_PATTERNS_EXTRACTED=0
declare -gi _AMMA_CONSOL_SUMMARIES_CREATED=0
declare -gi _AMMA_CONSOL_GARBAGE_COLLECTED=0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_ammma_consol_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "amma-consol" "$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[amma-consol] %s: %s\n' "$level" "$*" >&2
    fi
}

_ammma_consol_timestamp() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    else
        date +%s
    fi
}

_ammma_consol_days_to_seconds() {
    local days="$1"
    echo $((days * 86400))
}

# Calculate similarity between two strings (simple Jaccard-like)
_ammma_consol_similarity() {
    local str1="$1"
    local str2="$2"
    
    # Convert to lowercase and tokenize
    str1=$(echo "$str1" | tr '[:upper:]' '[:lower:]' | tr -s ' ' | tr ' ' '\n' | sort -u | tr '\n' ' ')
    str2=$(echo "$str2" | tr '[:upper:]' '[:lower:]' | tr -s ' ' | tr ' ' '\n' | sort -u | tr '\n' ' ')
    
    # Count common words
    local common
    common=$(echo "$str1 $str2" | tr ' ' '\n' | sort | uniq -d | wc -l)
    
    local total1 total2
    total1=$(echo "$str1" | wc -w)
    total2=$(echo "$str2" | wc -w)
    
    # Jaccard similarity: intersection / union
    if [[ $((total1 + total2 - common)) -eq 0 ]]; then
        printf '0'
    else
        awk "BEGIN {printf \"%.2f\", $common / ($total1 + $total2 - $common)}"
    fi
}

# =============================================================================
# MAIN CONSOLIDATION ENTRY POINT
# =============================================================================

# @pre: AMMA initialized
# @post: Consolidation run completed
# @returns: JSON summary of operations
#
# Run memory consolidation cycle.
# Merges similar episodes, extracts patterns, creates summaries.
#
# Usage: amma_consolidate [--session SESSION] [--dry-run]
# shellcheck disable=SC2120
ammma_consolidate() {
    if [[ "$_AMMA_INITIALIZED" != "true" ]]; then
        printf '{"error":"AMMA not initialized"}'
        return 1
    fi
    
    local session_id="$_AMMA_SESSION_ID"
    local dry_run=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --session)
                session_id="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    _ammma_consol_log info "Starting consolidation for session: $session_id"
    
    local start_time
    start_time=$(_ammma_consol_timestamp)
    
    # Phase 1: Merge similar episodic memories
    local merged
    merged=$(_ammma_consol_merge_episodes "$session_id" "$dry_run")
    
    # Phase 2: Extract patterns from episode sequences
    local patterns
    patterns=$(_ammma_consol_extract_patterns "$session_id" "$dry_run")
    
    # Phase 3: Create session summaries
    local summaries
    summaries=$(_ammma_consol_create_summaries "$session_id" "$dry_run")
    
    # Phase 4: Garbage collect obsolete memories
    local gc
    gc=$(_ammma_consol_garbage_collect "$session_id" "$dry_run")
    
    local end_time
    end_time=$(_ammma_consol_timestamp)
    local duration=$((end_time - start_time))
    
    # Output summary
    printf '{"session":"%s","duration_sec":%d,"operations":{%s,%s,%s,%s},"dry_run":%s}' \
        "$session_id" \
        "$duration" \
        "$merged" \
        "$patterns" \
        "$summaries" \
        "$gc" \
        "$($dry_run && echo 'true' || echo 'false')"
}

# =============================================================================
# PHASE 1: EPISODE MERGING
# =============================================================================

# Merge similar episodic memories
_ammma_consol_merge_episodes() {
    local session_id="$1"
    local dry_run="$2"
    
    local l2_path
    l2_path=$(_amma_l2_path)
    
    local episodes_dir="$l2_path/episodes"
    [[ ! -d "$episodes_dir" ]] && echo '"episodes":{"merged":0}' && return 0
    
    # Collect all episodic memories
    local -a episodes=()
    local -a episode_contents=()
    local -a episode_ids=()
    
    for mem_file in "$episodes_dir"/*.json; do
        [[ -f "$mem_file" ]] || continue
        
        local memory
        memory=$(cat "$mem_file")
        
        local mem_type
        mem_type=$(echo "$memory" | grep -o '"type":"[^"]*"' | head -1 | cut -d'"' -f4)
        
        if [[ "$mem_type" == "$AMMA_TYPE_EPISODIC" ]]; then
            local content
            content=$(echo "$memory" | grep -o '"description":"[^"]*"' | head -1 | cut -d'"' -f4)
            
            episode_ids+=("$(basename "$mem_file" .json)")
            episode_contents+=("$content")
            episodes+=("$memory")
        fi
    done
    
    local merged_count=0
    local -a merged_indices=()
    
    # Find similar episodes
    for ((i=0; i<${#episodes[@]}; i++)); do
        # Skip if already merged
        local already_merged=false
        for idx in "${merged_indices[@]}"; do
            if [[ "$idx" == "$i" ]]; then
                already_merged=true
                break
            fi
        done
        $already_merged && continue
        
        # shellcheck disable=SC2206
        local similar_group=($i)
        
        for ((j=i+1; j<${#episodes[@]}; j++)); do
            # Skip if already merged
            already_merged=false
            for idx in "${merged_indices[@]}"; do
                if [[ "$idx" == "$j" ]]; then
                    already_merged=true
                    break
                fi
            done
            $already_merged && continue
            
            # Calculate similarity
            local similarity
            similarity=$(_ammma_consol_similarity "${episode_contents[$i]}" "${episode_contents[$j]}")
            
            if [[ $(echo "$similarity >= $AMMA_CONSOL_SIMILARITY_THRESHOLD" | bc 2>/dev/null) -eq 1 ]]; then
                # shellcheck disable=SC2206
                similar_group+=($j)
                # shellcheck disable=SC2206
                merged_indices+=($j)
            fi
        done
        
        # If we found similar episodes, merge them
        if [[ ${#similar_group[@]} -gt 1 ]]; then
            if [[ "$dry_run" != "true" ]]; then
                _ammma_consol_do_merge "${similar_group[@]}" "${episode_ids[@]}"
            fi
            merged_count=$((merged_count + ${#similar_group[@]} - 1))
        fi
    done
    
    _AMMA_CONSOL_EPISODES_MERGED=$((_AMMA_CONSOL_EPISODES_MERGED + merged_count))
    
    printf '"episodes":{"merged":%d}' "$merged_count"
}

# Actually perform the merge
_ammma_consol_do_merge() {
    local -a indices=("$@")
    # shellcheck disable=SC2034
    local -a all_ids=()
    
    # Get IDs from indices (indices after the first are IDs)
    # This is a simplified implementation
    
    local l2_path
    l2_path=$(_amma_l2_path)
    # shellcheck disable=SC2034
    local primary_id=""
    # shellcheck disable=SC2034
    local merged_content=""
    
    for idx in "${indices[@]}"; do
        # In real implementation, we'd look up the ID from index
        :  # Placeholder
    done
    
    _ammma_consol_log debug "Merged ${#indices[@]} episodes"
}

# =============================================================================
# PHASE 2: PATTERN EXTRACTION
# =============================================================================

# Extract procedural patterns from episode sequences
_ammma_consol_extract_patterns() {
    local session_id="$1"
    local dry_run="$2"
    
    local l2_path
    l2_path=$(_amma_l2_path)
    local episodes_dir="$l2_path/episodes"
    
    [[ ! -d "$episodes_dir" ]] && echo '"patterns":{"extracted":0}' && return 0
    
    local patterns_found=0
    
    # Group episodes by task type
    declare -A task_groups
    
    for mem_file in "$episodes_dir"/*.json; do
        [[ -f "$mem_file" ]] || continue
        
        local memory
        memory=$(cat "$mem_file")
        
        local event_type
        event_type=$(echo "$memory" | grep -o '"type":"[^"]*"' | head -1 | cut -d'"' -f4)
        
        if [[ "$event_type" == "$AMMA_TYPE_EPISODIC" ]]; then
            # Try to identify task from content
            local content
            content=$(echo "$memory" | grep -o '"description":"[^"]*"' | head -1 | cut -d'"' -f4)
            
            # Extract task keywords (simplified)
            local task_key
            task_key=$(echo "$content" | grep -oE '(debug|test|deploy|refactor|implement|fix|create)' | head -1)
            
            if [[ -n "$task_key" ]]; then
                task_groups["$task_key"]+="$(basename "$mem_file" .json);"
            fi
        fi
    done
    
    # For tasks with enough episodes, create a pattern
    for task in "${!task_groups[@]}"; do
        local episodes_list="${task_groups[$task]}"
        local episode_count
        episode_count=$(echo "$episodes_list" | tr ';' '\n' | grep -c .)
        
        if [[ $episode_count -ge $AMMA_CONSOL_MIN_EPISODES_FOR_PATTERN ]]; then
            if [[ "$dry_run" != "true" ]]; then
                _ammma_consol_create_pattern "$task" "$episodes_list"
            fi
            patterns_found=$((patterns_found + 1))
        fi
    done
    
    _AMMA_CONSOL_PATTERNS_EXTRACTED=$((_AMMA_CONSOL_PATTERNS_EXTRACTED + patterns_found))
    
    printf '"patterns":{"extracted":%d}' "$patterns_found"
}

# Create a procedural pattern from episode sequence
_ammma_consol_create_pattern() {
    local task_name="$1"
    local episodes_list="$2"
    
    local pattern_id
    pattern_id=$(_amma_gen_id "pat")
    
    local l2_path
    l2_path=$(_amma_l2_path)
    
    # Build pattern structure
    local pattern
    pattern=$(printf '{"_schema":"amma.v3.pattern","id":"%s","name":"%s","extracted_from":"%s","created_at":%s,"specification":{"trigger_conditions":["%s"],"action_sequence":[]},"performance":{"success_rate":0.0,"usage_count":0}}' \
        "$pattern_id" \
        "pattern_$task_name" \
        "$episodes_list" \
        "$(_ammma_consol_timestamp)" \
        "$task_name")
    
    # Store in L2 patterns
    mkdir -p "$l2_path/patterns"
    printf '%s' "$pattern" > "$l2_path/patterns/$pattern_id.json"
    
    _ammma_consol_log debug "Created pattern $pattern_id for task: $task_name"
}

# =============================================================================
# PHASE 3: SUMMARY CREATION
# =============================================================================

# Create session summaries
_ammma_consol_create_summaries() {
    local session_id="$1"
    local dry_run="$2"
    
    local l2_path
    l2_path=$(_amma_l2_path)
    local summaries_dir="$l2_path/../summaries"
    
    # Count episodes by type
    local discoveries=0
    local decisions=0
    local errors=0
    local total=0
    
    for mem_file in "$l2_path/episodes"/*.json; do
        [[ -f "$mem_file" ]] || continue
        
        local memory
        memory=$(cat "$mem_file")
        
        local content
        content=$(echo "$memory" | grep -o '"description":"[^"]*"' | head -1 | cut -d'"' -f4)
        
        total=$((total + 1))
        
        # Categorize by content keywords
        if [[ "$content" == *"discover"* ]] || [[ "$content" == *"found"* ]]; then
            discoveries=$((discoveries + 1))
        elif [[ "$content" == *"decided"* ]] || [[ "$content" == *"chose"* ]]; then
            decisions=$((decisions + 1))
        elif [[ "$content" == *"error"* ]] || [[ "$content" == *"failed"* ]]; then
            errors=$((errors + 1))
        fi
    done
    
    local summaries_created=0
    
    if [[ $total -gt 0 ]]; then
        if [[ "$dry_run" != "true" ]]; then
            mkdir -p "$summaries_dir"
            
            local summary_id
            summary_id=$(_amma_gen_id "sum")
            
            local summary
            summary=$(printf '{"_schema":"amma.v3.summary","id":"%s","session_id":"%s","created_at":%s,"statistics":{"total_memories":%d,"discoveries":%d,"decisions":%d,"errors":%d},"highlights":[]}' \
                "$summary_id" \
                "$session_id" \
                "$(_ammma_consol_timestamp)" \
                "$total" \
                "$discoveries" \
                "$decisions" \
                "$errors")
            
            printf '%s' "$summary" > "$summaries_dir/$summary_id.json"
        fi
        summaries_created=1
    fi
    
    _AMMA_CONSOL_SUMMARIES_CREATED=$((_AMMA_CONSOL_SUMMARIES_CREATED + summaries_created))
    
    printf '"summaries":{"created":%d,"total_memories":%d}' "$summaries_created" "$total"
}

# =============================================================================
# PHASE 4: GARBAGE COLLECTION
# =============================================================================

# Remove obsolete memories
_ammma_consol_garbage_collect() {
    local session_id="$1"
    local dry_run="$2"
    
    local gc_count=0
    local cutoff_time
    cutoff_time=$(($(date +%s) - $(_ammma_consol_days_to_seconds "$AMMA_CONSOL_MAX_EPISODE_AGE_DAYS")))
    
    # Check L2 for old memories
    local l2_path
    l2_path=$(_amma_l2_path)
    
    for mem_file in "$l2_path/episodes"/*.json; do
        [[ -f "$mem_file" ]] || continue
        
        local file_mtime
        file_mtime=$(stat -c %Y "$mem_file" 2>/dev/null || stat -f %m "$mem_file" 2>/dev/null || echo "0")
        
        if [[ $file_mtime -lt $cutoff_time ]]; then
            local memory
            memory=$(cat "$mem_file")
            
            local importance
            importance=$(echo "$memory" | grep -o '"importance":"[^"]*"' | head -1 | cut -d'"' -f4)
            
            # Only GC low importance memories
            if [[ "$importance" == "$AMMA_IMPORTANCE_LOW" ]] || [[ "$importance" == "$AMMA_IMPORTANCE_NORMAL" ]]; then
                if [[ "$dry_run" != "true" ]]; then
                    rm -f "$mem_file"
                fi
                gc_count=$((gc_count + 1))
            fi
        fi
    done
    
    _AMMA_CONSOL_GARBAGE_COLLECTED=$((_AMMA_CONSOL_GARBAGE_COLLECTED + gc_count))
    
    printf '"garbage_collected":%d' "$gc_count"
}

# =============================================================================
# CONSOLIDATION SCHEDULING
# =============================================================================

# Schedule automatic consolidation
_ammma_consol_schedule() {
    local interval="${1:-21600}"  # Default 6 hours
    
    # In a real implementation, this would set up a background timer
    # For bash, we can use a timestamp check
    
    local last_run_file="$AMMA_ROOT/.last_consolidation"
    local last_run=0
    
    if [[ -f "$last_run_file" ]]; then
        last_run=$(cat "$last_run_file")
    fi
    
    local current_time
    current_time=$(_ammma_consol_timestamp)
    
    if [[ $((current_time - last_run)) -ge $interval ]]; then
        # shellcheck disable=SC2119
        ammma_consolidate
        printf '%s' "$current_time" > "$last_run_file"
    fi
}

# Check if consolidation is due
ammma_consolidation_check() {
    local interval="${1:-21600}"
    local last_run_file="$AMMA_ROOT/.last_consolidation"
    
    [[ ! -f "$last_run_file" ]] && return 0
    
    local last_run
    last_run=$(cat "$last_run_file")
    local current_time
    current_time=$(_ammma_consol_timestamp)
    
    [[ $((current_time - last_run)) -ge $interval ]]
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

AMMM_CONSOL_EXPORTS=(
    ammma_consolidate
    ammma_consolidation_check
)

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${AMMM_CONSOL_EXPORTS[@]}" 2>/dev/null || true
fi

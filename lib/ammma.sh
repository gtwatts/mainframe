#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/ammma.sh - Advanced Multi-tier Memory Architecture (AMMA V3)
# =============================================================================
# Description: Core API for cognitive-inspired memory management with
#              five-tier hierarchy, semantic retrieval, and cross-agent sharing.
#
# Version: 3.0.0
# Requires: Bash 4.0+
# Standards: USOP (Universal Structured Output Protocol)
# =============================================================================
# "Intelligent agents need intelligent memory."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_AMMA_LOADED:-}" ]] && return 0
readonly _MAINFRAME_AMMA_LOADED=1

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

readonly AMMA_VERSION="3.0.0"
readonly AMMA_SCHEMA_VERSION="1.0"

# Tier definitions
readonly AMMA_TIER_L1="L1"    # Immediate context
readonly AMMA_TIER_L2="L2"    # Working memory
# shellcheck disable=SC2034
readonly AMMA_TIER_L3="L3"    # Short-term memory
# shellcheck disable=SC2034
readonly AMMA_TIER_L4="L4"    # Long-term memory
# shellcheck disable=SC2034
readonly AMMA_TIER_L5="L5"    # External memory

# Memory types
readonly AMMA_TYPE_EPISODIC="episodic"
readonly AMMA_TYPE_PROCEDURAL="procedural"
readonly AMMA_TYPE_DECLARATIVE="declarative"
readonly AMMA_TYPE_CHECKPOINT="checkpoint"

# Importance levels
readonly AMMA_IMPORTANCE_CRITICAL="critical"
readonly AMMA_IMPORTANCE_HIGH="high"
readonly AMMA_IMPORTANCE_NORMAL="normal"
readonly AMMA_IMPORTANCE_LOW="low"

# Importance scores for ranking
readonly AMMA_SCORE_CRITICAL=100
readonly AMMA_SCORE_HIGH=70
readonly AMMA_SCORE_NORMAL=40
readonly AMMA_SCORE_LOW=10

# Sharing scopes
# shellcheck disable=SC2034
readonly AMMA_SCOPE_PUBLIC="public"
# shellcheck disable=SC2034
readonly AMMA_SCOPE_TEAM="team"
readonly AMMA_SCOPE_PRIVATE="private"
# shellcheck disable=SC2034
readonly AMMA_SCOPE_INHERIT="inherit"

# Default configuration
AMMA_ROOT="${AMMA_ROOT:-${HOME}/.mainframe/amma}"
AMMA_L1_MAX_SIZE="${AMMA_L1_MAX_SIZE:-4096}"           # 4KB
AMMA_L2_MAX_SIZE="${AMMA_L2_MAX_SIZE:-10485760}"      # 10MB
AMMA_L3_MAX_SIZE="${AMMA_L3_MAX_SIZE:-104857600}"     # 100MB
AMMA_L4_MAX_SIZE="${AMMA_L4_MAX_SIZE:-1073741824}"    # 1GB

AMMA_L2_TTL="${AMMA_L2_TTL:-86400}"                   # 24 hours
AMMA_L3_TTL="${AMMA_L3_TTL:-604800}"                  # 7 days
AMMA_L4_TTL="${AMMA_L4_TTL:-0}"                       # Indefinite

# Feature flags
AMMA_PREDICTIVE_PRELOAD="${AMMA_PREDICTIVE_PRELOAD:-true}"
AMMA_AUTO_CONSOLIDATE="${AMMA_AUTO_CONSOLIDATE:-true}"
AMMA_SEMANTIC_SEARCH="${AMMA_SEMANTIC_SEARCH:-true}"
AMMA_AUTO_EMBED_THRESHOLD="${AMMA_AUTO_EMBED_THRESHOLD:-0.3}"

# Token estimation (rough chars per token)
readonly AMMA_CHARS_PER_TOKEN=4

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Session state
_AMMA_SESSION_ID=""
_AMMA_AGENT_ID=""
_AMMA_PARENT_SESSION=""
_AMMA_NAMESPACE=""
_AMMA_INITIALIZED=false
_AMMA_START_TIME=""

# L1: Immediate Context (in-memory associative arrays)
declare -gA _AMMA_L1_MEMORY=()
declare -gA _AMMA_L1_META=()
declare -gA _AMMA_L1_TOKENS=()

# L2: Working Memory tracking
declare -gA _AMMA_L2_ACCESS_COUNT=()
declare -gA _AMMA_L2_LAST_ACCESS=()
declare -gA _AMMA_L2_SCORES=()

# Attention window (ordered list of memory IDs in focus)
declare -ga _AMMA_ATTENTION_WINDOW=()

# Statistics
declare -gi _AMMA_MEMORY_COUNT=0
declare -gi _AMMA_RETRIEVAL_COUNT=0
declare -gi _AMMA_EPISODE_COUNT=0
declare -gi _AMMA_FACT_COUNT=0
declare -gi _AMMA_PATTERN_COUNT=0
declare -gi _AMMA_CHECKPOINT_COUNT=0

# LRU tracking for tier management
declare -gA _AMMA_LRU_TIMES=()

# =============================================================================
# USOP OUTPUT HELPERS
# =============================================================================

# Output USOP success response
_amma_usop_success() {
    local data="${1:-null}"
    local hint="${2:-}"
    local elapsed="${3:-}"
    
    [[ -z "$elapsed" ]] && elapsed="0"
    
    if [[ -z "$hint" ]]; then
        printf '{"ok":true,"data":%s,"meta":{"elapsed_ms":%s,"timestamp":%s}}' \
            "$data" "$elapsed" "$(_amma_epoch_ms)"
    else
        printf '{"ok":true,"data":%s,"meta":{"elapsed_ms":%s,"timestamp":%s},"hint":"%s"}' \
            "$data" "$elapsed" "$(_amma_epoch_ms)" "$(_amma_json_escape "$hint")"
    fi
}

# Output USOP error response
_amma_usop_error() {
    local code="$1"
    local msg="$2"
    local suggestion="${3:-}"
    
    if [[ -z "$suggestion" ]]; then
        printf '{"ok":false,"error":{"code":"%s","msg":"%s"},"meta":{"timestamp":%s}}' \
            "$code" "$(_amma_json_escape "$msg")" "$(_amma_epoch_ms)"
    else
        printf '{"ok":false,"error":{"code":"%s","msg":"%s","suggestion":"%s"},"meta":{"timestamp":%s}}' \
            "$code" "$(_amma_json_escape "$msg")" "$(_amma_json_escape "$suggestion")" "$(_amma_epoch_ms)"
    fi
}

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_amma_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "amma" "$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[amma] %s: %s\n' "$level" "$*" >&2
    fi
}

_amma_epoch() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    elif printf -v _ts '%(%s)T' -1 2>/dev/null && [[ -n "$_ts" ]]; then
        printf '%s' "$_ts"
    else
        date +%s
    fi
}

_amma_epoch_ms() {
    local epoch
    epoch=$(_amma_epoch)
    printf '%s000' "$epoch"
}

_amma_timestamp() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        printf '%s' "$EPOCHREALTIME"
    else
        printf '%s.%s' "$(_amma_epoch)" "000000"
    fi
}

_amma_iso_timestamp() {
    local ts
    if printf -v ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1 2>/dev/null && [[ -n "$ts" ]]; then
        printf '%s' "$ts"
    else
        date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S'
    fi
}

_amma_gen_id() {
    local prefix="${1:-mem}"
    local rand
    rand=$(od -An -tx1 -N8 /dev/urandom 2>/dev/null | tr -d ' \n' | head -c 16)
    if [[ -z "$rand" ]]; then
        rand="$(printf '%04x%04x%04x%04x' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM")"
    fi
    printf '%s_%s_%s' "$prefix" "$(_amma_epoch)" "${rand:0:12}"
}

_amma_json_escape() {
    local str="$1"
    # Escape backslashes first
    str="${str//\\/\\\\}"
    # Escape double quotes
    str="${str//\"/\\\"}"
    # Escape newlines
    str="${str//$'\n'/\\n}"
    # Escape carriage returns
    str="${str//$'\r'/\\r}"
    # Escape tabs
    str="${str//$'\t'/\\t}"
    # Remove control characters (simple approach for portability)
    str="${str//[^[:print:][:space:]]/}"
    printf '%s' "$str"
}

_amma_estimate_tokens() {
    local content="$1"
    local char_count=${#content}
    printf '%d' $(( (char_count + AMMA_CHARS_PER_TOKEN - 1) / AMMA_CHARS_PER_TOKEN ))
}

_amma_validate_tier() {
    local tier="$1"
    case "$tier" in
        L1|L2|L3|L4|L5) return 0 ;;
        *) return 1 ;;
    esac
}

_amma_importance_to_score() {
    case "$1" in
        "$AMMA_IMPORTANCE_CRITICAL") printf '%d' "$AMMA_SCORE_CRITICAL" ;;
        "$AMMA_IMPORTANCE_HIGH") printf '%d' "$AMMA_SCORE_HIGH" ;;
        "$AMMA_IMPORTANCE_NORMAL") printf '%d' "$AMMA_SCORE_NORMAL" ;;
        "$AMMA_IMPORTANCE_LOW") printf '%d' "$AMMA_SCORE_LOW" ;;
        *) printf '%d' "$AMMA_SCORE_NORMAL" ;;
    esac
}

# =============================================================================
# PATH HELPERS
# =============================================================================

_amma_session_path() {
    printf '%s/sessions/%s' "$AMMA_ROOT" "${_AMMA_SESSION_ID:-default}"
}

_amma_l1_path() {
    printf '%s/l1_context' "$(_amma_session_path)"
}

_amma_l2_path() {
    printf '%s/l2_working' "$(_amma_session_path)"
}

_amma_l3_path() {
    printf '%s/l3_short' "$(_amma_session_path)"
}

_amma_l4_path() {
    printf '%s/l4_long' "$AMMA_ROOT"
}

_amma_l5_path() {
    printf '%s/l5_external' "$AMMA_ROOT"
}

_amma_ensure_dirs() {
    local session_path
    session_path=$(_amma_session_path)
    
    # L1: Shell-compatible exports (in-memory, but persist manifest)
    mkdir -p "$session_path"
    
    # L2: Working memory
    mkdir -p "$(_amma_l2_path)"/{episodes,facts,patterns,checkpoints,meta}
    
    # L3: Short-term memory
    mkdir -p "$(_amma_l3_path)"/{compressed,summaries}
    
    # L4: Long-term memory (global, not session-specific)
    mkdir -p "$(_amma_l4_path)"/{episodes,facts,patterns,vectors}
    
    # L5: External memory (sync pointers)
    mkdir -p "$(_amma_l5_path)"/pointers
}

# =============================================================================
# ATOMIC FILE OPERATIONS
# =============================================================================

_amma_atomic_write() {
    local target="$1"
    local content="$2"
    local dir
    dir="${target%/*}"
    
    [[ "$dir" != "$target" ]] && mkdir -p "$dir" 2>/dev/null
    
    local tmpfile
    tmpfile="${target}.tmp.$$.$RANDOM"
    
    if ! printf '%s' "$content" > "$tmpfile" 2>/dev/null; then
        rm -f "$tmpfile" 2>/dev/null
        return 1
    fi
    
    if ! mv -f "$tmpfile" "$target" 2>/dev/null; then
        rm -f "$tmpfile" 2>/dev/null
        return 1
    fi
    
    return 0
}

_amma_atomic_read() {
    local target="$1"
    if [[ -f "$target" ]]; then
        cat "$target" 2>/dev/null
    fi
    # Always return 0 - empty output means file doesn't exist or is empty
    return 0
}

# =============================================================================
# MANIFEST MANAGEMENT
# =============================================================================

_amma_manifest_path() {
    printf '%s/manifest.json' "$(_amma_session_path)"
}

_amma_manifest_write() {
    local manifest_path
    manifest_path=$(_amma_manifest_path)
    
    local parent_val="null"
    [[ -n "$_AMMA_PARENT_SESSION" ]] && parent_val="\"$_AMMA_PARENT_SESSION\""
    
    local manifest
    manifest=$(printf '{\
        "schema":"amma.v3.manifest",\
        "version":"%s",\
        "session_id":"%s",\
        "agent_id":"%s",\
        "parent_session":%s,\
        "namespace":"%s",\
        "created_at":"%s",\
        "updated_at":"%s",\
        "stats":{"episodes":%d,"facts":%d,"patterns":%d,"checkpoints":%d}\
    }' \
        "$AMMA_SCHEMA_VERSION" \
        "$_AMMA_SESSION_ID" \
        "$_AMMA_AGENT_ID" \
        "$parent_val" \
        "$_AMMA_NAMESPACE" \
        "$_AMMA_START_TIME" \
        "$(_amma_iso_timestamp)" \
        "$_AMMA_EPISODE_COUNT" \
        "$_AMMA_FACT_COUNT" \
        "$_AMMA_PATTERN_COUNT" \
        "${_AMMA_CHECKPOINT_COUNT:-0}")
    
    _amma_atomic_write "$manifest_path" "$manifest"
}

_amma_manifest_read() {
    local manifest_path
    manifest_path=$(_amma_manifest_path)
    _amma_atomic_read "$manifest_path"
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# @pre: none
# @post: AMMA initialized with session and namespace
# @returns: USOP JSON with session info
#
# Initialize AMMA memory system for current session.
#
# Usage: ammma_init [--session NAME] [--agent NAME] [--parent ID]
# Example: ammma_init --session "feature-x" --agent "builder-1" --parent "sess_123"
ammma_init() {
    local start_time
    start_time=$(_amma_timestamp)
    
    local session_name=""
    local agent_id=""
    local parent_session=""
    local namespace="default"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --session)
                session_name="$2"
                shift 2
                ;;
            --agent)
                agent_id="$2"
                shift 2
                ;;
            --parent)
                parent_session="$2"
                shift 2
                ;;
            --namespace)
                namespace="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Generate IDs if not provided
    _AMMA_SESSION_ID="${session_name:-$(_amma_gen_id sess)}"
    _AMMA_AGENT_ID="${agent_id:-$(_amma_gen_id agent)}"
    _AMMA_PARENT_SESSION="$parent_session"
    _AMMA_NAMESPACE="$namespace"
    _AMMA_START_TIME="$(_amma_iso_timestamp)"
    
    # Ensure directories exist
    _amma_ensure_dirs
    
    # Initialize L1 (clear any previous state)
    _AMMA_L1_MEMORY=()
    _AMMA_L1_META=()
    _AMMA_L1_TOKENS=()
    _AMMA_ATTENTION_WINDOW=()
    
    # Try to recover L2 state if session exists
    _amma_recover_session
    
    # Inherit from parent if specified
    if [[ -n "$parent_session" ]]; then
        _amma_inherit_from_parent "$parent_session"
    fi
    
    _AMMA_INITIALIZED=true
    
    # Write initial manifest
    _amma_manifest_write
    
    _amma_log info "AMMA initialized: session=$_AMMA_SESSION_ID, agent=$_AMMA_AGENT_ID"
    
    # Calculate elapsed
    local end_time elapsed
    end_time=$(_amma_timestamp)
    elapsed=$(echo "($end_time - $start_time) * 1000" | bc 2>/dev/null || echo "0")
    elapsed="${elapsed%.*}"
    [[ -z "$elapsed" ]] && elapsed="0"
    
    # Output USOP response
    local data
    data=$(printf '{"session_id":"%s","agent_id":"%s","namespace":"%s","initialized":true}' \
        "$_AMMA_SESSION_ID" "$_AMMA_AGENT_ID" "$_AMMA_NAMESPACE")
    _amma_usop_success "$data" "ammma_episode_log" "$elapsed"
}

# @pre: AMMA initialized
# @post: AMMA session closed and state persisted
# @returns: USOP JSON with close status
#
# Close AMMA memory system and persist all state.
#
# Usage: ammma_close
ammma_close() {
    local start_time
    start_time=$(_amma_timestamp)
    
    if [[ "$_AMMA_INITIALIZED" != "true" ]]; then
        _amma_usop_error "NOT_INITIALIZED" "AMMA not initialized. Call amma_init first." "Call ammma_init before closing"
        return 1
    fi
    
    # Persist L1 context
    _amma_persist_l1
    
    # Update manifest
    _amma_manifest_write
    
    # Clear L1 memory
    _AMMA_L1_MEMORY=()
    _AMMA_L1_META=()
    _AMMA_L1_TOKENS=()
    _AMMA_ATTENTION_WINDOW=()
    
    _AMMA_INITIALIZED=false
    
    _amma_log info "AMMA closed: session=$_AMMA_SESSION_ID"
    
    local end_time elapsed
    end_time=$(_amma_timestamp)
    elapsed=$(echo "($end_time - $start_time) * 1000" | bc 2>/dev/null || echo "0")
    elapsed="${elapsed%.*}"
    [[ -z "$elapsed" ]] && elapsed="0"
    
    local data
    data='{"closed":true,"session_id":"'"$_AMMA_SESSION_ID"'"}'
    _amma_usop_success "$data" "" "$elapsed"
}

# =============================================================================
# SESSION RECOVERY AND INHERITANCE
# =============================================================================

_amma_recover_session() {
    local manifest
    manifest=$(_amma_manifest_read)
    
    if [[ -n "$manifest" ]]; then
        _amma_log debug "Recovering existing session: $_AMMA_SESSION_ID"
        
        # Extract stats from manifest (pure bash extraction)
        local episode_count fact_count pattern_count
        episode_count=$(echo "$manifest" | grep -o '"episodes":[0-9]*' | head -1 | cut -d: -f2)
        fact_count=$(echo "$manifest" | grep -o '"facts":[0-9]*' | head -1 | cut -d: -f2)
        pattern_count=$(echo "$manifest" | grep -o '"patterns":[0-9]*' | head -1 | cut -d: -f2)
        
        _AMMA_EPISODE_COUNT="${episode_count:-0}"
        _AMMA_FACT_COUNT="${fact_count:-0}"
        _AMMA_PATTERN_COUNT="${pattern_count:-0}"
        
        # Load high-importance memories into L1
        local l2_path
        l2_path=$(_amma_l2_path)
        
        if [[ -d "$l2_path/episodes" ]]; then
            local l2_files
            l2_files=$(find "$l2_path/episodes" -name "*.json" 2>/dev/null)
            
            if [[ -n "$l2_files" ]]; then
                while IFS= read -r mem_file; do
                    [[ -f "$mem_file" ]] || continue
                    
                    local memory
                    memory=$(_amma_atomic_read "$mem_file")
                    [[ -z "$memory" ]] && continue
                    
                    local importance
                    importance=$(echo "$memory" | grep -o '"importance":"[^"]*"' | head -1 | cut -d'"' -f4)
                    
                    if [[ "$importance" == "$AMMA_IMPORTANCE_CRITICAL" ]]; then
                        local mem_id
                        mem_id=$(basename "$mem_file" .json)
                        _AMMA_L1_MEMORY["$mem_id"]="$memory"
                        _AMMA_L1_META["$mem_id"]="{\"tier\":\"$AMMA_TIER_L1\",\"stored_at\":$(_amma_timestamp)}"
                        _amma_attention_add "$mem_id"
                    fi
                done <<< "$l2_files"
            fi
        fi
    fi
}

_amma_inherit_from_parent() {
    local parent_id="$1"
    local parent_path="$AMMA_ROOT/sessions/$parent_id"
    
    if [[ ! -d "$parent_path" ]]; then
        _amma_log warn "Parent session not found: $parent_id"
        return 1
    fi
    
    _amma_log debug "Inheriting from parent session: $parent_id"
    
    # Inherit critical checkpoints
    local parent_l2="$parent_path/l2_working/checkpoints"
    if [[ -d "$parent_l2" ]]; then
        local l2_path
        l2_path=$(_amma_l2_path)
        
        local parent_files
        parent_files=$(find "$parent_l2" -name "*.json" 2>/dev/null)
        
        if [[ -n "$parent_files" ]]; then
            while IFS= read -r chk_file; do
                [[ -f "$chk_file" ]] || continue
                
                local memory
                memory=$(_amma_atomic_read "$chk_file")
                [[ -z "$memory" ]] && continue
                
                local importance
                importance=$(echo "$memory" | grep -o '"importance":"[^"]*"' | head -1 | cut -d'"' -f4)
                
                if [[ "$importance" == "$AMMA_IMPORTANCE_CRITICAL" ]] || [[ "$importance" == "$AMMA_IMPORTANCE_HIGH" ]]; then
                    local mem_id
                    mem_id=$(basename "$chk_file" .json)
                    cp "$chk_file" "$l2_path/checkpoints/"
                    
                    # Also load into L1
                    _AMMA_L1_MEMORY["$mem_id"]="$memory"
                    _AMMA_L1_META["$mem_id"]="{\"tier\":\"$AMMA_TIER_L1\",\"inherited_from\":\"$parent_id\",\"stored_at\":$(_amma_timestamp)}"
                    _amma_attention_add "$mem_id"
                fi
            done <<< "$parent_files"
        fi
    fi
}

_amma_persist_l1() {
    local l1_path
    l1_path=$(_amma_l1_path)
    mkdir -p "$l1_path"
    
    # Create shell-compatible exports file
    local exports_file="$l1_path/exports.sh"
    {
        echo "#!/usr/bin/env bash"
        echo "# AMMA L1 Context Exports - Auto-generated"
        echo "# Session: $_AMMA_SESSION_ID"
        echo "# Generated: $(_amma_iso_timestamp)"
        echo ""
        echo "export AMMA_SESSION_ID='$_AMMA_SESSION_ID'"
        echo "export AMMA_AGENT_ID='$_AMMA_AGENT_ID'"
        echo "export AMMA_NAMESPACE='$_AMMA_NAMESPACE'"
        echo ""
        
        for mem_id in "${!_AMMA_L1_MEMORY[@]}"; do
            local memory="${_AMMA_L1_MEMORY[$mem_id]}"
            local content
            content=$(echo "$memory" | grep -o '"description":"[^"]*"' | head -1 | cut -d'"' -f4)
            if [[ -n "$content" ]]; then
                local escaped_content
                escaped_content=$(_amma_json_escape "$content")
                printf "export AMMA_MEM_%s='%s'\n" "$mem_id" "$escaped_content"
            fi
        done
    } > "$exports_file"
}

# =============================================================================
# MEMORY CREATION
# =============================================================================

# Internal: Create base memory structure
_amma_memory_create() {
    local type="$1"
    local content="$2"
    local importance="${3:-$AMMA_IMPORTANCE_NORMAL}"
    local scope="${4:-$AMMA_SCOPE_PRIVATE}"
    local tier="${5:-$AMMA_TIER_L2}"
    
    local mem_id
    mem_id=$(_amma_gen_id "mem")
    
    local timestamp
    timestamp=$(_amma_timestamp)
    # shellcheck disable=SC2034
    local iso_ts
    iso_ts=$(_amma_iso_timestamp)
    
    local escaped_content
    escaped_content=$(_amma_json_escape "$content")
    
    local tokens
    tokens=$(_amma_estimate_tokens "$content")
    
    printf '{\
        "_schema":"amma.v3.memory",\
        "_version":"%s",\
        "id":"%s",\
        "type":"%s",\
        "tier":"%s",\
        "content":{\
            "description":"%s",\
            "importance":"%s",\
            "tokens":%d\
        },\
        "metadata":{\
            "created_at":%s,\
            "updated_at":%s,\
            "access_count":0,\
            "importance_score":%s,\
            "session_id":"%s",\
            "agent_id":"%s",\
            "namespace":"%s"\
        },\
        "sharing":{\
            "scope":"%s"\
        }\
    }' \
        "$AMMA_SCHEMA_VERSION" \
        "$mem_id" \
        "$type" \
        "$tier" \
        "$escaped_content" \
        "$importance" \
        "$tokens" \
        "$timestamp" \
        "$timestamp" \
        "$(_amma_importance_to_score "$importance")" \
        "${_AMMA_SESSION_ID:-}" \
        "${_AMMA_AGENT_ID:-}" \
        "${_AMMA_NAMESPACE:-}" \
        "$scope"
}

# @pre: AMMA initialized
# @post: Episodic memory stored
# @returns: USOP JSON with memory ID
#
# Log an episodic memory (event with context).
#
# Usage: amma_episode_log --content "text" [--importance low|normal|high|critical]
# Example: amma_episode_log --content "Fixed bug #123" --importance high
ammma_episode_log() {
    local start_time
    start_time=$(_amma_timestamp)
    
    if [[ "$_AMMA_INITIALIZED" != "true" ]]; then
        _amma_usop_error "NOT_INITIALIZED" "AMMA not initialized. Call ammma_init first." "Call ammma_init before logging episodes"
        return 1
    fi
    
    local content=""
    local importance="$AMMA_IMPORTANCE_NORMAL"
    local scope="$AMMA_SCOPE_PRIVATE"
    local tags=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --content)
                content="$2"
                shift 2
                ;;
            --importance)
                importance="$2"
                shift 2
                ;;
            --scope)
                scope="$2"
                shift 2
                ;;
            --tags)
                # shellcheck disable=SC2034
                tags="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ -z "$content" ]]; then
        _amma_usop_error "MISSING_CONTENT" "Content required for episodic memory" "Provide --content argument"
        return 1
    fi
    
    # Validate importance
    case "$importance" in
        low|normal|high|critical) ;;
        *) importance="$AMMA_IMPORTANCE_NORMAL" ;;
    esac
    
    # Create memory entry
    local memory
    memory=$(_amma_memory_create "$AMMA_TYPE_EPISODIC" "$content" "$importance" "$scope")
    
    # Extract memory ID
    local mem_id
    mem_id=$(echo "$memory" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    # Store in L2
    _amma_l2_store "$mem_id" "$memory"
    
    # Also store in L1 if high importance
    if [[ "$importance" == "$AMMA_IMPORTANCE_CRITICAL" ]] || [[ "$importance" == "$AMMA_IMPORTANCE_HIGH" ]]; then
        _AMMA_L1_MEMORY["$mem_id"]="$memory"
        _AMMA_L1_META["$mem_id"]="{\"tier\":\"$AMMA_TIER_L1\",\"stored_at\":$(_amma_timestamp)}"
        local tokens
        tokens=$(echo "$memory" | grep -o '"tokens":[0-9]*' | head -1 | cut -d: -f2)
        _AMMA_L1_TOKENS["$mem_id"]="${tokens:-0}"
        _amma_attention_add "$mem_id"
    fi
    
    _AMMA_EPISODE_COUNT=$((_AMMA_EPISODE_COUNT + 1))
    _AMMA_MEMORY_COUNT=$((_AMMA_MEMORY_COUNT + 1))
    
    # Update manifest
    _amma_manifest_write
    
    _amma_log debug "Episodic memory stored: $mem_id"
    
    local end_time elapsed
    end_time=$(_amma_timestamp)
    elapsed=$(echo "($end_time - $start_time) * 1000" | bc 2>/dev/null || echo "0")
    elapsed="${elapsed%.*}"
    [[ -z "$elapsed" ]] && elapsed="0"
    
    local data
    data="{\"memory_id\":\"$mem_id\",\"tier\":\"$([[ \"$importance\" == \"$AMMA_IMPORTANCE_CRITICAL\" ]] || [[ \"$importance\" == \"$AMMA_IMPORTANCE_HIGH\" ]] && echo L1 || echo L2)\"}"
    _amma_usop_success "$data" "ammma_retrieve" "$elapsed"
}

# @pre: AMMA initialized
# @post: Declarative fact stored
# @returns: USOP JSON with fact ID
#
# Store a declarative fact (knowledge triple: subject-predicate-object).
#
# Usage: amma_fact_store --subject "..." --predicate "..." --object "..."
# Example: amma_fact_store --subject "Python" --predicate "is" --object "typed"
ammma_fact_store() {
    local start_time
    start_time=$(_amma_timestamp)
    
    if [[ "$_AMMA_INITIALIZED" != "true" ]]; then
        _amma_usop_error "NOT_INITIALIZED" "AMMA not initialized" "Call ammma_init before storing facts"
        return 1
    fi
    
    local subject=""
    local predicate=""
    local object=""
    local confidence="0.9"
    local importance="$AMMA_IMPORTANCE_NORMAL"
    local source=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --subject) subject="$2"; shift 2 ;;
            --predicate) predicate="$2"; shift 2 ;;
            --object) object="$2"; shift 2 ;;
            --confidence) confidence="$2"; shift 2 ;;
            --importance) importance="$2"; shift 2 ;;
            --source)
                # shellcheck disable=SC2034
                source="$2"
                shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$subject" || -z "$predicate" || -z "$object" ]]; then
        _amma_usop_error "MISSING_ARGUMENTS" "Subject, predicate, and object required" "Provide --subject, --predicate, and --object"
        return 1
    fi
    
    local content="$subject $predicate $object"
    local memory
    memory=$(_amma_memory_create "$AMMA_TYPE_DECLARATIVE" "$content" "$importance")
    
    # Add fact-specific fields
    local mem_id
    mem_id=$(echo "$memory" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    # Enhance with triple structure
    local enhanced_memory
    # shellcheck disable=SC2001
    enhanced_memory=$(echo "$memory" | sed 's/"sharing":{/"triple":{"subject":"'"$(_amma_json_escape "$subject")"'","predicate":"'"$(_amma_json_escape "$predicate")"'","object":"'"$(_amma_json_escape "$object")"'","confidence":'"$confidence"'},"sharing":/')
    
    # Store in L2
    _amma_l2_store "$mem_id" "$enhanced_memory"
    
    # Also store in L4 facts for persistence
    local l4_path
    l4_path=$(_amma_l4_path)
    _amma_atomic_write "$l4_path/facts/$mem_id.json" "$enhanced_memory"
    
    _AMMA_FACT_COUNT=$((_AMMA_FACT_COUNT + 1))
    _AMMA_MEMORY_COUNT=$((_AMMA_MEMORY_COUNT + 1))
    
    # Update manifest
    _amma_manifest_write
    
    _amma_log debug "Fact stored: $mem_id"
    
    local end_time elapsed
    end_time=$(_amma_timestamp)
    elapsed=$(echo "($end_time - $start_time) * 1000" | bc 2>/dev/null || echo "0")
    elapsed="${elapsed%.*}"
    [[ -z "$elapsed" ]] && elapsed="0"
    
    local data
    data="{\"memory_id\":\"$mem_id\",\"type\":\"declarative\"}"
    _amma_usop_success "$data" "ammma_fact_query" "$elapsed"
}

# @pre: AMMA initialized
# @post: Procedural pattern stored
# @returns: USOP JSON with pattern ID
#
# Store a procedural pattern (learned workflow: trigger -> action).
#
# Usage: amma_pattern_learn --name "..." --trigger "..." --action "..."
# Example: amma_pattern_learn --name "git_commit" --trigger "files changed" --action "git add . && git commit"
ammma_pattern_learn() {
    local start_time
    start_time=$(_amma_timestamp)
    
    if [[ "$_AMMA_INITIALIZED" != "true" ]]; then
        _amma_usop_error "NOT_INITIALIZED" "AMMA not initialized" "Call ammma_init before learning patterns"
        return 1
    fi
    
    local name=""
    local trigger=""
    local action=""
    local importance="$AMMA_IMPORTANCE_NORMAL"
    local condition=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --trigger) trigger="$2"; shift 2 ;;
            --action) action="$2"; shift 2 ;;
            --importance) importance="$2"; shift 2 ;;
            --condition) condition="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$name" || -z "$trigger" || -z "$action" ]]; then
        _amma_usop_error "MISSING_ARGUMENTS" "Name, trigger, and action required" "Provide --name, --trigger, and --action"
        return 1
    fi
    
    local content="Pattern: $name | Trigger: $trigger | Action: $action"
    [[ -n "$condition" ]] && content="$content | Condition: $condition"
    
    local memory
    memory=$(_amma_memory_create "$AMMA_TYPE_PROCEDURAL" "$content" "$importance")
    
    local mem_id
    mem_id=$(echo "$memory" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    # Enhance with pattern structure
    local enhanced_memory
    # shellcheck disable=SC2001
    enhanced_memory=$(echo "$memory" | sed 's/"sharing":{/"pattern":{"name":"'"$(_amma_json_escape "$name")"'","trigger":"'"$(_amma_json_escape "$trigger")"'","action":"'"$(_amma_json_escape "$action")"'"'"$([[ -n "$condition" ]] && echo ",\"condition\":\"$(_amma_json_escape "$condition")\"")"'},"sharing":/')
    
    # Store in L2
    _amma_l2_store "$mem_id" "$enhanced_memory"
    
    # Also store in L4 patterns
    local l4_path
    l4_path=$(_amma_l4_path)
    _amma_atomic_write "$l4_path/patterns/$mem_id.json" "$enhanced_memory"
    
    _AMMA_PATTERN_COUNT=$((_AMMA_PATTERN_COUNT + 1))
    _AMMA_MEMORY_COUNT=$((_AMMA_MEMORY_COUNT + 1))
    
    # Update manifest
    _amma_manifest_write
    
    _amma_log debug "Pattern learned: $mem_id"
    
    local end_time elapsed
    end_time=$(_amma_timestamp)
    elapsed=$(echo "($end_time - $start_time) * 1000" | bc 2>/dev/null || echo "0")
    elapsed="${elapsed%.*}"
    [[ -z "$elapsed" ]] && elapsed="0"
    
    local data
    data="{\"memory_id\":\"$mem_id\",\"type\":\"procedural\",\"name\":\"$(_amma_json_escape "$name")\"}"
    _amma_usop_success "$data" "ammma_pattern_learn" "$elapsed"
}

# @pre: AMMA initialized
# @post: Checkpoint stored
# @returns: USOP JSON with checkpoint ID
#
# Store a checkpoint (key-value state snapshot).
#
# Usage: ammma_checkpoint_set --key "..." --value "..."
# Example: ammma_checkpoint_set --key "build_state" --value "compiled"
ammma_checkpoint_set() {
    local start_time
    start_time=$(_amma_timestamp)
    
    if [[ "$_AMMA_INITIALIZED" != "true" ]]; then
        _amma_usop_error "NOT_INITIALIZED" "AMMA not initialized" "Call ammma_init before setting checkpoints"
        return 1
    fi
    
    local key=""
    local value=""
    local importance="$AMMA_IMPORTANCE_NORMAL"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key) key="$2"; shift 2 ;;
            --value) value="$2"; shift 2 ;;
            --importance) importance="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$key" ]]; then
        _amma_usop_error "MISSING_KEY" "Key required for checkpoint" "Provide --key argument"
        return 1
    fi
    
    local content="Checkpoint: $key = $value"
    local memory
    memory=$(_amma_memory_create "$AMMA_TYPE_CHECKPOINT" "$content" "$importance")
    
    local mem_id
    mem_id=$(echo "$memory" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    # Enhance with checkpoint structure
    local escaped_key
    escaped_key=$(_amma_json_escape "$key")
    local escaped_value
    escaped_value=$(_amma_json_escape "$value")
    
    local enhanced_memory
    # shellcheck disable=SC2001
    enhanced_memory=$(echo "$memory" | sed 's/"sharing":{/"checkpoint":{"key":"'"$escaped_key"'","value":"'"$escaped_value"'"},"sharing":/')
    
    # Store in L2 checkpoints
    local l2_path
    l2_path=$(_amma_l2_path)
    _amma_atomic_write "$l2_path/checkpoints/$mem_id.json" "$enhanced_memory"
    
    # Also store in L1 if high importance
    if [[ "$importance" == "$AMMA_IMPORTANCE_CRITICAL" ]] || [[ "$importance" == "$AMMA_IMPORTANCE_HIGH" ]]; then
        _AMMA_L1_MEMORY["$mem_id"]="$enhanced_memory"
        _AMMA_L1_META["$mem_id"]="{\"tier\":\"$AMMA_TIER_L1\",\"stored_at\":$(_amma_timestamp)}"
        _amma_attention_add "$mem_id"
    fi
    
    _AMMA_CHECKPOINT_COUNT=$((_AMMA_CHECKPOINT_COUNT + 1))
    _AMMA_MEMORY_COUNT=$((_AMMA_MEMORY_COUNT + 1))
    
    # Update manifest
    _amma_manifest_write
    
    _amma_log debug "Checkpoint set: $key -> $mem_id"
    
    local end_time elapsed
    end_time=$(_amma_timestamp)
    elapsed=$(echo "($end_time - $start_time) * 1000" | bc 2>/dev/null || echo "0")
    elapsed="${elapsed%.*}"
    [[ -z "$elapsed" ]] && elapsed="0"
    
    local data
    data="{\"checkpoint_id\":\"$mem_id\",\"key\":\"$escaped_key\"}"
    _amma_usop_success "$data" "ammma_checkpoint_get" "$elapsed"
}

# =============================================================================
# MEMORY RETRIEVAL
# =============================================================================

# @pre: AMMA initialized
# @post: Returns matching memories
# @returns: USOP JSON array of memories
#
# Retrieve memories using search across specified tiers.
#
# Usage: ammma_retrieve --query "..." [--limit N] [--tier L1|L2|L3|L4|L5]
# Example: ammma_retrieve --query "FastAPI error" --limit 5 --tier L2
ammma_retrieve() {
    local start_time
    start_time=$(_amma_timestamp)
    
    if [[ "$_AMMA_INITIALIZED" != "true" ]]; then
        _amma_usop_error "NOT_INITIALIZED" "AMMA not initialized" "Call ammma_init before retrieving"
        return 1
    fi
    
    local query=""
    local limit=10
    local tier=""
    local min_score=0.5
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --query)
                query="$2"
                shift 2
                ;;
            --limit)
                limit="$2"
                shift 2
                ;;
            --tier)
                tier="$2"
                shift 2
                ;;
            --min-score)
                # shellcheck disable=SC2034
                min_score="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ -z "$query" ]]; then
        _amma_usop_error "MISSING_QUERY" "Query required for retrieval" "Provide --query argument"
        return 1
    fi
    
    # Validate limit
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
        limit=10
    fi
    
    _AMMA_RETRIEVAL_COUNT=$((_AMMA_RETRIEVAL_COUNT + 1))
    
    # Collect results
    local results=()
    local count=0
    
    # Search specified tier(s) or all
    local search_l1=true
    local search_l2=true
    local search_l3=false
    local search_l4=false
    local search_l5=false
    
    if [[ -n "$tier" ]]; then
        search_l1=false
        search_l2=false
        case "$tier" in
            L1) search_l1=true ;;
            L2) search_l2=true ;;
            L3) search_l3=true ;;
            L4) search_l4=true ;;
            L5)
                # shellcheck disable=SC2034
                search_l5=true ;;
        esac
    fi
    
    # Search L1 (immediate context) - highest priority
    if [[ "$search_l1" == "true" ]]; then
        for mem_id in "${_AMMA_ATTENTION_WINDOW[@]}"; do
            [[ $count -ge $limit ]] && break
            [[ -n "${_AMMA_L1_MEMORY[$mem_id]:-}" ]] || continue
            
            local memory="${_AMMA_L1_MEMORY[$mem_id]}"
            local content
            content=$(echo "$memory" | grep -o '"description":"[^"]*"' | head -1 | cut -d'"' -f4)
            
            if [[ "${content,,}" == *"${query,,}"* ]]; then
                results+=("$memory")
                : $((count++))
            fi
        done
    fi
    
    # Search L2 (working memory)
    if [[ "$search_l2" == "true" && $count -lt $limit ]]; then
        local l2_path
        l2_path=$(_amma_l2_path)
        
        local l2_files
        l2_files=$(find "$l2_path/episodes" -name "*.json" 2>/dev/null)
        
        if [[ -n "$l2_files" ]]; then
            while IFS= read -r mem_file; do
                [[ $count -ge $limit ]] && break
                [[ -f "$mem_file" ]] || continue
                
                local mem_id
                mem_id=$(basename "$mem_file" .json)
                
                # Skip if already in results
                local already_found=false
                for result in "${results[@]}"; do
                    if [[ "$result" == *"\"id\":\"$mem_id\""* ]]; then
                        already_found=true
                        break
                    fi
                done
                [[ "$already_found" == "true" ]] && continue
                
                if grep -qi "$query" "$mem_file" 2>/dev/null; then
                    local memory
                    memory=$(_amma_atomic_read "$mem_file")
                    [[ -n "$memory" ]] && results+=("$memory")
                    : $((count++))
                fi
            done <<< "$l2_files"
        fi
    fi
    
    # Search L3 (short-term)
    if [[ "$search_l3" == "true" && $count -lt $limit ]]; then
        local l3_path
        l3_path=$(_amma_l3_path)
        
        local l3_files
        l3_files=$(find "$l3_path/summaries" -name "*.json" 2>/dev/null)
        
        if [[ -n "$l3_files" ]]; then
            while IFS= read -r mem_file; do
                [[ $count -ge $limit ]] && break
                [[ -f "$mem_file" ]] || continue
                
                if grep -qi "$query" "$mem_file" 2>/dev/null; then
                    local memory
                    memory=$(_amma_atomic_read "$mem_file")
                    [[ -n "$memory" ]] && results+=("$memory")
                    : $((count++))
                fi
            done <<< "$l3_files"
        fi
    fi
    
    # Search L4 (long-term)
    if [[ "$search_l4" == "true" && $count -lt $limit ]]; then
        local l4_path
        l4_path=$(_amma_l4_path)
        
        for dir in episodes facts patterns; do
            [[ $count -ge $limit ]] && break
            [[ -d "$l4_path/$dir" ]] || continue
            
            local l4_files
            l4_files=$(find "$l4_path/$dir" -name "*.json" 2>/dev/null)
            
            if [[ -n "$l4_files" ]]; then
                while IFS= read -r mem_file; do
                    [[ $count -ge $limit ]] && break
                    [[ -f "$mem_file" ]] || continue
                    
                    if grep -qi "$query" "$mem_file" 2>/dev/null; then
                        local memory
                        memory=$(_amma_atomic_read "$mem_file")
                        [[ -n "$memory" ]] && results+=("$memory")
                        : $((count++))
                    fi
                done <<< "$l4_files"
            fi
        done
    fi
    
    # Build response
    local data="["
    local first=true
    for result in "${results[@]}"; do
        $first || data="$data,"
        first=false
        data="$data$result"
    done
    data="$data]"
    
    local end_time elapsed
    end_time=$(_amma_timestamp)
    elapsed=$(echo "($end_time - $start_time) * 1000" | bc 2>/dev/null || echo "0")
    elapsed="${elapsed%.*}"
    [[ -z "$elapsed" ]] && elapsed="0"
    
    local response_data
    response_data="{\"query\":\"$(_amma_json_escape "$query")\",\"results\":$data,\"count\":$count,\"tier\":\"${tier:-all}\"}"
    _amma_usop_success "$response_data" "ammma_episode_get" "$elapsed"
}

# @pre: AMMA initialized
# @post: Returns specific episode
# @returns: USOP JSON with episode data
#
# Get a specific episode by ID.
#
# Usage: ammma_episode_get --id "..."
ammma_episode_get() {
    local start_time
    start_time=$(_amma_timestamp)
    
    if [[ "$_AMMA_INITIALIZED" != "true" ]]; then
        _amma_usop_error "NOT_INITIALIZED" "AMMA not initialized" "Call ammma_init first"
        return 1
    fi
    
    local mem_id=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id) mem_id="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$mem_id" ]]; then
        _amma_usop_error "MISSING_ID" "Memory ID required" "Provide --id argument"
        return 1
    fi
    
    # Try L1 first
    local memory="${_AMMA_L1_MEMORY[$mem_id]:-}"
    
    # Then L2
    if [[ -z "$memory" ]]; then
        local l2_path
        l2_path=$(_amma_l2_path)
        memory=$(_amma_atomic_read "$l2_path/episodes/$mem_id.json")
    fi
    
    # Then L3
    if [[ -z "$memory" ]]; then
        local l3_path
        l3_path=$(_amma_l3_path)
        memory=$(_amma_atomic_read "$l3_path/summaries/$mem_id.json")
    fi
    
    # Then L4
    if [[ -z "$memory" ]]; then
        local l4_path
        l4_path=$(_amma_l4_path)
        for dir in episodes facts patterns; do
            memory=$(_amma_atomic_read "$l4_path/$dir/$mem_id.json")
            [[ -n "$memory" ]] && break
            # Try nested
            memory=$(_amma_atomic_read "$l4_path/$dir"/*"/$mem_id.json" 2>/dev/null)
            [[ -n "$memory" ]] && break
        done
    fi
    
    if [[ -z "$memory" ]]; then
        _amma_usop_error "NOT_FOUND" "Episode not found: $mem_id" "Check the memory ID or try searching"
        return 1
    fi
    
    _AMMA_RETRIEVAL_COUNT=$((_AMMA_RETRIEVAL_COUNT + 1))
    
    local end_time elapsed
    end_time=$(_amma_timestamp)
    elapsed=$(echo "($end_time - $start_time) * 1000" | bc 2>/dev/null || echo "0")
    elapsed="${elapsed%.*}"
    [[ -z "$elapsed" ]] && elapsed="0"
    
    _amma_usop_success "$memory" "ammma_fact_query" "$elapsed"
}

# @pre: AMMA initialized
# @post: Returns matching facts
# @returns: USOP JSON array of facts
#
# Query declarative facts by subject and optional predicate.
#
# Usage: ammma_fact_query --subject "..." [--predicate "..."]
# Example: ammma_fact_query --subject "Python" --predicate "is"
ammma_fact_query() {
    local start_time
    start_time=$(_amma_timestamp)
    
    if [[ "$_AMMA_INITIALIZED" != "true" ]]; then
        _amma_usop_error "NOT_INITIALIZED" "AMMA not initialized" "Call ammma_init first"
        return 1
    fi
    
    local subject=""
    local predicate=""
    local limit=20
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --subject) subject="$2"; shift 2 ;;
            --predicate) predicate="$2"; shift 2 ;;
            --limit) limit="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$subject" ]]; then
        _amma_usop_error "MISSING_SUBJECT" "Subject required for fact query" "Provide --subject argument"
        return 1
    fi
    
    local results=()
    local count=0
    
    # Search L2 and L4 facts
    local l2_path l4_path
    l2_path=$(_amma_l2_path)
    l4_path=$(_amma_l4_path)
    
    for fact_dir in "$l2_path/facts" "$l4_path/facts"; do
        [[ -d "$fact_dir" ]] || continue
        
        for fact_file in "$fact_dir"/*.json; do
            [[ $count -ge $limit ]] && break
            [[ -f "$fact_file" ]] || continue
            
            local memory
            memory=$(_amma_atomic_read "$fact_file")
            [[ -z "$memory" ]] && continue
            
            # Check subject match
            local fact_subject
            fact_subject=$(echo "$memory" | grep -o '"subject":"[^"]*"' | head -1 | cut -d'"' -f4)
            
            if [[ "${fact_subject,,}" == "${subject,,}"* ]]; then
                # Check predicate if specified
                if [[ -n "$predicate" ]]; then
                    local fact_predicate
                    fact_predicate=$(echo "$memory" | grep -o '"predicate":"[^"]*"' | head -1 | cut -d'"' -f4)
                    [[ "${fact_predicate,,}" != "${predicate,,}"* ]] && continue
                fi
                
                results+=("$memory")
                : $((count++))
            fi
        done
    done
    
    # Build response
    local data="["
    local first=true
    for result in "${results[@]}"; do
        $first || data="$data,"
        first=false
        data="$data$result"
    done
    data="$data]"
    
    local end_time elapsed
    end_time=$(_amma_timestamp)
    elapsed=$(echo "($end_time - $start_time) * 1000" | bc 2>/dev/null || echo "0")
    elapsed="${elapsed%.*}"
    [[ -z "$elapsed" ]] && elapsed="0"
    
    local response_data
    response_data="{\"subject\":\"$(_amma_json_escape "$subject")\",\"predicate\":\"$(_amma_json_escape "$predicate")\",\"results\":$data,\"count\":$count}"
    _amma_usop_success "$response_data" "ammma_checkpoint_get" "$elapsed"
}

# @pre: AMMA initialized
# @post: Returns checkpoint value
# @returns: USOP JSON with checkpoint value
#
# Get a checkpoint value by key.
#
# Usage: ammma_checkpoint_get --key "..."
ammma_checkpoint_get() {
    local start_time
    start_time=$(_amma_timestamp)
    
    if [[ "$_AMMA_INITIALIZED" != "true" ]]; then
        _amma_usop_error "NOT_INITIALIZED" "AMMA not initialized" "Call ammma_init first"
        return 1
    fi
    
    local key=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key) key="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$key" ]]; then
        _amma_usop_error "MISSING_KEY" "Key required for checkpoint retrieval" "Provide --key argument"
        return 1
    fi
    
    # Search L1 first
    for mem_id in "${!_AMMA_L1_MEMORY[@]}"; do
        local memory="${_AMMA_L1_MEMORY[$mem_id]}"
        local mem_key
        mem_key=$(echo "$memory" | grep -o '"key":"[^"]*"' | head -1 | cut -d'"' -f4)
        
        if [[ "$mem_key" == "$key" ]]; then
            local value
            value=$(echo "$memory" | grep -o '"value":"[^"]*"' | head -1 | cut -d'"' -f4)
            
            local end_time elapsed
            end_time=$(_amma_timestamp)
            elapsed=$(echo "($end_time - $start_time) * 1000" | bc 2>/dev/null || echo "0")
            elapsed="${elapsed%.*}"
            [[ -z "$elapsed" ]] && elapsed="0"
            
            local data
            data="{\"key\":\"$(_amma_json_escape "$key")\",\"value\":\"$(_amma_json_escape "$value")\",\"checkpoint_id\":\"$mem_id\",\"tier\":\"L1\"}"
            _amma_usop_success "$data" "ammma_context_build" "$elapsed"
            return 0
        fi
    done
    
    # Search L2 checkpoints
    local l2_path
    l2_path=$(_amma_l2_path)
    
    # Search L2 checkpoints (use find to safely handle empty directories)
    local chk_files
    chk_files=$(find "$l2_path/checkpoints" -name "*.json" 2>/dev/null)
    
    if [[ -n "$chk_files" ]]; then
        while IFS= read -r chk_file; do
            [[ -f "$chk_file" ]] || continue
            
            local memory
            memory=$(_amma_atomic_read "$chk_file")
            [[ -z "$memory" ]] && continue
            
            local mem_key
            mem_key=$(echo "$memory" | grep -o '"key":"[^"]*"' | head -1 | cut -d'"' -f4)
            
            if [[ "$mem_key" == "$key" ]]; then
                local value mem_id
                value=$(echo "$memory" | grep -o '"value":"[^"]*"' | head -1 | cut -d'"' -f4)
                mem_id=$(basename "$chk_file" .json)
                
                local end_time elapsed
                end_time=$(_amma_timestamp)
                elapsed=$(echo "($end_time - $start_time) * 1000" | bc 2>/dev/null || echo "0")
                elapsed="${elapsed%.*}"
                [[ -z "$elapsed" ]] && elapsed="0"
                
                local data
                data="{\"key\":\"$(_amma_json_escape "$key")\",\"value\":\"$(_amma_json_escape "$value")\",\"checkpoint_id\":\"$mem_id\",\"tier\":\"L2\"}"
                _amma_usop_success "$data" "ammma_context_build" "$elapsed"
                return 0
            fi
        done <<< "$chk_files"
    fi
    
    _amma_usop_error "NOT_FOUND" "Checkpoint not found: $key" "Set the checkpoint first using ammma_checkpoint_set"
    return 1
}

# @pre: AMMA initialized
# @post: Returns context package for LLM consumption
# @returns: USOP JSON context object
#
# Build context package for current LLM interaction.
#
# Usage: ammma_context_build [--max-tokens N]
ammma_context_build() {
    local start_time
    start_time=$(_amma_timestamp)
    
    if [[ "$_AMMA_INITIALIZED" != "true" ]]; then
        _amma_usop_error "NOT_INITIALIZED" "AMMA not initialized" "Call ammma_init first"
        return 1
    fi
    
    local max_tokens=4000
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-tokens) max_tokens="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    local max_chars=$((max_tokens * AMMA_CHARS_PER_TOKEN))
    local total_chars=0
    local total_tokens=0
    local memories=()
    
    # Add memories from attention window (L1) first
    for mem_id in "${_AMMA_ATTENTION_WINDOW[@]}"; do
        local memory="${_AMMA_L1_MEMORY[$mem_id]:-}"
        [[ -z "$memory" ]] && continue
        
        local mem_chars=${#memory}
        local mem_tokens
        mem_tokens=$(echo "$memory" | grep -o '"tokens":[0-9]*' | head -1 | cut -d: -f2)
        mem_tokens="${mem_tokens:-0}"
        [[ "$mem_tokens" -eq 0 ]] && mem_tokens=$(_amma_estimate_tokens "$memory")
        
        if [[ $((total_chars + mem_chars)) -gt $max_chars ]]; then
            break
        fi
        
        memories+=("$memory")
        total_chars=$((total_chars + mem_chars))
        total_tokens=$((total_tokens + mem_tokens))
    done
    
    # Build memories array
    local mem_array="["
    local first=true
    for memory in "${memories[@]}"; do
        $first || mem_array="$mem_array,"
        first=false
        mem_array="$mem_array$memory"
    done
    mem_array="$mem_array]"
    
    local end_time elapsed
    end_time=$(_amma_timestamp)
    elapsed=$(echo "($end_time - $start_time) * 1000" | bc 2>/dev/null || echo "0")
    elapsed="${elapsed%.*}"
    [[ -z "$elapsed" ]] && elapsed="0"
    
    local data
    data=$(printf '{\
        "session_id":"%s",\
        "agent_id":"%s",\
        "max_tokens":%d,\
        "used_tokens":%d,\
        "used_chars":%d,\
        "memory_count":%d,\
        "memories":%s\
    }' "$_AMMA_SESSION_ID" "$_AMMA_AGENT_ID" "$max_tokens" "$total_tokens" "$total_chars" "${#memories[@]}" "$mem_array")
    
    _amma_usop_success "$data" "ammma_tier_promote" "$elapsed"
}

# =============================================================================
# TIER MANAGEMENT
# =============================================================================

# @pre: AMMA initialized
# @post: Memory promoted to target tier
# @returns: USOP JSON with promotion status
#
# Promote a memory to a higher/faster tier.
#
# Usage: ammma_tier_promote --id "..." --to L1|L2|L3|L4|L5
ammma_tier_promote() {
    local start_time
    start_time=$(_amma_timestamp)
    
    if [[ "$_AMMA_INITIALIZED" != "true" ]]; then
        _amma_usop_error "NOT_INITIALIZED" "AMMA not initialized" "Call ammma_init first"
        return 1
    fi
    
    local mem_id=""
    local to_tier=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id) mem_id="$2"; shift 2 ;;
            --to) to_tier="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$mem_id" || -z "$to_tier" ]]; then
        _amma_usop_error "MISSING_ARGUMENTS" "Memory ID and target tier required" "Provide --id and --to arguments"
        return 1
    fi
    
    # Validate tier
    if ! _amma_validate_tier "$to_tier"; then
        _amma_usop_error "INVALID_TIER" "Invalid tier: $to_tier" "Use L1, L2, L3, L4, or L5"
        return 1
    fi
    
    # Find current location and promote
    local from_tier=""
    local memory=""
    
    # Check L1
    if [[ -n "${_AMMA_L1_MEMORY[$mem_id]:-}" ]]; then
        from_tier="L1"
        memory="${_AMMA_L1_MEMORY[$mem_id]}"
    fi
    
    # Check L2
    if [[ -z "$memory" ]]; then
        local l2_path
        l2_path=$(_amma_l2_path)
        memory=$(_amma_atomic_read "$l2_path/episodes/$mem_id.json")
        [[ -z "$memory" ]] && memory=$(_amma_atomic_read "$l2_path/checkpoints/$mem_id.json")
        [[ -n "$memory" ]] && from_tier="L2"
    fi
    
    # Check L3
    if [[ -z "$memory" ]]; then
        local l3_path
        l3_path=$(_amma_l3_path)
        memory=$(_amma_atomic_read "$l3_path/summaries/$mem_id.json")
        [[ -n "$memory" ]] && from_tier="L3"
    fi
    
    # Check L4
    if [[ -z "$memory" ]]; then
        local l4_path
        l4_path=$(_amma_l4_path)
        for dir in episodes facts patterns; do
            memory=$(_amma_atomic_read "$l4_path/$dir/$mem_id.json")
            [[ -n "$memory" ]] && { from_tier="L4"; break; }
            memory=$(_amma_atomic_read "$l4_path/$dir"/*"/$mem_id.json" 2>/dev/null)
            [[ -n "$memory" ]] && { from_tier="L4"; break; }
        done
    fi
    
    if [[ -z "$memory" ]]; then
        _amma_usop_error "NOT_FOUND" "Memory not found: $mem_id" "Check the memory ID"
        return 1
    fi
    
    # Execute promotion based on source and target
    local result
    case "$from_tier:$to_tier" in
        "L2:L1")
            _AMMA_L1_MEMORY["$mem_id"]="$memory"
            _AMMA_L1_META["$mem_id"]="{\"tier\":\"$AMMA_TIER_L1\",\"promoted_at\":$(_amma_timestamp),\"from\":\"$from_tier\"}"
            local tokens
            tokens=$(echo "$memory" | grep -o '"tokens":[0-9]*' | head -1 | cut -d: -f2)
            _AMMA_L1_TOKENS["$mem_id"]="${tokens:-0}"
            _amma_attention_add "$mem_id"
            result="success"
            ;;
        "L3:L2")
            local l3_path l2_path
            l3_path=$(_amma_l3_path)
            l2_path=$(_amma_l2_path)
            mv "$l3_path/summaries/$mem_id.json" "$l2_path/episodes/" 2>/dev/null || {
                _amma_usop_error "PROMOTE_FAILED" "Failed to promote from L3 to L2" "Check file permissions"
                return 1
            }
            result="success"
            ;;
        "L4:L3")
            local l4_path l3_path
            l4_path=$(_amma_l4_path)
            l3_path=$(_amma_l3_path)
            
            # Find in L4
            local found_file=""
            for dir in episodes facts patterns; do
                found_file=$(find "$l4_path/$dir" -name "$mem_id.json" 2>/dev/null | head -1)
                [[ -n "$found_file" ]] && break
            done
            
            if [[ -n "$found_file" ]]; then
                cp "$found_file" "$l3_path/summaries/"
                result="success"
            else
                _amma_usop_error "PROMOTE_FAILED" "Failed to find memory in L4" "Memory may have been moved"
                return 1
            fi
            ;;
        *)
            _amma_usop_error "INVALID_PROMOTION" "Cannot promote from $from_tier to $to_tier" "Check tier compatibility"
            return 1
            ;;
    esac
    
    # Update LRU tracking
    _AMMA_LRU_TIMES["$mem_id"]=$(_amma_timestamp)
    
    local end_time elapsed
    end_time=$(_amma_timestamp)
    elapsed=$(echo "($end_time - $start_time) * 1000" | bc 2>/dev/null || echo "0")
    elapsed="${elapsed%.*}"
    [[ -z "$elapsed" ]] && elapsed="0"
    
    local data
    data="{\"memory_id\":\"$mem_id\",\"from\":\"$from_tier\",\"to\":\"$to_tier\",\"status\":\"$result\"}"
    _amma_usop_success "$data" "ammma_tier_demote" "$elapsed"
}

# @pre: AMMA initialized
# @post: Memory demoted to target tier
# @returns: USOP JSON with demotion status
#
# Demote a memory to a lower tier.
#
# Usage: ammma_tier_demote --id "..." --to L1|L2|L3|L4|L5
ammma_tier_demote() {
    local start_time
    start_time=$(_amma_timestamp)
    
    if [[ "$_AMMA_INITIALIZED" != "true" ]]; then
        _amma_usop_error "NOT_INITIALIZED" "AMMA not initialized" "Call ammma_init first"
        return 1
    fi
    
    local mem_id=""
    local to_tier=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id) mem_id="$2"; shift 2 ;;
            --to) to_tier="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$mem_id" || -z "$to_tier" ]]; then
        _amma_usop_error "MISSING_ARGUMENTS" "Memory ID and target tier required" "Provide --id and --to arguments"
        return 1
    fi
    
    # Validate tier
    if ! _amma_validate_tier "$to_tier"; then
        _amma_usop_error "INVALID_TIER" "Invalid tier: $to_tier" "Use L1, L2, L3, L4, or L5"
        return 1
    fi
    
    # Find current location
    local from_tier=""
    local memory=""
    
    # Check L1
    if [[ -n "${_AMMA_L1_MEMORY[$mem_id]:-}" ]]; then
        from_tier="L1"
        memory="${_AMMA_L1_MEMORY[$mem_id]}"
    fi
    
    # Check L2
    if [[ -z "$memory" ]]; then
        local l2_path
        l2_path=$(_amma_l2_path)
        memory=$(_amma_atomic_read "$l2_path/episodes/$mem_id.json")
        [[ -z "$memory" ]] && memory=$(_amma_atomic_read "$l2_path/checkpoints/$mem_id.json")
        [[ -n "$memory" ]] && from_tier="L2"
    fi
    
    # Check L3
    if [[ -z "$memory" ]]; then
        local l3_path
        l3_path=$(_amma_l3_path)
        memory=$(_amma_atomic_read "$l3_path/summaries/$mem_id.json")
        [[ -n "$memory" ]] && from_tier="L3"
    fi
    
    if [[ -z "$memory" ]]; then
        _amma_usop_error "NOT_FOUND" "Memory not found: $mem_id" "Check the memory ID"
        return 1
    fi
    
    # Execute demotion
    local result
    case "$from_tier:$to_tier" in
        "L1:L2")
            # Remove from L1 (already persisted in L2 during creation)
            unset "_AMMA_L1_MEMORY[$mem_id]"
            unset "_AMMA_L1_META[$mem_id]"
            unset "_AMMA_L1_TOKENS[$mem_id]"
            
            # Remove from attention window
            local new_window=()
            for id in "${_AMMA_ATTENTION_WINDOW[@]}"; do
                [[ "$id" == "$mem_id" ]] && continue
                new_window+=("$id")
            done
            _AMMA_ATTENTION_WINDOW=("${new_window[@]}")
            result="success"
            ;;
        "L2:L3")
            local l2_path l3_path
            l2_path=$(_amma_l2_path)
            l3_path=$(_amma_l3_path)
            
            # Find and move
            for subdir in episodes checkpoints; do
                if [[ -f "$l2_path/$subdir/$mem_id.json" ]]; then
                    mv "$l2_path/$subdir/$mem_id.json" "$l3_path/summaries/"
                    result="success"
                    break
                fi
            done
            ;;
        "L3:L4")
            local l3_path l4_path
            l3_path=$(_amma_l3_path)
            l4_path=$(_amma_l4_path)
            
            if [[ -f "$l3_path/summaries/$mem_id.json" ]]; then
                # Determine type for organization
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
                year_month=$(date +%Y/%m 2>/dev/null || echo "unknown")
                mkdir -p "$l4_path/$target_dir/$year_month"
                
                mv "$l3_path/summaries/$mem_id.json" "$l4_path/$target_dir/$year_month/"
                result="success"
            fi
            ;;
        "L4:L5")
            # Mark for external storage
            local l5_path
            l5_path=$(_amma_l5_path)
            echo "$memory" > "$l5_path/pointers/$mem_id.json"
            result="marked_for_external"
            ;;
        *)
            _amma_usop_error "INVALID_DEMOTION" "Cannot demote from $from_tier to $to_tier" "Check tier compatibility"
            return 1
            ;;
    esac
    
    if [[ "$result" == "success" ]] || [[ "$result" == "marked_for_external" ]]; then
        local end_time elapsed
        end_time=$(_amma_timestamp)
        elapsed=$(echo "($end_time - $start_time) * 1000" | bc 2>/dev/null || echo "0")
        elapsed="${elapsed%.*}"
        [[ -z "$elapsed" ]] && elapsed="0"
        
        local data
        data="{\"memory_id\":\"$mem_id\",\"from\":\"$from_tier\",\"to\":\"$to_tier\",\"status\":\"$result\"}"
        _amma_usop_success "$data" "ammma_tier_promote" "$elapsed"
    else
        _amma_usop_error "DEMOTION_FAILED" "Failed to demote memory" "Check file permissions and paths"
        return 1
    fi
}

# =============================================================================
# ATTENTION MECHANISM
# =============================================================================

_amma_attention_add() {
    local mem_id="$1"
    
    # Remove if already in window (will re-add at front)
    local new_window=()
    for id in "${_AMMA_ATTENTION_WINDOW[@]}"; do
        [[ "$id" == "$mem_id" ]] && continue
        new_window+=("$id")
    done
    
    # Add to front
    new_window=("$mem_id" "${new_window[@]}")
    
    # Trim to window size (default 20)
    local max_window="${AMMA_ATTENTION_WINDOW_SIZE:-20}"
    if [[ ${#new_window[@]} -gt $max_window ]]; then
        new_window=("${new_window[@]:0:$max_window}")
    fi
    
    _AMMA_ATTENTION_WINDOW=("${new_window[@]}")
}

# =============================================================================
# TIER STORAGE INTERNALS
# =============================================================================

_amma_l2_store() {
    local mem_id="$1"
    local memory="$2"
    
    local l2_path
    l2_path=$(_amma_l2_path)
    local mem_file="$l2_path/episodes/$mem_id.json"
    
    _amma_atomic_write "$mem_file" "$memory"
    
    # Update access tracking
    _AMMA_L2_ACCESS_COUNT["$mem_id"]=0
    _AMMA_L2_LAST_ACCESS["$mem_id"]=$(_amma_timestamp)
    _AMMA_LRU_TIMES["$mem_id"]=$(_amma_timestamp)
    
    # Calculate importance score
    local importance
    importance=$(echo "$memory" | grep -o '"importance":"[^"]*"' | head -1 | cut -d'"' -f4)
    _AMMA_L2_SCORES["$mem_id"]=$(_amma_importance_to_score "$importance")
}

_amma_l2_get() {
    local mem_id="$1"
    
    # First check L1
    if [[ -n "${_AMMA_L1_MEMORY[$mem_id]:-}" ]]; then
        printf '%s' "${_AMMA_L1_MEMORY[$mem_id]}"
        return 0
    fi
    
    # Then check L2 disk
    local l2_path
    l2_path=$(_amma_l2_path)
    
    for subdir in episodes checkpoints; do
        local mem_file="$l2_path/$subdir/$mem_id.json"
        if [[ -f "$mem_file" ]]; then
            _amma_atomic_read "$mem_file"
            
            # Update access count
            local count="${_AMMA_L2_ACCESS_COUNT[$mem_id]:-0}"
            _AMMA_L2_ACCESS_COUNT["$mem_id"]=$((count + 1))
            _AMMA_L2_LAST_ACCESS["$mem_id"]=$(_amma_timestamp)
            _AMMA_LRU_TIMES["$mem_id"]=$(_amma_timestamp)
            
            return 0
        fi
    done
    
    return 1
}

# =============================================================================
# STATISTICS AND STATUS
# =============================================================================

# Get AMMA statistics
ammma_stats() {
    if [[ "$_AMMA_INITIALIZED" != "true" ]]; then
        _amma_usop_error "NOT_INITIALIZED" "AMMA not initialized" "Call ammma_init first"
        return 1
    fi
    
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
    for dir in episodes facts patterns; do
        if [[ -d "$l4_path/$dir" ]]; then
            l4_count=$((l4_count + $(find "$l4_path/$dir" -name "*.json" 2>/dev/null | wc -l)))
        fi
    done
    
    local data
    data=$(printf '{\
        "version":"%s",\
        "session":"%s",\
        "tiers":{"l1":%d,"l2":%d,"l3":%d,"l4":%d},\
        "memory_count":{"episodes":%d,"facts":%d,"patterns":%d,"total":%d},\
        "retrievals":%d,\
        "attention_window":%d\
    }' \
        "$AMMA_VERSION" \
        "${_AMMA_SESSION_ID:-null}" \
        "$l1_count" "$l2_count" "$l3_count" "$l4_count" \
        "$_AMMA_EPISODE_COUNT" "$_AMMA_FACT_COUNT" "$_AMMA_PATTERN_COUNT" "$_AMMA_MEMORY_COUNT" \
        "$_AMMA_RETRIEVAL_COUNT" \
        "${#_AMMA_ATTENTION_WINDOW[@]}")
    
    _amma_usop_success "$data"
}

# Get AMMA status
ammma_status() {
    local data
    data=$(printf '{\
        "initialized":%s,\
        "session_id":"%s",\
        "agent_id":"%s",\
        "parent_session":"%s",\
        "namespace":"%s",\
        "version":"%s"\
    }' \
        "$([[ "$_AMMA_INITIALIZED" == "true" ]] && echo 'true' || echo 'false')" \
        "${_AMMA_SESSION_ID:-null}" \
        "${_AMMA_AGENT_ID:-null}" \
        "${_AMMA_PARENT_SESSION:-null}" \
        "${_AMMA_NAMESPACE:-null}" \
        "$AMMA_VERSION")
    
    _amma_usop_success "$data"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

AMMM_EXPORTS=(
    # Initialization
    ammma_init
    ammma_close
    ammma_status
    
    # Memory Creation
    ammma_episode_log
    ammma_fact_store
    ammma_pattern_learn
    ammma_checkpoint_set
    
    # Retrieval
    ammma_retrieve
    ammma_episode_get
    ammma_fact_query
    ammma_checkpoint_get
    ammma_context_build
    
    # Tier Management
    ammma_tier_promote
    ammma_tier_demote
    
    # Statistics
    ammma_stats
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${AMMM_EXPORTS[@]}" 2>/dev/null || true
fi


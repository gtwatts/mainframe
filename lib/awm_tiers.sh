#!/usr/bin/env bash
# AWM Tiered Memory Manager
# Hot/Warm/Cold memory tiers with automatic promotion and eviction
# Version: 2.0.0

# Prevent double-loading
[[ -n "${_AWM_TIERS_LOADED:-}" ]] && return 0

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

# Load dependencies
# shellcheck source=./awm_storage.sh
if declare -F lazy_load_library >/dev/null 2>&1; then
    lazy_load_library awm_storage || return 1
else
    source "${BASH_SOURCE%/*}/awm_storage.sh" 2>/dev/null ||
        source "$(dirname "$0")/awm_storage.sh" ||
        return 1
fi
# shellcheck source=./awm_stream.sh
if declare -F lazy_load_library >/dev/null 2>&1; then
    lazy_load_library awm_stream || return 1
else
    source "${BASH_SOURCE%/*}/awm_stream.sh" 2>/dev/null ||
        source "$(dirname "$0")/awm_stream.sh" ||
        return 1
fi

# =============================================================================
# TIER CONFIGURATION
# =============================================================================

# Hot tier: In-memory associative array (fastest, limited by context)
declare -gA _AWM_HOT_TIER
declare -gA _AWM_HOT_META  # Metadata: access_count, last_access, importance

# Warm tier: File/Redis (fast, larger capacity)
AWM_WARM_DIR="${MAINFRAME_AWM_DIR:-$HOME/.mainframe/awm}/warm"
AWM_WARM_MAX_SIZE="${AWM_WARM_MAX_SIZE:-10485760}"  # 10MB default
AWM_WARM_TTL="${AWM_WARM_TTL:-3600}"  # 1 hour default

# Cold tier: Persistent storage (largest, searchable)
AWM_COLD_DIR="${MAINFRAME_AWM_DIR:-$HOME/.mainframe/awm}/cold"
AWM_COLD_TTL_DAYS="${AWM_COLD_TTL_DAYS:-30}"

# Importance levels
readonly AWM_IMPORTANCE_CRITICAL="critical"
readonly AWM_IMPORTANCE_HIGH="high"
readonly AWM_IMPORTANCE_NORMAL="normal"
readonly AWM_IMPORTANCE_LOW="low"

# Importance weights for eviction scoring
declare -gA AWM_IMPORTANCE_WEIGHTS=(
    ["critical"]=1000
    ["high"]=100
    ["normal"]=10
    ["low"]=1
)

# =============================================================================
# TIER INITIALIZATION
# =============================================================================

# Initialize tier system
# Usage: awm_tier_init
awm_tier_init() {
    mkdir -p "$AWM_WARM_DIR" "$AWM_COLD_DIR"

    # Initialize storage backend
    awm_storage_init

    # Clear hot tier
    _AWM_HOT_TIER=()
    _AWM_HOT_META=()
}

# =============================================================================
# HOT TIER OPERATIONS (In-Memory)
# =============================================================================

# Set value in hot tier
# Usage: awm_hot_set "key" "value" [importance]
awm_hot_set() {
    local key="$1"
    local value="$2"
    local importance="${3:-$AWM_IMPORTANCE_NORMAL}"

    _AWM_HOT_TIER["$key"]="$value"
    _AWM_HOT_META["$key"]=$(jq -n \
        --arg imp "$importance" \
        --argjson access 1 \
        --arg last "$(date +%s)" \
        --argjson tokens "$(awm_estimate_tokens "$value")" \
        '{importance: $imp, access_count: $access, last_access: $last, tokens: $tokens}')
}

# Get value from hot tier
# Usage: awm_hot_get "key"
awm_hot_get() {
    local key="$1"

    [[ -z "${_AWM_HOT_TIER[$key]+x}" ]] && return 1

    # Update access metadata
    local meta="${_AWM_HOT_META[$key]}"
    if [[ -n "$meta" ]]; then
        local count
        count=$(echo "$meta" | jq -r '.access_count')
        _AWM_HOT_META["$key"]=$(echo "$meta" | jq \
            --argjson count "$((count + 1))" \
            --arg last "$(date +%s)" \
            '.access_count = $count | .last_access = $last')
    fi

    echo "${_AWM_HOT_TIER[$key]}"
}

# Delete from hot tier
# Usage: awm_hot_delete "key"
awm_hot_delete() {
    local key="$1"
    unset "_AWM_HOT_TIER[$key]"
    unset "_AWM_HOT_META[$key]"
}

# Check if key exists in hot tier
# Usage: awm_hot_exists "key"
awm_hot_exists() {
    local key="$1"
    [[ -n "${_AWM_HOT_TIER[$key]+x}" ]]
}

# Get hot tier size in tokens
# Usage: awm_hot_size
awm_hot_size() {
    local total=0

    for key in "${!_AWM_HOT_META[@]}"; do
        local tokens
        tokens=$(echo "${_AWM_HOT_META[$key]}" | jq -r '.tokens // 0')
        ((total += tokens))
    done

    echo "$total"
}

# List hot tier keys
# Usage: awm_hot_keys
awm_hot_keys() {
    printf '%s\n' "${!_AWM_HOT_TIER[@]}"
}

# =============================================================================
# WARM TIER OPERATIONS (File/Redis with TTL)
# =============================================================================

# Set value in warm tier
# Usage: awm_warm_set "key" "value" [ttl_seconds] [importance]
awm_warm_set() {
    local key="$1"
    local value="$2"
    local ttl="${3:-$AWM_WARM_TTL}"
    local importance="${4:-$AWM_IMPORTANCE_NORMAL}"

    local key_hash
    key_hash=$(echo -n "$key" | _mainframe_sha256 | cut -c1-16)

    # Store with metadata
    local data
    data=$(jq -n \
        --arg key "$key" \
        --arg value "$value" \
        --arg imp "$importance" \
        --argjson access 0 \
        --arg created "$(date +%s)" \
        --argjson ttl "$ttl" \
        --argjson tokens "$(awm_estimate_tokens "$value")" \
        '{key: $key, value: $value, importance: $imp, access_count: $access, created: $created, ttl: $ttl, tokens: $tokens}')

    # Use storage backend
    awm_store_set "warm:$key_hash" "$data" "$ttl"
}

# Get value from warm tier
# Usage: awm_warm_get "key"
awm_warm_get() {
    local key="$1"

    local key_hash
    key_hash=$(echo -n "$key" | _mainframe_sha256 | cut -c1-16)

    local data
    data=$(awm_store_get "warm:$key_hash")

    [[ -z "$data" ]] && return 1

    # Update access count
    local count
    count=$(echo "$data" | jq -r '.access_count')
    local updated
    updated=$(echo "$data" | jq --argjson count "$((count + 1))" '.access_count = $count')
    awm_store_set "warm:$key_hash" "$updated"

    echo "$data" | jq -r '.value'
}

# Delete from warm tier
# Usage: awm_warm_delete "key"
awm_warm_delete() {
    local key="$1"

    local key_hash
    key_hash=$(echo -n "$key" | _mainframe_sha256 | cut -c1-16)

    awm_store_delete "warm:$key_hash"
}

# Check warm tier existence
# Usage: awm_warm_exists "key"
awm_warm_exists() {
    local key="$1"

    local key_hash
    key_hash=$(echo -n "$key" | _mainframe_sha256 | cut -c1-16)

    awm_store_exists "warm:$key_hash"
}

# Get warm tier size in bytes
# Usage: awm_warm_size
awm_warm_size() {
    if [[ ! -d "$AWM_WARM_DIR" ]]; then
        printf '0\n'
        return 0
    fi

    if du -sk "$AWM_WARM_DIR" >/dev/null 2>&1; then
        local kb
        kb=$(du -sk "$AWM_WARM_DIR" 2>/dev/null | awk '{print $1}')
        printf '%d\n' "$(( ${kb:-0} * 1024 ))"
    else
        printf '0\n'
    fi
}

# =============================================================================
# COLD TIER OPERATIONS (Persistent Archive with Search)
# =============================================================================

# Set value in cold tier (indexed for search)
# Usage: awm_cold_set "key" "value" [metadata_json]
awm_cold_set() {
    local key="$1"
    local value="$2"
    local metadata="${3:-{}}"

    local key_hash
    key_hash=$(echo -n "$key" | _mainframe_sha256 | cut -c1-16)

    # Validate metadata is valid JSON, default to empty object
    if ! echo "$metadata" | jq . >/dev/null 2>&1; then
        metadata='{}'
    fi

    # Store value
    local data
    data=$(jq -n \
        --arg key "$key" \
        --arg value "$value" \
        --argjson meta "$metadata" \
        --arg created "$(date +%s)" \
        --argjson tokens "$(awm_estimate_tokens "$value")" \
        '{key: $key, value: $value, metadata: $meta, created: $created, tokens: $tokens}')

    # Store in cold tier
    awm_store_set "cold:$key_hash" "$data"

    # Index for search
    awm_store_index "$key" "$value" "$metadata"
}

# Get value from cold tier
# Usage: awm_cold_get "key"
awm_cold_get() {
    local key="$1"

    local key_hash
    key_hash=$(echo -n "$key" | _mainframe_sha256 | cut -c1-16)

    local data
    data=$(awm_store_get "cold:$key_hash")

    [[ -z "$data" ]] && return 1

    echo "$data" | jq -r '.value'
}

# Delete from cold tier
# Usage: awm_cold_delete "key"
awm_cold_delete() {
    local key="$1"

    local key_hash
    key_hash=$(echo -n "$key" | _mainframe_sha256 | cut -c1-16)

    awm_store_delete "cold:$key_hash"
}

# Search cold tier
# Usage: awm_cold_search "query" [limit]
awm_cold_search() {
    local query="$1"
    local limit="${2:-10}"

    awm_store_search "$query" "$limit"
}

# =============================================================================
# UNIFIED TIER OPERATIONS
# =============================================================================

# Write to appropriate tier based on size and importance
# Usage: awm_tier_write "key" "value" [importance]
awm_tier_write() {
    local key="$1"
    local value="$2"
    local importance="${3:-$AWM_IMPORTANCE_NORMAL}"

    local tokens
    tokens=$(awm_estimate_tokens "$value")

    local max_hot
    max_hot=$(awm_budget_max)
    local hot_threshold=$((max_hot / 10))  # 10% of budget per item max

    if [[ "$importance" == "$AWM_IMPORTANCE_CRITICAL" ]] || [[ $tokens -lt $hot_threshold ]]; then
        # Small or critical -> hot tier
        awm_hot_set "$key" "$value" "$importance"
    elif [[ $tokens -lt 10000 ]]; then
        # Medium -> warm tier
        awm_warm_set "$key" "$value" "$AWM_WARM_TTL" "$importance"
    else
        # Large -> cold tier (with pointer in hot)
        local ptr
        ptr=$(awm_pointer_create "$value" "auto" "{\"importance\":\"$importance\"}")
        awm_hot_set "$key" "$ptr" "$importance"
        awm_cold_set "$key" "$value" "{\"importance\":\"$importance\"}"
    fi
}

# Read with tier traversal (hot -> warm -> cold)
# Usage: awm_tier_read "key" [default] [promote]
# promote: if true, promotes found value to hot tier
awm_tier_read() {
    local key="$1"
    local default="${2:-}"
    local promote="${3:-true}"

    # Try hot tier first
    if awm_hot_exists "$key"; then
        local value
        value=$(awm_hot_get "$key")

        # Check if it's a pointer
        if [[ "$value" == ptr://awm/* ]]; then
            awm_pointer_resolve "$value"
        else
            echo "$value"
        fi
        return 0
    fi

    # Try warm tier
    if awm_warm_exists "$key"; then
        local value
        value=$(awm_warm_get "$key")

        # Promote to hot if requested and fits
        if [[ "$promote" == "true" ]]; then
            local tokens
            tokens=$(awm_estimate_tokens "$value")
            if awm_budget_fits "$tokens"; then
                awm_hot_set "$key" "$value"
            fi
        fi

        echo "$value"
        return 0
    fi

    # Try cold tier
    local value
    value=$(awm_cold_get "$key")

    if [[ -n "$value" ]]; then
        # Promote to warm tier
        if [[ "$promote" == "true" ]]; then
            awm_warm_set "$key" "$value"
        fi

        echo "$value"
        return 0
    fi

    # Not found
    echo "$default"
}

# Delete from all tiers
# Usage: awm_tier_delete "key"
awm_tier_delete() {
    local key="$1"

    awm_hot_delete "$key"
    awm_warm_delete "$key"
    awm_cold_delete "$key"
}

# =============================================================================
# EVICTION POLICIES
# =============================================================================

# Evict from hot tier to warm
# Usage: awm_evict_hot [target_tokens]
# Returns: number of items evicted
awm_evict_hot() {
    local target="${1:-0}"

    # If no target, evict to 75% of budget
    if [[ $target -eq 0 ]]; then
        local max
        max=$(awm_budget_max)
        target=$((max * 3 / 4))
    fi

    local current
    current=$(awm_hot_size)

    [[ $current -le $target ]] && echo 0 && return 0

    # Build eviction candidates with scores
    local candidates='[]'

    for key in "${!_AWM_HOT_META[@]}"; do
        local meta="${_AWM_HOT_META[$key]}"
        local importance
        importance=$(echo "$meta" | jq -r '.importance')
        local access_count
        access_count=$(echo "$meta" | jq -r '.access_count')
        local last_access
        last_access=$(echo "$meta" | jq -r '.last_access')
        local tokens
        tokens=$(echo "$meta" | jq -r '.tokens')

        # Skip critical items
        [[ "$importance" == "$AWM_IMPORTANCE_CRITICAL" ]] && continue

        # Calculate eviction score (lower = evict first)
        local weight="${AWM_IMPORTANCE_WEIGHTS[$importance]:-10}"
        local age=$(($(date +%s) - last_access))
        local score=$((weight * access_count * 1000 / (age + 1)))

        candidates=$(echo "$candidates" | jq \
            --arg key "$key" \
            --argjson score "$score" \
            --argjson tokens "$tokens" \
            '. + [{key: $key, score: $score, tokens: $tokens}]')
    done

    # Sort by score (ascending) and evict until under target
    local evicted=0
    local freed=0

    echo "$candidates" | jq -c 'sort_by(.score) | .[]' | while read -r candidate; do
        [[ $((current - freed)) -le $target ]] && break

        local key
        key=$(echo "$candidate" | jq -r '.key')
        local tokens
        tokens=$(echo "$candidate" | jq -r '.tokens')

        # Move to warm tier
        local value="${_AWM_HOT_TIER[$key]}"
        local importance
        importance=$(echo "${_AWM_HOT_META[$key]}" | jq -r '.importance')

        awm_warm_set "$key" "$value" "$AWM_WARM_TTL" "$importance"
        awm_hot_delete "$key"

        ((freed += tokens))
        ((evicted++))
    done

    echo "$evicted"
}

# Evict from warm tier to cold
# Usage: awm_evict_warm [target_size_bytes]
awm_evict_warm() {
    local target="${1:-$AWM_WARM_MAX_SIZE}"

    local current
    current=$(awm_warm_size)

    [[ $current -le $target ]] && echo 0 && return 0

    # List warm tier files sorted by access time (oldest first)
    local evicted=0

    find "$AWM_WARM_DIR" -type f -printf '%T@ %p\n' 2>/dev/null | \
        sort -n | \
        while read -r mtime file; do
            [[ $(awm_warm_size) -le $target ]] && break
            [[ ! -f "$file" ]] && continue

            # Read and move to cold
            local data
            data=$(cat "$file")
            local key
            key=$(echo "$data" | jq -r '.key')
            local value
            value=$(echo "$data" | jq -r '.value')
            local meta
            meta=$(echo "$data" | jq '{importance: .importance}')

            awm_cold_set "$key" "$value" "$meta"
            rm -f "$file"

            ((evicted++))
        done

    echo "$evicted"
}

# Evict from cold tier by age
# Usage: awm_evict_cold [days]
awm_evict_cold() {
    local days="${1:-$AWM_COLD_TTL_DAYS}"

    local evicted=0

    find "$AWM_COLD_DIR" -type f -mtime "+$days" 2>/dev/null | while read -r file; do
        rm -f "$file"
        ((evicted++))
    done

    echo "$evicted"
}

# Run full eviction cycle
# Usage: awm_evict_all
awm_evict_all() {
    local hot_evicted warm_evicted cold_evicted

    hot_evicted=$(awm_evict_hot)
    warm_evicted=$(awm_evict_warm)
    cold_evicted=$(awm_evict_cold)

    jq -n \
        --argjson hot "$hot_evicted" \
        --argjson warm "$warm_evicted" \
        --argjson cold "$cold_evicted" \
        '{hot_evicted: $hot, warm_evicted: $warm, cold_evicted: $cold}'
}

# =============================================================================
# TIER STATISTICS
# =============================================================================

# Get tier statistics
# Usage: awm_tier_stats
awm_tier_stats() {
    local hot_count=${#_AWM_HOT_TIER[@]}
    local hot_tokens
    hot_tokens=$(awm_hot_size)

    local warm_size
    warm_size=$(awm_warm_size)
    local warm_count
    warm_count=$(find "$AWM_WARM_DIR" -type f 2>/dev/null | wc -l | tr -d '[:space:]')

    local cold_size
    if du -sk "$AWM_COLD_DIR" >/dev/null 2>&1; then
        cold_size=$(du -sk "$AWM_COLD_DIR" 2>/dev/null | awk '{print $1 * 1024}')
    else
        cold_size=0
    fi
    local cold_count
    cold_count=$(find "$AWM_COLD_DIR" -type f 2>/dev/null | wc -l | tr -d '[:space:]')

    local budget_max budget_remaining
    budget_max=$(awm_budget_max)
    budget_remaining=$(awm_budget_remaining)

    jq -n \
        --argjson hot_count "$hot_count" \
        --argjson hot_tokens "$hot_tokens" \
        --argjson warm_count "$warm_count" \
        --argjson warm_bytes "$warm_size" \
        --argjson cold_count "$cold_count" \
        --argjson cold_bytes "$cold_size" \
        --argjson budget_max "$budget_max" \
        --argjson budget_remaining "$budget_remaining" \
        '{
            hot: {count: $hot_count, tokens: $hot_tokens},
            warm: {count: $warm_count, bytes: $warm_bytes},
            cold: {count: $cold_count, bytes: $cold_bytes},
            budget: {max: $budget_max, remaining: $budget_remaining}
        }'
}

# =============================================================================
# TIER PROMOTION/DEMOTION
# =============================================================================

# Manually promote item to higher tier
# Usage: awm_tier_promote "key"
awm_tier_promote() {
    local key="$1"

    # Check cold -> warm
    if ! awm_warm_exists "$key"; then
        local value
        value=$(awm_cold_get "$key")
        if [[ -n "$value" ]]; then
            awm_warm_set "$key" "$value"
            return 0
        fi
    fi

    # Check warm -> hot
    if ! awm_hot_exists "$key"; then
        local value
        value=$(awm_warm_get "$key")
        if [[ -n "$value" ]]; then
            local tokens
            tokens=$(awm_estimate_tokens "$value")
            if awm_budget_fits "$tokens"; then
                awm_hot_set "$key" "$value"
                return 0
            fi
        fi
    fi

    return 1
}

# Manually demote item to lower tier
# Usage: awm_tier_demote "key"
awm_tier_demote() {
    local key="$1"

    # Check hot -> warm
    if awm_hot_exists "$key"; then
        local value
        value=$(awm_hot_get "$key")
        awm_warm_set "$key" "$value"
        awm_hot_delete "$key"
        return 0
    fi

    # Check warm -> cold
    if awm_warm_exists "$key"; then
        local value
        value=$(awm_warm_get "$key")
        awm_cold_set "$key" "$value"
        awm_warm_delete "$key"
        return 0
    fi

    return 1
}

# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

# Clear all tiers
# Usage: awm_tier_clear [--confirm]
awm_tier_clear() {
    [[ "$1" != "--confirm" ]] && echo "Use --confirm to clear all tiers" && return 1

    _AWM_HOT_TIER=()
    _AWM_HOT_META=()
    rm -rf "${AWM_WARM_DIR:?}"/*
    rm -rf "${AWM_COLD_DIR:?}"/*
}

# Dump hot tier for debugging
# Usage: awm_hot_dump
awm_hot_dump() {
    local result='{'
    local first=1

    for key in "${!_AWM_HOT_TIER[@]}"; do
        [[ $first -eq 0 ]] && result+=','
        first=0

        local value="${_AWM_HOT_TIER[$key]}"
        local meta="${_AWM_HOT_META[$key]}"

        result+=$(printf '"%s":{"value":%s,"meta":%s}' \
            "$key" \
            "$(echo "$value" | jq -Rs .)" \
            "$meta")
    done

    echo "${result}}"
}

# Prefetch keys into hot tier
# Usage: awm_tier_prefetch key1 key2 ...
awm_tier_prefetch() {
    local keys=("$@")
    local loaded=0

    for key in "${keys[@]}"; do
        if ! awm_hot_exists "$key"; then
            local value
            value=$(awm_tier_read "$key" "" "true")
            [[ -n "$value" ]] && ((loaded++))
        fi
    done

    echo "$loaded"
}

# =============================================================================
# TIER PROMOTION LATENCY TRACKING
# =============================================================================

# Track tier promotion latency (target: sub-100ms)
declare -gA _AWM_TIER_LATENCY=()

# @pre: none
# @post: latency recorded
# @returns: latency in milliseconds
#
# Measure tier promotion latency.
#
# Usage: awm_tier_latency "operation" start_time
_awm_measure_latency() {
    local operation="$1"
    local start_ms="$2"

    local end_ms
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        end_ms=$(printf '%.0f' "$(echo "${EPOCHREALTIME} * 1000" | bc 2>/dev/null)")
    else
        end_ms=$(($(date +%s) * 1000))
    fi

    local latency=$((end_ms - start_ms))
    _AWM_TIER_LATENCY["$operation"]="$latency"

    # Warn if exceeds target
    if [[ $latency -gt 100 ]]; then
        echo "[awm_tiers] WARN: $operation latency ${latency}ms exceeds 100ms target" >&2
    fi

    echo "$latency"
}

# @pre: none
# @post: none (read-only)
# @returns: latency statistics as JSON
#
# Get tier operation latency statistics.
#
# Usage: awm_tier_latency_stats
awm_tier_latency_stats() {
    local result='{'
    local first=1

    for op in "${!_AWM_TIER_LATENCY[@]}"; do
        [[ $first -eq 0 ]] && result+=','
        first=0
        result+="\"${op}\":${_AWM_TIER_LATENCY[$op]}"
    done

    echo "${result}}"
}

# =============================================================================
# CRASH-SAFE RECOVERY
# =============================================================================

# @pre: session_id exists
# @post: hot tier restored from warm/cold
# @returns: number of items recovered
#
# Recover hot tier state after crash/restart.
#
# Usage: awm_tier_recover session_id
awm_tier_recover() {
    local session_id="$1"

    [[ -z "$session_id" ]] && return 1

    local recovered=0

    # Recover from warm tier checkpoint
    local checkpoint_file="${AWM_WARM_DIR}/.checkpoint_${session_id}"
    if [[ -f "$checkpoint_file" ]]; then
        while IFS= read -r line; do
            local key value
            key=$(echo "$line" | jq -r '.key')
            value=$(echo "$line" | jq -r '.value')
            local importance
            importance=$(echo "$line" | jq -r '.importance // "normal"')

            awm_hot_set "$key" "$value" "$importance"
            ((recovered++))
        done < "$checkpoint_file"

        rm -f "$checkpoint_file"
    fi

    echo "$recovered"
}

# @pre: active session
# @post: hot tier checkpointed to warm
# @returns: 0 on success
#
# Checkpoint hot tier for crash recovery (zero data loss).
#
# Usage: awm_tier_checkpoint session_id
awm_tier_checkpoint() {
    local session_id="$1"

    [[ -z "$session_id" ]] && return 1

    mkdir -p "$AWM_WARM_DIR"

    local checkpoint_file="${AWM_WARM_DIR}/.checkpoint_${session_id}"
    local tmpfile="${checkpoint_file}.tmp.$$"

    # Write hot tier state to checkpoint
    for key in "${!_AWM_HOT_TIER[@]}"; do
        local value="${_AWM_HOT_TIER[$key]}"
        local meta="${_AWM_HOT_META[$key]}"
        local importance
        importance=$(echo "$meta" | jq -r '.importance // "normal"' 2>/dev/null || echo "normal")

        jq -nc \
            --arg key "$key" \
            --arg value "$value" \
            --arg imp "$importance" \
            '{key: $key, value: $value, importance: $imp}' >> "$tmpfile"
    done

    # Atomic rename
    mv -f "$tmpfile" "$checkpoint_file" 2>/dev/null

    return 0
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_AWM_TIERS_EXPORTS=(
    # Initialization
    awm_tier_init
    # Hot Tier Operations
    awm_hot_set
    awm_hot_get
    awm_hot_delete
    awm_hot_exists
    awm_hot_size
    awm_hot_keys
    awm_hot_dump
    # Warm Tier Operations
    awm_warm_set
    awm_warm_get
    awm_warm_delete
    awm_warm_exists
    awm_warm_size
    # Cold Tier Operations
    awm_cold_set
    awm_cold_get
    awm_cold_delete
    awm_cold_search
    # Unified Operations
    awm_tier_write
    awm_tier_read
    awm_tier_delete
    awm_tier_promote
    awm_tier_demote
    awm_tier_prefetch
    # Eviction
    awm_evict_hot
    awm_evict_warm
    awm_evict_cold
    awm_evict_all
    # Statistics
    awm_tier_stats
    awm_tier_latency_stats
    # Recovery
    awm_tier_checkpoint
    awm_tier_recover
    # Management
    awm_tier_clear
)

# Do not advertise a partially sourced tier manager as loaded. In particular,
# a missing stream/storage dependency must be repairable within the same shell.
readonly _AWM_TIERS_LOADED=1

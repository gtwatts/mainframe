#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/fast_cache.sh - High-Performance LRU Cache
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_FAST_CACHE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_FAST_CACHE_LOADED=1

# =============================================================================
# DEFAULTS
# =============================================================================

readonly _FAST_CACHE_DEFAULT_SIZE=1000
readonly _FAST_CACHE_DEFAULT_TTL=0

# =============================================================================
# CACHE STATE
# =============================================================================

declare -gA _FAST_CACHE_REGISTRY=()

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_fast_cache_epoch() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    elif printf -v ts '%(%s)T' -1 2>/dev/null; then
        printf '%s' "$ts"
    else
        date +%s
    fi
}

_fast_cache_var() {
    local name="$1"
    local suffix="$2"
    printf '_FAST_CACHE_%s_%s' "$name" "$suffix"
}

_fast_cache_init_storage() {
    local name="$1"
    local size="${2:-$_FAST_CACHE_DEFAULT_SIZE}"
    
    if [[ -z "${_FAST_CACHE_REGISTRY[$name]:-}" ]]; then
        _FAST_CACHE_REGISTRY[$name]=1
        
        local data_var=$(_fast_cache_var "$name" "data")
        local ttl_var=$(_fast_cache_var "$name" "ttl")
        local lru_var=$(_fast_cache_var "$name" "lru")
        local hits_var=$(_fast_cache_var "$name" "hits")
        local misses_var=$(_fast_cache_var "$name" "misses")
        local size_var=$(_fast_cache_var "$name" "size")
        local max_var=$(_fast_cache_var "$name" "max_size")
        
        # Use eval to create associative arrays with dynamic names
        eval "declare -gA $data_var=()"
        eval "declare -gA $ttl_var=()"
        eval "declare -gA $lru_var=()"
        eval "declare -gi $hits_var=0"
        eval "declare -gi $misses_var=0"
        eval "declare -gi $size_var=0"
        eval "declare -gi $max_var=$size"
    fi
}

# =============================================================================
# CORE CACHE API
# =============================================================================

fast_cache_init() {
    local size="$_FAST_CACHE_DEFAULT_SIZE"
    local name="default"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --size) size="$2"; shift 2 ;;
            --name) name="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if ! [[ "$size" =~ ^[0-9]+$ ]] || [[ "$size" -lt 1 ]]; then
        printf 'fast_cache_init: invalid size: %s\n' "$size" >&2
        return 1
    fi
    
    _fast_cache_init_storage "$name" "$size"
}

fast_cache_get() {
    local key=""
    local name="default"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key) key="$2"; shift 2 ;;
            --name) name="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    [[ -z "$key" ]] && return 1
    [[ -z "${_FAST_CACHE_REGISTRY[$name]:-}" ]] && return 1
    
    local data_var=$(_fast_cache_var "$name" "data")
    local ttl_var=$(_fast_cache_var "$name" "ttl")
    local lru_var=$(_fast_cache_var "$name" "lru")
    local hits_var=$(_fast_cache_var "$name" "hits")
    local misses_var=$(_fast_cache_var "$name" "misses")
    local size_var=$(_fast_cache_var "$name" "size")
    
    # Use eval to access arrays
    local data_val ttl_val
    eval "data_val=\"\${$data_var[\$key]:-}\""
    
    if [[ -n "$data_val" ]]; then
        eval "ttl_val=\"\${$ttl_var[\$key]:-0}\""
        
        if [[ "$ttl_val" -gt 0 ]]; then
            local now
            now=$(_fast_cache_epoch)
            if [[ "$now" -gt "$ttl_val" ]]; then
                # Expired - remove entry
                eval "unset $data_var[\"\$key\"]"
                eval "unset $ttl_var[\"\$key\"]"
                eval "unset $lru_var[\"\$key\"]"
                eval "((--$size_var))"
                eval "((++$misses_var))"
                return 1
            fi
        fi
        
        # Update LRU timestamp
        local now
        now=$(_fast_cache_epoch)
        eval "$lru_var[\"\$key\"]=\"\$now\""
        eval "((++$hits_var))"
        
        printf '%s' "$data_val"
        return 0
    fi
    
    eval "((++$misses_var))"
    return 1
}

fast_cache_set() {
    local key=""
    local value=""
    local ttl="$_FAST_CACHE_DEFAULT_TTL"
    local name="default"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key) key="$2"; shift 2 ;;
            --value) value="$2"; shift 2 ;;
            --ttl) ttl="$2"; shift 2 ;;
            --name) name="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    [[ -z "$key" ]] && return 1
    
    _fast_cache_init_storage "$name"
    
    local data_var=$(_fast_cache_var "$name" "data")
    local ttl_var=$(_fast_cache_var "$name" "ttl")
    local lru_var=$(_fast_cache_var "$name" "lru")
    local size_var=$(_fast_cache_var "$name" "size")
    local max_var=$(_fast_cache_var "$name" "max_size")
    
    # Check if key exists
    local existing=""
    eval "existing=\"\${$data_var[\$key]:-}\""
    
    # Check capacity
    local current_size max_size
    eval "current_size=\"\${$size_var}\""
    eval "max_size=\"\${$max_var}\""
    
    if [[ -z "$existing" && "$current_size" -ge "$max_size" ]]; then
        # Need to evict - find oldest entry
        local lru_key oldest_key="" oldest_time=9999999999
        eval "for lru_key in \"\${!$lru_var[@]}\"; do
            local ts=\"\${$lru_var[\$lru_key]}\"
            if [[ \"\$ts\" -lt \"\$oldest_time\" ]]; then
                oldest_time=\$ts
                oldest_key=\$lru_key
            fi
        done"
        
        if [[ -n "$oldest_key" ]]; then
            eval "unset $data_var[\"\$oldest_key\"]"
            eval "unset $ttl_var[\"\$oldest_key\"]"
            eval "unset $lru_var[\"\$oldest_key\"]"
            eval "((--$size_var))"
        fi
    fi
    
    # Set value
    eval "$data_var[\"\$key\"]=\"\$value\""
    
    if [[ "$ttl" -gt 0 ]]; then
        local expiry
        expiry=$(( $(_fast_cache_epoch) + ttl ))
        eval "$ttl_var[\"\$key\"]=\"\$expiry\""
    else
        eval "$ttl_var[\"\$key\"]=\"0\""
    fi
    
    local now
    now=$(_fast_cache_epoch)
    eval "$lru_var[\"\$key\"]=\"\$now\""
    
    if [[ -z "$existing" ]]; then
        eval "((++$size_var))"
    fi
}

fast_cache_has() {
    local key=""
    local name="default"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key) key="$2"; shift 2 ;;
            --name) name="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    [[ -z "$key" ]] && return 1
    fast_cache_get --key "$key" --name "$name" >/dev/null 2>&1
}

fast_cache_clear() {
    local name="default"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    [[ -z "${_FAST_CACHE_REGISTRY[$name]:-}" ]] && return 0
    
    local data_var=$(_fast_cache_var "$name" "data")
    local ttl_var=$(_fast_cache_var "$name" "ttl")
    local lru_var=$(_fast_cache_var "$name" "lru")
    local hits_var=$(_fast_cache_var "$name" "hits")
    local misses_var=$(_fast_cache_var "$name" "misses")
    local size_var=$(_fast_cache_var "$name" "size")
    
    eval "$data_var=()"
    eval "$ttl_var=()"
    eval "$lru_var=()"
    eval "$hits_var=0"
    eval "$misses_var=0"
    eval "$size_var=0"
}

fast_cache_stats() {
    local name="default"
    local json_output=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --json) json_output=true; shift ;;
            *) shift ;;
        esac
    done
    
    local hits=0 misses=0 size=0 max=1000
    
    if [[ -n "${_FAST_CACHE_REGISTRY[$name]:-}" ]]; then
        local hits_var=$(_fast_cache_var "$name" "hits")
        local misses_var=$(_fast_cache_var "$name" "misses")
        local size_var=$(_fast_cache_var "$name" "size")
        local max_var=$(_fast_cache_var "$name" "max_size")
        
        eval "hits=\"\${$hits_var}\""
        eval "misses=\"\${$misses_var}\""
        eval "size=\"\${$size_var}\""
        eval "max=\"\${$max_var}\""
    fi
    
    local total=$((hits + misses))
    local hit_rate=0
    if [[ $total -gt 0 ]]; then
        hit_rate=$((hits * 100 / total))
    fi
    
    if [[ "$json_output" == true ]]; then
        printf '{"name":"%s","hits":%d,"misses":%d,"hit_rate_pct":%d,"size":%d,"max_size":%d}' \
            "$name" "$hits" "$misses" "$hit_rate" "$size" "$max"
    else
        printf 'Cache: %s\n' "$name"
        printf '  Hits:      %d\n' "$hits"
        printf '  Misses:    %d\n' "$misses"
        printf '  Hit Rate:  %d%%\n' "$hit_rate"
        printf '  Size:      %d / %d\n' "$size" "$max"
    fi
}

# =============================================================================
# SPECIALIZED CACHES
# =============================================================================

json_escape_cached() {
    local str="$1"
    local cache_key="escape:$str"
    local result
    
    if [[ -z "${_FAST_CACHE_REGISTRY[json]:-}" ]]; then
        fast_cache_init --name json --size 500
    fi
    
    if fast_cache_get --key "$cache_key" --name json >/dev/null; then
        fast_cache_get --key "$cache_key" --name json
        return 0
    fi
    
    if declare -F json_escape_fast &>/dev/null; then
        result=$(json_escape_fast "$str")
    elif declare -F json_escape &>/dev/null; then
        result=$(json_escape "$str")
    else
        result="${str//\\/\\\\}"
        result="${result//\"/\\\"}"
    fi
    
    fast_cache_set --key "$cache_key" --value "$result" --name json
    printf '%s' "$result"
}

validate_cached() {
    local validator="$1"
    local value="$2"
    local cache_key="${validator}:${value}"
    
    if [[ -z "${_FAST_CACHE_REGISTRY[validate]:-}" ]]; then
        fast_cache_init --name validate --size 1000
    fi
    
    local cached
    if cached=$(fast_cache_get --key "$cache_key" --name validate 2>/dev/null); then
        return "$cached"
    fi
    
    local result=0
    case "$validator" in
        int|integer)
            [[ "$value" =~ ^-?[0-9]+$ ]] || result=1
            ;;
        float|number)
            [[ "$value" =~ ^-?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$ ]] || result=1
            ;;
        bool|boolean)
            [[ "${value,,}" =~ ^(true|false|1|0|yes|no|on|off)$ ]] || result=1
            ;;
        email)
            [[ "$value" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || result=1
            ;;
        url)
            [[ "$value" =~ ^https?://[A-Za-z0-9.-]+ ]] || result=1
            ;;
        uuid)
            [[ "$value" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || result=1
            ;;
        *)
            if declare -F "$validator" &>/dev/null; then
                "$validator" "$value"
                result=$?
            else
                result=1
            fi
            ;;
    esac
    
    fast_cache_set --key "$cache_key" --value "$result" --name validate
    return $result
}

token_count_cached() {
    local text="$1"
    local model="${2:-default}"
    local cache_key="${model}:${#text}:${text:0:50}"
    
    if [[ -z "${_FAST_CACHE_REGISTRY[tokens]:-}" ]]; then
        fast_cache_init --name tokens --size 200
    fi
    
    local cached
    if cached=$(fast_cache_get --key "$cache_key" --name tokens 2>/dev/null); then
        printf '%s' "$cached"
        return 0
    fi
    
    local count=0
    if declare -F llm_count_tokens &>/dev/null; then
        count=$(llm_count_tokens "$text" "$model")
    else
        count=$(( (${#text} + 2) / 4 ))
    fi
    
    fast_cache_set --key "$cache_key" --value "$count" --name tokens
    printf '%s' "$count"
}

# =============================================================================
# BENCHMARKING
# =============================================================================

fast_cache_benchmark() {
    local iterations="${1:-10000}"
    
    printf 'Fast Cache Benchmark (%d iterations)\n' "$iterations"
    printf '\n'
    
    fast_cache_init --name benchmark --size 1000
    fast_cache_clear --name benchmark
    
    local start end set_ms
    start=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")
    for ((i=0; i<iterations; i++)); do
        fast_cache_set --key "key_$i" --value "value_$i" --name benchmark
    done
    end=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")
    set_ms=$(( (end - start) / 1000000 ))
    
    printf 'Set %d entries:    %d ms (%d ops/sec)\n' \
        "$iterations" "$set_ms" "$(( iterations * 1000 / (set_ms + 1) ))"
    
    local get_ms
    start=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")
    for ((i=0; i<iterations; i++)); do
        fast_cache_get --key "key_$i" --name benchmark >/dev/null
    done
    end=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")
    get_ms=$(( (end - start) / 1000000 ))
    
    printf 'Get %d entries:    %d ms (%d ops/sec)\n' \
        "$iterations" "$get_ms" "$(( iterations * 1000 / (get_ms + 1) ))"
    
    printf '\n'
    fast_cache_stats --name benchmark
}

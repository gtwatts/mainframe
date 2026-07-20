#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/fast_cache.sh - Lightweight Named In-Memory Cache
# =============================================================================
# Description: Small compatibility cache used by context helpers and tests.
#              Supports multiple named caches, fixed entry limits, and simple
#              hit/miss statistics without external dependencies.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================

[[ -n "${_MAINFRAME_FAST_CACHE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_FAST_CACHE_LOADED=1

declare -gA _FAST_CACHE_VALUES=()
declare -gA _FAST_CACHE_LIMITS=()
declare -gA _FAST_CACHE_COUNTS=()
declare -gA _FAST_CACHE_HITS=()
declare -gA _FAST_CACHE_MISSES=()
declare -gA _FAST_CACHE_ORDER=()
declare -g _FAST_CACHE_CURRENT_NAME="default"

_fast_cache_full_key() {
    printf '%s::%s' "$1" "$2"
}

_fast_cache_remove_from_order() {
    local name="$1"
    local key="$2"
    local order="${_FAST_CACHE_ORDER[$name]:-}"
    local updated=""
    local entry

    while IFS= read -r entry; do
        [[ -z "$entry" || "$entry" == "$key" ]] && continue
        if [[ -n "$updated" ]]; then
            updated+=$'\n'
        fi
        updated+="$entry"
    done <<< "$order"

    _FAST_CACHE_ORDER["$name"]="$updated"
}

_fast_cache_append_order() {
    local name="$1"
    local key="$2"

    _fast_cache_remove_from_order "$name" "$key"

    if [[ -n "${_FAST_CACHE_ORDER[$name]:-}" ]]; then
        _FAST_CACHE_ORDER["$name"]+=$'\n'
    fi
    _FAST_CACHE_ORDER["$name"]+="$key"
}

_fast_cache_delete_key() {
    local name="$1"
    local key="$2"
    local full_key

    full_key=$(_fast_cache_full_key "$name" "$key")
    if [[ -n "${_FAST_CACHE_VALUES[$full_key]+x}" ]]; then
        unset "_FAST_CACHE_VALUES[$full_key]"
        _FAST_CACHE_COUNTS["$name"]=$(( ${_FAST_CACHE_COUNTS[$name]:-0} - 1 ))
        [[ ${_FAST_CACHE_COUNTS[$name]:-0} -lt 0 ]] && _FAST_CACHE_COUNTS["$name"]=0
    fi

    _fast_cache_remove_from_order "$name" "$key"
}

_fast_cache_trim() {
    local name="$1"
    local limit="${_FAST_CACHE_LIMITS[$name]:-100}"
    local oldest

    while (( ${_FAST_CACHE_COUNTS[$name]:-0} > limit )); do
        oldest="${_FAST_CACHE_ORDER[$name]%%$'\n'*}"
        [[ "$oldest" == "${_FAST_CACHE_ORDER[$name]}" ]] && [[ "$oldest" == *$'\n'* ]] && oldest=""
        [[ -z "$oldest" ]] && oldest="${_FAST_CACHE_ORDER[$name]}"
        [[ -z "$oldest" ]] && break
        _fast_cache_delete_key "$name" "$oldest"
    done
}

_fast_cache_resolve_name() {
    local explicit_name="$1"
    if [[ -n "$explicit_name" ]]; then
        printf '%s' "$explicit_name"
    else
        printf '%s' "${_FAST_CACHE_CURRENT_NAME:-default}"
    fi
}

fast_cache_init() {
    local name="default"
    local size=100

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                name="$2"
                shift 2
                ;;
            --size)
                size="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    [[ -z "$name" ]] && name="default"
    [[ ! "$size" =~ ^[0-9]+$ ]] && size=100

    _FAST_CACHE_CURRENT_NAME="$name"
    _FAST_CACHE_LIMITS["$name"]="$size"
    _FAST_CACHE_COUNTS["$name"]="${_FAST_CACHE_COUNTS[$name]:-0}"
    _FAST_CACHE_HITS["$name"]="${_FAST_CACHE_HITS[$name]:-0}"
    _FAST_CACHE_MISSES["$name"]="${_FAST_CACHE_MISSES[$name]:-0}"
    _FAST_CACHE_ORDER["$name"]="${_FAST_CACHE_ORDER[$name]:-}"

    printf 'Initialized cache %s (size=%s)\n' "$name" "$size"
}

fast_cache_set() {
    local key=""
    local value=""
    local name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key)
                key="$2"
                shift 2
                ;;
            --value)
                value="$2"
                shift 2
                ;;
            --name)
                name="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    [[ -z "$key" ]] && return 1
    name=$(_fast_cache_resolve_name "$name")
    [[ -z "${_FAST_CACHE_LIMITS[$name]:-}" ]] && fast_cache_init --name "$name" >/dev/null

    local full_key
    full_key=$(_fast_cache_full_key "$name" "$key")
    if [[ -z "${_FAST_CACHE_VALUES[$full_key]+x}" ]]; then
        _FAST_CACHE_COUNTS["$name"]=$(( ${_FAST_CACHE_COUNTS[$name]:-0} + 1 ))
    fi

    _FAST_CACHE_VALUES["$full_key"]="$value"
    _fast_cache_append_order "$name" "$key"
    _fast_cache_trim "$name"
}

fast_cache_has() {
    local key=""
    local name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key)
                key="$2"
                shift 2
                ;;
            --name)
                name="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    [[ -z "$key" ]] && return 1
    name=$(_fast_cache_resolve_name "$name")

    local full_key
    full_key=$(_fast_cache_full_key "$name" "$key")
    if [[ -n "${_FAST_CACHE_VALUES[$full_key]+x}" ]]; then
        _FAST_CACHE_HITS["$name"]=$(( ${_FAST_CACHE_HITS[$name]:-0} + 1 ))
        return 0
    fi

    _FAST_CACHE_MISSES["$name"]=$(( ${_FAST_CACHE_MISSES[$name]:-0} + 1 ))
    return 1
}

fast_cache_clear() {
    local name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                name="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    name=$(_fast_cache_resolve_name "$name")

    local full_key
    for full_key in "${!_FAST_CACHE_VALUES[@]}"; do
        [[ "$full_key" == "$name::"* ]] || continue
        unset "_FAST_CACHE_VALUES[$full_key]"
    done

    _FAST_CACHE_COUNTS["$name"]=0
    _FAST_CACHE_ORDER["$name"]=""
}

fast_cache_stats() {
    local name=""
    local json=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                name="$2"
                shift 2
                ;;
            --json)
                json=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    name=$(_fast_cache_resolve_name "$name")

    local size="${_FAST_CACHE_COUNTS[$name]:-0}"
    local limit="${_FAST_CACHE_LIMITS[$name]:-0}"
    local hits="${_FAST_CACHE_HITS[$name]:-0}"
    local misses="${_FAST_CACHE_MISSES[$name]:-0}"

    if [[ "$json" == "true" ]]; then
        printf '{"name":"%s","size":%d,"max_size":%d,"hits":%d,"misses":%d}' \
            "$name" "$size" "$limit" "$hits" "$misses"
    else
        printf 'Cache: %s\n' "$name"
        printf 'Size: %d/%d\n' "$size" "$limit"
        printf 'Hits: %d\n' "$hits"
        printf 'Misses: %d\n' "$misses"
    fi
}


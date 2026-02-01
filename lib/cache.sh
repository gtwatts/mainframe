#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/cache.sh - Caching and Memoization System
# =============================================================================
# Description: Function memoization with TTL, content-addressable store,
#              session cache, dependency-aware invalidation, LRU eviction,
#              and concurrency-safe operations for AI agent workflows.
# Version: 2.0.0
# Requires: Bash 4.0+, sha256sum/shasum/openssl
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_CACHE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_CACHE_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Cache root directory
MAINFRAME_CACHE_ROOT="${MAINFRAME_CACHE_ROOT:-$HOME/.mainframe/cache}"

# Maximum cache size in MB (default 512MB)
MAINFRAME_CACHE_MAX_SIZE_MB="${MAINFRAME_CACHE_MAX_SIZE_MB:-512}"

# Default TTL in seconds (0 = no expiration)
MAINFRAME_CACHE_DEFAULT_TTL="${MAINFRAME_CACHE_DEFAULT_TTL:-0}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Session cache (in-memory associative array)
declare -gA _MAINFRAME_SESSION_CACHE=()

# Cache statistics
declare -gi _MAINFRAME_CACHE_HITS=0
declare -gi _MAINFRAME_CACHE_MISSES=0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Delegate to centralized logging (with fallback for standalone testing)
_cache_log() {
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "cache" "$@"
    else
        local level="$1"; shift
        [[ "${MAINFRAME_QUIET:-}" != "1" ]] && printf '[cache] %s: %s\n' "$level" "$*" >&2
        :  # Ensure return 0 even when quiet mode suppresses output
    fi
}

# Get epoch seconds (optimized: EPOCHSECONDS > printf builtin > date fallback)
_cache_epoch() {
    local ts
    # Fastest: Bash 5.0+ EPOCHSECONDS variable
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    # Fast: Bash 4.2+ printf builtin (~100x faster than date)
    elif printf -v ts '%(%s)T' -1 2>/dev/null && [[ -n "$ts" ]]; then
        printf '%s' "$ts"
    # Fallback: external date command
    else
        date +%s
    fi
}

# Compute SHA-256 hash of input string
_cache_sha256() {
    local input="$1"
    if type -p sha256sum &>/dev/null; then
        printf '%s' "$input" | sha256sum | cut -d' ' -f1
    elif type -p shasum &>/dev/null; then
        printf '%s' "$input" | shasum -a 256 | cut -d' ' -f1
    elif type -p openssl &>/dev/null; then
        printf '%s' "$input" | openssl dgst -sha256 | awk '{print $NF}'
    else
        _cache_log error "No SHA-256 tool available"
        return 1
    fi
}

# Compute SHA-256 hash of a file
_cache_sha256_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        printf ''
        return 1
    fi
    if type -p sha256sum &>/dev/null; then
        sha256sum "$file" | cut -d' ' -f1
    elif type -p shasum &>/dev/null; then
        shasum -a 256 "$file" | cut -d' ' -f1
    elif type -p openssl &>/dev/null; then
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    else
        printf ''
        return 1
    fi
}

# Ensure cache directory structure exists
_cache_ensure_dirs() {
    mkdir -p "${MAINFRAME_CACHE_ROOT}/memo" 2>/dev/null
    mkdir -p "${MAINFRAME_CACHE_ROOT}/cas" 2>/dev/null
    mkdir -p "${MAINFRAME_CACHE_ROOT}/locks" 2>/dev/null
}

# Atomic write: write to temp, then rename
_cache_atomic_write() {
    local target="$1"
    local content="$2"

    # Use MAINFRAME atomic_write if available
    if declare -F atomic_write &>/dev/null; then
        atomic_write "$target" "$content"
        return $?
    fi

    # Fallback: manual temp-then-rename
    local dir
    dir="${target%/*}"
    [[ "$dir" == "$target" ]] && dir="."
    local tmpfile="${dir}/.cache_tmp_${$}_${RANDOM}"

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

# Generate cache key from function name and args
_cache_make_key() {
    local func_name="$1"
    shift
    local args_serialized="${func_name}"
    local arg
    for arg in "$@"; do
        args_serialized="${args_serialized}|${arg}"
    done
    _cache_sha256 "$args_serialized"
}

# Build JSON metadata (uses json_object if available, otherwise manual)
_cache_build_meta() {
    local timestamp="$1"
    local ttl="$2"
    local hit_count="$3"
    local func_name="$4"
    shift 4
    local deps=("$@")

    if declare -F json_object &>/dev/null; then
        local deps_json="[]"
        if [[ ${#deps[@]} -gt 0 ]]; then
            deps_json="["
            local first=true
            local dep
            for dep in "${deps[@]}"; do
                $first || deps_json+=","
                first=false
                deps_json+="\"${dep}\""
            done
            deps_json+="]"
        fi
        printf '{"timestamp":%s,"ttl":%s,"hit_count":%s,"function":"%s","deps":%s}' \
            "$timestamp" "$ttl" "$hit_count" "$func_name" "$deps_json"
    else
        # Manual JSON construction
        local deps_json="[]"
        if [[ ${#deps[@]} -gt 0 ]]; then
            deps_json="["
            local first=true
            local dep
            for dep in "${deps[@]}"; do
                $first || deps_json+=","
                first=false
                deps_json+="\"${dep}\""
            done
            deps_json+="]"
        fi
        printf '{"timestamp":%s,"ttl":%s,"hit_count":%s,"function":"%s","deps":%s}' \
            "$timestamp" "$ttl" "$hit_count" "$func_name" "$deps_json"
    fi
}

# Parse a simple JSON value by key (lightweight, no jq dependency)
_cache_json_get() {
    local json="$1"
    local key="$2"

    # Handle numeric values
    local pattern="\"${key}\":([0-9]+)"
    if [[ "$json" =~ $pattern ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    # Handle string values
    pattern="\"${key}\":\"([^\"]*)\""
    if [[ "$json" =~ $pattern ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    # Handle array values
    pattern="\"${key}\":\[([^\]]*)\]"
    if [[ "$json" =~ $pattern ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

# Acquire lock for a given key (flock-based if available)
_cache_lock() {
    local key="$1"
    local lock_file="${MAINFRAME_CACHE_ROOT}/locks/${key}.lock"

    mkdir -p "${MAINFRAME_CACHE_ROOT}/locks" 2>/dev/null

    if command -v flock &>/dev/null; then
        exec 9>"$lock_file"
        flock -x -w 10 9 || return 1
    else
        # Fallback: mkdir-based lock (atomic on POSIX)
        local attempts=0
        local max_attempts=100
        while ! mkdir "${lock_file}.d" 2>/dev/null; do
            attempts=$((attempts + 1))
            if [[ $attempts -ge $max_attempts ]]; then
                return 1
            fi
            sleep 0.1
        done
    fi
    return 0
}

# Release lock for a given key
_cache_unlock() {
    local key="$1"
    local lock_file="${MAINFRAME_CACHE_ROOT}/locks/${key}.lock"

    if command -v flock &>/dev/null; then
        exec 9>&- 2>/dev/null
    else
        rmdir "${lock_file}.d" 2>/dev/null
    fi
    rm -f "$lock_file" 2>/dev/null
}

# Check if a cache entry has expired based on TTL
_cache_is_expired() {
    local meta_file="$1"
    local now

    if [[ ! -f "$meta_file" ]]; then
        return 0  # No metadata = expired
    fi

    local meta
    meta=$(< "$meta_file")

    local ttl
    ttl=$(_cache_json_get "$meta" "ttl")
    [[ -z "$ttl" ]] && ttl=0

    # TTL of 0 means no expiration
    [[ "$ttl" -eq 0 ]] && return 1

    local timestamp
    timestamp=$(_cache_json_get "$meta" "timestamp")
    [[ -z "$timestamp" ]] && return 0

    now=$(_cache_epoch)
    local age=$((now - timestamp))

    [[ $age -ge $ttl ]]
}

# Update access time on meta file for LRU tracking
_cache_touch_meta() {
    local meta_file="$1"

    if [[ ! -f "$meta_file" ]]; then
        return 1
    fi

    local meta
    meta=$(< "$meta_file")

    local hit_count
    hit_count=$(_cache_json_get "$meta" "hit_count")
    [[ -z "$hit_count" ]] && hit_count=0
    hit_count=$((hit_count + 1))

    # Update hit_count in metadata using regex match-and-replace
    local new_meta="$meta"
    if [[ "$meta" =~ \"hit_count\":[0-9]+ ]]; then
        new_meta="${meta/${BASH_REMATCH[0]}/\"hit_count\":${hit_count}}"
    fi

    _cache_atomic_write "$meta_file" "$new_meta"

    # Touch the file for LRU (atime-based)
    touch "$meta_file" 2>/dev/null
}

# Get total cache size in bytes
_cache_total_size() {
    if [[ ! -d "$MAINFRAME_CACHE_ROOT" ]]; then
        printf '0'
        return
    fi

    # GNU du supports -sb (bytes), macOS du does not
    local size
    size=$(du -sb "$MAINFRAME_CACHE_ROOT" 2>/dev/null | cut -f1)
    if [[ -n "$size" ]]; then
        printf '%s' "$size"
    else
        # macOS fallback: du -sk gives kilobytes
        size=$(du -sk "$MAINFRAME_CACHE_ROOT" 2>/dev/null | cut -f1)
        if [[ -n "$size" ]]; then
            printf '%s' "$((size * 1024))"
        else
            printf '0'
        fi
    fi
}

# =============================================================================
# FUNCTION MEMOIZATION
# =============================================================================

# @pre: FUNCTION must be a declared function or available command
# @post: result cached on disk with TTL and dependency tracking
# @idempotent: yes - returns cached value if valid, recomputes if expired
# @atomic: yes - uses flock + temp-then-rename for writes
# @returns: 0 on success (cache hit or successful compute), 1 on failure
#
# Memoize a function call with optional TTL and file-dependency invalidation.
# On cache hit: outputs cached value, returns 0.
# On cache miss: runs function, caches output, returns function's exit code.
#
# Usage: memoize [--ttl SECONDS] [--invalidate-on FILE...] FUNCTION [ARGS...]
# Example: memoize --ttl 300 expensive_lookup "key1"
# Example: memoize --invalidate-on config.json my_func arg1 arg2
memoize() {
    _cache_ensure_dirs

    local ttl="${MAINFRAME_CACHE_DEFAULT_TTL}"
    local -a invalidate_files=()
    local func_name=""
    local -a func_args=()

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ttl)
                ttl="$2"
                shift 2
                ;;
            --invalidate-on)
                shift
                # Consume file arguments until we hit another option or a known function
                while [[ $# -gt 0 ]]; do
                    # Stop at next option flag
                    [[ "$1" == --* ]] && break
                    # Stop if this looks like a function/command (not a file path)
                    if [[ "$1" != */* ]] && [[ "$1" != *.* ]] && { declare -F "$1" &>/dev/null || type -p "$1" &>/dev/null; }; then
                        break
                    fi
                    invalidate_files+=("$1")
                    shift
                done
                ;;
            --)
                shift
                func_name="$1"
                shift
                func_args=("$@")
                break
                ;;
            *)
                func_name="$1"
                shift
                func_args=("$@")
                break
                ;;
        esac
    done

    if [[ -z "$func_name" ]]; then
        _cache_log error "memoize: function name required"
        return 1
    fi

    # Verify function exists
    if ! declare -F "$func_name" &>/dev/null && ! type -p "$func_name" &>/dev/null; then
        _cache_log error "memoize: function '$func_name' not found"
        return 1
    fi

    # Generate cache key
    local cache_key
    cache_key=$(_cache_make_key "$func_name" "${func_args[@]}")
    if [[ -z "$cache_key" ]]; then
        # Hash failed, run without caching
        "$func_name" "${func_args[@]}"
        return $?
    fi

    local cache_file="${MAINFRAME_CACHE_ROOT}/memo/${cache_key}"
    local meta_file="${cache_file}.meta"

    # Check cache hit
    if [[ -f "$cache_file" ]] && [[ -f "$meta_file" ]]; then
        # Check TTL expiration
        if ! _cache_is_expired "$meta_file"; then
            # Check file dependencies
            if cache_check_deps "$cache_key"; then
                # Cache hit
                _MAINFRAME_CACHE_HITS=$((_MAINFRAME_CACHE_HITS + 1))
                _cache_touch_meta "$meta_file"
                cat "$cache_file"
                return 0
            fi
        fi
    fi

    # Cache miss - acquire lock for thundering herd protection
    _cache_lock "$cache_key"

    # Double-check after acquiring lock (another process may have computed it)
    if [[ -f "$cache_file" ]] && [[ -f "$meta_file" ]]; then
        if ! _cache_is_expired "$meta_file"; then
            if cache_check_deps "$cache_key"; then
                _MAINFRAME_CACHE_HITS=$((_MAINFRAME_CACHE_HITS + 1))
                _cache_touch_meta "$meta_file"
                _cache_unlock "$cache_key"
                cat "$cache_file"
                return 0
            fi
        fi
    fi

    # Execute function and capture output
    _MAINFRAME_CACHE_MISSES=$((_MAINFRAME_CACHE_MISSES + 1))
    local output
    local exit_code
    output=$("$func_name" "${func_args[@]}" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        # Store result atomically
        _cache_atomic_write "$cache_file" "$output"

        # Build and store metadata
        local now
        now=$(_cache_epoch)
        local meta
        meta=$(_cache_build_meta "$now" "$ttl" "0" "$func_name" "${invalidate_files[@]}")
        _cache_atomic_write "$meta_file" "$meta"

        # Register file dependencies if any
        if [[ ${#invalidate_files[@]} -gt 0 ]]; then
            cache_depends_on "$cache_key" "${invalidate_files[@]}"
        fi
    fi

    _cache_unlock "$cache_key"

    # Output the result
    printf '%s' "$output"
    return $exit_code
}

# @pre: none
# @post: matching memoized entries removed from disk
# @returns: 0 on success, number of removed entries printed
#
# Clear memoized cache entries, optionally matching a pattern.
# Without pattern, clears all memoized entries.
#
# Usage: memoize_clear [PATTERN]
# Example: memoize_clear "expensive_*"
# Example: memoize_clear  # clears all
memoize_clear() {
    local pattern="${1:-}"
    local count=0

    local memo_dir="${MAINFRAME_CACHE_ROOT}/memo"
    if [[ ! -d "$memo_dir" ]]; then
        printf '0'
        return 0
    fi

    if [[ -z "$pattern" ]]; then
        # Clear all memoized entries
        local file
        while IFS= read -r -d '' file; do
            local basename="${file##*/}"
            [[ "$basename" == *.meta ]] && continue
            [[ "$basename" == *.deps ]] && continue
            rm -f "$file" "${file}.meta" "${file}.deps" 2>/dev/null
            count=$((count + 1))
        done < <(find "$memo_dir" -type f -print0 2>/dev/null)

        printf '%s' "$count"
        return 0
    fi

    # Use cache_invalidate for pattern matching
    count=$(cache_invalidate "$pattern")
    printf '%s' "$count"
    return 0
}

# @pre: none
# @post: memoization statistics printed to stdout
# @returns: 0
#
# Display memoization statistics: hit/miss counts, hit ratio.
#
# Usage: memoize_stats [--json]
# Example: memoize_stats --json
memoize_stats() {
    local json_output=false

    if [[ "${1:-}" == "--json" ]]; then
        json_output=true
    fi

    local total_requests=$((_MAINFRAME_CACHE_HITS + _MAINFRAME_CACHE_MISSES))
    local hit_ratio=0
    if [[ $total_requests -gt 0 ]]; then
        hit_ratio=$(( (_MAINFRAME_CACHE_HITS * 100) / total_requests ))
    fi

    local memo_count=0
    if [[ -d "${MAINFRAME_CACHE_ROOT}/memo" ]]; then
        memo_count=$(find "${MAINFRAME_CACHE_ROOT}/memo" -type f ! -name "*.meta" ! -name "*.deps" 2>/dev/null | wc -l)
    fi

    if [[ "$json_output" == true ]]; then
        printf '{"hits":%d,"misses":%d,"hit_ratio_pct":%d,"cached_entries":%d}' \
            "$_MAINFRAME_CACHE_HITS" "$_MAINFRAME_CACHE_MISSES" "$hit_ratio" "$memo_count"
    else
        printf 'Memoization Statistics:\n'
        printf '  Hits:           %d\n' "$_MAINFRAME_CACHE_HITS"
        printf '  Misses:         %d\n' "$_MAINFRAME_CACHE_MISSES"
        printf '  Hit Ratio:      %d%%\n' "$hit_ratio"
        printf '  Cached Entries: %d\n' "$memo_count"
    fi

    return 0
}

# =============================================================================
# CONTENT-ADDRESSABLE STORE (CAS)
# =============================================================================

# @pre: MAINFRAME_CACHE_ROOT is writable
# @post: content stored at hash-based path, hash printed to stdout
# @idempotent: yes - storing same content produces same hash, no duplication
# @atomic: yes - temp-then-rename
# @returns: 0 on success, 1 on failure
#
# Store content by its SHA-256 hash. Returns the hash on stdout.
# Duplicate content is automatically deduplicated.
#
# Usage: cas_store "content to store"
# Example: hash=$(cas_store "$(cat config.json)")
cas_store() {
    local content="$1"

    if [[ -z "$content" ]]; then
        _cache_log error "cas_store: content required"
        return 1
    fi

    _cache_ensure_dirs

    local hash
    hash=$(_cache_sha256 "$content")
    if [[ -z "$hash" ]]; then
        return 1
    fi

    # Use first 2 chars as directory prefix for distribution
    local prefix="${hash:0:2}"
    local cas_dir="${MAINFRAME_CACHE_ROOT}/cas/${prefix}"
    local cas_file="${cas_dir}/${hash}"

    mkdir -p "$cas_dir" 2>/dev/null

    # Only write if not already stored (idempotent)
    if [[ ! -f "$cas_file" ]]; then
        _cache_atomic_write "$cas_file" "$content"
    fi

    printf '%s' "$hash"
    return 0
}

# @pre: hash is a valid SHA-256 hex string
# @post: content printed to stdout if found
# @returns: 0 if found and printed, 1 if not found
#
# Retrieve content from the CAS by its hash.
#
# Usage: cas_get HASH
# Example: content=$(cas_get "$hash")
cas_get() {
    local hash="$1"

    if [[ -z "$hash" ]]; then
        _cache_log error "cas_get: hash required"
        return 1
    fi

    local prefix="${hash:0:2}"
    local cas_file="${MAINFRAME_CACHE_ROOT}/cas/${prefix}/${hash}"

    if [[ -f "$cas_file" ]]; then
        cat "$cas_file"
        return 0
    fi

    return 1
}

# @pre: hash is a valid SHA-256 hex string
# @post: none (read-only check)
# @returns: 0 if content exists, 1 if not
#
# Check if content exists in the CAS.
#
# Usage: cas_exists HASH
# Example: if cas_exists "$hash"; then echo "found"; fi
cas_exists() {
    local hash="$1"

    if [[ -z "$hash" ]]; then
        return 1
    fi

    local prefix="${hash:0:2}"
    local cas_file="${MAINFRAME_CACHE_ROOT}/cas/${prefix}/${hash}"

    [[ -f "$cas_file" ]]
}

# @pre: MAINFRAME_CACHE_ROOT/cas exists
# @post: old CAS entries removed from disk
# @returns: 0 on success, number of removed entries printed
#
# Garbage collect old CAS entries based on modification time.
#
# Usage: cas_gc [--older-than DAYS]
# Example: cas_gc --older-than 30
cas_gc() {
    local days=30

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --older-than)
                days="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    local cas_dir="${MAINFRAME_CACHE_ROOT}/cas"
    if [[ ! -d "$cas_dir" ]]; then
        printf '0'
        return 0
    fi

    local count=0
    local file

    # Find files older than specified days and remove them
    while IFS= read -r -d '' file; do
        rm -f "$file" 2>/dev/null
        count=$((count + 1))
    done < <(find "$cas_dir" -type f -mtime +"$days" -print0 2>/dev/null)

    # Clean up empty prefix directories
    find "$cas_dir" -type d -empty -delete 2>/dev/null

    printf '%s' "$count"
    return 0
}

# =============================================================================
# SESSION CACHE (IN-MEMORY)
# =============================================================================

# @pre: KEY is a non-empty string
# @post: value stored in memory-resident associative array
# @returns: 0 on success, 1 if key is empty
#
# Store a value in the in-memory session cache.
# Session cache persists only for the lifetime of the current shell.
#
# Usage: session_cache_set KEY VALUE
# Example: session_cache_set "user_name" "Gordon"
session_cache_set() {
    local key="$1"
    local value="$2"

    if [[ -z "$key" ]]; then
        _cache_log error "session_cache_set: key required"
        return 1
    fi

    _MAINFRAME_SESSION_CACHE["$key"]="$value"
    return 0
}

# @pre: KEY is a non-empty string
# @post: value printed to stdout (or DEFAULT if key not found)
# @returns: 0 if found, 1 if not found (default returned)
#
# Retrieve a value from the in-memory session cache.
#
# Usage: session_cache_get KEY [DEFAULT]
# Example: name=$(session_cache_get "user_name" "unknown")
session_cache_get() {
    local key="$1"
    local default="${2:-}"

    if [[ -z "$key" ]]; then
        printf '%s' "$default"
        return 1
    fi

    if [[ -v "_MAINFRAME_SESSION_CACHE[$key]" ]]; then
        printf '%s' "${_MAINFRAME_SESSION_CACHE[$key]}"
        return 0
    fi

    printf '%s' "$default"
    return 1
}

# @pre: none
# @post: all session cache entries removed
# @returns: 0
#
# Clear the entire in-memory session cache.
#
# Usage: session_cache_clear
session_cache_clear() {
    _MAINFRAME_SESSION_CACHE=()
    return 0
}

# @pre: KEY is a non-empty string
# @post: none (read-only check)
# @returns: 0 if key exists, 1 if not
#
# Check if a key exists in the session cache.
#
# Usage: session_cache_has KEY
# Example: if session_cache_has "user_name"; then echo "exists"; fi
session_cache_has() {
    local key="$1"

    if [[ -z "$key" ]]; then
        return 1
    fi

    [[ -v "_MAINFRAME_SESSION_CACHE[$key]" ]]
}

# @pre: none
# @post: statistics printed to stdout (plain text or JSON)
# @returns: 0
#
# Display session cache statistics: entry count, estimated memory usage.
#
# Usage: session_cache_stats [--json]
# Example: session_cache_stats --json
session_cache_stats() {
    local json_output=false

    if [[ "${1:-}" == "--json" ]]; then
        json_output=true
    fi

    local entry_count=${#_MAINFRAME_SESSION_CACHE[@]}
    local total_bytes=0

    # Estimate memory usage (key length + value length)
    local key
    for key in "${!_MAINFRAME_SESSION_CACHE[@]}"; do
        total_bytes=$((total_bytes + ${#key} + ${#_MAINFRAME_SESSION_CACHE[$key]}))
    done

    if [[ "$json_output" == true ]]; then
        printf '{"entries":%d,"estimated_bytes":%d}' "$entry_count" "$total_bytes"
    else
        printf 'Session Cache Statistics:\n'
        printf '  Entries:         %d\n' "$entry_count"
        printf '  Estimated bytes: %d\n' "$total_bytes"
    fi

    return 0
}

# =============================================================================
# CACHE MANAGEMENT
# =============================================================================

# @pre: PATTERN is a non-empty string (function name, key prefix, or glob)
# @post: matching cache entries removed from disk
# @returns: 0 on success, number of removed entries printed
#
# Invalidate cache entries matching a pattern.
# Supports: exact cache key, function name prefix, or shell glob.
#
# Usage: cache_invalidate PATTERN
# Example: cache_invalidate "expensive_*"
# Example: cache_invalidate "abc123def456..."  (exact key)
cache_invalidate() {
    local pattern="$1"
    local count=0

    if [[ -z "$pattern" ]]; then
        _cache_log error "cache_invalidate: pattern required"
        return 1
    fi

    local memo_dir="${MAINFRAME_CACHE_ROOT}/memo"
    if [[ ! -d "$memo_dir" ]]; then
        printf '0'
        return 0
    fi

    # Strategy 1: Exact key match
    if [[ -f "${memo_dir}/${pattern}" ]]; then
        rm -f "${memo_dir}/${pattern}" "${memo_dir}/${pattern}.meta" "${memo_dir}/${pattern}.deps" 2>/dev/null
        count=$((count + 1))
    fi

    # Strategy 2: Search meta files for function name match
    local meta_file
    while IFS= read -r -d '' meta_file; do
        if [[ -f "$meta_file" ]]; then
            local meta
            meta=$(< "$meta_file")
            local func
            func=$(_cache_json_get "$meta" "function")
            if [[ "$func" == $pattern ]]; then
                local base="${meta_file%.meta}"
                rm -f "$base" "$meta_file" "${base}.deps" 2>/dev/null
                count=$((count + 1))
            fi
        fi
    done < <(find "$memo_dir" -name "*.meta" -print0 2>/dev/null)

    # Strategy 3: Glob match on keys (for wildcard patterns)
    if [[ "$pattern" == *'*'* ]] || [[ "$pattern" == *'?'* ]]; then
        local file
        while IFS= read -r -d '' file; do
            local basename="${file##*/}"
            # Skip meta and deps files
            [[ "$basename" == *.meta ]] && continue
            [[ "$basename" == *.deps ]] && continue
            rm -f "$file" "${file}.meta" "${file}.deps" 2>/dev/null
            count=$((count + 1))
        done < <(find "$memo_dir" -name "${pattern}" -print0 2>/dev/null)
    fi

    printf '%s' "$count"
    return 0
}

# @pre: none (--force skips confirmation)
# @post: entire cache directory cleared
# @returns: 0 on success
#
# Clear the entire cache (memo + CAS + locks).
#
# Usage: cache_clear [--force]
# Example: cache_clear --force
cache_clear() {
    local force=false

    if [[ "${1:-}" == "--force" ]]; then
        force=true
    fi

    if [[ ! -d "$MAINFRAME_CACHE_ROOT" ]]; then
        return 0
    fi

    if [[ "$force" != true ]]; then
        _cache_log warn "cache_clear: use --force to confirm cache deletion"
        return 1
    fi

    rm -rf "${MAINFRAME_CACHE_ROOT}/memo" 2>/dev/null
    rm -rf "${MAINFRAME_CACHE_ROOT}/cas" 2>/dev/null
    rm -rf "${MAINFRAME_CACHE_ROOT}/locks" 2>/dev/null

    # Reset statistics
    _MAINFRAME_CACHE_HITS=0
    _MAINFRAME_CACHE_MISSES=0

    _cache_ensure_dirs
    _cache_log info "Cache cleared"
    return 0
}

# @pre: none
# @post: statistics printed to stdout (plain text or JSON)
# @returns: 0
#
# Display cache statistics: hit/miss ratio, size, entry count.
#
# Usage: cache_stats [--json]
# Example: cache_stats --json
cache_stats() {
    local json_output=false

    if [[ "${1:-}" == "--json" ]]; then
        json_output=true
    fi

    local total_size=0
    local memo_count=0
    local cas_count=0

    if [[ -d "$MAINFRAME_CACHE_ROOT" ]]; then
        total_size=$(_cache_total_size)
    fi

    if [[ -d "${MAINFRAME_CACHE_ROOT}/memo" ]]; then
        memo_count=$(find "${MAINFRAME_CACHE_ROOT}/memo" -type f ! -name "*.meta" ! -name "*.deps" 2>/dev/null | wc -l)
    fi

    if [[ -d "${MAINFRAME_CACHE_ROOT}/cas" ]]; then
        cas_count=$(find "${MAINFRAME_CACHE_ROOT}/cas" -type f 2>/dev/null | wc -l)
    fi

    local total_requests=$((_MAINFRAME_CACHE_HITS + _MAINFRAME_CACHE_MISSES))
    local hit_ratio=0
    if [[ $total_requests -gt 0 ]]; then
        hit_ratio=$(( (_MAINFRAME_CACHE_HITS * 100) / total_requests ))
    fi

    local size_mb
    if [[ $total_size -gt 0 ]]; then
        size_mb=$(( total_size / 1048576 ))
    else
        size_mb=0
    fi

    if [[ "$json_output" == true ]]; then
        printf '{"hits":%d,"misses":%d,"hit_ratio_pct":%d,"memo_entries":%d,"cas_entries":%d,"total_size_bytes":%d,"size_mb":%d,"max_size_mb":%d}' \
            "$_MAINFRAME_CACHE_HITS" "$_MAINFRAME_CACHE_MISSES" "$hit_ratio" \
            "$memo_count" "$cas_count" "$total_size" "$size_mb" "$MAINFRAME_CACHE_MAX_SIZE_MB"
    else
        printf 'Cache Statistics:\n'
        printf '  Hits:          %d\n' "$_MAINFRAME_CACHE_HITS"
        printf '  Misses:        %d\n' "$_MAINFRAME_CACHE_MISSES"
        printf '  Hit Ratio:     %d%%\n' "$hit_ratio"
        printf '  Memo Entries:  %d\n' "$memo_count"
        printf '  CAS Entries:   %d\n' "$cas_count"
        printf '  Total Size:    %d bytes (%d MB)\n' "$total_size" "$size_mb"
        printf '  Max Size:      %d MB\n' "$MAINFRAME_CACHE_MAX_SIZE_MB"
    fi

    return 0
}

# @pre: SIZE is a valid size specification (e.g., "256MB", "1GB", or numeric MB)
# @post: MAINFRAME_CACHE_MAX_SIZE_MB updated, LRU eviction triggered if over limit
# @returns: 0 on success
#
# Set the maximum cache size. Triggers eviction if current size exceeds new limit.
#
# Usage: cache_max_size SIZE
# Example: cache_max_size "256MB"
# Example: cache_max_size 512
cache_max_size() {
    local size_spec="$1"

    if [[ -z "$size_spec" ]]; then
        _cache_log error "cache_max_size: size required"
        return 1
    fi

    local size_mb

    # Parse size specification
    case "$size_spec" in
        *GB|*gb)
            size_mb=$(( ${size_spec%[Gg][Bb]} * 1024 ))
            ;;
        *MB|*mb)
            size_mb=${size_spec%[Mm][Bb]}
            ;;
        *KB|*kb)
            size_mb=$(( ${size_spec%[Kk][Bb]} / 1024 ))
            [[ $size_mb -eq 0 ]] && size_mb=1
            ;;
        *)
            # Assume numeric MB
            size_mb="$size_spec"
            ;;
    esac

    # Validate numeric
    if ! [[ "$size_mb" =~ ^[0-9]+$ ]]; then
        _cache_log error "cache_max_size: invalid size format"
        return 1
    fi

    MAINFRAME_CACHE_MAX_SIZE_MB="$size_mb"

    # Trigger eviction if over limit
    cache_evict_lru "$size_mb" >/dev/null

    return 0
}

# @pre: MAX_SIZE_MB is a positive integer (defaults to MAINFRAME_CACHE_MAX_SIZE_MB)
# @post: least-recently-used entries evicted until cache is under limit
# @returns: 0 on success, number of evicted entries
#
# Evict least-recently-used cache entries to stay within size limits.
# Uses file modification time as LRU proxy.
#
# Usage: cache_evict_lru [MAX_SIZE_MB]
# Example: cache_evict_lru 256
cache_evict_lru() {
    local max_mb="${1:-$MAINFRAME_CACHE_MAX_SIZE_MB}"
    local max_bytes=$((max_mb * 1048576))
    local evicted=0

    if [[ ! -d "${MAINFRAME_CACHE_ROOT}/memo" ]]; then
        printf '0'
        return 0
    fi

    local current_size
    current_size=$(_cache_total_size)

    if [[ $current_size -le $max_bytes ]]; then
        printf '0'
        return 0
    fi

    # Sort memo entries by modification time (oldest first = LRU)
    local -a files_by_age=()
    while IFS= read -r file; do
        files_by_age+=("$file")
    done < <(find "${MAINFRAME_CACHE_ROOT}/memo" -type f ! -name "*.meta" ! -name "*.deps" -printf '%T@ %p\n' 2>/dev/null | sort -n | cut -d' ' -f2-)

    # Fallback for macOS (no -printf)
    if [[ ${#files_by_age[@]} -eq 0 ]]; then
        while IFS= read -r file; do
            files_by_age+=("$file")
        done < <(find "${MAINFRAME_CACHE_ROOT}/memo" -type f ! -name "*.meta" ! -name "*.deps" -exec stat -f '%m %N' {} \; 2>/dev/null | sort -n | cut -d' ' -f2-)
    fi

    for file in "${files_by_age[@]}"; do
        if [[ $current_size -le $max_bytes ]]; then
            break
        fi

        local file_size
        file_size=$(stat -c %s "$file" 2>/dev/null || stat -f %z "$file" 2>/dev/null || echo 0)

        rm -f "$file" "${file}.meta" "${file}.deps" 2>/dev/null
        current_size=$((current_size - file_size))
        evicted=$((evicted + 1))
    done

    printf '%s' "$evicted"
    return 0
}

# =============================================================================
# DEPENDENCY-AWARE INVALIDATION
# =============================================================================

# @pre: CACHE_KEY exists or will exist, FILE paths are valid
# @post: dependency hashes stored in .deps file
# @returns: 0 on success
#
# Register file dependencies for a cache key.
# When files change (hash differs), the cache entry is considered stale.
#
# Usage: cache_depends_on CACHE_KEY FILE...
# Example: cache_depends_on "$key" "/etc/config.json" "/etc/hosts"
cache_depends_on() {
    local cache_key="$1"
    shift
    local -a files=("$@")

    if [[ -z "$cache_key" ]] || [[ ${#files[@]} -eq 0 ]]; then
        _cache_log error "cache_depends_on: cache_key and at least one file required"
        return 1
    fi

    _cache_ensure_dirs

    local deps_file="${MAINFRAME_CACHE_ROOT}/memo/${cache_key}.deps"
    local deps_content=""

    local file
    for file in "${files[@]}"; do
        local hash=""
        if [[ -f "$file" ]]; then
            hash=$(_cache_sha256_file "$file")
        fi
        deps_content+="${file}|${hash}"$'\n'
    done

    _cache_atomic_write "$deps_file" "$deps_content"
    return 0
}

# @pre: CACHE_KEY has registered dependencies
# @post: none (read-only check)
# @returns: 0 if deps are unchanged (cache valid), 1 if deps changed (stale)
#
# Check if file dependencies for a cache key have changed.
# Compares current file hashes against stored dependency hashes.
#
# Usage: cache_check_deps CACHE_KEY
# Example: if cache_check_deps "$key"; then echo "still valid"; fi
cache_check_deps() {
    local cache_key="$1"

    local deps_file="${MAINFRAME_CACHE_ROOT}/memo/${cache_key}.deps"

    # No deps file means no dependencies - cache is valid
    if [[ ! -f "$deps_file" ]]; then
        return 0
    fi

    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local file="${line%%|*}"
        local stored_hash="${line#*|}"

        # File was tracked but didn't exist before
        if [[ -z "$stored_hash" ]]; then
            # If it exists now, deps changed
            if [[ -f "$file" ]]; then
                return 1
            fi
            continue
        fi

        # File no longer exists
        if [[ ! -f "$file" ]]; then
            return 1
        fi

        # Compare current hash to stored hash
        local current_hash
        current_hash=$(_cache_sha256_file "$file")
        if [[ "$current_hash" != "$stored_hash" ]]; then
            return 1
        fi
    done < "$deps_file"

    return 0
}

# =============================================================================
# SMART PRELOADING
# =============================================================================

# @pre: PROJECT_TYPE is a recognized type (bash, node, python, etc.)
# @post: common operations for project type are pre-cached
# @returns: 0 on success
#
# Warm the cache by preloading common operations for a project type.
# Useful for speeding up first-time operations in a new session.
#
# Usage: cache_warm PROJECT_TYPE [PROJECT_DIR]
# Example: cache_warm "project-type=node" "/path/to/project"
# Example: cache_warm "project-type=python"
cache_warm() {
    local spec="$1"
    local project_dir="${2:-.}"

    if [[ -z "$spec" ]]; then
        _cache_log error "cache_warm: specification required (e.g., project-type=node)"
        return 1
    fi

    _cache_ensure_dirs

    local project_type=""

    # Parse specification
    case "$spec" in
        project-type=*)
            project_type="${spec#project-type=}"
            ;;
        *)
            project_type="$spec"
            ;;
    esac

    # Preload based on project type
    case "$project_type" in
        node|nodejs|npm)
            # Node.js project preloading
            if [[ -f "${project_dir}/package.json" ]]; then
                # Cache package.json hash for dependency detection
                local pkg_hash
                pkg_hash=$(_cache_sha256_file "${project_dir}/package.json")
                session_cache_set "_warm_node_pkg_hash" "$pkg_hash"

                # Pre-cache common node patterns
                session_cache_set "_warm_project_type" "node"
            fi
            ;;

        python|py)
            # Python project preloading
            if [[ -f "${project_dir}/requirements.txt" ]]; then
                local req_hash
                req_hash=$(_cache_sha256_file "${project_dir}/requirements.txt")
                session_cache_set "_warm_py_req_hash" "$req_hash"
            fi

            if [[ -f "${project_dir}/pyproject.toml" ]]; then
                local pyp_hash
                pyp_hash=$(_cache_sha256_file "${project_dir}/pyproject.toml")
                session_cache_set "_warm_py_pyproject_hash" "$pyp_hash"
            fi

            session_cache_set "_warm_project_type" "python"
            ;;

        bash|shell)
            # Bash project preloading
            session_cache_set "_warm_project_type" "bash"

            # Cache shell detection info
            session_cache_set "_warm_bash_version" "${BASH_VERSION:-unknown}"
            ;;

        go|golang)
            # Go project preloading
            if [[ -f "${project_dir}/go.mod" ]]; then
                local mod_hash
                mod_hash=$(_cache_sha256_file "${project_dir}/go.mod")
                session_cache_set "_warm_go_mod_hash" "$mod_hash"
            fi

            session_cache_set "_warm_project_type" "go"
            ;;

        rust|cargo)
            # Rust project preloading
            if [[ -f "${project_dir}/Cargo.toml" ]]; then
                local cargo_hash
                cargo_hash=$(_cache_sha256_file "${project_dir}/Cargo.toml")
                session_cache_set "_warm_rust_cargo_hash" "$cargo_hash"
            fi

            session_cache_set "_warm_project_type" "rust"
            ;;

        *)
            # Generic preloading - detect project type
            if [[ -f "${project_dir}/package.json" ]]; then
                cache_warm "project-type=node" "$project_dir"
            elif [[ -f "${project_dir}/requirements.txt" ]] || [[ -f "${project_dir}/pyproject.toml" ]]; then
                cache_warm "project-type=python" "$project_dir"
            elif [[ -f "${project_dir}/go.mod" ]]; then
                cache_warm "project-type=go" "$project_dir"
            elif [[ -f "${project_dir}/Cargo.toml" ]]; then
                cache_warm "project-type=rust" "$project_dir"
            else
                session_cache_set "_warm_project_type" "unknown"
            fi
            ;;
    esac

    _cache_log debug "Cache warmed for project type: ${project_type}"
    return 0
}

# =============================================================================
# AI-AGENT OPTIMIZED CACHING (v2.0)
# =============================================================================
# Extended caching primitives for AI agent workflows:
# - Function decorator-style memoization
# - Command output caching with TTL
# - File content caching with auto-invalidation
# - Computation caching with dependency tracking
# - Cache statistics and prewarming
# =============================================================================

# @pre: FN_NAME is a declared function
# @post: function is wrapped with memoization, original preserved as _memo_orig_FN_NAME
# @idempotent: no - calling twice will double-wrap (use memo_unwrap first)
# @returns: 0 on success, 1 if function not found
#
# Decorator-style memoization: wraps an existing function so all calls are cached.
# The original function is preserved as _memo_orig_<fn_name>.
#
# Usage: memo_wrap FUNCTION_NAME [TTL_SECONDS]
# Example: memo_wrap expensive_lookup 300
memo_wrap() {
    local fn_name="$1"
    local ttl="${2:-3600}"

    # Verify function exists
    if ! declare -F "$fn_name" &>/dev/null; then
        _cache_log error "memo_wrap: function '$fn_name' not found"
        return 1
    fi

    # Check if already wrapped
    local orig_fn="_memo_orig_${fn_name}"
    if declare -F "$orig_fn" &>/dev/null; then
        _cache_log warn "memo_wrap: function '$fn_name' already wrapped"
        return 0
    fi

    # Save original function definition
    local fn_def
    fn_def=$(declare -f "$fn_name")

    # Create the original backup
    eval "${fn_def/$fn_name/$orig_fn}"

    # Create memoized wrapper
    eval "${fn_name}() {
        local _memo_key=\"memo_${fn_name}_\$(_cache_sha256 \"\$*\")\"
        local _memo_file=\"\${MAINFRAME_CACHE_ROOT}/memo/\${_memo_key}\"
        local _memo_meta=\"\${_memo_file}.meta\"

        _cache_ensure_dirs

        # Check cache
        if [[ -f \"\$_memo_file\" ]] && [[ -f \"\$_memo_meta\" ]]; then
            if ! _cache_is_expired \"\$_memo_meta\"; then
                _MAINFRAME_CACHE_HITS=\$((_MAINFRAME_CACHE_HITS + 1))
                _cache_touch_meta \"\$_memo_meta\"
                cat \"\$_memo_file\"
                return 0
            fi
        fi

        # Cache miss - compute
        _MAINFRAME_CACHE_MISSES=\$((_MAINFRAME_CACHE_MISSES + 1))
        local _memo_result
        _memo_result=\$($orig_fn \"\$@\")
        local _memo_exit=\$?

        if [[ \$_memo_exit -eq 0 ]]; then
            _cache_atomic_write \"\$_memo_file\" \"\$_memo_result\"
            local _memo_now
            _memo_now=\$(_cache_epoch)
            _cache_atomic_write \"\$_memo_meta\" \"{\\\"timestamp\\\":\$_memo_now,\\\"ttl\\\":$ttl,\\\"hit_count\\\":0,\\\"function\\\":\\\"$fn_name\\\",\\\"deps\\\":[]}\"
        fi

        printf '%s' \"\$_memo_result\"
        return \$_memo_exit
    }"

    return 0
}

# @pre: FN_NAME was previously wrapped with memo_wrap
# @post: original function restored, wrapper removed
# @returns: 0 on success, 1 if not wrapped
#
# Remove memoization wrapper and restore original function.
#
# Usage: memo_unwrap FUNCTION_NAME
# Example: memo_unwrap expensive_lookup
memo_unwrap() {
    local fn_name="$1"
    local orig_fn="_memo_orig_${fn_name}"

    if ! declare -F "$orig_fn" &>/dev/null; then
        _cache_log error "memo_unwrap: function '$fn_name' is not wrapped"
        return 1
    fi

    # Restore original
    local fn_def
    fn_def=$(declare -f "$orig_fn")
    eval "${fn_def/$orig_fn/$fn_name}"

    # Remove the backup
    unset -f "$orig_fn"

    return 0
}

# @pre: FN_NAME was wrapped with memo_wrap
# @post: cached entries for this function are cleared
# @returns: number of cleared entries
#
# Clear memoization cache for a specific wrapped function.
#
# Usage: memo_clear FUNCTION_NAME
# Example: memo_clear expensive_lookup
memo_clear() {
    local fn_name="$1"
    local count=0

    if [[ -z "$fn_name" ]]; then
        _cache_log error "memo_clear: function name required"
        return 1
    fi

    local memo_dir="${MAINFRAME_CACHE_ROOT}/memo"
    if [[ ! -d "$memo_dir" ]]; then
        printf '0'
        return 0
    fi

    # Find and remove entries matching this function
    local pattern="memo_${fn_name}_"
    local file
    while IFS= read -r -d '' file; do
        local basename="${file##*/}"
        if [[ "$basename" == ${pattern}* ]]; then
            rm -f "$file" "${file}.meta" "${file}.deps" 2>/dev/null
            count=$((count + 1))
        fi
    done < <(find "$memo_dir" -type f ! -name "*.meta" ! -name "*.deps" -print0 2>/dev/null)

    printf '%s' "$count"
    return 0
}

# @pre: TTL is a positive integer (seconds)
# @post: command output cached on disk
# @returns: command exit code
#
# Cache command output with TTL. Useful for expensive shell commands like
# git status, find operations, or network requests.
#
# Usage: cache_command TTL COMMAND [ARGS...]
# Example: cache_command 5 git status --porcelain
# Example: cache_command 60 curl -s https://api.example.com/data
cache_command() {
    local ttl="$1"
    shift

    if [[ $# -eq 0 ]]; then
        _cache_log error "cache_command: command required"
        return 1
    fi

    _cache_ensure_dirs

    # Build cache key from command string
    local cmd_string="$*"
    local cache_key
    cache_key="cmd_$(_cache_sha256 "$cmd_string")"
    local cache_file="${MAINFRAME_CACHE_ROOT}/memo/${cache_key}"
    local meta_file="${cache_file}.meta"

    # Check cache
    if [[ -f "$cache_file" ]] && [[ -f "$meta_file" ]]; then
        if ! _cache_is_expired "$meta_file"; then
            _MAINFRAME_CACHE_HITS=$((_MAINFRAME_CACHE_HITS + 1))
            _cache_touch_meta "$meta_file"
            cat "$cache_file"
            return 0
        fi
    fi

    # Cache miss - execute command
    _MAINFRAME_CACHE_MISSES=$((_MAINFRAME_CACHE_MISSES + 1))
    local result
    result=$("$@" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        _cache_atomic_write "$cache_file" "$result"
        local now
        now=$(_cache_epoch)
        local meta
        meta=$(_cache_build_meta "$now" "$ttl" "0" "command" )
        _cache_atomic_write "$meta_file" "$meta"
    fi

    printf '%s' "$result"
    return $exit_code
}

# @pre: PATH is a valid file path
# @post: file content cached with inode+mtime key for auto-invalidation
# @returns: 0 on success, 1 if file not found
#
# Cache file contents with automatic invalidation when file changes.
# Uses inode + mtime as cache key, so modifications trigger re-read.
#
# Usage: cache_file PATH
# Example: content=$(cache_file "/etc/hosts")
cache_file() {
    local path="$1"

    if [[ ! -f "$path" ]]; then
        _cache_log error "cache_file: file not found: $path"
        return 1
    fi

    _cache_ensure_dirs

    # Build cache key from path + stat info
    local stat_info
    stat_info=$(stat -c '%i_%Y_%s' "$path" 2>/dev/null || stat -f '%i_%m_%z' "$path" 2>/dev/null)
    if [[ -z "$stat_info" ]]; then
        # Fallback: just use path hash
        stat_info=$(date +%s)
    fi

    local path_safe="${path//\//_}"
    local cache_key="file_${path_safe}_$(_cache_sha256 "$stat_info")"
    local cache_file="${MAINFRAME_CACHE_ROOT}/memo/${cache_key}"
    local meta_file="${cache_file}.meta"

    # Check cache - file caches don't expire by time, only by content change
    if [[ -f "$cache_file" ]]; then
        _MAINFRAME_CACHE_HITS=$((_MAINFRAME_CACHE_HITS + 1))
        cat "$cache_file"
        return 0
    fi

    # Cache miss - read file
    _MAINFRAME_CACHE_MISSES=$((_MAINFRAME_CACHE_MISSES + 1))
    local content
    content=$(<"$path")

    _cache_atomic_write "$cache_file" "$content"
    local now
    now=$(_cache_epoch)
    # TTL of 0 = never expires by time (only by stat change)
    local meta
    meta=$(_cache_build_meta "$now" "0" "0" "file:$path")
    _cache_atomic_write "$meta_file" "$meta"

    printf '%s' "$content"
    return 0
}

# @pre: PATH is a valid file path that was previously cached
# @post: cached content for this file is removed
# @returns: 0 on success
#
# Invalidate file cache when you know the file has changed.
#
# Usage: cache_file_invalidate PATH
# Example: cache_file_invalidate "/etc/hosts"
cache_file_invalidate() {
    local path="$1"
    local path_safe="${path//\//_}"
    local pattern="file_${path_safe}_"
    local count=0

    local memo_dir="${MAINFRAME_CACHE_ROOT}/memo"
    if [[ ! -d "$memo_dir" ]]; then
        return 0
    fi

    local file
    while IFS= read -r -d '' file; do
        local basename="${file##*/}"
        if [[ "$basename" == ${pattern}* ]]; then
            rm -f "$file" "${file}.meta" 2>/dev/null
            count=$((count + 1))
        fi
    done < <(find "$memo_dir" -type f ! -name "*.meta" -print0 2>/dev/null)

    return 0
}

# @pre: KEY is a unique identifier, COMPUTE_FN is a function name
# @post: computed result cached with dependency tracking
# @returns: computed result (cached or fresh)
#
# Cache expensive computations with dependency tracking on files.
# Result is invalidated when any dependency file changes.
#
# Usage: cache_compute KEY COMPUTE_FN [DEPENDENCY_FILE...]
# Example: cache_compute "project_summary" compute_summary package.json tsconfig.json
cache_compute() {
    local key="$1"
    local compute_fn="$2"
    shift 2
    local -a deps=("$@")

    if [[ -z "$key" ]] || [[ -z "$compute_fn" ]]; then
        _cache_log error "cache_compute: key and compute function required"
        return 1
    fi

    if ! declare -F "$compute_fn" &>/dev/null; then
        _cache_log error "cache_compute: function '$compute_fn' not found"
        return 1
    fi

    _cache_ensure_dirs

    # Build dependency hash from all file stats
    local dep_hash=""
    local dep
    for dep in "${deps[@]}"; do
        if [[ -f "$dep" ]]; then
            local stat_info
            stat_info=$(stat -c '%i_%Y_%s' "$dep" 2>/dev/null || stat -f '%i_%m_%z' "$dep" 2>/dev/null)
            dep_hash+="${dep}:${stat_info}|"
        else
            dep_hash+="${dep}:missing|"
        fi
    done

    local cache_key="compute_${key}_$(_cache_sha256 "$dep_hash")"
    local cache_file="${MAINFRAME_CACHE_ROOT}/memo/${cache_key}"
    local meta_file="${cache_file}.meta"

    # Check cache
    if [[ -f "$cache_file" ]] && [[ -f "$meta_file" ]]; then
        # For compute caches, we rely on the dep_hash being in the key
        # So if the file exists, the deps haven't changed
        _MAINFRAME_CACHE_HITS=$((_MAINFRAME_CACHE_HITS + 1))
        _cache_touch_meta "$meta_file"
        cat "$cache_file"
        return 0
    fi

    # Cache miss - compute
    _MAINFRAME_CACHE_MISSES=$((_MAINFRAME_CACHE_MISSES + 1))
    local result
    result=$("$compute_fn")
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        _cache_atomic_write "$cache_file" "$result"
        local now
        now=$(_cache_epoch)
        local meta
        meta=$(_cache_build_meta "$now" "0" "0" "$compute_fn" "${deps[@]}")
        _cache_atomic_write "$meta_file" "$meta"

        # Also register deps for explicit invalidation checks
        if [[ ${#deps[@]} -gt 0 ]]; then
            cache_depends_on "$cache_key" "${deps[@]}"
        fi
    fi

    printf '%s' "$result"
    return $exit_code
}

# @pre: none
# @post: hit/miss counters reset to 0
# @returns: 0
#
# Reset cache statistics counters.
#
# Usage: cache_stats_reset
cache_stats_reset() {
    _MAINFRAME_CACHE_HITS=0
    _MAINFRAME_CACHE_MISSES=0
    return 0
}

# @pre: PROFILE is one of: standard, git, project, system, all
# @post: common operations for the profile are pre-cached
# @returns: 0 on success
#
# Prewarm cache with common operations for AI agent workflows.
# This reduces latency for first-time operations.
#
# Usage: cache_prewarm [PROFILE]
# Example: cache_prewarm git
# Example: cache_prewarm project
cache_prewarm() {
    local profile="${1:-standard}"

    _cache_ensure_dirs

    case "$profile" in
        git)
            # Git operations are frequently repeated
            if command -v git &>/dev/null && git rev-parse --git-dir &>/dev/null 2>&1; then
                cache_command 60 git status --porcelain 2>/dev/null || true
                cache_command 300 git branch --show-current 2>/dev/null || true
                cache_command 300 git rev-parse --short HEAD 2>/dev/null || true
                cache_command 300 git remote get-url origin 2>/dev/null || true
            fi
            ;;

        project)
            # Cache common project files
            local files=(
                "package.json"
                "Cargo.toml"
                "pyproject.toml"
                "go.mod"
                "requirements.txt"
                "tsconfig.json"
                "Makefile"
            )
            local f
            for f in "${files[@]}"; do
                [[ -f "$f" ]] && cache_file "$f" >/dev/null 2>&1 || true
            done
            ;;

        system)
            # System info rarely changes
            cache_command 3600 uname -a 2>/dev/null || true
            cache_command 3600 hostname 2>/dev/null || true
            cache_command 3600 whoami 2>/dev/null || true
            cache_command 300 pwd 2>/dev/null || true
            ;;

        standard|all)
            # Combined prewarming
            cache_prewarm git
            cache_prewarm project
            cache_prewarm system
            ;;

        *)
            _cache_log warn "cache_prewarm: unknown profile '$profile'"
            return 1
            ;;
    esac

    return 0
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_CACHE_EXPORTS=(
    # Memoization (original)
    memoize
    memoize_clear
    memoize_stats
    # Decorator-style Memoization (v2.0)
    memo_wrap
    memo_unwrap
    memo_clear
    # Command Caching (v2.0)
    cache_command
    # File Caching (v2.0)
    cache_file
    cache_file_invalidate
    # Computation Caching (v2.0)
    cache_compute
    # Statistics (v2.0)
    cache_stats_reset
    # Prewarming (v2.0)
    cache_prewarm
    # Content-Addressable Store
    cas_store
    cas_get
    cas_exists
    cas_gc
    # Session Cache
    session_cache_set
    session_cache_get
    session_cache_has
    session_cache_clear
    session_cache_stats
    # Cache Management
    cache_invalidate
    cache_clear
    cache_stats
    cache_max_size
    cache_evict_lru
    cache_warm
    # Dependency-Aware Invalidation
    cache_depends_on
    cache_check_deps
)

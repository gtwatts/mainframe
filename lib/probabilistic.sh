#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/probabilistic.sh - Probabilistic Data Structures
# =============================================================================
# Description: Pure bash implementation of space-efficient probabilistic data
#              structures for approximate membership, cardinality, and frequency
#              estimation. Includes Bloom filters, HyperLogLog, Count-Min Sketch,
#              and MinHash for Jaccard similarity.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_PROBABILISTIC_LOADED:-}" ]] && return 0
readonly _MAINFRAME_PROBABILISTIC_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default Bloom filter parameters
PROB_BLOOM_DEFAULT_SIZE="${PROB_BLOOM_DEFAULT_SIZE:-1024}"
PROB_BLOOM_DEFAULT_HASHES="${PROB_BLOOM_DEFAULT_HASHES:-7}"

# Default HyperLogLog precision (registers = 2^precision)
PROB_HLL_DEFAULT_PRECISION="${PROB_HLL_DEFAULT_PRECISION:-14}"

# Default Count-Min Sketch parameters
PROB_CMS_DEFAULT_WIDTH="${PROB_CMS_DEFAULT_WIDTH:-1024}"
PROB_CMS_DEFAULT_DEPTH="${PROB_CMS_DEFAULT_DEPTH:-5}"

# Default MinHash signature size
PROB_MINHASH_DEFAULT_SIZE="${PROB_MINHASH_DEFAULT_SIZE:-128}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# JSON-escape a string for USOP output
# @pre: input string provided
# @post: escaped string returned
_prob_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Emit structured error (USOP compliant)
# @pre: code is integer, msg is non-empty
# @post: JSON error emitted to stderr
# @returns: the provided exit code
_prob_error() {
    local code="${1:-1}"
    local msg="${2:-unknown error}"
    shift 2 2>/dev/null || shift $#

    local func="${FUNCNAME[1]:-main}"
    local escaped_msg escaped_func
    escaped_msg=$(_prob_json_escape "$msg")
    escaped_func=$(_prob_json_escape "$func")

    local json
    json="{\"error\":true,\"code\":$code,\"msg\":\"$escaped_msg\",\"func\":\"$escaped_func\""

    # Add context key=value pairs
    if [[ $# -gt 0 ]]; then
        json+=",\"context\":{"
        local first=true kv key val
        for kv in "$@"; do
            key="${kv%%=*}"
            val="${kv#*=}"
            local escaped_key escaped_val
            escaped_key=$(_prob_json_escape "$key")
            escaped_val=$(_prob_json_escape "$val")
            [[ "$first" == "true" ]] || json+=","
            first=false
            json+="\"$escaped_key\":\"$escaped_val\""
        done
        json+="}"
    fi

    json+="}"
    printf '%s\n' "$json" >&2
    return "$code"
}

# =============================================================================
# HASH FUNCTIONS
# =============================================================================

# General-purpose hash function using djb2 algorithm
# @pre: input string provided
# @post: 32-bit hash returned as decimal
# @idempotent: yes
# @returns: hash value
#
# Usage: prob_hash "string"
# Example: hash=$(prob_hash "hello")
prob_hash() {
    local str="$1"
    local hash=5381
    local i char_code

    for ((i = 0; i < ${#str}; i++)); do
        printf -v char_code '%d' "'${str:i:1}"
        hash=$(( ((hash << 5) + hash + char_code) & 0xFFFFFFFF ))
    done

    printf '%u\n' "$hash"
}

# MurmurHash3-inspired hash function (32-bit)
# @pre: input string and optional seed provided
# @post: 32-bit hash returned as decimal
# @idempotent: yes
# @returns: hash value
#
# Usage: prob_murmurhash "string" [seed]
# Example: hash=$(prob_murmurhash "hello" 42)
prob_murmurhash() {
    local str="$1"
    local seed="${2:-0}"
    local h="$seed"
    local c1=0xcc9e2d51
    local c2=0x1b873593
    local r1=15
    local r2=13
    local m=5
    local n=0xe6546b64
    local i char_code k

    for ((i = 0; i < ${#str}; i++)); do
        printf -v char_code '%d' "'${str:i:1}"
        k=$char_code

        k=$(( (k * c1) & 0xFFFFFFFF ))
        k=$(( ((k << r1) | (k >> (32 - r1))) & 0xFFFFFFFF ))
        k=$(( (k * c2) & 0xFFFFFFFF ))

        h=$(( (h ^ k) & 0xFFFFFFFF ))
        h=$(( ((h << r2) | (h >> (32 - r2))) & 0xFFFFFFFF ))
        h=$(( (h * m + n) & 0xFFFFFFFF ))
    done

    # Finalization mix
    h=$(( (h ^ ${#str}) & 0xFFFFFFFF ))
    h=$(( (h ^ (h >> 16)) & 0xFFFFFFFF ))
    h=$(( (h * 0x85ebca6b) & 0xFFFFFFFF ))
    h=$(( (h ^ (h >> 13)) & 0xFFFFFFFF ))
    h=$(( (h * 0xc2b2ae35) & 0xFFFFFFFF ))
    h=$(( (h ^ (h >> 16)) & 0xFFFFFFFF ))

    printf '%u\n' "$h"
}

# Generate multiple hash values for an element
# @pre: element string, count, and max value provided
# @post: newline-separated hash values returned
# @idempotent: yes
# @returns: hash values
#
# Usage: _prob_multi_hash "element" count max_value
_prob_multi_hash() {
    local element="$1"
    local count="$2"
    local max_value="$3"
    local h1 h2 i hash

    h1=$(prob_hash "$element")
    h2=$(prob_murmurhash "$element" 42)

    for ((i = 0; i < count; i++)); do
        hash=$(( (h1 + i * h2) % max_value ))
        printf '%u\n' "$hash"
    done
}

# Count leading zeros in a 32-bit number
# @pre: positive integer provided
# @post: count of leading zeros returned
# @idempotent: yes
# @returns: count (0-32)
_prob_clz32() {
    local n="$1"
    local count=0

    [[ $n -eq 0 ]] && { printf '32\n'; return; }

    while (( (n & 0x80000000) == 0 && count < 32 )); do
        ((n <<= 1))
        ((count++))
    done

    printf '%d\n' "$count"
}

# =============================================================================
# BLOOM FILTER
# =============================================================================
# A Bloom filter is a space-efficient probabilistic data structure that tests
# whether an element is a member of a set. False positives are possible, but
# false negatives are not.
# =============================================================================

# Global associative arrays for Bloom filter storage
declare -gA _PROB_BLOOM_FILTERS=()
declare -gA _PROB_BLOOM_METADATA=()

# Create a new Bloom filter
# @pre: name is non-empty, size > 0, hash_count > 0
# @post: empty Bloom filter created
# @idempotent: no (recreates filter)
# @returns: 0 on success, 1 on error
#
# Usage: bloom_create name [size] [hash_count]
# Example: bloom_create "my_filter" 10000 7
bloom_create() {
    local name="$1"
    local size="${2:-$PROB_BLOOM_DEFAULT_SIZE}"
    local hash_count="${3:-$PROB_BLOOM_DEFAULT_HASHES}"

    # Validate inputs
    if [[ -z "$name" ]]; then
        _prob_error 1 "filter name required"
        return 1
    fi

    if [[ ! "$size" =~ ^[0-9]+$ ]] || (( size <= 0 )); then
        _prob_error 1 "size must be positive integer" "size=$size"
        return 1
    fi

    if [[ ! "$hash_count" =~ ^[0-9]+$ ]] || (( hash_count <= 0 )); then
        _prob_error 1 "hash_count must be positive integer" "hash_count=$hash_count"
        return 1
    fi

    # Initialize bit array as hex string (4 bits per char)
    local hex_size=$(( (size + 3) / 4 ))
    local bits=""
    for ((i = 0; i < hex_size; i++)); do
        bits+="0"
    done

    _PROB_BLOOM_FILTERS["$name"]="$bits"
    _PROB_BLOOM_METADATA["${name}_size"]="$size"
    _PROB_BLOOM_METADATA["${name}_hashes"]="$hash_count"
    _PROB_BLOOM_METADATA["${name}_count"]="0"

    # USOP output
    printf '{"ok":true,"filter":"%s","size":%d,"hash_count":%d}\n' \
        "$(_prob_json_escape "$name")" "$size" "$hash_count"
}

# Set a bit in the bloom filter
# @pre: filter exists, bit_index valid
# @post: bit set to 1
_bloom_set_bit() {
    local name="$1"
    local bit_index="$2"
    local bits="${_PROB_BLOOM_FILTERS[$name]}"
    local hex_index=$(( bit_index / 4 ))
    local bit_offset=$(( bit_index % 4 ))

    # Get current hex digit
    local hex_char="${bits:hex_index:1}"
    local hex_val
    printf -v hex_val '%d' "0x$hex_char"

    # Set the bit
    local mask=$(( 1 << (3 - bit_offset) ))
    hex_val=$(( hex_val | mask ))

    # Convert back to hex
    local new_hex
    printf -v new_hex '%x' "$hex_val"

    # Update bits string
    _PROB_BLOOM_FILTERS["$name"]="${bits:0:hex_index}${new_hex}${bits:hex_index+1}"
}

# Get a bit from the bloom filter
# @pre: filter exists, bit_index valid
# @post: returns 0 if set, 1 if not set
_bloom_get_bit() {
    local name="$1"
    local bit_index="$2"
    local bits="${_PROB_BLOOM_FILTERS[$name]}"
    local hex_index=$(( bit_index / 4 ))
    local bit_offset=$(( bit_index % 4 ))

    # Get current hex digit
    local hex_char="${bits:hex_index:1}"
    local hex_val
    printf -v hex_val '%d' "0x$hex_char"

    # Check the bit
    local mask=$(( 1 << (3 - bit_offset) ))
    if (( (hex_val & mask) != 0 )); then
        return 0  # bit is set
    else
        return 1  # bit is not set
    fi
}

# Add element to Bloom filter
# @pre: filter exists, element is non-empty
# @post: element added to filter
# @idempotent: yes
# @returns: 0 on success, 1 on error
#
# Usage: bloom_add filter_name element
# Example: bloom_add "my_filter" "hello"
bloom_add() {
    local name="$1"
    local element="$2"

    if [[ -z "${_PROB_BLOOM_FILTERS[$name]+x}" ]]; then
        _prob_error 1 "filter not found" "filter=$name"
        return 1
    fi

    if [[ -z "$element" ]]; then
        _prob_error 1 "element required"
        return 1
    fi

    local size="${_PROB_BLOOM_METADATA[${name}_size]}"
    local hash_count="${_PROB_BLOOM_METADATA[${name}_hashes]}"

    # Generate hash values and set bits
    local hashes
    hashes=$(_prob_multi_hash "$element" "$hash_count" "$size")

    while IFS= read -r hash; do
        _bloom_set_bit "$name" "$hash"
    done <<< "$hashes"

    # Increment estimated count
    local count="${_PROB_BLOOM_METADATA[${name}_count]}"
    _PROB_BLOOM_METADATA["${name}_count"]=$((count + 1))

    printf '{"ok":true,"filter":"%s","element":"%s"}\n' \
        "$(_prob_json_escape "$name")" "$(_prob_json_escape "$element")"
}

# Check if element might be in Bloom filter
# @pre: filter exists, element is non-empty
# @post: returns JSON with "contains":true/false
# @idempotent: yes
# @returns: 0 on success (check "contains" field for result), 1 on error
#
# Usage: bloom_contains filter_name element
# Example: result=$(bloom_contains "my_filter" "hello")
#          [[ "$result" =~ \"contains\":true ]] && echo "probably present"
bloom_contains() {
    local name="$1"
    local element="$2"

    if [[ -z "${_PROB_BLOOM_FILTERS[$name]+x}" ]]; then
        _prob_error 1 "filter not found" "filter=$name"
        return 1
    fi

    if [[ -z "$element" ]]; then
        _prob_error 1 "element required"
        return 1
    fi

    local size="${_PROB_BLOOM_METADATA[${name}_size]}"
    local hash_count="${_PROB_BLOOM_METADATA[${name}_hashes]}"

    # Generate hash values and check bits
    local hashes
    hashes=$(_prob_multi_hash "$element" "$hash_count" "$size")

    while IFS= read -r hash; do
        if ! _bloom_get_bit "$name" "$hash"; then
            printf '{"ok":true,"filter":"%s","element":"%s","contains":false}\n' \
                "$(_prob_json_escape "$name")" "$(_prob_json_escape "$element")"
            return 0
        fi
    done <<< "$hashes"

    printf '{"ok":true,"filter":"%s","element":"%s","contains":true}\n' \
        "$(_prob_json_escape "$name")" "$(_prob_json_escape "$element")"
    return 0
}

# Clear all elements from Bloom filter
# @pre: filter exists
# @post: all bits set to 0
# @idempotent: yes
# @returns: 0 on success, 1 on error
#
# Usage: bloom_clear filter_name
# Example: bloom_clear "my_filter"
bloom_clear() {
    local name="$1"

    if [[ -z "${_PROB_BLOOM_FILTERS[$name]+x}" ]]; then
        _prob_error 1 "filter not found" "filter=$name"
        return 1
    fi

    local size="${_PROB_BLOOM_METADATA[${name}_size]}"
    local hex_size=$(( (size + 3) / 4 ))
    local bits=""

    for ((i = 0; i < hex_size; i++)); do
        bits+="0"
    done

    _PROB_BLOOM_FILTERS["$name"]="$bits"
    _PROB_BLOOM_METADATA["${name}_count"]="0"

    printf '{"ok":true,"filter":"%s","cleared":true}\n' "$(_prob_json_escape "$name")"
}

# Get Bloom filter size in bits
# @pre: filter exists
# @post: size returned
# @idempotent: yes
# @returns: size in bits
#
# Usage: bloom_size filter_name
# Example: size=$(bloom_size "my_filter")
bloom_size() {
    local name="$1"

    if [[ -z "${_PROB_BLOOM_FILTERS[$name]+x}" ]]; then
        _prob_error 1 "filter not found" "filter=$name"
        return 1
    fi

    local size="${_PROB_BLOOM_METADATA[${name}_size]}"
    printf '{"ok":true,"filter":"%s","size":%d}\n' "$(_prob_json_escape "$name")" "$size"
}

# Get estimated element count in Bloom filter
# @pre: filter exists
# @post: count returned
# @idempotent: yes
# @returns: estimated count
#
# Usage: bloom_count filter_name
# Example: count=$(bloom_count "my_filter")
bloom_count() {
    local name="$1"

    if [[ -z "${_PROB_BLOOM_FILTERS[$name]+x}" ]]; then
        _prob_error 1 "filter not found" "filter=$name"
        return 1
    fi

    local count="${_PROB_BLOOM_METADATA[${name}_count]}"
    printf '{"ok":true,"filter":"%s","count":%d}\n' "$(_prob_json_escape "$name")" "$count"
}

# Calculate false positive rate for Bloom filter
# @pre: filter exists
# @post: estimated FP rate returned
# @idempotent: yes
# @returns: false positive rate (0-1)
#
# Usage: bloom_false_positive_rate filter_name
# Example: rate=$(bloom_false_positive_rate "my_filter")
bloom_false_positive_rate() {
    local name="$1"

    if [[ -z "${_PROB_BLOOM_FILTERS[$name]+x}" ]]; then
        _prob_error 1 "filter not found" "filter=$name"
        return 1
    fi

    local size="${_PROB_BLOOM_METADATA[${name}_size]}"
    local hashes="${_PROB_BLOOM_METADATA[${name}_hashes]}"
    local count="${_PROB_BLOOM_METADATA[${name}_count]}"

    # FP rate = (1 - e^(-kn/m))^k
    # Approximate using: (1 - (1 - 1/m)^(kn))^k
    # For bash, we'll use a simpler approximation

    if (( count == 0 )); then
        printf '{"ok":true,"filter":"%s","fp_rate":0.0}\n' "$(_prob_json_escape "$name")"
        return 0
    fi

    # Calculate bits set (approximate)
    local expected_bits_set
    # p = 1 - (1 - 1/m)^(kn) ~ 1 - e^(-kn/m)
    # For integers: p ~ kn/m (for small values)
    local kn=$(( hashes * count ))
    local bits_ratio_x1000=$(( (kn * 1000) / size ))

    # Clamp to reasonable range
    (( bits_ratio_x1000 > 999 )) && bits_ratio_x1000=999

    # FP rate ~ (bits_ratio)^k
    local fp_x1000000=1000000
    for ((i = 0; i < hashes; i++)); do
        fp_x1000000=$(( (fp_x1000000 * bits_ratio_x1000) / 1000 ))
    done

    # Convert to decimal string
    local fp_int=$(( fp_x1000000 / 10000 ))
    local fp_frac=$(( fp_x1000000 % 10000 ))
    printf '{"ok":true,"filter":"%s","fp_rate":0.%04d%02d}\n' \
        "$(_prob_json_escape "$name")" "$fp_int" "$((fp_frac / 100))"
}

# Union two Bloom filters
# @pre: both filters exist with same size and hash count
# @post: new filter created with union
# @idempotent: no (creates new filter)
# @returns: 0 on success, 1 on error
#
# Usage: bloom_union result_name filter1 filter2
# Example: bloom_union "combined" "filter_a" "filter_b"
bloom_union() {
    local result_name="$1"
    local name1="$2"
    local name2="$3"

    if [[ -z "${_PROB_BLOOM_FILTERS[$name1]+x}" ]]; then
        _prob_error 1 "filter not found" "filter=$name1"
        return 1
    fi

    if [[ -z "${_PROB_BLOOM_FILTERS[$name2]+x}" ]]; then
        _prob_error 1 "filter not found" "filter=$name2"
        return 1
    fi

    local size1="${_PROB_BLOOM_METADATA[${name1}_size]}"
    local size2="${_PROB_BLOOM_METADATA[${name2}_size]}"
    local hashes1="${_PROB_BLOOM_METADATA[${name1}_hashes]}"
    local hashes2="${_PROB_BLOOM_METADATA[${name2}_hashes]}"

    if (( size1 != size2 || hashes1 != hashes2 )); then
        _prob_error 1 "filters must have same size and hash count" \
            "size1=$size1" "size2=$size2" "hashes1=$hashes1" "hashes2=$hashes2"
        return 1
    fi

    local bits1="${_PROB_BLOOM_FILTERS[$name1]}"
    local bits2="${_PROB_BLOOM_FILTERS[$name2]}"
    local result_bits=""
    local hex1 hex2 hex_or

    for ((i = 0; i < ${#bits1}; i++)); do
        printf -v hex1 '%d' "0x${bits1:i:1}"
        printf -v hex2 '%d' "0x${bits2:i:1}"
        hex_or=$(( hex1 | hex2 ))
        printf -v result_bits '%s%x' "$result_bits" "$hex_or"
    done

    _PROB_BLOOM_FILTERS["$result_name"]="$result_bits"
    _PROB_BLOOM_METADATA["${result_name}_size"]="$size1"
    _PROB_BLOOM_METADATA["${result_name}_hashes"]="$hashes1"

    local count1="${_PROB_BLOOM_METADATA[${name1}_count]}"
    local count2="${_PROB_BLOOM_METADATA[${name2}_count]}"
    _PROB_BLOOM_METADATA["${result_name}_count"]=$(( count1 + count2 ))

    printf '{"ok":true,"filter":"%s","operation":"union","source1":"%s","source2":"%s"}\n' \
        "$(_prob_json_escape "$result_name")" "$(_prob_json_escape "$name1")" "$(_prob_json_escape "$name2")"
}

# Intersect two Bloom filters
# @pre: both filters exist with same size and hash count
# @post: new filter created with intersection
# @idempotent: no (creates new filter)
# @returns: 0 on success, 1 on error
#
# Usage: bloom_intersect result_name filter1 filter2
# Example: bloom_intersect "common" "filter_a" "filter_b"
bloom_intersect() {
    local result_name="$1"
    local name1="$2"
    local name2="$3"

    if [[ -z "${_PROB_BLOOM_FILTERS[$name1]+x}" ]]; then
        _prob_error 1 "filter not found" "filter=$name1"
        return 1
    fi

    if [[ -z "${_PROB_BLOOM_FILTERS[$name2]+x}" ]]; then
        _prob_error 1 "filter not found" "filter=$name2"
        return 1
    fi

    local size1="${_PROB_BLOOM_METADATA[${name1}_size]}"
    local size2="${_PROB_BLOOM_METADATA[${name2}_size]}"
    local hashes1="${_PROB_BLOOM_METADATA[${name1}_hashes]}"
    local hashes2="${_PROB_BLOOM_METADATA[${name2}_hashes]}"

    if (( size1 != size2 || hashes1 != hashes2 )); then
        _prob_error 1 "filters must have same size and hash count" \
            "size1=$size1" "size2=$size2" "hashes1=$hashes1" "hashes2=$hashes2"
        return 1
    fi

    local bits1="${_PROB_BLOOM_FILTERS[$name1]}"
    local bits2="${_PROB_BLOOM_FILTERS[$name2]}"
    local result_bits=""
    local hex1 hex2 hex_and

    for ((i = 0; i < ${#bits1}; i++)); do
        printf -v hex1 '%d' "0x${bits1:i:1}"
        printf -v hex2 '%d' "0x${bits2:i:1}"
        hex_and=$(( hex1 & hex2 ))
        printf -v result_bits '%s%x' "$result_bits" "$hex_and"
    done

    _PROB_BLOOM_FILTERS["$result_name"]="$result_bits"
    _PROB_BLOOM_METADATA["${result_name}_size"]="$size1"
    _PROB_BLOOM_METADATA["${result_name}_hashes"]="$hashes1"
    _PROB_BLOOM_METADATA["${result_name}_count"]="0"  # Unknown after intersection

    printf '{"ok":true,"filter":"%s","operation":"intersect","source1":"%s","source2":"%s"}\n' \
        "$(_prob_json_escape "$result_name")" "$(_prob_json_escape "$name1")" "$(_prob_json_escape "$name2")"
}

# Serialize Bloom filter to JSON
# @pre: filter exists
# @post: JSON representation returned
# @idempotent: yes
# @returns: JSON string
#
# Usage: bloom_to_json filter_name
# Example: json=$(bloom_to_json "my_filter")
bloom_to_json() {
    local name="$1"

    if [[ -z "${_PROB_BLOOM_FILTERS[$name]+x}" ]]; then
        _prob_error 1 "filter not found" "filter=$name"
        return 1
    fi

    local bits="${_PROB_BLOOM_FILTERS[$name]}"
    local size="${_PROB_BLOOM_METADATA[${name}_size]}"
    local hashes="${_PROB_BLOOM_METADATA[${name}_hashes]}"
    local count="${_PROB_BLOOM_METADATA[${name}_count]}"

    printf '{"type":"bloom","name":"%s","size":%d,"hash_count":%d,"count":%d,"bits":"%s"}\n' \
        "$(_prob_json_escape "$name")" "$size" "$hashes" "$count" "$bits"
}

# Deserialize Bloom filter from JSON
# @pre: valid JSON with bloom filter data
# @post: filter recreated
# @idempotent: no (overwrites existing filter)
# @returns: 0 on success, 1 on error
#
# Usage: bloom_from_json json_string
# Example: bloom_from_json '{"type":"bloom","name":"test",...}'
bloom_from_json() {
    local json="$1"

    # Extract fields using regex (simple parsing)
    local name size hashes count bits

    if [[ "$json" =~ \"name\":\"([^\"]+)\" ]]; then
        name="${BASH_REMATCH[1]}"
    else
        _prob_error 1 "missing name in JSON"
        return 1
    fi

    if [[ "$json" =~ \"size\":([0-9]+) ]]; then
        size="${BASH_REMATCH[1]}"
    else
        _prob_error 1 "missing size in JSON"
        return 1
    fi

    if [[ "$json" =~ \"hash_count\":([0-9]+) ]]; then
        hashes="${BASH_REMATCH[1]}"
    else
        _prob_error 1 "missing hash_count in JSON"
        return 1
    fi

    if [[ "$json" =~ \"count\":([0-9]+) ]]; then
        count="${BASH_REMATCH[1]}"
    else
        count=0
    fi

    if [[ "$json" =~ \"bits\":\"([0-9a-fA-F]+)\" ]]; then
        bits="${BASH_REMATCH[1]}"
    else
        _prob_error 1 "missing bits in JSON"
        return 1
    fi

    _PROB_BLOOM_FILTERS["$name"]="$bits"
    _PROB_BLOOM_METADATA["${name}_size"]="$size"
    _PROB_BLOOM_METADATA["${name}_hashes"]="$hashes"
    _PROB_BLOOM_METADATA["${name}_count"]="$count"

    printf '{"ok":true,"filter":"%s","loaded":true}\n' "$(_prob_json_escape "$name")"
}

# =============================================================================
# COUNTING BLOOM FILTER
# =============================================================================
# A Counting Bloom filter extends the standard Bloom filter by using counters
# instead of bits, allowing for element removal.
# =============================================================================

declare -gA _PROB_CBLOOM_FILTERS=()
declare -gA _PROB_CBLOOM_METADATA=()

# Create a new Counting Bloom filter
# @pre: name is non-empty, size > 0, hash_count > 0
# @post: empty counting Bloom filter created
# @idempotent: no (recreates filter)
# @returns: 0 on success, 1 on error
#
# Usage: cbloom_create name [size] [hash_count]
# Example: cbloom_create "my_cfilter" 1000 5
cbloom_create() {
    local name="$1"
    local size="${2:-$PROB_BLOOM_DEFAULT_SIZE}"
    local hash_count="${3:-$PROB_BLOOM_DEFAULT_HASHES}"

    if [[ -z "$name" ]]; then
        _prob_error 1 "filter name required"
        return 1
    fi

    if [[ ! "$size" =~ ^[0-9]+$ ]] || (( size <= 0 )); then
        _prob_error 1 "size must be positive integer" "size=$size"
        return 1
    fi

    if [[ ! "$hash_count" =~ ^[0-9]+$ ]] || (( hash_count <= 0 )); then
        _prob_error 1 "hash_count must be positive integer" "hash_count=$hash_count"
        return 1
    fi

    # Initialize counters array (space-separated zeros)
    local counters=""
    for ((i = 0; i < size; i++)); do
        counters+="0 "
    done
    counters="${counters% }"  # Remove trailing space

    _PROB_CBLOOM_FILTERS["$name"]="$counters"
    _PROB_CBLOOM_METADATA["${name}_size"]="$size"
    _PROB_CBLOOM_METADATA["${name}_hashes"]="$hash_count"
    _PROB_CBLOOM_METADATA["${name}_count"]="0"

    printf '{"ok":true,"filter":"%s","type":"counting_bloom","size":%d,"hash_count":%d}\n' \
        "$(_prob_json_escape "$name")" "$size" "$hash_count"
}

# Add element to Counting Bloom filter
# @pre: filter exists, element is non-empty
# @post: counters incremented
# @idempotent: no (increments counters)
# @returns: 0 on success, 1 on error
#
# Usage: cbloom_add filter_name element
# Example: cbloom_add "my_cfilter" "hello"
cbloom_add() {
    local name="$1"
    local element="$2"

    if [[ -z "${_PROB_CBLOOM_FILTERS[$name]+x}" ]]; then
        _prob_error 1 "filter not found" "filter=$name"
        return 1
    fi

    if [[ -z "$element" ]]; then
        _prob_error 1 "element required"
        return 1
    fi

    local size="${_PROB_CBLOOM_METADATA[${name}_size]}"
    local hash_count="${_PROB_CBLOOM_METADATA[${name}_hashes]}"
    local counters
    read -ra counters <<< "${_PROB_CBLOOM_FILTERS[$name]}"

    # Generate hash values and increment counters
    local hashes
    hashes=$(_prob_multi_hash "$element" "$hash_count" "$size")

    while IFS= read -r hash; do
        (( counters[hash] = counters[hash] + 1 ))
    done <<< "$hashes"

    _PROB_CBLOOM_FILTERS["$name"]="${counters[*]}"

    local count="${_PROB_CBLOOM_METADATA[${name}_count]}"
    _PROB_CBLOOM_METADATA["${name}_count"]=$((count + 1))

    printf '{"ok":true,"filter":"%s","element":"%s","added":true}\n' \
        "$(_prob_json_escape "$name")" "$(_prob_json_escape "$element")"
}

# Remove element from Counting Bloom filter
# @pre: filter exists, element is non-empty
# @post: counters decremented (minimum 0)
# @idempotent: no (decrements counters)
# @returns: 0 on success, 1 on error
#
# Usage: cbloom_remove filter_name element
# Example: cbloom_remove "my_cfilter" "hello"
cbloom_remove() {
    local name="$1"
    local element="$2"

    if [[ -z "${_PROB_CBLOOM_FILTERS[$name]+x}" ]]; then
        _prob_error 1 "filter not found" "filter=$name"
        return 1
    fi

    if [[ -z "$element" ]]; then
        _prob_error 1 "element required"
        return 1
    fi

    local size="${_PROB_CBLOOM_METADATA[${name}_size]}"
    local hash_count="${_PROB_CBLOOM_METADATA[${name}_hashes]}"
    local counters
    read -ra counters <<< "${_PROB_CBLOOM_FILTERS[$name]}"

    # Generate hash values and decrement counters
    local hashes
    hashes=$(_prob_multi_hash "$element" "$hash_count" "$size")

    while IFS= read -r hash; do
        if (( counters[hash] > 0 )); then
            counters[hash]=$((counters[hash] - 1))
        fi
    done <<< "$hashes"

    _PROB_CBLOOM_FILTERS["$name"]="${counters[*]}"

    local count="${_PROB_CBLOOM_METADATA[${name}_count]}"
    if (( count > 0 )); then
        _PROB_CBLOOM_METADATA["${name}_count"]=$((count - 1))
    fi

    printf '{"ok":true,"filter":"%s","element":"%s","removed":true}\n' \
        "$(_prob_json_escape "$name")" "$(_prob_json_escape "$element")"
}

# Check if element might be in Counting Bloom filter
# @pre: filter exists, element is non-empty
# @post: returns JSON with "contains":true/false
# @idempotent: yes
# @returns: 0 on success (check "contains" field for result), 1 on error
#
# Usage: cbloom_contains filter_name element
# Example: result=$(cbloom_contains "my_cfilter" "hello")
#          [[ "$result" =~ \"contains\":true ]] && echo "probably present"
cbloom_contains() {
    local name="$1"
    local element="$2"

    if [[ -z "${_PROB_CBLOOM_FILTERS[$name]+x}" ]]; then
        _prob_error 1 "filter not found" "filter=$name"
        return 1
    fi

    if [[ -z "$element" ]]; then
        _prob_error 1 "element required"
        return 1
    fi

    local size="${_PROB_CBLOOM_METADATA[${name}_size]}"
    local hash_count="${_PROB_CBLOOM_METADATA[${name}_hashes]}"
    local counters
    read -ra counters <<< "${_PROB_CBLOOM_FILTERS[$name]}"

    # Generate hash values and check counters
    local hashes
    hashes=$(_prob_multi_hash "$element" "$hash_count" "$size")

    while IFS= read -r hash; do
        if (( counters[hash] == 0 )); then
            printf '{"ok":true,"filter":"%s","element":"%s","contains":false}\n' \
                "$(_prob_json_escape "$name")" "$(_prob_json_escape "$element")"
            return 0
        fi
    done <<< "$hashes"

    printf '{"ok":true,"filter":"%s","element":"%s","contains":true}\n' \
        "$(_prob_json_escape "$name")" "$(_prob_json_escape "$element")"
    return 0
}

# Estimate frequency of element in Counting Bloom filter
# @pre: filter exists, element is non-empty
# @post: minimum counter value returned
# @idempotent: yes
# @returns: estimated count
#
# Usage: cbloom_count_estimate filter_name element
# Example: count=$(cbloom_count_estimate "my_cfilter" "hello")
cbloom_count_estimate() {
    local name="$1"
    local element="$2"

    if [[ -z "${_PROB_CBLOOM_FILTERS[$name]+x}" ]]; then
        _prob_error 1 "filter not found" "filter=$name"
        return 1
    fi

    if [[ -z "$element" ]]; then
        _prob_error 1 "element required"
        return 1
    fi

    local size="${_PROB_CBLOOM_METADATA[${name}_size]}"
    local hash_count="${_PROB_CBLOOM_METADATA[${name}_hashes]}"
    local counters
    read -ra counters <<< "${_PROB_CBLOOM_FILTERS[$name]}"

    # Generate hash values and find minimum counter
    local hashes min_count=-1
    hashes=$(_prob_multi_hash "$element" "$hash_count" "$size")

    while IFS= read -r hash; do
        local count="${counters[hash]}"
        if (( min_count < 0 || count < min_count )); then
            min_count=$count
        fi
    done <<< "$hashes"

    printf '{"ok":true,"filter":"%s","element":"%s","estimated_count":%d}\n' \
        "$(_prob_json_escape "$name")" "$(_prob_json_escape "$element")" "$min_count"
}

# =============================================================================
# HYPERLOGLOG
# =============================================================================
# HyperLogLog is a probabilistic data structure for estimating the cardinality
# (count of distinct elements) of a multiset. Uses O(m) space where m is the
# number of registers (typically 2^14 = 16384).
# =============================================================================

declare -gA _PROB_HLL_REGISTERS=()
declare -gA _PROB_HLL_METADATA=()

# Precomputed alpha constants for HLL bias correction
_prob_hll_alpha() {
    local m="$1"
    case $m in
        16)   printf '0.673' ;;
        32)   printf '0.697' ;;
        64)   printf '0.709' ;;
        *)    printf '0.7213' ;;  # For m >= 128: 0.7213/(1 + 1.079/m)
    esac
}

# Create a new HyperLogLog counter
# @pre: name is non-empty, precision in range 4-18
# @post: empty HLL counter created with 2^precision registers
# @idempotent: no (recreates counter)
# @returns: 0 on success, 1 on error
#
# Usage: hll_create name [precision]
# Example: hll_create "unique_users" 14
hll_create() {
    local name="$1"
    local precision="${2:-$PROB_HLL_DEFAULT_PRECISION}"

    if [[ -z "$name" ]]; then
        _prob_error 1 "counter name required"
        return 1
    fi

    if [[ ! "$precision" =~ ^[0-9]+$ ]] || (( precision < 4 || precision > 18 )); then
        _prob_error 1 "precision must be between 4 and 18" "precision=$precision"
        return 1
    fi

    local m=$(( 1 << precision ))

    # Initialize registers to 0 (space-separated)
    local registers=""
    for ((i = 0; i < m; i++)); do
        registers+="0 "
    done
    registers="${registers% }"

    _PROB_HLL_REGISTERS["$name"]="$registers"
    _PROB_HLL_METADATA["${name}_precision"]="$precision"
    _PROB_HLL_METADATA["${name}_m"]="$m"

    printf '{"ok":true,"counter":"%s","type":"hyperloglog","precision":%d,"registers":%d}\n' \
        "$(_prob_json_escape "$name")" "$precision" "$m"
}

# Add element to HyperLogLog counter
# @pre: counter exists, element is non-empty
# @post: register updated if new leading zero count is higher
# @idempotent: yes
# @returns: 0 on success, 1 on error
#
# Usage: hll_add counter_name element
# Example: hll_add "unique_users" "user123"
hll_add() {
    local name="$1"
    local element="$2"

    if [[ -z "${_PROB_HLL_REGISTERS[$name]+x}" ]]; then
        _prob_error 1 "counter not found" "counter=$name"
        return 1
    fi

    if [[ -z "$element" ]]; then
        _prob_error 1 "element required"
        return 1
    fi

    local precision="${_PROB_HLL_METADATA[${name}_precision]}"
    local m="${_PROB_HLL_METADATA[${name}_m]}"
    local registers
    read -ra registers <<< "${_PROB_HLL_REGISTERS[$name]}"

    # Hash the element
    local hash
    hash=$(prob_murmurhash "$element" 0)

    # Use first p bits for register index
    local index=$(( hash & (m - 1) ))

    # Use remaining bits for counting leading zeros
    local w=$(( hash >> precision ))
    local leading_zeros
    leading_zeros=$(_prob_clz32 "$w")

    # Update register with max(current, leading_zeros + 1)
    local rho=$(( leading_zeros + 1 ))
    if (( rho > registers[index] )); then
        registers[index]=$rho
    fi

    _PROB_HLL_REGISTERS["$name"]="${registers[*]}"

    printf '{"ok":true,"counter":"%s","element":"%s","added":true}\n' \
        "$(_prob_json_escape "$name")" "$(_prob_json_escape "$element")"
}

# Estimate cardinality from HyperLogLog counter
# @pre: counter exists
# @post: estimated unique count returned
# @idempotent: yes
# @returns: estimated cardinality
#
# Usage: hll_count counter_name
# Example: estimate=$(hll_count "unique_users")
hll_count() {
    local name="$1"

    if [[ -z "${_PROB_HLL_REGISTERS[$name]+x}" ]]; then
        _prob_error 1 "counter not found" "counter=$name"
        return 1
    fi

    local m="${_PROB_HLL_METADATA[${name}_m]}"
    local registers
    read -ra registers <<< "${_PROB_HLL_REGISTERS[$name]}"

    # Calculate harmonic mean of 2^(-register) values
    # E = alpha * m^2 / sum(2^(-M[j]))
    # Using integer arithmetic with high precision scaling (10^9)

    local sum_inv=0
    local zeros=0
    local scale=1000000000  # 10^9 for precision

    for ((j = 0; j < m; j++)); do
        local reg="${registers[j]}"
        if (( reg == 0 )); then
            (( zeros = zeros + 1 ))
            # 2^0 = 1, so add scale
            (( sum_inv = sum_inv + scale ))
        else
            # 2^(-reg) scaled by scale
            # For reg >= 30, this becomes 0, which is fine
            if (( reg < 30 )); then
                local inv=$(( scale >> reg ))
                (( sum_inv = sum_inv + inv ))
            fi
            # For reg >= 30, contribution is negligible (< 1)
        fi
    done

    # Avoid division by zero
    if (( sum_inv == 0 )); then
        sum_inv=1
    fi

    # alpha varies by m (using higher precision: x10000)
    local alpha_x10000
    case $m in
        16)   alpha_x10000=6730 ;;
        32)   alpha_x10000=6970 ;;
        64)   alpha_x10000=7090 ;;
        *)    alpha_x10000=7213 ;;  # 0.7213 for large m
    esac

    # Raw estimate: E = alpha * m^2 / sum
    # E = (alpha_x10000 / 10000) * m * m / (sum_inv / scale)
    # E = (alpha_x10000 * m * m * scale) / (sum_inv * 10000)
    local estimate=$(( (alpha_x10000 * m / 10000) * (m * scale / sum_inv) ))

    # Apply small range correction (linear counting) if zeros > 0 and estimate is small
    if (( zeros > 0 && estimate <= (5 * m / 2) )); then
        # Linear counting: E* = m * ln(m / zeros)
        # Using logarithm approximation: ln(x) via repeated halving
        local ratio=$(( m * 1000 / zeros ))  # ratio * 1000

        if (( ratio > 1000 )); then
            # Calculate ln(ratio/1000) * 1000 = ln(m/zeros) * 1000
            local ln_val=0
            local x=$ratio

            # Use ln(x) = ln(x/2) + ln(2) repeatedly
            while (( x > 2000 )); do
                (( ln_val = ln_val + 693 ))  # ln(2) * 1000 ~ 693
                (( x = x / 2 ))
            done

            # For x in [1000, 2000], use ln(1+y) ~ y - y^2/2 where y = (x-1000)/1000
            if (( x > 1000 )); then
                local y=$(( x - 1000 ))  # y is in [0, 1000] representing [0, 1]
                local ln_part=$(( y - (y * y / 2000) ))
                (( ln_val = ln_val + ln_part ))
            fi

            estimate=$(( (m * ln_val) / 1000 ))
        fi
    fi

    printf '{"ok":true,"counter":"%s","estimate":%d}\n' \
        "$(_prob_json_escape "$name")" "$estimate"
}

# Merge two HyperLogLog counters
# @pre: both counters exist with same precision
# @post: new counter created with merged registers
# @idempotent: no (creates new counter)
# @returns: 0 on success, 1 on error
#
# Usage: hll_merge result_name counter1 counter2
# Example: hll_merge "combined" "counter_a" "counter_b"
hll_merge() {
    local result_name="$1"
    local name1="$2"
    local name2="$3"

    if [[ -z "${_PROB_HLL_REGISTERS[$name1]+x}" ]]; then
        _prob_error 1 "counter not found" "counter=$name1"
        return 1
    fi

    if [[ -z "${_PROB_HLL_REGISTERS[$name2]+x}" ]]; then
        _prob_error 1 "counter not found" "counter=$name2"
        return 1
    fi

    local p1="${_PROB_HLL_METADATA[${name1}_precision]}"
    local p2="${_PROB_HLL_METADATA[${name2}_precision]}"

    if (( p1 != p2 )); then
        _prob_error 1 "counters must have same precision" "p1=$p1" "p2=$p2"
        return 1
    fi

    local m="${_PROB_HLL_METADATA[${name1}_m]}"
    local registers1 registers2
    read -ra registers1 <<< "${_PROB_HLL_REGISTERS[$name1]}"
    read -ra registers2 <<< "${_PROB_HLL_REGISTERS[$name2]}"

    # Merge by taking max of each register
    local result_registers=""
    for ((j = 0; j < m; j++)); do
        local r1="${registers1[j]}"
        local r2="${registers2[j]}"
        if (( r1 > r2 )); then
            result_registers+="$r1 "
        else
            result_registers+="$r2 "
        fi
    done
    result_registers="${result_registers% }"

    _PROB_HLL_REGISTERS["$result_name"]="$result_registers"
    _PROB_HLL_METADATA["${result_name}_precision"]="$p1"
    _PROB_HLL_METADATA["${result_name}_m"]="$m"

    printf '{"ok":true,"counter":"%s","operation":"merge","source1":"%s","source2":"%s"}\n' \
        "$(_prob_json_escape "$result_name")" "$(_prob_json_escape "$name1")" "$(_prob_json_escape "$name2")"
}

# Clear HyperLogLog counter
# @pre: counter exists
# @post: all registers reset to 0
# @idempotent: yes
# @returns: 0 on success, 1 on error
#
# Usage: hll_clear counter_name
# Example: hll_clear "unique_users"
hll_clear() {
    local name="$1"

    if [[ -z "${_PROB_HLL_REGISTERS[$name]+x}" ]]; then
        _prob_error 1 "counter not found" "counter=$name"
        return 1
    fi

    local m="${_PROB_HLL_METADATA[${name}_m]}"
    local registers=""

    for ((i = 0; i < m; i++)); do
        registers+="0 "
    done
    registers="${registers% }"

    _PROB_HLL_REGISTERS["$name"]="$registers"

    printf '{"ok":true,"counter":"%s","cleared":true}\n' "$(_prob_json_escape "$name")"
}

# Serialize HyperLogLog to JSON
# @pre: counter exists
# @post: JSON representation returned
# @idempotent: yes
# @returns: JSON string
#
# Usage: hll_to_json counter_name
# Example: json=$(hll_to_json "unique_users")
hll_to_json() {
    local name="$1"

    if [[ -z "${_PROB_HLL_REGISTERS[$name]+x}" ]]; then
        _prob_error 1 "counter not found" "counter=$name"
        return 1
    fi

    local precision="${_PROB_HLL_METADATA[${name}_precision]}"
    local m="${_PROB_HLL_METADATA[${name}_m]}"
    local registers="${_PROB_HLL_REGISTERS[$name]}"

    # Convert registers to JSON array
    local regs_json="["
    local first=true
    for reg in $registers; do
        $first || regs_json+=","
        first=false
        regs_json+="$reg"
    done
    regs_json+="]"

    printf '{"type":"hyperloglog","name":"%s","precision":%d,"m":%d,"registers":%s}\n' \
        "$(_prob_json_escape "$name")" "$precision" "$m" "$regs_json"
}

# Deserialize HyperLogLog from JSON
# @pre: valid JSON with HLL data
# @post: counter recreated
# @idempotent: no (overwrites existing counter)
# @returns: 0 on success, 1 on error
#
# Usage: hll_from_json json_string
# Example: hll_from_json '{"type":"hyperloglog",...}'
hll_from_json() {
    local json="$1"
    local name precision m

    if [[ "$json" =~ \"name\":\"([^\"]+)\" ]]; then
        name="${BASH_REMATCH[1]}"
    else
        _prob_error 1 "missing name in JSON"
        return 1
    fi

    if [[ "$json" =~ \"precision\":([0-9]+) ]]; then
        precision="${BASH_REMATCH[1]}"
    else
        _prob_error 1 "missing precision in JSON"
        return 1
    fi

    if [[ "$json" =~ \"m\":([0-9]+) ]]; then
        m="${BASH_REMATCH[1]}"
    else
        m=$(( 1 << precision ))
    fi

    # Extract registers array
    local registers=""
    if [[ "$json" =~ \"registers\":\[([0-9,]+)\] ]]; then
        registers="${BASH_REMATCH[1]//,/ }"
    else
        _prob_error 1 "missing registers in JSON"
        return 1
    fi

    _PROB_HLL_REGISTERS["$name"]="$registers"
    _PROB_HLL_METADATA["${name}_precision"]="$precision"
    _PROB_HLL_METADATA["${name}_m"]="$m"

    printf '{"ok":true,"counter":"%s","loaded":true}\n' "$(_prob_json_escape "$name")"
}

# =============================================================================
# COUNT-MIN SKETCH
# =============================================================================
# Count-Min Sketch is a probabilistic data structure for frequency estimation.
# It uses a 2D array of counters with multiple hash functions to provide
# estimates with one-sided error (always overestimates).
# =============================================================================

declare -gA _PROB_CMS_COUNTERS=()
declare -gA _PROB_CMS_METADATA=()

# Create a new Count-Min Sketch
# @pre: name is non-empty, width > 0, depth > 0
# @post: empty CMS created
# @idempotent: no (recreates sketch)
# @returns: 0 on success, 1 on error
#
# Usage: cms_create name [width] [depth]
# Example: cms_create "frequency" 1024 5
cms_create() {
    local name="$1"
    local width="${2:-$PROB_CMS_DEFAULT_WIDTH}"
    local depth="${3:-$PROB_CMS_DEFAULT_DEPTH}"

    if [[ -z "$name" ]]; then
        _prob_error 1 "sketch name required"
        return 1
    fi

    if [[ ! "$width" =~ ^[0-9]+$ ]] || (( width <= 0 )); then
        _prob_error 1 "width must be positive integer" "width=$width"
        return 1
    fi

    if [[ ! "$depth" =~ ^[0-9]+$ ]] || (( depth <= 0 )); then
        _prob_error 1 "depth must be positive integer" "depth=$depth"
        return 1
    fi

    # Initialize counters (depth rows, width columns)
    local counters=""
    local total=$(( width * depth ))
    for ((i = 0; i < total; i++)); do
        counters+="0 "
    done
    counters="${counters% }"

    _PROB_CMS_COUNTERS["$name"]="$counters"
    _PROB_CMS_METADATA["${name}_width"]="$width"
    _PROB_CMS_METADATA["${name}_depth"]="$depth"

    printf '{"ok":true,"sketch":"%s","type":"count_min_sketch","width":%d,"depth":%d}\n' \
        "$(_prob_json_escape "$name")" "$width" "$depth"
}

# Update Count-Min Sketch with element and count
# @pre: sketch exists, element is non-empty, delta is integer
# @post: counters updated
# @idempotent: no (adds to counters)
# @returns: 0 on success, 1 on error
#
# Usage: cms_update sketch_name element [delta]
# Example: cms_update "frequency" "item1" 1
cms_update() {
    local name="$1"
    local element="$2"
    local delta="${3:-1}"

    if [[ -z "${_PROB_CMS_COUNTERS[$name]+x}" ]]; then
        _prob_error 1 "sketch not found" "sketch=$name"
        return 1
    fi

    if [[ -z "$element" ]]; then
        _prob_error 1 "element required"
        return 1
    fi

    local width="${_PROB_CMS_METADATA[${name}_width]}"
    local depth="${_PROB_CMS_METADATA[${name}_depth]}"
    local counters
    read -ra counters <<< "${_PROB_CMS_COUNTERS[$name]}"

    # Update each row with different hash
    for ((d = 0; d < depth; d++)); do
        local hash
        hash=$(prob_murmurhash "$element" "$d")
        local col=$(( hash % width ))
        local idx=$(( d * width + col ))
        (( counters[idx] += delta ))
    done

    _PROB_CMS_COUNTERS["$name"]="${counters[*]}"

    printf '{"ok":true,"sketch":"%s","element":"%s","delta":%d}\n' \
        "$(_prob_json_escape "$name")" "$(_prob_json_escape "$element")" "$delta"
}

# Query element frequency from Count-Min Sketch
# @pre: sketch exists, element is non-empty
# @post: minimum counter value returned (conservative estimate)
# @idempotent: yes
# @returns: estimated frequency
#
# Usage: cms_query sketch_name element
# Example: freq=$(cms_query "frequency" "item1")
cms_query() {
    local name="$1"
    local element="$2"

    if [[ -z "${_PROB_CMS_COUNTERS[$name]+x}" ]]; then
        _prob_error 1 "sketch not found" "sketch=$name"
        return 1
    fi

    if [[ -z "$element" ]]; then
        _prob_error 1 "element required"
        return 1
    fi

    local width="${_PROB_CMS_METADATA[${name}_width]}"
    local depth="${_PROB_CMS_METADATA[${name}_depth]}"
    local counters
    read -ra counters <<< "${_PROB_CMS_COUNTERS[$name]}"

    # Query each row and take minimum
    local min_count=-1

    for ((d = 0; d < depth; d++)); do
        local hash
        hash=$(prob_murmurhash "$element" "$d")
        local col=$(( hash % width ))
        local idx=$(( d * width + col ))
        local count="${counters[idx]}"

        if (( min_count < 0 || count < min_count )); then
            min_count=$count
        fi
    done

    printf '{"ok":true,"sketch":"%s","element":"%s","frequency":%d}\n' \
        "$(_prob_json_escape "$name")" "$(_prob_json_escape "$element")" "$min_count"
}

# Merge two Count-Min Sketches
# @pre: both sketches exist with same dimensions
# @post: new sketch created with merged counters
# @idempotent: no (creates new sketch)
# @returns: 0 on success, 1 on error
#
# Usage: cms_merge result_name sketch1 sketch2
# Example: cms_merge "combined" "sketch_a" "sketch_b"
cms_merge() {
    local result_name="$1"
    local name1="$2"
    local name2="$3"

    if [[ -z "${_PROB_CMS_COUNTERS[$name1]+x}" ]]; then
        _prob_error 1 "sketch not found" "sketch=$name1"
        return 1
    fi

    if [[ -z "${_PROB_CMS_COUNTERS[$name2]+x}" ]]; then
        _prob_error 1 "sketch not found" "sketch=$name2"
        return 1
    fi

    local w1="${_PROB_CMS_METADATA[${name1}_width]}"
    local w2="${_PROB_CMS_METADATA[${name2}_width]}"
    local d1="${_PROB_CMS_METADATA[${name1}_depth]}"
    local d2="${_PROB_CMS_METADATA[${name2}_depth]}"

    if (( w1 != w2 || d1 != d2 )); then
        _prob_error 1 "sketches must have same dimensions" \
            "w1=$w1" "w2=$w2" "d1=$d1" "d2=$d2"
        return 1
    fi

    local counters1 counters2
    read -ra counters1 <<< "${_PROB_CMS_COUNTERS[$name1]}"
    read -ra counters2 <<< "${_PROB_CMS_COUNTERS[$name2]}"

    # Sum counters
    local result_counters=""
    local total=$(( w1 * d1 ))
    for ((i = 0; i < total; i++)); do
        local sum=$(( counters1[i] + counters2[i] ))
        result_counters+="$sum "
    done
    result_counters="${result_counters% }"

    _PROB_CMS_COUNTERS["$result_name"]="$result_counters"
    _PROB_CMS_METADATA["${result_name}_width"]="$w1"
    _PROB_CMS_METADATA["${result_name}_depth"]="$d1"

    printf '{"ok":true,"sketch":"%s","operation":"merge","source1":"%s","source2":"%s"}\n' \
        "$(_prob_json_escape "$result_name")" "$(_prob_json_escape "$name1")" "$(_prob_json_escape "$name2")"
}

# Serialize Count-Min Sketch to JSON
# @pre: sketch exists
# @post: JSON representation returned
# @idempotent: yes
# @returns: JSON string
#
# Usage: cms_to_json sketch_name
# Example: json=$(cms_to_json "frequency")
cms_to_json() {
    local name="$1"

    if [[ -z "${_PROB_CMS_COUNTERS[$name]+x}" ]]; then
        _prob_error 1 "sketch not found" "sketch=$name"
        return 1
    fi

    local width="${_PROB_CMS_METADATA[${name}_width]}"
    local depth="${_PROB_CMS_METADATA[${name}_depth]}"
    local counters="${_PROB_CMS_COUNTERS[$name]}"

    # Convert counters to JSON array
    local ctrs_json="["
    local first=true
    for ctr in $counters; do
        $first || ctrs_json+=","
        first=false
        ctrs_json+="$ctr"
    done
    ctrs_json+="]"

    printf '{"type":"count_min_sketch","name":"%s","width":%d,"depth":%d,"counters":%s}\n' \
        "$(_prob_json_escape "$name")" "$width" "$depth" "$ctrs_json"
}

# Deserialize Count-Min Sketch from JSON
# @pre: valid JSON with CMS data
# @post: sketch recreated
# @idempotent: no (overwrites existing sketch)
# @returns: 0 on success, 1 on error
#
# Usage: cms_from_json json_string
# Example: cms_from_json '{"type":"count_min_sketch",...}'
cms_from_json() {
    local json="$1"
    local name width depth

    if [[ "$json" =~ \"name\":\"([^\"]+)\" ]]; then
        name="${BASH_REMATCH[1]}"
    else
        _prob_error 1 "missing name in JSON"
        return 1
    fi

    if [[ "$json" =~ \"width\":([0-9]+) ]]; then
        width="${BASH_REMATCH[1]}"
    else
        _prob_error 1 "missing width in JSON"
        return 1
    fi

    if [[ "$json" =~ \"depth\":([0-9]+) ]]; then
        depth="${BASH_REMATCH[1]}"
    else
        _prob_error 1 "missing depth in JSON"
        return 1
    fi

    # Extract counters array
    local counters=""
    if [[ "$json" =~ \"counters\":\[([0-9,]+)\] ]]; then
        counters="${BASH_REMATCH[1]//,/ }"
    else
        _prob_error 1 "missing counters in JSON"
        return 1
    fi

    _PROB_CMS_COUNTERS["$name"]="$counters"
    _PROB_CMS_METADATA["${name}_width"]="$width"
    _PROB_CMS_METADATA["${name}_depth"]="$depth"

    printf '{"ok":true,"sketch":"%s","loaded":true}\n' "$(_prob_json_escape "$name")"
}

# =============================================================================
# MINHASH (Jaccard Similarity)
# =============================================================================
# MinHash is a technique for quickly estimating the Jaccard similarity between
# sets. It uses random hash functions to create compact signatures that can
# be compared much faster than comparing full sets.
# =============================================================================

declare -gA _PROB_MINHASH_SIGS=()
declare -gA _PROB_MINHASH_METADATA=()

# Create a new MinHash signature
# @pre: name is non-empty, num_hashes > 0
# @post: empty MinHash signature created
# @idempotent: no (recreates signature)
# @returns: 0 on success, 1 on error
#
# Usage: minhash_create name [num_hashes]
# Example: minhash_create "doc1" 128
minhash_create() {
    local name="$1"
    local num_hashes="${2:-$PROB_MINHASH_DEFAULT_SIZE}"

    if [[ -z "$name" ]]; then
        _prob_error 1 "signature name required"
        return 1
    fi

    if [[ ! "$num_hashes" =~ ^[0-9]+$ ]] || (( num_hashes <= 0 )); then
        _prob_error 1 "num_hashes must be positive integer" "num_hashes=$num_hashes"
        return 1
    fi

    # Initialize signature with max values
    local signature=""
    for ((i = 0; i < num_hashes; i++)); do
        signature+="4294967295 "  # UINT32_MAX
    done
    signature="${signature% }"

    _PROB_MINHASH_SIGS["$name"]="$signature"
    _PROB_MINHASH_METADATA["${name}_size"]="$num_hashes"

    printf '{"ok":true,"signature":"%s","type":"minhash","num_hashes":%d}\n' \
        "$(_prob_json_escape "$name")" "$num_hashes"
}

# Add element to MinHash signature
# @pre: signature exists, element is non-empty
# @post: signature updated with minimum hash values
# @idempotent: yes
# @returns: 0 on success, 1 on error
#
# Usage: minhash_add signature_name element
# Example: minhash_add "doc1" "word"
minhash_add() {
    local name="$1"
    local element="$2"

    if [[ -z "${_PROB_MINHASH_SIGS[$name]+x}" ]]; then
        _prob_error 1 "signature not found" "signature=$name"
        return 1
    fi

    if [[ -z "$element" ]]; then
        _prob_error 1 "element required"
        return 1
    fi

    local num_hashes="${_PROB_MINHASH_METADATA[${name}_size]}"
    local signature
    read -ra signature <<< "${_PROB_MINHASH_SIGS[$name]}"

    # Update each hash position with minimum value
    for ((i = 0; i < num_hashes; i++)); do
        local hash
        hash=$(prob_murmurhash "$element" "$i")

        if (( hash < signature[i] )); then
            signature[i]=$hash
        fi
    done

    _PROB_MINHASH_SIGS["$name"]="${signature[*]}"

    printf '{"ok":true,"signature":"%s","element":"%s","added":true}\n' \
        "$(_prob_json_escape "$name")" "$(_prob_json_escape "$element")"
}

# Get MinHash signature as array
# @pre: signature exists
# @post: signature array returned
# @idempotent: yes
# @returns: space-separated hash values
#
# Usage: minhash_signature signature_name
# Example: sig=$(minhash_signature "doc1")
minhash_signature() {
    local name="$1"

    if [[ -z "${_PROB_MINHASH_SIGS[$name]+x}" ]]; then
        _prob_error 1 "signature not found" "signature=$name"
        return 1
    fi

    local num_hashes="${_PROB_MINHASH_METADATA[${name}_size]}"
    local signature="${_PROB_MINHASH_SIGS[$name]}"

    # Convert to JSON array
    local sig_json="["
    local first=true
    for hash in $signature; do
        $first || sig_json+=","
        first=false
        sig_json+="$hash"
    done
    sig_json+="]"

    printf '{"ok":true,"signature":"%s","values":%s}\n' \
        "$(_prob_json_escape "$name")" "$sig_json"
}

# Estimate Jaccard similarity between two MinHash signatures
# @pre: both signatures exist with same size
# @post: similarity estimate returned (0.0-1.0)
# @idempotent: yes
# @returns: similarity as JSON
#
# Usage: minhash_similarity sig1 sig2
# Example: sim=$(minhash_similarity "doc1" "doc2")
minhash_similarity() {
    local name1="$1"
    local name2="$2"

    if [[ -z "${_PROB_MINHASH_SIGS[$name1]+x}" ]]; then
        _prob_error 1 "signature not found" "signature=$name1"
        return 1
    fi

    if [[ -z "${_PROB_MINHASH_SIGS[$name2]+x}" ]]; then
        _prob_error 1 "signature not found" "signature=$name2"
        return 1
    fi

    local size1="${_PROB_MINHASH_METADATA[${name1}_size]}"
    local size2="${_PROB_MINHASH_METADATA[${name2}_size]}"

    if (( size1 != size2 )); then
        _prob_error 1 "signatures must have same size" "size1=$size1" "size2=$size2"
        return 1
    fi

    local sig1 sig2
    read -ra sig1 <<< "${_PROB_MINHASH_SIGS[$name1]}"
    read -ra sig2 <<< "${_PROB_MINHASH_SIGS[$name2]}"

    # Count matching hash values
    local matches=0
    for ((i = 0; i < size1; i++)); do
        if (( sig1[i] == sig2[i] )); then
            ((matches++))
        fi
    done

    # Calculate similarity as fraction (0.0 to 1.0)
    local sim_x10000=$(( (matches * 10000) / size1 ))

    # Format similarity properly (handles 0.0 to 1.0)
    local sim_str
    if (( sim_x10000 == 10000 )); then
        sim_str="1.0"
    elif (( sim_x10000 == 0 )); then
        sim_str="0.0"
    else
        # Format as 0.XXXX
        printf -v sim_str "0.%04d" "$sim_x10000"
        # Trim trailing zeros but keep at least one decimal place
        sim_str="${sim_str%0}"
        sim_str="${sim_str%0}"
        sim_str="${sim_str%0}"
        # Ensure we don't trim the last digit after decimal
        [[ "$sim_str" == "0." ]] && sim_str="0.0"
    fi

    printf '{"ok":true,"signature1":"%s","signature2":"%s","similarity":%s,"matches":%d,"total":%d}\n' \
        "$(_prob_json_escape "$name1")" "$(_prob_json_escape "$name2")" \
        "$sim_str" "$matches" "$size1"
}

# Merge two MinHash signatures (for set union)
# @pre: both signatures exist with same size
# @post: new signature created with minimum values
# @idempotent: no (creates new signature)
# @returns: 0 on success, 1 on error
#
# Usage: minhash_merge result_name sig1 sig2
# Example: minhash_merge "merged" "doc1" "doc2"
minhash_merge() {
    local result_name="$1"
    local name1="$2"
    local name2="$3"

    if [[ -z "${_PROB_MINHASH_SIGS[$name1]+x}" ]]; then
        _prob_error 1 "signature not found" "signature=$name1"
        return 1
    fi

    if [[ -z "${_PROB_MINHASH_SIGS[$name2]+x}" ]]; then
        _prob_error 1 "signature not found" "signature=$name2"
        return 1
    fi

    local size1="${_PROB_MINHASH_METADATA[${name1}_size]}"
    local size2="${_PROB_MINHASH_METADATA[${name2}_size]}"

    if (( size1 != size2 )); then
        _prob_error 1 "signatures must have same size" "size1=$size1" "size2=$size2"
        return 1
    fi

    local sig1 sig2
    read -ra sig1 <<< "${_PROB_MINHASH_SIGS[$name1]}"
    read -ra sig2 <<< "${_PROB_MINHASH_SIGS[$name2]}"

    # Take minimum of each position
    local result_sig=""
    for ((i = 0; i < size1; i++)); do
        if (( sig1[i] < sig2[i] )); then
            result_sig+="${sig1[i]} "
        else
            result_sig+="${sig2[i]} "
        fi
    done
    result_sig="${result_sig% }"

    _PROB_MINHASH_SIGS["$result_name"]="$result_sig"
    _PROB_MINHASH_METADATA["${result_name}_size"]="$size1"

    printf '{"ok":true,"signature":"%s","operation":"merge","source1":"%s","source2":"%s"}\n' \
        "$(_prob_json_escape "$result_name")" "$(_prob_json_escape "$name1")" "$(_prob_json_escape "$name2")"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Calculate optimal Bloom filter size for given expected elements and FP rate
# @pre: n > 0, fp_rate in (0,1)
# @post: optimal size in bits returned
# @idempotent: yes
# @returns: optimal filter size
#
# Usage: prob_optimal_bloom_size expected_elements fp_rate_percent
# Example: size=$(prob_optimal_bloom_size 10000 1)  # 1% FP rate
prob_optimal_bloom_size() {
    local n="$1"
    local fp_percent="${2:-1}"

    if [[ ! "$n" =~ ^[0-9]+$ ]] || (( n <= 0 )); then
        _prob_error 1 "expected elements must be positive integer" "n=$n"
        return 1
    fi

    # m = -(n * ln(p)) / (ln(2)^2)
    # Approximation: m ~ n * -log2(p) * 1.44
    # For p=1%: -log2(0.01) ~ 6.64
    # For p=0.1%: -log2(0.001) ~ 9.97

    local log2_fp
    case $fp_percent in
        10)  log2_fp=332 ;;   # -log2(0.1) * 100 ~ 3.32
        5)   log2_fp=432 ;;   # -log2(0.05) * 100 ~ 4.32
        1)   log2_fp=664 ;;   # -log2(0.01) * 100 ~ 6.64
        "0.1"|0) log2_fp=997 ;;  # -log2(0.001) * 100 ~ 9.97
        *)   log2_fp=664 ;;   # Default to 1%
    esac

    # m = n * log2_fp * 1.44 / 100
    local m=$(( (n * log2_fp * 144) / 10000 ))

    printf '{"ok":true,"expected_elements":%d,"fp_rate_percent":%s,"optimal_size":%d}\n' \
        "$n" "$fp_percent" "$m"
}

# Calculate optimal hash count for Bloom filter
# @pre: m > 0, n > 0
# @post: optimal hash count returned
# @idempotent: yes
# @returns: optimal hash count
#
# Usage: prob_optimal_hash_count filter_size expected_elements
# Example: k=$(prob_optimal_hash_count 10000 1000)
prob_optimal_hash_count() {
    local m="$1"
    local n="$2"

    if [[ ! "$m" =~ ^[0-9]+$ ]] || (( m <= 0 )); then
        _prob_error 1 "filter size must be positive integer" "m=$m"
        return 1
    fi

    if [[ ! "$n" =~ ^[0-9]+$ ]] || (( n <= 0 )); then
        _prob_error 1 "expected elements must be positive integer" "n=$n"
        return 1
    fi

    # k = (m/n) * ln(2) ~ (m/n) * 0.693
    local k=$(( (m * 693) / (n * 1000) ))

    # Ensure at least 1 hash
    (( k < 1 )) && k=1

    # Cap at reasonable maximum
    (( k > 20 )) && k=20

    printf '{"ok":true,"filter_size":%d,"expected_elements":%d,"optimal_hash_count":%d}\n' \
        "$m" "$n" "$k"
}

# Delete a Bloom filter
# @pre: filter exists
# @post: filter removed from memory
# @idempotent: yes
# @returns: 0 on success
#
# Usage: bloom_delete filter_name
bloom_delete() {
    local name="$1"

    unset "_PROB_BLOOM_FILTERS[$name]"
    unset "_PROB_BLOOM_METADATA[${name}_size]"
    unset "_PROB_BLOOM_METADATA[${name}_hashes]"
    unset "_PROB_BLOOM_METADATA[${name}_count]"

    printf '{"ok":true,"filter":"%s","deleted":true}\n' "$(_prob_json_escape "$name")"
}

# Delete a Counting Bloom filter
# @pre: filter exists
# @post: filter removed from memory
# @idempotent: yes
# @returns: 0 on success
#
# Usage: cbloom_delete filter_name
cbloom_delete() {
    local name="$1"

    unset "_PROB_CBLOOM_FILTERS[$name]"
    unset "_PROB_CBLOOM_METADATA[${name}_size]"
    unset "_PROB_CBLOOM_METADATA[${name}_hashes]"
    unset "_PROB_CBLOOM_METADATA[${name}_count]"

    printf '{"ok":true,"filter":"%s","deleted":true}\n' "$(_prob_json_escape "$name")"
}

# Delete a HyperLogLog counter
# @pre: counter exists
# @post: counter removed from memory
# @idempotent: yes
# @returns: 0 on success
#
# Usage: hll_delete counter_name
hll_delete() {
    local name="$1"

    unset "_PROB_HLL_REGISTERS[$name]"
    unset "_PROB_HLL_METADATA[${name}_precision]"
    unset "_PROB_HLL_METADATA[${name}_m]"

    printf '{"ok":true,"counter":"%s","deleted":true}\n' "$(_prob_json_escape "$name")"
}

# Delete a Count-Min Sketch
# @pre: sketch exists
# @post: sketch removed from memory
# @idempotent: yes
# @returns: 0 on success
#
# Usage: cms_delete sketch_name
cms_delete() {
    local name="$1"

    unset "_PROB_CMS_COUNTERS[$name]"
    unset "_PROB_CMS_METADATA[${name}_width]"
    unset "_PROB_CMS_METADATA[${name}_depth]"

    printf '{"ok":true,"sketch":"%s","deleted":true}\n' "$(_prob_json_escape "$name")"
}

# Delete a MinHash signature
# @pre: signature exists
# @post: signature removed from memory
# @idempotent: yes
# @returns: 0 on success
#
# Usage: minhash_delete signature_name
minhash_delete() {
    local name="$1"

    unset "_PROB_MINHASH_SIGS[$name]"
    unset "_PROB_MINHASH_METADATA[${name}_size]"

    printf '{"ok":true,"signature":"%s","deleted":true}\n' "$(_prob_json_escape "$name")"
}

# List all probabilistic data structures
# @pre: none
# @post: JSON array of all structures returned
# @idempotent: yes
# @returns: JSON list
#
# Usage: prob_list
prob_list() {
    local output='{"ok":true,"structures":{'

    # Bloom filters
    output+='"bloom_filters":['
    local first=true
    for name in "${!_PROB_BLOOM_FILTERS[@]}"; do
        $first || output+=","
        first=false
        output+="\"$(_prob_json_escape "$name")\""
    done
    output+='],'

    # Counting Bloom filters
    output+='"counting_bloom_filters":['
    first=true
    for name in "${!_PROB_CBLOOM_FILTERS[@]}"; do
        $first || output+=","
        first=false
        output+="\"$(_prob_json_escape "$name")\""
    done
    output+='],'

    # HyperLogLog counters
    output+='"hyperloglog_counters":['
    first=true
    for name in "${!_PROB_HLL_REGISTERS[@]}"; do
        $first || output+=","
        first=false
        output+="\"$(_prob_json_escape "$name")\""
    done
    output+='],'

    # Count-Min Sketches
    output+='"count_min_sketches":['
    first=true
    for name in "${!_PROB_CMS_COUNTERS[@]}"; do
        $first || output+=","
        first=false
        output+="\"$(_prob_json_escape "$name")\""
    done
    output+='],'

    # MinHash signatures
    output+='"minhash_signatures":['
    first=true
    for name in "${!_PROB_MINHASH_SIGS[@]}"; do
        $first || output+=","
        first=false
        output+="\"$(_prob_json_escape "$name")\""
    done
    output+=']'

    output+='}}'
    printf '%s\n' "$output"
}

# Clear all probabilistic data structures
# @pre: none
# @post: all structures removed from memory
# @idempotent: yes
# @returns: 0
#
# Usage: prob_clear_all
prob_clear_all() {
    _PROB_BLOOM_FILTERS=()
    _PROB_BLOOM_METADATA=()
    _PROB_CBLOOM_FILTERS=()
    _PROB_CBLOOM_METADATA=()
    _PROB_HLL_REGISTERS=()
    _PROB_HLL_METADATA=()
    _PROB_CMS_COUNTERS=()
    _PROB_CMS_METADATA=()
    _PROB_MINHASH_SIGS=()
    _PROB_MINHASH_METADATA=()

    printf '{"ok":true,"cleared":true}\n'
}

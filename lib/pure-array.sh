#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/pure-array.sh - Pure Bash Array Operations
# =============================================================================
# Description: Array operations without external tools
# Source: Inspired by Pure Bash Bible
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_PURE_ARRAY_LOADED:-}" ]] && return 0
readonly _MAINFRAME_PURE_ARRAY_LOADED=1

# =============================================================================
# BASIC OPERATIONS
# =============================================================================

# Get array length
# Usage: array_length "${arr[@]}"
array_length() {
    printf '%d\n' "$#"
}

# Get first element
# Usage: array_first "${arr[@]}"
array_first() {
    printf '%s\n' "$1"
}

# Get last element
# Usage: array_last "${arr[@]}"
array_last() {
    printf '%s\n' "${@: -1}"
}

# Get element at index
# Usage: array_get 2 "${arr[@]}"
array_get() {
    local index="$1"
    shift
    local arr=("$@")
    printf '%s\n' "${arr[$index]}"
}

# Get slice of array
# Usage: array_slice 1 3 "${arr[@]}"  # Elements 1-3
array_slice() {
    local start="$1"
    local end="$2"
    shift 2
    local arr=("$@")
    printf '%s\n' "${arr[@]:$start:$((end - start + 1))}"
}

# =============================================================================
# SEARCH & CHECK
# =============================================================================

# Check if array contains element
# Usage: array_contains "needle" "${arr[@]}"
array_contains() {
    local needle="$1"
    shift
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

# Find index of element
# Usage: array_index_of "needle" "${arr[@]}"
array_index_of() {
    local needle="$1"
    shift
    local i=0
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && { printf '%d\n' "$i"; return 0; }
        ((i++))
    done
    printf '%d\n' "-1"
    return 0
}

# Count occurrences of element
# Usage: array_count "needle" "${arr[@]}"
array_count() {
    local needle="$1"
    shift
    local count=0
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && ((count++))
    done
    printf '%d\n' "$count"
}

# Check if array is empty
# Usage: array_empty "${arr[@]}"
array_empty() {
    [[ $# -eq 0 ]]
}

# =============================================================================
# TRANSFORMATION
# =============================================================================

# Reverse array
# Usage: array_reverse "${arr[@]}"
array_reverse() {
    local arr=("$@")
    local len=${#arr[@]}
    for ((i=len-1; i>=0; i--)); do
        printf '%s\n' "${arr[i]}"
    done
}

# Remove duplicates (preserves order)
# Usage: array_unique "${arr[@]}"
array_unique() {
    declare -A seen
    for item in "$@"; do
        if [[ -z "${seen[$item]:-}" ]]; then
            printf '%s\n' "$item"
            seen["$item"]=1
        fi
    done
}

# Sort array (lexicographic)
# Usage: array_sort "${arr[@]}"
array_sort() {
    local arr=("$@")
    local n=${#arr[@]}

    # Simple bubble sort in pure bash
    for ((i=0; i<n; i++)); do
        for ((j=0; j<n-i-1; j++)); do
            if [[ "${arr[j]}" > "${arr[j+1]}" ]]; then
                local tmp="${arr[j]}"
                arr[j]="${arr[j+1]}"
                arr[j+1]="$tmp"
            fi
        done
    done
    printf '%s\n' "${arr[@]}"
}

# Sort array numerically
# Usage: array_sort_num "${arr[@]}"
array_sort_num() {
    local arr=("$@")
    local n=${#arr[@]}

    for ((i=0; i<n; i++)); do
        for ((j=0; j<n-i-1; j++)); do
            if ((arr[j] > arr[j+1])); then
                local tmp="${arr[j]}"
                arr[j]="${arr[j+1]}"
                arr[j+1]="$tmp"
            fi
        done
    done
    printf '%s\n' "${arr[@]}"
}

# Shuffle array
# Usage: array_shuffle "${arr[@]}"
array_shuffle() {
    local arr=("$@")
    local n=${#arr[@]}

    for ((i=n-1; i>0; i--)); do
        local j=$((RANDOM % (i + 1)))
        local tmp="${arr[i]}"
        arr[i]="${arr[j]}"
        arr[j]="$tmp"
    done
    printf '%s\n' "${arr[@]}"
}

# =============================================================================
# SELECTION
# =============================================================================

# Get random element
# Usage: array_random "${arr[@]}"
array_random() {
    local arr=("$@")
    printf '%s\n' "${arr[RANDOM % $#]}"
}

# Get N random elements
# Usage: array_sample 3 "${arr[@]}"
array_sample() {
    local n="$1"
    shift
    local arr=("$@")
    local len=${#arr[@]}

    # Shuffle and take first N
    for ((i=len-1; i>0 && n>0; i--, n--)); do
        local j=$((RANDOM % (i + 1)))
        printf '%s\n' "${arr[j]}"
        arr[j]="${arr[i]}"
    done
}

# Filter array by pattern
# Usage: array_filter '*error*' "${arr[@]}"
array_filter() {
    local pattern="$1"
    shift
    for item in "$@"; do
        [[ "$item" == $pattern ]] && printf '%s\n' "$item"
    done
    return 0
}

# Reject array by pattern
# Usage: array_reject '*error*' "${arr[@]}"
array_reject() {
    local pattern="$1"
    shift
    for item in "$@"; do
        [[ "$item" != $pattern ]] && printf '%s\n' "$item"
    done
}

# =============================================================================
# MODIFICATION
# =============================================================================

# Append element
# Usage: array_push arr "new_element"
array_push() {
    local -n arr_ref="$1"
    shift
    arr_ref+=("$@")
}

# Prepend element
# Usage: array_unshift arr "new_element"
array_unshift() {
    local -n arr_ref="$1"
    shift
    arr_ref=("$@" "${arr_ref[@]}")
}

# Remove first element and return it
# Usage: array_shift arr
array_shift() {
    local -n arr_ref="$1"
    printf '%s\n' "${arr_ref[0]}"
    arr_ref=("${arr_ref[@]:1}")
}

# Remove last element and return it
# Usage: array_pop arr
array_pop() {
    local -n arr_ref="$1"
    local last_idx=$((${#arr_ref[@]} - 1))
    printf '%s\n' "${arr_ref[$last_idx]}"
    unset "arr_ref[$last_idx]"
}

# Remove element at index
# Usage: array_remove_at arr 2
array_remove_at() {
    local -n arr_ref="$1"
    local index="$2"
    unset "arr_ref[$index]"
    arr_ref=("${arr_ref[@]}")
}

# Remove all occurrences of element
# Usage: array_remove arr "element"
array_remove() {
    local -n arr_ref="$1"
    local needle="$2"
    local new_arr=()

    for item in "${arr_ref[@]}"; do
        [[ "$item" != "$needle" ]] && new_arr+=("$item")
    done
    arr_ref=("${new_arr[@]}")
}

# =============================================================================
# JOINING
# =============================================================================

# Join values with delimiter. This is the canonical implementation used by
# array_join after it resolves the supported calling convention.
_array_join_values() {
    local delim="$1"
    shift
    local first=true

    for item in "$@"; do
        if $first; then
            printf '%s' "$item"
            first=false
        else
            printf '%s%s' "$delim" "$item"
        fi
    done
    printf '\n'
}

# Join array values with a delimiter.
#
# Preferred usage passes the delimiter followed by values:
#   array_join "," "${arr[@]}"
#
# For backward compatibility with collection.sh, an array variable name may
# be passed first, followed by an optional delimiter:
#   array_join arr ","
array_join() {
    # The canonical broker contract is always delimiter-first. Its clean child
    # sets this internal marker so a delimiter that happens to name an array
    # cannot activate the legacy nameref overload or expose shell state.
    if [[ "${MAINFRAME_CANONICAL_INVOKE:-0}" != 1 ]] && (( $# > 0 )); then
        local declaration
        if declaration=$(declare -p "$1" 2>/dev/null) &&
            [[ "$declaration" =~ ^declare\ -[^[:space:]]*[aA][^[:space:]]*\  ]]; then
            local -n arr_ref="$1"
            local delim="${2:-,}"
            _array_join_values "$delim" "${arr_ref[@]}"
            return 0
        fi
    fi

    _array_join_values "$@"
}

# =============================================================================
# COMPARISON
# =============================================================================

# Check if two arrays are equal
# Usage: array_equals arr1 arr2
array_equals() {
    local -n a1="$1"
    local -n a2="$2"

    [[ ${#a1[@]} -ne ${#a2[@]} ]] && return 1

    for i in "${!a1[@]}"; do
        [[ "${a1[$i]}" != "${a2[$i]}" ]] && return 1
    done
    return 0
}

# Get intersection of two arrays
# Usage: array_intersect arr1 arr2
array_intersect() {
    local -n a1="$1"
    local -n a2="$2"
    declare -A seen

    for item in "${a2[@]}"; do
        seen["$item"]=1
    done

    for item in "${a1[@]}"; do
        [[ -n "${seen[$item]:-}" ]] && printf '%s\n' "$item"
    done
}

# Get difference (a1 - a2)
# Usage: array_diff arr1 arr2
array_diff() {
    local -n a1="$1"
    local -n a2="$2"
    declare -A seen

    for item in "${a2[@]}"; do
        seen["$item"]=1
    done

    for item in "${a1[@]}"; do
        [[ -z "${seen[$item]:-}" ]] && printf '%s\n' "$item"
    done
    return 0
}

# Get union of two arrays
# Usage: array_union arr1 arr2
array_union() {
    local -n a1="$1"
    local -n a2="$2"
    declare -A seen

    for item in "${a1[@]}" "${a2[@]}"; do
        if [[ -z "${seen[$item]:-}" ]]; then
            printf '%s\n' "$item"
            seen["$item"]=1
        fi
    done
}

# =============================================================================
# AGGREGATION
# =============================================================================

# Sum numeric array
# Usage: array_sum "${arr[@]}"
array_sum() {
    local sum=0
    for item in "$@"; do
        ((sum += item))
    done
    printf '%d\n' "$sum"
}

# Get min of numeric array
# Usage: array_min "${arr[@]}"
array_min() {
    local min="$1"
    shift
    for item in "$@"; do
        ((item < min)) && min="$item"
    done
    printf '%d\n' "$min"
}

# Get max of numeric array
# Usage: array_max "${arr[@]}"
array_max() {
    local max="$1"
    shift
    for item in "$@"; do
        ((item > max)) && max="$item"
    done
    printf '%d\n' "$max"
}

# Get average of numeric array
# Usage: array_avg "${arr[@]}"
array_avg() {
    local sum=0
    local count=$#
    for item in "$@"; do
        ((sum += item))
    done
    printf '%d\n' "$((sum / count))"
}
